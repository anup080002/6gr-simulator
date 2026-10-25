"""Original child lifecycle plus exact runner liveness, not sweep PHY qualification."""
import json
import os
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as dash


def setup_parent(tmp_path, monkeypatch, active=False):
    parent = tmp_path / "original_sweep"
    (parent / "meta").mkdir(parents=True)
    (parent / "meta/scenario_config_identity.json").write_text('{"ScenarioID":"declared_fixture"}')
    (parent / "meta/scenario_config_resolved.json").write_text(json.dumps({
        "scenario": {"runner_profile": "generic_sweep", "sweep": {"overrides": [
            {"label": "point_a", "config": {}}, {"label": "point_b", "config": {}}]}}}))
    for point in ("point_a", "point_b"):
        (parent / "sweeps" / point / "reports/csv").mkdir(parents=True)
    monkeypatch.setattr(dash, "local_run_process_active", lambda row: active and row["run_tag"] == parent.name)
    return parent


def live(parent, point="point_a"):
    path = parent / "sweeps" / point / "reports/csv/live_stage_status.csv"
    path.write_text("Stage,CurrentSlot,TotalSlots\ndl_ul_raw_trials_streaming,44,70\n")
    return path


def failure(parent):
    path = parent / "sweeps/point_a/reports/csv/runtime_failure_checkpoint.csv"
    path.write_text("ErrorIdentifier,ErrorMessage,Slot,DLTrialRows,ULTrialRows,RunState,EvidenceScope\n"
                    "sixgr:phy:sync:StaleULTimingReference,stale,45,3,0,failed_runtime_checkpoint_not_finalized,completed_runtime_observations_before_failure\n")
    return path


def status(parent):
    row = dash.filesystem_run_row_from_folder(parent)
    value = json.loads(row["status_json"])
    assert row["status_text"] == value["status"]
    return value


def test_failed_child_no_process_not_initializing_and_original_unchanged(tmp_path, monkeypatch):
    parent = setup_parent(tmp_path, monkeypatch)
    live(parent)
    path = failure(parent)
    before = path.read_bytes()
    result = status(parent)
    assert result["status"] == "failed"
    assert result["stage"] == "generic_sweep_interrupted_after_child_failure"
    assert result["result_ok"] is False and result["parent_terminal_result_available"] is False
    assert [p["status"] for p in result["sweep_children"]] == ["failed", "pending"]
    progress = dash._observed_sweep_lifecycle(parent)
    assert progress["failed"] == 1 and progress["pending"] == 1 and progress["ongoing"] == 0
    assert progress["points"][0]["current_slot"] == 45
    assert path.read_bytes() == before


def test_active_recovery_not_terminal_parent_or_resumed_phy(tmp_path, monkeypatch):
    parent = setup_parent(tmp_path, monkeypatch, True)
    live(parent)
    failure(parent)
    result = status(parent)
    assert result["status"] == "running"
    assert result["stage"] == "generic_sweep_active_after_child_failure"
    assert result["failed_child_count"] == 1 and result["result_ok"] is False
    assert "not proof of resumed PHY" in result["reason"]


def test_other_child_running_preserves_failure_without_copying_terminal_status(tmp_path, monkeypatch):
    parent = setup_parent(tmp_path, monkeypatch, True)
    failure(parent)
    live(parent, "point_b")
    result = status(parent)
    assert result["status"] == "running" and result["stage"] == "generic_sweep_child_execution"
    assert [p["status"] for p in result["sweep_children"]] == ["failed", "running"]


@pytest.mark.parametrize("stale", [False, True])
def test_missing_process_without_failure_does_not_invent_failure_or_success(tmp_path, monkeypatch, stale):
    parent = setup_parent(tmp_path, monkeypatch)
    path = live(parent)
    if stale:
        old = time.time() - 60 * (dash.STALE_RUNNING_MINUTES + 1)
        os.utime(path, (old, old))
    result = status(parent)
    assert result["status"] == ("aborted_stale_no_run_process" if stale else "process_unobserved")
    assert result["result_ok"] is None


def test_terminal_parent_remains_authoritative(tmp_path, monkeypatch):
    parent = setup_parent(tmp_path, monkeypatch, True)
    failure(parent)
    (parent / "reports/csv").mkdir(parents=True)
    (parent / "reports/csv/scenario_summary.csv").write_text("RunCompletion,ResultOk\ncompleted_with_failures,0\n")
    result = status(parent)
    assert result["status"] == "completed_with_failures" and result["result_ok"] is False
    assert "sweep_children" not in result


def test_nonterminal_parent_summary_cannot_hide_later_child_failure(tmp_path, monkeypatch):
    parent = setup_parent(tmp_path, monkeypatch)
    failure(parent)
    (parent / "reports/csv").mkdir(parents=True)
    (parent / "reports/csv/scenario_summary.csv").write_text("RunCompletion,ResultOk\ninitializing,\n")
    assert status(parent)["status"] == "failed"
