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
            trials = read_rows(path, strict=True)
            crc = [number(r.get("CRCPass")) for r in trials]
            crc = [v for v in crc if v in (0, 1)]
            failures = sum(v == 0 for v in crc)
            ci_low, ci_high = wilson_interval(failures, len(crc))
            row.update(DataAvailability=("measured_rows_present" if trials else "source_present_empty"),
                       TrialCount=len(trials), CRCObservedCount=len(crc), FailureCount=failures,
                       AttemptBLER=(failures / len(crc) if crc else ""),
                       AttemptBLER_CI_Low=ci_low, AttemptBLER_CI_High=ci_high)
            for target, source in fields.items():
                values = [number(r.get(source)) for r in trials]
                values = [v for v in values if v is not None]
                row[target] = sum(values) / len(values) if values else ""
                row[target + "_Count"] = len(values)
            rows.append(row)
    columns = ["PointIndex", "Label", "ConfiguredSNR_dB", "PointStatus", "Direction",
               "DataAvailability", "TrialCount", "CRCObservedCount", "FailureCount", "AttemptBLER",
               "AttemptBLER_CI_Low", "AttemptBLER_CI_High", "SourceCSV"]
    columns += [item for field in fields for item in (field, field + "_Count")]
    write_csv(root / "reports/csv/sweep_link_comparison.csv", columns, rows)
    bler_columns = ["PointIndex", "Label", "ConfiguredSNR_dB", "PointStatus", "Direction",
                    "DataAvailability", "CRCObservedCount", "FailureCount", "AttemptBLER",
                    "AttemptBLER_CI_Low", "AttemptBLER_CI_High", "SourceCSV"]
    write_csv(root / "reports/csv/sweep_bler_vs_configured_snr.csv", bler_columns,
              [{field: row.get(field, "") for field in bler_columns} for row in rows])
    measured_bler_rows = measured_sinr_bler_rows(progress)
    measured_bler_columns = ["Direction", "MCSIndex", "Modulation", "Rank",
        "PostEqSINR_dB_BinCenter", "PostEqSINR_dB_BinMin", "PostEqSINR_dB_BinMax",
        "ObservedSINRMin_dB", "ObservedSINRMax_dB", "TrialCount", "FailureCount", "BLER",
        "BLER_CI_Low", "BLER_CI_High", "SourcePointIndices", "SourceConfiguredSNR_dB",
        "SourceCSVSet", "EvidenceClass"]
    write_csv(root / "reports/csv/sweep_bler_vs_measured_sinr.csv",
              measured_bler_columns, measured_bler_rows)
    if not save_images:
        return
    fig, axes = plt.subplots(2, 2, figsize=(13, 8), constrained_layout=True)
    for ax, (metric, label) in zip(axes.flat, [
        ("MeanMeasuredSINR_dB", "Mean measured trial SINR (dB)"),
        ("AttemptBLER", "CRC failure fraction (all recorded attempts)"),
        ("MeanAttemptGoodput_Mbps", "Mean per-attempt goodput (Mbps; not wall-clock rate)"),
        ("MeanExecutedLayers", "Mean executed layers (not capability)")]):
        available = False
        for direction in ("DL", "UL"):
            by_point = {r["PointIndex"]: r for r in rows if r["Direction"] == direction}
            xs = [p["configured_snr_db"] for p in progress["points"]]
            ys = [number(by_point.get(p["index"], {}).get(metric)) for p in progress["points"]]
            available = available or any(v is not None for v in ys)
            ax.plot(xs, [v if v is not None else math.nan for v in ys], "o-", label=direction)
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


def measured_sinr_bler_rows(progress):
    """Aggregate only CRC-observed trials on their receiver-measured SINR axis."""
    groups = {}
    for point in progress["points"]:
        if point["status"] not in {"passed", "failed"}:
            continue
        for direction, filename in (("DL", "dl_pdsch_trials.csv"), ("UL", "ul_pusch_trials.csv")):
            path = Path(point["run_folder"]) / "air_interface/csv" / filename
            if not io_path(path).is_file():
                continue
            for row in read_rows(path, strict=True):
                sinr = number(row.get("MeasuredTrialSINR_dB"))
                crc = number(row.get("CRCPass"))
                if sinr is None or crc not in (0, 1):
                    continue
                mcs = number(row.get("MCSIndex", row.get("MCS")))
                rank = number(row.get("Layers", row.get("RankIndicator", row.get("Rank"))))
                modulation = str(row.get("Modulation", "")).strip() or "unavailable"
                lower = math.floor(sinr)
                key = (direction, mcs, modulation, rank, lower)
                bucket = groups.setdefault(key, dict(sinr=[], crc=[], points=set(), snrs=set(), sources=set()))
                bucket["sinr"].append(sinr)
                bucket["crc"].append(crc)
                bucket["points"].add(point["index"])
                bucket["snrs"].add(point["configured_snr_db"])
                bucket["sources"].add(f"sweeps/{Path(point['run_folder']).name}/air_interface/csv/{filename}")
    rows = []
    for (direction, mcs, modulation, rank, lower), bucket in sorted(
            groups.items(), key=lambda item: (item[0][0], item[0][4], str(item[0][1]), item[0][2], str(item[0][3]))):
        count = len(bucket["crc"])
        failures = sum(value == 0 for value in bucket["crc"])
        ci_low, ci_high = wilson_interval(failures, count)
        rows.append(dict(Direction=direction, MCSIndex="" if mcs is None else mcs,
            Modulation=modulation, Rank="" if rank is None else rank,
            PostEqSINR_dB_BinCenter=lower + 0.5, PostEqSINR_dB_BinMin=lower,
            PostEqSINR_dB_BinMax=lower + 1, ObservedSINRMin_dB=min(bucket["sinr"]),
            ObservedSINRMax_dB=max(bucket["sinr"]), TrialCount=count, FailureCount=failures,
            BLER=failures / count, BLER_CI_Low=ci_low, BLER_CI_High=ci_high,
            SourcePointIndices="|".join(map(str, sorted(bucket["points"]))),
            SourceConfiguredSNR_dB="|".join(str(value) for value in sorted(bucket["snrs"])),
            SourceCSVSet="|".join(sorted(bucket["sources"])),
            EvidenceClass="cross_run_observed_crc_and_receiver_post_equalization_sinr"))
    return rows


def plot_configured_snr_bler(root, progress, rows):
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(9, 5), constrained_layout=True)
    for direction in ("DL", "UL"):
        indexed = {row["PointIndex"]: row for row in rows if row["Direction"] == direction}
        xs = [point["configured_snr_db"] for point in progress["points"]]
        ys = [number(indexed.get(point["index"], {}).get("AttemptBLER")) for point in progress["points"]]
        low = [number(indexed.get(point["index"], {}).get("AttemptBLER_CI_Low")) for point in progress["points"]]
        high = [number(indexed.get(point["index"], {}).get("AttemptBLER_CI_High")) for point in progress["points"]]
        y = [value if value is not None else math.nan for value in ys]
        lower_error = [(value - lo) if value is not None and lo is not None else math.nan
                       for value, lo in zip(ys, low)]
        upper_error = [(hi - value) if value is not None and hi is not None else math.nan
                       for value, hi in zip(ys, high)]
        ax.errorbar(xs, y, yerr=[lower_error, upper_error], marker="o", capsize=3, label=direction)
    ax.set(xlabel="Configured occupied-RE reference SNR (dB)", ylabel="Initial-attempt BLER",
           ylim=(-0.03, 1.03), title="Observed initial-attempt BLER vs configured SNR")
    ax.set_xticks([point["configured_snr_db"] for point in progress["points"]
                   if point["configured_snr_db"] is not None])
    ax.grid(True, alpha=0.25)
    ax.legend()
    ax.text(0.01, 0.01, "Gaps are unavailable populations; bars are 95% Wilson intervals.",
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
            key = (row["MCSIndex"], row["Modulation"], row["Rank"])
            series.setdefault(key, []).append(row)
        for key, values in sorted(series.items(), key=lambda item: str(item[0])):
            values.sort(key=lambda row: row["PostEqSINR_dB_BinCenter"])
            ax.plot([row["PostEqSINR_dB_BinCenter"] for row in values],
                    [row["BLER"] for row in values], "o-",
                    label=f"MCS {key[0]} | {key[1]} | rank {key[2]}")
        ax.set(xlabel="Receiver post-equalization SINR (dB)", ylabel="Initial-attempt BLER",
               ylim=(-0.03, 1.03), title=direction)
        ax.grid(True, alpha=0.25)
        if series:
            ax.legend(fontsize=7)
        else:
            ax.text(0.5, 0.5, "No CRC-observed trials with measured SINR.",
                    ha="center", va="center", transform=ax.transAxes)
    fig.suptitle("BLER vs measured SINR; populations separated by MCS, modulation and rank")
    atomic_write(root / "reports/image/sweep_bler_vs_measured_sinr.png",
                 lambda path: fig.savefig(path, dpi=300))
    plt.close(fig)


STANDARD_MEASUREMENT_FIELDS = [
    "CategoryCode", "CategoryKey", "CategoryName", "MetricKey", "MetricName",
    "Entity", "Statistic", "Availability", "CountsTowardCoverage",
    "ValueNumeric", "ValueText", "Unit", "SourceArtifact", "Notes",
]


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
    unavailable and non-finite rows remain in the availability ledger but are
    excluded from the measured-value table and plots.
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
                    if not set(STANDARD_MEASUREMENT_FIELDS).issubset(header):
                        continue
                    for source_row_index, source in enumerate(reader, 1):
                        row = {
                            "PointIndex": point["index"],
                            "Label": point["label"],
                            "ConfiguredSNR_dB": point["configured_snr_db"],
                            "PointStatus": point["status"],
                            **{field: source.get(field, "") for field in STANDARD_MEASUREMENT_FIELDS},
                            "SourceOutputTable": f"sweeps/{Path(point['run_folder']).name}/{relative}",
                            "SourceOutputRow": source_row_index,
                            "EvidenceClass": "runtime_published_standardized_measurement_row",
                        }
                        availability_rows.append(row)
                        value = number(source.get("ValueNumeric"))
                        if (str(source.get("Availability", "")).strip().lower() == "observed"
                                and _is_true(source.get("CountsTowardCoverage"))
                                and value is not None):
                            row = dict(row)
                            row["ValueNumeric"] = value
                            measured_rows.append(row)
            except (OSError, csv.Error):
                raise
    return availability_rows, measured_rows


def _plot_standardized_metric(path, progress, rows, title, unit):
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(figsize=(10, 5.8), constrained_layout=True)
    series = {}
    for row in rows:
        key = (str(row.get("Entity", "")).strip() or "all",
               str(row.get("Statistic", "")).strip() or "value")
        series.setdefault(key, {}).setdefault(float(row["ConfiguredSNR_dB"]), []).append(
            float(row["ValueNumeric"]))
    if len(series) <= 12:
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
    configured = sorted({point["configured_snr_db"] for point in progress["points"]
                         if point["configured_snr_db"] is not None})
    ax.set_xticks(configured)
    ax.set_xlabel("Configured occupied-RE reference SNR (dB)")
    ax.set_ylabel(unit or "Published measurement value")
    ax.set_title(title)
    ax.grid(True, alpha=0.25)
    if series:
        ax.legend(fontsize=7, loc="best")
    else:
        ax.text(0.5, 0.5, "No observed runtime-published values.",
                ha="center", va="center", transform=ax.transAxes)
    ax.text(0.01, 0.01,
            "Markers are per-point arithmetic means of matching published rows; shaded range is min-max. "
            "Exact rows are retained in the companion CSV; missing points are gaps.",
            transform=ax.transAxes, fontsize=8, va="bottom", wrap=True)
    atomic_write(path, lambda output: fig.savefig(output, dpi=300))
    plt.close(fig)


def export_standardized_measurement_curves(root, progress, *, save_images=True):
    """Publish one cross-point CSV/PNG per observed standardized metric."""
    availability, measured = standardized_measurement_rows(progress)
    fields = ["PointIndex", "Label", "ConfiguredSNR_dB", "PointStatus",
              *STANDARD_MEASUREMENT_FIELDS, "SourceOutputTable", "SourceOutputRow",
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
            "SeriesCount": len({(row.get("Entity", ""), row.get("Statistic", "")) for row in rows}),
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
    """Add the resolved carrier to every mutable parent campaign CSV."""
    for path in sorted((root / "reports/csv").rglob("*.csv")):
        rows = read_rows(path, strict=True)
        with path.open(encoding="utf-8-sig", newline="") as handle:
            fields = next(csv.reader(handle), [])
        if "CenterFrequencyHz" not in fields:
            fields = ["CenterFrequencyHz", *fields]
        for row in rows:
            row["CenterFrequencyHz"] = center_frequency_hz
        write_csv(path, fields, rows)


def _write_common_campaign_exports(root, progress, config, measurement_manifest, *, save_images=True):
    """Publish stable campaign-level names without inventing unavailable data."""
    out_csv = root / "reports/csv"
    out_image = root / "reports/image"
    center_frequency_hz = config.get("frequency", {}).get("center_frequency_hz", "")

    point_fields = list(progress["points"][0]) if progress["points"] else ["index"]
    write_csv(out_csv / "point_status.csv", ["CenterFrequencyHz", *point_fields], [
        {"CenterFrequencyHz": center_frequency_hz, **point} for point in progress["points"]
    ])

    _, measured = standardized_measurement_rows(progress)
    metric_fields = ["CenterFrequencyHz", "PointIndex", "Label", "ConfiguredSNR_dB",
                     "PointStatus", *STANDARD_MEASUREMENT_FIELDS, "SourceOutputTable",
                     "SourceOutputRow", "EvidenceClass"]
    write_csv(out_csv / "metrics_long.csv", metric_fields, [
        {"CenterFrequencyHz": center_frequency_hz, **row} for row in measured
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
    calibration_fields = ["CenterFrequencyHz", "PointIndex", "Label", "ConfiguredSNR_dB",
                          "PointStatus", "Direction", "DataAvailability",
                          "MeanMeasuredSINR_dB", "MeanMeasuredSINR_dB_Count", "SourceCSV"]
    write_csv(out_csv / "sinr_calibration.csv", calibration_fields, [
        {field: (center_frequency_hz if field == "CenterFrequencyHz" else row.get(field, ""))
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
        "ScopeBoundary": "terrestrial_single_carrier_tdd_fixed_4ghz_stage0",
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
        signature = hashlib.sha256(json.dumps({
            "version": 2,
            "points": [(p["index"], p["status"], p["configured_snr_db"]) for p in progress["points"]],
            "sources": [(p["index"], io_path(f).stat().st_size, io_path(f).stat().st_mtime_ns)
                        for p, f, _ in sources]}).encode()).hexdigest()
        source_points = {p["index"] for p, _, _ in sources}
        row = dict(SourceRelativePath=relative, CombinedArtifact=target,
                   SourcePoints="|".join(str(p["index"]) for p, _, _ in sources),
                   MissingCompletedPoints="|".join(str(p["index"]) for p in progress["points"]
                       if p["status"] in {"passed", "failed"} and p["index"] not in source_points),
                   NotCompletedPoints="|".join(str(p["index"]) for p in progress["points"]
                       if p["status"] not in {"passed", "failed"}),
                   SourceSignature=signature, Status="written", Error="",
                   EvidenceClass="cross_run_exact_rows" if suffix == ".csv" else "cross_run_labeled_original_raster_panels")
        prior = previous.get(relative, {})
        try:
            if not (prior.get("SourceSignature") == signature and prior.get("Status") == "written" and io_path(root / target).is_file()):
                if suffix == ".csv":
                    concatenate_csv(root / target, sources)
                else:
                    comparison_png(root / target, sources, progress["points"])
        except (OSError, ValueError, RuntimeError, csv.Error) as exc:
            row.update(Status="failed", Error=str(exc))
        manifest.append(row)
    fields = ["SourceRelativePath", "CombinedArtifact", "SourcePoints", "MissingCompletedPoints",
              "NotCompletedPoints", "SourceSignature", "Status", "Error", "EvidenceClass"]
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
