from pathlib import Path
import csv
import sys
import hashlib
import math
import json
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
from audit_lls_measurement_catalog import audit_trial_values, audit_channel_resources, _io_path


def _pucch_timing_archive(tmp_path, mutation=None):
    evidence = dict(TimingOffsetSamples=16, AppliedTimingCorrectionSamples=16,
                    TimingSource="completed_same_slot_received_UL_pilot_alignment",
                    InputSampleCount=256, DemodulatedSampleCount=240,
                    OracleTimingUsed=False, ReceiverZeroPaddingUsed=False,
                    ReferenceAvailableAtSample=1256, ReferenceAgeSlots=0,
                    ReferenceSourceAbsoluteSlot0=44, TargetAbsoluteSlot0=44)
    row = dict(Slot=45, ObservationStartSample=1000, ObservationEndSampleExclusive=1256,
               EstimatedTimingOffsetSamples=16, AppliedTimingCorrectionSamples=16,
               ReceiverInputSampleCount=256, ReceiverDemodulatedSampleCount=240,
               TimingEstimateSource=evidence["TimingSource"], ReceiverTimingOracleUsed=0,
               ReceiverZeroPaddingUsed=0)
    if mutation:
        mutation(row, evidence)
    row["ReceiverTimingEvidenceJSON"] = json.dumps(evidence) if evidence is not None else ""
    path = tmp_path / "air_interface/csv/pucch_trials.csv"
    path.parent.mkdir(parents=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(row))
        writer.writeheader(); writer.writerow(row)
    return path


def test_pucch_timing_does_not_require_csi_cfo_contract(tmp_path):
    path = _pucch_timing_archive(tmp_path)
    original = path.read_bytes()
    rows = audit_trial_values(tmp_path, arithmetic=True)
    assert len(rows) == 1 and rows[0]["Metric"] == "PUCCHReceiverTimingEvidence"
    assert rows[0]["CheckStatus"] == "PASS_source_reconciliation_only"
    assert "not_CFO" in rows[0]["Scope"] and path.read_bytes() == original


def _prior_pucch_timing(row, evidence):
    evidence.update(TimingOffsetSamples=None,
                    TimingSource="prior_received_UL_pilot_constant_phase_prediction",
                    TimingValueRole="predicted_from_prior_measurement_not_current_timing_measurement",
                    ReferenceSource="SRS", ReferenceAvailableAtSample=900,
                    ReceiverTimingAvailableAtSample=900, ReferenceAvailableDuringBuffer=False,
                    ReferenceAgeSlots=4, ReferenceSourceAbsoluteSlot0=40, TargetAbsoluteSlot0=44)
    row.update(EstimatedTimingOffsetSamples="NaN", TimingEstimateUsed=0,
               TimingEstimateSource=evidence["TimingSource"])


def test_prior_pucch_clock_is_not_a_missing_fresh_estimate(tmp_path):
    path = _pucch_timing_archive(tmp_path, _prior_pucch_timing)
    original = path.read_bytes()
    result = audit_trial_values(tmp_path, arithmetic=True)[0]
    assert result["CheckStatus"] == "PASS_source_reconciliation_only"
    assert path.read_bytes() == original  # No retrospective measurement or relabeling.


def test_prior_pilot_completed_inside_buffer_is_causal(tmp_path):
    def mutate(row, evidence):
        _prior_pucch_timing(row, evidence)
        evidence.update(ReferenceAvailableAtSample=1100, ReceiverTimingAvailableAtSample=1100,
                        ReferenceAvailableDuringBuffer=True)
    _pucch_timing_archive(tmp_path, mutate)
    assert audit_trial_values(tmp_path, arithmetic=True)[0]["CheckStatus"] == "PASS_source_reconciliation_only"


@pytest.mark.parametrize("field,value", [
    ("ReferenceAvailableAtSample", 1257), ("ReceiverTimingAvailableAtSample", 901),
    ("ReferenceAgeSlots", 0), ("ReferenceAgeSlots", 3), ("ReferenceSourceAbsoluteSlot0", 45),
    ("TargetAbsoluteSlot0", 45), ("ReferenceAvailableDuringBuffer", True),
    ("TimingOffsetSamples", 16), ("TimingValueRole", "fresh_received_timing"),
    ("ReferenceSource", "injected_timing_truth")])
def test_prior_pucch_prediction_rejects_wrong_causality_or_measurement_claim(tmp_path, field, value):
    def mutate(row, evidence):
        _prior_pucch_timing(row, evidence)
        evidence[field] = value
    _pucch_timing_archive(tmp_path, mutate)
    assert audit_trial_values(tmp_path, arithmetic=True)[0]["CheckStatus"] == "FAIL_source_reconciliation"


@pytest.mark.parametrize("field,value", [
    ("TimingEstimateUsed", 1), ("EstimatedTimingOffsetSamples", 16)])
def test_prior_pucch_export_cannot_claim_fresh_measurement(tmp_path, field, value):
    def mutate(row, evidence):
        _prior_pucch_timing(row, evidence)
        row[field] = value
    _pucch_timing_archive(tmp_path, mutate)
    assert audit_trial_values(tmp_path, arithmetic=True)[0]["CheckStatus"] == "FAIL_source_reconciliation"


def test_prior_pucch_missing_source_remains_unverified(tmp_path):
    def mutate(row, evidence):
        _prior_pucch_timing(row, evidence)
        evidence.pop("ReferenceSource")
    _pucch_timing_archive(tmp_path, mutate)
    assert audit_trial_values(tmp_path, arithmetic=True)[0]["CheckStatus"] == "NOT_EVALUATED_missing_source_evidence"


@pytest.mark.parametrize("field,value", [
    ("AppliedTimingCorrectionSamples", 0), ("ReceiverDemodulatedSampleCount", 256),
    ("ReceiverInputSampleCount", 255), ("ReceiverTimingOracleUsed", 1),
    ("ReceiverZeroPaddingUsed", 1), ("TimingEstimateSource", "injected_offset"),
    ("ObservationEndSampleExclusive", 1200)])
def test_pucch_timing_mismatched_exports_are_not_accepted(tmp_path, field, value):
    _pucch_timing_archive(tmp_path, lambda row, _: row.update({field: value}))
    assert audit_trial_values(tmp_path, arithmetic=True)[0]["CheckStatus"] == "FAIL_source_reconciliation"


@pytest.mark.parametrize("field,value", [
    ("ReferenceAvailableAtSample", 1257), ("ReferenceSourceAbsoluteSlot0", 43),
    ("ReferenceAgeSlots", 1), ("OracleTimingUsed", True), ("ReceiverZeroPaddingUsed", True)])
def test_pucch_timing_bad_source_cannot_be_qualified_by_matching_labels(tmp_path, field, value):
    _pucch_timing_archive(tmp_path, lambda _, evidence: evidence.update({field: value}))
    assert audit_trial_values(tmp_path, arithmetic=True)[0]["CheckStatus"] == "FAIL_source_reconciliation"


def test_pucch_missing_timing_evidence_stays_missing(tmp_path):
    path = _pucch_timing_archive(tmp_path)
    with path.open(newline="") as stream:
        row = next(csv.DictReader(stream))
    row["ReceiverTimingEvidenceJSON"] = ""
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(row))
        writer.writeheader(); writer.writerow(row)
    assert audit_trial_values(tmp_path, arithmetic=True)[0]["CheckStatus"] == "NOT_EVALUATED_missing_source_evidence"


def _csi_sync_archive(tmp_path, mutation=None):
    row = dict(Slot=6, ObservationStartSample=1000, ObservationEndSampleExclusive=1256)
    for prefix, timing, cfo in (("Receiver", 16, 400), ("PhysicalMeasurement", 15, 3)):
        evidence = dict(Timing=dict(TimingOffsetSamples=timing,
                                    AppliedTimingCorrectionSamples=timing,
                                    DemodulatedSampleCount=256-timing,
                                    InputSampleCount=256,
                                    TimingSource="received_reference", OracleTimingUsed=False,
                                    ReceiverZeroPaddingUsed=False),
                        Frequency=dict(EstimatedCFO_Hz=cfo, CFOCorrectionApplied_Hz=cfo,
                                       CFOEstimateAvailable=True, CFOCorrectionApplied=True,
                                       Status="applied", Source="received_pilots"))
        row.update({prefix+"SynchronizationJSON": json.dumps(evidence),
                    prefix+"TimingOffset_samples": timing,
                    prefix+"TimingCorrection_samples": timing,
                    prefix+"DemodulatedSampleCount": 256-timing,
                    prefix+"TimingSource": "received_reference",
                    prefix+"EstimatedCFO_Hz": cfo, prefix+"AppliedCFO_Hz": cfo,
                    prefix+"CFOEstimateAvailable": 1, prefix+"CFOCorrectionApplied": 1,
                    prefix+"CFOStatus": "applied", prefix+"CFOSource": "received_pilots",
                    prefix+"SynchronizationSource": prefix+"_received_samples",
                    prefix+"SynchronizationSampleDomain": "relative_to_observation_capture_start_zero_based"})
    if mutation:
        mutation(row)
    path = tmp_path / "air_interface/csv/csi_rs_trials.csv"
    path.parent.mkdir(parents=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(row))
        writer.writeheader(); writer.writerow(row)
    return path


def test_csi_synchronization_audit_keeps_received_planes_separate(tmp_path):
    path = _csi_sync_archive(tmp_path)
    before = path.read_bytes()
    checks = audit_trial_values(tmp_path, arithmetic=True)
    assert [r["Metric"] for r in checks] == [
        "ReceiverSynchronizationEvidence", "PhysicalMeasurementSynchronizationEvidence"]
    assert all(r["CheckStatus"] == "PASS_source_reconciliation_only" for r in checks)
    assert path.read_bytes() == before


@pytest.mark.parametrize("field,value", [
    ("PhysicalMeasurementEstimatedCFO_Hz", 400),  # Post-RF value in pre-RF export.
    ("ReceiverTimingCorrection_samples", 0),
    ("ReceiverDemodulatedSampleCount", 256),
    ("ReceiverCFOEstimateAvailable", 0),
    ("ReceiverCFOSource", "different_source"),
    ("PhysicalMeasurementSynchronizationSampleDomain", "absolute_slot"),
    ("ReceiverSynchronizationJSON", "{broken"),
    ("ReceiverSynchronizationJSON", "[]"),
    ("ObservationEndSampleExclusive", 1200),
])
def test_csi_synchronization_audit_detects_inconsistent_exports(tmp_path, field, value):
    path = _csi_sync_archive(tmp_path, lambda row: row.update({field: value}))
    before = path.read_bytes()
    checks = audit_trial_values(tmp_path, arithmetic=True)
    assert any(r["CheckStatus"] == "FAIL_source_reconciliation" for r in checks)
    assert path.read_bytes() == before


def test_csi_synchronization_absence_is_not_a_zero_or_other_plane(tmp_path):
    _csi_sync_archive(tmp_path, lambda row: row.update(PhysicalMeasurementSynchronizationJSON=""))
    checks = audit_trial_values(tmp_path, arithmetic=True)
    assert checks[0]["CheckStatus"] == "PASS_source_reconciliation_only"
    assert checks[1]["CheckStatus"] == "NOT_EVALUATED_missing_source_evidence"


@pytest.mark.parametrize("field,value", [
    ("OracleTimingUsed", True), ("ReceiverZeroPaddingUsed", True),
    ("InputSampleCount", 255), ("DemodulatedSampleCount", -1),
    ("AppliedTimingCorrectionSamples", 0.5),
])
def test_csi_synchronization_rejects_invalid_source_even_when_flat_fields_match(tmp_path, field, value):
    def corrupt(row):
        evidence = json.loads(row["ReceiverSynchronizationJSON"])
        evidence["Timing"][field] = value
        aliases = {"DemodulatedSampleCount": "DemodulatedSampleCount",
                   "AppliedTimingCorrectionSamples": "TimingCorrection_samples"}
        if field in aliases:
            row["Receiver" + aliases[field]] = value
        row["ReceiverSynchronizationJSON"] = json.dumps(evidence)
    _csi_sync_archive(tmp_path, corrupt)
    assert audit_trial_values(tmp_path, arithmetic=True)[0]["CheckStatus"] == "FAIL_source_reconciliation"


def test_csi_synchronization_zero_cfo_and_equal_planes_are_valid(tmp_path):
    def equal_received_planes(row):
        for prefix in ("Receiver", "PhysicalMeasurement"):
            evidence = json.loads(row[prefix+"SynchronizationJSON"])
            evidence["Frequency"]["EstimatedCFO_Hz"] = 0
            evidence["Frequency"]["CFOCorrectionApplied_Hz"] = 0
            row[prefix+"EstimatedCFO_Hz"] = row[prefix+"AppliedCFO_Hz"] = 0
            row[prefix+"SynchronizationJSON"] = json.dumps(evidence)
    _csi_sync_archive(tmp_path, equal_received_planes)
    assert all(r["CheckStatus"] == "PASS_source_reconciliation_only"
               for r in audit_trial_values(tmp_path, arithmetic=True))


@pytest.mark.parametrize("field,value", [("CFOEstimateAvailable", False),
                                       ("CFOCorrectionApplied", False),
                                       ("CFOEstimateAvailable", "unknown")])
def test_csi_synchronization_rejects_inconsistent_frequency_availability(tmp_path, field, value):
    def corrupt(row):
        evidence = json.loads(row["ReceiverSynchronizationJSON"])
        evidence["Frequency"][field] = value
        row["Receiver"+field] = value
        row["ReceiverSynchronizationJSON"] = json.dumps(evidence)
    _csi_sync_archive(tmp_path, corrupt)
    assert audit_trial_values(tmp_path, arithmetic=True)[0]["CheckStatus"] == "FAIL_source_reconciliation"


def test_csi_synchronization_disabled_estimator_is_not_zero_frequency_evidence(tmp_path):
    def disabled(row):
        evidence = json.loads(row["ReceiverSynchronizationJSON"])
        for field, alias in (("EstimatedCFO_Hz", "EstimatedCFO_Hz"),
                             ("CFOCorrectionApplied_Hz", "AppliedCFO_Hz")):
            evidence["Frequency"][field] = None
            row["Receiver"+alias] = "NaN"
        for field in ("CFOEstimateAvailable", "CFOCorrectionApplied"):
            evidence["Frequency"][field] = False
            row["Receiver"+field] = 0
        evidence["Frequency"]["Status"] = row["ReceiverCFOStatus"] = "disabled_by_config"
        row["ReceiverSynchronizationJSON"] = json.dumps(evidence)
    _csi_sync_archive(tmp_path, disabled)
    checks = audit_trial_values(tmp_path, arithmetic=True)
    assert checks[0]["CheckStatus"] == "NOT_EVALUATED_missing_source_evidence"
    assert checks[1]["CheckStatus"] == "PASS_source_reconciliation_only"


def test_trial_audit_retains_missing_values_and_detects_wrong_arithmetic(tmp_path):
    folder = tmp_path / "air_interface" / "csv"
    folder.mkdir(parents=True)
    path = folder / "dl_pdsch_trials.csv"
    with path.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["Slot", "EVM_rms", "EVMErrorEnergy", "EVMReferenceEnergy", "QCLType"])
        writer.writerows([[1, 0.1, 1, 100, "A"], [2, 0.2, 1, 100, ""], [3, "", "", "", ""]])
    original = path.read_bytes()
    inventory = audit_trial_values(tmp_path)
    qcl = next(row for row in inventory if row["Field"] == "QCLType")
    assert qcl["EmptyValues"] == 2 and qcl["TrialRows"] == 3
    checks = audit_trial_values(tmp_path, arithmetic=True)
    assert [row["CheckStatus"] for row in checks] == [
        "PASS_arithmetic_only", "FAIL_arithmetic", "NOT_EVALUATED_missing_or_nonfinite_operands"]
    assert path.read_bytes() == original


def test_empty_table_is_not_zero_error_evidence(tmp_path):
    folder = tmp_path / "air_interface" / "csv"
    folder.mkdir(parents=True)
    (folder / "ul_pusch_trials.csv").write_text("Slot,EVM_rms\n")
    inventory = audit_trial_values(tmp_path)
    assert all(row["InventoryStatus"] == "no_trial_rows" for row in inventory)
    assert audit_trial_values(tmp_path, arithmetic=True) == []


@pytest.mark.parametrize("arithmetic", [False, True])
def test_trial_audit_reads_long_run_path_without_dropping_real_rows(tmp_path, arithmetic):
    # Checkpoint recovery directories can make the PRIMARY CSV path long,
    # not merely a channel-resource path below an otherwise short run root.
    run = tmp_path / ("recovery_" + "a" * 90) / ("retained_" + "b" * 90)
    path = run / "air_interface/csv/dl_pdsch_trials.csv"
    assert len(str(path.resolve())) > 260
    _io_path(path.parent).mkdir(parents=True, exist_ok=True)
    original = b"Slot,EVM_rms,EVMErrorEnergy,EVMReferenceEnergy\n41,0.1,1,100\n"
    with _io_path(path).open("wb") as stream:
        stream.write(original)
    rows = audit_trial_values(run, arithmetic=arithmetic)
    assert rows, "Existing long-path trial files must not silently disappear from the audit."
    assert all(row["SourceCSV"] == "air_interface/csv/dl_pdsch_trials.csv" for row in rows)
    assert all(row["SourceSHA256"] == hashlib.sha256(original).hexdigest() for row in rows)
    if arithmetic:
        assert len(rows) == 1 and rows[0]["CheckStatus"] == "PASS_arithmetic_only"
    else:
        assert len(rows) == 4 and all(row["TrialRows"] == 1 for row in rows)
    assert _io_path(path).read_bytes() == original


def test_converter_audit_uses_production_column_names(tmp_path):
    folder = tmp_path / "air_interface" / "csv"
    folder.mkdir(parents=True)
    (folder / "pdcch_trials.csv").write_text(
        "Slot,ADCErrorMeanSquare,ADCErrorEnergy,ADCErrorSampleCount,"
        "DACErrorMeanSquare,DACErrorEnergy,DACErrorSampleCount\n"
        "1,0.002,2,1000,0.003,1,1000\n")
    checks = audit_trial_values(tmp_path, arithmetic=True)
    assert [(r["Metric"], r["CheckStatus"]) for r in checks] == [
        ("ADCErrorMeanSquare", "PASS_arithmetic_only"),
        ("DACErrorMeanSquare", "FAIL_arithmetic")]


def test_noise_transform_and_rsrq_keep_actual_domain_and_selected_branch(tmp_path):
    folder = tmp_path / "air_interface" / "csv"
    folder.mkdir(parents=True)
    (folder / "csi_rs_trials.csv").write_text(
        "Slot,ReferenceAWGNGridNoiseVariance,ReferenceAWGNSampleNoiseVariance,"
        "SampleToGridNoiseVarianceGain,MeasurementRSRQ_dB,MeasurementNumRB,"
        "MeasurementRSRQNumeratorRSRP_dB_re_UnitOccupiedRE_Es,"
        "MeasurementRSRQDenominatorRSSI_dB_re_UnitOccupiedRE_Es,"
        "MeasurementRSRP_dB_re_UnitOccupiedRE_Es,ChannelEstimateNoiseVariance\n"
        "1,0.0001,2.44140625e-8,4096,-10,100,-20,10,-18,0.003\n"
        "2,0.0002,2.44140625e-8,4096,-8,100,-20,10,-18,0.003\n")
    checks = audit_trial_values(tmp_path, arithmetic=True)
    assert [(r["Metric"], r["CheckStatus"]) for r in checks] == [
        ("ReferenceAWGNGridNoiseVariance", "PASS_arithmetic_only"),
        ("MeasurementRSRQ_dB", "PASS_arithmetic_only"),
        ("ReferenceAWGNGridNoiseVariance", "FAIL_arithmetic"),
        ("MeasurementRSRQ_dB", "FAIL_arithmetic")]


def _channel_archive(tmp_path, direction="dl", mutate=None, relative=None):
    relative = relative or "channel_estimation/csv/same_capture.csv"
    resource = tmp_path / relative
    _io_path(resource.parent).mkdir(parents=True, exist_ok=True)
    row = dict(Slot=41, UEIndex=1, ConfiguredSNR_dB=40,
               HReal=1.1, HImag=0, ReferenceHReal=1, ReferenceHImag=0,
               ChannelErrorEnergy=0.01, ReferenceChannelEnergy=1,
               ChannelObservationID="actual-observation", ChannelReferencePlane="executed-clock",
               ReferenceUsedByReceiver=0, GainOrPhaseFitted=0)
    if mutate:
        row.update(mutate)
    with _io_path(resource).open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(row)); w.writeheader(); w.writerow(row)
    trial = dict(Slot=41, UEIndex=1, ConfiguredSNR_dB=40, NMSE_dB=-20,
                 ChannelObservationID="actual-observation",
                 ChannelEstimateReferencePlane="executed-clock",
                 ChannelEstimateComparedValues=1,
                 ChannelEstimateResourcesCSV=relative,
                 ChannelEstimateResourcesCSVSHA256=hashlib.sha256(_io_path(resource).read_bytes()).hexdigest())
    primary = tmp_path / "air_interface/csv" / ("dl_pdsch_trials.csv" if direction == "dl" else "ul_pusch_trials.csv")
    primary.parent.mkdir(parents=True, exist_ok=True)
    with primary.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(trial)); w.writeheader(); w.writerow(trial)
    return primary, resource


@pytest.mark.parametrize("direction", ["dl", "ul"])
def test_channel_archive_recomputes_actual_complex_samples(tmp_path, direction):
    primary, resource = _channel_archive(tmp_path, direction)
    old_primary = primary.read_bytes(); old_resource = resource.read_bytes()
    rows = audit_channel_resources(tmp_path)
    assert len(rows) == 1 and rows[0]["CheckStatus"] == "PASS_resource_reconciliation_only"
    assert math.isclose(rows[0]["RecomputedNMSE_dB"], -20, abs_tol=1e-12)
    assert primary.read_bytes() == old_primary and resource.read_bytes() == old_resource


@pytest.mark.parametrize("change,reason", [
    ({"HReal": 1.2}, "resource_error_energy_mismatch"),
    ({"Slot": 42}, "resource_trial_identity_mismatch:Slot"),
    ({"ChannelObservationID": "other"}, "resource_observation_mismatch"),
    ({"ChannelReferencePlane": "different"}, "resource_reference_plane_mismatch"),
    ({"ReferenceUsedByReceiver": 1}, "reference_not_independent_of_receiver"),
    ({"GainOrPhaseFitted": 1}, "unexpected_gain_or_phase_fit_in_data_channel_archive"),
])
def test_channel_archive_rejects_numeric_or_identity_corruption_with_valid_hash(tmp_path, change, reason):
    _channel_archive(tmp_path, mutate=change)
    row = audit_channel_resources(tmp_path)[0]
    assert row["CheckStatus"] == "FAIL_resource_reconciliation"
    assert reason in row["Reasons"]
    assert "sha256" not in row["Reasons"]  # The contents, not just the hash, are checked.


def test_channel_archive_rejects_changed_hash_and_escaping_path(tmp_path):
    primary, resource = _channel_archive(tmp_path)
    with resource.open("a") as f:
        f.write("\n")
    assert "resource_sha256_mismatch_or_missing" in audit_channel_resources(tmp_path)[0]["Reasons"]
    original = primary.read_text()
    primary.write_text(original.replace("channel_estimation/csv/same_capture.csv", "../outside.csv"))
    assert audit_channel_resources(tmp_path)[0]["CheckStatus"] == "FAIL_resource_path"


def test_channel_archive_reads_long_windows_path_without_false_missing(tmp_path):
    relative = "/".join(["channel_estimation", "x" * 80, "y" * 80, "sample.csv"])
    _channel_archive(tmp_path, relative=relative)
    assert audit_channel_resources(tmp_path)[0]["CheckStatus"] == "PASS_resource_reconciliation_only"
