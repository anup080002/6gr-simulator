from __future__ import annotations

import copy
import csv
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
from lls_waveform_quality import (waveform_quality_fields, precoding_evidence_fields,
                                  synchronization_search_fields, qualification_criteria_fields)
import lls_web_dashboard as dashboard


def test_precoder_matrix_match_is_not_scalar_pmi_or_a_measured_beam():
    row = dict(Slot=47, RequestedPrecoderSHA256="a"*64, AppliedPrecoderSHA256="a"*64,
               PrecoderDigestDomain="element", RequestedBeamIndexSet=1, BestBeamIndex=3,
               BestBeamGain_dB=-12, BeamCandidateCount=4, LinkAdaptationBootstrap=1,
               AppliedPrecoderPMI="NaN", AppliedBeamIndexSet="")
    view = dashboard.summarize_data_trial_preview_rows("dl_trials", [row])[0]
    assert view["Matrix identity match"] == 1 and view["Bootstrap grant"] == 1
    assert view["Best projection power (dB)"] == -12
    assert "Applied beam" not in view and "Applied basis PMI" not in view
    row["AppliedPrecoderSHA256"] = "b"*64
    assert precoding_evidence_fields(row)["Matrix identity match"] == 0
    row.pop("PrecoderDigestDomain")
    assert "Matrix identity match" not in precoding_evidence_fields(row)


@pytest.mark.parametrize("window,count", [([0,0],1), ([0,1229],1230), ([10,20],11)])
def test_retained_csi_search_extent_exposes_fixed_alignment(window,count):
    row = {"ReceiverSynchronizationJSON": json.dumps({"Timing":{"SearchWindowSamples":window}})}
    fields = synchronization_search_fields(row, "Receiver")
    assert fields["timing_hypotheses"] == count
    assert ("no timing acquisition" in fields["timing_search_scope"]) == (count==1)
    assert synchronization_search_fields(row, "PhysicalMeasurement") == {}


@pytest.mark.parametrize("value", ["", "null", "[]", "invalid", '{"Timing":null}'])
def test_absent_sync_metadata_is_not_inferred_from_zero_correction(value):
    assert synchronization_search_fields({"ReceiverSynchronizationJSON":value,
                                         "ReceiverTimingCorrection_samples":0}, "Receiver") == {}


def test_thresholds_are_retained_not_invented_from_status():
    view = qualification_criteria_fields("trs_trials", dict(
        DetectionThreshold=.55, ChannelNMSEThreshold_dB=-8,
        TRSRuntimeEvidenceUsable=1, StrictReceiverEvidenceOk=1, StrictOk=0))
    assert view["Detection threshold"] == .55
    assert view["NMSE qualification limit (dB)"] == -8
    assert view["TRS runtime usable"] == 1 and view["Qualification passed"] == 0
    assert qualification_criteria_fields("trs_trials", {"Status":"PASS"}) == {}
    prach = qualification_criteria_fields("prach_trials", dict(
        PreambleDetectionThresholdSource="native_format_formula",
        PreambleDetectionThresholdCalibrationStatus="single_detection_not_statistical_qualification",
        Msg1ConfiguredTargetFalseAlarmProbability=.001))
    assert prach["Target false-alarm probability"] == .001
    assert prach["Detector qualification"] == "single_detection_not_statistical_qualification"


def test_realtime_template_explains_beam_search_threshold_and_symbol_semantics():
    template = Path(dashboard.__file__).read_text(encoding="utf-8")
    for text in ("Recorded receiver acceptance / qualification criteria",
                 "Matrix identity match", "Timing hypotheses",
                 "symbols are zero-based inclusive allocation bounds",
                 "post-hoc Hest projection scores are not antenna gain"):
        assert text in template


@pytest.mark.parametrize("key", [
    "pbch_trials", "pdcch_trials", "pucch_trials", "srs_trials", "trs_trials",
    "dl_trials", "ul_trials",
])
def test_actual_fields_survive_production_preview(key):
    raw = dict(Slot=47, UEID=1, EVM_rms=.0707672426201632,
               EVMReferenceSource="same_executed_desired_link_received_pilot_grid",
               EVMValueStatus="MEASURED_PAIRED_RECEIVED_PILOT_GRID_NOT_RF_CONFORMANCE",
               NMSE_dB=-24.68, NMSEScoringAvailable=1, NMSEReferenceSource="actual_reference",
               ChannelEstimateAvailable=1, ChannelEstimateSource="actual_estimator",
               EqualizationAvailable=0, SweepPointIndex=2, ConfiguredSNR_dB=40)
    original = copy.deepcopy(raw)
    reducer = (dashboard.summarize_data_trial_preview_rows if key in {"dl_trials", "ul_trials"}
               else dashboard.summarize_control_trial_preview_rows)
    view = reducer(key, [raw])[0]
    assert view["EVM percent"] == pytest.approx(7.07672426201632)
    assert view["EVM applicable"] == 1
    assert view["EVM status"] == raw["EVMValueStatus"]
    assert view["EVM reference source"] == raw["EVMReferenceSource"]
    assert view["NMSE reference source"] == "actual_reference"
    assert view["Channel estimate available"] == 1 and view["Equalization available"] == 0
    assert raw == original


def test_pbch_legacy_flag_conflict_and_beam_identity_remain_visible():
    raw = dict(Slot=1, SSBIndex=0, RuntimeStageWaveformsUsed=0,
               ObservationCoverageSource="complete_contiguous_received_sample_buffer",
               ObservationStartSample=0, ObservationEndSampleExclusive=860160,
               ObservationSampleRateHz=122880000, ChannelEstimateAvailable=1,
               ChannelEstimateSource="nrChannelEstimate_pbch_dmrs_sss", EqualizationAvailable=1)
    view = dashboard.summarize_control_trial_preview_rows("pbch_trials", [raw])[0]
    assert view["Waveform executed"] == 1
    assert "legacy waveform-used flag" in view["Evidence notes"]
    assert view["SSB index"] == 0
    assert view["Observation start sample"] == 0
    assert raw["RuntimeStageWaveformsUsed"] == 0


def test_noncoherent_flags_are_not_mistaken_for_executed_estimator():
    raw = dict(ChannelEstimateSource="not_applicable_format0_noncoherent_sequence_detection",
               ChannelEstimateAvailable=1, EqualizationAvailable=1)
    view = waveform_quality_fields("pucch_trials", raw)
    assert view["Channel estimate applicable"] == view["Equalization applicable"] == 0
    assert view["Channel estimate available"] == view["Equalization available"] == 0
    assert view["EVM applicable"] == 0 and "legacy availability" in view["Evidence notes"]
    assert "EVM rms" not in view and "EVM percent" not in view


def test_data_clock_and_nmse_alias_are_exact_and_scope_labelled():
    raw = dict(NMSESource="actual_PDSCH_DMRS_LS", NMSEScoringAvailable=1,
               DataReceiveTimingSource="actual_received_reference_alignment_and_executed_OFDM_symbol_lengths",
               DataReceiveSymbolStartSample=2835088, DataReceiveSymbolEndSampleExclusive=2887696,
               DataReceiveSampleRateHz=122880000, ChannelObservationStartSample=2826240,
               RxRFOutputWaveformSHA256="a" * 64)
    view = waveform_quality_fields("dl_trials", raw)
    assert view["NMSE reference source"] == raw["NMSESource"]
    assert view["Observation start sample"] == 2835088
    assert "not full capture" in view["Observation scope"]
    assert "not necessarily decoder-aligned" in view["Waveform hash plane"]


def test_hash_plane_cannot_silently_switch_from_tx_to_rx():
    raw = dict(PDCCHWaveformHash="a" * 64)
    assert waveform_quality_fields("pdcch_trials", raw)["Waveform hash plane"] == "prepared PDCCH TX waveform"
    raw.update(ReceiverObservationSHA256="b" * 64,
               ReceiverObservationHashPlane="actual_receiver_input_before_synchronization")
    view = waveform_quality_fields("pdcch_trials", raw)
    assert view["Waveform hash"] == "b" * 64
    assert view["Waveform hash plane"] == raw["ReceiverObservationHashPlane"]


@pytest.mark.parametrize("key", ["pbch_trials", "prach_trials", "pdcch_trials", "dl_trials"])
def test_pass_never_fills_missing_measurements_or_execution(key):
    view = waveform_quality_fields(key, dict(Status="PASS", EVM_rms="NaN",
                                            NMSE_dB="NaN", ChannelObservationStartSample=0))
    assert view == {}


def test_conflicting_evm_units_are_visible_not_silently_accepted():
    view = waveform_quality_fields("pucch_trials", dict(EVM_rms=.05, ReceiverEVMPercent=50))
    assert view["EVM percent"] == 5 and "conflicting stored EVM units" in view["Evidence notes"]


def test_csi_nominal_channel_scoring_survives_production_preview():
    # Retained CSI scoring schema: nominal linear reference, not the
    # effective RF-inclusive pilot reference used by some other channels.
    raw = dict(Slot=46, UEIndex=1, Direction="DL", ConfiguredSNR_dB=40,
               NMSE_dB=-4.08515671254281, NMSEScoringAvailable=1,
               ChannelNMSESource="executed_channel_coefficients_and_actual_resource_precoders_after_CSI_selection",
               ChannelNMSEReferencePlane="nominal_linear_CSI_RS_port_channel_on_actual_RX_FFT_clock",
               ChannelNMSEComparedComplexValues=69888, ChannelNMSEPilotResourceCount=17472,
               ChannelNMSEQualificationMode="same_execution_nominal_linear_channel_no_gain_or_phase_fit",
               ChannelNMSEReferenceIncludesRFImpairments=0,
               ChannelNMSEReferenceUsedByReceiver=0, ChannelEstimateAvailable=1,
               ChannelEstimateSource="csirs_resource_set_receiver_measurements")
    original = copy.deepcopy(raw)
    view = dashboard.summarize_control_trial_preview_rows("csirs_trials", [raw])[0]
    assert view["Slot"] == 46 and view["UE"] == 1
    assert view["NMSE dB"] == raw["NMSE_dB"]
    assert view["NMSE reference source"] == raw["ChannelNMSESource"]
    assert view["NMSE reference plane"] == raw["ChannelNMSEReferencePlane"]
    assert view["NMSE compared complex values"] == 69888
    assert view["NMSE pilot resource count"] == 17472
    assert view["NMSE qualification mode"] == raw["ChannelNMSEQualificationMode"]
    assert view["NMSE reference includes RF impairments"] == 0
    assert view["NMSE reference used by receiver"] == 0
    assert not {"EVM rms", "EVM percent", "Waveform hash", "Waveform executed"} & view.keys()
    assert raw == original


def test_csi_waveform_quality_never_uses_aggregated_stats_as_a_receiver_trial():
    owner = dashboard.CANONICAL_RUNTIME_ARTIFACT_OWNERS["csirs_trials"]
    assert owner["canonical_path"] == "air_interface/csv/csi_rs_trials.csv"
    assert owner["legacy_paths"] == ["control/csv/csi_rs_trials.csv"]


@pytest.mark.parametrize("logical_path,expected", [
    ("air_interface/csv/csi_rs_trials.csv", 2),
    ("reports/csv/live_csirs_stats.csv", 0),
])
def test_runtime_payload_binds_csi_observations_not_aggregate_alias(tmp_path, logical_path, expected):
    # Repeated SNR and slot values must not collapse distinct sweep points.
    path = tmp_path / "source.csv"
    rows = [dict(Slot=46, UEIndex=1, SweepPointIndex=point, ConfiguredSNR_dB=40,
                 NMSE_dB=-4, ChannelNMSESource="nominal_linear_reference",
                 ChannelNMSEReferencePlane="nominal_linear_port_channel",
                 ChannelNMSEComparedComplexValues=16) for point in (1, 2)]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    artifact = dict(artifact_id=-902, logical_path=logical_path, filesystem_path=str(path),
                    byte_size=path.stat().st_size, artifact_kind="csv", mime_type="text/csv")
    context = dashboard.extract_runtime_context(dict(run_id=-902, status="running"), [artifact])
    preview = context["control_trial_previews"]["csirs_trials"]
    assert len(preview) == expected
    if expected:
        assert [row["Sweep point"] for row in preview] == [1, 2]
        assert all(row["NMSE reference source"] == "nominal_linear_reference" for row in preview)
        assert all("Waveform executed" not in row and "EVM rms" not in row for row in preview)
        assert context["artifact_selection"]["raw_control_trials"]["csirs_trials"]["fallback_used"] is False


def test_production_javascript_waveform_quality_includes_exact_csi_rows():
    node = shutil.which("node")
    if node is None:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    source = Path(dashboard.__file__).read_text(encoding="utf-8")
    begin = source.index("    const firstValue = (row, names) => {", source.index("const controlPreviews ="))
    end = source.index("    const dlSynchronizationRows =", begin)
    rows = [dict(Slot=46, UE=1, **{"NMSE dB": -4.085,
            "NMSE reference source": "actual_nominal_reference",
            "NMSE reference plane": "nominal_linear_CSI_RS_port_channel_on_actual_RX_FFT_clock",
            "NMSE compared complex values": 69888, "NMSE pilot resource count": 17472,
            "NMSE reference includes RF impairments": 0,
            "NMSE reference used by receiver": 0})]
    script = "const recent = rows => rows || []; const dataPreviews = {}; const controlPreviews = "
    script += json.dumps({"csirs_trials": rows}) + ";\n" + source[begin:end]
    script += "\nconsole.log(JSON.stringify(waveformQualityRows));"
    actual = json.loads(subprocess.run([node, "-e", script], capture_output=True,
                                     text=True, check=True, timeout=15).stdout)
    assert len(actual) == 1 and actual[0]["Channel"] == "CSI-RS"
    for key, value in rows[0].items():
        assert actual[0][key] == value
    assert actual[0]["EVM rms"] is None and actual[0]["Waveform hash"] is None
    panel = next(line for line in source.splitlines() if "id:'waveform_quality'" in line)
    for field in ("NMSE reference plane", "NMSE compared complex values",
                  "NMSE pilot resource count", "NMSE reference includes RF impairments",
                  "NMSE reference used by receiver"):
        assert repr(field) in panel


def _untransmitted_pdcch_row():
    return dict(Slot=51, UEID=1, Direction="DL", SweepPointIndex=1,
                ConfiguredSNR_dB=40, Status="NA", MeasurementAttempted=0,
                PDCCHReceiverTrialExecuted=0, RuntimeStageWaveformsUsed=0,
                RuntimeMaterializationStatus="active_integrated_pdcch_pretransmission_admission_disposition",
                FailureReason="control_blocked_no_nonoverlapping_pdcch_candidate")


@pytest.mark.parametrize("csv_strings", [False, True])
def test_pdcch_admission_disposition_is_not_a_missing_receiver_measurement(csv_strings):
    raw = _untransmitted_pdcch_row()
    if csv_strings:
        raw = {k: str(v) for k, v in raw.items()}
    original = copy.deepcopy(raw)
    view = dashboard.summarize_control_trial_preview_rows("pdcch_trials", [raw])[0]
    assert view["Receiver evidence scope"] == "pretransmission_admission_no_receiver"
    assert view["Admission blocker"] == raw["FailureReason"]
    assert float(view["PDCCH receiver attempted"]) == 0
    assert float(view["Measurement attempted"]) == 0
    assert float(view["Waveform executed"]) == 0 and view["Status"] == "NA"
    assert float(view["UE"]) == 1 and float(view["Slot"]) == 51
    assert raw == original


@pytest.mark.parametrize("changes", [
    {"PDCCHReceiverTrialExecuted": 1},
    {"MeasurementAttempted": 1},
    {"RuntimeStageWaveformsUsed": 1},
    {"ReceiverObservationSHA256": "a" * 64},
    {"ReceiverObservationSHA256": "malformed_hash_needs_review"},
    {"EVM_rms": .1},
    {"EVM_rms": "invalid_measurement_needs_review"},
    {"NMSE_dB": -20},
    {"NMSE_dB": "-Inf"},
    {"ObservationCoverageSource": "complete_contiguous_received_sample_buffer"},
    {"ChannelEstimateAvailable": 1},
    {"NMSEScoringAvailable": 1},
])
def test_conflicting_admission_record_cannot_hide_received_evidence(changes):
    raw = {**_untransmitted_pdcch_row(), **changes}
    view = waveform_quality_fields("pdcch_trials", raw)
    assert view["Receiver evidence scope"] == "conflicting_pretransmission_and_receiver_evidence"
    assert "conflicting" in view["Evidence notes"]


@pytest.mark.parametrize("missing", ["RuntimeStageWaveformsUsed", "PDCCHReceiverTrialExecuted", "MeasurementAttempted"])
def test_admission_disposition_with_missing_execution_flags_stays_visible(missing):
    raw = _untransmitted_pdcch_row()
    raw.pop(missing)
    view = waveform_quality_fields("pdcch_trials", raw)
    assert view["Receiver evidence scope"] == "pretransmission_disposition_execution_unverified"


def test_absent_or_failed_receiver_is_not_inferred_to_be_an_admission_disposition():
    for row in ({"Slot": 51, "Status": "NA"},
                {"Slot": 51, "Status": "FAIL", "PDCCHReceiverTrialExecuted": 1},
                {"Slot": 51, "Status": "CRASH", "RuntimeStageWaveformsUsed": 1}):
        assert waveform_quality_fields("pdcch_trials", row).get("Receiver evidence scope") != (
            "pretransmission_admission_no_receiver")


def test_browser_separates_admission_without_dropping_failed_receivers():
    node = shutil.which("node")
    if node is None:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    raw = [_untransmitted_pdcch_row(), dict(Slot=52, UEIndex=1, Status="FAIL",
           RuntimeStageWaveformsUsed=1, PDCCHReceiverTrialExecuted=1,
           MeasurementAttempted=1, EVM_rms=.2), dict(Slot=53, UEIndex=1, Status="CRASH")]
    preview = dashboard.summarize_control_trial_preview_rows("pdcch_trials", raw)
    source = Path(dashboard.__file__).read_text(encoding="utf-8")
    begin = source.index("    const firstValue = (row, names) => {", source.index("const controlPreviews ="))
    end = source.index("    const dlSynchronizationRows =", begin)
    script = "const recent = rows => rows || []; const dataPreviews = {}; const controlPreviews = "
    script += json.dumps({"pdcch_trials": preview}) + ";\n" + source[begin:end]
    script += "\nconsole.log(JSON.stringify({quality:waveformQualityRows,admission:pdcchAdmissionRows,received:pdcchReceiverRows}));"
    actual = json.loads(subprocess.run([node, "-e", script], capture_output=True,
                                     text=True, check=True, timeout=15).stdout)
    assert [r["Slot"] for r in actual["admission"]] == [51]
    assert [r["Slot"] for r in actual["received"]] == [52, 53]
    assert [r["Slot"] for r in actual["quality"]] == [52, 53]
    assert actual["admission"][0]["Admission blocker"] == raw[0]["FailureReason"]
    assert [r["Status"] for r in actual["quality"]] == ["FAIL", "CRASH"]
    admission_panel = next(line for line in source.splitlines() if "id:'pdcch_admission'" in line)
    assert "rows:pdcchAdmissionRows" in admission_panel and "Admission blocker" in admission_panel
    for key in ("pdcch", "pdcch_hypotheses"):
        panel = next(line for line in source.splitlines() if "id:'" + key + "'" in line)
        assert "rows:pdcchReceiverRows" in panel
