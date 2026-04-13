from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    artifacts = [
        {"logical_path": "reports/csv/runtime_operating_mode.csv", "artifact_id": 1, "byte_size": 128, "artifact_kind": "table_csv"},
        {"logical_path": "air_interface/csv/trs_trials.csv", "artifact_id": 2, "byte_size": 256, "artifact_kind": "table_csv"},
    ]
    runtime_rows = [
        {
            "Direction": "DL",
            "TRSMode": "runtime_shared_receiver_tracking_state_gate",
            "TRSGatingActive": "1",
            "TRSRuntimeConsumer": "shared_receiver_tracking_state",
            "TRSInfluencedDecision": "1",
            "TRSInfluenceDefinition": "shared_receiver_tracking_state_feeds_scheduler_eligibility_when_trs_gating_active",
            "TRSReceiverIntegrationStatus": "integrated_shared_tracking_object",
            "TRSReceiverIntegrationBlocker": "",
        }
    ]
    trs_rows = [
        {
            "Frame": "1",
            "Slot": "5",
            "TRSValidityState": "valid",
            "TrackingEligibility": "1",
            "TRSRuntimeConsumer": "shared_receiver_tracking_state",
            "TRSInfluencedDecision": "1",
            "TRSProcessed": "1",
            "TRSReceiverIntegrationStatus": "integrated_shared_tracking_object",
        }
    ]

    orig_load_small = dash.load_small_csv_rows
    try:
        def fake_load_small(artifacts_arg, logical_path, *, max_rows=64):
            if logical_path == "reports/csv/runtime_operating_mode.csv":
                return runtime_rows
            if logical_path == "air_interface/csv/trs_trials.csv":
                return trs_rows
            return []

        dash.load_small_csv_rows = fake_load_small
        run_row = {"run_id": 611, "status_text": "completed", "config_json": "{}"}
        runtime_context = dash.extract_runtime_context(run_row, artifacts)
        assert runtime_context["truth_modes"]["trs_runtime_consumer"] == "shared_receiver_tracking_state", (
            "browser runtime truth modes must surface the canonical TRS consumer from runtime_operating_mode.csv"
        )
        assert runtime_context["truth_modes"]["trs_receiver_integration_status"] == "integrated_shared_tracking_object", (
            "browser runtime truth modes must surface receiver tracking integration when runtime evidence exists"
        )
        assert runtime_context["trs_trials_preview"][0]["TRSValidityState"] == "valid", (
            "browser runtime context must include a canonical TRS trials preview when present"
        )
        assert any("TRS runtime consumer: shared_receiver_tracking_state." in note for note in runtime_context["notes"]), (
            "browser notes must disclose the real TRS runtime consumer"
        )
        assert not any("TRS receiver integration blocker:" in note for note in runtime_context["notes"]), (
            "browser notes must not emit an obsolete TRS blocker after receiver tracking integration"
        )
    finally:
        dash.load_small_csv_rows = orig_load_small


if __name__ == "__main__":
    main()
