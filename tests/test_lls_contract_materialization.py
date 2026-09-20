from __future__ import annotations

import io
import hashlib
import json
import shutil
import sys
import tempfile
from pathlib import Path

from PIL import Image


REPO_ROOT = Path(__file__).absolute().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_contract_materializer as materializer  # noqa: E402


def _filesystem_artifacts(root: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for index, path in enumerate(sorted(p for p in root.rglob("*") if p.is_file()), 1):
        rows.append(
            {
                "artifact_id": index,
                "logical_path": path.relative_to(root).as_posix().lower(),
                "artifact_kind": "table_csv" if path.suffix == ".csv" else "image_png",
                "mime_type": "text/csv" if path.suffix == ".csv" else "image/png",
                "byte_size": path.stat().st_size,
                "filesystem_path": str(path),
                "metadata_json": "{}",
            }
        )
    return rows


def test_direct_contract_aliases_remain_producer_owned_cache_inputs() -> None:
    contract_paths = materializer._contract_artifact_paths()
    assert "reports/csv/all_csv_artifact_audit.csv" not in contract_paths
    assert "reports/csv/all_image_artifact_audit.csv" not in contract_paths
    assert materializer.manifest_logical_path() in contract_paths


def test_exact_filesystem_cache_detects_source_and_contract_byte_changes(monkeypatch) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        source = root / "air_interface" / "csv" / "measured.csv"
        contract_csv = root / "reports" / "csv" / "contract__x__plot.csv"
        contract_png = root / "reports" / "image" / "contract__x__plot.png"
        manifest = root / materializer.manifest_logical_path()
        coverage = root / materializer.coverage_logical_path()
        lineage = root / materializer.plot_lineage_logical_path()
        for path, payload in (
            (source, b"x,y\n1,2\n"),
            (contract_csv, b"x,y\n1,2\n"),
            (contract_png, b"png-bytes"),
            (manifest, b"manifest\n"),
            (coverage, b"coverage\n"),
            (lineage, b"lineage\n"),
        ):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload)
        monkeypatch.setattr(materializer, "_table_specs", lambda: [])
        monkeypatch.setattr(
            materializer,
            "_chart_specs",
            lambda: [{"chart_name": "plot", "section_slug": "x"}],
        )
        artifacts = _filesystem_artifacts(root)
        payload = materializer.write_filesystem_contract_cache(root, artifacts, {})
        assert payload["source_artifact_count"] == 1
        assert materializer.filesystem_contract_cache_current(
            root, _filesystem_artifacts(root), {}
        )

        source.write_bytes(b"x,y\n1,3\n")
        assert not materializer.filesystem_contract_cache_current(
            root, _filesystem_artifacts(root), {}
        )
        source.write_bytes(b"x,y\n1,2\n")
        contract_png.write_bytes(b"tampered-png")
        assert not materializer.filesystem_contract_cache_current(
            root, _filesystem_artifacts(root), {}
        )


def test_specialized_config_measured_view_uses_runtime_units_and_snr() -> None:
    dl_path = "air_interface/csv/dl_pdsch_trials.csv"
    payload = (
        b"ConfiguredSNR_dB,MeasuredSINR_dB,ServingRSRP_dBm,CSI_RSRP_dBm,CSI_RSRP_dB\n"
        b"12,18,-89,-75,24\n"
    )
    artifacts = {
        dl_path: {
            "artifact_id": 1,
            "logical_path": dl_path,
            "artifact_kind": "table_csv",
            "mime_type": "text/csv",
        }
    }
    result = materializer._specialized_live_report_table(
        "reports_config_vs_measured_conflicts_v",
        artifacts,
        fetch_artifact_bytes=lambda artifact_id: payload,
        run_id=7,
        run_row={},
        feature_policy={},
    )
    assert result is not None
    header, rows = materializer._decode_csv_dicts(result["data"])
    assert "mean_csi_rsrp_dbm" in header
    assert "mean_csi_rsrp_db" not in header
    assert rows[0]["configured_snr_db"] == "12.0"
    assert rows[0]["mean_csi_rsrp_dbm"] == "-75.0"
    assert rows[0]["measured_minus_configured_snr_db"] == "6.0"


def test_prach_component_filters_inapplicable_config_measured_view() -> None:
    policy = {"runner_profile": "prach_detection"}
    assert materializer.contract_artifact_is_policy_filtered(
        "reports/csv/reports_config_vs_measured_conflicts_v.csv",
        policy,
        contract_name="reports_config_vs_measured_conflicts_v",
    )
    assert materializer.contract_artifact_is_policy_filtered(
        "reports/csv/contract__generic-investigator-views__config-vs-measured-conflict-dashboard.csv",
        policy,
        contract_name="config vs measured conflict dashboard",
    )


def test_prach_value_semantics_uses_native_runtime_categories() -> None:
    prach_path = "air_interface/csv/prach_trials.csv"
    payload = (
        b"Status,ThresholdMode,Notes,EvidenceScope,ChannelModelApplied,PRACHDesign\n"
        b"PASS,fixed,correct_detection,in_path,AWGN,nr_baseline\n"
    )
    artifacts = {
        prach_path: {
            "artifact_id": 1,
            "logical_path": prach_path,
            "artifact_kind": "table_csv",
            "mime_type": "text/csv",
        }
    }
    result = materializer._specialized_live_report_table(
        "reports_value_semantics_coverage_v",
        artifacts,
        fetch_artifact_bytes=lambda artifact_id: payload,
        run_id=11,
        run_row={"profile_name": "prach_detection"},
        feature_policy={"runner_profile": "prach_detection"},
    )
    assert result is not None
    _, rows = materializer._decode_csv_dicts(result["data"])
    observed = {(row["artifact_family"], row["field_name"], row["enum_value"])
                for row in rows}
    assert ("prach", "Status", "PASS") in observed
    assert ("prach", "ThresholdMode", "fixed") in observed
    assert ("prach", "EvidenceScope", "in_path") in observed


def test_ai_benchmark_filters_inapplicable_connected_link_investigator_views() -> None:
    policy = {"runner_profile": "ai_benchmark"}
    for path, contract_name in (
        (
            "reports/csv/reports_config_vs_measured_conflicts_v.csv",
            "reports_config_vs_measured_conflicts_v",
        ),
        (
            "reports/csv/reports_value_semantics_coverage_v.csv",
            "reports_value_semantics_coverage_v",
        ),
        (
            "reports/csv/contract__generic-investigator-views__config-vs-measured-conflict-dashboard.csv",
            "config vs measured conflict dashboard",
        ),
        (
            "reports/csv/contract__generic-investigator-views__value-semantics-coverage-chart.csv",
            "value semantics coverage chart",
        ),
    ):
        assert materializer.contract_artifact_is_policy_filtered(
            path,
            policy,
            contract_name=contract_name,
        )


def test_forced_filesystem_refresh_replaces_stale_derived_truth_alias(
    monkeypatch,
) -> None:
    """Terminal force-refresh must not preserve a pre-finalization verdict."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        source_path = "reports/csv/truth_contract_summary.csv"
        target_path = "analytics/csv/truth_policy_analytics.csv"
        source_bytes = b"RuntimeTruthContractOk,ResultOk,StrictTruthFailureCount\n1,1,0\n"
        stale_bytes = b"RuntimeTruthContractOk,ResultOk,StrictTruthFailureCount\n0,0,4\n"
        (root / source_path).parent.mkdir(parents=True, exist_ok=True)
        (root / target_path).parent.mkdir(parents=True, exist_ok=True)
        (root / source_path).write_bytes(source_bytes)
        (root / target_path).write_bytes(stale_bytes)

        table_spec = {
            "table_name": "truth_policy_analytics",
            "logical_path": target_path,
            "section_title": "Truth analytics",
            "section_slug": "truth-analytics",
        }
        monkeypatch.setattr(materializer, "_table_specs", lambda: [table_spec])
        monkeypatch.setattr(materializer, "_chart_specs", lambda: [])
        monkeypatch.setitem(
            materializer.CONTRACT_TABLE_ALIAS_PATHS,
            "truth_policy_analytics",
            [source_path],
        )
        payloads = {1: source_bytes, 2: stale_bytes}
        artifacts = [
            {
                "artifact_id": 1,
                "logical_path": source_path,
                "artifact_kind": "table_csv",
                "mime_type": "text/csv",
                "metadata_json": "{}",
            },
            {
                "artifact_id": 2,
                "logical_path": target_path,
                "artifact_kind": "table_csv",
                "mime_type": "text/csv",
                "metadata_json": "{}",
            },
        ]
        materializer.materialize_run_contract_artifacts(
            {"run_id": 1, "run_folder": str(root), "status_text": "completed"},
            artifacts,
            fetch_artifact_bytes=lambda artifact_id: payloads[int(artifact_id)],
            db_connection_factory=None,
            feature_policy={},
            force=True,
            filesystem_only=True,
        )
        assert (root / target_path).read_bytes() == source_bytes


def test_yaml_disabled_raster_output_filters_charts_not_primary_tables() -> None:
    policy = {"raster_output_enabled": False}
    assert materializer.contract_artifact_is_policy_filtered(
        "reports/csv/contract__receiver__llr-histograms.csv",
        policy,
        contract_name="LLR histograms",
    )
    assert not materializer.contract_artifact_is_policy_filtered(
        "air_interface/csv/dl_pdsch_trials.csv",
        policy,
        contract_name="live_pdsch_trials",
    )


def test_filesystem_materializer_honors_yaml_raster_authority() -> None:
    source = (
        REPO_ROOT / "scripts" / "materialize_lls_contract_artifacts.py"
    ).read_text(encoding="utf-8")
    assert 'raster_output_enabled = bool(policy.get("raster_output_enabled", True))' in source
    assert "args.replace_existing_rasters_from_csv and raster_output_enabled" in source
    assert "raster_replacement_executed = bool(" in source
    assert '"raster_replacement_executed": raster_replacement_executed' in source


def test_forced_filesystem_materialization_refreshes_terminal_source_index() -> None:
    source = (
        REPO_ROOT / "scripts" / "materialize_lls_contract_artifacts.py"
    ).read_text(encoding="utf-8")
    cache_clear = source.index(
        'if args.force:\n            dash.clear_dashboard_caches(int(run_row.get("run_id") or 0))'
    )
    source_index = source.index(
        "initial_artifacts = dash.filesystem_artifacts_for_run(run_row)"
    )
    assert cache_clear < source_index


def test_native_prach_snapshot_is_a_producer_owned_canonical_source() -> None:
    target = "reports/csv/live_prach_native_allocation_snapshot.csv"
    assert materializer._table_sources(  # noqa: SLF001
        "live_prach_native_allocation_snapshot"
    ) == [target]


def test_image_artifact_audit_is_materialized_after_contract_charts() -> None:
    source = (REPO_ROOT / "apps" / "lls_contract_materializer.py").read_text(
        encoding="utf-8"
    )
    chart_loop = source.index("for chart_spec in _chart_specs():")
    late_audit = source.index('late_image_audit_name = "all_image_artifact_audit"')
    coverage = source.index("coverage = coverage_summary(final_artifacts, feature_policy)")
    assert chart_loop < late_audit < coverage
    assert "post_render_exact_image_artifact_audit" in source


def test_filesystem_replacement_restores_declared_artifact_pngs_before_indexing() -> None:
    source = (
        REPO_ROOT / "scripts" / "materialize_lls_contract_artifacts.py"
    ).read_text(encoding="utf-8")
    deletion = source.index("io_path(target).unlink()")
    declared_rasters = source.index(
        "declared_artifact_rasters = materialize_declared_artifact_generation_rasters("
    )
    report_rasters = source.index(
        "declared_report_rasters = materialize_declared_report_rasters(run_folder)"
    )
    filesystem_index = source.index("run_row = dash.filesystem_run_row_from_folder(run_folder)")
    assert deletion < declared_rasters < filesystem_index
    assert deletion < report_rasters < filesystem_index
    assert '"declared_artifact_rasters_regenerated"' in source
    assert '"declared_report_rasters_regenerated"' in source


def test_runtime_geometry_profile_prach_and_single_ue_adapters_use_exact_rows() -> None:
    payloads = {
        701: materializer._encode_csv(  # noqa: SLF001
            ["CanonicalSlot", "UEID", "X_m", "Y_m", "Distance2D_m", "Distance3D_m", "Pathloss_dB", "AppliedDopplerHz"],
            [[0, 1, 10.0, 20.0, 22.36, 23.0, 91.5, 31.0], [1, 1, 11.0, 21.0, 23.71, 24.2, 92.0, 32.0]],
        ),
        702: materializer._encode_csv(  # noqa: SLF001
            ["StageOrder", "StageName", "StageElapsed_s", "BundleElapsed_s"],
            [[1, "frame", 0.01, 0.01], [2, "pdsch", 0.02, 0.03]],
        ),
        703: materializer._encode_csv(  # noqa: SLF001
            ["RAUEId", "CorrelationPeak", "DetectionThreshold", "PDPAverageNoiseFloor", "DetectorPeakLagSamples"],
            [[1, 0.75, 0.5, 0.02, 3]],
        ),
        704: materializer._encode_csv(  # noqa: SLF001
            ["UEID", "UserThroughput_Mbps"], [[1, 12.5]],
        ),
    }
    existing = {
        "geometry/csv/trajectory_geometry.csv": {"artifact_id": 701, "logical_path": "geometry/csv/trajectory_geometry.csv"},
        "reports/csv/runtime_stage_profile.csv": {"artifact_id": 702, "logical_path": "reports/csv/runtime_stage_profile.csv"},
        "air_interface/csv/prach_trials.csv": {"artifact_id": 703, "logical_path": "air_interface/csv/prach_trials.csv"},
        "reports/csv/live_user_performance_snapshot.csv": {"artifact_id": 704, "logical_path": "reports/csv/live_user_performance_snapshot.csv"},
    }
    fetch = lambda artifact_id: payloads[artifact_id]

    trajectory = materializer._specialized_chart_materialization("UE trajectory overlay", existing, fetch, 55)  # noqa: SLF001
    assert trajectory is not None
    assert "10.0,20.0" in trajectory["csv_bytes"].decode("utf-8")
    assert "Runtime UE trajectory" in trajectory["img_bytes"].decode("utf-8")

    profile = materializer._specialized_chart_materialization("stage latency", existing, fetch, 55)  # noqa: SLF001
    assert profile is not None
    profile_text = profile["csv_bytes"].decode("utf-8")
    assert "frame,10.0" in profile_text and "pdsch,20.0" in profile_text

    prach = materializer._specialized_chart_materialization("PRACH peak search timeline", existing, fetch, 55)  # noqa: SLF001
    assert prach is not None
    prach_text = prach["csv_bytes"].decode("utf-8")
    assert "0.75,0.5,0.02,3.0" in prach_text

    per_ue = materializer._specialized_chart_materialization("per-UE throughput", existing, fetch, 55)  # noqa: SLF001
    assert per_ue is not None
    assert "Evidence shape: operating point" in per_ue["img_bytes"].decode("utf-8")


def test_single_ue_distribution_and_uninstrumented_resource_charts_are_policy_disabled() -> None:
    policy = {
        "num_ues": 1,
        "traffic_runtime_enabled": True,
        "profiler_enabled": True,
        "resource_profiler_enabled": False,
        "worker_profiler_enabled": False,
        "database_profiler_enabled": False,
        "artifact_timing_enabled": False,
        "api_profiler_enabled": False,
        "parallel_determinism_enabled": False,
    }
    for chart_name in ("throughput CDF", "throughput percentile plots", "CPU cycles", "memory usage", "worker timelines", "DB write latency", "export lag", "API message rate", "single-thread vs multi-thread determinism"):
        assert materializer.contract_artifact_is_policy_filtered(
            f"analytics/image/{chart_name}.png", policy, contract_name=chart_name
        )
    assert not materializer.contract_artifact_is_policy_filtered(
        "analytics/image/per-UE throughput.png", policy, contract_name="per-UE throughput"
    )


def test_contract_plot_lineage_binds_exact_raster_and_dataset_bytes() -> None:
    image_buffer = io.BytesIO()
    Image.new("RGB", (37, 23), color=(12, 34, 56)).save(
        image_buffer, format="PNG"
    )
    image_bytes = image_buffer.getvalue()
    source_bytes = b"x_value,y_value\n0,1\n1,2\n"
    row = materializer._contract_plot_lineage_row(  # noqa: SLF001
        "contract__test__curve",
        "analytics/image/contract__test__curve.png",
        "analytics/csv/contract__test__curve.csv",
        image_bytes,
        source_bytes,
    )
    assert materializer.plot_lineage_logical_path() == (
        "reports/csv/contract_plot_lineage.csv"
    )
    assert row[3] == hashlib.sha256(source_bytes).hexdigest()
    assert row[4] == hashlib.sha256(image_bytes).hexdigest()
    assert row[5:8] == [37, 23, "image/png"]
    assert row[8:12] == [1, 1, "apps.lls_contract_materializer", "pass"]


def test_filesystem_contract_alias_png_gets_exact_lineage() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        csv_rel = "analytics/csv/contract__section__metric.csv"
        png_rel = "analytics/image/contract__section__metric.png"
        (root / csv_rel).parent.mkdir(parents=True, exist_ok=True)
        (root / png_rel).parent.mkdir(parents=True, exist_ok=True)
        (root / csv_rel).write_bytes(b"x,y\n1,2\n")
        image = Image.new("RGB", (16, 16), "white")
        image.save(root / png_rel, format="PNG")
        rows: list[list[object]] = []
        materializer._append_filesystem_contract_alias_lineage(  # noqa: SLF001
            str(root), rows
        )
        assert len(rows) == 1
        assert rows[0][1] == png_rel
        assert rows[0][2] == csv_rel
        assert rows[0][3] == hashlib.sha256((root / csv_rel).read_bytes()).hexdigest()
        assert rows[0][4] == hashlib.sha256((root / png_rel).read_bytes()).hexdigest()
def test_prb_heatmap_and_dl_power_use_explicit_runtime_mappings() -> None:
    payloads = {
        1: materializer._encode_csv(  # noqa: SLF001
            ["cell_id", "slot", "rb_index", "occupancy_count"],
            [[1, 4, 0, 2], [1, 4, 1, 2], [1, 5, 0, 1], [1, 5, 1, 1]],
        ),
        2: materializer._encode_csv(  # noqa: SLF001
            ["direction", "state", "dl_tx_power_dbm", "cell_id", "ue_id", "frame", "slot"],
            [["DL", "active_tx", 46.0, 1, 7, 0, 4]],
        ),
        3: materializer._encode_csv(  # noqa: SLF001
            ["Frame", "Slot", "UEID", "AppliedBeamIndexSet"],
            [[0, 4, 7, 3]],
        ),
    }
    existing = {
        "reports/csv/prb_allocation_heatmap.csv": {
            "artifact_id": 1,
            "logical_path": "reports/csv/prb_allocation_heatmap.csv",
            "artifact_kind": "table_csv",
        },
        "reports/csv/live_power_runtime_table.csv": {
            "artifact_id": 2,
            "logical_path": "reports/csv/live_power_runtime_table.csv",
            "artifact_kind": "table_csv",
        },
        "packet_flow/csv/live_dl_scheduler_grants.csv": {
            "artifact_id": 3,
            "logical_path": "packet_flow/csv/live_dl_scheduler_grants.csv",
            "artifact_kind": "table_csv",
        },
    }
    fetch = lambda artifact_id: payloads[int(artifact_id)]
    heatmap = materializer._specialized_chart_materialization(  # noqa: SLF001
        "PRB heatmap", existing, fetch, 91
    )
    assert heatmap is not None
    assert heatmap["source_mapping_status"] == "exact"
    assert "slot,rb_index,occupancy_value" in heatmap["csv_bytes"].decode("utf-8")
    power = materializer._specialized_chart_materialization(  # noqa: SLF001
        "DL Tx power per cell / beam / UE", existing, fetch, 91
    )
    assert power is not None
    assert power["source_mapping_status"] == "exact"
    power_csv = power["csv_bytes"].decode("utf-8")
    assert "46.0,1,3,7" in power_csv
    assert "no configured power or beam value is substituted" in power["note"].lower()


def test_csv_decoder_accepts_runtime_ldpc_vector_larger_than_python_default() -> None:
    parity_vector = "|".join("1" if index % 2 else "0" for index in range(80000))
    payload = materializer._encode_csv(  # noqa: SLF001
        ["run_id", "MeasuredLDPCParityCheckVector"],
        [["runtime-1", parity_vector]],
    )
    assert len(parity_vector.encode("utf-8")) > 131072
    positional_header, positional_rows = materializer._decode_csv(payload)  # noqa: SLF001
    assert positional_header == ["run_id", "MeasuredLDPCParityCheckVector"]
    assert positional_rows == [["runtime-1", parity_vector]]
    header, rows = materializer._decode_csv_dicts(payload)  # noqa: SLF001
    assert header == ["run_id", "MeasuredLDPCParityCheckVector"]
    assert rows == [{"run_id": "runtime-1", "MeasuredLDPCParityCheckVector": parity_vector}]


def test_low_information_reason_png_is_not_a_real_contract_chart() -> None:
    svg = materializer._render_svg_plot(  # noqa: SLF001
        "single point trend",
        "runtime evidence",
        {"mode": "line", "x_label": "Slot", "y_label": "BLER", "points": [[1.0, 0.0]]},
        ["rows=1"],
    )
    png = materializer._rasterize_contract_png(  # noqa: SLF001
        svg,
        source_mime_type="image/svg+xml",
        source_logical_path="internal://test/single-point.vector",
    )
    assert materializer._png_low_information_reason(png) == "all_zero_metric_values"  # noqa: SLF001
    assert materializer._is_placeholder_materialization_status(  # noqa: SLF001
        "generated_low_information_reason_png"
    )


def test_explicit_evidence_shapes_preserve_flat_truth_without_enabling_fake_curves() -> None:
    flat_timeline = {
        "mode": "line",
        "points": [[1.0, 0.0], [2.0, 0.0], [3.0, 0.0]],
        "evidence_shape_policy": "observed_timeline",
        "sample_count": 3,
    }
    reason, _details = materializer._dataset_low_information_reason(flat_timeline)  # noqa: SLF001
    assert reason == ""

    one_state_distribution = {
        "mode": "bar",
        "points": [[0.0, 12.0]],
        "evidence_shape_policy": "observed_distribution",
        "sample_count": 12,
    }
    reason, _details = materializer._dataset_low_information_reason(one_state_distribution)  # noqa: SLF001
    assert reason == ""

    zero_response_relation = {
        "mode": "scatter",
        "points": [[10.0, 0.0], [20.0, 0.0]],
        "evidence_shape_policy": "observed_relation",
        "sample_count": 12,
    }
    reason, _details = materializer._dataset_low_information_reason(zero_response_relation)  # noqa: SLF001
    assert reason == ""

    unlabelled_one_point_curve = {"mode": "line", "points": [[20.0, 0.0]]}
    reason, _details = materializer._dataset_low_information_reason(unlabelled_one_point_curve)  # noqa: SLF001
    assert reason == "all_zero_metric_values"


def test_reliability_uses_weighted_bit_denominator_and_exports_wilson_interval() -> None:
    payload = materializer._encode_csv(  # noqa: SLF001
        ["BitErrors", "BitsCompared", "CRCPass", "ConfiguredSNR_dB"],
        [[0, 100, 1, 20], [5, 900, 0, 20]],
    )
    existing = {
        "air_interface/csv/dl_pdsch_trials.csv": {
            "artifact_id": 701,
            "logical_path": "air_interface/csv/dl_pdsch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    result = materializer._specialized_chart_materialization(  # noqa: SLF001
        "BER", existing, lambda _artifact_id: payload, 44
    )
    assert result is not None
    csv_text = result["csv_bytes"].decode("utf-8")
    assert "metric_value,error_count,sample_count,ci95_lower,ci95_upper" in csv_text
    assert "BER,0.005,5.0,1000" in csv_text
    png = materializer._rasterize_contract_png(  # noqa: SLF001
        result["img_bytes"],
        source_mime_type="image/svg+xml",
        source_logical_path="internal://test/weighted-ber.vector",
    )
    assert materializer._png_low_information_reason(png) == ""  # noqa: SLF001


def test_prach_probability_exports_wilson_bounds_from_trial_flags() -> None:
    payload = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "ConfiguredSNR_dB", "DecodeSuccess", "FalseAlarmFlag"],
        [[1, 20, 1, 0], [2, 20, 0, 0]],
    )
    existing = {
        "air_interface/csv/prach_trials.csv": {
            "artifact_id": 702,
            "logical_path": "air_interface/csv/prach_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    result = materializer._specialized_chart_materialization(  # noqa: SLF001
        "P_D", existing, lambda _artifact_id: payload, 45
    )
    assert result is not None
    csv_text = result["csv_bytes"].decode("utf-8")
    assert "ci95_lower,ci95_upper" in csv_text
    assert ",0.5,2," in csv_text
    svg_text = result["img_bytes"].decode("utf-8")
    assert ">1<" in svg_text
    # No measured quality axis exists: show one aggregate and its uncertainty,
    # not a curve over the configured SNR label or a missing-evidence card.
    assert all(label in svg_text for label in ["95% lower", "Observed", "95% upper", "denominator=2"])
    assert "not three operating points" in svg_text
    _, probability_rows = materializer._decode_csv_dicts(result["csv_bytes"])
    assert len(probability_rows) == 1
    assert float(probability_rows[0]["metric_value"]) == .5
    assert int(probability_rows[0]["sample_count"]) == 2
    assert 0 <= float(probability_rows[0]["ci95_lower"]) < .5 < float(probability_rows[0]["ci95_upper"]) <= 1
    png = materializer._rasterize_contract_png(  # noqa: SLF001
        result["img_bytes"],
        source_mime_type="image/svg+xml",
        source_logical_path="internal://test/prach-pd.vector",
    )
    assert materializer._png_low_information_reason(png) == ""  # noqa: SLF001


def test_scientific_renderers_publish_numeric_axes_and_truthful_constellation_counts() -> None:
    bar_svg = materializer._render_svg_plot(  # noqa: SLF001
        "beam gap",
        "runtime values",
        {
            "mode": "bar",
            "x_label": "Beam gain gap dB",
            "y_label": "Count",
            "points": [[1.25, 2.0], [1.75, 5.0]],
        },
        ["samples=7"],
    ).decode("utf-8")
    assert "Beam gain gap dB" in bar_svg
    assert "Count" in bar_svg
    assert 'transform="rotate(-90' in bar_svg
    assert ">1.25<" in bar_svg and ">1.75<" in bar_svg

    payload = materializer._encode_csv(  # noqa: SLF001
        ["Direction", "RawEqualizedReal", "RawEqualizedImag", "ReferenceSymbolReal", "ReferenceSymbolImag"],
        [
            ["DL", -0.7, 0.7, -0.707, 0.707],
            ["DL", 0.7, -0.7, 0.707, -0.707],
            ["UL", -0.7, -0.7, -0.707, -0.707],
        ],
    )
    existing = {
        "reports/csv/equalized_constellations.csv": {
            "artifact_id": 1,
            "logical_path": "reports/csv/equalized_constellations.csv",
            "artifact_kind": "table_csv",
        }
    }
    result = materializer._specialized_chart_materialization(  # noqa: SLF001
        "post-equalization constellation", existing, lambda _artifact_id: payload, 91
    )
    assert result is not None
    constellation_svg = result["img_bytes"].decode("utf-8")
    assert "dl_rows=2" in constellation_svg
    assert "ul_rows=1" in constellation_svg
    assert "In-phase" in constellation_svg
    assert "Quadrature" in constellation_svg


def test_constellation_preview_includes_late_adapted_samples(monkeypatch) -> None:
    rows = [["DL", 0.7, 0.7, 0.707, 0.707] for _ in range(1000)]
    rows.append(["DL", 0.15, -0.45, 0.154, -0.463])
    payload = materializer._encode_csv(
        ["Direction", "RawEqualizedReal", "RawEqualizedImag", "ReferenceSymbolReal", "ReferenceSymbolImag"], rows
    )
    existing = {"reports/csv/equalized_constellations.csv": {
        "artifact_id": 1, "logical_path": "reports/csv/equalized_constellations.csv", "artifact_kind": "table_csv"
    }}
    captured = []
    def render(_title, _subtitle, panels, _summary):
        captured.extend(panels)
        return b"preview"
    monkeypatch.setattr(materializer, "_render_scatter_panels_svg", render)
    result = materializer._specialized_chart_materialization(
        "post-equalization constellation", existing, lambda _id: payload, 91
    )
    assert result["source_row_count"] == 1001
    points, references = captured[0][1:]
    assert len(points) == 450
    assert points[0][:2] == (0.7, 0.7)
    assert points[-1][:2] == (0.15, -0.45)
    assert references == [(0.707, 0.707), (0.154, -0.463)]


def test_symbol_decision_histogram_retains_resolved_constellation_sources() -> None:
    payload = materializer._encode_csv(  # noqa: SLF001
        ["Direction", "EqualizedReal", "EqualizedImag", "ReferenceSymbolReal", "ReferenceSymbolImag"],
        [["DL", 0.70, -0.70, 0.707, -0.707]],
    )
    path = "air_interface/csv/dl_constellation_samples.csv"
    result = materializer._specialized_chart_materialization(  # noqa: SLF001
        "symbol decision error histogram",
        {path: {"artifact_id": 1}},
        lambda _artifact_id: payload,
        91,
    )
    assert result is not None
    assert result["source_table_path"] == path
    assert result["source_row_count"] == 1


def test_contract_cleanup_never_removes_runtime_source_csv(tmp_path: Path) -> None:
    stale = tmp_path / "analytics" / "image" / "contract__old__chart.png"
    source = tmp_path / "air_interface" / "csv" / "dl_pdsch_trials.csv"
    stale.parent.mkdir(parents=True)
    source.parent.mkdir(parents=True)
    stale.write_bytes(b"old-generated-chart")
    source.write_text("Frame,Slot\n1,1\n", encoding="utf-8")
    materializer._remove_materializer_owned_file(  # noqa: SLF001
        str(tmp_path), "analytics/image/contract__old__chart.png"
    )
    materializer._remove_materializer_owned_file(  # noqa: SLF001
        str(tmp_path), "air_interface/csv/dl_pdsch_trials.csv"
    )
    assert not stale.exists()
    assert source.exists()
import lls_output_contract as output_contract  # noqa: E402
import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    report_sections = output_contract.product_sections_payload("reports")
    analytics_sections = output_contract.product_sections_payload("analytics")

    scheduler_section = next(
        section for section in report_sections if section["slug"] == "scheduler-mac-queue-qos-power-control-uci-flow"
    )
    queue_table = next(table for table in scheduler_section["tables"] if table["table_name"] == "live_queue_state")
    assert materializer.table_contract_path(queue_table) == "reports/csv/live_queue_state.csv"
    assert dash.contract_table_candidate_paths(queue_table)[0] == "reports/csv/live_queue_state.csv"

    waveform_section = next(
        section for section in analytics_sections if section["slug"] == "waveform-time-domain-analytics"
    )
    tx_chart = next(chart for chart in waveform_section["charts"] if chart["chart_name"] == "Tx waveform")
    chart_paths = dash.contract_chart_candidate_paths(tx_chart)
    assert materializer.chart_contract_csv_path(tx_chart) in chart_paths
    assert materializer.chart_contract_image_path(tx_chart) in chart_paths

    chart_path = materializer.chart_contract_image_path(tx_chart)
    assert chart_path.endswith(".png")
    assert "waveform-time-domain-analytics" in chart_path
    assert "tx-waveform" in chart_path

    csv_path = materializer.chart_contract_csv_path(tx_chart)
    assert csv_path.endswith(".csv")
    assert csv_path.startswith("analytics/csv/")

    manifest = materializer.manifest_logical_path()
    assert manifest == "reports/csv/contract_materialization_manifest.csv"

    coverage = materializer.coverage_logical_path()
    assert coverage == "reports/csv/contract_materialization_coverage.csv"

    with tempfile.TemporaryDirectory() as temporary_root:
        long_root = Path(temporary_root) / ("materializer-long-root-" + "x" * 100)
        long_logical = (
            "reports/image/contract__" + "long-chart-name-" * 8 + ".png"
        )
        long_payload = b"filesystem-long-path-regression"
        materializer._write_file_if_possible(  # noqa: SLF001
            str(long_root), long_logical, long_payload
        )
        long_target = long_root / Path(*long_logical.split("/"))
        assert materializer._windows_long_path(long_target).read_bytes() == long_payload  # noqa: SLF001
        shutil.rmtree(materializer._windows_long_path(long_root))  # noqa: SLF001

    chart_csv = materializer._chart_dataset_csv(  # noqa: SLF001
        36,
        "throughput",
        {
            "mode": "line",
            "x_label": "slot",
            "y_label": "throughput_mbps",
            "points": [[1, 12.5], [2, 15.0]],
        },
        "system/csv/system_time_series.csv",
        240,
        "derived_chart_dataset",
        "derived from persisted source rows",
    ).decode("utf-8")
    assert "chart_name,chart_mode,x_label,y_label,point_index,x_value,y_value" in chart_csv
    assert "throughput,line,slot,throughput_mbps,1,1,12.5" in chart_csv
    assert "system/csv/system_time_series.csv" in chart_csv
    assert "source_mapping_status" in chart_csv
    assert "exact" in chart_csv

    constant_svg = materializer._render_svg_plot(  # noqa: SLF001
        "beam gain gap histogram",
        "Beam gap distribution from exported runtime beam metrics.",
        {"mode": "bar", "x_label": "Beam gap (dB)", "y_label": "Count", "points": [[0.0, 1546.0]]},
        ["samples=1546"],
    ).decode("utf-8")
    assert "visual_gate=single_bucket_distribution" in constant_svg
    assert "would not support a defensible chart conclusion" in constant_svg

    useful_bar_svg = materializer._render_svg_plot(  # noqa: SLF001
        "rank distribution",
        "Rank/layer distribution from runtime rows.",
        {"mode": "bar", "x_label": "Rank", "y_label": "Count", "points": [[1.0, 100.0], [2.0, 45.0]]},
        ["samples=145"],
    ).decode("utf-8")
    assert "visual_gate=" not in useful_bar_svg
    assert "<rect" in useful_bar_svg

    raster_png = materializer._rasterize_contract_png(  # noqa: SLF001
        useful_bar_svg.encode("utf-8"),
        source_mime_type="image/svg+xml",
        source_logical_path="internal://test/rank-distribution.svg",
    )
    assert raster_png.startswith(b"\x89PNG\r\n\x1a\n")
    with Image.open(io.BytesIO(raster_png)) as raster_image:
        assert raster_image.format == "PNG"
        assert raster_image.width >= 640
        assert raster_image.height >= 360

    jpeg_buffer = io.BytesIO()
    Image.new("RGB", (32, 24), color=(8, 122, 112)).save(jpeg_buffer, format="JPEG")
    jpeg_as_png = materializer._rasterize_contract_png(  # noqa: SLF001
        jpeg_buffer.getvalue(),
        source_mime_type="image/jpeg",
        source_logical_path="reports/image/legacy-source.jpeg",
    )
    assert jpeg_as_png.startswith(b"\x89PNG\r\n\x1a\n")
    with Image.open(io.BytesIO(jpeg_as_png)) as converted_image:
        assert converted_image.format == "PNG"
        assert converted_image.size == (32, 24)

    assert materializer.EXACT_CHART_FAMILY_CONTRACTS["heatmap"]["required_columns"] == ("x_value", "y_value", "z_value")
    assert materializer.EXACT_CHART_FAMILY_CONTRACTS["timeline"]["required_columns"] == ("x_value", "y_value")

    for unsafe_chart_name in ["fake heatmap", "fake serving map", "fake beam timeline"]:
        exact_dataset, mapping_status, reason = materializer._dataset_from_exact_chart_contract(  # noqa: SLF001
            unsafe_chart_name,
            "reports/csv/generic_numeric_source.csv",
            ["Frame", "SomeMetric"],
            [["1", "5"], ["2", "6"], ["3", "7"]],
        )
        assert exact_dataset is None
        assert mapping_status == "invalid"
        assert "Generic numeric-column inference is disabled" in reason or "exact direct source" in reason
        invalid_csv = materializer._chart_dataset_csv(  # noqa: SLF001
            37,
            unsafe_chart_name,
            exact_dataset,
            "reports/csv/generic_numeric_source.csv",
            3,
            "invalid_source_mapping",
            reason,
            mapping_status,
        ).decode("utf-8")
        assert "source_mapping_status" in invalid_csv
        assert "invalid" in invalid_csv
        assert ",line," not in invalid_csv, "Unsafe chart families must not become generic line plots."

    exact_timeline, mapping_status, _reason = materializer._dataset_from_exact_chart_contract(  # noqa: SLF001
        "real runtime timeline",
        "reports/csv/exact_chart_dataset.csv",
        ["chart_mode", "x_label", "y_label", "x_value", "y_value"],
        [["line", "slot", "metric", "1", "5"], ["line", "slot", "metric", "2", "6"], ["line", "slot", "metric", "3", "7"]],
    )
    assert exact_timeline is not None
    assert mapping_status == "exact"
    assert exact_timeline["mode"] == "line"

    constant_timeline, mapping_status, reason = materializer._dataset_from_exact_chart_contract(  # noqa: SLF001
        "constant runtime timeline",
        "reports/csv/exact_chart_dataset.csv",
        ["chart_mode", "x_label", "y_label", "x_value", "y_value"],
        [["line", "slot", "metric", "1", "5"], ["line", "slot", "metric", "2", "5"], ["line", "slot", "metric", "3", "5"]],
    )
    assert constant_timeline is None
    assert mapping_status == "invalid"
    assert "constant/single y-series" in reason

    finalized = materializer._finalize_chart_materialization_result(  # noqa: SLF001
        {
            "csv_bytes": materializer._encode_csv(["run_id", "chart_name"], [[1, "unavailable chart"]]),  # noqa: SLF001
            "img_bytes": b"<svg></svg>",
            "csv_status": "unavailable_exact_reason",
            "image_status": "generated_unavailable_reason_svg",
        }
    )
    assert finalized is not None
    finalized_csv = finalized["csv_bytes"].decode("utf-8")
    assert "source_mapping_status" in finalized_csv
    assert "unavailable" in finalized_csv

    impairment_section = next(
        section for section in analytics_sections if section["slug"] == "impairments-tracking-analytics"
    )
    iq_chart = next(chart for chart in impairment_section["charts"] if chart["chart_name"] == "IQ imbalance summary")
    iq_paths = dash.contract_chart_candidate_paths(iq_chart)
    assert materializer.chart_contract_csv_path(iq_chart) in iq_paths
    assert materializer.chart_contract_image_path(iq_chart) in iq_paths
    assert "rf/csv/probe_rf_iq_imbalance.csv" in iq_paths
    assert "rf/csv/iq_imbalance_timeline_trace.csv" in iq_paths

    timeline_csv = materializer._encode_csv(  # noqa: SLF001
        [
            "Direction",
            "Frame",
            "Slot",
            "IQImbalanceImageRejection_dB",
            "IQImbalanceMirrorPowerRatio_dB",
            "IQImbalanceIQCorrelation",
        ],
        [
            ["DL", 1, 7, 27.5, -27.5, 0.08],
            ["UL", 1, 8, 25.0, -25.0, 0.11],
        ],
    )
    summary_csv = materializer._encode_csv(  # noqa: SLF001
        ["Direction", "Availability", "MeasuredRowCount", "AppliedRowCount", "MeanImageRejection_dB", "ModelSet"],
        [
            ["DL", "measured_runtime_iq_imbalance", 1, 1, 27.5, "widely_linear"],
            ["UL", "measured_runtime_iq_imbalance", 1, 1, 25.0, "widely_linear"],
        ],
    )
    existing = {
        "rf/csv/iq_imbalance_timeline_trace.csv": {
            "artifact_id": 1,
            "logical_path": "rf/csv/iq_imbalance_timeline_trace.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        },
        "rf/csv/probe_rf_iq_imbalance.csv": {
            "artifact_id": 2,
            "logical_path": "rf/csv/probe_rf_iq_imbalance.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        },
    }
    payloads = {1: timeline_csv, 2: summary_csv}
    special = materializer._specialized_chart_materialization(  # noqa: SLF001
        "IQ imbalance summary",
        existing,
        lambda artifact_id: payloads[artifact_id],
        7,
    )
    assert special is not None
    assert special["csv_status"] == "specialized_runtime_iq_imbalance_dataset"
    assert special["image_status"] == "generated_specialized_runtime_summary_svg"
    assert "iq_imbalance_timeline_trace.csv" in special["source_table_path"]
    assert "mean_image_rejection_db" in special["csv_bytes"].decode("utf-8")
    assert b"IQ imbalance summary" in special["img_bytes"]

    prach_csv = materializer._encode_csv(  # noqa: SLF001
        ["SNR_dB", "SuccessFlag", "FalseAlarmFlag", "DetectionMetric", "Status"],
        [
            [0, 0, 0, 0, "FAIL"],
            [0, 1, 0, 1, "PASS"],
            [10, 1, 0, 1, "PASS"],
            [10, 0, 1, 0, "FAIL"],
        ],
    )
    existing = {
        "air_interface/csv/prach_trials.csv": {
            "artifact_id": 11,
            "logical_path": "air_interface/csv/prach_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {11: prach_csv}
    detection_special = materializer._specialized_chart_materialization(  # noqa: SLF001
        "detection rate",
        existing,
        lambda artifact_id: payloads[artifact_id],
        9,
    )
    assert detection_special is not None
    assert detection_special["csv_status"] == "specialized_runtime_detection_dataset"
    assert "bucket_name,snr_db,metric_value,sample_count" in detection_special["csv_bytes"].decode("utf-8")
    # Configured SNR labels are not measured-SINR evidence. Preserve the
    # scalar aggregate rather than inventing an observed quality axis.
    _, detection_rows = materializer._decode_csv_dicts(detection_special["csv_bytes"])
    assert len(detection_rows) == 1
    assert detection_rows[0]["snr_db"] == ""
    assert float(detection_rows[0]["metric_value"]) == 0.5
    assert int(detection_rows[0]["sample_count"]) == 4
    assert all(0 <= float(row["ci95_lower"]) < 0.5 < float(row["ci95_upper"]) <= 1
               for row in detection_rows)
    detection_svg = detection_special["img_bytes"].decode("utf-8")
    assert all(label in detection_svg for label in ["95% lower", "Observed", "95% upper", "denominator=4"])
    assert "wilson95_lower=" in detection_svg

    false_alarm_special = materializer._specialized_chart_materialization(  # noqa: SLF001
        "false alarm rate",
        existing,
        lambda artifact_id: payloads[artifact_id],
        9,
    )
    assert false_alarm_special is not None
    assert false_alarm_special["csv_status"] == "specialized_runtime_detection_dataset"
    assert "false alarm rate" in false_alarm_special["csv_bytes"].decode("utf-8").lower()

    prach_peak_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "PeakValue", "DetectionMetric", "TimingError_samples", "Status"],
        [[5, 0.87, 0.87, 0, "PASS"], [5, 0.89, 0.89, 0, "PASS"]],
    )
    existing = {
        "air_interface/csv/prach_trials.csv": {
            "artifact_id": 111,
            "logical_path": "air_interface/csv/prach_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {111: prach_peak_csv}
    prach_peak = materializer._specialized_chart_materialization(  # noqa: SLF001
        "PRACH peak search timeline",
        existing,
        lambda artifact_id: payloads[artifact_id],
        10,
    )
    assert prach_peak is not None
    assert "visual_gate=sparse_prach_peak_evidence" in prach_peak["img_bytes"].decode("utf-8")
    _, peak_rows = materializer._decode_csv_dicts(prach_peak["csv_bytes"])
    assert len(peak_rows) == 2
    assert [float(row["correlation_peak"]) for row in peak_rows] == [0.87, 0.89]
    assert all(float(row["occasion_slot"]) == 5 for row in peak_rows)
    assert all(row["detection_threshold"] == "" for row in peak_rows)

    csirs_csv = materializer._encode_csv(  # noqa: SLF001
        ["CellID", "Slot", "ResourceID", "ResourceSetID", "RBOffset", "NumRB", "SymbolLocations", "NRE", "MeasurementRSRP_dB", "UEIndex"],
        [
            [1, 7, 0, 0, 10, 2, "2 10", 48, -95.0, 3],
            [1, 7, 0, 0, 10, 2, "2 10", 48, -98.0, 5],
        ],
    )
    existing = {
        "air_interface/csv/csi_rs_trials.csv": {
            "artifact_id": 21,
            "logical_path": "air_interface/csv/csi_rs_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {21: csirs_csv}
    csirs_special = materializer._specialized_chart_materialization(  # noqa: SLF001
        "CSI-RS map",
        existing,
        lambda artifact_id: payloads[artifact_id],
        12,
    )
    assert csirs_special is not None
    assert csirs_special["csv_status"] == "specialized_runtime_grid_dataset"
    csirs_text = csirs_special["csv_bytes"].decode("utf-8")
    assert "symbol_index,rb_index,occupancy_value" in csirs_text
    assert csirs_text.count("\n") >= 4

    csirs_stripe_csv = materializer._encode_csv(  # noqa: SLF001
        ["CellID", "Slot", "ResourceID", "ResourceSetID", "RBOffset", "NumRB", "SymbolLocations", "NRE", "MeasurementRSRP_dB"],
        [[1, 7, 0, 0, 0, 4, "0", 16, -91.5]],
    )
    existing = {
        "air_interface/csv/csi_rs_trials.csv": {
            "artifact_id": 211,
            "logical_path": "air_interface/csv/csi_rs_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {211: csirs_stripe_csv}
    csirs_stripe = materializer._specialized_chart_materialization(  # noqa: SLF001
        "CSI-RS resource occupancy",
        existing,
        lambda artifact_id: payloads[artifact_id],
        12,
    )
    assert csirs_stripe is not None
    csirs_stripe_svg = csirs_stripe["img_bytes"].decode("utf-8")
    assert "view=exact_1d_projection" in csirs_stripe_svg
    assert "visual_gate=" not in csirs_stripe_svg
    assert csirs_stripe["image_status"] == "generated_specialized_runtime_projection_svg"
    assert csirs_stripe["uniform_runtime_evidence_is_valid"] is True

    srs_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "UEIndex", "NMSE_dB", "SuccessFlag", "Status"],
        [
            [8, 2, -27.1, 1, "PASS"],
            [8, 6, -25.8, 1, "PASS"],
            [9, 2, -24.0, 0, "FAIL"],
        ],
    )
    existing = {
        "air_interface/csv/srs_trials.csv": {
            "artifact_id": 31,
            "logical_path": "air_interface/csv/srs_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {31: srs_csv}
    srs_special = materializer._specialized_chart_materialization(  # noqa: SLF001
        "SRS map",
        existing,
        lambda artifact_id: payloads[artifact_id],
        13,
    )
    assert srs_special is not None
    assert srs_special["csv_status"] == "specialized_runtime_srs_dataset"
    assert "ue_index,occupancy_value,nmse_db,success_flag" in srs_special["csv_bytes"].decode("utf-8")

    trial_csv = materializer._encode_csv(  # noqa: SLF001
        ["Direction", "Slot", "MCS", "CRCPass", "Throughput_Mbps", "Goodput_Mbps", "Latency_ms"],
        [
            ["DL", 1, 4, 1, 10.0, 10.0, 0.4],
            ["DL", 1, 4, 0, 12.0, 0.0, 0.6],
            ["DL", 2, 8, 1, 20.0, 20.0, 0.5],
        ],
    )
    existing = {
        "air_interface/csv/dl_pdsch_trials.csv": {
            "artifact_id": 41,
            "logical_path": "air_interface/csv/dl_pdsch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {41: trial_csv}
    throughput_time = materializer._specialized_chart_materialization(  # noqa: SLF001
        "throughput over time",
        existing,
        lambda artifact_id: payloads[artifact_id],
        14,
    )
    assert throughput_time is not None
    assert throughput_time["csv_status"] == "specialized_runtime_throughput_timeline_dataset"
    throughput_time_text = throughput_time["csv_bytes"].decode("utf-8")
    assert "series_name,chart_mode,x_label,y_label,x_value,y_value" in throughput_time_text
    assert ",scatter," in throughput_time_text, "Two-slot throughput evidence must not be rendered as a fake line trend."

    bler_mcs = materializer._specialized_chart_materialization(  # noqa: SLF001
        "BLER vs MCS",
        existing,
        lambda artifact_id: payloads[artifact_id],
        14,
    )
    assert bler_mcs is not None
    assert "mcs,bler,sample_count" in bler_mcs["csv_bytes"].decode("utf-8")

    mixed_reliability_csv = materializer._encode_csv(  # noqa: SLF001
        ["CRCPass", "BitsCompared", "BitErrors", "PostEqSINR_dB"],
        [[1, 1000, 0, 18.0], [1, 1000, 10, 19.0]],
    )
    pucch_reliability_csv = materializer._encode_csv(  # noqa: SLF001
        ["CRCPass", "DetectionAttempted", "BitsCompared"],
        [[0, 1, 0]],
    )
    existing = {
        "air_interface/csv/dl_pdsch_trials.csv": {
            "artifact_id": 411,
            "logical_path": "air_interface/csv/dl_pdsch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        },
        "air_interface/csv/pucch_trials.csv": {
            "artifact_id": 412,
            "logical_path": "air_interface/csv/pucch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        },
    }
    payloads = {411: mixed_reliability_csv, 412: pucch_reliability_csv}
    bler_summary = materializer._specialized_chart_materialization(  # noqa: SLF001
        "BLER",
        existing,
        lambda artifact_id: payloads[artifact_id],
        16,
    )
    assert bler_summary is not None
    bler_summary_text = bler_summary["csv_bytes"].decode("utf-8")
    _, bler_rows = materializer._decode_csv_dicts(bler_summary["csv_bytes"])
    assert len(bler_rows) == 1
    assert bler_rows[0]["metric_name"] == "BLER"
    assert float(bler_rows[0]["metric_value"]) == 0.0
    assert float(bler_rows[0]["error_count"]) == 0.0
    assert int(bler_rows[0]["sample_count"]) == 2
    assert float(bler_rows[0]["ci95_lower"]) == 0.0
    z_squared = 1.959963984540054 ** 2
    assert abs(float(bler_rows[0]["ci95_upper"]) - z_squared / (2 + z_squared)) < 1e-12
    assert bler_rows[0]["source_table_logical_path"] == "air_interface/csv/dl_pdsch_trials.csv"
    assert "pucch_trials" not in bler_summary_text, "Data-channel BLER must not mix PUCCH control decode failures into the denominator."
    # The three bars are an interval and its estimate, not three simulated trials.
    bler_svg = bler_summary["img_bytes"].decode("utf-8")
    assert all(label in bler_svg for label in ("95% lower", "Observed", "95% upper", "denominator=2"))

    flat_waveform_csv = materializer._encode_csv(  # noqa: SLF001
        ["SampleIndex", "Time_s", "TxReal", "TxImag", "TxMagnitude", "RxReal", "RxImag", "RxMagnitude"],
        [[1, 0.0, 0.0, 0.0, 0.0, 0.1, 0.0, 0.1], [2, 1e-6, 0.0, 0.0, 0.0, 0.2, 0.0, 0.2]],
    )
    existing = {
        "analytics/csv/waveform_analytics.csv": {
            "artifact_id": 413,
            "logical_path": "analytics/csv/waveform_analytics.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {413: flat_waveform_csv}
    flat_tx = materializer._specialized_chart_materialization(  # noqa: SLF001
        "Tx waveform",
        existing,
        lambda artifact_id: payloads[artifact_id],
        16,
    )
    assert flat_tx is not None
    assert "visual_gate=flat_waveform_preview" in flat_tx["img_bytes"].decode("utf-8")

    ssb_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "SSBIndex"],
        [[1, 0], [1, 1]],
    )
    existing = {
        "reports/csv/live_ssb_stage_table.csv": {
            "artifact_id": 414,
            "logical_path": "reports/csv/live_ssb_stage_table.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {414: ssb_csv}
    ssb_sparse = materializer._specialized_chart_materialization(  # noqa: SLF001
        "SSB index timeline",
        existing,
        lambda artifact_id: payloads[artifact_id],
        16,
    )
    assert ssb_sparse is not None
    assert "visual_gate=sparse_ssb_index_events" in ssb_sparse["img_bytes"].decode("utf-8")
    _, ssb_event_rows = materializer._decode_csv_dicts(ssb_sparse["csv_bytes"])
    assert [float(row["slot"]) for row in ssb_event_rows] == [1, 1]
    assert [float(row["ssb_index"]) for row in ssb_event_rows] == [0, 1]

    pbch_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "CellID", "DecodeSuccess", "SelectedBeamIndex"],
        [[1, 1, 1, 0], [1, 2, 1, 1]],
    )
    existing = {
        "air_interface/csv/pbch_trials.csv": {
            "artifact_id": 415,
            "logical_path": "air_interface/csv/pbch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {415: pbch_csv}
    pbch_sparse = materializer._specialized_chart_materialization(  # noqa: SLF001
        "PBCH/SSB map",
        existing,
        lambda artifact_id: payloads[artifact_id],
        16,
    )
    assert pbch_sparse is not None
    assert pbch_sparse["image_status"] == "generated_specialized_runtime_projection_svg"
    assert "view=exact_1d_projection" in pbch_sparse["img_bytes"].decode("utf-8")
    _, pbch_projection_rows = materializer._decode_csv_dicts(pbch_sparse["csv_bytes"])
    assert [float(row["slot"]) for row in pbch_projection_rows] == [1, 1]
    assert [row["cell_id"] for row in pbch_projection_rows] == ["1", "2"]
    assert [float(row["occupancy_value"]) for row in pbch_projection_rows] == [1, 1]

    pucch_dtx_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "UEID", "CRCPass", "DetectionAttempted", "BitsCompared", "DTXFlag", "MissedDetection", "FalseAlarmFlag"],
        [
            [1, 7, 1, 1, 0, 0, 0, 0],
            [2, 7, 0, 1, 0, 1, 0, 0],
            [3, 7, 0, 1, 0, 0, 1, 0],
        ],
    )
    existing = {
        "air_interface/csv/pucch_trials.csv": {
            "artifact_id": 421,
            "logical_path": "air_interface/csv/pucch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {421: pucch_dtx_csv}
    pucch_dtx = materializer._specialized_chart_materialization(  # noqa: SLF001
        "PUCCH DTX statistics",
        existing,
        lambda artifact_id: payloads[artifact_id],
        17,
    )
    assert pucch_dtx is not None
    pucch_dtx_text = pucch_dtx["csv_bytes"].decode("utf-8")
    assert "Decoded/observed" in pucch_dtx_text
    assert "DTX" in pucch_dtx_text
    assert "Missed detection" in pucch_dtx_text
    assert "1.0,7,Decoded/observed" in pucch_dtx_text, "Zero compared bits alone must not convert a decoded PUCCH row into DTX."

    beam_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "SelectedBeamIndex", "BestBeamIndex"],
        [[1, 3, 5], [2, 4, 4]],
    )
    existing = {
        "beamforming/csv/beam_precoder_table.csv": {
            "artifact_id": 431,
            "logical_path": "beamforming/csv/beam_precoder_table.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {431: beam_csv}
    beam_gap = materializer._specialized_chart_materialization(  # noqa: SLF001
        "beam gain gap histogram",
        existing,
        lambda artifact_id: payloads[artifact_id],
        18,
    )
    assert beam_gap is not None
    assert beam_gap["csv_status"] == "unavailable_exact_reason"
    assert "Beam-index distance is not a dB gain gap" in beam_gap["csv_bytes"].decode("utf-8")

    layer_quality_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "WidebandCQI", "MCSIndex", "Layers", "PostEqSINRPerLayer_dB"],
        [[1, 12, 18, 2, "[14.5 11.25]"], [2, 10, 15, 2, "[12.0, 10.0]"]],
    )
    existing = {
        "reports/csv/live_link_adaptation_input_table.csv": {
            "artifact_id": 441,
            "logical_path": "reports/csv/live_link_adaptation_input_table.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {441: layer_quality_csv}
    layer_quality = materializer._specialized_chart_materialization(  # noqa: SLF001
        "per-layer quality plot",
        existing,
        lambda artifact_id: payloads[artifact_id],
        19,
    )
    assert layer_quality is not None
    layer_text = layer_quality["csv_bytes"].decode("utf-8")
    assert "1,13.25" in layer_text and "2,10.625" in layer_text

    existing = {
        "air_interface/csv/dl_pdsch_trials.csv": {
            "artifact_id": 41,
            "logical_path": "air_interface/csv/dl_pdsch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {41: trial_csv}
    latency_cdf = materializer._specialized_chart_materialization(  # noqa: SLF001
        "latency CDF",
        existing,
        lambda artifact_id: payloads[artifact_id],
        14,
    )
    assert latency_cdf is not None
    assert "latency_ms,cdf_probability" in latency_cdf["csv_bytes"].decode("utf-8")

    energy_csv = materializer._encode_csv(  # noqa: SLF001
        ["Energy_J", "SuccessfulBits", "ActiveBWFraction", "ActiveRank", "Power_W"],
        [
            [0.1, 1000, 0.25, 1, 10.0],
            [0.2, 2000, 0.50, 2, 20.0],
            [0.0, 0, 0.75, 2, 30.0],
        ],
    )
    existing = {
        "rf/csv/energy_timeline_trace.csv": {
            "artifact_id": 51,
            "logical_path": "rf/csv/energy_timeline_trace.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {51: energy_csv}
    energy_hist = materializer._specialized_chart_materialization(  # noqa: SLF001
        "energy per bit histogram",
        existing,
        lambda artifact_id: payloads[artifact_id],
        15,
    )
    assert energy_hist is not None
    assert "x_value,y_value,sample_count" in energy_hist["csv_bytes"].decode("utf-8")

    bw_power = materializer._specialized_chart_materialization(  # noqa: SLF001
        "active bandwidth vs power",
        existing,
        lambda artifact_id: payloads[artifact_id],
        15,
    )
    assert bw_power is not None
    assert "x_value,y_value,power_w" in bw_power["csv_bytes"].decode("utf-8")

    original_loader = dash.load_cached_csv_preview
    original_artifact_url = dash.artifact_url
    try:
        preview_map = {
            101: (
                ["slot", "rb_index", "occupancy_value"],
                [["7", "10", "0.5"], ["7", "11", "0.5"], ["8", "10", "1.0"]],
            ),
            102: (
                ["series_name", "x_value", "y_value"],
                [["Sites", "0", "0"], ["Sites", "1", "0"], ["UEs", "0.5", "2.0"]],
            ),
            103: (
                ["bucket_name", "metric_value"],
                [["0 dB", "0.5"], ["10 dB", "1.0"]],
            ),
        }
        dash.load_cached_csv_preview = lambda artifact_id, limit: preview_map[int(artifact_id)]
        dash.artifact_url = lambda artifact_id, download=False: f"/artifact/{artifact_id}{'?download=1' if download else ''}"

        heatmap_chart = dash.build_numeric_chart_from_artifact({"artifact_id": 101, "logical_path": "analytics/csv/contract__resource-grid__heatmap.csv"})
        assert heatmap_chart is not None
        assert heatmap_chart["series"][0]["mode"] == "heatmap"

        scatter_chart = dash.build_numeric_chart_from_artifact({"artifact_id": 102, "logical_path": "reports/csv/contract__topology.csv"})
        assert scatter_chart is not None
        assert len(scatter_chart["series"]) == 2
        assert scatter_chart["series"][0]["points"][0]["x"] == 0.0

        bar_chart = dash.build_numeric_chart_from_artifact({"artifact_id": 103, "logical_path": "analytics/csv/contract__detection.csv"})
        assert bar_chart is not None
        assert bar_chart["series"][0]["trace_type"] == "bar"
        assert bar_chart["series"][0]["points"][0]["x"] == "0 dB"
    finally:
        dash.load_cached_csv_preview = original_loader
        dash.artifact_url = original_artifact_url


def test_exact_phy_signal_diagnostic_materializes_only_observed_array_boundaries() -> None:
    header = [
        "SnapshotID", "Panel", "Series", "PointIndex", "XValue", "YValue",
        "Direction", "UEIndex", "CellID", "SFN", "Slot", "SampleIndex",
        "SubcarrierIndex", "OFDMSymbolIndex", "ResourceBlockIndex",
        "SubcarrierInResourceBlock", "RxPortIndex0Based", "TxPortIndex0Based",
        "IValue", "QValue", "Magnitude_dB", "Phase_deg", "WrappedPhase_rad",
        "UnwrappedPhaseFrequency_rad", "UnwrappedPhaseTime_rad",
        "PhaseDeltaFrequency_rad", "PhaseDeltaTime_rad", "SampleRate_Hz",
        "ChannelEstimateSource", "ChannelEstimateMethod", "GridSHA256",
        "truth_status", "SourceArtifact", "Status",
    ]
    rows = [
        ["snap_dl", "time_domain", "tx", 1, 0.0, 1.0, "DL", 1, 42, 0, 3, 1, "", "", "", "", "", "", 1.0, 0.0, "", "", "", "", "", "", "", 7.68e6, "nrChannelEstimate", "practical", "", "real_lls_evidence", "runtime_phy_arrays_same_trial", "available"],
        ["snap_dl", "time_domain", "tx", 2, 1 / 7.68e6, 1.0, "DL", 1, 42, 0, 3, 2, "", "", "", "", "", "", 0.0, 1.0, "", "", "", "", "", "", "", 7.68e6, "nrChannelEstimate", "practical", "", "real_lls_evidence", "runtime_phy_arrays_same_trial", "available"],
        ["snap_dl", "time_domain", "rx", 1, 0.0, 0.5, "DL", 1, 42, 0, 3, 1, "", "", "", "", "", "", 0.5, 0.0, "", "", "", "", "", "", "", 7.68e6, "nrChannelEstimate", "practical", "", "real_lls_evidence", "runtime_phy_arrays_same_trial", "available"],
        ["snap_dl", "time_domain", "rx", 2, 1 / 7.68e6, 0.5, "DL", 1, 42, 0, 3, 2, "", "", "", "", "", "", 0.0, 0.5, "", "", "", "", "", "", "", 7.68e6, "nrChannelEstimate", "practical", "", "real_lls_evidence", "runtime_phy_arrays_same_trial", "available"],
        ["snap_dl", "channel_estimate", "hest", 1, 0, -3.0, "DL", 1, 42, 0, 3, "", 0, 0, 0, 0, 0, 0, 0.7, 0.1, -3.0, 8.13, 0.142, 0.142, 0.142, "", "", 7.68e6, "nrChannelEstimate", "practical", "abc", "real_lls_evidence", "runtime_phy_arrays_same_trial", "available"],
        ["snap_dl", "channel_estimate", "hest", 2, 1, -4.0, "DL", 1, 42, 0, 3, "", 1, 0, 0, 1, 0, 0, 0.6, -0.2, -4.0, -18.43, -0.322, -0.322, -0.322, -0.464, "", 7.68e6, "nrChannelEstimate", "practical", "abc", "real_lls_evidence", "runtime_phy_arrays_same_trial", "available"],
        ["snap_dl", "channel_estimate_grid", "receiver_hest_exact_tensor", 1, 0, 0, "DL", 1, 42, 0, 3, "", 0, 0, 0, 0, 0, 0, 0.7, 0.1, -3.0, 8.13, 0.142, 0.142, 0.142, "", "", 7.68e6, "nrChannelEstimate", "practical", "abc", "real_lls_evidence", "runtime_phy_arrays_same_trial", "available"],
        ["snap_dl", "channel_estimate_grid", "receiver_hest_exact_tensor", 2, 1, 0, "DL", 1, 42, 0, 3, "", 1, 0, 0, 1, 0, 0, 0.6, -0.2, -4.0, -18.43, -0.322, -0.322, -0.322, -0.464, "", 7.68e6, "nrChannelEstimate", "practical", "abc", "real_lls_evidence", "runtime_phy_arrays_same_trial", "available"],
        ["snap_dl", "channel_estimate_grid", "receiver_hest_exact_tensor", 3, 0, 1, "DL", 1, 42, 0, 3, "", 0, 1, 0, 0, 0, 0, 0.5, 0.3, -4.65, 30.96, 0.540, 0.540, 0.540, "", 0.398, 7.68e6, "nrChannelEstimate", "practical", "abc", "real_lls_evidence", "runtime_phy_arrays_same_trial", "available"],
        ["snap_dl", "channel_estimate_grid", "receiver_hest_exact_tensor", 4, 1, 1, "DL", 1, 42, 0, 3, "", 1, 1, 0, 1, 0, 0, 0.4, -0.4, -4.95, -45.0, -0.785, -0.785, -0.785, "", -1.325, 7.68e6, "nrChannelEstimate", "practical", "abc", "real_lls_evidence", "runtime_phy_arrays_same_trial", "available"],
    ]
    def diagnostic_row(**values):
        return [values.get(name, "") for name in header]

    rows.extend([
        diagnostic_row(SnapshotID="snap_dl", Panel="time_domain", Series="post_channel", PointIndex=1, XValue=0.0, YValue=0.8, Direction="DL", UEIndex=1, CellID=42, SFN=0, Slot=3, SampleIndex=1, IValue=0.8, QValue=0.0, SampleRate_Hz=7.68e6, truth_status="real_lls_evidence", SourceArtifact="runtime_phy_arrays_same_trial", Status="available"),
        diagnostic_row(SnapshotID="snap_dl", Panel="time_domain", Series="post_channel", PointIndex=2, XValue=1 / 7.68e6, YValue=0.8, Direction="DL", UEIndex=1, CellID=42, SFN=0, Slot=3, SampleIndex=2, IValue=0.0, QValue=0.8, SampleRate_Hz=7.68e6, truth_status="real_lls_evidence", SourceArtifact="runtime_phy_arrays_same_trial", Status="available"),
        diagnostic_row(SnapshotID="snap_dl", Panel="true_channel_impulse_response", Series="executed_path_gain_rx1_tx1", PointIndex=1, XValue=0.0, IValue=1.0, QValue=0.0, Magnitude_dB=0.0, Phase_deg=0.0, Direction="DL", UEIndex=1, CellID=42, SFN=0, Slot=3, GridSHA256="pathhash", truth_status="real_lls_evidence", SourceArtifact="runtime_phy_arrays_same_trial", Status="available"),
        diagnostic_row(SnapshotID="snap_dl", Panel="true_channel_impulse_response", Series="executed_path_gain_rx1_tx1", PointIndex=2, XValue=100e-9, IValue=0.2, QValue=0.1, Magnitude_dB=-13.0103, Phase_deg=26.565, Direction="DL", UEIndex=1, CellID=42, SFN=0, Slot=3, GridSHA256="pathhash", truth_status="real_lls_evidence", SourceArtifact="runtime_phy_arrays_same_trial", Status="available"),
        diagnostic_row(SnapshotID="snap_dl", Panel="estimated_channel_impulse_response", Series="receiver_hhat_tau_rx1_tx1", PointIndex=1, XValue=0.0, IValue=0.9, QValue=0.0, Magnitude_dB=-0.91515, Phase_deg=0.0, Direction="DL", UEIndex=1, CellID=42, SFN=0, Slot=3, GridSHA256="hhathash", truth_status="real_lls_evidence", SourceArtifact="runtime_phy_arrays_same_trial", Status="available"),
        diagnostic_row(SnapshotID="snap_dl", Panel="estimated_channel_impulse_response", Series="receiver_hhat_tau_rx1_tx1", PointIndex=2, XValue=100e-9, IValue=0.18, QValue=0.08, Magnitude_dB=-14.116, Phase_deg=23.962, Direction="DL", UEIndex=1, CellID=42, SFN=0, Slot=3, GridSHA256="hhathash", truth_status="real_lls_evidence", SourceArtifact="runtime_phy_arrays_same_trial", Status="available"),
        diagnostic_row(SnapshotID="snap_dl", Panel="true_channel_frequency_response", Series="executed_h_f_rx1_tx1", PointIndex=1, XValue=-15000.0, IValue=1.2, QValue=0.1, Magnitude_dB=1.611, Phase_deg=4.764, Direction="DL", UEIndex=1, CellID=42, SFN=0, Slot=3, GridSHA256="pathhash", truth_status="real_lls_evidence", SourceArtifact="runtime_phy_arrays_same_trial", Status="available"),
        diagnostic_row(SnapshotID="snap_dl", Panel="true_channel_frequency_response", Series="executed_h_f_rx1_tx1", PointIndex=2, XValue=15000.0, IValue=1.18, QValue=-0.1, Magnitude_dB=1.468, Phase_deg=-4.844, Direction="DL", UEIndex=1, CellID=42, SFN=0, Slot=3, GridSHA256="pathhash", truth_status="real_lls_evidence", SourceArtifact="runtime_phy_arrays_same_trial", Status="available"),
    ])
    payload = materializer._encode_csv(header, rows)  # noqa: SLF001
    existing = {
        "reports/csv/phy_signal_diagnostic_source.csv": {"artifact_id": 8801}
    }
    fetch = lambda artifact_id: payload if int(artifact_id) == 8801 else b""

    pre_channel = materializer._specialized_chart_materialization(  # noqa: SLF001
        "pre-channel waveform", existing, fetch, 77
    )
    assert pre_channel is not None
    assert pre_channel["source_mapping_status"] == "exact"
    assert pre_channel["source_row_count"] == 2
    assert b"runtime_same_trial_phy_arrays" in pre_channel["img_bytes"]

    post_impairment = materializer._specialized_chart_materialization(  # noqa: SLF001
        "post-impairment waveform", existing, fetch, 77
    )
    assert post_impairment is not None
    assert post_impairment["source_row_count"] == 2

    post_channel = materializer._runtime_phy_signal_diagnostic_chart(  # noqa: SLF001
        "post-channel waveform", existing, fetch, 77
    )
    assert post_channel is not None
    assert post_channel["source_mapping_status"] == "exact"
    assert post_channel["source_row_count"] == 2
    post_header, post_rows = materializer._decode_csv_dicts(post_channel["csv_bytes"])  # noqa: SLF001
    assert "endpoint" in post_header
    assert {row["endpoint"] for row in post_rows} == {"post_channel"}

    link_waveforms = materializer._runtime_phy_signal_diagnostic_chart(  # noqa: SLF001
        "UE-wise / link-wise waveform comparison", existing, fetch, 77
    )
    assert link_waveforms is not None
    assert link_waveforms["source_row_count"] == 6

    true_htau = materializer._runtime_phy_signal_diagnostic_chart(  # noqa: SLF001
        "true H(tau) if available", existing, fetch, 77
    )
    assert true_htau is not None
    assert true_htau["source_mapping_status"] == "exact"
    assert true_htau["source_row_count"] == 2
    assert b"executed_runtime_path_gain_tensor" in true_htau["img_bytes"]
    routed_true_htau = materializer._specialized_chart_materialization(  # noqa: SLF001
        "true H(tau) if available", existing, fetch, 77
    )
    assert routed_true_htau is not None
    assert routed_true_htau["source_mapping_status"] == "exact"
    assert b"executed_runtime_path_gain_tensor" in routed_true_htau["img_bytes"]

    estimated_htau = materializer._runtime_phy_signal_diagnostic_chart(  # noqa: SLF001
        "estimated Hhat(tau)", existing, fetch, 77
    )
    assert estimated_htau is not None
    assert estimated_htau["source_row_count"] == 2
    assert b"receiver_channel_estimate_ifft" in estimated_htau["img_bytes"]
    routed_estimated_htau = materializer._specialized_chart_materialization(  # noqa: SLF001
        "estimated Hhat(tau)", existing, fetch, 77
    )
    assert routed_estimated_htau is not None
    assert routed_estimated_htau["source_mapping_status"] == "exact"
    assert b"receiver_channel_estimate_ifft" in routed_estimated_htau["img_bytes"]

    true_hf = materializer._runtime_phy_signal_diagnostic_chart(  # noqa: SLF001
        "true H(f) if available", existing, fetch, 77
    )
    assert true_hf is not None
    assert true_hf["source_mapping_status"] == "exact"
    assert true_hf["source_row_count"] == 2
    routed_true_hf = materializer._specialized_chart_materialization(  # noqa: SLF001
        "true H(f) if available", existing, fetch, 77
    )
    assert routed_true_hf is not None
    assert routed_true_hf["source_mapping_status"] == "exact"
    assert routed_true_hf["source_row_count"] == 2

    hhat = materializer._specialized_chart_materialization(  # noqa: SLF001
        "estimated Hhat(f)", existing, fetch, 77
    )
    assert hhat is not None
    assert hhat["source_row_count"] == 2
    assert b"receiver_Hest" in hhat["img_bytes"]

    phase = materializer._specialized_chart_materialization(  # noqa: SLF001
        "channel phase heatmap", existing, fetch, 77
    )
    assert phase is not None
    assert phase["source_row_count"] == 4
    decoded_header, decoded_rows = materializer._decode_csv_dicts(phase["csv_bytes"])  # noqa: SLF001
    assert "phase_deg" in decoded_header
    assert {row["grid_sha256"] for row in decoded_rows} == {"abc"}


def test_runtime_antenna_pattern_uses_actual_sampled_array_object() -> None:
    header = [
        "NodeType", "NodeIndex", "BaseStationID", "UEIndex",
        "Frequency_Hz", "Azimuth_deg", "Elevation_deg", "Directivity_dBi",
        "ArrayClass", "ElementClass", "ElementModel",
        "BoresightAzimuth_deg", "BoresightElevation_deg",
        "BoresightSlant_deg", "CoordinateFrame", "PatternKind",
        "PatternSource", "SelectedBeamApplied", "SelectedBeamEvidenceSource",
        "PatternSHA256", "truth_status",
    ]
    rows = []
    for elevation in (-5, 5):
        for azimuth in (-10, 10):
            rows.append([
                "BS", 1, 1, "", 3.5e9, azimuth, elevation,
                8.0 - abs(azimuth) / 10.0 - abs(elevation) / 5.0,
                "phased.NRRectangularPanelArray", "phased.NRAntennaElement",
                "3gpp_nr_element", 0, 0, 0,
                "local_array_coordinate_frame_before_runtime_orientation",
                "physical_array_element_directivity_without_selected_precoder_taper",
                "actual_CoupledTruthRuntime_phased_NRRectangularPanelArray",
                0, "separate_runtime_beam_precoder_tables", "abc123",
                "real_runtime_object_evidence",
            ])
    payload = materializer._encode_csv(header, rows)  # noqa: SLF001
    existing = {"reports/csv/antenna_pattern_samples.csv": {"artifact_id": 9901}}
    fetch = lambda artifact_id: payload if int(artifact_id) == 9901 else b""

    chart = materializer._specialized_chart_materialization(  # noqa: SLF001
        "antenna radiation pattern", existing, fetch, 88
    )
    assert chart is not None
    assert chart["source_mapping_status"] == "exact"
    assert chart["source_row_count"] == 4
    assert chart["csv_status"] == "specialized_actual_runtime_antenna_pattern_dataset"
    csv_header, csv_rows = materializer._decode_csv_dicts(chart["csv_bytes"])  # noqa: SLF001
    assert "directivity_dbi" in csv_header
    assert {row["pattern_sha256"] for row in csv_rows} == {"abc123"}
    assert {row["truth_status"] for row in csv_rows} == {"real_runtime_object_evidence"}
    svg = chart["img_bytes"].decode("utf-8")
    assert "actual phased.NRRectangularPanelArray" in svg
    assert "selected_beam_taper=not_applied" in svg


def test_cqi_mcs_single_runtime_state_is_labelled_operating_point() -> None:
    payload = materializer._encode_csv(  # noqa: SLF001
        ["slot", "direction", "mcs_index", "wideband_cqi"],
        [[6, "DL", 1, "NaN"], [11, "DL", 15, 9], [12, "DL", 15, 9]],
    )
    existing = {
        "reports/csv/live_scheduler_cycle.csv": {
            "artifact_id": 9910,
            "logical_path": "reports/csv/live_scheduler_cycle.csv",
        }
    }
    result = materializer._specialized_chart_materialization(  # noqa: SLF001
        "CQI vs selected MCS", existing, lambda _artifact_id: payload, 88
    )

    assert result is not None
    header, rows = materializer._decode_csv_dicts(result["csv_bytes"])  # noqa: SLF001
    assert rows and "x_value" in header and "y_value" in header
    assert {float(row["x_value"]) for row in rows} == {9.0}
    assert {float(row["y_value"]) for row in rows} == {15.0}
    assert {row["evidence_shape_policy"] for row in rows} == {"operating_point"}
    assert {int(row["source_sample_count"]) for row in rows} == {2}
    assert b"no relation or sweep is inferred" in result["csv_bytes"]


def test_receiver_stage_latency_charts_use_only_measured_stage_fields() -> None:
    payloads = {
        9911: materializer._encode_csv(  # noqa: SLF001
            ["Slot", "UEIndex", "ChannelEstimationLatency_ms", "EqualizationLatency_ms", "ReceiverStageLatencySource"],
            [[1, 1, 0.31, 0.12, "matlab_tic_toc_canonical_pdsch_receiver_stages"]],
        ),
        9912: materializer._encode_csv(  # noqa: SLF001
            ["Slot", "UEIndex", "ChannelEstimationLatency_ms", "EqualizationLatency_ms", "ReceiverStageLatencySource"],
            [[2, 1, 0.42, 0.18, "matlab_tic_toc_canonical_pusch_receiver_stages"]],
        ),
        9913: materializer._encode_csv(  # noqa: SLF001
            ["Slot", "UEIndex", "ChannelEstimationLatency_ms", "ReceiverPipelineLatency_ms", "ReceiverStageLatencySource"],
            [[3, 1, 0.27, 0.51, "matlab_tic_toc_csirs_runtime_observation_and_estimation"]],
        ),
        9914: materializer._encode_csv(  # noqa: SLF001
            ["Slot", "UEIndex", "PUCCHFormat", "ReceiverPipelineLatency_ms", "ChannelEstimationLatency_ms", "EqualizationLatency_ms", "ReceiverStageLatencySource"],
            [[4, 1, 0, 0.21, "", "", "matlab_tic_toc_canonical_pucch_receiver_stages"],
             [5, 1, 2, 0.63, 0.19, 0.11, "matlab_tic_toc_canonical_pucch_receiver_stages"]],
        ),
    }
    existing = {
        "air_interface/csv/dl_pdsch_trials.csv": {"artifact_id": 9911},
        "air_interface/csv/ul_pusch_trials.csv": {"artifact_id": 9912},
        "air_interface/csv/csi_rs_trials.csv": {"artifact_id": 9913},
        "air_interface/csv/pucch_trials.csv": {"artifact_id": 9914},
    }
    fetch = lambda artifact_id: payloads[int(artifact_id)]

    csirs = materializer._specialized_chart_materialization(  # noqa: SLF001
        "CSI-RS latency trend", existing, fetch, 91
    )
    assert csirs is not None
    assert csirs["source_row_count"] == 1

    channel_estimation = materializer._specialized_chart_materialization(  # noqa: SLF001
        "channel estimation latency", existing, fetch, 91
    )
    assert channel_estimation is not None
    assert channel_estimation["source_row_count"] == 4

    equalizer = materializer._specialized_chart_materialization(  # noqa: SLF001
        "equalizer latency", existing, fetch, 91
    )
    assert equalizer is not None
    assert equalizer["source_row_count"] == 3

    per_format = materializer._specialized_chart_materialization(  # noqa: SLF001
        "per-format latency histograms", existing, fetch, 91
    )
    assert per_format is not None
    assert per_format["source_mapping_status"] == "exact"
    assert per_format["source_row_count"] == 2
    header, rows = materializer._decode_csv_dicts(per_format["csv_bytes"])  # noqa: SLF001
    assert "latency_ms" in header
    assert {row["pucch_format"] for row in rows} == {"0", "2"}


def test_pdcch_component_charts_use_exact_study_evidence() -> None:
    candidate_csv = materializer._encode_csv(  # noqa: SLF001
        ["TrialIndex", "start_cce", "AL", "candidate_detected"],
        [[1, 0, 2, 1], [2, 2, 4, 0]],
    )
    dmrs_csv = materializer._encode_csv(  # noqa: SLF001
        ["SlotIndex", "Symbol", "Subcarrier", "Port", "DMRSIndex"],
        [[0, 1, 12, 0, 1], [0, 1, 16, 0, 2], [1, 2, 12, 0, 3]],
    )
    summary_csv = materializer._encode_csv(  # noqa: SLF001
        ["SNRdB", "mean_DetectionProbability", "mean_MissProbability", "mean_FalseAlarmProbability"],
        [[-5, 0.75, 0.25, 0.02], [0, 0.98, 0.02, 0.001]],
    )
    existing = {
        "reports/csv/pdcch6gr_per_candidate_results.csv": {
            "artifact_id": 501,
            "logical_path": "reports/csv/pdcch6gr_per_candidate_results.csv",
        },
        "reports/csv/pdcch6gr_dmrs_locations.csv": {
            "artifact_id": 502,
            "logical_path": "reports/csv/pdcch6gr_dmrs_locations.csv",
        },
        "reports/csv/pdcch6gr_summary_by_snr.csv": {
            "artifact_id": 503,
            "logical_path": "reports/csv/pdcch6gr_summary_by_snr.csv",
        },
    }
    payloads = {501: candidate_csv, 502: dmrs_csv, 503: summary_csv}
    fetch = lambda artifact_id: payloads[artifact_id]

    cce = materializer._specialized_chart_materialization(  # noqa: SLF001
        "CCE usage heatmap", existing, fetch, 99
    )
    assert cce is not None
    assert cce["source_row_count"] == 2
    _header, cce_rows = materializer._decode_csv_dicts(cce["csv_bytes"])  # noqa: SLF001
    assert len(cce_rows) == 6
    assert {row["cce_index"] for row in cce_rows} == {"0", "1", "2", "3", "4", "5"}

    dmrs = materializer._specialized_chart_materialization(  # noqa: SLF001
        "PDCCH DMRS occupancy", existing, fetch, 99
    )
    assert dmrs is not None
    assert dmrs["csv_status"] == "specialized_runtime_pdcch_exact_dmrs_dataset"
    _header, dmrs_rows = materializer._decode_csv_dicts(dmrs["csv_bytes"])  # noqa: SLF001
    assert {(row["slot_index"], row["symbol_index"], row["subcarrier_index"]) for row in dmrs_rows} == {
        ("0", "1", "12"), ("0", "1", "16"), ("1", "2", "12")
    }

    expected = {"P_FA": "0.02", "FAR": "0.02", "P_MD": "0.25", "P_D": "0.75"}
    for name, first_value in expected.items():
        result = materializer._specialized_chart_materialization(  # noqa: SLF001
            name, existing, fetch, 99
        )
        assert result is not None, name
        assert result["csv_status"] == "specialized_runtime_pdcch_probability_dataset"
        _header, rows = materializer._decode_csv_dicts(result["csv_bytes"])  # noqa: SLF001
        assert rows[0]["probability"] == first_value


if __name__ == "__main__":
    main()
