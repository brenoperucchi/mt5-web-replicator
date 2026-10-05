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


def engine_ctx(request: Request):
    """Engine context for admin actions (same settings as the v4 routes)."""
    from .auth import version_gated
    from .engine.lifecycle import Ctx

    settings = settings_of(request)
    clock = request.app.state.clock
    return Ctx(open_ttl_seconds=settings.open_ttl_seconds, lease_seconds=settings.command_lease_seconds,
               gated=lambda a: version_gated(a, settings), mono=clock.monotonic(), server_epoch=clock.epoch)
