"""Boundary fixtures for publication, not physical beam-qualification evidence."""
from __future__ import annotations

import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).absolute().parents[1] / "apps"))
import lls_contract_materializer as materializer


@pytest.mark.parametrize("value, expected", [(0, "0"), (False, "False"), (None, ""), ("", "")])
def test_zero_is_not_a_missing_configuration_or_measurement(value, expected):
    assert materializer._row_text(dict(value=value), "value") == expected
    if value is not None and value != "":
        assert materializer._row_text(dict(value=value, alternative=19), "value", "alternative") == expected


def publish_beams(source_rows, configuration=None):
    path = "air_interface/csv/dl_pdsch_trials.csv"
    data = materializer._encode_rows_from_dicts(source_rows)
    result = materializer._specialized_table_materialization(
        "live_beam_selection_table", {path: dict(artifact_id=1)}, lambda _: data,
        7, "Beam management", dict(config_json=json.dumps(configuration or {})), {})
    assert result is not None
    return result, materializer._decode_csv_dicts(result["data"])[1]


def test_configuration_does_not_claim_received_tci_or_qcl():
    _, rows = publish_beams([dict(Slot=41, SelectedBeamIndex=2)], dict(
        tci=dict(state_id=0, unified_state_id=16, validity_timer_slots=20),
        qcl=dict(type="TypeD", source_rs="CSI-RS-3"),
        near_field=dict(fraunhofer_boundary_m=10, focal_point_m=[1, 2, 3])))
    row = rows[0]
    for name in ("tci_state_id", "unified_tci_state_id", "tci_validity_timer_slots",
                 "qcl_type", "qcl_source_rs", "fraunhofer_boundary_m", "near_field_focal_point_m"):
        assert row[name] == "", f"Configuration is not executed evidence: {name}"
    assert row["tci_status"] == row["qcl_status"] == "not_materialized_in_active_truth_path"
    assert row["configured_tci_state_id"] == "0"
    assert row["configured_unified_tci_state_id"] == "16"
    assert row["configured_qcl_source_rs"] == "CSI-RS-3"
    assert row["beam_management_procedure"] == "runtime_data_beam_selection"


def test_runtime_tci_zero_and_source_provenance_survive_materialization():
    _, rows = publish_beams([dict(Slot=41, TCIStateID=0, QCLType="TypeD",
        QCLSourceRS="SSB-1", TCIStatus="decoded_control_applied", QCLStatus="received_control_bound",
        RunID="h4-run", ExecutionID="execution-a", ConfiguredSNR_dB=40, SweepPointIndex=1,
        SelectedBeamIndex=2, SelectedBeamGain_dB=-3.5)], dict(tci=dict(state_id=19)))
    row = rows[0]
    assert row["tci_state_id"] == "0" and row["configured_tci_state_id"] == "19"
    assert row["tci_status"] == "decoded_control_applied" and row["qcl_status"] == "received_control_bound"
    assert row["qcl_source_rs"] == "SSB-1"
    assert row["source_run_id"] == "h4-run" and row["source_execution_id"] == "execution-a"
    assert row["configured_snr_db"] == "40" and row["sweep_point_index"] == "1"
    assert row["selected_beam_gain_db"] == "-3.5"


def test_beam_table_does_not_guess_ue_index_from_rnti():
    _, rows = publish_beams([dict(Slot=41, RNTI=181, SelectedBeamIndex=2)])
    assert rows[0]["ue_id"] == "" and rows[0]["rnti"] == "181"


@pytest.mark.parametrize("samples_per_point", [1, 200])
def test_joint_beam_publication_retains_every_sweep_point_and_row(samples_per_point):
    snrs = [40, 30, 20, 10, 0, -10, -20, -30]
    supplied = [dict(Slot=slot, ConfiguredSNR_dB=snr, SweepPointIndex=point,
                     ExecutionID=f"point-{point}", RunID="joint-run", SelectedBeamIndex=point % 4)
                for point, snr in enumerate(snrs, 1) for slot in range(samples_per_point)]
    result, rows = publish_beams(supplied)
    assert len(rows) == len(supplied) == result["source_row_count"]
    assert {int(row["configured_snr_db"]) for row in rows} == set(snrs)
    assert [(int(row["sweep_point_index"]), int(row["slot"])) for row in rows] == [
        (row["SweepPointIndex"], row["Slot"]) for row in supplied]


@pytest.mark.parametrize("chart", ["selected vs best beam timeline", "beam id timeline", "beam pair timeline"])
def test_beam_plot_keeps_all_eight_points_and_both_beam_series(chart):
    snrs = [40, 30, 20, 10, 0, -10, -20, -30]
    supplied = [dict(Slot=slot, Direction="DL", UEIndex=1, ServingCell=1,
                     ConfiguredSNR_dB=snr, SweepPointIndex=point,
                     ExecutionID=f"point-{point}", RunID="joint-run",
                     SelectedBeamIndex=slot % 4, BestBeamIndex=(slot + point) % 4)
                for point, snr in enumerate(snrs, 1) for slot in range(201)]
    path = "air_interface/csv/dl_pdsch_trials.csv"
    data = materializer._encode_rows_from_dicts(supplied)
    chart_data = materializer._specialized_chart_materialization(
        chart, {path: dict(artifact_id=1)}, lambda _: data, 7)
    assert chart_data is not None
    _, rows = materializer._decode_csv_dicts(chart_data["csv_bytes"])
    assert len(rows) == len(supplied) == chart_data["source_row_count"]
    assert {int(row["configured_snr_db"]) for row in rows} == set(snrs)
    assert {row["direction"] for row in rows} == {"DL"}
    assert {row["ue_id"] for row in rows} == {"1"}
    # Verify actual rendered series, not just a CSV or success flag. Every
    # selected/best sample is retained; no first-180-row preview substitution.
    svg = ET.fromstring(chart_data["img_bytes"])
    lines = svg.findall(".//{http://www.w3.org/2000/svg}polyline")
    assert len(lines) == 16
    assert all(len(line.attrib["points"].split()) == 201 for line in lines)
    if chart == "selected vs best beam timeline":
        png = materializer._rasterize_contract_png(chart_data["img_bytes"],
            source_mime_type="image/svg+xml", source_logical_path="internal://beam-sweep-test")
        assert materializer._png_low_information_reason(png) == ""


def test_beam_timeline_needs_an_observed_slot_and_excludes_proxy_rows():
    path = "air_interface/csv/dl_pdsch_trials.csv"
    data = materializer._encode_rows_from_dicts([
        dict(Slot="", SelectedBeamIndex=3, ProxyUsed=0),
        dict(Slot=4, SelectedBeamIndex=2, ProxyUsed=1)])
    chart = materializer._beam_mimo_chart_materialization(
        "beam id timeline", {path: dict(artifact_id=1)}, lambda _: data, 7)
    assert chart is None
