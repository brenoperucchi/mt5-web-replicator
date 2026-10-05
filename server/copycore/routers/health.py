from __future__ import annotations

from fastapi import APIRouter, Request
from sqlalchemy import text

from ..errors import json_response

router = APIRouter()


@router.get("/health")
@router.get("/healthz")
def health(request: Request):
    """Liveness + DB reachability. No auth."""
    try:
        with request.app.state.engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return json_response({"status": "ok"})
    except Exception:  # noqa: BLE001
        return json_response({"status": "error", "error": "database_unavailable"}, 503)
