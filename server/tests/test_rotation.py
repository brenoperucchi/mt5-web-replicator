"""Two-step token rotation (D8 step 5) and scenario S25."""

from __future__ import annotations

import uuid
from datetime import timedelta

from copycore.models import Account, utcnow

from .conftest import bearer, ikey


def rotate(client, token, restart=False, key=None):
    url = "/v4/token/rotate" + ("?restart=true" if restart else "")
    return client.post(url, headers={**bearer(token), "Idempotency-Key": key or str(uuid.uuid4())})


def confirm(client, token, pending_id, key=None):
    return client.post("/v4/token/confirm", json={"pending_id": pending_id},
                       headers={**bearer(token), "Idempotency-Key": key or str(uuid.uuid4())})


def test_rotation_two_step(api, client):
    _, old = api.enrolled()
    r = rotate(client, old)
    assert r.status_code == 200
    new, pid = r.json()["new_token"], r.json()["pending_id"]
    assert new != old
    assert client.get("/v4/config", headers=bearer(old)).status_code == 200  # old valid until confirm
    r = confirm(client, new, pid)
    assert r.status_code == 204
    assert client.get("/v4/config", headers=bearer(old)).status_code == 401  # confirm revokes old
    assert client.get("/v4/config", headers=bearer(new)).status_code == 200


def test_s25_rotate_response_lost(api, client):
    """S25: rotate response lost → old token still works; replay → 409 rotation_pending."""
    _, old = api.enrolled()
    key = str(uuid.uuid4())
    lost = rotate(client, old, key=key)  # response never reaches the EA
    assert lost.status_code == 200
    assert client.get("/v4/config", headers=bearer(old)).status_code == 200
    replay = rotate(client, old, key=key)  # same Idempotency-Key: not served from cache
    assert replay.status_code == 409 and replay.json()["error"] == "rotation_pending"
    assert "new_token" not in replay.text
    fresh = rotate(client, old)  # new key, same outcome
    assert fresh.status_code == 409
    # Recovery: restart discards the lost pending token and issues another.
    r = rotate(client, old, restart=True)
    assert r.status_code == 200
    new, pid = r.json()["new_token"], r.json()["pending_id"]
    lost_token = lost.json()["new_token"]
    assert confirm(client, lost_token, lost.json()["pending_id"]).status_code == 401
    assert confirm(client, new, pid).status_code == 204
    assert client.get("/v4/config", headers=bearer(new)).status_code == 200
    assert client.get("/v4/config", headers=bearer(old)).status_code == 401


def test_pending_token_only_valid_for_confirm(api, client):
    _, old = api.enrolled()
    new = rotate(client, old).json()["new_token"]
    r = client.get("/v4/config", headers=bearer(new))
    assert r.status_code == 401 and r.json()["error"] == "token_not_confirmed"


def test_confirm_requires_new_token_and_matching_pending_id(api, client):
    _, old = api.enrolled()
    r = rotate(client, old).json()
    assert confirm(client, old, r["pending_id"]).status_code == 409
    assert confirm(client, r["new_token"], "rot_wrong").json()["error"] == "pending_mismatch"
    assert confirm(client, r["new_token"], r["pending_id"]).status_code == 204


def test_confirm_response_lost_replay_returns_204(api, client):
    _, old = api.enrolled()
    r = rotate(client, old).json()
    key = str(uuid.uuid4())
    assert confirm(client, r["new_token"], r["pending_id"], key=key).status_code == 204
    again = confirm(client, r["new_token"], r["pending_id"], key=key)
    assert again.status_code == 204


def test_pending_rotation_expires_after_ttl(api, client, app):
    acct, old = api.enrolled()
    r = rotate(client, old).json()
    with app.state.sessionmaker() as s:
        a = s.get(Account, acct["id"])
        a.pending_token_issued_at = utcnow() - timedelta(hours=25)
        s.commit()
    assert confirm(client, r["new_token"], r["pending_id"]).status_code == 401
    assert rotate(client, old).status_code == 200  # expired pending no longer blocks


def test_rotate_requires_idempotency_key(api, client):
    _, old = api.enrolled()
    assert client.post("/v4/token/rotate", headers=bearer(old)).status_code == 400
    assert client.post("/v4/token/rotate", headers={**bearer(old), **ikey()}).status_code == 200
