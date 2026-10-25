"""Declared CSV populations exercise the real grid reader, not PHY evidence."""
from __future__ import annotations

import csv
import hashlib
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as dash

pytestmark = pytest.mark.webgui_unit


def write_csv(path, rows):
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def allocation(slot, *, channel="CSI-RS", identity="original", occurrences="", count=""):
    return dict(absolute_slot=slot, direction="DL" if channel == "CSI-RS" else "UL",
                channel=channel, component=channel, subcarrier_start=12,
                subcarrier_count=1, symbol_index=3, port_index=0, ue_id=1,
                allocation_id=identity, occurrence_slots=occurrences, occurrence_count=count,
                coordinate_precision="exact_contiguous_re_run",
                evidence_scope="runtime_observed_tx_occupancy", SourceSHA256="001234")


def install_run(monkeypatch, tmp_path, rows, trace_slots=(6,), planned=None):
    artifacts = []
    sources = [("components/frame_grid/csv/observed_re_allocation.csv", rows)]
    if trace_slots:
        sources.append(("reports/csv/slot_trace.csv", [dict(CanonicalSlot=s,
            DLNumSymbols=14, DLSymbolStart=0, ULNumSymbols=0,
            ULSymbolStart=0, GuardNumSymbols=0, SpecialSlotActive=False) for s in trace_slots]))
    if planned is not None:
        sources.append(("components/frame_grid/csv/planned_re_allocation.csv", planned))
    for index, (logical, records) in enumerate(sources):
        path = tmp_path / f"source_{index}.csv"
        write_csv(path, records)
        artifacts.append(dict(artifact_id=index + 1, logical_path=logical,
                              filesystem_path=str(path), byte_size=path.stat().st_size))
    run = dict(run_id=73, run_tag="declared-window-fixture", status_text="completed",
               updated_utc="fixed", status_json="{}", config_json=json.dumps({
                   "resolved_runtime_view": {"active_grid_num_rbs": 51},
                   "frame_timing": {"symbols_per_slot": 14}}))
    monkeypatch.setattr(dash, "fetch_run", lambda _: run)
    monkeypatch.setattr(dash, "fetch_artifacts", lambda _: artifacts)
    monkeypatch.setattr(dash, "merge_db_and_filesystem_artifacts", lambda a, _: a)
    dash.PHY_GRID_PAYLOAD_CACHE.clear()
    return artifacts


def test_late_unsorted_requested_rows_survive_old_cap_without_coercing_other_slots(monkeypatch, tmp_path):
    rows = [allocation(49, identity="outside")] * 100001
    rows += [allocation(5, identity="late-first"), allocation(4, identity="outside-before"),
             allocation(5, identity="late-second")]
    artifacts = install_run(monkeypatch, tmp_path, rows)
    path = Path(artifacts[0]["filesystem_path"])
    before = hashlib.sha256(path.read_bytes()).hexdigest()
    converted = []
    original = dash.coerce_csv_cell

    def record(name, raw):
        if name == "allocation_id":
            converted.append(raw)
        return original(name, raw)

    monkeypatch.setattr(dash, "coerce_csv_cell", record)
    payload = dash.build_phy_grid_payload(73, slot_limit=1)
    grid = payload["grid"]
    assert grid["event_count"] == 2
    assert {x["allocation_id"] for x in grid["events"]} == {"late-first", "late-second"}
    assert {(x["source_slot"], x["slot"], x["direction"]) for x in grid["events"]} == {(5, 6, "DL")}
    assert "outside" not in converted and "outside-before" not in converted
    assert all(x["event_count"] == 2 for x in grid["time_frequency_cells"])
    assert hashlib.sha256(path.read_bytes()).hexdigest() == before
    meta = next(x for x in payload["table_status"] if x["table_key"] == "observed_re_allocation")
    assert meta["rows_loaded"] == 2 and meta["row_population_scope"] == "complete_requested_slot_window"


def test_periodic_template_and_details_zero_preserve_exact_overlay(monkeypatch, tmp_path):
    install_run(monkeypatch, tmp_path, [allocation(5)], planned=[
        allocation(0, identity="periodic", occurrences="0|5|10", count=3),
        allocation(0, identity="bad-count", occurrences="0|5", count=3)])
    full = dash.build_phy_grid_payload(73, slot_limit=1)
    compact = dash.build_phy_grid_payload(73, slot_limit=1, include_details=False)
    assert full["grid"]["event_count"] == compact["grid"]["event_count"] == 2
    assert compact["grid"]["events"] == []
    assert compact["grid"]["time_frequency_cells"] == full["grid"]["time_frequency_cells"]
    assert compact["dataflow"] == full["dataflow"]
    assert {(r["source_slot"], r["slot"]) for r in full["grid"]["events"]} == {(5, 6)}
    assert {r["allocation_id"] for r in full["grid"]["events"]} == {"original", "periodic"}


def test_zero_based_trace_and_original_literal_cells(monkeypatch, tmp_path):
    artifacts = install_run(monkeypatch, tmp_path, [allocation(0), allocation(1)], trace_slots=(0,))
    choose = dash.phy_grid_allocation_window_filter([{"CanonicalSlot": 0}], 1)
    rows, _ = dash.select_canonical_csv_rows(artifacts, artifacts[0]["logical_path"],
                                           max_rows=None, raw_row_filter=choose)
    assert len(rows) == 1 and rows[0]["SourceSHA256"] == "001234"
    assert rows[0]["port_index"] == 0
    result = dash.build_phy_grid_payload(73, slot_limit=1)
    assert [(e["source_slot"], e["slot"]) for e in result["grid"]["events"]] == [(0, 0)]


def test_missing_trace_retains_all_source_records_without_invented_window(monkeypatch, tmp_path):
    artifacts = install_run(monkeypatch, tmp_path, [allocation(5), allocation(1)], trace_slots=())
    rows, _ = dash.select_canonical_csv_rows(artifacts, artifacts[0]["logical_path"],
        max_rows=None, raw_row_filter=dash.phy_grid_allocation_window_filter([], 1))
    assert [r["absolute_slot"] for r in rows] == [5, 1]


def test_canonical_outside_window_does_not_fall_back_to_legacy(monkeypatch, tmp_path):
    artifacts = install_run(monkeypatch, tmp_path, [allocation(49)])
    legacy = tmp_path / "legacy.csv"
    write_csv(legacy, [allocation(5, identity="must-not-substitute")])
    artifacts.append(dict(artifact_id=99, logical_path="legacy.csv", filesystem_path=str(legacy)))
    rows, meta = dash.select_canonical_csv_rows(artifacts, artifacts[0]["logical_path"],
        legacy_paths=["legacy.csv"], max_rows=None,
        raw_row_filter=dash.phy_grid_allocation_window_filter([{"CanonicalSlot": 6}], 1))
    assert rows == [] and meta["selection_status"] == "canonical_empty"
    assert not meta["fallback_used"]


def test_cache_age_starts_when_slow_build_finishes_and_return_is_isolated(monkeypatch, tmp_path):
    install_run(monkeypatch, tmp_path, [allocation(5)])

    class Clock(datetime):
        elapsed = 0

        @classmethod
        def now(cls, tz=None):
            return cls(2026, 10, 25, tzinfo=timezone.utc) + timedelta(seconds=cls.elapsed)

    monkeypatch.setattr(dash, "datetime", Clock)
    original = dash.select_canonical_csv_rows
    calls = []

    def slow(*args, **kwargs):
        calls.append(args[1])
        if args[1].endswith("observed_re_allocation.csv"):
            Clock.elapsed += 8
        return original(*args, **kwargs)

    monkeypatch.setattr(dash, "select_canonical_csv_rows", slow)
    first = dash.build_phy_grid_payload(73, slot_limit=1)
    count = len(calls)
    first["grid"]["events"][0]["slot"] = 999
    second = dash.build_phy_grid_payload(73, slot_limit=1)
    assert len(calls) == count and second["grid"]["events"][0]["slot"] == 6
    Clock.elapsed += 6
    dash.build_phy_grid_payload(73, slot_limit=1)
    assert len(calls) > count


def test_window_filter_does_not_change_first_nonempty_legacy_source(monkeypatch, tmp_path):
    artifacts = []
    for index, slot in enumerate([49, 5]):
        path = tmp_path / f"legacy{index}.csv"
        write_csv(path, [allocation(slot)])
        artifacts.append(dict(artifact_id=index + 1, logical_path=path.name, filesystem_path=str(path)))
    rows, meta = dash.select_canonical_csv_rows(artifacts, "absent.csv",
        legacy_paths=["legacy0.csv", "legacy1.csv"], max_rows=None,
        raw_row_filter=dash.phy_grid_allocation_window_filter([{"CanonicalSlot": 6}], 1))
    assert rows == [] and meta["selected_logical_path"] == "legacy0.csv"


def test_shared_header_index_preserves_per_row_blank_and_case_alias_precedence():
    names = {"a": "A", "b": "B"}
    first = dash._GridCSVRow({"A": "", "B": "first"}, names)
    second = dash._GridCSVRow({"A": "second", "B": "other"}, names)
    for row in [first, second, first]:
        assert dash.first_present_value(row, ["a", "b"]) == dash.first_present_value(dict(row), ["a", "b"])
    assert dash.first_present_value(first, ["absent"], "missing") == "missing"
