"""Expose hash-verified run visualizations without upgrading component truth.

The three in-path component contracts and the browser's derived CSV/PNG
contracts are different evidence scopes. A plot is not a PHY pass verdict.
"""
from __future__ import annotations

import csv
import hashlib
import io
import json
import re
from typing import Any, Callable


def verified_runtime_visualizations(
    artifacts: list[dict[str, Any]], read_bytes: Callable[[dict[str, Any]], bytes]
) -> list[dict[str, Any]]:
    by_path: dict[str, dict[str, Any]] = {}
    for artifact in artifacts:
        path = str(artifact.get("logical_path") or "").replace("\\", "/")
        if not path or path.startswith("/") or ".." in path.split("/"):
            continue
        if path in by_path:
            return []  # Ambiguous membership is not publication authority.
        by_path[path] = artifact
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
