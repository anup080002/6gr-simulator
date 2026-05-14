from __future__ import annotations

import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    artifacts = [
        {"artifact_id": 1, "logical_path": "reports/csv/scenario_summary.csv"},
        {"artifact_id": 2, "logical_path": "meta/scenario_manifest.json"},
        {"artifact_id": 3, "logical_path": "reports/csv/truth_contract_summary.csv"},
    ]

    orig_fetch_artifacts = dash.fetch_artifacts
    orig_load_cached_csv_preview = dash.load_cached_csv_preview
    orig_fetch_artifact_bytes = dash.fetch_artifact_bytes
    try:
        dash.fetch_artifacts = lambda run_id, kind_prefix=None, limit=None, newest_first=False: list(artifacts)
        dash.load_cached_csv_preview = lambda artifact_id, preview_rows=2: (
            ["RunCompletion", "StatusAuthority", "ResultOk", "RuntimeTruthContractOk", "RequiredFailureCount"],
            [["completed", "scenario_status_aggregation_v2_runtime_truth_contract", "1", "1", "0"]],
        )
        dash.fetch_artifact_bytes = lambda artifact_id: json.dumps(
            {
                "RunCompletion": "completed",
                "StatusAuthority": "scenario_status_aggregation_v2_runtime_truth_contract",
                "ResultOk": True,
                "RuntimeTruthContractOk": True,
            }
        ).encode("utf-8")

        status = dash.infer_terminal_status_from_artifacts({"run_id": 70})
        assert status is not None, (
            "Terminal promotion must work when scenario summary + manifest + truth contract exist, even if artifact_manifest.json is absent."
        )
        status_text, payload = status
        assert status_text == "completed"
        assert payload["truth_contract_summary"] == "reports/csv/truth_contract_summary.csv"

        dash.fetch_artifacts = lambda run_id, kind_prefix=None, limit=None, newest_first=False: [
            {"artifact_id": 1, "logical_path": "reports/csv/scenario_summary.csv"},
            {"artifact_id": 2, "logical_path": "meta/scenario_manifest.json"},
        ]
        repaired_row, changed = dash.repair_run_row_from_terminal_artifacts(
            {"run_id": 71, "status_text": "aborted_stale_no_run_process", "status_json": "{}"},
            persist=False,
        )
        assert changed, (
            "Rows that were mislabeled stale must be repairable from a truth-gated terminal summary even before late coverage artifacts arrive."
        )
        assert repaired_row["status_text"] == "completed"
        repaired_payload = json.loads(repaired_row["status_json"])
        assert repaired_payload["terminal_evidence_mode"] == "terminal_summary_manifest_truth_fields_only"
    finally:
        dash.fetch_artifacts = orig_fetch_artifacts
        dash.load_cached_csv_preview = orig_load_cached_csv_preview
        dash.fetch_artifact_bytes = orig_fetch_artifact_bytes


if __name__ == "__main__":
    main()
