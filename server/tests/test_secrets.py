"""Tokens are never persisted or logged (D8 step 6, 5.7; S25/S26 'no token in DB/logs')."""

from __future__ import annotations

import logging
import uuid

from sqlalchemy import inspect, select, text

from copycore.models import IdempotencyKey
from copycore.security import RedactingFilter, redact

from .conftest import admin_headers, bearer


def all_db_text(engine) -> str:
    chunks = []
    with engine.connect() as conn:
        for table in inspect(engine).get_table_names():
            for row in conn.execute(text(f'SELECT * FROM "{table}"')):  # noqa: S608
                chunks.append(repr(tuple(row)))
    return "\n".join(chunks)


def test_tokens_never_stored_in_db_or_logs(api, client, app, engine, caplog):
    caplog.set_level(logging.DEBUG)
    acct = api.create_account()
    code = api.issue_code(acct["id"])
    token = api.enroll(code, key="enroll-key-1").json()["token"]
    client.get("/v4/config", headers=bearer(token))
    r = client.post("/v4/token/rotate", headers={**bearer(token), "Idempotency-Key": "rot-key-1"}).json()
    new = r["new_token"]
    client.post("/v4/token/confirm", json={"pending_id": r["pending_id"]},
                headers={**bearer(new), "Idempotency-Key": "confirm-key-1"})
    logging.getLogger("copycore").info("debug dump Authorization: Bearer %s body={'token': '%s'}", new, token)

    with app.state.sessionmaker() as s:
        rows = {row.key: row for row in s.scalars(select(IdempotencyKey))}
    assert rows["enroll-key-1"].kind == "token" and rows["enroll-key-1"].response is None
    assert rows["rot-key-1"].kind == "token" and rows["rot-key-1"].response is None
    assert rows["confirm-key-1"].kind == "response"

    dump = all_db_text(engine)
    for secret in (token, new, code):
        assert secret not in dump
        assert secret not in caplog.text


def test_redaction_patterns():
    s = redact('Authorization: Bearer cct_abc {"token": "xyz", "new_token": "q"} cct_zzz')
    assert "cct_abc" not in s and "xyz" not in s and '"q"' not in s and "cct_zzz" not in s
    rec = logging.LogRecord("copycore", logging.INFO, "f", 1, "token=%s", ("cct_secret",), None)
    RedactingFilter().filter(rec)
    assert "cct_secret" not in rec.getMessage()


def test_admin_account_view_never_exposes_hashes(api, client):
    acct, _ = api.enrolled()
    body = client.get(f"/admin/accounts/{acct['id']}", headers=admin_headers()).text
    assert "hash" not in body


def test_idempotency_key_reuse_with_different_body_409(api, client):
    _, old = api.enrolled()
    r = client.post("/v4/token/rotate", headers={**bearer(old), "Idempotency-Key": "k1"}).json()
    key = str(uuid.uuid4())
    h = {**bearer(r["new_token"]), "Idempotency-Key": key}
    assert client.post("/v4/token/confirm", json={"pending_id": "rot_other"}, headers=h).status_code == 409
    ok = client.post("/v4/token/confirm", json={"pending_id": r["pending_id"]}, headers=h)
    assert ok.status_code == 204  # a failed request stores nothing; the key is still free
    reuse = client.post("/v4/token/confirm", json={"pending_id": "rot_different"},
                        headers={**bearer(r["new_token"]), "Idempotency-Key": key})
    assert reuse.status_code == 409 and reuse.json()["error"] == "idempotency_key_reuse"


def test_enroll_replay_same_key_is_not_served_from_cache(api):
    acct = api.create_account()
    code = api.issue_code(acct["id"])
    a = api.enroll(code, key="same").json()["token"]
    b = api.enroll(code, key="same")
    assert b.status_code == 201 and b.json()["token"] != a  # D8 recovery rule, fresh token
