"""Analytic CSV fixtures test plot semantics, not waveform qualification."""
import csv
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m


def plot(name, header, rows):
    payload = m._encode_csv(header, rows)
    return m._runtime_prach_operational_chart(name,
        {"air_interface/csv/prach_trials.csv": {"artifact_id": 1}}, lambda _: payload, 7)


def test_detection_is_not_complete_access_and_missing_is_not_failure():
    result = plot("access attempt/success timeline",
        ["DetectionSuccess", "RACompleted"], [[1, ""], [1, 0], ["", ""]])
    rows = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert [row["success_scope"] for row in rows] == ["Preamble detected", "RA completed", ""]
    assert [row["success_flag"] for row in rows] == ["1", "0", ""]
    svg = result["img_bytes"].decode()
    assert "Preamble detected" in svg and "RA completed" in svg
    assert "Outcome unavailable" in svg
    assert "executed four-step" not in svg + result["note"]


def test_missing_timing_components_are_not_zero_bars():
    result = plot("timing offset true vs estimated vs residual",
        ["EstimatedTimingOffset_samples"], [[0.498072998660603]])
    svg = result["img_bytes"].decode()
    assert "True unavailable" in svg and "Residual unavailable" in svg
    assert "bucket_2=" not in svg
    rows = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert rows[0]["true_timing_offset_samples"] == ""
    assert rows[0]["timing_error_samples"] == ""
    assert float(rows[0]["estimated_timing_offset_samples"]) == 0.498072998660603


def test_standalone_timing_caption_does_not_claim_a_four_step_chain():
    result = plot("TA estimate trend", ["EstimatedTimingOffset_samples"], [[0.498]])
    assert "executed four-step" not in result["img_bytes"].decode() + result["note"]
    assert "Timing estimate (samples)" in result["img_bytes"].decode()


def test_absent_timing_is_explicitly_unavailable_not_a_generic_replacement():
    result = plot("timing offset true vs estimated vs residual", ["DetectionSuccess"], [[1]])
    assert result["csv_status"] == "unavailable_exact_reason"
    assert result["source_row_count"] == 0
