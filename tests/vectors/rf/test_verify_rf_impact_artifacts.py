"""Declared numeric/archive fixtures only: no RF/receiver/PHY execution.

Exercises the independent verifier's real entry point, original MAT operands,
exact source populations and plotted CSV axes. PNG is a declared test image,
not a simulator measurement or a rendering-performance qualification.
"""
import contextlib
import csv
import hashlib
import importlib.util
import io
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
import pytest
from scipy.io import savemat


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("rf_impact_verifier", HERE / "verify_rf_impact_artifacts.py")
VERIFIER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFIER)
SCOPE = "declared_numeric_verifier_fixture_not_RF_execution"
METRICS = ["WaveformRelativeRMSError_pct", "OutputPAPR_dB", "MeasuredBandPowerRatio_dB", "ClippingRatio",
           "AppliedPhaseRMS_rad", "ModeledNoiseFigure_dB", "AppliedPowerTarget_dBm", "BLER", "CFOError_Hz",
           "TimingError_samples", "FalseLock", "CPE", "ICI", "StandardACLR", "SEM", "MeasuredPower_dBm",
           "InteractionEffect", "ParallelExecution"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def token(value):
    def safe(v):
        if isinstance(v, dict):
            return {k: safe(x) for k, x in v.items()}
        if isinstance(v, float) and not math.isfinite(v):
            return None
        return v
    return json.dumps(safe(value), separators=(",", ":"), allow_nan=False)


def token_hash(value):
    return hashlib.sha256(value.encode()).hexdigest()


def array_hash(value):
    h = hashlib.sha256(b"runtime_array:double:")
    h.update(np.array(value.shape, dtype="<u8").tobytes())
    h.update(np.asarray(value.real, dtype="<f8").tobytes(order="F"))
    h.update(np.asarray(value.imag, dtype="<f8").tobytes(order="F"))
    return h.hexdigest()


def text(value):
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, float):
        return format(value, ".17g")
    return str(value)


def write_csv(path, rows, header=None):
    header = list(header or rows[0])
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=header)
        writer.writeheader()
        writer.writerows({k: text(row[k]) for k in header} for row in rows)


def read_csv(path):
    with path.open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream)
        return reader.fieldnames, list(reader)


def change_row(path, key, value, index=0):
    header, rows = read_csv(path)
    rows[index][key] = value
    write_csv(path, rows, header)


@pytest.fixture
def publication(tmp_path):
    root, pack = tmp_path / "publication", tmp_path / "declared_contract"
    root.mkdir(); pack.mkdir()
    _, contracts = read_csv(HERE / "desired_rf_impact_csv_contract.csv")
    _, images = read_csv(HERE / "desired_rf_impact_image_contract.csv")
    images = [r for r in images if r["ImageFile"] in {"rf_impact_converter_bits_error.png", "rf_impact_adc_bits.png"}]
    write_csv(pack / "desired_rf_impact_csv_contract.csv", contracts)
    write_csv(pack / "desired_rf_impact_image_contract.csv", images)
    # A declared numeric transform (not claimed to execute ADCModel).
    x = np.array([.1+.2j, .3-.4j, -.2+.5j, .7-.1j], dtype=np.complex128).reshape(-1, 1)
    raw, originals = [], []
    category_fields = set().union(*(set(c["RequiredColumns"].split(";")) for c in contracts if c["CountPolicy"] == "category"))
    for ordinal, factor in enumerate((.5, .4)):
        y = x * factor
        ref, err = float(np.sum(abs(x)**2)), float(np.sum(abs(y-x)**2))
        value = 100 * math.sqrt(err / ref)
        cfg = {"DeclaredScale": factor, "Bits": 4-ordinal, "FullScale": 1.0, "Scope": SCOPE}
        receipt = {k: math.nan for k in category_fields - {"ExperimentID", "MeasurementReceiptSHA256"}}
        receipt.update(Kernel="declared_numeric_transform_not_RF_kernel", KernelConfigJSON=token(cfg),
                       ReferencePlane=SCOPE, ObservationMode="declared_numeric_test_fixture",
                       ReceiverExecuted=False, TransportBlockDecoderExecuted=False,
                       InputSHA256=array_hash(x), OutputSHA256=array_hash(y), SampleCount=x.size,
                       SampleRate_Hz=1000.0, ReferenceEnergy=ref, ErrorEnergy=err,
                       WaveformRelativeRMSError_pct=value, InputMeanPower=ref/x.size,
                       OutputMeanPower=float(np.mean(abs(y)**2)), OutputPAPR_dB=float(10*np.log10(np.max(abs(y)**2)/np.mean(abs(y)**2))),
                       ADCResultAvailable=True, Bits=4-ordinal, FullScale=1.0, ClippingRatio=0.0,
                       ADCErrorVariance=float(np.mean(abs(y-x)**2)),
                       WaveformSignalToErrorRatio_dB=float(10*np.log10(ref/err)),
                       BLER=math.nan, BLERAvailable=False, BLERStatus="unavailable_no_transport_block_decoder",
                       SpectrumAvailable=False, SpectrumWindow="", SpectrumNFFT=math.nan)
        receipt["KernelConfigSHA256"] = token_hash(receipt["KernelConfigJSON"])
        row = dict(ExperimentID=f"declared-{ordinal}", CaseID="declared", FamilyID="F34", PairID="declared-pair",
                   Role=("baseline", "treatment")[ordinal], Seed=11, TrialID=1,
                   Metric="WaveformRelativeRMSError_pct", Value=value, MetricAvailable=True, Status="declared_fixture", **receipt)
        row["MeasurementReceiptJSON"] = token(row)
        row["MeasurementReceiptSHA256"] = token_hash(row["MeasurementReceiptJSON"])
        originals.append(dict(ExperimentID=row["ExperimentID"], Receipt=receipt, Input=x, Output=y,
                              Configuration=cfg, ReturnedEvidence=dict(Output=y, Bits=4-ordinal, FullScale=1.0,
                              ClippingRatio=0.0, ErrorVariance=receipt["ADCErrorVariance"]),
                              MeasurementReceiptJSON=row["MeasurementReceiptJSON"], MeasurementReceiptSHA256=row["MeasurementReceiptSHA256"]))
        raw.append(row)
    cells = np.empty((2, 1), dtype=object)
    cells[:, 0] = originals
    write_csv(pack / "rf_impact_experiment_matrix.csv", [{k: r[k] for k in ("ExperimentID", "FamilyID", "PairID", "Role", "Seed", "TrialID")} for r in raw])
    archive = root / "rf_impact_observation_operands.mat"
    savemat(archive, {"Observations": cells, "Metadata": dict(RequestedExecutionCount=2, ExecutedCount=2, Scope=SCOPE,
            ExperimentMatrixSHA256=digest(pack / "rf_impact_experiment_matrix.csv"))}, long_field_names=True)
    for row in raw:
        row.update(SourceOperandsMAT=archive.name, SourceOperandsMATSHA256=digest(archive))
    pair_context = token(dict(FamilyID="F34", Seed=11, TrialID=1, Scope=SCOPE))
    effect = raw[1]["Value"] - raw[0]["Value"]
    tables = {
        "rf_impact_raw_trials.csv": raw,
        "rf_impact_operating_points.csv": [dict(PairID="declared-pair", FamilyID="F34", BaselineExperimentID="declared-0",
            TreatmentExperimentID="declared-1", DeclaredPairContextJSON=pair_context, DeclaredPairContextSHA256=token_hash(pair_context),
            InputSHA256=raw[0]["InputSHA256"], Complete=True, Status=SCOPE)],
        "rf_impact_pairwise_effects.csv": [dict(FamilyID="F34", Metric=raw[0]["Metric"], PairCount=1,
            BaselineMean=raw[0]["Value"], TreatmentMean=raw[1]["Value"], Effect=effect, PairedDifferenceSD=0.0,
            CILower=math.nan, CIUpper=math.nan, PValue=math.nan, AdjustedPValue=math.nan, StatisticallyQualified=False, Status=SCOPE)],
        "rf_impact_run_manifest.csv": [dict(FamilyID="F34", PlannedPairs=1, CompletedPairs=1,
            Status="executed_component_pairs_not_feature_qualification")],
        "rf_impact_summary.csv": [dict(FamilyID="F34", Experiments=2, Completed=2, Failed=0, Incomplete=0,
            PrimaryEffect=effect, FeatureQualified=False, Conclusion=SCOPE, Status="not_feature_qualified")],
        "rf_impact_runtime.csv": [dict(FamilyID="F34", Runtime_s=0.1, RuntimeAvailable=True, ExecutedObservationCount=2,
            WholeRawTableStorageBytes=1000, PeakMemory_MB=math.nan, ParallelDigest="", ParallelExecutionPerformed=False, Status=SCOPE)],
        "rf_impact_interactions.csv": [],
        "rf_impact_metric_availability.csv": [dict(ExperimentID=r["ExperimentID"], FamilyID="F34", Metric=m,
            Available=m in r and not math.isnan(r[m]), Status=SCOPE) for r in raw for m in METRICS],
    }
    original_rules = [dict(RuleID="declared-profile", FamilyID="F34", Metric="PrimaryMetric", Operator="PROFILE_SPECIFIC",
                          Threshold="FROM_PROFILE", Mandatory=True),
                      dict(RuleID="finite", FamilyID="ALL", Metric="NonFiniteSamples", Operator="==", Threshold="0", Mandatory=True)]
    tables["rf_impact_rule_evaluation.csv"] = [dict(original_rules[0], Observed=math.nan, Evaluated=False, Passed=math.nan,
        Evidence="unavailable", Status="not_evaluated"), dict(original_rules[1], Observed=0, Evaluated=True, Passed=1, Evidence=SCOPE, Status="PASS")]
    write_csv(pack / "rf_impact_acceptance_rules.csv", original_rules)
    for c in contracts:
        name = c["FileName"]
        if c["CountPolicy"] == "category":
            tables[name] = raw if "F34" in c["SourceFamilies"].split(";") else []
        if name == "rf_impact_image_semantic_audit.csv":
            continue
        rows = tables[name]
        header = list(raw[0]) if c["CountPolicy"] == "category" else (list(rows[0]) if rows else c["RequiredColumns"].split(";"))
        write_csv(root / name, rows, header)
    audits = []
    for image in images:
        available = image["AvailabilityColumn"] == "ADCResultAvailable"
        a = dict(ImageFile=image["ImageFile"], SourceCSV=image["SourceCSV"], SourceCSVSHA256=digest(root / image["SourceCSV"]),
                 PNGSHA256="", XColumn=image["XColumn"], YColumn=image["YColumn"], SeriesColumns=image["SeriesColumns"],
                 SourceRowCount=2, AvailableRowCount=2 if available else 0, PlottedRowCount=2 if available else 0,
                 UndefinedOrInfiniteRowCount=0, PointsCSV="", PointsCSVSHA256="", SeriesCount=2 if available else 0,
                 Title=image["ExpectedTitle"], XLabel=image["ExpectedXLabel"], YLabel=image["ExpectedYLabel"],
                 Width=32 if available else math.nan, Height=24 if available else math.nan,
                 Status="rendered_exact_original_finite_points" if available else "unavailable_no_defined_population")
        if available:
            img = Image.new("RGB", (32, 24), "white")
            ImageDraw.Draw(img).line([(1, 20), (30, 1)], fill="black", width=2)
            img.save(root / a["ImageFile"])
            a["PNGSHA256"] = digest(root / a["ImageFile"])
            a["PointsCSV"] = "declared_points.csv"
            points = []
            for r in raw:
                p = dict(r, PlotX=r[a["XColumn"]], PlotY=r[a["YColumn"]],
                         PlotSeriesIdentityJSON=token({k: r[k] for k in a["SeriesColumns"].split(";")}))
                points.append(p)
            write_csv(root / a["PointsCSV"], points)
            a["PointsCSVSHA256"] = digest(root / a["PointsCSV"])
        audits.append(a)
    write_csv(root / "rf_impact_image_semantic_audit.csv", audits)
    return root, pack


def assert_invalid(publication, expected):
    result = VERIFIER.verify(*publication)
    assert not result["PublicationValid"] and not result["AcceptanceQualified"]
    assert expected in " ".join(result["Failures"]), result


def test_valid_unqualified_publication_and_original_operand_counts(publication):
    result = VERIFIER.verify(*publication)
    assert result["PublicationValid"], result
    assert not result["AcceptanceQualified"]
    assert result["OriginalExecutionCount"] == 2 and result["OriginalPairCount"] == 1
    assert result["OriginalOperandsValidated"] and result["MATLABTypedTextRevalidated"]
    assert result["OriginalExperimentMatrixHashValidation"] == "verified_exact_original_bytes"


def test_cli_default_requires_acceptance_and_explicit_publication_only(publication):
    root, pack = publication
    args = [str(root), "--contract-root", str(pack)]
    with contextlib.redirect_stdout(io.StringIO()) as out:
        assert VERIFIER.main(args) == 2
    assert not json.loads(out.getvalue())["AcceptanceQualified"]
    with contextlib.redirect_stdout(io.StringIO()) as out:
        assert VERIFIER.main(args + ["--publication-only"]) == 0
    assert json.loads(out.getvalue())["PublicationOnlyRequested"]


def test_original_archive_hash_corruption(publication):
    root, _ = publication
    path = root / "rf_impact_observation_operands.mat"
    path.write_bytes(path.read_bytes() + b"tampered")
    assert_invalid(publication, "original MAT hash mismatch")


def test_original_matrix_exact_bytes_not_just_equivalent_rows(publication):
    _, pack = publication
    path = pack / "rf_impact_experiment_matrix.csv"
    # Same CSV rows, distinct original bytes: cannot silently claim hash match.
    path.write_bytes(path.read_bytes() + b"\r\n")
    assert_invalid(publication, "original experiment matrix byte hash mismatch")


def test_resealed_primary_value_cannot_replace_original_arithmetic(publication):
    root, _ = publication
    path = root / "rf_impact_raw_trials.csv"
    header, rows = read_csv(path)
    rows[0]["Value"] = "0.01"
    obj = json.loads(rows[0]["MeasurementReceiptJSON"]); obj["Value"] = .01
    rows[0]["MeasurementReceiptJSON"] = token(obj)
    rows[0]["MeasurementReceiptSHA256"] = token_hash(rows[0]["MeasurementReceiptJSON"])
    write_csv(path, rows, header)
    assert_invalid(publication, "primary metric used by pair reductions")


def test_resealed_plot_coordinate_cannot_replace_source(publication):
    root, _ = publication
    change_row(root / "declared_points.csv", "PlotX", "999")
    change_row(root / "rf_impact_image_semantic_audit.csv", "PointsCSVSHA256", digest(root / "declared_points.csv"))
    assert_invalid(publication, "plotted coordinate substitution")


@pytest.mark.parametrize("operation", ["duplicate", "drop"])
def test_category_cannot_pad_or_drop_original_observation(publication, operation):
    root, _ = publication
    path = root / "rf_impact_data_converters.csv"
    header, rows = read_csv(path)
    rows = rows + [rows[0]] if operation == "duplicate" else rows[:1]
    write_csv(path, rows, header)
    assert_invalid(publication, "category must preserve every exact original row")


def test_fabricated_bler_is_rejected(publication):
    root, _ = publication
    change_row(root / "rf_impact_raw_trials.csv", "BLER", "0")
    assert_invalid(publication, "missing/nonfinite receipt changed: BLER")


def test_unevaluated_rule_cannot_be_reported_pass(publication):
    root, _ = publication
    change_row(root / "rf_impact_rule_evaluation.csv", "Passed", "1")
    assert_invalid(publication, "false acceptance result")


def test_bare_absolute_metric_cannot_be_paired_difference(publication):
    root, pack = publication
    for path in (pack / "rf_impact_acceptance_rules.csv", root / "rf_impact_rule_evaluation.csv"):
        header, rows = read_csv(path)
        rows[0].update(Metric="WaveformRelativeRMSError_pct", Operator="<=", Threshold="40")
        write_csv(path, rows, header)
    assert VERIFIER.verify(root, pack)["PublicationValid"]
    change_row(root / "rf_impact_rule_evaluation.csv", "Observed", "10")
    assert_invalid(publication, "rule observed value lacks its named source")


def test_explicit_paired_effect_can_evaluate_declared_threshold(publication):
    root, pack = publication
    for path in (pack / "rf_impact_acceptance_rules.csv", root / "rf_impact_rule_evaluation.csv"):
        header, rows = read_csv(path)
        rows[0].update(Metric="PairedEffect:WaveformRelativeRMSError_pct", Operator="<=", Threshold="40")
        if "Observed" in rows[0]:
            _, effects = read_csv(root / "rf_impact_pairwise_effects.csv")
            rows[0].update(Observed=effects[0]["Effect"], Evaluated="true", Passed="1", Status="PASS")
        write_csv(path, rows, header)
    result = VERIFIER.verify(root, pack)
    assert result["PublicationValid"] and result["AcceptanceQualified"], result
    with contextlib.redirect_stdout(io.StringIO()):
        assert VERIFIER.main([str(root), "--contract-root", str(pack)]) == 0


def test_unavailable_plot_must_remain_absent(publication):
    root, _ = publication
    (root / "rf_impact_adc_bits.png").write_bytes((root / "rf_impact_converter_bits_error.png").read_bytes())
    assert_invalid(publication, "unavailable plot masquerades as measured")


def test_cross_population_pair_is_rejected(publication):
    root, _ = publication
    path = root / "rf_impact_raw_trials.csv"
    header, rows = read_csv(path)
    rows[1]["Seed"] = "23"
    obj = json.loads(rows[1]["MeasurementReceiptJSON"]); obj["Seed"] = 23
    rows[1]["MeasurementReceiptJSON"] = token(obj)
    rows[1]["MeasurementReceiptSHA256"] = token_hash(rows[1]["MeasurementReceiptJSON"])
    write_csv(path, rows, header)
    assert_invalid(publication, "cross-population pair")


def test_parallel_or_peak_memory_claim_is_rejected(publication):
    root, _ = publication
    change_row(root / "rf_impact_runtime.csv", "ParallelExecutionPerformed", "true")
    assert_invalid(publication, "unmeasured parallel execution/peak memory")


def test_unexecuted_metric_availability_is_rejected(publication):
    root, _ = publication
    path = root / "rf_impact_metric_availability.csv"
    header, rows = read_csv(path)
    next(r for r in rows if r["Metric"] == "BLER")["Available"] = "true"
    write_csv(path, rows, header)
    assert_invalid(publication, "availability substituted source/value")


def test_plot_source_identity_is_preserved(publication):
    root, _ = publication
    change_row(root / "declared_points.csv", "ExperimentID", "other-execution")
    change_row(root / "rf_impact_image_semantic_audit.csv", "PointsCSVSHA256", digest(root / "declared_points.csv"))
    assert_invalid(publication, "plot source value/identity changed: ExperimentID")
