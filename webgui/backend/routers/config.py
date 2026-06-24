from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from config import settings
from services.csv_store import repo_relative, resolve_repo_path

router = APIRouter(tags=["config"])


class ConfigPayload(BaseModel):
    text: str


@router.get("/config/scenarios")
async def list_scenarios() -> list[dict[str, Any]]:
    roots = [
        settings.repo_root_path / "simulator" / "configs" / "scenarios",
        settings.repo_root_path / "configs" / "scenarios",
    ]
    rows: list[dict[str, Any]] = []
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.yaml")):
            rows.append({"path": repo_relative(path), "name": path.stem, "root": repo_relative(root)})
    return rows


@router.get("/config/file")
async def read_config_file(path: str) -> dict[str, Any]:
    cfg_path = resolve_repo_path(path)
    if not cfg_path.exists():
        raise HTTPException(status_code=404, detail=f"Config not found: {path}")
    text = cfg_path.read_text(encoding="utf-8")
    try:
        parsed = yaml.safe_load(text) or {}
    except Exception as exc:
        return {"valid": False, "path": repo_relative(cfg_path), "text": text, "error": str(exc)}
    return {"valid": True, "path": repo_relative(cfg_path), "text": text, "config": parsed}


@router.post("/config/validate")
async def validate_config(payload: ConfigPayload) -> dict[str, Any]:
    try:
        parsed = yaml.safe_load(payload.text) or {}
    except Exception as exc:
        return {"valid": False, "error": str(exc)}
    if not isinstance(parsed, dict):
        return {"valid": False, "error": "Top-level YAML document must be a mapping."}
    return {"valid": True, "config": parsed}

