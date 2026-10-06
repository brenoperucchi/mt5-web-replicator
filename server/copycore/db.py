"""Engine and unit of work (design D6).

SQLite: pysqlite runs in driver autocommit and a SQLAlchemy ``begin`` hook issues
``BEGIN IMMEDIATE``, so the write lock is taken before the first read of a unit of work.
PRAGMAs: WAL, synchronous=FULL, busy_timeout=5000, foreign_keys=ON, auto_vacuum=INCREMENTAL.
Postgres: plain transactions (row locks are added by the engine logic in later PRs).

Read-first units (``run_read_first``): the hot polling paths (empty ``GET /v4/slave/commands``,
``GET /v4/config``) first run on a connection marked ``copycore_read_only``, which opens a plain
deferred ``BEGIN``: in WAL mode it takes no write lock, so idle polls of many EAs never serialize
on the database lock. When the work would change anything (dirty/new/deleted objects), that read
unit is rolled back and the same work runs again as a normal write unit.
"""

from __future__ import annotations

import logging
import random
import time
from collections.abc import Callable

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session, sessionmaker

log = logging.getLogger("copycore.db")

SQLITE_PRAGMAS = (
    "PRAGMA journal_mode=WAL",
    "PRAGMA synchronous=FULL",
    "PRAGMA busy_timeout=5000",
    "PRAGMA foreign_keys=ON",
    "PRAGMA auto_vacuum=INCREMENTAL",
)

BUSY_RETRIES = 3
READ_ONLY_OPTION = "copycore_read_only"


def normalize_url(url: str) -> str:
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://"):]
    if url.startswith("postgresql://"):
        url = "postgresql+psycopg://" + url[len("postgresql://"):]
    return url


def make_engine(url: str, **kw) -> Engine:
    url = normalize_url(url)
    if url.startswith("sqlite"):
        engine = create_engine(url, connect_args={"check_same_thread": False}, **kw)
        install_sqlite_hooks(engine)
        return engine
    return create_engine(url, pool_pre_ping=True, **kw)


def install_sqlite_hooks(engine: Engine) -> None:
    @event.listens_for(engine, "connect")
    def _on_connect(dbapi_conn, _record):
        # Driver autocommit: pysqlite must not emit its own (deferred) BEGIN.
        dbapi_conn.isolation_level = None
        cur = dbapi_conn.cursor()
        for pragma in SQLITE_PRAGMAS:
            cur.execute(pragma)
        cur.close()

    @event.listens_for(engine, "begin")
    def _on_begin(conn):
        conn.exec_driver_sql("BEGIN" if conn.get_execution_options().get(READ_ONLY_OPTION) else "BEGIN IMMEDIATE")


def make_sessionmaker(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(bind=engine, expire_on_commit=False)


def make_read_sessionmaker(engine: Engine) -> sessionmaker[Session]:
    """Sessions whose transactions start with a deferred BEGIN on SQLite (no write lock)."""
    return sessionmaker(bind=engine.execution_options(**{READ_ONLY_OPTION: True}), expire_on_commit=False,
                        autoflush=False)


class NeedsWrite(Exception):
    """Raised inside a read-first unit when the work has something to write."""


def run_read_first[T](read_factory: sessionmaker[Session], factory: sessionmaker[Session],
                      work: Callable[[Session], T]) -> T:
    """Run ``work`` read-only when it changes nothing; otherwise run it again as a write unit.

    ``work`` must be safe to run twice (the read attempt is always rolled back) and must not flush:
    the read session has autoflush off, and any pending change sends the call to the write path.
    """
    session = read_factory()
    try:
        result = work(session)
        if session.new or session.dirty or session.deleted:
            raise NeedsWrite
        session.rollback()
        return result
    except NeedsWrite:
        session.rollback()
    except OperationalError as exc:
        session.rollback()
        if not is_busy_error(exc):
            raise
    except BaseException:
        session.rollback()
        raise
    finally:
        session.close()
    return run_unit_of_work(factory, work)


def is_busy_error(exc: BaseException) -> bool:
    msg = str(getattr(exc, "orig", exc)).lower()
    return "database is locked" in msg or "database is busy" in msg


class BusyError(RuntimeError):
    """SQLite stayed busy after all retries; mapped to 503 + Retry-After."""


def run_unit_of_work[T](factory: sessionmaker[Session], work: Callable[[Session], T]) -> T:
    """Run ``work`` in one transaction, retrying the whole unit on SQLITE_BUSY (max 3, jittered)."""
    for attempt in range(1, BUSY_RETRIES + 1):
        session = factory()
        try:
            result = work(session)
            session.commit()
            return result
        except OperationalError as exc:
            session.rollback()
            if not is_busy_error(exc):
                raise
            log.warning("database busy (attempt %d/%d)", attempt, BUSY_RETRIES)
            if attempt == BUSY_RETRIES:
                raise BusyError("database busy") from exc
            time.sleep(random.uniform(0.05, 0.25) * attempt)  # noqa: S311
        except BaseException:
            session.rollback()
            raise
        finally:
            session.close()
    raise BusyError("database busy")  # pragma: no cover
