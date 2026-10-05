"""Server-side symbol mapping (design 7.1, D9): per-slave map, then global map, then identity."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import SymbolMap


def resolve_symbol(s: Session, slave_id: int, master_symbol: str) -> str:
    rows = s.scalars(select(SymbolMap).where(
        SymbolMap.master_symbol == master_symbol,
        (SymbolMap.slave_id == slave_id) | SymbolMap.slave_id.is_(None))).all()
    specific = next((r for r in rows if r.slave_id == slave_id), None)
    if specific is not None:
        return specific.slave_symbol
    glob = next((r for r in rows if r.slave_id is None), None)
    return glob.slave_symbol if glob is not None else master_symbol
