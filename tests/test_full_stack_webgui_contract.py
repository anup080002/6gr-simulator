from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402

SCENARIO = Path(dash.FULL_STACK_QUALIFICATION_SCENARIO).stem


def test_full_stack_scenario_is_a_canonical_webgui_mode() -> None:
    scenario = dash.FULL_STACK_QUALIFICATION_SCENARIO
    assert scenario in dash.OPERATOR_MASTER_SCENARIOS
    assert scenario in dash.list_scenarios()
    mode = next(
        item
        for item in dash.PRODUCT_SCENARIO_MODES
        if item["id"] == "full_stack_qualification"
    )
    assert mode["scenario"] == scenario
    assert dash.DEFAULT_DASHBOARD_PORT == 62906


def test_full_stack_scenario_resolves_and_is_launchable() -> None:
    payload, chain = dash.load_resolved_config_payload(
        dash.FULL_STACK_QUALIFICATION_SCENARIO
    )
    assert chain
    assert (
        dash.path_get(payload, "scenario.runner_profile", "")
        == "full_stack_qualification"
    )
    assert (
        dash.path_get(payload, "qualification.suite.preset", "")
        == "comprehensive_smoke"
    )
    assert dash.path_get(
        payload, "qualification.main_fixed_sinr_sweep.snr_db", []
    ) == [-8, -4, 0, 4, 10]
    contract = dash.scenario_launch_contract(
        payload, dash.FULL_STACK_QUALIFICATION_SCENARIO
    )
    assert contract["launch_allowed"] is True


def test_full_stack_page_contract_is_rendered_in_single_webgui() -> None:
    rows = dash.load_full_stack_webgui_page_contract()
    assert len(rows) == 13
    assert sum(bool(row["mandatory"]) for row in rows) == 12
    page = dash.build_product_frontend_page(
        "qualification",
        dash.FULL_STACK_QUALIFICATION_SCENARIO,
        user_profile=None,
    ).decode("utf-8")
    assert 'window.SIXGR_PRODUCT_DATA' in page
    assert '"page": "qualification"' in page
    assert "SourceYAMLSHA256" in page
    assert "ResolvedYAMLSHA256" in page
    assert "ExecutedYAMLSHA256" in page
    for row in rows:
        assert row["page"] in page


def test_bounded_command_reports_success_and_timeout(tmp_path: Path) -> None:
    helper = REPO_ROOT / "tools" / "run_bounded_command.py"
    success_log = tmp_path / "success.log"
    success = subprocess.run(
        [
            sys.executable,
            str(helper),
            "--timeout-seconds",
            "5",
            "--log",
            str(success_log),
            "--",
            sys.executable,
            "-c",
            "print('bounded-ok')",
        ],
        check=False,
    )
    assert success.returncode == 0
    assert "bounded-ok" in success_log.read_text(encoding="utf-8")

    timeout_log = tmp_path / "timeout.log"
    started = time.monotonic()
    timeout = subprocess.run(
        [
            sys.executable,
            str(helper),
            "--timeout-seconds",
            "0.1",
            "--log",
            str(timeout_log),
            "--",
            sys.executable,
            "-c",
            "import time; time.sleep(30)",
        ],
        check=False,
    )
    assert timeout.returncode == 124
    assert time.monotonic() - started < 10
    assert "FULLSTACK:RegressionTimeout" in timeout_log.read_text(
        encoding="utf-8"
    )


def test_incomplete_full_stack_run_remains_filesystem_indexable(
    tmp_path: Path,
) -> None:
    run_folder = tmp_path / "results" / "lls" / SCENARIO / "bounded-stop"
    csv_dir = run_folder / "reports" / "csv"
    csv_dir.mkdir(parents=True)
    (csv_dir / "full_stack_run_manifest.csv").write_text(
        "RunID,SuitePreset,ScenarioID,StartUTC,ExitCode,FinalStatus,Status\n"
        "bounded-stop,comprehensive_smoke,"
        f"{SCENARIO},2026-07-28T00:00:00Z,2,FAIL,FAIL\n",
        encoding="utf-8",
    )
    row = dash.filesystem_run_row_from_folder(run_folder)
    assert row is not None
    assert row["run_tag"] == "bounded-stop"
    assert row["scenario_id"] == SCENARIO
    assert row["status_text"] == "failed"
    assert row["profile_name"] == "full_stack_qualification"
