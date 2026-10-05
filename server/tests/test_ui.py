"""Minimal server-rendered admin (design Q9): sign-in, CSRF, read-only scope, and the operator flows
(accounts, enrollment code, links, maps, copies + resolution, conflicts, events, logs, tokens)."""

from __future__ import annotations

import re

from sqlalchemy import select

from copycore.models import SymbolConflict

from .conftest import ADMIN, admin_headers
from .copyhelpers import pos
from .test_admin_ops import uncertain_open
from .test_reconcile import spos
from .test_results import copy_of, opened, setup


def login(client, token=ADMIN):
    r = client.post("/ui/login", data={"token": token}, follow_redirects=False)
    assert r.status_code == 303 and r.headers["location"] == "/ui/", r.text
    return r


def csrf(client, path) -> str:
    html = client.get(path).text
    return re.search(r'name=csrf value="([0-9a-f]+)"', html).group(1)


def post(client, path, data, page=None):
    data = {**data, "csrf": csrf(client, page or path.rsplit("/", 1)[0] or "/ui/")}
    return client.post(path, data=data, follow_redirects=True)


def test_login_required_and_cookie_flags(client):
    r = client.get("/ui/", follow_redirects=False)
    assert r.status_code == 303 and r.headers["location"] == "/ui/login"
    r = client.post("/ui/login", data={"token": "wrong"}, follow_redirects=False)
    assert r.status_code == 303 and "err=" in r.headers["location"]
    cookie = login(client).headers["set-cookie"]
    assert "HttpOnly" in cookie and "SameSite=strict" in cookie and "Path=/ui" in cookie
    assert ADMIN not in cookie  # only a signed reference is stored
    page = client.get("/ui/")
    assert page.status_code == 200 and "Needs attention" in page.text
    assert page.headers["cache-control"] == "no-store"


def test_post_without_csrf_rejected(client):
    login(client)
    r = client.post("/ui/accounts", data={"broker_server": "B", "login": "1", "role": "slave"})
    assert "csrf" in r.text
    assert client.get("/admin/accounts", headers=admin_headers()).json()["accounts"] == []


def test_accounts_enroll_code_suspend_and_links(client, api):
    login(client)
    r = post(client, "/ui/accounts", {"broker_server": "Broker-Live", "login": "500", "role": "master",
                                      "label": "<b>m</b>"}, page="/ui/accounts")
    assert "account #1 created" in r.text and "<b>m</b>" not in r.text and "&lt;b&gt;m&lt;/b&gt;" in r.text
    post(client, "/ui/accounts", {"broker_server": "Broker-Live", "login": "600", "role": "slave"}, "/ui/accounts")
    r = post(client, "/ui/accounts/2/enroll_code", {}, page="/ui/accounts/2")
    code = re.search(r"<code class=secret>([A-Z0-9]{10})</code>", r.text).group(1)
    assert api.enroll(code, login=600, role="slave").status_code == 201
    r = post(client, "/ui/groups", {"master_id": "1", "name": "main", "magic_allow": "", "symbol_filter": ""},
             page="/ui/accounts/1")
    assert "group #1 created" in r.text
    r = post(client, "/ui/links", {"group_id": "1", "slave_id": "2", "enabled": "1", "lot_mode": "multiplier",
                                   "lot_value": "", "below_min": "skip", "magic_mode": "same", "copy_sl_tp": "1"},
             page="/ui/links")
    assert "lot_value is required" in r.text  # validation shown, nothing created
    r = post(client, "/ui/links", {"group_id": "1", "slave_id": "2", "enabled": "1", "lot_mode": "multiplier",
                                   "lot_value": "2", "below_min": "skip", "magic_mode": "same", "copy_sl_tp": "1",
                                   "max_entry_deviation_points": "30"}, page="/ui/links")
    assert "link #1 created" in r.text
    link = client.get("/admin/links", headers=admin_headers()).json()["links"][0]
    assert (link["lot_mode"], float(link["lot_value"]), link["max_entry_deviation_points"]) == ("multiplier", 2, 30)
    r = post(client, "/ui/links/1", {"lot_mode": "fixed", "lot_value": "0.1", "below_min": "skip",
                                     "magic_mode": "same"}, page="/ui/links/1")
    assert "saved" in r.text
    link = client.get("/admin/links", headers=admin_headers()).json()["links"][0]
    assert (link["enabled"], link["lot_mode"], link["copy_sl_tp"]) == (False, "fixed", False)
    r = post(client, "/ui/symbol_maps", {"slave_id": "2", "master_symbol": "XAUUSD", "slave_symbol": "GOLD"},
             page="/ui/symbol_maps")
    assert "map #1 created" in r.text and "GOLD" in r.text
    r = post(client, "/ui/symbol_maps", {"slave_id": "2", "master_symbol": "XAUUSD", "slave_symbol": "X"},
             page="/ui/symbol_maps")
    assert "map_conflict" in r.text
    r = post(client, "/ui/accounts/2/status", {"status": "suspended", "suspended_reason": "billing"},
             page="/ui/accounts/2")
    assert "status: suspended" in r.text
    assert client.get("/admin/accounts/2", headers=admin_headers()).json()["suspended_reason"] == "billing"
    r = post(client, "/ui/accounts/2/revoke", {}, page="/ui/accounts/2")
    assert "tick the confirmation box" in r.text
    r = post(client, "/ui/accounts/2/revoke", {"confirm": "1"}, page="/ui/accounts/2")
    assert client.get("/admin/accounts/2", headers=admin_headers()).json()["status"] == "revoked"


def test_copy_resolution_and_events_pages(cp, client, app):
    """S42 through the UI: the suspended copy is listed under attention and resolved from its page."""
    master, sl, c = uncertain_open(cp)
    login(client)
    home = client.get("/ui/").text
    assert f'href="/ui/copies/{c["copy_id"]}"' in home and "copy.uncertain" in home
    r = post(client, f"/ui/copies/{c['copy_id']}/resolve", {"resolution": "executed", "position_id": "7001",
                                                          "volume": "1", "price": "", "note": "checked"},
             page=f"/ui/copies/{c['copy_id']}")
    assert "resolved: open" in r.text
    assert copy_of(cp, c["copy_id"])["state"] == "open"
    r = post(client, f"/ui/copies/{c['copy_id']}/resolve", {"resolution": "not_executed"},
             page=f"/ui/copies/{c['copy_id']}")
    assert "not_resolvable" in r.text
    ev = client.get("/ui/events", params={"copy_id": c["copy_id"], "prefix": "admin."}).text
    assert "admin.resolved" in ev and "copy.pending" not in ev
    assert "copy.uncertain" in client.get("/ui/events", params={"alerts": "1"}).text
    assert "no EA log uploads" in client.get("/ui/logs").text


def test_conflict_pages(cp, client, app):
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    o = opened(cp, master, sl)
    cp.slave_snapshot(sl, [spos(7001, o["copy_id"]), pos(8888, comment="manual")])
    with app.state.sessionmaker() as s:
        conf_id = s.scalars(select(SymbolConflict)).one().id
    login(client)
    assert "unmanaged_position" in client.get("/ui/conflicts").text
    r = post(client, f"/ui/conflicts/{conf_id}/resolve", {"resolution": "accept", "note": "ok"}, page="/ui/conflicts")
    assert "resolved" in r.text
    assert "unmanaged_position" not in client.get("/ui/conflicts").text
    assert "accepted: ok" in client.get("/ui/conflicts", params={"show": "all"}).text


def test_readonly_token_sees_but_cannot_change(client):
    r = client.post("/admin/api_tokens", json={"name": "ro", "scopes": ["readonly"]}, headers=admin_headers())
    login(client, r.json()["token"])
    page = client.get("/ui/accounts").text
    assert "(read-only)" in page and "Create account" not in page
    # a forged form with a valid CSRF still needs the admin scope
    token = re.search(r'name=csrf value="([0-9a-f]+)"', page).group(1)
    r = client.post("/ui/accounts", data={"csrf": token, "broker_server": "B", "login": "1", "role": "slave"})
    assert "read-only token" in r.text
    assert client.get("/admin/accounts", headers=admin_headers()).json()["accounts"] == []


def test_tokens_page_and_revocation_ends_session(client):
    login(client)
    r = post(client, "/ui/tokens", {"name": "svc", "scope": "admin"}, page="/ui/tokens")
    token = re.search(r"<code class=secret>(cct_[^<]+)</code>", r.text).group(1)
    other = type(client)(client.app)
    login(other, token)
    assert other.get("/ui/accounts").status_code == 200
    tid = client.get("/admin/api_tokens", headers=admin_headers()).json()["api_tokens"][0]["id"]
    post(client, f"/ui/tokens/{tid}/revoke", {}, page="/ui/tokens")
    r = other.get("/ui/accounts", follow_redirects=False)
    assert r.status_code == 303 and r.headers["location"] == "/ui/login"
