from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pandas as pd

from services.csv_store import load_csv, safe_records


def first_existing(run_dir: Path, candidates: list[str]) -> Path | None:
    for rel in candidates:
        path = run_dir / rel
        if path.exists():
            return path
    return None


def load_profile_frame(run_dir: Path) -> pd.DataFrame:
    path = first_existing(
        run_dir,
        [
            "analytics/csv/time_profile_analytics.csv",
            "reports/csv/time_profile_analytics.csv",
            "reports/csv/time_profile_calls.csv",
        ],
    )
    if path is None:
        return pd.DataFrame()
    df = pd.read_csv(path)
    for col in ["FunctionName", "Stage", "Status", "Elapsed_s", "EstimatedFLOPs", "EstimatedBytes", "MetadataJSON"]:
        if col not in df.columns:
            df[col] = "" if col in {"FunctionName", "Stage", "Status", "MetadataJSON"} else 0.0
    df["Elapsed_s"] = pd.to_numeric(df["Elapsed_s"], errors="coerce").fillna(0.0)
    df["EstimatedFLOPs"] = pd.to_numeric(df["EstimatedFLOPs"], errors="coerce").fillna(0.0)
    df["EstimatedBytes"] = pd.to_numeric(df["EstimatedBytes"], errors="coerce").fillna(0.0)
    return df


def parse_metadata(value: Any) -> dict[str, Any]:
    if value is None:
        return {}
    text = str(value).strip()
    if not text:
        return {}
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def aggregate_time_profile(run_dir: Path, sort_by: str = "total_time_s") -> dict[str, Any]:
    df = load_profile_frame(run_dir)
    if df.empty:
        return {"functions": [], "stages": [], "total_wall_s": 0.0, "top_5_by_time": [], "error": "No time profile data found"}
    agg = (
        df.groupby(["FunctionName", "Stage"], dropna=False)
        .agg(
            call_count=("Elapsed_s", "count"),
            total_time_s=("Elapsed_s", "sum"),
            mean_time_s=("Elapsed_s", "mean"),
            max_time_s=("Elapsed_s", "max"),
            total_flops=("EstimatedFLOPs", "sum"),
            total_bytes=("EstimatedBytes", "sum"),
        )
        .reset_index()
    )
    denom = agg["total_time_s"].sum()
    agg["flops_per_second"] = agg["total_flops"] / agg["total_time_s"].replace(0, 1e-9)
    agg["time_pct"] = 0.0 if denom <= 0 else 100.0 * agg["total_time_s"] / denom
    if sort_by not in agg.columns:
        sort_by = "total_time_s"
    agg = agg.sort_values(sort_by, ascending=False)
    stage_rows = load_csv(run_dir / "reports" / "csv" / "runtime_stage_profile.csv")
    return {
        "functions": safe_records(agg),
        "stages": stage_rows,
        "total_wall_s": float(agg["total_time_s"].sum()),
        "top_5_by_time": safe_records(agg.head(5)[["FunctionName", "total_time_s", "call_count"]]),
    }

