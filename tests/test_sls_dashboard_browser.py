"""Headless mode routing/rendering checks; all API values are test fixtures."""
import json
import sys
from pathlib import Path
from urllib.parse import urlparse

import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as dash
from sixgr_sls_dashboard import live_payload, run_row


def test_sls_live_and_result_mode_selectors(tmp_path, monkeypatch):
    playwright = pytest.importorskip("playwright.sync_api")
    scenario = "sls_network_calibrated.yaml"
    monkeypatch.setattr(dash, "list_scenarios", lambda: [scenario])
    (tmp_path / "meta").mkdir()
    (tmp_path / "meta/simulation_run.json").write_text(json.dumps({
        "Schema": "sixgr.simulation_run/v1", "ExecutionMode": "SLS", "Status": "completed",
        "ScenarioID": "browser_fixture", "RunTag": "fixture_not_study", "PrimaryStudyAccepted": False}))
    row = run_row(tmp_path, 9000000011)
    live = live_payload(row, [])
    pages = {"/realtime": dash.build_product_frontend_page("realtime", scenario).decode(),
             "/plots": dash.build_product_frontend_page("plots", scenario).decode()}
    with playwright.sync_playwright() as p:
        if not Path(p.chromium.executable_path).is_file():
            pytest.skip("Playwright Chromium not installed")
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        errors = []
        page.on("pageerror", lambda exc: errors.append(str(exc)))

        def route(request):
            path = urlparse(request.request.url).path
            if path in pages:
                request.fulfill(content_type="text/html", body=pages[path])
            elif path == "/api/runs":
                request.fulfill(json={"runs": [row]})
            elif path.endswith("/live"):
                request.fulfill(json=live)
            elif path.endswith("/plots-browser"):
                request.fulfill(json={"items": [], "raw_items": [], "buckets": [], "total_count": 0})
            else:
                request.fulfill(json={})

        page.route("**/*", route)
        page.goto("http://sixgr.test/realtime?run_id=9000000011")
        page.get_by_role("heading", name="SLS network execution", exact=True).wait_for(timeout=15000)
        assert page.locator('[data-result-mode="true"] option').all_text_contents() == ["All modes", "LLS", "SLS"]
        assert page.get_by_text("PrimaryStudyAccepted", exact=True).count() == 1
        page.goto("http://sixgr.test/plots?run_id=9000000011")
        page.locator('[data-result-mode="true"]').wait_for()
        page.locator('[data-result-mode="true"]').select_option("SLS")
        page.wait_for_url(lambda url: "result_mode=SLS" in url, wait_until="commit")
        page.locator('[data-result-mode="true"]').wait_for()
        assert page.locator('[data-result-mode="true"]').input_value() == "SLS"
        assert not errors, errors
        browser.close()
