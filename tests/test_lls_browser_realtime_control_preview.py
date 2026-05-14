from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    pdcch_rows = [
        {
            "Direction": "DL",
            "Frame": 1,
            "Slot": 7,
            "UEID": 5,
            "RNTI": 5,
            "Modulation": "not_applicable_for_active_pdcch_runtime",
            "TargetCodeRate": "not_recorded_by_active_pdcch_runtime",
            "AggregationLevel": 1,
            "DCISize_bits": 41,
            "BlindDecodeCount": 24,
            "ControlDecodeOk": 1,
            "CRCPass": 1,
            "DetectionMetric": 0.99,
            "Status": "PASS",
        }
    ]
    preview = dash.summarize_control_trial_preview_rows("pdcch_trials", pdcch_rows)
    assert len(preview) == 1
    row = preview[0]
    assert row["Direction"] == "DL"
    assert row["AggLevel"] == 1
    assert row["DCI bits"] == 41
    assert row["Decode ok"] == 1
    assert row["CRC pass"] == 1
    assert row["Metric"] == 0.99
    assert "TargetCodeRate" not in row
    assert "Modulation" not in row

    pusch_rows = [
        {
            "Direction": "UL",
            "Frame": 1,
            "Slot": 11,
            "UEID": 5,
            "RNTI": 5,
            "AllocatedPRBCount": 45,
            "NumSymbols": 14,
            "MCSIndex": 3,
            "Modulation": "16QAM",
            "TargetCodeRate": 0.33203125,
            "TBSize_bits": 10240,
            "MeasuredTrialSINR_dB": 18.25,
            "WidebandCQI": 10,
            "Status": "PASS",
        }
    ]
    data_preview = dash.summarize_data_trial_preview_rows("ul_trials", pusch_rows)
    assert len(data_preview) == 1
    data_row = data_preview[0]
    assert data_row["Direction"] == "UL"
    assert data_row["PRBs"] == 45
    assert data_row["Symbols"] == 14
    assert data_row["MCS"] == 3
    assert data_row["Modulation"] == "16QAM"
    assert data_row["TargetCodeRate"] == 0.33203125
    assert data_row["TBS bits"] == 10240
    assert data_row["Measured SINR dB"] == 18.25
    assert data_row["CQI"] == 10
    assert data_row["Status"] == "PASS"

    control_summary = dash.annotate_control_summary_row(
        {
            "UsersControlEligible": 50,
            "UsersSchedulingEligible": 50,
            "SchedulingOpportunitiesBlockedByGating": 388,
        }
    )
    assert control_summary["CurrentUsersBlockedByGating"] == 0
    assert "cumulative ue scheduling opportunities" in control_summary[
        "SchedulingOpportunitiesBlockedByGatingDefinition"
    ].lower()


if __name__ == "__main__":
    main()
