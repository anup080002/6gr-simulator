from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    artifacts = [
        {"logical_path": "meta/scenario_config_resolved.json", "artifact_id": 1, "byte_size": 64, "created_utc": "2026-04-09T00:00:00Z", "artifact_kind": "json"},
        {"logical_path": "meta/scenario_config_resolved.yaml", "artifact_id": 2, "byte_size": 64, "created_utc": "2026-04-09T00:00:00Z", "artifact_kind": "yaml"},
        {"logical_path": "meta/scenario_source_chain.csv", "artifact_id": 3, "byte_size": 64, "created_utc": "2026-04-09T00:00:00Z", "artifact_kind": "table_csv"},
        {"logical_path": "reports/csv/config_roundtrip_verification.csv", "artifact_id": 4, "byte_size": 256, "created_utc": "2026-04-09T00:00:00Z", "artifact_kind": "table_csv"},
        {"logical_path": "reports/csv/browser_runtime_db_consistency.csv", "artifact_id": 5, "byte_size": 256, "created_utc": "2026-04-09T00:00:00Z", "artifact_kind": "table_csv"},
        {"logical_path": "reports/csv/summary_vs_raw_consistency.csv", "artifact_id": 6, "byte_size": 256, "created_utc": "2026-04-09T00:00:00Z", "artifact_kind": "table_csv"},
        {"logical_path": "reports/csv/value_source_audit.csv", "artifact_id": 7, "byte_size": 256, "created_utc": "2026-04-09T00:00:00Z", "artifact_kind": "table_csv"},
    ]
    run_row = {
        "run_id": 41,
        "status_text": "completed",
        "config_json": '{"lls6g":{"submittedScenarioConfig":{"deployment_topology":{"inter_site_distance":640}}}}',
    }

    snapshot = dash.build_config_snapshot_context(run_row, artifacts)
    for key in (
        "config_roundtrip_verification",
        "browser_runtime_db_consistency",
        "summary_vs_raw_consistency",
        "value_source_audit",
    ):
        assert key in snapshot["downloads"], f"browser config snapshot downloads must expose {key}"

    roundtrip_rows = [
        {
            "ParameterName": "deployment_topology.inter_site_distance",
            "BrowserSubmittedValue": "640",
            "RuntimeOverlayValue": "640",
            "ResolvedMATLABValue": "640",
            "DBSnapshotValue": "640",
            "ExportedCSVValue": "640",
            "BrowserDisplayedValue": "640",
            "ConsistencyStatus": "consistent",
        }
        ,
        {
            "ParameterName": "deployment_topology.layout_type",
            "BrowserSubmittedValue": "hex_grid",
            "RuntimeOverlayValue": "hex_grid",
            "ResolvedMATLABValue": "hex_grid",
            "RuntimeEvidenceArtifact": "reports/csv/deployment_layout_reference.csv",
            "RuntimeEvidenceField": "LayoutType",
            "RuntimeEvidenceValue": "rect_grid",
            "ConsistencyStatus": "mismatch",
            "ConsistencyNotes": "runtime_evidence_diverges_from_resolved_runtime_value",
        }
    ]
    browser_db_rows = [
        {
            "ParameterName": "deployment_topology.inter_site_distance",
            "DBSnapshotValue": "640",
            "ExportedCSVValue": "640",
            "BrowserDisplayedValue": "640",
            "ConsistencyStatus": "consistent",
        }
    ]
    summary_vs_raw_rows = [
        {
            "SummaryField": "EffectiveDLTrialCount",
            "SummaryValue": "1",
            "RawDerivedValue": "1",
            "ConsistencyStatus": "consistent",
        }
    ]
    value_source_rows = [
        {
            "FieldName": "ConfiguredSNR_dB",
            "ObservedValue": "8",
            "ValueSource": "configured_reference_metadata",
            "ValueRole": "configured",
            "ValueStatus": "OK",
            "ConsistencyStatus": "observed",
        }
    ]

    orig_load_small = dash.load_small_csv_rows
    orig_load_first = dash.load_first_available_csv_rows
    try:
        def fake_load_small(artifacts_arg, logical_path, *, max_rows=64):
            if logical_path == "reports/csv/config_roundtrip_verification.csv":
                return roundtrip_rows
            if logical_path == "reports/csv/browser_runtime_db_consistency.csv":
                return browser_db_rows
            if logical_path == "reports/csv/summary_vs_raw_consistency.csv":
                return summary_vs_raw_rows
            if logical_path == "reports/csv/value_source_audit.csv":
                return value_source_rows
            if logical_path == "reports/csv/runtime_operating_mode.csv":
                return []
            return []

        dash.load_small_csv_rows = fake_load_small
        dash.load_first_available_csv_rows = lambda artifacts_arg, logical_paths, *, max_rows=64: []
        runtime_context = dash.extract_runtime_context(run_row, artifacts)
        roundtrip = runtime_context["roundtrip_artifacts"]
        assert roundtrip["config_roundtrip_verification"][0]["ParameterName"] == "deployment_topology.inter_site_distance"
        assert roundtrip["browser_runtime_db_consistency"][0]["ConsistencyStatus"] == "consistent"
        assert roundtrip["summary_vs_raw_consistency"][0]["SummaryField"] == "EffectiveDLTrialCount"
        assert roundtrip["value_source_audit"][0]["FieldName"] == "ConfiguredSNR_dB"
        assert runtime_context["roundtrip_artifacts"]["summary"]["config_roundtrip_rows"] == 2
        assert runtime_context["roundtrip_artifacts"]["summary"]["config_roundtrip_mismatches"] == 1
        assert roundtrip["mismatch_rows"]["config_roundtrip_verification"][0]["ParameterName"] == "deployment_topology.layout_type"
        assert any("Roundtrip verifier artifacts" in note for note in runtime_context["notes"])
    finally:
        dash.load_small_csv_rows = orig_load_small
        dash.load_first_available_csv_rows = orig_load_first


if __name__ == "__main__":
    main()
