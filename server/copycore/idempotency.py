"""Idempotency-Key handling for mutating calls (4.1, 5.7).

- Same key + same request → the stored response is replayed.
- Same key + different request (body or route) → 409 `idempotency_key_reuse`.
- Token-bearing responses (enroll, rotate) are NEVER stored: only a marker row
  (kind='token', response=NULL) is written, and a replay is answered by the D8 recovery
  rules (re-enroll within TTL / 409 rotation_pending), not by the cache.
"""

from __future__ import annotations

from datetime import timedelta

from fastapi import Request
from fastapi.responses import Response
from sqlalchemy.orm import Session

from .errors import ApiError, json_response, server_time_ms
from .models import IdempotencyKey, utcnow
from .security import sha256_hex

HEADER = "Idempotency-Key"
MAX_KEY_LEN = 128


def request_key(request: Request) -> str:
    key = request.headers.get(HEADER)
    if not key:
        raise ApiError(400, "idempotency_key_required", f"{HEADER} header is required on mutating calls")
    if len(key) > MAX_KEY_LEN:
        raise ApiError(400, "idempotency_key_invalid", "Idempotency-Key too long")
    return key


def request_hash(method: str, route: str, body: bytes) -> str:
    return sha256_hex(method.encode() + b" " + route.encode() + b"\n" + body)


def lookup(session: Session, *, account_id: int, key: str, route: str, req_hash: str,
           ttl_hours: int) -> Response | None:
    """Return the stored response to replay, None to process the request, or raise 409."""
    row = session.get(IdempotencyKey, (account_id, key))
    if row is None:
        return None
    created = row.created_at if row.created_at.tzinfo else row.created_at.replace(tzinfo=utcnow().tzinfo)
    if utcnow() - created > timedelta(hours=ttl_hours):
        session.delete(row)
        session.flush()
        return None
    if row.request_sha256 != req_hash or row.route != route:
        raise ApiError(409, "idempotency_key_reuse", "Idempotency-Key reused with a different request")
    if row.kind == "token":
        return None  # never cached; caller applies the D8 recovery rules
    return replay(row)


def replay(row: IdempotencyKey) -> Response:
    if row.status_code == 204:
        return Response(status_code=204)
    body = dict(row.response or {})
    body["server_time"] = server_time_ms()
    return json_response(body, row.status_code or 200, {"Idempotent-Replay": "true"})


def record(session: Session, *, account_id: int, key: str, route: str, req_hash: str, status_code: int,
           response: dict | None, token_bearing: bool) -> None:
    if session.get(IdempotencyKey, (account_id, key)) is not None:
        return  # marker already present (token-bearing replay)
    if token_bearing:
        row = IdempotencyKey(account_id=account_id, key=key, route=route, request_sha256=req_hash,
                             kind="token", status_code=status_code, response=None)
    else:
        stored = {k: v for k, v in (response or {}).items() if k != "server_time"}
        row = IdempotencyKey(account_id=account_id, key=key, route=route, request_sha256=req_hash,
                             kind="response", status_code=status_code, response=stored)
    session.add(row)
