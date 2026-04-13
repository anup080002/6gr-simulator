from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    artifacts = [
        {"logical_path": "reports/csv/runtime_operating_mode.csv", "artifact_id": 1, "byte_size": 128, "artifact_kind": "table_csv"},
        {"logical_path": "packet_flow/csv/live_pucch_grants.csv", "artifact_id": 2, "byte_size": 256, "artifact_kind": "table_csv"},
        {"logical_path": "air_interface/csv/pbch_trials.csv", "artifact_id": 3, "byte_size": 256, "artifact_kind": "table_csv"},
        {"logical_path": "air_interface/csv/prach_trials.csv", "artifact_id": 4, "byte_size": 256, "artifact_kind": "table_csv"},
        {"logical_path": "air_interface/csv/pdcch_trials.csv", "artifact_id": 5, "byte_size": 256, "artifact_kind": "table_csv"},
        {"logical_path": "air_interface/csv/srs_trials.csv", "artifact_id": 6, "byte_size": 256, "artifact_kind": "table_csv"},
        {"logical_path": "air_interface/csv/trs_trials.csv", "artifact_id": 7, "byte_size": 256, "artifact_kind": "table_csv"},
    ]
    runtime_rows = [
        {
            "Direction": "DL",
            "PUCCHMode": "runtime_coupled_pucch_grant_waveform_execution",
            "ControlIntegrationMode": "runtime_control_access_tracking_state_gated",
        }
    ]
    pucch_grant_rows = [
        {
            "PUCCHGrantId": "pucchgrant:fbdir=DL:due=5:src=1:ue=1:rnti=320:harq=0:cell=1",
            "UEID": "1",
            "BaseStationID": "1",
            "Frame": "1",
            "Slot": "5",
            "PUCCHResourceId": "pucch:cell=1:slot=5:rnti=320:reqfmt=2:resfmt=1:prb=3:1:sym=10:4",
            "UCIType": "harq_ack",
            "PUCCHGrantState": "waveform_observed_feedback_applied",
            "RuntimeStateConsumer": "HARQEntity.onFeedback",
            "StateChangeApplied": "1",
            "InterferenceMode": "full_per_link_channel_waveform_sum",
        }
    ]
    control_trial_rows = [
        {
            "SignalFamily": "PBCH",
            "SourceClassification": "active_integrated",
            "RuntimeMaterializationStatus": "active_integrated_waveform_cell_search_gate",
            "ControlGatingEffect": "cell_acquisition_gate",
            "Status": "PASS",
        }
    ]

    orig_load_small = dash.load_small_csv_rows
    try:
        def fake_load_small(artifacts_arg, logical_path, *, max_rows=64):
            if logical_path == "reports/csv/runtime_operating_mode.csv":
                return runtime_rows
            if logical_path == "packet_flow/csv/live_pucch_grants.csv":
                return pucch_grant_rows
            if logical_path.startswith("air_interface/csv/") and logical_path.endswith("_trials.csv"):
                rows = [dict(control_trial_rows[0])]
                rows[0]["SignalFamily"] = logical_path.split("/")[-1].split("_")[0].upper()
                return rows
            return []

        dash.load_small_csv_rows = fake_load_small
        run_row = {"run_id": 601, "status_text": "completed", "config_json": "{}"}
        runtime_context = dash.extract_runtime_context(run_row, artifacts)
        selection = runtime_context["artifact_selection"]["scheduler_grants"]["pucch"]
        assert selection["selection_status"] == "canonical", "browser must read the canonical live_pucch_grants artifact when present"
        assert runtime_context["pucch_grants"][0]["PUCCHGrantState"] == "waveform_observed_feedback_applied", (
            "browser runtime context must expose canonical PUCCH grant rows"
        )
        previews = runtime_context["control_trial_previews"]
        assert previews["pbch_trials"][0]["SourceClassification"] == "active_integrated", (
            "browser runtime context must expose canonical raw control/reference-signal trial previews"
        )
        assert runtime_context["artifact_selection"]["raw_control_trials"]["pbch_trials"]["selection_status"] == "canonical", (
            "browser raw control/reference selection must prefer canonical air_interface artifacts"
        )
        assert any("explicit runtime PUCCH grant/resource rows" in note for note in runtime_context["notes"]), (
            "browser notes must describe the explicit waveform-backed PUCCH grant path honestly"
        )
        assert any("Canonical PUCCH grant trace is present" in note for note in runtime_context["notes"]), (
            "browser notes must disclose the canonical PUCCH grant artifact when present"
        )
    finally:
        dash.load_small_csv_rows = orig_load_small


if __name__ == "__main__":
    main()
