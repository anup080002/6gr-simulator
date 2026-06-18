#!/usr/bin/env python3
"""Audit expected block I/O evidence for a config-driven LLS run.

This is a measurement-first audit. It does not convert missing values into
success labels; it reports missing artifacts, missing columns, and empty or
non-finite measurement columns so the underlying block can be repaired.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


SPEC_REFS = {
    "38.211": "https://www.3gpp.org/ftp/Specs/archive/38_series/38.211/",
    "38.212": "https://www.3gpp.org/ftp/Specs/archive/38_series/38.212/",
    "38.213": "https://www.3gpp.org/ftp/Specs/archive/38_series/38.213/",
    "38.214": "https://www.3gpp.org/ftp/Specs/archive/38_series/38.214/",
    "38.215": "https://www.3gpp.org/ftp/Specs/archive/38_series/38.215/",
    "38.321": "https://www.3gpp.org/ftp/Specs/archive/38_series/38.321/",
    "38.331": "https://www.3gpp.org/ftp/Specs/archive/38_series/38.331/",
    "38.901": "https://www.3gpp.org/ftp/Specs/archive/38_series/38.901/",
}


@dataclass(frozen=True)
class ArtifactExpectation:
    path: str
    required_columns: tuple[str, ...] = ()
    finite_columns: tuple[str, ...] = ()


@dataclass(frozen=True)
class BlockExpectation:
    block_id: str
    display_name: str
    enabled_paths: tuple[str, ...]
    spec_refs: tuple[str, ...]
    expected_inputs: tuple[str, ...]
    expected_outputs: tuple[str, ...]
    code_refs: tuple[str, ...]
    code_patterns: tuple[str, ...]
    log_patterns: tuple[str, ...] = ()
    artifacts: tuple[ArtifactExpectation, ...] = ()
    fix_hint: str = ""


BLOCKS: tuple[BlockExpectation, ...] = (
    BlockExpectation(
        "runtime_monitoring",
        "Runtime monitor and live progress",
        ("scenario.runner_profile",),
        (),
        ("run folder", "slot heartbeat from SystemLevelRunner", "MATLAB process id"),
        ("RUNNING.status.json", "reports/csv/live_stage_progress.csv"),
        ("+sixgr/+system/SystemLevelRunner.m", "scripts/run_monitored_lls_scenario.ps1"),
        ("localEmitLiveProgress", "localEmitFilesystemLiveProgress"),
        ("system_level_lls_slot_progress", "replay_progress"),
        (
            ArtifactExpectation("RUNNING.status.json"),
            ArtifactExpectation(
                "reports/csv/live_stage_progress.csv",
                ("StageName", "CurrentSlot", "TotalSlots", "RunCompletion", "ElapsedSeconds"),
                ("CurrentSlot", "TotalSlots", "RunCompletion", "ElapsedSeconds"),
            ),
        ),
        "Write filesystem live-progress from the runner heartbeat, not only DB/log output.",
    ),
    BlockExpectation(
        "provenance_config",
        "Resolved config and provenance",
        ("meta.scenario_id",),
        (),
        ("input YAML", "inherited scenario chain", "run tag"),
        ("resolved JSON/YAML", "source-chain CSV"),
        ("+sixgr/+lls6g/+runners/runSingle.m", "+sixgr/+lls6g/buildInternalConfig.m"),
        ("scenario_config_resolved.json", "scenario_config_resolved.yaml"),
        (),
        (
            ArtifactExpectation("meta/scenario_config_resolved.json"),
            ArtifactExpectation("meta/scenario_config_resolved.yaml"),
            ArtifactExpectation("meta/scenario_source_chain.csv"),
        ),
        "Ensure snapshots are written before long PHY execution starts.",
    ),
    BlockExpectation(
        "deployment_channel_rf",
        "Deployment, pathloss, fading, and RF impairments",
        ("channels.model_type", "channel_model.model"),
        ("38.901", "38.211", "38.215"),
        ("carrier frequency", "UE/BS geometry", "TDL/CDL/UMa profile", "Doppler", "RF impairment config"),
        ("large-scale state", "pathloss/shadow/O2I", "applied timing/CFO/phase-noise evidence"),
        (
            "+sixgr/+channel/TR38901Plus.m",
            "+sixgr/+link/applyWaveformImpairments.m",
            "+sixgr/+system/+waveform/replayGrant.m",
        ),
        ("TR38901Plus", "applyWaveformImpairments", "EstimatedCFO_Hz"),
        ("TR38901Plus", "large_scale_ready"),
        (
            ArtifactExpectation("system/csv/system_interference_detail.csv"),
            ArtifactExpectation(
                "packet_flow/csv/live_dl_scheduler_grants.csv",
                ("AppliedPathloss_dB", "AppliedShadowFading_dB", "TimingEstimateUsed", "EstimatedCFO_Hz"),
            ),
            ArtifactExpectation(
                "packet_flow/csv/live_ul_scheduler_grants.csv",
                ("AppliedPathloss_dB", "AppliedShadowFading_dB", "TimingEstimateUsed", "EstimatedCFO_Hz"),
            ),
        ),
        "If CFO/timing are configured, make the waveform impairment and estimator path produce measured estimates.",
    ),
    BlockExpectation(
        "mac_scheduler_link_adaptation",
        "MAC scheduler and link adaptation",
        ("scheduler.type", "link_adaptation.fixed_or_amc"),
        ("38.214", "38.321"),
        ("UE backlog", "CQI/RI/PMI feedback or bootstrap policy", "PRB budget", "HARQ state"),
        ("real grants", "MCS", "TBS from nrTBS", "HARQ process/RV/NDI"),
        (
            "+sixgr/+l2/+mac/SchedulerBase.m",
            "+sixgr/+l2/+mac/SchedulerPF.m",
            "+sixgr/+l2/+mac/HARQEntity.m",
            "+sixgr/+system/SystemLevelRunner.m",
            "+sixgr/+util/resolveGrantTBSBits.m",
        ),
        ("nrTBS", "selectAMC", "HarqID"),
        ("SchedulerPF", "scheduler_ready"),
        (
            ArtifactExpectation(
                "packet_flow/csv/live_dl_scheduler_grants.csv",
                ("Slot", "UEId", "MCSIndex", "Modulation", "TBSBits", "HarqID", "RV", "NDI"),
                ("Slot", "UEId", "MCSIndex", "TBSBits"),
            ),
            ArtifactExpectation(
                "packet_flow/csv/live_ul_scheduler_grants.csv",
                ("Slot", "UEId", "MCSIndex", "Modulation", "TBSBits", "HarqID", "RV", "NDI"),
                ("Slot", "UEId", "MCSIndex", "TBSBits"),
            ),
        ),
        "Repair missing grant fields from real allocations; do not reconstruct TBS from served bits.",
    ),
    BlockExpectation(
        "dl_pdsch_chain",
        "DL PDSCH TX/channel/RX chain",
        ("pdsch.enabled",),
        ("38.211", "38.212", "38.214"),
        ("carrier", "PDSCH PRB/symbol allocation", "TB bits", "DMRS", "precoder", "channel output"),
        ("post-equalization SINR", "LLRs", "DLSCH CRC", "raw BER/BLER", "decoder iterations"),
        (
            "+sixgr/+phy/+dl/PDSCH_Tx.m",
            "+sixgr/+phy/+dl/PDSCH_Rx.m",
            "+sixgr/+pdsch/DLSCHDecoder.m",
            "+sixgr/+phy/+rx/equalizeMMSE.m",
            "+sixgr/+phy/+phycode/rateRecoverLDPC.m",
            "+sixgr/+phy/+phycode/ldpcDecode.m",
            "+sixgr/+phy/+tb/checkCRC.m",
            "+sixgr/+system/+waveform/replayGrant.m",
        ),
        (
            "nrPDSCH",
            "nrPDSCHDecode",
            "rateRecoverLDPC",
            "ldpcDecode",
            "checkCRC",
            "nrChannelEstimate",
            "nrEqualizeMMSE",
        ),
        ("dl_replay_progress",),
        (
            ArtifactExpectation(
                "packet_flow/csv/live_dl_scheduler_grants.csv",
                (
                    "PostEqSINR_dB",
                    "DecoderIterations",
                    "ChannelEstimateAvailable",
                    "EqualizationAvailable",
                    "DecodeAttempted",
                    "DecodeAvailable",
                    "LLRFinite",
                ),
                ("PostEqSINR_dB", "DecoderIterations"),
            ),
            ArtifactExpectation(
                "air_interface/csv/dl_pdsch_trials.csv",
                ("MeasuredTrialSINR_dB", "BitErrors", "BitsCompared", "TBCrcPass"),
                ("MeasuredTrialSINR_dB", "BitsCompared"),
            ),
        ),
        "Trace the missing DL measurement to TX, channel estimate, equalizer, demapper, or DLSCH decode stage.",
    ),
    BlockExpectation(
        "ul_pusch_chain",
        "UL PUSCH TX/channel/RX chain",
        ("pusch.enabled",),
        ("38.211", "38.212", "38.214"),
        ("carrier", "PUSCH PRB/symbol allocation", "ULSCH TB bits", "DMRS/SRS state", "channel output"),
        ("post-equalization SINR", "LLRs", "ULSCH CRC", "raw BER/BLER", "decoder iterations"),
        (
            "+sixgr/+phy/+ul/PUSCH_Tx.m",
            "+sixgr/+phy/+ul/PUSCH_Rx.m",
            "+sixgr/+phy/+rx/equalizeMMSE.m",
            "+sixgr/+phy/+phycode/rateRecoverLDPC.m",
            "+sixgr/+phy/+phycode/ldpcDecode.m",
            "+sixgr/+phy/+tb/checkCRC.m",
            "+sixgr/+system/+waveform/replayGrant.m",
        ),
        (
            "nrPUSCH",
            "nrPUSCHDecode",
            "rateRecoverLDPC",
            "ldpcDecode",
            "checkCRC",
            "nrChannelEstimate",
            "nrEqualizeMMSE",
        ),
        ("ul_replay_progress",),
        (
            ArtifactExpectation(
                "packet_flow/csv/live_ul_scheduler_grants.csv",
                (
                    "PostEqSINR_dB",
                    "DecoderIterations",
                    "ChannelEstimateAvailable",
                    "EqualizationAvailable",
                    "DecodeAttempted",
                    "DecodeAvailable",
                    "LLRFinite",
                ),
                ("PostEqSINR_dB", "DecoderIterations"),
            ),
            ArtifactExpectation(
                "air_interface/csv/ul_pusch_trials.csv",
                ("MeasuredTrialSINR_dB", "BitErrors", "BitsCompared", "TBCrcPass"),
                ("MeasuredTrialSINR_dB", "BitsCompared"),
            ),
        ),
        "Trace the missing UL measurement to PUSCH DMRS, channel estimator, equalizer, demapper, or ULSCH decode stage.",
    ),
    BlockExpectation(
        "control_pdcch_pucch",
        "DL/UL control channels PDCCH and PUCCH",
        ("pdcch.enabled", "pucch.enabled", "control.pdcch_enabled", "control.pucch_enabled"),
        ("38.211", "38.212", "38.213"),
        ("CORESET", "search space", "DCI payload", "PUCCH resource", "HARQ/CSI/SR payload"),
        ("blind decode result", "DCI CRC", "PUCCH UCI bits", "detection metrics"),
        (
            "+sixgr/+phy/+pdcch/runStrictPDCCHValidation.m",
            "+sixgr/+phy/+pdcch/blindDecodePDCCH.m",
            "+sixgr/+phy/+ul/PUCCH_Tx.m",
            "+sixgr/+phy/+ul/PUCCH_Rx.m",
        ),
        ("nrPDCCH", "nrPDCCHDecode", "nrPUCCH", "nrPUCCHDecode"),
        (),
        (
            ArtifactExpectation("control/csv/pdcch_trials.csv"),
            ArtifactExpectation("control/csv/pucch_trials.csv"),
        ),
        "Run focused PDCCH/PUCCH block validation if these trial artifacts are absent or empty.",
    ),
    BlockExpectation(
        "broadcast_initial_access",
        "SSB, PBCH, MIB, SIB1, and initial access",
        ("sib1_and_initial_access.sib1_required", "reference_signals.ssb_enabled", "reference_signals.pbch_enabled"),
        ("38.211", "38.212", "38.213", "38.331"),
        ("SSB burst", "PSS/SSS/PBCH DMRS", "MIB", "CORESET0/SearchSpace0", "SI-RNTI PDCCH", "SIB1 PDSCH"),
        ("cell ID", "timing", "PBCH decode", "ASN.1 SIB1 roundtrip", "SIB1 PDSCH CRC"),
        (
            "+sixgr/+phy/+broadcast/generateSSB_MIB_SIB1_Waveform.m",
            "+sixgr/+phy/+broadcast/recoverSIB1FromWaveform.m",
            "+sixgr/+link/runCellSearch_MIB_SIB1.m",
            "+sixgr/+phy/+sync/cellSearch.m",
            "+sixgr/+phy/+sync/timingEstimate.m",
            "+sixgr/+phy/+dl/PBCH_Recovery.m",
        ),
        ("nrPSS", "nrSSS", "nrPBCHDecode", "nrPDCCH", "nrPDSCH"),
        (),
        (
            ArtifactExpectation("air_interface/csv/cell_search_mib_sib1_trials.csv"),
            ArtifactExpectation("control/csv/sib1_trials.csv"),
        ),
        "Separate SSB/PBCH/SIB1 waveform recovery from scenario labels; verify decoded MIB/SIB1 fields.",
    ),
    BlockExpectation(
        "random_access_rach",
        "PRACH and four-step RACH",
        ("prach.enabled", "random_access.enabled", "random_access_evidence.four_step_ra_required"),
        ("38.211", "38.213", "38.321"),
        ("PRACH config index", "root sequence", "preamble", "RO mapping", "RAR grant", "Msg3 PUSCH"),
        ("preamble detection", "timing advance", "RAR MAC CE", "Msg3 decode", "contention resolution"),
        (
            "+sixgr/+phy/+prach/generatePRACHWaveform.m",
            "+sixgr/+phy/+prach/detectPRACHWaveform.m",
            "+sixgr/+phy/+ul/PRACH_Tx.m",
            "+sixgr/+phy/+ul/PRACH_Rx.m",
            "+sixgr/+link/runPRACHDetection.m",
            "+sixgr/+phy/+ra/runFourStepRA.m",
        ),
        ("nrPRACH", "nrPRACHDetect", "nrPDCCH", "nrPUSCH"),
        (),
        (
            ArtifactExpectation("air_interface/csv/prach_trials.csv"),
            ArtifactExpectation("control/csv/prach_trials.csv"),
            ArtifactExpectation("control/csv/random_access_trials.csv"),
        ),
        "Implement/fix missing Msg1-Msg4 evidence instead of counting PRACH config rows as RACH success.",
    ),
    BlockExpectation(
        "reference_signals_csi_srs_trs",
        "DMRS, CSI-RS, SRS, TRS, and measurements",
        (
            "reference_signals.csi_rs_enabled",
            "reference_signals.srs_enabled",
            "reference_signals.trs_enabled",
            "csi_acquisition_and_reporting.dl_csi_enabled",
            "csi_acquisition_and_reporting.ul_csi_enabled",
        ),
        ("38.211", "38.214", "38.215"),
        ("RS resource config", "RS symbols/indices", "received grid", "measurement filter/timeline"),
        ("RSRP/SINR", "RI/PMI/CQI", "SRS channel estimate", "TRS timing/frequency tracking"),
        (
            "+sixgr/+phy/+srs/estimateULChannelFromSRS.m",
            "+sixgr/+phy/+trs/estimateTRSChannel.m",
            "+sixgr/+phy/+dl/CSI_Feedback.m",
            "+sixgr/+phy/+ul/SRS_Tx.m",
            "+sixgr/+phy/+ul/SRS_Rx.m",
            "+sixgr/+phy/+refsig/csirs.m",
            "+sixgr/+phy/+dl/+CSI_Feedback/estimateRI.m",
        ),
        ("nrChannelEstimate", "nrSRS", "nrCSIRS", "estimateRI"),
        (),
        (
            ArtifactExpectation("air_interface/csv/srs_trials.csv"),
            ArtifactExpectation("air_interface/csv/trs_trials.csv"),
            ArtifactExpectation("reports/csv/csi_feedback_trace.csv"),
        ),
        "Tie CQI/PMI/RI and SRS/TRS measurements to the scheduler instead of using bootstrap indefinitely.",
    ),
)


FALSE_TOKENS = {"", "0", "false", "none", "disabled", "off", "no", "nan", "null"}


def nested_get(data: dict[str, Any], path: str) -> Any:
    cur: Any = data
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def is_enabled(data: dict[str, Any], paths: tuple[str, ...]) -> bool:
    for path in paths:
        value = nested_get(data, path)
        if isinstance(value, bool):
            if value:
                return True
            continue
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            if math.isfinite(float(value)) and float(value) != 0.0:
                return True
            continue
        if isinstance(value, str):
            if value.strip().lower() not in FALSE_TOKENS:
                return True
            continue
        if value not in (None, [], {}, ()):
            return True
    return False


def read_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return ""


def is_finite_text(value: str) -> bool:
    text = str(value).strip()
    if not text or text.lower() in {"nan", "inf", "-inf", "missing", "<missing>"}:
        return False
    try:
        return math.isfinite(float(text))
    except Exception:
        return False


def csv_artifact_stats(path: Path, required: tuple[str, ...], finite: tuple[str, ...]) -> dict[str, Any]:
    stats: dict[str, Any] = {
        "exists": path.is_file(),
        "rows": 0,
        "missing_columns": list(required),
        "empty_measurement_columns": list(finite),
        "nonfinite_measurement_columns": [],
    }
    if not path.is_file():
        return stats
    try:
        with path.open("r", newline="", encoding="utf-8-sig", errors="replace") as handle:
            reader = csv.DictReader(handle)
            columns = list(reader.fieldnames or [])
            rows = list(reader)
    except Exception as exc:
        stats["read_error"] = str(exc)
        return stats
    stats["rows"] = len(rows)
    stats["missing_columns"] = [col for col in required if col not in columns]
    empty_cols: list[str] = []
    nonfinite_cols: list[str] = []
    for col in finite:
        if col not in columns:
            continue
        values = [row.get(col, "") for row in rows]
        finite_count = sum(1 for value in values if is_finite_text(value))
        nonempty_count = sum(1 for value in values if str(value).strip() != "")
        if len(rows) > 0 and finite_count == 0:
            empty_cols.append(col)
        elif nonempty_count > finite_count:
            nonfinite_cols.append(f"{col}:{nonempty_count - finite_count}/{len(rows)}")
    stats["empty_measurement_columns"] = empty_cols
    stats["nonfinite_measurement_columns"] = nonfinite_cols
    return stats


def rel_exists(repo: Path, rel: str) -> bool:
    return (repo / rel.replace("/", "\\")).is_file()


def code_pattern_check(repo: Path, rels: tuple[str, ...], patterns: tuple[str, ...]) -> tuple[list[str], list[str]]:
    combined = "\n".join(read_text(repo / rel.replace("/", "\\")) for rel in rels)
    missing_files = [rel for rel in rels if not rel_exists(repo, rel)]
    missing_patterns = [pat for pat in patterns if pat not in combined]
    return missing_files, missing_patterns


def discover_log_text(repo: Path, run_folder: Path, explicit_log: str | None) -> str:
    if explicit_log:
        return read_text(Path(explicit_log))
    log_paths = [run_folder / "logs" / "matlab_diary.log"]
    leaf = run_folder.name
    log_paths.append(repo / "logs" / "monitored_lls_runs" / f"{leaf}.log")
    log_paths.append(repo / "logs" / "codex_rootcause_runs" / f"{leaf}_driver.out.log")
    return "\n".join(read_text(path) for path in log_paths if path.is_file())


def run_audit(repo: Path, run_folder: Path, log_text: str) -> list[dict[str, str]]:
    config = read_json(run_folder / "meta" / "scenario_config_resolved.json")
    rows: list[dict[str, str]] = []
    for block in BLOCKS:
        enabled = is_enabled(config, block.enabled_paths)
        missing_code_files, missing_code_patterns = code_pattern_check(repo, block.code_refs, block.code_patterns)
        log_hits = [pat for pat in block.log_patterns if re.search(re.escape(pat), log_text, flags=re.IGNORECASE)]

        missing_artifacts: list[str] = []
        missing_columns: list[str] = []
        empty_measurements: list[str] = []
        nonfinite_measurements: list[str] = []
        row_counts: list[str] = []
        for artifact in block.artifacts:
            artifact_path = run_folder / artifact.path.replace("/", "\\")
            stats = csv_artifact_stats(artifact_path, artifact.required_columns, artifact.finite_columns)
            if not stats["exists"]:
                missing_artifacts.append(artifact.path)
                continue
            row_counts.append(f"{artifact.path}:{stats['rows']}")
            missing_columns.extend(f"{artifact.path}:{col}" for col in stats["missing_columns"])
            empty_measurements.extend(f"{artifact.path}:{col}" for col in stats["empty_measurement_columns"])
            nonfinite_measurements.extend(f"{artifact.path}:{col}" for col in stats["nonfinite_measurement_columns"])

        finding_parts: list[str] = []
        if enabled and missing_code_files:
            finding_parts.append("missing_code_files")
        if enabled and missing_code_patterns:
            finding_parts.append("missing_expected_code_primitives")
        if enabled and missing_artifacts:
            finding_parts.append("missing_runtime_artifacts")
        if enabled and missing_columns:
            finding_parts.append("missing_runtime_columns")
        if enabled and empty_measurements:
            finding_parts.append("empty_measurement_columns")
        if enabled and nonfinite_measurements:
            finding_parts.append("nonfinite_measurement_values")
        if enabled and not log_hits and block.log_patterns:
            finding_parts.append("missing_runtime_log_evidence")
        if not enabled:
            finding_parts.append("not_enabled_by_resolved_config")
        if not finding_parts:
            finding_parts.append("evidence_present_for_checked_surface")

        rows.append(
            {
                "BlockId": block.block_id,
                "BlockName": block.display_name,
                "EnabledByResolvedConfig": str(enabled),
                "SpecReferences": ";".join(f"{ref}:{SPEC_REFS.get(ref, ref)}" for ref in block.spec_refs),
                "ExpectedInputs": ";".join(block.expected_inputs),
                "ExpectedOutputs": ";".join(block.expected_outputs),
                "CodeRefs": ";".join(block.code_refs),
                "MissingCodeFiles": ";".join(missing_code_files),
                "MissingCodePatterns": ";".join(missing_code_patterns),
                "LogEvidencePatternsFound": ";".join(log_hits),
                "RuntimeArtifactRows": ";".join(row_counts),
                "MissingArtifacts": ";".join(missing_artifacts),
                "MissingColumns": ";".join(missing_columns),
                "EmptyMeasurementColumns": ";".join(empty_measurements),
                "NonFiniteMeasurementColumns": ";".join(nonfinite_measurements),
                "Finding": ";".join(finding_parts),
                "RecommendedEngineeringFix": block.fix_hint,
            }
        )
    return rows


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=".")
    parser.add_argument("--run-folder", required=True)
    parser.add_argument("--log", default=None)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    run_folder = Path(args.run_folder).resolve()
    log_text = discover_log_text(repo, run_folder, args.log)
    rows = run_audit(repo, run_folder, log_text)

    out_path = Path(args.out).resolve() if args.out else run_folder / "audit" / "block_io_audit.csv"
    write_csv(out_path, rows)

    problems = [
        row for row in rows
        if row["EnabledByResolvedConfig"] == "True"
        and row["Finding"] != "evidence_present_for_checked_surface"
    ]
    print(f"block_io_audit={out_path}")
    print(f"enabled_blocks_with_findings={len(problems)}")
    for row in problems:
        print(f"{row['BlockId']}: {row['Finding']}")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
