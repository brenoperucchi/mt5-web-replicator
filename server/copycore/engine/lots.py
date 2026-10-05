"""Server-side lot calculation (design 5.4, OD6). Pure function, Decimal only."""

from __future__ import annotations

from dataclasses import dataclass
from decimal import ROUND_FLOOR, Decimal


@dataclass(frozen=True)
class LotResult:
    volume: Decimal | None  # None = skipped
    skip_reason: str | None = None
    raw: Decimal | None = None


def _d(v) -> Decimal | None:
    return None if v is None else Decimal(str(v))


def floor_to_step(value: Decimal, step: Decimal) -> Decimal:
    steps = (value / step).to_integral_value(rounding=ROUND_FLOOR)
    exponent = min(int(step.normalize().as_tuple().exponent), 0)
    return (steps * step).quantize(Decimal(1).scaleb(exponent))


def calc_lot(*, lot_mode: str, lot_value, master_volume, below_min: str,
             volume_min, volume_step, volume_max=None,
             master_contract_size=None, slave_contract_size=None) -> LotResult:
    """raw by mode → contract-size factor (master/multiplier) → floor to step → clamp → below-min policy."""
    vmin, step, vmax = _d(volume_min), _d(volume_step), _d(volume_max)
    if vmin is None or step is None or step <= 0 or vmin <= 0:
        return LotResult(None, "missing_symbol_spec")
    mv, lv = _d(master_volume), _d(lot_value)
    if lot_mode == "master":
        raw = mv
    elif lot_mode == "multiplier":
        raw = mv * lv
    elif lot_mode == "fixed":
        raw = lv
    elif lot_mode == "min_lot_x":
        raw = vmin * lv
    else:  # pragma: no cover - guarded by the DB enum
        raise ValueError(lot_mode)
    mcs, scs = _d(master_contract_size), _d(slave_contract_size)
    if lot_mode in ("master", "multiplier") and mcs and scs:
        raw = raw * mcs / scs
    lot = floor_to_step(raw, step)
    if vmax is not None and vmax > 0:
        lot = min(lot, vmax)
    if lot < vmin:
        if below_min == "open_min":
            return LotResult(vmin, None, raw)
        return LotResult(None, "below_min", raw)
    return LotResult(lot, None, raw)
