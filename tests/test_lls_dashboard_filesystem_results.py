from __future__ import annotations

import csv
import json
import hashlib
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


@pytest.mark.parametrize("limit", [0, 1, 4])
def test_csv_preview_stops_after_requested_logical_records(monkeypatch, limit):
    original_reader = csv.reader
    consumed = []

    def bounded_reader(*args, **kwargs):
        for row in original_reader(*args, **kwargs):
            consumed.append(row)
            assert len(consumed) <= limit + 1, "Preview parsed unrequested CSV rows"
            yield row

    monkeypatch.setattr(dash.csv, "reader", bounded_reader)
    raw = b'!Slot,Notes\n1,"first\nsecond"\n2,OK\n3,FAIL\n4,OK\n5,extra\n'
    header, rows = dash.parse_csv_bytes(raw, max_rows=limit)
    assert header == ["Slot", "Notes"]
    assert len(rows) == limit
    if rows:
        assert rows[0] == ["1", "first\nsecond"]
    assert len(consumed) == limit + 1


def test_filesystem_preview_streams_known_path_and_preserves_evidence(tmp_path, monkeypatch):
    path = tmp_path / "receiver_summary.csv"
    vector = "0" * 150000
    path.write_bytes((
        'Slot,ReceivedIdentity,CRCPass,MeasuredLDPCParityCheckVector,Notes\n'
        f'1,000000000001,0,{vector},"failed\nretained"\n'
        '2,000000000002,1,0,OK\n'
    ).encode("utf-8"))
    artifact = {"logical_path": "receiver_summary.csv", "filesystem_path": str(path),
                "artifact_id": 9900000001, "byte_size": path.stat().st_size}

    def unexpected_read(*args, **kwargs):
        pytest.fail("Known filesystem preview must not read all bytes or rescan other runs")

    monkeypatch.setattr(Path, "read_bytes", unexpected_read)
    monkeypatch.setattr(dash, "filesystem_artifact_by_id", unexpected_read)
    original_reader = csv.reader

    def bounded_reader(*args, **kwargs):
        for index, row in enumerate(original_reader(*args, **kwargs)):
            assert index <= 1, "Filesystem preview parsed unrequested rows"
            yield row

    monkeypatch.setattr(dash.csv, "reader", bounded_reader)
    original_limit = csv.field_size_limit()
    rows = dash.load_small_csv_rows([artifact], "receiver_summary.csv", max_rows=1)
    assert csv.field_size_limit() == original_limit
    assert rows[0]["ReceivedIdentity"] == "000000000001"
    assert rows[0]["CRCPass"] == 0
    assert rows[0]["Notes"] == "failed\nretained"
    assert dash.load_artifact_csv_preview(artifact, 1)[1][0][3] == vector


def test_live_metric_and_chart_use_known_filesystem_artifact(tmp_path, monkeypatch):
    path = tmp_path / "runtime_summary.csv"
    path.write_text("Slot,ThroughputMbps\n1,0\n2,15.5\n", encoding="utf-8")
    artifact = {"logical_path": "reports/csv/runtime_summary.csv", "filesystem_path": str(path),
                "artifact_id": 9900000001, "byte_size": path.stat().st_size}

    def unexpected_lookup(*args, **kwargs):
        pytest.fail("Already inventoried artifacts must not rediscover unrelated runs")

    monkeypatch.setattr(dash, "filesystem_artifact_by_id", unexpected_lookup)
    monkeypatch.setattr(dash, "load_cached_csv_preview", unexpected_lookup)
    cards = dash.extract_metric_cards({"run_id": 9000000001}, [artifact], {"stage": {}})
    assert any(card["source"] == artifact["logical_path"] for card in cards)
    chart = dash.build_numeric_chart_from_artifact(artifact)
    assert chart and chart["artifact_id"] == artifact["artifact_id"]
    # The live preview is bounded; the saved source CSV remains unchanged.
    assert path.read_text(encoding="utf-8") == "Slot,ThroughputMbps\n1,0\n2,15.5\n"


@pytest.mark.parametrize("coordinates", ["Latitude,Longitude", "Lat,Lon"])
def test_live_map_uses_known_filesystem_coordinates(tmp_path, monkeypatch, coordinates):
    path = tmp_path / "sites.csv"
    path.write_text(f"SiteID,{coordinates}\n1,26.0,73.0\n", encoding="utf-8")
    artifact = {"logical_path": "reports/csv/sites.csv", "filesystem_path": str(path),
                "artifact_id": 9900000001, "byte_size": path.stat().st_size}

    def unexpected_lookup(*args, **kwargs):
        pytest.fail("Map must not rediscover a known artifact through other runs")

    monkeypatch.setattr(dash, "load_cached_csv_preview", unexpected_lookup)
    markers = dash.map_table_rows([artifact], ("sites.csv",), "site")
    assert len(markers) == 1
    assert markers[0]["lat"] == 26.0 and markers[0]["lon"] == 73.0
    assert markers[0]["source"] == artifact["logical_path"]


@pytest.mark.parametrize("authority", ["completed", "failed", "live"])
def test_evidenced_run_does_not_probe_preflight_processes(
    tmp_path, monkeypatch, authority
):
    """Run-list polling must not spawn a process query for each stored run."""
    run_folder = tmp_path / "known_run"
    meta = run_folder / "meta"
    reports = run_folder / "reports" / "csv"
    meta.mkdir(parents=True)
    reports.mkdir(parents=True)
    (meta / "scenario_config_identity.json").write_text(
        json.dumps({"ScenarioID": "known_scenario"}), encoding="utf-8"
    )
    (meta / "scenario_config_resolved.json").write_text(
        json.dumps({"scenario": {"runner_profile": "waveform_bundle"}}),
        encoding="utf-8",
    )
    if authority == "live":
        (reports / "live_stage_status.csv").write_text(
            "Stage,CurrentSlot,TotalSlots\nphysical_execution,5,200\n",
            encoding="utf-8",
        )
    else:
        (meta / "scenario_manifest.json").write_text(
            json.dumps({"ScenarioID": "known_scenario", "RunCompletion": authority,
                        "ResultOk": authority == "completed"}),
            encoding="utf-8",
        )

    def unexpected_process_probe(_row):
        pytest.fail("Authoritative run evidence must not invoke preflight process discovery")

    monkeypatch.setattr(dash, "local_run_process_active", unexpected_process_probe)
    assert dash._is_discoverable_filesystem_run_folder(run_folder)
    row = dash.filesystem_run_row_from_folder(run_folder)
    assert row is not None
    assert row["status_text"] == ("running" if authority == "live" else authority)
    status = json.loads(row["status_json"])
    if authority == "live":
        assert status["current_slot"] == 5
        assert status["result_ok"] is None
    else:
        assert status["result_ok"] is (authority == "completed")


@pytest.mark.parametrize("backend", ["filesystem", "database"])
def test_csv_loaders_preserve_literal_receiver_evidence(tmp_path, monkeypatch, backend):
    # These are the exact forms corrupted by generic numeric inference in
    # the two-UE run. This test exercises the loader, not just the preview.
    header = ["PayloadHex", "ReceivedIdentity", "Msg4ContentionIdentity",
              "UCIDecodedBitVector", "AssignmentDigest", "LayerSINRdB",
              "RNTI", "MeasuredSINR_dB", "CRCPass"]
    values = ["020000000000011234320001", "000000000001", "000000000001",
              "00001101", "0" * 63 + "1", "21", "4660", "20.25", "1"]
    missing = [""] * 6 + ["4661", "", "0"]
    payload = (",".join(header) + "\n" + ",".join(values) + "\n" +
               ",".join(missing) + "\n").encode("utf-8")
    logical_path = "control/csv/receiver_literal_fixture.csv"
    if backend == "filesystem":
        path = tmp_path / "receiver.csv"
        path.write_bytes(payload)
        artifacts = [{"logical_path": logical_path, "filesystem_path": str(path)}]
    else:
        monkeypatch.setattr(dash, "load_cached_csv_preview",
                            lambda *_args: dash.parse_csv_bytes(payload))
        dash.load_cached_csv_rows.cache_clear()
        artifacts = [{"logical_path": logical_path, "artifact_id": 987654321}]
    try:
        rows = dash.load_small_csv_rows(artifacts, logical_path)
        assert len(rows) == 2
        for name, expected in zip(header[:6], values[:6]):
            assert rows[0][name] == expected
            assert rows[1][name] == ""  # CRC failure has no decoded bytes.
        assert rows[0]["RNTI"] == 4660
        assert rows[0]["MeasuredSINR_dB"] == 20.25
        assert rows[0]["CRCPass"] == 1 and rows[1]["CRCPass"] == 0
        assert dash.normalize_preview_value(rows[0]["ReceivedIdentity"]) == "000000000001"
    finally:
        dash.load_cached_csv_rows.cache_clear()


def test_dashboard_reads_run_authority_beyond_windows_max_path(tmp_path) -> None:
    """Deep result metadata must remain visible to terminal finalization."""
    if os.name != "nt":
        return

    run_folder = tmp_path
    while len(str(run_folder.absolute())) <= 275:
        run_folder /= "deep_runtime_qualification_segment"
    meta_dir = dash._windows_extended_path(run_folder / "meta")
    csv_dir = dash._windows_extended_path(run_folder / "reports" / "csv")
    meta_dir.mkdir(parents=True)
    csv_dir.mkdir(parents=True)
    (meta_dir / "scenario_manifest.json").write_text(
        json.dumps(
            {
                "ScenarioID": "long_path_runtime",
                "RunCompletion": "completed",
            }
        ),
        encoding="utf-8",
    )
    (csv_dir / "scenario_summary.csv").write_text(
        "ScenarioID,RunCompletion,Status\n"
        "long_path_runtime,completed,PASS\n",
        encoding="utf-8",
    )

    assert dash._is_discoverable_filesystem_run_folder(run_folder)
    row = dash.filesystem_run_row_from_folder(run_folder)
    assert row is not None
    assert row["scenario_id"] == "long_path_runtime"
    assert row["status_text"] == "completed"


def _write_compact_manifest(run_folder: Path, relative_paths: list[str]) -> None:
    lines = ["RelativePath,Bytes,SHA256,ArtifactType"]
    for relative_path in relative_paths:
        payload = (run_folder / relative_path).read_bytes()
        artifact_type = Path(relative_path).suffix.lstrip(".").upper()
        lines.append(
            f"{relative_path},{len(payload)},{hashlib.sha256(payload).hexdigest()},"
            f"{artifact_type}"
        )
    (run_folder / "artifact_manifest.csv").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )


def test_dashboard_parent_run_excludes_nested_sweep_artifacts(tmp_path) -> None:
    run_folder = tmp_path / "parent"
    parent_csv = run_folder / "reports" / "csv" / "sweep_summary.csv"
    child_csv = run_folder / "sweeps" / "point_1" / "reports" / "csv" / "child.csv"
    parent_csv.parent.mkdir(parents=True)
    child_csv.parent.mkdir(parents=True)
    parent_csv.write_text("Label,Ok\npoint_1,1\n", encoding="utf-8")
    child_csv.write_text("Value\n1\n", encoding="utf-8")

    artifacts = dash.filesystem_artifacts_for_run(
        {"run_folder": str(run_folder), "run_id": 123, "status_text": "running"}
    )
    logical_paths = {str(row["logical_path"]) for row in artifacts}
    assert "reports/csv/sweep_summary.csv" in logical_paths
    assert "sweeps/point_1/reports/csv/child.csv" not in logical_paths


def test_dashboard_discovers_sweep_points_before_and_after_parent_completion(
    tmp_path, monkeypatch
) -> None:
    results = tmp_path / "results"
    parent = results / "lls" / "sweep_scenario" / "sweep_run"
    child = parent / "sweeps" / "snr_m30_db"
    child_csv = child / "reports" / "csv"
    child_csv.mkdir(parents=True)
    (child_csv / "scenario_summary.csv").write_text(
        "ScenarioID,RunCompletion,Ok\nsweep_scenario,failed,0\n", encoding="utf-8"
    )
    # Config-only future points and arbitrary debug descendants are not runs.
    future = parent / "sweeps" / "snr_m20_db" / "meta"
    future.mkdir(parents=True)
    (future / "scenario_config_identity.json").write_text("{}", encoding="utf-8")
    debug = parent / "debug" / "nested" / "reports" / "csv"
    debug.mkdir(parents=True)
    (debug / "scenario_summary.csv").write_text("Ok\n1\n", encoding="utf-8")
    monkeypatch.setattr(dash, "_dashboard_result_roots", lambda: [results])
    assert dash._filesystem_run_folders() == [child]
    row = dash.filesystem_run_row_from_folder(child)
    assert row is not None and row["status_text"] == "failed"
    assert dash.filesystem_fetch_run(row["run_id"])["run_folder"] == str(child.absolute())
    parent_csv = parent / "reports" / "csv"
    parent_csv.mkdir(parents=True)
    (parent_csv / "scenario_summary.csv").write_text(
        "ScenarioID,RunCompletion,Ok\nsweep_scenario,completed_with_failures,0\n",
        encoding="utf-8",
    )
    assert set(dash._filesystem_run_folders()) == {parent, child}


def test_dashboard_discovers_generic_sweep_parent_during_child_preflight(
    tmp_path, monkeypatch
) -> None:
    results = tmp_path / "results"
    parent = results / "lls" / "h4_sweep" / "run_01"
    meta = parent / "meta"
    child = parent / "sweeps" / "snr_40_db"
    meta.mkdir(parents=True)
    child.mkdir(parents=True)
    (meta / "scenario_config_identity.json").write_text(
        json.dumps({"ScenarioID": "h4_sweep", "GeneratedUTC": "2026-09-27T00:00:00Z"}),
        encoding="utf-8",
    )
    (meta / "scenario_config_resolved.json").write_text(
        json.dumps({
            "meta": {"scenario_id": "h4_sweep"},
            "scenario": {
                "runner_profile": "generic_sweep",
                "sweep": {
                    "overrides": [
                        {"label": "snr_40_db", "config": {"simulation": {"snr_db": 40}}}
                    ]
                },
            },
        }),
        encoding="utf-8",
    )
    monkeypatch.setattr(dash, "_dashboard_result_roots", lambda: [results])

    assert dash._filesystem_run_folders() == [parent]
    row = dash.filesystem_run_row_from_folder(parent)
    assert row is not None
    assert row["status_text"] == "initializing"
    status = dash._status_payload(row)
    assert status["stage"] == "generic_sweep_child_preflight"
    assert status["status_authority"] == (
        "generic_sweep_resolved_config_and_materialized_child"
    )
    completed = dict(row)
    completed["run_id"] = row["run_id"] + 1
    completed["status_text"] = "completed"
    completed["status_json"] = json.dumps({"run_completion": "completed"})
    assert dash.order_run_rows_for_display(
        [completed, row], prefer_active=True
    )[0]["status_text"] == "initializing"


def test_dashboard_discovers_active_waveform_preflight_only_with_exact_process(
    tmp_path, monkeypatch
) -> None:
    results = tmp_path / "results"
    run_folder = results / "lls" / "h4_gate" / "active_run"
    meta = run_folder / "meta"
    meta.mkdir(parents=True)
    (meta / "scenario_config_identity.json").write_text(
        json.dumps(
            {"ScenarioID": "h4_gate", "GeneratedUTC": "2026-09-29T00:00:00Z"}
        ),
        encoding="utf-8",
    )
    (meta / "scenario_config_resolved.json").write_text(
        json.dumps(
            {
                "meta": {"scenario_id": "h4_gate"},
                "scenario": {"runner_profile": "waveform_bundle"},
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(dash, "_dashboard_result_roots", lambda: [results])
    monkeypatch.setattr(dash, "local_run_process_active", lambda row: False)

    assert dash._filesystem_run_folders() == []
    assert dash.filesystem_run_row_from_folder(run_folder) is None

    observed: list[str] = []

    def exact_process(row):
        observed.append(str(row.get("run_tag") or ""))
        return row.get("run_tag") == "active_run"

    monkeypatch.setattr(dash, "local_run_process_active", exact_process)
    assert dash._filesystem_run_folders() == [run_folder]
    row = dash.filesystem_run_row_from_folder(run_folder)
    assert row is not None
    assert observed and set(observed) == {"active_run"}
    assert row["scenario_id"] == "h4_gate"
    assert row["status_text"] == "initializing"
    status = dash._status_payload(row)
    assert status["stage"] == "waveform_bundle_preflight"
    assert status["status_authority"] == "resolved_config_and_active_run_process"


def test_dashboard_marks_abandoned_generic_sweep_preflight_stale(
    tmp_path, monkeypatch
) -> None:
    results = tmp_path / "results"
    parent = results / "lls" / "h4_sweep" / "run_01"
    meta = parent / "meta"
    child = parent / "sweeps" / "snr_40_db"
    meta.mkdir(parents=True)
    child.mkdir(parents=True)
    identity = meta / "scenario_config_identity.json"
    resolved = meta / "scenario_config_resolved.json"
    identity.write_text(
        json.dumps({"ScenarioID": "h4_sweep", "GeneratedUTC": "2026-09-27T00:00:00Z"}),
        encoding="utf-8",
    )
    resolved.write_text(
        json.dumps({
            "meta": {"scenario_id": "h4_sweep"},
            "scenario": {"runner_profile": "generic_sweep", "sweep": {"overrides": []}},
        }),
        encoding="utf-8",
    )
    stale_time = (
        datetime.now(timezone.utc)
        - timedelta(minutes=dash.STALE_RUNNING_MINUTES + 1)
    ).timestamp()
    for path in (parent, meta, child, identity, resolved):
        os.utime(path, (stale_time, stale_time))
    monkeypatch.setattr(dash, "_dashboard_result_roots", lambda: [results])
    monkeypatch.setattr(dash, "local_run_process_active", lambda _row: False)

    row = dash.filesystem_run_row_from_folder(parent)
    assert row is not None
    assert row["status_text"] == "aborted_stale_no_run_process"
    status = dash._status_payload(row)
    assert status["stage"] == "generic_sweep_preflight_stale"
    assert status["status_authority"] == "dashboard_process_and_artifact_staleness"
    assert status["last_updated_utc"]


def test_dashboard_marks_abandoned_live_stage_run_stale(
    tmp_path, monkeypatch
) -> None:
    run_folder = tmp_path / "results" / "lls" / "h4_gate" / "abandoned_run"
    meta = run_folder / "meta"
    live_dir = run_folder / "air_interface" / "reports" / "csv"
    meta.mkdir(parents=True)
    live_dir.mkdir(parents=True)
    identity = meta / "scenario_config_identity.json"
    resolved = meta / "scenario_config_resolved.json"
    live = live_dir / "live_stage_status.csv"
    identity.write_text(
        json.dumps({"ScenarioID": "h4_gate", "GeneratedUTC": "2026-09-29T00:00:00Z"}),
        encoding="utf-8",
    )
    resolved.write_text(
        json.dumps({
            "meta": {"scenario_id": "h4_gate"},
            "scenario": {"runner_profile": "waveform_bundle"},
        }),
        encoding="utf-8",
    )
    live.write_text(
        "Stage,CurrentSNR_dB,CurrentSlot,TotalSlots,RunCompletion,Notes\n"
        "dl_ul_raw_trials_streaming,40,17,200,0.085,interrupted\n",
        encoding="utf-8",
    )
    stale_time = (
        datetime.now(timezone.utc)
        - timedelta(minutes=dash.STALE_RUNNING_MINUTES + 1)
    ).timestamp()
    for path in (run_folder, meta, live_dir, identity, resolved, live):
        os.utime(path, (stale_time, stale_time))
    monkeypatch.setattr(dash, "local_run_process_active", lambda _row: False)

    row = dash.filesystem_run_row_from_folder(run_folder)
    assert row is not None
    assert row["status_text"] == "aborted_stale_no_run_process"
    status = dash._status_payload(row)
    assert status["stage"] == "live_stage_stale"
    assert status["status_authority"] == "dashboard_process_and_artifact_staleness"
    assert status["last_updated_utc"]


def test_dashboard_csv_parser_accepts_large_exact_phy_vector() -> None:
    packed_vector = "|".join("0" for _ in range(70000))
    raw = ("TrialID,MeasuredLDPCParityCheckVector,CRCPass\n"
           f"1,\"{packed_vector}\",1\n").encode("utf-8")
    header, rows = dash.parse_csv_bytes(raw)
    assert header == ["TrialID", "MeasuredLDPCParityCheckVector", "CRCPass"]
    assert len(rows) == 1
    assert rows[0][1] == packed_vector


def test_dashboard_preserves_sweep_execution_failure_without_phy_rows() -> None:
    raw = (
        'Label,Ok,Returned,ExecutionStatus,ErrorIdentifier,ErrorMessage\n'
        'snr_m30_db,0,0,execution_error,sixgr:test:PublicationFailed,'
        '"No data observations, retained failure\nsecond diagnostic line"\n'
        'snr_20_db,1,1,completed_pass,,\n'
    ).encode('utf-8')
    header, rows = dash.parse_csv_bytes(raw)
    records = [dict(zip(header, row)) for row in rows]
    assert len(records) == 2
    assert records[0]['Ok'] == '0'
    assert records[0]['Returned'] == '0'
    assert records[0]['ExecutionStatus'] == 'execution_error'
    assert records[0]['ErrorIdentifier'] == 'sixgr:test:PublicationFailed'
    assert records[0]['ErrorMessage'].endswith('\nsecond diagnostic line')
    assert records[1]['Ok'] == '1'
    assert not {'BLER', 'ThroughputMbps', 'CRCPass'}.intersection(header)


@pytest.mark.parametrize(
    "live_relative_dir",
    (Path("reports") / "csv", Path("air_interface") / "reports" / "csv"),
)
def test_dashboard_discovers_active_filesystem_run_before_terminal_manifest(
    tmp_path, monkeypatch, live_relative_dir
) -> None:
    results_root = tmp_path / "results"
    run_folder = results_root / "lls" / "active_scenario" / "active_run"
    (run_folder / "meta").mkdir(parents=True)
    live_dir = run_folder / live_relative_dir
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


def test_filesystem_logs_combine_runtime_and_high_level_sources(tmp_path) -> None:
    run_folder = tmp_path / "run"
    air_log = run_folder / "air_interface" / "logs" / "run.log"
    runtime_log = run_folder / "logs" / "run.log"
    air_log.parent.mkdir(parents=True)
    runtime_log.parent.mkdir(parents=True)
    air_log.write_text(
        "[2026-08-23 00:00:01.000] INFO high-level stage\n",
        encoding="utf-8",
    )
    runtime_log.write_text(
        "[2026-08-23 00:00:02.000] INFO slot 2/12 PDSCH transmitted\n",
        encoding="utf-8",
    )
    event_log = run_folder / "runtime" / "journal" / "runtime_events.jsonl"
    event_log.parent.mkdir(parents=True)
    event_log.write_text(
        json.dumps(
            {
                "timestamp_utc": "2026-08-23T00:00:03Z",
                "event_type": "HEARTBEAT",
                "status": "progress",
                "message": "frame-grid artifact committed",
            }
        )
        + "\n",
        encoding="utf-8",
    )

    rows = dash.filesystem_log_rows(
        {"run_folder": str(run_folder), "updated_utc": "2026-08-23T00:00:02Z"},
        limit=10,
        descending=False,
    )

    assert [row["message_text"] for row in rows] == [
        "[2026-08-23 00:00:01.000] INFO high-level stage",
        "[2026-08-23 00:00:02.000] INFO slot 2/12 PDSCH transmitted",
        "[2026-08-23T00:00:03Z] HEARTBEAT progress frame-grid artifact committed",
    ]
    assert [row["source"] for row in rows] == [
        "air_interface/logs/run.log:1",
        "logs/run.log:1",
        "runtime/journal/runtime_events.jsonl:1",
    ]


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


def test_dashboard_publishes_hash_verified_compact_rank4_lls_run(
    tmp_path, monkeypatch
) -> None:
    monkeypatch.delenv("SIXGR_RESULTS_ROOT", raising=False)
    results_root = tmp_path / "results"
    run_folder = (
        results_root
        / "lls"
        / "ran1_waveform_qualification"
        / "rank4_su_mimo"
        / "run_01"
    )
    run_folder.mkdir(parents=True)
    (run_folder / "run_provenance.json").write_text(
        json.dumps(
            {
                "SchemaVersion": "sixgr.lls.run_provenance/v1",
                "ScenarioId": "rank4_su_mimo",
                "ExecutionBackend": "waveform_truth",
                "ApproximationMode": "none",
                "CreatedUTC": "2026-08-10T00:00:00Z",
                "ResultValidity": "complete_valid",
            }
        ),
        encoding="utf-8",
    )
    (run_folder / "resolved_config.json").write_text(
        json.dumps({"scenario": {"id": "rank4_su_mimo"}}),
        encoding="utf-8",
    )
    (run_folder / "bler_vs_snr.csv").write_text(
        "ScenarioId,SNRdB,NumTB,NumBlockErrors,BLER,ExecutionBackend\n"
        "rank4_su_mimo,50,1,0,0,waveform_truth\n",
        encoding="utf-8",
    )
    (run_folder / "truth_contract.csv").write_text(
        "ScenarioId,WaveformGenerated,UsesSyntheticBLER,Status\n"
        "rank4_su_mimo,1,0,valid_waveform_truth\n",
        encoding="utf-8",
    )
    (run_folder / "result_validity.csv").write_text(
        "Check,Pass,Status,Evidence\ntruth_contract,1,PASS,waveform truth executed\n",
        encoding="utf-8",
    )
    (run_folder / "rank4_resource_grid.png").write_bytes(b"verified-raster")
    _write_compact_manifest(
        run_folder,
        [
            "bler_vs_snr.csv",
            "rank4_resource_grid.png",
            "resolved_config.json",
            "result_validity.csv",
            "run_provenance.json",
            "truth_contract.csv",
        ],
    )

    monkeypatch.setattr(dash, "RESULTS_ROOT", results_root)
    dash.clear_dashboard_caches()

    rows = dash.filesystem_run_rows(limit=10)
    assert len(rows) == 1
    row = rows[0]
    assert row["scenario_id"] == "rank4_su_mimo"
    assert row["run_tag"] == "run_01"
    assert row["status_text"] == "completed"
    assert row["profile_name"] == "ran1_waveform_truth"
    assert row["backend"] == "waveform_truth"
    status = dash._status_payload(row)
    assert status["status_authority"] == "run_provenance_and_result_validity"
    assert status["result_ok"] is True
    assert status["runtime_truth_contract_ok"] is True
    assert status["required_failure_count"] == 0

    artifacts = dash.filesystem_artifacts_for_run(row)
    selected, authority = dash.select_primary_result_artifacts(artifacts)
    assert authority["status"] == "compact_lls_manifest_authoritative"
    assert authority["evidence_scope"] == "ran1_waveform_truth"
    assert authority["manifest_hash_verified"] is True
    assert {item["logical_path"] for item in selected} == {
        "artifact_manifest.csv",
        "bler_vs_snr.csv",
        "rank4_resource_grid.png",
        "resolved_config.json",
        "result_validity.csv",
        "run_provenance.json",
        "truth_contract.csv",
    }

    payload = dash.build_live_payload(int(row["run_id"]))
    assert payload["run"]["status_text"] == "completed"
    assert payload["counts"]["tables_total"] == 4
    assert payload["counts"]["images_total"] == 1
    assert payload["realtime_dashboard"]["folder_policy"]["status"] == (
        "compact_lls_manifest_authoritative"
    )


def test_dashboard_publishes_enabled_ntn_compact_lls_evidence(
    tmp_path, monkeypatch
) -> None:
    results_root = tmp_path / "results"
    run_folder = results_root / "lls" / "ntn_waveform" / "ntn_case" / "run_01"
    run_folder.mkdir(parents=True)
    (run_folder / "run_provenance.json").write_text(
        json.dumps(
            {
                "ScenarioId": "ntn_case",
                "ExecutionBackend": "waveform_truth",
                "ResultValidity": "complete_valid",
                "CreatedUTC": "2026-08-10T00:00:00Z",
            }
        ),
        encoding="utf-8",
    )
    (run_folder / "resolved_config.json").write_text(
        json.dumps(
            {
                "schemaVersion": "sixgr.lls.config/v1",
                "scenario": {"id": "ntn_case"},
                "simulation": {"link": "PDSCH"},
                "channel": {"model": "NTN-TDL-D"},
                "ntn": {"enabled": True},
                "harq": {"enabled": False},
                "interference": {"enabled": False},
            }
        ),
        encoding="utf-8",
    )
    (run_folder / "bler_vs_snr.csv").write_text(
        "ScenarioId,SNRdB,NumTB,BLER\nntn_case,30,1,0\n", encoding="utf-8"
    )
    (run_folder / "truth_contract.csv").write_text(
        "ScenarioId,WaveformGenerated,ActualNTNChannel,NTNEvidenceValid,Status\n"
        "ntn_case,1,1,1,valid_waveform_truth\n",
        encoding="utf-8",
    )
    (run_folder / "result_validity.csv").write_text(
        "Check,Pass,Status\nntn_channel_authority,1,PASS\n", encoding="utf-8"
    )
    (run_folder / "ntn_channel_state.csv").write_text(
        "NTNEnabled,NTNProfile,NTNSlantRangeM\n1,NTN-TDL-D,760823.18\n",
        encoding="utf-8",
    )
    (run_folder / "ntn_geometry_and_doppler.png").write_bytes(b"png-evidence")
    _write_compact_manifest(
        run_folder,
        [
            "bler_vs_snr.csv",
            "ntn_channel_state.csv",
            "ntn_geometry_and_doppler.png",
            "resolved_config.json",
            "result_validity.csv",
            "run_provenance.json",
            "truth_contract.csv",
        ],
    )

    monkeypatch.setattr(dash, "RESULTS_ROOT", results_root)
    dash.clear_dashboard_caches()
    row = dash.filesystem_run_rows(limit=10)[0]
    policy = dash.extract_run_feature_policy(row)
    assert policy["ntn_enabled"] is True
    assert policy["harq_enabled"] is False
    assert policy["interference_enabled"] is False
    assert policy["initial_access_enabled"] is False

    payload = dash.build_live_payload(int(row["run_id"]))
    assert payload["feature_policy"]["ntn_enabled"] is True
    assert payload["summary"]["result_ok"] is True
    assert payload["summary"]["runtime_truth_contract_ok"] is True
    assert payload["summary"]["effective_dl_trial_count"] == 1
    assert payload["runtime_context"]["truth_modes"]["waveform_phy_active"] is True
    assert payload["runtime_context"]["truth_modes"]["proxy_phy_active"] is False
    assert payload["runtime_context"]["truth_modes"]["noise_operating_mode"] == (
        "configured_EsN0_per_occupied_QAM_RE"
    )
    assert payload["counts"]["tables_total"] == 5
    assert payload["counts"]["images_total"] == 1
    assert any(
        table["logical_path"] == "ntn_channel_state.csv"
        for table in payload["tables_all"]
    )
    assert any(
        image["logical_path"] == "ntn_geometry_and_doppler.png"
        for image in payload["images_all"]
    )


def test_dashboard_publishes_enabled_isac_compact_lls_evidence(
    tmp_path, monkeypatch
) -> None:
    results_root = tmp_path / "results"
    run_folder = results_root / "lls" / "isac_waveform" / "isac_case" / "run_01"
    run_folder.mkdir(parents=True)
    (run_folder / "run_provenance.json").write_text(
        json.dumps(
            {
                "ScenarioId": "isac_case",
                "ExecutionBackend": "waveform_truth",
                "ResultValidity": "complete_valid",
                "CreatedUTC": "2026-08-11T00:00:00Z",
            }
        ),
        encoding="utf-8",
    )
    (run_folder / "resolved_config.json").write_text(
        json.dumps(
            {
                "schemaVersion": "sixgr.lls.config/v1",
                "scenario": {"id": "isac_case"},
                "simulation": {"link": "PDSCH"},
                "isac": {
                    "enabled": True,
                    "approach": "communication_centric_nr_ofdm",
                    "waveformAuthority": "exact_runtime_pdsch_waveform",
                },
                "harq": {"enabled": False},
                "interference": {"enabled": False},
            }
        ),
        encoding="utf-8",
    )
    (run_folder / "bler_vs_snr.csv").write_text(
        "ScenarioId,SNRdB,NumTB,BLER\nisac_case,35,1,0\n", encoding="utf-8"
    )
    (run_folder / "truth_contract.csv").write_text(
        "ScenarioId,WaveformGenerated,ActualISACSensing,ISACEvidenceValid,Status\n"
        "isac_case,1,1,1,valid_waveform_truth\n",
        encoding="utf-8",
    )
    (run_folder / "result_validity.csv").write_text(
        "Check,Pass,Status\nisac_sensing_authority,1,PASS\n", encoding="utf-8"
    )
    (run_folder / "isac_detections.csv").write_text(
        "DetectionIndex,RangeM,AzimuthDeg,MatchedTargetIndex\n1,39.0,14.0,1\n",
        encoding="utf-8",
    )
    (run_folder / "isac_range_angle_map.png").write_bytes(b"png-evidence")
    (run_folder / "isac_scenario_geometry.png").write_bytes(b"geometry-evidence")
    _write_compact_manifest(
        run_folder,
        [
            "bler_vs_snr.csv",
            "isac_detections.csv",
            "isac_range_angle_map.png",
            "isac_scenario_geometry.png",
            "resolved_config.json",
            "result_validity.csv",
            "run_provenance.json",
            "truth_contract.csv",
        ],
    )

    monkeypatch.setattr(dash, "RESULTS_ROOT", results_root)
    dash.clear_dashboard_caches()
    row = dash.filesystem_run_rows(limit=10)[0]
    policy = dash.extract_run_feature_policy(row)
    assert policy["sensing_enabled"] is True

    payload = dash.build_live_payload(int(row["run_id"]))
    assert payload["feature_policy"]["sensing_enabled"] is True
    assert payload["counts"]["tables_total"] == 5
    assert payload["counts"]["images_total"] == 2
    detection_table = next(
        table
        for table in payload["tables_all"]
        if table["logical_path"] == "isac_detections.csv"
    )
    range_angle_image = next(
        image
        for image in payload["images_all"]
        if image["logical_path"] == "isac_range_angle_map.png"
    )
    assert detection_table["section"] == "isac"
    assert range_angle_image["section"] == "isac"
    assert range_angle_image["bucket"] == "isac"
    scenario_image = next(
        image
        for image in payload["images_all"]
        if image["logical_path"] == "isac_scenario_geometry.png"
    )
    assert scenario_image["section"] == "isac"
    assert scenario_image["bucket"] == "isac"


def test_dashboard_discovers_component_qualification_without_scenario_manifest(
    tmp_path, monkeypatch
) -> None:
    monkeypatch.delenv("SIXGR_RESULTS_ROOT", raising=False)
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
