"""SQLite runtime contract (D6): PRAGMAs and BEGIN IMMEDIATE for every unit of work."""

from __future__ import annotations

import threading
import time

import pytest
from sqlalchemy import event, text
from sqlalchemy.orm import Session

from copycore.db import make_sessionmaker, run_unit_of_work
from copycore.models import Event

from .conftest import PG_URL

pytestmark = pytest.mark.skipif(bool(PG_URL), reason="SQLite-only behavior")


def test_pragmas(engine):
    with engine.connect() as conn:
        assert conn.exec_driver_sql("PRAGMA journal_mode").scalar() == "wal"
        assert conn.exec_driver_sql("PRAGMA synchronous").scalar() == 2  # FULL
        assert conn.exec_driver_sql("PRAGMA busy_timeout").scalar() == 5000
        assert conn.exec_driver_sql("PRAGMA foreign_keys").scalar() == 1


def test_transactions_start_with_begin_immediate(engine):
    seen = []

    @event.listens_for(engine, "before_cursor_execute")
    def _capture(conn, cursor, statement, *a):
        seen.append(statement)

    with Session(engine) as s:
        s.execute(text("SELECT 1"))
        s.commit()
    assert "BEGIN IMMEDIATE" in seen


def test_foreign_keys_enforced(engine):
    from sqlalchemy.exc import IntegrityError

    from copycore.models import SymbolMap
    with Session(engine) as s:
        s.add(SymbolMap(slave_id=999_999, master_symbol="A", slave_symbol="B"))
        with pytest.raises(IntegrityError):
            s.commit()


def test_concurrent_read_modify_write_serializes(engine):
    """Two writers that read then write: with BEGIN IMMEDIATE the second waits for the first.

    With a deferred BEGIN both would read the same value and the second upgrade to a write lock
    would fail with SQLITE_BUSY(_SNAPSHOT) or lose an update.
    """
    factory = make_sessionmaker(engine)
    with factory() as s:
        s.add(Event(type="counter", payload={"n": 0}))
        s.commit()
    barrier = threading.Barrier(2)
    errors: list[BaseException] = []

    def worker():
        # No unit-of-work retry here: the lock itself must serialize the two writers.
        try:
            barrier.wait()
            with factory() as s:
                ev = s.query(Event).filter_by(type="counter").one()
                n = ev.payload["n"]
                time.sleep(0.3)  # hold the transaction open after the read
                ev.payload = {"n": n + 1}
                s.commit()
        except BaseException as exc:  # noqa: BLE001
            errors.append(exc)

    threads = [threading.Thread(target=worker) for _ in range(2)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert errors == []
    with factory() as s:
        assert s.query(Event).filter_by(type="counter").one().payload == {"n": 2}


def test_busy_unit_of_work_retried_then_busy_error(engine):
    from sqlalchemy.exc import OperationalError

    from copycore.db import BUSY_RETRIES, BusyError

    calls = []

    def work(_s):
        calls.append(1)
        raise OperationalError("BEGIN IMMEDIATE", {}, Exception("database is locked"))

    with pytest.raises(BusyError):
        run_unit_of_work(make_sessionmaker(engine), work)
    assert len(calls) == BUSY_RETRIES


def test_busy_maps_to_503_with_retry_after(app, client, monkeypatch):
    from copycore import deps
    from copycore.db import BusyError

    def busy(*_a, **_k):
        raise BusyError("busy")

    monkeypatch.setattr(deps, "run_unit_of_work", busy)
    r = client.get("/v4/config", headers={"Authorization": "Bearer x"})
    assert r.status_code == 503 and r.headers["Retry-After"] == "1"
