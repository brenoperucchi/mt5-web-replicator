"""Copy lifecycle transitions shared by results, slave reconciliation and adoption (design 5.2-5.5, 5.8).

The copy state describes exposure on the slave; commands describe attempts (5.2). Every transition
here is per copy and never raises for a business conflict (D6): a reservation that cannot be taken
becomes a `symbol_conflicts` row + event, never a rollback of the request.

Zero-exposure proofs (`closed`, `cancelled`, `skipped`, `error` of an open) free a netting slot and
promote at most one `pending_blocked` successor, revalidated inside the same transaction (5.3, C5).
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..models import (
    Account,
    Command,
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
from .fanout import issue_open, policy_check, slot_holder
from .lots import floor_to_step
from .symbols import resolve_symbol

# A zero-exposure terminal state frees the netting slot (5.2, C5).
ZERO_EXPOSURE = ("closed", "cancelled", "skipped", "error")


@dataclass
class Ctx:
    """What the engine needs from settings, without importing the web layer."""

    open_ttl_seconds: int
    lease_seconds: int
    gated: Callable[[Account], bool]
    now: datetime = field(default_factory=utcnow)
    # Server monotonic clock and runtime epoch for close-detection timers (5.6, C4).
    mono: float = 0.0
    server_epoch: str = ""


def event(s: Session, type_: str, **payload) -> None:
    s.add(Event(type=type_, payload={k: (str(v) if isinstance(v, Decimal) else v) for k, v in payload.items()}))


def master_open(s: Session, copy: Copy) -> bool:
    mp = s.get(MasterPosition, copy.master_position_id)
    return mp is not None and mp.state == "open"


def supersede(s: Session, copy: Copy, actions: tuple[str, ...], reason: str, *,
              undelivered_only: bool = False, keep: Command | None = None) -> list[str]:
    out = []
    for cmd in cmds.outstanding(s, copy.id, actions):
        if cmd is keep or (undelivered_only and cmd.state != "queued"):
            continue
        cmd.state = "superseded"
        cmd.result = {"status": "superseded", "reason": reason}
        cmd.lease_until = None
        out.append(cmd.id)
    return out


def issue_close(s: Session, copy: Copy, reason: str) -> Command | None:
    """Durable close obligation by position identity (never without one, C5). Never expires (5.5)."""
    copy.close_intent = True
    if copy.position_id is None:
        return None
    existing = cmds.outstanding(s, copy.id, ("close",))
    if copy.state != "superseded":
        copy.state = "closing"
    if existing:
        return existing[0]
    # A full close replaces reductions and SL/TP changes the EA has not received yet.
    supersede(s, copy, ("close_partial", "modify"), "close_issued", undelivered_only=True)
    params = copy.exec_params or {}
    cmd = cmds.issue(s, copy, "close", {
        "symbol": copy.symbol_local, "position_id": copy.position_id,
        "volume": copy.confirmed_volume if copy.confirmed_volume is not None else copy.volume,
        "magic": params.get("magic"), "comment": params.get("comment", f"c{copy.id}")})
    event(s, "copy.closing", copy_id=copy.id, command_id=cmd.id, reason=reason, position_id=copy.position_id)
    return cmd


def mark_closed(s: Session, copy: Copy, ctx: Ctx, *, reason: str, deal: int | None = None,
                price=None, profit=None, fee=None) -> None:
    """Close confirmed. A `superseded` sibling stays `superseded` (terminal once its close is
    confirmed, 5.5) with `close_intent` cleared, so it never competes with the copy it duplicated."""
    if copy.state == "closed" or (copy.state == "superseded" and not copy.close_intent):
        return
    if copy.state == "superseded":
        copy.close_intent = False
    else:
        copy.state = "closed"
    copy.close_reason = copy.close_reason if reason == "master_closed" and copy.close_reason else reason
    copy.closed_at = ctx.now
    copy.close_deal = deal if deal is not None else copy.close_deal
    copy.price_close = _dec(price) if price is not None else copy.price_close
    copy.profit = _dec(profit) if profit is not None else copy.profit
    copy.fee = _dec(fee) if fee is not None else copy.fee
    supersede(s, copy, ("open", "modify", "close", "close_partial", "cancel"), "copy_closed")
    event(s, "copy.closed", copy_id=copy.id, state=copy.state, close_reason=copy.close_reason,
          close_deal=copy.close_deal, position_id=copy.position_id)
    if copy.state == "closed":
        promote_successors(s, copy, ctx)


def mark_cancelled(s: Session, copy: Copy, ctx: Ctx, reason: str) -> None:
    """Only with proof the open never executed (`not_executed`, `expired`, never delivered)."""
    if copy.state in ZERO_EXPOSURE or copy.position_id is not None:
        return
    copy.state = "cancelled"
    copy.close_reason = reason
    copy.close_intent = False
    supersede(s, copy, ("open", "modify", "cancel"), reason)
    event(s, "copy.cancelled", copy_id=copy.id, reason=reason)
    promote_successors(s, copy, ctx)


def mark_open_failed(s: Session, copy: Copy, ctx: Ctx, *, state: str, reason: str) -> None:
    """Open definitively failed with no position: `error` (or `skipped` for the first-open price guard)."""
    if copy.state in ZERO_EXPOSURE or copy.position_id is not None:
        return
    copy.state = state
    copy.skip_reason = reason
    copy.close_intent = False
    supersede(s, copy, ("modify", "cancel"), "open_failed")
    event(s, "copy.skipped" if state == "skipped" else "copy.error", copy_id=copy.id, reason=reason)
    if reason == "unmanaged_position_on_symbol":
        event(s, "copy.slot_occupied", copy_id=copy.id, slave_id=copy.slave_id, symbol=copy.symbol_local)
    promote_successors(s, copy, ctx)


def open_symbol_conflict(s: Session, copy: Copy, kind: str, position_id: int | None, **extra) -> SymbolConflict:
    """C8: never a second reservation, never a rollback; block new opens on that symbol (5.8)."""
    row = s.scalar(select(SymbolConflict).where(
        SymbolConflict.slave_id == copy.slave_id, SymbolConflict.symbol_local == copy.symbol_local,
        SymbolConflict.kind == kind, SymbolConflict.position_id == position_id,
        SymbolConflict.resolved_at.is_(None)).limit(1))
    if row is not None:
        return row
    row = SymbolConflict(slave_id=copy.slave_id, symbol_local=copy.symbol_local, kind=kind, copy_id=copy.id,
                         position_id=position_id, opened_at=utcnow())
    s.add(row)
    s.flush()
    event(s, "copy.symbol_conflict", conflict_id=row.id, kind=kind, copy_id=copy.id, slave_id=copy.slave_id,
          symbol=copy.symbol_local, position_id=position_id, **extra)
    return row


@dataclass
class Fill:
    """Exposure evidence for a copy: from an open result or from adoption (5.5, 5.8)."""

    position_id: int
    position_ticket: int | None = None
    order: int | None = None
    deal: int | None = None
    price: Decimal | None = None
    volume: Decimal | None = None


def apply_fill(s: Session, copy: Copy, fill: Fill, ctx: Ctx, *, source: str) -> str:
    """Record the position on the copy and move it by the 5.5/5.8 rules. Returns the outcome:
    `open`, `closing`, `conflict` (reservation taken by someone else) or `duplicate`."""
    if copy.position_id is not None and copy.position_id != fill.position_id:
        return "duplicate"
    prior = copy.state
    if prior == "closed":
        return "closed"
    if copy.position_id == fill.position_id and prior in ("open", "closing", "superseded"):
        _set_ids(copy, fill, ctx)  # known exposure (e.g. adopted, then the late result): enrich ids only
        _settle_open(s, copy, source)
        return "known"
    wants_close = (prior in ("cancel_requested", "closing") or copy.close_intent or not master_open(s, copy))
    target = "superseded" if prior == "superseded" else ("closing" if wants_close else "open")
    try:
        with s.begin_nested():
            _set_ids(copy, fill, ctx)
            copy.state = target
            s.flush()
    except IntegrityError:
        # The slot (netting) or the position identity (hedging) is held by another copy: record the
        # evidence on this copy without taking a reservation, open a conflict (C8, S51).
        try:
            with s.begin_nested():
                _set_ids(copy, fill, ctx)
                s.flush()
        except IntegrityError:
            pass
        open_symbol_conflict(s, copy, "late_adoption", fill.position_id, source=source)
        _settle_open(s, copy, source)
        return "conflict"
    _settle_open(s, copy, source)
    if prior in ("cancelled", "error", "uncertain"):
        event(s, "copy.late_fill", copy_id=copy.id, prior_state=prior, position_id=fill.position_id, source=source)
    if target == "open":
        event(s, "copy.opened", copy_id=copy.id, position_id=fill.position_id, volume=copy.confirmed_volume,
              price_open=copy.price_open, source=source)
        # A reduction that arrived while the open was in flight starts from the confirmed volume (5.4).
        advance_reduction(s, copy)
        return "open"
    # Master closed / cancel requested before the open was confirmed: keep the ids, close it (rev-2 A12).
    supersede(s, copy, ("cancel",), "late_fill_close", undelivered_only=True)
    issue_close(s, copy, "master_closed" if not master_open(s, copy) else "cancel_requested")
    return "closing"


def _set_ids(copy: Copy, fill: Fill, ctx: Ctx) -> None:
    copy.position_id = fill.position_id
    copy.position_ticket = fill.position_ticket if fill.position_ticket is not None else copy.position_ticket
    copy.open_order = fill.order if fill.order is not None else copy.open_order
    copy.open_deal = fill.deal if fill.deal is not None else copy.open_deal
    copy.price_open = fill.price if fill.price is not None else copy.price_open
    if fill.volume is not None:
        copy.confirmed_volume = fill.volume
    elif copy.confirmed_volume is None:
        copy.confirmed_volume = copy.volume
    copy.opened_at = copy.opened_at or ctx.now


def _settle_open(s: Session, copy: Copy, source: str) -> None:
    """Exposure evidence settles the open obligation (adoption answers it on the EA's behalf)."""
    for cmd in cmds.outstanding(s, copy.id, ("open",)):
        cmd.state = "done"
        cmd.lease_until = None
        cmd.result = {**(cmd.result or {}), "status": "done", "source": source}


def _dec(v) -> Decimal | None:
    return None if v is None else Decimal(str(v))


# --- master closed (5.5) -----------------------------------------------------------------------------

def master_closed(s: Session, copy: Copy, ctx: Ctx, reason: str = "master_closed") -> str:
    """The 5.5 "master closed" transitions for one copy, by its state. Returns what was done.

    pending (open never delivered) → cancelled, open superseded; pending (open delivered/in progress)
    → cancel_requested + cancel; pending_blocked → cancelled; open → closing + close by position
    identity; uncertain → close intent kept for adoption/resolution (5.8). Closes are never issued
    without a position identity (C5)."""
    st = copy.state
    if st in ZERO_EXPOSURE or st in ("closing", "cancel_requested") or (st == "superseded"):
        return "none"
    if st == "pending_blocked":
        copy.blocked_by = None
        mark_cancelled(s, copy, ctx, "master_closed_while_blocked")
        return "cancelled"
    if st == "uncertain":
        copy.close_intent = True
        event(s, "copy.close_intent", copy_id=copy.id, reason=reason)
        return "close_intent"
    if st == "open":
        copy.close_reason = copy.close_reason or reason  # kept when the close is confirmed
        issue_close(s, copy, reason)
        return "closing"
    # pending
    opens = cmds.outstanding(s, copy.id, ("open",))
    if opens and all(c.state == "queued" for c in opens):
        mark_cancelled(s, copy, ctx, reason)  # proven unsent: supersedes the open
        return "cancelled"
    copy.state = "cancel_requested"
    copy.close_intent = True
    params = copy.exec_params or {}
    cmd = cmds.issue(s, copy, "cancel", {
        "symbol": copy.symbol_local, "position_id": None, "open_command_id": opens[0].id if opens else None,
        "magic": params.get("magic"), "comment": params.get("comment", f"c{copy.id}")})
    event(s, "copy.cancel_requested", copy_id=copy.id, command_id=cmd.id, reason=reason)
    return "cancel_requested"


# --- partial reductions (5.4, C7) ----------------------------------------------------------------

def reduction_target(s: Session, copy: Copy, master_volume: Decimal, master_opened: Decimal) -> Decimal | None:
    """round_down_step(copy.opened_volume × new_master_volume / master.opened_volume), from persisted
    values only (never from in-flight volumes)."""
    if copy.opened_volume is None or not master_opened:
        return None
    spec = s.get(SymbolSpec, (copy.slave_id, copy.symbol_local))
    raw = Decimal(copy.opened_volume) * Decimal(master_volume) / Decimal(master_opened)
    if spec is None or not spec.volume_step:
        return raw
    return floor_to_step(raw, Decimal(spec.volume_step))


def volume_min(s: Session, copy: Copy) -> Decimal:
    spec = s.get(SymbolSpec, (copy.slave_id, copy.symbol_local))
    return Decimal(spec.volume_min) if spec is not None and spec.volume_min else Decimal(0)


FINANCIAL = ("open", "close", "close_partial", "cancel")


def advance_reduction(s: Session, copy: Copy) -> Command | None:
    """Issue the next `close_partial` toward `reduction_target` when nothing financial is in flight
    for this position (5.4, C7). Reductions arriving meanwhile only move the target (coalesced).

    - delta = confirmed_volume − target; delta below volume_min → nothing now (the target persists);
    - target below volume_min → full `close`."""
    if copy.state != "open" or copy.reduction_target is None or copy.position_id is None:
        return None
    if cmds.outstanding(s, copy.id, FINANCIAL):
        return None
    vmin = volume_min(s, copy)
    target = Decimal(copy.reduction_target)
    if target < vmin or target <= 0:
        cmd = issue_close(s, copy, "master_reduced_below_min")
        event(s, "copy.reduction_full_close", copy_id=copy.id, target=target, volume_min=vmin)
        return cmd
    confirmed = Decimal(copy.confirmed_volume if copy.confirmed_volume is not None else copy.volume or 0)
    delta = confirmed - target
    if delta <= 0 or delta < vmin:
        return None
    params = copy.exec_params or {}
    cmd = cmds.issue(s, copy, "close_partial", {
        "symbol": copy.symbol_local, "position_id": copy.position_id, "side": params.get("side"),
        "volume": delta, "residual_volume": target, "magic": params.get("magic"),
        "comment": params.get("comment", f"c{copy.id}")})
    event(s, "copy.reducing", copy_id=copy.id, command_id=cmd.id, volume=delta, target=target)
    return cmd


# --- SL/TP modify (5.5, S28) ---------------------------------------------------------------------

MODIFIABLE = ("pending", "pending_blocked", "open")


def apply_sltp(s: Session, copy: Copy, sl, tp) -> Command | None:
    """Mirror a master SL/TP change on one copy.

    pending_blocked / pending with an undelivered open → the open payload carries the new SL/TP (no
    command). Otherwise a `modify` that supersedes the queued (undelivered) modifies of the copy;
    delivered ones keep their seq and run first, so the latest values always end last (S28)."""
    if copy.state not in MODIFIABLE or copy.no_sltp:
        return None
    sl, tp = _dec(sl), _dec(tp)
    opens = cmds.outstanding(s, copy.id, ("open",))
    if copy.state == "pending_blocked" or (copy.state == "pending" and opens
                                           and all(c.state == "queued" for c in opens)):
        copy.sl, copy.tp = sl, tp
        for c in opens:
            c.payload = {**(c.payload or {}), "sl": cmds.wire(sl), "tp": cmds.wire(tp)}
        event(s, "copy.sltp_in_open", copy_id=copy.id, sl=sl, tp=tp)
        return None
    supersede(s, copy, ("modify",), "newer_modify", undelivered_only=True)
    params = copy.exec_params or {}
    cmd = cmds.issue(s, copy, "modify", {
        "symbol": copy.symbol_local, "position_id": copy.position_id, "sl": sl, "tp": tp,
        "magic": params.get("magic"), "comment": params.get("comment", f"c{copy.id}")})
    event(s, "copy.modify", copy_id=copy.id, command_id=cmd.id, sl=sl, tp=tp)
    return cmd


# --- netting successor (5.3, C5) -------------------------------------------------------------------

def promote_successors(s: Session, freed: Copy, ctx: Ctx) -> Copy | None:
    """`freed` proved zero exposure: cancel stale blocked candidates, promote at most one successor."""
    if freed.state not in ZERO_EXPOSURE:
        return None
    candidates = list(s.scalars(select(Copy).where(Copy.blocked_by == freed.id, Copy.state == "pending_blocked")
                                .order_by(Copy.id)))
    live: list[tuple[Copy, MasterPosition]] = []
    for c in candidates:
        mp = s.get(MasterPosition, c.master_position_id)
        if mp is None or mp.state != "open":
            c.state = "cancelled"
            c.close_reason = "master_closed_while_blocked"
            c.blocked_by = None
            event(s, "copy.cancelled", copy_id=c.id, reason="master_closed_while_blocked")
        else:
            live.append((c, mp))
    if not live:
        return None
    live.sort(key=lambda cm: (cm[1].generation, cm[1].id, cm[0].id))
    chosen, mp = live[-1]
    for other, _ in live[:-1]:  # older candidates stay blocked behind the chosen one
        other.blocked_by = chosen.id
    return _promote(s, chosen, mp, ctx)


def _promote(s: Session, copy: Copy, mp: MasterPosition, ctx: Ctx) -> Copy | None:
    link, slave = s.get(CopyLink, copy.link_id), s.get(Account, copy.slave_id)
    group = s.get(CopyGroup, link.group_id) if link else None
    master = s.get(Account, mp.master_id)
    reason: tuple[str, str, dict] | None = None
    volume = None
    if link is None or group is None or not link.enabled or not group.enabled:
        reason = ("link_disabled", "copy.skipped", {})
    elif slave is None or slave.status != "active":
        reason = ("account_drain", "copy.skipped", {})
    else:
        copy.symbol_local = resolve_symbol(s, slave.id, mp.symbol)
        volume, reason = policy_check(s, master, mp, link, group, slave, copy.symbol_local, ctx.gated)
    if reason is None:
        holder = slot_holder(s, copy.slave_id, copy.symbol_local, exclude_id=copy.id)
        if holder is not None:  # still occupied (e.g. the slot was re-taken): wait behind the holder
            copy.blocked_by = holder.id
            return None
    if reason is not None:
        copy.state, copy.skip_reason, copy.blocked_by = "skipped", reason[0], None
        event(s, reason[1], copy_id=copy.id, link_id=copy.link_id, slave_id=copy.slave_id, reason=reason[0],
              **reason[2])
        return promote_successors(s, copy, ctx)
    try:
        with s.begin_nested():
            copy.state, copy.blocked_by = "pending", None
            copy.volume = copy.opened_volume = volume
            s.flush()
    except IntegrityError:
        copy.state, copy.skip_reason, copy.blocked_by = "skipped", "netting_conflict", None
        event(s, "copy.skipped_netting_conflict", copy_id=copy.id, symbol=copy.symbol_local)
        return promote_successors(s, copy, ctx)
    magic = link.magic_value if link.magic_mode == "fixed" else mp.magic
    issue_open(s, copy, mp, link, volume, magic=magic, ttl_seconds=ctx.open_ttl_seconds)
    event(s, "copy.promoted", copy_id=copy.id, symbol=copy.symbol_local)
    return copy


__all__ = ["Ctx", "Fill", "ZERO_EXPOSURE", "advance_reduction", "apply_fill", "apply_sltp", "event", "issue_close",
           "mark_cancelled", "mark_closed", "mark_open_failed", "master_closed", "master_open",
           "open_symbol_conflict", "promote_successors", "reduction_target", "supersede", "volume_min"]
