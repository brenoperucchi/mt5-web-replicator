"""Admin API for copy configuration and debugging (Phase 1 / PR 2).

Groups (≈ Rails traces), links with config-time validation (5.3: hedging master → netting
slave 422, cycles 422, netting filter overlap 422, contract size 5.4), symbol maps (7.1, two
partial unique indexes → 409 map_conflict), and read-only listings of copies and commands.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Literal

from fastapi import APIRouter, Request
from fastapi.responses import Response
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..auth import authenticate_admin
from ..deps import settings_of, uow
from ..engine.commands import command_json
from ..engine.validation import contract_size_conflict, link_problem, netting_overlap
from ..errors import ApiError, json_response
from ..models import Account, Command, Copy, CopyGroup, CopyLink, Event, SymbolMap

router = APIRouter(prefix="/admin")


def conflict(reason: str) -> ApiError:
    return ApiError(422, "config_conflict", reason)


def _s(v):
    return str(v) if isinstance(v, Decimal) else v


class GroupIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    master_id: int
    name: str = Field(min_length=1, max_length=128)
    enabled: bool = True
    magic_allow: list[int] | None = None
    symbol_filter: list[str] | None = None


class GroupPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str | None = Field(default=None, min_length=1, max_length=128)
    enabled: bool | None = None
    magic_allow: list[int] | None = None
    symbol_filter: list[str] | None = None


LINK_FIELDS = ("enabled", "lot_mode", "lot_value", "below_min", "allow_contract_size_diff", "magic_mode",
               "magic_value", "max_slippage_points", "max_entry_deviation_points", "copy_sl_tp")


class LinkParams(BaseModel):
    # extra="forbid": `copy_pending` (and anything unknown) is rejected with 422 (5.3a).
    model_config = ConfigDict(extra="forbid")
    enabled: bool | None = None
    lot_mode: Literal["master", "multiplier", "fixed", "min_lot_x"] | None = None
    lot_value: Decimal | None = Field(default=None, gt=0)
    below_min: Literal["skip", "open_min"] | None = None
    allow_contract_size_diff: bool | None = None
    magic_mode: Literal["same", "fixed"] | None = None
    magic_value: int | None = None
    max_slippage_points: int | None = Field(default=None, ge=0)
    max_entry_deviation_points: int | None = Field(default=None, ge=0)
    copy_sl_tp: bool | None = None


class LinkIn(LinkParams):
    group_id: int
    slave_id: int


class MapIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    slave_id: int | None = None
    master_symbol: str = Field(min_length=1, max_length=64)
    slave_symbol: str = Field(min_length=1, max_length=64)


class MapPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    slave_symbol: str = Field(min_length=1, max_length=64)


def group_json(g: CopyGroup) -> dict:
    return {"id": g.id, "master_id": g.master_id, "name": g.name, "enabled": g.enabled,
            "magic_allow": g.magic_allow, "symbol_filter": g.symbol_filter}


def link_json(lk: CopyLink) -> dict:
    return {"id": lk.id, "group_id": lk.group_id, "master_id": lk.master_id, "slave_id": lk.slave_id,
            "disabled_reason": lk.disabled_reason, **{f: _s(getattr(lk, f)) for f in LINK_FIELDS}}


def map_json(m: SymbolMap) -> dict:
    return {"id": m.id, "slave_id": m.slave_id, "master_symbol": m.master_symbol, "slave_symbol": m.slave_symbol}


COPY_FIELDS = ("id", "link_id", "master_position_id", "slave_id", "slave_margin_mode", "symbol_master",
               "symbol_local", "volume", "sl", "tp", "state", "blocked_by", "skip_reason", "close_reason",
               "close_intent", "exec_params", "position_id", "opened_volume", "reduction_target",
               "position_ticket", "confirmed_volume", "open_order",
               "open_deal", "close_deal", "price_open", "price_close", "profit", "fee", "no_sltp",
               "notmodify_count", "created_at")


def copy_json(c: Copy) -> dict:
    out = {f: _s(getattr(c, f)) for f in COPY_FIELDS}
    out["created_at"] = c.created_at.isoformat() if c.created_at else None
    return out


def _get(s: Session, model, ident, what: str):
    row = s.get(model, ident)
    if row is None:
        raise ApiError(404, "not_found", f"{what} not found")
    return row


def _check_lot(lk: CopyLink) -> None:
    if lk.lot_mode in ("multiplier", "fixed", "min_lot_x") and not lk.lot_value:
        raise ApiError(422, "validation", f"lot_value is required for lot_mode={lk.lot_mode}")
    if lk.magic_mode == "fixed" and lk.magic_value is None:
        raise ApiError(422, "validation", "magic_value is required for magic_mode=fixed")


def _revalidate_slave(s: Session, slave_id: int | None) -> None:
    """After a map change: netting overlap and contract size of every enabled link touching it."""
    q = select(CopyLink).where(CopyLink.enabled.is_(True))
    if slave_id is not None:
        q = q.where(CopyLink.slave_id == slave_id)
    links = s.scalars(q).all()
    for slave in {lk.slave_id for lk in links}:
        acct = s.get(Account, slave)
        if (reason := netting_overlap(s, acct)) is not None:
            raise conflict(reason)
    for lk in links:
        if (reason := contract_size_conflict(s, lk, s.get(Account, lk.master_id),
                                             s.get(Account, lk.slave_id))) is not None:
            raise conflict(reason)


# --- groups -----------------------------------------------------------------------------------

@router.post("/groups", status_code=201)
def create_group(body: GroupIn, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings)
        master = _get(s, Account, body.master_id, "master account")
        if master.role != "master":
            raise conflict("group master must be a master account")
        g = CopyGroup(**body.model_dump())
        s.add(g)
        s.flush()
        return json_response(group_json(g), 201)

    return uow(request, work)


@router.get("/groups")
def list_groups(request: Request, master_id: int | None = None):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings, scope="readonly")
        q = select(CopyGroup).order_by(CopyGroup.id)
        if master_id is not None:
            q = q.where(CopyGroup.master_id == master_id)
        return json_response({"groups": [group_json(g) for g in s.scalars(q)]})

    return uow(request, work)


@router.patch("/groups/{group_id}")
def patch_group(group_id: int, body: GroupPatch, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings)
        g = _get(s, CopyGroup, group_id, "group")
        for k, v in body.model_dump(exclude_unset=True).items():
            setattr(g, k, v)
        s.flush()
        for lk in s.scalars(select(CopyLink).where(CopyLink.group_id == g.id, CopyLink.enabled.is_(True))):
            if (reason := link_problem(s, lk, g)) is not None:
                raise conflict(reason)
        return json_response(group_json(g))

    return uow(request, work)


# --- links ------------------------------------------------------------------------------------

@router.post("/links", status_code=201)
def create_link(body: LinkIn, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings)
        g = _get(s, CopyGroup, body.group_id, "group")
        _get(s, Account, body.slave_id, "slave account")
        dup = s.scalar(select(CopyLink.id).where(CopyLink.group_id == g.id, CopyLink.slave_id == body.slave_id))
        if dup is not None:
            raise ApiError(409, "link_exists", "this group already links that slave")
        params = {k: v for k, v in body.model_dump(exclude={"group_id", "slave_id"}).items() if v is not None}
        lk = CopyLink(group_id=g.id, master_id=g.master_id, slave_id=body.slave_id, **params)
        for f, default in (("enabled", True), ("lot_mode", "master"), ("below_min", "skip"),
                           ("allow_contract_size_diff", False), ("magic_mode", "same"), ("copy_sl_tp", True)):
            if getattr(lk, f) is None:
                setattr(lk, f, default)
        _check_lot(lk)
        if (reason := link_problem(s, lk, g)) is not None:
            raise conflict(reason)
        s.add(lk)
        s.flush()
        return json_response(link_json(lk), 201)

    return uow(request, work)


@router.get("/links")
def list_links(request: Request, master_id: int | None = None, slave_id: int | None = None):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings, scope="readonly")
        q = select(CopyLink).order_by(CopyLink.id)
        if master_id is not None:
            q = q.where(CopyLink.master_id == master_id)
        if slave_id is not None:
            q = q.where(CopyLink.slave_id == slave_id)
        return json_response({"links": [link_json(lk) for lk in s.scalars(q)]})

    return uow(request, work)


@router.patch("/links/{link_id}")
def patch_link(link_id: int, body: LinkParams, request: Request):
    """Parameter changes apply to new copies only; existing copies keep their frozen exec_params (C6).
    TODO(PR: drain/link disable): disabling a link supersedes proven-unsent opens (6.2, C6)."""
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings)
        lk = _get(s, CopyLink, link_id, "link")
        for k, v in body.model_dump(exclude_unset=True).items():
            setattr(lk, k, v)
        if body.enabled:
            lk.disabled_reason = None
        _check_lot(lk)
        if (reason := link_problem(s, lk, s.get(CopyGroup, lk.group_id))) is not None:
            raise conflict(reason)
        s.add(Event(type="link.updated", payload={"link_id": lk.id,
                                                  "fields": sorted(body.model_dump(exclude_unset=True))}))
        return json_response(link_json(lk))

    return uow(request, work)


# --- symbol maps ------------------------------------------------------------------------------

def _map_conflict() -> ApiError:
    return ApiError(409, "map_conflict", "a map for this master symbol already exists in this scope")


@router.post("/symbol_maps", status_code=201)
def create_map(body: MapIn, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings)
        if body.slave_id is not None and _get(s, Account, body.slave_id, "slave account").role != "slave":
            raise conflict("symbol maps apply to slave accounts")
        same_scope = (SymbolMap.slave_id == body.slave_id) if body.slave_id is not None \
            else SymbolMap.slave_id.is_(None)
        if s.scalar(select(SymbolMap.id).where(same_scope, SymbolMap.master_symbol == body.master_symbol)):
            raise _map_conflict()
        m = SymbolMap(**body.model_dump())
        try:
            with s.begin_nested():
                s.add(m)
                s.flush()
        except IntegrityError as exc:  # concurrent insert: the partial unique index decides
            raise _map_conflict() from exc
        _revalidate_slave(s, body.slave_id)
        return json_response(map_json(m), 201)

    return uow(request, work)


@router.get("/symbol_maps")
def list_maps(request: Request, slave_id: int | None = None):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings, scope="readonly")
        q = select(SymbolMap).order_by(SymbolMap.id)
        if slave_id is not None:
            q = q.where(SymbolMap.slave_id == slave_id)
        return json_response({"symbol_maps": [map_json(m) for m in s.scalars(q)]})

    return uow(request, work)


@router.patch("/symbol_maps/{map_id}")
def patch_map(map_id: int, body: MapPatch, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings)
        m = _get(s, SymbolMap, map_id, "symbol map")
        m.slave_symbol = body.slave_symbol
        s.flush()
        _revalidate_slave(s, m.slave_id)
        return json_response(map_json(m))

    return uow(request, work)


@router.delete("/symbol_maps/{map_id}", status_code=204)
def delete_map(map_id: int, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings)
        m = _get(s, SymbolMap, map_id, "symbol map")
        slave_id = m.slave_id
        s.delete(m)
        s.flush()
        _revalidate_slave(s, slave_id)
        return Response(status_code=204)

    return uow(request, work)


# --- debugging listings -----------------------------------------------------------------------

@router.get("/copies")
def list_copies(request: Request, slave_id: int | None = None, link_id: int | None = None,
                state: str | None = None, limit: int = 200):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings, scope="readonly")
        q = select(Copy).order_by(Copy.id.desc()).limit(min(max(limit, 1), 1000))
        if slave_id is not None:
            q = q.where(Copy.slave_id == slave_id)
        if link_id is not None:
            q = q.where(Copy.link_id == link_id)
        if state is not None:
            q = q.where(Copy.state == state)
        return json_response({"copies": [copy_json(c) for c in s.scalars(q)]})

    return uow(request, work)


@router.get("/commands")
def list_commands(request: Request, slave_id: int | None = None, copy_id: int | None = None,
                  state: str | None = None, limit: int = 200):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings, scope="readonly")
        q = select(Command).join(Copy, Command.copy_id == Copy.id).order_by(Command.issued_at.desc())
        q = q.limit(min(max(limit, 1), 1000))
        if slave_id is not None:
            q = q.where(Copy.slave_id == slave_id)
        if copy_id is not None:
            q = q.where(Command.copy_id == copy_id)
        if state is not None:
            q = q.where(Command.state == state)
        return json_response({"commands": [{**command_json(c), "state": c.state,
                                            "lease_until": c.lease_until.isoformat() if c.lease_until else None}
                                           for c in s.scalars(q)]})

    return uow(request, work)
