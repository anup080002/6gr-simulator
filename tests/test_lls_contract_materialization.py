from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).absolute().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_contract_materializer as materializer  # noqa: E402
import lls_output_contract as output_contract  # noqa: E402
import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    report_sections = output_contract.product_sections_payload("reports")
    analytics_sections = output_contract.product_sections_payload("analytics")

    scheduler_section = next(
        section for section in report_sections if section["slug"] == "scheduler-mac-queue-qos-power-control-uci-flow"
    )
    queue_table = next(table for table in scheduler_section["tables"] if table["table_name"] == "live_queue_state")
    assert materializer.table_contract_path(queue_table) == "reports/csv/live_queue_state.csv"
    assert dash.contract_table_candidate_paths(queue_table)[0] == "reports/csv/live_queue_state.csv"

    waveform_section = next(
        section for section in analytics_sections if section["slug"] == "waveform-time-domain-analytics"
    )
    tx_chart = next(chart for chart in waveform_section["charts"] if chart["chart_name"] == "Tx waveform")
    chart_paths = dash.contract_chart_candidate_paths(tx_chart)
    assert materializer.chart_contract_csv_path(tx_chart) in chart_paths
    assert materializer.chart_contract_image_path(tx_chart) in chart_paths

    chart_path = materializer.chart_contract_image_path(tx_chart)
    assert chart_path.endswith(".svg")
    assert "waveform-time-domain-analytics" in chart_path
    assert "tx-waveform" in chart_path

    csv_path = materializer.chart_contract_csv_path(tx_chart)
    assert csv_path.endswith(".csv")
    assert csv_path.startswith("analytics/csv/")

    manifest = materializer.manifest_logical_path()
    assert manifest == "reports/csv/contract_materialization_manifest.csv"

    coverage = materializer.coverage_logical_path()
    assert coverage == "reports/csv/contract_materialization_coverage.csv"

    chart_csv = materializer._chart_dataset_csv(  # noqa: SLF001
        36,
        "throughput",
        {
            "mode": "line",
            "x_label": "slot",
            "y_label": "throughput_mbps",
            "points": [[1, 12.5], [2, 15.0]],
        },
        "system/csv/system_time_series.csv",
        240,
        "derived_chart_dataset",
        "derived from persisted source rows",
    ).decode("utf-8")
    assert "chart_name,chart_mode,x_label,y_label,point_index,x_value,y_value" in chart_csv
    assert "throughput,line,slot,throughput_mbps,1,1,12.5" in chart_csv
    assert "system/csv/system_time_series.csv" in chart_csv

    metric_key_dataset = materializer._dataset_from_rows(  # noqa: SLF001
        "Metric key fallback",
        ["MetricKey", "MetricName", "ValueNumeric"],
        [["bler_runtime", "", "0.25"]],
    )
    assert metric_key_dataset is not None
    assert metric_key_dataset["tick_labels"] == ["bler_runtime"]

    impairment_section = next(
        section for section in analytics_sections if section["slug"] == "impairments-tracking-analytics"
    )
    iq_chart = next(chart for chart in impairment_section["charts"] if chart["chart_name"] == "IQ imbalance summary")
    iq_paths = dash.contract_chart_candidate_paths(iq_chart)
    assert materializer.chart_contract_csv_path(iq_chart) in iq_paths
    assert materializer.chart_contract_image_path(iq_chart) in iq_paths
    assert "rf/csv/probe_rf_iq_imbalance.csv" in iq_paths
    assert "rf/csv/iq_imbalance_timeline_trace.csv" in iq_paths

    timeline_csv = materializer._encode_csv(  # noqa: SLF001
        [
            "Direction",
            "Frame",
            "Slot",
            "IQImbalanceImageRejection_dB",
            "IQImbalanceMirrorPowerRatio_dB",
            "IQImbalanceIQCorrelation",
        ],
        [
            ["DL", 1, 7, 27.5, -27.5, 0.08],
            ["UL", 1, 8, 25.0, -25.0, 0.11],
        ],
    )
    summary_csv = materializer._encode_csv(  # noqa: SLF001
        ["Direction", "Availability", "MeasuredRowCount", "AppliedRowCount", "MeanImageRejection_dB", "ModelSet"],
        [
            ["DL", "measured_runtime_iq_imbalance", 1, 1, 27.5, "widely_linear"],
            ["UL", "measured_runtime_iq_imbalance", 1, 1, 25.0, "widely_linear"],
        ],
    )
    existing = {
        "rf/csv/iq_imbalance_timeline_trace.csv": {
            "artifact_id": 1,
            "logical_path": "rf/csv/iq_imbalance_timeline_trace.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        },
        "rf/csv/probe_rf_iq_imbalance.csv": {
            "artifact_id": 2,
            "logical_path": "rf/csv/probe_rf_iq_imbalance.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        },
    }
    payloads = {1: timeline_csv, 2: summary_csv}
    special = materializer._specialized_chart_materialization(  # noqa: SLF001
        "IQ imbalance summary",
        existing,
        lambda artifact_id: payloads[artifact_id],
        7,
    )
    assert special is not None
    assert special["csv_status"] == "specialized_runtime_iq_imbalance_dataset"
    assert special["image_status"] == "generated_specialized_runtime_summary_svg"
    assert "iq_imbalance_timeline_trace.csv" in special["source_table_path"]
    assert "mean_image_rejection_db" in special["csv_bytes"].decode("utf-8")
    assert b"IQ imbalance summary" in special["img_bytes"]

    prach_csv = materializer._encode_csv(  # noqa: SLF001
        ["SNR_dB", "SuccessFlag", "FalseAlarmFlag", "DetectionMetric", "Status"],
        [
            [0, 0, 0, 0, "FAIL"],
            [0, 1, 0, 1, "PASS"],
            [10, 1, 0, 1, "PASS"],
            [10, 0, 1, 0, "FAIL"],
        ],
    )
    existing = {
        "air_interface/csv/prach_trials.csv": {
            "artifact_id": 11,
            "logical_path": "air_interface/csv/prach_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {11: prach_csv}
    detection_special = materializer._specialized_chart_materialization(  # noqa: SLF001
        "detection rate",
        existing,
        lambda artifact_id: payloads[artifact_id],
        9,
    )
    assert detection_special is not None
    assert detection_special["csv_status"] == "specialized_runtime_detection_dataset"
    assert "bucket_name,snr_db,metric_value,sample_count" in detection_special["csv_bytes"].decode("utf-8")

    false_alarm_special = materializer._specialized_chart_materialization(  # noqa: SLF001
        "false alarm rate",
        existing,
        lambda artifact_id: payloads[artifact_id],
        9,
    )
    assert false_alarm_special is not None
    assert false_alarm_special["csv_status"] == "specialized_runtime_detection_dataset"
    assert "false alarm rate" in false_alarm_special["csv_bytes"].decode("utf-8").lower()

    csirs_csv = materializer._encode_csv(  # noqa: SLF001
        ["CellID", "Slot", "ResourceID", "ResourceSetID", "RBOffset", "NumRB", "SymbolLocations", "NRE", "MeasurementRSRP_dB", "UEIndex"],
        [
            [1, 7, 0, 0, 10, 2, "2 10", 48, -95.0, 3],
            [1, 7, 0, 0, 10, 2, "2 10", 48, -98.0, 5],
        ],
    )
    existing = {
        "air_interface/csv/csi_rs_trials.csv": {
            "artifact_id": 21,
            "logical_path": "air_interface/csv/csi_rs_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {21: csirs_csv}
    csirs_special = materializer._specialized_chart_materialization(  # noqa: SLF001
        "CSI-RS map",
        existing,
        lambda artifact_id: payloads[artifact_id],
        12,
    )
    assert csirs_special is not None
    assert csirs_special["csv_status"] == "specialized_runtime_grid_dataset"
    csirs_text = csirs_special["csv_bytes"].decode("utf-8")
    assert "symbol_index,rb_index,occupancy_value" in csirs_text
    assert csirs_text.count("\n") >= 4

    srs_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "UEIndex", "NMSE_dB", "SuccessFlag", "Status"],
        [
            [8, 2, -27.1, 1, "PASS"],
            [8, 6, -25.8, 1, "PASS"],
            [9, 2, -24.0, 0, "FAIL"],
        ],
    )
    existing = {
        "air_interface/csv/srs_trials.csv": {
            "artifact_id": 31,
            "logical_path": "air_interface/csv/srs_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {31: srs_csv}
    srs_special = materializer._specialized_chart_materialization(  # noqa: SLF001
        "SRS map",
        existing,
        lambda artifact_id: payloads[artifact_id],
        13,
    )
    assert srs_special is not None
    assert srs_special["csv_status"] == "specialized_runtime_srs_dataset"
    assert "ue_index,occupancy_value,nmse_db,success_flag" in srs_special["csv_bytes"].decode("utf-8")

    trial_csv = materializer._encode_csv(  # noqa: SLF001
        ["Direction", "Slot", "MCS", "CRCPass", "Throughput_Mbps", "Goodput_Mbps", "Latency_ms"],
        [
            ["DL", 1, 4, 1, 10.0, 10.0, 0.4],
            ["DL", 1, 4, 0, 12.0, 0.0, 0.6],
            ["DL", 2, 8, 1, 20.0, 20.0, 0.5],
        ],
    )
    existing = {
        "air_interface/csv/dl_pdsch_trials.csv": {
            "artifact_id": 41,
            "logical_path": "air_interface/csv/dl_pdsch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {41: trial_csv}
    throughput_time = materializer._specialized_chart_materialization(  # noqa: SLF001
        "throughput over time",
        existing,
        lambda artifact_id: payloads[artifact_id],
        14,
    )
    assert throughput_time is not None
    assert throughput_time["csv_status"] == "specialized_runtime_throughput_timeline_dataset"
    assert "series_name,chart_mode,x_label,y_label,x_value,y_value" in throughput_time["csv_bytes"].decode("utf-8")

    bler_mcs = materializer._specialized_chart_materialization(  # noqa: SLF001
        "BLER vs MCS",
        existing,
        lambda artifact_id: payloads[artifact_id],
        14,
    )
    assert bler_mcs is not None
    assert "mcs,bler,sample_count" in bler_mcs["csv_bytes"].decode("utf-8")

    latency_cdf = materializer._specialized_chart_materialization(  # noqa: SLF001
        "latency CDF",
        existing,
        lambda artifact_id: payloads[artifact_id],
        14,
    )
    assert latency_cdf is not None
    assert "latency_ms,cdf_probability" in latency_cdf["csv_bytes"].decode("utf-8")

    energy_csv = materializer._encode_csv(  # noqa: SLF001
        ["Energy_J", "SuccessfulBits", "ActiveBWFraction", "ActiveRank", "Power_W"],
        [
            [0.1, 1000, 0.25, 1, 10.0],
            [0.2, 2000, 0.50, 2, 20.0],
            [0.0, 0, 0.75, 2, 30.0],
        ],
    )
    existing = {
        "rf/csv/energy_timeline_trace.csv": {
            "artifact_id": 51,
            "logical_path": "rf/csv/energy_timeline_trace.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {51: energy_csv}
    energy_hist = materializer._specialized_chart_materialization(  # noqa: SLF001
        "energy per bit histogram",
        existing,
        lambda artifact_id: payloads[artifact_id],
        15,
    )
    assert energy_hist is not None
    assert "x_value,y_value,sample_count" in energy_hist["csv_bytes"].decode("utf-8")

    bw_power = materializer._specialized_chart_materialization(  # noqa: SLF001
        "active bandwidth vs power",
        existing,
        lambda artifact_id: payloads[artifact_id],
        15,
    )
    assert bw_power is not None
    assert "x_value,y_value,power_w" in bw_power["csv_bytes"].decode("utf-8")

    original_loader = dash.load_cached_csv_preview
    original_artifact_url = dash.artifact_url
    try:
        preview_map = {
            101: (
                ["slot", "rb_index", "occupancy_value"],
                [["7", "10", "0.5"], ["7", "11", "0.5"], ["8", "10", "1.0"]],
            ),
            102: (
                ["series_name", "x_value", "y_value"],
                [["Sites", "0", "0"], ["Sites", "1", "0"], ["UEs", "0.5", "2.0"]],
            ),
            103: (
                ["bucket_name", "metric_value"],
                [["0 dB", "0.5"], ["10 dB", "1.0"]],
            ),
        }
        dash.load_cached_csv_preview = lambda artifact_id, limit: preview_map[int(artifact_id)]
        dash.artifact_url = lambda artifact_id, download=False: f"/artifact/{artifact_id}{'?download=1' if download else ''}"

        heatmap_chart = dash.build_numeric_chart_from_artifact({"artifact_id": 101, "logical_path": "analytics/csv/contract__resource-grid__heatmap.csv"})
        assert heatmap_chart is not None
        assert heatmap_chart["series"][0]["mode"] == "heatmap"

        scatter_chart = dash.build_numeric_chart_from_artifact({"artifact_id": 102, "logical_path": "reports/csv/contract__topology.csv"})
        assert scatter_chart is not None
        assert len(scatter_chart["series"]) == 2
        assert scatter_chart["series"][0]["points"][0]["x"] == 0.0

        bar_chart = dash.build_numeric_chart_from_artifact({"artifact_id": 103, "logical_path": "analytics/csv/contract__detection.csv"})
        assert bar_chart is not None
        assert bar_chart["series"][0]["trace_type"] == "bar"
        assert bar_chart["series"][0]["points"][0]["x"] == "0 dB"
    finally:
        dash.load_cached_csv_preview = original_loader
        dash.artifact_url = original_artifact_url


if __name__ == "__main__":
    main()
