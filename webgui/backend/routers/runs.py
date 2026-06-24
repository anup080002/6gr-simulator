from __future__ import annotations

import asyncio
from datetime import datetime
from pathlib import Path
from typing import Optional

import yaml
from fastapi import APIRouter, File, HTTPException, UploadFile
from pydantic import BaseModel, Field

from services.csv_store import config_hash, read_results_for_run, resolve_repo_path, save_run_manifest
from services.db_store import get_all_runs, get_run_by_id, save_run
from services.matlab_runner import get_active_runs, get_run_status, launch_run, make_run_id, stop_run

router = APIRouter(tags=["runs"])


class RunRequest(BaseModel):
    scenario_yaml: str
    snr_db: Optional[float] = 12.0
    slot_steps: Optional[int] = 500
    dut_blocks: list[str] = Field(default_factory=list)
    run_tag_prefix: str = "webgui"
    notes: str = ""
    parent_run_id: Optional[str] = None
    execute: bool = True


@router.post("/runs")
@router.post("/run")
async def create_run(req: RunRequest):
    scenario_path = resolve_repo_path(req.scenario_yaml)
    if not scenario_path.exists():
        raise HTTPException(status_code=404, detail=f"Scenario YAML not found: {req.scenario_yaml}")
    run_id = make_run_id(req.run_tag_prefix)
    run_tag = f"{run_id}_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}"
    payload = req.model_dump()
    payload.update(
        {
            "status": "queued",
            "run_tag": run_tag,
            "scenario_yaml": str(scenario_path),
            "config_hash": config_hash(scenario_path),
        }
    )
    await save_run(run_id, run_tag, payload)
    if req.execute:
        asyncio.create_task(launch_run(run_id, str(scenario_path), run_tag, req.dut_blocks, payload))
    else:
        save_run_manifest(run_id, run_tag, payload)
    return {"run_id": run_id, "run_tag": run_tag, "status": "queued", "ws_url": f"/ws/{run_id}"}


@router.get("/runs")
async def list_runs(limit: int = 50, status: Optional[str] = None):
    return await get_all_runs(limit=limit, status_filter=status)


@router.get("/runs/active")
async def active_runs():
    return get_active_runs()


@router.get("/runs/{run_id}")
async def get_run(run_id: str):
    run = await get_run_by_id(run_id)
    if not run:
        raise HTTPException(status_code=404, detail=f"Run {run_id} not found")
    run["live_status"] = get_run_status(run_id)
    return run


@router.delete("/runs/{run_id}")
async def stop_run_endpoint(run_id: str):
    return {"stopped": stop_run(run_id)}


@router.post("/runs/upload-yaml")
async def upload_yaml(file: UploadFile = File(...)):
    content = await file.read()
    try:
        text = content.decode("utf-8")
        parsed = yaml.safe_load(text) or {}
        return {"valid": True, "config": parsed, "filename": file.filename, "bytes": len(content)}
    except Exception as exc:
        return {"valid": False, "error": str(exc), "filename": file.filename}


@router.get("/runs/{run_id}/results")
async def get_results(run_id: str):
    try:
        return read_results_for_run(run_id)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc

