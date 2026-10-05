"""The Alembic migration builds exactly the models' schema (SQLite, and Postgres when configured)."""

from __future__ import annotations

from pathlib import Path

from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from sqlalchemy import inspect, text

from copycore.db import make_engine
from copycore.models import Base

from .conftest import PG_URL

SERVER = Path(__file__).resolve().parents[1]


def _alembic_cfg(url: str) -> Config:
    cfg = Config(str(SERVER / "alembic.ini"))
    cfg.set_main_option("sqlalchemy.url", url)
    cfg.attributes["configure_logger"] = False
    return cfg


def _reset(engine):
    Base.metadata.drop_all(engine)
    with engine.begin() as conn:
        conn.execute(text("DROP TABLE IF EXISTS alembic_version"))


def test_upgrade_head_matches_models(tmp_path):
    url = PG_URL or f"sqlite:///{tmp_path / 'mig.db'}"
    engine = make_engine(url)
    _reset(engine)
    try:
        command.upgrade(_alembic_cfg(url), "head")
        tables = set(inspect(engine).get_table_names())
        assert set(Base.metadata.tables) <= tables
        with engine.connect() as conn:
            ctx = MigrationContext.configure(conn, opts={"compare_type": True})
            diff = compare_metadata(ctx, Base.metadata)
        assert diff == [], diff
        command.downgrade(_alembic_cfg(url), "base")
        assert set(inspect(engine).get_table_names()) <= {"alembic_version"}
    finally:
        _reset(engine)
        engine.dispose()
