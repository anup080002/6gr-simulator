from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    orig_load_first = dash.load_first_available_csv_rows
    try:
        def fake_load_first(_artifacts, logical_paths, *, max_rows=64):
            key = logical_paths[0] if logical_paths else ""
            if key == "reports/csv/live_rsrp_serving_trace.csv":
                return [
                    {"Slot": 10, "Time_s": 0.005, "UEID": 1, "ServingCell": 101, "BaseStationID": 11, "ReceiverHestWidebandSINR_dB": -4.25, "WidebandCQI": 2, "ServingRSRP_dBm": -79.3},
                    {"Slot": 11, "Time_s": 0.0055, "UEID": 1, "ServingCell": 101, "BaseStationID": 11, "ReceiverHestWidebandSINR_dB": -2.0, "WidebandCQI": 4, "ServingRSRP_dBm": -78.0},
                    {"Slot": 10, "Time_s": 0.005, "UEID": 2, "ServingCell": 202, "BaseStationID": 22, "ReceiverHestWidebandSINR_dB": 1.5, "WidebandCQI": 7, "ServingRSRP_dBm": -71.0},
                ]
            if key == "air_interface/csv/dl_pdsch_trials.csv":
                return [
                    {"Slot": 10, "UEID": 1, "CellID": 101, "BaseStationID": 11, "Goodput_Mbps": 12.5, "OfferedThroughput_Mbps": 18.0, "AllocatedPRBCount": 88, "MCSIndex": 10, "MeasuredTrialSINR_dB": -3.5, "ReceiverHestSINR_dB": -4.25},
                    {"Slot": 10, "UEID": 2, "CellID": 202, "BaseStationID": 22, "Goodput_Mbps": 24.0, "OfferedThroughput_Mbps": 24.0, "AllocatedPRBCount": 120, "MCSIndex": 14},
                ]
            if key == "air_interface/csv/ul_pusch_trials.csv":
                return [
                    {"Slot": 10, "UEID": 1, "CellID": 101, "BaseStationID": 11, "Goodput_Mbps": 6.0, "OfferedThroughput_Mbps": 8.0, "AllocatedPRBCount": 28, "MCSIndex": 8},
                ]
            if key == "reports/csv/live_user_performance_snapshot.csv":
                return [
                    {"UEIndex": 1, "DL_Throughput_Mbps": 15.2, "UL_Throughput_Mbps": 6.4, "UserThroughput_Mbps": 21.6, "DL_BLER": 0.1, "UL_BLER": 0.2},
                    {"UEIndex": 2, "DL_Throughput_Mbps": 24.0, "UL_Throughput_Mbps": 0.0, "UserThroughput_Mbps": 24.0, "DL_BLER": 0.0, "UL_BLER": 0.0},
                ]
            return []

        dash.load_first_available_csv_rows = fake_load_first
        payload = dash.build_metric_explorer_payload([], {"configured_users": 200})
        assert payload["available"] is True
        assert payload["configured_ue_count"] == 200
        assert payload["chartable_ue_count"] == 2
        assert payload["chartable_cell_count"] == 2
        assert payload["cell_ids"] == [101, 202]
        metric_ids = {metric["id"] for metric in payload["available_metrics"]}
        assert {"sinr_dB", "cqi", "dl_goodput_mbps", "ul_goodput_mbps"} <= metric_ids
        first = next(row for row in payload["rows"] if int(row["slot"]) == 10 and int(row["ueid"]) == 1)
        assert first["serving_cell"] == 101
        assert first["base_station_id"] == 11
        assert abs(float(first["sinr_dB"]) - (-3.5)) < 1e-9
        assert abs(float(first["receiver_hest_sinr_dB"]) - (-4.25)) < 1e-9
        assert abs(float(first["dl_goodput_mbps"]) - 12.5) < 1e-9
        assert abs(float(first["ul_goodput_mbps"]) - 6.0) < 1e-9
        second = next(row for row in payload["rows"] if int(row["slot"]) == 11 and int(row["ueid"]) == 1)
        assert second["sinr_dB"] is None
        assert abs(float(second["receiver_hest_sinr_dB"]) - (-2.0)) < 1e-9
        assert payload["ue_summaries"]["1"]["source_table"] == "reports/csv/live_user_performance_snapshot.csv"
        assert payload["sampling"]["chart_rows_browser"] >= 2
        assert "sampled runtime rows" in payload["sampling_note"].lower()
    finally:
        dash.load_first_available_csv_rows = orig_load_first


if __name__ == "__main__":
    main()
