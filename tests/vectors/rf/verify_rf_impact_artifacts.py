#!/usr/bin/env python3
"""Verify bounded RF-impact publication independently; never infer link BLER.

Default exit zero still requires all declared mandatory acceptance criteria.
--publication-only permits a valid, explicitly unqualified publication.
Original MAT operands are read, not re-executed. MATLAB typed-string closure
remains the native producer's responsibility when scipy exposes MCOS objects.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageStat
from scipy.io import loadmat
from scipy.io.matlab import MatlabOpaque


class IntegrityError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise IntegrityError(message)


def read_csv(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        header = reader.fieldnames
        require(header and all(header) and len(set(header)) == len(header), f"invalid CSV header: {path.name}")
        data = list(reader)
        require(all(None not in r and all(v is not None for v in r.values()) for r in data), f"ragged CSV: {path.name}")
        return header, data


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_path(root, value):
    path = Path(value)
    require(value and not path.is_absolute() and ":" not in value and ".." not in path.parts, "unsafe artifact path")
    resolved = (root / path).resolve()
    require(resolved.is_relative_to(root.resolve()), "artifact escapes declared root")
    return resolved


def number(value):
    return float(value) if str(value).strip() else math.nan


def boolean(value):
    token = str(value).strip().lower()
    require(token in {"0", "1", "false", "true"}, f"unknown boolean {value!r}")
    return token in {"1", "true"}


def same_number(a, b):
    a, b = float(a), float(b)
    return a == b or math.isnan(a) and math.isnan(b)


def near(a, b, label):
    require(np.allclose(a, b, rtol=2e-12, atol=1e-25, equal_nan=True), f"operand arithmetic mismatch: {label}")


def unwrap(value):
    while isinstance(value, np.ndarray) and value.dtype == object and value.size == 1:
        value = value.flat[0]
    return value


def field(value, key):
    value = unwrap(value)
    return value[key] if isinstance(value, dict) else getattr(value, key)


def scalar(value):
    arr = np.asarray(value)
    require(arr.size == 1 and arr.dtype.kind in "biuf", "expected original scalar numerical operand")
    return arr.reshape(-1)[0].item()


def mat_text(value):
    arr = np.asarray(value)
    if arr.dtype.kind in "US":
        return "".join(arr.reshape(-1).tolist())
    return None  # MATLAB MCOS/string is not decoded or fabricated here.


def runtime_hash(value):
    value = np.asarray(value)
    classes = {"f": "single" if value.dtype.itemsize == 4 else "double", "c": "single" if value.dtype.itemsize == 8 else "double"}
    require(value.dtype.kind in classes, "unsupported waveform class")
    shape = value.shape if value.ndim >= 2 else (value.size, 1)
    digest = hashlib.sha256(("runtime_array:" + classes[value.dtype.kind] + ":").encode())
    digest.update(np.asarray(shape, dtype="<u8").tobytes())
    digest.update(np.asarray(value.real, dtype="<f8").tobytes(order="F"))
    digest.update(np.asarray(value.imag, dtype="<f8").tobytes(order="F"))
    return digest.hexdigest()


def check_json_row(row):
    token = row["MeasurementReceiptJSON"]
    require(hashlib.sha256(token.encode()).hexdigest() == row["MeasurementReceiptSHA256"], "receipt token hash")
    obj = json.loads(token)
    require(isinstance(obj, dict), "receipt must be a scalar object")
    for key, value in obj.items():
        require(key in row, f"receipt field missing: {key}")
        if value is None:
            require(not math.isfinite(number(row[key])), f"missing/nonfinite receipt changed: {key}")
        elif isinstance(value, bool):
            require(boolean(row[key]) == value, f"receipt boolean changed: {key}")
        elif isinstance(value, (int, float)):
            require(same_number(row[key], value), f"receipt numeric changed: {key}")
        else:
            require(isinstance(value, str) and row[key] == value, f"receipt text changed: {key}")
    require(hashlib.sha256(row["KernelConfigJSON"].encode()).hexdigest() == row["KernelConfigSHA256"], "kernel config hash")


def check_operands(root, raw, pack):
    require(raw, "no actual requested observations")
    archive_paths = {r["SourceOperandsMAT"] for r in raw}
    require(len(archive_paths) == 1, "one original operand archive required")
    path = safe_path(root, next(iter(archive_paths)))
    digest = sha(path)
    require(all(r["SourceOperandsMATSHA256"] == digest for r in raw), "original MAT hash mismatch")
    mat = loadmat(path, struct_as_record=False, squeeze_me=False)
    observations = np.asarray(mat["Observations"], dtype=object).reshape(-1, order="F")
    require(len(observations) == len(raw), "original operand count mismatch")
    metadata = mat["Metadata"]
    require(scalar(field(metadata, "RequestedExecutionCount")) == len(raw) and
            scalar(field(metadata, "ExecutedCount")) == len(raw), "original requested/executed count mismatch")
    original_matrix_hash = field(metadata, "ExperimentMatrixSHA256")
    matrix_hash = mat_text(original_matrix_hash)
    if matrix_hash is None:
        require(isinstance(unwrap(original_matrix_hash), MatlabOpaque), "invalid original experiment matrix hash type")
        matrix_status = "unavailable_MATLAB_opaque_text_native_snapshot_hash_assertion_required"
    else:
        require(re.fullmatch(r"[0-9a-f]{64}", matrix_hash) is not None and
                matrix_hash == sha(pack / "rf_impact_experiment_matrix.csv"), "original experiment matrix byte hash mismatch")
        matrix_status = "verified_exact_original_bytes"
    typed_text = True
    for row, obj in zip(raw, observations):
        check_json_row(row)
        original_id = mat_text(field(obj, "ExperimentID"))
        typed_text &= original_id is not None
        if original_id is not None:
            require(original_id == row["ExperimentID"], "original MAT experiment identity mismatch")
        require(not boolean(row["BLERAvailable"]) and math.isnan(number(row["BLER"])), "unexecuted BLER cannot be published")
        if "ReceiverExecuted" in row:
            require(not boolean(row["ReceiverExecuted"]) and not boolean(row["TransportBlockDecoderExecuted"]), "component is not a receiver")
        receipt = unwrap(field(obj, "Receipt"))
        names = receipt.keys() if isinstance(receipt, dict) else receipt._fieldnames
        for name in names:
            value = np.asarray(field(receipt, name))
            if value.size == 1 and value.dtype.kind in "biuf":
                supplied = boolean(row[name]) if row.get(name, "").lower() in {"true", "false"} else number(row.get(name, ""))
                require(name in row and same_number(supplied, scalar(value)), f"original scalar receipt mismatch: {name}")
        x, y = np.asarray(field(obj, "Input")), np.asarray(field(obj, "Output"))
        require(np.isfinite(x).all() and np.isfinite(y).all(), "nonfinite original waveform")
        returned = field(obj, "ReturnedEvidence")
        if y.size:
            require(x.shape == y.shape and x.size == number(row["SampleCount"]), "original waveform shape/count mismatch")
            require(runtime_hash(x) == row["InputSHA256"] and runtime_hash(y) == row["OutputSHA256"], "original waveform bytes mismatch")
            ref, err = np.sum(np.abs(x) ** 2), np.sum(np.abs(y - x) ** 2)
            near(ref, number(row["ReferenceEnergy"]), "reference energy")
            near(err, number(row["ErrorEnergy"]), "error energy")
            expected = 100 * math.sqrt(err / ref)
            near(expected, number(row["WaveformRelativeRMSError_pct"]), "time-waveform relative RMS error")
            near(np.mean(np.abs(y) ** 2), number(row["OutputMeanPower"]), "output sample power")
            metric = "WaveformRelativeRMSError_pct"
            if row["Metric"] == "MeasuredBandPowerRatio_dB":
                n = y.size
                require(number(row["SpectrumNFFT"]) == n and row["SpectrumWindow"] == "rectangular_all_original_samples", "spectral support/window")
                fs = number(row["SampleRate_Hz"])
                require(math.isfinite(fs) and fs > 0, "spectral Fs")
                f = np.arange(-n // 2, n // 2) * fs / n
                spectrum = np.abs(np.fft.fftshift(np.fft.fft(y.reshape(-1, order="F")))) ** 2 / n ** 2
                a = spectrum[(f >= number(row["AssignedBandLow_Hz"])) & (f <= number(row["AssignedBandHigh_Hz"]))].sum()
                b = spectrum[(abs(f) >= number(row["AdjacentAbsBandLow_Hz"])) & (abs(f) <= number(row["AdjacentAbsBandHigh_Hz"]))].sum()
                near(a, number(row["AssignedBandPower"]), "assigned-band power")
                near(b, number(row["AdjacentBandPower"]), "adjacent-band power")
                expected = float(10 * np.log10(a / b))
                metric = "MeasuredBandPowerRatio_dB"
            if boolean(row.get("ADCResultAvailable", "false")):
                require(np.array_equal(field(returned, "Output"), y), "ADC returned output")
                for key in ("Bits", "FullScale", "ClippingRatio"):
                    require(same_number(scalar(field(returned, key)), number(row[key])), f"ADC returned {key}")
                near(scalar(field(returned, "ErrorVariance")), number(row["ADCErrorVariance"]), "ADC error variance")
        elif row["Metric"] == "ModeledNoiseFigure_dB":
            metric, expected = "ModeledNoiseFigure_dB", scalar(field(returned, "CascadeNF_dB"))
        else:
            require(row["Kernel"] == "DeclaredAdditivePowerBudgetEquation", "unknown analytical owner")
            cfg = field(obj, "Configuration")
            get = lambda k: scalar(field(cfg, k))
            requested = get("P0_dBm") + 10 * math.log10(2 ** get("Mu") * get("MRB")) + get("Alpha") * get("AssumedPathloss_dB") + get("DeltaTF_dB") + get("AssumedTPCOffset_dB")
            near(requested, number(row["RequestedPower_dBm"]), "assumed-input budget")
            expected, metric = min(get("PCMAX_dBm"), requested), "AppliedPowerTarget_dBm"
            require(all(not scalar(field(returned, k)) for k in ("ReceiverMeasurementUsed", "DecodedControlUsed", "WaveformPowerApplied")), "analytical source misrepresented")
        require(row["Metric"] == metric, "unrelated metric substituted")
        near(expected, number(row["Value"]), "primary metric used by pair reductions")
        near(expected, number(row[metric]), "named primary metric")
        require(boolean(row["MetricAvailable"]) == (not math.isnan(expected)), "primary metric availability")
    return typed_text, matrix_status


def check_pairs(tables):
    raw = tables["rf_impact_raw_trials.csv"]
    ids = {r["ExperimentID"]: r for r in raw}
    require(len(ids) == len(raw), "duplicate original execution")
    groups = {}
    for row in raw:
        groups.setdefault(row["PairID"], []).append(row)
    pairs = tables["rf_impact_operating_points.csv"]
    require({r["PairID"] for r in pairs} == set(groups) and len(pairs) == len(groups), "pair population mismatch")
    for pair in pairs:
        entries = groups[pair["PairID"]]
        require(len(entries) == 2 and {r["Role"] for r in entries} == {"baseline", "treatment"}, "incomplete/duplicate pair")
        b = next(r for r in entries if r["Role"] == "baseline")
        t = next(r for r in entries if r["Role"] == "treatment")
        require(pair["BaselineExperimentID"] == b["ExperimentID"] and pair["TreatmentExperimentID"] == t["ExperimentID"], "pair source join")
        require(all(b[k] == t[k] for k in ("FamilyID", "Seed", "TrialID", "Kernel", "Metric", "ReferencePlane", "InputSHA256")), "cross-population pair")
        require(boolean(pair["Complete"]), "incomplete original pair")
        token = pair["DeclaredPairContextJSON"]
        require(hashlib.sha256(token.encode()).hexdigest() == pair["DeclaredPairContextSHA256"], "pair-context hash")
        declared = json.loads(token)
        require(declared["FamilyID"] == b["FamilyID"] and same_number(declared["Seed"], b["Seed"]) and same_number(declared["TrialID"], b["TrialID"]), "declared pair context")
    effects = tables["rf_impact_pairwise_effects.csv"]
    families = {r["FamilyID"] for r in raw}
    require(len(effects) == len(families) and {r["FamilyID"] for r in effects} == families, "effect population mismatch")
    for effect in effects:
        selected = sorted((p for p in pairs if p["FamilyID"] == effect["FamilyID"]), key=lambda p: p["PairID"])
        b = np.array([number(ids[p["BaselineExperimentID"]]["Value"]) for p in selected])
        t = np.array([number(ids[p["TreatmentExperimentID"]]["Value"]) for p in selected])
        require(number(effect["PairCount"]) == len(selected), "effect pair count")
        require(all(ids[p["BaselineExperimentID"]]["Metric"] == effect["Metric"] for p in selected), "effect metric domain")
        expected = (np.mean(b), np.mean(t), np.mean(t - b)) if np.isfinite(np.r_[b, t]).all() else (math.nan,) * 3
        for key, value in zip(("BaselineMean", "TreatmentMean", "Effect"), expected):
            near(value, number(effect[key]), f"paired {key}")
        require(not boolean(effect["StatisticallyQualified"]), "no inferential population qualification")
        require(all(math.isnan(number(effect[k])) for k in ("CILower", "CIUpper", "PValue", "AdjustedPValue")), "unsupported statistical inference")
    return families


def check_rules(tables, pack, families):
    rules = tables["rf_impact_rule_evaluation.csv"]
    _, original = read_csv(pack / "rf_impact_acceptance_rules.csv")
    original = [r for r in original if r["FamilyID"] in families or r["FamilyID"] == "ALL"]
    expected = {r["RuleID"]: r for r in original}
    require(len(rules) == len(expected) and {r["RuleID"] for r in rules} == set(expected), "requested rule population mismatch")
    effects = {r["FamilyID"]: r for r in tables["rf_impact_pairwise_effects.csv"]}
    raw = tables["rf_impact_raw_trials.csv"]
    operations = {"==": lambda a, b: a == b, "<=": lambda a, b: a <= b, ">=": lambda a, b: a >= b, "<": lambda a, b: a < b, ">": lambda a, b: a > b}
    mandatory = []
    for row in rules:
        source = expected[row["RuleID"]]
        require(all(row[k] == source[k] for k in ("FamilyID", "Metric", "Operator", "Threshold")) and boolean(row["Mandatory"]) == boolean(source["Mandatory"]), "changed acceptance rule")
        observed = math.nan
        if row["FamilyID"] == "ALL" and row["Metric"] == "IncompletePoints":
            observed = sum(not boolean(r["MetricAvailable"]) for r in raw)
        elif row["FamilyID"] == "ALL" and row["Metric"] == "NonFiniteSamples" and any(number(r["SampleCount"]) > 0 for r in raw):
            observed = 0
        elif row["FamilyID"] in effects and row["Metric"] == "PairedEffect:" + effects[row["FamilyID"]]["Metric"]:
            observed = number(effects[row["FamilyID"]]["Effect"])
        require(same_number(observed, number(row["Observed"])), "rule observed value lacks its named source")
        try:
            threshold = number(row["Threshold"])
        except ValueError:
            threshold = math.nan
        evaluated = math.isfinite(observed) and math.isfinite(threshold) and row["Operator"] in operations
        require(boolean(row["Evaluated"]) == evaluated, "rule evaluated without applicable source/threshold")
        passed = operations[row["Operator"]](observed, threshold) if evaluated else None
        require(same_number(number(row["Passed"]), float(passed) if evaluated else math.nan), "false acceptance result")
        require(row["Status"] == ("PASS" if passed else "FAIL") if evaluated else row["Status"] == "not_evaluated", "rule status")
        if boolean(row["Mandatory"]):
            mandatory.append(bool(evaluated and passed))
    return bool(mandatory) and all(mandatory)


def check_summaries(tables, families):
    raw = tables["rf_impact_raw_trials.csv"]
    pairs = tables["rf_impact_operating_points.csv"]
    effects = {r["FamilyID"]: r for r in tables["rf_impact_pairwise_effects.csv"]}
    for filename in ("rf_impact_summary.csv", "rf_impact_runtime.csv", "rf_impact_run_manifest.csv"):
        rows = tables[filename]
        require(len(rows) == len(families) and {r["FamilyID"] for r in rows} == families, "summary family population")
        for row in rows:
            selected = [r for r in raw if r["FamilyID"] == row["FamilyID"]]
            n = len(selected)
            if filename == "rf_impact_summary.csv":
                require(number(row["Experiments"]) == n and number(row["Completed"]) == n and number(row["Failed"]) == 0 and
                        number(row["Incomplete"]) == sum(not boolean(r["MetricAvailable"]) for r in selected), "summary execution counts")
                near(number(row["PrimaryEffect"]), number(effects[row["FamilyID"]]["Effect"]), "summary paired effect")
                require(not boolean(row["FeatureQualified"]) and row["Status"] == "not_feature_qualified", "component family falsely qualified")
            elif filename == "rf_impact_runtime.csv":
                require(number(row["ExecutedObservationCount"]) == n and boolean(row["RuntimeAvailable"]) and
                        math.isfinite(number(row["Runtime_s"])) and number(row["Runtime_s"]) >= 0, "runtime original count/elapsed")
                require(not boolean(row["ParallelExecutionPerformed"]) and not row["ParallelDigest"] and
                        math.isnan(number(row["PeakMemory_MB"])), "unmeasured parallel execution/peak memory")
            else:
                count = sum(p["FamilyID"] == row["FamilyID"] for p in pairs)
                require(number(row["PlannedPairs"]) == count and number(row["CompletedPairs"]) == count and
                        row["Status"] == "executed_component_pairs_not_feature_qualification", "manifest population/qualification")
    metrics = {"WaveformRelativeRMSError_pct", "OutputPAPR_dB", "MeasuredBandPowerRatio_dB", "ClippingRatio",
               "AppliedPhaseRMS_rad", "ModeledNoiseFigure_dB", "AppliedPowerTarget_dBm", "BLER", "CFOError_Hz",
               "TimingError_samples", "FalseLock", "CPE", "ICI", "StandardACLR", "SEM", "MeasuredPower_dBm",
               "InteractionEffect", "ParallelExecution"}
    availability = tables["rf_impact_metric_availability.csv"]
    source = {r["ExperimentID"]: r for r in raw}
    expected = {(key, metric) for key in source for metric in metrics}
    require(len(availability) == len(expected) and {(r["ExperimentID"], r["Metric"]) for r in availability} == expected,
            "availability original execution/metric population")
    for row in availability:
        src = source[row["ExperimentID"]]
        available = row["Metric"] in src and not math.isnan(number(src[row["Metric"]]))
        require(row["FamilyID"] == src["FamilyID"] and boolean(row["Available"]) == available, "availability substituted source/value")


def check_images(root, pack, tables, headers):
    _, contract = read_csv(pack / "desired_rf_impact_image_contract.csv")
    audit_rows = tables["rf_impact_image_semantic_audit.csv"]
    audit = {r["ImageFile"]: r for r in audit_rows}
    require(len(audit_rows) == len(contract) and set(audit) == {r["ImageFile"] for r in contract}, "plot request/audit population mismatch")
    for c in contract:
        a = audit[c["ImageFile"]]
        source = tables[c["SourceCSV"]]
        require(a["SourceCSV"] == c["SourceCSV"] and a["SourceCSVSHA256"] == sha(root / c["SourceCSV"]), "plot source hash")
        require(all(a[k] == c[k] for k in ("XColumn", "YColumn", "SeriesColumns")), "plot axes/series contract changed")
        require(a["Title"] == c["ExpectedTitle"] and a["XLabel"] == c["ExpectedXLabel"] and a["YLabel"] == c["ExpectedYLabel"], "plot physical labels changed")
        require(number(a["SourceRowCount"]) == len(source), "plot source population count")
        names = headers[c["SourceCSV"]]
        applicable = all(k in names for k in (c["XColumn"], c["YColumn"], c["AvailabilityColumn"]))
        available = [r for r in source if applicable and boolean(r[c["AvailabilityColumn"]])]
        selected = [r for r in available if math.isfinite(number(r[c["XColumn"]])) and math.isfinite(number(r[c["YColumn"]]))]
        require(number(a["AvailableRowCount"]) == len(available) and number(a["PlottedRowCount"]) == len(selected) and number(a["UndefinedOrInfiniteRowCount"]) == len(available) - len(selected), "plot exact applicability/counts")
        image = safe_path(root, c["ImageFile"])
        if not selected:
            require(a["Status"].startswith("unavailable") and not image.exists() and not a["PNGSHA256"] and not a["PointsCSV"] and not a["PointsCSVSHA256"], "unavailable plot masquerades as measured")
            continue
        require(a["Status"] == "rendered_exact_original_finite_points" and sha(image) == a["PNGSHA256"], "rendered image hash/status")
        points_path = safe_path(root, a["PointsCSV"])
        require(sha(points_path) == a["PointsCSVSHA256"], "plotted-point hash")
        point_header, points = read_csv(points_path)
        require(len(points) == len(selected), "plotted points dropped/duplicated")
        keys = set()
        for src, point in zip(selected, points):
            for name in names:
                if name not in {"SourceOperandsMAT", "SourceOperandsMATSHA256"}:
                    require(name in point_header and src[name] == point[name], f"plot source value/identity changed: {name}")
            require(point["PlotX"] == src[c["XColumn"]] and point["PlotY"] == src[c["YColumn"]], "plotted coordinate substitution")
            token = point["PlotSeriesIdentityJSON"]
            group = json.loads(token)
            require(set(group) == set(c["SeriesColumns"].split(";")), "plot group identity fields")
            for key, value in group.items():
                require(same_number(src[key], value) if isinstance(value, (int, float)) else src[key] == value, "plot group value changed")
            keys.add(token)
        require(number(a["SeriesCount"]) == len(keys), "duplicate/arbitrary plot series")
        with Image.open(image) as img:
            require(img.size == (int(number(a["Width"])), int(number(a["Height"]))) and max(ImageStat.Stat(img.convert("RGB")).var) > 0.1, "image dimensions/nonblank content")


def verify(root, pack=None):
    root = Path(root)
    pack = Path(pack) if pack else Path(__file__).resolve().parent
    result = {"PublicationValid": False, "AcceptanceQualified": False, "Failures": [], "Scope": "component_archive_integrity_not_RF_link_device_or_statistical_qualification"}
    try:
        _, contract = read_csv(pack / "desired_rf_impact_csv_contract.csv")
        tables, headers = {}, {}
        for c in contract:
            headers[c["FileName"]], tables[c["FileName"]] = read_csv(safe_path(root, c["FileName"]))
            require(set(c["RequiredColumns"].split(";")) <= set(headers[c["FileName"]]), f"required schema: {c['FileName']}")
        raw = tables["rf_impact_raw_trials.csv"]
        result["MATLABTypedTextRevalidated"], result["OriginalExperimentMatrixHashValidation"] = check_operands(root, raw, pack)
        families = check_pairs(tables)
        _, matrix = read_csv(pack / "rf_impact_experiment_matrix.csv")
        matrix = [r for r in matrix if r["FamilyID"] in families]
        require({r["ExperimentID"] for r in matrix} == {r["ExperimentID"] for r in raw} and len(matrix) == len(raw), "original requested experiment population")
        original = {r["ExperimentID"]: r for r in matrix}
        for r in raw:
            require(all(r[k] == original[r["ExperimentID"]][k] for k in ("FamilyID", "PairID", "Role", "Seed", "TrialID")), "original experiment identity changed")
        for c in contract:
            value = tables[c["FileName"]]
            policy = c["CountPolicy"]
            if policy == "category":
                expected = [r for r in raw if r["FamilyID"] in c["SourceFamilies"].split(";")]
                require(value == expected, "category must preserve every exact original row without padding")
            elif policy == "empty_unexecuted":
                require(not value, "unexecuted interaction population")
            else:
                expected = {"executions": len(raw), "pairs": len({r["PairID"] for r in raw}), "families": len(families), "rules": len(tables["rf_impact_rule_evaluation.csv"]), "availability": len(tables["rf_impact_metric_availability.csv"]), "images": len(read_csv(pack / "desired_rf_impact_image_contract.csv")[1])}
                require(policy in expected and len(value) == expected[policy], f"exact original count: {c['FileName']}")
        result["AcceptanceQualified"] = check_rules(tables, pack, families)
        check_summaries(tables, families)
        check_images(root, pack, tables, headers)
        result.update(PublicationValid=True, OriginalExecutionCount=len(raw), OriginalPairCount=len(tables["rf_impact_operating_points.csv"]), OriginalOperandsValidated=True)
    except Exception as exc:
        result["Failures"].append(f"{type(exc).__name__}: {exc}")
        result["AcceptanceQualified"] = False
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--contract-root", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--publication-only", action="store_true", help="Check publication integrity without requiring unavailable scientific acceptance.")
    args = parser.parse_args(argv)
    result = verify(args.root, args.contract_root)
    result["PublicationOnlyRequested"] = args.publication_only
    print(json.dumps(result, indent=2))
    return 0 if result["PublicationValid"] and (args.publication_only or result["AcceptanceQualified"]) else 2


if __name__ == "__main__":
    raise SystemExit(main())
