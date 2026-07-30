"""Collect and execute an explicit pytest shard with durable test counts."""

from __future__ import annotations

import argparse
import csv
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


def _run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def _collection_count(output: str) -> int:
    matches = re.findall(
        r"(\d+)\s+(?:tests?|items?)\s+collected", output
    )
    if matches:
        return int(matches[-1])
    node_ids = [
        line
        for line in output.splitlines()
        if "::test" in line and not line.lstrip().startswith("<")
    ]
    return len(node_ids)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--count-output", type=Path, required=True)
    parser.add_argument("--marker", default="")
    parser.add_argument("targets", nargs="+")
    args = parser.parse_args()
    selection = ["-m", args.marker] if args.marker else []
    collect = _run(
        [
            sys.executable,
            "-m",
            "pytest",
            "--collect-only",
            "-q",
            *selection,
            *args.targets,
        ]
    )
    sys.stdout.write(collect.stdout)
    collected = _collection_count(collect.stdout)
    if collect.returncode != 0:
        return collect.returncode
    if collected <= 0:
        sys.stderr.write("FULLSTACK:PytestShardSelectedZeroTests\n")
        return 5
    with tempfile.TemporaryDirectory(prefix="sixgr-pytest-gate-") as temp:
        junit = Path(temp) / "junit.xml"
        execution = _run(
            [
                sys.executable,
                "-m",
                "pytest",
                "-q",
                *selection,
                f"--junitxml={junit}",
                *args.targets,
            ]
        )
        sys.stdout.write(execution.stdout)
        if junit.is_file():
            root = ET.parse(junit).getroot()
            suite = (
                root
                if root.tag == "testsuite"
                else root.find(".//testsuite")
            )
            tests = int(suite.attrib.get("tests", collected))
            failures = int(suite.attrib.get("failures", 0)) + int(
                suite.attrib.get("errors", 0)
            )
            skipped = int(suite.attrib.get("skipped", 0))
        else:
            tests = collected
            failures = 0 if execution.returncode == 0 else 1
            skipped = 0
        passed = max(0, tests - failures - skipped)
        args.count_output.parent.mkdir(parents=True, exist_ok=True)
        with args.count_output.open(
            "w", encoding="utf-8", newline=""
        ) as handle:
            csv.writer(handle).writerow(
                [tests, passed, failures, skipped]
            )
        return execution.returncode


if __name__ == "__main__":
    raise SystemExit(main())
