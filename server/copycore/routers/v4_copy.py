"""v4 copy endpoints: sessions, symbol specs, master snapshot, command delivery (PR 2), command
results, slave snapshot reconciliation and adoption (PR 3), master close detection, partial
reductions, reversal and SL/TP modify (PR 4) (design 4.3-4.6, 5.4-5.8).

Mutating calls require `Idempotency-Key` and run as one unit of work (retried as a whole on
SQLITE_BUSY). The unit of work runs in the threadpool so concurrent requests serialize on the
database lock (SQLite BEGIN IMMEDIATE / Postgres row lock on the account) instead of the loop.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any, Literal

from fastapi import APIRouter, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import Response
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .. import idempotency as idem
from ..auth import authenticate, version_gated
from ..deps import settings_of, uow
from ..engine import commands as cmds
from ..engine import raw as rawstore
from ..engine.fanout import PositionData
from ..engine.lifecycle import Ctx
from ..engine.master import CloseRules, process_master_snapshot
from ..engine.reconcile import reconcile_slave
from ..engine.results import apply_results
from ..errors import ApiError, json_response
from ..models import Account, Event, SessionRow, SymbolSpec, utcnow
from ..security import normalize_server

router = APIRouter(prefix="/v4")


class SessionIn(BaseModel):
    boot_nonce: str = Field(min_length=1, max_length=64)
    taken_at: int = Field(ge=0)
    ea_clock_offset_ms: int = 0


class SymbolSpecIn(BaseModel):
    name: str = Field(min_length=1, max_length=64)
    volume_min: Decimal | None = Field(default=None, ge=0)
    volume_step: Decimal | None = Field(default=None, ge=0)
    volume_max: Decimal | None = Field(default=None, ge=0)
    contract_size: Decimal | None = Field(default=None, ge=0)
    digits: int | None = Field(default=None, ge=0, le=12)
    point: Decimal | None = Field(default=None, ge=0)
    tick_size: Decimal | None = Field(default=None, ge=0)
    trade_mode: str | None = Field(default=None, max_length=32)
    filling_modes: list[str] | None = None
    stops_level: int | None = Field(default=None, ge=0)
    freeze_level: int | None = Field(default=None, ge=0)


class SymbolsIn(BaseModel):
    symbols: list[SymbolSpecIn] = Field(max_length=5000)


class PositionIn(BaseModel):
    position_ticket: int
    position_id: int
    symbol: str = Field(min_length=1, max_length=64)
    type: Literal["buy", "sell"]
    volume: Decimal = Field(gt=0)
    price_open: Decimal | None = None
    sl: Decimal | None = None
    tp: Decimal | None = None
    magic: int = 0
    comment: str = Field(default="", max_length=64)
    time_msc: int | None = None


class SnapshotIn(BaseModel):
    session_id: str = Field(min_length=1, max_length=64)
    epoch: int
    seq: int = Field(ge=1)
    taken_at: int = Field(ge=0)
    ea_clock_offset_ms: int = 0
    connected: bool
    login: int
    server: str = Field(min_length=1, max_length=128)
    history_synced: bool
    positions: list[PositionIn] = Field(default_factory=list, max_length=2000)
    # Reported but ignored for fan-out in Phase 1 (5.3a).
    pending: list[dict[str, Any]] = Field(default_factory=list, max_length=2000)
    # Exit/inout deals: fast close, reversal and processed_deals dedup (5.4, 5.6).
    history: list[dict[str, Any]] = Field(default_factory=list, max_length=5000)


ResultStatus = Literal["in_progress", "done", "done_partial", "closed", "failed", "expired", "not_executed",
                       "uncertain", "skipped", "notmodify"]


class ResultIn(BaseModel):
    """One journal result (4.3, 4.6). `attempt_id` defaults to the command's current attempt."""

    model_config = ConfigDict(extra="ignore")
    command_id: str = Field(min_length=1, max_length=40)
    attempt_id: str | None = Field(default=None, max_length=40)
    copy_id: int | None = None
    status: ResultStatus
    order: int | None = None
    deal: int | None = None
    request_id: int | None = None
    position_ticket: int | None = None
    position_id: int | None = None
    symbol: str | None = Field(default=None, max_length=64)
    volume: Decimal | None = None
    executed_volume: Decimal | None = None
    residual_volume: Decimal | None = None
    price: Decimal | None = None
    sl: Decimal | None = None
    tp: Decimal | None = None
    profit: Decimal | None = None
    commission: Decimal | None = None
    swap: Decimal | None = None
    close_reason: str | None = Field(default=None, max_length=64)
    executed_at: int | None = None
    error_code: str | None = Field(default=None, max_length=64)
    message: str | None = Field(default=None, max_length=512)


class ResultsIn(BaseModel):
    results: list[ResultIn] = Field(max_length=50)


def _locked_account(s: Session, acct: Account) -> Account:
    """Postgres: row lock on the account serializes this producer's units of work (D6).
    SQLite: BEGIN IMMEDIATE already holds the write lock; FOR UPDATE is not rendered."""
    return s.scalars(select(Account).where(Account.id == acct.id).with_for_update()
                     .execution_options(populate_existing=True)).one()


def _require_role(acct: Account, role: str) -> None:
    if acct.role != role:
        raise ApiError(403, "wrong_role", f"this route is for {role} accounts")


async def _mutating(request: Request, route: str) -> tuple[str, bytes, str]:
    key = idem.request_key(request)
    body = await request.body()
    return key, body, idem.request_hash(request.method, route, body)


@router.post("/session", status_code=201)
async def new_session(body: SessionIn, request: Request):
    """Server-issued session (C4): retires the previous one; seq restarts at 1."""
    settings = settings_of(request)
    key, _raw, req_hash = await _mutating(request, "/v4/session")

    def work(s: Session):
        acct = _locked_account(s, authenticate(s, request, settings).account)
        replay = idem.lookup(s, account_id=acct.id, key=key, route="/v4/session", req_hash=req_hash,
                             ttl_hours=settings.idempotency_ttl_hours)
        if replay is not None:
            return replay
        now = utcnow()
        for old in s.scalars(select(SessionRow).where(SessionRow.account_id == acct.id,
                                                      SessionRow.retired_at.is_(None))):
            old.retired_at = now
        epoch = (s.scalar(select(func.max(SessionRow.epoch)).where(SessionRow.account_id == acct.id)) or 0) + 1
        sid = "s_" + uuid.uuid4().hex
        s.add(SessionRow(id=sid, account_id=acct.id, epoch=epoch, boot_nonce=body.boot_nonce, created_at=now))
        acct.session_id, acct.session_epoch, acct.last_seq = sid, epoch, 0
        acct.session_taken_at = None
        released = cmds.release_leases(s, acct.id) if acct.role == "slave" else 0
        s.add(Event(type="account.session_started", payload={
            "account_id": acct.id, "session_id": sid, "epoch": epoch,
            "ea_clock_offset_ms": body.ea_clock_offset_ms, "released_leases": released}))
        resp = {"session_id": sid, "epoch": epoch}
        idem.record(s, account_id=acct.id, key=key, route="/v4/session", req_hash=req_hash, status_code=201,
                    response=resp, token_bearing=False)
        return json_response(resp, 201)

    return await run_in_threadpool(uow, request, work)


@router.put("/symbols", status_code=204)
async def put_symbols(body: SymbolsIn, request: Request):
    settings = settings_of(request)
    key, _raw, req_hash = await _mutating(request, "/v4/symbols")

    def work(s: Session):
        acct = authenticate(s, request, settings).account
        replay = idem.lookup(s, account_id=acct.id, key=key, route="/v4/symbols", req_hash=req_hash,
                             ttl_hours=settings.idempotency_ttl_hours)
        if replay is not None:
            return replay
        now = utcnow()
        for spec in body.symbols:
            row = s.get(SymbolSpec, (acct.id, spec.name))
            if row is None:
                row = SymbolSpec(account_id=acct.id, symbol=spec.name)
                s.add(row)
            for field in ("volume_min", "volume_step", "volume_max", "contract_size", "digits", "point",
                          "tick_size", "trade_mode", "filling_modes", "stops_level", "freeze_level"):
                setattr(row, field, getattr(spec, field))
            row.updated_at = now
        idem.record(s, account_id=acct.id, key=key, route="/v4/symbols", req_hash=req_hash, status_code=204,
                    response=None, token_bearing=False)
        return Response(status_code=204)

    return await run_in_threadpool(uow, request, work)


def _session_problem(s: Session, acct: Account, body: SnapshotIn) -> str | None:
    """None when the snapshot belongs to the account's current session; else why it is stale (C4)."""
    if acct.session_id is None or body.session_id != acct.session_id or body.epoch != acct.session_epoch:
        row = s.get(SessionRow, body.session_id)
        if row is None or row.account_id != acct.id:
            return "unknown_session"
        return "retired_session"
    return None


def _snapshot_refusal(s: Session, acct: Account, body: SnapshotIn, route: str, raw_body: bytes, settings,
                      key: str, req_hash: str):
    """Login/server check (409 account_mismatch), session fencing (409 stale_session) and seq
    ordering (200 accepted:false), shared by master and slave snapshots (4.3, 5.6)."""
    if body.login != acct.login or normalize_server(body.server) != acct.broker_server_norm:
        # 409, no snapshot state stored; the error is deduplicated by signature (5.9).
        rawstore.record_error(s, account_id=acct.id, route=route, error_class="account_mismatch",
                              cause=f"{body.login}@{normalize_server(body.server)}", body=raw_body,
                              quota_mb=settings.raw_daily_quota_mb)
        s.add(Event(type="account.mismatch", payload={"account_id": acct.id, "login": body.login,
                                                      "server": body.server}))
        return ApiError(409, "account_mismatch",
                        "snapshot login/server differ from the token's account").response()

    if (problem := _session_problem(s, acct, body)) is not None:
        rawstore.record_error(s, account_id=acct.id, route=route, error_class="stale_session",
                              cause=problem, body=raw_body, quota_mb=settings.raw_daily_quota_mb)
        return ApiError(409, "stale_session", f"{problem}: request a new session").response()

    if body.seq <= (acct.last_seq or 0):
        resp = {"accepted": False, "seq": acct.last_seq}
        idem.record(s, account_id=acct.id, key=key, route=route, req_hash=req_hash, status_code=200,
                    response=resp, token_bearing=False)
        return json_response(resp)

    return None


@router.post("/master/snapshot")
async def master_snapshot(body: SnapshotIn, request: Request):
    settings = settings_of(request)
    route = "/v4/master/snapshot"
    key, raw_body, req_hash = await _mutating(request, route)

    def work(s: Session):
        acct = authenticate(s, request, settings).account
        _require_role(acct, "master")
        acct = _locked_account(s, acct)
        replay = idem.lookup(s, account_id=acct.id, key=key, route=route, req_hash=req_hash,
                             ttl_hours=settings.idempotency_ttl_hours)
        if replay is not None:
            return replay

        if (refused := _snapshot_refusal(s, acct, body, route, raw_body, settings, key, req_hash)) is not None:
            return refused

        acct.last_seq = body.seq
        acct.session_taken_at = _ms_to_dt(body.taken_at)
        positions = [PositionData(**p.model_dump()) for p in body.positions]
        stats: dict = {}
        if body.connected:
            fan_out = acct.status != "suspended" and not version_gated(acct, settings)
            stats = process_master_snapshot(
                s, acct, positions, body.history, history_synced=body.history_synced,
                ea_clock_offset_ms=body.ea_clock_offset_ms, fan_out=fan_out, rules=_close_rules(settings),
                ctx=_ctx(settings, clock=request.app.state.clock))
        # connected=false: seq advances but positions are not acted on and absence is neither counted
        # nor reset (5.6: a disconnected terminal's view is not evidence).

        state = {"connected": body.connected, "positions": sorted(
            (p.position_id, p.position_ticket, p.symbol, p.type, str(p.volume), str(p.sl), str(p.tp))
            for p in body.positions),
            "pending": sorted(str(sorted(o.items())) for o in body.pending),
            "deals": sorted(str(h.get("deal")) for h in body.history)}
        rawstore.store_snapshot_raw(s, account_id=acct.id, kind="master_snapshot", body=raw_body, state=state,
                                    quota_mb=settings.raw_daily_quota_mb)
        resp = {"accepted": True, "seq": body.seq, **({"fanout": stats} if stats else {})}
        idem.record(s, account_id=acct.id, key=key, route=route, req_hash=req_hash, status_code=200,
                    response=resp, token_bearing=False)
        return json_response(resp)

    return await run_in_threadpool(uow, request, work)


def _ms_to_dt(value: int) -> datetime:
    return datetime.fromtimestamp(value / 1000, tz=UTC)


@router.get("/slave/commands")
async def slave_commands(request: Request, after: str | None = None):
    """Un-acked commands for this slave (4.5). `after` is a hint only: never hides an un-acked command."""
    settings = settings_of(request)

    def work(s: Session):
        acct = authenticate(s, request, settings).account
        _require_role(acct, "slave")
        now = utcnow()
        cmds.expire_opens(s, acct.id, now, ctx=_ctx(settings, now))
        out = cmds.deliver(s, acct.id, now)
        return json_response({"commands": [cmds.command_json(c) for c in out], "cursor": cmds.cursor_for(s, acct.id)})

    return await run_in_threadpool(uow, request, work)


def _ctx(settings, now: datetime | None = None, clock=None) -> Ctx:
    return Ctx(open_ttl_seconds=settings.open_ttl_seconds, lease_seconds=settings.command_lease_seconds,
               gated=lambda a: version_gated(a, settings), now=now or utcnow(),
               mono=clock.monotonic() if clock is not None else 0.0,
               server_epoch=clock.epoch if clock is not None else "")


def _close_rules(settings) -> CloseRules:
    return CloseRules(absent_snapshots=settings.close_absent_snapshots,
                      absent_seconds=settings.close_absent_seconds, mass_min=settings.mass_disappear_min,
                      mass_seconds=settings.mass_disappear_seconds)


@router.post("/slave/results")
async def slave_results(body: ResultsIn, request: Request):
    """Results outbox (4.5, 4.6, 5.5). Applied once per (command_id, attempt_id); unknown or foreign
    commands/attempts are answered in `unknown` (never 404). Results are not session-fenced: the
    EA's durable outbox replays them across restarts."""
    settings = settings_of(request)
    route = "/v4/slave/results"
    key, raw_body, req_hash = await _mutating(request, route)

    def work(s: Session):
        acct = authenticate(s, request, settings).account
        _require_role(acct, "slave")
        acct = _locked_account(s, acct)
        replay = idem.lookup(s, account_id=acct.id, key=key, route=route, req_hash=req_hash,
                             ttl_hours=settings.idempotency_ttl_hours)
        if replay is not None:
            return replay
        if any(r.status != "in_progress" for r in body.results):  # results always stored (5.9)
            rawstore.store_raw(s, account_id=acct.id, kind="slave_results", body=raw_body, reason="change",
                               quota_mb=settings.raw_daily_quota_mb)
        out = apply_results(s, acct.id, [r.model_dump() for r in body.results], _ctx(settings))
        resp = {"unknown": out.unknown, "applied": out.applied, "duplicates": out.duplicates}
        idem.record(s, account_id=acct.id, key=key, route=route, req_hash=req_hash, status_code=200,
                    response=resp, token_bearing=False)
        return json_response(resp)

    return await run_in_threadpool(uow, request, work)


@router.post("/slave/snapshot")
async def slave_snapshot(body: SnapshotIn, request: Request):
    """Slave positions + recent history (4.3): same fencing as the master snapshot, then
    reconciliation and adoption (5.5, 5.8). Nothing is acted on while `connected=false`."""
    settings = settings_of(request)
    route = "/v4/slave/snapshot"
    key, raw_body, req_hash = await _mutating(request, route)

    def work(s: Session):
        acct = authenticate(s, request, settings).account
        _require_role(acct, "slave")
        acct = _locked_account(s, acct)
        replay = idem.lookup(s, account_id=acct.id, key=key, route=route, req_hash=req_hash,
                             ttl_hours=settings.idempotency_ttl_hours)
        if replay is not None:
            return replay
        if (refused := _snapshot_refusal(s, acct, body, route, raw_body, settings, key, req_hash)) is not None:
            return refused

        acct.last_seq = body.seq
        acct.session_taken_at = _ms_to_dt(body.taken_at)
        ctx = _ctx(settings)
        stats: dict = {}
        if body.connected:
            cmds.renew_leases(s, acct.id, settings.command_lease_seconds, ctx.now)
            positions = [PositionData(**p.model_dump()) for p in body.positions]
            stats = reconcile_slave(s, acct, positions, body.history, history_synced=body.history_synced, ctx=ctx)
        state = {"connected": body.connected, "positions": sorted(
            (p.position_id, p.position_ticket, p.symbol, p.type, str(p.volume), p.comment, p.magic)
            for p in body.positions), "deals": sorted(str(h.get("deal")) for h in body.history)}
        rawstore.store_snapshot_raw(s, account_id=acct.id, kind="slave_snapshot", body=raw_body, state=state,
                                    quota_mb=settings.raw_daily_quota_mb)
        resp = {"accepted": True, "seq": body.seq, **({"reconcile": stats} if stats else {})}
        idem.record(s, account_id=acct.id, key=key, route=route, req_hash=req_hash, status_code=200,
                    response=resp, token_bearing=False)
        return json_response(resp)

    return await run_in_threadpool(uow, request, work)
