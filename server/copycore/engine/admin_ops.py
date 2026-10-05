"""Operator actions shared by the admin API and the admin UI (design 4.6 step 7, 5.8, 5.8a, 6.2, C3, C6, C8).

- **Drain** (6.2, C6): entering account suspension or disabling a link/group takes back every open
  not yet executed, in the same transaction: `pending` with the open proven unsent → `cancelled`;
  `pending` with the open delivered/in progress → `cancel_requested` + `cancel`; `pending_blocked`
  → `cancelled`. Copies with possible exposure (`open`, `closing`, `uncertain`, `superseded` with
  `close_intent`) keep full management.
- **Copy resolution** (4.6 step 7, 5.8): an operator settles a suspended attempt (`uncertain`) as
  `executed` or `not_executed`, or settles a close that never found evidence (`close_unconfirmed`,
  or exposure left on a revoked slave) as `closed` / `retry_close`. Each one is audited
  (`admin.resolved`) and, when an EA attempt was suspended, emits a `resolve` command so the EA
  journal leaves `suspended`. The `resolve` command is issued **before** any follow-up command of
  the copy, and the EA applies it on receipt (it is a journal update, not a trade).
- **Conflict resolution** (5.8, C8): `accept` the extra exposure (the block on new opens ends), or
  `close` it by its position identity. The close travels on a `superseded` sibling copy without
  `close_intent` (it never takes a reservation) and the conflict stays open until the close is
  confirmed.

Business refusals raise `ApiError` (409 / 422); nothing here is partially applied.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal

from sqlalchemy import and_, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..errors import ApiError
from ..models import (
    EXPOSURE_STATES,
    Account,
    Command,
    CommandAttempt,
    Copy,
    CopyLink,
    SymbolConflict,
)
from . import commands as cmds
from .lifecycle import (
    Ctx,
    Fill,
    advance_reduction,
    apply_fill,
    event,
    issue_close,
    mark_cancelled,
    mark_closed,
    master_open,
    withdraw_pending,
)

COPY_RESOLUTIONS = ("executed", "not_executed", "closed", "retry_close")
CONFLICT_RESOLUTIONS = ("accept", "close")


# --- drain (6.2, C6) ----------------------------------------------------------------------------------

def drain_copies(s: Session, ctx: Ctx, reason: str, *, slave_id: int | None = None,
                 master_id: int | None = None, link_ids: list[int] | None = None) -> dict:
    """C6 transitions for the not-yet-executed copies in scope. The caller has already flipped the
    account status / link flag, so a successor promoted by a freed slot is revalidated and skipped."""
    q = select(Copy).where(Copy.state.in_(("pending_blocked", "pending")))
    if slave_id is not None:
        q = q.where(Copy.slave_id == slave_id)
    if master_id is not None:
        q = q.where(Copy.link_id.in_(select(CopyLink.id).where(CopyLink.master_id == master_id)))
    if link_ids is not None:
        q = q.where(Copy.link_id.in_(link_ids or [-1]))
    stats = {"cancelled": 0, "cancel_requested": 0}
    # Blocked candidates first: cancelling them never promotes anything into the drained scope.
    for copy in sorted(s.scalars(q), key=lambda c: (c.state != "pending_blocked", c.id)):
        # Same identity-mapped instances: an earlier transition in this loop is already visible here.
        if copy.state == "pending_blocked":
            copy.blocked_by = None
            mark_cancelled(s, copy, ctx, reason)
            stats["cancelled"] += 1
        elif copy.state == "pending":
            stats[withdraw_pending(s, copy, ctx, reason)] += 1
    if any(stats.values()):
        event(s, "drain.applied", reason=reason, slave_id=slave_id, master_id=master_id, link_ids=link_ids,
              **stats)
    return stats


# --- copy resolution (4.6 step 7, 5.8) -------------------------------------------------------------------

@dataclass
class CopyResolution:
    resolution: str
    position_id: int | None = None
    volume: Decimal | None = None  # executed volume of an open; residual volume of a close_partial
    price: Decimal | None = None
    note: str | None = None


def uncertain_command(s: Session, copy: Copy) -> Command | None:
    for cmd in cmds.outstanding(s, copy.id):
        if cmds.is_uncertain(cmd):
            return cmd
    return None


def close_unconfirmed_command(s: Session, copy: Copy) -> Command | None:
    """The close answered `position_not_found` that never found an exit deal (5.5, S29)."""
    for cmd in s.scalars(select(Command).where(Command.copy_id == copy.id, Command.action == "close",
                                               Command.state == "failed").order_by(Command.seq_in_copy.desc())):
        if (cmd.result or {}).get("error_code") == "position_not_found":
            return cmd
    return None


def exposed(copy: Copy) -> bool:
    return copy.state in EXPOSURE_STATES or (copy.state == "superseded" and copy.close_intent)


def resolve_copy(s: Session, copy: Copy, ctx: Ctx, r: CopyResolution, actor: str) -> dict:
    if r.resolution not in COPY_RESOLUTIONS:
        raise ApiError(422, "validation", f"resolution must be one of {', '.join(COPY_RESOLUTIONS)}")
    prior = copy.state
    cmd = uncertain_command(s, copy)
    issued: Command | None = None
    if r.resolution in ("executed", "not_executed"):
        if cmd is None and copy.state != "uncertain":
            raise ApiError(409, "not_resolvable", "the copy has no suspended (uncertain) attempt")
        outcome, issued = _resolve_suspended(s, copy, cmd, ctx, r, actor)
    elif r.resolution == "closed":
        slave = s.get(Account, copy.slave_id)
        unconfirmed = close_unconfirmed_command(s, copy)
        if not exposed(copy) or not (unconfirmed is not None or (slave is not None and slave.status == "revoked")
                                     or copy.state == "uncertain"):
            raise ApiError(409, "not_resolvable",
                           "`closed` applies to close_unconfirmed, uncertain or revoked-slave copies")
        if cmd is not None:
            issued = _issue_resolve(s, copy, cmd, "executed" if cmd.action in ("close", "cancel") else "closed",
                                    r)
            _settle_attempt(s, cmd, "done", actor)
        mark_closed(s, copy, ctx, reason="operator_closed")
        outcome = "closed"
    else:  # retry_close
        unconfirmed = close_unconfirmed_command(s, copy)
        if unconfirmed is None or copy.state not in ("closing", "superseded"):
            raise ApiError(409, "not_resolvable", "`retry_close` applies to a close answered position_not_found")
        unconfirmed.result = {k: v for k, v in (unconfirmed.result or {}).items()
                              if k not in ("not_found_snapshots", "close_unconfirmed")}
        if copy.close_reason == "close_unconfirmed":
            copy.close_reason = None
        cmds.new_attempt(s, unconfirmed, now=ctx.now)
        outcome = "close_reissued"
    event(s, "admin.resolved", target="copy", copy_id=copy.id, resolution=r.resolution, actor=actor,
          note=r.note, prior_state=prior, state=copy.state, outcome=outcome,
          command_id=cmd.id if cmd is not None else None, resolve_command_id=issued.id if issued else None,
          position_id=r.position_id)
    return {"copy_id": copy.id, "resolution": r.resolution, "outcome": outcome, "prior_state": prior,
            "state": copy.state, "resolve_command_id": issued.id if issued else None}


def _resolve_suspended(s: Session, copy: Copy, cmd: Command | None, ctx: Ctx, r: CopyResolution,
                       actor: str) -> tuple[str, Command]:
    action = cmd.action if cmd is not None else "open"
    executed = r.resolution == "executed"
    if executed and action == "open" and r.position_id is None and copy.position_id is None:
        raise ApiError(422, "validation", "position_id is required to resolve an open as executed")
    if executed and action == "close_partial" and r.volume is None:
        raise ApiError(422, "validation", "volume (the position's residual volume) is required for close_partial")
    if not executed and action in ("open", "cancel") and copy.position_id is not None:
        raise ApiError(409, "not_resolvable", "the copy already has a position: it cannot be not_executed")

    issued = _issue_resolve(s, copy, cmd, r.resolution, r)
    if cmd is not None:
        _settle_attempt(s, cmd, "done" if executed else "failed", actor)

    if action == "open":
        if executed:
            pid = r.position_id if r.position_id is not None else copy.position_id
            outcome = apply_fill(s, copy, Fill(position_id=pid, price=r.price, volume=r.volume), ctx, source="operator")
        else:
            mark_cancelled(s, copy, ctx, "operator_not_executed")
            outcome = "cancelled"
    elif action == "cancel":
        if executed:  # the open had executed and the EA's cancel closed that position (S05)
            if r.position_id is not None and copy.position_id is None:
                copy.position_id = r.position_id
            for open_cmd in cmds.outstanding(s, copy.id, ("open",)):
                open_cmd.state, open_cmd.result = "done", {"status": "done", "source": "operator"}
            mark_closed(s, copy, ctx, reason=(cmd.payload or {}).get("reason") or "master_closed")
            outcome = "closed"
        else:  # no position ever came from this copy
            mark_cancelled(s, copy, ctx, "operator_not_executed")
            outcome = "cancelled"
    elif action == "close":
        if executed:
            mark_closed(s, copy, ctx, reason="master_closed", price=r.price)
            outcome = "closed"
        else:  # the close had no effect: same obligation, new attempt
            if copy.state == "uncertain":
                copy.state = "closing"
            cmds.new_attempt(s, cmd, now=ctx.now)
            outcome = "close_reissued"
    elif action == "close_partial":
        if copy.state == "uncertain":
            copy.state = "open"
        if executed:
            copy.confirmed_volume = copy.volume = r.volume
            event(s, "copy.reduced", copy_id=copy.id, residual=r.volume, source="operator")
            if r.volume <= 0:
                mark_closed(s, copy, ctx, reason="master_reduced")
                return "closed", issued
        outcome = _follow_up(s, copy)
    else:
        raise ApiError(409, "not_resolvable", f"a suspended {action} cannot be resolved this way")
    return outcome, issued


def _follow_up(s: Session, copy: Copy) -> str:
    """Back to `open` after a resolved reduction: close if the master closed meanwhile, else continue
    toward the persisted reduction target (5.4, C7)."""
    if copy.close_intent or not master_open(s, copy):
        issue_close(s, copy, "master_closed")
        return "closing"
    advance_reduction(s, copy)
    return "open"


def _settle_attempt(s: Session, cmd: Command, state: str, actor: str) -> None:
    att = s.get(CommandAttempt, (cmd.id, cmd.attempt_id))
    if att is not None:
        att.outcome = "done" if state == "done" else "rejected"
        att.evidence = {**(att.evidence or {}), "source": "operator", "actor": actor}
    cmd.state, cmd.lease_until = state, None
    cmd.result = {**(cmd.result or {}), "status": state, "source": "operator"}


def _issue_resolve(s: Session, copy: Copy, cmd: Command | None, resolution: str, r: CopyResolution) -> Command:
    """The `resolve` command for the EA journal (4.6 step 7): the suspended entry becomes `confirmed`."""
    params = copy.exec_params or {}
    return cmds.issue(s, copy, "resolve", {
        "resolves_command_id": cmd.id if cmd is not None else None,
        "resolves_attempt_id": cmd.attempt_id if cmd is not None else None,
        "resolves_action": cmd.action if cmd is not None else None,
        "resolution": resolution, "symbol": copy.symbol_local,
        "position_id": r.position_id if r.position_id is not None else copy.position_id,
        "residual_volume": r.volume if cmd is not None and cmd.action == "close_partial" else None,
        "magic": params.get("magic"), "comment": params.get("comment", f"c{copy.id}")})


# --- symbol conflict resolution (5.8, C8) ------------------------------------------------------------------

def conflict_close_command(s: Session, conflict: SymbolConflict) -> Command | None:
    rows = s.execute(select(Command).join(Copy, Command.copy_id == Copy.id).where(
        Copy.slave_id == conflict.slave_id, Command.action == "close",
        Command.state.not_in(cmds.TERMINAL_COMMAND_STATES))).scalars()
    return next((c for c in rows if (c.payload or {}).get("conflict_id") == conflict.id), None)


def resolve_conflict(s: Session, conflict: SymbolConflict, ctx: Ctx, resolution: str, note: str | None,
                     actor: str) -> dict:
    if resolution not in CONFLICT_RESOLUTIONS:
        raise ApiError(422, "validation", f"resolution must be one of {', '.join(CONFLICT_RESOLUTIONS)}")
    if conflict.resolved_at is not None:
        raise ApiError(409, "already_resolved", "the conflict is already resolved")
    pending = conflict_close_command(s, conflict)
    copy = s.get(Copy, conflict.copy_id) if conflict.copy_id is not None else None
    close_cmd: Command | None = None
    if resolution == "accept":
        if pending is not None:
            raise ApiError(409, "close_in_flight", "a close of this exposure is in flight; wait for its result")
        conflict.resolved_at = ctx.now
        conflict.resolution = "accepted" + (f": {note}" if note else "")
    else:
        if conflict.position_id is None or copy is None:
            raise ApiError(409, "not_resolvable", "the conflict has no position identity to close")
        close_cmd = pending or _issue_conflict_close(s, conflict, copy, ctx)
        conflict.resolution = f"close_requested (command {close_cmd.id})"
    issued = None
    if copy is not None:
        params = copy.exec_params or {}
        issued = cmds.issue(s, copy, "resolve", {
            "resolves_command_id": None, "resolves_attempt_id": None, "resolves_action": None,
            "conflict_id": conflict.id, "resolution": resolution, "symbol": conflict.symbol_local,
            "position_id": conflict.position_id, "residual_volume": None,
            "magic": params.get("magic"), "comment": params.get("comment", f"c{copy.id}")})
    event(s, "admin.resolved", target="symbol_conflict", conflict_id=conflict.id, kind=conflict.kind,
          resolution=resolution, actor=actor, note=note, position_id=conflict.position_id,
          close_command_id=close_cmd.id if close_cmd else None, resolve_command_id=issued.id if issued else None)
    return {"conflict_id": conflict.id, "resolution": resolution,
            "resolved": conflict.resolved_at is not None,
            "close_command_id": close_cmd.id if close_cmd else None,
            "resolve_command_id": issued.id if issued else None}


def _issue_conflict_close(s: Session, conflict: SymbolConflict, copy: Copy, ctx: Ctx) -> Command:
    carrier = s.scalar(select(Copy).where(
        Copy.slave_id == conflict.slave_id, Copy.position_id == conflict.position_id,
        Copy.state == "superseded", Copy.close_intent.is_(False), Copy.close_reason.is_(None)).limit(1))
    if carrier is None:
        carrier = Copy(link_id=copy.link_id, master_position_id=copy.master_position_id, slave_id=copy.slave_id,
                       slave_margin_mode=copy.slave_margin_mode, symbol_master=copy.symbol_master,
                       symbol_local=conflict.symbol_local, state="superseded", close_intent=False,
                       position_id=conflict.position_id, opened_at=ctx.now,
                       exec_params={"magic": None, "comment": None, "conflict_id": conflict.id})
        try:
            with s.begin_nested():
                s.add(carrier)
                s.flush()
        except IntegrityError as exc:  # the position identity is held by a managed copy (hedging)
            raise ApiError(409, "not_resolvable",
                           "that position is held by a managed copy: resolve the copy instead") from exc
    return cmds.issue(s, carrier, "close", {
        "symbol": conflict.symbol_local, "position_id": conflict.position_id, "volume": None,
        "magic": None, "comment": None, "conflict_id": conflict.id})


# --- operator listings ------------------------------------------------------------------------------------

def attention(s: Session, limit: int = 200) -> dict:
    """What needs an operator (the "orphans" of the Phase 1 exit criteria): suspended copies,
    closes without evidence, exposure left on revoked slaves, and open symbol conflicts."""
    uncertain = list(s.scalars(select(Copy).where(Copy.state == "uncertain").order_by(Copy.id).limit(limit)))
    unconfirmed = list(s.scalars(select(Copy).where(Copy.close_reason == "close_unconfirmed",
                                                    Copy.state.in_(("closing", "superseded")))
                                 .order_by(Copy.id).limit(limit)))
    revoked = list(s.scalars(select(Copy).join(Account, Copy.slave_id == Account.id).where(
        Account.status == "revoked",
        or_(Copy.state.in_(EXPOSURE_STATES), and_(Copy.state == "superseded", Copy.close_intent)))
        .order_by(Copy.id).limit(limit)))
    conflicts = list(s.scalars(select(SymbolConflict).where(SymbolConflict.resolved_at.is_(None))
                               .order_by(SymbolConflict.id).limit(limit)))
    return {"uncertain": uncertain, "close_unconfirmed": unconfirmed, "revoked_exposure": revoked,
            "conflicts": conflicts}


__all__ = ["COPY_RESOLUTIONS", "CONFLICT_RESOLUTIONS", "CopyResolution", "attention", "close_unconfirmed_command",
           "drain_copies", "resolve_conflict", "resolve_copy", "uncertain_command"]
