"""Live stage evidence must not be limited to the recent-activity gallery."""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as dash


@pytest.mark.parametrize("filename", [
    "beam_management_state_trace.csv", "ssb_beam_sweep.csv",
    "ssb_pbch_sib1_beam_sweep.csv", "applied_data_precoder_weights.csv",
])
@pytest.mark.parametrize("has_data", [False, True])
def test_canonical_beam_evidence_readiness_is_not_qualification(tmp_path, filename, has_data):
    # Parser fixtures only. A recorded failed observation is still evidence,
    # but readiness must never change a failed run to a passing run.
    source = tmp_path / filename
    source.write_text("Slot,Status\n" + ("50,FAIL\n" if has_data else ""), encoding="utf-8")
    artifacts = [{"artifact_id": 1, "artifact_kind": "table_csv", "mime_type": "text/csv",
                  "logical_path": "beamforming/csv/" + filename,
                  "filesystem_path": str(source), "byte_size": source.stat().st_size}]
    stage = dash.infer_effective_live_stage(
        {"Stage": "failed_runtime_checkpoint_not_finalized", "RunCompletion": "failed"}, artifacts)
    assert stage["BeamReady"] == int(has_data)
    assert stage["Stage"] == "failed_runtime_checkpoint_not_finalized"
    assert stage["RunCompletion"] == "failed"


@pytest.mark.parametrize("has_data", [False, True])
def test_lite_stage_keeps_older_canonical_trial_evidence(tmp_path, monkeypatch, has_data):
    # These are parser fixtures, not PHY measurements or primary run results.
    dl = tmp_path / "dl_pdsch_trials.csv"
    ul = tmp_path / "ul_pusch_trials.csv"
    dl.write_text("Slot,CRCPass\n" + ("47,1\n" if has_data else ""), encoding="utf-8")
    ul.write_text("Slot,CRCPass\n", encoding="utf-8")
    artifacts = [
        {"artifact_id": i, "artifact_kind": "table_csv", "mime_type": "text/csv",
         "logical_path": "air_interface/csv/" + path.name,
         "filesystem_path": str(path), "byte_size": path.stat().st_size,
         "created_utc": "2026-10-20T10:00:00Z"}
        for i, path in enumerate((dl, ul), 1)
    ]
    # Later plot/activity entries must not erase an already completed trial.
    artifacts += [
        {"artifact_id": 1000 + i, "artifact_kind": "image_png", "mime_type": "image/png",
         "logical_path": f"reports/image/activity_{i}.png", "byte_size": 1,
         "created_utc": "2026-10-20T11:00:00Z"}
        for i in range(dash.MAX_ACTIVITY_POINTS + 1)
    ]
    run_id = 9876543210
    run = {"run_id": run_id, "run_folder": str(tmp_path), "status_text": "running",
           "updated_utc": "2026-10-20T11:00:00Z", "scenario_id": "fixture"}
    monkeypatch.setattr(dash, "fetch_run", lambda _: run)
    monkeypatch.setattr(dash.sls_dashboard, "is_sls_run", lambda _: False)
    monkeypatch.setattr(dash, "sync_runtime_log_for_run", lambda _: 0)
    monkeypatch.setattr(dash, "fetch_artifacts", lambda _: artifacts)
    monkeypatch.setattr(dash, "is_filesystem_virtual_run_id", lambda _: True)
    monkeypatch.setattr(dash, "select_primary_result_artifacts", lambda a: (a, []))
    monkeypatch.setattr(dash, "artifact_content_version", lambda *args: "fixture-v1")
    monkeypatch.setattr(dash, "register_artifact_content_version", lambda *args: None)
    monkeypatch.setattr(dash, "observe_sweep", lambda _: {})
    monkeypatch.setattr(dash, "CACHED_PAYLOAD_VERSION", {})
    monkeypatch.setattr(dash, "LIVE_PAYLOAD_CACHE", {})
    monkeypatch.setattr(dash, "fetch_logs", lambda *args, **kwargs: [])
    monkeypatch.setattr(dash, "count_logs", lambda _: 0)
    monkeypatch.setattr(dash, "parse_status_json", lambda _: {
        "stage": "dl_raw_trials_streaming", "current_slot": 50, "total_slots": 100,
        "run_completion": "running"})
    monkeypatch.setattr(dash, "parse_config_json", lambda _: {})
    monkeypatch.setattr(dash, "infer_runtime_truth_modes", lambda *args: {})
    monkeypatch.setattr(dash, "compact_run_row", lambda row, _: dict(row))

    # The existing data-row parser succeeds when given the full inventory.
    expected = dash.infer_effective_live_stage({"Stage": "dl_raw_trials_streaming"}, artifacts)
    assert expected["DLTrialsReady"] == int(has_data)
    assert expected["ULTrialsReady"] == 0
    payload = dash.build_lite_live_payload(run_id)
    stage = payload["runtime_context"]["stage"]
    assert stage["DLTrialsReady"] == int(has_data)
    assert stage["ULTrialsReady"] == 0, "A header-only PUSCH file is not a completed UL trial."
    assert stage["Stage"] == ("dl_raw_trials_streaming" if has_data else "control_access_pending")
    assert stage["CurrentSlot"] == 50
