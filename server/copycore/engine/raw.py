"""Inbound raw storage and error signatures (design 5.9).

- Master snapshots: stored only when the copy-relevant state changed, plus one heartbeat
  sample per HEARTBEAT_SECONDS, gzipped.
- Errors: one `error_signatures` row per normalized signature (account, route, class, cause);
  first occurrence stores the raw body, repeats only advance counters and keep at most
  MAX_SAMPLES_PER_DAY sampled raw ids per day.
- A daily byte quota (RAW_DAILY_QUOTA_MB) stops new raw rows (counters keep advancing) and emits
  `storage.quota_reached` once per day. The quota never touches transactional state.
"""

from __future__ import annotations

import gzip
import json
from datetime import datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..models import ErrorSignature, Event, InboundRaw, utcnow
from ..security import sha256_hex

HEARTBEAT_SECONDS = 300
MAX_SAMPLES_PER_DAY = 5


def _aware(dt: datetime | None) -> datetime | None:
    return dt if dt is None or dt.tzinfo else dt.replace(tzinfo=utcnow().tzinfo)


def _day_start(now: datetime) -> datetime:
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


def quota_allows(s: Session, quota_mb: int, size: int) -> bool:
    now = utcnow()
    used = s.scalar(select(func.coalesce(func.sum(func.length(InboundRaw.content)), 0)).where(
        InboundRaw.received_at >= _day_start(now))) or 0
    if used + size <= quota_mb * 1024 * 1024:
        return True
    day = now.date().isoformat()
    already = s.scalar(select(func.count()).select_from(Event).where(
        Event.type == "storage.quota_reached", Event.created_at >= _day_start(now)))
    if not already:
        s.add(Event(type="storage.quota_reached", payload={"kind": "inbound_raw", "day": day}))
    return False


def store_raw(s: Session, *, account_id: int | None, kind: str, body: bytes, reason: str,
              quota_mb: int) -> InboundRaw | None:
    content = gzip.compress(body)
    if not quota_allows(s, quota_mb, len(content)):
        return None
    row = InboundRaw(account_id=account_id, kind=kind, content=content, content_sha256=sha256_hex(body),
                     reason=reason)
    s.add(row)
    s.flush()
    return row


def state_digest(state: object) -> str:
    return sha256_hex(json.dumps(state, sort_keys=True, default=str).encode())


def store_snapshot_raw(s: Session, *, account_id: int, kind: str, body: bytes, state: object,
                       quota_mb: int) -> InboundRaw | None:
    """Store on copy-relevant change (digest of the normalized state) or as a 5-minute heartbeat."""
    last = s.scalars(select(InboundRaw).where(InboundRaw.account_id == account_id, InboundRaw.kind == kind)
                     .order_by(InboundRaw.received_at.desc(), InboundRaw.id.desc()).limit(1)).first()
    digest = state_digest(state)
    if last is None:
        return store_raw(s, account_id=account_id, kind=kind, body=_tag(body, digest), reason="change",
                         quota_mb=quota_mb)
    try:
        last_state = json.loads(gzip.decompress(last.content)).get("_state_digest")
    except (OSError, ValueError, AttributeError):
        last_state = None
    if last_state != digest:
        return store_raw(s, account_id=account_id, kind=kind, body=_tag(body, digest), reason="change",
                         quota_mb=quota_mb)
    if utcnow() - _aware(last.received_at) >= timedelta(seconds=HEARTBEAT_SECONDS):
        return store_raw(s, account_id=account_id, kind=kind, body=_tag(body, digest), reason="heartbeat",
                         quota_mb=quota_mb)
    return None


def _tag(body: bytes, digest: str) -> bytes:
    """Embed the state digest so the next snapshot compares without re-normalizing the old body."""
    try:
        doc = json.loads(body)
    except ValueError:
        return body
    if isinstance(doc, dict):
        doc["_state_digest"] = digest
        return json.dumps(doc, separators=(",", ":")).encode()
    return body


def record_error(s: Session, *, account_id: int, route: str, error_class: str, cause: str, body: bytes,
                 quota_mb: int) -> ErrorSignature:
    """Deduplicate an error by its normalized signature (never includes seq/taken_at/session)."""
    signature = sha256_hex(f"{account_id}|{route}|{error_class}|{cause}".encode())
    now = utcnow()
    today = now.date().isoformat()
    row = s.get(ErrorSignature, (account_id, signature))
    if row is None:
        raw = store_raw(s, account_id=account_id, kind=f"error:{route}", body=body, reason="error",
                        quota_mb=quota_mb)
        row = ErrorSignature(account_id=account_id, signature=signature, first_raw_id=raw.id if raw else None,
                             count=1, first_seen=now, last_seen=now,
                             samples=[[today, raw.id]] if raw else [])
        s.add(row)
        return row
    row.count += 1
    row.last_seen = now
    todays = [smp for smp in (row.samples or []) if smp and smp[0] == today]
    if len(todays) < MAX_SAMPLES_PER_DAY:
        raw = store_raw(s, account_id=account_id, kind=f"error:{route}", body=body, reason="error",
                        quota_mb=quota_mb)
        if raw is not None:
            todays.append([today, raw.id])
    row.samples = todays
    return row
