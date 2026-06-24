from __future__ import annotations

import csv
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

import pandas as pd

from config import settings

WEBGUI_DATA_DIR = Path(__file__).resolve().parents[1] / "data"
RUN_MANIFEST = WEBGUI_DATA_DIR / "run_manifest.csv"


def _ensure_data_dir() -> None:
    WEBGUI_DATA_DIR.mkdir(parents=True, exist_ok=True)


def safe_records(df: pd.DataFrame) -> list[dict[str, Any]]:
    cleaned = df.where(pd.notna(df), None)
    return cleaned.to_dict("records")


def load_csv(path: Path, limit: int | None = None) -> list[dict[str, Any]]:
    if not path.exists() or not path.is_file():
        return []
    df = pd.read_csv(path)
    if limit is not None:
        df = df.tail(limit)
    return safe_records(df)


def read_last_n_rows(path: Path, n: int = 5) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    return rows[-n:]


def repo_relative(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(settings.repo_root_path)).replace("\\", "/")
    except ValueError:
        return str(path)


def resolve_repo_path(path_text: str) -> Path:
    raw = Path(path_text)
    path = raw if raw.is_absolute() else settings.repo_root_path / raw
    resolved = path.resolve()
    try:
        resolved.relative_to(settings.repo_root_path)
    except ValueError as exc:
        raise ValueError(f"Path must stay within repository root: {path_text}") from exc
    return resolved


def config_hash(path: Path) -> str:
    if not path.exists():
        return ""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _candidate_result_dirs() -> Iterable[Path]:
    root = settings.results_root_path
    if not root.exists():
        return []
    candidates: list[Path] = []
    for directory in root.rglob("*"):
        if not directory.is_dir():
            continue
        if any((directory / child).exists() for child in ("air_interface", "reports", "meta", "control")):
            candidates.append(directory)
    return candidates


def find_run_dir(run_id: str) -> Path:
    token = str(run_id).strip()
    if not token:
        raise FileNotFoundError("Empty run id")
    root = settings.results_root_path
    direct_candidates = [
        root / token,
        root / "lls" / token,
    ]
    for candidate in direct_candidates:
        if candidate.exists() and candidate.is_dir():
            return candidate
    for candidate in _candidate_result_dirs():
        if candidate.name == token or candidate.name.startswith(token) or token in candidate.name:
            return candidate
    manifest = load_run_manifest_csv(limit=10000)
    for row in manifest:
        if row.get("run_id") == token or row.get("run_tag") == token:
            run_dir = row.get("run_dir") or ""
            if run_dir:
                path = Path(run_dir)
                if path.exists():
                    return path
    raise FileNotFoundError(f"Run artifacts not found for {run_id}")


def list_result_runs(limit: int = 50) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for directory in sorted(_candidate_result_dirs(), key=lambda p: p.stat().st_mtime, reverse=True):
        rows.append(
            {
                "run_id": directory.name,
                "run_tag": directory.name,
                "status": "completed",
                "run_dir": str(directory),
                "source": "filesystem_results",
                "updated_utc": datetime.fromtimestamp(directory.stat().st_mtime, tz=timezone.utc).isoformat(),
            }
        )
        if len(rows) >= limit:
            break
    return rows


def save_run_manifest(run_id: str, run_tag: str, payload: dict[str, Any]) -> None:
    _ensure_data_dir()
    scenario_yaml = str(payload.get("scenario_yaml", ""))
    scenario_path = resolve_repo_path(scenario_yaml) if scenario_yaml else Path("")
    row = {
        "run_id": run_id,
        "run_tag": run_tag,
        "scenario_yaml": scenario_yaml,
        "scenario_id": Path(scenario_yaml).stem if scenario_yaml else "",
        "config_hash": config_hash(scenario_path) if scenario_yaml else "",
        "status": str(payload.get("status", "queued")),
        "snr_db": payload.get("snr_db", ""),
        "slot_steps": payload.get("slot_steps", ""),
        "parent_run_id": payload.get("parent_run_id", ""),
        "notes": payload.get("notes", ""),
        "run_dir": str(payload.get("run_dir", "")),
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "config_json": json.dumps(payload, sort_keys=True, default=str),
    }
    existing = load_run_manifest_csv(limit=100000)
    existing = [r for r in existing if r.get("run_id") != run_id]
    existing.insert(0, row)
    with RUN_MANIFEST.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(row.keys()))
        writer.writeheader()
        writer.writerows(existing)


def update_run_manifest(run_id: str, **updates: Any) -> None:
    if not RUN_MANIFEST.exists():
        return
    rows = load_run_manifest_csv(limit=100000)
    for row in rows:
        if row.get("run_id") == run_id:
            for key, value in updates.items():
                row[key] = value
            row["updated_utc"] = datetime.now(timezone.utc).isoformat()
    if not rows:
        return
    fieldnames = list(dict.fromkeys(k for row in rows for k in row.keys()))
    with RUN_MANIFEST.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def load_run_manifest_csv(limit: int = 50) -> list[dict[str, Any]]:
    if not RUN_MANIFEST.exists():
        return []
    with RUN_MANIFEST.open("r", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    return rows[:limit]


def read_results_for_run(run_id: str) -> dict[str, Any]:
    run_dir = find_run_dir(run_id)
    artifacts = {
        "dl_pdsch_trials": run_dir / "air_interface" / "csv" / "dl_pdsch_trials.csv",
        "ul_pusch_trials": run_dir / "air_interface" / "csv" / "ul_pusch_trials.csv",
        "pdcch_trials": run_dir / "control" / "csv" / "pdcch_trials.csv",
        "pucch_trials": run_dir / "control" / "csv" / "pucch_trials.csv",
        "runtime_stage_profile": run_dir / "reports" / "csv" / "runtime_stage_profile.csv",
        "kpi_summary": run_dir / "air_interface" / "csv" / "lls_kpi_summary.csv",
    }
    return {
        "run_id": run_id,
        "run_dir": str(run_dir),
        "available_artifacts": {
            name: repo_relative(path)
            for name, path in artifacts.items()
            if path.exists()
        },
        "tables": {name: load_csv(path, limit=500) for name, path in artifacts.items() if path.exists()},
    }

