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
                       "post-equalization constellation", "frame/slot/symbol occupancy timeline")
SOURCES = tuple(dict.fromkeys(radio.SOURCE_PATHS + (
    "reports/csv/live_re_allocation_snapshot.csv",
    "air_interface/csv/dl_constellation_samples.csv",
    "air_interface/csv/ul_constellation_samples.csv",
    "air_interface/csv/dl_constellation_preview.csv",
    "air_interface/csv/ul_constellation_preview.csv",
    "reports/csv/equalized_constellations.csv")))


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def file_digest(path):
    value = hashlib.sha256()
    with io_path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b""):
            value.update(chunk)
    return value.hexdigest()


def csv_data_row_count(path, logical):
    """Validate every record without retaining the input population."""
    with io_path(path).open("r", encoding="utf-8-sig", newline="") as stream:
        records = csv.reader(stream, strict=True)
        header = next(records, [])
        count = 0
        for row in records:
            if not row:
                continue
            if len(row) != len(header):
                raise ValueError(f"Malformed CSV record width: {logical}")
            count += 1
    return count


def _stat_identity(stat):
    # Windows path.stat()/descriptor fstat() can expose different ctime
    # meanings. Use file identity, size and modification time; the final
    # SHA256 comparison independently verifies the actual source bytes.
    return (stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns)


def snapshot_source(source, target, logical):
    """Copy/hash one source once; reject replacement or writes during copy."""
    source, target = io_path(source), io_path(target)
    before = _stat_identity(source.stat())
    target.parent.mkdir(parents=True, exist_ok=True)
    value, size = hashlib.sha256(), 0
    with source.open("rb") as reader, target.open("xb") as writer:
        if _stat_identity(os.fstat(reader.fileno())) != before:
            raise ValueError("Source changed before live snapshot: " + logical)
        for chunk in iter(lambda: reader.read(1024*1024), b""):
            writer.write(chunk)
            value.update(chunk)
            size += len(chunk)
        after = _stat_identity(os.fstat(reader.fileno()))
    if before != after or before != _stat_identity(source.stat()) or size != before[2]:
        raise ValueError("Source changed during live snapshot: " + logical)
    csv_data_row_count(target, logical)
    return value.hexdigest()


def source_path(root, logical):
    path = (root / logical).resolve()
    if not path.is_relative_to(root):
        raise ValueError(f"Source escapes active run: {logical}")
    return path


def available_sources(root):
    """Include exact scoring dependencies declared by the primary trials.

    The NMSE chart independently checks complex-channel operands and their
    hash; copying only its summary would make valid measurements invisible.
    Do not glob unrelated runs/resources or synthesize a missing dependency.
    """
    sources = {logical: source_path(root, logical) for logical in SOURCES
               if io_path(source_path(root, logical)).is_file()}
    references = set()
    for logical in radio.TRIALS + ("air_interface/csv/srs_trials.csv", radio.CSI_TRIALS):
        if logical not in sources:
            continue
        with io_path(sources[logical]).open(encoding="utf-8-sig", newline="") as stream:
            rows = csv.DictReader(stream, strict=True)
            if "ChannelEstimateResourcesCSV" not in (rows.fieldnames or []):
                continue
            for row in rows:
                reference = (row.get("ChannelEstimateResourcesCSV") or "").strip().replace("\\", "/")
                if not reference:
                    continue
                if (not reference.startswith("channel_estimation/csv/")
                        or not reference.endswith(".csv") or ":" in reference
                        or any(part in ("", ".", "..") for part in reference.split("/"))):
                    raise ValueError("Invalid channel NMSE resource path: " + reference)
                references.add(reference)
    for logical in sorted(references):
        path = source_path(root, logical)
        if io_path(path).is_file():
            sources[logical] = path
    return sources


def verify_sources(source_root, expected):
    # Also detect newly appearing inputs; a mixed checkpoint must not advance
    # latest.json merely because the files present at start stayed unchanged.
    sources = available_sources(source_root)
    if set(sources) != set(expected):
        raise ValueError("Source changed during live publication: input or scoring-resource inventory")
    for logical, path in sources.items():
        if file_digest(path) != expected[logical]:
            raise ValueError("Source changed during live publication: " + logical)


def atomic_write(path, payload):
    path = io_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".live-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            count, value = 0, hashlib.sha256()
            for chunk in materializer._payload_chunks(payload):
                stream.write(chunk)
                count += len(chunk)
                value.update(chunk)
        if (count != materializer._payload_size(payload)
                or value.hexdigest() != materializer._payload_sha256(payload)):
            raise ValueError("Live artifact changed during publication")
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def publish(run_folder, *, source_run_folder=None):
    root = Path(run_folder).resolve(strict=True)
    source_root = Path(source_run_folder).resolve(strict=True) if source_run_folder else root
    preview = source_root != root
    parent = root / "reports/live_measurements"
    io_path(parent).mkdir(parents=True, exist_ok=True)
    # A slot-complete poll often has no new radio measurement. Hash the
    # current bytes before staging: unchanged inputs must not be copied and
    # parsed again (a full-band paired-sample CSV can exceed 600 MB).
    latest = parent / "latest.json"
    if io_path(latest).is_file():
        prior = json.loads(io_path(latest).read_text(encoding="utf-8"))
        current = {logical: file_digest(path) for logical, path in available_sources(source_root).items()}
        if (prior.get("source_sha256") == current and prior.get("producer_sha256") == producer_hashes()
                and prior.get("run_folder") == str(root) and prior.get("source_run_folder") == str(source_root)):
            snapshot = prior.get("snapshot", "")
            if not re.fullmatch(r"[0-9a-f]{64}", snapshot):
                raise ValueError("Live snapshot receipt mismatch: snapshot identity")
            folder = parent / snapshot
            manifest_path = folder / "manifest.json"
            if (io_path(manifest_path).read_bytes() != io_path(latest).read_bytes()
                    or prior.get("terminal_qualification") is not False):
                raise ValueError("Live snapshot receipt mismatch: latest manifest")
            for logical, expected in prior["artifact_sha256"].items():
                target = (folder / logical).resolve()
                if not target.is_relative_to(folder.resolve()) or file_digest(target) != expected:
                    raise ValueError("Live snapshot receipt mismatch: " + logical)
            verify_sources(source_root, current)
            return {"Status": "unchanged_verified_snapshot", "Manifest": str(manifest_path),
                    "CreatedCount": prior["png_count"]}
    # Staging is private and on the destination volume. Only a fully verified
    # directory becomes an immutable checkpoint; failed input never replaces
    # latest.json or leaves a partial checkpoint pretending to be complete.
    with tempfile.TemporaryDirectory(prefix=".live-stage-", dir=io_path(parent)) as work:
        stage = Path(work) / "snapshot"
        stage.mkdir()
        return publish_snapshot(root, source_root, preview, stage)


def producer_hashes():
    return {str(p.relative_to(REPO)).replace("\\", "/"): file_digest(p) for p in (
        Path(__file__).resolve(), REPO / "apps/lls_contract_materializer.py",
        REPO / "apps/lls_radio_measurement_plots.py", REPO / "apps/lls_resource_occupancy_plots.py",
        REPO / "scripts/regenerate_lls_rasters_from_csv.py")}


def reuse_unchanged_charts(root, source_root, preview, sources, producers, stage):
    """Reuse plotted bytes only when the chart's full input closure is unchanged.

    A new occupancy row must not reparse a million unchanged CSI-RS pairs.
    Nor should a new data row redraw unchanged access/CSI charts. Charts
    without an explicit dependency contract are rebuilt. Independent NMSE
    operands include dynamically referenced channel-estimate CSVs.
    No sample thinning, estimator change, or reuse across a producer edit.
    """
    latest = root / "reports/live_measurements/latest.json"
    if not io_path(latest).is_file():
        return {}, {}
    data = io_path(latest).read_bytes()
    prior = json.loads(data)
    if (prior.get("producer_sha256") != producers or prior.get("run_folder") != str(root)
            or prior.get("source_run_folder") != str(source_root)
            or prior.get("status") != ("post_run_diagnostic_preview" if preview else
                                       "partial_runtime_measurement_snapshot")):
        return {}, {}
    key = digest(json.dumps({"sources": prior["source_sha256"], "producers": producers,
                             "source_root": str(source_root), "preview": preview}, sort_keys=True).encode())
    folder = latest.parent / key
    if (prior.get("snapshot") != key or prior.get("terminal_qualification") is not False
            or io_path(folder / "manifest.json").read_bytes() != data):
        raise ValueError("Live snapshot receipt mismatch: EVM reuse identity")
    rows, hashes = {}, {}
    for row in prior["charts"]:
        name = row["name"]
        if name not in radio.CHART_SOURCES or row.get("status") != "measured_checkpoint":
            continue
        dependencies = set(radio.CHART_SOURCES[name])
        # Conservative closure: every retained complex-channel operand is
        # included, not only the summary CSV that names it. Presence/absence
        # changes also invalidate reuse.
        if name in ("NMSE vs SNR / SINR", radio.TRS_NMSE_CHART):
            dependencies.update(p for p in set(sources) | set(prior["source_sha256"])
                                if p.startswith("channel_estimation/csv/"))
        if any(sources.get(p) != prior["source_sha256"].get(p) for p in dependencies):
            continue
        for field, extension in (("csv", ".csv"), ("png", ".png")):
            logical = row[field]
            target = (folder / logical).resolve()
            if not target.is_relative_to(folder.resolve()) or target.suffix != extension:
                raise ValueError("Live snapshot receipt mismatch: EVM reuse path")
            payload = io_path(target).read_bytes()
            expected = prior["artifact_sha256"][logical]
            if digest(payload) != expected:
                raise ValueError("Live snapshot receipt mismatch: " + logical)
            atomic_write(stage / logical, payload)
            hashes[logical] = expected
        rows[name] = dict(row)
    return rows, hashes


def verified_prior_inputs(root, source_root, preview):
    """Validate the sealed previous snapshot before sharing immutable bytes.

    Only prior snapshot files may be linked, never mutable run measurements.
    Changed producers may reuse exact input bytes, but not old plotted output.
    """
    latest = root / "reports/live_measurements/latest.json"
    if not io_path(latest).is_file():
        return {}
    encoded = io_path(latest).read_bytes()
    prior = json.loads(encoded)
    if prior.get("run_folder") != str(root) or prior.get("source_run_folder") != str(source_root):
        return {}
    key = digest(json.dumps({"sources": prior["source_sha256"], "producers": prior["producer_sha256"],
                            "source_root": str(source_root), "preview": preview}, sort_keys=True).encode())
    folder = latest.parent / key
    if (prior.get("snapshot") != key or prior.get("terminal_qualification") is not False
            or io_path(folder / "manifest.json").read_bytes() != encoded):
        raise ValueError("Live snapshot receipt mismatch: immutable input identity")
    for logical, expected in prior["artifact_sha256"].items():
        target = (folder / logical).resolve()
        if not target.is_relative_to(folder.resolve()) or file_digest(target) != expected:
            raise ValueError("Live snapshot receipt mismatch: " + logical)
    inputs = {}
    for logical, expected in prior["source_sha256"].items():
        if prior["artifact_sha256"].get("sources/" + logical) != expected:
            raise ValueError("Live snapshot receipt mismatch: source hash " + logical)
        target = (folder / "sources" / logical).resolve()
        if not target.is_relative_to((folder / "sources").resolve()):
            raise ValueError("Live snapshot receipt mismatch: source path " + logical)
        primary = source_path(source_root, logical)
        if io_path(primary).exists() and os.path.samefile(io_path(primary), io_path(target)):
            raise ValueError("Live snapshot receipt mismatch: mutable primary linked as immutable input")
        inputs[logical] = (target, expected)
    return inputs


def retain_immutable_input(retained, target, expected, logical):
    """Share verified immutable data, with an exact copy on unsupported filesystems."""
    target = io_path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(io_path(retained), target)
    except OSError:
        # Do not overwrite an existing/unverified target on a link failure.
        if target.exists():
            raise
        actual = snapshot_source(retained, target, logical)
    else:
        actual = file_digest(target)
    if actual != expected:
        raise ValueError("Live snapshot receipt mismatch: retained input " + logical)
    return actual


def publish_snapshot(root, source_root, preview, stage):
    prior_inputs = verified_prior_inputs(root, source_root, preview)
    source_hashes, snapshots = {}, {}
    for logical, path in available_sources(source_root).items():
        snapshot = stage / "sources" / logical
        retained = prior_inputs.get(logical)
        if retained and file_digest(path) == retained[1]:
            source_hashes[logical] = retain_immutable_input(retained[0], snapshot, retained[1], logical)
        else:
            source_hashes[logical] = snapshot_source(path, snapshot, logical)
        snapshots[logical] = snapshot
    producers = producer_hashes()
    key = digest(json.dumps({"sources": source_hashes, "producers": producers,
                            "source_root": str(source_root), "preview": preview}, sort_keys=True).encode())
    folder = root / "reports/live_measurements" / key
    if not folder.resolve().is_relative_to(root):
        raise ValueError("Live output escapes run folder")
    manifest_path = folder / "manifest.json"
    latest = root / "reports/live_measurements/latest.json"
    if io_path(manifest_path).is_file():
        manifest = json.loads(io_path(manifest_path).read_text(encoding="utf-8"))
        if (manifest.get("source_sha256") != source_hashes or
                manifest.get("producer_sha256") != producers or manifest.get("snapshot") != key or
                manifest.get("terminal_qualification") is not False or
                any(manifest.get("artifact_sha256", {}).get("sources/" + logical) != expected
                    for logical, expected in source_hashes.items())):
            raise ValueError("Live snapshot receipt mismatch: manifest source identity")
        # Check receipts, not just existence, before reusing a snapshot.
        for logical, expected in manifest["artifact_sha256"].items():
            target = (folder / logical).resolve()
            if not target.is_relative_to(folder.resolve()) or file_digest(target) != expected:
                raise ValueError("Live snapshot receipt mismatch: " + logical)
        verify_sources(source_root, source_hashes)
        atomic_write(latest, io_path(manifest_path).read_bytes())
        return {"Status": "unchanged_verified_snapshot", "Manifest": str(manifest_path),
                "CreatedCount": manifest["png_count"]}
    existing = {path: {"artifact_id": n} for n, path in enumerate(snapshots)}
    snapshot_paths = tuple(snapshots.values())
    def fetch(artifact_id):
        # Legacy small-table consumers may still request bytes; never cache
        # all sources together. Sample-volume EVM uses the opener below.
        return io_path(snapshot_paths[artifact_id]).read_bytes()
    def open_artifact_binary(artifact_id):
        return io_path(snapshot_paths[artifact_id]).open("rb")
    fetch.open_artifact_binary = open_artifact_binary
    reused, hashes = reuse_unchanged_charts(root, source_root, preview, source_hashes, producers, stage)
    charts = []
    for name in CHARTS:
        if name in reused:
            charts.append(reused[name])
            continue
        result = materializer._specialized_chart_materialization(name, existing, fetch, root.name)
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
        csv_payload = result["csv_file"] if "csv_file" in result else result["csv_bytes"]
        for logical, data in ((f"csv/{stem}.csv", csv_payload), (f"image/{stem}.png", png)):
            atomic_write(stage / logical, data)
            hashes[logical] = materializer._payload_sha256(data)
        row.update(status="measured_checkpoint", csv=f"csv/{stem}.csv", png=f"image/{stem}.png")
        charts.append(row)
    # Preserve the exact input bytes. Later source updates cannot invalidate
    # the scientific meaning of an earlier checkpoint or its reconciliation.
    for path, expected in source_hashes.items():
        hashes["sources/" + path] = expected
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
        plotted_count = csv_data_row_count(stage / chart["csv"], chart["csv"])
        writer.writerow({"PlotId": f"live_{key}_{Path(chart['png']).stem}",
                         "ImagePath": chart["png"], "SourceCSV": chart["csv"],
                         "SourceCSV_SHA256": hashes[chart["csv"]], "ImageSHA256": hashes[chart["png"]],
                         "Status": "rendered_component_plot", "Producer": "publish_lls_live_csv_plots",
                         "SourceRows": plotted_count, "EvidenceScope": "partial_measured_checkpoint",
                         "TerminalQualification": "false"})
    if any(chart["status"] == "measured_checkpoint" for chart in charts):
        logical = "checkpoint_plot_lineage.csv"
        data = lineage.getvalue().encode("utf-8")
        atomic_write(stage / logical, data)
        hashes[logical] = digest(data)
    # Single MATLAB owner is synchronous; detect any concurrent source edit.
    verify_sources(source_root, source_hashes)
    if producer_hashes() != producers:
        raise ValueError("Producer changed during live publication")
    manifest = {"status": "post_run_diagnostic_preview" if preview else "partial_runtime_measurement_snapshot",
                "run_folder": str(root), "source_run_folder": str(source_root),
                "snapshot": key, "created_utc": datetime.now(timezone.utc).isoformat(),
                "source_sha256": source_hashes, "producer_sha256": producers,
                "artifact_sha256": hashes, "charts": charts,
                "png_count": sum(c["status"] == "measured_checkpoint" for c in charts),
                "terminal_qualification": False}
    encoded = json.dumps(manifest, indent=2, allow_nan=False).encode()
    atomic_write(stage / "manifest.json", encoded)
    if io_path(folder).exists():
        raise ValueError("Unverified live snapshot already exists; preserve it: " + str(folder))
    os.rename(io_path(stage), io_path(folder))
    atomic_write(latest, encoded)
    return {"Status": manifest["status"], "Manifest": str(manifest_path), "CreatedCount": manifest["png_count"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-folder", type=Path, required=True)
    parser.add_argument("--source-run-folder", type=Path,
                        help="Read-only original run for an explicitly labelled post-run diagnostic preview.")
    args = parser.parse_args()
    print(json.dumps(publish(args.run_folder, source_run_folder=args.source_run_folder)))
