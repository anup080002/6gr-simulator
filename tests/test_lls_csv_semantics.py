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
    _audit_frc_point_table,
    _audit_link_table,
    _audit_manifest_integrity,
    _audit_runtime_call_ledger,
    _audit_status_reduction,
)


def _frc_point_row() -> dict[str, str]:
    return {
        "EntryId": "dl_rank4_tdla",
        "FRC": "R.PDSCH.1-2.4 FDD",
        "Condition": "TDL-A 30ns 10Hz",
        "Direction": "DL",
        "PhysicalChannel": "PDSCH",
        "Profile": "diagnostic",
        "Metric": "fraction_max_throughput",
        "RequiredSNR_dB": "15.6",
        "TargetFraction": "0.7",
        "SNR_dB": "15.6",
        "RequiredPoint": "1",
        "ExperimentSeed": "38104",
        "MetricEstimate": "0.8",
        "ConfidenceLower": "0.741744938411775",
        "ConfidenceUpper": "0.897599323883307",
        "OneSidedLower": "0.754273569428739",
        "OneSidedUpper": "1",
        "TransportBlocks": "4",
        "DeliveredTransportBlocks": "4",
        "FailedTransportBlocks": "0",
        "Transmissions": "5",
        "FailedTransmissionAttempts": "1",
        "PointEstimatePass": "1",
        "ObservedConfidenceBoundSupportsPass": "1",
        "ConfidenceSupportsPass": "0",
        "ConfidenceQualificationEligible": "0",
        "ConfidenceMethod": "clopper_pearson",
        "StopReason": "diagnostic_transport_block_cap",
        "StandardDocument": "TS 38.101-4",
        "StandardVersion": "18.7.0",
        "StandardRelease": "18",
        "StandardSourceURL": "https://www.3gpp.org/ftp/Specs/archive/38_series/38.101-4/",
        "FRCDefinitionClause": "Annex A",
        "FRCDefinitionTable": "Table A.3.2.2-1",
        "RequirementClause": "Clause 7.3",
        "RequirementTables": "Table 7.3.2-1",
        "ConfidenceLevel": "0.95",
        "RequiredQualificationTransportBlocks": "9604",
        "ConfidenceSamplingPlan": "one_sided_binomial",
        "StatisticalUnit": "transport_block",
        "ConfiguredModulation": "64QAM",
        "ConfiguredMCSTable": "qam64_table1",
        "ConfiguredMCSIndex": "20",
        "ConfiguredTargetCodeRate": "0.6015625",
        "EffectiveTargetCodeRate": "0.6015625",
        "ConfiguredTBSBits": "24456",
        "EffectiveTBSBits": "24456",
        "ConfiguredCodedBitsPerSlot": "40640",
        "EffectiveCodedBitsPerSlot": "40640",
        "ConfiguredLayers": "4",
        "ConfiguredTxAntennas": "4",
        "ConfiguredRxAntennas": "4",
        "EffectiveLayers": "4",
        "EffectiveTxPorts": "4",
        "NoiseVarSource": "waveform_awgn_variance",
        "DecoderNoiseVar": "0.0123",
        "PostEqSINR_dB": "14.8",
        "LastTBReceiverOk": "1",
        "LastTBCRCError": "0",
        "ChannelExecutionMode": "streamed_complete_sequence",
        "ChannelChunkSlots": "1",
        "ChannelChunkSamples": "15360",
        "ChannelCallCount": "21",
        "ChannelMaximumInputRows": "15360",
        "ChannelFullSequenceProcessed": "1",
        "ExecutionBackend": "matlab_5g_toolbox_waveform",
        "ApproximationMode": "none",
        "Source": "sixgr.conformance.runFRCPoint",
        "FullStandardExecutionExact": "0",
        "DataChannelExact": "1",
        "ProxyUsed": "0",
        "FallbackUsed": "0",
        "EvidenceClass": "SELECTED_DATA_CHANNEL_TRUTH_EXECUTION",
        "CatalogSHA256": "a" * 64,
    }


def test_frc_point_semantics_accept_exact_runtime_truth() -> None:
    row = _frc_point_row()
    checks = _audit_frc_point_table(
        "reports/csv/frc_reference_points.csv", list(row), [row]
    )
    assert checks
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_frc_point_semantics_reject_count_and_effective_rank_corruption() -> None:
    row = _frc_point_row()
    row["DeliveredTransportBlocks"] = "5"
    row["EffectiveLayers"] = "1"
    checks = _audit_frc_point_table(
        "reports/csv/frc_reference_points.csv", list(row), [row]
    )
    failed = {check.check_id: check.details for check in checks if not check.passed}
    assert "transport_block_arithmetic_mismatch" in failed[
        "metric_confidence_and_tb_arithmetic"
    ]
    assert "configured_effective_phy_mismatch" in failed[
        "configured_effective_phy_and_receiver"
    ]


def test_frc_only_run_is_not_skipped_by_semantic_audit(tmp_path: Path) -> None:
    row = _frc_point_row()
    _write_rows(tmp_path / "reports/csv/frc_reference_points.csv", [row])
    audit = audit_run(tmp_path)
    assert audit["summary"][0]["semantic_check_count"] >= 4
    assert audit["summary"][0]["semantic_required_failure_count"] == 0
    assert all(check["passed"] for check in audit["canonical_csv_semantic_audit"])
    assert all(
        check["category"] == "frc_reference"
        for check in audit["canonical_csv_semantic_audit"]
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


def test_runtime_antenna_rows_require_resolved_antenna_configuration(
    tmp_path: Path,
) -> None:
    _write_rows(
        tmp_path / "reports/csv/antenna_runtime_evidence.csv",
        [{"Direction": "DL", "UEIndex": "1"}],
    )
    resolved = tmp_path / "reports/csv/antenna_config_resolved.csv"
    resolved.parent.mkdir(parents=True, exist_ok=True)
    resolved.write_text("NodeType,NodeIndex,NumElements\n", encoding="utf-8")

    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "fixed", "ConfigHash": "a" * 64},
    )
    check = next(
        item for item in checks
        if item.artifact_path == "reports/csv/antenna_config_resolved.csv"
        and item.check_id == "schema_and_runtime_rows"
    )
    assert check.required and check.evaluated and not check.passed
    assert "missing_runtime_rows" in check.details


def test_failed_truth_contract_cannot_publish_empty_issue_registries(
    tmp_path: Path,
) -> None:
    _write_rows(
        tmp_path / "reports/csv/truth_contract_failures.csv",
        [{"FailureCode": "missing_runtime_rows", "Reason": "evidence absent"}],
    )
    for name in ("active_issue_gate_summary.csv", "result_issue_registry.csv"):
        path = tmp_path / "reports/csv" / name
        path.write_text("IssueCode,Reason\n", encoding="utf-8")

    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "failed", "ConfigHash": "a" * 64},
    )
    failed = {
        item.artifact_path: item
        for item in checks
        if item.check_id == "schema_and_runtime_rows" and not item.passed
    }
    assert "reports/csv/active_issue_gate_summary.csv" in failed
    assert "reports/csv/result_issue_registry.csv" in failed


def test_evaluated_empty_issue_registries_are_valid_with_canonical_receipts(
    tmp_path: Path,
) -> None:
    run_id = "evaluated-empty-run"
    config_hash = "a" * 64
    _write_rows(
        tmp_path / "reports/csv/truth_contract_failures.csv",
        [{"FailureCode": "visual_artifact_integrity", "Reason": "terminal visual gate"}],
    )
    for name in ("active_issue_gate_summary.csv", "result_issue_registry.csv"):
        path = tmp_path / "reports/csv" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("IssueCode,Reason\n", encoding="utf-8")
    _write_rows(
        tmp_path / "reports/csv/result_issue_registry_evaluation.csv",
        [{
            "RunId": run_id,
            "ScenarioId": "fixed",
            "ConfigHash": config_hash,
            "EvaluationStatus": "EVALUATED",
            "IssueRowCount": "0",
            "SourceTableCount": "11",
            "RuntimeSourceRowCount": "240",
            "Evaluator": "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildResultIssueRegistry",
            "SchemaVersion": "result_issue_registry_evaluation_v1",
            "EvaluatedSources": "DLTrials|ULTrials",
        }],
    )
    active_summary = {
        "RunId": run_id,
        "ActiveIssueGateOk": True,
        "ActiveCriticalIssueCount": 0,
        "ActiveHighIssueCount": 0,
        "ActiveMediumIssueCount": 0,
        "ActiveMandatoryIssueCount": 0,
        "IssueRegistryStatus": "PASS",
        "IssueRegistryRowCount": 0,
        "IssueRegistryEvaluationValid": True,
        "IssueRegistryEvaluationAudit": {
            "ObservedRunId": run_id,
            "ObservedConfigHash": config_hash,
            "ObservedIssueRowCount": 0,
            "EvaluationStatus": "EVALUATED",
        },
    }
    summary_path = tmp_path / "reports/json/active_issue_gate_summary.json"
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(json.dumps(active_summary), encoding="utf-8")

    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "fixed", "ConfigHash": config_hash},
    )
    by_path = {
        item.artifact_path: item
        for item in checks
        if item.check_id == "schema_and_runtime_rows"
    }
    assert by_path["reports/csv/active_issue_gate_summary.csv"].passed
    assert by_path["reports/csv/result_issue_registry.csv"].passed


def test_live_scenario_overview_requires_populated_radio_runtime_fields(
    tmp_path: Path,
) -> None:
    _write_rows(
        tmp_path / "reports/csv/live_scenario_overview.csv",
        [{
            "run_id": "run-1", "scenario_id": "scenario", "center_frequency_hz": "",
            "bandwidth_hz": "", "scs_khz": "", "n_rb": "", "duplex_mode": "",
            "num_frames": "", "total_slots": "", "strict_mode": "",
            "honesty_mode": "",
        }],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "scenario", "ConfigHash": "a" * 64},
    )
    value_check = next(
        item for item in checks
        if item.artifact_path == "reports/csv/live_scenario_overview.csv"
        and item.check_id == "populated_physical_value_ranges"
    )
    assert not value_check.passed
    assert "center_frequency_hz_missing_or_nonpositive" in value_check.details
    assert "duplex_mode_missing" in value_check.details


def test_live_scenario_overview_accepts_strict_text_honesty_mode(
    tmp_path: Path,
) -> None:
    _write_rows(
        tmp_path / "reports/csv/live_scenario_overview.csv",
        [{
            "run_id": "run-1", "scenario_id": "scenario",
            "center_frequency_hz": "4000000000", "bandwidth_hz": "100000000",
            "scs_khz": "30", "n_rb": "273", "duplex_mode": "TDD",
            "num_frames": "2", "total_slots": "40", "strict_mode": "true",
            "honesty_mode": "strict",
        }],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "scenario", "ConfigHash": "a" * 64},
    )
    value_check = next(
        item for item in checks
        if item.artifact_path == "reports/csv/live_scenario_overview.csv"
        and item.check_id == "populated_physical_value_ranges"
    )
    assert value_check.passed, value_check.details


def test_enabled_prach_correlation_rejects_unavailable_nan_row(
    tmp_path: Path,
) -> None:
    config = tmp_path / "meta/scenario_config_resolved.json"
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text(
        json.dumps({"control_gating": {"prach_required": True}}),
        encoding="utf-8",
    )
    _write_rows(
        tmp_path / "reports/csv/prach_correlation_trace.csv",
        [{
            "lag_samples": "NaN", "correlation_abs": "NaN",
            "truth_status": "not_available",
        }],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "scenario", "ConfigHash": "a" * 64},
    )
    failed = {
        item.check_id: item.details for item in checks
        if item.artifact_path == "reports/csv/prach_correlation_trace.csv"
        and not item.passed
    }
    assert "lag_samples_missing" in failed["populated_physical_value_ranges"]
    assert "truth_status_not_real_lls_evidence" in failed["in_path_truth_proxy_separation"]


def test_fixed_link_only_audit_uses_declared_campaign_trial_tables(tmp_path: Path) -> None:
    resolved = {
        "sweeps_and_matrix": {"fixed_link_calibration": {"only": True}},
    }
    config_path = tmp_path / "meta/scenario_config_resolved.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(resolved), encoding="utf-8")
    _write_rows(
        tmp_path / "reports/csv/scenario_summary.csv",
        [{
            "ScenarioID": "fixed",
            "ConfigHash": "a" * 64,
            "EffectiveDLTrialCount": "1",
            "EffectiveULTrialCount": "1",
        }],
    )
    for direction, name in (("DL", "dl"), ("UL", "ul")):
        _write_rows(
            tmp_path / f"air_interface/csv/{name}_fixed_link_campaign_trials.csv",
            [{"Direction": direction, "FixedLinkCampaign": "1"}],
        )

    audit = audit_run(tmp_path)
    paths = {
        row["artifact_path"]
        for row in audit["canonical_csv_semantic_audit"]
        if row["category"] == "primary_link"
    }
    assert "air_interface/csv/dl_fixed_link_campaign_trials.csv" in paths
    assert "air_interface/csv/ul_fixed_link_campaign_trials.csv" in paths
    assert "air_interface/csv/dl_pdsch_trials.csv" not in paths
    assert "air_interface/csv/ul_pusch_trials.csv" not in paths


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
