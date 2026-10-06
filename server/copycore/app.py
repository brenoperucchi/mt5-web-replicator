"""App factory. Run with: uvicorn copycore.app:create_app --factory"""

from __future__ import annotations

import logging
import threading
import time

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from . import __version__
from .config import Settings, get_settings
from .db import make_engine, make_read_sessionmaker, make_sessionmaker
from .engine.clock import Clock
from .errors import install_handlers, server_time_ms
from .routers import admin, admin_copy, admin_ops, health, ui, v4, v4_copy
from .security import install_log_redaction

log = logging.getLogger("copycore")


class AccessTrace:
    """Opt-in per-call trace (ACCESS_TRACE_PATH) for latency/load tests: one tab-separated line per /v4 call,
    `start_ms account_id method path status duration_ms`. Never logs tokens or bodies."""

    def __init__(self, path: str):
        self._f = open(path, "a", buffering=1, encoding="utf-8")  # noqa: SIM115 - lives as long as the app
        self._lock = threading.Lock()

    def write(self, start_ms, account_id, method, path, status, dur_ms) -> None:
        with self._lock:
            self._f.write(f"{start_ms}\t{account_id if account_id is not None else '-'}\t{method}\t{path}\t"
                          f"{status}\t{dur_ms:.1f}\n")


def create_app(settings: Settings | None = None, engine=None) -> FastAPI:
    settings = settings or get_settings()  # raises ConfigError on invalid/missing config
    install_log_redaction()
    app = FastAPI(title="Copy Server", version=__version__, docs_url=None, redoc_url=None)
    app.state.settings = settings
    app.state.engine = engine or make_engine(settings.database_url)
    app.state.sessionmaker = make_sessionmaker(app.state.engine)
    app.state.read_sessionmaker = make_read_sessionmaker(app.state.engine)
    # Server runtime epoch + monotonic clock for close-detection timers (5.6, C4).
    app.state.clock = Clock()

    trace = AccessTrace(settings.access_trace_path) if settings.access_trace_path else None

    @app.middleware("http")
    async def _server_time_and_limits(request: Request, call_next):
        length = request.headers.get("content-length")
        if length and length.isdigit() and int(length) > settings.body_max_bytes:
            return JSONResponse({"error": "too_large", "server_time": server_time_ms()}, 413)
        started_ms = server_time_ms()
        t0 = time.perf_counter()
        response = await call_next(request)
        response.headers["X-Server-Time"] = str(server_time_ms())
        if trace is not None and request.url.path.startswith("/v4/"):
            trace.write(started_ms, getattr(request.state, "account_id", None), request.method, request.url.path,
                        response.status_code, (time.perf_counter() - t0) * 1000)
        return response

    install_handlers(app)
    app.include_router(health.router)
    app.include_router(v4.router)
    app.include_router(v4_copy.router)
    app.include_router(admin.router)
    app.include_router(admin_copy.router)
    app.include_router(admin_ops.router)
    ui.install(app)  # minimal server-rendered admin (Q9)
    log.info("copy server %s started (env=%s, db=%s)", __version__, settings.env,
             "sqlite" if settings.is_sqlite else "postgres")
    return app
