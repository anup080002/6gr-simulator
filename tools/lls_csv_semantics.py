#!/usr/bin/env python3
"""Semantic and cross-table audit for one finalized LLS result tree.

The generic exhaustive inventory checks that every CSV can be parsed.  This
module checks the values that make the primary PHY tables scientific evidence:
identity, exact scheduled/transmitted operating point, transport-block
arithmetic, CRC/BER/goodput consistency, measured SINR/noise lineage and
truth/proxy separation.  It also verifies every materialized chart against the
exact chart-data CSV and byte hashes recorded by contract_plot_lineage.csv.

No configured value is substituted for a missing runtime measurement here.
Missing required evidence is a failed check.
"""

from __future__ import annotations

import csv
import hashlib
import json
import math
import os
import statistics
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
from lls_applied_beam import validate_samples as validate_applied_beam_samples

from lls_beam_summary_audit import reconcile_beam_summary
from lls_continuous_iq_audit import validate_capture as validate_continuous_iq_capture
from lls_continuous_iq_audit import MANIFEST as CONTINUOUS_IQ_MANIFEST, SEGMENTS as CONTINUOUS_IQ_SEGMENTS


PRIMARY_LINK_TABLES = {
    "DL": "air_interface/csv/dl_pdsch_trials.csv",
    "UL": "air_interface/csv/ul_pusch_trials.csv",
}
FIXED_LINK_PRIMARY_TABLES = {
    "DL": "air_interface/csv/dl_fixed_link_campaign_trials.csv",
    "UL": "air_interface/csv/ul_fixed_link_campaign_trials.csv",
}
RUNTIME_CALL_LEDGER = "reports/csv/runtime_call_ledger.csv"
RUNTIME_LEDGER_REQUIRED_COLUMNS = (
    "Sequence",
    "TimestampUTC",
    "FunctionName",
    "Component",
    "Direction",
    "Event",
    "RunId",
    "ExecutionID",
    "ConfigHash",
    "ContextSHA256",
    "EvidenceClass",
    "ApproximationMode",
)
CONTROL_TABLES = (
    "air_interface/csv/pbch_trials.csv",
    "air_interface/csv/prach_trials.csv",
    "air_interface/csv/pdcch_trials.csv",
    "air_interface/csv/pucch_trials.csv",
    "air_interface/csv/csi_rs_trials.csv",
    "air_interface/csv/srs_trials.csv",
    "air_interface/csv/trs_trials.csv",
)
COMPONENT_ONLY_RUNNER_PROFILES = {
    "prach_detection",
    "prach_strict_validation",
    "pdcch_blind_decode_sweep",
    "pdcch_strict_validation",
    "ctrl6gr_pdcch_study",
    "srs_strict_validation",
    "trs_strict_validation",
    "channel_rf_strict_validation",
    "random_access_four_step",
    "ai_benchmark",
    # A generic sweep is an orchestration run.  Exact child evidence is
    # indexed below sweeps/* and parent aggregate tables are measured
    # reductions; it must never be required to invent parent waveform rows.
    "generic_sweep",
}
DERIVED_LINK_TABLES = (
    "air_interface/csv/distance_vs_sinr.csv",
    "air_interface/csv/dl_measured_sinr_bler_curve.csv",
    "air_interface/csv/ul_measured_sinr_bler_curve.csv",
    "air_interface/csv/dl_measured_sinr_throughput_curve.csv",
    "air_interface/csv/ul_measured_sinr_throughput_curve.csv",
    "air_interface/csv/fer_summary.csv",
    "air_interface/csv/live_measured_sinr_summary.csv",
    "air_interface/csv/lls_measured_sinr_summary.csv",
    "air_interface/csv/lls_kpi_summary.csv",
    "air_interface/csv/lls_snr_sweep.csv",
    "air_interface/csv/measured_sinr_distribution.csv",
    "air_interface/csv/multiuser_user_summary.csv",
    "air_interface/csv/papr_ccdf.csv",
)
MANIFEST_TABLES = (
    "artifact_generation/artifact_generation_results.csv",
    "artifact_generation/artifact_generation_summary.csv",
    "reports/csv/component_artifact_publication_manifest.csv",
    "reports/csv/component_artifact_publication_summary.csv",
    "raw/evidence/raw_evidence_index.csv",
)
ARTIFACT_GENERATION_PNG_SOURCES = {
    "prach_preamble_correlation.png": "prach/csv/prach_detection_trials.csv",
    "pdsch_bler_vs_snr.png": "pdsch/csv/pdsch_bler_curve.csv",
    "pusch_bler_vs_snr.png": "pusch/csv/pusch_bler_curve.csv",
}
COMPONENT_BLER_TABLES = {
    "DL": "components/pdsch/csv/pdsch_bler_curve.csv",
    "UL": "components/pusch/csv/pusch_bler_curve.csv",
}
MIMO_RANK_LAYER_TABLE = "beamforming/csv/rank_layer_trials.csv"
MIMO_COMPANION_TABLES = (
    "beamforming/csv/antenna_array_config.csv",
    "beamforming/csv/antenna_port_mapping.csv",
    "beamforming/csv/beam_codebook.csv",
    "beamforming/csv/beam_precoder_table.csv",
    "beamforming/csv/beam_sweep_measurements.csv",
    "beamforming/csv/beamforming_analytics_table.csv",
    "beamforming/csv/mimo_config_strict.csv",
    "beamforming/csv/mimo_config_validation.csv",
    "beamforming/csv/mimo_configured_vs_effective.csv",
    "beamforming/csv/mimo_layer_metrics.csv",
    "beamforming/csv/mimo_oracle_guard.csv",
    "beamforming/csv/mimo_rank_utilization_table.csv",
    "beamforming/csv/precoder_evidence.csv",
    "beamforming/csv/rank_layer_usage_histogram.csv",
)
HARQ_OBSERVATION_TIMELINE = "harq/csv/live_harq_observation_timeline.csv"
HARQ_OBSERVATION_SUMMARY = "harq/csv/live_harq_observation_summary.csv"
DL_PROTOCOL_DECISIONS = "harq/csv/received_dl_protocol_decisions.csv"
KPI_DELIVERY_TABLES = {
    "DL": {
        "trace": "reports/csv/kpi_harq_delivery_trace_dl.csv",
        "ledger": "reports/csv/kpi_tb_delivery_ledger_dl.csv",
        "contributions": "reports/csv/kpi_row_contributions_dl.csv",
    },
    "UL": {
        "trace": "reports/csv/kpi_harq_delivery_trace_ul.csv",
        "ledger": "reports/csv/kpi_tb_delivery_ledger_ul.csv",
        "contributions": "reports/csv/kpi_row_contributions_ul.csv",
    },
}
METRIC_OUTPUT_TABLES = (
    "reports/csv/aggregated_reporting_outputs.csv",
    "reports/csv/ai_ml_outputs.csv",
    "reports/csv/basic_phy_performance_outputs.csv",
    "reports/csv/channel_estimation_tracking_outputs.csv",
    "reports/csv/coding_decoder_outputs.csv",
    "reports/csv/complexity_implementation_outputs.csv",
    "reports/csv/csi_outputs.csv",
    "reports/csv/beam_management_outputs.csv",
    "reports/csv/debug_trace_outputs.csv",
    "reports/csv/energy_efficiency_outputs.csv",
    "reports/csv/harq_outputs.csv",
    "reports/csv/initial_access_random_access_outputs.csv",
    "reports/csv/lls_output_metric_rows.csv",
    "reports/csv/modulation_shaping_outputs.csv",
    "reports/csv/pdcch_control_outputs.csv",
    "reports/csv/pdsch_outputs.csv",
    "reports/csv/pusch_pucch_outputs.csv",
    "reports/csv/run_metadata_outputs.csv",
)
METRIC_COVERAGE_TABLE = "reports/csv/lls_output_spec_coverage.csv"
METRIC_COVERAGE_REQUIRED_COLUMNS = {
    "CategoryCode", "CategoryKey", "CategoryName", "MetricKey", "MetricName",
    "Availability", "CountsTowardCoverage", "CoveredRowCount",
    "ObservedRowCount", "DerivedRowCount", "ConfigOnlyRowCount",
    "DisabledRowCount", "PlaceholderRowCount", "NotSupportedRowCount",
    "NotAvailableRowCount", "NotExercisedRowCount", "SourceArtifacts", "Notes",
}
METRIC_OUTPUT_REQUIRED_COLUMNS = {
    "CategoryCode",
    "CategoryKey",
    "CategoryName",
    "MetricKey",
    "MetricName",
    "Entity",
    "Statistic",
    "Availability",
    "CountsTowardCoverage",
    "ValueNumeric",
    "ValueText",
    "Unit",
    "SourceArtifact",
    "Notes",
}
METRIC_OUTPUT_AVAILABILITY = {
    "observed",
    "derived",
    "config_only",
    "disabled",
    "not_available",
    "not_supported",
}
DOMAIN_RUNTIME_PREFIXES = (
    "air_interface/csv/",
    "analytics/csv/",
    "beamforming/csv/",
    "channel/csv/",
    "component_anchors/channel_rf/",
    "component_anchors/protocol/protocol_stack/csv/",
    "configuration/csv/",
    "control/csv/",
    "geometry/csv/",
    "harq/csv/",
    "interference/csv/",
    "meta/",
    "mobility/csv/",
    "packet_flow/csv/",
    "rf/csv/",
    "reports/csv/",
    "reports/final/",
    "runtime/csv/",
    "storage/csv/",
    # Live WebGUI tables are persisted derived/runtime surfaces, not exempt
    # presentation data.  Audit their populated values and truth labels with
    # the same baseline contract before they can source a chart.
    "reports/csv/live_",
)
DOMAIN_RUNTIME_EXACT = {
    "air_interface/reports/csv/live_stage_status.csv",
    "components/contract_plot_lineage.csv",
    "components/prach/csv/prach_detection_trials.csv",
    "frame_grid/csv/observed_re_allocation.csv",
    "reports/csv/channel_snapshots.csv",
    "reports/csv/doppler_reconciliation.csv",
    "reports/csv/live_dl_scheduler_grants.csv",
    "reports/csv/live_ul_scheduler_grants.csv",
    "reports/csv/mimo_rank_utilization_table.csv",
    "reports/csv/pdcch_dci_table.csv",
    "reports/csv/runtime_config_application_evidence.csv",
    "reports/csv/trajectory_geometry.csv",
    "reports/csv/trs_receiver_tracking_table.csv",
    "validation/csv/contract_plot_lineage.csv",
    "waveform/csv/final_tx_iq_capture_manifest.csv",
    "waveform/csv/final_tx_iq_dl.csv",
    "waveform/csv/final_tx_iq_ul.csv",
    "reports/csv/all_csv_artifact_audit.csv",
    "reports/csv/all_image_artifact_audit.csv",
    "reports/csv/artifact_issue_registry.csv",
    "reports/csv/visual_artifact_audit.csv",
    "reports/csv/visual_artifact_integrity.csv",
    "reports/csv/contract_materialization_coverage.csv",
    "reports/csv/contract_materialization_manifest.csv",
    "reports/csv/public_output_claim_scan.csv",
    "reports/csv/reports_all_artifacts_v.csv",
    "reports/csv/reports_all_enums_v.csv",
    "reports/csv/reports_all_scalars_v.csv",
    "reports/csv/reports_all_stage_exec_v.csv",
    "reports/csv/reports_config_vs_measured_conflicts_v.csv",
    "reports/csv/reports_partial_or_missing_v.csv",
    "reports/csv/reports_stage_lineage_v.csv",
    "reports/csv/reports_status_rollup_explanations_v.csv",
    "reports/csv/reports_truth_violations_v.csv",
    "reports/csv/reports_value_semantics_coverage_v.csv",
    "reports/csv/standards_claim_audit.csv",
    # Zero-row component surfaces need an explicit applicability contract.
    # Merely creating a header is not runtime evidence and must not disappear
    # from the semantic audit just because the table lives outside a broadly
    # audited component directory.
    "beamforming/csv/mimo_negative_trials.csv",
    "geometry/csv/serving_cell_assignment.csv",
    "mobility/csv/channel_continuity_reconciliation.csv",
    "mobility/csv/doppler_reconciliation.csv",
    "mobility/csv/inter_ue_distance_validation.csv",
    "mobility/csv/pathloss_reconciliation.csv",
    "mobility/csv/propagation_delay_reconciliation.csv",
    "mobility/csv/trajectory_constraint_conflicts.csv",
    "reports/csv/active_issue_gate_summary.csv",
    "reports/csv/access_state_timeline.csv",
    "reports/csv/access_transition_ledger.csv",
    "reports/csv/antenna_config_resolved.csv",
    "reports/csv/beam_management_outputs.csv",
    "reports/csv/channel_impulse_response.csv",
    "reports/csv/channel_rf_cdlc_realization_table.csv",
    "component_anchors/channel_rf/reports/csv/channel_rf_cdlc_realization_table.csv",
    "reports/csv/dl_pdsch_objective_failures.csv",
    "reports/csv/equalized_constellations.csv",
    "reports/csv/pdcch_grant_binding_evidence.csv",
    "reports/csv/prach_correlation_trace.csv",
    "reports/csv/prach_correlation_traces.csv",
    "reports/csv/raster_replacement_inventory.csv",
    "reports/csv/result_issue_registry.csv",
    "reports/csv/truth_contract_failures.csv",
    "reports/csv/unavailable_plot_card_registry.csv",
}
IDENTITY_COLUMNS = (
    "RunID",
    "RunTag",
    "ScenarioID",
    "ConfigHash",
    "ExecutionID",
)
LOCAL_CONFIG_HASH_TABLES = {
    # These rows bind a direction-specific normalized MIMO configuration,
    # not the complete scenario. Dedicated MIMO auditors reconcile this hash
    # to validation and configured/effective evidence for each direction.
    "beamforming/csv/mimo_config_strict.csv",
    "beamforming/csv/mimo_config_validation.csv",
    # This is the normalized channel/RF sub-configuration hash.  It is
    # intentionally narrower than the complete scenario hash and is
    # reconciled by the dedicated channel/RF configuration audit.
    "component_anchors/channel_rf/channel/csv/channel_rf_config_strict.csv",
}
LINK_REQUIRED_COLUMNS = (
    "Direction",
    "Frame",
    "Slot",
    "UEID",
    "MCSIndex",
    "Modulation",
    "TargetCodeRate",
    "TBSize_bits",
    "Layers",
    "Rank",
    "EffectiveMCSIndex",
    "EffectiveModulation",
    "EffectiveLayers",
    "EffectiveRank",
    "ScheduledMCSIndex",
    "ScheduledModulation",
    "ScheduledOperatingPointMatchesTransmitted",
    "CRCPass",
    "BitErrors",
    "BitsCompared",
    "RawBER",
    "OfferedBits",
    "GoodBits",
    "OfferedThroughput_Mbps",
    "Goodput_Mbps",
    "AirInterfaceObservation_ms",
    "NoiseVariance",
    "PostEqualizationNoiseVariance",
    "LLRNoiseVariance",
    "PostEqSINR_dB",
    "PostEqSINRSource",
    "MeasuredTrialSINR_dB",
    "MeasuredTrialSINRSource",
    "EVM_rms",
    "EVMProxySINR_dB",
    "RuntimeChannelStateKey",
    "RuntimeChannelLinkKey",
    "RuntimeChannelSeed",
    "RuntimeChannelReciprocityExact",
    "RuntimeChannelReciprocityDirection",
    "RuntimeChannelReciprocitySource",
    "RuntimeChannelReciprocityApproximationMode",
    "RuntimeChannelTransmitAndReceiveSwapped",
    "RuntimeChannelAngleEvidenceAvailable",
    "RuntimeChannelAngleEvidenceSource",
    "RuntimeChannelAnglePathCount",
    "RuntimeChannelCanonicalInputSamples",
    "RuntimeChannelAlignmentLookaheadSamples",
    "RuntimeChannelAlignmentLookaheadExecutedOnFork",
    "RuntimeChannelObjectClockExact",
    "RuntimeChannelPathGainsSHA256",
    "StrictReceiverEvidenceOk",
    "StrictOk",
    "TruthStatus",
    "ExecutionBackend",
    "ApproximationMode",
    "FallbackFlag",
    "PlaceholderFlag",
    "FinalizedFlag",
) + IDENTITY_COLUMNS

MODULATION_QM = {
    "BPSK": 1,
    "PI/2-BPSK": 1,
    "QPSK": 2,
    "16QAM": 4,
    "64QAM": 6,
    "256QAM": 8,
    "1024QAM": 10,
    "4096QAM": 12,
}

BAD_TRUTH_TOKENS = ("proxy", "synthetic", "fallback", "placeholder", "logistic", "lut")
GENERIC_AXIS_LABELS = {"", "x", "y", "value", "metric", "not_available", "n/a", "na"}
FRC_POINT_TABLE = "reports/csv/frc_reference_points.csv"
FRC_SUMMARY_TABLES = (
    "reports/csv/frc_reference_qualification.csv",
    "reports/csv/frc_reference_diagnostic.csv",
    "reports/csv/frc_reference_qualification.partial.csv",
)
FRC_PLOT_LINEAGE = "reports/csv/frc_reference_plot_lineage.csv"

# These persisted reducers feed Phase-7 and production qualification.  Each
# file has an explicit outcome field; the semantic auditor must reconcile the
# field with the final Phase-7 row instead of treating a parsed CSV as proof.
RECONCILIATION_PHASE7_FLAGS = {
    "reports/csv/access_kpi_reconciliation.csv": "AccessKpiReconciliationOk",
    "reports/csv/antenna_array_reconciliation.csv": "AntennaArrayReconciliationOk",
    "reports/csv/artifact_completeness_summary.csv": "ArtifactCompletenessOk",
    "reports/csv/blerber_reconciliation.csv": "BlerBerReconciliationOk",
    "reports/csv/cfo_reconciliation.csv": "CfoConfiguredAppliedOk",
    "reports/csv/channel_realization_reconciliation.csv": (
        "ChannelRealizationOk", "CdlRealizationOk"
    ),
    "reports/csv/channel_rf_reconciliation.csv": "ChannelRfConfiguredVsAppliedOk",
    "reports/csv/checkpoint_resume_equivalence.csv": "CheckpointResumeEquivalenceOk",
    "reports/csv/energy_model_gate.csv": "EnergyModelOk",
    "reports/csv/evm_reconciliation.csv": "EvmReconciliationOk",
    "reports/csv/final_scientific_claims_truthfulness.csv": "FinalScientificClaimsTruthfulOk",
    "reports/csv/interference_accounting.csv": "InterferenceAccountingOk",
    "reports/csv/iq_imbalance_reconciliation.csv": "IqImbalanceConfiguredAppliedOk",
    "reports/csv/latency_reconciliation.csv": "LatencyReconciliationOk",
    "reports/csv/long_run_stability_summary.csv": "LongRunStabilityOk",
    "reports/csv/mimo_kpi_reconciliation.csv": "MimoKpiReconciliationOk",
    "reports/csv/mobility_kpi_reconciliation.csv": "MobilityKpiReconciliationOk",
    "reports/csv/noise_reconciliation.csv": "NoiseReconciliationOk",
    "reports/csv/pa_reconciliation.csv": "PaConfiguredAppliedOk",
    "reports/csv/papr_reconciliation.csv": "PaprReconciliationOk",
    "reports/csv/path_power_normalization_reconciliation.csv": "PathPowerNormalizationOk",
    "reports/csv/performance_profile_summary.csv": "PerformanceProfileOk",
    "reports/csv/phase_noise_reconciliation.csv": "PhaseNoiseConfiguredAppliedOk",
    "reports/csv/plot_data_lineage_summary.csv": "PlotDataLineageOk",
    "reports/csv/polarization_reconciliation.csv": "PolarizationReconciliationOk",
    "reports/csv/rf_chain_definition.csv": "RfChainDefinitionOk",
    "reports/csv/scheduler_kpi_reconciliation.csv": "SchedulerKpiReconciliationOk",
    "reports/csv/serial_parallel_determinism.csv": "SerialParallelDeterminismOk",
    "reports/csv/throughput_reconciliation.csv": "ThroughputReconciliationOk",
    "reports/csv/timing_offset_reconciliation.csv": "TimingOffsetConfiguredAppliedOk",
}

PHASE7_PHASE_MEMBERS = {
    "Phase1Ok": (
        "GeometryValidationOk", "FullTrajectoryExecutedOk",
        "MobilityStateContinuousOk", "InterUeConstraintResolvedOk",
        "LosStateModelOk", "PathlossReconciliationOk",
        "ShadowFadingReconciliationOk", "LargeScaleParameterReconciliationOk",
        "CdlRealizationOk", "ChannelStateContinuityOk",
        "PathPowerNormalizationOk", "DopplerReconciliationOk",
        "PropagationDelayReconciliationOk", "AntennaArrayReconciliationOk",
        "PolarizationReconciliationOk",
    ),
    "Phase2Ok": (
        "ResolvedConfigurationConsistentOk", "NoiseReconciliationOk",
        "InterferenceAccountingOk", "RfChainDefinitionOk",
        "CfoConfiguredAppliedOk", "PhaseNoiseConfiguredAppliedOk",
        "TimingOffsetConfiguredAppliedOk", "IqImbalanceConfiguredAppliedOk",
        "PaConfiguredAppliedOk", "EvmReconciliationOk", "PaprReconciliationOk",
        "ChannelRfConfiguredVsAppliedOk", "MimoKpiReconciliationOk",
        "SchedulerKpiReconciliationOk", "MobilityKpiReconciliationOk",
    ),
    "Phase3Ok": (
        "ArtifactCompletenessOk", "PlotDataLineageOk", "Phase7NoFabricationOk",
    ),
    "Phase4Ok": (
        "CanonicalKpiLedgerOk", "ThroughputReconciliationOk",
        "BlerBerReconciliationOk", "LatencyReconciliationOk",
        "AccessKpiReconciliationOk", "SchedulerKpiReconciliationOk",
    ),
    "Phase5Ok": (
        "SeedHierarchyOk", "CampaignDesignOk", "CampaignCompletionOk",
        "MultiSeedDropStatisticsOk", "ConfidenceIntervalsOk",
        "SampleAdequacyOk", "SweepDataQualityOk",
        "CheckpointResumeEquivalenceOk", "SerialParallelDeterminismOk",
    ),
    "Phase6Ok": (
        "EnergyModelOk", "PerformanceProfileOk", "LongRunStabilityOk",
    ),
}

PHASE7_GATE_NAMES = (
    "ResolvedConfigurationConsistentOk", "CapturePolicyTruthfulOk",
    "GeometryValidationOk", "FullTrajectoryExecutedOk",
    "MobilityStateContinuousOk", "InterUeConstraintResolvedOk",
    "LosStateModelOk", "PathlossReconciliationOk",
    "ShadowFadingReconciliationOk", "LargeScaleParameterReconciliationOk",
    "CdlRealizationOk", "ChannelStateContinuityOk",
    "PathPowerNormalizationOk", "DopplerReconciliationOk",
    "PropagationDelayReconciliationOk", "AntennaArrayReconciliationOk",
    "PolarizationReconciliationOk", "NoiseReconciliationOk",
    "InterferenceAccountingOk", "RfChainDefinitionOk",
    "CfoConfiguredAppliedOk", "PhaseNoiseConfiguredAppliedOk",
    "TimingOffsetConfiguredAppliedOk", "IqImbalanceConfiguredAppliedOk",
    "PaConfiguredAppliedOk", "EvmReconciliationOk", "PaprReconciliationOk",
    "ChannelRfConfiguredVsAppliedOk", "CheckpointResumeEquivalenceOk",
    "SeedHierarchyOk", "CampaignDesignOk", "CampaignCompletionOk",
    "MultiSeedDropStatisticsOk", "CanonicalKpiLedgerOk",
    "ThroughputReconciliationOk", "BlerBerReconciliationOk",
    "LatencyReconciliationOk", "AccessKpiReconciliationOk",
    "SchedulerKpiReconciliationOk", "MobilityKpiReconciliationOk",
    "MimoKpiReconciliationOk", "EnergyModelOk", "ConfidenceIntervalsOk",
    "SampleAdequacyOk", "SweepDataQualityOk",
    "SerialParallelDeterminismOk", "PerformanceProfileOk",
    "LongRunStabilityOk", "OutputSchemaValidationOk",
    "ArtifactCompletenessOk", "PlotDataLineageOk", "Phase7NoFabricationOk",
    "Phase7ProvenanceOk", "TwoModeAcceptanceGatesOk",
    "FinalScientificClaimsTruthfulOk",
)

PRODUCTION_GATE_ORDER = (
    "FunctionalRun", "ScenarioObjective", "RuntimeWiringCoverage",
    "Phase7NumericalValidation", "StatisticalQualification",
    "IndependentFRCQualification", "IndependentReferenceComparison",
    "TerminalPublicationEvidence", "ProductionGrade",
)

MEASUREMENT_SIDECAR_MANIFEST = "reports/csv/measurement_sidecar_manifest.csv"
CANONICAL_COMPONENT_MANIFEST = "artifact_generation/canonical_component_manifest.csv"
CONTRACT_CATALOG_SNAPSHOT = "artifact_generation/contract_catalog_snapshot.csv"
DUT_REFERENCE_DETAIL = "reports/csv/dut_reference_comparison.csv"
DUT_REFERENCE_SUMMARY = "reports/csv/lls_reference_comparison_summary.csv"


@dataclass
class AuditCheck:
    category: str
    artifact_path: str
    check_id: str
    required: bool
    evaluated: bool
    passed: bool
    row_count: int
    failure_count: int
    details: str


def _io_path(path: Path) -> Path:
    resolved = path.resolve()
    if os.name != "nt":
        return resolved
    text = str(resolved)
    if text.startswith("\\\\?\\"):
        return resolved
    if text.startswith("\\\\"):
        return Path("\\\\?\\UNC\\" + text[2:])
    return Path("\\\\?\\" + text)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with _io_path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _png_semantics(path: Path) -> str:
    try:
        from PIL import Image

        with Image.open(_io_path(path)) as image:
            image.load()
            return str(image.info.get("sixgr_visual_semantics") or "").strip()
    except (OSError, ImportError):
        return ""


def _png_dimensions(path: Path) -> tuple[int, int] | None:
    try:
        from PIL import Image

        with Image.open(_io_path(path)) as image:
            image.load()
            if image.format != "PNG":
                return None
            return image.width, image.height
    except (OSError, ImportError):
        return None


def _run_relative_path(run_root: Path, value: str) -> Path | None:
    relative = Path(str(value or "").strip().replace("\\", "/"))
    if not str(relative) or relative.is_absolute():
        return None
    candidate = (run_root / relative).resolve()
    try:
        candidate.relative_to(run_root.resolve())
    except ValueError:
        return None
    return candidate


def _read_rows(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    source = _io_path(path)
    if not source.is_file():
        return [], []
    previous = csv.field_size_limit()
    try:
        csv.field_size_limit(max(previous, int(source.stat().st_size) + 1))
        with source.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            header = list(reader.fieldnames or [])
            rows = [
                {str(key): "" if value is None else str(value).strip() for key, value in row.items()}
                for row in reader
            ]
        return header, rows
    finally:
        csv.field_size_limit(previous)


def _find_named_files(root: Path, filename: str) -> list[Path]:
    """Recursively find files without losing Windows extended-length paths."""

    if not _io_path(root).is_dir():
        return []
    io_root = _io_path(root)
    results: list[Path] = []
    for directory, _, files in os.walk(str(io_root)):
        if filename not in files:
            continue
        relative = os.path.relpath(
            os.path.join(directory, filename), str(io_root)
        )
        results.append(root / Path(relative))
    return sorted(results, key=lambda value: value.as_posix().lower())


def _text(row: dict[str, str], *names: str) -> str:
    for name in names:
        value = str(row.get(name, "")).strip()
        if value and value.lower() not in {"nan", "+nan", "-nan", "<missing>", "null"}:
            return value
    return ""


def _number(row: dict[str, str], *names: str) -> float | None:
    # Numeric aliases are ordered candidates, not text aliases.  A common
    # canonical schema carries both UEID="UE1" and UEIndex=1; stopping at the
    # first non-empty string incorrectly discards the usable numeric alias.
    for name in names:
        text = _text(row, name)
        if not text:
            continue
        try:
            value = float(text)
        except (TypeError, ValueError):
            continue
        if math.isfinite(value):
            return value
    return None


def _boolean(row: dict[str, str], *names: str) -> bool | None:
    value = _text(row, *names).lower()
    if value in {"1", "true", "yes", "pass", "passed", "ok"}:
        return True
    if value in {"0", "false", "no", "fail", "failed"}:
        return False
    return None


def _beam_index_set(row: dict[str, str], *names: str) -> str:
    value = _text(row, *names)
    normalized = value.lower()
    if (
        not value
        or normalized in {"none", "unavailable", "not_available"}
        or normalized.startswith((
            "not_recorded_by_active_", "not_emitted_by_active_",
            "field_not_emitted_by_active_",
        ))
    ):
        return "not_selected"
    return value


def _close(actual: float | None, expected: float | None, *, atol: float, rtol: float = 1e-9) -> bool:
    return (
        actual is not None
        and expected is not None
        and math.isclose(actual, expected, abs_tol=atol, rel_tol=rtol)
    )


def _check(
    category: str,
    artifact_path: str,
    check_id: str,
    rows: list[dict[str, str]],
    failures: Iterable[str],
    *,
    required: bool = True,
    evaluated: bool = True,
) -> AuditCheck:
    failure_list = list(failures)
    return AuditCheck(
        category=category,
        artifact_path=artifact_path,
        check_id=check_id,
        required=required,
        evaluated=evaluated,
        passed=evaluated and not failure_list,
        row_count=len(rows),
        failure_count=len(failure_list),
        details=" | ".join(failure_list[:24]),
    )


def _expected_link_count(summary: dict[str, str], direction: str) -> int:
    field = "EffectiveDLTrialCount" if direction == "DL" else "EffectiveULTrialCount"
    value = _number(summary, field)
    return int(value) if value is not None and value >= 0 else 0


def _audit_large_scale_power_table(
    path: str, rows: list[dict[str, str]],
) -> list[AuditCheck]:
    """Expected loss is never evidence of a measured waveform power change."""
    failures: list[str] = []
    for index, row in enumerate(rows, start=1):
        before = _number(row, "WaveformPowerBeforeDb")
        after = _number(row, "WaveformPowerAfterDb")
        measured = _number(row, "MeasuredDeltaDb")
        expected = _number(row, "ExpectedDeltaDb")
        tolerance = _number(row, "ToleranceDb")
        if any(value is None for value in (before, after, measured, expected, tolerance)):
            failures.append(f"row={index}:independent_waveform_power_measurement_missing")
            continue
        if not _close(measured, before - after, atol=1e-9):
            failures.append(f"row={index}:measured_delta_not_input_minus_output_power")
        if tolerance < 0 or abs(measured - expected) > tolerance + 1e-9:
            failures.append(f"row={index}:measured_power_does_not_close_against_expected_net_gain")
    return [_check(
        "channel_power", path, "independent_gain_stage_power_closure", rows, failures,
        required=bool(rows), evaluated=bool(rows),
    )]


def _audit_identity(path: str, rows: list[dict[str, str]]) -> list[AuditCheck]:
    checks: list[AuditCheck] = []
    failures: list[str] = []
    for index, row in enumerate(rows, start=1):
        missing = [
            name
            for name in IDENTITY_COLUMNS
            if not (
                _text(row, "ScenarioConfigHash", "ConfigHash")
                if name == "ConfigHash"
                else _text(row, name)
            )
        ]
        if missing:
            failures.append(f"row={index}:missing={','.join(missing)}")
        run_id = _text(row, "RunID")
        run_tag = _text(row, "RunTag")
        if run_id and run_tag and run_id != run_tag:
            failures.append(f"row={index}:RunID!=RunTag")
        config_hash = _text(row, "ScenarioConfigHash", "ConfigHash")
        if config_hash and (len(config_hash) != 64 or any(ch not in "0123456789abcdefABCDEF" for ch in config_hash)):
            failures.append(f"row={index}:ConfigHash_not_sha256")
    checks.append(_check("runtime_identity", path, "identity_complete_and_consistent", rows, failures))
    for column in IDENTITY_COLUMNS:
        values = {
            (_text(row, "ScenarioConfigHash", "ConfigHash") if column == "ConfigHash" else _text(row, column))
            for row in rows
            if (_text(row, "ScenarioConfigHash", "ConfigHash") if column == "ConfigHash" else _text(row, column))
        }
        checks.append(
            _check(
                "runtime_identity",
                path,
                f"single_{column}",
                rows,
                [] if len(values) == 1 else [f"unique_nonblank_count={len(values)}"],
            )
        )
    return checks


def _audit_link_table(
    path: str,
    header: list[str],
    rows: list[dict[str, str]],
    direction: str,
    expected_count: int,
) -> list[AuditCheck]:
    checks: list[AuditCheck] = []
    missing_columns = [name for name in LINK_REQUIRED_COLUMNS if name not in header]
    checks.append(_check("primary_link", path, "required_columns", rows, missing_columns))
    checks.append(
        _check(
            "primary_link",
            path,
            "expected_trial_count",
            rows,
            [] if len(_measured_analysis_rows(rows)) == expected_count and expected_count > 0 else [
                f"expected={expected_count};actual_effective={len(_measured_analysis_rows(rows))};actual_total={len(rows)}"
            ],
        )
    )
    if not rows:
        return checks
    checks.extend(_audit_identity(path, rows))

    keys: set[tuple[str, ...]] = set()
    duplicate_failures: list[str] = []
    value_failures: list[str] = []
    operating_failures: list[str] = []
    transport_failures: list[str] = []
    noise_failures: list[str] = []
    truth_failures: list[str] = []
    mimo_failures: list[str] = []
    for index, row in enumerate(rows, start=1):
        prefix = f"row={index}"
        fixed_link_trial = _boolean(row, "FixedLinkCampaign") is True
        if fixed_link_trial:
            # Independent calibration points restart their local NR frame
            # timeline by design. Point/drop/trial identity is therefore the
            # physical Monte-Carlo primary key, not Frame/Slot alone.
            key = (
                _text(row, "Direction"),
                _text(row, "FixedLinkPointIndex"),
                _text(row, "FixedLinkDropIndex"),
                _text(row, "FixedLinkTrialIndex"),
                _text(row, "ExecutionID"),
            )
        else:
            key = (
                _text(row, "Direction"),
                _text(row, "Frame"),
                _text(row, "Slot"),
                _text(row, "UEID", "UEIndex"),
                _text(row, "HARQRound"),
                _text(row, "ExecutionID"),
            )
        if key in keys:
            duplicate_failures.append(prefix + ":duplicate_primary_key")
        keys.add(key)
        if _text(row, "Direction").upper() != direction:
            value_failures.append(prefix + f":Direction={_text(row, 'Direction')}")

        transmitted_mcs = _number(row, "MCSIndex", "MCS")
        effective_mcs = _number(row, "EffectiveMCSIndex")
        scheduled_mcs = _number(row, "ScheduledMCSIndex", "ScheduledMCS")
        transmitted_mod = _text(row, "Modulation").upper()
        effective_mod = _text(row, "EffectiveModulation").upper()
        scheduled_mod = _text(row, "ScheduledModulation").upper()
        layers = _number(row, "Layers")
        rank = _number(row, "Rank", "RankEstimate")
        effective_layers = _number(row, "EffectiveLayers")
        effective_rank = _number(row, "EffectiveRank")
        if not _close(effective_mcs, transmitted_mcs, atol=0):
            operating_failures.append(prefix + ":effective_mcs_missing_or_mismatch")
        if effective_mod != transmitted_mod or not transmitted_mod:
            operating_failures.append(prefix + ":effective_modulation_missing_or_mismatch")
        if not _close(effective_layers, layers, atol=0):
            operating_failures.append(prefix + ":effective_layers_missing_or_mismatch")
        if not _close(effective_rank, rank, atol=0):
            operating_failures.append(prefix + ":effective_rank_missing_or_mismatch")
        genuinely_scheduled = (
            _boolean(row, "AdaptiveMode") is True
            and _boolean(row, "LinkAdaptationScheduled") is True
        )
        if genuinely_scheduled:
            if not _close(scheduled_mcs, transmitted_mcs, atol=0):
                operating_failures.append(prefix + ":scheduled_mcs_mismatch")
            if scheduled_mod != transmitted_mod or not scheduled_mod:
                operating_failures.append(prefix + ":scheduled_modulation_mismatch")
            if _boolean(row, "ScheduledOperatingPointMatchesTransmitted") is not True:
                operating_failures.append(prefix + ":scheduled_transmitted_match_flag_not_true")
        else:
            status = _text(row, "ScheduledOperatingPointEvidenceStatus").lower()
            if "not_applicable_no_adaptive_scheduled_decision" not in status:
                operating_failures.append(prefix + ":unscheduled_row_missing_not_applicable_status")
            if _boolean(row, "ScheduledOperatingPointMatchesTransmitted") is True:
                operating_failures.append(prefix + ":unscheduled_row_fabricated_match_flag")
        if transmitted_mod not in MODULATION_QM:
            operating_failures.append(prefix + f":unsupported_modulation={transmitted_mod}")
        qm = _number(row, "ModulationOrderQm")
        if qm is not None and transmitted_mod in MODULATION_QM and not _close(qm, MODULATION_QM[transmitted_mod], atol=0):
            operating_failures.append(prefix + ":modulation_order_mismatch")
        if layers is None or rank is None or layers < 1 or rank < 1 or rank < layers:
            operating_failures.append(prefix + ":invalid_rank_layers")

        mu_enabled = _boolean(row, "MUMIMOEnabled") is True
        mu_group_size = _number(row, "MUMIMOGroupSize")
        if mu_enabled:
            if mu_group_size is None or mu_group_size < 2:
                mimo_failures.append(prefix + ":mu_group_size_invalid")
            if (_number(row, "InterferenceContributorCount") or 0) < 1:
                mimo_failures.append(prefix + ":mu_interference_contributor_missing")
            if _boolean(row, "FullInterfererChannelTruthUsed") is not True:
                mimo_failures.append(prefix + ":full_interferer_channel_truth_not_used")
            if _boolean(row, "InterferenceCovarianceAvailable") is not True:
                mimo_failures.append(prefix + ":mu_interference_covariance_unavailable")
            covariance_source = _text(row, "InterferenceCovarianceSource").lower()
            if covariance_source != (
                "oracle_separated_shared_slot_per_prb_symbol_"
                "contribution_grid_covariance"
            ):
                mimo_failures.append(prefix + ":mu_covariance_source_not_explicit_oracle_per_re")
            if "irc" not in _text(row, "EqualizerType").lower():
                mimo_failures.append(prefix + ":mu_equalizer_not_irc")
            if direction.upper() == "DL":
                # DL PDSCH suppresses the peer layers in its joint per-RE
                # MMSE-IRC equalizer.  Do not invent a separate receive
                # combiner matrix merely to make DL resemble the UL chain.
                if _boolean(row, "MUMIMOReceiveProcessingApplied") is not True:
                    mimo_failures.append(prefix + ":mu_receive_processing_not_applied")
                for field in (
                    "MUMIMOReceiveProcessingStatus",
                    "MUMIMOReceiveProcessingSource",
                    "MUMIMOReceiveProcessingModeApplied",
                    "MUMIMOReceiverAlgorithmApplied",
                ):
                    if not _text(row, field):
                        mimo_failures.append(prefix + f":{field}_missing")
                if "irc" not in _text(row, "MUMIMOReceiveProcessingModeApplied").lower():
                    mimo_failures.append(prefix + ":mu_receive_processing_mode_not_irc")
                if "irc" not in _text(row, "MUMIMOReceiverAlgorithmApplied").lower():
                    mimo_failures.append(prefix + ":mu_receiver_algorithm_applied_not_irc")
                if _boolean(row, "MUMIMOReceiveCombinerApplied") is False:
                    combiner_status = _text(row, "MUMIMOReceiveCombinerStatus").lower()
                    if not combiner_status.startswith("not_applicable_"):
                        mimo_failures.append(prefix + ":separate_combiner_absence_not_explained")
            else:
                if _boolean(row, "MUMIMOReceiveCombinerApplied") is not True:
                    mimo_failures.append(prefix + ":mu_receive_combiner_not_applied")
                for field in (
                    "MUMIMOReceiveCombinerStatus",
                    "MUMIMOReceiveCombinerSource",
                    "MUMIMOReceiveProcessingMode",
                    "MUMIMOReceiverAlgorithm",
                    "MUMIMOReceiverAlgorithmApplied",
                ):
                    if not _text(row, field):
                        mimo_failures.append(prefix + f":{field}_missing")

        tbs = _number(row, "TBSize_bits")
        offered = _number(row, "OfferedBits")
        good = _number(row, "GoodBits")
        errors = _number(row, "BitErrors")
        compared = _number(row, "BitsCompared")
        ber = _number(row, "RawBER")
        crc = _boolean(row, "CRCPass")
        duration_ms = _number(row, "AirInterfaceObservation_ms")
        offered_rate = _number(row, "OfferedThroughput_Mbps")
        goodput = _number(row, "Goodput_Mbps")
        code_rate = _number(row, "TargetCodeRate")
        retransmission = _kpi_retransmission(row)
        if tbs is None or tbs <= 0 or not _close(tbs, round(tbs), atol=0):
            transport_failures.append(prefix + ":invalid_tbs")
        if retransmission:
            # A HARQ retransmission repeats an already admitted transport
            # block.  It consumes air-interface resources but must not be
            # counted as newly offered traffic a second time.
            if not _close(offered, 0.0, atol=0):
                transport_failures.append(prefix + ":retransmission_offered_bits_nonzero")
        elif not _close(offered, tbs, atol=0):
            transport_failures.append(prefix + ":new_data_offered_bits_not_tbs")
        if compared is None or compared <= 0 or errors is None or errors < 0 or errors > compared:
            transport_failures.append(prefix + ":invalid_bit_error_counts")
        elif not _close(ber, errors / compared, atol=1e-12, rtol=1e-9):
            transport_failures.append(prefix + ":ber_arithmetic_mismatch")
        if crc is True and not _close(good, tbs, atol=0):
            # A successful retransmission delivers the original TB even
            # though OfferedBits is zero on that retransmission row.
            transport_failures.append(prefix + ":crc_pass_delivered_bits_not_tbs")
        if crc is False and good not in {0, 0.0}:
            transport_failures.append(prefix + ":crc_fail_good_bits_nonzero")
        if duration_ms is None or duration_ms <= 0:
            transport_failures.append(prefix + ":invalid_observation_duration")
        else:
            if not _close(offered_rate, (offered or 0.0) / duration_ms / 1000.0, atol=1e-9, rtol=1e-9):
                transport_failures.append(prefix + ":offered_throughput_formula_mismatch")
            if not _close(goodput, (good or 0.0) / duration_ms / 1000.0, atol=1e-9, rtol=1e-9):
                transport_failures.append(prefix + ":goodput_formula_mismatch")
        if code_rate is None or not (0 < code_rate < 1):
            transport_failures.append(prefix + ":target_code_rate_out_of_range")

        for field in ("NoiseVariance", "PostEqualizationNoiseVariance", "LLRNoiseVariance"):
            value = _number(row, field)
            if value is None or value <= 0:
                noise_failures.append(prefix + f":{field}_not_positive_finite")
        measured = _number(row, "MeasuredTrialSINR_dB")
        posteq = _number(row, "PostEqSINR_dB")
        if not _close(measured, posteq, atol=1e-9, rtol=1e-9):
            noise_failures.append(prefix + ":measured_sinr_not_canonical_posteq")
        if not _text(row, "MeasuredTrialSINRSource") or not _text(row, "PostEqSINRSource"):
            noise_failures.append(prefix + ":sinr_source_missing")
        evm = _number(row, "EVM_rms")
        evm_sinr = _number(row, "EVMProxySINR_dB")
        if evm is None or evm <= 0 or evm_sinr is None:
            noise_failures.append(prefix + ":evm_measurement_missing")
        elif not _close(evm_sinr, -20.0 * math.log10(evm), atol=1e-8, rtol=1e-8):
            noise_failures.append(prefix + ":evm_sinr_formula_mismatch")

        # On a BLER campaign a failed CRC is an expected measured outcome,
        # not invalid evidence. Fixed-link rows carry the receiver trust
        # boundary separately; requiring decode-oriented StrictOk would erase
        # exactly the errors needed to form the waterfall.
        # Receiver-evidence validity and TB decoding are orthogonal. A CRC
        # failure is a legitimate measured BLER outcome and must not make an
        # otherwise complete waveform/estimation/equalization/LLR row
        # semantically invalid. Prefer the explicit receiver trust-boundary
        # flag for every waveform trial; retain StrictOk only for legacy rows
        # that predate that field.
        strict_evidence = _boolean(row, "StrictReceiverEvidenceOk")
        if strict_evidence is None:
            strict_evidence = _boolean(row, "StrictOk")
        if strict_evidence is not True:
            truth_failures.append(prefix + ":strict_execution_evidence_not_true")
        if _boolean(row, "FinalizedFlag") is not True:
            truth_failures.append(prefix + ":FinalizedFlag_not_true")
        if _boolean(row, "FallbackFlag") is not False:
            truth_failures.append(prefix + ":FallbackFlag_not_false")
        if _boolean(row, "PlaceholderFlag") is not False:
            truth_failures.append(prefix + ":PlaceholderFlag_not_false")
        truth_text = " ".join(
            _text(row, name).lower()
            for name in ("TruthStatus", "ExecutionBackend", "ApproximationMode")
        )
        if not _text(row, "TruthStatus") or not _text(row, "ExecutionBackend"):
            truth_failures.append(prefix + ":truth_lineage_missing")
        if any(token in truth_text for token in BAD_TRUTH_TOKENS):
            truth_failures.append(prefix + ":proxy_or_fallback_in_primary_truth")

    checks.extend(
        [
            _check("primary_link", path, "unique_trial_primary_key", rows, duplicate_failures),
            _check("primary_link", path, "direction_and_basic_values", rows, value_failures),
            _check("primary_link", path, "scheduled_transmitted_effective_operating_point", rows, operating_failures),
            _check("primary_link", path, "transport_crc_ber_goodput_arithmetic", rows, transport_failures),
            _check("primary_link", path, "noise_sinr_evm_lineage", rows, noise_failures),
            _check("primary_link", path, "mu_mimo_receiver_execution", rows, mimo_failures),
            _check("primary_link", path, "truth_proxy_and_lifecycle", rows, truth_failures),
        ]
    )
    return checks


def _audit_control_table(path: str, header: list[str], rows: list[dict[str, str]]) -> list[AuditCheck]:
    if not rows:
        return [_check("control_runtime", path, "present_rows_are_semantic", rows, [], required=False, evaluated=False)]
    checks = _audit_identity(path, rows)
    failures: list[str] = []
    for index, row in enumerate(rows, start=1):
        if "FinalizedFlag" in header and _boolean(row, "FinalizedFlag") is not True:
            failures.append(f"row={index}:FinalizedFlag_not_true")
        if _boolean(row, "PlaceholderFlag") is True or _boolean(row, "FallbackFlag") is True:
            failures.append(f"row={index}:fallback_or_placeholder")
        truth_text = " ".join(_text(row, name).lower() for name in ("TruthStatus", "SourceClassification", "ExecutionBackend"))
        if any(token in truth_text for token in BAD_TRUTH_TOKENS):
            failures.append(f"row={index}:proxy_or_fallback_truth")
        measured_fields = (
            "MeasuredTrialSINR_dB",
            "PostEqSINR_dB",
            "ReceiverHestSINR_dB",
            "DetectionMetric",
            "RSRP_dB",
            "CSI_RSRP_dB",
            "SINR_dB",
            "MeasurementRSRP_dB",
            "ChannelEstimateNoiseVariance",
            "EstimatedSINR_dB",
            "PostEqEVM",
            "NMSEChannelEst",
        )
        if not any(_number(row, name) is not None for name in measured_fields if name in header):
            failures.append(f"row={index}:no_finite_runtime_measurement")
    checks.append(_check("control_runtime", path, "runtime_measurement_and_truth", rows, failures))
    if "ReceiverHestSINRApplicable" in header:
        applicability_failures: list[str] = []
        for index, row in enumerate(rows, start=1):
            applicable = _boolean(row, "ReceiverHestSINRApplicable")
            value = _number(row, "ReceiverHestSINR_dB")
            if applicable is None:
                applicability_failures.append(f"row={index}:invalid_receiver_sinr_applicability")
            elif applicable and value is None:
                applicability_failures.append(f"row={index}:applicable_receiver_sinr_missing")
            elif not applicable and value is not None:
                applicability_failures.append(f"row={index}:finite_receiver_sinr_marked_not_applicable")
            if applicable and "ChannelEstimateAvailable" in header and \
                    _boolean(row, "ChannelEstimateAvailable") is not True:
                applicability_failures.append(f"row={index}:receiver_sinr_without_channel_estimate")
        # Availability consistency is not a detector: a finite channel/noise
        # estimate must never certify that the desired signal was detected.
        checks.append(_check(
            "control_runtime", path, "receiver_sinr_applicability", rows,
            applicability_failures,
        ))
    return checks


def _whole(value: float | None, minimum: int = 0) -> bool:
    return value is not None and value >= minimum and value == round(value)


def _is_sha256(value: str) -> bool:
    token = str(value or "").strip()
    return len(token) == 64 and all(ch in "0123456789abcdefABCDEF" for ch in token)


def _beta_continued_fraction(a: float, b: float, x: float) -> float:
    """Evaluate the continued fraction used by regularized incomplete beta.

    This is an independent Python implementation of the standard modified
    Lentz algorithm.  It deliberately does not reuse MATLAB interval output,
    so a corrupt persisted confidence interval cannot certify itself.
    """

    maximum_iterations = 400
    epsilon = 3.0e-14
    floor = 1.0e-300
    qab = a + b
    qap = a + 1.0
    qam = a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < floor:
        d = floor
    d = 1.0 / d
    result = d
    for iteration in range(1, maximum_iterations + 1):
        even = 2 * iteration
        numerator = iteration * (b - iteration) * x / (
            (qam + even) * (a + even)
        )
        d = 1.0 + numerator * d
        if abs(d) < floor:
            d = floor
        c = 1.0 + numerator / c
        if abs(c) < floor:
            c = floor
        d = 1.0 / d
        result *= d * c

        numerator = -(a + iteration) * (qab + iteration) * x / (
            (a + even) * (qap + even)
        )
        d = 1.0 + numerator * d
        if abs(d) < floor:
            d = floor
        c = 1.0 + numerator / c
        if abs(c) < floor:
            c = floor
        d = 1.0 / d
        delta = d * c
        result *= delta
        if abs(delta - 1.0) <= epsilon:
            return result
    raise ArithmeticError("incomplete beta continued fraction did not converge")


def _regularized_beta(x: float, a: float, b: float) -> float:
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    log_term = (
        math.lgamma(a + b)
        - math.lgamma(a)
        - math.lgamma(b)
        + a * math.log(x)
        + b * math.log1p(-x)
    )
    term = math.exp(log_term)
    if x < (a + 1.0) / (a + b + 2.0):
        return term * _beta_continued_fraction(a, b, x) / a
    return 1.0 - term * _beta_continued_fraction(b, a, 1.0 - x) / b


def _beta_quantile(probability: float, a: float, b: float) -> float:
    if probability <= 0.0:
        return 0.0
    if probability >= 1.0:
        return 1.0
    lower = 0.0
    upper = 1.0
    for _iteration in range(180):
        midpoint = (lower + upper) / 2.0
        if _regularized_beta(midpoint, a, b) < probability:
            lower = midpoint
        else:
            upper = midpoint
        if upper - lower <= 2.0e-15:
            break
    return (lower + upper) / 2.0


def _clopper_pearson_two_sided(
    errors: int, trials: int, confidence_level: float
) -> tuple[float, float]:
    alpha = 1.0 - confidence_level
    lower = 0.0 if errors == 0 else _beta_quantile(
        alpha / 2.0, float(errors), float(trials - errors + 1)
    )
    upper = 1.0 if errors == trials else _beta_quantile(
        1.0 - alpha / 2.0, float(errors + 1), float(trials - errors)
    )
    return lower, upper


def _component_operating_key(row: dict[str, str], direction: str) -> str:
    snr = _number(row, "SNRdB", "ConfiguredSNR_dB")
    rank = _number(row, "Rank")
    mcs = _number(row, "MCSIndex", "MCS")
    channel = _text(row, "ChannelModel", "ChannelModelApplied")
    modulation = _text(row, "Modulation").upper()
    if snr is None or rank is None or mcs is None:
        return ""
    key = (
        f"snr={snr:.12g}|channel={channel}|rank={int(round(rank))}"
        f"|mcs={int(round(mcs))}|mod={modulation}"
    )
    if direction == "UL":
        transform = _boolean(row, "TransformPrecoding", "TransformPrecodingApplied")
        hopping = _text(row, "FrequencyHopping", "FrequencyHoppingMode").lower()
        if transform is None:
            return ""
        key += f"|tp={int(transform)}|hop={hopping}"
    return key


def _component_source_row_eligible(row: dict[str, str]) -> bool:
    def enabled(name: str, default: bool) -> bool:
        if name not in row:
            return default
        return _boolean(row, name) is True

    if not enabled("FinalizedFlag", True):
        return False
    if not enabled("CRCApplicable", True):
        return False
    if not enabled("DecodeAttempted", True):
        return False
    if enabled("FallbackFlag", False) or enabled("PlaceholderFlag", False):
        return False
    if "TruthStatus" in row and _text(row, "TruthStatus").lower() != "real_lls_evidence":
        return False
    return True


def _audit_component_bler_curve(
    path: str,
    header: list[str],
    rows: list[dict[str, str]],
    direction: str,
    primary_rows: list[dict[str, str]],
    scenario_summary: dict[str, str],
) -> list[AuditCheck]:
    required_columns = {
        "CampaignID", "OperatingPointID", "SNRdB", "ChannelModel", "Rank",
        "MCSIndex", "Modulation", "Trials", "TBErrors", "BLER",
        "ConfidenceLevel", "CILower", "CIUpper", "CIHalfWidth",
        "MinErrorsRequired", "QualificationProfile",
        "PublicationQualificationRequested", "PublicationEligible",
        "StopReason", "Incomplete", "Status", "ScenarioID", "ConfigHash",
        "EvidenceScope", "EvidenceOrigin", "RunID", "ExecutionID",
        "CenterFrequencyHz", "BandwidthHz", "SubcarrierSpacingHz",
        "IntervalMethod", "EvidenceUnit",
    }
    if direction == "UL":
        required_columns.update({"TransformPrecoding", "FrequencyHopping"})
    checks = [_check(
        "component_bler", path, "required_columns", rows,
        sorted(required_columns - set(header)),
    )]
    if not rows:
        checks.append(_check(
            "component_bler", path, "runtime_operating_points_present", rows,
            ["component_curve_has_no_runtime_rows"],
        ))
        return checks

    identity_failures: list[str] = []
    arithmetic_failures: list[str] = []
    qualification_failures: list[str] = []
    source_failures: list[str] = []
    observed_keys: set[str] = set()
    expected_scenario = _text(scenario_summary, "ScenarioID")
    expected_hash = _text(scenario_summary, "ConfigHash")
    expected_groups: dict[str, list[dict[str, str]]] = {}
    for raw in primary_rows:
        if not _component_source_row_eligible(raw):
            continue
        key = _component_operating_key(raw, direction)
        if key:
            expected_groups.setdefault(key, []).append(raw)
        else:
            source_failures.append("source_row_has_invalid_operating_point")

    for index, row in enumerate(rows, start=1):
        prefix = f"row={index}"
        campaign_id = _text(row, "CampaignID")
        run_id = _text(row, "RunID")
        scenario_id = _text(row, "ScenarioID")
        config_hash = _text(row, "ConfigHash")
        execution_id = _text(row, "ExecutionID")
        if not campaign_id or campaign_id != run_id:
            identity_failures.append(prefix + ":CampaignID_RunID_mismatch_or_missing")
        if not scenario_id or (expected_scenario and scenario_id != expected_scenario):
            identity_failures.append(prefix + ":ScenarioID_mismatch_or_missing")
        if not _is_sha256(config_hash) or (
            expected_hash and config_hash.lower() != expected_hash.lower()
        ):
            identity_failures.append(prefix + ":ConfigHash_mismatch_or_invalid")
        if not execution_id:
            identity_failures.append(prefix + ":ExecutionID_missing")
        for name in ("CenterFrequencyHz", "BandwidthHz", "SubcarrierSpacingHz"):
            value = _number(row, name)
            if value is None or value <= 0:
                identity_failures.append(prefix + f":{name}_not_positive_finite")
        if _text(row, "EvidenceScope").lower() != "in_path":
            identity_failures.append(prefix + ":EvidenceScope_not_in_path")
        if _text(row, "EvidenceOrigin").lower() not in {
            "current_runtime_memory", "persisted_completed_run_truth"
        }:
            identity_failures.append(prefix + ":EvidenceOrigin_invalid")
        if _text(row, "EvidenceUnit").lower() != "decoded_transport_block":
            identity_failures.append(prefix + ":EvidenceUnit_invalid")

        key = _component_operating_key(row, direction)
        operating_id = _text(row, "OperatingPointID").lower()
        if not key:
            arithmetic_failures.append(prefix + ":operating_point_invalid")
        elif key in observed_keys:
            arithmetic_failures.append(prefix + ":duplicate_operating_point")
        else:
            observed_keys.add(key)
            expected_id = hashlib.sha256(key.encode("utf-8")).hexdigest()
            if operating_id != expected_id:
                arithmetic_failures.append(prefix + ":OperatingPointID_hash_mismatch")
        channel = _text(row, "ChannelModel")
        if not channel or channel.upper() in {"TDL", "CDL"}:
            arithmetic_failures.append(prefix + ":ChannelModel_missing_or_nonconcrete")
        rank = _number(row, "Rank")
        mcs = _number(row, "MCSIndex")
        if not _whole(rank, 1):
            arithmetic_failures.append(prefix + ":Rank_not_positive_integer")
        if not _whole(mcs) or (mcs is not None and mcs > 31):
            arithmetic_failures.append(prefix + ":MCSIndex_invalid")
        if _text(row, "Modulation").upper() not in MODULATION_QM:
            arithmetic_failures.append(prefix + ":Modulation_invalid")
        if direction == "UL":
            transform = _boolean(row, "TransformPrecoding")
            hopping = _text(row, "FrequencyHopping").lower()
            if transform is None:
                arithmetic_failures.append(prefix + ":TransformPrecoding_invalid")
            if hopping not in {"none", "intra_slot", "inter_slot"}:
                arithmetic_failures.append(prefix + ":FrequencyHopping_invalid")

        trials = _number(row, "Trials")
        errors = _number(row, "TBErrors")
        bler = _number(row, "BLER")
        confidence = _number(row, "ConfidenceLevel")
        lower = _number(row, "CILower")
        upper = _number(row, "CIUpper")
        half_width = _number(row, "CIHalfWidth")
        if not (
            _whole(trials, 1) and _whole(errors)
            and errors <= trials
            and bler is not None
            and _close(bler, errors / trials, atol=1e-12)
            and confidence is not None and 0 < confidence < 1
            and lower is not None and upper is not None and half_width is not None
            and 0 <= lower <= bler <= upper <= 1
            and _close(half_width, (upper - lower) / 2.0, atol=1e-12)
        ):
            arithmetic_failures.append(prefix + ":bler_count_or_interval_arithmetic_invalid")
        elif _text(row, "IntervalMethod").upper() != "CLOPPER_PEARSON_TWO_SIDED":
            arithmetic_failures.append(prefix + ":IntervalMethod_not_exact_clopper_pearson")
        else:
            expected_lower, expected_upper = _clopper_pearson_two_sided(
                int(errors), int(trials), confidence
            )
            if not _close(lower, expected_lower, atol=2e-11, rtol=2e-11):
                arithmetic_failures.append(prefix + ":CILower_not_exact_clopper_pearson")
            if not _close(upper, expected_upper, atol=2e-11, rtol=2e-11):
                arithmetic_failures.append(prefix + ":CIUpper_not_exact_clopper_pearson")

        profile = _text(row, "QualificationProfile").lower()
        requested = _boolean(row, "PublicationQualificationRequested")
        eligible = _boolean(row, "PublicationEligible")
        incomplete = _boolean(row, "Incomplete")
        status = _text(row, "Status").upper()
        stop_reason = _text(row, "StopReason").lower()
        minimum_errors = _number(row, "MinErrorsRequired")
        if profile not in {"diagnostic", "full"}:
            qualification_failures.append(prefix + ":QualificationProfile_invalid")
        if any(value is None for value in (requested, eligible, incomplete)):
            qualification_failures.append(prefix + ":qualification_boolean_missing")
        if profile == "diagnostic" and (requested is not False or eligible is not False):
            qualification_failures.append(prefix + ":diagnostic_promoted_to_publication")
        if incomplete is True:
            if eligible is not False or status != "NOT_EVALUATED":
                qualification_failures.append(prefix + ":incomplete_status_or_eligibility_invalid")
        elif profile == "diagnostic":
            if status != "MEASURED":
                qualification_failures.append(prefix + ":diagnostic_status_not_measured")
        elif requested is True:
            if not (
                eligible is True and status == "STATISTICALLY_QUALIFIED"
                and minimum_errors is not None and minimum_errors >= 1
                and errors is not None and errors >= minimum_errors
                and stop_reason == "configured_trial_error_and_confidence_requirements_reached"
            ):
                qualification_failures.append(prefix + ":full_qualification_claim_unsupported")
        elif eligible is not False or status != "MEASURED":
            qualification_failures.append(prefix + ":nonrequested_publication_status_invalid")
        if not stop_reason:
            qualification_failures.append(prefix + ":StopReason_missing")

        source = expected_groups.get(key, [])
        if not source:
            source_failures.append(prefix + ":no_matching_primary_runtime_rows")
        else:
            expected_errors = sum(_boolean(item, "CRCPass") is False for item in source)
            if trials is None or int(trials) != len(source):
                source_failures.append(prefix + ":Trials_not_source_row_count")
            if errors is None or int(errors) != expected_errors:
                source_failures.append(prefix + ":TBErrors_not_source_crc_fail_count")
            for field, source_field in (
                ("ScenarioID", "ScenarioID"),
                ("ConfigHash", "ConfigHash"),
                ("RunID", "RunID"),
                ("ExecutionID", "ExecutionID"),
            ):
                source_values = {_text(item, source_field) for item in source}
                source_values.discard("")
                if len(source_values) != 1 or _text(row, field) not in source_values:
                    source_failures.append(prefix + f":{field}_not_source_identity")

    if set(expected_groups) != observed_keys:
        missing = sorted(set(expected_groups) - observed_keys)
        extra = sorted(observed_keys - set(expected_groups))
        source_failures.append(
            f"operating_point_set_mismatch:missing={len(missing)};extra={len(extra)}"
        )
    checks.extend([
        _check("component_bler", path, "runtime_identity_and_truth_origin", rows, identity_failures),
        _check("component_bler", path, "operating_point_bler_and_exact_interval", rows, arithmetic_failures),
        _check("component_bler", path, "qualification_status_fail_closed", rows, qualification_failures),
        _check("component_bler", path, "exact_primary_trial_reconciliation", rows, source_failures),
    ])
    return checks


def _audit_component_bler_outputs(
    run_root: Path,
    link_rows: dict[str, list[dict[str, str]]],
    scenario_summary: dict[str, str],
) -> list[AuditCheck]:
    checks: list[AuditCheck] = []
    for direction, relative in COMPONENT_BLER_TABLES.items():
        header, rows = _read_rows(run_root / relative)
        if header or rows:
            checks.extend(_audit_component_bler_curve(
                relative, header, rows, direction,
                link_rows.get(direction, []), scenario_summary,
            ))
    return checks


def _adaptive_policy_expectation(row: dict[str, str]) -> tuple[bool, str]:
    if _boolean(row, "AdaptiveMode") is not True:
        return True, "not_applicable_fixed_operating_point"
    reasons: list[str] = []
    policy = _text(row, "ConfiguredMCSSelectionPolicy").lower()
    lineage = [
        _text(row, field).lower()
        for field in (
            "ActualMCSSelectionMode", "MCSSelectionSource", "MCSAuthority",
            "ModulationAuthority", "AppliedOperatingPointSource",
        )
    ]
    if not policy or policy in {"fixed", "configured_fixed", "disabled", "off", "none"}:
        reasons.append("adaptive_policy_not_configured")
    if not (
        _boolean(row, "LinkAdaptationScheduled") is True
        and _boolean(row, "LinkAdaptationApplied") is True
    ):
        reasons.append("adaptive_schedule_or_apply_evidence_missing")
    scheduled_mcs = _number(row, "ScheduledMCS")
    transmitted_mcs = _number(row, "TransmittedMCS")
    if not _close(scheduled_mcs, transmitted_mcs, atol=0):
        reasons.append("scheduled_transmitted_mcs_mismatch")
    maximum_mcs = _number(row, "ConfiguredMaximumMCS")
    if maximum_mcs is None:
        reasons.append("adaptive_maximum_mcs_not_configured")
    elif (
        (scheduled_mcs is not None and scheduled_mcs > maximum_mcs)
        or (transmitted_mcs is not None and transmitted_mcs > maximum_mcs)
    ):
        reasons.append("adaptive_maximum_mcs_exceeded")
    if _number(row, "ConfiguredInitialMCS") is None:
        reasons.append("adaptive_initial_mcs_not_configured")
    if (
        not _text(row, "ScheduledModulation")
        or _text(row, "ScheduledModulation").upper()
        != _text(row, "TransmittedModulation").upper()
    ):
        reasons.append("scheduled_transmitted_modulation_mismatch")
    if not _text(row, "AdaptationEvidenceId") or not any(lineage):
        reasons.append("adaptive_decision_lineage_missing")
    forbidden = (
        "proxy", "fallback", "configured_fixed", "legacy_mcs", "missing",
        "unavailable", "error", "rejected",
    )
    if any(token in value for token in forbidden for value in lineage):
        reasons.append("adaptive_decision_lineage_not_truth_eligible")
    if (
        ("cqi" in policy or policy in {"amc", "adaptive"})
        and not (
            _number(row, "WidebandCQI") is not None
            and _number(row, "CQIDerivedMCS") is not None
            and any("cqi" in value for value in lineage)
        )
    ):
        reasons.append("cqi_policy_runtime_measurement_lineage_missing")
    if "effective_sinr" in policy and not any("effective_sinr" in value for value in lineage):
        reasons.append("effective_sinr_policy_lineage_missing")
    reasons = list(dict.fromkeys(reasons))
    return not reasons, "|".join(reasons)


def _audit_mimo_rank_layer_table(
    path: str,
    header: list[str],
    rows: list[dict[str, str]],
    link_rows: dict[str, list[dict[str, str]]],
) -> list[AuditCheck]:
    required_columns = {
        "RunId", "ScenarioName", "TrialId", "Direction", "CellId", "UEId",
        "Frame", "Slot", "ConfiguredRank", "ConfiguredLayers",
        "ScheduledRank", "ScheduledLayers", "TransmittedRank",
        "TransmittedLayers", "ReceiverEstimatedRank", "EffectiveDecodedRank",
        "SpatialChannelRankEstimate", "SpatialChannelTxPorts",
        "SpatialChannelRxAntennas", "SpatialChannelRankDomain",
        "SpatialChannelRankSource", "EffectiveDecodedLayers",
        "NumRxAntennas", "NumTxPorts",
        "TxWaveformColumns", "PhysicalTxAntennas", "RxWaveformBranches",
        "PhysicalRxAntennas", "LogicalTxPortCount", "LogicalRxBranchCount",
        "ConfiguredModulation", "ScheduledModulation", "TransmittedModulation",
        "EffectiveDecodedModulation", "ConfiguredMCS", "ScheduledMCS",
        "TransmittedMCS", "EffectiveDecodedMCS", "DMRSPorts",
        "ConfiguredMCSSelectionPolicy", "ActualMCSSelectionMode",
        "MCSSelectionSource", "MCSAuthority", "ModulationAuthority",
        "AppliedOperatingPointSource", "LinkAdaptationScheduled",
        "LinkAdaptationApplied", "AdaptiveFeedbackDecisionObserved",
        "AppliedPrecoderMatrixSHA256", "LayerSINRdB", "DecodeCrcPass",
        "ExactSpatialMatch", "SpatialContractMatch", "ExactOperatingPointMatch",
        "FixedOperatingPointMatch", "AdaptivePolicyRequired",
        "AdaptivePolicyMatch", "AdaptivePolicyConformance",
        "AdaptivePolicyFailureReason", "OperatingPointContractMatch",
        "MUExecutionRequired", "MUMIMOEnabled", "MUExecutionMatch",
        "ExactConfiguredMatch", "ExecutionContractMatch", "AdaptiveMode",
        "FixedAnchorMode", "StrictEligible", "ExecutionContractOk",
        "DecodeReliabilityOk", "DecodeReliabilityStatus", "StrictOk",
        "SourceArtifactRef", "SourceRowsHash", "Status", "FailureReason",
    }
    checks = [_check(
        "mimo_rank_layer", path, "required_columns", rows,
        sorted(required_columns - set(header)),
    )]
    expected_count = sum(len(link_rows.get(direction, [])) for direction in ("DL", "UL"))
    checks.append(_check(
        "mimo_rank_layer", path, "one_row_per_primary_link_trial", rows,
        [] if expected_count > 0 and len(rows) == expected_count
        else [f"expected={expected_count};actual={len(rows)}"],
    ))
    if not rows:
        return checks

    value_failures: list[str] = []
    contract_failures: list[str] = []
    reliability_failures: list[str] = []
    source_failures: list[str] = []

    rows_by_direction = {
        direction: [row for row in rows if _text(row, "Direction").upper() == direction]
        for direction in ("DL", "UL")
    }
    invalid_direction_rows = [
        index for index, row in enumerate(rows, start=1)
        if _text(row, "Direction").upper() not in {"DL", "UL"}
    ]
    if invalid_direction_rows:
        value_failures.append(f"invalid_direction_rows={invalid_direction_rows[:12]}")

    for direction in ("DL", "UL"):
        directional = rows_by_direction[direction]
        source = link_rows.get(direction, [])
        if not directional and not source:
            continue
        trial_ids = [_number(row, "TrialId") for row in directional]
        if (
            any(not _whole(value, 1) for value in trial_ids)
            or [int(value) for value in trial_ids if value is not None]
            != list(range(1, len(directional) + 1))
        ):
            source_failures.append(direction + ":TrialId_not_contiguous_from_one")
        hashes = {_text(row, "SourceRowsHash").lower() for row in directional}
        if len(hashes) != 1 or not hashes or not all(_is_sha256(value) for value in hashes):
            source_failures.append(direction + ":SourceRowsHash_missing_invalid_or_inconsistent")
        expected_source = (
            "air_interface/csv/dl_pdsch_trials.csv"
            if direction == "DL" else "air_interface/csv/ul_pusch_trials.csv"
        )
        if any(_text(row, "SourceArtifactRef") != expected_source for row in directional):
            source_failures.append(direction + ":SourceArtifactRef_mismatch")
        if len(directional) != len(source):
            source_failures.append(
                direction + f":source_row_count_mismatch:{len(directional)}!={len(source)}"
            )

        for local_index, row in enumerate(directional, start=1):
            prefix = f"{direction}:row={local_index}"
            configured_rank = _number(row, "ConfiguredRank")
            configured_layers = _number(row, "ConfiguredLayers")
            scheduled_rank = _number(row, "ScheduledRank")
            scheduled_layers = _number(row, "ScheduledLayers")
            transmitted_rank = _number(row, "TransmittedRank")
            transmitted_layers = _number(row, "TransmittedLayers")
            receiver_rank = _number(row, "ReceiverEstimatedRank")
            spatial_rank = _number(row, "SpatialChannelRankEstimate")
            spatial_tx_ports = _number(row, "SpatialChannelTxPorts")
            spatial_rx_antennas = _number(row, "SpatialChannelRxAntennas")
            decoded_rank = _number(row, "EffectiveDecodedRank")
            decoded_layers = _number(row, "EffectiveDecodedLayers")
            tx_ports = _number(row, "NumTxPorts")
            rx_antennas = _number(row, "NumRxAntennas")
            logical_tx = _number(row, "LogicalTxPortCount")
            logical_rx = _number(row, "LogicalRxBranchCount")
            spatial_values = (
                configured_rank, configured_layers, scheduled_rank,
                scheduled_layers, transmitted_rank, transmitted_layers,
                receiver_rank, tx_ports, rx_antennas, logical_tx, logical_rx,
            )
            if not all(_whole(value, 1) for value in spatial_values):
                value_failures.append(prefix + ":rank_layer_or_port_value_invalid")
            elif not (
                transmitted_rank <= min(tx_ports, rx_antennas)
                and transmitted_layers <= tx_ports
                and receiver_rank <= min(tx_ports, rx_antennas)
                and logical_tx >= transmitted_layers
                and logical_rx >= 1
            ):
                value_failures.append(prefix + ":rank_layer_exceeds_runtime_dimensions")
            if not all(_whole(value, 1) for value in (
                spatial_rank, spatial_tx_ports, spatial_rx_antennas,
            )):
                value_failures.append(prefix + ":spatial_channel_rank_or_dimension_invalid")
            elif spatial_rank > min(spatial_tx_ports, spatial_rx_antennas):
                value_failures.append(prefix + ":spatial_channel_rank_exceeds_measurement_dimensions")
            if not _text(row, "SpatialChannelRankDomain") or not _text(
                row, "SpatialChannelRankSource"
            ):
                value_failures.append(prefix + ":spatial_channel_rank_lineage_missing")
            for name in (
                "TxWaveformColumns", "PhysicalTxAntennas", "RxWaveformBranches",
                "PhysicalRxAntennas",
            ):
                if not _whole(_number(row, name), 1):
                    value_failures.append(prefix + f":{name}_invalid")
            configured_modulation = _text(row, "ConfiguredModulation").upper()
            scheduled_modulation = _text(row, "ScheduledModulation").upper()
            transmitted_modulation = _text(row, "TransmittedModulation").upper()
            decoded_modulation = _text(row, "EffectiveDecodedModulation").upper()
            if any(value not in MODULATION_QM for value in (
                configured_modulation, scheduled_modulation,
                transmitted_modulation, decoded_modulation,
            )):
                value_failures.append(prefix + ":modulation_invalid")
            for name in ("ConfiguredMCS", "ScheduledMCS", "TransmittedMCS", "EffectiveDecodedMCS"):
                value = _number(row, name)
                if not _whole(value) or (value is not None and value > 31):
                    value_failures.append(prefix + f":{name}_invalid")
            if not _is_sha256(_text(row, "AppliedPrecoderMatrixSHA256")):
                value_failures.append(prefix + ":AppliedPrecoderMatrixSHA256_invalid")
            layer_sinr = [
                token for token in _text(row, "LayerSINRdB").replace(",", "|").split("|")
                if token.strip()
            ]
            try:
                finite_layer_sinr = all(math.isfinite(float(value)) for value in layer_sinr)
            except ValueError:
                finite_layer_sinr = False
            if not (
                transmitted_layers is not None
                and len(layer_sinr) == int(transmitted_layers)
                and finite_layer_sinr
            ):
                value_failures.append(prefix + ":LayerSINRdB_not_per_transmitted_layer")
            dmrs_ports = [token for token in _text(row, "DMRSPorts").split("|") if token]
            if transmitted_layers is not None and dmrs_ports != [
                str(index) for index in range(int(transmitted_layers))
            ]:
                value_failures.append(prefix + ":DMRSPorts_not_one_per_transmitted_layer")

            spatial_match = (
                transmitted_rank is not None and configured_rank is not None
                and transmitted_layers is not None and configured_layers is not None
                and transmitted_rank == configured_rank
                and transmitted_layers == configured_layers
            )
            operating_match = (
                (not configured_modulation or transmitted_modulation == configured_modulation)
                and (
                    _number(row, "ConfiguredMCS") is None
                    or _close(_number(row, "TransmittedMCS"), _number(row, "ConfiguredMCS"), atol=0)
                )
            )
            adaptive = _boolean(row, "AdaptiveMode") is True
            adaptive_match, adaptive_reason = _adaptive_policy_expectation(row)
            operating_contract = operating_match if not adaptive else adaptive_match
            mu_required = _boolean(row, "MUExecutionRequired") is True
            mu_match = _boolean(row, "MUExecutionMatch")
            if not mu_required:
                expected_mu_match = True
            else:
                group_size = _number(row, "MUMIMOGroupSize")
                required_users = _number(row, "RequiredMUUserCount")
                expected_mu_match = bool(
                    _boolean(row, "MUMIMOEnabled") is True
                    and _whole(group_size, 2)
                    and _whole(required_users, 2)
                    and group_size >= required_users
                    and _number(row, "InterferenceContributorCount") is not None
                    and _number(row, "InterferenceContributorCount") >= required_users - 1
                    and _is_sha256(_text(row, "AppliedPrecoderMatrixSHA256"))
                )
            expected_flags = {
                "ExactSpatialMatch": spatial_match,
                "SpatialContractMatch": spatial_match,
                "ExactOperatingPointMatch": operating_match,
                "FixedOperatingPointMatch": operating_match,
                "AdaptivePolicyRequired": adaptive,
                "AdaptivePolicyMatch": adaptive_match,
                "AdaptivePolicyConformance": adaptive_match,
                "OperatingPointContractMatch": operating_contract,
                "MUExecutionMatch": expected_mu_match,
                "ExactConfiguredMatch": spatial_match and operating_match,
                "ExecutionContractMatch": spatial_match and operating_contract,
            }
            for name, expected in expected_flags.items():
                if _boolean(row, name) is not expected:
                    contract_failures.append(prefix + f":{name}_mismatch")
            if _text(row, "AdaptivePolicyFailureReason") != adaptive_reason:
                contract_failures.append(prefix + ":AdaptivePolicyFailureReason_mismatch")
            if mu_match is not expected_mu_match:
                contract_failures.append(prefix + ":MUExecutionMatch_mismatch")

            crc_pass = _boolean(row, "DecodeCrcPass")
            strict_eligible = _boolean(row, "StrictEligible")
            execution_contract = spatial_match and operating_contract
            execution_ok = strict_eligible is True and execution_contract and expected_mu_match
            reliability_ok = strict_eligible is True and crc_pass is True
            reliability_status = (
                "not_evaluated" if strict_eligible is not True
                else "crc_pass" if crc_pass is True else "crc_fail"
            )
            if _boolean(row, "ExecutionContractOk") is not execution_ok:
                reliability_failures.append(prefix + ":ExecutionContractOk_mismatch")
            if _boolean(row, "StrictOk") is not execution_ok:
                reliability_failures.append(prefix + ":StrictOk_must_equal_execution_contract_not_crc")
            if _boolean(row, "DecodeReliabilityOk") is not reliability_ok:
                reliability_failures.append(prefix + ":DecodeReliabilityOk_mismatch")
            if _text(row, "DecodeReliabilityStatus").lower() != reliability_status:
                reliability_failures.append(prefix + ":DecodeReliabilityStatus_mismatch")
            if crc_pass is False:
                if decoded_rank != 0 or decoded_layers != 0:
                    reliability_failures.append(prefix + ":crc_fail_decoded_rank_layers_not_zero")
            elif crc_pass is True:
                if not (
                    _whole(decoded_rank, 1) and _whole(decoded_layers, 1)
                    and decoded_rank <= transmitted_rank
                    and decoded_layers <= transmitted_layers
                ):
                    reliability_failures.append(prefix + ":crc_pass_decoded_rank_layers_invalid")
            else:
                reliability_failures.append(prefix + ":DecodeCrcPass_invalid")
            status = _text(row, "Status").lower()
            reason = _text(row, "FailureReason")
            if strict_eligible is not True:
                if status != "not_evaluated" or reason != "warmup_row_excluded_from_strict_mimo_evidence":
                    reliability_failures.append(prefix + ":warmup_status_reduction_invalid")
            elif execution_ok:
                if status != "pass" or reason:
                    reliability_failures.append(prefix + ":passing_execution_status_invalid")
            elif status != "fail" or not reason:
                reliability_failures.append(prefix + ":failed_execution_status_invalid")

            if local_index <= len(source):
                raw = source[local_index - 1]
                comparisons = (
                    ("RunId", _text(raw, "RunID", "RunId"), _text(row, "RunId")),
                    ("ScenarioName", _text(raw, "ScenarioID"), _text(row, "ScenarioName")),
                    ("Frame", _number(raw, "Frame"), _number(row, "Frame")),
                    ("Slot", _number(raw, "Slot"), _number(row, "Slot")),
                    ("UEId", _number(raw, "UEID", "UEIndex", "UE"), _number(row, "UEId")),
                    ("DecodeCrcPass", _boolean(raw, "CRCPass"), crc_pass),
                    ("TransmittedRank", _number(raw, "TransmittedRank", "TransmittedLayers", "PrecodingNumLayers", "Layers"), transmitted_rank),
                    ("TransmittedLayers", _number(raw, "TransmittedLayers", "PrecodingNumLayers", "Layers"), transmitted_layers),
                    ("TransmittedMCS", _number(raw, "TransmittedMCS", "MCS", "MCSIndex"), _number(row, "TransmittedMCS")),
                    ("TransmittedModulation", _text(raw, "TransmittedModulation", "Modulation").upper(), transmitted_modulation),
                )
                for name, expected, observed in comparisons:
                    if isinstance(expected, bool) or isinstance(observed, bool):
                        match = expected is observed
                    elif isinstance(expected, (float, int)) or isinstance(observed, (float, int)):
                        match = _close(
                            float(observed) if observed is not None else None,
                            float(expected) if expected is not None else None,
                            atol=0,
                        )
                    else:
                        match = bool(expected) and expected == observed
                    if not match:
                        source_failures.append(prefix + f":{name}_not_primary_source")
                source_warmup = _boolean(raw, "IsWarmupFrame") is True
                if strict_eligible is not (not source_warmup):
                    source_failures.append(prefix + ":StrictEligible_not_source_warmup_inverse")

    checks.extend([
        _check("mimo_rank_layer", path, "rank_layer_port_precoder_values", rows, value_failures),
        _check("mimo_rank_layer", path, "execution_contract_boolean_reduction", rows, contract_failures),
        _check("mimo_rank_layer", path, "decode_reliability_separate_from_execution", rows, reliability_failures),
        _check("mimo_rank_layer", path, "ordered_primary_trial_and_lineage_reconciliation", rows, source_failures),
    ])
    return checks


def _audit_mimo_rank_layer_output(
    run_root: Path,
    link_rows: dict[str, list[dict[str, str]]],
) -> list[AuditCheck]:
    header, rows = _read_rows(run_root / MIMO_RANK_LAYER_TABLE)
    if not header and not rows:
        return []
    return _audit_mimo_rank_layer_table(
        MIMO_RANK_LAYER_TABLE, header, rows, link_rows
    )


def _mode_number(rows: list[dict[str, str]], field: str) -> float | None:
    values = [_number(row, field) for row in rows]
    finite = [value for value in values if value is not None]
    if not finite:
        return None
    counts: dict[float, int] = {}
    for value in finite:
        counts[value] = counts.get(value, 0) + 1
    maximum = max(counts.values())
    return min(value for value, count in counts.items() if count == maximum)


def _mode_text(rows: list[dict[str, str]], field: str) -> str:
    values = [_text(row, field) for row in rows]
    populated = [value for value in values if value]
    if not populated:
        return ""
    counts: dict[str, int] = {}
    for value in populated:
        counts[value] = counts.get(value, 0) + 1
    maximum = max(counts.values())
    return min(value for value, count in counts.items() if count == maximum)


def _audit_mimo_configured_effective_table(
    path: str,
    header: list[str],
    rows: list[dict[str, str]],
    rank_rows: list[dict[str, str]],
) -> list[AuditCheck]:
    required_columns = {
        "RunId", "ScenarioName", "Direction", "ConfiguredRank",
        "DominantScheduledRank", "DominantTransmittedRank",
        "DominantEffectiveDecodedRank", "ConfiguredLayers",
        "DominantScheduledLayers", "DominantTransmittedLayers",
        "DominantEffectiveDecodedLayers", "ConfiguredModulation",
        "DominantEffectiveModulation", "ConfiguredMCS",
        "ConfiguredInitialMCS", "ConfiguredMaximumMCS", "DominantEffectiveMCS",
        "AdaptiveMode", "StrictEligibleRowCount", "ExactMatchRowCount",
        "ExactMatchPercent", "ExactSpatialMatchRowCount",
        "ExactSpatialMatchPercent", "ExactOperatingPointMatchRowCount",
        "ExactOperatingPointMatchPercent", "AdaptivePolicyMatchRowCount",
        "AdaptivePolicyMatchPercent", "AdaptiveFeedbackDecisionRowCount",
        "ExecutionContractMatchRowCount", "ExecutionContractMatchPercent",
        "SpatialContractRequired", "SpatialContractMatch",
        "FixedOperatingPointRequired", "FixedOperatingPointMatch",
        "AdaptivePolicyRequired", "AdaptivePolicyConformance",
        "MUExecutionRequired", "RequiredMUUserCount",
        "RequiredMULeakageThreshold_dB", "RequiredMUExecutionMode",
        "MUExecutedTrialRowCount", "MUExecutedDistinctGroupCount",
        "MUExecutionMatch", "MUExecutionFailureReason",
        "RequiredExactMatchPercent", "RequiredExecutionContractMatchPercent",
        "ScenarioObjectivePass", "RuntimePopulated", "RuntimeTrialCount",
        "RuntimeRank2Fraction", "RuntimeExactMatchFraction",
        "RuntimeEvidenceSource", "EvidenceClass", "Status", "FailureReason",
    }
    checks = [_check(
        "mimo_companion", path, "required_columns", rows,
        sorted(required_columns - set(header)),
    )]
    failures: list[str] = []
    expected_directions = {
        _text(row, "Direction").upper() for row in rank_rows
        if _text(row, "Direction").upper() in {"DL", "UL"}
    }
    observed_directions = [_text(row, "Direction").upper() for row in rows]
    if set(observed_directions) != expected_directions or len(observed_directions) != len(set(observed_directions)):
        failures.append("direction_rows_not_exactly_one_per_runtime_direction")
    for row_index, row in enumerate(rows, start=1):
        direction = _text(row, "Direction").upper()
        prefix = f"row={row_index}:{direction or 'missing'}"
        subset = [
            item for item in rank_rows
            if _text(item, "Direction").upper() == direction
            and _boolean(item, "StrictEligible") is True
        ]
        if not subset:
            failures.append(prefix + ":no_strict_rank_layer_source_rows")
            continue
        if any(_text(item, "RunId") != _text(row, "RunId") for item in subset):
            failures.append(prefix + ":RunId_not_rank_source")
        if any(_text(item, "ScenarioName") != _text(row, "ScenarioName") for item in subset):
            failures.append(prefix + ":ScenarioName_not_rank_source")
        # EffectiveDecodedRank/EffectiveDecodedLayers are deliberately zero on
        # CRC-failed transport blocks.  Those zeroes are reliability evidence,
        # not observations that the executed spatial rank changed to zero.
        # Match the MATLAB producer: reduce decoded rank/layers over successful
        # receiver rows and report zero only when no successful row exists.
        decoded_subset = [
            item for item in subset
            if _boolean(item, "DecodeCrcPass") is True
            and (_number(item, "EffectiveDecodedRank") or 0.0) > 0.0
            and (_number(item, "EffectiveDecodedLayers") or 0.0) > 0.0
        ]
        expected_modes = {
            "ConfiguredRank": _mode_number(subset, "ConfiguredRank"),
            "DominantScheduledRank": _mode_number(subset, "ScheduledRank"),
            "DominantTransmittedRank": _mode_number(subset, "TransmittedRank"),
            "DominantEffectiveDecodedRank": (
                _mode_number(decoded_subset, "EffectiveDecodedRank")
                if decoded_subset else 0.0
            ),
            "ConfiguredLayers": _mode_number(subset, "ConfiguredLayers"),
            "DominantScheduledLayers": _mode_number(subset, "ScheduledLayers"),
            "DominantTransmittedLayers": _mode_number(subset, "TransmittedLayers"),
            "DominantEffectiveDecodedLayers": (
                _mode_number(decoded_subset, "EffectiveDecodedLayers")
                if decoded_subset else 0.0
            ),
            "ConfiguredMCS": _mode_number(subset, "ConfiguredMCS"),
            "ConfiguredInitialMCS": _mode_number(subset, "ConfiguredInitialMCS"),
            "ConfiguredMaximumMCS": _mode_number(subset, "ConfiguredMaximumMCS"),
            "DominantEffectiveMCS": _mode_number(subset, "EffectiveDecodedMCS"),
        }
        for field, expected in expected_modes.items():
            if not _close(_number(row, field), expected, atol=0):
                failures.append(prefix + f":{field}_not_rank_mode")
        if _text(row, "ConfiguredModulation").upper() != _mode_text(subset, "ConfiguredModulation").upper():
            failures.append(prefix + ":ConfiguredModulation_not_rank_mode")
        if _text(row, "DominantEffectiveModulation").upper() != _mode_text(subset, "EffectiveDecodedModulation").upper():
            failures.append(prefix + ":DominantEffectiveModulation_not_rank_mode")

        count = len(subset)
        count_fields = {
            "ExactMatch": "ExactConfiguredMatch",
            "ExactSpatialMatch": "ExactSpatialMatch",
            "ExactOperatingPointMatch": "ExactOperatingPointMatch",
            "AdaptivePolicyMatch": "AdaptivePolicyMatch",
            "ExecutionContractMatch": "ExecutionContractMatch",
        }
        derived_counts: dict[str, int] = {}
        for prefix_name, source_field in count_fields.items():
            observed_count = sum(_boolean(item, source_field) is True for item in subset)
            derived_counts[prefix_name] = observed_count
            if not _close(_number(row, prefix_name + "RowCount"), float(observed_count), atol=0):
                failures.append(prefix + f":{prefix_name}RowCount_mismatch")
            if not _close(_number(row, prefix_name + "Percent"), observed_count / count, atol=1e-12):
                failures.append(prefix + f":{prefix_name}Percent_mismatch")
        feedback_count = sum(
            _boolean(item, "AdaptiveFeedbackDecisionObserved") is True for item in subset
        )
        for field in ("StrictEligibleRowCount", "RuntimeTrialCount"):
            if not _close(_number(row, field), float(count), atol=0):
                failures.append(prefix + f":{field}_mismatch")
        if not _close(_number(row, "AdaptiveFeedbackDecisionRowCount"), float(feedback_count), atol=0):
            failures.append(prefix + ":AdaptiveFeedbackDecisionRowCount_mismatch")

        adaptive = all(_boolean(item, "AdaptiveMode") is True for item in subset)
        fixed_anchor = all(_boolean(item, "FixedAnchorMode") is True for item in subset)
        spatial_match = all(_boolean(item, "SpatialContractMatch") is True for item in subset)
        fixed_match = all(_boolean(item, "FixedOperatingPointMatch") is True for item in subset)
        adaptive_conformance = (
            all(_boolean(item, "AdaptivePolicyConformance") is True for item in subset)
            and (not adaptive or feedback_count > 0)
        )
        mu_required = any(_boolean(item, "MUExecutionRequired") is True for item in subset)
        (
            mu_execution_match,
            mu_executed_rows,
            mu_executed_groups,
            mu_failure_reason,
        ) = _recompute_mu_summary_execution(subset, row, mu_required)
        expected_booleans = {
            "AdaptiveMode": adaptive,
            "SpatialContractRequired": fixed_anchor,
            "SpatialContractMatch": spatial_match,
            "FixedOperatingPointRequired": not adaptive,
            "FixedOperatingPointMatch": fixed_match,
            "AdaptivePolicyRequired": adaptive,
            "AdaptivePolicyConformance": adaptive_conformance,
            "MUExecutionRequired": mu_required,
            "MUExecutionMatch": mu_execution_match,
            "RuntimePopulated": True,
        }
        for field, expected in expected_booleans.items():
            if _boolean(row, field) is not expected:
                failures.append(prefix + f":{field}_mismatch")
        rank2_fraction = sum(
            _number(item, "TransmittedRank") == 2
            or _number(item, "EffectiveDecodedRank") == 2
            for item in subset
        ) / count
        exact_fraction = derived_counts["ExactMatch"] / count
        if not _close(_number(row, "RuntimeRank2Fraction"), rank2_fraction, atol=1e-12):
            failures.append(prefix + ":RuntimeRank2Fraction_mismatch")
        if not _close(_number(row, "RuntimeExactMatchFraction"), exact_fraction, atol=1e-12):
            failures.append(prefix + ":RuntimeExactMatchFraction_mismatch")

        if (
            not _close(_number(row, "MUExecutedTrialRowCount"), float(mu_executed_rows), atol=0)
            or not _close(
                _number(row, "MUExecutedDistinctGroupCount"),
                float(mu_executed_groups),
                atol=0,
            )
        ):
            failures.append(prefix + ":mu_execution_counts_not_rank_source")
        if _text(row, "MUExecutionFailureReason") != mu_failure_reason:
            failures.append(prefix + ":MUExecutionFailureReason_mismatch")

        exact_threshold = _number(row, "RequiredExactMatchPercent")
        execution_threshold = _number(row, "RequiredExecutionContractMatchPercent")
        objective = bool(
            count > 0
            and (exact_threshold is None or exact_fraction + 2.3e-16 >= exact_threshold)
            and (
                execution_threshold is None
                or derived_counts["ExecutionContractMatch"] / count + 2.3e-16
                >= execution_threshold
            )
            and (not fixed_anchor or spatial_match)
            and (adaptive or fixed_match)
            and (not adaptive or adaptive_conformance)
            and mu_execution_match
        )
        if _boolean(row, "ScenarioObjectivePass") is not objective:
            failures.append(prefix + ":ScenarioObjectivePass_mismatch")
        expected_status = "pass" if objective else "fail"
        if _text(row, "Status").lower() != expected_status:
            failures.append(prefix + ":Status_not_objective_reduction")
        if objective and _text(row, "FailureReason"):
            failures.append(prefix + ":passing_row_has_failure_reason")
        if not objective and not _text(row, "FailureReason"):
            failures.append(prefix + ":failed_row_missing_failure_reason")
        if _text(row, "RuntimeEvidenceSource") != "rank_layer_trials_from_air_interface_raw_trials":
            failures.append(prefix + ":RuntimeEvidenceSource_invalid")
        if _text(row, "EvidenceClass") != "DIRECT_RUNTIME_EVIDENCE":
            failures.append(prefix + ":EvidenceClass_invalid")
    checks.append(_check(
        "mimo_companion", path,
        "configured_effective_summary_recomputed_from_rank_trials", rows, failures,
    ))
    return checks


def _recompute_mu_summary_execution(
    subset: list[dict[str, str]],
    summary: dict[str, str],
    mu_required: bool,
) -> tuple[bool, int, int, str]:
    """Rebuild the scenario MU objective from complete physical MU groups.

    Bootstrap and single-user trials are valid causal precursors to measured
    pairing and therefore do not make a scenario-level MU objective fail.
    Conversely, every row in a group that claims shared-slot MU execution must
    satisfy the per-trial waveform/receiver contract and share the exact
    allocation with the other users in that group.
    """
    if not mu_required:
        return True, 0, 0, "not_applicable_mu_disabled"

    required_users_value = _number(summary, "RequiredMUUserCount")
    required_users = max(2, int(round(required_users_value or 2)))
    required_mode = _text(summary, "RequiredMUExecutionMode").strip().lower()
    if required_mode != "shared_slot_waveform_superposition":
        return False, 0, 0, "configured_mu_execution_mode_is_not_shared_waveform_superposition"

    candidates: list[dict[str, str]] = []
    for item in subset:
        group_id = _number(item, "MUMIMOGroupId")
        group_size = _number(item, "MUMIMOGroupSize")
        if (
            _boolean(item, "MUMIMOEnabled") is True
            and group_id is not None
            and group_size is not None
            and group_size >= required_users
        ):
            candidates.append(item)
    if not candidates:
        return False, 0, 0, "no_shared_prb_mu_trial_rows"

    grouped: dict[float, list[dict[str, str]]] = {}
    for item in candidates:
        group_id = _number(item, "MUMIMOGroupId")
        assert group_id is not None
        grouped.setdefault(group_id, []).append(item)

    executed_rows = 0
    passed_groups = 0
    invalid_groups = 0
    for group_rows in grouped.values():
        ue_ids = {
            ue_id for item in group_rows
            if (ue_id := _number(item, "UEId")) is not None
        }
        allocation_matches = all(
            _all_same_finite(group_rows, field)
            for field in ("PRBStart", "PRBCount", "SymbolStart", "NumSymbols")
        )
        group_ok = (
            len(group_rows) >= required_users
            and len(ue_ids) >= required_users
            and all(_boolean(item, "MUExecutionMatch") is True for item in group_rows)
            and allocation_matches
        )
        if group_ok:
            passed_groups += 1
            executed_rows += len(group_rows)
        else:
            invalid_groups += 1

    match = passed_groups > 0 and invalid_groups == 0
    if match:
        reason = ""
    elif passed_groups == 0:
        reason = "no_complete_physical_mu_group"
    else:
        reason = "one_or_more_labeled_mu_groups_failed_shared_resource_or_waveform_contract"
    return match, executed_rows, passed_groups, reason


def _all_same_finite(rows: list[dict[str, str]], field: str) -> bool:
    values = [_number(item, field) for item in rows]
    return bool(values) and all(value is not None for value in values) and all(
        value == values[0] for value in values
    )


def _audit_mimo_per_trial_companion(
    path: str,
    header: list[str],
    rows: list[dict[str, str]],
    rank_rows: list[dict[str, str]],
) -> list[AuditCheck]:
    required_by_path = {
        "beamforming/csv/beam_sweep_measurements.csv": {
            "RunId", "TrialId", "Direction", "SelectedBeamId",
            "MeasurementSource", "SourceRowsHash", "Status", "FailureReason",
        },
        "beamforming/csv/mimo_oracle_guard.csv": {
            "RunId", "Direction", "TrialId", "CellId", "UEId", "Stage",
            "OracleFieldName", "WasAccessed", "Allowed", "Violation",
            "Status", "FailureReason",
        },
        "beamforming/csv/precoder_evidence.csv": {
            "RunId", "TrialId", "Direction", "PrecoderId", "PMI",
            "AppliedPrecoderMatrixSHA256", "EvidenceType", "PrecoderSource",
            "PrecodingActive", "SourceRowsHash", "Status", "FailureReason",
        },
    }
    required = required_by_path[path]
    checks = [_check(
        "mimo_companion", path, "required_columns", rows,
        sorted(required - set(header)),
    )]
    failures: list[str] = []
    if len(rows) != len(rank_rows):
        failures.append(f"row_count_mismatch:{len(rows)}!={len(rank_rows)}")
    for index, (row, rank) in enumerate(zip(rows, rank_rows), start=1):
        prefix = f"row={index}"
        for field in ("RunId", "Direction", "TrialId"):
            observed = _number(row, field) if field == "TrialId" else _text(row, field)
            expected = _number(rank, field) if field == "TrialId" else _text(rank, field)
            if observed != expected:
                failures.append(prefix + f":{field}_not_rank_source")
        status = _text(row, "Status").lower()
        reason = _text(row, "FailureReason")
        if path.endswith("beam_sweep_measurements.csv"):
            selected = _text(rank, "BeamId") or "not_selected"
            configured_layers = _number(rank, "ConfiguredLayers")
            expected_pass = bool(
                selected != "not_selected"
                or (configured_layers is not None and configured_layers <= 1)
            )
            if _text(row, "SelectedBeamId") != selected:
                failures.append(prefix + ":SelectedBeamId_not_rank_source")
            if _text(row, "SourceRowsHash") != _text(rank, "SourceRowsHash"):
                failures.append(prefix + ":SourceRowsHash_not_rank_source")
            if _text(row, "MeasurementSource") not in {
                "air_interface_trial_row", "csi_or_grant_runtime_evidence"
            }:
                failures.append(prefix + ":MeasurementSource_invalid")
        elif path.endswith("mimo_oracle_guard.csv"):
            expected_violation = bool(
                _number(rank, "EffectiveDecodedRank") is not None
                and _number(rank, "ConfiguredRank") is not None
                and _number(rank, "EffectiveDecodedRank") == _number(rank, "ConfiguredRank")
                and not _text(rank, "LayerSINRdB")
                and _boolean(rank, "DecodeCrcPass") is True
            )
            expected_pass = not expected_violation
            if _boolean(row, "Violation") is not expected_violation:
                failures.append(prefix + ":Violation_formula_mismatch")
            if _boolean(row, "WasAccessed") is not False or _boolean(row, "Allowed") is not False:
                failures.append(prefix + ":configured_rank_oracle_access_not_forbidden")
            if _text(row, "Stage") != "effective_rank_derivation" or _text(row, "OracleFieldName") != "ConfiguredRank":
                failures.append(prefix + ":oracle_stage_or_field_invalid")
            for field in ("CellId", "UEId"):
                if not _close(_number(row, field), _number(rank, field), atol=0):
                    failures.append(prefix + f":{field}_not_rank_source")
        else:
            pmi = _text(rank, "PrecoderId")
            matrix_hash = _text(rank, "AppliedPrecoderMatrixSHA256").lower()
            matrix_available = _is_sha256(matrix_hash)
            pmi_available = bool(pmi)
            expected_active = pmi_available or matrix_available
            expected_pass = bool(
                expected_active or (_number(rank, "ConfiguredLayers") or 0) <= 1
            )
            expected_id = (
                "matrix_sha256:" + matrix_hash if matrix_available
                else "pmi:" + pmi if pmi_available else ""
            )
            expected_type = (
                "pmi_and_applied_matrix" if matrix_available and pmi_available
                else "applied_matrix" if matrix_available
                else "pmi" if pmi_available else "missing"
            )
            if _text(row, "PrecoderId") != expected_id:
                failures.append(prefix + ":PrecoderId_formula_mismatch")
            if _text(row, "PMI") != (pmi if pmi_available else ""):
                failures.append(prefix + ":PMI_not_rank_source")
            if _text(row, "AppliedPrecoderMatrixSHA256").lower() != (
                matrix_hash if matrix_available else ""
            ):
                failures.append(prefix + ":matrix_hash_not_rank_source")
            if _text(row, "EvidenceType") != expected_type:
                failures.append(prefix + ":EvidenceType_mismatch")
            if _boolean(row, "PrecodingActive") is not expected_active:
                failures.append(prefix + ":PrecodingActive_mismatch")
            if _text(row, "SourceRowsHash") != _text(rank, "SourceRowsHash"):
                failures.append(prefix + ":SourceRowsHash_not_rank_source")
        if status != ("pass" if expected_pass else "fail"):
            failures.append(prefix + ":Status_mismatch")
        if expected_pass and reason:
            failures.append(prefix + ":passing_row_has_failure_reason")
        if not expected_pass and not reason:
            failures.append(prefix + ":failed_row_missing_failure_reason")
    checks.append(_check(
        "mimo_companion", path, "ordered_row_reconciliation_to_rank_trials",
        rows, failures,
    ))
    return checks


def _audit_mimo_layer_metrics_table(
    path: str,
    header: list[str],
    rows: list[dict[str, str]],
    rank_rows: list[dict[str, str]],
) -> list[AuditCheck]:
    required = {
        "RunId", "TrialId", "CellId", "UEId", "Direction", "Slot",
        "LayerIndex", "CodewordIndex", "DMRSPort", "PostEqSINRdB", "EVMdB",
        "ChannelEstimateNMSEdB", "LLRMeanAbs", "DecodeCrcPass", "BER",
        "BLERContribution", "Status",
    }
    checks = [_check(
        "mimo_companion", path, "required_columns", rows,
        sorted(required - set(header)),
    )]
    failures: list[str] = []
    expected_count = sum(int(_number(rank, "TransmittedLayers") or 0) for rank in rank_rows)
    if len(rows) != expected_count:
        failures.append(f"layer_row_count_mismatch:{len(rows)}!={expected_count}")
    offset = 0
    for rank_index, rank in enumerate(rank_rows, start=1):
        layers = int(_number(rank, "TransmittedLayers") or 0)
        source_sinr = [
            float(token) for token in _text(rank, "LayerSINRdB").split("|")
            if token.strip()
        ]
        group = rows[offset:offset + layers]
        offset += layers
        if len(group) != layers:
            failures.append(f"trial={rank_index}:missing_layer_rows")
            continue
        for layer_index, row in enumerate(group, start=1):
            prefix = f"trial={rank_index}:layer={layer_index}"
            for field in ("RunId", "Direction", "TrialId", "CellId", "UEId", "Slot"):
                observed = _number(row, field) if field in {"TrialId", "CellId", "UEId", "Slot"} else _text(row, field)
                expected = _number(rank, field) if field in {"TrialId", "CellId", "UEId", "Slot"} else _text(rank, field)
                if observed != expected:
                    failures.append(prefix + f":{field}_not_rank_source")
            if _number(row, "LayerIndex") != layer_index or _number(row, "DMRSPort") != layer_index - 1:
                failures.append(prefix + ":layer_or_dmrs_index_invalid")
            expected_codeword = 1 if layers <= 4 else min(2, math.ceil(layer_index / 4))
            if _number(row, "CodewordIndex") != expected_codeword:
                failures.append(prefix + ":CodewordIndex_invalid")
            if layer_index <= len(source_sinr):
                if not _close(_number(row, "PostEqSINRdB"), source_sinr[layer_index - 1], atol=1e-8):
                    failures.append(prefix + ":PostEqSINRdB_not_rank_source")
            elif _number(row, "PostEqSINRdB") is not None:
                failures.append(prefix + ":unexpected_PostEqSINRdB")
            crc = _boolean(rank, "DecodeCrcPass")
            if _boolean(row, "DecodeCrcPass") is not crc:
                failures.append(prefix + ":DecodeCrcPass_not_rank_source")
            if _number(row, "BLERContribution") != (0 if crc is True else 1):
                failures.append(prefix + ":BLERContribution_not_crc_inverse")
            ber = _number(row, "BER")
            if ber is None or not 0 <= ber <= 1:
                failures.append(prefix + ":BER_invalid")
            for field in ("EVMdB", "ChannelEstimateNMSEdB", "LLRMeanAbs"):
                if _number(row, field) is None:
                    failures.append(prefix + f":{field}_missing")
            expected_status = "pass" if layer_index <= len(source_sinr) else "missing_layer_receiver_metric"
            if _text(row, "Status") != expected_status:
                failures.append(prefix + ":Status_mismatch")
    checks.append(_check(
        "mimo_companion", path, "per_layer_receiver_metrics_reconcile_rank_trials",
        rows, failures,
    ))
    return checks


def _audit_mimo_beam_codebook_table(
    path: str,
    header: list[str],
    rows: list[dict[str, str]],
    rank_rows: list[dict[str, str]],
) -> list[AuditCheck]:
    required = {
        "RunId", "Direction", "BeamId", "WeightVectorHash",
        "SourceRowsHash", "Status", "FailureReason",
    }
    checks = [_check(
        "mimo_companion", path, "required_columns", rows,
        sorted(required - set(header)),
    )]
    failures: list[str] = []
    expected: set[tuple[str, str]] = set()
    for direction in ("DL", "UL"):
        subset = [item for item in rank_rows if _text(item, "Direction").upper() == direction]
        if not subset:
            continue
        beams = {_text(item, "BeamId") for item in subset if _text(item, "BeamId")}
        if not beams:
            beams = {"not_selected"}
        expected.update((direction, beam) for beam in beams)
    observed: set[tuple[str, str]] = set()
    for index, row in enumerate(rows, start=1):
        prefix = f"row={index}"
        direction = _text(row, "Direction").upper()
        beam = _text(row, "BeamId")
        key = (direction, beam)
        if key in observed:
            failures.append(prefix + ":duplicate_direction_beam")
        observed.add(key)
        subset = [item for item in rank_rows if _text(item, "Direction").upper() == direction]
        if not subset:
            failures.append(prefix + ":no_rank_source_direction")
            continue
        if _text(row, "RunId") != _text(subset[0], "RunId"):
            failures.append(prefix + ":RunId_not_rank_source")
        if _text(row, "SourceRowsHash") != _text(subset[0], "SourceRowsHash"):
            failures.append(prefix + ":SourceRowsHash_not_rank_source")
        if not _is_sha256(_text(row, "WeightVectorHash")):
            failures.append(prefix + ":WeightVectorHash_invalid")
        multi_layer_missing = beam == "not_selected" and any(
            (_number(item, "ConfiguredLayers") or 0) > 1 for item in subset
        )
        expected_pass = not multi_layer_missing
        if _text(row, "Status").lower() != ("pass" if expected_pass else "fail"):
            failures.append(prefix + ":Status_mismatch")
        if expected_pass and _text(row, "FailureReason"):
            failures.append(prefix + ":passing_row_has_failure_reason")
        if not expected_pass and not _text(row, "FailureReason"):
            failures.append(prefix + ":failed_row_missing_failure_reason")
    if observed != expected:
        failures.append(f"direction_beam_set_mismatch:{len(observed)}!={len(expected)}")
    checks.append(_check(
        "mimo_companion", path, "beam_codebook_reconciles_rank_trial_beams",
        rows, failures,
    ))
    return checks


def _optional_number_equal(
    actual: float | None, expected: float | None, *, atol: float = 0.0
) -> bool:
    if actual is None or expected is None:
        return actual is None and expected is None
    return math.isclose(actual, expected, abs_tol=atol, rel_tol=1e-9)


def _mode_first_available(
    rows: list[dict[str, str]], fields: tuple[str, ...]
) -> float | None:
    for field in fields:
        value = _mode_number(rows, field)
        if value is not None:
            return value
    return None


def _audit_beam_precoder_table(
    path: str,
    header: list[str],
    rows: list[dict[str, str]],
    link_rows: dict[str, list[dict[str, str]]],
) -> list[AuditCheck]:
    semantic_columns = {
        "timestamp_sim_ms", "frame", "slot", "direction", "ue_id", "rnti",
        "cell_id", "configured_beam_selection_strategy", "beam_selection_strategy",
        "selected_beam_index", "best_beam_index", "beam_hit",
        "requested_beam_index_set", "requested_beam_truth_classification",
        "precoder_source", "applied_precoder_source", "requested_precoder_pmi",
        "requested_precoder_pmi_truth_classification", "applied_precoder_pmi",
        "applied_precoder_pmi_type", "applied_precoder_codebook_mode",
        "requested_vs_applied_precoder_pmi_match_status", "beamforming_applied",
        "applied_beam_index_set", "applied_beam_application_source",
        "applied_beam_truth_classification", "applied_precoder_pmi_application_source",
        "applied_precoder_pmi_truth_classification", "precoding_mode",
        "precoding_application_stage", "precoding_active",
        "explicit_beam_weights_applied", "transform_precoding_applied",
        "precoding_num_ports", "precoding_num_layers", "precoding_matrix_rows",
        "precoding_matrix_cols", "qcl_accuracy", "qcl_type", "qcl_source_rs",
        "qcl_status", "tci_state_id", "unified_tci_state_id",
        "tci_validity_timer_slots", "tci_status",
        "near_field_status", "runtime_evidence",
        "source_artifact_ref", "run_tag", "scenario_id", "config_hash",
        "code_commit", "seed", "producer_module", "status_code",
        "status_classification", "derived_flag", "active_flag",
    }
    checks = [_check(
        "mimo_companion", path, "required_columns", rows,
        sorted(semantic_columns - set(header)),
    )]
    sources: list[tuple[str, dict[str, str]]] = []
    for direction in ("DL", "UL"):
        sources.extend((direction, row) for row in link_rows.get(direction, []))
    failures: list[str] = []
    if len(rows) != len(sources):
        failures.append(f"row_count_mismatch:{len(rows)}!={len(sources)}")
    numeric_mapping = {
        "frame": ("Frame",), "slot": ("Slot",),
        "ue_id": ("UEID", "UEIndex", "UE", "RNTI"), "rnti": ("RNTI",),
        "cell_id": ("CellID", "ServingCell"),
        "selected_beam_index": ("SelectedBeamIndex",),
        "best_beam_index": ("BestBeamIndex",), "beam_hit": ("BeamHit",),
        "requested_precoder_pmi": ("RequestedPrecoderPMI",),
        "applied_precoder_pmi": ("AppliedPrecoderPMI",),
        "precoding_num_ports": ("PrecodingNumPorts",),
        "precoding_num_layers": ("PrecodingNumLayers",),
        "precoding_matrix_rows": ("PrecodingMatrixRows",),
        "precoding_matrix_cols": ("PrecodingMatrixCols",),
        "qcl_accuracy": ("QCLAccuracy",),
        "tci_validity_timer_slots": ("TCIValidityTimerSlots",),
        "fraunhofer_boundary_m": ("FraunhoferBoundary_m",),
        "near_field_focal_point_m": ("NearFieldFocalPoint_m", "FocalPoint_m"),
    }
    text_mapping = {
        "configured_beam_selection_strategy": ("ConfiguredBeamSelectionStrategy",),
        "beam_selection_strategy": ("BeamSelectionStrategy",),
        "requested_beam_index_set": ("RequestedBeamIndexSet",),
        "requested_beam_truth_classification": ("RequestedBeamTruthClassification",),
        "precoder_source": ("PrecoderSource",),
        "applied_precoder_source": ("AppliedPrecoderSource",),
        "requested_precoder_pmi_truth_classification": ("RequestedPrecoderPMITruthClassification",),
        "applied_precoder_pmi_type": ("AppliedPrecoderPMIType",),
        "applied_precoder_codebook_mode": ("AppliedPrecoderCodebookMode",),
        "requested_vs_applied_precoder_pmi_match_status": ("RequestedVsAppliedPrecoderPMIMatchStatus",),
        "applied_beam_index_set": ("AppliedBeamIndexSet",),
        "applied_beam_application_source": ("AppliedBeamApplicationSource",),
        "applied_beam_truth_classification": ("AppliedBeamTruthClassification",),
        "applied_precoder_pmi_application_source": ("AppliedPrecoderPMIApplicationSource",),
        "applied_precoder_pmi_truth_classification": ("AppliedPrecoderPMITruthClassification",),
        "precoding_mode": ("PrecodingMode",),
        "precoding_application_stage": ("PrecodingApplicationStage",),
        "qcl_type": ("QCLType", "QCLTypes"), "qcl_source_rs": ("QCLSourceRS",),
        "tci_state_id": ("TCIState", "TCIStateID"),
        "unified_tci_state_id": ("UnifiedTCIStateID",),
    }
    logical_mapping = {
        "beamforming_applied": "BeamformingApplied",
        "precoding_active": "PrecodingActive",
        "explicit_beam_weights_applied": "ExplicitBeamWeightsApplied",
        "transform_precoding_applied": "TransformPrecodingApplied",
    }
    for index, (row, source_item) in enumerate(zip(rows, sources), start=1):
        direction, source = source_item
        prefix = f"row={index}:{direction}"
        timestamp = _number(source, "TimestampSim_ms")
        if timestamp is None:
            time_s = _number(source, "Time_s")
            timestamp = None if time_s is None else 1000.0 * time_s
        if not _optional_number_equal(_number(row, "timestamp_sim_ms"), timestamp, atol=1e-9):
            failures.append(prefix + ":timestamp_not_primary_source")
        if _text(row, "direction").upper() != direction:
            failures.append(prefix + ":direction_not_primary_order")
        for target, aliases in numeric_mapping.items():
            if not _optional_number_equal(_number(row, target), _number(source, *aliases), atol=1e-9):
                failures.append(prefix + f":{target}_not_primary_source")
        for target, aliases in text_mapping.items():
            if target in {"requested_beam_index_set", "applied_beam_index_set"}:
                matches = _beam_index_set(row, target) == _beam_index_set(source, *aliases)
            else:
                matches = _text(row, target) == _text(source, *aliases)
            if not matches:
                failures.append(prefix + f":{target}_not_primary_source")
        for target, source_field in logical_mapping.items():
            expected = _boolean(source, source_field)
            expected = False if expected is None else expected
            if _boolean(row, target) is not expected:
                failures.append(prefix + f":{target}_not_primary_source")
        expected_qcl_status = _text(source, "QCLStatus")
        if not expected_qcl_status:
            expected_qcl_status = (
                "runtime_qcl_accuracy_measured"
                if _number(source, "QCLAccuracy") is not None
                else "not_materialized_in_active_truth_path"
            )
        expected_tci_status = _text(source, "TCIStatus")
        if not expected_tci_status:
            expected_tci_status = (
                "runtime_or_configured_tci_state_present"
                if _text(source, "TCIState", "TCIStateID")
                else "not_materialized_in_active_truth_path"
            )
        if _text(row, "qcl_status") != expected_qcl_status:
            failures.append(prefix + ":qcl_status_formula_mismatch")
        if _text(row, "tci_status") != expected_tci_status:
            failures.append(prefix + ":tci_status_formula_mismatch")
        expected_near = _text(source, "NearFieldStatus") or "not_materialized_in_active_truth_path"
        if _text(row, "near_field_status") != expected_near:
            failures.append(prefix + ":near_field_status_formula_mismatch")
        expected_source = (
            "air_interface/csv/dl_pdsch_trials.csv" if direction == "DL"
            else "air_interface/csv/ul_pusch_trials.csv"
        )
        exact_text = {
            "runtime_evidence": "persisted_air_interface_trial_row",
            "source_artifact_ref": expected_source,
            "run_tag": _text(source, "RunTag", "RunID"),
            "scenario_id": _text(source, "ScenarioID"),
            "config_hash": _text(source, "ConfigHash"),
            "producer_module": "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildBeamPrecoderTable",
            "status_code": "implemented",
            "status_classification": "runtime_beam_precoder_trial_rows",
        }
        for field, expected in exact_text.items():
            if _text(row, field) != expected:
                failures.append(prefix + f":{field}_mismatch")
        if _boolean(row, "derived_flag") is not False or _boolean(row, "active_flag") is not True:
            failures.append(prefix + ":finalization_flags_invalid")
        if not _is_sha256(_text(row, "config_hash")):
            failures.append(prefix + ":config_hash_invalid")
        commit = _text(row, "code_commit").lower()
        if len(commit) != 40 or any(char not in "0123456789abcdef" for char in commit):
            failures.append(prefix + ":code_commit_invalid")
        if _number(row, "seed") is None:
            failures.append(prefix + ":seed_missing")
    checks.append(_check(
        "mimo_companion", path, "ordered_trial_and_all_beam_precoder_fields_reconcile",
        rows, failures,
    ))
    return checks


def _group_key_number(value: float | None) -> str:
    return "NOT_AVAILABLE" if value is None else format(value, ".17g")


def _audit_beamforming_analytics_table(
    path: str,
    header: list[str],
    rows: list[dict[str, str]],
    beam_rows: list[dict[str, str]],
) -> list[AuditCheck]:
    required = {
        "direction", "cell_id", "ue_id", "trial_row_count",
        "beamforming_applied_count", "runtime_applied_beam_rows",
        "runtime_applied_pmi_rows", "beam_hit_rate", "mean_precoding_ports",
        "mean_precoding_layers", "analytics_value_source", "producer_module",
        "status_code", "status_classification", "source_artifact_ref",
        "derived_flag", "active_flag",
    }
    checks = [_check(
        "mimo_companion", path, "required_columns", rows,
        sorted(required - set(header)),
    )]
    groups: dict[tuple[str, str, str], list[dict[str, str]]] = {}
    for source in beam_rows:
        direction = _text(source, "direction").upper() or "NOT_AVAILABLE"
        key = (
            direction,
            _group_key_number(_number(source, "cell_id")),
            _group_key_number(_number(source, "ue_id")),
        )
        groups.setdefault(key, []).append(source)
    failures: list[str] = []
    if len(rows) != len(groups):
        failures.append(f"row_count_mismatch:{len(rows)}!={len(groups)}")
    for index, (row, (key, subset)) in enumerate(zip(rows, groups.items()), start=1):
        prefix = f"row={index}"
        direction, _cell_token, _ue_token = key
        expected_numbers = {
            "cell_id": _number(subset[0], "cell_id"),
            "ue_id": _number(subset[0], "ue_id"),
            "trial_row_count": float(len(subset)),
            "beamforming_applied_count": float(sum(_boolean(item, "beamforming_applied") is True for item in subset)),
            "runtime_applied_beam_rows": float(sum(_text(item, "applied_beam_truth_classification") == "applied_runtime_value" for item in subset)),
            "runtime_applied_pmi_rows": float(sum(_text(item, "applied_precoder_pmi_truth_classification") == "applied_runtime_value" for item in subset)),
            "beam_hit_rate": _finite_mean([_number(item, "beam_hit") for item in subset]),
            "mean_precoding_ports": _finite_mean([_number(item, "precoding_num_ports") for item in subset]),
            "mean_precoding_layers": _finite_mean([_number(item, "precoding_num_layers") for item in subset]),
        }
        if _text(row, "direction").upper() != direction:
            failures.append(prefix + ":direction_group_mismatch")
        for field, expected in expected_numbers.items():
            if not _optional_number_equal(_number(row, field), expected, atol=1e-12):
                failures.append(prefix + f":{field}_aggregate_mismatch")
        exact = {
            "analytics_value_source": "beamforming/csv/beam_precoder_table.csv",
            "producer_module": "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildBeamformingAnalyticsTable",
            "status_code": "implemented", "status_classification": "derived_beamforming_analytics",
            "source_artifact_ref": "beamforming/csv/beam_precoder_table.csv",
        }
        for field, expected in exact.items():
            if _text(row, field) != expected:
                failures.append(prefix + f":{field}_invalid")
        if _boolean(row, "derived_flag") is not True or _boolean(row, "active_flag") is not True:
            failures.append(prefix + ":finalization_flags_invalid")
    checks.append(_check(
        "mimo_companion", path, "grouped_beam_analytics_recomputed_from_precoder_rows",
        rows, failures,
    ))
    return checks


def _finite_mean(values: list[float | None]) -> float | None:
    finite = [value for value in values if value is not None]
    return None if not finite else sum(finite) / len(finite)


def _audit_mimo_rank_coverage_table(
    path: str,
    header: list[str],
    rows: list[dict[str, str]],
    beam_rows: list[dict[str, str]],
    *,
    histogram: bool,
) -> list[AuditCheck]:
    required = {
        "direction", "cell_id", "rank_or_layer_count", "trial_row_count",
        "utilization_fraction", "source_artifact_ref", "producer_module",
        "status_code", "status_classification", "derived_flag", "active_flag",
    }
    if histogram:
        required.add("histogram_definition")
    checks = [_check(
        "mimo_companion", path, "required_columns", rows,
        sorted(required - set(header)),
    )]
    groups: dict[tuple[str, str, str], list[dict[str, str]]] = {}
    denominators: dict[tuple[str, str], int] = {}
    for source in beam_rows:
        rank = _number(source, "precoding_num_layers")
        if rank is None:
            continue
        direction = _text(source, "direction").upper() or "NOT_AVAILABLE"
        cell = _group_key_number(_number(source, "cell_id"))
        groups.setdefault((direction, cell, _group_key_number(rank)), []).append(source)
        denominators[(direction, cell)] = denominators.get((direction, cell), 0) + 1
    failures: list[str] = []
    if len(rows) != len(groups):
        failures.append(f"row_count_mismatch:{len(rows)}!={len(groups)}")
    for index, (row, (key, subset)) in enumerate(zip(rows, groups.items()), start=1):
        direction, cell, rank_token = key
        prefix = f"row={index}"
        expected = {
            "cell_id": _number(subset[0], "cell_id"),
            "rank_or_layer_count": _number(subset[0], "precoding_num_layers"),
            "trial_row_count": float(len(subset)),
            "utilization_fraction": len(subset) / max(denominators[(direction, cell)], 1),
        }
        if _text(row, "direction").upper() != direction:
            failures.append(prefix + ":direction_group_mismatch")
        for field, value in expected.items():
            if not _optional_number_equal(_number(row, field), value, atol=1e-12):
                failures.append(prefix + f":{field}_aggregate_mismatch")
        exact = {
            "source_artifact_ref": "beamforming/csv/beam_precoder_table.csv",
            "producer_module": (
                "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildRankLayerUsageHistogram"
                if histogram else
                "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildMIMORankUtilizationTable"
            ),
            "status_code": "implemented",
            "status_classification": (
                "derived_rank_layer_histogram" if histogram else "derived_mimo_rank_utilization"
            ),
        }
        for field, value in exact.items():
            if _text(row, field) != value:
                failures.append(prefix + f":{field}_invalid")
        if histogram and _text(row, "histogram_definition") != (
            "rank/layer usage histogram from runtime beam-precoder rows"
        ):
            failures.append(prefix + ":histogram_definition_invalid")
        if _boolean(row, "derived_flag") is not True or _boolean(row, "active_flag") is not True:
            failures.append(prefix + ":finalization_flags_invalid")
    checks.append(_check(
        "mimo_companion", path,
        "rank_histogram_recomputed_from_precoder_rows" if histogram
        else "rank_utilization_recomputed_from_precoder_rows",
        rows, failures,
    ))
    return checks


def _rows_by_direction(rows: list[dict[str, str]]) -> dict[str, dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    for row in rows:
        direction = _text(row, "Direction").upper()
        if direction in {"DL", "UL"} and direction not in result:
            result[direction] = row
    return result


def _audit_mimo_antenna_array_table(
    path: str,
    header: list[str],
    rows: list[dict[str, str]],
    rank_rows: list[dict[str, str]],
    config_rows: list[dict[str, str]],
) -> list[AuditCheck]:
    required = {
        "RunId", "ScenarioName", "Direction", "ArrayGeometryId",
        "PhysicalTxAntennaCount", "PhysicalRxAntennaCount", "TxRFChainCount",
        "RxRFChainCount", "TxAntennaPortCount", "RxAntennaPortCount",
        "ObservedTxPortCount", "ObservedRxAntennaCount", "RuntimePopulated",
        "FullElementDomainRequired", "ExpectedRuntimeTxCount", "ExpectedRuntimeRxCount",
        "ExactRuntimeAntennaMatch", "ObservedPhysicalTxAntennaCount",
        "ObservedPhysicalRxAntennaCount", "ObservedLogicalTxPortCount",
        "ObservedLogicalRxBranchCount", "LogicalPortLayerMatch",
        "RuntimeAntennaObjectCreated", "ChannelUsesSameRuntimeAntennaAssumptions",
        "NominalCapabilityOnly", "EvidenceClass", "RuntimeEvidenceSource",
        "SourceHash", "Status", "FailureReason",
    }
    checks = [_check(
        "mimo_companion", path, "required_columns", rows,
        sorted(required - set(header)),
    )]
    configs = _rows_by_direction(config_rows)
    failures: list[str] = []
    if len(rows) != len(configs) or len(rows) != len({_text(row, "Direction").upper() for row in rows}):
        failures.append("direction_rows_not_exactly_one_per_config_direction")
    for index, row in enumerate(rows, start=1):
        direction = _text(row, "Direction").upper()
        prefix = f"row={index}:{direction or 'missing'}"
        config = configs.get(direction)
        subset = [item for item in rank_rows if _text(item, "Direction").upper() == direction]
        if config is None:
            failures.append(prefix + ":missing_config_source")
            continue
        copy_numbers = (
            "PhysicalTxAntennaCount", "PhysicalRxAntennaCount", "TxRFChainCount",
            "RxRFChainCount", "TxAntennaPortCount", "RxAntennaPortCount",
        )
        for field in copy_numbers:
            if not _optional_number_equal(_number(row, field), _number(config, field)):
                failures.append(prefix + f":{field}_not_config_source")
        if _text(row, "RunId") != _text(config, "RunId") or _text(row, "ScenarioName") != _text(config, "ScenarioName"):
            failures.append(prefix + ":run_identity_not_config_source")
        if _text(row, "ArrayGeometryId") != "scenario_config_array_counts":
            failures.append(prefix + ":ArrayGeometryId_invalid")
        observed_tx_ports = _mode_number(subset, "NumTxPorts")
        if observed_tx_ports is None:
            observed_tx_ports = _mode_number(subset, "TransmittedLayers")
        observed_rx = _mode_number(subset, "NumRxAntennas")
        if observed_rx is None:
            observed_rx = _mode_number(subset, "EffectiveDecodedLayers")
        logical_tx = _mode_number(subset, "LogicalTxPortCount")
        if logical_tx is None:
            logical_tx = _mode_number(subset, "TransmittedLayers")
        logical_rx = _mode_number(subset, "LogicalRxBranchCount")
        if logical_rx is None:
            logical_rx = _mode_number(subset, "EffectiveDecodedLayers")
        if direction == "UL":
            physical_tx = _mode_first_available(subset, ("TxWaveformColumns", "PhysicalTxAntennas", "UEAntennaElements", "UEAntennaNumPorts"))
            physical_rx = _mode_first_available(subset, ("RxWaveformBranches", "PhysicalRxAntennas", "BSAntennaElements", "BSAntennaNumPorts"))
        else:
            physical_tx = _mode_first_available(subset, ("TxWaveformColumns", "PhysicalTxAntennas", "BSAntennaElements", "BSAntennaNumPorts"))
            physical_rx = _mode_first_available(subset, ("RxWaveformBranches", "PhysicalRxAntennas", "NumRxAntennas", "UEAntennaElements", "UEAntennaNumPorts"))
        expected_numbers = {
            "ObservedTxPortCount": observed_tx_ports,
            "ObservedRxAntennaCount": observed_rx,
            "ObservedPhysicalTxAntennaCount": physical_tx,
            "ObservedPhysicalRxAntennaCount": physical_rx,
            "ObservedLogicalTxPortCount": logical_tx,
            "ObservedLogicalRxBranchCount": logical_rx,
        }
        for field, expected in expected_numbers.items():
            if not _optional_number_equal(_number(row, field), expected):
                failures.append(prefix + f":{field}_not_rank_source")
        runtime = bool(subset)
        full_element = _boolean(config, "FullElementDomainRequired") is True
        expected_tx = _number(config, "PhysicalTxAntennaCount" if full_element else "TxAntennaPortCount")
        expected_rx = _number(config, "PhysicalRxAntennaCount" if full_element else "RxAntennaPortCount")
        runtime_object = runtime and all(_boolean(item, "AntennaRuntimeObjectCreated") is True for item in subset)
        same_assumptions = runtime and all(_boolean(item, "ChannelUsesSameRuntimeAntennaAssumptions") is True for item in subset)
        configured_layers = _number(config, "ConfiguredLayers")
        logical_match = bool(
            runtime and logical_tx is not None and logical_rx is not None
            and configured_layers is not None and logical_tx == configured_layers
            and logical_rx >= configured_layers
        )
        exact_match = logical_match
        if full_element:
            exact_match = bool(
                runtime and physical_tx == expected_tx and physical_rx == expected_rx
                and logical_match and runtime_object and same_assumptions
            )
        expected_booleans = {
            "RuntimePopulated": runtime, "FullElementDomainRequired": full_element,
            "ExactRuntimeAntennaMatch": exact_match, "LogicalPortLayerMatch": logical_match,
            "RuntimeAntennaObjectCreated": runtime_object,
            "ChannelUsesSameRuntimeAntennaAssumptions": same_assumptions,
            "NominalCapabilityOnly": not runtime,
        }
        for field, expected in expected_booleans.items():
            if _boolean(row, field) is not expected:
                failures.append(prefix + f":{field}_formula_mismatch")
        for field, expected in (("ExpectedRuntimeTxCount", expected_tx), ("ExpectedRuntimeRxCount", expected_rx)):
            if not _optional_number_equal(_number(row, field), expected):
                failures.append(prefix + f":{field}_formula_mismatch")
        evidence = "CONFIGURATION_WITH_DIRECT_RUNTIME_TRIAL_EVIDENCE" if runtime else "CONFIGURATION_ONLY"
        runtime_source = "rank_layer_trials_from_air_interface_raw_trials" if runtime else ""
        if _text(row, "EvidenceClass") != evidence or _text(row, "RuntimeEvidenceSource") != runtime_source:
            failures.append(prefix + ":evidence_class_or_source_invalid")
        if _text(row, "SourceHash") != _text(config, "ConfigHash") or not _is_sha256(_text(row, "SourceHash")):
            failures.append(prefix + ":SourceHash_not_config_hash")
        if _text(row, "Status").lower() != ("pass" if exact_match else "fail"):
            failures.append(prefix + ":Status_formula_mismatch")
        if exact_match != (not bool(_text(row, "FailureReason"))):
            failures.append(prefix + ":FailureReason_formula_mismatch")
    checks.append(_check(
        "mimo_companion", path, "antenna_execution_domain_recomputed_from_rank_trials",
        rows, failures,
    ))
    return checks


def _audit_mimo_antenna_port_mapping_table(
    path: str,
    header: list[str],
    rows: list[dict[str, str]],
    rank_rows: list[dict[str, str]],
    config_rows: list[dict[str, str]],
) -> list[AuditCheck]:
    required = {
        "RunId", "ScenarioName", "Direction", "TxAntennaPortCount",
        "RxAntennaPortCount", "DMRSPorts", "DMRSPortCount", "ConfiguredLayers",
        "ObservedTransmittedLayers", "ObservedEffectiveDecodedLayers",
        "MappingEvidenceSource", "SourceRowsHash", "Status", "FailureReason",
    }
    checks = [_check("mimo_companion", path, "required_columns", rows, sorted(required - set(header)))]
    configs = _rows_by_direction(config_rows)
    failures: list[str] = []
    if len(rows) != len(configs):
        failures.append(f"row_count_mismatch:{len(rows)}!={len(configs)}")
    for index, row in enumerate(rows, start=1):
        direction = _text(row, "Direction").upper()
        prefix = f"row={index}:{direction or 'missing'}"
        config = configs.get(direction)
        subset = [item for item in rank_rows if _text(item, "Direction").upper() == direction]
        if config is None:
            failures.append(prefix + ":missing_config_source")
            continue
        for field in ("TxAntennaPortCount", "RxAntennaPortCount", "DMRSPortCount", "ConfiguredLayers"):
            if not _optional_number_equal(_number(row, field), _number(config, field)):
                failures.append(prefix + f":{field}_not_config_source")
        if _text(row, "DMRSPorts") != _text(config, "DMRSPorts"):
            failures.append(prefix + ":DMRSPorts_not_config_source")
        if _text(row, "RunId") != _text(config, "RunId") or _text(row, "ScenarioName") != _text(config, "ScenarioName"):
            failures.append(prefix + ":run_identity_not_config_source")
        transmitted = _mode_number(subset, "TransmittedLayers")
        decoded = _mode_number(subset, "EffectiveDecodedLayers")
        if not _optional_number_equal(_number(row, "ObservedTransmittedLayers"), transmitted):
            failures.append(prefix + ":ObservedTransmittedLayers_not_rank_source")
        if not _optional_number_equal(_number(row, "ObservedEffectiveDecodedLayers"), decoded):
            failures.append(prefix + ":ObservedEffectiveDecodedLayers_not_rank_source")
        expected_source = "air_interface/csv/dl_pdsch_trials.csv" if direction == "DL" else "air_interface/csv/ul_pusch_trials.csv"
        if _text(row, "MappingEvidenceSource") != expected_source:
            failures.append(prefix + ":MappingEvidenceSource_invalid")
        expected_hash = _text(subset[0], "SourceRowsHash") if subset else "empty"
        if _text(row, "SourceRowsHash") != expected_hash:
            failures.append(prefix + ":SourceRowsHash_not_rank_source")
        ok = bool(subset and transmitted is not None and transmitted <= (_number(config, "DMRSPortCount") or -1))
        if _text(row, "Status").lower() != ("pass" if ok else "fail"):
            failures.append(prefix + ":Status_formula_mismatch")
        if ok != (not bool(_text(row, "FailureReason"))):
            failures.append(prefix + ":FailureReason_formula_mismatch")
    checks.append(_check(
        "mimo_companion", path, "antenna_port_mapping_recomputed_from_config_and_rank_trials",
        rows, failures,
    ))
    return checks


def _audit_mimo_config_validation_table(
    path: str,
    header: list[str],
    rows: list[dict[str, str]],
    config_rows: list[dict[str, str]],
) -> list[AuditCheck]:
    required = {"RunId", "ScenarioName", "Direction", "ValidationRule", "Pass", "Status", "FailureReason", "ConfigHash"}
    checks = [_check("mimo_companion", path, "required_columns", rows, sorted(required - set(header)))]
    rules = (
        "physical_antenna_counts_present", "antenna_ports_present",
        "configured_rank_supported_by_ports", "configured_layers_supported_by_ports",
        "dmrs_ports_cover_layers", "unsupported_codebook_modes_fail_closed",
    )
    reason_by_rule = {
        "physical_antenna_counts_present": "physical_tx_rx_antenna_counts_missing",
        "antenna_ports_present": "tx_rx_antenna_ports_missing",
        "configured_rank_supported_by_ports": "configured_rank_exceeds_tx_rx_dmrs_port_support",
        "configured_layers_supported_by_ports": "configured_layers_exceed_tx_rx_dmrs_port_support",
        "dmrs_ports_cover_layers": "dmrs_port_count_less_than_configured_layers",
        "unsupported_codebook_modes_fail_closed": "unsupported_codebook_or_multipanel_mode",
    }
    expected: list[tuple[dict[str, str], str, bool]] = []
    for config in config_rows:
        values = [
            _number(config, field) for field in (
                "PhysicalTxAntennaCount", "PhysicalRxAntennaCount", "TxRFChainCount",
                "RxRFChainCount", "TxAntennaPortCount", "RxAntennaPortCount", "DMRSPortCount",
            )
        ]
        supported = min(values) if all(value is not None for value in values) else None
        codebook = (_text(config, "CodebookType") + "|" + _text(config, "CodebookMode")).lower()
        passes = (
            _number(config, "PhysicalTxAntennaCount") is not None and _number(config, "PhysicalRxAntennaCount") is not None,
            _number(config, "TxAntennaPortCount") is not None and _number(config, "RxAntennaPortCount") is not None,
            supported is not None and (_number(config, "ConfiguredRank") or math.inf) <= supported,
            supported is not None and (_number(config, "ConfiguredLayers") or math.inf) <= supported,
            (_number(config, "DMRSPortCount") or -math.inf) >= (_number(config, "ConfiguredLayers") or math.inf),
            not any(token in codebook for token in ("typeii", "multi-panel", "multipanel")),
        )
        expected.extend((config, rule, passed) for rule, passed in zip(rules, passes))
    failures: list[str] = []
    if len(rows) != len(expected):
        failures.append(f"row_count_mismatch:{len(rows)}!={len(expected)}")
    for index, (row, expected_item) in enumerate(zip(rows, expected), start=1):
        config, rule, passed = expected_item
        prefix = f"row={index}:{rule}"
        for field in ("RunId", "ScenarioName", "Direction", "ConfigHash"):
            if _text(row, field) != _text(config, field):
                failures.append(prefix + f":{field}_not_config_source")
        if _text(row, "ValidationRule") != rule:
            failures.append(prefix + ":ValidationRule_order_mismatch")
        if _boolean(row, "Pass") is not passed or _text(row, "Status").lower() != ("pass" if passed else "fail"):
            failures.append(prefix + ":pass_status_formula_mismatch")
        expected_reason = "" if passed else reason_by_rule[rule]
        if _text(row, "FailureReason") != expected_reason:
            failures.append(prefix + ":FailureReason_formula_mismatch")
    checks.append(_check(
        "mimo_companion", path, "strict_config_rules_recomputed_from_mimo_config",
        rows, failures,
    ))
    return checks


def _audit_mimo_config_strict_table(
    path: str,
    header: list[str],
    rows: list[dict[str, str]],
    rank_rows: list[dict[str, str]],
    configured_rows: list[dict[str, str]],
    validation_rows: list[dict[str, str]],
) -> list[AuditCheck]:
    required = {
        "RunId", "ScenarioName", "Direction", "NCellID", "NSizeGrid",
        "SubcarrierSpacingKHz", "PhysicalTxAntennaCount", "PhysicalRxAntennaCount",
        "TxRFChainCount", "RxRFChainCount", "TxAntennaPortCount", "RxAntennaPortCount",
        "FullElementDomainRequired", "DMRSPorts", "DMRSPortCount", "ConfiguredRank",
        "ConfiguredLayers", "ConfiguredCodewords", "ConfiguredModulation", "ConfiguredMCS",
        "ConfiguredInitialMCS", "ConfiguredMaximumMCS", "ConfiguredMCSSelectionPolicy",
        "ConfiguredMUMIMOEnabled", "ConfiguredMUUsersPerPRB",
        "ConfiguredMUMIMOLeakageThreshold_dB", "ConfiguredMUMIMOExecutionMode",
        "ConfiguredMCSTable", "ConfiguredTransmissionScheme", "CodebookType",
        "ConfiguredPMI", "FixedAnchorMode", "AdaptiveMode", "RankSelectionSource",
        "PrecoderSelectionSource", "BeamSelectionSource", "StrictUnsupportedReason",
        "ConfigHash", "Status", "RuntimePopulated", "RuntimeTrialCount",
        "RuntimeRank2Fraction", "RuntimeExactMatchFraction", "RuntimeEvidenceSource",
        "EvidenceClass",
    }
    checks = [_check("mimo_companion", path, "required_columns", rows, sorted(required - set(header)))]
    configured = _rows_by_direction(configured_rows)
    failures: list[str] = []
    observed_directions = [_text(row, "Direction").upper() for row in rows]
    expected_directions = {_text(row, "Direction").upper() for row in rank_rows if _text(row, "Direction").upper() in {"DL", "UL"}}
    if set(observed_directions) != expected_directions or len(observed_directions) != len(set(observed_directions)):
        failures.append("direction_rows_not_exactly_one_per_runtime_direction")
    for index, row in enumerate(rows, start=1):
        direction = _text(row, "Direction").upper()
        prefix = f"row={index}:{direction or 'missing'}"
        subset = [item for item in rank_rows if _text(item, "Direction").upper() == direction and _boolean(item, "StrictEligible") is True]
        summary = configured.get(direction)
        if not subset or summary is None:
            failures.append(prefix + ":missing_rank_or_configured_effective_source")
            continue
        expected_modes = {
            "ConfiguredRank": _mode_number(subset, "ConfiguredRank"),
            "ConfiguredLayers": _mode_number(subset, "ConfiguredLayers"),
            "ConfiguredMCS": _mode_number(subset, "ConfiguredMCS"),
            "ConfiguredInitialMCS": _mode_number(subset, "ConfiguredInitialMCS"),
            "ConfiguredMaximumMCS": _mode_number(subset, "ConfiguredMaximumMCS"),
        }
        for field, expected in expected_modes.items():
            if not _optional_number_equal(_number(row, field), expected):
                failures.append(prefix + f":{field}_not_rank_source")
        expected_text = {
            "ConfiguredModulation": _mode_text(subset, "ConfiguredModulation"),
            "ConfiguredMCSSelectionPolicy": _mode_text(subset, "ConfiguredMCSSelectionPolicy"),
            "DMRSPorts": _mode_text(subset, "DMRSPorts"),
        }
        for field, expected in expected_text.items():
            if _text(row, field) != expected:
                failures.append(prefix + f":{field}_not_rank_source")
        if _text(row, "RunId") != _text(subset[0], "RunId") or _text(row, "ScenarioName") != _text(subset[0], "ScenarioName"):
            failures.append(prefix + ":run_identity_not_rank_source")
        count = len(subset)
        rank2_fraction = sum(
            _number(item, "TransmittedRank") == 2 or _number(item, "EffectiveDecodedRank") == 2
            for item in subset
        ) / count
        exact_fraction = sum(_boolean(item, "ExactConfiguredMatch") is True for item in subset) / count
        if _boolean(row, "RuntimePopulated") is not True or _number(row, "RuntimeTrialCount") != count:
            failures.append(prefix + ":runtime_population_mismatch")
        if not _close(_number(row, "RuntimeRank2Fraction"), rank2_fraction, atol=1e-12):
            failures.append(prefix + ":RuntimeRank2Fraction_mismatch")
        if not _close(_number(row, "RuntimeExactMatchFraction"), exact_fraction, atol=1e-12):
            failures.append(prefix + ":RuntimeExactMatchFraction_mismatch")
        if _text(row, "RuntimeEvidenceSource") != "rank_layer_trials_from_air_interface_raw_trials" or _text(row, "EvidenceClass") != "CONFIGURATION_WITH_DIRECT_RUNTIME_TRIAL_EVIDENCE":
            failures.append(prefix + ":runtime_evidence_invalid")
        for field in ("ConfiguredMCSTable", "ConfiguredTransmissionScheme", "CodebookType", "RankSelectionSource", "PrecoderSelectionSource", "BeamSelectionSource"):
            if not _text(row, field):
                failures.append(prefix + f":{field}_missing")
        if _number(row, "NCellID") is None or (_number(row, "NSizeGrid") or 0) <= 0 or (_number(row, "SubcarrierSpacingKHz") or 0) <= 0:
            failures.append(prefix + ":carrier_configuration_invalid")
        layers = _number(row, "ConfiguredLayers")
        expected_codewords = None if layers is None else (1 if layers <= 4 else 2)
        if not _optional_number_equal(_number(row, "ConfiguredCodewords"), expected_codewords):
            failures.append(prefix + ":ConfiguredCodewords_formula_mismatch")
        adaptive = all(_boolean(item, "AdaptiveMode") is True for item in subset)
        fixed_anchor = all(_boolean(item, "FixedAnchorMode") is True for item in subset)
        mu_required = any(_boolean(item, "MUExecutionRequired") is True for item in subset)
        expected_bools = {
            "AdaptiveMode": adaptive, "FixedAnchorMode": fixed_anchor,
            "ConfiguredMUMIMOEnabled": mu_required,
        }
        for field, expected in expected_bools.items():
            if _boolean(row, field) is not expected:
                failures.append(prefix + f":{field}_not_rank_source")
        if not _optional_number_equal(_number(row, "ConfiguredMUUsersPerPRB"), _mode_number(subset, "RequiredMUUserCount")):
            failures.append(prefix + ":ConfiguredMUUsersPerPRB_not_rank_source")
        if not _optional_number_equal(_number(row, "ConfiguredMUMIMOLeakageThreshold_dB"), _mode_number(subset, "RequiredMULeakageThreshold_dB")):
            failures.append(prefix + ":ConfiguredMUMIMOLeakageThreshold_not_rank_source")
        if _text(row, "ConfiguredMUMIMOExecutionMode") != _mode_text(subset, "RequiredMUExecutionMode"):
            failures.append(prefix + ":ConfiguredMUMIMOExecutionMode_not_rank_source")
        audit_subset = [item for item in validation_rows if _text(item, "Direction").upper() == direction]
        expected_pass = _boolean(summary, "ScenarioObjectivePass") is True and bool(audit_subset) and all(_boolean(item, "Pass") is True for item in audit_subset)
        if _text(row, "Status").lower() != ("pass" if expected_pass else "fail"):
            failures.append(prefix + ":Status_not_runtime_validation_reduction")
        if expected_pass and _text(row, "StrictUnsupportedReason"):
            failures.append(prefix + ":passing_config_has_StrictUnsupportedReason")
        if not _is_sha256(_text(row, "ConfigHash")):
            failures.append(prefix + ":ConfigHash_invalid")
        if any(_text(item, "ConfigHash") != _text(row, "ConfigHash") for item in audit_subset):
            failures.append(prefix + ":ConfigHash_not_validation_source")
    checks.append(_check(
        "mimo_companion", path, "strict_config_runtime_summary_and_status_recomputed",
        rows, failures,
    ))
    return checks


def _audit_mimo_companion_outputs(
    run_root: Path,
    link_rows: dict[str, list[dict[str, str]]],
) -> list[AuditCheck]:
    _rank_header, rank_rows = _read_rows(run_root / MIMO_RANK_LAYER_TABLE)
    if not rank_rows:
        return []
    table_rows = {
        relative: _read_rows(run_root / relative)
        for relative in MIMO_COMPANION_TABLES
    }
    config_rows = table_rows["beamforming/csv/mimo_config_strict.csv"][1]
    configured_rows = table_rows["beamforming/csv/mimo_configured_vs_effective.csv"][1]
    validation_rows = table_rows["beamforming/csv/mimo_config_validation.csv"][1]
    beam_rows = table_rows["beamforming/csv/beam_precoder_table.csv"][1]
    checks: list[AuditCheck] = []
    for relative in MIMO_COMPANION_TABLES:
        header, rows = table_rows[relative]
        if not header and not rows:
            continue
        if relative.endswith("antenna_array_config.csv"):
            checks.extend(_audit_mimo_antenna_array_table(
                relative, header, rows, rank_rows, config_rows
            ))
        elif relative.endswith("antenna_port_mapping.csv"):
            checks.extend(_audit_mimo_antenna_port_mapping_table(
                relative, header, rows, rank_rows, config_rows
            ))
        elif relative.endswith("beam_precoder_table.csv"):
            checks.extend(_audit_beam_precoder_table(
                relative, header, rows, link_rows
            ))
        elif relative.endswith("beamforming_analytics_table.csv"):
            checks.extend(_audit_beamforming_analytics_table(
                relative, header, rows, beam_rows
            ))
        elif relative.endswith("mimo_config_strict.csv"):
            checks.extend(_audit_mimo_config_strict_table(
                relative, header, rows, rank_rows, configured_rows, validation_rows
            ))
        elif relative.endswith("mimo_config_validation.csv"):
            checks.extend(_audit_mimo_config_validation_table(
                relative, header, rows, config_rows
            ))
        elif relative.endswith("mimo_configured_vs_effective.csv"):
            checks.extend(_audit_mimo_configured_effective_table(
                relative, header, rows, rank_rows
            ))
        elif relative.endswith("mimo_layer_metrics.csv"):
            checks.extend(_audit_mimo_layer_metrics_table(
                relative, header, rows, rank_rows
            ))
        elif relative.endswith("beam_codebook.csv"):
            checks.extend(_audit_mimo_beam_codebook_table(
                relative, header, rows, rank_rows
            ))
        elif relative.endswith("mimo_rank_utilization_table.csv"):
            checks.extend(_audit_mimo_rank_coverage_table(
                relative, header, rows, beam_rows, histogram=False
            ))
        elif relative.endswith("rank_layer_usage_histogram.csv"):
            checks.extend(_audit_mimo_rank_coverage_table(
                relative, header, rows, beam_rows, histogram=True
            ))
        else:
            checks.extend(_audit_mimo_per_trial_companion(
                relative, header, rows, rank_rows
            ))
    return checks


def _audit_dl_protocol_decisions(run_root: Path, link_rows: dict[str, list[dict[str, str]]]) -> list[AuditCheck]:
    header, rows = _read_rows(run_root / DL_PROTOCOL_DECISIONS)
    if not header:
        return []
    required = {
        "ContractVersion", "UEId", "RNTI", "HARQProcess", "NDI", "ControlAbsoluteSlot",
        "DataAbsoluteSlot", "ReceivedAssignmentDigest", "PriorAcknowledgedAssignmentDigest",
        "PriorAcknowledgedDataAbsoluteSlot", "InitialAssignmentDigest", "RetainedTBSBits",
        "ACK", "DecodeAttempted", "DeliverTransportBlock", "FeedbackTransmissionQualified",
        "Source", "ControlAvailableAtSample", "DecisionAvailableAtSample", "SampleRateHz",
        "HARQFeedbackAbsoluteSlot", "PUCCHResourceIndicator",
    }
    checks = [_check("harq_protocol", DL_PROTOCOL_DECISIONS, "required_columns", rows,
                     sorted(required - set(header)))]
    failures: list[str] = []
    forbidden = {"CRCPass", "SINR_dB", "EVM_pct", "TimingOffsetSamples", "DataDecodeAvailableAtSample"}
    failures.extend(f"current_measurement_column:{name}" for name in sorted(forbidden & set(header)))
    trials: dict[str, list[dict[str, str]]] = {}
    for trial in link_rows.get("DL", []):
        trials.setdefault(trial.get("ReceivedAssignmentDigest", ""), []).append(trial)
    seen: dict[str, dict[str, str]] = {}
    for index, row in enumerate(rows, 1):
        prefix = f"row{index}"
        digest = row.get("ReceivedAssignmentDigest", "")
        for key in ("ReceivedAssignmentDigest", "PriorAcknowledgedAssignmentDigest", "InitialAssignmentDigest"):
            value = row.get(key, "")
            if len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
                failures.append(f"{prefix}:invalid_digest:{key}")
        if digest in seen or digest in trials:
            failures.append(f"{prefix}:duplicate_or_new_decode_for_protocol_assignment")
        if (row.get("ContractVersion") != "received_dl_retained_ack/v1" or
                row.get("Source") != "received_dci_and_ue_retained_decoded_tb" or
                _number(row, "ACK") != 1 or any(_number(row, key) != 0 for key in
                ("DecodeAttempted", "DeliverTransportBlock", "FeedbackTransmissionQualified"))):
            failures.append(f"{prefix}:invalid_protocol_disposition")
        integers = ("UEId", "RNTI", "HARQProcess", "NDI", "ControlAbsoluteSlot", "DataAbsoluteSlot",
                    "PriorAcknowledgedDataAbsoluteSlot", "RetainedTBSBits", "ControlAvailableAtSample",
                    "DecisionAvailableAtSample", "HARQFeedbackAbsoluteSlot", "PUCCHResourceIndicator")
        values = {key: _number(row, key) for key in integers}
        if any(v is None or v < 0 or not v.is_integer() for v in values.values()):
            failures.append(f"{prefix}:invalid_integer_domain")
        elif not (values["UEId"] >= 1 and values["RNTI"] >= 1 and values["NDI"] in (0, 1) and
                  values["RetainedTBSBits"] > 0 and values["RetainedTBSBits"] % 8 == 0 and
                  values["ControlAbsoluteSlot"] <= values["DataAbsoluteSlot"] and
                  values["PriorAcknowledgedDataAbsoluteSlot"] < values["DataAbsoluteSlot"] and
                  values["HARQFeedbackAbsoluteSlot"] >= values["DataAbsoluteSlot"] and
                  values["ControlAvailableAtSample"] <= values["DecisionAvailableAtSample"] and
                  (_number(row, "SampleRateHz") or 0) > 0):
            failures.append(f"{prefix}:invalid_causal_or_payload_domain")
        initial = trials.get(row.get("InitialAssignmentDigest", ""), [])
        if len(initial) != 1:
            failures.append(f"{prefix}:missing_unique_initial_decode_lineage")
        else:
            first = initial[0]
            mapping = {"UEId": "UEIndex", "RNTI": "RNTI", "HARQProcess": "HARQProcess", "NDI": "NDI",
                       "RetainedTBSBits": "TBSize_bits"}
            first_slot = _number(first, "Slot")
            prior_slot = _number(row, "PriorAcknowledgedDataAbsoluteSlot")
            if (any(_number(row, k) != _number(first, v) for k, v in mapping.items()) or
                    first_slot is None or prior_slot is None or first_slot - 1 > prior_slot):
                failures.append(f"{prefix}:initial_decode_identity_mismatch")
        prior_digest = row.get("PriorAcknowledgedAssignmentDigest", "")
        prior_protocol = seen.get(prior_digest)
        prior_trials = trials.get(prior_digest, [])
        if prior_protocol is not None:
            mappings = {"UEId": "UEId", "RNTI": "RNTI", "HARQProcess": "HARQProcess", "NDI": "NDI",
                        "RetainedTBSBits": "RetainedTBSBits", "PriorAcknowledgedDataAbsoluteSlot": "DataAbsoluteSlot"}
            if (any(_number(row, k) != _number(prior_protocol, v) for k, v in mappings.items()) or
                    row.get("InitialAssignmentDigest") != prior_protocol.get("InitialAssignmentDigest") or
                    (_number(prior_protocol, "DecisionAvailableAtSample") or 0) >
                    (_number(row, "DecisionAvailableAtSample") or 0)):
                failures.append(f"{prefix}:prior_protocol_identity_or_clock_mismatch")
        elif len(prior_trials) == 1:
            prior = prior_trials[0]
            mappings = {"UEId": "UEIndex", "RNTI": "RNTI", "HARQProcess": "HARQProcess", "NDI": "NDI",
                        "RetainedTBSBits": "TBSize_bits"}
            slot = _number(prior, "Slot")
            available = _number(prior, "DataDecodeAvailableAtSample")
            if (any(_number(row, k) != _number(prior, v) for k, v in mappings.items()) or
                    _number(prior, "CRCPass") != 1 or slot is None or
                    _number(row, "PriorAcknowledgedDataAbsoluteSlot") != slot - 1 or
                    available is None or available > (_number(row, "DecisionAvailableAtSample") or 0)):
                failures.append(f"{prefix}:prior_decode_identity_or_clock_mismatch")
        else:
            failures.append(f"{prefix}:missing_unique_prior_ACK_lineage")
        seen[digest] = row
    checks.append(_check("harq_protocol", DL_PROTOCOL_DECISIONS,
                         "retained_ACK_identity_clock_and_no_duplicate_decode", rows, failures))
    return checks


def _audit_harq_observation_tables(
    run_root: Path,
    link_rows: dict[str, list[dict[str, str]]],
) -> list[AuditCheck]:
    timeline_header, timeline_rows = _read_rows(run_root / HARQ_OBSERVATION_TIMELINE)
    summary_header, summary_rows = _read_rows(run_root / HARQ_OBSERVATION_SUMMARY)
    if not timeline_header and not summary_header:
        return []
    timeline_required = {
        "Direction", "TraceSource", "SNR_dB", "Frame", "Slot", "CRCPass",
        "Status", "Crash", "GoodBits", "OfferedBits", "Goodput_Mbps",
        "ReceiverHestSINR_dB", "RankIndicator", "Notes",
    }
    checks = [_check(
        "harq_runtime", HARQ_OBSERVATION_TIMELINE, "required_columns",
        timeline_rows, sorted(timeline_required - set(timeline_header)),
    )]
    expected: list[tuple[str, dict[str, str]]] = []
    for direction in ("DL", "UL"):
        source = link_rows.get(direction, [])
        snr_order: list[float | None] = []
        for row in source:
            snr = _number(row, "SNR_dB")
            if snr not in snr_order:
                snr_order.append(snr)
        for snr in snr_order:
            expected.extend(
                (direction, row) for row in source
                if _optional_number_equal(_number(row, "SNR_dB"), snr, atol=1e-9)
            )
    failures: list[str] = []
    if len(timeline_rows) != len(expected):
        failures.append(f"row_count_mismatch:{len(timeline_rows)}!={len(expected)}")
    numeric_fields = {
        "SNR_dB": ("SNR_dB",), "Frame": ("Frame",), "Slot": ("Slot",),
        "CRCPass": ("CRCPass",), "Crash": ("Crash",), "GoodBits": ("GoodBits",),
        "OfferedBits": ("OfferedBits",), "Goodput_Mbps": ("Goodput_Mbps",),
        "ReceiverHestSINR_dB": ("ReceiverHestSINR_dB",),
        "DecoderTruthProxySINR_dB": ("DecoderTruthProxySINR_dB",),
        "WidebandCQI": ("WidebandCQI",), "CQIDerivedMCS": ("CQIDerivedMCS",),
        "CQIDerivedTargetCodeRate": ("CQIDerivedTargetCodeRate",),
        "PMI": ("PMI",), "CRI": ("CRI",), "RankIndicator": ("RankIndicator",),
    }
    for index, (row, expected_item) in enumerate(zip(timeline_rows, expected), start=1):
        direction, source = expected_item
        prefix = f"row={index}:{direction}"
        if _text(row, "Direction").upper() != direction:
            failures.append(prefix + ":Direction_order_mismatch")
        if _text(row, "TraceSource") != direction.lower() + "_raw_link_trials":
            failures.append(prefix + ":TraceSource_invalid")
        for target, aliases in numeric_fields.items():
            if target not in timeline_header and _number(source, *aliases) is None:
                continue
            if not _optional_number_equal(_number(row, target), _number(source, *aliases), atol=1e-9):
                failures.append(prefix + f":{target}_not_primary_source")
        for field in ("Status", "CQIDerivedModulation"):
            if field in timeline_header and _text(row, field) != _text(source, field):
                failures.append(prefix + f":{field}_not_primary_source")
        if _text(row, "Notes") != "Actual frame-level DL/UL decode outcome for live HARQ visibility.":
            failures.append(prefix + ":Notes_invalid")
    checks.append(_check(
        "harq_runtime", HARQ_OBSERVATION_TIMELINE,
        "ordered_observations_reconcile_primary_link_trials", timeline_rows, failures,
    ))

    summary_required = {
        "Direction", "TraceSource", "SNR_dB", "FramesObserved", "CRCPassRate",
        "CRCFailRate", "CrashRate", "MeanGoodput_Mbps", "Notes",
    }
    checks.append(_check(
        "harq_runtime", HARQ_OBSERVATION_SUMMARY, "required_columns",
        summary_rows, sorted(summary_required - set(summary_header)),
    ))
    summary_failures: list[str] = []
    direction_order: list[str] = []
    for row in timeline_rows:
        direction = _text(row, "Direction").upper()
        if direction and direction not in direction_order:
            direction_order.append(direction)
    if len(summary_rows) != len(direction_order):
        summary_failures.append(f"row_count_mismatch:{len(summary_rows)}!={len(direction_order)}")
    mean_fields = {
        "SNR_dB": "SNR_dB", "CRCPassRate": "CRCPass",
        "CrashRate": "Crash", "MeanGoodput_Mbps": "Goodput_Mbps",
        "MeanReceiverHestSINR_dB": "ReceiverHestSINR_dB",
        "MeanDecoderTruthProxySINR_dB": "DecoderTruthProxySINR_dB",
        "MeanMeasuredSINR_dB": "MeasuredSINR_dB", "MeanWidebandCQI": "WidebandCQI",
        "MeanCQIDerivedMCS": "CQIDerivedMCS",
    }
    for index, (row, direction) in enumerate(zip(summary_rows, direction_order), start=1):
        prefix = f"row={index}:{direction}"
        subset = [item for item in timeline_rows if _text(item, "Direction").upper() == direction]
        if _text(row, "Direction").upper() != direction:
            summary_failures.append(prefix + ":Direction_order_mismatch")
        expected_trace = _mode_text(subset, "TraceSource") or "runtime_harq_timeline"
        if _text(row, "TraceSource") != expected_trace:
            summary_failures.append(prefix + ":TraceSource_not_timeline_mode")
        if _number(row, "FramesObserved") != len(subset):
            summary_failures.append(prefix + ":FramesObserved_mismatch")
        for target, source_field in mean_fields.items():
            if target not in summary_header and all(_number(item, source_field) is None for item in subset):
                continue
            expected_mean = _finite_mean([_number(item, source_field) for item in subset])
            if not _optional_number_equal(_number(row, target), expected_mean, atol=1e-9):
                summary_failures.append(prefix + f":{target}_mean_mismatch")
        crc_mean = _finite_mean([_number(item, "CRCPass") for item in subset])
        expected_fail = None if crc_mean is None else 1.0 - crc_mean
        if not _optional_number_equal(_number(row, "CRCFailRate"), expected_fail, atol=1e-9):
            summary_failures.append(prefix + ":CRCFailRate_mismatch")
        if _text(row, "Notes") != "Live HARQ observation summary derived from the provided runtime HARQ timeline.":
            summary_failures.append(prefix + ":Notes_invalid")
    checks.append(_check(
        "harq_runtime", HARQ_OBSERVATION_SUMMARY,
        "direction_summary_recomputed_from_timeline", summary_rows, summary_failures,
    ))
    return checks


def _kpi_new_data(row: dict[str, str]) -> bool:
    explicit = _boolean(row, "NewDataFlag")
    if explicit is True:
        return True
    retransmission = _kpi_retransmission(row)
    rv = _number(row, "RV")
    return not retransmission and (rv is None or abs(rv) < 1e-12)


def _kpi_retransmission(row: dict[str, str]) -> bool:
    for field in ("RetransmissionFlag", "HARQIsRetransmission"):
        if _boolean(row, field) is True:
            return True
    rv = _number(row, "RV", "HARQRV")
    return rv is not None and abs(rv) > 1e-12


def _matlab_key_token(value: float | None) -> str:
    return "nan" if value is None else format(value, ".15g")


def _kpi_transport_block_keys(
    rows: list[dict[str, str]], direction: str
) -> list[str]:
    keys: list[str] = []
    active: dict[str, str] = {}
    instances: dict[str, int] = {}
    for row in rows:
        explicit = _text(row, "TransportBlockId", "TBId", "MACPDUId", "MACSDUId")
        if explicit:
            keys.append(explicit)
            continue
        ue = _number(row, "UEIndex", "UEId")
        rnti = _number(row, "RNTI")
        harq = _number(row, "HARQProcessId", "HARQProcess")
        ndi = _number(row, "NDI")
        codeword = _number(row, "Codeword", "CodewordIndex")
        if codeword is None:
            codeword = 0.0
        base = (
            f"derived_{direction}_ue{_matlab_key_token(ue)}"
            f"_rnti{_matlab_key_token(rnti)}"
            f"_harq{_matlab_key_token(harq)}"
            f"_ndi{_matlab_key_token(ndi)}"
            f"_cw{_matlab_key_token(codeword)}"
        )
        if base not in active or _kpi_new_data(row):
            instances[base] = instances.get(base, 0) + 1
            active[base] = f"{base}_tb{instances[base]}"
        keys.append(active[base])
    return keys


def _audit_kpi_delivery_direction(
    run_root: Path,
    direction: str,
    source_rows: list[dict[str, str]],
    source_path: str,
) -> list[AuditCheck]:
    paths = KPI_DELIVERY_TABLES[direction]
    trace_header, trace_rows = _read_rows(run_root / paths["trace"])
    ledger_header, ledger_rows = _read_rows(run_root / paths["ledger"])
    contribution_header, contribution_rows = _read_rows(run_root / paths["contributions"])
    if not trace_header and not ledger_header and not contribution_header:
        return []
    trace_required = {
        "RunId", "Direction", "UEId", "TransportBlockId", "Codeword",
        "AttemptIndex", "RV", "NDI", "NewDataFlag", "RetransmissionFlag",
        "ScheduledBits", "TBCrcPass", "DeliveredThisAttempt",
        "FirstSuccessDelivery", "DuplicateDelivery", "CountedGoodputBits",
        "DeliveryStatus", "Status", "FailureReason",
    }
    checks = [_check(
        "kpi_delivery", paths["trace"], "required_columns", trace_rows,
        sorted(trace_required - set(trace_header)),
    )]
    keys = _kpi_transport_block_keys(source_rows, direction)
    scheduled = [
        _number(row, "ScheduledBits", "TBSize_bits", "OfferedBits", "TBS") or 0.0
        for row in source_rows
    ]
    crc = [(_boolean(row, "TBCrcPass", "CRCPass") is not False) for row in source_rows]
    good_bits: list[float] = []
    for row, passed in zip(source_rows, crc):
        value = _number(row, "GoodputBits", "GoodBits", "DeliveredBits", "PayloadBits")
        if value is None and passed:
            value = _number(row, "TBSize_bits", "TBS", "ScheduledBits")
        good_bits.append(float(value or 0.0) if passed else 0.0)
    failures: list[str] = []
    if len(trace_rows) != len(source_rows):
        failures.append(f"row_count_mismatch:{len(trace_rows)}!={len(source_rows)}")
    delivered_keys: set[str] = set()
    for index, (row, source, key, scheduled_bits, bits, passed) in enumerate(
        zip(trace_rows, source_rows, keys, scheduled, good_bits, crc), start=1
    ):
        prefix = f"row={index}"
        delivered = passed and bits > 0
        duplicate = delivered and key in delivered_keys
        first = delivered and not duplicate
        counted = bits if first else 0.0
        if delivered:
            delivered_keys.add(key)
        expected_numbers = {
            "UEId": _number(source, "UEIndex", "UEId"),
            "Codeword": _number(source, "Codeword", "CodewordIndex") or 0.0,
            "AttemptIndex": float(index), "RV": _number(source, "RV"),
            "NDI": _number(source, "NDI"), "ScheduledBits": scheduled_bits,
            "CountedGoodputBits": counted,
        }
        for field, expected in expected_numbers.items():
            if not _optional_number_equal(_number(row, field), expected, atol=1e-9):
                failures.append(prefix + f":{field}_not_source_or_formula")
        if _text(row, "Direction").upper() != direction or _text(row, "TransportBlockId") != key:
            failures.append(prefix + ":direction_or_transport_block_identity_mismatch")
        expected_bools = {
            "NewDataFlag": _kpi_new_data(source),
            "RetransmissionFlag": _kpi_retransmission(source),
            "TBCrcPass": passed, "DeliveredThisAttempt": delivered,
            "FirstSuccessDelivery": first, "DuplicateDelivery": duplicate,
        }
        for field, expected in expected_bools.items():
            if _boolean(row, field) is not expected:
                failures.append(prefix + f":{field}_formula_mismatch")
        expected_status = (
            "duplicate_delivery_not_counted" if duplicate else
            "first_success_delivery_counted" if first else "not_delivered"
        )
        if _text(row, "DeliveryStatus") != expected_status:
            failures.append(prefix + ":DeliveryStatus_formula_mismatch")
        if _text(row, "Status") != "pass" or _text(row, "FailureReason"):
            failures.append(prefix + ":row_status_invalid")
        if _kpi_new_data(source) and not _text(source, "TransportBlockId", "TBId", "MACPDUId", "MACSDUId"):
            if _text(row, "TransportBlockId") == _text(source, "GrantContextId"):
                failures.append(prefix + ":grant_context_improperly_used_as_transport_block_identity")
    checks.append(_check(
        "kpi_delivery", paths["trace"],
        "tb_identity_deduplication_and_goodput_recomputed_from_primary_trials",
        trace_rows, failures,
    ))

    ledger_failures: list[str] = []
    if ledger_header != trace_header:
        ledger_failures.append("ledger_schema_not_trace_schema")
    if len(ledger_rows) != len(trace_rows):
        ledger_failures.append(f"row_count_mismatch:{len(ledger_rows)}!={len(trace_rows)}")
    for index, (ledger, trace) in enumerate(zip(ledger_rows, trace_rows), start=1):
        for field in trace_header:
            if _text(ledger, field) != _text(trace, field):
                ledger_failures.append(f"row={index}:{field}_not_trace_mirror")
    checks.extend([
        _check("kpi_delivery", paths["ledger"], "required_columns", ledger_rows, sorted(trace_required - set(ledger_header))),
        _check("kpi_delivery", paths["ledger"], "exact_harq_trace_mirror", ledger_rows, ledger_failures),
    ])

    contribution_required = {
        "RunId", "ScenarioName", "KPIName", "FormulaId", "Direction",
        "SourceTablePath", "SourceRowIndex", "UEId", "TrialId", "Slot", "Frame",
        "TransportBlockId", "RV", "NDI", "NewDataFlag", "RetransmissionFlag",
        "TBCrcPass", "ScheduledBitsContribution", "DeliveredBitsContribution",
        "GoodputBitsContribution", "DurationContributionSec",
        "MeasurementWindowContributionSec", "FirstSuccessDelivery",
        "DuplicateDelivery", "Included", "Status",
    }
    checks.append(_check(
        "kpi_delivery", paths["contributions"], "required_columns", contribution_rows,
        sorted(contribution_required - set(contribution_header)),
    ))
    contribution_failures: list[str] = []
    if len(contribution_rows) != len(source_rows):
        contribution_failures.append(f"row_count_mismatch:{len(contribution_rows)}!={len(source_rows)}")
    for index, (row, source, trace) in enumerate(zip(contribution_rows, source_rows, trace_rows), start=1):
        prefix = f"row={index}"
        exact_text = {
            "Direction": direction, "KPIName": direction + "_TB_Delivery_Goodput_Mbps",
            "FormulaId": direction + "_TB_Delivery_Goodput_Mbps",
            "SourceTablePath": source_path,
            "TransportBlockId": _text(trace, "TransportBlockId"), "Status": "pass",
        }
        for field, expected in exact_text.items():
            if _text(row, field) != expected:
                contribution_failures.append(prefix + f":{field}_mismatch")
        source_numbers = {
            "SourceRowIndex": float(index), "UEId": _number(source, "UEIndex", "UEId"),
            "TrialId": _number(source, "TrialId") or float(index),
            "Slot": _number(source, "Slot"), "Frame": _number(source, "Frame"),
            "RV": _number(source, "RV"), "NDI": _number(source, "NDI"),
            "ScheduledBitsContribution": _number(trace, "ScheduledBits"),
            "DeliveredBitsContribution": _number(trace, "CountedGoodputBits"),
            "GoodputBitsContribution": _number(trace, "CountedGoodputBits"),
        }
        for field, expected in source_numbers.items():
            if not _optional_number_equal(_number(row, field), expected, atol=1e-9):
                contribution_failures.append(prefix + f":{field}_mismatch")
        for field in (
            "NewDataFlag", "RetransmissionFlag", "TBCrcPass",
            "FirstSuccessDelivery", "DuplicateDelivery",
        ):
            if _boolean(row, field) is not _boolean(trace, field):
                contribution_failures.append(prefix + f":{field}_not_trace_source")
        if _boolean(row, "Included") is not True:
            contribution_failures.append(prefix + ":Included_not_true")
        duration = _number(row, "DurationContributionSec")
        measurement = _number(row, "MeasurementWindowContributionSec")
        if duration is None or duration <= 0 or measurement is None or measurement <= 0:
            contribution_failures.append(prefix + ":duration_contribution_invalid")
    checks.append(_check(
        "kpi_delivery", paths["contributions"],
        "row_contributions_reconcile_primary_trials_and_harq_trace",
        contribution_rows, contribution_failures,
    ))
    return checks


def _audit_kpi_delivery_outputs(
    run_root: Path,
    link_rows: dict[str, list[dict[str, str]]],
    source_paths: dict[str, str],
) -> list[AuditCheck]:
    checks: list[AuditCheck] = []
    _manifest_header, manifest_rows = _read_rows(
        run_root / "reports/csv/kpi_source_table_manifest.csv"
    )
    manifest_by_direction = {
        _text(row, "Direction").upper(): row for row in manifest_rows
    }
    for direction in ("DL", "UL"):
        source_path = source_paths[direction]
        source_rows = link_rows.get(direction, [])
        manifest = manifest_by_direction.get(direction, {})
        declared_path = _text(manifest, "SourceTablePath").replace("\\", "/")
        declared_file = _run_relative_path(run_root, declared_path)
        if declared_file is not None and _io_path(declared_file).is_file():
            _source_header, source_rows = _read_rows(declared_file)
            source_path = declared_path
        checks.extend(_audit_kpi_delivery_direction(
            run_root, direction, source_rows, source_path
        ))
    return checks


def _audit_frc_point_table(
    path: str, header: list[str], rows: list[dict[str, str]]
) -> list[AuditCheck]:
    required_columns = {
        "EntryId", "FRC", "Condition", "Direction", "PhysicalChannel",
        "Profile", "Metric", "RequiredSNR_dB", "TargetFraction", "SNR_dB",
        "RequiredPoint", "ExperimentSeed", "MetricEstimate", "ConfidenceLower",
        "ConfidenceUpper", "OneSidedLower", "OneSidedUpper",
        "TransportBlocks", "DeliveredTransportBlocks", "FailedTransportBlocks",
        "Transmissions", "FailedTransmissionAttempts",
        "PointEstimatePass", "ConfidenceSupportsPass",
        "ObservedConfidenceBoundSupportsPass",
        "ConfidenceQualificationEligible", "ConfidenceMethod", "StopReason",
        "StandardDocument", "StandardVersion", "StandardRelease",
        "StandardSourceURL", "FRCDefinitionClause", "FRCDefinitionTable",
        "RequirementClause", "RequirementTables", "ConfidenceLevel",
        "RequiredQualificationTransportBlocks", "ConfidenceSamplingPlan",
        "StatisticalUnit", "ConfiguredModulation", "ConfiguredMCSTable",
        "ConfiguredMCSIndex", "ConfiguredTargetCodeRate",
        "EffectiveTargetCodeRate", "ConfiguredTBSBits", "EffectiveTBSBits",
        "ConfiguredCodedBitsPerSlot", "EffectiveCodedBitsPerSlot",
        "ConfiguredLayers", "ConfiguredTxAntennas", "ConfiguredRxAntennas",
        "EffectiveLayers", "EffectiveTxPorts", "NoiseVarSource",
        "DecoderNoiseVar", "PostEqSINR_dB", "LastTBReceiverOk",
        "LastTBCRCError", "ChannelExecutionMode", "ChannelChunkSlots",
        "ChannelChunkSamples", "ChannelCallCount", "ChannelMaximumInputRows",
        "ChannelFullSequenceProcessed", "ExecutionBackend",
        "ApproximationMode", "Source", "FullStandardExecutionExact",
        "DataChannelExact", "ProxyUsed", "FallbackUsed", "EvidenceClass",
        "CatalogSHA256",
    }
    checks = [_check(
        "frc_reference", path, "required_columns", rows,
        sorted(required_columns - set(header)),
    )]
    value_failures: list[str] = []
    phy_failures: list[str] = []
    truth_failures: list[str] = []
    for index, row in enumerate(rows, start=1):
        prefix = f"row={index}"
        for name in (
            "EntryId", "FRC", "Condition", "Direction", "PhysicalChannel",
            "Profile", "Metric", "StandardDocument", "StandardVersion",
            "StandardSourceURL", "FRCDefinitionClause", "FRCDefinitionTable",
            "RequirementClause", "RequirementTables", "ConfidenceMethod",
            "ConfidenceSamplingPlan", "StatisticalUnit",
        ):
            if not _text(row, name):
                value_failures.append(prefix + f":{name}_missing")
        target = _number(row, "TargetFraction")
        estimate = _number(row, "MetricEstimate")
        lower = _number(row, "ConfidenceLower")
        upper = _number(row, "ConfidenceUpper")
        one_lower = _number(row, "OneSidedLower")
        one_upper = _number(row, "OneSidedUpper")
        required_snr = _number(row, "RequiredSNR_dB")
        snr = _number(row, "SNR_dB")
        if any(value is None for value in (
            target, estimate, lower, upper, one_lower, one_upper,
            required_snr, snr,
        )):
            value_failures.append(prefix + ":nonfinite_metric_or_snr")
        elif not (
            0 < target < 1
            and 0 <= lower <= estimate <= upper <= 1
            and 0 <= one_lower <= estimate <= one_upper <= 1
        ):
            value_failures.append(prefix + ":invalid_metric_or_confidence_order")
        if (
            target is not None and estimate is not None and one_lower is not None
            and _text(row, "Metric").lower() == "fraction_max_throughput"
        ):
            point_pass = _boolean(row, "PointEstimatePass")
            observed_bound_pass = _boolean(
                row, "ObservedConfidenceBoundSupportsPass"
            )
            qualification_eligible = _boolean(
                row, "ConfidenceQualificationEligible"
            )
            qualification_bound_pass = _boolean(row, "ConfidenceSupportsPass")
            if point_pass is not (estimate >= target):
                value_failures.append(prefix + ":point_estimate_pass_mismatch")
            if observed_bound_pass is not (one_lower >= target):
                value_failures.append(prefix + ":observed_confidence_bound_pass_mismatch")
            if qualification_bound_pass is not (
                observed_bound_pass is True and qualification_eligible is True
            ):
                value_failures.append(
                    prefix + ":qualification_confidence_gate_mismatch"
                )
        required_point = _boolean(row, "RequiredPoint")
        if required_snr is not None and snr is not None and (
            required_point is not (abs(required_snr - snr) <= 1e-10)
        ):
            value_failures.append(prefix + ":required_point_flag_mismatch")
        tb = _number(row, "TransportBlocks")
        delivered = _number(row, "DeliveredTransportBlocks")
        failed = _number(row, "FailedTransportBlocks")
        transmissions = _number(row, "Transmissions")
        failed_attempts = _number(row, "FailedTransmissionAttempts")
        if not (
            _whole(_number(row, "ExperimentSeed"))
            and
            _whole(tb, 1) and _whole(delivered) and _whole(failed)
            and _whole(transmissions, 1)
            and delivered + failed == tb and transmissions >= tb
            and _whole(failed_attempts)
            and failed_attempts == transmissions - delivered
        ):
            value_failures.append(prefix + ":transport_block_arithmetic_mismatch")

        configured_rate = _number(row, "ConfiguredTargetCodeRate")
        effective_rate = _number(row, "EffectiveTargetCodeRate")
        configured_tbs = _number(row, "ConfiguredTBSBits")
        effective_tbs = _number(row, "EffectiveTBSBits")
        configured_g = _number(row, "ConfiguredCodedBitsPerSlot")
        effective_g = _number(row, "EffectiveCodedBitsPerSlot")
        configured_layers = _number(row, "ConfiguredLayers")
        effective_layers = _number(row, "EffectiveLayers")
        configured_tx = _number(row, "ConfiguredTxAntennas")
        configured_rx = _number(row, "ConfiguredRxAntennas")
        effective_ports = _number(row, "EffectiveTxPorts")
        if not (
            configured_rate is not None and 0 < configured_rate < 1
            and _close(effective_rate, configured_rate, atol=1e-12)
            and _whole(configured_tbs, 1)
            and _close(effective_tbs, configured_tbs, atol=0)
            and _whole(configured_g, 1)
            and _close(effective_g, configured_g, atol=0)
            and _whole(configured_layers, 1)
            and _close(effective_layers, configured_layers, atol=0)
            and _whole(configured_tx, 1) and _whole(configured_rx, 1)
            and _close(effective_ports, configured_tx, atol=0)
        ):
            phy_failures.append(prefix + ":configured_effective_phy_mismatch")
        if not all(_text(row, name) for name in (
            "ConfiguredModulation", "ConfiguredMCSTable", "ConfiguredMCSIndex",
            "NoiseVarSource",
        )):
            phy_failures.append(prefix + ":phy_or_noise_lineage_missing")
        decoder_noise = _number(row, "DecoderNoiseVar")
        posteq = _number(row, "PostEqSINR_dB")
        if decoder_noise is None or decoder_noise <= 0 or posteq is None:
            phy_failures.append(prefix + ":receiver_noise_or_sinr_invalid")

        full_standard = _boolean(row, "FullStandardExecutionExact")
        data_exact = _boolean(row, "DataChannelExact")
        proxy = _boolean(row, "ProxyUsed")
        fallback = _boolean(row, "FallbackUsed")
        approximation = _text(row, "ApproximationMode").lower()
        evidence = _text(row, "EvidenceClass").upper()
        if not (
            data_exact is True and proxy is False and fallback is False
            and approximation == "none"
            and _text(row, "ExecutionBackend")
            and _text(row, "Source")
            and len(_text(row, "CatalogSHA256")) == 64
        ):
            truth_failures.append(prefix + ":truth_or_provenance_invalid")
        if full_standard is True and "FULL_STANDARD_TRUTH_EXECUTION" not in evidence:
            truth_failures.append(prefix + ":full_standard_evidence_class_mismatch")
        if full_standard is False and "SELECTED_DATA_CHANNEL_TRUTH_EXECUTION" not in evidence:
            truth_failures.append(prefix + ":selected_channel_evidence_class_mismatch")

        channel_mode = _text(row, "ChannelExecutionMode")
        if channel_mode:
            chunk_slots = _number(row, "ChannelChunkSlots")
            chunk_samples = _number(row, "ChannelChunkSamples")
            calls = _number(row, "ChannelCallCount")
            maximum_rows = _number(row, "ChannelMaximumInputRows")
            if _boolean(row, "ChannelFullSequenceProcessed") is not True:
                truth_failures.append(prefix + ":fading_full_sequence_not_processed")
            if channel_mode == "streamed_complete_sequence":
                if not (
                    _whole(chunk_slots, 1) and _whole(chunk_samples, 1)
                    and _whole(calls, 2) and _whole(maximum_rows, 1)
                    and maximum_rows <= chunk_samples
                ):
                    truth_failures.append(prefix + ":streamed_channel_evidence_invalid")
            elif channel_mode == "monolithic_complete_sequence":
                if not (
                    chunk_slots == 0 and chunk_samples == 0
                    and calls == 1 and _whole(maximum_rows, 1)
                ):
                    truth_failures.append(prefix + ":monolithic_channel_evidence_invalid")
            else:
                truth_failures.append(prefix + ":unknown_channel_execution_mode")
    checks.extend([
        _check("frc_reference", path, "metric_confidence_and_tb_arithmetic", rows, value_failures),
        _check("frc_reference", path, "configured_effective_phy_and_receiver", rows, phy_failures),
        _check("frc_reference", path, "truth_channel_and_provenance", rows, truth_failures),
    ])
    return checks


def _audit_frc_summary_table(
    path: str, header: list[str], rows: list[dict[str, str]]
) -> list[AuditCheck]:
    required_columns = {
        "EntryId", "FRC", "Condition", "Required", "Profile",
        "ExperimentSeed",
        "ExecutionAttempted", "DataChannelExact", "FullStandardExecutionExact",
        "StatisticallyQualified", "OneSidedReferencePass", "RequiredSNR_dB",
        "MeasuredSNR_dB", "Delta_dB", "MeasuredSNRAvailable",
        "CrossingStatus", "TransportBlocks", "BlockErrors", "Transmissions",
        "FailedTransmissionAttempts",
        "Pass", "Status", "EvidenceClass", "CatalogSHA256",
        "FailureIdentifier", "FailureReason",
    }
    checks = [_check(
        "frc_reference", path, "required_columns", rows,
        sorted(required_columns - set(header)),
    )]
    failures: list[str] = []
    for index, row in enumerate(rows, start=1):
        prefix = f"row={index}"
        profile = _text(row, "Profile").lower()
        passed = _boolean(row, "Pass")
        qualified = _boolean(row, "StatisticallyQualified")
        reference_pass = _boolean(row, "OneSidedReferencePass")
        tb = _number(row, "TransportBlocks")
        block_errors = _number(row, "BlockErrors")
        transmissions = _number(row, "Transmissions")
        failed_attempts = _number(row, "FailedTransmissionAttempts")
        if not (
            all(_text(row, name) for name in ("EntryId", "FRC", "Condition"))
            and profile in {"diagnostic", "full"}
            and _boolean(row, "Required") is True
            and _boolean(row, "ExecutionAttempted") is True
            and _boolean(row, "DataChannelExact") is True
            and _whole(_number(row, "ExperimentSeed"))
            and _whole(tb, 1) and _whole(block_errors)
            and block_errors <= tb
            and _whole(transmissions, 1) and transmissions >= tb
            and _whole(failed_attempts)
            and failed_attempts == transmissions - (tb - block_errors)
            and _number(row, "RequiredSNR_dB") is not None
            and len(_text(row, "CatalogSHA256")) == 64
        ):
            failures.append(prefix + ":identity_execution_or_count_invalid")
        if passed is True and not (
            profile == "full" and qualified is True and reference_pass is True
            and _boolean(row, "FullStandardExecutionExact") is True
            and _text(row, "Status").upper() == "PASS"
        ):
            failures.append(prefix + ":pass_claim_not_supported")
        if profile == "diagnostic" and passed is not False:
            failures.append(prefix + ":diagnostic_promoted_to_qualification")
        measured = _number(row, "MeasuredSNR_dB")
        delta = _number(row, "Delta_dB")
        measured_available = _boolean(row, "MeasuredSNRAvailable")
        crossing_status = _text(row, "CrossingStatus")
        if not crossing_status or measured_available is not (
            measured is not None and delta is not None
        ):
            failures.append(prefix + ":crossing_availability_disclosure_mismatch")
        if (measured is None) != (delta is None):
            failures.append(prefix + ":crossing_delta_partial")
        elif measured is not None and not _close(
            delta, measured - (_number(row, "RequiredSNR_dB") or 0.0), atol=1e-10
        ):
            failures.append(prefix + ":crossing_delta_arithmetic_mismatch")
        reason = _text(row, "FailureReason")
        if (
            "observed_pass_not_statistically_qualified" in reason
            and "one_sided_reference_point_failed" in reason
        ):
            failures.append(prefix + ":observed_pass_mislabeled_failed")
        if "TRUTH_EXECUTION" not in _text(row, "EvidenceClass").upper():
            failures.append(prefix + ":truth_evidence_class_missing")
    checks.append(_check(
        "frc_reference", path, "status_counts_and_qualification_semantics", rows, failures
    ))
    return checks


def _audit_frc_progress_table(
    path: str, header: list[str], rows: list[dict[str, str]]
) -> list[AuditCheck]:
    required_columns = {
        "EntryId", "FRC", "Condition", "SNR_dB", "SNRSeedIndex",
        "ExperimentSeed",
        "CompletedTransportBlocks", "MaxTransportBlocks",
        "DeliveredTransportBlocks", "FailedTransportBlocks", "Transmissions",
        "FailedTransmissionAttempts",
        "MetricEstimate", "ConfidenceLower", "ConfidenceUpper",
        "OneSidedLower", "OneSidedUpper", "ConfidenceMethod",
        "ConfidenceHalfWidth", "Status", "StopReason",
        "ConfidenceQualificationEligible", "EvidenceClass",
        "ApproximationMode", "IdentitySHA256",
    }
    checks = [_check(
        "frc_reference", path, "required_columns", rows,
        sorted(required_columns - set(header)),
    )]
    failures: list[str] = []
    for index, row in enumerate(rows, start=1):
        prefix = f"row={index}"
        completed = _number(row, "CompletedTransportBlocks")
        maximum = _number(row, "MaxTransportBlocks")
        delivered = _number(row, "DeliveredTransportBlocks")
        failed = _number(row, "FailedTransportBlocks")
        transmissions = _number(row, "Transmissions")
        failed_attempts = _number(row, "FailedTransmissionAttempts")
        estimate = _number(row, "MetricEstimate")
        lower = _number(row, "ConfidenceLower")
        upper = _number(row, "ConfidenceUpper")
        if not (
            _whole(completed, 1) and _whole(maximum, 1) and completed <= maximum
            and _whole(_number(row, "ExperimentSeed"))
            and _whole(delivered) and _whole(failed) and delivered + failed == completed
            and _whole(transmissions, 1) and transmissions >= completed
            and _whole(failed_attempts)
            and failed_attempts == transmissions - delivered
            and estimate is not None and lower is not None and upper is not None
            and 0 <= lower <= estimate <= upper <= 1
            and _text(row, "ApproximationMode").lower() == "none"
            and "ACTUAL_FRC_TRUTH_EXECUTION" in _text(row, "EvidenceClass").upper()
            and len(_text(row, "IdentitySHA256")) == 64
        ):
            failures.append(prefix + ":progress_arithmetic_or_truth_invalid")
    checks.append(_check(
        "frc_reference", path, "progress_arithmetic_and_truth", rows, failures
    ))
    return checks


def _audit_frc_plot_lineage(
    run_root: Path, path: str, header: list[str], rows: list[dict[str, str]]
) -> list[AuditCheck]:
    required_columns = {
        "PlotId", "ImagePath", "SourceCSV", "SourceCSV_SHA256",
        "ImageSHA256", "Width", "Height", "MimeType", "ImageExists",
        "SourceExists", "ProducerModule", "Status", "FailureReason",
    }
    checks = [_check(
        "frc_reference", path, "required_columns", rows,
        sorted(required_columns - set(header)),
    )]
    failures: list[str] = []
    for index, row in enumerate(rows, start=1):
        prefix = f"row={index}"
        image_path = run_root / _text(row, "ImagePath")
        source_path = run_root / _text(row, "SourceCSV")
        dimensions = _png_dimensions(image_path) if _io_path(image_path).is_file() else None
        if not (
            _boolean(row, "ImageExists") is True
            and _boolean(row, "SourceExists") is True
            and _text(row, "Status").lower() == "pass"
            and _text(row, "MimeType").lower() == "image/png"
            and _io_path(image_path).is_file() and _io_path(source_path).is_file()
            and _sha256(image_path).lower() == _text(row, "ImageSHA256").lower()
            and _sha256(source_path).lower() == _text(row, "SourceCSV_SHA256").lower()
            and dimensions is not None
            and dimensions == (
                int(_number(row, "Width") or -1), int(_number(row, "Height") or -1)
            )
            and dimensions[0] >= 1200 and dimensions[1] >= 675
        ):
            failures.append(prefix + ":plot_lineage_hash_dimension_or_file_invalid")
    checks.append(_check(
        "frc_reference", path, "plot_lineage_hashes_dimensions_and_files", rows, failures
    ))
    return checks


def _audit_frc_reference_outputs(run_root: Path) -> list[AuditCheck]:
    checks: list[AuditCheck] = []
    point_header, point_rows = _read_rows(run_root / FRC_POINT_TABLE)
    if point_header or point_rows:
        checks.extend(_audit_frc_point_table(FRC_POINT_TABLE, point_header, point_rows))
    point_shard_paths = sorted(
        run_root.glob("reports/csv/frc_reference_points/*.csv")
    )
    for shard_path in point_shard_paths:
        relative = shard_path.relative_to(run_root).as_posix()
        header, rows = _read_rows(shard_path)
        checks.extend(_audit_frc_point_table(relative, header, rows))

    summary_paths = [
        path for path in FRC_SUMMARY_TABLES
        if _io_path(run_root / path).is_file()
    ]
    summary_rows: list[dict[str, str]] = []
    for summary_path in summary_paths:
        summary_header, current_rows = _read_rows(run_root / summary_path)
        checks.extend(_audit_frc_summary_table(
            summary_path, summary_header, current_rows
        ))
        if not summary_rows:
            summary_rows = current_rows
    progress_paths = _find_named_files(
        run_root / "reports/csv/frc_reference_progress",
        "frc_reference_progress.csv",
    )
    progress_rows: list[dict[str, str]] = []
    for progress_path in progress_paths:
        relative = progress_path.relative_to(run_root).as_posix()
        header, rows = _read_rows(progress_path)
        progress_rows.extend(rows)
        checks.extend(_audit_frc_progress_table(relative, header, rows))
    lineage_header, lineage_rows = _read_rows(run_root / FRC_PLOT_LINEAGE)
    if lineage_header or lineage_rows:
        checks.extend(_audit_frc_plot_lineage(
            run_root, FRC_PLOT_LINEAGE, lineage_header, lineage_rows
        ))
    reconcile_failures: list[str] = []
    if point_rows and summary_rows:
        summary_by_entry = {_text(row, "EntryId"): row for row in summary_rows}
        for row in point_rows:
            entry = _text(row, "EntryId")
            summary_row = summary_by_entry.get(entry)
            if summary_row is None:
                reconcile_failures.append(f"entry={entry}:summary_missing")
                continue
            if not (
                _close(_number(summary_row, "TransportBlocks"), _number(row, "TransportBlocks"), atol=0)
                and _close(_number(summary_row, "BlockErrors"), _number(row, "FailedTransportBlocks"), atol=0)
                and _close(_number(summary_row, "Transmissions"), _number(row, "Transmissions"), atol=0)
                and _close(_number(summary_row, "FailedTransmissionAttempts"), _number(row, "FailedTransmissionAttempts"), atol=0)
                and _close(_number(summary_row, "RequiredSNR_dB"), _number(row, "RequiredSNR_dB"), atol=1e-12)
                and _close(_number(summary_row, "ExperimentSeed"), _number(row, "ExperimentSeed"), atol=0)
            ):
                reconcile_failures.append(f"entry={entry}:summary_point_mismatch")
    if point_rows and progress_rows:
        progress_by_entry = {_text(row, "EntryId"): row for row in progress_rows}
        for row in point_rows:
            entry = _text(row, "EntryId")
            progress_row = progress_by_entry.get(entry)
            if progress_row is None or not (
                _close(_number(progress_row, "CompletedTransportBlocks"), _number(row, "TransportBlocks"), atol=0)
                and _close(_number(progress_row, "DeliveredTransportBlocks"), _number(row, "DeliveredTransportBlocks"), atol=0)
                and _close(_number(progress_row, "FailedTransportBlocks"), _number(row, "FailedTransportBlocks"), atol=0)
                and _close(_number(progress_row, "Transmissions"), _number(row, "Transmissions"), atol=0)
                and _close(_number(progress_row, "FailedTransmissionAttempts"), _number(row, "FailedTransmissionAttempts"), atol=0)
                and _close(_number(progress_row, "MetricEstimate"), _number(row, "MetricEstimate"), atol=1e-12)
                and _close(_number(progress_row, "ExperimentSeed"), _number(row, "ExperimentSeed"), atol=0)
            ):
                reconcile_failures.append(f"entry={entry}:progress_point_mismatch")
    if point_rows:
        checks.append(_check(
            "frc_reference", FRC_POINT_TABLE,
            "summary_progress_point_reconciliation", point_rows,
            reconcile_failures,
        ))
    return checks


def _raw_rows_for_scope(
    link_rows: dict[str, list[dict[str, str]]], direction: str, ue_value: str
) -> list[dict[str, str]]:
    rows = _measured_analysis_rows(link_rows.get(direction.upper(), []))
    ue = str(ue_value or "").strip().lower()
    if ue in {"", "all", "nan", "n/a"}:
        return rows
    return [
        row
        for row in rows
        if _text(row, "UEIndex", "UEID").strip().lower() == ue
    ]


def _finalized_truth_rows_for_scope(
    link_rows: dict[str, list[dict[str, str]]], direction: str, ue_value: str
) -> list[dict[str, str]]:
    rows = _finalized_truth_rows(link_rows.get(direction.upper(), []))
    ue = str(ue_value or "").strip().lower()
    if ue in {"", "all", "nan", "n/a"}:
        return rows
    return [
        row
        for row in rows
        if _text(row, "UEIndex", "UEID").strip().lower() == ue
    ]


def _finalized_truth_rows(
    rows: list[dict[str, str]],
) -> list[dict[str, str]]:
    """Return all finalized, non-fallback waveform trial observations."""
    return [
        row
        for row in rows
        if ("FinalizedFlag" not in row or _boolean(row, "FinalizedFlag") is True)
        and _boolean(row, "FallbackFlag") is not True
    ]


def _measured_analysis_rows(
    rows: list[dict[str, str]],
) -> list[dict[str, str]]:
    """Mirror generateMeasuredSINRCurves' finalized measurement population."""
    selected: list[dict[str, str]] = []
    for row in _finalized_truth_rows(rows):
        if _boolean(row, "IsWarmupFrame") is True:
            continue
        if "PostEqSINR_dB" in row and _number(row, "PostEqSINR_dB") is None:
            continue
        if "PostEqSINRValueStatus" in row and not _text(
            row, "PostEqSINRValueStatus"
        ).strip().upper().startswith("OK"):
            continue
        selected.append(row)
    return selected


def _raw_error_rates(rows: list[dict[str, str]]) -> tuple[float, float, int]:
    failures = sum(_boolean(row, "CRCPass") is False for row in rows)
    bit_errors = sum((_number(row, "BitErrors") or 0.0) for row in rows)
    bits_compared = sum((_number(row, "BitsCompared") or 0.0) for row in rows)
    bler = failures / len(rows) if rows else math.nan
    ber = bit_errors / bits_compared if bits_compared > 0 else math.nan
    return bler, ber, failures


def _audit_derived_link_table(
    path: str,
    header: list[str],
    rows: list[dict[str, str]],
    link_rows: dict[str, list[dict[str, str]]],
) -> list[AuditCheck]:
    """Validate derived link artifacts against the same persisted raw trials."""

    name = Path(path).name.lower()
    required_by_name = {
        "distance_vs_sinr.csv": {
            "Direction", "TrialIndex", "PropagationDistance_m", "PostEqSINR_dB",
            "CRCPass", "Goodput_Mbps", "SourceArtifact",
        },
        "dl_measured_sinr_bler_curve.csv": {
            "Direction", "PostEqSINR_dB_BinCenter", "PostEqSINR_dB_BinMin",
            "PostEqSINR_dB_BinMax", "BLER", "BLER_CI_Low", "BLER_CI_High",
            "BER", "TrialCount", "FailureCount", "SourceArtifact",
        },
        "ul_measured_sinr_bler_curve.csv": {
            "Direction", "PostEqSINR_dB_BinCenter", "PostEqSINR_dB_BinMin",
            "PostEqSINR_dB_BinMax", "BLER", "BLER_CI_Low", "BLER_CI_High",
            "BER", "TrialCount", "FailureCount", "SourceArtifact",
        },
        "dl_measured_sinr_throughput_curve.csv": {
            "Direction", "PostEqSINR_dB_BinCenter", "PostEqSINR_dB_BinMin",
            "PostEqSINR_dB_BinMax", "Throughput_Mbps_mean", "Goodput_Mbps_mean",
            "OfferedThroughput_Mbps_mean", "TrialCount", "SourceArtifact",
        },
        "ul_measured_sinr_throughput_curve.csv": {
            "Direction", "PostEqSINR_dB_BinCenter", "PostEqSINR_dB_BinMin",
            "PostEqSINR_dB_BinMax", "Throughput_Mbps_mean", "Goodput_Mbps_mean",
            "OfferedThroughput_Mbps_mean", "TrialCount", "SourceArtifact",
        },
        "fer_summary.csv": {
            "Scope", "Direction", "ObservedFrames", "ErroredFrames", "FER",
            "BLER", "BER", "TraceSource",
        },
        "live_measured_sinr_summary.csv": {
            "Direction", "UEIndex", "N_Trials", "SINR_min_dB", "SINR_p5_dB",
            "SINR_median_dB", "SINR_p95_dB", "SINR_max_dB", "BLER_overall",
            "BER_overall", "Throughput_Mbps_mean", "Goodput_Mbps_mean",
            "OfferedThroughput_Mbps_mean", "SourceArtifact",
        },
        "lls_measured_sinr_summary.csv": {
            "Direction", "UEIndex", "N_Trials", "SINR_min_dB", "SINR_p5_dB",
            "SINR_median_dB", "SINR_p95_dB", "SINR_max_dB", "BLER_overall",
            "BER_overall", "Throughput_Mbps_mean", "Goodput_Mbps_mean",
            "OfferedThroughput_Mbps_mean", "SourceArtifact",
        },
        "lls_kpi_summary.csv": {
            "RunId", "Direction", "UEIndex", "KPIReconciliationPass",
            "BLER_overall", "BER_overall", "Throughput_Mbps", "Goodput_Mbps",
            "OfferedThroughput_Mbps", "RadioDuration_s", "TrialCount", "StrictOk",
            "Status", "SourceArtifact",
        },
        "lls_snr_sweep.csv": {
            "SNR_dB", "CampaignKind", "SweepKind", "DL_BER", "DL_BLER",
            "DL_TrialCount", "DL_FailureCount", "DL_Throughput_Mbps",
            "DL_OfferedThroughput_Mbps", "DL_Goodput_Mbps", "UL_BER", "UL_BLER",
            "UL_TrialCount", "UL_FailureCount", "UL_Throughput_Mbps",
            "UL_OfferedThroughput_Mbps", "UL_Goodput_Mbps",
        },
        "measured_sinr_distribution.csv": {
            "Direction", "UEIndex", "PostEqSINR_dB_BinCenter", "TrialCount",
            "Fraction", "SourceArtifact",
        },
        "multiuser_user_summary.csv": {
            "UEIndex", "Direction", "Throughput_Mbps", "OfferedThroughput_Mbps",
            "Goodput_Mbps", "ObservedRowCount", "BLER", "BER", "PassRate",
            "SummaryRowValid", "RuntimeDataPresent", "SummaryStatus",
        },
        "papr_ccdf.csv": {"Direction", "PAPR_dB", "CCDF"},
    }
    required_columns = required_by_name.get(name, set())
    schema_failures = sorted(required_columns.difference(header))
    raw_link_population = [
        row for direction_rows in link_rows.values()
        for row in _measured_analysis_rows(direction_rows)
    ]
    link_without_geometry = bool(raw_link_population) and all(
        _number(row, "PropagationDistance_m") is None
        for row in raw_link_population
    )
    if not rows and name == "distance_vs_sinr.csv" and link_without_geometry:
        return [
            _check(
                "derived_link",
                path,
                "not_applicable_link_without_geometry",
                rows,
                schema_failures,
                required=False,
                evaluated=False,
            )
        ]
    if not rows:
        schema_failures.append("missing_runtime_rows")
    checks = [
        _check("derived_link", path, "required_schema_and_rows", rows, schema_failures)
    ]
    if schema_failures or not rows:
        return checks

    range_failures: list[str] = []
    reconciliation_failures: list[str] = []
    for index, row in enumerate(rows, start=1):
        prefix = f"row={index}"
        direction = _text(row, "Direction").upper()
        if "Direction" in header and direction not in {"DL", "UL"}:
            range_failures.append(prefix + ":invalid_direction")
        for field in ("BER", "BLER", "FER", "BER_overall", "BLER_overall", "PassRate", "Fraction", "CCDF"):
            if field not in header:
                continue
            value = _number(row, field)
            if value is None or value < -1e-12 or value > 1.0 + 1e-12:
                range_failures.append(prefix + f":{field}_outside_unit_interval")
        for field in ("TrialCount", "FailureCount", "N_Trials", "ObservedFrames", "ErroredFrames", "ObservedRowCount"):
            if field not in header:
                continue
            value = _number(row, field)
            if value is None or value < 0 or not _close(value, round(value), atol=0):
                range_failures.append(prefix + f":{field}_not_nonnegative_integer")
        for field in (
            "Throughput_Mbps", "Throughput_Mbps_mean", "Goodput_Mbps",
            "Goodput_Mbps_mean", "OfferedThroughput_Mbps",
            "OfferedThroughput_Mbps_mean", "RadioDuration_s", "PropagationDistance_m",
        ):
            if field in header:
                value = _number(row, field)
                if value is None or value < -1e-12:
                    range_failures.append(prefix + f":{field}_negative_or_nonfinite")

        if "PostEqSINR_dB_BinCenter" in header:
            center = _number(row, "PostEqSINR_dB_BinCenter")
            low = _number(row, "PostEqSINR_dB_BinMin")
            high = _number(row, "PostEqSINR_dB_BinMax")
            if center is None or (low is not None and center < low) or (high is not None and center > high):
                range_failures.append(prefix + ":sinr_bin_order_invalid")
        if "BLER_CI_Low" in header:
            low = _number(row, "BLER_CI_Low")
            value = _number(row, "BLER")
            high = _number(row, "BLER_CI_High")
            if low is None or value is None or high is None or not (0 <= low <= value <= high <= 1):
                range_failures.append(prefix + ":bler_confidence_interval_invalid")
        if "Goodput_Mbps" in header and "OfferedThroughput_Mbps" in header:
            if (_number(row, "Goodput_Mbps") or 0.0) > (_number(row, "OfferedThroughput_Mbps") or 0.0) + 1e-9:
                range_failures.append(prefix + ":goodput_exceeds_offered")
        if (
            "Goodput_Mbps_mean" in header
            and "OfferedThroughput_Mbps_mean" in header
            and not name.endswith("_measured_sinr_throughput_curve.csv")
        ):
            if (_number(row, "Goodput_Mbps_mean") or 0.0) > (_number(row, "OfferedThroughput_Mbps_mean") or 0.0) + 1e-9:
                range_failures.append(prefix + ":mean_goodput_exceeds_offered")

    # A successful HARQ retransmission can deliver a TB in a different SINR
    # bin from the original transmission.  Consequently, per-bin goodput may
    # legitimately exceed newly offered traffic in that bin.  Conservation is
    # still mandatory over the complete population for each direction/UE
    # scope, weighted by the exact number of persisted trials in every bin.
    if name.endswith("_measured_sinr_throughput_curve.csv"):
        grouped_throughput: dict[tuple[str, str], list[dict[str, str]]] = {}
        for row in rows:
            key = (_text(row, "Direction").upper(), _text(row, "UEIndex"))
            grouped_throughput.setdefault(key, []).append(row)
        for key, group in grouped_throughput.items():
            weighted_goodput = sum(
                (_number(row, "Goodput_Mbps_mean") or 0.0)
                * (_number(row, "TrialCount") or 0.0)
                for row in group
            )
            weighted_offered = sum(
                (_number(row, "OfferedThroughput_Mbps_mean") or 0.0)
                * (_number(row, "TrialCount") or 0.0)
                for row in group
            )
            if weighted_goodput > weighted_offered + 1e-9:
                range_failures.append(
                    f"group={key}:population_goodput_exceeds_offered"
                )

    if name.endswith("_measured_sinr_bler_curve.csv"):
        for row in rows:
            count = _number(row, "TrialCount")
            failures = _number(row, "FailureCount")
            bler = _number(row, "BLER")
            if count is None or count <= 0 or failures is None or failures > count or not _close(bler, failures / count, atol=1e-12):
                reconciliation_failures.append("bler_failure_count_arithmetic_mismatch")
                break
    if name in {"live_measured_sinr_summary.csv", "lls_measured_sinr_summary.csv", "lls_kpi_summary.csv"}:
        for index, row in enumerate(rows, start=1):
            raw = _raw_rows_for_scope(link_rows, _text(row, "Direction"), _text(row, "UEIndex"))
            count = _number(row, "N_Trials", "TrialCount")
            bler, ber, _failures = _raw_error_rates(raw)
            if not raw or not _close(count, len(raw), atol=0):
                reconciliation_failures.append(f"row={index}:trial_count_mismatch")
                continue
            if not _close(_number(row, "BLER_overall"), bler, atol=1e-12):
                reconciliation_failures.append(f"row={index}:bler_raw_mismatch")
            if not _close(_number(row, "BER_overall"), ber, atol=1e-12):
                reconciliation_failures.append(f"row={index}:ber_raw_mismatch")
            throughput_field = "Throughput_Mbps" if "Throughput_Mbps" in header else "Throughput_Mbps_mean"
            expected_throughput = sum((_number(item, "Throughput_Mbps") or 0.0) for item in raw) / len(raw)
            if not _close(_number(row, throughput_field), expected_throughput, atol=1e-9):
                reconciliation_failures.append(f"row={index}:throughput_raw_mismatch")
            if name == "lls_kpi_summary.csv":
                if _boolean(row, "KPIReconciliationPass") is not True or _boolean(row, "StrictOk") is not True:
                    reconciliation_failures.append(f"row={index}:kpi_reconciliation_not_pass")
    elif name == "measured_sinr_distribution.csv":
        grouped: dict[tuple[str, str], list[dict[str, str]]] = {}
        for row in rows:
            grouped.setdefault((_text(row, "Direction").upper(), _text(row, "UEIndex")), []).append(row)
        for key, group in grouped.items():
            raw = _raw_rows_for_scope(link_rows, key[0], key[1])
            count = sum(int(_number(row, "TrialCount") or 0) for row in group)
            fraction = sum((_number(row, "Fraction") or 0.0) for row in group)
            if count != len(raw) or not _close(fraction, 1.0, atol=1e-12):
                reconciliation_failures.append(f"group={key}:distribution_population_mismatch")
    elif name == "multiuser_user_summary.csv":
        for index, row in enumerate(rows, start=1):
            raw = _finalized_truth_rows_for_scope(
                link_rows, _text(row, "Direction"), _text(row, "UEIndex")
            )
            bler, ber, failures = _raw_error_rates(raw)
            if not raw or not _close(_number(row, "ObservedRowCount"), len(raw), atol=0):
                reconciliation_failures.append(f"row={index}:observed_count_mismatch")
                continue
            if not _close(_number(row, "BLER"), bler, atol=1e-12) or not _close(_number(row, "BER"), ber, atol=1e-12):
                reconciliation_failures.append(f"row={index}:error_rate_raw_mismatch")
            if not _close(_number(row, "PassRate"), 1.0 - failures / len(raw), atol=1e-12):
                reconciliation_failures.append(f"row={index}:pass_rate_raw_mismatch")
    elif name == "papr_ccdf.csv":
        for direction in ("DL", "UL"):
            group = [row for row in rows if _text(row, "Direction").upper() == direction]
            thresholds = [_number(row, "PAPR_dB") for row in group]
            probabilities = [_number(row, "CCDF") for row in group]
            if (
                not group
                or any(value is None for value in thresholds + probabilities)
                or any(float(thresholds[i]) >= float(thresholds[i + 1]) for i in range(len(thresholds) - 1))
                or any(float(probabilities[i]) < float(probabilities[i + 1]) - 1e-12 for i in range(len(probabilities) - 1))
            ):
                reconciliation_failures.append(f"direction={direction}:ccdf_not_monotone")
    elif name == "distance_vs_sinr.csv":
        expected_distance_rows = sum(
            len(_measured_analysis_rows(value)) for value in link_rows.values()
        )
        if len(rows) != expected_distance_rows:
            reconciliation_failures.append("distance_table_trial_count_mismatch")
    elif name == "fer_summary.csv":
        for index, row in enumerate(rows, start=1):
            raw = _raw_rows_for_scope(link_rows, _text(row, "Direction"), _text(row, "UEIndex"))
            frame_groups: dict[tuple[str, ...], list[dict[str, str]]] = {}
            for item in raw:
                if _boolean(item, "FixedLinkCampaign") is True:
                    frame_key = (
                        "fixed_link",
                        _text(item, "FixedLinkPointIndex"),
                        _text(item, "FixedLinkDropIndex"),
                        _text(item, "FixedLinkTrialIndex"),
                    )
                else:
                    frame_key = (
                        "runtime_frame",
                        _text(item, "SFN", "Frame"),
                        _text(item, "SweepPointIndex"),
                    )
                frame_groups.setdefault(frame_key, []).append(item)
            errored = sum(any(_boolean(item, "CRCPass") is False for item in group) for group in frame_groups.values())
            observed = len(frame_groups)
            if not _close(_number(row, "ObservedFrames"), observed, atol=0) or not _close(_number(row, "ErroredFrames"), errored, atol=0):
                reconciliation_failures.append(f"row={index}:frame_count_raw_mismatch")
            expected_fer = errored / observed if observed else math.nan
            if not _close(_number(row, "FER"), expected_fer, atol=1e-12):
                reconciliation_failures.append(f"row={index}:fer_raw_mismatch")

    checks.extend(
        [
            _check("derived_link", path, "physical_ranges_and_arithmetic", rows, range_failures),
            _check("derived_link", path, "same_trial_population_reconciliation", rows, reconciliation_failures),
        ]
    )
    return checks


def _audit_manifest_integrity(run_root: Path) -> list[AuditCheck]:
    """Validate persisted publication claims against exact filesystem bytes."""

    checks: list[AuditCheck] = []
    results_rel = "artifact_generation/artifact_generation_results.csv"
    results_header, result_rows = _read_rows(run_root / results_rel)
    if result_rows:
        failures: list[str] = []
        required_columns = {
            "ContractID", "Domain", "Component", "Profile", "ArtifactType", "FileName", "Required",
            "Status", "SourceRows", "OutputRelativePath", "SourceSHA256", "SHA256",
            "ByteSize", "Width", "Height", "AxesCount", "SeriesCount", "FinitePointCount",
        }
        if not required_columns.issubset(results_header):
            failures.append("missing_columns=" + ",".join(sorted(required_columns.difference(results_header))))
        canonical_rel = "artifact_generation/canonical_component_manifest.csv"
        canonical_header, canonical_rows = _read_rows(run_root / canonical_rel)
        canonical_by_contract: dict[str, dict[str, str]] = {}
        duplicate_contracts: set[str] = set()
        for manifest_row in canonical_rows:
            contract_id = _text(manifest_row, "ContractID")
            if not contract_id:
                continue
            if contract_id in canonical_by_contract:
                duplicate_contracts.add(contract_id)
            canonical_by_contract[contract_id] = manifest_row
        if duplicate_contracts:
            failures.append(
                "canonical_manifest_duplicate_contracts="
                + ",".join(sorted(duplicate_contracts))
            )
        for index, row in enumerate(result_rows, start=1):
            prefix = f"row={index}"
            status = _text(row, "Status").upper()
            required = _boolean(row, "Required") is True
            contract_id = _text(row, "ContractID")
            canonical_row = canonical_by_contract.get(contract_id)
            if status == "PASS" and canonical_row is None:
                failures.append(prefix + ":pass_claim_missing_canonical_manifest_row")
            published_relative = (
                _text(canonical_row or {}, "PublishedRelativePath")
                or f"components/{_text(row, 'OutputRelativePath')}"
            ).replace("\\", "/")
            output = _run_relative_path(run_root, published_relative)
            if output is None:
                failures.append(prefix + ":invalid_output_path")
                continue
            if canonical_row is not None:
                for field in ("Status", "SHA256", "SourceSHA256", "ByteSize"):
                    if _text(canonical_row, field) != _text(row, field):
                        failures.append(prefix + f":canonical_manifest_{field}_mismatch")
            exists = _io_path(output).is_file()
            if status == "PASS" and not exists:
                failures.append(prefix + ":pass_claim_output_missing")
                continue
            if required and status != "PASS":
                failures.append(prefix + f":required_status={status or 'missing'}")
            if not exists:
                continue
            actual_hash = _sha256(output)
            actual_bytes = _io_path(output).stat().st_size
            if actual_hash.lower() != _text(row, "SHA256").lower():
                failures.append(prefix + ":output_hash_mismatch")
            if not _close(_number(row, "ByteSize"), actual_bytes, atol=0):
                failures.append(prefix + ":output_byte_size_mismatch")
            artifact_type = _text(row, "ArtifactType").upper()
            source = output
            if artifact_type == "PNG":
                source_rel = ARTIFACT_GENERATION_PNG_SOURCES.get(_text(row, "FileName"))
                source = _run_relative_path(run_root, source_rel or "") if source_rel else None
                if source is None:
                    failures.append(prefix + ":no_exact_png_source_mapping")
                dimensions = _png_dimensions(output)
                if dimensions is None:
                    failures.append(prefix + ":invalid_png")
                else:
                    if not _close(_number(row, "Width"), dimensions[0], atol=0) or not _close(
                        _number(row, "Height"), dimensions[1], atol=0
                    ):
                        failures.append(prefix + ":png_dimensions_mismatch")
                semantics = _png_semantics(output)
                if not semantics:
                    failures.append(prefix + ":png_semantics_missing")
                elif "visual_gate=" in semantics.lower() or "unavailable without faking" in semantics.lower():
                    failures.append(prefix + ":reason_card_claimed_as_png_evidence")
                for field in ("AxesCount", "SeriesCount", "FinitePointCount"):
                    value = _number(row, field)
                    if value is None or value <= 0 or not _close(value, round(value), atol=0):
                        failures.append(prefix + f":{field}_not_positive_integer")
            if source is None or not _io_path(source).is_file():
                failures.append(prefix + ":source_csv_missing")
            else:
                source_header, source_rows = _read_rows(source)
                if _sha256(source).lower() != _text(row, "SourceSHA256").lower():
                    failures.append(prefix + ":source_hash_mismatch")
                if not _close(_number(row, "SourceRows"), len(source_rows), atol=0):
                    failures.append(prefix + ":source_row_count_mismatch")
                if artifact_type == "CSV" and not source_header:
                    failures.append(prefix + ":csv_schema_missing")
        checks.append(_check("manifest_integrity", results_rel, "declared_artifacts_match_filesystem", result_rows, failures))

        summary_rel = "artifact_generation/artifact_generation_summary.csv"
        summary_header, summary_rows = _read_rows(run_root / summary_rel)
        summary_failures: list[str] = []
        expected: dict[tuple[str, str, str, str], dict[str, int | str]] = {}
        for row in result_rows:
            key = tuple(_text(row, name) for name in ("Domain", "Component", "Profile", "ArtifactType"))
            item = expected.setdefault(
                key,
                {
                    "ContractCount": 0, "RequiredCount": 0, "GeneratedCount": 0,
                    "MissingCount": 0, "FailedCount": 0, "RequiredFailureCount": 0,
                    "SourceRowCount": 0, "PublishedByteCount": 0, "Status": "PASS",
                },
            )
            item["ContractCount"] = int(item["ContractCount"]) + 1
            required = _boolean(row, "Required") is True
            status = _text(row, "Status").upper()
            item["RequiredCount"] = int(item["RequiredCount"]) + int(required)
            item["GeneratedCount"] = int(item["GeneratedCount"]) + int(status == "PASS")
            item["MissingCount"] = int(item["MissingCount"]) + int(status == "MISSING")
            item["FailedCount"] = int(item["FailedCount"]) + int(status not in {"PASS", "MISSING"})
            item["RequiredFailureCount"] = int(item["RequiredFailureCount"]) + int(required and status != "PASS")
            item["SourceRowCount"] = int(item["SourceRowCount"]) + int(_number(row, "SourceRows") or 0)
            if status == "PASS":
                item["PublishedByteCount"] = int(item["PublishedByteCount"]) + int(_number(row, "ByteSize") or 0)
        observed = {
            tuple(_text(row, name) for name in ("Domain", "Component", "Profile", "ArtifactType")): row
            for row in summary_rows
        }
        if set(observed) != set(expected):
            summary_failures.append("summary_group_keys_do_not_match_results")
        for key, expected_row in expected.items():
            row = observed.get(key, {})
            expected_row["Status"] = "PASS" if int(expected_row["RequiredFailureCount"]) == 0 else "FAIL"
            for field, value in expected_row.items():
                if field == "Status":
                    if _text(row, field).upper() != str(value):
                        summary_failures.append(f"group={key}:{field}_mismatch")
                elif not _close(_number(row, field), float(value), atol=0):
                    summary_failures.append(f"group={key}:{field}_mismatch")
        if not summary_rows or not summary_header:
            summary_failures.append("summary_missing_or_empty")
        checks.append(_check("manifest_integrity", summary_rel, "artifact_summary_reconciles_results", summary_rows, summary_failures))

    publication_rel = "reports/csv/component_artifact_publication_manifest.csv"
    publication_header, publication_rows = _read_rows(run_root / publication_rel)
    if publication_rows:
        publication_failures: list[str] = []
        destinations: dict[str, str] = {}
        canonical_row_failures: dict[str, list[str]] = {}
        for index, row in enumerate(publication_rows, start=1):
            prefix = f"row={index}"
            canonical_rel = _text(row, "CanonicalRelativePath").replace("\\", "/")
            item_failures: list[str] = []
            canonical = _run_relative_path(run_root, _text(row, "CanonicalRelativePath"))
            published = _run_relative_path(run_root, _text(row, "PublishedRelativePath"))
            if canonical is None or published is None:
                item_failures.append("invalid_or_escaping_path")
                publication_failures.extend(prefix + ":" + value for value in item_failures)
                canonical_row_failures.setdefault(canonical_rel or publication_rel, []).extend(item_failures)
                continue
            if not _io_path(canonical).is_file() or not _io_path(published).is_file():
                item_failures.append("declared_file_missing")
                publication_failures.extend(prefix + ":" + value for value in item_failures)
                canonical_row_failures.setdefault(canonical_rel, []).extend(item_failures)
                continue
            canonical_hash = _sha256(canonical)
            published_hash = _sha256(published)
            if canonical_hash != published_hash:
                item_failures.append("canonical_published_bytes_differ")
            if canonical_hash.lower() != _text(row, "CanonicalSHA256").lower():
                item_failures.append("canonical_hash_mismatch")
            if published_hash.lower() != _text(row, "PublishedSHA256").lower():
                item_failures.append("published_hash_mismatch")
            if not _close(_number(row, "ByteSize"), _io_path(canonical).stat().st_size, atol=0):
                item_failures.append("byte_size_mismatch")
            if _text(row, "PublishStatus").upper() != "PUBLISHED_HASH_VERIFIED":
                item_failures.append("publish_status_not_verified")
            destination = _text(row, "PublishedRelativePath").replace("\\", "/").lower()
            previous = destinations.get(destination)
            if previous and previous != canonical_hash:
                item_failures.append("conflicting_canonical_authority")
            destinations[destination] = canonical_hash
            publication_failures.extend(prefix + ":" + value for value in item_failures)
            canonical_row_failures.setdefault(canonical_rel, []).extend(item_failures)
        checks.append(_check("manifest_integrity", publication_rel, "component_mirrors_match_canonical_bytes", publication_rows, publication_failures))
        for canonical_rel, failures in canonical_row_failures.items():
            header, rows = _read_rows(run_root / canonical_rel) if canonical_rel.lower().endswith(".csv") else ([], [])
            checks.append(
                _check(
                    "manifest_integrity",
                    canonical_rel,
                    "canonical_artifact_publication_binding",
                    rows if rows else ([{"path": canonical_rel}] if not failures else []),
                    failures,
                )
            )

        component_summary_rel = "reports/csv/component_artifact_publication_summary.csv"
        _summary_header, component_summary_rows = _read_rows(run_root / component_summary_rel)
        component_failures: list[str] = []
        scenario_rows = _read_rows(run_root / "reports/csv/scenario_summary.csv")[1]
        scenario = scenario_rows[0] if scenario_rows else {}
        by_component: dict[str, list[dict[str, str]]] = {}
        for row in publication_rows:
            by_component.setdefault(_text(row, "Component"), []).append(row)
        observed_components = {_text(row, "Component"): row for row in component_summary_rows}
        for component, row in observed_components.items():
            if not _text(row, "ScenarioID") or _text(row, "ScenarioID") != _text(scenario, "ScenarioID"):
                component_failures.append(f"component={component}:scenario_identity_mismatch")
            if not _text(row, "ConfigHash") or _text(row, "ConfigHash") != _text(scenario, "ConfigHash"):
                component_failures.append(f"component={component}:config_hash_mismatch")
            if not _text(row, "RunnerProfile") or _text(row, "RunnerProfile") != _text(scenario, "RunnerProfile"):
                component_failures.append(f"component={component}:runner_profile_mismatch")
            source = by_component.get(component, [])
            expected_counts = {
                "SourceArtifactCount": len(source),
                "CSVCount": sum(_text(item, "ArtifactType").lower() == "csv" for item in source),
                "RasterImageCount": sum(_text(item, "ArtifactType").lower() == "image" for item in source),
                "JSONCount": sum(_text(item, "ArtifactType").lower() == "json" for item in source),
                "MATCount": sum(_text(item, "ArtifactType").lower() == "mat" for item in source),
            }
            for field, value in expected_counts.items():
                if not _close(_number(row, field), value, atol=0):
                    component_failures.append(f"component={component}:{field}_mismatch")
            expected_status = "PUBLISHED_HASH_VERIFIED" if source else "NO_CANONICAL_EVIDENCE"
            if _text(row, "PublicationStatus").upper() != expected_status:
                component_failures.append(f"component={component}:publication_status_mismatch")
        if not component_summary_rows:
            component_failures.append("component_summary_missing_or_empty")
        checks.append(_check("manifest_integrity", component_summary_rel, "component_summary_reconciles_manifest", component_summary_rows, component_failures))

    raw_index_rel = "raw/evidence/raw_evidence_index.csv"
    raw_header, raw_rows = _read_rows(run_root / raw_index_rel)
    if raw_rows:
        raw_failures: list[str] = []
        for index, row in enumerate(raw_rows, start=1):
            prefix = f"row={index}"
            relative_value = _text(row, "RelativePath")
            run_candidate = _run_relative_path(run_root, relative_value)
            index_candidate = _run_relative_path(run_root, f"raw/evidence/{relative_value}")
            existing = [
                candidate
                for candidate in (run_candidate, index_candidate)
                if candidate is not None and _io_path(candidate).is_file()
            ]
            if not existing:
                raw_failures.append(prefix + ":indexed_table_missing")
                continue
            if len({candidate.resolve() for candidate in existing}) != 1:
                raw_failures.append(prefix + ":indexed_path_ambiguous")
                continue
            target = existing[0]
            header, rows = _read_rows(target)
            if _sha256(target).lower() != _text(row, "SHA256").lower():
                raw_failures.append(prefix + ":indexed_hash_mismatch")
            if not _close(_number(row, "RowCount"), len(rows), atol=0):
                raw_failures.append(prefix + ":indexed_row_count_mismatch")
            if not _close(_number(row, "ColumnCount"), len(header), atol=0):
                raw_failures.append(prefix + ":indexed_column_count_mismatch")
            key_spec = _text(row, "PrimaryKeyColumns")
            if key_spec and not key_spec.startswith("row_order_only"):
                keys = key_spec.split("|")
                if not all(key in header for key in keys):
                    raw_failures.append(prefix + ":primary_key_column_missing")
                else:
                    values = [tuple(item.get(key, "") for key in keys) for item in rows]
                    duplicate_count = len(values) - len(set(values))
                    if not _close(_number(row, "DuplicateKeyCount"), duplicate_count, atol=0):
                        raw_failures.append(prefix + ":duplicate_key_count_mismatch")
            item_failures = [
                value.split(":", 1)[1]
                for value in raw_failures
                if value.startswith(prefix + ":")
            ]
            target_rel = target.relative_to(run_root).as_posix()
            checks.append(
                _check(
                    "manifest_integrity",
                    target_rel,
                    "raw_evidence_index_binding",
                    rows,
                    item_failures,
                )
            )
        checks.append(_check("manifest_integrity", raw_index_rel, "raw_evidence_index_matches_tables", raw_rows, raw_failures))
    return checks


def _normalized_column(name: str) -> str:
    return "".join(ch for ch in str(name).lower() if ch.isalnum())


def _audit_metric_output_tables(run_root: Path) -> list[AuditCheck]:
    """Validate the canonical long-form metric catalog and category views.

    A metric only counts as runtime coverage when its persisted source exists
    in the same run tree.  Config-only, disabled and unavailable descriptors
    remain useful catalog rows, but they cannot be promoted to observed
    evidence and cannot count toward runtime coverage.
    """

    checks: list[AuditCheck] = []
    aggregate_tables = {
        "reports/csv/lls_output_metric_rows.csv",
    }
    for relative in METRIC_OUTPUT_TABLES:
        header, rows = _read_rows(run_root / relative)
        if not header and not rows:
            continue
        missing_columns = sorted(METRIC_OUTPUT_REQUIRED_COLUMNS - set(header))
        checks.append(
            _check(
                "metric_output",
                relative,
                "required_metric_catalog_columns",
                rows,
                missing_columns,
            )
        )
        if missing_columns:
            continue

        identity_failures: list[str] = []
        coverage_failures: list[str] = []
        value_failures: list[str] = []
        source_failures: list[str] = []
        observed_keys: set[tuple[str, str, str, str]] = set()
        expected_category = Path(relative).stem
        for index, row in enumerate(rows, start=1):
            prefix = f"row={index}"
            category_code = _text(row, "CategoryCode")
            category_key = _text(row, "CategoryKey")
            category_name = _text(row, "CategoryName")
            metric_key = _text(row, "MetricKey")
            metric_name = _text(row, "MetricName")
            entity = _text(row, "Entity")
            statistic = _text(row, "Statistic")
            if not all((category_code, category_key, category_name, metric_key, metric_name)):
                identity_failures.append(prefix + ":missing_category_or_metric_identity")
            if relative not in aggregate_tables and category_key != expected_category:
                identity_failures.append(
                    prefix + f":CategoryKey_mismatch:{category_key or 'missing'}!={expected_category}"
                )
            key = (category_key, metric_key, entity, statistic)
            if key in observed_keys:
                identity_failures.append(prefix + ":duplicate_metric_entity_statistic_key")
            observed_keys.add(key)

            availability = _text(row, "Availability").lower()
            if availability not in METRIC_OUTPUT_AVAILABILITY:
                coverage_failures.append(
                    prefix + f":invalid_availability:{availability or 'missing'}"
                )
            counts = _boolean(row, "CountsTowardCoverage")
            if counts is None:
                coverage_failures.append(prefix + ":CountsTowardCoverage_not_boolean")
                continue
            runtime_evidence = availability in {"observed", "derived"}
            if counts is not runtime_evidence:
                coverage_failures.append(
                    prefix + f":coverage_availability_mismatch:{int(counts)}:{availability}"
                )

            numeric_text = _text(row, "ValueNumeric") if "ValueNumeric" in header else ""
            numeric_value = _number(row, "ValueNumeric") if "ValueNumeric" in header else None
            value_text = _text(row, "ValueText")
            if counts and numeric_value is None and not value_text:
                value_failures.append(prefix + ":counted_metric_has_no_value")
            if numeric_value is not None and value_text:
                try:
                    rendered_value = float(value_text)
                except (TypeError, ValueError):
                    rendered_value = None
                if (
                    rendered_value is not None
                    and math.isfinite(rendered_value)
                    and not math.isclose(
                        numeric_value,
                        rendered_value,
                        rel_tol=5e-5,
                        abs_tol=1e-12,
                    )
                ):
                    value_failures.append(prefix + ":ValueNumeric_ValueText_mismatch")
            unit = _text(row, "Unit").strip().lower()
            if numeric_value is not None:
                if unit in {"fraction", "probability"} and not (
                    -1e-12 <= numeric_value <= 1.0 + 1e-12
                ):
                    value_failures.append(prefix + f":{unit}_outside_unit_interval")
                if unit in {"percent", "%"} and not (
                    -1e-12 <= numeric_value <= 100.0 + 1e-12
                ):
                    value_failures.append(prefix + ":percent_outside_0_100")
                normalized_statistic = _normalized_column(statistic)
                if normalized_statistic in {
                    "count", "samplecount", "trialcount", "errorcount",
                }:
                    if numeric_value < 0 or not math.isclose(
                        numeric_value, round(numeric_value), abs_tol=1e-9
                    ):
                        value_failures.append(prefix + ":count_not_nonnegative_integer")
            elif numeric_text and numeric_text.lower() not in {
                "nan", "+nan", "-nan", "not_available", "n/a", "na",
            }:
                value_failures.append(prefix + ":ValueNumeric_not_finite_or_nan")

            source_text = _text(row, "SourceArtifact")
            if counts:
                source_path = _run_relative_path(run_root, source_text)
                if not source_text:
                    source_failures.append(prefix + ":counted_metric_source_missing")
                elif source_path is None:
                    source_failures.append(prefix + ":counted_metric_source_not_run_relative")
                elif not _io_path(source_path).is_file():
                    source_failures.append(
                        prefix + f":counted_metric_source_not_found:{source_text}"
                    )

        checks.extend(
            [
                _check(
                    "metric_output",
                    relative,
                    "metric_identity_and_unique_key",
                    rows,
                    identity_failures,
                ),
                _check(
                    "metric_output",
                    relative,
                    "availability_matches_runtime_coverage",
                    rows,
                    coverage_failures,
                ),
                _check(
                    "metric_output",
                    relative,
                    "metric_values_and_units_are_coherent",
                    rows,
                    value_failures,
                ),
                _check(
                    "metric_output",
                    relative,
                    "counted_metrics_bind_existing_run_artifacts",
                    rows,
                    source_failures,
                ),
            ]
        )
    return checks


def _audit_metric_coverage_table(run_root: Path) -> list[AuditCheck]:
    """Recompute every coverage row from the canonical metric-row ledger."""

    header, rows = _read_rows(run_root / METRIC_COVERAGE_TABLE)
    detail_header, detail_rows = _read_rows(
        run_root / "reports/csv/lls_output_metric_rows.csv"
    )
    if not header and not rows:
        return []
    checks: list[AuditCheck] = []
    missing_columns = sorted(METRIC_COVERAGE_REQUIRED_COLUMNS - set(header))
    checks.append(
        _check(
            "metric_coverage",
            METRIC_COVERAGE_TABLE,
            "required_coverage_columns",
            rows,
            missing_columns,
        )
    )
    if missing_columns:
        return checks
    detail_missing = sorted(METRIC_OUTPUT_REQUIRED_COLUMNS - set(detail_header))
    checks.append(
        _check(
            "metric_coverage",
            METRIC_COVERAGE_TABLE,
            "canonical_metric_ledger_present",
            rows,
            detail_missing or ([] if detail_rows else ["metric_ledger_empty"]),
        )
    )
    if detail_missing or not detail_rows:
        return checks

    grouped: dict[tuple[str, str], list[dict[str, str]]] = {}
    for detail in detail_rows:
        grouped.setdefault(
            (_text(detail, "CategoryKey"), _text(detail, "MetricKey")), []
        ).append(detail)
    observed_keys: set[tuple[str, str]] = set()
    failures: list[str] = []
    count_fields = {
        "observed": "ObservedRowCount",
        "derived": "DerivedRowCount",
        "config_only": "ConfigOnlyRowCount",
        "disabled": "DisabledRowCount",
        "placeholder": "PlaceholderRowCount",
        "not_supported": "NotSupportedRowCount",
        "not_available": "NotAvailableRowCount",
        "not_exercised": "NotExercisedRowCount",
    }
    precedence = (
        "observed", "derived", "config_only", "disabled", "placeholder",
        "not_supported", "not_exercised", "not_available",
    )
    for index, row in enumerate(rows, start=1):
        prefix = f"row={index}"
        key = (_text(row, "CategoryKey"), _text(row, "MetricKey"))
        if not all(key):
            failures.append(prefix + ":coverage_key_missing")
            continue
        if key in observed_keys:
            failures.append(prefix + ":duplicate_coverage_key")
        observed_keys.add(key)
        source_rows = grouped.get(key, [])
        if not source_rows:
            # Some primary catalogs intentionally suppress unmeasured rows
            # (notably beam-management evidence) so a table cannot be padded
            # with non-observations.  The coverage catalog may still declare
            # that gap, but it must be an exact zero-count, non-covered,
            # source-free not_available row.
            zero_fields = (
                "CoveredRowCount", "ObservedRowCount", "DerivedRowCount",
                "ConfigOnlyRowCount", "DisabledRowCount",
                "PlaceholderRowCount", "NotSupportedRowCount",
                "NotAvailableRowCount", "NotExercisedRowCount",
            )
            if (
                _text(row, "Availability").lower() != "not_available"
                or _boolean(row, "CountsTowardCoverage") is not False
                or any(not _close(_number(row, field), 0, atol=0) for field in zero_fields)
                or _text(row, "SourceArtifacts")
            ):
                failures.append(prefix + ":unmeasured_catalog_gap_not_fail_closed")
            continue
        states = [_text(item, "Availability").lower() for item in source_rows]
        expected_counts = {
            state: sum(value == state for value in states) for state in count_fields
        }
        for state, field in count_fields.items():
            actual = _number(row, field)
            if actual is None or actual < 0 or not _close(
                actual, expected_counts[state], atol=0
            ):
                failures.append(prefix + f":{field}_mismatch")
        covered = expected_counts["observed"] + expected_counts["derived"]
        if not _close(_number(row, "CoveredRowCount"), covered, atol=0):
            failures.append(prefix + ":CoveredRowCount_mismatch")
        if _boolean(row, "CountsTowardCoverage") is not (covered > 0):
            failures.append(prefix + ":CountsTowardCoverage_mismatch")
        expected_availability = next(
            (state for state in precedence if expected_counts[state] > 0),
            "not_available",
        )
        if _text(row, "Availability").lower() != expected_availability:
            failures.append(prefix + ":Availability_rollup_mismatch")
        expected_sources = sorted(
            {
                _text(item, "SourceArtifact")
                for item in source_rows
                if _text(item, "SourceArtifact")
            }
        )
        observed_sources = sorted(
            value for value in _text(row, "SourceArtifacts").split("|") if value
        )
        if observed_sources != expected_sources:
            failures.append(prefix + ":SourceArtifacts_rollup_mismatch")
    missing_rollups = sorted(set(grouped) - observed_keys)
    failures.extend(
        f"missing_coverage_row:{category}:{metric}"
        for category, metric in missing_rollups
    )
    checks.append(
        _check(
            "metric_coverage",
            METRIC_COVERAGE_TABLE,
            "coverage_recomputed_from_metric_ledger",
            rows,
            failures,
        )
    )
    return checks


def _audit_domain_runtime_tables(
    run_root: Path,
    scenario_summary: dict[str, str],
) -> list[AuditCheck]:
    """Apply baseline value contracts to canonical component-domain CSVs.

    These checks do not turn a short run into statistical qualification. They
    guarantee that every selected domain table has observations, coherent run
    identity, physically bounded populated probabilities/counts and no proxy
    or fallback row mislabeled as in-path truth.
    """

    extended_root = _io_path(run_root)
    resolved_config = _load_resolved_config(run_root)
    resolved_primary_tables = primary_link_tables(run_root)
    candidates: list[tuple[str, Path]] = []
    for current, _directories, filenames in os.walk(extended_root):
        current_path = Path(current)
        relative_directory = current_path.relative_to(extended_root)
        for filename in filenames:
            if not filename.lower().endswith(".csv"):
                continue
            relative = (relative_directory / filename).as_posix()
            if relative in resolved_primary_tables.values() or relative in CONTROL_TABLES or relative in DERIVED_LINK_TABLES:
                # These tables have stronger, schema-specific checks above;
                # do not reclassify an explicitly non-applicable derived
                # table as missing through the generic domain rule.
                continue
            if relative in DOMAIN_RUNTIME_EXACT or any(
                relative.startswith(prefix) for prefix in DOMAIN_RUNTIME_PREFIXES
            ):
                candidates.append((relative, run_root / relative_directory / filename))
    checks: list[AuditCheck] = []
    probability_columns = {
        "ber", "bler", "fer", "ccdf", "cdf", "fraction", "passrate",
        "successrate", "failurerate", "collisionrate", "falsealarmrate",
        "misseddetectionrate", "detectionprobability", "falsealarmprobability",
        "misseddetectionprobability", "probability", "confidencelevel",
    }
    for relative, path in sorted(candidates):
        header, rows = _read_rows(path)
        schema_failures: list[str] = []
        if not header:
            schema_failures.append("missing_schema")
        if len(header) != len(set(header)):
            schema_failures.append("duplicate_column_names")
        empty_means_no_event = _empty_domain_table_is_valid_zero_event(
            relative, run_root
        )
        required, evaluated = _domain_table_applicability(
            relative, run_root, scenario_summary, resolved_config
        )
        if not rows and not empty_means_no_event and required:
            schema_failures.append("missing_runtime_rows")
        checks.append(_check(
            "domain_runtime", relative, "schema_and_runtime_rows", rows,
            schema_failures, required=required, evaluated=evaluated,
        ))
        if not required and not evaluated:
            continue
        if schema_failures:
            continue

        identity_failures: list[str] = []
        application_identity_failures: list[str] = []
        value_failures: list[str] = []
        truth_failures: list[str] = []
        expected_scenario = _text(scenario_summary, "ScenarioID")
        expected_hash = _text(scenario_summary, "ConfigHash")
        snapshot_time_limit_s: float | None = None
        if relative == "channel/csv/channel_snapshots.csv":
            overview_header, overview_rows = _read_rows(
                run_root / "reports/csv/live_scenario_overview.csv"
            )
            if overview_header and overview_rows:
                total_slots = _number(overview_rows[0], "total_slots")
                scs_khz = _number(overview_rows[0], "scs_khz")
                if (
                    total_slots is not None
                    and total_slots > 0
                    and scs_khz is not None
                    and scs_khz > 0
                ):
                    # NR slot duration is 1 ms / 2^mu and SCS=15*2^mu kHz.
                    slot_duration_s = 1e-3 * 15.0 / scs_khz
                    snapshot_time_limit_s = (total_slots + 1.0) * slot_duration_s
        for index, row in enumerate(rows, start=1):
            prefix = f"row={index}"
            if "ScenarioID" in header:
                observed = _text(row, "ScenarioID")
                if not observed or (expected_scenario and observed != expected_scenario):
                    identity_failures.append(prefix + ":ScenarioID_mismatch_or_missing")
            if "ConfigHash" in header and relative not in LOCAL_CONFIG_HASH_TABLES:
                observed = _text(row, "ScenarioConfigHash", "ConfigHash")
                if not observed or (expected_hash and observed.lower() != expected_hash.lower()):
                    identity_failures.append(prefix + ":ConfigHash_mismatch_or_missing")
            if "RunID" in header and not _text(row, "RunID"):
                identity_failures.append(prefix + ":RunID_missing")
            if "RunId" in header and not _text(row, "RunId"):
                identity_failures.append(prefix + ":RunId_missing")
            if "ExecutionID" in header and not _text(row, "ExecutionID"):
                identity_failures.append(prefix + ":ExecutionID_missing")
            if relative == "reports/csv/runtime_config_application_evidence.csv":
                run_id = _text(row, "RunId")
                run_tag = _text(row, "RunTag")
                if not run_id or not run_tag or run_id != run_tag:
                    application_identity_failures.append(
                        prefix + f":RunId_RunTag_mismatch:{run_id or 'missing'}!={run_tag or 'missing'}"
                    )
            if relative == "reports/csv/live_scenario_overview.csv":
                required_text = ("run_id", "scenario_id", "duplex_mode")
                required_numeric = (
                    "center_frequency_hz", "bandwidth_hz", "scs_khz", "n_rb",
                    "num_frames", "total_slots",
                )
                for column in required_text:
                    if not _text(row, column):
                        value_failures.append(prefix + f":{column}_missing")
                for column in required_numeric:
                    value = _number(row, column)
                    if value is None or not math.isfinite(value) or value <= 0:
                        value_failures.append(prefix + f":{column}_missing_or_nonpositive")
                if _boolean(row, "strict_mode") is None:
                    value_failures.append(prefix + ":strict_mode_missing_or_invalid")
                honesty_mode = _text(row, "honesty_mode").strip().lower()
                if honesty_mode != "strict":
                    value_failures.append(prefix + ":honesty_mode_missing_or_not_strict")
            if relative in {
                "reports/csv/prach_correlation_trace.csv",
                "reports/csv/prach_correlation_traces.csv",
            }:
                if _number(row, "lag_samples") is None:
                    value_failures.append(prefix + ":lag_samples_missing")
                if _number(row, "correlation_abs") is None:
                    value_failures.append(prefix + ":correlation_abs_missing")
                if _text(row, "truth_status").lower() != "real_lls_evidence":
                    truth_failures.append(prefix + ":truth_status_not_real_lls_evidence")
            if relative == "channel/csv/channel_snapshots.csv":
                sample_time_s = _number(row, "SampleTimeSec")
                sample_rate_hz = _number(row, "SampleRateHz")
                sample_rate_source = _text(row, "SampleRateSource")
                if sample_time_s is None or not math.isfinite(sample_time_s) or sample_time_s < 0:
                    value_failures.append(prefix + ":SampleTimeSec_missing_nonfinite_or_negative")
                elif snapshot_time_limit_s is not None and sample_time_s > snapshot_time_limit_s + 1e-12:
                    value_failures.append(
                        prefix + f":SampleTimeSec_outside_run_duration:{sample_time_s}>{snapshot_time_limit_s}"
                    )
                if sample_rate_hz is None or not math.isfinite(sample_rate_hz) or sample_rate_hz <= 0:
                    value_failures.append(prefix + ":SampleRateHz_missing_or_nonpositive")
                if not sample_rate_source:
                    value_failures.append(prefix + ":SampleRateSource_missing")

            for column in header:
                normalized = _normalized_column(column)
                value = _number(row, column)
                if value is None:
                    continue
                if normalized in probability_columns and not (-1e-12 <= value <= 1.0 + 1e-12):
                    value_failures.append(prefix + f":{column}_outside_unit_interval")
                is_count = normalized.endswith(("count", "bytes", "bits", "trials", "errors"))
                is_duration = normalized.endswith(("durationms", "durations", "latencyms", "delayms"))
                is_linear_resource = normalized.endswith(("energymj", "energyj", "powermw", "powerw"))
                if (is_count or is_duration or is_linear_resource) and value < -1e-12:
                    value_failures.append(prefix + f":{column}_negative")

            if _text(row, "EvidenceScope").lower() == "in_path":
                if _boolean(row, "FallbackFlag") is True:
                    truth_failures.append(prefix + ":FallbackFlag_true_in_path")
                if _boolean(row, "PlaceholderFlag") is True:
                    truth_failures.append(prefix + ":PlaceholderFlag_true_in_path")
                lineage = " ".join(
                    _text(row, name).lower()
                    for name in ("TruthStatus", "ExecutionBackend", "ApproximationMode")
                )
                if any(token in lineage for token in BAD_TRUTH_TOKENS):
                    truth_failures.append(prefix + ":proxy_or_fallback_labeled_in_path")

        checks.extend(
            [
                _check("domain_runtime", relative, "scenario_execution_identity", rows, identity_failures),
                _check("domain_runtime", relative, "populated_physical_value_ranges", rows, value_failures),
                _check("domain_runtime", relative, "in_path_truth_proxy_separation", rows, truth_failures),
            ]
        )
        if relative == "reports/csv/runtime_config_application_evidence.csv":
            sequences = [_number(row, "ApplicationEventSequence") for row in rows]
            event_ids = [_text(row, "ApplicationEventID") for row in rows]
            if (
                any(value is None for value in sequences)
                or [int(value) for value in sequences if value is not None]
                != list(range(1, len(rows) + 1))
            ):
                application_identity_failures.append("ApplicationEventSequence_not_contiguous_from_one")
            if any(not value for value in event_ids) or len(event_ids) != len(set(event_ids)):
                application_identity_failures.append("ApplicationEventID_missing_or_duplicate")
            checks.append(
                _check(
                    "domain_runtime",
                    relative,
                    "runtime_config_application_identity",
                    rows,
                    application_identity_failures,
                )
            )
    return checks


def _audit_dynamic_tdd_runtime_channel_reciprocity(
    run_root: Path,
    link_rows: dict[str, list[dict[str, str]]],
) -> list[AuditCheck]:
    """Require one exact moving-TDD fading state and executed-path angles.

    A TDD CDL/TDL link at nonzero Doppler must not instantiate unrelated DL
    and UL fading processes. The persisted primary rows prove state/seed
    sharing and direction reversal; when the scenario requests the PHY signal
    diagnostic, angle rows must bind to the same executed path-gain tensor.
    """

    relative = "reports/csv/phy_signal_diagnostic_source.csv"
    resolved = _load_resolved_config(run_root)
    frequency = resolved.get("frequency", {}) if isinstance(resolved, dict) else {}
    frame = resolved.get("frame", {}) if isinstance(resolved, dict) else {}
    channels = resolved.get("channels", {}) if isinstance(resolved, dict) else {}
    channel_model = resolved.get("channel_model", {}) if isinstance(resolved, dict) else {}
    output = resolved.get("output", {}) if isinstance(resolved, dict) else {}
    duplex = str(
        frequency.get("duplex_mode", frame.get("duplex", ""))
        if isinstance(frequency, dict) and isinstance(frame, dict)
        else ""
    ).strip().upper()
    model = str(
        channels.get("model_type", channel_model.get("model_type", ""))
        if isinstance(channels, dict) and isinstance(channel_model, dict)
        else ""
    ).strip().upper()
    profile = str(
        channels.get("profile", channel_model.get("profile", ""))
        if isinstance(channels, dict) and isinstance(channel_model, dict)
        else ""
    ).strip().upper()
    doppler_raw = None
    if isinstance(channels, dict):
        doppler_raw = channels.get("max_doppler_hz", channels.get("doppler_hz"))
    if doppler_raw is None and isinstance(channel_model, dict):
        doppler_raw = channel_model.get("max_doppler_hz", channel_model.get("doppler_hz"))
    try:
        doppler_hz = float(doppler_raw)
    except (TypeError, ValueError):
        doppler_hz = math.nan
    fading = model in {"CDL", "TDL"} or profile.startswith(("CDL-", "TDL-"))
    required = duplex == "TDD" and fading and math.isfinite(doppler_hz) and doppler_hz > 0
    if not required:
        return []

    rows = [row for direction in ("DL", "UL") for row in link_rows.get(direction, [])]
    provenance_failures: list[str] = []
    state_keys: set[str] = set()
    seeds: set[int] = set()
    trial_hashes: set[str] = set()
    for direction in ("DL", "UL"):
        for index, row in enumerate(link_rows.get(direction, []), start=1):
            prefix = f"{direction}:row={index}"
            state_key = _text(row, "RuntimeChannelStateKey")
            link_key = _text(row, "RuntimeChannelLinkKey")
            seed = _number(row, "RuntimeChannelSeed")
            path_hash = _text(row, "RuntimeChannelPathGainsSHA256")
            if not state_key:
                provenance_failures.append(prefix + ":state_key_missing")
            else:
                state_keys.add(state_key)
            if not link_key or direction.lower() not in link_key.lower():
                provenance_failures.append(prefix + ":directional_link_key_missing_or_mismatched")
            if not _whole(seed, minimum=1):
                provenance_failures.append(prefix + ":seed_missing_or_invalid")
            else:
                seeds.add(int(seed))
            if _boolean(row, "RuntimeChannelReciprocityExact") is not True:
                provenance_failures.append(prefix + ":exact_reciprocity_not_true")
            if _text(row, "RuntimeChannelReciprocityDirection").upper() != direction:
                provenance_failures.append(prefix + ":reciprocity_direction_mismatch")
            if _text(row, "RuntimeChannelReciprocitySource") != (
                "matlab_nr_channel_swapTransmitAndReceive_shared_fading_timeline"
            ):
                provenance_failures.append(prefix + ":reciprocity_source_not_exact_runtime_swap")
            if _text(row, "RuntimeChannelReciprocityApproximationMode") != "none_dynamic_exact":
                provenance_failures.append(prefix + ":reciprocity_approximation_mode_not_none_dynamic_exact")
            canonical_samples = _number(row, "RuntimeChannelCanonicalInputSamples")
            start_sample = _number(row, "RuntimeChannelStartSample")
            end_sample = _number(row, "RuntimeChannelEndSample")
            if canonical_samples is None or canonical_samples <= 0:
                provenance_failures.append(prefix + ":canonical_input_sample_count_missing_or_nonpositive")
            elif not _close(end_sample, (start_sample or 0) + canonical_samples, atol=0):
                provenance_failures.append(prefix + ":logical_channel_clock_interval_mismatch")
            if _boolean(row, "RuntimeChannelObjectClockExact") is not True:
                provenance_failures.append(prefix + ":canonical_object_clock_not_exact")
            expected_swapped = direction == "UL"
            if _boolean(row, "RuntimeChannelTransmitAndReceiveSwapped") is not expected_swapped:
                provenance_failures.append(prefix + ":transmit_receive_swap_state_mismatch")
            if not _is_sha256(path_hash):
                provenance_failures.append(prefix + ":executed_path_gain_hash_missing_or_invalid")
            else:
                trial_hashes.add(path_hash.lower())
    if len(state_keys) != 1:
        provenance_failures.append(f"shared_state_key_count={len(state_keys)};expected=1")
    if len(seeds) != 1:
        provenance_failures.append(f"shared_seed_count={len(seeds)};expected=1")

    checks = [_check(
        "runtime_channel_reciprocity",
        "air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv",
        "dynamic_TDD_shared_exact_fading_state",
        rows,
        provenance_failures,
    )]

    diagnostic_requested = bool(
        isinstance(output, dict) and output.get("phy_signal_diagnostic_enabled", False)
    )
    if not diagnostic_requested:
        return checks
    header, all_diagnostic_rows = _read_rows(run_root / relative)
    angle_rows = [
        row for row in all_diagnostic_rows
        if _text(row, "Panel") == "runtime_channel_angles"
    ]
    required_columns = {
        "SnapshotID", "Direction", "CellID", "UEIndex", "RNTI", "SFN",
        "Slot", "AbsoluteSlot", "PathIndex", "PathDelay_s",
        "AzimuthDeparture_deg", "AzimuthArrival_deg", "ZenithDeparture_deg",
        "ZenithArrival_deg", "PowerLinear", "Power_dB",
        "AngleCoordinateFrame", "AngleEvidenceSource",
        "RuntimeChannelStateKey", "RuntimeChannelLinkKey",
        "RuntimeChannelSeed", "RuntimeChannelReciprocityExact",
        "RuntimeChannelReciprocityDirection", "RuntimeChannelReciprocitySource",
        "RuntimeChannelReciprocityApproximationMode",
        "RuntimeChannelTransmitAndReceiveSwapped", "GridSHA256",
    }
    angle_failures = [
        "missing_columns=" + ",".join(sorted(required_columns - set(header)))
    ] if required_columns - set(header) else []
    by_direction: dict[str, list[dict[str, str]]] = {"DL": [], "UL": []}
    for index, row in enumerate(angle_rows, start=1):
        prefix = f"row={index}"
        direction = _text(row, "Direction").upper()
        if direction not in by_direction:
            angle_failures.append(prefix + ":invalid_direction")
            continue
        by_direction[direction].append(row)
        path_index = _number(row, "PathIndex")
        delay_s = _number(row, "PathDelay_s")
        azd = _number(row, "AzimuthDeparture_deg")
        aza = _number(row, "AzimuthArrival_deg")
        zd = _number(row, "ZenithDeparture_deg")
        za = _number(row, "ZenithArrival_deg")
        power_linear = _number(row, "PowerLinear")
        power_db = _number(row, "Power_dB")
        if not _whole(path_index, minimum=1):
            angle_failures.append(prefix + ":invalid_path_index")
        if delay_s is None or delay_s < 0:
            angle_failures.append(prefix + ":invalid_path_delay")
        if azd is None or not -180 <= azd <= 180 or aza is None or not -180 <= aza <= 180:
            angle_failures.append(prefix + ":azimuth_outside_3gpp_global_angle_range")
        if zd is None or not 0 <= zd <= 180 or za is None or not 0 <= za <= 180:
            angle_failures.append(prefix + ":zenith_outside_3gpp_global_angle_range")
        if power_linear is None or power_linear <= 0 or power_db is None:
            angle_failures.append(prefix + ":invalid_executed_path_power")
        elif not _close(power_db, 10.0 * math.log10(power_linear), atol=1e-9, rtol=1e-9):
            angle_failures.append(prefix + ":path_power_db_formula_mismatch")
        if _text(row, "AngleCoordinateFrame") != "3gpp_tr38901_global_coordinate_system":
            angle_failures.append(prefix + ":angle_coordinate_frame_mismatch")
        if _text(row, "AngleEvidenceSource") != "info_on_same_executed_runtime_channel_object":
            angle_failures.append(prefix + ":angle_source_not_same_executed_channel_object")
        if _text(row, "RuntimeChannelStateKey") not in state_keys:
            angle_failures.append(prefix + ":angle_state_key_not_primary_trial_state")
        if _text(row, "RuntimeChannelReciprocityDirection").upper() != direction:
            angle_failures.append(prefix + ":angle_reciprocity_direction_mismatch")
        if _boolean(row, "RuntimeChannelReciprocityExact") is not True:
            angle_failures.append(prefix + ":angle_exact_reciprocity_not_true")
        if _text(row, "RuntimeChannelReciprocityApproximationMode") != "none_dynamic_exact":
            angle_failures.append(prefix + ":angle_approximation_mode_not_none_dynamic_exact")
        if _text(row, "GridSHA256").lower() not in trial_hashes:
            angle_failures.append(prefix + ":angle_path_gain_hash_not_primary_trial_hash")
    if not angle_rows:
        angle_failures.append("runtime_channel_angles_rows_missing")
    if rows and any(
        not by_direction[direction]
        for direction in ("DL", "UL")
        if link_rows.get(direction)
    ):
        angle_failures.append("runtime_channel_angles_missing_active_direction")

    if by_direction["DL"] and by_direction["UL"]:
        dl_by_path = {int(_number(row, "PathIndex") or -1): row for row in by_direction["DL"]}
        ul_by_path = {int(_number(row, "PathIndex") or -1): row for row in by_direction["UL"]}
        if set(dl_by_path) != set(ul_by_path):
            angle_failures.append("DL_UL_path_index_set_mismatch")
        else:
            for path_index in sorted(dl_by_path):
                dl = dl_by_path[path_index]
                ul = ul_by_path[path_index]
                for lhs, rhs, label in (
                    ("AzimuthDeparture_deg", "AzimuthArrival_deg", "AoD_to_AoA"),
                    ("AzimuthArrival_deg", "AzimuthDeparture_deg", "AoA_to_AoD"),
                    ("ZenithDeparture_deg", "ZenithArrival_deg", "ZoD_to_ZoA"),
                    ("ZenithArrival_deg", "ZenithDeparture_deg", "ZoA_to_ZoD"),
                ):
                    if not _close(
                        _number(dl, lhs), _number(ul, rhs), atol=1e-12, rtol=1e-12
                    ):
                        angle_failures.append(
                            f"path={path_index}:{label}_reciprocal_swap_mismatch"
                        )

    checks.append(_check(
        "runtime_channel_reciprocity",
        relative,
        "executed_path_AoA_AoD_reciprocity_and_power",
        angle_rows,
        angle_failures,
    ))
    return checks


def _audit_prach_detection_trials(run_root: Path) -> list[AuditCheck]:
    relative = "components/prach/csv/prach_detection_trials.csv"
    header, rows = _read_rows(run_root / relative)
    if not header and not rows:
        return []
    required_columns = {
        "TrialID", "OccasionID", "PreambleIndexTx", "PreambleIndexDetected",
        "Detected", "PeakMetric", "Threshold", "TimingEstimate_samples",
        "TimingError_samples", "FalseAlarm", "MissedDetection", "Ambiguous",
        "Status", "ScenarioID", "ConfigHash", "EvidenceScope", "RunID",
        "ExecutionID", "EvidenceOrigin",
    }
    schema_failures = [
        "missing_columns=" + ",".join(sorted(required_columns - set(header)))
    ] if required_columns - set(header) else []
    value_failures: list[str] = []
    for index, row in enumerate(rows, start=1):
        prefix = f"row={index}"
        detected = _boolean(row, "Detected")
        false_alarm = _boolean(row, "FalseAlarm")
        missed = _boolean(row, "MissedDetection")
        ambiguous = _boolean(row, "Ambiguous")
        peak = _number(row, "PeakMetric")
        threshold = _number(row, "Threshold")
        tx_index = _number(row, "PreambleIndexTx")
        rx_index = _number(row, "PreambleIndexDetected")
        if None in {detected, false_alarm, missed, ambiguous}:
            value_failures.append(prefix + ":invalid_detection_boolean")
        if peak is None or threshold is None or peak < 0 or threshold < 0:
            value_failures.append(prefix + ":invalid_peak_or_threshold")
        elif detected is not (peak >= threshold):
            value_failures.append(prefix + ":Detected_not_equal_peak_threshold_decision")
        expected_missed = detected is False
        if missed is not expected_missed:
            value_failures.append(prefix + ":MissedDetection_inconsistent")
        expected_false_alarm = bool(detected) and (
            tx_index is None or rx_index is None or tx_index != rx_index
        )
        if false_alarm is not expected_false_alarm:
            value_failures.append(prefix + ":FalseAlarm_inconsistent")
        if detected and not ambiguous and tx_index != rx_index:
            value_failures.append(prefix + ":detected_unambiguous_preamble_mismatch")
        if not _text(row, "TrialID") or not _text(row, "OccasionID"):
            value_failures.append(prefix + ":runtime_identity_missing")
        if _text(row, "EvidenceScope").lower() != "in_path":
            value_failures.append(prefix + ":EvidenceScope_not_in_path")
        if _text(row, "Status").upper() != "MEASURED":
            value_failures.append(prefix + ":Status_not_MEASURED")
        if not _text(row, "EvidenceOrigin"):
            value_failures.append(prefix + ":EvidenceOrigin_missing")
    return [
        _check("domain_runtime", relative, "prach_detection_schema", rows, schema_failures),
        _check("domain_runtime", relative, "prach_detection_decision_reconciliation", rows, value_failures),
    ]


def _configured_tdd_symbol_direction(
    resolved_config: dict[str, Any], absolute_slot: int, symbol: int
) -> str | None:
    frequency = resolved_config.get("frequency", {})
    if not isinstance(frequency, dict) or str(
        frequency.get("duplex_mode", "")
    ).strip().upper() != "TDD":
        return None
    frame = resolved_config.get("frame", {})
    if not isinstance(frame, dict):
        return None
    common = frame.get("tdd_common", {})
    if not isinstance(common, dict):
        return None
    pattern = common.get("Pattern1", common.get("pattern1", {}))
    if not isinstance(pattern, dict):
        return None

    def value(*names: str) -> float | None:
        for name in names:
            raw = pattern.get(name)
            if isinstance(raw, (int, float)) and math.isfinite(float(raw)):
                return float(raw)
        return None

    scs = frequency.get("numerology_options_khz", frame.get("scs_khz"))
    if isinstance(scs, list):
        scs = scs[0] if len(scs) == 1 else None
    try:
        scs = float(scs)
    except (TypeError, ValueError):
        return None
    periodicity = value("PeriodicityMilliseconds", "periodicity_milliseconds")
    n_dl_slots = value("NumDownlinkSlots", "num_downlink_slots")
    n_dl_symbols = value("NumDownlinkSymbols", "num_downlink_symbols")
    n_ul_slots = value("NumUplinkSlots", "num_uplink_slots")
    n_ul_symbols = value("NumUplinkSymbols", "num_uplink_symbols")
    values = (periodicity, n_dl_slots, n_dl_symbols, n_ul_slots, n_ul_symbols)
    if any(item is None for item in values):
        return None
    period_slots_float = periodicity * scs / 15
    if not math.isclose(period_slots_float, round(period_slots_float), abs_tol=1e-9):
        return None
    period_slots = int(round(period_slots_float))
    slot = absolute_slot % period_slots
    n_dl_slots_i = int(n_dl_slots)
    n_ul_slots_i = int(n_ul_slots)
    n_dl_symbols_i = int(n_dl_symbols)
    n_ul_symbols_i = int(n_ul_symbols)
    if slot < n_dl_slots_i:
        return "DL"
    if slot >= period_slots - n_ul_slots_i:
        return "UL"
    if slot == n_dl_slots_i and symbol < n_dl_symbols_i:
        return "DL"
    ul_partial_slot = period_slots - n_ul_slots_i - 1
    if slot == ul_partial_slot and symbol >= 14 - n_ul_symbols_i:
        return "UL"
    return "GUARD"


def _exact_mu_context_authority(
    run_root: Path,
) -> dict[str, tuple[str, int, str, int]]:
    """Return contexts belonging to complete finalized exact MU groups."""
    candidates = (
        ("DL", "air_interface/csv/dl_pdsch_trials.csv"),
        ("UL", "air_interface/csv/ul_pusch_trials.csv"),
    )
    groups: dict[
        tuple[str, int, str], list[tuple[str, int, int]]
    ] = {}
    for expected_direction, relative in candidates:
        _, trial_rows = _read_rows(run_root / relative)
        for row in trial_rows:
            context = _text(row, "GrantContextId").strip()
            if not context:
                context = _text(row, "FrozenGrantContextId").strip()
            group_token = _text(row, "MUMIMOGroupId").strip().lower()
            slot = _number(row, "Slot")
            ue_id = _number(row, "UEIndex")
            group_size = _number(row, "MUMIMOGroupSize")
            direction = _text(row, "Direction").strip().upper()
            if not direction:
                direction = expected_direction
            if (
                not context
                or direction != expected_direction
                or _boolean(row, "MUMIMOEnabled") is not True
                or group_token in {"", "nan", "na", "n/a", "none"}
                or not _whole(slot)
                or not _whole(ue_id, minimum=1)
                or not _whole(group_size, minimum=2)
                or _boolean(row, "FinalizedFlag") is not True
                or _boolean(row, "FallbackFlag") is True
                or _boolean(row, "PlaceholderFlag") is True
            ):
                continue
            key = (direction, int(slot), group_token)
            groups.setdefault(key, []).append(
                (context, int(ue_id), int(group_size))
            )

    authority: dict[str, tuple[str, int, str, int]] = {}
    for key, members in groups.items():
        expected_sizes = {member[2] for member in members}
        contexts = {member[0] for member in members}
        ue_ids = {member[1] for member in members}
        if len(expected_sizes) != 1:
            continue
        expected_size = next(iter(expected_sizes))
        if (
            len(members) != expected_size
            or len(contexts) != expected_size
            or len(ue_ids) != expected_size
        ):
            continue
        for context, ue_id, _ in members:
            authority[context] = (key[0], key[1], key[2], ue_id)
    return authority


def _observed_si_broadcast(row: dict[str, str], slots_per_frame: int) -> bool:
    """SI-RNTI is cell broadcast, not a missing unicast UE (38.321 7.1).

    The exemption requires the executed broadcast producer's retained grid
    and committed waveform interval; an RNTI value alone is insufficient.
    """
    if (
        _text(row, "direction").upper() != "DL"
        or _text(row, "channel").upper() != "PDSCH"
        or _number(row, "rnti") != 65535
        or _text(row, "authority") != "executed_broadcast_tx_grid_and_committed_waveform_interval"
        or _text(row, "waveform_port_domain") != "physical_element_domain"
        or not _is_sha256(_text(row, "transmit_grid_sha256"))
        or not _whole(_number(row, "associated_ssb_index0"))
        or not _whole(_number(row, "cell_id"), minimum=1)
        or slots_per_frame <= 0
    ):
        return False
    first = _number(row, "broadcast_start_sample")
    last = _number(row, "broadcast_end_sample_exclusive")
    rate = _number(row, "observation_sample_rate_hz")
    slot = _number(row, "absolute_slot")
    if not all(_whole(value) for value in (first, last, slot)) or rate is None or rate <= 0:
        return False
    slot_samples = rate * 0.01 / slots_per_frame
    return last > first and first <= slot * slot_samples + 1e-7 and last >= (slot + 1) * slot_samples - 1e-7


def _audit_observed_re_allocation(run_root: Path) -> list[AuditCheck]:
    relative = "frame_grid/csv/observed_re_allocation.csv"
    header, rows = _read_rows(run_root / relative)
    if not header and not rows:
        return []
    required_columns = {
        "ScenarioID", "ConfigHash", "absolute_slot", "sfn",
        "slot_within_frame", "direction", "channel", "subcarrier_start",
        "subcarrier_count", "symbol_index", "port_index", "re_count",
        "cell_id", "ue_id", "authority", "resolver", "allocation_id", "coordinate_precision",
        "evidence_scope", "run_tag", "status_classification", "active_flag",
    }
    schema_failures = [
        "missing_columns=" + ",".join(sorted(required_columns - set(header)))
    ] if required_columns - set(header) else []
    resolved = _load_resolved_config(run_root)
    frequency = resolved.get("frequency", {}) if isinstance(resolved, dict) else {}
    frame = resolved.get("frame", {}) if isinstance(resolved, dict) else {}
    bwp = resolved.get("bwp", {}) if isinstance(resolved, dict) else {}
    dl_bwp = bwp.get("dl", {}) if isinstance(bwp, dict) else {}
    resource_grid = resolved.get("resource_grid", {}) if isinstance(resolved, dict) else {}
    # The frequency catalog may advertise several supported numerologies;
    # that list is not the numerology executed by this run.  Audit exact RE
    # coordinates against the resolved active frame/BWP first and use the
    # catalog only when it contains a single unambiguous value.
    n_rb_raw = (
        dl_bwp.get("n_size_bwp") if isinstance(dl_bwp, dict) else None
    )
    if n_rb_raw is None and isinstance(resource_grid, dict):
        n_rb_raw = resource_grid.get("num_rbs")
    if n_rb_raw is None and isinstance(frequency, dict):
        n_rb_raw = frequency.get("n_size_grid")
    scs_raw = frame.get("scs_khz") if isinstance(frame, dict) else None
    if scs_raw is None and isinstance(dl_bwp, dict):
        scs_raw = dl_bwp.get("scs_khz")
    if scs_raw is None and isinstance(frequency, dict):
        scs_raw = frequency.get("numerology_options_khz")
    if isinstance(scs_raw, list):
        scs_raw = scs_raw[0] if len(scs_raw) == 1 else None
    try:
        n_subcarriers = 12 * int(n_rb_raw)
        slots_per_frame = int(round(10 * float(scs_raw) / 15))
    except (TypeError, ValueError):
        n_subcarriers = 0
        slots_per_frame = 0
    value_failures: list[str] = []
    # DL and UL occupy distinct RF carriers in FDD, so identical numerical
    # slot/symbol/subcarrier coordinates are not a collision across
    # directions.  In TDD the configured symbol-direction check above is the
    # authority that prevents simultaneous opposite-direction ownership.
    occupied: dict[
        tuple[int, str, int, int, int, int], tuple[str, str, int | None]
    ] = {}
    mu_authority = _exact_mu_context_authority(run_root)
    dl_channels = {"PSS", "SSS", "PBCH", "SSB", "PDCCH", "PDSCH", "CSI-RS", "CSIRS", "TRS"}
    ul_channels = {"PRACH", "PUCCH", "PUSCH", "SRS"}
    for index, row in enumerate(rows, start=1):
        prefix = f"row={index}"
        absolute_slot = _number(row, "absolute_slot")
        sfn = _number(row, "sfn")
        slot_in_frame = _number(row, "slot_within_frame")
        symbol = _number(row, "symbol_index")
        start = _number(row, "subcarrier_start")
        count = _number(row, "subcarrier_count")
        port = _number(row, "port_index")
        re_count = _number(row, "re_count")
        direction = _text(row, "direction").upper()
        channel = _text(row, "channel").upper()
        ue_id = _number(row, "ue_id")
        cell_id = _number(row, "cell_id")
        if not _whole(cell_id, minimum=1):
            value_failures.append(prefix + ":missing_or_invalid_cell_identity")
            continue
        if channel == "PRACH" or _text(row, "grid_domain") not in {"", "carrier_cp_ofdm"}:
            value_failures.append(prefix + ":noncarrier_native_grid_in_carrier_RE_table")
            continue
        if not all(_whole(value) for value in (absolute_slot, sfn, slot_in_frame, symbol, start, port)):
            value_failures.append(prefix + ":noninteger_or_negative_coordinate")
            continue
        if not _whole(count, minimum=1) or not _whole(re_count, minimum=1):
            value_failures.append(prefix + ":nonpositive_RE_run")
            continue
        if count != re_count:
            value_failures.append(prefix + ":re_count_not_equal_contiguous_subcarrier_count")
        if symbol >= 14:
            value_failures.append(prefix + ":symbol_outside_normal_CP_slot")
        if n_subcarriers <= 0 or start + count > n_subcarriers:
            value_failures.append(prefix + ":subcarrier_run_outside_configured_grid")
        if slots_per_frame <= 0 or slot_in_frame != absolute_slot % slots_per_frame:
            value_failures.append(prefix + ":slot_within_frame_mismatch")
        if slots_per_frame > 0 and sfn != (absolute_slot // slots_per_frame) % 1024:
            value_failures.append(prefix + ":sfn_mismatch")
        if channel in dl_channels and direction != "DL":
            value_failures.append(prefix + ":DL_channel_direction_mismatch")
        if channel in ul_channels and direction != "UL":
            value_failures.append(prefix + ":UL_channel_direction_mismatch")
        si_broadcast = _observed_si_broadcast(row, slots_per_frame)
        if si_broadcast and ue_id is not None:
            value_failures.append(prefix + ":cell_broadcast_must_not_claim_unicast_UE")
        if channel in {"PDSCH", "PUSCH"} and not _whole(ue_id, minimum=1) and not si_broadcast:
            value_failures.append(prefix + ":data_allocation_missing_UE_identity")
        allowed = _configured_tdd_symbol_direction(resolved, int(absolute_slot), int(symbol))
        if allowed is not None and allowed != direction:
            value_failures.append(prefix + f":TDD_symbol_direction={allowed};observed={direction}")
        if not _text(row, "authority").lower().startswith("executed_"):
            value_failures.append(prefix + ":authority_not_executed_runtime")
        if _text(row, "coordinate_precision") != "exact_contiguous_re_run":
            value_failures.append(prefix + ":coordinate_precision_not_exact")
        if _text(row, "evidence_scope") != "runtime_observed_tx_occupancy":
            value_failures.append(prefix + ":evidence_scope_not_runtime_observed")
        if _boolean(row, "active_flag") is not True:
            value_failures.append(prefix + ":active_flag_not_true")
        allocation = _text(row, "allocation_id")
        for subcarrier in range(int(start), int(start + count)):
            # Different cells own distinct transmitters/ports. Cochannel
            # inter-cell interference is not duplicate same-cell allocation.
            key = (int(cell_id), direction, int(absolute_slot), int(symbol), int(port), subcarrier)
            previous = occupied.get(key)
            current_ue = int(ue_id) if _whole(ue_id, minimum=1) else None
            current = (channel, allocation, current_ue)
            if previous is not None and previous != current:
                previous_mu = mu_authority.get(previous[1])
                current_mu = mu_authority.get(allocation)
                legal_mu_reuse = (
                    channel in {"PDSCH", "PUSCH"}
                    and previous[0] == channel
                    and previous_mu is not None
                    and current_mu is not None
                    and previous_mu[:3] == current_mu[:3]
                    and previous_mu[0] == direction
                    and previous_mu[1] == int(absolute_slot) + 1
                    and previous_mu[3] != current_mu[3]
                    and previous[2] == previous_mu[3]
                    and current_ue == current_mu[3]
                )
                if legal_mu_reuse:
                    continue
                value_failures.append(prefix + f":RE_collision_with={previous[0]}:{previous[1]}")
                break
            if previous is not None:
                value_failures.append(prefix + ":duplicate_RE_run")
                break
            occupied[key] = current
    return [
        _check("domain_runtime", relative, "exact_RE_allocation_schema", rows, schema_failures),
        _check("domain_runtime", relative, "exact_RE_bounds_direction_and_collision", rows, value_failures),
    ]


def _read_headerless_iq(path: Path) -> list[tuple[float, float]] | None:
    source = _io_path(path)
    if not source.is_file():
        return None
    values: list[tuple[float, float]] = []
    try:
        with source.open("r", encoding="utf-8-sig", newline="") as handle:
            for row in csv.reader(handle):
                if len(row) != 2:
                    return None
                i_value, q_value = float(row[0]), float(row[1])
                if not math.isfinite(i_value) or not math.isfinite(q_value):
                    return None
                values.append((i_value, q_value))
    except (OSError, UnicodeError, ValueError):
        return None
    return values


def _audit_final_tx_iq(run_root: Path) -> list[AuditCheck]:
    manifest_rel = "waveform/csv/final_tx_iq_capture_manifest.csv"
    header, rows = _read_rows(run_root / manifest_rel)
    if not header and not rows:
        return []
    required_columns = {
        "Direction", "SampleRateHz", "CenterFrequencyHz", "SampleCount",
        "PortCount", "CapturePoint", "WaveformAuthority",
        "CommonNormalizationFullScale", "NormalizedPeak", "NormalizedRMS",
        "CanonicalCSV", "CanonicalCSV_SHA256", "KeysightCSVPerPort",
        "KeysightCSV_SHA256", "MATFile", "MATFileSHA256", "ProxyUsed",
        "FallbackFlag", "PlaceholderFlag", "CaptureStatus",
    }
    schema_failures = [
        "missing_columns=" + ",".join(sorted(required_columns - set(header)))
    ] if required_columns - set(header) else []
    checks = [_check("domain_runtime", manifest_rel, "VSG_IQ_manifest_schema", rows, schema_failures)]
    manifest_failures: list[str] = []
    for row_index, row in enumerate(rows, start=1):
        prefix = f"row={row_index}"
        direction = _text(row, "Direction").upper()
        sample_rate = _number(row, "SampleRateHz")
        sample_count = _number(row, "SampleCount")
        port_count = _number(row, "PortCount")
        full_scale = _number(row, "CommonNormalizationFullScale")
        if direction not in {"DL", "UL"}:
            manifest_failures.append(prefix + ":invalid_direction")
            continue
        if not _whole(sample_count, minimum=1) or not _whole(port_count, minimum=1):
            manifest_failures.append(prefix + ":invalid_sample_or_port_count")
            continue
        if sample_rate is None or sample_rate <= 0 or full_scale is None or full_scale <= 0:
            manifest_failures.append(prefix + ":invalid_sample_rate_or_full_scale")
            continue
        if any(_boolean(row, name) is not False for name in ("ProxyUsed", "FallbackFlag", "PlaceholderFlag")):
            manifest_failures.append(prefix + ":proxy_fallback_or_placeholder_capture")
        if _text(row, "CaptureStatus").upper() != "PASS":
            manifest_failures.append(prefix + ":CaptureStatus_not_PASS")
        if not _text(row, "WaveformAuthority").startswith("exact_runtime_"):
            manifest_failures.append(prefix + ":WaveformAuthority_not_exact_runtime")

        canonical = _run_relative_path(run_root, _text(row, "CanonicalCSV"))
        if canonical is None or not _io_path(canonical).is_file():
            manifest_failures.append(prefix + ":canonical_csv_missing_or_unsafe")
            continue
        canonical_rel = canonical.relative_to(run_root).as_posix()
        canonical_header, canonical_rows = _read_rows(canonical)
        expected_header = ["SampleIndex", "Time_s"] + [
            name
            for port_index in range(1, int(port_count) + 1)
            for name in (f"I_Port{port_index}", f"Q_Port{port_index}")
        ]
        canonical_failures: list[str] = []
        if canonical_header != expected_header:
            canonical_failures.append("canonical_schema_mismatch")
        if len(canonical_rows) != int(sample_count):
            canonical_failures.append(
                f"sample_count={len(canonical_rows)};expected={int(sample_count)}"
            )
        if _sha256(canonical).lower() != _text(row, "CanonicalCSV_SHA256").lower():
            canonical_failures.append("canonical_csv_sha256_mismatch")
        power_sum = 0.0
        component_peak = 0.0
        complex_samples: list[list[complex]] = []
        for sample_index, sample in enumerate(canonical_rows):
            observed_index = _number(sample, "SampleIndex")
            observed_time = _number(sample, "Time_s")
            if observed_index != sample_index:
                canonical_failures.append(f"sample={sample_index}:index_not_contiguous")
                break
            if not _close(observed_time, sample_index / sample_rate, atol=1e-14, rtol=1e-11):
                canonical_failures.append(f"sample={sample_index}:time_axis_mismatch")
                break
            ports: list[complex] = []
            for port_index in range(1, int(port_count) + 1):
                i_value = _number(sample, f"I_Port{port_index}")
                q_value = _number(sample, f"Q_Port{port_index}")
                if i_value is None or q_value is None:
                    canonical_failures.append(f"sample={sample_index}:nonfinite_port_{port_index}")
                    break
                value = complex(i_value, q_value)
                ports.append(value)
                power_sum += abs(value) ** 2
                component_peak = max(component_peak, abs(i_value), abs(q_value))
            complex_samples.append(ports)
        if component_peak <= 0:
            canonical_failures.append("waveform_has_no_nonzero_runtime_samples")
        elif not _close(component_peak, full_scale, atol=1e-10, rtol=1e-10):
            canonical_failures.append("common_normalization_full_scale_mismatch")
        sample_denominator = max(1, int(sample_count) * int(port_count))
        normalized_rms = math.sqrt(power_sum / sample_denominator) / full_scale
        if not _close(_number(row, "NormalizedPeak"), 1.0, atol=1e-12):
            canonical_failures.append("normalized_peak_not_unity")
        if not _close(_number(row, "NormalizedRMS"), normalized_rms, atol=1e-12, rtol=1e-10):
            canonical_failures.append("normalized_rms_mismatch")
        checks.append(_check(
            "domain_runtime", canonical_rel, "VSG_IQ_sample_time_power_and_hash",
            canonical_rows, canonical_failures,
        ))

        key_paths = [item for item in _text(row, "KeysightCSVPerPort").split("|") if item]
        key_hashes = [item for item in _text(row, "KeysightCSV_SHA256").split("|") if item]
        if len(key_paths) != int(port_count) or len(key_hashes) != int(port_count):
            manifest_failures.append(prefix + ":Keysight_port_manifest_count_mismatch")
        for port_index, key_relative in enumerate(key_paths, start=1):
            key_path = _run_relative_path(run_root, key_relative)
            key_failures: list[str] = []
            values = _read_headerless_iq(key_path) if key_path is not None else None
            if key_path is None or values is None:
                key_failures.append("headerless_keysight_file_missing_or_invalid")
                values = []
            if len(values) != int(sample_count):
                key_failures.append(f"row_count={len(values)};expected={int(sample_count)}")
            if key_path is not None and port_index <= len(key_hashes) and _io_path(key_path).is_file():
                if _sha256(key_path).lower() != key_hashes[port_index - 1].lower():
                    key_failures.append("keysight_csv_sha256_mismatch")
            if port_index <= int(port_count):
                for sample_index, (i_value, q_value) in enumerate(values):
                    if sample_index >= len(complex_samples) or port_index > len(complex_samples[sample_index]):
                        break
                    expected = complex_samples[sample_index][port_index - 1] / full_scale
                    if not math.isclose(i_value, expected.real, abs_tol=1e-12, rel_tol=1e-10) or not math.isclose(q_value, expected.imag, abs_tol=1e-12, rel_tol=1e-10):
                        key_failures.append(f"sample={sample_index}:normalized_IQ_mismatch")
                        break
            checks.append(_check(
                "domain_runtime", key_relative,
                "Keysight_headerless_normalized_IQ_matches_canonical",
                [{"I": str(value[0]), "Q": str(value[1])} for value in values],
                key_failures,
            ))

        mat_path = _run_relative_path(run_root, _text(row, "MATFile"))
        if mat_path is None or not _io_path(mat_path).is_file():
            manifest_failures.append(prefix + ":MAT_file_missing_or_unsafe")
        elif _sha256(mat_path).lower() != _text(row, "MATFileSHA256").lower():
            manifest_failures.append(prefix + ":MAT_file_sha256_mismatch")
    checks.append(_check(
        "domain_runtime", manifest_rel, "VSG_IQ_manifest_files_and_authority",
        rows, manifest_failures,
    ))
    return checks


def _load_resolved_config(run_root: Path) -> dict[str, Any]:
    for relative in (
        "meta/scenario_config_resolved.json",
        "meta/config_resolved.json",
        "config/scenario_config_resolved.json",
    ):
        path = _io_path(run_root / relative)
        if not path.is_file():
            continue
        try:
            decoded = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            continue
        if isinstance(decoded, dict):
            return decoded
    return {}


def _nested_value(source: dict[str, Any], path: str, default: Any = None) -> Any:
    value: Any = source
    for part in path.split("."):
        if not isinstance(value, dict) or part not in value:
            return default
        value = value[part]
    return value


def _truthy_config(source: dict[str, Any], *paths: str) -> bool:
    for path in paths:
        value = _nested_value(source, path, None)
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            return bool(value)
        if isinstance(value, str):
            token = value.strip().lower()
            if token in {"true", "1", "yes", "on", "enabled"}:
                return True
            if token in {"false", "0", "no", "off", "disabled"}:
                return False
    return False


def _empty_domain_table_is_valid_zero_event(relative: str, run_root: Path) -> bool:
    """Return true only for an explicitly event-driven zero-row table.

    Failure/issue registries are zero-event tables only when their canonical
    evaluator receipt proves that all runtime sources were evaluated and
    found zero issues.  A separate terminal gate (for example a visual gate)
    can fail without manufacturing a PHY issue row, so the global truth
    failure count is not the authority for this domain table.
    """

    if relative in {
        "beamforming/csv/mimo_negative_trials.csv",
        "channel/csv/trajectory_constraint_conflicts.csv",
        "mobility/csv/trajectory_constraint_conflicts.csv",
        "reports/csv/dl_pdsch_objective_failures.csv",
        "reports/csv/live_cell_reselection_events.csv",
        "reports/csv/raster_replacement_inventory.csv",
        "reports/csv/unavailable_plot_card_registry.csv",
    }:
        return True
    if relative == "reports/csv/truth_contract_failures.csv":
        return _evaluated_empty_truth_contract_failures_is_valid(run_root)
    if relative in {
        "reports/csv/active_issue_gate_summary.csv",
        "reports/csv/result_issue_registry.csv",
    }:
        return _evaluated_empty_issue_registry_is_valid(relative, run_root)
    return False


def _evaluated_empty_truth_contract_failures_is_valid(run_root: Path) -> bool:
    """Accept an empty failure ledger only when the PHY-truth authorities pass.

    A header-only failure table is positive zero-event evidence only when the
    independently persisted scenario status and truth-contract summary agree
    on the same run identity and explicitly report zero *truth* failures.  The
    enclosing run may still fail a later, independent terminal publication or
    browser-materialization gate; that must not manufacture a PHY-truth
    failure row or make the already evaluated zero-event ledger invalid.
    Merely naming a table ``truth_contract_failures`` never makes it valid.
    """

    _summary_header, summary_rows = _read_rows(
        run_root / "reports/csv/scenario_summary.csv"
    )
    _truth_header, truth_rows = _read_rows(
        run_root / "reports/csv/truth_contract_summary.csv"
    )
    if len(summary_rows) != 1 or len(truth_rows) != 1:
        return False
    summary = summary_rows[0]
    truth = truth_rows[0]
    if _boolean(summary, "RuntimeTruthContractOk") is not True:
        return False
    if _boolean(summary, "TruthContractOk") is not True:
        return False
    if _boolean(truth, "RuntimeTruthContractOk") is not True:
        return False
    zero_fields = (
        "StrictTruthFailureCount",
        "StrictProxyGuardFailureCount",
        "CanonicalArtifactGapCount",
        "RoundtripMismatchCount",
        "RequiredRuntimeEvidenceMissingCount",
    )
    for field in zero_fields:
        if _number(truth, field) != 0:
            return False
    for field in ("ScenarioID", "ConfigHash"):
        summary_value = _text(summary, field).strip().lower()
        truth_value = _text(truth, field).strip().lower()
        if not summary_value or summary_value != truth_value:
            return False
    return True


def _evaluated_empty_issue_registry_is_valid(relative: str, run_root: Path) -> bool:
    """Validate the fail-closed receipt for a genuinely empty issue registry."""

    _header, receipts = _read_rows(
        run_root / "reports/csv/result_issue_registry_evaluation.csv"
    )
    if len(receipts) != 1:
        return False
    receipt = receipts[0]
    if _text(receipt, "EvaluationStatus").upper() != "EVALUATED":
        return False
    if _text(receipt, "SchemaVersion") != "result_issue_registry_evaluation_v1":
        return False
    if _text(receipt, "Evaluator") != (
        "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildResultIssueRegistry"
    ):
        return False
    if _number(receipt, "IssueRowCount") != 0:
        return False
    source_count = _number(receipt, "SourceTableCount")
    runtime_row_count = _number(receipt, "RuntimeSourceRowCount")
    if source_count is None or source_count < 1:
        return False
    if runtime_row_count is None or runtime_row_count < 1:
        return False
    run_id = _text(receipt, "RunId")
    config_hash = _text(receipt, "ConfigHash").lower()
    if not run_id or len(config_hash) != 64 or any(
        character not in "0123456789abcdef" for character in config_hash
    ):
        return False
    if relative == "reports/csv/result_issue_registry.csv":
        return True

    summary_path = _io_path(
        run_root / "reports/json/active_issue_gate_summary.json"
    )
    if not summary_path.is_file():
        return False
    try:
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return False
    if not isinstance(summary, dict):
        return False
    if str(summary.get("RunId", "")).strip() != run_id:
        return False
    if summary.get("ActiveIssueGateOk") is not True:
        return False
    if str(summary.get("IssueRegistryStatus", "")).strip().upper() != "PASS":
        return False
    if summary.get("IssueRegistryEvaluationValid") is not True:
        return False
    numeric_zero_fields = (
        "IssueRegistryRowCount",
        "ActiveCriticalIssueCount",
        "ActiveHighIssueCount",
        "ActiveMediumIssueCount",
        "ActiveMandatoryIssueCount",
    )
    for field in numeric_zero_fields:
        try:
            if float(summary.get(field, math.nan)) != 0:
                return False
        except (TypeError, ValueError):
            return False
    audit = summary.get("IssueRegistryEvaluationAudit", {})
    if not isinstance(audit, dict):
        return False
    if str(audit.get("ObservedRunId", "")).strip() != run_id:
        return False
    if str(audit.get("ObservedConfigHash", "")).strip().lower() != config_hash:
        return False
    if str(audit.get("EvaluationStatus", "")).strip().upper() != "EVALUATED":
        return False
    try:
        if float(audit.get("ObservedIssueRowCount", math.nan)) != 0:
            return False
    except (TypeError, ValueError):
        return False
    return True


def primary_link_tables(run_root: Path) -> dict[str, str]:
    """Resolve primary PHY table names from the persisted run authority."""

    resolved = _load_resolved_config(run_root)
    fixed_only = _truthy_config(
        resolved,
        "sweeps_and_matrix.fixed_link_calibration.only",
        "canonical_control.run.fixed_link_campaign_only",
    )
    return dict(FIXED_LINK_PRIMARY_TABLES if fixed_only else PRIMARY_LINK_TABLES)


def _domain_table_applicability(
    relative: str,
    run_root: Path,
    scenario_summary: dict[str, str],
    resolved_config: dict[str, Any],
) -> tuple[bool, bool]:
    """Return exact run-policy applicability for optional live surfaces.

    A header-only file is not evidence, but it is also not a failure when
    the owning feature is explicitly disabled. Unknown tables remain
    required and fail closed.
    """

    if relative == "reports/csv/geometry_plot_lineage.csv":
        # This is a lineage ledger for producer-owned geometry rasters, not
        # an unconditional runtime measurement table.  A fixed-link run can
        # legitimately produce no geometry rasters; in that case its typed
        # zero-row ledger is explicit non-applicability.  If any governed
        # raster exists, rows are mandatory and the generic schema/runtime
        # audit below remains fail-closed.
        governed_images = (
            "geometry/image/topology_map.png",
            "geometry/image/ue_trajectory_xy.png",
            "geometry/image/distance_vs_slot.png",
            "mobility/image/doppler_vs_slot.png",
            "mobility/image/pathloss_vs_slot.png",
            "reports/image/measured_sinr_vs_slot.png",
            "reports/image/mcs_rank_vs_slot.png",
            "reports/image/geometry_scenario_dashboard.png",
        )
        enabled = any(_io_path(run_root / item).is_file() for item in governed_images)
        return enabled, enabled

    runner_profile = _text(scenario_summary, "RunnerProfile").strip().lower()
    if runner_profile in COMPONENT_ONLY_RUNNER_PROFILES:
        _header, observed_rows = _read_rows(run_root / relative)
        component_prefixes: tuple[str, ...] = ()
        if runner_profile in {"prach_detection", "prach_strict_validation"}:
            component_prefixes = (
                "air_interface/csv/prach_",
                "control/csv/prach_",
                "reports/csv/prach_",
                "reports/csv/initial_access_random_access_outputs.csv",
            )
        elif runner_profile in {
            "pdcch_blind_decode_sweep", "pdcch_strict_validation",
            "ctrl6gr_pdcch_study",
        }:
            component_prefixes = (
                "air_interface/csv/pdcch_",
                "control/csv/pdcch_",
                "reports/csv/pdcch_",
            )
        elif runner_profile == "srs_strict_validation":
            component_prefixes = (
                "air_interface/csv/srs_", "control/csv/srs_",
                "reports/csv/srs_",
            )
        elif runner_profile == "trs_strict_validation":
            component_prefixes = (
                "air_interface/csv/trs_", "control/csv/trs_",
                "reports/csv/trs_",
            )
        # A component runner may still emit a populated shared runtime table;
        # populated evidence is audited normally. Header-only tables owned by
        # another PHY component are explicit non-applicability, not missing
        # waveform evidence for this run profile.
        full_link_only_tables = {
            DUT_REFERENCE_DETAIL,
            DUT_REFERENCE_SUMMARY,
            "reports/csv/mcs_table_reference.csv",
            "reports/csv/cqi_table_reference.csv",
            "reports/csv/configured_effective_operating_point.csv",
            "reports/csv/lls_link_performance_summary.csv",
            "reports/csv/measured_sinr_timeseries.csv",
            # Standalone PDCCH waveform/blind-decode campaigns have no
            # scheduled PDSCH/PUSCH grant to bind. Their PDCCH trial tables
            # are the component evidence; an empty data-grant binding ledger
            # is explicit non-applicability. Full link runners remain subject
            # to the stronger populated data-link binding checks above.
            "reports/csv/pdcch_grant_binding_evidence.csv",
        }
        if relative in full_link_only_tables:
            return False, False
        if not observed_rows and not any(
            relative.startswith(prefix) for prefix in component_prefixes
        ):
            return False, False

    if relative == "mobility/csv/inter_ue_distance_validation.csv":
        num_ues = _nested_value(
            resolved_config,
            "canonical_control.topology.num_ues",
            _nested_value(
                resolved_config,
                "deployment_topology.num_ues",
                _nested_value(resolved_config, "scenario.ue.nUE", math.nan),
            ),
        )
        try:
            if int(num_ues) < 2:
                return False, False
        except (TypeError, ValueError, OverflowError):
            pass
    if relative in {
        "reports/csv/channel_rf_cdlc_realization_table.csv",
        "component_anchors/channel_rf/reports/csv/channel_rf_cdlc_realization_table.csv",
    }:
        profile = str(
            _nested_value(
                resolved_config,
                "channels.profile",
                _nested_value(
                    resolved_config,
                    "channel_model.scenario_label",
                    _nested_value(
                        resolved_config,
                        "channel_model.delay_profile",
                        "",
                    ),
                ),
            )
        ).strip().upper().replace("_", "-")
        # This artifact is intentionally the exact CDL-C 24-path table.  A
        # header-only result is correct for every other concrete channel
        # profile; those profiles are represented by the generic runtime
        # channel-realization and impulse-response tables instead.
        enabled = profile == "CDL-C"
        return enabled, enabled
    if relative in {
        "control/csv/access_state_timeline.csv",
        "control/csv/access_transition_ledger.csv",
        "reports/csv/access_state_timeline.csv",
        "reports/csv/access_transition_ledger.csv",
    }:
        enabled = _truthy_config(
            resolved_config,
            "initial_access.enabled",
            "random_access.enabled",
            "control_gating.pbch_required",
            "control_gating.prach_required",
        )
        return enabled, enabled
    if relative == "control/csv/pbch_trials.csv":
        enabled = _truthy_config(
            resolved_config,
            "initial_access.enabled",
            "control_gating.pbch_required",
        )
        return enabled, enabled
    if relative == "control/csv/prach_trials.csv":
        enabled = _truthy_config(
            resolved_config,
            "random_access.enabled",
            "control_gating.prach_required",
        )
        return enabled, enabled
    if relative == "control/csv/ra_collision_trials.csv":
        enabled = _truthy_config(
            resolved_config,
            "validation.random_access_evidence.preamble_collision_test_enabled",
            "random_access_evidence.preamble_collision_test_enabled",
            "random_access.enable_collision_mode",
        )
        return enabled, enabled
    if relative == "control/csv/ra_negative_trials.csv":
        enabled = _truthy_config(
            resolved_config,
            "validation.random_access_evidence.four_step_negative_test_enabled",
            "random_access_evidence.four_step_negative_test_enabled",
            "random_access.run_negative_suite",
        )
        return enabled, enabled
    if relative == "control/csv/csi_rs_trials.csv":
        enabled = _truthy_config(
            resolved_config,
            "reference_signals.csi_rs_enabled",
            "reference_signals.nzp_csi_rs.enabled",
        )
        return enabled, enabled
    if relative == "control/csv/srs_trials.csv":
        enabled = _truthy_config(
            resolved_config,
            "reference_signals.srs_enabled",
            "reference_signals.srs.enabled",
            "control_gating.srs_required",
        )
        return enabled, enabled
    if relative == "control/csv/trs_trials.csv":
        enabled = _truthy_config(
            resolved_config,
            "reference_signals.trs_enabled",
            "reference_signals.trs.enabled",
            "control_gating.trs_required",
        )
        return enabled, enabled
    if relative == "reports/csv/live_receiver_tracking_trace.csv":
        enabled = _truthy_config(
            resolved_config,
            "reference_signals.srs_enabled",
            "reference_signals.srs.enabled",
            "reference_signals.trs_enabled",
            "reference_signals.trs.enabled",
            "control_gating.srs_required",
            "control_gating.trs_required",
        )
        return enabled, enabled

    if relative == "reports/csv/live_beam_p1_acquisition_stats.csv":
        enabled = _truthy_config(
            resolved_config,
            "mimo_and_beam_management.beam_sweeping",
            "system.beam.enable",
            "reference_signals.ssb_enabled",
        )
        return enabled, enabled
    if relative == "reports/csv/beam_management_outputs.csv":
        enabled = _truthy_config(
            resolved_config,
            "mimo_and_beam_management.beam_sweeping",
            "mimo_and_beam_management.beam_refinement",
            "mimo_and_beam_management.beam_switching",
            "mimo_and_beam_management.beam_tracking",
            "system.beam.enable",
        )
        return enabled, enabled
    if relative == "reports/csv/live_csirs_stats.csv":
        enabled = _truthy_config(
            resolved_config,
            "reference_signals.csi_rs_enabled",
            "reference_signals.nzp_csi_rs.enabled",
        )
        return enabled, enabled
    if relative == "reports/csv/live_coverage_layer.csv":
        run_class = str(
            _nested_value(
                resolved_config,
                "validation.run_class",
                _text(scenario_summary, "RunClass"),
            )
        ).strip().lower()
        enabled = _truthy_config(
            resolved_config,
            "canonical_control.launch.geometry_enabled",
        ) or run_class in {
            "geometry_based_lls",
            "geometry_based_link_level",
            "geometry_mobility_lls",
        }
        return enabled, enabled
    if relative in {
        "geometry/csv/serving_cell_assignment.csv",
        "geometry/csv/trajectory_geometry.csv",
        "geometry/csv/ue_initial_positions.csv",
        "mobility/csv/channel_continuity_reconciliation.csv",
        "mobility/csv/doppler_reconciliation.csv",
        "mobility/csv/inter_ue_distance_validation.csv",
        "mobility/csv/pathloss_reconciliation.csv",
        "mobility/csv/propagation_delay_reconciliation.csv",
        "mobility/csv/trajectory_segment_table.csv",
    }:
        run_class = str(
            _nested_value(
                resolved_config,
                "validation.run_class",
                _text(scenario_summary, "RunClass"),
            )
        ).strip().lower()
        enabled = _truthy_config(
            resolved_config,
            "canonical_control.launch.geometry_enabled",
        ) or run_class in {
            "geometry_based_lls",
            "geometry_based_link_level",
            "geometry_mobility_lls",
        }
        return enabled, enabled
    if relative == "reports/csv/equalized_constellations.csv":
        enabled = _truthy_config(
            resolved_config,
            "run_control.save_constellations",
            "output_control.save_constellations",
        )
        return enabled, enabled
    if relative == "reports/csv/channel_impulse_response.csv":
        model = str(
            _nested_value(
                resolved_config,
                "channel_model.model_family",
                _nested_value(resolved_config, "channels.model_type", ""),
            )
        ).strip().upper()
        enabled = model not in {"", "AWGN", "UNIT", "IDENTITY"}
        return enabled, enabled
    if relative == "reports/csv/pdcch_grant_binding_evidence.csv":
        enabled = _truthy_config(
            resolved_config,
            "control_gating.pdcch_required",
            "pdcch.enabled",
            "canonical_control.control.pdcch_required",
        )
        return enabled, enabled
    if relative in {
        "reports/csv/prach_correlation_trace.csv",
        "reports/csv/prach_correlation_traces.csv",
    }:
        enabled = _truthy_config(
            resolved_config,
            "control_gating.prach_required",
            "prach.enabled",
            "prach.enable",
            "canonical_control.control.prach_required",
        )
        return enabled, enabled
    if relative == "reports/csv/antenna_config_resolved.csv":
        has_runtime_antenna_rows = bool(
            _read_rows(run_root / "reports/csv/antenna_runtime_evidence.csv")[1]
        )
        has_link_rows = any(
            bool(_read_rows(run_root / path)[1])
            for path in primary_link_tables(run_root).values()
        )
        enabled = has_runtime_antenna_rows or has_link_rows
        return enabled, enabled
    if relative == "reports/csv/live_user_performance_snapshot.csv":
        has_link_rows = any(
            bool(_read_rows(run_root / path)[1])
            for path in primary_link_tables(run_root).values()
        )
        return has_link_rows, has_link_rows
    return True, True


def _executed_symbol_occupancy_failures(run_root: Path, points: list[dict[str, str]]) -> list[str]:
    """Independently close occupancy against exact TX REs, not slot capacity."""
    source = "reports/csv/live_re_allocation_snapshot.csv"
    if any(_text(point, "source_table_logical_path") != source for point in points):
        return ["occupancy_uses_nonexecuted_source"]
    _, records = _read_rows(run_root / source)
    if not records:
        return ["executed_tx_re_source_missing"]
    expected: dict[tuple, set[int]] = {}
    for row in records:
        if _text(row, "evidence_scope") != "runtime_observed_tx_occupancy":
            return ["occupancy_source_contains_nonexecuted_evidence"]
        active = _text(row, "active_flag").lower()
        values = [_number(row, field) for field in ("absolute_slot", "symbol_index", "subcarrier_count")]
        if active not in {"true", "false", "0", "1"} or any(
            value is None or value < 0 or value != int(value) for value in values
        ):
            return ["occupancy_source_invalid_coordinates_or_activity"]
        slot, symbol, width = (int(value) for value in values)
        if active in {"false", "0"} or width == 0:
            continue
        key = (_text(row, "cell_id"), _text(row, "component_carrier", "component_carrier_id"),
               _text(row, "bwp_id"), _text(row, "direction").upper(), slot)
        expected.setdefault(key, set()).add(symbol)
    failures = []
    seen = set()
    for ordinal, point in enumerate(points, 1):
        slot = _number(point, "x_value")
        key = (_text(point, "cell_id"), _text(point, "component_carrier"),
               _text(point, "bwp_id"), _text(point, "direction").upper(), slot)
        if key in seen:
            failures.append(f"occupancy_point={ordinal}:duplicate_scope")
        seen.add(key)
        if key not in expected:
            failures.append(f"occupancy_point={ordinal}:unobserved_scope")
            continue
        if _number(point, "y_value") != len(expected[key]):
            failures.append(f"occupancy_point={ordinal}:distinct_symbol_count_mismatch")
        if _text(point, "symbol_indices_0based") != "|".join(map(str, sorted(expected[key]))):
            failures.append(f"occupancy_point={ordinal}:symbol_set_mismatch")
        if "0-based" not in _text(point, "x_label"):
            failures.append(f"occupancy_point={ordinal}:slot_index_domain_missing")
    if seen != set(expected):
        failures.append("occupancy_executed_scope_coverage_mismatch")
    return failures


def _audit_chart_lineage(run_root: Path) -> list[AuditCheck]:
    lineage_rel = "reports/csv/contract_plot_lineage.csv"
    lineage_path = run_root / lineage_rel
    header, rows = _read_rows(lineage_path)
    if not rows:
        return [_check("chart_lineage", lineage_rel, "lineage_present", rows, ["missing_or_empty"])]
    failures: list[str] = []
    chart_checks: list[AuditCheck] = []
    for index, row in enumerate(rows, start=1):
        plot_id = _text(row, "PlotId") or f"row_{index}"
        image_rel = _text(row, "ImagePath")
        source_rel = _text(row, "SourceCSV")
        status = _text(row, "Status").lower()
        item_failures: list[str] = []
        if status != "pass":
            item_failures.append(f"status={status or 'missing'}")
        image_path = run_root / image_rel
        source_path = run_root / source_rel
        if not _io_path(image_path).is_file():
            item_failures.append("image_missing")
        elif _sha256(image_path).lower() != _text(row, "ImageSHA256").lower():
            item_failures.append("image_hash_mismatch")
        if _io_path(image_path).is_file():
            visual_semantics = _png_semantics(image_path)
            if not visual_semantics:
                item_failures.append("rendered_visual_semantics_metadata_missing")
            if "visual_gate=" in visual_semantics.lower() or "unavailable without faking" in visual_semantics.lower():
                item_failures.append("low_information_reason_card_counted_as_chart")
        if not _io_path(source_path).is_file():
            item_failures.append("source_csv_missing")
            source_header: list[str] = []
            source_rows: list[dict[str, str]] = []
        else:
            if _sha256(source_path).lower() != _text(row, "SourceCSV_SHA256").lower():
                item_failures.append("source_hash_mismatch")
            source_header, source_rows = _read_rows(source_path)
            normalized_chart_schema = {
                "chart_mode", "x_label", "y_label", "point_index",
                "x_value", "y_value", "source_mapping_status",
            }.issubset(source_header)
            if normalized_chart_schema:
                point_rows = [r for r in source_rows if (_number(r, "point_index") or 0) > 0]
                if not point_rows:
                    item_failures.append("no_numeric_chart_points")
                for point_index, point in enumerate(point_rows, start=1):
                    if _number(point, "x_value") is None or _number(point, "y_value") is None:
                        item_failures.append(f"point={point_index}:nonfinite_xy")
                    mapping = _text(point, "source_mapping_status").lower()
                    if mapping != "exact":
                        item_failures.append(f"point={point_index}:mapping={mapping or 'missing'}")
                    x_label = _text(point, "x_label").lower()
                    y_label = _text(point, "y_label").lower()
                    if x_label in GENERIC_AXIS_LABELS or y_label in GENERIC_AXIS_LABELS:
                        item_failures.append(f"point={point_index}:generic_or_missing_axis_label")
                if point_rows:
                    modes = {_text(point, "chart_mode").lower() for point in point_rows}
                    if modes.intersection({"line", "scatter", "relation", "vs", "cdf"}):
                        unique_x = {_number(point, "x_value") for point in point_rows}
                        unique_x.discard(None)
                        shape_policies = {
                            _text(point, "evidence_shape_policy").lower()
                            for point in point_rows
                        }
                        sample_counts = [
                            _number(point, "source_sample_count")
                            for point in point_rows
                        ]
                        explicit_scalar_observation = (
                            shape_policies.issubset({"operating_point", "measured_scalar"})
                            and bool(shape_policies)
                            and "" not in shape_policies
                            and all(
                                count is not None and count >= 1
                                for count in sample_counts
                            )
                        )
                        if len(unique_x) < 2 and not explicit_scalar_observation:
                            item_failures.append("insufficient_independent_x_values")
            else:
                # Specialized chart datasets deliberately use domain columns
                # (for example slot/cell/occupancy or aggregation/count).
                # Require real rows, finite numeric evidence and exact mapping;
                # do not force them into the generic x_value/y_value schema.
                if not source_rows:
                    item_failures.append("specialized_chart_source_empty")
                finite_values = 0
                for source_row in source_rows:
                    for column, raw_value in source_row.items():
                        if column.lower() in {"run_id", "point_index"}:
                            continue
                        try:
                            value = float(str(raw_value).strip())
                        except (TypeError, ValueError):
                            continue
                        finite_values += int(math.isfinite(value))
                if finite_values == 0:
                    item_failures.append("specialized_chart_has_no_finite_runtime_values")
                if "source_mapping_status" not in source_header:
                    item_failures.append("source_mapping_status_column_missing")
                elif any(_text(source_row, "source_mapping_status").lower() != "exact" for source_row in source_rows):
                    item_failures.append("specialized_chart_mapping_not_exact")
        if any(_text(point, "chart_name").lower() == "frame/slot/symbol occupancy timeline" for point in source_rows):
            item_failures.extend(_executed_symbol_occupancy_failures(run_root, source_rows))
        chart_checks.append(
            _check(
                "chart_lineage",
                source_rel or lineage_rel,
                plot_id,
                source_rows if "source_rows" in locals() else [],
                item_failures,
            )
        )
        failures.extend(f"{plot_id}:{reason}" for reason in item_failures)
    chart_checks.insert(0, _check("chart_lineage", lineage_rel, "all_lineaged_charts_exact", rows, failures))
    return chart_checks


def _audit_reconciliation(
    summary_path: str,
    summary: dict[str, str],
    link_rows: dict[str, list[dict[str, str]]],
    *,
    primary_links_required: bool = True,
) -> list[AuditCheck]:
    checks: list[AuditCheck] = []
    for direction, rows in link_rows.items():
        expected = _expected_link_count(summary, direction)
        measured_rows = _measured_analysis_rows(rows)
        checks.append(
            _check(
                "cross_table_reconciliation",
                summary_path,
                f"{direction.lower()}_summary_trial_count",
                measured_rows,
                [] if expected == len(measured_rows) else [
                    f"summary={expected};effective_table={len(measured_rows)};total_table={len(rows)}"
                ],
                required=primary_links_required or bool(rows),
                evaluated=primary_links_required or bool(rows),
            )
        )
    config_hashes = {
        _text(row, "ConfigHash")
        for rows in link_rows.values()
        for row in rows
        if _text(row, "ConfigHash")
    }
    summary_hash = _text(summary, "ConfigHash")
    checks.append(
        _check(
            "cross_table_reconciliation",
            summary_path,
            "summary_config_hash_matches_trials",
            [summary] if summary else [],
            [] if summary_hash and config_hashes == {summary_hash} else [f"summary={summary_hash};trials={sorted(config_hashes)}"],
            required=primary_links_required or bool(config_hashes),
            evaluated=primary_links_required or bool(config_hashes),
        )
    )
    return checks


def _audit_runtime_call_ledger(
    run_root: Path,
    summary: dict[str, str],
    link_rows: dict[str, list[dict[str, str]]],
) -> list[AuditCheck]:
    """Require exact Tx/Rx invocation evidence for populated PHY trial tables.

    Trial rows prove what a receiver reported; they cannot reconstruct which
    production entry points were actually invoked.  The call ledger is
    consequently a separate, identity-bound primary artifact.  In particular,
    an empty ledger after resumed finalization must fail rather than being
    inferred from the trials or replaced with synthetic rows.
    """

    required = any(link_rows.get(direction, []) for direction in ("DL", "UL"))
    header, rows = _read_rows(run_root / RUNTIME_CALL_LEDGER)
    if not required:
        return [
            _check(
                "runtime_execution_lineage",
                RUNTIME_CALL_LEDGER,
                "runtime_call_ledger_required_for_populated_phy_trials",
                rows,
                [],
                required=False,
                evaluated=False,
            )
        ]

    checks: list[AuditCheck] = []
    checks.append(
        _check(
            "runtime_execution_lineage",
            RUNTIME_CALL_LEDGER,
            "runtime_call_ledger_present_nonempty",
            rows,
            [] if header and rows else ["missing_or_header_only_runtime_call_ledger"],
        )
    )
    missing_columns = [name for name in RUNTIME_LEDGER_REQUIRED_COLUMNS if name not in header]
    checks.append(
        _check(
            "runtime_execution_lineage",
            RUNTIME_CALL_LEDGER,
            "runtime_call_ledger_exact_schema",
            rows,
            [] if not missing_columns else ["missing_columns=" + ",".join(missing_columns)],
        )
    )
    if not rows or missing_columns:
        return checks

    sequence_failures: list[str] = []
    sequences: list[int] = []
    for index, row in enumerate(rows, start=1):
        value = _number(row, "Sequence")
        if value is None or value < 1 or value != math.floor(value):
            sequence_failures.append(f"row={index}:invalid_sequence={_text(row, 'Sequence')}")
        else:
            sequences.append(int(value))
    if len(sequences) != len(set(sequences)):
        sequence_failures.append("duplicate_sequence")
    if sequences != sorted(sequences):
        sequence_failures.append("non_monotonic_sequence")
    checks.append(
        _check(
            "runtime_execution_lineage",
            RUNTIME_CALL_LEDGER,
            "runtime_call_sequence_positive_unique_monotonic",
            rows,
            sequence_failures,
        )
    )

    identity_failures: list[str] = []
    for field in ("RunId", "ExecutionID"):
        values = {_text(row, field) for row in rows if _text(row, field)}
        if len(values) != 1 or any(not _text(row, field) for row in rows):
            identity_failures.append(f"{field}_not_single_nonblank={sorted(values)}")
    summary_hash = _text(summary, "ConfigHash")
    ledger_hashes = {_text(row, "ConfigHash") for row in rows if _text(row, "ConfigHash")}
    if not summary_hash or ledger_hashes != {summary_hash} or any(
        not _text(row, "ConfigHash") for row in rows
    ):
        identity_failures.append(
            f"ConfigHash_mismatch:summary={summary_hash};ledger={sorted(ledger_hashes)}"
        )
    for summary_field, ledger_field in (("RunID", "RunId"), ("RunId", "RunId"), ("ExecutionID", "ExecutionID")):
        expected = _text(summary, summary_field)
        if expected and any(_text(row, ledger_field) != expected for row in rows):
            identity_failures.append(f"{ledger_field}_mismatch_summary_{summary_field}")
    checks.append(
        _check(
            "runtime_execution_lineage",
            RUNTIME_CALL_LEDGER,
            "runtime_call_identity_matches_run",
            rows,
            identity_failures,
        )
    )

    truth_failures: list[str] = []
    for index, row in enumerate(rows, start=1):
        if _text(row, "Event").upper() != "ENTER":
            truth_failures.append(f"row={index}:Event={_text(row, 'Event')}")
        if _text(row, "EvidenceClass").upper() != "ACTUAL_RUNTIME_ENTRY":
            truth_failures.append(f"row={index}:EvidenceClass={_text(row, 'EvidenceClass')}")
        if _text(row, "ApproximationMode").lower() != "none":
            truth_failures.append(f"row={index}:ApproximationMode={_text(row, 'ApproximationMode')}")
        function_name = _text(row, "FunctionName")
        if not function_name:
            truth_failures.append(f"row={index}:FunctionName_blank")
        context_hash = _text(row, "ContextSHA256").lower()
        if len(context_hash) != 64 or any(character not in "0123456789abcdef" for character in context_hash):
            truth_failures.append(f"row={index}:ContextSHA256_invalid")
    checks.append(
        _check(
            "runtime_execution_lineage",
            RUNTIME_CALL_LEDGER,
            "runtime_call_rows_are_actual_nonproxy_entries",
            rows,
            truth_failures,
        )
    )

    observed_functions = {_text(row, "FunctionName").lower() for row in rows}
    for direction, required_functions in (
        ("DL", ("sixgr.phy.dl.pdsch_tx", "sixgr.phy.dl.pdsch_rx")),
        ("UL", ("sixgr.phy.ul.pusch_tx", "sixgr.phy.ul.pusch_rx")),
    ):
        if not link_rows.get(direction, []):
            continue
        missing_functions = [name for name in required_functions if name not in observed_functions]
        checks.append(
            _check(
                "runtime_execution_lineage",
                RUNTIME_CALL_LEDGER,
                f"{direction.lower()}_canonical_tx_rx_entry_points_observed",
                rows,
                [] if not missing_functions else ["missing_functions=" + ",".join(missing_functions)],
            )
        )
    return checks


def _audit_measurement_sidecar_manifest(run_root: Path) -> list[AuditCheck]:
    relative = MEASUREMENT_SIDECAR_MANIFEST
    header, rows = _read_rows(run_root / relative)
    required_columns = {
        "SourceArtifact", "MeasurementArtifact", "ProvenanceArtifact",
        "SourceRows", "MeasurementRows", "ProvenanceRows",
        "MeasurementColumnCount", "ProvenanceColumnCount", "SplitKind",
    }
    failures: list[str] = []
    missing = sorted(required_columns - set(header))
    if missing:
        failures.append("missing_columns=" + ",".join(missing))
    if not rows:
        failures.append("sidecar_manifest_rows_missing")
    for field in ("SourceArtifact", "MeasurementArtifact", "ProvenanceArtifact"):
        values = [_text(row, field).replace("\\", "/") for row in rows]
        if any(not value for value in values):
            failures.append(field + "_blank")
        if len(values) != len(set(values)):
            failures.append(field + "_duplicate")

    checks: list[AuditCheck] = []
    for index, row in enumerate(rows, start=1):
        prefix = f"row={index}"
        source_rel = _text(row, "SourceArtifact").replace("\\", "/")
        measurement_rel = _text(row, "MeasurementArtifact").replace("\\", "/")
        provenance_rel = _text(row, "ProvenanceArtifact").replace("\\", "/")
        per_file_failures: list[str] = []
        loaded: dict[str, tuple[list[str], list[dict[str, str]]]] = {}
        for label, artifact in (
            ("source", source_rel),
            ("measurement", measurement_rel),
            ("provenance", provenance_rel),
        ):
            if not artifact or not _io_path(run_root / artifact).is_file():
                per_file_failures.append(f"{label}_artifact_missing={artifact or 'blank'}")
                loaded[label] = ([], [])
            else:
                loaded[label] = _read_rows(run_root / artifact)
        declared_specs = (
            ("SourceRows", "source", None),
            ("MeasurementRows", "measurement", "MeasurementColumnCount"),
            ("ProvenanceRows", "provenance", "ProvenanceColumnCount"),
        )
        for row_field, label, column_field in declared_specs:
            declared_rows = _number(row, row_field)
            observed_header, observed_rows = loaded[label]
            if not _whole(declared_rows) or int(declared_rows) != len(observed_rows):
                per_file_failures.append(
                    f"{row_field}_mismatch={declared_rows}!={len(observed_rows)}"
                )
            if column_field:
                declared_columns = _number(row, column_field)
                if not _whole(declared_columns) or int(declared_columns) != len(observed_header):
                    per_file_failures.append(
                        f"{column_field}_mismatch={declared_columns}!={len(observed_header)}"
                    )
        source_rows = loaded["source"][1]
        measurement_rows = loaded["measurement"][1]
        provenance_rows = loaded["provenance"][1]
        if len(provenance_rows) != len(source_rows):
            per_file_failures.append("provenance_not_one_row_per_source_row")
        if len(measurement_rows) > len(source_rows):
            per_file_failures.append("measurement_rows_exceed_source_rows")
        for label, split_rows in (("measurement", measurement_rows), ("provenance", provenance_rows)):
            if split_rows and "SourceArtifact" in loaded[label][0]:
                mismatches = sum(
                    _text(item, "SourceArtifact").replace("\\", "/") != source_rel
                    for item in split_rows
                )
                if mismatches:
                    per_file_failures.append(
                        f"{label}_SourceArtifact_mismatch_count={mismatches}"
                    )
            for flag in ("FallbackFlag", "PlaceholderFlag"):
                if flag in loaded[label][0] and any(
                    _boolean(item, flag) is True for item in split_rows
                ):
                    per_file_failures.append(f"{label}_{flag}_true")
        failures.extend(prefix + ":" + reason for reason in per_file_failures)
        for artifact, label in (
            (measurement_rel, "measurement_split_matches_manifest"),
            (provenance_rel, "provenance_split_matches_manifest"),
        ):
            if artifact:
                checks.append(
                    _check(
                        "manifest_integrity", artifact, label,
                        loaded["measurement" if artifact == measurement_rel else "provenance"][1],
                        per_file_failures,
                    )
                )
    checks.insert(
        0,
        _check(
            "manifest_integrity", relative, "measurement_sidecars_match_sources",
            rows, failures,
        ),
    )
    return checks


def _audit_canonical_component_manifest(run_root: Path) -> list[AuditCheck]:
    manifest_header, manifest_rows = _read_rows(run_root / CANONICAL_COMPONENT_MANIFEST)
    catalog_header, catalog_rows = _read_rows(run_root / CONTRACT_CATALOG_SNAPSHOT)
    failures: list[str] = []
    manifest_required = {
        "ContractID", "ArtifactType", "Required", "Status", "SourceRows",
        "PublishedRelativePath", "SourceSHA256", "SHA256", "ByteSize",
    }
    catalog_required = {
        "ContractID", "ArtifactType", "Required", "MinimumRows",
        "RequiredColumns", "PrimaryKey",
    }
    missing_manifest = sorted(manifest_required - set(manifest_header))
    missing_catalog = sorted(catalog_required - set(catalog_header))
    if missing_manifest:
        failures.append("manifest_missing_columns=" + ",".join(missing_manifest))
    if missing_catalog:
        failures.append("catalog_missing_columns=" + ",".join(missing_catalog))
    manifest_ids = [_text(row, "ContractID") for row in manifest_rows]
    catalog_ids = [_text(row, "ContractID") for row in catalog_rows]
    if any(not value for value in manifest_ids + catalog_ids):
        failures.append("blank_contract_id")
    if len(manifest_ids) != len(set(manifest_ids)):
        failures.append("duplicate_manifest_contract_id")
    if len(catalog_ids) != len(set(catalog_ids)):
        failures.append("duplicate_catalog_contract_id")
    if set(manifest_ids) != set(catalog_ids):
        failures.append("manifest_catalog_contract_id_set_mismatch")
    catalog_by_id = {_text(row, "ContractID"): row for row in catalog_rows}
    for index, row in enumerate(manifest_rows, start=1):
        contract_id = _text(row, "ContractID")
        prefix = f"row={index}:{contract_id or 'blank'}"
        catalog = catalog_by_id.get(contract_id, {})
        for field in ("ArtifactType", "Required"):
            if _text(row, field).upper() != _text(catalog, field).upper():
                failures.append(prefix + f":{field}_catalog_mismatch")
        required = _boolean(row, "Required")
        status = _text(row, "Status").upper()
        if status not in {"PASS", "FAIL", "NOT_EVALUATED", "NOT_REQUIRED"}:
            failures.append(prefix + ":status_invalid")
        if required is True and status != "PASS" and not _text(row, "Message"):
            failures.append(prefix + ":required_nonpass_message_missing")
        published_rel = _text(row, "PublishedRelativePath").replace("\\", "/")
        published = _io_path(run_root / published_rel) if published_rel else None
        if published is None or not published.is_file():
            failures.append(prefix + f":published_artifact_missing={published_rel or 'blank'}")
            continue
        observed_hash = _sha256(published)
        if _text(row, "SHA256").lower() != observed_hash:
            failures.append(prefix + ":published_sha256_mismatch")
        if _text(row, "SourceSHA256").lower() != observed_hash:
            failures.append(prefix + ":source_sha256_mismatch")
        byte_size = _number(row, "ByteSize")
        if not _whole(byte_size) or int(byte_size) != published.stat().st_size:
            failures.append(prefix + ":byte_size_mismatch")
        artifact_type = _text(row, "ArtifactType").upper()
        if artifact_type == "CSV":
            published_header, published_rows = _read_rows(run_root / published_rel)
            source_rows = _number(row, "SourceRows")
            minimum_rows = _number(catalog, "MinimumRows")
            if not _whole(source_rows) or int(source_rows) != len(published_rows):
                failures.append(prefix + ":SourceRows_mismatch")
            if minimum_rows is None or len(published_rows) < int(minimum_rows):
                failures.append(prefix + ":MinimumRows_not_met")
            required_columns = {
                token.strip() for token in _text(catalog, "RequiredColumns").split("|")
                if token.strip()
            }
            missing_columns = sorted(required_columns - set(published_header))
            if missing_columns:
                failures.append(prefix + ":required_columns_missing=" + ",".join(missing_columns))
            primary_key = [
                token.strip() for token in _text(catalog, "PrimaryKey").split("|")
                if token.strip()
            ]
            if primary_key and all(name in published_header for name in primary_key):
                keys = [tuple(_text(item, name) for name in primary_key) for item in published_rows]
                if any(any(not value for value in key) for key in keys):
                    failures.append(prefix + ":primary_key_blank")
                if len(keys) != len(set(keys)):
                    failures.append(prefix + ":primary_key_duplicate")
    check = _check(
        "manifest_integrity", CANONICAL_COMPONENT_MANIFEST,
        "canonical_manifest_matches_catalog_and_filesystem", manifest_rows, failures,
    )
    catalog_check = _check(
        "manifest_integrity", CONTRACT_CATALOG_SNAPSHOT,
        "contract_catalog_matches_canonical_manifest", catalog_rows, failures,
    )
    return [check, catalog_check]


def _audit_mcs_cqi_reference_tables(run_root: Path) -> list[AuditCheck]:
    checks: list[AuditCheck] = []
    specs = (
        ("reports/csv/mcs_table_reference.csv", "MCSTable", "MCSIndex", False),
        ("reports/csv/cqi_table_reference.csv", "CQITable", "CQI", True),
    )
    for relative, table_field, index_field, zero_is_reserved in specs:
        header, rows = _read_rows(run_root / relative)
        required = {
            "ScenarioID", "ConfigHash", "Direction", table_field, index_field,
            "Modulation", "TargetCodeRate", "SpectralEfficiency",
        }
        failures: list[str] = []
        missing = sorted(required - set(header))
        if missing:
            failures.append("missing_columns=" + ",".join(missing))
        identities = {
            (_text(row, "ScenarioID"), _text(row, "ConfigHash")) for row in rows
        }
        if len(identities) != 1 or any(not all(identity) for identity in identities):
            failures.append("scenario_or_config_identity_not_single_nonblank")
        keys: list[tuple[str, str, int]] = []
        grouped: dict[tuple[str, str], list[int]] = {}
        for row_index, row in enumerate(rows, start=1):
            prefix = f"row={row_index}"
            direction = _text(row, "Direction").upper()
            table_name = _text(row, table_field)
            index = _number(row, index_field)
            if direction not in {"DL", "UL"} or not table_name or not _whole(index):
                failures.append(prefix + ":key_invalid")
                continue
            int_index = int(index)
            key = (direction, table_name, int_index)
            keys.append(key)
            grouped.setdefault((direction, table_name), []).append(int_index)
            rate = _number(row, "TargetCodeRate")
            efficiency = _number(row, "SpectralEfficiency")
            modulation = _text(row, "Modulation").upper()
            if zero_is_reserved and int_index == 0:
                if modulation or rate != 0 or efficiency != 0:
                    failures.append(prefix + ":reserved_zero_entry_invalid")
                continue
            qm = MODULATION_QM.get(modulation)
            if qm is None:
                failures.append(prefix + ":modulation_invalid")
            if rate is None or not (0 < rate <= 1):
                failures.append(prefix + ":target_code_rate_invalid")
            if qm is not None and rate is not None and not _close(
                efficiency, qm * rate, atol=5e-4, rtol=5e-4
            ):
                failures.append(prefix + ":spectral_efficiency_mismatch")
        if len(keys) != len(set(keys)):
            failures.append("duplicate_direction_table_index")
        for group, indexes in grouped.items():
            expected = list(range(min(indexes), max(indexes) + 1))
            if sorted(indexes) != expected:
                failures.append(f"noncontiguous_index_range={group}")
        checks.append(
            _check(
                "domain_runtime", relative,
                "mcs_cqi_reference_arithmetic_and_keys", rows, failures,
            )
        )
    return checks


def _audit_dut_reference_comparison(run_root: Path) -> list[AuditCheck]:
    detail_header, detail_rows = _read_rows(run_root / DUT_REFERENCE_DETAIL)
    summary_header, summary_rows = _read_rows(run_root / DUT_REFERENCE_SUMMARY)
    detail_failures: list[str] = []
    detail_required = {
        "RunId", "BlockId", "DUTValue", "ReferenceValue", "DeltaAbs",
        "ToleranceAbs", "ToleranceRel", "Pass", "ReferenceAvailable",
        "ReferenceSource", "DUTArtifactPath", "FailureReason",
    }
    missing = sorted(detail_required - set(detail_header))
    if missing:
        detail_failures.append("missing_columns=" + ",".join(missing))
    grouped: dict[str, list[dict[str, str]]] = {}
    for index, row in enumerate(detail_rows, start=1):
        prefix = f"row={index}"
        block = _text(row, "BlockId")
        if not block:
            detail_failures.append(prefix + ":BlockId_blank")
        grouped.setdefault(block, []).append(row)
        available = _boolean(row, "ReferenceAvailable")
        passed = _boolean(row, "Pass")
        if available is None or passed is None:
            detail_failures.append(prefix + ":availability_or_pass_invalid")
            continue
        if not available:
            if passed or not _text(row, "FailureReason"):
                detail_failures.append(prefix + ":unavailable_reference_not_fail_closed")
            continue
        dut = _number(row, "DUTValue")
        reference = _number(row, "ReferenceValue")
        delta = _number(row, "DeltaAbs")
        tolerance_abs = _number(row, "ToleranceAbs")
        tolerance_rel = _number(row, "ToleranceRel")
        if None in (dut, reference, delta, tolerance_abs, tolerance_rel):
            detail_failures.append(prefix + ":available_comparison_numeric_value_missing")
            continue
        expected_delta = abs(dut - reference)
        if not _close(delta, expected_delta, atol=1e-12, rtol=1e-9):
            detail_failures.append(prefix + ":DeltaAbs_mismatch")
        expected_pass = expected_delta <= tolerance_abs + tolerance_rel * abs(reference) + 1e-12
        if passed is not expected_pass:
            detail_failures.append(prefix + ":Pass_tolerance_mismatch")
        artifact = _text(row, "DUTArtifactPath").replace("\\", "/")
        if not artifact or not _io_path(run_root / artifact).is_file():
            detail_failures.append(prefix + ":DUTArtifactPath_missing")

    summary_failures: list[str] = []
    summary_by_block = {_text(row, "BlockId"): row for row in summary_rows}
    if set(summary_by_block) != set(grouped):
        summary_failures.append("summary_detail_block_set_mismatch")
    for block, rows in grouped.items():
        summary = summary_by_block.get(block, {})
        passes = sum(_boolean(row, "Pass") is True for row in rows)
        available = all(_boolean(row, "ReferenceAvailable") is True for row in rows)
        expected = {
            "ComparisonCount": len(rows),
            "PassCount": passes,
            "FailCount": len(rows) - passes,
        }
        for field, value in expected.items():
            observed = _number(summary, field)
            if not _whole(observed) or int(observed) != value:
                summary_failures.append(f"{block}:{field}_mismatch")
        if _boolean(summary, "ReferenceAvailable") is not available:
            summary_failures.append(f"{block}:ReferenceAvailable_mismatch")
        if _boolean(summary, "DUTReferencePass") is not (available and passes == len(rows)):
            summary_failures.append(f"{block}:DUTReferencePass_mismatch")
    return [
        _check(
            "cross_table_reconciliation", DUT_REFERENCE_DETAIL,
            "dut_reference_values_and_tolerances", detail_rows, detail_failures,
        ),
        _check(
            "cross_table_reconciliation", DUT_REFERENCE_SUMMARY,
            "reference_summary_recomputed_from_detail", summary_rows, summary_failures,
        ),
    ]


def _fixed_snr_group_key(direction: str, row: dict[str, str]) -> tuple[str, int] | None:
    point = _number(row, "FixedLinkPointIndex", "PointIndex")
    if direction not in {"DL", "UL"} or not _whole(point, 1):
        return None
    return direction, int(point)


def _audit_fixed_snr_reporting_tables(
    run_root: Path,
    link_rows: dict[str, list[dict[str, str]]],
) -> list[AuditCheck]:
    """Recompute the publication sweep tables from canonical TB trials."""

    summary_rel = "reports/csv/fixed_snr_sweep_curve_summary.csv"
    reporting_paths = (
        summary_rel,
        "reports/csv/dl_fixed_snr_bler_curve.csv",
        "reports/csv/dl_fixed_snr_ber_curve.csv",
        "reports/csv/ul_fixed_snr_bler_curve.csv",
        "reports/csv/ul_fixed_snr_ber_curve.csv",
        "reports/csv/dl_fixed_link_bler_curve.csv",
        "reports/csv/dl_fixed_link_ber_curve.csv",
        "reports/csv/ul_fixed_link_bler_curve.csv",
        "reports/csv/ul_fixed_link_ber_curve.csv",
        "reports/csv/fixed_link_campaign_summary.csv",
        "reports/csv/fixed_snr_sweep_required_outputs.csv",
        "reports/csv/fixed_snr_sweep_audit.csv",
    )
    # This contract is specific to a materialized fixed-SNR reporting bundle.
    # PDCCH-only, component-only, and minimal primary-link audits legitimately
    # have no such bundle.  Once any member exists, however, the complete
    # cross-table contract below applies and missing peers fail closed.
    if not any((run_root / relative).is_file() for relative in reporting_paths):
        return []
    summary_header, summary_rows = _read_rows(run_root / summary_rel)
    required_columns = {
        "Direction", "PointIndex", "PointSeed", "SNR_dB", "ConfiguredSNR_dB",
        "AppliedSNR_dB", "MeanMeasuredSINR_dB", "MCS", "Modulation", "Rank",
        "Layers", "TrialCount", "TBPassCount", "TBFailCount", "BLER",
        "BLER_CI_Low", "BLER_CI_High", "BitErrors", "BitsCompared", "BER",
        "BER_CI_Low", "BER_CI_High", "Throughput_Mbps", "Goodput_Mbps",
        "PointStatus", "Incomplete", "Status",
    }
    failures: list[str] = []
    missing = sorted(required_columns - set(summary_header))
    if missing:
        failures.append("missing_columns=" + ",".join(missing))
    raw_groups: dict[tuple[str, int], list[dict[str, str]]] = {}
    for direction, rows in link_rows.items():
        for row in rows:
            key = _fixed_snr_group_key(direction, row)
            if key is None:
                failures.append(f"{direction}:raw_fixed_point_key_missing")
            else:
                raw_groups.setdefault(key, []).append(row)
    summary_by_key: dict[tuple[str, int], dict[str, str]] = {}
    for row in summary_rows:
        direction = _text(row, "Direction").upper()
        key = _fixed_snr_group_key(direction, row)
        if key is None or key in summary_by_key:
            failures.append(f"summary_key_invalid_or_duplicate={key}")
        else:
            summary_by_key[key] = row
    if set(summary_by_key) != set(raw_groups):
        failures.append("summary_raw_operating_point_set_mismatch")

    for key, raw in raw_groups.items():
        row = summary_by_key.get(key, {})
        prefix = f"{key[0]}:point={key[1]}"
        trials = len(raw)
        crc_values = [_boolean(item, "CRCPass") for item in raw]
        if any(value is None for value in crc_values):
            failures.append(prefix + ":raw_crc_invalid")
            continue
        fail_count = sum(value is False for value in crc_values)
        pass_count = trials - fail_count
        bit_errors = sum(int(_number(item, "BitErrors") or 0) for item in raw)
        bits_compared = sum(int(_number(item, "BitsCompared") or 0) for item in raw)
        bler = fail_count / trials if trials else math.nan
        ber = bit_errors / bits_compared if bits_compared else math.nan
        bler_low, bler_high = _clopper_pearson_two_sided(fail_count, trials, 0.95)
        ber_low, ber_high = _clopper_pearson_two_sided(bit_errors, bits_compared, 0.95)
        expected_numbers = {
            "TrialCount": trials,
            "TBPassCount": pass_count,
            "TBFailCount": fail_count,
            "BLER": bler,
            "BLER_CI_Low": bler_low,
            "BLER_CI_High": bler_high,
            "BitErrors": bit_errors,
            "BitsCompared": bits_compared,
            "BER": ber,
            "BER_CI_Low": ber_low,
            "BER_CI_High": ber_high,
        }
        measured = [_number(item, "MeasuredTrialSINR_dB", "PostEqSINR_dB") for item in raw]
        if any(value is None for value in measured):
            failures.append(prefix + ":raw_measured_sinr_missing")
        else:
            values = [float(value) for value in measured if value is not None]
            expected_numbers["MeanMeasuredSINR_dB"] = statistics.fmean(values)
            expected_numbers["MedianMeasuredSINR_dB"] = statistics.median(values)
        goodputs = [_number(item, "Goodput_Mbps") for item in raw]
        if all(value is not None for value in goodputs):
            mean_goodput = statistics.fmean(float(value) for value in goodputs if value is not None)
            expected_numbers["Goodput_Mbps"] = mean_goodput
            expected_numbers["Throughput_Mbps"] = mean_goodput
        for field, expected in expected_numbers.items():
            tolerance = 2e-12 if field not in {"MeanMeasuredSINR_dB", "MedianMeasuredSINR_dB"} else 2e-10
            if not _close(_number(row, field), float(expected), atol=tolerance, rtol=2e-10):
                failures.append(prefix + f":{field}_mismatch")
        if not _close(
            _number(row, "BLER_CI_Width"), bler_high - bler_low, atol=2e-12
        ):
            failures.append(prefix + ":BLER_CI_Width_mismatch")
        if not _close(
            _number(row, "BER_CI_Width"), ber_high - ber_low, atol=2e-12
        ):
            failures.append(prefix + ":BER_CI_Width_mismatch")
        configured_snr = _mode_number(raw, "ConfiguredSNR_dB")
        applied_snr = _mode_number(raw, "AppliedAWGNSNR_dB")
        for field, expected in (
            ("SNR_dB", configured_snr),
            ("ConfiguredSNR_dB", configured_snr),
            ("AppliedSNR_dB", applied_snr),
            ("MCS", _mode_number(raw, "MCSIndex")),
            ("Rank", _mode_number(raw, "Rank")),
            ("Layers", _mode_number(raw, "Layers")),
        ):
            if not _close(_number(row, field), expected, atol=1e-12):
                failures.append(prefix + f":{field}_raw_mode_mismatch")
        if _text(row, "Modulation").upper() != _mode_text(raw, "Modulation").upper():
            failures.append(prefix + ":Modulation_raw_mode_mismatch")
        if _boolean(row, "Incomplete") is True:
            failures.append(prefix + ":complete_point_marked_incomplete")
        # A zero-error point whose one-sided upper confidence bound met the
        # configured stopping rule is complete but right-censored.  Preserve
        # that distinction instead of rejecting truthful CENSORED_COMPLETE
        # evidence as an incomplete operating point.
        point_status = _text(row, "PointStatus").upper()
        if point_status not in {"COMPLETE", "CENSORED_COMPLETE"} or _text(row, "Status").lower() != "complete":
            failures.append(prefix + ":point_status_not_complete")

    checks: list[AuditCheck] = [
        _check(
            "derived_link", summary_rel,
            "fixed_snr_curve_recomputed_from_primary_trials", summary_rows, failures,
        )
    ]

    # The four directional BER/BLER tables intentionally expose the same
    # complete point schema.  Reconcile every field rather than accepting
    # same-shaped but stale copies.
    for direction in ("DL", "UL"):
        expected_rows = [
            row for row in summary_rows if _text(row, "Direction").upper() == direction
        ]
        for metric in ("bler", "ber"):
            relative = f"reports/csv/{direction.lower()}_fixed_snr_{metric}_curve.csv"
            header, rows = _read_rows(run_root / relative)
            copy_failures: list[str] = []
            if header != summary_header:
                copy_failures.append("schema_differs_from_curve_summary")
            if rows != expected_rows:
                copy_failures.append("rows_differ_from_directional_curve_summary")
            checks.append(
                _check(
                    "derived_link", relative,
                    "directional_curve_is_exact_summary_projection", rows, copy_failures,
                )
            )

    for direction in ("DL", "UL"):
        expected_rows = {
            int(_number(row, "PointIndex") or -1): row
            for row in summary_rows
            if _text(row, "Direction").upper() == direction
        }
        for metric in ("bler", "ber"):
            relative = f"reports/csv/{direction.lower()}_fixed_link_{metric}_curve.csv"
            _header, rows = _read_rows(run_root / relative)
            metric_failures: list[str] = []
            if len(rows) != len(expected_rows):
                metric_failures.append("point_count_mismatch")
            for index, item in enumerate(rows, start=1):
                point = int(_number(item, "PointIndex") or -1)
                source = expected_rows.get(point, {})
                expected_metric = metric.upper()
                if _text(item, "Direction").upper() != direction or _text(item, "Metric").upper() != expected_metric:
                    metric_failures.append(f"row={index}:direction_or_metric_mismatch")
                value_field = "BLER" if metric == "bler" else "BER"
                low_field = value_field + "_CI_Low"
                high_field = value_field + "_CI_High"
                for observed_field, source_field in (
                    ("Value", value_field), ("CI_Low", low_field),
                    ("CI_High", high_field), ("TrialCount", "TrialCount"),
                    ("FailureCount", "TBFailCount"),
                    ("MeasuredSINR_dB", "MeanMeasuredSINR_dB"),
                    ("Throughput_Mbps", "Throughput_Mbps"),
                    ("Goodput_Mbps", "Goodput_Mbps"),
                ):
                    if not _close(
                        _number(item, observed_field), _number(source, source_field),
                        atol=2e-10, rtol=2e-10,
                    ):
                        metric_failures.append(f"row={index}:{observed_field}_mismatch")
            checks.append(
                _check(
                    "derived_link", relative,
                    "metric_curve_reconciles_fixed_snr_summary", rows, metric_failures,
                )
            )

    campaign_rel = "reports/csv/fixed_link_campaign_summary.csv"
    _campaign_header, campaign_rows = _read_rows(run_root / campaign_rel)
    campaign_failures: list[str] = []
    campaign_by_direction = {
        _text(row, "Direction").upper(): row for row in campaign_rows
    }
    for direction in ("DL", "UL"):
        source = [
            row for row in summary_rows if _text(row, "Direction").upper() == direction
        ]
        row = campaign_by_direction.get(direction, {})
        expected = {
            "SNRPointCount": len(source),
            "TotalTBCount": sum(int(_number(item, "TrialCount") or 0) for item in source),
            "TotalFailureCount": sum(int(_number(item, "TBFailCount") or 0) for item in source),
            "IncompletePointCount": sum(_boolean(item, "Incomplete") is True for item in source),
        }
        for field, value in expected.items():
            if _number(row, field) != value:
                campaign_failures.append(f"{direction}:{field}_mismatch")
        max_half_width = max(
            ((_number(item, "BLER_CI_Width") or 0) / 2 for item in source),
            default=0.0,
        )
        if not _close(_number(row, "MaxBLERCIHalfWidth"), max_half_width, atol=2e-12):
            campaign_failures.append(direction + ":MaxBLERCIHalfWidth_mismatch")
        if _boolean(row, "CurvePresent") is not bool(source):
            campaign_failures.append(direction + ":CurvePresent_mismatch")
    checks.append(
        _check(
            "derived_link", campaign_rel,
            "campaign_summary_recomputed_from_curve_points", campaign_rows, campaign_failures,
        )
    )

    required_rel = "reports/csv/fixed_snr_sweep_required_outputs.csv"
    _required_header, required_rows = _read_rows(run_root / required_rel)
    required_failures: list[str] = []
    for index, row in enumerate(required_rows, start=1):
        artifact = _text(row, "ArtifactPath").replace("\\", "/")
        path = _io_path(run_root / artifact) if artifact else None
        exists = path is not None and path.is_file()
        nonempty = exists and path.stat().st_size > 0
        if _boolean(row, "Required") is not True:
            required_failures.append(f"row={index}:Required_not_true")
        if _boolean(row, "Present") is not exists:
            required_failures.append(f"row={index}:Present_mismatch")
        if _boolean(row, "Readable") is not exists:
            required_failures.append(f"row={index}:Readable_mismatch")
        if _boolean(row, "NonEmpty") is not nonempty:
            required_failures.append(f"row={index}:NonEmpty_mismatch")
        expected_status = "PASS" if exists and nonempty else "FAIL"
        if _text(row, "Status").upper() != expected_status:
            required_failures.append(f"row={index}:Status_mismatch")
    checks.append(
        _check(
            "manifest_integrity", required_rel,
            "fixed_snr_required_outputs_match_filesystem", required_rows, required_failures,
        )
    )

    audit_rel = "reports/csv/fixed_snr_sweep_audit.csv"
    _audit_header, audit_rows = _read_rows(run_root / audit_rel)
    audit_failures: list[str] = []
    names = [_text(row, "CheckName") for row in audit_rows]
    if any(not value for value in names) or len(names) != len(set(names)):
        audit_failures.append("audit_check_name_blank_or_duplicate")
    for index, row in enumerate(audit_rows, start=1):
        checked = _number(row, "RowsChecked")
        failed = _number(row, "RowsFailed")
        if not _whole(checked) or not _whole(failed) or (checked is not None and failed is not None and failed > checked):
            audit_failures.append(f"row={index}:row_counts_invalid")
        expected_status = "PASS" if failed == 0 else "FAIL"
        if _text(row, "Status").upper() != expected_status:
            audit_failures.append(f"row={index}:status_failure_count_mismatch")
    checks.append(
        _check(
            "status_reduction", audit_rel,
            "fixed_snr_audit_row_arithmetic", audit_rows, audit_failures,
        )
    )
    return checks


def _audit_kpi_reporting_tables(run_root: Path) -> list[AuditCheck]:
    """Reconcile KPI registries, source manifests, formulas, and bindings."""

    registry_rel = "reports/csv/kpi_formula_registry.csv"
    manifest_rel = "reports/csv/kpi_source_table_manifest.csv"
    reconstruction_rel = "reports/csv/kpi_reconstruction_summary.csv"
    binding_rel = "reports/csv/kpi_objective_binding.csv"
    core_paths = (registry_rel, manifest_rel, reconstruction_rel, binding_rel)
    if not any((run_root / relative).is_file() for relative in core_paths):
        return []

    checks: list[AuditCheck] = []
    registry_header, registry_rows = _read_rows(run_root / registry_rel)
    registry_failures: list[str] = []
    registry_required = {
        "KPIName", "Direction", "Layer", "Units", "RequiredSourceTables",
        "Tolerance", "StrictAllowed", "FormulaVersion", "FormulaEquation",
        "ProducerModule", "Status",
    }
    missing = sorted(registry_required - set(registry_header))
    if missing:
        registry_failures.append("missing_columns=" + ",".join(missing))
    registry_names = [_text(row, "KPIName") for row in registry_rows]
    if any(not value for value in registry_names) or len(registry_names) != len(set(registry_names)):
        registry_failures.append("kpi_name_blank_or_duplicate")
    for index, row in enumerate(registry_rows, start=1):
        prefix = f"row={index}"
        if _text(row, "Direction").upper() not in {"DL", "UL", "SCENARIO"}:
            registry_failures.append(prefix + ":direction_invalid")
        if not all(_text(row, name) for name in (
            "Layer", "Units", "RequiredSourceTables", "FormulaVersion",
            "FormulaEquation", "ProducerModule",
        )):
            registry_failures.append(prefix + ":formula_provenance_incomplete")
        tolerance = _number(row, "Tolerance")
        if tolerance is None or tolerance < 0:
            registry_failures.append(prefix + ":tolerance_invalid")
        if _boolean(row, "StrictAllowed") is None:
            registry_failures.append(prefix + ":strict_allowed_invalid")
        if _text(row, "Status").lower() != "active":
            registry_failures.append(prefix + ":formula_not_active")
    checks.append(_check(
        "manifest_integrity", registry_rel,
        "kpi_registry_unique_versioned_formulas", registry_rows, registry_failures,
    ))

    manifest_header, manifest_rows = _read_rows(run_root / manifest_rel)
    manifest_failures: list[str] = []
    manifest_required = {
        "RunId", "ScenarioName", "SourceTablePath", "SourceTableName",
        "Direction", "Layer", "RequiredForObjective", "Exists", "RowCount",
        "ColumnCount", "FileHash", "SchemaHash", "ProducerModule", "Status",
        "FailureReason",
    }
    missing = sorted(manifest_required - set(manifest_header))
    if missing:
        manifest_failures.append("missing_columns=" + ",".join(missing))
    expected_directions = {
        "UL", "DL", "PacketSDU", "ApplicationPackets", "HARQTimeline",
        "ULGrants", "DLGrants", "SlotTrace",
    }
    manifest_by_direction: dict[str, dict[str, str]] = {}
    manifest_sources: dict[str, tuple[list[str], list[dict[str, str]]]] = {}
    for index, row in enumerate(manifest_rows, start=1):
        prefix = f"row={index}"
        direction = _text(row, "Direction")
        if not direction or direction in manifest_by_direction:
            manifest_failures.append(prefix + ":direction_blank_or_duplicate")
        else:
            manifest_by_direction[direction] = row
        required = _boolean(row, "RequiredForObjective")
        exists = _boolean(row, "Exists")
        if required is None or exists is None:
            manifest_failures.append(prefix + ":required_or_exists_invalid")
        source_value = _text(row, "SourceTablePath")
        source_path = _run_relative_path(run_root, source_value)
        if source_value and source_path is None:
            manifest_failures.append(prefix + ":source_path_not_run_relative")
        actual_header: list[str] = []
        actual_rows: list[dict[str, str]] = []
        actual_exists = bool(source_path and _io_path(source_path).is_file())
        if actual_exists and source_path is not None:
            actual_header, actual_rows = _read_rows(source_path)
            manifest_sources[direction] = (actual_header, actual_rows)
        if exists is not actual_exists or not _close(
            _number(row, "RowCount"), float(len(actual_rows)), atol=0,
        ) or not _close(
            _number(row, "ColumnCount"), float(len(actual_header)), atol=0,
        ):
            manifest_failures.append(prefix + ":persisted_source_shape_or_exists_mismatch")
        source_hash = _text(row, "FileHash")
        if actual_exists and not _is_sha256(source_hash):
            manifest_failures.append(prefix + ":source_rows_hash_invalid")
        if not actual_exists and source_hash.lower() not in {"", "empty"}:
            manifest_failures.append(prefix + ":missing_source_hash_not_empty")
        status = _text(row, "Status").lower()
        reason = _text(row, "FailureReason")
        if actual_exists:
            if status != "pass" or reason:
                manifest_failures.append(prefix + ":available_source_status_invalid")
        elif required is True:
            if status not in {"missing", "fail"} or not reason:
                manifest_failures.append(prefix + ":required_missing_source_not_fail_closed")
        elif required is False:
            if status != "not_applicable" or not reason:
                manifest_failures.append(prefix + ":optional_missing_source_not_applicable")
        if not _text(row, "SchemaHash") or not _text(row, "ProducerModule"):
            manifest_failures.append(prefix + ":schema_or_producer_missing")
    if set(manifest_by_direction) != expected_directions:
        manifest_failures.append("source_direction_membership_mismatch")
    checks.append(_check(
        "manifest_integrity", manifest_rel,
        "kpi_source_manifest_matches_exact_persisted_tables",
        manifest_rows, manifest_failures,
    ))

    reconstruction_header, reconstruction_rows = _read_rows(run_root / reconstruction_rel)
    reconstruction_failures: list[str] = []
    reconstruction_required = {
        "KPIName", "Direction", "FormulaId", "FormulaVersion", "Value",
        "SourceTablePaths", "SourceRowCount", "EligibleRowCount",
        "ExcludedRowCount", "SourceRowsHash", "MissingRawData", "SchemaValid",
        "Applicable", "ApplicabilityReason", "FormulaExecuted",
        "ReconstructionValue", "ReconciliationTolerance", "ReconciliationPass",
        "StrictOk", "Status", "FailureReason",
    }
    missing = sorted(reconstruction_required - set(reconstruction_header))
    if missing:
        reconstruction_failures.append("missing_columns=" + ",".join(missing))
    reconstruction_by_name: dict[str, dict[str, str]] = {}
    for index, row in enumerate(reconstruction_rows, start=1):
        prefix = f"row={index}"
        name = _text(row, "KPIName")
        if not name or name in reconstruction_by_name:
            reconstruction_failures.append(prefix + ":kpi_name_blank_or_duplicate")
        else:
            reconstruction_by_name[name] = row
        if name not in set(registry_names):
            reconstruction_failures.append(prefix + ":kpi_not_in_registry")
        if _text(row, "FormulaId") != name:
            reconstruction_failures.append(prefix + ":formula_id_mismatch")
        direction = _text(row, "Direction")
        applicable = _boolean(row, "Applicable")
        source_relative = _text(row, "SourceTablePaths").replace("\\", "/")
        manifest_row = next((
            item for item in manifest_rows
            if _text(item, "SourceTablePath").replace("\\", "/") == source_relative
        ), {})
        if manifest_row and applicable is True:
            manifest_direction = _text(manifest_row, "Direction")
            if manifest_direction == "HARQTimeline" and direction.upper() in {"DL", "UL"}:
                expected_count = _number(
                    manifest_row, direction.upper() + "SubsetRowCount"
                )
                expected_hash = _text(
                    manifest_row, direction.upper() + "SubsetRowsHash"
                )
            else:
                expected_count = _number(manifest_row, "RowCount")
                expected_hash = _text(manifest_row, "FileHash")
            if not _close(
                _number(row, "SourceRowCount"), expected_count, atol=0,
            ) or _text(row, "SourceRowsHash") != expected_hash:
                reconstruction_failures.append(prefix + ":source_count_or_hash_manifest_mismatch")
        elif source_relative and _run_relative_path(run_root, source_relative) is None:
            reconstruction_failures.append(prefix + ":source_path_not_run_relative")
        source_rows = _number(row, "SourceRowCount")
        eligible = _number(row, "EligibleRowCount")
        excluded = _number(row, "ExcludedRowCount")
        if applicable is True and not _close(
            source_rows, (eligible or 0) + (excluded or 0), atol=0
        ):
            reconstruction_failures.append(prefix + ":eligible_excluded_source_count_mismatch")
        strict = _boolean(row, "StrictOk")
        recon_pass = _boolean(row, "ReconciliationPass")
        formula_executed = _boolean(row, "FormulaExecuted")
        status = _text(row, "Status").lower()
        reason = _text(row, "FailureReason")
        if applicable is True:
            if formula_executed is not True or strict is not True or recon_pass is not True or status != "pass":
                reconstruction_failures.append(prefix + ":applicable_kpi_not_strict_pass")
            if reason or _number(row, "Value") is None or not _close(
                _number(row, "Value"), _number(row, "ReconstructionValue"), atol=2e-12,
            ):
                reconstruction_failures.append(prefix + ":applicable_kpi_value_or_reason_invalid")
        elif applicable is False:
            if formula_executed is not False or strict is not True or status != "not_applicable":
                reconstruction_failures.append(prefix + ":disabled_kpi_applicability_status_invalid")
            if not _text(row, "ApplicabilityReason"):
                reconstruction_failures.append(prefix + ":disabled_kpi_reason_missing")
        else:
            reconstruction_failures.append(prefix + ":applicable_invalid")
    checks.append(_check(
        "cross_table_reconciliation", reconstruction_rel,
        "kpi_reconstruction_matches_registry_sources_and_applicability",
        reconstruction_rows, reconstruction_failures,
    ))

    binding_header, binding_rows = _read_rows(run_root / binding_rel)
    binding_failures: list[str] = []
    binding_required = {
        "KPIName", "FormulaId", "MandatoryInScenarioObjective", "Applicable",
        "ApplicabilityReason", "RawEvidenceAvailable", "ReconstructionPass",
        "StrictOk", "ScenarioObjectiveContribution", "Status", "FailureReason",
    }
    missing = sorted(binding_required - set(binding_header))
    if missing:
        binding_failures.append("missing_columns=" + ",".join(missing))
    binding_names = [_text(row, "KPIName") for row in binding_rows]
    if set(binding_names) != set(registry_names) or len(binding_names) != len(set(binding_names)):
        binding_failures.append("binding_registry_membership_or_uniqueness_mismatch")
    for index, row in enumerate(binding_rows, start=1):
        prefix = f"row={index}"
        name = _text(row, "KPIName")
        if _text(row, "FormulaId") != name:
            binding_failures.append(prefix + ":formula_id_mismatch")
        applicable = _boolean(row, "Applicable")
        mandatory = _boolean(row, "MandatoryInScenarioObjective")
        status = _text(row, "Status").lower()
        reason = _text(row, "FailureReason")
        recon = reconstruction_by_name.get(name)
        if applicable is False:
            if mandatory is not False or status != "not_applicable" or not _text(row, "ApplicabilityReason"):
                binding_failures.append(prefix + ":not_applicable_binding_invalid")
        elif recon is not None:
            for binding_field, reconstruction_field in (
                ("Applicable", "Applicable"),
                ("ReconstructionPass", "ReconciliationPass"),
                ("StrictOk", "StrictOk"),
            ):
                if _boolean(row, binding_field) is not _boolean(recon, reconstruction_field):
                    binding_failures.append(prefix + f":{binding_field}_reconstruction_mismatch")
            expected_raw = _boolean(recon, "MissingRawData") is False
            if _boolean(row, "RawEvidenceAvailable") is not expected_raw:
                binding_failures.append(prefix + ":raw_evidence_reconstruction_mismatch")
            if _boolean(row, "StrictOk") is True and (status != "pass" or reason):
                binding_failures.append(prefix + ":strict_binding_not_clean_pass")
        elif applicable is True:
            if status not in {"not_evaluated", "fail"} or not reason:
                binding_failures.append(prefix + ":applicable_missing_reconstruction_not_fail_closed")
        else:
            binding_failures.append(prefix + ":applicable_invalid")
    checks.append(_check(
        "cross_table_reconciliation", binding_rel,
        "kpi_objective_binding_exact_registry_and_reconstruction_reduction",
        binding_rows, binding_failures,
    ))

    direction_rel = "reports/csv/kpi_direction_isolation_audit.csv"
    _direction_header, direction_rows = _read_rows(run_root / direction_rel)
    direction_failures: list[str] = []
    direction_by_name = {_text(row, "Direction").upper(): row for row in direction_rows}
    if set(direction_by_name) != {"DL", "UL"} or len(direction_rows) != 2:
        direction_failures.append("direction_membership_mismatch")
    for direction in ("DL", "UL"):
        row = direction_by_name.get(direction, {})
        manifest_row = manifest_by_direction.get(direction, {})
        opposite = manifest_by_direction.get("UL" if direction == "DL" else "DL", {})
        if _text(row, "SourceTablePath").replace("\\", "/") != _text(
            manifest_row, "SourceTablePath"
        ).replace("\\", "/"):
            direction_failures.append(direction + ":source_path_mismatch")
        if not _close(_number(row, "RowsWithExpectedDirection"), _number(manifest_row, "RowCount"), atol=0):
            direction_failures.append(direction + ":expected_direction_count_mismatch")
        if any((_number(row, field) or 0) != 0 for field in (
            "RowsWithWrongDirection", "CrossDirectionSourceUsed", "HashCollisionOrCopySuspected",
        )):
            direction_failures.append(direction + ":cross_direction_contamination")
        if _text(row, "SourceRowsHash") != _text(manifest_row, "FileHash") or _text(
            row, "OppositeDirectionRowsHash"
        ) != _text(opposite, "FileHash"):
            direction_failures.append(direction + ":direction_hash_manifest_mismatch")
        if _text(row, "Status").lower() != "pass" or _text(row, "FailureReason"):
            direction_failures.append(direction + ":direction_status_invalid")
    checks.append(_check(
        "cross_table_reconciliation", direction_rel,
        "kpi_direction_isolation_matches_source_manifest", direction_rows, direction_failures,
    ))

    duration_rel = "reports/csv/kpi_duration_source_audit.csv"
    _duration_header, duration_rows = _read_rows(run_root / duration_rel)
    duration_failures: list[str] = []
    for index, row in enumerate(duration_rows, start=1):
        direction = _text(row, "Direction").upper()
        prefix = f"row={index}"
        if direction not in {"DL", "UL"}:
            duration_failures.append(prefix + ":direction_invalid")
            continue
        if not _close(_number(row, "SlotCount"), _number(manifest_by_direction.get(direction, {}), "RowCount"), atol=0):
            duration_failures.append(prefix + ":slot_count_source_rows_mismatch")
        aggregation = _number(row, "AggregationDurationSec")
        if aggregation is None or aggregation <= 0 or not _close(
            aggregation, _number(row, "RadioDurationSec"), atol=2e-12,
        ) or _boolean(row, "WallClockUsedForRadioThroughput") is not False:
            duration_failures.append(prefix + ":radio_duration_or_wallclock_invalid")
        if _boolean(row, "Pass") is not True or _text(row, "Status").lower() != "pass" or _text(row, "FailureReason"):
            duration_failures.append(prefix + ":duration_status_invalid")
    checks.append(_check(
        "cross_table_reconciliation", duration_rel,
        "kpi_duration_uses_radio_not_wallclock_time", duration_rows, duration_failures,
    ))

    unit_rel = "reports/csv/kpi_unit_conversion_audit.csv"
    _unit_header, unit_rows = _read_rows(run_root / unit_rel)
    unit_failures: list[str] = []
    for index, row in enumerate(unit_rows, start=1):
        prefix = f"row={index}"
        applicable = _boolean(row, "Applicable")
        if applicable is True:
            bits = _number(row, "Bits")
            duration = _number(row, "DurationSec")
            expected = bits / duration / 1e6 if bits is not None and duration and duration > 0 else None
            if not _close(_number(row, "ExpectedMbps"), expected, atol=2e-12) or not _close(
                _number(row, "Delta"), abs((_number(row, "ExpectedMbps") or 0) - (_number(row, "ComputedMbps") or 0)), atol=2e-12,
            ):
                unit_failures.append(prefix + ":mbps_formula_or_delta_mismatch")
            if _boolean(row, "Pass") is not True or _text(row, "Status").lower() != "pass":
                unit_failures.append(prefix + ":unit_conversion_not_pass")
        elif applicable is False:
            if _text(row, "Status").lower() != "not_applicable":
                unit_failures.append(prefix + ":disabled_conversion_status_invalid")
        else:
            unit_failures.append(prefix + ":applicable_invalid")
    checks.append(_check(
        "cross_table_reconciliation", unit_rel,
        "kpi_bit_duration_mbps_conversion_recomputed", unit_rows, unit_failures,
    ))

    alias_rel = "reports/csv/kpi_legacy_alias_map.csv"
    _alias_header, alias_rows = _read_rows(run_root / alias_rel)
    alias_failures: list[str] = []
    for index, row in enumerate(alias_rows, start=1):
        if not _close(_number(row, "AliasValue"), _number(row, "CanonicalValue"), atol=2e-12) or _boolean(row, "Equal") is not True:
            alias_failures.append(f"row={index}:alias_canonical_value_mismatch")
        if _text(row, "Status").lower() != "pass" or _text(row, "FailureReason"):
            alias_failures.append(f"row={index}:alias_status_invalid")
    checks.append(_check(
        "cross_table_reconciliation", alias_rel,
        "legacy_kpi_aliases_equal_canonical_values", alias_rows, alias_failures,
    ))

    bug_rel = "reports/csv/kpi_known_bug_regression.csv"
    _bug_header, bug_rows = _read_rows(run_root / bug_rel)
    bug_failures: list[str] = []
    for index, row in enumerate(bug_rows, start=1):
        if not _close(_number(row, "CorrectExportedULValueMbps"), _number(row, "ULRawValueMbps"), atol=2e-12):
            bug_failures.append(f"row={index}:correct_ul_not_raw_ul")
        if _boolean(row, "BugDetected") is not False or _boolean(row, "BugPrevented") is not True:
            bug_failures.append(f"row={index}:known_bug_guard_invalid")
        if _text(row, "Status").lower() != "pass" or _text(row, "FailureReason"):
            bug_failures.append(f"row={index}:known_bug_status_invalid")
    checks.append(_check(
        "cross_table_reconciliation", bug_rel,
        "ul_kpi_copy_regression_guard", bug_rows, bug_failures,
    ))

    lineage_rel = "reports/csv/kpi_lineage_table.csv"
    _lineage_header, lineage_rows = _read_rows(run_root / lineage_rel)
    lineage_failures: list[str] = []
    if len(lineage_rows) != len(reconstruction_rows):
        lineage_failures.append("lineage_reconstruction_row_count_mismatch")
    lineage_by_name = {_text(row, "KPIName"): row for row in lineage_rows}
    for name, recon in reconstruction_by_name.items():
        row = lineage_by_name.get(name, {})
        for field in (
            "Direction", "FormulaId", "FormulaVersion", "Applicable",
            "ApplicabilityReason", "Value", "NumeratorValue", "DenominatorValue",
            "AggregationDurationSec", "DurationSource", "SourceTablePaths",
            "SourceRowCount", "EligibleRowCount", "SourceRowsHash",
            "StrictOk", "Status", "FailureReason",
        ):
            if _text(row, field) != _text(recon, field):
                lineage_failures.append(name + f":{field}_reconstruction_projection_mismatch")
        if _boolean(row, "ReconstructionPass") is not _boolean(recon, "ReconciliationPass"):
            lineage_failures.append(name + ":ReconstructionPass_reconstruction_projection_mismatch")
    checks.append(_check(
        "cross_table_reconciliation", lineage_rel,
        "kpi_lineage_exact_reconstruction_projection", lineage_rows, lineage_failures,
    ))

    summary_rel = "reports/csv/summary_vs_raw_consistency.csv"
    _summary_header, summary_rows = _read_rows(run_root / summary_rel)
    summary_failures: list[str] = []
    for index, row in enumerate(summary_rows, start=1):
        summary_value = _number(row, "SummaryValue")
        raw_value = _number(row, "RawDerivedValue")
        browser_value = _number(row, "BrowserDisplayedValue")
        numeric = summary_value is not None or raw_value is not None or browser_value is not None
        if numeric:
            consistent = _close(summary_value, raw_value, atol=2e-12) and _close(summary_value, browser_value, atol=2e-12)
        else:
            consistent = _text(row, "SummaryValue") == _text(row, "RawDerivedValue") == _text(row, "BrowserDisplayedValue")
        if not consistent or _text(row, "ConsistencyStatus").lower() != "consistent":
            summary_failures.append(f"row={index}:summary_raw_browser_mismatch")
        source_tokens = [value for value in _text(row, "RawSourceArtifacts").split("|") if value]
        if not source_tokens or any(_run_relative_path(run_root, value) is None for value in source_tokens):
            summary_failures.append(f"row={index}:raw_source_artifact_invalid")
    checks.append(_check(
        "cross_table_reconciliation", summary_rel,
        "scenario_summary_values_match_raw_and_browser", summary_rows, summary_failures,
    ))
    return checks


def _audit_provenance_and_reference_tables(
    run_root: Path, *, component_only: bool = False
) -> list[AuditCheck]:
    checks: list[AuditCheck] = []
    checks.extend(_audit_measurement_sidecar_manifest(run_root))
    if component_only:
        for relative, check_id in (
            (CANONICAL_COMPONENT_MANIFEST, "not_applicable_without_artifact_contract"),
            (CONTRACT_CATALOG_SNAPSHOT, "not_applicable_without_artifact_contract"),
            ("reports/csv/mcs_table_reference.csv", "not_applicable_without_data_channel"),
            ("reports/csv/cqi_table_reference.csv", "not_applicable_without_data_channel"),
            (DUT_REFERENCE_DETAIL, "not_applicable_without_dut_reference_campaign"),
            (DUT_REFERENCE_SUMMARY, "not_applicable_without_dut_reference_campaign"),
        ):
            _header, rows = _read_rows(run_root / relative)
            checks.append(_check(
                "manifest_integrity" if "artifact_" in relative else "domain_runtime",
                relative, check_id, rows, [], required=False, evaluated=False,
            ))
        return checks
    capture_header, capture_rows = _read_rows(run_root / CONTINUOUS_IQ_MANIFEST)
    segment_header, segment_rows = _read_rows(run_root / CONTINUOUS_IQ_SEGMENTS)
    capture_required = _nested_value(_load_resolved_config(run_root),
                                    "run_control.continuous_raw_iq_capture_enable", False) is True
    if capture_header or segment_header or capture_required:
        failures = validate_continuous_iq_capture(run_root, capture_rows, segment_rows, _io_path)
        for path, rows in [(CONTINUOUS_IQ_MANIFEST, capture_rows), (CONTINUOUS_IQ_SEGMENTS, segment_rows)]:
            checks.append(_check("manifest_integrity", path,
                "continuous_iq_file_and_segment_rf_hash_clock_closure", rows, failures))
    checks.extend(_audit_canonical_component_manifest(run_root))
    checks.extend(_audit_mcs_cqi_reference_tables(run_root))
    checks.extend(_audit_dut_reference_comparison(run_root))
    return checks


def _audit_status_reduction(run_root: Path, summary_path: str, summary: dict[str, str]) -> list[AuditCheck]:
    """Verify terminal status CSVs describe the exact persisted visual tree."""

    integrity_rel = "reports/csv/visual_artifact_integrity.csv"
    visual_rel = "reports/csv/visual_artifact_audit.csv"
    result_rel = "reports/csv/result_status_summary.csv"
    failures_rel = "reports/csv/truth_contract_failures.csv"
    _ih, integrity_rows = _read_rows(run_root / integrity_rel)
    _vh, visual_rows = _read_rows(run_root / visual_rel)
    _rh, result_rows = _read_rows(run_root / result_rel)
    _fh, failure_rows = _read_rows(run_root / failures_rel)
    if not integrity_rows and not visual_rows and not result_rows:
        return [
            _check(
                "status_reduction",
                summary_path,
                "terminal_status_evidence_present",
                [],
                [],
                required=False,
                evaluated=False,
            )
        ]

    integrity_failures = sum(_boolean(row, "IntegrityOk", "integrity_ok") is not True for row in integrity_rows)
    visual_failures = sum(_boolean(row, "audit_ok", "AuditOk") is not True for row in visual_rows)
    visual_ok = bool(integrity_rows) and bool(visual_rows) and integrity_failures == 0 and visual_failures == 0
    expected_visual_failures = integrity_failures + visual_failures
    result = result_rows[0] if result_rows else {}
    checks: list[AuditCheck] = []

    visual_status_failures: list[str] = []
    for label, row, boolean_names, count_names in (
        (
            "scenario_summary_legacy",
            summary,
            ("VisualArtifactIntegrityOk",),
            ("VisualArtifactIntegrityFailureCount",),
        ),
        (
            "scenario_summary_gate",
            summary,
            ("VisualArtifactGateOk",),
            ("VisualArtifactFailureCount",),
        ),
        (
            "result_status",
            result,
            ("VisualArtifactGateOk",),
            ("VisualArtifactFailureCount",),
        ),
    ):
        observed_ok = _boolean(row, *boolean_names)
        observed_count = _number(row, *count_names)
        if observed_ok is not visual_ok:
            visual_status_failures.append(f"{label}:ok={observed_ok};expected={visual_ok}")
        if observed_count is None or int(observed_count) != expected_visual_failures:
            visual_status_failures.append(
                f"{label}:failure_count={observed_count};expected={expected_visual_failures}"
            )
    visual_failure_tokens = [
        _text(row, "FailureCode")
        for row in failure_rows
        if "visual_artifact" in _text(row, "FailureCode").lower()
    ]
    if visual_ok and visual_failure_tokens:
        visual_status_failures.append("truth_contract_retains_visual_failures_after_visual_pass")
    if not visual_ok and not visual_failure_tokens:
        visual_status_failures.append("truth_contract_omits_current_visual_failure")
    checks.append(
        _check(
            "status_reduction",
            summary_path,
            "terminal_visual_status_matches_persisted_audits",
            [summary] if summary else [],
            visual_status_failures,
        )
    )

    truth_clean = len(failure_rows) == 0
    truth_status_failures: list[str] = []
    for label, row in (("scenario_summary", summary), ("result_status", result)):
        observed = _boolean(row, "RuntimeTruthContractOk", "TruthContractOk")
        if observed is not truth_clean:
            truth_status_failures.append(f"{label}:truth_ok={observed};expected={truth_clean}")
    summary_result = _boolean(summary, "ResultOk", "Ok")
    root_result = _boolean(result, "ResultOk")
    if summary_result is None or root_result is None or summary_result is not root_result:
        truth_status_failures.append(
            f"result_ok_mismatch:scenario_summary={summary_result};result_status={root_result}"
        )
    checks.append(
        _check(
            "status_reduction",
            result_rel,
            "truth_failure_and_root_status_reduction_consistent",
            result_rows,
            truth_status_failures,
        )
    )
    return checks


def _split_artifact_paths(value: str) -> list[str]:
    return [
        token.strip().replace("\\", "/")
        for token in str(value).split("|")
        if token.strip()
    ]


def _all_required_gate_rows_pass(
    rows: list[dict[str, str]],
    required_column: str,
    pass_column: str,
) -> bool:
    required = [_boolean(row, required_column) for row in rows]
    passed = [_boolean(row, pass_column) for row in rows]
    return (
        bool(rows)
        and all(value is not None for value in required + passed)
        and any(value is True for value in required)
        and all(req is not True or ok is True for req, ok in zip(required, passed))
    )


def _audit_gate_row_table(
    run_root: Path,
    relative: str,
    *,
    key_column: str,
    required_column: str,
    pass_column: str | None = None,
    status_column: str | None = None,
    evidence_column: str | None = None,
    source_count_column: str | None = None,
) -> AuditCheck:
    """Validate one explicitly declared gate table without requiring a pass.

    A failing gate may be the correct scientific result.  The contract checks
    that required/pass/status arithmetic, failure disclosure and referenced
    evidence are coherent; it never rewrites a FAIL into PASS.
    """

    header, rows = _read_rows(run_root / relative)
    required_columns = {key_column, required_column}
    if pass_column:
        required_columns.add(pass_column)
    if status_column:
        required_columns.add(status_column)
    if evidence_column:
        required_columns.add(evidence_column)
    if source_count_column:
        required_columns.add(source_count_column)
    failures: list[str] = []
    missing = sorted(required_columns - set(header))
    if missing:
        failures.append("missing_columns=" + ",".join(missing))
    if not rows:
        failures.append("gate_rows_missing")
    keys = [_text(row, key_column) for row in rows]
    if any(not key for key in keys):
        failures.append("blank_gate_key")
    if len(keys) != len(set(keys)):
        failures.append("duplicate_gate_key")

    for index, row in enumerate(rows, start=1):
        prefix = f"row={index}:{_text(row, key_column) or 'missing_key'}"
        required = _boolean(row, required_column)
        if required is None:
            failures.append(prefix + ":required_flag_invalid")
        passed: bool | None = None
        if pass_column:
            passed = _boolean(row, pass_column)
            if passed is None:
                failures.append(prefix + ":pass_flag_invalid")
        if status_column:
            status = _text(row, status_column).upper()
            if status not in {"PASS", "FAIL", "NOT_EVALUATED", "NOT_REQUIRED", "NOT_APPLICABLE"}:
                failures.append(prefix + f":status_invalid={status or 'blank'}")
            status_pass = status == "PASS"
            if passed is not None and status_pass is not passed:
                failures.append(prefix + ":pass_status_mismatch")
            if passed is None:
                passed = status_pass
        failure_reason = _text(row, "FailureReason", "FailureCode", "Reason")
        if required is True and passed is False and not failure_reason:
            failures.append(prefix + ":required_failure_reason_missing")

        for count_name in ("FailureCount", "RowsChecked", "RowsFailed", source_count_column or ""):
            if not count_name or count_name not in header:
                continue
            count = _number(row, count_name)
            if not _whole(count):
                failures.append(prefix + f":{count_name}_invalid")
        if "FailureCount" in header:
            failure_count = _number(row, "FailureCount")
            if passed is True and failure_count != 0:
                failures.append(prefix + ":pass_with_nonzero_failure_count")
            if passed is False and required is True and failure_count == 0 and not failure_reason:
                failures.append(prefix + ":failed_required_gate_has_no_failure_evidence")
        if "RowsFailed" in header:
            rows_failed = _number(row, "RowsFailed")
            if passed is True and rows_failed != 0:
                failures.append(prefix + ":pass_with_failed_rows")

        if evidence_column:
            artifacts = _split_artifact_paths(_text(row, evidence_column))
            if required is True and passed is True and not artifacts:
                failures.append(prefix + ":passing_required_gate_has_no_evidence_path")
            existing_rows = 0
            for artifact in artifacts:
                artifact_path = _io_path(run_root / artifact)
                if not artifact_path.is_file():
                    if passed is True:
                        failures.append(prefix + f":passing_gate_evidence_missing={artifact}")
                    continue
                if source_count_column:
                    _source_header, source_rows = _read_rows(run_root / artifact)
                    existing_rows += len(source_rows)
            if source_count_column and artifacts:
                declared = _number(row, source_count_column)
                if declared is None or int(declared) != existing_rows:
                    failures.append(
                        prefix + f":source_row_count_mismatch={declared}!={existing_rows}"
                    )

    return _check(
        "status_reduction", relative, "declared_gate_rows_are_coherent", rows, failures
    )


def _audit_phase7_reducer(run_root: Path) -> list[AuditCheck]:
    relative = "reports/csv/phase7_truth_gates.csv"
    header, rows = _read_rows(run_root / relative)
    failures: list[str] = []
    if len(rows) != 1:
        failures.append(f"expected_one_phase7_row;observed={len(rows)}")
        return [_check("status_reduction", relative, "phase7_exact_reduction", rows, failures)]
    row = rows[0]
    try:
        first_phase = header.index("Phase1Ok")
    except ValueError:
        failures.append("Phase1Ok_missing")
        first_phase = 0
    gate_names = [name for name in header[:first_phase] if name.endswith("Ok")]
    if tuple(gate_names) != PHASE7_GATE_NAMES:
        failures.append("phase7_gate_columns_missing_extra_or_reordered")
    not_applicable = {
        token.strip()
        for token in _text(row, "NotApplicableGateNames").split(";")
        if token.strip()
    }
    unknown_not_applicable = sorted(not_applicable - set(gate_names))
    if unknown_not_applicable:
        failures.append("unknown_not_applicable=" + ",".join(unknown_not_applicable))
    observed_gate_values: dict[str, bool] = {}
    for name in gate_names:
        value = _boolean(row, name)
        if value is None:
            failures.append(name + "_invalid_boolean")
        else:
            observed_gate_values[name] = value

    for phase_name, member_names in PHASE7_PHASE_MEMBERS.items():
        observed = _boolean(row, phase_name)
        expected = all(
            member in not_applicable or observed_gate_values.get(member) is True
            for member in member_names
        )
        if observed is not expected:
            failures.append(f"{phase_name}_rollup_mismatch={observed}!={expected}")
    phase7_expected = all(
        name in not_applicable or observed_gate_values.get(name) is True
        for name in gate_names
    )
    if _boolean(row, "Phase7Ok") is not phase7_expected:
        failures.append("Phase7Ok_rollup_mismatch")
    phase_values = [_boolean(row, f"Phase{index}Ok") for index in range(1, 7)]
    result_expected = phase7_expected and all(value is True for value in phase_values)
    if _boolean(row, "ResultOk") is not result_expected:
        failures.append("ResultOk_phase_rollup_mismatch")

    expected_failure_codes = [
        name + "_false"
        for name in gate_names
        if name not in not_applicable and observed_gate_values.get(name) is False
    ]
    expected_failure_codes.extend(
        f"Phase{index}Ok_false"
        for index, value in enumerate(phase_values, start=1)
        if value is False
    )
    if _boolean(row, "PublicationReadinessOk") is not True:
        expected_failure_codes.append("PublicationReadinessOk_false")
    observed_failure_codes = [
        token.strip()
        for token in _text(row, "FailureCodes").split(";")
        if token.strip()
    ]
    if observed_failure_codes != expected_failure_codes:
        failures.append("FailureCodes_do_not_match_false_applicable_gates")
    expected_primary = expected_failure_codes[0] if expected_failure_codes else ""
    if _text(row, "PrimaryFailureCode") != expected_primary:
        failures.append("PrimaryFailureCode_mismatch")
    if _text(row, "ResultOkAuthority") != "all_phase_gates_required_no_lower_pass_override":
        failures.append("ResultOkAuthority_invalid")
    if _text(row, "ProducerModule") != "sixgr.runtime.Phase7TruthEvaluator":
        failures.append("ProducerModule_invalid")
    return [_check("status_reduction", relative, "phase7_exact_reduction", rows, failures)]


def _audit_reconciliation_reducers(run_root: Path) -> list[AuditCheck]:
    phase7_rel = "reports/csv/phase7_truth_gates.csv"
    _phase7_header, phase7_rows = _read_rows(run_root / phase7_rel)
    phase7 = phase7_rows[0] if len(phase7_rows) == 1 else {}
    checks: list[AuditCheck] = []
    for relative, mapping in RECONCILIATION_PHASE7_FLAGS.items():
        source_field, phase7_field = mapping if isinstance(mapping, tuple) else (mapping, mapping)
        header, rows = _read_rows(run_root / relative)
        failures: list[str] = []
        if source_field not in header:
            failures.append("outcome_column_missing=" + source_field)
        if not rows:
            failures.append("reconciliation_rows_missing")
        source_values = [_boolean(row, source_field) for row in rows]
        if any(value is None for value in source_values):
            failures.append("outcome_boolean_invalid")
        source_outcome = bool(rows) and all(value is True for value in source_values)
        phase7_outcome = _boolean(phase7, phase7_field)
        if phase7_outcome is None:
            failures.append("phase7_outcome_missing_or_invalid=" + phase7_field)
        elif source_outcome is not phase7_outcome:
            failures.append(
                f"phase7_outcome_mismatch:{source_field}={source_outcome};"
                f"{phase7_field}={phase7_outcome}"
            )
        for index, row in enumerate(rows, start=1):
            value = _boolean(row, source_field)
            if value is False and "FailureReason" in header and not _text(row, "FailureReason"):
                failures.append(f"row={index}:failed_reconciliation_reason_missing")
            for name in header:
                normalized = _normalized_column(name)
                if not normalized.endswith(("count", "rows")):
                    continue
                number = _number(row, name)
                if number is not None and not _whole(number):
                    failures.append(f"row={index}:{name}_negative_or_fractional")
        checks.append(
            _check(
                "cross_table_reconciliation", relative,
                "outcome_matches_phase7_and_rows_are_coherent", rows, failures,
            )
        )
    return checks


def _audit_publication_reducer(run_root: Path) -> list[AuditCheck]:
    relative = "reports/csv/publication_readiness_gate_summary.csv"
    header, rows = _read_rows(run_root / relative)
    failures: list[str] = []
    fields = (
        "EnergyModelOk", "PerformanceProfileOk", "LongRunStabilityOk",
        "ArtifactCompletenessOk", "PlotDataLineageOk",
        "FinalScientificClaimsTruthfulOk", "TwoModeAcceptanceGatesOk",
        "FixedSNRLLSOk", "GeometryScenarioOk", "PublicationReferenceComparisonOk",
    )
    if len(rows) != 1:
        failures.append(f"expected_one_publication_row;observed={len(rows)}")
        return [_check("status_reduction", relative, "publication_exact_reduction", rows, failures)]
    row = rows[0]
    values: dict[str, bool] = {}
    for field in fields + ("TerminalPublicationGatesOk",):
        if field not in header:
            failures.append(field + "_missing")
            continue
        value = _boolean(row, field)
        if value is None:
            failures.append(field + "_invalid_boolean")
        else:
            values[field] = value
    terminal_members = fields[:7]
    terminal_expected = all(values.get(field) is True for field in terminal_members)
    if values.get("TerminalPublicationGatesOk") is not terminal_expected:
        failures.append("TerminalPublicationGatesOk_rollup_mismatch")
    if _text(row, "EvaluationPolicy") != "evidence_files_only_no_forced_publication_pass":
        failures.append("EvaluationPolicy_invalid")

    _phase_header, phase_rows = _read_rows(run_root / "reports/csv/phase7_truth_gates.csv")
    phase = phase_rows[0] if len(phase_rows) == 1 else {}
    for field in fields:
        phase_value = _boolean(phase, field)
        if phase_value is not None and values.get(field) is not phase_value:
            failures.append(f"{field}_mismatch_phase7")
    return [_check("status_reduction", relative, "publication_exact_reduction", rows, failures)]


def _audit_production_qualification_reducer(run_root: Path) -> list[AuditCheck]:
    relative = "reports/csv/production_qualification_gate.csv"
    header, rows = _read_rows(run_root / relative)
    failures: list[str] = []
    required_columns = {"Gate", "Required", "Pass", "Status", "EvidenceArtifact", "FailureReason"}
    missing = sorted(required_columns - set(header))
    if missing:
        failures.append("missing_columns=" + ",".join(missing))
    gate_names = [_text(row, "Gate") for row in rows]
    if tuple(gate_names) != PRODUCTION_GATE_ORDER:
        failures.append("gate_order_or_membership_mismatch")
    by_gate = {_text(row, "Gate"): row for row in rows}

    _result_header, result_rows = _read_rows(run_root / "reports/csv/result_status_summary.csv")
    result = result_rows[0] if len(result_rows) == 1 else {}
    functional = all(
        _boolean(result, name) is True
        for name in (
            "ResultOk", "ExecutionCompleted", "RuntimeTruthContractOk",
            "MandatorySubsystemsOk", "KpiConsistencyOk",
        )
    )
    scenario = _boolean(result, "ScenarioObjectiveOk") is True
    _wiring_header, wiring_rows = _read_rows(
        run_root / "reports/csv/phy_package_execution_evidence_gate.csv"
    )
    wiring = _all_required_gate_rows_pass(wiring_rows, "Required", "Pass")
    _phase_header, phase_rows = _read_rows(run_root / "reports/csv/phase7_truth_gates.csv")
    phase = phase_rows[0] if len(phase_rows) == 1 else {}
    phase7 = _boolean(phase, "Phase7Ok") is True
    statistical_fields = (
        "SeedHierarchyOk", "CampaignDesignOk", "CampaignCompletionOk",
        "MultiSeedDropStatisticsOk", "ConfidenceIntervalsOk",
        "SampleAdequacyOk", "SweepDataQualityOk",
    )
    statistical = all(_boolean(phase, name) is True for name in statistical_fields)
    resolved_config = _load_resolved_config(run_root)
    run_class = _text(phase, "RunClass").strip().lower()
    if not run_class:
        run_class = str(
            _nested_value(
                resolved_config,
                "validation.RunClass",
                _nested_value(resolved_config, "validation.run_class", ""),
            )
        ).strip().lower()
    campaign_run_classes = {
        "fixed_snr_sweep_lls", "ue_placement_geometry_lls", "hybrid_validation",
    }
    _stat_header, stat_rows = _read_rows(
        run_root / "reports/csv/statistical_qualification_gate.csv"
    )
    component_statistics_required = any(
        _boolean(row, "RequiredForStandardsClaim") is True for row in stat_rows
    )
    statistical_not_evaluated = (
        not statistical
        and run_class not in campaign_run_classes
        and not component_statistics_required
    )
    _publication_header, publication_rows = _read_rows(
        run_root / "reports/csv/publication_readiness_gate_summary.csv"
    )
    publication = (
        len(publication_rows) == 1
        and _boolean(publication_rows[0], "TerminalPublicationGatesOk") is True
    )
    frc_required_raw = _nested_value(
        resolved_config,
        "validation.independent_reference_qualification.required_for_production",
        None,
    )
    frc_required = True
    if isinstance(frc_required_raw, bool):
        frc_required = frc_required_raw
    elif isinstance(frc_required_raw, (int, float)):
        frc_required = bool(frc_required_raw)
    elif isinstance(frc_required_raw, str):
        token = frc_required_raw.strip().lower()
        if token in {"false", "0", "no", "off", "disabled"}:
            frc_required = False
        elif token in {"true", "1", "yes", "on", "enabled"}:
            frc_required = True
    frc_path = _io_path(run_root / "reports/csv/frc_reference_qualification.csv")
    frc = False
    if frc_path.is_file():
        _frc_header, frc_rows = _read_rows(
            run_root / "reports/csv/frc_reference_qualification.csv"
        )
        frc = bool(frc_rows) and all(
            _boolean(row, "QualificationOk", "ReferenceQualificationOk", "Pass") is True
            for row in frc_rows
        )
    frc_satisfied = (not frc_required) or frc
    reference_comparison_required = run_class in {
        "fixed_snr_sweep_lls", "hybrid_validation",
    }
    reference_comparison_value = (
        _boolean(publication_rows[0], "PublicationReferenceComparisonOk")
        if len(publication_rows) == 1
        else None
    )
    # Publication readiness represents a non-applicable comparison as a
    # satisfied roll-up.  The production evidence row has stricter
    # semantics: Pass means that an independent comparison actually ran.
    # Therefore a run class that does not require the comparison must remain
    # Pass=false/NOT_EVALUATED rather than inheriting the N/A roll-up.
    reference_comparison = (
        reference_comparison_required and reference_comparison_value is True
    )
    reference_comparison_satisfied = (
        not reference_comparison_required or reference_comparison
    )
    production = all((
        functional, scenario, wiring, phase7, statistical, frc_satisfied,
        reference_comparison_satisfied, publication,
    ))
    expected = {
        "FunctionalRun": functional,
        "ScenarioObjective": scenario,
        "RuntimeWiringCoverage": wiring,
        "Phase7NumericalValidation": phase7,
        "StatisticalQualification": statistical,
        "IndependentFRCQualification": frc,
        "IndependentReferenceComparison": reference_comparison,
        "TerminalPublicationEvidence": publication,
        "ProductionGrade": production,
    }
    for gate_name in PRODUCTION_GATE_ORDER:
        row = by_gate.get(gate_name, {})
        expected_required = not (
            (gate_name == "IndependentFRCQualification" and not frc_required)
            or (
                gate_name == "IndependentReferenceComparison"
                and not reference_comparison_required
            )
        )
        if _boolean(row, "Required") is not expected_required:
            failures.append(
                gate_name + f":Required_mismatch_expected_{expected_required}"
            )
        observed = _boolean(row, "Pass")
        if observed is not expected[gate_name]:
            failures.append(f"{gate_name}:Pass={observed};expected={expected[gate_name]}")
        status = _text(row, "Status").upper()
        if expected[gate_name]:
            expected_status = "PASS"
        elif gate_name == "StatisticalQualification" and statistical_not_evaluated:
            expected_status = "NOT_EVALUATED"
        elif gate_name == "IndependentFRCQualification" and (
            not frc_required or not frc_path.is_file()
        ):
            expected_status = "NOT_EVALUATED"
        elif gate_name == "IndependentReferenceComparison" and (
            not reference_comparison_required
            or reference_comparison_value is None
        ):
            expected_status = "NOT_EVALUATED"
        elif gate_name == "ProductionGrade" and not functional:
            expected_status = "NOT_EVALUATED"
        else:
            expected_status = "FAIL"
        if status != expected_status:
            failures.append(f"{gate_name}:Status={status};expected={expected_status}")
        reason = _text(row, "FailureReason")
        if expected[gate_name] and reason:
            failures.append(gate_name + ":passing_gate_has_failure_reason")
        if not expected[gate_name] and expected_required and not reason:
            failures.append(gate_name + ":failed_gate_reason_missing")
    return [_check("status_reduction", relative, "production_exact_reduction", rows, failures)]


def _audit_qualification_status_tables(
    run_root: Path, *, component_only: bool = False
) -> list[AuditCheck]:
    """Audit terminal reducers and their exact persisted evidence inputs."""

    checks: list[AuditCheck] = []
    checks.extend(_audit_phase7_reducer(run_root))
    if component_only:
        checks.append(_check(
            "cross_table_reconciliation", "reports/csv/phase7_truth_gates.csv",
            "full_link_reconciliation_not_applicable_to_component_runner", [], [],
            required=False, evaluated=False,
        ))
    else:
        checks.extend(_audit_reconciliation_reducers(run_root))
    checks.extend(_audit_publication_reducer(run_root))
    checks.extend(_audit_production_qualification_reducer(run_root))
    checks.extend(
        [
            _audit_gate_row_table(
                run_root, "reports/csv/kpi_consistency_gate.csv",
                key_column="GateName", required_column="Required", pass_column="Pass",
                evidence_column="EvidenceArtifact",
            ),
            _audit_gate_row_table(
                run_root, "reports/csv/phy_package_execution_evidence_gate.csv",
                key_column="Gate", required_column="Required", pass_column="Pass",
            ),
            _audit_gate_row_table(
                run_root, "reports/csv/scenario_objective_gates.csv",
                key_column="ObjectiveName", required_column="Mandatory", pass_column="Pass",
                evidence_column="SourceCsv", source_count_column="SourceRowCount",
            ),
            _audit_gate_row_table(
                run_root, "reports/csv/strict_anchor_acceptance_report.csv",
                key_column="GateName", required_column="Required", pass_column="Pass",
                evidence_column="EvidenceArtifacts",
            ),
            _audit_gate_row_table(
                run_root, "reports/csv/two_mode_acceptance_gates.csv",
                key_column="GateName", required_column="Required", status_column="Status",
                evidence_column="EvidencePath",
            ),
        ]
    )
    return checks


def _audit_beam_measurement_summaries(run_root: Path) -> list[AuditCheck]:
    relative = "reports/csv/live_beam_p1_acquisition_stats.csv"
    _, rows = _read_rows(run_root / relative)
    if not rows:
        return []  # Presence/enablement is checked by the domain-table audit.
    sources = {}
    for source in {row.get("TraceSource", "") for row in rows}:
        path = (run_root / source).resolve()
        if not source or not path.is_relative_to(run_root.resolve()):
            sources[source] = []
        else:
            _, sources[source] = _read_rows(path)
    return [_check("beam_measurement", relative, "measured_quality_and_physical_ssb_scope",
                   rows, reconcile_beam_summary(rows, sources))]


def _audit_applied_data_precoder(run_root: Path) -> list[AuditCheck]:
    weights_path = "beamforming/csv/applied_data_precoder_weights.csv"
    patterns_path = "beamforming/csv/applied_data_precoder_patterns.csv"
    wh, weights = _read_rows(run_root / weights_path)
    ph, patterns = _read_rows(run_root / patterns_path)
    if not (wh or ph):
        return []  # Required chart enablement is checked by chart contracts.
    failures = []
    try:
        validate_applied_beam_samples(weights, patterns)
    except (ValueError, KeyError, TypeError, OverflowError) as exc:
        failures.append(str(exc))
    return [_check("applied_data_precoder", path, "matrix_identity_and_angular_samples", rows, failures)
            for path, rows in ((weights_path, weights), (patterns_path, patterns))]


def audit_run(run_root: Path) -> dict[str, list[dict[str, Any]]]:
    run_root = run_root.resolve()
    resolved_primary_tables = primary_link_tables(run_root)
    summary_rel = "reports/csv/scenario_summary.csv"
    _summary_header, summary_rows = _read_rows(run_root / summary_rel)
    summary = summary_rows[0] if summary_rows else {}
    runner_profile = _text(summary, "RunnerProfile").strip().lower()
    if not runner_profile:
        runner_profile = str(_nested_value(
            _load_resolved_config(run_root), "scenario.runner_profile", ""
        )).strip().lower()
    component_only = runner_profile in COMPONENT_ONLY_RUNNER_PROFILES
    has_primary_run_evidence = bool(summary_rows) or any(
        _io_path(run_root / path).is_file() for path in resolved_primary_tables.values()
    )
    has_chart_contract = _io_path(
        run_root / "reports/csv/contract_plot_lineage.csv"
    ).is_file()
    has_frc_reference = _io_path(run_root / FRC_POINT_TABLE).is_file()
    has_applied_beam = any(_io_path(run_root / f"beamforming/csv/applied_data_precoder_{name}.csv").is_file()
                           for name in ("weights", "patterns"))
    control_paths = tuple(dict.fromkeys(
        CONTROL_TABLES + tuple(path.replace("air_interface/", "control/", 1) for path in CONTROL_TABLES)
    ))
    has_control_run_evidence = any(
        _io_path(run_root / path).is_file() for path in control_paths
    )
    if not (has_primary_run_evidence or has_control_run_evidence or has_chart_contract or has_frc_reference or has_applied_beam):
        return {
            "canonical_csv_semantic_audit": [],
            "chart_source_semantic_audit": [],
            "runtime_physics_reconciliation": [],
            "summary": [{
                "semantic_check_count": 0,
                "semantic_required_failure_count": 0,
                "chart_check_count": 0,
                "chart_required_failure_count": 0,
                "ok": True,
            }],
        }
    checks: list[AuditCheck] = []
    checks.extend(_audit_beam_measurement_summaries(run_root))
    checks.extend(_audit_applied_data_precoder(run_root))
    if has_frc_reference:
        checks.extend(_audit_frc_reference_outputs(run_root))
    if not (has_primary_run_evidence or has_control_run_evidence or has_chart_contract):
        required_failures = sum(
            check.required and (not check.evaluated or not check.passed)
            for check in checks
        )
        return {
            "canonical_csv_semantic_audit": [asdict(check) for check in checks],
            "chart_source_semantic_audit": [],
            "runtime_physics_reconciliation": [
                asdict(check)
                for check in checks
                if check.category == "frc_reference"
            ],
            "summary": [{
                "semantic_check_count": len(checks),
                "semantic_required_failure_count": required_failures,
                "chart_check_count": 0,
                "chart_required_failure_count": 0,
                "ok": required_failures == 0,
            }],
        }
    if has_control_run_evidence and not summary_rows:
        checks.append(_check(
            "run_lifecycle", summary_rel, "run_completion_summary_present",
            summary_rows, ["missing_run_summary_control_observations_not_final_qualification"],
        ))
    link_rows: dict[str, list[dict[str, str]]] = {}
    for direction, path in resolved_primary_tables.items():
        header, rows = _read_rows(run_root / path)
        link_rows[direction] = rows
        if component_only and not rows:
            checks.append(
                _check(
                    "primary_link",
                    path,
                    "not_applicable_to_component_runner",
                    rows,
                    [],
                    required=False,
                    evaluated=False,
                )
            )
            continue
        checks.extend(
            _audit_link_table(
                path,
                header,
                rows,
                direction,
                _expected_link_count(summary, direction),
            )
        )
    for path in control_paths:
        header, rows = _read_rows(run_root / path)
        if header or rows:
            checks.extend(_audit_control_table(path, header, rows))
    for path in DERIVED_LINK_TABLES:
        header, rows = _read_rows(run_root / path)
        if header or rows:
            checks.extend(_audit_derived_link_table(path, header, rows, link_rows))
    large_scale_path = "channel/csv/large_scale_parameters.csv"
    _large_scale_header, large_scale_rows = _read_rows(run_root / large_scale_path)
    if large_scale_rows:
        checks.extend(_audit_large_scale_power_table(large_scale_path, large_scale_rows))
    checks.extend(_audit_component_bler_outputs(run_root, link_rows, summary))
    checks.extend(_audit_fixed_snr_reporting_tables(run_root, link_rows))
    checks.extend(_audit_mimo_rank_layer_output(run_root, link_rows))
    checks.extend(_audit_mimo_companion_outputs(run_root, link_rows))
    checks.extend(_audit_harq_observation_tables(run_root, link_rows))
    checks.extend(_audit_dl_protocol_decisions(run_root, link_rows))
    checks.extend(_audit_kpi_delivery_outputs(
        run_root, link_rows, resolved_primary_tables
    ))
    checks.extend(_audit_kpi_reporting_tables(run_root))
    checks.extend(_audit_runtime_call_ledger(run_root, summary, link_rows))
    checks.extend(_audit_manifest_integrity(run_root))
    checks.extend(_audit_provenance_and_reference_tables(
        run_root, component_only=component_only,
    ))
    checks.extend(_audit_metric_output_tables(run_root))
    checks.extend(_audit_metric_coverage_table(run_root))
    checks.extend(_audit_domain_runtime_tables(run_root, summary))
    checks.extend(_audit_dynamic_tdd_runtime_channel_reciprocity(run_root, link_rows))
    checks.extend(_audit_prach_detection_trials(run_root))
    checks.extend(_audit_observed_re_allocation(run_root))
    checks.extend(_audit_final_tx_iq(run_root))
    checks.extend(
        _audit_reconciliation(
            summary_rel,
            summary,
            link_rows,
            primary_links_required=not component_only,
        )
    )
    checks.extend(_audit_status_reduction(run_root, summary_rel, summary))
    checks.extend(_audit_qualification_status_tables(
        run_root, component_only=component_only,
    ))
    chart_checks = _audit_chart_lineage(run_root)
    required_failures = sum(check.required and (not check.evaluated or not check.passed) for check in checks)
    chart_failures = sum(check.required and (not check.evaluated or not check.passed) for check in chart_checks)
    return {
        "canonical_csv_semantic_audit": [asdict(check) for check in checks],
        "chart_source_semantic_audit": [asdict(check) for check in chart_checks],
        "runtime_physics_reconciliation": [
            asdict(check)
            for check in checks
            if check.category in {"primary_link", "cross_table_reconciliation"}
        ],
        "summary": [
            {
                "semantic_check_count": len(checks),
                "semantic_required_failure_count": required_failures,
                "chart_check_count": len(chart_checks),
                "chart_required_failure_count": chart_failures,
                "ok": required_failures == 0 and chart_failures == 0,
            }
        ],
    }


def write_rows(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def write_audit(output_root: Path, audit: dict[str, list[dict[str, Any]]]) -> None:
    for name in (
        "canonical_csv_semantic_audit",
        "chart_source_semantic_audit",
        "runtime_physics_reconciliation",
        "summary",
    ):
        write_rows(output_root / f"{name}.csv", audit[name])
