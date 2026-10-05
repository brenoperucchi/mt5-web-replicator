"""Config load rules (D7, 5.6)."""

from __future__ import annotations

import pytest

from copycore.app import create_app
from copycore.config import ConfigError, get_settings, load_settings


def test_s34_close_absent_seconds_below_floor_rejected():
    """S34 (C1): CLOSE_ABSENT_SECONDS=30 is rejected at config load."""
    with pytest.raises(ConfigError, match="CLOSE_ABSENT_SECONDS"):
        load_settings(env="test", close_absent_seconds=30)


def test_s34_close_absent_seconds_from_env_rejected(monkeypatch):
    monkeypatch.setenv("ENV", "test")
    monkeypatch.setenv("CLOSE_ABSENT_SECONDS", "59")
    with pytest.raises(ConfigError):
        load_settings()


def test_close_absent_seconds_floor_and_upward_accepted():
    assert load_settings(env="test").close_absent_seconds == 60
    assert load_settings(env="test", close_absent_seconds=90).close_absent_seconds == 90


def test_mass_disappear_seconds_below_floor_rejected():
    with pytest.raises(ConfigError):
        load_settings(env="test", mass_disappear_seconds=30)


def test_production_refuses_to_start_without_token_pepper(monkeypatch):
    for var in ("TOKEN_PEPPER", "TOKEN_HMAC_KEY"):
        monkeypatch.delenv(var, raising=False)
    monkeypatch.setenv("ENV", "production")
    monkeypatch.setenv("ADMIN_TOKEN", "x" * 32)
    get_settings.cache_clear()
    try:
        with pytest.raises(ConfigError, match="TOKEN_PEPPER"):
            create_app()
    finally:
        get_settings.cache_clear()


def test_production_refuses_to_start_without_admin_token(monkeypatch):
    monkeypatch.delenv("ADMIN_TOKEN", raising=False)
    with pytest.raises(ConfigError, match="ADMIN_TOKEN"):
        load_settings(env="production", token_pepper="p" * 32)


def test_env_defaults_to_production(monkeypatch):
    for var in ("ENV", "COPYCORE_ENV", "TOKEN_PEPPER", "TOKEN_HMAC_KEY", "ADMIN_TOKEN"):
        monkeypatch.delenv(var, raising=False)
    with pytest.raises(ConfigError):
        load_settings()


def test_token_hmac_key_alias(monkeypatch):
    monkeypatch.delenv("TOKEN_PEPPER", raising=False)
    monkeypatch.setenv("TOKEN_HMAC_KEY", "k" * 32)
    s = load_settings(env="production", admin_token="a" * 32)
    assert s.token_pepper == "k" * 32


def test_dev_env_gets_dev_secrets():
    s = load_settings(env="development")
    assert s.token_pepper and s.admin_token


def test_sqlite_requires_single_worker():
    with pytest.raises(ConfigError, match="single uvicorn worker"):
        load_settings(env="test", web_concurrency=2)
    load_settings(env="test", database_url="postgresql://x/y", web_concurrency=2)
