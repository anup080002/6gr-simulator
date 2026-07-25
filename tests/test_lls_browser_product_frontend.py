from __future__ import annotations

import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


SCENARIO = "variants/SCN00_BASELINE_CAPACITY.yaml"
USER_PROFILE = {
    "username": "admin",
    "display_name": "Admin",
    "role": "Administrator",
}


def _product_data(page: str) -> dict:
    marker = "<script>window.SIXGR_PRODUCT_DATA = "
    start = page.index(marker) + len(marker)
    end = page.index(";</script>", start)
    return json.loads(page[start:end])


def main() -> None:
    original_scenarios = dash.list_scenarios
    try:
        dash.list_scenarios = lambda: [SCENARIO]

        page_ids = (
            "home",
            "scenario",
            "run_control",
            "runs",
            "realtime",
            "phy_grid",
            "plots",
            "tables",
            "reports",
            "analytics",
            "artifacts",
            "parameters",
            "compare",
        )
        pages = {
            page_id: dash.build_product_frontend_page(
                page_id,
                SCENARIO,
                user_profile=USER_PROFILE,
            ).decode("utf-8")
            for page_id in page_ids
        }
        data = {page_id: _product_data(page) for page_id, page in pages.items()}

        expected_nav = [
            ("home", "Scenario", "/home"),
            ("scenario", "Configure", "/scenario"),
            ("run_control", "Run", "/run-control"),
            ("runs", "Runs", "/runs"),
            ("realtime", "Live", "/realtime"),
            ("plots", "Results & Evidence", "/plots"),
        ]
        assert dash.PRODUCT_NAV == expected_nav
        expected_nav_payload = [
            {"id": page_id, "label": label, "href": href}
            for page_id, label, href in expected_nav
        ]

        clutter = (
            "Open Access",
            "Intranet Viewer",
            "No login required",
            "Mode-first console for browser-owned LLS execution",
            "6G LLS Real-Time Console",
            "Direct MySQL-backed monitoring",
        )
        for page_id, page in pages.items():
            assert page.lower().count("<!doctype html>") == 1, f"{page_id} must have one document"
            assert page.count('<div class="app-shell" data-product-shell>') == 1, (
                f"{page_id} must render one product shell"
            )
            assert page.count('<aside class="sidebar"') == 1, f"{page_id} must have one sidebar"
            assert page.count('<main id="productMain"></main>') == 1, (
                f"{page_id} must have one content host"
            )
            assert "<iframe" not in page.lower(), (
                f"{page_id} must not embed another WebGUI/page; render content natively"
            )
            assert ">OA<" not in page
            for phrase in clutter:
                assert phrase not in page, f"{page_id} still exposes legacy clutter: {phrase}"
            assert data[page_id]["nav"] == expected_nav_payload
            assert data[page_id]["modes"] == ["LLS"], (
                f"{page_id} must expose only LLS in the browser launch UI"
            )

        home_page = pages["home"]
        home_data = data["home"]
        assert home_data["title"] == "6G Link-Level Simulator"
        assert home_data["initial_mode"] == "LLS"
        assert home_data["fully_wired_mode"] == "LLS"
        assert home_data["config_loaded"] is False
        assert home_data["execution_policy"] == {
            "id": dash.WEBGUI_EXECUTION_POLICY,
            "workers": 1,
            "parallel_pool": False,
        }
        assert home_data["report_sections"] == []
        assert home_data["analytics_sections"] == []
        assert "window.SIXGR_PRODUCT_DATA" in home_page
        assert "config_api_url" in home_data
        assert "fields_api_url" in home_data
        assert "parameter_constraints_api_url" in home_data
        assert "Upload YAML" in home_page
        assert "Download resolved config" in home_page
        assert "Configure" in home_page
        assert "View results" in home_page
        assert "configPreview" not in home_page, (
            "the compact product must not expose the legacy raw-config preview"
        )
        assert "Backend Status" not in home_page, (
            "the compact product must not render the legacy backend-status widget"
        )

        scenario_page = pages["scenario"]
        for control in (
            'id="loadConfigJsonBtn"',
            'id="saveScenarioBtn"',
            'id="downloadConfigBtn"',
            'id="configSearch"',
        ):
            assert control in scenario_page
        for label in ("Import JSON", "Save draft", "Export JSON", "General", "PHY", "Advanced"):
            assert label in scenario_page
        assert '<details class="config-group">' in scenario_page
        assert '<details class="config-group" open>' not in scenario_page, (
            "configuration groups should start collapsed to keep the page compact"
        )

        run_page = pages["run_control"]
        assert 'id="validateBtn"' in run_page
        assert 'id="runScenarioBtn"' in run_page
        assert 'id="runModeInput"' in run_page
        assert 'name="execution_mode" value="LLS"' in run_page
        assert 'data-scenario-mode="${esc(item.id)}"' in run_page
        assert "SINR Sweep" in json.dumps(data["run_control"]["scenario_modes"])
        assert "Geometry Based" in json.dumps(data["run_control"]["scenario_modes"])
        assert 'class="upload-dropzone"' in run_page
        assert 'id="runTagEditor"' in run_page
        assert "View all runs" in run_page
        assert '<option value="SLS"' not in run_page
        assert '<option value="E2E"' not in run_page
        assert 'data-mode="SLS"' not in run_page
        assert 'data-mode="E2E"' not in run_page
        assert "License-safe" in run_page
        assert "parallel pool off" in run_page
        assert dash.FULLY_WIRED_BROWSER_EXECUTION_MODE == "LLS"

        runs_page = pages["runs"]
        assert "Run history" in runs_page
        assert 'id="selectAllRuns"' in runs_page
        assert 'id="deleteSelectedRunsBtn"' in runs_page
        assert 'action="/admin/delete-runs"' in runs_page
        assert 'data-run-checkbox' in runs_page
        assert "every associated database row, log, artifact, runtime YAML, and output file" in runs_page

        realtime_page = pages["realtime"]
        assert "Run status and current measurements." in realtime_page
        assert "Resource Grid" in realtime_page
        assert "/api/run/${id}/live" in realtime_page
        assert "captureScrollState" in realtime_page
        assert "restoreScrollState" in realtime_page
        assert "function eventElement(target)" in realtime_page
        assert "payload_version" in realtime_page

        phy_grid_page = pages["phy_grid"]
        assert "Symbols / slot" in phy_grid_page
        assert "without inventing resource assignments" in phy_grid_page
        assert "/phy-grid" in phy_grid_page

        plots_page = pages["plots"]
        assert 'id="plotBrowserCatalogSelect"' in plots_page
        assert 'id="plotBrowserBucketSelect"' in plots_page
        assert 'id="plotBrowserSelect"' in plots_page
        assert 'id="plotBrowserViewer"' in plots_page
        assert "Zoom In" in plots_page
        assert "Fit" in plots_page

        tables_page = pages["tables"]
        assert 'id="tableBrowserBucketSelect"' in tables_page
        assert 'id="tableBrowserSelect"' in tables_page
        assert 'id="tableBrowserViewer"' in tables_page
        assert "Download CSV" in tables_page
        assert "loadTableBrowserPreview" in tables_page
        assert "data-table-preview-scroll" in tables_page
        assert "Load more rows" in tables_page
        assert "<iframe" not in tables_page.lower()

        for label in (
            "Images & Graphs",
            "Tables",
            "Runtime Report",
            "Analytics",
            "Files",
            "Compare",
        ):
            assert label in plots_page, f"missing compact result tab: {label}"

        assert data["reports"]["report_sections"], "runtime report contract must be loaded on demand"
        assert data["analytics"]["analytics_sections"], "analytics contract must be loaded on demand"
        assert 'data-run-selector="true"' in pages["reports"]
        assert 'data-run-selector="true"' in pages["analytics"]
        assert 'data-run-selector="true"' in pages["artifacts"]
        assert 'data-run-selector="true"' in pages["parameters"]

        for header in (
            "parameter name",
            "current value",
            "requested value",
            "resolved value",
            "applied value",
            "measured/runtime value",
            "source",
            "owner",
            "role",
        ):
            assert header in pages["parameters"], (
                f"advanced parameter table must expose {header}"
            )

        phy_names = {
            block["name"]
            for family in dash.product_phy_families()
            for block in family["blocks"]
        }
        for required in (
            "PDCCH",
            "SSB / PBCH",
            "CSI-RS",
            "PDSCH",
            "PUSCH",
            "PUCCH Format 0",
            "PUCCH Format 1",
            "PUCCH Formats 2/3/4",
            "PRACH",
            "SRS",
            "TRS",
            "Beamforming / Precoding / MIMO",
            "DL Chain",
            "UL Chain",
        ):
            assert required in phy_names, f"missing LLS PHY block: {required}"

        route_expectations = {
            "/": "home",
            "/home": "home",
            "/scenario": "scenario",
            "/run-control": "run_control",
            "/runs": "runs",
            "/realtime": "realtime",
            "/result": "realtime",
            "/phy-grid": "phy_grid",
            "/plots": "plots",
            "/results": "plots",
            "/tables": "tables",
            "/reports": "reports",
            "/analytics": "analytics",
            "/artifacts": "artifacts",
            "/outputs": "artifacts",
            "/images": "artifacts",
            "/parameter-catalog": "parameters",
            "/compare-runs": "compare",
        }
        for route, page_id in route_expectations.items():
            assert dash.PRODUCT_PAGE_ROUTES.get(route) == page_id, (
                f"{route} must resolve inside the single product WebGUI"
            )
    finally:
        dash.list_scenarios = original_scenarios


if __name__ == "__main__":
    main()
