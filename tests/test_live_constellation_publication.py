"""Publish retained receiver captures; do not simulate or fit constellation data."""
import csv
import hashlib
import io
import json
from pathlib import Path
import sys

import pytest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import publish_lls_live_csv_plots as live

SOURCE = ROOT / "docs/lls/evidence_20260913/gnb_feedback_ul_constellation_03"
CAPTURE = "air_interface/csv/ul_constellation_samples.csv"
CHART = "post-equalization constellation"


def test_retained_receiver_capture_publishes_constellation_with_exact_identity(tmp_path):
    before = {str(p.relative_to(SOURCE)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in SOURCE.rglob("*") if p.is_file()}
    result = live.publish(tmp_path, source_run_folder=SOURCE)
    manifest_path = live.io_path(Path(result["Manifest"]))
    manifest = json.loads(manifest_path.read_text())
    chart = next(c for c in manifest["charts"] if c["name"] == CHART)
    assert chart["status"] == "measured_checkpoint"
    assert chart["source_paths"] == CAPTURE
    assert manifest["terminal_qualification"] is False
    original = list(csv.DictReader(io.StringIO((SOURCE / CAPTURE).read_text())))
    plotted = list(csv.DictReader(io.StringIO((manifest_path.parent / chart["csv"]).read_text())))
    assert len(plotted) == len(original) == 3522
    fields = {"ue_index": "UEIndex", "frame": "Frame", "sfn": "SFN",
              "slot": "Slot", "layer_index": "LayerIndex", "codeword_index": "CodewordIndex",
              "sample_index": "SampleIndex", "modulation": "Modulation", "capture_scope": "CaptureScope"}
    for actual, expected in zip(plotted, original):
        assert float(actual["x_value"]) == float(expected["RawEqualizedReal"])
        assert float(actual["y_value"]) == float(expected["RawEqualizedImag"])
        assert all(actual[a] == expected[b] for a, b in fields.items())
    with Image.open(manifest_path.parent / chart["png"]) as image:
        assert image.format == "PNG"
        text = image.info["sixgr_visual_semantics"]
        assert "POST-RUN PREVIEW" in text and "ul_rows=3522" in text
        assert "In-phase" in text and "Quadrature" in text
        image.verify()
    assert live.publish(tmp_path, source_run_folder=SOURCE)["Status"] == "unchanged_verified_snapshot"
    sys.path.insert(0, str(ROOT / "tools"))
    import audit_lls_visual_artifacts as audit
    # Match the audit CLI's Windows extended-path boundary.
    audit_rows, seen = audit.audit_component_plot_lineages(audit.windows_extended_path(tmp_path), set())
    assert len(audit_rows) == len(seen) == manifest["png_count"]
    assert all(not row.failure_code for row in audit_rows)
    assert before == {str(p.relative_to(SOURCE)): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in SOURCE.rglob("*") if p.is_file()}


@pytest.mark.parametrize("field,value,message", [
    ("Source", "fast_proxy", "Non-runtime evidence"),
    ("ExecutionBackend", "synthetic", "Non-runtime evidence"),
    ("ApproximationMode", "lut", "Non-runtime evidence"),
    ("TruthStatus", "fallback", "Non-runtime evidence"),
    ("E2EAirModel", "logistic", "Non-runtime evidence"),
    ("Direction", "DL", "direction contradicts"),
    ("RawEqualizedReal", "nan", "nonfinite or missing"),
    ("RawEqualizedImag", "", "nonfinite or missing"),
])
def test_bad_source_is_rejected_not_repaired_into_a_cloud(field, value, message):
    row = next(csv.DictReader(io.StringIO((SOURCE / CAPTURE).read_text())))
    row[field] = value
    stream = io.StringIO()
    writer = csv.DictWriter(stream, list(row))
    writer.writeheader()
    writer.writerow(row)
    with pytest.raises(ValueError, match=message):
        live.materializer._specialized_chart_materialization(
            CHART, {CAPTURE: {"artifact_id": 1}}, lambda _: stream.getvalue().encode(), "fixture")


def test_absent_capture_does_not_synthesize_constellation(tmp_path):
    result = live.publish(tmp_path)
    manifest = json.loads(live.io_path(Path(result["Manifest"])).read_text())
    chart = next(c for c in manifest["charts"] if c["name"] == CHART)
    assert chart["status"] == "unavailable_at_checkpoint"
    assert not list(tmp_path.rglob("*.png"))
