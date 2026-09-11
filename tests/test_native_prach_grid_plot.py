"""Declared renderer fixtures; actual producer integration runs in MATLAB."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m


def row(**changes):
    return dict(carrier_origin_slot0=14, native_symbol_index=0,
                native_subcarrier_start=2, native_subcarrier_count=139, port_index=0,
                grid_domain="prach_native_ofdm", grid_subcarrier_count=150, grid_symbol_count=14, grid_port_count=2,
                native_grid_complete=1, native_grid_sha256="a"*64, grid_subcarrier_spacing_hz=30000,
                sample_rate_hz=7680000, port_domain="waveform_port_before_spatial_projection",
                allocation_id="declared_renderer_fixture", cell_id=1, ue_id=1,
                evidence_scope="runtime_observed_tx_occupancy", active_flag=1,
                cp_start_sample_relative=0, useful_start_sample_relative=121,
                useful_end_sample_exclusive_relative=377) | changes


def plot(rows):
    payload=m._encode_dict_rows(list(rows[0]),rows)
    return m._specialized_chart_materialization("PRACH native resource grid",
        {"reports/csv/live_prach_native_allocation_snapshot.csv":{"artifact_id":1}},lambda _:payload,7)


def test_native_axes_and_all_ports_remain_explicit():
    result=plot([row(),row(port_index=1)])
    assert result["source_row_count"]==2
    assert result["csv_status"]=="executed_native_prach_grid_dataset"
    assert "Native PRACH subcarrier index" in result["img_bytes"].decode()
    assert "mapped ports per native RE" in result["img_bytes"].decode()


@pytest.mark.parametrize("changes",[
    {"grid_domain":"carrier_cp_ofdm"}, {"native_grid_complete":0},
    {"native_subcarrier_start":-1}, {"native_subcarrier_count":151},
    {"native_symbol_index":14}, {"native_symbol_index":.5},
    {"useful_end_sample_exclusive_relative":100}, {"native_grid_sha256":""},
    {"evidence_scope":"planned_config_not_runtime_observation"},
])
def test_invalid_native_evidence_is_rejected(changes):
    with pytest.raises(ValueError,match="Native PRACH"):
        plot([row(**changes)])


def test_one_occasion_cannot_mix_incompatible_grid_authorities():
    with pytest.raises(ValueError,match="inconsistent grid authority"):
        plot([row(),row(port_index=1,native_grid_sha256="b"*64)])
