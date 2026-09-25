"""Publication-only fixtures; no channel estimates or success are synthesized."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m
from lls_pdcch_unavailable_plot import unobserved_pdcch_channel_chart
from test_directional_no_data_publication import artifacts, fixture


def tables():
    result = fixture("DL")
    fields = ["Slot", "Direction", "CRCPass", "DecodeAttempted",
              "ChannelEstimateAvailable", "ConfiguredSNR_dB"]
    for path in ("control/csv/pdcch_trials.csv", "air_interface/csv/pdcch_trials.csv"):
        result[path] = (fields, [])
    return result


def render(source, name="PDCCH channel-estimate magnitude"):
    entries, fetch = artifacts(source)
    existing = {entry["logical_path"]: entry for entry in entries}
    return unobserved_pdcch_channel_chart(name, existing, fetch, 17)


@pytest.mark.parametrize("kind", ["magnitude", "phase"])
def test_explicit_unavailability_preserves_completed_failed_run(kind):
    source = tables()
    result = render(source, f"PDCCH channel-estimate {kind}")
    assert result["source_row_count"] == 0
    fields, rows = m._decode_csv_dicts(result["csv_bytes"])
    assert len(rows) == 1 and rows[0]["status"] == "unavailable_no_recorded_pdcch_reception"
    assert rows[0]["ConfiguredSNR_dB"] == "-10.0" and rows[0]["CompletedSlots"] == "2"
    assert not {"HReal", "HImag", "Magnitude", "Phase_rad", "CRCPass"}.intersection(fields)
    assert b"not observed" in result["img_bytes"]
    assert source["reports/csv/scenario_summary.csv"][1][0]["RunCompletion"] == "completed_with_failures"


@pytest.mark.parametrize("path", list(tables()))
def test_missing_authority_is_not_hidden(path):
    source = tables()
    del source[path]
    assert render(source) is None


@pytest.mark.parametrize("path", ["control/csv/pdcch_trials.csv", "air_interface/csv/pdcch_trials.csv"])
@pytest.mark.parametrize("passed", [0, 1])
def test_any_recorded_pdcch_trial_keeps_strict_estimate_requirement(path, passed):
    source = tables()
    source[path][1].append(dict(Slot=2, Direction="DL", CRCPass=passed,
                               DecodeAttempted=1, ChannelEstimateAvailable=1, ConfiguredSNR_dB=-10))
    assert render(source) is None


@pytest.mark.parametrize("path,columns,rows", [
    ("control/csv/pdcch_trials.csv", ["Slot"], []),
    ("control/csv/pdcch_channel_estimates.csv", [], []),
    ("control/csv/pdcch_channel_estimates.csv", ["HReal", "HImag"], [dict(HReal=1, HImag=0)]),
])
def test_malformed_or_contradictory_capture_is_not_hidden(path, columns, rows):
    source = tables()
    source[path] = (columns, rows)
    assert render(source) is None


def test_partial_or_cross_point_clock_is_not_completed_absence():
    source = tables()
    source["reports/csv/run_state.csv"][1][0]["CurrentCanonicalSlot"] = 1
    assert render(source) is None
    source = tables()
    source["reports/csv/slot_trace.csv"][1][1]["ConfiguredSNR_dB"] = 20
    assert render(source) is None


def test_unrelated_chart_is_not_relaxed():
    assert render(tables(), "PUCCH BLER vs measured SINR") is None
