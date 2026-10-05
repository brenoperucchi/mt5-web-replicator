"""Slave command results (design 4.5, 4.6, 5.5, 5.7; contracts C2, C3).

- `command_id` is the logical obligation, `attempt_id` one durable attempt of it. A result is
  applied once per `(command_id, attempt_id)`: a replay of the same attempt (EA outbox replay after
  a restart, a lost 200) is a no-op. The only accepted change of an already-settled attempt is
  `uncertain` → conclusive execution evidence (`done`/`done_partial`/`closed`), because exposure
  evidence always wins (4.6 step 7, 5.5).
- Results of one batch are applied per copy in `seq_in_copy` order, whatever order they arrive in.
- Results never 404: unknown/foreign commands or attempts are answered in `unknown` (4.2).
- Copy (financial) state is changed only through lifecycle transitions; a failed command never
  ends a copy whose position may be alive (5.2).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from decimal import Decimal
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import Command, CommandAttempt, Copy
from . import commands as cmds
from .lifecycle import (
    ZERO_EXPOSURE,
    Ctx,
    Fill,
    advance_reduction,
    apply_fill,
    event,
    issue_close,
    mark_cancelled,
    mark_closed,
    mark_open_failed,
    master_open,
    volume_min,
)

RESULT_STATUSES = ("in_progress", "done", "done_partial", "closed", "failed", "expired", "not_executed",
                   "uncertain", "skipped", "notmodify")
CONCLUSIVE = ("done", "done_partial", "closed")
OUTCOME = {"done": "done", "closed": "done", "done_partial": "done_partial", "uncertain": "uncertain",
           "failed": "rejected", "expired": "rejected", "not_executed": "rejected", "skipped": "rejected",
           "notmodify": "rejected"}
# Open failures that prove a policy skip rather than an error (S20: price guard on the first open).
OPEN_SKIP_CODES = {"price_out_of_range"}
# Open failures that prove the open never executed and was refused for a non-error reason.
OPEN_CANCEL_CODES = {"drain"}
NOTMODIFY_LIMIT = 2  # NOTMODIFY per day → NOSLTP after 2 (slave_presenter.rb:61-65)


@dataclass
class Outcome:
    unknown: list[str] = field(default_factory=list)
    applied: int = 0
    duplicates: int = 0


def apply_results(s: Session, slave_id: int, results: list[dict[str, Any]], ctx: Ctx) -> Outcome:
    out = Outcome()
    rows: list[tuple[tuple, dict, Command | None]] = []
    for i, r in enumerate(results):
        cmd = s.get(Command, r["command_id"])
        order = (cmd.copy_id, cmd.seq_in_copy, r["status"] != "in_progress", i) if cmd else (0, 0, False, i)
        rows.append((order, r, cmd))
    rows.sort(key=lambda x: x[0])
    for _, r, cmd in rows:
        status = apply_result(s, slave_id, r, cmd, ctx)
        if status == "unknown":
            out.unknown.append(r["command_id"])
        elif status == "duplicate":
            out.duplicates += 1
        else:
            out.applied += 1
    return out


def apply_result(s: Session, slave_id: int, r: dict[str, Any], cmd: Command | None, ctx: Ctx) -> str:
    if cmd is None:
        return "unknown"
    copy = s.get(Copy, cmd.copy_id)
    if copy is None or copy.slave_id != slave_id or (r.get("copy_id") is not None and r["copy_id"] != copy.id):
        return "unknown"
    attempt_id = r.get("attempt_id") or cmd.attempt_id
    att = s.get(CommandAttempt, (cmd.id, attempt_id))
    if att is None:
        return "unknown"
    status = r["status"]
    current = attempt_id == cmd.attempt_id

    if status == "in_progress":
        if current:
            cmds.ack_in_progress(s, slave_id, cmd.id, copy.id, ctx.lease_seconds, ctx.now)
        return "applied"

    if att.outcome is not None and not (att.outcome == "uncertain" and status in CONCLUSIVE):
        return "duplicate"
    att.outcome = OUTCOME[status]
    att.evidence = _jsonable(r)
    if not current and status not in CONCLUSIVE:
        return "applied"  # an older attempt's reject: recorded only; the obligation moved on

    handler = {"open": _open, "close": _close, "cancel": _cancel, "close_partial": _close_partial,
               "modify": _modify, "resolve": _resolve}[cmd.action]
    handler(s, cmd, copy, r, ctx)
    return "applied"


def _settle(cmd: Command, state: str, r: dict[str, Any]) -> None:
    cmd.state = state
    cmd.lease_until = None
    cmd.result = _jsonable(r)


def _mark_uncertain(s: Session, cmd: Command, copy: Copy, r: dict[str, Any], *, close_intent: bool) -> None:
    """EA journal `suspended` (4.6 step 6-7): per copy only, never global; no evidence ≠ not executed."""
    cmd.state = "in_progress"
    cmd.lease_until = None
    cmd.result = _jsonable(r)
    if copy.state not in ZERO_EXPOSURE and copy.state != "superseded":
        copy.state = "uncertain"
    copy.close_intent = copy.close_intent or close_intent
    event(s, "copy.uncertain", copy_id=copy.id, command_id=cmd.id, action=cmd.action,
          error_code=r.get("error_code"), message=r.get("message"))


def _fill_from(r: dict[str, Any]) -> Fill | None:
    if r.get("position_id") is None:
        return None
    vol = r.get("executed_volume") if r.get("executed_volume") is not None else r.get("volume")
    return Fill(position_id=r["position_id"], position_ticket=r.get("position_ticket"), order=r.get("order"),
                deal=r.get("deal"), price=_d(r.get("price")), volume=_d(vol))


# --- per action --------------------------------------------------------------------------------------

def _open(s: Session, cmd: Command, copy: Copy, r: dict[str, Any], ctx: Ctx) -> None:
    status = r["status"]
    if status in CONCLUSIVE:
        fill = _fill_from(r)
        if fill is None:
            # `done` without a position identity is not evidence of exposure we can manage: keep it
            # uncertain until adoption or the operator resolves it (C3).
            _mark_uncertain(s, cmd, copy, {**r, "status": "uncertain", "reason": "done_without_position_id"},
                            close_intent=not master_open(s, copy))
            return
        _settle(cmd, "done", r)
        requested = _d((cmd.payload or {}).get("volume"))
        if fill.volume is not None and requested is not None and fill.volume < requested:
            event(s, "copy.partial_fill", copy_id=copy.id, requested=requested, filled=fill.volume)
        outcome = apply_fill(s, copy, fill, ctx, source="result")
        if outcome == "duplicate":
            event(s, "copy.duplicate_position", copy_id=copy.id, position_id=fill.position_id,
                  known_position_id=copy.position_id)
        return
    if status == "uncertain":
        _mark_uncertain(s, cmd, copy, r, close_intent=copy.state == "cancel_requested" or not master_open(s, copy))
        return
    if status == "skipped":
        _settle(cmd, "skipped", r)
        return
    # Definitive: failed / expired / not_executed — the attempt had no effect (4.6 step 5).
    _settle(cmd, "expired" if status == "expired" else "failed", r)
    if copy.position_id is not None:
        return  # exposure evidence already recorded (adoption): it wins
    code = r.get("error_code") or status
    if copy.state == "cancel_requested" or status in ("expired", "not_executed") or code in OPEN_CANCEL_CODES:
        mark_cancelled(s, copy, ctx, "open_" + ("expired" if status == "expired" else code))
    elif code in OPEN_SKIP_CODES:
        mark_open_failed(s, copy, ctx, state="skipped", reason=code)
    else:
        mark_open_failed(s, copy, ctx, state="error", reason=code)


def _close(s: Session, cmd: Command, copy: Copy, r: dict[str, Any], ctx: Ctx) -> None:
    status = r["status"]
    if status in ("done", "closed"):
        _settle(cmd, "done", r)
        mark_closed(s, copy, ctx, reason=r.get("close_reason") or "master_closed", deal=r.get("deal"),
                    price=r.get("price"), profit=r.get("profit"), fee=_fee(r))
    elif status == "done_partial":
        # Part of the volume closed: exposure remains, the copy stays closing, the rest is a new attempt (C2).
        residual = _d(r.get("residual_volume"))
        if residual is not None:
            copy.confirmed_volume = residual
        cmd.result = _jsonable(r)
        event(s, "copy.close_partial_fill", copy_id=copy.id, executed=r.get("executed_volume"), residual=residual)
        if residual is not None and residual <= 0:
            _settle(cmd, "done", r)
            mark_closed(s, copy, ctx, reason="master_closed", deal=r.get("deal"), price=r.get("price"))
        else:
            cmd.payload = {**(cmd.payload or {}), "volume": float(residual) if residual is not None else None}
            cmds.new_attempt(s, cmd, now=ctx.now)
    elif status == "uncertain":
        _mark_uncertain(s, cmd, copy, r, close_intent=True)
    elif status == "skipped":
        _settle(cmd, "skipped", r)
    elif r.get("error_code") == "position_not_found":
        # Wait for slave history: an exit deal for position_id closes it; otherwise the slave
        # snapshot reconciliation flags `close_unconfirmed` after 3 snapshots (5.5, S29).
        _settle(cmd, "failed", {**r, "not_found_snapshots": 0})
        event(s, "copy.close_position_not_found", copy_id=copy.id, command_id=cmd.id, position_id=copy.position_id)
    else:
        _retry(s, cmd, copy, r, ctx)


def _cancel(s: Session, cmd: Command, copy: Copy, r: dict[str, Any], ctx: Ctx) -> None:
    status = r["status"]
    if status == "not_executed":
        _settle(cmd, "done", r)
        if copy.position_id is None:
            mark_cancelled(s, copy, ctx, "master_closed")
    elif status in ("closed", "done"):
        # The open had executed; the EA closed that position and reports the close deal (4.4, S05).
        _settle(cmd, "done", r)
        if r.get("position_id") is not None and copy.position_id is None:
            copy.position_id = r["position_id"]
            copy.position_ticket = r.get("position_ticket")
        for open_cmd in cmds.outstanding(s, copy.id, ("open",)):
            open_cmd.state, open_cmd.result = "done", {"status": "done", "source": "cancel_closed"}
        mark_closed(s, copy, ctx, reason="master_closed", deal=r.get("deal"), price=r.get("price"),
                    profit=r.get("profit"), fee=_fee(r))
    elif status == "uncertain":
        _mark_uncertain(s, cmd, copy, r, close_intent=True)
    elif status == "skipped":
        _settle(cmd, "skipped", r)
    else:
        _retry(s, cmd, copy, r, ctx)


def _close_partial(s: Session, cmd: Command, copy: Copy, r: dict[str, Any], ctx: Ctx) -> None:
    status = r["status"]
    if status in ("done", "done_partial"):
        # Per-action evidence (4.6 step 4): executed volume and the resulting position volume.
        residual = _d(r.get("residual_volume"))
        if residual is None:
            executed = _d(r.get("executed_volume") or r.get("volume") or (cmd.payload or {}).get("volume"))
            base = copy.confirmed_volume if copy.confirmed_volume is not None else copy.volume
            if executed is not None and base is not None:
                residual = Decimal(base) - executed
        if residual is not None:
            copy.confirmed_volume = residual
            copy.volume = residual
        event(s, "copy.reduced", copy_id=copy.id, executed=r.get("executed_volume"), residual=residual,
              partial=status == "done_partial")
        if residual is not None and residual <= 0:
            _settle(cmd, "done", r)
            mark_closed(s, copy, ctx, reason="master_reduced", deal=r.get("deal"), price=r.get("price"))
            return
        target = _d(copy.reduction_target)
        rest = (residual - target) if (status == "done_partial" and residual is not None
                                       and target is not None) else None
        if rest is not None and rest > 0 and rest >= volume_min(s, copy) and copy.state == "open":
            # DONE_PARTIAL: same obligation, the remainder toward the (possibly coalesced) target as a
            # new attempt (4.6 step 4, C2).
            cmd.result = _jsonable(r)
            cmd.payload = {**(cmd.payload or {}), "volume": float(rest), "residual_volume": float(target)}
            cmds.new_attempt(s, cmd, now=ctx.now)
            return
        _settle(cmd, "done", r)
        # Reductions coalesced while this one was in flight: next delta from the persisted target (C7).
        advance_reduction(s, copy)
    elif status == "uncertain":
        _mark_uncertain(s, cmd, copy, r, close_intent=copy.close_intent)
    elif status == "skipped":
        _settle(cmd, "skipped", r)
    else:
        _retry(s, cmd, copy, r, ctx)


def _modify(s: Session, cmd: Command, copy: Copy, r: dict[str, Any], ctx: Ctx) -> None:
    """Audit only: a modify failure never changes the copy state (5.5)."""
    status = r["status"]
    if status in CONCLUSIVE:
        _settle(cmd, "done", r)
        payload = cmd.payload or {}
        copy.sl = _d(r["sl"]) if r.get("sl") is not None else _d(payload.get("sl"))
        copy.tp = _d(r["tp"]) if r.get("tp") is not None else _d(payload.get("tp"))
    elif status == "notmodify":
        _settle(cmd, "done", r)
        today = ctx.now.date().isoformat() if ctx.now else date.today().isoformat()
        if copy.notmodify_day != today:
            copy.notmodify_day, copy.notmodify_count = today, 0
        copy.notmodify_count += 1
        event(s, "copy.notmodify", copy_id=copy.id, count=copy.notmodify_count)
        if copy.notmodify_count >= NOTMODIFY_LIMIT and not copy.no_sltp:
            copy.no_sltp = True
            event(s, "copy.no_sltp", copy_id=copy.id)
    elif status == "skipped":
        _settle(cmd, "skipped", r)
    else:
        _settle(cmd, "failed", r)


def _resolve(s: Session, cmd: Command, copy: Copy, r: dict[str, Any], ctx: Ctx) -> None:
    _settle(cmd, "done" if r["status"] in CONCLUSIVE else "failed", r)


def _retry(s: Session, cmd: Command, copy: Copy, r: dict[str, Any], ctx: Ctx) -> None:
    """Definitive reject with no deal on a never-expiring obligation (close/close_partial/cancel):
    new attempt after backoff; the copy keeps its state and its reservation (5.5, S08, S35)."""
    cmd.result = _jsonable(r)
    delay = cmds.retry_backoff_seconds(cmd.attempts)
    cmds.new_attempt(s, cmd, delay_seconds=delay, now=ctx.now)
    event(s, "command.rejected", command_id=cmd.id, copy_id=copy.id, action=cmd.action,
          error_code=r.get("error_code"), retry_in_seconds=delay)


def _fee(r: dict[str, Any]) -> Decimal | None:
    parts = [_d(r.get(k)) for k in ("commission", "swap")]
    parts = [p for p in parts if p is not None]
    return sum(parts, Decimal(0)) if parts else None


def _d(v) -> Decimal | None:
    return None if v is None else Decimal(str(v))


def _jsonable(r: dict[str, Any]) -> dict[str, Any]:
    return {k: (str(v) if isinstance(v, Decimal) else v) for k, v in r.items() if v is not None}


def pending_not_found(s: Session, slave_id: int) -> list[tuple[Command, Copy]]:
    """Close commands answered `position_not_found` that still wait for slave history evidence."""
    rows = s.execute(select(Command, Copy).join(Copy, Command.copy_id == Copy.id).where(
        Copy.slave_id == slave_id, Command.action == "close", Command.state == "failed",
        Copy.state.in_(("closing", "superseded")))).all()
    return [(c, cp) for c, cp in rows if (c.result or {}).get("error_code") == "position_not_found"
            and not (c.result or {}).get("close_unconfirmed")]


__all__ = ["RESULT_STATUSES", "Outcome", "apply_results", "issue_close", "pending_not_found"]
