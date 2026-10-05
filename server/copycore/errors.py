"""Uniform error responses (4.1): `{error, message, server_time}`."""

from __future__ import annotations

import time

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from .db import BusyError


def server_time_ms() -> int:
    return int(time.time() * 1000)


def json_response(body: dict | None, status_code: int = 200, headers: dict | None = None) -> JSONResponse:
    content = dict(body or {})
    content.setdefault("server_time", server_time_ms())
    return JSONResponse(content, status_code=status_code, headers=headers)


class ApiError(Exception):
    def __init__(self, status_code: int, error: str, message: str = "", headers: dict | None = None):
        super().__init__(error)
        self.status_code, self.error, self.message, self.headers = status_code, error, message, headers

    def response(self) -> JSONResponse:
        return json_response({"error": self.error, "message": self.message}, self.status_code, self.headers)


def install_handlers(app) -> None:
    @app.exception_handler(ApiError)
    async def _api_error(_req: Request, exc: ApiError):
        return exc.response()

    @app.exception_handler(BusyError)
    async def _busy(_req: Request, _exc: BusyError):
        return json_response({"error": "busy", "message": "database busy"}, 503, {"Retry-After": "1"})

    @app.exception_handler(RequestValidationError)
    async def _validation(_req: Request, exc: RequestValidationError):
        # Never echo input values back (they may contain codes/tokens).
        details = [{"loc": list(e.get("loc", ())), "type": e.get("type")} for e in exc.errors()]
        return json_response({"error": "validation", "message": "invalid request", "details": details}, 422)
