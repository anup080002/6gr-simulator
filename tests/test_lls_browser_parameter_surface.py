from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    applied_text = dash.default_applied_status_text()
    measured_text = dash.default_measured_status_text()

    assert "unavailable until runtime evidence is published" not in applied_text.lower()
    assert "unavailable until runtime evidence is published" not in measured_text.lower()
    assert "resolved in matlab config" in applied_text.lower()
    assert "runtime consumer evidence is not yet instrumented" in applied_text.lower()
    assert "runtime measurement evidence is not yet published" in measured_text.lower()

    prach_taxonomy = dash.parameter_taxonomy_entry("random_access.configuration_index")
    assert prach_taxonomy["feature_family"] == "Random_Access_PRACH"
    assert prach_taxonomy["ui_section"] == "Random_Access_PRACH"

    meta_taxonomy = dash.parameter_taxonomy_entry("meta.scenario_name")
    assert meta_taxonomy["feature_family"] == "Scenario_Metadata"
    assert meta_taxonomy["ui_section"] == "Scenario_Metadata"

    config_payload = {
        "meta": {"scenario_name": "browser_surface_smoke"},
        "run_control": {"execution_mode": "LLS"},
        "frame_timing": {"tdd_pattern": "DDDSU"},
        "random_access": {"enabled": True, "configuration_index": 95},
        "pdcch": {"aggregation_level": 8},
        "output_control": {"save_report": True},
    }
    rows = dash.product_field_records(config_payload)
    by_path = {str(row["path"]): row for row in rows}

    assert by_path["meta.scenario_name"]["ui_section"] == "Scenario_Metadata"
    assert by_path["run_control.execution_mode"]["ui_section"] == "Truth_Contract"
    assert by_path["frame_timing.tdd_pattern"]["ui_section"] == "Carrier_Numerology_Grid"
    assert by_path["random_access.configuration_index"]["ui_section"] == "Random_Access_PRACH"
    assert by_path["pdcch.aggregation_level"]["ui_section"] == "DL_Control_PDCCH_DCI"
    assert by_path["output_control.save_report"]["ui_section"] == "CSV_Image_Exports"

    for path in (
        "meta.scenario_name",
        "run_control.execution_mode",
        "frame_timing.tdd_pattern",
        "random_access.configuration_index",
        "pdcch.aggregation_level",
        "output_control.save_report",
    ):
        row = by_path[path]
        assert row["ui_section"] != "Uncategorized"
        assert row["feature_family"] != "Uncategorized"
        assert row["applied_value"] == applied_text
        assert row["measured_value"] == measured_text


if __name__ == "__main__":
    main()
