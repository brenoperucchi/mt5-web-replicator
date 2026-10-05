from __future__ import annotations

from collections.abc import Callable

from fastapi import Request
from sqlalchemy.orm import Session

from .config import Settings
from .db import run_unit_of_work


def settings_of(request: Request) -> Settings:
    return request.app.state.settings


def uow[T](request: Request, work: Callable[[Session], T]) -> T:
    """One request = one unit of work (5.7), retried as a whole on SQLITE_BUSY (D6)."""
    return run_unit_of_work(request.app.state.sessionmaker, work)
