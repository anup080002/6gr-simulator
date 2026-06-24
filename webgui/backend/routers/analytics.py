from __future__ import annotations

from typing import Any

import pandas as pd
from fastapi import APIRouter, HTTPException

from services.analytics_engine import aggregate_time_profile
from services.csv_store import find_run_dir, load_csv, safe_records

router = APIRouter(tags=["analytics"])


@router.get("/analytics/kpi/{run_id}")
async def get_kpi(run_id: str):
    try:
        run_dir = find_run_dir(run_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {
        "kpi": load_csv(run_dir / "air_interface" / "csv" / "lls_kpi_summary.csv"),
        "lineage": load_csv(run_dir / "reports" / "csv" / "kpi_lineage_table.csv"),
    }


@router.get("/analytics/bler-curve/{run_id}")
async def get_bler_curve(run_id: str):
    run_dir = find_run_dir(run_id)
    path = run_dir / "air_interface" / "csv" / "lls_snr_sweep.csv"
    if not path.exists():
        return {"dl": [], "ul": [], "error": "No SNR sweep data"}
    df = pd.read_csv(path)
    if "direction" not in df.columns:
        return {"dl": [], "ul": [], "error": "SNR sweep table has no direction column"}
    return {
        "dl": safe_records(df[df["direction"].astype(str).str.upper() == "DL"]),
        "ul": safe_records(df[df["direction"].astype(str).str.upper() == "UL"]),
    }


@router.post("/analytics/compare")
async def compare_runs(run_ids: list[str]):
    if len(run_ids) < 2:
        return {"error": "Need at least 2 run IDs to compare"}
    if len(run_ids) > 5:
        return {"error": "Maximum 5 runs in comparison"}
    result: dict[str, Any] = {}
    for run_id in run_ids:
        run_dir = find_run_dir(run_id)
        result[run_id] = {
            "bler": await get_bler_curve(run_id),
            "kpi": load_csv(run_dir / "air_interface" / "csv" / "lls_kpi_summary.csv", limit=1),
            "top_functions": aggregate_time_profile(run_dir).get("top_5_by_time", []),
        }
    return {"run_ids": run_ids, "runs": result}


@router.get("/analytics/real-time/{run_id}")
async def get_realtime_snapshot(run_id: str):
    try:
        run_dir = find_run_dir(run_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {
        "dl": _summarize_trials(run_dir / "air_interface" / "csv" / "dl_pdsch_trials.csv"),
        "ul": _summarize_trials(run_dir / "air_interface" / "csv" / "ul_pusch_trials.csv"),
    }


def _summarize_trials(path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    df = pd.read_csv(path)
    if df.empty:
        return {"n_trials": 0}
    crc_col = "CRCPass" if "CRCPass" in df.columns else "TBCRCPass" if "TBCRCPass" in df.columns else ""
    if crc_col:
        crc = df[crc_col].astype(bool)
        bler = float((~crc).mean())
        n_pass = int(crc.sum())
    else:
        bler = None
        n_pass = 0
    return {
        "n_trials": int(len(df)),
        "n_pass": n_pass,
        "n_fail": int(len(df) - n_pass) if crc_col else None,
        "bler": bler,
        "goodput_mbps": _mean_if_present(df, ["Goodput_Mbps", "GoodputMbps", "Throughput_Mbps"]),
        "sinr_db": _mean_if_present(df, ["PostEqSINR_dB", "SINR_dB", "ReceiverHestSINR_dB"]),
    }


def _mean_if_present(df: pd.DataFrame, names: list[str]) -> float | None:
    for name in names:
        if name in df.columns:
            value = pd.to_numeric(df[name], errors="coerce").mean()
            return None if pd.isna(value) else float(value)
    return None

