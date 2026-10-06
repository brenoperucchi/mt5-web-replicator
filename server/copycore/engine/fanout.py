"""Fan-out of one master position to its links (design 5.2-5.4): admission, lots, open commands.

The master snapshot interpretation (new positions, SL/TP, reductions, reversal, close detection)
lives in `engine.master`. Business conflicts never raise: each copy gets its own state + event (D6).
"""

from __future__ import annotations

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
)
from . import commands as cmds
from . import correlation
from .lots import calc_lot
from .symbols import resolve_symbol

NETTING_RESERVING = ("pending", "open", "cancel_requested", "closing", "uncertain")
# A predecessor of the same link in these states is being taken off the slot (close-then-reopen, 5.3).
LEAVING_SLOT = ("closing", "cancel_requested")


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
    copy_id = correlation.candidate_copy_id(pos.comment)
    if copy_id is None:
        return False
    copy = s.get(Copy, copy_id)
    if copy is None:
        return False
    slave = s.get(Account, copy.slave_id)
    if slave is None or (slave.broker_server_norm, slave.login) != (master.broker_server_norm, master.login):
        return False
    return correlation.matches(copy.exec_params, copy.id, pos.comment, pos.magic)


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


def policy_check(s: Session, master: Account, mp: MasterPosition, link: CopyLink, group: CopyGroup,
                 slave: Account, symbol_local: str, gated) -> tuple[Decimal | None, tuple[str, str, dict] | None]:
    """Filters, drain, specs, contract size, lot policy and open symbol conflicts (5.3, 5.4, 5.8).

    Returns `(volume, None)` when the copy may open, else `(None, (skip_reason, event_type, extra))`.
    Used at fan-out and again when a blocked successor is promoted (C5/C6 revalidation)."""
    # Filters (group = Rails trace): magic allow-list, master symbol allow-list.
    if group.magic_allow and mp.magic not in group.magic_allow:
        return None, ("filtered_magic", "copy.skipped", {})
    if group.symbol_filter and mp.symbol not in group.symbol_filter:
        return None, ("filtered_symbol", "copy.skipped", {})
    if account_drained(slave, gated(slave)):
        return None, ("account_drain", "copy.skipped", {})

    sspec = s.get(SymbolSpec, (slave.id, symbol_local))
    mspec = s.get(SymbolSpec, (master.id, mp.symbol))
    if sspec is None:
        return None, ("missing_symbol_spec", "copy.skipped", {"symbol": symbol_local})
    mcs, scs = (mspec.contract_size if mspec else None), sspec.contract_size
    if (link.lot_mode in ("master", "multiplier") and mcs and scs and Decimal(mcs) != Decimal(scs)
            and not link.allow_contract_size_diff):
        return None, ("contract_size_mismatch", "copy.skipped",
                      {"master_contract_size": str(mcs), "slave_contract_size": str(scs)})
    lot = calc_lot(lot_mode=link.lot_mode, lot_value=link.lot_value, master_volume=mp.volume,
                   below_min=link.below_min, volume_min=sspec.volume_min, volume_step=sspec.volume_step,
                   volume_max=sspec.volume_max, master_contract_size=mcs, slave_contract_size=scs)
    if lot.volume is None:
        event = "copy.skipped_below_min" if lot.skip_reason == "below_min" else "copy.skipped"
        return None, (lot.skip_reason or "lot", event, {"raw": str(lot.raw) if lot.raw is not None else None})

    # Open symbol conflict blocks new opens on that slave symbol (5.8, C8).
    conflict = open_conflict(s, slave.id, symbol_local)
    if conflict is not None:
        return None, ("netting_conflict", "copy.skipped_netting_conflict", {"symbol_conflict": conflict})
    return lot.volume, None


def open_conflict(s: Session, slave_id: int, symbol_local: str) -> int | None:
    return s.scalar(select(SymbolConflict.id).where(
        SymbolConflict.slave_id == slave_id, SymbolConflict.symbol_local == symbol_local,
        SymbolConflict.resolved_at.is_(None)).limit(1))


def slot_holder(s: Session, slave_id: int, symbol_local: str, exclude_id: int | None = None) -> Copy | None:
    """The copy holding the netting reservation of (slave, symbol), if any (5.2)."""
    q = select(Copy).where(
        Copy.slave_id == slave_id, Copy.symbol_local == symbol_local, Copy.slave_margin_mode == "netting",
        Copy.state.in_(NETTING_RESERVING) | ((Copy.state == "superseded") & Copy.close_intent))
    if exclude_id is not None:
        q = q.where(Copy.id != exclude_id)
    return s.scalar(q.limit(1))


def still_exposed(copy: Copy | None) -> bool:
    """No proof of zero exposure yet (C5): the predecessor still blocks a successor."""
    if copy is None or copy.state in ("closed", "cancelled", "skipped", "error"):
        return False
    return copy.state != "superseded" or bool(copy.close_intent)


def fan_out_one(s: Session, master: Account, mp: MasterPosition, pair: tuple[CopyLink, CopyGroup], *,
                open_ttl_seconds: int, gated, stats: dict, predecessor: Copy | None = None) -> Copy | None:
    """One copy for one link. `predecessor` = this link's copy of the previous generation (reversal,
    5.4): the new side opens only after it proves zero exposure, on netting AND hedging slaves."""
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

    volume, skip = policy_check(s, master, mp, link, group, slave, symbol_local, gated)
    if skip is not None:
        reason, event, extra = skip
        return _skip(s, copy, reason, event, stats, **extra)
    copy.volume = copy.opened_volume = volume

    blocker = predecessor if still_exposed(predecessor) else None
    if blocker is None and slave.margin_mode == "netting":
        holder = slot_holder(s, slave.id, symbol_local)
        if holder is not None:
            if holder.link_id == link.id and (holder.state in LEAVING_SLOT or holder.close_intent):
                blocker = holder
            else:
                return _skip(s, copy, "netting_conflict", "copy.skipped_netting_conflict", stats,
                             blocking_copy_id=holder.id, symbol=symbol_local)
    if blocker is not None:
        copy.state = "pending_blocked"
        copy.blocked_by = blocker.id
        copy.sl, copy.tp = (mp.sl, mp.tp) if link.copy_sl_tp else (None, None)
        s.add(copy)
        s.flush()
        s.add(Event(type="copy.pending_blocked", payload={"copy_id": copy.id, "blocked_by": blocker.id}))
        stats["copies"] += 1
        stats["blocked"] += 1
        # Promoted by lifecycle.promote_successors once `blocker` proves zero exposure (C5).
        return copy

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

    issue_open(s, copy, mp, link, volume, magic=magic, ttl_seconds=open_ttl_seconds)
    stats["copies"] += 1
    stats["opens"] += 1
    return copy


def issue_open(s: Session, copy: Copy, mp: MasterPosition, link: CopyLink, volume: Decimal, *, magic: int | None,
               ttl_seconds: int):
    """Freeze execution params on the copy and issue its `open` (4.4, C6)."""
    comment = correlation.build_comment(copy.id, mp.position_id)
    copy.exec_params = {
        "symbol": copy.symbol_local, "side": mp.type, "volume": str(volume), "magic": magic,
        "comment": comment, "max_slippage_points": link.max_slippage_points,
        "max_entry_deviation_points": link.max_entry_deviation_points,
        "master_price": str(mp.price_open) if mp.price_open is not None else None,
        # Master volume this copy was sized from: base of its proportional reductions (5.4).
        "master_volume": str(mp.volume),
    }
    cmd = cmds.issue(s, copy, "open", {
        "symbol": copy.symbol_local, "side": mp.type, "volume": volume, "master_price": mp.price_open,
        "sl": copy.sl, "tp": copy.tp, "max_slippage_points": link.max_slippage_points,
        "max_entry_deviation_points": link.max_entry_deviation_points, "position_id": None,
        "magic": magic, "comment": comment,
    }, ttl_seconds=ttl_seconds)
    s.add(Event(type="copy.pending", payload={"copy_id": copy.id, "command_id": cmd.id, "link_id": link.id,
                                              "slave_id": copy.slave_id, "symbol": copy.symbol_local,
                                              "volume": str(volume)}))
    return cmd
