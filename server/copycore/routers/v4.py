"""v4 EA endpoints implemented in Phase 1 / PR 1: enroll, token rotation, config (4.3, D8)."""

from __future__ import annotations

import uuid
from typing import Literal

from fastapi import APIRouter, Request
from fastapi.responses import Response
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import idempotency as idem
from ..auth import authenticate, aware, pending_expired, version_gated
from ..deps import settings_of, uow
from ..engine.validation import revalidate_account_links
from ..errors import ApiError, json_response
from ..models import Account, Copy, EnrollCode, SymbolSpec, utcnow
from ..security import hmac_hex, new_token, normalize_code, normalize_server

router = APIRouter(prefix="/v4")


class EnrollIn(BaseModel):
    code: str = Field(min_length=4, max_length=32)
    broker_server: str = Field(min_length=1, max_length=128)
    login: int = Field(gt=0)
    role: Literal["master", "slave"]
    margin_mode: Literal["hedging", "netting"]
    ea_version: str = Field(min_length=1, max_length=32)


class ConfirmIn(BaseModel):
    pending_id: str = Field(min_length=1, max_length=64)


@router.post("/enroll", status_code=201)
async def enroll(body: EnrollIn, request: Request):
    settings = settings_of(request)
    key = idem.request_key(request)
    raw = await request.body()
    req_hash = idem.request_hash("POST", "/v4/enroll", raw)

    def work(s: Session):
        now = utcnow()
        code = s.scalar(select(EnrollCode).where(
            EnrollCode.code_hash == hmac_hex(settings.token_pepper, normalize_code(body.code))))
        if code is None:
            raise ApiError(401, "invalid_code", "unknown enrollment code")
        if code.consumed_at is not None:
            raise ApiError(401, "code_consumed", "enrollment code already used")
        if aware(code.expires_at) < now:
            raise ApiError(401, "code_expired", "enrollment code expired")
        identity = (normalize_server(body.broker_server), body.login, body.role)
        if identity != (code.server_norm, code.login, code.role):
            code.failed_attempts += 1
            if code.failed_attempts >= settings.enroll_code_max_failures:
                code.consumed_at = now  # burned (D8.3)
            # Committed on purpose: failed attempts must count even though we answer 401.
            return ApiError(401, "identity_mismatch", "code not valid for this account").response()

        acct = s.get(Account, code.account_id)
        replay = idem.lookup(s, account_id=acct.id, key=key, route="/v4/enroll", req_hash=req_hash,
                             ttl_hours=settings.idempotency_ttl_hours)
        if replay is not None:  # cannot happen for token rows; defensive
            return replay

        # Fresh token; any previous unconfirmed token from this code is invalidated by overwrite.
        token = new_token()
        th = hmac_hex(settings.token_pepper, token)
        acct.token_hash = th
        acct.token_issued_at = now
        acct.pending_token_hash = acct.pending_token_id = acct.pending_token_issued_at = None
        acct.broker_server = body.broker_server
        acct.margin_mode = body.margin_mode
        acct.ea_version = body.ea_version
        if acct.status == "revoked":
            acct.status = "active"  # the admin issued a new code after revocation
        code.issued_at = now
        s.flush()
        revalidate_account_links(s, acct)  # margin_mode now known (5.3, S10)
        code.issued_token_hash = th
        idem.record(s, account_id=acct.id, key=key, route="/v4/enroll", req_hash=req_hash,
                    status_code=201, response=None, token_bearing=True)
        return json_response({"token": token, "account_id": acct.id}, 201)

    return uow(request, work)


@router.post("/token/rotate")
async def rotate(request: Request, restart: bool = False):
    settings = settings_of(request)
    key = idem.request_key(request)
    route = "/v4/token/rotate" + ("?restart=true" if restart else "")
    req_hash = idem.request_hash("POST", route, await request.body())

    def work(s: Session):
        acct = authenticate(s, request, settings).account
        idem.lookup(s, account_id=acct.id, key=key, route=route, req_hash=req_hash,
                    ttl_hours=settings.idempotency_ttl_hours)
        if acct.pending_token_hash and not pending_expired(acct, settings) and not restart:
            raise ApiError(409, "rotation_pending",
                           "a rotation is pending: confirm it with the new token or rotate?restart=true")
        new = new_token()
        acct.pending_token_hash = hmac_hex(settings.token_pepper, new)
        acct.pending_token_id = "rot_" + uuid.uuid4().hex
        acct.pending_token_issued_at = utcnow()
        idem.record(s, account_id=acct.id, key=key, route=route, req_hash=req_hash,
                    status_code=200, response=None, token_bearing=True)
        return json_response({"new_token": new, "pending_id": acct.pending_token_id}, 200)

    return uow(request, work)


@router.post("/token/confirm", status_code=204)
async def confirm(body: ConfirmIn, request: Request):
    settings = settings_of(request)
    key = idem.request_key(request)
    req_hash = idem.request_hash("POST", "/v4/token/confirm", await request.body())

    def work(s: Session):
        ctx = authenticate(s, request, settings, allow_pending=True)
        acct = ctx.account
        replay = idem.lookup(s, account_id=acct.id, key=key, route="/v4/token/confirm", req_hash=req_hash,
                             ttl_hours=settings.idempotency_ttl_hours)
        if replay is not None:
            return replay
        if not ctx.via_pending:
            raise ApiError(409, "confirm_requires_new_token", "call confirm with the new (pending) token")
        if body.pending_id != acct.pending_token_id:
            raise ApiError(409, "pending_mismatch", "pending_id does not match the pending rotation")
        acct.token_hash = acct.pending_token_hash  # revokes the old token
        acct.token_issued_at = utcnow()
        acct.pending_token_hash = acct.pending_token_id = acct.pending_token_issued_at = None
        idem.record(s, account_id=acct.id, key=key, route="/v4/token/confirm", req_hash=req_hash,
                    status_code=204, response=None, token_bearing=False)
        return Response(status_code=204)

    return uow(request, work)


def symbols_wanted(s: Session, acct: Account) -> list[str]:
    """Slave symbols a copy was skipped for because their spec is missing (5.4)."""
    if acct.role != "slave":
        return []
    rows = s.scalars(select(Copy.symbol_local).where(
        Copy.slave_id == acct.id, Copy.skip_reason == "missing_symbol_spec").distinct())
    return sorted(sym for sym in rows if s.get(SymbolSpec, (acct.id, sym)) is None)


@router.get("/config")
def get_config(request: Request):
    settings = settings_of(request)

    def work(s: Session):
        acct = authenticate(s, request, settings).account
        drain = acct.status == "suspended" or version_gated(acct, settings)
        if acct.status == "suspended":
            message = acct.suspended_reason or "account suspended: no new copies"
        elif drain:
            message = f"upgrade the EA to {settings.min_ea_version} or newer"
        else:
            message = ""
        return json_response({
            "account_id": acct.id,
            "role": acct.role,
            "mode": "drain" if drain else "normal",
            "message": message,
            "poll_ms": settings.poll_ms,
            "debug": False,
            "send_history": False,
            "symbols_wanted": symbols_wanted(s, acct),
            "min_ea_version": settings.min_ea_version,
        })

    return uow(request, work)
