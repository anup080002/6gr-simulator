from __future__ import annotations
import json
import csv
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
        "ExecutionID": "test_execution_identity",
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


def test_live_network_trace_preserves_latest_pilot_evidence(tmp_path):
    write_receipt(tmp_path)
    path = tmp_path / "csv/system_network_spatial_evidence.csv"
    path.parent.mkdir()
    columns = ["AbsoluteSlot0", "CSIRSInterferenceIncluded", "CSIRSEmissionCount",
               "ReferenceSignalInterferenceQualified", "WaveformBacked", "SourceClassification"]
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(columns)
        for slot in range(103):
            writer.writerow([slot, 1, 4, 0, 0, "development_fixture_not_study_result"])
    row = sls.run_row(tmp_path, 1)
    before = sls.live_payload(row, [])
    name = "Network interference (modeled, not RF measurement)"
    panel = before["sls"]["evidence"][name]
    assert panel["row_selection"] == "latest" and panel["row_limit"] == 100
    assert len(panel["rows"]) == 100
    assert panel["rows"][0]["AbsoluteSlot0"] == "3"
    assert panel["rows"][-1]["AbsoluteSlot0"] == "102"
    assert panel["rows"][-1]["CSIRSEmissionCount"] == "4"
    assert panel["rows"][-1]["ReferenceSignalInterferenceQualified"] == "0"
    assert panel["rows"][-1]["WaveformBacked"] == "0"
    with path.open("a", newline="") as handle:
        csv.writer(handle).writerow([103, 1, 0, 0, 0, "development_fixture_not_study_result"])
    after = sls.live_payload(row, [])
    assert after["version"] != before["version"]
    assert after["sls"]["evidence"][name]["rows"][-1]["CSIRSEmissionCount"] == "0"
    assert after["sls"]["evidence"][name]["rows"][0]["AbsoluteSlot0"] == "4"
    assert after["sls"]["receipt"]["PrimaryStudyAccepted"] is False


def test_latest_csv_records_keep_quoted_multiline_fields(tmp_path):
    path = tmp_path / "trace.csv"
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["Slot", "Reason"])
        writer.writerows([[1, "old"], [2, 'two lines\nquoted "reason", retained'], [3, "latest"]])
    assert sls.read_rows(path, 2)[-1]["Slot"] == "2"
    latest = sls.read_rows(path, 2, latest=True)
    assert [r["Slot"] for r in latest] == ["2", "3"]
    assert latest[0]["Reason"] == 'two lines\nquoted "reason", retained'
    assert sls.read_rows(path, 0, latest=True) == []


def test_feedback_clock_and_censored_evidence_not_inferred(tmp_path):
    write_receipt(tmp_path)
    (tmp_path / "csv").mkdir()
    (tmp_path / "csv/system_modeled_feedback_capture.csv").write_text(
        "CaptureAbsoluteSlot0,DeferredCSICompletions,WaveformBacked\n5,2,0\n")
    (tmp_path / "csv/system_censored_reference_feedback.csv").write_text(
        "SourceAbsoluteSlot0,Status,WaveformBacked\n6,awaiting_committed_receive_window,0\n")
    payload = sls.live_payload(sls.run_row(tmp_path, 1), [])
    evidence = payload["sls"]["evidence"]
    assert evidence["Feedback capture / completion clock"]["rows"][0]["DeferredCSICompletions"] == "2"
    assert evidence["Unfinished reference receptions (pending/censored)"]["rows"][0]["Status"] == "awaiting_committed_receive_window"
    assert evidence["Network interference (modeled, not RF measurement)"]["rows"] == []


@pytest.mark.parametrize("filename,key", [("system_run_manifest.json", "qualification"),
                                         ("cross_check_report.json", "output_audit")])
def test_qualification_content_changes_refresh_version(tmp_path, filename, key):
    write_receipt(tmp_path)
    (tmp_path / "manifests").mkdir()
    path = tmp_path / "manifests" / filename
    path.write_text('{"Status":"PASS"}')
    row = sls.run_row(tmp_path, 1)
    before = sls.live_payload(row, [])
    # Same filename, count, byte size, receipt and heartbeat. Only content
    # changes; the GUI must not keep displaying the older qualification.
    path.write_text('{"Status":"FAIL"}')
    after = sls.live_payload(row, [])
    assert before["version"] != after["version"]
    assert after["sls"][key]["Status"] == "FAIL"
    assert after["sls"]["receipt"]["PrimaryStudyAccepted"] is False


def test_live_checkpoint_before_final_csv_and_primary_precedence(tmp_path):
    write_receipt(tmp_path)
    (tmp_path / "live").mkdir()
    checkpoint = {"Schema": "sixgr.sls_live_evidence/v1", "WaveformBacked": False,
                  "ExecutionID": "test_execution_identity",
                  "PrimaryStudyAccepted": False, "CommittedThroughAbsoluteSlot0": 9,
                  "SourceClassification": "retained_calibrated_sls_runtime_rows_not_final_results",
                  "Evidence": {"NetworkSpatial": {"Rows": [{"AbsoluteSlot0": 8, "CSIRSEmissionCount": 4}],
                               "RetainedRows": 1, "TotalRows": 1}}}
    path = tmp_path / "live/sls_evidence.json"
    path.write_text(json.dumps(checkpoint))
    row = sls.run_row(tmp_path, 1)
    name = "Network interference (modeled, not RF measurement)"
    panel = sls.live_payload(row, [])["sls"]["evidence"][name]
    assert panel["rows"][0]["CSIRSEmissionCount"] == 4
    assert panel["source"] == "live/sls_evidence.json#Evidence.NetworkSpatial"
    assert panel["evidence_scope"] == "bounded_live_checkpoint_not_final_results"
    assert panel["committed_through_absolute_slot0"] == 9
    # A completed primary table, even header-only, is authoritative. Do not
    # rescue an empty final table using older live checkpoint rows.
    (tmp_path / "csv").mkdir()
    primary = tmp_path / "csv/system_network_spatial_evidence.csv"
    primary.write_text("AbsoluteSlot0,CSIRSEmissionCount\n")
    panel = sls.live_payload(row, [])["sls"]["evidence"][name]
    assert panel["rows"] == [] and panel["source"] == "csv/system_network_spatial_evidence.csv"
    primary.write_text("AbsoluteSlot0,CSIRSEmissionCount\n10,0\n")
    assert sls.live_payload(row, [])["sls"]["evidence"][name]["rows"][0]["CSIRSEmissionCount"] == "0"


def test_uci_reservation_completion_and_harq_decision_are_distinct(tmp_path):
    write_receipt(tmp_path)
    (tmp_path / "live").mkdir()
    checkpoint = {
        "Schema": "sixgr.sls_live_evidence/v1", "ExecutionID": "test_execution_identity",
        "WaveformBacked": False, "PrimaryStudyAccepted": False,
        "CommittedThroughAbsoluteSlot0": 9,
        "SourceClassification": "retained_calibrated_sls_runtime_rows_not_final_results",
        "Evidence": {
            "UCIObligations": {"Rows": [{"ObligationID": "occasion9", "HARQBits": 1}],
                               "RetainedRows": 1, "TotalRows": 1},
            "UCICompletions": {"Rows": [], "RetainedRows": 0, "TotalRows": 0},
            "HARQDecisions": {"Rows": [], "RetainedRows": 0, "TotalRows": 0},
        },
    }
    path = tmp_path / "live/sls_evidence.json"
    path.write_text(json.dumps(checkpoint))
    row = sls.run_row(tmp_path, 1)
    completion_name = "UCI transport completions (ideal delayed control)"
    decision_name = "HARQ decisions (modeled, not waveform CRC)"
    emission_name = "Native PUCCH transmissions (TX audit, not reception)"
    before = sls.live_payload(row, [])
    assert before["sls"]["evidence"][completion_name]["rows"] == []
    assert before["sls"]["evidence"][decision_name]["rows"] == []
    assert before["sls"]["evidence"][emission_name]["rows"] == []
    checkpoint["Evidence"]["PUCCHEmissions"] = {
        "Rows": [{"ObligationID": "occasion9", "AbsoluteSlot0": 9,
                  "Disposition": "native_PUCCH_transmitted_modeled_control",
                  "NativeWaveformExecuted": True, "PhysicalReceptionQualified": False,
                  "EmissionSHA256": "a" * 64}], "RetainedRows": 1, "TotalRows": 1,
    }
    path.write_text(json.dumps(checkpoint))
    transmitted = sls.live_payload(row, [])
    assert transmitted["version"] != before["version"]
    assert transmitted["sls"]["evidence"][emission_name]["rows"][0]["NativeWaveformExecuted"] is True
    assert transmitted["sls"]["evidence"][emission_name]["rows"][0]["PhysicalReceptionQualified"] is False
    assert transmitted["sls"]["evidence"][completion_name]["rows"] == []
    assert transmitted["sls"]["evidence"][decision_name]["rows"] == []
    # A reservation alone must never appear as a completion or ACK.
    checkpoint["Evidence"]["UCICompletions"] = {
        "Rows": [{"ObligationID": "occasion9", "CompletionAbsoluteSlot0": 9,
                  "Transport": "PUCCH", "CompletionSource": "ideal_error_free_delayed_control",
                  "WaveformBacked": False, "PhysicalDecodeQualified": False}],
        "RetainedRows": 1, "TotalRows": 1,
    }
    checkpoint["Evidence"]["HARQDecisions"] = {
        "Rows": [{"ACK": False, "TransmissionAbsoluteSlot0": 5, "ReceiveCompletionAbsoluteSlot0": 6,
                  "FeedbackAbsoluteSlot0": 9, "TransportBlockIdentity": "test_tb",
                  "SourceClassification": "development_fixture_not_study_result",
                  "WaveformBacked": False, "CalibrationQualified": False}],
        "RetainedRows": 1, "TotalRows": 1,
    }
    path.write_text(json.dumps(checkpoint))
    after = sls.live_payload(row, [])
    assert before["version"] != after["version"]
    evidence = after["sls"]["evidence"]
    assert evidence[completion_name]["rows"][0]["PhysicalDecodeQualified"] is False
    assert evidence[decision_name]["rows"][0]["ACK"] is False
    assert evidence[decision_name]["source"] == "live/sls_evidence.json#Evidence.HARQDecisions"
    assert after["sls"]["receipt"]["PrimaryStudyAccepted"] is False
    (tmp_path / "csv").mkdir()
    primary = tmp_path / "csv/system_modeled_harq_payload_decisions.csv"
    primary.write_text("ACK,TransportBlockIdentity,WaveformBacked\n")
    panel = sls.live_payload(row, [])["sls"]["evidence"][decision_name]
    assert panel["rows"] == [] and panel["source"] == "csv/system_modeled_harq_payload_decisions.csv"
    primary.write_text("ACK,TransportBlockIdentity,WaveformBacked\n0,test_tb,0\n")
    panel = sls.live_payload(row, [])["sls"]["evidence"][decision_name]
    assert panel["rows"][0]["ACK"] == "0"
    # Final emission CSV is authoritative too, even when header-only.
    emission_csv = tmp_path / "csv/system_native_pucch_emission_audit.csv"
    emission_csv.write_text("ObligationID,NativeWaveformExecuted,PhysicalReceptionQualified\n")
    panel = sls.live_payload(row, [])["sls"]["evidence"][emission_name]
    assert panel["rows"] == [] and panel["source"] == "csv/system_native_pucch_emission_audit.csv"
    emission_csv.write_text("ObligationID,NativeWaveformExecuted,PhysicalReceptionQualified\noccasion9,1,0\n")
    panel = sls.live_payload(row, [])["sls"]["evidence"][emission_name]
    assert panel["rows"][0]["PhysicalReceptionQualified"] == "0"
    # Do not adopt even perfectly shaped rows from another run's checkpoint.
    checkpoint["ExecutionID"] = "other_run"
    path.write_text(json.dumps(checkpoint))
    assert sls.live_payload(row, [])["sls"]["evidence"][completion_name]["rows"] == []
    emission_csv.unlink()  # Isolated pytest fixture; no production evidence.
    assert sls.live_payload(row, [])["sls"]["evidence"][emission_name]["rows"] == []


@pytest.mark.parametrize("mutation", [{"WaveformBacked": True}, {"PrimaryStudyAccepted": True},
                                       {"Schema": "unknown"}, {"Evidence": []},
                                       {"ExecutionID": "another_execution"}, {"ExecutionID": ""},
                                       {"ExecutionID": None}])
def test_invalid_live_checkpoint_is_not_promoted(tmp_path, mutation):
    write_receipt(tmp_path)
    (tmp_path / "live").mkdir()
    checkpoint = {"Schema": "sixgr.sls_live_evidence/v1", "WaveformBacked": False,
                  "ExecutionID": "test_execution_identity",
                  "PrimaryStudyAccepted": False,
                  "SourceClassification": "retained_calibrated_sls_runtime_rows_not_final_results",
                  "Evidence": {"NetworkSpatial": {"Rows": [{"CSIRSEmissionCount": 4}],
                               "RetainedRows": 1, "TotalRows": 1}}}
    checkpoint.update(mutation)
    (tmp_path / "live/sls_evidence.json").write_text(json.dumps(checkpoint))
    panel = sls.live_payload(sls.run_row(tmp_path, 1), [])["sls"]["evidence"][
        "Network interference (modeled, not RF measurement)"]
    assert panel["rows"] == []


@pytest.mark.parametrize("identity", [None, "", " ", 123])
def test_unbound_receipt_cannot_accept_live_checkpoint(tmp_path, identity):
    write_receipt(tmp_path)
    receipt_path = tmp_path / "meta/simulation_run.json"
    receipt = json.loads(receipt_path.read_text())
    receipt["ExecutionID"] = identity
    receipt_path.write_text(json.dumps(receipt))
    (tmp_path / "live").mkdir()
    (tmp_path / "live/sls_evidence.json").write_text(json.dumps({
        "Schema": "sixgr.sls_live_evidence/v1", "ExecutionID": identity,
        "WaveformBacked": False, "PrimaryStudyAccepted": False,
        "SourceClassification": "retained_calibrated_sls_runtime_rows_not_final_results",
        "Evidence": {"NetworkSpatial": {"Rows": [{"CSIRSEmissionCount": 4}],
                                       "RetainedRows": 1, "TotalRows": 1}}}))
    panel = sls.live_payload(sls.run_row(tmp_path, 1), [])["sls"]["evidence"][
        "Network interference (modeled, not RF measurement)"]
    assert panel["rows"] == []
