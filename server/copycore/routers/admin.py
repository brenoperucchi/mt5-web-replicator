"""Minimal admin API (6.3) for Phase 1 / PR 1: accounts, enrollment codes, revoke, suspend."""

from __future__ import annotations

from datetime import timedelta
from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..auth import authenticate_admin
from ..deps import settings_of, uow
from ..errors import ApiError, json_response
from ..models import EXPOSURE_STATES, Account, Copy, CopyLink, EnrollCode, Event, utcnow
from ..security import hmac_hex, new_enroll_code, normalize_server

router = APIRouter(prefix="/admin")


class AccountIn(BaseModel):
    broker_server: str = Field(min_length=1, max_length=128)
    login: int = Field(gt=0)
    role: Literal["master", "slave"]
    label: str | None = Field(default=None, max_length=128)


class AccountPatch(BaseModel):
    status: Literal["active", "suspended"] | None = None
    suspended_reason: str | None = Field(default=None, max_length=255)
    label: str | None = Field(default=None, max_length=128)


def account_json(a: Account) -> dict:
    return {
        "id": a.id, "broker_server": a.broker_server, "login": a.login, "role": a.role,
        "margin_mode": a.margin_mode, "label": a.label, "status": a.status,
        "suspended_reason": a.suspended_reason, "ea_version": a.ea_version,
        "enrolled": a.token_hash is not None,
        "last_seen_at": a.last_seen_at.isoformat() if a.last_seen_at else None,
    }


def get_account(s: Session, account_id: int) -> Account:
    acct = s.get(Account, account_id)
    if acct is None:
        raise ApiError(404, "not_found", "account not found")
    return acct


@router.post("/accounts", status_code=201)
def create_account(body: AccountIn, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings)
        norm = normalize_server(body.broker_server)
        dup = s.scalar(select(Account).where(Account.broker_server_norm == norm, Account.login == body.login,
                                             Account.role == body.role))
        if dup is not None:
            raise ApiError(409, "account_exists", "account already exists")
        acct = Account(broker_server=body.broker_server, broker_server_norm=norm, login=body.login,
                       role=body.role, label=body.label, margin_mode="unknown", status="active")
        s.add(acct)
        s.flush()
        return json_response(account_json(acct), 201)

    return uow(request, work)


@router.get("/accounts/{account_id}")
def show_account(account_id: int, request: Request):
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings, scope="readonly")
        return json_response(account_json(get_account(s, account_id)))

    return uow(request, work)


@router.post("/accounts/{account_id}/enroll_codes", status_code=201)
def issue_enroll_code(account_id: int, request: Request):
    """One-time code bound to (server_norm, login, role); 15 min TTL; stored hashed (D8.1)."""
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings)
        acct = get_account(s, account_id)
        code = new_enroll_code()
        expires = utcnow() + timedelta(seconds=settings.enroll_code_ttl_seconds)
        s.add(EnrollCode(account_id=acct.id, server_norm=acct.broker_server_norm, login=acct.login,
                         role=acct.role, code_hash=hmac_hex(settings.token_pepper, code), expires_at=expires))
        return json_response({"code": code, "account_id": acct.id, "expires_at": expires.isoformat()}, 201)

    return uow(request, work)


@router.post("/accounts/{account_id}/revoke")
def revoke(account_id: int, request: Request):
    """Security revocation (6.2): 401 on every call; open copies listed in `account.revoked`."""
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings)
        acct = get_account(s, account_id)
        acct.status = "revoked"
        acct.token_hash = acct.pending_token_hash = acct.pending_token_id = None
        acct.pending_token_issued_at = None
        q = select(Copy.id).where(Copy.state.in_(EXPOSURE_STATES))
        q = q.where(Copy.slave_id == acct.id) if acct.role == "slave" else q.join(
            CopyLink, Copy.link_id == CopyLink.id).where(CopyLink.master_id == acct.id)
        s.add(Event(type="account.revoked", payload={"account_id": acct.id, "open_copies": list(s.scalars(q))}))
        return json_response(account_json(acct))

    return uow(request, work)


@router.patch("/accounts/{account_id}")
def patch_account(account_id: int, body: AccountPatch, request: Request):
    """Commercial suspension = drain (6.2, D11); `status: active` lifts it. Never revokes."""
    settings = settings_of(request)

    def work(s: Session):
        authenticate_admin(s, request, settings)
        acct = get_account(s, account_id)
        if acct.status == "revoked" and body.status is not None:
            raise ApiError(409, "account_revoked", "revoked accounts must re-enroll")
        if body.status is not None and body.status != acct.status:
            acct.status = body.status
            acct.suspended_reason = body.suspended_reason if body.status == "suspended" else None
            s.add(Event(type=f"account.{'suspended' if body.status == 'suspended' else 'reactivated'}",
                        payload={"account_id": acct.id}))
        if body.label is not None:
            acct.label = body.label
        return json_response(account_json(acct))

    return uow(request, work)
