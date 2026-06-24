from __future__ import annotations

import datetime as dt
from pathlib import Path
from typing import Any

import pandas as pd

from models.database import Session, get_engine
from models.profile_model import FunctionProfile
from models.run_model import Run
from services.csv_store import (
    config_hash,
    list_result_runs,
    load_run_manifest_csv,
    resolve_repo_path,
    save_run_manifest,
    update_run_manifest,
)


async def save_run(run_id: str, run_tag: str, payload: dict[str, Any]) -> None:
    payload = dict(payload)
    payload.setdefault("status", "queued")
    save_run_manifest(run_id, run_tag, payload)
    if get_engine() is None or Session is None:
        return
    scenario_yaml = str(payload.get("scenario_yaml", ""))
    scenario_path = resolve_repo_path(scenario_yaml) if scenario_yaml else Path("")
    with Session() as session:
        session.merge(
            Run(
                id=run_id,
                run_tag=run_tag,
                scenario_id=Path(scenario_yaml).stem if scenario_yaml else "",
                scenario_yaml=scenario_yaml,
                config_hash=config_hash(scenario_path) if scenario_yaml else "",
                snr_db=payload.get("snr_db"),
                slot_steps=payload.get("slot_steps"),
                status=payload.get("status", "queued"),
                dut_blocks=payload.get("dut_blocks"),
                config_json=payload,
                notes=payload.get("notes"),
                parent_run_id=payload.get("parent_run_id"),
            )
        )
        session.commit()


async def mark_run_status(run_id: str, status: str, **updates: Any) -> None:
    update_run_manifest(run_id, status=status, **updates)
    if get_engine() is None or Session is None:
        return
    with Session() as session:
        row = session.get(Run, run_id)
        if row is None:
            return
        row.status = status
        if status in {"completed", "failed", "stopped"}:
            row.run_end = dt.datetime.utcnow()
        if "wall_clock_s" in updates:
            row.wall_clock_s = updates["wall_clock_s"]
        if "result_ok" in updates:
            row.result_ok = updates["result_ok"]
        session.commit()


async def get_run_by_id(run_id: str) -> dict[str, Any] | None:
    if get_engine() is not None and Session is not None:
        with Session() as session:
            row = session.get(Run, run_id)
            if row is not None:
                data = {k: v for k, v in row.__dict__.items() if not k.startswith("_")}
                return data
    for row in load_run_manifest_csv(limit=100000):
        if row.get("run_id") == run_id or row.get("run_tag") == run_id:
            return row
    return None


async def get_all_runs(limit: int = 50, status_filter: str | None = None) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if get_engine() is not None and Session is not None:
        with Session() as session:
            query = session.query(Run).order_by(Run.run_start.desc())
            if status_filter:
                query = query.filter(Run.status == status_filter)
            for row in query.limit(limit).all():
                rows.append({k: v for k, v in row.__dict__.items() if not k.startswith("_")})
    if len(rows) < limit:
        manifest_rows = load_run_manifest_csv(limit=limit)
        if status_filter:
            manifest_rows = [r for r in manifest_rows if r.get("status") == status_filter]
        seen = {str(r.get("run_id")) for r in rows}
        rows.extend([r for r in manifest_rows if str(r.get("run_id")) not in seen])
    if len(rows) < limit:
        seen = {str(r.get("run_id")) for r in rows}
        rows.extend([r for r in list_result_runs(limit=limit) if str(r.get("run_id")) not in seen])
    return rows[:limit]


async def persist_results_from_run(run_id: str, run_dir: Path) -> None:
    if get_engine() is None or Session is None:
        return
    profile_path = run_dir / "analytics" / "csv" / "time_profile_analytics.csv"
    if not profile_path.exists():
        return
    df = pd.read_csv(profile_path)
    with Session() as session:
        for _, row in df.iterrows():
            session.add(
                FunctionProfile(
                    run_id=run_id,
                    function_name=str(row.get("FunctionName", "")),
                    stage=str(row.get("Stage", "")),
                    status=str(row.get("Status", "")),
                    elapsed_s=float(row.get("Elapsed_s", 0) or 0),
                    estimated_flops=float(row.get("EstimatedFLOPs", 0) or 0),
                    estimated_bytes=float(row.get("EstimatedBytes", 0) or 0),
                    estimate_note=str(row.get("EstimateNote", "")),
                    call_utc=str(row.get("CallUTC", "")),
                    metadata_json=str(row.get("MetadataJSON", "")),
                )
            )
        session.commit()

