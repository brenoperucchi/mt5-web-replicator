"""Master snapshot, sessions and fan-out (design 4.3, 5.2-5.7)."""

from __future__ import annotations

import uuid

from sqlalchemy import func, select

from copycore.models import Command, Copy, ErrorSignature, Event, InboundRaw, MasterPosition

from .conftest import admin_headers, bearer
from .copyhelpers import pos


def count(app, model, *where):
    with app.state.sessionmaker() as s:
        return s.scalar(select(func.count()).select_from(model).where(*where))


def events(app, type_):
    with app.state.sessionmaker() as s:
        return [e.payload for e in s.scalars(select(Event).where(Event.type == type_).order_by(Event.id))]


def setup_pair(cp, n_slaves=1, master_margin="hedging", slave_margin="hedging", **link_kw):
    master = cp.account("master", 500, master_margin)
    group = cp.group(master["id"])
    slaves = []
    for i in range(n_slaves):
        sl = cp.account("slave", 600 + i, slave_margin)
        cp.link(group["id"], sl["id"], **link_kw)
        slaves.append(sl)
    return master, group, slaves


# --- fan-out --------------------------------------------------------------------------------------

def test_new_position_one_open_command_per_enabled_link(cp, app):
    master, group, slaves = setup_pair(cp, n_slaves=2, max_entry_deviation_points=150, max_slippage_points=30)
    off = cp.account("slave", 700)
    cp.link(group["id"], off["id"], enabled=False)
    r = cp.snapshot(master, [pos(9001, volume=0.2, price=1.2345, magic=7)])
    assert r.json()["accepted"] is True and r.json()["seq"] == 1
    assert count(app, MasterPosition) == 1
    with app.state.sessionmaker() as s:
        mp = s.scalars(select(MasterPosition)).one()
        assert (mp.position_id, mp.generation, mp.state) == (9001, 0, "open")
    for sl in slaves:
        cmds = cp.poll(sl)["commands"]
        assert len(cmds) == 1
        c = cmds[0]
        assert c["action"] == "open" and c["side"] == "buy" and c["symbol"] == "EURUSD"
        assert c["volume"] == 0.2 and c["master_price"] == 1.2345 and c["magic"] == 7
        assert c["max_entry_deviation_points"] == 150 and c["max_slippage_points"] == 30
        assert c["comment"] == f"c{c['copy_id']}-9001" and c["seq_in_copy"] == 1 and c["position_id"] is None
        assert c["expires_at"] - c["issued_at"] == 30_000  # OPEN_TTL_SECONDS
        assert c["attempt_id"].startswith("a_") and c["command_id"].startswith("c_")
    assert cp.poll(off)["commands"] == []
    copies = cp.copies()
    assert len(copies) == 2 and {c["state"] for c in copies} == {"pending"}
    assert copies[0]["exec_params"]["comment"] == f"c{copies[0]['id']}-9001"
    assert len(events(app, "copy.pending")) == 2 and len(events(app, "master_position.opened")) == 1


def test_idempotent_replay_does_not_duplicate(cp, app):
    """5.7: same Idempotency-Key → stored response; same seq new key → accepted:false; no duplicates."""
    master, _, _ = setup_pair(cp, n_slaves=2)
    body = cp.snapshot_body(master, [pos(1)])
    k = str(uuid.uuid4())
    first = cp.post_snapshot(master, body, idem=k)
    again = cp.post_snapshot(master, body, idem=k)
    assert first.status_code == again.status_code == 200
    assert again.headers.get("Idempotent-Replay") == "true" and again.json()["accepted"] is True
    stale = cp.post_snapshot(master, body)  # same seq, new key
    assert stale.status_code == 200 and stale.json() == {"accepted": False, "seq": 1,
                                                         "server_time": stale.json()["server_time"]}
    cp.snapshot(master, [pos(1)])  # next seq, same position: known, nothing new
    assert count(app, MasterPosition) == 1 and count(app, Copy) == 2 and count(app, Command) == 2
    other = dict(body, seq=99)
    assert cp.post_snapshot(master, other, idem=k).status_code == 409  # key reuse, different body


def test_account_mismatch_409_nothing_stored(cp, app):
    """S17: login/server ≠ token account → 409 account_mismatch, no state change; errors deduplicated."""
    master, _, _ = setup_pair(cp)
    for kw in ({"login": 999}, {"server": "Other-Server"}, {"login": 999}):
        r = cp.snapshot(master, [pos(1)], expect=409, **kw)
        assert r.json()["error"] == "account_mismatch"
    assert count(app, MasterPosition) == 0 and count(app, Copy) == 0
    assert len(events(app, "account.mismatch")) == 3
    with app.state.sessionmaker() as s:
        sigs = s.scalars(select(ErrorSignature).order_by(ErrorSignature.first_seen)).all()
        assert sorted(sg.count for sg in sigs) == [1, 2]  # two causes; the repeated one counted
    # server name is compared normalized
    assert cp.snapshot(master, [pos(1)], server="  broker-live ").json()["accepted"] is True


def test_role_is_enforced(cp):
    _, _, (slave,) = setup_pair(cp)
    r = cp.c.post("/v4/master/snapshot", json=cp.snapshot_body(slave), headers={**bearer(slave["token"]),
                                                                                  "Idempotency-Key": "k1"})
    assert r.status_code == 403 and r.json()["error"] == "wrong_role"


# --- sessions (C4, S09, S44) ----------------------------------------------------------------------

def test_session_required_and_invented_ids_rejected(cp, app):
    master, _, _ = setup_pair(cp)
    fake = {"session_id": "s_" + uuid.uuid4().hex, "epoch": 1}
    r = cp.snapshot(master, [pos(1)], expect=409, session=fake)  # no session ever issued
    assert r.json()["error"] == "stale_session"
    cp.session(master["token"])
    r = cp.snapshot(master, [pos(1)], expect=409, session=fake)  # invented id never authorizes
    assert r.json()["error"] == "stale_session"
    assert count(app, MasterPosition) == 0


def test_s09_new_session_accepted_old_session_fenced(cp, app):
    master, _, (slave,) = setup_pair(cp)
    old = cp.session(master["token"])
    for _ in range(5):
        cp.snapshot(master, [pos(1)])
    assert cp.snapshot(master, [pos(1)], seq=3).json()["accepted"] is False  # stale seq: no change
    new = cp.session(master["token"])  # EA restart (OnInit)
    assert new["session_id"] != old["session_id"] and new["epoch"] == old["epoch"] + 1
    r = cp.snapshot(master, [pos(1), pos(2)], seq=1)  # seq restarts at 1 in the new session
    assert r.json()["accepted"] is True
    late = cp.snapshot(master, [pos(3)], seq=50, session=old, expect=409)  # late request of retired session
    assert late.json()["error"] == "stale_session"
    assert count(app, MasterPosition) == 2
    assert len(cp.poll(slave)["commands"]) == 2


def test_session_replay_returns_same_session(cp):
    master, _, _ = setup_pair(cp)
    body = {"boot_nonce": "n1", "taken_at": 1, "ea_clock_offset_ms": 0}
    h = {**bearer(master["token"]), "Idempotency-Key": "same-key"}
    a, b = (cp.c.post("/v4/session", json=body, headers=h) for _ in range(2))
    assert a.status_code == b.status_code == 201
    assert (a.json()["session_id"], a.json()["epoch"]) == (b.json()["session_id"], b.json()["epoch"])


# --- symbol mapping (7.1, D9) ---------------------------------------------------------------------

def test_symbol_mapping_specific_over_global(cp):
    master = cp.account("master", 500, symbols=("XAUUSD",))
    group = cp.group(master["id"])
    s1 = cp.account("slave", 601, symbols=("GOLD.s1",))
    s2 = cp.account("slave", 602, symbols=("GOLD",))
    s3 = cp.account("slave", 603, symbols=("EURUSD",))
    for sl in (s1, s2, s3):
        cp.link(group["id"], sl["id"])
    cp.smap("XAUUSD", "GOLD")  # global
    cp.smap("XAUUSD", "GOLD.s1", slave_id=s1["id"])  # specific wins for s1
    cp.smap("EURUSD", "EURUSD.x")  # global for a symbol s3 trades as identity
    cp.smap("EURUSD", "EURUSD", slave_id=s3["id"])  # ...overridden back to identity for s3
    cp.snapshot(master, [pos(1, symbol="XAUUSD"), pos(2, symbol="EURUSD")])
    assert [c["symbol"] for c in cp.poll(s1)["commands"]] == ["GOLD.s1"]
    assert [c["symbol"] for c in cp.poll(s2)["commands"]] == ["GOLD"]
    assert [c["symbol"] for c in cp.poll(s3)["commands"]] == ["EURUSD"]


def test_s22_duplicate_map_409(cp):
    sl = cp.account("slave", 601)
    cp.smap("XAUUSD", "GOLD")
    assert cp.smap("XAUUSD", "GOLD2", expect=409)["error"] == "map_conflict"
    cp.smap("XAUUSD", "GOLD3", slave_id=sl["id"])
    assert cp.smap("XAUUSD", "GOLD4", slave_id=sl["id"], expect=409)["error"] == "map_conflict"


# --- lots end to end (S18, S19) -------------------------------------------------------------------

def test_s18_below_min_skipped_by_default_and_open_min_opt_in(cp, app):
    master = cp.account("master", 500)
    group = cp.group(master["id"])
    skip = cp.account("slave", 601)
    opt = cp.account("slave", 602)
    cp.link(group["id"], skip["id"], lot_mode="multiplier", lot_value=0.1)
    cp.link(group["id"], opt["id"], lot_mode="multiplier", lot_value=0.1, below_min="open_min")
    cp.snapshot(master, [pos(1, volume=0.05)])
    assert cp.poll(skip)["commands"] == []
    (c,) = cp.copies(slave_id=skip["id"])
    assert (c["state"], c["skip_reason"]) == ("skipped", "below_min")
    assert len(events(app, "copy.skipped_below_min")) == 1
    assert [x["volume"] for x in cp.poll(opt)["commands"]] == [0.01]


def test_s19_contract_size_map_rejected_without_opt_in_then_factor(cp):
    master = cp.account("master", 500, symbols=())
    cp.symbols(master["token"], {"XAUUSD": {"contract_size": 100}})
    group = cp.group(master["id"])
    sl = cp.account("slave", 601, symbols=())
    cp.symbols(sl["token"], {"GOLD": {"contract_size": 10}})
    lk = cp.link(group["id"], sl["id"])
    r = cp.c.post("/admin/symbol_maps", json={"slave_id": sl["id"], "master_symbol": "XAUUSD",
                                              "slave_symbol": "GOLD"}, headers=admin_headers())
    assert r.status_code == 422 and r.json()["error"] == "config_conflict"
    r = cp.c.patch(f"/admin/links/{lk['id']}", json={"allow_contract_size_diff": True}, headers=admin_headers())
    assert r.status_code == 200
    cp.smap("XAUUSD", "GOLD", slave_id=sl["id"])
    cp.snapshot(master, [pos(1, symbol="XAUUSD", volume=0.05)])
    assert [c["volume"] for c in cp.poll(sl)["commands"]] == [0.5]


def test_missing_slave_spec_skipped_and_wanted(cp):
    master, _, (sl,) = setup_pair(cp)
    cp.snapshot(master, [pos(1, symbol="USDJPY")])
    (c,) = cp.copies()
    assert c["skip_reason"] == "missing_symbol_spec"
    assert cp.c.get("/v4/config", headers=bearer(sl["token"])).json()["symbols_wanted"] == ["USDJPY"]


# --- filters, drain, pending[] --------------------------------------------------------------------

def test_magic_and_symbol_filters(cp):
    master = cp.account("master", 500, symbols=("EURUSD", "GBPUSD"))
    sl = cp.account("slave", 601, symbols=("EURUSD", "GBPUSD"))
    cp.link(cp.group(master["id"], magic_allow=[42], symbol_filter=["EURUSD"])["id"], sl["id"])
    cp.snapshot(master, [pos(1, magic=42), pos(2, magic=1), pos(3, symbol="GBPUSD", magic=42)])
    assert len(cp.poll(sl)["commands"]) == 1
    reasons = sorted(c["skip_reason"] or "" for c in cp.copies())
    assert reasons == ["", "filtered_magic", "filtered_symbol"]


def test_suspended_slave_is_skipped_with_account_drain(cp):
    master, _, (sl,) = setup_pair(cp)
    cp.c.patch(f"/admin/accounts/{sl['id']}", json={"status": "suspended"}, headers=admin_headers())
    cp.snapshot(master, [pos(1)])
    (c,) = cp.copies()
    assert (c["state"], c["skip_reason"]) == ("skipped", "account_drain")


def test_s30_pending_orders_ignored_for_fan_out(cp, app):
    master, _, (sl,) = setup_pair(cp)
    pending = [{"order": 77, "symbol": "EURUSD", "type": "buy_limit", "volume": 1.0, "price": 1.0}]
    cp.snapshot(master, [], pending=pending)
    assert count(app, MasterPosition) == 0 and cp.poll(sl)["commands"] == []
    cp.snapshot(master, [pos(77, price=1.0)])  # the order filled: a new position, copied at market
    (c,) = cp.poll(sl)["commands"]
    assert c["master_price"] == 1.0


def test_disconnected_snapshot_does_not_fan_out(cp, app):
    master, _, (sl,) = setup_pair(cp)
    assert cp.snapshot(master, [pos(1)], connected=False).json()["accepted"] is True
    assert count(app, MasterPosition) == 0
    cp.snapshot(master, [pos(1)])
    assert len(cp.poll(sl)["commands"]) == 1


# --- netting admission (5.3) ----------------------------------------------------------------------

def test_netting_second_copy_same_symbol_skipped_no_rollback(cp, app):
    master = cp.account("master", 500, "netting", symbols=("EURUSD", "GBPUSD"))
    sl = cp.account("slave", 601, "netting", symbols=("EURUSD", "GBPUSD"))
    cp.link(cp.group(master["id"])["id"], sl["id"])
    cp.snapshot(master, [pos(1)])
    # a second master position on the same slave symbol (e.g. after a race) plus an unrelated one
    r = cp.snapshot(master, [pos(1), pos(2), pos(3, symbol="GBPUSD")])
    assert r.status_code == 200 and r.json()["accepted"] is True
    states = {(c["symbol_local"], c["state"], c["skip_reason"]) for c in cp.copies()}
    assert states == {("EURUSD", "pending", None), ("EURUSD", "skipped", "netting_conflict"),
                      ("GBPUSD", "pending", None)}
    assert len(events(app, "copy.skipped_netting_conflict")) == 1
    assert len(cp.poll(sl)["commands"]) == 2


def test_netting_close_then_reopen_is_pending_blocked(cp, app):
    """S11 (admission half): predecessor of the same link leaving the slot → pending_blocked, no open."""
    master = cp.account("master", 500, "netting")
    sl = cp.account("slave", 601, "netting")
    cp.link(cp.group(master["id"])["id"], sl["id"])
    cp.snapshot(master, [pos(1)])
    (o,) = cp.poll(sl)["commands"]
    cp.results(sl, [{"command_id": o["command_id"], "attempt_id": o["attempt_id"], "copy_id": o["copy_id"],
                     "status": "done", "position_id": 7001, "volume": 1.0}])
    cp.close_master(master, 1)
    first_id = o["copy_id"]
    assert next(c for c in cp.copies() if c["id"] == first_id)["state"] == "closing"
    cp.snapshot(master, [pos(2)])
    blocked = [c for c in cp.copies() if c["id"] != first_id]
    assert [(c["state"], c["blocked_by"]) for c in blocked] == [("pending_blocked", first_id)]
    assert count(app, Command, Command.action == "open") == 1  # no open for the blocked copy


def test_exclude_copier_positions(cp, app):
    """5.3: an account that is both slave and master ignores positions the copier opened on it."""
    a = cp.account("master", 500)
    b_slave = cp.account("slave", 777)
    cp.link(cp.group(a["id"])["id"], b_slave["id"], magic_mode="fixed", magic_value=4242)
    cp.snapshot(a, [pos(1)])
    copy_id = cp.copies()[0]["id"]
    b_master = cp.account("master", 777)  # same terminal (server + login) as b_slave
    cp.c.patch(f"/admin/accounts/{b_master['id']}", json={"exclude_copier_positions": True},
               headers=admin_headers())
    c_slave = cp.account("slave", 888)
    cp.link(cp.group(b_master["id"])["id"], c_slave["id"])
    cp.snapshot(b_master, [pos(55, magic=4242, comment=f"c{copy_id}-1"),  # the copier's own position
                           pos(54, magic=4242, comment=f"c{copy_id}-"),  # same, suffix truncated by the broker
                           pos(56, magic=4242, comment="c999999-1"),  # unknown copy id: a real trade
                           pos(57, magic=1, comment=f"c{copy_id}-1"),  # wrong magic: a real trade
                           pos(58, magic=4242, comment=f"c{copy_id}")])  # bare id for a long-form copy: ambiguous
    assert sorted(c["comment"] for c in cp.poll(c_slave)["commands"]) == [
        f"c{x['id']}-{pid}" for x, pid in zip(sorted(cp.copies(slave_id=c_slave["id"]), key=lambda x: x["id"]),
                                              (56, 57, 58), strict=True)]
    with app.state.sessionmaker() as s:
        ids = set(s.scalars(select(MasterPosition.position_id).where(MasterPosition.master_id == b_master["id"])))
    assert ids == {56, 57, 58}


# --- raw storage (5.9) ----------------------------------------------------------------------------

def test_raw_stored_on_change_only(cp, app):
    master, _, _ = setup_pair(cp)
    cp.snapshot(master, [pos(1)])
    cp.snapshot(master, [pos(1)])
    cp.snapshot(master, [pos(1)])
    assert count(app, InboundRaw, InboundRaw.kind == "master_snapshot") == 1
    cp.snapshot(master, [pos(1), pos(2)])
    assert count(app, InboundRaw, InboundRaw.kind == "master_snapshot") == 2
