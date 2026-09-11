from __future__ import annotations

import copy
import math
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as materializer


@pytest.mark.parametrize("label", ["Beam quality (dB)", "Per-layer quality (dB)"])
def test_negative_physical_measurement_is_not_a_nonnegative_index(label: str) -> None:
    dataset = {
        "mode": "bar", "x_label": "Slot", "y_label": label,
        "points": [[35.0, -21.6758]], "sample_count": 1,
        "evidence_shape_policy": "measured_scalar",
    }
    before = copy.deepcopy(dataset)
    svg = materializer._render_svg_plot("Measured quality", "Receiver evidence", dataset, []).decode()
    assert dataset == before
    assert label in svg and "visual_gate=" not in svg
    assert ">-20<" in svg


def test_small_nonzero_physical_power_is_not_formatted_as_zero() -> None:
    assert materializer._format_axis_tick(1e-15) == "1.00e-15"
    assert materializer._format_axis_tick(-1e-15) == "-1.00e-15"
    ticks = materializer._axis_tick_values(1e-15, 2e-15)
    assert len(ticks) >= 2
    assert all(1e-15 * (1 - 1e-12) <= tick <= 2e-15 * (1 + 1e-12) for tick in ticks)
    assert len(set(ticks)) == len(ticks)


def test_subnormal_axis_uses_its_representable_endpoints() -> None:
    smallest = math.nextafter(0.0, 1.0)
    assert materializer._axis_tick_values(0.0, smallest) == [0.0, smallest]


def test_invalid_axis_bounds_fail_explicitly() -> None:
    with pytest.raises(ValueError, match="finite ordered"):
        materializer._axis_tick_values(2.0, 1.0)
