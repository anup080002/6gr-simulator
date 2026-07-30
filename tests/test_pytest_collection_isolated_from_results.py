from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _collect(cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            "--collect-only",
            "-q",
            str(REPO_ROOT / "tests"),
        ],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def test_pytest_collection_isolated_from_results(tmp_path: Path) -> None:
    probe = REPO_ROOT / "results" / "pytest_collection_isolation_probe"
    if probe.exists():
        shutil.rmtree(probe)
    probe.mkdir(parents=True)
    shadow = probe / "test_generated_result_shadow.py"
    shadow.write_text(
        "raise RuntimeError('generated result tree was collected')\n",
        encoding="utf-8",
    )
    try:
        first = _collect(REPO_ROOT)
        shadow.unlink()
        probe.rmdir()
        second = _collect(tmp_path)
    finally:
        if probe.exists():
            shutil.rmtree(probe)
    assert first.returncode == 0, first.stdout
    assert second.returncode == 0, second.stdout
    assert "test_generated_result_shadow" not in first.stdout
    assert "test_generated_result_shadow" not in second.stdout
