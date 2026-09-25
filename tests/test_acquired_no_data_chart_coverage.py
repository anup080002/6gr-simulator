"""Publication-only fixtures: successful access does not imply data attempts."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as materializer
from test_directional_no_data_publication import artifacts, fixture


def acquired_without_data():
    tables = fixture("DL")
    for path, (fields, rows) in fixture("UL").items():
        if path not in tables:
            tables[path] = (fields, rows)
            continue
        prior_fields, prior_rows = tables[path]
        assert len(prior_rows) == len(rows)
        merged_rows = [dict(left, **right) for left, right in zip(prior_rows, rows)]
        tables[path] = (list(dict.fromkeys(prior_fields + fields)), merged_rows)
    fields = ["CRCPass", "Crash", "SSBIdentityVerified", "SelectedBeamFlag"]
    tables["air_interface/csv/pbch_trials.csv"] = (fields, [dict(zip(fields, [1, 0, 1, 1]))])
    return tables


def test_both_directions_without_attempts_do_not_require_failed_acquisition():
    entries, fetch = artifacts(acquired_without_data())
    for direction in ("DL", "UL"):
        assert materializer._no_data_chart_sources(entries, fetch, direction=direction)
    proof = materializer._no_data_chart_sources(entries, fetch)
    assert proof, "Completed no-data evidence remains valid after successful acquisition."
    assert {"packet_flow/csv/live_dl_scheduler_grants.csv",
            "packet_flow/csv/live_ul_scheduler_grants.csv"}.issubset(proof)


def test_acquired_no_data_constellation_is_unavailable_not_missing_or_success(monkeypatch):
    entries, fetch = artifacts(acquired_without_data())
    specs = [dict(chart_name="post-equalization constellation", section_slug="fixture")]
    monkeypatch.setattr(materializer, "_table_specs", lambda: [])
    monkeypatch.setattr(materializer, "_chart_specs", lambda: specs)
    coverage = materializer.coverage_summary(entries,
        {"constellation_capture_enabled": True}, fetch_artifact_bytes=fetch)
    assert coverage["charts_available"] == 0
    assert coverage["charts_policy_disabled"] == 0
    assert coverage["unavailable_chart_names"] == ["post-equalization constellation"]
    assert coverage["missing_chart_names"] == []


@pytest.mark.parametrize("direction", ["DL", "UL"])
def test_single_real_attempt_prevents_global_no_data_explanation(direction):
    tables = acquired_without_data()
    channel = "pdsch" if direction == "DL" else "pusch"
    path = f"air_interface/csv/{direction.lower()}_{channel}_trials.csv"
    tables[path] = (["Slot", "CRCPass"], [dict(Slot=2, CRCPass=0)])
    entries, fetch = artifacts(tables)
    assert not materializer._no_data_chart_sources(entries, fetch)


def test_missing_direction_authority_cannot_be_excused_by_successful_access():
    tables = acquired_without_data()
    del tables["packet_flow/csv/live_ul_scheduler_grants.csv"]
    entries, fetch = artifacts(tables)
    assert not materializer._no_data_chart_sources(entries, fetch)


@pytest.mark.parametrize("path", [
    "air_interface/csv/dl_constellation_samples.csv",
    "air_interface/csv/ul_constellation_samples.csv",
    "reports/csv/equalized_constellations.csv",
])
def test_contradictory_constellation_samples_are_not_hidden(path):
    tables = acquired_without_data()
    tables[path] = (["I", "Q"], [dict(I=1, Q=0)])
    entries, fetch = artifacts(tables)
    assert not materializer._no_data_chart_sources(entries, fetch)


def test_incomplete_physical_clock_is_not_completed_no_data():
    tables = acquired_without_data()
    tables["reports/csv/run_state.csv"][1][0]["CurrentCanonicalSlot"] = 1
    entries, fetch = artifacts(tables)
    assert not materializer._no_data_chart_sources(entries, fetch)


def test_no_executed_data_beam_does_not_claim_failed_acquisition():
    entries, fetch = artifacts(acquired_without_data())
    existing = {entry["logical_path"]: entry for entry in entries}
    result = materializer._runtime_beam_pattern_chart(
        "executed data beam pattern", existing, fetch, 1)
    assert result["csv_status"] == "unavailable_exact_reason"
    assert result["source_row_count"] == 0
    assert "PBCH acquisition failed" not in result["note"]
    assert "zero data grants" in result["note"]
