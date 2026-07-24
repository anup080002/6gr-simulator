from __future__ import annotations

import csv
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_output_contract as contract  # noqa: E402
import lls_web_dashboard as dash  # noqa: E402


def _read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def test_contract_sections_and_context() -> None:
    assert len(contract.REPORT_SECTIONS) == 25
    assert len(contract.ANALYTICS_SECTIONS) == 19
    assert {"direction", "ue_id", "bs_id", "sfn", "slot", "symbol"}.issubset(contract.BASE_CONTEXT_COLUMNS)
    for kind in ("reports", "analytics"):
        for row in contract.iter_table_specs(kind):
            columns = set(row["required_columns"])
            for required in contract.MANDATORY_CONTEXT_COLUMNS:
                assert required in columns, f"{row['table_name']} missing {required}"
            assert "value_role" in columns
            assert "value_source" in columns
            assert "value_status" in columns
            assert "na_reason" in columns
            assert row["smoke_visible_default"] is False
            assert row["placeholder_flag_default"] is False
            assert row["fallback_flag_default"] is False
        for chart in contract.iter_chart_specs(kind):
            assert chart["requires_real_data"] is True
            assert chart["lineage_required"] is True
            assert chart["placeholder_chart_allowed"] is False


def test_contract_covers_required_domains() -> None:
    report_names = " ".join(row["table_name"] for row in contract.iter_table_specs("reports")).lower()
    analytics_names = " ".join(row["table_name"] for row in contract.iter_table_specs("analytics")).lower()
    for token in (
        "scheduler",
        "mac",
        "pdcch",
        "pbch",
        "pdsch",
        "pusch",
        "pucch",
        "prach",
        "srs",
        "csirs",
        "harq",
        "beam",
        "mimo",
        "ue",
        "gnb",
        "power",
        "energy",
        "handover",
    ):
        assert token in report_names or token in analytics_names, f"missing coverage token {token}"


def test_generated_deliverables_exist_and_are_additive() -> None:
    required_files = [
        "docs/REPORTS_COMPLETE_OUTPUT_SPEC.md",
        "docs/ANALYTICS_COMPLETE_OUTPUT_SPEC.md",
        "docs/POWER_ENERGY_OUTPUT_SPEC.md",
        "docs/SCHEDULER_MAC_PHY_OUTPUT_SPEC.md",
        "docs/UE_GNB_AIR_INTERFACE_OUTPUT_SPEC.md",
        "reports/60_reports_complete_output_matrix.csv",
        "reports/61_analytics_complete_output_matrix.csv",
        "reports/62_missing_outputs_gap_list.csv",
        "reports/63_power_energy_gap_list.csv",
        "reports/64_scheduler_mac_phy_gap_list.csv",
        "reports/65_ue_air_interface_gap_list.csv",
        "reports/66_added_routes_views_tables.csv",
        "reports/67_analytics_job_manifest.csv",
        "reports/68_contract_runtime_reconciliation.csv",
        "sql/lls_complete_output_contract_views.sql",
    ]
    for rel in required_files:
        assert (REPO_ROOT / rel).is_file(), f"missing deliverable {rel}"
    assert "drop table" not in (REPO_ROOT / "sql/lls_complete_output_contract_views.sql").read_text(encoding="utf-8").lower()
    assert "delete from" not in (REPO_ROOT / "sql/lls_complete_output_contract_views.sql").read_text(encoding="utf-8").lower()
    report_rows = _read_csv(REPO_ROOT / "reports/60_reports_complete_output_matrix.csv")
    analytics_rows = _read_csv(REPO_ROOT / "reports/61_analytics_complete_output_matrix.csv")
    gap_rows = _read_csv(REPO_ROOT / "reports/62_missing_outputs_gap_list.csv")
    power_gap_rows = _read_csv(REPO_ROOT / "reports/63_power_energy_gap_list.csv")
    scheduler_gap_rows = _read_csv(REPO_ROOT / "reports/64_scheduler_mac_phy_gap_list.csv")
    reconciliation_rows = _read_csv(REPO_ROOT / "reports/68_contract_runtime_reconciliation.csv")
    assert len(report_rows) >= len(contract.iter_table_specs("reports"))
    assert len(analytics_rows) >= len(contract.iter_table_specs("analytics"))
    assert gap_rows and all("unavailable_until" in row["default_status"] for row in gap_rows)
    assert scheduler_gap_rows and all("reference_smoke_runtime_status" in row for row in scheduler_gap_rows)
    assert any(row["canonical_gap_classification"] == "canonical_live_table_or_view_missing_but_runtime_evidence_present" for row in scheduler_gap_rows)
    power_gap_names = {row["name"] for row in power_gap_rows}
    assert "live_power_runtime_table" not in power_gap_names
    assert "live_rf_power_table" not in power_gap_names
    assert "live_bb_power_table" not in power_gap_names
    assert "live_energy_efficiency_table" not in power_gap_names
    assert "live_sleep_state_table" not in power_gap_names
    assert "power_analytics" not in power_gap_names
    assert "energy_efficiency_analytics" not in power_gap_names
    assert "runtime_power_analytics" not in power_gap_names
    assert "sleep_state_analytics" not in power_gap_names
    assert any(row["section_slug"] == "scheduler-mac-queue-qos-power-control-uci-flow" and row["reference_smoke_implemented_count"] != "0" for row in reconciliation_rows)
    assert any(row["route"] == "/reports/scheduler-mac-queue-qos-power-control-uci-flow" for row in _read_csv(REPO_ROOT / "reports/66_added_routes_views_tables.csv"))
    assert all(row["placeholder_allowed"] == "false" for row in _read_csv(REPO_ROOT / "reports/67_analytics_job_manifest.csv"))


def test_browser_uses_one_compact_shell_and_preserves_deep_links() -> None:
    expected_nav = [
        ("home", "Scenario", "/home"),
        ("scenario", "Configure", "/scenario"),
        ("run_control", "Run", "/run-control"),
        ("realtime", "Live", "/realtime"),
        ("plots", "Results & Evidence", "/plots"),
    ]
    assert dash.PRODUCT_NAV == expected_nav
    assert len({route for _, _, route in dash.PRODUCT_NAV}) == len(expected_nav)
    for page_id, _, route in dash.PRODUCT_NAV:
        assert dash.PRODUCT_PAGE_ROUTES[route] == page_id

    expected_result_routes = {
        "/plots": "plots",
        "/tables": "tables",
        "/analytics": "analytics",
        "/artifacts": "artifacts",
        "/compare": "compare",
        "/phy-grid": "phy_grid",
    }
    for route, page_id in expected_result_routes.items():
        assert dash.PRODUCT_PAGE_ROUTES[route] == page_id

    assert dash.PRODUCT_PAGE_ROUTES["/"] == "home"
    assert dash.PRODUCT_PAGE_ROUTES["/reports"] == "reports"
    assert dash.PRODUCT_PAGE_ROUTES["/reports/power-energy-thermal-compute-runtime"] == "reports"
    assert dash.PRODUCT_PAGE_ROUTES["/analytics/power-energy-efficiency-analytics"] == "analytics"
    for preserved in ("/home", "/l1-phy", "/previous-runs", "/parameters"):
        assert preserved in dash.PRODUCT_PAGE_ROUTES, f"old route removed: {preserved}"


if __name__ == "__main__":
    test_contract_sections_and_context()
    test_contract_covers_required_domains()
    test_generated_deliverables_exist_and_are_additive()
    test_browser_uses_one_compact_shell_and_preserves_deep_links()
