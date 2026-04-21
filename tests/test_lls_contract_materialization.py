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


if __name__ == "__main__":
    main()
