from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as dashboard


def test_time_varying_agc_and_converter_errors_are_not_hidden_or_called_evm():
    source = dict(
        AGCExecuted=1, AGCControlModel="causal_windowed_joint_rms_attack_hold_release",
        AGCDecisionCausal=1, AGCExecutionStatus="executed_time_varying_sample_gain",
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
