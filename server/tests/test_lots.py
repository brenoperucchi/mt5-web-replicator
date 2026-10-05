"""Lot calculation table (design 5.4; scenarios S18, S19)."""

from __future__ import annotations

from decimal import Decimal

import pytest

from copycore.engine.lots import calc_lot

D = Decimal


@pytest.mark.parametrize(("case", "kw", "expected", "reason"), [
    ("master 1:1", dict(lot_mode="master", master_volume="0.37"), "0.37", None),
    ("multiplier 0.333 floors to step", dict(lot_mode="multiplier", lot_value="0.333", master_volume="1"),
     "0.33", None),
    ("multiplier 2", dict(lot_mode="multiplier", lot_value="2", master_volume="0.15"), "0.30", None),
    ("fixed", dict(lot_mode="fixed", lot_value="0.5", master_volume="3"), "0.50", None),
    ("min_lot_x", dict(lot_mode="min_lot_x", lot_value="3", master_volume="9"), "0.03", None),
    ("min 0.1 step 0.1 floors", dict(lot_mode="master", master_volume="0.29", volume_min="0.1",
                                     volume_step="0.1"), "0.2", None),
    ("step 0.05 != min 0.1", dict(lot_mode="master", master_volume="0.29", volume_min="0.1",
                                  volume_step="0.05"), "0.25", None),
    ("clamp at max", dict(lot_mode="multiplier", lot_value="10", master_volume="20", volume_max="50"), "50", None),
    ("S19 contract 100 vs 10 (x10)", dict(lot_mode="master", master_volume="0.05", master_contract_size="100",
                                         slave_contract_size="10"), "0.50", None),
    ("contract factor then clamp", dict(lot_mode="master", master_volume="9", master_contract_size="100",
                                        slave_contract_size="10", volume_max="50"), "50", None),
    ("contract factor ignored for fixed", dict(lot_mode="fixed", lot_value="0.2", master_volume="1",
                                               master_contract_size="100", slave_contract_size="10"),
     "0.20", None),
    ("S18 below min skipped by default", dict(lot_mode="multiplier", lot_value="0.1", master_volume="0.05",
                                              volume_min="0.01"), None, "below_min"),
    ("S18 below min open_min opt-in", dict(lot_mode="multiplier", lot_value="0.1", master_volume="0.05",
                                           below_min="open_min"), "0.01", None),
    ("min 0.1: 0.09 skipped", dict(lot_mode="master", master_volume="0.09", volume_min="0.1",
                                   volume_step="0.1"), None, "below_min"),
    ("missing spec", dict(lot_mode="master", master_volume="1", volume_min=None), None, "missing_symbol_spec"),
])
def test_lot_table(case, kw, expected, reason):
    args = dict(lot_value=None, below_min="skip", volume_min="0.01", volume_step="0.01", volume_max="100")
    args.update(kw)
    res = calc_lot(**args)
    assert res.skip_reason == reason, case
    if expected is None:
        assert res.volume is None
    else:
        assert res.volume == D(expected), (case, res.volume)
