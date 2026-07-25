#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import tempfile
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageStat
except ImportError as exc:  # pragma: no cover - execution environment guard
    raise SystemExit("Pillow is required") from exc

HERE = Path(__file__).resolve().parent


def truth(value: object) -> bool:
    return str(value).strip().upper() in {"1", "TRUE", "YES", "PASS"}


def finite(value: object) -> float | None:
    try:
        result = float(str(value).strip())
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


def integer(value: object) -> int | None:
    parsed = finite(value)
    if parsed is None or abs(parsed - round(parsed)) > 1e-9:
        return None
    return int(round(parsed))


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]], list[str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        raw = list(csv.reader(handle))
    if not raw:
        return [], [], ["empty"]
    header = raw[0]
    errors: list[str] = []
    if len(header) != len(set(header)):
        errors.append("duplicate_header")
    rows: list[dict[str, str]] = []
    for line_number, row in enumerate(raw[1:], 2):
        if len(row) != len(header):
            errors.append(f"nonrectangular:{line_number}")
        else:
            rows.append(dict(zip(header, row)))
    if not rows:
        errors.append("no_rows")
    return header, rows, errors


def contract_rows(name: str) -> list[dict[str, str]]:
    with (HERE / name).open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def source_hash(root: Path, names: list[str]) -> str:
    hasher = hashlib.sha256()
    for name in sorted(filter(None, names)):
        path = root / name
        if not path.exists():
            return ""
        hasher.update(name.encode("utf-8"))
        hasher.update(digest(path).encode("ascii"))
    return hasher.hexdigest()


def verify(root: Path) -> int:
    failures: list[str] = []
    parsed: dict[str, list[dict[str, str]]] = {}
    csv_contracts = contract_rows("desired_pdcch_impact_csv_contract.csv")
    image_contracts = contract_rows("desired_pdcch_impact_image_contract.csv")
    experiments = contract_rows("pdcch_impact_experiment_matrix.csv")
    rules = contract_rows("pdcch_impact_acceptance_rules.csv")
    mandatory_experiments = {row["ExperimentID"] for row in experiments}
    rule_map = {row["RuleID"]: row for row in rules}

    for contract in csv_contracts:
        path = root / contract["FileName"]
        required_columns = [column for column in contract["RequiredColumns"].split("|") if column]
        if not path.exists():
            failures.append("missing_csv:" + path.name)
            continue
        header, rows, errors = read_csv(path)
        parsed[path.name] = rows
        failures.extend(path.name + ":" + error for error in errors)
        missing_columns = [column for column in required_columns if column not in header]
        if missing_columns:
            failures.append(path.name + ":missing_columns:" + ",".join(missing_columns))
            continue
        if len(rows) < int(contract["MinRows"]):
            failures.append(path.name + ":too_few_rows")
        primary_keys = [column for column in contract["PrimaryKey"].split("|") if column]
        seen: set[tuple[str, ...]] = set()
        for line_number, row in enumerate(rows, 2):
            key = tuple(row.get(column, "") for column in primary_keys)
            if key in seen:
                failures.append(path.name + ":duplicate_key:" + repr(key))
            seen.add(key)
            if "Status" in row and str(row["Status"]).upper() != "PASS":
                failures.append(path.name + f":nonpass:{line_number}")

    manifest_rows = parsed.get("pdcch_impact_run_manifest.csv", [])
    for line_number, row in enumerate(manifest_rows, 2):
        for field in ["RunID", "GitCommit", "MATLABVersion", "ToolboxVersion", "SeedList", "ExperimentMatrixSHA256"]:
            if not row.get(field, "").strip():
                failures.append(f"manifest_missing:{field}:{line_number}")
        if finite(row.get("ConfidenceLevel")) is None:
            failures.append(f"manifest_confidence_nonfinite:{line_number}")

    raw_trials = parsed.get("pdcch_impact_raw_trials.csv", [])
    input_experiment_map = {row["ExperimentID"]: row for row in experiments}
    pair_variants: dict[tuple[str, str], set[str]] = {}
    for line_number, row in enumerate(raw_trials, 2):
        if row.get("ExperimentID") not in mandatory_experiments:
            failures.append(f"raw_trial_unknown_experiment:{line_number}")
        if not row.get("PairID", "").strip() or not row.get("Variant", "").strip():
            failures.append(f"raw_trial_pairing_missing:{line_number}")
        for field in ["MeasuredSINRdB", "RuntimeMs", "MemoryMB"]:
            if finite(row.get(field)) is None:
                failures.append(f"raw_trial_nonfinite:{field}:{line_number}")
        expected_experiment = input_experiment_map.get(row.get("ExperimentID", ""))
        if expected_experiment is not None:
            for field in ["FamilyID", "PairID", "Variant", "FactorName", "FactorValue", "BaselineFactorValue"]:
                if row.get(field) != expected_experiment.get(field):
                    failures.append(f"raw_trial_experiment_mismatch:{field}:{line_number}")
            pair_variants.setdefault((row.get("FamilyID", ""), row.get("PairID", "")), set()).add(row.get("Variant", ""))
        for field in ["ChannelRealizationID", "NoiseRealizationID", "PayloadID"]:
            if not row.get(field, "").strip():
                failures.append(f"raw_trial_pairing_id_missing:{field}:{line_number}")
        signal_present = truth(row.get("SignalPresent"))
        correct = truth(row.get("CorrectDetection"))
        false_alarm = truth(row.get("FalseAlarm"))
        missed = truth(row.get("MissedDetection"))
        if signal_present and correct == missed:
            failures.append(f"raw_trial_detection_partition:{line_number}")
        if not signal_present and correct:
            failures.append(f"raw_trial_no_signal_correct_detection:{line_number}")
        if false_alarm and correct:
            failures.append(f"raw_trial_false_alarm_and_correct:{line_number}")

    for pair_key, variants in pair_variants.items():
        if variants != {"baseline", "treatment"}:
            failures.append("raw_trial_pair_incomplete:" + repr(pair_key))

    operating_points = parsed.get("pdcch_impact_operating_points.csv", [])
    completed = {row.get("ExperimentID") for row in operating_points}
    missing_experiments = mandatory_experiments - completed
    if missing_experiments:
        failures.append("missing_experiments:" + ",".join(sorted(missing_experiments)[:50]))
    for line_number, row in enumerate(operating_points, 2):
        if row.get("ExperimentID") not in mandatory_experiments:
            failures.append(f"operating_point_unknown_experiment:{line_number}")
        if truth(row.get("Incomplete")):
            failures.append(f"incomplete:{line_number}")
        numeric_fields = [
            "Trials",
            "CorrectDetections",
            "Misses",
            "FalseAlarms",
            "DetectionProbability",
            "DetectionCILower",
            "DetectionCIUpper",
            "FalseAlarmProbability",
            "FalseAlarmCIUpper",
            "MeanRuntimeMs",
            "MeanMemoryMB",
        ]
        for field in numeric_fields:
            if finite(row.get(field)) is None:
                failures.append(f"nonfinite:{field}:{line_number}")
        trials = integer(row.get("Trials"))
        correct = integer(row.get("CorrectDetections"))
        misses = integer(row.get("Misses"))
        false_alarms = integer(row.get("FalseAlarms"))
        if None not in {trials, correct, misses} and correct + misses > trials:
            failures.append(f"operating_point_count_inconsistent:{line_number}")
        if None not in {trials, false_alarms} and false_alarms > trials:
            failures.append(f"operating_point_false_alarm_count:{line_number}")
        probability_fields = [
            "DetectionProbability",
            "DetectionCILower",
            "DetectionCIUpper",
            "FalseAlarmProbability",
            "FalseAlarmCIUpper",
        ]
        for field in probability_fields:
            value = finite(row.get(field))
            if value is not None and not (0.0 <= value <= 1.0):
                failures.append(f"probability_out_of_range:{field}:{line_number}")
        lower = finite(row.get("DetectionCILower"))
        estimate = finite(row.get("DetectionProbability"))
        upper = finite(row.get("DetectionCIUpper"))
        if None not in {lower, estimate, upper} and not (lower <= estimate <= upper):
            failures.append(f"detection_ci_order:{line_number}")

    rule_evaluations = parsed.get("pdcch_impact_rule_evaluation.csv", [])
    seen_rules = {row.get("RuleID") for row in rule_evaluations}
    missing_rules = set(rule_map) - seen_rules
    if missing_rules:
        failures.append("missing_rules:" + ",".join(sorted(missing_rules)))
    for line_number, row in enumerate(rule_evaluations, 2):
        rule_id = row.get("RuleID")
        if rule_id not in rule_map:
            failures.append(f"unknown_rule:{rule_id}:{line_number}")
            continue
        if row.get("FamilyID") != rule_map[rule_id]["FamilyID"]:
            failures.append(f"rule_family_mismatch:{rule_id}:{line_number}")
        if rule_map[rule_id]["Severity"] == "HARD" and not truth(row.get("Passed")):
            failures.append(f"hard_rule_failed:{rule_id}:{line_number}")
        if finite(row.get("ObservedValue")) is None:
            failures.append(f"rule_observed_nonfinite:{rule_id}:{line_number}")
        if not row.get("EvidenceCSV", "").strip():
            failures.append(f"rule_evidence_missing:{rule_id}:{line_number}")

    for line_number, row in enumerate(parsed.get("pdcch_impact_pairwise_effects.csv", []), 2):
        numeric_fields = [
            "BaselineValue",
            "TreatmentValue",
            "AbsoluteEffect",
            "RelativeEffect",
            "CILower",
            "CIUpper",
            "PValue",
            "AdjustedPValue",
            "EffectSize",
        ]
        for field in numeric_fields:
            if finite(row.get(field)) is None:
                failures.append(f"effect_nonfinite:{field}:{line_number}")
        baseline = finite(row.get("BaselineValue"))
        treatment = finite(row.get("TreatmentValue"))
        effect = finite(row.get("AbsoluteEffect"))
        if None not in {baseline, treatment, effect} and abs((treatment - baseline) - effect) > 1e-9:
            failures.append(f"effect_sign_convention:{line_number}")
        p_value = finite(row.get("PValue"))
        adjusted = finite(row.get("AdjustedPValue"))
        if p_value is not None and not (0 <= p_value <= 1):
            failures.append(f"pvalue_range:{line_number}")
        if adjusted is not None and not (0 <= adjusted <= 1):
            failures.append(f"adjusted_pvalue_range:{line_number}")
        if adjusted is not None and p_value is not None and adjusted + 1e-12 < p_value:
            failures.append(f"adjusted_pvalue_smaller:{line_number}")

    for line_number, row in enumerate(parsed.get("pdcch_impact_summary.csv", []), 2):
        required = integer(row.get("ExperimentsRequired"))
        completed_count = integer(row.get("ExperimentsCompleted"))
        hard_failed = integer(row.get("HardRulesFailed"))
        if None in {required, completed_count, hard_failed}:
            failures.append(f"summary_noninteger:{line_number}")
        else:
            if completed_count != required:
                failures.append(f"summary_incomplete:{line_number}")
            if hard_failed != 0:
                failures.append(f"summary_hard_rules_failed:{line_number}")

    audit = {row.get("ImageFile", ""): row for row in parsed.get("pdcch_impact_image_semantic_audit.csv", [])}
    for contract in image_contracts:
        path = root / contract["ImageFile"]
        name = path.name
        if not path.exists():
            failures.append("missing_png:" + name)
            continue
        try:
            with Image.open(path) as image:
                image.load()
                width, height = image.size
                variance = ImageStat.Stat(image.convert("L")).var[0]
        except Exception as exc:
            failures.append("bad_png:" + name + ":" + str(exc))
            continue
        if width < int(contract["MinWidth"]) or height < int(contract["MinHeight"]):
            failures.append("small_png:" + name)
        if variance < 1.0:
            failures.append("blank_png:" + name)
        audit_row = audit.get(name)
        if not audit_row:
            failures.append("missing_image_audit:" + name)
            continue
        if integer(audit_row.get("Width")) != width or integer(audit_row.get("Height")) != height:
            failures.append("image_dimension_audit_mismatch:" + name)
        if audit_row.get("PNG_SHA256") != digest(path):
            failures.append("png_hash_mismatch:" + name)
        sources = [item for item in contract["SourceCSV"].split("|") if item]
        if audit_row.get("SourceCSV_SHA256") != source_hash(root, sources):
            failures.append("source_hash_mismatch:" + name)
        if integer(audit_row.get("AxesCount")) is None or integer(audit_row.get("AxesCount")) < int(contract["MinAxesCount"]):
            failures.append("axes:" + name)
        if integer(audit_row.get("SeriesCount")) is None or integer(audit_row.get("SeriesCount")) < int(contract["MinSeriesCount"]):
            failures.append("series:" + name)
        if integer(audit_row.get("FinitePointCount")) is None or integer(audit_row.get("FinitePointCount")) < int(contract["MinFinitePointCount"]):
            failures.append("points:" + name)
        if contract["ExpectedTitleToken"].lower() not in audit_row.get("ActualTitle", "").lower():
            failures.append("title:" + name)
        if " ".join(contract["ExpectedXLabel"].split()) != " ".join(audit_row.get("ActualXLabel", "").split()):
            failures.append("xlabel:" + name)
        if " ".join(contract["ExpectedYLabel"].split()) != " ".join(audit_row.get("ActualYLabel", "").split()):
            failures.append("ylabel:" + name)

    result = {
        "required_experiments": len(mandatory_experiments),
        "completed_experiments": len(completed),
        "required_rules": len(rule_map),
        "required_csvs": len(csv_contracts),
        "required_pngs": len(image_contracts),
        "failures": failures,
    }
    print(json.dumps(result, indent=2))
    return 0 if not failures else 2


def write_csv(path: Path, columns: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def base_row(columns: list[str], index: int) -> dict[str, str]:
    row = {column: "1" for column in columns}
    defaults = {
        "RunID": "SYNTHETIC",
        "Status": "PASS",
        "Passed": "true",
        "Incomplete": "false",
        "Seed": "11",
        "Trial": str(index),
        "Variant": "baseline",
        "PairID": f"PAIR-{index:04d}",
        "OperatingPointID": f"OP-{index:04d}",
    }
    for key, value in defaults.items():
        if key in row:
            row[key] = value
    return row


def self_test() -> int:
    csv_contracts = contract_rows("desired_pdcch_impact_csv_contract.csv")
    image_contracts = contract_rows("desired_pdcch_impact_image_contract.csv")
    experiments = contract_rows("pdcch_impact_experiment_matrix.csv")
    rules = contract_rows("pdcch_impact_acceptance_rules.csv")
    families = contract_rows("pdcch_impact_analysis_families.csv")

    with tempfile.TemporaryDirectory() as temp_dir:
        root = Path(temp_dir)
        semantic_contract: tuple[dict[str, str], list[str]] | None = None

        for contract in csv_contracts:
            columns = [column for column in contract["RequiredColumns"].split("|") if column]
            name = contract["FileName"]
            if name == "pdcch_impact_image_semantic_audit.csv":
                semantic_contract = (contract, columns)
                continue
            rows: list[dict[str, object]] = []

            if name == "pdcch_impact_run_manifest.csv":
                row = base_row(columns, 0)
                row.update(
                    GitCommit="0" * 40,
                    MATLABVersion="R2025b",
                    ToolboxVersion="25.2",
                    SeedList="11|23|47|89",
                    ConfidenceLevel="0.95",
                    ExperimentMatrixSHA256=digest(HERE / "pdcch_impact_experiment_matrix.csv"),
                )
                rows = [row]
            elif name in {"pdcch_impact_raw_trials.csv", "pdcch_impact_operating_points.csv"}:
                for index, experiment in enumerate(experiments):
                    row = base_row(columns, index)
                    row.update(
                        ExperimentID=experiment["ExperimentID"],
                        FamilyID=experiment["FamilyID"],
                        PairID=experiment["PairID"],
                        Variant=experiment["Variant"],
                        FactorName=experiment["FactorName"],
                        FactorValue=experiment["FactorValue"],
                        BaselineFactorValue=experiment["BaselineFactorValue"],
                        ChannelRealizationID=f"CHAN-{experiment['PairID']}-{index//2}",
                        NoiseRealizationID=f"NOISE-{experiment['PairID']}-{index//2}",
                        PayloadID=f"PAYLOAD-{experiment['PairID']}-{index//2}",
                    )
                    if name == "pdcch_impact_raw_trials.csv":
                        row.update(
                            Seed="11",
                            Trial=str(index),
                            SignalPresent="true",
                            CorrectDetection="true",
                            FalseAlarm="false",
                            MissedDetection="false",
                            MeasuredSINRdB="5.0",
                            RuntimeMs="1.2",
                            MemoryMB="4.0",
                        )
                    else:
                        row.update(
                            OperatingPointID=f"OP-{index:04d}",
                            Trials="1000",
                            CorrectDetections="990",
                            Misses="10",
                            FalseAlarms="0",
                            DetectionProbability="0.99",
                            DetectionCILower="0.98",
                            DetectionCIUpper="0.995",
                            FalseAlarmProbability="0.0",
                            FalseAlarmCIUpper="0.003",
                            MeanRuntimeMs="1.2",
                            MeanMemoryMB="4.0",
                            Incomplete="false",
                            StopReason="confidence_and_trials_met",
                        )
                    rows.append(row)
            elif name == "pdcch_impact_rule_evaluation.csv":
                for index, rule in enumerate(rules):
                    row = base_row(columns, index)
                    row.update(
                        RuleID=rule["RuleID"],
                        FamilyID=rule["FamilyID"],
                        ExperimentID=experiments[index % len(experiments)]["ExperimentID"],
                        PairID=experiments[index % len(experiments)]["PairID"],
                        Metric=rule["Metric"],
                        ObservedValue="0",
                        Threshold=rule["Threshold"],
                        Passed="true",
                        EvidenceCSV="pdcch_impact_operating_points.csv",
                    )
                    rows.append(row)
            elif name == "pdcch_impact_pairwise_effects.csv":
                count = max(int(contract["MinRows"]), len(families))
                for index in range(count):
                    row = base_row(columns, index)
                    row.update(
                        FamilyID=families[index % len(families)]["FamilyID"],
                        PairID=f"PAIR-{index:04d}",
                        OperatingPointKey=f"OPKEY-{index:04d}",
                        Metric="DetectionProbability",
                        BaselineValue="0.90",
                        TreatmentValue="0.92",
                        AbsoluteEffect="0.02",
                        RelativeEffect="0.0222222222222",
                        CILower="0.01",
                        CIUpper="0.03",
                        PValue="0.01",
                        AdjustedPValue="0.02",
                        EffectSize="0.2",
                        Conclusion="treatment_higher",
                    )
                    rows.append(row)
            elif name == "pdcch_impact_summary.csv":
                experiment_count_by_family: dict[str, int] = {}
                for experiment in experiments:
                    experiment_count_by_family[experiment["FamilyID"]] = experiment_count_by_family.get(experiment["FamilyID"], 0) + 1
                for index, family in enumerate(families):
                    count = experiment_count_by_family[family["FamilyID"]]
                    row = base_row(columns, index)
                    row.update(
                        FamilyID=family["FamilyID"],
                        ExperimentsRequired=str(count),
                        ExperimentsCompleted=str(count),
                        HardRulesPassed="1",
                        HardRulesFailed="0",
                        StatisticalConclusion="synthetic_pass",
                        LargestEffect="0.2",
                        ResidualDependency="none",
                    )
                    rows.append(row)
            else:
                count = max(int(contract["MinRows"]), 1)
                for index in range(count):
                    row = base_row(columns, index)
                    for key in [item for item in contract["PrimaryKey"].split("|") if item]:
                        if key == "RunID":
                            row[key] = "SYNTHETIC"
                        elif key == "FamilyID":
                            row[key] = families[index % len(families)]["FamilyID"]
                        elif key == "ExperimentID":
                            row[key] = experiments[index % len(experiments)]["ExperimentID"]
                        else:
                            row[key] = f"{key}-{index:04d}"
                    numeric_columns = {
                        "PayloadBits",
                        "FieldCount",
                        "CodeRate",
                        "PackRuntimeUs",
                        "CORESETDuration",
                        "CORESETRBs",
                        "REGBundleSize",
                        "InterleaverSize",
                        "CandidateCount",
                        "MonitoringLoad",
                        "DetectionProbability",
                        "SSBSCSkHz",
                        "PDCCHSCSkHz",
                        "ControlResourceSetZero",
                        "SearchSpaceZero",
                        "OffsetRB",
                        "MonitoringLatencySlots",
                        "Trials",
                        "FalseAlarms",
                        "FalseAlarmProbability",
                        "FalseAlarmCIUpper",
                        "SNRdB",
                        "DopplerHz",
                        "CFOHz",
                        "TimingOffsetSamples",
                        "PhaseNoiseLevel",
                        "CFOErrorHz",
                        "TimingErrorSamples",
                        "CandidatesTested",
                        "FormatsTested",
                        "RNTIsTested",
                        "AggregationLevelsTested",
                        "RuntimeMs",
                        "MemoryMB",
                        "CandidatesPerSecond",
                        "Coefficient",
                        "StdError",
                        "CILower",
                        "CIUpper",
                        "PValue",
                        "AdjustedPValue",
                        "UnexpectedGrantCount",
                    }
                    for column in numeric_columns.intersection(row):
                        row[column] = "1"
                    for column in ["CorrectApplication", "AssignmentDigestChanged", "WaveformDigestChanged"]:
                        if column in row:
                            row[column] = "true"
                    if "ConfiguredOracleChanged" in row:
                        row["ConfiguredOracleChanged"] = "false"
                    rows.append(row)

            write_csv(root / name, columns, rows)

        assert semantic_contract is not None
        semantic_columns = semantic_contract[1]
        semantic_rows: list[dict[str, object]] = []
        for index, contract in enumerate(image_contracts):
            width = max(1100, int(contract["MinWidth"]))
            height = max(700, int(contract["MinHeight"]))
            image = Image.new("RGB", (width, height), "white")
            draw = ImageDraw.Draw(image)
            draw.rectangle((40, 40, width - 40, height - 60), outline="black", width=3)
            for point in range(100):
                x = 60 + point * (width - 120) // 100
                y = 60 + ((point * 43 + index * 31) % (height - 160))
                draw.ellipse((x, y, x + 4, y + 4), fill="black")
            image_path = root / contract["ImageFile"]
            image.save(image_path)
            sources = [item for item in contract["SourceCSV"].split("|") if item]
            row = {column: "1" for column in semantic_columns}
            row.update(
                ImageFile=contract["ImageFile"],
                SourceCSV=contract["SourceCSV"],
                Width=str(width),
                Height=str(height),
                AxesCount=contract["MinAxesCount"],
                SeriesCount=contract["MinSeriesCount"],
                FinitePointCount=contract["MinFinitePointCount"],
                ExpectedTitleToken=contract["ExpectedTitleToken"],
                ActualTitle="Synthetic " + contract["ExpectedTitleToken"],
                ExpectedXLabel=contract["ExpectedXLabel"],
                ActualXLabel=contract["ExpectedXLabel"],
                ExpectedYLabel=contract["ExpectedYLabel"],
                ActualYLabel=contract["ExpectedYLabel"],
                SourceCSV_SHA256=source_hash(root, sources),
                PNG_SHA256=digest(image_path),
                Status="PASS",
            )
            semantic_rows.append(row)
        write_csv(root / "pdcch_impact_image_semantic_audit.csv", semantic_columns, semantic_rows)

        good_result = verify(root)
        semantic_rows[0]["PNG_SHA256"] = "0" * 64
        write_csv(root / "pdcch_impact_image_semantic_audit.csv", semantic_columns, semantic_rows)
        bad_result = verify(root)
        print(json.dumps({"self_test_valid_exit": good_result, "self_test_corrupt_exit": bad_result}, indent=2))
        return 0 if good_result == 0 and bad_result == 2 else 3


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        raise SystemExit(self_test())
    if arguments.output_dir is None:
        parser.error("output_dir is required unless --self-test is used")
    raise SystemExit(verify(arguments.output_dir))
