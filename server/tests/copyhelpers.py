"""Helpers for the copy-flow tests (sessions, symbols, snapshots, admin config, polling)."""

from __future__ import annotations

import time
import uuid

from .conftest import admin_headers, bearer

SERVER = "Broker-Live"

DEFAULT_SPEC = {"volume_min": 0.01, "volume_step": 0.01, "volume_max": 100, "contract_size": 100000,
                "digits": 5, "point": 0.00001, "tick_size": 0.00001, "trade_mode": "full",
                "filling_modes": ["fok", "ioc"], "stops_level": 0, "freeze_level": 0}


def key() -> dict:
    return {"Idempotency-Key": str(uuid.uuid4())}


def pos(position_id, symbol="EURUSD", type="buy", volume=1.0, price=1.1, magic=0, comment="", sl=None, tp=None):
    return {"position_ticket": position_id, "position_id": position_id, "symbol": symbol, "type": type,
            "volume": volume, "price_open": price, "sl": sl, "tp": tp, "magic": magic, "comment": comment,
            "time_msc": int(time.time() * 1000)}


class Copier:
    def __init__(self, api, client):
        self.api, self.c = api, client
        self.sessions: dict[str, dict] = {}
        self.seq: dict[str, int] = {}

    # --- accounts / config ---
    def account(self, role, login, margin_mode="hedging", server=SERVER, symbols=("EURUSD",)):
        acct, token = self.api.enrolled(server, login, role, margin_mode)
        acct["token"] = token
        acct["login"] = login
        if symbols:
            self.symbols(token, {s: {} for s in symbols})
        return acct

    def symbols(self, token, specs: dict[str, dict]):
        body = {"symbols": [{"name": n, **{**DEFAULT_SPEC, **over}} for n, over in specs.items()]}
        r = self.c.put("/v4/symbols", json=body, headers={**bearer(token), **key()})
        assert r.status_code == 204, r.text

    def group(self, master_id, **kw):
        r = self.c.post("/admin/groups", json={"master_id": master_id, "name": "g", **kw}, headers=admin_headers())
        assert r.status_code == 201, r.text
        return r.json()

    def link(self, group_id, slave_id, expect=201, **kw):
        r = self.c.post("/admin/links", json={"group_id": group_id, "slave_id": slave_id, **kw},
                        headers=admin_headers())
        assert r.status_code == expect, r.text
        return r.json()

    def smap(self, master_symbol, slave_symbol, slave_id=None, expect=201):
        r = self.c.post("/admin/symbol_maps", json={"slave_id": slave_id, "master_symbol": master_symbol,
                                                    "slave_symbol": slave_symbol}, headers=admin_headers())
        assert r.status_code == expect, r.text
        return r.json()

    def copies(self, **params):
        r = self.c.get("/admin/copies", params=params, headers=admin_headers())
        assert r.status_code == 200, r.text
        return r.json()["copies"]

    def commands(self, **params):
        r = self.c.get("/admin/commands", params=params, headers=admin_headers())
        assert r.status_code == 200, r.text
        return r.json()["commands"]

    # --- EA calls ---
    def session(self, token, idem=None):
        r = self.c.post("/v4/session", json={"boot_nonce": uuid.uuid4().hex, "taken_at": int(time.time() * 1000),
                                             "ea_clock_offset_ms": 0},
                        headers={**bearer(token), "Idempotency-Key": idem or str(uuid.uuid4())})
        assert r.status_code == 201, r.text
        self.sessions[token] = r.json()
        self.seq[token] = 0
        return r.json()

    def snapshot_body(self, acct, positions=(), seq=None, session=None, connected=True, pending=(),
                      login=None, server=SERVER):
        token = acct["token"]
        sess = session or self.sessions.get(token) or self.session(token)
        if seq is None:
            self.seq[token] = self.seq.get(token, 0) + 1
            seq = self.seq[token]
        return {"session_id": sess["session_id"], "epoch": sess["epoch"], "seq": seq,
                "taken_at": int(time.time() * 1000), "ea_clock_offset_ms": 0, "connected": connected,
                "login": login if login is not None else acct["login"], "server": server,
                "history_synced": True, "positions": list(positions), "pending": list(pending), "history": []}

    def post_snapshot(self, acct, body, idem=None):
        return self.c.post("/v4/master/snapshot", json=body,
                           headers={**bearer(acct["token"]), "Idempotency-Key": idem or str(uuid.uuid4())})

    def snapshot(self, acct, positions=(), expect=200, **kw):
        r = self.post_snapshot(acct, self.snapshot_body(acct, positions, **kw))
        assert r.status_code == expect, r.text
        return r

    def poll(self, acct, after=None):
        r = self.c.get("/v4/slave/commands", params={"after": after} if after else None,
                       headers=bearer(acct["token"]))
        assert r.status_code == 200, r.text
        return r.json()

    def ack(self, acct, command_id, copy_id=None, status="in_progress"):
        return self.c.post("/v4/slave/results",
                           json={"results": [{"command_id": command_id, "copy_id": copy_id, "status": status}]},
                           headers={**bearer(acct["token"]), **key()})
