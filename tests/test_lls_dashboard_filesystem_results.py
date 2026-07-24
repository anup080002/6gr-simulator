from __future__ import annotations

import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def test_dashboard_discovers_filesystem_only_result_run(tmp_path, monkeypatch) -> None:
    results_root = tmp_path / "results"
    run_folder = results_root / "lls" / "scenario_a" / "run_a"
    (run_folder / "meta").mkdir(parents=True)
    (run_folder / "reports" / "csv").mkdir(parents=True)
    (run_folder / "air_interface" / "csv").mkdir(parents=True)
    (run_folder / "figures").mkdir(parents=True)

    (run_folder / "meta" / "scenario_manifest.json").write_text(
        json.dumps(
            {
                "GeneratedUTC": "2026-06-22T01:02:03+00:00",
                "ScenarioID": "scenario_a",
                "RunnerProfile": "waveform_bundle",
                "RunCompletion": "completed",
                "ResultOk": True,
                "OutputBackend": "results_folder",
            }
        ),
        encoding="utf-8",
    )
    (run_folder / "meta" / "scenario_config_resolved.json").write_text(
        json.dumps({"scenario": {"id": "scenario_a"}, "run_control": {"total_slots": 60}}),
        encoding="utf-8",
    )
    (run_folder / "reports" / "csv" / "scenario_summary.csv").write_text(
        "ScenarioID,RunnerProfile,RunCompletion,ResultOk,RequiredFailureCount,RuntimeTruthContractOk\n"
        "scenario_a,waveform_bundle,completed,1,0,1\n",
        encoding="utf-8",
    )
    (run_folder / "air_interface" / "csv" / "dl_pdsch_trials.csv").write_text(
        "Slot,CRCPass,PostEqSINR_dB\n0,1,18.5\n",
        encoding="utf-8",
    )
    (run_folder / "figures" / "placeholder.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"></svg>',
        encoding="utf-8",
    )

    def no_db(*_args, **_kwargs):
        raise dash.DashboardMySQLUnavailable("forced filesystem-only test")

    monkeypatch.setattr(dash, "RESULTS_ROOT", results_root)
    monkeypatch.setattr(dash, "db_connection", no_db)
    dash.clear_dashboard_caches()

    rows = dash.fetch_runs(limit=10)
    assert rows
    assert rows[0]["run_tag"] == "run_a"
    assert rows[0]["scenario_id"] == "scenario_a"

    run_id = int(rows[0]["run_id"])
    assert dash.latest_run_id() == run_id
    run_row = dash.fetch_run(run_id)
    assert run_row is not None
    assert run_row["backend"] == "results_folder"

    artifacts = dash.fetch_artifacts(run_id)
    logical_paths = {str(item["logical_path"]) for item in artifacts}
    assert "reports/csv/scenario_summary.csv" in logical_paths
    assert "air_interface/csv/dl_pdsch_trials.csv" in logical_paths
    assert any(str(item.get("mime_type") or "").startswith("image/") for item in artifacts)
    assert all(int(item["artifact_id"]) >= dash.FILESYSTEM_ARTIFACT_ID_BASE for item in artifacts)

    summary_artifact = next(item for item in artifacts if item["logical_path"] == "reports/csv/scenario_summary.csv")
    preview = dash.build_table_preview_payload(int(summary_artifact["artifact_id"]))
    assert preview is not None
    assert preview["header"][0] == "ScenarioID"
    assert preview["rows"][0][0] == "scenario_a"
    assert preview["row_count"] == 1
    assert preview["row_limit"] == dash.MAX_TABLE_PREVIEW_ROWS
    assert preview["meta"]["logical_path"] == "reports/csv/scenario_summary.csv"

    payload = dash.build_live_payload(run_id)
    assert payload["run"]["run_id"] == run_id
    assert payload["counts"]["tables_total"] >= 2
    assert payload["counts"]["images_total"] == 1
    assert payload["tables_all"]
