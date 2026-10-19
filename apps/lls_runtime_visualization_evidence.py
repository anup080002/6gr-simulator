"""Expose hash-verified run visualizations without upgrading component truth.

The three in-path component contracts and the browser's derived CSV/PNG
contracts are different evidence scopes. A plot is not a PHY pass verdict.
"""
from __future__ import annotations

import csv
import hashlib
import io
import json
import os
import re
from typing import Any, Callable


def verified_runtime_visualizations(
    artifacts: list[dict[str, Any]], read_bytes: Callable[[dict[str, Any]], bytes],
    *, run_folder: str = "",
) -> list[dict[str, Any]]:
    by_path: dict[str, dict[str, Any]] = {}
    for artifact in artifacts:
        path = str(artifact.get("logical_path") or "").replace("\\", "/")
        if not path or path.startswith("/") or ".." in path.split("/"):
            continue
        if path in by_path:
            return []  # Ambiguous membership is not publication authority.
        by_path[path] = artifact
    return (_verified_terminal_visualizations(by_path, read_bytes)
            + _verified_live_visualizations(by_path, read_bytes, run_folder))


def _verified_terminal_visualizations(by_path, read_bytes):
    receipt_path = "published/browser_publication_receipt.json"
    lineage_path = "reports/csv/contract_plot_lineage.csv"
    if receipt_path not in by_path or lineage_path not in by_path:
        return []
    try:
        receipt = json.loads(read_bytes(by_path[receipt_path]))
        if not (
            receipt.get("SchemaName") == "sixgr.browser_publication_receipt"
            and receipt.get("Status") == "PASS"
            and receipt.get("BrowserMaterialized") is True
            and receipt.get("MissingRequiredTableCount") == 0
            and receipt.get("MissingRequiredChartCount") == 0
            and receipt.get("MaterializerExitCode") == 0
            and receipt.get("RunID")
        ):
            return []
        lineage = list(csv.DictReader(io.StringIO(read_bytes(by_path[lineage_path]).decode("utf-8-sig"))))
    except (OSError, ValueError, KeyError, UnicodeError, csv.Error):
        return []
    selected: dict[str, dict[str, Any]] = {}
    digests: dict[str, str] = {}
    for row in lineage:
        if row.get("Status", "").lower() != "pass" or row.get("ProducerModule") != "apps.lls_contract_materializer":
            continue
        image = row.get("ImagePath", "")
        source = row.get("SourceCSV", "")
        if not (image.startswith(("reports/image/contract__", "analytics/image/contract__")) and image.endswith(".png")
                and source.startswith(("reports/csv/contract__", "analytics/csv/contract__")) and source.endswith(".csv")):
            continue
        pair = [(image, row.get("ImageSHA256", "")), (source, row.get("SourceCSV_SHA256", ""))]
        valid = True
        for path, expected in pair:
            if path not in by_path or not re.fullmatch(r"[0-9a-fA-F]{64}", expected):
                valid = False
                break
            try:
                if path not in digests:
                    digests[path] = hashlib.sha256(read_bytes(by_path[path])).hexdigest()
            except (OSError, ValueError, KeyError):
                valid = False
                break
            if digests[path] != expected.lower():
                valid = False
                break
        if not valid:
            continue  # Never expose a stale image or an unbound CSV on its own.
        for path, _ in pair:
            selected[path] = dict(by_path[path], evidence_scope="verified_runtime_visualization",
                                  source_csv=source, image_path=image,
                                  publication_run_id=receipt["RunID"], hash_verified=True)
    return list(selected.values())


def _verified_live_visualizations(by_path, read_bytes, run_folder):
    """Publish immutable measured checkpoints, never a terminal PHY verdict.

    The selected run's folder is mandatory. A post-run preview sourced from
    another run is not authority for the selected run, even if its hashes fit.
    Verify the plotted pair and its lineage, not the growing raw input CSVs.
    """
    latest = "reports/live_measurements/latest.json"
    if not run_folder or latest not in by_path:
        return []
    try:
        payload = read_bytes(by_path[latest])
        manifest = json.loads(payload)
        identity = lambda path: os.path.normcase(os.path.abspath(path))
        if (manifest.get("status") != "partial_runtime_measurement_snapshot"
                or manifest.get("terminal_qualification") is not False
                or not os.path.isabs(manifest.get("run_folder", ""))
                or identity(manifest["run_folder"]) != identity(run_folder)
                or identity(manifest.get("source_run_folder", "")) != identity(run_folder)):
            return []
        snapshot = manifest.get("snapshot", "")
        if not re.fullmatch(r"[0-9a-f]{64}", snapshot):
            return []
        key = hashlib.sha256(json.dumps({"sources": manifest["source_sha256"],
            "producers": manifest["producer_sha256"],
            "source_root": manifest["source_run_folder"], "preview": False},
            sort_keys=True).encode()).hexdigest()
        if key != snapshot:
            return []
        prefix = f"reports/live_measurements/{snapshot}/"
        if read_bytes(by_path[prefix + "manifest.json"]) != payload:
            return []
        hashes = manifest["artifact_sha256"]
        def verified_bytes(relative):
            if (not relative or relative.startswith(("/", "\\")) or ":" in relative
                    or "\\" in relative or any(p in ("..", ".", "") for p in relative.split("/"))):
                raise ValueError("Unsafe live artifact path")
            expected = hashes[relative]
            if not re.fullmatch(r"[0-9a-f]{64}", expected):
                raise ValueError("Missing live artifact digest")
            data = read_bytes(by_path[prefix + relative])
            if hashlib.sha256(data).hexdigest() != expected:
                raise ValueError("Changed live artifact")
            return data
        lineage = list(csv.DictReader(io.StringIO(
            verified_bytes("checkpoint_plot_lineage.csv").decode("utf-8-sig"))))
        pairs = {}
        for row in lineage:
            pair = (row.get("SourceCSV"), row.get("ImagePath"))
            if pair in pairs:
                return []
            pairs[pair] = row
        selected = {}
        for chart in manifest["charts"]:
            if chart.get("status") != "measured_checkpoint":
                continue
            source, image = chart["csv"], chart["png"]
            row = pairs.get((source, image), {})
            if (not source.startswith("csv/") or not source.endswith(".csv")
                    or not image.startswith("image/") or not image.endswith(".png")
                    or row.get("Status") != "rendered_component_plot"
                    or row.get("Producer") != "publish_lls_live_csv_plots"
                    or row.get("EvidenceScope") != "partial_measured_checkpoint"
                    or row.get("TerminalQualification") != "false"
                    or int(row.get("SourceRows", "0")) < 1
                    or row.get("SourceCSV_SHA256") != hashes.get(source)
                    or row.get("ImageSHA256") != hashes.get(image)):
                continue
            try:
                plotted = list(csv.DictReader(io.StringIO(verified_bytes(source).decode("utf-8-sig"))))
                verified_bytes(image)
                if len(plotted) != int(row["SourceRows"]):
                    continue
            except (OSError, ValueError, KeyError, UnicodeError, csv.Error):
                continue
            for relative in (source, image):
                path = prefix + relative
                selected[path] = dict(by_path[path], evidence_scope="verified_runtime_visualization",
                    source_csv=prefix + source, image_path=prefix + image, hash_verified=True,
                    publication_kind="partial_measured_checkpoint", terminal_qualification=False,
                    publication_snapshot=snapshot, measurement_name=chart["name"])
        return list(selected.values())
    except (OSError, ValueError, KeyError, TypeError, UnicodeError, csv.Error):
        return []
