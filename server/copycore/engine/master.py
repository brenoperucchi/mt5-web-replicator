"""Master snapshot interpretation (design 5.4 "master event precedence", 5.5, 5.6; contracts C1, C4, C7).

For each master `position_id` in an accepted, connected snapshot exactly one interpretation applies,
in this order (C1):

1. Present, **same side, lower volume** → partial reduction (persisted `reduction_target` per copy,
   proportional, rounded down to the slave step), even if an `out` deal is in history.
2. Present, **side changed** (or an unprocessed `inout` deal) → one reversal = one new generation:
   generation g `closed` (`close_source=reversal`), its copies follow the "master closed" lifecycle,
   generation g+1 is fanned out with each link's open serialized behind the previous copy (5.3, 5.4).
3. Absent **and** an exit deal (`out`/`out_by`) for it → fast close (`close_source=history`).
4. Absent without an exit deal → absence path: closes only after `CLOSE_ABSENT_SNAPSHOTS` absent
   snapshots **and** `CLOSE_ABSENT_SECONDS` (≥ 60 s) on the server monotonic clock within the current
   server epoch; counted only on `connected=true` + `history_synced=true` snapshots. A
   mass disappearance (≥ `MASS_DISAPPEAR_MIN`, or all open positions when ≥ 2, vanishing in one
   snapshot) latches an episode on those positions: alert, `send_history=true` in the master config,
   and `MASS_DISAPPEAR_SECONDS` instead of T. Reappearance resets the counter and the episode.

Present positions also carry SL/TP changes (→ `modify`, 5.5) and volume increases (netting:
drift only, `copy.volume_drift`, 5.3).

Each history deal is recorded once in `processed_deals (account_id, deal)` with the generation it
affected; replays are ignored. A deal whose time (EA time + `ea_clock_offset_ms`) is not after the
current generation's start can never close or reverse that generation. A position id that reappears
after its last generation was closed is not re-copied: `master_position.reappeared` alert (once).
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from dataclasses import dataclass
from decimal import Decimal
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import Account, Copy, CopyLink, Event, MasterPosition, ProcessedDeal
from . import commands as cmds
from .fanout import PositionData, enabled_links, fan_out_one, is_copier_position
from .lifecycle import Ctx, advance_reduction, apply_sltp, event, master_closed, reduction_target
from .reconcile import Deal

EXIT_ENTRIES = ("out", "out_by")
REDUCIBLE = ("pending", "open", "uncertain")


@dataclass(frozen=True)
class CloseRules:
    absent_snapshots: int
    absent_seconds: int
    mass_min: int
    mass_seconds: int


def process_master_snapshot(s: Session, master: Account, positions: list[PositionData],
                            history: list[dict[str, Any]], *, history_synced: bool, ea_clock_offset_ms: int,
                            fan_out: bool, rules: CloseRules, ctx: Ctx) -> dict:
    """Apply one accepted snapshot of a connected master. Returns counters."""
    stats: dict[str, int] = defaultdict(int)
    present: dict[int, PositionData] = {}
    for pos in positions:
        if master.exclude_copier_positions and is_copier_position(s, master, pos):
            stats["ignored"] += 1
            continue
        present[pos.position_id] = pos

    open_mps: dict[int, MasterPosition] = {}
    for mp in s.scalars(select(MasterPosition).where(MasterPosition.master_id == master.id,
                                                     MasterPosition.state == "open")
                        .order_by(MasterPosition.generation)):
        open_mps[mp.position_id] = mp  # latest open generation per position id

    deals = _unprocessed_deals(s, master.id, history) if history_synced else {}
    snap = _Snap(s, master, ctx, rules, fan_out, ea_clock_offset_ms, stats)

    # Closes first: a netting slot freed by a close in this snapshot is visible to the positions
    # opened in the same snapshot (close-then-reopen blocks behind the closing copy, 5.3).
    absent = [mp for pid, mp in open_mps.items() if pid not in present]
    snap.absent(absent, deals, history_synced=history_synced, open_count=len(open_mps))

    for pid, pos in present.items():
        mp = open_mps.get(pid)
        if mp is None:
            snap.new_or_reappeared(pos)
        else:
            snap.present(mp, pos, deals.get(pid, []))
    return dict(stats)


def send_history_wanted(s: Session, master_id: int) -> bool:
    """`send_history=true` while a mass-disappearance episode is latched on an open position (5.6)."""
    return s.scalar(select(MasterPosition.id).where(
        MasterPosition.master_id == master_id, MasterPosition.state == "open",
        MasterPosition.mass_episode_id.is_not(None)).limit(1)) is not None


def _unprocessed_deals(s: Session, account_id: int, history: list[dict[str, Any]]) -> dict[int, list[Deal]]:
    parsed: dict[int, Deal] = {}
    for h in history:
        d = Deal.parse(h)
        if d is not None and d.position_id is not None and d.entry in (*EXIT_ENTRIES, "inout"):
            parsed[d.deal] = d
    if not parsed:
        return {}
    seen = set(s.scalars(select(ProcessedDeal.deal).where(ProcessedDeal.account_id == account_id,
                                                          ProcessedDeal.deal.in_(list(parsed)))))
    out: dict[int, list[Deal]] = defaultdict(list)
    for d in sorted(parsed.values(), key=lambda x: x.deal):
        if d.deal not in seen:
            out[d.position_id].append(d)  # type: ignore[index]
    return out


class _Snap:
    def __init__(self, s: Session, master: Account, ctx: Ctx, rules: CloseRules, fan_out: bool,
                 offset_ms: int, stats: dict[str, int]):
        self.s, self.master, self.ctx, self.rules = s, master, ctx, rules
        self.fan_out, self.offset_ms, self.stats = fan_out, offset_ms, stats

    # --- helpers ---------------------------------------------------------------------------------
    def after_start(self, d: Deal, mp: MasterPosition) -> bool:
        """The deal happened after this generation started (C1). Without a time it cannot be proven."""
        start = cmds.ms(mp.opened_at)
        return d.time_msc is not None and (start is None or d.time_msc + self.offset_ms > start)

    def record(self, d: Deal, mp: MasterPosition | None, effect: str) -> None:
        self.s.add(ProcessedDeal(account_id=self.master.id, deal=d.deal, position_id=d.position_id,
                                 generation=mp.generation if mp is not None else None, effect=effect))

    def copies_of(self, mp: MasterPosition) -> list[Copy]:
        return list(self.s.scalars(select(Copy).where(Copy.master_position_id == mp.id).order_by(Copy.id)))

    def close(self, mp: MasterPosition, source: str, deal: Deal | None = None) -> None:
        mp.state, mp.close_source, mp.closed_at = "closed", source, self.ctx.now
        event(self.s, "master_position.closed", master_id=self.master.id, master_position_id=mp.id,
              position_id=mp.position_id, generation=mp.generation, close_source=source,
              deal=deal.deal if deal else None, absent_count=mp.absent_count, mass_episode_id=mp.mass_episode_id)
        reason = "master_reversed" if source == "reversal" else "master_closed"
        for c in self.copies_of(mp):
            master_closed(self.s, c, self.ctx, reason)
        self.stats[f"closed_{source}"] += 1

    def create(self, pos: PositionData, generation: int) -> MasterPosition:
        mp = MasterPosition(master_id=self.master.id, position_id=pos.position_id, generation=generation,
                            position_ticket=pos.position_ticket, symbol=pos.symbol, type=pos.type,
                            volume=pos.volume, opened_volume=pos.volume, price_open=pos.price_open,
                            sl=pos.sl, tp=pos.tp, magic=pos.magic, comment=pos.comment, state="open",
                            opened_at=self.ctx.now)
        self.s.add(mp)
        self.s.flush()
        self.stats["new_positions"] += 1
        event(self.s, "master_position.opened", master_id=self.master.id, master_position_id=mp.id,
              position_id=pos.position_id, generation=generation, symbol=pos.symbol, type=pos.type,
              volume=pos.volume)
        return mp

    def fan(self, mp: MasterPosition, predecessors: dict[int, Copy] | None = None) -> None:
        if not self.fan_out:
            self.s.add(Event(type="master_position.not_fanned_out",
                             payload={"master_position_id": mp.id, "reason": "master_drain"}))
            return
        for pair in enabled_links(self.s, self.master.id):
            fan_out_one(self.s, self.master, mp, pair, open_ttl_seconds=self.ctx.open_ttl_seconds,
                        gated=self.ctx.gated, stats=self.stats,
                        predecessor=(predecessors or {}).get(pair[0].id))

    # --- present positions --------------------------------------------------------------------------
    def new_or_reappeared(self, pos: PositionData) -> None:
        last = self.s.scalar(select(MasterPosition).where(
            MasterPosition.master_id == self.master.id, MasterPosition.position_id == pos.position_id)
            .order_by(MasterPosition.generation.desc()).limit(1))
        if last is None:
            self.fan(self.create(pos, 0))
            return
        # The last generation was closed (absence, history or a stale view) and the id is back: never
        # re-copied automatically; the operator is alerted once per closed generation.
        if not _alerted(self.s, "master_position.reappeared", last.id):
            event(self.s, "master_position.reappeared", master_id=self.master.id, master_position_id=last.id,
                  position_id=pos.position_id, generation=last.generation, close_source=last.close_source)
        self.stats["reappeared"] += 1

    def present(self, mp: MasterPosition, pos: PositionData, pdeals: list[Deal]) -> None:
        mp.position_ticket = pos.position_ticket
        if mp.absent_since_mono is not None or mp.absent_count or mp.mass_episode_id:
            event(self.s, "master_position.reappeared_before_close", master_position_id=mp.id,
                  absent_count=mp.absent_count, mass_episode_id=mp.mass_episode_id)
            mp.absent_count, mp.absent_since_mono, mp.absent_epoch, mp.mass_episode_id = 0, None, None, None

        fresh = [d for d in pdeals if self.after_start(d, mp)]
        stale = [d for d in pdeals if d not in fresh]
        for d in stale:
            self.record(d, None, "none")
        inouts = [d for d in fresh if d.entry == "inout"]
        if pos.type != mp.type or inouts:
            for d in fresh:
                self.record(d, mp, "reversal" if d.entry == "inout" else "none")
            self.reverse(mp, pos)
            return

        if pos.volume < mp.volume:
            for d in fresh:
                self.record(d, mp, "partial")
            self.reduce(mp, pos.volume)
        else:
            for d in fresh:
                self.record(d, mp, "none")
            if pos.volume > mp.volume:
                self.drift(mp, pos.volume)

        if not (_same(pos.sl, mp.sl) and _same(pos.tp, mp.tp)):
            self.modify(mp, pos.sl, pos.tp)

    def reverse(self, mp: MasterPosition, pos: PositionData) -> None:
        """Netting reversal (OD4): close generation g through the lifecycle, open g+1 behind it (5.4)."""
        old_type = mp.type
        predecessors = {c.link_id: c for c in self.copies_of(mp) if c.state != "superseded"}
        self.close(mp, "reversal")
        nxt = (self.s.scalar(select(MasterPosition.generation).where(
            MasterPosition.master_id == self.master.id, MasterPosition.position_id == mp.position_id)
            .order_by(MasterPosition.generation.desc()).limit(1)) or 0) + 1
        new = self.create(pos, nxt)
        event(self.s, "master_position.reversed", master_id=self.master.id, position_id=pos.position_id,
              from_generation=mp.generation, to_generation=nxt, from_type=old_type, to_type=pos.type,
              volume=pos.volume)
        self.stats["reversals"] += 1
        self.fan(new, predecessors)

    def reduce(self, mp: MasterPosition, new_volume: Decimal) -> None:
        old = mp.volume
        mp.volume = new_volume
        event(self.s, "master_position.reduced", master_position_id=mp.id, position_id=mp.position_id,
              from_volume=old, to_volume=new_volume)
        self.stats["reductions"] += 1
        for c in self.copies_of(mp):
            if c.state not in REDUCIBLE:
                continue  # pending_blocked: promotion sizes from the current master volume
            base = _d((c.exec_params or {}).get("master_volume")) or mp.opened_volume or old
            target = reduction_target(self.s, c, new_volume, base)
            if target is None:
                continue
            if c.reduction_target is None or target < c.reduction_target:
                c.reduction_target = target
                event(self.s, "copy.reduction_target", copy_id=c.id, target=target, master_volume=new_volume)
            advance_reduction(self.s, c)

    def drift(self, mp: MasterPosition, new_volume: Decimal) -> None:
        """Netting master volume increase: not mirrored in Phase 1 (5.3, OD5)."""
        old = mp.volume
        mp.volume = new_volume
        for c in self.copies_of(mp):
            if c.state in ("pending", "open", "uncertain"):
                event(self.s, "copy.volume_drift", copy_id=c.id, master_volume=new_volume, master_previous=old,
                      slave_volume=c.confirmed_volume if c.confirmed_volume is not None else c.volume)
        self.stats["drift"] += 1

    def modify(self, mp: MasterPosition, sl, tp) -> None:
        mp.sl, mp.tp = sl, tp
        for c in self.copies_of(mp):
            link = self.s.get(CopyLink, c.link_id)
            if link is not None and link.copy_sl_tp and apply_sltp(self.s, c, sl, tp) is not None:
                self.stats["modifies"] += 1

    # --- absent positions ---------------------------------------------------------------------------
    def absent(self, absent: list[MasterPosition], deals: dict[int, list[Deal]], *, history_synced: bool,
               open_count: int) -> None:
        if not history_synced:
            return  # neither fast path nor absence counting without a synced history (5.6)
        vanished: list[MasterPosition] = []
        waiting: list[MasterPosition] = []
        for mp in absent:
            pdeals = deals.get(mp.position_id, [])
            exits = [d for d in pdeals if d.entry in EXIT_ENTRIES and self.after_start(d, mp)]
            if exits:
                for d in pdeals:
                    self.record(d, mp if d in exits else None, "close" if d in exits else "none")
                self.close(mp, "history", max(exits, key=lambda d: d.deal))
                continue
            for d in pdeals:
                self.record(d, None, "none")
            if mp.absent_since_mono is None or mp.absent_epoch != self.ctx.server_epoch:
                restarted = mp.absent_epoch is not None
                # New absence, or a previous server epoch: elapsed time is never reused (C4). After a
                # restart this snapshot is the healthy confirmation; counting starts after it.
                mp.absent_since_mono, mp.absent_epoch = self.ctx.mono, self.ctx.server_epoch
                mp.absent_count = 0 if restarted else 1
                mp.mass_episode_id = None
                vanished.append(mp)
                event(self.s, "master_position.absence_restarted" if restarted else "master_position.absent",
                      master_position_id=mp.id, position_id=mp.position_id)
            else:
                mp.absent_count += 1
            waiting.append(mp)

        n = len(vanished)
        if n and (n >= self.rules.mass_min or (n == open_count and open_count >= 2)):
            episode = "m_" + uuid.uuid4().hex
            for mp in vanished:
                mp.mass_episode_id = episode
            event(self.s, "master.mass_disappearance", master_id=self.master.id, episode=episode, count=n,
                  position_ids=[mp.position_id for mp in vanished], hold_seconds=self.rules.mass_seconds)
            self.stats["mass_disappearance"] += n

        for mp in waiting:
            hold = self.rules.mass_seconds if mp.mass_episode_id else self.rules.absent_seconds
            elapsed = self.ctx.mono - float(mp.absent_since_mono or 0)
            if mp.absent_count >= self.rules.absent_snapshots and elapsed >= hold:
                self.close(mp, "absence")
            else:
                self.stats["absent"] += 1


def _alerted(s: Session, type_: str, master_position_id: int) -> bool:
    for payload in s.scalars(select(Event.payload).where(Event.type == type_).order_by(Event.id.desc()).limit(500)):
        if (payload or {}).get("master_position_id") == master_position_id:
            return True
    return False


def _same(a, b) -> bool:
    if a is None or b is None:
        return a is None and b is None
    return Decimal(str(a)) == Decimal(str(b))


def _d(v) -> Decimal | None:
    return None if v is None else Decimal(str(v))


__all__ = ["CloseRules", "process_master_snapshot", "send_history_wanted"]
