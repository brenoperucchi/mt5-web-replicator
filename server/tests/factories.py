from __future__ import annotations

from decimal import Decimal

from copycore.models import Account, Copy, CopyGroup, CopyLink, MasterPosition

_seq = iter(range(10_000, 10_000_000))


def account(s, role="slave", margin_mode="hedging", **kw) -> Account:
    login = kw.pop("login", next(_seq))
    a = Account(broker_server="Broker-Live", broker_server_norm="broker-live", login=login, role=role,
                margin_mode=margin_mode, **kw)
    s.add(a)
    s.flush()
    return a


def graph(s, slave_margin="hedging"):
    master = account(s, "master")
    slave = account(s, "slave", slave_margin)
    group = CopyGroup(master_id=master.id, name="g1")
    s.add(group)
    s.flush()
    link = CopyLink(group_id=group.id, master_id=master.id, slave_id=slave.id)
    s.add(link)
    s.flush()
    return master, slave, group, link


def master_position(s, master, position_id=None, generation=0, symbol="EURUSD") -> MasterPosition:
    mp = MasterPosition(master_id=master.id, position_id=position_id or next(_seq), generation=generation,
                        symbol=symbol, type="buy", volume=Decimal("1.0"))
    s.add(mp)
    s.flush()
    return mp


def copy(s, link, mp, slave, state="open", symbol="EURUSD", position_id=None, close_intent=False) -> Copy:
    c = Copy(link_id=link.id, master_position_id=mp.id, slave_id=slave.id,
             slave_margin_mode=slave.margin_mode, symbol_master=mp.symbol, symbol_local=symbol,
             state=state, position_id=position_id, close_intent=close_intent)
    s.add(c)
    s.flush()
    return c
