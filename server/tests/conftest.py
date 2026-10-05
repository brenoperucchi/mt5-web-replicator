"""Test fixtures.

By default every test gets a fresh SQLite file. Set COPYCORE_TEST_DATABASE_URL to a
throwaway Postgres database to run the same suite on Postgres (tables are dropped/recreated).
"""

from __future__ import annotations

import os
import uuid

import pytest
from fastapi.testclient import TestClient

from copycore.app import create_app
from copycore.config import load_settings
from copycore.db import make_engine
from copycore.models import Base

PG_URL = os.environ.get("COPYCORE_TEST_DATABASE_URL")
ADMIN = "test-admin-token"


@pytest.fixture
def db_url(tmp_path):
    return PG_URL or f"sqlite:///{tmp_path / 'test.db'}"


@pytest.fixture
def engine(db_url):
    eng = make_engine(db_url)
    Base.metadata.drop_all(eng)
    Base.metadata.create_all(eng)
    yield eng
    Base.metadata.drop_all(eng)  # leave a shared Postgres database empty
    eng.dispose()


@pytest.fixture
def settings(db_url):
    return load_settings(env="test", database_url=db_url, admin_token=ADMIN,
                         token_pepper="test-pepper-0123456789")


@pytest.fixture
def app(settings, engine):
    return create_app(settings, engine=engine)


@pytest.fixture
def client(app):
    with TestClient(app) as c:
        yield c


def ikey() -> dict:
    return {"Idempotency-Key": str(uuid.uuid4())}


def admin_headers() -> dict:
    return {"Authorization": f"Bearer {ADMIN}"}


def bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


class Api:
    """Small helper around the HTTP API used by the tests."""

    def __init__(self, client: TestClient):
        self.c = client

    def create_account(self, server="Broker-Live", login=1001, role="slave", **kw):
        r = self.c.post("/admin/accounts", json={"broker_server": server, "login": login, "role": role, **kw},
                        headers=admin_headers())
        assert r.status_code == 201, r.text
        return r.json()

    def issue_code(self, account_id: int) -> str:
        r = self.c.post(f"/admin/accounts/{account_id}/enroll_codes", headers=admin_headers())
        assert r.status_code == 201, r.text
        return r.json()["code"]

    def enroll(self, code, server="Broker-Live", login=1001, role="slave", margin_mode="hedging",
               key=None, ea_version="1.0.0"):
        body = {"code": code, "broker_server": server, "login": login, "role": role,
                "margin_mode": margin_mode, "ea_version": ea_version}
        return self.c.post("/v4/enroll", json=body, headers={"Idempotency-Key": key or str(uuid.uuid4())})

    def enrolled(self, server="Broker-Live", login=1001, role="slave", margin_mode="hedging"):
        acct = self.create_account(server, login, role)
        r = self.enroll(self.issue_code(acct["id"]), server, login, role, margin_mode)
        assert r.status_code == 201, r.text
        return acct, r.json()["token"]


@pytest.fixture
def api(client):
    return Api(client)


@pytest.fixture
def cp(api, client):
    from .copyhelpers import Copier
    return Copier(api, client)
