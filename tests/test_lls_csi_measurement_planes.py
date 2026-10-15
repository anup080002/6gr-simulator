from __future__ import annotations

from pathlib import Path
import sys

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
