"""Idle polls are read-only (D6 at scale): no write lock, no row writes, last_seen_at throttled."""

from __future__ import annotations

import sqlite3
import time
from datetime import timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import event, select, update
from sqlalchemy.orm import Session

from copycore.app import create_app
from copycore.auth import aware
from copycore.models import Account, Command, utcnow

from .conftest import PG_URL, bearer
from .copyhelpers import pos


def capture(engine) -> list[str]:
    seen: list[str] = []

    @event.listens_for(engine, "before_cursor_execute")
    def _capture(conn, cursor, statement, *a):
        seen.append(statement.strip().split()[0].upper() + " " + statement.strip()[6:40])

    return seen


def writes(stmts: list[str]) -> list[str]:
    return [s for s in stmts if s.split()[0] in ("INSERT", "UPDATE", "DELETE")]


@pytest.fixture
def slave(cp):
    acct = cp.account("slave", 2001)
    cp.poll(acct)     # first call: consumes the enroll code and stamps last_seen_at
    return acct


def test_idle_poll_writes_nothing(engine, cp, slave):
    stmts = capture(engine)
    body = cp.poll(slave)
    assert body["commands"] == []
    assert writes(stmts) == []
    if not PG_URL:
        assert "BEGIN " in [s[:6] for s in stmts] and not any(s.startswith("BEGIN IMMEDIATE") for s in stmts)


def test_idle_config_writes_nothing(engine, client, slave):
    stmts = capture(engine)
    r = client.get("/v4/config", headers=bearer(slave["token"]))
    assert r.status_code == 200
    assert writes(stmts) == []


def test_last_seen_throttled(engine, cp, slave):
    with Session(engine) as s:
        first = s.scalar(select(Account.last_seen_at).where(Account.id == slave["id"]))
    assert first is not None
    cp.poll(slave)
    with Session(engine) as s:
        assert s.scalar(select(Account.last_seen_at).where(Account.id == slave["id"])) == first
        s.execute(update(Account).where(Account.id == slave["id"])
                  .values(last_seen_at=utcnow() - timedelta(seconds=31)))
        s.commit()
    cp.poll(slave)    # older than LAST_SEEN_WRITE_SECONDS: written again (write path)
    with Session(engine) as s:
        again = s.scalar(select(Account.last_seen_at).where(Account.id == slave["id"]))
    assert again is not None and utcnow() - aware(again) < timedelta(seconds=5)


def test_poll_with_a_command_still_delivers(engine, cp):
    master = cp.account("master", 1001)
    s_acct = cp.account("slave", 2002)
    g = cp.group(master["id"])
    cp.link(g["id"], s_acct["id"])
    cp.snapshot(master, [pos(5001)])
    out = cp.poll(s_acct)["commands"]
    assert [c["action"] for c in out] == ["open"]
    with Session(engine) as s:
        assert s.get(Command, out[0]["command_id"]).state == "delivered"
    assert [c["command_id"] for c in cp.poll(s_acct)["commands"]] == [out[0]["command_id"]]  # un-acked: again


def test_expired_open_is_still_expired_by_a_poll(engine, cp):
    master = cp.account("master", 1003)
    s_acct = cp.account("slave", 2003)
    g = cp.group(master["id"])
    cp.link(g["id"], s_acct["id"])
    cp.snapshot(master, [pos(5002)])
    with Session(engine) as s:
        s.execute(update(Command).values(expires_at=utcnow() - timedelta(seconds=1)))
        s.commit()
    assert cp.poll(s_acct)["commands"] == []
    with Session(engine) as s:
        assert {c.state for c in s.scalars(select(Command))} == {"expired"}


@pytest.mark.skipif(bool(PG_URL), reason="SQLite lock behavior")
def test_idle_poll_not_blocked_by_a_writer(db_url, cp, client, slave):
    """Another unit of work holds the SQLite write lock: an idle poll is answered at once (no busy wait)."""
    path = db_url.removeprefix("sqlite:///")
    holder = sqlite3.connect(path, isolation_level=None)
    holder.execute("BEGIN IMMEDIATE")
    try:
        t0 = time.monotonic()
        r = client.get("/v4/slave/commands", headers=bearer(slave["token"]))
        took = time.monotonic() - t0
    finally:
        holder.execute("ROLLBACK")
        holder.close()
    assert r.status_code == 200, r.text
    assert took < 1.0


def test_access_trace(tmp_path, settings, engine, cp):
    trace = tmp_path / "trace.tsv"
    app = create_app(settings.model_copy(update={"access_trace_path": str(trace)}), engine=engine)
    with TestClient(app) as c:
        acct = cp.account("slave", 2004)
        r = c.get("/v4/slave/commands", headers=bearer(acct["token"]))
        assert r.status_code == 200
        c.get("/v4/config", headers={"Authorization": "Bearer nope"})
    lines = [ln.split("\t") for ln in trace.read_text().splitlines()]
    assert lines[0][1:5] == [str(acct["id"]), "GET", "/v4/slave/commands", "200"]
    assert lines[1][1:5] == ["-", "GET", "/v4/config", "401"]
    assert "nope" not in trace.read_text() and acct["token"] not in trace.read_text()
