"""Fault-injecting reverse proxy between a real TradeMirror EA and a real Copy Server.

The Strategy Tester cannot run WebRequest, so the live half of the EA client tests (design section 8:
S01-S05, S24-S26 "with a real HTTP fake server from a script outside the Tester") runs a demo terminal
against this proxy:

    EA (WebRequest) --> http://localhost:8080 (this proxy) --> Copy Server (http://127.0.0.1:8000)

Every EA request body is validated against the server's own Pydantic models (the v4 contract) and any
key the server would silently ignore is reported. Faults are injected per route:

    --drop-results N     forward the next N results posts, then drop the reply (S01: lost result)
    --drop-enroll N      forward enroll, drop the reply (S26)
    --drop-rotate N      forward token/rotate, drop the reply (S25)
    --rate-limit P=S     answer 429 with Retry-After S to every request whose path starts with P (S24)
    --fail-all-for S     answer 503 to everything for S seconds (network cut / server down)

Run from the repository root (uses the server's virtualenv for the models):

    uv run --project server python ea/mt5/tests/fault_proxy.py --upstream http://127.0.0.1:8000 \
        --port 8080 --drop-results 1

The EA's ServerUrl is then http://localhost:8080 (http is accepted for localhost only), and
http://localhost:8080 must be in the terminal's WebRequest allow-list. Violations and faults are
printed and kept in `proxy.violations` / `proxy.events`.
"""

from __future__ import annotations

import argparse
import json
import sys
import threading
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# Forward: (method, path_with_query, headers, body) -> (status, headers, body)
Forward = Callable[[str, str, dict[str, str], bytes], tuple[int, dict[str, str], bytes]]

HOP_HEADERS = {"connection", "keep-alive", "transfer-encoding", "content-length", "host"}


def _models():
    """The server's request models (the v4 contract). Imported lazily so the proxy also runs without
    validation when copycore is not importable."""
    server_dir = Path(__file__).resolve().parents[3] / "server"
    if str(server_dir) not in sys.path:
        sys.path.insert(0, str(server_dir))
    from copycore.routers.v4 import ConfirmIn, EnrollIn
    from copycore.routers.v4_copy import (
        PositionIn,
        ResultIn,
        ResultsIn,
        SessionIn,
        SnapshotIn,
        SymbolsIn,
    )

    return {
        ("POST", "/v4/enroll"): EnrollIn,
        ("POST", "/v4/session"): SessionIn,
        ("POST", "/v4/token/confirm"): ConfirmIn,
        ("PUT", "/v4/symbols"): SymbolsIn,
        ("POST", "/v4/master/snapshot"): SnapshotIn,
        ("POST", "/v4/slave/snapshot"): SnapshotIn,
        ("POST", "/v4/slave/results"): ResultsIn,
    }, {"positions": PositionIn, "results": ResultIn}


def unknown_keys(model, body: dict, nested: dict) -> list[str]:
    """Keys the server would ignore (or reject): a misspelled field is a silent contract bug."""
    out = [k for k in body if k not in model.model_fields]
    for key, sub in nested.items():
        if key in model.model_fields and isinstance(body.get(key), list):
            for i, item in enumerate(body[key]):
                if isinstance(item, dict):
                    out += [f"{key}[{i}].{k}" for k in item if k not in sub.model_fields]
    return out


@dataclass
class Faults:
    drop_results: int = 0
    drop_enroll: int = 0
    drop_rotate: int = 0
    rate_limit: dict[str, int] = field(default_factory=dict)
    fail_until: float = 0.0


@dataclass
class ProxyState:
    faults: Faults
    validate: bool = True
    violations: list[str] = field(default_factory=list)
    events: list[str] = field(default_factory=list)
    lock: threading.Lock = field(default_factory=threading.Lock)

    def note(self, kind: str, msg: str) -> None:
        with self.lock:
            (self.violations if kind == "violation" else self.events).append(msg)
        print(f"[proxy] {kind}: {msg}", flush=True)

    def take(self, attr: str) -> bool:
        with self.lock:
            n = getattr(self.faults, attr)
            if n > 0:
                setattr(self.faults, attr, n - 1)
                return True
            return False


def make_handler(state: ProxyState, forward: Forward):
    try:
        validators, nested = _models() if state.validate else ({}, {})
    except ImportError as exc:  # pragma: no cover - only without the server venv
        print(f"[proxy] validation disabled ({exc})", flush=True)
        validators, nested = {}, {}

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):  # quiet default logging
            pass

        def _reply(self, status: int, headers: dict[str, str], body: bytes) -> None:
            self.send_response(status)
            for k, v in headers.items():
                if k.lower() not in HOP_HEADERS:
                    self.send_header(k, v)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _lose(self, what: str) -> None:
            state.note("fault", f"{what}: forwarded, reply dropped")
            self.close_connection = True  # no status line: the EA sees a network error

        def _handle(self) -> None:
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length) if length else b""
            path = self.path.split("?", 1)[0]
            if time.monotonic() < state.faults.fail_until:
                state.note("fault", f"503 {self.command} {path}")
                return self._reply(503, {"Retry-After": "2", "Content-Type": "application/json"},
                                   b'{"error":"busy"}')
            for prefix, retry_after in state.faults.rate_limit.items():
                if path.startswith(prefix):
                    state.note("fault", f"429 {self.command} {path}")
                    return self._reply(429, {"Retry-After": str(retry_after), "Content-Type": "application/json"},
                                       b'{"error":"rate_limited"}')
            model = validators.get((self.command, path))
            if model is not None:
                try:
                    data = json.loads(body or b"null")
                    model.model_validate(data)
                    extra = unknown_keys(model, data, nested) if isinstance(data, dict) else []
                    if extra:
                        state.note("violation", f"{self.command} {path}: keys unknown to the server: {extra}")
                except Exception as exc:  # noqa: BLE001 - any parse/validation error is a contract violation
                    state.note("violation", f"{self.command} {path}: {exc}")
            if self.command != "GET" and path.startswith("/v4/") and path != "/v4/logs" \
                    and not self.headers.get("Idempotency-Key"):
                state.note("violation", f"{self.command} {path}: missing Idempotency-Key")
            headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP_HEADERS}
            status, rheaders, rbody = forward(self.command, self.path, headers, body)
            if path == "/v4/slave/results" and state.take("drop_results"):
                return self._lose("results")
            if path == "/v4/enroll" and state.take("drop_enroll"):
                return self._lose("enroll")
            if path.startswith("/v4/token/rotate") and state.take("drop_rotate"):
                return self._lose("rotate")
            self._reply(status, rheaders, rbody)

        do_GET = do_POST = do_PUT = _handle

    return Handler


def url_forwarder(upstream: str, timeout: float = 10.0) -> Forward:
    def forward(method, path, headers, body):
        req = urllib.request.Request(upstream.rstrip("/") + path, data=body or None, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.status, dict(resp.headers.items()), resp.read()
        except urllib.error.HTTPError as err:
            return err.code, dict(err.headers.items()), err.read()

    return forward


def serve(state: ProxyState, forward: Forward, host: str = "127.0.0.1", port: int = 8080) -> ThreadingHTTPServer:
    server = ThreadingHTTPServer((host, port), make_handler(state, forward))
    server.daemon_threads = True
    return server


def parse_rate_limits(values: list[str]) -> dict[str, int]:
    out: dict[str, int] = {}
    for v in values:
        prefix, _, secs = v.partition("=")
        out[prefix] = int(secs or "3600")
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--upstream", default="http://127.0.0.1:8000")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--drop-results", type=int, default=0)
    ap.add_argument("--drop-enroll", type=int, default=0)
    ap.add_argument("--drop-rotate", type=int, default=0)
    ap.add_argument("--rate-limit", action="append", default=[], metavar="PATH=SECONDS")
    ap.add_argument("--fail-all-for", type=float, default=0.0, metavar="SECONDS")
    ap.add_argument("--no-validate", action="store_true")
    args = ap.parse_args(argv)
    faults = Faults(drop_results=args.drop_results, drop_enroll=args.drop_enroll, drop_rotate=args.drop_rotate,
                    rate_limit=parse_rate_limits(args.rate_limit),
                    fail_until=time.monotonic() + args.fail_all_for if args.fail_all_for else 0.0)
    state = ProxyState(faults=faults, validate=not args.no_validate)
    server = serve(state, url_forwarder(args.upstream), args.host, args.port)
    print(f"[proxy] http://{args.host}:{args.port} -> {args.upstream}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    print(f"[proxy] {len(state.violations)} contract violation(s)", flush=True)
    return 1 if state.violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
