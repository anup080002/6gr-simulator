from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def resolve_run(args: argparse.Namespace) -> dict:
    if args.run_id is not None:
        row = dash.fetch_run(int(args.run_id))
        if row is None:
            raise KeyError(f"Run {args.run_id} was not found.")
        return row
    if not args.run_tag:
        raise ValueError("Either --run-id or --run-tag is required.")
    runs = dash.fetch_runs(limit=200, run_tag=args.run_tag)
    if not runs:
        raise KeyError(f"Run tag {args.run_tag!r} was not found.")
    return runs[0]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Optional post-processing helper for DB-backed 6G_4GHz_100MHz_19S3_100UE_UMa runs."
    )
    parser.add_argument("--run-id", type=int, default=None)
    parser.add_argument("--run-tag", default="")
    args = parser.parse_args()

    run_row = resolve_run(args)
    run_id = int(run_row["run_id"])
    artifacts = dash.fetch_artifacts(run_id)

    logical_paths = [
        "reports/csv/scenario_summary.csv",
        "reports/csv/runtime_operating_mode.csv",
        "reports/csv/live_error_rate_summary.csv",
        "reports/csv/live_user_performance_snapshot.csv",
        "air_interface/csv/dl_pdsch_trials.csv",
        "air_interface/csv/ul_pusch_trials.csv",
    ]
    preview = {}
    for logical_path in logical_paths:
        preview[logical_path] = dash.load_small_csv_rows(artifacts, logical_path, max_rows=10)

    print(
        json.dumps(
            {
                "run_id": run_id,
                "run_tag": run_row.get("run_tag"),
                "scenario_id": run_row.get("scenario_id"),
                "artifact_preview": preview,
            },
            indent=2,
            default=str,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
