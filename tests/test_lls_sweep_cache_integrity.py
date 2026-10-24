"""Publication fixtures only: no waveform or statistical qualification claim."""
import hashlib
import json
import os
from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_sweep_report as report


def fixture(root):
    config_path = root / "meta/scenario_config_resolved.json"
    config_path.parent.mkdir(parents=True)
    config_path.write_text(json.dumps({
        "frequency": {"center_frequency_hz": 2350000000},
        "output": {"save_figures": False},
        "scenario": {"runner_profile": "generic_sweep", "sweep": {"overrides": [
            {"label": "point_a", "config": {"simulation": {"snr_db": 0}}}]}}
    }), encoding="utf-8")
    summary = root / "reports/csv/sweep_summary.csv"
    summary.parent.mkdir(parents=True)
    summary.write_text("Label,Ok,ExecutionStatus\npoint_a,1,completed\n", encoding="utf-8")
    source = root / "sweeps/point_a/air_interface/csv/measurement.csv"
    source.parent.mkdir(parents=True)
    source.write_text("Value,CenterFrequencyHz\n1.25,4000000000\n", encoding="utf-8")
    return source


def combined(root):
    rows = report.read_rows(root / "reports/csv/sweep_comparison_manifest.csv", strict=True)
    return rows[0], root / rows[0]["CombinedArtifact"]


def test_same_size_same_mtime_source_change_invalidates_cache(tmp_path):
    source = fixture(tmp_path)
    report.export_sweep(tmp_path)
    first, output = combined(tmp_path)
    stat = source.stat()
    source.write_text(source.read_text(encoding="utf-8").replace("1.25", "2.25"), encoding="utf-8")
    os.utime(source, ns=(stat.st_atime_ns, stat.st_mtime_ns))
    assert source.stat().st_size == stat.st_size
    report.export_sweep(tmp_path)
    second, _ = combined(tmp_path)
    assert second["SourceSignature"] != first["SourceSignature"]
    assert report.read_rows(output)[0]["Value"] == "2.25"
    assert second["OutputSHA256"] == hashlib.sha256(output.read_bytes()).hexdigest()


def test_output_corruption_rebuilt_and_valid_output_reused(tmp_path):
    fixture(tmp_path)
    report.export_sweep(tmp_path)
    original, output = combined(tmp_path)
    output.write_text(output.read_text(encoding="utf-8").replace("1.25", "9.25"), encoding="utf-8")
    report.export_sweep(tmp_path)
    repaired, _ = combined(tmp_path)
    assert repaired["OutputSHA256"] == original["OutputSHA256"]
    assert report.read_rows(output)[0]["Value"] == "1.25"
    with patch.object(report, "concatenate_csv", side_effect=AssertionError("Unchanged source/output recopied")):
        report.export_sweep(tmp_path)


def test_parent_frequency_cannot_overwrite_child_carrier(tmp_path):
    source = fixture(tmp_path)
    before = source.read_bytes()
    report.export_sweep(tmp_path)
    receipt, output = combined(tmp_path)
    row = report.read_rows(output)[0]
    assert row["CenterFrequencyHz"] == "4000000000"
    assert "ParentConfiguredCenterFrequencyHz" not in row
    assert source.read_bytes() == before
    assert receipt["OutputSHA256"] == hashlib.sha256(output.read_bytes()).hexdigest()
    manifest = report.read_json(tmp_path / "reports/campaign_manifest.json")
    assert manifest["CenterFrequencyHz"] == 2350000000
    assert "4ghz" not in manifest["ScopeBoundary"]
    assert manifest["CarrierMetadataScope"] == "parent_configuration_not_verification_of_child_carriers"
    point = report.read_rows(tmp_path / "reports/csv/point_status.csv")[0]
    assert point["ParentConfiguredCenterFrequencyHz"] == "2350000000"
    assert "CenterFrequencyHz" not in point


def test_source_mutation_during_copy_not_receipted_as_written(tmp_path):
    source = fixture(tmp_path)
    copy = report.concatenate_csv

    def mutate_after_copy(*args, **kwargs):
        copy(*args, **kwargs)
        source.write_text(source.read_text(encoding="utf-8").replace("1.25", "2.25"), encoding="utf-8")

    with patch.object(report, "concatenate_csv", side_effect=mutate_after_copy):
        result = report.export_sweep(tmp_path)
    receipt, _ = combined(tmp_path)
    assert result["FailedArtifacts"] == 1
    assert receipt["Status"] == "failed" and not receipt["OutputSHA256"]
    assert "changed during" in receipt["Error"]
