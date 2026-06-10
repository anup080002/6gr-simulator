from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    orig_backend = dash.product_backend_status
    orig_scenarios = dash.list_scenarios
    orig_load = dash.load_resolved_config_payload
    try:
        dash.product_backend_status = lambda: {
            "matlab_exe": str(dash.MATLAB_EXE),
            "matlab_r2023b_only": True,
            "matlab_available": True,
            "mysql_host": "localhost",
            "mysql_port": 3306,
            "mysql_database": "sixgr_results",
            "mysql_status": "connected",
            "mysql_reason": "",
            "latest_run_id": 42,
        }
        dash.list_scenarios = lambda: ["variants/SCN00_BASELINE_CAPACITY.yaml"]
        dash.load_resolved_config_payload = lambda scenario: (
            {
                "scenario": {"name": "frontend_smoke"},
                "run_control": {"execution_mode": "LLS", "n_frames": 1},
                "frequency": {"center_frequency_hz": 700000000, "bandwidth_hz": 20000000},
                "deployment_topology": {"layout_type": "hexagonal_wraparound", "inter_site_distance": 500},
                "traffic": {"model": "full_buffer"},
                "system": {"scheduler": {"type": "PF"}},
                "pdcch": {"enabled": True},
                "pucch": {"enabled": True},
                "prach": {"enabled": True},
                "reference_signals": {"srs": {"enabled": True}, "trs": {"enabled": True}},
                "mimo": {"n_layers": 2, "precoder_type": "codebook"},
                "channels": {"profile": "TDL-C"},
            },
            ["variants/SCN00_BASELINE_CAPACITY.yaml"],
        )

        page = dash.build_product_frontend_page(
            "home",
            "variants/SCN00_BASELINE_CAPACITY.yaml",
            user_profile={"username": "admin", "display_name": "Admin", "role": "Administrator"},
        ).decode("utf-8")
        realtime_page = dash.build_product_frontend_page(
            "realtime",
            "variants/SCN00_BASELINE_CAPACITY.yaml",
            user_profile={"username": "admin", "display_name": "Admin", "role": "Administrator"},
        ).decode("utf-8")
        analytics_page = dash.build_product_frontend_page(
            "analytics",
            "variants/SCN00_BASELINE_CAPACITY.yaml",
            user_profile={"username": "admin", "display_name": "Admin", "role": "Administrator"},
        ).decode("utf-8")
        reports_page = dash.build_product_frontend_page(
            "reports",
            "variants/SCN00_BASELINE_CAPACITY.yaml",
            user_profile={"username": "admin", "display_name": "Admin", "role": "Administrator"},
        ).decode("utf-8")
        artifacts_page = dash.build_product_frontend_page(
            "artifacts",
            "variants/SCN00_BASELINE_CAPACITY.yaml",
            user_profile={"username": "admin", "display_name": "Admin", "role": "Administrator"},
        ).decode("utf-8")
        parameters_page = dash.build_product_frontend_page(
            "parameters",
            "variants/SCN00_BASELINE_CAPACITY.yaml",
            user_profile={"username": "admin", "display_name": "Admin", "role": "Administrator"},
        ).decode("utf-8")

        assert "Jio Platforms Limited RAN Simulator" in page
        assert "LLS" in page and "SLS" in page and "E2E" in page
        assert "Load Config JSON" in page
        assert "Download Config JSON" in page
        assert "Recent Runs" in page
        assert "Previous Runs" in page
        assert "Reports" in page
        assert "Runtime truth lives under" not in page
        assert "Show Output" in page
        assert "View Tables" in page
        assert "Add Baseline" in page
        assert "Add Candidate" in page
        assert "Delete Run" in page
        assert "Download Full File" in page
        assert "window.SIXGR_PRODUCT_DATA" in page
        assert "config_api_url" in page
        assert "config_overview" in page
        assert "fields_api_url" in page
        assert "parameter_constraints_api_url" in page
        assert "parameter_constraints_summary" in page
        assert "field_count" in page
        assert '"report_sections": []' in page
        assert '"analytics_sections": []' in page
        assert "configPreview" not in page, "front page must not expose the old raw config preview"
        assert "Backend Status" not in page, "visible backend status widget should not be rendered in the product shell"
        assert "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" in page
        assert "/api/run/${id}/live" in page or "/api/run/${state.live.run.run_id}/live" in page
        assert "captureScrollState" in page
        assert "restoreScrollState" in page
        assert "function eventElement(target)" in page
        assert "ensureFieldsLoaded" in page
        assert "pageNeedsFieldCatalog" in page
        assert "refreshRunsList" in page
        assert "function runStatusRank(run, preferActive)" in page
        assert "state.liveVersion" in page
        assert "payload_version" in page
        assert '"config_loaded": false' in page
        assert "const target = eventElement(e.target);" in page
        assert "e.target.matches('[data-run-selector=\"true\"]')" not in page
        assert "selected_run_section_evidence_present" in analytics_page
        assert "published in selected run" in analytics_page
        assert 'data-scroll-key="sidebar-scroll"' in page
        assert "Live UE Metric Explorer" in realtime_page
        assert "liveMetricSelect" in realtime_page
        assert "liveUESelect" in realtime_page
        assert "liveUEScopeSelect" in realtime_page
        assert "liveSecondaryMetricSelect" in realtime_page
        assert "liveOverlaySelect" in realtime_page
        assert "liveMetricExportBtn" in realtime_page
        assert "realtimeRunSelect" in realtime_page
        assert "All configured UEs" in realtime_page
        assert "Selected UE" in realtime_page
        assert "Per-cell overlay" in realtime_page
        assert "Analytics Explorer" in analytics_page
        assert "analyticsMetricSelect" in analytics_page
        assert "analyticsSecondaryMetricSelect" in analytics_page
        assert "analyticsOverlaySelect" in analytics_page
        assert "analyticsMetricExportBtn" in analytics_page
        assert "Waveform / Heatmap / Constellation Artifacts" in analytics_page
        assert "Published Analytics Charts" in analytics_page
        assert "Control Signal Runtime Evidence" in realtime_page
        assert "Selected Run" in realtime_page
        assert 'data-run-selector="true"' in analytics_page
        assert 'data-run-selector="true"' in reports_page
        assert 'data-run-selector="true"' in artifacts_page
        assert 'data-run-selector="true"' in parameters_page
        assert len(realtime_page) < len(analytics_page), "realtime page should not inline heavy report/analytics contract payloads"
        assert len(page) < len(analytics_page), "home page should stay lighter than analytics-heavy pages"
        for block in (
            "Scenario",
            "Geometry",
            "Waveform",
            "Traffic",
            "MAC / Scheduler",
            "Control / Access",
            "L1 / PHY",
            "Antenna / Air Interface / Channel",
            "Real-time Data",
            "Analytics",
        ):
            assert block in page, f"missing architecture block: {block}"
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
            assert header in page, f"block parameter panel must expose {header}"

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
            assert required in phy_names, f"missing L1/PHY block: {required}"

        route_expectations = {
            "/": "home",
            "/home": "home",
            "/run-control": "run_control",
            "/reports": "reports",
            "/reports/scheduler-mac-queue-qos-power-control-uci-flow": "reports",
            "/documentation": "architecture",
            "/scenario": "scenario",
            "/geometry": "geometry",
            "/waveform": "waveform",
            "/traffic": "traffic",
            "/mac-scheduler": "mac_scheduler",
            "/l1-phy": "l1_phy",
            "/antenna-air": "antenna_air",
            "/realtime": "realtime",
            "/analytics": "analytics",
            "/artifacts": "artifacts",
            "/parameter-catalog": "parameters",
            "/compare-runs": "compare",
            "/runs": "runs",
            "/recent-runs": "runs",
            "/previous-run": "previous_runs",
            "/previous-runs": "previous_runs",
            "/result": "realtime",
            "/outputs": "artifacts",
            "/map": "geometry",
            "/logs": "realtime",
            "/tables": "tables",
            "/images": "artifacts",
        }
        for route, page_id in route_expectations.items():
            assert dash.PRODUCT_PAGE_ROUTES.get(route) == page_id, f"{route} must route to the new product page"

        nav_ids = [item[0] for item in dash.PRODUCT_NAV]
        for required in (
            "home",
            "run_control",
            "scenario",
            "geometry",
            "waveform",
            "traffic",
            "mac_scheduler",
            "l1_phy",
            "antenna_air",
            "realtime",
            "reports",
            "analytics",
            "runs",
            "previous_runs",
            "artifacts",
            "parameters",
            "compare",
        ):
            assert required in nav_ids, f"missing product nav item: {required}"
        assert nav_ids.index("reports") < nav_ids.index("analytics")
        assert dash.BROWSER_EXECUTION_MODE_OPTIONS == ["LLS", "SLS", "E2E"]
        assert dash.FULLY_WIRED_BROWSER_EXECUTION_MODE == "LLS"
    finally:
        dash.product_backend_status = orig_backend
        dash.list_scenarios = orig_scenarios
        dash.load_resolved_config_payload = orig_load


if __name__ == "__main__":
    main()
