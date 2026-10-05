"""Admin operations (Phase 1 / PR 5): resolution actions, drain on suspend / link disable, conflicts,
events/alerts, orphans and scoped admin tokens (design 4.6 step 7, 5.8, 5.8a, 6.2, 6.3, C3, C6, C8)."""

from __future__ import annotations

from sqlalchemy import select

from copycore.models import Command, CommandAttempt, Copy, MasterPosition, SymbolConflict

from .conftest import admin_headers, bearer
from .copyhelpers import pos
from .test_reconcile import spos
from .test_results import copy_of, done, events, opened, res, setup


def resolve(cp, copy_id, expect=200, **body):
    r = cp.c.post(f"/admin/copies/{copy_id}/resolve", json=body, headers=admin_headers())
    assert r.status_code == expect, r.text
    return r.json()


def resolve_conflict(cp, conflict_id, resolution, expect=200, **kw):
    r = cp.c.post(f"/admin/symbol_conflicts/{conflict_id}/resolve", json={"resolution": resolution, **kw},
                  headers=admin_headers())
    assert r.status_code == expect, r.text
    return r.json()


def uncertain_open(cp, magic=0):
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1, magic=magic)])
    (c,) = cp.poll(sl)["commands"]
    cp.results(sl, [res(c, "uncertain", error_code="timeout")])
    assert copy_of(cp, c["copy_id"])["state"] == "uncertain"
    return master, sl, c


# --- copy resolution (4.6 step 7, 5.8) --------------------------------------------------------------

def test_s42_operator_resolves_suspended_open_as_executed(cp, app):
    """S42 / S39: a suspended open is resolved by the operator; the EA journal gets a `resolve` command
    before any follow-up, and a later master close executes on the resolved position."""
    master, sl, c = uncertain_open(cp)
    assert cp.poll(sl)["commands"] == []  # suspended attempt is not re-delivered in the same session
    out = resolve(cp, c["copy_id"], executed=7001, volume=1.0, price=1.1, note="seen in terminal")
    assert (out["outcome"], out["state"], out["copy"]["position_id"]) == ("open", "open", 7001)
    (rv,) = cp.poll(sl)["commands"]
    assert (rv["action"], rv["resolves_command_id"], rv["resolves_attempt_id"], rv["resolution"],
            rv["position_id"]) == ("resolve", c["command_id"], c["attempt_id"], "executed", 7001)
    with app.state.sessionmaker() as s:
        assert s.get(Command, c["command_id"]).state == "done"
        assert s.get(CommandAttempt, (c["command_id"], c["attempt_id"])).outcome == "done"
    (audit,) = events(app, "admin.resolved")
    assert (audit["actor"], audit["resolution"], audit["prior_state"]) == ("env:ADMIN_TOKEN", "executed", "uncertain")
    cp.results(sl, [res(rv, "done")])
    cp.close_master(master, 1)
    (close,) = cp.poll(sl)["commands"]
    assert (close["action"], close["position_id"]) == ("close", 7001)
    cp.results(sl, [res(close, "done", deal=55)])
    assert copy_of(cp, c["copy_id"])["state"] == "closed"
    # a late outbox replay of the suspended attempt is a duplicate, not a second fill
    assert cp.results(sl, [done(c, 7001)])["duplicates"] == 1


def test_s42_resolved_executed_after_master_closed_closes(cp):
    """Suspended open whose master closed (close_intent): resolving it as executed issues the close."""
    master, sl, c = uncertain_open(cp)
    cp.close_master(master, 1)
    assert copy_of(cp, c["copy_id"])["close_intent"] is True
    out = resolve(cp, c["copy_id"], resolution="executed", position_id=7001)
    assert out["state"] == "closing"
    actions = [x["action"] for x in cp.poll(sl)["commands"]]
    assert actions == ["resolve", "close"]  # resolve first, then the follow-up


def test_resolve_open_not_executed_cancels(cp):
    master, sl, c = uncertain_open(cp)
    out = resolve(cp, c["copy_id"], not_executed=True)
    assert (out["state"], out["copy"]["close_reason"]) == ("cancelled", "operator_not_executed")
    (rv,) = cp.poll(sl)["commands"]
    assert (rv["action"], rv["resolution"]) == ("resolve", "not_executed")


def test_resolve_refusals(cp):
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    resolve(cp, o["copy_id"], expect=409, not_executed=True)  # not suspended
    resolve(cp, o["copy_id"], expect=422, executed=1, not_executed=True)  # two forms
    resolve(cp, 99999, expect=404, not_executed=True)
    r = cp.c.post(f"/admin/copies/{o['copy_id']}/resolve", json={"not_executed": True})
    assert r.status_code == 401
    _, sl2, c = uncertain_open_second(cp, master)
    resolve(cp, c["copy_id"], expect=422, resolution="executed")  # open needs a position_id


def uncertain_open_second(cp, master):
    g = cp.group(master["id"])
    sl2 = cp.account("slave", 777)
    cp.link(g["id"], sl2["id"])
    cp.snapshot(master, [pos(1), pos(2)])
    c = next(x for x in cp.poll(sl2)["commands"] if x["action"] == "open")
    cp.results(sl2, [res(c, "uncertain")])
    return master, sl2, c


def test_resolve_uncertain_close_not_executed_reissues_close(cp, app):
    """S41 / C3: an uncertain close resolved `not_executed` → same obligation, new attempt, copy closing."""
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    cp.close_master(master, 1)
    (close,) = cp.poll(sl)["commands"]
    cp.results(sl, [res(close, "uncertain")])
    assert copy_of(cp, o["copy_id"])["state"] == "uncertain"
    out = resolve(cp, o["copy_id"], not_executed=True)
    assert out["state"] == "closing"
    rv, again = cp.poll(sl)["commands"]
    assert (rv["action"], rv["resolves_attempt_id"]) == ("resolve", close["attempt_id"])
    assert (again["command_id"], again["action"]) == (close["command_id"], "close")
    assert again["attempt_id"] != close["attempt_id"]
    cp.results(sl, [res(again, "done", deal=8)])
    assert copy_of(cp, o["copy_id"])["state"] == "closed"


def test_resolve_uncertain_close_executed_closes(cp):
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    cp.close_master(master, 1)
    (close,) = cp.poll(sl)["commands"]
    cp.results(sl, [res(close, "uncertain")])
    out = resolve(cp, o["copy_id"], resolution="executed")
    assert out["state"] == "closed"


def test_resolve_uncertain_close_partial(cp):
    """Suspended reduction resolved with the residual volume; the copy returns to `open`."""
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    cp.snapshot(master, [pos(1, volume=0.4)])
    (cpart,) = cp.poll(sl)["commands"]
    assert cpart["action"] == "close_partial"
    cp.results(sl, [res(cpart, "uncertain")])
    resolve(cp, o["copy_id"], expect=422, resolution="executed")  # residual volume required
    out = resolve(cp, o["copy_id"], resolution="executed", volume=0.4)
    assert out["state"] == "open" and float(out["copy"]["confirmed_volume"]) == 0.4


def test_s29_close_unconfirmed_retry_and_closed(cp, app):
    """S29 follow-up: `retry_close` re-issues the close as a new attempt; `closed` settles it by hand."""
    master, (s1, s2) = setup(cp, n_slaves=2)
    o1 = opened(cp, master, s1)
    o2 = next(x for x in cp.poll(s2)["commands"])
    cp.results(s2, [done(o2, 7101)])
    cp.close_master(master, 1)
    (k1,) = cp.poll(s1)["commands"]
    (k2,) = cp.poll(s2)["commands"]
    cp.results(s1, [res(k1, "failed", error_code="position_not_found")])
    cp.results(s2, [res(k2, "failed", error_code="position_not_found")])
    for _ in range(3):
        cp.slave_snapshot(s1, [])
        cp.slave_snapshot(s2, [])
    orphans = cp.c.get("/admin/orphans", headers=admin_headers()).json()
    assert sorted(c["id"] for c in orphans["close_unconfirmed"]) == sorted([o1["copy_id"], o2["copy_id"]])
    out = resolve(cp, o1["copy_id"], resolution="retry_close")
    assert (out["outcome"], out["copy"]["close_reason"]) == ("close_reissued", None)
    (again,) = cp.poll(s1)["commands"]
    assert again["command_id"] == k1["command_id"] and again["attempt_id"] != k1["attempt_id"]
    cp.results(s1, [res(again, "done", deal=12)])
    assert copy_of(cp, o1["copy_id"])["state"] == "closed"
    out = resolve(cp, o2["copy_id"], resolution="closed", note="closed by hand at the broker")
    assert (out["state"], out["copy"]["close_reason"]) == ("closed", "operator_closed")
    resolve(cp, o2["copy_id"], expect=409, resolution="closed")
    assert cp.c.get("/admin/orphans", headers=admin_headers()).json()["close_unconfirmed"] == []


def test_revoked_slave_exposure_listed_and_closed(cp):
    """6.2: after a revocation the server no longer manages the slave's copies; the operator settles them."""
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    resolve(cp, o["copy_id"], expect=409, resolution="closed")  # managed copy: not by hand
    assert cp.c.post(f"/admin/accounts/{sl['id']}/revoke", headers=admin_headers()).status_code == 200
    orphans = cp.c.get("/admin/orphans", headers=admin_headers()).json()
    assert [c["id"] for c in orphans["revoked_exposure"]] == [o["copy_id"]]
    assert resolve(cp, o["copy_id"], resolution="closed")["state"] == "closed"


# --- drain (6.2, C6) ------------------------------------------------------------------------------

def test_s47_suspend_drains_queued_delivered_and_keeps_uncertain(cp, app):
    """S47: entering drain → open queued → cancelled (superseded), delivered → cancel_requested + cancel,
    uncertain and open copies keep full management; no open is born in drain."""
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)                                     # open
    cp.snapshot(master, [pos(1), pos(2)])
    (d2,) = cp.poll(sl)["commands"]                                # delivered
    cp.snapshot(master, [pos(1), pos(2), pos(3)])
    (u3,) = [x for x in cp.poll(sl)["commands"] if x["copy_id"] != d2["copy_id"]]
    cp.results(sl, [res(u3, "uncertain")])                         # uncertain
    cp.snapshot(master, [pos(1), pos(2), pos(3), pos(4)])           # queued (not polled)
    q4 = max(cp.copies(), key=lambda c: c["id"])
    r = cp.c.patch(f"/admin/accounts/{sl['id']}", json={"status": "suspended", "suspended_reason": "billing"},
                   headers=admin_headers())
    assert r.status_code == 200 and r.json()["drain"] == {"cancelled": 1, "cancel_requested": 1}
    assert copy_of(cp, q4["id"])["state"] == "cancelled"
    assert copy_of(cp, d2["copy_id"])["state"] == "cancel_requested"
    assert copy_of(cp, u3["copy_id"])["state"] == "uncertain"
    assert copy_of(cp, o["copy_id"])["state"] == "open"
    assert cp.c.get("/v4/config", headers=bearer(sl["token"])).json()["mode"] == "drain"
    (cancel,) = [x for x in cp.poll(sl)["commands"] if x["action"] == "cancel"]
    assert (cancel["action"], cancel["copy_id"], cancel["reason"]) == ("cancel", d2["copy_id"], "account_drain")
    cp.results(sl, [res(cancel, "not_executed")])
    got = copy_of(cp, d2["copy_id"])
    assert (got["state"], got["close_reason"]) == ("cancelled", "account_drain")
    cp.snapshot(master, [pos(1), pos(2), pos(3), pos(4), pos(5)])   # new position: skipped, never opened
    assert max(cp.copies(), key=lambda c: c["id"])["skip_reason"] == "account_drain"
    cp.close_master(master, 1, keep=[pos(2), pos(3), pos(4), pos(5)])  # existing copy still closes
    (close,) = [x for x in cp.poll(sl)["commands"] if x["action"] == "close"]
    assert close["copy_id"] == o["copy_id"]
    with app.state.sessionmaker() as s:
        assert not any(c.action == "open" and c.state == "queued" for c in s.scalars(select(Command)))


def test_link_disable_drains_and_keeps_existing_copies(cp, app):
    """6.2 link disable: new opens stop, not-yet-executed opens are taken back, existing copies keep
    receiving close."""
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    cp.snapshot(master, [pos(1), pos(2)])  # queued
    q = max(cp.copies(), key=lambda c: c["id"])
    link_id = q["link_id"]
    r = cp.c.patch(f"/admin/links/{link_id}", json={"enabled": False}, headers=admin_headers())
    assert r.status_code == 200 and r.json()["drain"] == {"cancelled": 1, "cancel_requested": 0}
    got = copy_of(cp, q["id"])
    assert (got["state"], got["close_reason"]) == ("cancelled", "link_disabled")
    cp.snapshot(master, [pos(1), pos(2), pos(3)])
    assert len(cp.copies()) == 2  # no copy for a disabled link
    cp.close_master(master, 1, keep=[pos(2), pos(3)])
    (close,) = cp.poll(sl)["commands"]
    assert (close["action"], close["copy_id"]) == ("close", o["copy_id"])


def test_group_disable_drains(cp):
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    (c,) = cp.copies()
    g = cp.c.get("/admin/groups", headers=admin_headers()).json()["groups"][0]
    r = cp.c.patch(f"/admin/groups/{g['id']}", json={"enabled": False}, headers=admin_headers())
    assert r.status_code == 200 and r.json()["drain"]["cancelled"] == 1
    assert copy_of(cp, c["id"])["state"] == "cancelled"


# --- symbol conflicts (5.8, C8) --------------------------------------------------------------------------

def _late_adoption_conflict(cp, app):
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    cp.snapshot(master, [pos(1)])
    (a,) = cp.poll(sl)["commands"]
    cp.results(sl, [res(a, "expired")])
    with app.state.sessionmaker() as s:
        s.get(MasterPosition, s.get(Copy, a["copy_id"]).master_position_id).state = "closed"
        s.commit()
    cp.snapshot(master, [pos(2)])
    (b,) = [x for x in cp.poll(sl)["commands"] if x["copy_id"] != a["copy_id"]]
    cp.results(sl, [done(b, 7002)])
    cp.slave_snapshot(sl, [spos(7001, a["copy_id"]), spos(7002, b["copy_id"])])
    with app.state.sessionmaker() as s:
        (conf,) = s.scalars(select(SymbolConflict)).all()
        return master, sl, a, b, conf.id


def test_s51_conflict_accepted_unblocks_new_opens(cp, app):
    master, sl, a, b, conf_id = _late_adoption_conflict(cp, app)
    listed = cp.c.get("/admin/symbol_conflicts", params={"open": True}, headers=admin_headers()).json()
    assert [c["id"] for c in listed["symbol_conflicts"]] == [conf_id]
    out = resolve_conflict(cp, conf_id, "accept", note="manual hedge kept")
    assert out["resolved"] is True and out["conflict"]["resolution"] == "accepted: manual hedge kept"
    (rv,) = [x for x in cp.poll(sl)["commands"] if x["action"] == "resolve"]
    assert (rv["conflict_id"], rv["resolution"], rv["position_id"]) == (conf_id, "accept", 7001)
    resolve_conflict(cp, conf_id, "accept", expect=409)
    with app.state.sessionmaker() as s:  # slot freed: a new master position opens again
        s.get(Copy, b["copy_id"]).state = "closed"
        s.get(MasterPosition, s.get(Copy, b["copy_id"]).master_position_id).state = "closed"
        s.commit()
    cp.snapshot(master, [pos(3)])
    assert max(cp.copies(), key=lambda c: c["id"])["state"] == "pending"


def test_s53_conflict_closed_by_identity(cp, app):
    """S53: the operator closes the unmanaged position by its identity; the conflict (and the block on
    new opens) ends only when the close is confirmed; the managed copy is untouched."""
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    o = opened(cp, master, sl)
    cp.slave_snapshot(sl, [spos(7001, o["copy_id"]), pos(8888, comment="manual")])
    with app.state.sessionmaker() as s:
        conf_id = s.scalars(select(SymbolConflict)).one().id
    out = resolve_conflict(cp, conf_id, "close")
    assert out["resolved"] is False and out["close_command_id"]
    assert resolve_conflict(cp, conf_id, "close")["close_command_id"] == out["close_command_id"]  # idempotent
    resolve_conflict(cp, conf_id, "accept", expect=409)  # close in flight
    cmds_ = cp.poll(sl)["commands"]
    close = next(x for x in cmds_ if x["action"] == "close")
    assert (close["position_id"], close["conflict_id"], close["magic"]) == (8888, conf_id, None)
    cp.results(sl, [res(close, "failed", error_code="market_closed")])  # retried like any close
    with app.state.sessionmaker() as s:
        assert s.get(SymbolConflict, conf_id).resolved_at is None
        cmd = s.get(Command, close["command_id"])
        cmd.next_attempt_at = None
        s.commit()
    again = next(x for x in cp.poll(sl)["commands"] if x["action"] == "close")
    cp.results(sl, [res(again, "done", deal=99)])
    with app.state.sessionmaker() as s:
        conf = s.get(SymbolConflict, conf_id)
        assert conf.resolved_at is not None and conf.resolution.startswith("closed")
    assert copy_of(cp, o["copy_id"])["state"] == "open"
    assert len(events(app, "symbol_conflict.closed")) == 1


# --- listings, tokens ---------------------------------------------------------------------------------

def test_events_alerts_and_accounts_listing(cp, app):
    master, sl, c = uncertain_open(cp)
    r = cp.c.get("/admin/events", params={"copy_id": c["copy_id"]}, headers=admin_headers())
    types = [e["type"] for e in r.json()["events"]]
    assert "copy.pending" in types and "copy.uncertain" in types
    assert all(e["payload"].get("copy_id") == c["copy_id"] for e in r.json()["events"])
    alerts = cp.c.get("/admin/alerts", headers=admin_headers()).json()["alerts"]
    assert [a["type"] for a in alerts] == ["copy.uncertain"]
    by_acct = cp.c.get("/admin/events", params={"account_id": sl["id"], "prefix": "account."},
                       headers=admin_headers()).json()["events"]
    assert by_acct and all(e["type"].startswith("account.") for e in by_acct)
    page = cp.c.get("/admin/events", params={"limit": 2}, headers=admin_headers()).json()
    older = cp.c.get("/admin/events", params={"limit": 2, "before_id": page["next_before_id"]},
                     headers=admin_headers()).json()["events"]
    assert older and max(e["id"] for e in older) < page["next_before_id"]
    accts = cp.c.get("/admin/accounts", params={"role": "slave"}, headers=admin_headers()).json()["accounts"]
    assert [a["id"] for a in accts] == [sl["id"]]
    assert cp.c.get("/admin/logs", headers=admin_headers()).json()["logs"] == []


def test_scoped_api_tokens(cp, client):
    """6.3: admin/readonly bearer tokens, shown once, stored as HMAC, revocable."""
    r = client.post("/admin/api_tokens", json={"name": "dashboard", "scopes": ["readonly"]}, headers=admin_headers())
    assert r.status_code == 201 and r.headers["cache-control"] == "no-store"
    ro = r.json()
    assert ro["token"].startswith("cct_")
    hdr = bearer(ro["token"])
    assert client.get("/admin/copies", headers=hdr).status_code == 200
    assert client.post("/admin/accounts", json={"broker_server": "B", "login": 5, "role": "slave"},
                       headers=hdr).status_code == 403
    assert client.post("/admin/api_tokens", json={"name": "x", "scopes": ["admin"]}, headers=hdr).status_code == 403
    listed = client.get("/admin/api_tokens", headers=admin_headers()).json()["api_tokens"]
    assert [t["name"] for t in listed] == ["dashboard"] and "token" not in listed[0]
    assert client.post(f"/admin/api_tokens/{ro['id']}/revoke", headers=admin_headers()).status_code == 200
    assert client.get("/admin/copies", headers=hdr).status_code == 401
    svc = client.post("/admin/api_tokens", json={"name": "rails", "scopes": ["admin"]},
                      headers=admin_headers()).json()
    assert client.post("/admin/accounts", json={"broker_server": "B", "login": 5, "role": "slave"},
                       headers=bearer(svc["token"])).status_code == 201
