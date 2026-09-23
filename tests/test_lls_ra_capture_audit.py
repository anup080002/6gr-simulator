import copy
import json
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from audit_lls_ra_capture import audit_rows


def fixture():
    return dict(StageName="Msg1", Direction="UL", RuntimeTransportMode="shared_physical_waveform_stream",
                WaveformSource="shared_physical_stream_received_post_adc_gain_compensated",
                RuntimeStageWaveformUsed="1", SelfLoopWaveformUsed="0", ObservationStartSample="100",
                ObservationEndSampleExclusive="200", ObservationSampleRateHz="1000", RxSampleCount="100",
                ObservationCompletionTime_s="0.2", RuntimeChannelLinkKey="dir=UL;tx=UE1;rx=gNB1",
                RuntimeChannelStateUsed="1", AppliedTxPower_dBm="-10", MeasuredTxPowerBeforeRF_dBm="-10",
                TxPowerClosureError_dB="0", NoiseOperatingMode="receiver_noise_figure_thermal_noise",
                PowerNormalizationPolicy="active_ofdm_total_power", FullBWPActivityFactor="1",
                ReferenceOutputPower_dBm="-10", ExpectedEmittedPower_mW="0.1",
                ThermalNoisePSD_mWPerHz="1e-17", ThermalSampleNoiseBandwidth_Hz="1000",
                NoiseVariancePreFrontEnd_mW="1e-14", PhysicalExecutionSegmentsJSON=json.dumps([
                    dict(Source="composed_tx_retained_rf_per_link_channel_sum_receiver_noise_rf",
                         StartSample=a, EndSampleExclusive=b) for a, b in [(90, 150), (150, 210)]]))


def test_valid_partial_and_complete_scopes():
    row = fixture()
    assert audit_rows([row])["passed"]
    assert not audit_rows([row], require_complete=True)["passed"]
    assert not audit_rows([])["passed"]
    rows = []
    for i in range(1, 5):
        r = copy.deepcopy(row)
        r["StageName"] = f"Msg{i}"
        r["Direction"] = "UL" if i % 2 else "DL"
        r["RuntimeChannelLinkKey"] = f"dir={r['Direction']};actual_fixture_link"
        rows.append(r)
    assert audit_rows(rows, require_complete=True)["passed"]
    setup = fixture()
    setup["StageName"] = "RRCSetupComplete"
    assert audit_rows(rows+[setup], require_complete=True)["passed"]


@pytest.mark.parametrize("field,value", [("Direction", "DL"), ("SelfLoopWaveformUsed", "1"),
    ("RxSampleCount", "99"), ("ObservationCompletionTime_s", "0.201"),
    ("RuntimeChannelLinkKey", "dir=DL;tx=gNB1"), ("MeasuredTxPowerBeforeRF_dBm", "-9"),
    ("TxPowerClosureError_dB", "1"), ("NoiseVariancePreFrontEnd_mW", "1e-13"),
    ("ObservationSampleRateHz", "NaN"), ("PhysicalExecutionSegmentsJSON", "[]")])
def test_corruption_is_not_masked(field, value):
    row = fixture()
    row[field] = value
    assert not audit_rows([row])["passed"]


@pytest.mark.parametrize("boundary", [149, 151])
def test_overlap_and_gap_rejected(boundary):
    row = fixture()
    segments = json.loads(row["PhysicalExecutionSegmentsJSON"])
    segments[1]["StartSample"] = boundary
    row["PhysicalExecutionSegmentsJSON"] = json.dumps(segments)
    assert not audit_rows([row])["passed"]


def test_full_bwp_budget_is_not_actual_emitted_power():
    row = fixture()
    row.update(PowerNormalizationPolicy="fixed_epre_over_configured_bwp", FullBWPActivityFactor="0.5",
               MeasuredTxPowerBeforeRF_dBm="-13.010299956639813", ExpectedEmittedPower_mW="0.05")
    assert audit_rows([row])["passed"]
    del row["FullBWPActivityFactor"]
    assert not audit_rows([row])["passed"]


def normalized_fixture():
    row = fixture()
    for field in ("AppliedTxPower_dBm", "MeasuredTxPowerBeforeRF_dBm", "ReferenceOutputPower_dBm",
                  "ExpectedEmittedPower_mW", "NoiseVariancePreFrontEnd_mW"):
        row[field] = "NaN"
    row.update(NoiseOperatingMode="standalone_awgn_snr_argument", NoiseApplied="1",
               PhysicalDevicePowerClaim="0", PowerNormalizationPolicy="unit_occupied_re_fixed_esn0",
               AppliedTxPowerValueRole="normalized_waveform_power_not_physical_dbm",
               AppliedTxPower_dB_re_UnitOccupiedRE_Es="-30", MeasuredTxPowerBeforeRF_dB_re_UnitOccupiedRE_Es="-30",
               ReferenceOutputPower_dB_re_UnitOccupiedRE_Es="-30", ExpectedWaveformPower_re_UnitOccupiedRE_Es="0.001",
               RequestedAWGNReferenceSNR_dB="20", ReferenceAWGNGridNoiseVariance="0.0025",
               ReferenceAWGNSampleNoiseVariance="0.0000048828125", SampleToGridNoiseVarianceGain="512",
               NoiseVariancePreFrontEnd_re_UnitOccupiedRE_Es="0.0000048828125",
               NoiseVarianceSource="fixed_configured_occupied_re_esn0_canonical_ofdm_transform",
               SharedNoiseCalibrationSource="fixed_once_from_configured_occupied_re_energy_and_canonical_ofdm_noise_transform")
    return row


def test_normalized_awgn_requires_independent_config_not_dbm_or_thermal_labels():
    row = normalized_fixture()
    reference = dict(snr_db=20, awgn_reference_re_energy=0.25)
    assert audit_rows([row], awgn_reference=reference)["passed"]
    for invalid in (None, {}, dict(snr_db=19, awgn_reference_re_energy=0.25),
                    dict(snr_db=20, awgn_reference_re_energy=1)):
        assert not audit_rows([row], awgn_reference=invalid)["passed"]


@pytest.mark.parametrize("field,value", [
    ("PhysicalDevicePowerClaim", "1"), ("AppliedTxPower_dBm", "-30"),
    ("PowerNormalizationPolicy", "active_ofdm_total_power"),
    ("AppliedTxPowerValueRole", "physical_dbm"),
    ("MeasuredTxPowerBeforeRF_dB_re_UnitOccupiedRE_Es", "-29"),
    ("ExpectedWaveformPower_re_UnitOccupiedRE_Es", "0.002"),
    ("TxPowerClosureError_dB", "1"), ("NoiseApplied", "0"),
    ("RequestedAWGNReferenceSNR_dB", "0"), ("ReferenceAWGNGridNoiseVariance", "0.25"),
    ("ReferenceAWGNSampleNoiseVariance", "0.0001"), ("SampleToGridNoiseVarianceGain", "1024"),
    ("NoiseVariancePreFrontEnd_re_UnitOccupiedRE_Es", "0.001"),
    ("NoiseVarianceSource", "instantaneous_waveform_power"),
    ("SharedNoiseCalibrationSource", "receiver_estimated_noise")])
def test_normalized_awgn_corruption_is_not_masked(field, value):
    row = normalized_fixture()
    row[field] = value
    assert not audit_rows([row], awgn_reference=dict(snr_db=20, awgn_reference_re_energy=0.25))["passed"]
