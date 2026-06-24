from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND = REPO_ROOT / "webgui" / "backend"
sys.path.insert(0, str(BACKEND))

from config import settings  # noqa: E402
from services.analytics_engine import aggregate_time_profile  # noqa: E402
from services.csv_store import find_run_dir, read_results_for_run  # noqa: E402
from services.oracle_guard import scan_oracle_violations  # noqa: E402


def _run_dir(root: Path) -> Path:
    run_dir = root / "lls" / "scenario_a" / "run_a"
    (run_dir / "air_interface" / "csv").mkdir(parents=True)
    (run_dir / "analytics" / "csv").mkdir(parents=True)
    return run_dir


def test_webgui_csv_store_reads_existing_artifacts_without_placeholders(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(settings, "RESULTS_ROOT", str(tmp_path))
    run_dir = _run_dir(tmp_path)
    pd.DataFrame(
        {
            "CRCPass": [True, False],
            "NoiseVarSource": ["runtime_metadata", "runtime_metadata"],
            "UsedOracleFields": ["", ""],
        }
    ).to_csv(run_dir / "air_interface" / "csv" / "dl_pdsch_trials.csv", index=False)

    assert find_run_dir("run_a") == run_dir
    payload = read_results_for_run("run_a")
    assert "dl_pdsch_trials" in payload["available_artifacts"]
    assert "ul_pusch_trials" not in payload["available_artifacts"]
    assert len(payload["tables"]["dl_pdsch_trials"]) == 2


def test_webgui_oracle_guard_rejects_configured_snr_and_perfect_tokens(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(settings, "RESULTS_ROOT", str(tmp_path))
    run_dir = _run_dir(tmp_path)
    pd.DataFrame(
        {
            "NoiseVarSource": ["runtime_metadata", "configured_snr"],
            "ChannelEstMethod": ["dmrs_nrChannelEstimate", "perfect"],
            "UsedOracleFields": ["", "scheduler_struct"],
        }
    ).to_csv(run_dir / "air_interface" / "csv" / "dl_pdsch_trials.csv", index=False)

    violations = scan_oracle_violations(run_dir)
    fields = {row["field"] for row in violations}
    assert {"NoiseVarSource", "ChannelEstMethod", "UsedOracleFields"}.issubset(fields)


def test_webgui_time_profile_aggregates_measurement_rows_only(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(settings, "RESULTS_ROOT", str(tmp_path))
    run_dir = _run_dir(tmp_path)
    empty = aggregate_time_profile(run_dir)
    assert empty["functions"] == []

    pd.DataFrame(
        {
            "FunctionName": ["sixgr.phy.dl.PDSCH_Rx", "sixgr.phy.dl.PDSCH_Rx"],
            "Stage": ["dl", "dl"],
            "Status": ["ok", "ok"],
            "Elapsed_s": [0.25, 0.75],
            "EstimatedFLOPs": [1000, 3000],
            "EstimatedBytes": [200, 400],
            "MetadataJSON": ['{"NRE": 144}', '{"NRE": 144}'],
        }
    ).to_csv(run_dir / "analytics" / "csv" / "time_profile_analytics.csv", index=False)

    profile = aggregate_time_profile(run_dir)
    assert profile["total_wall_s"] == 1.0
    assert profile["functions"][0]["call_count"] == 2
    assert profile["functions"][0]["total_flops"] == 4000
