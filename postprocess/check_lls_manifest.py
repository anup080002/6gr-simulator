#!/usr/bin/env python3
"""Audit a completed run directory against the LLS publication manifest."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from lls_manifest_contract import run_manifest_audit, final_manifest_acceptance_gate


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_dir", type=Path)
    parser.add_argument("--strict", action="store_true", help="Exit non-zero if acceptance gate fails.")
    args = parser.parse_args(argv)
    if not args.run_dir.exists():
        print(f"Run directory does not exist: {args.run_dir}", file=sys.stderr)
        return 2
    result = run_manifest_audit(args.run_dir)
    summary = result["summary"]
    print(f"Manifest audit: {summary['pass_count']}/{summary['total_items']} PASS")
    print(f"Report: {args.run_dir / 'reports' / 'csv' / 'manifest_audit_report.csv'}")
    gate = final_manifest_acceptance_gate(args.run_dir)
    print(
        "Gate: "
        f"T1={'PASS' if gate['tier1_pass'] else 'FAIL'} "
        f"T2={gate['tier2_pass_fraction']:.2f} "
        f"Images={gate['image_pass_fraction']:.2f} "
        f"NoBlocked={'PASS' if gate['no_blocked'] else 'FAIL'} "
        f"Grade={gate['grade_estimate']}/10"
    )
    return 1 if args.strict and not gate["ok"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
