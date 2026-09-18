"""Optional headless UI check against a real generated exhibit (requires Playwright)."""
import argparse
import json
from pathlib import Path
from playwright.sync_api import sync_playwright


def check(folder):
    folder = Path(folder).resolve()
    data = json.loads((folder / "replay_data.json").read_text(encoding="utf-8"))
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1920, "height": 1080})
        errors, network = [], []
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.on("request", lambda r: network.append(r.url) if r.url.startswith(("http:", "https:")) else None)
        page.goto((folder / "index.html").as_uri())
        assert "NOT LIVE RF" in page.inner_text(".badge")
        for direction in ("DL", "UL"):
            assert f"{data['summary'][direction]['gbps']:.3f}" in page.inner_text("#headlines")
        for e in [e for e in data["events"] if not e["crc"] or e["retx"]]:
            page.locator("#seek").fill(str(e["slot"]))
            page.locator("#seek").dispatch_event("input")
            assert ("CRC PASS" if e["crc"] else "CRC FAIL") in page.inner_text("#current" + e["direction"])
            if e["retx"]:
                assert "retransmission" in page.inner_text("#current" + e["direction"])
        page.locator("#reset").click()
        page.locator("#speed").select_option("2")
        page.locator("#play").click()
        page.wait_for_timeout(600)
        page.locator("#play").click()
        assert int(page.locator("#seek").input_value()) > 0
        page.locator("#seek").fill(str(len(data["timeline"]) - 1))
        page.locator("#seek").dispatch_event("input")
        assert f"{data['horizonMs']:.3f} / {data['horizonMs']:.3f}" in page.inner_text("#clock")
        assert page.evaluate("document.documentElement.scrollHeight <= innerHeight"), "Exhibit must fit a 1080p display"
        page.screenshot(path=str(folder / "dashboard.png"), full_page=True)
        page.set_viewport_size({"width": 390, "height": 844})
        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth + 1")
        assert not errors, errors
        assert not network, network
        browser.close()
    print("RECORDED_DEMO_BROWSER_PASS: values, HARQ replay, controls, end clock, mobile width, no network/errors")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    check(parser.parse_args().folder)
