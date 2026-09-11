"""Declared CSV fixtures test publication, not a simulated radio outcome."""
import csv
import io
import json
from pathlib import Path
import sys

import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import publish_lls_live_csv_plots as live


def feedback(root, value=10, source="actual_decoded_csi"):
    path = root / live.radio.FEEDBACK
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,CQI,Source\n"
                    f"DL,1,7,9,delivered_to_runtime_scheduler,{value},{source}\n", encoding="utf-8")
    return path


def test_runtime_png_uses_exact_snapshot_and_updates(tmp_path):
    source = feedback(tmp_path)
    original = source.read_bytes()
    result = live.publish(tmp_path)
    manifest_path = Path(result["Manifest"])
    manifest = json.loads(manifest_path.read_text())
    assert manifest["terminal_qualification"] is False and manifest["png_count"] == 1
    chart = next(c for c in manifest["charts"] if c["name"] == "CSI CQI timeline")
    folder = manifest_path.parent
    rows = list(csv.DictReader(io.StringIO((folder / chart["csv"]).read_text())))
    assert rows[0]["reported_value_token"] == "10" and rows[0]["source_slot"] == "7.0"
    assert (folder / "sources" / live.radio.FEEDBACK).read_bytes() == original
    with Image.open(folder / chart["png"]) as png:
        assert png.format == "PNG" and png.width > 0
        assert "LIVE CHECKPOINT" in png.info["sixgr_visual_semantics"]
        png.verify()
    assert live.publish(tmp_path)["Status"] == "unchanged_verified_snapshot"
    feedback(tmp_path, value=12)
    second = live.publish(tmp_path)
    assert second["Manifest"] != result["Manifest"]
    assert (folder / "sources" / live.radio.FEEDBACK).read_bytes() == original
    assert not (tmp_path / "meta/manifest.json").exists()


def test_absent_measurements_do_not_generate_reason_png_or_primary_rows(tmp_path):
    result = live.publish(tmp_path)
    manifest = json.loads(Path(result["Manifest"]).read_text())
    assert manifest["png_count"] == 0
    assert all(c["status"] == "unavailable_at_checkpoint" for c in manifest["charts"])
    assert not list(tmp_path.rglob("*.png")) and not list(tmp_path.rglob("*.csv"))


def test_proxy_cannot_become_live_measurement(tmp_path):
    feedback(tmp_path, source="fast_proxy")
    result = live.publish(tmp_path)
    manifest = json.loads(Path(result["Manifest"]).read_text())
    assert manifest["png_count"] == 0
    cqi = next(c for c in manifest["charts"] if c["name"] == "CSI CQI timeline")
    assert "Non-runtime evidence" in cqi["note"]


@pytest.mark.parametrize("field,marker", [("Source","fast_proxy"), ("ExecutionBackend","synthetic"),
    ("ApproximationMode","lut"), ("E2EAirModel","logistic"), ("TruthStatus","fallback")])
def test_proxy_data_source_cannot_enter_throughput_renderer(tmp_path, field, marker):
    path = tmp_path / live.radio.TRIALS[0]
    path.parent.mkdir(parents=True)
    path.write_text(f"Direction,UEIndex,Slot,PostEqSINR_dB,Throughput_Mbps,{field}\n"
                    f"DL,1,7,12,2,{marker}\n")
    result = live.publish(tmp_path)
    manifest = json.loads(live.io_path(Path(result["Manifest"])).read_text())
    assert manifest["png_count"] == 0


def test_corrupted_snapshot_is_not_reused(tmp_path):
    feedback(tmp_path)
    result = live.publish(tmp_path)
    manifest = Path(result["Manifest"])
    image = next(manifest.parent.rglob("*.png"))
    image.write_bytes(b"corrupt")
    with pytest.raises(ValueError, match="receipt mismatch"):
        live.publish(tmp_path)


def test_malformed_csv_fails_without_receipt(tmp_path):
    path = feedback(tmp_path)
    path.write_text("a,b\n1,2,3\n")
    with pytest.raises(ValueError, match="Malformed CSV"):
        live.publish(tmp_path)
    assert not list(tmp_path.rglob("manifest.json"))


def test_post_run_preview_never_claims_live_publication(tmp_path):
    source = tmp_path / "original"
    path = feedback(source)
    data = path.read_bytes()
    output = tmp_path / "preview"
    output.mkdir()
    result = live.publish(output, source_run_folder=source)
    assert result["Status"] == "post_run_diagnostic_preview"
    assert path.read_bytes() == data and not (source / "reports").exists()
    image = next(output.rglob("*.png"))
    with Image.open(image) as png:
        assert "POST-RUN PREVIEW" in png.info["sixgr_visual_semantics"]
        assert "LIVE CHECKPOINT" not in png.info["sixgr_visual_semantics"]


def test_windows_long_snapshot_paths(tmp_path):
    root = tmp_path / ("long_run_name_" * 7)
    root.mkdir()
    feedback(root)
    result = live.publish(root)
    assert result["CreatedCount"] == 1
    assert len(result["Manifest"]) > 260
    assert live.publish(root)["Status"] == "unchanged_verified_snapshot"


def test_checkpoint_lineage_is_consumed_by_terminal_auditor(tmp_path):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
    import audit_lls_visual_artifacts as audit
    feedback(tmp_path)
    first = live.publish(tmp_path)
    feedback(tmp_path, value=12)
    second = live.publish(tmp_path)
    rows, seen = audit.audit_component_plot_lineages(live.io_path(tmp_path), set())
    assert len(rows) == 2 and len(seen) == 2
    assert all(not row.failure_code for row in rows)
    for result in (first, second):
        manifest = json.loads(live.io_path(Path(result["Manifest"])).read_text())
        assert "checkpoint_plot_lineage.csv" in manifest["artifact_sha256"]
        assert manifest["terminal_qualification"] is False
    # Altering a plotted checkpoint CSV must fail the existing strict audit.
    source = next(live.io_path(Path(first["Manifest"]).parent / "csv").glob("*.csv"))
    source.write_bytes(source.read_bytes() + b"\n")
    rows, _ = audit.audit_component_plot_lineages(live.io_path(tmp_path), set())
    assert any("component_plot_source_hash_mismatch" in row.failure_code for row in rows)
