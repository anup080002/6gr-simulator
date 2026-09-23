"""Declared chart fixtures; no waveform or SINR calibration claim."""
import csv
import io
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m


def render(changes=None, directions=("DL", "UL")):
    sources = {}
    for direction in directions:
        rows = []
        for point, snr in enumerate((-30, 40), 1):
            row = dict(Direction=direction, Slot=35, UEIndex=1, CellID=1,
                       SweepPointIndex=point, ConfiguredSNR_dB=snr,
                       PostEqSINR_dB=snr + (1 if direction == "DL" else 2),
                       PostEqSINRSource="receiver_post_equalization_data_measurement",
                       PostEqSINRValueRole="measured_post_equalization_scheduling_input",
                       PostEqSINRValueStatus="OK_decision_residual_bounded")
            row.update(changes or {})
            rows.append(row)
        stream = io.StringIO()
        writer = csv.DictWriter(stream, list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
        channel = "pdsch" if direction == "DL" else "pusch"
        sources[f"air_interface/csv/{direction.lower()}_{channel}_trials.csv"] = stream.getvalue().encode()
    data = dict(enumerate(sources.values(), 1))
    existing = {path: dict(artifact_id=i, logical_path=path) for i, path in enumerate(sources, 1)}
    result = m._specialized_chart_materialization("measured_sinr_vs_slot", existing, data.__getitem__, 1)
    assert result is not None
    return result, list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))


def test_sinr_timeline_keeps_both_directions_and_repeated_slots():
    result, rows = render()
    assert len(rows) == 4
    assert {r["direction"] for r in rows} == {"DL", "UL"}
    assert {float(r["measured_sinr_db"]) for r in rows} == {-29, -28, 41, 42}
    assert {int(r["sweep_point_index"]) for r in rows} == {1, 2}
    assert {float(r["configured_snr_db"]) for r in rows} == {-30, 40}
    assert all(r["configured_snr_value_role"] == "configured_operating_point_metadata" for r in rows)
    svg = result["img_bytes"].decode()
    for direction in ("DL", "UL"):
        assert direction in svg
    assert "point 1" in svg and "point 2" in svg


@pytest.mark.parametrize("changes", [
    {"PostEqSINRSource": "configured_sweep"},
    {"PostEqSINRValueRole": "estimated"},
    {"PostEqSINRValueStatus": "FAILED"},
    {"PostEqSINRValueStatus": ""},
    {"Slot": ""},
])
def test_sinr_timeline_cannot_use_ineligible_or_slotless_values(changes):
    result, _ = render(changes)
    assert result["csv_status"] == "unavailable_exact_reason"


def test_sinr_timeline_keeps_ul_when_dl_is_absent():
    result, rows = render(directions=("UL",))
    assert len(rows) == 2 and all(r["direction"] == "UL" for r in rows)
    assert result["source_row_count"] == 2
