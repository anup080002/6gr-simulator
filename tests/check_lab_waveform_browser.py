"""Browser acceptance against a completed real campaign, never mock KPIs."""
import argparse
import hashlib
import json
from pathlib import Path
from playwright.sync_api import sync_playwright


def check(root):
    root=Path(root).resolve(); folder=root/"webgui"
    data=json.loads((folder/"replay_data.json").read_text(encoding="utf-8"))
    assert data["meta"]["Status"]=="phy_completed"
    errors=[]; remote=[]
    with sync_playwright() as pw:
        browser=pw.chromium.launch(headless=True)
        page=browser.new_page(viewport={"width":1920,"height":1080},device_scale_factor=1)
        page.on("pageerror",lambda e:errors.append(str(e)))
        page.on("request",lambda r:remote.append(r.url) if r.url.startswith(("https:","http:")) else None)
        page.goto((folder/"index.html").as_uri()); page.wait_for_timeout(500)
        assert page.locator("#snr").input_value()==str(data["config"]["lab_waveform"]["rx_snr_db"][-1])
        assert "Peak PSD" in page.inner_text("#psdsummary")
        assert "Integrated power" in page.inner_text("#psdsummary")
        for profile in data["profiles"]:
            page.locator("#profile").select_option(profile)
            for direction in ("DL","UL"):
                page.locator("#"+direction.lower()).click()
                for snr,case in data["profiles"][profile][direction]["cases"].items():
                    page.locator("#snr").select_option(snr)
                    assert f"{case['summary']['EVMRMSPercent']:.3f}%" in page.inner_text("#kpis")
                    assert f"{case['summary']['TBSBits']:,}" in page.inner_text("#payload")
                for layer in ("0","1"):
                    page.locator("#layer").select_option(layer)
                    assert f"Layer {int(layer)+1}" in page.inner_text("#pointcount")
        page.locator("#physical").click()
        if data["physical"] is None:
            assert "Awaiting instrument capture" in page.inner_text("#rfbody")
        page.locator("#closerf").click()
        page.locator("#engineering").click()
        assert "common-scale playback" in page.inner_text("#engbody")
        page.locator("#closeeng").click()
        page.locator("#profile").select_option(next(iter(data["profiles"])))
        page.locator("#dl").click(); page.locator("#snr").select_option(str(data["config"]["lab_waveform"]["rx_snr_db"][-1]))
        page.locator("#layer").select_option("0"); page.locator("#reset").click()
        for width,height in ((1920,1080),(2560,1440),(3840,2160)):
            page.set_viewport_size({"width":width,"height":height}); page.wait_for_timeout(100)
            assert page.evaluate("document.documentElement.scrollWidth <= innerWidth && document.documentElement.scrollHeight <= innerHeight"),"Page overflows"
            assert page.evaluate("[...document.querySelectorAll('.panel')].every(e => e.scrollHeight <= e.clientHeight+2)"),"Panel content is clipped"
            if width==1920: page.screenshot(path=str(folder/"demo_dashboard_1920x1080.png"))
        page.set_viewport_size({"width":1920,"height":1080})
        page.locator("#fullscreen").click(); page.wait_for_timeout(150)
        assert page.evaluate("!!document.fullscreenElement"),"Fullscreen did not activate"
        page.locator("#fullscreen").click()
        page.locator("#play").click(); page.wait_for_timeout(1000); page.locator("#play").click()
        assert "Slot 0 ·" not in page.inner_text("#clock"),"Recorded clock did not advance"
        page.locator("#next").click(); assert "2/16" in page.inner_text("#story")
        page.locator("#prev").click(); page.locator("#reset").click()
        assert not errors,errors; assert not remote,remote
        browser.close()
    receipt={"Passed":True,"Viewports":[[1920,1080],[2560,1440],[3840,2160]],"Offline":True,
             "ProfilesAndSNRsChecked":True,"FullscreenChecked":True,"ReplayChecked":True,
             "SourceRun":data["meta"]["RunTag"],"JavaScriptErrors":errors}
    receipt["CheckedFiles"]={name:hashlib.sha256((folder/name).read_bytes()).hexdigest()
                             for name in ("index.html","replay_data.json","demo_dashboard_1920x1080.png")}
    (root/"validation/browser_receipt.json").write_text(json.dumps(receipt,indent=2),encoding="utf-8")
    print("LAB_BROWSER_PASS: actual KPI values, all profiles/SNRs/layers, 1080p/1440p/4K, fullscreen, replay, no network")


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__); p.add_argument("run_folder",type=Path)
    check(p.parse_args().run_folder)
