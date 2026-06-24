#!/usr/bin/env python3
"""Run the full LLS manifest pipeline: audit, generate, plot, re-audit."""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from lls_manifest_contract import final_manifest_acceptance_gate  # noqa: E402


def run_step(script: str, run_dir: Path, extra_args: list[str] | None = None) -> int:
    cmd = [sys.executable, str(SCRIPT_DIR / script), str(run_dir)]
    if extra_args:
        cmd.extend(extra_args)
    print(f"\nRunning {script}")
    proc = subprocess.run(cmd, cwd=SCRIPT_DIR.parent, text=True, check=False)
    return int(proc.returncode)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_dir", type=Path)
    parser.add_argument("--overwrite", action="store_true", help="Regenerate derived CSVs and plots even when present.")
    parser.add_argument("--strict", action="store_true", help="Exit non-zero if the final acceptance gate fails.")
    args = parser.parse_args(argv)
    if not args.run_dir.exists():
        print(f"Run directory does not exist: {args.run_dir}", file=sys.stderr)
        return 2

    print("=" * 60)
    print("LLS Full Manifest Pipeline")
    print(f"Run: {args.run_dir}")
    print("=" * 60)

    rc = 0
    rc |= run_step("check_lls_manifest.py", args.run_dir)
    csv_args = ["--overwrite"] if args.overwrite else []
    rc |= run_step("generate_missing_csvs.py", args.run_dir, csv_args)
    rc |= run_step("generate_missing_plots.py", args.run_dir, csv_args)
    rc |= run_step("check_lls_manifest.py", args.run_dir)

    gate = final_manifest_acceptance_gate(args.run_dir)
    print("\nFinal gate")
    print(f"Tier 1 raw trials: {'PASS' if gate['tier1_pass'] else 'FAIL'}")
    print(f"Tier 2 strict pass fraction: {gate['tier2_pass_fraction']:.2f}")
    print(f"Image pass fraction: {gate['image_pass_fraction']:.2f}")
    print(f"No blocked items: {'PASS' if gate['no_blocked'] else 'FAIL'}")
    print(f"Overall: {gate['pass_count']}/{gate['total_items']} PASS")
    print(f"Grade estimate: {gate['grade_estimate']}/10")
    print(f"Audit report: {args.run_dir / 'reports' / 'csv' / 'manifest_audit_report.csv'}")
    print(f"Dashboard: {args.run_dir / 'reports' / 'html' / 'master_dashboard.html'}")

    if rc != 0:
        return rc
    return 1 if args.strict and not gate["ok"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
