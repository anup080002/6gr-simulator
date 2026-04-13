from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    artifacts = [
        {"logical_path": "air_interface/csv/dl_pdsch_trials.csv", "artifact_id": 1, "byte_size": 512, "artifact_kind": "table_csv"},
        {"logical_path": "air_interface/csv/ul_pusch_trials.csv", "artifact_id": 2, "byte_size": 512, "artifact_kind": "table_csv"},
    ]
    run_row = {"run_id": 88, "status_text": "completed", "config_json": "{}"}

    dl_rows = [
        {
            "RowLifecycleState": "finalized",
            "FinalizedFlag": "1",
            "PartialRowFlag": "0",
            "PrimaryTruthValueStatus": "OK",
            "SecondaryFieldGapFlag": "1",
            "SecondaryFieldGapCount": "1",
            "SecondaryFieldGapReason": "large_scale_sinr_not_finalized",
        }
    ]
    ul_rows = [
        {
            "RowLifecycleState": "partial",
            "FinalizedFlag": "0",
            "PartialRowFlag": "1",
            "PrimaryTruthValueStatus": "NOT_AVAILABLE",
            "SecondaryFieldGapFlag": "0",
            "SecondaryFieldGapCount": "0",
            "SecondaryFieldGapReason": "",
        }
    ]

    orig_load_small = dash.load_small_csv_rows
    orig_load_first = dash.load_first_available_csv_rows
    try:
        def fake_load_small(artifacts_arg, logical_path, *, max_rows=64):
            if logical_path == "air_interface/csv/dl_pdsch_trials.csv":
                return dl_rows
            if logical_path == "air_interface/csv/ul_pusch_trials.csv":
                return ul_rows
            return []

        dash.load_small_csv_rows = fake_load_small
        dash.load_first_available_csv_rows = lambda artifacts_arg, logical_paths, *, max_rows=64: []

        runtime_context = dash.extract_runtime_context(run_row, artifacts)
        lifecycle = runtime_context["raw_trial_lifecycle"]
        assert lifecycle["dl"]["status"] == "exact"
        assert lifecycle["dl"]["finalized_rows"] == 1
        assert lifecycle["dl"]["finalized_secondary_gap_rows"] == 1
        assert lifecycle["ul"]["partial_rows"] == 1
        assert any("SecondaryFieldGap" in note for note in runtime_context["notes"]), (
            "browser live payload notes must explain that secondary gaps no longer force finalized rows to partial"
        )
    finally:
        dash.load_small_csv_rows = orig_load_small
        dash.load_first_available_csv_rows = orig_load_first


if __name__ == "__main__":
    main()
