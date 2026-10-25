"""Reporting-only TRS projections; no PHY execution or accuracy claim."""
from __future__ import annotations

import csv
import hashlib
import io
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "apps"))
import lls_contract_materializer as materializer
import lls_web_dashboard as dashboard

TRS_PATH = "air_interface/csv/trs_trials.csv"
TRACE_PATH = "reports/csv/rf_synchronization_observations.csv"


def fixture():
    return {"Direction": "DL", "Slot": "7", "UEIndex": "1",
            "ResidualCFO_EstimatedPostCorrection_Hz": "-21.2931666848223",
            "ResidualCFO_PostCorrection_Hz": "NaN",
            "ResidualCFOEstimateAvailable": "1",
            "ResidualCFOEstimateRole": "received_common_frequency_not_separated_oscillator",
            "ResidualCFOEstimateSource": "declared_different_received_observable",
            "ResidualCFOReusesAcquisitionObservation": "1",
            "ResidualFrequencyUsesDifferentObservable": "1",
            "ResidualFrequencyStatus": "measured_received_common_frequency_after_correction"}


def encode(row):
    return materializer._encode_dict_rows(list(row), [row])


def chart(payload):
    return materializer._runtime_cfo_tracking_chart(
        "CFO true vs estimated vs residual", {TRACE_PATH: {"artifact_id": 1}},
        lambda _: payload, 1)


def decoded(payload):
    with materializer._csv_field_limit_for_payload(payload):
        return list(csv.DictReader(io.StringIO(payload.decode("utf-8-sig"))))


def test_trs_shared_capture_different_observable_is_not_estimator_consistency():
    row = fixture()
    result = chart(encode(row))
    record = decoded(result["csv_bytes"])[0]
    assert float(record["receiver_common_residual_hz"]) == float(row["ResidualCFO_EstimatedPostCorrection_Hz"])
    assert record["residual_cfo_hz"] == record["true_cfo_hz"] == ""
    assert record["receiver_residual_role"] == row["ResidualCFOEstimateRole"]
    assert record["uses_different_observable"] == record["receiver_residual_available"] == "1"
    assert float(record["reuses_acquisition_observation"]) == 1
    svg = result["img_bytes"].decode()
    assert "Post-correction common frequency" in svg
    assert "Estimator self-consistency" not in svg


@pytest.mark.parametrize("role,expected", [
    ("same_observation_estimator_consistency_not_independent_residual", "Estimator self-consistency"),
    ("", "Post-correction estimate (scope unspecified)"),
])
def test_reuse_flag_alone_does_not_authorize_a_measurement_scope(role, expected):
    row = fixture()
    row["ResidualCFOEstimateRole"] = role
    row.pop("ResidualFrequencyUsesDifferentObservable")
    result = chart(encode(row))
    assert expected in result["img_bytes"].decode()
    assert "Post-correction common frequency" not in result["img_bytes"].decode()
    assert decoded(result["csv_bytes"])[0]["uses_different_observable"] == ""


def test_live_tracking_preserves_canonical_residual_separately_from_legacy_reference():
    row = fixture()
    payload = encode(row)
    result = materializer._specialized_live_report_table(
        "live_tracking_table", {TRS_PATH: {"artifact_id": 1}}, lambda _: payload, 1, {}, {})
    out = decoded(result["data"])[0]
    assert out["source_artifact"] == TRS_PATH
    assert float(out["receiver_common_residual_hz"]) == float(row["ResidualCFO_EstimatedPostCorrection_Hz"])
    assert out["residual_cfo_post_correction_hz"] in ("", "NaN")
    assert out["receiver_residual_source"] == row["ResidualCFOEstimateSource"]
    assert out["receiver_residual_role"] == row["ResidualCFOEstimateRole"]
    assert out["receiver_residual_available"] == out["uses_different_observable"] == "1"


def test_measurement_authority_preview_is_original_not_inferred_from_pass():
    original = {"Slot": "7", "Status": "PASS", "DLMeasurementAuthorityRequired": "1",
                "DLMeasurementAuthorityEligible": "0",
                "DLMeasurementAuthorityStatus": "declared_diagnostic_only",
                "DLMeasurementAuthoritySource": "declared_original_owner_fixture",
                "DLMeasurementConfigurationFamily": "CSI-RS",
                "DLMeasurementConfigurationSHA256": "a" * 64,
                "DLMeasurementInstallationSHA256": "b" * 64, "DLMeasurementNCellID": "7"}
    for kind in ("csirs_trials", "trs_trials"):
        shown = dashboard.summarize_control_trial_preview_rows(kind, [original])[0]
        assert str(shown["Operational authority eligible"]) == "0"
        assert shown["Operational authority status"] == "declared_diagnostic_only"
        assert shown["DL measurement installation SHA"] == "b" * 64
        absent = dashboard.summarize_control_trial_preview_rows(kind, [{"Slot": "7", "Status": "PASS"}])[0]
        assert "Operational authority eligible" not in absent


def test_retained_v198_trs_projection_without_new_phy_or_original_mutation():
    path = Path(r"E:\SixGRResults\lls\lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep\n40_sixpoint_repair_20261024_v198\sweeps\reference_esn0_30_db\air_interface\csv\trs_trials.csv")
    if not path.is_file():
        pytest.skip("Optional retained v198 evidence not present; declared regressions remain independent.")
    payload = path.read_bytes()
    before = hashlib.sha256(payload).hexdigest()
    original = decoded(payload)
    assert len(original) == 1 and original[0]["Slot"] == "7"
    assert original[0]["ResidualCFOEstimateRole"] == "received_common_frequency_not_separated_oscillator"
    result = chart(payload)
    out = decoded(result["csv_bytes"])[0]
    assert float(out["receiver_common_residual_hz"]) == float(original[0]["ResidualCFO_EstimatedPostCorrection_Hz"])
    assert "Estimator self-consistency" not in result["img_bytes"].decode()
    assert out["residual_cfo_hz"] == ""
    assert before == hashlib.sha256(path.read_bytes()).hexdigest()
