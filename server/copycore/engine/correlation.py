"""Copier comment correlation (design 5.8a, owner decision 2026-10-06).

The slave order comment is `c<copy_id>-<master position_id>` (POSITION_IDENTIFIER of the master), so
slave and master can be compared side by side. When that would exceed the MT5 comment limit (31 chars)
the comment falls back to the legacy `c<copy_id>`.

Correlation only ever uses the `c<copy_id>` part, always together with the copy's frozen magic:

- `c<digits>-<anything>`: the copy id is the digits between `c` and the first `-`. The `-` proves the
  digits are complete, so a suffix that the broker truncated or rewrote does not matter. A digits-only
  suffix is a master position id written by a copier: it must be this copy's (or a truncation of it);
  `c22-<another master id>` is another copy that reused the id (another Copy Server, a reset sequence).
- `c<digits>` (no `-`): either the legacy/fallback comment, or a comment the broker truncated. A cut
  exactly before the `-` cannot be told apart from a cut inside the digits (`c13-77` → `c1`), so this
  form is accepted only for a copy whose frozen comment is exactly `c<copy_id>` (legacy/fallback).
  For a copy issued with the long form it is ambiguous and rejected: the execution stays for manual
  reconciliation (5.8 resolution path) instead of risking a wrong adoption.
- Anything else (no `c<digits>` prefix, `c` followed by a non-digit) is not a copier comment.

Time bound (`fresh`): snapshot evidence correlated by comment counts only when it is not older than the
copy. Deal/position `time_msc` is broker server time (the broker's wall clock written as if UTC); the
EA reports `broker_offset_ms` (broker time - EA UTC) and `ea_clock_offset_ms` (server - EA), so
server time = time_msc - broker_offset_ms + ea_clock_offset_ms, compared with `created_at - SKEW`.
An EA that does not report `broker_offset_ms` gets `UNKNOWN_OFFSET_MS` of slack (any broker timezone).
"""

from __future__ import annotations

import re
from datetime import UTC, datetime
from typing import Any

MT5_COMMENT_MAX = 31
SKEW_MS = 5_000
UNKNOWN_OFFSET_MS = 14 * 3_600_000
_PREFIX = re.compile(r"^c(\d+)(-)?")
_STRICT = re.compile(r"^c(\d+)(?:-.*)?$", re.S)


def build_comment(copy_id: int, master_position_id: int | None) -> str:
    legacy = f"c{copy_id}"
    if master_position_id is None:
        return legacy
    full = f"{legacy}-{master_position_id}"
    return full if len(full) <= MT5_COMMENT_MAX else legacy


def candidate_copy_id(comment: str | None) -> int | None:
    """Copy id a comment may refer to (still to be confirmed with `matches`)."""
    m = _STRICT.match(comment or "")
    return int(m.group(1)) if m else None


def matches(exec_params: dict[str, Any] | None, copy_id: int, comment: str | None, magic: int | None) -> bool:
    """True when `comment` + `magic` correlate with copy `copy_id` (frozen `exec_params`)."""
    params = exec_params or {}
    if params.get("magic") != magic:
        return False
    m = _PREFIX.match(comment or "")
    if not m or not _STRICT.match(comment or "") or int(m.group(1)) != copy_id:
        return False
    if m.group(2):  # `c<id>-...`: digits complete
        expected = str(params.get("comment") or "")
        got_sfx, exp_sfx = (comment or "")[m.end():], expected.partition("-")[2]
        if got_sfx.isdigit() and exp_sfx.isdigit() and expected.startswith(f"c{copy_id}-"):
            return exp_sfx.startswith(got_sfx)  # ours, or ours truncated by the broker
        return True
    # bare `c<id>`: legacy/fallback only; ambiguous for a long-form copy (possible truncation).
    return comment == f"c{copy_id}" and params.get("comment", f"c{copy_id}") == f"c{copy_id}"


def fresh(time_msc: int | None, created_at: datetime | None, *, ea_clock_offset_ms: int = 0,
          broker_offset_ms: int | None = None) -> bool:
    """True when broker-time `time_msc` is not older than `created_at` (server clock) minus the skew."""
    if created_at is None:
        return True
    if time_msc is None:
        return False
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=UTC)
    floor = int(created_at.timestamp() * 1000) - SKEW_MS
    if broker_offset_ms is None:
        return time_msc + ea_clock_offset_ms + UNKNOWN_OFFSET_MS >= floor
    return time_msc - broker_offset_ms + ea_clock_offset_ms >= floor
