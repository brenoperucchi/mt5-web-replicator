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

from ..models import Account, Command, Copy, CopyGroup, CopyLink, Event, MasterPosition, SymbolConflict, utcnow
from . import commands as cmds
from .fanout import issue_open, policy_check, slot_holder
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


__all__ = ["Ctx", "Fill", "ZERO_EXPOSURE", "apply_fill", "event", "issue_close", "mark_cancelled", "mark_closed",
           "mark_open_failed", "master_open", "open_symbol_conflict", "promote_successors",
           "supersede"]
