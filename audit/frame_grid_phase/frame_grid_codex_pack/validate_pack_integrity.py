#!/usr/bin/env python3
"""Validate the supplied frame/grid vectors, golden CSVs, and audit summaries.

This checks the integrity and internal consistency of the implementation pack.
It is not a substitute for executing the production MATLAB simulator.
"""
from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def read_csv(name: str) -> list[dict[str, str]]:
    with (ROOT / name).open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    checks: list[dict[str, object]] = []

    def add(name: str, ok: bool, observed: object, expected: object, detail: str = "") -> None:
        checks.append({
            "Check": name,
            "Status": "PASS" if ok else "FAIL",
            "Observed": observed,
            "Expected": expected,
            "Detail": detail,
        })

    numerology = read_csv("frame_numerology_test_vectors.csv")
    add("numerology_vector_row_count", len(numerology) == 18, len(numerology), 18)
    for row in numerology:
        if row["ExpectedValid"].upper() != "TRUE":
            continue
        mu = int(row["Mu"])
        cp = row["CyclicPrefix"]
        ok = (
            int(row["SCS_kHz"]) == 15 * (2 ** mu)
            and int(row["ExpectedSlotsPerSubframe"]) == 2 ** mu
            and int(row["ExpectedSlotsPerFrame"]) == 10 * (2 ** mu)
            and int(row["ExpectedSymbolsPerSlot"]) == (12 if cp == "extended" else 14)
            and (cp != "extended" or mu == 2)
        )
        add(f"numerology_{row['TestID']}", ok, "formula_match", "formula_match", row["SpecAnchor"])

    carrier = read_csv("frame_carrier_grid_test_vectors.csv")
    add("carrier_vector_row_count", len(carrier) == 71, len(carrier), 71)
    valid_carrier = [row for row in carrier if row["ExpectedValid"].upper() == "TRUE"]
    invalid_carrier = [row for row in carrier if row["ExpectedValid"].upper() != "TRUE"]
    add(
        "carrier_valid_rows_have_nrb_guardband",
        all(row["ExpectedNRB"] and row["ExpectedMinGuardband_kHz"] for row in valid_carrier),
        len(valid_carrier),
        len(valid_carrier),
    )
    add(
        "carrier_invalid_rows_have_no_nrb_guardband",
        all(not row["ExpectedNRB"] and not row["ExpectedMinGuardband_kHz"] for row in invalid_carrier),
        len(invalid_carrier),
        len(invalid_carrier),
    )

    tdd = read_csv("frame_tdd_test_vectors.csv")
    add("tdd_vector_row_count", len(tdd) == 11, len(tdd), 11)
    valid_tdd = [row for row in tdd if row["ExpectedValid"].upper() == "TRUE"]
    for row in valid_tdd:
        symbols_per_slot = 12 if row["TestID"] == "TDD-011" else 14
        lengths = [len(slot) for slot in row["ExpectedSlotSymbolMap"].split("|")]
        add(
            f"tdd_map_{row['TestID']}",
            all(length == symbols_per_slot for length in lengths),
            str(lengths),
            f"all {symbols_per_slot}",
            row["Purpose"],
        )
    maps_with_unresolved_flex = sum("F" in row["ExpectedSlotSymbolMap"] for row in valid_tdd)
    add("tdd_vectors_preserve_unresolved_flex", maps_with_unresolved_flex == 5, maps_with_unresolved_flex, 5)

    allocation = read_csv("frame_allocation_test_vectors.csv")
    add("allocation_vector_row_count", len(allocation) == 14, len(allocation), 14)
    add(
        "allocation_vectors_include_positive_negative",
        any(row["ExpectedValid"] == "TRUE" for row in allocation)
        and any(row["ExpectedValid"] == "FALSE" for row in allocation),
        "both",
        "both",
    )

    expected_files = {
        "expected_frame_numerology_matrix.csv": 18,
        "expected_carrier_grid_matrix.csv": 71,
        "expected_slot_symbol_ownership.csv": 510,
        "expected_allocation_legality.csv": 14,
    }
    integrity_rows: list[dict[str, object]] = []
    for name, expected_count in expected_files.items():
        rows = read_csv(name)
        all_pass = all(row.get("Status") == "PASS" for row in rows)
        ok = len(rows) == expected_count and all_pass
        add(f"golden_{name}", ok, len(rows), expected_count)
        integrity_rows.append({
            "File": name,
            "Rows": len(rows),
            "AllStatusPASS": str(all_pass).upper(),
            "SHA256": sha256(ROOT / name),
            "Status": "PASS" if ok else "FAIL",
        })

    with (ROOT / "expected_output_integrity_audit.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(integrity_rows[0]))
        writer.writeheader()
        writer.writerows(integrity_rows)

    static = read_csv("current_frame_static_audit.csv")
    grid_comparison = read_csv("current_carrier_grid_comparison.csv")
    flex_regression = read_csv("current_tdd_flexible_symbol_regression.csv")
    existing_images = read_csv("existing_output_image_integrity_audit.csv")
    existing_csvs = read_csv("existing_output_csv_integrity_audit.csv")
    artifact_presence = read_csv("existing_frame_artifact_presence_audit.csv")
    reference_images = read_csv("reference_image_integrity_audit.csv")

    add("current_static_shortcut_failures", sum(row["CurrentStatus"] == "FAIL" for row in static) == 12,
        sum(row["CurrentStatus"] == "FAIL" for row in static), 12)
    add("current_carrier_grid_mismatches", sum(row["Status"] == "FAIL" for row in grid_comparison) == 17,
        sum(row["Status"] == "FAIL" for row in grid_comparison), 17)
    add("current_flexible_symbol_failures", sum(row["Status"] == "FAIL" for row in flex_regression) == 4,
        sum(row["Status"] == "FAIL" for row in flex_regression), 4)
    add("existing_png_structural_passes", len(existing_images) == 40 and all(row["Status"] == "PASS" for row in existing_images),
        sum(row["Status"] == "PASS" for row in existing_images), 40)
    add("existing_csv_parse_passes", len(existing_csvs) == 5 and all(row["Status"] == "PASS" for row in existing_csvs),
        sum(row["Status"] == "PASS" for row in existing_csvs), 5)
    add("required_frame_artifacts_absent", len(artifact_presence) == 18 and all(row["Status"] == "FAIL" for row in artifact_presence),
        sum(row["Status"] == "FAIL" for row in artifact_presence), 18)
    add("reference_image_integrity", len(reference_images) == 4 and all(row["Status"] == "PASS" for row in reference_images),
        sum(row["Status"] == "PASS" for row in reference_images), 4)

    positive = json.loads((ROOT / "verifier_selftest_pass.json").read_text(encoding="utf-8"))
    negative = json.loads((ROOT / "verifier_selftest_negative.json").read_text(encoding="utf-8"))
    add("artifact_verifier_positive_selftest", positive["pass"] == 25 and positive["fail"] == 0,
        f"pass={positive['pass']};fail={positive['fail']}", "pass=25;fail=0")
    add("artifact_verifier_negative_selftest", negative["fail"] == 1,
        f"pass={negative['pass']};fail={negative['fail']}", "exactly one injected failure")

    with (ROOT / "limited_vector_validation.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(checks[0]))
        writer.writeheader()
        writer.writerows(checks)

    prompt_path = ROOT / "CODEX_PROMPT_01_FRAME_GRID_NUMEROLOGY_DUPLEXING.md"
    summary = {
        "repository": "/mnt/data/6gr_work/6GR Simulator_v2_clean_main",
        "output": str(ROOT),
        "matlab_available": False,
        "prompt": {
            "lines": sum(1 for _ in prompt_path.open(encoding="utf-8")),
            "bytes": prompt_path.stat().st_size,
        },
        "vectors": {"numerology": 18, "carrier_grid": 71, "tdd": 11, "allocation": 14, "total": 114},
        "golden_expected_outputs": {
            "numerology_rows": 18,
            "carrier_rows": 71,
            "slot_symbol_rows": 510,
            "allocation_rows": 14,
        },
        "current_audit": {
            "static_failures": 12,
            "carrier_grid_mismatches": 17,
            "flexible_symbol_failures": 4,
            "existing_frame_artifacts_missing": 18,
        },
        "existing_outputs": {"png_checked": 40, "png_failed": 0, "csv_checked": 5, "csv_failed": 0},
        "reference_images": {"checked": 4, "failed": 0},
        "verifier_selftest": {"positive_pass": 25, "positive_fail": 0, "negative_injected_failures_detected": 1},
        "vector_validation": {"checks": len(checks), "failed": sum(row["Status"] != "PASS" for row in checks)},
    }
    (ROOT / "limited_test_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    summary_rows: list[dict[str, object]] = []
    for section, values in summary.items():
        if isinstance(values, dict):
            for metric, value in values.items():
                summary_rows.append({
                    "Section": section,
                    "Metric": metric,
                    "Value": json.dumps(value) if isinstance(value, (dict, list)) else value,
                })
        else:
            summary_rows.append({"Section": "general", "Metric": section, "Value": values})
    with (ROOT / "limited_test_summary.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=("Section", "Metric", "Value"))
        writer.writeheader()
        writer.writerows(summary_rows)

    failures = [row for row in checks if row["Status"] != "PASS"]
    print(json.dumps({"checks": len(checks), "failed": len(failures)}, indent=2))
    return 0 if not failures else 2


if __name__ == "__main__":
    raise SystemExit(main())
