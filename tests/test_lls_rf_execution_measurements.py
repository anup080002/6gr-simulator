from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as dashboard


def test_srs_common_phase_rate_is_not_relabelled_doppler_or_zero():
    source = dict(Slot=10, PilotCommonPhaseRate_Hz=75.01,
                  PilotPhaseUnaliasedHalfWidth_Hz=100,
                  PilotPhasePairCount=1, PilotPhaseMatchedChannelValueCount=576,
                  PilotPhaseObservationScope="between_received_occasions",
                  PilotPhaseHistoryStatus="matched_previous_received_pilot_snapshot",
                  PilotPhaseObservationSeparation_s=0.005,
                  PilotPhaseEvolutionStatus="measured_common_phase_rate_with_explicit_alias_interval",
                  DopplerMeasurementStatus="maximum_doppler_spread_not_identifiable_from_common_phase")
    row = dashboard.summarize_control_trial_preview_rows("srs_trials", [source])[0]
    assert row["Matched-pilot common phase rate (Hz; not Doppler spread)"] == 75.01
    assert row["Pilot phase observation scope"] == "between_received_occasions"
    assert row["Unaliased common-phase half-width (Hz)"] == 100
    empty = dashboard.summarize_control_trial_preview_rows("srs_trials", [{"Slot": 5}])[0]
    assert dashboard.coerce_numeric(empty.get("Matched-pilot common phase rate (Hz; not Doppler spread)")) is None


def test_time_varying_agc_and_converter_errors_are_not_hidden_or_called_evm():
    source = dict(
        AGCExecuted=1, AGCControlModel="causal_windowed_joint_rms_attack_hold_release",
        AGCDecisionCausal=1, AGCExecutionStatus="executed_time_varying_sample_gain",
        AGCTargetRMS=0.25, AGCOverloadGuardEnabled=1, AGCOverloadGuardGainStep_dB=6,
        AGCOverloadGuardFeedbackLatencySamples=1, AGCOverloadGuardTriggerCount=7,
        AGCOverloadGuardObservationPlane="pre_ADC_I_Q_rail_comparator_before_dither_or_jitter",
        AGCGainIsTimeVarying=1, AGCGain_dB="NaN", AGCGainMin_dB=0,
        AGCGainMax_dB=40, AGCGainSampleCount=100, AGCGainEvidenceSource="retained_sample_trace",
        ADCErrorMeanSquare=0.01, ADCErrorSampleCount=400, ADCInputEnergy=100,
        ADCErrorEnergy=4, ADCErrorMeasurementStatus="measured_complete_executed_converter_sample_population",
        ADCErrorDefinition="mean_squared_actual_input_output_difference",
        ADCErrorDomain="converter_sample_amplitude_squared_not_post_equalization_EVM",
    )
    labels = dict(dashboard.RX_RF_MEASUREMENT_PREVIEW_COLUMNS)
    for key in ("dl_trials", "ul_trials", "ra_receiver_rf"):
        summarize = (dashboard.summarize_procedure_preview_rows if key == "ra_receiver_rf"
                     else dashboard.summarize_data_trial_preview_rows)
        row = summarize(key, [source])[0]
        for field, value in source.items():
            if field != "AGCGain_dB":
                assert row[labels[field]] == value
        assert dashboard.coerce_numeric(row.get(labels["AGCGain_dB"])) is None
        assert "not EVM" in labels["ADCErrorMeanSquare"]
        empty = summarize(key, [{"Slot": 1}])[0]
        assert dashboard.coerce_numeric(empty.get(labels["ADCErrorMeanSquare"])) is None
        assert dashboard.coerce_numeric(empty.get(labels["AGCExecuted"])) is None
