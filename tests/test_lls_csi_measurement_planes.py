from __future__ import annotations

from pathlib import Path
import sys
import json
import shutil
import subprocess

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as dash


def test_csi_reference_and_rank_objective_remain_distinct():
    row = {
        "UEIndex": 1, "Slot": 6, "SINR_dB": 12.0,
        "SINRSource": "selected_rank_objective",
        "SINRMeasurementDomain": "selected_precoder_layer_receiver_objective",
        "SINRValueRole": "measured_csi_receiver_objective_scheduling_input",
        "ReferenceMeasuredSINR_dB": 20.0,
        "ReferenceMeasuredSINRSource": "received_reference_ratio",
        "ReferenceMeasuredSINRDomain": "csi_rs_port3000_reference_re_received_plane",
    }
    ue = dash.build_realtime_ue_status({}, {}, {"csi": [row]})[0]
    assert ue["csi_sinr_db"] == 20.0
    assert ue["csi_sinr_source"] == "received_reference_ratio"
    assert ue["csi_sinr_domain"] == row["ReferenceMeasuredSINRDomain"]
    assert ue["csi_scheduling_objective_db"] == 12.0
    assert ue["csi_scheduling_objective_source"] == "selected_rank_objective"
    del row["ReferenceMeasuredSINR_dB"]
    ue = dash.build_realtime_ue_status({}, {}, {"csi": [row]})[0]
    assert ue["csi_sinr_db"] is None
    assert ue["csi_scheduling_objective_db"] == 12.0


def test_missing_reference_source_does_not_borrow_scheduling_source():
    row = {"UEIndex": 1, "Slot": 6, "ReferenceMeasuredSINR_dB": 20,
           "SINRSource": "unrelated_objective", "SINR_dB": 12}
    ue = dash.build_realtime_ue_status({}, {}, {"csi": [row]})[0]
    assert ue["csi_sinr_db"] == 20 and ue["csi_sinr_source"] == ""
    assert ue["csi_scheduling_objective_db"] is None


def test_csi_panel_columns_match_produced_measurement_keys():
    source = Path(dash.__file__).read_text(encoding="utf-8")
    panel = source.split("{id:'csi', title:", 1)[1].split("rows:csiRows", 1)[0]
    for name in ("CSI-RSRP (dB re unit occupied-RE Es)",
                 "CSI-RSSI (dB re unit occupied-RE Es)", "CSI-RSRQ dB",
                 "RSRP RX branch (1-based)", "Rank/PMI objective dB", "SINR plane"):
        assert name in panel
    assert "CSI-RSRP (dB re configured power plane)" not in panel


@pytest.mark.parametrize("missing", ["NaN", float("nan"), "Inf", "-Inf", "", None])
def test_absolute_csi_power_does_not_select_missing_normalized_plane(missing):
    row = dict(UEIndex=1, Slot=6, MeasurementRSRP_dBm=-97.498434,
               MeasurementRSSI_dBm=-75.73875,
               MeasurementRSRP_dB_re_UnitOccupiedRE_Es=missing,
               MeasurementRSSI_dB_re_UnitOccupiedRE_Es=missing,
               ReferenceMeasuredSINR_dB=missing, PilotSINR_dB=0,
               PilotSINRSource="independent_pilot", PilotSINRMeasurementDomain="received")
    ue = dash.build_realtime_ue_status({}, {}, {"csi": [row]})[0]
    assert ue["csi_power_unit"] == "dBm"
    assert ue["csi_rsrp_normalized_db"] is None
    assert ue["csi_rssi_normalized_db"] is None
    assert ue["csi_rssi_dbm"] == -75.73875
    assert ue["csi_sinr_db"] == 0
    assert ue["csi_sinr_source"] == "independent_pilot"
    row["MeasurementRSRP_dBm"] = missing
    row["MeasurementRSRP_dB_re_UnitOccupiedRE_Es"] = 0
    ue = dash.build_realtime_ue_status({}, {}, {"csi": [row]})[0]
    assert ue["csi_rsrp_dbm"] is None
    assert ue["csi_rsrp_normalized_db"] == 0
    assert ue["csi_power_unit"] == "dB_re_unit_occupied_RE_Es"


def test_csi_recommendations_and_branch_provenance_reach_browser_projection():
    row = dict(UEIndex=1, Slot=6, RI=2, PMI=23, CRI=1, CQI=14,
               MeasurementRSRP_dBm=-97.498434, MeasurementRSSI_dBm=-75.73875,
               MeasurementReceiveAntennaIndex1Based=1,
               MeasurementRSRQReceiveAntennaIndex1Based=2,
               MeasurementRSRQNumeratorRSRP_dBm=-98.105159,
               MeasurementRSRQDenominatorRSSI_dBm=-76.555416,
               DLMeasurementAuthorityRequired=1, DLMeasurementAuthorityEligible=0,
               DLMeasurementAuthorityStatus="awaiting_received_DL_acquisition_and_configuration",
               DLMeasurementAuthoritySource="preconfigured_LLS_not_decoded_dedicated_RRC",
               PhysicalMeasurementStatus="available")
    ue = dash.build_realtime_ue_status({}, {}, {"csi": [row]})[0]
    assert ue["csi_authority_eligible"] == 0
    assert ue["csi_rsrp_receive_branch"] == 1
    assert ue["csi_rsrq_receive_branch"] == 2
    source = Path(dash.__file__).read_text(encoding="utf-8")
    projection = "\n".join(line.strip() for line in source.splitlines()
                           if line.strip().startswith(("const csiRows =", "const csiRecommendationRows =")))
    node = shutil.which("node")
    if node is None:
        import playwright
        node = str(Path(playwright.__file__).parent / "driver" /
                   ("node.exe" if sys.platform == "win32" else "node"))
    js = "const recent=x=>x;const dashboard=" + json.dumps({"ue_status": [ue]}) + ";"
    result = subprocess.run([node, "-e", js + projection +
                             "console.log(JSON.stringify([csiRows,csiRecommendationRows]));"],
                            capture_output=True, text=True, check=True, timeout=15)
    powers, recommended = json.loads(result.stdout)
    assert powers[0]["CSI-RSSI dBm"] == -75.73875
    assert powers[0]["RSRQ RX branch (1-based)"] == 2
    assert powers[0]["RSRQ numerator RSRP dBm"] == -98.105159
    assert [recommended[0]["Recommended " + key] for key in ("CRI", "RI", "PMI", "CQI")] == [1, 2, 23, 14]
    assert recommended[0]["DL authority eligible"] == 0
    assert recommended[0]["Measurement status"] == "available"
    assert "not delivered feedback or transmitted layers" in source
    empty = dash.build_realtime_ue_status({}, {}, {"csi": [dict(UEIndex=1, Slot=6)]})[0]
    assert all(empty["csi_recommended_" + k] is None for k in ("cri", "ri", "pmi", "cqi"))
    assert empty["csi_authority_eligible"] is None
    vector = dash.build_realtime_ue_status({}, {}, {"csi": [dict(row, PMI=[2, 3], CQI=[14, 11])]})[0]
    assert vector["csi_recommended_pmi"] == [2, 3]
    assert vector["csi_recommended_cqi"] == [14, 11]


def test_independent_sib1_preview_is_not_pbch_or_inferred_crc():
    owner = dash.CANONICAL_RUNTIME_ARTIFACT_OWNERS["sib1_trials"]
    assert owner["canonical_path"] == "air_interface/csv/sib1_received_trials.csv"
    assert owner["legacy_paths"] == []
    raw = dict(ObservationID="si-1", UEId=1, ResourceAbsoluteSlot0Based=8,
               DeliverySlot1Based=10, DCICrcPass=1, DLSCHCrcPass=0,
               Installed=0, DeliveryStatus="received_SI_not_accepted",
               RawPostRFInputSHA256="a" * 64, DecoderInputSHA256="b" * 64)
    row = dash.summarize_control_trial_preview_rows("sib1_trials", [raw])[0]
    assert row["Resource slot (0-based)"] == 8
    assert row["Delivery slot (1-based)"] == 10
    assert row["SI DCI CRC pass"] == 1 and row["SI DLSCH CRC pass"] == 0
    assert row["Installed"] == 0 and row.get("ASN1 decoded") is None
    assert row["Raw RX SHA256"] != row["Decoder input SHA256"]
    assert dash.summarize_control_trial_preview_rows("sib1_trials", []) == []


def test_independent_sib1_file_reaches_runtime_preview(tmp_path):
    import csv
    path = tmp_path / "sib1_received_trials.csv"
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=["ObservationID", "UEId", "Installed", "DeliveryStatus"])
        writer.writeheader()
        writer.writerow(dict(ObservationID="fixture-si", UEId=1, Installed=0,
                             DeliveryStatus="received_SI_not_accepted"))
    artifact = dict(artifact_id=-1, logical_path="air_interface/csv/sib1_received_trials.csv",
                    filesystem_path=str(path), byte_size=path.stat().st_size)
    context = dash.extract_runtime_context({}, [artifact])
    assert context["control_trial_previews"]["sib1_trials"][0]["Installed"] == 0
    assert context["control_trial_previews"]["pbch_trials"] == []
    assert context["artifact_selection"]["raw_control_trials"]["sib1_trials"]["selected_logical_path"] == artifact["logical_path"]
