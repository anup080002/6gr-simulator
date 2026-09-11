from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from lls_csv_semantics import _audit_large_scale_power_table


def _row() -> dict[str, str]:
    return {
        "WaveformPowerBeforeDb": "3", "WaveformPowerAfterDb": "-27",
        "MeasuredDeltaDb": "30", "ExpectedDeltaDb": "30", "ToleranceDb": "1e-10",
        "TotalLargeScaleLossDbApplied": "40",  # Endpoint gains are separate.
    }


def test_actual_net_power_change_is_not_pathloss_alone() -> None:
    checks = _audit_large_scale_power_table("channel/csv/large_scale_parameters.csv", [_row()])
    assert len(checks) == 1 and checks[0].passed and checks[0].required


def test_copying_expected_loss_without_measurement_fails() -> None:
    row = _row()
    row.update(WaveformPowerBeforeDb="NaN", WaveformPowerAfterDb="NaN")
    check = _audit_large_scale_power_table("power.csv", [row])[0]
    assert not check.passed and "independent_waveform_power_measurement_missing" in check.details


def test_wrong_measured_delta_cannot_hide_behind_matching_expected_value() -> None:
    row = _row()
    row.update(MeasuredDeltaDb="40", ExpectedDeltaDb="40")
    check = _audit_large_scale_power_table("power.csv", [row])[0]
    assert not check.passed and "measured_delta_not_input_minus_output_power" in check.details


def test_actual_wrong_gain_is_reported_even_when_delta_math_is_correct() -> None:
    row = _row()
    row.update(WaveformPowerAfterDb="-24", MeasuredDeltaDb="27")
    check = _audit_large_scale_power_table("power.csv", [row])[0]
    assert not check.passed and "measured_power_does_not_close" in check.details
