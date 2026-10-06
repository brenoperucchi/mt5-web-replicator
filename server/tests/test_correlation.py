"""Copier comment `c<copy_id>-<master position_id>` and correlation by the `c<copy_id>` part (5.8a)."""

from __future__ import annotations

import pytest
from sqlalchemy import select

from copycore.engine.correlation import MT5_COMMENT_MAX, build_comment, candidate_copy_id, matches
from copycore.models import Copy, SymbolConflict

from .copyhelpers import pos
from .test_reconcile import spos
from .test_results import copy_of, res, setup

LONG = {"magic": 7, "comment": "c13-9001"}
LEGACY = {"magic": 7, "comment": "c13"}


def test_build_comment_carries_master_position_id_within_mt5_limit():
    assert build_comment(13, 9001) == "c13-9001"
    assert build_comment(13, None) == "c13"
    huge = 10 ** 30
    assert len(f"c13-{huge}") > MT5_COMMENT_MAX and build_comment(13, huge) == "c13"


@pytest.mark.parametrize("comment, params, expected", [
    ("c13-9001", LONG, True),            # full comment
    ("c13-90", LONG, True),              # suffix truncated by the broker
    ("c13-", LONG, True),                # truncated right after the separator
    ("c13-9001[sl 1.1]", LONG, True),    # suffix rewritten
    ("c13-xyz", LONG, True),             # suffix replaced
    ("c13-9002", LONG, False),           # full comment of another master position (reused copy id)
    ("c13-90011", LONG, False),          # longer master position id, not a truncation of 9001
    ("c13", LONG, False),                # truncated before `-`: indistinguishable from a cut inside the digits
    ("c1", LONG, False),                 # `c13-...` cut inside the digits: other id, never this copy
    ("c14-9001", LONG, False),           # wrong copy id
    ("c130-9001", LONG, False),          # longer id sharing the prefix
    ("c13", LEGACY, True),               # legacy / fallback comment
    ("c13-5", LEGACY, True),             # legacy copy, broker appended something after `-`
    ("c13x", LEGACY, False),             # not a copier comment
    ("C13-9001", LONG, False),
    ("", LONG, False),
])
def test_matches_uses_only_the_copy_id_part(comment, params, expected):
    assert matches(params, 13, comment, 7) is expected


def test_matches_requires_the_frozen_magic():
    assert matches(LONG, 13, "c13-9001", 8) is False


def test_candidate_copy_id():
    assert candidate_copy_id("c13-9001") == 13 and candidate_copy_id("c13") == 13
    assert candidate_copy_id("c13-") == 13 and candidate_copy_id("x13") is None and candidate_copy_id(None) is None


def _uncertain(cp, master_pid=1):
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(master_pid, magic=7)])
    (c,) = cp.poll(sl)["commands"]
    assert c["comment"] == f"c{c['copy_id']}-{master_pid}"
    cp.results(sl, [res(c, "uncertain")])
    return sl, c


@pytest.mark.parametrize("suffix", ["-4242", "-42", "-", "-4242 rewritten"])
def test_adoption_tolerates_truncated_or_rewritten_suffix(cp, suffix):
    sl, c = _uncertain(cp, 4242)
    out = cp.slave_snapshot(sl, [spos(7001, c["copy_id"], magic=7, comment=f"c{c['copy_id']}{suffix}")])
    assert out["reconcile"]["adopted"] == 1
    assert copy_of(cp, c["copy_id"])["position_id"] == 7001


@pytest.mark.parametrize("comment", ["c{id}", "c{other}-4242", "c{id}0-4242", "manual"])
def test_adoption_rejects_ambiguous_or_foreign_comments(cp, comment):
    sl, c = _uncertain(cp, 4242)
    text = comment.format(id=c["copy_id"], other=c["copy_id"] + 1)
    cp.slave_snapshot(sl, [spos(7001, c["copy_id"], magic=7, comment=text)])
    got = copy_of(cp, c["copy_id"])
    assert got["state"] == "uncertain" and got["position_id"] is None


def test_legacy_bare_comment_still_adopted(cp, app):
    sl, c = _uncertain(cp)
    with app.state.sessionmaker() as s:
        copy = s.get(Copy, c["copy_id"])
        copy.exec_params = {**copy.exec_params, "comment": f"c{copy.id}"}  # issued before this change
        s.commit()
    out = cp.slave_snapshot(sl, [spos(7001, c["copy_id"], magic=7, comment=f"c{c['copy_id']}")])
    assert out["reconcile"]["adopted"] == 1


def test_netting_bare_comment_of_long_form_copy_is_unmanaged(cp, app):
    master, (sl,) = setup(cp, master_margin="netting", slave_margin="netting")
    cp.snapshot(master, [pos(1)])
    (c,) = cp.poll(sl)["commands"]
    cp.results(sl, [{"command_id": c["command_id"], "attempt_id": c["attempt_id"], "copy_id": c["copy_id"],
                     "status": "done", "order": 81, "deal": 91, "position_ticket": 7001, "position_id": 7001,
                     "volume": 1.0, "price": 1.1}])
    cid = c["copy_id"]
    cp.slave_snapshot(sl, [spos(7001, cid, comment=f"c{cid}-1"), pos(8001, comment=f"c{cid}-1 edited"),
                           pos(8002, comment=f"c{cid}")])
    with app.state.sessionmaker() as s:
        kinds = {(x.kind, x.position_id) for x in s.scalars(select(SymbolConflict))}
    # 8001 correlates (copy id part + magic): a duplicate, not unmanaged; 8002 is ambiguous → unmanaged.
    assert ("unmanaged_position", 8002) in kinds and ("unmanaged_position", 8001) not in kinds
