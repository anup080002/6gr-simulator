from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    page = dash.build_analytics_page(None, run_tag="unit_output_coverage", user_profile=None).decode(
        "utf-8",
        errors="ignore",
    )
    for token in (
        'data-analytics-tab-button="coverage"',
        'data-analytics-tab-button="rootcause"',
        'data-analytics-tab-panel="coverage"',
        'data-analytics-tab-panel="rootcause"',
        "coverageRegistryBody",
        "coverageImplementationBody",
        "coverageUnavailableBody",
        "coverageCompareBody",
        "coverageOutputCards",
        "kpiHealthBody",
        "KPI Health Flags",
        "rootCauseBody",
        "powerEnergyPreviewBody",
        "prbPreviewBody",
        "backend_source_exists_flag",
        "export_supported_flag",
        "Overstated Implemented",
        "renderOutputFamilyCards",
        "/outputs/",
        "renderCoveragePanel",
        "renderRootCausePanel",
    ):
        assert token in page, f"Analytics page must expose output coverage/root-cause UI token: {token}"

    assert dash.classify_result_section("reports/csv/output_coverage_registry.csv") == "summary"
    assert dash.classify_result_section("reports/csv/lls_implementation_register.csv") == "summary"
    assert dash.classify_result_section("reports/csv/honest_unavailable_registry.csv") == "summary"
    assert dash.classify_result_section("reports/csv/root_cause_candidate_table.csv") == "summary"

    empty = dash.build_output_coverage_context([])
    for key in (
        "registry",
        "implementation_register",
        "completeness",
        "api_audit",
        "persistence_audit",
        "honest_unavailable",
        "compare_prerequisites",
        "kpi_health_flags",
        "dashboard_cards",
        "output_family_cards",
        "artifact_links",
    ):
        assert key in empty, f"Live payload coverage block must always include {key}."

    labels = {str(card.get("label")) for card in empty["dashboard_cards"]}
    assert "Registry Rows" in labels
    assert "Implementation Rows" in labels
    assert "Unavailable Reasons" in labels
    assert "Overstated Implemented" in labels
    assert "KPI Health Rows" in labels
    assert empty["overstated_implemented_count"] == 0

    cards = dash.build_output_family_cards(
        [
            {
                "output_name": "table_latency",
                "ui_section": "latency",
                "block_module": "packet_latency",
                "current_status": "unavailable",
                "classification_code": "a",
                "backend_source_exists_flag": 0,
                "persisted_flag": 0,
                "api_exposed_flag": 0,
                "export_supported_flag": 0,
                "ui_rendered_flag": 1,
                "blocker_reason": "backend_source_missing",
                "target_phase": "phase_backlog",
                "run_id": 42,
            },
            {
                "output_name": "power_energy_table",
                "ui_section": "energy",
                "block_module": "rf_energy",
                "current_status": "implemented",
                "classification_code": "c",
                "backend_source_exists_flag": 1,
                "persisted_flag": 1,
                "api_exposed_flag": 1,
                "export_supported_flag": 1,
                "ui_rendered_flag": 1,
                "blocker_reason": "",
                "target_phase": "phase_now",
                "run_id": 42,
            },
        ],
        [
            {
                "output_name": "table_latency",
                "unavailable_reason": "backend_source_missing",
                "next_implementation_step": "persist packet lifecycle timestamps",
            }
        ],
        [{"output_name": "power_energy_table", "backend_source": "rf_energy", "api_route": "/api/run/<run_id>/live"}],
        [{"output_name": "power_energy_table", "writer_enabled": 1}],
        [],
    )
    assert len(cards) == 2
    latency = next(item for item in cards if item["output_name"] == "table_latency")
    assert latency["href"] == "/outputs/table_latency?run_id=42"
    assert latency["reason_code"] == "backend_source_missing"
    assert latency["next_action"] == "persist packet lifecycle timestamps"
    energy = next(item for item in cards if item["output_name"] == "power_energy_table")
    assert energy["current_status"] == "implemented"
    assert energy["source_mapping"] == "rf_energy"

    family_index = dash.build_outputs_index_page(None, run_tag="unit_output_coverage", user_profile=None).decode(
        "utf-8",
        errors="ignore",
    )
    assert "Output Families" in family_index
    assert "Waiting for the run row" in family_index


if __name__ == "__main__":
    main()
