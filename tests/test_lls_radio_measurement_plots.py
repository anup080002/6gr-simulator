from __future__ import annotations

import csv
import io
import json
import math
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m
import lls_radio_measurement_plots as radio


def test_csi_reference_sinr_publication_keeps_its_domain_separate_from_pmi_objective():
    # The MATLAB publication helper emits these exact field names. A CSI
    # receiver objective and an L2SM CQI coordinate are not reference SINR.
    row = {
        "ConfiguredSNR_dB": "-10",
        "MeasuredTrialSINR_dB": "-4.75029139663857",
        "MeasuredTrialSINRSource": "received_reference_RE_power",
        "MeasuredTrialSINRValueStatus": "OK",
        "MeasuredTrialSINRValueRole": "received_reference_RE_power_ratio_estimate",
        "MeasuredTrialSINRMeasurementDomain": "csi_rs_port3000_reference_re_received_plane",
        "SINR_dB": "-4.94860378887855",
        "SINRSource": "measured_csi_state_receiver_objective",
        "SINRMeasurementDomain": "selected_PMI_receiver_objective",
        "CQIEffectiveSINR_dB": "-2.06795360388242",
    }
    result = m._measured_sinr_evidence(row)
    assert result["value"] == float(row["MeasuredTrialSINR_dB"])
    assert result["source"] == row["MeasuredTrialSINRSource"]
    assert result["domain"] == row["MeasuredTrialSINRMeasurementDomain"]
    assert result["role"] == row["MeasuredTrialSINRValueRole"]
    missing = dict(row, MeasuredTrialSINR_dB="NaN")
    assert m._measured_sinr_evidence(missing)["value"] is None


def chart(name, sources):
    data = {i: payload for i, payload in enumerate(sources.values(), 1)}
    existing = {path: {"artifact_id": i, "logical_path": path}
                for i, path in enumerate(sources, 1)}
    result = m._specialized_chart_materialization(name, existing, data.__getitem__, 9)
    rows = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    return result, rows


def csv_records(records):
    out = io.StringIO()
    writer = csv.DictWriter(out, list(records[0]))
    writer.writeheader(); writer.writerows(records)
    return out.getvalue().encode()


def test_clipping_plot_uses_both_real_converter_populations_across_all_points():
    sources = {}
    for direction, path in zip(("DL", "UL"), radio.TRIALS):
        records = []
        for point, snr in enumerate((40, 30, 20, 10, 0, -10, -20, -30), 1):
            record = dict(Direction=direction, Slot=43, UEID=1, CellID=1,
                          SweepPointIndex=point, ConfiguredSNR_dB=snr, PeakClippingEvents=0)
            for converter, count, population in (("DAC", 5824, 3932160), ("ADC", 12, 246216)):
                record.update({converter + "ClippingStatus": "measured",
                               converter + "ClippedSampleCount": count,
                               converter + "ClippingSampleCount": population,
                               converter + "ClippingRatio": count/population,
                               converter + "ClippingSource": "actual_converter_mask",
                               converter + "ClippingPopulation": "complex_samples_any_I_or_Q_component_across_all_channels"})
            records.append(record)
        sources[path] = csv_records(records)
    result, rows = chart("clipping event histogram", sources)
    assert result["source_row_count"] == 32
    assert {row["converter"] for row in rows} == {"ADC", "DAC"}
    assert {row["sweep_point_index"] for row in rows} == set(map(str, range(1, 9)))
    assert {int(row["clipped_complex_samples"]) for row in rows} == {12, 5824}
    assert b"DAC" in result["img_bytes"] and b"ADC" in result["img_bytes"]
    corrupted = records[0].copy()
    corrupted["DACClippingRatio"] = 0
    bad, _ = chart("clipping event histogram", {radio.TRIALS[1]: csv_records([corrupted])})
    assert bad["csv_status"] == "unavailable_exact_reason" and "closure" in bad["note"]
    legacy, _ = chart("clipping event histogram", {radio.TRIALS[0]: b"Slot,PeakClippingEvents\n1,0\n"})
    assert legacy["csv_status"] == "unavailable_exact_reason"


def normalized_ssb_power_payload(change="", n_rx=2):
    row = next(csv.DictReader(io.StringIO(ssb_power_payload(n_rx=n_rx).decode())))
    evidence = json.loads(row.pop("SSBWindowPowerMeasurementJSON"))
    powers = evidence.pop("SymbolPowerPerAntenna_W")
    # Values remain relative here, never labelled as watts or dBm.
    evidence["SymbolPowerPerAntenna_UnitOccupiedRE_Es"] = powers
    rssi = _test_vector(evidence.pop("RSSIPerAntenna_dBm"))
    rssi = [v-30 for v in rssi]
    evidence.update(AmplitudeUnit="sqrt_UnitOccupiedRE_Es",
                    RSSIPerAntenna_dB_re_UnitOccupiedRE_Es=rssi)
    row.pop("SSBWindowRSSIPerReceiveAntenna_dBm")
    row.update(PowerReferencePlane="normalized_fixed_esn0_unit_occupied_re_es",
        SSPhysicalMeasurementStatus="available_normalized_fixed_esn0_not_absolute_dbm",
        SSMeasurementSource="noise_debiased_linear_sss_re_power_and_received_reference_disturbance",
        SSBWindowRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es=json.dumps(rssi))
    if change == "energy":
        if n_rx == 1: powers[0] *= 2
        else: powers[0][0] *= 2
    if change == "mirror": row["SSBWindowRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"] = "[123,123]"
    if change == "units": evidence["AmplitudeUnit"] = "sqrt_W"
    if change == "scope": evidence["Scope"] = "full_carrier"
    if change == "bandwidth": evidence["Bandwidth_Hz"] *= 2
    if change == "branch": evidence["NumReceiveAntennas"] += 1
    if change == "boolean": evidence["SymbolPowerPerAntenna_UnitOccupiedRE_Es"][0][0] = True
    if change == "absolute": evidence["RSSIPerAntenna_dBm"] = rssi
    row["SSBWindowRelativePowerMeasurementJSON"] = json.dumps(evidence) if change != "missing" else ""
    return csv_records([row])


def _test_vector(value):
    return value if isinstance(value, list) else [value]


@pytest.mark.parametrize("name,signal", [("PRACH EVM", "PRACH"), ("CSI-RS EVM", "CSI-RS")])
def test_transmitter_evm_cannot_be_mislabeled_as_equalized_receiver_evm(name, signal):
    rows = list(csv.DictReader(io.StringIO(control_pairs(signal).decode())))
    for row in rows:
        row.update(MeasurementDomain="transmitter_resource_elements",
            ReferenceSource="actual_pre_TX_RF_waveform_on_declared_resource_clock",
            AlignmentSource="frozen_transmitter_OFDM_clock_no_gain_phase_or_timing_fit",
            PortRole="physical_TX_antenna_not_equalized_RX_stream")
    result, output = chart(name, {"air_interface/csv/control_evm_samples.csv": csv_records(rows)})
    assert result["csv_status"] == "specialized_runtime_radio_measurement_dataset"
    assert output[0]["measurement_domain"] == "transmitter_resource_elements"
    assert output[0]["standardized_modulation_evm_qualified"] == "False"
    assert output[0]["measurement_claim"] == "raw_gain_inclusive_TX_pair_error_not_standardized_modulation_EVM"
    assert output[0]["amplitude_reference_treatment"] == "pre_TX_RF_amplitude_no_PA_backoff_or_gain_removal"
    assert b"TX RF" in result["img_bytes"]
    rows[0]["ReferenceSource"] = "receiver_pilot_fit"
    bad, _ = chart(name, {"air_interface/csv/control_evm_samples.csv": csv_records(rows)})
    assert bad["csv_status"] == "unavailable_exact_reason"


@pytest.mark.parametrize("n_rx", [1, 2, 4])
def test_normalized_ssb_rssi_reconciles_retained_linear_power(n_rx):
    result, rows = chart(radio.SSB_POWER_CHART, {"air_interface/csv/pbch_trials.csv": normalized_ssb_power_payload(n_rx=n_rx)})
    assert result["csv_status"] == "specialized_runtime_radio_measurement_dataset"
    assert len(rows) == n_rx
    for row in rows:
        p = json.loads(row["symbol_powers_unit_occupied_re_es"])
        assert float(row["rssi_db_re_unit_occupied_re_es"]) == pytest.approx(10*math.log10(sum(p)/4))


@pytest.mark.parametrize("change", ["energy", "mirror", "units", "scope", "bandwidth", "branch", "boolean", "absolute", "missing"])
def test_normalized_ssb_rssi_rejects_corrupt_evidence(change):
    result, _ = chart(radio.SSB_POWER_CHART, {"air_interface/csv/pbch_trials.csv": normalized_ssb_power_payload(change)})
    assert result["csv_status"] == "unavailable_exact_reason"


def test_ssb_absolute_and_normalized_power_cannot_share_a_numeric_axis():
    absolute = next(csv.DictReader(io.StringIO(ssb_power_payload().decode())))
    relative = next(csv.DictReader(io.StringIO(normalized_ssb_power_payload().decode())))
    fields = set(absolute) | set(relative)
    records = [{key: row.get(key, "") for key in fields} for row in (absolute, relative)]
    records[0].update(SweepPointIndex=1, ConfiguredSNR_dB=40)
    records[1].update(SweepPointIndex=2, ConfiguredSNR_dB=30)
    result, rows = chart(radio.SSB_POWER_CHART, {"air_interface/csv/pbch_trials.csv": csv_records(records)})
    assert result["csv_status"] == "unavailable_exact_reason"
    assert "cannot share one numeric measurement axis" in rows[0]["reason"]


@pytest.mark.parametrize("family", ["PRACH", "PBCH", "CSI-RS", "SSB_absolute", "SSB_normalized", "DL", "UL"])
def test_repeated_identities_across_eight_points_remain_joint_and_separate(family, monkeypatch):
    if family in {"PRACH", "PBCH", "CSI-RS"}:
        payload = control_pairs(family)
        path = "air_interface/csv/control_evm_samples.csv"
        name = {"PRACH": "PRACH EVM", "PBCH": "SSB EVM", "CSI-RS": "CSI-RS EVM"}[family]
        per_point = 1
    elif family.startswith("SSB"):
        payload = ssb_power_payload() if family.endswith("absolute") else normalized_ssb_power_payload()
        path, name, per_point = "air_interface/csv/pbch_trials.csv", radio.SSB_POWER_CHART, 2
    else:
        payload = normalized_data_carrier_payload(direction=family)
        path = radio.TRIALS[0 if family == "DL" else 1]
        name, per_point = ("PDSCH" if family == "DL" else "PUSCH") + "-window carrier RSSI timeline", 2
    base = list(csv.DictReader(io.StringIO(payload.decode())))
    values = [40,30,20,10,0,-10,-20,-30]
    joined = [dict(row, SweepPointIndex=p, ConfiguredSNR_dB=snr) for p,snr in enumerate(values,1) for row in base]
    captured = []
    original = m._render_multi_series_svg
    def render(*args, **kwargs):
        captured.extend(args[2]); return original(*args, **kwargs)
    monkeypatch.setattr(m, "_render_multi_series_svg", render)
    result, rows = chart(name, {path: csv_records(joined)})
    assert result["csv_status"] == "specialized_runtime_radio_measurement_dataset"
    assert len(rows) == 8*per_point
    assert {r["sweep_point_index"] for r in rows} == {str(i) for i in range(1,9)}
    assert {float(r["configured_snr_db"]) for r in rows} == set(values)
    assert all("point=" in series["name"] for series in captured)
    assert len(captured) == 16  # RMS/peak or two independent receive branches.
    duplicate, _ = chart(name, {path: csv_records(joined+[joined[0]])})
    assert duplicate["csv_status"] == "unavailable_exact_reason"


def test_control_evm_keeps_same_slot_beam_observation_identities(monkeypatch):
    base = list(csv.DictReader(io.StringIO(control_pairs("PBCH").decode())))
    rows = [dict(row, ObservationID=f"received_SSB_{beam}",
                 SweepPointIndex=point, ConfiguredSNR_dB=snr)
            for point, snr in enumerate([40, 30, 20, 10, 0, -10, -20, -30], 1)
            for beam in range(4) for row in base]
    captured = []
    original = m._render_multi_series_svg
    def render(*args, **kwargs):
        captured.extend(args[2]); return original(*args, **kwargs)
    monkeypatch.setattr(m, "_render_multi_series_svg", render)
    result, output = chart("SSB EVM", {"air_interface/csv/ssb_evm_samples.csv": csv_records(rows)})
    assert result["csv_status"] == "specialized_runtime_radio_measurement_dataset"
    assert len(output) == 32
    assert len(captured) == 64  # RMS/peak, four beams, eight operating points.
    assert len({s["name"] for s in captured}) == 64
    assert all("observation=received_SSB_" in s["name"] for s in captured)


def test_radio_plot_preserves_all_samples_and_full_measurement_labels():
    # Go beyond the old 180-point preview and eight-series legend defaults.
    series = {f"DL UE 1 point {i} port 3000 reference RE power ratio independent measurement":
              [[j, i + j / 1000] for j in range(241)] for i in range(9)}
    records = [{"point": i, "slot": p[0], "value": p[1]}
               for i, points in enumerate(series.values()) for p in points]
    note = ("Measured reference power is distinct from the selected PMI receiver objective. " * 3 +
            "No calibrated absolute dBm measurement is claimed.")
    result = radio._finish(m, "CSI SINR timeline", 9, records, series,
                           "Slot", "SINR (dB)", note, [radio.CSI_TRIALS])
    rows = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert len(rows) == 9 * 241
    root = ET.fromstring(result["img_bytes"])
    ns = {"svg": "http://www.w3.org/2000/svg"}
    # Count only data markers; legend markers live outside the plot panel.
    markers = [e for e in root.findall("svg:circle", ns) if float(e.attrib["cx"]) < 900]
    markers += [e for e in root.findall("svg:rect", ns)
                if e.attrib.get("width") == "6" and float(e.attrib["x"]) < 900]
    assert len(markers) == len(rows)
    legends = root.findall("svg:g", ns)
    assert len(legends) == len(series)
    for group, label in zip(legends, series):
        assert " ".join(e.text for e in group.findall("svg:text", ns)) == label
        assert all(float(e.attrib["y"]) < float(root.attrib["height"])
                   for e in group.findall("svg:text", ns))
    subtitle = [e for e in root.findall("svg:text", ns)
                if e.attrib.get("x") == "40" and e.attrib.get("font-size") == "14"]
    assert " ".join(e.text for e in subtitle) == note
    plot = next(e for e in root.findall("svg:rect", ns) if e.attrib.get("width") == "820")
    assert max(float(e.attrib["y"]) for e in subtitle) < float(plot.attrib["y"])


def data_carrier_power_payload(change="", direction="UL", n_rx=2, n_symbols=3):
    powers = [[1e-9*(symbol+1)*(branch+1) for branch in range(n_rx)] for symbol in range(n_symbols)]
    rssis = [10*math.log10(sum(p[b] for p in powers)/n_symbols)+30 for b in range(n_rx)]
    e = {"ContractVersion": "received_data_carrier_power/v1",
        "Scope": "received_data_symbol_window_full_carrier_not_ue_NR_RSSI_report",
        "PowerReferencePlane": "receiver_antenna_connector_pre_composite_front_end",
        "Source": "actual_physical_received_IQ_OFDM_carrier_energy", "InputAmplitudeUnit": "sqrt_mW",
        "GridAmplitudeUnit": "sqrt_W", "FrequencyAlignment": "nominal_carrier_no_oracle_CFO_correction",
        "CPIncluded": False, "Direction": direction, "RNTI": 1, "GrantContextId": "received-grant-1",
        "DataAbsoluteSlot": 9, "ObservationStartSample": 900, "ObservationEndSampleExclusive": 1000,
        "ReceivedSymbolStartSample": 920, "ReceivedSymbolEndSampleExclusive": 990,
        "NumRB": 25, "SubcarrierSpacing_kHz": 15, "Bandwidth_Hz": 4500000,
        "NumReceiveAntennas": n_rx, "SampleRateHz": 7680000, "Nfft": 512,
        "SymbolIndices0Based": list(range(2, 2+n_symbols)), "SymbolAllocation": [2, n_symbols],
        "RSSIPerAntenna_dBm": rssis, "SymbolPowerPerAntenna_W": powers,
        "PhysicalObservationSHA256": "a"*64}
    if change == "closure": powers[0][0] *= 2
    if change == "plane": e["PowerReferencePlane"] = "normalized_receiver_grid"
    if change == "scope": e["Scope"] = "UE_NR_RSSI"
    if change == "bandwidth": e["Bandwidth_Hz"] *= 2
    if change == "symbols": e["SymbolIndices0Based"] = [2, 4, 5]
    if change == "branch": e["NumReceiveAntennas"] += 1
    if change == "clock": e["ReceivedSymbolEndSampleExclusive"] = 1001
    if change == "grant": e["GrantContextId"] = ""
    if change == "slot": e["DataAbsoluteSlot"] = 8
    if change == "units": e["InputAmplitudeUnit"] = "normalized"
    if change == "hash": e["PhysicalObservationSHA256"] = ""
    if n_rx == 1: e["SymbolPowerPerAntenna_W"] = [p[0] for p in powers]
    if n_symbols == 1:
        e["SymbolIndices0Based"] = 2
        e["SymbolPowerPerAntenna_W"] = powers[0] if n_rx > 1 else powers[0][0]
    if change == "boolean_energy": e["SymbolPowerPerAntenna_W"] = True
    row = {"Direction": direction, "RNTI": 1, "UEIndex": 1, "CellID": 1, "Slot": 10,
        "AllocationCarrierPowerMeasurementJSON": json.dumps(e),
        "AllocationCarrierRSSIPerReceiveAntenna_dBm": json.dumps(rssis)}
    if change == "proxy": row["Source"] = "fast_proxy"
    if change == "mirror": row["AllocationCarrierRSSIPerReceiveAntenna_dBm"] = "[0, 0]"
    output = io.StringIO(); writer = csv.DictWriter(output, list(row))
    writer.writeheader(); writer.writerow(row)
    if change == "duplicate": writer.writerow(row)
    return output.getvalue().encode()


@pytest.mark.parametrize("direction,path,name", [("UL", radio.TRIALS[1], "PUSCH-window carrier RSSI timeline"),
                                                ("DL", radio.TRIALS[0], "PDSCH-window carrier RSSI timeline")])
@pytest.mark.parametrize("n_rx", [1, 2, 4])
@pytest.mark.parametrize("n_symbols", [1, 3])
def test_data_carrier_rssi_keeps_measured_window_and_branches(direction, path, name, n_rx, n_symbols):
    result, rows = chart(name, {path: data_carrier_power_payload(direction=direction, n_rx=n_rx, n_symbols=n_symbols)})
    assert result["csv_status"] == "specialized_runtime_radio_measurement_dataset"
    assert len(rows) == n_rx and all(row["grant_context_id"] == "received-grant-1" for row in rows)
    assert all(row["measurement_scope"].endswith("not_ue_NR_RSSI_report") for row in rows)
    png = m._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml", source_logical_path="test://power.svg")
    assert png.startswith(b"\x89PNG\r\n\x1a\n")


@pytest.mark.parametrize("change", ["closure", "plane", "scope", "bandwidth", "symbols", "branch", "clock",
                                    "grant", "slot", "units", "hash", "proxy", "mirror", "duplicate"])
def test_data_carrier_rssi_rejects_corrupt_or_mislabeled_measurements(change):
    result, _ = chart("PUSCH-window carrier RSSI timeline", {radio.TRIALS[1]: data_carrier_power_payload(change)})
    assert result["csv_status"] == "unavailable_exact_reason"


def test_data_carrier_rssi_rejects_boolean_scalar_energy():
    result, _ = chart("PUSCH-window carrier RSSI timeline", {radio.TRIALS[1]:
        data_carrier_power_payload("boolean_energy", n_rx=1, n_symbols=1)})
    assert result["csv_status"] == "unavailable_exact_reason"


def normalized_data_carrier_payload(change="", direction="UL"):
    row = next(csv.DictReader(io.StringIO(data_carrier_power_payload(direction=direction).decode())))
    e = json.loads(row["AllocationCarrierPowerMeasurementJSON"])
    factor = e["Nfft"]**2*1000
    e.update(ContractVersion="received_data_carrier_power/v2",
             PowerReferencePlane="normalized_fixed_esn0_unit_occupied_re_es",
             Source="actual_normalized_received_IQ_OFDM_carrier_energy",
             InputAmplitudeUnit="normalized_OFDM_waveform_unit_occupied_re_es",
             GridAmplitudeUnit="sqrt_UnitOccupiedRE_Es")
    e["SymbolPowerPerAntenna_UnitOccupiedRE_Es"] = [[p*factor for p in s] for s in e.pop("SymbolPowerPerAntenna_W")]
    e["RSSIPerAntenna_dB_re_UnitOccupiedRE_Es"] = [p+20*math.log10(e["Nfft"]) for p in e.pop("RSSIPerAntenna_dBm")]
    row["AllocationCarrierRSSIPerReceiveAntenna_dBm"] = ""
    row["AllocationCarrierRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"] = json.dumps(e["RSSIPerAntenna_dB_re_UnitOccupiedRE_Es"])
    row["TransmitPowerReferencePlane"] = "normalized_fixed_esn0_unit_occupied_re_es"
    if change == "physical_claim": e["RSSIPerAntenna_dBm"] = [0, 0]
    if change == "wrong_units": e["GridAmplitudeUnit"] = "sqrt_W"
    if change == "energy": e["SymbolPowerPerAntenna_UnitOccupiedRE_Es"][0][0] *= 2
    if change == "mirror": row["AllocationCarrierRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"] = "[0, 0]"
    if change == "physical_tx": row["TransmitPowerReferencePlane"] = "receiver_antenna_connector_pre_composite_front_end"
    row["AllocationCarrierPowerMeasurementJSON"] = json.dumps(e)
    output = io.StringIO(); writer = csv.DictWriter(output, list(row)); writer.writeheader(); writer.writerow(row)
    return output.getvalue().encode()


@pytest.mark.parametrize("direction,path,name", [("UL", radio.TRIALS[1], "PUSCH-window carrier RSSI timeline"),
                                                ("DL", radio.TRIALS[0], "PDSCH-window carrier RSSI timeline")])
def test_normalized_carrier_power_has_relative_csv_and_png_units(direction, path, name):
    result, rows = chart(name, {path: normalized_data_carrier_payload(direction=direction)})
    assert len(rows) == 2 and "rssi_dbm" not in rows[0] and "symbol_powers_w" not in rows[0]
    for row in rows:
        powers = json.loads(row["symbol_powers_unit_occupied_re_es"])
        assert math.isclose(float(row["rssi_db_re_unit_occupied_re_es"]), 10*math.log10(sum(powers)/len(powers)), abs_tol=1e-10)
    assert b"Carrier-window RSSI (dB re unit occupied-RE Es)" in result["img_bytes"]
    assert b"Carrier-window RSSI (dBm)" not in result["img_bytes"]
    assert m._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml").startswith(b"\x89PNG\r\n\x1a\n")


@pytest.mark.parametrize("change", ["physical_claim", "wrong_units", "energy", "mirror", "physical_tx"])
def test_normalized_carrier_power_rejects_inconsistent_units_and_operands(change):
    result, _ = chart("PUSCH-window carrier RSSI timeline", {radio.TRIALS[1]: normalized_data_carrier_payload(change)})
    assert result["csv_status"] == "unavailable_exact_reason"


def test_old_physical_carrier_metadata_cannot_qualify_a_normalized_trial():
    row = next(csv.DictReader(io.StringIO(data_carrier_power_payload().decode())))
    row["TransmitPowerReferencePlane"] = "normalized_fixed_esn0_unit_occupied_re_es"
    output = io.StringIO(); writer = csv.DictWriter(output, list(row)); writer.writeheader(); writer.writerow(row)
    result, _ = chart("PUSCH-window carrier RSSI timeline", {radio.TRIALS[1]: output.getvalue().encode()})
    assert result["csv_status"] == "unavailable_exact_reason"


def ssb_power_payload(change="", n_rx=2):
    powers = [[1e-8*(symbol+1)*(branch+1) for branch in range(n_rx)] for symbol in range(4)]
    rssis = [10*math.log10(sum(p[b] for p in powers)/4)+30 for b in range(n_rx)]
    evidence = {"Available": True, "Source": "nrSSBMeasurements_actual_antenna_plane_ssb_grid",
        "Scope": "ssb_240_subcarrier_four_symbol_window_not_full_carrier_RSSI",
        "AmplitudeUnit": "sqrt_W", "CPIncluded": False, "NumRB": 20, "NumSubcarriers": 240,
        "SymbolIndicesWithinSSB0Based": [0, 1, 2, 3], "NumReceiveAntennas": n_rx,
        "SubcarrierSpacing_kHz": 15, "Bandwidth_Hz": 3600000,
        "RSSIPerAntenna_dBm": rssis if n_rx > 1 else rssis[0],
        "SymbolPowerPerAntenna_W": powers if n_rx > 1 else [p[0] for p in powers]}
    record = {"Direction": "DL", "UEIndex": 1, "CellID": 1, "Slot": 1, "SSBIndex": 3,
        "ObservationStartSample": 0, "ObservationEndSampleExclusive": 38400, "ObservationSampleRateHz": 7680000,
        "PowerReferencePlane": "receiver_antenna_connector_pre_composite_front_end",
        "SSBWindowRSSIPerReceiveAntenna_dBm": json.dumps(rssis)}
    if change == "plane": record["PowerReferencePlane"] = "post_agc"
    if change == "closure": powers[0][0] *= 2
    if change == "mirror": record["SSBWindowRSSIPerReceiveAntenna_dBm"] = "[0, 0]"
    if change == "bandwidth": evidence["Bandwidth_Hz"] *= 2
    if change == "symbols": evidence["SymbolIndicesWithinSSB0Based"] = [0, 1, 2]
    if change == "branches": evidence["NumReceiveAntennas"] += 1
    if change == "scope": evidence["Scope"] = "full_carrier_RSSI"
    if change == "proxy": record["Source"] = "fast_proxy"
    record["SSBWindowPowerMeasurementJSON"] = json.dumps(evidence)
    stream = io.StringIO(); writer = csv.DictWriter(stream, list(record))
    writer.writeheader(); writer.writerow(record)
    if change == "duplicate": writer.writerow(record)
    return stream.getvalue().encode()


@pytest.mark.parametrize("n_rx", [1, 2, 4])
def test_ssb_rssi_has_real_window_each_branch_and_png(n_rx):
    result, rows = chart(radio.SSB_POWER_CHART, {"air_interface/csv/pbch_trials.csv": ssb_power_payload(n_rx=n_rx)})
    assert result["csv_status"] == "specialized_runtime_radio_measurement_dataset"
    assert len(rows) == n_rx and all(r["ssb_index_0based"] == "3" for r in rows)
    assert all(r["measurement_scope"].endswith("not_full_carrier_RSSI") for r in rows)
    png = m._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml", source_logical_path="test://ssb.svg")
    assert png.startswith(b"\x89PNG\r\n\x1a\n")


@pytest.mark.parametrize("change", ["plane", "closure", "mirror", "bandwidth", "symbols", "branches", "scope", "proxy", "duplicate"])
def test_ssb_rssi_rejects_incomplete_inconsistent_or_proxy_evidence(change):
    result, _ = chart(radio.SSB_POWER_CHART, {"air_interface/csv/pbch_trials.csv": ssb_power_payload(change)})
    assert result["csv_status"] == "unavailable_exact_reason"


def csi_power_payload(change=""):
    resource = {"ResourceID": 3, "NumReceiveAntennas": 2, "NumRB": 24,
        "FirstPRB0Based": 6, "SubcarrierSpacing_kHz": 30, "Bandwidth_Hz": 8640000,
        "SymbolIndices0Based": [6, 7], "RSRPPerAntenna_dBm": [-80, -85],
        "RSSIPerAntenna_dBm": [-50, -53],
        "RSRQPerAntenna_dB": [10*math.log10(24)-30, 10*math.log10(24)-32],
        "Available": True, "Source": "nrCSIRSMeasurements_actual_physical_grid"}
    record = {"Direction": "DL", "UEIndex": 1, "CellID": 1, "Slot": 5,
        "PhysicalMeasurementStatus": "available", "PowerReferencePlane": "receiver_antenna_connector_pre_composite_front_end",
        "MeasurementSource": "nrCSIRSMeasurements_runtime_pre_front_end_antenna_plane_grid"}
    if change == "plane": record["PowerReferencePlane"] = "post_agc_normalized_grid"
    if change == "closure": resource["RSRQPerAntenna_dB"][0] += 3
    if change == "bandwidth": resource["Bandwidth_Hz"] *= 2
    if change == "branches": resource["RSSIPerAntenna_dBm"] = [-50]
    if change == "missing": resource["SymbolIndices0Based"] = []
    if change == "proxy": record["Source"] = "fast_proxy"
    if change == "absent": record["PhysicalMeasurementStatus"] = "unavailable"
    record["MeasurementPhysicalResourcesJSON"] = json.dumps([resource])
    stream = io.StringIO()
    writer = csv.DictWriter(stream, list(record)); writer.writeheader(); writer.writerow(record)
    if change == "duplicate": writer.writerow(record)
    return stream.getvalue().encode()


@pytest.mark.parametrize("name", radio.CSI_POWER_FIELDS)
def test_csi_rssi_and_rsrq_retain_each_branch_and_actual_scope(name):
    result, rows = chart(name, {"air_interface/csv/csi_rs_trials.csv": csi_power_payload()})
    assert result["csv_status"] == "specialized_runtime_radio_measurement_dataset"
    assert len(rows) == 2 and [r["receive_antenna_index_1based"] for r in rows] == ["1", "2"]
    assert all(r["resource_id"] == "3" and r["bandwidth_hz"] == "8640000" for r in rows)
    assert all(r["symbol_indices_0based"] == "[6, 7]" for r in rows)
    png = m._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml", source_logical_path="test://actual_schema.svg")
    assert png.startswith(b"\x89PNG\r\n\x1a\n")


@pytest.mark.parametrize("change", ["plane", "closure", "bandwidth", "branches", "missing", "proxy", "absent", "duplicate"])
def test_csi_physical_power_rejects_inconsistent_or_absent_evidence(change):
    result, _ = chart("CSI-RS RSSI timeline", {"air_interface/csv/csi_rs_trials.csv": csi_power_payload(change)})
    assert result["csv_status"] == "unavailable_exact_reason"


@pytest.mark.parametrize("normalized", [False, True])
def test_csi_power_keeps_repeated_slots_from_all_sweep_points(normalized, monkeypatch):
    base = next(csv.DictReader(io.StringIO(csi_power_payload().decode())))
    if normalized:
        base.pop("MeasurementPhysicalResourcesJSON")
        base.update(PhysicalMeasurementStatus="available_normalized_fixed_esn0_not_absolute_dbm",
            PowerReferencePlane="normalized_fixed_esn0_unit_occupied_re_es",
            MeasurementSource="actual_csirs_re_measurement_relative_to_unit_occupied_re_es",
            MeasurementNumRB=24, MeasurementFirstPRB0Based=6, MeasurementSubcarrierSpacing_kHz=30,
            MeasurementBandwidth_Hz=8640000, MeasurementSymbolIndices0Based="[6,7]",
            MeasurementRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es="[-10,-15]",
            MeasurementRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es="[20,17]",
            MeasurementRSRQPerReceiveAntenna_dB=json.dumps([10*math.log10(24)-30, 10*math.log10(24)-32]))
    points = [dict(base, SweepPointIndex=i, ConfiguredSNR_dB=snr)
              for i, snr in enumerate([40,30,20,10,0,-10,-20,-30], 1)]
    data = io.StringIO()
    writer = csv.DictWriter(data, list(points[0])); writer.writeheader(); writer.writerows(points)
    captured = []
    original = m._render_multi_series_svg
    def retain_series(title, subtitle, series, *args, **kwargs):
        captured.extend(series)
        return original(title, subtitle, series, *args, **kwargs)
    monkeypatch.setattr(m, "_render_multi_series_svg", retain_series)
    result, rows = chart("CSI-RS RSRP timeline", {radio.CSI_TRIALS: data.getvalue().encode()})
    assert result["csv_status"] == "specialized_runtime_radio_measurement_dataset"
    assert len(rows) == 16 and len(captured) == 16
    assert {r["sweep_point_index"] for r in rows} == {str(i) for i in range(1,9)}
    assert {float(r["metric_value"]) for r in rows} == ({-10,-15} if normalized else {-80,-85})
    unit = b"RSRP (dB re unit occupied-RE Es)" if normalized else b"RSRP (dBm)"
    assert unit in result["img_bytes"]
    if normalized:
        assert "rsrp_dbm" not in rows[0] and b"RSRP (dBm)" not in result["img_bytes"]


@pytest.mark.parametrize("normalized", [False, True])
def test_csi_power_uses_all_eight_core_resource_records_not_only_selected_vector(normalized):
    base = next(csv.DictReader(io.StringIO(csi_power_payload().decode())))
    original = json.loads(base["MeasurementPhysicalResourcesJSON"])[0]
    resources = []
    for rid in range(8):
        resource = dict(original, ResourceID=rid)
        resource["Source"] = "received_port3000_linear_RSRP_and_nrCSIRSMeasurements_RSSI"
        if normalized:
            resource.update(Source="received_port3000_linear_RSRP_and_native_RSSI_normalized_unit_RE_grid",
                            PowerUnit="relative_to_unit_occupied_RE_Es")
            resource["RSRPPerAntenna_dB_re_UnitOccupiedRE_Es"] = [-10-rid, -15-rid]
            resource["RSSIPerAntenna_dB_re_UnitOccupiedRE_Es"] = [20, 17]
            resource["RSRPPerAntenna_dBm"] = [None, None]
            resource["RSSIPerAntenna_dBm"] = [None, None]
        else:
            resource["RSRPPerAntenna_dBm"] = [-80-rid, -85-rid]
        resource["RSRQPerAntenna_dB"] = [10*math.log10(24)-30-rid, 10*math.log10(24)-32-rid]
        resources.append(resource)
    if normalized:
        base.update(PhysicalMeasurementStatus="available_normalized_fixed_esn0_not_absolute_dbm",
            PowerReferencePlane="normalized_fixed_esn0_unit_occupied_re_es",
            MeasurementSource="actual_csirs_re_measurement_relative_to_unit_occupied_re_es",
            MeasurementRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es="[99,99]")
    # Deliberately poisoned selected-vector metadata must not replace the
    # actual complete per-resource measurements in the core JSON archive.
    base["MeasurementPhysicalResourcesJSON"] = json.dumps(resources)
    output = io.StringIO(); writer = csv.DictWriter(output, list(base)); writer.writeheader(); writer.writerow(base)
    for name in radio.CSI_POWER_FIELDS:
        result, rows = chart(name, {radio.CSI_TRIALS: output.getvalue().encode()})
        assert result["csv_status"] == "specialized_runtime_radio_measurement_dataset"
        assert len(rows) == 16 and {r["resource_id"] for r in rows} == {str(i) for i in range(8)}
        assert all(r["measurement_scope"] == "all_retained_resource_records" for r in rows)
        if name == "CSI-RS RSRP timeline":
            assert float(rows[-1]["metric_value"]) == (-22 if normalized else -92)
        if name == "CSI-RS RSRP by resource":
            assert {int(r["plot_x_value"]) for r in rows} == set(range(8))
            assert all(r["plot_x_semantics"] == "configured_resource_id_not_angle" for r in rows)


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


def test_trs_post_correction_frequency_retains_its_measurement_domain():
    raw = dict(Direction="DL", Slot=47, UEIndex=1, ConfiguredSNR_dB=40,
               ResidualCFOEstimateAvailable=True, ResidualCFO_EstimatedPostCorrection_Hz=7.25,
               ResidualCFOEstimateRole="received_common_frequency_not_separated_oscillator",
               ResidualCFOEstimateSource="trs_reference_phase_slope_frequency_estimator_after_receiver_frequency_processing",
               ResidualFrequencyUsesDifferentObservable=True, CFOCorrectionApplied=True,
               CFOCorrectionApplied_Hz=400, TRSResidualFrequencyEvidenceJSON='[{"FromSlot":46}]')
    result, rows = chart(radio.TRS_FREQUENCY_CHART, {radio.TRS_TRIALS: csv_records([raw])})
    assert result["source_row_count"] == 1
    assert float(rows[0]["post_correction_common_frequency_hz"]) == 7.25
    raw["ResidualFrequencyUsesDifferentObservable"] = False
    bad, _ = chart(radio.TRS_FREQUENCY_CHART, {radio.TRS_TRIALS: csv_records([raw])})
    assert bad["csv_status"] == "unavailable_exact_reason"


@pytest.mark.parametrize("signal", ["TRS", "SRS"])
def test_received_pilot_evm_preserves_plane_and_rejects_fitted_reference(signal):
    records = list(csv.DictReader(io.StringIO(control_pairs(signal).decode())))
    for row in records:
        row.update(MeasurementDomain="received_resource_elements",
                   ReferencePlane="test_received_clock",
                   ReferenceSource="same_executed_desired_link_received_pilot_grid",
                   AlignmentSource="recorded_receiver_timing_and_frequency_clock_no_fit",
                   PortRole="physical_RX_branch_not_equalized_layer")
    name = f"{signal} received-pilot EVM"
    source = radio.CONTROL_EVM[name][1]
    result, rows = chart(name, {source: csv_records(records)})
    assert result["source_row_count"] == 1
    assert float(rows[0]["rms_evm_pct"]) == pytest.approx(100*math.sqrt(.82/10))
    assert rows[0]["measurement_claim"] == "received_pilot_grid_pair_error_not_equalized_or_RF_conformance"
    assert rows[0]["direction"] == ("UL" if signal == "SRS" else "DL")
    for flag in ("GainOrPhaseFitted", "ReceiverUsesScoringReference"):
        altered = [dict(r, **{flag: "true"}) for r in records]
        bad, _ = chart(name, {source: csv_records(altered)})
        assert bad["csv_status"] == "unavailable_exact_reason"
    records[0]["ReferenceSource"] = "same_sample_fitted_reference"
    bad, _ = chart(name, {source: csv_records(records)})
    assert bad["csv_status"] == "unavailable_exact_reason"


def control_pairs(signal="PRACH"):
    direction = "UL" if signal in {"PRACH", "SRS"} else "DL"
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
    assert b"CQI delivered:" not in result["img_bytes"]


def test_csi_sinr_retains_selected_pmi_objective_domain():
    payload = (b"Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,SINR_dB,SINRSource,SINRValueRole\n"
               b"DL,1,32,35,delivered_to_runtime_scheduler,18.7,measured_csi_state_receiver_objective,measured_csi_receiver_objective_scheduling_input\n")
    result, rows = chart("CSI SINR timeline", {radio.FEEDBACK: payload})
    assert rows[0]["sinr_measurement_domain"] == "csi_rs_selected_pmi_receiver_objective"
    assert rows[0]["sinr_source"] == "measured_csi_state_receiver_objective"
    assert rows[0]["sinr_value_role"] == "measured_csi_receiver_objective_scheduling_input"
    assert b"CSI SINR (dB; distinct measurement domains)" in result["img_bytes"]


def test_csi_measurement_reference_and_delivery_are_not_conflated(monkeypatch):
    feedback = (b"Direction,UEIndex,SourceSlot,CSIReferenceSlot,SourceSlotAuthority,DeliveredSlot,DeliveryStatus,SINR_dB,SINRSource\n"
                b"DL,1,34,34,configured_CSI_reference_resource_not_UE_measurement_slot,39,delivered_to_runtime_scheduler,NaN,not_reported_in_CSI_payload\n")
    observations = (b"Direction,UEIndex,Slot,CSIMeasurementSlot,ObservationDeliverySlot,SINR_dB,SINRSource,SINRMeasurementDomain,ReferenceMeasuredSINR_dB,ReferenceMeasuredSINRSource,ReferenceMeasuredSINRDomain,CSIMeasurementID\n"
                    b"DL,1,32,32,33,22.2,measured_csi_state_receiver_objective,csi_rs_selected_pmi_receiver_objective,19.8,nrChannelEstimate_port3000_reference_RE_power_per_receive_branch,csi_rs_port3000_reference_re_received_plane,measurement-32\n")
    captured = []
    original = m._render_multi_series_svg
    def retain_series(title, subtitle, series, *args, **kwargs):
        captured.extend(series)
        return original(title, subtitle, series, *args, **kwargs)
    monkeypatch.setattr(m, "_render_multi_series_svg", retain_series)
    result, rows = chart("CSI SINR timeline", {radio.FEEDBACK: feedback, radio.CSI_TRIALS: observations})
    assert len(rows) == 3
    assert rows[0]["component_values"] == "[]"
    assert rows[0]["measurement_slot"] == ""
    assert rows[0]["csi_reference_slot"] == "34.0" and rows[0]["delivered_slot"] == "39.0"
    assert rows[0]["value_status"] == "unavailable_in_source"
    for row in rows[1:]:
        assert row["measurement_slot"] == "32.0" and row["measurement_available_slot"] == "33.0"
        assert row["delivered_slot"] == "" and row["report_identity"] == ""
        assert row["delivery_status"] == "not_a_received_feedback_payload"
        assert row["measurement_identity"] == "measurement-32"
    assert rows[1]["sinr_measurement_domain"] != rows[2]["sinr_measurement_domain"]
    assert len(captured) == 2
    assert sorted(s["points"] for s in captured) == [[[32.0, 19.8]], [[32.0, 22.2]]]
    assert radio.CSI_TRIALS in result["source_table_path"]


def test_named_pmi_fields_are_preserved_not_decomposed_from_packed_index():
    payload = (b"Direction,UEIndex,SourceSlot,CSIReferenceSlot,DeliveredSlot,DeliveryStatus,PMI,PMI_I11,PMI_I12,PMI_I13,PMI_I2\n"
               b"DL,1,34,34,39,delivered_to_runtime_scheduler,30,7,0,1,0\n")
    result, rows = chart("CSI PMI components timeline", {radio.FEEDBACK: payload})
    assert rows[0]["reported_value_token"] == "30"
    assert json.loads(rows[0]["component_fields"]) == ["PMI_I11", "PMI_I12", "PMI_I13", "PMI_I2"]
    assert json.loads(rows[0]["component_values"]) == [7, 0, 1, 0]
    assert rows[0]["timing_role"] == "configured reference"
    assert rows[0]["measurement_slot"] == ""
    assert b"PMI_I11" in result["img_bytes"]


def test_csi_producer_audit_cannot_supply_missing_received_sinr():
    payload = (b"Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,SINR_dB,UEReferenceRecordJSON\n"
               b'DL,1,34,39,delivered_to_runtime_scheduler,NaN,"{""SINR_dB"":99}"\n')
    result, _ = chart("CSI SINR timeline", {radio.FEEDBACK: payload})
    assert result["csv_status"] == "unavailable_exact_reason"


def test_csi_observation_series_keep_sweep_points_and_resources_separate(monkeypatch):
    payload = (b"Direction,UEIndex,CellID,Slot,SNR_dB,ResourceID,SINR_dB,SINRSource\n"
               b"DL,1,1,32,-30,1,-29,actual_receiver\n"
               b"DL,1,1,32,20,1,21,actual_receiver\n"
               b"DL,1,1,32,20,2,22,actual_receiver\n")
    captured = []
    original = m._render_multi_series_svg
    def retain_series(title, subtitle, series, *args, **kwargs):
        captured.extend(series)
        return original(title, subtitle, series, *args, **kwargs)
    monkeypatch.setattr(m, "_render_multi_series_svg", retain_series)
    _, rows = chart("CSI SINR timeline", {radio.CSI_TRIALS: payload})
    assert len(rows) == 3 and len(captured) == 3
    assert all(len(s["points"]) == 1 for s in captured)
    assert [(r["snr_db"], r["resource_id"]) for r in rows] == [("-30.0", "1"), ("20.0", "1"), ("20.0", "2")]


def test_applied_csi_basis_pmi_is_not_replaced_by_equivalent_port_basis_index():
    payload = (b"Slot,UEIndex,RequestedPrecoderPMI,AppliedPrecoderPMI,AppliedPrecoderPMIBasis,EquivalentPDSCHPortBasisCodebookIndex,PMICodebookMatrixCSIPortsSHA256,CSIRSPortToElementMatrixSHA256,ComposedElementMatrixSHA256\n"
               + b"36,1,3,3,csi_rs_port_basis,1," + b"a"*64 + b"," + b"b"*64 + b"," + b"c"*64 + b"\n")
    _, rows = chart("reported versus applied PMI", {radio.TRIALS[0]: payload})
    assert rows[0]["applied_pmi_token"] == "3"
    assert rows[0]["applied_pmi_basis"] == "csi_rs_port_basis"
    assert rows[0]["equivalent_pdsch_port_basis_codebook_index"] == "1.0"
    assert rows[0]["requested_applied_pmi_equal"] == "1"
    assert rows[0]["csi_port_pmi_matrix_sha256"] == "a"*64
    assert rows[0]["csi_port_to_element_matrix_sha256"] == "b"*64
    assert rows[0]["composed_element_matrix_sha256"] == "c"*64


@pytest.mark.parametrize("status", ["not_delivered", "pusch_csi_decode_unavailable_not_delivered"])
def test_failed_delivery_cannot_pass_a_substring_match(status):
    payload = f"Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,CQI,PMI\nDL,1,7,9,{status},10,0\n".encode()
    result, _ = chart("CSI CQI timeline", {radio.FEEDBACK: payload})
    assert b"CQI delivered:" not in result["img_bytes"]
    trial = b"Slot,UEIndex,LinkAdaptationAppliedFeedbackSourceSlot,RequestedPrecoderPMI,AppliedPrecoderPMI\n11,1,7,0,0\n"
    _, rows = chart("reported versus applied PMI", {radio.FEEDBACK: payload, radio.TRIALS[0]: trial})
    assert rows[0]["reported_pmi_token"] == ""


def test_precoder_feedback_requires_explicit_delivered_source_slot_not_value_equality():
    trials = (b"Slot,UEIndex,CSIMeasurementSlot,LinkAdaptationAppliedFeedbackSourceSlot,RequestedPrecoderPMI,AppliedPrecoderPMI\n"
              b"7,1,7,NaN,0,0\n11,1,12,7,0,0\n")
    reports = b"Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,PMI,RI\nDL,1,7,9,delivered_to_runtime_scheduler,0,2\nDL,1,12,14,delivered_to_runtime_scheduler,3,2\n"
    result, rows = chart("reported versus applied PMI", {radio.TRIALS[0]: trials, radio.FEEDBACK: reports})
    assert rows[0]["reported_pmi_token"] == ""  # Slot 7 measurement was not delivered yet.
    assert rows[1]["reported_pmi_token"] == "0"  # Uses explicit source 7, not current CSI slot 12.
    assert rows[1]["reported_ri"] == "2.0"
    assert rows[1]["feedback_binding_authority"].endswith("not_proof_of_precoder_selection_causality")
    assert b"no bound feedback" not in result["img_bytes"].lower()


def test_requested_pmi_is_not_titled_reported_when_no_feedback_is_bound():
    trials = b"Slot,UEIndex,RequestedPrecoderPMI,AppliedPrecoderPMI\n31,1,0,0\n32,1,0,0\n"
    result, rows = chart("reported versus applied PMI", {radio.TRIALS[0]: trials})
    image = result["img_bytes"].lower()
    assert b"requested versus applied pmi (no bound feedback)" in image
    assert b"reported versus applied pmi" not in image
    assert all(row["reported_pmi_token"] == "" for row in rows)
    assert all(row["chart_name"] == "reported versus applied PMI" for row in rows)


def test_physical_csi_plot_uses_received_fields_not_poisoned_ue_report(monkeypatch):
    captured = []
    original = m._render_multi_series_svg
    def retain_series(title, subtitle, series, *args, **kwargs):
        captured.extend(series)
        return original(title, subtitle, series, *args, **kwargs)
    monkeypatch.setattr(m, "_render_multi_series_svg", retain_series)
    legacy = b"Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,RI,CQI\nDL,1,34,39,delivered,4,15\n"
    received = (b"Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,RI,CQI,SourceSignal,CSIUCIDecodeOk,CSIUCITransport,SchedulerAcceptedRank,RankIncreaseConfirmationCount,RankIncreaseRequiredCount,SchedulerSpatialDecisionDeferred\n"
                b"DL,1,34,39,delivered_to_runtime_scheduler,2,9,received_CSI_UCI,1,pucch_independently_received,1,1,2,true\n")
    result, rows = chart("CSI RI timeline", {radio.FEEDBACK: legacy, radio.RECEIVED_CSI: received})
    assert len(rows) == 1 and rows[0]["component_values"] == "[2]"
    assert rows[0]["scheduler_accepted_rank"] == "1.0"
    assert rows[0]["rank_confirmation_count"] == "1.0"
    assert rows[0]["source_table_logical_path"] == radio.RECEIVED_CSI
    accepted = [s for s in captured if s["name"].startswith("Accepted rank (not TX):")]
    assert len(accepted) == 1 and accepted[0]["points"] == [[39.0, 1.0]]
    assert b"Accepted rank (not TX)" in result["img_bytes"]
    assert b"SNRNone" not in result["img_bytes"]
    _, rows = chart("CSI CQI timeline", {radio.FEEDBACK: legacy, radio.RECEIVED_CSI: received})
    assert rows[0]["component_values"] == "[9]"


def test_empty_independent_csi_is_not_filled_from_ue_state():
    legacy = b"Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,RI\nDL,1,34,39,delivered,4\n"
    result, _ = chart("CSI RI timeline", {radio.FEEDBACK: legacy,
        radio.RECEIVED_CSI: b"Direction,SourceSignal,CSIUCIDecodeOk,RI\n"})
    assert result["csv_status"] == "unavailable_exact_reason"


def test_configured_physical_csi_calendar_does_not_imply_any_received_report():
    legacy = (b"Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,RI,CRI\n"
              b"DL,1,34,39,delivered,4,7\n")
    # No independent received CSV is written until the first physical
    # completion. An obligation must not become evidence of that completion.
    calendar = b"ObligationID,ReportSlot,CSIReferenceSlot\ncsi-1,39,34\n"
    for name in ("CSI RI timeline", "CSI CRI timeline"):
        result, _ = chart(name, {radio.FEEDBACK: legacy, radio.CSI_OBLIGATIONS: calendar})
        assert result["csv_status"] == "unavailable_exact_reason"


def test_cri_plot_requires_decoded_resource_identity_not_pmi_or_tci():
    received = (b"Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,CRI,PMI,ActiveTCIStateID,SourceSignal,CSIUCIDecodeOk\n"
                b"DL,1,34,39,delivered,3,7,16,received_CSI_UCI,1\n")
    result, rows = chart("CSI CRI timeline", {radio.RECEIVED_CSI: received})
    assert rows[0]["component_values"] == "[3]"
    assert rows[0]["source_table_logical_path"] == radio.RECEIVED_CSI
    assert "not a measured angle, applied data beam or active TCI state" in result["note"]
    missing = received.replace(b",3,7,16,", b",NaN,7,16,")
    result, _ = chart("CSI CRI timeline", {radio.RECEIVED_CSI: missing})
    assert result["csv_status"] == "unavailable_exact_reason"


def test_failed_csi_attempt_is_retained_without_plotting_undecoded_fields():
    received = (b"Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,CRI,PMI,PMI_I2,SourceSignal,CSIUCIDecodeOk\n"
                b"DL,1,34,39,delivered,3,7,1,received_CSI_UCI,1\n"
                b"DL,1,54,59,decode_failed,6,5,2,received_CSI_UCI,0\n")
    for name in ("CSI CRI timeline", "CSI PMI components timeline"):
        result, rows = chart(name, {radio.RECEIVED_CSI: received})
        assert result["csv_status"] == "specialized_runtime_radio_measurement_dataset" and len(rows) == 2
        assert rows[1]["value_status"] == "unavailable_uci_not_decoded"
        assert rows[1]["component_values"] == "[]" and rows[1]["component_fields"] == "[]"
        assert rows[1]["delivered_slot"] == "59.0" and rows[1]["delivery_status"] == "decode_failed"


def test_physical_csi_failed_decode_cannot_be_published_as_delivered():
    received = (b"Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,RI,SourceSignal,CSIUCIDecodeOk\n"
                b"DL,1,34,39,delivered,2,received_CSI_UCI,0\n")
    result, rows = chart("CSI RI timeline", {radio.RECEIVED_CSI: received})
    assert result["csv_status"] == "unavailable_exact_reason"
    assert "successful UCI decode" in rows[0]["reason"]


def test_precoder_join_and_plot_preserve_all_sweep_points(monkeypatch):
    reports = (b"Direction,UEIndex,SourceSlot,DeliveredSlot,DeliveryStatus,PMI,RI,SNR_dB,SweepPointIndex,SourceSignal,CSIUCIDecodeOk\n"
               b"DL,1,34,39,delivered,3,2,40,1,received_CSI_UCI,1\n"
               b"DL,1,34,39,delivered,1,1,20,2,received_CSI_UCI,1\n")
    trials = (b"Slot,UEIndex,LinkAdaptationAppliedFeedbackSourceSlot,RequestedPrecoderPMI,AppliedPrecoderPMI,SNR_dB,SweepPointIndex\n"
              b"42,1,34,3,3,40,1\n42,1,34,1,1,20,2\n")
    captured = []
    original = m._render_multi_series_svg
    def retain_series(title, subtitle, series, *args, **kwargs):
        captured.extend(series)
        return original(title, subtitle, series, *args, **kwargs)
    monkeypatch.setattr(m, "_render_multi_series_svg", retain_series)
    _, rows = chart("reported versus applied PMI", {radio.TRIALS[0]: trials, radio.RECEIVED_CSI: reports})
    assert [r["reported_pmi_token"] for r in rows] == ["3", "1"]
    assert all(r["feedback_source_table"] == radio.RECEIVED_CSI for r in rows)
    assert len(captured) == 6 and all(len(s["points"]) == 1 for s in captured)


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
        b"Slot,UEIndex,Format,PostEqSINR_dB,CRCPass,PUCCHDecodeOk,ExpectedBitCount,PUCCHTransmissionPrepared\n5,1,0,20,NaN,1,1,1\n"})
    assert rows[0]["metric_value"] == "0" and rows[0]["metric_source_field"] == "uci_block_error"
    assert result["csv_status"] != "unavailable_exact_reason"


def test_negative_sr_dtx_and_missing_tx_payload_are_not_uci_block_errors():
    payload = (b"Slot,UEIndex,Format,PostEqSINR_dB,PUCCHDecodeOk,ExpectedBitCount,PUCCHTransmissionPrepared,DTXFlag\n"
               b"4,1,0,NaN,0,NaN,0,1\n"
               b"9,1,0,20,0,NaN,0,1\n"
               b"19,1,2,30,1,15,1,0\n"
               b"39,1,2,2,0,15,1,1\n")
    result, rows = chart("PUCCH BLER vs measured SINR", {"air_interface/csv/pucch_trials.csv": payload})
    assert result["csv_status"] == "specialized_runtime_radio_measurement_dataset"
    assert len(rows) == 4  # Retain every attempted reception in the CSV.
    assert all(row["metric_value"] == "" and row["block_error_population_status"] ==
               "not_a_transmitted_payload_block" for row in rows[:2])
    assert all(row["value_status"] == "not_applicable_no_transmitted_payload" for row in rows[:2])
    assert rows[2]["metric_value"] == "0" and rows[3]["metric_value"] == "1"
    assert rows[2]["value_status"] == rows[3]["value_status"] == "available"
    assert rows[3]["block_error_population_status"] == "observed_payload_decode", (
        "A missed real transmission must remain an error; DTX alone cannot remove it.")


def test_transmitted_uci_without_decode_evidence_stays_unresolved():
    payload = (b"Slot,UEIndex,Format,PostEqSINR_dB,PUCCHDecodeOk,ExpectedBitCount,PUCCHTransmissionPrepared\n"
               b"19,1,2,30,1,15,1\n"
               b"39,1,2,30,,15,1\n")
    _, rows = chart("PUCCH BLER vs measured SINR", {"air_interface/csv/pucch_trials.csv": payload})
    assert rows[1]["metric_value"] == ""
    assert rows[1]["block_error_population_status"] == "decode_outcome_unavailable"
    assert rows[1]["value_status"] == "required_measurement_unavailable"


@pytest.mark.parametrize("count,prepared,expected_population,expected_metric", [
    ("NaN", "1", "observed_payload_decode", "1"),
    ("NaN", "", "transmission_evidence_unavailable", ""),
    ("", "", "transmission_evidence_unavailable", ""),
    ("15", "", "observed_payload_decode", "1"),
    ("0", "", "not_a_transmitted_payload_block", ""),
    ("15", "0", "not_a_transmitted_payload_block", ""),
    ("0", "1", "conflicting_transmission_evidence", ""),
    ("-1", "1", "invalid_transmission_evidence", ""),
    ("1.5", "1", "invalid_transmission_evidence", ""),
    ("NaN", "unavailable", "transmission_evidence_unavailable", ""),
    ("NaN", "2", "invalid_transmission_evidence", ""),
    ("15", "-1", "invalid_transmission_evidence", ""),
    ("NaN", "true", "observed_payload_decode", "1"),
    ("NaN", "false", "not_a_transmitted_payload_block", ""),
])
def test_uci_bler_requires_positive_or_explicitly_absent_transmission_evidence(
        count, prepared, expected_population, expected_metric):
    payload = ("Slot,UEIndex,Format,PostEqSINR_dB,PUCCHDecodeOk,ExpectedBitCount,PUCCHTransmissionPrepared\n"
               "19,1,2,30,1,15,1\n"
               f"39,1,2,2,0,{count},{prepared}\n").encode()
    _, rows = chart("PUCCH BLER vs measured SINR", {"air_interface/csv/pucch_trials.csv": payload})
    assert rows[1]["block_error_population_status"] == expected_population
    assert rows[1]["metric_value"] == expected_metric
    if expected_population.endswith("_evidence") or expected_population == "transmission_evidence_unavailable":
        assert rows[1]["value_status"] == "required_measurement_unavailable"


def test_uci_decode_alone_does_not_prove_a_transmitted_block():
    payload = (b"Slot,UEIndex,Format,PostEqSINR_dB,PUCCHDecodeOk\n19,1,2,30,1\n")
    result, rows = chart("PUCCH BLER vs measured SINR", {"air_interface/csv/pucch_trials.csv": payload})
    # With no observed payload population there is no numerical BLER chart.
    # The reason artifact is not a fabricated primary performance row.
    assert result["csv_status"] == "unavailable_exact_reason"
    assert "transmission_evidence_unavailable=1" in result["note"]
    assert "metric_value" not in rows[0]
