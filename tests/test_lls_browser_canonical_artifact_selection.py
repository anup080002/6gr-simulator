from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    orig_load_small = dash.load_small_csv_rows
    try:
        canonical_and_legacy = [
            {"logical_path": "reports/csv/live_control_gating_summary.csv", "artifact_id": 1, "byte_size": 128, "artifact_kind": "table_csv"},
            {"logical_path": "control/csv/control_gating_summary.csv", "artifact_id": 2, "byte_size": 256, "artifact_kind": "table_csv"},
            {"logical_path": "reports/csv/live_control_gating_state.csv", "artifact_id": 3, "byte_size": 128, "artifact_kind": "table_csv"},
            {"logical_path": "control/csv/control_gating_state.csv", "artifact_id": 4, "byte_size": 256, "artifact_kind": "table_csv"},
            {"logical_path": "reports/csv/live_stage_status.csv", "artifact_id": 5, "byte_size": 128, "artifact_kind": "table_csv"},
            {"logical_path": "air_interface/reports/csv/live_stage_status.csv", "artifact_id": 6, "byte_size": 256, "artifact_kind": "table_csv"},
        ]

        def fake_load_small_canonical_empty(artifacts_arg, logical_path, *, max_rows=64):
            if logical_path in {
                "reports/csv/live_control_gating_summary.csv",
                "reports/csv/live_control_gating_state.csv",
                "reports/csv/live_stage_status.csv",
            }:
                return []
            if logical_path == "control/csv/control_gating_summary.csv":
                return [{"ControlMode": "legacy_mirror"}]
            if logical_path == "control/csv/control_gating_state.csv":
                return [{"SchedulingEligibility": "1"}]
            if logical_path == "air_interface/reports/csv/live_stage_status.csv":
                return [{"DLTrialsReady": "1"}]
            return []

        dash.load_small_csv_rows = fake_load_small_canonical_empty

        rows, meta = dash.select_canonical_csv_rows(
            canonical_and_legacy,
            "reports/csv/live_control_gating_summary.csv",
            legacy_paths=["control/csv/control_gating_summary.csv"],
            max_rows=4,
            owner_kind="live_control_gating_summary",
        )
        assert rows == [], "browser must not hop to the legacy control summary when the canonical artifact exists but is empty"
        assert meta["selection_status"] == "canonical_empty", "canonical empty state must be preserved explicitly"
        assert not meta["fallback_used"], "canonical empty selection must not masquerade as fallback"

        run_row = {"run_id": 501, "status_text": "completed", "config_json": "{}"}
        runtime_context = dash.extract_runtime_context(run_row, canonical_and_legacy)
        selection = runtime_context["artifact_selection"]
        assert runtime_context["control_summary"] == {}, "live payload must not populate control summary from a legacy mirror when canonical exists"
        assert runtime_context["control_state_preview"] == [], "live payload must not populate control state from a legacy mirror when canonical exists"
        assert str(runtime_context["stage"].get("DLTrialsReady") or "").strip() != "1", (
            "live payload must not import legacy stage-status row content when the canonical stage report exists but is empty"
        )
        assert selection["live_control_gating_summary"]["selection_status"] == "canonical_empty"
        assert selection["live_control_gating_state"]["selection_status"] == "canonical_empty"
        assert selection["live_stage_status"]["selection_status"] == "canonical_empty"
        assert any("not silently replacing these with legacy mirrors" in note for note in runtime_context["notes"]), (
            "browser notes must explain that canonical-empty artifacts are not replaced with legacy mirrors"
        )

        def fake_load_small_canonical_present(artifacts_arg, logical_path, *, max_rows=64):
            if logical_path == "reports/csv/live_control_gating_summary.csv":
                return [{"ControlMode": "canonical_runtime", "Source": "reports/csv/live_control_gating_summary.csv"}]
            if logical_path == "control/csv/control_gating_summary.csv":
                return [{"ControlMode": "legacy_mirror", "Source": "control/csv/control_gating_summary.csv"}]
            return []

        dash.load_small_csv_rows = fake_load_small_canonical_present

        rows, meta = dash.select_canonical_csv_rows(
            canonical_and_legacy,
            "reports/csv/live_control_gating_summary.csv",
            legacy_paths=["control/csv/control_gating_summary.csv"],
            max_rows=4,
            owner_kind="live_control_gating_summary",
        )
        assert rows and rows[0]["ControlMode"] == "canonical_runtime", (
            "browser canonical selector must use the live canonical control summary when both canonical and legacy mirrors exist"
        )
        assert meta["selection_status"] == "canonical", "canonical presence must be labeled as canonical, not fallback"
        assert not meta["fallback_used"], "canonical selection must not set fallback_used"
        assert meta["selected_logical_path"] == "reports/csv/live_control_gating_summary.csv"

        legacy_only = [
            {"logical_path": "control/csv/control_gating_summary.csv", "artifact_id": 20, "byte_size": 256, "artifact_kind": "table_csv"},
        ]

        def fake_load_small_legacy_only(artifacts_arg, logical_path, *, max_rows=64):
            if logical_path == "control/csv/control_gating_summary.csv":
                return [{"ControlMode": "legacy_mirror"}]
            return []

        dash.load_small_csv_rows = fake_load_small_legacy_only

        rows, meta = dash.select_canonical_csv_rows(
            legacy_only,
            "reports/csv/live_control_gating_summary.csv",
            legacy_paths=["control/csv/control_gating_summary.csv"],
            max_rows=4,
            owner_kind="live_control_gating_summary",
        )
        assert rows and rows[0]["ControlMode"] == "legacy_mirror", "legacy data may be used only when the canonical artifact is absent"
        assert meta["selection_status"] == "legacy_fallback", "legacy usage must be labeled explicitly"
        assert meta["fallback_used"], "legacy usage must set fallback_used"

        ui_items = [
            {
                "logical_path": "control/csv/pdcch_trials.csv",
                "artifact_id": 31,
                "byte_size": 800,
                "created_utc": "2026-04-10T00:00:01Z",
                "section": "control",
                "display_rank": dash.result_artifact_display_priority("control", "control/csv/pdcch_trials.csv"),
            },
            {
                "logical_path": "air_interface/csv/pdcch_trials.csv",
                "artifact_id": 32,
                "byte_size": 128,
                "created_utc": "2026-04-10T00:00:00Z",
                "section": "control",
                "display_rank": dash.result_artifact_display_priority("control", "air_interface/csv/pdcch_trials.csv"),
            },
            {
                "logical_path": "control/csv/control_gating_summary.csv",
                "artifact_id": 33,
                "byte_size": 900,
                "created_utc": "2026-04-10T00:00:01Z",
                "section": "control",
                "display_rank": dash.result_artifact_display_priority("control", "control/csv/control_gating_summary.csv"),
            },
            {
                "logical_path": "reports/csv/live_control_gating_summary.csv",
                "artifact_id": 34,
                "byte_size": 100,
                "created_utc": "2026-04-10T00:00:00Z",
                "section": "control",
                "display_rank": dash.result_artifact_display_priority("control", "reports/csv/live_control_gating_summary.csv"),
            },
            {
                "logical_path": "air_interface/reports/csv/live_stage_status.csv",
                "artifact_id": 35,
                "byte_size": 900,
                "created_utc": "2026-04-10T00:00:01Z",
                "section": "debug",
                "display_rank": dash.result_artifact_display_priority("debug", "air_interface/reports/csv/live_stage_status.csv"),
            },
            {
                "logical_path": "reports/csv/live_stage_status.csv",
                "artifact_id": 36,
                "byte_size": 100,
                "created_utc": "2026-04-10T00:00:00Z",
                "section": "debug",
                "display_rank": dash.result_artifact_display_priority("debug", "reports/csv/live_stage_status.csv"),
            },
        ]
        deduped = dash.dedupe_table_descriptors_for_ui(ui_items)
        paths = {str(item["logical_path"]) for item in deduped}
        assert "air_interface/csv/pdcch_trials.csv" in paths, "results UI must keep the canonical raw control trial when both canonical and legacy mirrors exist"
        assert "control/csv/pdcch_trials.csv" not in paths, "results UI must not prefer the legacy raw control trial mirror"
        assert "reports/csv/live_control_gating_summary.csv" in paths, "results UI must keep the canonical live control gating summary"
        assert "control/csv/control_gating_summary.csv" not in paths, "results UI must not prefer the legacy control summary mirror"
        assert "reports/csv/live_stage_status.csv" in paths, "results UI must keep the canonical live stage status report"
        assert "air_interface/reports/csv/live_stage_status.csv" not in paths, "results UI must not prefer the legacy stage-status mirror"
    finally:
        dash.load_small_csv_rows = orig_load_small


if __name__ == "__main__":
    main()
