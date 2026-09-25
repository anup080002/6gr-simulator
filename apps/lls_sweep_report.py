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
        if point["status"] not in {"passed", "failed"}:
            continue
        for direction, filename in (("DL", "dl_pdsch_trials.csv"), ("UL", "ul_pusch_trials.csv")):
            path = Path(point["run_folder"]) / "air_interface/csv" / filename
            if not io_path(path).is_file():
                continue
            trials = read_rows(path, strict=True)
            crc = [number(r.get("CRCPass")) for r in trials]
            crc = [v for v in crc if v in (0, 1)]
            row = dict(PointIndex=point["index"], Label=point["label"],
                       ConfiguredSNR_dB=point["configured_snr_db"], PointStatus=point["status"],
                       Direction=direction, TrialCount=len(trials), CRCObservedCount=len(crc),
                       AttemptBLER=(sum(v == 0 for v in crc) / len(crc) if crc else ""),
                       SourceCSV=f"sweeps/{path.parents[2].name}/air_interface/csv/{filename}")
            for target, source in fields.items():
                values = [number(r.get(source)) for r in trials]
                values = [v for v in values if v is not None]
                row[target] = sum(values) / len(values) if values else ""
                row[target + "_Count"] = len(values)
            rows.append(row)
    columns = ["PointIndex", "Label", "ConfiguredSNR_dB", "PointStatus", "Direction", "TrialCount",
               "CRCObservedCount", "AttemptBLER", "SourceCSV"]
    columns += [item for field in fields for item in (field, field + "_Count")]
    write_csv(root / "reports/csv/sweep_link_comparison.csv", columns, rows)
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
    atomic_write(root / "reports/image/sweep_link_comparison.png", lambda p: fig.savefig(p, dpi=140))
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
    receipt = dict(UpdatedUTC=datetime.now(timezone.utc).isoformat(),
                   CompletedPoints=progress["completed"], TotalPoints=progress["total"],
                   ArtifactCount=len(manifest), FailedArtifacts=sum(r["Status"] == "failed" for r in manifest),
                   Complete=progress["completed"] == progress["total"],
                   Note="Comparative publication only; failed PHY points remain failed. Pending/active points are not measured zeros.")
    atomic_write(root / "reports/sweep_comparison_receipt.json", lambda p: p.write_text(json.dumps(receipt, indent=2), encoding="utf-8"))
    return receipt
