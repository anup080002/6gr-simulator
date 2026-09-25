"""Consolidate retained generic-sweep CSVs/PNGs without launching MATLAB."""
import argparse
import json
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).absolute().parents[1] / "apps"))
from lls_sweep_report import export_sweep, observe_sweep


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-folder", required=True)
    parser.add_argument("--watch", action="store_true", help="Refresh on point completion; no MATLAB execution")
    args = parser.parse_args()
    previous = None
    while True:
        progress = observe_sweep(args.run_folder)
        signature = tuple((p["label"], p["status"]) for p in progress.get("points", []))
        if signature != previous:
            receipt = export_sweep(args.run_folder)
            print(json.dumps(receipt), flush=True)
            previous = signature
            if receipt["Complete"]:
                return int(receipt["FailedArtifacts"] > 0)
        if not args.watch:
            return int(receipt["FailedArtifacts"] > 0)
        time.sleep(30)


if __name__ == "__main__":
    raise SystemExit(main())
