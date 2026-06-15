#!/usr/bin/env python
from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from pathlib import Path


REQUIRED_COLUMNS = [
    "issue_id",
    "severity",
    "area",
    "category",
    "summary",
    "evidence",
    "impact",
    "recommended_fix",
    "source",
    "fix_status",
    "fix_commit_or_patch",
    "regression_test",
    "verification_artifact",
]
BLOCKING_SEVERITIES = {"critical", "high", "medium"}
RESOLVED_STATUSES = {"fixed", "verified", "closed"}
WAIVER_STATUS = "waived_non_blocking"


@dataclass(frozen=True)
class GateResult:
    ok: bool
    missing_columns: list[str]
    blocking_rows: list[dict[str, str]]
    waiver_errors: list[str]


def read_backlog(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        fieldnames = list(reader.fieldnames or [])
    return fieldnames, rows


def evaluate_backlog(path: Path) -> GateResult:
    fieldnames, rows = read_backlog(path)
    missing = [name for name in REQUIRED_COLUMNS if name not in fieldnames]
    blocking: list[dict[str, str]] = []
    waiver_errors: list[str] = []

    if missing:
        return GateResult(False, missing, rows, ["backlog schema is incomplete"])

    for row in rows:
        severity = str(row.get("severity", "")).strip().lower()
        status = str(row.get("fix_status", "")).strip().lower()
        issue_id = str(row.get("issue_id", "")).strip()
        evidence = str(row.get("evidence", "")).strip()
        test = str(row.get("regression_test", "")).strip()
        artifact = str(row.get("verification_artifact", "")).strip()

        if not issue_id:
            blocking.append(row)
            continue

        if severity == "critical" and status == WAIVER_STATUS:
            waiver_errors.append(f"{issue_id}: critical issues cannot be waived")
            blocking.append(row)
            continue

        if severity in BLOCKING_SEVERITIES and status not in RESOLVED_STATUSES and status != WAIVER_STATUS:
            blocking.append(row)
            continue

        if status in RESOLVED_STATUSES and (not evidence or not test or not artifact):
            waiver_errors.append(f"{issue_id}: resolved issue lacks evidence, regression_test, or verification_artifact")
            blocking.append(row)

    ok = not missing and not blocking and not waiver_errors
    return GateResult(ok, missing, blocking, waiver_errors)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Fail CI when mandatory LLS audit issues remain unresolved.")
    parser.add_argument(
        "backlog",
        nargs="?",
        default="docs/audit/issue_fix_backlog.csv",
        help="Path to issue_fix_backlog.csv",
    )
    parser.add_argument(
        "--allow-open",
        action="store_true",
        help="Report active blockers but return success. Use only for local planning, not CI.",
    )
    args = parser.parse_args(argv)

    backlog = Path(args.backlog)
    if not backlog.is_file():
        print(f"ERROR: issue backlog not found: {backlog}", file=sys.stderr)
        return 2

    result = evaluate_backlog(backlog)
    if result.missing_columns:
        print("ERROR: backlog is missing required columns: " + ", ".join(result.missing_columns), file=sys.stderr)

    if result.waiver_errors:
        for error in result.waiver_errors:
            print(f"ERROR: {error}", file=sys.stderr)

    if result.blocking_rows:
        print(f"Active mandatory LLS issue blockers: {len(result.blocking_rows)}")
        for row in result.blocking_rows[:25]:
            print(
                f"- {row.get('issue_id','<missing>')} "
                f"[{row.get('severity','')}/{row.get('fix_status','')}]: {row.get('summary','')}"
            )
        if len(result.blocking_rows) > 25:
            print(f"- ... {len(result.blocking_rows) - 25} additional blockers omitted")
    else:
        print("No active critical/high/medium backlog blockers.")

    if result.ok or args.allow_open:
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
