"""Minimal server-rendered admin UI (design Q9): accounts, groups, links and per-link parameters,
symbol maps, enrollment codes, copy states with the 5.8 resolution actions, symbol conflicts,
events/alerts and the EA log viewer with filters. No SPA, no JavaScript, no extra dependency:
HTML is built with the standard library and every value is escaped.

Auth: the operator signs in with an admin bearer (`ADMIN_TOKEN` or an `api_tokens` row). The cookie
holds only a signed reference (`env` or the token id) + expiry, HttpOnly, SameSite=Strict, scoped
to `/ui`; it dies when the token is revoked or `ADMIN_TOKEN` changes. Every form carries a CSRF
token derived from the cookie. `readonly` tokens see everything and change nothing.

All mutations reuse the admin API's `*_op` functions and `engine.admin_ops`, in one unit of work.
"""

from __future__ import annotations

import hmac
import time
from decimal import Decimal, InvalidOperation
from html import escape
from typing import Any
from urllib.parse import parse_qs, urlencode

from fastapi import APIRouter, FastAPI, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import HTMLResponse, RedirectResponse
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..deps import engine_ctx, settings_of, uow
from ..engine.admin_ops import CopyResolution, attention, resolve_conflict, resolve_copy
from ..errors import ApiError
from ..models import (
    COPY_STATES,
    Account,
    ApiToken,
    Command,
    Copy,
    CopyGroup,
    CopyLink,
    EaLog,
    SymbolConflict,
    SymbolMap,
)
from ..security import hmac_hex
from .admin import (
    AccountIn,
    AccountPatch,
    ApiTokenIn,
    create_account_op,
    create_api_token_op,
    issue_code_op,
    patch_account_op,
    revoke_api_token_op,
    revoke_op,
)
from .admin_copy import (
    LINK_FIELDS,
    GroupIn,
    GroupPatch,
    LinkIn,
    LinkParams,
    MapIn,
    create_group_op,
    create_link_op,
    create_map_op,
    delete_map_op,
    patch_group_op,
    patch_link_op,
)
from .admin_ops import ALERT_TYPES, query_events

router = APIRouter(prefix="/ui", include_in_schema=False)
COOKIE = "cc_admin"
SESSION_SECONDS = 8 * 3600


class LoginRequired(Exception):
    pass


def install(app: FastAPI) -> None:
    app.include_router(router)

    @app.exception_handler(LoginRequired)
    async def _login(_req: Request, _exc: LoginRequired):
        return RedirectResponse("/ui/login", 303)


# --- auth ----------------------------------------------------------------------------------------------

class Actor:
    def __init__(self, name: str, scopes: list[str], cookie: str, pepper: str):
        self.name, self.scopes, self.cookie, self.pepper = name, scopes, cookie, pepper

    @property
    def admin(self) -> bool:
        return "admin" in self.scopes

    @property
    def csrf(self) -> str:
        return hmac_hex(self.pepper, "csrf|" + self.cookie)


def _marker(settings, s: Session, ref: str) -> tuple[str, list[str], str] | None:
    """(secret marker, scopes, actor name) for a cookie reference, None when no longer valid."""
    if ref == "env":
        if not settings.admin_token:
            return None
        return hmac_hex(settings.token_pepper, "admin|" + settings.admin_token), ["admin"], "env:ADMIN_TOKEN"
    if ref.startswith("t") and ref[1:].isdigit():
        row = s.get(ApiToken, int(ref[1:]))
        if row is not None and row.revoked_at is None:
            return row.token_hash, list(row.scopes or []), f"api_token:{row.id}"
    return None


def _sign(settings, ref: str, exp: int, marker: str) -> str:
    return hmac_hex(settings.token_pepper, f"ui|{ref}|{exp}|{marker}")


def actor_of(s: Session, request: Request) -> Actor:
    settings = settings_of(request)
    raw = request.cookies.get(COOKIE, "")
    ref, _, rest = raw.partition(".")
    exp_s, _, sig = rest.partition(".")
    if not exp_s.isdigit() or int(exp_s) < time.time():
        raise LoginRequired()
    found = _marker(settings, s, ref)
    if found is None or not hmac.compare_digest(sig, _sign(settings, ref, int(exp_s), found[0])):
        raise LoginRequired()
    return Actor(found[2], found[1], raw, settings.token_pepper)


async def form_of(request: Request) -> dict[str, str]:
    body = (await request.body()).decode("utf-8", "replace")
    return {k: v[0] for k, v in parse_qs(body, keep_blank_values=True).items()}


def _check_post(actor: Actor, form: dict[str, str]) -> None:
    if not hmac.compare_digest(form.get("csrf", ""), actor.csrf):
        raise ApiError(403, "csrf", "stale form: reload the page")
    if not actor.admin:
        raise ApiError(403, "forbidden", "read-only token")


def _back(url: str, msg: str | None = None, err: str | None = None) -> RedirectResponse:
    q = {k: v for k, v in (("msg", msg), ("err", err)) if v}
    sep = "&" if "?" in url else "?"
    return RedirectResponse(url + (sep + urlencode(q) if q else ""), 303)


async def mutate(request: Request, back: str, fn) -> Any:
    """POST helper: CSRF + admin scope, one unit of work, errors shown on the page (nothing applied)."""
    form = await form_of(request)

    def work(s: Session):
        actor = actor_of(s, request)
        _check_post(actor, form)
        return fn(s, actor, form)

    try:
        out = await run_in_threadpool(uow, request, work)
    except ApiError as exc:
        return _back(back, err=f"{exc.error}: {exc.message}")
    except ValidationError as exc:
        fields = ", ".join(".".join(str(p) for p in e["loc"]) or "form" for e in exc.errors())
        return _back(back, err=f"invalid input: {fields}")
    except ValueError as exc:
        return _back(back, err=f"invalid input: {exc}")
    return out if not isinstance(out, str) else _back(back, msg=out)


# --- HTML helpers -------------------------------------------------------------------------------------

CSS = """
:root{--bg:#fafafa;--fg:#1b1b1b;--muted:#666;--line:#ddd;--accent:#0b5cad;--bad:#a4161a;--ok:#2b7a0b;--card:#fff}
@media (prefers-color-scheme: dark){:root{--bg:#141414;--fg:#e8e8e8;--muted:#9a9a9a;--line:#333;
--accent:#6aa9ff;--bad:#ff7b7b;--ok:#8fd16a;--card:#1d1d1d}}
*{box-sizing:border-box}body{margin:0;font:14px/1.45 system-ui,sans-serif;background:var(--bg);color:var(--fg)}
header{display:flex;flex-wrap:wrap;gap:12px;align-items:center;padding:10px 16px;border-bottom:1px solid var(--line)}
header b{margin-right:8px}header a{color:var(--accent);text-decoration:none}main{padding:16px;max-width:1200px}
table{border-collapse:collapse;width:100%;margin:8px 0 16px;background:var(--card)}
th,td{border:1px solid var(--line);padding:4px 6px;text-align:left;vertical-align:top}
th{font-weight:600}td.wrap{white-space:pre-wrap;word-break:break-all;font-family:ui-monospace,monospace;font-size:12px}
.scroll{overflow-x:auto}.msg{color:var(--ok)}.err{color:var(--bad)}.muted{color:var(--muted)}
form.inline{display:inline}fieldset{border:1px solid var(--line);margin:8px 0 16px;background:var(--card)}
input,select,button{font:inherit;margin:2px 4px 2px 0}code.secret{font-size:18px;padding:4px 8px;border:1px dashed}
a{color:var(--accent)}
"""

NAV = (("Attention", "/ui/"), ("Accounts", "/ui/accounts"), ("Links", "/ui/links"), ("Symbol maps", "/ui/symbol_maps"),
       ("Copies", "/ui/copies"), ("Conflicts", "/ui/conflicts"), ("Events", "/ui/events"),
       ("Alerts", "/ui/events?alerts=1"), ("EA logs", "/ui/logs"), ("Tokens", "/ui/tokens"))


def e(v: Any) -> str:
    return "" if v is None else escape(str(v))


def page(request: Request, title: str, body: str, actor: Actor | None = None) -> HTMLResponse:
    nav = ""
    if actor is not None:
        links = " ".join(f'<a href="{href}">{e(name)}</a>' for name, href in NAV)
        nav = (f"<header><b>Copy Server</b>{links}<span class=muted>{e(actor.name)}"
               f"{'' if actor.admin else ' (read-only)'}</span>"
               f'<form class=inline method=post action="/ui/logout">{csrf(actor)}<button>Sign out</button></form>'
               "</header>")
    flash = ""
    if m := request.query_params.get("msg"):
        flash += f"<p class=msg>{e(m)}</p>"
    if m := request.query_params.get("err"):
        flash += f"<p class=err>{e(m)}</p>"
    html = (f"<!doctype html><html lang=en><head><meta charset=utf-8>"
            f"<meta name=viewport content='width=device-width,initial-scale=1'><title>{e(title)} · Copy Server</title>"
            f"<style>{CSS}</style></head><body>{nav}<main><h1>{e(title)}</h1>{flash}{body}</main></body></html>")
    return HTMLResponse(html, headers={"Cache-Control": "no-store", "X-Frame-Options": "DENY",
                                       "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; "
                                                                  "form-action 'self'; frame-ancestors 'none'"})


def csrf(actor: Actor) -> str:
    return f'<input type=hidden name=csrf value="{e(actor.csrf)}">'


def table(headers: list[str], rows: list[list[str]], empty: str = "none") -> str:
    if not rows:
        return f"<p class=muted>{e(empty)}</p>"
    head = "".join(f"<th>{e(h)}</th>" for h in headers)
    body = "".join("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>" for r in rows)
    return f"<div class=scroll><table><tr>{head}</tr>{body}</table></div>"


def form(actor: Actor, action: str, inner: str, button: str) -> str:
    if not actor.admin:
        return ""
    return (f'<form class=inline method=post action="{e(action)}">{csrf(actor)}{inner}'
            f"<button>{e(button)}</button></form>")


def field(name: str, label: str, value: Any = "", kind: str = "text", **attrs) -> str:
    extra = " ".join(f'{k}="{e(v)}"' for k, v in attrs.items())
    return f'<label>{e(label)} <input name="{e(name)}" type="{kind}" value="{e(value)}" {extra}></label>'


def select_(name: str, label: str, options: list[str], value: Any = None, blank: bool = False) -> str:
    opts = ("<option value=''></option>" if blank else "") + "".join(
        f"<option{' selected' if str(o) == str(value) else ''}>{e(o)}</option>" for o in options)
    return f'<label>{e(label)} <select name="{e(name)}">{opts}</select></label>'


def checkbox(name: str, label: str, checked: bool) -> str:
    return f'<label><input type=checkbox name="{e(name)}" value=1{" checked" if checked else ""}> {e(label)}</label>'


def a(href: str, text: Any) -> str:
    return f'<a href="{e(href)}">{e(text)}</a>'


def acct_label(acct: Account | None) -> str:
    if acct is None:
        return ""
    return a(f"/ui/accounts/{acct.id}", f"#{acct.id} {acct.role} {acct.login}@{acct.broker_server}"
             + (f" ({acct.label})" if acct.label else ""))


def ts(v) -> str:
    return e(v.isoformat(timespec="seconds")) if v is not None else ""


def opt_int(v: str | None) -> int | None:
    v = (v or "").strip()
    return int(v) if v else None


def opt_str(v: str | None) -> str | None:
    v = (v or "").strip()
    return v or None


def view(request: Request, render) -> HTMLResponse:
    """GET helper: authenticated read in one unit of work."""
    return uow(request, lambda s: render(s, actor_of(s, request)))


# --- login --------------------------------------------------------------------------------------------

@router.get("/login")
def login_form(request: Request):
    body = ("<form method=post action='/ui/login'><p>Admin or service bearer token.</p>"
            "<input type=password name=token autocomplete=off size=60 required> <button>Sign in</button></form>")
    return page(request, "Sign in", body)


@router.post("/login")
async def login(request: Request):
    settings = settings_of(request)
    token = (await form_of(request)).get("token", "").strip()

    def work(s: Session):
        if settings.admin_token and token and hmac.compare_digest(token.encode(), settings.admin_token.encode()):
            ref = "env"
        else:
            row = s.scalar(select(ApiToken).where(ApiToken.token_hash == hmac_hex(settings.token_pepper, token),
                                                  ApiToken.revoked_at.is_(None))) if token else None
            if row is None:
                return None
            ref = f"t{row.id}"
        exp = int(time.time()) + SESSION_SECONDS
        return f"{ref}.{exp}.{_sign(settings, ref, exp, _marker(settings, s, ref)[0])}"

    value = await run_in_threadpool(uow, request, work)
    if value is None:
        return _back("/ui/login", err="invalid token")
    resp = RedirectResponse("/ui/", 303)
    secure = request.url.scheme == "https" or request.headers.get("x-forwarded-proto") == "https"
    resp.set_cookie(COOKIE, value, max_age=SESSION_SECONDS, path="/ui", httponly=True, samesite="strict",
                    secure=secure)
    return resp


@router.post("/logout")
async def logout(request: Request):
    resp = RedirectResponse("/ui/login", 303)
    resp.delete_cookie(COOKIE, path="/ui")
    return resp


# --- attention (orphans) ---------------------------------------------------------------------------------

def copy_rows(s: Session, copies: list[Copy]) -> list[list[str]]:
    return [[a(f"/ui/copies/{c.id}", c.id), e(c.state), e(c.close_reason or c.skip_reason),
             acct_label(s.get(Account, c.slave_id)), e(c.symbol_local), e(c.volume), e(c.position_id),
             e("yes" if c.close_intent else ""), ts(c.created_at)] for c in copies]


COPY_HEAD = ["copy", "state", "reason", "slave", "symbol", "volume", "position", "close intent", "created"]


def conflict_rows(s: Session, rows: list[SymbolConflict], actor: Actor) -> list[list[str]]:
    out = []
    for c in rows:
        actions = "" if c.resolved_at else (
            form(actor, f"/ui/conflicts/{c.id}/resolve", "<input type=hidden name=resolution value=accept>"
                 + field("note", "note"), "Accept exposure") + " "
            + form(actor, f"/ui/conflicts/{c.id}/resolve", "<input type=hidden name=resolution value=close>",
                   "Close position"))
        out.append([e(c.id), e(c.kind), acct_label(s.get(Account, c.slave_id)), e(c.symbol_local),
                    a(f"/ui/copies/{c.copy_id}", c.copy_id) if c.copy_id else "", e(c.position_id), ts(c.opened_at),
                    e(c.resolution), actions])
    return out


CONFLICT_HEAD = ["id", "kind", "slave", "symbol", "copy", "position", "opened", "resolution", "actions"]


@router.get("/")
def home(request: Request):
    def render(s: Session, actor: Actor):
        att = attention(s)
        alerts = query_events(s, alerts=True, limit=20)
        body = ("<h2>Suspended copies (uncertain)</h2>" + table(COPY_HEAD, copy_rows(s, att["uncertain"]))
                + "<h2>Closes without evidence (close_unconfirmed)</h2>"
                + table(COPY_HEAD, copy_rows(s, att["close_unconfirmed"]))
                + "<h2>Exposure on revoked slaves</h2>" + table(COPY_HEAD, copy_rows(s, att["revoked_exposure"]))
                + "<h2>Open symbol conflicts</h2>" + table(CONFLICT_HEAD, conflict_rows(s, att["conflicts"], actor))
                + "<h2>Recent alerts</h2>" + event_table(alerts))
        return page(request, "Needs attention", body, actor)

    return view(request, render)


# --- accounts ------------------------------------------------------------------------------------------

@router.get("/accounts")
def accounts(request: Request):
    def render(s: Session, actor: Actor):
        rows = [[acct_label(x), e(x.role), e(x.margin_mode), e(x.status), e(x.suspended_reason), e(x.ea_version),
                 e("yes" if x.token_hash else "no"), ts(x.last_seen_at)]
                for x in s.scalars(select(Account).order_by(Account.id))]
        create = form(actor, "/ui/accounts", field("broker_server", "broker server", required="required")
                      + field("login", "login", kind="number", required="required")
                      + select_("role", "role", ["master", "slave"]) + field("label", "label"), "Create account")
        body = (table(["account", "role", "margin", "status", "reason", "EA", "enrolled", "last seen"], rows)
                + (f"<fieldset><legend>New account</legend>{create}</fieldset>" if create else ""))
        return page(request, "Accounts", body, actor)

    return view(request, render)


@router.post("/accounts")
async def accounts_create(request: Request):
    def fn(s: Session, actor: Actor, f: dict):
        acct = create_account_op(s, AccountIn(broker_server=f.get("broker_server", ""), login=int(f.get("login") or 0),
                                              role=f.get("role", ""), label=opt_str(f.get("label"))))
        return f"account #{acct.id} created"

    return await mutate(request, "/ui/accounts", fn)


def _account_body(s: Session, x: Account, actor: Actor, code: dict | None = None) -> str:
    info = table(["field", "value"], [[e(k), e(v)] for k, v in (
        ("broker server", x.broker_server), ("login", x.login), ("role", x.role), ("margin mode", x.margin_mode),
        ("status", x.status), ("suspended reason", x.suspended_reason), ("EA version", x.ea_version),
        ("enrolled", "yes" if x.token_hash else "no"), ("session", x.session_id), ("last seen", x.last_seen_at),
        ("exclude copier positions", x.exclude_copier_positions))])
    out = info
    if code:
        out += (f"<fieldset><legend>Enrollment code (shown once)</legend><code class=secret>{e(code['code'])}</code>"
                f"<p class=muted>Valid until {e(code['expires_at'])}; bound to this server, login and role.</p>"
                "</fieldset>")
    base = f"/ui/accounts/{x.id}"
    actions = form(actor, f"{base}/enroll_code", "", "Issue enrollment code")
    if x.status == "active":
        actions += " " + form(actor, f"{base}/status", "<input type=hidden name=status value=suspended>"
                              + field("suspended_reason", "reason"), "Suspend (drain)")
    elif x.status == "suspended":
        actions += " " + form(actor, f"{base}/status", "<input type=hidden name=status value=active>", "Reactivate")
    if x.status != "revoked":
        actions += " " + form(actor, f"{base}/revoke", checkbox("confirm", "confirm revocation", False),
                              "Revoke token")
    if actions:
        out += f"<fieldset><legend>Actions</legend>{actions}</fieldset>"
    if x.role == "master":
        groups = list(s.scalars(select(CopyGroup).where(CopyGroup.master_id == x.id).order_by(CopyGroup.id)))
        grows = [[e(g.id), e(g.name), e("enabled" if g.enabled else "disabled"), e(g.magic_allow), e(g.symbol_filter),
                  form(actor, f"/ui/groups/{g.id}", f"<input type=hidden name=enabled value={0 if g.enabled else 1}>"
                       f"<input type=hidden name=back value={base}>", "Disable" if g.enabled else "Enable")]
                 for g in groups]
        out += "<h2>Groups</h2>" + table(["id", "name", "state", "magic allow", "symbol filter", ""], grows)
        out += form(actor, "/ui/groups", f"<input type=hidden name=master_id value={x.id}>"
                    + field("name", "name", required="required") + field("magic_allow", "magic allow (comma list)")
                    + field("symbol_filter", "symbol filter (comma list)"), "Create group")
    links = list(s.scalars(select(CopyLink).where((CopyLink.master_id == x.id) | (CopyLink.slave_id == x.id))
                           .order_by(CopyLink.id)))
    out += "<h2>Links</h2>" + link_table(s, links)
    out += f"<p>{a(f'/ui/copies?slave_id={x.id}', 'Copies of this slave')} · " \
           f"{a(f'/ui/events?account_id={x.id}', 'Events')} · {a(f'/ui/logs?account_id={x.id}', 'EA logs')}</p>"
    return out


@router.get("/accounts/{account_id}")
def account_page(account_id: int, request: Request):
    def render(s: Session, actor: Actor):
        x = s.get(Account, account_id)
        if x is None:
            return page(request, "Not found", "<p>account not found</p>", actor)
        return page(request, f"Account #{x.id}", _account_body(s, x, actor), actor)

    return view(request, render)


@router.post("/accounts/{account_id}/enroll_code")
async def account_code(account_id: int, request: Request):
    form_data = await form_of(request)
    settings = settings_of(request)

    def work(s: Session):
        actor = actor_of(s, request)
        _check_post(actor, form_data)
        x = s.get(Account, account_id)
        if x is None:
            raise ApiError(404, "not_found", "account not found")
        code = issue_code_op(s, settings, x)
        return page(request, f"Account #{x.id}", _account_body(s, x, actor, code), actor)

    try:
        return await run_in_threadpool(uow, request, work)
    except ApiError as exc:
        return _back(f"/ui/accounts/{account_id}", err=f"{exc.error}: {exc.message}")


@router.post("/accounts/{account_id}/status")
async def account_status(account_id: int, request: Request):
    def fn(s: Session, actor: Actor, f: dict):
        x = s.get(Account, account_id)
        if x is None:
            raise ApiError(404, "not_found", "account not found")
        out = patch_account_op(s, x, AccountPatch(status=f.get("status"),
                                                  suspended_reason=opt_str(f.get("suspended_reason"))),
                               engine_ctx(request), actor.name)
        drain = out.get("drain")
        return f"status: {x.status}" + (f"; drain {drain}" if drain else "")

    return await mutate(request, f"/ui/accounts/{account_id}", fn)


@router.post("/accounts/{account_id}/revoke")
async def account_revoke(account_id: int, request: Request):
    def fn(s: Session, actor: Actor, f: dict):
        if f.get("confirm") != "1":
            raise ApiError(422, "confirm", "tick the confirmation box to revoke")
        x = s.get(Account, account_id)
        if x is None:
            raise ApiError(404, "not_found", "account not found")
        revoke_op(s, x, actor.name)
        return "token revoked: issue a new enrollment code to re-enroll"

    return await mutate(request, f"/ui/accounts/{account_id}", fn)


def _csv_ints(v: str | None) -> list[int] | None:
    parts = [p.strip() for p in (v or "").split(",") if p.strip()]
    return [int(p) for p in parts] or None


def _csv(v: str | None) -> list[str] | None:
    return [p.strip() for p in (v or "").split(",") if p.strip()] or None


@router.post("/groups")
async def group_create(request: Request):
    def fn(s: Session, actor: Actor, f: dict):
        g = create_group_op(s, GroupIn(master_id=int(f.get("master_id") or 0), name=f.get("name", ""),
                                       magic_allow=_csv_ints(f.get("magic_allow")),
                                       symbol_filter=_csv(f.get("symbol_filter"))))
        return f"group #{g.id} created"

    master_id = opt_int((await _peek(request)).get("master_id")) if \
        (await _peek(request)).get("master_id", "").strip().isdigit() else None
    return await mutate(request, f"/ui/accounts/{master_id}" if master_id else "/ui/accounts", fn)


@router.post("/groups/{group_id}")
async def group_toggle(group_id: int, request: Request):
    def fn(s: Session, actor: Actor, f: dict):
        g, drained = patch_group_op(s, group_id, GroupPatch(enabled=f.get("enabled") == "1"), engine_ctx(request))
        return f"group #{g.id} {'enabled' if g.enabled else 'disabled'}" + (f"; drain {drained}" if drained else "")

    form_data = await _peek(request)
    return await mutate(request, form_data.get("back") if (form_data.get("back") or "").startswith("/ui/")
                        else "/ui/accounts", fn)


async def _peek(request: Request) -> dict[str, str]:
    return await form_of(request)  # Starlette caches the body: `mutate` can read it again


# --- links ------------------------------------------------------------------------------------------------

def link_table(s: Session, links: list[CopyLink]) -> str:
    rows = [[a(f"/ui/links/{lk.id}", lk.id), e(s.get(CopyGroup, lk.group_id).name if lk.group_id else ""),
             acct_label(s.get(Account, lk.master_id)), acct_label(s.get(Account, lk.slave_id)),
             e("enabled" if lk.enabled else f"disabled {lk.disabled_reason or ''}"),
             e(f"{lk.lot_mode} {lk.lot_value or ''}"), e(f"{lk.magic_mode} {lk.magic_value or ''}"),
             e(lk.max_entry_deviation_points), e("yes" if lk.copy_sl_tp else "no")] for lk in links]
    return table(["link", "group", "master", "slave", "state", "lot", "magic", "max entry dev.", "SL/TP"], rows)


def _link_inputs(lk: CopyLink | None) -> str:
    def g(f: str, d: Any = None) -> Any:
        return getattr(lk, f) if lk is not None else d

    return (checkbox("enabled", "enabled", g("enabled", True))
            + select_("lot_mode", "lot mode", ["master", "multiplier", "fixed", "min_lot_x"], g("lot_mode", "master"))
            + field("lot_value", "lot value (multiplier / fixed lot)", g("lot_value") or "")
            + select_("below_min", "below min", ["skip", "open_min"], g("below_min", "skip"))
            + checkbox("allow_contract_size_diff", "allow contract size diff", g("allow_contract_size_diff", False))
            + select_("magic_mode", "magic", ["same", "fixed"], g("magic_mode", "same"))
            + field("magic_value", "fixed magic", g("magic_value") or "")
            + field("max_slippage_points", "max slippage (points)", g("max_slippage_points") or "")
            + field("max_entry_deviation_points", "max entry deviation (points)",
                    g("max_entry_deviation_points") or "")
            + checkbox("copy_sl_tp", "copy SL/TP", g("copy_sl_tp", True)))


def _link_params(f: dict) -> dict:
    out: dict[str, Any] = {}
    for name in LINK_FIELDS:
        if name in ("enabled", "allow_contract_size_diff", "copy_sl_tp"):
            out[name] = f.get(name) == "1"
        elif name in ("lot_mode", "below_min", "magic_mode"):
            out[name] = f.get(name) or None
        elif name == "lot_value":
            out[name] = opt_str(f.get(name))
        else:
            out[name] = opt_int(f.get(name))
    return out


@router.get("/links")
def links(request: Request):
    def render(s: Session, actor: Actor):
        all_links = list(s.scalars(select(CopyLink).order_by(CopyLink.id)))
        groups = list(s.scalars(select(CopyGroup).order_by(CopyGroup.id)))
        slaves = list(s.scalars(select(Account).where(Account.role == "slave").order_by(Account.id)))
        create = ""
        if groups and slaves:
            create = form(actor, "/ui/links",
                          "<label>group <select name=group_id>" + "".join(
                              f"<option value={g.id}>#{g.id} {e(g.name)} (master #{g.master_id})</option>"
                              for g in groups) + "</select></label>"
                          + "<label>slave <select name=slave_id>" + "".join(
                              f"<option value={x.id}>#{x.id} {e(x.login)}@{e(x.broker_server)}</option>"
                              for x in slaves) + "</select></label><br>" + _link_inputs(None), "Create link")
        body = link_table(s, all_links) + (f"<fieldset><legend>New link</legend>{create}</fieldset>" if create else
                                           "<p class=muted>Create a group (on a master account page) and a slave "
                                           "account to add links.</p>")
        return page(request, "Links", body, actor)

    return view(request, render)


@router.post("/links")
async def link_create(request: Request):
    def fn(s: Session, actor: Actor, f: dict):
        lk = create_link_op(s, LinkIn(group_id=int(f.get("group_id") or 0), slave_id=int(f.get("slave_id") or 0),
                                      **_link_params(f)))
        return f"link #{lk.id} created"

    return await mutate(request, "/ui/links", fn)


@router.get("/links/{link_id}")
def link_page(link_id: int, request: Request):
    def render(s: Session, actor: Actor):
        lk = s.get(CopyLink, link_id)
        if lk is None:
            return page(request, "Not found", "<p>link not found</p>", actor)
        maps = list(s.scalars(select(SymbolMap).where((SymbolMap.slave_id == lk.slave_id)
                                                      | SymbolMap.slave_id.is_(None)).order_by(SymbolMap.id)))
        body = (link_table(s, [lk])
                + (f"<fieldset><legend>Parameters (new copies only; existing copies keep their frozen "
                   f"parameters)</legend>{form(actor, f'/ui/links/{lk.id}', _link_inputs(lk), 'Save')}</fieldset>"
                   if actor.admin else "")
                + "<h2>Symbol maps for this slave</h2>"
                + table(["id", "scope", "master symbol", "slave symbol"],
                        [[e(m.id), e("slave" if m.slave_id else "global"), e(m.master_symbol), e(m.slave_symbol)]
                         for m in maps])
                + f"<p>{a('/ui/symbol_maps', 'Edit symbol maps')} · {a(f'/ui/copies?link_id={lk.id}', 'Copies')}</p>")
        return page(request, f"Link #{lk.id}", body, actor)

    return view(request, render)


@router.post("/links/{link_id}")
async def link_save(link_id: int, request: Request):
    def fn(s: Session, actor: Actor, f: dict):
        lk, drained = patch_link_op(s, link_id, LinkParams(**_link_params(f)), engine_ctx(request))
        return "saved" + (f"; drain {drained}" if drained else "")

    return await mutate(request, f"/ui/links/{link_id}", fn)


# --- symbol maps -------------------------------------------------------------------------------------------

@router.get("/symbol_maps")
def maps(request: Request):
    def render(s: Session, actor: Actor):
        rows = [[e(m.id), acct_label(s.get(Account, m.slave_id)) if m.slave_id else "global", e(m.master_symbol),
                 e(m.slave_symbol), form(actor, f"/ui/symbol_maps/{m.id}/delete", "", "Delete")]
                for m in s.scalars(select(SymbolMap).order_by(SymbolMap.id))]
        slaves = list(s.scalars(select(Account).where(Account.role == "slave").order_by(Account.id)))
        create = form(actor, "/ui/symbol_maps", "<label>slave <select name=slave_id><option value=''>global</option>"
                      + "".join(f"<option value={x.id}>#{x.id} {e(x.login)}@{e(x.broker_server)}</option>"
                                for x in slaves) + "</select></label>"
                      + field("master_symbol", "master symbol", required="required")
                      + field("slave_symbol", "slave symbol", required="required"), "Add map")
        body = (table(["id", "scope", "master symbol", "slave symbol", ""], rows)
                + (f"<fieldset><legend>New map</legend>{create}</fieldset>" if create else ""))
        return page(request, "Symbol maps", body, actor)

    return view(request, render)


@router.post("/symbol_maps")
async def map_create(request: Request):
    def fn(s: Session, actor: Actor, f: dict):
        m = create_map_op(s, MapIn(slave_id=opt_int(f.get("slave_id")),
                                   master_symbol=f.get("master_symbol", "").strip(),
                                   slave_symbol=f.get("slave_symbol", "").strip()))
        return f"map #{m.id} created"

    return await mutate(request, "/ui/symbol_maps", fn)


@router.post("/symbol_maps/{map_id}/delete")
async def map_delete(map_id: int, request: Request):
    def fn(s: Session, actor: Actor, f: dict):
        delete_map_op(s, map_id)
        return f"map #{map_id} deleted"

    return await mutate(request, "/ui/symbol_maps", fn)


# --- copies -------------------------------------------------------------------------------------------------

@router.get("/copies")
def copies(request: Request, state: str | None = None, slave_id: str | None = None, link_id: str | None = None):
    def render(s: Session, actor: Actor):
        q = select(Copy).order_by(Copy.id.desc()).limit(300)
        if state:
            q = q.where(Copy.state == state)
        if opt_int(slave_id) is not None:
            q = q.where(Copy.slave_id == int(slave_id))
        if opt_int(link_id) is not None:
            q = q.where(Copy.link_id == int(link_id))
        filters = ("<form method=get action='/ui/copies'>" + select_("state", "state", list(COPY_STATES), state, True)
                   + field("slave_id", "slave id", slave_id or "") + field("link_id", "link id", link_id or "")
                   + "<button>Filter</button></form>")
        return page(request, "Copies", filters + table(COPY_HEAD, copy_rows(s, list(s.scalars(q)))), actor)

    return view(request, render)


@router.get("/copies/{copy_id}")
def copy_page(copy_id: int, request: Request):
    def render(s: Session, actor: Actor):
        c = s.get(Copy, copy_id)
        if c is None:
            return page(request, "Not found", "<p>copy not found</p>", actor)
        info = table(["field", "value"], [[e(k), e(getattr(c, k))] for k in (
            "state", "close_reason", "skip_reason", "close_intent", "link_id", "master_position_id", "slave_id",
            "symbol_master", "symbol_local", "volume", "confirmed_volume", "reduction_target", "position_id",
            "position_ticket", "open_order", "open_deal", "close_deal", "price_open", "price_close", "profit",
            "blocked_by", "exec_params", "opened_at", "closed_at")])
        cmd_rows = [[e(x.seq_in_copy), e(x.action), e(x.state), e(x.id), e(x.attempt_id), e(x.attempts),
                     ts(x.issued_at), f"<span class=wrap>{e(x.result)}</span>"]
                    for x in s.scalars(select(Command).where(Command.copy_id == c.id).order_by(Command.seq_in_copy))]
        resolve_form = form(actor, f"/ui/copies/{c.id}/resolve",
                            select_("resolution", "resolution", ["executed", "not_executed", "closed", "retry_close"])
                            + field("position_id", "position id (executed open)")
                            + field("volume", "volume (open fill / residual after close_partial)")
                            + field("price", "price") + field("note", "note (audited)"), "Resolve")
        help_ = ("<p class=muted><b>executed</b> / <b>not_executed</b> settle a suspended (uncertain) attempt and "
                 "send a <code>resolve</code> to the EA journal; <b>closed</b> settles a close without evidence "
                 "or exposure on a revoked slave; <b>retry_close</b> re-issues a close answered "
                 "position_not_found. Every action is audited.</p>")
        body = (info + "<h2>Commands</h2>"
                + table(["seq", "action", "state", "command", "attempt", "attempts", "issued", "result"], cmd_rows)
                + (f"<fieldset><legend>Operator resolution (5.8)</legend>{help_}{resolve_form}</fieldset>"
                   if actor.admin else "")
                + "<h2>Events</h2>" + event_table(query_events(s, copy_id=c.id, limit=100)))
        return page(request, f"Copy #{c.id}", body, actor)

    return view(request, render)


@router.post("/copies/{copy_id}/resolve")
async def copy_resolve(copy_id: int, request: Request):
    def fn(s: Session, actor: Actor, f: dict):
        c = s.get(Copy, copy_id)
        if c is None:
            raise ApiError(404, "not_found", "copy not found")
        vol, price = opt_str(f.get("volume")), opt_str(f.get("price"))
        try:
            r = CopyResolution(resolution=f.get("resolution", ""), position_id=opt_int(f.get("position_id")),
                               volume=Decimal(vol) if vol else None, price=Decimal(price) if price else None,
                               note=opt_str(f.get("note")))
        except InvalidOperation as exc:
            raise ApiError(422, "validation", "volume/price must be numbers") from exc
        out = resolve_copy(s, c, engine_ctx(request), r, actor.name)
        return f"resolved: {out['outcome']} (state {out['state']})"

    return await mutate(request, f"/ui/copies/{copy_id}", fn)


# --- conflicts ---------------------------------------------------------------------------------------------

@router.get("/conflicts")
def conflicts(request: Request, show: str | None = None):
    def render(s: Session, actor: Actor):
        q = select(SymbolConflict).order_by(SymbolConflict.id.desc()).limit(300)
        if show != "all":
            q = q.where(SymbolConflict.resolved_at.is_(None))
        body = (f"<p>{a('/ui/conflicts', 'Open')} · {a('/ui/conflicts?show=all', 'All')}</p>"
                "<p class=muted><b>Accept</b> leaves the exposure as it is and lifts the block on new opens; "
                "<b>Close position</b> closes it by its position id, and the conflict ends when the close "
                "is confirmed.</p>"
                + table(CONFLICT_HEAD, conflict_rows(s, list(s.scalars(q)), actor)))
        return page(request, "Symbol conflicts", body, actor)

    return view(request, render)


@router.post("/conflicts/{conflict_id}/resolve")
async def conflict_resolve(conflict_id: int, request: Request):
    def fn(s: Session, actor: Actor, f: dict):
        row = s.get(SymbolConflict, conflict_id)
        if row is None:
            raise ApiError(404, "not_found", "symbol conflict not found")
        out = resolve_conflict(s, row, engine_ctx(request), f.get("resolution", ""), opt_str(f.get("note")),
                               actor.name)
        return "resolved" if out["resolved"] else f"close requested ({out['close_command_id']})"

    return await mutate(request, "/ui/conflicts", fn)


# --- events / logs ------------------------------------------------------------------------------------------

def event_table(rows) -> str:
    return table(["id", "time", "type", "payload"],
                 [[e(x.id), ts(x.created_at), e(x.type), f"<span class=wrap>{e(x.payload)}</span>"] for x in rows])


@router.get("/events")
def events(request: Request, type: str | None = None, prefix: str | None = None, alerts: str | None = None,
           copy_id: str | None = None, account_id: str | None = None, before_id: str | None = None):
    def render(s: Session, actor: Actor):
        rows = query_events(s, type=opt_str(type), prefix=opt_str(prefix), alerts=bool(alerts),
                            copy_id=opt_int(copy_id), account_id=opt_int(account_id), before_id=opt_int(before_id),
                            limit=200)
        filters = ("<form method=get action='/ui/events'>" + field("type", "type", type or "")
                   + field("prefix", "type prefix", prefix or "") + field("copy_id", "copy id", copy_id or "")
                   + field("account_id", "account id", account_id or "") + checkbox("alerts", "alerts only",
                                                                                   bool(alerts))
                   + "<button>Filter</button></form>"
                   f"<p class=muted>Alert types: {e(', '.join(ALERT_TYPES))}</p>")
        more = ""
        if len(rows) == 200:
            params = {k: v for k, v in (("type", type), ("prefix", prefix), ("alerts", alerts), ("copy_id", copy_id),
                                        ("account_id", account_id)) if v}
            more = a("/ui/events?" + urlencode({**params, "before_id": rows[-1].id}), "Older")
        return page(request, "Alerts" if alerts else "Events", filters + event_table(rows) + more, actor)

    return view(request, render)


@router.get("/logs")
def logs(request: Request, account_id: str | None = None, before_id: str | None = None):
    def render(s: Session, actor: Actor):
        q = select(EaLog).order_by(EaLog.id.desc()).limit(100)
        if opt_int(account_id) is not None:
            q = q.where(EaLog.account_id == int(account_id))
        if opt_int(before_id) is not None:
            q = q.where(EaLog.id < int(before_id))
        rows = [[e(x.id), ts(x.received_at), acct_label(s.get(Account, x.account_id)), e(x.size_bytes),
                 f"<span class=wrap>{e(x.content)}</span>"] for x in s.scalars(q)]
        filters = ("<form method=get action='/ui/logs'>" + field("account_id", "account id", account_id or "")
                   + "<button>Filter</button></form>")
        return page(request, "EA logs", filters + table(["id", "received", "account", "bytes", "content"], rows,
                                                         "no EA log uploads"), actor)

    return view(request, render)


# --- tokens ---------------------------------------------------------------------------------------------------

def _tokens_body(s: Session, actor: Actor, created: dict | None = None) -> str:
    rows = [[e(t.id), e(t.name), e(", ".join(t.scopes or [])), ts(t.created_at), ts(t.revoked_at),
             "" if t.revoked_at else form(actor, f"/ui/tokens/{t.id}/revoke", "", "Revoke")]
            for t in s.scalars(select(ApiToken).order_by(ApiToken.id))]
    out = ""
    if created:
        out += (f"<fieldset><legend>New token (shown once)</legend><code class=secret>{e(created['token'])}</code>"
                "</fieldset>")
    out += table(["id", "name", "scopes", "created", "revoked", ""], rows)
    out += form(actor, "/ui/tokens", field("name", "name", required="required")
                + select_("scope", "scope", ["readonly", "admin"]), "Create token")
    return out


@router.get("/tokens")
def tokens(request: Request):
    def render(s: Session, actor: Actor):
        if not actor.admin:
            return page(request, "Tokens", "<p class=muted>admin scope required</p>", actor)
        return page(request, "Admin and service tokens", _tokens_body(s, actor), actor)

    return view(request, render)


@router.post("/tokens")
async def token_create(request: Request):
    form_data = await form_of(request)
    settings = settings_of(request)

    def work(s: Session):
        actor = actor_of(s, request)
        _check_post(actor, form_data)
        created = create_api_token_op(s, settings, ApiTokenIn(name=form_data.get("name", ""),
                                                              scopes=[form_data.get("scope", "readonly")]),
                                      actor.name)
        return page(request, "Admin and service tokens", _tokens_body(s, actor, created), actor)

    try:
        return await run_in_threadpool(uow, request, work)
    except (ApiError, ValidationError) as exc:
        return _back("/ui/tokens", err=getattr(exc, "message", None) or "invalid input")


@router.post("/tokens/{token_id}/revoke")
async def token_revoke(token_id: int, request: Request):
    def fn(s: Session, actor: Actor, f: dict):
        revoke_api_token_op(s, token_id, actor.name)
        return f"token #{token_id} revoked"

    return await mutate(request, "/ui/tokens", fn)
