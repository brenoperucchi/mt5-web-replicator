"""Slave snapshot: fencing, reconciliation, adoption, conflicts and netting successor (design 4.3, 5.3, 5.5, 5.8)."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select

from copycore.models import Command, Copy, Event, MasterPosition, SymbolConflict, utcnow

from .copyhelpers import deal, pos
from .test_results import copy_of, done, opened, res, setup


def events(app, type_):
    with app.state.sessionmaker() as s:
        return [e.payload for e in s.scalars(select(Event).where(Event.type == type_).order_by(Event.id))]


def spos(position_id, copy_id, magic=0, symbol="EURUSD", volume=1.0, comment=None):
    return pos(position_id, symbol=symbol, volume=volume, magic=magic,
               comment=comment if comment is not None else f"c{copy_id}")


# --- fencing ---------------------------------------------------------------------------------------

def test_slave_snapshot_fencing_and_mismatch(cp, app):
    """S17 / S44 for the slave: login mismatch → 409 nothing stored; retired session → 409 stale_session;
    seq not newer → accepted:false; connected=false → nothing acted on."""
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    (c,) = cp.poll(sl)["commands"]
    old = cp.session(sl["token"])
    assert cp.slave_snapshot(sl, [spos(7001, c["copy_id"])], connected=False)["accepted"] is True
    assert copy_of(cp, c["copy_id"])["state"] == "pending"  # disconnected view is not evidence
    r = cp.c.post("/v4/slave/snapshot", json=cp.snapshot_body(sl, login=999),
                  headers={"Authorization": f"Bearer {sl['token']}", "Idempotency-Key": "mm-1"})
    assert r.status_code == 409 and r.json()["error"] == "account_mismatch"
    cp.session(sl["token"])
    stale = cp.snapshot_body(sl, [spos(7001, c["copy_id"])], session=old, seq=99)
    r = cp.c.post("/v4/slave/snapshot", json=stale,
                  headers={"Authorization": f"Bearer {sl['token']}", "Idempotency-Key": "st-1"})
    assert r.status_code == 409 and r.json()["error"] == "stale_session"
    assert copy_of(cp, c["copy_id"])["state"] == "pending"
    cp.slave_snapshot(sl, seq=5)
    assert cp.slave_snapshot(sl, [spos(7001, c["copy_id"])], seq=5)["accepted"] is False
    assert copy_of(cp, c["copy_id"])["state"] == "pending"
    assert cp.c.post("/v4/slave/snapshot", json=cp.snapshot_body(master),
                     headers={"Authorization": f"Bearer {master['token']}",
                              "Idempotency-Key": "role-1"}).status_code == 403


def test_slave_snapshot_renews_leases(cp, app):
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    cp.session(sl["token"])
    (c,) = cp.poll(sl)["commands"]
    cp.ack(sl, c["command_id"], c["copy_id"])
    with app.state.sessionmaker() as s:
        s.get(Command, c["command_id"]).lease_until = utcnow() + timedelta(seconds=1)
        s.commit()
    cp.slave_snapshot(sl)
    with app.state.sessionmaker() as s:
        lease = s.get(Command, c["command_id"]).lease_until
        assert lease.replace(tzinfo=lease.tzinfo or utcnow().tzinfo) > utcnow() + timedelta(seconds=60)


# --- adoption --------------------------------------------------------------------------------------

def test_s04_uncertain_open_adopted_from_snapshot(cp, app):
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1, magic=7)])
    (c,) = cp.poll(sl)["commands"]
    cp.results(sl, [res(c, "uncertain")])
    # wrong magic → never adopted (weak matching is not used, 5.8a)
    cp.slave_snapshot(sl, [spos(7001, c["copy_id"], magic=8)])
    assert copy_of(cp, c["copy_id"])["state"] == "uncertain"
    out = cp.slave_snapshot(sl, [spos(7001, c["copy_id"], magic=7)])
    assert out["reconcile"]["adopted"] == 1
    got = copy_of(cp, c["copy_id"])
    assert (got["state"], got["position_id"]) == ("open", 7001)
    assert cp.commands(copy_id=c["copy_id"])[0]["state"] == "done"
    assert events(app, "copy.adopted")[0]["prior_state"] == "uncertain"
    # the late real result of the same attempt afterwards only enriches ids
    cp.results(sl, [done(c, 7001)])
    got = copy_of(cp, c["copy_id"])
    assert got["state"] == "open" and got["open_deal"] == 91
    assert len(events(app, "copy.opened")) == 1


def test_s06_expired_open_executed_result_lost_adopted(cp, app):
    """S06: the server cancelled the copy (open expired), the EA executed it and the result was lost.
    Comment c<id> + magic in the slave snapshot → adopted: open (master open) / closing + close (closed)."""
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1), pos(2)])
    a, b = cp.poll(sl)["commands"]
    with app.state.sessionmaker() as s:
        for cid in (a["copy_id"], b["copy_id"]):
            s.get(Copy, cid).state = "cancelled"
        for cmd in s.scalars(select(Command)):
            cmd.state = "expired"
        s.get(MasterPosition, s.get(Copy, b["copy_id"]).master_position_id).state = "closed"
        s.commit()
    cp.slave_snapshot(sl, [spos(7001, a["copy_id"]), spos(7002, b["copy_id"])])
    assert copy_of(cp, a["copy_id"])["state"] == "open"
    assert copy_of(cp, b["copy_id"])["state"] == "closing"
    (close,) = cp.poll(sl)["commands"]
    assert (close["action"], close["position_id"]) == ("close", 7002)
    # adoption is idempotent across snapshots
    cp.slave_snapshot(sl, [spos(7001, a["copy_id"]), spos(7002, b["copy_id"])])
    assert len(events(app, "copy.adopted")) == 2 and len(cp.poll(sl)["commands"]) == 1


def test_s40_adoption_from_history_already_closed(cp, app):
    """S40: executed and closed locally before restart: history `in` (comment) + exit deal → closed."""
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    (c,) = cp.poll(sl)["commands"]
    cp.results(sl, [res(c, "uncertain")])
    hist = [deal(10, 7001, "in", comment=f"c{c['copy_id']}"), deal(11, 7001, "out", reason="client", profit=-3)]
    cp.slave_snapshot(sl, [], hist)
    got = copy_of(cp, c["copy_id"])
    assert (got["state"], got["position_id"], got["close_deal"], got["close_reason"]) == (
        "closed", 7001, 11, "manual")
    # without history_synced, history is never used as evidence
    cp.snapshot(master, [pos(1), pos(2)])
    (c2,) = [x for x in cp.poll(sl)["commands"] if x["copy_id"] != c["copy_id"]]
    cp.results(sl, [res(c2, "uncertain")])
    cp.slave_snapshot(sl, [], [deal(20, 7002, "in", comment=f"c{c2['copy_id']}")], history_synced=False)
    assert copy_of(cp, c2["copy_id"])["state"] == "uncertain"


def test_s52_duplicate_correlation_superseded_sibling(cp, app):
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    cid = o["copy_id"]
    cp.slave_snapshot(sl, [spos(7001, cid), spos(7009, cid)])
    sib = [c for c in cp.copies() if c["id"] != cid]
    assert len(sib) == 1
    sib = sib[0]
    assert (sib["state"], sib["position_id"], sib["close_intent"]) == ("superseded", 7009, True)
    (close,) = cp.poll(sl)["commands"]
    assert (close["copy_id"], close["position_id"], close["action"]) == (sib["id"], 7009, "close")
    cp.slave_snapshot(sl, [spos(7001, cid), spos(7009, cid)])  # no second sibling
    assert len(cp.copies()) == 2
    cp.results(sl, [res(close, "done", deal=77)])
    got = copy_of(cp, sib["id"])
    assert (got["state"], got["close_intent"], got["close_deal"]) == ("superseded", False, 77)
    assert copy_of(cp, cid)["state"] == "open"
    assert len(events(app, "copy.duplicate_position")) == 1


def test_s51_late_adoption_slot_reoccupied_opens_conflict(cp, app):
    """S51: netting slot freed (copy cancelled) and re-occupied; a late fill of the old copy shows up →
    symbol_conflicts(late_adoption), no second reservation, no rollback, new opens on the symbol blocked."""
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    cp.snapshot(master, [pos(1)])
    (a,) = cp.poll(sl)["commands"]
    cp.results(sl, [res(a, "expired")])  # EA refused it: cancelled, slot free
    with app.state.sessionmaker() as s:
        s.get(MasterPosition, s.get(Copy, a["copy_id"]).master_position_id).state = "closed"
        s.commit()
    cp.snapshot(master, [pos(2)])
    (b,) = [x for x in cp.poll(sl)["commands"] if x["copy_id"] != a["copy_id"]]
    cp.results(sl, [done(b, 7002)])
    r = cp.slave_snapshot(sl, [spos(7001, a["copy_id"]), spos(7002, b["copy_id"])])
    assert r["accepted"] is True
    got = copy_of(cp, a["copy_id"])
    assert got["state"] == "cancelled" and got["position_id"] == 7001  # evidence recorded, no reservation
    with app.state.sessionmaker() as s:
        (conf,) = s.scalars(select(SymbolConflict)).all()
        assert (conf.kind, conf.copy_id, conf.position_id) == ("late_adoption", a["copy_id"], 7001)
    with app.state.sessionmaker() as s:  # free the slot; a new master position is still blocked
        s.get(Copy, b["copy_id"]).state = "closed"
        s.get(MasterPosition, s.get(Copy, b["copy_id"]).master_position_id).state = "closed"
        s.commit()
    cp.snapshot(master, [pos(3)])
    newest = max(cp.copies(), key=lambda c: c["id"])
    assert (newest["state"], newest["skip_reason"]) == ("skipped", "netting_conflict")


def test_s53_unmanaged_position_on_netting_symbol(cp, app):
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    o = opened(cp, master, sl)
    cp.slave_snapshot(sl, [spos(7001, o["copy_id"]), pos(8888, comment="manual")])
    with app.state.sessionmaker() as s:
        (conf,) = s.scalars(select(SymbolConflict)).all()
        assert (conf.kind, conf.position_id, conf.copy_id) == ("unmanaged_position", 8888, o["copy_id"])
    cp.slave_snapshot(sl, [spos(7001, o["copy_id"]), pos(8888, comment="manual")])
    assert len(events(app, "copy.symbol_conflict")) == 1  # deduplicated
    assert copy_of(cp, o["copy_id"])["state"] == "open"  # never auto-closed by weak matching


# --- slave-side closes -----------------------------------------------------------------------------

def test_s21_slave_sl_hit_closes_without_command(cp, app):
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    cp.slave_snapshot(sl, [], [deal(31, 7001, "out", reason="sl", profit=-12.5)])
    got = copy_of(cp, o["copy_id"])
    assert (got["state"], got["close_reason"], got["close_deal"]) == ("closed", "slave_sl", 31)
    assert cp.poll(sl)["commands"] == []
    cp.close_master(master, 1)  # master closes later: no close for a closed copy
    assert cp.poll(sl)["commands"] == [] and copy_of(cp, o["copy_id"])["state"] == "closed"


def test_position_ticket_refreshed(cp):
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    p = spos(7001, o["copy_id"])
    p["position_ticket"] = 99001
    cp.slave_snapshot(sl, [p])
    assert copy_of(cp, o["copy_id"])["position_ticket"] == 99001


def test_s29_close_position_not_found(cp, app):
    """S29: position_not_found + slave history exit deal → closed (not error); without evidence after
    3 snapshots → close_unconfirmed alert, reservation kept (copy stays closing)."""
    master, (s1, s2) = setup(cp, n_slaves=2)
    o1 = opened(cp, master, s1)
    o2 = next(x for x in cp.poll(s2)["commands"])
    cp.results(s2, [done(o2, 7101)])
    cp.close_master(master, 1)
    (k1,) = cp.poll(s1)["commands"]
    (k2,) = cp.poll(s2)["commands"]
    cp.results(s1, [res(k1, "failed", error_code="position_not_found")])
    cp.results(s2, [res(k2, "failed", error_code="position_not_found")])
    assert copy_of(cp, o1["copy_id"])["state"] == "closing"
    cp.slave_snapshot(s1, [], [deal(41, 7001, "out", reason="client")])
    assert copy_of(cp, o1["copy_id"])["state"] == "closed"
    for _ in range(3):
        cp.slave_snapshot(s2, [])
    got = copy_of(cp, o2["copy_id"])
    assert (got["state"], got["close_reason"]) == ("closing", "close_unconfirmed")
    assert len(events(app, "copy.close_unconfirmed")) == 1


# --- netting successor (C5) ------------------------------------------------------------------------

def _close_then_reopen(cp, app):
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    o = opened(cp, master, sl)
    cp.close_master(master, 1, keep=[pos(2)])  # close-then-reopen in one snapshot
    blocked = max(cp.copies(), key=lambda c: c["id"])
    assert (blocked["state"], blocked["blocked_by"]) == ("pending_blocked", o["copy_id"])
    (close,) = cp.poll(sl)["commands"]
    return master, sl, o, close, blocked


def test_s11_successor_promoted_after_close_confirmed(cp, app):
    master, sl, o, close, blocked = _close_then_reopen(cp, app)
    cp.results(sl, [res(close, "uncertain")])  # S45: uncertain never unblocks
    assert copy_of(cp, blocked["id"])["state"] == "pending_blocked"
    cp.results(sl, [res(close, "done", deal=5)])  # resolved by evidence: zero exposure proven
    got = copy_of(cp, blocked["id"])
    assert got["state"] == "pending" and got["blocked_by"] is None
    (op,) = cp.poll(sl)["commands"]
    assert (op["action"], op["copy_id"], op["comment"]) == ("open", blocked["id"], f"c{blocked['id']}")
    assert len(events(app, "copy.promoted")) == 1


def test_s46_blocked_candidate_of_closed_master_cancelled(cp, app):
    master, sl, o, close, blocked = _close_then_reopen(cp, app)
    with app.state.sessionmaker() as s:
        s.get(MasterPosition, s.get(Copy, blocked["id"]).master_position_id).state = "closed"
        s.commit()
    cp.results(sl, [res(close, "done", deal=5)])
    assert copy_of(cp, blocked["id"])["state"] == "cancelled"
    assert cp.poll(sl)["commands"] == []


def test_promotion_revalidates_drain(cp, app):
    """C6: entering drain cancels the blocked successor (6.2), so the freed slot never emits an open."""
    master, sl, o, close, blocked = _close_then_reopen(cp, app)
    r = cp.c.patch(f"/admin/accounts/{sl['id']}", json={"status": "suspended"},
                   headers={"Authorization": "Bearer test-admin-token"})
    assert r.status_code == 200, r.text
    assert r.json()["drain"] == {"cancelled": 1, "cancel_requested": 0}
    cp.results(sl, [res(close, "done", deal=5)])
    got = copy_of(cp, blocked["id"])
    assert (got["state"], got["close_reason"]) == ("cancelled", "account_drain")
    assert len(cp.commands(copy_id=blocked["id"])) == 0  # no open born in drain
    # nothing exposed any more: the drained slave now gets 403 (6.2, S14)
    r = cp.c.get("/v4/slave/commands", headers={"Authorization": f"Bearer {sl['token']}"})
    assert r.status_code == 403


def test_expired_open_promotes_successor(cp, app):
    """A never-delivered open expiring frees the netting slot and promotes the blocked successor (C5)."""
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    cp.snapshot(master, [pos(1)])
    with app.state.sessionmaker() as s:
        first = s.scalars(select(Copy)).one()
        first.state = "cancel_requested"  # pretend a cancel is outstanding and blocks the slot
        s.get(MasterPosition, first.master_position_id).state = "closed"
        s.commit()
        first_id = first.id
    cp.snapshot(master, [pos(2)])
    blocked = max(cp.copies(), key=lambda c: c["id"])
    assert blocked["blocked_by"] == first_id
    with app.state.sessionmaker() as s:
        f = s.get(Copy, first_id)
        f.state = "pending"
        for cmd in s.scalars(select(Command)):
            cmd.expires_at = utcnow() - timedelta(seconds=1)
        s.commit()
    (op,) = cp.poll(sl)["commands"]
    assert copy_of(cp, first_id)["state"] == "cancelled"
    assert (op["action"], op["copy_id"]) == ("open", blocked["id"])
