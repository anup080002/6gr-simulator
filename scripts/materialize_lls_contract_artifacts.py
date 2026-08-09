from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).absolute().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_contract_materializer as materializer  # noqa: E402
import lls_web_dashboard as dash  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Materialize canonical Reports/Analytics contract artifacts for a completed LLS run."
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--run-id", type=int, help="DB run_id to materialize.")
    source.add_argument(
        "--run-folder",
        type=Path,
        help=(
            "Filesystem-backed completed run to verify against the same browser "
            "contract. No database or placeholder artifacts are created."
        ),
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail if any non-policy contract table/chart artifact is still missing after materialization.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Bypass the manifest-current fast path and rebuild contract artifacts for this run.",
    )
    args = parser.parse_args()

    if args.run_folder is not None:
        run_folder = args.run_folder.absolute()
        run_row = dash.filesystem_run_row_from_folder(run_folder)
        if run_row is None:
            raise SystemExit(
                f"Filesystem run metadata was not found under {run_folder}."
            )
        artifacts = dash.filesystem_artifacts_for_run(run_row)
        policy = dash.extract_run_feature_policy(run_row)
        result = materializer.materialize_filesystem_run_contract_artifacts(
            run_row,
            artifacts,
            feature_policy=policy,
            force=bool(args.force),
        )
        # Terminal filesystem runs are cached by the dashboard.  The cache
        # necessarily reflects the pre-materialization file set unless it is
        # invalidated before strict coverage is recomputed.
        dash.clear_dashboard_caches(int(run_row.get("run_id") or 0))
        run_row = dash.filesystem_run_row_from_folder(run_folder) or run_row
        refreshed = dash.filesystem_artifacts_for_run(run_row)
        coverage = materializer.coverage_summary(refreshed, policy)
        payload = {
            "run_id": int(run_row.get("run_id") or 0),
            "run_folder": str(run_folder),
            "storage_backend": "results_folder",
            "verification_only": False,
            "materializer_version": materializer.MATERIALIZER_VERSION,
            "created_count": len(result.get("created") or []),
            "manifest_path": result.get("manifest_path"),
            "coverage_path": result.get("coverage_path"),
            "tables_total": coverage.get("tables_total"),
            "tables_available": coverage.get("tables_available"),
            "tables_policy_disabled": coverage.get("tables_policy_disabled"),
            "tables_missing": len(coverage.get("missing_table_paths") or []),
            "charts_total": coverage.get("charts_total"),
            "charts_available": coverage.get("charts_available"),
            "charts_policy_disabled": coverage.get("charts_policy_disabled"),
            "charts_missing": len(coverage.get("missing_chart_names") or []),
        }
        print(json.dumps(payload, indent=2))
        if args.strict and (
            coverage.get("missing_table_paths")
            or coverage.get("missing_chart_names")
        ):
            missing_tables = ", ".join(coverage.get("missing_table_paths") or [])
            missing_charts = ", ".join(coverage.get("missing_chart_names") or [])
            raise SystemExit(
                "Filesystem contract verification incomplete. "
                f"Missing tables: [{missing_tables}] "
                f"Missing charts: [{missing_charts}]"
            )
        return 0

    run_row = dash.fetch_run(int(args.run_id))
    if run_row is None:
        raise SystemExit(f"Run {args.run_id} was not found in sim_runs.")

    artifacts = dash.fetch_artifacts(int(args.run_id))
    result = materializer.materialize_run_contract_artifacts(
        run_row,
        artifacts,
        fetch_artifact_bytes=dash.fetch_artifact_bytes,
        db_connection_factory=dash.db_connection,
        feature_policy=dash.extract_run_feature_policy(run_row),
        force=bool(args.force),
        lock_timeout_seconds=300,
    )
    coverage = dict(result.get("coverage") or {})
    if not coverage:
        refreshed = dash.fetch_artifacts(int(args.run_id))
        coverage = materializer.coverage_summary(
            refreshed,
            dash.extract_run_feature_policy(run_row),
        )

    payload = {
        "run_id": int(args.run_id),
        "materializer_version": materializer.MATERIALIZER_VERSION,
        "created_count": len(result.get("created") or []),
        "manifest_path": result.get("manifest_path"),
        "coverage_path": result.get("coverage_path"),
        "tables_total": coverage.get("tables_total"),
        "tables_available": coverage.get("tables_available"),
        "tables_policy_disabled": coverage.get("tables_policy_disabled"),
        "tables_missing": len(coverage.get("missing_table_paths") or []),
        "charts_total": coverage.get("charts_total"),
        "charts_available": coverage.get("charts_available"),
        "charts_policy_disabled": coverage.get("charts_policy_disabled"),
        "charts_missing": len(coverage.get("missing_chart_names") or []),
    }
    print(json.dumps(payload, indent=2))

    if args.strict and (
        coverage.get("missing_table_paths") or coverage.get("missing_chart_names")
    ):
        missing_tables = ", ".join(coverage.get("missing_table_paths") or [])
        missing_charts = ", ".join(coverage.get("missing_chart_names") or [])
        raise SystemExit(
            "Contract materialization incomplete. "
            f"Missing tables: [{missing_tables}] Missing charts: [{missing_charts}]"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
