"""Receiver diagnostics retain field identity, units, and missing evidence."""
from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as dash


def preview(channel, row):
    return dash.summarize_control_trial_preview_rows(channel, [row])[0]


def test_prach_preamble_zero_and_timing_domains():
    row = preview("prach_trials", dict(Slot=31, PreambleIndexTx=0,
        DetectedPreambleIndex=0, PreambleDetected=1, PRACHRawTimingEstimate_samples=77,
        PRACHPropagationTimingEstimate_samples=0, PRACHTimingSampleRate_Hz=7680000,
        TimingAdvanceCommand=0, TimingAdvanceNTA_Tc=0, TimingAdvance_us=0,
        Msg3TimingAdvanceApplied=1, MissedDetection=0, FalseAlarmFlag=0, DTXFlag=0,
        PreambleDetectionThresholdCalibrationStatus="single_detection_not_statistical_qualification"))
    assert row["TX preamble (audit)"] == row["Detected preamble"] == 0
    assert row["Raw timing (samples)"] == 77
    assert row["Propagation timing (samples)"] == row["RAR TA command"] == 0
    assert row["TA (us)"] == 0 and row["Msg3 TA applied"] == 1
    assert row["Missed detection"] == row["False alarm"] == row["DTX"] == 0
    assert row["Qualification status"] == "single_detection_not_statistical_qualification"


def test_ssb_sync_is_not_substituted_by_configured_truth():
    row = preview("pbch_trials", dict(Slot=1, PSSDetected=1, SSSDetected=1,
        NCellIDRecovered=17, NCellID=4, SSBIndex=0, SSBIdentityVerified=1,
        TimingOffset_samples=1100, EstimatedCFO_PreCorrection_Hz=21.5,
        InjectedCFO_Hz=25, SS_RSRP_dB_re_UnitOccupiedRE_Es=-6.8,
        SS_SINR_dB=19.2, ResidualCFOMeasurementStatus="unavailable_no_estimator"))
    assert row["Recovered PCI"] == 17
    assert row["SSB position (samples)"] == 1100
    assert row["Estimated CFO (Hz)"] == 21.5
    assert "Residual CFO (Hz)" not in row
    assert "SS-RSRP (dBm)" not in row
    assert row["SS-RSRP (dB re unit Es)"] == -6.8


def test_failed_ssb_preserves_measured_detector_not_a_fake_sinr():
    row = preview("pbch_trials", dict(PSSDetected=0, CRCPass=0,
        PSSNormalizedMetric=0.08, PSSDetectionThreshold=0.17,
        PSSDetectionHypothesisCount=4185, ConfiguredSNR_dB=-30))
    assert row["PSS normalized correlation"] == 0.08
    assert row["PSS detection threshold"] == 0.17
    assert row["PSS tested hypotheses"] == 4185
    assert "SSS normalized correlation" not in row


def test_blind_candidates_and_hypotheses_are_separate():
    row = preview("pdcch_trials", dict(Slot=44, PDCCHCandidatesAvailable=8,
        PDCCHCandidatesAttempted=8, BlindDecodeCount=16, PDCCHSelectedCandidateIndex=1,
        PDCCHCandidateFlatIndex=2, PDCCHCandidateDecodeOKVector="0|1|1|0",
        PDCCHMissedDetection=0, PDCCHFalseAlarm=0, DecodedDCIFormat="0_1"))
    assert row["Candidates attempted"] == 8 and row["Blind decodes"] == 16
    assert row["Selected candidate"] == 1 and row["Selected flat index"] == 2
    assert row["Hypothesis decode vector"] == "0|1|1|0"
    assert row["Decoded DCI format"] == "0_1"


def test_crc_failure_does_not_invent_dtx_or_false_alarm():
    for channel in ("prach_trials", "pdcch_trials", "pucch_trials"):
        row = preview(channel, dict(Slot=34, CRCPass=0, Status="FAIL"))
        assert "DTX" not in row and "Missed detection" not in row
        assert "Missed feedback" not in row and "False alarm" not in row
    assert dash.summarize_control_trial_preview_rows("prach_trials", []) == []


def test_short_uci_crc_applicability_and_reported_dtx():
    row = preview("pucch_trials", dict(Slot=34, DTXFlag=1, CRCApplicable=0,
        CRCOutcome="not_applicable", MissedFeedback=1, FalseAck=0,
        DetectionOutcome="dtx", DetectionThreshold=0.2))
    assert row["CRC applicable"] == 0 and row["CRC outcome"] == "not_applicable"
    assert row["DTX"] == 1 and row["Missed feedback"] == 1
    assert row["False ACK"] == 0


def test_rendered_page_contains_diagnostic_panels_and_scope_note():
    with patch.object(dash, "list_scenarios", return_value=["test.yaml"]):
        page = dash.build_product_frontend_page("realtime", "test.yaml").decode()
    for title in ("PRACH timing / RAR timing advance", "SSB measured timing / frequency synchronization",
                  "PDCCH / DCI blind detection", "PDCCH receiver hypothesis evidence",
                  "PUCCH / UCI detection and DTX"):
        assert title in page
    assert "not statistically qualified rates" in page
    assert 'colspan="${spec.columns.length}"' in page
