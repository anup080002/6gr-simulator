from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "regenerate_lls_rasters_from_csv.py"
SPEC = importlib.util.spec_from_file_location("regenerate_lls_rasters_from_csv", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def _semantic_row(category: str, *, passed: bool) -> dict[str, object]:
    return {
        "category": category,
        "artifact_path": "reports/csv/example.csv",
        "check_id": category + "_check",
        "details": "pass" if passed else "intentional_failure",
        "required": True,
        "evaluated": True,
        "passed": passed,
    }


def test_pre_raster_gate_defers_only_terminal_status_and_manifest(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    image_audit = _semantic_row("domain_runtime", passed=False)
    image_audit["artifact_path"] = "reports/csv/all_image_artifact_audit.csv"
    audit = {
        "canonical_csv_semantic_audit": [
            _semantic_row("primary_link", passed=True),
            _semantic_row("runtime_execution_lineage", passed=True),
            _semantic_row("status_reduction", passed=False),
            _semantic_row("manifest_integrity", passed=False),
            image_audit,
        ]
    }
    monkeypatch.setattr(MODULE, "audit_run", lambda _run_root: audit)
    assert MODULE.require_primary_csv_semantics(tmp_path) is audit


def test_pre_raster_gate_still_rejects_runtime_ledger_failure(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    audit = {
        "canonical_csv_semantic_audit": [
            _semantic_row("primary_link", passed=True),
            _semantic_row("runtime_execution_lineage", passed=False),
            _semantic_row("status_reduction", passed=False),
        ]
    }
    monkeypatch.setattr(MODULE, "audit_run", lambda _run_root: audit)
    with pytest.raises(SystemExit, match="runtime_execution_lineage_check"):
        MODULE.require_primary_csv_semantics(tmp_path)


def test_pre_raster_gate_skips_only_configuration_filtered_csv(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    distance = _semantic_row("primary_link", passed=False)
    distance["artifact_path"] = "air_interface/csv/distance_vs_sinr.csv"
    required_runtime = _semantic_row("runtime_execution_lineage", passed=True)
    audit = {"canonical_csv_semantic_audit": [distance, required_runtime]}
    monkeypatch.setattr(MODULE, "audit_run", lambda _run_root: audit)

    def fixed_link_filter(path: str, _name: str) -> bool:
        return path == "air_interface/csv/distance_vs_sinr.csv"

    assert (
        MODULE.require_primary_csv_semantics(
            tmp_path, policy_filter=fixed_link_filter
        )
        is audit
    )


def test_pre_raster_policy_filter_does_not_hide_other_required_failure(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    distance = _semantic_row("primary_link", passed=False)
    distance["artifact_path"] = "air_interface/csv/distance_vs_sinr.csv"
    ledger = _semantic_row("runtime_execution_lineage", passed=False)
    audit = {"canonical_csv_semantic_audit": [distance, ledger]}
    monkeypatch.setattr(MODULE, "audit_run", lambda _run_root: audit)

    with pytest.raises(SystemExit, match="runtime_execution_lineage_check"):
        MODULE.require_primary_csv_semantics(
            tmp_path,
            policy_filter=lambda path, _name: path.endswith("distance_vs_sinr.csv"),
        )


def test_post_raster_gate_defers_only_caller_owned_terminal_status() -> None:
    audit = {
        "canonical_csv_semantic_audit": [
            _semantic_row("status_reduction", passed=False),
            _semantic_row("manifest_integrity", passed=True),
        ],
        "chart_source_semantic_audit": [
            _semantic_row("chart_lineage", passed=True),
        ],
    }
    assert MODULE.post_materialization_required_failures(audit) == []


def test_post_raster_gate_keeps_manifest_and_chart_failures_strict() -> None:
    manifest_failure = _semantic_row("manifest_integrity", passed=False)
    chart_failure = _semantic_row("chart_lineage", passed=False)
    audit = {
        "canonical_csv_semantic_audit": [
            _semantic_row("status_reduction", passed=False),
            manifest_failure,
        ],
        "chart_source_semantic_audit": [chart_failure],
    }
    assert MODULE.post_materialization_required_failures(audit) == [
        manifest_failure,
        chart_failure,
    ]


def test_component_mapping_routes_contract_plots_to_requested_folders() -> None:
    assert MODULE.component_for_plot("contract__prach-random-access__detection-rate") == "prach"
    assert MODULE.component_for_plot("contract__dl-control-phy-pdcch__cce-usage") == "pdcch"
    assert MODULE.component_for_plot("contract__beamforming-precoding-mimo__rank") == "mimo"
    assert MODULE.component_for_plot("contract__fixed-snr-sweep__bler") == "validation"


def test_run_root_guard_rejects_paths_outside_results_lls(tmp_path: Path) -> None:
    with pytest.raises(SystemExit, match="Refusing raster replacement outside"):
        MODULE.validate_run_root(tmp_path)


def test_run_root_guard_uses_component_waveform_authority(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setattr(MODULE, "REPO_ROOT", tmp_path)
    run = tmp_path / "results" / "lls" / "pdcch_component" / "run_1"
    (run / "meta").mkdir(parents=True)
    (run / "reports" / "csv").mkdir(parents=True)
    (run / "air_interface" / "csv").mkdir(parents=True)
    (run / "meta" / "scenario_config_identity.json").write_text(
        "{}", encoding="utf-8"
    )
    (run / "meta" / "scenario_config_resolved.json").write_text(
        json.dumps(
            {
                "scenario": {"runner_profile": "ctrl6gr_pdcch_study"},
                "simulation": {"link_direction": "dl"},
            }
        ),
        encoding="utf-8",
    )
    (run / "reports" / "csv" / "scenario_summary.csv").write_text(
        "RunCompletion\ncompleted\n", encoding="utf-8"
    )
    (run / "air_interface" / "csv" / "pdcch_trials.csv").write_text(
        "TrialId,CRCOK\n1,1\n", encoding="utf-8"
    )

    assert MODULE.validate_run_root(run) == run.resolve()
    assert not (run / "air_interface" / "csv" / "dl_pdsch_trials.csv").exists()
    assert not (run / "air_interface" / "csv" / "ul_pusch_trials.csv").exists()


def test_run_root_guard_requires_configured_link_direction_authority(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setattr(MODULE, "REPO_ROOT", tmp_path)
    run = tmp_path / "results" / "lls" / "dl_only" / "run_1"
    (run / "meta").mkdir(parents=True)
    (run / "reports" / "csv").mkdir(parents=True)
    (run / "air_interface" / "csv").mkdir(parents=True)
    (run / "meta" / "scenario_config_identity.json").write_text(
        "{}", encoding="utf-8"
    )
    (run / "meta" / "scenario_config_resolved.json").write_text(
        json.dumps(
            {
                "scenario": {"runner_profile": "waveform_bundle"},
                "simulation": {"link_direction": "dl"},
            }
        ),
        encoding="utf-8",
    )
    (run / "reports" / "csv" / "scenario_summary.csv").write_text(
        "RunCompletion\ncompleted\n", encoding="utf-8"
    )
    (run / "air_interface" / "csv" / "dl_pdsch_trials.csv").write_text(
        "TrialId,CRCPass\n1,1\n", encoding="utf-8"
    )

    assert MODULE.validate_run_root(run) == run.resolve()


def test_run_root_guard_accepts_yaml_declared_fixed_link_primary_trials(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setattr(MODULE, "REPO_ROOT", tmp_path)
    run = tmp_path / "results" / "lls" / "fixed_link" / "run_1"
    (run / "meta").mkdir(parents=True)
    (run / "reports" / "csv").mkdir(parents=True)
    (run / "air_interface" / "csv").mkdir(parents=True)
    (run / "meta" / "scenario_config_identity.json").write_text(
        "{}", encoding="utf-8"
    )
    (run / "meta" / "scenario_config_resolved.json").write_text(
        json.dumps(
            {
                "scenario": {"runner_profile": "waveform_bundle"},
                "simulation": {"link_direction": "both"},
                "sweeps_and_matrix": {
                    "fixed_link_calibration": {"enabled": True, "only": True}
                },
            }
        ),
        encoding="utf-8",
    )
    (run / "reports" / "csv" / "scenario_summary.csv").write_text(
        "RunCompletion\ncompleted\n", encoding="utf-8"
    )
    for direction in ("dl", "ul"):
        (run / "air_interface" / "csv" / f"{direction}_fixed_link_campaign_trials.csv").write_text(
            "Direction,CRCPass\n" + direction.upper() + ",1\n",
            encoding="utf-8",
        )

    assert MODULE.validate_run_root(run) == run.resolve()
    assert not (run / "air_interface" / "csv" / "dl_pdsch_trials.csv").exists()
    assert not (run / "air_interface" / "csv" / "ul_pusch_trials.csv").exists()


def test_missing_legacy_raster_claim_is_retired_without_touching_source_csv(
    tmp_path: Path,
) -> None:
    run = tmp_path / "scenario" / "run"
    source = run / "channel" / "csv" / "measurements.csv"
    source.parent.mkdir(parents=True)
    source.write_text("x,y\n1,2\n", encoding="utf-8")
    lineage = run / "channel" / "csv" / "channel_plot_lineage.csv"
    lineage.write_text(
        "PlotId,ImagePath,SourceCSV,ImageSHA256,ImageExists,Status,FailureReason\n"
        "channel_plot,channel/image/old.png,channel/csv/measurements.csv,"
        + "a" * 64
        + ",1,pass,\n",
        encoding="utf-8",
    )

    changes = MODULE.reconcile_removed_raster_lineage(run)
    assert len(changes) == 1
    rows = MODULE.read_csv(lineage)
    assert rows[0]["Status"] == "not_rendered"
    assert rows[0]["ImageExists"] == "0"
    assert rows[0]["ImageSHA256"] == ""
    assert rows[0]["FailureReason"] == "removed_by_csv_authority_raster_replacement"
    assert source.read_text(encoding="utf-8") == "x,y\n1,2\n"
    retired = MODULE.retired_raster_lineage_inventory(run)
    assert len(retired) == 1
    assert retired[0]["image_path"] == "channel/image/old.png"


def _write_frc_point_fixture(run: Path, *, proxy_used: str = "0") -> tuple[Path, Path]:
    source = run / "reports" / "csv" / "frc_reference_points" / "dl_qpsk_awgn.csv"
    MODULE.write_csv(
        source,
        [
            {
                "EntryId": "dl_qpsk_awgn",
                "FRC": "R.PDSCH.1-1.4 FDD",
                "Condition": "awgn_static_1x2",
                "Metric": "block_error_rate",
                "SNR_dB": "3.2",
                "MetricEstimate": "0.01",
                "ConfidenceLower": "0.002",
                "ConfidenceUpper": "0.035",
                "TargetFraction": "0.01",
                "RequiredSNR_dB": "3.2",
                "TransportBlocks": "100",
                "ExecutionBackend": "truth_waveform",
                "ApproximationMode": "none",
                "Source": "sixgr.conformance.runFRCPoint",
                "ProxyUsed": proxy_used,
                "FallbackUsed": "0",
            }
        ],
        [
            "EntryId", "FRC", "Condition", "Metric", "SNR_dB",
            "MetricEstimate", "ConfidenceLower", "ConfidenceUpper",
            "TargetFraction", "RequiredSNR_dB", "TransportBlocks",
            "ExecutionBackend", "ApproximationMode", "Source",
            "ProxyUsed", "FallbackUsed",
        ],
    )
    image = run / "reports" / "image" / "dl_qpsk_awgn_reference_point.png"
    lineage = run / "reports" / "csv" / "frc_reference_plot_lineage.csv"
    MODULE.write_csv(
        lineage,
        [
            {
                "PlotId": "frc_reference_point_dl_qpsk_awgn",
                "ImagePath": image.relative_to(run).as_posix(),
                "SourceCSV": source.relative_to(run).as_posix(),
                "SourceCSV_SHA256": "",
                "ImageSHA256": "",
                "Width": "0",
                "Height": "0",
                "MimeType": "image/png",
                "ImageExists": "0",
                "SourceExists": "1",
                "ProducerModule": "old_producer",
                "Status": "not_rendered",
                "FailureReason": "removed_by_csv_authority_raster_replacement",
            }
        ],
        [
            "PlotId", "ImagePath", "SourceCSV", "SourceCSV_SHA256",
            "ImageSHA256", "Width", "Height", "MimeType", "ImageExists",
            "SourceExists", "ProducerModule", "Status", "FailureReason",
        ],
    )
    return source, image


def test_frc_reference_raster_is_rebuilt_from_exact_csv_and_lineage_resealed(
    tmp_path: Path,
) -> None:
    from PIL import Image

    run = tmp_path / "scenario" / "run"
    source, image = _write_frc_point_fixture(run)

    generated = MODULE.materialize_frc_reference_rasters(run)

    assert len(generated) == 1
    assert image.is_file()
    with Image.open(image) as raster:
        raster.load()
        assert raster.size == (1280, 720)
        assert raster.format == "PNG"
        assert "FRC RUNTIME TRUTH" in str(raster.info.get("sixgr_visual_semantics", ""))
    lineage = MODULE.read_csv(run / "reports/csv/frc_reference_plot_lineage.csv")[0]
    assert lineage["Status"] == "pass"
    assert lineage["FailureReason"] == ""
    assert lineage["ImageExists"] == "1"
    assert lineage["SourceExists"] == "1"
    assert lineage["SourceCSV_SHA256"] == MODULE.sha256(source)
    assert lineage["ImageSHA256"] == MODULE.sha256(image)
    assert lineage["Width"] == "1280"
    assert lineage["Height"] == "720"
    assert lineage["ProducerModule"].endswith("materialize_frc_reference_rasters")
    assert MODULE.reconcile_removed_raster_lineage(run) == []


def test_frc_reference_raster_rejects_proxy_rows(tmp_path: Path) -> None:
    run = tmp_path / "scenario" / "run"
    _write_frc_point_fixture(run, proxy_used="1")
    with pytest.raises(RuntimeError, match="Proxy or fallback FRC rows"):
        MODULE.materialize_frc_reference_rasters(run)


@pytest.mark.skipif(os.name != "nt", reason="Windows MAX_PATH regression")
def test_long_path_raster_inventory_and_lineage_reconciliation(tmp_path: Path) -> None:
    run = tmp_path / "scenario" / "run"
    deep = run
    while len(str(deep / "chart.png")) <= 280:
        deep = deep / "contract_chart_directory_with_a_long_semantic_name"
    image = deep / "chart.png"
    MODULE.io_path(image.parent).mkdir(parents=True, exist_ok=True)
    from PIL import Image

    Image.new("RGB", (32, 24), "white").save(MODULE.io_path(image), format="PNG")
    lineage = run / "reports" / "csv" / "contract_plot_lineage.csv"
    MODULE.write_csv(
        lineage,
        [
            {
                "PlotId": "long_path_chart",
                "ImagePath": image.relative_to(run).as_posix(),
                "ImageSHA256": MODULE.sha256(image),
                "ImageExists": "1",
                "Status": "pass",
            }
        ],
        ["PlotId", "ImagePath", "ImageSHA256", "ImageExists", "Status"],
    )

    inventory = MODULE.raster_inventory(run)
    assert [row["relative_path"] for row in inventory] == [image.relative_to(run).as_posix()]
    assert MODULE.reconcile_removed_raster_lineage(run) == []
    assert MODULE.read_csv(lineage)[0]["Status"] == "pass"


def test_missing_chart_inventory_classifies_evidence_gap_without_placeholder_png(
    tmp_path: Path,
) -> None:
    run = tmp_path / "scenario" / "run"
    manifest = run / "reports" / "csv" / "contract_materialization_manifest.csv"
    MODULE.write_csv(
        manifest,
        [
            {
                "logical_path": "reports/image/bler.png",
                "artifact_kind": "image_png",
                "materialization_status": "suppressed_placeholder_artifact",
                "source_logical_path": "air_interface/csv/dl_pdsch_trials.csv",
                "note": "BLER vs SNR",
            }
        ],
        [
            "logical_path",
            "artifact_kind",
            "materialization_status",
            "source_logical_path",
            "note",
        ],
    )
    rows = MODULE.missing_chart_contract_inventory(run)
    assert len(rows) == 1
    assert rows[0]["classification"] == "requires_multi_point_or_statistical_evidence"
    assert list(run.rglob("*.png")) == []


def test_declared_component_csv_mirror_is_rebound_to_current_canonical_bytes(
    tmp_path: Path,
) -> None:
    run = tmp_path / "scenario" / "run"
    canonical = run / "reports" / "csv" / "plot_manifest.csv"
    published = run / "validation" / "csv" / "plot_manifest.csv"
    canonical.parent.mkdir(parents=True)
    published.parent.mkdir(parents=True)
    canonical.write_text("PlotId,Status\nnew,pass\n", encoding="utf-8")
    published.write_text("PlotId,Status\nold,fail\n", encoding="utf-8")
    manifest = run / "reports" / "csv" / "component_artifact_publication_manifest.csv"
    old_hash = MODULE.sha256(published)
    MODULE.write_csv(
        manifest,
        [
            {
                "Component": "validation",
                "ArtifactType": "csv",
                "CanonicalRelativePath": "reports/csv/plot_manifest.csv",
                "PublishedRelativePath": "validation/csv/plot_manifest.csv",
                "CanonicalSHA256": old_hash,
                "PublishedSHA256": old_hash,
                "ByteSize": published.stat().st_size,
                "MirrorOnly": 1,
                "CanonicalAuthorityRetained": 1,
                "SourceTruthClassification": "byte_identical_canonical_mirror",
                "PublishStatus": "PUBLISHED_HASH_VERIFIED",
            }
        ],
        [
            "Component",
            "ArtifactType",
            "CanonicalRelativePath",
            "PublishedRelativePath",
            "CanonicalSHA256",
            "PublishedSHA256",
            "ByteSize",
            "MirrorOnly",
            "CanonicalAuthorityRetained",
            "SourceTruthClassification",
            "PublishStatus",
        ],
    )

    changes = MODULE.synchronize_declared_component_mirrors(run)
    assert len(changes) == 1
    assert changes[0]["bytes_replaced"] == "1"
    assert published.read_bytes() == canonical.read_bytes()
    row = MODULE.read_csv(manifest)[0]
    assert row["CanonicalSHA256"] == MODULE.sha256(canonical)
    assert row["PublishedSHA256"] == MODULE.sha256(canonical)
    assert row["PublishStatus"] == "PUBLISHED_HASH_VERIFIED"


def test_header_only_component_csv_mirror_is_pruned(tmp_path: Path) -> None:
    run = tmp_path / "scenario" / "run"
    canonical = run / "reports/csv/truth_contract_failures.csv"
    published = run / "validation/csv/truth_contract_failures.csv"
    canonical.parent.mkdir(parents=True)
    published.parent.mkdir(parents=True)
    canonical.write_text("FailureCode,FailureReason\n", encoding="utf-8")
    published.write_bytes(canonical.read_bytes())
    manifest = run / "reports/csv/component_artifact_publication_manifest.csv"
    digest = MODULE.sha256(canonical)
    MODULE.write_csv(
        manifest,
        [{
            "Component": "validation", "ArtifactType": "csv",
            "CanonicalRelativePath": "reports/csv/truth_contract_failures.csv",
            "PublishedRelativePath": "validation/csv/truth_contract_failures.csv",
            "CanonicalSHA256": digest, "PublishedSHA256": digest,
            "ByteSize": canonical.stat().st_size, "MirrorOnly": 1,
            "CanonicalAuthorityRetained": 1,
            "SourceTruthClassification": "byte_identical_canonical_mirror",
            "PublishStatus": "PUBLISHED_HASH_VERIFIED",
        }],
        [
            "Component", "ArtifactType", "CanonicalRelativePath",
            "PublishedRelativePath", "CanonicalSHA256", "PublishedSHA256",
            "ByteSize", "MirrorOnly", "CanonicalAuthorityRetained",
            "SourceTruthClassification", "PublishStatus",
        ],
    )
    changes = MODULE.synchronize_declared_component_mirrors(run)
    assert len(changes) == 1 and changes[0]["bytes_replaced"] == "-1"
    assert canonical.is_file()
    assert not published.exists()
    assert MODULE.read_csv(manifest) == []


def test_declared_component_mirror_refuses_path_escape(tmp_path: Path) -> None:
    run = tmp_path / "scenario" / "run"
    manifest = run / "reports" / "csv" / "component_artifact_publication_manifest.csv"
    MODULE.write_csv(
        manifest,
        [
            {
                "CanonicalRelativePath": "../../outside.csv",
                "PublishedRelativePath": "validation/csv/outside.csv",
                "CanonicalSHA256": "",
                "PublishedSHA256": "",
                "ByteSize": 0,
                "MirrorOnly": 1,
                "CanonicalAuthorityRetained": 1,
                "SourceTruthClassification": "byte_identical_canonical_mirror",
                "PublishStatus": "PUBLISHED_HASH_VERIFIED",
            }
        ],
        [
            "CanonicalRelativePath",
            "PublishedRelativePath",
            "CanonicalSHA256",
            "PublishedSHA256",
            "ByteSize",
            "MirrorOnly",
            "CanonicalAuthorityRetained",
            "SourceTruthClassification",
            "PublishStatus",
        ],
    )
    with pytest.raises(RuntimeError, match="escapes run root"):
        MODULE.synchronize_declared_component_mirrors(run)


def test_declared_component_mirror_refuses_conflicting_canonical_authorities(
    tmp_path: Path,
) -> None:
    run = tmp_path / "scenario" / "run"
    first = run / "reports" / "csv" / "first.csv"
    second = run / "reports" / "csv" / "second.csv"
    first.parent.mkdir(parents=True)
    first.write_text("value\n1\n", encoding="utf-8")
    second.write_text("value\n2\n", encoding="utf-8")
    manifest = run / "reports" / "csv" / "component_artifact_publication_manifest.csv"
    base = {
        "PublishedRelativePath": "validation/csv/shared.csv",
        "CanonicalSHA256": "",
        "PublishedSHA256": "",
        "ByteSize": 0,
        "MirrorOnly": 1,
        "CanonicalAuthorityRetained": 1,
        "SourceTruthClassification": "byte_identical_canonical_mirror",
        "PublishStatus": "PUBLISHED_HASH_VERIFIED",
    }
    MODULE.write_csv(
        manifest,
        [
            {**base, "CanonicalRelativePath": "reports/csv/first.csv"},
            {**base, "CanonicalRelativePath": "reports/csv/second.csv"},
        ],
        [
            "CanonicalRelativePath",
            "PublishedRelativePath",
            "CanonicalSHA256",
            "PublishedSHA256",
            "ByteSize",
            "MirrorOnly",
            "CanonicalAuthorityRetained",
            "SourceTruthClassification",
            "PublishStatus",
        ],
    )
    with pytest.raises(RuntimeError, match="Conflicting canonical authorities"):
        MODULE.synchronize_declared_component_mirrors(run)


def test_component_summary_uses_canonical_nonblank_scenario_identity(tmp_path: Path) -> None:
    run = tmp_path / "scenario" / "run"
    MODULE.write_csv(
        run / "reports/csv/scenario_summary.csv",
        [{"ScenarioID": "scenario_a", "ConfigHash": "a" * 64, "RunnerProfile": "waveform_bundle"}],
        ["ScenarioID", "ConfigHash", "RunnerProfile"],
    )
    MODULE.update_component_summary(run, [])
    rows = MODULE.read_csv(run / "reports/csv/component_artifact_publication_summary.csv")
    assert len(rows) == len(MODULE.COMPONENTS)
    assert {row["ScenarioID"] for row in rows} == {"scenario_a"}
    assert {row["ConfigHash"] for row in rows} == {"a" * 64}
    assert {row["RunnerProfile"] for row in rows} == {"waveform_bundle"}


def test_retired_artifact_engine_png_rows_are_removed_without_regeneration(
    tmp_path: Path,
) -> None:
    run = tmp_path / "scenario" / "run"
    result = run / "artifact_generation/artifact_generation_results.csv"
    result_fields = [
        "ContractID", "Domain", "Component", "Profile", "ArtifactType", "FileName",
        "Required", "Status", "Producer", "SourceRows", "OutputRelativePath",
        "SourceSHA256", "SHA256", "ByteSize", "Width", "Height", "AxesCount",
        "SeriesCount", "FinitePointCount", "Message",
    ]
    MODULE.write_csv(
        result,
        [{
            "ContractID": "retired_png|runtime_in_path", "Domain": "pdsch", "Component": "pdsch",
            "Profile": "base", "ArtifactType": "PNG", "FileName": "retired_runtime_plot.png",
            "Required": "1", "Status": "PASS", "Producer": "stale", "SourceRows": "2",
            "OutputRelativePath": "pdsch/png/retired_runtime_plot.png", "SourceSHA256": "b" * 64,
            "SHA256": "c" * 64, "ByteSize": "1", "Width": "1", "Height": "1",
            "AxesCount": "0", "SeriesCount": "0", "FinitePointCount": "0", "Message": "",
        }],
        result_fields,
    )
    retired = MODULE.retire_runtime_artifact_engine_rasters(run)
    assert len(retired) == 1
    assert retired[0]["migration_reason"] == (
        "runtime_raster_authority_moved_to_csv_contract_materializer"
    )
    assert MODULE.materialize_declared_artifact_generation_rasters(run) == []
    assert MODULE.read_csv(result) == []
    assert not (run / "pdsch/png/retired_runtime_plot.png").exists()


def test_csv_only_resume_removes_header_only_runtime_metadata(tmp_path: Path) -> None:
    run = tmp_path / "scenario" / "run"
    result = run / "artifact_generation/artifact_generation_results.csv"
    MODULE.write_csv(
        result,
        [{"ContractID": "pdsch|base|csv|curve.csv|runtime_in_path",
          "ArtifactType": "CSV", "Status": "PASS"}],
        ["ContractID", "ArtifactType", "Status"],
    )
    component_lineage = run / "components/contract_plot_lineage.csv"
    failure_registry = run / "artifact_generation/artifact_generation_failures.csv"
    MODULE.write_csv(component_lineage, [], ["PlotId", "ImagePath", "Status"])
    MODULE.write_csv(failure_registry, [], ["ContractID", "Status", "Message"])

    assert MODULE.retire_runtime_artifact_engine_rasters(run) == []
    assert not component_lineage.exists()
    assert not failure_registry.exists()
    assert MODULE.read_csv(result)[0]["ArtifactType"] == "CSV"


def test_raw_index_shape_repair_changes_only_stale_column_count(tmp_path: Path) -> None:
    run = tmp_path / "scenario" / "run"
    raw = run / "raw/evidence/tables/raw.csv"
    MODULE.write_csv(raw, [{"a": "1", "b": "2"}], ["a", "b"])
    original_bytes = raw.read_bytes()
    index = run / "raw/evidence/raw_evidence_index.csv"
    MODULE.write_csv(
        index,
        [{
            "RelativePath": "tables/raw.csv", "RowCount": "1", "ColumnCount": "1",
            "SHA256": MODULE.sha256(raw),
        }],
        ["RelativePath", "RowCount", "ColumnCount", "SHA256"],
    )
    changes = MODULE.reconcile_raw_evidence_index_shape_metadata(run)
    assert len(changes) == 1
    assert changes[0]["previous_column_count"] == "1"
    assert changes[0]["current_column_count"] == "2"
    assert raw.read_bytes() == original_bytes
    assert MODULE.read_csv(index)[0]["ColumnCount"] == "2"


def test_raw_index_shape_repair_refuses_hash_mismatch(tmp_path: Path) -> None:
    run = tmp_path / "scenario" / "run"
    raw = run / "raw/evidence/tables/raw.csv"
    MODULE.write_csv(raw, [{"a": "1"}], ["a"])
    MODULE.write_csv(
        run / "raw/evidence/raw_evidence_index.csv",
        [{"RelativePath": "tables/raw.csv", "RowCount": "1", "ColumnCount": "1", "SHA256": "0" * 64}],
        ["RelativePath", "RowCount", "ColumnCount", "SHA256"],
    )
    with pytest.raises(RuntimeError, match="authenticated bytes differ"):
        MODULE.reconcile_raw_evidence_index_shape_metadata(run)
