"""Snapshot MATLAB regression evidence without declaring mixed-source closure.

Only root FULLSTACK markers, paired FOCUSED markers, or timed
runFocusedTests result lines or complete saved runFocusedTests reports count.
Nested probes and arbitrary '[PASS]' text are not regression results. Historical
source identity is unknown unless provided by the original execution receipt;
the current git revision must never be attributed to a retained test run.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import io
import math
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
import re

START = re.compile(r"^FULLSTACK_TEST_START (\w+)\s*$")
END = re.compile(r"^FULLSTACK_TEST_END (\w+) (PASS|FAIL)\s*$")
FOCUSED = re.compile(r"^\[(PASS|FAIL)\] (\w+) \(([0-9.]+)s\)\s*$")
FOCUSED_START = re.compile(r"^FOCUSED_START (\w+)\s*$")
FOCUSED_END = re.compile(r"^FOCUSED_(PASS|FAIL) (\w+)\s*$")


def parse_results(text: str) -> tuple[list[dict], list[str]]:
    """An unmatched start is incomplete, never a pass or a counted failure."""
    rows, active = [], []
    has_markers = any(START.match(line) or END.match(line) for line in text.splitlines())
    has_focused_markers = not has_markers and any(
        FOCUSED_START.match(line) for line in text.splitlines())
    for line_number, line in enumerate(text.splitlines(), 1):
        if match := START.match(line):
            active.append(match[1])
        elif match := END.match(line):
            if not active or active[-1] != match[1]:
                raise ValueError(f"Unmatched terminal marker at line {line_number}: {line}")
            active.pop()
            if not active:
                rows.append(dict(test=match[1], status=match[2], line=line_number))
        elif has_focused_markers and (match := FOCUSED_START.match(line)):
            active.append(match[1])
        elif has_focused_markers and (match := FOCUSED_END.match(line)):
            # Older diagnostic scripts also print unpaired component PASS
            # markers. They are not whole-test completion evidence.
            if not active:
                continue
            if active[-1] != match[2]:
                raise ValueError(f"Unmatched terminal marker at line {line_number}: {line}")
            active.pop()
            if not active:
                rows.append(dict(test=match[2], status=match[1], line=line_number))
        elif not has_markers and not has_focused_markers and (match := FOCUSED.match(line)):
            rows.append(dict(test=match[2], status=match[1], line=line_number))
    return rows, active


def parse_focused_mat(raw: bytes) -> tuple[list[dict], list[str]]:
    """Read terminal reports, not arbitrary booleans or MATLAB object internals.

    Source hashes saved as opaque MATLAB strings are deliberately not decoded
    or replaced by current-checkout hashes. MAT results are observation evidence,
    not proof of final-source acceptance. scipy supports the v7 receipts here;
    unsupported v7.3 files must be converted explicitly, never silently skipped.
    """
    from scipy.io import loadmat

    content = loadmat(io.BytesIO(raw), simplify_cells=True)
    events = []
    for variable, report in content.items():
        if not isinstance(report, dict) or not {
            "ok", "results", "selected_tests", "total_duration_s"
        }.issubset(report):
            continue
        selected = report["selected_tests"]
        selected = [selected] if isinstance(selected, str) else list(selected)
        rows = report["results"]
        rows = [rows] if isinstance(rows, dict) else list(rows)
        if (not selected or len(rows) != len(selected)
                or not math.isfinite(float(report["total_duration_s"]))
                or float(report["total_duration_s"]) < 0):
            raise ValueError(f"Incomplete focused report: {variable}")
        statuses = []
        batch = []
        for index, (name, row) in enumerate(zip(selected, rows)):
            if (not isinstance(name, str) or not re.fullmatch(r"\w+", name)
                    or not isinstance(row, dict) or row.get("name") != name
                    or row.get("ok") not in (0, 1)
                    or not math.isfinite(float(row.get("duration_s", math.nan)))
                    or float(row["duration_s"]) < 0):
                raise ValueError(f"Malformed focused result: {variable}[{index}]")
            statuses.append(bool(row["ok"]))
            batch.append(dict(test=name, status="PASS" if row["ok"] else "FAIL",
                              variable=variable, result_index=index,
                              duration_s=float(row["duration_s"])))
        if report["ok"] not in (0, 1) or bool(report["ok"]) != all(statuses):
            raise ValueError(f"Inconsistent focused report outcome: {variable}")
        events.extend(batch)
    if not events:
        raise ValueError("No complete runFocusedTests report in MAT receipt")
    return events, []


def reconcile(logs: list[Path], output: Path) -> dict:
    # A new directory preserves every prior audit and source log.
    output.mkdir(parents=True, exist_ok=False)
    snapshots = output / "snapshots"
    snapshots.mkdir()
    evidence, receipts = defaultdict(list), []
    for index, supplied in enumerate(logs):
        path = supplied.resolve(strict=True)
        before = path.stat()
        raw = path.read_bytes()
        after = path.stat()
        snapshot = snapshots / f"{index:03d}_{path.name}"
        snapshot.write_bytes(raw)
        if path.suffix.lower() == ".mat":
            events, incomplete = parse_focused_mat(raw)
        else:
            events, incomplete = parse_results(raw.decode("utf-8-sig", errors="replace"))
        digest = hashlib.sha256(raw).hexdigest()
        receipts.append(dict(
            original_path=str(path), snapshot=str(snapshot.relative_to(output)),
            snapshot_sha256=digest, snapshot_bytes=len(raw),
            file_changed_during_read=(before.st_mtime_ns, before.st_size)
            != (after.st_mtime_ns, after.st_size),
            passed=sum(row["status"] == "PASS" for row in events),
            failed=sum(row["status"] == "FAIL" for row in events),
            incomplete_start_markers=incomplete,
            executed_source_identity="unknown_not_inferred_from_current_checkout",
        ))
        for event in events:
            evidence[event["test"]].append(dict(
                **event, log=str(path), snapshot=str(snapshot.relative_to(output)),
                snapshot_sha256=digest,
            ))
    rows = []
    for name, events in sorted(evidence.items()):
        statuses = {event["status"] for event in events}
        state = ("pass_and_fail_evidence_requires_source_check" if len(statuses) == 2
                 else "failure_observed_requires_reproduction" if "FAIL" in statuses
                 else "pass_observed_not_final_source_acceptance")
        rows.append(dict(test=name, state=state,
                         pass_observations=sum(e["status"] == "PASS" for e in events),
                         fail_observations=sum(e["status"] == "FAIL" for e in events),
                         final_source_accepted=False))
    columns = ["test", "state", "pass_observations", "fail_observations", "final_source_accepted"]
    for filename, selected in (
        ("test_inventory.csv", rows),
        ("failure_reconciliation.csv", [row for row in rows if row["fail_observations"]]),
    ):
        with (output / filename).open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=columns)
            writer.writeheader()
            writer.writerows(selected)
    receipt = dict(
        scope="regression_evidence_inventory_not_scientific_qualification",
        snapshot_utc=datetime.now(timezone.utc).isoformat(),
        final_source_accepted=False, logs=receipts,
        distinct_tests=len(rows), tests_with_failure_evidence=sum(bool(r["fail_observations"]) for r in rows),
        evidence=dict(evidence),
    )
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return receipt


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, action="append", default=[])
    parser.add_argument("--mat", type=Path, action="append", default=[],
                        help="Complete saved runFocusedTests v7 MAT receipt")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.log and not args.mat:
        parser.error("Provide at least one --log or --mat receipt")
    receipt = reconcile(args.log + args.mat, args.output)
    print(json.dumps({key: receipt[key] for key in
                      ("distinct_tests", "tests_with_failure_evidence", "final_source_accepted")}))
    print(f"AUDIT_FOLDER={args.output.resolve()}")


if __name__ == "__main__":
    main()
