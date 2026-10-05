"""App factory. Run with: uvicorn copycore.app:create_app --factory"""

from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from . import __version__
from .config import Settings, get_settings
from .db import make_engine, make_sessionmaker
from .engine.clock import Clock
from .errors import install_handlers, server_time_ms
from .routers import admin, admin_copy, health, v4, v4_copy
from .security import install_log_redaction

log = logging.getLogger("copycore")


def create_app(settings: Settings | None = None, engine=None) -> FastAPI:
    settings = settings or get_settings()  # raises ConfigError on invalid/missing config
    install_log_redaction()
    app = FastAPI(title="Copy Server", version=__version__, docs_url=None, redoc_url=None)
    app.state.settings = settings
    app.state.engine = engine or make_engine(settings.database_url)
    app.state.sessionmaker = make_sessionmaker(app.state.engine)
    # Server runtime epoch + monotonic clock for close-detection timers (5.6, C4).
    app.state.clock = Clock()

    @app.middleware("http")
    async def _server_time_and_limits(request: Request, call_next):
        length = request.headers.get("content-length")
        if length and length.isdigit() and int(length) > settings.body_max_bytes:
            return JSONResponse({"error": "too_large", "server_time": server_time_ms()}, 413)
        response = await call_next(request)
        response.headers["X-Server-Time"] = str(server_time_ms())
        return response

    install_handlers(app)
    app.include_router(health.router)
    app.include_router(v4.router)
    app.include_router(v4_copy.router)
    app.include_router(admin.router)
    app.include_router(admin_copy.router)
    log.info("copy server %s started (env=%s, db=%s)", __version__, settings.env,
             "sqlite" if settings.is_sqlite else "postgres")
    return app
