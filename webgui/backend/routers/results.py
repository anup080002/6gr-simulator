from __future__ import annotations

from fastapi import APIRouter, HTTPException

from services.csv_store import find_run_dir, load_csv, read_results_for_run

router = APIRouter(tags=["results"])


@router.get("/results/{run_id}")
async def all_results(run_id: str):
    try:
        return read_results_for_run(run_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/results/{run_id}/table/{table_name}")
async def result_table(run_id: str, table_name: str, limit: int = 500):
    try:
        run_dir = find_run_dir(run_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    table_map = {
        "dl": run_dir / "air_interface" / "csv" / "dl_pdsch_trials.csv",
        "ul": run_dir / "air_interface" / "csv" / "ul_pusch_trials.csv",
        "stages": run_dir / "reports" / "csv" / "runtime_stage_profile.csv",
        "implementation": run_dir / "reports" / "csv" / "lls_implementation_register.csv",
        "call_edges": run_dir / "reports" / "csv" / "runtime_function_call_edges.csv",
    }
    path = table_map.get(table_name)
    if path is None:
        raise HTTPException(status_code=404, detail=f"Unknown table: {table_name}")
    return {"run_id": run_id, "table": table_name, "rows": load_csv(path, limit=limit)}

