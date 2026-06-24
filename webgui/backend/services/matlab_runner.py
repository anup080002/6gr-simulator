from __future__ import annotations

import asyncio
import re
import shutil
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from config import settings
from services.csv_store import find_run_dir, resolve_repo_path, update_run_manifest
from services.db_store import mark_run_status, persist_results_from_run
from services.file_watcher import register_run_watcher
from services.realtime_hub import publish

_runs: dict[str, dict[str, Any]] = {}


def make_run_id(prefix: str = "webgui") -> str:
    cleaned = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in prefix).strip("_") or "webgui"
    return f"{cleaned}_{uuid.uuid4().hex[:8]}"


def _matlab_string(value: str | Path) -> str:
    text = str(value).replace("\\", "/").replace("'", "''")
    return f"'{text}'"


def _matlab_executable() -> str:
    exe = settings.MATLAB_EXE.strip() or "matlab"
    if Path(exe).exists() or shutil.which(exe):
        return exe
    return exe


def get_run_status(run_id: str) -> str:
    return str(_runs.get(run_id, {}).get("status", "unknown"))


def get_active_runs() -> dict[str, dict[str, Any]]:
    return {k: {x: y for x, y in v.items() if x != "process"} for k, v in _runs.items()}


async def launch_run(
    run_id: str,
    scenario_yaml: str,
    run_tag: str,
    dut_blocks: list[str] | None = None,
    extra_params: dict[str, Any] | None = None,
) -> None:
    scenario_path = resolve_repo_path(scenario_yaml)
    register_run_watcher(run_tag, run_id)
    start = datetime.now(timezone.utc)
    _runs[run_id] = {
        "status": "running",
        "start_time": start,
        "process": None,
        "scenario_yaml": str(scenario_path),
        "run_tag": run_tag,
        "dut_blocks": dut_blocks or [],
    }
    await mark_run_status(run_id, "running")
    await publish(run_id, {"type": "status", "status": "running", "run_tag": run_tag})
    matlab_cmd = (
        "setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false); "
        f"out=run_true_lls({_matlab_string(scenario_path)}, {_matlab_string(run_tag)}, "
        f"'ResultsRoot', {_matlab_string(settings.results_root_path)}, "
        f"'RunAnalysis', {str(bool(settings.RUN_ANALYSIS_AFTER_RUN)).lower()}, "
        f"'ErrorOnOracleViolation', {str(bool(settings.ORACLE_ERROR_ON_VIOLATION)).lower()}); "
        "disp(jsonencode(struct('WebGUIResultOk',logical(out.Ok),'WebGUIStatus',string(out.Status))));"
    )
    cmd = [_matlab_executable(), "-batch", matlab_cmd]
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            cwd=str(settings.repo_root_path),
        )
    except Exception as exc:
        _runs[run_id]["status"] = "failed"
        await mark_run_status(run_id, "failed")
        await publish(run_id, {"type": "run_complete", "status": "failed", "error": str(exc), "return_code": -1})
        return
    _runs[run_id]["process"] = proc
    assert proc.stdout is not None
    async for raw in proc.stdout:
        line = raw.decode("utf-8", errors="replace").rstrip()
        if not line:
            continue
        await publish(run_id, {"type": "log", "message": line})
        await _parse_progress_line(line, run_id)
    return_code = await proc.wait()
    status = "completed" if return_code == 0 else "failed"
    _runs[run_id]["status"] = status
    wall_clock_s = (datetime.now(timezone.utc) - start).total_seconds()
    run_dir = ""
    try:
        run_dir = str(find_run_dir(run_tag))
        await persist_results_from_run(run_id, Path(run_dir))
    except Exception:
        pass
    update_run_manifest(run_id, run_dir=run_dir)
    await mark_run_status(run_id, status, wall_clock_s=wall_clock_s)
    await publish(
        run_id,
        {
            "type": "run_complete",
            "status": status,
            "return_code": return_code,
            "wall_clock_s": wall_clock_s,
            "run_dir": run_dir,
        },
    )


async def _parse_progress_line(line: str, run_id: str) -> None:
    if "[PROGRESS]" in line:
        await publish(run_id, {"type": "progress", "data": _parse_key_values(line)})
    elif "[KPI]" in line:
        await publish(run_id, {"type": "kpi_update", "raw": line, "data": _parse_key_values(line)})
    elif "[STAGE]" in line:
        await publish(run_id, {"type": "stage_update", "raw": line, "data": _parse_key_values(line)})
    elif "[ORACLE_GUARD]" in line:
        await publish(run_id, {"type": "oracle_guard", "raw": line, "status": "pass" if "PASS" in line.upper() else "fail"})


def _parse_key_values(line: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for key, value in re.findall(r"([A-Za-z0-9_]+)=([^,\s]+)", line):
        result[key] = value.rstrip(",")
    return result


def stop_run(run_id: str) -> bool:
    entry = _runs.get(run_id)
    if not entry:
        return False
    proc = entry.get("process")
    if proc and getattr(proc, "returncode", None) is None:
        try:
            proc.terminate()
        except ProcessLookupError:
            pass
    entry["status"] = "stopped"
    return True

