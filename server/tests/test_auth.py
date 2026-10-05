"""Bearer auth and 401/403 semantics (4.1, 6.2)."""

from __future__ import annotations

from copycore.models import Account

from . import factories as f
from .conftest import admin_headers, bearer


def test_valid_token_resolves_account_and_role(api, client):
    acct, token = api.enrolled(role="master", login=555)
    r = client.get("/v4/config", headers=bearer(token))
    assert r.status_code == 200
    body = r.json()
    assert body["account_id"] == acct["id"] and body["role"] == "master"
    assert body["mode"] == "normal"
    for k in ("message", "poll_ms", "debug", "send_history", "symbols_wanted", "min_ea_version", "server_time"):
        assert k in body
    assert "X-Server-Time" in r.headers


def test_missing_and_invalid_token_401(client):
    assert client.get("/v4/config").status_code == 401
    assert client.get("/v4/config", headers={"Authorization": "Basic abc"}).status_code == 401
    r = client.get("/v4/config", headers=bearer("cct_nope"))
    assert r.status_code == 401 and r.json()["error"] == "invalid_token"


def test_revoked_token_401(api, client):
    acct, token = api.enrolled()
    r = client.post(f"/admin/accounts/{acct['id']}/revoke", headers=admin_headers())
    assert r.json()["status"] == "revoked"
    assert client.get("/v4/config", headers=bearer(token)).status_code == 401


def test_suspended_without_open_copies_403(api, client):
    acct, token = api.enrolled()
    r = client.patch(f"/admin/accounts/{acct['id']}", json={"status": "suspended", "suspended_reason": "billing"},
                     headers=admin_headers())
    assert r.status_code == 200 and r.json()["status"] == "suspended"
    r = client.get("/v4/config", headers=bearer(token))
    assert r.status_code == 403 and r.json()["error"] == "account_blocked"
    client.patch(f"/admin/accounts/{acct['id']}", json={"status": "active"}, headers=admin_headers())
    assert client.get("/v4/config", headers=bearer(token)).status_code == 200


def test_s14_suspended_slave_with_open_copy_drains(api, client, app):
    """S14 (auth part): suspended slave with exposure gets 200 + mode=drain, not 403."""
    acct, token = api.enrolled()
    with app.state.sessionmaker() as s:
        slave = s.get(Account, acct["id"])
        master = f.account(s, "master")
        from copycore.models import CopyGroup, CopyLink
        g = CopyGroup(master_id=master.id, name="g")
        s.add(g)
        s.flush()
        link = CopyLink(group_id=g.id, master_id=master.id, slave_id=slave.id)
        s.add(link)
        s.flush()
        f.copy(s, link, f.master_position(s, master), slave, state="open", position_id=1)
        s.commit()
    client.patch(f"/admin/accounts/{acct['id']}", json={"status": "suspended"}, headers=admin_headers())
    r = client.get("/v4/config", headers=bearer(token))
    assert r.status_code == 200 and r.json()["mode"] == "drain"


def test_version_gate_without_copies_403(api, client, app):
    acct, token = api.enrolled()
    app.state.settings.min_ea_version = "2.0.0"
    r = client.get("/v4/config", headers=bearer(token))
    assert r.status_code == 403


def test_admin_requires_admin_token(client):
    body = {"broker_server": "B", "login": 1, "role": "slave"}
    assert client.post("/admin/accounts", json=body).status_code == 401
    assert client.post("/admin/accounts", json=body, headers=bearer("wrong")).status_code == 401


def test_admin_duplicate_account_409(api, client):
    api.create_account("Broker-Live", 7, "slave")
    r = client.post("/admin/accounts", json={"broker_server": "broker-live", "login": 7, "role": "slave"},
                    headers=admin_headers())
    assert r.status_code == 409


def test_health_no_auth(client):
    for path in ("/health", "/healthz"):
        r = client.get(path)
        assert r.status_code == 200 and r.json()["status"] == "ok"
