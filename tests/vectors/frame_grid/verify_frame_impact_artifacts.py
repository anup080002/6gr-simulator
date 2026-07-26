#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageStat

HERE = Path(__file__).resolve().parent


def read_contract(name: str) -> list[dict[str, str]]:
    with (HERE / name).open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def read_csv(path: Path):
    with path.open(newline="", encoding="utf-8-sig") as handle:
        raw = list(csv.reader(handle))
    if not raw:
        return [], [], ["empty"]
    header = raw[0]
    errors = []
    if len(header) != len(set(header)):
        errors.append("duplicate_header")
    rows = []
    for line, values in enumerate(raw[1:], 2):
        if len(values) != len(header):
            errors.append(f"nonrectangular:{line}")
        else:
            rows.append(dict(zip(header, values)))
    if not rows:
        errors.append("no_rows")
    return header, rows, errors


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def source_hash(root: Path, names: list[str]) -> str:
    value = hashlib.sha256()
    for name in sorted(names):
        path = root / name
        if not path.exists():
            return ""
        value.update(name.encode())
        value.update(digest(path).encode())
    return value.hexdigest()


def truth(value: object) -> bool:
    return str(value).strip().upper() in {"1", "TRUE", "YES", "PASS"}


def finite(value: object):
    try:
        number = float(str(value).strip())
    except ValueError:
        return None
    return number if math.isfinite(number) else None


def verify(root: Path) -> int:
    failures: list[str] = []
    parsed: dict[str, list[dict[str, str]]] = {}
    csv_contract = read_contract("desired_frame_impact_csv_contract.csv")
    image_contract = read_contract("desired_frame_impact_image_contract.csv")
    matrix = read_contract("frame_impact_experiment_matrix.csv")
    rules = {
        row["RuleID"]: row
        for row in read_contract("frame_impact_acceptance_rules.csv")
    }

    for contract in csv_contract:
        name = contract["FileName"]
        path = root / name
        required = contract["RequiredColumns"].split("|")
        if not path.exists():
            failures.append("missing_csv:" + name)
            continue
        header, rows, errors = read_csv(path)
        parsed[name] = rows
        failures.extend(name + ":" + error for error in errors)
        missing = [column for column in required if column not in header]
        if missing:
            failures.append(name + ":missing_columns:" + ",".join(missing))
            continue
        keys = contract["PrimaryKey"].split("|")
        observed = set()
        for line, row in enumerate(rows, 2):
            key = tuple(row.get(column, "") for column in keys)
            if key in observed:
                failures.append(name + ":duplicate_key:" + repr(key))
            observed.add(key)
            if "Status" in row and row["Status"].upper() != "PASS":
                failures.append(name + f":nonpass_line:{line}")

    required_experiments = {row["ExperimentID"] for row in matrix}
    raw = parsed.get("frame_impact_raw_trials.csv", [])
    completed = {row.get("ExperimentID", "") for row in raw}
    missing_experiments = sorted(required_experiments - completed)
    if missing_experiments:
        failures.append("missing_experiments:" + ",".join(missing_experiments))
    if len(completed) != 36:
        failures.append(f"experiment_count:{len(completed)}")
    for line, row in enumerate(raw, 2):
        if finite(row.get("ObservedValue")) is None:
            failures.append(f"raw_nonfinite:line={line}")
        if not truth(row.get("SourceRowsPass")):
            failures.append(f"source_rows_failed:line={line}")
        if truth(row.get("TruthQualified")):
            failures.append(f"truth_relabel:line={line}")
        if "not_waveform_truth" not in row.get("ApproximationMode", ""):
            failures.append(f"missing_proxy_label:line={line}")

    evaluation = parsed.get("frame_impact_rule_evaluation.csv", [])
    observed_rules = {row.get("RuleID", "") for row in evaluation}
    missing_rules = sorted(set(rules) - observed_rules)
    if missing_rules:
        failures.append("missing_rules:" + ",".join(missing_rules))
    for line, row in enumerate(evaluation, 2):
        rule = rules.get(row.get("RuleID", ""))
        if rule is None:
            failures.append(f"unknown_rule:line={line}")
        elif rule["Severity"] == "HARD" and not truth(row.get("Passed")):
            failures.append("hard_rule_failed:" + rule["RuleID"])

    effects = parsed.get("frame_impact_pairwise_effects.csv", [])
    if len(effects) != 12:
        failures.append(f"effect_count:{len(effects)}")
    for line, row in enumerate(effects, 2):
        for column in (
            "BaselineValue",
            "TreatmentValue",
            "AbsoluteEffect",
            "CILower",
            "CIUpper",
            "PValue",
            "AdjustedPValue",
            "EffectSize",
        ):
            if finite(row.get(column)) is None:
                failures.append(f"effect_nonfinite:{column}:line={line}")

    summary = parsed.get("frame_impact_summary.csv", [])
    if len(summary) != 12:
        failures.append(f"summary_count:{len(summary)}")

    manifest = parsed.get("frame_impact_run_manifest.csv", [])
    if len(manifest) == 1:
        row = manifest[0]
        if truth(row.get("TruthQualified")):
            failures.append("manifest_truth_relabel")
        if row.get("BaseArtifactVerifierExit") != "0":
            failures.append("base_verifier_not_zero")

    audits = {
        row.get("ImageFile", ""): row
        for row in parsed.get("frame_impact_image_semantic_audit.csv", [])
    }
    for contract in image_contract:
        name = contract["ImageFile"]
        path = root / name
        if not path.exists():
            failures.append("missing_png:" + name)
            continue
        try:
            with Image.open(path) as image:
                image.load()
                width, height = image.size
                variance = ImageStat.Stat(image.convert("L")).var[0]
        except Exception as cause:  # pragma: no cover - diagnostic path
            failures.append("bad_png:" + name + ":" + str(cause))
            continue
        if width < int(contract["MinWidth"]) or height < int(
            contract["MinHeight"]
        ):
            failures.append("small_png:" + name)
        if variance < 1.0:
            failures.append("blank_png:" + name)
        audit = audits.get(name)
        if audit is None:
            failures.append("missing_image_audit:" + name)
            continue
        if audit.get("PNG_SHA256") != digest(path):
            failures.append("png_hash_mismatch:" + name)
        names = [item for item in contract["SourceCSV"].split("|") if item]
        if audit.get("SourceCSV_SHA256") != source_hash(root, names):
            failures.append("source_hash_mismatch:" + name)
        if int(float(audit.get("AxesCount", "0"))) < int(
            contract["MinAxesCount"]
        ):
            failures.append("axes_count:" + name)
        if int(float(audit.get("SeriesCount", "0"))) < int(
            contract["MinSeriesCount"]
        ):
            failures.append("series_count:" + name)
        if int(float(audit.get("FinitePointCount", "0"))) < int(
            contract["MinFinitePointCount"]
        ):
            failures.append("point_count:" + name)
        if contract["ExpectedTitleToken"].lower() not in audit.get(
            "ActualTitle", ""
        ).lower():
            failures.append("title:" + name)
        if " ".join(contract["ExpectedXLabel"].split()) != " ".join(
            audit.get("ActualXLabel", "").split()
        ):
            failures.append("xlabel:" + name)
        if " ".join(contract["ExpectedYLabel"].split()) != " ".join(
            audit.get("ActualYLabel", "").split()
        ):
            failures.append("ylabel:" + name)

    report = {
        "required_experiments": len(required_experiments),
        "completed_experiments": len(completed),
        "required_rules": len(rules),
        "evaluated_rules": len(observed_rules),
        "required_csvs": len(csv_contract),
        "required_pngs": len(image_contract),
        "failures": failures,
    }
    print(json.dumps(report, indent=2))
    return 0 if not failures else 2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    return verify(args.output_dir.resolve())


if __name__ == "__main__":
    raise SystemExit(main())
