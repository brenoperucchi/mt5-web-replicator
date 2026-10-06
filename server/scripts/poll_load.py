"""Synthetic poll load against a throwaway Copy Server (never a live one).

Starts its own server (alembic + uvicorn, one worker) on a fresh database, enrolls 1 master and
N slaves with one link each, then for --duration seconds:

- the master posts a snapshot every --master-ms (default 1000) and opens/closes one position
  every --trade-every seconds (so slaves get real commands, results and fan-out writes);
- each slave polls GET /v4/slave/commands every --poll-ms (jittered start), posts `done`/`closed`
  results for what it receives and a slave snapshot every 10 s, like the EA.

Reports req/s, p50/p99 latency per route, non-2xx and 503 rates, and the CPU of the server
process (and of the Postgres cluster when --pg-pids-from is given).

    uv run python scripts/poll_load.py --database-url sqlite:////tmp/x/load.db --slaves 20 --poll-ms 1000
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import random
import statistics
import subprocess
import sys
import time
import uuid
from collections import defaultdict
from pathlib import Path

import httpx

ADMIN = "load-admin-token"
SERVER = "Load-Broker"
SPEC = {"volume_min": 0.01, "volume_step": 0.01, "volume_max": 100, "contract_size": 100000, "digits": 5,
        "point": 0.00001, "tick_size": 0.00001, "trade_mode": "full", "filling_modes": ["fok", "ioc"],
        "stops_level": 0, "freeze_level": 0}
TICK = os.sysconf("SC_CLK_TCK")


def cpu_seconds(pid: int) -> float:
    try:
        f = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        return (int(f[11]) + int(f[12])) / TICK
    except (OSError, IndexError):
        return 0.0


def tree_pids(root: int) -> list[int]:
    out = [root]
    for p in Path("/proc").iterdir():
        if p.name.isdigit():
            try:
                ppid = int((p / "stat").read_text().rsplit(")", 1)[1].split()[1])
            except (OSError, IndexError):
                continue
            if ppid == root:
                out.append(int(p.name))
    return out


class Stats:
    def __init__(self):
        self.lat = defaultdict(list)
        self.codes = defaultdict(lambda: defaultdict(int))

    def add(self, route: str, ms: float, code: int):
        self.lat[route].append(ms)
        self.codes[route][code] += 1


async def call(c: httpx.AsyncClient, st: Stats | None, route: str, method: str, url: str, **kw) -> httpx.Response:
    t = time.perf_counter()
    try:
        r = await c.request(method, url, **kw)
        code = r.status_code
    except httpx.HTTPError:
        r, code = None, 599
    if st is not None:
        st.add(route, (time.perf_counter() - t) * 1000, code)
    return r


def hdr(token=None, idem=False):
    h = {"Authorization": f"Bearer {token or ADMIN}"}
    if idem:
        h["Idempotency-Key"] = str(uuid.uuid4())
    return h


async def enroll(c: httpx.AsyncClient, login: int, role: str) -> dict:
    a = (await c.post("/admin/accounts", json={"broker_server": SERVER, "login": login, "role": role},
                      headers=hdr())).json()
    code = (await c.post(f"/admin/accounts/{a['id']}/enroll_codes", headers=hdr())).json()["code"]
    r = await c.post("/v4/enroll", json={"code": code, "broker_server": SERVER, "login": login, "role": role,
                                         "margin_mode": "hedging", "ea_version": "1.0.0"},
                     headers={"Idempotency-Key": str(uuid.uuid4())})
    r.raise_for_status()
    a["token"], a["login"] = r.json()["token"], login
    r = await c.put("/v4/symbols", json={"symbols": [{"name": "EURUSD", **SPEC}]}, headers=hdr(a["token"], True))
    r.raise_for_status()
    r = await c.post("/v4/session", json={"boot_nonce": uuid.uuid4().hex, "taken_at": int(time.time() * 1000)},
                     headers=hdr(a["token"], True))
    r.raise_for_status()
    a["session"] = r.json()
    a["seq"] = 0
    return a


def snap_body(a: dict, positions: list, history: list) -> dict:
    a["seq"] += 1
    return {"session_id": a["session"]["session_id"], "epoch": a["session"]["epoch"], "seq": a["seq"],
            "taken_at": int(time.time() * 1000), "ea_clock_offset_ms": 0, "connected": True, "login": a["login"],
            "server": SERVER, "history_synced": True, "positions": positions, "pending": [], "history": history}


async def master_loop(c, st, m, stop, master_ms, trade_every):
    positions, history, next_pid, last_trade = [], [], 500_000, time.monotonic()
    while not stop.is_set():
        t0 = time.monotonic()
        if t0 - last_trade >= trade_every:
            last_trade = t0
            now = int(time.time() * 1000)
            if positions:
                p = positions.pop()
                history = [{"deal": next_pid * 10 + 1, "order": next_pid * 10 + 1, "position_id": p["position_id"],
                            "entry": "out", "reason": "client", "symbol": "EURUSD", "volume": 0.1, "price": 1.1,
                            "profit": 0, "commission": 0, "swap": 0, "magic": 0, "comment": "", "time_msc": now}]
            else:
                next_pid += 1
                positions.append({"position_ticket": next_pid, "position_id": next_pid, "symbol": "EURUSD",
                                  "type": "buy", "volume": 0.1, "price_open": 1.1, "sl": None, "tp": None,
                                  "magic": 0, "comment": "", "time_msc": now})
        await call(c, st, "master/snapshot", "POST", "/v4/master/snapshot",
                   json=snap_body(m, positions, history), headers=hdr(m["token"], True))
        await asyncio.sleep(max(0, master_ms / 1000 - (time.monotonic() - t0)))


async def slave_loop(c, st, a, stop, poll_ms):
    await asyncio.sleep(random.uniform(0, poll_ms / 1000))  # noqa: S311
    open_pos: dict[int, dict] = {}   # copy_id -> position
    pid = a["login"] * 1000
    last_snap = time.monotonic()
    while not stop.is_set():
        t0 = time.monotonic()
        r = await call(c, st, "slave/commands", "GET", "/v4/slave/commands", headers=hdr(a["token"]))
        cmds = r.json().get("commands", []) if r is not None and r.status_code == 200 else []
        results = []
        for cmd in cmds:
            if cmd["action"] == "open":
                pid += 1
                open_pos[cmd["copy_id"]] = {"position_ticket": pid, "position_id": pid, "symbol": "EURUSD",
                                            "type": cmd.get("side", "buy"), "volume": cmd.get("volume", 0.1),
                                            "price_open": 1.1, "sl": None, "tp": None, "magic": 0,
                                            "comment": cmd.get("comment", ""), "time_msc": int(time.time() * 1000)}
                results.append({"command_id": cmd["command_id"], "copy_id": cmd["copy_id"], "status": "done",
                                "position_id": pid, "position_ticket": pid, "price": 1.1,
                                "executed_volume": cmd.get("volume", 0.1), "executed_at": int(time.time() * 1000)})
            else:
                open_pos.pop(cmd["copy_id"], None)
                results.append({"command_id": cmd["command_id"], "copy_id": cmd["copy_id"], "status": "closed",
                                "price": 1.1, "executed_at": int(time.time() * 1000)})
        if results:
            await call(c, st, "slave/results", "POST", "/v4/slave/results", json={"results": results},
                       headers=hdr(a["token"], True))
        if time.monotonic() - last_snap >= 10:
            last_snap = time.monotonic()
            await call(c, st, "slave/snapshot", "POST", "/v4/slave/snapshot",
                       json=snap_body(a, list(open_pos.values()), []), headers=hdr(a["token"], True))
        await asyncio.sleep(max(0, poll_ms / 1000 - (time.monotonic() - t0)))


def pct(v: list[float], q: float) -> float:
    if not v:
        return 0.0
    v = sorted(v)
    return v[min(len(v) - 1, int(round(q * (len(v) - 1))))]


async def run(args) -> dict:
    env = {**os.environ, "ENV": "test", "DATABASE_URL": args.database_url, "ADMIN_TOKEN": ADMIN,
           "TOKEN_PEPPER": "load-pepper-0123456789", "POLL_MS": str(args.poll_ms)}
    here = Path(__file__).resolve().parents[1]
    subprocess.run([sys.executable, "-m", "alembic", "upgrade", "head"], cwd=here, env=env, check=True,
                   capture_output=True)
    log = open(args.server_log, "ab")  # noqa: SIM115
    srv = subprocess.Popen(  # noqa: S603
        [sys.executable, "-m", "uvicorn", "copycore.app:create_app", "--factory", "--host", "127.0.0.1",
         "--port", str(args.port), "--log-level",
         "warning"], cwd=here, env=env, stdout=subprocess.DEVNULL, stderr=log)
    base = f"http://127.0.0.1:{args.port}"
    try:
        limits = httpx.Limits(max_connections=args.slaves + 10, max_keepalive_connections=args.slaves + 10)
        async with httpx.AsyncClient(base_url=base, timeout=10, limits=limits) as c:
            for _ in range(100):
                try:
                    if (await c.get("/healthz")).status_code == 200:
                        break
                except httpx.HTTPError:
                    pass
                await asyncio.sleep(0.1)
            m = await enroll(c, 1, "master")
            g = (await c.post("/admin/groups", json={"master_id": m["id"], "name": "g"}, headers=hdr())).json()
            slaves = []
            for i in range(args.slaves):
                a = await enroll(c, 1000 + i, "slave")
                r = await c.post("/admin/links", json={"group_id": g["id"], "slave_id": a["id"], "lot_mode": "master"},
                                 headers=hdr())
                r.raise_for_status()
                slaves.append(a)
            st, stop = Stats(), asyncio.Event()
            pg_pids = tree_pids(args.pg_pid) if args.pg_pid else []
            cpu0 = cpu_seconds(srv.pid)
            pg0 = sum(cpu_seconds(p) for p in pg_pids)
            t0 = time.monotonic()
            tasks = [asyncio.create_task(master_loop(c, st, m, stop, args.master_ms, args.trade_every))]
            tasks += [asyncio.create_task(slave_loop(c, st, a, stop, args.poll_ms)) for a in slaves]
            await asyncio.sleep(args.duration)
            stop.set()
            await asyncio.gather(*tasks)
            wall = time.monotonic() - t0
            cpu = cpu_seconds(srv.pid) - cpu0
            pg_pids = tree_pids(args.pg_pid) if args.pg_pid else []
            pg = sum(cpu_seconds(p) for p in pg_pids) - pg0 if pg_pids else None
            copies = (await c.get("/admin/copies", headers=hdr())).json().get("copies", [])
    finally:
        srv.terminate()
        srv.wait(10)
        log.close()
    total = sum(len(v) for v in st.lat.values())
    allv = [x for v in st.lat.values() for x in v]
    non2xx = sum(n for codes in st.codes.values() for code, n in codes.items() if code >= 300)
    n503 = sum(codes.get(503, 0) for codes in st.codes.values())
    out = {"db": "postgres" if args.database_url.startswith("postgres") else "sqlite", "slaves": args.slaves,
           "poll_ms": args.poll_ms, "duration_s": round(wall, 1), "req_s": round(total / wall, 1),
           "p50_ms": round(statistics.median(allv), 1) if allv else None, "p99_ms": round(pct(allv, 0.99), 1),
           "non2xx": non2xx, "err_pct": round(100 * non2xx / max(total, 1), 2), "n503": n503,
           "server_cpu_pct": round(100 * cpu / wall, 1),
           "pg_cpu_pct": round(100 * pg / wall, 1) if pg is not None else None,
           "copies": len(copies), "routes": {}}
    for route, v in sorted(st.lat.items()):
        out["routes"][route] = {"n": len(v), "p50_ms": round(statistics.median(v), 1), "p99_ms": round(pct(v, 0.99), 1),
                                "codes": dict(st.codes[route])}
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--database-url", required=True, help="a THROWAWAY database (tables are created)")
    ap.add_argument("--slaves", type=int, default=20)
    ap.add_argument("--poll-ms", type=int, default=1000)
    ap.add_argument("--master-ms", type=int, default=1000)
    ap.add_argument("--trade-every", type=float, default=5.0)
    ap.add_argument("--duration", type=float, default=60)
    ap.add_argument("--port", type=int, default=18099)
    ap.add_argument("--pg-pid", type=int, default=0, help="postmaster pid: adds the cluster CPU to the report")
    ap.add_argument("--server-log", default=os.devnull)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    res = asyncio.run(run(args))
    if args.json:
        print(json.dumps(res))
        return
    print(f"{res['db']:8} slaves={res['slaves']:3} poll={res['poll_ms']:5}ms  {res['req_s']:6} req/s  "
          f"p50={res['p50_ms']}ms p99={res['p99_ms']}ms  non2xx={res['err_pct']}% 503={res['n503']}  "
          f"server_cpu={res['server_cpu_pct']}%"
          + (f" pg_cpu={res['pg_cpu_pct']}%" if res['pg_cpu_pct'] is not None else "") + f"  copies={res['copies']}")
    for r, v in res["routes"].items():
        print(f"   {r:16} n={v['n']:6} p50={v['p50_ms']}ms p99={v['p99_ms']}ms codes={v['codes']}")


if __name__ == "__main__":
    main()
