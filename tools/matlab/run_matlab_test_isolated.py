#!/usr/bin/env python3
"""Run MATLAB tests in fresh processes and persist crash-aware logs.

This helper is intentionally small: it launches one MATLAB process per test so
native crashes cannot poison a long-lived MATLAB session or hide the failing
test behind later state.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


CRASH_PATTERNS = (
    "access violation",
    "segmentation violation",
    "segmentation fault",
    "fatal error",
    "matlab error exit status",
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def matlab_exe() -> str:
    env_value = os.environ.get("MATLAB_EXE", "").strip()
    if env_value:
        return env_value
    default_r2024a = Path(r"C:\Program Files\MATLAB\R2024a\bin\matlab.exe")
    if default_r2024a.exists():
        return str(default_r2024a)
    return "matlab"


def normalize_test_name(raw: str) -> str:
    name = Path(raw).stem if raw.lower().endswith(".m") else raw
    name = name.strip()
    if not re.fullmatch(r"[A-Za-z]\w*", name):
        raise ValueError(f"Invalid MATLAB test function name: {raw!r}")
    return name


def matlab_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def run_one(test_name: str, timeout_s: int, log_dir: Path) -> dict:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    log_path = log_dir / f"{timestamp}_{test_name}.log"
    batch = (
        "setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false); "
        f"try, feval({matlab_literal(test_name)}); "
        "catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end; exit(0);"
    )
    cmd = [matlab_exe(), "-batch", batch]
    started = datetime.now(timezone.utc)
    timed_out = False
    try:
        proc = subprocess.run(
            cmd,
            cwd=repo_root(),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout_s,
            check=False,
        )
        output = proc.stdout or ""
        return_code = int(proc.returncode)
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        output = (exc.stdout or "") + "\nTIMEOUT: MATLAB test exceeded timeout.\n"
        return_code = 124

    ended = datetime.now(timezone.utc)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(output, encoding="utf-8", errors="replace")
    lower_output = output.lower()
    crashed = any(pattern in lower_output for pattern in CRASH_PATTERNS)
    return {
        "test": test_name,
        "ok": return_code == 0 and not timed_out and not crashed,
        "return_code": return_code,
        "timed_out": timed_out,
        "crashed": crashed,
        "started_utc": started.isoformat(),
        "ended_utc": ended.isoformat(),
        "log": str(log_path),
        "matlab": matlab_exe(),
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="+", help="MATLAB test function names or tests/*.m paths.")
    parser.add_argument("--timeout", type=int, default=600, help="Per-test timeout in seconds.")
    parser.add_argument("--cooldown", type=float, default=3.0, help="Delay between MATLAB processes.")
    parser.add_argument("--log-dir", default="reports/logs/matlab", help="Directory for per-test logs.")
    args = parser.parse_args(argv)

    root = repo_root()
    log_dir = (root / args.log_dir).resolve()
    log_dir.mkdir(parents=True, exist_ok=True)
    results = []
    for idx, test_arg in enumerate(args.tests):
        if idx > 0 and args.cooldown > 0:
            time.sleep(float(args.cooldown))
        results.append(run_one(normalize_test_name(test_arg), int(args.timeout), log_dir))

    summary_path = log_dir / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "_isolated_summary.json")
    summary_path.write_text(json.dumps({"results": results}, indent=2), encoding="utf-8")
    for result in results:
        status = "PASS" if result["ok"] else "FAIL"
        print(f"[{status}] {result['test']} rc={result['return_code']} crash={result['crashed']} log={result['log']}")
    print(f"summary={summary_path}")
    return 0 if all(r["ok"] for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
