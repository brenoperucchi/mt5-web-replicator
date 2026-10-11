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
import re
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
    direct: bool = False               # the EA talks to the server itself (https), no in-container forwarder
    remote_network: str = "bridge"     # docker network a remote terminal is disconnected from to cut it
    _io: LocalFiles | None = None
    _cut: bool = False
    _fwd_port: int | None = None       # forwarder target port (a fault proxy), None = the server itself

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
        if self.remote or self.direct:
            return True   # talks to the server directly (no forwarder to cut)
        return self.podman("exec", self.container, "pgrep", "-f", "forward").returncode == 0

    def stop_forwarder(self) -> None:
        if self.remote or self.direct:
            raise Skip(f"{self.role} talks to the server directly: use cut()/uncut() instead of the forwarder")
        self.podman("exec", self.container, "pkill", "-f", "tm_forward.py")
        self.podman("exec", self.container, "pkill", "-f", "tm_e2e_forward")
        wait_for(f"{self.role} forwarder stopped", lambda: not self.forwarder_running(), 10, 0.5)

    def start_forwarder(self, port: int | None = None) -> None:
        """Default forwarder (tm_forward.py -> host:8099) or, with a port, one to host:<port>."""
        if self.remote or self.direct:
            if port is not None:
                raise Skip(f"{self.role} talks to the server directly: the fault proxy cannot be put in front of it")
            return
        self._fwd_port = port
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
        """Hard-kill terminal64 (no profile save, no OnDeinit): the container's main process exits."""
        self.podman("exec", self.container, "pkill", "-9", "-f", "terminal64.exe")
        try:
            wait_for(f"{self.container} exited", lambda: self.state() in ("exited", "stopped"), 20, 0.5)
        except Fail:
            self.podman("stop", "-t", "5", self.container)

    def start_terminal(self) -> None:
        for attempt in range(3):
            if self.state() != "running":
                self.podman("start", self.container, check_rc=True)
            started = time.time()

            def up() -> bool:
                if self.state() != "running":
                    if time.time() - started > 12:
                        raise Fail(f"{self.container} stopped right after it started")
                    return False
                return self.podman("exec", self.container, "pgrep", "-f", "terminal64.exe").returncode == 0

            try:
                wait_for(f"{self.container} terminal64 running", up, 60, 1)
                time.sleep(8)   # a terminal that hands over to a live updater is gone within seconds
                if self.state() != "running":
                    raise Fail(f"{self.container} stopped right after it started")
                break
            except Fail:
                # A pending MT5 live update makes terminal64 hand over to its updater and exit, which stops the
                # container (the updater dies with it): apply it in a throwaway container and start again.
                if attempt == 2 or self.state() == "running" or not self.apply_pending_update(started):
                    raise
        self.start_forwarder(self._fwd_port)
        wait_for(f"{self.role} driver writing status again",
                 lambda: self.status_age() < time.time() - started - 1 and self.alive(), 120)

    def apply_pending_update(self, since: float) -> bool:
        """The container's terminal exited after announcing a LiveUpdate: run that updater to completion in a
        container of its own (same image and prefix, name ends in -updater so it stays ours)."""
        pat = re.compile(r'LiveUpdate\s+start "([^"]+)" /update /path:"([^"]+)"')
        image = self.podman("inspect", self.container, "--format", "{{.ImageName}}").stdout.strip()
        if self.remote:
            root, rest = (self.remote_files or "").split("/drive_c/", 1)
            tdir = rest.split("/MQL5/")[0]
            line = self.remote.run(f"f=$(ls -t {shlex.quote(root)}/drive_c/{shlex.quote(tdir)}/logs/*.log | head -1);"
                                   f" iconv -f utf-16 -t utf-8 \"$f\" | grep -a LiveUpdate | tail -1").stdout
            m = pat.search(line)
            user = self.podman("inspect", self.container, "--format", "{{.Config.User}}").stdout.strip()
            run_args = ["--user", user, "-v", f"{root}:/wineprefix", "-e", "WINEPREFIX=/wineprefix", "-e", "HOME=/tmp"]
        else:
            logdir = self.prefix / "drive_c" / self.terminal_dir / "logs"
            m = None
            for f in sorted(logdir.glob("*.log"))[-2:]:
                if f.stat().st_mtime < since - 5:
                    continue
                for ln in f.read_bytes().decode("utf-16", errors="ignore").splitlines():
                    m = pat.search(ln) or m
            run_args = ["--userns=keep-id", "-v", f"{self.prefix}:/home/mt5/.mt5", "-e", "WINEPREFIX=/home/mt5/.mt5",
                        "-e", "HOME=/home/mt5"]
        if m is None:
            return False
        cmd = [m.group(1), "/update", f"/path:{m.group(2)}", "/portable"]
        script = ("Xvfb :99 -screen 0 1600x900x24 >/dev/null 2>&1 & sleep 3; wine " +
                  " ".join(shlex.quote(x) for x in cmd) + "; sleep 3")
        log(f"{self.role}: MT5 live update pending, applying it in {self.container}-updater")
        argv = ["run", "--rm", "--name", f"{self.container}-updater", *run_args, "-e", "WINEDEBUG=-all",
                "-e", "WINEDLLOVERRIDES=mscoree=d", "-e", "DISPLAY=:99", "-e", "TZ=BRT3", image, "bash", "-c", script]
        if self.remote:
            p = self.remote.run(shlex.join(["docker", *argv]), timeout=900)
        else:
            p = sh(["podman", *argv], timeout=900)
        return p.returncode == 0

    def stop_container(self, timeout: int = 20) -> None:
        """Graceful stop (SIGTERM, the terminal saves its state); used for long outages."""
        self.podman("stop", "-t", str(timeout), self.container)

    # network faults -----------------------------------------------------------------------------
    # Local terminals: nftables in the container's own network namespace (rootless: `podman unshare nsenter`),
    # so only this container is touched and it can be selective. Remote (KS1, no sudo): the whole container
    # is disconnected from its docker network (broker and server together).
    NFT_TABLE = "tmchaos"

    def _nft(self, script: str, check_rc: bool = True) -> None:
        pid = self.podman("inspect", "-f", "{{.State.Pid}}", self.container).stdout.strip()
        if not pid.isdigit() or int(pid) == 0:
            raise RuntimeError(f"{self.container} has no running process (pid {pid!r})")
        p = subprocess.run(["podman", "unshare", "nsenter", "-t", pid, "-n", "nft", "-f", "-"], input=script,
                           capture_output=True, text=True, timeout=30)
        if check_rc and p.returncode != 0:
            raise RuntimeError(f"nft in {self.container} failed: {p.stderr.strip()[:300]}")

    def cut(self, kind: str, server_ips: list[str], server_port: int) -> None:
        """kind 'server': nothing reaches the Copy Server (the terminal keeps its broker connection).
        kind 'broker': the terminal loses its broker connection (the server stays reachable).
        kind 'all': both. Remote terminals can only do 'all'."""
        assert kind in ("server", "broker", "all"), kind
        if self.remote:
            if kind != "all":
                raise Skip(f"{self.role} is remote ({self.remote.target}) and cannot be cut selectively (no root)")
            self.podman("network", "disconnect", self.remote_network, self.container, check_rc=True)
            self._cut = True
            return
        ips = "{ " + ", ".join(server_ips) + " }"
        rules = []
        if kind in ("server", "all"):
            rules.append(f"ip daddr {ips} tcp dport {server_port} counter reject with tcp reset")
        if kind in ("broker", "all"):
            rules += ["ip daddr 127.0.0.0/8 accept", "meta l4proto { tcp, udp } th dport 53 accept"]
            if kind == "broker":
                rules.append(f"ip daddr {ips} accept")
            rules += ["meta l4proto tcp counter reject with tcp reset", "counter drop"]
        body = "\n    ".join(rules)
        self._nft(f"table inet {self.NFT_TABLE}\ndelete table inet {self.NFT_TABLE}\n"
                  f"table inet {self.NFT_TABLE} {{\n  chain out {{\n    type filter hook output priority 0; "
                  f"policy accept;\n    {body}\n  }}\n}}\n")
        self._cut = True
        log(f"{self.role}: network cut ({kind})")

    def uncut(self) -> None:
        """Undo cut(); idempotent and safe on a terminal that was never cut."""
        if self.remote:
            if self._cut:
                self.podman("network", "connect", self.remote_network, self.container, check_rc=True)
        elif self.state() == "running":
            self._nft(f"table inet {self.NFT_TABLE}\ndelete table inet {self.NFT_TABLE}\n", check_rc=False)
        if self._cut:
            log(f"{self.role}: network restored")
        self._cut = False

    def connected(self) -> bool:
        return bool(self.fresh_status()["connected"])


# --- server ------------------------------------------------------------------------------------

class Admin:
    def __init__(self, url: str, token: str):
        self.url = url.rstrip("/")
        self.http = httpx.Client(base_url=self.url, headers={"Authorization": f"Bearer {token}"}, timeout=10)

    def get(self, path: str, **params: Any) -> dict:
        r = self.http.get(path, params={k: v for k, v in params.items() if v is not None})
        r.raise_for_status()
        return r.json()

    def send(self, method: str, path: str, body: dict | None = None) -> Any:
        r = self.http.request(method, path, json=body)
        r.raise_for_status()
        return r.json() if r.content else None

    def patch(self, path: str, body: dict) -> Any:
        return self.send("PATCH", path, body)

    def post(self, path: str, body: dict | None = None) -> Any:
        return self.send("POST", path, body or {})

    def delete(self, path: str) -> Any:
        return self.send("DELETE", path)

    def account(self, account_id: int) -> dict:
        return self.get(f"/admin/accounts/{account_id}")

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
    undo: list[tuple[str, Callable[[], None]]] = field(default_factory=list)   # restore steps of the running scenario
    copy_floor: int = 0     # newest copy id before this scenario
    copies_before: set[int] = field(default_factory=set)  # ids that belong to earlier scenarios (the id
    # sequence may be rewound to reproduce a c<id> collision, so "newer" is not "bigger id")
    event_floor: int = 0

    def note(self, msg: str) -> None:
        self.notes.append(msg)
        log(msg)

    def on_cleanup(self, label: str, fn: Callable[[], None]) -> None:
        """Register a restore step; the runner runs them (newest first) after the scenario, pass or fail."""
        self.undo.append((label, fn))

    def run_undo(self) -> list[str]:
        errs = []
        while self.undo:
            label, fn = self.undo.pop()
            try:
                fn()
            except Exception as e:  # noqa: BLE001
                errs.append(f"{label}: {type(e).__name__}: {e}")
                log(f"restore step {label!r} failed: {e}")
        return errs

    def server_endpoint(self) -> tuple[list[str], int]:
        """IPv4 addresses and port of the Copy Server (what a network cut has to block)."""
        import socket
        from urllib.parse import urlparse
        u = urlparse(self.args.server_url)
        port = u.port or (443 if u.scheme == "https" else 80)
        ips = sorted({ai[4][0] for ai in socket.getaddrinfo(u.hostname, port, socket.AF_INET, socket.SOCK_STREAM)})
        return ips, port

    def cut(self, t: "Terminal", kind: str) -> None:
        ips, port = self.server_endpoint()
        t.cut(kind, ips, port)
        self.on_cleanup(f"restore {t.role} network", t.uncut)

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
    group: str = "core"


SCENARIOS: list[Scenario] = []


def scenario(slow: bool = False, group: str = "core"):
    def deco(fn: Callable[[Ctx], None]):
        SCENARIOS.append(Scenario(fn.__name__.removeprefix("s_"), fn, (fn.__doc__ or "").strip(), slow, group))
        return fn
    return deco


def is_copy_comment(comment: str | None, copy_id: int) -> bool:
    """Slave comment of copy `copy_id`: `c<copy_id>-<master position id>` (or legacy `c<copy_id>`)."""
    return comment == f"c{copy_id}" or (comment or "").startswith(f"c{copy_id}-")


def open_and_mirror(ctx: Ctx, symbol: str, side: str, volume: float, tag: str, **kw: Any) -> tuple[dict, dict]:
    known = {c["id"] for c in ctx.new_copies(symbol)}   # a scenario may open the same symbol more than once
    ctx.master_open(symbol, side, volume, tag, **kw)
    copy = wait_for(f"a new copy({symbol}) open",
                    lambda: next((c for c in ctx.new_copies(symbol) if c["id"] not in known and c["state"] == "open"),
                                 None), ctx.timeout)
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
    """fault_proxy.py on the host, with a terminal's forwarder pointed at it (the slave by default).

    `set(...)` rewrites the proxy's control file while it runs (snapshot mutations, server_time shift, fail_all);
    see ea/mt5/tests/fault_proxy.py. Several proxies can run at once on different ports (one per terminal)."""

    def __init__(self, ctx: Ctx, *fault_args: str, term: Terminal | None = None, port: int | None = None):
        self.ctx, self.fault_args = ctx, list(fault_args)
        self.term = term or ctx.slave
        self.port = port or ctx.args.proxy_port
        self.proc: subprocess.Popen | None = None
        stamp = f"{self.term.role}-{int(time.time())}"
        self.out = ctx.args.out_dir / f"proxy-{stamp}.log"
        self.control = ctx.args.out_dir / f"proxy-{stamp}.control.json"

    def __enter__(self) -> "Proxy":
        a = self.ctx.args
        self.control.unlink(missing_ok=True)
        cmd = ["uv", "run", "-q", "--project", str(a.server_project), "python",
               str(REPO / "ea/mt5/tests/fault_proxy.py"), "--upstream", a.server_url,
               "--host", a.proxy_host, "--port", str(self.port), "--control", str(self.control), *self.fault_args]
        self.fh = self.out.open("w")
        self.proc = subprocess.Popen(cmd, stdout=self.fh, stderr=subprocess.STDOUT, start_new_session=True)
        wait_for("fault proxy listening", lambda: _port_open(a.proxy_host, self.port), 60, 0.5)
        self.term.start_forwarder(self.port)
        log(f"{self.term.role} -> proxy :{self.port} {' '.join(self.fault_args)}")
        return self

    def set(self, **ctl: Any) -> None:
        """Replace the runtime faults (set() with nothing clears them)."""
        tmp = self.control.with_suffix(".tmp")
        tmp.write_text(json.dumps(ctl))
        os.replace(tmp, self.control)
        log(f"{self.term.role} proxy faults: {ctl or 'none'}")

    def __exit__(self, *exc: Any) -> None:
        try:
            self.term.start_forwarder()
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


# --- chaos group -----------------------------------------------------------------------------------
# Error scenarios: each one sets up a copy, injects a fault (kill, network or broker loss, proxy rewrite, DB
# rollback, suspension ...), asserts on the admin API (/admin/copies, /commands, /events, /orphans) and the
# drivers' status, and restores everything through ctx.on_cleanup. Select with --group chaos or by name.
# A scenario that cannot run on the current setup raises Skip with the reason.

def hold(seconds: float, probe: Callable[[], None], every: float = 3.0) -> None:
    """Run probe() every `every` seconds for `seconds`; probe raises Fail when an invariant breaks."""
    end = time.monotonic() + seconds
    while True:
        probe()
        if time.monotonic() >= end:
            return
        time.sleep(min(every, max(0.1, end - time.monotonic())))


def copy_row(ctx: Ctx, copy_id: int) -> dict:
    row = next((c for c in ctx.admin.copies(link_id=ctx.link_id, limit=500) if c["id"] == copy_id), None)
    check(row is not None, f"copy {copy_id} not found")
    return row  # type: ignore[return-value]


def copy_commands(ctx: Ctx, copy_id: int, *actions: str) -> list[dict]:
    return [c for c in ctx.admin.commands(copy_id=copy_id, limit=200) if not actions or c["action"] in actions]


def new_events_of(ctx: Ctx, *types: str) -> list[dict]:
    return [e for e in ctx.new_events() if e["type"] in types]


def exit_deals(ctx: Ctx, t: Terminal, position_id: Any) -> list[dict]:
    return [d for d in t.status()["deals"] if d["entry"] in ("out", "out_by") and str(d["position_id"]) == str(position_id)]


def master_ticket_of(ctx: Ctx, tag: str) -> int:
    ps = [p for p in ctx.master.fresh_status()["positions"] if p["comment"] == f"e2e-{tag}"[:31]]
    check(len(ps) == 1, f"expected one master position e2e-{tag}, got {len(ps)}")
    return ps[0]["ticket"]


def close_reason_events(ctx: Ctx) -> dict[str, int]:
    """close_source of every master_position.closed event of this scenario, counted."""
    out: dict[str, int] = {}
    for e in new_events_of(ctx, "master_position.closed"):
        src = (e["payload"] or {}).get("close_source", "?")
        out[src] = out.get(src, 0) + 1
    return out


def exposure_intact(ctx: Ctx, copy: dict, what: str) -> None:
    """The copy is still open, the slave still holds exactly its position, and nothing on the server looks
    like a master close (no absence/close events, no close/cancel command)."""
    row = copy_row(ctx, copy["id"])
    check(row["state"] == "open", f"{what}: copy {copy['id']} is {row['state']} (expected open)")
    ps = ctx.slave_pos(copy["id"])
    check(len(ps) == 1, f"{what}: slave holds {len(ps)} position(s) for c{copy['id']}")
    bad = [e["type"] for e in new_events_of(ctx, "master_position.closed", "master_position.absent",
                                            "master_position.absence_restarted", "master.mass_disappearance")]
    check(not bad, f"{what}: server events that look like a master close: {bad}")
    cmds = copy_commands(ctx, copy["id"], "close", "cancel")
    check(not cmds, f"{what}: close/cancel commands exist: {[(c['action'], c['state']) for c in cmds]}")


# 1 -----------------------------------------------------------------------------------------------
@scenario(slow=True, group="chaos")
def s_chaos_master_restart(ctx: Ctx) -> None:
    """Master terminal hard-killed with a position open, and right after a close the server never heard: no
    duplicate copy after the restart, and the close still reaches the slave."""
    a = ctx.args
    sym, sym2 = a.symbol, (a.symbols[1] if len(a.symbols) > 1 else a.symbol)
    copy, _ = open_and_mirror(ctx, sym, "buy", 0.01, "mrestart-a")
    mid = ctx.master.positions(symbol=sym, magic=a.magic)[0]["identifier"]
    ctx.master.kill_terminal()
    ctx.master.start_terminal()
    time.sleep(25)   # a new session and fresh snapshots: give a duplicate the chance to appear
    check(len(ctx.new_copies(sym)) == 1,
          f"restart created extra copies: {[(c['id'], c['state']) for c in ctx.new_copies(sym)]}")
    ctx.wait_copy_state(copy["id"], {"open"}, 10)
    check(len(ctx.slave_pos(copy["id"])) == 1, "slave position count changed after the master restart")
    mps = ctx.master.fresh_status() and ctx.master.positions(symbol=sym, magic=a.magic)
    check(len(mps) == 1 and mps[0]["identifier"] == mid, "master position changed across the restart")
    bad = new_events_of(ctx, "master_position.closed", "master_position.reappeared", "master_position.absent")
    check(not bad, f"the restart looked like a close/reappearance: {[e['type'] for e in bad]}")
    ctx.note("(a) position open across a master restart: one copy, nothing closed")

    # (b) the master closes while the server cannot hear it, then dies before it can tell
    copy_b, _ = open_and_mirror(ctx, sym2, "sell", 0.01, "mrestart-b")
    tk = _master_ticket(ctx, sym2)
    if ctx.master.remote:
        ctx.master.must("close", ticket=tk)       # no selective cut on a remote master: kill right after the ack
        ctx.master.kill_terminal()
    else:
        ctx.cut(ctx.master, "server")
        ctx.master.must("close", ticket=tk)
        time.sleep(4)                              # snapshots fail meanwhile
        check(copy_row(ctx, copy_b["id"])["state"] == "open", "server learned of the close despite the cut")
        ctx.master.kill_terminal()
    ctx.master.start_terminal()
    ctx.wait_slave_gone(copy_b["id"], timeout=150)
    c = ctx.wait_copy_state(copy_b["id"], {"closed"}, 60)
    check(c["close_reason"] == "master_closed", f"close_reason {c['close_reason']} != master_closed")
    check(len(ctx.new_copies(sym2)) == 1 and len(ctx.new_copies(sym)) == 1,
          "extra copies after the restart-during-close")
    ctx.note(f"(b) close made while the server was unreachable reached the slave after the restart "
             f"(master closes by source: {close_reason_events(ctx)})")
    close_and_mirror(ctx, copy, sym)


# 2 -----------------------------------------------------------------------------------------------
@scenario(slow=True, group="chaos")
def s_chaos_master_netloss(ctx: Ctx) -> None:
    """Master loses its link to the server for --chaos-cut-seconds while it closes its position: the slave keeps
    the position during the blackout (the server cannot know) and closes it after recovery; no orphan.
    A remote master (no root) loses all internet instead, so its close happens right after reconnecting."""
    a = ctx.args
    sym = a.symbol
    copy, _ = open_and_mirror(ctx, sym, "buy", 0.01, "mnet")
    tk = _master_ticket(ctx, sym)
    remote = bool(ctx.master.remote)
    ctx.cut(ctx.master, "all" if remote else "server")
    if remote:
        ctx.note("remote master: broker and server are both unreachable, it closes after the reconnect")
    else:
        ctx.master.must("close", ticket=tk)
        ctx.note("master closed its position while cut off from the server")
    t0 = time.monotonic()
    while time.monotonic() - t0 < a.chaos_cut_seconds:
        check(len(ctx.slave_pos(copy["id"])) == 1, "slave closed without the server hearing from the master")
        check(copy_row(ctx, copy["id"])["state"] == "open", "server moved the copy while the master was silent")
        time.sleep(3)
    ctx.master.uncut()
    if remote:
        wait_for("master terminal reconnected", lambda: ctx.master.fresh_status()["connected"], 150, 3)
        time.sleep(10)
        check(len(ctx.slave_pos(copy["id"])) == 1, "slave closed before the master closed")
        check(copy_row(ctx, copy["id"])["state"] == "open", "copy changed after reconnect without a master close")
        ctx.master.must("close", ticket=_master_ticket(ctx, sym))
    ctx.wait_slave_gone(copy["id"], timeout=150)
    c = ctx.wait_copy_state(copy["id"], {"closed"}, 60)
    check(c["close_reason"] == "master_closed", f"close_reason {c['close_reason']} != master_closed")
    check(len(ctx.new_copies(sym)) == 1, "extra copies after the outage")
    check(len(ctx.slave_in_deals(c)) == 1, "duplicate entry deals on the slave")
    ctx.note(f"slave closed {time.monotonic() - t0 - a.chaos_cut_seconds:.0f}s after the link returned "
             f"(close source: {close_reason_events(ctx)})")


# 3 -----------------------------------------------------------------------------------------------
@scenario(slow=True, group="chaos")
def s_chaos_broker_disconnect(ctx: Ctx) -> None:
    """The terminal loses its BROKER connection (nftables, server stays reachable): (a) on the master, (b) a
    master that reports connected=false with an empty position list (fault proxy; the real EA never sends one)
    and (c) on the slave while the master closes. Nothing closes by mistake; the slave closes after it reconnects."""
    a = ctx.args
    sym = a.symbol
    copy, _ = open_and_mirror(ctx, sym, "buy", 0.01, "brk")

    def intact(what: str) -> Callable[[], None]:
        return lambda: exposure_intact(ctx, copy, what)

    try:
        ctx.cut(ctx.master, "broker")
    except Skip as e:
        ctx.note(f"(a) skipped: {e}")
    else:
        wait_for("master terminal reports no broker connection", lambda: not ctx.master.fresh_status()["connected"],
                 180, 2)   # the terminal notices a silent cut after ~90 s when the market is quiet
        hold(a.chaos_cut_seconds, intact("(a) master offline from the broker"))
        ctx.master.uncut()
        wait_for("master terminal back on the broker", lambda: ctx.master.fresh_status()["connected"], 150, 3)
        time.sleep(15)
        exposure_intact(ctx, copy, "(a) after the master reconnected")
        ctx.note("(a) master broker outage: copy stayed open, no close/absence event")

    if ctx.master.remote or ctx.master.direct:
        ctx.note("(b) skipped: the master talks to the server directly, no fault proxy possible")
    else:
        with Proxy(ctx, term=ctx.master, port=a.master_proxy_port) as px:
            px.set(snapshot={"connected": False, "drop_positions": True})
            hold(max(a.chaos_cut_seconds, 70), intact("(b) connected=false snapshots"))
            px.set()
            time.sleep(10)
            exposure_intact(ctx, copy, "(b) after the proxy rewrite stopped")
        ctx.note("(b) connected=false + empty positions for >70 s were ignored")

    try:
        ctx.cut(ctx.slave, "broker")
    except Skip as e:
        ctx.note(f"(c) skipped: {e}")
        close_and_mirror(ctx, copy, sym)
        return
    wait_for("slave terminal reports no broker connection", lambda: not ctx.slave.fresh_status()["connected"], 180, 2)
    ctx.master.must("close", ticket=_master_ticket(ctx, sym))
    ctx.wait_copy_state(copy["id"], {"closing"}, 30)

    def slave_holds() -> None:
        check(len(ctx.slave_pos(copy["id"])) == 1, "slave position vanished while its terminal was offline")
        st = copy_row(ctx, copy["id"])["state"]
        check(st in ("closing", "open"), f"copy is {st} while the slave cannot execute the close")

    hold(a.chaos_cut_seconds, slave_holds)
    cl = copy_commands(ctx, copy["id"], "close")
    attempts = max((c.get("attempts") or 1) for c in cl) if cl else 0
    ctx.slave.uncut()
    wait_for("slave terminal back on the broker", lambda: ctx.slave.fresh_status()["connected"], 150, 3)
    ctx.wait_slave_gone(copy["id"], timeout=150)
    c = ctx.wait_copy_state(copy["id"], {"closed"}, 90)
    check(c["close_reason"] == "master_closed", f"close_reason {c['close_reason']} != master_closed")
    n_retry = len([e for e in new_events_of(ctx, "command.retry") if e["payload"].get("copy_id") == copy["id"]])
    check(n_retry <= 12, f"retry storm: {n_retry} retries of the close in {a.chaos_cut_seconds:.0f}s")
    ctx.note(f"(c) slave broker outage during the master close: closed after reconnect "
             f"({attempts} attempt(s) while offline, {n_retry} retries)")


# 4 -----------------------------------------------------------------------------------------------
@scenario(slow=True, group="chaos")
def s_chaos_slave_side_close(ctx: Ctx) -> None:
    """The copied position is closed on the slave (by hand, then by a stop-loss) while the master stays open: the
    copy is marked closed with a slave close reason, nothing re-opens, nothing closes twice, and the master's later
    close is a no-op."""
    a = ctx.args
    sym = a.symbol
    copy, pos = open_and_mirror(ctx, sym, "buy", 0.01, "sclose")
    ctx.slave.must("close", ticket=pos["ticket"])
    c = ctx.wait_copy_state(copy["id"], {"closed"}, 60)
    ctx.note(f"manual slave close -> copy closed, close_reason={c['close_reason']}")
    check(c["close_reason"] != "master_closed" and c["close_reason"], f"close_reason {c['close_reason']!r} names no slave source")
    time.sleep(20)   # a re-open or a second close would show up now
    check(len(ctx.new_copies(sym)) == 1, f"a new copy appeared after the slave-side close: "
          f"{[(x['id'], x['state']) for x in ctx.new_copies(sym)]}")
    check(not ctx.slave_pos(copy["id"]), "slave position came back")
    check(len(ctx.slave_in_deals(c)) == 1, "re-opened: more than one entry deal")
    check(len(exit_deals(ctx, ctx.slave, pos["identifier"])) == 1, "more than one exit deal for the position")
    live = [x for x in copy_commands(ctx, copy["id"]) if x["state"] not in ("done", "superseded", "expired", "failed", "skipped")]
    check(not live, f"commands still live after the copy closed: {[(x['action'], x['state']) for x in live]}")
    n_cmds = len(copy_commands(ctx, copy["id"]))
    ctx.master.must("close", ticket=_master_ticket(ctx, sym))
    wait_for("master flat", lambda: not ctx.master.fresh_status()["positions"], 30, 1)
    time.sleep(20)
    c2 = copy_row(ctx, copy["id"])
    check(c2["state"] == "closed" and c2["close_reason"] == c["close_reason"],
          f"master's later close changed the copy: {c2['state']}/{c2['close_reason']}")
    check(len(copy_commands(ctx, copy["id"])) == n_cmds, "master's later close issued new commands (not a no-op)")
    check(len(exit_deals(ctx, ctx.slave, pos["identifier"])) == 1, "double close on the slave")
    check(len(ctx.new_copies(sym)) == 1, "extra copies after the master close")

    # (b) the broker closes the slave position on a stop-loss or take-profit (best effort: needs a tick)
    copy2, pos2 = open_and_mirror(ctx, sym, "buy", 0.01, "sclose-sl")
    q = ctx.slave.must("quote", symbol=pos2["symbol"])
    point = 10 ** -int(q["digits"])
    sl = round(q["bid"] - 2 * point, int(q["digits"]))
    tp = round(q["bid"] + 2 * point, int(q["digits"]))   # whichever side the next tick takes
    m = ctx.slave.send("modify", ticket=pos2["ticket"], sl=sl, tp=tp)
    if not m.get("ok"):
        ctx.note(f"(b) SL/TP not accepted on the slave ({m.get('retcode_text') or m.get('error')}): skipped")
    else:
        try:
            wait_for("slave position stopped out", lambda: not ctx.slave_pos(copy2["id"]), 90, 1)
        except Fail:
            ctx.note("(b) price never touched the 2-point SL/TP within 90 s: skipped")
        else:
            c3 = ctx.wait_copy_state(copy2["id"], {"closed"}, 60)
            ctx.note(f"(b) slave SL/TP hit -> copy closed, close_reason={c3['close_reason']}")
            check(c3["close_reason"] in ("slave_sl", "slave_tp"), f"close_reason {c3['close_reason']} is not slave_sl/slave_tp")
            check(c3["close_reason"] != "master_closed", f"close_reason {c3['close_reason']} names no slave source")
            time.sleep(15)
            check(len(ctx.new_copies(sym)) == 2, "re-open after the slave stop-loss")
            check(not ctx.slave_pos(copy2["id"]), "slave position came back after the stop-loss")
    ctx.master.must("close", ticket=_master_ticket(ctx, sym))
    ctx.wait_copy_state(copy2["id"], {"closed"}, 60)


# 5 -----------------------------------------------------------------------------------------------
def _link(ctx: Ctx) -> dict:
    return next(x for x in ctx.admin.get("/admin/links")["links"] if x["id"] == ctx.link_id)


def _patch_link_restoring(ctx: Ctx, **params: Any) -> None:
    link = _link(ctx)
    before = {k: link[k] for k in params}
    ctx.admin.patch(f"/admin/links/{ctx.link_id}", params)
    ctx.on_cleanup("restore link parameters", lambda: ctx.admin.patch(f"/admin/links/{ctx.link_id}", before))


def _reject_probe(ctx: Ctx, symbol: str) -> str | None:
    """Try one lot (one share on a stock CFD) on the slave: returns the broker's reject text when the symbol cannot
    trade right now, None when it can (the probe position is closed again) or does not exist."""
    for _ in range(3):   # a symbol just added to Market Watch has no tick for a moment
        if ctx.slave.send("quote", symbol=symbol).get("ok"):
            break
        time.sleep(1.5)
    else:
        return None
    r = ctx.slave.send("open", symbol=symbol, side="buy", volume=1.0, magic=777005, comment="probe-reject")
    if r.get("ok"):
        for p in ctx.slave.fresh_status()["positions"]:
            if p["comment"] == "probe-reject":
                ctx.slave.send("close", ticket=p["ticket"])
        return None
    return str(r.get("retcode_text") or r.get("error"))


@scenario(slow=True, group="chaos")
def s_chaos_slave_reject(ctx: Ctx) -> None:
    """Orders the slave's broker rejects: (a) a copy far beyond the slave's margin (link multiplier 10000) and
    (b) a symbol that is closed right now (symbol map to a stock CFD): the copy ends skipped/error/cancelled with a
    reason, the slave holds no position, retries stay bounded and nothing is left uncertain."""
    a = ctx.args
    sym = a.symbol
    outcomes: list[str] = []

    def one(label: str, tag: str) -> None:
        known = {c["id"] for c in ctx.new_copies(sym)}
        ctx.master_open(sym, "buy", 0.01, tag)
        copy = wait_for(f"{label}: a new copy", lambda: next((c for c in ctx.new_copies(sym) if c["id"] not in known),
                                                             None), 30)
        c = wait_for(f"{label}: copy settled", lambda: (r := copy_row(ctx, copy["id"])) and
                     r["state"] in ("open", "skipped", "error", "cancelled", "closed", "uncertain") and r, 90, 2)
        if c["state"] == "open":
            ctx.note(f"{label}: the broker ACCEPTED the order (copy open); not a reject case")
            outcomes.append(f"{label}: accepted")
        else:
            check(c["state"] in ("skipped", "error", "cancelled"), f"{label}: copy ended {c['state']} (uncertain/closed?)")
            reason = c["skip_reason"] or c["close_reason"]
            check(bool(reason), f"{label}: copy {c['state']} without a reason")
            check(not ctx.slave_pos(copy["id"]), f"{label}: slave holds a position of a rejected copy")
            outcomes.append(f"{label}: {c['state']} ({reason})")
            ctx.note(f"{label}: copy {copy['id']} -> {c['state']} ({reason})")
        n0 = len([e for e in new_events_of(ctx, "command.retry") if e["payload"].get("copy_id") == copy["id"]])
        cmds0 = len(copy_commands(ctx, copy["id"]))
        check(n0 <= 3, f"{label}: {n0} retries of a rejected open")
        time.sleep(20)   # a retry storm would grow now
        n1 = len([e for e in new_events_of(ctx, "command.retry") if e["payload"].get("copy_id") == copy["id"]])
        check(n1 == n0 and len(copy_commands(ctx, copy["id"])) == cmds0, f"{label}: commands keep being issued ({n0}->{n1} retries)")
        # the master closes its (still open) position: for a settled copy this must be a no-op
        if c["state"] == "open":
            close_and_mirror(ctx, copy, sym)
        else:
            ctx.master.must("close", ticket=_master_ticket(ctx, sym))
            time.sleep(8)
            check(copy_row(ctx, copy["id"])["state"] == c["state"], f"{label}: master close changed a settled copy")

    # (a) margin / volume
    _patch_link_restoring(ctx, lot_mode="multiplier", lot_value="10000")
    one("(a) huge lot", "rej-lot")
    ctx.admin.patch(f"/admin/links/{ctx.link_id}", {"lot_mode": "master", "lot_value": None})

    # (b) a symbol that cannot trade right now
    closed = None
    for cand in a.reject_symbols:
        why = _reject_probe(ctx, cand)
        if why:
            closed = (cand, why)
            break
    if closed is None:
        ctx.note(f"(b) skipped: none of {a.reject_symbols} rejects an order right now (all open or unknown)")
    else:
        cand, why = closed
        ctx.note(f"(b) slave symbol {cand} rejects orders now: {why}")
        _patch_link_restoring(ctx, allow_contract_size_diff=True, lot_mode="fixed", lot_value="1")
        m = ctx.admin.post("/admin/symbol_maps", {"slave_id": ctx.slave_id, "master_symbol": sym, "slave_symbol": cand})
        ctx.on_cleanup("delete symbol map", lambda: ctx.admin.delete(f"/admin/symbol_maps/{m['id']}"))
        one(f"(b) closed symbol {cand}", "rej-closed")
    if all(o.endswith("accepted") for o in outcomes):
        raise Skip(f"no variant produced a reject: {outcomes}")


# 6 -----------------------------------------------------------------------------------------------
@scenario(slow=True, group="chaos")
def s_chaos_partial_restart(ctx: Ctx) -> None:
    """A partial close executes on the slave, its result is held back (429 on /v4/slave/results) and the slave
    terminal dies before it is reported: after the restart the volume is exactly the reduced one (no second
    partial), the result is replayed once the link works, and the next partial and the close still converge."""
    sym = ctx.args.symbol
    copy, _ = open_and_mirror(ctx, sym, "buy", 0.03, "prestart")
    with Proxy(ctx, "--rate-limit", "/v4/slave/results=3600"):
        ctx.master.must("close_partial", ticket=_master_ticket(ctx, sym), volume=0.01)
        ctx.wait_slave_pos(copy["id"], lambda p: abs(p["volume"] - 0.02) < 1e-9, "volume 0.02")
        parts = copy_commands(ctx, copy["id"], "close_partial")
        ctx.note(f"slave reduced to 0.02; partial command state at the server: {[c['state'] for c in parts]}")
        ctx.slave.kill_terminal()
        ctx.slave.start_terminal()
        time.sleep(20)   # a re-executed partial would show now
        ps = ctx.slave.fresh_status() and ctx.slave_pos(copy["id"])
        check(len(ps) == 1 and abs(ps[0]["volume"] - 0.02) < 1e-9,
              f"after the restart the slave holds {[p['volume'] for p in ps]} (expected [0.02])")
    # proxy gone, but the EA honours the 3600 s Retry-After it was given: reload it so the outbox replays now
    ctx.slave.kill_terminal()
    ctx.slave.start_terminal()

    def converged() -> dict | None:
        r = copy_row(ctx, copy["id"])
        parts = copy_commands(ctx, copy["id"], "close_partial")
        done = parts and all(c["state"] == "done" for c in parts)
        return r if (r["state"] == "open" and r["confirmed_volume"] is not None and
                     abs(float(r["confirmed_volume"]) - 0.02) < 1e-9 and done) else None
    wait_for("server confirmed volume 0.02 and the partial is done", converged, 120, 2)
    ps = ctx.slave_pos(copy["id"])
    check(len(ps) == 1 and abs(ps[0]["volume"] - 0.02) < 1e-9, f"slave volume {[p['volume'] for p in ps]} after replay")
    ctx.master.must("close_partial", ticket=_master_ticket(ctx, sym), volume=0.01)
    ctx.wait_slave_pos(copy["id"], lambda p: abs(p["volume"] - 0.01) < 1e-9, "volume 0.01")
    time.sleep(8)
    check(len(ctx.slave_pos(copy["id"])) == 1 and abs(ctx.slave_pos(copy["id"])[0]["volume"] - 0.01) < 1e-9,
          "second partial did not converge to 0.01")
    check(len(ctx.new_copies(sym)) == 1, "extra copies")
    close_and_mirror(ctx, copy, sym)


# 7 -----------------------------------------------------------------------------------------------
def _open_legs(ctx: Ctx, tag: str, n: int = 3) -> list[dict]:
    legs = [(s, "buy" if i % 2 == 0 else "sell") for i, s in enumerate(ctx.args.symbols[:n])]
    check(len(legs) >= 3, "mass close needs three symbols (--symbols)")
    for s, side in legs:
        ctx.master_open(s, side, 0.01, f"{tag}-{s}")
    copies = []
    for s, _ in legs:
        c = wait_for(f"copy for {s} open", lambda s=s: next((c for c in ctx.new_copies(s) if c["state"] == "open"
                     and c["id"] not in {x["id"] for x in copies}), None), ctx.timeout, 1)
        ctx.wait_slave_pos(c["id"])
        copies.append(c)
    return copies


@scenario(slow=True, group="chaos")
def s_chaos_mass_close(ctx: Ctx) -> None:
    """Three master positions vanish at once. (a) A real close_all: the exit deals close all three copies on the fast
    path, no mass-disappearance alert. (b) The position list goes empty in a connected, history-synced snapshot with
    no exit deals (a terminal glitch, simulated by the fault proxy while the positions stay open): the guard latches
    (alert), nothing closes for longer than the normal 60 s absence timer, and when the positions come back the
    episode resets. (c) The same empty list with history_synced=false is held, not counted. A final close_all
    still closes everything on the fast path."""
    a = ctx.args
    legs = a.symbols[:3]
    check(len(legs) >= 3, "mass close needs three symbols (--symbols)")

    # (a) fast path
    copies = _open_legs(ctx, "mass-a")
    t0 = time.monotonic()
    ctx.master.must("close_all", magic=a.magic)
    for c in copies:
        ctx.wait_slave_gone(c["id"], timeout=60)
        ctx.wait_copy_state(c["id"], {"closed"}, 30)
    srcs = close_reason_events(ctx)
    check(srcs == {"history": 3}, f"(a) close sources {srcs}, expected 3 x history")
    check(not new_events_of(ctx, "master.mass_disappearance"), "(a) mass-disappearance alert on a clean close_all")
    ctx.note(f"(a) 3 copies closed via history deals in {time.monotonic() - t0:.0f}s")

    if ctx.master.remote or ctx.master.direct:
        raise Skip("(b)/(c) need the fault proxy in front of the master (local master only); (a) passed")

    def last_event_id() -> int:
        return max([e["id"] for e in ctx.new_events()] or [ctx.event_floor])

    with Proxy(ctx, term=ctx.master, port=a.master_proxy_port) as px:
        copies = _open_legs(ctx, "mass-b")
        floor = last_event_id()

        def untouched(what: str) -> None:
            for c in copies:
                check(copy_row(ctx, c["id"])["state"] == "open", f"{what}: copy {c['id']} left 'open'")
                check(len(ctx.slave_pos(c["id"])) == 1, f"{what}: slave position of copy {c['id']} closed")
            closed = [e["type"] for e in ctx.new_events() if e["id"] > floor and e["type"] == "master_position.closed"]
            check(not closed, f"{what}: master_position.closed {closed}")

        # (b) glitch: connected + history_synced, positions gone, no exit deals
        px.set(snapshot={"drop_positions": True})
        ev = wait_for("master.mass_disappearance event",
                      lambda: [e for e in ctx.new_events() if e["id"] > floor and e["type"] == "master.mass_disappearance"],
                      45, 2)
        check((ev[0]["payload"] or {}).get("count") == 3, f"(b) the episode covers {ev[0]['payload']}")
        hold(75, lambda: untouched("(b) during the guard hold"))   # a plain absence would have closed them at ~60 s
        px.set()
        time.sleep(12)
        untouched("(b) after the positions came back")
        back = [e for e in ctx.new_events() if e["id"] > floor and e["type"] == "master_position.reappeared_before_close"]
        check(len(back) == 3, f"(b) expected 3 reappeared_before_close events, got {len(back)}")
        ctx.note("(b) mass guard latched, held 75 s (> the 60 s absence timer) and reset when the positions returned")

        # (c) unsynced history: not evidence at all
        floor = last_event_id()
        px.set(snapshot={"history_synced": False, "drop_positions": True})

        def unsynced() -> None:
            untouched("(c) unsynced snapshots")
            bad = [e["type"] for e in ctx.new_events() if e["id"] > floor and e["type"].startswith(("master_position.", "master."))]
            check(not bad, f"(c) absence bookkeeping on unsynced snapshots: {bad}")

        hold(max(a.chaos_cut_seconds, 70), unsynced)
        px.set()
        time.sleep(10)
        unsynced()
        ctx.note("(c) history_synced=false + empty list for >70 s: nothing counted, nothing closed")

    ctx.master.must("close_all", magic=a.magic)
    for c in copies:
        ctx.wait_slave_gone(c["id"], timeout=60)
        ctx.wait_copy_state(c["id"], {"closed"}, 30)


# 8 -----------------------------------------------------------------------------------------------
@scenario(slow=True, group="chaos")
def s_chaos_clock_skew(ctx: Ctx) -> None:
    """EA clocks skewed by +/-90 s (the fault proxy shifts `server_time` in replies, which is how the EA learns its
    offset): a slave whose clock reads the server 90 s ahead refuses the open as expired (copy cancelled, no
    exposure); one 90 s behind still executes; a skewed master still gets its close mirrored."""
    a = ctx.args
    if ctx.slave.direct or ctx.master.remote or ctx.master.direct:
        raise Skip("needs the fault proxy in front of both EAs (local pair behind forwarders)")
    sym = a.symbol
    shift = 90_000
    with Proxy(ctx, term=ctx.slave) as sp, Proxy(ctx, term=ctx.master, port=a.master_proxy_port) as mp:
        # slave thinks the server is 90 s ahead: every open looks past its 30 s TTL
        sp.set(server_time_shift_ms=shift)
        time.sleep(8)   # the offset refreshes on the next reply
        ctx.master_open(sym, "buy", 0.01, "skew-a")
        copy = wait_for("copy for skew-a", lambda: (ctx.new_copies(sym) or [None])[-1], 30)
        c = wait_for("copy settled", lambda: (r := copy_row(ctx, copy["id"])) and r["state"] in
                     ("cancelled", "open", "error", "skipped") and r, 60, 2)
        ctx.note(f"slave clock +90 s: copy {c['state']} ({c['close_reason'] or c['skip_reason']})")
        check(c["state"] in ("cancelled", "error", "skipped"), f"open executed although it looked expired: {c['state']}")
        check(not ctx.slave_pos(copy["id"]), "slave holds a position for an open it judged expired")
        ctx.master.must("close", ticket=_master_ticket(ctx, sym))
        time.sleep(8)
        check(copy_row(ctx, copy["id"])["state"] == c["state"], "master close changed a cancelled copy")
        sp.set()

        # slave 90 s behind: the open is fresh in its view and executes
        sp.set(server_time_shift_ms=-shift)
        time.sleep(8)
        copy_b, _ = open_and_mirror(ctx, sym, "buy", 0.01, "skew-b")
        close_and_mirror(ctx, copy_b, sym)
        ctx.note("slave clock -90 s: open and close mirrored normally")
        sp.set()

        # master clocks: close detection compares deal time with the generation start using that offset
        for sign in (1, -1):
            mp.set(server_time_shift_ms=sign * shift)
            time.sleep(8)
            copy_c, _ = open_and_mirror(ctx, sym, "buy", 0.01, f"skew-m{'p' if sign > 0 else 'n'}")
            t0 = time.monotonic()
            ctx.master.must("close", ticket=_master_ticket(ctx, sym))
            ctx.wait_slave_gone(copy_c["id"], timeout=150)
            cc = ctx.wait_copy_state(copy_c["id"], {"closed"}, 30)
            check(cc["close_reason"] == "master_closed", f"close_reason {cc['close_reason']}")
            ctx.note(f"master clock {'+' if sign > 0 else '-'}90 s: slave closed after {time.monotonic() - t0:.0f}s "
                     f"(sources so far {close_reason_events(ctx)})")
        mp.set()
    check(len([c for c in ctx.new_copies(sym)]) == 4, f"unexpected copy count {len(ctx.new_copies(sym))} (expected 4)")


# 9 -----------------------------------------------------------------------------------------------
@scenario(slow=True, group="chaos")
def s_chaos_long_outage(ctx: Ctx) -> None:
    """The slave terminal is down for --outage-seconds (default 10 min) while the master closes one copied
    position, opens another and leaves it open, and opens+closes a third: on return the close is executed, the
    stale open is cancelled by its TTL without ever executing, the never-delivered open was cancelled when the
    master closed it, and the slave ends flat."""
    a = ctx.args
    s0, s1, s2 = (a.symbols + a.symbols)[:3] if len(a.symbols) < 3 else a.symbols[:3]
    if a.outage_seconds < 60:
        raise Skip(f"--outage-seconds {a.outage_seconds:.0f} is below the open TTL window; use >= 60")
    c0, p0 = open_and_mirror(ctx, s0, "buy", 0.01, "out0")
    ctx.on_cleanup("restart slave", lambda: ctx.slave.start_terminal() if ctx.slave.state() != "running" else None)
    ctx.slave.stop_container()
    t_down = time.monotonic()
    ctx.note(f"slave container stopped; outage {a.outage_seconds:.0f}s")
    ctx.master.must("close", ticket=_master_ticket(ctx, s0))                    # P0: close queued
    c0r = wait_for("P0 close issued", lambda: (r := copy_row(ctx, c0["id"])) and r["state"] == "closing" and r, 30, 1)
    ctx.master_open(s1, "sell", 0.01, "out1")                                   # P1: stays open on the master
    c1 = wait_for("P1 copy", lambda: (ctx.new_copies(s1) or [None])[-1], 30)
    ctx.master_open(s2, "buy", 0.01, "out2")                                    # P2: opened and closed meanwhile
    c2 = wait_for("P2 copy", lambda: (ctx.new_copies(s2) or [None])[-1], 30)
    ctx.master.must("close", ticket=_master_ticket(ctx, s2))
    wait_for("P2 copy cancelled (open never delivered)", lambda: copy_row(ctx, c2["id"])["state"] == "cancelled", 30, 1)
    ctx.note(f"during the outage: P0 {c0r['state']}, P1 {copy_row(ctx, c1['id'])['state']}, "
             f"P2 {copy_row(ctx, c2['id'])['state']}")

    def while_down() -> None:
        check(copy_row(ctx, c1["id"])["state"] == "pending", "P1 open left 'pending' state while the slave is down "
              "(expiry needs the slave's poll)")
        check(copy_row(ctx, c0["id"])["state"] == "closing", "P0 close completed without a slave")
    while time.monotonic() - t_down < a.outage_seconds:
        while_down()
        time.sleep(15)
    ctx.slave.start_terminal()
    ctx.note(f"slave back after {time.monotonic() - t_down:.0f}s")
    ctx.wait_slave_gone(c0["id"], timeout=120)
    ctx.wait_copy_state(c0["id"], {"closed"}, 60)
    r1 = wait_for("P1 copy cancelled by its TTL", lambda: (r := copy_row(ctx, c1["id"])) and r["state"] in
                  ("cancelled", "open", "error", "skipped") and r, 90, 2)
    check(r1["state"] == "cancelled" and r1["close_reason"] == "open_expired",
          f"stale open P1 ended {r1['state']}/{r1['close_reason']} (expected cancelled/open_expired)")
    time.sleep(10)
    check(not ctx.slave_pos(c1["id"]) and not ctx.slave_pos(c2["id"]), "a stale open executed on the slave")
    check(not ctx.slave_in_deals(r1) and not ctx.slave_in_deals(copy_row(ctx, c2["id"])), "entry deals exist for cancelled opens")
    cmds0 = copy_commands(ctx, c0["id"])
    order = [(c["action"], c["state"]) for c in sorted(cmds0, key=lambda c: c["seq_in_copy"])]
    check(order == [("open", "done"), ("close", "done")], f"P0 commands {order}")
    flat = ctx.slave.fresh_status()["positions"]
    check(not [p for p in flat if p["magic"] == a.magic], f"slave not flat: {flat}")
    ctx.master.must("close", ticket=_master_ticket(ctx, s1))   # P1's master close: no-op for the cancelled copy
    time.sleep(10)
    check(copy_row(ctx, c1["id"])["state"] == "cancelled", "master close changed the cancelled copy")
    check(not [p for p in ctx.slave.fresh_status()["positions"] if p["magic"] == a.magic],
          "slave got a position after the master close")


# 10 ----------------------------------------------------------------------------------------------
def _server_pids(ctx: Ctx) -> list[str]:
    return sh(["pgrep", "-f", ctx.args.server_match]).stdout.split()


def stop_server(ctx: Ctx) -> None:
    pids = _server_pids(ctx)
    check(bool(pids), f"no server process matching {ctx.args.server_match!r}")
    for pid in pids:
        os.kill(int(pid), signal.SIGTERM)
    wait_for("server down", lambda: not ctx.admin.health(), 30, 0.5)


def start_server(ctx: Ctx) -> None:
    subprocess.Popen(["bash", "-c", ctx.args.server_restart_cmd], start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_for("server healthy", ctx.admin.health, 60, 1)


@scenario(slow=True, group="chaos")
def s_chaos_db_rollback(ctx: Ctx) -> None:
    """The (local, SQLite) server database is restored to a snapshot taken BEFORE two copies existed while both EAs
    keep running: the copy ids are reused (the c<id> collision class). After settling there must be exactly one
    slave position per open master position, at most one live copy per master position, no orphan, and a master
    close_all must leave the slave flat."""
    a = ctx.args
    if not a.server_db or not a.server_restart_cmd:
        raise Skip("needs --server-db (a LOCAL SQLite server database) and --server-restart-cmd; never run against KS1")
    import re
    import sqlite3
    import shutil
    db = Path(a.server_db)
    check(db.exists(), f"{db} not found")
    snap = a.out_dir / f"db-before-{int(time.time())}.sqlite"
    with sqlite3.connect(str(db)) as src, sqlite3.connect(str(snap)) as dst:
        src.backup(dst)
    ctx.note(f"database snapshot {snap.name} ({snap.stat().st_size} bytes)")
    s0, s1 = a.symbols[0], (a.symbols[1] if len(a.symbols) > 1 else a.symbols[0])
    ca, pa = open_and_mirror(ctx, s0, "buy", 0.01, "rb-a")
    cb, pb = open_and_mirror(ctx, s1, "sell", 0.01, "rb-b")
    before = sorted((c["id"], c["state"]) for c in ctx.new_copies())
    ctx.note(f"before the rollback: copies {before}")
    stop_server(ctx)
    shutil.copyfile(snap, db)
    for suffix in ("-wal", "-shm"):
        Path(str(db) + suffix).unlink(missing_ok=True)
    start_server(ctx)
    ctx.note("database rolled back and the server restarted")
    # the slave EA must come back to a consistent state on its own
    time.sleep(a.timeout + 45)
    mp = {str(p["identifier"]): p for p in ctx.master.fresh_status()["positions"] if p["magic"] == a.magic}
    check(len(mp) == 2, f"master positions {sorted(mp)}")
    sp = [p for p in ctx.slave.fresh_status()["positions"] if p["magic"] == a.magic]
    by_master: dict[str, list[dict]] = {}
    for p in sp:
        m = re.match(r"c(\d+)-(\d+)$", p["comment"] or "")
        by_master.setdefault(m.group(2) if m else "?", []).append(p)
    ctx.note(f"slave positions per master position: { {k: [(x['comment'], x['volume']) for x in v] for k, v in by_master.items()} }")
    copies = ctx.admin.copies(link_id=ctx.link_id, limit=500)
    live = [c for c in copies if c["state"] in EXPOSURE or (c["state"] == "superseded" and c["close_intent"])]
    ctx.note(f"live copies after the rollback: {[(c['id'], c['state'], c['position_id']) for c in live]}")
    problems = []
    for pid in mp:
        n = len(by_master.get(pid, []))
        if n != 1:
            problems.append(f"master position {pid}: {n} slave positions")
    extra = [k for k in by_master if k not in mp]
    if extra:
        problems.append(f"slave positions for unknown master positions: {extra}")
    owned = {str(c["position_id"]) for c in live if c["position_id"] is not None}
    unmanaged = [p for p in sp if str(p["identifier"]) not in owned]
    if unmanaged:
        problems.append(f"slave positions no live copy manages: {[(p['comment'], p['ticket']) for p in unmanaged]}")
    check(not problems, "; ".join(problems))
    ctx.master.must("close_all", magic=a.magic)
    wait_for("slave flat after the master close_all", lambda: not [p for p in ctx.slave.fresh_status()["positions"]
             if p["magic"] == a.magic], 90, 2)


# 11 ----------------------------------------------------------------------------------------------
@scenario(slow=True, group="chaos")
def s_chaos_slave_suspend(ctx: Ctx) -> None:
    """Slave account suspended (admin PATCH) while copies are open: it drains. (a) open copies stay managed, a new
    master open is skipped (account_drain) and resuming while exposure remains works at once; (b) after suspending
    again the master's closes still reach the slave, the flat slave is then refused (403) and, once reactivated, the
    EA comes back on its own (its blocked-state config check runs every 5 min) and mirrors a new open."""
    a = ctx.args
    s0, s1, s2 = (a.symbols + a.symbols + a.symbols)[:3]
    path = f"/admin/accounts/{ctx.slave_id}"

    def suspend() -> None:
        ctx.admin.patch(path, {"status": "suspended", "suspended_reason": "chaos"})
        check(ctx.admin.account(ctx.slave_id)["status"] == "suspended", "account not suspended")

    def resume() -> None:
        ctx.admin.patch(path, {"status": "active"})
        check(ctx.admin.account(ctx.slave_id)["status"] == "active", "account not active")

    ctx.on_cleanup("reactivate slave", resume)

    # (a) drain with exposure, resume with exposure
    ca, _ = open_and_mirror(ctx, s0, "buy", 0.01, "susp-a")
    cb, _ = open_and_mirror(ctx, s1, "sell", 0.01, "susp-b")
    suspend()
    time.sleep(10)
    for c in (ca, cb):
        check(copy_row(ctx, c["id"])["state"] == "open", f"copy {c['id']} changed on suspension")
        check(len(ctx.slave_pos(c["id"])) == 1, f"slave position of copy {c['id']} closed on suspension")
    ctx.master_open(s2, "buy", 0.01, "susp-c")
    cc = wait_for("copy for the open made while suspended", lambda: (ctx.new_copies(s2) or [None])[-1], 30)
    r = wait_for("drained copy settled", lambda: (x := copy_row(ctx, cc["id"])) and x["state"] != "pending" and x, 30, 1)
    check(r["state"] == "skipped" and r["skip_reason"] == "account_drain",
          f"open while suspended: {r['state']}/{r['skip_reason']}")
    check(not ctx.slave_pos(cc["id"]), "slave opened a position while suspended")
    ctx.note("(a) suspended: open copies untouched, new open skipped (account_drain)")
    resume()
    ctx.master.must("close", ticket=_master_ticket(ctx, s2))   # the skipped copy's master closes: no-op
    ctx.master_open(s2, "sell", 0.01, "susp-c2")
    cc2 = wait_for("copy opened right after resuming", lambda: next((c for c in ctx.new_copies(s2) if c["id"] != cc["id"]), None), 30)
    ctx.wait_copy_state(cc2["id"], {"open"}, 60)
    ctx.wait_slave_pos(cc2["id"])
    ctx.note("(a) resumed with exposure still open: the next open was mirrored at once")
    ctx.master.must("close", ticket=_master_ticket(ctx, s2))
    ctx.wait_slave_gone(cc2["id"], timeout=60)

    # (b) full drain: closes still flow, then 403, then recovery after reactivation
    suspend()
    ctx.master.must("close", ticket=_master_ticket(ctx, s0))
    ctx.wait_slave_gone(ca["id"], timeout=60)
    ctx.wait_copy_state(ca["id"], {"closed"}, 30)
    ctx.master.must("close", ticket=_master_ticket(ctx, s1))
    ctx.wait_slave_gone(cb["id"], timeout=60)
    ctx.wait_copy_state(cb["id"], {"closed"}, 30)
    ctx.note("(b) drain: both closes were mirrored while suspended")
    time.sleep(15)   # the flat slave is refused with 403 now and its EA blocks itself
    t_resume = time.time()
    resume()

    def seen_again() -> bool:
        ls = ctx.admin.account(ctx.slave_id)["last_seen_at"]
        if not ls:
            return False
        from datetime import datetime, timezone
        dt = datetime.fromisoformat(ls)
        dt = dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
        return dt.timestamp() > t_resume
    wait_for("slave EA calls the server again after reactivation", seen_again, 380, 5)
    t_back = time.time() - t_resume
    time.sleep(8)   # session + first poll
    ctx.master_open(s0, "buy", 0.01, "susp-d")
    cd = wait_for("copy after resume", lambda: (ctx.new_copies(s0) or [None])[-1] if len(ctx.new_copies(s0)) >= 2 else None, 30)
    ctx.wait_copy_state(cd["id"], {"open"}, 120)
    ctx.wait_slave_pos(cd["id"])
    ctx.note(f"(b) reactivated: the slave EA was back {t_back:.0f}s later and mirrored the new open")
    close_and_mirror(ctx, cd, s0)
    check(len(ctx.new_copies(s0)) == 2 and len(ctx.new_copies(s1)) == 1, "unexpected copy counts")


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
    ap.add_argument("--group", choices=["core", "chaos", "all"], default="core",
                    help="scenario group when no names are given: core (default), chaos (error scenarios: restarts, "
                         "network and broker loss, rejects, outages, DB rollback, suspension) or all")
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
    ap.add_argument("--chaos-cut-seconds", type=float, default=75.0,
                    help="chaos group: how long master/slave lose the server or the broker (60-90 s is the useful range:"
                         " above the server's 60 s absence timer, below MASTER_STALE_SECONDS)")
    ap.add_argument("--outage-seconds", type=float, default=600.0,
                    help="chaos long_outage: how long the slave terminal stays down (default 10 min)")
    ap.add_argument("--slave-direct", action="store_true", default=env.get("E2E_SLAVE_DIRECT") == "1",
                    help="the slave EA talks to the server itself (https): no forwarder, no fault proxy for it; "
                         "network cuts use nftables on the server address")
    ap.add_argument("--master-network", default=env.get("E2E_MASTER_NETWORK", "bridge"),
                    help="docker network a remote master is disconnected from for 'all' network cuts")
    ap.add_argument("--server-db", type=Path, default=env.get("E2E_SERVER_DB"),
                    help="SQLite file of a LOCAL server: enables db_rollback (never point this at a shared server)")
    ap.add_argument("--reject-symbols", default=env.get("E2E_REJECT_SYMBOLS", "AAPL,MSFT,TSLA,NVDA,AMZN,GOOGL,META"),
                    help="chaos slave_reject: candidate slave symbols that may be closed right now (market-closed reject)")
    ap.add_argument("--rate-limit-wait", type=float, default=60.0,
                    help="wait for the held result after removing the 429 proxy before reloading the slave")
    ap.add_argument("--proxy-host", default="172.17.0.1")
    ap.add_argument("--proxy-port", type=int, default=8098, help="fault proxy port in front of the slave")
    ap.add_argument("--master-proxy-port", type=int, default=8097, help="fault proxy port in front of the master")
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
    a.reject_symbols = [s.strip() for s in a.reject_symbols.split(",") if s.strip()]
    a.latency_symbols = [s.strip() for s in a.latency_symbols.split(",") if s.strip()]
    return a


def main(argv: list[str] | None = None) -> int:
    a = build_args(argv)
    if a.list:
        for s in SCENARIOS:
            print(f"{s.name:26} {s.group:6} {'[slow] ' if s.slow else ''}{s.doc.splitlines()[0] if s.doc else ''}")
        return 0
    names = {s.name for s in SCENARIOS}
    unknown = [n for n in a.scenarios if n not in names]
    if unknown:
        print(f"unknown scenario(s): {unknown}; see --list", file=sys.stderr)
        return 2
    selected = [s for s in SCENARIOS
                if (s.name in a.scenarios if a.scenarios else a.group in ("all", s.group))
                and (not a.keyword or a.keyword in s.name) and not (a.fast and s.slow)]
    if not a.admin_token:
        print("ADMIN_TOKEN not set (use --admin-token, ADMIN_TOKEN or --env-file)", file=sys.stderr)
        return 2
    a.out_dir.mkdir(parents=True, exist_ok=True)
    ctx = Ctx(args=a, admin=Admin(a.server_url, a.admin_token),
              master=Terminal("master", a.master_container, a.master_prefix, a.master_dir, a.forward_host,
                              remote=Remote(a.master_ssh, Path.home() / ".ssh" / "tm-e2e") if a.master_ssh else None,
                              remote_files=a.master_files, remote_network=a.master_network),
              slave=Terminal("slave", a.slave_container, a.slave_prefix, a.slave_dir, a.forward_host,
                             direct=a.slave_direct),
              link_id=a.link_id, slave_id=a.slave_id, master_id=a.master_id, timeout=a.timeout)

    print(f"TradeMirror e2e: {len(selected)} scenario(s) against {a.server_url}", flush=True)
    problems = preconditions(ctx)
    if problems:
        print("PRECONDITIONS FAILED:\n  - " + "\n  - ".join(problems), file=sys.stderr)
        return 2
    for term in (ctx.master, ctx.slave):   # a table left by an aborted earlier run would keep the terminal cut
        try:
            term.uncut()
        except Exception as e:  # noqa: BLE001
            print(f"could not clear network faults on {term.role}: {e}", file=sys.stderr)
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
            undo_errs = ctx.run_undo()
            if undo_errs and status == "PASS":
                status, detail = "FAIL", "restore failed: " + "; ".join(undo_errs)
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
