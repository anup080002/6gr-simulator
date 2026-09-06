from __future__ import annotations

import csv
import io
import math
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as materializer


def render(payload: bytes, duplicate_alias: bool = False):
    path = "reports/csv/equalized_constellations.csv"
    existing = {path: {"artifact_id": 1, "logical_path": path}}
    if duplicate_alias:
        alias = "air_interface/csv/dl_constellation_samples.csv"
        existing[alias] = {"artifact_id": 2, "logical_path": alias}
    return materializer._specialized_chart_materialization(
        "EVM per symbol", existing, lambda _id: payload, 17
    )


PAYLOAD = (
    "Direction,UEIndex,Frame,RuntimeSlot,TBId,LayerIndex,CodewordIndex,"
    "OFDMSymbolIndex,ReferenceSymbolReal,ReferenceSymbolImag,EqualizedReal,"
    "EqualizedImag,SymbolEVM_rms,TruthStatus,EqualizationSource\n"
    "DL,1,1,6,1,1,0,3,1,0,1.1,0,0.1,real_lls_evidence,receiver_output_without_payload_gain_or_phase_fit\n"
    "DL,1,1,6,1,1,0,3,3,0,3.9,0,0.3,real_lls_evidence,receiver_output_without_payload_gain_or_phase_fit\n"
    "DL,1,1,7,2,1,0,3,1,0,1.5,0,0.5,real_lls_evidence,receiver_output_without_payload_gain_or_phase_fit\n"
    "DL,2,1,6,1,1,0,3,1,0,1.8,0,0.8,real_lls_evidence,receiver_output_without_payload_gain_or_phase_fit\n"
).encode()


def test_evm_energy_normalization_peak_and_slot_identity():
    result = render(PAYLOAD)
    rows = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert len(rows) == 3, "EVM needs one energy aggregate per UE/slot/symbol, not per-RE means."
    first = next(row for row in rows if row["ue_index"] == "1" and row["slot"] == "6")
    assert float(first["rms_evm_pct"]) == pytest.approx(100 * math.sqrt(0.82 / 10))
    assert float(first["peak_evm_pct"]) == pytest.approx(100 * 0.9 / math.sqrt(5))
    assert int(first["sample_count"]) == 2
    assert first["measurement_scope"] == "persisted_paired_sample_subset"
    assert b"EVM (%)" in result["img_bytes"]
    assert b"RMS" in result["img_bytes"] and b"Peak" in result["img_bytes"]


def test_evm_aliases_do_not_double_count_same_runtime_capture():
    result = render(PAYLOAD, duplicate_alias=True)
    rows = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert sum(int(row["sample_count"]) for row in rows) == 4


def test_evm_scalar_without_paired_samples_is_not_reconstructed():
    result = render(b"Direction,RuntimeSlot,OFDMSymbolIndex,SymbolEVM_rms\nDL,6,3,0.1\n")
    assert result["csv_status"] == "unavailable_exact_reason"


@pytest.mark.parametrize("status", ["mismatched_layer_domain", "unavailable", "invalid_ordering"])
def test_evm_rejects_known_unmatched_symbol_ordering(status):
    records = PAYLOAD.decode().splitlines()
    payload = (records[0] + ",SymbolOrderingStatus\n" +
               "\n".join(row + "," + status for row in records[1:]) + "\n").encode()
    assert render(payload)["csv_status"] == "unavailable_exact_reason"


def test_throughput_sinr_preserves_direction_trial_and_crc():
    paths = ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"]
    header = b"Slot,UEIndex,MCS,Layers,CRCPass,MeasuredSINR_dB,Throughput_Mbps,Goodput_Mbps\n"
    payloads = {1: header + b"6,1,4,1,1,10,2,2\n", 2: header + b"9,1,9,2,0,10,5,0\n"}
    existing = {path: {"artifact_id": idx, "logical_path": path}
                for idx, path in enumerate(paths, 1)}
    result = materializer._specialized_chart_materialization(
        "throughput vs SINR", existing, payloads.__getitem__, 17
    )
    rows = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert len(rows) == 2, "Equal DL/UL SINR values must not merge into one average."
    assert {row["direction"] for row in rows} == {"DL", "UL"}
    ul = next(row for row in rows if row["direction"] == "UL")
    assert float(ul["throughput_mbps"]) == 5 and float(ul["goodput_mbps"]) == 0
    assert ul["crc_pass"] == "0" and ul["mcs"] == "9" and ul["layers"] == "2"
    assert ul["source_table_logical_path"] == paths[1]


def test_direction_specific_evm_keeps_zero_and_single_symbol_observations():
    path = "reports/csv/equalized_constellations.csv"
    header = PAYLOAD.split(b"\n", 1)[0] + b"\n"
    payload = header + b"DL,1,1,6,1,1,0,3,1,0,1,0,0,real_lls_evidence,receiver_output_without_payload_gain_or_phase_fit\n" + b"UL,1,1,9,2,1,0,1,1,0,1.3,0,0.3,real_lls_evidence,receiver_output_without_payload_gain_or_phase_fit\n"
    existing = {path: {"artifact_id": 1, "logical_path": path}}
    for chart_name, direction, expected in (("PDSCH EVM per symbol", "DL", 0), ("PUSCH EVM per symbol", "UL", 30)):
        result = materializer._specialized_chart_materialization(chart_name, existing, lambda _: payload, 17)
        rows = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
        assert len(rows) == 1 and rows[0]["direction"] == direction
        assert float(rows[0]["rms_evm_pct"]) == pytest.approx(expected)
        assert b"EVM (%)" in result["img_bytes"] and b"<circle " in result["img_bytes"]
        png = materializer._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml")
        assert png.startswith(b"\x89PNG\r\n\x1a\n")


@pytest.mark.parametrize("field", ["ConfiguredSNR_dB", "SNR_dB", "LargeScaleSINR_dB"])
def test_throughput_does_not_use_configured_or_geometry_only_sinr(field):
    path = "air_interface/csv/dl_pdsch_trials.csv"
    payload = f"Slot,UEIndex,{field},Throughput_Mbps,Goodput_Mbps\n1,1,25,5,5\n".encode()
    result = materializer._specialized_chart_materialization("throughput vs SINR",
        {path: {"artifact_id": 1, "logical_path": path}}, lambda _: payload, 17)
    assert result["csv_status"] == "unavailable_exact_reason"
    assert b"measured_sinr_unavailable" in result["csv_bytes"]


@pytest.mark.parametrize("truth", ["fast_proxy", "synthetic", "fallback"])
def test_throughput_proxy_rows_never_enter_primary_measured_dataset(truth):
    path = "air_interface/csv/dl_pdsch_trials.csv"
    payload = f"Slot,UEIndex,MeasuredSINR_dB,Throughput_Mbps,Goodput_Mbps,TruthStatus\n1,1,25,5,5,{truth}\n".encode()
    result = materializer._specialized_chart_materialization("throughput vs SINR",
        {path: {"artifact_id": 1, "logical_path": path}}, lambda _: payload, 17)
    assert result["csv_status"] == "unavailable_exact_reason"
    assert b"non_runtime_evidence" in result["csv_bytes"]
    assert b"throughput_mbps" not in result["csv_bytes"]


def test_throughput_preserves_missing_goodput_instead_of_substituting_tb_rate():
    path = "air_interface/csv/dl_pdsch_trials.csv"
    payload = b"Slot,UEIndex,PostEqSINR_dB,Throughput_Mbps,Goodput_Mbps\n1,1,25,5,NaN\n"
    result = materializer._specialized_chart_materialization("throughput vs SINR",
        {path: {"artifact_id": 1, "logical_path": path}}, lambda _: payload, 17)
    row = next(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert row["throughput_mbps"] == "5.0" and row["goodput_mbps"] == ""
    assert row["goodput_value_status"] == "unavailable_in_source"


def test_sinr_proxy_source_is_not_exported_as_a_measured_number():
    path = "air_interface/csv/dl_pdsch_trials.csv"
    payload = b"Slot,UEIndex,PostEqSINR_dB,PostEqSINRSource,Throughput_Mbps,Goodput_Mbps\n1,1,25,evm_proxy,5,5\n"
    result = materializer._specialized_chart_materialization("throughput vs SINR",
        {path: {"artifact_id": 1, "logical_path": path}}, lambda _: payload, 17)
    row = next(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert row["sinr_db"] == "" and row["value_status"] == "sinr_source_not_measured_evidence"
    assert result["csv_status"] == "unavailable_exact_reason"


def test_plot_review_preserves_original_sources_and_refuses_overwrites(tmp_path):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
    from export_lls_observed_data_plots import export_observed_plots
    root, review = tmp_path / "run", tmp_path / "review"
    source = root / "reports/csv/equalized_constellations.csv"
    source.parent.mkdir(parents=True)
    source.write_bytes(PAYLOAD)
    before = source.read_bytes()
    report = export_observed_plots(root, review)
    assert source.read_bytes() == before
    assert report["source_run_tag"] == "run"
    assert (review / "pdsch_evm_per_symbol.png").is_file()
    assert not (review / "pusch_evm_per_symbol.png").exists()
    assert (review / "provenance.json").is_file()
    with pytest.raises(FileExistsError):
        export_observed_plots(root, review)
    with pytest.raises(ValueError):
        export_observed_plots(root, root / "nested_review")


def test_evm_prefers_actual_raw_receiver_over_payload_fitted_constellation():
    # Fitted equalized value pretends to be perfect; the receiver has a 50%
    # amplitude error. Existing capture files retain both fields.
    header = PAYLOAD.split(b"\n", 1)[0] + b",RawEqualizedReal,RawEqualizedImag\n"
    payload = header + b"DL,1,1,6,1,1,0,3,1,0,1,0,0,real_lls_evidence,,1.5,0\n"
    result = render(payload)
    row = next(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert float(row["rms_evm_pct"]) == pytest.approx(50)
    assert row["measured_sample_source"] == "raw_receiver_equalized_before_reporter_payload_fit"
    # Invalid raw evidence must not fall through to the perfect fitted pair.
    assert render(payload.replace(b",1.5,0\n", b",NaN,0\n"))["csv_status"] == "unavailable_exact_reason"


def test_evm_rejects_unqualified_or_explicitly_payload_fitted_samples():
    for source in (b"", b"same_sample_payload_gain_fit"):
        payload = PAYLOAD.replace(b"receiver_output_without_payload_gain_or_phase_fit", source)
        assert render(payload)["csv_status"] == "unavailable_exact_reason"


def full_capture_payload():
    rows = list(csv.DictReader(io.StringIO(PAYLOAD.decode())))[:2]
    for index, row in enumerate(rows, 1):
        row.update(CaptureScope="full_allocation_paired_symbols", ObservationSymbolCount="2",
                   CapturedSymbolCount="2", SampleIndex=str(index), SubcarrierIndex=str(index))
    return encode_rows(rows)


def encode_rows(rows):
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
    return output.getvalue().encode()


def test_full_evm_capture_requires_complete_observation_and_preserves_math():
    result = render(full_capture_payload())
    row = next(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert row["measurement_scope"] == "full_allocation_paired_symbols"
    assert float(row["rms_evm_pct"]) == pytest.approx(100*math.sqrt(.82/10))
    assert b"scope=full paired allocation" in result["img_bytes"]


@pytest.mark.parametrize("defect", ["missing_row", "duplicate_sample", "duplicate_resource", "wrong_total", "wrong_captured", "mixed_scope", "invalid_index", "missing_coordinate"])
def test_full_capture_never_passes_with_missing_or_inconsistent_evidence(defect):
    rows = list(csv.DictReader(io.StringIO(full_capture_payload().decode())))
    if defect == "missing_row":
        rows.pop()
    elif defect == "duplicate_sample":
        rows[1]["SampleIndex"] = "1"
    elif defect == "duplicate_resource":
        rows[1]["SubcarrierIndex"] = "1"
    elif defect == "wrong_total":
        rows[1]["ObservationSymbolCount"] = "3"
    elif defect == "wrong_captured":
        rows[1]["CapturedSymbolCount"] = "1"
    elif defect == "mixed_scope":
        rows[1]["CaptureScope"] = "paired_sample_preview"
    elif defect == "invalid_index":
        rows[1]["SampleIndex"] = "3"
    else:
        rows[1]["SubcarrierIndex"] = "NaN"
    assert render(encode_rows(rows))["csv_status"] == "unavailable_exact_reason"


def test_dft_despread_qam_is_valid_per_symbol_but_not_physical_subcarrier_evm():
    rows = list(csv.DictReader(io.StringIO(full_capture_payload().decode())))
    for row in rows:
        row["Direction"] = "UL"
        row["SymbolCoordinateDomain"] = "pre_transform_qam_positions"
    payload = encode_rows(rows)
    assert render(payload)["csv_status"] == "specialized_runtime_evm_dataset"
    path = "air_interface/csv/ul_constellation_samples.csv"
    result = materializer._specialized_chart_materialization("EVM per subcarrier",
        {path: {"artifact_id": 1, "logical_path": path}}, lambda _: payload, 17)
    assert result["csv_status"] == "unavailable_exact_reason"
