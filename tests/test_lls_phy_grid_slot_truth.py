from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

pytestmark = pytest.mark.webgui_unit

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def _trace_row(slot: int, token: str, *, grants: int = 0, reason: str = "") -> dict:
    partitions = {
        "D": (14, 0, 0, False),
        "S": (12, 1, 1, True),
        "U": (0, 0, 14, False),
    }
    dl_symbols, guard_symbols, ul_symbols, special = partitions[token]
    return {
        "CanonicalSlot": slot,
        "SpecialSlotActive": special,
        "DLNumSymbols": dl_symbols,
        "GuardNumSymbols": guard_symbols,
        "ULNumSymbols": ul_symbols,
        "DLActiveUsers": 4 if token in {"D", "S"} else 0,
        "DLQueueBits": 120000 if token in {"D", "S"} else 0,
        "DLGrantCount": grants if token in {"D", "S"} else 0,
        "ULActiveUsers": 4 if token in {"U", "S"} else 0,
        "ULQueueBits": 120000 if token in {"U", "S"} else 0,
        "ULGrantCount": grants if token == "U" else 0,
        "DLNoGrantReason": reason if token in {"D", "S"} else "",
        "ULNoGrantReason": reason if token == "U" else "",
    }


def test_slot_trace_is_authoritative_and_idle_is_explicit(monkeypatch: pytest.MonkeyPatch) -> None:
    rows = [_trace_row(index + 1, token, grants=1 if index == 0 else 0) for index, token in enumerate("DDDSU")]
    config = {
        "frame_timing": {
            "slot_duration_ms": 0.5,
            "symbols_per_slot": 14,
            "tdd_common": {
                "Pattern1": {
                    "PeriodicityMilliseconds": 2.5,
                    "NumDownlinkSlots": 3,
                    "NumDownlinkSymbols": 12,
                    "NumUplinkSlots": 1,
                    "NumUplinkSymbols": 1,
                }
            },
        }
    }
    run_row = {
        "run_id": 77,
        "run_tag": "slot-truth",
        "scenario_id": "slot-truth",
        "status_text": "completed",
        "status_json": "{}",
        "config_json": json.dumps(config),
        "updated_utc": "2026-08-02T00:00:00Z",
    }
    monkeypatch.setattr(dash, "fetch_run", lambda _run_id: run_row)
    monkeypatch.setattr(dash, "fetch_artifacts", lambda _run_id: [])
    monkeypatch.setattr(dash, "merge_db_and_filesystem_artifacts", lambda _artifacts, _run: [])

    def select_rows(_artifacts, logical_path, **_kwargs):
        selected = rows if logical_path == "reports/csv/slot_trace.csv" else []
        return selected, {
            "selected_logical_path": logical_path,
            "canonical_logical_path": logical_path,
            "selection_status": "selected" if selected else "unavailable",
            "selected_artifact_id": None,
        }

    monkeypatch.setattr(dash, "select_canonical_csv_rows", select_rows)
    dash.PHY_GRID_PAYLOAD_CACHE.clear()
    payload = dash.build_phy_grid_payload(77, slot_limit=5)
    grid = payload["grid"]

    assert grid["tdd_pattern"] == "DDDSU"
    assert grid["tdd_pattern_source"] == "slot_trace.csv"
    assert [slot["tdd"] for slot in grid["slots"]] == list("DDDSU")
    assert grid["slots"][0]["activity"] == "allocated"
    assert grid["slots"][1]["state_label"] == "DL idle — no grant"
    assert grid["slots"][1]["reason"] == "no_grant_reason_not_exported_by_legacy_run"
    assert grid["slots"][3]["state_label"] == "Special DL/guard/UL slot"
    assert "slot_trace" not in {event.get("table_key") for event in grid["events"]}


def test_tdd_pattern_derives_from_common_pattern_and_nan_is_not_a_ue() -> None:
    cfg = {
        "frame_timing": {
            "slot_duration_ms": 0.5,
            "tdd_common": {
                "Pattern1": {
                    "PeriodicityMilliseconds": 2.5,
                    "NumDownlinkSlots": 3,
                    "NumDownlinkSymbols": 12,
                    "NumUplinkSlots": 1,
                    "NumUplinkSymbols": 1,
                }
            },
        }
    }
    assert dash.phy_grid_configured_tdd_pattern(cfg) == "DDDSU"
    assert dash.phy_grid_shortest_repeating_pattern(list("DDDSUDDDSU")) == "DDDSU"
    assert dash.phy_grid_ue_value({"UEIndex": float("nan")}) == ""
    assert dash.phy_grid_ue_value({"UEIndex": "nan"}) == ""
    assert dash.phy_grid_ue_value({"UEIndex": 4.0}) == "4"


def test_exact_planned_re_rows_render_without_inventing_coordinates(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    trace_rows = [_trace_row(1, "D", grants=1)]
    planned_rows = [
        {
            "absolute_slot": 0,
            "sfn": 0,
            "slot_within_frame": 0,
            "direction": "DL",
            "channel": "PDSCH",
            "component": "PDSCH_DMRS",
            "subcarrier_start": 241,
            "subcarrier_count": 1,
            "symbol_index": 2,
            "port_index": 1,
            "re_count": 1,
            "cell_id": 42,
            "ue_id": 7,
            "layer_count": 2,
            "authority": "resolved_runtime_allocation",
            "resolver": "nrPDSCHDMRSIndices",
            "allocation_id": "pdsch_dmrs_1",
            "coordinate_precision": "exact_sparse_re_span",
            "evidence_scope": "planned_config",
        }
    ]
    config = {
        "resolved_runtime_view": {"active_grid_num_rbs": 25},
        "frame_timing": {"symbols_per_slot": 14},
    }
    run_row = {
        "run_id": 78,
        "run_tag": "exact-grid",
        "scenario_id": "exact-grid",
        "status_text": "running",
        "status_json": "{}",
        "config_json": json.dumps(config),
        "updated_utc": "2026-08-22T00:00:00Z",
    }
    monkeypatch.setattr(dash, "fetch_run", lambda _run_id: run_row)
    monkeypatch.setattr(dash, "fetch_artifacts", lambda _run_id: [])
    monkeypatch.setattr(dash, "merge_db_and_filesystem_artifacts", lambda _artifacts, _run: [])

    def select_rows(_artifacts, logical_path, **_kwargs):
        selected = []
        if logical_path == "reports/csv/slot_trace.csv":
            selected = trace_rows
        elif logical_path == "components/frame_grid/csv/planned_re_allocation.csv":
            selected = planned_rows
        return selected, {
            "selected_logical_path": logical_path,
            "canonical_logical_path": logical_path,
            "selection_status": "selected" if selected else "unavailable",
            "selected_artifact_id": None,
        }

    monkeypatch.setattr(dash, "select_canonical_csv_rows", select_rows)
    dash.PHY_GRID_PAYLOAD_CACHE.clear()
    grid = dash.build_phy_grid_payload(78, slot_limit=1)["grid"]

    assert grid["event_count"] == 1
    event = grid["events"][0]
    assert event["channel"] == "PDSCH-DMRS"
    assert event["slot"] == 1
    assert event["source_slot"] == 0
    assert event["symbol_start"] == 2
    assert event["symbol_count"] == 1
    assert event["subcarrier_start"] == 241
    assert event["subcarrier_count"] == 1
    assert event["prb_start"] == 20
    assert event["prb_count"] == 1
    assert str(event["port_index"]) == "1"
    assert str(event["layer_count"]) == "2"
    assert str(event["cell_id"]) == "42"
    assert event["ue_id"] == "7"
    assert event["coordinate_precision"] == "exact_sparse_re_span"
    assert "display_slot_offset=+1" in event["source_note"]
    assert grid["axis_contract"] == {
        "x": "absolute slot / OFDM symbol",
        "y": "physical resource block / subcarrier span",
        "subcarriers_per_prb": 12,
    }
    assert grid["time_frequency_cell_count"] == 1
    display_cell = grid["time_frequency_cells"][0]
    assert display_cell["slot"] == 1
    assert display_cell["symbol"] == 2
    assert display_cell["prb"] == 20
    assert display_cell["subcarrier_start"] == 240
    assert display_cell["subcarrier_stop"] == 251
    assert display_cell["channels"] == ["PDSCH-DMRS"]
    assert display_cell["port_indices"] == ["1"]
    assert display_cell["layer_counts"] == ["2"]
