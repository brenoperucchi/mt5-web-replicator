"""Master snapshot processing (design 4.3, 5.2-5.5): new positions → copies + open commands.

Scope of Phase 1 / PR 2: only NEW master positions are fanned out. SL/TP modifies, partial
reductions, reversal, fast close by history and the absence path come in later PRs (hooks are
marked TODO below). Business conflicts never raise: each copy gets its own state + event (D6).
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..models import (
    Account,
    Copy,
    CopyGroup,
    CopyLink,
    Event,
    MasterPosition,
    SymbolConflict,
    SymbolSpec,
    utcnow,
)
from . import commands as cmds
from .lots import calc_lot
from .symbols import resolve_symbol

NETTING_RESERVING = ("pending", "open", "cancel_requested", "closing", "uncertain")
# A predecessor of the same link in these states is being taken off the slot (close-then-reopen, 5.3).
LEAVING_SLOT = ("closing", "cancel_requested")
COPIER_COMMENT = re.compile(r"^c(\d+)$")


@dataclass
class PositionData:
    position_ticket: int
    position_id: int
    symbol: str
    type: str
    volume: Decimal
    price_open: Decimal | None
    sl: Decimal | None
    tp: Decimal | None
    magic: int
    comment: str
    time_msc: int | None


def account_drained(acct: Account, gated: bool) -> bool:
    return acct.status == "suspended" or gated


def is_copier_position(s: Session, master: Account, pos: PositionData) -> bool:
    """`exclude_copier_positions` (5.3): comment `c<id>` of a copy whose slave is this same terminal
    (same broker server + login) and whose frozen magic matches."""
    m = COPIER_COMMENT.match(pos.comment or "")
    if not m:
        return False
    copy = s.get(Copy, int(m.group(1)))
    if copy is None:
        return False
    slave = s.get(Account, copy.slave_id)
    if slave is None or (slave.broker_server_norm, slave.login) != (master.broker_server_norm, master.login):
        return False
    return (copy.exec_params or {}).get("magic") == pos.magic


def process_master_positions(s: Session, master: Account, positions: list[PositionData], *,
                             open_ttl_seconds: int, fan_out: bool, gated) -> dict:
    """Create master_positions for new position ids and fan them out. Returns counters."""
    stats = {"new_positions": 0, "copies": 0, "opens": 0, "skipped": 0, "blocked": 0, "ignored": 0}
    for pos in positions:
        if master.exclude_copier_positions and is_copier_position(s, master, pos):
            stats["ignored"] += 1
            continue
        current = s.scalar(select(MasterPosition).where(
            MasterPosition.master_id == master.id, MasterPosition.position_id == pos.position_id,
            MasterPosition.state == "open").order_by(MasterPosition.generation.desc()).limit(1))
        if current is not None:
            current.position_ticket = pos.position_ticket
            # TODO(PR: modify/partials/reversal): SL/TP change → modify (5.5); same side lower volume →
            # reduction (5.4); side change → reversal (new generation, 5.4).
            continue
        known = s.scalar(select(MasterPosition.id).where(
            MasterPosition.master_id == master.id, MasterPosition.position_id == pos.position_id).limit(1))
        if known is not None:
            # A closed position id reappearing is not re-copied here (reversal creates generations
            # explicitly in a later PR).
            continue
        mp = MasterPosition(master_id=master.id, position_id=pos.position_id, generation=0,
                            position_ticket=pos.position_ticket, symbol=pos.symbol, type=pos.type,
                            volume=pos.volume, opened_volume=pos.volume, price_open=pos.price_open,
                            sl=pos.sl, tp=pos.tp, magic=pos.magic, comment=pos.comment, state="open",
                            opened_at=utcnow())
        s.add(mp)
        s.flush()
        stats["new_positions"] += 1
        s.add(Event(type="master_position.opened", payload={
            "master_id": master.id, "master_position_id": mp.id, "position_id": pos.position_id,
            "generation": 0, "symbol": pos.symbol, "type": pos.type, "volume": str(pos.volume)}))
        if not fan_out:
            s.add(Event(type="master_position.not_fanned_out",
                        payload={"master_position_id": mp.id, "reason": "master_drain"}))
            continue
        for link in enabled_links(s, master.id):
            fan_out_one(s, master, mp, link, open_ttl_seconds=open_ttl_seconds, gated=gated, stats=stats)
    # TODO(PR: close detection): positions absent from this snapshot → fast path by history exit
    # deal / guarded absence path (5.6).
    return stats


def enabled_links(s: Session, master_id: int) -> list[tuple[CopyLink, CopyGroup]]:
    rows = s.execute(select(CopyLink, CopyGroup).join(CopyGroup, CopyLink.group_id == CopyGroup.id).where(
        CopyLink.master_id == master_id, CopyLink.enabled.is_(True), CopyGroup.enabled.is_(True))
        .order_by(CopyLink.id)).all()
    return [(lk, g) for lk, g in rows]


def _skip(s: Session, copy: Copy, reason: str, event: str, stats: dict, **extra) -> Copy:
    copy.state = "skipped"
    copy.skip_reason = reason
    s.add(copy)
    s.flush()
    s.add(Event(type=event, payload={"copy_id": copy.id, "link_id": copy.link_id, "slave_id": copy.slave_id,
                                     "reason": reason, **extra}))
    stats["copies"] += 1
    stats["skipped"] += 1
    return copy


def fan_out_one(s: Session, master: Account, mp: MasterPosition, pair: tuple[CopyLink, CopyGroup], *,
                open_ttl_seconds: int, gated, stats: dict) -> Copy | None:
    link, group = pair
    slave = s.get(Account, link.slave_id)
    if slave is None or slave.status == "revoked" or slave.margin_mode not in ("hedging", "netting"):
        reason = "slave_revoked" if slave is not None and slave.status == "revoked" else "slave_not_enrolled"
        s.add(Event(type="copy.not_created", payload={"link_id": link.id, "master_position_id": mp.id,
                                                      "reason": reason}))
        return None

    symbol_local = resolve_symbol(s, slave.id, mp.symbol)
    magic = link.magic_value if link.magic_mode == "fixed" else mp.magic
    copy = Copy(link_id=link.id, master_position_id=mp.id, slave_id=slave.id, slave_margin_mode=slave.margin_mode,
                symbol_master=mp.symbol, symbol_local=symbol_local, state="pending")

    # Filters (group = Rails trace): magic allow-list, master symbol allow-list.
    if group.magic_allow and mp.magic not in group.magic_allow:
        return _skip(s, copy, "filtered_magic", "copy.skipped", stats)
    if group.symbol_filter and mp.symbol not in group.symbol_filter:
        return _skip(s, copy, "filtered_symbol", "copy.skipped", stats)
    if account_drained(slave, gated(slave)):
        return _skip(s, copy, "account_drain", "copy.skipped", stats)

    sspec = s.get(SymbolSpec, (slave.id, symbol_local))
    mspec = s.get(SymbolSpec, (master.id, mp.symbol))
    if sspec is None:
        return _skip(s, copy, "missing_symbol_spec", "copy.skipped", stats, symbol=symbol_local)
    mcs, scs = (mspec.contract_size if mspec else None), sspec.contract_size
    if (link.lot_mode in ("master", "multiplier") and mcs and scs and Decimal(mcs) != Decimal(scs)
            and not link.allow_contract_size_diff):
        return _skip(s, copy, "contract_size_mismatch", "copy.skipped", stats,
                     master_contract_size=str(mcs), slave_contract_size=str(scs))
    lot = calc_lot(lot_mode=link.lot_mode, lot_value=link.lot_value, master_volume=mp.volume,
                   below_min=link.below_min, volume_min=sspec.volume_min, volume_step=sspec.volume_step,
                   volume_max=sspec.volume_max, master_contract_size=mcs, slave_contract_size=scs)
    if lot.volume is None:
        event = "copy.skipped_below_min" if lot.skip_reason == "below_min" else "copy.skipped"
        return _skip(s, copy, lot.skip_reason or "lot", event, stats,
                     raw=str(lot.raw) if lot.raw is not None else None)
    copy.volume = copy.opened_volume = lot.volume

    # Open symbol conflict blocks new opens on that slave symbol (5.8, C8).
    conflict = s.scalar(select(SymbolConflict.id).where(
        SymbolConflict.slave_id == slave.id, SymbolConflict.symbol_local == symbol_local,
        SymbolConflict.resolved_at.is_(None)).limit(1))
    if conflict is not None:
        return _skip(s, copy, "netting_conflict", "copy.skipped_netting_conflict", stats, symbol_conflict=conflict)

    if slave.margin_mode == "netting":
        holder = s.scalar(select(Copy).where(
            Copy.slave_id == slave.id, Copy.symbol_local == symbol_local, Copy.slave_margin_mode == "netting",
            Copy.state.in_(NETTING_RESERVING) | ((Copy.state == "superseded") & Copy.close_intent)).limit(1))
        if holder is not None:
            if holder.link_id == link.id and holder.state in LEAVING_SLOT:
                copy.state = "pending_blocked"
                copy.blocked_by = holder.id
                copy.sl, copy.tp = (mp.sl, mp.tp) if link.copy_sl_tp else (None, None)
                s.add(copy)
                s.flush()
                s.add(Event(type="copy.pending_blocked", payload={"copy_id": copy.id, "blocked_by": holder.id}))
                stats["copies"] += 1
                stats["blocked"] += 1
                # TODO(PR: netting successor): promotion on zero-exposure proof of `holder` (C5).
                return copy
            return _skip(s, copy, "netting_conflict", "copy.skipped_netting_conflict", stats,
                         blocking_copy_id=holder.id, symbol=symbol_local)

    copy.sl, copy.tp = (mp.sl, mp.tp) if link.copy_sl_tp else (None, None)
    try:
        with s.begin_nested():
            s.add(copy)
            s.flush()
    except IntegrityError:
        # Reservation race with a concurrent change: per-copy skip, never a rollback (5.3 runtime #2).
        copy = Copy(link_id=link.id, master_position_id=mp.id, slave_id=slave.id,
                    slave_margin_mode=slave.margin_mode, symbol_master=mp.symbol, symbol_local=symbol_local)
        return _skip(s, copy, "netting_conflict", "copy.skipped_netting_conflict", stats, symbol=symbol_local)

    exec_params = {
        "symbol": symbol_local, "side": mp.type, "volume": str(lot.volume), "magic": magic,
        "comment": f"c{copy.id}", "max_slippage_points": link.max_slippage_points,
        "max_entry_deviation_points": link.max_entry_deviation_points,
        "master_price": str(mp.price_open) if mp.price_open is not None else None,
    }
    copy.exec_params = exec_params
    cmd = cmds.issue(s, copy, "open", {
        "symbol": symbol_local, "side": mp.type, "volume": lot.volume, "master_price": mp.price_open,
        "sl": copy.sl, "tp": copy.tp, "max_slippage_points": link.max_slippage_points,
        "max_entry_deviation_points": link.max_entry_deviation_points, "position_id": None,
        "magic": magic, "comment": f"c{copy.id}",
    }, ttl_seconds=open_ttl_seconds)
    s.add(Event(type="copy.pending", payload={"copy_id": copy.id, "command_id": cmd.id, "link_id": link.id,
                                              "slave_id": slave.id, "symbol": symbol_local,
                                              "volume": str(lot.volume)}))
    stats["copies"] += 1
    stats["opens"] += 1
    return copy
