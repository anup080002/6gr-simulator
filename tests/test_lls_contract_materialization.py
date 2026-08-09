from __future__ import annotations

import io
import shutil
import sys
import tempfile
from pathlib import Path

from PIL import Image


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
    assert chart_path.endswith(".png")
    assert "waveform-time-domain-analytics" in chart_path
    assert "tx-waveform" in chart_path

    csv_path = materializer.chart_contract_csv_path(tx_chart)
    assert csv_path.endswith(".csv")
    assert csv_path.startswith("analytics/csv/")

    manifest = materializer.manifest_logical_path()
    assert manifest == "reports/csv/contract_materialization_manifest.csv"

    coverage = materializer.coverage_logical_path()
    assert coverage == "reports/csv/contract_materialization_coverage.csv"

    with tempfile.TemporaryDirectory() as temporary_root:
        long_root = Path(temporary_root) / ("materializer-long-root-" + "x" * 100)
        long_logical = (
            "reports/image/contract__" + "long-chart-name-" * 8 + ".png"
        )
        long_payload = b"filesystem-long-path-regression"
        materializer._write_file_if_possible(  # noqa: SLF001
            str(long_root), long_logical, long_payload
        )
        long_target = long_root / Path(*long_logical.split("/"))
        assert materializer._windows_long_path(long_target).read_bytes() == long_payload  # noqa: SLF001
        shutil.rmtree(materializer._windows_long_path(long_root))  # noqa: SLF001

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
    assert "source_mapping_status" in chart_csv
    assert "exact" in chart_csv

    constant_svg = materializer._render_svg_plot(  # noqa: SLF001
        "beam gain gap histogram",
        "Beam gap distribution from exported runtime beam metrics.",
        {"mode": "bar", "x_label": "Beam gap (dB)", "y_label": "Count", "points": [[0.0, 1546.0]]},
        ["samples=1546"],
    ).decode("utf-8")
    assert "visual_gate=single_bucket_distribution" in constant_svg
    assert "would not support a defensible chart conclusion" in constant_svg

    useful_bar_svg = materializer._render_svg_plot(  # noqa: SLF001
        "rank distribution",
        "Rank/layer distribution from runtime rows.",
        {"mode": "bar", "x_label": "Rank", "y_label": "Count", "points": [[1.0, 100.0], [2.0, 45.0]]},
        ["samples=145"],
    ).decode("utf-8")
    assert "visual_gate=" not in useful_bar_svg
    assert "<rect" in useful_bar_svg

    raster_png = materializer._rasterize_contract_png(  # noqa: SLF001
        useful_bar_svg.encode("utf-8"),
        source_mime_type="image/svg+xml",
        source_logical_path="internal://test/rank-distribution.svg",
    )
    assert raster_png.startswith(b"\x89PNG\r\n\x1a\n")
    with Image.open(io.BytesIO(raster_png)) as raster_image:
        assert raster_image.format == "PNG"
        assert raster_image.width >= 640
        assert raster_image.height >= 360

    jpeg_buffer = io.BytesIO()
    Image.new("RGB", (32, 24), color=(8, 122, 112)).save(jpeg_buffer, format="JPEG")
    jpeg_as_png = materializer._rasterize_contract_png(  # noqa: SLF001
        jpeg_buffer.getvalue(),
        source_mime_type="image/jpeg",
        source_logical_path="reports/image/legacy-source.jpeg",
    )
    assert jpeg_as_png.startswith(b"\x89PNG\r\n\x1a\n")
    with Image.open(io.BytesIO(jpeg_as_png)) as converted_image:
        assert converted_image.format == "PNG"
        assert converted_image.size == (32, 24)

    assert materializer.EXACT_CHART_FAMILY_CONTRACTS["heatmap"]["required_columns"] == ("x_value", "y_value", "z_value")
    assert materializer.EXACT_CHART_FAMILY_CONTRACTS["timeline"]["required_columns"] == ("x_value", "y_value")

    for unsafe_chart_name in ["fake heatmap", "fake serving map", "fake beam timeline"]:
        exact_dataset, mapping_status, reason = materializer._dataset_from_exact_chart_contract(  # noqa: SLF001
            unsafe_chart_name,
            "reports/csv/generic_numeric_source.csv",
            ["Frame", "SomeMetric"],
            [["1", "5"], ["2", "6"], ["3", "7"]],
        )
        assert exact_dataset is None
        assert mapping_status == "invalid"
        assert "Generic numeric-column inference is disabled" in reason or "exact direct source" in reason
        invalid_csv = materializer._chart_dataset_csv(  # noqa: SLF001
            37,
            unsafe_chart_name,
            exact_dataset,
            "reports/csv/generic_numeric_source.csv",
            3,
            "invalid_source_mapping",
            reason,
            mapping_status,
        ).decode("utf-8")
        assert "source_mapping_status" in invalid_csv
        assert "invalid" in invalid_csv
        assert ",line," not in invalid_csv, "Unsafe chart families must not become generic line plots."

    exact_timeline, mapping_status, _reason = materializer._dataset_from_exact_chart_contract(  # noqa: SLF001
        "real runtime timeline",
        "reports/csv/exact_chart_dataset.csv",
        ["chart_mode", "x_label", "y_label", "x_value", "y_value"],
        [["line", "slot", "metric", "1", "5"], ["line", "slot", "metric", "2", "6"], ["line", "slot", "metric", "3", "7"]],
    )
    assert exact_timeline is not None
    assert mapping_status == "exact"
    assert exact_timeline["mode"] == "line"

    constant_timeline, mapping_status, reason = materializer._dataset_from_exact_chart_contract(  # noqa: SLF001
        "constant runtime timeline",
        "reports/csv/exact_chart_dataset.csv",
        ["chart_mode", "x_label", "y_label", "x_value", "y_value"],
        [["line", "slot", "metric", "1", "5"], ["line", "slot", "metric", "2", "5"], ["line", "slot", "metric", "3", "5"]],
    )
    assert constant_timeline is None
    assert mapping_status == "invalid"
    assert "constant/single y-series" in reason

    finalized = materializer._finalize_chart_materialization_result(  # noqa: SLF001
        {
            "csv_bytes": materializer._encode_csv(["run_id", "chart_name"], [[1, "unavailable chart"]]),  # noqa: SLF001
            "img_bytes": b"<svg></svg>",
            "csv_status": "unavailable_exact_reason",
            "image_status": "generated_unavailable_reason_svg",
        }
    )
    assert finalized is not None
    finalized_csv = finalized["csv_bytes"].decode("utf-8")
    assert "source_mapping_status" in finalized_csv
    assert "unavailable" in finalized_csv

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
    assert "visual_gate=scalar_prach_rate_kpi" in detection_special["img_bytes"].decode("utf-8")

    false_alarm_special = materializer._specialized_chart_materialization(  # noqa: SLF001
        "false alarm rate",
        existing,
        lambda artifact_id: payloads[artifact_id],
        9,
    )
    assert false_alarm_special is not None
    assert false_alarm_special["csv_status"] == "specialized_runtime_detection_dataset"
    assert "false alarm rate" in false_alarm_special["csv_bytes"].decode("utf-8").lower()

    prach_peak_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "PeakValue", "DetectionMetric", "TimingError_samples", "Status"],
        [[5, 0.87, 0.87, 0, "PASS"], [5, 0.89, 0.89, 0, "PASS"]],
    )
    existing = {
        "air_interface/csv/prach_trials.csv": {
            "artifact_id": 111,
            "logical_path": "air_interface/csv/prach_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {111: prach_peak_csv}
    prach_peak = materializer._specialized_chart_materialization(  # noqa: SLF001
        "PRACH peak search timeline",
        existing,
        lambda artifact_id: payloads[artifact_id],
        10,
    )
    assert prach_peak is not None
    assert "visual_gate=sparse_prach_peak_evidence" in prach_peak["img_bytes"].decode("utf-8")

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

    csirs_stripe_csv = materializer._encode_csv(  # noqa: SLF001
        ["CellID", "Slot", "ResourceID", "ResourceSetID", "RBOffset", "NumRB", "SymbolLocations", "NRE", "MeasurementRSRP_dB"],
        [[1, 7, 0, 0, 0, 4, "0", 16, -91.5]],
    )
    existing = {
        "air_interface/csv/csi_rs_trials.csv": {
            "artifact_id": 211,
            "logical_path": "air_interface/csv/csi_rs_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {211: csirs_stripe_csv}
    csirs_stripe = materializer._specialized_chart_materialization(  # noqa: SLF001
        "CSI-RS resource occupancy",
        existing,
        lambda artifact_id: payloads[artifact_id],
        12,
    )
    assert csirs_stripe is not None
    assert "visual_gate=single_axis_resource_occupancy" in csirs_stripe["img_bytes"].decode("utf-8")

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
    throughput_time_text = throughput_time["csv_bytes"].decode("utf-8")
    assert "series_name,chart_mode,x_label,y_label,x_value,y_value" in throughput_time_text
    assert ",scatter," in throughput_time_text, "Two-slot throughput evidence must not be rendered as a fake line trend."

    bler_mcs = materializer._specialized_chart_materialization(  # noqa: SLF001
        "BLER vs MCS",
        existing,
        lambda artifact_id: payloads[artifact_id],
        14,
    )
    assert bler_mcs is not None
    assert "mcs,bler,sample_count" in bler_mcs["csv_bytes"].decode("utf-8")

    mixed_reliability_csv = materializer._encode_csv(  # noqa: SLF001
        ["CRCPass", "BitsCompared", "BitErrors", "PostEqSINR_dB"],
        [[1, 1000, 0, 18.0], [1, 1000, 10, 19.0]],
    )
    pucch_reliability_csv = materializer._encode_csv(  # noqa: SLF001
        ["CRCPass", "DetectionAttempted", "BitsCompared"],
        [[0, 1, 0]],
    )
    existing = {
        "air_interface/csv/dl_pdsch_trials.csv": {
            "artifact_id": 411,
            "logical_path": "air_interface/csv/dl_pdsch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        },
        "air_interface/csv/pucch_trials.csv": {
            "artifact_id": 412,
            "logical_path": "air_interface/csv/pucch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        },
    }
    payloads = {411: mixed_reliability_csv, 412: pucch_reliability_csv}
    bler_summary = materializer._specialized_chart_materialization(  # noqa: SLF001
        "BLER",
        existing,
        lambda artifact_id: payloads[artifact_id],
        16,
    )
    assert bler_summary is not None
    bler_summary_text = bler_summary["csv_bytes"].decode("utf-8")
    assert "BLER,0.0,2,air_interface/csv/dl_pdsch_trials.csv" in bler_summary_text
    assert "pucch_trials" not in bler_summary_text, "Data-channel BLER must not mix PUCCH control decode failures into the denominator."
    assert "visual_gate=scalar_reliability_kpi" in bler_summary["img_bytes"].decode("utf-8")

    flat_waveform_csv = materializer._encode_csv(  # noqa: SLF001
        ["SampleIndex", "Time_s", "TxReal", "TxImag", "TxMagnitude", "RxReal", "RxImag", "RxMagnitude"],
        [[1, 0.0, 0.0, 0.0, 0.0, 0.1, 0.0, 0.1], [2, 1e-6, 0.0, 0.0, 0.0, 0.2, 0.0, 0.2]],
    )
    existing = {
        "analytics/csv/waveform_analytics.csv": {
            "artifact_id": 413,
            "logical_path": "analytics/csv/waveform_analytics.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {413: flat_waveform_csv}
    flat_tx = materializer._specialized_chart_materialization(  # noqa: SLF001
        "Tx waveform",
        existing,
        lambda artifact_id: payloads[artifact_id],
        16,
    )
    assert flat_tx is not None
    assert "visual_gate=flat_waveform_preview" in flat_tx["img_bytes"].decode("utf-8")

    ssb_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "SSBIndex"],
        [[1, 0], [1, 1]],
    )
    existing = {
        "reports/csv/live_ssb_stage_table.csv": {
            "artifact_id": 414,
            "logical_path": "reports/csv/live_ssb_stage_table.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {414: ssb_csv}
    ssb_sparse = materializer._specialized_chart_materialization(  # noqa: SLF001
        "SSB index timeline",
        existing,
        lambda artifact_id: payloads[artifact_id],
        16,
    )
    assert ssb_sparse is not None
    assert "visual_gate=sparse_ssb_index_events" in ssb_sparse["img_bytes"].decode("utf-8")

    pbch_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "CellID", "DecodeSuccess", "SelectedBeamIndex"],
        [[1, 1, 1, 0], [1, 2, 1, 1]],
    )
    existing = {
        "air_interface/csv/pbch_trials.csv": {
            "artifact_id": 415,
            "logical_path": "air_interface/csv/pbch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {415: pbch_csv}
    pbch_sparse = materializer._specialized_chart_materialization(  # noqa: SLF001
        "PBCH/SSB map",
        existing,
        lambda artifact_id: payloads[artifact_id],
        16,
    )
    assert pbch_sparse is not None
    assert "visual_gate=single_axis_resource_occupancy" in pbch_sparse["img_bytes"].decode("utf-8")

    pucch_dtx_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "UEID", "CRCPass", "DetectionAttempted", "BitsCompared", "DTXFlag", "MissedDetection", "FalseAlarmFlag"],
        [
            [1, 7, 1, 1, 0, 0, 0, 0],
            [2, 7, 0, 1, 0, 1, 0, 0],
            [3, 7, 0, 1, 0, 0, 1, 0],
        ],
    )
    existing = {
        "air_interface/csv/pucch_trials.csv": {
            "artifact_id": 421,
            "logical_path": "air_interface/csv/pucch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {421: pucch_dtx_csv}
    pucch_dtx = materializer._specialized_chart_materialization(  # noqa: SLF001
        "PUCCH DTX statistics",
        existing,
        lambda artifact_id: payloads[artifact_id],
        17,
    )
    assert pucch_dtx is not None
    pucch_dtx_text = pucch_dtx["csv_bytes"].decode("utf-8")
    assert "Decoded/observed" in pucch_dtx_text
    assert "DTX" in pucch_dtx_text
    assert "Missed detection" in pucch_dtx_text
    assert "1.0,7,Decoded/observed" in pucch_dtx_text, "Zero compared bits alone must not convert a decoded PUCCH row into DTX."

    beam_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "SelectedBeamIndex", "BestBeamIndex"],
        [[1, 3, 5], [2, 4, 4]],
    )
    existing = {
        "beamforming/csv/beam_precoder_table.csv": {
            "artifact_id": 431,
            "logical_path": "beamforming/csv/beam_precoder_table.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {431: beam_csv}
    beam_gap = materializer._specialized_chart_materialization(  # noqa: SLF001
        "beam gain gap histogram",
        existing,
        lambda artifact_id: payloads[artifact_id],
        18,
    )
    assert beam_gap is not None
    assert beam_gap["csv_status"] == "unavailable_exact_reason"
    assert "Beam-index distance is not a dB gain gap" in beam_gap["csv_bytes"].decode("utf-8")

    layer_quality_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "WidebandCQI", "MCSIndex", "Layers", "PostEqSINRPerLayer_dB"],
        [[1, 12, 18, 2, "[14.5 11.25]"], [2, 10, 15, 2, "[12.0, 10.0]"]],
    )
    existing = {
        "reports/csv/live_link_adaptation_input_table.csv": {
            "artifact_id": 441,
            "logical_path": "reports/csv/live_link_adaptation_input_table.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {441: layer_quality_csv}
    layer_quality = materializer._specialized_chart_materialization(  # noqa: SLF001
        "per-layer quality plot",
        existing,
        lambda artifact_id: payloads[artifact_id],
        19,
    )
    assert layer_quality is not None
    layer_text = layer_quality["csv_bytes"].decode("utf-8")
    assert "1,13.25" in layer_text and "2,10.625" in layer_text

    existing = {
        "air_interface/csv/dl_pdsch_trials.csv": {
            "artifact_id": 41,
            "logical_path": "air_interface/csv/dl_pdsch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    payloads = {41: trial_csv}
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
