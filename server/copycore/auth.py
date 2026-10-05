"""Bearer authentication for EA accounts (D8, 6.2) and admin tokens (6.3).

401: missing/invalid/revoked token. 403: account suspended (or version-gated) with no open
copies; with open copies the call proceeds and `/v4/config` reports `mode: drain` (6.2).
"""

from __future__ import annotations

import hmac
from dataclasses import dataclass
from datetime import timedelta

from fastapi import Request
from sqlalchemy import and_, exists, or_, select
from sqlalchemy.orm import Session

from .config import Settings
from .errors import ApiError
from .models import EXPOSURE_STATES, Account, ApiToken, Copy, CopyLink, EnrollCode, utcnow
from .security import hmac_hex


@dataclass
class AuthContext:
    account: Account
    token_hash: str
    via_pending: bool  # authenticated with the not-yet-confirmed rotation token


def bearer(request: Request) -> str:
    header = request.headers.get("Authorization", "")
    scheme, _, value = header.partition(" ")
    if scheme.lower() != "bearer" or not value.strip():
        raise ApiError(401, "missing_token", "Authorization: Bearer <token> required")
    return value.strip()


def aware(dt):
    return dt if dt is None or dt.tzinfo else dt.replace(tzinfo=utcnow().tzinfo)


def pending_expired(acct: Account, settings: Settings) -> bool:
    issued = aware(acct.pending_token_issued_at)
    return issued is None or utcnow() - issued > timedelta(hours=settings.pending_token_ttl_hours)


def has_exposure(session: Session, acct: Account) -> bool:
    exposed = or_(Copy.state.in_(EXPOSURE_STATES), and_(Copy.state == "superseded", Copy.close_intent))
    if acct.role == "slave":
        q = exists().where(Copy.slave_id == acct.id, exposed)
    else:
        q = exists().where(Copy.link_id == CopyLink.id, CopyLink.master_id == acct.id, exposed)
    return bool(session.scalar(select(q)))


def version_tuple(v: str | None) -> tuple[int, ...]:
    parts = []
    for p in (v or "").replace("-", ".").split("."):
        digits = "".join(ch for ch in p if ch.isdigit())
        parts.append(int(digits) if digits else 0)
    return tuple(parts)


def version_gated(acct: Account, settings: Settings) -> bool:
    return bool(settings.min_ea_version) and version_tuple(acct.ea_version) < version_tuple(
        settings.min_ea_version)


def authenticate(session: Session, request: Request, settings: Settings, *,
                 allow_pending: bool = False) -> AuthContext:
    token = bearer(request)
    th = hmac_hex(settings.token_pepper, token)
    acct = session.scalar(select(Account).where(Account.token_hash == th))
    via_pending = False
    if acct is None:
        acct = session.scalar(select(Account).where(Account.pending_token_hash == th))
        if acct is None or pending_expired(acct, settings):
            raise ApiError(401, "invalid_token", "unknown or revoked token")
        if not allow_pending:
            raise ApiError(401, "token_not_confirmed", "confirm the rotated token first")
        via_pending = True
    if acct.status == "revoked":
        raise ApiError(401, "revoked", "account revoked; re-enroll")

    # D8.3: the enrollment code is consumed on the first authenticated call with the issued token.
    code = session.scalar(select(EnrollCode).where(
        EnrollCode.account_id == acct.id, EnrollCode.issued_token_hash == th,
        EnrollCode.consumed_at.is_(None)))
    if code is not None:
        code.consumed_at = utcnow()
    acct.last_seen_at = utcnow()

    if (acct.status == "suspended" or version_gated(acct, settings)) and not has_exposure(session, acct):
        raise ApiError(403, "account_blocked",
                       acct.suspended_reason or ("upgrade the EA" if version_gated(acct, settings)
                                                 else "account suspended"))
    return AuthContext(account=acct, token_hash=th, via_pending=via_pending)


def authenticate_admin(session: Session, request: Request, settings: Settings,
                       scope: str = "admin") -> str:
    token = bearer(request)
    if settings.admin_token and hmac.compare_digest(token.encode(), settings.admin_token.encode()):
        return "env:ADMIN_TOKEN"
    row = session.scalar(select(ApiToken).where(
        ApiToken.token_hash == hmac_hex(settings.token_pepper, token), ApiToken.revoked_at.is_(None)))
    if row is None:
        raise ApiError(401, "invalid_token", "invalid admin token")
    if scope not in (row.scopes or []) and "admin" not in (row.scopes or []):
        raise ApiError(403, "forbidden", f"scope {scope!r} required")
    return f"api_token:{row.id}"
