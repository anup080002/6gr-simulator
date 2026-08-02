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
            artifact("prach/csv/prach_trials.csv", artifact_id=5),
            artifact("reports/csv/mac_harq_trials.csv", artifact_id=6),
            artifact("reports/image/channel_geometry.png", "image/png", 7),
        ],
        "completed",
    )
    by_id = {row["component_id"]: row for row in rows}
    assert len(rows) == 20
    assert by_id["prach_rach"]["status"] == "evidence_available"
    assert by_id["prach_rach"]["csv_count"] == 1
    assert by_id["prach_rach"]["image_count"] == 1
    assert by_id["prach_rach"]["legacy_svg_count"] == 1
    assert by_id["prach_rach"]["planned_folder"] == "prach"
    assert "pass" not in by_id["prach_rach"]["status"]
    assert by_id["l3"]["status"] == "not_published"
    assert by_id["mac_harq_scheduler"]["csv_count"] == 1
    assert by_id["channel"]["image_count"] == 1
    assert dashboard.is_component_view_artifact_path("prach/csv/prach_trials.csv")
    assert not dashboard.is_component_view_artifact_path(
        "control/csv/prach_trials.csv"
    )


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


def test_component_view_detection_does_not_hide_canonical_roots() -> None:
    assert not dashboard.is_component_view_artifact_path(
        "air_interface/csv/dl_pdsch_trials.csv"
    )
    assert not dashboard.is_component_view_artifact_path(
        "system/image/system_topology.png"
    )
    assert dashboard.is_component_view_artifact_path(
        "pdsch/image/dl_bler_vs_snr.png"
    )


def test_manifest_hides_mirrors_from_primary_gallery_only() -> None:
    rows = [
        artifact("air_interface/csv/dl_pdsch_trials.csv", artifact_id=1),
        artifact("pdsch/csv/dl_pdsch_trials.csv", artifact_id=2),
    ]
    assert dashboard.prefer_canonical_artifacts_over_component_views(rows, None) == rows
    filtered = dashboard.prefer_canonical_artifacts_over_component_views(
        rows, artifact("reports/csv/component_artifact_publication_manifest.csv", artifact_id=3)
    )
    assert [row["artifact_id"] for row in filtered] == [1]
