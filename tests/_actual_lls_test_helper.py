from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
RUNNER = REPO_ROOT / "tools" / "matlab" / "run_matlab_test_isolated.py"


def run_isolated_matlab_test(test_file: str) -> None:
    last = None
    for attempt in range(3):
        if attempt > 0:
            time.sleep(5)
        completed = subprocess.run(
            [sys.executable, str(RUNNER), test_file, "--cooldown", "3"],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        last = completed
        if completed.returncode == 0:
            return
        crash_text = (completed.stdout + completed.stderr).lower()
        if "crash=true" not in crash_text and "3221225477" not in crash_text:
            break

    assert last is not None
    assert last.returncode == 0, (
        f"isolated MATLAB test failed for {test_file}\n"
        f"stdout:\n{last.stdout}\n"
        f"stderr:\n{last.stderr}"
    )
