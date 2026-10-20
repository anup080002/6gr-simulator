from __future__ import annotations

import copy
import json
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
