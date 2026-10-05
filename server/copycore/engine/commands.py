"""Command issue and delivery (design 4.4, 4.5).

- A command is a durable logical obligation (`command_id`) with a current durable attempt
  (`attempt_id`). Execution parameters are frozen in its payload at issue time (C6).
- Delivery: a poll returns every command of the slave that is not acked and not terminal
  (`queued`, `delivered`, `retry_wait` past its time, `in_progress` whose lease expired).
  The cursor is only a hint and never hides an un-acked command.
- `in_progress` is a receipt ack: the command goes under a lease and is not re-sent until the
  lease expires or the slave starts a new session.
- Expiry: only `open` expires, and only before it was ever sent (state `queued`): the open is
  marked `expired` and the copy `cancelled` (open never delivered → no exposure, 5.5).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..models import Command, CommandAttempt, Copy, Event, utcnow

TERMINAL_COMMAND_STATES = ("done", "failed", "expired", "superseded", "skipped")


def new_command_id() -> str:
    return "c_" + uuid.uuid4().hex


def new_attempt_id() -> str:
    return "a_" + uuid.uuid4().hex


def ms(dt: datetime | None) -> int | None:
    if dt is None:
        return None
    return int(aware(dt).timestamp() * 1000)


def aware(dt: datetime | None) -> datetime | None:
    return dt if dt is None or dt.tzinfo else dt.replace(tzinfo=utcnow().tzinfo)


def wire(v):
    """JSON-safe numbers for payloads (Decimal → float)."""
    return float(v) if isinstance(v, Decimal) else v


def issue(s: Session, copy: Copy, action: str, payload: dict, *, ttl_seconds: int | None = None) -> Command:
    now = utcnow()
    seq = (s.scalar(select(func.max(Command.seq_in_copy)).where(Command.copy_id == copy.id)) or 0) + 1
    cmd = Command(id=new_command_id(), copy_id=copy.id, seq_in_copy=seq, action=action,
                  payload={k: wire(v) for k, v in payload.items()}, state="queued",
                  attempt_id=new_attempt_id(), attempts=1, issued_at=now,
                  expires_at=now + timedelta(seconds=ttl_seconds) if ttl_seconds else None)
    s.add(cmd)
    s.flush()
    s.add(CommandAttempt(command_id=cmd.id, attempt_id=cmd.attempt_id, issued_at=now))
    return cmd


def command_json(cmd: Command) -> dict:
    return {
        **(cmd.payload or {}),
        "command_id": cmd.id,
        "attempt_id": cmd.attempt_id,
        "action": cmd.action,
        "copy_id": cmd.copy_id,
        "seq_in_copy": cmd.seq_in_copy,
        "issued_at": ms(cmd.issued_at),
        "expires_at": ms(cmd.expires_at),
    }


def _live_commands(s: Session, slave_id: int) -> list[tuple[Command, Copy]]:
    rows = s.execute(select(Command, Copy).join(Copy, Command.copy_id == Copy.id).where(
        Copy.slave_id == slave_id, Command.state.not_in(TERMINAL_COMMAND_STATES))).all()
    return [(c, cp) for c, cp in rows]


def expire_opens(s: Session, slave_id: int, now: datetime | None = None, ctx=None) -> list[str]:
    """Expire never-sent `open` commands past `expires_at` (4.4); the copy becomes `cancelled`.
    With an engine context the freed netting slot promotes its blocked successor (C5)."""
    now = now or utcnow()
    expired = []
    for cmd, copy in _live_commands(s, slave_id):
        if cmd.action != "open" or cmd.state != "queued" or cmd.expires_at is None:
            continue
        if aware(cmd.expires_at) > now:
            continue
        cmd.state = "expired"
        cmd.result = {"status": "expired", "reason": "open_ttl_before_delivery"}
        if copy.state == "pending":
            copy.state = "cancelled"
            copy.close_reason = "open_expired"
            s.add(Event(type="copy.cancelled", payload={"copy_id": copy.id, "reason": "open_expired",
                                                        "command_id": cmd.id}))
            if ctx is not None:
                from .lifecycle import promote_successors  # lifecycle imports this module
                promote_successors(s, copy, ctx)
        expired.append(cmd.id)
    return expired


def deliver(s: Session, slave_id: int, now: datetime | None = None) -> list[Command]:
    """Un-acked commands for this slave, ordered per copy in issue order; marks them delivered."""
    now = now or utcnow()
    out = []
    for cmd, _copy in _live_commands(s, slave_id):
        if cmd.state == "retry_wait" and cmd.next_attempt_at is not None and aware(cmd.next_attempt_at) > now:
            continue
        if cmd.state == "in_progress" and cmd.lease_until is not None and aware(cmd.lease_until) > now:
            continue  # acked and leased
        if cmd.state == "in_progress" and is_uncertain(cmd):
            continue  # the EA suspended this attempt (4.6 step 7); a new session re-delivers it once
        if cmd.state in ("queued", "retry_wait", "in_progress"):
            cmd.state = "delivered"
            cmd.lease_until = None
        out.append(cmd)
    # A `resolve` is a journal update the EA applies on receipt (4.6 step 7): it goes first, so a
    # re-issued attempt of the command it settles is never seen before it.
    out.sort(key=lambda c: (c.action != "resolve", aware(c.issued_at), c.copy_id, c.seq_in_copy))
    return out


def cursor_for(s: Session, slave_id: int) -> str:
    last = s.scalar(select(func.max(Command.issued_at)).join(Copy, Command.copy_id == Copy.id)
                    .where(Copy.slave_id == slave_id))
    return str(ms(last) or 0)


def ack_in_progress(s: Session, slave_id: int, command_id: str, copy_id: int | None, lease_seconds: int,
                    now: datetime | None = None) -> bool:
    """Receipt ack (C2): lease the command. Returns False for unknown/foreign commands."""
    now = now or utcnow()
    cmd = s.get(Command, command_id)
    if cmd is None:
        return False
    copy = s.get(Copy, cmd.copy_id)
    if copy is None or copy.slave_id != slave_id or (copy_id is not None and copy_id != copy.id):
        return False
    if cmd.state in TERMINAL_COMMAND_STATES:
        return True  # already settled; a late receipt ack is a no-op
    cmd.state = "in_progress"
    cmd.acked_at = cmd.acked_at or now
    cmd.lease_until = now + timedelta(seconds=lease_seconds)
    return True


def release_leases(s: Session, slave_id: int) -> int:
    """New slave session (4.5): leased commands are re-delivered; the EA answers from its journal."""
    n = 0
    for cmd, _copy in _live_commands(s, slave_id):
        if cmd.state == "in_progress":
            cmd.state = "delivered"
            cmd.lease_until = None
            n += 1
    return n


def is_uncertain(cmd: Command) -> bool:
    return (cmd.result or {}).get("status") == "uncertain"


def retry_backoff_seconds(attempts: int) -> int:
    """Backoff before a new attempt of a never-expiring obligation (close/cancel): 5, 10, 20 ... 300 s."""
    return min(5 * 2 ** max(attempts - 1, 0), 300)


def new_attempt(s: Session, cmd: Command, *, delay_seconds: int = 0, now: datetime | None = None) -> str:
    """Same logical obligation (`command_id`), new durable attempt (`attempt_id`) (4.6, C2).

    Issued only after a definitive reject with no effect, or for the remainder of a DONE_PARTIAL."""
    now = now or utcnow()
    cmd.attempt_id = new_attempt_id()
    cmd.attempts = (cmd.attempts or 1) + 1
    cmd.state = "retry_wait" if delay_seconds > 0 else "queued"
    cmd.next_attempt_at = now + timedelta(seconds=delay_seconds) if delay_seconds > 0 else None
    cmd.lease_until = None
    s.add(CommandAttempt(command_id=cmd.id, attempt_id=cmd.attempt_id, issued_at=now))
    s.add(Event(type="command.retry", payload={"command_id": cmd.id, "copy_id": cmd.copy_id,
                                               "attempt_id": cmd.attempt_id, "attempts": cmd.attempts,
                                               "delay_seconds": delay_seconds}))
    return cmd.attempt_id


def outstanding(s: Session, copy_id: int, actions: tuple[str, ...] | None = None) -> list[Command]:
    q = select(Command).where(Command.copy_id == copy_id, Command.state.not_in(TERMINAL_COMMAND_STATES))
    if actions is not None:
        q = q.where(Command.action.in_(actions))
    return list(s.scalars(q.order_by(Command.seq_in_copy)))


def renew_leases(s: Session, slave_id: int, lease_seconds: int, now: datetime | None = None) -> int:
    """A snapshot from the current session renews the receipt-ack leases (4.5)."""
    now = now or utcnow()
    n = 0
    for cmd, _copy in _live_commands(s, slave_id):
        if cmd.state == "in_progress" and cmd.lease_until is not None:
            cmd.lease_until = now + timedelta(seconds=lease_seconds)
            n += 1
    return n
