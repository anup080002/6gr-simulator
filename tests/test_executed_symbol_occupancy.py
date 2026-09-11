"""Analytic reporting fixtures; not waveform or receiver qualification."""
import csv
import io
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m

NAME = "frame/slot/symbol occupancy timeline"
SOURCE = "reports/csv/live_re_allocation_snapshot.csv"


def record(slot=2, symbol=4, **kw):
    return {"absolute_slot": slot, "symbol_index": symbol, "cell_id": 1,
            "direction": "DL", "subcarrier_count": 1, "port_index": 0,
            "active_flag": 1, "evidence_scope": "runtime_observed_tx_occupancy", **kw}


def plot(rows):
    header = sorted(set().union(*(row.keys() for row in rows)))
    payload = m._encode_dict_rows(header, rows)
    return m._specialized_chart_materialization(NAME,
        {SOURCE: {"artifact_id": 1}}, lambda _: payload, 7)


def decoded(result):
    return list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))


def test_count_distinct_executed_symbols_not_re_rows_or_ports():
    result = plot([record(), record(), record(port_index=1),
                   record(symbol=8), record(symbol=10, active_flag=0)])
    rows = decoded(result)
    assert len(rows) == 1
    assert rows[0]["x_value"] == "2" and rows[0]["y_value"] == "2"
    assert rows[0]["symbol_indices_0based"] == "4|8"
    assert rows[0]["source_row_count"] == "4"
    assert rows[0]["scope_identity_status"] == "partial_carrier_or_bwp_not_exported"
    assert "Absolute slot (0-based)" in result["img_bytes"].decode()


def test_scopes_and_missing_intervals_are_not_merged_or_filled():
    rows = decoded(plot([record(), record(slot=4), record(direction="UL"),
                         record(cell_id=2), record(component_carrier=1),
                         record(bwp_id=2)]))
    assert len(rows) == 6
    assert all(row["y_value"] == "1" for row in rows)
    assert {row["x_value"] for row in rows} == {"2", "4"}
    assert {row["direction"] for row in rows} == {"DL", "UL"}


def test_only_slot_capacity_is_explicitly_unavailable():
    payload = m._encode_csv(["CanonicalSlot", "DLNumSymbols"], [[3, 14]])
    result = m._specialized_chart_materialization(NAME,
        {"reports/csv/slot_trace.csv": {"artifact_id": 1}}, lambda _: payload, 7)
    assert result["csv_status"] == "unavailable_exact_reason"
    assert "y_value" not in decoded(result)[0]
    assert result["source_row_count"] == 0


@pytest.mark.parametrize("change", [
    {"symbol_index": -1}, {"symbol_index": 0.5}, {"absolute_slot": "NaN"},
    {"subcarrier_count": -1}, {"active_flag": "unknown"},
    {"direction": "GUARD"}, {"evidence_scope": "configured_capacity"},
    {"grid_domain": "prach_native_ofdm"}, {"channel": "PRACH"},
])
def test_invalid_or_unexecuted_evidence_is_not_silently_skipped(change):
    with pytest.raises(ValueError, match="Occupancy row"):
        plot([record(), record(**change)])


def test_zero_active_re_rows_do_not_invent_a_zero_timeline():
    result = plot([record(active_flag=0)])
    assert result["csv_status"] == "unavailable_exact_reason"


def test_complete_scope_requires_both_exported_carrier_and_bwp():
    rows = decoded(plot([record(component_carrier=0, bwp_id=0)]))
    assert rows[0]["scope_identity_status"] == "complete"
    assert rows[0]["component_carrier"] == "0" and rows[0]["bwp_id"] == "0"


def test_same_slot_dl_ul_is_an_observed_snapshot_not_a_sweep():
    rows = decoded(plot([record(), record(direction="UL")]))
    assert all(row["evidence_shape_policy"] == "operating_point" for row in rows)
    assert all(int(row["source_sample_count"]) == 1 for row in rows)


def test_independent_audit_rejects_capacity_and_wrong_counts(tmp_path):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
    from lls_csv_semantics import _executed_symbol_occupancy_failures

    records = [record(), record(symbol=8), record(port_index=1)]
    target = tmp_path / SOURCE
    target.parent.mkdir(parents=True)
    target.write_bytes(m._encode_dict_rows(list(records[0]), records))
    points = decoded(plot(records))
    assert not _executed_symbol_occupancy_failures(tmp_path, points)
    points[0]["y_value"] = "14"
    assert "distinct_symbol_count_mismatch" in "|".join(_executed_symbol_occupancy_failures(tmp_path, points))
    points[0]["source_table_logical_path"] = "reports/csv/slot_trace.csv"
    assert _executed_symbol_occupancy_failures(tmp_path, points) == ["occupancy_uses_nonexecuted_source"]


def test_independent_audit_rejects_missing_and_duplicate_scopes(tmp_path):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
    from lls_csv_semantics import _executed_symbol_occupancy_failures

    records = [record(), record(direction="UL")]
    target = tmp_path / SOURCE
    target.parent.mkdir(parents=True)
    target.write_bytes(m._encode_dict_rows(list(records[0]), records))
    points = decoded(plot(records))
    assert not _executed_symbol_occupancy_failures(tmp_path, points)
    assert "occupancy_executed_scope_coverage_mismatch" in _executed_symbol_occupancy_failures(tmp_path, points[:1])
    assert "duplicate_scope" in "|".join(_executed_symbol_occupancy_failures(tmp_path, points + points[:1]))
