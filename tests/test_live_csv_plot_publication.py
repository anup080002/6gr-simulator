"""Declared CSV fixtures test publication, not a simulated radio outcome."""
import csv
import io
import json
from pathlib import Path
import sys
import tracemalloc

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


def scored_channel_fixture(root, signal="CSI-RS", error=.5):
    """Independent arithmetic fixture; not a physical channel observation."""
    from test_data_nmse_plot_reconciliation import fixture
    row, _, payloads = fixture(error)
    sample = next(csv.DictReader(io.StringIO(payloads[1].decode())))
    logical = "channel_estimation/csv/live_scored_channel.csv"
    if signal == "CSI-RS":
        sample["CSIChannelEstimateObservationID"] = sample.pop("ChannelObservationID")
        sample["ResourceID"] = "1"
        row.update(SignalFamily=signal,
            CSIChannelEstimateObservationID=row.pop("ChannelObservationID"),
            ChannelNMSESource=row.pop("NMSESource"),
            ChannelNMSEReferencePlane=row.pop("ChannelEstimateReferencePlane"),
            ChannelNMSEReferenceUsedByReceiver="0", ChannelNMSEComparedComplexValues="1",
            NMSEScoringAvailable="1")
    out = io.StringIO(newline="")
    writer = csv.DictWriter(out, fieldnames=sample)
    writer.writeheader(); writer.writerow(sample)
    resource = live.io_path(root / logical)
    resource.parent.mkdir(parents=True, exist_ok=True)
    resource.write_bytes(out.getvalue().encode())
    row.update(Slot="6", UEIndex="1", Direction="UL" if signal == "PUSCH" else "DL",
        ConfiguredSNR_dB="40", PostEqSINR_dB="20", PostEqSINRSource="receiver_fixture",
        PostEqSINRValueStatus="OK", PostEqSINRValueRole="estimated",
        PostEqSINRMeasurementDomain="post_equalization",
        ChannelEstimateResourcesCSV=logical,
        ChannelEstimateResourcesCSVSHA256=live.file_digest(resource))
    primary = (live.radio.CSI_TRIALS if signal == "CSI-RS" else
               live.radio.TRIALS[1 if signal == "PUSCH" else 0])
    target = live.io_path(root / primary)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=row)
        writer.writeheader(); writer.writerow(row)
    return target, resource, logical


@pytest.mark.parametrize("signal", ["CSI-RS", "PDSCH", "PUSCH"])
def test_live_nmse_snapshots_referenced_complex_resources(tmp_path, signal):
    primary, resource, logical = scored_channel_fixture(tmp_path, signal)
    original = resource.read_bytes()
    result = live.publish(tmp_path)
    manifest_path = Path(result["Manifest"])
    manifest = json.loads(manifest_path.read_text())
    chart = next(c for c in manifest["charts"] if c["name"] == "NMSE vs SNR / SINR")
    assert chart["status"] == "measured_checkpoint", chart["note"]
    assert manifest["source_sha256"][logical] == live.digest(original)
    assert (manifest_path.parent / "sources" / logical).read_bytes() == original
    rows = list(csv.DictReader(io.StringIO((manifest_path.parent / chart["csv"]).read_text())))
    assert len(rows) == 1 and abs(float(rows[0]["metric_value"]) - 20*live.radio.math.log10(.5)) < 1e-10
    assert resource.read_bytes() == original
    assert live.publish(tmp_path)["Status"] == "unchanged_verified_snapshot"
    scored_channel_fixture(tmp_path, signal, error=.25)
    updated = live.publish(tmp_path)
    assert updated["Manifest"] != result["Manifest"]
    assert (manifest_path.parent / "sources" / logical).read_bytes() == original


def test_live_nmse_missing_then_available_resource_is_not_an_empty_success(tmp_path):
    _, resource, logical = scored_channel_fixture(tmp_path)
    retained = resource.with_suffix(".held")
    resource.rename(retained)
    first = live.publish(tmp_path)
    manifest = json.loads(Path(first["Manifest"]).read_text())
    chart = next(c for c in manifest["charts"] if c["name"] == "NMSE vs SNR / SINR")
    assert chart["status"] == "unavailable_at_checkpoint" and "csv" not in chart
    assert logical not in manifest["source_sha256"]
    retained.rename(resource)
    second = live.publish(tmp_path)
    assert second["Manifest"] != first["Manifest"]
    updated = json.loads(Path(second["Manifest"]).read_text())
    assert next(c for c in updated["charts"] if c["name"] == chart["name"])["status"] == "measured_checkpoint"


def test_changed_live_snapshot_shares_only_verified_immutable_inputs(tmp_path):
    primary, resource, logical = scored_channel_fixture(tmp_path)
    first = live.publish(tmp_path)
    first_folder = Path(first["Manifest"]).parent
    retained = first_folder / "sources" / logical
    original = retained.read_bytes()
    feedback(tmp_path)  # Another measurement changed; this complex sample set did not.
    second = live.publish(tmp_path)
    second_folder = Path(second["Manifest"]).parent
    reused = second_folder / "sources" / logical
    assert first_folder != second_folder
    assert retained.read_bytes() == reused.read_bytes() == original
    assert retained.stat().st_ino == reused.stat().st_ino, (
        "Unchanged immutable sample sets must not be copied at every slot."
    )
    assert resource.stat().st_ino != retained.stat().st_ino, (
        "Never hard-link a mutable primary measurement into an immutable snapshot."
    )
    resource.write_bytes(original + b"\n")
    assert retained.read_bytes() == reused.read_bytes() == original


def test_live_source_reuse_rejects_corrupt_prior_snapshot(tmp_path):
    _, _, logical = scored_channel_fixture(tmp_path)
    first = live.publish(tmp_path)
    retained = Path(first["Manifest"]).parent / "sources" / logical
    retained.write_bytes(retained.read_bytes() + b"corrupt")
    latest = tmp_path / "reports/live_measurements/latest.json"
    before = latest.read_bytes()
    feedback(tmp_path)
    with pytest.raises(ValueError, match="receipt mismatch"):
        live.publish(tmp_path)
    assert latest.read_bytes() == before


def test_immutable_input_reuse_has_hash_exact_copy_path_when_links_are_unsupported(tmp_path, monkeypatch):
    import errno
    _, resource, logical = scored_channel_fixture(tmp_path)
    first = live.publish(tmp_path)
    retained = Path(first["Manifest"]).parent / "sources" / logical
    original = retained.read_bytes()
    def unsupported_link(*args, **kwargs):
        raise OSError(errno.EXDEV, "declared filesystem without hard-link support")
    monkeypatch.setattr(live.os, "link", unsupported_link)
    feedback(tmp_path)
    second = live.publish(tmp_path)
    copied = Path(second["Manifest"]).parent / "sources" / logical
    assert copied.read_bytes() == retained.read_bytes() == resource.read_bytes() == original
    assert copied.stat().st_ino != retained.stat().st_ino != resource.stat().st_ino
    manifest = json.loads(Path(second["Manifest"]).read_text())
    assert manifest["artifact_sha256"]["sources/" + logical] == live.digest(original)


@pytest.mark.parametrize("reference", ["../outside.csv", "channel_estimation/csv/../outside.csv",
                                         "C:/another_run/resource.csv"])
def test_live_nmse_rejects_out_of_run_reference(tmp_path, reference):
    primary, _, logical = scored_channel_fixture(tmp_path)
    primary.write_text(primary.read_text().replace(logical, reference), encoding="utf-8")
    with pytest.raises(ValueError, match="Invalid channel NMSE resource path"):
        live.publish(tmp_path)
    assert not (tmp_path / "reports/live_measurements/latest.json").exists()


def test_live_nmse_corrupt_scoring_resource_never_publishes_measurement(tmp_path):
    _, resource, _ = scored_channel_fixture(tmp_path)
    resource.write_bytes(resource.read_bytes() + b"\n")  # Primary expected hash is deliberately unchanged.
    result = live.publish(tmp_path)
    manifest = json.loads(Path(result["Manifest"]).read_text())
    chart = next(c for c in manifest["charts"] if c["name"] == "NMSE vs SNR / SINR")
    assert chart["status"] == "unavailable_at_checkpoint" and "csv" not in chart
    assert "hash mismatch" in chart["note"]


def test_live_nmse_resource_change_during_render_preserves_latest(tmp_path, monkeypatch):
    _, resource, _ = scored_channel_fixture(tmp_path)
    live.publish(tmp_path)
    latest = tmp_path / "reports/live_measurements/latest.json"
    before = latest.read_bytes()
    feedback(tmp_path)  # Force another measured snapshot.
    original = live.materializer._specialized_chart_materialization
    changed = False
    def mutate(*args, **kwargs):
        nonlocal changed
        result = original(*args, **kwargs)
        if not changed:
            changed = True
            resource.write_bytes(resource.read_bytes() + b"\n")
        return result
    monkeypatch.setattr(live.materializer, "_specialized_chart_materialization", mutate)
    with pytest.raises(ValueError, match="Source changed"):
        live.publish(tmp_path)
    assert latest.read_bytes() == before


def test_live_nmse_long_resource_path_and_browser_lineage(tmp_path):
    root = tmp_path / ("long_run_name_" * 7)
    root.mkdir()
    _, resource, logical = scored_channel_fixture(root)
    result = live.publish(root)
    manifest_path = live.io_path(Path(result["Manifest"]))
    manifest = json.loads(manifest_path.read_text())
    snapshot = live.io_path(manifest_path.parent / "sources" / logical)
    assert len(str(snapshot)) > 260 and snapshot.read_bytes() == resource.read_bytes()
    chart = next(c for c in manifest["charts"] if c["name"] == "NMSE vs SNR / SINR")
    assert chart["status"] == "measured_checkpoint"
    selected = select_browser_snapshot(root)
    assert any(a["logical_path"].endswith("/image/nmse_vs_snr_sinr.png") for a in selected)
    assert all(a["terminal_qualification"] is False for a in selected)


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


def browser_artifacts(root):
    files = [p for p in live.io_path(root).rglob("*") if p.is_file()]
    return [dict(logical_path=p.relative_to(live.io_path(root)).as_posix(), artifact_id=i,
        artifact_kind="table_csv" if p.suffix == ".csv" else "image" if p.suffix == ".png" else "json",
        mime_type="image/png" if p.suffix == ".png" else "text/csv",
        byte_size=p.stat().st_size, created_utc="2026-10-17T00:00:00Z")
        for i, p in enumerate(files, 1)]


def select_browser_snapshot(root, *, expected_root=None):
    from lls_runtime_visualization_evidence import verified_runtime_visualizations
    return verified_runtime_visualizations(browser_artifacts(root),
        lambda a: live.io_path(root / a["logical_path"]).read_bytes(),
        run_folder=str(expected_root or root))


def test_producer_to_browser_live_publication_without_terminal_receipt(tmp_path):
    feedback(tmp_path)
    live.publish(tmp_path)
    selected = select_browser_snapshot(tmp_path)
    assert len(selected) == 2
    assert all(a["publication_kind"] == "partial_measured_checkpoint" and
        a["terminal_qualification"] is False and a["hash_verified"] for a in selected)
    import lls_web_dashboard as dashboard
    descriptors = [dashboard.build_artifact_descriptor(a) for a in selected]
    assert all(a["terminal_qualification"] is False for a in descriptors)
    assert not select_browser_snapshot(tmp_path, expected_root=tmp_path / "another_run")
    # Later mutable input does not invalidate the snapshot's exact plotted CSV.
    feedback(tmp_path, value=14)
    assert select_browser_snapshot(tmp_path) == selected
    live.publish(tmp_path)
    assert {a["publication_snapshot"] for a in select_browser_snapshot(tmp_path)} != {
        a["publication_snapshot"] for a in selected}


def test_production_filesystem_index_discovers_long_live_snapshot(tmp_path):
    import lls_web_dashboard as dashboard
    from lls_runtime_visualization_evidence import verified_runtime_visualizations
    root = tmp_path / ("long_selected_run_" * 6)
    root.mkdir()
    feedback(root)
    first = live.publish(root)
    assert len(first["Manifest"]) > 260
    run = dict(run_id=9100000001, run_folder=str(root), status_text="completed")
    def selected():
        artifacts = dashboard.filesystem_artifacts_for_run(run)
        assert not any(".live-stage-" in a["logical_path"] for a in artifacts)
        return verified_runtime_visualizations(artifacts,
            lambda a: dashboard._windows_extended_path(a["filesystem_path"]).read_bytes(),
            run_folder=str(root))
    # The real scanner and verifier must work together, including terminal
    # inventory invalidation when latest.json points to a new snapshot.
    before = selected()
    assert len(before) == 2
    staging = live.io_path(root / "reports/live_measurements/.live-stage-incomplete")
    staging.mkdir()
    (staging / "not_published.csv").write_text("value\n1\n")
    feedback(root, value=14)
    live.publish(root)
    after = selected()
    assert len(after) == 2
    assert {a["publication_snapshot"] for a in before} != {
        a["publication_snapshot"] for a in after}


def test_plot_browser_includes_verified_partial_measurements(tmp_path, monkeypatch):
    import lls_web_dashboard as dashboard
    feedback(tmp_path)
    result = live.publish(tmp_path)
    manifest = json.loads(Path(result["Manifest"]).read_text())
    run_id = 9100000002
    run = dict(run_id=run_id, run_folder=str(tmp_path), status_text="running")
    artifacts = dashboard.filesystem_artifacts_for_run(run)
    monkeypatch.setattr(dashboard, "fetch_run", lambda _: run)
    monkeypatch.setattr(dashboard, "fetch_artifacts", lambda _: artifacts)
    monkeypatch.setattr(dashboard, "sync_runtime_log_for_run", lambda _: 0)
    monkeypatch.setattr(dashboard, "extract_run_feature_policy", lambda _: {})
    # Only the inventory/transport is a fixture. Selection, publication
    # authority and plot-browser item construction use production code.
    monkeypatch.setattr(dashboard, "build_numeric_charts_from_artifacts", lambda *a, **k: [])
    assert dashboard.select_primary_result_artifacts(artifacts)[0] == []
    payload = dashboard.build_plot_browser_payload(run_id)
    images = [item for item in payload["items"] if item["kind"] == "image"]
    assert len(images) == manifest["png_count"] == 1
    assert images[0]["source"].startswith("reports/live_measurements/")


@pytest.mark.parametrize("target", ["csv", "png", "manifest", "lineage"])
def test_browser_rejects_changed_live_plot_pair_or_receipt(tmp_path, target):
    feedback(tmp_path)
    result = live.publish(tmp_path)
    path = Path(result["Manifest"])
    manifest = json.loads(path.read_text())
    chart = next(c for c in manifest["charts"] if c["status"] == "measured_checkpoint")
    changed = path if target == "manifest" else path.parent / (
        "checkpoint_plot_lineage.csv" if target == "lineage" else chart[target])
    changed.write_bytes(changed.read_bytes() + b"changed")
    assert not select_browser_snapshot(tmp_path)


def test_browser_does_not_promote_preview_from_other_run(tmp_path):
    source, output = tmp_path / "source", tmp_path / "preview"
    feedback(source)
    output.mkdir()
    live.publish(output, source_run_folder=source)
    assert not select_browser_snapshot(output)


def test_received_csi_sweep_has_one_csv_and_png_per_metric(tmp_path):
    # Export fixture only: verifies joint publication, not eight PHY passes.
    snrs = [40, 30, 20, 10, 0, -10, -20, -30]
    path = tmp_path / live.radio.RECEIVED_CSI
    path.parent.mkdir(parents=True)
    header = ("Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,RI,CQI,PMI,CRI,"
              "SourceSignal,CSIUCIDecodeOk,SNR_dB,SweepPointIndex,SchedulerAcceptedRank\n")
    path.write_text(header + "".join(
        f"DL,1,34,39,delivered,2,9,3,{point-1},received_CSI_UCI,1,{snr},{point},1\n"
        for point, snr in enumerate(snrs, 1)), encoding="utf-8")
    # Legacy producer values cannot contaminate received-report plots.
    feedback(tmp_path, value=15)
    result = live.publish(tmp_path)
    manifest_path = Path(result["Manifest"])
    manifest = json.loads(manifest_path.read_text())
    for name in ("CSI CQI timeline", "CSI RI timeline", "CSI PMI components timeline", "CSI CRI timeline"):
        matched = [c for c in manifest["charts"] if c["name"] == name]
        assert len(matched) == 1
        chart = matched[0]
        rows = list(csv.DictReader((manifest_path.parent / chart["csv"]).open(encoding="utf-8")))
        assert len(rows) == len(snrs)
        assert [float(r["snr_db"]) for r in rows] == snrs
        assert [int(r["sweep_point_index"]) for r in rows] == list(range(1, 9))
        assert all(r["source_table_logical_path"] == live.radio.RECEIVED_CSI for r in rows)
        if name == "CSI CRI timeline":
            assert [json.loads(r["component_values"]) for r in rows] == [[i] for i in range(8)]
        with Image.open(manifest_path.parent / chart["png"]) as png:
            assert png.format == "PNG"
            png.verify()


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


def test_multifile_input_snapshot_has_bounded_memory(tmp_path, monkeypatch):
    # Storage-only fixtures: no PHY performance or scientific chart claim.
    # Input size, not an arbitrary sample cap, must cease to own working RAM.
    sources = (live.radio.FEEDBACK, live.radio.CSI_TRIALS)
    count = 20_000
    for logical in sources:
        path = tmp_path / logical
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", newline="", encoding="utf-8") as out:
            writer = csv.writer(out)
            writer.writerow(["SampleIndex", "AuditDetail"])
            for index in range(count):
                writer.writerow([index, "fixture-only-" + "x"*512])
    monkeypatch.setattr(live, "SOURCES", sources)
    monkeypatch.setattr(live, "CHARTS", ())
    tracemalloc.start()
    try:
        result = live.publish(tmp_path)
        _, peak = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    assert peak < 8*1024*1024, f"Input payloads/rows retained in RAM: peak={peak}"
    manifest = json.loads(Path(result["Manifest"]).read_text())
    folder = Path(result["Manifest"]).parent
    for logical in sources:
        original = tmp_path / logical
        snapshot = folder / "sources" / logical
        assert live.digest(original.read_bytes()) == live.digest(snapshot.read_bytes())
        with snapshot.open(newline="", encoding="utf-8") as stream:
            assert sum(1 for _ in csv.DictReader(stream)) == count
    assert manifest["terminal_qualification"] is False
    print(f"LIVE_INPUT_SNAPSHOT_MEMORY sources=2 rows_each={count} python_peak_bytes={peak}")


def test_control_evm_live_snapshot_uses_streaming_consumer(tmp_path, monkeypatch):
    from test_lls_radio_measurement_plots import control_pairs
    logical = live.radio.CONTROL_EVM["CSI-RS EVM"][1]
    path = tmp_path / logical
    path.parent.mkdir(parents=True)
    path.write_bytes(control_pairs("CSI-RS"))
    old_read = Path.read_bytes
    def bounded_read(file):
        if file.suffix == ".csv":
            raise AssertionError("Local CSV inputs must use streaming snapshots/consumers")
        return old_read(file)
    monkeypatch.setattr(Path, "read_bytes", bounded_read)
    result = live.publish(tmp_path)
    manifest = json.loads(Path(result["Manifest"]).read_text())
    chart = next(c for c in manifest["charts"] if c["name"] == "CSI-RS EVM")
    assert chart["status"] == "measured_checkpoint"
    assert live.publish(tmp_path)["Status"] == "unchanged_verified_snapshot"


def test_unchanged_evm_bytes_reused_without_reducing_population(tmp_path, monkeypatch):
    from test_lls_radio_measurement_plots import control_pairs
    logical = live.radio.CONTROL_EVM["CSI-RS EVM"][1]
    path = tmp_path / logical
    path.parent.mkdir(parents=True)
    path.write_bytes(control_pairs("CSI-RS"))
    feedback(tmp_path)
    first = live.publish(tmp_path)
    first_manifest = json.loads(Path(first["Manifest"]).read_text())
    actual = live.materializer._specialized_chart_materialization
    calls = []
    def track(name, *args, **kwargs):
        calls.append(name)
        return actual(name, *args, **kwargs)
    monkeypatch.setattr(live.materializer, "_specialized_chart_materialization", track)
    feedback(tmp_path, value=12)
    second = live.publish(tmp_path)
    second_manifest = json.loads(Path(second["Manifest"]).read_text())
    assert "CSI-RS EVM" not in calls and "CSI CQI timeline" in calls
    chart = next(c for c in first_manifest["charts"] if c["name"] == "CSI-RS EVM")
    for field in ("csv", "png"):
        assert (Path(first["Manifest"]).parent / chart[field]).read_bytes() == (
            Path(second["Manifest"]).parent / chart[field]).read_bytes()
    assert next(c for c in second_manifest["charts"] if c["name"] == chart["name"]) == chart
    calls.clear()
    # Even a byte-level source edit forces complete re-evaluation.
    path.write_bytes(path.read_bytes() + b"\n")
    third = live.publish(tmp_path)
    assert "CSI-RS EVM" in calls
    # A changed unrelated input cannot rescue a corrupt old EVM plot.
    old_plot = Path(third["Manifest"]).parent / chart["png"]
    old_plot.write_bytes(b"corrupted")
    feedback(tmp_path, value=14)
    with pytest.raises(ValueError, match="receipt mismatch"):
        live.publish(tmp_path)


def test_changed_source_cannot_publish_new_latest(tmp_path, monkeypatch):
    path = feedback(tmp_path)
    live.publish(tmp_path)
    latest = tmp_path / "reports/live_measurements/latest.json"
    before = latest.read_bytes()
    feedback(tmp_path, value=12)
    actual = live.materializer._specialized_chart_materialization
    changed = False
    def concurrent_edit(*args, **kwargs):
        nonlocal changed
        value = actual(*args, **kwargs)
        if not changed:
            changed = True
            feedback(tmp_path, value=14)
        return value
    monkeypatch.setattr(live.materializer, "_specialized_chart_materialization", concurrent_edit)
    with pytest.raises(ValueError, match="Source changed"):
        live.publish(tmp_path)
    assert latest.read_bytes() == before
    assert ",14," in path.read_text()


@pytest.mark.parametrize("payload", [b'a,b\n1,"unfinished', b'a,b\n1,2\n3,4,5\n',
                                      b'a,b\n1,\xff\n'])
def test_torn_or_invalid_input_never_replaces_receipt(tmp_path, payload):
    path = feedback(tmp_path)
    live.publish(tmp_path)
    latest = tmp_path / "reports/live_measurements/latest.json"
    before = latest.read_bytes()
    path.write_bytes(payload)
    with pytest.raises((ValueError, csv.Error, UnicodeDecodeError)):
        live.publish(tmp_path)
    assert latest.read_bytes() == before


def test_input_added_during_render_is_not_a_complete_snapshot(tmp_path, monkeypatch):
    feedback(tmp_path)
    live.publish(tmp_path)
    latest = tmp_path / "reports/live_measurements/latest.json"
    before = latest.read_bytes()
    feedback(tmp_path, value=12)
    actual = live.materializer._specialized_chart_materialization
    extra = tmp_path / live.radio.CSI_TRIALS
    def add_source(*args, **kwargs):
        value = actual(*args, **kwargs)
        extra.write_text("Slot,Status\n", encoding="utf-8")
        return value
    monkeypatch.setattr(live.materializer, "_specialized_chart_materialization", add_source)
    with pytest.raises(ValueError, match="Source changed"):
        live.publish(tmp_path)
    assert latest.read_bytes() == before
    assert not list(latest.parent.glob(".live-stage-*"))


def test_cached_snapshot_rechecks_mutable_source_before_latest(tmp_path, monkeypatch):
    feedback(tmp_path)
    live.publish(tmp_path)
    latest = tmp_path / "reports/live_measurements/latest.json"
    before = latest.read_bytes()
    actual = live.file_digest
    changed = False
    def mutate_during_receipt_check(path):
        nonlocal changed
        value = actual(path)
        if Path(path).suffix == ".png" and not changed:
            changed = True
            feedback(tmp_path, value=12)
        return value
    monkeypatch.setattr(live, "file_digest", mutate_during_receipt_check)
    with pytest.raises(ValueError, match="Source changed"):
        live.publish(tmp_path)
    assert changed and latest.read_bytes() == before


def test_receipt_cannot_omit_source_hashes(tmp_path):
    feedback(tmp_path)
    result = live.publish(tmp_path)
    path = Path(result["Manifest"])
    manifest = json.loads(path.read_text())
    del manifest["artifact_sha256"]["sources/" + live.radio.FEEDBACK]
    path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ValueError, match="receipt mismatch"):
        live.publish(tmp_path)


def test_source_replaced_before_copy_is_rejected(tmp_path, monkeypatch):
    path = feedback(tmp_path)
    original = live._stat_identity
    called = False
    def replace_after_stat(stat):
        nonlocal called
        result = original(stat)
        if not called:
            called = True
            replacement = path.with_suffix(".replacement")
            replacement.write_text("a,b\n1,2\n", encoding="utf-8")
            replacement.replace(path)
        return result
    monkeypatch.setattr(live, "_stat_identity", replace_after_stat)
    with pytest.raises(ValueError, match="Source changed"):
        live.publish(tmp_path)
    assert not list(tmp_path.rglob("manifest.json"))
    assert not list((tmp_path / "reports/live_measurements").glob(".live-stage-*"))
