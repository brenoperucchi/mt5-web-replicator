"""Copier comment correlation (design 5.8a, owner decision 2026-10-06).

The slave order comment is `c<copy_id>-<master position_id>` (POSITION_IDENTIFIER of the master), so
slave and master can be compared side by side. When that would exceed the MT5 comment limit (31 chars)
the comment falls back to the legacy `c<copy_id>`.

Correlation only ever uses the `c<copy_id>` part, always together with the copy's frozen magic:

- `c<digits>-<anything>`: the copy id is the digits between `c` and the first `-`. The `-` proves the
  digits are complete, so a suffix that the broker truncated or rewrote does not matter.
- `c<digits>` (no `-`): either the legacy/fallback comment, or a comment the broker truncated. A cut
  exactly before the `-` cannot be told apart from a cut inside the digits (`c13-77` → `c1`), so this
  form is accepted only for a copy whose frozen comment is exactly `c<copy_id>` (legacy/fallback).
  For a copy issued with the long form it is ambiguous and rejected: the execution stays for manual
  reconciliation (5.8 resolution path) instead of risking a wrong adoption.
- Anything else (no `c<digits>` prefix, `c` followed by a non-digit) is not a copier comment.
"""

from __future__ import annotations

import re
from typing import Any

MT5_COMMENT_MAX = 31
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
        return True
    # bare `c<id>`: legacy/fallback only; ambiguous for a long-form copy (possible truncation).
    return comment == f"c{copy_id}" and params.get("comment", f"c{copy_id}") == f"c{copy_id}"
