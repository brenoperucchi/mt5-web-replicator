"""Admin API (6.3): accounts, enrollment codes, revoke, suspend/drain (PR 1, PR 5), admin/service tokens (PR 5).

The `*_op` functions hold the logic and are shared with the server-rendered admin UI (`routers.ui`)."""

from __future__ import annotations

from datetime import timedelta
from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..auth import authenticate_admin
from ..deps import engine_ctx, settings_of, uow
from ..engine.admin_ops import drain_copies
from ..errors import ApiError, json_response
from ..models import EXPOSURE_STATES, Account, ApiToken, Copy, CopyLink, EnrollCode, Event, utcnow
from ..security import hmac_hex, new_enroll_code, new_token, normalize_server

router = APIRouter(prefix="/admin")


class AccountIn(BaseModel):
    broker_server: str = Field(min_length=1, max_length=128)
    login: int = Field(gt=0)
    role: Literal["master", "slave"]
    label: str | None = Field(default=None, max_length=128)


class AccountPatch(BaseModel):
    status: Literal["active", "suspended"] | None = None
    suspended_reason: str | None = Field(default=None, max_length=255)
    label: str | None = Field(default=None, max_length=128)
    exclude_copier_positions: bool | None = None


def account_json(a: Account) -> dict:
    return {
        "id": a.id, "broker_server": a.broker_server, "login": a.login, "role": a.role,
        "margin_mode": a.margin_mode, "label": a.label, "status": a.status,
        "suspended_reason": a.suspended_reason, "ea_version": a.ea_version,
        "enrolled": a.token_hash is not None, "exclude_copier_positions": a.exclude_copier_positions,
        "last_seen_at": a.last_seen_at.isoformat() if a.last_seen_at else None,
    }


def get_account(s: Session, account_id: int) -> Account:
    acct = s.get(Account, account_id)
    if acct is None:
        raise ApiError(404, "not_found", "account not found")
    return acct


def create_account_op(s: Session, body: AccountIn) -> Account:
    norm = normalize_server(body.broker_server)
    dup = s.scalar(select(Account).where(Account.broker_server_norm == norm, Account.login == body.login,
                                         Account.role == body.role))
    if dup is not None:
        raise ApiError(409, "account_exists", "account already exists")
    acct = Account(broker_server=body.broker_server, broker_server_norm=norm, login=body.login,
                   role=body.role, label=body.label, margin_mode="unknown", status="active")
    s.add(acct)
    s.flush()
    return acct


@router.post("/accounts", status_code=201)
def create_account(body: AccountIn, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings)
        return json_response(account_json(create_account_op(s, body)), 201)

    return uow(request, work)


@router.get("/accounts")
def list_accounts(request: Request, role: str | None = None, status: str | None = None):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings, scope="readonly")
        q = select(Account).order_by(Account.id)
        if role is not None:
            q = q.where(Account.role == role)
        if status is not None:
            q = q.where(Account.status == status)
        return json_response({"accounts": [account_json(a) for a in s.scalars(q)]})

    return uow(request, work)


@router.get("/accounts/{account_id}")
def show_account(account_id: int, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings, scope="readonly")
        return json_response(account_json(get_account(s, account_id)))

    return uow(request, work)


def issue_code_op(s: Session, settings, acct: Account) -> dict:
    """One-time code bound to (server_norm, login, role); 15 min TTL; stored hashed (D8.1)."""
    code = new_enroll_code()
    expires = utcnow() + timedelta(seconds=settings.enroll_code_ttl_seconds)
    s.add(EnrollCode(account_id=acct.id, server_norm=acct.broker_server_norm, login=acct.login,
                     role=acct.role, code_hash=hmac_hex(settings.token_pepper, code), expires_at=expires))
    s.add(Event(type="account.enroll_code_issued", payload={"account_id": acct.id,
                                                            "expires_at": expires.isoformat()}))
    return {"code": code, "account_id": acct.id, "expires_at": expires.isoformat()}


@router.post("/accounts/{account_id}/enroll_codes", status_code=201)
def issue_enroll_code(account_id: int, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings)
        return json_response(issue_code_op(s, settings, get_account(s, account_id)), 201)

    return uow(request, work)


def revoke_op(s: Session, acct: Account, actor: str) -> Account:
    """Security revocation (6.2): 401 on every call; open copies listed in `account.revoked`."""
    acct.status = "revoked"
    acct.token_hash = acct.pending_token_hash = acct.pending_token_id = None
    acct.pending_token_issued_at = None
    q = select(Copy.id).where(Copy.state.in_(EXPOSURE_STATES))
    q = q.where(Copy.slave_id == acct.id) if acct.role == "slave" else q.join(
        CopyLink, Copy.link_id == CopyLink.id).where(CopyLink.master_id == acct.id)
    s.add(Event(type="account.revoked", payload={"account_id": acct.id, "open_copies": list(s.scalars(q)),
                                                 "actor": actor}))
    return acct


@router.post("/accounts/{account_id}/revoke")
def revoke(account_id: int, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        actor = authenticate_admin(s, request, settings)
        return json_response(account_json(revoke_op(s, get_account(s, account_id), actor)))

    return uow(request, work)


def patch_account_op(s: Session, acct: Account, body: AccountPatch, ctx, actor: str) -> dict:
    """Commercial suspension = drain (6.2, D11); `status: active` lifts it. Never revokes.

    Entering suspension applies the C6 transitions in the same transaction (`drain_copies`)."""
    if acct.status == "revoked" and body.status is not None:
        raise ApiError(409, "account_revoked", "revoked accounts must re-enroll")
    drained = None
    if body.status is not None and body.status != acct.status:
        acct.status = body.status
        acct.suspended_reason = body.suspended_reason if body.status == "suspended" else None
        s.add(Event(type=f"account.{'suspended' if body.status == 'suspended' else 'reactivated'}",
                    payload={"account_id": acct.id, "actor": actor, "reason": acct.suspended_reason}))
        if body.status == "suspended":
            s.flush()
            scope = {"slave_id": acct.id} if acct.role == "slave" else {"master_id": acct.id}
            drained = drain_copies(s, ctx, "account_drain", **scope)
    elif body.status == "suspended" and body.suspended_reason is not None:
        acct.suspended_reason = body.suspended_reason
    if body.label is not None:
        acct.label = body.label
    if body.exclude_copier_positions is not None:
        acct.exclude_copier_positions = body.exclude_copier_positions
    out = account_json(acct)
    if drained is not None:
        out["drain"] = drained
    return out


@router.patch("/accounts/{account_id}")
def patch_account(account_id: int, body: AccountPatch, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        actor = authenticate_admin(s, request, settings)
        return json_response(patch_account_op(s, get_account(s, account_id), body, engine_ctx(request), actor))

    return uow(request, work)


# --- admin / service tokens (6.3) -------------------------------------------------------------------

class ApiTokenIn(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    scopes: list[Literal["admin", "readonly"]] = Field(min_length=1)


def api_token_json(t: ApiToken) -> dict:
    return {"id": t.id, "name": t.name, "scopes": t.scopes, "created_at": t.created_at.isoformat(),
            "revoked_at": t.revoked_at.isoformat() if t.revoked_at else None}


def create_api_token_op(s: Session, settings, body: ApiTokenIn, actor: str) -> dict:
    """Scoped bearer for `/admin/*` (Rails service token, read-only dashboards). Shown once, stored as HMAC."""
    token = new_token()
    row = ApiToken(name=body.name, scopes=sorted(set(body.scopes)), token_hash=hmac_hex(settings.token_pepper, token))
    s.add(row)
    s.flush()
    s.add(Event(type="api_token.created", payload={"api_token_id": row.id, "name": row.name,
                                                   "scopes": row.scopes, "actor": actor}))
    return {**api_token_json(row), "token": token}


@router.post("/api_tokens", status_code=201)
def create_api_token(body: ApiTokenIn, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        actor = authenticate_admin(s, request, settings)
        # Token-bearing response: never cached or logged (D8.6).
        return json_response(create_api_token_op(s, settings, body, actor), 201, {"Cache-Control": "no-store"})

    return uow(request, work)


@router.get("/api_tokens")
def list_api_tokens(request: Request):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings)
        rows = s.scalars(select(ApiToken).order_by(ApiToken.id))
        return json_response({"api_tokens": [api_token_json(t) for t in rows]})

    return uow(request, work)


def revoke_api_token_op(s: Session, token_id: int, actor: str) -> ApiToken:
    row = s.get(ApiToken, token_id)
    if row is None:
        raise ApiError(404, "not_found", "api token not found")
    if row.revoked_at is None:
        row.revoked_at = utcnow()
        s.add(Event(type="api_token.revoked", payload={"api_token_id": row.id, "actor": actor}))
    return row


@router.post("/api_tokens/{token_id}/revoke")
def revoke_api_token(token_id: int, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        actor = authenticate_admin(s, request, settings)
        return json_response(api_token_json(revoke_api_token_op(s, token_id, actor)))

    return uow(request, work)
