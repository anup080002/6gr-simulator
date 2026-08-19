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
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable


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
DOMAIN_RUNTIME_PREFIXES = (
    "air_interface/csv/",
    "analytics/csv/",
    "channel/csv/",
    "component_anchors/protocol/protocol_stack/csv/",
    "configuration/csv/",
    "control/csv/",
    "rf/csv/",
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
}
IDENTITY_COLUMNS = (
    "RunID",
    "RunTag",
    "ScenarioID",
    "ConfigHash",
    "ExecutionID",
)
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


def _text(row: dict[str, str], *names: str) -> str:
    for name in names:
        value = str(row.get(name, "")).strip()
        if value and value.lower() not in {"nan", "+nan", "-nan", "<missing>", "null"}:
            return value
    return ""


def _number(row: dict[str, str], *names: str) -> float | None:
    text = _text(row, *names)
    try:
        value = float(text)
    except (TypeError, ValueError):
        return None
    return value if math.isfinite(value) else None


def _boolean(row: dict[str, str], *names: str) -> bool | None:
    value = _text(row, *names).lower()
    if value in {"1", "true", "yes", "pass", "passed", "ok"}:
        return True
    if value in {"0", "false", "no", "fail", "failed"}:
        return False
    return None


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
            [] if len(rows) == expected_count and expected_count > 0 else [f"expected={expected_count};actual={len(rows)}"],
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
        if tbs is None or tbs <= 0 or not _close(tbs, round(tbs), atol=0):
            transport_failures.append(prefix + ":invalid_tbs")
        if not _close(offered, tbs, atol=0):
            transport_failures.append(prefix + ":offered_bits_not_tbs")
        if compared is None or compared <= 0 or errors is None or errors < 0 or errors > compared:
            transport_failures.append(prefix + ":invalid_bit_error_counts")
        elif not _close(ber, errors / compared, atol=1e-12, rtol=1e-9):
            transport_failures.append(prefix + ":ber_arithmetic_mismatch")
        if crc is True and not _close(good, offered, atol=0):
            transport_failures.append(prefix + ":crc_pass_good_bits_mismatch")
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
        strict_evidence = (
            _boolean(row, "StrictReceiverEvidenceOk")
            if fixed_link_trial
            else _boolean(row, "StrictOk")
        )
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
    return checks


def _raw_rows_for_scope(
    link_rows: dict[str, list[dict[str, str]]], direction: str, ue_value: str
) -> list[dict[str, str]]:
    rows = link_rows.get(direction.upper(), [])
    ue = str(ue_value or "").strip().lower()
    if ue in {"", "all", "nan", "n/a"}:
        return rows
    return [
        row
        for row in rows
        if _text(row, "UEIndex", "UEID").strip().lower() == ue
    ]


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
        row for direction_rows in link_rows.values() for row in direction_rows
    ]
    fixed_link_without_geometry = bool(raw_link_population) and all(
        _boolean(row, "FixedLinkCampaign") is True
        and _number(row, "PropagationDistance_m") is None
        for row in raw_link_population
    )
    if not rows and name == "distance_vs_sinr.csv" and fixed_link_without_geometry:
        return [
            _check(
                "derived_link",
                path,
                "not_applicable_fixed_link_without_geometry",
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
        if "Goodput_Mbps_mean" in header and "OfferedThroughput_Mbps_mean" in header:
            if (_number(row, "Goodput_Mbps_mean") or 0.0) > (_number(row, "OfferedThroughput_Mbps_mean") or 0.0) + 1e-9:
                range_failures.append(prefix + ":mean_goodput_exceeds_offered")

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
            raw = _raw_rows_for_scope(link_rows, _text(row, "Direction"), _text(row, "UEIndex"))
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
        if len(rows) != sum(len(value) for value in link_rows.values()):
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
        empty_means_no_event = relative in {
            "channel/csv/trajectory_constraint_conflicts.csv",
            "reports/csv/live_cell_reselection_events.csv",
        }
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
        for index, row in enumerate(rows, start=1):
            prefix = f"row={index}"
            if "ScenarioID" in header:
                observed = _text(row, "ScenarioID")
                if not observed or (expected_scenario and observed != expected_scenario):
                    identity_failures.append(prefix + ":ScenarioID_mismatch_or_missing")
            if "ConfigHash" in header:
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

    if relative == "reports/csv/live_beam_p1_acquisition_stats.csv":
        enabled = _truthy_config(
            resolved_config,
            "mimo_and_beam_management.beam_sweeping",
            "system.beam.enable",
            "reference_signals.ssb_enabled",
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
        enabled = run_class in {
            "geometry_based_lls",
            "geometry_based_link_level",
            "geometry_mobility_lls",
        }
        return enabled, enabled
    if relative == "reports/csv/live_user_performance_snapshot.csv":
        has_link_rows = any(
            bool(_read_rows(run_root / path)[1])
            for path in primary_link_tables(run_root).values()
        )
        return has_link_rows, has_link_rows
    return True, True


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
                        if len(unique_x) < 2:
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
        checks.append(
            _check(
                "cross_table_reconciliation",
                summary_path,
                f"{direction.lower()}_summary_trial_count",
                rows,
                [] if expected == len(rows) else [f"summary={expected};table={len(rows)}"],
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


def audit_run(run_root: Path) -> dict[str, list[dict[str, Any]]]:
    run_root = run_root.resolve()
    resolved_primary_tables = primary_link_tables(run_root)
    summary_rel = "reports/csv/scenario_summary.csv"
    _summary_header, summary_rows = _read_rows(run_root / summary_rel)
    summary = summary_rows[0] if summary_rows else {}
    runner_profile = _text(summary, "RunnerProfile").strip().lower()
    component_only = runner_profile in COMPONENT_ONLY_RUNNER_PROFILES
    has_primary_run_evidence = bool(summary_rows) or any(
        _io_path(run_root / path).is_file() for path in resolved_primary_tables.values()
    )
    has_chart_contract = _io_path(
        run_root / "reports/csv/contract_plot_lineage.csv"
    ).is_file()
    if not has_primary_run_evidence and not has_chart_contract:
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
    for path in CONTROL_TABLES:
        header, rows = _read_rows(run_root / path)
        if header or rows:
            checks.extend(_audit_control_table(path, header, rows))
    for path in DERIVED_LINK_TABLES:
        header, rows = _read_rows(run_root / path)
        if header or rows:
            checks.extend(_audit_derived_link_table(path, header, rows, link_rows))
    checks.extend(_audit_runtime_call_ledger(run_root, summary, link_rows))
    checks.extend(_audit_manifest_integrity(run_root))
    checks.extend(_audit_domain_runtime_tables(run_root, summary))
    checks.extend(
        _audit_reconciliation(
            summary_rel,
            summary,
            link_rows,
            primary_links_required=not component_only,
        )
    )
    checks.extend(_audit_status_reduction(run_root, summary_rel, summary))
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
