from __future__ import annotations

import csv
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
TOOL = REPO_ROOT / "tools" / "audit" / "check_issue_backlog.py"
FIELDNAMES = [
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


def write_backlog(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES)
        writer.writeheader()
        writer.writerows(rows)


def test_issue_backlog_gate_blocks_open_high_issue(tmp_path: Path) -> None:
    backlog = tmp_path / "issue_fix_backlog.csv"
    write_backlog(
        backlog,
        [
            {
                "issue_id": "AUD-TEST",
                "severity": "high",
                "area": "truth",
                "category": "gate",
                "summary": "open high issue",
                "evidence": "unit fixture",
                "impact": "must block",
                "recommended_fix": "fix it",
                "source": "test",
                "fix_status": "open",
                "fix_commit_or_patch": "pending",
                "regression_test": "unit",
                "verification_artifact": "artifact",
            }
        ],
    )

    proc = subprocess.run([sys.executable, str(TOOL), str(backlog)], cwd=REPO_ROOT, text=True, capture_output=True, check=False)
    assert proc.returncode == 1
    assert "AUD-TEST" in proc.stdout


def test_issue_backlog_gate_allows_verified_issue(tmp_path: Path) -> None:
    backlog = tmp_path / "issue_fix_backlog.csv"
    write_backlog(
        backlog,
        [
            {
                "issue_id": "AUD-FIXED",
                "severity": "critical",
                "area": "truth",
                "category": "gate",
                "summary": "verified critical issue",
                "evidence": "runtime evidence",
                "impact": "fixed",
                "recommended_fix": "done",
                "source": "test",
                "fix_status": "verified",
                "fix_commit_or_patch": "abc123",
                "regression_test": "unit",
                "verification_artifact": "artifact",
            }
        ],
    )

    proc = subprocess.run([sys.executable, str(TOOL), str(backlog)], cwd=REPO_ROOT, text=True, capture_output=True, check=False)
    assert proc.returncode == 0
    assert "No active" in proc.stdout


def test_issue_backlog_gate_rejects_critical_waiver(tmp_path: Path) -> None:
    backlog = tmp_path / "issue_fix_backlog.csv"
    write_backlog(
        backlog,
        [
            {
                "issue_id": "AUD-CRIT",
                "severity": "critical",
                "area": "truth",
                "category": "waiver",
                "summary": "critical waived",
                "evidence": "unit fixture",
                "impact": "must block",
                "recommended_fix": "fix it",
                "source": "test",
                "fix_status": "waived_non_blocking",
                "fix_commit_or_patch": "pending",
                "regression_test": "unit",
                "verification_artifact": "artifact",
            }
        ],
    )

    proc = subprocess.run([sys.executable, str(TOOL), str(backlog)], cwd=REPO_ROOT, text=True, capture_output=True, check=False)
    assert proc.returncode == 1
    assert "critical issues cannot be waived" in proc.stderr
