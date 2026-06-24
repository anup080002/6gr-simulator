from __future__ import annotations

from typing import Any

import pandas as pd
from fastapi import APIRouter, HTTPException

from services.analytics_engine import load_profile_frame, parse_metadata
from services.csv_store import find_run_dir, safe_records

router = APIRouter(tags=["complexity"])

THRESHOLDS = {
    "flops": {"low": 1e6, "medium": 1e8, "high": 1e10},
    "bytes": {"low": 1e6, "medium": 1e8, "high": 1e9},
    "time": {"low": 0.1, "medium": 1.0, "high": 10.0},
}


@router.get("/complexity/{run_id}")
async def get_complexity(run_id: str):
    try:
        run_dir = find_run_dir(run_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    df = load_profile_frame(run_dir)
    if df.empty:
        return {"functions": [], "total_flops": 0.0, "total_bytes": 0.0, "bottleneck_function": "", "error": "No profile data"}
    agg = (
        df.groupby("FunctionName", dropna=False)
        .agg(
            calls=("Elapsed_s", "count"),
            total_s=("Elapsed_s", "sum"),
            mean_s=("Elapsed_s", "mean"),
            total_flops=("EstimatedFLOPs", "sum"),
            total_bytes=("EstimatedBytes", "sum"),
            stage=("Stage", "first"),
            metadata_json=("MetadataJSON", "first"),
        )
        .reset_index()
    )
    agg["flops_tier"] = agg["total_flops"].apply(lambda v: _tier(v, THRESHOLDS["flops"]))
    agg["bytes_tier"] = agg["total_bytes"].apply(lambda v: _tier(v, THRESHOLDS["bytes"]))
    agg["time_tier"] = agg["total_s"].apply(lambda v: _tier(v, THRESHOLDS["time"]))
    eps = 1e-12
    agg["bottleneck_score"] = (
        agg["total_s"] / (agg["total_s"].max() + eps) * 0.5
        + agg["total_flops"] / (agg["total_flops"].max() + eps) * 0.3
        + agg["total_bytes"] / (agg["total_bytes"].max() + eps) * 0.2
    )
    metadata_rows: list[dict[str, Any]] = []
    for _, row in agg.iterrows():
        meta = parse_metadata(row.get("metadata_json", ""))
        metadata_rows.append({"FunctionName": row["FunctionName"], **meta})
    if metadata_rows:
        meta_df = pd.DataFrame(metadata_rows)
        agg = agg.merge(meta_df, on="FunctionName", how="left")
    result = agg.sort_values("bottleneck_score", ascending=False)
    return {
        "functions": safe_records(result),
        "total_flops": float(agg["total_flops"].sum()),
        "total_bytes": float(agg["total_bytes"].sum()),
        "bottleneck_function": str(result.iloc[0]["FunctionName"]) if len(result) else "",
    }


def _tier(value: float, thresholds: dict[str, float]) -> str:
    if value < thresholds["low"]:
        return "low"
    if value < thresholds["medium"]:
        return "medium"
    if value < thresholds["high"]:
        return "high"
    return "extreme"

