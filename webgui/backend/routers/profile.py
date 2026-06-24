from __future__ import annotations

import pandas as pd
from fastapi import APIRouter, HTTPException

from services.analytics_engine import aggregate_time_profile
from services.csv_store import find_run_dir, safe_records

router = APIRouter(tags=["profile"])


@router.get("/profile/{run_id}")
async def get_time_profile(run_id: str, sort_by: str = "total_time_s"):
    try:
        return aggregate_time_profile(find_run_dir(run_id), sort_by=sort_by)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/profile/{run_id}/call-graph")
async def get_call_graph(run_id: str, max_depth: int = 20):
    try:
        run_dir = find_run_dir(run_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    path = run_dir / "reports" / "csv" / "runtime_function_call_edges.csv"
    if not path.exists():
        return {"nodes": [], "edges": [], "error": "No call graph data"}
    df = pd.read_csv(path).head(max_depth * 10)
    nodes = set()
    edges = []
    for _, row in df.iterrows():
        caller = str(row.get("CallerFunctionName", ""))
        callee = str(row.get("CalleeFunctionName", ""))
        if not caller or not callee:
            continue
        nodes.add(caller)
        nodes.add(callee)
        edges.append(
            {
                "from": caller,
                "to": callee,
                "calls": row.get("NumCalls", 0),
                "total_time_s": row.get("TotalTime_s", 0),
            }
        )
    return {
        "nodes": [{"id": n, "label": n.split(".")[-1], "full": n} for n in sorted(nodes)],
        "edges": safe_records(pd.DataFrame(edges)) if edges else [],
    }

