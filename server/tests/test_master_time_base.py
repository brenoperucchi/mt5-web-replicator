"""Master deal times are broker server time; generation start is Copy Server UTC.

`after_start` must convert with `broker_offset_ms` (broker - EA UTC) and `ea_clock_offset_ms`
(server - EA) like adoption does, or a stale deal looks newer (broker ahead of UTC) and a genuine
close looks older (broker behind UTC).
"""

from __future__ import annotations

import time

from .copyhelpers import deal, pos
from .test_master_close import commands_of, masters
from .test_results import events, opened, setup

HOUR = 3_600_000


def _snap(cp, master, positions, history, broker_offset_ms, ea_clock_offset_ms=0):
    body = cp.snapshot_body(master, positions, history=history)
    body["broker_offset_ms"] = broker_offset_ms
    body["ea_clock_offset_ms"] = ea_clock_offset_ms
    r = cp.post_snapshot(master, body)
    assert r.status_code == 200, r.text


def _broker(offset_ms, utc_delta_ms=0, ea_clock_offset_ms=0):
    """Broker-time `time_msc` of an event at server UTC now + utc_delta, as the EA reports it."""
    return int(time.time() * 1000) + utc_delta_ms + offset_ms - ea_clock_offset_ms


def test_stale_out_deal_not_newer_when_broker_ahead_of_utc(cp, app):
    master, (sl,) = setup(cp)
    opened(cp, master, sl)
    old = deal(6001, 1, "out")
    old["time_msc"] = _broker(3 * HOUR, -HOUR)  # 1 h before generation start in UTC
    _snap(cp, master, [], [old], 3 * HOUR)
    assert masters(app)[0][3] == "open"


def test_genuine_out_deal_closes_via_history_when_broker_behind_utc(cp, app):
    master, (sl,) = setup(cp)
    o = opened(cp, master, sl)
    out = deal(6002, 1, "out")
    out["time_msc"] = _broker(-3 * HOUR)  # happening now in UTC
    _snap(cp, master, [], [out], -3 * HOUR)
    assert masters(app)[0][3:] == ("closed", "history")
    assert commands_of(cp, o["copy_id"])[-1] == ("close", "queued")


def test_genuine_out_deal_with_broker_ahead_and_ea_clock_skew_closes(cp, app):
    master, (sl,) = setup(cp)
    opened(cp, master, sl)
    out = deal(6003, 1, "out")
    out["time_msc"] = _broker(3 * HOUR, ea_clock_offset_ms=-120_000)  # EA clock 2 min ahead of server
    _snap(cp, master, [], [out], 3 * HOUR, ea_clock_offset_ms=-120_000)
    assert masters(app)[0][3:] == ("closed", "history")


def test_stale_inout_deal_does_not_reverse_when_broker_ahead_of_utc(cp, app):
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    opened(cp, master, sl)
    late = deal(6004, 1, "inout", volume=2.0)
    late["time_msc"] = _broker(3 * HOUR, -HOUR)
    _snap(cp, master, [pos(1)], [late], 3 * HOUR)
    assert [m[:2] for m in masters(app)] == [(1, 0)]
    assert not events(app, "master_position.reversed")


def test_genuine_inout_reverses_when_broker_behind_utc(cp, app):
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    opened(cp, master, sl)
    inout = deal(6005, 1, "inout", volume=2.0)
    inout["time_msc"] = _broker(-3 * HOUR)
    _snap(cp, master, [pos(1, type="sell")], [inout], -3 * HOUR)
    assert [m[:2] for m in masters(app)] == [(1, 0), (1, 1)]
