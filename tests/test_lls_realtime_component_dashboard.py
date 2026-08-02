from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps"))

import lls_web_dashboard as dashboard  # noqa: E402


def artifact(path: str, mime_type: str = "text/csv", artifact_id: int = 1) -> dict:
    return {
        "artifact_id": artifact_id,
        "logical_path": path,
        "mime_type": mime_type,
        "artifact_kind": "table_csv" if path.endswith(".csv") else "image",
        "created_utc": "2026-08-02T00:00:00Z",
        "byte_size": 10,
    }


def test_component_dashboard_separates_raster_from_legacy_svg() -> None:
    rows = dashboard.build_realtime_component_dashboard(
        [
            artifact("air_interface/csv/prach_trials.csv", artifact_id=1),
            artifact("reports/image/prach_correlation.png", "image/png", 2),
            artifact("reports/image/prach_legacy.svg", "image/svg+xml", 3),
            artifact("air_interface/csv/dl_pdsch_trials.csv", artifact_id=4),
        ],
        "completed",
    )
    by_id = {row["component_id"]: row for row in rows}
    assert len(rows) == 14
    assert by_id["prach_rach"]["status"] == "evidence_available"
    assert by_id["prach_rach"]["csv_count"] == 1
    assert by_id["prach_rach"]["image_count"] == 1
    assert by_id["prach_rach"]["legacy_svg_count"] == 1
    assert by_id["prach_rach"]["planned_folder"] == "prach"
    assert "pass" not in by_id["prach_rach"]["status"]
    assert by_id["l3"]["status"] == "not_published"


def test_ue_status_merges_control_and_performance_without_upgrading_fidelity() -> None:
    metric_explorer = {
        "ue_summaries": {
            "1": {
                "ueid": 1,
                "dl_bler": 0.0,
                "ul_bler": 0.25,
                "dl_mean_measured_sinr_dB": 12.5,
                "ul_mean_measured_sinr_dB": 7.0,
                "source_table": "reports/csv/live_user_performance_snapshot.csv",
                "fidelity_level": "abstraction_level",
            }
        }
    }
    runtime = {
        "control_state_preview": [
            {
                "UEIndex": 1,
                "ServingCell": 3,
                "SchedulingEligibility": 1,
                "AccessState": "connected",
                "LastPDCCHStatus": "control_ok",
                "SRSValidityState": "valid",
                "CSIValidityState": "fresh_srs",
                "TRSValidityState": "valid",
            }
        ]
    }
    rows = dashboard.build_realtime_ue_status(metric_explorer, runtime)
    assert len(rows) == 1
    assert rows[0]["ue_id"] == "1"
    assert rows[0]["health"] == "attention"
    assert rows[0]["scheduling_eligible"] is True
    assert rows[0]["performance_fidelity"] == "abstraction_level"
    assert rows[0]["control_source"] == "reports/csv/live_control_gating_state.csv"


def test_runtime_log_component_annotation_preserves_original_message() -> None:
    source = [{"level_str": "INFO", "message_text": "PDCCH DCI decoded for UE 2"}]
    rows = dashboard.annotate_realtime_logs(source)
    assert rows[0]["component"] == "pdcch"
    assert rows[0]["message_text"] == source[0]["message_text"]
    assert "component" not in source[0]
