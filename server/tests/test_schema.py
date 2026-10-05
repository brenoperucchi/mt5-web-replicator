"""Schema invariants of 5.1/5.2 enforced by the database (run on SQLite and, when configured, Postgres)."""

from __future__ import annotations

import pytest
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from copycore.models import CopyLink, IdempotencyKey, MasterPosition, SymbolMap

from . import factories as f


@pytest.fixture
def s(engine):
    with Session(engine) as session:
        yield session


def test_s22_duplicate_global_symbol_map_rejected(s):
    """S22: two global maps for the same master symbol violate the partial unique index."""
    s.add(SymbolMap(slave_id=None, master_symbol="XAUUSD", slave_symbol="GOLD"))
    s.commit()
    s.add(SymbolMap(slave_id=None, master_symbol="XAUUSD", slave_symbol="XAU"))
    with pytest.raises(IntegrityError):
        s.commit()


def test_symbol_maps_per_slave_unique_and_coexists_with_global(s):
    slave = f.account(s)
    other = f.account(s)
    s.add_all([
        SymbolMap(slave_id=None, master_symbol="XAUUSD", slave_symbol="GOLD"),
        SymbolMap(slave_id=slave.id, master_symbol="XAUUSD", slave_symbol="GOLD.m"),
        SymbolMap(slave_id=other.id, master_symbol="XAUUSD", slave_symbol="XAUUSD.r"),
    ])
    s.commit()
    s.add(SymbolMap(slave_id=slave.id, master_symbol="XAUUSD", slave_symbol="GOLD.x"))
    with pytest.raises(IntegrityError):
        s.commit()


def test_copy_links_unique_group_master_slave(s):
    master, slave, group, _ = f.graph(s)
    s.commit()
    s.add(CopyLink(group_id=group.id, master_id=master.id, slave_id=slave.id))
    with pytest.raises(IntegrityError):
        s.commit()


def test_two_groups_on_same_pair_allowed(s):
    from copycore.models import CopyGroup
    master, slave, _, _ = f.graph(s)
    g2 = CopyGroup(master_id=master.id, name="g2")
    s.add(g2)
    s.flush()
    s.add(CopyLink(group_id=g2.id, master_id=master.id, slave_id=slave.id))
    s.commit()


def test_master_positions_unique_generation(s):
    master, *_ = f.graph(s)
    f.master_position(s, master, position_id=42, generation=0)
    f.master_position(s, master, position_id=42, generation=1)  # reversal = new generation
    s.commit()
    s.add(MasterPosition(master_id=master.id, position_id=42, generation=1, symbol="EURUSD", type="sell",
                         volume=1))
    with pytest.raises(IntegrityError):
        s.commit()


def test_hedging_copies_unique_slave_position_id(s):
    """5.2 hedging index: one copy per (slave, position_id) on hedging slaves."""
    master, slave, _, link = f.graph(s, "hedging")
    f.copy(s, link, f.master_position(s, master), slave, position_id=777)
    f.copy(s, link, f.master_position(s, master), slave, position_id=None)  # NULLs never collide
    f.copy(s, link, f.master_position(s, master), slave, position_id=None)
    s.commit()
    with pytest.raises(IntegrityError):
        f.copy(s, link, f.master_position(s, master), slave, position_id=777)
        s.commit()


def test_netting_slot_reserved_by_exposed_states_only(s):
    """5.2 netting index: one exposed copy per (slave, symbol); terminal/blocked states free the slot."""
    master, slave, _, link = f.graph(s, "netting")
    for state in ("closed", "cancelled", "skipped", "error", "pending_blocked", "pending_blocked"):
        f.copy(s, link, f.master_position(s, master), slave, state=state)
    f.copy(s, link, f.master_position(s, master), slave, state="superseded", close_intent=False)
    f.copy(s, link, f.master_position(s, master), slave, state="open")
    s.commit()
    for state, intent in (("pending", False), ("closing", False), ("superseded", True)):
        with pytest.raises(IntegrityError):
            f.copy(s, link, f.master_position(s, master), slave, state=state, close_intent=intent)
            s.commit()
        s.rollback()
    f.copy(s, link, f.master_position(s, master), slave, state="open", symbol="GBPUSD")
    s.commit()


def test_copy_unique_per_link_and_master_position(s):
    master, slave, _, link = f.graph(s, "hedging")
    mp = f.master_position(s, master)
    f.copy(s, link, mp, slave, state="closed")
    s.commit()
    with pytest.raises(IntegrityError):
        f.copy(s, link, mp, slave, state="closed")
        s.commit()


def test_idempotency_token_rows_cannot_hold_a_response(s):
    acct = f.account(s)
    s.add(IdempotencyKey(account_id=acct.id, key="k", route="/v4/enroll", request_sha256="0" * 64,
                         kind="token", status_code=201, response={"token": "x"}))
    with pytest.raises(IntegrityError):
        s.commit()


def test_enum_check_constraints(s):
    f.account(s)
    s.commit()
    from sqlalchemy import text
    with pytest.raises(IntegrityError):
        s.execute(text("UPDATE accounts SET status = 'bogus'"))
        s.commit()
