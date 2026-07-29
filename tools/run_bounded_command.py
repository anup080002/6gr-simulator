"""Run one command with an exact wall-clock limit and a durable log.

This helper is intentionally small and dependency-free so MATLAB qualification
orchestrators can execute repository regressions without allowing an in-process
test runner to exceed the selected preset's bounded runtime contract.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


TIMEOUT_EXIT_CODE = 124


def _terminate_tree(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(process.pid), "/T", "/F"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    else:
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=5)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout-seconds", type=float, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--heartbeat-seconds", type=float, default=30.0)
    parser.add_argument("--heartbeat-file", type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = list(args.command)
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("a command is required after --")
    if not args.timeout_seconds > 0:
        parser.error("--timeout-seconds must be positive")
    if not args.heartbeat_seconds > 0:
        parser.error("--heartbeat-seconds must be positive")

    args.log.parent.mkdir(parents=True, exist_ok=True)
    if args.heartbeat_file is not None:
        args.heartbeat_file.parent.mkdir(parents=True, exist_ok=True)
    creation_flags = (
        subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
    )
    with args.log.open("wb") as output:
        process = subprocess.Popen(
            command,
            cwd=Path.cwd(),
            stdout=output,
            stderr=subprocess.STDOUT,
            start_new_session=os.name != "nt",
            creationflags=creation_flags,
        )
        started = time.monotonic()
        deadline = started + args.timeout_seconds
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                _terminate_tree(process)
                output.write(
                    (
                        f"\nFULLSTACK:RegressionTimeout command exceeded "
                        f"{args.timeout_seconds:.3f} seconds.\n"
                    ).encode("utf-8")
                )
                output.flush()
                return TIMEOUT_EXIT_CODE
            try:
                return process.wait(
                    timeout=min(args.heartbeat_seconds, remaining)
                )
            except subprocess.TimeoutExpired:
                if args.heartbeat_file is not None:
                    payload = {
                        "utc": datetime.now(timezone.utc).isoformat(),
                        "pid": process.pid,
                        "elapsed_seconds": round(
                            time.monotonic() - started, 6
                        ),
                        "timeout_seconds": args.timeout_seconds,
                        "status": "RUNNING",
                    }
                    args.heartbeat_file.write_text(
                        json.dumps(payload, sort_keys=True) + "\n",
                        encoding="utf-8",
                    )


if __name__ == "__main__":
    sys.exit(main())
