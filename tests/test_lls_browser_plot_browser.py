from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    orig_build_live = dash.build_live_payload
    orig_build_numeric = dash.build_numeric_charts_from_artifacts
    orig_load_cached = dash.load_cached_csv_preview
    orig_artifact_url = dash.artifact_url
    orig_fetch_run = dash.fetch_run
    orig_fetch_artifacts = dash.fetch_artifacts
    orig_sync_runtime_log = dash.sync_runtime_log_for_run
    orig_extract_feature_policy = dash.extract_run_feature_policy
    orig_materialize = dash.contract_materializer.materialize_run_contract_artifacts
    try:
        def fake_build_live(_run_id: int, lite: bool = False):
            return {
                "tables_all": [
                    {
                        "artifact_id": 101,
                        "logical_path": "analytics/csv/contract__waveform-time-domain-analytics__rx-waveform.csv",
                        "artifact_kind": "table_csv",
                        "download_url": "/artifact/101/raw?download=1",
                        "view_url": "/artifact/101/table",
                        "section": "analytics",
                    },
                    {
                        "artifact_id": 201,
                        "logical_path": "analytics/csv/contract__throughput-goodput-spectral-efficiency-analytics__goodput.csv",
                        "artifact_kind": "table_csv",
                        "download_url": "/artifact/201/raw?download=1",
                        "view_url": "/artifact/201/table",
                        "section": "analytics",
                    },
                    {
                        "artifact_id": 202,
                        "logical_path": "analytics/csv/contract__throughput-goodput-spectral-efficiency-analytics__fairness-index-trend.csv",
                        "artifact_kind": "table_csv",
                        "download_url": "/artifact/202/raw?download=1",
                        "view_url": "/artifact/202/table",
                        "section": "analytics",
                    },
                    {
                        "artifact_id": 301,
                        "logical_path": "reports/csv/contract__scenario-geometry-topology-layout__serving-cell-map.csv",
                        "artifact_kind": "table_csv",
                        "download_url": "/artifact/301/raw?download=1",
                        "view_url": "/artifact/301/table",
                        "section": "reports",
                    },
                    {
                        "artifact_id": 401,
                        "logical_path": "reports/csv/latency_cdf_plot.csv",
                        "artifact_kind": "table_csv",
                        "download_url": "/artifact/401/raw?download=1",
                        "view_url": "/artifact/401/table",
                        "section": "reports",
                    },
                ],
                "images_all": [
                    {
                        "artifact_id": 102,
                        "logical_path": "analytics/image/contract__waveform-time-domain-analytics__rx-waveform.svg",
                        "artifact_kind": "image_svg",
                        "view_url": "/artifact/102/raw",
                        "download_url": "/artifact/102/raw?download=1",
                        "section": "analytics",
                    },
                    {
                        "artifact_id": 302,
                        "logical_path": "reports/image/contract__scenario-geometry-topology-layout__serving-cell-map.svg",
                        "artifact_kind": "image_svg",
                        "view_url": "/artifact/302/raw",
                        "download_url": "/artifact/302/raw?download=1",
                        "section": "reports",
                    },
                ],
            }

        def fake_artifacts(_run_id: int):
            payload = fake_build_live(_run_id)
            rows = []
            for row in list(payload["tables_all"]) + list(payload["images_all"]):
                enriched = dict(row)
                enriched.setdefault("byte_size", 128)
                enriched.setdefault("created_utc", "2026-05-25T00:00:00Z")
                if str(enriched.get("artifact_kind") or "") == "table_csv":
                    enriched.setdefault("mime_type", "text/csv; charset=UTF-8")
                else:
                    enriched.setdefault("mime_type", "image/svg+xml")
                rows.append(enriched)
            # This fixture uses the legacy published-layout contract. The
            # production browser now requires an explicit publication
            # authority; bare files alone must remain diagnostics.
            rows.append({"artifact_id": 777, "artifact_kind": "table_csv",
                "logical_path": "reports/csv/component_artifact_publication_manifest.csv",
                "mime_type": "text/csv; charset=UTF-8", "byte_size": 128,
                "created_utc": "2026-05-25T00:00:00Z"})
            return rows

        def fake_build_numeric(_artifacts, limit: int = 12):
            _ = limit
            charts = [
                {
                    "artifact_id": 101,
                    "title": "analytics/csv/contract__waveform-time-domain-analytics__rx-waveform.csv",
                    "download_url": "/artifact/101/raw?download=1",
                },
                {
                    "artifact_id": 201,
                    "title": "analytics/csv/contract__throughput-goodput-spectral-efficiency-analytics__goodput.csv",
                    "download_url": "/artifact/201/raw?download=1",
                },
                {
                    "artifact_id": 202,
                    "title": "analytics/csv/contract__throughput-goodput-spectral-efficiency-analytics__fairness-index-trend.csv",
                    "download_url": "/artifact/202/raw?download=1",
                },
                {
                    "artifact_id": 301,
                    "title": "reports/csv/contract__scenario-geometry-topology-layout__serving-cell-map.csv",
                    "download_url": "/artifact/301/raw?download=1",
                },
                {
                    "artifact_id": 401,
                    "title": "reports/csv/latency_cdf_plot.csv",
                    "download_url": "/artifact/401/raw?download=1",
                    "xaxis_title": "Latency Ms",
                    "yaxis_title": "Value",
                },
            ]
            allowed = {int(a["artifact_id"]) for a in _artifacts}
            return [chart for chart in charts if chart["artifact_id"] in allowed]

        dash.build_live_payload = fake_build_live
        dash.build_numeric_charts_from_artifacts = fake_build_numeric
        dash.fetch_run = lambda _run_id: {"run_id": _run_id, "status_text": "completed", "status_json": "{}"}
        dash.fetch_artifacts = fake_artifacts
        dash.sync_runtime_log_for_run = lambda _run_row: 0
        dash.extract_run_feature_policy = lambda _run_row: {}
        dash.contract_materializer.materialize_run_contract_artifacts = lambda *args, **kwargs: {"created": [], "skipped": True}

        unaccepted = [row for row in fake_artifacts(77) if row["artifact_id"] != 777]
        assert dash.select_primary_result_artifacts(unaccepted)[0] == [], (
            "A plot-browser fixture must not bypass atomic publication authority."
        )
        payload = dash.build_plot_browser_payload(77)
        assert payload["mode"] == "canonical_plus_published_artifacts"
        assert payload["suppressed_raw_count"] == 0, "Default plot browser must expose published raw chart/image artifacts."
        assert len(payload["items"]) >= len(payload["canonical_items"]), (
            "Merged plot browser payload must keep canonical family cards and append non-duplicate published artifacts."
        )

        item_map = {str(item["label"]): item for item in payload["items"]}
        assert item_map["sector_coverage_footprint"]["kind"] == "unavailable", (
            "A serving-cell topology map does not establish a measured sector coverage footprint."
        )
        assert item_map["rx_waveform"]["kind"] == "interactive", "Waveform family must prefer the truthful interactive chart over the duplicate SVG."
        assert item_map["rx_waveform"]["source"].endswith("__rx-waveform.csv")
        assert any("fairness index trend" in label for label in item_map), (
            "Non-canonical published chart artifacts must be visible by default."
        )

        assert item_map["throughput_vs_time"]["kind"] == "unavailable", (
            "Throughput-vs-time should stay unavailable when the run only published summary or cross-metric throughput charts."
        )
        assert item_map["goodput_vs_time"]["kind"] == "unavailable", (
            "Goodput-vs-time should stay unavailable when the run only published summary or retransmission-based goodput charts."
        )
        assert item_map["latency_cdf"]["kind"] == "interactive"
        assert item_map["latency_cdf"]["source"].endswith("latency_cdf_plot.csv")

        serving_map_items = [
            item for label, item in item_map.items()
            if "serving cell map" in label or label == "topology_map"
        ]
        assert serving_map_items, "Serving-cell topology artifacts must remain visible in the merged plot browser."

        def fake_cached_preview(artifact_id: int, _max_rows: int):
            if artifact_id == 999:
                return (
                    [
                        "run_id",
                        "chart_name",
                        "chart_mode",
                        "x_label",
                        "y_label",
                        "point_index",
                        "x_value",
                        "y_value",
                    ],
                    [
                        ["51", "tap power profile", "bar", "Metric bucket", "MeanValue", "1", "1.0", "6.9"],
                        ["51", "tap power profile", "bar", "Metric bucket", "MeanValue", "2", "2.0", "3.1"],
                    ],
                )
            if artifact_id == 1001:
                return (
                    [
                        "run_id",
                        "chart_name",
                        "chart_mode",
                        "x_label",
                        "y_label",
                        "point_index",
                        "x_value",
                        "y_value",
                    ],
                    [
                        ["51", "selected beam timeline", "line", "Time_s", "ServingBeamIndex", "1", "0.003", "20.0"],
                        ["51", "selected beam timeline", "line", "Time_s", "ServingBeamIndex", "2", "0.003", "7.0"],
                        ["51", "selected beam timeline", "line", "Time_s", "ServingBeamIndex", "3", "0.004", "24.0"],
                        ["51", "selected beam timeline", "line", "Time_s", "ServingBeamIndex", "4", "0.004", "19.0"],
                    ],
                )
            if artifact_id == 1002:
                return (
                    [
                        "run_id",
                        "chart_name",
                        "series_name",
                        "x_value",
                        "y_value",
                        "label",
                        "source_table_logical_path",
                    ],
                    [
                        ["51", "BS/sector/UE topology scatter plot", "Sites", "72.999217", "19.122164", "1", "reports/csv/sites.csv"],
                        ["51", "BS/sector/UE topology scatter plot", "Sites", "73.004921", "19.122163", "2", "reports/csv/sites.csv"],
                        ["51", "BS/sector/UE topology scatter plot", "UEs", "73.000359", "19.122399", "3", "reports/csv/live_rsrp_serving_trace.csv"],
                        ["51", "BS/sector/UE topology scatter plot", "UEs", "73.001042", "19.120963", "5", "reports/csv/live_rsrp_serving_trace.csv"],
                    ],
                )
            raise AssertionError(f"Unexpected artifact_id: {artifact_id}")

        dash.load_cached_csv_preview = fake_cached_preview
        dash.artifact_url = lambda artifact_id, download=False: f"/artifact/{artifact_id}/raw{'?download=1' if download else ''}"
        chart = dash.build_numeric_chart_from_artifact(
            {
                "artifact_id": 999,
                "logical_path": "analytics/csv/contract__channel-estimation-propagation-analytics__tap-power-profile.csv",
            }
        )
        assert chart is not None
        assert chart["xaxis_title"] == "Metric bucket"
        assert chart["yaxis_title"] == "MeanValue"
        assert chart["series"][0]["trace_type"] == "bar"

        beam_chart = dash.build_numeric_chart_from_artifact(
            {
                "artifact_id": 1001,
                "logical_path": "reports/csv/contract__mobility-access-cell-selection-reselection-handover__selected-beam-timeline.csv",
            }
        )
        assert beam_chart is not None
        assert beam_chart["series"][0]["mode"] == "heatmap"
        assert beam_chart["yaxis_title"] == "ServingBeamIndex"

        topology_chart = dash.build_numeric_chart_from_artifact(
            {
                "artifact_id": 1002,
                "logical_path": "reports/csv/contract__scenario-geometry-topology-layout__bs-sector-ue-topology-scatter-plot.csv",
            }
        )
        assert topology_chart is not None
        assert topology_chart["xaxis_title"] == "Longitude"
        assert topology_chart["yaxis_title"] == "Latitude"
        assert topology_chart["layout_hints"]["axis_equal"] is True
        assert topology_chart["series"][0]["mode"].startswith("markers")
        assert topology_chart["series"][1]["mode"] == "markers"
    finally:
        dash.build_live_payload = orig_build_live
        dash.build_numeric_charts_from_artifacts = orig_build_numeric
        dash.load_cached_csv_preview = orig_load_cached
        dash.artifact_url = orig_artifact_url
        dash.fetch_run = orig_fetch_run
        dash.fetch_artifacts = orig_fetch_artifacts
        dash.sync_runtime_log_for_run = orig_sync_runtime_log
        dash.extract_run_feature_policy = orig_extract_feature_policy
        dash.contract_materializer.materialize_run_contract_artifacts = orig_materialize


if __name__ == "__main__":
    main()
