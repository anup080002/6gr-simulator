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


@pytest.mark.parametrize("matrix,label,ticks", [
    ([[-20.0, -10.0], [-15.0, -5.0]], "Receiver Hest magnitude (dB)", ["-20", "-12.5", "-5"]),
    ([[-90.0, 0.0], [45.0, 90.0]], "Receiver Hest phase (deg)", ["-90", "0", "90"]),
    ([[0.0, 0.0], [0.0, 0.0]], "Receiver Hest phase (deg)", ["0"]),
])
def test_physical_heatmap_has_signed_scale_and_preserves_zero_measurements(matrix, label, ticks):
    before = copy.deepcopy(matrix)
    svg = materializer._render_heatmap_svg(
        "Measured Hest", "Exact receiver tensor", ["0", "1"], ["2", "3"],
        matrix, [], "Subcarrier", "Symbol", physical_color_label=label,
    ).decode()
    assert matrix == before
    assert label in svg and "visual_gate=" not in svg
    assert "every heatmap cell is zero" not in svg
    for tick in ticks:
        assert f">{tick}</text>" in svg


def test_physical_heatmap_does_not_replace_missing_cells_with_zero():
    svg = materializer._render_heatmap_svg(
        "Measured Hest", "Exact receiver tensor", ["0", "1"], ["2", "3"],
        [[-90.0, None], [0.0, 90.0]], [], "Subcarrier", "Symbol",
        physical_color_label="Phase (deg)",
    ).decode()
    assert 'fill="#e2e8f0"' in svg
    assert "Grey cells: missing measurement" in svg
    missing = materializer._render_heatmap_svg(
        "Measured Hest", "Exact receiver tensor", ["0", "1"], ["2", "3"],
        [[None, None], [None, None]], [], "Subcarrier", "Symbol",
        physical_color_label="Phase (deg)",
    ).decode()
    assert "No finite physical heatmap measurements" in missing


def test_zero_count_heatmap_retains_its_existing_no_activity_semantics():
    svg = materializer._render_heatmap_svg(
        "Counts", "Actual events", ["0", "1"], ["2", "3"],
        [[0.0, 0.0], [0.0, 0.0]], [], "Slot", "PRB",
    ).decode()
    assert "all_zero_heatmap_cells" in svg
