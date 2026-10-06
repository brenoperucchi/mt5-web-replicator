"""Slave snapshot reconciliation and adoption (design 4.3, 5.5 "slave snapshot", 5.8, 5.8a).

Runs inline in `POST /v4/slave/snapshot` for this slave's copies:

1. **Adoption (5.8):** a position (or a history `in` deal) whose comment correlates with `c<copy_id>`
   (`engine.correlation`: `c<copy_id>-<master position_id>` or legacy `c<copy_id>`) and the copy's
   frozen magic, for a copy without `position_id` in `pending/cancel_requested/uncertain/error/cancelled`
   younger than 7 days → the copy gets the ids; master open → `open`; master closed → `closing` +
   `close`; an exit deal for it in history → `closed`. A reservation that cannot be taken →
   `symbol_conflicts(late_adoption)` (C8).
2. **Duplicates (5.8):** a second position with the same correlation → `superseded` sibling copy
   with `close_intent` and its own `close` (keeps exposure until the close is confirmed).
3. **Slave-side close (5.5, S21):** a copy with `position_id` whose position is gone and whose exit
   deal is in history → `closed` with `close_reason` from the deal reason; pending commands superseded.
4. **close `position_not_found` (5.5, S29):** exit deal → `closed`; no evidence after 3 snapshots →
   alert `copy.close_unconfirmed`, reservation kept.
5. **Unmanaged exposure (5.8a, C8):** on a netting slave, a position without copier correlation on a
   symbol the copier holds → `symbol_conflicts(unmanaged_position)`. Weak matching is never used.

History-based decisions (3, 4 and adoption from deals) need `history_synced=true`; nothing runs
while `connected=false` (a disconnected terminal's view is not evidence).

Operator resolution (`/admin/copies/:id/resolve`, `/admin/symbol_conflicts/:id/resolve`, `resolve`
command to the EA journal) lives in `engine.admin_ops`.

TODO(PR: background worker): adoption sweep for copies older than the 7-day inline window (5.8, D6).
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..models import Account, Copy
from . import correlation
from .fanout import NETTING_RESERVING, PositionData, slot_holder
from .lifecycle import (
    Ctx,
    Fill,
    apply_fill,
    event,
    issue_close,
    mark_closed,
    open_symbol_conflict,
)
from .results import pending_not_found

ADOPTABLE = ("pending", "cancel_requested", "uncertain", "error", "cancelled")
ADOPTION_WINDOW = timedelta(days=7)
NOT_FOUND_SNAPSHOTS = 3
EXIT_ENTRIES = ("out", "out_by")
# DEAL_REASON_* → close_reason (5.5).
DEAL_REASONS = {"sl": "slave_sl", "tp": "slave_tp", "so": "stop_out", "stop_out": "stop_out",
                "client": "manual", "mobile": "manual", "web": "manual", "expert": "slave_expert"}


@dataclass
class Deal:
    deal: int
    position_id: int | None
    entry: str
    reason: str | None
    volume: Decimal | None
    price: Decimal | None
    profit: Decimal | None
    fee: Decimal | None
    magic: int | None
    comment: str
    time_msc: int | None = None

    @classmethod
    def parse(cls, d: dict[str, Any]) -> Deal | None:
        try:
            deal = int(d["deal"])
        except (KeyError, TypeError, ValueError):
            return None
        fee = [Decimal(str(d[k])) for k in ("commission", "swap") if d.get(k) is not None]
        return cls(deal=deal, position_id=_int(d.get("position_id")), entry=str(d.get("entry") or "").lower(),
                   reason=str(d["reason"]).lower() if d.get("reason") is not None else None,
                   volume=_dec(d.get("volume")), price=_dec(d.get("price")), profit=_dec(d.get("profit")),
                   fee=sum(fee, Decimal(0)) if fee else None, magic=_int(d.get("magic")),
                   comment=str(d.get("comment") or ""), time_msc=_int(d.get("time_msc")))


def reconcile_slave(s: Session, slave: Account, positions: list[PositionData], history: list[dict[str, Any]], *,
                    history_synced: bool, ctx: Ctx) -> dict:
    stats = defaultdict(int)
    deals = [d for d in (Deal.parse(h) for h in history) if d is not None] if history_synced else []
    by_pid = {p.position_id: p for p in positions}
    exits: dict[int, list[Deal]] = defaultdict(list)
    entries_by_copy: dict[int, list[Deal]] = defaultdict(list)
    for d in deals:
        if d.entry in EXIT_ENTRIES and d.position_id is not None:
            exits[d.position_id].append(d)
        elif d.entry == "in" and (cid := correlation.candidate_copy_id(d.comment)) is not None:
            entries_by_copy[cid].append(d)
    positions_by_copy: dict[int, list[PositionData]] = defaultdict(list)
    for p in positions:
        if (cid := correlation.candidate_copy_id(p.comment)) is not None:
            positions_by_copy[cid].append(p)

    # 1 + 2: correlation by comment c<copy_id> + frozen magic (5.8a).
    correlated: set[int] = set()
    for copy_id, plist in positions_by_copy.items():
        copy = s.get(Copy, copy_id)
        if copy is None or copy.slave_id != slave.id:
            continue
        hits = sorted((p for p in plist if correlation.matches(copy.exec_params, copy.id, p.comment, p.magic)),
                      key=lambda p: p.position_id)
        if not hits:
            continue
        correlated.update(p.position_id for p in hits)
        if copy.position_id is None:
            if copy.state in ADOPTABLE and _recent(copy, ctx):
                first, hits = hits[0], hits[1:]
                _adopt(s, copy, Fill(position_id=first.position_id, position_ticket=first.position_ticket,
                                     price=first.price_open, volume=first.volume), exits, ctx, stats)
            else:
                continue  # older than the inline window: left to the background sweep
        for extra in hits:
            if extra.position_id != copy.position_id:
                _duplicate(s, copy, extra, ctx, stats)

    # 1b: adoption from history `in` deals (the position may already be closed again, S40).
    for copy_id, dlist in entries_by_copy.items():
        copy = s.get(Copy, copy_id)
        if copy is None or copy.slave_id != slave.id or copy.position_id is not None:
            continue
        hit = next((d for d in dlist if correlation.matches(copy.exec_params, copy.id, d.comment, d.magic)
                    and d.position_id is not None), None)
        if hit is None or copy.state not in ADOPTABLE or not _recent(copy, ctx):
            continue
        _adopt(s, copy, Fill(position_id=hit.position_id, deal=hit.deal, price=hit.price, volume=hit.volume),
               exits, ctx, stats)

    # 3: refresh tickets; slave-side close by exit deal.
    managed = list(s.scalars(select(Copy).where(
        Copy.slave_id == slave.id, Copy.position_id.is_not(None),
        Copy.state.in_(("open", "closing", "uncertain", "cancel_requested", "superseded")))))
    for copy in managed:
        pos = by_pid.get(copy.position_id)
        if pos is not None:
            copy.position_ticket = pos.position_ticket
            continue
        if copy.state == "superseded" and not copy.close_intent:
            continue
        if (deal := _exit(exits, copy.position_id)) is not None:
            reason = "master_closed" if copy.state == "closing" else DEAL_REASONS.get(deal.reason or "", "slave_closed")
            mark_closed(s, copy, ctx, reason=reason, deal=deal.deal, price=deal.price, profit=deal.profit,
                        fee=deal.fee)
            stats["closed_by_history"] += 1

    # 4: close `position_not_found` waiting for evidence.
    if history_synced:
        for cmd, copy in pending_not_found(s, slave.id):
            if copy.state == "closed":
                continue
            n = int((cmd.result or {}).get("not_found_snapshots", 0)) + 1
            result = {**(cmd.result or {}), "not_found_snapshots": n}
            if n >= NOT_FOUND_SNAPSHOTS:
                # 5.5 says error(close_unconfirmed) with the reservation KEPT; `error` is outside the
                # netting index, so the copy stays `closing` and carries the reason instead.
                result["close_unconfirmed"] = True
                copy.close_reason = "close_unconfirmed"
                event(s, "copy.close_unconfirmed", copy_id=copy.id, position_id=copy.position_id,
                      command_id=cmd.id)
                stats["close_unconfirmed"] += 1
            cmd.result = result

    # 5: unmanaged exposure on a netting symbol held by the copier.
    if slave.margin_mode == "netting":
        for p in positions:
            if p.position_id in correlated or _ours(s, slave.id, p):
                continue
            holder = slot_holder(s, slave.id, p.symbol)
            if holder is not None and holder.position_id != p.position_id:
                open_symbol_conflict(s, holder, "unmanaged_position", p.position_id, comment=p.comment,
                                     magic=p.magic)
                stats["unmanaged"] += 1
    return dict(stats)


def _adopt(s: Session, copy: Copy, fill: Fill, exits: dict[int, list[Deal]], ctx: Ctx, stats) -> None:
    prior = copy.state
    outcome = apply_fill(s, copy, fill, ctx, source="adoption")
    event(s, "copy.adopted", copy_id=copy.id, position_id=fill.position_id, prior_state=prior, outcome=outcome)
    stats["adopted"] += 1
    if outcome in ("open", "closing") and (deal := _exit(exits, fill.position_id)) is not None:
        mark_closed(s, copy, ctx, reason="master_closed" if outcome == "closing" else
                    DEAL_REASONS.get(deal.reason or "", "slave_closed"),
                    deal=deal.deal, price=deal.price, profit=deal.profit, fee=deal.fee)


def _duplicate(s: Session, copy: Copy, p: PositionData, ctx: Ctx, stats) -> None:
    """Second fill with the same correlation (S52): a `superseded` sibling owns it until it is closed."""
    if s.scalar(select(Copy.id).where(Copy.slave_id == copy.slave_id, Copy.position_id == p.position_id).limit(1)):
        return
    sibling = Copy(link_id=copy.link_id, master_position_id=copy.master_position_id, slave_id=copy.slave_id,
                   slave_margin_mode=copy.slave_margin_mode, symbol_master=copy.symbol_master,
                   symbol_local=copy.symbol_local, volume=p.volume, confirmed_volume=p.volume, state="superseded",
                   close_intent=True, exec_params=copy.exec_params, position_id=p.position_id,
                   position_ticket=p.position_ticket, price_open=p.price_open, opened_at=ctx.now)
    try:
        with s.begin_nested():
            s.add(sibling)
            s.flush()
    except IntegrityError:
        open_symbol_conflict(s, copy, "unexpected_exposure", p.position_id, reason="duplicate_position")
        return
    event(s, "copy.duplicate_position", copy_id=copy.id, sibling_copy_id=sibling.id, position_id=p.position_id)
    issue_close(s, sibling, "duplicate_position")
    stats["duplicates"] += 1


def _ours(s: Session, slave_id: int, p: PositionData) -> bool:
    if s.scalar(select(Copy.id).where(Copy.slave_id == slave_id, Copy.position_id == p.position_id,
                                      Copy.state.in_((*NETTING_RESERVING, "superseded"))).limit(1)):
        return True
    copy_id = correlation.candidate_copy_id(p.comment)
    if copy_id is None:
        return False
    copy = s.get(Copy, copy_id)
    return copy is not None and copy.slave_id == slave_id and correlation.matches(copy.exec_params, copy.id,
                                                                                    p.comment, p.magic)


def _exit(exits: dict[int, list[Deal]], position_id: int | None) -> Deal | None:
    lst = exits.get(position_id) if position_id is not None else None
    return max(lst, key=lambda d: d.deal) if lst else None


def _recent(copy: Copy, ctx: Ctx) -> bool:
    created = copy.created_at
    if created is None:
        return True
    if created.tzinfo is None:
        created = created.replace(tzinfo=ctx.now.tzinfo)
    return ctx.now - created <= ADOPTION_WINDOW


def _int(v) -> int | None:
    try:
        return None if v is None else int(v)
    except (TypeError, ValueError):
        return None


def _dec(v) -> Decimal | None:
    return None if v is None else Decimal(str(v))
