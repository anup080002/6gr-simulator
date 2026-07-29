from __future__ import annotations

import csv
import hashlib
import os
import time
from pathlib import Path
from urllib.parse import urljoin

from playwright.sync_api import Page, sync_playwright


REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_ROOT = (
    REPO_ROOT / "audit" / "6gr_webgui_full_stack_qualification_pack"
)
SCENARIO = "lls_webgui_full_stack_sinr_geometry_qualification"


def _login_if_required(page: Page, base_url: str) -> None:
    page.goto(urljoin(base_url, "/qualification"), wait_until="domcontentloaded")
    if "/login" not in page.url:
        return
    username = os.environ.get("SIXGR_WEBGUI_TEST_USERNAME", "")
    password = os.environ.get("SIXGR_WEBGUI_TEST_PASSWORD", "")
    assert username and password, (
        "The secured WebGUI requested login, but the Playwright operator "
        "credentials were not configured."
    )
    page.locator("#username").fill(username)
    page.locator("#password").fill(password)
    page.get_by_role("button", name="Sign in").click()
    page.wait_for_url(lambda url: "/login" not in url)


def _selected_registry() -> list[dict[str, str]]:
    with (
        PACK_ROOT / "full_stack_required_artifact_registry.csv"
    ).open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    return [
        row
        for row in rows
        if str(row["RequiredInComprehensiveSmoke"]).lower() == "true"
    ]


def _page_contract() -> list[dict[str, str]]:
    with (
        PACK_ROOT / "full_stack_webgui_page_contract.csv"
    ).open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def test_full_stack_webgui_actual_run_workflow() -> None:
    base_url = os.environ.get(
        "SIXGR_WEBGUI_BASE_URL", "http://127.0.0.1:62906"
    ).rstrip("/")
    run_tag = os.environ.get("SIXGR_WEBGUI_RUN_TAG", "")
    launch_run = os.environ.get(
        "SIXGR_FULL_STACK_E2E_ALLOW_LAUNCH", ""
    ).strip().lower() in {"1", "true", "yes"}
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        context = browser.new_context(accept_downloads=True)
        page = context.new_page()
        _login_if_required(page, base_url)

        run_control = (
            f"{base_url}/run-control?scenario="
            "lls_webgui_full_stack_sinr_geometry_qualification.yaml"
        )
        page.goto(run_control, wait_until="networkidle")
        page.get_by_text("Full-Stack Qualification", exact=True).first.wait_for()
        assert page.locator("#runScenarioInput").get_attribute("value").endswith(
            "lls_webgui_full_stack_sinr_geometry_qualification.yaml"
        )
        if launch_run:
            assert run_tag, (
                "A unique SIXGR_WEBGUI_RUN_TAG is required for the "
                "external Playwright launch."
            )
            page.locator("#runTagInput").evaluate(
                "(element, value) => { element.value = value; }", run_tag
            )
            page.locator("#runScenarioBtn").wait_for(state="visible")
            page.wait_for_function(
                "() => !document.querySelector('#runScenarioBtn').disabled"
            )
            page.locator("#runScenarioBtn").click()
            page.wait_for_load_state("domcontentloaded")

        candidates: list[dict[str, object]] = []
        deadline = time.monotonic() + (7200 if launch_run else 60)
        while time.monotonic() < deadline:
            runs_response = context.request.get(
                f"{base_url}/api/runs?limit=5000"
            )
            assert runs_response.ok
            runs = runs_response.json().get("runs", [])
            candidates = [
                run
                for run in runs
                if (
                    (run_tag and str(run.get("run_tag") or "") == run_tag)
                    or (
                        not run_tag
                        and SCENARIO in str(run.get("scenario_id") or "")
                    )
                )
            ]
            if candidates:
                break
            time.sleep(2)
        assert candidates, "The WebGUI-launched Phase-18 run is not indexed."
        current = candidates[0]
        run_id = str(current["run_id"])
        if launch_run:
            terminal = {
                "completed",
                "completed_with_failures",
                "failed",
                "aborted",
                "stopped",
            }
            while time.monotonic() < deadline:
                run_response = context.request.get(
                    f"{base_url}/api/run/{run_id}"
                )
                assert run_response.ok
                current = run_response.json()
                status = str(
                    current.get("status_text")
                    or current.get("status")
                    or ""
                ).strip().lower()
                if status in terminal or any(
                    status.startswith(prefix)
                    for prefix in ("failed", "aborted", "completed")
                ):
                    break
                time.sleep(5)
            else:
                raise AssertionError(
                    f"WebGUI run {run_id} did not finish within two hours."
                )

        live_response = context.request.get(
            f"{base_url}/api/run/{run_id}/live"
        )
        assert live_response.ok
        live = live_response.json()
        qualification = live.get("full_stack_qualification") or {}
        subcases = qualification.get("subcases") or []
        observed_subcases = {
            str(row.get("SubcaseID")) for row in subcases
        }
        assert observed_subcases == {
            f"SC-{index:02d}" for index in range(31)
        }, "The Live payload did not expose all 31 mandatory subcases."
        binding = (qualification.get("config_binding") or [{}])[0]
        assert binding.get("ResolvedYAMLSHA256")
        assert (
            binding.get("ResolvedYAMLSHA256")
            == binding.get("ExecutedYAMLSHA256")
        )

        page.goto(
            f"{base_url}/qualification?run_id={run_id}&section=Configure",
            wait_until="networkidle",
        )
        page.get_by_text("ResolvedYAMLSHA256", exact=True).wait_for()
        page.locator(
            "tr", has_text="ResolvedYAMLSHA256"
        ).get_by_text(
            str(binding["ResolvedYAMLSHA256"]), exact=True
        ).wait_for()

        for row in _page_contract():
            if str(row.get("Mandatory") or "").lower() != "true":
                continue
            section = str(row["Page"])
            page.goto(
                f"{base_url}/qualification?run_id={run_id}"
                f"&section={section.replace(' ', '%20')}",
                wait_until="networkidle",
            )
            page.locator("section.panel h3", has_text=section).last.wait_for()

        artifacts = live.get("artifacts_all") or []
        by_name = {
            Path(str(item.get("logical_path") or "")).name: item
            for item in artifacts
        }
        selected = _selected_registry()
        required_names = {row["FileName"] for row in selected}
        missing = sorted(required_names - set(by_name))
        assert not missing, (
            f"{len(missing)} selected-preset artifacts are not indexed: "
            + ", ".join(missing[:25])
        )

        # Download one CSV and one PNG per domain. Repeated byte hashes prove
        # the WebGUI download is stable for the selected immutable RunID.
        representatives: list[dict[str, str]] = []
        for domain in sorted({row["Domain"] for row in selected}):
            domain_rows = [row for row in selected if row["Domain"] == domain]
            for kind in ("CSV", "PNG"):
                match = next(
                    (
                        row
                        for row in domain_rows
                        if row["ArtifactType"] == kind
                    ),
                    None,
                )
                if match:
                    representatives.append(match)
        for row in representatives:
            descriptor = by_name[row["FileName"]]
            url = urljoin(base_url, str(descriptor["download_url"]))
            first = context.request.get(url)
            second = context.request.get(url)
            assert first.ok and second.ok
            assert first.body()
            assert hashlib.sha256(first.body()).hexdigest() == hashlib.sha256(
                second.body()
            ).hexdigest()

        acceptance = qualification.get("acceptance") or []
        assert acceptance, "Acceptance rows are not visible in WebGUI data."
        failed_ids = {
            str(row.get("RuleID"))
            for row in acceptance
            if str(row.get("Status") or "").upper() != "PASS"
        }
        if failed_ids:
            assert any(
                str(row.get("Status") or "").upper() != "PASS"
                for row in acceptance
            ), "Failed acceptance rows were hidden."

        run_folder = Path(str((live.get("run") or {}).get("run_folder") or ""))
        assert run_folder.is_dir()
        screenshot_dir = (
            run_folder / "qualification_evidence" / "webgui_screenshots"
        )
        screenshot_dir.mkdir(parents=True, exist_ok=True)
        page.screenshot(
            path=str(screenshot_dir / "full_stack_qualification.png"),
            full_page=True,
        )
        browser.close()
