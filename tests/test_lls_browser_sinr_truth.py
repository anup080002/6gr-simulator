from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    coverage_rows = [
        {
            "UEID": "7",
            "Slot": "3",
            "ServingCell": "2",
            "ServingSite": "1",
            "ServingSector": "2",
            "Lat": "12.0",
            "Lon": "77.0",
            "RSRP_dBm": "-82.5",
            "PostEqWidebandSINR_dB": "9.7",
            "ReceiverHestWidebandSINR_dB": "31.2",
            "DecoderTruthProxyWidebandSINR_dB": "8.4",
            "LargeScaleWidebandSINR_dB": "12.1",
            "WidebandSINRSource": "post_equalization_sinr_from_equalizer_channel_estimate",
            "WidebandSINRValueRole": "measured_post_equalization_scheduling_input",
            "WidebandCQI": "10",
        }
    ]
    points = dash.build_coverage_points(coverage_rows)
    assert points[0]["PostEqWidebandSINR_dB"] == "9.7"
    assert points[0]["ReceiverHestWidebandSINR_dB"] == "31.2"
    assert points[0]["DecoderTruthProxyWidebandSINR_dB"] == "8.4"
    assert points[0]["WidebandSINRValueRole"] == "measured_post_equalization_scheduling_input"

    movement = dash.build_movement_payload(coverage_rows)
    assert movement["points"][0]["sinr_dB"] == 9.7

    assert dash.MAP_METRIC_SPECS[2]["key"] == "PostEqWidebandSINR_dB"
    assert dash.MAP_METRIC_SPECS[3]["key"] == "ReceiverHestWidebandSINR_dB"
    assert dash.MAP_METRIC_SPECS[4]["key"] == "DecoderTruthProxyWidebandSINR_dB"

    system_estimate_rows = [
        {
            "UEID": "8",
            "Slot": "4",
            "ServingCell": "3",
            "Lat": "12.1",
            "Lon": "77.1",
            "EstimatedWidebandSINR_dB": "44.0",
            "SystemLevelWidebandSINR_dB": "13.5",
            "SystemLevelSINRSource": "system_level_desired_interference_noise_budget",
            "WidebandSINRValueStatus": "available_system_level_estimate",
        }
    ]
    system_points = dash.build_coverage_points(system_estimate_rows)
    assert system_points[0]["ReceiverHestWidebandSINR_dB"] is None
    assert system_points[0]["MeasuredWidebandSINR_dB"] is None
    assert system_points[0]["SystemLevelWidebandSINR_dB"] == "13.5"
    system_movement = dash.build_movement_payload(system_estimate_rows)
    assert system_movement["points"][0]["sinr_dB"] is None
    assert system_movement["points"][0]["system_level_sinr_dB"] == 13.5

    artifacts = [{"logical_path": "reports/csv/runtime_operating_mode.csv", "artifact_id": 1, "byte_size": 256}]
    run_row = {
        "run_id": 52,
        "status_text": "completed",
        "config_json": "{}",
    }
    operating_mode_rows = [
        {
            "Direction": "DL",
            "RequestedOperatingPointSource": "cqi_link_adaptation",
            "ConfiguredMCSSelectionPolicy": "cqi_driven",
        }
    ]

    orig_load_small = dash.load_small_csv_rows
    orig_load_first = dash.load_first_available_csv_rows
    try:
        def fake_load_small(artifacts_arg, logical_path, *, max_rows=64):
            if logical_path == "reports/csv/runtime_operating_mode.csv":
                return operating_mode_rows
            if logical_path == "air_interface/csv/dl_pdsch_trials.csv":
                return []
            if logical_path == "air_interface/csv/ul_pusch_trials.csv":
                return []
            return []

        dash.load_small_csv_rows = fake_load_small
        dash.load_first_available_csv_rows = lambda artifacts_arg, logical_paths, *, max_rows=64: []
        runtime_context = dash.extract_runtime_context(run_row, artifacts)
        notes = " ".join(runtime_context["notes"])
        assert "not a decoder-truth SINR measurement" in notes
        assert "it is not a measured SINR" in notes
        assert "ReceiverHestSINR_dB is a receiver-side diagnostic from Hest/reference-signal residual measurement" in notes
    finally:
        dash.load_small_csv_rows = orig_load_small
        dash.load_first_available_csv_rows = orig_load_first


if __name__ == "__main__":
    main()
