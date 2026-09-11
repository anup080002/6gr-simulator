"""Publish non-terminal measured CSV/PNG snapshots, without finalizing a run."""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from datetime import datetime, timezone

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "apps"))
import lls_contract_materializer as materializer
import lls_radio_measurement_plots as radio
from regenerate_lls_rasters_from_csv import io_path

CHARTS = radio.CHARTS + ("throughput vs SINR", "PDSCH EVM per symbol", "PUSCH EVM per symbol",
                       "frame/slot/symbol occupancy timeline")
SOURCES = tuple(dict.fromkeys(radio.SOURCE_PATHS + (
    "reports/csv/live_re_allocation_snapshot.csv",
    "air_interface/csv/dl_constellation_samples.csv",
    "air_interface/csv/ul_constellation_samples.csv",
    "air_interface/csv/dl_constellation_preview.csv",
    "air_interface/csv/ul_constellation_preview.csv",
    "reports/csv/equalized_constellations.csv")))


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def atomic_write(path, payload):
    path = io_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".live-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def publish(run_folder, *, source_run_folder=None):
    root = Path(run_folder).resolve(strict=True)
    source_root = Path(source_run_folder).resolve(strict=True) if source_run_folder else root
    preview = source_root != root
    payloads, source_hashes = {}, {}
    for logical in SOURCES:
        path = (source_root / logical).resolve()
        if not path.is_relative_to(source_root):
            raise ValueError(f"Source escapes active run: {logical}")
        if io_path(path).is_file():
            data = io_path(path).read_bytes()
            # Do not let a torn or malformed CSV become a runtime chart.
            records = list(csv.reader(io.StringIO(data.decode("utf-8-sig")), strict=True))
            if records and any(len(row) != len(records[0]) for row in records[1:] if row):
                raise ValueError(f"Malformed CSV record width: {logical}")
            payloads[logical] = data
            source_hashes[logical] = digest(data)
    producers = {str(p.relative_to(REPO)).replace("\\", "/"): digest(p.read_bytes()) for p in (
        Path(__file__).resolve(), REPO / "apps/lls_contract_materializer.py",
        REPO / "apps/lls_radio_measurement_plots.py", REPO / "apps/lls_resource_occupancy_plots.py",
        REPO / "scripts/regenerate_lls_rasters_from_csv.py")}
    key = digest(json.dumps({"sources": source_hashes, "producers": producers,
                            "source_root": str(source_root), "preview": preview}, sort_keys=True).encode())
    folder = root / "reports/live_measurements" / key
    if not folder.resolve().is_relative_to(root):
        raise ValueError("Live output escapes run folder")
    manifest_path = folder / "manifest.json"
    latest = root / "reports/live_measurements/latest.json"
    if io_path(manifest_path).is_file():
        manifest = json.loads(io_path(manifest_path).read_text(encoding="utf-8"))
        # Check receipts, not just existence, before reusing a snapshot.
        for logical, expected in manifest["artifact_sha256"].items():
            target = (folder / logical).resolve()
            if not target.is_relative_to(folder.resolve()) or digest(io_path(target).read_bytes()) != expected:
                raise ValueError("Live snapshot receipt mismatch: " + logical)
        atomic_write(latest, io_path(manifest_path).read_bytes())
        return {"Status": "unchanged_verified_snapshot", "Manifest": str(manifest_path),
                "CreatedCount": manifest["png_count"]}
    existing = {path: {"artifact_id": n} for n, path in enumerate(payloads)}
    buffers = list(payloads.values())
    hashes, charts = {}, []
    for name in CHARTS:
        result = materializer._specialized_chart_materialization(name, existing, buffers.__getitem__, root.name)
        if result is None:
            raise ValueError("No source-bound builder for " + name)
        row = {"name": name, "source_paths": result.get("source_table_path", ""),
               "source_row_count": result.get("source_row_count", 0), "note": result.get("note", "")}
        if result.get("csv_status") == "unavailable_exact_reason" or not row["source_row_count"]:
            row["status"] = "unavailable_at_checkpoint"
            charts.append(row)
            continue  # No primary reason rows or fake reason-card PNGs.
        if "unavailable" in str(result.get("image_status", "")):
            raise ValueError("Available rows contradict unavailable image: " + name)
        # Caption explicitly identifies a checkpoint, not a final/swept result.
        svg = result["img_bytes"].decode("utf-8")
        caption = "POST-RUN PREVIEW" if preview else "LIVE CHECKPOINT"
        svg = svg.replace("</svg>", '<text x="12" y="18" font-size="11" fill="#222">'
                          + caption + ' — partial measured evidence; not final qualification</text></svg>')
        png = materializer._rasterize_contract_png(svg.encode(), source_mime_type="image/svg+xml")
        stem = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
        for logical, data in ((f"csv/{stem}.csv", result["csv_bytes"]), (f"image/{stem}.png", png)):
            atomic_write(folder / logical, data)
            hashes[logical] = digest(data)
        row.update(status="measured_checkpoint", csv=f"csv/{stem}.csv", png=f"image/{stem}.png")
        charts.append(row)
    # Preserve the exact input bytes. Later source updates cannot invalidate
    # the scientific meaning of an earlier checkpoint or its reconciliation.
    for path, data in payloads.items():
        logical = "sources/" + path
        atomic_write(folder / logical, data)
        hashes[logical] = digest(data)
    # The terminal auditor recursively consumes component plot ledgers.
    # Register each immutable checkpoint against its OWN plotted CSV bytes,
    # never the mutable latest run CSV or another snapshot's raster.
    lineage = io.StringIO(newline="")
    fields = ["PlotId", "ImagePath", "SourceCSV", "SourceCSV_SHA256", "ImageSHA256",
              "Status", "Producer", "SourceRows", "EvidenceScope", "TerminalQualification"]
    writer = csv.DictWriter(lineage, fieldnames=fields)
    writer.writeheader()
    for chart in charts:
        if chart["status"] != "measured_checkpoint":
            continue
        plotted = list(csv.reader(io.StringIO(io_path(folder / chart["csv"]).read_text(encoding="utf-8-sig"))))
        writer.writerow({"PlotId": f"live_{key}_{Path(chart['png']).stem}",
                         "ImagePath": chart["png"], "SourceCSV": chart["csv"],
                         "SourceCSV_SHA256": hashes[chart["csv"]], "ImageSHA256": hashes[chart["png"]],
                         "Status": "rendered_component_plot", "Producer": "publish_lls_live_csv_plots",
                         "SourceRows": max(0, len(plotted) - 1), "EvidenceScope": "partial_measured_checkpoint",
                         "TerminalQualification": "false"})
    if any(chart["status"] == "measured_checkpoint" for chart in charts):
        logical = "checkpoint_plot_lineage.csv"
        data = lineage.getvalue().encode("utf-8")
        atomic_write(folder / logical, data)
        hashes[logical] = digest(data)
    # Single MATLAB owner is synchronous; detect any concurrent source edit.
    for path, expected in source_hashes.items():
        if digest(io_path(source_root / path).read_bytes()) != expected:
            raise ValueError("Source changed during live publication: " + path)
    manifest = {"status": "post_run_diagnostic_preview" if preview else "partial_runtime_measurement_snapshot",
                "run_folder": str(root), "source_run_folder": str(source_root),
                "snapshot": key, "created_utc": datetime.now(timezone.utc).isoformat(),
                "source_sha256": source_hashes, "producer_sha256": producers,
                "artifact_sha256": hashes, "charts": charts,
                "png_count": sum(c["status"] == "measured_checkpoint" for c in charts),
                "terminal_qualification": False}
    encoded = json.dumps(manifest, indent=2, allow_nan=False).encode()
    atomic_write(manifest_path, encoded)
    atomic_write(latest, encoded)
    return {"Status": manifest["status"], "Manifest": str(manifest_path), "CreatedCount": manifest["png_count"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-folder", type=Path, required=True)
    parser.add_argument("--source-run-folder", type=Path,
                        help="Read-only original run for an explicitly labelled post-run diagnostic preview.")
    args = parser.parse_args()
    print(json.dumps(publish(args.run_folder, source_run_folder=args.source_run_folder)))
