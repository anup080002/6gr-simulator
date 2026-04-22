#!/usr/bin/env python
from __future__ import annotations

import argparse
import copy
import csv
import email.message
import html
import io
import json
import math
import os
import re
import shutil
import socket
import secrets
import subprocess
import sys
import textwrap
import urllib.parse
import webbrowser
from http.cookies import SimpleCookie
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

import mysql.connector
from mysql.connector import pooling
import yaml

import lls_output_contract as output_contract
import lls_contract_materializer as contract_materializer
from lls_contract_aliases import (
    CONTRACT_CHART_ALIAS_PATHS,
    CONTRACT_TABLE_ALIAS_PATHS,
    OPTIONAL_6G_CHARTS,
    OPTIONAL_6G_TABLES,
)


# Preserve the active checkout path instead of collapsing through resolve(),
# which can jump to a sibling canonical path on Windows.
REPO_ROOT = Path(__file__).absolute().parent.parent
SCENARIO_ROOT = REPO_ROOT / "simulator" / "configs" / "scenarios"
MATLAB_EXE = Path(r"C:\Program Files\MATLAB\R2023b\bin\matlab.exe")
if not MATLAB_EXE.is_file():
    raise FileNotFoundError(
        f"Required MATLAB R2023b executable is missing: {MATLAB_EXE}"
    )
MYSQL_HOST = os.environ.get("MYSQL_HOST", "localhost")
MYSQL_PORT = int(os.environ.get("MYSQL_PORT", "3306"))
MYSQL_USER = os.environ.get("MYSQL_USER", "root")
MYSQL_PASSWORD = os.environ.get("MYSQL_PASSWORD", "root")
MYSQL_DATABASE = os.environ.get("MYSQL_DATABASE", "sixgr_results")
DEFAULT_DASHBOARD_HOST = os.environ.get("SIXGR_DASHBOARD_HOST", "0.0.0.0").strip() or "0.0.0.0"
try:
    DEFAULT_DASHBOARD_PORT = int(os.environ.get("SIXGR_DASHBOARD_PORT", "62906") or "62906")
except Exception:
    DEFAULT_DASHBOARD_PORT = 62906
DEFAULT_DASHBOARD_PUBLIC_HOST = os.environ.get("SIXGR_DASHBOARD_PUBLIC_HOST", "").strip()
DEFAULT_DASHBOARD_SERVER = os.environ.get("SIXGR_DASHBOARD_SERVER", "auto").strip().lower() or "auto"
try:
    DEFAULT_DASHBOARD_THREADS = max(4, int(os.environ.get("SIXGR_DASHBOARD_THREADS", "32") or "32"))
except Exception:
    DEFAULT_DASHBOARD_THREADS = 32
LEGACY_WAVEFORM_HONEST_SCENARIO = "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1000slot.yaml"
HONEST_SYSTEM_LEVEL_DEFAULT_SCENARIO = "lls_3gpp_rel20_anchor_4ghz_100mhz_system_level_honest_200ue_1000slot.yaml"
WAVEFORM_TRUTH_DEFAULT_SCENARIO = "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_50ue_14slot.yaml"
DEFAULT_SCENARIO = WAVEFORM_TRUTH_DEFAULT_SCENARIO
WAVEFORM_TRUTH_IDENTITY_TOKENS = ("waveform_honest", "waveform_truth")
BROWSER_EXECUTION_MODE_OPTIONS = ["LLS", "SLS", "E2E"]
BROWSER_EXECUTION_MODE_LABELS = {
    "LLS": "LLS",
    "SLS": "SLS",
    "E2E": "E2E",
}
BROWSER_EXECUTION_MODE_NOTES = {
    "LLS": "Browser launch is fully wired for the truthful LLS coupled-truth path in this dashboard.",
    "SLS": "SLS is separated from LLS here, but browser launch for the system-level runner is not enabled from this page in this pass.",
    "E2E": "E2E is separated from LLS here, but browser launch for the packet-stack flow is not enabled from this page in this pass.",
}
FULLY_WIRED_BROWSER_EXECUTION_MODE = "LLS"
MAX_TABLE_PREVIEW_ROWS = 200
MAX_LIVE_LOG_ROWS = 160
MAX_ACTIVITY_POINTS = 200
POLL_INTERVAL_MS = 1000
RUNTIME_LOG_DIR = REPO_ROOT / "tmp_web_runs"
PROCESSING_CHAIN_CATALOG_PATH = REPO_ROOT / "simulator" / "configs" / "defaults" / "processing_chains.yaml"
LLS_DOCS_ROOT = REPO_ROOT / "docs" / "6g_lls"
DEFAULT_MAP_CENTER = {
    "lat": 19.122164,
    "lon": 72.999217,
    "label": "Reliance Corporate Park, Ghansoli, Navi Mumbai",
    "source": "default_center",
}
SESSION_COOKIE_NAME = "sixgr_session"
SESSION_TTL = timedelta(hours=12)
DEFAULT_DASHBOARD_AUTH_MODE = os.environ.get("SIXGR_DASHBOARD_AUTH_MODE", "open").strip().lower() or "open"
if DEFAULT_DASHBOARD_AUTH_MODE not in {"open", "login"}:
    DEFAULT_DASHBOARD_AUTH_MODE = "open"
OPEN_ACCESS_PROFILE = {
    "username": "open",
    "display_name": "Open Access",
    "role": "Intranet Viewer",
    "theme": "signal",
    "bio": "Open intranet mode is active. The dashboard is reachable without a username or password.",
}
USER_PROFILES = {
    "admin": {
        "username": "admin",
        "password": "admin",
        "display_name": "Admin",
        "role": "Administrator",
        "theme": "aurora",
        "bio": "Owns the full LLS intranet console and global run controls.",
    },
    "anup": {
        "username": "anup",
        "password": "anup",
        "display_name": "Anup",
        "role": "RAN Engineer",
        "theme": "signal",
        "bio": "Focuses on PHY chains, scheduler behavior, and implementation detail review.",
    },
    "brijesh": {
        "username": "brijesh",
        "password": "brijesh",
        "display_name": "Brijesh",
        "role": "Simulation Lead",
        "theme": "vector",
        "bio": "Works on truthful 6G LLS behavior, validation, and runtime analysis.",
    },
}
ACTIVE_SESSIONS: dict[str, dict[str, Any]] = {}
DB_POOLS: dict[str, pooling.MySQLConnectionPool] = {}
LIVE_PAYLOAD_CACHE: dict[int, dict[str, Any]] = {}
CACHED_PAYLOAD_VERSION: dict[int, str] = {}
SECTION_PAYLOAD_CACHE: dict[tuple[int, str, str, str], dict[str, Any]] = {}
DB_POOL_SIZE = max(8, int(os.environ.get("MYSQL_POOL_SIZE", "32") or "32"))
STALE_RUNNING_MINUTES = max(5, int(os.environ.get("SIXGR_STALE_RUNNING_MINUTES", "15") or "15"))
PROCESS_HEARTBEAT_STALL_MINUTES = max(
    STALE_RUNNING_MINUTES + 5,
    int(os.environ.get("SIXGR_PROCESS_HEARTBEAT_STALL_MINUTES", "30") or "30"),
)
TERMINAL_STATUS_PREFIXES = ("completed", "failed", "aborted")
TERMINAL_STATUS_VALUES = {"completed", "completed_with_failures", "aborted", "failed", "stopped"}


def db_connection(database: str | None = MYSQL_DATABASE):
    pool_key = str(database or "__default__")
    kwargs: dict[str, Any] = {
        "host": MYSQL_HOST,
        "port": MYSQL_PORT,
        "user": MYSQL_USER,
        "password": MYSQL_PASSWORD,
        "autocommit": True,
        "connection_timeout": 10,
    }
    if database:
        kwargs["database"] = database
    pool = DB_POOLS.get(pool_key)
    if pool is None:
        pool_kwargs = dict(kwargs)
        pool_kwargs.update({
            "pool_size": DB_POOL_SIZE,
            "pool_reset_session": True,
        })
        pool_name = re.sub(r"[^A-Za-z0-9_]+", "_", f"sixgr_{pool_key}")[:48]
        pool = pooling.MySQLConnectionPool(pool_name=pool_name, **pool_kwargs)
        DB_POOLS[pool_key] = pool
    try:
        return pool.get_connection()
    except mysql.connector.errors.PoolError:
        # The live dashboard can issue many nested metadata reads while users
        # poll /api/run/<id>/live in parallel. Fall back to a direct
        # connection instead of failing the whole request with a 500.
        return mysql.connector.connect(**kwargs)


def clear_dashboard_caches(run_id: int | None = None) -> None:
    if run_id is None:
        LIVE_PAYLOAD_CACHE.clear()
        CACHED_PAYLOAD_VERSION.clear()
        SECTION_PAYLOAD_CACHE.clear()
        fetch_artifact_bytes.cache_clear()
        load_cached_csv_preview.cache_clear()
        load_cached_csv_rows.cache_clear()
        return
    LIVE_PAYLOAD_CACHE.pop(int(run_id), None)
    CACHED_PAYLOAD_VERSION.pop(int(run_id), None)
    for key in list(SECTION_PAYLOAD_CACHE.keys()):
        if int(key[0]) == int(run_id):
            SECTION_PAYLOAD_CACHE.pop(key, None)
    # Artifact ids are immutable per DB row, but per-run rematerialization,
    # deletion, or relaunch can invalidate cached bytes/previews that were
    # generated from an older artifact set. Clear them eagerly so the browser
    # never serves stale analytics or deleted artifact bodies after a rerun.
    fetch_artifact_bytes.cache_clear()
    load_cached_csv_preview.cache_clear()
    load_cached_csv_rows.cache_clear()


def is_terminal_status(status: Any) -> bool:
    lowered = str(status or "").strip().lower()
    if not lowered:
        return False
    return lowered in TERMINAL_STATUS_VALUES or lowered.startswith(TERMINAL_STATUS_PREFIXES)


def matlab_process_command_lines() -> list[str]:
    try:
        if os.name == "nt":
            proc = subprocess.run(
                [
                    "powershell",
                    "-NoProfile",
                    "-Command",
                    "Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'MATLAB|matlab' } | "
                    "Select-Object -ExpandProperty CommandLine",
                ],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            lines = [line.strip() for line in (proc.stdout or "").splitlines() if line.strip()]
            if lines:
                return lines
            output = (proc.stdout or "") + (proc.stderr or "")
            return [output] if ("MATLAB.exe" in output or "matlab.exe" in output) else []
        proc = subprocess.run(
            ["pgrep", "-af", "MATLAB|matlab"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        if proc.returncode != 0:
            return []
        return [line.strip() for line in (proc.stdout or "").splitlines() if line.strip()]
    except Exception:
        return []


def local_matlab_process_active() -> bool:
    return bool(matlab_process_command_lines())


def local_run_process_active(run_row: dict[str, Any]) -> bool:
    run_tag = str(run_row.get("run_tag") or "").strip().lower()
    if not run_tag:
        return local_matlab_process_active()
    token = safe_token(run_tag).lower()
    pid_path = runtime_pid_file(run_tag)
    pid_value: int | None = None
    if pid_path is not None and pid_path.is_file():
        try:
            payload = json.loads(pid_path.read_text(encoding="utf-8"))
            pid_value = int(payload.get("pid") or 0)
        except Exception:
            pid_value = None
    if pid_value and pid_value > 0:
        try:
            if os.name == "nt":
                proc = subprocess.run(
                    ["tasklist", "/FI", f"PID eq {pid_value}", "/FO", "CSV", "/NH"],
                    capture_output=True,
                    text=True,
                    timeout=5,
                    check=False,
                )
                output = (proc.stdout or "") + (proc.stderr or "")
                if f'"{pid_value}"' in output or f",{pid_value}," in output:
                    return True
            else:
                os.kill(pid_value, 0)
                return True
        except Exception:
            pass
    for command_line in matlab_process_command_lines():
        lowered = command_line.lower()
        if run_tag in lowered or token in lowered:
            return True
    return False


def infer_terminal_status_from_artifacts(run_row: dict[str, Any]) -> tuple[str, dict[str, Any]] | None:
    raw_run_id = run_row.get("run_id")
    if raw_run_id in (None, ""):
        return None
    run_id = int(raw_run_id)
    artifacts = fetch_artifacts(run_id)
    if not artifacts:
        return None
    summary_art = find_artifact_by_logical_path(artifacts, "reports/csv/scenario_summary.csv")
    manifest_art = find_artifact_by_logical_path(artifacts, "meta/scenario_manifest.json")
    artifact_manifest_art = next(
        (art for art in artifacts if str(art.get("logical_path") or "").endswith("/artifact_manifest.json")),
        None,
    )
    if summary_art is None or manifest_art is None or artifact_manifest_art is None:
        return None

    summary_row: dict[str, str] = {}
    try:
        header, rows = load_cached_csv_preview(int(summary_art["artifact_id"]), 2)
        if rows:
            summary_row = {str(k): str(v) for k, v in zip(header, rows[0])}
    except Exception:
        summary_row = {}

    manifest_payload: dict[str, Any] = {}
    try:
        manifest_payload = json.loads(fetch_artifact_bytes(int(manifest_art["artifact_id"])).decode("utf-8", errors="replace"))
        if not isinstance(manifest_payload, dict):
            manifest_payload = {}
    except Exception:
        manifest_payload = {}

    status_text = str(summary_row.get("RunCompletion") or manifest_payload.get("RunCompletion") or "").strip()
    if not status_text:
        return None
    lowered = status_text.lower()
    if not is_terminal_status(lowered):
        return None

    def _parse_bool(raw: Any) -> bool | None:
        text = str(raw if raw is not None else "").strip().lower()
        if text in {"true", "1", "yes"}:
            return True
        if text in {"false", "0", "no"}:
            return False
        return None

    def _parse_int(raw: Any) -> int | None:
        text = str(raw if raw is not None else "").strip()
        if not text:
            return None
        try:
            return int(float(text))
        except Exception:
            return None

    payload: dict[str, Any] = {
        "status": status_text,
        "run_completion": status_text,
        "stage": "dashboard_terminal_promotion_from_artifacts",
        "status_authority": str(summary_row.get("StatusAuthority") or manifest_payload.get("StatusAuthority") or "dashboard_artifact_terminal_promotion"),
        "reason": "Dashboard promoted a stale running row to the terminal scenario status because scenario_summary, scenario_manifest, and artifact_manifest were already persisted.",
        "summary_artifact": "reports/csv/scenario_summary.csv",
        "manifest_artifact": "meta/scenario_manifest.json",
        "artifact_manifest": str(artifact_manifest_art.get("logical_path") or ""),
    }
    result_ok = _parse_bool(summary_row.get("ResultOk") or summary_row.get("Ok") or manifest_payload.get("ResultOk"))
    if result_ok is not None:
        payload["result_ok"] = result_ok
    required_failures = _parse_int(summary_row.get("RequiredFailureCount") or manifest_payload.get("RequiredFailureCount"))
    if required_failures is not None:
        payload["required_failure_count"] = required_failures
    truth_ok = _parse_bool(summary_row.get("RuntimeTruthContractOk") or manifest_payload.get("RuntimeTruthContractOk"))
    if truth_ok is not None:
        payload["runtime_truth_contract_ok"] = truth_ok
    return status_text, payload


def mark_stale_running_runs() -> int:
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=STALE_RUNNING_MINUTES)
    stalled_cutoff = datetime.now(timezone.utc) - timedelta(minutes=PROCESS_HEARTBEAT_STALL_MINUTES)
    try:
        count = 0
        with db_connection() as conn:
            with conn.cursor(dictionary=True) as cur:
                cur.execute(
                    """
                    SELECT run_id, run_tag, run_folder, status_text, status_json, updated_utc
                    FROM sim_runs
                    WHERE LOWER(COALESCE(status_text,''))='running'
                    """
                )
                rows = [rowify(row) for row in cur.fetchall()]
        for row in rows:
            run_id = int(row.get("run_id"))
            try:
                if sync_runtime_log_for_run(row) > 0:
                    continue
            except Exception:
                pass
            terminal = infer_terminal_status_from_artifacts(row)
            if terminal is not None:
                status_text, payload = terminal
                with db_connection() as conn:
                    with conn.cursor() as cur:
                        cur.execute(
                            """
                            UPDATE sim_runs
                            SET status_text=%s, status_json=%s, updated_utc=UTC_TIMESTAMP()
                            WHERE run_id=%s AND LOWER(COALESCE(status_text,''))='running'
                            """,
                            (status_text, json.dumps(payload, separators=(",", ":")), run_id),
                        )
                        count += int(cur.rowcount or 0)
                continue
            updated_utc = row.get("updated_utc")
            if isinstance(updated_utc, datetime) and updated_utc.replace(tzinfo=timezone.utc) >= cutoff:
                continue
            run_process_active = local_run_process_active(row)
            if run_process_active:
                if isinstance(updated_utc, datetime) and updated_utc.replace(tzinfo=timezone.utc) < stalled_cutoff:
                    payload = {
                        "status": "stalled_running_process_no_heartbeat",
                        "reason": "Dashboard found a run-specific MATLAB process but no DB/log/artifact heartbeat within the configured stall window.",
                        "stale_running_minutes": STALE_RUNNING_MINUTES,
                        "stall_minutes": PROCESS_HEARTBEAT_STALL_MINUTES,
                        "last_updated_utc": updated_utc.isoformat(),
                    }
                    with db_connection() as conn:
                        with conn.cursor() as cur:
                            cur.execute(
                                """
                                UPDATE sim_runs
                                SET status_text=%s, status_json=%s, updated_utc=UTC_TIMESTAMP()
                                WHERE run_id=%s AND LOWER(COALESCE(status_text,''))='running'
                                """,
                                ("stalled_running_process_no_heartbeat", json.dumps(payload, separators=(",", ":")), run_id),
                            )
                            count += int(cur.rowcount or 0)
                continue
            payload = {
                "status": "aborted_stale_no_run_process",
                "reason": "Dashboard found a stale running DB row with no matching MATLAB process, no fresh heartbeat, and no terminal artifact evidence.",
                "stale_running_minutes": STALE_RUNNING_MINUTES,
                "last_updated_utc": updated_utc.isoformat() if isinstance(updated_utc, datetime) else "",
            }
            with db_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        UPDATE sim_runs
                        SET status_text=%s, status_json=%s, updated_utc=UTC_TIMESTAMP()
                        WHERE run_id=%s AND LOWER(COALESCE(status_text,''))='running'
                        """,
                        ("aborted_stale_no_run_process", json.dumps(payload, separators=(",", ":")), run_id),
                    )
                    count += int(cur.rowcount or 0)
        if count > 0:
            clear_dashboard_caches()
        return count
    except mysql.connector.Error:
        return 0


def clone_user_profile(username: str) -> dict[str, Any] | None:
    if str(username or "").strip().lower() == str(OPEN_ACCESS_PROFILE["username"]):
        return dict(OPEN_ACCESS_PROFILE)
    profile = USER_PROFILES.get(str(username or "").strip().lower())
    if profile is None:
        return None
    return dict(profile)


def auth_mode_open() -> bool:
    return DEFAULT_DASHBOARD_AUTH_MODE == "open"


def prune_sessions() -> None:
    now = datetime.now(timezone.utc)
    expired = [token for token, payload in ACTIVE_SESSIONS.items() if payload.get("expires_utc") and payload["expires_utc"] <= now]
    for token in expired:
        ACTIVE_SESSIONS.pop(token, None)


def create_session(username: str) -> str:
    prune_sessions()
    token = secrets.token_urlsafe(32)
    now = datetime.now(timezone.utc)
    ACTIVE_SESSIONS[token] = {
        "username": username,
        "created_utc": now,
        "expires_utc": now + SESSION_TTL,
        "last_seen_utc": now,
    }
    return token


def clear_session(token: str | None) -> None:
    if token:
        ACTIVE_SESSIONS.pop(token, None)


def parse_cookie_value(header_value: str | None, key: str) -> str | None:
    if not header_value:
        return None
    jar = SimpleCookie()
    try:
        jar.load(header_value)
    except Exception:
        return None
    morsel = jar.get(key)
    return None if morsel is None else morsel.value


def resolve_user_profile_from_cookie(header_value: str | None) -> tuple[str | None, dict[str, Any] | None]:
    if auth_mode_open():
        return None, dict(OPEN_ACCESS_PROFILE)
    prune_sessions()
    token = parse_cookie_value(header_value, SESSION_COOKIE_NAME)
    if not token:
        return None, None
    session = ACTIVE_SESSIONS.get(token)
    if session is None:
        return token, None
    now = datetime.now(timezone.utc)
    if session.get("expires_utc") and session["expires_utc"] <= now:
        clear_session(token)
        return token, None
    session["last_seen_utc"] = now
    session["expires_utc"] = now + SESSION_TTL
    return token, clone_user_profile(str(session.get("username") or ""))


@lru_cache(maxsize=1)
def load_processing_chain_catalog() -> dict[str, Any]:
    if not PROCESSING_CHAIN_CATALOG_PATH.is_file():
        return {}
    raw = yaml.safe_load(PROCESSING_CHAIN_CATALOG_PATH.read_text(encoding="utf-8")) or {}
    catalog = raw.get("processing_chains", {})
    return catalog if isinstance(catalog, dict) else {}


def resolve_repo_path(rel_path: str) -> Path:
    safe_rel = Path(rel_path)
    abs_path = (REPO_ROOT / safe_rel).absolute()
    repo_root = REPO_ROOT.absolute()
    if abs_path != repo_root and repo_root not in abs_path.parents:
        raise ValueError("Requested path escapes the repository root.")
    return abs_path


@lru_cache(maxsize=64)
def load_repo_markdown(rel_path: str) -> str:
    path = resolve_repo_path(rel_path)
    if not path.is_file():
        return f"# Missing Document\n\nRequested document `{rel_path}` was not found in the repository."
    return path.read_text(encoding="utf-8")


def render_inline_markdown(text: str) -> str:
    escaped = html.escape(str(text))

    def _link_repl(match: re.Match[str]) -> str:
        label = match.group(1)
        href = match.group(2)
        if href.endswith(".md") and not href.startswith(("http://", "https://", "/")):
            return f'<span class="doc-ref" title="{href}">{label}</span>'
        return f'<a href="{href}" target="_blank" rel="noopener noreferrer">{label}</a>'

    escaped = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", _link_repl, escaped)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
    return escaped


def split_markdown_table_row(line: str) -> list[str]:
    text = line.strip()
    if text.startswith("|"):
        text = text[1:]
    if text.endswith("|"):
        text = text[:-1]
    return [cell.strip() for cell in text.split("|")]


def is_markdown_table_separator(line: str) -> bool:
    cells = split_markdown_table_row(line)
    if not cells:
        return False
    for cell in cells:
        token = cell.replace(" ", "")
        if not token:
            continue
        if re.fullmatch(r":?-{3,}:?", token) is None:
            return False
    return True


def render_markdown_document(text: str, *, css_class: str = "doc-markdown") -> str:
    lines = str(text).splitlines()
    out: list[str] = [f'<div class="{css_class}">']
    paragraph: list[str] = []
    list_type = ""
    list_items: list[str] = []
    in_code = False
    code_lang = ""
    code_lines: list[str] = []
    i = 0

    def flush_paragraph() -> None:
        nonlocal paragraph
        if paragraph:
            out.append(f"<p>{render_inline_markdown(' '.join(paragraph))}</p>")
            paragraph = []

    def flush_list() -> None:
        nonlocal list_type, list_items
        if list_type and list_items:
            inner = "".join(f"<li>{render_inline_markdown(item)}</li>" for item in list_items)
            out.append(f"<{list_type}>{inner}</{list_type}>")
        list_type = ""
        list_items = []

    def flush_code() -> None:
        nonlocal in_code, code_lang, code_lines
        if in_code:
            language_class = f' class="language-{html.escape(code_lang)}"' if code_lang else ""
            code_html = html.escape("\n".join(code_lines))
            out.append(
                f'<div class="doc-code-wrap"><div class="doc-code-label">{html.escape(code_lang or "text")}</div>'
                f'<pre><code{language_class}>{code_html}</code></pre></div>'
            )
        in_code = False
        code_lang = ""
        code_lines = []

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if in_code:
            if stripped.startswith("```"):
                flush_code()
            else:
                code_lines.append(line)
            i += 1
            continue

        if stripped.startswith("```"):
            flush_paragraph()
            flush_list()
            in_code = True
            code_lang = stripped[3:].strip()
            code_lines = []
            i += 1
            continue

        if stripped == "":
            flush_paragraph()
            flush_list()
            i += 1
            continue

        if "|" in stripped and (i + 1) < len(lines) and is_markdown_table_separator(lines[i + 1]):
            flush_paragraph()
            flush_list()
            header = split_markdown_table_row(lines[i])
            rows: list[list[str]] = []
            i += 2
            while i < len(lines):
                candidate = lines[i].strip()
                if not candidate or "|" not in candidate:
                    break
                rows.append(split_markdown_table_row(lines[i]))
                i += 1
            header_html = "".join(f"<th>{render_inline_markdown(cell)}</th>" for cell in header)
            row_html = []
            for row in rows:
                padded = row + [""] * max(0, len(header) - len(row))
                row_html.append(
                    "<tr>" + "".join(f"<td>{render_inline_markdown(cell)}</td>" for cell in padded[: len(header)]) + "</tr>"
                )
            out.append(
                '<div class="table-scroll"><table class="doc-table"><thead><tr>'
                + header_html
                + "</tr></thead><tbody>"
                + "".join(row_html)
                + "</tbody></table></div>"
            )
            continue

        heading_match = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if heading_match:
            flush_paragraph()
            flush_list()
            level = min(4, len(heading_match.group(1)))
            out.append(f"<h{level}>{render_inline_markdown(heading_match.group(2))}</h{level}>")
            i += 1
            continue

        unordered_match = re.match(r"^[-*]\s+(.*)$", stripped)
        if unordered_match:
            flush_paragraph()
            if list_type not in {"", "ul"}:
                flush_list()
            list_type = "ul"
            list_items.append(unordered_match.group(1))
            i += 1
            continue

        ordered_match = re.match(r"^\d+\.\s+(.*)$", stripped)
        if ordered_match:
            flush_paragraph()
            if list_type not in {"", "ol"}:
                flush_list()
            list_type = "ol"
            list_items.append(ordered_match.group(1))
            i += 1
            continue

        flush_list()
        paragraph.append(stripped)
        i += 1

    flush_paragraph()
    flush_list()
    flush_code()
    out.append("</div>")
    return "".join(out)


def extract_source_excerpt(rel_path: str, anchors: list[str], *, radius: int = 4) -> list[tuple[str, str]]:
    path = resolve_repo_path(rel_path)
    if not path.is_file():
        return []
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    snippets: list[tuple[str, str]] = []
    used_ranges: list[tuple[int, int]] = []
    for anchor in anchors:
        anchor_lower = anchor.lower()
        match_index = next((idx for idx, line in enumerate(lines) if anchor_lower in line.lower()), None)
        if match_index is None:
            continue
        start = max(0, match_index - radius)
        stop = min(len(lines), match_index + radius + 1)
        if any(not (stop <= r0 or start >= r1) for r0, r1 in used_ranges):
            continue
        used_ranges.append((start, stop))
        block = "\n".join(f"{idx + 1:4d}: {lines[idx]}" for idx in range(start, stop))
        snippets.append((anchor, block))
    return snippets


def build_source_excerpt_card(excerpts: list[tuple[str, list[str]]]) -> str:
    cards: list[str] = []
    for rel_path, anchors in excerpts:
        snippet_blocks = extract_source_excerpt(rel_path, anchors)
        if not snippet_blocks:
            continue
        content = []
        for anchor, snippet in snippet_blocks:
            content.append(
                f'<div class="doc-code-wrap"><div class="doc-code-label">{html.escape(Path(rel_path).name)} | {html.escape(anchor)}</div>'
                f'<pre><code>{html.escape(snippet)}</code></pre></div>'
            )
        cards.append(
            build_doc_card(
                f"Exact Source Excerpts | {Path(rel_path).name}",
                "".join(content),
                search_text=f"{rel_path} {' '.join(anchors)}",
                extra_class="doc-card-wide",
            )
        )
    return "".join(cards)


def build_doc_card(title: str, body: str, *, search_text: str = "", extra_class: str = "") -> str:
    classes = "doc-card"
    if extra_class:
        classes += f" {extra_class}"
    search_attr = html.escape((search_text or f"{title} {body}").lower())
    return (
        f'<section class="{classes}" data-doc-search="{search_attr}">'
        f"<h3>{html.escape(title)}</h3>{body}</section>"
    )


def build_chain_explorer_markup() -> str:
    catalog = load_processing_chain_catalog()
    if not catalog:
        return '<p class="muted">No processing-chain catalog is available in this repository.</p>'

    buttons: list[str] = []
    panels: list[str] = []
    for idx, (chain_id, chain) in enumerate(catalog.items()):
        chain_label = str(chain.get("chain_label") or humanize_key(chain_id))
        active = " active" if idx == 0 else ""
        buttons.append(
            f'<button type="button" class="subtab-button{active}" data-chain-button="{html.escape(chain_id)}">'
            f"{html.escape(chain_label)}</button>"
        )
        ordered_blocks = chain.get("ordered_blocks") or []
        rows = []
        for block in ordered_blocks:
            config_paths = "<br>".join(html.escape(str(item)) for item in block.get("config_paths", []))
            outputs = "<br>".join(html.escape(str(item)) for item in block.get("outputs", []))
            rows.append(
                "<tr>"
                f"<td>{html.escape(str(block.get('order', '')))}</td>"
                f"<td><strong>{html.escape(str(block.get('block_name', '')))}</strong><div class=\"mini-note\">{html.escape(str(block.get('block_id', '')))}</div></td>"
                f"<td>{html.escape(str(block.get('baseline_or_candidate_tag', '')))}</td>"
                f"<td>{config_paths}</td>"
                f"<td>{outputs}</td>"
                f"<td>{'Optional' if bool(block.get('optional_flag', False)) else 'Required'}</td>"
                f"<td>{html.escape(str(block.get('notes', '')))}</td>"
                "</tr>"
            )
        pills = "".join(
            [
                f'<span class="pill">{html.escape(str(chain.get("baseline_or_candidate_tag") or "unclassified"))}</span>',
                f'<span class="pill">Exact Order: {"Yes" if bool(chain.get("exact_order_locked", False)) else "No"}</span>',
                f'<span class="pill">Blocks: {len(ordered_blocks)}</span>',
            ]
        )
        kpis = "".join(f"<li>{html.escape(str(item))}</li>" for item in (chain.get("kpi_bindings") or []))
        artifacts = "".join(f"<li>{html.escape(str(item))}</li>" for item in (chain.get("artifact_bindings") or []))
        panel_body = (
            f'<div class="doc-callout">{pills}<p class="muted">{html.escape(str(chain.get("notes") or ""))}</p></div>'
            '<div class="two-col">'
            + build_doc_card(
                "KPI Bindings",
                f"<ul>{kpis or '<li>No KPI bindings declared.</li>'}</ul>",
                search_text=f"{chain_id} {' '.join(chain.get('kpi_bindings') or [])}",
                extra_class="doc-card-tight",
            )
            + build_doc_card(
                "Artifact Bindings",
                f"<ul>{artifacts or '<li>No artifact bindings declared.</li>'}</ul>",
                search_text=f"{chain_id} {' '.join(chain.get('artifact_bindings') or [])}",
                extra_class="doc-card-tight",
            )
            + "</div>"
            + '<div class="table-scroll"><table class="doc-table"><thead><tr>'
            "<th>Order</th><th>Block</th><th>Class</th><th>Config Paths</th><th>Outputs</th><th>Flag</th><th>Notes</th>"
            + "</tr></thead><tbody>"
            + "".join(rows)
            + "</tbody></table></div>"
        )
        panels.append(
            f'<div class="subtab-panel{" active" if idx == 0 else ""}" data-chain-panel="{html.escape(chain_id)}" '
            f'data-doc-search="{html.escape((chain_label + " " + json.dumps(chain, default=default_json)).lower())}">'
            f"<h3>{html.escape(chain_label)}</h3>{panel_body}</div>"
        )

    return (
        '<div class="chain-layout">'
        f'<div class="chain-nav panel-scroll-x"><div class="tabular-tabs">{"".join(buttons)}</div></div>'
        f'<div class="chain-detail">{"".join(panels)}</div>'
        "</div>"
    )


def build_calculation_markup() -> str:
    cards = [
        {
            "title": "Configuration Resolution",
            "body": (
                "<p>The front door only accepts config path, output root, and optional run tag. "
                "Everything else is resolved through layered YAML inheritance into one validated scenario object.</p>"
                "<pre><code>resolvedConfig = merge(global, release, band, waveform, channel, MIMO, RS, AI, impairments, scenario, sweep)</code></pre>"
                "<p class=\"mini-note\">Primary surfaces: <code>run_6g_phy_lls_single.m</code>, "
                "<code>+sixgr/+lls6g/+config/loadScenarioConfig.m</code>, "
                "<code>+sixgr/+lls6g/+config/validateScenarioConfig.m</code>, "
                "<code>+sixgr/+lls6g/buildInternalConfig.m</code>.</p>"
            ),
        },
        {
            "title": "Propagation and Large-Scale State",
            "body": (
                "<p>The simulator caches geometry-driven large-scale terms instead of opportunistically resampling them. "
                "That cache carries distances, LOS state, shadowing, pathloss, beam choice, link power, and RSRP.</p>"
                "<pre><code>rxPower_dBm = txPower_dBm + beamGain_dB - pathloss_dB - shadow_dB</code></pre>"
                "<p class=\"mini-note\">Primary surfaces: <code>+sixgr/+system/SystemLevelRunner.m</code>, "
                "<code>+sixgr/+system/buildLargeScaleStateCache.m</code>, "
                "<code>+sixgr/+channel/TR38901Plus.m</code>.</p>"
            ),
        },
        {
            "title": "Desired / Interference / Noise SINR",
            "body": (
                "<p>The default system path now computes explicit desired power, non-serving interference power from active cells, "
                "and thermal noise plus receiver NF. The older margin shortcut is kept only as an explicit legacy calibration mode.</p>"
                "<pre><code>noise_dBm = -174 + 10*log10(BW_Hz) + NF_dB\n"
                "SINR_dB = 10*log10(P_desired_mW / (P_interference_mW + P_noise_mW))</code></pre>"
                "<p class=\"mini-note\">Primary surfaces: <code>+sixgr/+system/SystemLevelRunner.m</code> local explicit SINR helpers.</p>"
            ),
        },
        {
            "title": "Wideband CQI to NR AMC",
            "body": (
                "<p>Wideband CQI is resolved from the same desired/interference/noise SINR path. "
                "CQI table selection is configuration-driven, and AMC resolution is table-driven instead of scalar shortcuts.</p>"
                "<pre><code>CQI --&gt; resolveCQIProfile(table1|table2) --&gt; resolveMCSFromCQI --&gt; resolveMCSProfile</code></pre>"
                "<p class=\"mini-note\">Primary surfaces: <code>+sixgr/+system/SystemLevelRunner.m</code>, "
                "<code>+sixgr/+link/amcFromCQI.m</code>, "
                "<code>+sixgr/+link/resolveCQIProfile.m</code>, "
                "<code>+sixgr/+link/resolveMCSProfile.m</code>.</p>"
            ),
        },
        {
            "title": "NR TBS and Queue-Limited Grants",
            "body": (
                "<p>Scheduler grant construction uses the actual NR TBS path in strict / Vienna-equivalent modes. "
                "New-data grants are queue-limited at construction time, while retransmissions preserve HARQ semantics.</p>"
                "<pre><code>N_info = N_RE * Qm * R * layers\n"
                "TBS = nrTBS(... faithful path in strict mode)\n"
                "grant.TBSBits = min(rawEstimatedTBSBits, pendingQueueBits)</code></pre>"
                "<p class=\"mini-note\">Primary surfaces: <code>+sixgr/+l2/+mac/SchedulerBase.m</code>, "
                "<code>+sixgr/+l2/+mac/SchedulerRR.m</code>, "
                "<code>+sixgr/+l2/+mac/SchedulerPF.m</code>.</p>"
            ),
        },
        {
            "title": "DL and UL Waveform Chains",
            "body": (
                "<p>The exact TX/RX order is declared in the processing-chain catalog, then executed by the waveform truth path. "
                "That includes PDSCH, PUSCH, PRACH, PDCCH, RS generation, CE, equalization, decoding, HARQ, and KPI capture.</p>"
                "<p class=\"mini-note\">Primary surfaces: <code>simulator/configs/defaults/processing_chains.yaml</code>, "
                "<code>+sixgr/+truth/runWaveformLinkBundle.m</code>, "
                "<code>+sixgr/+phy/*</code>, <code>+sixgr/+link/*</code>.</p>"
            ),
        },
        {
            "title": "Determinism, Truth, and Result Integrity",
            "body": (
                "<p>Strict validation records config, seed, environment, run scope, and completion status. "
                "Truth guards prevent proxy or fallback artifacts from being mislabeled as primary truth outputs.</p>"
                "<p class=\"mini-note\">Primary surfaces: <code>+sixgr/+report/checkResultIntegrity.m</code>, "
                "<code>+sixgr/+truth/scanTruthArtifacts.m</code>, "
                "<code>+sixgr/+link/enforcePrimaryLinkExportIntegrity.m</code>.</p>"
            ),
        },
        {
            "title": "Realtime Browser and Database Flow",
            "body": (
                "<p>The intranet console does not stream via Kafka. MATLAB writes logs and artifacts directly to MySQL, "
                "and the browser polls live JSON endpoints for tables, analytics, logs, and map layers.</p>"
                "<pre><code>MATLAB run --&gt; sim_runs / sim_run_logs / sim_artifacts --&gt; browser /api/run/&lt;id&gt;/live</code></pre>"
                "<p class=\"mini-note\">Primary surfaces: <code>+sixgr/+db/artifactStore.m</code>, "
                "<code>+sixgr/+lls6g/+runners/runSingle.m</code>, "
                "<code>apps/lls_web_dashboard.py</code>.</p>"
            ),
        },
    ]
    return '<div class="doc-grid">' + "".join(
        build_doc_card(item["title"], item["body"], search_text=item["title"] + " " + item["body"])
        for item in cards
    ) + "</div>"


def build_source_map_markup() -> str:
    sources = [
        ("Front Door CLI", "run_6g_phy_lls_single.m", "Single-scenario entry point that hands control to the config-driven LLS runner."),
        ("Runner Dispatch", "+sixgr/+lls6g/+runners/runSingle.m", "Loads config, validates it, chooses result layout, dispatches runner profile, and publishes artifacts."),
        ("Config Translation", "+sixgr/+lls6g/buildInternalConfig.m", "Maps resolved scenario config into the internal simulator cfg without hidden behavioral defaults."),
        ("Config Load / Validation", "+sixgr/+lls6g/+config/loadScenarioConfig.m", "Reads layered YAML/JSON, resolves inheritance, and builds canonical scenario objects."),
        ("Scenario Validation", "+sixgr/+lls6g/+config/validateScenarioConfig.m", "Structural and compatibility validation with fail-fast errors."),
        ("Waveform Truth Bundle", "+sixgr/+truth/runWaveformLinkBundle.m", "Main waveform LLS execution surface for DL/UL/control/RS bundles."),
        ("System Power and SINR", "+sixgr/+system/SystemLevelRunner.m", "Shared large-scale state, attach / HO measurements, interference sums, SINR traces, and system analytics."),
        ("AMC and Tables", "+sixgr/+link/amcFromCQI.m", "CQI-to-AMC handoff using selected CQI and MCS tables."),
        ("MCS Profiles", "+sixgr/+link/resolveMCSProfile.m", "NR MCS table resolution for modulation order, code rate, and spectral efficiency."),
        ("Scheduler Base", "+sixgr/+l2/+mac/SchedulerBase.m", "AMC selection, TBS estimation, queue-limited grant planning, HARQ-aware schedule helpers."),
        ("Database Artifact Store", "+sixgr/+db/artifactStore.m", "Writes tables, images, logs, and metadata to MySQL-backed artifact storage."),
        ("Realtime Dashboard", "apps/lls_web_dashboard.py", "Intranet browser, live polling APIs, results pages, analytics, map, and documentation console."),
        ("Processing Chain Catalog", "simulator/configs/defaults/processing_chains.yaml", "Normative machine-readable chain order, bindings, and artifact expectations."),
        ("Schema Catalogs", "simulator/configs/schema", "Parameter catalogs, allowed values, and validation policy."),
    ]
    cards = []
    for title, path, desc in sources:
        body = (
            f'<p class="mini-note"><code>{html.escape(path)}</code></p>'
            f"<p>{html.escape(desc)}</p>"
        )
        cards.append(build_doc_card(title, body, search_text=f"{title} {path} {desc}"))
    return '<div class="doc-grid">' + "".join(cards) + "</div>"


def build_vertical_flow_svg(title: str, steps: list[str]) -> str:
    box_width = 760
    box_height = 44
    gap = 18
    margin = 22
    total_height = margin * 2 + len(steps) * box_height + max(0, len(steps) - 1) * gap + 28
    svg_parts: list[str] = [
        f'<svg class="flow-svg" viewBox="0 0 820 {total_height}" role="img" aria-label="{html.escape(title)} flow">'
    ]
    svg_parts.append('<defs><marker id="arrowhead" markerWidth="10" markerHeight="7" refX="8" refY="3.5" orient="auto">'
                     '<polygon points="0 0, 10 3.5, 0 7" fill="#0d5c63" /></marker></defs>')
    svg_parts.append(
        f'<text x="30" y="26" fill="#1d2a2f" font-size="18" font-weight="700">{html.escape(title)}</text>'
    )
    x = 30
    y = margin + 12
    for idx, step in enumerate(steps):
        svg_parts.append(
            f'<rect x="{x}" y="{y}" rx="14" ry="14" width="{box_width}" height="{box_height}" '
            'fill="#fffdf8" stroke="#0d5c63" stroke-width="1.5" />'
        )
        svg_parts.append(
            f'<text x="{x + 18}" y="{y + 27}" fill="#1d2a2f" font-size="13">{html.escape(step)}</text>'
        )
        if idx < len(steps) - 1:
            y1 = y + box_height
            y2 = y + box_height + gap
            svg_parts.append(
                f'<line x1="{x + box_width / 2:.1f}" y1="{y1}" x2="{x + box_width / 2:.1f}" y2="{y2}" '
                'stroke="#0d5c63" stroke-width="2" marker-end="url(#arrowhead)" />'
            )
        y += box_height + gap
    svg_parts.append("</svg>")
    return "".join(svg_parts)


def build_file_refs_markup(paths: list[str]) -> str:
    return "<ul>" + "".join(f"<li><code>{html.escape(path)}</code></li>" for path in paths) + "</ul>"


def build_formula_cards(formulas: list[tuple[str, str]]) -> str:
    cards = []
    for title, expression in formulas:
        cards.append(
            '<div class="doc-formula">'
            f'<div class="doc-formula-title">{html.escape(title)}</div>'
            f"<pre><code>{html.escape(expression)}</code></pre>"
            "</div>"
        )
    return "".join(cards)


def build_exact_algorithm_markup() -> str:
    modules = [
        {
            "id": "mac-scheduler",
            "label": "MAC Scheduler",
            "search": "mac scheduler pf rr grant dci queue limited harq riv time domain assignment",
            "files": [
                "+sixgr/+l2/+mac/SchedulerBase.m",
                "+sixgr/+l2/+mac/SchedulerRR.m",
                "+sixgr/+l2/+mac/SchedulerPF.m",
            ],
            "summary": (
                "<p>The scheduler path is split into AMC selection, TBS estimation, queue-limited new-data planning, "
                "HARQ-aware grant construction, PF or RR prioritization, and compact DCI bitfield packing. "
                "The implementation is table-driven where possible and uses explicit queue-limited transport blocks instead of oversized grants.</p>"
            ),
            "flow": [
                "Read UE state: CQI, RI, buffers, explicit overrides, HARQ state",
                "Select AMC mode: fixed MCS, fixed modulation/TCR, or CQI-table-driven",
                "Estimate TBS using faithful nrTBS path or approximate path depending on strict mode",
                "If new-data TBS exceeds queue, scan PRB prefixes and candidate MCS profiles",
                "Choose best valid queue-limited plan, then emit grant + HARQ fields",
                "Pack DCI fields with RIV, TDA, MCS, NDI, RV, HARQ ID, DAI, K1, K2",
            ],
            "maths": [
                ("PF metric", "inst_bps = TBSBits / SlotDuration_s\nmetric = inst_bps / max(AvgThroughput_bps, 1)"),
                ("RIV mapping", "if (L - 1) <= floor(NRB/2)\n  RIV = NRB * (L - 1) + RBstart\nelse\n  RIV = NRB * (NRB - L + 1) + (NRB - 1 - RBstart)"),
                ("Queue-limited search", "for nUse = 1 : numel(PRBSet)\n  for each candidate AMC profile\n    TBS = estimateTBS(..., nUse, ...)\n    keep best TBSBytes <= queueBytes\n  end\nend"),
            ],
            "details": [
                "PF metric is implemented as instantaneous rate over exponential average throughput.",
                "Fixed-MCS, fixed-modulation, and CQI-table modes are separated in selectAMC().",
                "Queue-limited plans are built before transmission, not clipped only after decode.",
                "For CQI-table mode, candidate backoff walks downward from the selected MCS index to zero.",
            ],
            "excerpts": [
                ("+sixgr/+l2/+mac/SchedulerBase.m", ["pfMetric(obj, ue, tbsBits)", "metric = inst / max(avg, 1);", "38.214-style RIV mapping.", "localFindQueueLimitedPlan"]),
            ],
            "plantuml": """@startuml
start
:Read UE CQI / RI / buffers / HARQ state;
if (Explicit MCS index?) then (yes)
  :Use fixed_mcs path;
elseif (Explicit modulation or code rate?) then (yes)
  :Use fixed_modulation path;
else (no)
  :Resolve CQI table;
  :Resolve MCS from CQI;
endif
:Estimate TBS;
if (TBS > queue?) then (yes)
  :Scan PRB prefixes and candidate MCS profiles;
  :Pick best queue-limited plan;
endif
:Build DCI bitfield (RIV, TDA, MCS, NDI, RV, HARQ ID);
stop
@enduml""",
        },
        {
            "id": "sinr-cqi-amc",
            "label": "SINR -> CQI -> AMC",
            "search": "sinr cqi amc interference noise spectral efficiency wideband table1 table2",
            "files": [
                "+sixgr/+system/SystemLevelRunner.m",
                "+sixgr/+link/resolveWidebandCQI.m",
                "+sixgr/+link/resolveCQIProfile.m",
                "+sixgr/+link/resolveMCSFromCQI.m",
                "+sixgr/+link/amcFromCQI.m",
                "+sixgr/+link/resolveMCSProfile.m",
            ],
            "summary": (
                "<p>The current implementation computes explicit desired / interference / noise powers in system mode, "
                "then converts that same SINR state into wideband CQI and provisional AMC using selected NR CQI and MCS tables. "
                "The legacy interference-margin shortcut still exists only as an explicit non-default calibration mode.</p>"
            ),
            "flow": [
                "Build desired DL/UL power from serving-link state",
                "Sum active non-serving DL cells or UL grants in mW",
                "Compute thermal noise from PRBs, SCS, and NF",
                "Compute SINR in linear power domain and convert to dB",
                "Apply wideband SINR margin, map to spectral efficiency log2(1+SINR)",
                "Choose highest CQI row not exceeding effective spectral efficiency, then resolve AMC/MCS",
            ],
            "maths": [
                ("Noise power", "BW_Hz = NPRB * 12 * SCS_kHz * 1e3\nNoise_dBm = -174 + 10*log10(BW_Hz) + NF_dB"),
                ("Explicit SINR", "Pdes_mW = 10^(Desired_dBm/10)\nPint_mW = sum_k 10^(Interferer_k_dBm/10)\nPnoise_mW = 10^(Noise_dBm/10)\nSINR_dB = 10*log10(Pdes_mW / (Pint_mW + Pnoise_mW))"),
                ("Wideband CQI SE", "SE_eff = log2(1 + 10^((SINR_dB - widebandSINRMargin_dB)/10))\nCQI = max { i : SE_table(i) <= SE_eff }"),
                ("CQI to provisional MCS", "Choose highest valid MCS where Qm_MCS <= Qm_CQI and SE_MCS <= SE_CQI"),
            ],
            "details": [
                "DL interference is summed over active non-serving cells; UL interference is summed from active transmitting UEs mapped into the serving cell receiver.",
                "Wideband CQI uses the same SINR model as the scheduler input, so CQI and grants stay coupled to the actual interference state.",
                "CQI table choice is config-driven per direction, supporting at least NR Table 1 and Table 2.",
                "MCS profile resolution returns modulation order, target code rate, and spectral efficiency from the selected table.",
            ],
            "excerpts": [
                ("+sixgr/+system/SystemLevelRunner.m", ["Noise_dBm", "WidebandSINR_dB", "resolveWidebandCQI", "log2(1 + 10.^(double(sinr_dB)/10))"]),
                ("+sixgr/+link/resolveWidebandCQI.m", ["widebandSE = localSINRToSpectralEfficiency", "spectralEfficiency = log2(1 + sinrLin)"]),
                ("+sixgr/+link/amcFromCQI.m", ["MCSProfile", "TargetCodeRate"]),
            ],
            "plantuml": """@startuml
start
:Desired power from serving link-state cache;
:Interference power from active non-serving transmitters;
:Noise power from BW and NF;
:Compute linear SINR and convert to dB;
:Apply wideband SINR margin;
:SE = log2(1 + SINR_lin);
:Choose CQI row from selected table;
:Resolve MCS from CQI and MCS table;
stop
@enduml""",
        },
        {
            "id": "tbs-coding",
            "label": "TBS / Coding / LDPC",
            "search": "tbs coding ldpc rate recovery decode desegment crc strict nrTBS",
            "files": [
                "+sixgr/+l2/+mac/SchedulerBase.m",
                "+sixgr/+phy/+phycode/rateRecoverLDPC.m",
                "+sixgr/+phy/+phycode/ldpcDecode.m",
                "+sixgr/+phy/+tb/desegmentLDPC.m",
                "+sixgr/+phy/+tb/checkCRC.m",
            ],
            "summary": (
                "<p>The simulator uses a faithful NR-style TBS path in strict or Vienna-equivalent modes, with actual NRE-per-PRB extraction from the scheduled allocation. "
                "Decode-side processing then applies LDPC rate recovery, LDPC decoding, code-block desegmentation, and transport-block CRC checking.</p>"
            ),
            "flow": [
                "Estimate NRE per PRB from actual PDSCH/PUSCH allocation when faithful mode is active",
                "Call nrTBS(modulation, layers, nPRB, nrePerPRB, targetCodeRate, xOverhead)",
                "Apply queue-limited new-data grant search if needed",
                "On RX, call nrRateRecoverLDPC on codeword LLRs",
                "Decode each code block with nrLDPCDecode or batch MEX kernel",
                "Desegment decoded CBs and remove / verify TB CRC",
            ],
            "maths": [
                ("Fast NRE approximation", "NREPerPRB_approx = 12 * nSym"),
                ("Faithful TBS path", "TBSBits = nrTBS(Modulation, NumLayers, NPRB, NREPerPRB, TargetCodeRate, xOverhead)"),
                ("Approximate TBS fallback", "if fast path enabled:\n  eff = Qm * TargetCodeRate\n  TBSBits = floor(NPRB * NREPerPRB * eff)\n  TBSBits = 8 * floor(TBSBits / 8)"),
                ("TB + CRC length", "B = TransportBlockSize + TB_CRCLength"),
            ],
            "details": [
                "Strict mode disables rough fallback when faithful nrTBS evaluation fails.",
                "The scheduler memoizes repeated TBS queries by direction, modulation, layers, PRBs, symbols, and code rate.",
                "Rate recovery exposes filler-bit behavior from nrRateRecoverLDPC, which is expected by nrLDPCDecode.",
                "Decode can use parallel MATLAB workers or the LDPC batch MEX kernel when enabled.",
            ],
            "excerpts": [
                ("+sixgr/+l2/+mac/SchedulerBase.m", ["Estimate TB size using nrTBS", "nrTBS(char(modStr)", "Strict mode forbids rough TBS fallback"]),
                ("+sixgr/+phy/+dl/PDSCH_Rx.m", ["trBlkSize = nrTBS", "nrPDSCHDecode"]),
                ("+sixgr/+phy/+ul/PUSCH_Rx.m", ["trBlkSize = nrTBS", "nrPUSCHDecode"]),
            ],
            "plantuml": """@startuml
start
:Get modulation, layers, PRBs, symbol allocation, code rate;
if (Strict / faithful mode?) then (yes)
  :Extract NRE per PRB from actual allocation;
  :Call nrTBS(...);
else (no)
  :Use 12*nSym fast NRE approximation;
  :Approximate TBS;
endif
:Rate recover LDPC;
:Decode each code block;
:Desegment code blocks;
:Check TB CRC;
stop
@enduml""",
        },
        {
            "id": "ofdm-waveform",
            "label": "OFDM / Waveform",
            "search": "ofdm waveform fft ifft nrOFDMModulate nrOFDMDemodulate transform precoding",
            "files": [
                "+sixgr/+phy/+waveform/ofdmModulate.m",
                "+sixgr/+phy/+waveform/ofdmDemodulate.m",
                "+sixgr/+phy/+waveform/transformPrecode.m",
                "+sixgr/+phy/+waveform/transformDeprecode.m",
            ],
            "summary": (
                "<p>The waveform wrappers are intentionally thin. They normalize shapes, call the 5G Toolbox OFDM or transform-precoding primitives, "
                "and return metadata so later stages can recover sample rate, FFT parameters, and grid sizes consistently.</p>"
            ),
            "flow": [
                "Normalize resource-grid dimensions to K x L x Ports",
                "Call nrOFDMModulate with forwarded numerology and optional windowing",
                "Carry OFDM metadata forward with engine, grid size, waveform size",
                "Call nrOFDMDemodulate on receive waveform",
                "Optionally use transform precoding / deprecoding for DFT-s-OFDM UL studies",
            ],
            "maths": [
                ("OFDM call surface", "waveform = nrOFDMModulate(carrier, grid, ...)\ngrid = nrOFDMDemodulate(carrier, waveform, ...)"),
                ("Approximate sample-rate derivation", "SampleRate ~= Nfft * SCS_Hz (used only when detailed OFDM info is unavailable)"),
                ("Transform precoding", "tpSym = nrTransformPrecode(modSym, MRB)\nmodSym = nrTransformDeprecode(tpSym, MRB)"),
            ],
            "details": [
                "These wrappers do not invent a custom FFT or CP algorithm; they rely on the 5G Toolbox kernels and standardize metadata.",
                "Shape normalization is important because many later blocks assume an explicit third port dimension.",
                "Transform precoding is exposed as an explicit wrapper rather than being hidden inside generic waveform code.",
            ],
            "excerpts": [
                ("+sixgr/+phy/+waveform/ofdmModulate.m", ["nrOFDMModulate"]),
                ("+sixgr/+phy/+waveform/ofdmDemodulate.m", ["nrOFDMDemodulate"]),
                ("+sixgr/+phy/+waveform/transformPrecode.m", ["nrTransformPrecode"]),
            ],
            "plantuml": """@startuml
start
:Resource grid K x L x P;
:Normalize dimensions;
:nrOFDMModulate(...);
:Waveform metadata captured;
:nrOFDMDemodulate(...);
if (DFT-s-OFDM path?) then (yes)
  :nrTransformPrecode / nrTransformDeprecode;
endif
stop
@enduml""",
        },
        {
            "id": "cell-search-pbch",
            "label": "Cell Search / PBCH",
            "search": "cell search pss sss pbch mib sib1 timing cfo dmrs bch decode",
            "files": [
                "+sixgr/+phy/+sync/cellSearch.m",
                "+sixgr/+phy/+dl/PBCH_Recovery.m",
                "+sixgr/+phy/+rrc/MIB_SIB1_Recovery.m",
            ],
            "summary": (
                "<p>Initial access uses a staged search path: PSS-based coarse frequency correction and NID2 selection, timing estimation, "
                "SSS correlation for NID1, then PBCH DM-RS based channel estimation and BCH decoding. Optional SIB1 payload recovery is configuration-backed, not a hidden waveform decoder.</p>"
            ),
            "flow": [
                "Run coarse frequency correction and obtain NID2 from PSS path",
                "Estimate timing offset to the symbol preceding PSS",
                "OFDM-demodulate SSB region and correlate SSS over all 336 NID1 hypotheses",
                "Build NCellID = 3*NID1 + NID2",
                "Loop PBCH iBar candidates, estimate channel from PBCH DM-RS + SSS, equalize and decode BCH",
                "Recover MIB and optionally map / source SIB1 payload from configured broadcast sources",
            ],
            "maths": [
                ("Cell ID reconstruction", "NCellID = 3 * NID1 + NID2"),
                ("SSS correlation metric", "metric(nid1) = abs(sum(conj(SSS_ref(nid1, NID2)) .* SSS_rx))"),
                ("PBCH candidate metric", "metric(ibar) = sum_r abs(sum(conj(DMRS_ref_ibar) .* DMRS_rx_r))^2"),
                ("PBCH chain", "nrChannelEstimate -> nrEqualizeMMSE -> nrPBCHDecode -> nrBCHDecode"),
            ],
            "details": [
                "cellSearch() demodulates a 20-RB SSB-sized carrier and pads missing symbols if needed.",
                "PBCH_Recovery() loops iBar candidates until BCH CRC passes; otherwise it falls back to the strongest DM-RS metric candidate for debug visibility.",
                "MIB_SIB1_Recovery() only performs true PBCH waveform recovery; SIB1 payload is sourced from explicit configured structures or the SystemInformation helper.",
            ],
            "excerpts": [
                ("+sixgr/+phy/+sync/cellSearch.m", ["NCellID = 3*NID1 + NID2;", "metric = abs(sum(conj(sss(:))"]),
                ("+sixgr/+phy/+dl/PBCH_Recovery.m", ["metric = metric + abs(sum(conj(refDmrs(:)) .* rxDmrs(:, r))).^2;", "nrEqualizeMMSE(pbchRx, pbchHest, nVarUse)", "nrBCHDecode"]),
            ],
            "plantuml": """@startuml
start
:PSS coarse frequency correction and NID2;
:Timing estimate;
:OFDM demodulate SSB region;
:Correlate SSS over 336 NID1 candidates;
:NCellID = 3*NID1 + NID2;
repeat
  :Try PBCH iBar candidate;
  :Estimate channel from PBCH DM-RS + SSS;
  :Equalize and decode BCH;
repeat while (CRC fail?)
:Build MIB and optional SIB1 context;
stop
@enduml""",
        },
        {
            "id": "pdsch-rx",
            "label": "PDSCH Rx",
            "search": "pdsch rx timing dmrs channel estimate mmse equalization llr rate recovery ldpc crc",
            "files": [
                "+sixgr/+phy/+dl/PDSCH_Rx.m",
                "+sixgr/+phy/+rx/channelEstimate.m",
                "+sixgr/+phy/+rx/equalizeMMSE.m",
                "+sixgr/+phy/+phycode/rateRecoverLDPC.m",
                "+sixgr/+phy/+phycode/ldpcDecode.m",
            ],
            "summary": (
                "<p>PDSCH reception is a concrete waveform chain: timing estimate, OFDM demodulation, DMRS-based channel estimation, MMSE equalization, "
                "PDSCH soft demodulation, LDPC rate recovery, code-block decode, desegmentation, and transport-block CRC.</p>"
            ),
            "flow": [
                "Materialize carrier and PDSCH allocation / indices",
                "If needed, derive transport-block size from nrTBS and allocation info",
                "Estimate timing from DMRS and shift waveform",
                "OFDM-demodulate to a resource grid and estimate channel",
                "Extract PDSCH REs, MMSE-equalize, and demodulate to codeword LLRs",
                "Rate-recover, LDPC-decode, desegment, and check TB CRC",
            ],
            "maths": [
                ("PDSCH TB size derivation", "TBS = nrTBS(Modulation, NumLayers, NPRB, NREPerPRB, TargetCodeRate, xOverhead)"),
                ("MMSE equalization", "eqSym, csi = nrEqualizeMMSE(rxSym, hEstSym, nVar)"),
                ("Decode chain", "LLR -> nrRateRecoverLDPC -> nrLDPCDecode -> desegmentLDPC -> checkCRC"),
                ("AWGN shortcut guard", "Fast scalar channel estimate is allowed only in explicit AWGN / flat SISO validation modes"),
            ],
            "details": [
                "The receiver can use a unit-channel shortcut only in validated AWGN / flat SISO conditions.",
                "Under explicit precoding, DMRS ports already define the effective layer-domain channel seen by the receiver.",
                "LDPC decode can use batch MEX, MATLAB parallelism, or pure toolbox fallback depending on runtime settings.",
            ],
            "excerpts": [
                ("+sixgr/+phy/+dl/PDSCH_Rx.m", ["trBlkSize = nrTBS", "[eqSym, csi] = nrEqualizeMMSE", "nrPDSCHDecode"]),
                ("+sixgr/+phy/+rx/channelEstimate.m", ["nrChannelEstimate(carrier, rxGrid, refInd, refSym", "Safe fallback to the resource-selective nrChannelEstimate path."]),
            ],
            "plantuml": """@startuml
start
:Carrier and PDSCH allocation;
:Timing estimate from DMRS;
:OFDM demodulate;
:Channel estimate;
:Extract PDSCH REs;
:MMSE equalize;
:nrPDSCHDecode to LLRs;
:Rate recover LDPC;
:LDPC decode;
:Desegment and CRC check;
stop
@enduml""",
        },
        {
            "id": "pusch-rx",
            "label": "PUSCH Rx",
            "search": "pusch rx dmrs timing equalization ldpc transform precoding uplink",
            "files": [
                "+sixgr/+phy/+ul/PUSCH_Rx.m",
                "+sixgr/+phy/+rx/channelEstimate.m",
                "+sixgr/+phy/+rx/equalizeMMSE.m",
                "+sixgr/+phy/+phycode/rateRecoverLDPC.m",
                "+sixgr/+phy/+phycode/ldpcDecode.m",
            ],
            "summary": (
                "<p>PUSCH reception mirrors the PDSCH chain but uses the UL allocation and UL-SCH metadata. "
                "It supports AWGN fast-path validation guards, DMRS-based timing and estimation, MMSE equalization, and LDPC decode.</p>"
            ),
            "flow": [
                "Build carrier and PUSCH allocation / indices",
                "Derive UL transport-block size from nrTBS when not supplied",
                "Estimate timing from UL DMRS and shift waveform",
                "OFDM-demodulate, estimate channel, and extract PUSCH REs",
                "MMSE-equalize and call nrPUSCHDecode to produce codeword LLRs",
                "Rate-recover, LDPC-decode, desegment, and CRC-check UL-SCH",
            ],
            "maths": [
                ("UL TB size", "TBS = nrTBS(Modulation, NumLayers, NPRB, NREPerPRB, TargetCodeRate, xOverhead)"),
                ("Noise variance", "Use estimated noise variance when finite; otherwise clamp to a small positive floor"),
                ("Decode chain", "nrPUSCHDecode -> rateRecoverLDPC -> ldpcDecode -> desegmentLDPC -> checkCRC"),
            ],
            "details": [
                "The implementation shares the same strict channel-estimation guard as PDSCH_Rx.",
                "When no explicit noise variance is provided, the estimator output is used, with a fallback floor if needed.",
                "The compact-output mode preserves only the essentials while the full mode includes symbols, CSI, code blocks, and channel estimates.",
            ],
            "excerpts": [
                ("+sixgr/+phy/+ul/PUSCH_Rx.m", ["trBlkSize = nrTBS", "[eqSym, csi] = nrEqualizeMMSE", "nrPUSCHDecode"]),
                ("+sixgr/+phy/+rx/equalizeMMSE.m", ["nrEqualizeMMSE", "eqSym = rxSym .* conj(hSym) ./ (abs(hSym).^2 + nVar);"]),
            ],
            "plantuml": """@startuml
start
:Carrier and PUSCH allocation;
:Timing estimate from UL DMRS;
:OFDM demodulate;
:Channel estimate;
:Extract PUSCH REs;
:MMSE equalize;
:nrPUSCHDecode to LLRs;
:Rate recover LDPC;
:LDPC decode;
:Desegment and CRC check;
stop
@enduml""",
        },
        {
            "id": "channel-estimation",
            "label": "Channel Estimation / Equalization",
            "search": "channel estimation equalization strict mex scalar awgn flat siso nrChannelEstimate nrEqualizeMMSE",
            "files": [
                "+sixgr/+phy/+rx/channelEstimate.m",
                "+sixgr/+phy/+rx/equalizeMMSE.m",
            ],
            "summary": (
                "<p>The estimation wrapper standardizes DMRS / CSI-RS style channel estimation and protects truth runs from invalid scalar shortcuts. "
                "The equalization wrapper can either call the 5G Toolbox MMSE equalizer directly or fall back to a manual SISO expression if the toolbox function is unavailable.</p>"
            ),
            "flow": [
                "Parse local controls such as UseFastMex, StrictMode, ChannelModel, ExpectedTxPorts",
                "Reject scalar-fast path in strict fading or multi-antenna conditions",
                "Optionally call scalar LS MEX kernel for explicit AWGN / flat SISO only",
                "Otherwise call nrChannelEstimate on reference indices and symbols",
                "Extract data REs and MMSE-equalize with nrEqualizeMMSE or manual SISO fallback",
            ],
            "maths": [
                ("Manual SISO equalizer", "eqSym = rxSym * conj(hSym) / (abs(hSym)^2 + nVar)\ncsi = abs(hSym)^2 / (abs(hSym)^2 + nVar)"),
                ("Scalar-fast path policy", "Allowed only if channel is explicit AWGN / flat and TxPorts = 1 and RxAnt = 1"),
            ],
            "details": [
                "channelEstimate() exposes why the scalar fast path was disabled, which is useful for truth validation.",
                "The MEX least-squares shortcut multiplies a single scalar estimate over the whole grid and is intentionally blocked for selective fading or spatial channels.",
                "equalizeMMSE() can optionally perform resource extraction if indices are passed to it.",
            ],
            "excerpts": [
                ("+sixgr/+phy/+rx/channelEstimate.m", ["Safe fallback to the resource-selective nrChannelEstimate path.", "[Hest, nVar] = nrChannelEstimate", "engine = \"nrChannelEstimate\""]),
                ("+sixgr/+phy/+rx/equalizeMMSE.m", ["[eqSym, csi] = nrEqualizeMMSE", "eqSym = rxSym .* conj(hSym) ./ (abs(hSym).^2 + nVar);"]),
            ],
            "plantuml": """@startuml
start
:Parse estimator policy inputs;
if (AWGN / flat SISO and fast scalar path?) then (yes)
  :Use scalar LS estimator;
else (no)
  :Use nrChannelEstimate;
endif
:Extract data REs;
if (nrEqualizeMMSE available?) then (yes)
  :Use nrEqualizeMMSE;
else (no)
  :Use manual SISO MMSE expression;
endif
stop
@enduml""",
        },
        {
            "id": "prach",
            "label": "PRACH",
            "search": "prach tx rx detect preamble random access msg1 nrPRACH nrPRACHDetect",
            "files": [
                "+sixgr/+phy/+ul/PRACH_Tx.m",
                "+sixgr/+phy/+ul/PRACH_Rx.m",
                "+sixgr/+link/runPRACHDetection.m",
            ],
            "summary": (
                "<p>The PRACH path is implemented as a concrete Msg1 waveform generation and detection chain using the 5G Toolbox PRACH APIs. "
                "The KPI wrapper optionally injects AWGN, measures compute latency, and records air-interface observation duration.</p>"
            ),
            "flow": [
                "Create nrCarrierConfig and nrPRACHConfig from cfg",
                "Generate PRACH symbols, indices, grid, and OFDM waveform",
                "Optionally inject AWGN for KPI runs",
                "Detect the preamble with nrPRACHDetect",
                "Report detection flag, preamble index, timing offset, and observation duration",
            ],
            "maths": [
                ("Observation duration", "AirInterfaceObservation_ms = 1e3 * (numSamples / SampleRate_Hz)"),
                ("Detection wrapper", "if SNR is finite: rxWave = addAwgnComplex(txWave, SNR_dB)\nthen PRACH_Rx -> nrPRACHDetect"),
            ],
            "details": [
                "Strict mode rejects disabled PRACH coverage or missing 5G Toolbox PRACH APIs.",
                "PRACH_Tx materializes symbols, indices, grid, waveform, and sample-rate metadata.",
                "The KPI wrapper distinguishes compute latency from air-interface observation time.",
            ],
            "excerpts": [
                ("+sixgr/+link/runPRACHDetection.m", ["nrPRACHDetect", "AirInterfaceObservation_ms", "Strict mode requires nrPRACH/nrPRACHDetect"]),
            ],
            "plantuml": """@startuml
start
:Build carrier and PRACH config;
:Generate PRACH symbols / indices / grid;
:PRACH OFDM modulation;
if (SNR finite?) then (yes)
  :Inject AWGN;
endif
:nrPRACHDetect;
:Report detection, preamble index, timing offset;
stop
@enduml""",
        },
    ]

    buttons = []
    panels = []
    for idx, module in enumerate(modules):
        active = " active" if idx == 0 else ""
        buttons.append(
            f'<button type="button" class="subtab-button{active}" data-impl-button="{html.escape(module["id"])}">'
            f'{html.escape(module["label"])}</button>'
        )
        flow_svg = build_vertical_flow_svg(module["label"] + " Flow", module["flow"])
        details_markup = "<ul>" + "".join(f"<li>{html.escape(item)}</li>" for item in module["details"]) + "</ul>"
        panel = (
            f'<div class="subtab-panel{" active" if idx == 0 else ""}" data-impl-panel="{html.escape(module["id"])}" '
            f'data-doc-search="{html.escape((module["search"] + " " + json.dumps(module, default=default_json)).lower())}">'
            f'<div class="doc-callout"><h3>{html.escape(module["label"])}</h3>{module["summary"]}</div>'
            '<div class="two-col">'
            + build_doc_card("Exact Code Surfaces", build_file_refs_markup(module["files"]), search_text=" ".join(module["files"]), extra_class="doc-card-tight")
            + build_doc_card("Implemented Message Flow", "<ol>" + "".join(f"<li>{html.escape(step)}</li>" for step in module["flow"]) + "</ol>", search_text=" ".join(module["flow"]), extra_class="doc-card-tight")
            + "</div>"
            + build_doc_card("Calculation Mathematics", build_formula_cards(module["maths"]), search_text=" ".join(expr for _, expr in module["maths"]), extra_class="doc-card-wide")
            + build_doc_card("Implemented Behaviors and Branches", details_markup, search_text=" ".join(module["details"]), extra_class="doc-card-wide")
            + build_source_excerpt_card(module.get("excerpts", []))
            + build_doc_card("Interactive Flow Diagram", f'<div class="flow-svg-wrap">{flow_svg}</div>', search_text=" ".join(module["flow"]), extra_class="doc-card-wide")
            + build_doc_card(
                "PlantUML Source",
                '<details class="uml-source" open><summary>Show editable PlantUML</summary>'
                f'<pre><code>{html.escape(module["plantuml"])}</code></pre></details>',
                search_text=module["plantuml"],
                extra_class="doc-card-wide",
            )
            + "</div>"
        )
        panels.append(panel)

    intro = (
        '<div class="doc-callout" data-doc-search="implementation exact algorithms code math interactive diagram plantuml">'
        "<h3>Exact Implementation Explorer</h3>"
        "<p class=\"muted\">Each module below is grounded in the current MATLAB code, not only the design docs. "
        "The page shows the concrete files, the implemented branch logic, the main formulas visible in code, a local rendered flow, "
        "and the matching PlantUML source so you can reuse or extend the diagrams.</p>"
        "</div>"
    )
    return intro + '<div class="chain-layout"><div class="chain-nav panel-scroll-x"><div class="tabular-tabs">' + "".join(buttons) + '</div></div><div class="chain-detail">' + "".join(panels) + "</div></div>"


def documentation_page_script() -> str:
    return """
<script>
function activateDocTab(tabName) {
  document.querySelectorAll('[data-doc-tab-button]').forEach((el) => {
    el.classList.toggle('active', el.dataset.docTabButton === tabName);
  });
  document.querySelectorAll('[data-doc-tab-panel]').forEach((el) => {
    el.classList.toggle('active', el.dataset.docTabPanel === tabName);
  });
}
function activateChainTab(chainId) {
  document.querySelectorAll('[data-chain-button]').forEach((el) => {
    el.classList.toggle('active', el.dataset.chainButton === chainId);
  });
  document.querySelectorAll('[data-chain-panel]').forEach((el) => {
    el.classList.toggle('active', el.dataset.chainPanel === chainId);
  });
}
function activateImplTab(moduleId) {
  document.querySelectorAll('[data-impl-button]').forEach((el) => {
    el.classList.toggle('active', el.dataset.implButton === moduleId);
  });
  document.querySelectorAll('[data-impl-panel]').forEach((el) => {
    el.classList.toggle('active', el.dataset.implPanel === moduleId);
  });
}
function applyDocSearch() {
  const query = String(document.getElementById('docSearch')?.value || '').trim().toLowerCase();
  document.querySelectorAll('[data-doc-search]').forEach((el) => {
    const haystack = String(el.dataset.docSearch || '');
    const match = !query || haystack.includes(query);
    el.classList.toggle('hidden', !match);
  });
}
document.querySelectorAll('[data-doc-tab-button]').forEach((button) => {
  button.addEventListener('click', () => activateDocTab(button.dataset.docTabButton));
});
document.querySelectorAll('[data-chain-button]').forEach((button) => {
  button.addEventListener('click', () => activateChainTab(button.dataset.chainButton));
});
document.querySelectorAll('[data-impl-button]').forEach((button) => {
  button.addEventListener('click', () => activateImplTab(button.dataset.implButton));
});
const docSearch = document.getElementById('docSearch');
if (docSearch) {
  docSearch.addEventListener('input', applyDocSearch);
}
const firstDocTab = document.querySelector('[data-doc-tab-button]');
if (firstDocTab) activateDocTab(firstDocTab.dataset.docTabButton);
const firstChainTab = document.querySelector('[data-chain-button]');
if (firstChainTab) activateChainTab(firstChainTab.dataset.chainButton);
const firstImplTab = document.querySelector('[data-impl-button]');
if (firstImplTab) activateImplTab(firstImplTab.dataset.implButton);
applyDocSearch();
</script>
"""


def build_documentation_page(user_profile: dict[str, Any] | None = None) -> bytes:
    scenario_count = len(list_scenarios())
    chain_catalog = load_processing_chain_catalog()
    chain_count = len(chain_catalog)
    block_count = sum(len((chain.get("ordered_blocks") or [])) for chain in chain_catalog.values())

    overview_cards = [
        ("Scenario Packs", str(scenario_count), "Config-driven runnable scenario YAMLs under simulator/configs/scenarios."),
        ("Processing Chains", str(chain_count), "Machine-readable exact TX/RX chain definitions loaded from processing_chains.yaml."),
        ("Declared Blocks", str(block_count), "Normative ordered block entries across initial access, control, DL, UL, CSI, HARQ, and more."),
        ("Execution Paths", "3", "Browser-backed single runs launch run_6g_phy_lls_single, matrix campaigns launch run_6g_phy_lls_matrix, and runLLSTests is validation-only."),
    ]
    overview_metric_cards = "".join(
        f'<div class="metric-card" data-doc-search="{html.escape((label + " " + note).lower())}">'
        f'<div class="metric-value">{html.escape(value)}</div>'
        f'<div class="metric-label">{html.escape(label)}</div>'
        f'<div class="mini-note">{html.escape(note)}</div></div>'
        for label, value, note in overview_cards
    )

    run_guide_markup = """
<div class="doc-grid">
  <section class="doc-card" data-doc-search="run guide matlab command cli dashboard mysql browser single scenario">
    <h3>How To Run From MATLAB</h3>
    <p>Single-scenario LLS front door:</p>
    <div class="doc-code-wrap">
      <div class="doc-code-label">MATLAB</div>
      <pre><code>setup6GRSimToolkit('Verbose',false);
run_6g_phy_lls_single('simulator/configs/scenarios/lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml','results','browser_like_run')</code></pre>
    </div>
    <p>Matrix front door:</p>
    <div class="doc-code-wrap">
      <div class="doc-code-label">MATLAB</div>
      <pre><code>setup6GRSimToolkit('Verbose',false);
run_6g_phy_lls_matrix('simulator/configs/matrices/example.yaml','results','matrix_run')</code></pre>
    </div>
  </section>
  <section class="doc-card" data-doc-search="browser dashboard intranet home run analytics result mysql web control plane">
    <h3>How To Run From The Browser</h3>
    <ol>
      <li>Open <code>/home</code> and choose a scenario YAML.</li>
      <li>Edit resolved parameters in grouped tabs.</li>
      <li>Press the run button to create a runtime YAML overlay from the current browser payload.</li>
      <li>The backend launches <code>run_6g_phy_lls_single</code> against that exact runtime file.</li>
      <li>Watch <code>/result</code>, <code>/analytics</code>, <code>/logs</code>, and <code>/map</code> update from MySQL in near real time.</li>
    </ol>
    <p class="mini-note">The web flow uses the same MATLAB entry point and scenario config model. It does not create a second simulation path. For the current coupled multi-UE LLS path, the serving waveform chain is sample-domain truth and the honest default interferer path is now full per-link channel-waveform summation; any remaining hybrid or abstract interferer mode stays explicitly labeled rather than being relabeled as truth.</p>
  </section>
  <section class="doc-card" data-doc-search="validation harness runllstests regression matlab tests only">
    <h3>Validation Harness Only</h3>
    <p><code>runLLSTests</code> is the focused MATLAB regression pack for LLS and coupled-truth validation. It is not the production browser run path.</p>
    <div class="doc-code-wrap">
      <div class="doc-code-label">MATLAB</div>
      <pre><code>setup6GRSimToolkit('Verbose',false);
runLLSTests('Verbose',true)</code></pre>
    </div>
    <p class="mini-note">Use this to validate the repo. Use the browser or <code>run_6g_phy_lls_single</code> to execute a real scenario run.</p>
  </section>
  <section class="doc-card" data-doc-search="strict mode truth deterministic seeds validation fallback honest output">
    <h3>Strict Truth Expectations</h3>
    <ul>
      <li>Behavior must come from resolved configuration, not hidden environment state.</li>
      <li>Deterministic mode records seed, config, environment, and manifest metadata.</li>
      <li>Strict validation rejects invalid combinations before simulation work starts.</li>
      <li>Truth artifacts must not be mislabeled proxy or fallback outputs.</li>
    </ul>
  </section>
  <section class="doc-card" data-doc-search="where results go mysql db filesystem run folder artifacts tables images logs">
    <h3>Where Outputs Go</h3>
    <p>In filesystem mode the canonical root is <code>results/lls/&lt;scenario_id&gt;/&lt;run_tag&gt;/</code>. In MySQL-backed web mode the same logical artifact paths are stored in <code>sim_artifacts</code> and streamed back to the browser.</p>
    <p class="mini-note">See the Results tab for the canonical artifact layout and ownership rules.</p>
  </section>
</div>
"""

    tabs = [
        ("overview", "Overview"),
        ("run-guide", "Run Guide"),
        ("architecture", "Architecture"),
        ("baselines", "Baselines"),
        ("chains", "Chains"),
        ("implementation", "Implementation"),
        ("calculations", "Calculations"),
        ("results", "Results"),
        ("source-map", "Source Map"),
    ]
    tab_buttons = "".join(
        f'<button type="button" class="subtab-button" data-doc-tab-button="{tab_id}">{label}</button>'
        for tab_id, label in tabs
    )

    overview_panel = (
        '<div class="panel doc-hero" data-doc-search="overview architecture lls config driven truth">'
        "<h2>LLS Architecture Guide</h2>"
        "<p class=\"muted\">This page is built from the repository's own 6G LLS deliverables, configuration catalogs, "
        "processing-chain declarations, and current implementation surfaces. It is designed to explain how the simulator is structured, "
        "how runs are launched, what the main baselines and candidate features are, how TX/RX chains are ordered, and where the main calculations live.</p>"
        f'<div class="metric-grid">{overview_metric_cards}</div>'
        "</div>"
        + build_doc_card(
            "Deliverables Pack",
            render_markdown_document(load_repo_markdown("docs/6g_lls/README.md")),
            search_text=load_repo_markdown("docs/6g_lls/README.md"),
            extra_class="doc-card-wide",
        )
    )

    baselines_panel = (
        '<div class="two-col">'
        + build_doc_card(
            "Scenario Library",
            render_markdown_document(load_repo_markdown("docs/6g_lls/scenario_library.md")),
            search_text=load_repo_markdown("docs/6g_lls/scenario_library.md"),
            extra_class="doc-card-wide",
        )
        + build_doc_card(
            "Validation Rules",
            render_markdown_document(load_repo_markdown("docs/6g_lls/validation_rules.md")),
            search_text=load_repo_markdown("docs/6g_lls/validation_rules.md"),
            extra_class="doc-card-wide",
        )
        + "</div>"
    )

    results_panel = (
        '<div class="two-col">'
        + build_doc_card(
            "LLS Result Specification",
            render_markdown_document(load_repo_markdown("docs/6g_lls/result_specification.md")),
            search_text=load_repo_markdown("docs/6g_lls/result_specification.md"),
            extra_class="doc-card-wide",
        )
        + build_doc_card(
            "Repository Output Layout",
            render_markdown_document(load_repo_markdown("docs/result_output_layout.md")),
            search_text=load_repo_markdown("docs/result_output_layout.md"),
            extra_class="doc-card-wide",
        )
        + "</div>"
    )

    chain_intro = (
        build_doc_card(
            "Chain Catalog Contract",
            render_markdown_document(load_repo_markdown("docs/6g_lls/processing_chains.md")),
            search_text=load_repo_markdown("docs/6g_lls/processing_chains.md"),
            extra_class="doc-card-wide",
        )
        + build_doc_card(
            "Block Diagrams and Parameter Families",
            render_markdown_document(load_repo_markdown("docs/6g_lls/block_diagrams_and_parameters.md")),
            search_text=load_repo_markdown("docs/6g_lls/block_diagrams_and_parameters.md"),
            extra_class="doc-card-wide",
        )
    )

    panels = {
        "overview": overview_panel,
        "run-guide": run_guide_markup,
        "architecture": build_doc_card(
            "Simulator Architecture",
            render_markdown_document(load_repo_markdown("docs/6g_lls/architecture.md")),
            search_text=load_repo_markdown("docs/6g_lls/architecture.md"),
            extra_class="doc-card-wide",
        ),
        "baselines": baselines_panel,
        "chains": chain_intro + build_chain_explorer_markup(),
        "implementation": build_exact_algorithm_markup(),
        "calculations": build_calculation_markup(),
        "results": results_panel,
        "source-map": build_source_map_markup(),
    }

    tab_panels = "".join(
        f'<div class="subtab-panel" data-doc-tab-panel="{tab_id}">{panels[tab_id]}</div>' for tab_id, _ in tabs
    )

    body = f"""
    <section class="panel">
      <div class="toolbar">
        <input id="docSearch" class="search-input" type="search" placeholder="Search architecture, chains, metrics, files, algorithms, and results...">
        <span class="pill">Interactive tabs</span>
        <span class="pill">Exact chain explorer</span>
        <span class="pill">Source-linked implementation guide</span>
      </div>
      <div class="subtab-bar" style="margin-top:16px;">{tab_buttons}</div>
      {tab_panels}
    </section>
    """
    return page_shell(
        "Documentation",
        body,
        active="documentation",
        extra_script=documentation_page_script(),
        user_profile=user_profile,
    )


def resolve_scenario_path(rel_path: str) -> Path:
    safe_rel = Path(rel_path)
    abs_path = (SCENARIO_ROOT / safe_rel).absolute()
    scenario_root = SCENARIO_ROOT.absolute()
    if abs_path != scenario_root and scenario_root not in abs_path.parents:
        raise ValueError("Scenario path escapes the scenario catalog.")
    return abs_path


def list_scenarios() -> list[str]:
    if not SCENARIO_ROOT.is_dir():
        return []
    items = []
    for path in sorted(SCENARIO_ROOT.rglob("*.yaml")):
        if path.name.startswith("__web_runtime_"):
            continue
        items.append(path.relative_to(SCENARIO_ROOT).as_posix())
    return items


def load_scenario_text(rel_path: str) -> str:
    return resolve_scenario_path(rel_path).read_text(encoding="utf-8")


def repo_relative_text(path: Path) -> str:
    try:
        return path.absolute().relative_to(REPO_ROOT.absolute()).as_posix()
    except Exception:
        return str(path.absolute())


def resolve_catalog_reference(base_file: Path, raw_ref: str) -> Path:
    candidate = Path(str(raw_ref))
    if candidate.is_file():
        return candidate.absolute()
    relative_candidate = (base_file.parent / candidate).absolute()
    if relative_candidate.is_file():
        return relative_candidate
    repo_candidate = (REPO_ROOT / candidate).absolute()
    if repo_candidate.is_file():
        return repo_candidate
    raise FileNotFoundError(f"Unable to resolve inherited config '{raw_ref}' from '{base_file}'.")


def merge_config_dict(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    merged: dict[str, Any] = {}
    for key, value in base.items():
        if isinstance(value, dict):
            merged[key] = merge_config_dict(value, {})
        elif isinstance(value, list):
            merged[key] = list(value)
        else:
            merged[key] = value
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = merge_config_dict(merged[key], value)
        elif isinstance(value, dict):
            merged[key] = merge_config_dict({}, value)
        elif isinstance(value, list):
            merged[key] = list(value)
        else:
            merged[key] = value
    return merged


CONFIG_NO_CHANGE = object()


def diff_config_value(base: Any, current: Any) -> Any:
    if isinstance(base, dict) and isinstance(current, dict):
        diff: dict[str, Any] = {}
        for key, value in current.items():
            if key not in base:
                diff[key] = copy.deepcopy(value)
                continue
            child_diff = diff_config_value(base.get(key), value)
            if child_diff is not CONFIG_NO_CHANGE:
                diff[key] = child_diff
        return diff if diff else CONFIG_NO_CHANGE
    if isinstance(base, list) and isinstance(current, list):
        return CONFIG_NO_CHANGE if values_equal(base, current) else copy.deepcopy(current)
    return CONFIG_NO_CHANGE if values_equal(base, current) else copy.deepcopy(current)


PATH_MISSING = object()
BROWSER_ALIAS_RULES: list[tuple[str, str, str]] = [
    ("run_control.seed", "simulation.random_seed", "identity"),
    ("run_control.deterministic_mode", "simulation.deterministic_mode", "identity"),
    ("global_radio_scope.carrier_frequency_hz", "frequency.center_frequency_hz", "identity"),
    ("global_radio_scope.frequency_range_label", "frequency.range_name", "identity"),
    ("global_radio_scope.channel_bandwidth_hz", "frequency.bandwidth_hz", "identity"),
    ("global_radio_scope.simulation_bandwidth_hz", "frequency.bandwidth_hz", "identity"),
    ("global_radio_scope.duplex_mode", "frequency.duplex_mode", "identity"),
    ("global_radio_scope.scs_hz", "frame.scs_khz", "hz_to_khz"),
    ("global_radio_scope.cp_type", "frame.cp_type", "identity"),
    ("global_radio_scope.sample_rate_hz", "waveform.sample_rate_hz", "identity"),
    ("global_radio_scope.fft_size", "waveform.fft_size", "identity"),
    ("frame_timing.tdd_pattern", "frame.tdd_pattern", "identity"),
    ("mobility.ue_speed_kmh", "channels.mobility_kmph", "identity"),
    ("mobility.spatial_consistency_flag", "channels.spatial_consistency_enabled", "identity"),
    ("antenna_and_array.bs_num_antenna_elements", "mimo.n_tx_ant", "identity"),
    ("antenna_and_array.ue_num_antenna_elements", "mimo.n_rx_ant", "identity"),
    ("antenna_and_array.digital_precoder_family", "mimo.precoder_type", "identity"),
    ("power_and_rf_frontend.bs_tx_power_dbm", "energy_efficiency.tx_power_dbm", "identity"),
    ("system.scheduler.maxActiveUEsPerSlot", "system.scheduler.max_active_ues_per_slot", "identity"),
    ("system.scheduler.maxPRBAllocationPerUE", "system.scheduler.max_prb_allocation_per_ue", "identity"),
    ("system.scheduler.fairnessAlpha", "system.scheduler.fairness_alpha", "identity"),
    ("system.scheduler.proportionalFairWindow_ms", "system.scheduler.proportional_fair_window_ms", "identity"),
    ("system.scheduler.beamAware", "system.scheduler.beam_aware_scheduler_enable", "identity"),
    ("system.scheduler.energyAware", "system.scheduler.energy_aware_scheduler_enable", "identity"),
    ("system.scheduler.qosAware", "system.scheduler.qos_aware_enable", "identity"),
    ("system.scheduler.sliceAware", "system.scheduler.slice_aware_enable", "identity"),
    ("system.scheduler.starvationGuard", "system.scheduler.starvation_guard_enable", "identity"),
    ("system.scheduler.cellEdgeBoost", "system.scheduler.cell_edge_boost_enable", "identity"),
    ("waveform.dl_waveform", "waveform.dl_waveform", "identity"),
    ("waveform.ul_waveform", "waveform.ul_waveform", "identity"),
    ("waveform.transform_precoding", "waveform.transform_precoding_enabled", "identity"),
    ("waveform.windowing", "waveform.windowing_enabled", "identity"),
    ("channel_model.model_family", "channels.model_type", "identity"),
    ("channel_model.scenario_label", "channels.profile", "identity"),
    ("channel_model.delay_spread_ns", "channels.delay_spread_ns", "identity"),
    ("channel_model.doppler_hz", "channels.doppler_hz", "identity"),
    ("channel_model.doppler_source_mode", "channels.doppler_source_mode", "identity"),
    ("mimo_and_beam_management.beam_sweeping", "mimo.beam_sweep_enabled", "identity"),
    ("mimo_and_beam_management.rank_set", "mimo.n_layers", "first_numeric"),
    ("mimo_and_beam_management.codebook_family", "mimo.codebook_type", "identity"),
    ("mimo_and_beam_management.mtrp_coordination", "mimo.mtrp_ready", "identity"),
    ("csi_acquisition_and_reporting.cqi_policy", "reference_signals.cqi_reporting_enabled", "policy_to_bool"),
    ("csi_acquisition_and_reporting.pmi_policy", "reference_signals.pmi_reporting_enabled", "policy_to_bool"),
    ("csi_acquisition_and_reporting.ri_policy", "reference_signals.ri_reporting_enabled", "policy_to_bool"),
    ("csi_acquisition_and_reporting.cri_policy", "reference_signals.cri_reporting_enabled", "policy_to_bool"),
    ("csi_acquisition_and_reporting.channel_state_information_mode", "reference_signals.csi_feedback_mode", "identity"),
    ("csi_acquisition_and_reporting.pmi_codebook_mode", "reference_signals.pmi_codebook_mode", "identity"),
    ("csi_acquisition_and_reporting.dl_csi_enabled", "reference_signals.csi_reporting_enabled", "identity"),
    ("channel_coding.data_channel_family", "coding.data_code_type", "identity"),
    ("channel_coding.control_channel_family", "coding.control_code_type", "identity"),
    ("channel_coding.ldpc_base_graph", "coding.base_graph", "identity"),
    ("ai_ml.model_name", "ai_ml.model_id", "identity"),
    ("ai_ml.fallback_mode", "ai_ml.fallback_enabled", "string_to_bool"),
    ("energy_and_complexity.throughput_per_watt", "kpis.energy_per_bit", "bool_to_metric"),
    ("kpi_spec.mandatory_kpis", "kpis", "kpi_list_to_struct"),
    ("output_control.save_intermediate", "logging.save_intermediate", "identity"),
    ("output_control.save_plots", "output.save_figures", "identity"),
    ("output_control.save_plots", "output.save_png", "identity"),
    ("output_control.save_resolved_config", "output.save_yaml_snapshot", "identity"),
    ("output_control.save_resolved_config", "output.save_json_snapshot", "identity"),
    ("signals_and_channels_common.ssb.enable_flag", "reference_signals.ssb_enabled", "identity"),
    ("signals_and_channels_common.pbch.enable_flag", "reference_signals.pbch_enabled", "identity"),
    ("reference_signals.pdcch_dmrs.enabled", "reference_signals.pdcch_dmrs_enabled", "identity"),
    ("reference_signals.nzp_csi_rs.enabled", "reference_signals.csi_rs_enabled", "identity"),
    ("reference_signals.srs.enabled", "reference_signals.srs_enabled", "identity"),
    ("reference_signals.trs.enabled", "reference_signals.trs_enabled", "identity"),
    ("reference_signals.tracking_rs.enabled", "reference_signals.tracking_rs_enabled", "identity"),
    ("reference_signals.ptrs.enabled", "reference_signals.ptrs_enabled", "identity"),
    ("reference_signals.pdsch_dmrs.num_ports", "reference_signals.pdsch_dmrs_ports", "identity"),
    ("reference_signals.pusch_dmrs.num_ports", "reference_signals.pusch_dmrs_ports", "identity"),
    ("reference_signals.srs.num_ports", "reference_signals.srs_ports", "identity"),
    ("reference_signals.srs.sequence_type", "reference_signals.srs_sequence_family", "identity"),
    ("reference_signals.srs.periodicity", "reference_signals.srs_periodicity_ms", "identity"),
    ("pdcch.enabled", "control.pdcch_enabled", "identity"),
    ("pdcch.aggregation_levels", "control.aggregation_levels", "identity"),
    ("pucch.enabled", "control.pucch_enabled", "identity"),
    ("prach.enabled", "random_access.enabled", "identity"),
    ("prach.sequence_family", "random_access.prach_sequence_family", "identity"),
    ("prach.format_set", "random_access.prach_format", "first_string"),
]
BROWSER_OPTION_SOURCE_ALIASES: dict[str, list[str]] = {
    "mobility.trajectory_model": ["scenario.mobility.model"],
    "mobility.direction_model": ["scenario.mobility.model"],
    "output.backend": ["outputs.storageBackend"],
    "output_control.save_intermediate": ["logging.save_intermediate"],
    "output_control.save_plots": ["output.save_figures", "output.save_png"],
    "power_and_rf_frontend.bs_tx_power_dbm": ["energy_efficiency.tx_power_dbm"],
}
GENERIC_OPTION_LEAVES = {
    "type",
    "model",
    "mode",
    "profile",
    "family",
    "format",
    "policy",
    "enabled",
    "value",
    "name",
    "coding",
    "purpose",
}
BROWSER_GENERATED_TOP_LEVEL_KEYS = {"config_inheritance", "_download_metadata"}
HOME_GROUP_ORDER = ["topology", "radio", "antenna", "scheduler", "control", "output", "other"]
HOME_GROUP_LABELS = {
    "topology": "Topology / Geometry",
    "radio": "Radio / Channel",
    "antenna": "Antenna / Beamforming / CSI",
    "scheduler": "Scheduler / MAC / HARQ",
    "control": "Control / Access",
    "output": "Output / Execution",
    "other": "Other / Secondary",
}


def path_get(node: Any, path: str, default: Any = PATH_MISSING) -> Any:
    current = node
    for key in [part for part in path.split(".") if part]:
        if not isinstance(current, dict) or key not in current:
            return default
        current = current[key]
    return current


def path_set(node: dict[str, Any], path: str, value: Any) -> dict[str, Any]:
    current = node
    parts = [part for part in path.split(".") if part]
    for key in parts[:-1]:
        child = current.get(key)
        if not isinstance(child, dict):
            child = {}
            current[key] = child
        current = child
    if parts:
        current[parts[-1]] = value
    return node


def path_delete(node: dict[str, Any], path: str) -> None:
    parts = [part for part in path.split(".") if part]
    if not parts:
        return
    stack: list[tuple[dict[str, Any], str]] = []
    current: Any = node
    for key in parts[:-1]:
        if not isinstance(current, dict) or key not in current:
            return
        stack.append((current, key))
        current = current[key]
    if not isinstance(current, dict):
        return
    current.pop(parts[-1], None)
    while stack:
        parent, key = stack.pop()
        child = parent.get(key)
        if isinstance(child, dict) and not child:
            parent.pop(key, None)
        else:
            break


def values_equal(left: Any, right: Any) -> bool:
    return left == right


def resolve_home_group(path: str) -> str:
    normalized = str(path or "").strip().lower()
    if normalized.startswith(("deployment_topology.", "mobility.", "users.")) or normalized in {
        "simulation.random_seed",
        "run_control.seed",
    }:
        return "topology"
    if normalized.startswith((
        "frequency.",
        "global_radio_scope.",
        "frame.",
        "frame_timing.",
        "bandwidth_operation.",
        "power_and_rf_frontend.",
        "waveform.",
        "resource_grid.",
        "channels.",
        "channel_model.",
        "impairments.",
    )):
        return "radio"
    if normalized.startswith(("antenna_and_array.", "mimo.", "mimo_and_beam_management.", "csi_acquisition_and_reporting.")):
        return "antenna"
    if normalized.startswith(("reference_signals.",)):
        if any(token in normalized for token in ("pbch", "srs", "trs", "tracking_rs")):
            return "control"
        return "antenna"
    if normalized.startswith(("link_adaptation.", "harq.", "traffic.", "system.scheduler.", "channel_coding.", "modulation_and_mapping.")):
        return "scheduler"
    if normalized.startswith(("system.beam.", "system.measurement.", "system.handover.", "system.queuemaxbits")):
        return "topology"
    if normalized.startswith(("pdcch.", "prach.", "pucch.", "control.", "random_access.", "signals_and_channels_common.", "control_gating.")):
        return "control"
    if normalized.startswith(("output.", "output_control.", "logging.", "run_control.", "sweeps_and_matrix.", "simulation.")):
        return "output"
    return "other"


def classify_browser_field_support(path: str) -> tuple[str, str]:
    normalized = str(path or "").strip().lower()
    if normalized == "run_control.execution_mode":
        return (
            "active",
            "This top-level browser selector is serialized into the authoritative payload and routes the backend launch path. "
            "In this pass, only LLS is fully launchable from /run; SLS, End-to-end, and Test all stay explicitly separated and blocked from accidental LLS execution.",
        )
    if normalized in {
        "mobility.ue_speed_kmh",
        "channels.mobility_kmph",
        "scenario.mobility.speed_kmh",
        "scenario.mobility.speed_mps",
    }:
        return (
            "active",
            "Serialized into the authoritative browser payload and consumed by the active browser-driven MATLAB run. "
            "This speed drives UE motion and large-scale geometry updates; when Doppler Source Mode is derive_from_ue_speed, it also resolves the fading Doppler applied to the waveform channel.",
        )
    if normalized in {
        "channels.doppler_hz",
        "channel_model.doppler_hz",
        "channels.doppler_source_mode",
        "channel_model.doppler_source_mode",
    }:
        return (
            "active",
            "Actively used in the runtime channel config. When Doppler Source Mode is derive_from_ue_speed, MATLAB resolves the effective Doppler from UE speed and carrier frequency and treats the numeric Doppler field as a fallback/display value.",
        )
    if normalized.startswith(("interference.",)):
        return (
            "active",
            "Actively used in the browser run. The no-proxy LLS path supports full_per_link_channel_waveform_sum for real grant-specific interferer waveforms with their own channel realizations; legacy large-scale overlap shortcuts are rejected before MATLAB runtime.",
        )
    if normalized.startswith(("traffic.",)):
        return (
            "active",
            "Serialized into the browser-owned payload and consumed by the active coupled runtime. "
            "TrafficFactory now reads the configured traffic model directly, and the browser LLS path no longer silently converts missing trace traffic into hidden full-buffer demand.",
        )
    if normalized.startswith(("system.scheduler.", "system.measurement.", "system.beam.")):
        return (
            "active",
            "Serialized into the browser-owned payload and consumed by the active coupled runtime. "
            "These knobs now feed scheduler selection, measurement cadence, beam-update cadence, queue sizing, and multi-cell serving-state behavior in the same LLS run path launched from /run.",
        )
    if normalized.startswith(("system.handover.",)):
        return (
            "secondary",
            "Stored in the resolved browser payload and runtime snapshots. The active coupled LLS path currently exports serving-cell reselection events from large-scale measurements, while full A3-like interruption semantics remain richer in the separate system runner.",
        )
    if normalized in {"simulation.noise_operating_mode", "simulation.operating_point_mode"}:
        return (
            "active",
            "Actively used in the browser run. The truthful LLS browser scenario now defaults to receiver-noise-figure thermal noise; configured snr_db remains available only as an explicit alternate operating mode.",
        )
    if normalized in {"simulation.snr_db", "simulation.snr_sweep_offsets_db"}:
        return (
            "secondary",
            "Retained in the payload for optional anchor-SNR and sweep-style LLS studies, but the main honest browser LLS scenario can now run with receiver-noise-derived noise instead.",
        )
    if normalized == "scenario.bundle_anchor_cases":
        return (
            "secondary",
            "YAML-owned advanced control for the waveform-bundle preflight only. It is serialized into the resolved scenario snapshot and constrains which anchor cases run before the canonical raw coupled-truth bundle takes over.",
        )
    if normalized.startswith(("control_gating.",)):
        return (
            "active",
            "Serialized into the authoritative browser payload and consumed by the active slot-coupled LLS runtime. "
            "These flags determine whether PBCH acquisition, PRACH access readiness, grant-coupled PDCCH delivery, and SRS freshness are real gating conditions before data scheduling/execution.",
        )
    if normalized.startswith(("reference_signals.trs", "reference_signals.tracking_rs")):
        return (
            "active",
            "Serialized into the payload and exported from the active coupled runtime. "
            "TRS currently feeds runtime tracking state and scheduler eligibility when gating is enabled, but the receiver kernels still do not consume a shared TRS-driven timing/CFO tracking object.",
        )
    if normalized.startswith((
        "pdcch.",
        "prach.",
        "pucch.",
        "random_access.",
        "signals_and_channels_common.",
        "reference_signals.pbch",
        "reference_signals.srs",
    )):
        return (
            "active",
            "Serialized into the runtime payload and used by the active slot-coupled LLS run. "
            "PBCH, PRACH, PDCCH, SRS, and TRS runtime state are exported from the active coupled LLS run. "
            "TRS can gate scheduler eligibility, but receiver-kernel coupling remains explicitly blocked unless a shared tracking object is added.",
        )
    if normalized.startswith(("sweeps_and_matrix.",)):
        return (
            "separate-mode",
            "Belongs to optional sweep or campaign execution. The default browser path stays on a single scenario run unless you explicitly switch modes.",
        )
    if normalized.startswith(("ai_ml.", "energy_and_complexity.", "sanity_checks.", "kpi_spec.")):
        return (
            "secondary",
            "Stored in the payload and artifacts, but not part of the primary browser-owned multi-UE coupled-truth loop for this scenario.",
        )
    return (
        "active",
        "Serialized into the authoritative browser payload and consumed by the active browser-driven MATLAB run.",
    )


def strip_inherits(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, dict):
        return {}
    payload = dict(raw)
    payload.pop("inherits", None)
    return payload


@lru_cache(maxsize=1)
def load_browser_alias_defaults() -> tuple[dict[str, Any], dict[str, Any]]:
    new_defaults: dict[str, Any] = {}
    for rel_path in (
        "simulator/configs/defaults/top_level_required_sections_01.yaml",
        "simulator/configs/defaults/top_level_required_sections_02.yaml",
        "simulator/configs/defaults/top_level_required_sections_03.yaml",
    ):
        raw = yaml.safe_load((REPO_ROOT / rel_path).read_text(encoding="utf-8")) or {}
        new_defaults = merge_config_dict(new_defaults, strip_inherits(raw))
    legacy_raw = yaml.safe_load((REPO_ROOT / "simulator/configs/defaults/global.yaml").read_text(encoding="utf-8")) or {}
    legacy_defaults = strip_inherits(legacy_raw)
    return new_defaults, legacy_defaults


def convert_alias_value(value: Any, mode: str, direction: str) -> Any:
    if value is PATH_MISSING:
        return value
    if mode == "identity":
        return value
    if mode == "hz_to_khz":
        if direction == "new_to_old":
            return float(value) / 1e3
        return float(value) * 1e3
    if mode == "first_numeric":
        if isinstance(value, (list, tuple)) and value:
            return float(value[0]) if direction == "new_to_old" else float(value[0])
        return value
    if mode == "first_string":
        if isinstance(value, (list, tuple)) and value:
            token = str(value[0])
            return token if direction == "new_to_old" else token
        return value
    if mode == "string_to_bool":
        if direction == "new_to_old":
            return str(value).strip().lower() not in {"disabled", "none", "off", "false"}
        return "enabled" if bool(value) else "disabled"
    if mode == "bool_to_metric":
        return bool(value)
    if mode == "policy_to_bool":
        if direction == "new_to_old":
            return str(value).strip().lower() not in {"disabled", "none", "off", "false"}
        return "baseline" if bool(value) else "disabled"
    if mode == "kpi_list_to_struct":
        if direction == "new_to_old":
            if isinstance(value, (list, tuple)):
                out: dict[str, Any] = {}
                for item in value:
                    key = re.sub(r"[^0-9A-Za-z_]+", "_", str(item).strip())
                    if key:
                        out[key] = True
                return out
        return value
    return value


def sync_browser_alias_value(
    payload: dict[str, Any],
    new_defaults: dict[str, Any],
    legacy_defaults: dict[str, Any],
    new_path: str,
    old_path: str,
    mode: str,
) -> None:
    new_val = path_get(payload, new_path)
    old_val = path_get(payload, old_path)
    new_base = path_get(new_defaults, new_path)
    old_base = path_get(legacy_defaults, old_path)

    new_diff = not values_equal(new_val, new_base)
    old_diff = not values_equal(old_val, old_base)
    new_to_old = convert_alias_value(new_val, mode, "new_to_old")
    old_to_new = convert_alias_value(old_val, mode, "old_to_new")

    if new_val is not PATH_MISSING and old_val is PATH_MISSING and new_to_old is not PATH_MISSING:
        path_set(payload, old_path, new_to_old)
        return
    if old_val is not PATH_MISSING and new_val is PATH_MISSING and old_to_new is not PATH_MISSING:
        path_set(payload, new_path, old_to_new)
        return
    if new_diff and not old_diff and new_to_old is not PATH_MISSING:
        path_set(payload, old_path, new_to_old)
        return
    if old_diff and not new_diff and old_to_new is not PATH_MISSING:
        path_set(payload, new_path, old_to_new)
        return
    if new_diff and old_diff and old_to_new is not PATH_MISSING:
        if not values_equal(old_val, new_to_old) and not values_equal(new_val, old_to_new):
            path_set(payload, new_path, old_to_new)


def canonicalize_browser_config_payload(payload: dict[str, Any], keep_legacy_aliases: bool = False) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return payload
    resolved = copy.deepcopy(payload)
    for key in BROWSER_GENERATED_TOP_LEVEL_KEYS:
        resolved.pop(key, None)
    new_defaults, legacy_defaults = load_browser_alias_defaults()
    for new_path, old_path, mode in BROWSER_ALIAS_RULES:
        if new_path == old_path:
            continue
        sync_browser_alias_value(resolved, new_defaults, legacy_defaults, new_path, old_path, mode)
    if not keep_legacy_aliases:
        for new_path, old_path, _ in BROWSER_ALIAS_RULES:
            if new_path == old_path:
                continue
            path_delete(resolved, old_path)
    apply_browser_derived_runtime_aliases(resolved, new_defaults)
    return resolved


def apply_browser_derived_runtime_aliases(payload: dict[str, Any], new_defaults: dict[str, Any]) -> None:
    scs_khz = path_get(payload, "frame.scs_khz")
    if scs_khz is PATH_MISSING:
        scs_hz = path_get(payload, "global_radio_scope.scs_hz")
        try:
            scs_khz = float(scs_hz) / 1e3
        except (TypeError, ValueError):
            scs_khz = PATH_MISSING
    try:
        scs_khz = float(scs_khz)
    except (TypeError, ValueError):
        return
    if not math.isfinite(scs_khz) or scs_khz <= 0:
        return
    mu = math.log2(scs_khz / 15.0)
    if not math.isfinite(mu):
        return
    mu = int(round(mu))
    if mu < 0:
        return

    _replace_if_default_or_missing(payload, new_defaults, "global_radio_scope.scs_hz", scs_khz * 1e3)
    _replace_if_default_or_missing(payload, new_defaults, "global_radio_scope.numerology_mu", mu)
    _replace_if_default_or_missing(payload, new_defaults, "frame_timing.slot_duration_ms", 1.0 / (2 ** mu))
    _replace_if_default_or_missing(payload, new_defaults, "frame_timing.slots_per_frame", 10 * (2 ** mu))
    _replace_if_default_or_missing(payload, new_defaults, "frame_timing.symbols_per_slot", 14)

    active_mode = str(path_get(payload, "bandwidth_operation.active_bandwidth_mode", "fullband") or "fullband").strip().lower()
    supports_partial = bool(path_get(payload, "bandwidth_operation.supports_partial_band_activation", False))
    grid_rbs = path_get(payload, "frequency.n_size_grid")
    try:
        grid_rbs = int(round(float(grid_rbs)))
    except (TypeError, ValueError):
        grid_rbs = None
    if grid_rbs is not None and grid_rbs > 0 and (not supports_partial or active_mode == "fullband"):
        _replace_if_default_or_missing(payload, new_defaults, "resource_grid.num_rbs", grid_rbs)


def _replace_if_default_or_missing(payload: dict[str, Any], defaults: dict[str, Any], path: str, value: Any) -> None:
    current = path_get(payload, path)
    base = path_get(defaults, path)
    if current is PATH_MISSING or values_equal(current, base):
        path_set(payload, path, value)


def load_resolved_config_payload(rel_path: str) -> tuple[dict[str, Any], list[str]]:
    scenario_path = resolve_scenario_path(rel_path)

    def _resolve_tree(config_path: Path, chain: list[str]) -> tuple[dict[str, Any], list[str]]:
        raw = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
        if not isinstance(raw, dict):
            raise ValueError(f"Config '{config_path}' must decode to a mapping.")
        inherits = raw.get("inherits", [])
        if isinstance(inherits, str):
            inherits = [inherits]
        merged: dict[str, Any] = {}
        for inherit_ref in inherits:
            parent_path = resolve_catalog_reference(config_path, str(inherit_ref))
            parent_payload, chain = _resolve_tree(parent_path, chain)
            merged = merge_config_dict(merged, parent_payload)
        raw_no_inherits = dict(raw)
        raw_no_inherits.pop("inherits", None)
        merged = merge_config_dict(merged, raw_no_inherits)
        chain.append(repo_relative_text(config_path))
        return merged, chain

    payload, chain = _resolve_tree(scenario_path, [])
    return canonicalize_browser_config_payload(payload), chain


def build_runtime_overlay_payload(scenario_name: str, payload: dict[str, Any]) -> dict[str, Any]:
    scenario_path = resolve_scenario_path(scenario_name)
    base_payload, _ = load_resolved_config_payload(scenario_name)
    base_with_aliases = canonicalize_browser_config_payload(base_payload, keep_legacy_aliases=True)
    payload_with_aliases = canonicalize_browser_config_payload(payload, keep_legacy_aliases=True)
    diff_payload = diff_config_value(base_with_aliases, payload_with_aliases)
    overlay = diff_payload if isinstance(diff_payload, dict) else {}
    overlay = copy.deepcopy(overlay)
    overlay["inherits"] = [f"./{scenario_path.name}"]
    return overlay


def scenario_identity_values(scenario_name: str, config_payload: dict[str, Any]) -> list[str]:
    values = [
        scenario_name,
        path_get(config_payload, "meta.scenario_id", ""),
        path_get(config_payload, "meta.scenario_group", ""),
        path_get(config_payload, "meta.scenario_name", ""),
        path_get(config_payload, "meta.baseline_reference_name", ""),
        path_get(config_payload, "scenario.name", ""),
    ]
    tags = path_get(config_payload, "meta.tags", [])
    if isinstance(tags, (list, tuple, set)):
        values.extend(tags)
    return [str(item).strip() for item in values if str(item).strip()]


def scenario_claims_waveform_truth(scenario_name: str, config_payload: dict[str, Any]) -> bool:
    for item in scenario_identity_values(scenario_name, config_payload):
        lowered = str(item).strip().lower()
        if any(token in lowered for token in WAVEFORM_TRUTH_IDENTITY_TOKENS):
            return True
    return False


def scenario_user_count(config_payload: dict[str, Any]) -> int:
    values = [
        path_get(config_payload, "users.n_users", 0),
        path_get(config_payload, "deployment_topology.num_ues", 0),
    ]
    numeric: list[int] = []
    for item in values:
        try:
            value = int(float(item))
        except (TypeError, ValueError):
            continue
        if value > 0:
            numeric.append(value)
    return max(numeric) if numeric else 0


def scenario_requested_total_slots(config_payload: dict[str, Any]) -> int:
    values = [
        path_get(config_payload, "run_control.total_slots", 0),
        path_get(config_payload, "simulation.n_slots", 0),
    ]
    numeric: list[int] = []
    for item in values:
        try:
            value = int(float(item))
        except (TypeError, ValueError):
            continue
        if value > 0:
            numeric.append(value)
    if numeric:
        return max(numeric)
    try:
        total_frames = int(float(path_get(config_payload, "run_control.total_frames", 0) or 0))
    except (TypeError, ValueError):
        total_frames = 0
    try:
        sim_frames = int(float(path_get(config_payload, "simulation.n_frames", 0) or 0))
    except (TypeError, ValueError):
        sim_frames = 0
    try:
        slots_per_frame = int(float(path_get(config_payload, "frame_timing.slots_per_frame", 0) or 0))
    except (TypeError, ValueError):
        slots_per_frame = 0
    if slots_per_frame <= 0:
        try:
            scs_khz = float(path_get(config_payload, "frame.scs_khz", 0) or 0)
            if scs_khz > 0:
                slots_per_frame = int(round(10 * (2 ** round(math.log2(scs_khz / 15.0)))))
        except (TypeError, ValueError, OverflowError):
            slots_per_frame = 0
    frame_count = max(total_frames, sim_frames)
    if frame_count > 0 and slots_per_frame > 0:
        return frame_count * slots_per_frame
    return 0


def scenario_duplex_mode(config_payload: dict[str, Any]) -> str:
    values = [
        path_get(config_payload, "frequency.duplex_mode", ""),
        path_get(config_payload, "global_radio_scope.duplex_mode", ""),
        path_get(config_payload, "phy.duplex.mode", ""),
        path_get(config_payload, "scenario.duplexMode", ""),
    ]
    for item in values:
        token = str(item or "").strip().upper()
        if token:
            return token
    return "TDD"


def scenario_tdd_pattern(config_payload: dict[str, Any]) -> str:
    values = [
        path_get(config_payload, "frame_timing.tdd_pattern", ""),
        path_get(config_payload, "frame.tdd_pattern", ""),
        path_get(config_payload, "phy.duplex.tddPattern", ""),
        path_get(config_payload, "scenario.tddPattern", ""),
    ]
    for item in values:
        token = str(item or "").strip().upper()
        if token:
            return token
    return "DDDSU"


def scenario_waveform_bundle_runtime_readiness(config_payload: dict[str, Any]) -> tuple[bool, str]:
    runner_profile = str(path_get(config_payload, "scenario.runner_profile", "") or "").strip().lower()
    if runner_profile != "waveform_bundle":
        return True, "Scenario does not request waveform_bundle dispatch."

    users_enabled = bool(path_get(config_payload, "users.enabled", False))
    execution_model = str(path_get(config_payload, "users.execution_model", "") or "").strip().lower()
    user_count = scenario_user_count(config_payload)
    total_slots = scenario_requested_total_slots(config_payload)
    duplex_mode = scenario_duplex_mode(config_payload)
    tdd_pattern = scenario_tdd_pattern(config_payload)

    if users_enabled and execution_model == "slot_coupled_truth" and user_count > 1 and duplex_mode == "TDD":
        reason = (
            "Waveform bundle launch is truth-ready for the coupled multi-user TDD path: the MATLAB "
            "runtime now preserves canonical slot accounting and applies the configured TDD duplex "
            "pattern inside the coupled waveform loop. "
            f"Requested users={user_count}, total_slots={total_slots or 'unavailable'}, "
            f"duplex_mode={duplex_mode}, tdd_pattern={tdd_pattern or 'unavailable'}."
        )
        return True, reason

    return True, "Waveform bundle dispatch is not blocked by the current browser launch contract."


def scenario_launch_contract(config_payload: dict[str, Any], scenario_name: str) -> dict[str, Any]:
    runner_profile = str(path_get(config_payload, "scenario.runner_profile", "") or "").strip()
    runner_profile_token = runner_profile.lower()
    scenario_id = str(path_get(config_payload, "meta.scenario_id", "") or "").strip()
    scenario_group = str(path_get(config_payload, "meta.scenario_group", "") or "").strip()
    tags = path_get(config_payload, "meta.tags", [])
    tag_values = [str(item).strip() for item in tags] if isinstance(tags, (list, tuple, set)) else []
    claims_waveform_truth = scenario_claims_waveform_truth(scenario_name, config_payload)
    runtime_truth_ready, runtime_truth_reason = scenario_waveform_bundle_runtime_readiness(config_payload)
    execution_model = str(path_get(config_payload, "users.execution_model", "") or "").strip()
    user_count = scenario_user_count(config_payload)
    total_slots = scenario_requested_total_slots(config_payload)

    if runner_profile_token == "waveform_bundle" and not runtime_truth_ready:
        presentation_label = "Waveform bundle truth blocked"
        launch_contract_name = "blocked_waveform_bundle_truth_gap"
        launch_allowed = False
        launch_reason = runtime_truth_reason
    elif runner_profile_token == "waveform_bundle":
        presentation_label = "Waveform bundle truth"
        launch_contract_name = "waveform_bundle_truth"
        launch_allowed = True
        launch_reason = runtime_truth_reason or (
            "Scenario identity and scenario.runner_profile agree on direct waveform_bundle dispatch."
        )
    elif runner_profile_token == "system_level_lls":
        presentation_label = "System-level LLS waveform-backed replay"
        if claims_waveform_truth:
            launch_contract_name = "blocked_mislabeled_waveform_truth"
            launch_allowed = False
            launch_reason = (
                "Scenario identity still claims waveform truth, but scenario.runner_profile resolves "
                "to 'system_level_lls'. Browser /run blocks this until the config truly dispatches "
                "to waveform_bundle or the scenario is relabeled honestly."
            )
        else:
            launch_contract_name = "system_level_lls_waveform_backed_replay"
            launch_allowed = True
            launch_reason = (
                "Scenario is honestly labeled for system_level_lls. Browser /run will follow the "
                "waveform-backed system-level replay path, not waveform_bundle truth."
            )
    elif claims_waveform_truth and runner_profile_token != "waveform_bundle":
        presentation_label = runner_profile or "unconfigured runner"
        launch_contract_name = "blocked_mislabeled_waveform_truth"
        launch_allowed = False
        launch_reason = (
            "Scenario identity claims waveform truth, but scenario.runner_profile is not "
            f"'waveform_bundle' (resolved value: {runner_profile or 'unconfigured'}). Browser /run "
            "blocks this until the launch contract is truthful."
        )
    else:
        presentation_label = runner_profile or "Unconfigured runner"
        launch_contract_name = "honest_non_waveform_bundle_runner"
        launch_allowed = True
        launch_reason = (
            "Browser /run will follow the configured scenario.runner_profile honestly."
            if runner_profile
            else "Scenario runner profile is not configured; browser /run will forward the current config as-is."
        )

    catalog_label = scenario_name
    if not launch_allowed:
        catalog_label = f"{scenario_name} [blocked: launch contract]"

    return {
        "scenario": scenario_name,
        "scenario_id": scenario_id,
        "scenario_group": scenario_group,
        "runner_profile": runner_profile,
        "claims_waveform_truth": claims_waveform_truth,
        "launch_allowed": launch_allowed,
        "launch_contract": launch_contract_name,
        "presentation_label": presentation_label,
        "launch_reason": launch_reason,
        "catalog_label": catalog_label,
        "tags": tag_values,
        "runtime_truth_ready": runtime_truth_ready,
        "runtime_truth_reason": runtime_truth_reason,
        "execution_model": execution_model,
        "user_count": user_count,
        "requested_total_slots": total_slots,
    }


@lru_cache(maxsize=128)
def resolved_scenario_launch_contract(scenario_name: str) -> dict[str, Any]:
    config_payload, _ = load_resolved_config_payload(scenario_name)
    return scenario_launch_contract(config_payload, scenario_name)


def scenario_catalog_label(scenario_name: str) -> str:
    try:
        return str(resolved_scenario_launch_contract(scenario_name)["catalog_label"])
    except Exception:
        return str(scenario_name)


def resolve_requested_launch_payload(
    scenario_name: str,
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    requested_payload = canonicalize_browser_config_payload(
        payload or {},
        keep_legacy_aliases=True,
    )
    if not scenario_name:
        return requested_payload
    base_payload, _ = load_resolved_config_payload(scenario_name)
    effective_payload = canonicalize_browser_config_payload(
        base_payload,
        keep_legacy_aliases=True,
    )
    if requested_payload:
        effective_payload = merge_config_dict(effective_payload, requested_payload)
    return effective_payload


def enforce_browser_launch_contract(
    scenario_name: str,
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    contract = scenario_launch_contract(
        resolve_requested_launch_payload(scenario_name, payload),
        scenario_name,
    )
    if not contract["launch_allowed"]:
        raise ValueError(str(contract["launch_reason"]))
    return contract


def default_json(value: Any):
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc).isoformat()
    if isinstance(value, (bytes, bytearray)):
        return value.decode("utf-8", errors="replace")
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


def sanitize_json_compatible(value: Any) -> Any:
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    if isinstance(value, dict):
        return {key: sanitize_json_compatible(item) for key, item in value.items()}
    if isinstance(value, list):
        return [sanitize_json_compatible(item) for item in value]
    if isinstance(value, tuple):
        return [sanitize_json_compatible(item) for item in value]
    return value


def json_bytes(payload: Any) -> bytes:
    safe_payload = sanitize_json_compatible(payload)
    return json.dumps(safe_payload, ensure_ascii=False, default=default_json, allow_nan=False).encode("utf-8")


def utc_iso(value: Any) -> str:
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc).isoformat()
    if value in (None, ""):
        return ""
    return str(value)


def rowify(row: dict[str, Any] | None) -> dict[str, Any] | None:
    if row is None:
        return None
    out = {}
    for key, value in row.items():
        out[key] = utc_iso(value) if isinstance(value, datetime) else value
    return out


def latest_run_id() -> int | None:
    try:
        mark_stale_running_runs()
        with db_connection() as conn:
            with conn.cursor(dictionary=True) as cur:
                cur.execute("SELECT run_id FROM sim_runs ORDER BY run_id DESC LIMIT 1")
                row = cur.fetchone()
                return None if row is None else int(row["run_id"])
    except mysql.connector.Error:
        return None


def _run_status_rank(status_text: Any, *, prefer_active: bool) -> int:
    token = str(status_text or "").strip().lower()
    if not token:
        return 0
    if any(key in token for key in ("queued", "launching", "running", "finalizing", "retry")):
        return 6 if prefer_active else 2
    if token == "completed":
        return 5 if not prefer_active else 4
    if token == "completed_with_failures":
        return 4 if not prefer_active else 3
    if token.startswith("aborted") or token.startswith("stalled"):
        return 1
    if token in {"failed", "timeout", "cancelled", "error"}:
        return 1
    return 2


def _date_parse_key(value: Any) -> float:
    if isinstance(value, datetime):
        try:
            return value.replace(tzinfo=timezone.utc).timestamp()
        except Exception:
            return 0.0
    if value in (None, ""):
        return 0.0
    text = str(value).strip()
    if not text:
        return 0.0
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()
    except Exception:
        return 0.0


def _select_preferred_run_row(rows: list[dict[str, Any]], *, prefer_active: bool) -> dict[str, Any] | None:
    if not rows:
        return None
    ordered = sorted(
        rows,
        key=lambda row: (
            _run_status_rank(row.get("status_text"), prefer_active=prefer_active),
            _date_parse_key(row.get("updated_utc")),
            _date_parse_key(row.get("created_utc")),
            int(row.get("run_id") or 0),
        ),
        reverse=True,
    )
    return ordered[0] if ordered else None


def preferred_live_run_id() -> int | None:
    row = _select_preferred_run_row(fetch_runs(limit=200), prefer_active=True)
    if not row:
        return None
    raw = row.get("run_id")
    return int(raw) if raw not in (None, "") else None


def preferred_analysis_run_id() -> int | None:
    row = _select_preferred_run_row(fetch_runs(limit=200), prefer_active=False)
    if not row:
        return None
    raw = row.get("run_id")
    return int(raw) if raw not in (None, "") else None


def fetch_runs(limit: int = 50, run_tag: str | None = None) -> list[dict[str, Any]]:
    try:
        mark_stale_running_runs()
        with db_connection() as conn:
            with conn.cursor(dictionary=True) as cur:
                sql = """
                    SELECT run_id, scenario_id, run_tag, profile_name, bucket, backend,
                           status_text, created_utc, updated_utc
                    FROM sim_runs
                """
                params: list[Any] = []
                if run_tag:
                    sql += " WHERE run_tag = %s"
                    params.append(run_tag)
                sql += " ORDER BY run_id DESC LIMIT %s"
                params.append(limit)
                cur.execute(sql, tuple(params))
                return [rowify(row) for row in cur.fetchall()]
    except mysql.connector.Error:
        return []


def fetch_run(run_id: int) -> dict[str, Any] | None:
    mark_stale_running_runs()
    with db_connection() as conn:
        with conn.cursor(dictionary=True) as cur:
            cur.execute(
                """
                SELECT run_id, run_uuid, scenario_id, run_tag, run_folder, bucket, profile_name,
                       backend, status_text, status_json, config_json, created_utc, updated_utc
                FROM sim_runs
                WHERE run_id = %s
                """,
                (run_id,),
            )
            return rowify(cur.fetchone())


def fetch_logs(run_id: int, limit: int = MAX_LIVE_LOG_ROWS, descending: bool = True) -> list[dict[str, Any]]:
    order = "DESC" if descending else "ASC"
    with db_connection() as conn:
        with conn.cursor(dictionary=True) as cur:
            cur.execute(
                f"""
                SELECT log_id, level_str, time_str, message_text, created_utc
                FROM sim_run_logs
                WHERE run_id = %s
                ORDER BY log_id {order}
                LIMIT %s
                """,
                (run_id, limit),
            )
            rows = [rowify(row) for row in cur.fetchall()]
    if descending:
        rows.reverse()
    return rows


def count_logs(run_id: int) -> int:
    with db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM sim_run_logs WHERE run_id=%s", (run_id,))
            row = cur.fetchone()
            return 0 if row is None else int(row[0])


def fetch_artifacts(
    run_id: int,
    kind_prefix: str | None = None,
    limit: int | None = None,
    newest_first: bool = False,
) -> list[dict[str, Any]]:
    sql = """
        SELECT artifact_id, run_id, logical_path, artifact_kind, mime_type,
               byte_size, created_utc
        FROM sim_artifacts
        WHERE run_id = %s
    """
    params: list[Any] = [run_id]
    if kind_prefix:
        sql += " AND artifact_kind LIKE %s"
        params.append(kind_prefix)
    order = "DESC" if newest_first else "ASC"
    sql += f" ORDER BY artifact_id {order}"
    if limit is not None:
        sql += " LIMIT %s"
        params.append(limit)
    with db_connection() as conn:
        with conn.cursor(dictionary=True) as cur:
            cur.execute(sql, tuple(params))
            rows = [rowify(row) for row in cur.fetchall()]
    if newest_first:
        rows.reverse()
    return rows


def fetch_artifact_meta(artifact_id: int) -> dict[str, Any] | None:
    with db_connection() as conn:
        with conn.cursor(dictionary=True) as cur:
            cur.execute(
                """
                SELECT artifact_id, run_id, logical_path, artifact_kind, mime_type,
                       byte_size, metadata_json, created_utc
                FROM sim_artifacts
                WHERE artifact_id = %s
                """,
                (artifact_id,),
            )
            return rowify(cur.fetchone())


@lru_cache(maxsize=1024)
def fetch_artifact_bytes(artifact_id: int) -> bytes:
    with db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT chunk_data
                FROM sim_artifact_chunks
                WHERE artifact_id = %s
                ORDER BY chunk_index ASC
                """,
                (artifact_id,),
            )
            return b"".join(bytes(chunk) for (chunk,) in cur.fetchall())


def artifact_url(artifact_id: int, download: bool = False) -> str:
    suffix = "?download=1" if download else ""
    return f"/artifact/{artifact_id}/raw{suffix}"


def artifact_etag(meta: dict[str, Any]) -> str:
    artifact_id = int(meta.get("artifact_id") or 0)
    byte_size = int(meta.get("byte_size") or 0)
    created = str(meta.get("created_utc") or "")
    return f'W/"artifact-{artifact_id}-{byte_size}-{created}"'


def format_status(value: str | None) -> str:
    raw = (value or "").strip().lower()
    cls = f"status-{raw}" if raw else ""
    return f'<span class="{cls}">{html.escape(value or "")}</span>'


def pretty_json(raw_value: Any) -> str:
    if raw_value in (None, "", b""):
        return "{}"
    if isinstance(raw_value, (dict, list)):
        return json.dumps(raw_value, indent=2, ensure_ascii=False)
    try:
        parsed = json.loads(raw_value)
    except Exception:
        return str(raw_value)
    return json.dumps(parsed, indent=2, ensure_ascii=False)


def json_for_script(value: Any) -> str:
    safe_value = sanitize_json_compatible(value)
    return json.dumps(safe_value, ensure_ascii=False, default=default_json, allow_nan=False).replace("</", "<\\/")


def render_log_lines(rows: list[dict[str, Any]]) -> str:
    if not rows:
        return "No log rows stored for this run yet."
    lines = []
    for row in rows:
        prefix = f"[{row.get('time_str') or row.get('created_utc')}] {row.get('level_str') or 'INFO'}"
        lines.append(f"{prefix} {row.get('message_text') or ''}")
    return "\n".join(lines)


def timestamp_tag(prefix: str) -> str:
    return f"{prefix}_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"


def safe_token(value: str) -> str:
    token = re.sub(r"[^A-Za-z0-9_.-]+", "_", value).strip("_.")
    return token or timestamp_tag("web")


def cleanup_runtime_yaml(folder: Path) -> None:
    cutoff = datetime.now(timezone.utc) - timedelta(days=2)
    for path in folder.glob("__web_runtime_*.yaml"):
        try:
            mtime = datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
            if mtime < cutoff:
                path.unlink(missing_ok=True)
        except OSError:
            continue


def normalize_run_yaml(raw_text: str, scenario_name: str | None = None) -> str:
    def _coerce_scalar_strings(value: Any, path: str = "") -> Any:
        if isinstance(value, dict):
            out: dict[str, Any] = {}
            for key, item in value.items():
                child_path = f"{path}.{key}" if path else str(key)
                out[key] = _coerce_scalar_strings(item, child_path)
            return out
        if isinstance(value, list):
            return [_coerce_scalar_strings(item, path) for item in value]
        if isinstance(value, str):
            text = value.strip()
            declared_type = schema_type_for_path(path)
            lowered = text.lower()
            if declared_type == "boolean" and lowered in {"true", "false"}:
                return lowered == "true"
            if declared_type == "integer" and re.fullmatch(r"[+-]?\d+", text):
                try:
                    return int(text)
                except ValueError:
                    return value
            if declared_type == "number" and re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", text):
                try:
                    return float(text)
                except ValueError:
                    return value
        return value

    payload = yaml.safe_load(raw_text) or {}
    if not isinstance(payload, dict):
        raise ValueError("Scenario YAML must decode to a mapping at the top level.")
    payload = _coerce_scalar_strings(payload)
    payload = canonicalize_browser_config_payload(payload, keep_legacy_aliases=True)
    if scenario_name:
        payload = build_runtime_overlay_payload(str(scenario_name), payload)
    for _, old_path, _ in BROWSER_ALIAS_RULES:
        if not schema_type_for_path(old_path):
            path_delete(payload, old_path)
    payload = _coerce_scalar_strings(payload)
    output_cfg = payload.get("output")
    if output_cfg is None or not isinstance(output_cfg, dict):
        output_cfg = {}
    output_cfg["backend"] = "mysql_web"
    output_cfg["database_host"] = MYSQL_HOST
    output_cfg["database_port"] = MYSQL_PORT
    output_cfg["database_schema"] = MYSQL_DATABASE
    payload["output"] = output_cfg
    # Emit JSON text on disk even for .yaml runtime files. YAML parsers accept JSON as a
    # subset, and this preserves numeric types like 1e-6 without PyYAML re-emitting them
    # into a plain-scalar form that later reloads as a string.
    return json.dumps(payload, indent=2, ensure_ascii=False)


def matlab_literal(text: str) -> str:
    return text.replace("'", "''")


def launch_run_from_yaml(scenario_name: str, yaml_text: str, run_tag: str) -> tuple[str, Path, Path]:
    scenario_path = resolve_scenario_path(scenario_name)
    cleanup_runtime_yaml(scenario_path.parent)

    normalized_yaml = normalize_run_yaml(yaml_text, scenario_name)
    token = safe_token(run_tag)
    runtime_path = scenario_path.with_name(f"__web_runtime_{token}.yaml")
    runtime_path.write_text(normalized_yaml, encoding="utf-8")

    RUNTIME_LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_file = RUNTIME_LOG_DIR / f"{token}.log"
    cursor_file = RUNTIME_LOG_DIR / f"{token}.offset.json"
    cursor_file.unlink(missing_ok=True)

    env = os.environ.copy()
    env["MYSQL_HOST"] = MYSQL_HOST
    env["MYSQL_PORT"] = str(MYSQL_PORT)
    env["MYSQL_USER"] = MYSQL_USER
    env["MYSQL_PASSWORD"] = MYSQL_PASSWORD
    env["MYSQL_DATABASE"] = MYSQL_DATABASE

    rel_runtime_path = runtime_path.relative_to(REPO_ROOT).as_posix()
    repo_root_literal = matlab_literal(str(REPO_ROOT))
    batch_cmd = (
        f"cd('{repo_root_literal}'); "
        f"addpath('{repo_root_literal}','-begin'); "
        "rehash; "
        "setup6GRSimToolkit('Verbose',false); "
        f"run_6g_phy_lls_single('{matlab_literal(rel_runtime_path)}','results','{matlab_literal(token)}');"
    )
    creationflags = 0
    if os.name == "nt":
        creationflags = (
            getattr(subprocess, "DETACHED_PROCESS", 0)
            | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
        )
    with log_file.open("w", encoding="utf-8") as handle:
        proc = subprocess.Popen(
            [str(MATLAB_EXE), "-sd", str(REPO_ROOT), "-batch", batch_cmd],
            cwd=str(REPO_ROOT),
            env=env,
            stdout=handle,
            stderr=subprocess.STDOUT,
            creationflags=creationflags,
        )
    pid_path = runtime_pid_file(token)
    if pid_path is not None:
        pid_path.write_text(
            json.dumps(
                {
                    "pid": int(proc.pid),
                    "run_tag": token,
                    "runtime_yaml": str(runtime_path.name),
                    "log_file": str(log_file.name),
                    "launched_utc": datetime.now(timezone.utc).isoformat(),
                },
                indent=2,
            ),
            encoding="utf-8",
        )
    return token, log_file, runtime_path


def runtime_log_file(run_tag: str | None) -> Path | None:
    token = safe_token(str(run_tag or ""))
    if not token:
        return None
    return RUNTIME_LOG_DIR / f"{token}.log"


def runtime_pid_file(run_tag: str | None) -> Path | None:
    token = safe_token(str(run_tag or ""))
    if not token:
        return None
    return RUNTIME_LOG_DIR / f"{token}.pid.json"


def runtime_log_cursor_file(run_tag: str | None) -> Path | None:
    token = safe_token(str(run_tag or ""))
    if not token:
        return None
    return RUNTIME_LOG_DIR / f"{token}.offset.json"


def dashboard_listener_file() -> Path:
    return RUNTIME_LOG_DIR / "dashboard_listener.json"


def write_dashboard_listener_file(
    bind_host: str,
    actual_port: int,
    local_url: str,
    intranet_url: str,
    lan_urls: list[str],
) -> None:
    RUNTIME_LOG_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "bind_host": str(bind_host),
        "port": int(actual_port),
        "local_url": str(local_url),
        "intranet_url": str(intranet_url),
        "lan_urls": [str(url) for url in lan_urls],
        "written_utc": datetime.now(timezone.utc).isoformat(),
    }
    dashboard_listener_file().write_text(json.dumps(payload, indent=2), encoding="utf-8")


def now_utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def classify_log_level(line: str) -> str:
    text = re.sub(r"[\x00-\x1f]+", " ", line).strip().lower()
    if "[fail]" in text or text.startswith("error:") or " exception" in text or " access is denied" in text:
        return "ERROR"
    if "warning" in text:
        return "WARN"
    if "[pass]" in text:
        return "PASS"
    if "[setup]" in text or "started run" in text:
        return "SETUP"
    return "INFO"


def extract_log_time(line: str) -> str:
    match = re.search(r"(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?)", line)
    if match:
        stamp = match.group(1).replace(" ", "T")
        return stamp if stamp.endswith("Z") else f"{stamp}Z"
    return now_utc_stamp()


def load_runtime_cursor(path: Path | None) -> dict[str, Any]:
    if path is None or not path.is_file():
        return {"offset": 0, "carry": ""}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {"offset": 0, "carry": ""}
    return {
        "offset": int(payload.get("offset", 0) or 0),
        "carry": str(payload.get("carry", "") or ""),
    }


def save_runtime_cursor(path: Path | None, payload: dict[str, Any]) -> None:
    if path is None:
        return
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def append_runtime_log_rows(run_id: int, rows: list[tuple[str, str, str]]) -> int:
    if not rows:
        return 0
    with db_connection() as conn:
        with conn.cursor() as cur:
            cur.executemany(
                """
                INSERT INTO sim_run_logs (run_id, level_str, time_str, message_text, created_utc)
                VALUES (%s, %s, %s, %s, UTC_TIMESTAMP())
                """,
                [(run_id, level, time_str, message) for (level, time_str, message) in rows],
            )
            cur.execute("UPDATE sim_runs SET updated_utc=UTC_TIMESTAMP() WHERE run_id=%s", (run_id,))
    return len(rows)


def sync_runtime_log_for_run(run_row: dict[str, Any] | None) -> int:
    if not run_row:
        return 0
    raw_run_id = run_row.get("run_id")
    if raw_run_id in (None, ""):
        return 0
    run_id = int(raw_run_id)
    log_path = runtime_log_file(str(run_row.get("run_tag") or ""))
    cursor_path = runtime_log_cursor_file(str(run_row.get("run_tag") or ""))
    if log_path is None or not log_path.is_file():
        return 0

    cursor = load_runtime_cursor(cursor_path)
    offset = max(0, int(cursor.get("offset", 0) or 0))
    carry = str(cursor.get("carry", "") or "")
    file_size = log_path.stat().st_size
    if offset > file_size:
        offset = 0
        carry = ""

    with log_path.open("rb") as handle:
        handle.seek(offset)
        raw = handle.read()
        new_offset = handle.tell()
    if not raw:
        return 0

    text = carry + raw.decode("utf-8", errors="replace")
    pieces = text.splitlines(keepends=True)
    complete_lines: list[str] = []
    next_carry = ""
    for piece in pieces:
        if piece.endswith("\n") or piece.endswith("\r"):
            complete_lines.append(piece.rstrip("\r\n"))
        else:
            next_carry += piece

    rows = [
        (
            classify_log_level(line),
            extract_log_time(line),
            re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]+", " ", line).strip(),
        )
        for line in complete_lines
        if line.strip()
    ]
    inserted = append_runtime_log_rows(run_id, rows)
    save_runtime_cursor(cursor_path, {"offset": new_offset, "carry": next_carry})
    return inserted


def parse_optional_int(raw: str | None) -> int | None:
    if raw in (None, "", "None"):
        return None
    return int(raw)


def parse_csv_bytes(raw: bytes, max_rows: int | None = None) -> tuple[list[str], list[list[str]]]:
    text = raw.decode("utf-8", errors="replace")
    rows = list(csv.reader(io.StringIO(text)))
    header = normalize_csv_header_row(rows[0] if rows else [])
    body = rows[1:] if len(rows) > 1 else []
    if max_rows is not None:
        body = body[:max_rows]
    return header, body


HEADER_REMAP = {
    "!Case": "Case",
    "!Direction": "Direction",
    "!ScenarioID": "ScenarioID",
    "+Direction": "Direction",
    "QStageOrder": "StageOrder",
    "ZCase": "Case",
    "c/uRelativePath": "RelativePath",
}


def normalize_csv_header_name(name: Any) -> str:
    raw = str(name or "").strip()
    if raw in HEADER_REMAP:
        return HEADER_REMAP[raw]
    normalized = raw
    normalized = re.sub(r"^[!+]+", "", normalized)
    if normalized.startswith("Q") and len(normalized) > 1 and normalized[1].isupper():
        normalized = normalized[1:]
    if normalized.startswith("Z") and len(normalized) > 1 and normalized[1].isupper():
        normalized = normalized[1:]
    normalized = normalized.replace("c/u", "")
    return normalized or raw


def normalize_csv_header_row(header: list[str]) -> list[str]:
    return [normalize_csv_header_name(name) for name in list(header or [])]


def build_table_preview_payload(artifact_id: int) -> dict[str, Any] | None:
    meta = fetch_artifact_meta(artifact_id)
    if meta is None:
        return None
    header, rows = load_cached_csv_preview(int(artifact_id), MAX_TABLE_PREVIEW_ROWS)
    return {"meta": meta, "header": header, "rows": rows}


@lru_cache(maxsize=512)
def load_cached_csv_preview(artifact_id: int, max_rows: int) -> tuple[list[str], list[list[str]]]:
    return parse_csv_bytes(fetch_artifact_bytes(int(artifact_id)), max_rows=max_rows)


@lru_cache(maxsize=1024)
def load_cached_csv_rows(artifact_id: int, max_rows: int) -> tuple[tuple[str, ...], tuple[tuple[Any, ...], ...]]:
    header, rows = load_cached_csv_preview(int(artifact_id), max_rows)
    if not header:
        return tuple(), tuple()
    records: list[tuple[Any, ...]] = []
    for row in rows:
        values: list[Any] = []
        for idx, _name in enumerate(header):
            raw = row[idx] if idx < len(row) else ""
            numeric = coerce_numeric(raw)
            values.append(numeric if numeric is not None else raw)
        records.append(tuple(values))
    return tuple(header), tuple(records)


def coerce_numeric(value: str) -> float | None:
    if value is None:
        return None
    text = str(value).strip()
    if text == "":
        return None
    if text.lower() in {"true", "false"}:
        return 1.0 if text.lower() == "true" else 0.0
    try:
        return float(text)
    except ValueError:
        return None


def is_truthy_value(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    numeric = coerce_numeric(value)
    if numeric is not None:
        return abs(float(numeric)) > 0
    token = str(value or "").strip().lower()
    return token in {"true", "yes", "on", "enabled"}


def humanize_key(text: str) -> str:
    out = re.sub(r"[_/]+", " ", str(text))
    out = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", out)
    out = re.sub(r"\s+", " ", out).strip()
    return out.title()


def resolve_field_label(path: str) -> str:
    normalized = str(path or "").strip().lower()
    if normalized in FIELD_LABEL_OVERRIDES:
        return FIELD_LABEL_OVERRIDES[normalized]
    return humanize_key(path.split(".")[-1] if path else "value")


def format_value_with_unit(value: Any, unit: str = "") -> str:
    text = str(value if value not in (None, "") else "n/a")
    if text == "n/a" or not unit:
        return text
    return f"{text} {unit}"


FIELD_OPTION_HINTS: dict[str, list[str]] = {
    "output.backend": ["mysql_web", "filesystem"],
    "output.bucket": ["lls", "sls", "e2e"],
    "run_control.execution_mode": BROWSER_EXECUTION_MODE_OPTIONS,
    "run_control.study_mode": ["smoke", "debug", "baseline", "campaign", "publication"],
    "run_control.simulation_mode": ["full_phy"],
    "run_control.run_profile": ["quick", "normal", "exhaustive", "very_long_run"],
    "mobility.trajectory_model": ["randomWaypoint", "straightLine", "zigzag", "trace", "linear"],
    "channels.doppler_source_mode": ["configured", "derive_from_ue_speed"],
    "channel_model.doppler_source_mode": ["configured", "derive_from_ue_speed"],
    "simulation.noise_operating_mode": ["receiver_noise_figure_thermal_noise", "configured_snr_anchor_after_large_scale_gain"],
    "interference.inter_cell_execution_mode": ["full_per_link_channel_waveform_sum", "none"],
    "simulation.link_direction": ["DL", "UL", "BIDIR"],
    "traffic.flowdirection": ["DL", "UL", "BIDIR"],
    "traffic.transport": ["UDP", "TCP"],
    "phy.duplex.mode": ["TDD", "FDD"],
    "phy.waveform.dl": ["CP-OFDM", "DFT-s-OFDM"],
    "phy.waveform.ul": ["CP-OFDM", "DFT-s-OFDM"],
    "channel.type": ["AWGN", "TDL-A", "TDL-B", "TDL-C", "CDL-A", "CDL-B", "CDL-C", "CDL-D", "CDL-E"],
    "channel.interference.model": ["fullReuse", "none"],
    "channel.pathloss.model": ["nrPathLoss", "freeSpace"],
    "phy.pdsch.cqitable": ["table1", "table2"],
    "phy.pusch.cqitable": ["table1", "table2"],
    "phy.pdsch.mcstable": ["qam64_table1", "qam64_table2", "qam256_table1", "qam256_table2"],
    "phy.pusch.mcstable": ["qam64_table1", "qam64_table2", "qam256_table1", "qam256_table2"],
    "random_access.frequency_range": ["FR1", "FR2"],
    "random_access.duplex_mode": ["FDD", "TDD"],
    "random_access.carrier_scs_khz": ["15", "30", "60", "120"],
    "random_access.prach_format": ["0", "1", "2", "3", "A1", "A2", "A3", "B1", "B4", "C0", "C2"],
    "random_access.subcarrier_spacing_khz": ["1.25", "5", "15", "30", "60", "120"],
    "random_access.restricted_set": ["UnrestrictedSet", "RestrictedSet"],
    "random_access.detection_threshold_mode": ["fixed", "auto"],
    "random_access.channel_model": ["AWGN", "TDL-A", "TDL-C", "CDL-C"],
    "phy.rx.channelestimation": ["DMRS", "Perfect"],
    "phy.rx.equalizer": ["MMSE", "ZF"],
    "phy.rx.mimodetector": ["MMSE", "ZF", "ML"],
    "mac.scheduler.type": ["PF", "RR"],
    "system.scheduler.type": ["PF", "RR", "LATENCY_AWARE_PF", "ENERGY_AWARE_PF", "MAX_CQI"],
    "mac.scheduler.tbsmode": ["approximate", "faithful"],
    "logging.level": ["debug", "info", "warning", "error"],
    "scenario.runner_profile": [
        "waveform_bundle",
        "system_level_lls",
        "prach_detection",
        "pdcch_blind_decode_sweep",
        "ctrl6gr_pdcch_study",
        "generic_sweep",
        "ai_benchmark",
    ],
}

FIELD_LABEL_OVERRIDES: dict[str, str] = {
    "run_control.execution_mode": "Execution Mode",
    "control_gating.pbch_required": "PBCH Gating Required",
    "control_gating.prach_required": "PRACH Gating Required",
    "control_gating.pdcch_required": "PDCCH Gating Required",
    "control_gating.srs_required": "SRS/CSI Gating Required",
    "control_gating.srs_max_age_slots": "Max SRS Age (slots)",
    "mobility.ue_speed_kmh": "UE Speed (km/h)",
    "channels.mobility_kmph": "UE Speed Alias (km/h)",
    "scenario.mobility.speed_kmh": "Resolved Mobility Speed (km/h)",
    "scenario.mobility.speed_mps": "Resolved Mobility Speed (m/s)",
    "channels.doppler_hz": "Doppler (Hz)",
    "channel_model.doppler_hz": "Doppler (Hz)",
    "channels.doppler_source_mode": "Doppler Source Mode",
    "channel_model.doppler_source_mode": "Doppler Source Mode",
    "random_access.configuration_index": "PRACH Config Index",
    "random_access.sequence_index": "PRACH Sequence Index",
    "random_access.logical_root_sequence_index": "Logical Root Sequence Index",
    "random_access.root_sequence_index": "Legacy Root Sequence Index",
    "random_access.frequency_start": "PRACH Frequency Start",
    "random_access.num_prach_occasions": "PRACH Occasions",
    "random_access.num_ues_per_ro": "UEs Per RO",
    "random_access.enable_collision_mode": "Collision Mode",
    "random_access.enable_inter_cell_interference": "Inter-Cell PRACH Interference",
    "random_access.enable_frequency_offset": "Enable PRACH CFO",
    "random_access.enable_phase_noise": "Enable Phase Noise",
    "random_access.enable_timing_uncertainty": "Enable Timing Uncertainty",
    "random_access.enable_frequency_estimation_metric": "Enable CFO Estimation Metric",
    "random_access.ue_frequency_offset_hz": "UE CFO (Hz)",
    "random_access.trp_frequency_offset_hz": "TRP CFO (Hz)",
    "random_access.delay_spread_ns": "Delay Spread (ns)",
    "random_access.speed_kmh": "PRACH Speed (km/h)",
    "random_access.cell_radius_m": "Cell Radius (m)",
    "random_access.timing_uncertainty_max_us": "Max Timing Uncertainty (us)",
    "random_access.timing_tolerance_us": "Timing Tolerance (us)",
    "random_access.snr_sweep_db": "PRACH SNR Sweep (dB)",
    "random_access.threshold_sweep": "PRACH Threshold Sweep",
}


def scalar_option_text(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        if not (value == value and value not in (float("inf"), float("-inf"))):
            return None
        if float(value).is_integer():
            return str(int(value))
        return format(value, "g")
    if isinstance(value, str):
        token = value.strip()
        return token if token else None
    return None


def append_unique_options(target: list[str], values: list[Any] | tuple[Any, ...] | None) -> None:
    if not values:
        return
    seen = {item.lower() for item in target}
    for raw in values:
        text = scalar_option_text(raw)
        if not text:
            continue
        key = text.lower()
        if key in seen:
            continue
        target.append(text)
        seen.add(key)


def merge_schema_catalog(base: dict[str, Any], incoming: dict[str, Any]) -> dict[str, Any]:
    merged = merge_config_dict(base, {})
    for key in ("sections", "nested_sections"):
        existing = merged.get(key, {})
        addition = incoming.get(key, {})
        if isinstance(existing, dict) and isinstance(addition, dict):
            merged[key] = merge_config_dict(existing, addition)
    return merged


@lru_cache(maxsize=1)
def load_schema_catalog() -> dict[str, Any]:
    schema_root = REPO_ROOT / "simulator" / "configs" / "schema"
    merged: dict[str, Any] = {"sections": {}, "nested_sections": {}}
    for schema_path in sorted(schema_root.glob("*.yaml")):
        raw = yaml.safe_load(schema_path.read_text(encoding="utf-8")) or {}
        if isinstance(raw, dict):
            merged = merge_schema_catalog(merged, raw)
    return merged


def option_values_from_param_meta(param_meta: dict[str, Any]) -> list[str]:
    options: list[str] = []
    if str(param_meta.get("type") or "").lower() == "boolean":
        append_unique_options(options, ["true", "false"])
    append_unique_options(options, param_meta.get("allowed_values"))
    append_unique_options(options, param_meta.get("allowed_numeric_values"))
    append_unique_options(options, param_meta.get("recommended_values"))
    return options


@lru_cache(maxsize=1)
def build_schema_option_indices() -> tuple[dict[str, list[str]], dict[str, list[str]], dict[str, list[str]]]:
    catalog = load_schema_catalog()
    sections = catalog.get("sections", {}) if isinstance(catalog.get("sections"), dict) else {}
    nested_sections = catalog.get("nested_sections", {}) if isinstance(catalog.get("nested_sections"), dict) else {}
    exact_index: dict[str, list[str]] = {}
    suffix_index: dict[str, list[str]] = {}
    leaf_index: dict[str, list[str]] = {}

    def record(path_parts: list[str], param_meta: dict[str, Any]) -> None:
        options = option_values_from_param_meta(param_meta)
        if not options:
            return
        exact_key = ".".join(path_parts).lower()
        append_unique_options(exact_index.setdefault(exact_key, []), options)
        if len(path_parts) >= 2:
            suffix_key = ".".join(path_parts[-2:]).lower()
            append_unique_options(suffix_index.setdefault(suffix_key, []), options)
        leaf_key = path_parts[-1].lower()
        append_unique_options(leaf_index.setdefault(leaf_key, []), options)

    def walk_parameters(path_parts: list[str], parameters: dict[str, Any]) -> None:
        for name, param_meta in parameters.items():
            if not isinstance(param_meta, dict):
                continue
            current_path = path_parts + [str(name)]
            nested_rule = param_meta.get("nested_rule")
            if isinstance(nested_rule, str):
                nested_spec = nested_sections.get(nested_rule, {})
                nested_params = nested_spec.get("parameters", {}) if isinstance(nested_spec, dict) else {}
                if isinstance(nested_params, dict) and nested_params:
                    walk_parameters(current_path, nested_params)
            record(current_path, param_meta)

    for section_name, section_spec in sections.items():
        if not isinstance(section_spec, dict):
            continue
        params = section_spec.get("parameters", {})
        if isinstance(params, dict):
            walk_parameters([str(section_name)], params)
    return exact_index, suffix_index, leaf_index


@lru_cache(maxsize=1)
def build_schema_type_index() -> dict[str, str]:
    catalog = load_schema_catalog()
    sections = catalog.get("sections", {}) if isinstance(catalog.get("sections"), dict) else {}
    nested_sections = catalog.get("nested_sections", {}) if isinstance(catalog.get("nested_sections"), dict) else {}
    exact_index: dict[str, str] = {}

    def walk_parameters(path_parts: list[str], parameters: dict[str, Any]) -> None:
        for name, param_meta in parameters.items():
            if not isinstance(param_meta, dict):
                continue
            current_path = path_parts + [str(name)]
            declared_type = str(param_meta.get("type") or "").strip().lower()
            if declared_type:
                exact_index[".".join(current_path).lower()] = declared_type
            nested_rule = param_meta.get("nested_rule")
            if isinstance(nested_rule, str):
                nested_spec = nested_sections.get(nested_rule, {})
                nested_params = nested_spec.get("parameters", {}) if isinstance(nested_spec, dict) else {}
                if isinstance(nested_params, dict) and nested_params:
                    walk_parameters(current_path, nested_params)

    for section_name, section_spec in sections.items():
        if not isinstance(section_spec, dict):
            continue
        params = section_spec.get("parameters", {})
        if isinstance(params, dict):
            walk_parameters([str(section_name)], params)
    return exact_index


def schema_type_for_path(path: str) -> str:
    return build_schema_type_index().get(str(path or "").strip().lower(), "")


def iter_yaml_scalar_paths(node: Any, prefix: str = ""):
    if isinstance(node, dict):
        for key, child in node.items():
            child_path = f"{prefix}.{key}" if prefix else str(key)
            yield from iter_yaml_scalar_paths(child, child_path)
        return
    if isinstance(node, list):
        for item in node:
            if isinstance(item, (dict, list)):
                yield from iter_yaml_scalar_paths(item, prefix)
                continue
            text = scalar_option_text(item)
            if text is not None and prefix:
                yield prefix, text
        return
    text = scalar_option_text(node)
    if text is not None and prefix:
        yield prefix, text


@lru_cache(maxsize=1)
def build_repo_option_indices() -> tuple[dict[str, list[str]], dict[str, list[str]], dict[str, list[str]]]:
    config_root = REPO_ROOT / "simulator" / "configs"
    exact_index: dict[str, list[str]] = {}
    suffix_index: dict[str, list[str]] = {}
    leaf_index: dict[str, list[str]] = {}
    for yaml_path in sorted(config_root.rglob("*.yaml")):
        if yaml_path.name.startswith("__web_runtime_"):
            continue
        try:
            raw = yaml.safe_load(yaml_path.read_text(encoding="utf-8")) or {}
        except Exception:
            continue
        for path, text in iter_yaml_scalar_paths(raw):
            exact_key = path.lower()
            append_unique_options(exact_index.setdefault(exact_key, []), [text])
            parts = exact_key.split(".")
            if len(parts) >= 2:
                suffix_key = ".".join(parts[-2:])
                append_unique_options(suffix_index.setdefault(suffix_key, []), [text])
            leaf_key = parts[-1]
            append_unique_options(leaf_index.setdefault(leaf_key, []), [text])
    return exact_index, suffix_index, leaf_index


@lru_cache(maxsize=1)
def build_browser_alias_lookup() -> dict[str, list[str]]:
    lookup: dict[str, list[str]] = {}
    for new_path, old_path, _ in BROWSER_ALIAS_RULES:
        if new_path == old_path:
            continue
        new_key = new_path.lower()
        old_key = old_path.lower()
        lookup.setdefault(new_key, []).append(old_key)
        lookup.setdefault(old_key, []).append(new_key)
    for path, aliases in BROWSER_OPTION_SOURCE_ALIASES.items():
        key = path.lower()
        for alias in aliases:
            alias_key = alias.lower()
            lookup.setdefault(key, []).append(alias_key)
            lookup.setdefault(alias_key, []).append(key)
    return lookup


def field_options_for_path(path: str, value: Any) -> list[str] | None:
    normalized = path.lower()
    if isinstance(value, bool):
        return ["true", "false"]
    schema_exact, schema_suffix, schema_leaf = build_schema_option_indices()
    repo_exact, repo_suffix, repo_leaf = build_repo_option_indices()
    combined: list[str] = []
    authoritative: list[str] = []
    suffix = ".".join(normalized.split(".")[-2:]) if "." in normalized else normalized
    leaf = normalized.split(".")[-1]
    alias_lookup = build_browser_alias_lookup()

    def append_from_indices(exact_key: str | None, suffix_key: str | None, leaf_key: str | None) -> None:
        if exact_key:
            append_unique_options(authoritative, schema_exact.get(exact_key))
            append_unique_options(combined, schema_exact.get(exact_key))
            append_unique_options(combined, repo_exact.get(exact_key))
        if suffix_key:
            append_unique_options(authoritative, schema_suffix.get(suffix_key))
            append_unique_options(combined, schema_suffix.get(suffix_key))
            append_unique_options(combined, repo_suffix.get(suffix_key))
        if leaf_key and leaf_key not in GENERIC_OPTION_LEAVES and len(combined) <= 1:
            append_unique_options(authoritative, schema_leaf.get(leaf_key))
            append_unique_options(combined, schema_leaf.get(leaf_key))
            append_unique_options(combined, repo_leaf.get(leaf_key))

    append_from_indices(normalized, suffix, leaf)
    for alias_path in alias_lookup.get(normalized, []):
        alias_suffix = ".".join(alias_path.split(".")[-2:]) if "." in alias_path else alias_path
        alias_leaf = alias_path.split(".")[-1]
        append_from_indices(alias_path, alias_suffix, alias_leaf)
    for key, options in FIELD_OPTION_HINTS.items():
        if normalized.endswith(key):
            append_unique_options(authoritative, options)
            append_unique_options(combined, options)
        elif key.endswith(f".{leaf}"):
            append_unique_options(authoritative, options)
            append_unique_options(combined, options)
    if not authoritative:
        current_text = scalar_option_text(value)
        if current_text:
            append_unique_options(combined, [current_text])
        return None if len(combined) <= 1 else combined
    if not combined:
        return None
    current_text = scalar_option_text(value)
    if current_text:
        append_unique_options(combined, [current_text])
    if len(combined) <= 1:
        return None
    return combined or None


def build_field_search_text(path: str, label: str, value: Any, options: list[str] | None) -> str:
    segments = [seg for seg in path.split(".") if seg]
    parts = [
        path,
        path.replace(".", " "),
        path.replace(".", "_"),
        humanize_key(path),
        label,
        str(value),
    ]
    parts.extend(segments)
    parts.extend(humanize_key(seg) for seg in segments)
    if len(segments) >= 2:
        parts.append(" ".join(segments[-2:]))
        parts.append(" ".join(humanize_key(seg) for seg in segments[-2:]))
    if options:
        parts.extend(options)
    return " ".join(str(item) for item in parts if item).lower()


def flatten_config_fields(value: Any, prefix: str = "") -> list[dict[str, Any]]:
    fields: list[dict[str, Any]] = []
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{prefix}.{key}" if prefix else str(key)
            fields.extend(flatten_config_fields(child, child_path))
        return fields

    group = prefix.split(".")[0] if prefix else "general"
    home_group = resolve_home_group(prefix)
    support_state, support_note = classify_browser_field_support(prefix)
    label = resolve_field_label(prefix)
    entry: dict[str, Any] = {
        "path": prefix,
        "label": label,
        "group": group,
        "group_label": humanize_key(group),
        "home_group": home_group,
        "home_group_label": HOME_GROUP_LABELS.get(home_group, humanize_key(home_group)),
        "support_state": support_state,
        "support_note": support_note,
    }

    if isinstance(value, bool):
        entry.update({"kind": "bool", "value": "true" if value else "false", "options": ["true", "false"]})
    elif isinstance(value, int) and not isinstance(value, bool):
        entry.update({"kind": "int", "value": str(value), "options": field_options_for_path(prefix, value)})
    elif isinstance(value, float):
        entry.update({"kind": "float", "value": str(value), "options": field_options_for_path(prefix, value)})
    elif isinstance(value, str):
        entry.update({"kind": "text", "value": value, "options": field_options_for_path(prefix, value)})
    else:
        entry.update({"kind": "json", "value": json.dumps(value, ensure_ascii=False), "options": None})
    entry["search_text"] = build_field_search_text(prefix, label, entry["value"], entry.get("options")) + " " + support_state + " " + support_note.lower()
    fields.append(entry)
    return fields


def group_config_fields(fields: list[dict[str, Any]]) -> list[tuple[str, list[dict[str, Any]]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for field in fields:
        grouped.setdefault(field["home_group"], []).append(field)
    order_lookup = {name: idx for idx, name in enumerate(HOME_GROUP_ORDER)}
    ordered = sorted(grouped.items(), key=lambda item: (order_lookup.get(item[0], len(HOME_GROUP_ORDER)), item[0]))
    for _, items in ordered:
        items.sort(key=lambda field: field["path"])
    return ordered


def infer_browser_truth_modes(config_payload: dict[str, Any]) -> dict[str, str]:
    browser_mode = str(path_get(config_payload, "run_control.execution_mode", "LLS") or "LLS").strip().upper()
    if browser_mode not in BROWSER_EXECUTION_MODE_OPTIONS:
        browser_mode = "LLS"
    multi_user_enabled = bool(path_get(config_payload, "users.enabled", False))
    num_users = path_get(config_payload, "users.n_users", path_get(config_payload, "deployment_topology.num_ues", ""))
    execution_model = str(path_get(config_payload, "users.execution_model", "independent_link_sweep") or "").strip()
    doppler_source_mode = str(
        path_get(
            config_payload,
            "channels.doppler_source_mode",
            path_get(config_payload, "channel_model.doppler_source_mode", "configured"),
        )
        or ""
    ).strip()
    interference_mode = str(
        path_get(
            config_payload,
            "interference.inter_cell_execution_mode",
            "full_per_link_channel_waveform_sum" if multi_user_enabled and execution_model == "slot_coupled_truth" else "none",
        )
        or ""
    ).strip()
    pbch_required = bool(path_get(config_payload, "control_gating.pbch_required", path_get(config_payload, "reference_signals.pbch_enabled", False)))
    prach_required = bool(path_get(config_payload, "control_gating.prach_required", path_get(config_payload, "random_access.enabled", False)))
    pdcch_required = bool(path_get(config_payload, "control_gating.pdcch_required", path_get(config_payload, "control.pdcch_enabled", False)))
    srs_required = bool(path_get(config_payload, "control_gating.srs_required", path_get(config_payload, "reference_signals.srs_enabled", False)))
    control_mode = "runtime_control_access_state_gated" if execution_model == "slot_coupled_truth" and any((pbch_required, prach_required, pdcch_required, srs_required)) else "independent_signal_bundle"
    sweep_enabled = bool(path_get(config_payload, "sweeps_and_matrix.snr_sweep.enabled", False))
    noise_mode = str(
        path_get(
            config_payload,
            "simulation.noise_operating_mode",
            path_get(config_payload, "simulation.operating_point_mode", "configured_snr_anchor_after_large_scale_gain"),
        )
        or ""
    ).strip()
    if not noise_mode:
        noise_mode = "configured_snr_anchor_after_large_scale_gain"
    entrypoint = "run_6g_phy_lls_single" if browser_mode == "LLS" else "not_wired_from_browser_dashboard"
    browser_control_plane = "authoritative_runtime_yaml_overlay" if browser_mode == "LLS" else "selector_separated_not_launched_here"
    return {
        "browser_execution_mode": browser_mode,
        "browser_execution_mode_label": BROWSER_EXECUTION_MODE_LABELS.get(browser_mode, browser_mode),
        "execution_model": execution_model or "independent_link_sweep",
        "configured_users": str(num_users),
        "noise_operating_mode": noise_mode,
        "doppler_source_mode": doppler_source_mode or "configured",
        "interference_mode": interference_mode or "none",
        "control_integration_mode": control_mode,
        "pbch_mode": "runtime_cell_search_gate" if pbch_required else "disabled",
        "prach_mode": "runtime_prach_success_gate_simplified_ra" if prach_required else "disabled",
        "pdcch_mode": "grant_coupled_pdcch_dci_gating" if pdcch_required else "disabled",
        "srs_mode": "srs_freshness_csi_gate" if srs_required else "disabled",
        "pbch_gating_active": pbch_required,
        "prach_gating_active": prach_required,
        "pdcch_gating_active": pdcch_required,
        "srs_gating_active": srs_required,
        "browser_control_plane": browser_control_plane,
        "result_store": str(path_get(config_payload, "output.backend", "filesystem") or ""),
        "entrypoint": entrypoint,
        "sweep_mode": "enabled" if sweep_enabled else "off_by_default_single_scenario",
    }


RESULT_SECTION_LABELS: dict[str, str] = {
    "all": "All",
    "summary": "Summary",
    "geometry": "Geometry",
    "waveform": "Waveform",
    "constellation": "Constellation",
    "pdsch": "PDSCH",
    "pusch": "PUSCH",
    "modulation": "Mod/Demod",
    "channelest": "Channel Est",
    "channel": "Channel",
    "control": "Control",
    "prach": "PRACH",
    "harq": "HARQ",
    "beam": "Beam",
    "energy": "Energy",
    "scheduler": "Scheduler",
    "csi": "CSI",
    "rf": "RF",
    "cellselection": "Cell Selection",
    "debug": "Debug",
    "logs": "Logs",
    "meta": "Meta",
    "other": "Other",
}


def normalize_result_section(raw: str | None) -> str:
    token = str(raw or "all").strip().lower()
    return token if token in RESULT_SECTION_LABELS else "all"


def classify_result_section(logical_path: str) -> str:
    path = str(logical_path or "").strip().lower()
    if not path:
        return "other"
    if path.startswith("meta/"):
        return "meta"
    if any(token in path for token in ("debug", "validation_messages", "artifact_inventory", "live_stage_status", "failure_debug_report")):
        return "debug"
    if any(token in path for token in ("summary", "manifest", "catalog", "checktable", "kpi_summary", "runtime_operating_mode", "truth_contract", "mcs_table_reference", "cqi_table_reference", "multiuser_user_summary", "runtime_stage_profile", "runtime_profiler_summary", "runtime_function_profile", "runtime_function_call_edges", "user_performance", "output_coverage_registry", "output_completeness", "instrumentation_coverage", "api_exposure_audit", "persistence_audit", "honest_unavailable_registry", "compare_run_prerequisites", "result_issue_registry", "table_scenario_topology", "scenario_consistency_check", "table_gnb_cell", "table_channel_summary", "table_noise_interference", "table_link_budget", "root_cause_candidate_table", "cell_edge_analytics_table", "beam_stability_analytics_table", "energy_root_cause_table")):
        return "summary"
    if any(token in path for token in ("sites.csv", "sectors.csv", "trps.csv", "ues.csv", "deployment_layout_reference", "layout", "geometry")):
        return "geometry"
    if any(token in path for token in ("antenna_", "array_consistency")):
        return "geometry"
    if "waveform_preview" in path:
        return "waveform"
    if "constellation_preview" in path:
        return "constellation"
    if "modulation_demodulation" in path:
        return "modulation"
    if any(token in path for token in ("channel_estimation_tti", "live_channel_estimation_stats")):
        return "channelest"
    if any(token in path for token in ("channel_state_tti", "doppler", "pathloss")):
        return "channel"
    if any(token in path for token in ("tod_toa", "timing_positioning")):
        return "channel"
    if any(token in path for token in ("cell_measurement", "cell_reselection", "serving_trace")):
        return "cellselection"
    if "prach" in path:
        return "prach"
    if "harq" in path:
        return "harq"
    if any(token in path for token in ("scheduler", "grant", "scheduling")):
        return "scheduler"
    if "beam" in path:
        return "beam"
    if any(token in path for token in ("energy", "power", "efficiency")):
        return "energy"
    if any(token in path for token in ("pdsch", "dlsch", "/dl_", "_dl_", "downlink")):
        return "pdsch"
    if any(token in path for token in ("pusch", "ulsch", "/ul_", "_ul_", "uplink")):
        return "pusch"
    if any(token in path for token in ("pdcch", "pucch", "pbch", "ssb", "prach", "control")):
        return "control"
    if any(token in path for token in ("csi", "srs", "dmrs", "trs", "tracking", "pmi", "cqi", "ri", "cri", "nmse", "rank_estimation", "csirs", "channel_estimation")):
        return "csi"
    if any(token in path for token in ("rf", "channel", "rsrp", "sinr", "pathloss", "interference", "coverage_layer", "coverage_snapshot", "cell_measurement", "cell_reselection")):
        return "rf"
    return "other"


def result_section_priority(section: str) -> int:
    order = [
        "summary",
        "waveform",
        "constellation",
        "pdsch",
        "pusch",
        "modulation",
        "channelest",
        "channel",
        "control",
        "prach",
        "harq",
        "beam",
        "csi",
        "rf",
        "cellselection",
        "scheduler",
        "geometry",
        "energy",
        "debug",
        "logs",
        "meta",
        "other",
    ]
    try:
        return order.index(section)
    except ValueError:
        return len(order)


def result_artifact_display_priority(section: str, logical_path: str) -> int:
    path = str(logical_path or "").strip().lower()
    exact_orders: dict[str, list[str]] = {
        "summary": [
            "reports/csv/runtime_operating_mode.csv",
            "reports/csv/runtime_stage_profile.csv",
            "reports/csv/runtime_profiler_summary.csv",
            "reports/csv/runtime_function_profile.csv",
            "reports/csv/runtime_function_call_edges.csv",
            "reports/csv/scenario_summary.csv",
            "reports/csv/live_error_rate_summary.csv",
            "air_interface/csv/lls_kpi_summary.csv",
            "air_interface/csv/link_kpis.csv",
            "air_interface/csv/link_anchor_kpis.csv",
            "reports/csv/live_stage_status.csv",
            "air_interface/reports/csv/live_stage_status.csv",
            "reports/csv/cqi_table_reference.csv",
            "reports/csv/mcs_table_reference.csv",
            "reports/csv/deployment_layout_reference.csv",
            "reports/csv/live_user_performance_snapshot.csv",
        ],
        "geometry": [
            "reports/csv/deployment_layout_reference.csv",
            "reports/csv/sites.csv",
            "reports/csv/sectors.csv",
            "reports/csv/trps.csv",
            "reports/csv/ues.csv",
            "reports/csv/antenna_config_resolved.csv",
            "reports/csv/antenna_runtime_evidence.csv",
            "reports/csv/channel_array_consistency.csv",
            "reports/csv/live_rsrp_serving_trace.csv",
        ],
        "waveform": [
            "reports/csv/live_waveform_preview.csv",
        ],
        "constellation": [
            "air_interface/csv/dl_constellation_preview.csv",
            "air_interface/csv/ul_constellation_preview.csv",
        ],
        "pdsch": [
            "air_interface/csv/dl_pdsch_trials.csv",
            "air_interface/csv/dl_constellation_preview.csv",
            "reports/csv/pdsch_outputs.csv",
            "reports/csv/coding_decoder_outputs.csv",
            "reports/csv/runtime_operating_mode.csv",
        ],
        "pusch": [
            "air_interface/csv/ul_pusch_trials.csv",
            "air_interface/csv/ul_constellation_preview.csv",
            "reports/csv/pusch_pucch_outputs.csv",
            "reports/csv/coding_decoder_outputs.csv",
            "reports/csv/runtime_operating_mode.csv",
        ],
        "modulation": [
            "reports/csv/live_modulation_demodulation_trace.csv",
            "air_interface/csv/dl_constellation_preview.csv",
            "air_interface/csv/ul_constellation_preview.csv",
        ],
        "channelest": [
            "reports/csv/live_channel_estimation_tti.csv",
            "reports/csv/live_channel_estimation_stats.csv",
            "reports/csv/live_rank_estimation_stats.csv",
        ],
        "channel": [
            "reports/csv/live_channel_state_tti.csv",
            "reports/csv/tod_toa_trace.csv",
            "reports/csv/timing_positioning_runtime_evidence.csv",
            "reports/csv/live_coverage_layer.csv",
            "reports/csv/live_coverage_snapshot.csv",
        ],
        "control": [
            "reports/csv/live_control_gating_summary.csv",
            "reports/csv/live_control_gating_state.csv",
            "air_interface/csv/pdcch_trials.csv",
            "air_interface/csv/pbch_trials.csv",
            "air_interface/csv/prach_trials.csv",
            "air_interface/csv/pucch_trials.csv",
            "air_interface/csv/srs_trials.csv",
            "air_interface/csv/trs_trials.csv",
            "reports/csv/pdcch_control_outputs.csv",
            "reports/csv/initial_access_random_access_outputs.csv",
            "control/csv/control_gating_summary.csv",
            "control/csv/control_gating_state.csv",
            "control/csv/pdcch_trials.csv",
            "control/csv/pbch_trials.csv",
            "control/csv/prach_trials.csv",
            "control/csv/pucch_trials.csv",
            "control/csv/srs_trials.csv",
            "control/csv/trs_trials.csv",
        ],
        "prach": [
            "air_interface/csv/prach_trials.csv",
            "control/csv/prach_trials.csv",
        ],
        "harq": [
            "harq/csv/harq_process_timeline.csv",
            "harq/csv/probe_harq_summary.csv",
            "harq/csv/probe_harq_packets.csv",
            "reports/csv/harq_outputs.csv",
        ],
        "scheduler": [
            "packet_flow/csv/live_dl_scheduler_grants.csv",
            "packet_flow/csv/live_ul_scheduler_grants.csv",
            "packet_flow/csv/live_pucch_grants.csv",
            "system/csv/system_scheduler_grants.csv",
        ],
        "beam": [
            "reports/csv/live_beam_selection_stats.csv",
            "beamforming/csv/beam_score_trace.csv",
            "beamforming/csv/probe_beam_mimo.csv",
            "beamforming/csv/probe_beam_management.csv",
            "reports/csv/beam_management_outputs.csv",
        ],
        "csi": [
            "reports/csv/live_channel_estimation_stats.csv",
            "reports/csv/live_rank_estimation_stats.csv",
            "reports/csv/live_csi_feedback_stats.csv",
            "reports/csv/live_csirs_stats.csv",
            "air_interface/csv/srs_trials.csv",
            "air_interface/csv/trs_trials.csv",
            "reports/csv/csi_outputs.csv",
            "reports/csv/cqi_table_reference.csv",
            "control/csv/srs_trials.csv",
            "control/csv/trs_trials.csv",
        ],
        "rf": [
            "reports/csv/live_coverage_layer.csv",
            "reports/csv/live_coverage_snapshot.csv",
            "reports/csv/live_rsrp_serving_trace.csv",
            "reports/csv/live_cell_measurement_trace.csv",
            "reports/csv/live_cell_reselection_events.csv",
            "reports/csv/energy_efficiency_outputs.csv",
            "rf/csv/energy_timeline_trace.csv",
            "rf/csv/probe_rf_energy.csv",
            "rf/csv/iq_imbalance_timeline_trace.csv",
            "rf/csv/probe_rf_iq_imbalance.csv",
            "reports/csv/channel_estimation_tracking_outputs.csv",
        ],
        "cellselection": [
            "reports/csv/live_rsrp_serving_trace.csv",
            "reports/csv/live_cell_measurement_trace.csv",
            "reports/csv/live_cell_reselection_events.csv",
        ],
        "debug": [
            "reports/csv/live_tx_rx_stage_trace.csv",
            "reports/csv/live_stage_status.csv",
            "air_interface/reports/csv/live_stage_status.csv",
            "reports/csv/debug_trace_outputs.csv",
            "reports/csv/validation_messages.csv",
            "reports/csv/artifact_inventory.csv",
        ],
    }
    preferred = exact_orders.get(section, [])
    if path in preferred:
        return preferred.index(path)
    if artifact_is_legacy_mirror(path):
        return 900
    keyword_groups: dict[str, list[str]] = {
        "summary": ["runtime", "scenario_summary", "kpi_summary", "link_kpis", "sweep", "coverage", "stage_profile"],
        "waveform": ["live_waveform_preview", "waveform"],
        "constellation": ["constellation_preview"],
        "pdsch": ["dl_pdsch_trials", "pdsch_outputs", "coding_decoder"],
        "pusch": ["ul_pusch_trials", "pusch_pucch_outputs", "coding_decoder"],
        "modulation": ["live_modulation_demodulation", "constellation_preview", "modulation"],
        "channelest": ["live_channel_estimation_tti", "live_channel_estimation_stats", "rank_estimation", "nmse"],
        "channel": ["live_channel_state_tti", "tod_toa", "timing_positioning", "live_coverage_snapshot", "doppler", "pathloss", "channel", "sinr"],
        "control": ["pdcch", "pbch", "prach", "pucch", "cell_search", "random_access"],
        "prach": ["prach"],
        "harq": ["harq"],
        "beam": ["live_beam_selection_stats", "beam"],
        "csi": ["live_channel_estimation_stats", "live_rank_estimation_stats", "live_csi_feedback_stats", "live_csirs_stats", "srs", "trs", "csi", "cqi_table_reference"],
        "rf": ["live_coverage_layer", "live_coverage_snapshot", "live_rsrp_serving_trace", "live_cell_measurement_trace", "cell_reselection", "energy", "rf", "sinr", "channel"],
        "cellselection": ["live_cell_measurement_trace", "live_rsrp_serving_trace", "live_cell_reselection_events"],
        "geometry": ["deployment_layout", "antenna_", "array_consistency", "sites", "sectors", "trps", "ues", "serving_trace"],
        "debug": ["live_stage_status", "debug", "validation", "artifact_inventory"],
    }
    for idx, token in enumerate(keyword_groups.get(section, []), start=len(preferred)):
        if token in path:
            return idx
    return len(preferred) + len(keyword_groups.get(section, [])) + 50


def build_artifact_descriptor(art: dict[str, Any]) -> dict[str, Any]:
    section = classify_result_section(str(art.get("logical_path") or ""))
    descriptor = {
        "artifact_id": art["artifact_id"],
        "logical_path": art["logical_path"],
        "artifact_kind": art["artifact_kind"],
        "mime_type": art.get("mime_type"),
        "section": section,
        "display_rank": result_artifact_display_priority(section, str(art.get("logical_path") or "")),
        "byte_size": art["byte_size"],
        "created_utc": art["created_utc"],
        "download_url": artifact_url(int(art["artifact_id"]), download=True),
    }
    if art["artifact_kind"] == "table_csv":
        descriptor["view_url"] = f"/artifact/{art['artifact_id']}/table"
    else:
        descriptor["view_url"] = artifact_url(int(art["artifact_id"]), download=False)
    return descriptor


CONTROL_TRIAL_TABLE_BASENAMES = {
    "pbch_trials.csv",
    "prach_trials.csv",
    "pdcch_trials.csv",
    "pucch_trials.csv",
    "srs_trials.csv",
    "trs_trials.csv",
}


CANONICAL_CONTROL_TRIAL_PATHS = {
    "air_interface/csv/pbch_trials.csv",
    "air_interface/csv/prach_trials.csv",
    "air_interface/csv/pdcch_trials.csv",
    "air_interface/csv/pucch_trials.csv",
    "air_interface/csv/srs_trials.csv",
    "air_interface/csv/trs_trials.csv",
}


CANONICAL_RUNTIME_ARTIFACT_OWNERS: dict[str, dict[str, Any]] = {
    "control_summary": {
        "canonical_path": "reports/csv/live_control_gating_summary.csv",
        "legacy_paths": ["control/csv/control_gating_summary.csv"],
        "owner_kind": "live_control_gating_summary",
    },
    "control_state": {
        "canonical_path": "reports/csv/live_control_gating_state.csv",
        "legacy_paths": ["control/csv/control_gating_state.csv"],
        "owner_kind": "live_control_gating_state",
    },
    "stage_status": {
        "canonical_path": "reports/csv/live_stage_status.csv",
        "legacy_paths": ["air_interface/reports/csv/live_stage_status.csv"],
        "owner_kind": "live_stage_status",
    },
    "dl_scheduler_grants": {
        "canonical_path": "packet_flow/csv/live_dl_scheduler_grants.csv",
        "legacy_paths": ["system/csv/system_scheduler_grants.csv"],
        "owner_kind": "scheduler_grants_dl",
    },
    "ul_scheduler_grants": {
        "canonical_path": "packet_flow/csv/live_ul_scheduler_grants.csv",
        "legacy_paths": ["system/csv/system_scheduler_grants.csv"],
        "owner_kind": "scheduler_grants_ul",
    },
    "pucch_grants": {
        "canonical_path": "packet_flow/csv/live_pucch_grants.csv",
        "legacy_paths": [],
        "owner_kind": "scheduler_grants_pucch",
    },
    "dl_trials": {
        "canonical_path": "air_interface/csv/dl_pdsch_trials.csv",
        "legacy_paths": [],
        "owner_kind": "raw_dl_trials",
    },
    "ul_trials": {
        "canonical_path": "air_interface/csv/ul_pusch_trials.csv",
        "legacy_paths": [],
        "owner_kind": "raw_ul_trials",
    },
    "scenario_summary": {
        "canonical_path": "reports/csv/scenario_summary.csv",
        "legacy_paths": [],
        "owner_kind": "summary_rollup",
    },
    "runtime_operating_mode": {
        "canonical_path": "reports/csv/runtime_operating_mode.csv",
        "legacy_paths": [],
        "owner_kind": "summary_rollup",
    },
    "live_error_rate_summary": {
        "canonical_path": "reports/csv/live_error_rate_summary.csv",
        "legacy_paths": [],
        "owner_kind": "summary_rollup",
    },
    "pdcch_trials": {
        "canonical_path": "air_interface/csv/pdcch_trials.csv",
        "legacy_paths": ["control/csv/pdcch_trials.csv"],
        "owner_kind": "raw_control_trials",
    },
    "pbch_trials": {
        "canonical_path": "air_interface/csv/pbch_trials.csv",
        "legacy_paths": ["control/csv/pbch_trials.csv"],
        "owner_kind": "raw_control_trials",
    },
    "prach_trials": {
        "canonical_path": "air_interface/csv/prach_trials.csv",
        "legacy_paths": ["control/csv/prach_trials.csv"],
        "owner_kind": "raw_control_trials",
    },
    "pucch_trials": {
        "canonical_path": "air_interface/csv/pucch_trials.csv",
        "legacy_paths": ["control/csv/pucch_trials.csv"],
        "owner_kind": "raw_control_trials",
    },
    "srs_trials": {
        "canonical_path": "air_interface/csv/srs_trials.csv",
        "legacy_paths": ["control/csv/srs_trials.csv"],
        "owner_kind": "raw_control_trials",
    },
    "trs_trials": {
        "canonical_path": "air_interface/csv/trs_trials.csv",
        "legacy_paths": ["control/csv/trs_trials.csv"],
        "owner_kind": "raw_control_trials",
    },
}


LEGACY_MIRROR_PATHS = {
    "control/csv/control_gating_summary.csv",
    "control/csv/control_gating_state.csv",
    "control/csv/pbch_trials.csv",
    "control/csv/prach_trials.csv",
    "control/csv/pdcch_trials.csv",
    "control/csv/pucch_trials.csv",
    "control/csv/srs_trials.csv",
    "control/csv/trs_trials.csv",
    "air_interface/reports/csv/live_stage_status.csv",
}


def artifact_runtime_family_key(logical_path: str) -> str | None:
    path = str(logical_path or "").strip().lower()
    if not path:
        return None
    if path in {
        "reports/csv/live_control_gating_summary.csv",
        "control/csv/control_gating_summary.csv",
    }:
        return "live_control_gating_summary"
    if path in {
        "reports/csv/live_control_gating_state.csv",
        "control/csv/control_gating_state.csv",
    }:
        return "live_control_gating_state"
    if path in {
        "reports/csv/live_stage_status.csv",
        "air_interface/reports/csv/live_stage_status.csv",
    }:
        return "live_stage_status"
    base = path.rsplit("/", 1)[-1]
    if base in CONTROL_TRIAL_TABLE_BASENAMES:
        return f"control_trial::{base}"
    return None


def artifact_canonical_preference_score(logical_path: str) -> int:
    path = str(logical_path or "").strip().lower()
    if path == "reports/csv/live_control_gating_summary.csv":
        return 50
    if path == "reports/csv/live_control_gating_state.csv":
        return 50
    if path == "reports/csv/live_stage_status.csv":
        return 50
    if path in CANONICAL_CONTROL_TRIAL_PATHS:
        return 50
    if path.startswith("packet_flow/csv/live_") and "scheduler_grants" in path:
        return 50
    if path.startswith("control/csv/"):
        return 10
    if path == "air_interface/reports/csv/live_stage_status.csv":
        return 10
    if path == "system/csv/system_scheduler_grants.csv":
        return 10
    return 0


def artifact_is_legacy_mirror(logical_path: str) -> bool:
    return str(logical_path or "").strip().lower() in LEGACY_MIRROR_PATHS


def dedupe_table_descriptors_for_ui(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    passthrough: list[dict[str, Any]] = []
    for item in items:
        path = str(item.get("logical_path") or "").strip().lower()
        family = artifact_runtime_family_key(path)
        if family:
            grouped.setdefault(family, []).append(item)
        else:
            passthrough.append(item)
    for group in grouped.values():
        best = max(
            group,
            key=lambda item: (
                artifact_canonical_preference_score(str(item.get("logical_path") or "")),
                1 if int(item.get("byte_size") or 0) > 2303 else 0,
                int(item.get("byte_size") or 0),
                str(item.get("created_utc") or ""),
            ),
        )
        passthrough.append(best)
    return sorted(passthrough, key=lambda item: (result_section_priority(str(item.get("section") or "other")), int(item.get("display_rank") or 999), str(item.get("logical_path") or "").lower()))


def artifact_sort_key(art: dict[str, Any]) -> tuple[int, str]:
    section = classify_result_section(str(art.get("logical_path") or ""))
    return (
        result_section_priority(section),
        result_artifact_display_priority(section, str(art.get("logical_path") or "")),
        str(art.get("logical_path") or "").lower(),
    )


def result_section_href(section: str, *, run_id: int | None = None, run_tag: str | None = None) -> str:
    normalized = normalize_result_section(section)
    base = "/result" if normalized == "all" else f"/result/{normalized}"
    query: dict[str, str] = {}
    if run_id is not None:
        query["run_id"] = str(run_id)
    elif run_tag:
        query["run_tag"] = str(run_tag)
    if query:
        return f"{base}?{urllib.parse.urlencode(query)}"
    return base


def build_result_section_links(current_section: str, *, run_id: int | None = None, run_tag: str | None = None) -> str:
    chips: list[str] = []
    for section, label in RESULT_SECTION_LABELS.items():
        cls = "subtab-button active" if section == current_section else "subtab-button"
        href = result_section_href(section, run_id=run_id, run_tag=run_tag)
        chips.append(f'<a class="{cls}" href="{html.escape(href)}">{html.escape(label)}</a>')
    return "".join(chips)


def find_field_value(fields: list[dict[str, Any]], suffixes: list[str]) -> str:
    normalized_suffixes = [suffix.lower() for suffix in suffixes]
    for field in fields:
        path = str(field["path"]).lower()
        leaf = path.split(".")[-1]
        if any(path.endswith(suffix) or leaf == suffix.rsplit(".", 1)[-1] for suffix in normalized_suffixes):
            return str(field.get("value") or "n/a")
    return "n/a"


def find_field_value_with_unit(fields: list[dict[str, Any]], suffixes: list[str], unit: str = "") -> str:
    return format_value_with_unit(find_field_value(fields, suffixes), unit)


def clear_dashboard_storage() -> dict[str, int]:
    stats = {
        "runs": 0,
        "artifacts": 0,
        "chunks": 0,
        "logs": 0,
        "runtime_yaml": 0,
        "disk_entries": 0,
    }
    clear_dashboard_caches()
    with db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM sim_runs")
            stats["runs"] = int(cur.fetchone()[0])
            cur.execute("SELECT COUNT(*) FROM sim_artifacts")
            stats["artifacts"] = int(cur.fetchone()[0])
            cur.execute("SELECT COUNT(*) FROM sim_artifact_chunks")
            stats["chunks"] = int(cur.fetchone()[0])
            cur.execute("SELECT COUNT(*) FROM sim_run_logs")
            stats["logs"] = int(cur.fetchone()[0])
            cur.execute("DELETE FROM sim_artifact_chunks")
            cur.execute("DELETE FROM sim_artifacts")
            cur.execute("DELETE FROM sim_run_logs")
            cur.execute("DELETE FROM sim_runs")
            for table_name in ("sim_runs", "sim_artifacts", "sim_run_logs"):
                try:
                    cur.execute(f"ALTER TABLE {table_name} AUTO_INCREMENT = 1")
                except mysql.connector.Error:
                    pass

    def _clear_children(root: Path) -> int:
        count = 0
        if not root.exists():
            return count
        resolved_root = root.resolve()
        repo_root = REPO_ROOT.resolve()
        if resolved_root != repo_root and repo_root not in resolved_root.parents:
            raise ValueError(f"Refusing to clear path outside repo root: {resolved_root}")
        for child in list(root.iterdir()):
            try:
                if child.is_dir():
                    shutil.rmtree(child, ignore_errors=False)
                else:
                    child.unlink(missing_ok=True)
            except FileNotFoundError:
                continue
            except OSError:
                if child.is_dir():
                    try:
                        os.rmdir("\\\\?\\" + str(child.resolve()))
                    except OSError:
                        shutil.rmtree("\\\\?\\" + str(child.resolve()), ignore_errors=True)
                else:
                    try:
                        Path("\\\\?\\" + str(child.resolve())).unlink(missing_ok=True)
                    except OSError:
                        pass
            count += 1
        return count

    stats["disk_entries"] += _clear_children(REPO_ROOT / "results")
    stats["disk_entries"] += _clear_children(REPO_ROOT / "tmp_web_runs")
    for runtime_yaml in SCENARIO_ROOT.rglob("__web_runtime_*.yaml"):
        runtime_yaml.unlink(missing_ok=True)
        stats["runtime_yaml"] += 1
    return stats


def delete_run_storage(run_id: int) -> dict[str, int | str]:
    run_row = fetch_run(int(run_id))
    if run_row is None:
        raise KeyError(f"Run {run_id} was not found.")
    status_text = str(run_row.get("status_text") or "").strip().lower()
    if status_text == "running":
        raise ValueError(f"Run {run_id} is still marked running. Stop or finish it before deleting.")

    stats: dict[str, int | str] = {
        "run_id": int(run_id),
        "artifacts": 0,
        "chunks": 0,
        "logs": 0,
        "runtime_yaml": 0,
        "disk_entries": 0,
        "run_tag": str(run_row.get("run_tag") or ""),
    }

    def _safe_delete_path(path_obj: Path) -> int:
        if not path_obj.exists():
            return 0
        resolved = path_obj.resolve()
        repo_root = REPO_ROOT.resolve()
        if resolved != repo_root and repo_root not in resolved.parents:
            raise ValueError(f"Refusing to delete path outside repo root: {resolved}")
        if path_obj.is_dir():
            shutil.rmtree(path_obj, ignore_errors=False)
        else:
            path_obj.unlink(missing_ok=True)
        return 1

    clear_dashboard_caches(int(run_id))
    with db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM sim_artifacts WHERE run_id=%s", (int(run_id),))
            stats["artifacts"] = int(cur.fetchone()[0])
            cur.execute(
                """
                SELECT COUNT(*)
                FROM sim_artifact_chunks
                WHERE artifact_id IN (SELECT artifact_id FROM sim_artifacts WHERE run_id=%s)
                """,
                (int(run_id),),
            )
            stats["chunks"] = int(cur.fetchone()[0])
            cur.execute("SELECT COUNT(*) FROM sim_run_logs WHERE run_id=%s", (int(run_id),))
            stats["logs"] = int(cur.fetchone()[0])
            cur.execute(
                """
                DELETE c FROM sim_artifact_chunks c
                INNER JOIN sim_artifacts a ON a.artifact_id = c.artifact_id
                WHERE a.run_id = %s
                """,
                (int(run_id),),
            )
            cur.execute("DELETE FROM sim_artifacts WHERE run_id=%s", (int(run_id),))
            cur.execute("DELETE FROM sim_run_logs WHERE run_id=%s", (int(run_id),))
            cur.execute("DELETE FROM sim_runs WHERE run_id=%s", (int(run_id),))

    run_folder = str(run_row.get("run_folder") or "").strip()
    if run_folder:
        try:
            stats["disk_entries"] += _safe_delete_path(Path(run_folder))
        except FileNotFoundError:
            pass

    run_tag = str(run_row.get("run_tag") or "").strip()
    if run_tag:
        runtime_yaml = SCENARIO_ROOT / f"__web_runtime_{safe_token(run_tag)}.yaml"
        if runtime_yaml.exists():
            runtime_yaml.unlink(missing_ok=True)
            stats["runtime_yaml"] += 1
        for extra_path in (runtime_log_file(run_tag), runtime_log_cursor_file(run_tag), runtime_pid_file(run_tag)):
            if extra_path is not None:
                try:
                    stats["disk_entries"] += _safe_delete_path(extra_path)
                except FileNotFoundError:
                    pass

    return stats


def metric_priority(name: str) -> int:
    token = name.lower()
    priorities = [
        "goodput",
        "throughput",
        "bler",
        "rsrp",
        "snr",
        "sinr",
        "cqi",
        "mcs",
        "coderate",
        "code rate",
        "latency",
        "delay",
        "detection",
        "falsealarm",
        "false alarm",
        "miss",
        "nmse",
        "energy",
        "complexity",
        "availability",
    ]
    for idx, key in enumerate(priorities):
        if key in token:
            return idx
    return len(priorities) + 10


def candidate_metric_columns(header: list[str]) -> list[int]:
    positions = [idx for idx, name in enumerate(header) if metric_priority(name) < 30]
    return positions if positions else list(range(len(header)))


def chart_column_priority(name: str) -> tuple[int, int, str]:
    token = str(name or "").strip().lower()
    priorities = [
        "goodput",
        "throughput",
        "bler",
        "rsrp",
        "sinr",
        "snr",
        "cqi",
        "mcs",
        "coderate",
        "code rate",
        "spectralefficiency",
        "spectral efficiency",
        "latency",
        "delay",
        "detection",
        "gain",
        "evm",
        "nmse",
        "harq",
        "beam",
        "interference",
        "noise",
        "power",
    ]
    for idx, key in enumerate(priorities):
        if key in token:
            return (0, idx, token)
    if re.search(r"(frame|slot|trial|seed|index|iteration|user|count|point|step|sample|tti)$", token):
        return (2, 99, token)
    return (1, 50, token)


def chart_is_coordinate_column(name: str) -> bool:
    token = str(name or "").strip().lower()
    return bool(
        re.search(r"(^lat$|^lon$|^x(_m)?$|^y(_m)?$|^z(_m)?$|heading|azimuth|longitude|latitude)", token)
    )


def aggregate_points_by_x(points: list[dict[str, Any]]) -> list[dict[str, Any]]:
    buckets: dict[float, list[float]] = {}
    for point in points:
        x_val = coerce_numeric(point.get("x"))
        y_val = coerce_numeric(point.get("y"))
        if x_val is None or y_val is None:
            continue
        buckets.setdefault(float(x_val), []).append(float(y_val))
    if not buckets:
        return points
    aggregated: list[dict[str, Any]] = []
    for x_val in sorted(buckets):
        values = buckets[x_val]
        aggregated.append({"x": x_val, "y": sum(values) / max(len(values), 1)})
    return aggregated


def _column_variation_score(rows: list[list[Any]], idx: int) -> tuple[int, int]:
    values = [coerce_numeric(row[idx]) for row in rows if idx < len(row)]
    values = [value for value in values if value is not None]
    if not values:
        return (0, 0)
    unique_values = {round(float(value), 9) for value in values}
    return (len(unique_values), len(values))


def _preferred_chart_x_index(
    artifact: dict[str, Any],
    header: list[str],
    rows: list[list[Any]],
    numeric_cols: list[tuple[int, str]],
) -> int | None:
    if not numeric_cols:
        return None
    logical_path = str(artifact.get("logical_path") or "").lower()
    waveform_like = any(token in logical_path for token in ("waveform", "constellation", "preview"))
    preferred_patterns: list[tuple[str, int]] = []
    if waveform_like:
        preferred_patterns.extend(
            [
                (r"^sampleindex$", 0),
                (r"^time_s$", 1),
                (r"sample", 2),
                (r"time", 3),
            ]
        )
    preferred_patterns.extend(
        [
            (r"^slot_or_sample$", 4),
            (r"^x_value$", 5),
            (r"^slot$", 6),
            (r"^frame$", 7),
            (r"^tti$", 8),
            (r"^trial$", 9),
            (r"^ue_rank$|^percentile$", 10),
            (r"index", 12),
            (r"user|ue", 20),
            (r"snr|sinr|rsrp|cqi|mcs", 40),
            (r"metric_value", 80),
        ]
    )
    ranked: list[tuple[int, int, int, int]] = []
    for idx, name in numeric_cols:
        token = str(name or "").strip().lower()
        unique_count, total_count = _column_variation_score(rows, idx)
        if unique_count <= 1:
            continue
        pattern_rank = 99
        for pattern, rank in preferred_patterns:
            if re.search(pattern, token, re.IGNORECASE):
                pattern_rank = rank
                break
        ranked.append((pattern_rank, -unique_count, -total_count, idx))
    if ranked:
        ranked.sort()
        return ranked[0][3]
    return numeric_cols[0][0]


def flatten_numeric_values(value: Any, prefix: str = "", depth: int = 0) -> dict[str, float]:
    if depth > 3:
        return {}
    out: dict[str, float] = {}
    if isinstance(value, dict):
        for key, child in value.items():
            child_prefix = f"{prefix}.{key}" if prefix else str(key)
            out.update(flatten_numeric_values(child, child_prefix, depth + 1))
    elif isinstance(value, bool):
        out[prefix] = 1.0 if value else 0.0
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        out[prefix] = float(value)
    return out


def find_artifact_by_logical_path(artifacts: list[dict[str, Any]], logical_path: str) -> dict[str, Any] | None:
    target = str(logical_path or "").strip().lower()
    matches = [
        art
        for art in artifacts
        if str(art.get("logical_path") or "").strip().lower() == target
    ]
    if not matches:
        return None
    matches.sort(
        key=lambda art: (
            int(art.get("byte_size") or 0) > 0,
            int(art.get("artifact_id") or 0),
        )
    )
    return matches[-1]


def load_small_csv_rows(artifacts: list[dict[str, Any]], logical_path: str, *, max_rows: int = 64) -> list[dict[str, Any]]:
    art = find_artifact_by_logical_path(artifacts, logical_path)
    if art is None:
        return []
    header, rows = load_cached_csv_rows(int(art["artifact_id"]), max_rows)
    if not header:
        return []
    out: list[dict[str, Any]] = []
    for row in rows:
        record: dict[str, Any] = {}
        for idx, name in enumerate(header):
            record[str(name)] = row[idx] if idx < len(row) else ""
        out.append(record)
    return out


def select_canonical_csv_rows(
    artifacts: list[dict[str, Any]],
    canonical_path: str,
    *,
    legacy_paths: list[str] | None = None,
    max_rows: int = 64,
    owner_kind: str = "",
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    canonical_norm = str(canonical_path or "").strip().lower()
    legacy_norm = [str(path or "").strip().lower() for path in (legacy_paths or []) if str(path or "").strip()]
    meta: dict[str, Any] = {
        "canonical_logical_path": canonical_norm,
        "selected_logical_path": "",
        "selected_artifact_id": None,
        "selection_status": "missing",
        "fallback_used": False,
        "legacy_candidates": legacy_norm,
        "owner_kind": owner_kind or "canonical_csv",
    }
    canonical_art = find_artifact_by_logical_path(artifacts, canonical_norm)
    if canonical_art is not None:
        rows = load_small_csv_rows(artifacts, canonical_norm, max_rows=max_rows)
        meta["selected_logical_path"] = canonical_norm
        meta["selected_artifact_id"] = int(canonical_art.get("artifact_id") or 0)
        meta["selection_status"] = "canonical" if rows else "canonical_empty"
        meta["byte_size"] = int(canonical_art.get("byte_size") or 0)
        return rows, meta
    first_legacy_present: dict[str, Any] | None = None
    for legacy_path in legacy_norm:
        legacy_art = find_artifact_by_logical_path(artifacts, legacy_path)
        if legacy_art is None:
            continue
        if first_legacy_present is None:
            first_legacy_present = legacy_art
        rows = load_small_csv_rows(artifacts, legacy_path, max_rows=max_rows)
        if rows:
            meta["selected_logical_path"] = legacy_path
            meta["selected_artifact_id"] = int(legacy_art.get("artifact_id") or 0)
            meta["selection_status"] = "legacy_fallback"
            meta["fallback_used"] = True
            meta["byte_size"] = int(legacy_art.get("byte_size") or 0)
            return rows, meta
    if first_legacy_present is not None:
        meta["selected_logical_path"] = str(first_legacy_present.get("logical_path") or "").strip().lower()
        meta["selected_artifact_id"] = int(first_legacy_present.get("artifact_id") or 0)
        meta["selection_status"] = "legacy_empty"
        meta["fallback_used"] = True
        meta["byte_size"] = int(first_legacy_present.get("byte_size") or 0)
    return [], meta


def load_first_available_csv_rows(artifacts: list[dict[str, Any]], logical_paths: list[str], *, max_rows: int = 64) -> list[dict[str, Any]]:
    for logical_path in logical_paths:
        rows = load_small_csv_rows(artifacts, logical_path, max_rows=max_rows)
        if rows:
            return rows
    return []


def count_non_consistent_rows(rows: list[dict[str, Any]]) -> int:
    mismatches = 0
    for row in rows:
        if not isinstance(row, dict):
            continue
        status = str(row.get("ConsistencyStatus") or "").strip().lower()
        if status and status not in {
            "consistent",
            "consistent_db_unavailable",
            "consistent_inherited_from_base",
            "consistent_inherited_from_base_db_unavailable",
            "consistent_runtime_derived",
            "consistent_runtime_derived_db_unavailable",
            "observed",
        }:
            mismatches += 1
    return mismatches


def filter_non_consistent_rows(rows: list[dict[str, Any]], *, max_rows: int = 50) -> list[dict[str, Any]]:
    mismatches: list[dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        status = str(row.get("ConsistencyStatus") or "").strip().lower()
        if status and status not in {
            "consistent",
            "consistent_db_unavailable",
            "consistent_inherited_from_base",
            "consistent_inherited_from_base_db_unavailable",
            "consistent_runtime_derived",
            "consistent_runtime_derived_db_unavailable",
            "observed",
        }:
            mismatches.append(row)
        if len(mismatches) >= max_rows:
            break
    return mismatches


def load_scenario_summary_row(artifacts: list[dict[str, Any]]) -> dict[str, Any]:
    rows = load_small_csv_rows(artifacts, "reports/csv/scenario_summary.csv", max_rows=2)
    if rows:
        return rows[0]
    return {}


def normalize_layout_type_token(value: Any) -> str:
    token = str(value or "").strip()
    if not token:
        return ""
    normalized = token.lower().replace("-", "_")
    if normalized in {"hex", "hexgrid", "hex_grid", "hexagonal_wraparound"}:
        return "hexagonal_wraparound"
    return token


def build_live_summary(
    run_row: dict[str, Any],
    artifacts: list[dict[str, Any]],
    runtime_context: dict[str, Any] | None = None,
) -> dict[str, Any]:
    runtime_context = runtime_context if isinstance(runtime_context, dict) else {}
    summary_row = load_scenario_summary_row(artifacts)
    roundtrip_artifacts = runtime_context.get("roundtrip_artifacts") if isinstance(runtime_context, dict) else {}
    roundtrip_summary = roundtrip_artifacts.get("summary") if isinstance(roundtrip_artifacts, dict) else {}
    truth_modes = runtime_context.get("truth_modes") if isinstance(runtime_context, dict) else {}
    deployment = runtime_context.get("deployment") if isinstance(runtime_context, dict) else {}
    summary = {
        "source": "reports/csv/scenario_summary.csv",
        "scenario_id": summary_row.get("ScenarioID") or run_row.get("scenario_id") or "",
        "run_completion": summary_row.get("RunCompletion") or run_row.get("run_completion") or "",
        "result_ok": summary_row.get("ResultOk"),
        "required_failure_count": summary_row.get("RequiredFailureCount"),
        "failing_case_count": summary_row.get("FailingCaseCount"),
        "warning_count": summary_row.get("WarningCount"),
        "required_case_count": summary_row.get("RequiredCaseCount"),
        "status_authority": summary_row.get("StatusAuthority") or "",
        "runtime_truth_contract_ok": summary_row.get("RuntimeTruthContractOk"),
        "required_runtime_evidence_missing_count": summary_row.get("RequiredRuntimeEvidenceMissingCount"),
        "strict_truth_failure_count": summary_row.get("StrictTruthFailureCount"),
        "strict_proxy_guard_failure_count": summary_row.get("StrictProxyGuardFailureCount"),
        "canonical_artifact_gap_count": summary_row.get("CanonicalArtifactGapCount"),
        "runtime_truth_contract_failures": summary_row.get("RuntimeTruthContractFailures") or "",
        "runner_profile": summary_row.get("RunnerProfile") or "",
        "effective_dl_trial_count": summary_row.get("EffectiveDLTrialCount"),
        "effective_ul_trial_count": summary_row.get("EffectiveULTrialCount"),
        "configured_users": summary_row.get("NumUsers") or deployment.get("ConfiguredUsers") or deployment.get("NumUEs"),
        "execution_backend": truth_modes.get("execution_backend") or "",
        "phy_mode": truth_modes.get("phy_mode") or "",
        "waveform_phy_active": truth_modes.get("waveform_phy_active"),
        "proxy_phy_active": truth_modes.get("proxy_phy_active"),
        "fallback_used": truth_modes.get("fallback_used"),
        "execution_model": truth_modes.get("execution_model") or "",
        "interference_mode": truth_modes.get("interference_mode") or "",
        "roundtrip_mismatch_count": summary_row.get("RoundtripMismatchCount") if summary_row.get("RoundtripMismatchCount") not in {None, ""} else sum(
            int(coerce_numeric(roundtrip_summary.get(key)) or 0)
            for key in (
                "config_roundtrip_mismatches",
                "browser_runtime_db_mismatches",
                "summary_vs_raw_mismatches",
                "value_source_audit_mismatches",
            )
        ),
    }
    return summary


def build_output_coverage_context(artifacts: list[dict[str, Any]]) -> dict[str, Any]:
    registry_rows = load_small_csv_rows(artifacts, "reports/csv/output_coverage_registry.csv", max_rows=512)
    completeness_rows = load_small_csv_rows(artifacts, "reports/csv/output_completeness_table.csv", max_rows=512)
    instrumentation_rows = load_small_csv_rows(artifacts, "reports/csv/instrumentation_coverage_table.csv", max_rows=256)
    api_audit_rows = load_small_csv_rows(artifacts, "reports/csv/api_exposure_audit_table.csv", max_rows=512)
    persistence_rows = load_small_csv_rows(artifacts, "reports/csv/persistence_audit_table.csv", max_rows=512)
    unavailable_rows = load_small_csv_rows(artifacts, "reports/csv/honest_unavailable_registry.csv", max_rows=512)
    compare_rows = load_small_csv_rows(artifacts, "reports/csv/compare_run_prerequisites.csv", max_rows=128)
    issue_rows = load_small_csv_rows(artifacts, "reports/csv/result_issue_registry.csv", max_rows=256)
    root_cause_rows = load_small_csv_rows(artifacts, "reports/csv/root_cause_candidate_table.csv", max_rows=128)
    cell_edge_rows = load_small_csv_rows(artifacts, "reports/csv/cell_edge_analytics_table.csv", max_rows=128)
    beam_stability_rows = load_small_csv_rows(artifacts, "reports/csv/beam_stability_analytics_table.csv", max_rows=128)
    energy_root_cause_rows = load_small_csv_rows(artifacts, "reports/csv/energy_root_cause_table.csv", max_rows=128)
    heatmap_rows = load_small_csv_rows(artifacts, "reports/csv/prb_allocation_heatmap.csv", max_rows=256)
    prb_rows = load_small_csv_rows(artifacts, "packet_flow/csv/live_prb_allocation.csv", max_rows=256)
    power_rows = load_small_csv_rows(artifacts, "rf/csv/power_energy_table.csv", max_rows=256)
    materialization_manifest_rows = load_small_csv_rows(artifacts, "reports/csv/contract_materialization_manifest.csv", max_rows=512)
    materialization_coverage_rows = load_small_csv_rows(artifacts, "reports/csv/contract_materialization_coverage.csv", max_rows=8)

    contract_fallback_active = False
    if not registry_rows and materialization_manifest_rows:
        contract_fallback_active = True
        registry_rows = []
        for row in materialization_manifest_rows:
            materialization_status = str(row.get("materialization_status") or "").strip().lower()
            current_status = "implemented"
            if "missing" in materialization_status or "unavailable" in materialization_status:
                current_status = "unavailable"
            registry_rows.append(
                {
                    "output_name": str(row.get("logical_path") or ""),
                    "current_status": current_status,
                    "classification_code": "contract_materialized",
                    "fix_now_flag": "no",
                    "required_flag": "yes" if str(row.get("artifact_kind") or "") == "table_csv" else "no",
                    "backend_source_exists_flag": "yes",
                    "persisted_flag": "yes",
                    "api_exposed_flag": "yes",
                    "export_supported_flag": "yes",
                    "ui_rendered_flag": "yes",
                    "source_logical_path": str(row.get("source_logical_path") or ""),
                    "note": str(row.get("note") or ""),
                }
            )

    status_counts: dict[str, int] = {}
    class_counts: dict[str, int] = {}
    fix_now_count = 0
    implemented_required = 0
    overstated_implemented_count = 0
    for row in registry_rows:
        current_status = str(row.get("current_status") or "unknown")
        classification_code = str(row.get("classification_code") or "")
        status_counts[current_status] = status_counts.get(current_status, 0) + 1
        if classification_code:
            class_counts[classification_code] = class_counts.get(classification_code, 0) + 1
        if str(row.get("fix_now_flag") or "").lower() in {"yes", "partial"}:
            fix_now_count += 1
        if is_truthy_value(row.get("required_flag")) and current_status == "implemented":
            implemented_required += 1
        if current_status == "implemented":
            required_flags = (
                row.get("backend_source_exists_flag"),
                row.get("persisted_flag"),
                row.get("api_exposed_flag"),
                row.get("export_supported_flag"),
                row.get("ui_rendered_flag"),
            )
            if not all(is_truthy_value(flag) for flag in required_flags):
                overstated_implemented_count += 1

    artifact_links: dict[str, dict[str, Any]] = {}
    for logical_path in (
        "reports/csv/output_coverage_registry.csv",
        "reports/csv/output_completeness_table.csv",
        "reports/csv/instrumentation_coverage_table.csv",
        "reports/csv/api_exposure_audit_table.csv",
        "reports/csv/persistence_audit_table.csv",
        "reports/csv/honest_unavailable_registry.csv",
        "reports/csv/compare_run_prerequisites.csv",
        "reports/csv/result_issue_registry.csv",
        "rf/csv/power_energy_table.csv",
        "packet_flow/csv/live_prb_allocation.csv",
        "reports/csv/prb_allocation_heatmap.csv",
    ):
        artifact = find_artifact_by_logical_path(artifacts, logical_path)
        if artifact is not None:
            artifact_links[logical_path] = build_artifact_descriptor(artifact)

    dashboard_cards = [
        {"label": "Registry Rows", "value": len(registry_rows)},
        {"label": "Implemented", "value": status_counts.get("implemented", 0)},
        {"label": "Partial", "value": status_counts.get("partial", 0)},
        {"label": "Blocked", "value": status_counts.get("blocked", 0)},
        {"label": "Unavailable", "value": status_counts.get("unavailable", 0)},
        {"label": "Schema Only", "value": status_counts.get("schema_only", 0)},
        {"label": "Fix-Now Outputs", "value": fix_now_count},
        {"label": "Required Implemented", "value": implemented_required},
        {"label": "Overstated Implemented", "value": overstated_implemented_count},
        {"label": "Unavailable Reasons", "value": len(unavailable_rows)},
        {"label": "Issue Rows", "value": len(issue_rows)},
    ]
    if contract_fallback_active and materialization_coverage_rows:
        coverage_row = materialization_coverage_rows[0]
        dashboard_cards.extend(
            [
                {"label": "Contract Tables", "value": int(coerce_numeric(coverage_row.get("tables_available")) or 0)},
                {"label": "Contract Charts", "value": int(coerce_numeric(coverage_row.get("charts_available")) or 0)},
            ]
        )
    output_family_cards = build_output_family_cards(
        registry_rows,
        unavailable_rows,
        api_audit_rows,
        persistence_rows,
        compare_rows,
    )
    if contract_fallback_active:
        output_family_cards = []
    return {
        "registry": registry_rows,
        "completeness": completeness_rows,
        "instrumentation": instrumentation_rows,
        "api_audit": api_audit_rows,
        "persistence_audit": persistence_rows,
        "honest_unavailable": unavailable_rows,
        "compare_prerequisites": compare_rows,
        "issue_registry": issue_rows,
        "root_cause_candidates": root_cause_rows,
        "cell_edge_analytics": cell_edge_rows,
        "beam_stability_analytics": beam_stability_rows,
        "energy_root_cause": energy_root_cause_rows,
        "prb_allocation_preview": prb_rows,
        "prb_heatmap_preview": heatmap_rows,
        "power_energy_preview": power_rows,
        "dashboard_cards": dashboard_cards,
        "output_family_cards": output_family_cards,
        "status_counts": status_counts,
        "classification_counts": class_counts,
        "overstated_implemented_count": overstated_implemented_count,
        "artifact_links": artifact_links,
    }


def output_family_candidate_paths(output_name: str) -> list[str]:
    name = str(output_name or "").strip()
    if not name:
        return []
    overrides: dict[str, list[str]] = {
        "live_prb_allocation": ["packet_flow/csv/live_prb_allocation.csv"],
        "power_energy_table": ["rf/csv/power_energy_table.csv", "reports/image/power_energy_cumulative.png"],
        "prb_allocation_heatmap": ["reports/csv/prb_allocation_heatmap.csv", "reports/image/prb_allocation_heatmap.png"],
        "compare_runs_kpi_delta_table": ["reports/csv/compare_run_prerequisites.csv"],
        "compare_run_overlay_plot": ["reports/csv/compare_run_prerequisites.csv"],
        "result_issue_registry": ["reports/csv/result_issue_registry.csv"],
        "output_coverage_dashboard": ["reports/csv/output_coverage_registry.csv"],
        "persistence_audit_dashboard": ["reports/csv/persistence_audit_table.csv"],
        "api_exposure_dashboard": ["reports/csv/api_exposure_audit_table.csv"],
        "honest_unavailable_dashboard": ["reports/csv/honest_unavailable_registry.csv"],
        "root_cause_dashboard": ["reports/csv/root_cause_candidate_table.csv"],
        "cell_edge_dashboard": ["reports/csv/cell_edge_analytics_table.csv"],
        "beam_stability_dashboard": ["reports/csv/beam_stability_analytics_table.csv"],
        "energy_root_cause_dashboard": ["reports/csv/energy_root_cause_table.csv"],
    }
    paths = list(overrides.get(name, []))
    candidates = [
        f"reports/csv/{name}.csv",
        f"packet_flow/csv/{name}.csv",
        f"air_interface/csv/{name}.csv",
        f"system/csv/{name}.csv",
        f"rf/csv/{name}.csv",
        f"reports/image/{name}.png",
        f"reports/image/{name}.svg",
    ]
    for path in candidates:
        if path not in paths:
            paths.append(path)
    return paths


def find_output_family_artifacts(artifacts: list[dict[str, Any]], output_name: str) -> list[dict[str, Any]]:
    found: list[dict[str, Any]] = []
    seen: set[int] = set()
    for logical_path in output_family_candidate_paths(output_name):
        artifact = find_artifact_by_logical_path(artifacts, logical_path)
        if artifact is None or artifact_is_legacy_mirror(str(artifact.get("logical_path") or "")):
            continue
        artifact_id = int(artifact.get("artifact_id") or 0)
        if artifact_id in seen:
            continue
        seen.add(artifact_id)
        found.append(build_artifact_descriptor(artifact))
    return found


def _row_by_output_name(rows: list[dict[str, Any]], output_name: str) -> dict[str, Any]:
    target = str(output_name or "")
    return next((row for row in rows if str(row.get("output_name") or "") == target), {})


def build_output_family_cards(
    registry_rows: list[dict[str, Any]],
    unavailable_rows: list[dict[str, Any]],
    api_audit_rows: list[dict[str, Any]],
    persistence_rows: list[dict[str, Any]],
    compare_rows: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    cards: list[dict[str, Any]] = []
    for row in registry_rows:
        output_name = str(row.get("output_name") or "").strip()
        if not output_name:
            continue
        unavailable = _row_by_output_name(unavailable_rows, output_name)
        api = _row_by_output_name(api_audit_rows, output_name)
        persistence = _row_by_output_name(persistence_rows, output_name)
        compare = _row_by_output_name(compare_rows, output_name)
        run_id_num = coerce_numeric(row.get("run_id"))
        run_id = int(run_id_num) if run_id_num is not None and math.isfinite(run_id_num) else None
        reason = (
            str(row.get("blocker_reason") or "").strip()
            or str(unavailable.get("unavailable_reason") or "").strip()
            or str(compare.get("status") or "").strip()
        )
        next_action = (
            str(unavailable.get("next_implementation_step") or "").strip()
            or str(compare.get("next_action") or "").strip()
            or str(row.get("target_phase") or "").strip()
        )
        href = f"/outputs/{urllib.parse.quote(output_name)}"
        if run_id is not None:
            href += f"?run_id={run_id}"
        cards.append(
            {
                "output_name": output_name,
                "ui_section": row.get("ui_section"),
                "block_module": row.get("block_module"),
                "current_status": row.get("current_status"),
                "classification_code": row.get("classification_code"),
                "fix_now_flag": row.get("fix_now_flag"),
                "backend_source_exists_flag": row.get("backend_source_exists_flag"),
                "persisted_flag": row.get("persisted_flag"),
                "api_exposed_flag": row.get("api_exposed_flag"),
                "export_supported_flag": row.get("export_supported_flag"),
                "ui_rendered_flag": row.get("ui_rendered_flag"),
                "reason_code": reason,
                "next_action": next_action,
                "source_mapping": api.get("backend_source") or row.get("block_module"),
                "api_route": api.get("api_route") or "",
                "writer_enabled": persistence.get("writer_enabled") if persistence else "",
                "href": href,
            }
        )
    return cards


def _config_get_nested(config: dict[str, Any], path: str, default: Any = None) -> Any:
    current: Any = config
    for token in str(path or "").split("."):
        if not isinstance(current, dict) or token not in current:
            return default
        current = current[token]
    return current


def extract_run_feature_policy(run_row: dict[str, Any]) -> dict[str, bool]:
    config = parse_config_json(run_row)
    ai_enabled = bool(
        _config_get_nested(config, "ai.enable", False)
        or _config_get_nested(config, "lls6g.resolvedConfig.ai.enable", False)
    )
    ntn_enabled = bool(
        _config_get_nested(config, "ntn.enable", False)
        or _config_get_nested(config, "lls6g.resolvedConfig.ntn.enable", False)
    )
    sensing_enabled = bool(
        _config_get_nested(config, "sensing.enable", False)
        or _config_get_nested(config, "isac.enable", False)
        or _config_get_nested(config, "lls6g.resolvedConfig.sensing.enable", False)
    )
    localization_enabled = bool(
        _config_get_nested(config, "ai.positioning.enable", False)
        or _config_get_nested(config, "localization.enable", False)
        or _config_get_nested(config, "lls6g.resolvedConfig.localization.enable", False)
    )
    ris_enabled = bool(
        _config_get_nested(config, "ris.enable", False)
        or _config_get_nested(config, "lls6g.resolvedConfig.ris.enable", False)
    )
    cell_free_enabled = bool(
        _config_get_nested(config, "cell_free.enable", False)
        or _config_get_nested(config, "lls6g.resolvedConfig.cell_free.enable", False)
    )
    center_frequency_hz = coerce_numeric(
        _config_get_nested(
            config,
            "frequency.center_frequency_hz",
            _config_get_nested(config, "global_radio_scope.carrier_frequency_hz", float("nan")),
        )
    )
    sub_thz_enabled = bool(
        center_frequency_hz is not None and math.isfinite(center_frequency_hz) and center_frequency_hz >= 90e9
    )
    return {
        "ai_enabled": ai_enabled,
        "ntn_enabled": ntn_enabled,
        "sensing_enabled": sensing_enabled,
        "localization_enabled": localization_enabled,
        "ris_enabled": ris_enabled,
        "cell_free_enabled": cell_free_enabled,
        "sub_thz_enabled": sub_thz_enabled,
    }


def artifact_is_policy_filtered(logical_path: str, feature_policy: dict[str, bool] | None) -> bool:
    path = str(logical_path or "").strip().lower()
    policy = feature_policy or {}
    if not path:
        return False

    def has_feature_token(*tokens: str) -> bool:
        for token in tokens:
            pattern = rf"(^|[\\/_.-]){re.escape(str(token).lower())}([\\/_.-]|$)"
            if re.search(pattern, path):
                return True
        return False

    if (has_feature_token("ai") or "ai_ml_outputs" in path) and not policy.get("ai_enabled", False):
        return True
    if has_feature_token("ntn") and not policy.get("ntn_enabled", False):
        return True
    if (has_feature_token("sensing") or has_feature_token("isac")) and not policy.get("sensing_enabled", False):
        return True
    if has_feature_token("localization") and not policy.get("localization_enabled", False):
        return True
    if has_feature_token("ris") and not policy.get("ris_enabled", False):
        return True
    if has_feature_token("cell_free") and not policy.get("cell_free_enabled", False):
        return True
    if has_feature_token("sub_thz") and not policy.get("sub_thz_enabled", False):
        return True
    return False


def filter_public_artifacts_for_policy(
    artifacts: list[dict[str, Any]],
    feature_policy: dict[str, bool] | None,
) -> list[dict[str, Any]]:
    return [
        art
        for art in artifacts
        if not artifact_is_policy_filtered(str(art.get("logical_path") or ""), feature_policy)
    ]


def contract_table_candidate_paths(table_spec_or_name: Any) -> list[str]:
    if isinstance(table_spec_or_name, dict):
        table_spec = dict(table_spec_or_name)
        name = str(table_spec.get("table_name") or "").strip()
        primary_path = str(table_spec.get("logical_path") or "").strip()
    else:
        table_spec = {}
        name = str(table_spec_or_name or "").strip()
        primary_path = ""
    if not name:
        return []
    paths: list[str] = []
    if primary_path:
        paths.append(primary_path)
    paths.extend(list(CONTRACT_TABLE_ALIAS_PATHS.get(name, [])))
    for path in output_family_candidate_paths(name):
        if path not in paths:
            paths.append(path)
    return paths


def contract_chart_candidate_paths(chart_spec_or_name: Any) -> list[str]:
    if isinstance(chart_spec_or_name, dict):
        chart_spec = dict(chart_spec_or_name)
        chart_name = str(chart_spec.get("chart_name") or "").strip()
        paths = [
            contract_materializer.chart_contract_image_path(chart_spec),
            contract_materializer.chart_contract_csv_path(chart_spec),
        ]
    else:
        chart_name = str(chart_spec_or_name or "").strip()
        paths = []
    for path in CONTRACT_CHART_ALIAS_PATHS.get(chart_name, []):
        if path not in paths:
            paths.append(path)
    return paths


def build_contract_table_evidence(
    table_spec: dict[str, Any],
    artifacts: list[dict[str, Any]],
    unavailable_index: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    table_name = str(table_spec.get("table_name") or "").strip()
    matches: list[dict[str, Any]] = []
    empty_matches: list[dict[str, Any]] = []
    for logical_path in contract_table_candidate_paths(table_spec):
        art = find_artifact_by_logical_path(artifacts, logical_path)
        if art is None or artifact_is_legacy_mirror(str(art.get("logical_path") or "")):
            continue
        descriptor = build_artifact_descriptor(art)
        preview_rows = load_small_csv_rows(artifacts, logical_path, max_rows=4)
        descriptor["preview_row_count"] = len(preview_rows)
        if preview_rows:
            matches.append(descriptor)
        else:
            empty_matches.append(descriptor)
    if matches:
        return {
            "status": "available",
            "status_label": "available",
            "status_class": "good",
            "reason": "db_backed_contract_alias",
            "lineage_note": "DB-backed artifact published for this run.",
            "matches": matches,
        }
    if empty_matches:
        return {
            "status": "empty",
            "status_label": "empty source",
            "status_class": "warn",
            "reason": "artifact_present_but_no_rows",
            "lineage_note": "A canonical or aliased source artifact exists, but it currently has no real rows.",
            "matches": empty_matches,
        }
    unavailable = unavailable_index.get(table_name) or {}
    return {
        "status": "unavailable",
        "status_label": "unavailable",
        "status_class": "warn",
        "reason": str(unavailable.get("unavailable_reason") or "").strip() or "no_db_backed_contract_artifact",
        "lineage_note": str(unavailable.get("next_implementation_step") or "").strip() or "No canonical artifact or honest alias is persisted for this run.",
        "matches": [],
    }


def build_contract_chart_evidence(
    section: dict[str, Any],
    chart_spec: dict[str, Any],
    artifacts: list[dict[str, Any]],
    numeric_charts: list[dict[str, Any]],
    table_evidence: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    chart_name = str(chart_spec.get("chart_name") or "").strip()
    if str(section.get("slug") or "") == "optional-6g-extension-analytics" or chart_name in OPTIONAL_6G_CHARTS:
        return {
            "status": "policy_disabled",
            "status_label": "policy disabled",
            "status_class": "warn",
            "reason": "feature_policy_disabled_for_this_run",
            "lineage_note": "Optional 6G/AI/NTN-style analytics are intentionally suppressed for this NR-only honest run.",
            "matches": [],
        }
    image_matches: list[dict[str, Any]] = []
    table_matches: list[dict[str, Any]] = []
    numeric_matches: list[dict[str, Any]] = []
    for logical_path in contract_chart_candidate_paths(chart_spec):
        art = find_artifact_by_logical_path(artifacts, logical_path)
        if art is None:
            continue
        descriptor = build_artifact_descriptor(art)
        if str(art.get("mime_type") or "").startswith("image/"):
            image_matches.append(descriptor)
        elif str(art.get("artifact_kind") or "") == "table_csv":
            table_matches.append(descriptor)
            artifact_id = int(art.get("artifact_id") or 0)
            chart = next((row for row in numeric_charts if int(row.get("artifact_id") or 0) == artifact_id), None)
            if chart is not None:
                numeric_matches.append(chart)
    if image_matches:
        return {
            "status": "image",
            "status_label": "published image artifact",
            "status_class": "good",
            "reason": "selected_run_image_artifact",
            "lineage_note": "A persisted image artifact exists for this chart family.",
            "matches": image_matches,
        }
    if numeric_matches:
        return {
            "status": "numeric_chart",
            "status_label": "published in selected run",
            "status_class": "good",
            "reason": "selected_run_numeric_chart_rows",
            "lineage_note": "Numeric chart rows are available and rendered from the selected run.",
            "matches": numeric_matches,
            "source_matches": table_matches,
        }
    if table_matches:
        return {
            "status": "table_source",
            "status_label": "chartable source table present",
            "status_class": "good",
            "reason": "selected_run_chart_source_table",
            "lineage_note": "A persisted source table exists for this chart family.",
            "matches": table_matches,
        }
    section_table_names = {str(row.get("table_name") or "") for row in (section.get("tables") or [])}
    section_available = [
        evidence
        for table_name, evidence in table_evidence.items()
        if table_name in section_table_names and evidence.get("status") in {"available", "empty"}
    ]
    if section_available:
        return {
            "status": "section_source",
            "status_label": "section source table present",
            "status_class": "good",
            "reason": "selected_run_section_table_present",
            "lineage_note": "This section has DB-backed tables that can be used to derive the chart truthfully.",
            "matches": section_available[0].get("matches") or [],
        }
    return {
        "status": "unavailable",
        "status_label": "unavailable until real source rows exist",
        "status_class": "warn",
        "reason": chart_spec.get("default_status") or "unavailable_until_source_table_has_real_rows",
        "lineage_note": "No matching image artifact, numeric chart rows, or DB-backed source table was published for this run.",
        "matches": [],
    }


def build_output_contract_surface(
    run_row: dict[str, Any],
    artifacts: list[dict[str, Any]],
    numeric_charts: list[dict[str, Any]],
    summary_charts: list[dict[str, Any]],
    output_coverage: dict[str, Any],
) -> dict[str, Any]:
    feature_policy = extract_run_feature_policy(run_row)
    public_artifacts = filter_public_artifacts_for_policy(artifacts, feature_policy)
    numeric_pool = list(numeric_charts or []) + list(summary_charts or [])
    unavailable_index = {
        str(row.get("output_name") or ""): row
        for row in (output_coverage.get("honest_unavailable") or [])
        if str(row.get("output_name") or "").strip()
    }
    surface: dict[str, Any] = {"feature_policy": feature_policy}
    for kind in ("reports", "analytics"):
        sections_out: list[dict[str, Any]] = []
        for section in output_contract.product_sections_payload(kind):
            table_evidence: dict[str, dict[str, Any]] = {}
            tables_out: list[dict[str, Any]] = []
            for table_spec in section.get("tables") or []:
                if str(table_spec.get("table_name") or "") in OPTIONAL_6G_TABLES:
                    evidence = {
                        "status": "policy_disabled",
                        "status_label": "policy disabled",
                        "status_class": "warn",
                        "reason": "feature_policy_disabled_for_this_run",
                        "lineage_note": "Optional 6G/AI/NTN-style analytics are intentionally suppressed for this NR-only honest run.",
                        "matches": [],
                    }
                else:
                    evidence = build_contract_table_evidence(table_spec, public_artifacts, unavailable_index)
                table_evidence[str(table_spec.get("table_name") or "")] = evidence
                tables_out.append({**table_spec, "evidence": evidence})
            charts_out = [
                {**chart_spec, "evidence": build_contract_chart_evidence(section, chart_spec, public_artifacts, numeric_pool, table_evidence)}
                for chart_spec in (section.get("charts") or [])
            ]
            sections_out.append({**section, "tables": tables_out, "charts": charts_out})
        surface[kind] = sections_out
    return surface


def dedupe_descriptor_list(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    out: list[dict[str, Any]] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        key = str(item.get("artifact_id") or item.get("logical_path") or "").strip()
        if not key or key in seen:
            continue
        seen.add(key)
        out.append(item)
    return out


def dedupe_numeric_chart_rows(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    out: list[dict[str, Any]] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        key = str(item.get("chart_id") or item.get("artifact_id") or item.get("title") or "").strip()
        if not key or key in seen:
            continue
        seen.add(key)
        out.append(item)
    return out


def build_contract_section_payload(run_id: int, *, kind: str, slug: str) -> dict[str, Any]:
    kind_token = str(kind or "").strip().lower()
    if kind_token not in {"reports", "analytics"}:
        raise KeyError(f"Unsupported contract section kind: {kind}")
    slug_token = str(slug or "").strip().lower()
    if not slug_token:
        raise KeyError("A non-empty section slug is required.")
    run_row = fetch_run(run_id)
    if run_row is None:
        raise KeyError(f"Run {run_id} was not found.")
    inserted_logs = sync_runtime_log_for_run(run_row)
    if inserted_logs:
        run_row = fetch_run(run_id) or run_row
    artifacts = fetch_artifacts(run_id)
    feature_policy = extract_run_feature_policy(run_row)
    status_text = str(run_row.get("status_text") or "").strip().lower()
    contract_prefix = f"contract__{slug_token}__"
    has_section_contract_artifacts = any(
        contract_prefix in str(art.get("logical_path") or "").strip().lower()
        and (
            str(art.get("artifact_kind") or "") == "table_csv"
            or str(art.get("mime_type") or "").startswith("image/")
        )
        for art in artifacts
    )
    should_materialize_contract = (
        (is_terminal_status(status_text) and not has_section_contract_artifacts)
        or (
            status_text == "running"
            and any(str(art.get("artifact_kind") or "") == "table_csv" for art in artifacts)
        )
    )
    if should_materialize_contract:
        contract_materializer.materialize_run_contract_artifacts(
            run_row,
            artifacts,
            fetch_artifact_bytes=fetch_artifact_bytes,
            db_connection_factory=db_connection,
            feature_policy=feature_policy,
            lock_timeout_seconds=0,
        )
        artifacts = fetch_artifacts(run_id)
    latest_artifact_id = max((int(art.get("artifact_id") or 0) for art in artifacts), default=0)
    artifact_version = f"{len(artifacts)}|{latest_artifact_id}"
    cache_key = (int(run_id), kind_token, slug_token, artifact_version)
    cached_payload = SECTION_PAYLOAD_CACHE.get(cache_key)
    if cached_payload is not None:
        return cached_payload
    public_artifacts = filter_public_artifacts_for_policy(artifacts, feature_policy)
    output_coverage = build_output_coverage_context(artifacts)
    unavailable_index = {
        str(row.get("output_name") or ""): row
        for row in (output_coverage.get("honest_unavailable") or [])
        if str(row.get("output_name") or "").strip()
    }
    section = next(
        (item for item in output_contract.product_sections_payload(kind_token) if str(item.get("slug") or "").strip().lower() == slug_token),
        None,
    )
    if section is None:
        raise KeyError(f"{kind_token.title()} section {slug!r} was not found.")
    contract_table_artifacts = [
        art
        for art in public_artifacts
        if str(art.get("artifact_kind") or "") == "table_csv"
        and contract_prefix in str(art.get("logical_path") or "").strip().lower()
    ]
    numeric_charts = build_numeric_charts_from_artifacts(contract_table_artifacts, limit=64)
    table_evidence: dict[str, dict[str, Any]] = {}
    tables_out: list[dict[str, Any]] = []
    for table_spec in section.get("tables") or []:
        if str(table_spec.get("table_name") or "") in OPTIONAL_6G_TABLES:
            evidence = {
                "status": "policy_disabled",
                "status_label": "policy disabled",
                "status_class": "warn",
                "reason": "feature_policy_disabled_for_this_run",
                "lineage_note": "Optional 6G/AI/NTN-style analytics are intentionally suppressed for this NR-only honest run.",
                "matches": [],
            }
        else:
            evidence = build_contract_table_evidence(table_spec, public_artifacts, unavailable_index)
        table_name = str(table_spec.get("table_name") or "")
        table_evidence[table_name] = evidence
        tables_out.append({**table_spec, "evidence": evidence})
    charts_out: list[dict[str, Any]] = []
    for chart_spec in section.get("charts") or []:
        evidence = build_contract_chart_evidence(section, chart_spec, public_artifacts, numeric_charts, table_evidence)
        charts_out.append({**chart_spec, "evidence": evidence})
    section_out = {**section, "tables": tables_out, "charts": charts_out}

    scoped_tables = [
        build_artifact_descriptor(art)
        for art in public_artifacts
        if str(art.get("artifact_kind") or "") == "table_csv"
        and contract_prefix in str(art.get("logical_path") or "").strip().lower()
    ]
    scoped_images = [
        build_artifact_descriptor(art)
        for art in public_artifacts
        if str(art.get("mime_type") or "").startswith("image/")
        and contract_prefix in str(art.get("logical_path") or "").strip().lower()
    ]
    contract_table_matches: list[dict[str, Any]] = []
    chart_table_matches: list[dict[str, Any]] = []
    chart_image_matches: list[dict[str, Any]] = []
    numeric_matches: list[dict[str, Any]] = []
    unavailable_rows: list[dict[str, Any]] = []
    for table in tables_out:
        evidence = dict(table.get("evidence") or {})
        matches = [row for row in (evidence.get("matches") or []) if isinstance(row, dict)]
        contract_table_matches.extend([row for row in matches if str(row.get("artifact_kind") or "").find("table") >= 0])
        if not matches:
            unavailable_rows.append(
                {
                    "type": "table",
                    "name": str(table.get("table_name") or ""),
                    "reason": str(evidence.get("reason") or evidence.get("lineage_note") or "No canonical table artifact was published for this run."),
                }
            )
    for chart in charts_out:
        evidence = dict(chart.get("evidence") or {})
        matches = [row for row in (evidence.get("matches") or []) if isinstance(row, dict)]
        numeric = [row for row in matches if row.get("series") is not None]
        numeric_matches.extend(numeric)
        chart_image_matches.extend([row for row in matches if str(row.get("mime_type") or "").startswith("image/")])
        chart_table_matches.extend([row for row in matches if str(row.get("artifact_kind") or "").find("table") >= 0])
        chart_table_matches.extend([row for row in (evidence.get("source_matches") or []) if isinstance(row, dict)])
        if not matches and not evidence.get("source_matches"):
            unavailable_rows.append(
                {
                    "type": "chart",
                    "name": str(chart.get("chart_name") or ""),
                    "reason": str(evidence.get("reason") or evidence.get("lineage_note") or "No matching chart evidence was published for this run."),
                }
            )
    evidence_bundle = {
        "tableArtifacts": dedupe_descriptor_list(scoped_tables + contract_table_matches + chart_table_matches),
        "imageArtifacts": dedupe_descriptor_list(scoped_images + chart_image_matches),
        "numericCharts": dedupe_numeric_chart_rows(numeric_matches),
        "unavailableRows": unavailable_rows,
        "kind": kind_token,
    }
    payload = {
        "run_id": int(run_id),
        "kind": kind_token,
        "slug": slug_token,
        "artifact_version": artifact_version,
        "section": {**section_out, "evidence_bundle": evidence_bundle},
    }
    SECTION_PAYLOAD_CACHE[cache_key] = payload
    return payload


def localEstimatedProjectedLatLon(
    x_m: Any,
    y_m: Any,
    *,
    anchor_lat: float = float(DEFAULT_MAP_CENTER["lat"]),
    anchor_lon: float = float(DEFAULT_MAP_CENTER["lon"]),
) -> tuple[float | None, float | None]:
    x = coerce_numeric(x_m)
    y = coerce_numeric(y_m)
    if x is None or y is None:
        return None, None
    return project_local_xy_to_geo(float(x), float(y), anchor_lat=anchor_lat, anchor_lon=anchor_lon)


def project_local_xy_to_geo(
    x_m: float,
    y_m: float,
    *,
    anchor_lat: float = float(DEFAULT_MAP_CENTER["lat"]),
    anchor_lon: float = float(DEFAULT_MAP_CENTER["lon"]),
) -> tuple[float, float]:
    radius_m = 6_378_137.0
    lat1 = math.radians(anchor_lat)
    lon1 = math.radians(anchor_lon)
    distance = math.hypot(float(x_m), float(y_m))
    if distance <= 0:
        return float(anchor_lat), float(anchor_lon)
    bearing = math.atan2(float(x_m), float(y_m))
    angular = distance / radius_m
    lat2 = math.asin(
        math.sin(lat1) * math.cos(angular)
        + math.cos(lat1) * math.sin(angular) * math.cos(bearing)
    )
    lon2 = lon1 + math.atan2(
        math.sin(bearing) * math.sin(angular) * math.cos(lat1),
        math.cos(angular) - math.sin(lat1) * math.sin(lat2),
    )
    return math.degrees(lat2), math.degrees(lon2)


def resolve_row_coordinates(row: dict[str, Any]) -> tuple[float | None, float | None]:
    coordinate_mode = str(row.get("CoordinateMode") or row.get("coordinate_mode") or "").strip().lower()
    if coordinate_mode.startswith("projected"):
        lat, lon = localEstimatedProjectedLatLon(row.get("X_m"), row.get("Y_m"))
        if lat is not None and lon is not None:
            return lat, lon
    return coerce_numeric(row.get("Lat")), coerce_numeric(row.get("Lon"))


def estimate_site_spacing_m(site_rows: list[dict[str, Any]]) -> float | None:
    points: list[tuple[float, float]] = []
    seen: set[tuple[float, float]] = set()
    for row in site_rows:
        x = coerce_numeric(row.get("X_m"))
        y = coerce_numeric(row.get("Y_m"))
        if x is None or y is None:
            continue
        key = (round(float(x), 6), round(float(y), 6))
        if key in seen:
            continue
        seen.add(key)
        points.append((float(x), float(y)))
    if len(points) < 2:
        return None
    min_dist = math.inf
    for idx in range(len(points)):
        x1, y1 = points[idx]
        for jdx in range(idx + 1, len(points)):
            x2, y2 = points[jdx]
            dist = math.hypot(x2 - x1, y2 - y1)
            if dist > 1e-9:
                min_dist = min(min_dist, dist)
    return None if not math.isfinite(min_dist) else float(min_dist)


def build_geometry_rows(artifacts: list[dict[str, Any]], logical_path: str, *, max_rows: int = 4096) -> list[dict[str, Any]]:
    return load_small_csv_rows(artifacts, logical_path, max_rows=max_rows)


def row_coord_mode(row: dict[str, Any]) -> str:
    return str(row.get("CoordinateMode") or row.get("coordinate_mode") or "").strip().lower()


def offset_row_coordinates(row: dict[str, Any], dx_m: float, dy_m: float) -> tuple[float | None, float | None]:
    x = coerce_numeric(row.get("X_m"))
    y = coerce_numeric(row.get("Y_m"))
    if row_coord_mode(row).startswith("projected") and x is not None and y is not None:
        return project_local_xy_to_geo(float(x + dx_m), float(y + dy_m))
    lat, lon = resolve_row_coordinates(row)
    if lat is None or lon is None:
        return None, None
    return project_local_xy_to_geo(float(dx_m), float(dy_m), anchor_lat=float(lat), anchor_lon=float(lon))


def build_site_geometry(site_rows: list[dict[str, Any]], spacing_m: float | None) -> tuple[list[dict[str, Any]], dict[int, dict[str, Any]]]:
    shapes: list[dict[str, Any]] = []
    site_index: dict[int, dict[str, Any]] = {}
    if not site_rows:
        return shapes, site_index
    polygon_radius_m = max(40.0, float(spacing_m or 160.0) / math.sqrt(3.0))
    for row in site_rows:
        site_id = int(coerce_numeric(row.get("SiteID")) or len(site_index) + 1)
        lat, lon = resolve_row_coordinates(row)
        if lat is None or lon is None:
            continue
        site_index[site_id] = row
        vertices: list[list[float]] = []
        for angle_deg in range(30, 390, 60):
            vx = polygon_radius_m * math.cos(math.radians(angle_deg))
            vy = polygon_radius_m * math.sin(math.radians(angle_deg))
            plat, plon = offset_row_coordinates(row, vx, vy)
            if plat is not None and plon is not None:
                vertices.append([plat, plon])
        if len(vertices) >= 3:
            shapes.append(
                {
                    "site_id": site_id,
                    "label": f"Site {site_id}",
                    "points": vertices,
                }
            )
    return shapes, site_index


def build_sector_geometry(
    sector_rows: list[dict[str, Any]],
    site_index: dict[int, dict[str, Any]],
    spacing_m: float | None,
) -> list[dict[str, Any]]:
    shapes: list[dict[str, Any]] = []
    if not sector_rows:
        return shapes
    sectors_per_site: dict[int, int] = {}
    for row in sector_rows:
        site_id = int(coerce_numeric(row.get("SiteID")) or 0)
        if site_id > 0:
            sectors_per_site[site_id] = sectors_per_site.get(site_id, 0) + 1
    outer_radius_m = max(60.0, float(spacing_m or 160.0) * 0.52)
    for row in sector_rows:
        site_id = int(coerce_numeric(row.get("SiteID")) or 0)
        sector_id = int(coerce_numeric(row.get("SectorID")) or 0)
        azimuth_deg = float(coerce_numeric(row.get("Azimuth_deg")) or 0.0)
        site_row = site_index.get(site_id, row)
        n_site_sectors = max(1, sectors_per_site.get(site_id, 1))
        span_deg = max(45.0, min(180.0, 360.0 / float(n_site_sectors)))
        left_deg = azimuth_deg - 0.5 * span_deg
        right_deg = azimuth_deg + 0.5 * span_deg
        left_xy = (
            outer_radius_m * math.cos(math.radians(left_deg)),
            outer_radius_m * math.sin(math.radians(left_deg)),
        )
        right_xy = (
            outer_radius_m * math.cos(math.radians(right_deg)),
            outer_radius_m * math.sin(math.radians(right_deg)),
        )
        center_latlon = resolve_row_coordinates(site_row)
        left_latlon = offset_row_coordinates(site_row, left_xy[0], left_xy[1])
        right_latlon = offset_row_coordinates(site_row, right_xy[0], right_xy[1])
        if None in center_latlon or None in left_latlon or None in right_latlon:
            continue
        shapes.append(
            {
                "site_id": site_id,
                "sector_id": sector_id,
                "azimuth_deg": azimuth_deg,
                "label": f"Site {site_id} Sector {sector_id}",
                "points": [
                    [float(center_latlon[0]), float(center_latlon[1])],
                    [float(left_latlon[0]), float(left_latlon[1])],
                    [float(right_latlon[0]), float(right_latlon[1])],
                ],
            }
        )
    return shapes


def build_live_ue_markers(movement: dict[str, Any], fallback_markers: list[dict[str, Any]]) -> list[dict[str, Any]]:
    points = list(movement.get("points") or [])
    if not points:
        return fallback_markers
    latest_by_ue: dict[int, dict[str, Any]] = {}
    for point in points:
        ueid = int(coerce_numeric(point.get("ueid")) or 0)
        slot = int(coerce_numeric(point.get("slot")) or -1)
        if ueid <= 0:
            continue
        prev = latest_by_ue.get(ueid)
        if prev is None or slot >= int(prev.get("slot") or -1):
            latest_by_ue[ueid] = point
    markers: list[dict[str, Any]] = []
    for ueid in sorted(latest_by_ue)[:160]:
        point = latest_by_ue[ueid]
        lat = coerce_numeric(point.get("lat"))
        lon = coerce_numeric(point.get("lon"))
        if lat is None or lon is None:
            continue
        markers.append(
            {
                "lat": float(lat),
                "lon": float(lon),
                "label": f"UE {ueid}",
                "type": "ue",
                "source": "reports/csv/live_rsrp_serving_trace.csv",
                "slot": int(coerce_numeric(point.get('slot')) or 0),
                "serving_cell": coerce_numeric(point.get("serving_cell")),
            }
        )
    return markers or fallback_markers


def infer_runtime_truth_modes(config: dict[str, Any], operating_mode: list[dict[str, Any]]) -> dict[str, Any]:
    browser_cfg = config if isinstance(config, dict) else {}
    if isinstance(browser_cfg.get("lls6g"), dict):
        submitted = browser_cfg["lls6g"].get("submittedScenarioConfig")
        if isinstance(submitted, dict) and submitted:
            browser_cfg = submitted
    truth_modes = dict(infer_browser_truth_modes(browser_cfg))
    if isinstance(operating_mode, list):
        for row in operating_mode:
            if not isinstance(row, dict):
                continue
            if row.get("BrowserExecutionMode"):
                mode_token = str(row.get("BrowserExecutionMode") or "").strip().upper()
                truth_modes["browser_execution_mode"] = mode_token
                truth_modes["browser_execution_mode_label"] = BROWSER_EXECUTION_MODE_LABELS.get(mode_token, mode_token)
            if row.get("NoiseOperatingMode"):
                truth_modes["noise_operating_mode"] = str(row.get("NoiseOperatingMode") or "")
            if row.get("DopplerSourceMode"):
                truth_modes["doppler_source_mode"] = str(row.get("DopplerSourceMode") or "")
            if row.get("InterferenceMode"):
                truth_modes["interference_mode"] = str(row.get("InterferenceMode") or "")
            if row.get("ControlIntegrationMode"):
                truth_modes["control_integration_mode"] = str(row.get("ControlIntegrationMode") or "")
            for key, row_key in {
                "execution_model": "UserExecutionModel",
                "execution_backend": "ExecutionBackend",
                "phy_mode": "PHYMode",
            }.items():
                if row.get(row_key):
                    truth_modes[key] = str(row.get(row_key) or "")
            for key, row_key in {
                "waveform_phy_active": "WaveformPHYActive",
                "proxy_phy_active": "ProxyPHYActive",
                "fallback_used": "FallbackUsed",
            }.items():
                if row.get(row_key) is not None:
                    truth_modes[key] = is_truthy_value(row.get(row_key))
            if row.get("ExecutionModel") and not truth_modes.get("execution_model"):
                truth_modes["execution_model"] = str(row.get("ExecutionModel") or "")
            for key, row_key in {
                "pbch_mode": "PBCHMode",
                "prach_mode": "PRACHMode",
                "pdcch_mode": "PDCCHMode",
                "pucch_mode": "PUCCHMode",
                "srs_mode": "SRSMode",
                "trs_mode": "TRSMode",
            }.items():
                if row.get(row_key):
                    truth_modes[key] = str(row.get(row_key) or "")
            for key, row_key in {
                "pbch_gating_active": "PBCHGatingActive",
                "prach_gating_active": "PRACHGatingActive",
                "pdcch_gating_active": "PDCCHGatingActive",
                "srs_gating_active": "SRSGatingActive",
                "trs_gating_active": "TRSGatingActive",
            }.items():
                if row.get(row_key) is not None:
                    truth_modes[key] = is_truthy_value(row.get(row_key))
            for key, row_key in {
                "trs_runtime_consumer": "TRSRuntimeConsumer",
                "trs_influence_definition": "TRSInfluenceDefinition",
                "trs_receiver_integration_status": "TRSReceiverIntegrationStatus",
                "trs_receiver_integration_blocker": "TRSReceiverIntegrationBlocker",
                "system_level_sinr_source": "SystemLevelSINRSource",
                "system_level_sinr_value_role": "SystemLevelSINRValueRole",
                "system_level_sinr_value_status": "SystemLevelSINRValueStatus",
                "receiver_hest_sinr_source": "ReceiverHestSINRSource",
                "receiver_hest_sinr_value_status": "ReceiverHestSINRValueStatus",
                "decoder_truth_proxy_sinr_source": "DecoderTruthProxySINRSource",
                "decoder_truth_proxy_sinr_value_status": "DecoderTruthProxySINRValueStatus",
                "measured_trial_sinr_source": "MeasuredTrialSINRSource",
                "measured_trial_sinr_value_status": "MeasuredTrialSINRValueStatus",
                "explicit_precoder_replay_status": "ExplicitPrecoderReplayStatus",
                "explicit_precoder_replay_blocker": "ExplicitPrecoderReplayBlocker",
                "antenna_runtime_object_source": "AntennaRuntimeObjectSource",
                "antenna_runtime_object_value_status": "AntennaRuntimeObjectValueStatus",
                "channel_array_model": "ChannelArrayModel",
                "channel_object_source": "ChannelObjectSource",
                "channel_object_class": "ChannelObjectClass",
                "channel_array_handling_status": "ChannelArrayHandlingStatus",
                "channel_array_handling_blocker": "ChannelArrayHandlingBlocker",
                "channel_array_value_status": "ChannelArrayValueStatus",
                "interference_channel_object_source": "InterferenceChannelObjectSource",
                "interference_channel_object_class": "InterferenceChannelObjectClass",
                "interference_channel_array_handling_status": "InterferenceChannelArrayHandlingStatus",
                "interference_channel_array_handling_blocker": "InterferenceChannelArrayHandlingBlocker",
                "interference_channel_array_value_status": "InterferenceChannelArrayValueStatus",
                "traffic_flow_source": "TrafficFlowSource",
                "traffic_flow_derivation_mode": "TrafficFlowDerivationMode",
            }.items():
                if row.get(row_key):
                    truth_modes[key] = str(row.get(row_key) or "")
            if row.get("TrafficFlowResolvedFlag") is not None:
                truth_modes["traffic_flow_resolved_flag"] = is_truthy_value(row.get("TrafficFlowResolvedFlag"))
            if row.get("TRSInfluencedDecision") is not None:
                truth_modes["trs_influenced_decision"] = is_truthy_value(row.get("TRSInfluencedDecision"))
            for key, row_key in {
                "channel_uses_same_runtime_antenna_assumptions": "ChannelUsesSameRuntimeAntennaAssumptions",
                "interference_uses_same_runtime_antenna_assumptions": "InterferenceUsesSameRuntimeAntennaAssumptions",
                "interference_path_uses_same_array_assumptions": "InterferencePathUsesSameArrayAssumptions",
            }.items():
                if row.get(row_key) is not None:
                    truth_modes[key] = is_truthy_value(row.get(row_key))
            if row.get("ParallelExecutionActive") is not None:
                truth_modes["parallel_execution_active"] = is_truthy_value(row.get("ParallelExecutionActive"))
            if row.get("EffectiveWorkers") is not None:
                truth_modes["effective_workers"] = coerce_numeric(row.get("EffectiveWorkers"))
            if row.get("CoupledGrantExecutionMode"):
                truth_modes["coupled_grant_execution_mode"] = str(row.get("CoupledGrantExecutionMode") or "")
            if row.get("ParallelDisabledReason"):
                truth_modes["parallel_disabled_reason"] = str(row.get("ParallelDisabledReason") or "")
    return truth_modes


def build_config_snapshot_context(run_row: dict[str, Any], artifacts: list[dict[str, Any]], config: dict[str, Any] | None = None) -> dict[str, Any]:
    config = config if isinstance(config, dict) else parse_config_json(run_row)
    lls_cfg = config.get("lls6g", {}) if isinstance(config.get("lls6g"), dict) else {}
    submitted = lls_cfg.get("submittedScenarioConfig", {}) if isinstance(lls_cfg.get("submittedScenarioConfig"), dict) else {}
    source_files_raw = lls_cfg.get("scenarioSourceFiles", [])
    source_files = [str(item) for item in source_files_raw] if isinstance(source_files_raw, list) else []
    downloads: dict[str, Any] = {}
    for key, logical_path in {
        "resolved_json": "meta/scenario_config_resolved.json",
        "resolved_yaml": "meta/scenario_config_resolved.yaml",
        "source_chain": "meta/scenario_source_chain.csv",
        "config_roundtrip_verification": "reports/csv/config_roundtrip_verification.csv",
        "browser_runtime_db_consistency": "reports/csv/browser_runtime_db_consistency.csv",
        "summary_vs_raw_consistency": "reports/csv/summary_vs_raw_consistency.csv",
        "value_source_audit": "reports/csv/value_source_audit.csv",
    }.items():
        art = find_artifact_by_logical_path(artifacts, logical_path)
        if art:
            downloads[key] = build_artifact_descriptor(art)
    return {
        "submitted_present": bool(submitted),
        "submitted_field_count": len(flatten_config_fields(submitted)) if submitted else 0,
        "source_files": source_files,
        "browser_execution_path": str(lls_cfg.get("browserExecutionPath") or ""),
        "downloads": downloads,
    }


def summarize_raw_trial_lifecycle_rows(rows: list[dict[str, Any]]) -> dict[str, Any]:
    summary = {
        "status": "exact",
        "row_count": 0,
        "finalized_rows": 0,
        "partial_rows": 0,
        "crashed_rows": 0,
        "finalized_secondary_gap_rows": 0,
        "secondary_gap_rows": 0,
    }
    for row in rows:
        if not isinstance(row, dict):
            continue
        summary["row_count"] += 1
        state = str(row.get("RowLifecycleState") or "").strip().lower()
        finalized = is_truthy_value(row.get("FinalizedFlag")) or state == "finalized"
        partial = is_truthy_value(row.get("PartialRowFlag")) or state == "partial"
        crashed = state == "crashed" or is_truthy_value(row.get("Crash"))
        secondary_gap = is_truthy_value(row.get("SecondaryFieldGapFlag"))
        if finalized:
            summary["finalized_rows"] += 1
        if partial:
            summary["partial_rows"] += 1
        if crashed:
            summary["crashed_rows"] += 1
        if secondary_gap:
            summary["secondary_gap_rows"] += 1
        if finalized and secondary_gap:
            summary["finalized_secondary_gap_rows"] += 1
    return summary


def build_raw_trial_lifecycle_context(artifacts: list[dict[str, Any]]) -> dict[str, Any]:
    context: dict[str, Any] = {}
    for direction, logical_path in (
        ("dl", "air_interface/csv/dl_pdsch_trials.csv"),
        ("ul", "air_interface/csv/ul_pusch_trials.csv"),
    ):
        art = find_artifact_by_logical_path(artifacts, logical_path)
        if art is None:
            continue
        byte_size = int(art.get("byte_size") or 0)
        if byte_size > 1_500_000:
            context[direction] = {
                "status": "not_sampled_large_artifact",
                "logical_path": logical_path,
                "byte_size": byte_size,
            }
            continue
        rows = load_small_csv_rows(artifacts, logical_path, max_rows=50000)
        summary = summarize_raw_trial_lifecycle_rows(rows)
        summary["logical_path"] = logical_path
        summary["byte_size"] = byte_size
        context[direction] = summary
    return context


def extract_runtime_context(run_row: dict[str, Any], artifacts: list[dict[str, Any]]) -> dict[str, Any]:
    operating_mode, operating_mode_source = select_canonical_csv_rows(
        artifacts,
        CANONICAL_RUNTIME_ARTIFACT_OWNERS["runtime_operating_mode"]["canonical_path"],
        legacy_paths=CANONICAL_RUNTIME_ARTIFACT_OWNERS["runtime_operating_mode"]["legacy_paths"],
        max_rows=8,
        owner_kind=str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["runtime_operating_mode"]["owner_kind"]),
    )
    config_roundtrip_rows = load_small_csv_rows(artifacts, "reports/csv/config_roundtrip_verification.csv", max_rows=512)
    browser_runtime_db_rows = load_small_csv_rows(artifacts, "reports/csv/browser_runtime_db_consistency.csv", max_rows=512)
    summary_vs_raw_rows = load_small_csv_rows(artifacts, "reports/csv/summary_vs_raw_consistency.csv", max_rows=128)
    value_source_audit_rows = load_small_csv_rows(artifacts, "reports/csv/value_source_audit.csv", max_rows=256)
    truth_contract_summary_rows = load_small_csv_rows(artifacts, "reports/csv/truth_contract_summary.csv", max_rows=8)
    truth_contract_failure_rows = load_small_csv_rows(artifacts, "reports/csv/truth_contract_failures.csv", max_rows=128)
    control_summary_rows, control_summary_source = select_canonical_csv_rows(
        artifacts,
        CANONICAL_RUNTIME_ARTIFACT_OWNERS["control_summary"]["canonical_path"],
        legacy_paths=CANONICAL_RUNTIME_ARTIFACT_OWNERS["control_summary"]["legacy_paths"],
        max_rows=4,
        owner_kind=str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["control_summary"]["owner_kind"]),
    )
    control_state_rows, control_state_source = select_canonical_csv_rows(
        artifacts,
        CANONICAL_RUNTIME_ARTIFACT_OWNERS["control_state"]["canonical_path"],
        legacy_paths=CANONICAL_RUNTIME_ARTIFACT_OWNERS["control_state"]["legacy_paths"],
        max_rows=16,
        owner_kind=str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["control_state"]["owner_kind"]),
    )
    pucch_grant_rows, pucch_grant_source = select_canonical_csv_rows(
        artifacts,
        CANONICAL_RUNTIME_ARTIFACT_OWNERS["pucch_grants"]["canonical_path"],
        legacy_paths=CANONICAL_RUNTIME_ARTIFACT_OWNERS["pucch_grants"]["legacy_paths"],
        max_rows=16,
        owner_kind=str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["pucch_grants"]["owner_kind"]),
    )
    control_trial_previews: dict[str, list[dict[str, Any]]] = {}
    control_trial_sources: dict[str, dict[str, Any]] = {}
    for control_key in ("pbch_trials", "prach_trials", "pdcch_trials", "pucch_trials", "srs_trials", "trs_trials"):
        control_rows, control_source = select_canonical_csv_rows(
            artifacts,
            CANONICAL_RUNTIME_ARTIFACT_OWNERS[control_key]["canonical_path"],
            legacy_paths=CANONICAL_RUNTIME_ARTIFACT_OWNERS[control_key]["legacy_paths"],
            max_rows=16,
            owner_kind=str(CANONICAL_RUNTIME_ARTIFACT_OWNERS[control_key]["owner_kind"]),
        )
        control_trial_previews[control_key] = control_rows
        control_trial_sources[control_key] = control_source
    trs_trial_rows = control_trial_previews.get("trs_trials", [])
    trs_trial_source = control_trial_sources.get("trs_trials", {})
    channel_array_rows = load_small_csv_rows(artifacts, "reports/csv/channel_array_consistency.csv", max_rows=8)
    antenna_runtime_rows = load_small_csv_rows(artifacts, "reports/csv/antenna_runtime_evidence.csv", max_rows=8)
    deployment_rows = load_small_csv_rows(artifacts, "reports/csv/deployment_layout_reference.csv", max_rows=2)
    deployment = deployment_rows[0] if deployment_rows else {}
    status_json = parse_status_json(run_row)
    stage_rows, stage_source = select_canonical_csv_rows(
        artifacts,
        CANONICAL_RUNTIME_ARTIFACT_OWNERS["stage_status"]["canonical_path"],
        legacy_paths=CANONICAL_RUNTIME_ARTIFACT_OWNERS["stage_status"]["legacy_paths"],
        max_rows=4,
        owner_kind=str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["stage_status"]["owner_kind"]),
    )
    stage = stage_rows[-1] if stage_rows else {}
    stage = merge_live_status_into_stage(stage, status_json)
    stage = infer_effective_live_stage(stage, artifacts)
    config = parse_config_json(run_row)
    truth_modes = infer_runtime_truth_modes(config, operating_mode)
    config_snapshot = build_config_snapshot_context(run_row, artifacts, config)
    raw_trial_lifecycle = build_raw_trial_lifecycle_context(artifacts)
    browser_cfg = config
    if isinstance(config.get("lls6g"), dict):
        submitted_cfg = config["lls6g"].get("submittedScenarioConfig")
        if isinstance(submitted_cfg, dict) and submitted_cfg:
            browser_cfg = submitted_cfg
    scenario_cfg = browser_cfg.get("scenario", {}) if isinstance(browser_cfg.get("scenario"), dict) else {}
    layout_cfg = browser_cfg.get("deployment_topology", {}) if isinstance(browser_cfg.get("deployment_topology"), dict) else {}
    legacy_layout_cfg = scenario_cfg.get("layout", {}) if isinstance(scenario_cfg.get("layout"), dict) else {}
    site_rows = load_small_csv_rows(artifacts, "reports/csv/sites.csv", max_rows=256)
    actual_site_spacing_m = estimate_site_spacing_m(site_rows)
    artifact_selection = {
        "live_control_gating_summary": control_summary_source,
        "live_control_gating_state": control_state_source,
        "live_stage_status": stage_source,
        "trs_trials": trs_trial_source,
        "raw_control_trials": {
            key: control_trial_sources.get(key) or select_canonical_csv_rows(
                artifacts,
                str(spec["canonical_path"]),
                legacy_paths=list(spec.get("legacy_paths") or []),
                max_rows=2,
                owner_kind=str(spec.get("owner_kind") or "raw_control_trials"),
            )[1]
            for key, spec in CANONICAL_RUNTIME_ARTIFACT_OWNERS.items()
            if str(spec.get("owner_kind") or "") == "raw_control_trials"
        },
        "scheduler_grants": {
            "dl": select_canonical_csv_rows(
                artifacts,
                str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["dl_scheduler_grants"]["canonical_path"]),
                legacy_paths=list(CANONICAL_RUNTIME_ARTIFACT_OWNERS["dl_scheduler_grants"].get("legacy_paths") or []),
                max_rows=2,
                owner_kind=str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["dl_scheduler_grants"]["owner_kind"]),
            )[1],
            "ul": select_canonical_csv_rows(
                artifacts,
                str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["ul_scheduler_grants"]["canonical_path"]),
                legacy_paths=list(CANONICAL_RUNTIME_ARTIFACT_OWNERS["ul_scheduler_grants"].get("legacy_paths") or []),
                max_rows=2,
                owner_kind=str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["ul_scheduler_grants"]["owner_kind"]),
            )[1],
            "pucch": pucch_grant_source,
        },
        "raw_link_trials": {
            "dl": select_canonical_csv_rows(
                artifacts,
                str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["dl_trials"]["canonical_path"]),
                legacy_paths=list(CANONICAL_RUNTIME_ARTIFACT_OWNERS["dl_trials"].get("legacy_paths") or []),
                max_rows=2,
                owner_kind=str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["dl_trials"]["owner_kind"]),
            )[1],
            "ul": select_canonical_csv_rows(
                artifacts,
                str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["ul_trials"]["canonical_path"]),
                legacy_paths=list(CANONICAL_RUNTIME_ARTIFACT_OWNERS["ul_trials"].get("legacy_paths") or []),
                max_rows=2,
                owner_kind=str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["ul_trials"]["owner_kind"]),
            )[1],
        },
        "summary_rollups": {
            "scenario_summary": select_canonical_csv_rows(
                artifacts,
                str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["scenario_summary"]["canonical_path"]),
                legacy_paths=list(CANONICAL_RUNTIME_ARTIFACT_OWNERS["scenario_summary"].get("legacy_paths") or []),
                max_rows=2,
                owner_kind=str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["scenario_summary"]["owner_kind"]),
            )[1],
            "runtime_operating_mode": operating_mode_source,
            "live_error_rate_summary": select_canonical_csv_rows(
                artifacts,
                str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["live_error_rate_summary"]["canonical_path"]),
                legacy_paths=list(CANONICAL_RUNTIME_ARTIFACT_OWNERS["live_error_rate_summary"].get("legacy_paths") or []),
                max_rows=2,
                owner_kind=str(CANONICAL_RUNTIME_ARTIFACT_OWNERS["live_error_rate_summary"]["owner_kind"]),
            )[1],
        },
    }
    notes: list[str] = []
    if operating_mode:
        receiver_hest_unavailable = any(
            str(row.get("ReceiverHestSINRValueStatus") or "").strip().lower() == "unavailable"
            for row in operating_mode
        )
        system_sinr_available = any(
            str(row.get("SystemLevelSINRValueStatus") or "").strip().lower() == "available_system_level_estimate"
            for row in operating_mode
        )
        if any(
            str(row.get("ConfiguredMCSSelectionPolicy") or row.get("ConfiguredMCSSelectionMode") or "").strip().lower() == "configured_fixed"
            or str(row.get("RequestedOperatingPointSource") or "").strip().lower() == "configured_fixed_mcs"
            for row in operating_mode
        ):
            notes.append(
                "This run is using a fixed transmitted MCS/modulation policy on at least one direction. "
                "If you see 16QAM at low SINR, that can be intentional fixed-policy behavior rather than CQI-driven AMC."
            )
        elif any(
            str(row.get("RequestedOperatingPointSource") or "").strip().lower() == "cqi_link_adaptation"
            or str(row.get("ConfiguredMCSSelectionPolicy") or row.get("ConfiguredMCSSelectionMode") or "").strip().lower() == "cqi_driven"
            for row in operating_mode
        ):
            if receiver_hest_unavailable and system_sinr_available:
                notes.append(
                    "This run is using CQI-driven link adaptation in the system-level adapter. Receiver Hest SINR is unavailable here; "
                    "the exported SystemLevelSINR_dB is a desired/interference/noise budget estimate and must not be read as decoder truth."
                )
            else:
                notes.append(
                    "This run is using CQI-driven link adaptation. The transmitted MCS/modulation should follow the receiver Hest/CSI wideband SINR and CQI path exported by the trial tables, not a decoder-truth SINR measurement."
                )
            notes.append(
                "Warmup rows can still show the configured starting MCS before the first CQI-driven decision is applied. "
                "Use IsWarmupFrame and LinkAdaptationApplied in the trial tables to separate pre-adaptation rows from steady-state AMC behavior."
            )
        if any(
            str(row.get("AppliedOperatingPointSource") or "").strip().lower() == "scheduler_grant"
            for row in operating_mode
        ):
            notes.append(
                "Scheduler grants are the applied operating-point authority for at least one direction in this run. "
                "Use ConfiguredMCSSelectionPolicy, SchedulerGrantMCSSelectionMode, and AppliedOperatingPointSource to separate configured intent from transmitted reality."
            )
    if deployment:
        if is_truthy_value(deployment.get("MobilityEnabled")):
            notes.append(
                "Mobility is enabled in the exported LLS layout context. Geometry/map artifacts reflect the configured deployment and mobility settings."
            )
    if stage:
        stage_name = str(stage.get("CurrentStage") or stage.get("StageName") or stage.get("Stage") or "").strip()
        stage_note = str(stage.get("Notes") or "").strip()
        if stage_name:
            notes.append(
                f"Current live stage: {stage_name}."
                + (f" {stage_note}" if stage_note else "")
            )
    requested_profile = str(browser_cfg.get("meta", {}).get("scenario_id") or scenario_cfg.get("name") or "").strip() if isinstance(browser_cfg.get("meta"), dict) else str(scenario_cfg.get("name") or "").strip()
    requested_layout_type = normalize_layout_type_token(
        layout_cfg.get("layout_type") or layout_cfg.get("site_layout") or legacy_layout_cfg.get("type") or ""
    )
    requested_isd = coerce_numeric(layout_cfg.get("inter_site_distance"))
    if requested_isd is None:
        requested_isd = coerce_numeric(legacy_layout_cfg.get("interSiteDistance_m"))
    if requested_isd is None:
        requested_isd = coerce_numeric(deployment.get("InterSiteDistance_m"))
    if actual_site_spacing_m is not None and requested_isd is not None and requested_isd > 0:
        if abs(actual_site_spacing_m - requested_isd) > max(25.0, 0.15 * requested_isd):
            notes.append(
                f"Stored live geometry currently shows nearest-site spacing around {actual_site_spacing_m:.1f} m, "
                f"while the resolved config requests {requested_isd:.1f} m. "
                f"The active resolved scenario profile is '{requested_profile or 'n/a'}' with layout type '{requested_layout_type or 'n/a'}'."
            )
    if truth_modes.get("interference_mode"):
        interference_mode = str(truth_modes["interference_mode"])
        notes.append(
            f"Interference mode: {interference_mode}. "
            + (
                "This run used a removed non-waveform interference shortcut. Current no-proxy LLS validation rejects this mode before MATLAB runtime."
                if any(token in interference_mode for token in ("abstract_large_scale", "waveform_overlap_large_scale", "explicit_activity_power_sum"))
                else "This run is using full per-link channel-waveform interferer summation: each overlapping interferer is rebuilt through its real grant-specific PHY Tx path and its own victim-link fading channel realization before sample-domain summation."
            )
        )
    if truth_modes.get("channel_array_handling_status"):
        status = str(truth_modes["channel_array_handling_status"]).strip().lower()
        if status == "count_only_spatial_dims_no_runtime_geometry":
            notes.append(
                "Active channel-array truth: the serving fading channel is still count-only. Runtime BS/UE antenna objects exist for beam and precoding context, but nrTDLChannel only consumed transmit and receive antenna counts."
            )
        elif status == "adapted_geometry_backed_reduced_representation":
            notes.append(
                "Active channel-array truth: the serving TDL channel uses a runtime-geometry-backed reduced representation. nrTDLChannel consumed custom Tx/Rx spatial correlation matrices derived from runtime element geometry, not full runtime array objects, pose, element patterns, polarization, or per-path angles."
            )
        elif status == "config_array_shape_no_runtime_object_pose":
            notes.append(
                "Active channel-array truth: the serving CDL channel uses config-resolved array shape, but it still does not consume the runtime antenna objects or their pose."
            )
        elif status == "no_fading_channel_object":
            notes.append(
                "Active channel-array truth: the run used the AWGN/no-fading shortcut, so no channel object consumed BS/UE array geometry."
            )
        else:
            notes.append(f"Active channel-array handling status: {truth_modes['channel_array_handling_status']}.")
    if truth_modes.get("channel_object_source"):
        notes.append(f"Serving channel object source: {truth_modes['channel_object_source']}.")
    if truth_modes.get("channel_array_handling_blocker"):
        notes.append(f"Serving channel-array blocker: {truth_modes['channel_array_handling_blocker']}.")
    if truth_modes.get("channel_uses_same_runtime_antenna_assumptions") is not None:
        notes.append(
            "The serving channel used the same antenna assumptions as the runtime BS/UE objects."
            if truth_modes.get("channel_uses_same_runtime_antenna_assumptions")
            else "The serving channel did not use the same antenna assumptions as the runtime BS/UE objects."
        )
    if truth_modes.get("interference_channel_array_handling_status"):
        notes.append(
            f"Interference channel-array handling status: {truth_modes['interference_channel_array_handling_status']}."
        )
    if truth_modes.get("interference_channel_object_source"):
        notes.append(f"Interference channel object source: {truth_modes['interference_channel_object_source']}.")
    if truth_modes.get("interference_channel_array_handling_blocker"):
        notes.append(f"Interference channel-array blocker: {truth_modes['interference_channel_array_handling_blocker']}.")
    if truth_modes.get("interference_path_uses_same_array_assumptions") is not None:
        notes.append(
            "Serving and interferer channel paths used the same channel-array handling level."
            if truth_modes.get("interference_path_uses_same_array_assumptions")
            else "Serving and interferer channel paths did not use the same channel-array handling level."
        )
    if truth_modes.get("interference_uses_same_runtime_antenna_assumptions") is not None:
        notes.append(
            "The interferer channel path used the same antenna assumptions as the runtime antenna objects."
            if truth_modes.get("interference_uses_same_runtime_antenna_assumptions")
            else "The interferer channel path did not use the same antenna assumptions as the runtime antenna objects."
        )
    if truth_modes.get("noise_operating_mode"):
        noise_mode = str(truth_modes["noise_operating_mode"])
        notes.append(
            f"Noise operating mode: {noise_mode}. "
            + (
                "The active waveform path derives receive noise from thermal noise plus receiver noise figure."
                if noise_mode == "receiver_noise_figure_thermal_noise"
                else "The active waveform path still derives AWGN from configured snr_db after large-scale waveform gain/loss is applied."
            )
        )
    if truth_modes.get("control_integration_mode"):
        control_mode = str(truth_modes["control_integration_mode"])
        notes.append(
            f"Control/access integration mode: {control_mode}. "
            + (
                "PBCH, PRACH, PDCCH, and SRS outcomes are now consumed by persistent slot-runtime state before data scheduling/execution."
                if "runtime_control_access_state_gated" in control_mode
                else "Control outputs are still not gating the active data path."
            )
        )
    if truth_modes.get("pucch_mode"):
        pucch_mode = str(truth_modes["pucch_mode"]).strip().lower()
        notes.append(
            f"PUCCH mode: {truth_modes['pucch_mode']}. "
            + (
                "HARQ/control feedback is being scheduled into explicit runtime PUCCH grant/resource rows before waveform execution and HARQ/scheduler state update."
                if "runtime_coupled_pucch" in pucch_mode or "waveform_harq_feedback_observation" in pucch_mode
                else "PUCCH is not running through the explicit waveform-backed coupled feedback path."
            )
        )
    if pucch_grant_rows:
        first_grant = pucch_grant_rows[0]
        notes.append(
            "Canonical PUCCH grant trace is present. "
            f"First visible row: grant id '{first_grant.get('PUCCHGrantId') or ''}', "
            f"resource '{first_grant.get('PUCCHResourceId') or ''}', "
            f"state '{first_grant.get('PUCCHGrantState') or ''}'."
        )
    if truth_modes.get("trs_mode"):
        trs_mode = str(truth_modes["trs_mode"])
        consumer = str(truth_modes.get("trs_runtime_consumer") or "").strip()
        blocker = str(truth_modes.get("trs_receiver_integration_blocker") or "").strip()
        influenced = truth_modes.get("trs_influenced_decision")
        notes.append(
            f"TRS mode: {trs_mode}. "
            + (
                "TRS state is being consumed by a shared receiver tracking object before any scheduler eligibility use."
                if consumer == "shared_receiver_tracking_state"
                else "TRS is waiting on a runtime observation before the shared receiver tracking object can update."
                if consumer == "pending_shared_receiver_tracking_state"
                else
                "TRS state is being consumed by scheduler eligibility/runtime tracking."
                if consumer == "scheduler_eligibility_gate"
                else "TRS state is currently being observed without downstream scheduler or receiver consumption."
                if consumer == "runtime_tracking_observer_only"
                else "TRS is not active in the current runtime path."
            )
        )
        if consumer:
            notes.append(f"TRS runtime consumer: {consumer}.")
        if influenced is not None:
            notes.append(
                "TRS influenced a downstream runtime decision in the active path."
                if influenced
                else "TRS did not influence a downstream runtime decision in the sampled runtime context."
            )
        if blocker:
            notes.append(f"TRS receiver integration blocker: {blocker}.")
    if truth_modes.get("doppler_source_mode"):
        notes.append(
            f"Doppler source mode: {truth_modes['doppler_source_mode']}. "
            + (
                "The runtime channel Doppler is derived from UE speed and carrier frequency for this scenario."
                if str(truth_modes["doppler_source_mode"]).strip().lower() == "derive_from_ue_speed"
                else "The runtime channel Doppler is taken directly from the configured Doppler field."
            )
        )
    if truth_modes.get("parallel_execution_active") is not None:
        notes.append(
            "Parallel grant execution: "
            + (
                f"active with {int(truth_modes.get('effective_workers') or 0)} worker(s); runtime still commits shared grant/HARQ state serially in the coordinator."
                if truth_modes.get("parallel_execution_active")
                else f"not active{': ' + str(truth_modes.get('parallel_disabled_reason')) if truth_modes.get('parallel_disabled_reason') else ''}."
            )
        )
    notes.append(
        "ReceiverHestSINR_dB is a receiver-side wideband effective SINR estimate from Hest and reference-signal residual measurement. "
        "DecoderTruthProxySINR_dB is only populated when the runtime emits a real decoder-truth proxy. "
        "SystemLevelSINR_dB is a desired/interference/noise budget estimate for coupled system-level views, and LargeScaleSINR_dB remains a large-scale preview."
    )
    if config_snapshot.get("submitted_present"):
        notes.append(
            "Config snapshots are DB-backed: the submitted scenario payload is stored in sim_runs.config_json and the resolved JSON/YAML snapshots are stored as MySQL artifacts."
        )
    if any(str(info.get("status") or "") == "exact" for info in raw_trial_lifecycle.values() if isinstance(info, dict)):
        notes.append(
            "Raw DL/UL trial row finalization is now driven by primary runtime decode/grant truth. "
            "Secondary gaps such as preview SINR or optional linkage stay in per-field status columns and SecondaryFieldGap* instead of forcing RowLifecycleState=partial."
        )
    roundtrip_summary = {
        "config_roundtrip_rows": len(config_roundtrip_rows),
        "config_roundtrip_mismatches": count_non_consistent_rows(config_roundtrip_rows),
        "browser_runtime_db_rows": len(browser_runtime_db_rows),
        "browser_runtime_db_mismatches": count_non_consistent_rows(browser_runtime_db_rows),
        "summary_vs_raw_rows": len(summary_vs_raw_rows),
        "summary_vs_raw_mismatches": count_non_consistent_rows(summary_vs_raw_rows),
        "value_source_audit_rows": len(value_source_audit_rows),
        "value_source_audit_mismatches": count_non_consistent_rows(value_source_audit_rows),
    }
    roundtrip_mismatch_rows = {
        "config_roundtrip_verification": filter_non_consistent_rows(config_roundtrip_rows),
        "browser_runtime_db_consistency": filter_non_consistent_rows(browser_runtime_db_rows),
        "summary_vs_raw_consistency": filter_non_consistent_rows(summary_vs_raw_rows),
        "value_source_audit": filter_non_consistent_rows(value_source_audit_rows),
    }
    if roundtrip_summary["config_roundtrip_rows"]:
        notes.append(
            "Roundtrip verifier artifacts are being read from canonical DB-backed CSVs and surfaced directly in the browser live payload."
        )
    if truth_contract_summary_rows:
        first_truth = truth_contract_summary_rows[0]
        notes.append(
            "Final truth-contract artifacts are being read from canonical DB-backed CSVs. "
            f"RuntimeTruthContractOk={first_truth.get('RuntimeTruthContractOk')}, "
            f"StrictTruthFailureCount={first_truth.get('StrictTruthFailureCount')}."
        )
    if truth_contract_failure_rows:
        notes.append(
            f"Truth-contract failure rows are present: {len(truth_contract_failure_rows)} required gate(s) need attention."
        )
    if roundtrip_summary["config_roundtrip_mismatches"] > 0 or roundtrip_summary["browser_runtime_db_mismatches"] > 0:
        notes.append(
            "At least one roundtrip verifier row is not marked consistent, so the browser should be treated as showing an active mismatch rather than a clean roundtrip."
        )
    legacy_fallbacks: list[str] = []
    canonical_empty: list[str] = []
    stack: list[tuple[str, Any]] = list(artifact_selection.items())
    while stack:
        label, value = stack.pop()
        if isinstance(value, dict) and "selection_status" in value:
            status = str(value.get("selection_status") or "").strip().lower()
            selected_path = str(value.get("selected_logical_path") or value.get("canonical_logical_path") or "").strip()
            if status == "legacy_fallback":
                legacy_fallbacks.append(f"{label} -> {selected_path}")
            elif status == "canonical_empty":
                canonical_empty.append(f"{label} -> {selected_path}")
        elif isinstance(value, dict):
            for child_key, child_value in value.items():
                stack.append((f"{label}.{child_key}", child_value))
    if legacy_fallbacks:
        notes.append(
            "Legacy artifact fallback is active only because the canonical artifact is absent for: "
            + ", ".join(sorted(legacy_fallbacks))
            + ". The browser is labeling these selections explicitly as legacy fallback."
        )
    if canonical_empty:
        notes.append(
            "Canonical artifacts exist but are empty for: "
            + ", ".join(sorted(canonical_empty))
            + ". The browser is not silently replacing these with legacy mirrors."
        )
    return {
        "operating_mode": operating_mode,
        "roundtrip_artifacts": {
            "config_roundtrip_verification": config_roundtrip_rows,
            "browser_runtime_db_consistency": browser_runtime_db_rows,
            "summary_vs_raw_consistency": summary_vs_raw_rows,
            "value_source_audit": value_source_audit_rows,
            "mismatch_rows": roundtrip_mismatch_rows,
            "summary": roundtrip_summary,
        },
        "truth_contract": {
            "summary": truth_contract_summary_rows[0] if truth_contract_summary_rows else {},
            "summary_rows": truth_contract_summary_rows,
            "failure_rows": truth_contract_failure_rows,
            "failure_count": len(truth_contract_failure_rows),
            "downloads": {
                "summary": build_artifact_descriptor(find_artifact_by_logical_path(artifacts, "reports/csv/truth_contract_summary.csv"))
                if find_artifact_by_logical_path(artifacts, "reports/csv/truth_contract_summary.csv") else None,
                "failures": build_artifact_descriptor(find_artifact_by_logical_path(artifacts, "reports/csv/truth_contract_failures.csv"))
                if find_artifact_by_logical_path(artifacts, "reports/csv/truth_contract_failures.csv") else None,
            },
        },
        "deployment": deployment,
        "stage": stage,
        "scenario_profile": requested_profile,
        "layout_type": requested_layout_type,
        "requested_isd_m": requested_isd,
        "actual_site_spacing_m": actual_site_spacing_m,
        "truth_modes": truth_modes,
        "raw_trial_lifecycle": raw_trial_lifecycle,
        "control_summary": control_summary_rows[0] if control_summary_rows else {},
        "control_state_preview": control_state_rows,
        "control_trial_previews": control_trial_previews,
        "pucch_grants": pucch_grant_rows,
        "trs_trials_preview": trs_trial_rows,
        "antenna_runtime_evidence_preview": antenna_runtime_rows,
        "channel_array_consistency_preview": channel_array_rows,
        "artifact_selection": artifact_selection,
        "config_snapshot": config_snapshot,
        "notes": notes,
    }


def infer_effective_live_stage(stage: dict[str, Any], artifacts: list[dict[str, Any]]) -> dict[str, Any]:
    stage = dict(stage or {})

    def artifact_bytes(path: str) -> int:
        art = find_artifact_by_logical_path(artifacts, path)
        if not art:
            return 0
        try:
            return int(art.get("byte_size") or 0)
        except Exception:
            return 0

    def csv_has_rows(path: str) -> bool:
        art = find_artifact_by_logical_path(artifacts, path)
        if not art:
            return False
        size = artifact_bytes(path)
        if size > 2303:
            return True
        if size <= 0:
            return False
        try:
            _, rows = load_cached_csv_preview(int(art["artifact_id"]), 2)
            return bool(rows)
        except Exception:
            return size > 2303

    control_paths = [
        "air_interface/csv/pbch_trials.csv",
        "air_interface/csv/prach_trials.csv",
        "air_interface/csv/pdcch_trials.csv",
        "air_interface/csv/pucch_trials.csv",
        "air_interface/csv/srs_trials.csv",
        "air_interface/csv/trs_trials.csv",
    ]
    harq_paths = [
        "harq/csv/live_harq_observation_summary.csv",
        "harq/csv/live_harq_observation_timeline.csv",
        "harq/csv/probe_harq_summary.csv",
        "harq/csv/harq_process_timeline.csv",
        "harq/csv/probe_harq_packets.csv",
    ]
    beam_paths = [
        "reports/csv/live_beam_selection_stats.csv",
        "beamforming/csv/probe_beam_mimo.csv",
        "beamforming/csv/probe_beam_management.csv",
    ]
    rf_paths = [
        "reports/csv/live_rsrp_serving_trace.csv",
        "reports/csv/live_cell_measurement_trace.csv",
        "reports/csv/live_coverage_layer.csv",
        "rf/csv/probe_rf_energy.csv",
        "rf/csv/energy_timeline_trace.csv",
        "rf/csv/probe_rf_iq_imbalance.csv",
        "rf/csv/iq_imbalance_timeline_trace.csv",
    ]
    has_control = any(csv_has_rows(path) for path in control_paths)
    has_dl = csv_has_rows("air_interface/csv/dl_pdsch_trials.csv")
    has_ul = csv_has_rows("air_interface/csv/ul_pusch_trials.csv")
    has_harq = any(csv_has_rows(path) for path in harq_paths)
    has_beam = any(csv_has_rows(path) for path in beam_paths)
    has_rf = any(csv_has_rows(path) for path in rf_paths)

    current_stage = str(stage.get("CurrentStage") or stage.get("StageName") or stage.get("Stage") or "").strip().lower()
    early_stage_names = {
        "",
        "link_anchor_complete",
        "pre_raw_sweep",
        "control_trials_ready",
        "raw_trials_streaming",
        "dl_raw_trials_streaming",
        "ul_raw_trials_streaming",
        "dl_ul_raw_trials_streaming",
    }
    harq_stage_names = {"harq_ready", "beam_ready", "rf_ready", "final_bundle_ready", "bundle_complete"}
    beam_stage_names = {"beam_ready", "rf_ready", "final_bundle_ready", "bundle_complete"}
    if current_stage in early_stage_names and has_ul:
        stage["Stage"] = "ul_raw_trials_streaming"
        stage["Notes"] = "UL PUSCH raw trial rows are streaming live from the database."
    elif current_stage in early_stage_names and has_dl:
        stage["Stage"] = "dl_raw_trials_streaming"
        stage["Notes"] = "DL PDSCH raw trial rows are streaming live from the database."
    elif current_stage in early_stage_names and has_control:
        stage["Stage"] = "control_trials_ready"
        stage["Notes"] = "Control-plane raw trial rows are available live in the database."
    stage["ControlReady"] = 1 if has_control else 0
    stage["DLTrialsReady"] = 1 if has_dl else 0
    stage["ULTrialsReady"] = 1 if has_ul else 0
    stage["HARQReady"] = 1 if has_harq else 0
    stage["BeamReady"] = 1 if has_beam else 0
    stage["RFReady"] = 1 if has_rf else 0
    return stage


def merge_live_status_into_stage(stage: dict[str, Any], status_json: dict[str, Any] | None) -> dict[str, Any]:
    merged = dict(stage or {})
    if not isinstance(status_json, dict) or not status_json:
        return merged
    field_map = {
        "stage": ("Stage", "CurrentStage"),
        "current_slot": ("CurrentSlot",),
        "total_slots": ("TotalSlots",),
        "current_ue_index": ("CurrentUEIndex",),
        "total_users": ("TotalUsers",),
        "run_completion": ("RunCompletion",),
        "elapsed_s": ("ElapsedSeconds",),
        "sim_time_ms": ("SimTime_ms",),
        "slot_duration_ms": ("SlotDuration_ms",),
        "slot_direction": ("CurrentDirection",),
        "current_direction": ("CurrentDirection",),
        "active_ue_count": ("ActiveUECount",),
        "cell_count": ("CellCount",),
        "grant_count_slot": ("GrantCountSlot",),
        "served_bits_total": ("ServedBitsTotal",),
        "dropped_bits_total": ("DroppedBitsTotal",),
        "overflow_event_count": ("OverflowEventCount",),
        "control_phase": ("ControlPhase",),
        "pbch_attempt_count": ("PBCHAttemptCount",),
        "prach_attempt_count": ("PRACHAttemptCount",),
        "srs_attempt_count": ("SRSAttemptCount",),
        "trs_attempt_count": ("TRSAttemptCount",),
        "notes": ("Notes",),
        "timestamp_utc": ("LastStatusTimestampUTC",),
        "value_role": ("ValueRole",),
        "value_source": ("ValueSource",),
        "value_status": ("ValueStatus",),
    }
    for source_key, target_keys in field_map.items():
        value = status_json.get(source_key)
        if value in {None, ""}:
            continue
        for target_key in target_keys:
            merged[target_key] = value
    if status_json.get("run_completion") not in {None, ""} and status_json.get("total_slots") not in {None, ""}:
        try:
            merged["CompletionPct"] = round(float(status_json["run_completion"]) * 100.0, 4)
        except Exception:
            pass
    merged.setdefault("StatusSource", "sim_runs.status_json")
    return merged


def extract_metric_cards(run_row: dict[str, Any], artifacts: list[dict[str, Any]], runtime_context: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    summary_row = load_scenario_summary_row(artifacts)
    max_metric_cards = 24
    metrics = [
        {"label": "Run ID", "value": str(run_row["run_id"]), "source": "sim_runs"},
        {"label": "Status", "value": str(run_row.get("status_text") or ""), "source": "sim_runs"},
    ]
    seen = {m["label"] for m in metrics}
    status_cards = [
        ("Run Completion", summary_row.get("RunCompletion")),
        ("Result OK", summary_row.get("ResultOk")),
        ("Required Failures", summary_row.get("RequiredFailureCount")),
        ("Status Authority", summary_row.get("StatusAuthority")),
        ("Runtime Truth Contract OK", summary_row.get("RuntimeTruthContractOk")),
        ("Roundtrip Mismatches", summary_row.get("RoundtripMismatchCount")),
        ("Runtime Evidence Missing", summary_row.get("RequiredRuntimeEvidenceMissingCount")),
        ("Strict Truth Failures", summary_row.get("StrictTruthFailureCount")),
        ("Failing Cases", summary_row.get("FailingCaseCount")),
        ("Warnings", summary_row.get("WarningCount")),
    ]
    for label, value in status_cards:
        if value in {None, ""} or label in seen:
            continue
        metrics.append({"label": label, "value": str(value), "source": "reports/csv/scenario_summary.csv"})
        seen.add(label)
    runtime_context = runtime_context or {}
    deployment = runtime_context.get("deployment") if isinstance(runtime_context, dict) else {}
    operating_mode = runtime_context.get("operating_mode") if isinstance(runtime_context, dict) else []
    truth_modes = runtime_context.get("truth_modes") if isinstance(runtime_context, dict) else {}
    if isinstance(truth_modes, dict):
        priority_truth_cards = [
            ("Execution Backend", truth_modes.get("execution_backend")),
            ("PHY Mode", truth_modes.get("phy_mode")),
            ("Waveform PHY Active", truth_modes.get("waveform_phy_active")),
            ("Proxy PHY Active", truth_modes.get("proxy_phy_active")),
            ("Fallback Used", truth_modes.get("fallback_used")),
        ]
        for label, value in priority_truth_cards:
            if value in {None, ""} or label in seen:
                continue
            metrics.append({"label": label, "value": str(value), "source": "runtime_context"})
            seen.add(label)
    if isinstance(deployment, dict) and deployment:
        deployment_cards = [
            ("Sites", deployment.get("NumSites")),
            ("Cells", deployment.get("NumCells")),
            ("UEs", deployment.get("NumUEs")),
            ("ISD m", deployment.get("InterSiteDistance_m")),
            ("Configured Users", deployment.get("ConfiguredUsers")),
            ("Mobility", "On" if is_truthy_value(deployment.get("MobilityEnabled")) else "Off"),
        ]
        for label, value in deployment_cards:
            if value in {None, ""} or label in seen:
                continue
            metrics.append({"label": label, "value": str(value), "source": "deployment_layout_reference.csv"})
            seen.add(label)
    if isinstance(operating_mode, list):
        for row in operating_mode[:2]:
            direction = str(row.get("Direction") or "").strip().upper() or "LLS"
            amc_policy = (
                row.get("ConfiguredMCSSelectionPolicy")
                or row.get("ConfiguredMCSSelectionMode")
                or row.get("ConfiguredLinkAdaptationMode")
                or row.get("LinkAdaptationMode")
            )
            cards = [
                (f"{direction} AMC Policy", amc_policy),
                (f"{direction} Requested Operating Point", row.get("RequestedOperatingPointSource")),
                (f"{direction} Applied AMC Mode", row.get("ActualMCSSelectionMode")),
                (f"{direction} Applied Operating Point", row.get("AppliedOperatingPointSource")),
                (f"{direction} Scheduler AMC Mode", row.get("SchedulerGrantMCSSelectionMode")),
                (f"{direction} CQI Table", row.get("CQITable")),
                (f"{direction} MCS Table", row.get("MCSTable")),
            ]
            for label, value in cards:
                if value in {None, ""} or label in seen:
                    continue
                metrics.append({"label": label, "value": str(value), "source": "runtime_operating_mode.csv"})
                seen.add(label)
    if isinstance(truth_modes, dict):
        truth_cards = [
            ("Browser Mode", truth_modes.get("browser_execution_mode_label") or truth_modes.get("browser_execution_mode")),
            ("Execution Backend", truth_modes.get("execution_backend")),
            ("PHY Mode", truth_modes.get("phy_mode")),
            ("Waveform PHY Active", truth_modes.get("waveform_phy_active")),
            ("Proxy PHY Active", truth_modes.get("proxy_phy_active")),
            ("Fallback Used", truth_modes.get("fallback_used")),
            ("Interference Mode", truth_modes.get("interference_mode")),
            ("Noise Mode", truth_modes.get("noise_operating_mode")),
            ("Doppler Source", truth_modes.get("doppler_source_mode")),
            ("Control Mode", truth_modes.get("control_integration_mode")),
            ("PUCCH Mode", truth_modes.get("pucch_mode")),
            ("TRS Mode", truth_modes.get("trs_mode")),
            ("Traffic Flow Source", truth_modes.get("traffic_flow_source")),
            ("Traffic Flow Mode", truth_modes.get("traffic_flow_derivation_mode")),
            ("Traffic Flow Resolved", truth_modes.get("traffic_flow_resolved_flag")),
            ("Workers", truth_modes.get("effective_workers")),
            ("Parallel Reason", truth_modes.get("parallel_disabled_reason")),
        ]
        for label, value in truth_cards:
            if value in {None, ""} or label in seen:
                continue
            metrics.append({"label": label, "value": str(value), "source": "runtime_context"})
            seen.add(label)
    summary_candidates = [
        art
        for art in artifacts
        if art["byte_size"] <= 250_000
        and (
            art["logical_path"].lower().endswith("summary.csv")
            or art["logical_path"].lower().endswith("runtime_summary.json")
            or art["logical_path"].lower().endswith("scenario_summary.csv")
        )
    ]
    for art in summary_candidates[:6]:
        path = art["logical_path"].lower()
        if path.endswith(".json"):
            raw = fetch_artifact_bytes(int(art["artifact_id"]))
            try:
                obj = json.loads(raw.decode("utf-8", errors="replace"))
            except json.JSONDecodeError:
                continue
            numeric = flatten_numeric_values(obj)
            for key, value in sorted(numeric.items(), key=lambda kv: metric_priority(kv[0]))[:8]:
                label = humanize_key(key.split(".")[-1])
                if label in seen:
                    continue
                metrics.append({"label": label, "value": f"{value:.4g}", "source": art["logical_path"]})
                seen.add(label)
        elif path.endswith(".csv"):
            header, rows = load_cached_csv_preview(int(art["artifact_id"]), 2)
            if not header or not rows:
                continue
            first_row = rows[0]
            for idx in candidate_metric_columns(header):
                if idx >= len(first_row):
                    continue
                numeric = coerce_numeric(first_row[idx])
                if numeric is None:
                    continue
                label = humanize_key(header[idx])
                if label in seen:
                    continue
                metrics.append({"label": label, "value": f"{numeric:.4g}", "source": art["logical_path"]})
                seen.add(label)
                if len(metrics) >= max_metric_cards:
                    break
        if len(metrics) >= max_metric_cards:
            break
    return metrics[:max_metric_cards]


def build_activity_series(items: list[dict[str, Any]], label: str) -> dict[str, Any]:
    points = []
    count = 0
    for item in items[-MAX_ACTIVITY_POINTS:]:
        created = item.get("created_utc") or item.get("updated_utc") or ""
        count += 1
        points.append({"x": created, "y": count})
    return {"title": label, "series": [{"name": label, "points": points}]}


def build_runtime_progress_charts(log_rows: list[dict[str, Any]], status_json: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    progress_pattern = re.compile(
        r"slot=(?P<slot>\d+)/(?P<total>\d+).*?"
        r"completion=(?P<completion>[0-9.]+).*?"
        r"elapsed_s=(?P<elapsed>[0-9.]+).*?"
        r"grants=(?P<grants>\d+).*?"
        r"served_bits=(?P<served>\d+).*?"
        r"dropped_bits=(?P<dropped>\d+).*?"
        r"overflow_events=(?P<overflow>\d+)",
        re.IGNORECASE,
    )
    by_slot: dict[int, dict[str, float]] = {}
    for row in log_rows:
        message = str(row.get("message_text") or "")
        match = progress_pattern.search(message)
        if not match:
            continue
        try:
            slot = int(match.group("slot"))
        except Exception:
            continue
        by_slot[slot] = {
            "slot": float(slot),
            "completion_pct": float(match.group("completion")) * 100.0,
            "elapsed_s": float(match.group("elapsed")),
            "grant_count": float(match.group("grants")),
            "served_bits_total": float(match.group("served")),
            "dropped_bits_total": float(match.group("dropped")),
            "overflow_events": float(match.group("overflow")),
        }
    if isinstance(status_json, dict) and status_json:
        slot = coerce_numeric(status_json.get("current_slot"))
        if slot is not None:
            slot_int = int(slot)
            by_slot[slot_int] = {
                "slot": float(slot_int),
                "completion_pct": float(coerce_numeric(status_json.get("run_completion")) or 0.0) * 100.0,
                "elapsed_s": float(coerce_numeric(status_json.get("elapsed_s")) or 0.0),
                "grant_count": float(coerce_numeric(status_json.get("grant_count_slot")) or 0.0),
                "served_bits_total": float(coerce_numeric(status_json.get("served_bits_total")) or 0.0),
                "dropped_bits_total": float(coerce_numeric(status_json.get("dropped_bits_total")) or 0.0),
                "overflow_events": float(coerce_numeric(status_json.get("overflow_event_count")) or 0.0),
            }
    progress_rows = [by_slot[key] for key in sorted(by_slot)]
    if not progress_rows:
        return []
    def series(name: str, field: str) -> list[dict[str, Any]]:
        return [{"x": row["slot"], "y": row[field]} for row in progress_rows if row.get(field) is not None]
    charts: list[dict[str, Any]] = []
    completion_points = series("Completion (%)", "completion_pct")
    if completion_points:
        charts.append(
            {
                "title": "Live Slot Completion",
                "chart_id": "live_slot_completion",
                "xaxis_title": "Slot",
                "yaxis_title": "Completion (%)",
                "series": [{"name": "Completion (%)", "points": completion_points}],
            }
        )
    served_points = series("Served Bits Total", "served_bits_total")
    if served_points:
        charts.append(
            {
                "title": "Live Served Bits",
                "chart_id": "live_served_bits_total",
                "xaxis_title": "Slot",
                "yaxis_title": "Bits",
                "series": [{"name": "Served Bits Total", "points": served_points}],
            }
        )
    grant_points = series("Grant Count", "grant_count")
    if grant_points:
        charts.append(
            {
                "title": "Live Grant Count",
                "chart_id": "live_grant_count",
                "xaxis_title": "Slot",
                "yaxis_title": "Grant Count",
                "series": [{"name": "Grant Count", "points": grant_points}],
            }
        )
    return charts


MAP_METRIC_SPECS: list[dict[str, str]] = [
    {"key": "CellThroughput_Mbps", "label": "Cell Throughput", "kind": "numeric"},
    {"key": "RSRP_dBm", "label": "RSRP", "kind": "numeric"},
    {"key": "ReceiverHestWidebandSINR_dB", "label": "Receiver Hest SINR", "kind": "numeric"},
    {"key": "DecoderTruthProxyWidebandSINR_dB", "label": "Decoder Truth Proxy SINR", "kind": "numeric"},
    {"key": "SystemLevelWidebandSINR_dB", "label": "System-Level SINR Estimate", "kind": "numeric"},
    {"key": "CQIDerivedModulation", "label": "Modulation", "kind": "categorical"},
    {"key": "CoverageScore", "label": "Coverage", "kind": "numeric"},
    {"key": "HARQFailureRate", "label": "HARQ Failure", "kind": "numeric"},
    {"key": "Pathloss_dB", "label": "Pathloss", "kind": "numeric"},
    {"key": "UserThroughput_Mbps", "label": "User Throughput", "kind": "numeric"},
    {"key": "WidebandCQI", "label": "CQI", "kind": "numeric"},
]


def parse_status_json(run_row: dict[str, Any]) -> dict[str, Any]:
    raw = run_row.get("status_json")
    if isinstance(raw, dict):
        return raw
    if not raw:
        return {}
    text = str(raw)
    candidates = [text]
    stripped = text.lstrip()
    if stripped.startswith(("{\\n", "[\\n", "{\\r\\n", "[\\r\\n")):
        candidates.append(text.replace("\\r\\n", "\n").replace("\\n", "\n").replace("\\t", "\t"))
    for candidate in candidates:
        try:
            decoded = json.loads(candidate)
        except Exception:
            continue
        if isinstance(decoded, dict):
            return decoded
    return {}


def parse_config_json(run_row: dict[str, Any]) -> dict[str, Any]:
    raw = run_row.get("config_json")
    if isinstance(raw, dict):
        return raw
    if not raw:
        return {}
    text = str(raw)
    candidates = [text]
    stripped = text.lstrip()
    if stripped.startswith(("{\\n", "[\\n", "{\\r\\n", "[\\r\\n")):
        candidates.append(text.replace("\\r\\n", "\n").replace("\\n", "\n").replace("\\t", "\t"))
    for candidate in candidates:
        try:
            decoded = json.loads(candidate)
        except Exception:
            try:
                decoded = yaml.safe_load(candidate)
            except Exception:
                continue
        if isinstance(decoded, str):
            try:
                decoded = json.loads(decoded)
            except Exception:
                try:
                    decoded = yaml.safe_load(decoded)
                except Exception:
                    continue
        if isinstance(decoded, dict):
            return decoded
    return {}


def is_direct_debug_artifact_path(path: str) -> bool:
    token = path.lower()
    generic_fragments = [
        "scenario_summary.csv",
        "runtime_summary.json",
        "environment.json",
        "scenario_manifest.json",
        "artifact_inventory.csv",
        "run_metadata_outputs.csv",
        "lls_output_",
        "per_scenario_summary_tables.csv",
        "per_sweep_comparison_tables.csv",
        "baseline_candidate_delta_tables.csv",
        "_outputs.csv",
        "basic_phy_performance_outputs.csv",
        "coding_decoder_outputs.csv",
        "modulation_shaping_outputs.csv",
        "channel_estimation_tracking_outputs.csv",
        "beam_management_outputs.csv",
        "initial_access_random_access_outputs.csv",
    ]
    return not any(fragment in token for fragment in generic_fragments)


def infer_relevant_chain_ids(run_row: dict[str, Any], artifacts: list[dict[str, Any]]) -> list[str]:
    catalog = load_processing_chain_catalog()
    if not catalog:
        return []
    cfg = parse_config_json(run_row)
    runner_cfg = cfg.get("lls6g", {}).get("resolvedConfig", {}).get("scenario", {}) if isinstance(cfg.get("lls6g"), dict) else {}
    configured_profile = ""
    if isinstance(runner_cfg, dict):
        configured_profile = str(runner_cfg.get("runner_profile") or "")
    profile = str(configured_profile or run_row.get("profile_name") or "").lower()
    scenario_id = str(run_row.get("scenario_id") or "").lower()
    artifact_text = " ".join(
        str(art.get("logical_path") or "") for art in artifacts if is_direct_debug_artifact_path(str(art.get("logical_path") or ""))
    ).lower()
    combined = " ".join([profile, scenario_id, artifact_text])
    chain_ids: list[str] = []

    def add_many(ids: list[str]) -> None:
        for chain_id in ids:
            if chain_id in catalog and chain_id not in chain_ids:
                chain_ids.append(chain_id)

    if "prach" in scenario_id or profile == "prach_detection":
        add_many(["prach_tx", "prach_rx"])
        return chain_ids
    if "pdcch" in scenario_id or profile in {"pdcch_blind_decode_sweep", "ctrl6gr_pdcch_study"}:
        add_many(["pdcch_tx", "pdcch_rx"])
        return chain_ids
    if profile == "waveform_bundle":
        add_many(
            [
                "dl_common_signal_initial_access_tx",
                "dl_common_signal_initial_access_rx",
                "pdcch_tx",
                "pdcch_rx",
                "pdsch_tx",
                "pdsch_rx",
                "pusch_tx",
                "pusch_rx",
                "reference_signal_chains",
                "csi_acquisition_reporting",
                "harq_chain",
            ]
        )
    if "prach" in combined:
        add_many(["prach_tx", "prach_rx"])
    if "pdcch" in combined or "control" in artifact_text:
        add_many(["pdcch_tx", "pdcch_rx"])
    if "pdsch" in combined:
        add_many(["pdsch_tx", "pdsch_rx"])
    if "pusch" in combined:
        add_many(["pusch_tx", "pusch_rx"])
    if "pucch" in combined:
        add_many(["pucch_tx_rx"])
    if any(token in combined for token in ["csi", "cqi", "pmi", "ri", "cri", "srs", "trs", "nmse"]):
        add_many(["reference_signal_chains", "csi_acquisition_reporting"])
    if "harq" in combined:
        add_many(["harq_chain"])
    if any(token in combined for token in ["ai_ml", "ai-inference", "ml-inference", "ai_scheduler", "ml_scheduler"]):
        add_many(["ai_ml_chain"])
    if not chain_ids:
        add_many(["pdsch_tx", "pdsch_rx", "pusch_tx", "pusch_rx"])
    return chain_ids


def chain_evidence_tokens(chain_id: str) -> list[str]:
    mapping = {
        "dl_common_signal_initial_access_tx": ["ssb", "pbch", "sib", "initial_access", "cell_search"],
        "dl_common_signal_initial_access_rx": ["ssb", "pbch", "sib", "initial_access", "cell_search"],
        "prach_tx": ["prach", "msg1", "random_access"],
        "prach_rx": ["prach", "msg1", "random_access"],
        "pdcch_tx": ["pdcch", "dci", "control"],
        "pdcch_rx": ["pdcch", "dci", "control"],
        "pdsch_tx": ["pdsch", "throughput", "bler", "goodput"],
        "pdsch_rx": ["pdsch", "throughput", "bler", "goodput"],
        "pusch_tx": ["pusch", "uplink", "ul_"],
        "pusch_rx": ["pusch", "uplink", "ul_"],
        "pucch_tx_rx": ["pucch", "harq_ack", "sr", "csi"],
        "reference_signal_chains": ["nmse", "srs", "trs", "tracking", "csi_rs", "reference"],
        "csi_acquisition_reporting": ["csi", "cqi", "pmi", "ri", "cri"],
        "harq_chain": ["harq", "retransmission", "retx"],
        "ai_ml_chain": ["ai_ml", "ai-inference", "ml-inference", "ai_scheduler", "ml_scheduler"],
    }
    return mapping.get(chain_id, [chain_id])


def build_debug_payload(run_row: dict[str, Any], artifacts: list[dict[str, Any]], logs_recent: list[dict[str, Any]]) -> dict[str, Any]:
    catalog = load_processing_chain_catalog()
    status_json = parse_status_json(run_row)
    summary_row = load_scenario_summary_row(artifacts)
    log_text = " ".join(str(row.get("message_text") or "") for row in logs_recent).lower()
    artifact_text = " ".join(
        str(art.get("logical_path") or "") for art in artifacts if is_direct_debug_artifact_path(str(art.get("logical_path") or ""))
    ).lower()
    chain_rows: list[dict[str, Any]] = []

    for chain_id in infer_relevant_chain_ids(run_row, artifacts):
        chain = catalog.get(chain_id, {})
        ordered_blocks = chain.get("ordered_blocks") or []
        tokens = chain_evidence_tokens(chain_id)
        artifact_hits = sorted({token for token in tokens if token in artifact_text})
        log_hits = sorted({token for token in tokens if token in log_text})
        if artifact_hits:
            evidence_state = "observed"
            evidence_type = "artifacts"
            evidence_note = f"Observed from artifact paths matching: {', '.join(artifact_hits[:4])}"
        elif log_hits:
            evidence_state = "observed"
            evidence_type = "logs"
            evidence_note = f"Observed from live logs matching: {', '.join(log_hits[:4])}"
        else:
            evidence_state = "missing"
            evidence_type = "missing"
            evidence_note = "No artifact or live-log evidence yet for this configured chain."
        mandatory_blocks = sum(0 if bool(block.get("optional_flag")) else 1 for block in ordered_blocks)
        optional_blocks = sum(1 if bool(block.get("optional_flag")) else 0 for block in ordered_blocks)
        chain_rows.append(
            {
                "chain_id": chain_id,
                "chain_label": str(chain.get("chain_label") or chain_id),
                "blocks_total": len(ordered_blocks),
                "mandatory_blocks": mandatory_blocks,
                "optional_blocks": optional_blocks,
                "evidence_state": evidence_state,
                "evidence_type": evidence_type,
                "evidence_note": evidence_note,
                "exact_order_locked": bool(chain.get("exact_order_locked")),
                "block_instrumentation": "chain_level_inference",
            }
        )

    highlights = []
    for row in logs_recent[-40:]:
        message = str(row.get("message_text") or "")
        level = str(row.get("level_str") or "")
        token = f"{level} {message}".lower()
        if level.upper() in {"ERROR", "WARN", "FAIL"} or any(key in token for key in ["fail", "error", "denied", "missing", "mismatch"]):
            highlights.append(
                {
                    "time": str(row.get("time_str") or row.get("created_utc") or ""),
                    "level": level or "INFO",
                    "message": message,
                }
            )

    return {
        "status": str(run_row.get("status_text") or ""),
        "status_json": status_json,
        "failure_message": str(summary_row.get("ErrorMessage") or status_json.get("error_message") or status_json.get("message") or ""),
        "failure_identifier": str(summary_row.get("ErrorIdentifier") or status_json.get("error_identifier") or status_json.get("identifier") or ""),
        "required_failure_count": summary_row.get("RequiredFailureCount") if summary_row.get("RequiredFailureCount") not in {None, ""} else status_json.get("required_failure_count"),
        "run_completion": str(summary_row.get("RunCompletion") or status_json.get("run_completion") or ""),
        "result_ok": summary_row.get("ResultOk"),
        "failing_case_count": summary_row.get("FailingCaseCount"),
        "warning_count": summary_row.get("WarningCount"),
        "status_authority": str(summary_row.get("StatusAuthority") or status_json.get("status_authority") or summary_row.get("AuthoritativeStatusSource") or ""),
        "runtime_truth_contract_ok": summary_row.get("RuntimeTruthContractOk") if summary_row.get("RuntimeTruthContractOk") not in {None, ""} else status_json.get("runtime_truth_contract_ok"),
        "roundtrip_mismatch_count": summary_row.get("RoundtripMismatchCount") if summary_row.get("RoundtripMismatchCount") not in {None, ""} else status_json.get("roundtrip_mismatch_count"),
        "required_runtime_evidence_missing_count": summary_row.get("RequiredRuntimeEvidenceMissingCount") if summary_row.get("RequiredRuntimeEvidenceMissingCount") not in {None, ""} else status_json.get("required_runtime_evidence_missing_count"),
        "strict_truth_failure_count": summary_row.get("StrictTruthFailureCount") if summary_row.get("StrictTruthFailureCount") not in {None, ""} else status_json.get("strict_truth_failure_count"),
        "chain_rows": chain_rows,
        "log_highlights": highlights[-20:],
        "note": (
            "Debug coverage is inferred at chain level from MySQL artifacts and live logs. "
            "A missing row means missing evidence for that chain, not a proven inner-block skip."
        ),
    }


def build_numeric_chart_from_artifact(artifact: dict[str, Any]) -> dict[str, Any] | None:
    header, rows = load_cached_csv_preview(int(artifact["artifact_id"]), MAX_ACTIVITY_POINTS)
    if len(rows) < 2 or not header:
        return None
    lowered = [str(name).strip().lower() for name in header]
    if "series_name" in lowered and len(rows) >= MAX_ACTIVITY_POINTS:
        expanded_header, expanded_rows = load_cached_csv_preview(int(artifact["artifact_id"]), 12000)
        if expanded_header:
            header, rows = expanded_header, expanded_rows
            lowered = [str(name).strip().lower() for name in header]
    if "equalizedreal" in lowered and "equalizedimag" in lowered:
        real_idx = lowered.index("equalizedreal")
        imag_idx = lowered.index("equalizedimag")
        decision_real_idx = lowered.index("harddecisionreal") if "harddecisionreal" in lowered else None
        decision_imag_idx = lowered.index("harddecisionimag") if "harddecisionimag" in lowered else None
        traces: list[dict[str, Any]] = []
        equalized_points = []
        for row in rows:
            real_val = coerce_numeric(row[real_idx]) if real_idx < len(row) else None
            imag_val = coerce_numeric(row[imag_idx]) if imag_idx < len(row) else None
            if real_val is None or imag_val is None:
                continue
            equalized_points.append({"x": real_val, "y": imag_val})
        if equalized_points:
            traces.append({"name": "Equalized Symbols", "mode": "markers", "points": equalized_points})
        if decision_real_idx is not None and decision_imag_idx is not None:
            decision_points = []
            for row in rows:
                real_val = coerce_numeric(row[decision_real_idx]) if decision_real_idx < len(row) else None
                imag_val = coerce_numeric(row[decision_imag_idx]) if decision_imag_idx < len(row) else None
                if real_val is None or imag_val is None:
                    continue
                decision_points.append({"x": real_val, "y": imag_val})
            if decision_points:
                traces.append({"name": "Hard Decisions", "mode": "markers", "points": decision_points})
        if traces:
            return {
                "title": artifact["logical_path"],
                "artifact_id": int(artifact["artifact_id"]),
                "download_url": artifact_url(int(artifact["artifact_id"]), download=True),
                "xaxis_title": "In-phase",
                "yaxis_title": "Quadrature",
                "series": traces,
            }
    numeric_cols = []
    for idx, name in enumerate(header):
        values = [coerce_numeric(row[idx]) for row in rows if idx < len(row)]
        values = [v for v in values if v is not None]
        if len(values) >= max(2, len(rows) // 4):
            numeric_cols.append((idx, name))
    ignored_x_tokens = {"run_id", "source_row_count", "point_index"}
    numeric_cols = [(idx, name) for idx, name in numeric_cols if str(name or "").strip().lower() not in ignored_x_tokens] or numeric_cols
    if not numeric_cols:
        return None
    x_idx = _preferred_chart_x_index(artifact, header, rows, numeric_cols)
    series_name_idx = lowered.index("series_name") if "series_name" in lowered else None
    metric_value_idx = None
    for candidate in ("metric_value", "metric_value_db", "throughput_mbps", "bler", "ber", "goodput_mbps", "mean_quality_db", "mean_bler"):
        if candidate in lowered:
            metric_value_idx = lowered.index(candidate)
            break
    if series_name_idx is not None and metric_value_idx is not None and x_idx is not None:
        grouped_series: dict[str, list[dict[str, Any]]] = {}
        for row_index, row in enumerate(rows):
            if series_name_idx >= len(row) or metric_value_idx >= len(row):
                continue
            series_name = str(row[series_name_idx] or "").strip() or "Series"
            x_candidate = row[x_idx] if x_idx < len(row) else row_index + 1
            x_val = coerce_numeric(x_candidate)
            y_val = coerce_numeric(row[metric_value_idx])
            if x_val is None or y_val is None:
                continue
            grouped_series.setdefault(series_name, []).append({"x": x_val, "y": y_val})
        chart_series = []
        for series_name, points in grouped_series.items():
            if len(points) >= 8:
                unique_x = len({point["x"] for point in points})
                duplicate_ratio = 1.0 - (unique_x / max(len(points), 1))
                if duplicate_ratio >= 0.25:
                    points = aggregate_points_by_x(points)
            chart_series.append({"name": humanize_key(series_name), "points": points})
        if chart_series:
            yaxis_name = humanize_key(header[metric_value_idx]) if metric_value_idx < len(header) else "Value"
            return {
                "title": artifact["logical_path"],
                "artifact_id": int(artifact["artifact_id"]),
                "download_url": artifact_url(int(artifact["artifact_id"]), download=True),
                "xaxis_title": humanize_key(header[x_idx]) if x_idx is not None and x_idx < len(header) else "Index",
                "yaxis_title": yaxis_name,
                "series": chart_series[:6],
            }
    y_columns = [item for item in numeric_cols if item[0] != x_idx]
    y_columns = [item for item in y_columns if str(item[1] or "").strip().lower() not in {"run_id", "source_row_count", "point_index", "sample_count"}] or y_columns
    y_columns.sort(key=lambda item: chart_column_priority(str(item[1])))
    y_columns = y_columns[:4]
    if not y_columns:
        return None
    chart_series = []
    for idx, name in y_columns:
        points = []
        for row_index, row in enumerate(rows):
            y_val = coerce_numeric(row[idx]) if idx < len(row) else None
            if y_val is None:
                continue
            if x_idx is None:
                x_val: float | str = row_index + 1
            else:
                x_candidate = row[x_idx] if x_idx < len(row) else row_index + 1
                numeric_x = coerce_numeric(x_candidate)
                x_val = numeric_x if numeric_x is not None else row_index + 1
            points.append({"x": x_val, "y": y_val})
        if x_idx is not None and len(points) >= 8:
            unique_x = len({point["x"] for point in points})
            duplicate_ratio = 1.0 - (unique_x / max(len(points), 1))
            if duplicate_ratio >= 0.25 and not chart_is_coordinate_column(name):
                points = aggregate_points_by_x(points)
        if points:
            chart_series.append({"name": humanize_key(name), "points": points})
    if not chart_series:
        return None
    return {
        "title": artifact["logical_path"],
        "artifact_id": int(artifact["artifact_id"]),
        "download_url": artifact_url(int(artifact["artifact_id"]), download=True),
        "xaxis_title": humanize_key(header[x_idx]) if x_idx is not None and x_idx < len(header) else "Index",
        "yaxis_title": "Value",
        "series": chart_series,
    }


def build_numeric_charts_from_artifacts(artifacts: list[dict[str, Any]], limit: int = 12) -> list[dict[str, Any]]:
    charts: list[dict[str, Any]] = []
    def chart_priority(logical_path: str) -> tuple[int, str]:
        path = logical_path.lower()
        if "runtime_operating_mode" in path:
            return (0, path)
        if "cqi_table_reference" in path:
            return (1, path)
        if "mcs_table_reference" in path:
            return (2, path)
        if "live_link_snr_sweep" in path:
            return (3, path)
        if "lls_snr_sweep" in path:
            return (4, path)
        if "constellation_preview" in path:
            return (5, path)
        if "prach" in path:
            return (6, path)
        if "harq" in path:
            return (7, path)
        if "energy" in path or "rf" in path:
            return (8, path)
        if "beam" in path:
            return (9, path)
        if "pdsch" in path or "pusch" in path:
            return (10, path)
        return (20, path)
    candidates = [
        art
        for art in artifacts
        if art["artifact_kind"] == "table_csv"
        and art["byte_size"] <= 750_000
        and classify_result_section(str(art["logical_path"])) not in {"geometry", "meta"}
        and any(
            token in art["logical_path"].lower()
            for token in ("summary", "trace", "trial", "timeline", "timeseries", "kpi", "outputs", "report", "sweep", "preview", "stage", "reference")
        )
    ]
    candidates.sort(key=lambda art: chart_priority(str(art["logical_path"])))
    for art in candidates:
        chart = build_numeric_chart_from_artifact(art)
        if chart:
            charts.append(chart)
        if len(charts) >= limit:
            break
    return charts


def compact_run_row(run_row: dict[str, Any], artifacts: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    keep = [
        "run_id",
        "scenario_id",
        "run_tag",
        "bucket",
        "profile_name",
        "backend",
        "status_text",
        "created_utc",
        "updated_utc",
        "run_folder",
    ]
    out = {key: run_row.get(key) for key in keep}
    summary_row = load_scenario_summary_row(artifacts or [])
    for summary_key, out_key in {
        "RunCompletion": "run_completion",
        "ResultOk": "result_ok",
        "CaseOk": "case_ok",
        "RequiredFailureCount": "required_failure_count",
        "FailingCaseCount": "failing_case_count",
        "WarningCount": "warning_count",
        "StatusAuthority": "status_authority",
        "RuntimeTruthContractOk": "runtime_truth_contract_ok",
        "RoundtripMismatchCount": "roundtrip_mismatch_count",
        "RequiredRuntimeEvidenceMissingCount": "required_runtime_evidence_missing_count",
        "StrictTruthFailureCount": "strict_truth_failure_count",
        "StrictProxyGuardFailureCount": "strict_proxy_guard_failure_count",
        "CanonicalArtifactGapCount": "canonical_artifact_gap_count",
        "RuntimeTruthContractFailures": "runtime_truth_contract_failures",
        "AuthoritativeStatusSource": "authoritative_status_source",
        "ErrorSource": "error_source",
        "ErrorIdentifier": "error_identifier",
        "ErrorMessage": "error_message",
    }.items():
        if summary_key in summary_row:
            out[out_key] = summary_row.get(summary_key)
    return out


def map_table_rows(artifacts: list[dict[str, Any]], keywords: tuple[str, ...], marker_type: str) -> list[dict[str, Any]]:
    candidates = [
        art
        for art in artifacts
        if art["byte_size"] <= 2_000_000 and any(key in art["logical_path"].lower() for key in keywords)
    ]
    markers = []
    lat_names = {"lat", "latitude", "latdeg", "sitelatitude", "uelatitude"}
    lon_names = {"lon", "lng", "longitude", "londeg", "sitelongitude", "uelongitude"}
    label_names = {"siteid", "ueid", "sectorid", "trpid", "name", "label"}
    coord_mode_names = {"coordinatemode", "coordinate_mode"}
    anchor_names = {"mapanchorlabel", "map_anchor_label", "anchorlabel", "anchor_label"}
    for art in candidates[:4]:
        header, rows = load_cached_csv_preview(int(art["artifact_id"]), 500)
        normalized = {re.sub(r"[^a-z0-9]+", "", name.lower()): idx for idx, name in enumerate(header)}
        lat_idx = next((idx for key, idx in normalized.items() if key in lat_names), None)
        lon_idx = next((idx for key, idx in normalized.items() if key in lon_names), None)
        if lat_idx is None or lon_idx is None:
            continue
        label_idx = next((idx for key, idx in normalized.items() if key in label_names), None)
        coord_mode_idx = next((idx for key, idx in normalized.items() if key in coord_mode_names), None)
        anchor_idx = next((idx for key, idx in normalized.items() if key in anchor_names), None)
        for pos, row in enumerate(rows):
            record = {header[idx]: row[idx] if idx < len(row) else "" for idx in range(len(header))}
            if lat_idx >= len(row) or lon_idx >= len(row):
                continue
            lat, lon = resolve_row_coordinates(record)
            if lat is None or lon is None:
                continue
            label = row[label_idx] if label_idx is not None and label_idx < len(row) else f"{marker_type.title()} {pos + 1}"
            coordinate_mode = row[coord_mode_idx] if coord_mode_idx is not None and coord_mode_idx < len(row) else ""
            anchor_label = row[anchor_idx] if anchor_idx is not None and anchor_idx < len(row) else ""
            markers.append(
                {
                    "lat": lat,
                    "lon": lon,
                    "label": label,
                    "type": marker_type,
                    "source": art["logical_path"],
                    "coordinate_mode": coordinate_mode,
                    "anchor_label": anchor_label,
                }
            )
    return markers


def sample_evenly(items: list[Any], max_items: int) -> list[Any]:
    if len(items) <= max_items:
        return items
    if max_items <= 1:
        return [items[-1]]
    step = (len(items) - 1) / float(max_items - 1)
    out: list[T] = []
    for idx in range(max_items):
        out.append(items[round(idx * step)])
    return out


def build_coverage_points(coverage_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    points: list[dict[str, Any]] = []
    for row in coverage_rows:
        lat, lon = resolve_row_coordinates(row)
        if lat is None or lon is None:
            continue
        point: dict[str, Any] = {
            "lat": lat,
            "lon": lon,
            "ueid": coerce_numeric(row.get("UEID")),
            "slot": coerce_numeric(row.get("Slot")),
            "serving_cell": coerce_numeric(row.get("ServingCell")),
            "serving_site": coerce_numeric(row.get("ServingSite")),
            "serving_sector": coerce_numeric(row.get("ServingSector")),
            "ReceiverHestWidebandSINR_dB": row.get("ReceiverHestWidebandSINR_dB"),
            "DecoderTruthProxyWidebandSINR_dB": row.get("DecoderTruthProxyWidebandSINR_dB", row.get("DecoderTruthProxySINR_dB")),
            "MeasuredWidebandSINR_dB": row.get("MeasuredWidebandSINR_dB"),
            "SystemLevelWidebandSINR_dB": row.get("SystemLevelWidebandSINR_dB", row.get("SystemLevelSINR_dB")),
            "LargeScaleWidebandSINR_dB": row.get("LargeScaleWidebandSINR_dB"),
            "RSRPSource": row.get("RSRPSource"),
            "WidebandSINRSource": row.get("WidebandSINRSource"),
            "WidebandSINRValueRole": row.get("WidebandSINRValueRole", row.get("SINRValueRole")),
            "WidebandSINRValueStatus": row.get("WidebandSINRValueStatus", row.get("SINRValueStatus")),
            "SystemLevelSINRSource": row.get("SystemLevelSINRSource"),
            "SystemLevelSINRValueRole": row.get("SystemLevelSINRValueRole"),
            "SystemLevelSINRValueStatus": row.get("SystemLevelSINRValueStatus"),
            "ReceiverHestSINRValueStatus": row.get("ReceiverHestSINRValueStatus"),
            "DecoderTruthProxySINRValueStatus": row.get("DecoderTruthProxySINRValueStatus"),
        }
        for spec in MAP_METRIC_SPECS:
            key = spec["key"]
            point[key] = row.get(key)
        if point.get("SystemLevelWidebandSINR_dB") in {None, ""}:
            point["SystemLevelWidebandSINR_dB"] = row.get("SystemLevelSINR_dB")
        points.append(point)
    return points


def build_coverage_points_from_serving_rows(serving_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    points: list[dict[str, Any]] = []
    for row in serving_rows:
        lat, lon = resolve_row_coordinates(row)
        if lat is None or lon is None:
            continue
        points.append(
            {
                "lat": lat,
                "lon": lon,
                "ueid": coerce_numeric(row.get("UEID")),
                "slot": coerce_numeric(row.get("Slot")),
                "serving_cell": coerce_numeric(row.get("ServingCell")),
                "serving_site": coerce_numeric(row.get("ServingSite")),
                "serving_sector": coerce_numeric(row.get("ServingSector")),
                "CellThroughput_Mbps": row.get("CellThroughput_Mbps"),
                "RSRP_dBm": row.get("RSRP_dBm"),
                "EstimatedWidebandSINR_dB": row.get("EstimatedWidebandSINR_dB"),
                "ReceiverHestWidebandSINR_dB": row.get("ReceiverHestWidebandSINR_dB"),
                "DecoderTruthProxyWidebandSINR_dB": row.get("DecoderTruthProxyWidebandSINR_dB", row.get("DecoderTruthProxySINR_dB")),
                "MeasuredWidebandSINR_dB": row.get("MeasuredWidebandSINR_dB"),
                "SystemLevelWidebandSINR_dB": row.get("SystemLevelWidebandSINR_dB", row.get("SystemLevelSINR_dB")),
                "LargeScaleWidebandSINR_dB": row.get("LargeScaleWidebandSINR_dB"),
                "RSRPSource": row.get("RSRPSource"),
                "WidebandSINRSource": row.get("WidebandSINRSource"),
                "WidebandSINRValueRole": row.get("WidebandSINRValueRole", row.get("SINRValueRole")),
                "WidebandSINRValueStatus": row.get("WidebandSINRValueStatus", row.get("SINRValueStatus")),
                "SystemLevelSINRSource": row.get("SystemLevelSINRSource"),
                "SystemLevelSINRValueRole": row.get("SystemLevelSINRValueRole"),
                "SystemLevelSINRValueStatus": row.get("SystemLevelSINRValueStatus"),
                "ReceiverHestSINRValueStatus": row.get("ReceiverHestSINRValueStatus"),
                "DecoderTruthProxySINRValueStatus": row.get("DecoderTruthProxySINRValueStatus"),
                "CQIDerivedModulation": row.get("CQIDerivedModulation"),
                "CoverageScore": row.get("CoverageScore"),
                "HARQFailureRate": row.get("HARQFailureRate"),
                "Pathloss_dB": row.get("Pathloss_dB"),
                "UserThroughput_Mbps": row.get("UserThroughput_Mbps"),
                "WidebandCQI": row.get("WidebandCQI"),
            }
        )
    return points


def build_coverage_points_from_measurement_rows(measurement_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    points: list[dict[str, Any]] = []
    for row in measurement_rows:
        lat, lon = resolve_row_coordinates(row)
        if lat is None or lon is None:
            continue
        points.append(
            {
                "lat": lat,
                "lon": lon,
                "ueid": coerce_numeric(row.get("UEID")),
                "slot": coerce_numeric(row.get("Slot")),
                "serving_cell": coerce_numeric(row.get("CellID")),
                "serving_site": coerce_numeric(row.get("SiteID")),
                "serving_sector": coerce_numeric(row.get("SectorID")),
                "CellThroughput_Mbps": row.get("CellThroughput_Mbps"),
                "RSRP_dBm": row.get("RSRP_dBm"),
                "EstimatedWidebandSINR_dB": row.get("EstimatedWidebandSINR_dB"),
                "ReceiverHestWidebandSINR_dB": row.get("ReceiverHestWidebandSINR_dB"),
                "DecoderTruthProxyWidebandSINR_dB": row.get("DecoderTruthProxyWidebandSINR_dB", row.get("DecoderTruthProxySINR_dB")),
                "MeasuredWidebandSINR_dB": row.get("MeasuredWidebandSINR_dB"),
                "SystemLevelWidebandSINR_dB": row.get("SystemLevelWidebandSINR_dB", row.get("SystemLevelSINR_dB")),
                "LargeScaleWidebandSINR_dB": row.get("LargeScaleWidebandSINR_dB"),
                "RSRPSource": row.get("RSRPSource"),
                "WidebandSINRSource": row.get("WidebandSINRSource"),
                "WidebandSINRValueRole": row.get("WidebandSINRValueRole", row.get("SINRValueRole")),
                "WidebandSINRValueStatus": row.get("WidebandSINRValueStatus", row.get("SINRValueStatus")),
                "SystemLevelSINRSource": row.get("SystemLevelSINRSource"),
                "SystemLevelSINRValueRole": row.get("SystemLevelSINRValueRole"),
                "SystemLevelSINRValueStatus": row.get("SystemLevelSINRValueStatus"),
                "ReceiverHestSINRValueStatus": row.get("ReceiverHestSINRValueStatus"),
                "DecoderTruthProxySINRValueStatus": row.get("DecoderTruthProxySINRValueStatus"),
                "CQIDerivedModulation": row.get("CQIDerivedModulation"),
                "CoverageScore": row.get("CoverageScore"),
                "HARQFailureRate": row.get("HARQFailureRate"),
                "Pathloss_dB": row.get("Pathloss_dB"),
                "UserThroughput_Mbps": row.get("UserThroughput_Mbps"),
                "WidebandCQI": row.get("WidebandCQI"),
            }
        )
    return points


def deduplicate_coverage_points(points: list[dict[str, Any]], *, max_points: int = 5000) -> list[dict[str, Any]]:
    deduped: list[dict[str, Any]] = []
    seen: set[tuple[Any, ...]] = set()
    for point in points:
        key = (
            round(float(point.get("lat") or 0.0), 7),
            round(float(point.get("lon") or 0.0), 7),
            point.get("ueid"),
            point.get("slot"),
            point.get("serving_cell"),
        )
        if key in seen:
            continue
        seen.add(key)
        deduped.append(point)
    return sample_evenly(deduped, min(max_points, len(deduped)))


def build_metric_stats(points: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    stats: dict[str, dict[str, Any]] = {}
    for spec in MAP_METRIC_SPECS:
        key = spec["key"]
        if spec["kind"] == "numeric":
            values = [float(value) for value in (coerce_numeric(point.get(key)) for point in points) if value is not None]
            if values:
                stats[key] = {"min": min(values), "max": max(values), "kind": "numeric"}
        else:
            categories = sorted({str(point.get(key) or "").strip() for point in points if str(point.get(key) or "").strip()})
            stats[key] = {"kind": "categorical", "categories": categories}
    return stats


def build_movement_payload(serving_rows: list[dict[str, Any]]) -> dict[str, Any]:
    filtered = []
    for row in serving_rows:
        lat, lon = resolve_row_coordinates(row)
        slot = coerce_numeric(row.get("Slot"))
        ueid = coerce_numeric(row.get("UEID"))
        if lat is None or lon is None or slot is None or ueid is None:
            continue
        filtered.append(
            {
                "lat": lat,
                "lon": lon,
                "slot": int(slot),
                "ueid": int(ueid),
                "serving_cell": coerce_numeric(row.get("ServingCell")),
                "rsrp_dBm": coerce_numeric(row.get("RSRP_dBm")),
                "sinr_dB": coerce_numeric(row.get("ReceiverHestWidebandSINR_dB")),
                "system_level_sinr_dB": coerce_numeric(row.get("SystemLevelWidebandSINR_dB", row.get("SystemLevelSINR_dB"))),
                "cqi": coerce_numeric(row.get("WidebandCQI")),
            }
        )
    if not filtered:
        return {"points": [], "paths": [], "slot_min": None, "slot_max": None, "latest_slot": None}
    filtered.sort(key=lambda item: (item["ueid"], item["slot"]))
    unique_ues = sorted({int(item["ueid"]) for item in filtered})
    selected_ues = unique_ues[: min(128, len(unique_ues))]
    selected = [item for item in filtered if int(item["ueid"]) in selected_ues]
    paths = []
    for ueid in selected_ues:
        ue_points = [item for item in selected if int(item["ueid"]) == ueid]
        sampled = sample_evenly(ue_points, min(96, len(ue_points)))
        paths.append({"ueid": ueid, "points": sampled})
    points = sample_evenly(selected, min(2400, len(selected)))
    slot_values = [int(item["slot"]) for item in selected]
    return {
        "points": points,
        "paths": paths,
        "slot_min": min(slot_values),
        "slot_max": max(slot_values),
        "latest_slot": max(slot_values),
    }


def sample_rows_by_ue(rows: list[dict[str, Any]], *, ue_key: str = "UEID", max_per_ue: int = 96) -> tuple[list[dict[str, Any]], int]:
    grouped: dict[int, list[dict[str, Any]]] = {}
    for row in rows:
        ueid = coerce_numeric(row.get(ue_key))
        if ueid is None:
            continue
        grouped.setdefault(int(ueid), []).append(row)
    sampled: list[dict[str, Any]] = []
    for ueid in sorted(grouped):
        ue_rows = grouped[ueid]
        sampled.extend(sample_evenly(ue_rows, min(max_per_ue, len(ue_rows))))
    return sampled, sum(len(items) for items in grouped.values())


def build_metric_explorer_payload(artifacts: list[dict[str, Any]], summary: dict[str, Any]) -> dict[str, Any]:
    serving_rows_raw = load_first_available_csv_rows(artifacts, ["reports/csv/live_rsrp_serving_trace.csv"], max_rows=50000)
    dl_rows_raw = load_first_available_csv_rows(artifacts, ["air_interface/csv/dl_pdsch_trials.csv"], max_rows=50000)
    ul_rows_raw = load_first_available_csv_rows(artifacts, ["air_interface/csv/ul_pusch_trials.csv"], max_rows=50000)
    user_perf_rows = load_first_available_csv_rows(artifacts, ["reports/csv/live_user_performance_snapshot.csv"], max_rows=4096)
    serving_rows, serving_raw_count = sample_rows_by_ue(serving_rows_raw, ue_key="UEID", max_per_ue=120)
    dl_rows, dl_raw_count = sample_rows_by_ue(dl_rows_raw, ue_key="UEID", max_per_ue=120)
    ul_rows, ul_raw_count = sample_rows_by_ue(ul_rows_raw, ue_key="UEID", max_per_ue=120)
    records: dict[tuple[int, int], dict[str, Any]] = {}

    def ensure_record(slot_value: Any, ueid_value: Any) -> dict[str, Any] | None:
        slot = coerce_numeric(slot_value)
        ueid = coerce_numeric(ueid_value)
        if slot is None or ueid is None:
            return None
        key = (int(slot), int(ueid))
        record = records.get(key)
        if record is None:
            record = {
                "slot": int(slot),
                "ueid": int(ueid),
                "time_s": None,
                "serving_cell": None,
                "base_station_id": None,
                "sinr_dB": None,
                "system_level_sinr_dB": None,
                "cqi": None,
                "rsrp_dBm": None,
                "dl_goodput_mbps": None,
                "ul_goodput_mbps": None,
                "dl_offered_mbps": None,
                "ul_offered_mbps": None,
                "dl_mcs": None,
                "ul_mcs": None,
                "dl_prbs": None,
                "ul_prbs": None,
                "_dl_mcs_sum": 0.0,
                "_dl_mcs_count": 0,
                "_ul_mcs_sum": 0.0,
                "_ul_mcs_count": 0,
                "_has_dl": False,
                "_has_ul": False,
            }
            records[key] = record
        return record

    for row in serving_rows:
        record = ensure_record(row.get("Slot"), row.get("UEID"))
        if record is None:
            continue
        time_s = coerce_numeric(row.get("Time_s"))
        if time_s is not None:
            record["time_s"] = float(time_s)
        serving_cell = coerce_numeric(row.get("ServingCell", row.get("CellID")))
        if serving_cell is not None:
            record["serving_cell"] = int(serving_cell)
        base_station_id = coerce_numeric(row.get("BaseStationID"))
        if base_station_id is not None:
            record["base_station_id"] = int(base_station_id)
        sinr = coerce_numeric(row.get("ReceiverHestWidebandSINR_dB", row.get("ReceiverHestSINR_dB")))
        system_sinr = coerce_numeric(row.get("SystemLevelWidebandSINR_dB", row.get("SystemLevelSINR_dB")))
        cqi = coerce_numeric(row.get("WidebandCQI"))
        rsrp = coerce_numeric(row.get("ServingRSRP_dBm", row.get("RSRP_dBm")))
        if sinr is not None:
            record["sinr_dB"] = float(sinr)
        if system_sinr is not None:
            record["system_level_sinr_dB"] = float(system_sinr)
        if cqi is not None:
            record["cqi"] = float(cqi)
        if rsrp is not None:
            record["rsrp_dBm"] = float(rsrp)

    for row in dl_rows:
        record = ensure_record(row.get("Slot"), row.get("UEID"))
        if record is None:
            continue
        record["_has_dl"] = True
        goodput = coerce_numeric(row.get("Goodput_Mbps"))
        offered = coerce_numeric(row.get("OfferedThroughput_Mbps"))
        mcs = coerce_numeric(row.get("MCSIndex", row.get("MCS")))
        prbs = coerce_numeric(row.get("AllocatedPRBCount", row.get("PRBs")))
        if goodput is not None:
            record["dl_goodput_mbps"] = float((record["dl_goodput_mbps"] or 0.0) + goodput)
        if offered is not None:
            record["dl_offered_mbps"] = float((record["dl_offered_mbps"] or 0.0) + offered)
        if prbs is not None:
            record["dl_prbs"] = float((record["dl_prbs"] or 0.0) + prbs)
        serving_cell = coerce_numeric(row.get("CellID", row.get("ServingCell")))
        if serving_cell is not None:
            record["serving_cell"] = int(serving_cell)
        base_station_id = coerce_numeric(row.get("BaseStationID"))
        if base_station_id is not None:
            record["base_station_id"] = int(base_station_id)
        if mcs is not None:
            record["_dl_mcs_sum"] += float(mcs)
            record["_dl_mcs_count"] += 1
        if record["sinr_dB"] is None:
            trial_sinr = coerce_numeric(row.get("ReceiverHestSINR_dB", row.get("MeasuredTrialSINR_dB")))
            if trial_sinr is not None:
                record["sinr_dB"] = float(trial_sinr)
        if record["cqi"] is None:
            cqi = coerce_numeric(row.get("WidebandCQI"))
            if cqi is not None:
                record["cqi"] = float(cqi)

    for row in ul_rows:
        record = ensure_record(row.get("Slot"), row.get("UEID"))
        if record is None:
            continue
        record["_has_ul"] = True
        goodput = coerce_numeric(row.get("Goodput_Mbps"))
        offered = coerce_numeric(row.get("OfferedThroughput_Mbps"))
        mcs = coerce_numeric(row.get("MCSIndex", row.get("MCS")))
        prbs = coerce_numeric(row.get("AllocatedPRBCount", row.get("PRBs")))
        if goodput is not None:
            record["ul_goodput_mbps"] = float((record["ul_goodput_mbps"] or 0.0) + goodput)
        if offered is not None:
            record["ul_offered_mbps"] = float((record["ul_offered_mbps"] or 0.0) + offered)
        if prbs is not None:
            record["ul_prbs"] = float((record["ul_prbs"] or 0.0) + prbs)
        serving_cell = coerce_numeric(row.get("CellID", row.get("ServingCell")))
        if serving_cell is not None:
            record["serving_cell"] = int(serving_cell)
        base_station_id = coerce_numeric(row.get("BaseStationID"))
        if base_station_id is not None:
            record["base_station_id"] = int(base_station_id)
        if mcs is not None:
            record["_ul_mcs_sum"] += float(mcs)
            record["_ul_mcs_count"] += 1
        if record["sinr_dB"] is None:
            trial_sinr = coerce_numeric(row.get("ReceiverHestSINR_dB", row.get("MeasuredTrialSINR_dB")))
            if trial_sinr is not None:
                record["sinr_dB"] = float(trial_sinr)

    metric_rows: list[dict[str, Any]] = []
    for record in sorted(records.values(), key=lambda item: (int(item["ueid"]), int(item["slot"]))):
        record["dl_mcs"] = (record["_dl_mcs_sum"] / record["_dl_mcs_count"]) if record["_dl_mcs_count"] else None
        record["ul_mcs"] = (record["_ul_mcs_sum"] / record["_ul_mcs_count"]) if record["_ul_mcs_count"] else None
        if record["_has_dl"] and record["_has_ul"]:
            record["direction"] = "DL+UL"
        elif record["_has_dl"]:
            record["direction"] = "DL"
        elif record["_has_ul"]:
            record["direction"] = "UL"
        else:
            record["direction"] = "channel"
        for private_key in ("_dl_mcs_sum", "_dl_mcs_count", "_ul_mcs_sum", "_ul_mcs_count", "_has_dl", "_has_ul"):
            record.pop(private_key, None)
        metric_rows.append(record)

    unique_ueids = sorted(
        {
            int(value)
            for value in (
                coerce_numeric(row.get("UEID"))
                for row in serving_rows + dl_rows + ul_rows
            )
            if value is not None
        }
    )
    unique_cell_ids = sorted(
        {
            int(value)
            for value in (
                coerce_numeric(row.get("ServingCell", row.get("CellID")))
                for row in serving_rows + dl_rows + ul_rows
            )
            if value is not None
        }
    )
    perf_summary: dict[str, dict[str, Any]] = {}
    for row in user_perf_rows:
        ueid = coerce_numeric(row.get("UEIndex"))
        if ueid is None:
            continue
        perf_summary[str(int(ueid))] = {
            "ueid": int(ueid),
            "dl_throughput_mbps": coerce_numeric(row.get("DL_Throughput_Mbps")),
            "ul_throughput_mbps": coerce_numeric(row.get("UL_Throughput_Mbps")),
            "user_throughput_mbps": coerce_numeric(row.get("UserThroughput_Mbps")),
            "dl_bler": coerce_numeric(row.get("DL_BLER")),
            "ul_bler": coerce_numeric(row.get("UL_BLER")),
            "dl_mean_measured_sinr_dB": coerce_numeric(row.get("DL_MeanMeasuredSINR_dB")),
            "ul_mean_measured_sinr_dB": coerce_numeric(row.get("UL_MeanMeasuredSINR_dB")),
            "harq_failure_rate": coerce_numeric(row.get("HARQFailureRate")),
            "source_table": "reports/csv/live_user_performance_snapshot.csv",
            "fidelity_level": "abstraction_level",
        }
    if not metric_rows:
        return {
            "available": False,
            "default_x_axis": "slot",
            "x_axes": [{"id": "slot", "label": "Slot"}],
            "available_metrics": [],
            "metric_count": 0,
            "rows": [],
            "ue_ids": unique_ueids,
            "ue_summaries": perf_summary,
            "cell_ids": unique_cell_ids,
            "configured_ue_count": int(coerce_numeric(summary.get("configured_users")) or len(unique_ueids)),
            "chartable_ue_count": len(unique_ueids),
            "chartable_cell_count": len(unique_cell_ids),
            "source_tables": [],
            "sampling": {
                "serving_trace_rows_raw": serving_raw_count,
                "serving_trace_rows_browser": len(serving_rows),
                "dl_trial_rows_raw": dl_raw_count,
                "dl_trial_rows_browser": len(dl_rows),
                "ul_trial_rows_raw": ul_raw_count,
                "ul_trial_rows_browser": len(ul_rows),
            },
            "unavailable_reason": "No slot-indexed UE runtime trace rows are available from the selected run.",
        }

    x_axes = [{"id": "slot", "label": "Slot"}]
    if any(row.get("time_s") is not None for row in metric_rows):
        x_axes.append({"id": "time_s", "label": "Time (s)"})
    available_metrics = [
        {
            "id": "sinr_dB",
            "label": "Receiver Hest SINR (dB)",
            "unit": "dB",
            "source_table": "reports/csv/live_rsrp_serving_trace.csv",
            "fidelity_level": "abstraction_level",
        },
        {
            "id": "system_level_sinr_dB",
            "label": "System-Level SINR (dB)",
            "unit": "dB",
            "source_table": "reports/csv/live_rsrp_serving_trace.csv",
            "fidelity_level": "abstraction_level",
        },
        {
            "id": "cqi",
            "label": "Wideband CQI",
            "unit": "index",
            "source_table": "reports/csv/live_rsrp_serving_trace.csv",
            "fidelity_level": "abstraction_level",
        },
        {
            "id": "rsrp_dBm",
            "label": "Serving RSRP (dBm)",
            "unit": "dBm",
            "source_table": "reports/csv/live_rsrp_serving_trace.csv",
            "fidelity_level": "abstraction_level",
        },
        {
            "id": "dl_goodput_mbps",
            "label": "DL Goodput (Mbps)",
            "unit": "Mbps",
            "source_table": "air_interface/csv/dl_pdsch_trials.csv",
            "fidelity_level": "waveform_level",
        },
        {
            "id": "ul_goodput_mbps",
            "label": "UL Goodput (Mbps)",
            "unit": "Mbps",
            "source_table": "air_interface/csv/ul_pusch_trials.csv",
            "fidelity_level": "waveform_level",
        },
        {
            "id": "dl_offered_mbps",
            "label": "DL Offered Throughput (Mbps)",
            "unit": "Mbps",
            "source_table": "air_interface/csv/dl_pdsch_trials.csv",
            "fidelity_level": "waveform_level",
        },
        {
            "id": "ul_offered_mbps",
            "label": "UL Offered Throughput (Mbps)",
            "unit": "Mbps",
            "source_table": "air_interface/csv/ul_pusch_trials.csv",
            "fidelity_level": "waveform_level",
        },
        {
            "id": "dl_prbs",
            "label": "DL Allocated PRBs",
            "unit": "PRBs",
            "source_table": "air_interface/csv/dl_pdsch_trials.csv",
            "fidelity_level": "waveform_level",
        },
        {
            "id": "ul_prbs",
            "label": "UL Allocated PRBs",
            "unit": "PRBs",
            "source_table": "air_interface/csv/ul_pusch_trials.csv",
            "fidelity_level": "waveform_level",
        },
        {
            "id": "dl_mcs",
            "label": "DL MCS Index",
            "unit": "index",
            "source_table": "air_interface/csv/dl_pdsch_trials.csv",
            "fidelity_level": "waveform_level",
        },
        {
            "id": "ul_mcs",
            "label": "UL MCS Index",
            "unit": "index",
            "source_table": "air_interface/csv/ul_pusch_trials.csv",
            "fidelity_level": "waveform_level",
        },
    ]
    available_metrics = [metric for metric in available_metrics if any(row.get(metric["id"]) is not None for row in metric_rows)]
    configured_ue_count = int(coerce_numeric(summary.get("configured_users")) or len(unique_ueids))
    source_tables = sorted(
        {
            metric["source_table"]
            for metric in available_metrics
            if str(metric.get("source_table") or "").strip()
        }
    )
    return {
        "available": True,
        "default_x_axis": "slot",
        "x_axes": x_axes,
        "available_metrics": available_metrics,
        "metric_count": len(available_metrics),
        "default_metrics": [metric["id"] for metric in available_metrics if metric["id"] in {"sinr_dB", "cqi"}][:2] or ([available_metrics[0]["id"]] if available_metrics else []),
        "rows": metric_rows,
        "ue_ids": unique_ueids,
        "ue_summaries": perf_summary,
        "cell_ids": unique_cell_ids,
        "configured_ue_count": configured_ue_count,
        "chartable_ue_count": len(unique_ueids),
        "chartable_cell_count": len(unique_cell_ids),
        "source_tables": source_tables,
        "sampling": {
            "serving_trace_rows_raw": serving_raw_count,
            "serving_trace_rows_browser": len(serving_rows),
            "dl_trial_rows_raw": dl_raw_count,
            "dl_trial_rows_browser": len(dl_rows),
            "ul_trial_rows_raw": ul_raw_count,
            "ul_trial_rows_browser": len(ul_rows),
            "chart_rows_browser": len(metric_rows),
        },
        "sampling_note": "Browser charts use sampled runtime rows for responsiveness. Source CSV artifacts remain downloadable for full-fidelity inspection.",
    }


def build_map_payload(run_id: int, artifacts: list[dict[str, Any]]) -> dict[str, Any]:
    site_rows = build_geometry_rows(artifacts, "reports/csv/sites.csv", max_rows=512)
    sector_rows = build_geometry_rows(artifacts, "reports/csv/sectors.csv", max_rows=2048)
    sites = map_table_rows(artifacts, ("sites.csv",), "site")
    if not sites:
        sites = map_table_rows(artifacts, ("sectors.csv",), "site")
    if not sites:
        sites = map_table_rows(artifacts, ("trps.csv",), "site")
    static_ues = map_table_rows(artifacts, ("ues.csv", "users.csv"), "ue")
    coverage_rows = load_first_available_csv_rows(artifacts, ["reports/csv/live_coverage_layer.csv", "reports/csv/live_coverage_snapshot.csv"], max_rows=5000)
    serving_rows = load_first_available_csv_rows(artifacts, ["reports/csv/live_rsrp_serving_trace.csv"], max_rows=5000)
    measurement_rows = load_first_available_csv_rows(artifacts, ["reports/csv/live_cell_measurement_trace.csv"], max_rows=5000)
    coverage_points = build_coverage_points(coverage_rows)
    if len(coverage_points) < 8:
        coverage_points = deduplicate_coverage_points(
            coverage_points
            + build_coverage_points_from_serving_rows(serving_rows)
            + build_coverage_points_from_measurement_rows(measurement_rows)
        )
    movement = build_movement_payload(serving_rows)
    site_spacing_rows = site_rows or load_small_csv_rows(artifacts, "reports/csv/sectors.csv", max_rows=256)
    actual_site_spacing_m = estimate_site_spacing_m(site_spacing_rows)
    site_polygons, site_index = build_site_geometry(site_rows, actual_site_spacing_m)
    sector_polygons = build_sector_geometry(sector_rows, site_index, actual_site_spacing_m)
    ues = build_live_ue_markers(movement, static_ues)
    markers = sites + ues
    center = dict(DEFAULT_MAP_CENTER)
    note = "LLS runs do not always emit site/UE geometry. When geometry artifacts are absent, the map falls back to Reliance Corporate Park, Navi Mumbai."
    coord_points = markers + [{"lat": point["lat"], "lon": point["lon"]} for point in coverage_points]
    if coord_points:
        center = {
            "lat": sum(item["lat"] for item in coord_points) / len(coord_points),
            "lon": sum(item["lon"] for item in coord_points) / len(coord_points),
            "label": "Artifact-derived center",
            "source": "artifact_center",
        }
        if any(str(item.get("coordinate_mode") or "").lower().startswith("projected") for item in markers):
            anchor_label = next((str(item.get("anchor_label") or "").strip() for item in markers if str(item.get("anchor_label") or "").strip()), DEFAULT_MAP_CENTER["label"])
            note = (
                "LLS geometry is being projected from simulator-local Cartesian coordinates onto OpenStreetMap "
                f"around {anchor_label}. This is a visualization anchor, not surveyed GPS truth."
            )
    deployment_rows = load_small_csv_rows(artifacts, "reports/csv/deployment_layout_reference.csv", max_rows=2)
    deployment = deployment_rows[0] if deployment_rows else {}
    requested_isd = coerce_numeric(deployment.get("InterSiteDistance_m"))
    if actual_site_spacing_m is not None and requested_isd is not None and requested_isd > 0:
        if abs(actual_site_spacing_m - requested_isd) > max(25.0, 0.15 * requested_isd):
            note += (
                f" Stored geometry spacing is about {actual_site_spacing_m:.1f} m while the deployment reference requests {requested_isd:.1f} m, "
                "so the active run configuration/profile should be checked."
            )
    else:
        markers = [dict(DEFAULT_MAP_CENTER, type="default")]
    if not coord_points:
        coord_points = [dict(DEFAULT_MAP_CENTER)]
    latitudes = [float(item["lat"]) for item in coord_points]
    longitudes = [float(item["lon"]) for item in coord_points]
    min_lat = min(latitudes)
    max_lat = max(latitudes)
    min_lon = min(longitudes)
    max_lon = max(longitudes)
    span = max(abs(max_lat - min_lat), abs(max_lon - min_lon))
    if span < 0.0005:
        preferred_zoom = 18
    elif span < 0.002:
        preferred_zoom = 17
    elif span < 0.01:
        preferred_zoom = 16
    elif span < 0.05:
        preferred_zoom = 15
    else:
        preferred_zoom = 13
    return {
        "run_id": run_id,
        "center": center,
        "sites": sites,
        "ues": ues,
        "markers": markers,
        "site_polygons": site_polygons,
        "sector_polygons": sector_polygons,
        "coverage_points": coverage_points,
        "available_metrics": MAP_METRIC_SPECS,
        "metric_stats": build_metric_stats(coverage_points),
        "movement": movement,
        "bounds": {
            "min_lat": min_lat,
            "max_lat": max_lat,
            "min_lon": min_lon,
            "max_lon": max_lon,
            "span": span,
        },
        "preferred_zoom": preferred_zoom,
        "note": note,
    }


def build_timing_payload(artifacts: list[dict[str, Any]]) -> dict[str, Any]:
    rows = load_first_available_csv_rows(artifacts, ["reports/csv/runtime_stage_profile.csv"], max_rows=256)
    profiler_summary_rows = load_first_available_csv_rows(artifacts, ["reports/csv/runtime_profiler_summary.csv"], max_rows=8)
    function_rows = load_first_available_csv_rows(artifacts, ["reports/csv/runtime_function_profile.csv"], max_rows=256)
    edge_rows = load_first_available_csv_rows(artifacts, ["reports/csv/runtime_function_call_edges.csv"], max_rows=160)
    profiler_summary = profiler_summary_rows[0] if profiler_summary_rows else {}
    total_elapsed = max(
        [float(value) for value in (coerce_numeric(row.get("BundleElapsed_s")) for row in rows) if value is not None],
        default=None,
    ) if rows else None
    stage_art = find_artifact_by_logical_path(artifacts, "reports/csv/runtime_stage_profile.csv")
    profiler_summary_art = find_artifact_by_logical_path(artifacts, "reports/csv/runtime_profiler_summary.csv")
    function_art = find_artifact_by_logical_path(artifacts, "reports/csv/runtime_function_profile.csv")
    edge_art = find_artifact_by_logical_path(artifacts, "reports/csv/runtime_function_call_edges.csv")
    return {
        "rows": rows,
        "total_elapsed_s": total_elapsed,
        "stage_count": len(rows),
        "profiler_summary": profiler_summary,
        "function_rows": function_rows,
        "edge_rows": edge_rows,
        "downloads": {
            "stage": build_artifact_descriptor(stage_art) if stage_art else None,
            "summary": build_artifact_descriptor(profiler_summary_art) if profiler_summary_art else None,
            "functions": build_artifact_descriptor(function_art) if function_art else None,
            "edges": build_artifact_descriptor(edge_art) if edge_art else None,
        },
    }


def summarize_artifacts(artifacts: list[dict[str, Any]]) -> dict[str, Any]:
    tables = [art for art in artifacts if art["artifact_kind"] == "table_csv"]
    images = [art for art in artifacts if str(art.get("mime_type") or "").startswith("image/")]
    markdown = [art for art in artifacts if art["artifact_kind"] == "markdown_report"]
    return {
        "artifacts_total": len(artifacts),
        "tables_total": len(tables),
        "images_total": len(images),
        "markdown_total": len(markdown),
        "bytes_total": int(sum(int(art.get("byte_size") or 0) for art in artifacts)),
    }


def build_status_issue_registry_rows(run_row: dict[str, Any], runtime_context: dict[str, Any]) -> list[dict[str, Any]]:
    status_json = parse_status_json(run_row)
    status_text = str(run_row.get("status_text") or status_json.get("run_completion") or "").strip()
    result_ok = status_json.get("result_ok")
    required_failures = status_json.get("required_failure_count")
    rows: list[dict[str, Any]] = []
    failed_status = (
        status_text.lower() in {"completed_with_failures", "failed", "aborted", "timeout", "stale_running", "stalled_running_process_no_heartbeat"}
        or status_text.lower().startswith("aborted")
        or status_text.lower().startswith("stalled")
    )
    failed_result = result_ok is False or str(result_ok).lower() == "false"
    try:
        failed_required = int(required_failures or 0) > 0
    except Exception:
        failed_required = False
    if failed_status or failed_result or failed_required:
        rows.append(
            {
                "issue_id": f"run_status_{run_row.get('run_id')}",
                "severity": "critical" if failed_required or failed_result else "high",
                "issue_status": "CRASHED" if (status_text.lower() in {"failed", "aborted", "timeout"} or status_text.lower().startswith("aborted")) else "REVIEW_REQUIRED",
                "issue_category": "run_status",
                "direction": "",
                "ue_id": "",
                "cell_id": "",
                "block_name": "run",
                "metric_name": "ResultOk/RequiredFailureCount",
                "observed_value": f"status={status_text}; result_ok={result_ok}; required_failure_count={required_failures}",
                "expected_or_policy": "ResultOk true requires zero required failures and truthful completion.",
                "evidence_artifact_ref": "sim_runs.status_json",
                "root_cause_hint": str(status_json.get("error_message") or status_json.get("message") or "Run status indicates failure or review needed."),
                "fix_plan": str(status_json.get("next_action") or "Open logs and required case outputs, fix the failing runtime/export path, then rerun."),
                "analytics_visible_flag": True,
            }
        )
    debug = runtime_context.get("debug") if isinstance(runtime_context, dict) else None
    if isinstance(debug, dict):
        try:
            missing_count = int(debug.get("required_runtime_evidence_missing_count") or 0)
        except Exception:
            missing_count = 0
        if missing_count > 0:
            rows.append(
                {
                    "issue_id": f"runtime_evidence_missing_{run_row.get('run_id')}",
                    "severity": "high",
                    "issue_status": "PARTIAL",
                    "issue_category": "runtime_evidence",
                    "direction": "",
                    "ue_id": "",
                    "cell_id": "",
                    "block_name": "runtime/export",
                    "metric_name": "RequiredRuntimeEvidenceMissingCount",
                    "observed_value": str(missing_count),
                    "expected_or_policy": "Required runtime evidence count must be zero for complete analytics.",
                    "evidence_artifact_ref": "sim_runs.status_json|runtime_context.debug",
                    "root_cause_hint": "A required runtime evidence stream is missing.",
                    "fix_plan": "Inspect output coverage and the missing evidence table/artifact before accepting analytics.",
                    "analytics_visible_flag": True,
                }
            )
    return rows


def condense_live_payload(full_payload: dict[str, Any]) -> dict[str, Any]:
    charts = dict(full_payload.get("charts") or {})
    lite_charts = {
        "artifact_activity": charts.get("artifact_activity"),
        "log_activity": charts.get("log_activity"),
        "progress_tabs": charts.get("progress_tabs"),
    }
    return {
        "run": full_payload.get("run"),
        "summary": full_payload.get("summary"),
        "counts": full_payload.get("counts"),
        "metrics": full_payload.get("metrics"),
        "runtime_context": full_payload.get("runtime_context"),
        "section_counts": full_payload.get("section_counts"),
        "analysis_mode": full_payload.get("analysis_mode"),
        "logs_recent": full_payload.get("logs_recent"),
        "charts": lite_charts,
        "payload_version": full_payload.get("payload_version"),
        "artifact_version": full_payload.get("artifact_version"),
        "lite": True,
    }


def build_live_payload(run_id: int, *, lite: bool = False) -> dict[str, Any]:
    run_row = fetch_run(run_id)
    if run_row is None:
        raise KeyError(f"Run {run_id} was not found.")
    inserted_logs = sync_runtime_log_for_run(run_row)
    if inserted_logs:
        run_row = fetch_run(run_id) or run_row
    artifacts = fetch_artifacts(run_id)
    feature_policy = extract_run_feature_policy(run_row)
    status_text = str(run_row.get("status_text") or "").strip().lower()
    should_materialize_contract = (
        is_terminal_status(status_text)
        or (
            status_text == "running"
            and any(str(art.get("artifact_kind") or "") == "table_csv" for art in artifacts)
        )
    )
    if should_materialize_contract:
        contract_materializer.materialize_run_contract_artifacts(
            run_row,
            artifacts,
            fetch_artifact_bytes=fetch_artifact_bytes,
            db_connection_factory=db_connection,
            feature_policy=feature_policy,
            lock_timeout_seconds=0,
        )
        artifacts = fetch_artifacts(run_id)
    latest_artifact_id = max((int(art.get("artifact_id") or 0) for art in artifacts), default=0)
    artifact_version = f"{len(artifacts)}|{latest_artifact_id}"
    cache_version = f"{run_row.get('updated_utc')}|{run_row.get('status_text')}|{inserted_logs}|{artifact_version}"
    if inserted_logs == 0 and CACHED_PAYLOAD_VERSION.get(run_id) == cache_version and run_id in LIVE_PAYLOAD_CACHE:
        cached_payload = LIVE_PAYLOAD_CACHE[run_id]
        return condense_live_payload(cached_payload) if lite else cached_payload
    logs_recent = fetch_logs(run_id, limit=MAX_LIVE_LOG_ROWS, descending=True)
    counts = summarize_artifacts(artifacts)
    counts["logs_total"] = count_logs(run_id)
    runtime_context = extract_runtime_context(run_row, artifacts)
    output_coverage = build_output_coverage_context(artifacts)
    public_artifacts = filter_public_artifacts_for_policy(artifacts, feature_policy)
    if not output_coverage.get("issue_registry"):
        status_issue_rows = build_status_issue_registry_rows(run_row, runtime_context)
        if status_issue_rows:
            output_coverage["issue_registry"] = status_issue_rows
            for card in output_coverage.get("dashboard_cards", []):
                if card.get("label") == "Issue Rows":
                    card["value"] = len(status_issue_rows)
                    break
    sorted_artifacts = sorted(public_artifacts, key=artifact_sort_key)
    table_artifacts = [art for art in sorted_artifacts if art["artifact_kind"] == "table_csv"]
    image_artifacts = [art for art in sorted_artifacts if str(art.get("mime_type") or "").startswith("image/")]
    recent_tables = [build_artifact_descriptor(art) for art in reversed(table_artifacts[-12:])]
    recent_images = [build_artifact_descriptor(art) for art in reversed(image_artifacts[-12:])]
    all_tables = dedupe_table_descriptors_for_ui([build_artifact_descriptor(art) for art in table_artifacts])
    all_images = [build_artifact_descriptor(art) for art in image_artifacts]
    recent_tables = [item for item in all_tables if item["artifact_id"] in {rt["artifact_id"] for rt in recent_tables}]
    summary_tables = [
        item
        for item in all_tables
        if item["section"] in {"summary", "debug", "meta"}
        or any(token in str(item["logical_path"]).lower() for token in ("summary", "manifest", "kpi", "coverage", "runtime", "status"))
    ]
    section_counts: dict[str, int] = {}
    for item in all_tables:
        section_counts[item["section"]] = section_counts.get(item["section"], 0) + 1
    analysis_mode = "post_run" if is_terminal_status(status_text) else "live"
    summary_chart_artifacts = [
        art
        for art in table_artifacts
        if classify_result_section(str(art["logical_path"])) in {"summary", "debug", "rf", "csi", "harq"}
        or any(token in str(art["logical_path"]).lower() for token in ("summary", "sweep", "kpi", "status"))
    ]
    summary = build_live_summary(run_row, artifacts, runtime_context)
    numeric_tabs = build_numeric_charts_from_artifacts(table_artifacts, limit=24)
    summary_tabs = build_numeric_charts_from_artifacts(summary_chart_artifacts, limit=16)
    contract_surface = build_output_contract_surface(run_row, artifacts, numeric_tabs, summary_tabs, output_coverage)
    payload = {
        "run": compact_run_row(run_row, artifacts),
        "summary": summary,
        "counts": counts,
        "metrics": extract_metric_cards(run_row, artifacts, runtime_context),
        "runtime_context": runtime_context,
        "output_coverage": output_coverage,
        "feature_policy": feature_policy,
        "contract_surface": contract_surface,
        "output_contract": {
            "reports": output_contract.product_sections_payload("reports"),
            "analytics": output_contract.product_sections_payload("analytics"),
            "rule": "/reports is runtime truth; /analytics is derived post-processing. Missing outputs stay unavailable.",
        },
        "tables_all": all_tables,
        "tables_recent": recent_tables,
        "tables_summary": summary_tables,
        "images_all": all_images,
        "images_recent": recent_images,
        "section_counts": section_counts,
        "analysis_mode": analysis_mode,
        "logs_recent": logs_recent[-60:],
        "charts": {
            "artifact_activity": build_activity_series(artifacts, "Artifacts"),
            "log_activity": build_activity_series(logs_recent, "Logs"),
            "progress_tabs": build_runtime_progress_charts(logs_recent, parse_status_json(run_row)),
            "numeric_tabs": numeric_tabs,
            "summary_tabs": summary_tabs,
        },
        "timing": build_timing_payload(artifacts),
        "map": build_map_payload(run_id, artifacts),
        "metric_explorer": build_metric_explorer_payload(artifacts, summary),
        "debug": build_debug_payload(run_row, artifacts, logs_recent),
        "payload_version": cache_version,
        "artifact_version": artifact_version,
    }
    CACHED_PAYLOAD_VERSION[run_id] = cache_version
    LIVE_PAYLOAD_CACHE[run_id] = payload
    return condense_live_payload(payload) if lite else payload


def render_user_strip(user_profile: dict[str, Any] | None) -> str:
    if auth_mode_open():
        profile = user_profile or OPEN_ACCESS_PROFILE
        display_name = str(profile.get("display_name") or "Open Access")
        role = str(profile.get("role") or "Intranet Viewer")
        initials = "".join(part[:1].upper() for part in display_name.split()[:2]) or "OA"
        return (
            '<div class="user-strip">'
            f'<span class="profile-chip" title="{html.escape(role)}">'
            f'<span class="profile-avatar">{html.escape(initials)}</span>'
            f'<span><strong>{html.escape(display_name)}</strong><span class="profile-role">{html.escape(role)}</span></span>'
            '</span>'
            '<span class="pill">No login required</span>'
            '</div>'
        )
    if not user_profile:
        return '<div class="user-strip"><a class="button-link" href="/login">Sign In</a></div>'
    username = str(user_profile.get("username") or "")
    display_name = str(user_profile.get("display_name") or username)
    role = str(user_profile.get("role") or "User")
    initials = "".join(part[:1].upper() for part in display_name.split()[:2]) or username[:1].upper()
    return (
        '<div class="user-strip">'
        f'<a class="profile-chip" href="/profile" title="{html.escape(role)}">'
        f'<span class="profile-avatar">{html.escape(initials)}</span>'
        f'<span><strong>{html.escape(display_name)}</strong><span class="profile-role">{html.escape(role)}</span></span>'
        '</a>'
        '<form method="post" action="/logout" class="inline-form">'
        '<button type="submit" class="secondary">Logout</button>'
        '</form>'
        '</div>'
    )


def render_nav(active: str, run_id: int | None = None, user_profile: dict[str, Any] | None = None) -> str:
    latest = run_id or latest_run_id()
    if not user_profile:
        return ""
    tab_links = [
        ("Home", "/home", active == "home"),
        ("Runs", "/runs", active == "runs"),
        ("Result", f"/result?run_id={latest}" if latest else "/result", active == "result"),
        ("Analytics", f"/analytics?run_id={latest}" if latest else "/analytics", active == "analytics"),
        ("Outputs", f"/outputs?run_id={latest}" if latest else "/outputs", active == "outputs"),
        ("Map", f"/map?run_id={latest}" if latest else "/map", active == "map"),
        ("Documentation", "/documentation", active == "documentation"),
        ("Profile", "/profile", active == "profile"),
    ]
    chips = []
    for label, href, is_active in tab_links:
        cls = "tab active" if is_active else "tab"
        chips.append(f'<a class="{cls}" href="{html.escape(href)}">{html.escape(label)}</a>')
    return "".join(chips)


def page_shell(
    title: str,
    body: str,
    active: str,
    run_id: int | None = None,
    *,
    extra_head: str = "",
    extra_script: str = "",
    user_profile: dict[str, Any] | None = None,
) -> bytes:
    nav = render_nav(active, run_id=run_id, user_profile=user_profile)
    user_strip = render_user_strip(user_profile)
    doc = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <style>
    :root {{
      --bg: #f4f7fb;
      --panel: rgba(255, 255, 255, 0.86);
      --ink: #122033;
      --muted: #5d6f86;
      --accent: #0f8b8d;
      --accent-2: #ff7a59;
      --accent-3: #6759ff;
      --accent-soft: rgba(15, 139, 141, 0.12);
      --warm: #f3b640;
      --danger: #d63c6b;
      --success: #12a57a;
      --border: rgba(133, 150, 178, 0.24);
      --shadow: rgba(18, 32, 51, 0.12);
      --hero: linear-gradient(135deg, rgba(15, 139, 141, 0.18) 0%, rgba(103, 89, 255, 0.16) 45%, rgba(255, 122, 89, 0.16) 100%);
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      color: var(--ink);
      font-family: "Segoe UI", "Trebuchet MS", Tahoma, Geneva, Verdana, sans-serif;
      background:
        radial-gradient(circle at 8% 10%, rgba(15, 139, 141, 0.16), transparent 28%),
        radial-gradient(circle at 92% 12%, rgba(103, 89, 255, 0.18), transparent 28%),
        radial-gradient(circle at 82% 78%, rgba(255, 122, 89, 0.16), transparent 24%),
        linear-gradient(180deg, #eef3fb 0%, var(--bg) 100%);
    }}
    header {{
      position: sticky;
      top: 0;
      z-index: 20;
      padding: 22px 28px 16px;
      border-bottom: 1px solid var(--border);
      background: rgba(246, 250, 255, 0.78);
      backdrop-filter: blur(16px);
      box-shadow: 0 10px 36px rgba(18, 32, 51, 0.08);
    }}
    h1, h2, h3 {{ margin: 0 0 12px; }}
    p {{ margin: 0 0 12px; }}
    .brand {{ display: flex; justify-content: space-between; align-items: flex-end; gap: 20px; flex-wrap: wrap; }}
    .title {{ font-size: 32px; font-weight: 800; letter-spacing: 0.02em; color: #0c2440; }}
    .sub {{ color: var(--muted); max-width: 940px; font-size: 14px; line-height: 1.6; }}
    .nav-row {{ display: flex; justify-content: space-between; align-items: center; gap: 18px; flex-wrap: wrap; margin-top: 18px; }}
    nav {{ margin-top: 16px; display: flex; gap: 10px; flex-wrap: wrap; }}
    .tab {{
      text-decoration: none; color: var(--ink); padding: 11px 16px; border-radius: 999px;
      border: 1px solid var(--border); background: rgba(255,255,255,0.84);
      box-shadow: 0 6px 18px rgba(18, 32, 51, 0.05);
      transition: transform 0.12s ease, background 0.12s ease, box-shadow 0.12s ease;
    }}
    .tab:hover {{ transform: translateY(-1px); box-shadow: 0 10px 20px rgba(18, 32, 51, 0.08); }}
    .tab.active {{
      background: linear-gradient(135deg, var(--accent) 0%, var(--accent-3) 100%);
      border-color: transparent; color: white;
      box-shadow: 0 12px 22px rgba(15, 139, 141, 0.28);
    }}
    main {{ padding: 28px; display: grid; gap: 20px; }}
    .panel {{
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 24px;
      padding: 22px;
      box-shadow: 0 18px 48px var(--shadow);
      backdrop-filter: blur(14px);
    }}
    .panel h2 {{ margin-bottom: 8px; }}
    .muted {{ color: var(--muted); }}
    .warning {{ border-left: 4px solid var(--warm); padding-left: 12px; color: #895e0f; }}
    .pill {{
      display: inline-flex; align-items: center; gap: 6px; padding: 6px 11px; border-radius: 999px;
      background: linear-gradient(135deg, rgba(15,139,141,0.09) 0%, rgba(103,89,255,0.08) 100%);
      color: var(--accent); font-size: 12px; margin-right: 8px; margin-bottom: 8px; border: 1px solid rgba(15, 139, 141, 0.14);
    }}
    .status-running {{ color: #b46a00; font-weight: 700; }}
    .status-completed {{ color: var(--success); font-weight: 700; }}
    .status-failed {{ color: var(--danger); font-weight: 700; }}
    .two-col {{ display: grid; gap: 20px; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); }}
    .three-col {{ display: grid; gap: 18px; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); }}
    .metric-grid {{ display: grid; gap: 14px; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); }}
    .metric-card, .meta-card {{
      padding: 16px; border-radius: 20px;
      background: linear-gradient(145deg, rgba(255,255,255,0.94) 0%, rgba(248,251,255,0.92) 100%);
      border: 1px solid rgba(133, 150, 178, 0.18);
      box-shadow: 0 10px 24px rgba(18, 32, 51, 0.06);
    }}
    .metric-value {{ font-size: 24px; font-weight: 800; margin-bottom: 4px; color: #0c2440; }}
    .metric-label {{ color: var(--muted); font-size: 13px; }}
    .toolbar {{ display: flex; gap: 12px; flex-wrap: wrap; align-items: center; margin-top: 10px; }}
    form {{ display: grid; gap: 12px; }}
    select, textarea, input {{
      width: 100%; padding: 12px 14px; border-radius: 16px; border: 1px solid var(--border);
      background: rgba(255,255,255,0.94); color: var(--ink); font: inherit;
      box-shadow: inset 0 1px 2px rgba(18, 32, 51, 0.04);
    }}
    textarea {{ min-height: 420px; resize: vertical; font-family: Consolas, "Courier New", monospace; font-size: 13px; line-height: 1.45; }}
    button, .button-link {{
      appearance: none; border: none; border-radius: 16px; padding: 12px 18px; background: linear-gradient(135deg, var(--accent) 0%, var(--accent-3) 100%);
      color: white; cursor: pointer; text-decoration: none; display: inline-flex; align-items: center; justify-content: center;
      gap: 8px; font-weight: 700; box-shadow: 0 12px 22px rgba(15, 139, 141, 0.22);
    }}
    .button-link.secondary, button.secondary {{
      background: rgba(255,255,255,0.88); color: var(--ink); border: 1px solid var(--border);
      box-shadow: 0 10px 20px rgba(18, 32, 51, 0.06);
    }}
    .button-link.danger, button.danger {{ background: linear-gradient(135deg, var(--danger) 0%, #ff6b6b 100%); color: #fff; }}
    form.inline-form {{ display: inline-flex; gap: 0; margin: 0; }}
    table {{ width: 100%; border-collapse: collapse; }}
    th, td {{ text-align: left; padding: 10px 12px; border-bottom: 1px solid rgba(133, 150, 178, 0.18); vertical-align: top; }}
    th {{ position: sticky; top: 0; background: rgba(242, 247, 255, 0.98); z-index: 1; }}
    .table-scroll {{ overflow: auto; max-height: 70vh; border: 1px solid var(--border); border-radius: 18px; background: rgba(255,255,255,0.76); }}
    .artifact-grid {{ display: grid; gap: 18px; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); }}
    .artifact-card {{ border: 1px solid var(--border); border-radius: 20px; padding: 14px; background: rgba(255,255,255,0.92); box-shadow: 0 10px 22px rgba(18, 32, 51, 0.06); content-visibility: auto; contain-intrinsic-size: 340px 300px; }}
    img {{ max-width: 100%; border-radius: 16px; border: 1px solid var(--border); background: white; }}
    .artifact-card img {{ display: block; width: 100%; min-height: 160px; object-fit: contain; }}
    pre {{ margin: 0; white-space: pre-wrap; word-break: break-word; background: #111b20; color: #eff8fb; padding: 16px; border-radius: 16px; overflow: auto; }}
    code {{ background: rgba(15, 139, 141, 0.1); padding: 2px 5px; border-radius: 6px; }}
    .live-dot {{
      display: inline-block; width: 10px; height: 10px; border-radius: 999px; background: var(--success);
      box-shadow: 0 0 0 0 rgba(18, 165, 122, 0.55); animation: pulse 1.8s infinite; margin-right: 8px;
    }}
    @keyframes pulse {{
      0% {{ box-shadow: 0 0 0 0 rgba(18, 165, 122, 0.55); }}
      70% {{ box-shadow: 0 0 0 12px rgba(18, 165, 122, 0); }}
      100% {{ box-shadow: 0 0 0 0 rgba(18, 165, 122, 0); }}
    }}
    .chart-box {{ border: 1px solid var(--border); border-radius: 22px; padding: 12px; background: rgba(255,255,255,0.95); min-height: 270px; box-shadow: inset 0 1px 0 rgba(255,255,255,0.8); }}
    .chart-svg {{ width: 100%; height: 220px; overflow: visible; display: block; }}
    .chart-empty {{ color: var(--muted); padding: 30px 12px; }}
    .subtab-bar {{ display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 16px; }}
    .subtab-button {{
      appearance: none; border: 1px solid var(--border); background: rgba(255,255,255,0.86); color: var(--ink);
      padding: 10px 14px; border-radius: 999px; cursor: pointer; font: inherit; box-shadow: 0 8px 16px rgba(18, 32, 51, 0.05);
    }}
    .subtab-button.active {{ background: linear-gradient(135deg, var(--accent) 0%, var(--accent-2) 100%); color: #fff; border-color: transparent; }}
    .subtab-panel {{ display: none; }}
    .subtab-panel.active {{ display: block; }}
    .field-grid {{ display: grid; gap: 14px; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); }}
    .field-row {{
      padding: 14px; border-radius: 18px; border: 1px solid rgba(133, 150, 178, 0.18); background: rgba(255,255,255,0.86);
      display: grid; gap: 8px;
    }}
    .field-label {{ font-weight: 700; }}
    .field-path {{ color: var(--muted); font-size: 12px; }}
    .field-row textarea {{ min-height: 96px; }}
    .field-row.hidden {{ display: none; }}
    .panel-scroll-x {{ overflow-x: auto; padding-bottom: 6px; }}
    .tabular-tabs {{ display: flex; gap: 8px; flex-wrap: nowrap; overflow-x: auto; padding-bottom: 8px; }}
    .tabular-tabs .subtab-button {{ white-space: nowrap; }}
    .table-meta {{ display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 10px; }}
    .mini-note {{ color: var(--muted); font-size: 12px; }}
    .search-input {{ max-width: 420px; }}
    #map {{ width: 100%; height: 560px; border-radius: 22px; border: 1px solid var(--border); overflow: hidden; box-shadow: 0 16px 34px rgba(18, 32, 51, 0.08); }}
    a {{ color: var(--accent); text-decoration: none; }}
    a:hover {{ text-decoration: underline; }}
    .doc-hero {{ margin-bottom: 18px; background: var(--hero); padding: 22px; border-radius: 24px; }}
    .doc-grid {{ display: grid; gap: 18px; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); }}
    .doc-card {{ background: rgba(255,255,255,0.92); border: 1px solid rgba(133, 150, 178, 0.18); border-radius: 22px; padding: 18px; box-shadow: 0 14px 30px var(--shadow); }}
    .doc-card-wide {{ margin-bottom: 18px; }}
    .doc-card-tight {{ padding-top: 14px; }}
    .doc-card.hidden, .doc-callout.hidden, .subtab-panel.hidden {{ display: none !important; }}
    .doc-markdown h1, .doc-markdown h2, .doc-markdown h3, .doc-markdown h4 {{ margin-top: 0; margin-bottom: 12px; }}
    .doc-markdown p {{ margin-bottom: 12px; line-height: 1.65; }}
    .doc-markdown ul, .doc-markdown ol {{ margin: 0 0 14px 22px; padding: 0; }}
    .doc-markdown li {{ margin-bottom: 8px; line-height: 1.55; }}
    .doc-table th {{ white-space: nowrap; }}
    .doc-callout {{ padding: 16px 18px; border-radius: 20px; border: 1px solid rgba(15, 139, 141, 0.18); background: linear-gradient(180deg, rgba(241,250,255,0.98) 0%, rgba(235,247,255,0.92) 100%); margin-bottom: 16px; }}
    .doc-ref {{ display: inline-block; padding: 2px 8px; border-radius: 999px; background: #eef3f5; color: var(--accent); font-size: 12px; }}
    .doc-code-wrap {{ margin: 12px 0 14px; }}
    .doc-code-label {{ display: inline-flex; margin-bottom: 8px; padding: 4px 10px; border-radius: 999px; background: #e9f1f2; color: var(--accent); font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; }}
    .doc-formula {{ border: 1px solid #d8e4e6; border-radius: 16px; padding: 12px; background: #f8fcfc; margin-bottom: 12px; }}
    .doc-formula-title {{ font-weight: 700; margin-bottom: 8px; color: var(--accent); }}
    .flow-svg-wrap {{ overflow-x: auto; border: 1px solid var(--border); border-radius: 18px; background: linear-gradient(180deg, #fbfdfd 0%, #f4f8f8 100%); padding: 10px; }}
    .flow-svg {{ width: 100%; min-width: 780px; height: auto; display: block; }}
    details.uml-source summary {{ cursor: pointer; font-weight: 700; margin-bottom: 8px; }}
    .chain-layout {{ display: grid; gap: 16px; }}
    .chain-nav {{ padding-bottom: 2px; }}
    .chain-detail {{ display: grid; gap: 16px; }}
    .login-shell {{ min-height: calc(100vh - 180px); display: grid; place-items: center; }}
    .login-card {{ width: min(980px, 100%); display: grid; gap: 20px; grid-template-columns: minmax(280px, 1.1fr) minmax(320px, 0.9fr); }}
    .login-hero {{
      padding: 26px; border-radius: 28px; background: var(--hero); border: 1px solid rgba(255,255,255,0.32);
      box-shadow: 0 22px 52px rgba(18, 32, 51, 0.12);
    }}
    .login-form-panel {{ padding: 26px; border-radius: 28px; background: rgba(255,255,255,0.95); border: 1px solid var(--border); box-shadow: 0 22px 52px rgba(18, 32, 51, 0.12); }}
    .profile-chip {{
      display: inline-flex; align-items: center; gap: 10px; text-decoration: none; color: var(--ink);
      padding: 8px 12px; border-radius: 999px; background: rgba(255,255,255,0.84); border: 1px solid var(--border);
      box-shadow: 0 10px 20px rgba(18, 32, 51, 0.06);
    }}
    .profile-avatar {{
      width: 34px; height: 34px; border-radius: 999px; display: inline-grid; place-items: center; font-weight: 800; color: white;
      background: linear-gradient(135deg, var(--accent) 0%, var(--accent-3) 100%);
    }}
    .profile-role {{ display: block; font-size: 12px; color: var(--muted); font-weight: 500; }}
    .user-strip {{ display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }}
    .hero-badges {{ display: flex; gap: 10px; flex-wrap: wrap; margin-top: 14px; }}
    .glass-list {{ display: grid; gap: 12px; margin-top: 18px; }}
    .glass-item {{ padding: 14px 16px; border-radius: 18px; background: rgba(255,255,255,0.58); border: 1px solid rgba(255,255,255,0.38); }}
    @media (max-width: 820px) {{
      .login-card {{ grid-template-columns: 1fr; }}
      .nav-row {{ align-items: flex-start; }}
    }}
  </style>
  {extra_head}
</head>
<body>
  <header>
    <div class="brand">
      <div>
        <div class="title">6G LLS Real-Time Console</div>
        <div class="sub">Direct MySQL-backed monitoring for MATLAB LLS runs. No Kafka is used here: MATLAB writes logs and artifacts straight into MySQL, and the browser polls live JSON endpoints to update tables, images, analytics, and the map.</div>
      </div>
    </div>
    <div class="nav-row">
      <nav>{nav}</nav>
      {user_strip}
    </div>
  </header>
  <main>{body}</main>
  {extra_script}
</body>
</html>
"""
    return doc.encode("utf-8")


def build_login_page(message: str = "", next_url: str = "/home") -> bytes:
    if auth_mode_open():
        return page_shell(
            "Open Access",
            '<section class="panel"><h2>Open Intranet Access</h2><p class="muted">The dashboard is configured for open intranet access. Username and password prompts are disabled.</p><div class="toolbar"><a class="button-link" href="/home">Open Dashboard</a></div></section>',
            active="login",
            user_profile=dict(OPEN_ACCESS_PROFILE),
        )
    next_url = next_url or "/home"
    safe_next = html.escape(next_url, quote=True)
    message_html = f'<p class="warning">{html.escape(message)}</p>' if message else ""
    body = f"""
    <section class="login-shell">
      <div class="login-card">
        <div class="login-hero">
          <span class="pill">Secure Intranet Access</span>
          <h2>6G LLS Operations Console</h2>
          <p class="muted">Sign in to launch runs, monitor live metrics, browse database-backed results, inspect realtime analytics, and read the detailed code-grounded LLS documentation.</p>
          <div class="hero-badges">
            <span class="pill">Realtime MySQL updates</span>
            <span class="pill">Interactive analytics</span>
            <span class="pill">Live map + logs</span>
            <span class="pill">Code-grounded documentation</span>
          </div>
        </div>
        <div class="login-form-panel">
          <h2>Login</h2>
          <p class="muted">Use your configured intranet operator credentials to enter the dashboard.</p>
          {message_html}
          <form method="post" action="/login">
            <input type="hidden" name="next" value="{safe_next}">
            <label for="username"><strong>Username</strong></label>
            <input id="username" name="username" type="text" autocomplete="username" placeholder="admin">
            <label for="password"><strong>Password</strong></label>
            <input id="password" name="password" type="password" autocomplete="current-password" placeholder="admin">
            <div class="toolbar" style="margin-top:8px;">
              <button type="submit">Enter Dashboard</button>
            </div>
          </form>
        </div>
      </div>
    </section>
    """
    return page_shell("Login", body, active="login", user_profile=None)


def build_profile_page(user_profile: dict[str, Any]) -> bytes:
    display_name = str(user_profile.get("display_name") or user_profile.get("username") or "")
    username = str(user_profile.get("username") or "")
    role = str(user_profile.get("role") or "User")
    theme = str(user_profile.get("theme") or "default")
    bio = str(user_profile.get("bio") or "")
    initials = "".join(part[:1].upper() for part in display_name.split()[:2]) or username[:1].upper()
    body = f"""
    <section class="panel">
      <div class="toolbar" style="justify-content:space-between;align-items:flex-start;">
        <div style="display:flex;gap:16px;align-items:center;flex-wrap:wrap;">
          <span class="profile-avatar" style="width:56px;height:56px;font-size:20px;">{html.escape(initials)}</span>
          <div>
            <h2 style="margin-bottom:4px;">{html.escape(display_name)}</h2>
            <div class="pill">{html.escape(role)}</div>
            <div class="mini-note">Username: <code>{html.escape(username)}</code> | Theme: <code>{html.escape(theme)}</code></div>
          </div>
        </div>
        <form method="post" action="/logout" class="inline-form">
          <button type="submit" class="secondary">Logout</button>
        </form>
      </div>
      <p class="muted" style="margin-top:14px;">{html.escape(bio)}</p>
    </section>
    <div class="three-col">
      <section class="panel">
        <h3>Quick Access</h3>
        <div class="toolbar">
          <a class="button-link" href="/home">Open Home</a>
          <a class="button-link secondary" href="/runs">Open Runs</a>
          <a class="button-link secondary" href="/documentation">Open Documentation</a>
        </div>
      </section>
      <section class="panel">
        <h3>Session Scope</h3>
        <ul>
          <li>Launch and monitor LLS runs from the browser.</li>
          <li>Inspect realtime DB tables, analytics, images, logs, and maps.</li>
          <li>Read the code-grounded implementation documentation.</li>
        </ul>
      </section>
      <section class="panel">
        <h3>Access Model</h3>
        <p class="muted">This intranet dashboard no longer publishes or requires username/password hints in the UI. Authentication mode is <code>{html.escape(DEFAULT_DASHBOARD_AUTH_MODE)}</code>.</p>
      </section>
    </div>
    """
    return page_shell("Profile", body, active="profile", user_profile=user_profile)


PRODUCT_PAGE_ROUTES: dict[str, str] = {
    "/": "home",
    "/home": "home",
    "/reports": "reports",
    "/architecture": "architecture",
    "/documentation": "architecture",
    "/run-control": "run_control",
    "/run_control": "run_control",
    "/scenario": "scenario",
    "/geometry": "geometry",
    "/waveform": "waveform",
    "/traffic": "traffic",
    "/mac-scheduler": "mac_scheduler",
    "/mac_scheduler": "mac_scheduler",
    "/l1-phy": "l1_phy",
    "/l1_phy": "l1_phy",
    "/antenna-air": "antenna_air",
    "/antenna_air": "antenna_air",
    "/realtime": "realtime",
    "/runs": "runs",
    "/recent-runs": "runs",
    "/previous-run": "previous_runs",
    "/previous-runs": "previous_runs",
    "/analytics": "analytics",
    "/artifacts": "artifacts",
    "/parameters": "parameters",
    "/parameter-catalog": "parameters",
    "/parameter_catalog": "parameters",
    "/compare": "compare",
    "/compare-runs": "compare",
    "/compare_runs": "compare",
    "/result": "realtime",
    "/map": "geometry",
    "/logs": "realtime",
    "/outputs": "artifacts",
    "/tables": "artifacts",
    "/images": "artifacts",
}
PRODUCT_PAGE_ROUTES.update(output_contract.route_map("reports"))
PRODUCT_PAGE_ROUTES.update(output_contract.route_map("analytics"))

PRODUCT_NAV = [
    ("home", "Home", "/home"),
    ("run_control", "Run Control", "/run-control"),
    ("scenario", "Scenario", "/scenario"),
    ("geometry", "Geometry", "/geometry"),
    ("waveform", "Waveform", "/waveform"),
    ("traffic", "Traffic", "/traffic"),
    ("mac_scheduler", "MAC / Scheduler", "/mac-scheduler"),
    ("l1_phy", "L1 / PHY", "/l1-phy"),
    ("antenna_air", "Antenna / Air Interface / Channel", "/antenna-air"),
    ("realtime", "Real-Time Data", "/realtime"),
    ("reports", "Reports", "/reports"),
    ("analytics", "Analytics", "/analytics"),
    ("runs", "Recent Runs", "/runs"),
    ("previous_runs", "Previous Runs", "/previous-runs"),
    ("artifacts", "Artifact Explorer", "/artifacts"),
    ("parameters", "Parameter Catalog", "/parameter-catalog"),
    ("compare", "Compare Runs", "/compare-runs"),
]

PRODUCT_CONFIG_MODEL_PAGES = {
    "run_control",
    "scenario",
    "geometry",
    "waveform",
    "traffic",
    "mac_scheduler",
    "l1_phy",
    "antenna_air",
    "parameters",
}

PRODUCT_DOMAIN_FILTERS: dict[str, dict[str, Any]] = {
    "run_control": {"title": "Run Control", "paths": ["run_control.", "simulation.", "seeds.", "output.", "logging_outputs.", "display_outputs."]},
    "scenario": {"title": "Scenario", "paths": ["scenario.", "meta.", "simulation.", "run_control.", "output."]},
    "geometry": {"title": "Geometry", "paths": ["deployment_topology.", "mobility.", "users.", "scenario.layout", "scenario.mobility", "system.handover.", "system.measurement."]},
    "waveform": {"title": "Waveform", "paths": ["frequency.", "global_radio_scope.", "frame.", "frame_timing.", "waveform.", "resource_grid.", "bandwidth_operation.", "modulation_and_mapping.", "channel_coding."]},
    "traffic": {"title": "Traffic", "paths": ["traffic.", "qos.", "application.", "users.", "system.queue", "system.queuemaxbits"]},
    "mac_scheduler": {"title": "MAC / Scheduler", "paths": ["system.scheduler.", "mac.", "scheduler.", "harq.", "link_adaptation.", "control_gating."]},
    "l1_phy": {"title": "L1 / PHY Explorer", "paths": ["phy.", "pdcch.", "pucch.", "prach.", "random_access.", "reference_signals.", "mimo.", "mimo_and_beam_management.", "receiver.", "control.", "channel_coding.", "waveform."]},
    "antenna_air": {"title": "Antenna / Air Interface / Channel", "paths": ["antenna_and_array.", "channels.", "channel_model.", "interference.", "power_and_rf_frontend.", "rf.", "impairments.", "energy_efficiency."]},
}


def product_architecture_blocks() -> list[dict[str, Any]]:
    return [
        {"id": "run_control", "title": "Run Control", "route": "/run-control", "domain": "run_control", "summary": "Execution mode, slot budget, replay seeds, checkpointing, logging, output export, and strict truth policy.", "params": ["run_control", "simulation", "seeds", "output"]},
        {"id": "scenario", "title": "Scenario", "route": "/scenario", "domain": "scenario", "summary": "Study identity, mode, seeds, validation policy, runtime budget, and output contract.", "params": ["scenario", "run_control", "simulation", "output"]},
        {"id": "geometry", "title": "Geometry", "route": "/geometry", "domain": "geometry", "summary": "Sites, sectors, TRPs, UE placement, hotspots, serving-cell state, and mobility.", "params": ["deployment_topology", "mobility", "users"]},
        {"id": "waveform", "title": "Waveform", "route": "/waveform", "domain": "waveform", "summary": "Carrier, numerology, grid, TDD, OFDM, coding, modulation, and impairments.", "params": ["frequency", "frame", "waveform", "channel_coding"]},
        {"id": "traffic", "title": "Traffic", "route": "/traffic", "domain": "traffic", "summary": "Traffic mix, queues, packet model, QoS, offered load, latency, and flow ownership.", "params": ["traffic", "qos", "users"]},
        {"id": "mac_scheduler", "title": "MAC / Scheduler", "route": "/mac-scheduler", "domain": "mac_scheduler", "summary": "Eligibility, grant planning, PRB allocation, MCS/TBS, HARQ, OLLA, and fairness.", "params": ["system.scheduler", "harq", "link_adaptation", "control_gating"]},
        {"id": "control_access", "title": "Control / Access", "route": "/l1-phy#control", "domain": "l1_phy", "summary": "PBCH, PRACH, PDCCH, PUCCH, SRS, TRS, acquisition, access, and scheduling gates.", "params": ["pdcch", "pucch", "prach", "control_gating", "reference_signals"]},
        {"id": "l1_phy", "title": "L1 / PHY", "route": "/l1-phy", "domain": "l1_phy", "summary": "DL chain, UL chain, control chain, reference signals, channel estimation, MIMO, and coding.", "params": ["phy", "reference_signals", "mimo", "receiver"]},
        {"id": "antenna_air", "title": "Antenna / Air Interface / Channel", "route": "/antenna-air", "domain": "antenna_air", "summary": "BS/UE arrays, propagation, fading profile, interference, pathloss, O2I, and beam truth.", "params": ["antenna_and_array", "channels", "channel_model", "interference"]},
        {"id": "realtime", "title": "Real-time Data", "route": "/realtime", "domain": "realtime", "summary": "Run status, frame/slot progression, active UEs/cells, KPIs, grants, state, warnings, and logs.", "params": []},
        {"id": "analytics", "title": "Analytics", "route": "/analytics", "domain": "analytics", "summary": "KPI overview, PHY/MAC/control/channel/beam/latency/energy dashboards, and truth coverage.", "params": []},
    ]


def product_phy_families() -> list[dict[str, Any]]:
    def b(block_id: str, name: str, group: str, purpose: str, params: list[str], runtime: list[str], artifacts: list[str], stages: list[str]) -> dict[str, Any]:
        return {"id": block_id, "name": name, "group": group, "purpose": purpose, "params": params, "runtime": runtime, "artifacts": artifacts, "tests": ["testLLS_DL", "testLLS_UL", "testLLS_ReferencePoints"], "stages": stages, "truth": "Canonical DB artifacts first. Missing outputs stay unavailable and are not replaced by proxy rows."}

    return [
        {"id": "dl_control", "title": "DL Control", "summary": "PDCCH, SSB/PBCH, and CSI-RS chains.", "blocks": [
            b("pdcch", "PDCCH", "DL Control", "DCI payload, CRC, polar coding, scrambling, modulation, RE mapping, and grant-coupled control evidence.", ["pdcch.enabled", "pdcch.aggregation_levels", "control.pdcch_enabled", "reference_signals.pdcch_dmrs.enabled"], ["ControlDecodeOk", "GrantControlState", "AggregationLevel"], ["air_interface/csv/pdcch_trials.csv", "reports/csv/live_control_gating_summary.csv"], ["Payload", "CRC", "Polar", "Scramble", "Modulate", "RE map", "DL IQ"]),
            b("ssb_pbch", "SSB / PBCH", "DL Control", "Synchronization burst and PBCH path with payload coding, PBCH DMRS, cell search, and acquisition gating.", ["signals_and_channels_common.ssb.enable_flag", "signals_and_channels_common.pbch.enable_flag", "reference_signals.pbch_enabled"], ["CellAcquisitionState", "PBCHFailureCount", "LastSuccessfulPBCHSlot"], ["air_interface/csv/pbch_trials.csv", "reports/csv/live_control_gating_state.csv"], ["SSB payload", "Interleave", "CRC", "Polar", "Scramble", "Modulate", "PBCH DMRS", "RE map"]),
            b("csirs", "CSI-RS", "Reference Signal", "CSI-RS resource mapping for measurement, beam/CSI observation, and CSI feedback lineage.", ["reference_signals.nzp_csi_rs.enabled", "reference_signals.csi_rs_enabled", "csi_acquisition_and_reporting.channel_state_information_mode"], ["CSI_RS_MeasurementAge", "BeamformedFlag", "CSIValidityState"], ["reports/csv/live_csi_feedback_stats.csv", "reports/csv/live_csirs_stats.csv"], ["CSI-RS payload", "Scramble", "Modulate", "RE map", "DL IQ"]),
        ]},
        {"id": "dl_data", "title": "DL Data", "summary": "PDSCH, DL chain, and downlink MIMO.", "blocks": [
            b("pdsch", "PDSCH", "DL Data", "TB CRC, CB CRC, LDPC, rate matching, scrambling, modulation, layer mapping, precoding, DMRS/PTRS, RE mapping, OFDM, and decode truth.", ["channel_coding.data_channel_family", "mimo.n_layers", "mimo.precoder_type", "reference_signals.pdsch_dmrs.num_ports"], ["TBSize_bits", "RateMatchedBits", "DMRSRECount", "PTRSRECount", "AppliedPrecoderPMI", "CRCPass"], ["air_interface/csv/dl_pdsch_trials.csv", "reports/csv/live_error_rate_summary.csv"], ["PDSCH payload", "TB CRC", "CB CRC", "LDPC", "Rate match", "Scramble", "Modulate", "Layer map", "Precode", "RE map"]),
            b("dl_chain", "DL Chain", "DL Data", "Full downlink path from MAC payload and control state through DL IQ samples and receiver evidence.", ["waveform.dl_waveform", "frequency.bandwidth_hz", "frame.scs_khz", "simulation.link_direction"], ["DLTrialsReady", "EffectiveDLTrialCount", "Goodput_Mbps"], ["air_interface/csv/dl_pdsch_trials.csv", "reports/csv/live_tx_rx_stage_trace.csv"], ["MAC payload", "Scheduler grant", "PDCCH", "PDSCH TX", "Channel", "PDSCH RX", "CRC", "DB artifact"]),
            b("dl_beam_mimo", "Beamforming / Precoding / MIMO", "MIMO", "PDSCH beam-weight generation, SRS channel estimate reuse, ZF/PMI selection, layer mapping, and DL beam forming.", ["mimo_and_beam_management.beam_sweeping", "mimo_and_beam_management.rank_set", "antenna_and_array.bs_num_antenna_elements"], ["RequestedBeamIndexSet", "AppliedBeamIndexSet", "RequestedPrecoderPMI", "AppliedPrecoderPMI", "BeamformingApplied"], ["reports/csv/beamforming_runtime_evidence.csv", "reports/csv/beam_stability_analytics_table.csv"], ["SRS estimate", "User buffer", "ZF weights", "DL beam weights", "MxN beamforming", "RE map", "IFFT"]),
        ]},
        {"id": "ul_control", "title": "UL Control", "summary": "PUCCH formats 0, 1, 2, 3, 4 and PRACH access.", "blocks": [
            b("pucch0", "PUCCH Format 0", "UL Control", "Low-PAPR sequence generation and format-0 detection for SR/ACK/NACK style control.", ["pucch.enabled", "pucch.formats_supported", "control.pucch_enabled"], ["RequestedFormat", "ResolvedFormat", "PUCCHDecodeOk", "UCIContentMatch"], ["air_interface/csv/pucch_trials.csv"], ["UL IQ", "Sequence low PAPR", "Format 0 detector", "MAC payload"]),
            b("pucch1", "PUCCH Format 1", "UL Control", "DMRS-assisted despreading, DTX detection, demodulation, and MAC payload delivery.", ["pucch.enabled", "pucch.formats_supported", "reference_signals.pucch_dmrs.enabled"], ["DTXFlag", "DecisionMetric", "UCIContentMatch"], ["air_interface/csv/pucch_trials.csv"], ["UL IQ", "DMRS", "Low-PAPR sequence", "Despread", "DTX", "Demodulate", "MAC payload"]),
            b("pucch234", "PUCCH Formats 2/3/4", "UL Control", "Coded UCI chain with channel estimation, equalization, demapping, descrambling, rate de-matching, polar/Reed-Muller decode, and CRC.", ["pucch.enabled", "pucch.formats_supported", "channel_coding.control_channel_family"], ["CodeBlockCount", "CRCApplicable", "CRCPass", "DecisionMetric"], ["air_interface/csv/pucch_trials.csv"], ["UL IQ", "PUCCH DMRS", "Channel estimate", "Equalize", "Demap", "Descramble", "Rate recover", "Polar decode", "CRC"]),
            b("prach", "PRACH", "UL Control", "Zadoff-Chu preamble detection with correlation, IFFT, normalization, power combining, noise floor estimate, and peak search.", ["prach.enabled", "random_access.enabled", "prach.sequence_family", "random_access.prach_format"], ["AccessState", "PRACHFailureCount", "CorrelationPeak", "TAEstimate"], ["air_interface/csv/prach_trials.csv", "reports/csv/live_control_gating_state.csv"], ["PRACH IQ", "ZC sequence", "Correlation", "IFFT", "Normalize", "Power combine", "Noise floor", "Peak search", "MAC payload"]),
        ]},
        {"id": "ul_data", "title": "UL Data", "summary": "PUSCH, UL chain, and uplink spatial filtering.", "blocks": [
            b("pusch", "PUSCH", "UL Data", "DMRS generation, MMSE channel estimation, equalization, RE demapping, layer demap, demodulation, descrambling, HARQ combining, LDPC decode, and CRC.", ["waveform.ul_waveform", "reference_signals.pusch_dmrs.num_ports", "mimo.n_layers", "receiver.use_ideal_timing_sync"], ["MeasuredTrialSINR_dB", "NMSE_dB", "EVM_rms", "DecoderIterations", "CRCPass"], ["air_interface/csv/ul_pusch_trials.csv", "reports/csv/live_tx_rx_stage_trace.csv"], ["UL IQ", "DMRS", "MMSE CE", "Equalize", "RE demap", "Layer demap", "Demodulate", "Descramble", "HARQ combine", "LDPC", "CRC"]),
            b("ul_chain", "UL Chain", "UL Data", "Full uplink path from UE payload through UL IQ samples, channel, receiver, decoder, and MAC payload.", ["simulation.link_direction", "waveform.ul_waveform", "traffic.flowdirection", "control_gating.srs_required"], ["ULTrialsReady", "EffectiveULTrialCount", "ULGoodput_Mbps"], ["air_interface/csv/ul_pusch_trials.csv", "packet_flow/csv/live_ul_scheduler_grants.csv"], ["MAC payload", "UL grant", "PUSCH TX", "UL channel", "PUSCH RX", "Decoder", "CRC", "DB artifact"]),
            b("ul_beam_mimo", "UL Spatial Filter / Antenna Combining", "MIMO", "UL beam-weight generation from SRS estimate, user buffer selection, ZF beam generation, spatial filtering, and antenna combining.", ["reference_signals.srs.num_ports", "mimo.n_layers", "antenna_and_array.ue_num_antenna_elements"], ["ULBeamWeightsActive", "SpatialFilterApplied", "InterfererBeamformingAppliedCount"], ["reports/csv/beamforming_runtime_evidence.csv", "reports/csv/channel_array_consistency.csv"], ["FFT", "RE map", "UL spatial filter", "SRS estimate", "User buffer", "ZF weights", "UL beam weights", "Antenna combine"]),
        ]},
        {"id": "reference", "title": "Reference Signal Chain", "summary": "SRS, TRS, CSI feedback, rank/PMI/RI/CRI, and tracking evidence.", "blocks": [
            b("srs", "SRS", "Reference Signal", "Sounding reference signal generation and channel estimation for UL CSI, beam/rank support, and scheduler freshness.", ["reference_signals.srs.enabled", "reference_signals.srs.num_ports", "reference_signals.srs.periodicity", "control_gating.srs_required"], ["SRSValidityState", "SRSAgeSlots", "UL_CSI_Quality"], ["air_interface/csv/srs_trials.csv", "reports/csv/live_control_gating_state.csv"], ["SRS IQ", "SRS sequence", "MMSE channel estimate", "MAC payload"]),
            b("trs", "TRS", "Reference Signal", "Tracking reference signal observation, runtime tracking state, Doppler/timing evidence, and optional scheduler eligibility influence.", ["reference_signals.trs.enabled", "reference_signals.tracking_rs.enabled", "control_gating.trs_required"], ["TRSValidityState", "TRSAgeSlots", "EstimatedDopplerHz", "TrackingFailureProbability"], ["air_interface/csv/trs_trials.csv", "reports/csv/timing_positioning_runtime_evidence.csv"], ["TRS", "Observe", "Tracking state", "Doppler", "Timing", "Eligibility"]),
            b("csi_feedback", "CSI Feedback", "Reference Signal", "CQI, PMI, RI, and CRI feedback construction, age/staleness handling, and scheduler consumption.", ["csi_acquisition_and_reporting.cqi_policy", "csi_acquisition_and_reporting.pmi_policy", "csi_acquisition_and_reporting.ri_policy", "reference_signals.csi_feedback_mode"], ["WidebandCQI", "PMI", "RI", "CRI", "CSIValidityState"], ["reports/csv/live_csi_feedback_stats.csv", "reports/csv/cqi_pmi_ri_time.csv"], ["CSI-RS", "Measure", "CQI", "PMI", "RI", "CRI", "Feedback", "Scheduler"]),
        ]},
    ]


def product_field_domain(path: str) -> str:
    normalized = str(path or "").lower()
    for domain, spec in PRODUCT_DOMAIN_FILTERS.items():
        for prefix in spec.get("paths", []):
            prefix_text = str(prefix).lower()
            if normalized.startswith(prefix_text) or prefix_text in normalized:
                return domain
    return "scenario"


def product_field_records(config_payload: dict[str, Any]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for field in flatten_config_fields(config_payload):
        path = str(field.get("path") or "")
        value = field.get("value")
        domain = product_field_domain(path)
        records.append(
            {
                "path": path,
                "label": field.get("label") or resolve_field_label(path),
                "domain": domain,
                "domain_label": PRODUCT_DOMAIN_FILTERS.get(domain, {}).get("title", humanize_key(domain)),
                "kind": field.get("kind") or "text",
                "value": value,
                "current_value": value,
                "requested_value": value,
                "resolved_value": value,
                "applied_value": "unavailable until runtime evidence is published",
                "measured_value": "unavailable until runtime evidence is published",
                "source": "browser + YAML resolved config",
                "owner": field.get("group_label") or humanize_key(path.split(".")[0] if path else "scenario"),
                "role": field.get("support_state") or "active",
                "support_note": field.get("support_note") or "",
                "options": field.get("options"),
                "search": field.get("search_text") or f"{path} {field.get('label') or ''}",
            }
        )
    records.sort(key=lambda item: (str(item["domain"]), str(item["path"])))
    return records


def product_field_count(config_payload: Any) -> int:
    if isinstance(config_payload, dict):
        if not config_payload:
            return 1
        return sum(product_field_count(value) for value in config_payload.values())
    if isinstance(config_payload, list):
        return len(config_payload) if config_payload else 1
    return 1


def product_page_needs_config_model(page_id: str) -> bool:
    return str(page_id or "").strip().lower() in PRODUCT_CONFIG_MODEL_PAGES


def product_config_overview(config_payload: dict[str, Any], scenario_name: str, mode: str) -> dict[str, Any]:
    contract = scenario_launch_contract(config_payload, scenario_name)
    return {
        "scenario": scenario_name,
        "mode": mode,
        "runner_profile": path_get(
            config_payload,
            "scenario.runner_profile",
            path_get(config_payload, "output.profile", "unavailable"),
        ),
        "carrier_hz": path_get(
            config_payload,
            "frequency.center_frequency_hz",
            path_get(config_payload, "global_radio_scope.carrier_frequency_hz", "unavailable"),
        ),
        "bandwidth_hz": path_get(
            config_payload,
            "frequency.bandwidth_hz",
            path_get(config_payload, "global_radio_scope.channel_bandwidth_hz", "unavailable"),
        ),
        "channel_profile": path_get(
            config_payload,
            "channels.profile",
            path_get(config_payload, "channel_model.scenario_label", "unavailable"),
        ),
        "num_ues": path_get(
            config_payload,
            "users.n_users",
            path_get(config_payload, "deployment_topology.num_ues", "unavailable"),
        ),
        "total_slots": path_get(
            config_payload,
            "run_control.total_slots",
            path_get(config_payload, "simulation.n_slots", "unavailable"),
        ),
        "launch_contract": contract["launch_contract"],
        "launch_allowed": contract["launch_allowed"],
        "launch_reason": contract["launch_reason"],
        "presentation_label": contract["presentation_label"],
        "claims_waveform_truth": contract["claims_waveform_truth"],
        "scenario_id": contract["scenario_id"],
    }


def product_backend_status() -> dict[str, Any]:
    status = {
        "matlab_exe": str(MATLAB_EXE),
        "matlab_r2023b_only": True,
        "matlab_available": MATLAB_EXE.is_file(),
        "mysql_host": MYSQL_HOST,
        "mysql_port": MYSQL_PORT,
        "mysql_database": MYSQL_DATABASE,
        "mysql_status": "unavailable",
        "mysql_reason": "",
        "latest_run_id": None,
        "preferred_live_run_id": None,
        "preferred_analysis_run_id": None,
    }
    try:
        with db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
        status["mysql_status"] = "connected"
        status["latest_run_id"] = latest_run_id()
        status["preferred_live_run_id"] = preferred_live_run_id()
        status["preferred_analysis_run_id"] = preferred_analysis_run_id()
    except Exception as exc:
        status["mysql_reason"] = str(exc)
    return status


def product_frontend_style() -> str:
    return """
<style>
:root{--bg:#f6f8f5;--panel:#fff;--ink:#17201a;--muted:#607064;--line:#dce5df;--strong:#b7c8bf;--blue:#087f5b;--teal:#2f6690;--green:#1d7f45;--red:#b42336;--amber:#8a6a00;--shadow:0 12px 28px rgba(28,43,34,.08);--mono:Consolas,"Courier New",monospace;--sans:"Segoe UI",Arial,sans-serif}
*{box-sizing:border-box}html,body{min-height:100%}body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans)}a{color:inherit;text-decoration:none}
.app-shell{display:grid;grid-template-columns:280px minmax(0,1fr);gap:16px;padding:16px;min-height:100vh}.sidebar,.config-dock,.product-header,.panel,.tile,.table-wrap,.map-box{background:var(--panel);border:1px solid var(--line);border-radius:8px;box-shadow:var(--shadow)}.sidebar{position:sticky;top:16px;height:calc(100vh - 32px);overflow:auto;overscroll-behavior:contain;scrollbar-gutter:stable both-edges;padding:16px}.config-dock{padding:16px}.workspace{display:grid;gap:16px;align-content:start;min-width:0}.brand{display:flex;gap:12px;align-items:center;margin-bottom:18px}.brand-mark{width:44px;height:44px;border-radius:8px;display:grid;place-items:center;background:#e7f5ef;color:var(--blue);font-weight:800;border:1px solid #b8dfd0}.brand h1{font-size:18px;margin:0 0 4px;line-height:1.2}.brand p,.subtle{margin:0;color:var(--muted);line-height:1.5}.field-label,.eyebrow{display:block;margin:0 0 8px;color:var(--muted);font-size:12px;font-weight:700}
.mode-row{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}.nav-list{display:grid;gap:6px;margin-top:18px}.nav-item{padding:10px 12px;border:1px solid transparent;border-radius:8px;color:#2f4438;font-weight:650}.nav-item.active,.nav-item:hover{border-color:#a6d6c3;background:#edf8f3;color:var(--blue)}
button,.button-link,select,input,textarea{font:inherit;border-radius:8px}button,.button-link{border:1px solid var(--strong);background:#fff;padding:10px 12px;color:var(--ink);font-weight:700;cursor:pointer}button.primary,.mode-button.active,.button-link.primary{background:var(--blue);color:#fff;border-color:var(--blue)}button:disabled{opacity:.55;cursor:not-allowed}select,input,textarea{border:1px solid var(--strong);background:#fff;padding:10px 12px;color:var(--ink);width:100%}
.product-header{padding:16px;display:grid;grid-template-columns:minmax(0,1fr)auto;gap:16px;align-items:start}.product-header h2{margin:0 0 6px;font-size:26px}.top-actions{display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end;max-width:760px}.top-actions select{width:260px}#runForm{display:inline}.message{padding:12px 14px;background:#fff8e8;color:#6b4500;border:1px solid #e9c77d;border-radius:8px}.hidden{display:none!important}.grid{display:grid;gap:12px}.grid.two{grid-template-columns:repeat(2,minmax(0,1fr))}.grid.three{grid-template-columns:repeat(3,minmax(0,1fr))}.grid.four{grid-template-columns:repeat(4,minmax(0,1fr))}.panel{padding:16px}.panel h3,.tile h3{margin:0 0 8px;font-size:18px}.tile{padding:14px;min-width:0}.tile h4{margin:0 0 6px;font-size:16px}.tile p{margin:0;color:var(--muted);line-height:1.45}.metric{border-left:4px solid var(--teal)}.metric .value{font-size:22px;font-weight:800;margin-top:4px}
.workflow{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:10px}.workflow .tile{cursor:pointer;min-height:148px}.workflow .tile:hover,.block-card:hover{border-color:var(--blue)}.badge{display:inline-flex;align-items:center;border:1px solid var(--strong);border-radius:8px;padding:4px 8px;font-size:12px;color:var(--muted);background:#f7f9fc;margin:3px 4px 3px 0}.badge.good{color:var(--green);border-color:#a9d5b7;background:#f2fbf5}.badge.warn{color:var(--amber);border-color:#e3c78d;background:#fff8e8}.badge.bad{color:var(--red);border-color:#e3a8b2;background:#fff3f5}
.form-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.param-editor{display:grid;gap:5px}.param-editor label{color:var(--muted);font-size:12px;font-weight:700}.diagram{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.diagram-step{padding:9px 11px;border:1px solid var(--strong);border-radius:8px;background:#f4faf7;font-size:13px;font-weight:700}.diagram-arrow{color:var(--muted);font-weight:800}.phy-layout{display:grid;grid-template-columns:220px minmax(0,1fr);gap:12px}.family-list{display:grid;gap:8px;align-content:start}.family-button.active{background:#e7f5ef;color:var(--blue);border-color:#a6d6c3}.block-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}.block-card{background:#fff;border:1px solid var(--line);border-radius:8px;padding:12px;cursor:pointer;min-height:150px}.block-card.active{border-color:var(--blue);box-shadow:0 0 0 2px rgba(8,127,91,.12)}.block-panel{margin-top:0}.block-panel table{font-size:13px}.config-dock .table-wrap{max-height:48vh}
.table-wrap{overflow:auto;max-height:560px;overscroll-behavior:contain;min-width:0}.table-wrap.page-table{max-height:none;overflow:visible}.table-wrap.tall-scroll{max-height:min(72vh, 880px)}table{width:100%;border-collapse:collapse}th,td{padding:9px 10px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}th{position:sticky;top:0;background:#f3f6fa;z-index:1;color:#405469}.stream{max-height:360px;overflow:auto;overscroll-behavior:contain;display:grid;gap:8px}.stream-item{border:1px solid var(--line);border-radius:8px;padding:10px;background:#fff}.log-warn{border-left:4px solid var(--amber)}.log-error{border-left:4px solid var(--red)}.warning{border-left:4px solid var(--amber);padding:10px 12px;background:#fff8e8;color:#6b4500;border-radius:8px}.map-box{min-height:500px;overflow:hidden}#geometryMap,#realtimeMap{height:500px;width:100%}.chart-box{height:380px;border:1px solid var(--line);border-radius:8px;background:#fff}.chart-empty{display:grid;place-items:center;height:100%;padding:18px;color:var(--muted);text-align:center}.toolbar{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-bottom:12px}.toolbar label{display:grid;gap:6px;font-size:12px;color:var(--muted);font-weight:700;min-width:140px}.toolbar label select{width:100%}.toolbar select[multiple]{min-height:132px}.metric-explorer-note{margin:8px 0 0;color:var(--muted);font-size:12px;line-height:1.45}.artifact-gallery{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.artifact-card{border:1px solid var(--line);border-radius:8px;padding:12px;background:#fff}.artifact-card h4{margin:0 0 8px}.artifact-card img{display:block;width:100%;max-height:320px;object-fit:contain;border:1px solid var(--line);border-radius:8px;background:#f7f9fc}.mini-note{font-size:12px;color:var(--muted);line-height:1.45}.split{display:grid;grid-template-columns:minmax(0,1.1fr) minmax(320px,.9fr);gap:12px}.small{font-size:12px;color:var(--muted)}.mono{font-family:var(--mono)}.user-host{margin-bottom:12px}.user-strip{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.profile-chip{display:inline-flex;gap:8px;align-items:center;padding:6px 8px;border:1px solid var(--line);border-radius:8px}.profile-avatar{width:28px;height:28px;display:grid;place-items:center;border-radius:8px;background:#eaf2ff;color:var(--blue);font-weight:800}.profile-role{display:block;color:var(--muted);font-size:12px}.inline-form{display:inline}
@media(max-width:1280px){.app-shell{grid-template-columns:240px minmax(0,1fr)}.workflow{grid-template-columns:repeat(3,minmax(0,1fr))}.block-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:860px){.app-shell,.product-header,.split,.phy-layout,.grid.two,.grid.three,.grid.four,.form-grid,.workflow,.block-grid{display:block}.sidebar{position:static;height:auto;margin-bottom:12px}.tile,.panel,.config-dock{margin-bottom:12px}.top-actions{justify-content:flex-start}}
</style>
"""


def build_product_frontend_page(
    page_id: str,
    selected_scenario: str,
    message: str = "",
    *,
    user_profile: dict[str, Any] | None = None,
) -> bytes:
    scenarios = list_scenarios()
    scenario_name = selected_scenario if selected_scenario in scenarios else (DEFAULT_SCENARIO if DEFAULT_SCENARIO in scenarios else (scenarios[0] if scenarios else DEFAULT_SCENARIO))
    try:
        config_payload, source_chain = load_resolved_config_payload(scenario_name)
    except Exception as exc:
        config_payload = {
            "scenario": {"name": Path(scenario_name).stem},
            "run_control": {"execution_mode": "LLS", "n_frames": 1},
            "output": {"database_host": MYSQL_HOST, "database_port": MYSQL_PORT, "database_schema": MYSQL_DATABASE},
        }
        source_chain = [f"resolved_config_unavailable: {exc}"]
        if not message:
            message = f"Resolved scenario load failed; browser is showing a minimal editable config shell: {exc}"
    run_control = config_payload.get("run_control")
    if not isinstance(run_control, dict):
        run_control = {}
        config_payload["run_control"] = run_control
    mode = str(run_control.get("execution_mode") or "LLS").strip().upper()
    if mode not in BROWSER_EXECUTION_MODE_OPTIONS:
        mode = "LLS"
    run_control["execution_mode"] = mode
    valid_pages = set(PRODUCT_PAGE_ROUTES.values()) | {"architecture"}
    page = page_id if page_id in valid_pages else "home"
    embed_full_config = product_page_needs_config_model(page)
    config_overview = product_config_overview(config_payload, scenario_name, mode)
    scenario_contract = scenario_launch_contract(config_payload, scenario_name)
    include_contract_sections = page in {"reports", "analytics"}
    product_data = {
        "title": "Jio Platforms Limited RAN Simulator",
        "page": page,
        "nav": [{"id": item[0], "label": item[1], "href": item[2]} for item in PRODUCT_NAV],
        "modes": BROWSER_EXECUTION_MODE_OPTIONS,
        "mode_labels": BROWSER_EXECUTION_MODE_LABELS,
        "mode_notes": BROWSER_EXECUTION_MODE_NOTES,
        "fully_wired_mode": FULLY_WIRED_BROWSER_EXECUTION_MODE,
        "scenario": scenario_name,
        "scenarios": scenarios,
        "source_chain": source_chain,
        "initial_mode": mode,
        "config": config_payload if embed_full_config else {},
        "config_loaded": embed_full_config,
        "config_api_url": f"/api/scenario-config?scenario={urllib.parse.quote(scenario_name)}",
        "config_overview": config_overview,
        "scenario_contract": scenario_contract,
        "field_count": product_field_count(config_payload),
        "fields_api_url": f"/api/scenario-fields?scenario={urllib.parse.quote(scenario_name)}",
        "domains": PRODUCT_DOMAIN_FILTERS,
        "architecture": product_architecture_blocks(),
        "phy_families": product_phy_families(),
        "report_sections": output_contract.product_sections_payload("reports") if include_contract_sections else [],
        "analytics_sections": output_contract.product_sections_payload("analytics") if include_contract_sections else [],
        "contract_context_columns": output_contract.BASE_CONTEXT_COLUMNS,
        "contract_value_roles": output_contract.VALUE_ROLES,
        "contract_value_statuses": output_contract.VALUE_STATUSES,
        "section_slug": "",
        "backend": product_backend_status(),
        "matlab_exe": str(MATLAB_EXE),
        "mysql": {"host": MYSQL_HOST, "port": MYSQL_PORT, "database": MYSQL_DATABASE},
        "message": message,
        "poll_ms": POLL_INTERVAL_MS,
        "download_config_url": f"/config/download?scenario={urllib.parse.quote(scenario_name)}",
        "map_default": DEFAULT_MAP_CENTER,
    }
    product_json = json.dumps(product_data, ensure_ascii=False).replace("</", "<\\/")
    scenario_options = "\n".join(
        f'<option value="{html.escape(item)}"{" selected" if item == scenario_name else ""}>{html.escape(scenario_catalog_label(item))}</option>'
        for item in scenarios
    )
    user_strip = render_user_strip(user_profile)
    doc = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(product_data["title"])}</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
  {product_frontend_style()}
</head>
<body>
  <div class="app-shell" data-product-shell>
    <aside class="sidebar" data-scroll-key="sidebar-scroll">
      <div class="brand">
        <div class="brand-mark">6G</div>
        <div>
          <h1>{html.escape(product_data["title"])}</h1>
          <p>Mode-first console for browser-owned LLS execution and DB-backed analysis.</p>
        </div>
      </div>
      <div class="user-host">{user_strip}</div>
      <label class="field-label" for="modeSelector">Mode</label>
      <div id="modeSelector" class="mode-row" aria-label="Mode selector"></div>
      <p id="modeNote" class="small" style="margin-top:10px;"></p>
      <nav id="productNav" class="nav-list" aria-label="Simulator pages"></nav>
    </aside>
    <section class="workspace">
      <header class="product-header">
        <div>
          <span id="activeModeBadge" class="badge good">LLS</span>
          <h2 id="pageTitle">{html.escape(product_data["title"])}</h2>
          <p id="pageSubtitle" class="subtle">Build, run, monitor, and inspect the simulator without exposing raw YAML or JSON on the front page.</p>
          <div id="messageBanner" class="message hidden"></div>
        </div>
        <div class="top-actions" aria-label="Quick actions">
          <select id="scenarioSelect" aria-label="Open Scenario">{scenario_options}</select>
          <button id="newScenarioBtn" type="button">New Scenario</button>
          <button id="openScenarioBtn" type="button">Open Scenario</button>
          <input id="configJsonFileInput" class="hidden" type="file" accept="application/json,.json">
          <button id="loadConfigJsonBtn" type="button">Load Config JSON</button>
          <button id="validateBtn" type="button">Validate</button>
          <form id="runForm" method="post" action="/run">
            <input id="runScenarioInput" type="hidden" name="scenario" value="{html.escape(scenario_name)}">
            <input id="runModeInput" type="hidden" name="execution_mode" value="LLS">
            <input id="runConfigInput" type="hidden" name="config_json" value="">
            <input id="runNextInput" type="hidden" name="next" value="/realtime">
            <input id="runTagInput" type="hidden" name="run_tag" value="">
            <button id="runScenarioBtn" class="primary" type="submit">Run Scenario</button>
          </form>
          <button id="saveScenarioBtn" type="button">Save</button>
          <button id="downloadConfigBtn" type="button">Download Config JSON</button>
        </div>
      </header>
      <main id="productMain"></main>
      <section class="config-dock" aria-label="Selected block configuration">
        <section id="blockPanel" class="block-panel"></section>
      </section>
    </section>
  </div>
  <script>window.SIXGR_PRODUCT_DATA = {product_json};</script>
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
  {product_frontend_script()}
</body>
</html>
"""
    return doc.encode("utf-8")


def product_frontend_script() -> str:
    return """
<script>
window.addEventListener('DOMContentLoaded', function () {
  const root = window.SIXGR_PRODUCT_DATA || {};
  const main = document.getElementById('productMain');
  const storage = { get(key) { try { return localStorage.getItem(key) || ''; } catch (err) { return ''; } }, set(key, value) { try { localStorage.setItem(key, value); } catch (err) {} } };
  const initialConfig = root.config && typeof root.config === 'object' ? root.config : {};
  const initialConfigLoaded = !!(root.config_loaded && Object.keys(initialConfig).length);
  const state = {page: root.page || 'home', mode: String(root.initial_mode || (((initialConfig || {}).run_control || {}).execution_mode || 'LLS')).trim().toUpperCase(), config: initialConfig, configLoaded: initialConfigLoaded, configLoading: false, fields: Array.isArray(root.fields) ? root.fields : [], fieldsLoaded: Array.isArray(root.fields) && root.fields.length > 0, fieldsLoading: false, live: null, liveVersion: '', liveArtifactVersion: '', liveFullPayload: null, liveFullFetchPending: '', sectionEvidence: null, sectionEvidenceVersion: '', runs: [], runsDigest: '', selectedBlock: null, activeFamily: ((root.phy_families || [])[0] || {}).id || '', filter: '', compareBaseline: storage.get('sixgr_compare_baseline'), compareCandidate: storage.get('sixgr_compare_candidate'), compareBaselineLive: null, compareCandidateLive: null, compareLoading: false, uiInteractionUntil: 0, analyticsPublishedChartId: '', metricExplorer: {xAxis: 'slot', metrics: [], secondaryMetric: '', scope: 'all_configured_ues', selectedUE: '', direction: 'all', overlayMode: 'per_ue_overlay'}, analyticsExplorer: {xAxis: 'slot', metrics: [], secondaryMetric: '', scope: 'all_configured_ues', selectedUE: '', direction: 'all', overlayMode: 'per_ue_overlay'}};
  const wired = root.fully_wired_mode || 'LLS';
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const get = (obj, path, fallback) => String(path || '').split('.').filter(Boolean).reduce((node, key) => node && typeof node === 'object' && key in node ? node[key] : undefined, obj) ?? fallback;
  const set = (obj, path, value) => { const parts = String(path || '').split('.').filter(Boolean); let node = obj; parts.slice(0,-1).forEach(k => { if (!node[k] || typeof node[k] !== 'object' || Array.isArray(node[k])) node[k] = {}; node = node[k]; }); if (parts.length) node[parts[parts.length - 1]] = value; };
  const text = (v) => v && typeof v === 'object' ? JSON.stringify(v) : String(v ?? '');
  const unavailable = (why) => `<div class="stream-item log-warn"><strong>Unavailable</strong><br>${esc(why || 'No canonical source is available.')}</div>`;
  function markUserInteracting(ms) { state.uiInteractionUntil = Math.max(Number(state.uiInteractionUntil || 0), Date.now() + Number(ms || 1400)); }
  function eventElement(target) {
    if (target instanceof Element) return target;
    if (target && target.nodeType === 3 && target.parentElement instanceof Element) return target.parentElement;
    return null;
  }
  function isInteractiveElement(el) { const target = eventElement(el); return !!(target && (target.matches('select,input,textarea,button') || target.closest('select,input,textarea,button,[data-scroll-key],.sidebar,.table-wrap,.stream,.chart-box,.toolbar'))); }
  function interactionLocked() { return Date.now() < Number(state.uiInteractionUntil || 0) || isInteractiveElement(document.activeElement); }
  function captureScrollState() { const elements = {}; document.querySelectorAll('[data-scroll-key]').forEach(el => { elements[el.dataset.scrollKey] = {top: el.scrollTop, left: el.scrollLeft}; }); return {page: state.page, windowX: window.scrollX, windowY: window.scrollY, elements}; }
  function restoreScrollState(snapshot) {
    if (!snapshot || snapshot.page !== state.page) return;
    const apply = () => {
      Object.entries(snapshot.elements || {}).forEach(([key, pos]) => {
        const el = [...document.querySelectorAll('[data-scroll-key]')].find(node => node.dataset.scrollKey === key);
        if (el) {
          el.scrollTop = Number(pos.top || 0);
          el.scrollLeft = Number(pos.left || 0);
        }
      });
      window.scrollTo(Number(snapshot.windowX || 0), Number(snapshot.windowY || 0));
    };
    window.requestAnimationFrame(() => {
      apply();
      window.requestAnimationFrame(apply);
      window.setTimeout(apply, 80);
    });
  }
  function scrollWrap(inner, opts) { const options = opts || {}; const className = ['table-wrap'].concat(options.className ? [options.className] : []).join(' '); const keyAttr = options.scrollKey ? ` data-scroll-key="${esc(options.scrollKey)}"` : ''; return `<div class="${esc(className)}"${keyAttr}>${inner}</div>`; }
  function selectValues(node) { return node ? [...node.selectedOptions].map(option => option.value).filter(Boolean) : []; }
  function downloadTextFile(filename, content, mimeType) { const anchor = document.createElement('a'); anchor.href = URL.createObjectURL(new Blob([content], {type: mimeType || 'text/plain;charset=utf-8'})); anchor.download = filename; document.body.appendChild(anchor); anchor.click(); window.setTimeout(() => { URL.revokeObjectURL(anchor.href); anchor.remove(); }, 0); }
  function csvEscape(value) { const token = value === null || value === undefined ? '' : String(value); return /[",\\n]/.test(token) ? `"${token.replace(/"/g, '""')}"` : token; }
  function downloadCsv(filename, rows) { if (!rows || !rows.length) return; const columns = [...new Set(rows.flatMap(row => Object.keys(row || {})))]; const lines = [columns.map(csvEscape).join(',')].concat(rows.map(row => columns.map(col => csvEscape(row[col])).join(','))); downloadTextFile(filename, lines.join('\\n'), 'text/csv;charset=utf-8'); }
  function parseValue(input) { if (input.dataset.kind === 'bool') return input.value === 'true'; if (input.dataset.kind === 'int') return parseInt(input.value, 10) || 0; if (input.dataset.kind === 'float') return parseFloat(input.value) || 0; if (input.dataset.kind === 'json') { try { return JSON.parse(input.value); } catch (err) { return input.value; } } return input.value; }
  function pageNeedsConfigModel(pageId) { return ['run_control','scenario','geometry','waveform','traffic','mac_scheduler','l1_phy','antenna_air','parameters'].includes(String(pageId || '')); }
  function pageNeedsFieldCatalog(pageId) { return pageNeedsConfigModel(pageId); }
  function scenarioClaimsWaveformTruth() {
    const overview = root.config_overview || {};
    const tags = state.configLoaded ? get(state.config, 'meta.tags', []) : ((root.scenario_contract || {}).tags || []);
    const identityValues = [
      root.scenario,
      state.configLoaded ? get(state.config, 'meta.scenario_id', '') : ((root.scenario_contract || {}).scenario_id || overview.scenario_id || ''),
      state.configLoaded ? get(state.config, 'meta.scenario_group', '') : ((root.scenario_contract || {}).scenario_group || ''),
      state.configLoaded ? get(state.config, 'meta.scenario_name', '') : '',
      state.configLoaded ? get(state.config, 'meta.baseline_reference_name', '') : '',
      state.configLoaded ? get(state.config, 'scenario.name', '') : '',
    ].concat(Array.isArray(tags) ? tags : []);
    return identityValues.some(value => {
      const lowered = String(value || '').trim().toLowerCase();
      return lowered && (lowered.includes('waveform_honest') || lowered.includes('waveform_truth'));
    });
  }
  function scenarioUserCount() {
    const values = [
      state.configLoaded ? get(state.config, 'users.n_users', 0) : ((root.scenario_contract || {}).user_count || 0),
      state.configLoaded ? get(state.config, 'deployment_topology.num_ues', 0) : ((root.config_overview || {}).num_ues || 0),
    ];
    return values.reduce((best, value) => {
      const numeric = Number(value);
      return Number.isFinite(numeric) && numeric > best ? numeric : best;
    }, 0);
  }
  function scenarioRequestedTotalSlots() {
    const values = [
      state.configLoaded ? get(state.config, 'run_control.total_slots', 0) : ((root.scenario_contract || {}).requested_total_slots || (root.config_overview || {}).total_slots || 0),
      state.configLoaded ? get(state.config, 'simulation.n_slots', 0) : 0,
    ];
    return values.reduce((best, value) => {
      const numeric = Number(value);
      return Number.isFinite(numeric) && numeric > best ? numeric : best;
    }, 0);
  }
  function waveformBundleRuntimeReadiness(runnerProfileToken) {
    if (runnerProfileToken !== 'waveform_bundle') return {ready:true, reason:'Scenario does not request waveform_bundle dispatch.'};
    if (!state.configLoaded && (root.scenario_contract || {}).runtime_truth_ready === false) {
      return {ready:false, reason:(root.scenario_contract || {}).runtime_truth_reason || (root.scenario_contract || {}).launch_reason || 'Waveform bundle runtime is blocked by the browser launch contract.'};
    }
    const usersEnabled = Boolean(state.configLoaded ? get(state.config, 'users.enabled', false) : false);
    const executionModel = String(state.configLoaded ? get(state.config, 'users.execution_model', '') : ((root.scenario_contract || {}).execution_model || '')).trim().toLowerCase();
    const userCount = scenarioUserCount();
    const totalSlots = scenarioRequestedTotalSlots();
    if (usersEnabled && executionModel === 'slot_coupled_truth' && userCount > 1) {
      const duplexMode = String(state.configLoaded ? get(state.config, 'frequency.duplex_mode', get(state.config, 'global_radio_scope.duplex_mode', get(state.config, 'phy.duplex.mode', get(state.config, 'scenario.duplexMode', 'TDD')))) : ((root.config_overview || {}).duplex_mode || 'TDD')).trim().toUpperCase() || 'TDD';
      const tddPattern = String(state.configLoaded ? get(state.config, 'frame_timing.tdd_pattern', get(state.config, 'frame.tdd_pattern', get(state.config, 'phy.duplex.tddPattern', get(state.config, 'scenario.tddPattern', 'DDDSU')))) : ((root.config_overview || {}).tdd_pattern || 'DDDSU')).trim().toUpperCase() || 'DDDSU';
      if (duplexMode === 'TDD') {
        return {
          ready:true,
          reason:`Waveform bundle launch is truth-ready for the coupled multi-user TDD path: the MATLAB runtime now preserves canonical slot accounting and applies the configured TDD duplex pattern inside the coupled waveform loop. Requested users=${userCount}, total_slots=${totalSlots || 'unavailable'}, duplex_mode=${duplexMode}, tdd_pattern=${tddPattern || 'unavailable'}.`,
        };
      }
    }
    return {ready:true, reason:'Waveform bundle dispatch is not blocked by the current browser launch contract.'};
  }
  function scenarioLaunchContract() {
    const runnerProfile = String(state.configLoaded ? get(state.config, 'scenario.runner_profile', '') : (((root.scenario_contract || {}).runner_profile) || ((root.config_overview || {}).runner_profile) || '')).trim();
    const runnerProfileToken = runnerProfile.toLowerCase();
    const claimsWaveformTruth = scenarioClaimsWaveformTruth();
    const readiness = waveformBundleRuntimeReadiness(runnerProfileToken);
    if (runnerProfileToken === 'waveform_bundle' && !readiness.ready) return {launchAllowed:false, launchContract:'blocked_waveform_bundle_truth_gap', presentationLabel:'Waveform bundle truth blocked', launchReason:readiness.reason, runnerProfile, claimsWaveformTruth};
    if (runnerProfileToken === 'waveform_bundle') return {launchAllowed:true, launchContract:'waveform_bundle_truth', presentationLabel:'Waveform bundle truth', launchReason:readiness.reason || 'Scenario identity and scenario.runner_profile agree on direct waveform_bundle dispatch.', runnerProfile, claimsWaveformTruth};
    if (runnerProfileToken === 'system_level_lls') {
      if (claimsWaveformTruth) return {launchAllowed:false, launchContract:'blocked_mislabeled_waveform_truth', presentationLabel:'System-level LLS waveform-backed replay', launchReason:"Scenario identity still claims waveform truth, but scenario.runner_profile resolves to 'system_level_lls'. Browser /run stays blocked until the config truly dispatches to waveform_bundle or the scenario is renamed honestly.", runnerProfile, claimsWaveformTruth};
      return {launchAllowed:true, launchContract:'system_level_lls_waveform_backed_replay', presentationLabel:'System-level LLS waveform-backed replay', launchReason:'Scenario is honestly labeled for system_level_lls. Browser /run will launch the waveform-backed system-level replay path, not waveform_bundle truth.', runnerProfile, claimsWaveformTruth};
    }
    if (claimsWaveformTruth && runnerProfileToken !== 'waveform_bundle') return {launchAllowed:false, launchContract:'blocked_mislabeled_waveform_truth', presentationLabel:runnerProfile || 'Unconfigured runner', launchReason:`Scenario identity claims waveform truth, but scenario.runner_profile is not 'waveform_bundle' (resolved value: ${runnerProfile || 'unconfigured'}). Browser /run stays blocked until the launch contract is truthful.`, runnerProfile, claimsWaveformTruth};
    return {launchAllowed:Boolean((root.scenario_contract || {}).launch_allowed ?? true), launchContract:(root.scenario_contract || {}).launch_contract || 'honest_non_waveform_bundle_runner', presentationLabel:runnerProfile || (root.scenario_contract || {}).presentation_label || 'Unconfigured runner', launchReason:(root.scenario_contract || {}).launch_reason || 'Browser /run will follow the configured scenario.runner_profile honestly.', runnerProfile, claimsWaveformTruth};
  }
  function ensureConfigLoaded(forceRender) {
    if (state.configLoaded || state.configLoading || !root.config_api_url) return Promise.resolve(state.config);
    state.configLoading = true;
    return fetch(root.config_api_url, {cache:'no-store'})
      .then(response => response.ok ? response.json() : Promise.reject(new Error(`scenario config HTTP ${response.status}`)))
      .then(payload => {
        state.config = payload && typeof payload.config === 'object' ? payload.config : {};
        state.configLoaded = true;
        state.configLoading = false;
        if (payload && payload.mode) state.mode = String(payload.mode).trim().toUpperCase() || state.mode;
        if (payload && payload.config_overview) root.config_overview = payload.config_overview;
        if (payload && payload.scenario_contract) root.scenario_contract = payload.scenario_contract;
        if (Array.isArray(payload?.source_chain) && payload.source_chain.length) root.source_chain = payload.source_chain;
        root.field_count = Number(payload?.field_count || root.field_count || 0);
        updateRunPayload();
        if (forceRender && !interactionLocked()) render({preserveScroll:true});
        return state.config;
      })
      .catch(err => {
        state.configLoading = false;
        const banner = document.getElementById('messageBanner');
        if (banner) {
          banner.textContent = `Scenario config load failed: ${err.message || err}`;
          banner.classList.remove('hidden');
        }
        return state.config;
      });
  }
  function ensureFieldsLoaded(forceRender) {
    if (state.fieldsLoaded || state.fieldsLoading || !root.fields_api_url) return Promise.resolve(state.fields);
    state.fieldsLoading = true;
    return fetch(root.fields_api_url, {cache:'no-store'})
      .then(response => response.ok ? response.json() : Promise.reject(new Error(`field catalog HTTP ${response.status}`)))
      .then(payload => {
        state.fields = Array.isArray(payload.fields) ? payload.fields : [];
        state.fieldsLoaded = true;
        state.fieldsLoading = false;
        root.field_count = Number(payload.field_count || state.fields.length || root.field_count || 0);
        if (forceRender && !interactionLocked()) render({preserveScroll:true});
        return state.fields;
      })
      .catch(err => {
        state.fieldsLoading = false;
        const banner = document.getElementById('messageBanner');
        if (banner) {
          banner.textContent = `Parameter catalog load failed: ${err.message || err}`;
          banner.classList.remove('hidden');
        }
        return state.fields;
      });
  }
  window.addEventListener('error', event => {
    const banner = document.getElementById('messageBanner');
    if (banner) {
      banner.textContent = `Browser render error: ${event.message || 'unknown error'}`;
      banner.classList.remove('hidden');
    }
  });
  window.addEventListener('unhandledrejection', event => {
    const banner = document.getElementById('messageBanner');
    if (banner) {
      banner.textContent = `Browser promise error: ${event.reason || 'unknown rejection'}`;
      banner.classList.remove('hidden');
    }
  });
  function kindFor(value) { if (typeof value === 'boolean') return 'bool'; if (Number.isInteger(value)) return 'int'; if (typeof value === 'number') return 'float'; if (value && typeof value === 'object') return 'json'; return 'text'; }
  function labelFor(path) { const leaf = String(path || 'config').split('.').pop() || 'config'; return leaf.replace(/_/g, ' ').replace(/([a-z])([A-Z])/g, '$1 $2').replace(/\b\w/g, ch => ch.toUpperCase()); }
  function domainFor(path) { const lower = String(path || '').toLowerCase(); for (const [domain, spec] of Object.entries(root.domains || {})) { if ((spec.paths || []).some(prefix => lower.startsWith(String(prefix).toLowerCase()) || lower.includes(String(prefix).toLowerCase()))) return domain; } return 'scenario'; }
  function flattenConfig(node, prefix) { if (node && typeof node === 'object' && !Array.isArray(node)) { const keys = Object.keys(node); if (keys.length) return keys.flatMap(key => flattenConfig(node[key], prefix ? `${prefix}.${key}` : key)); } const domain = domainFor(prefix); return [{path: prefix || 'config', label: labelFor(prefix), domain, domain_label: ((root.domains || {})[domain] || {}).title || domain, kind: kindFor(node), value: node, current_value: node, requested_value: node, resolved_value: node, applied_value: 'unavailable until runtime evidence is published', measured_value: 'unavailable until runtime evidence is published', source: 'loaded config JSON', owner: labelFor(String(prefix || 'config').split('.')[0]), role: 'browser_loaded', search: `${prefix} ${labelFor(prefix)}`}]; }
  function loadConfigFile(file) { const msg = document.getElementById('messageBanner'); if (!file) return; file.text().then(raw => { const parsed = JSON.parse(raw); if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('JSON root must be an object.'); delete parsed._download_metadata; state.config = parsed; state.configLoaded = true; state.configLoading = false; state.mode = String(get(parsed, 'run_control.execution_mode', 'LLS')).trim().toUpperCase(); if (!(root.modes || ['LLS']).includes(state.mode)) state.mode = 'LLS'; state.fields = flattenConfig(parsed, ''); state.fieldsLoaded = true; state.fieldsLoading = false; root.field_count = state.fields.length; state.selectedBlock = null; updateRunPayload(); render(); if (msg) { msg.textContent = `Loaded ${file.name}. Run Scenario will use this full config JSON payload.`; msg.classList.remove('hidden'); } }).catch(err => { if (msg) { msg.textContent = `Could not load config JSON: ${err.message}`; msg.classList.remove('hidden'); } }); }
  function inputFor(field) { const value = get(state.config, field.path, field.current_value); if (field.kind === 'bool') return `<select data-config-input data-path="${esc(field.path)}" data-kind="bool"><option value="true"${value === true ? ' selected' : ''}>true</option><option value="false"${value === false ? ' selected' : ''}>false</option></select>`; if (Array.isArray(field.options) && field.options.length) return `<select data-config-input data-path="${esc(field.path)}" data-kind="${esc(field.kind || 'text')}">${field.options.map(o => `<option value="${esc(o)}"${String(o) === String(value) ? ' selected' : ''}>${esc(o)}</option>`).join('')}</select>`; return `<input data-config-input data-path="${esc(field.path)}" data-kind="${esc(field.kind || 'text')}" value="${esc(text(value))}">`; }
  function updateRunPayload() { if (state.configLoaded) { set(state.config, 'run_control.execution_mode', state.mode); document.getElementById('runConfigInput').value = JSON.stringify(state.config); } else { document.getElementById('runConfigInput').value = ''; } document.getElementById('runModeInput').value = state.mode; document.getElementById('runScenarioInput').value = root.scenario || ''; document.getElementById('runTagInput').value ||= `web_${state.mode.toLowerCase()}_${new Date().toISOString().replace(/[-:.TZ]/g,'').slice(0,14)}`; }
  function runStatusToken(run) { return String((run || {}).status_text || '').toLowerCase().trim(); }
  function isActiveRun(run) { return /queued|launching|running|finalizing|retry/i.test(runStatusToken(run)) && !/completed|failed|cancelled|aborted/i.test(runStatusToken(run)); }
  function runStatusRank(run, preferActive) {
    const token = runStatusToken(run);
    if (!token) return 0;
    if (/(queued|launching|running|finalizing|retry)/i.test(token)) return preferActive ? 6 : 2;
    if (token === 'completed') return preferActive ? 4 : 5;
    if (token === 'completed_with_failures') return preferActive ? 3 : 4;
    if (token.startsWith('aborted') || token.startsWith('stalled')) return 1;
    if (['failed', 'timeout', 'cancelled', 'error'].includes(token)) return 1;
    return 2;
  }
  function sortedRuns(list, preferActive) {
    const prefer = preferActive !== false;
    return [...(list || [])].sort((a, b) => {
      const rankDelta = runStatusRank(b, prefer) - runStatusRank(a, prefer);
      if (rankDelta) return rankDelta;
      const updatedA = Date.parse(String(a.updated_utc || a.created_utc || '')) || 0;
      const updatedB = Date.parse(String(b.updated_utc || b.created_utc || '')) || 0;
      if (updatedB !== updatedA) return updatedB - updatedA;
      return (Number(b.run_id) || 0) - (Number(a.run_id) || 0);
    });
  }
  function pagePrefersActiveRun(pageId) { return String(pageId || state.page || '') === 'realtime'; }
  function currentPreferredRunId(runRows, pageId) {
    const ordered = sortedRuns(runRows || state.runs || [], pagePrefersActiveRun(pageId));
    return String(((ordered[0] || {}).run_id || ''));
  }
  function runsDigest(rows) {
    return (rows || []).map(run => [run.run_id, run.status_text, run.updated_utc, run.created_utc].map(part => String(part || '')).join('|')).join('||');
  }
  function queryRunId() { return new URLSearchParams(location.search).get('run_id') || ''; }
  function selectedRunId() {
    const explicit = queryRunId();
    if (explicit) return String(explicit);
    const preferred = currentPreferredRunId(state.runs, state.page);
    if (preferred) return preferred;
    return String(((state.live || {}).run || {}).run_id || ((root.backend || {}).latest_run_id || ''));
  }
  function preferredRunId(runRows) {
    const explicit = queryRunId();
    if (explicit) return explicit;
    const preferred = currentPreferredRunId(runRows, state.page);
    if (preferred) return preferred;
    return String((root.backend || {}).latest_run_id || '');
  }
  function runSelectOptions(selected, options) {
    const opts = options || {};
    const ordered = sortedRuns(state.runs || [], opts.preferActive !== false);
    const rows = opts.runningOnly ? ordered.filter(isActiveRun) : ordered;
    if (!rows.length) return '<option value="">No runs available</option>';
    return rows.map(run => {
      const tag = String(run.run_tag || run.scenario_id || run.scenario_name || '').slice(0, 42);
      const status = String(run.status_text || 'unknown');
      const prefix = isActiveRun(run) ? '[active]' : '[stored]';
      const label = `Run ${run.run_id} ${prefix} ${status} ${tag}`;
      return `<option value="${esc(run.run_id)}"${String(run.run_id) === String(selected || '') ? ' selected' : ''}>${esc(label)}</option>`;
    }).join('');
  }
  function pageRunSelector(selectId, label, options) { const opts = options || {}; const selected = selectedRunId(); const note = opts.note ? `<p class="mini-note">${esc(opts.note)}</p>` : ''; return `<div class="toolbar"><label>${esc(label || 'Run')}<select id="${esc(selectId)}" data-run-selector="true">${runSelectOptions(selected, opts)}</select></label>${opts.showRunningBadge ? `<span class="badge ${((state.runs || []).some(isActiveRun)) ? 'good' : 'warn'}">${esc(((state.runs || []).filter(isActiveRun).length))} active runs</span>` : ''}</div>${note}`; }
  function navigateWithRun(runId) { const url = new URL(window.location.href); if (runId) url.searchParams.set('run_id', runId); else url.searchParams.delete('run_id'); window.location.href = `${url.pathname}${url.search}`; }
  function evidenceTokens(value) { return String(value || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').split(/\s+/).filter(token => token && token.length > 2 && !['the','and','for','with','from','into','over','time','chart','plot','view','views','analytics','runtime','live','graph'].includes(token)); }
  function tokenOverlapScore(left, right) { const rightSet = new Set(right || []); return (left || []).reduce((score, token) => score + (rightSet.has(token) ? 1 : 0), 0); }
  function chartEvidenceCatalog(section) {
    const live = state.live || {};
    const sectionPrefix = `contract__${String(section.slug || '').toLowerCase()}__`;
    const sectionTokens = evidenceTokens([
      section.slug,
      section.title,
      section.domain,
      ...(section.tables || []).map(item => item.table_name || ''),
      ...(section.charts || []).map(item => item.chart_name || ''),
    ].join(' '));
    const sectionKey = String(section.domain || '').toLowerCase();
    const tableArtifacts = (live.tables_all || []).filter(item => {
      const logicalPath = String(item.logical_path || '').toLowerCase();
      const haystack = [item.logical_path, item.section, item.artifact_kind].join(' ');
      return logicalPath.includes(sectionPrefix) || String(item.section || '').toLowerCase() === sectionKey || tokenOverlapScore(sectionTokens, evidenceTokens(haystack)) > 0;
    });
    const imageArtifacts = (live.images_all || []).filter(item => {
      const logicalPath = String(item.logical_path || '').toLowerCase();
      const haystack = [item.logical_path, item.section, item.artifact_kind].join(' ');
      return logicalPath.includes(sectionPrefix) || String(item.section || '').toLowerCase() === sectionKey || tokenOverlapScore(sectionTokens, evidenceTokens(haystack)) > 0;
    });
    const numericCharts = publishedAnalyticsCharts().map(chart => ({...chart, __tokens: evidenceTokens([chart.title, chart.chart_id].join(' '))})).filter(chart => tokenOverlapScore(sectionTokens, chart.__tokens) > 0 || String(chart.chart_id || '').toLowerCase().includes(String(section.slug || '').toLowerCase()));
    return {tableArtifacts, imageArtifacts, numericCharts};
  }
  function dedupeArtifacts(items) {
    const seen = new Set();
    const out = [];
    (items || []).forEach(item => {
      const key = String((item || {}).artifact_id || (item || {}).logical_path || '');
      if (!key || seen.has(key)) return;
      seen.add(key);
      out.push(item);
    });
    return out;
  }
  function resolveChartEvidence(section, chart) {
    const catalog = chartEvidenceCatalog(section);
    const chartTokens = evidenceTokens([chart.chart_name, chart.default_status, section.slug, section.title, section.domain].join(' '));
    const numericMatches = catalog.numericCharts.filter(item => tokenOverlapScore(chartTokens, item.__tokens) > 0);
    const imageMatches = catalog.imageArtifacts.filter(item => tokenOverlapScore(chartTokens, evidenceTokens([item.logical_path, item.section].join(' '))) > 0);
    const tableMatches = catalog.tableArtifacts.filter(item => tokenOverlapScore(chartTokens, evidenceTokens([item.logical_path, item.section].join(' '))) > 0);
    let statusLabel = 'unavailable until real source rows exist';
    let statusClass = 'warn';
    let reason = chart.default_status || 'unavailable_until_source_table_has_real_rows';
    let lineageNote = 'No matching numeric chart rows, image artifact, or chartable source table was published for this run.';
    if (numericMatches.length) {
      statusLabel = 'published in selected run';
      statusClass = 'good';
      reason = 'selected_run_numeric_chart_rows';
      lineageNote = 'Published numeric chart rows are available in the selected run.';
    } else if (imageMatches.length) {
      statusLabel = 'published image artifact';
      statusClass = 'good';
      reason = 'selected_run_image_artifact';
      lineageNote = 'A persisted image artifact is available for this chart in the selected run.';
    } else if (tableMatches.length) {
      statusLabel = 'chartable source table present';
      statusClass = 'good';
      reason = 'selected_run_chart_source_table';
      lineageNote = 'A chartable source table is available for this chart in the selected run.';
    } else if (catalog.numericCharts.length || catalog.imageArtifacts.length || catalog.tableArtifacts.length) {
      statusLabel = 'section evidence present';
      statusClass = 'good';
      reason = 'selected_run_section_evidence_present';
      lineageNote = `This run published neighboring section evidence (${catalog.numericCharts.length} numeric charts, ${catalog.imageArtifacts.length} image artifacts, ${catalog.tableArtifacts.length} tables), but not a separately matched chart artifact for this exact row.`;
    }
    return {catalog, numericMatches, imageMatches, tableMatches, statusLabel, statusClass, reason, lineageNote};
  }
  function chartEvidenceFor(section, chart) {
    const evidence = resolveChartEvidence(section, chart);
    if (evidence.numericMatches.length) {
      const numericMatch = evidence.numericMatches[0];
      const lineage = numericMatch.download_url ? `<a class="button-link" href="${esc(numericMatch.download_url)}">Download Source CSV</a>` : evidence.lineageNote;
      return {status: statusBadge(evidence.statusLabel, evidence.statusClass), lineage, rule: evidence.reason};
    }
    if (evidence.imageMatches.length) {
      const imageMatch = evidence.imageMatches[0];
      const openUrl = imageMatch.view_url || imageMatch.download_url || '#';
      return {status: statusBadge(evidence.statusLabel, evidence.statusClass), lineage: `<a class="button-link" href="${esc(openUrl)}">Open Artifact</a>`, rule: evidence.reason};
    }
    if (evidence.tableMatches.length) {
      const tableMatch = evidence.tableMatches[0];
      const openUrl = tableMatch.view_url || tableMatch.download_url || '#';
      return {status: statusBadge(evidence.statusLabel, evidence.statusClass), lineage: `<a class="button-link" href="${esc(openUrl)}">Preview Source Table</a>`, rule: evidence.reason};
    }
    return {
      status: statusBadge(evidence.statusLabel, evidence.statusClass),
      lineage: chart.lineage_required ? evidence.lineageNote : 'n/a',
      rule: evidence.reason,
    };
  }
  function sectionPublishedArtifacts(section, kind) {
    if (section && section.evidence_bundle) return section.evidence_bundle;
    const catalog = chartEvidenceCatalog(section);
    const slugToken = `contract__${String(section.slug || '').toLowerCase()}__`;
    const live = state.live || {};
    const scopedTables = (live.tables_all || []).filter(item => String((item || {}).logical_path || '').toLowerCase().includes(slugToken));
    const scopedImages = (live.images_all || []).filter(item => String((item || {}).logical_path || '').toLowerCase().includes(slugToken));
    const contractTableMatches = [];
    const contractChartTableMatches = [];
    const contractChartImageMatches = [];
    (section.tables || []).forEach(table => {
      const evidence = table.evidence || {};
      const matches = Array.isArray(evidence.matches) && evidence.matches.length ? evidence.matches : artifactMatches(table);
      contractTableMatches.push(...matches.filter(match => String(match.artifact_kind || '').includes('table')));
    });
    const chartDetails = (section.charts || []).map(chart => ({ chart, evidence: resolveChartEvidence(section, chart) }));
    chartDetails.forEach(item => {
      contractChartTableMatches.push(...(item.evidence.tableMatches || []).filter(match => String(match.artifact_kind || '').includes('table')));
      contractChartImageMatches.push(...(item.evidence.imageMatches || []).filter(match => !String(match.artifact_kind || '').includes('table')));
    });
    const imageMatches = chartDetails.flatMap(item => item.evidence.imageMatches || []);
    const tableMatches = chartDetails.flatMap(item => item.evidence.tableMatches || []);
    const unavailableRows = [];
    (section.tables || []).forEach(table => {
      const evidence = table.evidence || {};
      const matches = Array.isArray(evidence.matches) && evidence.matches.length ? evidence.matches : artifactMatches(table);
      if (!matches.length) {
        unavailableRows.push({
          type: 'table',
          name: table.table_name,
          reason: evidence.reason || evidence.lineage_note || 'No canonical table artifact was published for this run.',
        });
      }
    });
    chartDetails.forEach(item => {
      if (!(item.evidence.numericMatches.length || item.evidence.imageMatches.length || item.evidence.tableMatches.length)) {
        unavailableRows.push({
          type: 'chart',
          name: item.chart.chart_name,
          reason: item.evidence.reason || item.evidence.lineageNote || 'No matching chart evidence was published for this run.',
        });
      }
    });
    return {
      numericCharts: catalog.numericCharts,
      tableArtifacts: dedupeArtifacts([...scopedTables, ...catalog.tableArtifacts, ...contractTableMatches, ...contractChartTableMatches, ...tableMatches]),
      imageArtifacts: dedupeArtifacts([...scopedImages, ...catalog.imageArtifacts, ...contractChartImageMatches, ...imageMatches]),
      unavailableRows,
      chartDetails,
      kind,
    };
  }
  function sectionArtifactTable(items, empty) {
    if (!items || !items.length) return unavailable(empty);
    return `<div class="table-wrap"><table><thead><tr><th>Artifact</th><th>Kind</th><th>Section</th><th>Bytes</th><th>Actions</th></tr></thead><tbody>${items.map(item => `<tr><td><strong>${esc(item.logical_path || item.artifact_id)}</strong><br><span class="small mono">artifact_id=${esc(item.artifact_id)}</span></td><td>${esc(item.artifact_kind || '')}</td><td>${esc(item.section || '')}</td><td>${esc(item.byte_size || '')}</td><td><a class="button-link" href="${esc(item.view_url || item.download_url || '#')}">${String(item.artifact_kind || '').includes('table') ? 'Preview Table' : 'Open'}</a> <a class="button-link" href="${esc(item.download_url || item.view_url || '#')}">Download</a></td></tr>`).join('')}</tbody></table></div>`;
  }
  function sectionImageGallery(items, empty) {
    if (!items || !items.length) return `<div class="chart-empty">${esc(empty)}</div>`;
    return `<div class="artifact-gallery">${items.slice(0, 12).map(item => `<article class="artifact-card"><h4>${esc(item.logical_path || item.artifact_id)}</h4><a href="${esc(item.view_url || item.download_url || '#')}" target="_blank" rel="noopener noreferrer"><img loading="lazy" decoding="async" src="${esc(item.view_url || item.download_url || '#')}" alt="${esc(item.logical_path || item.artifact_id)}"></a><div class="toolbar" style="margin-top:10px;"><a class="button-link secondary" href="${esc(item.view_url || item.download_url || '#')}" target="_blank" rel="noopener noreferrer">Open In New Tab</a><a class="button-link secondary" href="${esc(item.download_url || item.view_url || '#')}">Download</a></div></article>`).join('')}</div>`;
  }
  function sectionUnavailableTable(rows, empty) {
    if (!rows || !rows.length) return `<div class="mini-note">${esc(empty)}</div>`;
    return `<div class="table-wrap"><table><thead><tr><th>Type</th><th>Name</th><th>Exact Reason</th></tr></thead><tbody>${rows.map(row => `<tr><td>${esc(row.type)}</td><td>${esc(row.name)}</td><td>${esc(row.reason)}</td></tr>`).join('')}</tbody></table></div>`;
  }
  function sectionEvidencePanel(section, kind) {
    const evidence = sectionPublishedArtifacts(section, kind);
    const chartButtons = evidence.numericCharts.map(chart => `<a class="button-link" href="${esc(chart.download_url || '#')}">${esc(chart.title || chart.chart_id || 'Numeric Chart')}</a>`).join('');
    return `<section class="panel"><h3>Published Evidence For This ${esc(kind === 'analytics' ? 'Analytics' : 'Report')} Family</h3><p class="subtle">This panel shows only real persisted artifacts that match <code>${esc(section.slug || '')}</code> for the selected run. Missing rows stay explicitly unavailable with exact reasons.</p><div class="toolbar">${statusBadge(`${evidence.tableArtifacts.length} matched tables`, evidence.tableArtifacts.length ? 'good' : 'warn')}${statusBadge(`${evidence.imageArtifacts.length} matched visuals`, evidence.imageArtifacts.length ? 'good' : 'warn')}${statusBadge(`${evidence.numericCharts.length} numeric charts`, evidence.numericCharts.length ? 'good' : 'warn')}${statusBadge(`${evidence.unavailableRows.length} unavailable contract rows`, evidence.unavailableRows.length ? 'warn' : 'good')}</div><h4>Published Source Tables / Views</h4>${sectionArtifactTable(evidence.tableArtifacts, 'No persisted source tables matched this family for the selected run.')}<h4 style="margin-top:16px;">Published Visual Artifacts</h4>${sectionImageGallery(evidence.imageArtifacts, 'No persisted chart, waveform, heatmap, or image artifact matched this family for the selected run.')}<h4 style="margin-top:16px;">Numeric Chart Sources</h4>${chartButtons ? `<div class="toolbar">${chartButtons}</div>` : '<div class="mini-note">No directly chartable numeric tabs were matched for this family.</div>'}<h4 style="margin-top:16px;">Unavailable Rows</h4>${sectionUnavailableTable(evidence.unavailableRows, 'Every contract row in this family matched a real persisted source artifact or chart source.')}</section>`;
  }
  function rows(records, empty, opts) { if (!records || !records.length) return unavailable(empty); const keys = Object.keys(records[0]).slice(0, 12); return scrollWrap(`<table><thead><tr>${keys.map(k => `<th>${esc(k)}</th>`).join('')}</tr></thead><tbody>${records.map(r => `<tr>${keys.map(k => `<td>${esc(text(r[k]))}</td>`).join('')}</tr>`).join('')}</tbody></table>`, opts); }
  function objectTable(obj, empty, opts) { const keys = Object.keys(obj || {}); return keys.length ? scrollWrap(`<table><tbody>${keys.map(k => `<tr><th>${esc(k)}</th><td>${esc(text(obj[k]))}</td></tr>`).join('')}</tbody></table>`, opts) : unavailable(empty); }
  function issueRegistryTable() { const issues = (((state.live || {}).output_coverage || {}).issue_registry || []); const cols = ['severity','issue_status','issue_category','block_name','direction','ue_id','metric_name','observed_value','root_cause_hint','fix_plan']; const body = issues.length ? scrollWrap(`<table><thead><tr>${cols.map(c => `<th>${esc(c)}</th>`).join('')}</tr></thead><tbody>${issues.map(row => `<tr>${cols.map(c => `<td>${esc(text(row[c]))}</td>`).join('')}</tr>`).join('')}</tbody></table>`, {className:'tall-scroll', scrollKey:'issue-registry'}) : unavailable('No result issue registry rows are available for this run.'); return `<section class="panel"><h3>Result Issue Registry</h3><p class="subtle">Issues come from reports/csv/result_issue_registry.csv with evidence artifact references and fix plans. They are shown in both real-time result and analytics views.</p>${body}</section>`; }
  function blockFields(block) { const params = (block.params || []).map(p => String(p).toLowerCase()); const domain = String(block.domain || '').toLowerCase(); const exact = state.fields.filter(f => (domain && f.domain === domain) || params.some(p => String(f.path || '').toLowerCase().includes(p))); if (exact.length >= 25 || domain) return exact; if (block.group || block.tests || String(block.name || '').match(/PDCCH|PDSCH|PUSCH|PUCCH|PRACH|SRS|TRS|CSI|PBCH|SSB|MIMO|PHY/i)) return state.fields.filter(f => f.domain === 'l1_phy'); return exact; }
  function renderBlock(block) { const el = document.getElementById('blockPanel'); if (!block) { el.innerHTML = '<h3>Block Parameters</h3><p class="subtle">Select a workflow or PHY block to inspect editable parameters.</p>'; return; } if (!state.configLoaded || !state.fieldsLoaded) { ensureConfigLoaded(true); ensureFieldsLoaded(true); el.innerHTML = `<h3>${esc(block.name || block.title)}</h3>${unavailable('Block parameters are loading from the resolved scenario config and field catalog.')}`; return; } const body = blockFields(block).map(f => `<tr><td><strong>${esc(f.label || f.path)}</strong><br><span class="small mono">${esc(f.path)}</span></td><td>${esc(text(get(state.config, f.path, f.current_value)))}</td><td>${inputFor(f)}</td><td>${esc(text(f.resolved_value))}</td><td>${esc(text(f.applied_value))}</td><td>${esc(text(f.measured_value))}</td><td>${esc(f.source)}</td><td>${esc(f.owner)}</td><td>${esc(f.role)}</td></tr>`).join('') || '<tr><td colspan="9">Unavailable: no browser-exposed parameter maps directly to this block.</td></tr>'; el.innerHTML = `<h3>${esc(block.name || block.title)}</h3><p class="subtle">${esc(block.purpose || block.summary || '')}</p><p class="small">${esc((block.artifacts || []).join(', ') || block.truth || 'Canonical artifacts first; missing outputs stay unavailable.')}</p><div class="table-wrap"><table><thead><tr><th>parameter name</th><th>current value</th><th>requested value</th><th>resolved value</th><th>applied value</th><th>measured/runtime value</th><th>source</th><th>owner</th><th>role</th></tr></thead><tbody>${body}</tbody></table></div>`; }
  function chrome() { const contract = scenarioLaunchContract(); document.getElementById('productNav').innerHTML = (root.nav || []).map(n => `<a class="nav-item ${n.id === state.page ? 'active' : ''}" data-page="${esc(n.id)}" href="${esc(n.href)}">${esc(n.label)}</a>`).join(''); document.getElementById('modeSelector').innerHTML = (root.modes || ['LLS','SLS','E2E']).map(m => `<button type="button" class="mode-button ${m === state.mode ? 'active' : ''}" data-mode="${esc(m)}">${esc(m)}</button>`).join(''); document.getElementById('modeNote').textContent = state.mode === wired ? (contract.launchReason || (root.mode_notes || {})[state.mode] || '') : ((root.mode_notes || {})[state.mode] || ''); document.getElementById('activeModeBadge').textContent = `Mode: ${state.mode}`; document.getElementById('activeModeBadge').className = `badge ${state.mode === wired && contract.launchAllowed ? 'good' : 'warn'}`; document.getElementById('runScenarioBtn').disabled = state.mode !== wired || !contract.launchAllowed; document.getElementById('runScenarioBtn').textContent = state.mode !== wired ? `${state.mode} run unavailable` : (contract.launchAllowed ? 'Run Scenario' : 'Run blocked by scenario contract'); document.getElementById('runScenarioBtn').title = state.mode !== wired ? ((root.mode_notes || {})[state.mode] || '') : (contract.launchAllowed ? `Launch the real browser-owned LLS run via ${contract.presentationLabel || 'the configured runner'}.` : (contract.launchReason || 'Selected scenario is blocked.')); updateRunPayload(); }
  function title(t, s) { document.getElementById('pageTitle').textContent = t; document.getElementById('pageSubtitle').textContent = s; }
  function home() { title(root.title, 'Clickable workflow, current scenario, warnings, recent runs, and configuration readiness.'); const cards = (root.architecture || []).map(b => `<article class="tile" data-block="${esc(b.id)}"><span class="badge">${esc(b.domain)}</span><h4>${esc(b.title)}</h4><p>${esc(b.summary)}</p></article>`).join(''); const fieldCount = Number(root.field_count || state.fields.length || 0); const overview = root.config_overview || {}; const contract = scenarioLaunchContract(); main.innerHTML = `<div class="grid four"><div class="tile metric"><h4>Mode</h4><div class="value">${esc(state.mode)}</div><p>${state.mode === wired && contract.launchAllowed ? 'Launch enabled' : 'Configure only'}</p></div><div class="tile metric"><h4>Launch Contract</h4><div class="value">${esc(contract.launchContract || 'unavailable')}</div><p>${esc(contract.presentationLabel || 'Runtime label pending')}</p></div><div class="tile metric"><h4>Config JSON</h4><div class="value">${state.configLoaded ? 'Ready' : 'Lazy'}</div><p>${state.configLoaded ? 'Loaded in browser memory' : 'Loaded on demand for edit pages and downloads'}</p></div><div class="tile metric"><h4>Latest Run</h4><div class="value">${esc((root.backend || {}).latest_run_id || 'none')}</div><p>Result selector</p></div></div><section class="panel"><h3>Architecture Workflow</h3><p class="subtle">Click a block to configure that subsystem.</p><div class="workflow">${cards}</div></section><div class="split"><section class="panel"><h3>Recent Runs</h3><div id="homeRecentRuns">${rows(state.runs.slice(0,10), 'No recent runs are available from MySQL.', {className:'page-table', scrollKey:'home-recent-runs'})}</div></section><section class="panel"><h3>Current Scenario Summary</h3>${objectTable({Scenario: root.scenario, Mode: state.mode, RunnerProfile: state.configLoaded ? get(state.config, 'scenario.runner_profile', overview.runner_profile || 'unavailable') : (overview.runner_profile || 'loading'), Presentation: contract.presentationLabel || overview.presentation_label || 'loading', LaunchAllowed: contract.launchAllowed, Carrier: state.configLoaded ? get(state.config, 'frequency.center_frequency_hz', get(state.config, 'global_radio_scope.carrier_frequency_hz', overview.carrier_hz || 'unavailable')) : (overview.carrier_hz || 'loading'), Bandwidth: state.configLoaded ? get(state.config, 'frequency.bandwidth_hz', get(state.config, 'global_radio_scope.channel_bandwidth_hz', overview.bandwidth_hz || 'unavailable')) : (overview.bandwidth_hz || 'loading'), Channel: state.configLoaded ? get(state.config, 'channels.profile', get(state.config, 'channel_model.scenario_label', overview.channel_profile || 'unavailable')) : (overview.channel_profile || 'loading'), UEs: overview.num_ues || 'unavailable', Slots: overview.total_slots || 'unavailable'}, '')}<h3 style="margin-top:16px;">Warnings / Completeness</h3>${warnings()}</section></div>`; }
  function warnings() { const w = []; const contract = scenarioLaunchContract(); if (state.mode !== wired) w.push(`${state.mode} launch is intentionally unavailable from /run; switch to LLS to execute.`); if (!(root.backend || {}).matlab_available) w.push('Pinned MATLAB R2023b executable is missing.'); if ((root.backend || {}).mysql_status !== 'connected') w.push(`MySQL unavailable: ${(root.backend || {}).mysql_reason || 'no connection'}`); if (!contract.launchAllowed) w.push(contract.launchReason || 'Selected scenario launch contract is blocked.'); else if (contract.presentationLabel) w.push(`Browser launch contract: ${contract.presentationLabel}. ${contract.launchReason || ''}`); if (!w.length) w.push('No browser-side blockers. Runtime truth still comes from MATLAB and canonical artifacts.'); return w.map(x => `<div class="stream-item log-warn">${esc(x)}</div>`).join(''); }
  function domain(name) { const spec = (root.domains || {})[name] || {title:name}; title(spec.title || name, 'Traditional controls plus block-driven editing share the same browser config model.'); const bs = (root.architecture || []).filter(b => b.domain === name); if (!state.configLoaded || !state.fieldsLoaded) { ensureConfigLoaded(true); ensureFieldsLoaded(true); main.innerHTML = `<div class="split"><section class="panel"><h3>${esc(spec.title || name)}</h3>${unavailable('This page is loading the resolved scenario config and field catalog. Controls will appear automatically once that payload arrives.')}</section><section class="panel"><h3>Blocks</h3><div class="grid">${bs.map(b => `<article class="tile" data-block="${esc(b.id)}"><h4>${esc(b.title)}</h4><p>${esc(b.summary)}</p></article>`).join('') || unavailable('No workflow blocks map to this page.')}</div></section></div>`; return; } const fs = state.fields.filter(f => f.domain === name); main.innerHTML = `<div class="split"><section class="panel"><h3>${esc(spec.title || name)}</h3><p class="subtle">${fs.length} exposed parameters on this page.</p><div class="form-grid">${fs.map(f => `<div class="param-editor"><label>${esc(f.label || f.path)}</label>${inputFor(f)}<span class="small mono">${esc(f.path)}</span></div>`).join('') || unavailable('No browser-exposed parameters map to this page.')}</div></section><section class="panel"><h3>Blocks</h3><div class="grid">${bs.map(b => `<article class="tile" data-block="${esc(b.id)}"><h4>${esc(b.title)}</h4><p>${esc(b.summary)}</p></article>`).join('') || unavailable('No workflow blocks map to this page.')}</div></section></div>`; }
  function geometry() { domain('geometry'); main.insertAdjacentHTML('beforeend', '<section class="panel"><h3>OpenStreetMap Deployment View</h3><p class="subtle">Sites, sectors, UEs, hotspots, serving view, coverage overlays, and mobility paths use canonical map payloads when available. Dragging a site writes deployment_topology.site_overrides into the browser config.</p><div id="geometryMap" class="map-box"></div></section>'); setTimeout(map, 0); }
  function map() { if (!window.L) return; const p = (state.live || {}).map || {}; const c = p.center || root.map_default || {lat:19.122164, lon:72.999217}; const m = L.map('geometryMap').setView([Number(c.lat), Number(c.lon)], Number(c.zoom || 14)); L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {maxZoom:19, attribution:'&copy; OpenStreetMap contributors'}).addTo(m); [...(p.site_shapes || []), ...(p.sector_shapes || []), ...(p.coverage_shapes || [])].forEach(s => s.points && L.polygon(s.points, {color:'#1f5fbf', weight:1, fillOpacity:.08}).addTo(m)); const sites = (p.sites || p.markers || [{lat:c.lat, lon:c.lon, label:c.label, site_id:1}]).filter(x => String(x.type || 'site') !== 'ue'); sites.slice(0,120).forEach((s,i) => { const mk = L.marker([Number(s.lat), Number(s.lon)], {draggable:true}).addTo(m).bindPopup(esc(s.label || `Site ${i+1}`)); mk.on('dragend', () => { const ll = mk.getLatLng(); const id = s.site_id || i+1; const o = get(state.config, 'deployment_topology.site_overrides', {}) || {}; o[String(id)] = {lat:+ll.lat.toFixed(7), lon:+ll.lng.toFixed(7), source:'browser_osm_drag'}; set(state.config, 'deployment_topology.site_overrides', o); updateRunPayload(); }); }); (p.ues || p.markers || []).filter(x => String(x.type || '') === 'ue').slice(0,300).forEach(u => L.circleMarker([Number(u.lat), Number(u.lon)], {radius:4,color:'#0b7f82',fillOpacity:.7}).addTo(m).bindPopup(esc(u.label || 'UE'))); }
  function l1() { const fams = root.phy_families || []; const f = fams.find(x => x.id === state.activeFamily) || fams[0] || {blocks:[]}; title('L1 / PHY Explorer', 'Deep clickable DL, UL, control, reference-signal, and MIMO chains.'); main.innerHTML = `<section class="panel"><h3>L1 / PHY Explorer</h3><div class="phy-layout"><div class="family-list">${fams.map(x => `<button type="button" class="family-button ${x.id === f.id ? 'active' : ''}" data-family="${esc(x.id)}">${esc(x.title)}</button>`).join('')}</div><div><p class="subtle">${esc(f.summary || '')}</p><div class="block-grid">${(f.blocks || []).map(b => `<article class="block-card" data-phy="${esc(b.id)}"><span class="badge">${esc(b.group)}</span><h4>${esc(b.name)}</h4><p>${esc(b.purpose)}</p><p class="small">Tests: ${esc((b.tests || []).join(', '))}</p></article>`).join('')}</div><div class="panel" style="margin-top:12px;"><h3>Signal Flow</h3><div class="diagram">${(((f.blocks || [])[0] || {}).stages || []).map((s,i) => `${i ? '<span class="diagram-arrow">-></span>' : ''}<span class="diagram-step">${esc(s)}</span>`).join('')}</div></div></div></div></section>`; }
  function metricExplorerPayload() { return ((state.live || {}).metric_explorer || {}); }
  function metricMeta(metricId) { return (metricExplorerPayload().available_metrics || []).find(metric => metric.id === metricId) || null; }
  function rowMatchesDirection(row, direction) { if (!direction || direction === 'all') return true; const token = String(row.direction || '').toUpperCase(); if (!token) return direction === 'channel'; if (direction === 'channel') return token === 'CHANNEL'; return token === direction || token === `DL+UL`; }
  function ensureMetricExplorerState() { const explorer = metricExplorerPayload(); const defaults = explorer.default_metrics || []; const xAxes = explorer.x_axes || [{id:'slot', label:'Slot'}]; const currentXAxis = state.metricExplorer.xAxis; if (!xAxes.some(axis => axis.id === currentXAxis)) state.metricExplorer.xAxis = explorer.default_x_axis || xAxes[0].id || 'slot'; const availableIds = new Set((explorer.available_metrics || []).map(metric => metric.id)); const selectedMetrics = (state.metricExplorer.metrics || []).filter(metricId => availableIds.has(metricId)); state.metricExplorer.metrics = selectedMetrics.length ? selectedMetrics : defaults.slice(0, 2); const ueIds = explorer.ue_ids || []; if (state.metricExplorer.selectedUE && !ueIds.some(ueid => String(ueid) === String(state.metricExplorer.selectedUE))) state.metricExplorer.selectedUE = ueIds.length ? String(ueIds[0]) : ''; if (!state.metricExplorer.selectedUE && ueIds.length) state.metricExplorer.selectedUE = String(ueIds[0]); }
  function metricExplorerTraces() {
    const explorer = metricExplorerPayload();
    ensureMetricExplorerState();
    const rows = explorer.rows || [];
    const metrics = (state.metricExplorer.metrics || []).map(metricId => metricMeta(metricId)).filter(Boolean);
    const xAxis = state.metricExplorer.xAxis || 'slot';
    const direction = state.metricExplorer.direction || 'all';
    const filteredRows = rows.filter(row => rowMatchesDirection(row, direction));
    const traces = [];
    const scope = state.metricExplorer.scope || 'all_configured_ues';
    if (scope === 'selected_ue_only') {
      const selected = String(state.metricExplorer.selectedUE || '');
      const scopedRows = filteredRows.filter(row => String(row.ueid) === selected);
      metrics.forEach(metric => {
        const points = scopedRows.filter(row => row[xAxis] != null && row[metric.id] != null).sort((a, b) => Number(a[xAxis] || 0) - Number(b[xAxis] || 0));
        if (!points.length) return;
        traces.push({
          type: 'scattergl',
          mode: 'lines+markers',
          name: `${metric.label} · UE ${selected}`,
          x: points.map(point => point[xAxis]),
          y: points.map(point => point[metric.id]),
          customdata: points.map(point => [point.slot, point.direction, point.ueid]),
          hovertemplate: `UE %{customdata[2]}<br>Slot %{customdata[0]}<br>Direction %{customdata[1]}<br>${esc(metric.label)}: %{y}<extra></extra>`,
        });
      });
      return traces;
    }
    const ueids = [...new Set(filteredRows.map(row => String(row.ueid)).filter(Boolean))].sort((a, b) => Number(a) - Number(b));
    ueids.forEach(ueid => {
      const ueRows = filteredRows.filter(row => String(row.ueid) === ueid);
      metrics.forEach(metric => {
        const points = ueRows.filter(row => row[xAxis] != null && row[metric.id] != null).sort((a, b) => Number(a[xAxis] || 0) - Number(b[xAxis] || 0));
        if (!points.length) return;
        traces.push({
          type: 'scattergl',
          mode: 'lines',
          name: `UE ${ueid} · ${metric.label}`,
          x: points.map(point => point[xAxis]),
          y: points.map(point => point[metric.id]),
          customdata: points.map(point => [point.slot, point.direction, point.ueid]),
          hovertemplate: `UE %{customdata[2]}<br>Slot %{customdata[0]}<br>Direction %{customdata[1]}<br>${esc(metric.label)}: %{y}<extra></extra>`,
          line: {width: metrics.length > 1 ? 1.2 : 1.6},
          opacity: ueids.length > 24 ? 0.55 : 0.82,
        });
      });
    });
    return traces;
  }
  function renderMetricExplorer() {
    const explorer = metricExplorerPayload();
    const host = document.getElementById('liveMetricExplorer');
    const summaryHost = document.getElementById('liveMetricSummary');
    if (!host || !summaryHost) return;
    if (!explorer.available) {
      host.innerHTML = `<div class="chart-empty">${esc(explorer.unavailable_reason || 'No slot-indexed live metric rows are available yet.')}</div>`;
      summaryHost.innerHTML = '';
      return;
    }
    ensureMetricExplorerState();
    const traces = metricExplorerTraces();
    const metrics = (state.metricExplorer.metrics || []).map(metricId => metricMeta(metricId)).filter(Boolean);
    const xAxisMeta = (explorer.x_axes || []).find(axis => axis.id === state.metricExplorer.xAxis) || {label:'Slot'};
    const selectedSummary = explorer.ue_summaries ? explorer.ue_summaries[String(state.metricExplorer.selectedUE || '')] : null;
    const sourceBadges = (explorer.source_tables || []).map(path => `<span class="badge">${esc(path)}</span>`).join('');
    const sampling = explorer.sampling || {};
    const summaryBits = [
      `<span class="badge good">Configured UEs: ${esc(explorer.configured_ue_count)}</span>`,
      `<span class="badge">Chartable UEs: ${esc(explorer.chartable_ue_count)}</span>`,
      `<span class="badge">Chart rows in browser: ${esc(sampling.chart_rows_browser || 0)}</span>`,
      sourceBadges,
    ].join('');
    if (!traces.length) {
      host.innerHTML = '<div class="chart-empty">The selected metric and UE scope do not have chartable rows in this run.</div>';
    } else if (window.Plotly) {
      window.Plotly.newPlot(host, traces, {
        margin: {l: 54, r: 18, t: 36, b: 48},
        plot_bgcolor: 'rgba(255,255,255,0.96)',
        paper_bgcolor: 'rgba(255,255,255,0.96)',
        legend: {orientation: 'h', y: -0.28},
        xaxis: {title: xAxisMeta.label || 'Slot', gridcolor: 'rgba(133,150,178,0.18)'},
        yaxis: {title: metrics.length === 1 ? metrics[0].label : 'Selected metrics', gridcolor: 'rgba(133,150,178,0.18)'},
      }, {responsive: true, displaylogo: false, scrollZoom: true});
    } else {
      host.innerHTML = '<div class="chart-empty">Interactive chart library is unavailable, but the underlying runtime tables are still live and downloadable.</div>';
    }
    const selectedHtml = selectedSummary ? `<div class="stream-item"><strong>Selected UE snapshot</strong><br>UE ${esc(selectedSummary.ueid)} | DL throughput ${esc(selectedSummary.dl_throughput_mbps)} Mbps | UL throughput ${esc(selectedSummary.ul_throughput_mbps)} Mbps | User throughput ${esc(selectedSummary.user_throughput_mbps)} Mbps | DL BLER ${esc(selectedSummary.dl_bler)} | UL BLER ${esc(selectedSummary.ul_bler)}</div>` : '';
    summaryHost.innerHTML = `${summaryBits}${selectedHtml}<p class="metric-explorer-note">${esc(explorer.sampling_note || '')}</p>`;
  }
  function realtime() {
    title('Real-Time Data', 'Canonical MySQL live payload, logs, grants, control, PHY, channel, warnings, and a live UE metric explorer.');
    const live = state.live;
    if (!live) { main.innerHTML = `<section class="panel"><h3>Real-Time Data</h3>${pageRunSelector('realtimeRunSelect', 'Selected Run', {showRunningBadge: true, runningOnly: false, note: 'Pick any stored run, or let the browser follow an active running run by default.'})}${unavailable('No canonical live payload has been selected yet.')}</section>`; return; }
    const rt = live.runtime_context || {};
    const explorer = metricExplorerPayload();
    ensureMetricExplorerState();
    const logs = (live.logs_recent || []).filter(l => !state.filter || JSON.stringify(l).toLowerCase().includes(state.filter.toLowerCase()));
    const xAxisOptions = (explorer.x_axes || [{id:'slot', label:'Slot'}]).map(axis => `<option value="${esc(axis.id)}"${axis.id === state.metricExplorer.xAxis ? ' selected' : ''}>${esc(axis.label)}</option>`).join('');
    const metricOptions = (explorer.available_metrics || []).map(metric => `<option value="${esc(metric.id)}"${(state.metricExplorer.metrics || []).includes(metric.id) ? ' selected' : ''}>${esc(metric.label)} [${esc(metric.fidelity_level || 'unknown')}]</option>`).join('');
    const ueOptions = (explorer.ue_ids || []).map(ueid => `<option value="${esc(ueid)}"${String(ueid) === String(state.metricExplorer.selectedUE) ? ' selected' : ''}>UE ${esc(ueid)}</option>`).join('');
    main.innerHTML = `<div class="grid four">${[['Run Status',(live.run || {}).status_text],['ResultOk',(live.summary || {}).result_ok],['RequiredFailureCount',(live.summary || {}).required_failure_count],['Configured UEs',(live.summary || {}).configured_users]].map(x => `<div class="tile metric"><h4>${esc(x[0])}</h4><div class="value">${esc(text(x[1] ?? 'unavailable'))}</div><p>canonical live payload</p></div>`).join('')}</div><section class="panel"><h3>Live UE Metric Explorer</h3><p class="subtle">X-axis defaults to slot. Y-axis metrics come only from the selected run's real serving-trace and waveform trial tables; missing metrics stay unavailable instead of being invented.</p><div class="toolbar"><label>X Axis<select id="liveXAxisSelect">${xAxisOptions}</select></label><label>Y Axis Metrics<select id="liveMetricSelect" multiple>${metricOptions}</select></label><label>UE Scope<select id="liveUEScopeSelect"><option value="all_configured_ues"${state.metricExplorer.scope === 'all_configured_ues' ? ' selected' : ''}>All configured UEs</option><option value="selected_ue_only"${state.metricExplorer.scope === 'selected_ue_only' ? ' selected' : ''}>Selected UE</option></select></label><label>Selected UE<select id="liveUESelect"${state.metricExplorer.scope === 'selected_ue_only' ? '' : ' disabled'}>${ueOptions}</select></label><label>Direction<select id="liveDirectionSelect"><option value="all"${state.metricExplorer.direction === 'all' ? ' selected' : ''}>All</option><option value="DL"${state.metricExplorer.direction === 'DL' ? ' selected' : ''}>DL</option><option value="UL"${state.metricExplorer.direction === 'UL' ? ' selected' : ''}>UL</option><option value="channel"${state.metricExplorer.direction === 'channel' ? ' selected' : ''}>Channel / measurement only</option></select></label></div><div id="liveMetricExplorer" class="chart-box"></div><div id="liveMetricSummary"></div></section><div class="split"><section class="panel"><h3>Frame / Slot / Stage</h3>${objectTable(rt.stage || {}, 'No canonical stage row is available.', {className:'tall-scroll', scrollKey:'realtime-stage'})}<h3>Live Scheduler Grants</h3>${rows([...(rt.pucch_grants || [])], 'No canonical scheduler grant rows are available in this live payload.', {className:'tall-scroll', scrollKey:'realtime-grants'})}</section><section class="panel"><h3>Control / PHY / Channel State</h3>${objectTable(rt.control_summary || {}, 'No control summary is available.', {className:'tall-scroll', scrollKey:'realtime-control-summary'})}${rows(rt.control_state_preview || [], 'No live control state rows are available.', {className:'tall-scroll', scrollKey:'realtime-control-state'})}${rows(rt.channel_array_consistency_preview || [], 'No channel state rows are available.', {className:'tall-scroll', scrollKey:'realtime-channel-state'})}</section></div>${issueRegistryTable()}<section class="panel"><div class="toolbar"><h3 style="margin:0;">Logs / Event Stream</h3><input id="liveFilter" placeholder="Filter logs" value="${esc(state.filter)}"></div><div class="stream" data-scroll-key="realtime-logs">${logs.map(l => `<div class="stream-item ${/error/i.test(JSON.stringify(l)) ? 'log-error' : /warn/i.test(JSON.stringify(l)) ? 'log-warn' : ''}"><strong>${esc(l.source || l.module || l.created_utc || 'log')}</strong><br>${esc(l.message || l.line_text || l.log_message || JSON.stringify(l))}</div>`).join('') || unavailable('No logs are available for this run yet.')}</div></section>`;
    renderMetricExplorer();
  }
  function explorerState(kind) { return kind === 'analytics' ? state.analyticsExplorer : state.metricExplorer; }
  function explorerXAxisOptions(kind) { const explorer = metricExplorerPayload(); const baseAxes = explorer.x_axes || [{id:'slot', label:'Slot'}]; if (kind !== 'analytics') return baseAxes; return baseAxes.concat((explorer.available_metrics || []).map(metric => ({id: metric.id, label: metric.label}))); }
  function ensureMetricExplorerState(kind) {
    const explorer = metricExplorerPayload();
    const viewState = explorerState(kind);
    const defaults = explorer.default_metrics || [];
    const xAxes = explorerXAxisOptions(kind);
    if (!xAxes.some(axis => axis.id === viewState.xAxis)) viewState.xAxis = explorer.default_x_axis || ((xAxes[0] || {}).id || 'slot');
    const availableIds = new Set((explorer.available_metrics || []).map(metric => metric.id));
    const selectedMetrics = (viewState.metrics || []).filter(metricId => availableIds.has(metricId));
    viewState.metrics = selectedMetrics.length ? selectedMetrics : defaults.slice(0, 2);
    if (viewState.secondaryMetric && !availableIds.has(viewState.secondaryMetric)) viewState.secondaryMetric = '';
    if (!['per_ue_overlay', 'per_cell_overlay'].includes(String(viewState.overlayMode || ''))) viewState.overlayMode = 'per_ue_overlay';
    const ueIds = explorer.ue_ids || [];
    if (viewState.selectedUE && !ueIds.some(ueid => String(ueid) === String(viewState.selectedUE))) viewState.selectedUE = ueIds.length ? String(ueIds[0]) : '';
    if (!viewState.selectedUE && ueIds.length) viewState.selectedUE = String(ueIds[0]);
    return viewState;
  }
  function explorerFilteredRows(kind) {
    const viewState = ensureMetricExplorerState(kind);
    const rows = (metricExplorerPayload().rows || []).filter(row => rowMatchesDirection(row, viewState.direction || 'all'));
    if ((viewState.scope || 'all_configured_ues') === 'selected_ue_only') return rows.filter(row => String(row.ueid) === String(viewState.selectedUE || ''));
    return rows;
  }
  function explorerGroupKey(row, viewState) { if ((viewState.scope || 'all_configured_ues') === 'selected_ue_only') return `UE ${row.ueid}`; if ((viewState.overlayMode || 'per_ue_overlay') === 'per_cell_overlay') return row.serving_cell != null ? `Cell ${row.serving_cell}` : 'Cell unavailable'; return `UE ${row.ueid}`; }
  function buildMetricExplorerSeries(kind) {
    const explorer = metricExplorerPayload();
    const viewState = ensureMetricExplorerState(kind);
    const rows = explorerFilteredRows(kind);
    const primaryMetrics = (viewState.metrics || []).map(metricId => metricMeta(metricId)).filter(Boolean);
    const secondaryMetric = metricMeta(viewState.secondaryMetric);
    const metrics = primaryMetrics.slice();
    if (secondaryMetric && !metrics.some(metric => metric.id === secondaryMetric.id)) metrics.push(secondaryMetric);
    const xAxisId = viewState.xAxis || 'slot';
    const xAxisMeta = explorerXAxisOptions(kind).find(axis => axis.id === xAxisId) || {id: xAxisId, label: xAxisId};
    const groupedRows = new Map();
    rows.forEach(row => {
      const key = explorerGroupKey(row, viewState);
      if (!groupedRows.has(key)) groupedRows.set(key, []);
      groupedRows.get(key).push(row);
    });
    const traces = [];
    [...groupedRows.entries()].sort((a, b) => String(a[0]).localeCompare(String(b[0]), undefined, {numeric: true})).forEach(([groupLabel, groupRows]) => {
      metrics.forEach(metric => {
        const points = groupRows.filter(row => row[xAxisId] != null && row[metric.id] != null).sort((a, b) => Number(a[xAxisId] || 0) - Number(b[xAxisId] || 0));
        if (!points.length) return;
        const useSecondaryAxis = !!(secondaryMetric && metric.id === secondaryMetric.id);
        traces.push({
          type: 'scattergl',
          mode: points.length > 1 ? 'lines+markers' : 'markers',
          name: `${groupLabel} · ${metric.label}`,
          x: points.map(point => point[xAxisId]),
          y: points.map(point => point[metric.id]),
          yaxis: useSecondaryAxis ? 'y2' : 'y',
          customdata: points.map(point => [point.slot, point.direction, point.ueid, point.serving_cell]),
          hovertemplate: `${esc(groupLabel)}<br>Slot %{customdata[0]}<br>Direction %{customdata[1]}<br>UE %{customdata[2]}<br>Cell %{customdata[3]}<br>${esc(metric.label)}: %{y}<extra></extra>`,
          line: {width: primaryMetrics.length > 1 || useSecondaryAxis ? 1.2 : 1.8},
          opacity: groupedRows.size > 24 ? 0.55 : 0.82,
        });
      });
    });
    return {traces, primaryMetrics, secondaryMetric, xAxisMeta};
  }
  function metricExplorerExportRows(kind) {
    const viewState = ensureMetricExplorerState(kind);
    const filteredRows = explorerFilteredRows(kind);
    const metricIds = [...new Set([...(viewState.metrics || []), viewState.secondaryMetric].filter(Boolean))];
    const xAxisId = viewState.xAxis || 'slot';
    return filteredRows.filter(row => row[xAxisId] != null && metricIds.some(metricId => row[metricId] != null)).map(row => {
      const exportRow = {slot: row.slot, time_s: row.time_s, x_axis: xAxisId, x_value: row[xAxisId], ueid: row.ueid, serving_cell: row.serving_cell, base_station_id: row.base_station_id, direction: row.direction, overlay_group: explorerGroupKey(row, viewState)};
      metricIds.forEach(metricId => { exportRow[metricId] = row[metricId]; });
      return exportRow;
    });
  }
  function exportMetricExplorer(kind) { const rows = metricExplorerExportRows(kind); if (!rows.length) { window.alert('No filtered runtime rows are available for export in the current chart selection.'); return; } const viewState = ensureMetricExplorerState(kind); downloadCsv(`${kind}_metric_explorer_${String(viewState.overlayMode || 'overlay')}_${String(viewState.direction || 'all')}.csv`, rows); }
  function renderMetricExplorer(kind) {
    const explorer = metricExplorerPayload();
    const prefix = kind === 'analytics' ? 'analytics' : 'live';
    const host = document.getElementById(`${prefix}MetricExplorer`);
    const summaryHost = document.getElementById(`${prefix}MetricSummary`);
    if (!host || !summaryHost) return;
    if (!explorer.available) { host.innerHTML = `<div class="chart-empty">${esc(explorer.unavailable_reason || 'No slot-indexed live metric rows are available yet.')}</div>`; summaryHost.innerHTML = ''; return; }
    const viewState = ensureMetricExplorerState(kind);
    const series = buildMetricExplorerSeries(kind);
    const selectedSummary = explorer.ue_summaries ? explorer.ue_summaries[String(viewState.selectedUE || '')] : null;
    const sourceBadges = (explorer.source_tables || []).map(path => `<span class="badge">${esc(path)}</span>`).join('');
    const sampling = explorer.sampling || {};
    const filteredCount = metricExplorerExportRows(kind).length;
    const summaryBits = [`<span class="badge good">Configured UEs: ${esc(explorer.configured_ue_count)}</span>`,`<span class="badge">Chartable UEs: ${esc(explorer.chartable_ue_count)}</span>`,`<span class="badge">Chartable Cells: ${esc(explorer.chartable_cell_count || 0)}</span>`,`<span class="badge">Filtered Rows: ${esc(filteredCount)}</span>`,`<span class="badge">Chart rows in browser: ${esc(sampling.chart_rows_browser || 0)}</span>`,sourceBadges].join('');
    if (!series.traces.length) host.innerHTML = '<div class="chart-empty">The selected metric, overlay, and scope do not have chartable rows in this run.</div>';
    else if (window.Plotly) {
      const layout = {margin: {l: 54, r: 54, t: 36, b: 48}, plot_bgcolor: 'rgba(255,255,255,0.96)', paper_bgcolor: 'rgba(255,255,255,0.96)', legend: {orientation: 'h', y: -0.28}, xaxis: {title: series.xAxisMeta.label || 'Slot', gridcolor: 'rgba(133,150,178,0.18)'}, yaxis: {title: series.primaryMetrics.length === 1 ? series.primaryMetrics[0].label : 'Primary metrics', gridcolor: 'rgba(133,150,178,0.18)'}};
      if (series.secondaryMetric) layout.yaxis2 = {title: series.secondaryMetric.label, overlaying: 'y', side: 'right', gridcolor: 'rgba(0,0,0,0)'};
      window.Plotly.react(host, series.traces, layout, {responsive: true, displaylogo: false, scrollZoom: true});
    } else host.innerHTML = '<div class="chart-empty">Interactive chart library is unavailable, but the underlying runtime tables are still live and downloadable.</div>';
    const selectedHtml = selectedSummary ? `<div class="stream-item"><strong>Selected UE snapshot</strong><br>UE ${esc(selectedSummary.ueid)} | DL throughput ${esc(selectedSummary.dl_throughput_mbps)} Mbps | UL throughput ${esc(selectedSummary.ul_throughput_mbps)} Mbps | User throughput ${esc(selectedSummary.user_throughput_mbps)} Mbps | DL BLER ${esc(selectedSummary.dl_bler)} | UL BLER ${esc(selectedSummary.ul_bler)}</div>` : '';
    const secondaryHtml = series.secondaryMetric ? `<div class="stream-item"><strong>Dual-axis enabled</strong><br>Secondary Y axis: ${esc(series.secondaryMetric.label)}</div>` : '';
    summaryHost.innerHTML = `${summaryBits}${selectedHtml}${secondaryHtml}<p class="metric-explorer-note">${esc(explorer.sampling_note || '')}</p>`;
  }
  function refreshRealtimeExplorerUI() {
    const ueSelect = document.getElementById('liveUESelect');
    if (ueSelect) ueSelect.disabled = (explorerState('realtime').scope || 'all_configured_ues') !== 'selected_ue_only';
    renderMetricExplorer('realtime');
  }
  function refreshAnalyticsExplorerUI() {
    const ueSelect = document.getElementById('analyticsUESelect');
    if (ueSelect) ueSelect.disabled = (explorerState('analytics').scope || 'all_configured_ues') !== 'selected_ue_only';
    renderMetricExplorer('analytics');
  }
  function controlTruthNote() {
    const runtime = ((state.live || {}).runtime_context || {});
    const truthModes = runtime.truth_modes || {};
    const controlSummary = runtime.control_summary || {};
    const controlMode = String(truthModes.control_integration_mode || '');
    if (controlMode && !controlMode.includes('runtime_control_access_state_gated')) return `<div class="warning" style="margin-bottom:12px;">PBCH/PRACH/PDCCH/SRS/TRS gating fields remain zero in this run because <strong>${esc(controlMode)}</strong> does not couple control/access outcomes into the active scheduler/data path. These zeros are honest inactive-path values, not hidden executed control truth.</div>`;
    const controlZeroFields = ['PBCHGatingActive', 'PRACHGatingActive', 'PDCCHGatingActive', 'SRSGatingActive', 'TRSGatingActive'];
    if (controlZeroFields.every(field => Number(controlSummary[field] || 0) === 0)) return '<div class="warning" style="margin-bottom:12px;">The visible control gating counters are all zero in the sampled live payload. The browser is not fabricating control activity where the runtime did not persist any gating event.</div>';
    return '';
  }
  function controlTrialEvidencePanel() {
    const previews = (((state.live || {}).runtime_context || {}).control_trial_previews || {});
    const specs = [
      ['pbch_trials', 'PBCH'],
      ['prach_trials', 'PRACH'],
      ['pdcch_trials', 'PDCCH'],
      ['pucch_trials', 'PUCCH'],
      ['srs_trials', 'SRS'],
      ['trs_trials', 'TRS'],
    ];
    const cardsHtml = specs.map(([key, label]) => {
      const rowsForKey = Array.isArray(previews[key]) ? previews[key] : [];
      const body = rowsForKey.length
        ? rows(rowsForKey, `No ${label} rows are available.`, {className:'tall-scroll', scrollKey:`control-${key}`})
        : `<div class="chart-empty">No canonical ${esc(label)} runtime rows were published for this run.</div>`;
      return `<article class="artifact-card"><h4>${esc(label)} Runtime Rows</h4><p class="mini-note">${esc(rowsForKey.length)} preview row(s) loaded from the selected run.</p>${body}</article>`;
    }).join('');
    return `<section class="panel"><h3>Control Signal Runtime Evidence</h3><p class="subtle">These tables show actual PBCH/PRACH/PDCCH/PUCCH/SRS/TRS rows only when the selected run published them. Missing rows stay missing; the browser does not synthesize control execution.</p><div class="artifact-gallery">${cardsHtml}</div></section>`;
  }
  function publishedAnalyticsCharts() {
    const live = state.live || {};
    const charts = live.charts || {};
    const progressCharts = charts.progress_tabs || [];
    const preferredNumericCharts = live.analysis_mode === 'post_run'
      ? (((charts.summary_tabs || []).length) ? (charts.summary_tabs || []) : (charts.numeric_tabs || []))
      : (charts.numeric_tabs || []);
    return [
      ...progressCharts.map(chart => ({ ...chart, chart_id: chart.chart_id || `progress_${chart.title}` })),
      { chart_id: 'artifact_activity', title: 'Artifact Activity', series: (charts.artifact_activity || {}).series || [], xaxis_title: 'Index / Time', yaxis_title: 'Count' },
      { chart_id: 'log_activity', title: 'Log Activity', series: (charts.log_activity || {}).series || [], xaxis_title: 'Index / Time', yaxis_title: 'Count' },
      ...preferredNumericCharts.map(chart => ({ ...chart, chart_id: `artifact_${chart.artifact_id}` })),
    ].filter(chart => Array.isArray(chart.series) && chart.series.length);
  }
  function drawPublishedAnalyticsChart(hostId, chart) {
    const host = document.getElementById(hostId);
    if (!host) return;
    const prepared = [];
    let xmin = Infinity, xmax = -Infinity, ymin = Infinity, ymax = -Infinity;
    for (const series of (chart.series || [])) {
      const pts = [];
      for (const point of (series.points || [])) {
        const x = Number(point.x);
        const y = Number(point.y);
        if (!Number.isFinite(x) || !Number.isFinite(y)) continue;
        pts.push({x, y});
        xmin = Math.min(xmin, x); xmax = Math.max(xmax, x);
        ymin = Math.min(ymin, y); ymax = Math.max(ymax, y);
      }
      if (pts.length) prepared.push({name: series.name, points: pts, mode: series.mode || 'lines+markers'});
    }
    if (!prepared.length) { host.innerHTML = '<div class="chart-empty">No numeric points are available yet for this published chart.</div>'; return; }
    if (window.Plotly) {
      const traces = prepared.map(series => ({
        name: series.name,
        x: series.points.map(pt => pt.x),
        y: series.points.map(pt => pt.y),
        mode: series.mode,
        type: 'scatter',
        line: { width: 2.5 },
        marker: { size: 6 },
      }));
      const downloads = chart.download_url ? `<a class="button-link secondary" href="${esc(chart.download_url)}">Download Source CSV</a>` : '';
      host.innerHTML = `<div class="toolbar" style="justify-content:space-between;align-items:flex-start;"><div style="font-weight:700;margin-bottom:8px;">${esc(chart.title || 'Published Chart')}</div><div>${downloads}</div></div><div id="${hostId}_plot" style="width:100%;height:360px;"></div>`;
      window.Plotly.react(
        document.getElementById(`${hostId}_plot`),
        traces,
        {
          paper_bgcolor: 'rgba(0,0,0,0)',
          plot_bgcolor: 'rgba(255,255,255,0.95)',
          margin: { l: 50, r: 20, t: 20, b: 42 },
          legend: { orientation: 'h' },
          xaxis: { title: chart.xaxis_title || 'Index / Time', gridcolor: 'rgba(133,150,178,0.18)' },
          yaxis: { title: chart.yaxis_title || 'Value', gridcolor: 'rgba(133,150,178,0.18)' },
          hovermode: 'closest',
        },
        { responsive: true, displaylogo: false, scrollZoom: true },
      );
      return;
    }
    host.innerHTML = '<div class="chart-empty">Plotly is unavailable, but the selected run already published chartable numeric rows. Download the source CSV instead.</div>';
  }
  function renderPublishedAnalyticsPanel() {
    const tabs = document.getElementById('analyticsPublishedChartTabs');
    const host = document.getElementById('analyticsPublishedChartHost');
    if (!tabs || !host) return;
    const chartList = publishedAnalyticsCharts();
    if (!chartList.length) {
      tabs.innerHTML = '<span class="mini-note">No published numeric chart rows are available for the selected run yet.</span>';
      host.innerHTML = '<div class="chart-empty">When the run publishes chartable numeric rows or chart images, they appear here automatically.</div>';
      return;
    }
    if (!state.analyticsPublishedChartId || !chartList.some(item => item.chart_id === state.analyticsPublishedChartId)) {
      state.analyticsPublishedChartId = chartList[0].chart_id;
    }
    tabs.innerHTML = chartList.map(item => `<button type="button" class="mode-button ${item.chart_id === state.analyticsPublishedChartId ? 'active' : ''}" data-analytics-published-chart="${esc(item.chart_id)}">${esc(item.title)}</button>`).join('');
    const selected = chartList.find(item => item.chart_id === state.analyticsPublishedChartId) || chartList[0];
    drawPublishedAnalyticsChart('analyticsPublishedChartHost', selected);
  }
  function waveformArtifactPanel() {
    const images = ((state.live || {}).images_all || []);
    const waveformItems = images.filter(item => /waveform|resource[_-]?grid|grid|iq|spectrum/i.test(String(item.logical_path || '')));
    const constellationItems = images.filter(item => /constellation|evm/i.test(String(item.logical_path || '')));
    const heatmapItems = images.filter(item => /heatmap|prb|resource[_-]?grid/i.test(String(item.logical_path || '')));
    function cards(items, emptyReason) {
      if (!items.length) return `<div class="chart-empty">${esc(emptyReason)}</div>`;
      return `<div class="artifact-gallery">${items.slice(0, 8).map(item => `<article class="artifact-card"><h4>${esc(item.logical_path || item.artifact_id)}</h4><a href="${esc(item.view_url || item.download_url || '#')}" target="_blank" rel="noopener noreferrer"><img loading="lazy" decoding="async" src="${esc(item.view_url || item.download_url || '#')}" alt="${esc(item.logical_path || item.artifact_id)}"></a><div class="toolbar" style="margin-top:10px;"><a class="button-link secondary" href="${esc(item.view_url || item.download_url || '#')}" target="_blank" rel="noopener noreferrer">Open In New Tab</a><a class="button-link secondary" href="${esc(item.download_url || item.view_url || '#')}">Download</a></div></article>`).join('')}</div>`;
    }
    return `<section class="panel"><h3>Waveform / Heatmap / Constellation Artifacts</h3><p class="subtle">These panels only render persisted waveform, heatmap, and constellation artifacts that this run actually exported. If the backend did not publish them, the browser leaves them unavailable with an exact reason.</p><h4>Waveform / Grid</h4>${cards(waveformItems, 'No persisted waveform or resource-grid image artifacts were published for this run.')}<h4 style="margin-top:16px;">Heatmaps / Resource Occupancy</h4>${cards(heatmapItems, 'No persisted heatmap or PRB-occupancy image artifacts were published for this run.')}<h4 style="margin-top:16px;">Constellation / EVM</h4>${cards(constellationItems, 'No persisted constellation or EVM image artifacts were published for this run.')}</section>`;
  }
  function analyticsPublishedChartsPanel() {
    return `<section class="panel"><h3>Published Analytics Charts</h3><p class="subtle">These charts are built only from the selected run's real numeric chart rows and persisted chart source tables. They do not replace the contract table below; they surface whatever the run genuinely published.</p><div id="analyticsPublishedChartTabs" class="toolbar" style="margin-bottom:12px;"></div><div id="analyticsPublishedChartHost" class="chart-box"></div></section>`;
  }
  function analyticsExplorerPanel() {
    const explorer = metricExplorerPayload();
    ensureMetricExplorerState('analytics');
    const xAxisOptions = explorerXAxisOptions('analytics').map(axis => `<option value="${esc(axis.id)}"${axis.id === explorerState('analytics').xAxis ? ' selected' : ''}>${esc(axis.label)}</option>`).join('');
    const metricOptions = (explorer.available_metrics || []).map(metric => `<option value="${esc(metric.id)}"${(explorerState('analytics').metrics || []).includes(metric.id) ? ' selected' : ''}>${esc(metric.label)} [${esc(metric.fidelity_level || 'unknown')}]</option>`).join('');
    const secondaryOptions = ['<option value="">None</option>'].concat((explorer.available_metrics || []).map(metric => `<option value="${esc(metric.id)}"${String(metric.id) === String(explorerState('analytics').secondaryMetric || '') ? ' selected' : ''}>${esc(metric.label)}</option>`)).join('');
    const ueOptions = (explorer.ue_ids || []).map(ueid => `<option value="${esc(ueid)}"${String(ueid) === String(explorerState('analytics').selectedUE || '') ? ' selected' : ''}>UE ${esc(ueid)}</option>`).join('');
    return `<section class="panel"><h3>Analytics Explorer</h3><p class="subtle">Plot any published numeric runtime metric against slot, time, or another published numeric metric. This panel uses the same truthful live metric payload as Realtime; it does not invent missing telemetry.</p><div class="toolbar"><label>X Axis<select id="analyticsXAxisSelect">${xAxisOptions}</select></label><label>Primary Y Metrics<select id="analyticsMetricSelect" multiple>${metricOptions}</select></label><label>Secondary Y<select id="analyticsSecondaryMetricSelect">${secondaryOptions}</select></label><label>Overlay<select id="analyticsOverlaySelect"><option value="per_ue_overlay"${explorerState('analytics').overlayMode === 'per_ue_overlay' ? ' selected' : ''}>Per-UE overlay</option><option value="per_cell_overlay"${explorerState('analytics').overlayMode === 'per_cell_overlay' ? ' selected' : ''}>Per-cell overlay</option></select></label><label>UE Scope<select id="analyticsUEScopeSelect"><option value="all_configured_ues"${explorerState('analytics').scope === 'all_configured_ues' ? ' selected' : ''}>All configured UEs</option><option value="selected_ue_only"${explorerState('analytics').scope === 'selected_ue_only' ? ' selected' : ''}>Selected UE</option></select></label><label>Selected UE<select id="analyticsUESelect"${explorerState('analytics').scope === 'selected_ue_only' ? '' : ' disabled'}>${ueOptions}</select></label><label>Direction<select id="analyticsDirectionSelect"><option value="all"${explorerState('analytics').direction === 'all' ? ' selected' : ''}>All</option><option value="DL"${explorerState('analytics').direction === 'DL' ? ' selected' : ''}>DL</option><option value="UL"${explorerState('analytics').direction === 'UL' ? ' selected' : ''}>UL</option><option value="channel"${explorerState('analytics').direction === 'channel' ? ' selected' : ''}>Channel / measurement only</option></select></label><button type="button" id="analyticsMetricExportBtn">Export Filtered Rows</button></div><div id="analyticsMetricExplorer" class="chart-box"></div><div id="analyticsMetricSummary"></div></section>`;
  }
  function realtime() {
    title('Real-Time Data', 'Canonical MySQL live payload, logs, grants, control, PHY, channel, warnings, and a live UE metric explorer.');
    const live = state.live;
    if (!live) { main.innerHTML = `<section class="panel"><h3>Real-Time Data</h3>${unavailable('No canonical live payload has been selected yet.')}</section>`; return; }
    const rt = live.runtime_context || {};
    const explorer = metricExplorerPayload();
    ensureMetricExplorerState('realtime');
    const viewState = explorerState('realtime');
    const logs = (live.logs_recent || []).filter(l => !state.filter || JSON.stringify(l).toLowerCase().includes(state.filter.toLowerCase()));
    const xAxisOptions = explorerXAxisOptions('realtime').map(axis => `<option value="${esc(axis.id)}"${axis.id === viewState.xAxis ? ' selected' : ''}>${esc(axis.label)}</option>`).join('');
    const metricOptions = (explorer.available_metrics || []).map(metric => `<option value="${esc(metric.id)}"${(viewState.metrics || []).includes(metric.id) ? ' selected' : ''}>${esc(metric.label)} [${esc(metric.fidelity_level || 'unknown')}]</option>`).join('');
    const secondaryOptions = ['<option value="">None</option>'].concat((explorer.available_metrics || []).map(metric => `<option value="${esc(metric.id)}"${String(metric.id) === String(viewState.secondaryMetric || '') ? ' selected' : ''}>${esc(metric.label)}</option>`)).join('');
    const ueOptions = (explorer.ue_ids || []).map(ueid => `<option value="${esc(ueid)}"${String(ueid) === String(viewState.selectedUE) ? ' selected' : ''}>UE ${esc(ueid)}</option>`).join('');
    main.innerHTML = `<section class="panel"><h3>Run Selection</h3>${pageRunSelector('realtimeRunSelect', 'Selected Run', {showRunningBadge: true, runningOnly: false, note: 'Realtime defaults to an active running run when one exists. Stored runs remain selectable for post-run inspection.'})}</section><div class="grid four">${[['Run Status',(live.run || {}).status_text],['ResultOk',(live.summary || {}).result_ok],['RequiredFailureCount',(live.summary || {}).required_failure_count],['Configured UEs',(live.summary || {}).configured_users]].map(x => `<div class="tile metric"><h4>${esc(x[0])}</h4><div class="value">${esc(text(x[1] ?? 'unavailable'))}</div><p>canonical live payload</p></div>`).join('')}</div><section class="panel"><h3>Live UE Metric Explorer</h3><p class="subtle">X-axis defaults to slot. Y-axis metrics come only from the selected run's real serving-trace and waveform trial tables; missing metrics stay unavailable instead of being invented.</p><div class="toolbar"><label>X Axis<select id="liveXAxisSelect">${xAxisOptions}</select></label><label>Primary Y Metrics<select id="liveMetricSelect" multiple>${metricOptions}</select></label><label>Secondary Y<select id="liveSecondaryMetricSelect">${secondaryOptions}</select></label><label>Overlay<select id="liveOverlaySelect"><option value="per_ue_overlay"${viewState.overlayMode === 'per_ue_overlay' ? ' selected' : ''}>Per-UE overlay</option><option value="per_cell_overlay"${viewState.overlayMode === 'per_cell_overlay' ? ' selected' : ''}>Per-cell overlay</option></select></label><label>UE Scope<select id="liveUEScopeSelect"><option value="all_configured_ues"${viewState.scope === 'all_configured_ues' ? ' selected' : ''}>All configured UEs</option><option value="selected_ue_only"${viewState.scope === 'selected_ue_only' ? ' selected' : ''}>Selected UE</option></select></label><label>Selected UE<select id="liveUESelect"${viewState.scope === 'selected_ue_only' ? '' : ' disabled'}>${ueOptions}</select></label><label>Direction<select id="liveDirectionSelect"><option value="all"${viewState.direction === 'all' ? ' selected' : ''}>All</option><option value="DL"${viewState.direction === 'DL' ? ' selected' : ''}>DL</option><option value="UL"${viewState.direction === 'UL' ? ' selected' : ''}>UL</option><option value="channel"${viewState.direction === 'channel' ? ' selected' : ''}>Channel / measurement only</option></select></label><button type="button" id="liveMetricExportBtn">Export Filtered Rows</button></div><div id="liveMetricExplorer" class="chart-box"></div><div id="liveMetricSummary"></div></section><div class="split"><section class="panel"><h3>Frame / Slot / Stage</h3>${objectTable(rt.stage || {}, 'No canonical stage row is available.', {className:'tall-scroll', scrollKey:'realtime-stage'})}<h3>Live Scheduler Grants</h3>${rows([...(rt.pucch_grants || [])], 'No canonical scheduler grant rows are available in this live payload.', {className:'tall-scroll', scrollKey:'realtime-grants'})}</section><section class="panel"><h3>Control / PHY / Channel State</h3>${controlTruthNote()}${objectTable(rt.control_summary || {}, 'No control summary is available.', {className:'tall-scroll', scrollKey:'realtime-control-summary'})}${rows(rt.control_state_preview || [], 'No live control state rows are available.', {className:'tall-scroll', scrollKey:'realtime-control-state'})}${rows(rt.channel_array_consistency_preview || [], 'No channel state rows are available.', {className:'tall-scroll', scrollKey:'realtime-channel-state'})}</section></div>${controlTrialEvidencePanel()}${issueRegistryTable()}<section class="panel"><div class="toolbar"><h3 style="margin:0;">Logs / Event Stream</h3><input id="liveFilter" placeholder="Filter logs" value="${esc(state.filter)}"></div><div class="stream" data-scroll-key="realtime-logs">${logs.map(l => `<div class="stream-item ${/error/i.test(JSON.stringify(l)) ? 'log-error' : /warn/i.test(JSON.stringify(l)) ? 'log-warn' : ''}"><strong>${esc(l.source || l.module || l.created_utc || 'log')}</strong><br>${esc(l.message || l.line_text || l.log_message || JSON.stringify(l))}</div>`).join('') || unavailable('No logs are available for this run yet.')}</div></section>`;
    renderMetricExplorer('realtime');
  }
  function contractSlug(kind) { const parts = location.pathname.split('/').filter(Boolean); return parts[0] === kind ? (parts[1] || '') : ''; }
  function contractSections(kind) {
    const live = ((state.live || {}).contract_surface || {});
    const baseSections = (() => {
      const sections = live[kind];
      return Array.isArray(sections) && sections.length ? sections : (kind === 'reports' ? (root.report_sections || []) : (root.analytics_sections || []));
    })();
    const evidence = state.sectionEvidence;
    if (!evidence || evidence.kind !== kind || !evidence.section) return baseSections;
    const slug = String(evidence.slug || '');
    return baseSections.map(section => String(section.slug || '') === slug ? evidence.section : section);
  }
  function artifactMatches(table) {
    const live = state.live || {};
    const tableName = String(table.table_name || '');
    const sections = ((live.contract_surface || {}).reports || []).concat((live.contract_surface || {}).analytics || []);
    for (const section of sections) {
      const match = (section.tables || []).find(item => String(item.table_name || '') === tableName);
      if (match && match.evidence && Array.isArray(match.evidence.matches) && match.evidence.matches.length) return match.evidence.matches;
    }
    const tables = live.tables_all || [];
    const name = tableName.toLowerCase();
    const loose = name.replace(/^live_/, '').replace(/_table$/, '').replace(/_analytics$/, '').replace(/_view$/, '').replace(/_v$/, '');
    return tables.filter(a => { const path = String(a.logical_path || '').toLowerCase(); return path.includes(name) || (loose.length > 3 && path.includes(loose)); });
  }
  function statusBadge(label, cls) { return `<span class="badge ${cls || ''}">${esc(label)}</span>`; }
  function tableContractRows(section) {
    return (section.tables || []).map(t => {
      const evidence = t.evidence || {};
      const matches = Array.isArray(evidence.matches) ? evidence.matches : artifactMatches(t);
      const first = matches[0];
      const status = statusBadge(evidence.status_label || (first ? 'available' : 'unavailable'), evidence.status_class || (first ? 'good' : 'warn'));
      const lineage = first
        ? `<a class="button-link" href="${esc(first.view_url || first.download_url)}">Drilldown Raw Rows</a> <a class="button-link" href="${esc(first.download_url || first.view_url)}">Export Source</a><div class="small mono">${esc(evidence.reason || 'db_backed_contract_alias')}</div>`
        : `${esc(evidence.lineage_note || 'No canonical artifact or DB-backed view has been published for this run.')}<div class="small mono">${esc(evidence.reason || '')}</div>`;
      return `<tr><td><strong>${esc(t.table_name)}</strong><br><span class="small mono">${esc(t.mysql_view_name || '')}</span></td><td>${status}<br>${statusBadge('lineage required','')}</td><td>${esc((t.mandatory_context_columns || []).join(', '))}</td><td>${esc((t.required_columns || []).slice(0,18).join(', '))}${(t.required_columns || []).length > 18 ? ' ...' : ''}</td><td>${lineage}</td></tr>`;
    }).join('');
  }
  function chartContractRows(section) {
    return (section.charts || []).map(c => {
      const evidence = c.evidence || chartEvidenceFor(section, c);
      let lineage = esc(evidence.lineage_note || '');
      if (Array.isArray(evidence.matches) && evidence.matches.length) {
        const first = evidence.matches[0];
        if (first.download_url || first.view_url) lineage = `<a class="button-link" href="${esc(first.view_url || first.download_url)}">Open Evidence</a> <a class="button-link" href="${esc(first.download_url || first.view_url)}">Export Source</a><div class="small mono">${esc(evidence.lineage_note || '')}</div>`;
      }
      return `<tr><td><strong>${esc(c.chart_name)}</strong></td><td>${statusBadge(evidence.status_label || 'unavailable', evidence.status_class || 'warn')}</td><td>${esc(evidence.reason || c.default_status || '')}</td><td>${lineage}</td><td>${c.placeholder_chart_allowed ? statusBadge('placeholder allowed','bad') : statusBadge('no fake chart','good')}</td></tr>`;
    }).join('');
  }
  function applyContractControls() { const table = document.querySelector('[data-contract-table]'); if (!table) return; const q = String(document.getElementById('contractFilter')?.value || '').toLowerCase(); table.querySelectorAll('tbody tr').forEach(row => { row.style.display = !q || row.textContent.toLowerCase().includes(q) ? '' : 'none'; }); document.querySelectorAll('[data-contract-col]').forEach(cb => { const idx = Number(cb.dataset.contractCol); table.querySelectorAll('tr').forEach(row => { const cell = row.children[idx]; if (cell) cell.style.display = cb.checked ? '' : 'none'; }); }); }
  function sortContractTable(col) { const table = document.querySelector('[data-contract-table]'); if (!table) return; const body = table.tBodies[0]; [...body.rows].sort((a,b) => String(a.children[col]?.textContent || '').localeCompare(String(b.children[col]?.textContent || ''))).forEach(row => body.appendChild(row)); applyContractControls(); }
  function contractPage(kind) { const sections = contractSections(kind); const slug = contractSlug(kind); const section = sections.find(s => s.slug === slug); const titleText = kind === 'reports' ? 'Reports' : 'Analytics'; const subtitle = kind === 'reports' ? 'Real-time runtime truth only. Derived study views stay in Analytics.' : 'Derived post-processing study views only. Runtime truth stays in Reports.'; const selectorHtml = pageRunSelector(`${kind}RunSelect`, 'Selected Run', {showRunningBadge: kind === 'analytics', runningOnly: false, note: 'Switch runs here to inspect the same report or analytics family against a different truth-backed artifact set.'}); const issueHtml = kind === 'analytics' ? issueRegistryTable() : ''; title(titleText, subtitle); if (!section) { main.innerHTML = `${issueHtml}<section class="panel"><h3>${titleText}</h3>${selectorHtml}<p class="subtle">${subtitle}</p><div class="grid three">${sections.map(s => `<article class="tile"><span class="badge">${esc(s.domain)}</span><h4>${esc(s.title)}</h4><p>${esc((s.tables || []).length)} tables, ${esc((s.charts || []).length)} charts registered. Missing outputs stay unavailable.</p><a class="button-link" href="${esc(s.href)}">Open Section</a></article>`).join('')}</div></section>`; return; } const evidenceHtml = sectionEvidencePanel(section, kind); main.innerHTML = `${issueHtml}<section class="panel"><div class="toolbar"><a class="button-link" href="/${kind}">All ${titleText}</a><a class="button-link" href="/artifacts">Canonical Artifacts</a></div><h3>${esc(section.title)}</h3>${selectorHtml}<p class="subtle">${subtitle} Tables include mandatory direction/UE/BS/SFN/slot/symbol context and value_role/value_source/value_status semantics.</p><div class="toolbar">${statusBadge('no smoke data by default','good')}${statusBadge('no placeholder charts','good')}${statusBadge('lineage required','good')}</div></section>${evidenceHtml}<section class="panel"><div class="toolbar"><input id="contractFilter" placeholder="Filter tables, columns, status, lineage"><button type="button" data-contract-sort="0">Sort Tables</button><button type="button" data-contract-sort="1">Sort Status</button><label class="small"><input type="checkbox" data-contract-col="2" checked> Context</label><label class="small"><input type="checkbox" data-contract-col="3" checked> Columns</label><label class="small"><input type="checkbox" data-contract-col="4" checked> Drilldown / Export</label></div><h3>Tables / Views</h3><div class="table-wrap"><table data-contract-table><thead><tr><th>Table</th><th>Status</th><th>Mandatory Context</th><th>Columns</th><th>Drilldown / Export</th></tr></thead><tbody>${tableContractRows(section)}</tbody></table></div><h3>Charts / Graphs / Heatmaps</h3><div class="table-wrap"><table><thead><tr><th>Chart</th><th>Status</th><th>Rule</th><th>Lineage</th><th>Fake Data Guard</th></tr></thead><tbody>${chartContractRows(section)}</tbody></table></div></section>`; applyContractControls(); }
  function reports() { contractPage('reports'); }
  function analytics() {
    contractPage('analytics');
    if (!contractSlug('analytics')) {
      main.insertAdjacentHTML('afterbegin', `${analyticsExplorerPanel()}${analyticsPublishedChartsPanel()}${waveformArtifactPanel()}`);
      renderMetricExplorer('analytics');
      renderPublishedAnalyticsPanel();
    }
  }
  function artifactTable(items, empty) { if (!items || !items.length) return unavailable(empty); return `<div class="table-wrap"><table><thead><tr><th>Artifact</th><th>Kind</th><th>Section</th><th>Bytes</th><th>Created</th><th>Actions</th></tr></thead><tbody>${items.map(a => `<tr><td><strong>${esc(a.logical_path || a.artifact_id)}</strong><br><span class="small mono">artifact_id=${esc(a.artifact_id)}</span></td><td>${esc(a.artifact_kind || '')}</td><td>${esc(a.section || '')}</td><td>${esc(a.byte_size || '')}</td><td>${esc(a.created_utc || '')}</td><td><a class="button-link" href="${esc(a.view_url || a.download_url || '#')}">${String(a.artifact_kind || '').includes('table') ? 'Preview Table' : 'Open'}</a> <a class="button-link" href="${esc(a.download_url || a.view_url || '#')}">Download Full File</a></td></tr>`).join('')}</tbody></table></div>`; }
  function artifacts() { title('Artifact Explorer', 'Canonical artifact list, source, status, row-count hints, and previews.'); const tables = state.live ? (state.live.tables_all || []) : []; const images = state.live ? (state.live.images_all || []) : []; const runId = (state.live && state.live.run) ? state.live.run.run_id : 'unselected'; main.innerHTML = `<section class="panel"><h3>Canonical Tables For Run ${esc(runId)}</h3>${pageRunSelector('artifactsRunSelect', 'Selected Run', {runningOnly: false, note: 'Artifact Explorer stays truth-backed: it only lists persisted artifacts for the selected run.'})}<p class="subtle">${tables.length} table artifacts loaded from MySQL. Preview opens the browser table view; Download Full File retrieves the complete stored CSV.</p>${artifactTable(tables, 'No canonical table artifacts are available from the selected run.')}</section><section class="panel"><h3>Images And Other Visual Artifacts</h3>${artifactTable(images, 'No canonical image artifacts are available from the selected run.')}</section>`; }
  function parameters() { title('Parameter Catalog', 'Browser, YAML, resolved, applied, measured, source, owner, and role columns.'); const fs = state.fields; if (!state.configLoaded || !state.fieldsLoaded) { ensureConfigLoaded(true); ensureFieldsLoaded(true); main.innerHTML = `<section class="panel"><h3>Parameter Catalog</h3>${pageRunSelector('parametersRunSelect', 'Reference Run', {runningOnly: false, note: 'The editable config is browser-owned. The selected run gives the runtime context for any measured/applied columns that are available.'})}${unavailable('Parameter catalog is loading from the selected scenario config and resolved field list. The page will populate automatically once both payloads arrive.')}</section>`; return; } main.innerHTML = `<section class="panel"><h3>Parameter Catalog</h3>${pageRunSelector('parametersRunSelect', 'Reference Run', {runningOnly: false, note: 'The editable config is browser-owned. The selected run gives the runtime context for any measured/applied columns that are available.'})}<p class="subtle">${fs.length} exposed parameters loaded from the resolved/browser config.</p><div class="table-wrap"><table><thead><tr><th>parameter name</th><th>current value</th><th>requested value</th><th>resolved value</th><th>applied value</th><th>measured/runtime value</th><th>source</th><th>owner</th><th>role</th></tr></thead><tbody>${fs.map(f => `<tr><td><strong>${esc(f.label)}</strong><br><span class="small mono">${esc(f.path)}</span></td><td>${esc(text(get(state.config, f.path, f.current_value)))}</td><td>${inputFor(f)}</td><td>${esc(text(f.resolved_value))}</td><td>${esc(text(f.applied_value))}</td><td>${esc(text(f.measured_value))}</td><td>${esc(f.source)}</td><td>${esc(f.owner)}</td><td>${esc(f.role)}</td></tr>`).join('')}</tbody></table></div></section>`; }
  function runActions(r, next) { const id = esc(r.run_id); return `<div class="toolbar"><a class="button-link" href="/artifacts?run_id=${id}">Show Output</a><a class="button-link" href="/artifacts?run_id=${id}">View Tables</a><a class="button-link" href="/realtime?run_id=${id}">Live Data</a><a class="button-link" href="/analytics?run_id=${id}">Analytics</a><button type="button" data-compare-baseline="${id}">Add Baseline</button><button type="button" data-compare-candidate="${id}">Add Candidate</button><form method="post" action="/admin/delete-run" class="inline-form" onsubmit="return confirm('Delete run ${id} and all its database rows, logs, runtime YAML, stored artifacts, and disk files?');"><input type="hidden" name="run_id" value="${id}"><input type="hidden" name="next" value="${esc(next)}"><button type="submit">Delete Run</button></form></div>`; }
  function runsTable(runList, empty, next, scrollKey) { const runRows = (runList || []).map(r => `<tr><td><strong>${esc(r.run_id)}</strong></td><td>${esc(r.run_tag || '')}<br><span class="small">${esc(r.scenario_id || r.scenario_name || '')}</span></td><td>${esc(r.profile_name || '')}</td><td>${esc(r.status_text || '')}</td><td>${esc(r.created_utc || '')}</td><td>${esc(r.updated_utc || '')}</td><td>${runActions(r, next)}</td></tr>`).join(''); return scrollWrap(`<table><thead><tr><th>Run</th><th>Tag / Scenario</th><th>Profile</th><th>Status</th><th>Created</th><th>Updated</th><th>Options</th></tr></thead><tbody>${runRows || `<tr><td colspan="7">${unavailable(empty)}</td></tr>`}</tbody></table>`, {className:'page-table', scrollKey: scrollKey || 'runs-table'}); }
  function runsPage() { title('Recent Runs', 'Recent MySQL-backed runs with output, table, compare, and delete actions.'); const recent = (state.runs || []).slice(0,25); main.innerHTML = `<section class="panel"><h3>Recent Runs</h3><p class="subtle">${recent.length} recent run records shown. Open Previous Runs to browse the full loaded run list.</p><div class="toolbar"><a class="button-link" href="/previous-runs">Previous Runs</a><a class="button-link" href="/compare">Compare Runs</a></div><div id="recentRunsTable">${runsTable(recent, 'No recent runs are available from MySQL.', '/runs', 'recent-runs-table')}</div></section>`; }
  function previousRunsPage() { title('Previous Runs', 'Browse previous runs, view all canonical tables, delete a run and its files, or stage runs for comparison.'); const allRuns = state.runs || []; main.innerHTML = `<section class="panel"><h3>Previous Runs</h3><p class="subtle">${allRuns.length} run records loaded from MySQL. Show Output and View Tables open canonical DB-backed artifact lists for the selected run.</p><div class="toolbar"><a class="button-link" href="/runs">Recent Runs</a><a class="button-link" href="/compare">Compare Runs</a></div><div id="previousRunsTable">${runsTable(allRuns, 'No previous runs are available from MySQL.', '/previous-runs', 'previous-runs-table')}</div></section>`; }
  function compareOptions(selected) { return `<option value="">Select run</option>${(state.runs || []).map(r => `<option value="${esc(r.run_id)}"${String(r.run_id) === String(selected) ? ' selected' : ''}>Run ${esc(r.run_id)} - ${esc(r.run_tag || r.scenario_id || r.status_text || '')}</option>`).join('')}`; }
  function compareMetricRows() { const a = state.compareBaselineLive; const b = state.compareCandidateLive; if (!a || !b) return `<tr><td colspan="4">${state.compareLoading ? 'Loading canonical live payloads...' : 'Select baseline and candidate, then click Compare.'}</td></tr>`; const specs = [['Status','run.status_text'],['ResultOk','summary.result_ok'],['RequiredFailureCount','summary.required_failure_count'],['RuntimeTruthContractOk','summary.runtime_truth_contract_ok'],['Configured UEs','summary.configured_users'],['Artifacts','counts.artifacts_total'],['Tables','counts.tables_total'],['Images','counts.images_total'],['Logs','counts.logs_total'],['Bytes','counts.bytes_total']]; return specs.map(([label,path]) => { const av = get(a, path, 'unavailable'); const bv = get(b, path, 'unavailable'); const na = Number(av); const nb = Number(bv); const delta = Number.isFinite(na) && Number.isFinite(nb) ? (nb - na) : (String(av) === String(bv) ? 'same' : 'changed'); return `<tr><td>${esc(label)}</td><td>${esc(text(av))}</td><td>${esc(text(bv))}</td><td>${esc(text(delta))}</td></tr>`; }).join(''); }
  function refreshRunsSurfaces() {
    if (interactionLocked()) return;
    const scrollSnapshot = captureScrollState();
    const selectorState = new Map([...document.querySelectorAll('[data-run-selector="true"]')].map(select => [select.id, select.value]));
    const homeBox = document.getElementById('homeRecentRuns');
    if (homeBox) homeBox.innerHTML = rows((state.runs || []).slice(0,10), 'No recent runs are available from MySQL.', {className:'page-table', scrollKey:'home-recent-runs'});
    const recentBox = document.getElementById('recentRunsTable');
    if (recentBox) recentBox.innerHTML = runsTable((state.runs || []).slice(0,25), 'No recent runs are available from MySQL.', '/runs', 'recent-runs-table');
    const previousBox = document.getElementById('previousRunsTable');
    if (previousBox) previousBox.innerHTML = runsTable(state.runs || [], 'No previous runs are available from MySQL.', '/previous-runs', 'previous-runs-table');
    document.querySelectorAll('[data-run-selector="true"]').forEach(select => {
      const selected = selectorState.get(select.id) || select.value || selectedRunId();
      const runningOnly = select.id === 'realtimeRunSelect';
      select.innerHTML = runSelectOptions(selected, {runningOnly, preferActive: runningOnly});
      if (selected) select.value = String(selected);
    });
    restoreScrollState(scrollSnapshot);
  }
  function loadComparePayloads() { if (!state.compareBaseline || !state.compareCandidate) { compare(); return; } state.compareLoading = true; compare(); Promise.all([fetch(`/api/run/${encodeURIComponent(state.compareBaseline)}/live`, {cache:'no-store'}).then(r => r.ok ? r.json() : null).catch(() => null), fetch(`/api/run/${encodeURIComponent(state.compareCandidate)}/live`, {cache:'no-store'}).then(r => r.ok ? r.json() : null).catch(() => null)]).then(([a,b]) => { state.compareBaselineLive = a; state.compareCandidateLive = b; state.compareLoading = false; state.page = 'compare'; render({preserveScroll:true}); }); }
  function compare() { title('Compare Runs', 'Baseline and candidate delta analysis from canonical live payloads and artifact counts.'); const a = state.compareBaselineLive; const b = state.compareCandidateLive; main.innerHTML = `<section class="panel"><h3>Compare Runs</h3><p class="subtle">Use Add Baseline / Add Candidate from Previous Runs, or select runs here. Comparison fetches /api/run/&lt;id&gt;/live for both runs.</p><div class="toolbar"><label>Baseline<select id="compareBaselineSelect">${compareOptions(state.compareBaseline)}</select></label><label>Candidate<select id="compareCandidateSelect">${compareOptions(state.compareCandidate)}</select></label><button type="button" id="compareRunsBtn">Compare</button><a class="button-link" href="/previous-runs">Previous Runs</a></div>${scrollWrap(`<table><thead><tr><th>Metric</th><th>Baseline</th><th>Candidate</th><th>Delta</th></tr></thead><tbody>${compareMetricRows()}</tbody></table>`, {className:'page-table', scrollKey:'compare-metrics'})}</section><section class="panel"><h3>Compared Outputs</h3><div class="split"><div><h4>Baseline ${esc(state.compareBaseline || '')}</h4>${a ? artifactTable((a.tables_all || []).slice(0,50), 'No baseline canonical tables are available.') : unavailable('Baseline payload has not been loaded.')}</div><div><h4>Candidate ${esc(state.compareCandidate || '')}</h4>${b ? artifactTable((b.tables_all || []).slice(0,50), 'No candidate canonical tables are available.') : unavailable('Candidate payload has not been loaded.')}</div></div></section>`; }
  function mergeLivePayload(previous, incoming) {
    if (!previous) return incoming;
    if (!incoming) return previous;
    const merged = { ...previous, ...incoming };
    const stickyKeys = ['tables_all', 'tables_recent', 'tables_summary', 'images_all', 'images_recent', 'output_coverage', 'feature_policy', 'contract_surface', 'output_contract', 'timing', 'map', 'metric_explorer', 'debug'];
    stickyKeys.forEach((key) => {
      if (incoming[key] === undefined) merged[key] = previous[key];
    });
    merged.charts = { ...(previous.charts || {}), ...(incoming.charts || {}) };
    return merged;
  }
  async function fetchCanonicalLivePayload(runId) {
    const lite = await fetch(`/api/run/${encodeURIComponent(runId)}/live?lite=1`, {cache:'no-store'}).then(r => r.ok ? r.json() : null).catch(() => null);
    if (!lite) return null;
    const previousRunId = String((((state.liveFullPayload || {}).run) || {}).run_id || '');
    const needsFull = !state.liveFullPayload || previousRunId !== String(runId) || (lite.artifact_version && lite.artifact_version !== state.liveArtifactVersion);
    if (!needsFull) {
      const merged = mergeLivePayload(state.liveFullPayload, lite);
      state.liveFullPayload = merged;
      return merged;
    }
    const merged = previousRunId === String(runId) ? mergeLivePayload(state.liveFullPayload, lite) : lite;
    const fullFetchKey = `${String(runId)}|${String(lite.artifact_version || '')}`;
    if (state.liveFullFetchPending !== fullFetchKey) {
      state.liveFullFetchPending = fullFetchKey;
      fetch(`/api/run/${encodeURIComponent(runId)}/live`, {cache:'no-store'})
        .then(r => r.ok ? r.json() : null)
        .then(full => {
          if (!full) return;
          state.liveFullPayload = full;
          state.live = full;
          state.liveVersion = String(full.payload_version || '');
          state.liveArtifactVersion = String(full.artifact_version || '');
          if (!interactionLocked() && ['realtime','reports','analytics','artifacts','parameters'].includes(state.page)) render({preserveScroll:true});
        })
        .catch(() => {})
        .finally(() => {
          if (state.liveFullFetchPending === fullFetchKey) state.liveFullFetchPending = '';
        });
    }
    state.liveFullPayload = merged;
    return merged;
  }
  async function fetchContractSectionEvidence(kind) {
    const slug = contractSlug(kind);
    const runId = selectedRunId();
    if (!slug || !runId || !['reports','analytics'].includes(String(kind || ''))) {
      state.sectionEvidence = null;
      state.sectionEvidenceVersion = '';
      return null;
    }
    const payload = await fetch(`/api/run/${encodeURIComponent(runId)}/contract-section?kind=${encodeURIComponent(kind)}&slug=${encodeURIComponent(slug)}`, {cache:'no-store'})
      .then(r => r.ok ? r.json() : null)
      .catch(() => null);
    if (!payload) return null;
    state.sectionEvidence = payload;
    state.sectionEvidenceVersion = `${payload.kind || ''}|${payload.slug || ''}|${payload.artifact_version || ''}`;
    return payload;
  }
  function render(options) { const opts = options || {}; const scrollSnapshot = opts.preserveScroll ? captureScrollState() : null; chrome(); if (state.page === 'home' || state.page === 'architecture') home(); else if (state.page === 'reports') reports(); else if (state.page === 'runs') runsPage(); else if (state.page === 'previous_runs') previousRunsPage(); else if (state.page === 'geometry') geometry(); else if (state.page === 'l1_phy') l1(); else if (state.page === 'realtime') realtime(); else if (state.page === 'analytics') analytics(); else if (state.page === 'artifacts') artifacts(); else if (state.page === 'parameters') parameters(); else if (state.page === 'compare') compare(); else domain(state.page); renderBlock(state.selectedBlock); if (scrollSnapshot) restoreScrollState(scrollSnapshot); else window.requestAnimationFrame(() => window.scrollTo(0, 0)); }
  function refreshRunsList(shouldRender) {
    return fetch('/api/runs?limit=200', {cache:'no-store'})
      .then(r => r.ok ? r.json() : {runs:[]})
      .catch(() => ({runs:[]}))
      .then(payload => {
        const nextRuns = payload.runs || [];
        const nextDigest = runsDigest(nextRuns);
        const changed = nextDigest !== state.runsDigest;
        state.runs = nextRuns;
        state.runsDigest = nextDigest;
        if (shouldRender && changed && !interactionLocked()) {
          if (state.page === 'compare') compare();
          else if (document.querySelector('[data-run-selector="true"]') || ['home','runs','previous_runs'].includes(state.page)) refreshRunsSurfaces();
        }
        return state.runs;
      });
  }
  document.addEventListener('click', e => {
    const target = eventElement(e.target);
    if (!target) return;
    const p = target.closest('[data-page]');
    if (p) {
      const nextPage = p.dataset.page;
      const nextHref = p.getAttribute('href');
      if ((nextPage === 'reports' || nextPage === 'analytics') && !(((root.report_sections || []).length) || ((root.analytics_sections || []).length))) { window.location.href = nextHref; return; }
      e.preventDefault();
      state.page = nextPage;
      history.pushState({page:state.page}, '', nextHref);
      render({preserveScroll:false});
      if (pageNeedsConfigModel(state.page)) ensureConfigLoaded(true);
      if (pageNeedsFieldCatalog(state.page)) ensureFieldsLoaded(true);
    }
    const m = target.closest('[data-mode]');
    if (m) { state.mode = m.dataset.mode; set(state.config, 'run_control.execution_mode', state.mode); render({preserveScroll:false}); }
    const b = target.closest('[data-block]');
    if (b) { state.selectedBlock = (root.architecture || []).find(x => x.id === b.dataset.block); if (state.selectedBlock && state.selectedBlock.route) { const nav = (root.nav || []).find(n => state.selectedBlock.route.startsWith(n.href)); if (nav) state.page = nav.id; } render({preserveScroll:false}); }
    const ph = target.closest('[data-phy]');
    if (ph) { for (const f of root.phy_families || []) { const found = (f.blocks || []).find(x => x.id === ph.dataset.phy); if (found) state.selectedBlock = found; } renderBlock(state.selectedBlock); }
    const fam = target.closest('[data-family]');
    if (fam) { state.activeFamily = fam.dataset.family; l1(); }
    const baseline = target.closest('[data-compare-baseline]');
    if (baseline) { state.compareBaseline = baseline.dataset.compareBaseline; state.compareBaselineLive = null; storage.set('sixgr_compare_baseline', state.compareBaseline); state.page = 'compare'; history.pushState({page:'compare'}, '', '/compare'); loadComparePayloads(); }
    const candidate = target.closest('[data-compare-candidate]');
    if (candidate) { state.compareCandidate = candidate.dataset.compareCandidate; state.compareCandidateLive = null; storage.set('sixgr_compare_candidate', state.compareCandidate); state.page = 'compare'; history.pushState({page:'compare'}, '', '/compare'); loadComparePayloads(); }
    const contractSort = target.closest('[data-contract-sort]');
    if (contractSort) sortContractTable(Number(contractSort.dataset.contractSort || 0));
    const publishedChart = target.closest('[data-analytics-published-chart]');
    if (publishedChart) { state.analyticsPublishedChartId = publishedChart.dataset.analyticsPublishedChart; renderPublishedAnalyticsPanel(); }
    const msg = document.getElementById('messageBanner');
    if (target.id === 'compareRunsBtn') loadComparePayloads();
    if (target.id === 'openScenarioBtn') location.href = `/home?scenario=${encodeURIComponent(document.getElementById('scenarioSelect').value)}`;
    if (target.id === 'loadConfigJsonBtn') document.getElementById('configJsonFileInput').click();
    if (target.id === 'newScenarioBtn') { state.page = 'scenario'; render({preserveScroll:false}); ensureConfigLoaded(true); ensureFieldsLoaded(true); if (msg) { msg.textContent = 'New scenario draft is active in the browser. Run Scenario and Download Config JSON will use the edited config model.'; msg.classList.remove('hidden'); } }
    if (target.id === 'validateBtn') { ensureConfigLoaded(false).then(() => { const contract = scenarioLaunchContract(); if (msg) { msg.textContent = state.mode !== wired ? `${state.mode} is configurable here, but only LLS is launch-enabled from /run in this pass.` : (contract.launchAllowed ? `Browser validation passed for the editable config surface. Launch contract: ${contract.presentationLabel || contract.launchContract}. MATLAB runtime validation still occurs during /run.` : `Browser validation found a launch-contract blocker: ${contract.launchReason || 'selected scenario is blocked.'}`); msg.classList.remove('hidden'); } }); }
    if (target.id === 'saveScenarioBtn') { ensureConfigLoaded(false).then(() => { storage.set('sixgr_product_config', JSON.stringify(state.config)); if (msg) { msg.textContent = 'Scenario draft saved in browser storage.'; msg.classList.remove('hidden'); } }); }
    if (target.id === 'downloadConfigBtn') { ensureConfigLoaded(false).then(() => { updateRunPayload(); const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([JSON.stringify(state.config, null, 2)], {type:'application/json'})); a.download = 'sixgr_final_config.json'; a.click(); if (msg) { msg.textContent = 'Final browser config JSON downloaded for verification.'; msg.classList.remove('hidden'); } }); }
    if (target.id === 'liveMetricExportBtn') { exportMetricExplorer('realtime'); }
    if (target.id === 'analyticsMetricExportBtn') { exportMetricExplorer('analytics'); }
  });
  document.addEventListener('change', e => {
    const target = eventElement(e.target);
    if (!target) return;
    if (isInteractiveElement(target)) markUserInteracting(30000);
    if (target.id === 'configJsonFileInput') { loadConfigFile((target.files || [])[0]); target.value = ''; return; }
    if (target.id === 'compareBaselineSelect') { state.compareBaseline = target.value; state.compareBaselineLive = null; storage.set('sixgr_compare_baseline', state.compareBaseline); compare(); return; }
    if (target.id === 'compareCandidateSelect') { state.compareCandidate = target.value; state.compareCandidateLive = null; storage.set('sixgr_compare_candidate', state.compareCandidate); compare(); return; }
    if (target.matches('[data-run-selector="true"]')) { navigateWithRun(target.value || ''); return; }
    if (target.id === 'liveXAxisSelect') { state.metricExplorer.xAxis = target.value || 'slot'; refreshRealtimeExplorerUI(); return; }
    if (target.id === 'liveMetricSelect') { state.metricExplorer.metrics = selectValues(target); refreshRealtimeExplorerUI(); return; }
    if (target.id === 'liveSecondaryMetricSelect') { state.metricExplorer.secondaryMetric = target.value || ''; refreshRealtimeExplorerUI(); return; }
    if (target.id === 'liveOverlaySelect') { state.metricExplorer.overlayMode = target.value || 'per_ue_overlay'; refreshRealtimeExplorerUI(); return; }
    if (target.id === 'liveUEScopeSelect') { state.metricExplorer.scope = target.value || 'all_configured_ues'; refreshRealtimeExplorerUI(); return; }
    if (target.id === 'liveUESelect') { state.metricExplorer.selectedUE = target.value || ''; refreshRealtimeExplorerUI(); return; }
    if (target.id === 'liveDirectionSelect') { state.metricExplorer.direction = target.value || 'all'; refreshRealtimeExplorerUI(); return; }
    if (target.id === 'analyticsXAxisSelect') { state.analyticsExplorer.xAxis = target.value || 'slot'; refreshAnalyticsExplorerUI(); return; }
    if (target.id === 'analyticsMetricSelect') { state.analyticsExplorer.metrics = selectValues(target); refreshAnalyticsExplorerUI(); return; }
    if (target.id === 'analyticsSecondaryMetricSelect') { state.analyticsExplorer.secondaryMetric = target.value || ''; refreshAnalyticsExplorerUI(); return; }
    if (target.id === 'analyticsOverlaySelect') { state.analyticsExplorer.overlayMode = target.value || 'per_ue_overlay'; refreshAnalyticsExplorerUI(); return; }
    if (target.id === 'analyticsUEScopeSelect') { state.analyticsExplorer.scope = target.value || 'all_configured_ues'; refreshAnalyticsExplorerUI(); return; }
    if (target.id === 'analyticsUESelect') { state.analyticsExplorer.selectedUE = target.value || ''; refreshAnalyticsExplorerUI(); return; }
    if (target.id === 'analyticsDirectionSelect') { state.analyticsExplorer.direction = target.value || 'all'; refreshAnalyticsExplorerUI(); return; }
    if (target.closest('[data-contract-col]')) { applyContractControls(); return; }
    const i = target.closest('[data-config-input]');
    if (i) { set(state.config, i.dataset.path, parseValue(i)); updateRunPayload(); }
  });
  document.addEventListener('input', e => { const target = eventElement(e.target); if (!target) return; if (isInteractiveElement(target)) markUserInteracting(30000); if (target.id === 'liveFilter') { state.filter = target.value; if (state.page === 'realtime') render({preserveScroll:true}); } if (target.id === 'contractFilter') applyContractControls(); });
  document.addEventListener('focusin', e => { if (isInteractiveElement(e.target)) markUserInteracting(30000); }, true);
  document.addEventListener('pointerdown', e => { if (isInteractiveElement(e.target)) markUserInteracting(30000); }, true);
  document.addEventListener('wheel', e => { if (isInteractiveElement(e.target)) markUserInteracting(30000); }, {passive: true, capture: true});
  document.addEventListener('scroll', e => { if (isInteractiveElement(e.target)) markUserInteracting(30000); }, true);
  document.addEventListener('keydown', e => { if (isInteractiveElement(e.target)) markUserInteracting(30000); }, true);
  const runForm = document.getElementById('runForm');
  if (runForm) runForm.addEventListener('submit', e => { updateRunPayload(); const contract = scenarioLaunchContract(); if (state.mode !== wired || !contract.launchAllowed) { e.preventDefault(); alert(state.mode !== wired ? `${state.mode} is not launch-enabled from /run in this pass. Switch to LLS.` : (contract.launchReason || 'Selected scenario is blocked by the browser launch contract.')); } });
  render({preserveScroll:false});
  if (pageNeedsConfigModel(state.page) && !state.configLoaded) window.setTimeout(() => { ensureConfigLoaded(true); }, 0);
  if (pageNeedsFieldCatalog(state.page)) window.setTimeout(() => { ensureFieldsLoaded(true); }, 0);
  refreshRunsList(true).then(runRows => {
    const id = preferredRunId(runRows);
    const contractKind = state.page === 'reports' ? 'reports' : (state.page === 'analytics' ? 'analytics' : '');
    if (contractKind) {
      fetchContractSectionEvidence(contractKind)
        .then(() => {
          if (!interactionLocked() && ['reports','analytics'].includes(state.page)) render({preserveScroll:true});
        })
        .catch(() => {});
    }
    return id ? fetchCanonicalLivePayload(id) : null;
  }).then((live) => {
    state.live = live;
    state.liveVersion = String((live || {}).payload_version || '');
    state.liveArtifactVersion = String((live || {}).artifact_version || '');
    if (!interactionLocked()) render({preserveScroll:true});
    setInterval(() => {
      const runId = selectedRunId();
      if (!runId) return;
      const contractKind = state.page === 'reports' ? 'reports' : (state.page === 'analytics' ? 'analytics' : '');
      if (contractKind) {
        const previousSectionVersion = state.sectionEvidenceVersion;
        fetchContractSectionEvidence(contractKind)
          .then(() => {
            if (state.sectionEvidenceVersion !== previousSectionVersion && !interactionLocked() && ['reports','analytics'].includes(state.page)) render({preserveScroll:true});
          })
          .catch(() => {});
      }
      fetchCanonicalLivePayload(runId)
        .then((x) => {
          if (!x) return;
          const nextVersion = String(x.payload_version || '');
          const nextRunId = String((((x || {}).run) || {}).run_id || '');
          const changed = nextVersion !== state.liveVersion || nextRunId !== String((((state.live || {}).run) || {}).run_id || '');
          state.live = x;
          state.liveVersion = nextVersion;
          state.liveArtifactVersion = String(x.artifact_version || '');
          if (changed && ['realtime','reports','analytics','artifacts','parameters'].includes(state.page) && !interactionLocked()) render({preserveScroll:true});
        })
        .catch(() => {});
    }, Number(root.poll_ms || 1000));
    setInterval(() => { refreshRunsList(true); }, Math.max(Number(root.poll_ms || 1000) * 10, 15000));
  });
});
</script>
"""


def home_page_script(
    config_payload: dict[str, Any],
    groups: list[str],
    selected_scenario: str,
    scenario_contract: dict[str, Any],
) -> str:
    return f"""
<script>
const CONFIG_STATE = {json.dumps(config_payload, ensure_ascii=False)};
const HOME_GROUPS = {json.dumps(groups, ensure_ascii=False)};
const EXECUTION_MODE_OPTIONS = {json.dumps(BROWSER_EXECUTION_MODE_OPTIONS, ensure_ascii=False)};
const EXECUTION_MODE_NOTES = {json.dumps(BROWSER_EXECUTION_MODE_NOTES, ensure_ascii=False)};
const FULLY_WIRED_EXECUTION_MODE = {json.dumps(FULLY_WIRED_BROWSER_EXECUTION_MODE, ensure_ascii=False)};
const SELECTED_SCENARIO = {json.dumps(selected_scenario, ensure_ascii=False)};
const INITIAL_SCENARIO_CONTRACT = {json.dumps(scenario_contract, ensure_ascii=False)};
const WAVEFORM_TRUTH_IDENTITY_TOKENS = {json.dumps(WAVEFORM_TRUTH_IDENTITY_TOKENS, ensure_ascii=False)};
function homeEsc(value) {{
  return String(value ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}}
function ensureExecutionMode() {{
  if (typeof CONFIG_STATE.run_control !== 'object' || CONFIG_STATE.run_control === null) CONFIG_STATE.run_control = {{}};
  let mode = String(CONFIG_STATE.run_control.execution_mode || 'LLS').trim().toUpperCase();
  if (!EXECUTION_MODE_OPTIONS.includes(mode)) mode = 'LLS';
  CONFIG_STATE.run_control.execution_mode = mode;
  return mode;
}}
function currentScenarioLaunchContract() {{
  const meta = (typeof CONFIG_STATE.meta === 'object' && CONFIG_STATE.meta !== null) ? CONFIG_STATE.meta : {{}};
  const scenario = (typeof CONFIG_STATE.scenario === 'object' && CONFIG_STATE.scenario !== null) ? CONFIG_STATE.scenario : {{}};
  const runnerProfile = String(scenario.runner_profile || INITIAL_SCENARIO_CONTRACT.runner_profile || '').trim();
  const runnerProfileToken = runnerProfile.toLowerCase();
  const tags = Array.isArray(meta.tags) ? meta.tags : (Array.isArray(INITIAL_SCENARIO_CONTRACT.tags) ? INITIAL_SCENARIO_CONTRACT.tags : []);
  const identityValues = [SELECTED_SCENARIO, meta.scenario_id, meta.scenario_group, meta.scenario_name, meta.baseline_reference_name, scenario.name].concat(tags);
  const claimsWaveformTruth = identityValues.some((value) => {{
    const lowered = String(value || '').trim().toLowerCase();
    return lowered && WAVEFORM_TRUTH_IDENTITY_TOKENS.some((token) => lowered.includes(token));
  }});
  const usersEnabled = Boolean(((typeof CONFIG_STATE.users === 'object' && CONFIG_STATE.users !== null) ? CONFIG_STATE.users.enabled : false));
  const executionModel = String(((typeof CONFIG_STATE.users === 'object' && CONFIG_STATE.users !== null) ? CONFIG_STATE.users.execution_model : (INITIAL_SCENARIO_CONTRACT.execution_model || '')) || '').trim().toLowerCase();
  const userCount = [CONFIG_STATE?.users?.n_users, CONFIG_STATE?.deployment_topology?.num_ues, INITIAL_SCENARIO_CONTRACT.user_count || 0].reduce((best, value) => {{
    const numeric = Number(value);
    return Number.isFinite(numeric) && numeric > best ? numeric : best;
  }}, 0);
  const totalSlots = [CONFIG_STATE?.run_control?.total_slots, CONFIG_STATE?.simulation?.n_slots, INITIAL_SCENARIO_CONTRACT.requested_total_slots || 0].reduce((best, value) => {{
    const numeric = Number(value);
    return Number.isFinite(numeric) && numeric > best ? numeric : best;
  }}, 0);
  if (runnerProfileToken === 'waveform_bundle') {{
    if (usersEnabled && executionModel === 'slot_coupled_truth' && userCount > 1) {{
      const duplexMode = String(CONFIG_STATE?.frequency?.duplex_mode || CONFIG_STATE?.global_radio_scope?.duplex_mode || CONFIG_STATE?.phy?.duplex?.mode || CONFIG_STATE?.scenario?.duplexMode || INITIAL_SCENARIO_CONTRACT.duplex_mode || 'TDD').trim().toUpperCase() || 'TDD';
      const tddPattern = String(CONFIG_STATE?.frame_timing?.tdd_pattern || CONFIG_STATE?.frame?.tdd_pattern || CONFIG_STATE?.phy?.duplex?.tddPattern || CONFIG_STATE?.scenario?.tddPattern || INITIAL_SCENARIO_CONTRACT.tdd_pattern || 'DDDSU').trim().toUpperCase() || 'DDDSU';
      if (duplexMode === 'TDD') {{
        return {{
          launchAllowed: true,
          launchContract: 'waveform_bundle_truth',
          presentationLabel: 'Waveform bundle truth',
          launchReason: `Waveform bundle launch is truth-ready for the coupled multi-user TDD path: the MATLAB runtime now preserves canonical slot accounting and applies the configured TDD duplex pattern inside the coupled waveform loop. Requested users=${{userCount}}, total_slots=${{totalSlots || 'unavailable'}}, duplex_mode=${{duplexMode}}, tdd_pattern=${{tddPattern || 'unavailable'}}.`,
          runnerProfile,
          claimsWaveformTruth,
        }};
      }}
    }}
    return {{
      launchAllowed: true,
      launchContract: 'waveform_bundle_truth',
      presentationLabel: 'Waveform bundle truth',
      launchReason: `Waveform bundle launch is truth-ready for the coupled multi-user TDD path: the MATLAB runtime now preserves canonical slot accounting and applies the configured TDD duplex pattern inside the coupled waveform loop. Requested users=${{userCount || 'unavailable'}}, total_slots=${{totalSlots || 'unavailable'}}, duplex_mode=${{String(CONFIG_STATE?.frequency?.duplex_mode || CONFIG_STATE?.global_radio_scope?.duplex_mode || CONFIG_STATE?.phy?.duplex?.mode || CONFIG_STATE?.scenario?.duplexMode || INITIAL_SCENARIO_CONTRACT.duplex_mode || 'TDD').trim().toUpperCase() || 'TDD'}}, tdd_pattern=${{String(CONFIG_STATE?.frame_timing?.tdd_pattern || CONFIG_STATE?.frame?.tdd_pattern || CONFIG_STATE?.phy?.duplex?.tddPattern || CONFIG_STATE?.scenario?.tddPattern || INITIAL_SCENARIO_CONTRACT.tdd_pattern || 'DDDSU').trim().toUpperCase() || 'DDDSU'}}.`,
      runnerProfile,
      claimsWaveformTruth,
    }};
  }}
  if (runnerProfileToken === 'system_level_lls') {{
    if (claimsWaveformTruth) {{
      return {{
        launchAllowed: false,
        launchContract: 'blocked_mislabeled_waveform_truth',
        presentationLabel: 'System-level LLS waveform-backed replay',
        launchReason: "Scenario identity still claims waveform truth, but scenario.runner_profile resolves to 'system_level_lls'. Browser /run stays blocked until the config truly dispatches to waveform_bundle or the scenario is renamed honestly.",
        runnerProfile,
        claimsWaveformTruth,
      }};
    }}
    return {{
      launchAllowed: true,
      launchContract: 'system_level_lls_waveform_backed_replay',
      presentationLabel: 'System-level LLS waveform-backed replay',
      launchReason: 'Scenario is honestly labeled for system_level_lls. Browser /run will launch the waveform-backed system-level replay path, not waveform_bundle truth.',
      runnerProfile,
      claimsWaveformTruth,
    }};
  }}
  if (claimsWaveformTruth && runnerProfileToken !== 'waveform_bundle') {{
    return {{
      launchAllowed: false,
      launchContract: 'blocked_mislabeled_waveform_truth',
      presentationLabel: runnerProfile || 'Unconfigured runner',
      launchReason: `Scenario identity claims waveform truth, but scenario.runner_profile is not 'waveform_bundle' (resolved value: ${{runnerProfile || 'unconfigured'}}). Browser /run stays blocked until the launch contract is truthful.`,
      runnerProfile,
      claimsWaveformTruth,
    }};
  }}
  return {{
    launchAllowed: true,
    launchContract: INITIAL_SCENARIO_CONTRACT.launch_contract || 'honest_non_waveform_bundle_runner',
    presentationLabel: runnerProfile || INITIAL_SCENARIO_CONTRACT.presentation_label || 'Unconfigured runner',
    launchReason: INITIAL_SCENARIO_CONTRACT.launch_reason || 'Browser /run will follow the configured scenario.runner_profile honestly.',
    runnerProfile,
    claimsWaveformTruth,
  }};
}}
function activateHomeGroup(groupName) {{
  document.querySelectorAll('[data-home-group-button]').forEach((el) => el.classList.toggle('active', el.dataset.homeGroupButton === groupName));
  document.querySelectorAll('[data-home-group-panel]').forEach((el) => el.classList.toggle('active', el.dataset.homeGroupPanel === groupName));
}}
function applyHomeSearch() {{
  const query = String(document.getElementById('homeSearch')?.value || '').trim().toLowerCase();
  const tokens = query ? query.split(/\\s+/).filter(Boolean) : [];
  let visible = 0;
  const rows = document.querySelectorAll('[data-field-row]');
  rows.forEach((row) => {{
    const haystack = String(row.dataset.search || '');
    const match = !tokens.length || tokens.every((token) => haystack.includes(token));
    row.classList.toggle('hidden', !match);
    if (match) visible += 1;
  }});
  const summary = document.getElementById('fieldCount');
  if (summary) summary.textContent = `${{visible}} / ${{rows.length}} parameters visible`;
}}
function setByPath(root, path, value) {{
  const parts = path.split('.');
  let node = root;
  for (let i = 0; i < parts.length - 1; i += 1) {{
    const key = parts[i];
    if (typeof node[key] !== 'object' || node[key] === null) node[key] = {{}};
    node = node[key];
  }}
  node[parts[parts.length - 1]] = value;
}}
function parseFieldValue(input) {{
  const kind = input.dataset.kind || 'text';
  const raw = input.value;
  if (kind === 'bool') return String(raw).toLowerCase() === 'true';
  if (kind === 'int') {{
    const parsed = parseInt(raw, 10);
    return Number.isNaN(parsed) ? 0 : parsed;
  }}
  if (kind === 'float') {{
    const parsed = parseFloat(raw);
    return Number.isNaN(parsed) ? 0 : parsed;
  }}
  if (kind === 'json') {{
    try {{ return JSON.parse(raw); }} catch (err) {{ return raw; }}
  }}
  return raw;
}}
function refreshConfigPreview() {{
  const preview = document.getElementById('configPreview');
  if (preview) preview.textContent = JSON.stringify(CONFIG_STATE, null, 2);
  applyExecutionModeUI();
}}
function applyExecutionModeUI() {{
  const mode = ensureExecutionMode();
  const contract = currentScenarioLaunchContract();
  const selector = document.getElementById('executionModeSelector');
  if (selector && selector.value !== mode) selector.value = mode;
  const badge = document.getElementById('executionModeBadge');
  if (badge) badge.textContent = `Browser Mode: ${{mode.replaceAll('_', ' ')}}`;
  const note = document.getElementById('executionModeNote');
  if (note) note.textContent = mode === FULLY_WIRED_EXECUTION_MODE ? (contract.launchReason || '') : (EXECUTION_MODE_NOTES[mode] || '');
  const runButton = document.getElementById('runScenarioButton');
  if (runButton) {{
    const enabled = mode === FULLY_WIRED_EXECUTION_MODE && !!contract.launchAllowed;
    runButton.disabled = !enabled;
    runButton.textContent = enabled ? 'Run Scenario' : (mode !== FULLY_WIRED_EXECUTION_MODE ? `Run blocked for ${{mode.replaceAll('_', ' ')}}` : 'Run blocked by scenario contract');
    runButton.title = enabled ? `Launch the real browser-owned LLS run via ${{contract.presentationLabel || 'the configured runner'}}.` : (mode !== FULLY_WIRED_EXECUTION_MODE ? (EXECUTION_MODE_NOTES[mode] || '') : (contract.launchReason || 'Selected scenario is blocked.'));
  }}
  const blocker = document.getElementById('executionModeBlocker');
  if (blocker) {{
    const blockerText = mode !== FULLY_WIRED_EXECUTION_MODE ? (EXECUTION_MODE_NOTES[mode] || '') : (contract.launchAllowed ? '' : (contract.launchReason || ''));
    blocker.classList.toggle('hidden', !blockerText);
    blocker.textContent = blockerText;
  }}
}}
document.querySelectorAll('[data-config-input]').forEach((input) => {{
  const handler = () => {{
    setByPath(CONFIG_STATE, input.dataset.path, parseFieldValue(input));
    refreshConfigPreview();
  }};
  input.addEventListener('change', handler);
  input.addEventListener('input', handler);
}});
const runForm = document.getElementById('runForm');
if (runForm) {{
  runForm.addEventListener('submit', (event) => {{
    ensureExecutionMode();
    const contract = currentScenarioLaunchContract();
    const mode = String(CONFIG_STATE.run_control?.execution_mode || 'LLS').trim().toUpperCase();
    document.getElementById('config_json').value = JSON.stringify(CONFIG_STATE);
    if (mode !== FULLY_WIRED_EXECUTION_MODE || !contract.launchAllowed) {{
      event.preventDefault();
      window.alert(mode !== FULLY_WIRED_EXECUTION_MODE ? (EXECUTION_MODE_NOTES[mode] || 'Run is blocked for this execution mode.') : (contract.launchReason || 'Selected scenario is blocked.'));
    }}
  }});
}}
const executionModeSelector = document.getElementById('executionModeSelector');
if (executionModeSelector) {{
  executionModeSelector.addEventListener('change', () => {{
    ensureExecutionMode();
    CONFIG_STATE.run_control.execution_mode = String(executionModeSelector.value || 'LLS').trim().toUpperCase();
    refreshConfigPreview();
  }});
}}
document.querySelectorAll('[data-home-group-button]').forEach((button) => {{
  button.addEventListener('click', () => activateHomeGroup(button.dataset.homeGroupButton));
}});
const homeSearch = document.getElementById('homeSearch');
if (homeSearch) {{
  homeSearch.addEventListener('input', applyHomeSearch);
}}
ensureExecutionMode();
if (HOME_GROUPS.length > 0) activateHomeGroup(HOME_GROUPS[0]);
refreshConfigPreview();
applyHomeSearch();
</script>
"""


def build_home_page(selected_scenario: str, message: str = "", user_profile: dict[str, Any] | None = None) -> bytes:
    scenarios = list_scenarios()
    config_payload: dict[str, Any]
    source_chain: list[str]
    if scenarios:
        if selected_scenario not in scenarios:
            selected_scenario = DEFAULT_SCENARIO if DEFAULT_SCENARIO in scenarios else scenarios[0]
        config_payload, source_chain = load_resolved_config_payload(selected_scenario)
    else:
        selected_scenario = ""
        config_payload = {"scenario_yaml": "# No scenario YAML files were found under simulator/configs/scenarios\n"}
        source_chain = []

    if not isinstance(config_payload.get("run_control"), dict):
        config_payload["run_control"] = {}
    requested_browser_mode = str(config_payload["run_control"].get("execution_mode") or "LLS").strip().upper()
    if requested_browser_mode not in BROWSER_EXECUTION_MODE_OPTIONS:
        requested_browser_mode = "LLS"
    config_payload["run_control"]["execution_mode"] = requested_browser_mode

    fields = flatten_config_fields(config_payload)
    grouped = group_config_fields(fields)
    group_names = [name for name, _ in grouped]
    support_counts: dict[str, int] = {}
    for field in fields:
        state = str(field.get("support_state") or "active")
        support_counts[state] = support_counts.get(state, 0) + 1
    truth_modes = infer_browser_truth_modes(config_payload)
    scenario_contract = scenario_launch_contract(config_payload, selected_scenario)
    summary_cards = [
        ("Browser Mode", truth_modes.get("browser_execution_mode_label", "")),
        ("Launch Contract", scenario_contract.get("launch_contract", "")),
        ("Runner Presentation", scenario_contract.get("presentation_label", "")),
        ("Editable Params", str(len(fields))),
        ("Groups", str(len(grouped))),
        ("Resolved Files", str(len(source_chain))),
        ("Realtime Store", "MySQL"),
        ("Noise Mode", truth_modes.get("noise_operating_mode", "")),
        ("Doppler Mode", truth_modes.get("doppler_source_mode", "")),
        ("Interference", truth_modes.get("interference_mode", "")),
        ("Control Mode", truth_modes.get("control_integration_mode", "")),
        ("Band", find_field_value(fields, ["frequency.band", "band", "carrier.band", "radio.band"])),
        ("Bandwidth", find_field_value(fields, ["bandwidth_hz", "bandwidth_mhz", "frequency.bandwidth_hz", "frequency.bandwidth_mhz"])),
        ("Link Adaptation", find_field_value(fields, ["link_adaptation.fixed_or_amc", "phy.linkAdaptation.mode"])),
        ("CQI Table", find_field_value(fields, ["link_adaptation.cqi_table", "phy.csi.cqiTable", "phy.pdsch.cqiTable"])),
        ("Mobility", find_field_value_with_unit(fields, ["mobility.ue_speed_kmh", "mobility_kmph", "speed_kmph", "ue.mobility_kmph", "channels.mobility_kmph", "scenario.mobility.speed_kmh"], "km/h")),
        ("Sites", find_field_value(fields, ["deployment_topology.num_sites", "scenario.layout.nSites", "n_sites", "site_count", "network.n_sites"])),
        ("Cells", find_field_value(fields, ["deployment_topology.num_cells", "num_cells", "scenario.layout.nCells"])),
        ("UEs", find_field_value(fields, ["deployment_topology.num_ues", "users.n_users", "ue_count", "num_ues", "n_ues", "scenario.nUE"])),
        ("ISD m", find_field_value(fields, ["deployment_topology.inter_site_distance", "scenario.layout.interSiteDistance_m"])),
    ]
    mode_cards = [
        ("Browser Mode", truth_modes.get("browser_execution_mode_label", "")),
        ("Launch Contract", scenario_contract.get("launch_contract", "")),
        ("Runner Presentation", scenario_contract.get("presentation_label", "")),
        ("Browser Control Plane", truth_modes.get("browser_control_plane", "")),
        ("MATLAB Entrypoint", truth_modes.get("entrypoint", "")),
        ("Execution Model", truth_modes.get("execution_model", "")),
        ("Configured Users", truth_modes.get("configured_users", "")),
        ("Mobility Speed", find_field_value_with_unit(fields, ["mobility.ue_speed_kmh", "channels.mobility_kmph", "scenario.mobility.speed_kmh"], "km/h")),
        ("Noise Operating Mode", truth_modes.get("noise_operating_mode", "")),
        ("Doppler Source", truth_modes.get("doppler_source_mode", "")),
        ("Interference Mode", truth_modes.get("interference_mode", "")),
        ("Control Integration", truth_modes.get("control_integration_mode", "")),
        ("Sweep Mode", truth_modes.get("sweep_mode", "")),
    ]
    group_tabs = "".join(
        f'<button type="button" class="subtab-button" data-home-group-button="{html.escape(name)}">{html.escape(HOME_GROUP_LABELS.get(name, humanize_key(name)))}</button>'
        for name in group_names
    )

    group_panels: list[str] = []
    for group_name, group_fields in grouped:
        rows: list[str] = []
        for field in group_fields:
            path = html.escape(field["path"])
            label = html.escape(field["label"])
            field_path = html.escape(field["path"])
            value = field["value"]
            search_text = html.escape(str(field.get("search_text") or f"{field['path']} {field['label']} {str(value)[:120]}").lower())
            options = field.get("options")
            kind = html.escape(field["kind"])
            support_state = str(field.get("support_state") or "active")
            support_note = html.escape(str(field.get("support_note") or ""))
            support_badge = html.escape(humanize_key(support_state.replace("-", " ")))
            if options:
                option_html = "".join(
                    f'<option value="{html.escape(str(opt))}"{" selected" if str(opt) == str(value) else ""}>{html.escape(str(opt))}</option>'
                    for opt in options
                )
                control = (
                    f'<select data-config-input="1" data-path="{path}" data-kind="{kind}">{option_html}</select>'
                )
            elif field["kind"] == "json":
                control = (
                    f'<textarea data-config-input="1" data-path="{path}" data-kind="{kind}">{html.escape(str(value))}</textarea>'
                )
            else:
                input_type = "number" if field["kind"] in {"int", "float"} else "text"
                step = ' step="any"' if field["kind"] == "float" else ""
                control = (
                    f'<input type="{input_type}" value="{html.escape(str(value))}" data-config-input="1" '
                    f'data-path="{path}" data-kind="{kind}"{step}>'
                )
            rows.append(
                f"<div class=\"field-row\" data-field-row=\"1\" data-search=\"{search_text}\">"
                f"<div class=\"field-label\">{label} <span class=\"pill\">{support_badge}</span></div>"
                f"<div class=\"field-path\">{field_path}</div>"
                f"<div class=\"mini-note\" style=\"margin-bottom:8px;\">{support_note}</div>"
                f"{control}"
                "</div>"
            )
        group_panels.append(
            f'<div class="subtab-panel" data-home-group-panel="{html.escape(group_name)}"><div class="field-grid">{"".join(rows)}</div></div>'
        )

    message_html = f'<section class="panel"><strong>{html.escape(message)}</strong></section>' if message else ""
    options = []
    for item in scenarios:
        selected_attr = ' selected="selected"' if item == selected_scenario else ""
        label = scenario_catalog_label(item)
        options.append(f'<option value="{html.escape(item)}"{selected_attr}>{html.escape(label)}</option>')
    latest = latest_run_id()
    latest_result = f'/result?run_id={latest}' if latest else "/result"
    latest_analytics = f'/analytics?run_id={latest}' if latest else "/analytics"
    source_chain_html = "".join(f'<span class="pill">{html.escape(item)}</span>' for item in source_chain) or '<span class="mini-note">No source chain available.</span>'
    summary_cards_html = "".join(
        f'<div class="metric-card"><div class="metric-value">{html.escape(value)}</div><div class="metric-label">{html.escape(label)}</div></div>'
        for label, value in summary_cards
    )
    mode_cards_html = "".join(
        f'<div class="glass-item"><strong>{html.escape(label)}</strong><br><span class="mini-note">{html.escape(str(value or "n/a"))}</span></div>'
        for label, value in mode_cards
    )
    support_legend_html = "".join(
        f'<span class="pill">{html.escape(humanize_key(state.replace("-", " ")))}: {count}</span>'
        for state, count in sorted(support_counts.items())
    )
    execution_mode_options_html = "".join(
        f'<option value="{html.escape(mode)}"{" selected" if mode == requested_browser_mode else ""}>{html.escape(BROWSER_EXECUTION_MODE_LABELS.get(mode, mode))}</option>'
        for mode in BROWSER_EXECUTION_MODE_OPTIONS
    )
    browser_mode_label = BROWSER_EXECUTION_MODE_LABELS.get(requested_browser_mode, requested_browser_mode)
    browser_mode_note = BROWSER_EXECUTION_MODE_NOTES.get(requested_browser_mode, "")
    lls_honesty_note = (
        "The active LLS browser path now uses receiver-noise thermal mode and full per-link channel-waveform inter-cell interference when requested, with any hybrid fallback remaining explicitly labeled. "
        "PBCH/PRACH/PDCCH/SRS remain standalone control/access diagnostics unless the runtime exports a stronger integration mode."
    )
    scenario_contract_html = (
        f'<p class="warning">Selected scenario launch contract is blocked: {html.escape(str(scenario_contract.get("launch_reason") or ""))}</p>'
        if not scenario_contract.get("launch_allowed")
        else f'<p class="mini-note">Selected scenario launch contract: <strong>{html.escape(str(scenario_contract.get("presentation_label") or ""))}</strong>. {html.escape(str(scenario_contract.get("launch_reason") or ""))}</p>'
    )
    body = f"""
    {message_html}
    <div class="two-col">
      <section class="panel">
        <h2>Home</h2>
        <p class="muted">Choose the top-level execution mode, tune parameters one by one, and launch the real browser-backed run from here. The editor below is built from the resolved config tree, so inherited defaults are expanded, searchable, and serialized into the exact runtime payload passed to MATLAB.</p>
        <p class="warning">This browser flow keeps execution modes separated. <code>runLLSTests</code> remains validation-only and is not the browser execution path. For this pass, only <code>LLS</code> is fully launchable from <code>/run</code>; the other selector modes are visible but intentionally blocked from accidentally contaminating the LLS path. {html.escape(lls_honesty_note)}</p>
        {scenario_contract_html}
        <div class="glass-list" style="margin-bottom:14px;">{mode_cards_html}</div>
        <div class="toolbar" style="flex-wrap:wrap;margin-bottom:12px;">{support_legend_html}</div>
        <div class="mini-note" style="margin-bottom:14px;">Every field below is serialized into <code>config_json</code> for the browser submission. The badge tells you whether that field is active in the current coupled-truth path, still abstracted, exported as sidecar evidence, or only relevant for separate sweep/secondary modes.</div>
        <form method="get" action="/home">
          <label for="scenario"><strong>Scenario YAML</strong></label>
          <select id="scenario" name="scenario" onchange="this.form.submit()">
            {''.join(options)}
          </select>
        </form>
        <form id="runForm" method="post" action="/run" style="margin-top:14px;">
          <input type="hidden" name="scenario" value="{html.escape(selected_scenario)}">
          <input type="hidden" id="config_json" name="config_json" value="">
          <label for="executionModeSelector"><strong>Execution Mode</strong></label>
          <select id="executionModeSelector" name="execution_mode">
            {execution_mode_options_html}
          </select>
          <div class="toolbar" style="margin-top:8px;flex-wrap:wrap;">
            <span class="pill" id="executionModeBadge">Browser Mode: {html.escape(browser_mode_label)}</span>
            <span class="mini-note" id="executionModeNote">{html.escape(browser_mode_note)}</span>
          </div>
          <div class="warning hidden" id="executionModeBlocker" style="margin-top:10px;"></div>
          <label for="run_tag"><strong>Run tag</strong></label>
          <input id="run_tag" name="run_tag" type="text" value="{html.escape(timestamp_tag('web'))}">
          <div class="toolbar">
            <input id="homeSearch" class="search-input" type="text" placeholder="Search band, bandwidth, base station count, UE count, mobility, scheduler, PHY knobs...">
            <span class="pill" id="fieldCount">{len(fields)} / {len(fields)} parameters visible</span>
          </div>
          <div class="panel-scroll-x" style="margin-top:10px;">
            <div class="subtab-bar">{group_tabs}</div>
          </div>
          {''.join(group_panels) if group_panels else '<p class="muted">No editable parameters were found.</p>'}
          <div class="toolbar" style="margin-top:16px;">
            <button id="runScenarioButton" type="submit">Run Scenario</button>
            <a class="button-link secondary" href="{latest_result}">Open Latest Result</a>
            <a class="button-link secondary" href="{latest_analytics}">Open Latest Analytics</a>
          </div>
        </form>
        <form method="post" action="/admin/clear" class="inline-form" onsubmit="return confirm('Clear all stored runs, MySQL rows, runtime YAML files, and repo results folders? Use this only when no run is active.');">
          <input type="hidden" name="next" value="/home">
          <button type="submit" class="danger">Clear Previous Runs</button>
        </form>
      </section>
      <section class="panel">
        <h2>Resolved Overview</h2>
        <div class="metric-grid">
          {summary_cards_html}
        </div>
        <div class="meta-card" style="margin-top:16px;">
          <strong>Live Stack</strong><br>
          <span class="muted">{html.escape(MYSQL_HOST)}:{MYSQL_PORT}/{html.escape(MYSQL_DATABASE)}</span><br>
          <code>{html.escape(str(MATLAB_EXE))}</code>
        </div>
        <div class="meta-card" style="margin-top:16px;">
          <strong>Resolved Source Chain</strong>
          <div class="mini-note">These are the YAML files merged into the live config editor.</div>
          <div style="margin-top:10px;">{source_chain_html}</div>
        </div>
        <div class="meta-card" style="margin-top:16px;">
          <strong>Default map center</strong><br>
          <span class="muted">{html.escape(DEFAULT_MAP_CENTER['label'])}</span><br>
          <code>{DEFAULT_MAP_CENTER['lat']:.6f}, {DEFAULT_MAP_CENTER['lon']:.6f}</code>
        </div>
        <div class="meta-card" style="margin-top:16px;">
          <strong>Launch Payload Preview</strong>
          <div class="mini-note">This is the browser-side config object that will be converted back into YAML on the server before MATLAB starts.</div>
          <pre id="configPreview"></pre>
        </div>
      </section>
    </div>
    """
    return page_shell(
        "6G LLS Home",
        body,
        active="home",
        extra_script=home_page_script(config_payload, group_names, selected_scenario, scenario_contract),
        user_profile=user_profile,
    )


def build_runs_page(message: str = "", user_profile: dict[str, Any] | None = None) -> bytes:
    rows = fetch_runs()
    message_html = f'<section class="panel"><strong>{html.escape(message)}</strong></section>' if message else ""
    table_rows = []
    for row in rows:
        run_id = int(row["run_id"])
        table_rows.append(
            "<tr>"
            f"<td><a href=\"/run/{run_id}\">{run_id}</a></td>"
            f"<td>{html.escape(str(row.get('scenario_id') or ''))}</td>"
            f"<td>{html.escape(str(row.get('run_tag') or ''))}</td>"
            f"<td>{html.escape(str(row.get('profile_name') or ''))}</td>"
            f"<td>{format_status(str(row.get('status_text') or ''))}</td>"
            f"<td>{html.escape(str(row.get('created_utc') or ''))}</td>"
            f"<td>{html.escape(str(row.get('updated_utc') or ''))}</td>"
            "<td>"
            f"<a href=\"/result?run_id={run_id}\">Result</a> | <a href=\"/analytics?run_id={run_id}\">Analytics</a> | <a href=\"/map?run_id={run_id}\">Map</a>"
            "<div style=\"margin-top:8px;\">"
            f"<form method=\"post\" action=\"/admin/delete-run\" class=\"inline-form\" onsubmit=\"return confirm('Delete run {run_id} and all its database rows, logs, runtime YAML, and stored artifacts?');\">"
            f"<input type=\"hidden\" name=\"run_id\" value=\"{run_id}\">"
            "<input type=\"hidden\" name=\"next\" value=\"/runs\">"
            "<button type=\"submit\" class=\"danger small-button\">Delete Run</button>"
            "</form>"
            "</div>"
            "</td>"
            "</tr>"
        )
    body = f"""
    {message_html}
    <section class="panel">
      <h2>Runs</h2>
      <p class="muted">This table is read directly from <code>sim_runs</code>. Rows marked <span class="status-running">running</span> should keep moving because DB updates touch <code>updated_utc</code> whenever logs or artifacts are written.</p>
      <div class="toolbar">
        <a class="button-link secondary" href="/home">Back To Home</a>
        <form method="post" action="/admin/clear" class="inline-form" onsubmit="return confirm('Clear all stored runs, MySQL rows, runtime YAML files, and repo results folders? Use this only when no run is active.');">
          <input type="hidden" name="next" value="/runs">
          <button type="submit" class="danger">Clear Previous Runs</button>
        </form>
      </div>
      <div class="table-scroll">
        <table>
          <thead><tr><th>Run ID</th><th>Scenario</th><th>Run Tag</th><th>Profile</th><th>Status</th><th>Created</th><th>Updated</th><th>Open / Delete</th></tr></thead>
          <tbody>{''.join(table_rows) if table_rows else '<tr><td colspan="8">No runs found in MySQL yet.</td></tr>'}</tbody>
        </table>
      </div>
    </section>
    """
    return page_shell("6G LLS Runs", body, active="runs", user_profile=user_profile)


def build_run_page(run_id: int, user_profile: dict[str, Any] | None = None) -> bytes:
    run_row = fetch_run(run_id)
    if run_row is None:
        raise KeyError(f"Run {run_id} was not found.")
    sync_runtime_log_for_run(run_row)
    artifacts = fetch_artifacts(run_id)
    logs = fetch_logs(run_id, limit=80, descending=True)
    counts = summarize_artifacts(artifacts)
    counts["logs_total"] = count_logs(run_id)
    pills = "".join(
        [
            f'<span class="pill"><span class="live-dot"></span>Run {run_id}</span>',
            f'<span class="pill">Scenario: {html.escape(str(run_row.get("scenario_id") or ""))}</span>',
            f'<span class="pill">Tag: {html.escape(str(run_row.get("run_tag") or ""))}</span>',
            f'<span class="pill">Status: {html.escape(str(run_row.get("status_text") or ""))}</span>',
        ]
    )
    body = f"""
    <section class="panel">
      <h2>Run {run_id}</h2>
      <div>{pills}</div>
      <div class="metric-grid" style="margin-top:14px;">
        <div class="metric-card"><div class="metric-value">{counts['artifacts_total']}</div><div class="metric-label">Artifacts</div></div>
        <div class="metric-card"><div class="metric-value">{counts['tables_total']}</div><div class="metric-label">Tables</div></div>
        <div class="metric-card"><div class="metric-value">{counts['images_total']}</div><div class="metric-label">Images</div></div>
        <div class="metric-card"><div class="metric-value">{counts['logs_total']}</div><div class="metric-label">Logs</div></div>
      </div>
      <div class="toolbar">
        <a class="button-link secondary" href="/result?run_id={run_id}">Open Result</a>
        <a class="button-link secondary" href="/analytics?run_id={run_id}">Open Real-Time Analytics</a>
        <a class="button-link secondary" href="/map?run_id={run_id}">Open Map</a>
        <a class="button-link secondary" href="/images?run_id={run_id}">Images</a>
      </div>
    </section>
    <section class="panel"><h3>Status JSON</h3><pre>{html.escape(pretty_json(run_row.get("status_json")))}</pre></section>
    <section class="panel"><h3>Recent Logs</h3><pre>{html.escape(render_log_lines(logs))}</pre></section>
    """
    return page_shell(f"Run {run_id}", body, active="runs", run_id=run_id, user_profile=user_profile)


def result_page_script(
    run_id: int | None,
    run_tag: str | None = None,
    section: str = "all",
    *,
    initial_payload: dict[str, Any] | None = None,
    initial_preview: dict[str, Any] | None = None,
) -> str:
    run_id_literal = "null" if run_id is None else str(run_id)
    run_tag_literal = json.dumps(run_tag or "")
    section_literal = json.dumps(normalize_result_section(section))
    initial_payload_literal = json_for_script(initial_payload)
    initial_preview_literal = json_for_script(initial_preview)
    return f"""
<script>
let RESULT_RUN_ID = {run_id_literal};
const RESULT_RUN_TAG = {run_tag_literal};
const RESULT_SECTION = {section_literal};
const RESULT_POLL_MS = {POLL_INTERVAL_MS};
const RESULT_INITIAL_PAYLOAD = {initial_payload_literal};
const RESULT_INITIAL_PREVIEW = {initial_preview_literal};
let RESULT_LATEST_DATA = RESULT_INITIAL_PAYLOAD;
let CURRENT_TABLE_ID = null;
let RESULT_CURRENT_PREVIEW = null;
let RESULT_CHART_STATE = {{ xKey: '', yKey: '', groupKey: '', groupValue: 'aggregate' }};
let RESULT_IMAGE_ITEMS = [];
let RESULT_IMAGE_SIGNATURE = '';
let RESULT_IMAGE_LIMIT = 24;
let RESULT_SECTION_COUNTS = {{}};
let RESULT_REFRESH_TIMER = null;
let RESULT_FULL_PAYLOAD = RESULT_INITIAL_PAYLOAD;
let RESULT_ARTIFACT_VERSION = RESULT_INITIAL_PAYLOAD ? RESULT_INITIAL_PAYLOAD.artifact_version : '';
function resultEsc(value) {{
  return String(value ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}}
async function resultFetchJson(url) {{
  const resp = await fetch(url, {{ credentials: 'same-origin' }});
  if (resp.status === 401) {{
    let loginUrl = '/login';
    try {{
      const payload = await resp.json();
      if (payload && payload.login_url) loginUrl = payload.login_url;
    }} catch (_err) {{}}
    throw new Error(`Authentication required. Sign in again via ${{loginUrl}}`);
  }}
  if (!resp.ok) throw new Error(`HTTP ${{resp.status}}`);
  return resp.json();
}}
function mergeResultPayload(previous, incoming) {{
  if (!previous) return incoming;
  if (!incoming) return previous;
  const merged = {{ ...previous, ...incoming }};
  const stickyKeys = ['tables_all', 'tables_recent', 'tables_summary', 'images_all', 'images_recent', 'output_coverage', 'feature_policy', 'contract_surface', 'output_contract', 'timing', 'map', 'metric_explorer', 'debug'];
  stickyKeys.forEach((key) => {{
    if (incoming[key] === undefined) merged[key] = previous[key];
  }});
  merged.charts = {{ ...(previous.charts || {{}}), ...(incoming.charts || {{}}) }};
  return merged;
}}
function resultArtifactSignature(items) {{
  return (items || []).map((item) => `${{item.artifact_id}}:${{item.byte_size}}`).join('|');
}}
function resultArtifactCard(item) {{
  return `<div class="artifact-card"><h3>${{resultEsc(item.logical_path)}}</h3><a href="${{resultEsc(item.view_url)}}" target="_blank" rel="noopener noreferrer"><img loading="lazy" decoding="async" src="${{resultEsc(item.view_url)}}" alt="${{resultEsc(item.logical_path)}}" /></a><div class="toolbar"><a href="${{resultEsc(item.view_url)}}" target="_blank" rel="noopener noreferrer">Open In New Tab</a><a href="${{resultEsc(item.download_url)}}">Download Image</a></div></div>`;
}}
function renderResultImageGrid(images, sectionCounts) {{
  const host = document.getElementById('resultImageGrid');
  if (!host) return;
  const signature = resultArtifactSignature(images);
  if (signature !== RESULT_IMAGE_SIGNATURE) {{
    RESULT_IMAGE_SIGNATURE = signature;
    RESULT_IMAGE_LIMIT = 24;
  }}
  RESULT_IMAGE_ITEMS = images || [];
  RESULT_SECTION_COUNTS = sectionCounts || {{}};
  const visible = RESULT_IMAGE_ITEMS.slice(0, RESULT_IMAGE_LIMIT);
  const cards = visible.map((item) => resultArtifactCard(item)).join('');
  const emptyHtml = `<p class="muted">No image artifacts are published yet for ${{resultEsc(RESULT_SECTION.toUpperCase())}}. Section counts: ${{resultEsc(JSON.stringify(RESULT_SECTION_COUNTS))}}</p>`;
  const more = RESULT_IMAGE_ITEMS.length > RESULT_IMAGE_LIMIT
    ? `<div class="toolbar" style="margin-top:14px;"><button type="button" id="resultLoadMoreImages">Load More Images (${{resultEsc(RESULT_IMAGE_ITEMS.length - RESULT_IMAGE_LIMIT)}} remaining)</button></div>`
    : '';
  const nextState = `${{signature}}|${{RESULT_IMAGE_LIMIT}}`;
  if (host.dataset.state === nextState) return;
  host.dataset.state = nextState;
  host.innerHTML = cards || emptyHtml;
  if (more) {{
    host.insertAdjacentHTML('beforeend', more);
    const button = document.getElementById('resultLoadMoreImages');
    if (button) {{
      button.addEventListener('click', () => {{
        RESULT_IMAGE_LIMIT = Math.min(RESULT_IMAGE_LIMIT + 24, RESULT_IMAGE_ITEMS.length);
        renderResultImageGrid(RESULT_IMAGE_ITEMS, RESULT_SECTION_COUNTS);
      }});
    }}
  }}
}}
function resultNextPollDelay(data) {{
  const status = String(((data || {{}}).run || {{}}).status_text || '').toLowerCase();
  const visible = document.visibilityState === 'visible';
  if (status === 'running') return visible ? RESULT_POLL_MS : Math.max(RESULT_POLL_MS * 4, 4000);
  if (status === 'completed' || status === 'completed_with_failures' || status === 'failed' || status === 'stopped' || status.startsWith('aborted')) {{
    return visible ? 15000 : 30000;
  }}
  return visible ? 5000 : 15000;
}}
function scheduleResultRefresh(delayMs) {{
  if (RESULT_REFRESH_TIMER) window.clearTimeout(RESULT_REFRESH_TIMER);
  RESULT_REFRESH_TIMER = window.setTimeout(() => {{
    refreshResult().catch((err) => {{
      document.getElementById('resultPreview').innerHTML = `<p class="warning">Live result refresh failed: ${{resultEsc(err)}}</p>`;
      scheduleResultRefresh(15000);
    }});
  }}, Math.max(750, Number(delayMs) || RESULT_POLL_MS));
}}
async function resolveResultRunId() {{
  if (RESULT_RUN_ID !== null && RESULT_RUN_ID !== undefined) return RESULT_RUN_ID;
  if (!RESULT_RUN_TAG) return null;
  const data = await resultFetchJson(`/api/runs?run_tag=${{encodeURIComponent(RESULT_RUN_TAG)}}&limit=1`);
  const runs = data.runs || [];
  if (runs.length > 0) {{
    RESULT_RUN_ID = runs[0].run_id;
    const clean = new URL(window.location.href);
    clean.searchParams.set('run_id', String(RESULT_RUN_ID));
    clean.searchParams.delete('run_tag');
    window.history.replaceState(null, '', clean.toString());
    return RESULT_RUN_ID;
  }}
  return null;
}}
function filterTablesBySection(tables) {{
  const stage = (RESULT_LATEST_DATA && RESULT_LATEST_DATA.runtime_context && RESULT_LATEST_DATA.runtime_context.stage) || {{}};
  const filtered = (RESULT_SECTION === 'all'
    ? [...tables]
    : tables.filter((item) => String(item.section || 'other') === RESULT_SECTION))
    .filter((item) => {{
      const section = String(item.section || 'other');
      const path = String(item.logical_path || '').toLowerCase();
      const size = Number(item.byte_size || 0);
      if (section === 'harq' && !resultTruthyFlag(stage.HARQReady)) return false;
      if (section === 'beam' && !resultTruthyFlag(stage.BeamReady)) return false;
      if (section === 'pusch' && path.endsWith('ul_pusch_trials.csv') && size <= 2303) return false;
      if (section === 'pdsch' && path.endsWith('dl_pdsch_trials.csv') && size <= 2303) return false;
      if ((path.endsWith('dl_constellation_preview.csv') || path.endsWith('ul_constellation_preview.csv')) && size <= 2303) return false;
      return true;
    }});
  return filtered.sort((a, b) => {{
    const ra = Number(a.display_rank ?? 999);
    const rb = Number(b.display_rank ?? 999);
    if (ra !== rb) return ra - rb;
    return String(a.logical_path || '').localeCompare(String(b.logical_path || ''));
  }});
}}
function filterImagesBySection(images) {{
  const stage = (RESULT_LATEST_DATA && RESULT_LATEST_DATA.runtime_context && RESULT_LATEST_DATA.runtime_context.stage) || {{}};
  const filtered = (RESULT_SECTION === 'all'
    ? [...images]
    : images.filter((item) => String(item.section || 'other') === RESULT_SECTION))
    .filter((item) => {{
      const section = String(item.section || 'other');
      if (section === 'harq' && !resultTruthyFlag(stage.HARQReady)) return false;
      if (section === 'beam' && !resultTruthyFlag(stage.BeamReady)) return false;
      return true;
    }});
  return filtered.sort((a, b) => {{
    const ra = Number(a.display_rank ?? 999);
    const rb = Number(b.display_rank ?? 999);
    if (ra !== rb) return ra - rb;
    return String(a.logical_path || '').localeCompare(String(b.logical_path || ''));
  }});
}}
function renderRuntimeContext(runtimeContext) {{
  const host = document.getElementById('resultContext');
  if (!host) return;
  const deployment = runtimeContext?.deployment || {{}};
  const operating = Array.isArray(runtimeContext?.operating_mode) ? runtimeContext.operating_mode : [];
  const roundtrip = runtimeContext?.roundtrip_artifacts || {{}};
  const roundtripSummary = roundtrip.summary || {{}};
  const truthModes = runtimeContext?.truth_modes || {{}};
  const rawLifecycle = runtimeContext?.raw_trial_lifecycle || {{}};
  const controlSummary = runtimeContext?.control_summary || {{}};
  const configSnapshot = runtimeContext?.config_snapshot || {{}};
  const stage = runtimeContext?.stage || {{}};
  const pills = [];
  if (deployment.NumSites !== undefined) pills.push(`<span class="pill">Sites: ${{resultEsc(deployment.NumSites)}}</span>`);
  if (deployment.NumCells !== undefined) pills.push(`<span class="pill">Cells: ${{resultEsc(deployment.NumCells)}}</span>`);
  if (deployment.NumUEs !== undefined) pills.push(`<span class="pill">UEs: ${{resultEsc(deployment.NumUEs)}}</span>`);
  if (deployment.InterSiteDistance_m !== undefined) pills.push(`<span class="pill">ISD: ${{resultEsc(deployment.InterSiteDistance_m)}} m</span>`);
  if (runtimeContext?.scenario_profile) pills.push(`<span class="pill">Profile: ${{resultEsc(runtimeContext.scenario_profile)}}</span>`);
  if (runtimeContext?.layout_type) pills.push(`<span class="pill">Layout: ${{resultEsc(runtimeContext.layout_type)}}</span>`);
  if (runtimeContext?.actual_site_spacing_m !== undefined && runtimeContext?.actual_site_spacing_m !== null) pills.push(`<span class="pill">Observed Site Spacing: ${{resultEsc(Number(runtimeContext.actual_site_spacing_m).toFixed(1))}} m</span>`);
  if (stage.CurrentStage || stage.StageName || stage.Stage) pills.push(`<span class="pill">Stage: ${{resultEsc(stage.CurrentStage || stage.StageName || stage.Stage)}}</span>`);
  if (deployment.MobilityEnabled !== undefined) {{
    const mob = String(deployment.MobilityEnabled).toLowerCase();
    pills.push(`<span class="pill">Mobility: ${{mob === '1' || mob === 'true' ? 'On' : 'Off'}}</span>`);
  }}
  if (truthModes.noise_operating_mode) pills.push(`<span class="pill">Noise Mode: ${{resultEsc(truthModes.noise_operating_mode)}}</span>`);
  if (truthModes.doppler_source_mode) pills.push(`<span class="pill">Doppler Source: ${{resultEsc(truthModes.doppler_source_mode)}}</span>`);
  if (truthModes.interference_mode) pills.push(`<span class="pill">Interference: ${{resultEsc(truthModes.interference_mode)}}</span>`);
  if (truthModes.control_integration_mode) pills.push(`<span class="pill">Control: ${{resultEsc(truthModes.control_integration_mode)}}</span>`);
  if (truthModes.pbch_mode) pills.push(`<span class="pill">PBCH: ${{resultEsc(truthModes.pbch_mode)}}</span>`);
  if (truthModes.prach_mode) pills.push(`<span class="pill">PRACH: ${{resultEsc(truthModes.prach_mode)}}</span>`);
  if (truthModes.pdcch_mode) pills.push(`<span class="pill">PDCCH: ${{resultEsc(truthModes.pdcch_mode)}}</span>`);
  if (truthModes.srs_mode) pills.push(`<span class="pill">SRS: ${{resultEsc(truthModes.srs_mode)}}</span>`);
  if (truthModes.pbch_gating_active !== undefined) pills.push(`<span class="pill">PBCH Gate: ${{truthModes.pbch_gating_active ? 'on' : 'off'}}</span>`);
  if (truthModes.prach_gating_active !== undefined) pills.push(`<span class="pill">PRACH Gate: ${{truthModes.prach_gating_active ? 'on' : 'off'}}</span>`);
  if (truthModes.pdcch_gating_active !== undefined) pills.push(`<span class="pill">PDCCH Gate: ${{truthModes.pdcch_gating_active ? 'on' : 'off'}}</span>`);
  if (truthModes.srs_gating_active !== undefined) pills.push(`<span class="pill">SRS Gate: ${{truthModes.srs_gating_active ? 'on' : 'off'}}</span>`);
  if (roundtripSummary.config_roundtrip_rows) pills.push(`<span class="pill">Roundtrip Rows: ${{resultEsc(roundtripSummary.config_roundtrip_rows)}}</span>`);
  if (roundtripSummary.config_roundtrip_mismatches !== undefined) pills.push(`<span class="pill">Roundtrip Mismatches: ${{resultEsc(roundtripSummary.config_roundtrip_mismatches)}}</span>`);
  if (roundtripSummary.summary_vs_raw_rows) pills.push(`<span class="pill">Summary vs Raw Rows: ${{resultEsc(roundtripSummary.summary_vs_raw_rows)}}</span>`);
  if (controlSummary.PBCHFailureCount !== undefined) pills.push(`<span class="pill">PBCH Failures: ${{resultEsc(controlSummary.PBCHFailureCount)}}</span>`);
  if (controlSummary.PRACHFailureCount !== undefined) pills.push(`<span class="pill">PRACH Failures: ${{resultEsc(controlSummary.PRACHFailureCount)}}</span>`);
  if (controlSummary.ControlDecodeFailureCount !== undefined) pills.push(`<span class="pill">PDCCH Failures: ${{resultEsc(controlSummary.ControlDecodeFailureCount)}}</span>`);
  if (controlSummary.SRSInvalidEventCount !== undefined) pills.push(`<span class="pill">SRS Invalid Events: ${{resultEsc(controlSummary.SRSInvalidEventCount)}}</span>`);
  if (controlSummary.GrantsBlockedByGating !== undefined) pills.push(`<span class="pill">Blocked Grants: ${{resultEsc(controlSummary.GrantsBlockedByGating)}}</span>`);
  if (controlSummary.UsersAcquired !== undefined) pills.push(`<span class="pill">Users Acquired: ${{resultEsc(controlSummary.UsersAcquired)}}</span>`);
  if (controlSummary.UsersAccessReady !== undefined) pills.push(`<span class="pill">Access Ready: ${{resultEsc(controlSummary.UsersAccessReady)}}</span>`);
  if (controlSummary.UsersWithValidSRS !== undefined) pills.push(`<span class="pill">Users With Valid SRS: ${{resultEsc(controlSummary.UsersWithValidSRS)}}</span>`);
  if (configSnapshot.submitted_present) pills.push(`<span class="pill">Submitted Config: sim_runs.config_json</span>`);
  [['dl','DL'], ['ul','UL']].forEach(([key, label]) => {{
    const info = rawLifecycle[key] || {{}};
    if (String(info.status || '') === 'exact') {{
      pills.push(`<span class="pill">${{resultEsc(label)}} Finalized Rows: ${{resultEsc(info.finalized_rows ?? 0)}}</span>`);
      if ((info.partial_rows ?? 0) > 0) pills.push(`<span class="pill">${{resultEsc(label)}} Partial Rows: ${{resultEsc(info.partial_rows)}}</span>`);
      if ((info.finalized_secondary_gap_rows ?? 0) > 0) pills.push(`<span class="pill">${{resultEsc(label)}} Finalized With Secondary Gaps: ${{resultEsc(info.finalized_secondary_gap_rows)}}</span>`);
    }}
  }});
  operating.forEach((row) => {{
    const direction = String(row.Direction || 'LLS');
    const amcPolicy = row.ConfiguredMCSSelectionPolicy || row.ConfiguredMCSSelectionMode || row.ConfiguredLinkAdaptationMode || row.LinkAdaptationMode;
    if (amcPolicy) pills.push(`<span class="pill">${{resultEsc(direction)}} AMC Policy: ${{resultEsc(amcPolicy)}}</span>`);
    if (row.RequestedOperatingPointSource) pills.push(`<span class="pill">${{resultEsc(direction)}} Requested Operating Point: ${{resultEsc(row.RequestedOperatingPointSource)}}</span>`);
    if (row.ActualMCSSelectionMode) pills.push(`<span class="pill">${{resultEsc(direction)}} Applied AMC Mode: ${{resultEsc(row.ActualMCSSelectionMode)}}</span>`);
    if (row.AppliedOperatingPointSource) pills.push(`<span class="pill">${{resultEsc(direction)}} Applied Operating Point: ${{resultEsc(row.AppliedOperatingPointSource)}}</span>`);
    if (row.SchedulerGrantMCSSelectionMode) pills.push(`<span class="pill">${{resultEsc(direction)}} Scheduler AMC Mode: ${{resultEsc(row.SchedulerGrantMCSSelectionMode)}}</span>`);
    if (row.CQITable) pills.push(`<span class="pill">${{resultEsc(direction)}} CQI: ${{resultEsc(row.CQITable)}}</span>`);
    if (row.MCSTable) pills.push(`<span class="pill">${{resultEsc(direction)}} MCS: ${{resultEsc(row.MCSTable)}}</span>`);
    if (row.FixedMCSIndex !== undefined && row.FixedMCSIndex !== null && row.FixedMCSIndex !== '') {{
      pills.push(`<span class="pill">${{resultEsc(direction)}} Fixed MCS: ${{resultEsc(row.FixedMCSIndex)}}</span>`);
    }}
  }});
  const snapshotLinks = [];
  const downloads = configSnapshot.downloads || {{}};
  [['resolved_json','Resolved JSON'], ['resolved_yaml','Resolved YAML'], ['source_chain','Source Chain'], ['config_roundtrip_verification','Roundtrip CSV'], ['browser_runtime_db_consistency','Browser/DB CSV'], ['summary_vs_raw_consistency','Summary/Raw CSV'], ['value_source_audit','Value Source CSV']].forEach(([key, label]) => {{
    const item = downloads[key];
    if (item && (item.view_url || item.download_url)) {{
      snapshotLinks.push(`<a class="button-link secondary" href="${{resultEsc(item.view_url || item.download_url)}}">${{resultEsc(label)}}</a>`);
    }}
  }});
  const notes = Array.isArray(runtimeContext?.notes) ? runtimeContext.notes : [];
  const roundtripMismatchRows = roundtrip.mismatch_rows || {{}};
  const roundtripMismatchDetails = [];
  Object.entries(roundtripMismatchRows).forEach(([artifactName, rows]) => {{
    if (!Array.isArray(rows)) return;
    rows.slice(0, 8).forEach((row) => {{
      const parameter = row.ParameterName || row.FieldName || row.SummaryField || row.OutputName || 'unknown_field';
      const status = row.ConsistencyStatus || row.Status || row.current_status || 'non_consistent';
      const note = row.ConsistencyNotes || row.Notes || row.unavailable_reason || '';
      roundtripMismatchDetails.push(`${{resultEsc(artifactName)}}: ${{resultEsc(parameter)}} -> ${{resultEsc(status)}}${{note ? ' (' + resultEsc(note) + ')' : ''}}`);
    }});
  }});
  host.innerHTML = (pills.length ? pills.join('') : '<span class="mini-note">Runtime context is still loading.</span>') +
    (snapshotLinks.length ? `<div class="toolbar" style="margin-top:12px;">${{snapshotLinks.join('')}}</div>` : '') +
    (roundtripMismatchDetails.length ? `<div class="warning" style="margin-top:12px;"><strong>Roundtrip mismatches</strong><br>${{roundtripMismatchDetails.join('<br>')}}</div>` : '') +
    (notes.length ? `<div class="warning" style="margin-top:12px;">${{notes.map((note) => resultEsc(note)).join('<br>')}}</div>` : '');
}}
function resultChartPriority(name) {{
  const token = String(name || '').trim().toLowerCase();
  const priorities = ['goodput','throughput','bler','rsrp','sinr','snr','cqi','mcs','coderate','code rate','latency','delay','detection','gain','evm','nmse','harq','beam','interference','noise','power'];
  for (let idx = 0; idx < priorities.length; idx += 1) {{
    if (token.includes(priorities[idx])) return [0, idx, token];
  }}
  if (/(frame|slot|trial|seed|index|iteration|user|count|point|step|sample|tti)$/i.test(token)) return [2, 99, token];
  return [1, 50, token];
}}
function resultTruthyFlag(value) {{
  const token = String(value ?? '').trim().toLowerCase();
  return token === '1' || token === 'true' || token === 'yes' || token === 'on';
}}
function parseResultNumber(value) {{
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : null;
}}
function resultCoordinateColumn(name) {{
  return /(^lat$|^lon$|^x(_m)?$|^y(_m)?$|^z(_m)?$|heading|azimuth|longitude|latitude)/i.test(String(name || '').trim());
}}
function resultPreferredXColumn(name) {{
  return /(time|slot|frame|trial|index|tti|snr|sample|iteration|point|step|count)/i.test(String(name || '').trim());
}}
function resultPreferredGroupColumn(name) {{
  return /^(ueid|ueindex|userid|userindex|rnti|servingcell|cellid|siteid|sectorid|candidaterank|direction)$/i.test(String(name || '').trim());
}}
function buildResultChartModel(payload) {{
  const header = payload.header || [];
  const rows = payload.rows || [];
  const lowered = header.map((item) => String(item || '').trim().toLowerCase());
  if (!header.length || !rows.length) {{
    return {{ kind: 'empty', header, rows, lowered, numericColumns: [], xCandidates: [], yCandidates: [], groupCandidates: [] }};
  }}
  if (lowered.includes('equalizedreal') && lowered.includes('equalizedimag')) {{
    return {{ kind: 'constellation', header, rows, lowered, numericColumns: [], xCandidates: [], yCandidates: [], groupCandidates: [] }};
  }}
  const numericColumns = [];
  for (let idx = 0; idx < header.length; idx += 1) {{
    const values = rows.map((row) => parseResultNumber(row[idx])).filter((value) => value !== null);
    if (values.length >= Math.max(2, Math.floor(rows.length / 4))) {{
      numericColumns.push({{ idx, name: header[idx] }});
    }}
  }}
  const xCandidates = numericColumns
    .filter((item) => resultPreferredXColumn(item.name))
    .sort((a, b) => String(a.name).localeCompare(String(b.name)));
  const yCandidates = numericColumns
    .filter((item) => !resultCoordinateColumn(item.name))
    .sort((a, b) => {{
      const pa = resultChartPriority(a.name);
      const pb = resultChartPriority(b.name);
      if (pa[0] !== pb[0]) return pa[0] - pb[0];
      if (pa[1] !== pb[1]) return pa[1] - pb[1];
      return String(pa[2]).localeCompare(String(pb[2]));
    }});
  const groupCandidates = header
    .map((name, idx) => {{
      const values = Array.from(new Set(rows.map((row) => String(row[idx] ?? '').trim()).filter((value) => value !== '')));
      return {{ idx, name, values }};
    }})
    .filter((item) => item.values.length >= 2 && item.values.length <= Math.min(rows.length, 64))
    .sort((a, b) => {{
      const ap = resultPreferredGroupColumn(a.name) ? 0 : 1;
      const bp = resultPreferredGroupColumn(b.name) ? 0 : 1;
      if (ap !== bp) return ap - bp;
      if (a.values.length !== b.values.length) return a.values.length - b.values.length;
      return String(a.name).localeCompare(String(b.name));
    }});
  return {{ kind: 'numeric', header, rows, lowered, numericColumns, xCandidates, yCandidates, groupCandidates }};
}}
function ensureResultChartState(model) {{
  if (!model || model.kind !== 'numeric') {{
    RESULT_CHART_STATE = {{ xKey: '', yKey: '', groupKey: '', groupValue: 'aggregate' }};
    return;
  }}
  const numericKeys = model.numericColumns.map((item) => String(item.name));
  const xKeys = (model.xCandidates.length ? model.xCandidates : model.numericColumns).map((item) => String(item.name));
  const yKeys = model.yCandidates.map((item) => String(item.name));
  const groupKeys = model.groupCandidates.map((item) => String(item.name));
  if (!xKeys.includes(RESULT_CHART_STATE.xKey)) {{
    RESULT_CHART_STATE.xKey = xKeys.length ? xKeys[0] : '';
  }}
  const yPool = yKeys.filter((name) => name !== RESULT_CHART_STATE.xKey);
  if (!yPool.includes(RESULT_CHART_STATE.yKey)) {{
    RESULT_CHART_STATE.yKey = yPool.length ? yPool[0] : (numericKeys.find((name) => name !== RESULT_CHART_STATE.xKey) || '');
  }}
  if (!groupKeys.includes(RESULT_CHART_STATE.groupKey)) {{
    RESULT_CHART_STATE.groupKey = groupKeys.length ? groupKeys[0] : '';
    RESULT_CHART_STATE.groupValue = 'aggregate';
  }}
  const activeGroup = model.groupCandidates.find((item) => String(item.name) === RESULT_CHART_STATE.groupKey);
  if (!activeGroup) {{
    RESULT_CHART_STATE.groupValue = 'aggregate';
  }} else if (RESULT_CHART_STATE.groupValue !== 'aggregate' && !activeGroup.values.includes(RESULT_CHART_STATE.groupValue)) {{
    RESULT_CHART_STATE.groupValue = 'aggregate';
  }}
}}
function renderPreviewTable(payload) {{
  const header = payload.header || [];
  const rows = payload.rows || [];
  const headHtml = header.map((cell) => `<th>${{resultEsc(cell)}}</th>`).join('');
  const bodyHtml = rows.map((row) => `<tr>${{row.map((cell) => `<td>${{resultEsc(cell)}}</td>`).join('')}}</tr>`).join('');
  let noteHtml = '';
  if (header.includes('IsWarmupFrame') && header.includes('LinkAdaptationApplied')) {{
    const warmIdx = header.indexOf('IsWarmupFrame');
    const appliedIdx = header.indexOf('LinkAdaptationApplied');
    const warmCount = rows.filter((row) => String(row[warmIdx] ?? '').toLowerCase() === 'true' || String(row[warmIdx] ?? '') === '1').length;
    const appliedCount = rows.filter((row) => String(row[appliedIdx] ?? '').toLowerCase() === 'true' || String(row[appliedIdx] ?? '') === '1').length;
    noteHtml = `<div class="warning" style="margin-bottom:12px;">Preview contains ${{warmCount}} warmup rows and ${{appliedCount}} rows with an applied link-adaptation decision. Early rows can still show the configured starting MCS before AMC settles.</div>`;
  }}
  if (header.includes('RSRPSource') && header.includes('WidebandSINRSource')) {{
    const rsrpIdx = header.indexOf('RSRPSource');
    const sinrIdx = header.indexOf('WidebandSINRSource');
    const rsrpSource = rows.find((row) => String(row[rsrpIdx] ?? '').trim() !== '')?.[rsrpIdx] || 'n/a';
    const sinrSource = rows.find((row) => String(row[sinrIdx] ?? '').trim() !== '')?.[sinrIdx] || 'n/a';
    noteHtml += `<div class="mini-note" style="margin-bottom:12px;">RSRP source: ${{resultEsc(rsrpSource)}}. Wideband SINR source: ${{resultEsc(sinrSource)}}.</div>`;
  }}
  document.getElementById('resultPreview').innerHTML =
    `${{noteHtml}}<div class="table-scroll"><table><thead><tr>${{headHtml}}</tr></thead><tbody>${{bodyHtml || '<tr><td>No rows available.</td></tr>'}}</tbody></table></div>`;
}}
function renderResultAuxPanels(data) {{
  const logsPanel = document.getElementById('resultLogsPanel');
  const logsBox = document.getElementById('resultLogBox');
  const debugPanel = document.getElementById('resultDebugPanel');
  const debugSummary = document.getElementById('resultDebugSummary');
  const debugFailure = document.getElementById('resultDebugFailure');
  const debugHighlights = document.getElementById('resultDebugHighlights');
  const issuePanel = document.getElementById('resultIssuePanel');
  const issueBody = document.getElementById('resultIssueBody');
  if (logsPanel && logsBox) {{
    const logs = (data.logs_recent || []).map((row) => `[${{row.time_str || row.created_utc || ''}}] ${{row.level_str || 'INFO'}} ${{row.message_text || ''}}`);
    logsBox.textContent = logs.join('\\n') || 'No live logs have been stored yet for this run.';
    logsPanel.style.display = (RESULT_SECTION === 'logs' || RESULT_SECTION === 'debug') ? '' : 'none';
  }}
  if (debugPanel && debugSummary && debugFailure && debugHighlights) {{
    const debug = data.debug || {{}};
    const bits = [
      `<span class="pill">Status: ${{resultEsc(debug.status || data.run.status_text || 'n/a')}}</span>`,
      `<span class="pill">Run Completion: ${{resultEsc(debug.run_completion || 'n/a')}}</span>`,
      `<span class="pill">Failure Count: ${{resultEsc(debug.required_failure_count ?? 'n/a')}}</span>`,
      `<span class="pill">Truth Contract OK: ${{resultEsc(debug.runtime_truth_contract_ok ?? data.run.runtime_truth_contract_ok ?? 'n/a')}}</span>`,
      `<span class="pill">Roundtrip Mismatches: ${{resultEsc(debug.roundtrip_mismatch_count ?? data.run.roundtrip_mismatch_count ?? 'n/a')}}</span>`,
      `<span class="pill">Runtime Evidence Missing: ${{resultEsc(debug.required_runtime_evidence_missing_count ?? data.run.required_runtime_evidence_missing_count ?? 'n/a')}}</span>`,
      `<span class="pill">Strict Truth Failures: ${{resultEsc(debug.strict_truth_failure_count ?? data.run.strict_truth_failure_count ?? 'n/a')}}</span>`
    ];
    if (debug.failure_identifier) bits.push(`<span class="pill">Identifier: ${{resultEsc(debug.failure_identifier)}}</span>`);
    debugSummary.innerHTML = bits.join('');
    debugFailure.textContent = debug.failure_message || 'No explicit failure message is recorded for this run.';
    debugHighlights.textContent = (debug.log_highlights || []).map((row) => `[${{row.time || ''}}] ${{row.level || 'INFO'}} ${{row.message || ''}}`).join('\\n') || 'No warning/error highlights yet.';
    debugPanel.style.display = RESULT_SECTION === 'debug' ? '' : 'none';
  }}
  if (issuePanel && issueBody) {{
    const issues = (((data.output_coverage || {{}}).issue_registry) || []);
    if (!issues.length) {{
      issueBody.innerHTML = '<tr><td colspan="9">No result issue registry rows are available for this run.</td></tr>';
    }} else {{
      issueBody.innerHTML = issues.map((row) => `<tr>`
        + `<td>${{resultEsc(row.severity || '')}}</td>`
        + `<td>${{resultEsc(row.issue_status || '')}}</td>`
        + `<td>${{resultEsc(row.issue_category || '')}}</td>`
        + `<td>${{resultEsc(row.block_name || '')}}</td>`
        + `<td>${{resultEsc(row.direction || '')}}</td>`
        + `<td>${{resultEsc(row.ue_id ?? '')}}</td>`
        + `<td>${{resultEsc(row.metric_name || '')}}</td>`
        + `<td>${{resultEsc(row.observed_value || '')}}</td>`
        + `<td>${{resultEsc(row.fix_plan || '')}}</td>`
        + `</tr>`).join('');
    }}
    issuePanel.style.display = (RESULT_SECTION === 'summary' || RESULT_SECTION === 'debug' || RESULT_SECTION === 'all') ? '' : 'none';
  }}
}}
function buildConstellationTraces(payload, lowered) {{
  const rows = payload.rows || [];
  const realIdx = lowered.indexOf('equalizedreal');
  const imagIdx = lowered.indexOf('equalizedimag');
  const decisionRealIdx = lowered.includes('harddecisionreal') ? lowered.indexOf('harddecisionreal') : null;
  const decisionImagIdx = lowered.includes('harddecisionimag') ? lowered.indexOf('harddecisionimag') : null;
  const equalized = {{ name: 'Equalized Symbols', x: [], y: [], mode: 'markers', type: 'scatter', marker: {{ size: 7 }} }};
  rows.forEach((row) => {{
    const xr = parseResultNumber(row[realIdx]);
    const yi = parseResultNumber(row[imagIdx]);
    if (xr !== null && yi !== null) {{
      equalized.x.push(xr);
      equalized.y.push(yi);
    }}
  }});
  const traces = [equalized];
  if (decisionRealIdx !== null && decisionImagIdx !== null) {{
    const hard = {{ name: 'Hard Decisions', x: [], y: [], mode: 'markers', type: 'scatter', marker: {{ size: 8, symbol: 'x' }} }};
    rows.forEach((row) => {{
      const xr = parseResultNumber(row[decisionRealIdx]);
      const yi = parseResultNumber(row[decisionImagIdx]);
      if (xr !== null && yi !== null) {{
        hard.x.push(xr);
        hard.y.push(yi);
      }}
    }});
    if (hard.x.length) traces.push(hard);
  }}
  return traces.filter((trace) => trace.x.length);
}}
function buildRawTrace(rows, xIdx, yIdx, label) {{
  const points = [];
  rows.forEach((row, rowIndex) => {{
    const yVal = parseResultNumber(row[yIdx]);
    if (yVal === null) return;
    const xVal = xIdx === null ? rowIndex + 1 : (parseResultNumber(row[xIdx]) ?? (rowIndex + 1));
    points.push({{ x: xVal, y: yVal }});
  }});
  points.sort((a, b) => Number(a.x) - Number(b.x));
  return points.length ? [{{ name: label, x: points.map((item) => item.x), y: points.map((item) => item.y), mode: 'lines+markers', type: 'scatter', line: {{ width: 2.5 }} }}] : [];
}}
function buildAggregateTrace(rows, xIdx, yIdx, label) {{
  const buckets = new Map();
  rows.forEach((row, rowIndex) => {{
    const yVal = parseResultNumber(row[yIdx]);
    if (yVal === null) return;
    const xVal = xIdx === null ? rowIndex + 1 : (parseResultNumber(row[xIdx]) ?? (rowIndex + 1));
    const key = Number(xVal);
    if (!buckets.has(key)) buckets.set(key, []);
    buckets.get(key).push(yVal);
  }});
  const sorted = Array.from(buckets.entries()).sort((a, b) => a[0] - b[0]);
  if (!sorted.length) return [];
  const x = [];
  const y = [];
  sorted.forEach(([key, values]) => {{
    x.push(key);
    y.push(values.reduce((sum, value) => sum + value, 0) / Math.max(values.length, 1));
  }});
  return [{{ name: `${{label}} (mean)`, x, y, mode: 'lines+markers', type: 'scatter', line: {{ width: 2.8 }} }}];
}}
function buildResultChartData(payload) {{
  const model = buildResultChartModel(payload);
  if (model.kind === 'empty') return {{ model, traces: [], xTitle: 'Index / Time', yTitle: 'Value' }};
  if (model.kind === 'constellation') {{
    return {{ model, traces: buildConstellationTraces(payload, model.lowered), xTitle: 'In-phase', yTitle: 'Quadrature' }};
  }}
  ensureResultChartState(model);
  const header = payload.header || [];
  const rows = payload.rows || [];
  const xIdx = header.indexOf(RESULT_CHART_STATE.xKey);
  const yIdx = header.indexOf(RESULT_CHART_STATE.yKey);
  if (yIdx < 0) {{
    return {{ model, traces: [], xTitle: 'Index / Time', yTitle: 'Value' }};
  }}
  const activeGroup = model.groupCandidates.find((item) => String(item.name) === RESULT_CHART_STATE.groupKey);
  const label = RESULT_CHART_STATE.yKey || 'Value';
  let traces = [];
  if (activeGroup) {{
    if (RESULT_CHART_STATE.groupValue === 'aggregate') {{
      traces = buildAggregateTrace(rows, xIdx >= 0 ? xIdx : null, yIdx, label);
    }} else {{
      const filtered = rows.filter((row) => String(row[activeGroup.idx] ?? '') === RESULT_CHART_STATE.groupValue);
      traces = buildRawTrace(filtered, xIdx >= 0 ? xIdx : null, yIdx, `${{label}} | ${{activeGroup.name}}=${{RESULT_CHART_STATE.groupValue}}`);
    }}
  }} else {{
    const rawTrace = buildRawTrace(rows, xIdx >= 0 ? xIdx : null, yIdx, label);
    const duplicateRatio = rawTrace.length && rawTrace[0].x.length
      ? (1 - (new Set(rawTrace[0].x).size / Math.max(rawTrace[0].x.length, 1)))
      : 0;
    traces = duplicateRatio >= 0.25 ? buildAggregateTrace(rows, xIdx >= 0 ? xIdx : null, yIdx, label) : rawTrace;
  }}
  return {{
    model,
    traces,
    xTitle: xIdx >= 0 ? String(header[xIdx]) : 'Index / Time',
    yTitle: String(header[yIdx] || 'Value'),
  }};
}}
function renderResultChartControls(payload) {{
  const host = document.getElementById('resultChartControls');
  if (!host) return;
  const model = buildResultChartModel(payload);
  if (model.kind === 'empty') {{
    host.innerHTML = '<span class="mini-note">No graph controls are available yet because this table preview has no rows.</span>';
    return;
  }}
  if (model.kind === 'constellation') {{
    host.innerHTML = '<span class="pill">Live constellation scatter</span><span class="mini-note">Equalized I/Q points are being rendered directly from the live DB table.</span>';
    return;
  }}
  ensureResultChartState(model);
  const xOptions = (model.xCandidates.length ? model.xCandidates : model.numericColumns)
    .map((item) => `<option value="${{resultEsc(item.name)}}"${{String(item.name) === RESULT_CHART_STATE.xKey ? ' selected' : ''}}>${{resultEsc(item.name)}}</option>`)
    .join('');
  const yOptions = model.yCandidates
    .filter((item) => String(item.name) !== RESULT_CHART_STATE.xKey)
    .map((item) => `<option value="${{resultEsc(item.name)}}"${{String(item.name) === RESULT_CHART_STATE.yKey ? ' selected' : ''}}>${{resultEsc(item.name)}}</option>`)
    .join('');
  const groupKeyOptions = ['<option value="">No grouping</option>'].concat(
    model.groupCandidates.map((item) => `<option value="${{resultEsc(item.name)}}"${{String(item.name) === RESULT_CHART_STATE.groupKey ? ' selected' : ''}}>${{resultEsc(item.name)}}</option>`)
  ).join('');
  const activeGroup = model.groupCandidates.find((item) => String(item.name) === RESULT_CHART_STATE.groupKey);
  const groupValueOptions = activeGroup
    ? ['<option value="aggregate">Aggregate Mean</option>'].concat(
        activeGroup.values.map((value) => `<option value="${{resultEsc(value)}}"${{String(value) === RESULT_CHART_STATE.groupValue ? ' selected' : ''}}>${{resultEsc(value)}}</option>`)
      ).join('')
    : '<option value="aggregate">Aggregate Mean</option>';
  host.innerHTML = `
    <label class="mini-note">Graph X
      <select id="resultChartX" style="margin-left:8px;"><option value="">Row Index</option>${{xOptions}}</select>
    </label>
    <label class="mini-note">Graph Metric
      <select id="resultChartY" style="margin-left:8px;">${{yOptions}}</select>
    </label>
    <label class="mini-note">Group By
      <select id="resultChartGroup" style="margin-left:8px;">${{groupKeyOptions}}</select>
    </label>
    <label class="mini-note">Series
      <select id="resultChartGroupValue" style="margin-left:8px;"${{activeGroup ? '' : ' disabled'}}>${{groupValueOptions}}</select>
    </label>
  `;
  const xSelect = document.getElementById('resultChartX');
  const ySelect = document.getElementById('resultChartY');
  const groupSelect = document.getElementById('resultChartGroup');
  const valueSelect = document.getElementById('resultChartGroupValue');
  if (xSelect) xSelect.addEventListener('change', () => {{
    RESULT_CHART_STATE.xKey = xSelect.value || '';
    renderResultChart(payload);
    renderResultChartControls(payload);
  }});
  if (ySelect) ySelect.addEventListener('change', () => {{
    RESULT_CHART_STATE.yKey = ySelect.value || '';
    renderResultChart(payload);
  }});
  if (groupSelect) groupSelect.addEventListener('change', () => {{
    RESULT_CHART_STATE.groupKey = groupSelect.value || '';
    RESULT_CHART_STATE.groupValue = 'aggregate';
    renderResultChartControls(payload);
    renderResultChart(payload);
  }});
  if (valueSelect) valueSelect.addEventListener('change', () => {{
    RESULT_CHART_STATE.groupValue = valueSelect.value || 'aggregate';
    renderResultChart(payload);
  }});
}}
function renderResultChart(payload) {{
  const host = document.getElementById('resultChart');
  if (!host) return;
  if (!window.Plotly) {{
    host.innerHTML = '<div class="chart-empty">Interactive chart library is unavailable, but the live table preview is still working.</div>';
    return;
  }}
  const chart = buildResultChartData(payload);
  const traces = chart.traces || [];
  if (!traces.length) {{
    host.innerHTML = '<div class="chart-empty">This table does not expose enough numeric columns for a live plot.</div>';
    return;
  }}
  Plotly.react(
    host,
    traces,
    {{
      paper_bgcolor: 'rgba(0,0,0,0)',
      plot_bgcolor: 'rgba(255,255,255,0.94)',
      margin: {{ l: 48, r: 18, t: 28, b: 42 }},
      legend: {{ orientation: 'h' }},
      xaxis: {{ title: chart.xTitle, gridcolor: 'rgba(133,150,178,0.18)' }},
      yaxis: {{ title: chart.yTitle, gridcolor: 'rgba(133,150,178,0.18)' }},
      hovermode: traces.some((trace) => trace.mode === 'markers') ? 'closest' : 'x unified',
    }},
    {{ responsive: true, displaylogo: false, scrollZoom: true }}
  );
}}
async function loadSelectedTable() {{
  if (!CURRENT_TABLE_ID) {{
    document.getElementById('resultChartControls').innerHTML = '<span class="mini-note">Choose a table to configure its graph.</span>';
    document.getElementById('resultPreview').innerHTML = '<p class="muted">No table selected yet.</p>';
    document.getElementById('resultChart').innerHTML = '<div class="chart-empty">Choose a table to see its live chart.</div>';
    return;
  }}
  let payload = null;
  if (RESULT_INITIAL_PREVIEW && RESULT_INITIAL_PREVIEW.meta && Number(RESULT_INITIAL_PREVIEW.meta.artifact_id) === Number(CURRENT_TABLE_ID)) {{
    payload = RESULT_INITIAL_PREVIEW;
  }} else {{
    payload = await resultFetchJson(`/api/artifact/${{CURRENT_TABLE_ID}}/preview`);
  }}
  const meta = payload.meta || {{}};
  document.getElementById('resultTableMeta').innerHTML =
    `<span class="pill">${{resultEsc(meta.logical_path || '')}}</span><span class="pill">${{resultEsc(meta.byte_size || '')}} bytes</span><span class="pill">${{resultEsc(meta.created_utc || '')}}</span>`;
  document.getElementById('resultActions').innerHTML =
    `<a class="button-link secondary" href="/artifact/${{CURRENT_TABLE_ID}}/raw?download=1">Download CSV</a><a class="button-link secondary" href="/artifact/${{CURRENT_TABLE_ID}}/table">Open Full Preview</a>`;
  RESULT_CURRENT_PREVIEW = payload;
  renderPreviewTable(payload);
  renderResultChartControls(payload);
  renderResultChart(payload);
}}
function buildResultSectionAvailabilityMessage(data) {{
  const stage = data?.runtime_context?.stage || {{}};
  const notes = [];
  if (RESULT_SECTION === 'scheduler') {{
    notes.push('This waveform LLS profile does not publish a true MAC scheduler or grant trace unless a system-level grant source is attached.');
  }}
  if (RESULT_SECTION === 'pusch' && !resultTruthyFlag(stage.ULTrialsReady)) {{
    notes.push('UL PUSCH trial streaming has not reached MySQL yet for the active run.');
  }}
  if (RESULT_SECTION === 'harq' && !resultTruthyFlag(stage.HARQReady)) {{
    notes.push('HARQ diagnostics are suppressed until the DL/UL raw trial chain has completed enough evidence to support a truthful HARQ export.');
  }}
  if (RESULT_SECTION === 'beam' && !resultTruthyFlag(stage.BeamReady)) {{
    notes.push('Beam diagnostics are published only after the raw DL/UL evidence has been aggregated into live beam statistics.');
  }}
  if (RESULT_SECTION === 'rf' && !resultTruthyFlag(stage.RFReady)) {{
    notes.push('RF diagnostics and energy exports are not ready yet.');
  }}
  if (RESULT_SECTION === 'rf') {{
    notes.push('In coupled truth mode, RSRP is a serving-cell reference-signal power from the canonical slot runtime, while displayed receiver SINR is the Hest/CSI wideband estimate carried out of the active PDSCH/PUSCH trial row. Decoder-truth proxy SINR and large-scale preview SINR, when present, are shown separately.');
  }}
  if (RESULT_SECTION === 'csi') {{
    notes.push('CSI tables are aggregated from the active DL/UL trial chain and sounding/control evidence. They are not direct RSRP tables, so do not compare them one-to-one with RF map snapshots without checking the source columns.');
  }}
  if (RESULT_SECTION === 'logs') {{
    notes.push('This section streams directly from sim_run_logs in MySQL rather than from CSV artifacts.');
  }}
  return notes.length ? `<div class="warning" style="margin-top:12px;">${{notes.map((note) => resultEsc(note)).join('<br>')}}</div>` : '';
}}
function renderTableTabs(tables, data) {{
  const host = document.getElementById('resultTabBar');
  if (!tables.length) {{
    const sectionCounts = data?.section_counts || {{}};
    const stage = data?.runtime_context?.stage || {{}};
    const nonEmptySections = Object.entries(sectionCounts)
      .filter(([key, value]) => Number(value || 0) > 0)
      .map(([key, value]) => `${{key}}=${{value}}`)
      .join(', ');
    const emptyText = RESULT_SECTION === 'all'
      ? 'No table artifacts have reached MySQL yet.'
      : `No tables are currently published for ${{resultEsc(RESULT_SECTION.toUpperCase())}}.`;
    const stageText = stage.CurrentStage || stage.StageName || stage.Stage
      ? `<div class="warning" style="margin-top:12px;">Current live stage: ${{resultEsc(stage.CurrentStage || stage.StageName || stage.Stage)}}${{stage.Notes ? ` | ${{resultEsc(stage.Notes)}}` : ''}}</div>`
      : '';
    const sectionText = nonEmptySections
      ? `<div class="mini-note" style="margin-top:10px;">Currently populated sections: ${{resultEsc(nonEmptySections)}}</div>`
      : '';
    host.innerHTML = `<div><span class="mini-note">${{emptyText}}</span>${{sectionText}}${{stageText}}${{buildResultSectionAvailabilityMessage(data)}}</div>`;
    CURRENT_TABLE_ID = null;
    RESULT_CURRENT_PREVIEW = null;
    document.getElementById('resultChartControls').innerHTML = '<span class="mini-note">No graph controls are available for this section yet.</span>';
    document.getElementById('resultPreview').innerHTML = '<p class="muted">Waiting for a matching table preview.</p>';
    document.getElementById('resultChart').innerHTML = '<div class="chart-empty">This section has not published a chartable table yet.</div>';
    return;
  }}
  if (!CURRENT_TABLE_ID || !tables.some((item) => item.artifact_id === CURRENT_TABLE_ID)) {{
    CURRENT_TABLE_ID = tables[0].artifact_id;
  }}
  host.innerHTML = tables.map((item) => `<button type="button" class="subtab-button ${{item.artifact_id === CURRENT_TABLE_ID ? 'active' : ''}}" data-table-id="${{item.artifact_id}}">${{resultEsc(item.logical_path)}}</button>`).join('');
  host.querySelectorAll('[data-table-id]').forEach((button) => {{
    button.addEventListener('click', async () => {{
      CURRENT_TABLE_ID = Number(button.dataset.tableId);
      renderTableTabs(tables);
      await loadSelectedTable();
    }});
  }});
}}
async function applyResultData(data) {{
  if (!data || !data.run) throw new Error('Result payload is empty.');
  RESULT_LATEST_DATA = data;
  document.getElementById('resultHeadline').innerHTML = `<span class="live-dot"></span>Result | Run ${{resultEsc(data.run.run_id)}} | ${{resultEsc(data.run.scenario_id)}}`;
  const tables = filterTablesBySection(data.tables_all || []);
  const images = filterImagesBySection(data.images_all || []);
  const sectionCounts = data.section_counts || {{}};
  const counts = data.counts || {{}};
  document.getElementById('resultMeta').innerHTML = `<span class="pill">Status: ${{resultEsc(data.run.status_text)}}</span><span class="pill">Run Completion: ${{resultEsc(data.run.run_completion || 'n/a')}}</span><span class="pill">Result OK: ${{resultEsc(data.run.result_ok ?? 'n/a')}}</span><span class="pill">Required Failures: ${{resultEsc(data.run.required_failure_count ?? 'n/a')}}</span><span class="pill">Truth Contract OK: ${{resultEsc(data.run.runtime_truth_contract_ok ?? 'n/a')}}</span><span class="pill">Roundtrip Mismatches: ${{resultEsc(data.run.roundtrip_mismatch_count ?? 'n/a')}}</span><span class="pill">Runtime Evidence Missing: ${{resultEsc(data.run.required_runtime_evidence_missing_count ?? 'n/a')}}</span><span class="pill">Strict Truth Failures: ${{resultEsc(data.run.strict_truth_failure_count ?? 'n/a')}}</span><span class="pill">Failing Cases: ${{resultEsc(data.run.failing_case_count ?? 'n/a')}}</span><span class="pill">Warnings: ${{resultEsc(data.run.warning_count ?? 'n/a')}}</span><span class="pill">Visible Tables: ${{resultEsc(tables.length)}}</span><span class="pill">Visible Images: ${{resultEsc(images.length)}}</span><span class="pill">All Tables: ${{resultEsc(counts.tables_total)}}</span><span class="pill">Updated: ${{resultEsc(data.run.updated_utc)}}</span>`;
  try {{ renderRuntimeContext(data.runtime_context || {{}}); }} catch (err) {{ console.error('runtime context render failed', err); }}
  try {{
    const metrics = [{{label:'Artifacts', value:counts.artifacts_total}}, {{label:'Tables', value:counts.tables_total}}, {{label:'Images', value:counts.images_total}}, {{label:'Logs', value:counts.logs_total}}, ...(data.metrics || []).slice(0, 8)];
    document.getElementById('resultMetricGrid').innerHTML = metrics.map((item) => `<div class="metric-card"><div class="metric-value">${{resultEsc(item.value)}}</div><div class="metric-label">${{resultEsc(item.label)}}${{item.source ? ' | ' + resultEsc(item.source) : ''}}</div></div>`).join('');
  }} catch (err) {{ console.error('metric render failed', err); }}
  try {{
    renderResultImageGrid(images, sectionCounts);
  }} catch (err) {{ console.error('image render failed', err); }}
  try {{ renderResultAuxPanels(data); }} catch (err) {{ console.error('aux panel render failed', err); }}
  const previous = CURRENT_TABLE_ID;
  try {{ renderTableTabs(tables, data); }} catch (err) {{ console.error('tab render failed', err); }}
  try {{
    if (CURRENT_TABLE_ID && (CURRENT_TABLE_ID !== previous || !document.getElementById('resultPreview').dataset.loaded)) {{
      await loadSelectedTable();
      document.getElementById('resultPreview').dataset.loaded = '1';
    }}
  }} catch (err) {{
    console.error('table preview render failed', err);
    document.getElementById('resultPreview').innerHTML = `<p class="warning">Live table preview failed: ${{resultEsc(err)}}</p>`;
  }}
}}
async function refreshResult() {{
  const resolvedRunId = await resolveResultRunId();
  if (resolvedRunId === null) {{
    document.getElementById('resultHeadline').innerHTML = `<span class="live-dot"></span>Waiting for run tag ${{resultEsc(RESULT_RUN_TAG)}} to appear in MySQL...`;
    document.getElementById('resultMeta').innerHTML = '<span class="pill">Launch accepted</span><span class="pill">Waiting for sim_runs row</span>';
    scheduleResultRefresh(3000);
    return;
  }}
  let data = await resultFetchJson(`/api/run/${{resolvedRunId}}/live?lite=1`);
  if (!RESULT_FULL_PAYLOAD || (data.artifact_version && data.artifact_version !== RESULT_ARTIFACT_VERSION)) {{
    data = await resultFetchJson(`/api/run/${{resolvedRunId}}/live`);
    RESULT_FULL_PAYLOAD = data;
    RESULT_ARTIFACT_VERSION = data.artifact_version || '';
  }} else {{
    data = mergeResultPayload(RESULT_FULL_PAYLOAD, data);
    RESULT_FULL_PAYLOAD = data;
  }}
  await applyResultData(data);
  scheduleResultRefresh(resultNextPollDelay(data));
}}
if (RESULT_INITIAL_PAYLOAD && RESULT_INITIAL_PAYLOAD.run) {{
  applyResultData(RESULT_INITIAL_PAYLOAD).catch((err) => {{ console.error('initial result render failed', err); }});
}}
refreshResult().catch((err) => {{ document.getElementById('resultPreview').innerHTML = `<p class="warning">Live result refresh failed: ${{resultEsc(err)}}</p>`; }});
document.addEventListener('visibilitychange', () => scheduleResultRefresh(500));
</script>
"""


def build_result_page(run_id: int | None, run_tag: str | None = None, message: str = "", section: str = "all", user_profile: dict[str, Any] | None = None) -> bytes:
    section = normalize_result_section(section)
    if run_id is None and not run_tag:
        run_id = latest_run_id()
    if run_id is None and not run_tag:
        return page_shell("Result", '<section class="panel"><h2>Result</h2><p>No runs found.</p></section>', active="result", user_profile=user_profile)
    initial_payload = build_live_payload(run_id) if run_id is not None else None
    initial_preview = None
    if initial_payload is not None:
        initial_tables = [item for item in initial_payload.get("tables_all", []) if normalize_result_section(str(item.get("section") or "other")) == section] if section != "all" else list(initial_payload.get("tables_all", []))
        if initial_tables:
            first_artifact_id = int(initial_tables[0]["artifact_id"])
            initial_preview = build_table_preview_payload(first_artifact_id)
    message_html = f'<section class="panel"><strong>{html.escape(message)}</strong></section>' if message else ""
    title_token = str(run_id) if run_id is not None else (run_tag or "pending")
    section_links = build_result_section_links(section, run_id=run_id, run_tag=run_tag)
    body = f"""
    {message_html}
    <section class="panel">
      <h2 id="resultHeadline">Loading result {html.escape(title_token)}...</h2>
      <div id="resultMeta" class="toolbar"></div>
      <div id="resultMetricGrid" class="metric-grid" style="margin-top:14px;"></div>
      <div id="resultContext" class="toolbar" style="margin-top:14px;flex-wrap:wrap;"></div>
      <p class="muted">Tables are grouped by LLS block here, so you can jump straight to routes like <code>/result/pdsch</code> or <code>/result/pusch</code>. Inside each block, every DB table still gets its own live tab and download link.</p>
    </section>
    <section class="panel">
      <div class="panel-scroll-x"><div class="subtab-bar">{section_links}</div></div>
      <div class="panel-scroll-x"><div id="resultTabBar" class="tabular-tabs"></div></div>
      <div id="resultTableMeta" class="table-meta"></div>
      <div id="resultActions" class="toolbar"></div>
      <div id="resultChartControls" class="toolbar" style="margin-top:14px;flex-wrap:wrap;gap:12px;"></div>
      <div id="resultChart" class="chart-box" style="margin-top:14px;"></div>
      <div id="resultPreview" style="margin-top:14px;"></div>
    </section>
    <section class="panel" id="resultIssuePanel" style="display:none;">
      <h2>Result Issue Registry</h2>
      <p class="muted">These rows come from <code>reports/csv/result_issue_registry.csv</code> and point back to the source artifact that triggered each issue.</p>
      <div class="table-scroll">
        <table>
          <thead><tr><th>Severity</th><th>Status</th><th>Category</th><th>Block</th><th>Direction</th><th>UE</th><th>Metric</th><th>Observed</th><th>Fix Plan</th></tr></thead>
          <tbody id="resultIssueBody"><tr><td colspan="9">Loading...</td></tr></tbody>
        </table>
      </div>
    </section>
    <section class="panel" id="resultLogsPanel" style="display:none;">
      <h2>Live Logs</h2>
      <p class="muted">These rows come directly from <code>sim_run_logs</code> and refresh live while MATLAB is running.</p>
      <pre id="resultLogBox">Loading...</pre>
    </section>
    <section class="panel" id="resultDebugPanel" style="display:none;">
      <h2>Debug Summary</h2>
      <div id="resultDebugSummary" class="toolbar"></div>
      <div class="two-col" style="margin-top:14px;">
        <section class="panel"><h3>Failure Summary</h3><pre id="resultDebugFailure">Loading...</pre></section>
        <section class="panel"><h3>Highlights</h3><pre id="resultDebugHighlights">Loading...</pre></section>
      </div>
    </section>
    <section class="panel">
      <h2>Section Images</h2>
      <p class="muted">Images shown here come directly from MySQL-backed artifacts for the selected LLS block while the run is active.</p>
      <div id="resultImageGrid" class="artifact-grid"></div>
    </section>
    """
    return page_shell(
        f"Result {RESULT_SECTION_LABELS[section]} {title_token}",
        body,
        active="result",
        run_id=run_id,
        extra_head='<script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>',
        extra_script=result_page_script(run_id, run_tag=run_tag, section=section, initial_payload=initial_payload, initial_preview=initial_preview),
        user_profile=user_profile,
    )


def build_tables_page(run_id: int | None, user_profile: dict[str, Any] | None = None) -> bytes:
    return build_result_page(run_id, section="all", user_profile=user_profile)


def build_images_page(run_id: int | None, user_profile: dict[str, Any] | None = None) -> bytes:
    run_id = run_id or latest_run_id()
    if run_id is None:
        return page_shell("Images", '<section class="panel"><h2>Images</h2><p>No runs found.</p></section>', active="images", user_profile=user_profile)
    artifacts = [art for art in fetch_artifacts(run_id) if str(art.get("mime_type") or "").startswith("image/")]
    cards = []
    for art in artifacts:
        art_id = int(art["artifact_id"])
        cards.append(
            "<div class=\"artifact-card\">"
            f"<h3>{html.escape(str(art['logical_path']))}</h3>"
            f"<p class=\"muted\">{html.escape(str(art['created_utc']))} | {art['byte_size']} bytes</p>"
            f"<a href=\"{artifact_url(art_id)}\" target=\"_blank\" rel=\"noopener noreferrer\"><img loading=\"lazy\" decoding=\"async\" src=\"{artifact_url(art_id)}\" alt=\"artifact {art_id}\"></a>"
            f"<div class=\"toolbar\"><a href=\"{artifact_url(art_id)}\" target=\"_blank\" rel=\"noopener noreferrer\">Open In New Tab</a><a href=\"{artifact_url(art_id, download=True)}\">Download Image</a></div>"
            "</div>"
        )
    body = f"""
    <section class="panel">
      <h2>Images For Run {run_id}</h2>
      <div class="artifact-grid">
        {''.join(cards) if cards else '<p>No image artifacts were found for this run.</p>'}
      </div>
    </section>
    """
    return page_shell(f"Images {run_id}", body, active="images", run_id=run_id, user_profile=user_profile)


def build_logs_page(run_id: int | None, user_profile: dict[str, Any] | None = None) -> bytes:
    run_id = run_id or latest_run_id()
    if run_id is None:
        return page_shell("Logs", '<section class="panel"><h2>Logs</h2><p>No runs found.</p></section>', active="logs", user_profile=user_profile)
    sync_runtime_log_for_run(fetch_run(run_id))
    logs = fetch_logs(run_id, limit=MAX_LIVE_LOG_ROWS, descending=True)
    body = f"""
    <section class="panel">
      <h2>Logs For Run {run_id}</h2>
      <pre>{html.escape(render_log_lines(logs))}</pre>
    </section>
    """
    return page_shell(f"Logs {run_id}", body, active="logs", run_id=run_id, user_profile=user_profile)


def build_table_preview_page(artifact_id: int, user_profile: dict[str, Any] | None = None) -> bytes:
    meta = fetch_artifact_meta(artifact_id)
    if meta is None:
        raise KeyError(f"Artifact {artifact_id} was not found.")
    header, rows = load_cached_csv_preview(int(artifact_id), MAX_TABLE_PREVIEW_ROWS)
    head_html = "".join(f"<th>{html.escape(cell)}</th>" for cell in header)
    body_rows = ["<tr>" + "".join(f"<td>{html.escape(cell)}</td>" for cell in row) + "</tr>" for row in rows]
    body = f"""
    <section class="panel">
      <h2>Table Preview</h2>
      <p class="muted"><strong>{html.escape(str(meta['logical_path']))}</strong></p>
      <div class="toolbar">
        <a class="button-link secondary" href="{artifact_url(artifact_id, download=True)}">Download CSV</a>
        <a class="button-link secondary" href="/result?run_id={int(meta['run_id'])}">Back To Result</a>
      </div>
      <div class="table-scroll" style="margin-top:14px;">
        <table><thead><tr>{head_html}</tr></thead><tbody>{''.join(body_rows) if body_rows else '<tr><td>No rows found.</td></tr>'}</tbody></table>
      </div>
    </section>
    """
    return page_shell(f"Artifact {artifact_id}", body, active="result", run_id=int(meta["run_id"]), user_profile=user_profile)


def analytics_page_script(
    run_id: int | None,
    run_tag: str | None = None,
    *,
    initial_payload: dict[str, Any] | None = None,
) -> str:
    run_id_literal = "null" if run_id is None else str(run_id)
    run_tag_literal = json.dumps(run_tag or "")
    initial_payload_literal = json_for_script(initial_payload)
    script = """
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script>
let RUN_ID = __RUN_ID__;
const RUN_TAG = __RUN_TAG__;
const POLL_MS = __POLL_MS__;
const ANALYTICS_INITIAL_PAYLOAD = __INITIAL_PAYLOAD__;
let CURRENT_ANALYTICS_TAB = 'overview';
let CURRENT_CHART_ID = null;
let ANALYTICS_MAP = null;
let ANALYTICS_LAYER = null;
let CURRENT_MAP_PAYLOAD = null;
let CURRENT_MAP_METRIC = 'RSRP_dBm';
let CURRENT_MAP_SLOT = null;
let ANALYTICS_IMAGE_ITEMS = [];
let ANALYTICS_IMAGE_SIGNATURE = '';
let ANALYTICS_IMAGE_LIMIT = 18;
let ANALYTICS_REFRESH_TIMER = null;
let ANALYTICS_FULL_PAYLOAD = ANALYTICS_INITIAL_PAYLOAD;
let ANALYTICS_ARTIFACT_VERSION = ANALYTICS_INITIAL_PAYLOAD ? ANALYTICS_INITIAL_PAYLOAD.artifact_version : '';
function fmt(v) {{ return (v === null || v === undefined || v === '') ? 'n/a' : String(v); }}
function esc(value) {{
  return String(value ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}}
async function analyticsFetchJson(url) {{
  const resp = await fetch(url, {{ credentials: 'same-origin' }});
  if (resp.status === 401) {{
    let loginUrl = '/login';
    try {{
      const payload = await resp.json();
      if (payload && payload.login_url) loginUrl = payload.login_url;
    }} catch (_err) {{}}
    throw new Error(`Authentication required. Sign in again via ${{loginUrl}}`);
  }}
  if (!resp.ok) throw new Error(`HTTP ${{resp.status}}`);
  return resp.json();
}}
function mergeAnalyticsPayload(previous, incoming) {{
  if (!previous) return incoming;
  if (!incoming) return previous;
  const merged = {{ ...previous, ...incoming }};
  const stickyKeys = ['tables_all', 'tables_recent', 'tables_summary', 'images_all', 'images_recent', 'output_coverage', 'feature_policy', 'contract_surface', 'output_contract', 'timing', 'map', 'metric_explorer', 'debug'];
  stickyKeys.forEach((key) => {{
    if (incoming[key] === undefined) merged[key] = previous[key];
  }});
  merged.charts = {{ ...(previous.charts || {{}}), ...(incoming.charts || {{}}) }};
  return merged;
}}
function analyticsArtifactSignature(items) {{
  return (items || []).map((item) => `${{item.artifact_id}}:${{item.byte_size}}`).join('|');
}}
function analyticsArtifactCard(item) {{
  return `<div class="artifact-card"><h3>${{esc(item.logical_path)}}</h3><a href="${{esc(item.view_url)}}" target="_blank" rel="noopener noreferrer"><img loading="lazy" decoding="async" src="${{esc(item.view_url)}}" alt="${{esc(item.logical_path)}}" /></a><div class="toolbar"><a href="${{esc(item.view_url)}}" target="_blank" rel="noopener noreferrer">Open In New Tab</a><a href="${{esc(item.download_url)}}">Download Image</a></div></div>`;
}}
function analyticsFeaturedImageScore(item) {{
  const path = String((item && item.logical_path) || '').toLowerCase();
  if (!path) return -1;
  const scoreTable = [
    ['post-equalization-constellation', 100],
    ['evm-rms', 95],
    ['constellation-per-modulation-order', 90],
    ['symbol-decision-error-histogram', 85],
    ['tx-waveform', 82],
    ['rx-waveform', 80],
    ['resource-grid', 78],
    ['throughput-vs-sinr', 76],
    ['bler-vs-sinr', 74],
    ['ber-vs-sinr', 72],
    ['sinr', 70],
    ['throughput', 68],
    ['goodput', 66],
  ];
  for (const [token, score] of scoreTable) {{
    if (path.includes(token)) return score;
  }}
  if (/(constellation|evm|waveform|resource[_-]?grid|throughput|goodput|bler|ber|sinr)/.test(path)) return 50;
  return -1;
}}
function selectAnalyticsOverviewImages(items) {{
  return [...(items || [])]
    .map((item) => ({{ item, score: analyticsFeaturedImageScore(item) }}))
    .filter((entry) => entry.score >= 0)
    .sort((a, b) => {{
      if (b.score !== a.score) return b.score - a.score;
      const ar = Number(a.item.display_rank ?? 999);
      const br = Number(b.item.display_rank ?? 999);
      if (ar !== br) return ar - br;
      return String(a.item.logical_path || '').localeCompare(String(b.item.logical_path || ''));
    }})
    .slice(0, 6)
    .map((entry) => entry.item);
}}
function renderAnalyticsOverviewImages(items) {{
  const host = document.getElementById('overviewImageGrid');
  if (!host) return;
  const featured = selectAnalyticsOverviewImages(items);
  if (!featured.length) {{
    host.innerHTML = '<p class="muted">No featured PHY visuals are available yet. Open the Images tab for the full artifact list.</p>';
    return;
  }}
  host.innerHTML = featured.map((item) => analyticsArtifactCard(item)).join('') +
    '<div class="toolbar" style="margin-top:14px;"><button type="button" id="openAnalyticsImagesTab">Open Full Image Gallery</button></div>';
  const button = document.getElementById('openAnalyticsImagesTab');
  if (button) {{
    button.addEventListener('click', () => activateAnalyticsTab('images'));
  }}
}}
function renderAnalyticsImageGrid(force=false) {{
  const host = document.getElementById('imageGrid');
  if (!host) return;
  if (!force && CURRENT_ANALYTICS_TAB !== 'images') return;
  const signature = analyticsArtifactSignature(ANALYTICS_IMAGE_ITEMS);
  const nextState = `${{signature}}|${{ANALYTICS_IMAGE_LIMIT}}`;
  if (host.dataset.state === nextState) return;
  const visible = ANALYTICS_IMAGE_ITEMS.slice(0, ANALYTICS_IMAGE_LIMIT);
  host.dataset.state = nextState;
  host.innerHTML = visible.map((item) => analyticsArtifactCard(item)).join('') || '<p>No images published yet.</p>';
  if (ANALYTICS_IMAGE_ITEMS.length > ANALYTICS_IMAGE_LIMIT) {{
    host.insertAdjacentHTML('beforeend', `<div class="toolbar" style="margin-top:14px;"><button type="button" id="analyticsLoadMoreImages">Load More Images (${{esc(ANALYTICS_IMAGE_ITEMS.length - ANALYTICS_IMAGE_LIMIT)}} remaining)</button></div>`);
    const button = document.getElementById('analyticsLoadMoreImages');
    if (button) {{
      button.addEventListener('click', () => {{
        ANALYTICS_IMAGE_LIMIT = Math.min(ANALYTICS_IMAGE_LIMIT + 18, ANALYTICS_IMAGE_ITEMS.length);
        renderAnalyticsImageGrid(true);
      }});
    }}
  }}
}}
function analyticsNextPollDelay(data) {{
  const status = String(((data || {{}}).run || {{}}).status_text || '').toLowerCase();
  const visible = document.visibilityState === 'visible';
  if (status === 'running') return visible ? POLL_MS : Math.max(POLL_MS * 4, 4000);
  if (status === 'completed' || status === 'completed_with_failures' || status === 'failed' || status === 'stopped' || status.startsWith('aborted')) {{
    return visible ? 15000 : 30000;
  }}
  return visible ? 5000 : 15000;
}}
function scheduleAnalyticsRefresh(delayMs) {{
  if (ANALYTICS_REFRESH_TIMER) window.clearTimeout(ANALYTICS_REFRESH_TIMER);
  ANALYTICS_REFRESH_TIMER = window.setTimeout(() => {{
    refreshAnalytics().catch((err) => {{
      document.getElementById('logBox').textContent = `Live refresh failed: ${{err}}`;
      scheduleAnalyticsRefresh(15000);
    }});
  }}, Math.max(750, Number(delayMs) || POLL_MS));
}}
function activateAnalyticsTab(name) {{
  CURRENT_ANALYTICS_TAB = name;
  document.querySelectorAll('[data-analytics-tab-button]').forEach((el) => el.classList.toggle('active', el.dataset.analyticsTabButton === name));
  document.querySelectorAll('[data-analytics-tab-panel]').forEach((el) => el.classList.toggle('active', el.dataset.analyticsTabPanel === name));
  if (name === 'map' && ANALYTICS_MAP) {{
    window.setTimeout(() => ANALYTICS_MAP.invalidateSize(), 80);
  }}
  if (name === 'images') {{
    renderAnalyticsImageGrid(true);
  }}
}}
async function resolveRunId() {{
  if (RUN_ID !== null && RUN_ID !== undefined) return RUN_ID;
  if (!RUN_TAG) return null;
  const data = await analyticsFetchJson(`/api/runs?run_tag=${{encodeURIComponent(RUN_TAG)}}&limit=1`);
  const runs = data.runs || [];
  if (runs.length > 0) {{
    RUN_ID = runs[0].run_id;
    const clean = new URL(window.location.href);
    clean.searchParams.set('run_id', String(RUN_ID));
    clean.searchParams.delete('run_tag');
    window.history.replaceState(null, '', clean.toString());
    return RUN_ID;
  }}
  return null;
}}
function timeValue(x) {{ if (typeof x === 'number') return x; const p = Date.parse(x); return Number.isNaN(p) ? null : p; }}
function drawChart(hostId, chart) {{
  const host = document.getElementById(hostId);
  if (!host) return;
  if (!chart || !chart.series || chart.series.length === 0) {{ host.innerHTML = '<div class="chart-empty">No chart data available yet.</div>'; return; }}
  const width = Math.max(host.clientWidth || 400, 400), height = 220, pad = {{left:42,right:18,top:18,bottom:28}};
  const prepared = []; let xmin=null,xmax=null,ymin=null,ymax=null;
  for (const series of chart.series) {{
    const pts = [];
    for (const point of (series.points || [])) {{
      const x = typeof point.x === 'number' ? point.x : timeValue(point.x);
      const y = Number(point.y);
      if (x === null || Number.isNaN(y)) continue;
      pts.push({{x,y}}); xmin = xmin===null ? x : Math.min(xmin,x); xmax = xmax===null ? x : Math.max(xmax,x); ymin = ymin===null ? y : Math.min(ymin,y); ymax = ymax===null ? y : Math.max(ymax,y);
    }}
    if (pts.length) prepared.push({{name:series.name,points:pts}});
  }}
  if (!prepared.length) {{ host.innerHTML = '<div class="chart-empty">No numeric points available yet.</div>'; return; }}
  if (window.Plotly) {{
    const traces = prepared.map((series) => {{
      return {{
        name: series.name,
        x: series.points.map((pt) => pt.x),
        y: series.points.map((pt) => pt.y),
        mode: series.mode || 'lines+markers',
        type: 'scatter',
        line: {{ width: 2.5 }},
        marker: {{ size: 6 }},
      }};
    }});
    const downloads = chart.download_url ? `<a class="button-link secondary" href="${{esc(chart.download_url)}}">Download Source CSV</a>` : '';
    host.innerHTML = `<div class="toolbar" style="justify-content:space-between;align-items:flex-start;"><div style="font-weight:700;margin-bottom:8px;">${{esc(chart.title || 'Chart')}}</div><div>${{downloads}}</div></div><div id="${{hostId}}_plot" style="width:100%;height:360px;"></div>`;
    Plotly.react(
      document.getElementById(`${{hostId}}_plot`),
      traces,
      {{
        paper_bgcolor: 'rgba(0,0,0,0)',
        plot_bgcolor: 'rgba(255,255,255,0.95)',
        margin: {{ l: 50, r: 20, t: 20, b: 42 }},
        legend: {{ orientation: 'h' }},
        xaxis: {{ title: chart.xaxis_title || 'Index / Time', gridcolor: 'rgba(133,150,178,0.18)' }},
        yaxis: {{ title: chart.yaxis_title || 'Value', gridcolor: 'rgba(133,150,178,0.18)' }},
        hovermode: 'closest',
      }},
      {{ responsive: true, displaylogo: false, scrollZoom: true }}
    );
    return;
  }}
  if (xmin === xmax) xmax = xmin + 1; if (ymin === ymax) ymax = ymin + 1;
  const sx = (x) => pad.left + ((x-xmin)/(xmax-xmin))*(width-pad.left-pad.right);
  const sy = (y) => height-pad.bottom - ((y-ymin)/(ymax-ymin))*(height-pad.top-pad.bottom);
  const colors = ['#0d5c63','#f59e0b','#a63d40','#2563eb','#7c3aed'];
  const lines = prepared.map((series, idx) => `<polyline fill="none" stroke="${{colors[idx % colors.length]}}" stroke-width="2.8" points="${{series.points.map((pt) => `${{sx(pt.x).toFixed(1)}},${{sy(pt.y).toFixed(1)}}`).join(' ')}}" />`).join('');
  const legend = prepared.map((series, idx) => `<span class="pill" style="background:#fff;border:1px solid #d7d0c1;color:${{colors[idx % colors.length]}}">${{esc(series.name)}}</span>`).join('');
  const ticks = [0,0.25,0.5,0.75,1].map((r) => {{ const y = pad.top + r*(height-pad.top-pad.bottom); return `<line x1="${{pad.left}}" y1="${{y.toFixed(1)}}" x2="${{width-pad.right}}" y2="${{y.toFixed(1)}}" stroke="#ece4d7" />`; }}).join('');
  const downloads = chart.download_url ? `<a class="button-link secondary" href="${{esc(chart.download_url)}}">Download Source CSV</a>` : '';
  host.innerHTML = `<div class="toolbar" style="justify-content:space-between;align-items:flex-start;"><div style="font-weight:700;margin-bottom:8px;">${{esc(chart.title || 'Chart')}}</div><div>${{downloads}}</div></div><div style="margin-bottom:8px;">${{legend}}</div><svg class="chart-svg" viewBox="0 0 ${{width}} ${{height}}" preserveAspectRatio="none">${{ticks}}<line x1="${{pad.left}}" y1="${{height-pad.bottom}}" x2="${{width-pad.right}}" y2="${{height-pad.bottom}}" stroke="#cbbfa9" /><line x1="${{pad.left}}" y1="${{pad.top}}" x2="${{pad.left}}" y2="${{height-pad.bottom}}" stroke="#cbbfa9" />${{lines}}</svg>`;
}}
function renderChartTabs(chartList) {{
  const host = document.getElementById('analyticsChartTabs');
  if (!chartList.length) {{
    host.innerHTML = '<span class="mini-note">No chartable numeric tables are available yet.</span>';
    document.getElementById('analyticsChartHost').innerHTML = '<div class="chart-empty">Waiting for the first chartable table.</div>';
    return;
  }}
  if (!CURRENT_CHART_ID || !chartList.some((item) => item.chart_id === CURRENT_CHART_ID)) {{
    CURRENT_CHART_ID = chartList[0].chart_id;
  }}
  host.innerHTML = chartList.map((item) => `<button type="button" class="subtab-button ${{item.chart_id === CURRENT_CHART_ID ? 'active' : ''}}" data-chart-id="${{item.chart_id}}">${{esc(item.title)}}</button>`).join('');
  host.querySelectorAll('[data-chart-id]').forEach((button) => {{
    button.addEventListener('click', () => {{
      CURRENT_CHART_ID = button.dataset.chartId;
      renderChartTabs(chartList);
      const selected = chartList.find((item) => item.chart_id === CURRENT_CHART_ID);
      if (selected) drawChart('analyticsChartHost', selected);
    }});
  }});
  const selected = chartList.find((item) => item.chart_id === CURRENT_CHART_ID);
  if (selected) drawChart('analyticsChartHost', selected);
}}
function colorFor(type) {{ if (type === 'ue') return '#2563eb'; if (type === 'site') return '#0d5c63'; return '#a63d40'; }}
function clamp01(value) {{ return Math.max(0, Math.min(1, value)); }}
function lerp(a, b, t) {{ return a + (b - a) * t; }}
function blendColor(stops, t) {{
  const scaled = clamp01(t) * (stops.length - 1);
  const idx = Math.floor(scaled);
  const frac = scaled - idx;
  const lo = stops[Math.max(0, Math.min(stops.length - 1, idx))];
  const hi = stops[Math.max(0, Math.min(stops.length - 1, idx + 1))];
  const rgb = lo.map((value, pos) => Math.round(lerp(value, hi[pos], frac)));
  return `rgb(${{rgb[0]}},${{rgb[1]}},${{rgb[2]}})`;
}}
function numericMetricColor(value, stats, metricKey) {{
  if (value === null || value === undefined || Number.isNaN(Number(value))) return '#94a3b8';
  const numericValue = Number(value);
  const stat = stats[metricKey] || {{}};
  let minVal = Number(stat.min);
  let maxVal = Number(stat.max);
  if (!Number.isFinite(minVal) || !Number.isFinite(maxVal) || minVal === maxVal) {{
    minVal = numericValue - 1;
    maxVal = numericValue + 1;
  }}
  const t = clamp01((numericValue - minVal) / Math.max(maxVal - minVal, 1e-9));
  return blendColor([[30,64,175],[59,130,246],[16,185,129],[245,158,11],[220,38,38]], t);
}}
function categoricalMetricColor(value) {{
  const token = String(value || '').trim().toUpperCase();
  const mapping = {{
    'BPSK': '#1d4ed8',
    'QPSK': '#0f766e',
    'PI/2-BPSK': '#1e40af',
    '16QAM': '#ca8a04',
    '64QAM': '#dc2626',
    '256QAM': '#7c3aed',
    '1024QAM': '#be185d',
  }};
  return mapping[token] || '#475569';
}}
function metricDisplayValue(point, key) {{
  const raw = point ? point[key] : null;
  if (raw === null || raw === undefined || raw === '') return 'n/a';
  return String(raw);
}}
function buildLatestMovementPositions(points, slotValue) {{
  const latestByUE = new Map();
  (points || []).forEach((point) => {{
    const slot = Number(point.slot);
    const ueid = Number(point.ueid);
    if (Number.isNaN(slot) || Number.isNaN(ueid) || slot > Number(slotValue)) return;
    const prev = latestByUE.get(ueid);
    if (!prev || Number(prev.slot) <= slot) latestByUE.set(ueid, point);
  }});
  return Array.from(latestByUE.values());
}}
function renderTimingPanel(timingPayload) {{
  const rows = (timingPayload && timingPayload.rows) || [];
  const profilerSummary = (timingPayload && timingPayload.profiler_summary) || {{}};
  const functionRows = (timingPayload && timingPayload.function_rows) || [];
  const edgeRows = (timingPayload && timingPayload.edge_rows) || [];
  const downloads = (timingPayload && timingPayload.downloads) || {{}};
  const summaryHost = document.getElementById('timingSummary');
  const tableHost = document.getElementById('timingTable');
  const functionTableHost = document.getElementById('timingFunctionTable');
  const edgeTableHost = document.getElementById('timingEdgeTable');
  const stageChartHost = document.getElementById('timingStageChart');
  const functionChartHost = document.getElementById('timingFunctionChart');
  if (!rows.length && !functionRows.length) {{
    summaryHost.innerHTML = '<span class="mini-note">Runtime profiling has not been published yet.</span>';
    tableHost.innerHTML = '<tr><td colspan="5">Waiting for runtime stage profile rows.</td></tr>';
    functionTableHost.innerHTML = '<tr><td colspan="6">Waiting for function hotspot rows.</td></tr>';
    edgeTableHost.innerHTML = '<tr><td colspan="5">Waiting for caller to callee edge rows.</td></tr>';
    stageChartHost.innerHTML = '<div class="chart-empty">No stage timing data is available yet.</div>';
    functionChartHost.innerHTML = '<div class="chart-empty">No profiler function timing data is available yet.</div>';
    return;
  }}
  const pills = [
    `<span class="pill">Stages: ${{esc(timingPayload.stage_count || 0)}}</span>`,
    `<span class="pill">Total Elapsed: ${{esc(fmt(timingPayload.total_elapsed_s))}} s</span>`,
  ];
  if (profilerSummary.FunctionCount !== undefined) pills.push(`<span class="pill">Profiled Functions: ${{esc(fmt(profilerSummary.FunctionCount))}}</span>`);
  if (profilerSummary.ExportedFunctionCount !== undefined) pills.push(`<span class="pill">Visible Hotspots: ${{esc(fmt(profilerSummary.ExportedFunctionCount))}}</span>`);
  if (profilerSummary.EdgeCount !== undefined) pills.push(`<span class="pill">Call Edges: ${{esc(fmt(profilerSummary.EdgeCount))}}</span>`);
  if (profilerSummary.ClockPrecision_s !== undefined) pills.push(`<span class="pill">Clock Precision: ${{esc(fmt(profilerSummary.ClockPrecision_s))}} s</span>`);
  const downloadLinks = [];
  if (downloads.stage && downloads.stage.download_url) downloadLinks.push(`<a class="button-link secondary" href="${{esc(downloads.stage.download_url)}}">Stage CSV</a>`);
  if (downloads.summary && downloads.summary.download_url) downloadLinks.push(`<a class="button-link secondary" href="${{esc(downloads.summary.download_url)}}">Profiler Summary</a>`);
  if (downloads.functions && downloads.functions.download_url) downloadLinks.push(`<a class="button-link secondary" href="${{esc(downloads.functions.download_url)}}">Function CSV</a>`);
  if (downloads.edges && downloads.edges.download_url) downloadLinks.push(`<a class="button-link secondary" href="${{esc(downloads.edges.download_url)}}">Edge CSV</a>`);
  const note = profilerSummary.Notes ? `<span class="mini-note">${{esc(profilerSummary.Notes)}}</span>` : '';
  summaryHost.innerHTML = `${{pills.join('')}}${{downloadLinks.join('')}}${{note}}`;

  tableHost.innerHTML = rows.length
    ? rows.map((row) => `<tr><td>${{esc(row.StageOrder)}}</td><td>${{esc(row.StageName)}}</td><td>${{esc(fmt(row.StageElapsed_s))}}</td><td>${{esc(fmt(row.BundleElapsed_s))}}</td><td>${{esc(row.Notes || '')}}</td></tr>`).join('')
    : '<tr><td colspan="5">No runtime stage rows were exported for this run.</td></tr>';
  functionTableHost.innerHTML = functionRows.length
    ? functionRows.slice(0, 20).map((row) => `<tr><td>${{esc(row.ProfileRank)}}</td><td title="${{esc(row.CompleteName || row.FileName || '')}}"><strong>${{esc(row.FunctionName || 'function')}}</strong><div class="mini-note">${{esc(row.FileName || '')}}</div></td><td>${{esc(fmt(row.TotalTime_s))}}</td><td>${{esc(fmt(row.SelfTimeApprox_s))}}</td><td>${{esc(fmt(row.NumCalls))}}</td><td>${{esc(row.FunctionType || '')}}</td></tr>`).join('')
    : '<tr><td colspan="6">No function hotspot rows have been published yet.</td></tr>';
  edgeTableHost.innerHTML = edgeRows.length
    ? edgeRows.slice(0, 24).map((row) => `<tr><td>${{esc(row.EdgeRank)}}</td><td title="${{esc(row.CallerCompleteName || '')}}">${{esc(row.CallerFunctionName || 'caller')}}</td><td title="${{esc(row.CalleeCompleteName || '')}}">${{esc(row.CalleeFunctionName || 'callee')}}</td><td>${{esc(fmt(row.NumCalls))}}</td><td>${{esc(fmt(row.TotalTime_s))}}</td></tr>`).join('')
    : '<tr><td colspan="5">No profiler edge rows have been published yet.</td></tr>';
  if (window.Plotly) {{
    if (rows.length) {{
      const trace = {{
        x: rows.map((row) => String(row.StageName || 'stage')),
        y: rows.map((row) => Number(row.StageElapsed_s || 0)),
        type: 'bar',
        marker: {{
          color: rows.map((row) => numericMetricColor(Number(row.StageElapsed_s || 0), {{StageElapsed_s: {{min: 0, max: Math.max(...rows.map((item) => Number(item.StageElapsed_s || 0)), 1)}}}}, 'StageElapsed_s'))
        }},
      }};
      stageChartHost.innerHTML = '<div id="timingStageChartPlot" style="width:100%;height:360px;"></div>';
      Plotly.react(document.getElementById('timingStageChartPlot'), [trace], {{
        paper_bgcolor: 'rgba(0,0,0,0)',
        plot_bgcolor: 'rgba(255,255,255,0.95)',
        margin: {{ l: 48, r: 18, t: 18, b: 110 }},
        xaxis: {{ title: 'Stage', tickangle: -32 }},
        yaxis: {{ title: 'Stage Elapsed (s)', gridcolor: 'rgba(133,150,178,0.18)' }},
      }}, {{ responsive: true, displaylogo: false, scrollZoom: true }});
    }} else {{
      stageChartHost.innerHTML = '<div class="chart-empty">No stage timing data is available yet.</div>';
    }}
    if (functionRows.length) {{
      const hotFns = functionRows.slice(0, 15).slice().reverse();
      functionChartHost.innerHTML = '<div id="timingFunctionChartPlot" style="width:100%;height:360px;"></div>';
      Plotly.react(document.getElementById('timingFunctionChartPlot'), [
        {{
          x: hotFns.map((row) => Number(row.TotalTime_s || 0)),
          y: hotFns.map((row) => String(row.FunctionName || 'function')),
          name: 'Total Time',
          type: 'bar',
          orientation: 'h',
          marker: {{ color: '#0f8b8d' }},
        }},
        {{
          x: hotFns.map((row) => Number(row.SelfTimeApprox_s || 0)),
          y: hotFns.map((row) => String(row.FunctionName || 'function')),
          name: 'Self Approx',
          type: 'bar',
          orientation: 'h',
          marker: {{ color: '#ff7a59' }},
        }},
      ], {{
        barmode: 'group',
        paper_bgcolor: 'rgba(0,0,0,0)',
        plot_bgcolor: 'rgba(255,255,255,0.95)',
        margin: {{ l: 170, r: 18, t: 18, b: 42 }},
        xaxis: {{ title: 'Elapsed (s)', gridcolor: 'rgba(133,150,178,0.18)' }},
        yaxis: {{ title: 'Function' }},
      }}, {{ responsive: true, displaylogo: false, scrollZoom: true }});
    }} else {{
      functionChartHost.innerHTML = '<div class="chart-empty">No profiler function timing data is available yet.</div>';
    }}
  }} else {{
    stageChartHost.innerHTML = '<div class="chart-empty">Interactive chart library is unavailable, but the timing tables are still live.</div>';
    functionChartHost.innerHTML = '<div class="chart-empty">Interactive chart library is unavailable, but the timing tables are still live.</div>';
  }}
}}
function renderGenericRows(hostId, rows, columns, emptyText) {{
  const host = document.getElementById(hostId);
  if (!host) return;
  if (!rows || !rows.length) {{
    host.innerHTML = `<tr><td colspan="${columns.length}">${esc(emptyText)}</td></tr>`;
    return;
  }}
  host.innerHTML = rows.map((row) => `<tr>${columns.map((col) => `<td>${esc(fmt(row[col]))}</td>`).join('')}</tr>`).join('');
}}
function outputFamilyHref(outputName) {{
  const base = `/outputs/${{encodeURIComponent(String(outputName || ''))}}`;
  return RUN_ID === null || RUN_ID === undefined ? base : `${{base}}?run_id=${{encodeURIComponent(String(RUN_ID))}}`;
}}
function renderOutputFamilyCards(coverage) {{
  const host = document.getElementById('coverageOutputCards');
  if (!host) return;
  const cards = Array.isArray(coverage.output_family_cards) ? coverage.output_family_cards : [];
  if (!cards.length) {{
    host.innerHTML = '<div class="artifact-card"><h3>No Output Families Yet</h3><p class="muted">The coverage registry has not been published yet.</p></div>';
    return;
  }}
  host.innerHTML = cards.map((item) => {{
    const href = item.href || outputFamilyHref(item.output_name);
    const reason = item.reason_code ? `<p class="mini-note">Reason: ${{esc(item.reason_code)}}</p>` : '<p class="mini-note">Reason: none</p>';
    const next = item.next_action ? `<p class="mini-note">Next: ${{esc(item.next_action)}}</p>` : '';
    const flags = [
      `Backend ${{esc(fmt(item.backend_source_exists_flag))}}`,
      `Persisted ${{esc(fmt(item.persisted_flag))}}`,
      `API ${{esc(fmt(item.api_exposed_flag))}}`,
      `Export ${{esc(fmt(item.export_supported_flag))}}`,
      `UI ${{esc(fmt(item.ui_rendered_flag))}}`,
    ].map((label) => `<span class="pill">${{label}}</span>`).join('');
    return `<div class="artifact-card" data-output-family-card="${{esc(item.output_name)}}">`
      + `<h3><a href="${{esc(href)}}">${{esc(item.output_name)}}</a></h3>`
      + `<div class="toolbar"><span class="pill">Status: ${{esc(item.current_status || 'unknown')}}</span><span class="pill">Code: ${{esc(item.classification_code || 'n/a')}}</span><span class="pill">Section: ${{esc(item.ui_section || 'n/a')}}</span></div>`
      + `<p class="muted">Source: ${{esc(item.source_mapping || item.block_module || 'n/a')}}</p>`
      + `<div class="toolbar">${{flags}}</div>${{reason}}${{next}}`
      + `<div class="toolbar"><a class="button-link secondary" href="${{esc(href)}}">Open Output Page</a></div>`
      + `</div>`;
  }}).join('');
}}
function renderCoveragePanel(coverage) {{
  const cards = Array.isArray(coverage.dashboard_cards) ? coverage.dashboard_cards : [];
  document.getElementById('coverageCards').innerHTML = cards.map((item) => `<div class="metric-card"><div class="metric-value">${esc(fmt(item.value))}</div><div class="metric-label">${esc(item.label)}</div></div>`).join('') || '<div class="metric-card"><div class="metric-value">n/a</div><div class="metric-label">Coverage registry missing</div></div>';
  const links = Object.values(coverage.artifact_links || {}).map((item) => `<a class="button-link secondary" href="${esc(item.view_url || item.download_url)}">${esc(item.logical_path)}</a>`);
  document.getElementById('coverageLinks').innerHTML = links.join('') || '<span class="mini-note">Coverage artifacts are not persisted yet.</span>';
  renderOutputFamilyCards(coverage || {{}});
  renderGenericRows('coverageRegistryBody', coverage.registry || [], ['output_name','ui_section','current_status','classification_code','backend_source_exists_flag','persisted_flag','api_exposed_flag','export_supported_flag','ui_rendered_flag','blocker_reason'], 'Coverage registry is not available yet.');
  renderGenericRows('coverageCompletenessBody', coverage.completeness || [], ['output_name','actual_row_count','actual_artifact_count','completeness_percent','missing_columns','warning_flag'], 'Completeness table is not available yet.');
  renderGenericRows('coveragePersistenceBody', coverage.persistence_audit || [], ['output_name','backend_source_exists_flag','writer_enabled','csv_enabled','json_enabled','retention_policy'], 'Persistence audit is not available yet.');
  renderGenericRows('coverageAPIBody', coverage.api_audit || [], ['output_name','backend_source','api_route','payload_schema_version','response_non_empty_flag','ui_bind_state','exporter_state'], 'API exposure audit is not available yet.');
  renderGenericRows('coverageUnavailableBody', coverage.honest_unavailable || [], ['output_name','classification_code','unavailable_reason','required_backend_sources','required_capture_point','next_implementation_step'], 'No honest unavailable rows were exported.');
  renderGenericRows('coverageCompareBody', coverage.compare_prerequisites || [], ['output_name','prerequisite_name','status','required_condition','next_action'], 'Compare-run prerequisite table is not available yet.');
}}
function renderRootCausePanel(coverage) {{
  renderGenericRows('issueRegistryBody', coverage.issue_registry || [], ['severity','issue_status','issue_category','block_name','direction','ue_id','metric_name','observed_value','root_cause_hint','fix_plan'], 'No result issue registry rows are available yet.');
  renderGenericRows('rootCauseBody', coverage.root_cause_candidates || [], ['ue_id','cell_id','direction','symptom','severity_score','candidate_reason','evidence_metric','evidence_value'], 'Root-cause candidates are not available yet.');
  renderGenericRows('cellEdgeBody', coverage.cell_edge_analytics || [], ['ue_id','Zone','throughput_mbps','mean_sinr_db','mean_bler','mean_queue_bits'], 'Cell-edge analytics are not available yet.');
  renderGenericRows('beamStabilityBody', coverage.beam_stability_analytics || [], ['ue_id','cell_id','beam_event_count','beam_change_count','max_beam_gain_db','stability_class'], 'Beam-stability analytics are not available yet.');
  renderGenericRows('energyRootCauseBody', coverage.energy_root_cause || [], ['entity_type','entity_id','total_energy_j','useful_bits','energy_per_bit_nj','root_cause_reason'], 'Energy root-cause analytics are not available yet.');
  renderGenericRows('powerEnergyPreviewBody', coverage.power_energy_preview || [], ['entity_type','entity_id','state','power_estimate_value','power_estimate_unit','power_value_role','power_value_status','energy_increment_mJ','useful_bits'], 'Power/energy table preview is not available yet.');
  renderGenericRows('prbPreviewBody', coverage.prb_allocation_preview || [], ['frame','slot','cell_id','ue_id','direction','rb_start','rb_len'], 'PRB allocation preview is not available yet.');
}}
function applyLiveMapView(mapRef, mapPayload) {{
  const bounds = mapPayload.bounds || null;
  const preferredZoom = Number(mapPayload.preferred_zoom || 16);
  if (bounds && typeof bounds.min_lat === 'number' && typeof bounds.max_lat === 'number' && typeof bounds.min_lon === 'number' && typeof bounds.max_lon === 'number') {{
    const samePoint = Math.abs(bounds.max_lat - bounds.min_lat) < 1e-8 && Math.abs(bounds.max_lon - bounds.min_lon) < 1e-8;
    if (samePoint) {{
      mapRef.setView([mapPayload.center.lat, mapPayload.center.lon], preferredZoom);
      return;
    }}
    const latLngBounds = L.latLngBounds([[bounds.min_lat, bounds.min_lon], [bounds.max_lat, bounds.max_lon]]);
    mapRef.fitBounds(latLngBounds, {{ padding: [32, 32], maxZoom: preferredZoom }});
    return;
  }}
  mapRef.setView([mapPayload.center.lat, mapPayload.center.lon], preferredZoom || 15);
}
function refreshMapPanel(mapPayload) {{
  CURRENT_MAP_PAYLOAD = mapPayload || {{}};
  const mapHost = document.getElementById('analyticsMap');
  if (!mapHost) return;
  if (!window.L) {{
    const coveragePoints = Array.isArray(mapPayload?.coverage_points) ? mapPayload.coverage_points : [];
    const movement = mapPayload?.movement || {{}};
    const latestPositions = buildLatestMovementPositions(movement.points || [], movement.latest_slot ?? CURRENT_MAP_SLOT ?? 0);
    mapHost.innerHTML = `<div class="artifact-card"><h3>Interactive Map Unavailable</h3><p class="muted">Leaflet could not be loaded in this browser session, so the dashboard is showing the live map data as a fallback summary instead.</p><div class="toolbar"><span class="pill">Coverage Points: ${{esc(coveragePoints.length)}}</span><span class="pill">Tracked UEs: ${{esc(latestPositions.length)}}</span><span class="pill">Center: ${{esc(mapPayload?.center?.label || 'n/a')}}</span></div></div>`;
    document.getElementById('analyticsMapMeta').innerHTML = `<span class="pill">Fallback Mode</span><span class="pill">Coverage Points: ${{esc(coveragePoints.length)}}</span><span class="pill">Tracked UEs: ${{esc(latestPositions.length)}}</span>`;
    document.getElementById('analyticsMapNote').textContent = mapPayload?.note || 'Interactive map library is unavailable.';
    return;
  }}
  if (!ANALYTICS_MAP) {{
    ANALYTICS_MAP = L.map('analyticsMap');
    L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png', {{ attribution: '&copy; OpenStreetMap contributors' }}).addTo(ANALYTICS_MAP);
    ANALYTICS_LAYER = L.layerGroup().addTo(ANALYTICS_MAP);
  }}
  ANALYTICS_LAYER.clearLayers();
  const metrics = Array.isArray(mapPayload.available_metrics) ? mapPayload.available_metrics : [];
  const metricSelect = document.getElementById('analyticsMapMetric');
  if (metricSelect && !metricSelect.dataset.initialized) {{
    metricSelect.innerHTML = metrics.map((item) => `<option value="${{esc(item.key)}}">${{esc(item.label)}}</option>`).join('');
    if (metrics.some((item) => item.key === CURRENT_MAP_METRIC)) {{
      metricSelect.value = CURRENT_MAP_METRIC;
    }} else if (metrics.length) {{
      CURRENT_MAP_METRIC = String(metrics[0].key);
      metricSelect.value = CURRENT_MAP_METRIC;
    }}
    metricSelect.addEventListener('change', () => {{
      CURRENT_MAP_METRIC = metricSelect.value;
      refreshMapPanel(CURRENT_MAP_PAYLOAD || mapPayload);
    }});
    metricSelect.dataset.initialized = '1';
  }} else if (metricSelect && metrics.length) {{
    metricSelect.innerHTML = metrics.map((item) => `<option value="${{esc(item.key)}}">${{esc(item.label)}}</option>`).join('');
    metricSelect.value = metrics.some((item) => item.key === CURRENT_MAP_METRIC) ? CURRENT_MAP_METRIC : metrics[0].key;
    CURRENT_MAP_METRIC = metricSelect.value;
  }}
  const movement = mapPayload.movement || {{}};
  const slotSlider = document.getElementById('analyticsMapSlot');
  const slotLabel = document.getElementById('analyticsMapSlotLabel');
  if (slotSlider) {{
    if (movement.latest_slot !== null && movement.latest_slot !== undefined) {{
      slotSlider.disabled = false;
      slotSlider.min = String(movement.slot_min || movement.latest_slot);
      slotSlider.max = String(movement.slot_max || movement.latest_slot);
      if (CURRENT_MAP_SLOT === null || CURRENT_MAP_SLOT === undefined) CURRENT_MAP_SLOT = Number(movement.latest_slot);
      CURRENT_MAP_SLOT = Math.max(Number(slotSlider.min), Math.min(Number(slotSlider.max), Number(CURRENT_MAP_SLOT)));
      slotSlider.value = String(CURRENT_MAP_SLOT);
      slotLabel.textContent = `Slot ${{CURRENT_MAP_SLOT}}`;
      if (!slotSlider.dataset.initialized) {{
        slotSlider.addEventListener('input', () => {{
          CURRENT_MAP_SLOT = Number(slotSlider.value);
          slotLabel.textContent = `Slot ${{CURRENT_MAP_SLOT}}`;
          refreshMapPanel(CURRENT_MAP_PAYLOAD || mapPayload);
        }});
        slotSlider.dataset.initialized = '1';
      }}
    }} else {{
      slotSlider.disabled = true;
      slotSlider.value = '0';
      slotLabel.textContent = 'No slot trace';
    }}
  }}
  for (const shape of (mapPayload.site_polygons || [])) {{
    const pts = (shape.points || []).map((point) => [point[0], point[1]]);
    if (pts.length >= 3) {{
      const poly = L.polygon(pts, {{
        color: '#155e75',
        weight: 1.5,
        opacity: 0.85,
        fillColor: '#67e8f9',
        fillOpacity: 0.06,
      }});
      poly.bindPopup(`<strong>${{esc(shape.label || 'Site')}}</strong><br>Hexagonal site footprint`);
      poly.addTo(ANALYTICS_LAYER);
    }}
  }}
  for (const sector of (mapPayload.sector_polygons || [])) {{
    const pts = (sector.points || []).map((point) => [point[0], point[1]]);
    if (pts.length >= 3) {{
      const poly = L.polygon(pts, {{
        color: '#dc2626',
        weight: 1.2,
        opacity: 0.75,
        fillColor: '#fca5a5',
        fillOpacity: 0.08,
      }});
      poly.bindPopup(`<strong>${{esc(sector.label || 'Sector')}}</strong><br>Azimuth: ${{esc(sector.azimuth_deg)}} deg`);
      poly.addTo(ANALYTICS_LAYER);
    }}
  }}
  for (const item of (mapPayload.sites || [])) {{
    const marker = L.circleMarker([item.lat, item.lon], {{ radius: item.type === 'ue' ? 5 : 8, color: colorFor(item.type), weight: 2, fillOpacity: 0.25 }});
    marker.bindPopup(`<strong>${{esc(item.label)}}</strong><br>${{esc(item.type)}}<br>${{esc(item.source || '')}}`);
    marker.addTo(ANALYTICS_LAYER);
  }}
  const metricStats = mapPayload.metric_stats || {{}};
  const coveragePoints = Array.isArray(mapPayload.coverage_points) ? mapPayload.coverage_points : [];
  const activeMetricSpec = metrics.find((item) => item.key === CURRENT_MAP_METRIC) || metrics[0] || {{ key: 'RSRP_dBm', label: 'RSRP', kind: 'numeric' }};
  for (const point of coveragePoints) {{
    const value = point[CURRENT_MAP_METRIC];
    const markerColor = activeMetricSpec.kind === 'categorical'
      ? categoricalMetricColor(value)
      : numericMetricColor(value, metricStats, CURRENT_MAP_METRIC);
    const marker = L.circleMarker([point.lat, point.lon], {{
      radius: 8,
      color: markerColor,
      weight: 2,
      fillColor: markerColor,
      fillOpacity: 0.72,
    }});
    marker.bindPopup(
      `<strong>UE ${{esc(point.ueid)}}</strong><br>` +
      `Metric: ${{esc(activeMetricSpec.label)}} = ${{esc(metricDisplayValue(point, CURRENT_MAP_METRIC))}}<br>` +
      `RSRP: ${{esc(metricDisplayValue(point, 'RSRP_dBm'))}} dBm<br>` +
      `Receiver Hest SINR: ${{esc(metricDisplayValue(point, 'ReceiverHestWidebandSINR_dB'))}} dB<br>` +
      `${{point.DecoderTruthProxyWidebandSINR_dB !== undefined && point.DecoderTruthProxyWidebandSINR_dB !== null && point.DecoderTruthProxyWidebandSINR_dB !== '' ? `Decoder-truth proxy SINR: ${{esc(metricDisplayValue(point, 'DecoderTruthProxyWidebandSINR_dB'))}} dB<br>` : ''}}` +
      `${{point.SystemLevelWidebandSINR_dB !== undefined && point.SystemLevelWidebandSINR_dB !== null && point.SystemLevelWidebandSINR_dB !== '' ? `System-level SINR estimate: ${{esc(metricDisplayValue(point, 'SystemLevelWidebandSINR_dB'))}} dB<br>` : ''}}` +
      `${{point.LargeScaleWidebandSINR_dB !== undefined && point.LargeScaleWidebandSINR_dB !== null && point.LargeScaleWidebandSINR_dB !== '' ? `Large-scale SINR preview: ${{esc(metricDisplayValue(point, 'LargeScaleWidebandSINR_dB'))}} dB<br>` : ''}}` +
      `${{point.WidebandSINRSource ? `Wideband SINR source: ${{esc(point.WidebandSINRSource)}}<br>` : ''}}` +
      `${{point.WidebandSINRValueStatus ? `Wideband SINR status: ${{esc(point.WidebandSINRValueStatus)}}<br>` : ''}}` +
      `CQI: ${{esc(metricDisplayValue(point, 'WidebandCQI'))}}<br>` +
      `Cell: ${{esc(metricDisplayValue(point, 'serving_cell'))}}`
    );
    marker.addTo(ANALYTICS_LAYER);
  }}
  for (const path of (movement.paths || [])) {{
    const pathPoints = (path.points || []).map((point) => [point.lat, point.lon]);
    if (pathPoints.length >= 2) {{
      L.polyline(pathPoints, {{ color: '#94a3b8', weight: 1.4, opacity: 0.35 }}).addTo(ANALYTICS_LAYER);
    }}
  }}
  const latestPositions = buildLatestMovementPositions(movement.points || [], movement.latest_slot ?? CURRENT_MAP_SLOT);
  const currentPositions = buildLatestMovementPositions(movement.points || [], CURRENT_MAP_SLOT ?? movement.latest_slot ?? 0);
  for (const point of currentPositions) {{
    const marker = L.circleMarker([point.lat, point.lon], {{
      radius: 5,
      color: '#1d4ed8',
      weight: 1.5,
      fillColor: '#60a5fa',
      fillOpacity: 0.9,
    }});
    marker.bindPopup(
      `<strong>UE ${{esc(point.ueid)}}</strong><br>` +
      `Slot: ${{esc(point.slot)}}<br>` +
      `Serving Cell: ${{esc(point.serving_cell)}}<br>` +
      `RSRP: ${{esc(point.rsrp_dBm)}} dBm<br>` +
      `Receiver Hest SINR: ${{esc(point.sinr_dB)}} dB<br>` +
      `System-level SINR estimate: ${{esc(point.system_level_sinr_dB)}} dB<br>` +
      `CQI: ${{esc(point.cqi)}}`
    );
    marker.addTo(ANALYTICS_LAYER);
  }}
  document.getElementById('analyticsMapMeta').innerHTML = `<span class="pill">Center: ${{esc(mapPayload.center.label)}}</span><span class="pill">Sites: ${{esc(mapPayload.sites.length)}}</span><span class="pill">Sectors: ${{esc((mapPayload.sector_polygons || []).length)}}</span><span class="pill">Coverage Points: ${{esc(coveragePoints.length)}}</span><span class="pill">Tracked UEs: ${{esc(latestPositions.length)}}</span><span class="pill">Metric: ${{esc(activeMetricSpec.label)}}</span>`;
  document.getElementById('analyticsMapNote').textContent = mapPayload.note || '';
  applyLiveMapView(ANALYTICS_MAP, mapPayload);
}}
async function applyAnalyticsData(data) {{
  if (!data || !data.run) throw new Error('Analytics payload is empty.');
  document.getElementById('runHeadline').innerHTML = `<span class="live-dot"></span>Run ${{esc(data.run.run_id)}} | ${{esc(data.run.scenario_id)}} | <span class="status-${{esc((data.run.status_text || '').toLowerCase())}}">${{esc(data.run.status_text)}}</span> | Result OK: ${{esc(data.run.result_ok ?? 'n/a')}} | Truth Contract OK: ${{esc(data.run.runtime_truth_contract_ok ?? 'n/a')}} | Run Completion: ${{esc(data.run.run_completion || 'n/a')}}`;
  document.getElementById('runMeta').innerHTML = `<span class="pill">Tag: ${{esc(data.run.run_tag)}}</span><span class="pill">Backend: ${{esc(data.run.backend)}}</span><span class="pill">Roundtrip Mismatches: ${{esc(data.run.roundtrip_mismatch_count ?? 'n/a')}}</span><span class="pill">Runtime Evidence Missing: ${{esc(data.run.required_runtime_evidence_missing_count ?? 'n/a')}}</span><span class="pill">Strict Truth Failures: ${{esc(data.run.strict_truth_failure_count ?? 'n/a')}}</span><span class="pill">Updated: ${{esc(data.run.updated_utc)}}</span>`;
  document.getElementById('analyticsLinks').innerHTML = `<a class="button-link secondary" href="/result?run_id=${{esc(data.run.run_id)}}">Result</a><a class="button-link secondary" href="/outputs?run_id=${{esc(data.run.run_id)}}">Output Families</a><a class="button-link secondary" href="/map?run_id=${{esc(data.run.run_id)}}">Dedicated Map</a><a class="button-link secondary" href="/images?run_id=${{esc(data.run.run_id)}}">Legacy Images</a>`;
  const modeText = data.analysis_mode === 'post_run'
    ? 'This run is no longer active, so analytics is prioritizing summary tables and conclusion-oriented charts from the final MySQL-backed artifacts.'
    : 'This run is still active, so analytics is prioritizing live evidence, logs, and chartable runtime tables as they arrive from MySQL.';
  document.getElementById('overviewMode').textContent = modeText;
  const runtimeContext = data.runtime_context || {};
  const deployment = runtimeContext.deployment || {};
  const operating = Array.isArray(runtimeContext.operating_mode) ? runtimeContext.operating_mode : [];
  const roundtrip = runtimeContext.roundtrip_artifacts || {};
  const roundtripSummary = roundtrip.summary || {};
  const truthModes = runtimeContext.truth_modes || {};
  const rawLifecycle = runtimeContext.raw_trial_lifecycle || {};
  const controlSummary = runtimeContext.control_summary || {};
  const configSnapshot = runtimeContext.config_snapshot || {};
  const truthContract = runtimeContext.truth_contract || {};
  const truthSummary = truthContract.summary || {};
  const truthFailures = Array.isArray(truthContract.failure_rows) ? truthContract.failure_rows : [];
  const contextPills = [];
  if (deployment.NumSites !== undefined) contextPills.push(`<span class="pill">Sites: ${{esc(deployment.NumSites)}}</span>`);
  if (deployment.NumCells !== undefined) contextPills.push(`<span class="pill">Cells: ${{esc(deployment.NumCells)}}</span>`);
  if (deployment.NumUEs !== undefined) contextPills.push(`<span class="pill">UEs: ${{esc(deployment.NumUEs)}}</span>`);
  if (deployment.InterSiteDistance_m !== undefined) contextPills.push(`<span class="pill">ISD: ${{esc(deployment.InterSiteDistance_m)}} m</span>`);
  if (truthModes.noise_operating_mode) contextPills.push(`<span class="pill">Noise Mode: ${{esc(truthModes.noise_operating_mode)}}</span>`);
  if (truthModes.doppler_source_mode) contextPills.push(`<span class="pill">Doppler Source: ${{esc(truthModes.doppler_source_mode)}}</span>`);
  if (truthModes.interference_mode) contextPills.push(`<span class="pill">Interference: ${{esc(truthModes.interference_mode)}}</span>`);
  if (truthModes.control_integration_mode) contextPills.push(`<span class="pill">Control: ${{esc(truthModes.control_integration_mode)}}</span>`);
  if (truthModes.pbch_mode) contextPills.push(`<span class="pill">PBCH: ${{esc(truthModes.pbch_mode)}}</span>`);
  if (truthModes.prach_mode) contextPills.push(`<span class="pill">PRACH: ${{esc(truthModes.prach_mode)}}</span>`);
  if (truthModes.pdcch_mode) contextPills.push(`<span class="pill">PDCCH: ${{esc(truthModes.pdcch_mode)}}</span>`);
  if (truthModes.srs_mode) contextPills.push(`<span class="pill">SRS: ${{esc(truthModes.srs_mode)}}</span>`);
  if (truthModes.pbch_gating_active !== undefined) contextPills.push(`<span class="pill">PBCH Gate: ${{truthModes.pbch_gating_active ? 'on' : 'off'}}</span>`);
  if (truthModes.prach_gating_active !== undefined) contextPills.push(`<span class="pill">PRACH Gate: ${{truthModes.prach_gating_active ? 'on' : 'off'}}</span>`);
  if (truthModes.pdcch_gating_active !== undefined) contextPills.push(`<span class="pill">PDCCH Gate: ${{truthModes.pdcch_gating_active ? 'on' : 'off'}}</span>`);
  if (truthModes.srs_gating_active !== undefined) contextPills.push(`<span class="pill">SRS Gate: ${{truthModes.srs_gating_active ? 'on' : 'off'}}</span>`);
  if (roundtripSummary.config_roundtrip_rows) contextPills.push(`<span class="pill">Roundtrip Rows: ${{esc(roundtripSummary.config_roundtrip_rows)}}</span>`);
  if (roundtripSummary.config_roundtrip_mismatches !== undefined) contextPills.push(`<span class="pill">Roundtrip Mismatches: ${{esc(roundtripSummary.config_roundtrip_mismatches)}}</span>`);
  if (roundtripSummary.summary_vs_raw_rows) contextPills.push(`<span class="pill">Summary vs Raw Rows: ${{esc(roundtripSummary.summary_vs_raw_rows)}}</span>`);
  if (truthSummary.RuntimeTruthContractOk !== undefined) contextPills.push(`<span class="pill">Truth Contract Artifact OK: ${{esc(fmt(truthSummary.RuntimeTruthContractOk))}}</span>`);
  if (truthSummary.StrictTruthFailureCount !== undefined) contextPills.push(`<span class="pill">Truth Contract Failures: ${{esc(fmt(truthSummary.StrictTruthFailureCount))}}</span>`);
  if (truthSummary.NoProxyPHYOk !== undefined) contextPills.push(`<span class="pill">No Proxy PHY: ${{esc(fmt(truthSummary.NoProxyPHYOk))}}</span>`);
  if (truthSummary.SyntheticBLERFallbackOk !== undefined) contextPills.push(`<span class="pill">No Synthetic BLER: ${{esc(fmt(truthSummary.SyntheticBLERFallbackOk))}}</span>`);
  if (truthSummary.RawLifecycleOk !== undefined) contextPills.push(`<span class="pill">Raw Lifecycle OK: ${{esc(fmt(truthSummary.RawLifecycleOk))}}</span>`);
  if (truthSummary.FERRunScopeIdentityOk !== undefined) contextPills.push(`<span class="pill">FER Scope Identity OK: ${{esc(fmt(truthSummary.FERRunScopeIdentityOk))}}</span>`);
  if (truthSummary.AMCNamingOk !== undefined) contextPills.push(`<span class="pill">AMC Naming OK: ${{esc(fmt(truthSummary.AMCNamingOk))}}</span>`);
  if (controlSummary.PBCHFailureCount !== undefined) contextPills.push(`<span class="pill">PBCH Failures: ${{esc(controlSummary.PBCHFailureCount)}}</span>`);
  if (controlSummary.PRACHFailureCount !== undefined) contextPills.push(`<span class="pill">PRACH Failures: ${{esc(controlSummary.PRACHFailureCount)}}</span>`);
  if (controlSummary.ControlDecodeFailureCount !== undefined) contextPills.push(`<span class="pill">PDCCH Failures: ${{esc(controlSummary.ControlDecodeFailureCount)}}</span>`);
  if (controlSummary.SRSInvalidEventCount !== undefined) contextPills.push(`<span class="pill">SRS Invalid Events: ${{esc(controlSummary.SRSInvalidEventCount)}}</span>`);
  if (controlSummary.GrantsBlockedByGating !== undefined) contextPills.push(`<span class="pill">Blocked Grants: ${{esc(controlSummary.GrantsBlockedByGating)}}</span>`);
  if (controlSummary.UsersAcquired !== undefined) contextPills.push(`<span class="pill">Users Acquired: ${{esc(controlSummary.UsersAcquired)}}</span>`);
  if (controlSummary.UsersAccessReady !== undefined) contextPills.push(`<span class="pill">Access Ready: ${{esc(controlSummary.UsersAccessReady)}}</span>`);
  if (controlSummary.UsersWithValidSRS !== undefined) contextPills.push(`<span class="pill">Users With Valid SRS: ${{esc(controlSummary.UsersWithValidSRS)}}</span>`);
  if (configSnapshot.submitted_present) contextPills.push(`<span class="pill">Submitted Config: sim_runs.config_json</span>`);
  [['dl','DL'], ['ul','UL']].forEach(([key, label]) => {{
    const info = rawLifecycle[key] || {{}};
    if (String(info.status || '') === 'exact') {{
      contextPills.push(`<span class="pill">${{esc(label)}} Finalized Rows: ${{esc(info.finalized_rows ?? 0)}}</span>`);
      if ((info.partial_rows ?? 0) > 0) contextPills.push(`<span class="pill">${{esc(label)}} Partial Rows: ${{esc(info.partial_rows)}}</span>`);
      if ((info.finalized_secondary_gap_rows ?? 0) > 0) contextPills.push(`<span class="pill">${{esc(label)}} Finalized With Secondary Gaps: ${{esc(info.finalized_secondary_gap_rows)}}</span>`);
    }}
  }});
  operating.forEach((row) => {{
    const direction = String(row.Direction || 'LLS');
    const amcPolicy = row.ConfiguredMCSSelectionPolicy || row.ConfiguredMCSSelectionMode || row.ConfiguredLinkAdaptationMode || row.LinkAdaptationMode;
    if (amcPolicy) contextPills.push(`<span class="pill">${{esc(direction)}} AMC Policy: ${{esc(amcPolicy)}}</span>`);
    if (row.RequestedOperatingPointSource) contextPills.push(`<span class="pill">${{esc(direction)}} Requested Operating Point: ${{esc(row.RequestedOperatingPointSource)}}</span>`);
    if (row.ActualMCSSelectionMode) contextPills.push(`<span class="pill">${{esc(direction)}} Applied AMC Mode: ${{esc(row.ActualMCSSelectionMode)}}</span>`);
    if (row.AppliedOperatingPointSource) contextPills.push(`<span class="pill">${{esc(direction)}} Applied Operating Point: ${{esc(row.AppliedOperatingPointSource)}}</span>`);
    if (row.SchedulerGrantMCSSelectionMode) contextPills.push(`<span class="pill">${{esc(direction)}} Scheduler AMC Mode: ${{esc(row.SchedulerGrantMCSSelectionMode)}}</span>`);
    if (row.CQITable) contextPills.push(`<span class="pill">${{esc(direction)}} CQI: ${{esc(row.CQITable)}}</span>`);
    if (row.MCSTable) contextPills.push(`<span class="pill">${{esc(direction)}} MCS: ${{esc(row.MCSTable)}}</span>`);
  }});
  const snapshotLinks = [];
  const downloads = configSnapshot.downloads || {{}};
  [['resolved_json','Resolved JSON'], ['resolved_yaml','Resolved YAML'], ['source_chain','Source Chain'], ['config_roundtrip_verification','Roundtrip CSV'], ['browser_runtime_db_consistency','Browser/DB CSV'], ['summary_vs_raw_consistency','Summary/Raw CSV'], ['value_source_audit','Value Source CSV']].forEach(([key, label]) => {{
    const item = downloads[key];
    if (item && (item.view_url || item.download_url)) {{
      snapshotLinks.push(`<a class="button-link secondary" href="${{esc(item.view_url || item.download_url)}}">${{esc(label)}}</a>`);
    }}
  }});
  Object.entries(truthContract.downloads || {{}}).forEach(([key, item]) => {{
    if (item && (item.view_url || item.download_url)) {{
      snapshotLinks.push(`<a class="button-link secondary" href="${{esc(item.view_url || item.download_url)}}">Truth Contract ${{esc(key)}}</a>`);
    }}
  }});
  const runtimeNotes = Array.isArray(runtimeContext.notes) ? runtimeContext.notes : [];
  const roundtripMismatchRows = roundtrip.mismatch_rows || {{}};
  const roundtripMismatchDetails = [];
  Object.entries(roundtripMismatchRows).forEach(([artifactName, rows]) => {{
    if (!Array.isArray(rows)) return;
    rows.slice(0, 8).forEach((row) => {{
      const parameter = row.ParameterName || row.FieldName || row.SummaryField || row.OutputName || 'unknown_field';
      const status = row.ConsistencyStatus || row.Status || row.current_status || 'non_consistent';
      const note = row.ConsistencyNotes || row.Notes || row.unavailable_reason || '';
      roundtripMismatchDetails.push(`${{esc(artifactName)}}: ${{esc(parameter)}} -> ${{esc(status)}}${{note ? ' (' + esc(note) + ')' : ''}}`);
    }});
  }});
  document.getElementById('overviewContext').innerHTML = (contextPills.join('') || '<span class="mini-note">Runtime context not published yet.</span>') +
    (snapshotLinks.length ? `<div class="toolbar" style="margin-top:12px;">${{snapshotLinks.join('')}}</div>` : '') +
    (roundtripMismatchDetails.length ? `<div class="warning" style="margin-top:12px;"><strong>Roundtrip mismatches</strong><br>${{roundtripMismatchDetails.join('<br>')}}</div>` : '') +
    (runtimeNotes.length ? `<div class="warning" style="margin-top:12px;">${{runtimeNotes.map((note) => esc(note)).join('<br>')}}</div>` : '');
  const truthPanel = document.getElementById('truthContractPanel');
  if (truthPanel) {{
    const truthFields = [
      ['RuntimeTruthContractOk', 'Truth Contract OK'],
      ['NoProxyPHYOk', 'No Proxy PHY'],
      ['SyntheticBLERFallbackOk', 'No Synthetic BLER'],
      ['RawLifecycleOk', 'Raw Lifecycle OK'],
      ['FERRunScopeIdentityOk', 'FER Run-Scope Identity OK'],
      ['AMCNamingOk', 'AMC Naming OK'],
      ['HiddenDefaultAuditStatus', 'Hidden Default Audit'],
      ['StrictTruthFailureCount', 'Strict Failures'],
      ['RoundtripMismatchCount', 'Roundtrip Mismatches'],
      ['RequiredRuntimeEvidenceMissingCount', 'Runtime Evidence Missing']
    ];
    const rows = truthFields.map(([key, label]) => `<tr><td>${{esc(label)}}</td><td>${{esc(fmt(truthSummary[key]))}}</td></tr>`).join('');
    const failureRows = truthFailures.length
      ? truthFailures.slice(0, 12).map((row) => `<tr><td>${{esc(row.FailureIndex)}}</td><td>${{esc(row.FailureCategory)}}</td><td>${{esc(row.FailureCode)}}</td></tr>`).join('')
      : '<tr><td colspan="3">No truth-contract failure rows are present.</td></tr>';
    truthPanel.innerHTML = truthSummary.RuntimeTruthContractOk === undefined
      ? '<p class="muted">Truth-contract artifacts are not available yet.</p>'
      : `<div class="two-col"><div class="table-scroll"><table><thead><tr><th>Gate</th><th>Value</th></tr></thead><tbody>${{rows}}</tbody></table></div><div class="table-scroll"><table><thead><tr><th>#</th><th>Category</th><th>Failure</th></tr></thead><tbody>${{failureRows}}</tbody></table></div></div>`;
  }}
  const metrics = [{{label:'Artifacts',value:data.counts.artifacts_total}},{{label:'Tables',value:data.counts.tables_total}},{{label:'Images',value:data.counts.images_total}},{{label:'Logs',value:data.counts.logs_total}},...(data.metrics||[])];
  document.getElementById('metricGrid').innerHTML = metrics.map((item) => {{
    const sourceText = item.source ? (' | ' + esc(item.source)) : '';
    return `<div class="metric-card"><div class="metric-value">${{esc(fmt(item.value))}}</div><div class="metric-label">${{esc(item.label)}}${{sourceText}}</div></div>`;
  }}).join('');
  const charts = data.charts || {{}};
  const preferredNumericCharts = data.analysis_mode === 'post_run'
    ? (((charts.summary_tabs || []).length) ? (charts.summary_tabs || []) : (charts.numeric_tabs || []))
    : (charts.numeric_tabs || []);
  const chartList = [
    {{ chart_id: 'artifact_activity', title: 'Artifact Activity', series: (charts.artifact_activity || {{}}).series || [] }},
    {{ chart_id: 'log_activity', title: 'Log Activity', series: (charts.log_activity || {{}}).series || [] }},
    ...(preferredNumericCharts.map((chart) => ({{ ...chart, chart_id: `artifact_${{chart.artifact_id}}` }})))
  ];
  renderChartTabs(chartList);
  const preferredTables = data.analysis_mode === 'post_run'
    ? ((data.tables_summary || []).length ? (data.tables_summary || []) : (data.tables_all || []))
    : (data.tables_recent || []);
  const preferredImages = data.analysis_mode === 'post_run'
    ? ((data.images_all || []).length ? (data.images_all || []) : (data.images_recent || []))
    : (data.images_recent || []);
  renderAnalyticsOverviewImages(preferredImages);
  document.getElementById('tableList').innerHTML = preferredTables.map((item) => `<tr><td><a href="${{esc(item.view_url)}}">${{esc(item.logical_path)}}</a></td><td>${{esc(fmt(item.byte_size))}}</td><td><a href="${{esc(item.download_url)}}">Download CSV</a></td></tr>`).join('') || '<tr><td colspan="3">No tables yet.</td></tr>';
  const nextImageSignature = analyticsArtifactSignature(preferredImages);
  if (nextImageSignature !== ANALYTICS_IMAGE_SIGNATURE) {{
    ANALYTICS_IMAGE_SIGNATURE = nextImageSignature;
    ANALYTICS_IMAGE_LIMIT = 18;
  }}
  ANALYTICS_IMAGE_ITEMS = preferredImages;
  if (CURRENT_ANALYTICS_TAB === 'images') {{
    renderAnalyticsImageGrid(true);
  }}
  const logs = (data.logs_recent || []).map((row) => `[${{row.time_str || row.created_utc}}] ${{row.level_str || 'INFO'}} ${{row.message_text || ''}}`);
  document.getElementById('logBox').textContent = logs.join('\\n') || 'No logs yet.';
  const debug = data.debug || {{}};
  document.getElementById('debugSummary').innerHTML = [
    `<span class="pill">Status: ${{esc(debug.status || data.run.status_text || 'n/a')}}</span>`,
    `<span class="pill">Run Completion: ${{esc(debug.run_completion || 'n/a')}}</span>`,
    `<span class="pill">Failure Count: ${{esc(fmt(debug.required_failure_count))}}</span>`,
    `<span class="pill">Truth Contract OK: ${{esc(debug.runtime_truth_contract_ok ?? data.run.runtime_truth_contract_ok ?? 'n/a')}}</span>`,
    `<span class="pill">Roundtrip Mismatches: ${{esc(debug.roundtrip_mismatch_count ?? data.run.roundtrip_mismatch_count ?? 'n/a')}}</span>`,
    `<span class="pill">Runtime Evidence Missing: ${{esc(debug.required_runtime_evidence_missing_count ?? data.run.required_runtime_evidence_missing_count ?? 'n/a')}}</span>`,
    `<span class="pill">Strict Truth Failures: ${{esc(debug.strict_truth_failure_count ?? data.run.strict_truth_failure_count ?? 'n/a')}}</span>`,
    debug.failure_identifier ? `<span class="pill">Identifier: ${{esc(debug.failure_identifier)}}</span>` : ''
  ].join('');
  document.getElementById('debugFailure').textContent = debug.failure_message || 'No explicit failure message is recorded for this run.';
  document.getElementById('debugChainTable').innerHTML = (debug.chain_rows || []).map((row) => `<tr><td>${{esc(row.chain_label)}}</td><td><span class="pill">${{esc(row.evidence_state)}}</span></td><td>${{esc(fmt(row.blocks_total))}}</td><td>${{esc(fmt(row.mandatory_blocks))}}</td><td>${{esc(fmt(row.optional_blocks))}}</td><td>${{esc(row.evidence_note)}}</td></tr>`).join('') || '<tr><td colspan="6">No debug chain metadata is available yet.</td></tr>';
  document.getElementById('debugHighlights').textContent = (debug.log_highlights || []).map((row) => `[${{row.time}}] ${{row.level}} ${{row.message}}`).join('\\n') || 'No warning/error highlights yet.';
  document.getElementById('debugNote').textContent = debug.note || '';
  try {{ renderCoveragePanel(data.output_coverage || {{}}); }} catch (err) {{ console.error('output coverage render failed', err); }}
  try {{ renderRootCausePanel(data.output_coverage || {{}}); }} catch (err) {{ console.error('root cause render failed', err); }}
  try {{ renderTimingPanel(data.timing || {{}}); }} catch (err) {{ console.error('timing render failed', err); }}
  try {{ refreshMapPanel(data.map || {{}}); }} catch (err) {{ console.error('map render failed', err); document.getElementById('analyticsMapNote').textContent = `Map render failed: ${{err}}`; }}
}}
async function refreshAnalytics() {{
  const resolvedRunId = await resolveRunId();
  if (resolvedRunId === null) {{
    document.getElementById('runHeadline').innerHTML = `<span class="live-dot"></span>Waiting for run tag ${{esc(RUN_TAG)}} to appear in MySQL...`;
    document.getElementById('runMeta').innerHTML = '<span class="pill">Launch accepted</span><span class="pill">Waiting for sim_runs row</span>';
    document.getElementById('metricGrid').innerHTML = '<div class="metric-card"><div class="metric-value">pending</div><div class="metric-label">Run registration</div></div>';
    document.getElementById('logBox').textContent = 'MATLAB was launched. This page will bind to the run automatically once the first database row appears.';
    scheduleAnalyticsRefresh(3000);
    return;
  }}
  let data = await analyticsFetchJson(`/api/run/${{resolvedRunId}}/live?lite=1`);
  if (!ANALYTICS_FULL_PAYLOAD || (data.artifact_version && data.artifact_version !== ANALYTICS_ARTIFACT_VERSION)) {{
    data = await analyticsFetchJson(`/api/run/${{resolvedRunId}}/live`);
    ANALYTICS_FULL_PAYLOAD = data;
    ANALYTICS_ARTIFACT_VERSION = data.artifact_version || '';
  }} else {{
    data = mergeAnalyticsPayload(ANALYTICS_FULL_PAYLOAD, data);
    ANALYTICS_FULL_PAYLOAD = data;
  }}
  await applyAnalyticsData(data);
  scheduleAnalyticsRefresh(analyticsNextPollDelay(data));
}}
if (ANALYTICS_INITIAL_PAYLOAD && ANALYTICS_INITIAL_PAYLOAD.run) {{
  applyAnalyticsData(ANALYTICS_INITIAL_PAYLOAD).catch((err) => {{ console.error('initial analytics render failed', err); }});
}}
refreshAnalytics().catch((err) => {{ document.getElementById('logBox').textContent = `Live refresh failed: ${{err}}`; }});
document.addEventListener('visibilitychange', () => scheduleAnalyticsRefresh(500));
document.querySelectorAll('[data-analytics-tab-button]').forEach((button) => {{
  button.addEventListener('click', () => activateAnalyticsTab(button.dataset.analyticsTabButton));
}});
activateAnalyticsTab('overview');
</script>
"""
    return (
        script
        .replace("__RUN_ID__", run_id_literal)
        .replace("__RUN_TAG__", run_tag_literal)
        .replace("__POLL_MS__", str(POLL_INTERVAL_MS))
        .replace("__INITIAL_PAYLOAD__", initial_payload_literal)
        .replace("{{", "{")
        .replace("}}", "}")
    )


def build_analytics_page(run_id: int | None, run_tag: str | None = None, message: str = "", user_profile: dict[str, Any] | None = None) -> bytes:
    if run_id is None and not run_tag:
        run_id = latest_run_id()
    if run_id is None and not run_tag:
        return page_shell("Analytics", '<section class="panel"><h2>Analytics</h2><p>No runs found.</p></section>', active="analytics", user_profile=user_profile)
    initial_payload = build_live_payload(run_id) if run_id is not None else None
    message_html = f'<section class="panel"><strong>{html.escape(message)}</strong></section>' if message else ""
    title_token = str(run_id) if run_id is not None else (run_tag or "pending")
    body = f"""
    {message_html}
    <section class="panel">
      <h2 id="runHeadline">Loading run {html.escape(title_token)}...</h2>
      <div id="runMeta" class="toolbar"></div>
      <div id="analyticsLinks" class="toolbar" style="margin-top:12px;"></div>
      <p class="muted">This page polls MySQL-backed endpoints every {POLL_INTERVAL_MS / 1000:.1f} seconds. As MATLAB writes logs and artifacts, the browser updates without a manual refresh.</p>
    </section>
    <section class="panel">
      <div class="subtab-bar">
        <button type="button" class="subtab-button active" data-analytics-tab-button="overview">Overview</button>
        <button type="button" class="subtab-button" data-analytics-tab-button="charts">Charts</button>
        <button type="button" class="subtab-button" data-analytics-tab-button="timing">Timing</button>
        <button type="button" class="subtab-button" data-analytics-tab-button="debug">Debug</button>
        <button type="button" class="subtab-button" data-analytics-tab-button="coverage">Output Coverage</button>
        <button type="button" class="subtab-button" data-analytics-tab-button="rootcause">Root Cause</button>
        <button type="button" class="subtab-button" data-analytics-tab-button="map">Map</button>
        <button type="button" class="subtab-button" data-analytics-tab-button="images">Images</button>
      </div>
      <div class="subtab-panel active" data-analytics-tab-panel="overview">
        <section class="panel" style="padding:0;border:none;box-shadow:none;background:transparent;">
          <h2>LLS Overview</h2>
          <p id="overviewMode" class="muted"></p>
          <div id="overviewContext" class="toolbar" style="flex-wrap:wrap;margin-bottom:12px;"></div>
          <section class="panel" style="margin:12px 0 16px 0;">
            <h3>Final Truth Contract</h3>
            <p class="muted">Canonical summary and failure rows from <code>reports/csv/truth_contract_summary.csv</code> and <code>reports/csv/truth_contract_failures.csv</code>.</p>
            <div id="truthContractPanel"><p class="muted">Loading truth-contract artifacts...</p></div>
          </section>
          <div id="metricGrid" class="metric-grid"></div>
          <section class="panel" style="margin-top:16px;">
            <h3>Featured PHY Visuals</h3>
            <p class="muted">Key EVM, constellation, waveform, and link-quality visuals are surfaced here automatically from the persisted analytics image artifacts.</p>
            <div id="overviewImageGrid" class="artifact-grid"><p class="muted">Loading featured PHY visuals...</p></div>
          </section>
        </section>
        <div class="two-col" style="margin-top:16px;">
          <section class="panel"><h2>Summary And Analysis Tables</h2><div class="table-scroll"><table><thead><tr><th>Logical Path</th><th>Bytes</th><th>Download</th></tr></thead><tbody id="tableList"><tr><td colspan="3">Loading...</td></tr></tbody></table></div></section>
          <section class="panel"><h2>Live Logs</h2><pre id="logBox">Loading...</pre></section>
        </div>
      </div>
      <div class="subtab-panel" data-analytics-tab-panel="charts">
        <div class="panel-scroll-x"><div id="analyticsChartTabs" class="tabular-tabs"></div></div>
        <div id="analyticsChartHost" class="chart-box" style="margin-top:14px;"></div>
      </div>
      <div class="subtab-panel" data-analytics-tab-panel="timing">
        <section class="panel" style="padding:0;border:none;box-shadow:none;background:transparent;">
          <h2>Runtime Profiling</h2>
          <div id="timingSummary" class="toolbar"></div>
          <p class="muted">Function self time is exported as <code>SelfTimeApprox_s = TotalTime_s - sum(Child.TotalTime_s)</code> because MATLAB R2023b does not expose a native self-time field in <code>profile('info')</code>.</p>
          <div class="two-col" style="margin-top:14px;">
            <section class="panel">
              <h3>Stage Timeline</h3>
              <div id="timingStageChart" class="chart-box"></div>
            </section>
            <section class="panel">
              <h3>Function Hotspots</h3>
              <div id="timingFunctionChart" class="chart-box"></div>
            </section>
          </div>
          <div class="two-col" style="margin-top:14px;">
            <section class="panel">
              <h3>Stage Profile</h3>
              <div class="table-scroll">
                <table>
                  <thead><tr><th>Order</th><th>Stage</th><th>Stage Elapsed s</th><th>Bundle Elapsed s</th><th>Notes</th></tr></thead>
                  <tbody id="timingTable"><tr><td colspan="5">Loading...</td></tr></tbody>
                </table>
              </div>
            </section>
            <section class="panel">
              <h3>Function Profile</h3>
              <div class="table-scroll">
                <table>
                  <thead><tr><th>Rank</th><th>Function</th><th>Total s</th><th>Self Approx s</th><th>Calls</th><th>Type</th></tr></thead>
                  <tbody id="timingFunctionTable"><tr><td colspan="6">Loading...</td></tr></tbody>
                </table>
              </div>
            </section>
          </div>
          <section class="panel" style="margin-top:16px;">
            <h3>Hot Call Edges</h3>
            <div class="table-scroll">
              <table>
                <thead><tr><th>Rank</th><th>Caller</th><th>Callee</th><th>Calls</th><th>Total s</th></tr></thead>
                <tbody id="timingEdgeTable"><tr><td colspan="5">Loading...</td></tr></tbody>
              </table>
            </div>
          </section>
        </section>
      </div>
      <div class="subtab-panel" data-analytics-tab-panel="debug">
        <section class="panel" style="padding:0;border:none;box-shadow:none;background:transparent;">
          <h2>Run Debugger</h2>
          <div id="debugSummary" class="toolbar"></div>
          <p id="debugNote" class="muted"></p>
          <div class="two-col" style="margin-top:16px;">
            <section class="panel"><h3>Failure Summary</h3><pre id="debugFailure">Loading...</pre></section>
            <section class="panel"><h3>Warning/Error Highlights</h3><pre id="debugHighlights">Loading...</pre></section>
          </div>
          <section class="panel" style="margin-top:16px;">
            <h3>Expected Chain Coverage</h3>
            <p class="muted">This table helps spot likely missed TX/RX chain families. It is evidence-driven, so a missing row means the browser has not seen artifacts or live logs for that chain yet.</p>
            <div class="table-scroll">
              <table>
                <thead><tr><th>Chain</th><th>Evidence</th><th>Total Blocks</th><th>Mandatory</th><th>Optional</th><th>Note</th></tr></thead>
                <tbody id="debugChainTable"><tr><td colspan="6">Loading...</td></tr></tbody>
              </table>
            </div>
          </section>
        </section>
      </div>
      <div class="subtab-panel" data-analytics-tab-panel="coverage">
        <section class="panel" style="padding:0;border:none;box-shadow:none;background:transparent;">
          <h2>Output Coverage Dashboard</h2>
          <p class="muted">Status badges and reasons below come from canonical DB-backed output coverage artifacts. Unavailable entries are manifest/audit metadata only; no fake rows or fake plot files are created for them. The cards include an Overstated Implemented count, which must stay zero for strict coverage truth.</p>
          <div id="coverageCards" class="metric-grid"></div>
          <div id="coverageLinks" class="toolbar" style="margin-top:12px;flex-wrap:wrap;"></div>
          <section class="panel" style="margin-top:16px;">
            <h3>Per-Output Browser Cards</h3>
            <p class="muted">Every requested output family gets a card and a detail route. Implemented cards link to real canonical artifacts; unavailable and schema-only cards link to their reason and next-action contract.</p>
            <div id="coverageOutputCards" class="artifact-grid"></div>
          </section>
          <div class="two-col" style="margin-top:16px;">
            <section class="panel">
              <h3>Coverage Registry</h3>
              <div class="table-scroll">
                <table>
                  <thead><tr><th>Output</th><th>UI Section</th><th>Status</th><th>Code</th><th>Backend</th><th>Persisted</th><th>API</th><th>Export</th><th>UI</th><th>Reason</th></tr></thead>
                  <tbody id="coverageRegistryBody"><tr><td colspan="10">Loading...</td></tr></tbody>
                </table>
              </div>
            </section>
            <section class="panel">
              <h3>Completeness</h3>
              <div class="table-scroll">
                <table>
                  <thead><tr><th>Output</th><th>Rows</th><th>Artifacts</th><th>Completeness</th><th>Missing Columns</th><th>Warning</th></tr></thead>
                  <tbody id="coverageCompletenessBody"><tr><td colspan="6">Loading...</td></tr></tbody>
                </table>
              </div>
            </section>
          </div>
          <div class="two-col" style="margin-top:16px;">
            <section class="panel">
              <h3>Persistence Audit</h3>
              <div class="table-scroll">
                <table>
                  <thead><tr><th>Output</th><th>Backend Source</th><th>Writer</th><th>CSV</th><th>JSON</th><th>Retention</th></tr></thead>
                  <tbody id="coveragePersistenceBody"><tr><td colspan="6">Loading...</td></tr></tbody>
                </table>
              </div>
            </section>
            <section class="panel">
              <h3>API Exposure</h3>
              <div class="table-scroll">
                <table>
                  <thead><tr><th>Output</th><th>Backend Source</th><th>API Route</th><th>Schema</th><th>Non Empty</th><th>UI Bind</th><th>Export</th></tr></thead>
                  <tbody id="coverageAPIBody"><tr><td colspan="7">Loading...</td></tr></tbody>
                </table>
              </div>
            </section>
          </div>
          <div class="two-col" style="margin-top:16px;">
            <section class="panel">
              <h3>Honest Unavailable Registry</h3>
              <div class="table-scroll">
                <table>
                  <thead><tr><th>Output</th><th>Code</th><th>Reason</th><th>Source Needed</th><th>Capture Point</th><th>Next Step</th></tr></thead>
                  <tbody id="coverageUnavailableBody"><tr><td colspan="6">Loading...</td></tr></tbody>
                </table>
              </div>
            </section>
            <section class="panel">
              <h3>Compare-Run Prerequisites</h3>
              <div class="table-scroll">
                <table>
                  <thead><tr><th>Output</th><th>Prerequisite</th><th>Status</th><th>Reason</th><th>Next Action</th></tr></thead>
                  <tbody id="coverageCompareBody"><tr><td colspan="5">Loading...</td></tr></tbody>
                </table>
              </div>
            </section>
          </div>
        </section>
      </div>
      <div class="subtab-panel" data-analytics-tab-panel="rootcause">
        <section class="panel" style="padding:0;border:none;box-shadow:none;background:transparent;">
          <h2>Root Cause And Advanced Analytics</h2>
          <p class="muted">These dashboards render only persisted source tables. Missing analytics stay unavailable in the coverage registry until their runtime telemetry exists.</p>
          <section class="panel">
            <h3>Result Issue Registry</h3>
            <div class="table-scroll">
              <table>
                <thead><tr><th>Severity</th><th>Status</th><th>Category</th><th>Block</th><th>Direction</th><th>UE</th><th>Metric</th><th>Observed</th><th>Root Cause Hint</th><th>Fix Plan</th></tr></thead>
                <tbody id="issueRegistryBody"><tr><td colspan="10">Loading...</td></tr></tbody>
              </table>
            </div>
          </section>
          <div class="two-col">
            <section class="panel">
              <h3>Root Cause Candidates</h3>
              <div class="table-scroll">
                <table>
                  <thead><tr><th>UE</th><th>Cell</th><th>Direction</th><th>Symptom</th><th>Severity</th><th>Reason</th><th>Metric</th><th>Value</th></tr></thead>
                  <tbody id="rootCauseBody"><tr><td colspan="8">Loading...</td></tr></tbody>
                </table>
              </div>
            </section>
            <section class="panel">
              <h3>Cell-Edge Dashboard</h3>
              <div class="table-scroll">
                <table>
                  <thead><tr><th>UE</th><th>Zone</th><th>Throughput Mbps</th><th>Mean SINR dB</th><th>Mean BLER</th><th>Queue Bits</th></tr></thead>
                  <tbody id="cellEdgeBody"><tr><td colspan="6">Loading...</td></tr></tbody>
                </table>
              </div>
            </section>
          </div>
          <div class="two-col" style="margin-top:16px;">
            <section class="panel">
              <h3>Beam Stability Dashboard</h3>
              <div class="table-scroll">
                <table>
                  <thead><tr><th>UE</th><th>Cell</th><th>Events</th><th>Changes</th><th>Max Gain dB</th><th>Class</th></tr></thead>
                  <tbody id="beamStabilityBody"><tr><td colspan="6">Loading...</td></tr></tbody>
                </table>
              </div>
            </section>
            <section class="panel">
              <h3>Energy Root Cause Dashboard</h3>
              <div class="table-scroll">
                <table>
                  <thead><tr><th>Entity Type</th><th>Entity</th><th>Total Energy J</th><th>Useful Bits</th><th>Energy/bit nJ</th><th>Reason</th></tr></thead>
                  <tbody id="energyRootCauseBody"><tr><td colspan="6">Loading...</td></tr></tbody>
                </table>
              </div>
            </section>
          </div>
          <div class="two-col" style="margin-top:16px;">
            <section class="panel">
              <h3>Power / Energy Preview</h3>
              <div class="table-scroll">
                <table>
                  <thead><tr><th>Entity</th><th>Direction</th><th>State</th><th>Power</th><th>Unit</th><th>Role</th><th>Status</th><th>Energy mJ</th><th>Useful Bits</th></tr></thead>
                  <tbody id="powerEnergyPreviewBody"><tr><td colspan="9">Loading...</td></tr></tbody>
                </table>
              </div>
            </section>
            <section class="panel">
              <h3>PRB Allocation Preview</h3>
              <div class="table-scroll">
                <table>
                  <thead><tr><th>Frame</th><th>Slot</th><th>Cell</th><th>UE</th><th>Direction</th><th>RB Start</th><th>RB Len</th></tr></thead>
                  <tbody id="prbPreviewBody"><tr><td colspan="7">Loading...</td></tr></tbody>
                </table>
              </div>
            </section>
          </div>
        </section>
      </div>
      <div class="subtab-panel" data-analytics-tab-panel="map">
        <div class="toolbar" style="flex-wrap:wrap;align-items:center;">
          <label><strong>Coverage Layer</strong><br><select id="analyticsMapMetric"></select></label>
          <label><strong>Movement Slot</strong><br><input id="analyticsMapSlot" type="range" min="0" max="0" value="0" step="1" style="min-width:240px;"></label>
          <span id="analyticsMapSlotLabel" class="pill">Slot n/a</span>
        </div>
        <div id="analyticsMapMeta" class="toolbar" style="margin-top:12px;"></div>
        <p id="analyticsMapNote" class="muted"></p>
        <div id="analyticsMap" style="width:100%;height:560px;border-radius:18px;border:1px solid var(--border);overflow:hidden;"></div>
      </div>
      <div class="subtab-panel" data-analytics-tab-panel="images">
        <h2>Latest Images</h2>
        <div id="imageGrid" class="artifact-grid"></div>
      </div>
    </section>
    """
    return page_shell(
        f"Analytics {title_token}",
        body,
        active="analytics",
        run_id=run_id,
        extra_head='<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" /><script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script><script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>',
        extra_script=analytics_page_script(run_id, run_tag=run_tag, initial_payload=initial_payload),
        user_profile=user_profile,
    )


def output_status_badge_html(status: Any, code: Any = "") -> str:
    token = str(status or "unknown").strip().lower()
    color = {
        "implemented": "var(--success)",
        "partial": "var(--warm)",
        "schema_only": "var(--accent-3)",
        "blocked": "var(--danger)",
        "unavailable": "var(--muted)",
    }.get(token, "var(--muted)")
    label = f"{status or 'unknown'}"
    if code not in (None, ""):
        label += f" | {code}"
    return f'<span class="pill" style="border-color:{color};color:{color};">Status: {html.escape(str(label))}</span>'


def render_output_card_html(card: dict[str, Any]) -> str:
    href = str(card.get("href") or "#")
    output_name = str(card.get("output_name") or "output")
    reason = str(card.get("reason_code") or "none")
    next_action = str(card.get("next_action") or "")
    flags = [
        ("Backend", card.get("backend_source_exists_flag")),
        ("Persisted", card.get("persisted_flag")),
        ("API", card.get("api_exposed_flag")),
        ("Export", card.get("export_supported_flag")),
        ("UI", card.get("ui_rendered_flag")),
    ]
    flag_html = "".join(f'<span class="pill">{html.escape(label)}: {html.escape(str(value))}</span>' for label, value in flags)
    next_html = f'<p class="mini-note">Next: {html.escape(next_action)}</p>' if next_action else ""
    return (
        f'<div class="artifact-card" data-output-family-card="{html.escape(output_name)}">'
        f'<h3><a href="{html.escape(href)}">{html.escape(output_name)}</a></h3>'
        '<div class="toolbar">'
        f'{output_status_badge_html(card.get("current_status"), card.get("classification_code"))}'
        f'<span class="pill">Section: {html.escape(str(card.get("ui_section") or "n/a"))}</span>'
        f'<span class="pill">Source: {html.escape(str(card.get("source_mapping") or "n/a"))}</span>'
        '</div>'
        f'<div class="toolbar">{flag_html}</div>'
        f'<p class="mini-note">Reason: {html.escape(reason)}</p>'
        f'{next_html}'
        f'<div class="toolbar"><a class="button-link secondary" href="{html.escape(href)}">Open Output Page</a></div>'
        '</div>'
    )


def render_record_preview_table(rows: list[dict[str, Any]], *, empty_text: str) -> str:
    if not rows:
        return f'<p class="muted">{html.escape(empty_text)}</p>'
    columns: list[str] = []
    for row in rows:
        for key in row.keys():
            if key not in columns:
                columns.append(str(key))
            if len(columns) >= 16:
                break
        if len(columns) >= 16:
            break
    header = "".join(f"<th>{html.escape(col)}</th>" for col in columns)
    body = "".join(
        "<tr>" + "".join(f"<td>{html.escape(str(row.get(col, '')))}</td>" for col in columns) + "</tr>"
        for row in rows[:40]
    )
    return f'<div class="table-scroll"><table><thead><tr>{header}</tr></thead><tbody>{body}</tbody></table></div>'


def render_artifact_evidence(artifacts: list[dict[str, Any]], output_name: str) -> str:
    source_artifacts = find_output_family_artifacts(artifacts, output_name)
    if not source_artifacts:
        return '<p class="muted">No canonical source artifact exists for this output family in this run. The status badge and reason below are the browser truth for this output.</p>'
    cards: list[str] = []
    previews: list[str] = []
    for descriptor in source_artifacts:
        logical_path = str(descriptor.get("logical_path") or "")
        view_url = str(descriptor.get("view_url") or descriptor.get("download_url") or "#")
        download_url = str(descriptor.get("download_url") or view_url)
        cards.append(
            '<div class="artifact-card">'
            f'<h3>{html.escape(logical_path)}</h3>'
            f'<div class="toolbar"><a class="button-link secondary" href="{html.escape(view_url)}">Open</a>'
            f'<a class="button-link secondary" href="{html.escape(download_url)}">Download</a></div>'
            '</div>'
        )
        artifact_id = int(descriptor.get("artifact_id") or 0)
        if str(descriptor.get("artifact_kind") or "") == "table_csv" and artifact_id > 0:
            header, raw_rows = load_cached_csv_rows(artifact_id, 40)
            rows = [
                {str(name): row[idx] if idx < len(row) else "" for idx, name in enumerate(header)}
                for row in raw_rows
            ]
            previews.append(
                f'<section class="panel"><h3>Canonical Data Preview: {html.escape(logical_path)}</h3>'
                f'{render_record_preview_table(rows, empty_text="The canonical artifact exists but has no preview rows.")}</section>'
            )
        elif str(descriptor.get("mime_type") or "").startswith("image/"):
            previews.append(
                f'<section class="panel"><h3>Canonical Image: {html.escape(logical_path)}</h3>'
                f'<a href="{html.escape(view_url)}"><img src="{html.escape(view_url)}" alt="{html.escape(logical_path)}" style="max-width:100%;border-radius:18px;border:1px solid var(--border);" /></a></section>'
            )
    return '<div class="artifact-grid">' + "".join(cards) + "</div>" + "".join(previews)


def build_outputs_index_page(run_id: int | None, run_tag: str | None = None, message: str = "", user_profile: dict[str, Any] | None = None) -> bytes:
    if run_id is None and not run_tag:
        run_id = latest_run_id()
    if run_id is None and not run_tag:
        return page_shell("Output Families", '<section class="panel"><h2>Output Families</h2><p>No runs found.</p></section>', active="outputs", user_profile=user_profile)
    if run_id is None:
        body = '<section class="panel"><h2>Output Families</h2><p class="muted">Waiting for the run row before output-family cards can be resolved.</p></section>'
        return page_shell("Output Families", body, active="outputs", user_profile=user_profile)
    payload = build_live_payload(run_id)
    coverage = payload.get("output_coverage") or {}
    cards = list(coverage.get("output_family_cards") or [])
    message_html = f'<section class="panel"><strong>{html.escape(message)}</strong></section>' if message else ""
    grouped: dict[str, list[dict[str, Any]]] = {}
    for card in cards:
        grouped.setdefault(str(card.get("ui_section") or "other"), []).append(card)
    groups_html = []
    for section_name in sorted(grouped):
        cards_html = "".join(render_output_card_html(card) for card in grouped[section_name])
        groups_html.append(
            f'<section class="panel"><h3>{html.escape(section_name)}</h3>'
            f'<div class="artifact-grid">{cards_html}</div></section>'
        )
    body = f"""
    {message_html}
    <section class="panel">
      <h2>Output Family Index</h2>
      <p class="muted">Every requested output family from the coverage registry is represented here. Cards link to per-output routes; unavailable and schema-only outputs show their blocker and next action instead of blank/fake charts.</p>
      <div class="toolbar">
        <a class="button-link secondary" href="/analytics?run_id={int(run_id)}">Back To Analytics</a>
        <a class="button-link secondary" href="/result?run_id={int(run_id)}">Result</a>
      </div>
    </section>
    {''.join(groups_html) if groups_html else '<section class="panel"><p class="muted">The output coverage registry is not available yet.</p></section>'}
    """
    return page_shell("Output Families", body, active="outputs", run_id=run_id, user_profile=user_profile)


def build_output_family_page(run_id: int | None, output_name: str, run_tag: str | None = None, user_profile: dict[str, Any] | None = None) -> bytes:
    output_name = urllib.parse.unquote(str(output_name or "")).strip()
    if run_id is None and not run_tag:
        run_id = latest_run_id()
    if run_id is None:
        body = '<section class="panel"><h2>Output Family</h2><p class="muted">Waiting for the run row before output-family detail can be resolved.</p></section>'
        return page_shell("Output Family", body, active="outputs", user_profile=user_profile)
    payload = build_live_payload(run_id)
    artifacts = fetch_artifacts(run_id)
    coverage = payload.get("output_coverage") or {}
    registry = list(coverage.get("registry") or [])
    row = _row_by_output_name(registry, output_name)
    if not row:
        body = (
            '<section class="panel"><h2>Output Family Not Found</h2>'
            f'<p class="muted">No registry row named <code>{html.escape(output_name)}</code> exists for run {int(run_id)}.</p>'
            f'<div class="toolbar"><a class="button-link secondary" href="/outputs?run_id={int(run_id)}">Back To Output Families</a></div></section>'
        )
        return page_shell("Output Family Missing", body, active="outputs", run_id=run_id, user_profile=user_profile)
    unavailable = _row_by_output_name(list(coverage.get("honest_unavailable") or []), output_name)
    api = _row_by_output_name(list(coverage.get("api_audit") or []), output_name)
    persistence = _row_by_output_name(list(coverage.get("persistence_audit") or []), output_name)
    compare = _row_by_output_name(list(coverage.get("compare_prerequisites") or []), output_name)
    detail_rows = [
        {"field": "output_name", "value": output_name},
        {"field": "status", "value": row.get("current_status")},
        {"field": "classification_code", "value": row.get("classification_code")},
        {"field": "ui_section", "value": row.get("ui_section")},
        {"field": "block_module", "value": row.get("block_module")},
        {"field": "backend_source_exists_flag", "value": row.get("backend_source_exists_flag")},
        {"field": "persisted_flag", "value": row.get("persisted_flag")},
        {"field": "api_exposed_flag", "value": row.get("api_exposed_flag")},
        {"field": "export_supported_flag", "value": row.get("export_supported_flag")},
        {"field": "ui_rendered_flag", "value": row.get("ui_rendered_flag")},
        {"field": "blocker_reason", "value": row.get("blocker_reason")},
        {"field": "api_route", "value": api.get("api_route", "")},
        {"field": "api_backend_source", "value": api.get("backend_source", "")},
        {"field": "api_response_non_empty_flag", "value": api.get("response_non_empty_flag", "")},
        {"field": "persistence_writer_enabled", "value": persistence.get("writer_enabled", "")},
        {"field": "persistence_csv_enabled", "value": persistence.get("csv_enabled", "")},
        {"field": "persistence_json_enabled", "value": persistence.get("json_enabled", "")},
        {"field": "unavailable_reason", "value": unavailable.get("unavailable_reason", "")},
        {"field": "required_backend_sources", "value": unavailable.get("required_backend_sources", "")},
        {"field": "required_capture_point", "value": unavailable.get("required_capture_point", "")},
        {"field": "next_implementation_step", "value": unavailable.get("next_implementation_step", "") or compare.get("next_action", "")},
    ]
    reason = str(row.get("blocker_reason") or unavailable.get("unavailable_reason") or compare.get("status") or "")
    unavailable_panel = ""
    if str(row.get("current_status") or "") in {"unavailable", "schema_only", "blocked", "partial"}:
        unavailable_panel = (
            '<section class="panel">'
            '<h3>Honest Non-Implemented State</h3>'
            f'<p class="muted">Reason code: <code>{html.escape(reason or "none")}</code></p>'
            f'{render_record_preview_table([unavailable] if unavailable else [compare] if compare else [], empty_text="No separate unavailable/prerequisite row was published for this output.")}'
            '</section>'
        )
    body = f"""
    <section class="panel">
      <h2>Output Family: {html.escape(output_name)}</h2>
      <div class="toolbar">
        {output_status_badge_html(row.get("current_status"), row.get("classification_code"))}
        <span class="pill">Source: {html.escape(str(api.get("backend_source") or row.get("block_module") or "n/a"))}</span>
        <span class="pill">Reason: {html.escape(reason or "none")}</span>
      </div>
      <p class="muted">This page reads the canonical registry/audit artifacts and any matching canonical DB-backed output artifact. It does not synthesize charts or rows for missing outputs.</p>
      <div class="toolbar">
        <a class="button-link secondary" href="/outputs?run_id={int(run_id)}">All Output Families</a>
        <a class="button-link secondary" href="/analytics?run_id={int(run_id)}">Analytics Coverage</a>
        <a class="button-link secondary" href="/result?run_id={int(run_id)}">Result</a>
      </div>
    </section>
    <section class="panel">
      <h3>Status, Source, Reason, And Next Action</h3>
      {render_record_preview_table(detail_rows, empty_text="No status details were available.")}
    </section>
    <section class="panel">
      <h3>Canonical Runtime Evidence</h3>
      {render_artifact_evidence(artifacts, output_name)}
    </section>
    {unavailable_panel}
    """
    return page_shell(f"Output {output_name}", body, active="outputs", run_id=run_id, user_profile=user_profile)


def map_page_script(run_id: int) -> str:
    return f"""
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script>
const MAP_RUN_ID = {run_id}; const MAP_POLL_MS = {POLL_INTERVAL_MS}; let mapRef = null; let layerRef = null;
function esc(value) {{ return String(value ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;'); }}
function colorFor(type) {{ if (type === 'ue') return '#2563eb'; if (type === 'site') return '#0d5c63'; return '#a63d40'; }}
function applyMapView(payload) {{
  const preferredZoom = Number(payload.preferred_zoom || 16);
  const bounds = payload.bounds || null;
  if (bounds && typeof bounds.min_lat === 'number' && typeof bounds.max_lat === 'number' && typeof bounds.min_lon === 'number' && typeof bounds.max_lon === 'number') {{
    const samePoint = Math.abs(bounds.max_lat - bounds.min_lat) < 1e-8 && Math.abs(bounds.max_lon - bounds.min_lon) < 1e-8;
    if (samePoint) {{
      mapRef.setView([payload.center.lat, payload.center.lon], preferredZoom);
      return;
    }}
    const latLngBounds = L.latLngBounds([[bounds.min_lat, bounds.min_lon], [bounds.max_lat, bounds.max_lon]]);
    mapRef.fitBounds(latLngBounds, {{ padding: [36, 36], maxZoom: preferredZoom }});
    return;
  }}
  mapRef.setView([payload.center.lat, payload.center.lon], preferredZoom || 15);
}}
async function refreshMap() {{
  const resp = await fetch(`/api/run/${{MAP_RUN_ID}}/map`, {{ credentials: 'same-origin' }});
  if (!resp.ok) throw new Error(`HTTP ${{resp.status}}`);
  const payload = await resp.json();
  document.getElementById('mapMeta').innerHTML = `<span class="pill">Center: ${{esc(payload.center.label)}}</span><span class="pill">Sites: ${{esc(payload.sites.length)}}</span><span class="pill">Sectors: ${{esc((payload.sector_polygons || []).length)}}</span><span class="pill">UEs: ${{esc(payload.ues.length)}}</span><span class="pill">Coverage: ${{esc((payload.coverage_points || []).length)}}</span><span class="pill">Preferred Zoom: ${{esc(payload.preferred_zoom)}}</span>`;
  document.getElementById('mapNote').textContent = payload.note || '';
  if (!mapRef) {{
    mapRef = L.map('map');
    L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png', {{ attribution: '&copy; OpenStreetMap contributors' }}).addTo(mapRef);
    layerRef = L.layerGroup().addTo(mapRef);
  }}
  layerRef.clearLayers();
  for (const shape of (payload.site_polygons || [])) {{
    const pts = (shape.points || []).map((point) => [point[0], point[1]]);
    if (pts.length >= 3) {{
      const poly = L.polygon(pts, {{
        color: '#155e75',
        weight: 1.5,
        opacity: 0.85,
        fillColor: '#67e8f9',
        fillOpacity: 0.06,
      }});
      poly.bindPopup(`<strong>${{esc(shape.label || 'Site')}}</strong><br>Hexagonal site footprint`);
      poly.addTo(layerRef);
    }}
  }}
  for (const sector of (payload.sector_polygons || [])) {{
    const pts = (sector.points || []).map((point) => [point[0], point[1]]);
    if (pts.length >= 3) {{
      const poly = L.polygon(pts, {{
        color: '#dc2626',
        weight: 1.2,
        opacity: 0.75,
        fillColor: '#fca5a5',
        fillOpacity: 0.08,
      }});
      poly.bindPopup(`<strong>${{esc(sector.label || 'Sector')}}</strong><br>Azimuth: ${{esc(sector.azimuth_deg)}} deg`);
      poly.addTo(layerRef);
    }}
  }}
  for (const path of ((payload.movement || {{}}).paths || [])) {{
    const pathPoints = (path.points || []).map((point) => [point.lat, point.lon]);
    if (pathPoints.length >= 2) {{
      L.polyline(pathPoints, {{ color: '#94a3b8', weight: 1.4, opacity: 0.4 }}).addTo(layerRef);
    }}
  }}
  for (const point of (payload.coverage_points || [])) {{
    const marker = L.circleMarker([point.lat, point.lon], {{ radius: 7, color: '#f59e0b', weight: 1.2, fillColor: '#fbbf24', fillOpacity: 0.28 }});
    marker.bindPopup(`<strong>UE ${{esc(point.ueid)}}</strong><br>RSRP: ${{esc(point.RSRP_dBm)}} dBm<br>Receiver Hest SINR: ${{esc(point.ReceiverHestWidebandSINR_dB ?? '')}} dB<br>System-level SINR estimate: ${{esc(point.SystemLevelWidebandSINR_dB ?? '')}} dB<br>CQI: ${{esc(point.WidebandCQI)}}`);
    marker.addTo(layerRef);
  }}
  for (const item of (payload.markers || [])) {{
    const marker = L.circleMarker([item.lat, item.lon], {{ radius: item.type === 'ue' ? 5 : 8, color: colorFor(item.type), weight: 2, fillOpacity: 0.7 }});
    marker.bindPopup(`<strong>${{esc(item.label)}}</strong><br>${{esc(item.type)}}<br>${{esc(item.source || '')}}${{item.slot ? `<br>Slot: ${{esc(item.slot)}}` : ''}}${{item.serving_cell ? `<br>Serving Cell: ${{esc(item.serving_cell)}}` : ''}}`);
    marker.addTo(layerRef);
  }}
  applyMapView(payload);
}}
refreshMap().catch((err) => {{ document.getElementById('mapNote').textContent = `Map refresh failed: ${{err}}`; }});
window.setInterval(() => {{ refreshMap().catch((err) => {{ document.getElementById('mapNote').textContent = `Map refresh failed: ${{err}}`; }}); }}, MAP_POLL_MS);
</script>
"""


def build_map_page(run_id: int | None, user_profile: dict[str, Any] | None = None) -> bytes:
    run_id = run_id or latest_run_id()
    if run_id is None:
        return page_shell("Map", '<section class="panel"><h2>Map</h2><p>No runs found.</p></section>', active="map", user_profile=user_profile)
    body = f"""
    <section class="panel">
      <h2>OpenStreetMap Live View</h2>
      <p class="muted">Default center is set to {html.escape(DEFAULT_MAP_CENTER['label'])}. If a run publishes site or UE geography tables into MySQL, this map automatically overlays them.</p>
      <div id="mapMeta" class="toolbar"></div>
      <p id="mapNote" class="muted"></p>
    </section>
    <section class="panel"><div id="map"></div></section>
    """
    return page_shell(
        f"Map {run_id}",
        body,
        active="map",
        run_id=run_id,
        extra_head='<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />',
        extra_script=map_page_script(run_id),
        user_profile=user_profile,
    )


class DashboardHandler(BaseHTTPRequestHandler):
    server_version = "SixGRDashboard/2.0"

    def current_session(self) -> tuple[str | None, dict[str, Any] | None]:
        if auth_mode_open():
            return None, dict(OPEN_ACCESS_PROFILE)
        return resolve_user_profile_from_cookie(self.headers.get("Cookie"))

    def require_authentication(self, parsed: urllib.parse.ParseResult) -> tuple[str | None, dict[str, Any] | None] | None:
        if auth_mode_open():
            return None, dict(OPEN_ACCESS_PROFILE)
        token, user_profile = self.current_session()
        if user_profile is not None:
            return token, user_profile
        target = parsed.path + (f"?{parsed.query}" if parsed.query else "")
        if parsed.path.startswith("/api/") or parsed.path.startswith("/artifact/"):
            self.respond_json({"error": "authentication_required", "login_url": f"/login?next={urllib.parse.quote(target)}"}, status=HTTPStatus.UNAUTHORIZED)
            return None
        self.redirect(f"/login?next={urllib.parse.quote(target)}")
        return None

    def finish_login(self, username: str, next_url: str) -> None:
        if auth_mode_open():
            self.redirect(next_url or "/home")
            return
        token = create_session(username)
        self.send_response(HTTPStatus.SEE_OTHER)
        self.send_header("Location", next_url or "/home")
        self.send_header("Set-Cookie", f"{SESSION_COOKIE_NAME}={token}; Path=/; HttpOnly; SameSite=Lax")
        self.end_headers()

    def finish_logout(self, token: str | None, next_url: str = "/login") -> None:
        if auth_mode_open():
            self.redirect("/home")
            return
        clear_session(token)
        self.send_response(HTTPStatus.SEE_OTHER)
        self.send_header("Location", next_url)
        self.send_header("Set-Cookie", f"{SESSION_COOKIE_NAME}=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        try:
            parsed = urllib.parse.urlparse(self.path)
            params = urllib.parse.parse_qs(parsed.query)
            if parsed.path == "/login":
                if auth_mode_open():
                    self.redirect(params.get("next", ["/home"])[0] or "/home")
                    return
                _, active_profile = self.current_session()
                if active_profile is not None:
                    self.redirect(params.get("next", ["/home"])[0] or "/home")
                    return
                self.respond_html(build_login_page(params.get("message", [""])[0], params.get("next", ["/home"])[0]))
                return
            auth = self.require_authentication(parsed)
            if auth is None:
                return
            _, user_profile = auth
            if parsed.path == "/profile":
                self.respond_html(build_profile_page(user_profile))
                return
            if parsed.path == "/api/status":
                self.respond_json(product_backend_status())
                return
            if parsed.path == "/api/output-contract":
                self.respond_json({
                    "reports": output_contract.product_sections_payload("reports"),
                    "analytics": output_contract.product_sections_payload("analytics"),
                    "base_context_columns": output_contract.BASE_CONTEXT_COLUMNS,
                    "mandatory_context_columns": output_contract.MANDATORY_CONTEXT_COLUMNS,
                    "value_roles": output_contract.VALUE_ROLES,
                    "value_statuses": output_contract.VALUE_STATUSES,
                    "rule": "/reports is runtime truth; /analytics is derived post-processing. Missing values stay unavailable.",
                })
                return
            if parsed.path == "/config/download":
                scenario_name = params.get("scenario", [DEFAULT_SCENARIO])[0]
                config_payload, source_chain = load_resolved_config_payload(scenario_name)
                payload = dict(config_payload)
                payload.setdefault("run_control", {})
                if isinstance(payload["run_control"], dict):
                    payload["run_control"]["execution_mode"] = str(payload["run_control"].get("execution_mode") or "LLS").strip().upper()
                payload["_download_metadata"] = {
                    "scenario": scenario_name,
                    "source_chain": source_chain,
                    "matlab_exe": str(MATLAB_EXE),
                    "mysql_database": MYSQL_DATABASE,
                    "note": "Resolved config snapshot for browser verification. Browser-side edits use the Download Config JSON quick action.",
                }
                self.respond_json_download(payload, filename="sixgr_final_config.json")
                return
            if parsed.path.startswith("/run/") and parsed.path.split("/")[-1].isdigit():
                self.redirect(f"/realtime?run_id={urllib.parse.quote(parsed.path.split('/')[-1])}")
                return
            if (
                parsed.path in PRODUCT_PAGE_ROUTES
                or parsed.path.startswith("/reports/")
                or parsed.path.startswith("/analytics/")
                or parsed.path.startswith("/result/")
                or parsed.path.startswith("/outputs/")
            ):
                # The legacy page builders below remain in the file for history/debug helpers,
                # but this product router shadows the old active GUI routes.
                page_id = PRODUCT_PAGE_ROUTES.get(parsed.path)
                if page_id is None:
                    if parsed.path.startswith("/reports/"):
                        page_id = "reports"
                    elif parsed.path.startswith("/analytics/"):
                        page_id = "analytics"
                    else:
                        page_id = "realtime" if parsed.path.startswith("/result/") else "artifacts"
                self.respond_html(
                    build_product_frontend_page(
                        page_id,
                        params.get("scenario", [DEFAULT_SCENARIO])[0],
                        params.get("message", [""])[0],
                        user_profile=user_profile,
                    )
                )
                return
            if parsed.path in {"/", "/home"}:
                self.respond_html(build_home_page(params.get("scenario", [DEFAULT_SCENARIO])[0], params.get("message", [""])[0], user_profile=user_profile))
                return
            if parsed.path == "/runs":
                self.respond_html(build_runs_page(params.get("message", [""])[0], user_profile=user_profile))
                return
            if parsed.path.startswith("/run/"):
                run_id = int(parsed.path.split("/")[-1])
                self.respond_html(build_run_page(run_id, user_profile=user_profile))
                return
            if parsed.path == "/analytics":
                self.respond_html(
                    build_analytics_page(
                        parse_optional_int(params.get("run_id", [None])[0]),
                        run_tag=params.get("run_tag", [None])[0],
                        message=params.get("message", [""])[0],
                        user_profile=user_profile,
                    )
                )
                return
            if parsed.path == "/outputs":
                self.respond_html(
                    build_outputs_index_page(
                        parse_optional_int(params.get("run_id", [None])[0]),
                        run_tag=params.get("run_tag", [None])[0],
                        message=params.get("message", [""])[0],
                        user_profile=user_profile,
                    )
                )
                return
            if parsed.path.startswith("/outputs/"):
                output_name = urllib.parse.unquote(parsed.path.split("/", 2)[2])
                self.respond_html(
                    build_output_family_page(
                        parse_optional_int(params.get("run_id", [None])[0]),
                        output_name,
                        run_tag=params.get("run_tag", [None])[0],
                        user_profile=user_profile,
                    )
                )
                return
            if parsed.path == "/result" or parsed.path.startswith("/result/"):
                section = "all"
                if parsed.path.startswith("/result/"):
                    section = normalize_result_section(parsed.path.split("/", 2)[2])
                self.respond_html(
                    build_result_page(
                        parse_optional_int(params.get("run_id", [None])[0]),
                        run_tag=params.get("run_tag", [None])[0],
                        message=params.get("message", [""])[0],
                        section=section,
                        user_profile=user_profile,
                    )
                )
                return
            if parsed.path == "/map":
                self.respond_html(build_map_page(parse_optional_int(params.get("run_id", [None])[0]), user_profile=user_profile))
                return
            if parsed.path == "/tables":
                self.respond_html(build_tables_page(parse_optional_int(params.get("run_id", [None])[0]), user_profile=user_profile))
                return
            if parsed.path == "/images":
                self.respond_html(build_images_page(parse_optional_int(params.get("run_id", [None])[0]), user_profile=user_profile))
                return
            if parsed.path == "/logs":
                self.respond_html(build_logs_page(parse_optional_int(params.get("run_id", [None])[0]), user_profile=user_profile))
                return
            if parsed.path.startswith("/artifact/") and parsed.path.endswith("/table"):
                artifact_id = int(parsed.path.split("/")[2])
                self.respond_html(build_table_preview_page(artifact_id, user_profile=user_profile))
                return
            if parsed.path.startswith("/artifact/") and parsed.path.endswith("/raw"):
                artifact_id = int(parsed.path.split("/")[2])
                self.respond_artifact(artifact_id, download=(params.get("download", ["0"])[0] == "1"))
                return
            if parsed.path == "/api/runs":
                limit_raw = params.get("limit", ["50"])[0]
                try:
                    limit = max(1, min(200, int(limit_raw)))
                except ValueError:
                    limit = 50
                self.respond_json({"runs": fetch_runs(limit=limit, run_tag=params.get("run_tag", [None])[0])})
                return
            if parsed.path == "/api/scenario-fields":
                scenarios = list_scenarios()
                scenario_name = params.get("scenario", [DEFAULT_SCENARIO])[0]
                if scenario_name not in scenarios:
                    scenario_name = DEFAULT_SCENARIO if DEFAULT_SCENARIO in scenarios else (scenarios[0] if scenarios else DEFAULT_SCENARIO)
                config_payload, source_chain = load_resolved_config_payload(scenario_name)
                fields = product_field_records(config_payload)
                self.respond_json(
                    {
                        "scenario": scenario_name,
                        "field_count": len(fields),
                        "fields": fields,
                        "source_chain": source_chain,
                    }
                )
                return
            if parsed.path == "/api/scenario-config":
                scenarios = list_scenarios()
                scenario_name = params.get("scenario", [DEFAULT_SCENARIO])[0]
                if scenario_name not in scenarios:
                    scenario_name = DEFAULT_SCENARIO if DEFAULT_SCENARIO in scenarios else (scenarios[0] if scenarios else DEFAULT_SCENARIO)
                config_payload, source_chain = load_resolved_config_payload(scenario_name)
                mode = str(path_get(config_payload, "run_control.execution_mode", "LLS") or "LLS").strip().upper()
                if mode not in BROWSER_EXECUTION_MODE_OPTIONS:
                    mode = "LLS"
                self.respond_json(
                    {
                        "scenario": scenario_name,
                        "mode": mode,
                        "config": config_payload,
                        "config_loaded": True,
                        "config_overview": product_config_overview(config_payload, scenario_name, mode),
                        "scenario_contract": scenario_launch_contract(config_payload, scenario_name),
                        "field_count": product_field_count(config_payload),
                        "source_chain": source_chain,
                    }
                )
                return
            if parsed.path.startswith("/api/run/") and parsed.path.endswith("/live"):
                run_id = int(parsed.path.split("/")[3])
                lite = params.get("lite", ["0"])[0] in {"1", "true", "yes"}
                self.respond_json(build_live_payload(run_id, lite=lite))
                return
            if parsed.path.startswith("/api/run/") and parsed.path.endswith("/contract-section"):
                run_id = int(parsed.path.split("/")[3])
                kind = params.get("kind", ["analytics"])[0]
                slug = params.get("slug", [""])[0]
                self.respond_json(build_contract_section_payload(run_id, kind=kind, slug=slug))
                return
            if parsed.path.startswith("/api/run/") and parsed.path.endswith("/map"):
                run_id = int(parsed.path.split("/")[3])
                self.respond_json(build_live_payload(run_id)["map"])
                return
            if parsed.path.startswith("/api/run/"):
                run_id = int(parsed.path.split("/")[3])
                self.respond_json(fetch_run(run_id))
                return
            if parsed.path.startswith("/api/artifact/") and parsed.path.endswith("/preview"):
                artifact_id = int(parsed.path.split("/")[3])
                meta = fetch_artifact_meta(artifact_id)
                if meta is None:
                    raise KeyError(f"Artifact {artifact_id} was not found.")
                header, rows = load_cached_csv_preview(int(artifact_id), MAX_TABLE_PREVIEW_ROWS)
                self.respond_json({"meta": meta, "header": header, "rows": rows})
                return
            self.respond_error(HTTPStatus.NOT_FOUND, "Unknown route.")
        except KeyError as exc:
            self.respond_error(HTTPStatus.NOT_FOUND, str(exc))
        except Exception as exc:  # pragma: no cover
            self.respond_error(HTTPStatus.INTERNAL_SERVER_ERROR, str(exc))

    def do_POST(self) -> None:  # noqa: N802
        try:
            parsed = urllib.parse.urlparse(self.path)
            content_length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(content_length).decode("utf-8")
            fields = urllib.parse.parse_qs(raw, keep_blank_values=True)
            if parsed.path == "/login":
                if auth_mode_open():
                    self.redirect(str(fields.get("next", ["/home"])[0] or "/home"))
                    return
                username = str(fields.get("username", [""])[0]).strip().lower()
                password = str(fields.get("password", [""])[0])
                next_url = str(fields.get("next", ["/home"])[0] or "/home")
                profile = USER_PROFILES.get(username)
                if profile is None or password != str(profile.get("password") or ""):
                    self.redirect(f"/login?message={urllib.parse.quote('Invalid username or password.')}&next={urllib.parse.quote(next_url)}")
                    return
                self.finish_login(username, next_url if next_url.startswith("/") else "/home")
                return
            if parsed.path == "/logout":
                if auth_mode_open():
                    self.redirect("/home")
                    return
                token, _ = self.current_session()
                self.finish_logout(token)
                return
            auth = self.require_authentication(parsed)
            if auth is None:
                return
            next_url = str(fields.get("next", ["/home"])[0] or "/home")
            next_url = next_url if next_url.startswith("/") else "/home"
            if parsed.path == "/admin/clear":
                stats = clear_dashboard_storage()
                message = (
                    f"Cleared {stats['runs']} runs, {stats['artifacts']} artifacts, {stats['chunks']} chunks, "
                    f"{stats['logs']} log rows, {stats['runtime_yaml']} runtime YAML files, and "
                    f"{stats['disk_entries']} disk entries."
                )
                self.redirect(f"{next_url}?message={urllib.parse.quote(message)}")
                return
            if parsed.path == "/admin/delete-run":
                run_id_text = str(fields.get("run_id", [""])[0]).strip()
                if not run_id_text.isdigit():
                    raise ValueError("A numeric run_id is required for deletion.")
                stats = delete_run_storage(int(run_id_text))
                message = (
                    f"Deleted run {stats['run_id']} ({stats['run_tag']}): "
                    f"{stats['artifacts']} artifacts, {stats['chunks']} chunks, {stats['logs']} log rows, "
                    f"{stats['runtime_yaml']} runtime YAML files, and {stats['disk_entries']} disk entries removed."
                )
                self.redirect(f"{next_url}?message={urllib.parse.quote(message)}")
                return
            if parsed.path != "/run":
                self.respond_error(HTTPStatus.NOT_FOUND, "Unknown route.")
                return
            scenario_name = fields.get("scenario", [DEFAULT_SCENARIO])[0]
            run_tag = (fields.get("run_tag", [""])[0] or timestamp_tag("web")).strip()
            config_json_text = fields.get("config_json", [""])[0].strip()
            requested_payload: dict[str, Any] | None = None
            if config_json_text:
                config_payload = json.loads(config_json_text)
                if not isinstance(config_payload, dict):
                    raise ValueError("Browser config payload must decode to a mapping.")
                requested_payload = canonicalize_browser_config_payload(config_payload)
                requested_mode = str(path_get(requested_payload, "run_control.execution_mode", "LLS") or "LLS").strip().upper()
                if requested_mode not in BROWSER_EXECUTION_MODE_OPTIONS:
                    requested_mode = "LLS"
                yaml_text = yaml.safe_dump(requested_payload, sort_keys=False, allow_unicode=False)
            else:
                requested_mode = str(fields.get("execution_mode", ["LLS"])[0] or "LLS").strip().upper()
                if requested_mode not in BROWSER_EXECUTION_MODE_OPTIONS:
                    requested_mode = "LLS"
                yaml_text = fields.get("yaml_text", [""])[0]
                raw_payload = yaml.safe_load(yaml_text) if yaml_text else {}
                if raw_payload is None:
                    raw_payload = {}
                if not isinstance(raw_payload, dict):
                    raise ValueError("Scenario YAML must decode to a mapping at the top level.")
                requested_payload = canonicalize_browser_config_payload(raw_payload)
            if requested_mode != FULLY_WIRED_BROWSER_EXECUTION_MODE:
                raise ValueError(
                    f"Execution mode {BROWSER_EXECUTION_MODE_LABELS.get(requested_mode, requested_mode)!r} is intentionally separated from the LLS browser run path and is not launchable from /run in this pass."
                )
            enforce_browser_launch_contract(str(scenario_name), requested_payload)
            launch_tag, log_file, runtime_path = launch_run_from_yaml(scenario_name, yaml_text, run_tag)
            message = f"Started run '{launch_tag}'. MATLAB stdout is being written to {log_file}. Runtime YAML: {runtime_path.name}"
            self.redirect(
                f"/result?run_tag={urllib.parse.quote(launch_tag)}&message={urllib.parse.quote(message)}"
            )
        except Exception as exc:
            fallback_target = "/home"
            try:
                fallback_target = next_url if isinstance(next_url, str) and next_url.startswith("/") else "/home"
            except Exception:
                fallback_target = "/home"
            self.redirect(f"{fallback_target}?message={urllib.parse.quote(str(exc))}")

    def respond_html(self, payload: bytes) -> None:
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def respond_json(self, payload: Any, status: HTTPStatus = HTTPStatus.OK) -> None:
        raw = json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def respond_json_download(self, payload: Any, *, filename: str) -> None:
        raw = json_bytes(payload)
        safe_name = re.sub(r"[^A-Za-z0-9_.-]+", "_", filename).strip("_") or "config.json"
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Disposition", f'attachment; filename="{safe_name}"')
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def respond_error(self, status: HTTPStatus | int, message: str) -> None:
        try:
            code = int(status)
        except Exception:
            code = int(HTTPStatus.INTERNAL_SERVER_ERROR)
        phrase = HTTPStatus(code).phrase if code in HTTPStatus._value2member_map_ else "Error"
        request_path = ""
        try:
            request_path = urllib.parse.urlparse(str(self.path or "")).path
        except Exception:
            request_path = str(self.path or "")
        payload_message = str(message or phrase)
        if request_path.startswith("/api/"):
            raw = json_bytes({"error": payload_message, "status": code})
            self.send_response(code, phrase)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return
        raw = payload_message.encode("utf-8", errors="replace")
        self.send_response(code, phrase)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def respond_artifact(self, artifact_id: int, *, download: bool) -> None:
        meta = fetch_artifact_meta(artifact_id)
        if meta is None:
            raise KeyError(f"Artifact {artifact_id} was not found.")
        payload = fetch_artifact_bytes(artifact_id)
        mime_type = str(meta.get("mime_type") or "application/octet-stream")
        filename = Path(str(meta.get("logical_path") or artifact_id)).name
        disposition = "attachment" if download else "inline"
        etag = artifact_etag(meta)
        if_none_match = str(self.headers.get("If-None-Match") or "").strip()
        if if_none_match and if_none_match == etag:
            self.send_response(HTTPStatus.NOT_MODIFIED)
            self.send_header("ETag", etag)
            # Require revalidation so deleted/re-materialized artifact ids do
            # not stay pinned forever in browser caches, while still allowing
            # fast 304 responses through the in-process byte cache.
            self.send_header("Cache-Control", "private, max-age=0, must-revalidate")
            self.end_headers()
            return
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mime_type)
        self.send_header("Content-Disposition", f'{disposition}; filename="{filename}"')
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("ETag", etag)
        self.send_header("Cache-Control", "private, max-age=0, must-revalidate")
        self.end_headers()
        self.wfile.write(payload)

    def redirect(self, location: str) -> None:
        self.send_response(HTTPStatus.SEE_OTHER)
        self.send_header("Location", location)
        self.end_headers()

    def log_message(self, format_str: str, *args: Any) -> None:
        sys.stdout.write("%s - - [%s] %s\n" % (self.client_address[0], self.log_date_time_string(), format_str % args))


def detect_lan_ipv4_addresses() -> list[str]:
    addresses: list[str] = []

    def add_candidate(addr: str) -> None:
        addr = str(addr or "").strip()
        if not addr or addr.startswith("127.") or addr in addresses:
            return
        addresses.append(addr)

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("8.8.8.8", 80))
            add_candidate(sock.getsockname()[0])
    except Exception:
        pass
    try:
        for addr in socket.gethostbyname_ex(socket.gethostname())[2]:
            add_candidate(addr)
    except Exception:
        pass
    return addresses


def resolve_dashboard_urls(bind_host: str, actual_port: int, public_host: str) -> tuple[str, str, list[str]]:
    local_url = f"http://127.0.0.1:{actual_port}/"
    lan_urls = [f"http://{addr}:{actual_port}/" for addr in detect_lan_ipv4_addresses()]
    bind_host = str(bind_host or "").strip()
    public_host = str(public_host or "").strip()
    if public_host:
        intranet_url = f"http://{public_host}:{actual_port}/"
    elif bind_host.startswith("127.") or bind_host.lower() == "localhost":
        intranet_url = local_url
    elif bind_host in {"0.0.0.0", "::", ""}:
        intranet_url = lan_urls[0] if lan_urls else local_url
    else:
        intranet_url = f"http://{bind_host}:{actual_port}/"
    return local_url, intranet_url, lan_urls


def resolve_server_backend(requested_backend: str) -> str:
    token = str(requested_backend or DEFAULT_DASHBOARD_SERVER or "auto").strip().lower() or "auto"
    if token not in {"auto", "threading", "waitress"}:
        raise ValueError(f"Unsupported dashboard server backend: {requested_backend}")
    if token == "waitress":
        return "waitress"
    if token == "threading":
        return "threading"
    try:
        import waitress  # noqa: F401

        return "waitress"
    except Exception:
        return "threading"


class DashboardWSGIHandler(DashboardHandler):
    def __init__(self, environ: dict[str, Any], start_response: Any) -> None:
        self.environ = environ
        self._start_response = start_response
        self.command = str(environ.get("REQUEST_METHOD") or "GET").upper()
        path_info = str(environ.get("PATH_INFO") or "/")
        query = str(environ.get("QUERY_STRING") or "")
        self.path = path_info + (f"?{query}" if query else "")
        self.request_version = str(environ.get("SERVER_PROTOCOL") or "HTTP/1.1")
        self.requestline = f"{self.command} {self.path} {self.request_version}"
        self.client_address = (
            str(environ.get("REMOTE_ADDR") or "127.0.0.1"),
            int(environ.get("REMOTE_PORT") or 0),
        )
        self.server = None
        self.connection = None
        self.close_connection = True
        body = b""
        if self.command in {"POST", "PUT", "PATCH"}:
            try:
                content_length = int(environ.get("CONTENT_LENGTH") or 0)
            except Exception:
                content_length = 0
            body = environ.get("wsgi.input").read(content_length) if content_length > 0 else b""
        self.rfile = io.BytesIO(body)
        self.wfile = io.BytesIO()
        self.headers = email.message.Message()
        if environ.get("CONTENT_TYPE"):
            self.headers["Content-Type"] = str(environ.get("CONTENT_TYPE"))
        if environ.get("CONTENT_LENGTH"):
            self.headers["Content-Length"] = str(environ.get("CONTENT_LENGTH"))
        for key, value in environ.items():
            if not key.startswith("HTTP_"):
                continue
            header_name = key[5:].replace("_", "-").title()
            self.headers[header_name] = str(value)
        self._status_line = f"{HTTPStatus.OK.value} {HTTPStatus.OK.phrase}"
        self._response_headers: list[tuple[str, str]] = []

    def send_response(self, code: int, message: str | None = None) -> None:  # type: ignore[override]
        try:
            phrase = message or HTTPStatus(int(code)).phrase
        except Exception:
            phrase = message or "OK"
        self._status_line = f"{int(code)} {phrase}"

    def send_header(self, keyword: str, value: Any) -> None:  # type: ignore[override]
        self._response_headers.append((str(keyword), str(value)))

    def end_headers(self) -> None:  # type: ignore[override]
        return

    def finish(self) -> None:  # type: ignore[override]
        return

    def handle_exception(self, exc: Exception) -> None:
        self.respond_error(HTTPStatus.INTERNAL_SERVER_ERROR, str(exc))

    def send_error(self, code: int, message: str | None = None, explain: str | None = None) -> None:  # type: ignore[override]
        detail = message or explain or HTTPStatus(int(code)).phrase
        self.respond_error(int(code), str(detail))

    def dispatch(self) -> list[bytes]:
        try:
            if self.command == "POST":
                self.do_POST()
            elif self.command == "HEAD":
                self.do_GET()
            else:
                self.do_GET()
        except Exception as exc:  # pragma: no cover
            self.handle_exception(exc)
        payload = self.wfile.getvalue()
        headers = list(self._response_headers)
        if not any(key.lower() == "content-length" for key, _ in headers):
            headers.append(("Content-Length", str(len(payload))))
        self._start_response(self._status_line, headers)
        if self.command == "HEAD":
            return [b""]
        return [payload]


def dashboard_wsgi_app(environ: dict[str, Any], start_response: Any) -> list[bytes]:
    handler = DashboardWSGIHandler(environ, start_response)
    return handler.dispatch()


def main() -> int:
    parser = argparse.ArgumentParser(description="Real-time intranet dashboard for MySQL-backed 6G LLS runs.")
    parser.add_argument("--host", default=DEFAULT_DASHBOARD_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_DASHBOARD_PORT)
    parser.add_argument("--public-host", default=DEFAULT_DASHBOARD_PUBLIC_HOST)
    parser.add_argument("--server", choices=["auto", "threading", "waitress"], default=DEFAULT_DASHBOARD_SERVER)
    parser.add_argument("--threads", type=int, default=DEFAULT_DASHBOARD_THREADS)
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args()

    server_backend = resolve_server_backend(args.server)
    actual_port = int(args.port)
    local_url, intranet_url, lan_urls = resolve_dashboard_urls(args.host, actual_port, args.public_host)
    write_dashboard_listener_file(args.host, actual_port, local_url, intranet_url, lan_urls)
    print(f"6G LLS dashboard listening on {intranet_url}")
    print(f"Local URL    : {local_url}")
    print(f"Intranet URL : {intranet_url}")
    print(f"HTTP backend : {server_backend}")
    for idx, lan_url in enumerate(lan_urls[:5], start=1):
        print(f"LAN URL {idx}    : {lan_url}")
    print(
        textwrap.dedent(
            f"""
            MySQL target : {MYSQL_HOST}:{MYSQL_PORT}/{MYSQL_DATABASE}
            MATLAB path  : {MATLAB_EXE}
            Repo root    : {REPO_ROOT}
            Map default  : {DEFAULT_MAP_CENTER['label']} ({DEFAULT_MAP_CENTER['lat']:.6f}, {DEFAULT_MAP_CENTER['lon']:.6f})
            """
        ).strip()
    )
    if not args.no_browser:
        webbrowser.open(local_url)
    if server_backend == "waitress":
        try:
            from waitress import serve as waitress_serve
        except Exception as exc:
            print(f"Waitress is not available: {exc}", file=sys.stderr)
            return 1
        try:
            waitress_serve(
                dashboard_wsgi_app,
                host=args.host,
                port=actual_port,
                threads=max(4, int(args.threads)),
                connection_limit=max(512, int(args.threads) * 32),
                channel_timeout=120,
                cleanup_interval=30,
                ident="SixGRDashboard/2.0",
                expose_tracebacks=False,
            )
        except KeyboardInterrupt:
            print("\\nDashboard stopped.")
        return 0
    try:
        httpd = ThreadingHTTPServer((args.host, actual_port), DashboardHandler)
    except OSError as exc:
        print(f"Failed to bind dashboard server: {exc}", file=sys.stderr)
        return 1
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\\nDashboard stopped.")
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
