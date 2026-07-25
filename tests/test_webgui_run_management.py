from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest
import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def test_uploaded_yaml_uses_selected_master_without_overwriting_catalog(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    monkeypatch.setattr(dash, "SCENARIO_ROOT", tmp_path)
    (tmp_path / dash.SINR_SWEEP_MASTER_SCENARIO).write_text(
        "scenario:\n  runner_profile: waveform_bundle\nsimulation:\n  n_slots: 4\n",
        encoding="utf-8",
    )
    raw = "meta:\n  scenario_id: uploaded_sweep\n"

    target = dash.write_uploaded_scenario(
        dash.SINR_SWEEP_MASTER_SCENARIO,
        raw,
        base_scenario=dash.SINR_SWEEP_MASTER_SCENARIO,
    )

    assert target.parent == tmp_path
    assert target.name.startswith("__web_upload_master_sinr_sweep_")
    assert target.name != dash.SINR_SWEEP_MASTER_SCENARIO
    payload = yaml.safe_load(target.read_text(encoding="utf-8"))
    assert payload["inherits"] == [f"./{dash.SINR_SWEEP_MASTER_SCENARIO}"]
    assert payload["meta"]["scenario_id"] == "uploaded_sweep"
    resolved, source_chain = dash.load_resolved_config_payload(target.name)
    assert resolved["scenario"]["runner_profile"] == "waveform_bundle"
    assert resolved["simulation"]["n_slots"] == 4
    assert resolved["meta"]["scenario_id"] == "uploaded_sweep"
    assert len(source_chain) == 2


def test_filesystem_run_delete_removes_only_the_selected_run_outputs(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    results_root = tmp_path / "results"
    run_folder = results_root / "lls" / "scenario_a" / "run_a"
    (run_folder / "meta").mkdir(parents=True)
    (run_folder / "meta" / "scenario_manifest.json").write_text(
        json.dumps(
            {
                "ScenarioID": "scenario_a",
                "RunCompletion": "completed",
                "GeneratedUTC": "2026-07-25T00:00:00Z",
            }
        ),
        encoding="utf-8",
    )
    runtime_root = tmp_path / "runtime"
    scenario_root = tmp_path / "scenarios"
    runtime_root.mkdir()
    scenario_root.mkdir()
    monkeypatch.setattr(dash, "RESULTS_ROOT", results_root)
    monkeypatch.setattr(dash, "RUNTIME_LOG_DIR", runtime_root)
    monkeypatch.setattr(dash, "SCENARIO_ROOT", scenario_root)
    monkeypatch.setattr(dash, "_dashboard_result_roots", lambda: [results_root])
    monkeypatch.setattr(
        dash,
        "db_connection",
        lambda: (_ for _ in ()).throw(AssertionError("filesystem deletion must not require MySQL")),
    )
    run_id = dash._filesystem_run_id_for_folder(run_folder)

    stats = dash.delete_run_storage(run_id)

    assert stats["run_id"] == run_id
    assert stats["artifacts"] >= 1
    assert stats["disk_entries"] == 1
    assert not run_folder.exists()
    assert (results_root / "lls" / "scenario_a").is_dir()


def test_run_delete_rejects_broad_or_unrelated_output_paths(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    results_root = tmp_path / "results"
    broad_folder = results_root / "lls" / "scenario_a"
    broad_folder.mkdir(parents=True)
    run_id = dash.FILESYSTEM_RUN_ID_BASE + 7
    monkeypatch.setattr(dash, "_dashboard_result_roots", lambda: [results_root])
    monkeypatch.setattr(
        dash,
        "fetch_run",
        lambda _run_id: {
            "run_id": run_id,
            "run_tag": "unsafe",
            "run_folder": str(broad_folder),
            "status_text": "completed",
            "status_json": "{}",
        },
    )

    with pytest.raises(ValueError, match="allowed run storage roots"):
        dash.delete_run_storage(run_id)

    assert broad_folder.is_dir()


def test_bulk_delete_deduplicates_ids_and_preflights_active_runs(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    rows = {
        10: {"run_id": 10, "status_text": "completed", "status_json": "{}"},
        11: {"run_id": 11, "status_text": "running", "status_json": "{}"},
    }
    deleted: list[int] = []
    monkeypatch.setattr(dash, "fetch_run", lambda run_id: rows.get(run_id))
    monkeypatch.setattr(
        dash,
        "delete_run_storage",
        lambda run_id: {
            "run_id": run_id,
            "artifacts": 2,
            "chunks": 1,
            "logs": 3,
            "runtime_yaml": 1,
            "disk_entries": 1,
            "run_tag": f"run_{run_id}",
        }
        | (deleted.append(run_id) or {}),
    )

    stats = dash.delete_runs_storage(["10", "10"])

    assert stats["runs"] == 1
    assert stats["run_ids"] == [10]
    assert stats["artifacts"] == 2
    assert deleted == [10]

    with pytest.raises(ValueError, match="still running"):
        dash.delete_runs_storage(["10", "11"])

    assert deleted == [10]
