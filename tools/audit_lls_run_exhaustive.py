#!/usr/bin/env python3
"""Stream-audit every CSV and raster image in one completed LLS run.

This tool never modifies the run.  It reports structural/value statistics,
duplicate rows and files, non-finite tokens, explicit failure tokens, and
raster readability/hash/dimensions.  Domain acceptance remains authoritative
in the simulator's own truth-contract tables; this inventory makes omissions
and suspicious values reviewable without inventing replacement evidence.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import sys
from collections import Counter
from pathlib import Path
from statistics import fmean
from typing import Iterable

from PIL import Image, ImageStat

# Pytest imports this file as a module from the repository root, whereas the
# command-line entry point executes it with tools/ on sys.path.  Make both
# entry paths resolve the sibling semantic auditor identically.
TOOLS_ROOT = Path(__file__).resolve().parent
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

from lls_csv_semantics import audit_run as audit_csv_semantics
from lls_csv_semantics import write_audit as write_csv_semantic_audit
from lls_csv_semantics import LINK_REQUIRED_COLUMNS, primary_link_tables


FAILURE_TOKENS = {"fail", "failed", "error", "crash", "invalid"}
RISK_TOKENS = {
    "proxy": "proxy",
    "synthetic": "synthetic",
    "fallback": "fallback",
    "placeholder": "placeholder",
    "logistic": "proxy",
    "lut": "proxy",
}
# ``none`` is a valid, explicit value for fields such as ApproximationMode.
# Treating it as null concealed whether a truth row had declared that no
# approximation was used.
NULL_TOKENS = {"", "nan", "+nan", "-nan", "<missing>", "null"}
INF_TOKENS = {"inf", "+inf", "-inf", "infinity", "+infinity", "-infinity"}


def io_path(path: Path) -> Path:
    """Return a Windows extended-length path for filesystem I/O.

    Contract artifact names are intentionally descriptive and can exceed the
    legacy MAX_PATH limit once nested below a long repository/run root.  Keep
    the ordinary path for portable relative-path reporting, but use the
    extended form for every read/stat operation.
    """
    resolved = path.resolve()
    if os.name != "nt":
        return resolved
    text = str(resolved)
    if text.startswith("\\\\?\\"):
        return resolved
    if text.startswith("\\\\"):
        return Path("\\\\?\\UNC\\" + text[2:])
    return Path("\\\\?\\" + text)


def is_nested_execution_path(run_root: Path, candidate: Path) -> bool:
    """Exclude complete child sweep executions from a parent-run audit."""

    try:
        relative = candidate.resolve().relative_to(run_root.resolve())
    except (OSError, ValueError):
        return False
    return bool(relative.parts and relative.parts[0].lower() == "sweeps")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with io_path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def numeric(text: str) -> float | None:
    value = text.strip().lower()
    if value in NULL_TOKENS or value in INF_TOKENS:
        return None
    try:
        parsed = float(value)
    except ValueError:
        return None
    return parsed if math.isfinite(parsed) else None


def risk_counts(value: str) -> Counter[str]:
    lowered = value.strip().lower()
    result: Counter[str] = Counter()
    for token, kind in RISK_TOKENS.items():
        if token in lowered:
            result[kind] += 1
    return result


def audit_csv(path: Path, root: Path) -> tuple[dict, list[dict], list[dict]]:
    relative = path.relative_to(root).as_posix()
    source_path = io_path(path)
    file_row = {
        "relative_path": relative,
        "bytes": source_path.stat().st_size,
        "sha256": sha256(path),
        "parse_ok": False,
        "row_count": 0,
        "column_count": 0,
        "duplicate_header_count": 0,
        "row_width_mismatch_count": 0,
        "blank_cell_count": 0,
        "blank_fraction": 0.0,
        "nan_token_count": 0,
        "inf_token_count": 0,
        "duplicate_row_count": 0,
        "failure_token_count": 0,
        "proxy_token_count": 0,
        "synthetic_token_count": 0,
        "fallback_token_count": 0,
        "placeholder_token_count": 0,
        "schema_only": False,
        "observation_count": 0,
        "observations": "",
        "issue_count": 0,
        "issues": "",
    }
    issues: list[str] = []
    observations: list[str] = []
    columns: list[dict] = []
    first_rows: list[dict] = []
    try:
        with source_path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.reader(handle)
            header = next(reader, None)
            if header is None:
                issues.append("empty_file_no_header")
                file_row["issues"] = "|".join(issues)
                file_row["issue_count"] = len(issues)
                first_rows.append({
                    "relative_path": relative,
                    "source_row_number": 0,
                    "preview_state": "missing_header",
                    "nonblank_cell_count": 0,
                    "missing_or_nan_cell_count": 0,
                    "finite_numeric_cell_count": 0,
                    "zero_numeric_cell_count": 0,
                    "nonzero_numeric_cell_count": 0,
                    "header_json": "[]",
                    "values_json": "[]",
                })
                return file_row, columns, first_rows
            file_row["column_count"] = len(header)
            file_row["duplicate_header_count"] = len(header) - len(set(header))
            if not header:
                issues.append("empty_header")
            if file_row["duplicate_header_count"]:
                issues.append("duplicate_header_names")
            stats = [
                {
                    "relative_path": relative,
                    "column_index": index + 1,
                    "column_name": name,
                    "row_count": 0,
                    "blank_count": 0,
                    "blank_fraction": 0.0,
                    "nan_token_count": 0,
                    "inf_token_count": 0,
                    "unique_nonblank_count": 0,
                    "numeric_count": 0,
                    "finite_fraction": 0.0,
                    "zero_count": 0,
                    "nonzero_numeric_count": 0,
                    "numeric_min": "",
                    "numeric_max": "",
                    "numeric_mean": "",
                    "failure_token_count": 0,
                    "proxy_token_count": 0,
                    "synthetic_token_count": 0,
                    "fallback_token_count": 0,
                    "placeholder_token_count": 0,
                    "value_population_class": "",
                    "semantic_attention": "",
                }
                for index, name in enumerate(header)
            ]
            uniques = [set() for _ in header]
            numeric_values: list[list[float]] = [[] for _ in header]
            row_hashes: Counter[str] = Counter()
            header_index = {name: index for index, name in enumerate(header)}
            primary_paths = set(primary_link_tables(root).values())
            required_missing_counts: Counter[str] = Counter()
            scheduled_na_counts: Counter[str] = Counter()
            cell_count = 0
            for row in reader:
                file_row["row_count"] += 1
                if file_row["row_count"] <= 3:
                    normalized = row[: len(header)] + [""] * max(0, len(header) - len(row))
                    missing = 0
                    finite_numeric = 0
                    zero_numeric = 0
                    nonblank = 0
                    for value in normalized:
                        text = value.strip()
                        lowered = text.lower()
                        if lowered in NULL_TOKENS:
                            missing += 1
                            continue
                        nonblank += 1
                        number = numeric(text)
                        if number is not None:
                            finite_numeric += 1
                            if math.isclose(number, 0.0, abs_tol=0.0):
                                zero_numeric += 1
                    first_rows.append({
                        "relative_path": relative,
                        "source_row_number": file_row["row_count"],
                        "preview_state": "observed_row",
                        "nonblank_cell_count": nonblank,
                        "missing_or_nan_cell_count": missing,
                        "finite_numeric_cell_count": finite_numeric,
                        "zero_numeric_cell_count": zero_numeric,
                        "nonzero_numeric_cell_count": finite_numeric - zero_numeric,
                        "header_json": json.dumps(header, ensure_ascii=False),
                        "values_json": json.dumps(normalized, ensure_ascii=False),
                    })
                row_hashes[hashlib.sha256(
                    json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
                ).hexdigest()] += 1
                if len(row) != len(header):
                    file_row["row_width_mismatch_count"] += 1
                    if len(row) < len(header):
                        row = row + [""] * (len(header) - len(row))
                    else:
                        row = row[: len(header)]
                if relative in primary_paths:
                    schedule_status_index = header_index.get(
                        "ScheduledOperatingPointEvidenceStatus"
                    )
                    schedule_status = (
                        row[schedule_status_index].strip().lower()
                        if schedule_status_index is not None
                        else ""
                    )
                    explicit_unscheduled_na = (
                        "not_applicable_no_adaptive_scheduled_decision"
                        in schedule_status
                    )
                    for required_name in LINK_REQUIRED_COLUMNS:
                        required_index = header_index.get(required_name)
                        if required_index is None:
                            continue
                        if row[required_index].strip().lower() not in NULL_TOKENS:
                            continue
                        if (
                            required_name
                            in {"ScheduledMCSIndex", "ScheduledModulation"}
                            and explicit_unscheduled_na
                        ):
                            scheduled_na_counts[required_name] += 1
                        else:
                            required_missing_counts[required_name] += 1
                for index, value in enumerate(row):
                    text = value.strip()
                    lowered = text.lower()
                    stat = stats[index]
                    stat["row_count"] += 1
                    cell_count += 1
                    if lowered in NULL_TOKENS:
                        stat["blank_count"] += 1
                        file_row["blank_cell_count"] += 1
                        if lowered == "nan":
                            stat["nan_token_count"] += 1
                            file_row["nan_token_count"] += 1
                        continue
                    if lowered in INF_TOKENS:
                        stat["inf_token_count"] += 1
                        file_row["inf_token_count"] += 1
                        continue
                    uniques[index].add(text)
                    number = numeric(text)
                    if number is not None:
                        numeric_values[index].append(number)
                    if lowered in FAILURE_TOKENS:
                        stat["failure_token_count"] += 1
                        file_row["failure_token_count"] += 1
                    risks = risk_counts(text)
                    for kind, count in risks.items():
                        stat[f"{kind}_token_count"] += count
                        file_row[f"{kind}_token_count"] += count
            file_row["duplicate_row_count"] = sum(
                count - 1 for count in row_hashes.values() if count > 1
            )
            file_row["blank_fraction"] = (
                file_row["blank_cell_count"] / cell_count if cell_count else 0.0
            )
            if file_row["row_width_mismatch_count"]:
                issues.append("row_width_mismatch")
            if file_row["row_count"] == 0:
                # A header-only CSV is structurally valid. It commonly
                # represents an honestly empty failure/event table. Keep it
                # visible as an observation; semantic completeness remains
                # the responsibility of the run's artifact/truth contract.
                file_row["schema_only"] = True
                observations.append("header_only_no_rows")
                first_rows.append({
                    "relative_path": relative,
                    "source_row_number": 0,
                    "preview_state": "header_only_no_rows",
                    "nonblank_cell_count": 0,
                    "missing_or_nan_cell_count": 0,
                    "finite_numeric_cell_count": 0,
                    "zero_numeric_cell_count": 0,
                    "nonzero_numeric_cell_count": 0,
                    "header_json": json.dumps(header, ensure_ascii=False),
                    "values_json": "[]",
                })
            for index, stat in enumerate(stats):
                stat["blank_fraction"] = (
                    stat["blank_count"] / stat["row_count"] if stat["row_count"] else 0.0
                )
                stat["unique_nonblank_count"] = len(uniques[index])
                values = numeric_values[index]
                stat["numeric_count"] = len(values)
                stat["finite_fraction"] = (
                    len(values) / stat["row_count"] if stat["row_count"] else 0.0
                )
                stat["zero_count"] = sum(math.isclose(value, 0.0, abs_tol=0.0) for value in values)
                stat["nonzero_numeric_count"] = len(values) - stat["zero_count"]
                if values:
                    stat["numeric_min"] = format(min(values), ".17g")
                    stat["numeric_max"] = format(max(values), ".17g")
                    stat["numeric_mean"] = format(fmean(values), ".17g")
                if stat["row_count"] == 0:
                    stat["value_population_class"] = "schema_only_no_observations"
                elif stat["blank_count"] == stat["row_count"]:
                    stat["value_population_class"] = "all_missing_or_not_applicable"
                elif stat["numeric_count"] == stat["row_count"] and stat["zero_count"] == stat["row_count"]:
                    stat["value_population_class"] = "all_zero_finite"
                elif stat["numeric_count"] > 0 and stat["blank_count"] > 0:
                    stat["value_population_class"] = "mixed_finite_and_missing"
                elif stat["numeric_count"] > 0:
                    stat["value_population_class"] = "finite_numeric_population"
                else:
                    stat["value_population_class"] = "categorical_population"
                if (
                    relative in primary_paths
                    and stat["column_name"] in LINK_REQUIRED_COLUMNS
                    and required_missing_counts[stat["column_name"]] > 0
                ):
                    stat["semantic_attention"] = "required_primary_value_missing"
                elif (
                    relative in primary_paths
                    and stat["column_name"]
                    in {"ScheduledMCSIndex", "ScheduledModulation"}
                    and stat["blank_count"] > 0
                    and scheduled_na_counts[stat["column_name"]]
                    == stat["blank_count"]
                ):
                    stat["semantic_attention"] = (
                        "explicit_not_applicable_no_adaptive_scheduled_decision"
                    )
                elif (
                    stat["inf_token_count"] > 0
                    and stat["column_name"] in {"ExpectedMin", "ExpectedMax"}
                    and relative.endswith((
                        "generated_value_plausibility_audit.csv",
                        "phy_value_invariant_checks.csv",
                    ))
                ):
                    # Infinite lower/upper bounds are deliberate for
                    # one-sided invariant definitions; they are not measured
                    # non-finite runtime values.
                    stat["semantic_attention"] = "unbounded_acceptance_limit_not_runtime_measurement"
                elif stat["inf_token_count"] > 0:
                    stat["semantic_attention"] = "nonfinite_infinity_requires_review"
                elif stat["blank_count"] > 0 or stat["zero_count"] == stat["row_count"]:
                    stat["semantic_attention"] = "classified_observation_not_automatic_failure"
            columns = stats
            file_row["parse_ok"] = True
    except Exception as error:  # audit must record, not hide, unreadable artifacts
        issues.append(f"parse_error:{type(error).__name__}:{error}")
    file_row["observations"] = "|".join(observations)
    file_row["observation_count"] = len(observations)
    file_row["issues"] = "|".join(issues)
    file_row["issue_count"] = len(issues)
    return file_row, columns, first_rows


def audit_image(path: Path, root: Path) -> dict:
    source_path = io_path(path)
    row = {
        "relative_path": path.relative_to(root).as_posix(),
        "extension": path.suffix.lower(),
        "bytes": source_path.stat().st_size,
        "sha256": sha256(path),
        "decode_ok": False,
        "format": "",
        "width_px": 0,
        "height_px": 0,
        "mode": "",
        "grayscale_min": "",
        "grayscale_max": "",
        "grayscale_stddev": "",
        "blank_or_constant": False,
        "issue": "",
    }
    try:
        with Image.open(source_path) as image:
            image.load()
            gray = image.convert("L")
            extrema = gray.getextrema()
            stat = ImageStat.Stat(gray)
            row.update(
                decode_ok=True,
                format=image.format or "",
                width_px=image.width,
                height_px=image.height,
                mode=image.mode,
                grayscale_min=extrema[0],
                grayscale_max=extrema[1],
                grayscale_stddev=format(stat.stddev[0], ".17g"),
                blank_or_constant=extrema[0] == extrema[1],
            )
            if image.width < 32 or image.height < 32:
                row["issue"] = "implausibly_small_raster"
            elif row["blank_or_constant"]:
                row["issue"] = "blank_or_constant_raster"
    except Exception as error:
        row["issue"] = f"decode_error:{type(error).__name__}:{error}"
    return row


def write_csv(path: Path, rows: Iterable[dict]) -> None:
    rows = list(rows)
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def build_csv_file_dispositions(
    run_root: Path,
    csv_rows: list[dict],
    column_rows: list[dict],
    semantic_audit: dict[str, list[dict]],
) -> list[dict]:
    """Produce one honest disposition row for every CSV in the run.

    Parsing and numeric population statistics are not sufficient to certify
    a domain table.  This view therefore distinguishes semantic passes,
    semantic failures, byte-identical component mirrors, declared empty
    schemas, and files that still require a component-specific contract.
    """

    columns_by_path: dict[str, list[dict]] = {}
    for row in column_rows:
        columns_by_path.setdefault(str(row["relative_path"]), []).append(row)

    checks_by_path: dict[str, list[dict]] = {}
    for collection in (
        semantic_audit.get("canonical_csv_semantic_audit", []),
        semantic_audit.get("chart_source_semantic_audit", []),
    ):
        for check in collection:
            artifact_path = str(check.get("artifact_path", ""))
            if artifact_path:
                checks_by_path.setdefault(artifact_path, []).append(check)

    mirror_map: dict[str, dict[str, str]] = {}
    manifest = run_root / "reports" / "csv" / "component_artifact_publication_manifest.csv"
    if io_path(manifest).is_file():
        with io_path(manifest).open("r", encoding="utf-8-sig", newline="") as handle:
            for row in csv.DictReader(handle):
                published = str(row.get("PublishedRelativePath", "")).strip().replace("\\", "/")
                if published:
                    mirror_map[published] = {str(key): str(value) for key, value in row.items()}

    dispositions: list[dict] = []
    file_hash_by_path = {
        str(row["relative_path"]): str(row.get("sha256", "")).lower()
        for row in csv_rows
    }
    primary_paths = set(primary_link_tables(run_root).values())
    for file_row in csv_rows:
        relative = str(file_row["relative_path"])
        columns = columns_by_path.get(relative, [])
        checks = checks_by_path.get(relative, [])
        required_failures = sum(
            bool(check.get("required", False))
            and (not bool(check.get("evaluated", False)) or not bool(check.get("passed", False)))
            for check in checks
        )
        mirror = mirror_map.get(relative)
        mirror_verified = bool(
            mirror
            and str(mirror.get("PublishedSHA256", "")).lower() == str(file_row["sha256"]).lower()
            and str(mirror.get("CanonicalSHA256", "")).lower() == str(file_row["sha256"]).lower()
            and str(mirror.get("PublishStatus", "")).upper() == "PUBLISHED_HASH_VERIFIED"
        )
        if mirror:
            role = "byte_identical_component_mirror"
            canonical_source = str(mirror.get("CanonicalRelativePath", ""))
        elif relative in primary_paths:
            role = "primary_runtime_truth"
            canonical_source = relative
        elif "/contract__" in f"/{relative}" or relative.startswith("reports/csv/contract__"):
            role = "browser_contract_dataset"
            canonical_source = relative
        elif relative.startswith("raw/") or "/raw/" in f"/{relative}":
            role = "raw_runtime_or_lineage"
            canonical_source = relative
        else:
            role = "canonical_or_derived_artifact"
            canonical_source = relative

        if int(file_row["issue_count"]) > 0 or not bool(file_row["parse_ok"]):
            disposition = "FAIL_STRUCTURAL"
        elif required_failures:
            disposition = "FAIL_REQUIRED_SEMANTICS"
        elif mirror and mirror_verified:
            disposition = "PASS_BYTE_IDENTICAL_MIRROR"
        elif mirror:
            disposition = "FAIL_MIRROR_HASH_OR_STATUS"
        elif int(file_row["row_count"]) == 0:
            disposition = "EMPTY_DECLARED_SCHEMA_NO_OBSERVATIONS"
        elif checks and relative in primary_paths:
            disposition = "PASS_PRIMARY_RUNTIME_SEMANTICS"
        elif checks and any(str(check.get("category", "")) == "chart_lineage" for check in checks):
            disposition = "PASS_CHART_DATASET_SEMANTICS"
        elif checks and any(
            str(check.get("category", "")) == "control_runtime" for check in checks
        ):
            disposition = "PASS_CONTROL_RUNTIME_SEMANTICS"
        elif checks and any(
            str(check.get("category", ""))
            in {"status_reduction", "cross_table_reconciliation"}
            for check in checks
        ):
            disposition = "PASS_STATUS_REDUCTION_SEMANTICS"
        elif checks and any(
            str(check.get("category", "")) == "derived_link" for check in checks
        ):
            disposition = "PASS_DERIVED_LINK_SEMANTICS"
        elif checks and any(
            str(check.get("category", "")) == "manifest_integrity" for check in checks
        ):
            disposition = "PASS_MANIFEST_INTEGRITY_SEMANTICS"
        elif checks and any(
            str(check.get("category", "")) == "domain_runtime" for check in checks
        ):
            disposition = "PASS_DOMAIN_RUNTIME_SEMANTICS"
        else:
            disposition = "PARSED_UNCONTRACTED_REQUIRES_DOMAIN_REVIEW"

        dispositions.append(
            {
                "relative_path": relative,
                "artifact_role": role,
                "canonical_source": canonical_source,
                "row_count": int(file_row["row_count"]),
                "column_count": int(file_row["column_count"]),
                "all_zero_finite_column_count": sum(
                    str(row["value_population_class"]) == "all_zero_finite" for row in columns
                ),
                "all_missing_column_count": sum(
                    str(row["value_population_class"]) == "all_missing_or_not_applicable" for row in columns
                ),
                "mixed_finite_missing_column_count": sum(
                    str(row["value_population_class"]) == "mixed_finite_and_missing" for row in columns
                ),
                "semantic_check_count": len(checks),
                "required_semantic_failure_count": required_failures,
                "mirror_hash_verified": mirror_verified,
                "audit_disposition": disposition,
            }
        )

    # Exact run-local copies can inherit an already-passed contract only
    # when both their bytes and basename match the checked authority.  This
    # recognizes component/report replication without treating coincidental
    # equal values in differently named scientific tables as equivalent.
    pass_priority = {
        "PASS_PRIMARY_RUNTIME_SEMANTICS": 0,
        "PASS_CONTROL_RUNTIME_SEMANTICS": 1,
        "PASS_STATUS_REDUCTION_SEMANTICS": 2,
        "PASS_DERIVED_LINK_SEMANTICS": 3,
        "PASS_MANIFEST_INTEGRITY_SEMANTICS": 4,
        "PASS_DOMAIN_RUNTIME_SEMANTICS": 5,
        "PASS_CHART_DATASET_SEMANTICS": 6,
        "PASS_BYTE_IDENTICAL_MIRROR": 7,
    }
    passed_by_hash_and_name: dict[tuple[str, str], dict] = {}
    for row in sorted(
        dispositions,
        key=lambda item: pass_priority.get(str(item["audit_disposition"]), 99),
    ):
        if str(row["audit_disposition"]) not in pass_priority:
            continue
        relative = str(row["relative_path"])
        key = (file_hash_by_path.get(relative, ""), Path(relative).name.lower())
        if key[0]:
            passed_by_hash_and_name.setdefault(key, row)
    for row in dispositions:
        if row["audit_disposition"] != "PARSED_UNCONTRACTED_REQUIRES_DOMAIN_REVIEW":
            continue
        relative = str(row["relative_path"])
        key = (file_hash_by_path.get(relative, ""), Path(relative).name.lower())
        authority = passed_by_hash_and_name.get(key)
        if authority is None or str(authority["relative_path"]) == relative:
            continue
        row["artifact_role"] = "byte_identical_semantic_duplicate"
        row["canonical_source"] = str(authority["relative_path"])
        row["mirror_hash_verified"] = True
        row["audit_disposition"] = "PASS_BYTE_IDENTICAL_SEMANTIC_DUPLICATE"
    return dispositions


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_root", type=Path)
    parser.add_argument("output_root", type=Path)
    args = parser.parse_args()
    run_root = args.run_root.resolve()
    output_root = args.output_root.resolve()
    if not run_root.is_dir():
        raise SystemExit(f"run root does not exist: {run_root}")

    csv_rows: list[dict] = []
    column_rows: list[dict] = []
    first_row_previews: list[dict] = []
    for path in sorted(run_root.rglob("*.csv")):
        if is_nested_execution_path(run_root, path):
            continue
        file_row, columns, first_rows = audit_csv(path, run_root)
        csv_rows.append(file_row)
        column_rows.extend(columns)
        first_row_previews.extend(first_rows)
    image_paths = sorted(
        path for path in run_root.rglob("*")
        if not is_nested_execution_path(run_root, path)
        and io_path(path).is_file()
        and path.suffix.lower() in {".png", ".jpg", ".jpeg"}
    )
    image_rows = [audit_image(path, run_root) for path in image_paths]
    vector_paths = sorted(
        path
        for path in run_root.rglob("*.svg")
        if not is_nested_execution_path(run_root, path) and io_path(path).is_file()
    )

    hash_groups: dict[str, list[str]] = {}
    for row in csv_rows:
        hash_groups.setdefault(row["sha256"], []).append(row["relative_path"])
    duplicate_files = [
        {"sha256": digest, "copy_count": len(paths), "relative_paths": "|".join(paths)}
        for digest, paths in sorted(hash_groups.items()) if len(paths) > 1
    ]
    image_hash_groups: dict[str, list[str]] = {}
    for row in image_rows:
        image_hash_groups.setdefault(row["sha256"], []).append(row["relative_path"])
    duplicate_images = [
        {"sha256": digest, "copy_count": len(paths), "relative_paths": "|".join(paths)}
        for digest, paths in sorted(image_hash_groups.items()) if len(paths) > 1
    ]

    write_csv(output_root / "all_csv_file_audit.csv", csv_rows)
    write_csv(output_root / "all_csv_column_audit.csv", column_rows)
    write_csv(output_root / "all_csv_first_three_rows.csv", first_row_previews)
    zero_nan_rows = [
        row for row in column_rows
        if int(row["blank_count"]) > 0
        or int(row["nan_token_count"]) > 0
        or int(row["inf_token_count"]) > 0
        or (int(row["row_count"]) > 0 and int(row["zero_count"]) == int(row["row_count"]))
    ]
    write_csv(output_root / "zero_nan_column_classification.csv", zero_nan_rows)
    write_csv(output_root / "all_raster_image_audit.csv", image_rows)
    write_csv(output_root / "duplicate_csv_byte_hashes.csv", duplicate_files)
    write_csv(output_root / "duplicate_raster_byte_hashes.csv", duplicate_images)

    semantic_audit = audit_csv_semantics(run_root)
    write_csv_semantic_audit(output_root, semantic_audit)
    semantic_summary = semantic_audit["summary"][0]
    file_dispositions = build_csv_file_dispositions(
        run_root, csv_rows, column_rows, semantic_audit
    )
    write_csv(output_root / "csv_file_semantic_disposition.csv", file_dispositions)

    summary = {
        "run_root": str(run_root),
        "csv_file_count": len(csv_rows),
        "csv_total_rows": sum(int(row["row_count"]) for row in csv_rows),
        "csv_total_columns": sum(int(row["column_count"]) for row in csv_rows),
        "csv_all_blank_columns": sum(
            int(row["row_count"]) > 0
            and int(row["blank_count"]) == int(row["row_count"])
            for row in column_rows
        ),
        "csv_all_zero_finite_columns": sum(
            row["value_population_class"] == "all_zero_finite" for row in column_rows
        ),
        "csv_required_primary_columns_with_missing_values": sum(
            row["semantic_attention"] == "required_primary_value_missing" for row in column_rows
        ),
        "csv_parse_failures": sum(not bool(row["parse_ok"]) for row in csv_rows),
        "csv_empty_files": sum(int(row["row_count"]) == 0 for row in csv_rows),
        "csv_structural_issue_files": sum(int(row["issue_count"]) > 0 for row in csv_rows),
        "csv_duplicate_rows": sum(int(row["duplicate_row_count"]) for row in csv_rows),
        "csv_nan_tokens": sum(int(row["nan_token_count"]) for row in csv_rows),
        "csv_inf_tokens": sum(int(row["inf_token_count"]) for row in csv_rows),
        "csv_failure_tokens": sum(int(row["failure_token_count"]) for row in csv_rows),
        "csv_proxy_tokens": sum(int(row["proxy_token_count"]) for row in csv_rows),
        "csv_synthetic_tokens": sum(int(row["synthetic_token_count"]) for row in csv_rows),
        "csv_fallback_tokens": sum(int(row["fallback_token_count"]) for row in csv_rows),
        "csv_placeholder_tokens": sum(int(row["placeholder_token_count"]) for row in csv_rows),
        "duplicate_csv_hash_groups": len(duplicate_files),
        "raster_count": len(image_rows),
        "png_file_count": sum(row["extension"] == ".png" for row in image_rows),
        "jpeg_file_count": sum(row["extension"] in {".jpg", ".jpeg"} for row in image_rows),
        "duplicate_raster_hash_groups": len(duplicate_images),
        "raster_decode_failures": sum(not bool(row["decode_ok"]) for row in image_rows),
        "raster_issue_count": sum(bool(row["issue"]) for row in image_rows),
        "svg_file_count": len(vector_paths),
        "svg_paths": [path.relative_to(run_root).as_posix() for path in vector_paths],
        "csv_semantic_check_count": int(semantic_summary["semantic_check_count"]),
        "csv_semantic_required_failures": int(semantic_summary["semantic_required_failure_count"]),
        "chart_semantic_check_count": int(semantic_summary["chart_check_count"]),
        "chart_semantic_required_failures": int(semantic_summary["chart_required_failure_count"]),
        "csv_files_with_required_semantic_failures": sum(
            int(row["required_semantic_failure_count"]) > 0 for row in file_dispositions
        ),
        "csv_files_parsed_but_without_domain_contract": sum(
            row["audit_disposition"] == "PARSED_UNCONTRACTED_REQUIRES_DOMAIN_REVIEW"
            for row in file_dispositions
        ),
        "csv_verified_component_mirror_files": sum(
            row["audit_disposition"] == "PASS_BYTE_IDENTICAL_MIRROR"
            for row in file_dispositions
        ),
    }
    output_root.mkdir(parents=True, exist_ok=True)
    (output_root / "audit_summary.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8"
    )
    with (output_root / "audit_report.md").open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("# Exhaustive LLS run artifact inventory\n\n")
        handle.write(f"Run: `{run_root}`\n\n")
        for key, value in summary.items():
            if key not in {"run_root", "svg_paths"}:
                handle.write(f"- {key}: **{value}**\n")
        if summary["svg_paths"]:
            handle.write("\n## SVG files (unexpected for raster-only output)\n\n")
            for value in summary["svg_paths"]:
                handle.write(f"- `{value}`\n")
        handle.write("\nThe per-file and per-column CSVs contain the complete review inventory. "
                     "Blank/NaN counts are observations, not automatic failures: semantic N/A "
                     "classification is evaluated by the run's truth-contract tables.\n")
    print(json.dumps(summary, indent=2))
    return 1 if (
        summary["csv_parse_failures"]
        or summary["csv_structural_issue_files"]
        or summary["raster_decode_failures"]
        or summary["raster_issue_count"]
        or summary["svg_file_count"]
        or summary["csv_semantic_required_failures"]
        or summary["chart_semantic_required_failures"]
    ) else 0


if __name__ == "__main__":
    raise SystemExit(main())
