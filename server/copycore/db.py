"""Engine and unit of work (design D6).

SQLite: pysqlite runs in driver autocommit and a SQLAlchemy ``begin`` hook issues
``BEGIN IMMEDIATE``, so the write lock is taken before the first read of a unit of work.
PRAGMAs: WAL, synchronous=FULL, busy_timeout=5000, foreign_keys=ON, auto_vacuum=INCREMENTAL.
Postgres: plain transactions (row locks are added by the engine logic in later PRs).
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
        conn.exec_driver_sql("BEGIN IMMEDIATE")


def make_sessionmaker(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(bind=engine, expire_on_commit=False)


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
