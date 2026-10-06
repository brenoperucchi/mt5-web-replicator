"""Env-only configuration (design D7).

Every setting comes from the environment. Secrets (ADMIN_TOKEN, TOKEN_PEPPER) are required
outside development/test; the app refuses to start without them.
"""

from __future__ import annotations

import os
from functools import lru_cache

from pydantic import AliasChoices, Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

DEV_ENVS = frozenset({"dev", "development", "test"})
DEV_TOKEN_PEPPER = "dev-only-token-pepper-not-for-production"  # noqa: S105
DEV_ADMIN_TOKEN = "dev-admin-token"  # noqa: S105

# Floor fixed by the design (5.6 / C1): the absence path never closes faster than 60 s.
CLOSE_ABSENT_SECONDS_FLOOR = 60


class ConfigError(RuntimeError):
    """Configuration that must stop the process at startup."""


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="", case_sensitive=False, extra="ignore")

    env: str = Field(default="production", validation_alias=AliasChoices("ENV", "COPYCORE_ENV"))
    database_url: str = "sqlite:////data/copy.db"

    # Secrets. TOKEN_PEPPER is the HMAC key for token/code hashes; TOKEN_HMAC_KEY is accepted as an alias.
    admin_token: str | None = None
    token_pepper: str | None = Field(
        default=None, validation_alias=AliasChoices("TOKEN_PEPPER", "TOKEN_HMAC_KEY")
    )

    # Close detection (5.6)
    close_absent_snapshots: int = Field(default=3, ge=1)
    close_absent_seconds: int = 60
    mass_disappear_min: int = Field(default=3, ge=1)
    mass_disappear_seconds: int = 300

    open_ttl_seconds: int = Field(default=30, ge=1)
    master_stale_seconds: int = Field(default=120, ge=1)
    # Receipt-ack lease of an `in_progress` command before it is re-delivered (4.5, C2).
    command_lease_seconds: int = Field(default=120, ge=1)

    # Retention and quotas (5.9)
    raw_snapshot_retention_h: int = 48
    event_retention_d: int = 30
    log_retention_d: int = 7
    raw_daily_quota_mb: int = 50
    log_daily_quota_mb: int = 20

    webhook_url: str | None = None
    webhook_secret: str | None = None

    # Auth (D8)
    enroll_code_ttl_seconds: int = 15 * 60
    enroll_code_max_failures: int = 5
    pending_token_ttl_hours: int = 24
    idempotency_ttl_hours: int = 24

    # Config endpoint defaults (4.3)
    poll_ms: int = Field(default=2000, ge=500)   # EA clamps to >= 500 too
    # Opt-in per-call trace file for latency/load tests (account id, route, status, timing; no secrets).
    access_trace_path: str | None = None
    # last_seen_at is written at most this often per account, so idle polls stay read-only (D6).
    last_seen_write_seconds: int = Field(default=30, ge=0)
    min_ea_version: str | None = None

    # Rate limits (6.4) are not enforced yet; the switch exists so later PRs only add logic.
    rate_limit_enabled: bool = False
    body_max_bytes: int = 2 * 1024 * 1024

    web_concurrency: int = 1

    @field_validator("close_absent_seconds")
    @classmethod
    def _absence_floor(cls, v: int) -> int:
        if v < CLOSE_ABSENT_SECONDS_FLOOR:
            raise ValueError(f"CLOSE_ABSENT_SECONDS must be >= {CLOSE_ABSENT_SECONDS_FLOOR} (got {v})")
        return v

    @field_validator("mass_disappear_seconds")
    @classmethod
    def _mass_floor(cls, v: int) -> int:
        if v < CLOSE_ABSENT_SECONDS_FLOOR:
            raise ValueError(f"MASS_DISAPPEAR_SECONDS must be >= {CLOSE_ABSENT_SECONDS_FLOOR} (got {v})")
        return v

    @model_validator(mode="after")
    def _secrets_and_runtime(self) -> Settings:
        if self.is_dev:
            self.token_pepper = self.token_pepper or DEV_TOKEN_PEPPER
            self.admin_token = self.admin_token or DEV_ADMIN_TOKEN
        else:
            missing = [n for n, v in (("TOKEN_PEPPER", self.token_pepper), ("ADMIN_TOKEN", self.admin_token))
                       if not v]
            if missing:
                raise ValueError(f"{', '.join(missing)} required when ENV={self.env!r}")
        if self.is_sqlite and self.web_concurrency > 1:
            raise ValueError("SQLite requires a single uvicorn worker (WEB_CONCURRENCY=1)")
        return self

    @property
    def is_dev(self) -> bool:
        return self.env.lower() in DEV_ENVS

    @property
    def is_sqlite(self) -> bool:
        return self.database_url.startswith("sqlite")


def load_settings(**overrides) -> Settings:
    """Build settings from the environment; raise ConfigError on invalid config."""
    try:
        return Settings(**overrides)
    except ValueError as exc:  # pydantic ValidationError subclasses ValueError
        raise ConfigError(str(exc)) from exc


@lru_cache
def get_settings() -> Settings:
    return load_settings()


def env_database_url() -> str:
    """DATABASE_URL for tooling (Alembic) without requiring secrets."""
    return os.environ.get("DATABASE_URL", Settings.model_fields["database_url"].default)
