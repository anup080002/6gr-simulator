from __future__ import annotations

import csv
import io
import math
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m
import lls_radio_measurement_plots as radio


def chart(name, sources):
    data = {i: payload for i, payload in enumerate(sources.values(), 1)}
    existing = {path: {"artifact_id": i, "logical_path": path}
                for i, path in enumerate(sources, 1)}
    result = m._specialized_chart_materialization(name, existing, data.__getitem__, 9)
    rows = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    return result, rows


@pytest.mark.parametrize("name", radio.CONTROL_EVM)
def test_control_evm_never_uses_sinr_detection_or_nmse_proxy(name):
    result, _ = chart(name, {"air_interface/csv/control_evm_samples.csv":
        b"SignalName,Slot,PostEqSINR_dB,PilotResidualNMSE_dB,DetectionMetric\nPRACH,5,20,-20,0.9\n"})
    assert result["csv_status"] == "unavailable_exact_reason"


@pytest.mark.parametrize("name,signal", [("PRACH EVM", "PRACH"), ("SSB EVM", "PBCH"), ("CSI-RS EVM", "CSI-RS")])
def test_control_evm_uses_paired_energy_and_peak(name, signal):
    payload = control_pairs(signal)
    result, rows = chart(name, {"air_interface/csv/control_evm_samples.csv": payload})
    assert len(rows) == 1 and int(rows[0]["sample_count"]) == 2
    assert float(rows[0]["rms_evm_pct"]) == pytest.approx(100 * math.sqrt(.82 / 10))
    assert float(rows[0]["peak_evm_pct"]) == pytest.approx(100 * .9 / math.sqrt(5))
    assert b"EVM (%)" in result["img_bytes"]


def control_pairs(signal="PRACH"):
    direction = "UL" if signal == "PRACH" else "DL"
    domain = "equalized_sequence_symbols" if signal == "PRACH" else "equalized_resource_elements"
    header = "SignalName,Direction,UEIndex,Slot,ObservationID,PortIndex,EVMDefinition,AlignmentSource,ReferenceSource,ReferenceReal,ReferenceImag,MeasuredReal,MeasuredImag,SampleIndex,MeasurementDomain\n"
    return (header + f"{signal},{direction},1,5,obs1,0,reference_normalized_paired_symbol_evm,receiver_timing,recorded_tx_symbols,1,0,1.1,0,0,{domain}\n" +
            f"{signal},{direction},1,5,obs1,0,reference_normalized_paired_symbol_evm,receiver_timing,recorded_tx_symbols,3,0,3.9,0,1,{domain}\n").encode()


@pytest.mark.parametrize("change", ["duplicate", "direction", "domain", "reference"])
def test_control_evm_rejects_duplicate_samples_and_invalid_measurement_semantics(change):
    payload = control_pairs()
    if change == "duplicate":
        payload += payload.splitlines(keepends=True)[1]
    elif change == "direction":
        payload = payload.replace(b",UL,", b",DL,")
    elif change == "domain":
        payload = payload.replace(b"equalized_sequence_symbols", b"correlation_trace")
    else:
        payload = payload.replace(b"recorded_tx_symbols", b"same_sample_fitted_symbols")
    result, _ = chart("PRACH EVM", {"air_interface/csv/control_evm_samples.csv": payload})
    assert result["csv_status"] == "unavailable_exact_reason"


@pytest.mark.parametrize("token", ["type1_i2", '{"Size":[2,1],"RealHex":"0102"}', "[1, NaN]", "1.5", "-1"])
def test_pmi_parser_does_not_extract_digits_from_labels_or_metadata(token):
    assert radio._numbers(token, integers=True) == []


def test_pmi_vector_components_are_retained_without_invented_3gpp_index_names():
    payload = b'Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,PMI\nDL,1,7,9,delivered_to_runtime_scheduler,"[2,0,1]"\n'
    result, rows = chart("CSI PMI components timeline", {radio.FEEDBACK: payload})
    assert rows[0]["component_values"] == "[2, 0, 1]"
    assert b"PMI[0]" in result["img_bytes"] and b"PMI[2]" in result["img_bytes"]
    assert b"i11" not in result["img_bytes"]


def test_censored_csi_is_not_plotted_as_delivered():
    payload = b"Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,CQI\nUL,1,15,NaN,right_censored_terminal_horizon,9\n"
    result, rows = chart("CSI CQI timeline", {radio.FEEDBACK: payload})
    assert rows[0]["delivery_status"] == "right_censored_terminal_horizon"
    assert b"UL U1 CQI delivered" not in result["img_bytes"]


@pytest.mark.parametrize("status", ["not_delivered", "pusch_csi_decode_unavailable_not_delivered"])
def test_failed_delivery_cannot_pass_a_substring_match(status):
    payload = f"Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,CQI,PMI\nDL,1,7,9,{status},10,0\n".encode()
    result, _ = chart("CSI CQI timeline", {radio.FEEDBACK: payload})
    assert b"DL U1 CQI delivered" not in result["img_bytes"]
    trial = b"Slot,UEIndex,LinkAdaptationAppliedFeedbackSourceSlot,RequestedPrecoderPMI,AppliedPrecoderPMI\n11,1,7,0,0\n"
    _, rows = chart("reported versus applied PMI", {radio.FEEDBACK: payload, radio.TRIALS[0]: trial})
    assert rows[0]["reported_pmi_token"] == ""


def test_precoder_feedback_requires_explicit_delivered_source_slot_not_value_equality():
    trials = (b"Slot,UEIndex,CSIMeasurementSlot,LinkAdaptationAppliedFeedbackSourceSlot,RequestedPrecoderPMI,AppliedPrecoderPMI\n"
              b"7,1,7,NaN,0,0\n11,1,12,7,0,0\n")
    reports = b"Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,PMI,RI\nDL,1,7,9,delivered_to_runtime_scheduler,0,2\nDL,1,12,14,delivered_to_runtime_scheduler,3,2\n"
    _, rows = chart("reported versus applied PMI", {radio.TRIALS[0]: trials, radio.FEEDBACK: reports})
    assert rows[0]["reported_pmi_token"] == ""  # Slot 7 measurement was not delivered yet.
    assert rows[1]["reported_pmi_token"] == "0"  # Uses explicit source 7, not current CSI slot 12.
    assert rows[1]["reported_ri"] == "2.0"
    assert rows[1]["feedback_binding_authority"].endswith("not_proof_of_precoder_selection_causality")


@pytest.mark.parametrize("direction,path", [("DL", radio.TRIALS[0]), ("UL", radio.TRIALS[1])])
def test_actual_matrix_mismatch_is_exposed_for_both_directions(direction, path):
    header = "Direction,Slot,UEIndex,RequestedPrecoderPMI,AppliedPrecoderPMI,PrecodingNumPorts,PrecodingNumLayers,PrecodingMatrixRows,PrecodingMatrixCols,RequestedPrecoderSHA256,AppliedPrecoderSHA256\n"
    payload = (header + f"{direction},5,1,0,1,4,2,4,1," + "a"*64 + "," + "b"*64 + "\n").encode()
    _, rows = chart("precoder matrix integrity", {path: payload})
    assert rows[0]["requested_applied_pmi_equal"] == "0"
    assert rows[0]["matrix_dimension_match"] == "0"
    assert rows[0]["requested_applied_matrix_hash_equal"] == "0"


def test_matrix_preview_is_bounded_and_does_not_hide_late_failures_or_drop_csv_rows(monkeypatch):
    monkeypatch.setattr(m, "MAX_PREVIEW_ROWS", 2)
    header = "Slot,UEIndex,RequestedPrecoderPMI,AppliedPrecoderPMI,PrecodingNumPorts,PrecodingNumLayers,PrecodingMatrixRows,PrecodingMatrixCols\n"
    payload = (header + "1,1,0,0,2,1,2,1\n2,1,0,0,2,1,2,1\n3,1,0,1,2,1,2,1\n").encode()
    result, rows = chart("precoder matrix integrity", {radio.TRIALS[0]: payload})
    assert len(rows) == 3
    assert b"Showing 2/3 trials" in result["img_bytes"]
    assert b"total mismatch trials=1" in result["img_bytes"]
    assert b">MISMATCH<" in result["img_bytes"]


def test_nmse_requires_an_actual_channel_reference_not_a_pilot_residual():
    result, _ = chart("NMSE vs SNR / SINR", {radio.TRIALS[0]:
        b"Slot,UEIndex,ConfiguredSNR_dB,MeasuredSINR_dB,NMSE_dB,PilotResidualNMSE_dB\n1,1,12,20,-30,-30\n"})
    assert result["csv_status"] == "unavailable_exact_reason"


def test_snr_plot_never_substitutes_configured_snr():
    result, _ = chart("throughput vs SNR", {radio.TRIALS[0]:
        b"Slot,UEIndex,ConfiguredSNR_dB,Goodput_Mbps\n1,1,25,5\n"})
    assert result["csv_status"] == "unavailable_exact_reason"


def test_snr_plot_uses_actual_applied_noise_calibration_and_zero_goodput():
    result, rows = chart("throughput vs SNR", {radio.TRIALS[0]:
        b"Slot,UEIndex,AppliedAWGNSNR_dB,ConfiguredSNR_dB,Goodput_Mbps\n1,1,18,25,0\n"})
    assert rows[0]["x_value"] == "18.0" and rows[0]["metric_value"] == "0.0"
    assert b"Delivered goodput" in result["img_bytes"]


def test_snr_plot_keeps_scheduled_bitrate_distinct_from_missing_goodput():
    result, rows = chart("throughput vs SNR", {radio.TRIALS[0]:
        b"Slot,UEIndex,AppliedSNR_dB,ConfiguredSNR_dB,Throughput_Mbps\n1,1,18,25,5\n"})
    assert rows[0]["AppliedAWGNSNR_dB"] == "" and rows[0]["AppliedSNR_dB"] == "18.0"
    assert rows[0]["Throughput_Mbps"] == "5.0" and rows[0]["Goodput_Mbps"] == ""
    assert rows[0]["metric_source_field"] == "Throughput_Mbps"
    assert b"DL U1 scheduled TB rate" in result["img_bytes"]
    assert b"DL U1 goodput" not in result["img_bytes"]


@pytest.mark.parametrize("field,value", [("ExecutionBackend", "fast_proxy"), ("ApproximationMode", "logistic"), ("E2EAirModel", "lut")])
def test_radio_measurement_rejects_approximation_labels(field, value):
    result, _ = chart("throughput vs SNR", {radio.TRIALS[0]:
        f"Slot,UEIndex,AppliedAWGNSNR_dB,Goodput_Mbps,{field}\n1,1,18,5,{value}\n".encode()})
    assert result["csv_status"] == "unavailable_exact_reason"


def test_pucch_no_crc_does_not_mean_failed_uci_block():
    result, rows = chart("PUCCH BLER vs measured SINR", {"air_interface/csv/pucch_trials.csv":
        b"Slot,UEIndex,Format,PostEqSINR_dB,CRCPass,PUCCHDecodeOk\n5,1,0,20,NaN,1\n"})
    assert rows[0]["metric_value"] == "0" and rows[0]["metric_source_field"] == "uci_block_error"
    assert result["csv_status"] != "unavailable_exact_reason"
