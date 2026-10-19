"""A completed receiver trial is not successful completion of its scenario."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as dash


CHECKPOINT = (
    "ErrorIdentifier,ErrorMessage,Frame,Slot,DLTrialRows,ULTrialRows,RunState,EvidenceScope\n"
    "sixgr:truth:InvalidSharedDLRejectedControlEvidence,Decoded command rejected,3,47,4,0,"
    "failed_runtime_checkpoint_not_finalized,completed_runtime_observations_before_failure\n"
)


@pytest.mark.parametrize("other_authority", ["live", "summary_pass", "component_pass"])
@pytest.mark.parametrize("process_active", [False, True])
def test_runtime_failure_overrides_stale_or_partial_success(
    tmp_path, monkeypatch, other_authority, process_active
):
    folder = tmp_path / "results" / "lls" / "h4" / "failed_run"
    report = folder / "reports" / "csv"
    report.mkdir(parents=True)
    (folder / "meta").mkdir()
    (folder / "meta" / "scenario_config_identity.json").write_text(
        json.dumps({"ScenarioID": "h4"}), encoding="utf-8"
    )
    (report / "live_stage_status.csv").write_text(
        "Stage,CurrentSlot,TotalSlots\ndl_ul_raw_trials_streaming,47,100\n", encoding="utf-8"
    )
    checkpoint = report / "runtime_failure_checkpoint.csv"
    checkpoint.write_text(CHECKPOINT, encoding="utf-8")
    if other_authority == "summary_pass":
        (report / "scenario_summary.csv").write_text(
            "RunCompletion,ResultOk\ncompleted,1\n", encoding="utf-8"
        )
    elif other_authority == "component_pass":
        components = folder / "artifact_generation"
        components.mkdir()
        (components / "component_qualification_manifest.csv").write_text(
            "ScenarioID\nh4\n", encoding="utf-8"
        )
        (components / "component_qualification_summary.csv").write_text(
            "Domain,Status\nPDSCH,PASS\n", encoding="utf-8"
        )
    monkeypatch.setattr(dash, "local_run_process_active", lambda _: process_active)
    row = dash.filesystem_run_row_from_folder(folder)
    assert row["status_text"] == "failed"
    status = dash._status_payload(row)
    assert status["result_ok"] is False
    assert status["status_authority"] == "runtime_failure_checkpoint"
    assert status["failure_slot"] == 47
    assert status["completed_dl_trial_rows"] == 4
    assert status["completed_ul_trial_rows"] == 0
    assert status["stage"] == "failed_runtime_checkpoint_not_finalized"
    assert status["error_identifier"].endswith("InvalidSharedDLRejectedControlEvidence")
    assert status["runtime_truth_contract_ok"] is None  # No fabricated qualification outcome.
    assert dash._effective_run_status(row) == "failed"
    assert checkpoint.read_text(encoding="utf-8") == CHECKPOINT
    monkeypatch.setattr(dash, "load_scenario_summary_row", lambda _: {
        "RunCompletion": "completed", "ResultOk": "1", "StatusAuthority": "stale_summary",
    })
    summary = dash.build_live_summary(row, [])
    compact = dash.compact_run_row(row, [])
    debug = dash.build_debug_payload(row, [], [])
    for view in (summary, compact, debug):
        assert view["result_ok"] is False
        assert view["run_completion"] == "failed"
        assert view["status_authority"] == "runtime_failure_checkpoint"
    assert debug["failure_message"] == "Decoded command rejected"


def test_failure_checkpoint_is_terminal_before_final_manifests(tmp_path, monkeypatch):
    checkpoint = tmp_path / "runtime_failure_checkpoint.csv"
    checkpoint.write_text(CHECKPOINT, encoding="utf-8")
    artifact = {"artifact_id": 1, "logical_path": "reports/csv/runtime_failure_checkpoint.csv",
                "filesystem_path": str(checkpoint)}
    monkeypatch.setattr(dash, "fetch_artifacts", lambda _: [artifact])
    result = dash.infer_terminal_status_from_artifacts({"run_id": 70})
    assert result is not None
    status, payload = result
    assert status == "failed" and payload["result_ok"] is False
    assert payload["failure_slot"] == 47


def test_empty_checkpoint_is_not_an_execution_failure(tmp_path, monkeypatch):
    checkpoint = tmp_path / "runtime_failure_checkpoint.csv"
    checkpoint.write_text(CHECKPOINT.splitlines()[0] + "\n", encoding="utf-8")
    monkeypatch.setattr(dash, "fetch_artifacts", lambda _: [
        {"artifact_id": 1, "logical_path": "reports/csv/runtime_failure_checkpoint.csv",
         "filesystem_path": str(checkpoint)}
    ])
    assert dash.infer_terminal_status_from_artifacts({"run_id": 70}) is None


def test_failure_checkpoint_discovered_without_live_stage(tmp_path, monkeypatch):
    folder = tmp_path / "results" / "lls" / "h4" / "failed_run"
    report = folder / "reports" / "csv"
    report.mkdir(parents=True)
    (report / "runtime_failure_checkpoint.csv").write_text(CHECKPOINT, encoding="utf-8")
    monkeypatch.setattr(dash, "local_run_process_active", lambda _: False)
    assert dash._is_discoverable_filesystem_run_folder(folder)
    row = dash.filesystem_run_row_from_folder(folder)
    assert row and row["status_text"] == "failed"
