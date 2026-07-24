#!/usr/bin/env python3
"""Post-run verifier for the frame/grid MATLAB phase artifacts.

Usage:
    python verify_frame_artifacts.py /path/to/frame_phase_output

This verifier checks deterministic file presence, CSV rectangularity/schema,
primary-key uniqueness, PASS status rows, required test-summary zero counts,
PNG decoding/dimensions/nonblank content, SHA-256 hashes, and the links recorded
in frame_image_audit.csv between each PNG and its source CSV.

It deliberately does not use OCR. Semantic plot correctness must be checked in
MATLAB before export by inspecting axes and plotted XData/YData/CData; those
results are then recorded in frame_image_audit.csv and verified here.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

try:
    from PIL import Image, ImageStat
except ImportError as exc:  # pragma: no cover - explicit dependency failure
    raise SystemExit("Pillow is required: python -m pip install Pillow") from exc


@dataclass(frozen=True)
class CsvContract:
    columns: tuple[str, ...]
    key: tuple[str, ...]


REQUIRED_CSV: dict[str, CsvContract] = {
    "frame_numerology_matrix.csv": CsvContract(
        ("TestID", "Mu", "SCS_kHz", "CyclicPrefix", "ExpectedValid", "ResolvedValid",
         "ExpectedSymbolsPerSlot", "ResolvedSymbolsPerSlot", "ExpectedSlotsPerSubframe",
         "ResolvedSlotsPerSubframe", "ExpectedSlotsPerFrame", "ResolvedSlotsPerFrame",
         "ErrorID", "Status"),
        ("TestID",),
    ),
    "carrier_grid_matrix.csv": CsvContract(
        ("TestID", "Role", "FrequencyRange", "CenterFrequency_Hz", "ChannelBandwidth_MHz",
         "CarrierSCS_kHz", "ExpectedValid", "ResolvedValid", "ExpectedNRB", "ResolvedNRB",
         "NStartGrid", "OccupiedBandwidth_Hz", "GuardbandLow_Hz", "GuardbandHigh_Hz",
         "ErrorID", "Status"),
        ("TestID",),
    ),
    "slot_symbol_ownership.csv": CsvContract(
        ("TestID", "CellID", "CCID", "BWPID", "Frame", "Slot", "Symbol",
         "CommonDirection", "DedicatedDirection", "ResolvedDirection", "ResolutionSource",
         "AllocationOwner", "Status"),
        ("TestID", "CCID", "BWPID", "Frame", "Slot", "Symbol"),
    ),
    "resource_grid_occupancy.csv": CsvContract(
        ("TestID", "CCID", "BWPID", "Slot", "Symbol", "RB", "Port", "Channel",
         "Direction", "CollisionFlag", "ReservedReason", "Status"),
        ("TestID", "CCID", "BWPID", "Slot", "Symbol", "RB", "Port"),
    ),
    "allocation_legality.csv": CsvContract(
        ("TestID", "Channel", "Direction", "CCID", "BWPID", "AbsoluteSlot", "StartSymbol",
         "NumSymbols", "StartRB", "NumRB", "FlexDecision", "ExpectedValid", "ActualValid",
         "ReasonCode", "Status"),
        ("TestID",),
    ),
    "ofdm_roundtrip.csv": CsvContract(
        ("TestID", "Mu", "SCS_kHz", "CyclicPrefix", "NRB", "Nfft", "SampleRate_Hz",
         "CPLengthsSamples", "WindowingSamples", "OccupiedBandwidth_Hz", "GuardbandLow_Hz",
         "GuardbandHigh_Hz", "TxGridPower", "RxGridPower", "NMSE", "EVMPercent",
         "AliasingMargin_Hz", "Status"),
        ("TestID",),
    ),
    "timing_matrix.csv": CsvContract(
        ("TestID", "Procedure", "PDCCHAbsSlot", "SourceMu", "TargetMu", "K0", "K1", "K2",
         "TargetAbsSlot", "StartSymbol", "ProcessingTimeSymbols", "AvailableSymbols",
         "ExpectedValid", "ActualValid", "ReasonCode", "Status"),
        ("TestID",),
    ),
    "bwp_switch_trace.csv": CsvContract(
        ("TestID", "UEID", "CCID", "Direction", "AbsSlot", "OldBWPID", "CommandedBWPID",
         "ActivationAbsSlot", "ActiveBWPID", "TriggerSource", "ExpectedValid", "ActualValid",
         "ReasonCode", "Status"),
        ("TestID", "UEID", "CCID", "Direction", "AbsSlot"),
    ),
    "component_carrier_trace.csv": CsvContract(
        ("TestID", "UEID", "SchedulingCellID", "ScheduledCellID", "CarrierIndicator",
         "AbsSlot", "GrantType", "HARQProcessID", "BWPID", "ExpectedValid", "ActualValid",
         "ReasonCode", "Status"),
        ("TestID", "UEID", "AbsSlot", "GrantType", "HARQProcessID"),
    ),
    "frame_fix_test_summary.csv": CsvContract(
        ("Suite", "TestsRun", "Passed", "Failed", "Skipped", "Blocked", "Status", "ResultFile"),
        ("Suite",),
    ),
    "frame_image_audit.csv": CsvContract(
        ("ImageFile", "SourceCSV", "SourceCSV_SHA256", "ImageSHA256", "Width", "Height", "Mode",
         "FileBytes", "NonBlankFraction", "PixelStdDev", "ExpectedAxes", "ObservedAxes",
         "ExpectedSeries", "ObservedSeries", "Status", "Reason"),
        ("ImageFile",),
    ),
}

IMAGE_SOURCE: dict[str, str] = {
    "frame_slot_symbol_map.png": "slot_symbol_ownership.csv",
    "resource_grid_occupancy.png": "resource_grid_occupancy.csv",
    "numerology_timing_matrix.png": "frame_numerology_matrix.csv",
    "carrier_guardband_map.png": "carrier_grid_matrix.csv",
    "k0_k1_k2_timeline.png": "timing_matrix.csv",
    "bwp_switch_timeline.png": "bwp_switch_trace.csv",
    "component_carrier_resource_map.png": "component_carrier_trace.csv",
    "ssb_timing_map.png": "ssb_timing_matrix.csv",
    "prach_occasion_map.png": "prach_occasion_matrix.csv",
}

MIN_WIDTH = 1200
MIN_HEIGHT = 650
MIN_BYTES = 1_000
MIN_PIXEL_STDDEV = 1.0
MIN_NONBLANK_FRACTION = 0.001


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def normalize_bool(value: str) -> bool | None:
    token = str(value).strip().upper()
    if token in {"TRUE", "1", "YES"}:
        return True
    if token in {"FALSE", "0", "NO"}:
        return False
    return None


def finite_number(value: str) -> float | None:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    return parsed if math.isfinite(parsed) else None


def read_rectangular_csv(path: Path) -> tuple[list[str], list[dict[str, str]], list[str]]:
    errors: list[str] = []
    with path.open("r", newline="", encoding="utf-8-sig") as handle:
        raw_rows = list(csv.reader(handle))
    if not raw_rows:
        return [], [], ["empty_file"]
    header = raw_rows[0]
    if not header or any(not str(item).strip() for item in header):
        errors.append("empty_header_name")
    if len(set(header)) != len(header):
        errors.append("duplicate_header_name")
    expected_width = len(header)
    for line_number, raw in enumerate(raw_rows[1:], start=2):
        if len(raw) != expected_width:
            errors.append(f"nonrectangular_line:{line_number}:expected={expected_width}:actual={len(raw)}")
    if errors:
        return header, [], errors
    rows = [dict(zip(header, raw, strict=True)) for raw in raw_rows[1:]]
    if not rows:
        errors.append("no_data_rows")
    return header, rows, errors


def duplicate_keys(rows: Iterable[dict[str, str]], key_fields: tuple[str, ...]) -> list[str]:
    seen: set[tuple[str, ...]] = set()
    duplicates: list[str] = []
    for index, row in enumerate(rows, start=2):
        key = tuple(str(row.get(field, "")) for field in key_fields)
        if key in seen:
            duplicates.append(f"line={index}:key={key}")
        seen.add(key)
    return duplicates


def row_result(artifact: str, artifact_type: str, status: str, reasons: list[str], **extra: object) -> dict[str, object]:
    out: dict[str, object] = {
        "Artifact": artifact,
        "Type": artifact_type,
        "Status": status,
        "Reason": ";".join(reasons),
    }
    out.update(extra)
    return out


def verify_csvs(root: Path) -> tuple[list[dict[str, object]], dict[str, list[dict[str, str]]]]:
    results: list[dict[str, object]] = []
    parsed: dict[str, list[dict[str, str]]] = {}
    for name, contract in REQUIRED_CSV.items():
        path = root / name
        reasons: list[str] = []
        if not path.is_file():
            results.append(row_result(name, "CSV", "FAIL", ["missing"]))
            continue
        try:
            header, rows, parse_errors = read_rectangular_csv(path)
            reasons.extend(parse_errors)
            missing = [column for column in contract.columns if column not in header]
            if missing:
                reasons.append("missing_columns:" + ",".join(missing))
            if rows and not missing:
                bad_status = [str(index) for index, row in enumerate(rows, start=2)
                              if str(row.get("Status", "")).strip().upper() != "PASS"]
                if bad_status:
                    reasons.append("non_pass_rows:" + ",".join(bad_status[:50]))
                duplicates = duplicate_keys(rows, contract.key)
                if duplicates:
                    reasons.append("duplicate_keys:" + "|".join(duplicates[:20]))
            if name == "frame_fix_test_summary.csv" and rows:
                for index, row in enumerate(rows, start=2):
                    for field in ("Failed", "Skipped", "Blocked"):
                        number = finite_number(row.get(field, ""))
                        if number is None or number != 0:
                            reasons.append(f"summary_{field.lower()}_nonzero_or_invalid:line={index}:value={row.get(field,'')}")
                    run = finite_number(row.get("TestsRun", ""))
                    passed = finite_number(row.get("Passed", ""))
                    if run is None or passed is None or run <= 0 or passed != run:
                        reasons.append(f"summary_count_mismatch:line={index}")
            status = "PASS" if not reasons else "FAIL"
            results.append(row_result(name, "CSV", status, reasons, Rows=len(rows), Columns=len(header), SHA256=digest(path)))
            parsed[name] = rows
        except Exception as exc:  # pragma: no cover - defensive output
            results.append(row_result(name, "CSV", "FAIL", [f"parse:{type(exc).__name__}:{exc}"]))
    return results, parsed


def verify_images(root: Path) -> tuple[list[dict[str, object]], dict[str, dict[str, object]]]:
    results: list[dict[str, object]] = []
    metadata: dict[str, dict[str, object]] = {}
    for name in IMAGE_SOURCE:
        path = root / name
        reasons: list[str] = []
        if not path.is_file():
            results.append(row_result(name, "PNG", "FAIL", ["missing"]))
            continue
        try:
            with Image.open(path) as image:
                image.load()
                width, height = image.size
                mode = image.mode
                gray = image.convert("L")
                stat = ImageStat.Stat(gray)
                histogram = gray.histogram()
                nonblank_fraction = sum(histogram[:250]) / float(width * height)
                pixel_stddev = float(stat.stddev[0])
            file_bytes = path.stat().st_size
            sha = digest(path)
            if width < MIN_WIDTH or height < MIN_HEIGHT:
                reasons.append(f"dimensions_below_minimum:{width}x{height}")
            if file_bytes <= MIN_BYTES:
                reasons.append(f"file_too_small:{file_bytes}")
            if pixel_stddev <= MIN_PIXEL_STDDEV:
                reasons.append(f"pixel_stddev_too_low:{pixel_stddev}")
            if nonblank_fraction <= MIN_NONBLANK_FRACTION:
                reasons.append(f"nonblank_fraction_too_low:{nonblank_fraction}")
            status = "PASS" if not reasons else "FAIL"
            item = {
                "Width": width,
                "Height": height,
                "Mode": mode,
                "FileBytes": file_bytes,
                "PixelStdDev": pixel_stddev,
                "NonBlankFraction": nonblank_fraction,
                "SHA256": sha,
            }
            metadata[name] = item
            results.append(row_result(name, "PNG", status, reasons, **item))
        except Exception as exc:
            results.append(row_result(name, "PNG", "FAIL", [f"decode:{type(exc).__name__}:{exc}"]))
    return results, metadata


def verify_image_audit_links(root: Path, parsed_csv: dict[str, list[dict[str, str]]], image_meta: dict[str, dict[str, object]]) -> list[dict[str, object]]:
    results: list[dict[str, object]] = []
    rows = parsed_csv.get("frame_image_audit.csv", [])
    by_image: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_image.setdefault(str(row.get("ImageFile", "")), []).append(row)

    for image_name, expected_source in IMAGE_SOURCE.items():
        reasons: list[str] = []
        matches = by_image.get(image_name, [])
        if len(matches) != 1:
            reasons.append(f"audit_row_count:{len(matches)}")
            results.append(row_result(image_name, "IMAGE_AUDIT_LINK", "FAIL", reasons))
            continue
        row = matches[0]
        source_name = str(row.get("SourceCSV", ""))
        if source_name != expected_source:
            reasons.append(f"wrong_source_csv:expected={expected_source}:actual={source_name}")
        source_path = root / source_name
        if not source_path.is_file():
            reasons.append("source_csv_missing")
        else:
            actual_source_sha = digest(source_path)
            if str(row.get("SourceCSV_SHA256", "")).lower() != actual_source_sha.lower():
                reasons.append("source_csv_hash_mismatch")
        meta = image_meta.get(image_name)
        if meta is None:
            reasons.append("image_metadata_unavailable")
        else:
            if str(row.get("ImageSHA256", "")).lower() != str(meta["SHA256"]).lower():
                reasons.append("image_hash_mismatch")
            for field in ("Width", "Height", "FileBytes"):
                observed = finite_number(row.get(field, ""))
                if observed is None or int(observed) != int(meta[field]):
                    reasons.append(f"{field.lower()}_mismatch")
            if str(row.get("Mode", "")) != str(meta["Mode"]):
                reasons.append("mode_mismatch")
        expected_axes = finite_number(row.get("ExpectedAxes", ""))
        observed_axes = finite_number(row.get("ObservedAxes", ""))
        if expected_axes is None or observed_axes is None or observed_axes != expected_axes or observed_axes < 1:
            reasons.append("axes_semantic_check_failed")
        expected_series = finite_number(row.get("ExpectedSeries", ""))
        observed_series = finite_number(row.get("ObservedSeries", ""))
        if expected_series is None or observed_series is None or observed_series != expected_series or observed_series < 1:
            reasons.append("series_semantic_check_failed")
        if str(row.get("Status", "")).upper() != "PASS":
            reasons.append("matlab_semantic_status_not_pass")
        results.append(row_result(image_name, "IMAGE_AUDIT_LINK", "PASS" if not reasons else "FAIL", reasons))

    unexpected = sorted(set(by_image) - set(IMAGE_SOURCE))
    for name in unexpected:
        results.append(row_result(name, "IMAGE_AUDIT_LINK", "FAIL", ["unexpected_image_audit_row"]))
    return results


def write_report(root: Path, rows: list[dict[str, object]]) -> tuple[Path, Path]:
    csv_path = root / "frame_artifact_verification.csv"
    json_path = root / "frame_artifact_verification.json"
    keys = sorted({key for row in rows for key in row})
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=keys)
        writer.writeheader()
        writer.writerows(rows)
    summary = {
        "root": str(root),
        "pass": sum(row["Status"] == "PASS" for row in rows),
        "fail": sum(row["Status"] != "PASS" for row in rows),
        "rows": rows,
    }
    json_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps({key: summary[key] for key in ("root", "pass", "fail")}, indent=2))
    return csv_path, json_path


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_dir", type=Path, help="Directory produced by runFrameGridPhaseTests.m")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    root = args.output_dir.expanduser().resolve()
    if not root.is_dir():
        print(f"output directory does not exist: {root}", file=sys.stderr)
        return 66
    csv_results, parsed_csv = verify_csvs(root)
    image_results, image_meta = verify_images(root)
    link_results = verify_image_audit_links(root, parsed_csv, image_meta)
    all_results = csv_results + image_results + link_results
    write_report(root, all_results)
    return 0 if all(row["Status"] == "PASS" for row in all_results) else 2


if __name__ == "__main__":
    raise SystemExit(main())
