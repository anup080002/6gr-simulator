from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    rows = [
        {
            "run_id": 70,
            "run_tag": "duplicate_tag",
            "status_text": "running",
            "status_json": '{"run_completion":"completed","result_ok":1}',
            "created_utc": "2026-04-25T15:01:52+00:00",
            "updated_utc": "2026-04-25T16:20:15+00:00",
            "profile_name": "system_level_lls",
        },
        {
            "run_id": 71,
            "run_tag": "duplicate_tag",
            "status_text": "running",
            "status_json": '{"run_completion":"failed","result_ok":0}',
            "created_utc": "2026-04-25T16:20:12+00:00",
            "updated_utc": "2026-04-25T16:21:23+00:00",
            "profile_name": "recovery_artifact_refresh",
        },
    ]

    ordered = dash.order_run_rows_for_display(rows, prefer_active=True)
    assert [row["run_id"] for row in ordered] == [70, 71], (
        "Completed truthful runs must sort ahead of later failed recovery rows for the same run tag."
    )
    preferred = dash._select_preferred_run_row(rows, prefer_active=False)
    assert preferred is not None and preferred["run_id"] == 70

    active_rows = [
        {
            "run_id": 80,
            "run_tag": "active_tag",
            "status_text": "running",
            "created_utc": "2026-04-25T18:00:00+00:00",
            "updated_utc": "2026-04-25T18:10:00+00:00",
        },
        {
            "run_id": 79,
            "run_tag": "active_tag",
            "status_text": "completed",
            "created_utc": "2026-04-25T17:00:00+00:00",
            "updated_utc": "2026-04-25T17:30:00+00:00",
        },
    ]
    preferred_active = dash._select_preferred_run_row(active_rows, prefer_active=True)
    assert preferred_active is not None and preferred_active["run_id"] == 80, (
        "Active browser polling should still prefer the running row while the run is in flight."
    )


if __name__ == "__main__":
    main()
