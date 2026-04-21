from __future__ import annotations

import argparse
import os
import json
import sys
import http.cookiejar
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

try:
    import mysql.connector
except Exception:  # pragma: no cover - optional in browser-only validation envs.
    mysql = None
else:
    mysql = mysql.connector


REQUIRED_ARTIFACTS = {
    "reports/csv/scenario_summary.csv",
    "reports/csv/artifact_inventory.csv",
    "reports/csv/truth_contract_summary.csv",
    "reports/csv/output_coverage_registry.csv",
    "meta/scenario_config_resolved.json",
}
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASE_URL = "http://127.0.0.1:62906"


def resolve_base_url(explicit_value: str) -> str:
    if explicit_value:
        return explicit_value.rstrip("/")
    env_value = os.environ.get("SIXGR_DASHBOARD_BASE_URL", "").strip()
    if env_value:
        return env_value.rstrip("/")
    listener_path = REPO_ROOT / "tmp_web_runs" / "dashboard_listener.json"
    if listener_path.is_file():
        try:
            payload = json.loads(listener_path.read_text(encoding="utf-8"))
            for key in ("local_url", "intranet_url"):
                value = str(payload.get(key) or "").strip()
                if value:
                    return value.rstrip("/")
        except Exception:
            pass
    return DEFAULT_BASE_URL


def login_opener(base_url: str, username: str, password: str) -> urllib.request.OpenerDirector:
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPCookieProcessor(jar),
    )
    body = urllib.parse.urlencode({"username": username, "password": password, "next": "/home"}).encode("utf-8")
    request = urllib.request.Request(f"{base_url.rstrip('/')}/login", data=body, method="POST")
    opener.open(request, timeout=10).read()
    return opener


def fetch_json(opener: urllib.request.OpenerDirector, url: str) -> dict[str, Any]:
    with opener.open(url, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def fetch_db_artifact_paths(run_id: int) -> set[str]:
    if mysql is None:
        return set()
    try:
        conn = mysql.connect(
            host=os.environ.get("MYSQL_HOST", "localhost"),
            port=int(os.environ.get("MYSQL_PORT", "3306")),
            user=os.environ.get("MYSQL_USER", "root"),
            password=os.environ.get("MYSQL_PASSWORD", "root"),
            database=os.environ.get("MYSQL_DATABASE", "sixgr_results"),
            connection_timeout=5,
        )
    except Exception:
        return set()
    try:
        cur = conn.cursor()
        cur.execute("SELECT logical_path FROM sim_artifacts WHERE run_id=%s", (int(run_id),))
        return {str(row[0] or "") for row in cur.fetchall()}
    finally:
        conn.close()


def latest_run_id(opener: urllib.request.OpenerDirector, base_url: str, run_tag: str | None) -> int:
    params = {"limit": "20"}
    if run_tag:
        params["run_tag"] = run_tag
    url = f"{base_url.rstrip('/')}/api/runs?{urllib.parse.urlencode(params)}"
    payload = fetch_json(opener, url)
    runs = payload.get("runs") or []
    if not runs:
        raise AssertionError(f"No run rows found through {url}")
    return int(runs[0]["run_id"])


def validate_payload(payload: dict[str, Any], *, strict: bool, db_logical_paths: set[str] | None = None) -> list[str]:
    failures: list[str] = []
    run = payload.get("run") or {}
    counts = payload.get("counts") or {}
    tables = payload.get("tables_all") or []
    images = payload.get("images_all") or []
    debug = payload.get("debug") or {}
    runtime = payload.get("runtime_context") or {}
    coverage = payload.get("output_coverage") or {}

    logical_paths = {str(item.get("logical_path") or "") for item in tables + images}
    logical_paths.update(db_logical_paths or set())
    scenario_id = str(run.get("scenario_id") or "")
    if scenario_id != "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame":
        failures.append(f"scenario_id mismatch: {scenario_id}")
    if strict and str(run.get("status_text") or "").lower() != "completed":
        failures.append(f"run status is not completed: {run.get('status_text')}")
    if strict and run.get("result_ok") is not True:
        failures.append(f"result_ok is not true: {run.get('result_ok')}")
    if int(run.get("required_failure_count") or 0) != 0:
        failures.append(f"required_failure_count is nonzero: {run.get('required_failure_count')}")
    if int(counts.get("artifacts_total") or 0) <= 0:
        failures.append("no artifacts are visible through the browser API")
    if int(counts.get("tables_total") or 0) <= 0:
        failures.append("no table artifacts are visible through the browser API")
    if int(counts.get("logs_total") or 0) <= 0:
        failures.append("no live logs are visible through the browser API")
    missing = sorted(path for path in REQUIRED_ARTIFACTS if path not in logical_paths)
    if missing:
        failures.append("missing required canonical artifacts: " + ", ".join(missing))
    if strict and debug.get("runtime_truth_contract_ok") is False:
        failures.append("runtime truth contract is false")
    if strict and int(debug.get("strict_truth_failure_count") or 0) != 0:
        failures.append(f"strict truth failures present: {debug.get('strict_truth_failure_count')}")

    operating_rows = runtime.get("operating_mode") if isinstance(runtime, dict) else []
    if strict and not operating_rows:
        failures.append("runtime operating mode rows are not visible")

    registry = coverage.get("registry") if isinstance(coverage, dict) else []
    if strict and not registry:
        failures.append("output coverage registry rows are not visible")

    for item in tables + images:
        path = str(item.get("logical_path") or "").lower()
        if "smoke" in path and strict:
            failures.append(f"smoke artifact exposed in strict run: {path}")
        if "placeholder" in path and strict:
            failures.append(f"placeholder artifact exposed in strict run: {path}")

    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate the locked 4 GHz / 100 MHz / 200 UE / 1 frame waveform-honest LLS run through browser APIs.")
    parser.add_argument("--base-url", default="")
    parser.add_argument("--run-id", type=int, default=0)
    parser.add_argument("--run-tag", default="")
    parser.add_argument("--username", default="admin")
    parser.add_argument("--password", default="admin")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    base_url = resolve_base_url(args.base_url)

    try:
        opener = login_opener(base_url, args.username, args.password)
        run_id = args.run_id or latest_run_id(opener, base_url, args.run_tag or None)
        payload = fetch_json(opener, f"{base_url.rstrip('/')}/api/run/{run_id}/live")
        failures = validate_payload(
            payload,
            strict=bool(args.strict),
            db_logical_paths=fetch_db_artifact_paths(run_id),
        )
    except (AssertionError, urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        print(f"validation_error: {exc}", file=sys.stderr)
        return 2

    print(json.dumps({
        "run_id": run_id,
        "status": (payload.get("run") or {}).get("status_text"),
        "result_ok": (payload.get("run") or {}).get("result_ok"),
        "required_failure_count": (payload.get("run") or {}).get("required_failure_count"),
        "artifact_count": (payload.get("counts") or {}).get("artifacts_total"),
        "table_count": (payload.get("counts") or {}).get("tables_total"),
        "image_count": (payload.get("counts") or {}).get("images_total"),
        "log_count": (payload.get("counts") or {}).get("logs_total"),
        "failures": failures,
    }, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
