from __future__ import annotations
import json
import sys
from pathlib import Path
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as dash
import sixgr_sls_dashboard as sls


def write_receipt(folder, status="running"):
    (folder / "meta").mkdir(parents=True, exist_ok=True)
    (folder / "meta/simulation_run.json").write_text(json.dumps({
        "Schema": "sixgr.simulation_run/v1", "ExecutionMode": "SLS",
        "Status": status, "ScenarioID": "network", "RunTag": "test", "PrimaryStudyAccepted": False,
        "ExecutionBackend": "calibrated_link_abstraction", "UpdatedUTC": "2026-10-01T00:00:00Z"}))


def test_sls_discovery_and_terminal_authority(tmp_path, monkeypatch):
    folder = tmp_path / "sls/network/test"
    write_receipt(folder, "failed")
    (folder / "RUNNING.status.json").write_text(json.dumps({"CurrentSlot": 3, "ResultOk": True}))
    monkeypatch.setattr(dash, "_dashboard_result_roots", lambda: [tmp_path])
    assert folder in dash._filesystem_run_folders()
    row = dash.filesystem_run_row_from_folder(folder)
    assert row["status_text"] == "failed" and row["execution_mode"] == "SLS"
    payload = sls.live_payload(row, [])
    assert payload["sls"]["progress"]["ExecutionStatus"] == "failed"
    assert payload["sls"]["progress"]["ResultOk"] is False
    assert payload["sls"]["receipt"]["PrimaryStudyAccepted"] is False


def test_sls_does_not_call_lls_materializer(tmp_path, monkeypatch):
    write_receipt(tmp_path)
    row = sls.run_row(tmp_path, 9000000001)
    monkeypatch.setattr(dash, "fetch_run", lambda _: row)
    monkeypatch.setattr(dash, "filesystem_artifacts_for_run", lambda _: [])
    monkeypatch.setattr(dash, "sync_runtime_log_for_run", lambda _: pytest.fail("LLS sync called"))
    assert dash.build_live_payload(9000000001)["execution_mode"] == "SLS"
    assert dash.build_live_payload(9000000001, lite=True)["execution_mode"] == "SLS"
    plots = dash.build_plot_browser_payload(9000000001)
    assert plots["items"] == [] and plots["mode"] == "sls_persisted_network_evidence"
    assert dash.build_table_browser_payload(9000000001)["source"] == "persisted_sls_network_tables"


def test_native_fragment_fields_visible_and_overlay_preserved():
    payload, _ = dash.load_resolved_config_payload("sls_network_calibrated.yaml")
    assert payload["sls"]["config"]["system"]["linkAbstraction"]["minimumCalibrationTrials"] == 2000
    fields = dash.product_field_records(payload)
    assert any(f["path"] == "sls.config.system.linkAbstraction.minimumCalibrationTrials" for f in fields)
    assert dash.field_options_for_path("sls.config.system.phyBackend", "waveform") == ["waveform", "calibrated_link_abstraction"]
    assert dash.field_options_for_path("sls.config.channel.fc_Hz", 7e9) is None
    assert not dash.scenario_launch_contract(payload, "network")["launch_allowed"]
    import yaml
    overlay = yaml.safe_load(dash.normalize_run_yaml(yaml.safe_dump(payload), "sls_network_calibrated.yaml"))
    assert overlay["inherits"] == ["./sls_network_calibrated.yaml"]
    assert "output" not in overlay


def test_sls_mode_and_fixture_guard():
    payload = {"run_control": {"execution_mode": "SLS"}, "sls": {"config": {
        "run": {"mode": "system", "useConfigFragments": False},
        "system": {"phyBackend": "waveform"},
        "outputs": {"saveCSV": False}}}}
    assert dash.canonicalize_browser_config_payload(payload) == payload
    assert dash.scenario_launch_contract(payload, "network")["launch_allowed"]
    payload["sls"]["config"]["system"] = {"linkAbstraction": {"allowDevelopmentFixtures": True}}
    assert not dash.scenario_launch_contract(payload, "network")["launch_allowed"]
    payload["run_control"]["execution_mode"] = "LLS"
    with pytest.raises(ValueError):
        dash.scenario_launch_contract(payload, "network")


def test_rows_and_refresh(tmp_path):
    write_receipt(tmp_path)
    path = tmp_path / "summaries/system_kpi_summary.csv"
    path.parent.mkdir()
    path.write_text("Name,Value\n")
    row = sls.run_row(tmp_path, 1)
    before = sls.live_payload(row, [])
    assert before["sls"]["evidence"]["Network KPIs"]["rows"] == []
    path.write_text("Name,Value\nThroughput,42\n")
    (tmp_path / "RUNNING.status.json").write_text('{"CurrentSlot":2}')
    after = sls.live_payload(row, [])
    assert before["version"] != after["version"]
    assert after["sls"]["evidence"]["Network KPIs"]["rows"][0]["Value"] == "42"


def test_stopped_process_not_reported_running(tmp_path, monkeypatch):
    write_receipt(tmp_path)
    path = tmp_path / "meta/simulation_run.json"
    receipt = json.loads(path.read_text())
    receipt["MatlabPID"] = 1234
    path.write_text(json.dumps(receipt))
    monkeypatch.setattr(dash, "process_command_line_for_pid", lambda _: "")
    row = dash.filesystem_run_row_from_folder(tmp_path)
    assert row["status_text"] == "process_unobserved"
    assert sls.live_payload(row, [])["sls"]["receipt"]["PersistedStatus"] == "running"
    assert json.loads(path.read_text())["Status"] == "running"  # Read-only observation.


def test_plot_eligibility_requires_numeric_rows(tmp_path):
    path = tmp_path / "network.csv"
    path.write_text("Slot,Throughput\n")
    assert not sls.chartable_csv(path)
    path.write_text("Slot,Throughput\n1,NaN\n")
    assert not sls.chartable_csv(path)
    path.write_text("Slot,Throughput\n1,0\n")
    assert sls.chartable_csv(path)  # Measured zero remains valid evidence.
