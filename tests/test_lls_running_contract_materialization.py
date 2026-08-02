from __future__ import annotations

import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    run_row = {
        "run_id": 44,
        "status_text": "running",
        "updated_utc": "2026-04-21T11:05:00+00:00",
    }
    artifacts = [
        {
            "artifact_id": 10,
            "logical_path": "reports/csv/contract_materialization_manifest.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
            "byte_size": 512,
        },
        {
            "artifact_id": 11,
            "logical_path": "reports/image/contract__scheduler-mac-queue-qos-power-control-uci-flow__scheduled-prbs-per-ue-over-time.png",
            "artifact_kind": "image_png",
            "mime_type": "image/png",
            "byte_size": 1024,
        },
        {
            "artifact_id": 12,
            "logical_path": "packet_flow/csv/live_dl_scheduler_grants.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
            "byte_size": 4096,
        },
    ]
    artifacts_with_current_coverage = [
        *artifacts,
        {
            "artifact_id": 13,
            "logical_path": "reports/csv/contract_materialization_coverage.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
            "byte_size": 1024,
        },
    ]
    assert not dash.contract_materialization_is_current(
        artifacts_with_current_coverage,
        run_status="running",
    ), "running runs must refresh contract materialization because source tables can grow after early coverage rows"
    original_fetch_artifact_meta = dash.fetch_artifact_meta
    original_source_high_watermark = dash.contract_materializer._source_artifact_high_watermark
    try:
        dash.fetch_artifact_meta = lambda _artifact_id: {
            "metadata_json": json.dumps({"source_artifact_high_watermark": 10})
        }
        dash.contract_materializer._source_artifact_high_watermark = lambda _artifacts, _db_factory: 11
        assert not dash.contract_materialization_is_current(
            artifacts_with_current_coverage,
            run_status="aborted_live_integrity_failure",
        ), "terminal/aborted runs must rematerialize when newer source artifacts arrived after the manifest"
    finally:
        dash.fetch_artifact_meta = original_fetch_artifact_meta
        dash.contract_materializer._source_artifact_high_watermark = original_source_high_watermark

    calls: list[tuple[int, int]] = []
    original = {
        "fetch_run": dash.fetch_run,
        "sync_runtime_log_for_run": dash.sync_runtime_log_for_run,
        "fetch_artifacts": dash.fetch_artifacts,
        "extract_run_feature_policy": dash.extract_run_feature_policy,
        "materialize_run_contract_artifacts": dash.contract_materializer.materialize_run_contract_artifacts,
        "fetch_logs": dash.fetch_logs,
        "summarize_artifacts": dash.summarize_artifacts,
        "count_logs": dash.count_logs,
        "extract_runtime_context": dash.extract_runtime_context,
        "build_output_coverage_context": dash.build_output_coverage_context,
        "filter_public_artifacts_for_policy": dash.filter_public_artifacts_for_policy,
        "build_status_issue_registry_rows": dash.build_status_issue_registry_rows,
        "artifact_sort_key": dash.artifact_sort_key,
        "build_artifact_descriptor": dash.build_artifact_descriptor,
        "dedupe_table_descriptors_for_ui": dash.dedupe_table_descriptors_for_ui,
        "classify_result_section": dash.classify_result_section,
        "build_live_summary": dash.build_live_summary,
        "build_numeric_charts_from_artifacts": dash.build_numeric_charts_from_artifacts,
        "build_output_contract_surface": dash.build_output_contract_surface,
        "compact_run_row": dash.compact_run_row,
        "extract_metric_cards": dash.extract_metric_cards,
        "build_activity_series": dash.build_activity_series,
        "build_runtime_progress_charts": dash.build_runtime_progress_charts,
        "build_timing_payload": dash.build_timing_payload,
        "build_map_payload": dash.build_map_payload,
        "build_metric_explorer_payload": dash.build_metric_explorer_payload,
        "build_debug_payload": dash.build_debug_payload,
        "parse_status_json": dash.parse_status_json,
    }
    old_cache = dict(dash.CACHED_PAYLOAD_VERSION)
    old_live_cache = dict(dash.LIVE_PAYLOAD_CACHE)
    try:
        dash.CACHED_PAYLOAD_VERSION.clear()
        dash.LIVE_PAYLOAD_CACHE.clear()
        dash.fetch_run = lambda run_id: dict(run_row) if int(run_id) == 44 else None
        dash.sync_runtime_log_for_run = lambda _run_row: 0
        dash.fetch_artifacts = lambda run_id: list(artifacts)
        dash.extract_run_feature_policy = lambda _run_row: {}

        def fake_materialize(run_row_arg, artifacts_arg, **_kwargs):
            calls.append((int(run_row_arg["run_id"]), len(artifacts_arg)))
            return {"created": [], "coverage": {}, "manifest_path": "reports/csv/contract_materialization_manifest.csv", "coverage_path": "reports/csv/contract_materialization_coverage.csv"}

        dash.contract_materializer.materialize_run_contract_artifacts = fake_materialize
        dash.fetch_logs = lambda run_id, limit=0, descending=False: []
        dash.summarize_artifacts = lambda _artifacts: {"artifacts_total": len(_artifacts), "tables_total": len(_artifacts), "images_total": 1, "bytes_total": 5632}
        dash.count_logs = lambda run_id: 0
        dash.extract_runtime_context = lambda _run_row, _artifacts: {}
        dash.build_output_coverage_context = lambda _artifacts: {"issue_registry": [], "dashboard_cards": []}
        dash.filter_public_artifacts_for_policy = lambda _artifacts, _policy: list(_artifacts)
        dash.build_status_issue_registry_rows = lambda _run_row, _runtime_context: []
        dash.artifact_sort_key = lambda art: int(art.get("artifact_id") or 0)
        dash.build_artifact_descriptor = lambda art: {
            "artifact_id": art["artifact_id"],
            "logical_path": art["logical_path"],
            "artifact_kind": art["artifact_kind"],
            "mime_type": art["mime_type"],
            "section": "summary",
        }
        dash.dedupe_table_descriptors_for_ui = lambda items: list(items)
        dash.classify_result_section = lambda path: "summary"
        dash.build_live_summary = lambda _run_row, _artifacts, _runtime_context: {}
        dash.build_numeric_charts_from_artifacts = lambda _artifacts, limit=0: []
        dash.build_output_contract_surface = lambda _run_row, _artifacts, _numeric_tabs, _summary_tabs, _output_coverage: {}
        dash.compact_run_row = lambda _run_row, _artifacts: {"run_id": 44, "status_text": "running"}
        dash.extract_metric_cards = lambda _run_row, _artifacts, _runtime_context: []
        dash.build_activity_series = lambda _records, _label: []
        dash.build_runtime_progress_charts = lambda _logs, _status: []
        dash.build_timing_payload = lambda _artifacts: {}
        dash.build_map_payload = lambda _run_id, _artifacts: {}
        dash.build_metric_explorer_payload = lambda _artifacts, _summary: {}
        dash.build_debug_payload = lambda _run_row, _artifacts, _logs: {}
        dash.parse_status_json = lambda _run_row: {}

        payload = dash.build_live_payload(44)
        assert payload["run"]["status_text"] == "running"
        assert calls == [(44, len(artifacts))], "running payloads with raw tables must refresh contract materialization even when manifest/images already exist"
    finally:
        for name, value in original.items():
            if name == "materialize_run_contract_artifacts":
                dash.contract_materializer.materialize_run_contract_artifacts = value
            else:
                setattr(dash, name, value)
        dash.CACHED_PAYLOAD_VERSION.clear()
        dash.CACHED_PAYLOAD_VERSION.update(old_cache)
        dash.LIVE_PAYLOAD_CACHE.clear()
        dash.LIVE_PAYLOAD_CACHE.update(old_live_cache)


if __name__ == "__main__":
    main()
