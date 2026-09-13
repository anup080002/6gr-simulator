"""Launcher exit/log contracts only; fake executables are NOT PHY evidence."""
import json
import os
from pathlib import Path
import shutil
import subprocess

import pytest


pytestmark = pytest.mark.skipif(os.name != "nt", reason="Windows Terminal launcher")
SOURCE = Path(__file__).resolve().parents[1]


@pytest.fixture
def checkout(tmp_path):
    root = tmp_path / "checkout with spaces"
    (root / "scripts").mkdir(parents=True)
    shutil.copy2(SOURCE / "scripts/run_server_testall.ps1", root / "scripts")
    (root / ".gitignore").write_text("logs/\n")
    # Isolated process-control fixture. Only the third launcher argument is
    # the real logfile path; this fixture never invokes MATLAB or the PHY.
    (root / "fake_matlab.cmd").write_text(
        '@echo off\r\npowershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake.ps1" "%~3"\r\nexit /b %errorlevel%\r\n'
    )
    (root / "fake.ps1").write_text(
        "param([string]$LogPath)\n"
        "$dir=Split-Path -Parent $LogPath\n"
        "'FAKE LAUNCHER CONTRACT TEST, NOT MATLAB' | Set-Content -LiteralPath $LogPath\n"
        "if ($env:SIXGR_LAUNCHER_TEST_MODE -ne 'missing') {\n"
        "  @{status='passed'; scope='preflight_only'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'summary.json')\n"
        "}\n"
        "if ($env:SIXGR_LAUNCHER_TEST_MODE -eq 'nonzero') { exit 7 }; exit 0\n"
    )
    for args in (["init"], ["add", "."], ["-c", "user.name=Launcher Test", "-c", "user.email=test@example.invalid", "commit", "-m", "fixture"]):
        subprocess.run(["git", *args], cwd=root, check=True, capture_output=True)
    return root


@pytest.mark.parametrize("mode,expected", [("passed", 0), ("missing", 1), ("nonzero", 1)])
def test_terminal_exit_and_summary_must_agree(checkout, mode, expected):
    env = dict(os.environ, SIXGR_LAUNCHER_TEST_MODE=mode)
    result = subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         str(checkout / "scripts/run_server_testall.ps1"), "-PreflightOnly",
         "-MatlabExe", str(checkout / "fake_matlab.cmd")],
        cwd=checkout, env=env, capture_output=True, text=True, timeout=90,
    )
    assert result.returncode == expected, result.stdout + result.stderr
    runs = list((checkout / "logs").glob("testall_*/launcher.json"))
    assert len(runs) == 1
    meta = json.loads(runs[0].read_text(encoding="utf-8-sig"))
    assert not meta["suite_pass"]
    assert meta["status"] == ("preflight_passed_not_testall" if expected == 0 else "failed_or_incomplete")
    assert Path(str(runs[0].parent) + ".zip").is_file()
    assert subprocess.check_output(["git", "status", "--porcelain"], cwd=checkout).strip() == b""


def test_startup_error_still_has_shareable_logs(checkout):
    result = subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         str(checkout / "scripts/run_server_testall.ps1"), "-MatlabExe", "not-an-installed-matlab.exe"],
        cwd=checkout, capture_output=True, text=True, timeout=90,
    )
    assert result.returncode == 1
    runs = list((checkout / "logs").glob("testall_*/launcher.json"))
    meta = json.loads(runs[0].read_text(encoding="utf-8-sig"))
    assert meta["status"] == "failed_or_incomplete" and not meta["suite_pass"]
    assert (runs[0].parent / "launcher_error.txt").is_file()
    assert Path(str(runs[0].parent) + ".zip").is_file()
