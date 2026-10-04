"""SLS views read persisted network evidence, never LLS waveform substitutes."""
from __future__ import annotations

import csv
import hashlib
import json
import math
from collections import deque
from pathlib import Path


def native_catalog_defaults(node: dict) -> dict:
    """Expose static MATLAB catalog defaults without inventing dynamic values."""
    result = {}
    for key, value in node.items():
        if not isinstance(value, dict):
            continue
        if "value_type" in value:
            if "default" in value:
                result[key] = value["default"]
        else:
            child = native_catalog_defaults(value)
            if child:
                result[key] = child
    return result


def launch_readiness(native: dict) -> tuple[bool, str]:
    backend = native.get("system", {}).get("phyBackend")
    if native.get("run", {}).get("mode") != "system" or native.get("run", {}).get("useConfigFragments") is not False:
        return False, "SLS requires run.mode=system and run.useConfigFragments=false."
    if backend not in {"waveform", "calibrated_link_abstraction"}:
        return False, "Select system.phyBackend: waveform or calibrated_link_abstraction."
    calibration = native.get("system", {}).get("linkAbstraction", {})
    if calibration.get("allowDevelopmentFixtures", False):
        return False, "Test-only BLER calibration is not permitted in the public SLS runner."
    if backend == "calibrated_link_abstraction" and (not calibration.get("calibrationFile") or len(str(calibration.get("calibrationSHA256", ""))) != 64):
        return False, "Bind qualified calibrationFile and its 64-character SHA256; no default BLER curve is supplied."
    return True, "MATLAB verifies native configuration, backend, calibration content and coverage before execution."


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def read_rows(path: Path, limit: int = 100, *, latest: bool = False) -> list[dict]:
    if limit <= 0:
        return []
    try:
        with path.open(encoding="utf-8-sig", newline="") as handle:
            # Parse complete CSV records (including quoted newlines). A
            # byte-tail/splitlines shortcut can corrupt receiver evidence.
            rows = deque(maxlen=limit) if latest else []
            for row in csv.DictReader(handle):
                if any(str(value or "").strip() for value in row.values()):
                    rows.append(row)
                if not latest and len(rows) >= limit:
                    break
            return list(rows)
    except (OSError, csv.Error, UnicodeError):
        return []


def is_sls_run(row: dict) -> bool:
    return row.get("execution_mode") == "SLS" or row.get("bucket") == "sls"


def chartable_csv(path: Path) -> bool:
    """A header or file length alone is never plotted evidence."""
    for row in read_rows(path, limit=64):
        finite_columns = 0
        for value in row.values():
            try:
                finite_columns += int(math.isfinite(float(value)))
            except (TypeError, ValueError):
                pass
        if finite_columns >= 2:
            return True
    return False


def run_row(folder: Path, run_id: int) -> dict | None:
    receipt = read_json(folder / "meta/simulation_run.json")
    if receipt.get("Schema") != "sixgr.simulation_run/v1" or receipt.get("ExecutionMode") != "SLS":
        return None
    config = read_json(folder / "meta/scenario_config_resolved.json")
    progress = read_json(folder / "RUNNING.status.json")
    status = receipt.get("Status", "unknown")
    updated = receipt.get("UpdatedUTC", "")
    if status in {"running", "initializing"}:
        updated = progress.get("LastUpdateAt") or updated
    return {
        "run_id": run_id, "run_uuid": f"filesystem-{run_id}",
        "scenario_id": receipt.get("ScenarioID"), "run_tag": receipt.get("RunTag"),
        "run_folder": str(folder.absolute()), "bucket": "sls", "execution_mode": "SLS",
        "profile_name": "system_level", "backend": receipt.get("ExecutionBackend"),
        "status_text": status, "status_json": json.dumps(receipt),
        "config_json": json.dumps(config), "created_utc": receipt.get("CreatedUTC", updated),
        "updated_utc": updated, "primary_study_accepted": receipt.get("PrimaryStudyAccepted", False),
    }


def live_payload(row: dict, artifacts: list[dict]) -> dict:
    folder = Path(row["run_folder"])
    receipt = read_json(folder / "meta/simulation_run.json")
    if row.get("observed_process_state"):
        receipt["PersistedStatus"] = receipt.get("Status")
        receipt["Status"] = row["status_text"]
        receipt["ObservedProcessState"] = row["observed_process_state"]
    progress = read_json(folder / "RUNNING.status.json")
    # A prior heartbeat cannot turn a terminal failure/completion back into running.
    progress["ExecutionStatus"] = receipt.get("Status", "unknown")
    if receipt.get("Status") in {"completed", "failed", "process_unobserved"}:
        progress["LastRecordedStage"] = progress.get("CurrentStage")
        progress["CurrentStage"] = receipt["Status"]
        progress["RunCompleted"] = receipt["Status"] != "process_unobserved"
        progress["ResultOk"] = receipt.get("ExecutionOk", False)
    tables = [a for a in artifacts if str(a.get("logical_path", "")).endswith(".csv")]
    images = [a for a in artifacts if str(a.get("logical_path", "")).lower().endswith((".png", ".svg"))]
    selected = {
        "Network KPIs": "summaries/system_kpi_summary.csv",
        "UE metrics": "summaries/system_ue_summary.csv",
        "Load": "traces/system_cell_load.csv",
        "File completion": "traces/ftp3_user_metrics.csv",
        "UCI obligations (modeled control)": "csv/system_dynamic_pucch_obligations.csv",
        "Native PUCCH transmissions (TX audit, not reception)": "csv/system_native_pucch_emission_audit.csv",
        "UCI transport completions (ideal delayed control)": "csv/system_dynamic_uci_completions.csv",
        "HARQ decisions (modeled, not waveform CRC)": "csv/system_modeled_harq_payload_decisions.csv",
        "CSI (modeled feedback)": "csv/system_modeled_dl_csi.csv",
        "SRS (modeled feedback)": "csv/system_modeled_spatial_feedback.csv",
        "Network interference (modeled, not RF measurement)": "csv/system_network_spatial_evidence.csv",
        "Feedback capture / completion clock": "csv/system_modeled_feedback_capture.csv",
        "Unfinished reference receptions (pending/censored)": "csv/system_censored_reference_feedback.csv",
    }
    snapshot = read_json(folder / "live/sls_evidence.json")
    snapshot_keys = {
        "csv/system_modeled_dl_csi.csv": "DLCSI",
        "csv/system_modeled_spatial_feedback.csv": "SRS",
        "csv/system_network_spatial_evidence.csv": "NetworkSpatial",
        "csv/system_modeled_feedback_capture.csv": "FeedbackCapture",
        "csv/system_censored_reference_feedback.csv": "PendingReference",
        "csv/system_dynamic_pucch_obligations.csv": "UCIObligations",
        "csv/system_native_pucch_emission_audit.csv": "PUCCHEmissions",
        "csv/system_dynamic_uci_completions.csv": "UCICompletions",
        "csv/system_modeled_harq_payload_decisions.csv": "HARQDecisions",
    }
    snapshot_valid = (snapshot.get("Schema") == "sixgr.sls_live_evidence/v1"
                      and isinstance(receipt.get("ExecutionID"), str)
                      and bool(receipt["ExecutionID"].strip())
                      and snapshot.get("ExecutionID") == receipt["ExecutionID"]
                      and snapshot.get("WaveformBacked") is False
                      and snapshot.get("PrimaryStudyAccepted") is False
                      and snapshot.get("SourceClassification") == "retained_calibrated_sls_runtime_rows_not_final_results"
                      and isinstance(snapshot.get("Evidence"), dict))
    evidence = {}
    for name, path in selected.items():
        latest = not path.startswith("summaries/")
        evidence[name] = {"source": path, "rows": read_rows(folder / path, latest=latest),
                          "row_selection": "latest" if latest else "first", "row_limit": 100}
        # Full primary CSVs take precedence once published. Until then show
        # an explicitly identified bounded runtime snapshot, not an invented
        # final CSV or a substituted waveform measurement.
        if not (folder / path).is_file() and snapshot_valid and path in snapshot_keys:
            key = snapshot_keys[path]
            entry = snapshot["Evidence"].get(key, {})
            rows = entry.get("Rows") if isinstance(entry, dict) else None
            if (isinstance(rows, list) and len(rows) <= 100
                    and all(isinstance(record, dict) for record in rows)
                    and entry.get("RetainedRows") == len(rows)):
                evidence[name] = {"source": f"live/sls_evidence.json#Evidence.{key}",
                                  "rows": rows, "row_selection": "latest", "row_limit": 100,
                                  "evidence_scope": "bounded_live_checkpoint_not_final_results",
                                  "committed_through_absolute_slot0": snapshot.get("CommittedThroughAbsoluteSlot0"),
                                  "total_retained_history_rows": entry.get("TotalRows")}
    qualification = read_json(folder / "manifests/system_run_manifest.json")
    output_audit = read_json(folder / "manifests/cross_check_report.json")
    version = hashlib.sha256(json.dumps(
        [receipt, progress, artifacts, evidence, qualification, output_audit],
        sort_keys=True, default=str).encode()).hexdigest()
    return {
        "run": row, "execution_mode": "SLS", "version": version, "payload_version": version, "artifact_version": version,
        "runtime_context": {"stage": progress}, "summary": receipt,
        "sls": {"receipt": receipt, "progress": progress, "evidence": evidence,
                "qualification": qualification,
                "output_audit": output_audit,
                "scope": "Network execution evidence; execution completion does not certify a study.",
                "measurement_notice": "Calibrated abstraction is not waveform CRC/EVM or physical UCI measurement."},
        "tables_all": tables, "images": images, "images_all": images, "artifacts": artifacts,
        "counts": {"artifacts": len(artifacts), "artifacts_total": len(artifacts),
                   "tables_total": len(tables), "images_total": len(images)}, "logs": [], "logs_recent": [],
    }
