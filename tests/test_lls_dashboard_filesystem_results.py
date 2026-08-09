from __future__ import annotations

import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def test_dashboard_csv_parser_accepts_large_exact_phy_vector() -> None:
    packed_vector = "|".join("0" for _ in range(70000))
    raw = ("TrialID,MeasuredLDPCParityCheckVector,CRCPass\n"
           f"1,\"{packed_vector}\",1\n").encode("utf-8")
    header, rows = dash.parse_csv_bytes(raw)
    assert header == ["TrialID", "MeasuredLDPCParityCheckVector", "CRCPass"]
    assert len(rows) == 1
    assert rows[0][1] == packed_vector


def test_dashboard_discovers_active_filesystem_run_before_terminal_manifest(
    tmp_path, monkeypatch
) -> None:
    results_root = tmp_path / "results"
    run_folder = results_root / "lls" / "active_scenario" / "active_run"
    (run_folder / "meta").mkdir(parents=True)
    live_dir = run_folder / "air_interface" / "reports" / "csv"
    live_dir.mkdir(parents=True)
    (run_folder / "meta" / "scenario_config_identity.json").write_text(
        json.dumps(
            {
                "ScenarioID": "active_scenario",
                "GeneratedUTC": "2026-08-09T00:00:00Z",
            }
        ),
        encoding="utf-8",
    )
    (run_folder / "meta" / "scenario_config_resolved.json").write_text(
        json.dumps(
            {
                "meta": {"scenario_id": "active_scenario"},
                "scenario": {"run_control": {"runner_profile": "waveform_bundle"}},
            }
        ),
        encoding="utf-8",
    )
    (live_dir / "live_stage_status.csv").write_text(
        "Stage,CurrentSNR_dB,CurrentSlot,TotalSlots,RunCompletion,Notes\n"
        "control_gating_streaming,-20,1,120,0.008333,executing\n",
        encoding="utf-8",
    )
    runtime_log = run_folder / "air_interface" / "logs" / "run.log"
    runtime_log.parent.mkdir(parents=True)
    runtime_log.write_text(
        "[2026-08-09 00:00:01.000] INFO  Starting coupled control gating.\n"
        "[2026-08-09 00:00:02.000] WARN  PRACH pending.\n",
        encoding="utf-8",
    )

    def no_db(*_args, **_kwargs):
        raise dash.DashboardMySQLUnavailable("forced filesystem-only test")

    monkeypatch.setattr(dash, "RESULTS_ROOT", results_root)
    monkeypatch.setattr(dash, "db_connection", no_db)
    dash.clear_dashboard_caches()

    rows = dash.fetch_runs(limit=10)
    active = next(row for row in rows if row["run_tag"] == "active_run")
    assert active["scenario_id"] == "active_scenario"
    assert active["status_text"] == "running"
    assert active["profile_name"] == "waveform_bundle"
    status = dash._status_payload(active)
    assert status["status_authority"] == "live_stage_status"
    assert status["stage"] == "control_gating_streaming"
    assert status["current_stage"] == "control_gating_streaming"
    assert status["current_snr_db"] == -20
    assert status["current_slot"] == 1
    assert status["total_slots"] == 120
    logs = dash.fetch_logs(int(active["run_id"]), limit=10, descending=True)
    assert len(logs) == 2
    assert logs[-1]["level_str"] == "WARN"
    assert "PRACH pending" in logs[-1]["message_text"]
    assert dash.count_logs(int(active["run_id"])) == 2


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
    assert payload["counts"]["tables_total"] == 0
    assert payload["counts"]["images_total"] == 0
    assert payload["counts"]["diagnostic_tables_total"] >= 2
    assert payload["counts"]["diagnostic_images_total"] >= 1
    assert (
        payload["realtime_dashboard"]["folder_policy"]["status"]
        == "no_atomic_result_authority"
    )
    assert payload["tables_all"] == []
    assert payload["images_all"] == []
    lite_payload = dash.build_lite_live_payload(run_id)
    assert lite_payload["counts"]["tables_total"] == 0
    assert lite_payload["counts"]["diagnostic_tables_total"] >= 2


def test_dashboard_discovers_component_qualification_without_scenario_manifest(
    tmp_path, monkeypatch
) -> None:
    results_root = tmp_path / "results"
    run_folder = (
        results_root
        / "lls"
        / "canonical_component_rebuild"
        / "qualification_wave_01"
    )
    audit_dir = run_folder / "artifact_generation"
    component_csv = (
        run_folder
        / "components"
        / "pdsch"
        / "qualification"
        / "csv"
    )
    audit_dir.mkdir(parents=True)
    component_csv.mkdir(parents=True)
    (audit_dir / "component_qualification_manifest.csv").write_text(
        "Domain,Component,ArtifactType,FileName,PublishedRelativePath,Status\n"
        "pdsch,pdsch,CSV,pdsch_bler_curve.csv,"
        "components/pdsch/qualification/csv/pdsch_bler_curve.csv,PASS\n",
        encoding="utf-8",
    )
    (audit_dir / "component_qualification_summary.csv").write_text(
        "Domain,ContractCount,PublishedCount,CSVCount,PNGCount,Status\n"
        "pdsch,1,1,1,0,PASS\n"
        "mimo,2,0,0,0,FAIL\n",
        encoding="utf-8",
    )
    (component_csv / "pdsch_bler_curve.csv").write_text(
        "CaseID,Status\npdsch-1,PASS\n", encoding="utf-8"
    )

    monkeypatch.setattr(dash, "RESULTS_ROOT", results_root)
    dash.clear_dashboard_caches()
    rows = dash.filesystem_run_rows(limit=10)

    assert len(rows) == 1
    row = rows[0]
    assert row["scenario_id"] == "canonical_component_rebuild"
    assert row["run_tag"] == "qualification_wave_01"
    assert row["profile_name"] == "component_qualification"
    assert row["status_text"] == "completed_with_failures"
    status = dash._status_payload(row)
    assert status["status_authority"] == "component_qualification_summary"
    assert status["component_qualification_domain_count"] == 2
    assert status["component_qualification_passed_domain_count"] == 1
    assert status["component_qualification_failed_domain_count"] == 1
    assert status["required_failure_count"] == 1
    policy = dash.extract_run_feature_policy(row)
    assert policy["cross_feature_qualification"] is True
    assert not dash.artifact_is_policy_filtered(
        "components/channel/qualification/csv/ntn_channel_results.csv",
        policy,
    )

    artifacts = dash.fetch_artifacts(int(row["run_id"]))
    selected, authority = dash.select_primary_result_artifacts(artifacts)
    assert authority["evidence_scope"] == "component_validation_campaign"
    assert authority["canonical_count"] == 1
    assert {
        str(item["logical_path"]) for item in selected
    } == {
        "components/pdsch/qualification/csv/pdsch_bler_curve.csv",
        "artifact_generation/component_qualification_manifest.csv",
        "artifact_generation/component_qualification_summary.csv",
    }
    runtime = dash.extract_runtime_context(row, artifacts)
    assert runtime["truth_modes"] == {
        "evidence_scope": "component_qualification",
        "scenario_runtime_applicable": False,
    }
    assert any(
        "not a single scenario runtime" in note for note in runtime["notes"]
    )
    assert not any("Noise operating mode" in note for note in runtime["notes"])
    payload = dash.build_live_payload(int(row["run_id"]))
    metric_values = {item["label"]: item["value"] for item in payload["metrics"]}
    assert metric_values["Qualified Components"] == "1"
    assert metric_values["Failed Components"] == "1"
    assert metric_values["Component Contracts"] == "3"
    assert metric_values["Published Component Artifacts"] == "1"
    assert metric_values["Component CSVs"] == "1"
    assert metric_values["Component PNGs"] == "0"
    assert "Published Count" not in metric_values

    # A terminal component run may be refreshed in place.  Replacing the
    # authority manifest must invalidate the filesystem artifact cache so a
    # deleted/stale domain cannot remain visible until process restart.
    pucch_csv = (
        run_folder
        / "components"
        / "pucch"
        / "qualification"
        / "csv"
    )
    pucch_csv.mkdir(parents=True)
    (pucch_csv / "pucch_trials.csv").write_text(
        "CaseID,Status\npucch-1,PASS\n", encoding="utf-8"
    )
    (audit_dir / "component_qualification_manifest.csv").write_text(
        "Domain,Component,ArtifactType,FileName,PublishedRelativePath,Status\n"
        "pucch,pucch,CSV,pucch_trials.csv,"
        "components/pucch/qualification/csv/pucch_trials.csv,PASS\n",
        encoding="utf-8",
    )
    (audit_dir / "component_qualification_summary.csv").write_text(
        "Domain,ContractCount,PublishedCount,CSVCount,PNGCount,Status\n"
        "pdsch,1,0,0,0,FAIL\n"
        "pucch,1,1,1,0,PASS\n",
        encoding="utf-8",
    )
    (component_csv / "pdsch_bler_curve.csv").unlink()
    refreshed_row = dash.filesystem_run_row_from_folder(run_folder)
    refreshed_artifacts = dash.filesystem_artifacts_for_run(refreshed_row or {})
    refreshed_paths = {
        str(item["logical_path"]) for item in refreshed_artifacts
    }
    assert "components/pdsch/qualification/csv/pdsch_bler_curve.csv" not in refreshed_paths
    assert "components/pucch/qualification/csv/pucch_trials.csv" in refreshed_paths
    refreshed_payload = dash.build_live_payload(int(row["run_id"]))
    refreshed_metric_values = {
        item["label"]: item["value"] for item in refreshed_payload["metrics"]
    }
    assert refreshed_metric_values["Qualified Components"] == "1"
    assert refreshed_metric_values["Failed Components"] == "1"
    assert refreshed_metric_values["Component Contracts"] == "2"
    assert refreshed_metric_values["Published Component Artifacts"] == "1"
