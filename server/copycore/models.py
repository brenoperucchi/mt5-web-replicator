"""Data model: every table of design section 5.1.

Only portable SQL is used. Partial unique indexes carry both ``sqlite_where`` and
``postgresql_where`` so SQLite and Postgres enforce the same invariants.
"""

from __future__ import annotations

from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    MetaData,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


def utcnow() -> datetime:
    return datetime.now(UTC)


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)
    type_annotation_map = {dict[str, Any]: JSON(none_as_null=True), list[Any]: JSON(none_as_null=True)}


def enum(name: str, *values: str) -> Enum:
    """Portable enum: VARCHAR + CHECK constraint (no native PG enum types to migrate)."""
    return Enum(*values, name=name, native_enum=False, create_constraint=True, length=24,
                validate_strings=True)


TS = DateTime(timezone=True)
# Python None is stored as SQL NULL (not the JSON literal null).
JSONN = JSON(none_as_null=True)
VOL = Numeric(20, 8)
PRICE = Numeric(24, 10)

ROLE = ("master", "slave")
MARGIN_MODE = ("hedging", "netting", "unknown")
ACCOUNT_STATUS = ("active", "suspended", "revoked")
COPY_STATES = (
    "pending_blocked", "pending", "open", "cancel_requested", "closing", "uncertain",
    "closed", "cancelled", "skipped", "error", "superseded",
)
# States where exposure on the slave is possible (5.2); `superseded` counts only with close_intent.
EXPOSURE_STATES = ("pending", "open", "cancel_requested", "closing", "uncertain")
COMMAND_STATES = (
    "queued", "delivered", "in_progress", "retry_wait", "done", "failed", "expired", "superseded", "skipped",
)
COMMAND_ACTIONS = ("open", "modify", "close", "close_partial", "cancel", "resolve")


class Account(Base):
    __tablename__ = "accounts"
    __table_args__ = (UniqueConstraint("broker_server_norm", "login", "role"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    broker_server: Mapped[str] = mapped_column(String(128))
    broker_server_norm: Mapped[str] = mapped_column(String(128))
    login: Mapped[int] = mapped_column(BigInteger)
    role: Mapped[str] = mapped_column(enum("account_role", *ROLE))
    margin_mode: Mapped[str] = mapped_column(enum("margin_mode", *MARGIN_MODE), default="unknown")
    label: Mapped[str | None] = mapped_column(String(128))
    status: Mapped[str] = mapped_column(enum("account_status", *ACCOUNT_STATUS), default="active")
    suspended_reason: Mapped[str | None] = mapped_column(String(255))
    ea_version: Mapped[str | None] = mapped_column(String(32))
    last_seen_at: Mapped[datetime | None] = mapped_column(TS)
    session_id: Mapped[str | None] = mapped_column(String(64))
    session_epoch: Mapped[int | None] = mapped_column(Integer)
    session_taken_at: Mapped[datetime | None] = mapped_column(TS)
    last_seq: Mapped[int | None] = mapped_column(BigInteger)
    exclude_copier_positions: Mapped[bool] = mapped_column(Boolean, default=False)
    # Tokens are stored only as HMAC(TOKEN_PEPPER, token) hex digests (D8).
    token_hash: Mapped[str | None] = mapped_column(String(64), index=True)
    pending_token_hash: Mapped[str | None] = mapped_column(String(64), index=True)
    pending_token_id: Mapped[str | None] = mapped_column(String(64))
    pending_token_issued_at: Mapped[datetime | None] = mapped_column(TS)
    token_issued_at: Mapped[datetime | None] = mapped_column(TS)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)


class EnrollCode(Base):
    __tablename__ = "enroll_codes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    account_id: Mapped[int] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"), index=True)
    server_norm: Mapped[str | None] = mapped_column(String(128))
    login: Mapped[int | None] = mapped_column(BigInteger)
    role: Mapped[str | None] = mapped_column(enum("enroll_role", *ROLE))
    code_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[datetime] = mapped_column(TS)
    # `issued_at` = a token was issued with this code (D8 step 2); `consumed_at` = that token
    # made its first authenticated call (D8 step 3), or the code was burned.
    issued_at: Mapped[datetime | None] = mapped_column(TS)
    issued_token_hash: Mapped[str | None] = mapped_column(String(64))
    consumed_at: Mapped[datetime | None] = mapped_column(TS)
    failed_attempts: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)


class SymbolSpec(Base):
    __tablename__ = "symbol_specs"

    account_id: Mapped[int] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True)
    symbol: Mapped[str] = mapped_column(String(64), primary_key=True)
    volume_min: Mapped[Decimal | None] = mapped_column(VOL)
    volume_step: Mapped[Decimal | None] = mapped_column(VOL)
    volume_max: Mapped[Decimal | None] = mapped_column(VOL)
    contract_size: Mapped[Decimal | None] = mapped_column(Numeric(24, 8))
    digits: Mapped[int | None] = mapped_column(Integer)
    point: Mapped[Decimal | None] = mapped_column(PRICE)
    tick_size: Mapped[Decimal | None] = mapped_column(PRICE)
    trade_mode: Mapped[str | None] = mapped_column(String(32))
    filling_modes: Mapped[list[Any] | None] = mapped_column(JSONN)
    stops_level: Mapped[int | None] = mapped_column(Integer)
    freeze_level: Mapped[int | None] = mapped_column(Integer)
    updated_at: Mapped[datetime] = mapped_column(TS, default=utcnow, onupdate=utcnow)


class CopyGroup(Base):
    __tablename__ = "copy_groups"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    master_id: Mapped[int] = mapped_column(ForeignKey("accounts.id"), index=True)
    name: Mapped[str] = mapped_column(String(128))
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    magic_allow: Mapped[list[Any] | None] = mapped_column(JSONN)
    symbol_filter: Mapped[list[Any] | None] = mapped_column(JSONN)


class CopyLink(Base):
    __tablename__ = "copy_links"
    __table_args__ = (UniqueConstraint("group_id", "master_id", "slave_id"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    group_id: Mapped[int] = mapped_column(ForeignKey("copy_groups.id"))
    master_id: Mapped[int] = mapped_column(ForeignKey("accounts.id"), index=True)
    slave_id: Mapped[int] = mapped_column(ForeignKey("accounts.id"), index=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    disabled_reason: Mapped[str | None] = mapped_column(String(255))
    lot_mode: Mapped[str] = mapped_column(enum("lot_mode", "master", "multiplier", "fixed", "min_lot_x"),
                                          default="master")
    lot_value: Mapped[Decimal | None] = mapped_column(VOL)
    below_min: Mapped[str] = mapped_column(enum("below_min", "skip", "open_min"), default="skip")
    allow_contract_size_diff: Mapped[bool] = mapped_column(Boolean, default=False)
    magic_mode: Mapped[str] = mapped_column(enum("magic_mode", "same", "fixed"), default="same")
    magic_value: Mapped[int | None] = mapped_column(BigInteger)
    max_slippage_points: Mapped[int | None] = mapped_column(Integer)
    max_entry_deviation_points: Mapped[int | None] = mapped_column(Integer)
    copy_sl_tp: Mapped[bool] = mapped_column(Boolean, default=True)


class SymbolMap(Base):
    __tablename__ = "symbol_maps"
    __table_args__ = (
        # At most one global map per master symbol, and one per (slave, master symbol) (5.1, 7.1).
        Index("uq_symbol_maps_global_master_symbol", "master_symbol", unique=True,
              sqlite_where=text("slave_id IS NULL"), postgresql_where=text("slave_id IS NULL")),
        Index("uq_symbol_maps_slave_master_symbol", "slave_id", "master_symbol", unique=True,
              sqlite_where=text("slave_id IS NOT NULL"), postgresql_where=text("slave_id IS NOT NULL")),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    slave_id: Mapped[int | None] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    master_symbol: Mapped[str] = mapped_column(String(64))
    slave_symbol: Mapped[str] = mapped_column(String(64))


class MasterPosition(Base):
    __tablename__ = "master_positions"
    __table_args__ = (
        UniqueConstraint("master_id", "position_id", "generation"),
        Index("ix_master_positions_master_state", "master_id", "state"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    master_id: Mapped[int] = mapped_column(ForeignKey("accounts.id"))
    position_id: Mapped[int] = mapped_column(BigInteger)
    generation: Mapped[int] = mapped_column(Integer, default=0)
    position_ticket: Mapped[int | None] = mapped_column(BigInteger)
    symbol: Mapped[str] = mapped_column(String(64))
    type: Mapped[str] = mapped_column(enum("position_side", "buy", "sell"))
    volume: Mapped[Decimal] = mapped_column(VOL)
    opened_volume: Mapped[Decimal | None] = mapped_column(VOL)
    price_open: Mapped[Decimal | None] = mapped_column(PRICE)
    sl: Mapped[Decimal | None] = mapped_column(PRICE)
    tp: Mapped[Decimal | None] = mapped_column(PRICE)
    magic: Mapped[int | None] = mapped_column(BigInteger)
    comment: Mapped[str | None] = mapped_column(String(64))
    state: Mapped[str] = mapped_column(enum("master_position_state", "open", "closed"), default="open")
    absent_count: Mapped[int] = mapped_column(Integer, default=0)
    absent_since_mono: Mapped[float | None] = mapped_column(Numeric(20, 6, asdecimal=False))
    absent_epoch: Mapped[str | None] = mapped_column(String(64))
    mass_episode_id: Mapped[str | None] = mapped_column(String(64))
    close_source: Mapped[str | None] = mapped_column(enum("close_source", "history", "absence", "reversal"))
    opened_at: Mapped[datetime | None] = mapped_column(TS)
    closed_at: Mapped[datetime | None] = mapped_column(TS)


class Copy(Base):
    __tablename__ = "copies"
    __table_args__ = (
        UniqueConstraint("link_id", "master_position_id"),
        # Netting reservation: one exposed copy per (slave, symbol) (5.2).
        Index(
            "uq_copies_netting_slot", "slave_id", "symbol_local", unique=True,
            sqlite_where=text(
                "slave_margin_mode = 'netting' AND (state IN ('pending','open','cancel_requested',"
                "'closing','uncertain') OR (state = 'superseded' AND close_intent))"),
            postgresql_where=text(
                "slave_margin_mode = 'netting' AND (state IN ('pending','open','cancel_requested',"
                "'closing','uncertain') OR (state = 'superseded' AND close_intent))"),
        ),
        # Hedging: one copy per slave position identity (5.2).
        Index(
            "uq_copies_hedging_position", "slave_id", "position_id", unique=True,
            sqlite_where=text("position_id IS NOT NULL AND slave_margin_mode = 'hedging'"),
            postgresql_where=text("position_id IS NOT NULL AND slave_margin_mode = 'hedging'"),
        ),
        Index("ix_copies_slave_state", "slave_id", "state"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    link_id: Mapped[int] = mapped_column(ForeignKey("copy_links.id"))
    master_position_id: Mapped[int] = mapped_column(ForeignKey("master_positions.id"))
    slave_id: Mapped[int] = mapped_column(ForeignKey("accounts.id"))
    slave_margin_mode: Mapped[str] = mapped_column(enum("copy_margin_mode", "hedging", "netting"))
    symbol_master: Mapped[str] = mapped_column(String(64))
    symbol_local: Mapped[str] = mapped_column(String(64))
    volume: Mapped[Decimal | None] = mapped_column(VOL)
    opened_volume: Mapped[Decimal | None] = mapped_column(VOL)
    sl: Mapped[Decimal | None] = mapped_column(PRICE)
    tp: Mapped[Decimal | None] = mapped_column(PRICE)
    # Financial state (exposure on the slave), separate from command status (5.2).
    state: Mapped[str] = mapped_column(enum("copy_state", *COPY_STATES), default="pending")
    blocked_by: Mapped[int | None] = mapped_column(ForeignKey("copies.id"))
    skip_reason: Mapped[str | None] = mapped_column(String(64))
    close_reason: Mapped[str | None] = mapped_column(String(64))
    no_sltp: Mapped[bool] = mapped_column(Boolean, default=False)
    close_intent: Mapped[bool] = mapped_column(Boolean, default=False)
    confirmed_volume: Mapped[Decimal | None] = mapped_column(VOL)
    reduction_target: Mapped[Decimal | None] = mapped_column(VOL)
    exec_params: Mapped[dict[str, Any] | None] = mapped_column(JSONN)
    open_order: Mapped[int | None] = mapped_column(BigInteger)
    open_deal: Mapped[int | None] = mapped_column(BigInteger)
    position_ticket: Mapped[int | None] = mapped_column(BigInteger)
    position_id: Mapped[int | None] = mapped_column(BigInteger)
    close_deal: Mapped[int | None] = mapped_column(BigInteger)
    price_open: Mapped[Decimal | None] = mapped_column(PRICE)
    price_close: Mapped[Decimal | None] = mapped_column(PRICE)
    profit: Mapped[Decimal | None] = mapped_column(Numeric(20, 4))
    fee: Mapped[Decimal | None] = mapped_column(Numeric(20, 4))
    notmodify_count: Mapped[int] = mapped_column(Integer, default=0)
    notmodify_day: Mapped[str | None] = mapped_column(String(10))
    latency_ms: Mapped[int | None] = mapped_column(Integer)
    slippage_points: Mapped[int | None] = mapped_column(Integer)
    opened_at: Mapped[datetime | None] = mapped_column(TS)
    closed_at: Mapped[datetime | None] = mapped_column(TS)
    conciliated_at: Mapped[datetime | None] = mapped_column(TS)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)


class Command(Base):
    __tablename__ = "commands"
    __table_args__ = (
        Index("ix_commands_copy_seq", "copy_id", "seq_in_copy"),
        Index("ix_commands_state_next", "state", "next_attempt_at"),
    )

    id: Mapped[str] = mapped_column(String(40), primary_key=True)  # command_id: the logical obligation
    copy_id: Mapped[int] = mapped_column(ForeignKey("copies.id"))
    seq_in_copy: Mapped[int] = mapped_column(Integer)
    action: Mapped[str] = mapped_column(enum("command_action", *COMMAND_ACTIONS))
    payload: Mapped[dict[str, Any]] = mapped_column(JSONN)
    state: Mapped[str] = mapped_column(enum("command_state", *COMMAND_STATES), default="queued")
    attempt_id: Mapped[str] = mapped_column(String(40))  # current durable attempt
    attempts: Mapped[int] = mapped_column(Integer, default=1)
    next_attempt_at: Mapped[datetime | None] = mapped_column(TS)
    lease_until: Mapped[datetime | None] = mapped_column(TS)
    issued_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
    expires_at: Mapped[datetime | None] = mapped_column(TS)
    acked_at: Mapped[datetime | None] = mapped_column(TS)
    result: Mapped[dict[str, Any] | None] = mapped_column(JSONN)


class CommandAttempt(Base):
    __tablename__ = "command_attempts"

    command_id: Mapped[str] = mapped_column(ForeignKey("commands.id", ondelete="CASCADE"), primary_key=True)
    attempt_id: Mapped[str] = mapped_column(String(40), primary_key=True)
    issued_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
    outcome: Mapped[str | None] = mapped_column(
        enum("attempt_outcome", "done", "done_partial", "rejected", "uncertain"))
    evidence: Mapped[dict[str, Any] | None] = mapped_column(JSONN)


class SessionRow(Base):
    """Server-issued EA sessions; `retired_at` set = retired (fenced) session (C4)."""

    __tablename__ = "sessions"
    __table_args__ = (Index("ix_sessions_account_retired", "account_id", "retired_at"),)

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    account_id: Mapped[int] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    epoch: Mapped[int] = mapped_column(Integer)
    boot_nonce: Mapped[str | None] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
    retired_at: Mapped[datetime | None] = mapped_column(TS)


class ProcessedDeal(Base):
    __tablename__ = "processed_deals"

    account_id: Mapped[int] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True)
    deal: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    position_id: Mapped[int | None] = mapped_column(BigInteger)
    generation: Mapped[int | None] = mapped_column(Integer)
    effect: Mapped[str] = mapped_column(enum("deal_effect", "partial", "reversal", "close", "none"))
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)


class SymbolConflict(Base):
    __tablename__ = "symbol_conflicts"
    __table_args__ = (Index("ix_symbol_conflicts_open", "slave_id", "symbol_local", "resolved_at"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    slave_id: Mapped[int] = mapped_column(ForeignKey("accounts.id"))
    symbol_local: Mapped[str] = mapped_column(String(64))
    kind: Mapped[str] = mapped_column(
        enum("conflict_kind", "unexpected_exposure", "unmanaged_position", "late_adoption"))
    copy_id: Mapped[int | None] = mapped_column(ForeignKey("copies.id"))
    position_id: Mapped[int | None] = mapped_column(BigInteger)
    opened_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
    resolved_at: Mapped[datetime | None] = mapped_column(TS)
    resolution: Mapped[str | None] = mapped_column(String(255))


class IdempotencyKey(Base):
    """Stored responses for Idempotency-Key replays (5.7).

    Token-bearing responses are NEVER stored: those rows have kind='token' and response NULL.
    """

    __tablename__ = "idempotency_keys"
    __table_args__ = (
        CheckConstraint("kind <> 'token' OR response IS NULL", name="token_response_never_stored"),
    )

    account_id: Mapped[int] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True)
    key: Mapped[str] = mapped_column(String(128), primary_key=True)
    route: Mapped[str] = mapped_column(String(128))
    request_sha256: Mapped[str] = mapped_column(String(64))
    kind: Mapped[str] = mapped_column(enum("idempotency_kind", "response", "token"), default="response")
    status_code: Mapped[int | None] = mapped_column(Integer)
    response: Mapped[dict[str, Any] | None] = mapped_column(JSONN)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow, index=True)


class InboundRaw(Base):
    __tablename__ = "inbound_raw"
    __table_args__ = (Index("ix_inbound_raw_account_received", "account_id", "received_at"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    account_id: Mapped[int | None] = mapped_column(ForeignKey("accounts.id", ondelete="SET NULL"))
    kind: Mapped[str] = mapped_column(String(32))
    content: Mapped[bytes] = mapped_column(LargeBinary)  # gzip
    content_sha256: Mapped[str] = mapped_column(String(64))
    received_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
    reason: Mapped[str] = mapped_column(enum("raw_reason", "change", "heartbeat", "error"))


class ErrorSignature(Base):
    __tablename__ = "error_signatures"

    account_id: Mapped[int] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True)
    signature: Mapped[str] = mapped_column(String(64), primary_key=True)
    first_raw_id: Mapped[int | None] = mapped_column(ForeignKey("inbound_raw.id", ondelete="SET NULL"))
    count: Mapped[int] = mapped_column(Integer, default=1)
    first_seen: Mapped[datetime] = mapped_column(TS, default=utcnow)
    last_seen: Mapped[datetime] = mapped_column(TS, default=utcnow)
    samples: Mapped[list[Any] | None] = mapped_column(JSONN)  # <= 5 raw ids per day


class Event(Base):
    """Webhook/event outbox, written in the same transaction as the state change."""

    __tablename__ = "events"
    __table_args__ = (Index("ix_events_undelivered", "delivered_at", "id"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    type: Mapped[str] = mapped_column(String(64))
    payload: Mapped[dict[str, Any]] = mapped_column(JSONN)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
    delivered_at: Mapped[datetime | None] = mapped_column(TS)
    attempts: Mapped[int] = mapped_column(Integer, default=0)


class ApiToken(Base):
    """Admin/service bearer tokens (6.3); stored as HMAC only."""

    __tablename__ = "api_tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(128))
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    scopes: Mapped[list[Any]] = mapped_column(JSONN)
    created_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
    revoked_at: Mapped[datetime | None] = mapped_column(TS)


class EaLog(Base):
    """`POST /v4/logs` uploads (4.3, 5.9: 7 d retention, daily quota). Not listed in 5.1."""

    __tablename__ = "ea_logs"
    __table_args__ = (Index("ix_ea_logs_account_received", "account_id", "received_at"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    account_id: Mapped[int] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    content: Mapped[str] = mapped_column(Text)
    size_bytes: Mapped[int] = mapped_column(Integer)
    received_at: Mapped[datetime] = mapped_column(TS, default=utcnow)
