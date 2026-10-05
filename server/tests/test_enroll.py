"""Enrollment (D8 steps 1-3, 7) and scenario S26."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select

from copycore.models import EnrollCode, utcnow

from .conftest import admin_headers, bearer


def test_enroll_happy_path(api, client):
    acct = api.create_account("Broker-Live", 1001, "slave")
    code = api.issue_code(acct["id"])
    assert len(code) == 10
    r = api.enroll(code, "Broker-Live", 1001, "slave", "netting")
    assert r.status_code == 201
    body = r.json()
    assert body["account_id"] == acct["id"] and body["token"].startswith("cct_")
    assert "server_time" in body
    cfg = client.get("/v4/config", headers=bearer(body["token"]))
    assert cfg.status_code == 200
    shown = client.get(f"/admin/accounts/{acct['id']}", headers=admin_headers()).json()
    assert shown["margin_mode"] == "netting" and shown["enrolled"] is True and shown["ea_version"] == "1.0.0"


def test_enroll_server_name_is_normalized(api):
    acct = api.create_account("Broker-Live", 1001, "slave")
    r = api.enroll(api.issue_code(acct["id"]), "  broker-live ", 1001, "slave")
    assert r.status_code == 201


def test_s26_enroll_response_lost_same_identity_reenrolls_within_ttl(api, client):
    """S26: response lost → same code + identity re-enrolls; the previous unconfirmed token dies."""
    acct = api.create_account()
    code = api.issue_code(acct["id"])
    first = api.enroll(code).json()["token"]  # pretend this response never reached the EA
    second = api.enroll(code)
    assert second.status_code == 201
    token = second.json()["token"]
    assert token != first
    assert client.get("/v4/config", headers=bearer(first)).status_code == 401
    assert client.get("/v4/config", headers=bearer(token)).status_code == 200


def test_s26_code_consumed_on_first_authenticated_call(api, client, app):
    """S26: once the issued token is used, the code can no longer enroll."""
    acct = api.create_account()
    code = api.issue_code(acct["id"])
    token = api.enroll(code).json()["token"]
    with app.state.sessionmaker() as s:
        assert s.scalar(select(EnrollCode)).consumed_at is None
    assert client.get("/v4/config", headers=bearer(token)).status_code == 200
    with app.state.sessionmaker() as s:
        assert s.scalar(select(EnrollCode)).consumed_at is not None
    r = api.enroll(code)
    assert r.status_code == 401 and r.json()["error"] == "code_consumed"
    assert client.get("/v4/config", headers=bearer(token)).status_code == 200


def test_enroll_wrong_identity_rejected(api):
    acct = api.create_account("Broker-Live", 1001, "slave")
    code = api.issue_code(acct["id"])
    for server, login, role in (("Other-Server", 1001, "slave"), ("Broker-Live", 1002, "slave"),
                                ("Broker-Live", 1001, "master")):
        r = api.enroll(code, server, login, role)
        assert r.status_code == 401 and r.json()["error"] == "identity_mismatch"
    assert api.enroll(code).status_code == 201  # 3 failures < 5: still usable by the right identity


def test_enroll_five_failures_burn_the_code(api):
    acct = api.create_account("Broker-Live", 1001, "slave")
    code = api.issue_code(acct["id"])
    for _ in range(5):
        assert api.enroll(code, login=9999).status_code == 401
    r = api.enroll(code)
    assert r.status_code == 401 and r.json()["error"] == "code_consumed"


def test_enroll_unknown_and_expired_code(api, app):
    acct = api.create_account()
    assert api.enroll("ZZZZZZZZZZ").json()["error"] == "invalid_code"
    code = api.issue_code(acct["id"])
    with app.state.sessionmaker() as s:
        row = s.scalar(select(EnrollCode))
        row.expires_at = utcnow() - timedelta(seconds=1)
        s.commit()
    r = api.enroll(code)
    assert r.status_code == 401 and r.json()["error"] == "code_expired"


def test_enroll_requires_idempotency_key(api, client):
    acct = api.create_account()
    body = {"code": api.issue_code(acct["id"]), "broker_server": "Broker-Live", "login": 1001,
            "role": "slave", "margin_mode": "hedging", "ea_version": "1"}
    r = client.post("/v4/enroll", json=body)
    assert r.status_code == 400 and r.json()["error"] == "idempotency_key_required"


def test_enroll_validation_error_does_not_echo_code(api, client):
    r = client.post("/v4/enroll", json={"code": "SECRETCODE1", "login": "x"}, headers={"Idempotency-Key": "k"})
    assert r.status_code == 422
    assert "SECRETCODE1" not in r.text


def test_reenroll_after_revocation_with_new_code(api, client):
    acct, token = api.enrolled()
    assert client.post(f"/admin/accounts/{acct['id']}/revoke", headers=admin_headers()).status_code == 200
    assert client.get("/v4/config", headers=bearer(token)).status_code == 401
    new = api.enroll(api.issue_code(acct["id"]))
    assert new.status_code == 201
    assert client.get("/v4/config", headers=bearer(new.json()["token"])).status_code == 200
    assert client.get("/v4/config", headers=bearer(token)).status_code == 401
