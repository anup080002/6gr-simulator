from __future__ import annotations

"""Replace one LLS run's raster tree with CSV-derived scientific charts.

The command is intentionally fail-closed and destructive only inside one
validated ``results/lls/<scenario>/<run>`` folder.  It first proves that the
primary runtime CSV semantics pass, inventories every old raster, removes
those rasters, forces the canonical browser contract materializer to rebuild
eligible PNG charts from exact CSV sources, verifies chart lineage, and then
publishes hash-identical component-facing mirrors.

No placeholder/reason-card image is generated.  A chart without sufficient
runtime samples remains policy-disabled in contract coverage.
"""

import argparse
import csv
import hashlib
import json
import os
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Callable

from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[1]
TOOLS_ROOT = REPO_ROOT / "tools"
APPS_ROOT = REPO_ROOT / "apps"
sys.path.insert(0, str(TOOLS_ROOT))
sys.path.insert(0, str(APPS_ROOT))

from lls_csv_semantics import audit_run  # noqa: E402
import lls_contract_materializer as contract_materializer  # noqa: E402


RASTER_SUFFIXES = {".png", ".jpg", ".jpeg"}
COMPONENTS = (
    "prach",
    "initial_access",
    "ssb",
    "pdcch",
    "pdsch",
    "pusch",
    "pucch",
    "reference_signals",
    "mimo",
    "frame_grid",
    "l2",
    "waveform",
    "l3",
    "channel",
    "rf",
    "mac_harq_scheduler",
    "traffic",
    "validation",
)


COMPONENT_RUN_AUTHORITY: dict[str, tuple[str, ...]] = {
    "pdcch_blind_decode_sweep": ("air_interface/csv/pdcch_trials.csv",),
    "pdcch_strict_validation": ("air_interface/csv/pdcch_trials.csv",),
    "ctrl6gr_pdcch_study": ("air_interface/csv/pdcch_trials.csv",),
    "prach_detection": ("air_interface/csv/prach_trials.csv",),
    "prach_strict_validation": ("air_interface/csv/prach_trials.csv",),
    "srs_strict_validation": ("air_interface/csv/srs_trials.csv",),
    "trs_strict_validation": ("air_interface/csv/trs_trials.csv",),
}


def io_path(path: Path) -> Path:
    """Return an extended-length Windows path for all filesystem I/O."""

    resolved = path.resolve()
    raw = str(resolved)
    if os.name == "nt" and not raw.startswith("\\\\?\\"):
        raw = "\\\\?\\" + raw
    return Path(raw)


def iter_files(root: Path):
    """Yield normal-form paths while traversing with Windows long-path I/O."""

    normal_root = root.resolve()
    extended_root = io_path(normal_root)
    for current, _directories, filenames in os.walk(extended_root):
        current_path = Path(current)
        relative_directory = current_path.relative_to(extended_root)
        for filename in filenames:
            yield normal_root / relative_directory / filename


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with io_path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str]) -> None:
    io_path(path.parent).mkdir(parents=True, exist_ok=True)
    with io_path(path).open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def read_csv(path: Path) -> list[dict[str, str]]:
    with io_path(path).open("r", encoding="utf-8-sig", newline="") as handle:
        return [dict(row) for row in csv.DictReader(handle)]


def read_csv_shape(path: Path) -> tuple[int, int]:
    with io_path(path).open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        header = list(reader.fieldnames or [])
        row_count = sum(1 for _row in reader)
    return row_count, len(header)


def _run_relative_path(run_root: Path, value: str) -> Path:
    """Resolve one manifest path while refusing absolute/traversal targets."""

    relative = Path(str(value or "").strip().replace("\\", "/"))
    if not str(relative) or relative.is_absolute():
        raise RuntimeError(f"Invalid run-relative component mirror path: {value!r}")
    resolved = (run_root / relative).resolve()
    try:
        resolved.relative_to(run_root.resolve())
    except ValueError as error:
        raise RuntimeError(f"Component mirror path escapes run root: {value!r}") from error
    return resolved


def _canonical_run_identity(run_root: Path) -> dict[str, str]:
    """Return nonblank identity from the run's canonical scenario summary."""

    summary_path = run_root / "reports" / "csv" / "scenario_summary.csv"
    rows = read_csv(summary_path) if io_path(summary_path).is_file() else []
    row = rows[0] if rows else {}
    identity = {
        "ScenarioID": str(row.get("ScenarioID", "")).strip(),
        "ConfigHash": str(row.get("ConfigHash", "")).strip(),
        "RunnerProfile": str(row.get("RunnerProfile", "")).strip(),
    }
    if not identity["ScenarioID"]:
        raise RuntimeError("Canonical scenario summary does not contain ScenarioID.")
    config_hash = identity["ConfigHash"]
    if len(config_hash) != 64 or any(ch not in "0123456789abcdefABCDEF" for ch in config_hash):
        raise RuntimeError("Canonical scenario summary does not contain a SHA-256 ConfigHash.")
    if not identity["RunnerProfile"]:
        raise RuntimeError("Canonical scenario summary does not contain RunnerProfile.")
    return identity


def _rebuild_artifact_generation_summary(
    run_root: Path,
    result_rows: list[dict[str, str]],
) -> None:
    summary_path = run_root / "artifact_generation" / "artifact_generation_summary.csv"
    fieldnames = [
        "Domain", "Component", "Profile", "ArtifactType", "ContractCount",
        "RequiredCount", "GeneratedCount", "MissingCount", "FailedCount",
        "RequiredFailureCount", "SourceRowCount", "PublishedByteCount", "Status",
    ]
    grouped: dict[tuple[str, str, str, str], list[dict[str, str]]] = {}
    for row in result_rows:
        key = tuple(str(row.get(name, "")) for name in (
            "Domain", "Component", "Profile", "ArtifactType"
        ))
        grouped.setdefault(key, []).append(row)
    summaries: list[dict[str, Any]] = []
    for key in sorted(grouped):
        rows = grouped[key]
        required = [row for row in rows if str(row.get("Required", "")).strip().lower() in {
            "1", "true", "yes"
        }]
        generated = [row for row in rows if str(row.get("Status", "")).strip().upper() == "PASS"]
        missing = [row for row in rows if str(row.get("Status", "")).strip().upper() == "MISSING"]
        failed = [row for row in rows if str(row.get("Status", "")).strip().upper() not in {
            "PASS", "MISSING"
        }]
        required_failures = [row for row in required if str(row.get("Status", "")).strip().upper() != "PASS"]
        summaries.append({
            "Domain": key[0], "Component": key[1], "Profile": key[2],
            "ArtifactType": key[3], "ContractCount": len(rows),
            "RequiredCount": len(required), "GeneratedCount": len(generated),
            "MissingCount": len(missing), "FailedCount": len(failed),
            "RequiredFailureCount": len(required_failures),
            "SourceRowCount": sum(int(float(str(row.get("SourceRows", "0") or 0))) for row in rows),
            "PublishedByteCount": sum(int(float(str(row.get("ByteSize", "0") or 0))) for row in generated),
            "Status": "PASS" if not required_failures else "FAIL",
        })
    write_csv(summary_path, summaries, fieldnames)


def _prune_csv_rows(
    path: Path,
    predicate: Callable[[dict[str, str]], bool],
    *,
    delete_when_empty: bool = False,
) -> int:
    if not io_path(path).is_file():
        return 0
    with io_path(path).open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = list(reader.fieldnames or [])
        rows = [dict(row) for row in reader]
    kept = [row for row in rows if not predicate(row)]
    removed = len(rows) - len(kept)
    if not removed:
        return 0
    if delete_when_empty and not kept:
        io_path(path).unlink()
    else:
        write_csv(path, kept, fieldnames)
    return removed


def _delete_header_only_csv(path: Path) -> None:
    if io_path(path).is_file() and read_csv_shape(path)[0] == 0:
        io_path(path).unlink()


def retire_runtime_artifact_engine_rasters(run_root: Path) -> list[dict[str, str]]:
    """Remove obsolete in-path raster contracts and their metadata rows.

    Only contracts explicitly tagged ``runtime_in_path`` may be migrated.
    Phase-pack publication remains outside this LLS recovery pipeline.
    CSV evidence and its hashes are never modified.
    """

    results_path = run_root / "artifact_generation" / "artifact_generation_results.csv"
    if not io_path(results_path).is_file():
        return []
    with io_path(results_path).open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        result_fields = list(reader.fieldnames or [])
        result_rows = [dict(row) for row in reader]
    retired_rows = [
        row for row in result_rows
        if str(row.get("ArtifactType", "")).strip().upper() == "PNG"
    ]
    if not retired_rows:
        _delete_header_only_csv(
            run_root / "components" / "contract_plot_lineage.csv"
        )
        _delete_header_only_csv(
            run_root / "artifact_generation" / "artifact_generation_failures.csv"
        )
        return []
    invalid = [
        str(row.get("ContractID", "")) for row in retired_rows
        if not str(row.get("ContractID", "")).strip().lower().endswith("|runtime_in_path")
    ]
    if invalid:
        raise RuntimeError(
            "Refusing to retire non-runtime artifact raster contract(s): "
            + ", ".join(invalid)
        )

    contract_ids = {str(row.get("ContractID", "")).strip() for row in retired_rows}
    output_paths = {
        str(row.get("OutputRelativePath", "")).strip().replace("\\", "/")
        for row in retired_rows
    }
    output_paths.discard("")
    changes: list[dict[str, str]] = []
    for row in retired_rows:
        relative = str(row.get("OutputRelativePath", "")).strip().replace("\\", "/")
        output = _run_relative_path(run_root, relative)
        existed = io_path(output).is_file()
        previous_hash = sha256(output) if existed else ""
        if existed:
            io_path(output).unlink()
        changes.append({
            "contract_id": str(row.get("ContractID", "")),
            "output_relative_path": relative,
            "previous_sha256": previous_hash,
            "removed_file": "1" if existed else "0",
            "migration_reason": "runtime_raster_authority_moved_to_csv_contract_materializer",
        })

    remaining = [row for row in result_rows if str(row.get("ContractID", "")).strip() not in contract_ids]
    write_csv(results_path, remaining, result_fields)
    _rebuild_artifact_generation_summary(run_root, remaining)

    _prune_csv_rows(
        run_root / "artifact_generation" / "contract_catalog_snapshot.csv",
        lambda row: str(row.get("ContractID", "")).strip() in contract_ids,
    )
    manifest_path = run_root / "artifact_generation" / "canonical_component_manifest.csv"
    published_paths: set[str] = set()
    if io_path(manifest_path).is_file():
        for row in read_csv(manifest_path):
            if str(row.get("ContractID", "")).strip() in contract_ids:
                published = str(row.get("PublishedRelativePath", "")).strip().replace("\\", "/")
                if published:
                    published_paths.add(published)
                    target = _run_relative_path(run_root, published)
                    if io_path(target).is_file():
                        io_path(target).unlink()
        _prune_csv_rows(
            manifest_path,
            lambda row: str(row.get("ContractID", "")).strip() in contract_ids,
        )

    retired_paths = output_paths | published_paths
    for lineage_path in (
        run_root / "components" / "contract_plot_lineage.csv",
        run_root / "reports" / "csv" / "plot_manifest.csv",
    ):
        _prune_csv_rows(
            lineage_path,
            lambda row: str(
                row.get("ImagePath", row.get("PlotFile", ""))
            ).strip().replace("\\", "/") in retired_paths,
        )
    component_lineage_path = run_root / "components" / "contract_plot_lineage.csv"
    _delete_header_only_csv(component_lineage_path)
    failure_path = run_root / "artifact_generation" / "artifact_generation_failures.csv"
    _prune_csv_rows(
        failure_path,
        lambda row: str(row.get("ContractID", "")).strip() in contract_ids,
        delete_when_empty=True,
    )
    # A previous interrupted migration can leave a header-only failure file.
    # Absence, rather than an empty success-shaped registry, is the canonical
    # representation when artifact generation has no failures.
    _delete_header_only_csv(failure_path)
    return changes


def materialize_declared_artifact_generation_rasters(run_root: Path) -> list[dict[str, str]]:
    """Reject obsolete MATLAB artifact-engine raster contracts.

    Runtime raster output is owned exclusively by the browser visual
    contract materializer.  The in-path artifact engine is CSV-only.  This
    guard prevents an older audit snapshot from silently recreating retired
    images during recovery.
    """

    results_path = run_root / "artifact_generation" / "artifact_generation_results.csv"
    if not io_path(results_path).is_file():
        return []
    with io_path(results_path).open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        result_rows = [dict(row) for row in reader]
    png_rows = [row for row in result_rows if str(row.get("ArtifactType", "")).strip().upper() == "PNG"]
    if png_rows:
        raise RuntimeError(
            "Retired artifact-engine PNG rows are present. Re-finalize the "
            "run with the CSV-only runtime_in_path catalog before raster "
            "materialization."
        )
    return []


def reconcile_raw_evidence_index_shape_metadata(run_root: Path) -> list[dict[str, str]]:
    """Repair only stale shape metadata for already hash-matching raw bytes.

    Raw evidence CSVs are immutable.  This function refuses to touch a table
    or to update an index row when the recorded SHA-256 or row count differs.
    It can only correct a stale ColumnCount by parsing the exact bytes already
    authenticated by the index.
    """

    index_path = run_root / "raw" / "evidence" / "raw_evidence_index.csv"
    if not io_path(index_path).is_file():
        return []
    with io_path(index_path).open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = list(reader.fieldnames or [])
        rows = [dict(row) for row in reader]
    changes: list[dict[str, str]] = []
    for index, row in enumerate(rows, start=1):
        relative = str(row.get("RelativePath", "")).strip().replace("\\", "/")
        target = _run_relative_path(run_root, f"raw/evidence/{relative}")
        if target is None or not io_path(target).is_file():
            raise RuntimeError(f"Raw evidence index row {index} points to a missing table: {relative}")
        actual_hash = sha256(target)
        recorded_hash = str(row.get("SHA256", "")).strip().lower()
        if actual_hash.lower() != recorded_hash:
            raise RuntimeError(
                f"Refusing raw index repair because authenticated bytes differ at row {index}: {relative}"
            )
        actual_rows, actual_columns = read_csv_shape(target)
        recorded_rows = int(float(str(row.get("RowCount", "0") or 0)))
        recorded_columns = int(float(str(row.get("ColumnCount", "0") or 0)))
        if actual_rows != recorded_rows:
            raise RuntimeError(
                f"Refusing raw index repair because row count differs at row {index}: "
                f"index={recorded_rows}, csv={actual_rows}"
            )
        if actual_columns != recorded_columns:
            row["ColumnCount"] = str(actual_columns)
            changes.append(
                {
                    "row_index": str(index),
                    "relative_path": relative,
                    "sha256": actual_hash,
                    "row_count": str(actual_rows),
                    "previous_column_count": str(recorded_columns),
                    "current_column_count": str(actual_columns),
                    "repair_scope": "index_metadata_only_raw_csv_bytes_unchanged",
                }
            )
    if changes:
        write_csv(index_path, rows, fieldnames)
    return changes


def synchronize_declared_component_mirrors(run_root: Path) -> list[dict[str, str]]:
    """Rebind every declared byte-identical mirror to current canonical bytes.

    Finalization can legitimately update canonical lineage and status CSVs
    after their component copies were first published.  Leaving the old copy
    behind makes a ``PUBLISHED_HASH_VERIFIED`` manifest row false.  This step
    copies only already-declared mirrors, never creates new evidence, and
    fails closed when a declared canonical authority is absent.
    """

    manifest_path = run_root / "reports" / "csv" / "component_artifact_publication_manifest.csv"
    if not io_path(manifest_path).is_file():
        return []
    with io_path(manifest_path).open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = list(reader.fieldnames or [])
        rows = [dict(row) for row in reader]
    required_fields = {
        "CanonicalRelativePath",
        "PublishedRelativePath",
        "CanonicalSHA256",
        "PublishedSHA256",
        "ByteSize",
        "MirrorOnly",
        "CanonicalAuthorityRetained",
        "SourceTruthClassification",
        "PublishStatus",
    }
    if not required_fields.issubset(fieldnames):
        missing = sorted(required_fields.difference(fieldnames))
        raise RuntimeError(f"Component publication manifest is missing fields: {missing}")

    synchronized: list[dict[str, str]] = []
    retained_rows: list[dict[str, str]] = []
    for row_index, row in enumerate(rows, start=1):
        mirror_only = str(row.get("MirrorOnly", "")).strip().lower() in {"1", "true", "yes"}
        authority_retained = str(row.get("CanonicalAuthorityRetained", "")).strip().lower() in {
            "1", "true", "yes"
        }
        classification = str(row.get("SourceTruthClassification", "")).strip().lower()
        canonical_rel = str(row.get("CanonicalRelativePath", "")).strip().replace("\\", "/")
        published_rel = str(row.get("PublishedRelativePath", "")).strip().replace("\\", "/")
        is_declared_mirror = (
            mirror_only
            and authority_retained
            and classification == "byte_identical_canonical_mirror"
        )
        canonical = _run_relative_path(run_root, canonical_rel) if is_declared_mirror else None
        if (
            is_declared_mirror
            and canonical is not None
            and canonical.suffix.lower() == ".csv"
            and io_path(canonical).is_file()
            and read_csv_shape(canonical)[0] == 0
        ):
            published = _run_relative_path(run_root, published_rel)
            previous_hash = sha256(published) if io_path(published).is_file() else ""
            if io_path(published).is_file():
                io_path(published).unlink()
            synchronized.append({
                "row_index": str(row_index),
                "canonical_relative_path": canonical_rel,
                "published_relative_path": published_rel,
                "previous_published_sha256": previous_hash,
                "current_sha256": "",
                "bytes_replaced": "-1",
            })
            continue
        retained_rows.append(row)
    rows = retained_rows

    destination_authorities: dict[str, tuple[str, str]] = {}
    for row_index, row in enumerate(rows, start=1):
        mirror_only = str(row.get("MirrorOnly", "")).strip().lower() in {"1", "true", "yes"}
        authority_retained = str(row.get("CanonicalAuthorityRetained", "")).strip().lower() in {
            "1",
            "true",
            "yes",
        }
        classification = str(row.get("SourceTruthClassification", "")).strip().lower()
        if not (mirror_only and authority_retained and classification == "byte_identical_canonical_mirror"):
            continue
        canonical_rel = str(row.get("CanonicalRelativePath", "")).strip().replace("\\", "/")
        published_rel = str(row.get("PublishedRelativePath", "")).strip().replace("\\", "/")
        canonical = _run_relative_path(run_root, canonical_rel)
        if not io_path(canonical).is_file():
            raise RuntimeError(
                f"Declared component mirror canonical authority is missing: {canonical_rel}"
            )
        canonical_hash = sha256(canonical)
        previous = destination_authorities.get(published_rel)
        if previous and previous[0].lower() != canonical_hash.lower():
            raise RuntimeError(
                "Conflicting canonical authorities target one component mirror path: "
                f"{previous[1]} and {canonical_rel} -> {published_rel}"
            )
        destination_authorities[published_rel] = (canonical_hash, canonical_rel)

    for row_index, row in enumerate(rows, start=1):
        mirror_only = str(row.get("MirrorOnly", "")).strip().lower() in {"1", "true", "yes"}
        authority_retained = str(row.get("CanonicalAuthorityRetained", "")).strip().lower() in {
            "1",
            "true",
            "yes",
        }
        classification = str(row.get("SourceTruthClassification", "")).strip().lower()
        if not (mirror_only and authority_retained and classification == "byte_identical_canonical_mirror"):
            continue
        canonical_rel = str(row.get("CanonicalRelativePath", "")).strip().replace("\\", "/")
        published_rel = str(row.get("PublishedRelativePath", "")).strip().replace("\\", "/")
        canonical = _run_relative_path(run_root, canonical_rel)
        published = _run_relative_path(run_root, published_rel)
        if canonical == published:
            raise RuntimeError(f"Component mirror row {row_index} points canonical and published paths to the same file.")
        if not io_path(canonical).is_file():
            raise RuntimeError(
                f"Declared component mirror canonical authority is missing: {canonical_rel}"
            )
        canonical_hash = sha256(canonical)
        previous_hash = sha256(published) if io_path(published).is_file() else ""
        if previous_hash.lower() != canonical_hash.lower():
            io_path(published.parent).mkdir(parents=True, exist_ok=True)
            shutil.copyfile(io_path(canonical), io_path(published))
        published_hash = sha256(published)
        if published_hash.lower() != canonical_hash.lower():
            raise RuntimeError(f"Component mirror hash mismatch after synchronization: {published_rel}")
        row["CanonicalSHA256"] = canonical_hash
        row["PublishedSHA256"] = published_hash
        row["ByteSize"] = str(io_path(canonical).stat().st_size)
        row["PublishStatus"] = "PUBLISHED_HASH_VERIFIED"
        synchronized.append(
            {
                "row_index": str(row_index),
                "canonical_relative_path": canonical_rel,
                "published_relative_path": published_rel,
                "previous_published_sha256": previous_hash,
                "current_sha256": canonical_hash,
                "bytes_replaced": "1" if previous_hash.lower() != canonical_hash.lower() else "0",
            }
        )
    write_csv(manifest_path, rows, fieldnames)
    if io_path(run_root / "reports/csv/scenario_summary.csv").is_file():
        update_component_summary(run_root, rows)
    for row in rows:
        classification = str(row.get("SourceTruthClassification", "")).strip().lower()
        if classification != "byte_identical_canonical_mirror":
            continue
        canonical = _run_relative_path(run_root, str(row.get("CanonicalRelativePath", "")))
        published = _run_relative_path(run_root, str(row.get("PublishedRelativePath", "")))
        if not io_path(canonical).is_file() or not io_path(published).is_file():
            raise RuntimeError("Component mirror verification found a missing declared file.")
        canonical_hash = sha256(canonical)
        published_hash = sha256(published)
        if (
            canonical_hash.lower() != published_hash.lower()
            or canonical_hash.lower() != str(row.get("CanonicalSHA256", "")).lower()
            or published_hash.lower() != str(row.get("PublishedSHA256", "")).lower()
        ):
            raise RuntimeError(
                "Component mirror verification failed after synchronization: "
                + str(row.get("PublishedRelativePath", ""))
            )
    return synchronized


def reconcile_removed_raster_lineage(run_root: Path) -> list[dict[str, str]]:
    """Retire stale producer claims for rasters removed by this pipeline.

    The canonical CSV sources remain in place.  Only a manifest/lineage row
    whose declared image is now absent is changed.  Contract charts that
    were regenerated by the current materializer remain untouched.
    """

    changes: list[dict[str, str]] = []
    candidates = sorted(
        path
        for path in iter_files(run_root)
        if path.suffix.lower() == ".csv"
        and "plot" in path.name.lower()
        and ("manifest" in path.name.lower() or "lineage" in path.name.lower())
    )
    seen: set[Path] = set()
    for path in candidates:
        resolved = path.resolve()
        if resolved in seen or not io_path(path).is_file():
            continue
        seen.add(resolved)
        with io_path(path).open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            fieldnames = list(reader.fieldnames or [])
            rows = [dict(row) for row in reader]
        image_field = next(
            (name for name in ("ImagePath", "PlotFile", "ArtifactPath") if name in fieldnames),
            "",
        )
        if not image_field:
            continue
        changed = False
        for row_index, row in enumerate(rows, start=1):
            image_value = str(row.get(image_field, "")).strip().replace("\\", "/")
            if not image_value or Path(image_value).suffix.lower() not in RASTER_SUFFIXES:
                continue
            declared = Path(image_value)
            if declared.is_absolute():
                image_candidates = (declared,)
            else:
                # Producer lineages use both run-relative and lineage-relative
                # image paths. A live file under either interpretation is not
                # stale and must never be retired.
                image_candidates = (run_root / declared, path.parent / declared)
            if any(io_path(candidate).is_file() for candidate in image_candidates):
                continue
            before = str(row.get("Status", row.get("LineageStatus", row.get("PlotRenderStatus", ""))))
            if "PlotRenderStatus" in fieldnames:
                row["PlotRenderStatus"] = "suppressed"
            if "PlotSuppressionReason" in fieldnames:
                row["PlotSuppressionReason"] = "removed_by_csv_authority_raster_replacement"
            if "CountsAsRealPlot" in fieldnames:
                row["CountsAsRealPlot"] = "0"
            if "VisualValidity" in fieldnames:
                row["VisualValidity"] = "unavailable"
            if "IsUnavailableCard" in fieldnames:
                row["IsUnavailableCard"] = "0"
            if "Status" in fieldnames:
                row["Status"] = "not_rendered"
            if "LineageStatus" in fieldnames:
                row["LineageStatus"] = "incomplete"
            if "ImageExists" in fieldnames:
                row["ImageExists"] = "0"
            for hash_field in ("ImageSHA256", "PNG_SHA256", "sha256"):
                if hash_field in fieldnames:
                    row[hash_field] = ""
            for count_field in ("Width", "Height", "byte_count", "ByteCount"):
                if count_field in fieldnames:
                    row[count_field] = "0"
            if "actual_mime_type" in fieldnames:
                row["actual_mime_type"] = "missing"
            if "FailureReason" in fieldnames:
                row["FailureReason"] = "removed_by_csv_authority_raster_replacement"
            changes.append(
                {
                    "lineage_path": path.relative_to(run_root).as_posix(),
                    "row_index": str(row_index),
                    "image_path": image_value,
                    "previous_status": before,
                    "new_status": "not_rendered_or_suppressed",
                }
            )
            changed = True
        if changed:
            write_csv(path, rows, fieldnames)
    return changes


def retired_raster_lineage_inventory(run_root: Path) -> list[dict[str, str]]:
    """Return the current fail-closed rows retired by raster replacement."""

    rows: list[dict[str, str]] = []
    for path in sorted(iter_files(run_root)):
        name = path.name.lower()
        if path.suffix.lower() != ".csv" or "plot" not in name or not (
            "manifest" in name or "lineage" in name
        ):
            continue
        try:
            table_rows = read_csv(path)
        except (OSError, csv.Error, UnicodeError):
            continue
        for row_index, row in enumerate(table_rows, start=1):
            reason = str(
                row.get("FailureReason", "")
                or row.get("PlotSuppressionReason", "")
            ).strip()
            if reason != "removed_by_csv_authority_raster_replacement":
                continue
            rows.append(
                {
                    "lineage_path": path.relative_to(run_root.resolve()).as_posix(),
                    "row_index": str(row_index),
                    "plot_id": str(row.get("PlotId", "")),
                    "image_path": str(
                        row.get("ImagePath", "")
                        or row.get("PlotFile", "")
                        or row.get("ArtifactPath", "")
                    ),
                    "status": str(
                        row.get("Status", "")
                        or row.get("LineageStatus", "")
                        or row.get("PlotRenderStatus", "")
                    ),
                    "reason": reason,
                }
            )
    return rows


def missing_chart_contract_inventory(run_root: Path) -> list[dict[str, str]]:
    """Classify honest chart gaps without creating substitute evidence."""

    manifest_path = run_root / "reports" / "csv" / "contract_materialization_manifest.csv"
    if not io_path(manifest_path).is_file():
        return []
    inventory: list[dict[str, str]] = []
    for row in read_csv(manifest_path):
        status = str(row.get("materialization_status", "")).strip().lower()
        if str(row.get("artifact_kind", "")).strip().lower() != "image_png" or not status.startswith(
            "suppressed_"
        ):
            continue
        chart_name = str(row.get("note", "")).strip()
        token = chart_name.lower()
        if any(
            phrase in token
            for phrase in (
                "vs snr",
                "vs sinr",
                "vs mcs",
                "vs load",
                "cdf",
                "p_fa",
                "p_md",
                "p_d",
                "false alarm rate",
                "missed detection rate",
            )
        ):
            classification = "requires_multi_point_or_statistical_evidence"
            requirement = "Execute enough independent runtime operating points/trials for the stated curve or probability; do not interpolate one bounded point."
        elif any(
            phrase in token
            for phrase in (
                "harq",
                "retransmission",
                "newtx",
                "ack/nack",
                "drx",
                "sr/bsr",
                "combining gain",
            )
        ):
            classification = "requires_enabled_feature_runtime_evidence"
            requirement = "Execute the named enabled feature in the same Tx/channel/Rx lifecycle and export its event/process measurements."
        elif any(
            phrase in token
            for phrase in (
                "timeline",
                "trend",
                "map",
                "occupancy",
                "tracking",
                "over time",
            )
        ):
            classification = "requires_runtime_series_or_grid_evidence"
            requirement = "Export at least two independent time/grid coordinates with measured values from the production runtime."
        elif any(phrase in token for phrase in ("distribution", "histogram", "statistics", "breakdown")):
            classification = "requires_non_degenerate_sample_distribution"
            requirement = "Export enough non-degenerate measured samples/buckets for a defensible distribution; a single constant bucket remains suppressed."
        else:
            classification = "requires_runtime_measurement_or_schema_adapter"
            requirement = "Add an exact adapter to an existing measured CSV or export the missing runtime quantity; configured values are not substitutes."
        inventory.append(
            {
                "chart_name": chart_name,
                "logical_path": str(row.get("logical_path", "")),
                "source_logical_path": str(row.get("source_logical_path", "")),
                "materialization_status": status,
                "classification": classification,
                "required_next_evidence": requirement,
            }
        )
    return inventory


def validate_run_root(run_root: Path) -> Path:
    resolved = run_root.resolve()
    allowed = (REPO_ROOT / "results" / "lls").resolve()
    try:
        relative = resolved.relative_to(allowed)
    except ValueError as error:
        raise SystemExit(
            f"Refusing raster replacement outside {allowed}: {resolved}"
        ) from error
    if len(relative.parts) < 2 or resolved == allowed:
        raise SystemExit(
            "Raster replacement requires one exact results/lls/<scenario>/<run> folder."
        )
    resolved_config_path = resolved / "meta" / "scenario_config_resolved.json"
    required_markers = [
        resolved / "meta" / "scenario_config_identity.json",
        resolved_config_path,
        resolved / "reports" / "csv" / "scenario_summary.csv",
    ]
    if io_path(resolved_config_path).is_file():
        try:
            with io_path(resolved_config_path).open("r", encoding="utf-8") as handle:
                config = json.load(handle)
        except (OSError, ValueError, TypeError) as error:
            raise SystemExit(
                f"Resolved scenario config is not readable JSON: {resolved_config_path}: {error}"
            ) from error
        scenario = config.get("scenario", {}) if isinstance(config, dict) else {}
        simulation = config.get("simulation", {}) if isinstance(config, dict) else {}
        profile = str(scenario.get("runner_profile") or "").strip().lower() \
            if isinstance(scenario, dict) else ""
        component_markers = COMPONENT_RUN_AUTHORITY.get(profile)
        if component_markers is not None:
            required_markers.extend(resolved / marker for marker in component_markers)
        else:
            sweeps = config.get("sweeps_and_matrix", {}) \
                if isinstance(config, dict) else {}
            fixed_link = sweeps.get("fixed_link_calibration", {}) \
                if isinstance(sweeps, dict) else {}
            canonical = config.get("canonical_control", {}) \
                if isinstance(config, dict) else {}
            canonical_run = canonical.get("run", {}) \
                if isinstance(canonical, dict) else {}
            fixed_link_only = _as_config_bool(
                fixed_link.get("only") if isinstance(fixed_link, dict) else None,
                default=_as_config_bool(
                    canonical_run.get("fixed_link_campaign_only")
                    if isinstance(canonical_run, dict) else None,
                    default=False,
                ),
            )
            direction = str(simulation.get("link_direction") or "both").strip().lower() \
                if isinstance(simulation, dict) else "both"
            if direction in {"", "all"}:
                direction = "both"
            if direction in {"both", "dl", "downlink"}:
                required_markers.append(
                    resolved / "air_interface" / "csv" /
                    (
                        "dl_fixed_link_campaign_trials.csv"
                        if fixed_link_only else "dl_pdsch_trials.csv"
                    )
                )
            if direction in {"both", "ul", "uplink"}:
                required_markers.append(
                    resolved / "air_interface" / "csv" /
                    (
                        "ul_fixed_link_campaign_trials.csv"
                        if fixed_link_only else "ul_pusch_trials.csv"
                    )
                )
    missing = [str(path) for path in required_markers if not io_path(path).is_file()]
    if missing:
        raise SystemExit("Run folder is missing required authority files: " + "; ".join(missing))
    return resolved


def _as_config_bool(value: Any, *, default: bool) -> bool:
    if value is None:
        return bool(default)
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    token = str(value).strip().lower()
    if token in {"true", "1", "yes", "on", "enabled"}:
        return True
    if token in {"false", "0", "no", "off", "disabled"}:
        return False
    return bool(default)


def _semantic_row_is_policy_filtered(
    row: dict[str, Any],
    policy_filter: Callable[[str, str], bool] | None,
) -> bool:
    if policy_filter is None:
        return False
    artifact_path = str(row.get("artifact_path") or "")
    contract_name = Path(artifact_path).stem
    return bool(policy_filter(artifact_path, contract_name))


def require_primary_csv_semantics(
    run_root: Path,
    *,
    policy_filter: Callable[[str, str], bool] | None = None,
) -> dict[str, list[dict[str, Any]]]:
    audit = audit_run(run_root)
    # Terminal visual/status rows describe the post-materialization raster
    # tree and are necessarily stale before replacement.  Defer only these
    # two categories; primary PHY/runtime/ledger/value checks remain strict,
    # and the complete post-materialization audit below evaluates every
    # status and manifest check before publication succeeds.
    deferred_until_post_materialization = {"manifest_integrity", "status_reduction"}
    deferred_artifacts_until_post_materialization = {
        "reports/csv/all_image_artifact_audit.csv"
    }
    required_checks = [
        row
        for row in audit["canonical_csv_semantic_audit"]
        if bool(row.get("required"))
        and str(row.get("category")) not in deferred_until_post_materialization
        and str(row.get("artifact_path")) not in deferred_artifacts_until_post_materialization
        and not _semantic_row_is_policy_filtered(row, policy_filter)
    ]
    failures = sum(not bool(row.get("evaluated")) or not bool(row.get("passed")) for row in required_checks)
    if failures:
        details = [
            f"{row['artifact_path']}:{row['check_id']}:{row['details']}"
            for row in audit["canonical_csv_semantic_audit"]
            if bool(row.get("required"))
            and str(row.get("category")) not in deferred_until_post_materialization
            and str(row.get("artifact_path")) not in deferred_artifacts_until_post_materialization
            and not _semantic_row_is_policy_filtered(row, policy_filter)
            and (not bool(row.get("evaluated")) or not bool(row.get("passed")))
        ]
        raise SystemExit(
            "Primary CSV semantic gate failed before raster deletion: "
            + " | ".join(details)
        )
    return audit


def post_materialization_required_failures(
    audit: dict[str, list[dict[str, Any]]],
    *,
    policy_filter: Callable[[str, str], bool] | None = None,
) -> list[dict[str, Any]]:
    """Return failures Python can close before MATLAB terminal reduction.

    The runner computes terminal status only after this raster materializer
    returns and inspects the new tree. Requiring the pre-existing status rows
    here creates a circular dependency. Manifest and chart checks remain
    strict; only caller-owned `status_reduction` is deferred.
    """

    failures: list[dict[str, Any]] = []
    for collection_name in (
        "canonical_csv_semantic_audit",
        "chart_source_semantic_audit",
    ):
        for row in audit[collection_name]:
            if not bool(row.get("required")):
                continue
            if _semantic_row_is_policy_filtered(row, policy_filter):
                continue
            if (
                collection_name == "canonical_csv_semantic_audit"
                and str(row.get("category")) == "status_reduction"
            ):
                continue
            if not bool(row.get("evaluated")) or not bool(row.get("passed")):
                failures.append(row)
    return failures


def raster_inventory(run_root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path in sorted(iter_files(run_root)):
        if path.suffix.lower() not in RASTER_SUFFIXES or not io_path(path).is_file():
            continue
        with Image.open(io_path(path)) as image:
            image.load()
            rows.append(
                {
                    "relative_path": path.relative_to(run_root).as_posix(),
                    "extension": path.suffix.lower(),
                    "bytes": io_path(path).stat().st_size,
                    "sha256": sha256(path),
                    "width_px": image.width,
                    "height_px": image.height,
                    "format": image.format or "",
                }
            )
    return rows


def component_for_plot(plot_id: str) -> str:
    value = plot_id.lower()
    rules = (
        ("prach", ("prach", "random-access")),
        ("initial_access", ("initial-access", "access-delay", "sib1")),
        ("ssb", ("ssb", "pbch", "pss", "sss")),
        ("pdcch", ("pdcch", "dci", "coreset")),
        ("pdsch", ("pdsch", "dlsch", "dl-data")),
        ("pusch", ("pusch", "ulsch", "ul-data")),
        ("pucch", ("pucch", "uci")),
        ("reference_signals", ("reference-signal", "csi", "rsrp", "srs", "trs", "dmrs", "ptrs", "link-adaptation")),
        ("mimo", ("mimo", "beam", "precod", "rank", "per-layer")),
        ("frame_grid", ("frame-slot", "resource-grid", "re-occupancy", "prb-heatmap", "numerology", "duplex")),
        ("l2", ("rlc", "pdcp", "sdap", "bearer")),
        ("waveform", ("waveform", "constellation", "spectrum", "psd", "papr", "evm")),
        ("l3", ("rrc", "handover")),
        ("channel", ("channel", "propagation", "mobility", "pathloss", "doppler", "geometry")),
        ("rf", ("rf-", "impairment", "power-energy", "thermal", "cfo", "phase-noise", "iq-imbalance")),
        ("mac_harq_scheduler", ("scheduler", "harq", "queue", "retransmission", "ack-nack", "mcs-over-time")),
        ("traffic", ("traffic", "throughput", "goodput", "latency", "fairness")),
    )
    for component, tokens in rules:
        if any(token in value for token in tokens):
            return component
    return "validation"


def publish_component_raster_mirrors(run_root: Path) -> list[dict[str, Any]]:
    lineage_path = run_root / "reports" / "csv" / "contract_plot_lineage.csv"
    lineage = read_csv(lineage_path)
    manifest_path = run_root / "reports" / "csv" / "component_artifact_publication_manifest.csv"
    existing = read_csv(manifest_path) if io_path(manifest_path).is_file() else []
    manifest_fields = [
        "Component",
        "ArtifactType",
        "CanonicalRelativePath",
        "PublishedRelativePath",
        "CanonicalSHA256",
        "PublishedSHA256",
        "ByteSize",
        "MirrorOnly",
        "CanonicalAuthorityRetained",
        "SourceTruthClassification",
        "PublishStatus",
    ]
    retained = [row for row in existing if str(row.get("ArtifactType", "")).lower() != "image"]
    image_rows: list[dict[str, Any]] = []
    for row in lineage:
        if str(row.get("Status", "")).lower() != "pass":
            raise RuntimeError(f"Refusing to mirror non-pass chart {row.get('PlotId')}")
        image_rel = str(row.get("ImagePath", "")).replace("\\", "/")
        source = run_root / image_rel
        expected = str(row.get("ImageSHA256", "")).lower()
        if not io_path(source).is_file() or sha256(source).lower() != expected:
            raise RuntimeError(f"Canonical raster lineage mismatch for {image_rel}")
        component = component_for_plot(str(row.get("PlotId", "")))
        target = run_root / component / "image" / source.name
        io_path(target.parent).mkdir(parents=True, exist_ok=True)
        shutil.copyfile(io_path(source), io_path(target))
        published_hash = sha256(target)
        if published_hash.lower() != expected:
            raise RuntimeError(f"Component raster mirror hash mismatch for {target}")
        image_rows.append(
            {
                "Component": component,
                "ArtifactType": "image",
                "CanonicalRelativePath": image_rel,
                "PublishedRelativePath": target.relative_to(run_root).as_posix(),
                "CanonicalSHA256": expected,
                "PublishedSHA256": published_hash,
                "ByteSize": io_path(target).stat().st_size,
                "MirrorOnly": 1,
                "CanonicalAuthorityRetained": 1,
                "SourceTruthClassification": "byte_identical_canonical_mirror",
                "PublishStatus": "PUBLISHED_HASH_VERIFIED",
            }
        )
    combined = sorted(
        retained + image_rows,
        key=lambda row: (
            str(row.get("Component", "")),
            str(row.get("ArtifactType", "")),
            str(row.get("PublishedRelativePath", "")),
        ),
    )
    write_csv(manifest_path, combined, manifest_fields)
    update_component_summary(run_root, combined)
    return image_rows


def update_component_summary(run_root: Path, manifest: list[dict[str, Any]]) -> None:
    summary_path = run_root / "reports" / "csv" / "component_artifact_publication_summary.csv"
    identity = _canonical_run_identity(run_root)
    summary_fields = [
        "ScenarioID",
        "ConfigHash",
        "RunnerProfile",
        "Component",
        "Folder",
        "SourceArtifactCount",
        "CSVCount",
        "RasterImageCount",
        "JSONCount",
        "MATCount",
        "PublicationStatus",
        "EvidenceInterpretation",
    ]
    rows: list[dict[str, Any]] = []
    for component in COMPONENTS:
        component_rows = [row for row in manifest if row.get("Component") == component]
        kinds = Counter(str(row.get("ArtifactType", "")).lower() for row in component_rows)
        rows.append(
            {
                "ScenarioID": identity.get("ScenarioID", ""),
                "ConfigHash": identity.get("ConfigHash", ""),
                "RunnerProfile": identity.get("RunnerProfile", ""),
                "Component": component,
                "Folder": f"{component}/{{csv,image,json,mat}}",
                "SourceArtifactCount": len(component_rows),
                "CSVCount": kinds["csv"],
                "RasterImageCount": kinds["image"],
                "JSONCount": kinds["json"],
                "MATCount": kinds["mat"],
                "PublicationStatus": (
                    "PUBLISHED_HASH_VERIFIED" if component_rows else "NO_CANONICAL_EVIDENCE"
                ),
                "EvidenceInterpretation": (
                    "Presence is not a pass verdict; absent evidence is never synthesized."
                ),
            }
        )
    write_csv(summary_path, rows, summary_fields)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-folder", type=Path, required=True)
    parser.add_argument("--audit-output", type=Path, required=True)
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Required acknowledgement for deletion and replacement of run-local rasters.",
    )
    parser.add_argument(
        "--require-complete-contract",
        action="store_true",
        help=(
            "Return nonzero when statistically unsupported or otherwise missing "
            "chart contracts remain. Eligible CSV-derived charts are always "
            "materialized and audited first."
        ),
    )
    args = parser.parse_args()
    if not args.execute:
        raise SystemExit("Pass --execute to acknowledge run-local raster replacement.")

    run_root = validate_run_root(args.run_folder)
    audit_output = args.audit_output.resolve()
    audit_output.mkdir(parents=True, exist_ok=True)
    # Resume safely after an interrupted migration. These two files have no
    # evidentiary content when they contain only a schema row, and their mere
    # presence would correctly fail the runtime semantic gate.
    _delete_header_only_csv(run_root / "components" / "contract_plot_lineage.csv")
    _delete_header_only_csv(
        run_root / "artifact_generation" / "artifact_generation_failures.csv"
    )
    # The semantic catalog is deliberately broader than one scenario.  Apply
    # only configuration-derived applicability here: for example, an AWGN
    # fixed-link campaign must retain a header-only distance_vs_sinr.csv and
    # must not be blocked or populated with invented geometry rows.
    import lls_web_dashboard as dashboard  # noqa: E402

    run_row = dashboard.filesystem_run_row_from_folder(run_root)
    if run_row is None:
        raise SystemExit(f"Filesystem run metadata was not found under {run_root}.")
    feature_policy = dashboard.extract_run_feature_policy(run_row)

    def policy_filter(path: str, name: str) -> bool:
        return contract_materializer.contract_artifact_is_policy_filtered(
            path, feature_policy, contract_name=name
        )

    require_primary_csv_semantics(run_root, policy_filter=policy_filter)

    before = raster_inventory(run_root)
    write_csv(
        audit_output / "removed_raster_inventory.csv",
        before,
        ["relative_path", "extension", "bytes", "sha256", "width_px", "height_px", "format"],
    )
    for row in before:
        target = (run_root / str(row["relative_path"])).resolve()
        target.relative_to(run_root)
        io_path(target).unlink()

    command = [
        sys.executable,
        str(REPO_ROOT / "scripts" / "materialize_lls_contract_artifacts.py"),
        "--run-folder",
        str(run_root),
        "--force",
    ]
    process = subprocess.run(
        command,
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    io_path(audit_output / "materializer_stdout.log").write_text(process.stdout, encoding="utf-8")
    io_path(audit_output / "materializer_stderr.log").write_text(process.stderr, encoding="utf-8")
    if process.returncode:
        raise SystemExit(
            f"CSV raster materializer failed with exit {process.returncode}: {process.stderr or process.stdout}"
        )

    retired_runtime_rasters = retire_runtime_artifact_engine_rasters(run_root)
    write_csv(
        audit_output / "retired_runtime_artifact_engine_rasters.csv",
        retired_runtime_rasters,
        [
            "contract_id",
            "output_relative_path",
            "previous_sha256",
            "removed_file",
            "migration_reason",
        ],
    )
    artifact_generation_rasters = materialize_declared_artifact_generation_rasters(run_root)
    write_csv(
        audit_output / "artifact_generation_rasters.csv",
        artifact_generation_rasters,
        [
            "output_relative_path",
            "source_relative_path",
            "source_sha256",
            "image_sha256",
            "width",
            "height",
            "series_count",
            "finite_point_count",
        ],
    )

    lineage_changes = reconcile_removed_raster_lineage(run_root)
    retired_lineage = retired_raster_lineage_inventory(run_root)
    write_csv(
        audit_output / "stale_raster_lineage_rows_retired.csv",
        retired_lineage,
        ["lineage_path", "row_index", "plot_id", "image_path", "status", "reason"],
    )
    missing_charts = missing_chart_contract_inventory(run_root)
    write_csv(
        audit_output / "missing_chart_contracts.csv",
        missing_charts,
        [
            "chart_name",
            "logical_path",
            "source_logical_path",
            "materialization_status",
            "classification",
            "required_next_evidence",
        ],
    )
    mirrors = publish_component_raster_mirrors(run_root)
    synchronized_mirrors = synchronize_declared_component_mirrors(run_root)
    raw_index_repairs = reconcile_raw_evidence_index_shape_metadata(run_root)
    write_csv(
        audit_output / "raw_evidence_index_shape_repairs.csv",
        raw_index_repairs,
        [
            "row_index", "relative_path", "sha256", "row_count",
            "previous_column_count", "current_column_count", "repair_scope",
        ],
    )
    post_audit = audit_run(run_root)
    failures = post_materialization_required_failures(
        post_audit, policy_filter=policy_filter
    )
    if failures:
        raise SystemExit(
            "Post-materialization CSV/chart semantic gate failed: "
            + json.dumps(failures, sort_keys=True)
        )
    write_csv(
        audit_output / "component_mirror_synchronization.csv",
        synchronized_mirrors,
        [
            "row_index",
            "canonical_relative_path",
            "published_relative_path",
            "previous_published_sha256",
            "current_sha256",
            "bytes_replaced",
        ],
    )
    after = raster_inventory(run_root)
    write_csv(
        audit_output / "generated_raster_inventory.csv",
        after,
        ["relative_path", "extension", "bytes", "sha256", "width_px", "height_px", "format"],
    )
    try:
        materializer_summary = json.loads(process.stdout)
    except json.JSONDecodeError:
        materializer_summary = {}
    missing_tables = int(materializer_summary.get("tables_missing") or 0)
    missing_charts = int(materializer_summary.get("charts_missing") or 0)
    applicable_primary_failures = [
        row
        for row in post_audit["canonical_csv_semantic_audit"]
        if bool(row.get("required"))
        and str(row.get("category")) != "status_reduction"
        and not _semantic_row_is_policy_filtered(row, policy_filter)
        and (not bool(row.get("evaluated")) or not bool(row.get("passed")))
    ]
    applicable_chart_failures = [
        row
        for row in post_audit["chart_source_semantic_audit"]
        if bool(row.get("required"))
        and not _semantic_row_is_policy_filtered(row, policy_filter)
        and (not bool(row.get("evaluated")) or not bool(row.get("passed")))
    ]
    summary = {
        "run_folder": str(run_root),
        "old_rasters_removed": len(before),
        "csv_derived_rasters_generated": len(after),
        "canonical_lineaged_charts": len(post_audit["chart_source_semantic_audit"]) - 1,
        "component_raster_mirrors": len(mirrors),
        "artifact_generation_rasters": len(artifact_generation_rasters),
        "component_manifest_mirrors_synchronized": len(synchronized_mirrors),
        "raw_evidence_index_shape_repairs": len(raw_index_repairs),
        "stale_raster_lineage_rows_retired": len(lineage_changes),
        # Report only failures applicable to this exact YAML-selected run.
        # The raw semantic catalog deliberately contains other-mode entries;
        # exposing that unfiltered count here made a successful fail-closed
        # materialization look internally contradictory.
        "primary_csv_semantic_failures": len(applicable_primary_failures),
        "chart_semantic_failures": len(applicable_chart_failures),
        "contract_tables_missing": missing_tables,
        "contract_charts_missing": missing_charts,
        "contract_complete": missing_tables == 0 and missing_charts == 0,
        "generator": "scripts/regenerate_lls_rasters_from_csv.py",
        "no_placeholder_or_reason_card_png": True,
    }
    io_path(audit_output / "raster_regeneration_summary.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, indent=2))
    if args.require_complete_contract and not summary["contract_complete"]:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
