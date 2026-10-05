"""Admin operations API (Phase 1 / PR 5): resolution actions, conflicts, events/alerts, EA logs, orphans.

Design 4.6 step 7, 5.8, 5.8a, 6.2, Q9. The logic lives in `engine.admin_ops` and is shared with the UI.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from ..auth import authenticate_admin
from ..deps import engine_ctx, settings_of, uow
from ..engine.admin_ops import CopyResolution, attention, resolve_conflict, resolve_copy
from ..errors import ApiError, json_response
from ..models import Copy, EaLog, Event, SymbolConflict
from .admin_copy import copy_json

router = APIRouter(prefix="/admin")

# Event types an operator must look at (6.2, 5.6, 5.8, 5.9, 9 D11).
ALERT_TYPES = (
    "master.stale", "master.mass_disappearance", "master.duplicate_producer", "master_position.reappeared",
    "copy.uncertain", "copy.symbol_conflict", "copy.duplicate_position", "copy.close_unconfirmed",
    "copy.slot_occupied", "copy.late_fill", "copy.error", "account.mismatch", "account.revoked",
    "link.disabled_conflict", "storage.quota_reached", "symbol_conflict.close_failed", "command.rejected",
)


class CopyResolveIn(BaseModel):
    """`{executed: position_id}` / `{not_executed: true}` (5.8), plus `closed` / `retry_close` for closes
    without evidence. Alternatively `{resolution: ..., position_id: ...}`."""

    model_config = ConfigDict(extra="forbid")
    resolution: Literal["executed", "not_executed", "closed", "retry_close"] | None = None
    executed: int | None = None
    not_executed: bool | None = None
    position_id: int | None = None
    volume: Decimal | None = Field(default=None, ge=0)
    price: Decimal | None = None
    note: str | None = Field(default=None, max_length=255)

    @model_validator(mode="after")
    def _shape(self):
        forms = [self.resolution is not None, self.executed is not None, bool(self.not_executed)]
        if sum(forms) != 1:
            raise ValueError("give exactly one of resolution, executed, not_executed")
        if self.executed is not None:
            self.resolution, self.position_id = "executed", self.executed
        elif self.not_executed:
            self.resolution = "not_executed"
        return self


class ConflictResolveIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    resolution: Literal["accept", "close"]
    note: str | None = Field(default=None, max_length=255)


def conflict_json(c: SymbolConflict) -> dict:
    return {"id": c.id, "slave_id": c.slave_id, "symbol_local": c.symbol_local, "kind": c.kind,
            "copy_id": c.copy_id, "position_id": c.position_id,
            "opened_at": c.opened_at.isoformat() if c.opened_at else None,
            "resolved_at": c.resolved_at.isoformat() if c.resolved_at else None, "resolution": c.resolution}


def event_json(e: Event) -> dict:
    return {"id": e.id, "type": e.type, "payload": e.payload, "created_at": e.created_at.isoformat()}


def log_json(row: EaLog) -> dict:
    return {"id": row.id, "account_id": row.account_id, "received_at": row.received_at.isoformat(),
            "size_bytes": row.size_bytes, "content": row.content}


# --- resolution --------------------------------------------------------------------------------------

@router.post("/copies/{copy_id}/resolve")
def resolve_copy_route(copy_id: int, body: CopyResolveIn, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        actor = authenticate_admin(s, request, settings)
        copy = s.get(Copy, copy_id)
        if copy is None:
            raise ApiError(404, "not_found", "copy not found")
        out = resolve_copy(s, copy, engine_ctx(request), CopyResolution(
            resolution=body.resolution, position_id=body.position_id, volume=body.volume, price=body.price,
            note=body.note), actor)
        return json_response({**out, "copy": copy_json(copy)})

    return uow(request, work)


@router.post("/symbol_conflicts/{conflict_id}/resolve")
def resolve_conflict_route(conflict_id: int, body: ConflictResolveIn, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        actor = authenticate_admin(s, request, settings)
        row = s.get(SymbolConflict, conflict_id)
        if row is None:
            raise ApiError(404, "not_found", "symbol conflict not found")
        out = resolve_conflict(s, row, engine_ctx(request), body.resolution, body.note, actor)
        return json_response({**out, "conflict": conflict_json(row)})

    return uow(request, work)


# --- listings ----------------------------------------------------------------------------------------

@router.get("/symbol_conflicts")
def list_conflicts(request: Request, slave_id: int | None = None, open: bool | None = None, limit: int = 200):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings, scope="readonly")
        q = select(SymbolConflict).order_by(SymbolConflict.id.desc()).limit(min(max(limit, 1), 1000))
        if slave_id is not None:
            q = q.where(SymbolConflict.slave_id == slave_id)
        if open is not None:
            q = q.where(SymbolConflict.resolved_at.is_(None) if open else SymbolConflict.resolved_at.is_not(None))
        return json_response({"symbol_conflicts": [conflict_json(c) for c in s.scalars(q)]})

    return uow(request, work)


def _payload_eq(s: Session, key: str, value: int):
    """Portable JSON field equality: SQLite json_extract keeps the integer type, Postgres ->> is text."""
    field = Event.payload[key]
    if s.get_bind().dialect.name == "postgresql":
        return field.as_string() == str(value)
    return field.as_integer() == value


def query_events(s: Session, *, type: str | None = None, prefix: str | None = None, alerts: bool = False,
                 copy_id: int | None = None, account_id: int | None = None, before_id: int | None = None,
                 limit: int = 100) -> list[Event]:
    q = select(Event).order_by(Event.id.desc()).limit(min(max(limit, 1), 1000))
    if type:
        q = q.where(Event.type == type)
    if prefix:
        q = q.where(Event.type.startswith(prefix, autoescape=True))
    if alerts:
        q = q.where(Event.type.in_(ALERT_TYPES))
    if copy_id is not None:
        q = q.where(_payload_eq(s, "copy_id", copy_id))
    if account_id is not None:
        q = q.where(or_(*(_payload_eq(s, k, account_id) for k in ("account_id", "slave_id", "master_id"))))
    if before_id is not None:
        q = q.where(Event.id < before_id)
    return list(s.scalars(q))


@router.get("/events")
def list_events(request: Request, type: str | None = None, prefix: str | None = None, alerts: bool = False,
                copy_id: int | None = None, account_id: int | None = None, before_id: int | None = None,
                limit: int = 100):
    """Event outbox, newest first; `before_id` pages backwards. `alerts=true` keeps operator alerts only."""
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings, scope="readonly")
        rows = query_events(s, type=type, prefix=prefix, alerts=alerts, copy_id=copy_id, account_id=account_id,
                            before_id=before_id, limit=limit)
        return json_response({"events": [event_json(e) for e in rows],
                              "next_before_id": rows[-1].id if rows else None})

    return uow(request, work)


@router.get("/alerts")
def list_alerts(request: Request, account_id: int | None = None, before_id: int | None = None, limit: int = 100):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings, scope="readonly")
        rows = query_events(s, alerts=True, account_id=account_id, before_id=before_id, limit=limit)
        return json_response({"alerts": [event_json(e) for e in rows], "next_before_id": rows[-1].id if rows else None})

    return uow(request, work)


@router.get("/logs")
def list_logs(request: Request, account_id: int | None = None, before_id: int | None = None, limit: int = 50):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings, scope="readonly")
        q = select(EaLog).order_by(EaLog.id.desc()).limit(min(max(limit, 1), 500))
        if account_id is not None:
            q = q.where(EaLog.account_id == account_id)
        if before_id is not None:
            q = q.where(EaLog.id < before_id)
        return json_response({"logs": [log_json(r) for r in s.scalars(q)]})

    return uow(request, work)


@router.get("/orphans")
def list_orphans(request: Request, limit: int = 200):
    """Copies and conflicts that only an operator (or later broker evidence) can settle."""
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings, scope="readonly")
        a = attention(s, min(max(limit, 1), 1000))
        return json_response({"uncertain": [copy_json(c) for c in a["uncertain"]],
                              "close_unconfirmed": [copy_json(c) for c in a["close_unconfirmed"]],
                              "revoked_exposure": [copy_json(c) for c in a["revoked_exposure"]],
                              "symbol_conflicts": [conflict_json(c) for c in a["conflicts"]]})

    return uow(request, work)
