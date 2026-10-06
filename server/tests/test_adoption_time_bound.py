"""Adoption ignores a `c<copy_id>` that was on the slave before the copy existed (live 2026-10-06).

The slave demo account had history deals and positions from another Copy Server with comments
c22-c125; this server issued copies c22-c25 and adopted those old fills. Evidence from the snapshot
now counts only when its broker time, converted with `broker_offset_ms` (broker server time - EA UTC)
and `ea_clock_offset_ms` (server - EA), is not older than the copy's `created_at` minus a small skew,
and a digits-only comment suffix must be the copy's master position id (or a truncation of it).
"""

from __future__ import annotations

import time
import uuid
from datetime import UTC

from sqlalchemy import select

from copycore.models import Copy, SymbolConflict

from .conftest import bearer
from .copyhelpers import deal, pos
from .test_reconcile import spos
from .test_results import copy_of, res, setup

HOUR = 3_600_000


def _uncertain(cp, master_pid=1):
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(master_pid, magic=7)])
    (c,) = cp.poll(sl)["commands"]
    cp.results(sl, [res(c, "uncertain")])
    return sl, c


def _created_ms(app, copy_id) -> int:
    with app.state.sessionmaker() as s:
        created = s.get(Copy, copy_id).created_at
    if created.tzinfo is None:
        created = created.replace(tzinfo=UTC)
    return int(created.timestamp() * 1000)


def _snap(cp, sl, positions=(), history=(), broker_offset_ms=0, ea_clock_offset_ms=0):
    body = cp.snapshot_body(sl, positions)
    body["history"] = list(history)
    body["broker_offset_ms"] = broker_offset_ms
    body["ea_clock_offset_ms"] = ea_clock_offset_ms
    r = cp.c.post("/v4/slave/snapshot", json=body,
                  headers={**bearer(sl["token"]), "Idempotency-Key": str(uuid.uuid4())})
    assert r.status_code == 200, r.text
    return r.json()


def _at(p: dict, time_msc: int) -> dict:
    return {**p, "time_msc": time_msc}


def test_live_case_old_history_deal_and_position_with_same_copy_id_not_adopted(cp, app):
    """Old fills from before the copy (another server's c<id>) are never adopted, even with a suffix that
    looks like a truncation of ours; the copy stays for the EA result / manual resolution."""
    sl, c = _uncertain(cp)
    cid = c["copy_id"]
    old = _created_ms(app, cid) - 2 * HOUR
    stale_pos = _at(spos(5001, cid, magic=7, comment=f"c{cid}-1"), old)
    stale_in = _at(deal(500, 5002, "in", magic=7, comment=f"c{cid}-1"), old)
    stale_out = _at(deal(501, 5002, "out", magic=7), old + 1000)
    out = _snap(cp, sl, [stale_pos], [stale_in, stale_out])
    assert out.get("reconcile", {}).get("adopted", 0) == 0
    got = copy_of(cp, cid)
    assert (got["state"], got["position_id"]) == ("uncertain", None)


def test_fill_after_copy_creation_is_adopted_with_broker_offset(cp, app):
    """Broker time (UTC+3) of a fill made after the copy existed → adopted; the same wall-clock value
    read as UTC would have looked 3 h newer, so the offset is what keeps old deals out."""
    sl, c = _uncertain(cp)
    cid = c["copy_id"]
    created = _created_ms(app, cid)
    # 1 h before creation in UTC, but 2 h "after" when the broker offset is ignored: rejected
    early = _at(spos(5001, cid, magic=7, comment=f"c{cid}-1"), created - HOUR + 3 * HOUR)
    assert _snap(cp, sl, [early], broker_offset_ms=3 * HOUR).get("reconcile", {}).get("adopted", 0) == 0
    fresh = _at(spos(7001, cid, magic=7, comment=f"c{cid}-1"), created + 1000 + 3 * HOUR)
    assert _snap(cp, sl, [fresh], broker_offset_ms=3 * HOUR)["reconcile"]["adopted"] == 1
    assert copy_of(cp, cid)["position_id"] == 7001


def test_small_clock_skew_tolerated(cp, app):
    sl, c = _uncertain(cp)
    cid = c["copy_id"]
    fill = _at(spos(7001, cid, magic=7, comment=f"c{cid}-1"), _created_ms(app, cid) - 2000)
    assert _snap(cp, sl, [fill])["reconcile"]["adopted"] == 1


def test_full_comment_with_another_master_position_id_not_adopted(cp, app):
    sl, c = _uncertain(cp, 4242)
    cid = c["copy_id"]
    now = int(time.time() * 1000)
    out = _snap(cp, sl, [_at(spos(7001, cid, magic=7, comment=f"c{cid}-9999"), now)],
                [_at(deal(600, 7002, "in", magic=7, comment=f"c{cid}-4243"), now)])
    assert out.get("reconcile", {}).get("adopted", 0) == 0
    assert copy_of(cp, cid)["state"] == "uncertain"


def test_netting_old_position_with_colliding_comment_is_unmanaged(cp, app):
    """A pre-existing position c<id>-... on a netting slave is not ours: unmanaged conflict, not a duplicate."""
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    cp.snapshot(master, [pos(1)])
    (c,) = cp.poll(sl)["commands"]
    cid = c["copy_id"]
    cp.results(sl, [{"command_id": c["command_id"], "attempt_id": c["attempt_id"], "copy_id": cid,
                     "status": "done", "order": 81, "deal": 91, "position_ticket": 7001, "position_id": 7001,
                     "volume": 1.0, "price": 1.1}])
    old = _created_ms(app, cid) - 2 * HOUR
    _snap(cp, sl, [spos(7001, cid, comment=f"c{cid}-1"), _at(pos(8001, comment=f"c{cid}-1"), old)])
    with app.state.sessionmaker() as s:
        kinds = {(x.kind, x.position_id) for x in s.scalars(select(SymbolConflict))}
        siblings = s.scalars(select(Copy).where(Copy.position_id == 8001)).all()
    assert ("unmanaged_position", 8001) in kinds and not siblings
