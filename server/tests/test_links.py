"""Config-time link validation (design 5.3): S10, S27, netting overlap, copy_pending (5.3a)."""

from __future__ import annotations

from sqlalchemy import select

from copycore.models import Event

from .conftest import admin_headers


def test_s10_hedging_master_to_netting_slave_rejected(cp):
    master = cp.account("master", 500, "hedging")
    sl = cp.account("slave", 601, "netting")
    r = cp.link(cp.group(master["id"])["id"], sl["id"], expect=422)
    assert r["error"] == "config_conflict"


def test_s10_unknown_slave_linked_then_disabled_on_netting_enroll(cp, api, app):
    master = cp.account("master", 500, "hedging")
    acct = api.create_account("Broker-Live", 601, "slave")  # margin_mode unknown until enroll
    lk = cp.link(cp.group(master["id"])["id"], acct["id"])
    assert lk["enabled"] is True
    r = api.enroll(api.issue_code(acct["id"]), "Broker-Live", 601, "slave", "netting")
    assert r.status_code == 201
    (row,) = cp.c.get("/admin/links", headers=admin_headers()).json()["links"]
    assert row["enabled"] is False and "netting" in row["disabled_reason"]
    with app.state.sessionmaker() as s:
        assert [e.payload["link_id"] for e in s.scalars(select(Event).where(
            Event.type == "link.disabled_conflict"))] == [lk["id"]]
    r = cp.c.patch(f"/admin/links/{lk['id']}", json={"enabled": True}, headers=admin_headers())
    assert r.status_code == 422  # cannot be re-enabled while the conflict exists


def test_netting_master_to_netting_or_hedging_slave_allowed(cp):
    master = cp.account("master", 500, "netting")
    g = cp.group(master["id"])
    cp.link(g["id"], cp.account("slave", 601, "netting")["id"])
    cp.link(g["id"], cp.account("slave", 602, "hedging")["id"])


def test_s27_copy_cycle_rejected(cp):
    a_master = cp.account("master", 1)
    b_slave = cp.account("slave", 2)
    cp.link(cp.group(a_master["id"])["id"], b_slave["id"])
    b_master = cp.account("master", 2)
    a_slave = cp.account("slave", 1)
    r = cp.link(cp.group(b_master["id"])["id"], a_slave["id"], expect=422)
    assert "cycle" in r["message"]
    # indirect: A→B, B→C, C→A
    c_slave = cp.account("slave", 3)
    cp.link(cp.group(b_master["id"])["id"], c_slave["id"])
    c_master = cp.account("master", 3)
    assert cp.link(cp.group(c_master["id"])["id"], a_slave["id"], expect=422)["error"] == "config_conflict"


def test_netting_slave_links_need_disjoint_filters(cp):
    m1 = cp.account("master", 1, "netting")
    m2 = cp.account("master", 2, "netting")
    sl = cp.account("slave", 9, "netting")
    cp.link(cp.group(m1["id"])["id"], sl["id"])
    assert cp.link(cp.group(m2["id"])["id"], sl["id"], expect=422)["error"] == "config_conflict"
    g1 = cp.c.get("/admin/groups", params={"master_id": m1["id"]}, headers=admin_headers()).json()["groups"][0]
    r = cp.c.patch(f"/admin/groups/{g1['id']}", json={"symbol_filter": ["EURUSD"]}, headers=admin_headers())
    assert r.status_code == 200
    cp.link(cp.group(m2["id"], symbol_filter=["GBPUSD"])["id"], sl["id"])
    # a map that makes the two filters collide on the slave is rejected
    r = cp.c.post("/admin/symbol_maps", json={"slave_id": sl["id"], "master_symbol": "GBPUSD",
                                              "slave_symbol": "EURUSD"}, headers=admin_headers())
    assert r.status_code == 422


def test_link_rejects_copy_pending_and_validates_lot(cp):
    master = cp.account("master", 500)
    g = cp.group(master["id"])
    sl = cp.account("slave", 601)
    assert cp.link(g["id"], sl["id"], copy_pending=True, expect=422)["error"] == "validation"
    assert cp.link(g["id"], sl["id"], lot_mode="multiplier", expect=422)["error"] == "validation"
    assert cp.link(g["id"], sl["id"], magic_mode="fixed", expect=422)["error"] == "validation"
    cp.link(g["id"], sl["id"], lot_mode="fixed", lot_value=0.1)
    assert cp.link(g["id"], sl["id"], expect=409)["error"] == "link_exists"


def test_link_roles_enforced(cp):
    m = cp.account("master", 500)
    other_master = cp.account("master", 501)
    assert cp.link(cp.group(m["id"])["id"], other_master["id"], expect=422)["error"] == "config_conflict"
