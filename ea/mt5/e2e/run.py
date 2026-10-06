#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx>=0.27"]
# ///
"""End-to-end tests for TradeMirror (master + slave EA) against a live Copy Server.

Topology (see ea/mt5/README.md, "End-to-end tests"):

    host runner --cmd files--> TradeMirrorE2EDriver (master terminal) --trades--> broker (demo)
                                TradeMirror master EA --snapshots--> Copy Server <--admin API-- host runner
                                TradeMirror slave EA  <--commands--- Copy Server
    host runner <--status.json-- TradeMirrorE2EDriver (slave terminal)

Each terminal runs in a podman container whose Wine prefix is bind-mounted on the host, so the
runner talks to the drivers through files in MQL5/Files/TradeMirrorE2E. The EA reaches the server
through a forwarder inside the container (127.0.0.1:8099 -> host); network cuts and the fault proxy
work by stopping or re-pointing that forwarder.

    uv run ea/mt5/e2e/run.py --list
    uv run ea/mt5/e2e/run.py                       # all scenarios
    uv run ea/mt5/e2e/run.py open_copy full_close  # by name (or prefix match with -k)

Exit code 0 when every selected scenario passed (skips do not fail the run), 1 otherwise,
2 when preconditions fail.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import signal
import subprocess
import sys
import time
import traceback
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

import httpx

REPO = Path(__file__).resolve().parents[3]
LAB = Path("/home/brenoperucchi/VMs/mt5-wine-lab")
EXPOSURE = {"pending", "open", "cancel_requested", "closing", "uncertain"}
FINAL = {"closed", "cancelled", "skipped", "error"}

FORWARDER_SRC = r'''
import asyncio, sys
PORT = int(sys.argv[1])
async def pipe(r, w):
    try:
        while (d := await r.read(65536)):
            w.write(d); await w.drain()
    finally:
        w.close()
async def handle(cr, cw):
    try:
        sr, sw = await asyncio.open_connection("{host}", PORT)
    except OSError:
        cw.close(); return
    await asyncio.gather(pipe(cr, sw), pipe(sr, cw), return_exceptions=True)
async def main():
    srv = await asyncio.start_server(handle, "127.0.0.1", 8099)
    async with srv: await srv.serve_forever()
asyncio.run(main())
'''


class Fail(AssertionError):
    pass


class Skip(Exception):
    pass


def log(msg: str) -> None:
    print(f"  {time.strftime('%H:%M:%S')} {msg}", flush=True)


def wait_for(what: str, fn: Callable[[], Any], timeout: float, interval: float = 1.0) -> Any:
    """Poll fn until it returns a truthy value; raise Fail with the last value on timeout."""
    deadline = time.monotonic() + timeout
    last: Any = None
    while True:
        try:
            last = fn()
        except (httpx.HTTPError, OSError, ValueError) as e:  # transient while servers restart
            last = f"{type(e).__name__}: {e}"
        else:
            if last:
                return last
        if time.monotonic() >= deadline:
            raise Fail(f"timeout after {timeout:.0f}s waiting for {what} (last: {str(last)[:300]})")
        time.sleep(interval)


def check(cond: bool, msg: str) -> None:
    if not cond:
        raise Fail(msg)


def sh(args: list[str], check_rc: bool = False, timeout: float = 60) -> subprocess.CompletedProcess:
    p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if check_rc and p.returncode != 0:
        raise RuntimeError(f"{shlex.join(args)} -> {p.returncode}: {p.stderr.strip()[:300]}")
    return p


# --- terminals --------------------------------------------------------------------------------

class Remote:
    """A host reached over ssh (one multiplexed connection, so each call costs one round trip)."""

    def __init__(self, target: str, control_dir: Path):
        control_dir.mkdir(parents=True, exist_ok=True)
        self.target = target
        self.opts = ["-o", "ControlMaster=auto", "-o", f"ControlPath={control_dir}/cm-%C", "-o", "ControlPersist=15m",
                     "-o", "BatchMode=yes", "-o", "ServerAliveInterval=15"]

    def run(self, script: str, stdin: str | None = None, timeout: float = 30) -> subprocess.CompletedProcess:
        return subprocess.run(["ssh", *self.opts, self.target, script], input=stdin, capture_output=True, text=True,
                              timeout=timeout)

    def must(self, script: str, stdin: str | None = None) -> str:
        p = self.run(script, stdin)
        if p.returncode != 0:
            raise RuntimeError(f"ssh {self.target} {script[:80]!r} -> {p.returncode}: {p.stderr.strip()[:300]}")
        return p.stdout


class LocalFiles:
    """Driver directory on this host (bind-mounted Wine prefix)."""

    def __init__(self, root: Path):
        self.root = root

    def __str__(self) -> str:
        return str(self.root)

    def read(self, rel: str) -> str | None:
        try:
            return (self.root / rel).read_text(encoding="utf-8")
        except FileNotFoundError:
            return None

    def age(self, rel: str) -> float:
        return time.time() - (self.root / rel).stat().st_mtime

    def write_atomic(self, rel: str, text: str) -> None:
        dst = self.root / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        tmp = dst.parent / f".{dst.name}.tmp"
        tmp.write_text(text, encoding="utf-8")
        os.replace(tmp, dst)

    def take(self, rel: str) -> str | None:
        """Read and delete (ack files)."""
        t = self.read(rel)
        if t is not None:
            (self.root / rel).unlink(missing_ok=True)
        return t

    def unlink(self, rel: str) -> None:
        (self.root / rel).unlink(missing_ok=True)


class RemoteFiles(LocalFiles):
    """Driver directory on a remote host, over ssh: writes are tmp + mv in the same directory (atomic for the
    driver's FileFindFirst, which skips dot files); ages use the remote clock."""

    def __init__(self, remote: Remote, root: str):
        self.remote, self.root_s = remote, root.rstrip("/")
        self.root = Path(root)

    def __str__(self) -> str:
        return f"{self.remote.target}:{self.root_s}"

    def _p(self, rel: str) -> str:
        return shlex.quote(f"{self.root_s}/{rel}")

    def read(self, rel: str) -> str | None:
        p = self.remote.run(f"cat {self._p(rel)} 2>/dev/null")
        return p.stdout if p.returncode == 0 else None

    def age(self, rel: str) -> float:
        p = self.remote.run(f"echo $(date +%s.%N) $(stat -c %Y {self._p(rel)})")
        f = p.stdout.split()
        if p.returncode != 0 or len(f) != 2:
            raise OSError(f"stat {self}/{rel} failed: {p.stderr.strip()[:200]}")
        return float(f[0]) - float(f[1])

    def write_atomic(self, rel: str, text: str) -> None:
        d, name = (rel.rsplit("/", 1) if "/" in rel else ("", rel))
        dq = shlex.quote(f"{self.root_s}/{d}".rstrip("/"))
        tmp = shlex.quote(f".{name}.tmp")
        self.remote.must(f"mkdir -p {dq} && cd {dq} && cat > {tmp} && mv -f {tmp} {shlex.quote(name)}", stdin=text)

    def take(self, rel: str) -> str | None:
        p = self.remote.run(f"cat {self._p(rel)} 2>/dev/null && rm -f {self._p(rel)}")
        return p.stdout if p.returncode == 0 and p.stdout else None

    def unlink(self, rel: str) -> None:
        self.remote.run(f"rm -f {self._p(rel)}")


@dataclass
class Terminal:
    role: str
    container: str
    prefix: Path          # host path of the Wine prefix (bind-mounted at /home/mt5/.mt5)
    terminal_dir: str     # drive_c/<terminal_dir>
    forward_host: str     # host address the in-container forwarder connects to
    seq: int = 0
    remote: Remote | None = None       # master on another host: driver files and docker over ssh
    remote_files: str | None = None    # driver directory on that host (…/MQL5/Files/TradeMirrorE2E)
    _io: LocalFiles | None = None

    @property
    def files(self) -> LocalFiles:
        if self._io is None:
            if self.remote:
                self._io = RemoteFiles(self.remote, self.remote_files or "")
            else:
                self._io = LocalFiles(self.prefix / "drive_c" / self.terminal_dir / "MQL5" / "Files" / "TradeMirrorE2E")
        return self._io

    # driver protocol ------------------------------------------------------------------------
    def status(self) -> dict:
        t = self.files.read("status.json")
        if t is None:
            raise OSError(f"no status.json in {self.files}")
        return json.loads(t)

    def status_age(self) -> float:
        return self.files.age("status.json")

    def alive(self, max_age: float = 5.0) -> bool:
        try:
            return self.status_age() < max_age
        except OSError:
            return False

    def send(self, op: str, timeout: float = 30, **kw: Any) -> dict:
        """Write one command file atomically and wait for its ack."""
        self.seq += 1
        cid = f"{time.time_ns():020d}-{self.seq:04d}-{uuid.uuid4().hex[:6]}"
        self.files.write_atomic(f"cmd/{cid}.json", json.dumps({"id": cid, "op": op, **kw}))

        def ack() -> dict | None:
            t = self.files.take(f"ack/{cid}.json")
            return json.loads(t) if t else None

        try:
            a = wait_for(f"{self.role} driver ack of {op}", ack, timeout, 0.2)
        except Fail:
            self.files.unlink(f"cmd/{cid}.json")   # never let a late command trade later
            raise
        log(f"{self.role}: {op} {kw} -> {'ok' if a.get('ok') else 'FAILED'} {a.get('retcode_text') or a.get('error') or ''}")
        return a

    def must(self, op: str, **kw: Any) -> dict:
        a = self.send(op, **kw)
        check(bool(a.get("ok")), f"{self.role} {op} failed: {a}")
        return a

    def positions(self, **match: Any) -> list[dict]:
        out = []
        for p in self.status()["positions"]:
            if all(p.get(k) == v for k, v in match.items()):
                out.append(p)
        return out

    def fresh_status(self) -> dict:
        """A status.json written after this call (so it reflects broker state from now)."""
        beat = self.status()["beat"]
        return wait_for(f"{self.role} fresh status", lambda: (s := self.status())["beat"] > beat and s, 10, 0.2)

    # container / process control --------------------------------------------------------------
    def podman(self, *args: str, check_rc: bool = False) -> subprocess.CompletedProcess:
        if self.remote:   # docker on the remote host; only read-only inspection is used there
            p = self.remote.run(shlex.join(["docker", *args]))
            if check_rc and p.returncode != 0:
                raise RuntimeError(f"remote docker {args} -> {p.returncode}: {p.stderr.strip()[:300]}")
            return p
        return sh(["podman", *args], check_rc=check_rc)

    def state(self) -> str:
        return self.podman("inspect", self.container, "--format", "{{.State.Status}}").stdout.strip()

    def forwarder_running(self) -> bool:
        if self.remote:
            return True   # a remote terminal talks to the server directly (no forwarder to cut)
        return self.podman("exec", self.container, "pgrep", "-f", "forward").returncode == 0

    def stop_forwarder(self) -> None:
        if self.remote:
            raise Skip(f"{self.role} is remote ({self.remote.target}): network cuts are not supported")
        self.podman("exec", self.container, "pkill", "-f", "tm_forward.py")
        self.podman("exec", self.container, "pkill", "-f", "tm_e2e_forward")
        wait_for(f"{self.role} forwarder stopped", lambda: not self.forwarder_running(), 10, 0.5)

    def start_forwarder(self, port: int | None = None) -> None:
        """Default forwarder (tm_forward.py -> host:8099) or, with a port, one to host:<port>."""
        if self.forwarder_running():
            self.stop_forwarder()
        if port is None:
            self.podman("exec", "-d", self.container, "python3", "/home/mt5/.mt5/tm_forward.py", check_rc=True)
        else:
            src = FORWARDER_SRC.replace("{host}", self.forward_host)
            self.podman("exec", "-d", self.container, "python3", "-c", src, str(port), "tm_e2e_forward",
                        check_rc=True)
        wait_for(f"{self.role} forwarder started", self.forwarder_running, 10, 0.5)

    def kill_terminal(self) -> None:
        if self.remote:
            raise Skip(f"{self.role} is remote ({self.remote.target}): terminal restarts are not supported")
        """Hard-kill terminal64 (no profile save, no OnDeinit): the container's main process exits."""
        self.podman("exec", self.container, "pkill", "-9", "-f", "terminal64.exe")
        try:
            wait_for(f"{self.container} exited", lambda: self.state() in ("exited", "stopped"), 20, 0.5)
        except Fail:
            self.podman("stop", "-t", "5", self.container)

    def start_terminal(self) -> None:
        if self.state() != "running":
            self.podman("start", self.container, check_rc=True)
        started = time.time()
        wait_for(f"{self.container} terminal64 running",
                 lambda: self.podman("exec", self.container, "pgrep", "-f", "terminal64.exe").returncode == 0, 60)
        self.start_forwarder()
        wait_for(f"{self.role} driver writing status again",
                 lambda: self.status_age() < time.time() - started - 1 and self.alive(), 120)


# --- server ------------------------------------------------------------------------------------

class Admin:
    def __init__(self, url: str, token: str):
        self.url = url.rstrip("/")
        self.http = httpx.Client(base_url=self.url, headers={"Authorization": f"Bearer {token}"}, timeout=10)

    def get(self, path: str, **params: Any) -> dict:
        r = self.http.get(path, params={k: v for k, v in params.items() if v is not None})
        r.raise_for_status()
        return r.json()

    def health(self) -> bool:
        try:
            return httpx.get(f"{self.url}/health", timeout=3).status_code == 200
        except httpx.HTTPError:
            return False

    def copies(self, **params: Any) -> list[dict]:
        return self.get("/admin/copies", **params)["copies"]

    def commands(self, **params: Any) -> list[dict]:
        return self.get("/admin/commands", **params)["commands"]

    def events(self, **params: Any) -> list[dict]:
        return self.get("/admin/events", **params)["events"]

    def orphans(self) -> dict:
        return self.get("/admin/orphans")


# --- context -------------------------------------------------------------------------------------

@dataclass
class Ctx:
    args: argparse.Namespace
    admin: Admin
    master: Terminal
    slave: Terminal
    link_id: int
    slave_id: int
    master_id: int
    timeout: float
    notes: list[str] = field(default_factory=list)
    copy_floor: int = 0     # newest copy id before this scenario
    copies_before: set[int] = field(default_factory=set)  # ids that belong to earlier scenarios (the id
    # sequence may be rewound to reproduce a c<id> collision, so "newer" is not "bigger id")
    event_floor: int = 0

    def note(self, msg: str) -> None:
        self.notes.append(msg)
        log(msg)

    # baseline ---------------------------------------------------------------------------------
    def mark(self) -> None:
        cs = self.admin.copies(link_id=self.link_id, limit=1)
        self.copy_floor = cs[0]["id"] if cs else 0
        self.copies_before = {c["id"] for c in self.admin.copies(link_id=self.link_id, limit=500)}
        ev = self.admin.events(limit=1)
        self.event_floor = ev[0]["id"] if ev else 0

    def new_copies(self, symbol: str | None = None) -> list[dict]:
        cs = [c for c in self.admin.copies(link_id=self.link_id) if c["id"] not in self.copies_before]
        if symbol:
            cs = [c for c in cs if c["symbol_master"] == symbol]
        return sorted(cs, key=lambda c: c["id"])

    def new_events(self) -> list[dict]:
        return [e for e in self.admin.events(limit=500) if e["id"] > self.event_floor]

    # composite helpers ----------------------------------------------------------------------------
    def master_open(self, symbol: str, side: str, volume: float, tag: str, **kw: Any) -> dict:
        return self.master.must("open", symbol=symbol, side=side, volume=volume, magic=self.args.magic,
                                comment=f"e2e-{tag}"[:31], **kw)

    def wait_copy(self, symbol: str, states: set[str], timeout: float | None = None, n: int = 1) -> list[dict]:
        """Wait until n new copies for symbol exist and all are in one of states."""
        def ok():
            cs = self.new_copies(symbol)
            return cs if len(cs) >= n and all(c["state"] in states for c in cs[:n]) else None
        return wait_for(f"{n} copy({symbol}) in {sorted(states)}", ok, timeout or self.timeout)

    def slave_pos(self, copy_id: int) -> list[dict]:
        return [p for p in self.slave.status()["positions"] if is_copy_comment(p.get("comment"), copy_id)]

    def wait_slave_pos(self, copy_id: int, pred: Callable[[dict], bool] = lambda p: True,
                       what: str = "", timeout: float | None = None) -> dict:
        def ok():
            ps = self.slave_pos(copy_id)
            return ps[0] if len(ps) == 1 and pred(ps[0]) else None
        return wait_for(f"slave position c{copy_id} {what}".strip(), ok, timeout or self.timeout)

    def wait_slave_gone(self, copy_id: int, timeout: float | None = None) -> None:
        wait_for(f"slave position c{copy_id} closed", lambda: not self.slave_pos(copy_id), timeout or self.timeout)

    def wait_copy_state(self, copy_id: int, states: set[str], timeout: float | None = None) -> dict:
        def ok():
            c = next((c for c in self.admin.copies(link_id=self.link_id) if c["id"] == copy_id), None)
            return c if c and c["state"] in states else None
        return wait_for(f"copy {copy_id} in {sorted(states)}", ok, timeout or self.timeout)

    def slave_in_deals(self, copy: dict) -> list[dict]:
        """Entry deals of this copy: its exact frozen comment, so an older c<id>-<other master id> deal left in
        the slave history (another Copy Server, a reset sequence) is not counted."""
        want = (copy.get("exec_params") or {}).get("comment")
        return [d for d in self.slave.status()["deals"] if d["entry"] == "in" and
                (d["comment"] == want if want else is_copy_comment(d["comment"], copy["id"]))]

    def assert_no_new_orphans(self) -> None:
        o = self.admin.orphans()
        bad = [(k, c["id"], c["state"]) for k in ("uncertain", "close_unconfirmed", "revoked_exposure")
               for c in o.get(k, []) if c.get("link_id") == self.link_id and c["id"] not in self.copies_before]
        check(not bad, f"orphan copies after scenario: {bad}")

    def cleanup(self) -> None:
        """Flatten both accounts and wait until the link holds no exposure. With --cleanup-magic-only only
        positions/copies carrying --magic count (a shared master where someone may trade by hand)."""
        mo = self.args.cleanup_magic_only
        flt: dict[str, Any] = {"magic": self.args.magic} if mo else {}

        def mine(ps: list[dict]) -> list[dict]:
            return [p for p in ps if not mo or p.get("magic") == self.args.magic]

        # Master first and give the copier a chance to close its own copies; only then flatten the
        # slave by hand (that also removes manual positions and anything a failed scenario left).
        if self.master.alive(15) and mine(self.master.status()["positions"]):
            self.master.send("close_all", **flt)
        try:
            wait_for("slave flat via the copier", lambda: not mine(self.slave.fresh_status()["positions"]), 20, 1)
        except Fail:
            if self.slave.alive(15) and mine(self.slave.status()["positions"]):
                self.slave.send("close_all", **flt)
        for t in (self.master, self.slave):
            wait_for(f"{t.role} flat", lambda t=t: not mine(t.fresh_status()["positions"]), 60, 1)

        def mine_copy(c: dict) -> bool:
            return not mo or str((c.get("exec_params") or {}).get("magic")) == str(self.args.magic)
        wait_for("no exposure on the link",
                 lambda: not [c for c in self.admin.copies(link_id=self.link_id, limit=50) if mine_copy(c) and
                              (c["state"] in EXPOSURE or (c["state"] == "superseded" and c["close_intent"]))],
                 90, 2)


# --- scenarios -------------------------------------------------------------------------------------

@dataclass
class Scenario:
    name: str
    fn: Callable[[Ctx], None]
    doc: str
    slow: bool = False


SCENARIOS: list[Scenario] = []


def scenario(slow: bool = False):
    def deco(fn: Callable[[Ctx], None]):
        SCENARIOS.append(Scenario(fn.__name__.removeprefix("s_"), fn, (fn.__doc__ or "").strip(), slow))
        return fn
    return deco


def is_copy_comment(comment: str | None, copy_id: int) -> bool:
    """Slave comment of copy `copy_id`: `c<copy_id>-<master position id>` (or legacy `c<copy_id>`)."""
    return comment == f"c{copy_id}" or (comment or "").startswith(f"c{copy_id}-")


def open_and_mirror(ctx: Ctx, symbol: str, side: str, volume: float, tag: str, **kw: Any) -> tuple[dict, dict]:
    ctx.master_open(symbol, side, volume, tag, **kw)
    copy = ctx.wait_copy(symbol, {"open"})[0]
    pos = ctx.wait_slave_pos(copy["id"])
    check(pos["symbol"] == copy["symbol_local"], f"slave symbol {pos['symbol']} != {copy['symbol_local']}")
    check(pos["side"] == side, f"slave side {pos['side']} != {side}")
    check(abs(pos["volume"] - volume) < 1e-9, f"slave volume {pos['volume']} != {volume}")
    check(pos["magic"] == ctx.args.magic, f"slave magic {pos['magic']} != {ctx.args.magic} (magic_mode same)")
    check(str(copy["position_id"]) == str(pos["identifier"]),
          f"copy position_id {copy['position_id']} != slave identifier {pos['identifier']}")
    mps = ctx.master.positions(comment=f"e2e-{tag}"[:31], symbol=symbol)
    check(len(mps) == 1, f"expected one master position e2e-{tag} on {symbol}, got {len(mps)}")
    want = f"c{copy['id']}-{mps[0]['identifier']}"
    check(pos["comment"] == want, f"slave comment {pos['comment']!r} != {want!r} (c<copy_id>-<master position_id>)")
    return copy, pos


def close_and_mirror(ctx: Ctx, copy: dict, master_symbol: str) -> None:
    ctx.master.must("close", ticket=_master_ticket(ctx, master_symbol))
    ctx.wait_slave_gone(copy["id"])
    c = ctx.wait_copy_state(copy["id"], {"closed"})
    check(c["close_reason"] == "master_closed", f"close_reason {c['close_reason']} != master_closed")


def _master_ticket(ctx: Ctx, symbol: str) -> int:
    ps = [p for p in ctx.master.fresh_status()["positions"] if p["symbol"] == symbol and p["magic"] == ctx.args.magic]
    check(len(ps) == 1, f"expected one master position on {symbol}, got {len(ps)}")
    return ps[0]["ticket"]


@scenario()
def s_open_copy(ctx: Ctx) -> None:
    """Master opens BUY 0.01: copy becomes open, slave holds one position c<id> with same side/volume/magic."""
    copy, pos = open_and_mirror(ctx, ctx.args.symbol, "buy", 0.01, "open")
    check(len(ctx.slave_in_deals(copy)) == 1, "slave must have exactly one entry deal")


@scenario()
def s_full_close(ctx: Ctx) -> None:
    """Master closes: slave position closes and the copy ends closed/master_closed."""
    copy, _ = open_and_mirror(ctx, ctx.args.symbol, "buy", 0.01, "close")
    close_and_mirror(ctx, copy, ctx.args.symbol)


@scenario()
def s_sell_side(ctx: Ctx) -> None:
    """SELL is mirrored as SELL and its close propagates."""
    copy, _ = open_and_mirror(ctx, ctx.args.symbol, "sell", 0.01, "sell")
    close_and_mirror(ctx, copy, ctx.args.symbol)


@scenario()
def s_sltp_modify(ctx: Ctx) -> None:
    """SL/TP set at open and modified later on the master are mirrored on the slave (copy_sl_tp)."""
    sym = ctx.args.symbol
    copy, pos = open_and_mirror(ctx, sym, "buy", 0.01, "sltp")
    px = pos["price_open"]
    digits = 3 if px > 20 else 5
    pip = 0.01 if digits == 3 else 0.0001
    for k, (sl, tp) in enumerate([(px - 80 * pip, px + 80 * pip), (px - 50 * pip, px + 120 * pip)]):
        sl, tp = round(sl, digits), round(tp, digits)
        ctx.master.must("modify", ticket=_master_ticket(ctx, sym), sl=sl, tp=tp)
        ctx.wait_slave_pos(copy["id"], lambda p, sl=sl, tp=tp: abs(p["sl"] - sl) < pip / 10 and abs(p["tp"] - tp) < pip / 10,
                           f"with sl={sl} tp={tp} (step {k + 1})")
    close_and_mirror(ctx, copy, sym)


@scenario()
def s_partial_close(ctx: Ctx) -> None:
    """Master 0.03 -> partial 0.01 -> partial 0.01 -> close: slave volume follows, copy stays open, then closed."""
    sym = ctx.args.symbol
    copy, _ = open_and_mirror(ctx, sym, "buy", 0.03, "partial")
    for left in (0.02, 0.01):
        ctx.master.must("close_partial", ticket=_master_ticket(ctx, sym), volume=0.01)
        ctx.wait_slave_pos(copy["id"], lambda p, left=left: abs(p["volume"] - left) < 1e-9, f"volume {left}")
        ctx.wait_copy_state(copy["id"], {"open"})
    close_and_mirror(ctx, copy, sym)


@scenario()
def s_multi_symbol(ctx: Ctx) -> None:
    """Three symbols at once (buy/sell mix): three copies, three slave positions; close-all closes every copy."""
    legs = [(s, "buy" if i % 2 == 0 else "sell") for i, s in enumerate(ctx.args.symbols)]
    for s, side in legs:
        ctx.master_open(s, side, 0.01, f"multi-{s}")
    copies = {}
    for s, side in legs:
        c = ctx.wait_copy(s, {"open"})[0]
        p = ctx.wait_slave_pos(c["id"])
        check(p["side"] == side and p["symbol"] == c["symbol_local"], f"{s}: slave {p['side']} {p['symbol']}")
        copies[s] = c
    ctx.master.must("close_all", magic=ctx.args.magic)
    for s, c in copies.items():
        ctx.wait_slave_gone(c["id"])
        ctx.wait_copy_state(c["id"], {"closed"})


@scenario()
def s_manual_untouched(ctx: Ctx) -> None:
    """A manual position on the slave (other magic, no c<id> comment) survives a full copy cycle."""
    sym = ctx.args.symbols[1] if len(ctx.args.symbols) > 1 else ctx.args.symbol
    ctx.slave.must("open", symbol=sym, side="buy", volume=0.01, magic=777001, comment="manual-e2e")
    manual = wait_for("manual position on slave", lambda: ctx.slave.positions(comment="manual-e2e"), 15)[0]
    copy, _ = open_and_mirror(ctx, sym, "sell", 0.01, "manual")
    close_and_mirror(ctx, copy, sym)
    time.sleep(5)
    still = ctx.slave.fresh_status() and ctx.slave.positions(comment="manual-e2e")
    check(len(still) == 1 and still[0]["ticket"] == manual["ticket"] and still[0]["volume"] == manual["volume"],
          f"manual slave position was touched: before {manual}, after {still}")
    bad = [c for c in ctx.new_copies() if str(c.get("position_id")) == str(manual["identifier"])]
    check(not bad, f"server adopted the manual position as a copy: {bad}")


@scenario(slow=True)
def s_slave_restart_mid_open(ctx: Ctx) -> None:
    """Slave terminal is hard-killed right after an open is delivered; after restart there is exactly one
    position for the copy (journal/evidence prevent a duplicate) and the close still propagates."""
    sym = ctx.args.symbol
    ctx.master_open(sym, "buy", 0.01, "restart")
    copy = ctx.wait_copy(sym, EXPOSURE | {"open"}, timeout=30)[0]

    def delivered():
        cmds = [c for c in ctx.admin.commands(copy_id=copy["id"]) if c["action"] == "open"]
        return cmds and cmds[0]["state"] in ("delivered", "in_progress", "done")
    wait_for("open command delivered", delivered, 30, 0.2)
    ctx.slave.kill_terminal()
    ctx.note(f"slave killed with copy {copy['id']} {ctx.wait_copy_state(copy['id'], EXPOSURE | FINAL, 5)['state']}")
    ctx.slave.start_terminal()
    ctx.wait_copy_state(copy["id"], {"open"}, timeout=120)
    ctx.wait_slave_pos(copy["id"], timeout=60)
    time.sleep(15)   # give a duplicate the chance to appear
    ps = ctx.slave.fresh_status() and ctx.slave_pos(copy["id"])
    check(len(ps) == 1, f"expected 1 slave position for c{copy['id']} after restart, got {len(ps)}")
    check(len(ctx.slave_in_deals(copy)) == 1, f"duplicate entry deals for c{copy['id']}: {ctx.slave_in_deals(copy)}")
    close_and_mirror(ctx, copy, sym)


@scenario(slow=True)
def s_slave_restart_while_open(ctx: Ctx) -> None:
    """Slave terminal restarts while a copy is open: no second position, no orphan, close still works."""
    sym = ctx.args.symbol
    copy, _ = open_and_mirror(ctx, sym, "buy", 0.01, "restart2")
    ctx.slave.kill_terminal()
    ctx.slave.start_terminal()
    time.sleep(20)
    ps = ctx.slave.fresh_status() and ctx.slave_pos(copy["id"])
    check(len(ps) == 1, f"expected 1 slave position after restart, got {len(ps)}")
    ctx.wait_copy_state(copy["id"], {"open"}, 10)
    close_and_mirror(ctx, copy, sym)


@scenario(slow=True)
def s_network_cut_during_close(ctx: Ctx) -> None:
    """Slave loses the server (forwarder stopped) while the master closes: the slave keeps the position during
    the cut and closes it when the link returns; copy ends closed."""
    sym = ctx.args.symbol
    copy, _ = open_and_mirror(ctx, sym, "buy", 0.01, "netcut")
    ctx.slave.stop_forwarder()
    try:
        ctx.master.must("close", ticket=_master_ticket(ctx, sym))
        ctx.wait_copy_state(copy["id"], {"closing"}, 30)
        t_end = time.monotonic() + ctx.args.cut_seconds
        while time.monotonic() < t_end:
            check(len(ctx.slave_pos(copy["id"])) == 1, "slave closed without a server link (unexpected)")
            time.sleep(2)
    finally:
        ctx.slave.start_forwarder()
    ctx.wait_slave_gone(copy["id"], timeout=120)
    ctx.wait_copy_state(copy["id"], {"closed"}, 120)


@scenario(slow=True)
def s_network_cut_during_open(ctx: Ctx) -> None:
    """Slave link is down when the master opens: nothing is executed during the cut (or the open expires);
    after the link returns there is at most one position, the copy settles, and the close propagates."""
    sym = ctx.args.symbol
    ctx.slave.stop_forwarder()
    try:
        ctx.master_open(sym, "buy", 0.01, "netcut-open")
        copy = ctx.wait_copy(sym, EXPOSURE | FINAL, 30)[0]
        time.sleep(ctx.args.cut_seconds)
    finally:
        ctx.slave.start_forwarder()
    c = ctx.wait_copy_state(copy["id"], {"open", "cancelled", "error", "skipped", "closed"}, 120)
    ctx.note(f"copy {copy['id']} after cut: {c['state']} {c.get('skip_reason') or ''}")
    if c["state"] == "open":
        ctx.wait_slave_pos(copy["id"])
        close_and_mirror(ctx, copy, sym)
    else:
        check(not ctx.slave_pos(copy["id"]), f"copy {c['state']} but slave holds a position")


@scenario(slow=True)
def s_server_restart(ctx: Ctx) -> None:
    """Copy Server restarts while a copy is open: both EAs reconnect, the copy stays open, close propagates."""
    if not ctx.args.server_restart_cmd:
        raise Skip("no --server-restart-cmd / E2E_SERVER_RESTART_CMD configured")
    sym = ctx.args.symbol
    copy, _ = open_and_mirror(ctx, sym, "buy", 0.01, "srvrestart")
    restart_server(ctx)
    ctx.wait_copy_state(copy["id"], {"open"}, 30)
    time.sleep(10)
    close_and_mirror(ctx, copy, sym)


def restart_server(ctx: Ctx) -> None:
    pat = ctx.args.server_match
    pids = sh(["pgrep", "-f", pat]).stdout.split()
    check(bool(pids), f"no server process matching {pat!r}")
    for pid in pids:
        os.kill(int(pid), signal.SIGTERM)
    wait_for("server down", lambda: not ctx.admin.health(), 30, 0.5)
    ctx.note(f"server stopped (pids {pids}); restarting")
    subprocess.Popen(["bash", "-c", ctx.args.server_restart_cmd], start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_for("server healthy", ctx.admin.health, 60, 1)


class Proxy:
    """fault_proxy.py on the host, with the slave forwarder pointed at it."""

    def __init__(self, ctx: Ctx, *fault_args: str):
        self.ctx, self.fault_args = ctx, list(fault_args)
        self.proc: subprocess.Popen | None = None
        self.out = ctx.args.out_dir / f"proxy-{int(time.time())}.log"

    def __enter__(self) -> "Proxy":
        a = self.ctx.args
        cmd = ["uv", "run", "-q", "--project", str(a.server_project), "python",
               str(REPO / "ea/mt5/tests/fault_proxy.py"), "--upstream", a.server_url,
               "--host", a.proxy_host, "--port", str(a.proxy_port), *self.fault_args]
        self.fh = self.out.open("w")
        self.proc = subprocess.Popen(cmd, stdout=self.fh, stderr=subprocess.STDOUT, start_new_session=True)
        wait_for("fault proxy listening", lambda: _port_open(a.proxy_host, a.proxy_port), 60, 0.5)
        self.ctx.slave.start_forwarder(a.proxy_port)
        log(f"slave -> proxy {' '.join(self.fault_args)}")
        return self

    def __exit__(self, *exc: Any) -> None:
        try:
            self.ctx.slave.start_forwarder()
        finally:
            if self.proc:
                os.killpg(self.proc.pid, signal.SIGINT)
                try:
                    self.proc.wait(10)
                except subprocess.TimeoutExpired:
                    os.killpg(self.proc.pid, signal.SIGKILL)
            self.fh.close()
            text = self.out.read_text(errors="replace")
            viol = [line for line in text.splitlines() if "violation" in line.lower() and "0 contract" not in line]
            if viol:
                self.ctx.note(f"proxy reported contract violations ({self.out}): {viol[:3]}")

    def violations(self) -> list[str]:
        return [line for line in self.out.read_text(errors="replace").splitlines()
                if "violation" in line.lower() and "0 contract" not in line]


def _port_open(host: str, port: int) -> bool:
    import socket
    with socket.socket() as s:
        s.settimeout(0.5)
        return s.connect_ex((host, port)) == 0


@scenario(slow=True)
def s_fault_drop_results(ctx: Ctx) -> None:
    """S01 live: the first slave results reply is lost (proxy --drop-results 1). One position only, copy open,
    outbox drains (copy reaches open from the retried result); no proxy contract violations."""
    sym = ctx.args.symbol
    with Proxy(ctx, "--drop-results", "1") as px:
        copy, _ = open_and_mirror(ctx, sym, "buy", 0.01, "dropres")
        time.sleep(10)
        check(len(ctx.slave_pos(copy["id"])) == 1, "duplicate slave position after a lost result")
        check(len(ctx.slave_in_deals(copy)) == 1, "duplicate entry deal after a lost result")
        close_and_mirror(ctx, copy, sym)
        v = px.violations()
    check(not v, f"proxy contract violations: {v[:3]}")


@scenario(slow=True)
def s_fault_rate_limit_results(ctx: Ctx) -> None:
    """S24 live: /v4/slave/results answers 429 Retry-After 3600. The slave still polls and executes (position
    appears); the copy opens through the snapshot or, once the proxy is removed the results arrive and the copy opens."""
    sym = ctx.args.symbol
    with Proxy(ctx, "--rate-limit", "/v4/slave/results=3600"):
        ctx.master_open(sym, "buy", 0.01, "ratelimit")
        copy = ctx.wait_copy(sym, EXPOSURE, 30)[0]
        ctx.wait_slave_pos(copy["id"], timeout=60)
        time.sleep(8)
        c = ctx.wait_copy_state(copy["id"], EXPOSURE | FINAL, 5)
        ctx.note(f"copy {copy['id']} while results are rate-limited: {c['state']}")
        # The copy may still become open through the slave snapshot (adoption by comment, 5.8) even
        # though no result got through; both are valid. What must hold is one position, no duplicate.
        check(c["state"] in ("pending", "open"), f"unexpected copy state while results are 429: {c['state']}")
    # The EA honours Retry-After per route; the result only flows once that delay expires or the EA reloads.
    try:
        ctx.wait_copy_state(copy["id"], {"open"}, ctx.args.rate_limit_wait)
    except Fail:
        ctx.note("result still held by Retry-After; reloading the slave terminal to clear it")
        ctx.slave.kill_terminal()
        ctx.slave.start_terminal()
        ctx.wait_copy_state(copy["id"], {"open"}, 120)
    check(len(ctx.slave_pos(copy["id"])) == 1, "duplicate slave position after the rate-limit window")
    close_and_mirror(ctx, copy, sym)


@scenario(slow=True)
def s_fault_server_down(ctx: Ctx) -> None:
    """Server answers 503 to the slave for 45 s (proxy --fail-all-for) while the master opens: the open is
    executed once the server comes back, never twice."""
    sym = ctx.args.symbol
    with Proxy(ctx, "--fail-all-for", "45"):
        ctx.master_open(sym, "buy", 0.01, "srvdown")
        copy = ctx.wait_copy(sym, EXPOSURE | FINAL, 30)[0]
        c = ctx.wait_copy_state(copy["id"], {"open", "cancelled", "error", "skipped"}, 150)
    ctx.note(f"copy {copy['id']} after 503 window: {c['state']}")
    if c["state"] == "open":
        check(len(ctx.slave_pos(copy["id"])) == 1, "expected exactly one slave position")
        close_and_mirror(ctx, copy, sym)
    else:
        check(not ctx.slave_pos(copy["id"]), f"copy {c['state']} but slave holds a position")


# --- latency ---------------------------------------------------------------------------------------

def _pctl(v: list[float], q: float) -> float:
    v = sorted(v)
    return v[min(len(v) - 1, max(0, int(round(q * (len(v) - 1)))))]


def _deal(t: Terminal, position_id: Any, entry: str, timeout: float) -> dict:
    def find():
        for d in t.fresh_status()["deals"]:
            if str(d["position_id"]) == str(position_id) and d["entry"] == entry:
                return d
        return None
    return wait_for(f"{t.role} {entry} deal of position {position_id}", find, timeout, 0.5)


def read_trace(path: Path, since_ms: int, until_ms: int) -> dict[str, list[tuple[int, str]]]:
    """Server access trace (ACCESS_TRACE_PATH): `start_ms account method path status dur_ms` per /v4 call."""
    out: dict[str, list[tuple[int, str]]] = {}
    for line in path.read_text().splitlines():
        f = line.split("\t")
        if len(f) < 4 or not f[0].isdigit():
            continue
        t = int(f[0])
        if since_ms <= t <= until_ms and f[1] != "-":
            out.setdefault(f[1], []).append((t, f[3].split("?")[0]))
    return out


def check_trace(ctx: Ctx, since_ms: int, until_ms: int) -> dict:
    """Per account: calls/min and the smallest gap between two calls (asserted >= --min-gap-ms - tolerance)."""
    a = ctx.args
    if a.remote_access_trace:
        host, container, path = a.remote_access_trace.split(":", 2)
        p = subprocess.run(["ssh", "-o", "BatchMode=yes", host, shlex.join(["docker", "exec", container, "cat", path])],
                           capture_output=True, text=True, timeout=60)
        if p.returncode == 0:
            a.access_trace = str(a.out_dir / "access-remote.tsv")
            Path(a.access_trace).write_text(p.stdout)
        else:
            ctx.note(f"remote access trace not readable: {p.stderr.strip()[:200]}")
    if not a.access_trace or not Path(a.access_trace).exists():
        ctx.note("no --access-trace file: calls/min and min-gap not checked")
        return {}
    res = {}
    minutes = max((until_ms - since_ms) / 60000, 1e-9)
    for acct, calls in sorted(read_trace(Path(a.access_trace), since_ms, until_ms).items()):
        if acct not in (str(ctx.master_id), str(ctx.slave_id)):
            continue
        ts = sorted(t for t, _ in calls)
        gaps = [b - x for x, b in zip(ts, ts[1:])]
        role = "master" if acct == str(ctx.master_id) else "slave"
        by_route: dict[str, int] = {}
        for _, p in calls:
            by_route[p] = by_route.get(p, 0) + 1
        res[role] = {"calls": len(ts), "per_min": round(len(ts) / minutes, 1), "min_gap_ms": min(gaps) if gaps else None,
                     "routes": by_route}
        ctx.note(f"{role}: {len(ts)} calls, {res[role]['per_min']}/min, min gap {res[role]['min_gap_ms']} ms, {by_route}")
        if gaps:
            check(min(gaps) >= a.min_gap_ms - a.gap_tolerance_ms,
                  f"{role}: two calls {min(gaps)} ms apart (< min gap {a.min_gap_ms} - {a.gap_tolerance_ms} ms)")
    return res


def _pip(sym: str) -> float:
    return 0.01 if "JPY" in sym else 0.0001


def _rollover(utc_s: float) -> bool:
    """Inside 17:55-18:15 Brasília (UTC-3), the New York rollover window (spreads widen)."""
    t = time.gmtime(utc_s - 3 * 3600)
    m = t.tm_hour * 60 + t.tm_min
    return 17 * 60 + 55 <= m <= 18 * 60 + 15


def _latency_cycle(ctx: Ctx, sym: str, side: str, tag: str, seen: set[int]) -> dict:
    a = ctx.args
    t0 = time.time()
    op = ctx.master_open(sym, side, 0.01, tag)
    try:
        sq = ctx.slave.send("quote", timeout=10, symbol=sym)
    except Fail:
        sq = {}
    copy = wait_for(f"new copy({sym}) open",
                    lambda: next((c for c in ctx.new_copies(sym) if c["id"] not in seen and c["state"] == "open"),
                                 None), ctx.timeout, 0.5)
    spos = ctx.wait_slave_pos(copy["id"])
    mpos = ctx.master.positions(comment=f"e2e-{tag}"[:31], symbol=sym)
    check(len(mpos) == 1, f"one master position e2e-{tag}")
    m_in = _deal(ctx.master, mpos[0]["identifier"], "in", ctx.timeout)
    s_in = _deal(ctx.slave, spos["identifier"], "in", ctx.timeout)
    time.sleep(a.latency_hold)
    ctx.master.must("close", ticket=mpos[0]["ticket"])
    ctx.wait_slave_gone(copy["id"])
    m_out = _deal(ctx.master, mpos[0]["identifier"], "out", ctx.timeout)
    s_out = _deal(ctx.slave, spos["identifier"], "out", ctx.timeout)
    pip = _pip(sym)
    sgn = 1 if side == "buy" else -1

    def spread(q: dict) -> float | None:
        return round((q["ask"] - q["bid"]) / pip, 2) if q.get("ask") and q.get("bid") else None

    return {"symbol": sym, "side": side, "copy_id": copy["id"], "utc": time.strftime("%H:%M:%S", time.gmtime(t0)),
            "rollover": _rollover(t0) or _rollover(time.time()),
            "open_ms": s_in["time_msc"] - m_in["time_msc"], "close_ms": s_out["time_msc"] - m_out["time_msc"],
            # + = the slave got a worse price than the master
            "open_pips": round(sgn * (s_in["price"] - m_in["price"]) / pip, 2),
            "close_pips": round(sgn * (m_out["price"] - s_out["price"]) / pip, 2),
            "master_spread_pips": spread(op), "slave_spread_pips": spread(sq)}


def _summary(rows: list[dict]) -> dict:
    out = {}
    for k in ("open_ms", "close_ms", "open_pips", "close_pips", "master_spread_pips", "slave_spread_pips"):
        v = [r[k] for r in rows if r.get(k) is not None]
        if v:
            out[k] = {"p50": _pctl(v, 0.5), "p90": _pctl(v, 0.9), "max": max(v), "min": min(v)}
    return out


@scenario()
def s_latency(ctx: Ctx) -> None:
    """N open+close cycles on GBPUSD/EURUSD (or N per symbol of --latency-symbols): open/close latency (slave
    deal - master deal, broker time_msc), price diff in pips (+ = worse for the slave), spread at open,
    p50/p90/max; --max-p90-ms fails the run; per-account calls/min and min gap from the server access trace."""
    a = ctx.args
    if a.latency_symbols:
        plan, skipped = [], {}
        def quotable(t: Terminal, sym: str) -> bool:
            for _ in range(3):   # a symbol just added to Market Watch has no tick for a moment
                q = t.send("quote", timeout=10, symbol=sym)
                if q.get("ok") or "unknown op" in str(q.get("error")):   # older driver: no spread, still try
                    return True
                time.sleep(1.5)
            return False

        for sym in a.latency_symbols:
            bad = [t.role for t in (ctx.master, ctx.slave) if not quotable(t, sym)]
            if bad:
                skipped[sym] = f"no quote on {'/'.join(bad)}"
                ctx.note(f"{sym}: skipped ({skipped[sym]})")
            else:
                plan += [(sym, ("buy", "sell")[k % 2]) for k in range(a.latency_cycles)]
    else:
        syms = [s for s in ("GBPUSD", "EURUSD") if s in a.symbols] or a.symbols[:2]
        plan = [(syms[i % len(syms)], ("buy", "sell")[(i // len(syms)) % 2]) for i in range(a.latency_cycles)]
        skipped = {}
    rows: list[dict] = []
    failed: dict[str, str] = {}
    since = int(time.time() * 1000)
    started = time.time()
    for i, (sym, side) in enumerate(plan):
        if sym in failed:
            continue
        try:
            r = _latency_cycle(ctx, sym, side, f"lat{i}", {x["copy_id"] for x in rows})
        except Fail as e:
            if not a.latency_symbols:
                raise
            failed[sym] = str(e)
            ctx.note(f"{sym}: cycle failed, symbol abandoned: {e}")
            ctx.cleanup()
            continue
        rows.append(r)
        ctx.note(f"cycle {i + 1}/{len(plan)} {sym} {side}: open {r['open_ms']} ms ({r['open_pips']} pip), "
                 f"close {r['close_ms']} ms ({r['close_pips']} pip), spread {r['master_spread_pips']}/"
                 f"{r['slave_spread_pips']} pip{' ROLLOVER' if r['rollover'] else ''}")
        time.sleep(a.latency_pause)
    until = int(time.time() * 1000)
    check(rows, "no latency cycle completed")
    summary = _summary(rows)
    for k, v in summary.items():
        ctx.note(f"{k:18} p50={v['p50']} p90={v['p90']} max={v['max']}")
    per_symbol = {}
    if a.latency_symbols:
        for sym in dict.fromkeys(r["symbol"] for r in rows):
            per_symbol[sym] = _summary([r for r in rows if r["symbol"] == sym])
            ps = per_symbol[sym]
            ctx.note(f"{sym}: open {ps['open_ms']['p50']}/{ps['open_ms']['p90']} ms, close {ps['close_ms']['p50']}/"
                     f"{ps['close_ms']['p90']} ms, open pips p50 {ps['open_pips']['p50']} p90 {ps['open_pips']['p90']}"
                     f" worst {ps['open_pips']['max']}, close pips p50 {ps['close_pips']['p50']} p90 "
                     f"{ps['close_pips']['p90']} worst {ps['close_pips']['max']}")
    window = {"start_utc": time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(started)),
              "end_utc": time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime()),
              "rollover_overlap": any(r["rollover"] for r in rows)}
    trace = check_trace(ctx, since, until)
    out = a.out_dir / f"latency-{time.strftime('%Y%m%d-%H%M%S')}.json"
    out.write_text(json.dumps({"rows": rows, "summary": summary, "per_symbol": per_symbol, "skipped": skipped,
                               "failed": failed, "window": window, "http": trace, "label": a.latency_label},
                              indent=2))
    ctx.note(f"latency report: {out} ({window['start_utc']} - {window['end_utc']} UTC"
             f"{', overlaps the NY rollover' if window['rollover_overlap'] else ''})")
    if a.max_p90_ms:
        for k in ("open_ms", "close_ms"):
            check(summary[k]["p90"] <= a.max_p90_ms, f"{k} p90 {summary[k]['p90']} ms > --max-p90-ms {a.max_p90_ms}")


# --- runner --------------------------------------------------------------------------------------------

def preconditions(ctx: Ctx) -> list[str]:
    problems = []
    if not ctx.admin.health():
        return [f"server {ctx.admin.url} not healthy"]
    try:
        accts = {a["id"]: a for a in ctx.admin.get("/admin/accounts")["accounts"]}
        links = {l["id"]: l for l in ctx.admin.get("/admin/links")["links"]}
    except httpx.HTTPError as e:
        return [f"admin API failed: {e} (ADMIN_TOKEN?)"]
    for aid, role, term in ((ctx.master_id, "master", ctx.master), (ctx.slave_id, "slave", ctx.slave)):
        a = accts.get(aid)
        if not a:
            problems.append(f"account {aid} missing")
            continue
        if not a["enrolled"] or a["status"] != "active" or a["role"] != role:
            problems.append(f"account {aid}: enrolled={a['enrolled']} status={a['status']} role={a['role']}")
        if term.state() != "running":
            problems.append(f"container {term.container} is {term.state()}")
            continue
        if not term.alive(10):
            problems.append(f"{role} driver not writing {term.files}/status.json (attach TradeMirrorE2EDriver)")
            continue
        st = term.status()
        if str(st["login"]) != str(a["login"]):
            problems.append(f"{role} driver login {st['login']} != account {aid} login {a['login']}")
        if not st["demo"]:
            problems.append(f"{role} terminal is not a DEMO account")
        if not (st["terminal_trade_allowed"] and st["ea_trade_allowed"]):
            problems.append(f"{role}: AutoTrading / Allow algo trading is off")
        if not st["connected"]:
            problems.append(f"{role} terminal not connected to the broker")
        if not term.forwarder_running():
            problems.append(f"{role}: no forwarder in {term.container}; starting it")
            term.start_forwarder()
        try:
            ping = term.send("ping", timeout=10)
            if not ping.get("ok"):
                problems.append(f"{role} driver ping failed")
        except Fail as e:
            problems.append(str(e))
    link = links.get(ctx.link_id)
    if not link or not link["enabled"] or link["master_id"] != ctx.master_id or link["slave_id"] != ctx.slave_id:
        problems.append(f"link {ctx.link_id} missing/disabled or not {ctx.master_id}->{ctx.slave_id}: {link}")
    elif link["lot_mode"] != "master" or link["magic_mode"] != "same" or not link["copy_sl_tp"]:
        problems.append("link must be lot_mode=master, magic_mode=same, copy_sl_tp=true for these assertions")
    return problems


def build_args(argv: list[str] | None) -> argparse.Namespace:
    env = os.environ
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("scenarios", nargs="*", help="scenario names (default: all)")
    ap.add_argument("--list", action="store_true", help="list scenarios and exit")
    ap.add_argument("-k", dest="keyword", help="run scenarios whose name contains this text")
    ap.add_argument("--fast", action="store_true", help="skip slow scenarios (restarts, network cuts, faults)")
    ap.add_argument("--server-url", default=env.get("E2E_SERVER_URL", "http://172.17.0.1:8099"))
    ap.add_argument("--admin-token", default=env.get("ADMIN_TOKEN"))
    ap.add_argument("--admin-token-file", default=env.get("E2E_ADMIN_TOKEN_FILE"),
                    help="file holding the admin token (bare, or an env file with ADMIN_TOKEN=...)")
    ap.add_argument("--master-ssh", default=env.get("E2E_MASTER_SSH"),
                    help="user@host of a remote master: driver files and docker inspect go over ssh")
    ap.add_argument("--master-files", default=env.get("E2E_MASTER_FILES"),
                    help="with --master-ssh: remote path of the master driver dir (MQL5/Files/TradeMirrorE2E)")
    ap.add_argument("--cleanup-magic-only", action="store_true",
                    help="cleanup touches only --magic positions/copies (implied by --master-ssh)")
    ap.add_argument("--remote-access-trace", default=env.get("E2E_REMOTE_ACCESS_TRACE"),
                    help="'user@host:container:/path' of the server access trace (copied locally via docker exec)")
    ap.add_argument("--env-file", help="shell file with 'export ADMIN_TOKEN=...' (e.g. the demo env.sh)",
                    default=env.get("E2E_ENV_FILE"))
    ap.add_argument("--link-id", type=int, default=int(env.get("E2E_LINK_ID", 1)))
    ap.add_argument("--master-id", type=int, default=int(env.get("E2E_MASTER_ID", 1)))
    ap.add_argument("--slave-id", type=int, default=int(env.get("E2E_SLAVE_ID", 2)))
    ap.add_argument("--master-container", default=env.get("E2E_MASTER_CONTAINER", "mt5-trademirror"))
    ap.add_argument("--slave-container", default=env.get("E2E_SLAVE_CONTAINER", "mt5-trademirror-slave"))
    ap.add_argument("--master-prefix", type=Path, default=Path(env.get("E2E_MASTER_PREFIX", LAB / "prefix-trademirror")))
    ap.add_argument("--slave-prefix", type=Path, default=Path(env.get("E2E_SLAVE_PREFIX", LAB / "prefix-trademirror-slave")))
    ap.add_argument("--master-dir", default=env.get("E2E_MASTER_DIR", "MT5-trademirror"))
    ap.add_argument("--slave-dir", default=env.get("E2E_SLAVE_DIR", "MT5-trademirror-slave"))
    ap.add_argument("--forward-host", default=env.get("E2E_FORWARD_HOST", "172.17.0.1"),
                    help="host address the in-container forwarder connects to")
    ap.add_argument("--symbol", default=env.get("E2E_SYMBOL", "GBPUSD"))
    ap.add_argument("--symbols", default=env.get("E2E_SYMBOLS", "GBPUSD,EURUSD,USDJPY"))
    ap.add_argument("--magic", type=int, default=int(env.get("E2E_MAGIC", 424242)))
    ap.add_argument("--timeout", type=float, default=45.0, help="default wait per step (s)")
    ap.add_argument("--cut-seconds", type=float, default=60.0, help="network cut length (s)")
    ap.add_argument("--rate-limit-wait", type=float, default=60.0,
                    help="wait for the held result after removing the 429 proxy before reloading the slave")
    ap.add_argument("--proxy-host", default="172.17.0.1")
    ap.add_argument("--proxy-port", type=int, default=8098)
    ap.add_argument("--server-project", type=Path, default=REPO / "server",
                    help="uv project used to run fault_proxy.py (needs the server models)")
    ap.add_argument("--server-match", default=env.get("E2E_SERVER_MATCH", "uvicorn copycore.app:create_app.*--port 8099"),
                    help="pgrep -f pattern of the server process (server_restart)")
    ap.add_argument("--server-restart-cmd", default=env.get("E2E_SERVER_RESTART_CMD"),
                    help="shell command that starts the server again (server_restart is skipped without it)")
    ap.add_argument("--latency-cycles", type=int, default=int(env.get("E2E_LATENCY_CYCLES", 10)))
    ap.add_argument("--latency-hold", type=float, default=3.0, help="seconds a latency position stays open")
    ap.add_argument("--latency-pause", type=float, default=2.0, help="seconds between latency cycles")
    ap.add_argument("--latency-symbols", default="",
                    help="comma list: --latency-cycles open+close cycles per symbol, per-symbol summary")
    ap.add_argument("--latency-label", default="", help="free text stored in the latency report")
    ap.add_argument("--max-p90-ms", type=float, default=0, help="latency fails when open/close p90 exceeds this")
    ap.add_argument("--access-trace", default=env.get("E2E_ACCESS_TRACE"),
                    help="server ACCESS_TRACE_PATH file: per-account calls/min and min-gap check")
    ap.add_argument("--min-gap-ms", type=int, default=int(env.get("E2E_MIN_GAP_MS", 300)),
                    help="EA MinCallGapMs: no two calls of one account closer than this")
    ap.add_argument("--gap-tolerance-ms", type=int, default=30,
                    help="clock/arrival jitter allowed below --min-gap-ms (EA timer resolution ~16 ms)")
    ap.add_argument("--out-dir", type=Path, default=Path(__file__).resolve().parent / "out")
    ap.add_argument("--keep-going-on-cleanup-failure", action="store_true")
    a = ap.parse_args(argv)
    if a.env_file and not a.admin_token:
        for line in Path(a.env_file).read_text().splitlines():
            line = line.strip().removeprefix("export ").strip()
            if line.startswith("ADMIN_TOKEN="):
                a.admin_token = line.split("=", 1)[1].strip().strip("'\"")
    if a.admin_token_file and not a.admin_token:
        text = Path(a.admin_token_file).read_text()
        for line in text.splitlines():
            line = line.strip().removeprefix("export ").strip()
            if line.startswith("ADMIN_TOKEN="):
                a.admin_token = line.split("=", 1)[1].strip().strip("'\"")
        if not a.admin_token and len(text.split()) == 1:
            a.admin_token = text.strip()
    if a.master_ssh and not a.master_files:
        ap.error("--master-ssh needs --master-files")
    if a.master_ssh:
        a.cleanup_magic_only = True
    a.symbols = [s.strip() for s in a.symbols.split(",") if s.strip()]
    a.latency_symbols = [s.strip() for s in a.latency_symbols.split(",") if s.strip()]
    return a


def main(argv: list[str] | None = None) -> int:
    a = build_args(argv)
    if a.list:
        for s in SCENARIOS:
            print(f"{s.name:28} {'[slow] ' if s.slow else ''}{s.doc.splitlines()[0] if s.doc else ''}")
        return 0
    names = {s.name for s in SCENARIOS}
    unknown = [n for n in a.scenarios if n not in names]
    if unknown:
        print(f"unknown scenario(s): {unknown}; see --list", file=sys.stderr)
        return 2
    selected = [s for s in SCENARIOS if (not a.scenarios or s.name in a.scenarios)
                and (not a.keyword or a.keyword in s.name) and not (a.fast and s.slow)]
    if not a.admin_token:
        print("ADMIN_TOKEN not set (use --admin-token, ADMIN_TOKEN or --env-file)", file=sys.stderr)
        return 2
    a.out_dir.mkdir(parents=True, exist_ok=True)
    ctx = Ctx(args=a, admin=Admin(a.server_url, a.admin_token),
              master=Terminal("master", a.master_container, a.master_prefix, a.master_dir, a.forward_host,
                              remote=Remote(a.master_ssh, Path.home() / ".ssh" / "tm-e2e") if a.master_ssh else None,
                              remote_files=a.master_files),
              slave=Terminal("slave", a.slave_container, a.slave_prefix, a.slave_dir, a.forward_host),
              link_id=a.link_id, slave_id=a.slave_id, master_id=a.master_id, timeout=a.timeout)

    print(f"TradeMirror e2e: {len(selected)} scenario(s) against {a.server_url}", flush=True)
    problems = preconditions(ctx)
    if problems:
        print("PRECONDITIONS FAILED:\n  - " + "\n  - ".join(problems), file=sys.stderr)
        return 2
    print("preconditions ok; initial cleanup", flush=True)
    try:
        ctx.cleanup()
    except Exception as e:  # noqa: BLE001
        print(f"initial cleanup failed: {e}", file=sys.stderr)
        return 2

    results = []
    started = time.time()
    for s in selected:
        print(f"\n== {s.name}: {s.doc.splitlines()[0] if s.doc else ''}", flush=True)
        ctx.notes = []
        t0 = time.monotonic()
        status, detail = "PASS", ""
        try:
            ctx.mark()
            s.fn(ctx)
            ctx.assert_no_new_orphans()
        except Skip as e:
            status, detail = "SKIP", str(e)
        except Fail as e:
            status, detail = "FAIL", str(e)
        except Exception as e:  # noqa: BLE001
            status, detail = "ERROR", f"{type(e).__name__}: {e}"
            traceback.print_exc()
        finally:
            for t in (ctx.slave, ctx.master):   # never leave a cut link behind
                try:
                    if t.state() != "running":
                        t.start_terminal()
                    elif not t.forwarder_running():
                        t.start_forwarder()
                except Exception as e:  # noqa: BLE001
                    log(f"restore {t.role} failed: {e}")
        events = []
        try:
            events = [{"id": e["id"], "type": e["type"], "payload": e["payload"]} for e in ctx.new_events()]
        except Exception:  # noqa: BLE001
            pass
        cleanup_err = ""
        try:
            ctx.cleanup()
        except Exception as e:  # noqa: BLE001
            cleanup_err = f"cleanup failed: {e}"
            if status == "PASS":
                status, detail = "FAIL", cleanup_err
        dur = time.monotonic() - t0
        print(f"   -> {status} ({dur:.0f}s) {detail}", flush=True)
        results.append({"name": s.name, "status": status, "detail": detail, "seconds": round(dur, 1),
                        "notes": list(ctx.notes), "cleanup_error": cleanup_err, "events": events})
        if cleanup_err and not a.keep_going_on_cleanup_failure:
            print("stopping: cleanup failed, the accounts may not be flat", file=sys.stderr)
            break

    if (a.access_trace or a.remote_access_trace) and results:
        # every run: no two calls of one EA closer than the configured min gap (server-side arrival times)
        ctx.notes = []
        try:
            http = check_trace(ctx, int(started * 1000), int(time.time() * 1000))
            gap = {"name": "min_gap (whole run)", "status": "PASS", "detail": json.dumps(
                {k: {"per_min": v["per_min"], "min_gap_ms": v["min_gap_ms"]} for k, v in http.items()}),
                   "seconds": 0, "notes": list(ctx.notes), "cleanup_error": "", "events": []}
        except Fail as e:
            gap = {"name": "min_gap (whole run)", "status": "FAIL", "detail": str(e), "seconds": 0,
                   "notes": list(ctx.notes), "cleanup_error": "", "events": []}
        results.append(gap)
        selected = [*selected, None]

    print("\n" + "-" * 78)
    print(f"{'scenario':30} {'result':6} {'time':>6}  detail")
    print("-" * 78)
    for r in results:
        print(f"{r['name']:30} {r['status']:6} {r['seconds']:5.0f}s  {r['detail'][:120]}")
    print("-" * 78)
    counts = {k: sum(r["status"] == k for r in results) for k in ("PASS", "FAIL", "ERROR", "SKIP")}
    print("  ".join(f"{k} {v}" for k, v in counts.items()))
    report = a.out_dir / f"report-{time.strftime('%Y%m%d-%H%M%S')}.json"
    report.write_text(json.dumps({"started": started, "finished": time.time(), "server": a.server_url,
                                  "counts": counts, "results": results}, indent=2))
    print(f"report: {report}")
    return 0 if counts["FAIL"] == 0 and counts["ERROR"] == 0 and len(results) == len(selected) else 1


if __name__ == "__main__":
    raise SystemExit(main())
