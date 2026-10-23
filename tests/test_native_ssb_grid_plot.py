"""Renderer fixtures; waveform-derived producer coverage is tested in MATLAB."""
import csv
import io
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m
from lls_contract_aliases import CONTRACT_TABLE_ALIAS_PATHS

PATH = "reports/csv/live_ssb_native_allocation_snapshot.csv"


def row(**changes):
    return dict(channel="SSB", grid_domain="ssb_native_cp_ofdm", component="PSS",
        evidence_scope="runtime_observed_tx_occupancy", active_flag=1, ConfigHash="fixture",
        cell_id=1, ssb_index0=0, allocation_id="declared_renderer_fixture", transmit_grid_sha256="a" * 64,
        native_symbol_index_from_burst=2, port_index=0, native_subcarrier_start=56, native_subcarrier_count=127,
        grid_subcarrier_count=240, grid_symbol_count=280, grid_subcarrier_spacing_hz=30000,
        observation_sample_rate_hz=30720000, cp_start_sample=2208, useful_start_sample=2280,
        useful_end_sample_exclusive=3304, broadcast_start_sample=0, broadcast_end_sample_exclusive=276480,
        frequency_first_hz=-2070000, frequency_last_hz=1710000, ConfiguredSNR_dB=40, SweepPointIndex=1) | changes


def plot(rows):
    payload = m._encode_dict_rows(list(rows[0]), rows)
    return m._specialized_chart_materialization("SSB/PBCH occupancy map", {PATH: {"artifact_id": 1}}, lambda _: payload, 7)


def test_all_sweep_points_and_ports_share_one_native_dataset():
    result = plot([row(), row(port_index=1), row(ConfiguredSNR_dB=-10, SweepPointIndex=2)])
    data = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert result["source_row_count"] == 3 and len(data) == 254
    assert {r["ConfiguredSNR_dB"] for r in data} == {"40", "-10"}
    assert {r["mapped_port_count"] for r in data if r["ConfiguredSNR_dB"] == "40"} == {"2"}
    assert result["csv_status"] == "executed_native_ssb_grid_dataset"
    assert "Absolute TX time (ms)" in result["img_bytes"].decode()
    assert "carrier PRBs" in result["img_bytes"].decode()
    assert "ConfiguredSNR_dB=-10" in result["img_bytes"].decode()
    assert CONTRACT_TABLE_ALIAS_PATHS["live_ssb_native_allocation_snapshot"] == [PATH]


@pytest.mark.parametrize("changes", [
    {"grid_domain": "carrier_cp_ofdm"}, {"ConfigHash": ""}, {"transmit_grid_sha256": ""},
    {"useful_end_sample_exclusive": 3305}, {"native_subcarrier_start": 200},
    {"frequency_last_hz": 1700000}, {"component": "invented"},
    {"evidence_scope": "planned_config_not_runtime_observation"},
])
def test_invalid_native_evidence_rejected(changes):
    with pytest.raises(ValueError, match="Native SSB"):
        plot([row(**changes)])


def test_same_occasion_cannot_mix_grid_hashes_or_ownership():
    with pytest.raises(ValueError, match="conflicting grid authority"):
        plot([row(), row(port_index=1, transmit_grid_sha256="b" * 64)])
    with pytest.raises(ValueError, match="same RE"):
        plot([row(), row(port_index=1, component="SSS")])
