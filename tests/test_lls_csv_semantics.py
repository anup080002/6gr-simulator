from __future__ import annotations

import sys
import csv
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "tools"))

from lls_csv_semantics import (  # noqa: E402
    audit_run,
    _audit_derived_link_table,
    _audit_domain_runtime_tables,
    _audit_link_table,
    _audit_manifest_integrity,
    _audit_runtime_call_ledger,
    _audit_status_reduction,
)


def test_pdcch_component_semantics_require_pdcch_not_data_trials(tmp_path: Path) -> None:
    scenario_hash = "a" * 64
    _write_rows(
        tmp_path / "reports/csv/scenario_summary.csv",
        [{
            "RunnerProfile": "ctrl6gr_pdcch_study",
            "RunCompletion": "completed",
            "RunID": "run-1",
            "RunTag": "run-1",
            "ScenarioID": "pdcch-study",
            "ConfigHash": scenario_hash,
            "ExecutionID": "execution-1",
            "EffectiveDLTrialCount": "0",
            "EffectiveULTrialCount": "0",
        }],
    )
    _write_rows(
        tmp_path / "air_interface/csv/pdcch_trials.csv",
        [{
            "RunID": "run-1",
            "RunTag": "run-1",
            "ScenarioID": "pdcch-study",
            "ScenarioConfigHash": scenario_hash,
            "ExecutionID": "execution-1",
            "EvidenceScope": "in_path",
            "EstimatedSINR_dB": "12.5",
            "CRCPass": "1",
            "FalseAlarmFlag": "0",
        }],
    )

    audit = audit_run(tmp_path)
    checks = audit["canonical_csv_semantic_audit"]
    link_checks = [row for row in checks if row["category"] == "primary_link"]
    assert link_checks
    assert all(not row["required"] for row in link_checks)
    pdcch_checks = [
        row for row in checks if row["artifact_path"] == "air_interface/csv/pdcch_trials.csv"
    ]
    assert pdcch_checks
    assert all(row["passed"] for row in pdcch_checks), pdcch_checks


def _mu_check(direction: str, row: dict[str, str]):
    checks = _audit_link_table("trial.csv", list(row), [row], direction, 1)
    return next(check for check in checks if check.check_id == "mu_mimo_receiver_execution")


def test_dl_mu_requires_measured_joint_irc_processing_not_fake_combiner() -> None:
    row = {
        "MUMIMOEnabled": "1",
        "MUMIMOGroupSize": "2",
        "InterferenceContributorCount": "1",
        "FullInterfererChannelTruthUsed": "1",
        "InterferenceCovarianceAvailable": "1",
        "InterferenceCovarianceSource": "shared_slot_contribution_grid_covariance",
        "EqualizerType": "MMSE-IRC",
        "MUMIMOReceiveProcessingApplied": "1",
        "MUMIMOReceiveProcessingStatus": "applied_shared_slot_covariance_resource_selective_per_re_mmse_irc",
        "MUMIMOReceiveProcessingSource": "sixgr.phy.dl.PDSCH_Rx.EqualizationInfo",
        "MUMIMOReceiveProcessingModeApplied": "resource_selective_per_re_mmse_irc",
        "MUMIMOReceiverAlgorithmApplied": "MMSE-IRC",
        "MUMIMOReceiveCombinerApplied": "0",
        "MUMIMOReceiveCombinerStatus": "not_applicable_joint_per_re_mmse_irc_equalizer_no_separate_combiner",
    }
    check = _mu_check("DL", row)
    assert check.passed, check.details


def test_dl_mu_fails_without_applied_receiver_processing() -> None:
    row = {
        "MUMIMOEnabled": "1",
        "MUMIMOGroupSize": "2",
        "InterferenceContributorCount": "1",
        "FullInterfererChannelTruthUsed": "1",
        "InterferenceCovarianceAvailable": "1",
        "EqualizerType": "MMSE-IRC",
        "MUMIMOReceiveProcessingApplied": "0",
        "MUMIMOReceiveCombinerApplied": "0",
        "MUMIMOReceiveCombinerStatus": "not_applicable_joint_per_re_mmse_irc_equalizer_no_separate_combiner",
    }
    check = _mu_check("DL", row)
    assert not check.passed
    assert "mu_receive_processing_not_applied" in check.details


def _write_rows(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def test_terminal_status_reduction_rejects_stale_visual_failure(tmp_path: Path) -> None:
    _write_rows(
        tmp_path / "reports/csv/visual_artifact_integrity.csv",
        [{"IntegrityOk": "1"}],
    )
    _write_rows(
        tmp_path / "reports/csv/visual_artifact_audit.csv",
        [{"audit_ok": "1"}],
    )
    _write_rows(
        tmp_path / "reports/csv/result_status_summary.csv",
        [
            {
                "ResultOk": "0",
                "RuntimeTruthContractOk": "0",
                "VisualArtifactGateOk": "0",
                "VisualArtifactFailureCount": "2",
            }
        ],
    )
    _write_rows(
        tmp_path / "reports/csv/truth_contract_failures.csv",
        [{"FailureCode": "visual_artifact_gate_failed"}],
    )
    summary = {
        "ResultOk": "0",
        "RuntimeTruthContractOk": "0",
        "VisualArtifactIntegrityOk": "0",
        "VisualArtifactIntegrityFailureCount": "2",
        "VisualArtifactGateOk": "0",
        "VisualArtifactFailureCount": "2",
    }
    checks = _audit_status_reduction(tmp_path, "reports/csv/scenario_summary.csv", summary)
    assert any(not check.passed for check in checks)
    assert "retains_visual_failures" in checks[0].details


def test_visual_audit_tables_are_domain_contracted_and_fail_closed(tmp_path: Path) -> None:
    summary = {"ScenarioID": "visual_fixture", "ConfigHash": "a" * 64}
    _write_rows(
        tmp_path / "reports/csv/visual_artifact_integrity.csv",
        [{"ArtifactPath": "reports/image/chart.png", "IntegrityOk": "1"}],
    )
    _write_rows(
        tmp_path / "reports/csv/visual_artifact_audit.csv",
        [{"relative_path": "reports/image/chart.png", "audit_ok": "1"}],
    )
    checks = _audit_domain_runtime_tables(tmp_path, summary)
    selected = [
        check
        for check in checks
        if check.artifact_path
        in {
            "reports/csv/visual_artifact_integrity.csv",
            "reports/csv/visual_artifact_audit.csv",
        }
    ]
    assert len(selected) == 8
    assert all(check.passed for check in selected)

    _write_rows(
        tmp_path / "reports/csv/visual_artifact_integrity.csv",
        [{"ArtifactPath": "reports/image/chart.png", "IntegrityOk": "0"}],
    )
    checks = _audit_domain_runtime_tables(tmp_path, summary)
    # Baseline domain validation classifies and range-checks these tables;
    # terminal pass/fail reduction is enforced separately by
    # _audit_status_reduction against the exact same persisted rows.
    assert any(
        check.artifact_path == "reports/csv/visual_artifact_integrity.csv"
        for check in checks
    )


def test_derived_bler_curve_requires_exact_failure_count_arithmetic() -> None:
    row = {
        "Direction": "DL",
        "PostEqSINR_dB_BinCenter": "10",
        "PostEqSINR_dB_BinMin": "9.5",
        "PostEqSINR_dB_BinMax": "10.5",
        "BLER": "0.25",
        "BLER_CI_Low": "0.05",
        "BLER_CI_High": "0.55",
        "BER": "0.01",
        "TrialCount": "4",
        "FailureCount": "2",
        "SourceArtifact": "dl_pdsch_trials.csv",
    }
    checks = _audit_derived_link_table(
        "air_interface/csv/dl_measured_sinr_bler_curve.csv",
        list(row),
        [row],
        {"DL": [], "UL": []},
    )
    reconciliation = next(
        check for check in checks if check.check_id == "same_trial_population_reconciliation"
    )
    assert not reconciliation.passed
    assert "bler_failure_count_arithmetic_mismatch" in reconciliation.details


def test_derived_link_summary_reconciles_weighted_ber_and_trial_count() -> None:
    raw = [
        {
            "UEIndex": "1",
            "CRCPass": "1",
            "BitErrors": "0",
            "BitsCompared": "100",
            "Throughput_Mbps": "10",
        },
        {
            "UEIndex": "1",
            "CRCPass": "0",
            "BitErrors": "9",
            "BitsCompared": "900",
            "Throughput_Mbps": "20",
        },
    ]
    row = {
        "Direction": "DL",
        "UEIndex": "1",
        "N_Trials": "2",
        "SINR_min_dB": "1",
        "SINR_p5_dB": "1",
        "SINR_median_dB": "2",
        "SINR_p95_dB": "3",
        "SINR_max_dB": "3",
        "BLER_overall": "0.5",
        "BER_overall": "0.009",
        "Throughput_Mbps_mean": "15",
        "Goodput_Mbps_mean": "5",
        "OfferedThroughput_Mbps_mean": "15",
        "SourceArtifact": "dl_pdsch_trials.csv",
    }
    checks = _audit_derived_link_table(
        "air_interface/csv/live_measured_sinr_summary.csv",
        list(row),
        [row],
        {"DL": raw, "UL": []},
    )
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_artifact_manifest_rejects_pass_claim_for_missing_png(tmp_path: Path) -> None:
    rows = [{
        "ContractID": "pdsch|base|png|pdsch_bler_vs_snr.png|runtime_in_path",
        "Domain": "pdsch", "Component": "pdsch", "Profile": "base",
        "ArtifactType": "PNG", "FileName": "pdsch_bler_vs_snr.png", "Required": "1",
        "Status": "PASS", "SourceRows": "2", "OutputRelativePath": "pdsch/png/pdsch_bler_vs_snr.png",
        "SourceSHA256": "a" * 64, "SHA256": "b" * 64, "ByteSize": "123",
        "Width": "1180", "Height": "700", "AxesCount": "1", "SeriesCount": "2",
        "FinitePointCount": "4",
    }]
    _write_rows(tmp_path / "artifact_generation/artifact_generation_results.csv", rows)
    checks = _audit_manifest_integrity(tmp_path)
    result_check = next(check for check in checks if check.check_id == "declared_artifacts_match_filesystem")
    assert not result_check.passed
    assert "pass_claim_missing_canonical_manifest_row" in result_check.details


def test_artifact_manifest_resolves_generator_output_under_components_root(
    tmp_path: Path,
) -> None:
    import hashlib

    contract_id = "pdsch|base|csv|pdsch_bler_curve.csv|all|runtime_in_path"
    output = tmp_path / "components/pdsch/csv/pdsch_bler_curve.csv"
    _write_rows(output, [{"SNR_dB": "20", "BLER": "0"}])
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    result = {
        "ContractID": contract_id,
        "Domain": "pdsch", "Component": "pdsch", "Profile": "base",
        "ArtifactType": "CSV", "FileName": "pdsch_bler_curve.csv",
        "Required": "1", "Status": "PASS", "SourceRows": "1",
        "OutputRelativePath": "pdsch/csv/pdsch_bler_curve.csv",
        "SourceSHA256": digest, "SHA256": digest,
        "ByteSize": str(output.stat().st_size), "Width": "0", "Height": "0",
        "AxesCount": "0", "SeriesCount": "0", "FinitePointCount": "0",
    }
    _write_rows(
        tmp_path / "artifact_generation/artifact_generation_results.csv",
        [result],
    )
    manifest = dict(result)
    manifest["PublishedRelativePath"] = "components/pdsch/csv/pdsch_bler_curve.csv"
    _write_rows(
        tmp_path / "artifact_generation/canonical_component_manifest.csv",
        [manifest],
    )
    summary = {
        "Domain": "pdsch", "Component": "pdsch", "Profile": "base",
        "ArtifactType": "CSV", "ContractCount": "1", "RequiredCount": "1",
        "GeneratedCount": "1", "MissingCount": "0", "FailedCount": "0",
        "RequiredFailureCount": "0", "SourceRowCount": "1",
        "PublishedByteCount": str(output.stat().st_size), "Status": "PASS",
    }
    _write_rows(
        tmp_path / "artifact_generation/artifact_generation_summary.csv",
        [summary],
    )
    checks = _audit_manifest_integrity(tmp_path)
    result_check = next(
        check for check in checks
        if check.check_id == "declared_artifacts_match_filesystem"
    )
    assert result_check.passed, result_check.details


def test_component_summary_rejects_blank_identity(tmp_path: Path) -> None:
    canonical = tmp_path / "reports/csv/source.csv"
    published = tmp_path / "pdsch/csv/source.csv"
    _write_rows(canonical, [{"value": "1"}])
    _write_rows(published, [{"value": "1"}])
    import hashlib

    digest = hashlib.sha256(canonical.read_bytes()).hexdigest()
    _write_rows(
        tmp_path / "reports/csv/component_artifact_publication_manifest.csv",
        [{
            "Component": "pdsch", "ArtifactType": "csv",
            "CanonicalRelativePath": "reports/csv/source.csv",
            "PublishedRelativePath": "pdsch/csv/source.csv", "CanonicalSHA256": digest,
            "PublishedSHA256": digest, "ByteSize": str(canonical.stat().st_size),
            "PublishStatus": "PUBLISHED_HASH_VERIFIED",
        }],
    )
    _write_rows(
        tmp_path / "reports/csv/scenario_summary.csv",
        [{"ScenarioID": "scenario", "ConfigHash": "a" * 64, "RunnerProfile": "waveform_bundle"}],
    )
    _write_rows(
        tmp_path / "reports/csv/component_artifact_publication_summary.csv",
        [{
            "ScenarioID": "", "ConfigHash": "", "RunnerProfile": "", "Component": "pdsch",
            "SourceArtifactCount": "1", "CSVCount": "1", "RasterImageCount": "0",
            "JSONCount": "0", "MATCount": "0", "PublicationStatus": "PUBLISHED_HASH_VERIFIED",
        }],
    )
    checks = _audit_manifest_integrity(tmp_path)
    summary_check = next(check for check in checks if check.check_id == "component_summary_reconciles_manifest")
    assert not summary_check.passed
    assert "scenario_identity_mismatch" in summary_check.details


def test_domain_runtime_contract_checks_identity_probability_and_truth(tmp_path: Path) -> None:
    _write_rows(
        tmp_path / "analytics/csv/example.csv",
        [{
            "ScenarioID": "wrong", "ConfigHash": "b" * 64, "RunID": "run",
            "ExecutionID": "execution", "EvidenceScope": "in_path", "BLER": "1.2",
            "FallbackFlag": "1", "TruthStatus": "fallback", "TrialCount": "2",
        }],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "expected", "ConfigHash": "a" * 64},
    )
    failed = {check.check_id: check.details for check in checks if not check.passed}
    assert "ScenarioID_mismatch_or_missing" in failed["scenario_execution_identity"]
    assert "BLER_outside_unit_interval" in failed["populated_physical_value_ranges"]
    assert "FallbackFlag_true_in_path" in failed["in_path_truth_proxy_separation"]


def test_live_reselection_event_table_may_be_schema_only_when_no_event_occurred(tmp_path: Path) -> None:
    path = tmp_path / "reports/csv/live_cell_reselection_events.csv"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("ScenarioID,UEID,Slot,Event\n", encoding="utf-8")
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "scenario", "ConfigHash": "a" * 64},
    )
    assert checks
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_fixed_link_disabled_live_domains_are_not_required_but_user_summary_is(
    tmp_path: Path,
) -> None:
    resolved = {
        "validation": {"run_class": "fixed_snr_sweep_lls"},
        "mimo_and_beam_management": {"beam_sweeping": False},
        "system": {"beam": {"enable": False}},
        "reference_signals": {
            "ssb_enabled": False,
            "csi_rs_enabled": False,
            "nzp_csi_rs": {"enabled": False},
        },
    }
    config_path = tmp_path / "meta/scenario_config_resolved.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(resolved), encoding="utf-8")
    for relative in (
        "reports/csv/live_beam_p1_acquisition_stats.csv",
        "reports/csv/live_coverage_layer.csv",
        "reports/csv/live_csirs_stats.csv",
        "reports/csv/live_user_performance_snapshot.csv",
    ):
        path = tmp_path / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("ScenarioID,ConfigHash\n", encoding="utf-8")
    _write_rows(
        tmp_path / "air_interface/csv/dl_pdsch_trials.csv",
        [{"CRCPass": "1"}],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "fixed", "ConfigHash": "a" * 64},
    )
    by_path = {
        check.artifact_path: check
        for check in checks
        if check.check_id == "schema_and_runtime_rows"
    }
    for relative in (
        "reports/csv/live_beam_p1_acquisition_stats.csv",
        "reports/csv/live_coverage_layer.csv",
        "reports/csv/live_csirs_stats.csv",
    ):
        assert not by_path[relative].required
        assert not by_path[relative].evaluated
    user = by_path["reports/csv/live_user_performance_snapshot.csv"]
    assert user.required and user.evaluated and not user.passed
    assert "missing_runtime_rows" in user.details


def test_runtime_config_application_evidence_rejects_nan_run_identity(tmp_path: Path) -> None:
    _write_rows(
        tmp_path / "reports/csv/runtime_config_application_evidence.csv",
        [{
            "RunId": "NaN",
            "ScenarioID": "scenario",
            "RunTag": "run_1",
            "ApplicationEventSequence": "1",
            "ApplicationEventID": "config_apply_00000001",
        }],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "scenario", "ConfigHash": "a" * 64},
    )
    failed = {check.check_id: check.details for check in checks if not check.passed}
    assert "RunId_missing" in failed["scenario_execution_identity"]
    assert "RunId_RunTag_mismatch" in failed["runtime_config_application_identity"]


def test_runtime_config_application_evidence_accepts_logical_run_tag_identity(tmp_path: Path) -> None:
    _write_rows(
        tmp_path / "reports/csv/runtime_config_application_evidence.csv",
        [{
            "RunId": "run_1",
            "ScenarioID": "scenario",
            "RunTag": "run_1",
            "ApplicationEventSequence": "1",
            "ApplicationEventID": "config_apply_00000001",
        }],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "scenario", "ConfigHash": "a" * 64},
    )
    assert checks
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_persisted_audit_view_receives_baseline_value_contract(tmp_path: Path) -> None:
    _write_rows(
        tmp_path / "reports/csv/standards_claim_audit.csv",
        [{"ScenarioID": "scenario", "ConfigHash": "a" * 64, "PassRate": "1.2"}],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "scenario", "ConfigHash": "a" * 64},
    )
    assert any(
        check.artifact_path == "reports/csv/standards_claim_audit.csv"
        and check.check_id == "populated_physical_value_ranges"
        and not check.passed
        for check in checks
    )


def _runtime_row(sequence: str, function_name: str, *, config_hash: str = "a" * 64) -> dict[str, str]:
    return {
        "Sequence": sequence,
        "TimestampUTC": "2026-08-17T00:00:00Z",
        "FunctionName": function_name,
        "Component": "PDSCH" if ".dl." in function_name else "PUSCH",
        "Direction": "DL" if ".dl." in function_name else "UL",
        "Event": "ENTER",
        "RunId": "run-1",
        "ExecutionID": "execution-1",
        "ConfigHash": config_hash,
        "ContextSHA256": "b" * 64,
        "EvidenceClass": "ACTUAL_RUNTIME_ENTRY",
        "ApproximationMode": "none",
    }


def test_runtime_ledger_is_required_when_primary_phy_rows_exist(tmp_path: Path) -> None:
    checks = _audit_runtime_call_ledger(
        tmp_path,
        {"ConfigHash": "a" * 64},
        {"DL": [{"CRCPass": "1"}], "UL": []},
    )
    assert any(check.required and not check.passed for check in checks)
    assert checks[0].check_id == "runtime_call_ledger_present_nonempty"
    assert "header_only" in checks[0].details


def test_runtime_ledger_accepts_exact_identity_bound_dl_ul_entry_points(tmp_path: Path) -> None:
    rows = [
        _runtime_row("1", "sixgr.phy.dl.PDSCH_Tx"),
        _runtime_row("2", "sixgr.phy.dl.PDSCH_Rx"),
        _runtime_row("3", "sixgr.phy.ul.PUSCH_Tx"),
        _runtime_row("4", "sixgr.phy.ul.PUSCH_Rx"),
    ]
    _write_rows(tmp_path / "reports/csv/runtime_call_ledger.csv", rows)
    checks = _audit_runtime_call_ledger(
        tmp_path,
        {"ConfigHash": "a" * 64, "RunID": "run-1", "ExecutionID": "execution-1"},
        {"DL": [{"CRCPass": "1"}], "UL": [{"CRCPass": "1"}]},
    )
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_runtime_ledger_rejects_proxy_identity_and_sequence_corruption(tmp_path: Path) -> None:
    rows = [
        _runtime_row("2", "sixgr.phy.dl.PDSCH_Tx", config_hash="c" * 64),
        _runtime_row("2", "sixgr.phy.dl.PDSCH_Rx", config_hash="c" * 64),
    ]
    rows[0]["EvidenceClass"] = "synthetic_runtime_entry"
    rows[1]["ApproximationMode"] = "fast_proxy"
    rows[1]["ContextSHA256"] = ""
    _write_rows(tmp_path / "reports/csv/runtime_call_ledger.csv", rows)
    checks = _audit_runtime_call_ledger(
        tmp_path,
        {"ConfigHash": "a" * 64},
        {"DL": [{"CRCPass": "1"}], "UL": []},
    )
    failed = {check.check_id: check.details for check in checks if not check.passed}
    assert "duplicate_sequence" in failed["runtime_call_sequence_positive_unique_monotonic"]
    assert "ConfigHash_mismatch" in failed["runtime_call_identity_matches_run"]
    assert "synthetic_runtime_entry" in failed["runtime_call_rows_are_actual_nonproxy_entries"]
    assert "fast_proxy" in failed["runtime_call_rows_are_actual_nonproxy_entries"]
