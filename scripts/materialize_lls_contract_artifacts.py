from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).absolute().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_contract_materializer as materializer  # noqa: E402
import lls_web_dashboard as dash  # noqa: E402
from regenerate_lls_rasters_from_csv import (  # noqa: E402
    RASTER_SUFFIXES,
    io_path,
    materialize_declared_artifact_generation_rasters,
    materialize_frc_reference_rasters,
    reconcile_removed_raster_lineage,
    raster_inventory,
    require_primary_csv_semantics,
    validate_run_root,
    write_csv,
)


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
    parser.add_argument(
        "--replace-existing-rasters-from-csv",
        action="store_true",
        help=(
            "After the primary CSV semantic gate passes, inventory and remove all "
            "run-local PNG/JPEG files before rebuilding eligible scientific charts "
            "from exact CSV sources. No reason-card image is generated."
        ),
    )
    args = parser.parse_args()

    if args.run_folder is not None:
        # Contract materialization itself is run-folder-local and
        # non-destructive, so it is valid for isolated test/recovery roots.
        # The repository-root restriction applies only to the explicit
        # destructive raster-replacement option.
        if args.replace_existing_rasters_from_csv:
            run_folder = validate_run_root(args.run_folder)
        else:
            run_folder = Path(args.run_folder).resolve()
            if not run_folder.is_dir():
                raise SystemExit(f"Filesystem run folder does not exist: {run_folder}")
        _, policy = _filesystem_run_policy(run_folder)

        def policy_filter(path: str, name: str) -> bool:
            return materializer.contract_artifact_is_policy_filtered(
                path, policy, contract_name=name
            )

        removed_rasters: list[dict[str, object]] = []
        declared_artifact_rasters: list[dict[str, str]] = []
        if args.replace_existing_rasters_from_csv:
            require_primary_csv_semantics(run_folder, policy_filter=policy_filter)
            removed_rasters = raster_inventory(run_folder)
            inventory_path = (
                run_folder / "reports" / "csv" / "raster_replacement_inventory.csv"
            )
            write_csv(
                inventory_path,
                removed_rasters,
                [
                    "relative_path",
                    "extension",
                    "bytes",
                    "sha256",
                    "width_px",
                    "height_px",
                    "format",
                ],
            )
            for row in removed_rasters:
                target = (run_folder / str(row["relative_path"])).resolve()
                target.relative_to(run_folder)
                if target.suffix.lower() not in RASTER_SUFFIXES:
                    raise RuntimeError(f"Refusing to remove non-raster path {target}")
                io_path(target).unlink()
            # Artifact-engine PNGs are separate from the browser chart
            # contract, but their PASS rows are just as binding.  Rebuild
            # them now from their exact declared CSV sources so they are in
            # the filesystem inventory consumed by the post-render image
            # audit.  Leaving their old PASS rows after deleting the images
            # would make the run manifest dishonest.
            declared_artifact_rasters = materialize_declared_artifact_generation_rasters(
                run_folder
            )
        # Index only after any raster replacement so the filesystem artifact
        # set cannot be cached from the pre-replacement tree.
        run_row = dash.filesystem_run_row_from_folder(run_folder)
        if run_row is None:
            raise SystemExit(
                f"Filesystem run metadata was not found under {run_folder}."
            )
        artifacts = dash.filesystem_artifacts_for_run(run_row)
        result = materializer.materialize_filesystem_run_contract_artifacts(
            run_row,
            artifacts,
            feature_policy=policy,
            force=bool(args.force),
        )
        frc_reference_rasters: list[dict[str, str]] = []
        if args.replace_existing_rasters_from_csv:
            # FRC reference-point plots are outside the browser chart catalog,
            # but their lineage is a required scientific contract. Rebuild
            # them from the exact persisted per-entry CSVs before stale
            # lineage reconciliation runs.
            frc_reference_rasters = materialize_frc_reference_rasters(run_folder)
        retired_lineage_rows = []
        if args.replace_existing_rasters_from_csv:
            retired_lineage_rows = reconcile_removed_raster_lineage(run_folder)
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
            "old_rasters_removed": len(removed_rasters),
            "declared_artifact_rasters_regenerated": len(declared_artifact_rasters),
            "frc_reference_rasters_regenerated": len(frc_reference_rasters),
            "stale_raster_lineage_rows_retired": len(retired_lineage_rows),
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


def _filesystem_run_policy(run_folder: Path) -> tuple[dict[str, object], dict[str, object]]:
    """Resolve applicability before destructive raster replacement.

    This metadata read is policy-only. The run is indexed again after raster
    replacement so cached filesystem artifacts always describe the new tree.
    """
    policy_row = dash.filesystem_run_row_from_folder(run_folder)
    if policy_row is None:
        raise SystemExit(f"Filesystem run metadata was not found under {run_folder}.")
    return policy_row, dash.extract_run_feature_policy(policy_row)


if __name__ == "__main__":
    raise SystemExit(main())
