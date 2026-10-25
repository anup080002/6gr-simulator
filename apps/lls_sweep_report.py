"""Read-only sweep observation and provenance-preserving comparative exports.

Children remain the owners of physical evidence. Parent exports are explicitly
cross-run concatenations, not a new PHY execution. No missing point is filled
with measurements, zeros, a successful status, or an interpolated curve.
"""
from __future__ import annotations

import csv
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import tempfile
import textwrap
from datetime import datetime, timezone


def io_path(path: Path) -> Path:
    value = str(path.absolute())
    if os.name == "nt" and not value.startswith("\\\\?\\"):
        value = "\\\\?\\UNC\\" + value[2:] if value.startswith("\\\\") else "\\\\?\\" + value
    return Path(value)


def read_json(path):
    try:
        return json.loads(io_path(Path(path)).read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return {}


def read_rows(path, *, strict=False):
    try:
        with io_path(Path(path)).open(encoding="utf-8-sig", newline="") as handle:
            return list(csv.DictReader(handle))
    except (OSError, csv.Error):
        if strict:
            raise
        return []


def number(value):
    try:
        value = float(value)
        return value if math.isfinite(value) else None
    except (TypeError, ValueError):
        return None


def sweep_root(folder):
    folder = Path(folder).absolute()
    if folder.parent.name == "sweeps":
        folder = folder.parent.parent
    config = read_json(folder / "meta/scenario_config_resolved.json")
    if config.get("scenario", {}).get("runner_profile") != "generic_sweep":
        return None, {}
    return folder, config


def observe_sweep(folder):
    """Observe persisted lifecycle, not process liveness. Safe for GUI polling."""
    root, config = sweep_root(folder)
    if root is None:
        return {}
    summary = {r.get("Label"): r for r in read_rows(root / "reports/csv/sweep_summary.csv")}
    points = []
    seen = set()
    for index, override in enumerate(config.get("scenario", {}).get("sweep", {}).get("overrides", []), 1):
        label = str(override.get("label", f"case_{index}"))
        # Must match runSingle.localSanitizeToken, including case folding.
        token = re.sub(r"[^a-z0-9]+", "_", label.strip().lower()).strip("_") or "case"
        if token in {"", ".", ".."} or token in seen:
            raise ValueError("Sweep point folder is empty, unsafe or duplicated")
        seen.add(token)
        child = root / "sweeps" / token
        cfg = override.get("config", {})
        snr = number(cfg.get("simulation", {}).get("snr_db", config.get("simulation", {}).get("snr_db")))
        state_rows = read_rows(child / "reports/csv/run_state.csv")
        state = state_rows[-1] if state_rows else {}
        receipt = summary.get(label, {})
        error = receipt.get("ErrorIdentifier", "")
        current = number(state.get("CurrentCanonicalSlot"))
        total = number(state.get("CanonicalSlotsPerSweepPoint"))
        stage = "pending"
        if receipt:
            stage = "passed" if str(receipt.get("Ok", "")).lower() in {"1", "true"} else "failed"
        elif state:
            stage = "finalizing" if total and current == total else "running"
        elif io_path(child / "meta/scenario_config_resolved.json").is_file():
            stage = "initializing"
        points.append(dict(index=index, label=label, configured_snr_db=snr,
                           status=stage, current_slot=current, total_slots=total,
                           error=error, run_folder=str(child),
                           execution_status=receipt.get("ExecutionStatus", "")))
    return dict(run_folder=str(root), points=points, total=len(points),
                completed=sum(p["status"] in {"passed", "failed"} for p in points),
                passed=sum(p["status"] == "passed" for p in points),
                failed=sum(p["status"] == "failed" for p in points),
                ongoing=sum(p["status"] in {"initializing", "running", "finalizing"} for p in points),
                pending=sum(p["status"] == "pending" for p in points),
                note="Last persisted point state; finalizing is not completed. Configured SNR is not measured SINR.")


def atomic_write(path, write):
    path = io_path(Path(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=path.stem + "_", suffix=path.suffix, dir=path.parent)
    os.close(fd)
    try:
        write(Path(temp))
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def write_csv(path, fields, rows):
    def save(temp):
        with temp.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
    atomic_write(path, save)


PROVENANCE = ["SweepAggregatePointIndex", "SweepAggregateLabel", "SweepAggregateConfiguredSNR_dB",
              "SweepAggregateSourceCSV", "SweepAggregatePointStatus"]


def wilson_interval(failures, trials, z=1.959963984540054):
    """Two-sided Wilson score interval for an observed binomial population."""
    if not trials:
        return "", ""
    p = failures / trials
    denominator = 1 + z * z / trials
    center = (p + z * z / (2 * trials)) / denominator
    half_width = z * math.sqrt(p * (1 - p) / trials + z * z / (4 * trials * trials)) / denominator
    return max(0, center - half_width), min(1, center + half_width)


# Mirror linkTrialDecodeCoverage and exportLLSReportingBundle's supplied-source
# contract. This is original receiver-row acceptance, not archive reexecution
# or statistical independence. Status, BLER and CB CRCs cannot supply TB CRCs.
SCH_COHORT_FIELDS = (
    "RunID RunTag ExecutionID ScenarioID ConfigHash RandomSeed ChannelSeed "
    "SourceRandomSeed SourceChannelSeed PreparedRandomSeed PreparedChannelSeed "
    "SweepPointIndex ConfiguredSNR_dB SNR_dB UEIndex UEID RNTI ServingCell CellID "
    "ReceiverID ReceiverClockDomain ReceiverClockEpoch ConfigurationEpoch RFConfigurationEpoch "
    "ChannelModelApplied ChannelModel ChannelFadingApplied DopplerHz Layers NumLayers "
    "MCS MCSIndex MCSTable MCSMappingTable Modulation CodeRate TargetCodeRate NumCodewords ActualNumCodewords "
    "DecoderCRCInputDomain HARQSoftCombiningApplied HARQCombiningApplied IsRetransmission "
    "HARQIsRetransmission HARQRound RV HARQRV TBSizeBits TBSize_bits TBSBits OriginalTBSBits "
    "CurrentTBSBits RateMatchedBits PRBSet PRBSetJSON PRBs NumPRB PRBStart PRBCount AllocatedPRBCount "
    "TBSInputNPRB TBSInputNREPerPRB TBSInputTargetCodeRate TBSInputXOverhead "
    "SymbolAllocation SymbolStart SymbolLength StartSymbol NumSymbols HARQContextHash "
    "PrecodingMode PrecodingNumPorts PrecodingNumLayers PrecodingMatrixSHA256 AppliedPrecoderSHA256 "
    "PrecoderSHA256 AppliedPrecoderPMI AppliedPrecoderPMIType AppliedPrecoderCodebookMode "
    "ExecutionProfile ExecutionTaxonomy ExecutionBackend "
    "ApproximationMode RuntimeEvidenceSource RuntimeMaterializationStatus E2EAirModel Source"
).split()


def _sch_flag(row, field):
    value = str(row.get(field, "")).strip().lower()
    if value in {"", "nan"}:
        return None
    if value in {"true", "false"}:
        return int(value == "true")
    numeric = number(value)
    if numeric not in (0, 1):
        raise ValueError(f"SCH {field} requires original 0/1 or unavailable, got {value!r}")
    return int(numeric)


def _sch_acceptance(row, direction):
    supplied_direction = str(row.get("Direction", "")).strip().upper()
    if supplied_direction and supplied_direction != direction:
        raise ValueError("SCH source file and original Direction disagree")
    # Optional labels cannot create authority; explicit proxy or unknown
    # backends cannot override otherwise positive receiver flags.
    backends = {"scheduler_shared_stream_receiver", "scheduler_grant_waveform_chain"}
    backends |= ({"canonical_pdsch_compatibility_facades", "legacy_pdsch_calibration_facades"}
                 if direction == "DL" else {"canonical_pusch_waveform_chain"})
    channel = "pdsch" if direction == "DL" else "pusch"
    runner = "runDLPDSCHThroughput" if direction == "DL" else "runULPUSCHThroughput"
    allowed = {"ApproximationMode": {"none"}, "ExecutionBackend": backends,
               "RuntimeEvidenceSource": {f"sixgr.link.{runner}_returned_receiver"},
               "RuntimeMaterializationStatus": {f"active_waveform_{channel}_runtime"}}
    for field, choices in allowed.items():
        value = str(row.get(field, "")).strip()
        if value and value not in choices:
            return False, "supplied_source_contract_incompatible"
    for field in ("Source", "E2EAirModel"):
        value = str(row.get(field, "")).strip().lower()
        if value in {"lut", "logistic", "fast_proxy", "synthetic", "fallback"} or value.startswith(("synthetic_from_fast_kernel", "fast_proxy_")):
            return False, "supplied_source_contract_incompatible"
    for field in ("FallbackFlag", "PlaceholderFlag"):
        if field in row and _sch_flag(row, field) != 0:
            return False, "supplied_source_contract_incompatible"
    prefix = "DLSCH" if direction == "DL" else "ULSCH"
    required = {"FinalizedFlag": 1, "PartialRowFlag": 0, "Crash": 0,
                "IsWarmupFrame": 0, "DecodeAttempted": 1, "DecodeUsable": 1,
                prefix + "DecodeAttempted": 1, prefix + "DecodeAvailable": 1,
                "CRCApplicable": 1}
    flags = {field: _sch_flag(row, field) for field in required}
    crc = _sch_flag(row, "CRCPass")
    status = str(row.get("Status", "")).strip().upper()
    if flags["Crash"] == 1 or status == "CRASH":
        return False, "execution_failure_not_radio_decode_failure"
    if not supplied_direction or any(value is None for value in flags.values()) or crc is None:
        return False, "missing_original_receiver_lifecycle_authority"
    if any(flags[field] != wanted for field, wanted in required.items()) or status not in {"PASS", "FAIL"}:
        return False, "unavailable_or_inapplicable_completed_SCH_CRC"
    return True, ""


def _sch_attempt_class(row):
    flags = [_sch_flag(row, field) for field in ("IsRetransmission", "HARQIsRetransmission")]
    supplied = [flag for flag in flags if flag is not None]
    if len(set(supplied)) > 1:
        raise ValueError("Contradictory original SCH retransmission flags")
    # No assumed HARQRound index origin, RV=0 inference, or reconstructed TB.
    return ("retry" if supplied[0] else "first") if supplied else "unknown"


def _sch_source_sha256(path):
    digest = hashlib.sha256()
    with io_path(Path(path)).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _sch_observations(progress):
    observations = []
    for point in progress["points"]:
        if point["status"] not in {"passed", "failed"}:
            continue
        child = Path(point["run_folder"])
        config_path = io_path(child / "meta/scenario_config_resolved.json")
        config_hash = _sch_source_sha256(config_path) if config_path.is_file() else ""
        for direction, filename in (("DL", "dl_pdsch_trials.csv"), ("UL", "ul_pusch_trials.csv")):
            path = child / "air_interface/csv" / filename
            if not io_path(path).is_file():
                continue
            digest = _sch_source_sha256(path)
            source = f"sweeps/{child.name}/air_interface/csv/{filename}"
            trials = read_rows(path, strict=True)
            fingerprints = [hashlib.sha256(json.dumps(row, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
                            for row in trials]
            multiplicity = {}
            for value in fingerprints:
                multiplicity[value] = multiplicity.get(value, 0) + 1
            for index, (row, fingerprint) in enumerate(zip(trials, fingerprints), 1):
                eligible, reason = _sch_acceptance(row, direction)
                attempt = _sch_attempt_class(row)
                if multiplicity[fingerprint] > 1:
                    eligible, reason = False, "duplicate_original_row_identity_unresolved"
                cohort = {field: row[field] for field in SCH_COHORT_FIELDS if field in row}
                # No cross-point compatibility inferred from equal MCS/rank.
                cohort.update(PointIndex=point["index"], Direction=direction,
                              ChildConfigSHA256=config_hash, AttemptClass=attempt)
                if attempt != "first":
                    # A round number is not a complete conditional soft-buffer
                    # history. Keep retries individual until an explicit
                    # original-history population contract exists.
                    cohort["UnresolvedHistorySourceRow"] = index
                cohort_json = json.dumps(cohort, sort_keys=True, separators=(",", ":"))
                observations.append(dict(PointIndex=point["index"], Direction=direction,
                    ConfiguredSNR_dB=point["configured_snr_db"], SourceCSV=source,
                    SourceSHA256=digest, SourceRow=index, ChildConfigSHA256=config_hash,
                    AttemptClass=attempt, CompletedReceiverOutcomeAvailable=eligible,
                    ExclusionReason=reason, OriginalCRCPass=row.get("CRCPass", ""),
                    PopulationID=hashlib.sha256(cohort_json.encode()).hexdigest(),
                    PopulationJSON=cohort_json, StatisticalIndependenceClaimed=False,
                    # Keep only reduction operands between children, not large
                    # retained LLR/IQ JSON columns. Original rows remain in the
                    # unchanged, hash-identified source and concatenated CSV.
                    _row={field: row[field] for field in
                          ("CRCPass", "MeasuredTrialSINR_dB", "Goodput_Mbps", "MCSIndex", "MCS",
                           "Layers", "RankIndicator", "Rank", "Modulation") if field in row}))
            if _sch_source_sha256(path) != digest:
                raise RuntimeError(f"SCH source changed during snapshot: {path}")
    return observations


def concatenate_csv(destination, sources):
    """Stream exact rows; union schemas, preserve missing cells and row identity."""
    fields = list(PROVENANCE)
    signatures = []
    for point, path, relative in sources:
        stat = io_path(path).stat()
        signatures.append((stat.st_size, stat.st_mtime_ns))
        with io_path(path).open(encoding="utf-8-sig", newline="") as handle:
            header = next(csv.reader(handle), [])
        if not header or len(header) != len(set(header)) or set(header) & set(PROVENANCE):
            raise ValueError(f"Missing, duplicate or reserved CSV columns: {path}")
        fields.extend(field for field in header if field not in fields)
    counts = []
    def save(temp):
        with temp.open("w", encoding="utf-8", newline="") as output:
            writer = csv.DictWriter(output, fieldnames=fields)
            writer.writeheader()
            for (point, path, relative), signature in zip(sources, signatures):
                count = 0
                with io_path(path).open(encoding="utf-8-sig", newline="") as handle:
                    for row in csv.DictReader(handle):
                        if None in row:
                            raise ValueError(f"CSV row wider than its header: {path}")
                        row.update(dict(zip(PROVENANCE, [point["index"], point["label"],
                            point["configured_snr_db"], f"sweeps/{Path(point['run_folder']).name}/{relative}", point["status"]])))
                        writer.writerow(row)
                        count += 1
                stat = io_path(path).stat()
                if signature != (stat.st_size, stat.st_mtime_ns):
                    raise RuntimeError(f"Source changed during snapshot: {path}")
                counts.append(count)
    atomic_write(destination, save)
    return counts


def comparison_png(destination, sources, points=None):
    """One labeled multi-panel image per original PNG, never a substitute curve."""
    from PIL import Image, ImageDraw
    panels = []
    by_point = {point["index"]: path for point, path, _relative in sources}
    for point in points or [point for point, _, _ in sources]:
        path = by_point.get(point["index"])
        if path is None:
            panels.append((point, None))
            continue
        with Image.open(io_path(path)) as original:
            panel = original.convert("RGB")
            panel.thumbnail((1400, 1000))
            panels.append((point, panel.copy()))
    width = max(800, max((p.width for _, p in panels if p is not None), default=0))
    height = sum((p.height if p is not None else 65) + 48 for _, p in panels)
    canvas = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(canvas)
    y = 0
    for point, panel in panels:
        draw.text((12, y + 8), f"Point {point['index']} | configured SNR {point['configured_snr_db']} dB | {point['status']} | {point['label']}", fill="black")
        if panel is not None:
            canvas.paste(panel, (0, y + 38))
        else:
            message = ("Source image unavailable in completed point; inspect point diagnostics."
                       if point["status"] in {"passed", "failed"} else
                       "Point not completed; no final measurement image published yet.")
            draw.text((12, y + 45), message, fill="black")
        y += (panel.height if panel is not None else 65) + 48
    atomic_write(destination, lambda temp: canvas.save(temp, format="PNG"))


def export_overview(root, progress, *, save_images=True):
    """Common SNR axes; unavailable measurements remain gaps, never zeros."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    rows = []
    observations = _sch_observations(progress)
    audit_fields = ["PointIndex", "Direction", "ConfiguredSNR_dB", "SourceCSV", "SourceSHA256",
                    "SourceRow", "ChildConfigSHA256", "AttemptClass", "CompletedReceiverOutcomeAvailable",
                    "ExclusionReason", "OriginalCRCPass", "PopulationID", "PopulationJSON",
                    "StatisticalIndependenceClaimed"]
    write_csv(root / "reports/csv/sweep_sch_outcome_audit.csv", audit_fields,
              [{field: observation[field] for field in audit_fields} for observation in observations])
    fields = {"MeanMeasuredSINR_dB": "MeasuredTrialSINR_dB",
              "MeanAttemptGoodput_Mbps": "Goodput_Mbps", "MeanMCSIndex": "MCSIndex",
              "MeanExecutedLayers": "Layers"}
    for point in progress["points"]:
        for direction, filename in (("DL", "dl_pdsch_trials.csv"), ("UL", "ul_pusch_trials.csv")):
            path = Path(point["run_folder"]) / "air_interface/csv" / filename
            row = dict(PointIndex=point["index"], Label=point["label"],
                       ConfiguredSNR_dB=point["configured_snr_db"], PointStatus=point["status"],
                       Direction=direction, DataAvailability="not_completed",
                       TrialCount="", CRCObservedCount="", FailureCount="", AttemptBLER="",
                       AttemptBLER_CI_Low="", AttemptBLER_CI_High="",
                       FirstAttemptCount="", RetryAttemptCount="", UnknownAttemptClassCount="",
                       ExcludedRowCount="", StatisticalIndependenceClaimed=False,
                       PopulationScope="descriptive_all_completed_attempts_not_initial_or_residual_TB_BLER",
                       SourceCSV=f"sweeps/{path.parents[2].name}/air_interface/csv/{filename}")
            for target in fields:
                row[target] = ""
                row[target + "_Count"] = ""
            if point["status"] not in {"passed", "failed"}:
                rows.append(row)
                continue
            if not io_path(path).is_file():
                row["DataAvailability"] = "source_missing"
                rows.append(row)
                continue
            observed = [o for o in observations if o["PointIndex"] == point["index"] and o["Direction"] == direction]
            accepted = [o for o in observed if o["CompletedReceiverOutcomeAvailable"]]
            trials = [o["_row"] for o in accepted]
            crc = [_sch_flag(r, "CRCPass") for r in trials]
            failures = sum(v == 0 for v in crc)
            row.update(DataAvailability=("completed_SCH_rows_present" if trials else
                                         "no_eligible_completed_SCH_rows" if observed else "source_present_empty"),
                       TrialCount=len(observed), CRCObservedCount=len(crc), FailureCount=failures,
                       AttemptBLER=(failures / len(crc) if crc else ""),
                       FirstAttemptCount=sum(o["AttemptClass"] == "first" for o in accepted),
                       RetryAttemptCount=sum(o["AttemptClass"] == "retry" for o in accepted),
                       UnknownAttemptClassCount=sum(o["AttemptClass"] == "unknown" for o in accepted),
                       ExcludedRowCount=len(observed)-len(accepted))
            for target, source in fields.items():
                values = [number(r.get(source)) for r in trials]
                values = [v for v in values if v is not None]
                row[target] = sum(values) / len(values) if values else ""
                row[target + "_Count"] = len(values)
            rows.append(row)
    columns = ["PointIndex", "Label", "ConfiguredSNR_dB", "PointStatus", "Direction",
               "DataAvailability", "TrialCount", "CRCObservedCount", "FailureCount", "AttemptBLER",
               "AttemptBLER_CI_Low", "AttemptBLER_CI_High", "SourceCSV", "FirstAttemptCount",
               "RetryAttemptCount", "UnknownAttemptClassCount", "ExcludedRowCount",
               "StatisticalIndependenceClaimed", "PopulationScope"]
    columns += [item for field in fields for item in (field, field + "_Count")]
    write_csv(root / "reports/csv/sweep_link_comparison.csv", columns, rows)
    bler_columns = ["PointIndex", "Label", "ConfiguredSNR_dB", "PointStatus", "Direction",
                    "DataAvailability", "CRCObservedCount", "FailureCount", "AttemptBLER",
                    "AttemptBLER_CI_Low", "AttemptBLER_CI_High", "SourceCSV", "FirstAttemptCount",
                    "RetryAttemptCount", "UnknownAttemptClassCount", "ExcludedRowCount",
                    "StatisticalIndependenceClaimed", "PopulationScope"]
    write_csv(root / "reports/csv/sweep_bler_vs_configured_snr.csv", bler_columns,
              [{field: row.get(field, "") for field in bler_columns} for row in rows])
    measured_bler_rows = measured_sinr_bler_rows(progress, observations=observations)
    measured_bler_columns = ["Direction", "MCSIndex", "Modulation", "Rank",
        "PostEqSINR_dB_BinCenter", "PostEqSINR_dB_BinMin", "PostEqSINR_dB_BinMax",
        "ObservedSINRMin_dB", "ObservedSINRMax_dB", "TrialCount", "FailureCount", "BLER",
        "BLER_CI_Low", "BLER_CI_High", "SourcePointIndices", "SourceConfiguredSNR_dB",
        "SourceCSVSet", "EvidenceClass", "PopulationID", "PopulationJSON", "AttemptClass",
        "SourceRowsJSON", "SourceSHA256", "StatisticalIndependenceClaimed"]
    write_csv(root / "reports/csv/sweep_bler_vs_measured_sinr.csv",
              measured_bler_columns, measured_bler_rows)
    if not save_images:
        return
    fig, axes = plt.subplots(2, 2, figsize=(13, 8), constrained_layout=True)
    for ax, (metric, label) in zip(axes.flat, [
        ("MeanMeasuredSINR_dB", "Mean measured trial SINR (dB)"),
        ("AttemptBLER", "CRC failure fraction (completed attempts only)"),
        ("MeanAttemptGoodput_Mbps", "Mean per-attempt goodput (Mbps; not wall-clock rate)"),
        ("MeanExecutedLayers", "Mean executed layers (not capability)")]):
        available = False
        for direction in ("DL", "UL"):
            by_point = {r["PointIndex"]: r for r in rows if r["Direction"] == direction}
            xs = [p["configured_snr_db"] for p in progress["points"]]
            ys = [number(by_point.get(p["index"], {}).get(metric)) for p in progress["points"]]
            available = available or any(v is not None for v in ys)
            ax.plot(xs, [v if v is not None else math.nan for v in ys], "o", label=direction)
        ax.set(xlabel="Configured occupied-RE reference SNR (dB)", ylabel=label)
        ax.set_xticks([p["configured_snr_db"] for p in progress["points"] if p["configured_snr_db"] is not None])
        ax.grid(True, alpha=0.25)
        ax.legend()
        if not available:
            ax.set_yticks([])
            ax.text(0.5, 0.5, "No data-channel measurements in completed points yet.\n"
                    "Failed access / absent trials are not zero-valued measurements.",
                    ha="center", va="center", transform=ax.transAxes, fontsize=10, wrap=True)
    fig.suptitle(f"Sweep comparison: {progress['completed']}/{progress['total']} points finished, "
                 f"{progress['failed']} failed. Missing data are gaps, not zero BLER.")
    atomic_write(root / "reports/image/sweep_link_comparison.png", lambda p: fig.savefig(p, dpi=300))
    plt.close(fig)
    plot_configured_snr_bler(root, progress, rows)
    plot_measured_sinr_bler(root, measured_bler_rows)


def measured_sinr_bler_rows(progress, *, observations=None):
    """Descriptive completed-SCH fractions, not independent or fixed-link BLER."""
    groups = {}
    for observation in (_sch_observations(progress) if observations is None else observations):
        if not observation["CompletedReceiverOutcomeAvailable"]:
            continue
        row = observation["_row"]
        sinr = number(row.get("MeasuredTrialSINR_dB"))
        if sinr is None:
            continue
        mcs = number(row.get("MCSIndex", row.get("MCS")))
        rank = number(row.get("Layers", row.get("RankIndicator", row.get("Rank"))))
        modulation = str(row.get("Modulation", "")).strip() or "unavailable"
        lower = math.floor(sinr)
        key = (observation["Direction"], mcs, modulation, rank, lower, observation["PopulationID"])
        bucket = groups.setdefault(key, dict(sinr=[], crc=[], observations=[]))
        bucket["sinr"].append(sinr)
        bucket["crc"].append(_sch_flag(row, "CRCPass"))
        bucket["observations"].append(observation)
    rows = []
    for (direction, mcs, modulation, rank, lower, population_id), bucket in sorted(
            groups.items(), key=lambda item: str(item[0])):
        count = len(bucket["crc"])
        failures = sum(value == 0 for value in bucket["crc"])
        original = bucket["observations"][0]
        rows.append(dict(Direction=direction, MCSIndex="" if mcs is None else mcs,
            Modulation=modulation, Rank="" if rank is None else rank,
            PostEqSINR_dB_BinCenter=lower + 0.5, PostEqSINR_dB_BinMin=lower,
            PostEqSINR_dB_BinMax=lower + 1, ObservedSINRMin_dB=min(bucket["sinr"]),
            ObservedSINRMax_dB=max(bucket["sinr"]), TrialCount=count, FailureCount=failures,
            BLER=failures / count, BLER_CI_Low="", BLER_CI_High="",
            SourcePointIndices=str(original["PointIndex"]),
            SourceConfiguredSNR_dB=original["ConfiguredSNR_dB"],
            SourceCSVSet=original["SourceCSV"], SourceSHA256=original["SourceSHA256"],
            SourceRowsJSON=json.dumps([o["SourceRow"] for o in bucket["observations"]]),
            PopulationID=population_id, PopulationJSON=original["PopulationJSON"],
            AttemptClass=original["AttemptClass"], StatisticalIndependenceClaimed=False,
            EvidenceClass="completed_SCH_attempt_CRC_fraction_no_independence_claim"))
    return rows


def plot_configured_snr_bler(root, progress, rows):
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(9, 5), constrained_layout=True)
    for direction in ("DL", "UL"):
        indexed = {row["PointIndex"]: row for row in rows if row["Direction"] == direction}
        xs = [point["configured_snr_db"] for point in progress["points"]]
        ys = [number(indexed.get(point["index"], {}).get("AttemptBLER")) for point in progress["points"]]
        y = [value if value is not None else math.nan for value in ys]
        ax.plot(xs, y, "o", label=direction)
    ax.set(xlabel="Configured occupied-RE reference SNR (dB)", ylabel="Completed-attempt CRC failure fraction",
           ylim=(-0.03, 1.03), title="Descriptive completed-SCH attempts vs configured SNR")
    ax.set_xticks([point["configured_snr_db"] for point in progress["points"]
                   if point["configured_snr_db"] is not None])
    ax.grid(True, alpha=0.25)
    ax.legend()
    ax.text(0.01, 0.01, "All completed attempts, including retries; not initial/residual TB BLER.\n"
            "Gaps are unavailable; no independence or confidence-interval claim.",
            transform=ax.transAxes, fontsize=9)
    atomic_write(root / "reports/image/sweep_bler_vs_configured_snr.png",
                 lambda path: fig.savefig(path, dpi=300))
    plt.close(fig)


def plot_measured_sinr_bler(root, rows):
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(1, 2, figsize=(14, 5), constrained_layout=True)
    for ax, direction in zip(axes, ("DL", "UL")):
        direction_rows = [row for row in rows if row["Direction"] == direction]
        series = {}
        for row in direction_rows:
            key = (row["MCSIndex"], row["Modulation"], row["Rank"], row["PopulationID"], row["AttemptClass"], row["SourcePointIndices"])
            series.setdefault(key, []).append(row)
        for key, values in sorted(series.items(), key=lambda item: str(item[0])):
            values.sort(key=lambda row: row["PostEqSINR_dB_BinCenter"])
            ax.plot([row["PostEqSINR_dB_BinCenter"] for row in values],
                    [row["BLER"] for row in values], "o",
                    label=f"point {key[5]} | {key[4]} | MCS {key[0]} | rank {key[2]} | {key[3][:8]}")
        ax.set(xlabel="Receiver post-equalization SINR (dB)", ylabel="Completed-attempt CRC failure fraction",
               ylim=(-0.03, 1.03), title=direction)
        ax.grid(True, alpha=0.25)
        if series:
            ax.legend(fontsize=7)
        else:
            ax.text(0.5, 0.5, "No completed SCH trials with measured SINR.",
                    ha="center", va="center", transform=ax.transAxes)
    fig.suptitle("Descriptive completed-SCH fractions; point/PHY/HARQ populations separate; no independence claim")
    atomic_write(root / "reports/image/sweep_bler_vs_measured_sinr.png",
                 lambda path: fig.savefig(path, dpi=300))
    plt.close(fig)


STANDARD_MEASUREMENT_FIELDS = [
    "CategoryCode", "CategoryKey", "CategoryName", "MetricKey", "MetricName",
    "Entity", "Statistic", "Availability", "CountsTowardCoverage",
    "ValueNumeric", "ValueText", "Unit", "SourceArtifact", "Notes",
]

# Optional original publisher metadata. Legacy schemas remain valid; absence
# never licenses reconstruction of a reference plane or cross-point cohort.
MEASUREMENT_POPULATION_FIELDS = [
    "PopulationID", "PopulationJSON", "SupportConfigurationJSON",
    "PopulationSeriesID", "PopulationSeriesJSON",
]
MEASUREMENT_OPERATING_POINT_FIELDS = [
    "PublishedOperatingPoint_dB", "PublishedOperatingPointField", "PublishedOperatingPointRole",
]


def _is_nmse_measurement(row):
    return (str(row.get("MetricKey", "")) in {"nmse", "ce_nmse", "dmrs_estimation_quality", "srs_port_scaling_impact"}
            and str(row.get("Unit", "")).lower() == "db"
            and str(row.get("Statistic", "")) in {"mean", "p05", "p95", "max", "pooled_error_reference_ratio"})


def _is_csi_observation_metric(row):
    return (row.get("MetricKey") in {"csi_rsrp", "csi_rsrq", "csi_sinr"}
            or re.fullmatch(r"CSI-(?:RSRP_absolute|RSRP_normalized|RSRQ|SINR)@source_row=[0-9]+",
                            str(row.get("Entity", ""))) is not None)


def _is_srs_observation_metric(row):
    return (row.get("MetricKey") == "srs_rsrp"
            or re.fullmatch(r"SRS-(?:RSRP_absolute|reference-power_normalized)@source_row=[0-9]+",
                            str(row.get("Entity", ""))) is not None)


def _validated_csi_observation_population(row):
    """Validate the current publisher identity, not PHY/accuracy or a series.

    This is the outer report population digest, not the distinct original
    CSIObservationPopulationSHA256 inside that population. Legacy populations
    remain opaque marker identities and cannot authorize source coordinates.
    """
    return _validated_reference_observation_population(row, "CSI",
        r"CSI-(?:RSRP_absolute|RSRP_normalized|RSRQ|SINR)@source_row=[0-9]+", {
            "MeasurementRSRP_dBm": ("csi_rsrp", "dBm", "CSI-RSRP_absolute"),
            "MeasurementRSRP_dB_re_UnitOccupiedRE_Es": ("csi_rsrp", "dB_re_UnitOccupiedRE_Es", "CSI-RSRP_normalized"),
            "MeasurementRSRQ_dB": ("csi_rsrq", "dB", "CSI-RSRQ"),
            "ReferenceMeasuredSINR_dB": ("csi_sinr", "dB", "CSI-SINR"),
        }, "air_interface/csv/csi_rs_trials.csv")


def _validated_srs_observation_population(row):
    """Bind published SRS observations, not PHY, calibrated power or a curve.

    The report digest is distinct from SRSAbsolutePowerEvidenceSHA256. The
    absolute branch-selection observation and the normalized engineering
    branch mean retain different fields/units; neither licenses a series.
    """
    return _validated_reference_observation_population(row, "SRS",
        r"SRS-(?:RSRP_absolute|reference-power_normalized)@source_row=[0-9]+", {
            "SRS_RSRP_dBm": ("srs_rsrp", "dBm", "SRS-RSRP_absolute"),
            "SRS_RSRP_dB_re_UnitOccupiedRE_Es": (
                "srs_rsrp", "dB_re_UnitOccupiedRE_Es", "SRS-reference-power_normalized"),
        }, "air_interface/csv/srs_trials.csv")


def _validated_reference_observation_population(row, family, entity_pattern, contracts, artifact):
    """Shared byte/alias guard; family-specific producer fields stay explicit."""
    token, digest = row.get("PopulationJSON", ""), row.get("PopulationID", "")
    if not isinstance(token, str) or not isinstance(digest, str):
        raise ValueError(f"{family} population identity requires original text bytes")
    current_entity = re.fullmatch(entity_pattern, str(row.get("Entity", ""))) is not None
    if not token.strip():
        if digest.strip() or current_entity:
            raise ValueError(f"Current {family} population requires its original ID and JSON together")
        return None

    def pairs(items):
        value = {}
        for key, operand in items:
            if key in value:
                raise ValueError(f"Duplicate {family} population identity field")
            value[key] = operand
        return value

    try:
        population = json.loads(token, object_pairs_hook=pairs,
            parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
    except (ValueError, TypeError) as exc:
        raise ValueError(f"Malformed original {family} population JSON") from exc
    if not isinstance(population, dict):
        raise ValueError(f"Original {family} population must be a scalar object")
    if digest and (not re.fullmatch(r"[0-9a-fA-F]{64}", digest)
                   or hashlib.sha256(token.encode("utf-8")).hexdigest() != digest.lower()):
        raise ValueError(f"Original {family} PopulationID does not match exact PopulationJSON bytes")
    scope = "retained_source_row_not_independent_reception_verification"
    if population.get("ProvenanceScope") != scope and not current_entity:
        return None
    if not digest or population.get("ProvenanceScope") != scope:
        raise ValueError(f"Current {family} observation scope/identity is missing or contradictory")
    source_field = population.get("SourceField")
    if not isinstance(source_field, str) or source_field not in contracts:
        raise ValueError(f"Current {family} observation has an unknown original scalar field")
    metric, unit, entity = contracts[source_field]
    source_row = population.get("SourceRowIndex")
    if (isinstance(source_row, bool) or not isinstance(source_row, (int, float))
            or not math.isfinite(source_row) or source_row < 1
            or source_row >= 2**53 or source_row != int(source_row)):
        raise ValueError(f"Current {family} source row requires an exact positive integer identity")
    if (row.get("MetricKey") != metric or row.get("Statistic") != "observation"
            or row.get("SourceArtifact") != artifact or population.get("SourceArtifact") != artifact
            or row.get("Unit") != unit or population.get("Unit") != unit
            or row.get("Entity") != f"{entity}@source_row={int(source_row)}"):
        raise ValueError(f"Current {family} metric/unit/source-row aliases disagree with original population")

    def scalar(raw):
        if isinstance(raw, bool) or not isinstance(raw, (str, int, float)):
            raise ValueError(f"{family} scalar alias must be numeric CSV text or a numeric scalar")
        try:
            value = float(raw)
        except (ValueError, TypeError, OverflowError) as exc:
            raise ValueError(f"Invalid {family} scalar alias") from exc
        if math.isnan(value):
            raise ValueError(f"A retained {family} observation cannot acquire a fabricated NaN value")
        return value

    original_text = population.get("OriginalValueText")
    if not isinstance(original_text, str) or not isinstance(row.get("ValueText"), str):
        raise ValueError(f"Current {family} observation must retain original numeric text")
    original = scalar(original_text)
    for raw in (row.get("ValueNumeric"), row.get("ValueText")):
        actual = scalar(raw)
        # CSV decimal roundtrip only; this is not a physical error threshold.
        equal = actual == original
        if not equal and math.isfinite(actual) and math.isfinite(original):
            equal = abs(actual-original) <= 64 * math.ulp(max(1.0, abs(actual), abs(original)))
        if not equal:
            raise ValueError(f"Current {family} scalar aliases disagree with original observation")
    return population


def _is_selection_observation_metric(row):
    return (row.get("MetricKey") in {"pmi", "cri", "ri", "cqi"}
            or str(row.get("Entity", "")).startswith("CSI-selection-")
            or "sixgr.report.discrete_selection_observation/v1" in str(row.get("PopulationJSON", "")))


def _validated_selection_observation_population(row):
    """Original index/token identity, never configured-candidate or PHY accuracy."""
    token, digest = row.get("PopulationJSON", ""), row.get("PopulationID", "")
    current = str(row.get("Entity", "")).startswith("CSI-selection-")
    if not isinstance(token, str) or not isinstance(digest, str):
        raise ValueError("Selection population requires original text bytes")
    if not token.strip():
        if current or digest:
            raise ValueError("Current selection requires original population ID and JSON")
        return None

    def pairs(items):
        obj = {}
        for key, value in items:
            if key in obj:
                raise ValueError("Duplicate selection population field")
            obj[key] = value
        return obj

    p = json.loads(token, object_pairs_hook=pairs,
                   parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
    if not isinstance(p, dict):
        raise ValueError("Selection population must be an original scalar object")
    if p.get("ContractVersion") != "sixgr.report.discrete_selection_observation/v1":
        if current:
            raise ValueError("Unknown current selection population contract")
        return None
    if (not re.fullmatch(r"[0-9a-fA-F]{64}", digest)
            or hashlib.sha256(token.encode("utf-8")).hexdigest() != digest.lower()):
        raise ValueError("Selection population hash differs from original bytes")
    field = p.get("SourceField")
    index = p.get("SourceRowIndex")
    unit = "layers" if field == "RI" else "index"
    if (not isinstance(field, str) or field not in {"PMI", "CRI", "RI", "CQI"} or isinstance(index, bool)
            or not isinstance(index, (int, float)) or not math.isfinite(index)
            or index < 1 or index >= 2**53 or index != int(index)
            or row.get("Entity") != f"CSI-selection-{field}@source_row={int(index)}"
            or row.get("MetricKey") != field.lower() or row.get("Statistic") != "observation"
            or row.get("Unit") != unit or p.get("Unit") != unit
            or row.get("SourceArtifact") != "air_interface/csv/csi_rs_trials.csv"
            or p.get("SourceArtifact") != row.get("SourceArtifact")
            or p.get("ProvenanceScope") != "retained_source_row_not_independent_reception_verification"):
        raise ValueError("Selection metric/source/namespace aliases contradict original observation")
    original = p.get("OriginalValueText")
    if not isinstance(original, str) or row.get("ValueText") != original:
        raise ValueError("Selection must preserve its original scalar/component token")
    try:
        decoded = json.loads(original) if original.strip().startswith("[") else float(original)
    except (ValueError, TypeError) as exc:
        raise ValueError("Malformed discrete selection token") from exc
    components = decoded if isinstance(decoded, list) else [decoded]
    if (not components or any(isinstance(v, bool) or not isinstance(v, (int, float))
                              or not math.isfinite(v) or v < 0 or v >= 2**53 or v != int(v)
                              for v in components)):
        raise ValueError("Selection operands must be original nonnegative integers")
    numeric = number(row.get("ValueNumeric"))
    if isinstance(decoded, list) and len(decoded) > 1:
        if field != "PMI" or numeric is not None:
            raise ValueError("PMI components must not acquire a synthetic scalar index")
    elif numeric != components[0]:
        raise ValueError("Selection scalar differs from original token")
    return p


def _source_operating_point(row):
    result = {field: "" for field in MEASUREMENT_OPERATING_POINT_FIELDS}
    if _is_csi_observation_metric(row):
        population = _validated_csi_observation_population(row)
        if population is None:
            return result
    elif _is_srs_observation_metric(row):
        population = _validated_srs_observation_population(row)
        if population is None:
            return result
    elif _is_selection_observation_metric(row):
        population = _validated_selection_observation_population(row)
        if population is None:
            return result
    else:
        token = str(row.get("PopulationJSON", ""))
        if not token.strip():
            return result
        try:
            population = json.loads(token)
        except (ValueError, TypeError) as exc:
            raise ValueError("Original PopulationJSON is malformed; no operating point can be inferred") from exc
    if not isinstance(population, dict):
        raise ValueError("Original PopulationJSON must retain a scalar object")
    # Configured and legacy source SNR remain distinct metadata roles, neither
    # is measured SINR. JSON null is explicit unavailable, never numeric zero.
    candidates = []
    for field in ("ConfiguredSNR_dB", "SNR_dB"):
        if field not in population or population[field] is None:
            continue
        value = population[field]
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValueError(f"Original {field} requires a finite numeric scalar or explicit null")
        candidates.append((field, value))
    if candidates:
        field, value = candidates[0]
        result.update(PublishedOperatingPoint_dB=value, PublishedOperatingPointField=field,
                      PublishedOperatingPointRole=("source_configured_operating_point_metadata"
                                                   if field == "ConfiguredSNR_dB" else
                                                   "source_SNR_metadata_not_measured_SINR"))
    return result


def _plot_operating_point(row):
    if _is_selection_observation_metric(row) or _is_csi_observation_metric(row) or _is_srs_observation_metric(row):
        family = "selection" if _is_selection_observation_metric(row) else ("CSI" if _is_csi_observation_metric(row) else "SRS")
        original = _source_operating_point(row)  # Direct plot calls cannot bypass the importer.
        for field in MEASUREMENT_OPERATING_POINT_FIELDS:
            supplied = row.get(field, "")
            expected = original[field]
            if supplied == "":
                continue
            if field == "PublishedOperatingPoint_dB":
                if expected == "" or isinstance(supplied, bool) or number(supplied) != expected:
                    raise ValueError(f"{family} plot coordinate contradicts verified original population")
            elif supplied != expected:
                raise ValueError(f"{family} plot coordinate role contradicts original population")
        value = number(original["PublishedOperatingPoint_dB"])
        return value if value is not None else number(row.get("ConfiguredSNR_dB"))
    value = number(row.get("PublishedOperatingPoint_dB"))
    return value if value is not None else number(row.get("ConfiguredSNR_dB"))


def _is_true(value):
    return str(value).strip().lower() in {"1", "true", "yes"}


def _metric_slug(category, metric, unit):
    identity = "\x1f".join((str(category), str(metric), str(unit)))
    readable = re.sub(r"[^a-z0-9]+", "_", f"{category}_{metric}_{unit}".lower()).strip("_")
    readable = readable[:90] or "measurement"
    return f"{readable}__{hashlib.sha256(identity.encode()).hexdigest()[:12]}"


def standardized_measurement_rows(progress):
    """Collect runtime-published scalar measurements without reinterpreting them.

    The child output tables are the scientific owners of metric definitions and
    populations.  This function only adds sweep provenance.  Configuration-only,
    unavailable rows remain in the availability ledger. Original negative-
    infinity NMSE (exact zero error) remains a published value, but is annotated
    separately on plots: no arbitrary finite floor is a measurement.
    """
    availability_rows = []
    measured_rows = []
    for point in progress["points"]:
        if point["status"] not in {"passed", "failed"}:
            continue
        directory = Path(point["run_folder"]) / "reports/csv"
        if not io_path(directory).is_dir():
            continue
        for path in sorted(io_path(directory).glob("*_outputs.csv")):
            relative = Path(path).relative_to(io_path(Path(point["run_folder"]))).as_posix()
            try:
                with path.open(encoding="utf-8-sig", newline="") as handle:
                    reader = csv.DictReader(handle)
                    header = reader.fieldnames or []
                    if len(header) != len(set(header)):
                        raise ValueError(f"Duplicate original measurement CSV columns: {path}")
                    if not set(STANDARD_MEASUREMENT_FIELDS).issubset(header):
                        continue
                    for source_row_index, source in enumerate(reader, 1):
                        if None in source or any(value is None for value in source.values()):
                            raise ValueError(f"Malformed original measurement row: {path}:{source_row_index}")
                        row = {
                            "PointIndex": point["index"],
                            "Label": point["label"],
                            "ConfiguredSNR_dB": point["configured_snr_db"],
                            "PointStatus": point["status"],
                            **{field: source.get(field, "") for field in STANDARD_MEASUREMENT_FIELDS},
                            **{field: source.get(field, "") for field in MEASUREMENT_POPULATION_FIELDS},
                            "SourceOutputTable": f"sweeps/{Path(point['run_folder']).name}/{relative}",
                            "SourceOutputRow": source_row_index,
                            "EvidenceClass": "runtime_published_standardized_measurement_row",
                        }
                        row.update(_source_operating_point(row))
                        if _is_selection_observation_metric(row) and str(row.get("Entity", "")).startswith("CSI-selection-"):
                            row["EvidenceClass"] = "original_discrete_selection_observation_not_selection_accuracy"
                        _measurement_series_key(row)  # Validate supplied pairs even on unavailable rows.
                        availability_rows.append(row)
                        value = number(source.get("ValueNumeric"))
                        nmse = _is_nmse_measurement(source)
                        if nmse and str(source.get("ValueNumeric", "")).strip().lower() in {"-inf", "-infinity"}:
                            value = -math.inf
                        state = str(source.get("Availability", "")).strip().lower()
                        # Named NMSE report reductions are legitimately derived
                        # from original producer observations. This is not a
                        # generic promotion of all derived/proxy report values.
                        derived_nmse = (state == "derived" and nmse and
                                        source.get("SourceArtifact", "") == "reports/csv/channel_nmse_population_summary.csv")
                        if ((state == "observed" or derived_nmse)
                                and _is_true(source.get("CountsTowardCoverage"))
                                and value is not None):
                            row = dict(row)
                            row["ValueNumeric"] = value
                            if derived_nmse:
                                row["EvidenceClass"] = "original_producer_contract_NMSE_report_reduction_not_new_PHY_execution"
                            measured_rows.append(row)
            except (OSError, csv.Error):
                raise
    return availability_rows, measured_rows


def _validated_measurement_series(row):
    """Only the current original NMSE publisher contract licenses a line.

    Hash exact UTF-8 bytes, as summarizeChannelNMSEReport/sha256Hex do; never
    canonicalize and hash a newly manufactured substitute definition. Other
    publishers and historical unknown metadata remain readable marker data.
    This validates supplied scope, not the original PHY or accuracy.
    """
    token = str(row.get("PopulationSeriesJSON", ""))
    digest = str(row.get("PopulationSeriesID", "")).strip()
    if (not _is_nmse_measurement(row)
            or row.get("SourceArtifact") != "reports/csv/channel_nmse_population_summary.csv"
            or not re.fullmatch(r"[0-9a-fA-F]{64}", digest)
            or hashlib.sha256(token.encode("utf-8")).hexdigest() != digest.lower()):
        return False

    def strict_object(text):
        def pairs(items):
            result = {}
            for key, value in items:
                if key in result:
                    raise ValueError("Duplicate original population field")
                result[key] = value
            return result
        value = json.loads(text, object_pairs_hook=pairs,
                           parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
        if not isinstance(value, dict):
            raise ValueError("Original population must be a scalar object")
        return value

    try:
        series = strict_object(token)
        fields = {"Signal", "Adapter", "ReferenceSource", "ReferencePlane",
                  "ReferenceRFImpairmentsIncluded", "ComparedValues", "PilotResourceCount",
                  "PopulationJSON", "SupportConfigurationJSON"}
        if set(series) != fields:
            return False
        if any(not isinstance(series[name], str) or not series[name].strip()
               for name in ("Signal", "Adapter", "ReferenceSource", "ReferencePlane")):
            return False
        if series["Signal"] != row.get("Entity"):
            return False
        if series["Adapter"] not in {
                "shared_data_independent_pilot_score/v1", "isolated_executed_data_scoring/v1",
                "TRS_independent_complex_pilot_score/v1", "CSI_RS_nominal_linear_pilot_score/v1"}:
            return False
        for name in ("ComparedValues", "PilotResourceCount"):
            value = series[name]
            if value is None and name == "PilotResourceCount" and series["Adapter"] == "isolated_executed_data_scoring/v1":
                continue
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0 or value != int(value):
                return False
        if series["PilotResourceCount"] is not None and series["PilotResourceCount"] > series["ComparedValues"]:
            return False
        if not isinstance(series["ReferenceRFImpairmentsIncluded"], (int, float, bool)) or series["ReferenceRFImpairmentsIncluded"] not in (0, 1):
            return False
        if series["SupportConfigurationJSON"] != row.get("SupportConfigurationJSON"):
            return False
        strict_object(series["SupportConfigurationJSON"])
        original = strict_object(str(row.get("PopulationJSON", "")))
        expected = {key: value for key, value in original.items() if key not in {
            "SweepPointIndex", "SweepAggregatePointIndex", "PointIndex", "ConfiguredSNR_dB", "SNR_dB"}}
        recorded = strict_object(series["PopulationJSON"])
        # Serialization here is equality checking only, not a replacement hash.
        return json.dumps(recorded, sort_keys=True) == json.dumps(expected, sort_keys=True)
    except (ValueError, TypeError, OverflowError):
        return False


def _measurement_series_key(row):
    base = (str(row.get("Entity", "")).strip() or "all",
            str(row.get("Statistic", "")).strip() or "value")
    series_id = str(row.get("PopulationSeriesID", "")).strip()
    series_json = str(row.get("PopulationSeriesJSON", "")).strip()
    if bool(series_id) != bool(series_json):
        raise ValueError("An explicit population series requires its original ID and definition together")
    if series_id and _validated_measurement_series(row):
        # The producer excludes ONLY declared operating-point coordinates.
        # Run/config/seed/reference/support compatibility remains explicit.
        return (*base, "publisher_series", series_id, series_json,
                str(row.get("SupportConfigurationJSON", "")),
                str(row.get("PublishedOperatingPointField", "")))
    population = tuple(str(row.get(field, "")) for field in MEASUREMENT_POPULATION_FIELDS[:3])
    if any(population):
        # A point-scoped population hash cannot be converted into cross-point
        # compatibility. Preserve its complete supplied definition and scope.
        return (*base, "point_population", *population,
                str(row.get("PointIndex", "")), str(row.get("ConfiguredSNR_dB", "")))
    # Applies to ALL metrics, not only NMSE: equal labels/units do not bind
    # beams, resources, power planes or compatible child configurations.
    return (*base, "legacy_source_row", str(row.get("SourceOutputTable", "")),
            str(row.get("SourceOutputRow", "")), str(row.get("PointIndex", "")),
            str(row.get("ConfiguredSNR_dB", "")))


def _stagger_overlapping_measurement_ticks(fig, ax):
    """Move only label text vertically; retain every original tick/value."""
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    accepted = []
    for label in ax.get_xticklabels():
        bounds = label.get_window_extent(renderer)
        if bounds.x1 > fig.bbox.x1 - 8:
            label.set_horizontalalignment("right")
        elif bounds.x0 < fig.bbox.x0 + 8:
            label.set_horizontalalignment("left")
        step = 1.35 * label.get_fontsize() * fig.dpi / 72 / ax.bbox.height
        while True:
            bounds = label.get_window_extent(renderer).expanded(1.03, 1.08)
            if not any(bounds.overlaps(other) for other in accepted):
                accepted.append(bounds)
                break
            x, y = label.get_position()
            label.set_position((x, y - step))
    fig.canvas.draw()


def _plot_standardized_metric(path, progress, rows, title, unit):
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(figsize=(10, 5.8), constrained_layout=True)
    series = {}
    series_point_indices = {}
    coordinate_point_indices = {}
    zero_error_rows = []
    unplaced_rows = []
    for row in rows:
        key = _measurement_series_key(row)
        coordinate = _plot_operating_point(row)
        point_index = row.get("PointIndex")
        series_point_indices.setdefault(key, set()).add(point_index)
        coordinate_point_indices.setdefault((key, coordinate), set()).add(point_index)
        if coordinate is None:
            unplaced_rows.append(row)
            series.setdefault(key, {})
            continue
        if _is_nmse_measurement(row) and float(row["ValueNumeric"]) == -math.inf:
            zero_error_rows.append(row)
            series.setdefault(key, {}).setdefault(coordinate, [])
            continue
        series.setdefault(key, {}).setdefault(coordinate, []).append(
            float(row["ValueNumeric"]))
    scoped = any(len(key) > 2 for key in series) or bool(unplaced_rows)
    if scoped:
        # Already reduced NMSE statistics are not fresh linear observations.
        # Plot every original scalar; never average dB means or distinct scopes,
        # including the high-cardinality case. Exact identities remain in CSV.
        for index, (key, by_snr) in enumerate(sorted(series.items(), key=lambda item: str(item[0])), 1):
            if not any(by_snr.values()):
                continue
            # NaN is only a renderer gap at an original -Inf observation;
            # source/companion CSV keeps -Inf, and the annotation explains it.
            points = [(snr, value) for snr in sorted(by_snr)
                      for value in (by_snr[snr] or [math.nan])]
            xs, ys = zip(*points)
            label = " | ".join(key[:2])
            if len(key) > 2:
                label += f" | {key[2]} {index}: {key[3][:12]}"
            if len(series) > 12:
                label = "_nolegend_"
            # Duplicate x coordinates remain separate points, not a vertical
            # interpolated curve or an invented per-point mean.
            line_authorized = key[2] == "publisher_series" and len(set(xs)) == len(xs)
            mode = "o-" if line_authorized else "o"
            if line_authorized:
                # A planned but unavailable point must break the line, not
                # disappear into a straight segment. Gap coordinates below
                # are renderer-only NaNs; no invented measurement CSV row.
                order = {point["index"]: index for index, point in enumerate(progress["points"])}
                present = series_point_indices[key]
                render_x, render_y = [], []
                previous = None
                for x, y in points:
                    ids = coordinate_point_indices[(key, x)]
                    if previous is not None:
                        all_ids = previous | ids
                        known = all(value in order for value in all_ids)
                        positions = [order[value] for value in all_ids] if known else []
                        gap = not known or any(point["index"] not in present
                            for point in progress["points"][min(positions):max(positions)+1])
                        if gap:
                            render_x.append(math.nan); render_y.append(math.nan)
                    render_x.append(x); render_y.append(y)
                    previous = ids
                xs, ys = render_x, render_y
            ax.plot(xs, ys, mode, linewidth=1.2, markersize=4, label=label)
    elif len(series) <= 12:
        for key, by_snr in sorted(series.items(), key=lambda item: str(item[0])):
            xs = sorted(by_snr)
            means = [sum(by_snr[x]) / len(by_snr[x]) for x in xs]
            lows = [min(by_snr[x]) for x in xs]
            highs = [max(by_snr[x]) for x in xs]
            label = " | ".join(key)
            ax.plot(xs, means, "o-", linewidth=1.2, markersize=4, label=label)
            if any(lo != hi for lo, hi in zip(lows, highs)):
                ax.fill_between(xs, lows, highs, alpha=0.12)
    else:
        # Hundreds of runtime scopes can legitimately share one MetricKey.
        # Preserve every scalar in the CSV and show their per-SNR population
        # here; a 100-entry legend would be unreadable and can collapse the
        # plotting axes on finite-size PNG output.
        population = {}
        for by_snr in series.values():
            for snr, values in by_snr.items():
                population.setdefault(snr, []).extend(values)
        xs = sorted(population)
        for x in xs:
            ax.scatter([x] * len(population[x]), population[x], s=10,
                       alpha=0.25, color="tab:blue")
        means = [sum(population[x]) / len(population[x]) for x in xs]
        lows = [min(population[x]) for x in xs]
        highs = [max(population[x]) for x in xs]
        ax.plot(xs, means, "o-", linewidth=1.5, markersize=5,
                color="black", label=f"population mean ({len(series)} published series)")
        ax.fill_between(xs, lows, highs, alpha=0.12, color="tab:blue",
                        label="population min-max")
    configured = sorted({value for row in rows if (value := _plot_operating_point(row)) is not None})
    ax.set_xticks(configured)
    if scoped:
        ax.set_xticklabels([format(value, ".17g") for value in configured])
    roles = {str(row.get("PublishedOperatingPointField", "")) for row in rows}
    ax.set_xlabel("Source operating-point SNR metadata (dB; not measured SINR)"
                  if "SNR_dB" in roles else "Configured operating-point SNR (dB)")
    ax.set_ylabel(unit or "Published measurement value")
    ax.set_title(title)
    ax.grid(True, alpha=0.25)
    if ax.get_legend_handles_labels()[0] and not (scoped and len(series) > 12):
        ax.legend(fontsize=7, loc="best")
    elif not series:
        ax.text(0.5, 0.5, "No observed runtime-published values.",
                ha="center", va="center", transform=ax.transAxes)
    header_notes = []
    if zero_error_rows:
        zero_points = ", ".join(sorted({str(_plot_operating_point(row)) for row in zero_error_rows}))
        header_notes.append(f"Exact-zero NMSE: {len(zero_error_rows)} original -Inf dB values; "
                            f"operating-point SNR(s): {zero_points}. "
                            "Retained in CSV by population; no finite plotted floor.")
    if unplaced_rows:
        header_notes.append(f"{len(unplaced_rows)} original values have no finite source/wrapper operating-point coordinate; retained in CSV.")
    scope_note = (f"Original published scalars; {len(series)} distinct supplied population series, no additional averaging. "
                  "Cross-point connections require the same explicit publisher series definition. "
                  if scoped else
                  "Markers are per-point arithmetic means of matching published rows; shaded range is min-max. ")
    footer = scope_note + "Exact rows and identities are retained in the companion CSV; missing points are gaps."
    if scoped:
        # Reserve actual figure space; evidence notes must not cover samples.
        # Manual wrapping is deterministic and makes rendered extents testable.
        fig.set_layout_engine(None)
        header = "\n".join(textwrap.fill(note, width=115) for note in header_notes)
        header_lines = len(header.splitlines())
        top = .91 - header_lines * 10 / (fig.get_figheight() * 72)
        fig.subplots_adjust(left=.10, right=.97, bottom=.28, top=top)
        if header:
            fig.text(.10, .98, header, fontsize=8, va="top")
        fig.text(.10, .025, textwrap.fill(footer, width=115), fontsize=8, va="bottom")
        _stagger_overlapping_measurement_ticks(fig, ax)
    else:
        ax.text(0.01, 0.01, footer, transform=ax.transAxes, fontsize=8, va="bottom", wrap=True)
    atomic_write(path, lambda output: fig.savefig(output, dpi=300))
    plt.close(fig)


def export_standardized_measurement_curves(root, progress, *, save_images=True):
    """Publish one cross-point CSV/PNG per observed standardized metric."""
    availability, measured = standardized_measurement_rows(progress)
    fields = ["PointIndex", "Label", "ConfiguredSNR_dB", "PointStatus",
              *STANDARD_MEASUREMENT_FIELDS, *MEASUREMENT_POPULATION_FIELDS, *MEASUREMENT_OPERATING_POINT_FIELDS, "SourceOutputTable", "SourceOutputRow",
              "EvidenceClass"]
    write_csv(root / "reports/csv/sweep_measurement_availability.csv", fields, availability)
    write_csv(root / "reports/csv/sweep_measurement_values.csv", fields, measured)

    groups = {}
    for row in measured:
        key = (row.get("CategoryKey", ""), row.get("MetricKey", ""), row.get("Unit", ""))
        groups.setdefault(key, []).append(row)
    manifest = []
    terminal = {p["index"] for p in progress["points"] if p["status"] in {"passed", "failed"}}
    incomplete = {p["index"] for p in progress["points"] if p["status"] not in {"passed", "failed"}}
    for (category, metric, unit), rows in sorted(groups.items(), key=lambda item: str(item[0])):
        slug = _metric_slug(category, metric, unit)
        metric_csv = f"reports/csv/sweep_metrics/{slug}.csv"
        metric_png = f"reports/image/sweep_metrics/{slug}.png"
        write_csv(root / metric_csv, fields, rows)
        observed_points = {int(row["PointIndex"]) for row in rows}
        title = str(rows[0].get("MetricName", "")).strip() or str(metric).replace("_", " ")
        if save_images:
            _plot_standardized_metric(root / metric_png, progress, rows, title, unit)
        manifest.append({
            "CategoryKey": category,
            "MetricKey": metric,
            "MetricName": title,
            "Unit": unit,
            "ObservedRowCount": len(rows),
            "ObservedPointIndices": "|".join(map(str, sorted(observed_points))),
            "MissingTerminalPointIndices": "|".join(map(str, sorted(terminal - observed_points))),
            "IncompletePointIndices": "|".join(map(str, sorted(incomplete))),
            "SeriesCount": len({_measurement_series_key(row) for row in rows}),
            "CampaignCSV": metric_csv,
            "CampaignPNG": metric_png if save_images else "",
            "EvidenceClass": "cross_run_runtime_published_observed_measurements",
        })
    manifest_fields = ["CategoryKey", "MetricKey", "MetricName", "Unit",
                       "ObservedRowCount", "ObservedPointIndices",
                       "MissingTerminalPointIndices", "IncompletePointIndices",
                       "SeriesCount", "CampaignCSV", "CampaignPNG", "EvidenceClass"]
    write_csv(root / "reports/csv/sweep_measurement_plot_manifest.csv", manifest_fields, manifest)
    return manifest


def _annotate_parent_csv_frequency(root, center_frequency_hz):
    """Label parent configuration without overwriting child measurement identity.

    A parent frequency is not evidence of the carrier actually used by every
    child. Exact concatenations retain their original fields unchanged.
    """
    for path in sorted((root / "reports/csv").rglob("*.csv")):
        if path.name.startswith("sweep_combined__"):
            continue
        rows = read_rows(path, strict=True)
        with io_path(path).open(encoding="utf-8-sig", newline="") as handle:
            fields = next(csv.reader(handle), [])
        field = "ParentConfiguredCenterFrequencyHz"
        if field not in fields:
            fields = [field, *fields]
        for row in rows:
            row[field] = center_frequency_hz
        write_csv(path, fields, rows)


def _write_common_campaign_exports(root, progress, config, measurement_manifest, *, save_images=True):
    """Publish stable campaign-level names without inventing unavailable data."""
    out_csv = root / "reports/csv"
    out_image = root / "reports/image"
    center_frequency_hz = config.get("frequency", {}).get("center_frequency_hz", "")

    point_fields = list(progress["points"][0]) if progress["points"] else ["index"]
    write_csv(out_csv / "point_status.csv", ["ParentConfiguredCenterFrequencyHz", *point_fields], [
        {"ParentConfiguredCenterFrequencyHz": center_frequency_hz, **point} for point in progress["points"]
    ])

    _, measured = standardized_measurement_rows(progress)
    metric_fields = ["ParentConfiguredCenterFrequencyHz", "PointIndex", "Label", "ConfiguredSNR_dB",
                     "PointStatus", *STANDARD_MEASUREMENT_FIELDS, *MEASUREMENT_POPULATION_FIELDS, *MEASUREMENT_OPERATING_POINT_FIELDS, "SourceOutputTable",
                     "SourceOutputRow", "EvidenceClass"]
    write_csv(out_csv / "metrics_long.csv", metric_fields, [
        {"ParentConfiguredCenterFrequencyHz": center_frequency_hz, **row} for row in measured
    ])

    # These aliases preserve the existing scientifically defined populations.
    # Attempt CRC failure is all observed attempts, not initial-TB or residual BLER.
    aliases = [
        (out_csv / "sweep_bler_vs_configured_snr.csv",
         out_csv / "attempt_crc_failure_fraction.csv"),
        (out_image / "sweep_bler_vs_configured_snr.png",
         out_image / "attempt_crc_failure_fraction.png"),
    ]
    for source, destination in aliases:
        if io_path(source).is_file():
            atomic_write(destination, lambda target, source=source: shutil.copyfile(source, target))

    # Calibration rows retain both configured and receiver-measured axes.
    comparison = read_rows(out_csv / "sweep_link_comparison.csv")
    calibration_fields = ["ParentConfiguredCenterFrequencyHz", "PointIndex", "Label", "ConfiguredSNR_dB",
                          "PointStatus", "Direction", "DataAvailability",
                          "MeanMeasuredSINR_dB", "MeanMeasuredSINR_dB_Count", "SourceCSV"]
    write_csv(out_csv / "sinr_calibration.csv", calibration_fields, [
        {field: (center_frequency_hz if field == "ParentConfiguredCenterFrequencyHz" else row.get(field, ""))
         for field in calibration_fields} for row in comparison
    ])
    if save_images:
        _plot_sinr_calibration(out_image / "sinr_calibration.png", progress, comparison)

    required = [
        "campaign_manifest.json", "resolved_parameter_table.csv", "capability_coverage.csv",
        "point_status.csv", "metrics_long.csv", "sinr_calibration.csv", "sinr_calibration.png",
        "initial_tb_bler.csv", "initial_tb_bler.png", "attempt_crc_failure_fraction.csv",
        "attempt_crc_failure_fraction.png", "residual_tb_failure_rate.csv",
        "residual_tb_failure_rate.png", "goodput.csv", "goodput.png",
        "spectral_efficiency.csv", "spectral_efficiency.png", "rank_mcs_distribution.csv",
        "rank_mcs_distribution.png", "channel_estimation_nmse.csv",
        "channel_estimation_nmse.png", "evm.csv", "evm.png", "harq.csv", "harq.png",
        "control_feedback_errors.csv", "control_feedback_errors.png", "access_detection.csv",
        "access_detection.png", "rf_impairments.csv", "rf_impairments.png",
        "rs_measurements.csv", "rs_measurements.png", "beam_csi_overhead.csv",
        "beam_csi_overhead.png", "cb_pusch_multiuser.csv", "cb_pusch_multiuser.png",
        "sls_ue_throughput_cdf.csv", "sls_ue_throughput_cdf.png", "energy_latency.csv",
        "energy_latency.png",
    ]
    status_rows = []
    for name in required:
        candidates = [root / "reports/csv" / name, root / "reports/image" / name,
                      root / "reports" / name, root / "meta" / name]
        found = next((candidate for candidate in candidates if io_path(candidate).is_file()), None)
        status_rows.append({
            "Artifact": name,
            "Status": "available" if found else "unavailable",
            "Path": found.relative_to(root).as_posix() if found else "",
            "Reason": "" if found else "No execution-backed campaign reducer for this population in the current Stage-0 study; no placeholder was emitted.",
        })
    write_csv(out_csv / "campaign_artifact_status.csv",
              ["Artifact", "Status", "Path", "Reason"], status_rows)
    manifest = {
        "CampaignID": config.get("meta", {}).get("scenario_id", ""),
        "CenterFrequencyHz": center_frequency_hz,
        "PrimaryTargetValues_dB": [point.get("configured_snr_db") for point in progress["points"]],
        "PointCount": len(progress["points"]),
        "CompletedPointCount": progress["completed"],
        "FailedPointCount": progress["failed"],
        "EvidenceMode": "cross_run_execution_backed_truth_only",
        "StandardizedMeasurementPlotCount": len(measurement_manifest),
        "ScopeBoundary": "configured_generic_sweep_not_full_study_qualification",
        "CarrierMetadataScope": "parent_configuration_not_verification_of_child_carriers",
    }
    atomic_write(root / "reports/campaign_manifest.json",
                 lambda path: path.write_text(json.dumps(manifest, indent=2), encoding="utf-8"))


def _plot_sinr_calibration(path, progress, rows):
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(9, 5.5), constrained_layout=True)
    for direction in ("DL", "UL"):
        selected = [row for row in rows if row.get("Direction") == direction]
        xs = [number(row.get("ConfiguredSNR_dB")) for row in selected]
        ys = [number(row.get("MeanMeasuredSINR_dB")) for row in selected]
        pairs = [(x, y) for x, y in zip(xs, ys) if x is not None and y is not None]
        if pairs:
            ax.plot([pair[0] for pair in pairs], [pair[1] for pair in pairs], "o-", label=direction)
    configured = [point["configured_snr_db"] for point in progress["points"]
                  if point["configured_snr_db"] is not None]
    if configured:
        ax.plot(configured, configured, "--", color="black", alpha=0.5,
                label="configured-axis identity reference")
        ax.set_xticks(sorted(set(configured)))
    ax.set(xlabel="Configured occupied-RE reference SNR (dB)",
           ylabel="Mean receiver-measured SINR (dB)",
           title="Configured reference SNR versus measured receiver SINR")
    ax.grid(True, alpha=0.25)
    ax.legend()
    atomic_write(path, lambda output: fig.savefig(output, dpi=300))
    plt.close(fig)


def export_sweep(folder):
    """Publish atomic comparative snapshots. Never mutate source/child outputs."""
    # Export runs in its own process, so the CSV parser limit is not shared
    # with request handlers. Large retained bit/LLR vectors are legitimate.
    csv.field_size_limit(2**31 - 1)
    progress = observe_sweep(folder)
    if not progress:
        raise ValueError("Not a resolved generic sweep run")
    root = Path(progress["run_folder"])
    config = read_json(root / "meta/scenario_config_resolved.json")
    save_images = config.get("output", {}).get("save_figures", True) is not False
    out_csv = root / "reports/csv"
    write_csv(out_csv / "sweep_progress.csv", list(progress["points"][0]) if progress["points"] else ["index"], progress["points"])
    groups = {}
    # Only completed children have immutable tables/images suitable for an
    # exhaustive snapshot. The GUI progress still includes the active child.
    for point in progress["points"]:
        if point["status"] not in {"passed", "failed"}:
            continue
        child = Path(point["run_folder"])
        for directory, _dirs, files in os.walk(io_path(child)):
            for filename in files:
                if Path(filename).suffix.lower() not in {".csv", ".png"}:
                    continue
                if not save_images and Path(filename).suffix.lower() == ".png":
                    continue
                path = Path(directory) / filename
                relative = path.relative_to(io_path(child)).as_posix()
                groups.setdefault(relative, []).append((point, path, relative))
    receipt_path = out_csv / "sweep_comparison_manifest.csv"
    previous = {r.get("SourceRelativePath"): r for r in read_rows(receipt_path)}
    manifest = []
    for relative, sources in sorted(groups.items()):
        # Hash the complete relative name: avoids collisions between paths
        # like a/b.csv and a__b.csv while keeping Windows paths short.
        identity = hashlib.sha256(relative.encode()).hexdigest()[:16]
        stem = re.sub(r"[^A-Za-z0-9_-]", "_", Path(relative).stem)[:65]
        suffix = Path(relative).suffix.lower()
        target = f"reports/{'csv' if suffix == '.csv' else 'image'}/sweep_combined__{stem}__{identity}{suffix}"
        source_points = {p["index"] for p, _, _ in sources}
        row = dict(SourceRelativePath=relative, CombinedArtifact=target,
                   SourcePoints="|".join(str(p["index"]) for p, _, _ in sources),
                   MissingCompletedPoints="|".join(str(p["index"]) for p in progress["points"]
                       if p["status"] in {"passed", "failed"} and p["index"] not in source_points),
                   NotCompletedPoints="|".join(str(p["index"]) for p in progress["points"]
                       if p["status"] not in {"passed", "failed"}),
                   SourceSignature="", OutputSHA256="", Status="written", Error="",
                   EvidenceClass="cross_run_exact_rows" if suffix == ".csv" else "cross_run_labeled_original_raster_panels")
        prior = previous.get(relative, {})
        try:
            # Size/mtime are not content identity: a corrected measurement
            # can have the same byte count and preserved filesystem times.
            source_hashes = [(p["index"], _sch_source_sha256(f)) for p, f, _ in sources]
            signature = hashlib.sha256(json.dumps({
                "version": 3,
                "points": [(p["index"], p["label"], p["status"], p["configured_snr_db"])
                           for p in progress["points"]],
                "sources": source_hashes}, sort_keys=True).encode()).hexdigest()
            row["SourceSignature"] = signature
            output_hash = (_sch_source_sha256(root / target)
                           if io_path(root / target).is_file() else "")
            if not (prior.get("SourceSignature") == signature and prior.get("Status") == "written"
                    and output_hash and prior.get("OutputSHA256") == output_hash):
                if suffix == ".csv":
                    concatenate_csv(root / target, sources)
                else:
                    comparison_png(root / target, sources, progress["points"])
            # Do not receipt a source that changed during publication as an
            # immutable snapshot. The next call can retry the finished child.
            if source_hashes != [(p["index"], _sch_source_sha256(f)) for p, f, _ in sources]:
                raise ValueError("Child source content changed during comparative publication")
            row["OutputSHA256"] = _sch_source_sha256(root / target)
        except (OSError, ValueError, RuntimeError, csv.Error) as exc:
            row.update(Status="failed", Error=str(exc))
        manifest.append(row)
    fields = ["SourceRelativePath", "CombinedArtifact", "SourcePoints", "MissingCompletedPoints",
              "NotCompletedPoints", "SourceSignature", "OutputSHA256", "Status", "Error", "EvidenceClass"]
    write_csv(receipt_path, fields, manifest)
    export_overview(root, progress, save_images=save_images)
    measurement_manifest = export_standardized_measurement_curves(
        root, progress, save_images=save_images)
    _write_common_campaign_exports(root, progress, config, measurement_manifest,
                                   save_images=save_images)
    _annotate_parent_csv_frequency(
        root, config.get("frequency", {}).get("center_frequency_hz", ""))
    receipt = dict(UpdatedUTC=datetime.now(timezone.utc).isoformat(),
                   CompletedPoints=progress["completed"], TotalPoints=progress["total"],
                   ArtifactCount=len(manifest), FailedArtifacts=sum(r["Status"] == "failed" for r in manifest),
                   StandardizedMeasurementPlotCount=len(measurement_manifest),
                   Complete=progress["completed"] == progress["total"],
                   Note="Comparative publication only; failed PHY points remain failed. Pending/active points are not measured zeros.")
    atomic_write(root / "reports/sweep_comparison_receipt.json", lambda p: p.write_text(json.dumps(receipt, indent=2), encoding="utf-8"))
    return receipt
