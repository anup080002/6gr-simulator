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
from collections import Counter
from pathlib import Path
from statistics import fmean
from typing import Iterable

from PIL import Image, ImageStat


FAILURE_TOKENS = {"fail", "failed", "error", "crash", "invalid"}
RISK_TOKENS = {
    "proxy": "proxy",
    "synthetic": "synthetic",
    "fallback": "fallback",
    "placeholder": "placeholder",
    "logistic": "proxy",
    "lut": "proxy",
}
NULL_TOKENS = {"", "nan", "+nan", "-nan", "<missing>", "null", "none"}
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


def audit_csv(path: Path, root: Path) -> tuple[dict, list[dict]]:
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
        "issue_count": 0,
        "issues": "",
    }
    issues: list[str] = []
    columns: list[dict] = []
    try:
        with source_path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.reader(handle)
            header = next(reader, None)
            if header is None:
                issues.append("empty_file_no_header")
                file_row["issues"] = "|".join(issues)
                file_row["issue_count"] = len(issues)
                return file_row, columns
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
                    "numeric_min": "",
                    "numeric_max": "",
                    "numeric_mean": "",
                    "failure_token_count": 0,
                    "proxy_token_count": 0,
                    "synthetic_token_count": 0,
                    "fallback_token_count": 0,
                    "placeholder_token_count": 0,
                }
                for index, name in enumerate(header)
            ]
            uniques = [set() for _ in header]
            numeric_values: list[list[float]] = [[] for _ in header]
            row_hashes: Counter[str] = Counter()
            cell_count = 0
            for row in reader:
                file_row["row_count"] += 1
                row_hashes[hashlib.sha256(
                    json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
                ).hexdigest()] += 1
                if len(row) != len(header):
                    file_row["row_width_mismatch_count"] += 1
                    if len(row) < len(header):
                        row = row + [""] * (len(header) - len(row))
                    else:
                        row = row[: len(header)]
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
                issues.append("header_only_no_rows")
            for index, stat in enumerate(stats):
                stat["blank_fraction"] = (
                    stat["blank_count"] / stat["row_count"] if stat["row_count"] else 0.0
                )
                stat["unique_nonblank_count"] = len(uniques[index])
                values = numeric_values[index]
                stat["numeric_count"] = len(values)
                if values:
                    stat["numeric_min"] = format(min(values), ".17g")
                    stat["numeric_max"] = format(max(values), ".17g")
                    stat["numeric_mean"] = format(fmean(values), ".17g")
            columns = stats
            file_row["parse_ok"] = True
    except Exception as error:  # audit must record, not hide, unreadable artifacts
        issues.append(f"parse_error:{type(error).__name__}:{error}")
    file_row["issues"] = "|".join(issues)
    file_row["issue_count"] = len(issues)
    return file_row, columns


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
    for path in sorted(run_root.rglob("*.csv")):
        file_row, columns = audit_csv(path, run_root)
        csv_rows.append(file_row)
        column_rows.extend(columns)
    image_paths = sorted(
        path for path in run_root.rglob("*")
        if io_path(path).is_file() and path.suffix.lower() in {".png", ".jpg", ".jpeg"}
    )
    image_rows = [audit_image(path, run_root) for path in image_paths]
    vector_paths = sorted(path for path in run_root.rglob("*.svg") if io_path(path).is_file())

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
    write_csv(output_root / "all_raster_image_audit.csv", image_rows)
    write_csv(output_root / "duplicate_csv_byte_hashes.csv", duplicate_files)
    write_csv(output_root / "duplicate_raster_byte_hashes.csv", duplicate_images)

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
    ) else 0


if __name__ == "__main__":
    raise SystemExit(main())
