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
PER_TEST_TIMEOUT_EXIT_CODE = 125
TEST_START_PREFIX = "FULLSTACK_TEST_START "
TEST_END_PREFIX = "FULLSTACK_TEST_END "


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


def _progress_events(log_path: Path, offset: int) -> tuple[int, list[str]]:
    """Return complete progress lines appended since *offset*."""
    try:
        with log_path.open("rb") as stream:
            stream.seek(offset)
            payload = stream.read()
            new_offset = stream.tell()
    except FileNotFoundError:
        return offset, []
    # MATLAB emits one complete marker per line. Ignore a trailing partial
    # line; it will be re-read at the next heartbeat.
    complete = payload.rsplit(b"\n", 1)
    if len(complete) == 1:
        return offset, []
    consumed = len(complete[0]) + 1
    lines = complete[0].decode("utf-8", errors="replace").splitlines()
    return offset + consumed, lines


def _append_log(output: object, message: str) -> None:
    output.seek(0, os.SEEK_END)
    output.write(message.encode("utf-8"))
    output.flush()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout-seconds", type=float, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--heartbeat-seconds", type=float, default=30.0)
    parser.add_argument("--heartbeat-file", type=Path)
    parser.add_argument("--per-test-timeout-seconds", type=float)
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
    if (
        args.per_test_timeout_seconds is not None
        and not args.per_test_timeout_seconds > 0
    ):
        parser.error("--per-test-timeout-seconds must be positive")

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
        progress_offset = 0
        active_test: str | None = None
        active_test_started: float | None = None
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                _terminate_tree(process)
                _append_log(
                    output,
                    f"\nFULLSTACK:RegressionTimeout command exceeded "
                    f"{args.timeout_seconds:.3f} seconds.\n",
                )
                return TIMEOUT_EXIT_CODE
            try:
                return process.wait(
                    timeout=min(args.heartbeat_seconds, remaining)
                )
            except subprocess.TimeoutExpired:
                progress_offset, lines = _progress_events(
                    args.log, progress_offset
                )
                for line in lines:
                    if line.startswith(TEST_START_PREFIX):
                        active_test = line.removeprefix(
                            TEST_START_PREFIX
                        ).strip()
                        active_test_started = time.monotonic()
                    elif line.startswith(TEST_END_PREFIX):
                        completed = line.removeprefix(
                            TEST_END_PREFIX
                        ).strip()
                        if active_test and completed.startswith(active_test):
                            active_test = None
                            active_test_started = None
                active_elapsed = (
                    time.monotonic() - active_test_started
                    if active_test_started is not None
                    else None
                )
                if (
                    args.per_test_timeout_seconds is not None
                    and active_elapsed is not None
                    and active_elapsed > args.per_test_timeout_seconds
                ):
                    _terminate_tree(process)
                    _append_log(
                        output,
                        "\nFULLSTACK:PerTestTimeout "
                        f"test '{active_test}' exceeded "
                        f"{args.per_test_timeout_seconds:.3f} seconds.\n",
                    )
                    return PER_TEST_TIMEOUT_EXIT_CODE
                if args.heartbeat_file is not None:
                    payload = {
                        "utc": datetime.now(timezone.utc).isoformat(),
                        "pid": process.pid,
                        "elapsed_seconds": round(
                            time.monotonic() - started, 6
                        ),
                        "timeout_seconds": args.timeout_seconds,
                        "per_test_timeout_seconds": (
                            args.per_test_timeout_seconds
                        ),
                        "active_test": active_test,
                        "active_test_elapsed_seconds": (
                            round(active_elapsed, 6)
                            if active_elapsed is not None
                            else None
                        ),
                        "status": "RUNNING",
                    }
                    args.heartbeat_file.write_text(
                        json.dumps(payload, sort_keys=True) + "\n",
                        encoding="utf-8",
                    )


if __name__ == "__main__":
    sys.exit(main())
