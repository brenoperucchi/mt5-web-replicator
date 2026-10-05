"""Command delivery (design 4.4, 4.5): un-acked re-delivery, cursor hint, ordering, lease, expiry."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select

from copycore.models import Command, Copy, utcnow

from .copyhelpers import pos


def setup(cp, n_slaves=1):
    master = cp.account("master", 500)
    g = cp.group(master["id"])
    slaves = [cp.account("slave", 600 + i) for i in range(n_slaves)]
    for sl in slaves:
        cp.link(g["id"], sl["id"])
    return master, slaves


def test_poll_returns_unacked_regardless_of_cursor(cp):
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    first = cp.poll(sl)
    assert len(first["commands"]) == 1
    again = cp.poll(sl, after=first["cursor"])  # cursor is a hint: un-acked still re-included
    assert [c["command_id"] for c in again["commands"]] == [first["commands"][0]["command_id"]]
    cp.snapshot(master, [pos(1), pos(2)])
    third = cp.poll(sl, after=again["cursor"])
    assert len(third["commands"]) == 2 and int(third["cursor"]) >= int(first["cursor"])


def test_poll_is_per_slave_and_ordered(cp, app):
    master, (s1, s2) = setup(cp, 2)
    cp.snapshot(master, [pos(1)])
    cp.snapshot(master, [pos(1), pos(2)])
    cp.snapshot(master, [pos(1), pos(2), pos(3)])
    with app.state.sessionmaker() as s:  # add a second command on the first copy (issue order)
        from copycore.engine.commands import issue
        c1 = s.scalars(select(Copy).where(Copy.slave_id == s1["id"]).order_by(Copy.id)).first()
        issue(s, c1, "modify", {"sl": 1.0, "tp": None, "position_id": None})
        s.commit()
    cmds = cp.poll(s1)["commands"]
    assert [c["action"] for c in cmds] == ["open", "open", "open", "modify"]
    by_copy = [(c["copy_id"], c["seq_in_copy"]) for c in cmds if c["copy_id"] == cmds[0]["copy_id"]]
    assert by_copy == sorted(by_copy) and by_copy[-1][1] == 2
    assert all(c["copy_id"] != cmds[0]["copy_id"] for c in cp.poll(s2)["commands"])


def test_in_progress_ack_leases_then_redelivers(cp, app):
    """S38 (server side): in_progress = receipt ack under lease; re-delivered after lease expiry."""
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    (c,) = cp.poll(sl)["commands"]
    r = cp.ack(sl, c["command_id"], c["copy_id"])
    assert r.status_code == 200 and r.json()["unknown"] == []
    assert cp.poll(sl)["commands"] == []  # acked and leased
    with app.state.sessionmaker() as s:
        cmd = s.get(Command, c["command_id"])
        assert cmd.state == "in_progress" and cmd.acked_at is not None
        cmd.lease_until = utcnow() - timedelta(seconds=1)
        s.commit()
    assert [x["command_id"] for x in cp.poll(sl)["commands"]] == [c["command_id"]]


def test_new_slave_session_releases_leases(cp):
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    (c,) = cp.poll(sl)["commands"]
    cp.ack(sl, c["command_id"], c["copy_id"])
    assert cp.poll(sl)["commands"] == []
    cp.session(sl["token"])  # EA restart
    assert [x["command_id"] for x in cp.poll(sl)["commands"]] == [c["command_id"]]


def test_ack_unknown_or_foreign_commands(cp):
    master, (s1, s2) = setup(cp, 2)
    cp.snapshot(master, [pos(1)])
    (c,) = cp.poll(s1)["commands"]
    r = cp.ack(s2, c["command_id"])  # another slave's command
    assert r.json()["unknown"] == [c["command_id"]]
    assert cp.ack(s1, "c_nope").json()["unknown"] == ["c_nope"]
    assert cp.ack(s1, c["command_id"], copy_id=c["copy_id"] + 999).json()["unknown"] == [c["command_id"]]
    assert cp.ack(s1, c["command_id"], status="bogus").status_code == 422  # unknown status: EA keeps it


def test_open_expires_before_delivery_only(cp, app):
    master, (s1, s2) = setup(cp, 2)
    cp.snapshot(master, [pos(1)])
    (delivered,) = cp.poll(s2)["commands"]  # s2 received its open in time
    with app.state.sessionmaker() as s:
        for cmd in s.scalars(select(Command)):
            cmd.expires_at = utcnow() - timedelta(seconds=1)
        s.commit()
    assert cp.poll(s1)["commands"] == []  # never sent → expired, not delivered
    (c1,) = cp.copies(slave_id=s1["id"])
    assert (c1["state"], c1["close_reason"]) == ("cancelled", "open_expired")
    # already delivered: still re-delivered (the EA refuses it past expires_at and reports `expired`)
    assert [c["command_id"] for c in cp.poll(s2)["commands"]] == [delivered["command_id"]]
    assert cp.copies(slave_id=s2["id"])[0]["state"] == "pending"
