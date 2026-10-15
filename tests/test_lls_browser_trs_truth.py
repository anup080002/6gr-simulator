from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def test_trs_runtime_truth_preview() -> None:
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
            "StrictOk": "0",
            "Status": "FAIL",
            "TRSRuntimeConsumer": "shared_receiver_tracking_state",
            "TRSInfluencedDecision": "1",
            "TRSProcessed": "1",
            "TRSReceiverIntegrationStatus": "integrated_shared_tracking_object",
        }
    ]

    orig_load_small = dash.load_small_csv_rows
    trs_rows[0].update(ChannelNMSEReferencePlane="recorded_receiver_clock",
                       ChannelNMSEQualificationMode="independent_complex_pilot_resources_no_gain_or_phase_fit",
                       ChannelNMSEPilotResourceCount="3276", ChannelNMSEComparedComplexValues="13104",
                       ChannelNMSEErrorEnergy="1", ChannelNMSEReferenceEnergy="32")
    trs_rows[0].update(IndependentPilotSNDR_dB="20", IndependentPilotSNDRAvailable="1",
                       IndependentPilotReferencePlane="recorded_receiver_clock",
                       IndependentPilotValueRole="post_reception_scoring_only_not_receiver_or_scheduler_input")
    trs_rows[0].update(TimingEstimateUsed="1", AppliedTimingCorrection_samples="16",
                      TimingEstimateStatus="available_applied_at_received_window_origins",
                      TimingEstimateApplicationPolicy="per_resource_received_window_origin_shift_no_second_correction",
                      TRSAppliedTimingResourceCount="2", TRSExpectedTimingResourceCount="2",
                      TRSAppliedTimingEvidenceJSON='[{"Slot":7,"EstimatedTimingOffset_samples":16}]')
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
        preview = runtime_context["trs_trials_preview"][0]
        assert preview["Tracking state"] == "valid", (
            "browser runtime context must include a canonical TRS trials preview when present"
        )
        assert str(preview["Scheduler usable"]) == "1"
        assert str(preview["Qualification pass"]) == "0"
        assert preview["Status"] == "FAIL", "Scheduler usability must not turn failed qualification into PASS."
        assert preview["NMSE reference plane"] == "recorded_receiver_clock"
        assert preview["Scored pilot resources"] == "3276"
        assert preview["Compared complex values"] == "13104"
        assert preview["NMSE comparison mode"] == "independent_complex_pilot_resources_no_gain_or_phase_fit"
        assert preview["Independent pilot SNDR (dB; includes distortion)"] == "20"
        assert preview["Independent pilot value role"] == "post_reception_scoring_only_not_receiver_or_scheduler_input"
        assert preview["Timing estimate used"] == "1"
        assert preview["Applied timing correction (samples)"] == "16"
        assert preview["Timing status"] == "available_applied_at_received_window_origins"
        assert preview["Timing correction policy"] == "per_resource_received_window_origin_shift_no_second_correction"
        assert preview["Aligned TRS windows"] == "2" and preview["Expected TRS windows"] == "2"
        assert preview["Applied timing window evidence"] == trs_rows[0]["TRSAppliedTimingEvidenceJSON"]
        assert any("TRS runtime consumer: shared_receiver_tracking_state." in note for note in runtime_context["notes"]), (
            "browser notes must disclose the real TRS runtime consumer"
        )
        assert not any("TRS receiver integration blocker:" in note for note in runtime_context["notes"]), (
            "browser notes must not emit an obsolete TRS blocker after receiver tracking integration"
        )
    finally:
        dash.load_small_csv_rows = orig_load_small


if __name__ == "__main__":
    test_trs_runtime_truth_preview()
