"""Command results, retry policy and journal replay (design 4.5, 4.6, 5.5, 5.7; C2, C3).

Master close detection lands in a later PR: `master_closes` below applies the 5.5 "master closed"
transitions directly with the engine so result handling can be exercised now.
"""

from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from sqlalchemy import select

from copycore.engine import commands as cmds
from copycore.engine.lifecycle import issue_close
from copycore.models import Command, CommandAttempt, Copy, Event, MasterPosition, utcnow

from .copyhelpers import pos


def setup(cp, n_slaves=1, master_margin="hedging", slave_margin="hedging"):
    master = cp.account("master", 500, master_margin)
    g = cp.group(master["id"])
    slaves = [cp.account("slave", 600 + i, slave_margin) for i in range(n_slaves)]
    for sl in slaves:
        cp.link(g["id"], sl["id"])
    return master, slaves


def events(app, type_):
    with app.state.sessionmaker() as s:
        return [e.payload for e in s.scalars(select(Event).where(Event.type == type_).order_by(Event.id))]


def copy_of(cp, copy_id):
    return next(c for c in cp.copies() if c["id"] == copy_id)


def done(c, position_id=7001, **kw):
    return {"command_id": c["command_id"], "attempt_id": c["attempt_id"], "copy_id": c["copy_id"],
            "status": "done", "order": 81, "deal": 91, "position_ticket": position_id, "position_id": position_id,
            "volume": c.get("volume", 1.0), "price": 1.1002, **kw}


def res(c, status, **kw):
    return {"command_id": c["command_id"], "attempt_id": c["attempt_id"], "copy_id": c["copy_id"],
            "status": status, **kw}


def master_closes(app, copy_id):
    """5.5 'master closed' transitions (PR 4 will drive them from master snapshots)."""
    with app.state.sessionmaker() as s:
        copy = s.get(Copy, copy_id)
        s.get(MasterPosition, copy.master_position_id).state = "closed"
        if copy.state == "open":
            issue_close(s, copy, "master_closed")
        elif copy.state == "pending":
            copy.state = "cancel_requested"
            cmds.issue(s, copy, "cancel", {"position_id": None, "symbol": copy.symbol_local})
        elif copy.state == "uncertain":
            copy.close_intent = True
        s.commit()


def opened(cp, master, sl, position_id=1, result_pid=7001):
    cp.snapshot(master, [pos(position_id)])
    c = next(x for x in cp.poll(sl)["commands"] if x["action"] == "open")
    out = cp.results(sl, [done(c, result_pid)])
    assert out["unknown"] == [] and out["applied"] == 1
    return c


# --- open results -------------------------------------------------------------------------------

def test_open_done_confirms_copy_and_command(cp, app):
    master, (sl,) = setup(cp)
    c = opened(cp, master, sl)
    cp_ = copy_of(cp, c["copy_id"])
    assert cp_["state"] == "open" and cp_["position_id"] == 7001 and cp_["open_deal"] == 91
    assert Decimal(cp_["confirmed_volume"]) == Decimal("1") and Decimal(cp_["price_open"]) == Decimal("1.1002")
    assert cp.poll(sl)["commands"] == []
    (cmd,) = cp.commands(copy_id=c["copy_id"])
    assert cmd["state"] == "done"
    assert len(events(app, "copy.opened")) == 1
    with app.state.sessionmaker() as s:
        assert s.get(CommandAttempt, (c["command_id"], c["attempt_id"])).outcome == "done"


def test_duplicate_and_replayed_results_are_noops(cp, app):
    """5.7 / 4.6: same attempt result again (new key, outbox replay after restart) → no-op; same key → replay."""
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    (c,) = cp.poll(sl)["commands"]
    first = cp.results(sl, [done(c)], idem="k-1")
    replayed = cp.results(sl, [done(c)], idem="k-1")  # stored response
    assert {k: v for k, v in replayed.items() if k != "server_time"} == {
        k: v for k, v in first.items() if k != "server_time"} and first["applied"] == 1
    cp.session(sl["token"])  # EA restart: outbox replays with a fresh key
    again = cp.results(sl, [done(c)])
    assert again["duplicates"] == 1 and again["applied"] == 0 and again["unknown"] == []
    assert len(events(app, "copy.opened")) == 1


def test_s01_lost_result_redelivered_open_answered_from_journal(cp, app):
    """S01 / S38: in_progress ack, result lost, lease expires → re-delivered; the EA re-sends the stored
    result of the same attempt (never a second order); one copy, open."""
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    (c,) = cp.poll(sl)["commands"]
    cp.ack(sl, c["command_id"], c["copy_id"])
    with app.state.sessionmaker() as s:
        s.get(Command, c["command_id"]).lease_until = utcnow() - timedelta(seconds=1)
        s.commit()
    (again,) = cp.poll(sl)["commands"]
    assert (again["command_id"], again["attempt_id"]) == (c["command_id"], c["attempt_id"])
    cp.results(sl, [done(again)])
    assert copy_of(cp, c["copy_id"])["state"] == "open"
    assert cp.poll(sl)["commands"] == []


def test_out_of_order_results_in_one_batch_and_late_receipt(cp, app):
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    (c,) = cp.poll(sl)["commands"]
    # `done` listed before its own `in_progress`: applied in order (receipt first), ends done
    out = cp.results(sl, [done(c), res(c, "in_progress")])
    assert out["applied"] == 2
    cp.ack(sl, c["command_id"], c["copy_id"])  # late receipt ack after settlement: no-op
    assert cp.commands(copy_id=c["copy_id"])[0]["state"] == "done"
    # `uncertain` arriving after a conclusive result of the same attempt never downgrades it
    assert cp.results(sl, [res(c, "uncertain")])["duplicates"] == 1
    assert copy_of(cp, c["copy_id"])["state"] == "open"


def test_unknown_foreign_and_unknown_attempt(cp):
    master, (s1, s2) = setup(cp, 2)
    cp.snapshot(master, [pos(1)])
    (c,) = cp.poll(s1)["commands"]
    assert cp.results(s2, [done(c)])["unknown"] == [c["command_id"]]
    assert cp.results(s1, [{**done(c), "attempt_id": "a_never_issued"}])["unknown"] == [c["command_id"]]
    assert cp.results(s1, [{**done(c), "command_id": "c_nope"}])["unknown"] == ["c_nope"]
    assert copy_of(cp, c["copy_id"])["state"] == "pending"


def test_open_definitive_failures(cp, app):
    """5.5: open failed (definite) → error, no exposure; S20 price guard → skipped; expired/not_executed
    → cancelled; netting physical slot occupied → error + copy.slot_occupied."""
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1), pos(2), pos(3), pos(4)])
    c1, c2, c3, c4 = cp.poll(sl)["commands"]
    cp.results(sl, [res(c1, "failed", error_code="symbol_not_found"),
                    res(c2, "failed", error_code="price_out_of_range"),
                    res(c3, "expired"),
                    res(c4, "failed", error_code="unmanaged_position_on_symbol")])
    got = {c["id"]: (c["state"], c["skip_reason"], c["close_reason"]) for c in cp.copies()}
    assert got[c1["copy_id"]] == ("error", "symbol_not_found", None)
    assert got[c2["copy_id"]] == ("skipped", "price_out_of_range", None)
    assert got[c3["copy_id"]] == ("cancelled", None, "open_expired")
    assert got[c4["copy_id"]][:2] == ("error", "unmanaged_position_on_symbol")
    assert len(events(app, "copy.slot_occupied")) == 1
    assert {c["state"] for c in cp.commands()} == {"failed", "expired"}
    assert cp.poll(sl)["commands"] == []


def test_late_fill_after_expiry_reopens_or_closes(cp, app):
    """Late `done` after the server cancelled the copy: exposure evidence wins (5.5 transition
    idempotency). Master open → open; master closed → closing + close."""
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1), pos(2)])
    a, b = cp.poll(sl)["commands"]
    with app.state.sessionmaker() as s:  # both opens expired + copies cancelled on the server
        for cid in (a["copy_id"], b["copy_id"]):
            cp_ = s.get(Copy, cid)
            cp_.state, cp_.close_reason = "cancelled", "open_expired"
        for cmd in s.scalars(select(Command)):
            cmd.state = "expired"
        s.get(MasterPosition, s.get(Copy, b["copy_id"]).master_position_id).state = "closed"
        s.commit()
    cp.results(sl, [done(a, 7001), done(b, 7002)])
    assert copy_of(cp, a["copy_id"])["state"] == "open"
    assert copy_of(cp, b["copy_id"])["state"] == "closing"
    (close,) = cp.poll(sl)["commands"]
    assert close["action"] == "close" and close["position_id"] == 7002 and close["copy_id"] == b["copy_id"]
    assert len(events(app, "copy.late_fill")) == 2


def test_open_done_after_cancel_requested_closes(cp, app):
    """rev-2 A12: late `open done` on cancel_requested → record ids, closing + close; undelivered cancel superseded."""
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    (c,) = cp.poll(sl)["commands"]
    master_closes(app, c["copy_id"])
    assert copy_of(cp, c["copy_id"])["state"] == "cancel_requested"
    cp.results(sl, [done(c)])
    assert copy_of(cp, c["copy_id"])["state"] == "closing"
    states = {x["action"]: x["state"] for x in cp.commands(copy_id=c["copy_id"])}
    assert states == {"open": "done", "cancel": "superseded", "close": "queued"}


def test_s05_cancel_after_execution_reports_closed(cp, app):
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    (o,) = cp.poll(sl)["commands"]
    master_closes(app, o["copy_id"])
    (cancel,) = [x for x in cp.poll(sl)["commands"] if x["action"] == "cancel"]
    cp.results(sl, [res(cancel, "closed", position_id=7001, deal=99, price=1.2, profit=5.5)])
    got = copy_of(cp, o["copy_id"])
    assert (got["state"], got["close_reason"], got["close_deal"]) == ("closed", "master_closed", 99)
    assert cp.poll(sl)["commands"] == []
    assert {x["action"]: x["state"] for x in cp.commands(copy_id=o["copy_id"])} == {"open": "done",
                                                                                   "cancel": "done"}


def test_cancel_not_executed_cancels(cp, app):
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    (o,) = cp.poll(sl)["commands"]
    master_closes(app, o["copy_id"])
    (cancel,) = [x for x in cp.poll(sl)["commands"] if x["action"] == "cancel"]
    cp.results(sl, [res(cancel, "not_executed")])
    assert copy_of(cp, o["copy_id"])["state"] == "cancelled"
    assert cp.poll(sl)["commands"] == []


# --- close results, retries -------------------------------------------------------------------

def test_s08_s35_close_market_closed_retries_with_new_attempt(cp, app):
    """S08/S35: MARKET_CLOSED → same command, new attempt_id after backoff, symbol stays reserved;
    the old attempt's replay is a no-op; the new attempt closes for real."""
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    o = opened(cp, master, sl)
    master_closes(app, o["copy_id"])
    (close,) = cp.poll(sl)["commands"]
    out = cp.results(sl, [res(close, "failed", error_code="MARKET_CLOSED")])
    assert out["applied"] == 1
    assert copy_of(cp, o["copy_id"])["state"] == "closing"  # reservation kept
    assert cp.poll(sl)["commands"] == []  # retry_wait until next_attempt_at
    with app.state.sessionmaker() as s:
        cmd = s.get(Command, close["command_id"])
        assert cmd.state == "retry_wait" and cmd.attempts == 2 and cmd.attempt_id != close["attempt_id"]
        cmd.next_attempt_at = utcnow() - timedelta(seconds=1)
        s.commit()
    (retry,) = cp.poll(sl)["commands"]
    assert retry["command_id"] == close["command_id"] and retry["attempt_id"] != close["attempt_id"]
    assert cp.results(sl, [res(close, "failed", error_code="MARKET_CLOSED")])["duplicates"] == 1
    cp.results(sl, [res(retry, "done", deal=123, price=1.3, profit=10)])
    got = copy_of(cp, o["copy_id"])
    assert (got["state"], got["close_deal"]) == ("closed", 123)
    assert len(events(app, "command.retry")) == 1


def test_s37_done_partial_on_close_keeps_closing_and_reissues_rest(cp, app):
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    master_closes(app, o["copy_id"])
    (close,) = cp.poll(sl)["commands"]
    cp.results(sl, [res(close, "done_partial", executed_volume=0.6, residual_volume=0.4, deal=55)])
    got = copy_of(cp, o["copy_id"])
    assert got["state"] == "closing" and Decimal(got["confirmed_volume"]) == Decimal("0.4")
    (rest,) = cp.poll(sl)["commands"]
    assert rest["attempt_id"] != close["attempt_id"] and rest["volume"] == 0.4
    cp.results(sl, [res(rest, "done", deal=56)])
    assert copy_of(cp, o["copy_id"])["state"] == "closed"


def test_s41_uncertain_is_per_copy(cp, app):
    """S41 / S04: one copy uncertain (not re-delivered, close intent kept) while another copy's close runs."""
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1), pos(2)])
    a, b = cp.poll(sl)["commands"]
    cp.results(sl, [res(a, "uncertain", message="no answer while disconnected"), done(b, 7002)])
    assert copy_of(cp, a["copy_id"])["state"] == "uncertain"
    master_closes(app, a["copy_id"])
    master_closes(app, b["copy_id"])
    polled = cp.poll(sl)["commands"]
    assert [(x["action"], x["copy_id"]) for x in polled] == [("close", b["copy_id"])]
    got = copy_of(cp, a["copy_id"])
    assert got["state"] == "uncertain" and got["close_intent"] is True
    # later conclusive evidence for the same attempt resolves it (4.6 step 7): closing + close
    cp.results(sl, [done(a, 7001)])
    assert copy_of(cp, a["copy_id"])["state"] == "closing"
    assert {x["copy_id"] for x in cp.poll(sl)["commands"]} == {a["copy_id"], b["copy_id"]}


def test_uncertain_redelivered_once_on_new_session(cp):
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    (a,) = cp.poll(sl)["commands"]
    cp.results(sl, [res(a, "uncertain")])
    assert cp.poll(sl)["commands"] == []
    cp.session(sl["token"])  # EA restart: re-check from the journal (4.6 step 8)
    assert [x["command_id"] for x in cp.poll(sl)["commands"]] == [a["command_id"]]


def test_notmodify_escalates_to_no_sltp(cp, app):
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    with app.state.sessionmaker() as s:
        copy = s.get(Copy, o["copy_id"])
        for _ in range(2):
            cmds.issue(s, copy, "modify", {"sl": 1.0, "tp": None, "position_id": 7001})
        s.commit()
    m1, m2 = cp.poll(sl)["commands"]
    cp.results(sl, [res(m1, "notmodify"), res(m2, "notmodify")])
    got = copy_of(cp, o["copy_id"])
    assert got["no_sltp"] is True and got["notmodify_count"] == 2 and got["state"] == "open"
