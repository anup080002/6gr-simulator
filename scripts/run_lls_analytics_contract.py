from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_output_contract as contract  # noqa: E402


def build_rows() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for row in contract.iter_table_specs("analytics"):
        rows.append({
            "job_id": f"analytics_table::{row['table_name']}",
            "section_slug": str(row["section_slug"]),
            "output_name": str(row["table_name"]),
            "record_kind": "table",
            "source_policy": "canonical_reports_tables_and_artifact_manifests_only",
            "default_status": "registered_unavailable_until_reports_inputs_exist",
            "formula_required": "true",
            "valid_sample_count_required": "true",
            "missing_sample_count_required": "true",
            "artifact_id_required_when_generated": "true",
            "placeholder_allowed": "false",
            "smoke_visible_default": "false",
        })
    for row in contract.iter_chart_specs("analytics"):
        rows.append({
            "job_id": f"analytics_chart::{row['section_slug']}::{row['chart_name']}",
            "section_slug": str(row["section_slug"]),
            "output_name": str(row["chart_name"]),
            "record_kind": "chart",
            "source_policy": "render_only_from_real_analytics_table_rows",
            "default_status": "registered_unavailable_until_source_rows_exist",
            "formula_required": "true",
            "valid_sample_count_required": "true",
            "missing_sample_count_required": "true",
            "artifact_id_required_when_generated": "true",
            "placeholder_allowed": "false",
            "smoke_visible_default": "false",
        })
    return rows


def write_manifest(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = build_rows()
    fields = list(rows[0].keys()) if rows else []
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description="Register additive LLS analytics jobs without fabricating data.")
    parser.add_argument("--manifest", default="reports/67_analytics_job_manifest.csv")
    args = parser.parse_args()
    write_manifest(REPO_ROOT / args.manifest)


if __name__ == "__main__":
    main()
