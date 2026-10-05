"""Master close detection, partial reductions, reversal and SL/TP modify (design 5.4-5.6; C1, C4, C5, C7).

Every flow is driven by real master snapshots; timers use the test clock (server monotonic + epoch).
"""

from __future__ import annotations

import time
from decimal import Decimal

from sqlalchemy import func, select

from copycore.models import Command, MasterPosition, ProcessedDeal

from .conftest import admin_headers, bearer
from .copyhelpers import deal, pos
from .test_results import copy_of, done, events, opened, res, setup


def masters(app):
    with app.state.sessionmaker() as s:
        return [(m.position_id, m.generation, m.type, m.state, m.close_source)
                for m in s.scalars(select(MasterPosition).order_by(MasterPosition.id))]


def cmds_sorted(cp, copy_id):
    return sorted(cp.commands(copy_id=copy_id), key=lambda c: c["seq_in_copy"])


def commands_of(cp, copy_id):
    return [(c["action"], c["state"]) for c in cmds_sorted(cp, copy_id)]


def send_history(cp, acct):
    r = cp.c.get("/v4/config", headers=bearer(acct["token"]))
    assert r.status_code == 200, r.text
    return r.json()["send_history"]


def absent_snapshots(cp, clock, master, n, every, keep=(), **kw):
    for _ in range(n):
        clock.advance(every)
        cp.snapshot(master, list(keep), **kw)


# --- fast path (history exit deal) ----------------------------------------------------------------

def test_fast_close_master_closed_transitions_by_copy_state(cp, app):
    """5.5 "master closed": open → closing + close by position_id; pending (open undelivered) →
    cancelled; pending (delivered) → cancel_requested + cancel; uncertain → close intent kept."""
    master, (sl,) = setup(cp)
    opened(cp, master, sl, position_id=1)
    cp.snapshot(master, [pos(1), pos(2), pos(3)])
    a, b = cp.poll(sl)["commands"]  # opens of 2 and 3 delivered
    cp.results(sl, [res(b, "uncertain")])
    cp.snapshot(master, [pos(1), pos(2), pos(3), pos(4)])  # 4: open stays queued (never polled)
    copies = {c["master_position_id"]: c["id"] for c in cp.copies()}
    cp.close_master(master, 1, 2, 3, 4)
    got = {c["id"]: c for c in cp.copies()}
    with app.state.sessionmaker() as s:
        mp_ids = {m.position_id: m.id for m in s.scalars(select(MasterPosition))}
    c1, c2, c3, c4 = (got[copies[mp_ids[p]]] for p in (1, 2, 3, 4))
    assert (c1["state"], c2["state"], c3["state"], c4["state"]) == ("closing", "cancel_requested", "uncertain",
                                                                    "cancelled")
    assert c3["close_intent"] is True
    # (the delivered open of 2 is re-listed until acked, 4.5)
    polled = {(x["action"], x["copy_id"]): x for x in cp.poll(sl)["commands"] if x["action"] != "open"}
    assert set(polled) == {("close", c1["id"]), ("cancel", c2["id"])}
    assert polled[("close", c1["id"])]["position_id"] == 7001
    assert commands_of(cp, c4["id"]) == [("open", "superseded")]
    assert {m[3:] for m in masters(app)} == {("closed", "history")}


def test_s32_same_out_deal_in_three_snapshots_processed_once(cp, app):
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    out = deal(5001, 1, "out")
    for _ in range(3):
        cp.snapshot(master, [], history=[out])
    with app.state.sessionmaker() as s:
        (pd,) = s.scalars(select(ProcessedDeal)).all()
        assert (pd.deal, pd.position_id, pd.generation, pd.effect) == (5001, 1, 0, "close")
    assert commands_of(cp, o["copy_id"]) == [("open", "done"), ("close", "queued")]
    assert len(events(app, "master_position.closed")) == 1


def test_stale_exit_deal_never_closes_a_newer_generation(cp, app):
    """C1: a deal whose time precedes the generation start cannot close it; the absence path decides."""
    master, (sl,) = setup(cp)
    opened(cp, master, sl)
    old = deal(5002, 1, "out")
    old["time_msc"] = int(time.time() * 1000) - 3_600_000
    cp.snapshot(master, [], history=[old])
    assert masters(app)[0][3] == "open"
    with app.state.sessionmaker() as s:
        assert s.scalar(select(ProcessedDeal.effect).where(ProcessedDeal.deal == 5002)) == "none"


def test_s07_close_never_expires_while_slave_offline(cp, app, clock):
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    cp.close_master(master, 1)
    clock.advance(300)
    with app.state.sessionmaker() as s:  # 5 minutes later: still an outstanding obligation
        cmd = s.scalars(select(Command).where(Command.action == "close")).one()
        assert cmd.expires_at is None and cmd.state == "queued"
    (close,) = cp.poll(sl)["commands"]
    cp.results(sl, [res(close, "done", deal=77)])
    assert copy_of(cp, o["copy_id"])["state"] == "closed"


def test_suspended_master_still_closes(cp, app):
    """6.2: a suspended master's snapshots still drive closes of existing copies."""
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    r = cp.c.patch(f"/admin/accounts/{master['id']}", json={"status": "suspended"}, headers=admin_headers())
    assert r.status_code == 200, r.text
    cp.close_master(master, 1, keep=[pos(2)])
    assert copy_of(cp, o["copy_id"])["state"] == "closing"
    assert len(cp.copies()) == 1  # the new position is not fanned out
    assert len(events(app, "master_position.not_fanned_out")) == 1


# --- absence path ---------------------------------------------------------------------------------

def test_absence_needs_k_snapshots_and_t_seconds(cp, app, clock):
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    absent_snapshots(cp, clock, master, 3, every=10)  # K reached, T not
    assert copy_of(cp, o["copy_id"])["state"] == "open"
    clock.advance(40)  # 70 s since the first absence, but no new snapshot yet
    assert copy_of(cp, o["copy_id"])["state"] == "open"
    cp.snapshot(master, [])
    assert copy_of(cp, o["copy_id"])["state"] == "closing"
    assert masters(app)[0][3:] == ("closed", "absence")


def test_absence_t_alone_is_not_enough(cp, app, clock):
    master, (sl,) = setup(cp)
    opened(cp, master, sl)
    cp.snapshot(master, [])
    clock.advance(600)
    cp.snapshot(master, [])  # 2 absent snapshots after 10 minutes: K=3 not reached
    assert masters(app)[0][3] == "open"
    cp.snapshot(master, [])
    assert masters(app)[0][3] == "closed"


def test_s15_disconnected_and_unsynced_snapshots_never_count(cp, app, clock):
    """S15: empty snapshots with connected=false for 120 s close nothing and do not count; neither do
    snapshots with history_synced=false."""
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    absent_snapshots(cp, clock, master, 12, every=10, connected=False)
    absent_snapshots(cp, clock, master, 5, every=30, history_synced=False)
    assert copy_of(cp, o["copy_id"])["state"] == "open"
    with app.state.sessionmaker() as s:
        mp = s.scalars(select(MasterPosition)).one()
        assert (mp.absent_count, mp.absent_since_mono) == (0, None)


def test_reappearance_resets_the_counter(cp, app, clock):
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    absent_snapshots(cp, clock, master, 2, every=40)
    cp.snapshot(master, [pos(1)])  # back
    absent_snapshots(cp, clock, master, 2, every=40)
    assert copy_of(cp, o["copy_id"])["state"] == "open"  # counter restarted at the reappearance
    absent_snapshots(cp, clock, master, 1, every=40)
    assert copy_of(cp, o["copy_id"])["state"] == "closing"


def test_s43_server_restart_restarts_absence_counting(cp, app, clock):
    """S43 / C4: an elapsed time from a previous server epoch is never reused (even when the
    monotonic origin goes back after a reboot); counting resumes after a healthy confirmation."""
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    absent_snapshots(cp, clock, master, 2, every=50)
    clock.restart(start=5.0)  # host reboot: new epoch, monotonic time went back
    cp.snapshot(master, [])  # healthy confirmation in the new epoch
    absent_snapshots(cp, clock, master, 2, every=20)
    assert copy_of(cp, o["copy_id"])["state"] == "open"  # no premature close
    absent_snapshots(cp, clock, master, 1, every=30)  # 3 counted, 70 s in the new epoch
    assert copy_of(cp, o["copy_id"])["state"] == "closing"  # no stuck timer
    assert len(events(app, "master_position.absence_restarted")) == 1


def test_s16_mass_disappearance_holds_and_alerts(cp, app, clock):
    """S16: 5 positions vanish without exit deals → alert, send_history=true, no close before 300 s;
    an exit deal arriving meanwhile closes its position by the fast path."""
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(i) for i in range(1, 6)])
    cp.results(sl, [done(c, 7000 + i) for i, c in enumerate(cp.poll(sl)["commands"], 1)])
    assert send_history(cp, master) is False
    cp.snapshot(master, [])
    (alert,) = events(app, "master.mass_disappearance")
    assert alert["count"] == 5 and sorted(alert["position_ids"]) == [1, 2, 3, 4, 5]
    assert send_history(cp, master) is True
    absent_snapshots(cp, clock, master, 4, every=60)  # 240 s, K reached: still held
    assert {m[3] for m in masters(app)} == {"open"}
    cp.snapshot(master, [], history=[deal(6001, 3, "out")])  # fast path meanwhile
    assert [m[3:] for m in masters(app) if m[0] == 3] == [("closed", "history")]
    absent_snapshots(cp, clock, master, 1, every=61)  # 301 s
    assert {m[3:] for m in masters(app)} == {("closed", "absence"), ("closed", "history")}
    assert len(events(app, "master.mass_disappearance")) == 1  # latched, not re-raised
    assert send_history(cp, master) is False
    assert {c["state"] for c in cp.copies()} == {"closing"}


def test_all_open_positions_vanishing_is_a_mass_episode(cp, app, clock):
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1), pos(2)])
    cp.results(sl, [done(c, 7000 + i) for i, c in enumerate(cp.poll(sl)["commands"], 1)])
    absent_snapshots(cp, clock, master, 3, every=30)  # 2 of 2 vanished (< MASS_DISAPPEAR_MIN=3)
    assert len(events(app, "master.mass_disappearance")) == 1
    assert {m[3] for m in masters(app)} == {"open"}  # 90 s: held for 300 s


def test_closed_position_id_reappearing_is_not_recopied(cp, app, clock):
    master, (sl,) = setup(cp)
    opened(cp, master, sl)
    cp.close_master(master, 1)
    for _ in range(3):
        cp.snapshot(master, [pos(1)])
    assert len(masters(app)) == 1 and len(cp.copies()) == 1
    assert len(events(app, "master_position.reappeared")) == 1


# --- partial reductions (5.4, C7) -------------------------------------------------------------------

def test_s31_s13_hedging_partial_with_out_deal_then_full_close_below_min(cp, app):
    """S31: 1.0 → 0.4 with a real `out` deal and the position present → one close_partial (60 %),
    no close. S13: a further reduction whose target is below the slave minimum → full close."""
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    cp.snapshot(master, [pos(1, volume=0.4)], history=[deal(5101, 1, "out", volume=0.6)])
    (cpart,) = cp.poll(sl)["commands"]
    assert (cpart["action"], cpart["volume"], cpart["residual_volume"], cpart["position_id"]) == (
        "close_partial", 0.6, 0.4, 7001)
    with app.state.sessionmaker() as s:
        assert s.scalar(select(ProcessedDeal.effect).where(ProcessedDeal.deal == 5101)) == "partial"
    cp.snapshot(master, [pos(1, volume=0.4)], history=[deal(5101, 1, "out", volume=0.6)])  # replay
    assert len(cp.commands(copy_id=o["copy_id"])) == 2
    cp.results(sl, [res(cpart, "done", executed_volume=0.6, residual_volume=0.4)])
    got = copy_of(cp, o["copy_id"])
    assert got["state"] == "open" and Decimal(got["confirmed_volume"]) == Decimal("0.4")
    cp.snapshot(master, [pos(1, volume=0.004)])  # target 0.00 < volume_min 0.01
    (close,) = cp.poll(sl)["commands"]
    assert close["action"] == "close" and copy_of(cp, o["copy_id"])["state"] == "closing"


def test_reduction_rounds_target_down_to_step(cp, app):
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    cp.snapshot(master, [pos(1, volume=0.333)])
    (cpart,) = cp.poll(sl)["commands"]
    assert (cpart["volume"], cpart["residual_volume"]) == (0.67, 0.33)
    assert Decimal(copy_of(cp, o["copy_id"])["reduction_target"]) == Decimal("0.33")


def test_s49_reductions_coalesced_and_below_min_accumulated(cp, app):
    """S49: 1.0 → 0.8 → 0.6 before the first ack → one in-flight 0.20, then 0.20 more → 0.60."""
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    cp.snapshot(master, [pos(1, volume=0.8)])
    cp.snapshot(master, [pos(1, volume=0.6)])
    (first,) = cp.poll(sl)["commands"]
    assert first["volume"] == 0.2
    cp.results(sl, [res(first, "done", executed_volume=0.2, residual_volume=0.8)])
    (second,) = cp.poll(sl)["commands"]
    assert (second["action"], second["volume"], second["residual_volume"]) == ("close_partial", 0.2, 0.6)
    cp.results(sl, [res(second, "done", executed_volume=0.2, residual_volume=0.6)])
    assert Decimal(copy_of(cp, o["copy_id"])["confirmed_volume"]) == Decimal("0.6")
    assert cp.poll(sl)["commands"] == []


def test_s49_delta_below_min_waits_for_the_target(cp, app):
    master = cp.account("master", 500)
    sl = cp.account("slave", 600, symbols=())
    cp.symbols(sl["token"], {"EURUSD": {"volume_min": 0.1}})
    cp.link(cp.group(master["id"])["id"], sl["id"])
    o = opened(cp, master, sl)
    cp.snapshot(master, [pos(1, volume=0.95)])  # delta 0.05 < min 0.1: nothing now
    assert cp.poll(sl)["commands"] == []
    assert Decimal(copy_of(cp, o["copy_id"])["reduction_target"]) == Decimal("0.95")
    cp.snapshot(master, [pos(1, volume=0.9)])
    (cpart,) = cp.poll(sl)["commands"]
    assert cpart["volume"] == 0.1


def test_done_partial_on_close_partial_retries_the_rest(cp, app):
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    cp.snapshot(master, [pos(1, volume=0.4)])
    (cpart,) = cp.poll(sl)["commands"]
    cp.results(sl, [res(cpart, "done_partial", executed_volume=0.5, residual_volume=0.5)])
    (rest,) = cp.poll(sl)["commands"]
    assert rest["command_id"] == cpart["command_id"] and rest["attempt_id"] != cpart["attempt_id"]
    assert rest["volume"] == 0.1
    cp.results(sl, [res(rest, "done", executed_volume=0.1, residual_volume=0.4)])
    assert Decimal(copy_of(cp, o["copy_id"])["confirmed_volume"]) == Decimal("0.4")
    assert cp.poll(sl)["commands"] == []


def test_s50_reduction_during_inflight_open_uses_confirmed_volume(cp, app):
    """S50: a reduction while the open is in flight sets the target; the first delta is computed from
    the confirmed (partially filled) volume once the open is confirmed."""
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    (op,) = cp.poll(sl)["commands"]
    cp.snapshot(master, [pos(1, volume=0.5)])
    assert {c["action"] for c in cp.commands(copy_id=op["copy_id"])} == {"open"}
    cp.results(sl, [done(op, volume=0.8)])  # partial fill 0.8 of 1.0
    (cpart,) = cp.poll(sl)["commands"]
    assert (cpart["action"], cpart["volume"], cpart["residual_volume"]) == ("close_partial", 0.3, 0.5)


def test_s50_netting_increase_is_drift_only(cp, app):
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    o = opened(cp, master, sl)
    cp.snapshot(master, [pos(1, volume=1.5)])
    assert cp.poll(sl)["commands"] == []
    (drift,) = events(app, "copy.volume_drift")
    assert drift["copy_id"] == o["copy_id"] and drift["master_volume"] == "1.5"
    cp.snapshot(master, [pos(1, volume=1.2)])  # still above the copy's proportional size: no side flip
    assert cp.poll(sl)["commands"] == []


# --- reversal (5.4, C1, C5) ------------------------------------------------------------------------

def test_s12_netting_reversal_close_then_open(cp, app):
    """S12: buy 1.0 → sell 1.0 on the same id: gen 0 closed (reversal), its copy closed; gen 1 sell
    opened only after the close is confirmed."""
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    o = opened(cp, master, sl)
    cp.snapshot(master, [pos(1, type="sell")], history=[deal(5201, 1, "inout", volume=2.0)])
    assert masters(app) == [(1, 0, "buy", "closed", "reversal"), (1, 1, "sell", "open", None)]
    succ = max(cp.copies(), key=lambda c: c["id"])
    assert (succ["state"], succ["blocked_by"]) == ("pending_blocked", o["copy_id"])
    (close,) = cp.poll(sl)["commands"]
    assert (close["action"], close["copy_id"], close["position_id"]) == ("close", o["copy_id"], 7001)
    cp.results(sl, [res(close, "done", deal=88)])
    assert copy_of(cp, o["copy_id"])["close_reason"] == "master_reversed"
    (op,) = cp.poll(sl)["commands"]
    assert (op["action"], op["copy_id"], op["side"]) == ("open", succ["id"], "sell")
    with app.state.sessionmaker() as s:
        assert s.scalar(select(ProcessedDeal.effect).where(ProcessedDeal.deal == 5201)) == "reversal"


def test_s33_inout_deal_repeated_after_reversal(cp, app):
    """S33: the same `inout` deal in later snapshots (and a late `inout` older than gen 1) never
    reverses generation 1 again."""
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    opened(cp, master, sl)
    inout = deal(5301, 1, "inout", volume=2.0)
    cp.snapshot(master, [pos(1, type="sell")], history=[inout])
    late = deal(5302, 1, "inout", volume=2.0)
    late["time_msc"] = int(time.time() * 1000) - 60_000  # happened before gen 1 started
    for _ in range(3):
        cp.snapshot(master, [pos(1, type="sell")], history=[inout, late])
    assert [m[:2] for m in masters(app)] == [(1, 0), (1, 1)]
    assert len(events(app, "master_position.reversed")) == 1


def test_reversal_on_hedging_slave_is_serialized(cp, app):
    """5.4: on a hedging slave the new side also waits for the close (never both sides at once)."""
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="hedging")
    o = opened(cp, master, sl)
    cp.snapshot(master, [pos(1, type="sell")])
    succ = max(cp.copies(), key=lambda c: c["id"])
    assert (succ["state"], succ["blocked_by"]) == ("pending_blocked", o["copy_id"])
    (close,) = cp.poll(sl)["commands"]
    cp.results(sl, [res(close, "done", deal=9)])
    (op,) = cp.poll(sl)["commands"]
    assert (op["action"], op["side"]) == ("open", "sell")


def test_s45_reversal_before_predecessor_open_delivered_or_while_uncertain(cp, app):
    """S45: predecessor's open never delivered → cancelled, the new side opens at once; predecessor
    uncertain → the successor waits (no promotion without zero-exposure proof)."""
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    cp.snapshot(master, [pos(1)])
    cp.snapshot(master, [pos(1, type="sell")])
    first, second = sorted(cp.copies(), key=lambda c: c["id"])
    assert first["state"] == "cancelled" and second["state"] == "pending"
    (op,) = cp.poll(sl)["commands"]
    assert (op["copy_id"], op["side"]) == (second["id"], "sell")
    cp.results(sl, [res(op, "uncertain")])
    cp.snapshot(master, [pos(1, type="buy")])
    third = max(cp.copies(), key=lambda c: c["id"])
    assert copy_of(cp, second["id"])["state"] == "uncertain"
    assert (third["state"], third["blocked_by"]) == ("pending_blocked", second["id"])
    assert cp.poll(sl)["commands"] == []


def test_s46_three_fast_reversals_one_promotion(cp, app):
    """S46: buy → sell → buy → sell before the first close is confirmed: blocked candidates of closed
    generations are cancelled, exactly one successor is promoted, no UNIQUE violation."""
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    o = opened(cp, master, sl)
    for side in ("sell", "buy", "sell"):
        cp.snapshot(master, [pos(1, type=side)])
    assert [m[1:4] for m in masters(app)] == [(0, "buy", "closed"), (1, "sell", "closed"), (2, "buy", "closed"),
                                               (3, "sell", "open")]
    states = [c["state"] for c in sorted(cp.copies(), key=lambda c: c["id"])]
    assert states == ["closing", "cancelled", "cancelled", "pending_blocked"]
    (close,) = cp.poll(sl)["commands"]
    cp.results(sl, [res(close, "done", deal=1)])
    (op,) = cp.poll(sl)["commands"]
    assert op["side"] == "sell"
    assert len(events(app, "copy.promoted")) == 1
    with app.state.sessionmaker() as s:
        assert s.scalar(select(func.count()).select_from(Command).where(Command.action == "open")) == 2
    assert copy_of(cp, o["copy_id"])["state"] == "closed"


# --- SL/TP modify (5.5, S28) ------------------------------------------------------------------------

def test_s28_modify_supersession_and_pending_open_payload(cp, app):
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    cp.snapshot(master, [pos(1, sl=1.0)])
    cp.snapshot(master, [pos(1, sl=1.05, tp=1.2)])
    (m,) = cp.poll(sl)["commands"]  # only the latest SL/TP is delivered
    assert (m["action"], m["sl"], m["tp"], m["position_id"]) == ("modify", 1.05, 1.2, 7001)
    assert [x["state"] for x in cmds_sorted(cp, o["copy_id"]) if x["action"] == "modify"] == [
        "superseded", "delivered"]
    # modify on a pending copy (open not delivered yet) → the open payload is updated, no command
    cp.snapshot(master, [pos(1, sl=1.05, tp=1.2), pos(2)])
    cp.snapshot(master, [pos(1, sl=1.05, tp=1.2), pos(2, sl=0.9)])
    (op,) = [x for x in cp.poll(sl)["commands"] if x["action"] == "open"]
    assert op["sl"] == 0.9
    assert [x["action"] for x in cp.commands(copy_id=op["copy_id"])] == ["open"]


def test_modify_after_delivered_open_is_queued_after_it(cp, app):
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    (op,) = cp.poll(sl)["commands"]
    cp.snapshot(master, [pos(1, tp=1.3)])
    cmds_ = cmds_sorted(cp, op["copy_id"])
    assert [(c["action"], c["seq_in_copy"]) for c in cmds_] == [("open", 1), ("modify", 2)]


def test_modify_respects_copy_sl_tp_off(cp, app):
    master = cp.account("master", 500)
    sl = cp.account("slave", 600)
    cp.link(cp.group(master["id"])["id"], sl["id"], copy_sl_tp=False)
    o = opened(cp, master, sl)
    cp.snapshot(master, [pos(1, sl=1.0)])
    assert cp.poll(sl)["commands"] == [] and len(cp.commands(copy_id=o["copy_id"])) == 1
