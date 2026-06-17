#!/usr/bin/env python3
"""Run the actual mobile-2UE full-PHY study through isolated MATLAB sessions.

This runner exists to satisfy the run-first workflow for the mobile 2UE study:
1. Validate the authoritative YAML matches the requested full-run arguments.
2. Create a short inherited smoke config from the same YAML.
3. Run the smoke attempt.
4. Run the full 400-slot attempt.
5. Persist crash-aware logs and a machine-readable runner summary.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml


SUMMARY_START = "__CODEX_SUMMARY_START__"
SUMMARY_END = "__CODEX_SUMMARY_END__"
CRASH_PATTERNS = (
    "access violation",
    "segmentation violation",
    "segmentation fault",
    "fatal error",
)


@dataclass
class AttemptResult:
    name: str
    ok: bool
    return_code: int
    timed_out: bool
    crashed: bool
    config_path: str
    matlab_output_root: str
    requested_output_root: str
    repo_run_folder: str
    visible_run_folder: str
    batch_command: str
    matlab_command: list[str]
    stdout_log: str
    summary: dict[str, Any]
    crash_dump: str
    started_utc: str
    ended_utc: str


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def matlab_exe() -> str:
    env_value = os.environ.get("MATLAB_EXE", "").strip()
    if env_value:
        return env_value
    default_r2024a = Path(r"C:\Program Files\MATLAB\R2024a\bin\matlab.exe")
    if default_r2024a.exists():
        return str(default_r2024a)
    return "matlab"


def matlab_flags() -> list[str]:
    raw = os.environ.get("MATLAB_FLAGS", "").strip()
    if raw:
        return shlex.split(raw, posix=False)
    return []


def parse_bool(raw: str | bool) -> bool:
    if isinstance(raw, bool):
        return raw
    token = str(raw).strip().lower()
    if token in {"1", "true", "yes", "on"}:
        return True
    if token in {"0", "false", "no", "off"}:
        return False
    raise argparse.ArgumentTypeError(f"Invalid boolean value: {raw!r}")


def matlab_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"Top-level YAML must be a mapping: {path}")
    return data


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def resolve_config_tree(path: Path, seen: set[Path] | None = None) -> dict[str, Any]:
    resolved_path = path.resolve()
    if seen is None:
        seen = set()
    if resolved_path in seen:
        raise ValueError(f"Recursive config inheritance detected at {resolved_path}")
    seen = set(seen)
    seen.add(resolved_path)

    raw = load_yaml(resolved_path)
    inherits = raw.pop("inherits", []) or []
    if isinstance(inherits, str):
        inherits = [inherits]

    merged: dict[str, Any] = {}
    for parent in inherits:
        parent_path = Path(parent)
        if not parent_path.is_absolute():
            parent_path = (resolved_path.parent / parent_path).resolve()
        merged = deep_merge(merged, resolve_config_tree(parent_path, seen))
    return deep_merge(merged, raw)


def nested_get(data: dict[str, Any], path: str, default: Any = None) -> Any:
    current: Any = data
    for key in path.split("."):
        if not isinstance(current, dict) or key not in current:
            return default
        current = current[key]
    return current


def scenario_id_from_config(data: dict[str, Any]) -> str:
    for candidate in (
        nested_get(data, "meta.scenario_id"),
        nested_get(data, "scenario.name"),
        nested_get(data, "scenario_id"),
    ):
        if candidate:
            return str(candidate)
    raise ValueError("Unable to resolve scenario_id from config YAML.")


def normalize_visible_output_root(raw: str) -> Path:
    token = raw.strip()
    if os.name == "nt" and token.replace("\\", "/") == "/results":
        return Path(r"C:\results")
    return Path(token).expanduser()


def repo_results_root() -> Path:
    return repo_root() / "results"


def runner_summary_path() -> Path:
    return repo_results_root() / "_runner_reports" / "actual_mobile_2ue_full_phy_study_runner_summary.json"


def ensure_visible_results_root(visible_root: Path, repo_root_results: Path) -> str:
    repo_root_results.mkdir(parents=True, exist_ok=True)
    if visible_root.resolve() == repo_root_results.resolve():
        return "direct"

    if visible_root.exists():
        try:
            if visible_root.resolve() == repo_root_results.resolve():
                return "direct"
        except OSError:
            pass
    else:
        if os.name == "nt":
            visible_root.parent.mkdir(parents=True, exist_ok=True)
            ps = (
                f"$target={powershell_literal(str(repo_root_results.resolve()))}; "
                f"$link={powershell_literal(str(visible_root))}; "
                "New-Item -ItemType Junction -Path $link -Target $target | Out-Null"
            )
            completed = subprocess.run(
                ["powershell", "-NoProfile", "-Command", ps],
                cwd=repo_root(),
                text=True,
                capture_output=True,
                check=False,
            )
            if completed.returncode == 0 and visible_root.exists():
                return "junction"

        visible_root.mkdir(parents=True, exist_ok=True)
        return "mirror"

    return "mirror"


def powershell_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def build_smoke_override(base_config: Path, full_cfg: dict[str, Any], slots: int) -> Path:
    scenario_id = scenario_id_from_config(full_cfg)
    resolved_cfg = resolve_config_tree(base_config)
    slot_duration_ms = float(nested_get(resolved_cfg, "frame_timing.slot_duration_ms", 0.5))
    total_time_ms = slot_duration_ms * float(slots)
    output_dir = repo_root() / "results" / "_runner_inputs"
    output_dir.mkdir(parents=True, exist_ok=True)
    smoke_path = output_dir / f"{scenario_id}_smoke_{utc_stamp()}.yaml"
    payload = deep_merge(resolved_cfg, {})
    payload.pop("inherits", None)
    meta = dict(payload.get("meta", {}))
    meta["scenario_id"] = scenario_id
    meta["description"] = "Auto-generated 5-slot smoke config resolved from the authoritative mobile study YAML."
    meta["source_reference"] = "tools/matlab/run_actual_mobile_2ue_full_phy_study.py"
    payload["meta"] = meta

    run_control = dict(payload.get("run_control", {}))
    for key in ("total_frames", "warmup_frames", "measurement_frames"):
        run_control.pop(key, None)
    run_control.update({
        "total_slots": int(slots),
        "warmup_slots": 0,
        "measurement_slots": int(slots),
        "checkpoint_every_slots": 1,
        "snapshot_every_slots": 1,
        "log_every_slots": 1,
        "warmup_time_ms": 0,
        "measurement_time_ms": total_time_ms,
        "total_time_ms": total_time_ms,
    })
    payload["run_control"] = run_control

    simulation = dict(payload.get("simulation", {}))
    simulation.update({
        "n_frames": 1,
        "n_slots": int(slots),
        "n_subframes": int(max(1, round(total_time_ms))),
        "min_duration_s": max(total_time_ms / 1000.0, 0.0025),
    })
    payload["simulation"] = simulation
    with smoke_path.open("w", encoding="utf-8", newline="\n") as handle:
        yaml.safe_dump(payload, handle, sort_keys=False)
    return smoke_path


def validate_full_run_request(cfg: dict[str, Any], args: argparse.Namespace) -> None:
    expected = {
        "run_control.total_slots": int(args.slots),
        "run_control.num_workers": int(args.workers),
        "run_control.seed": int(args.seed),
    }
    mismatches: list[str] = []
    for path, requested in expected.items():
        configured = nested_get(cfg, path, None)
        if configured is None:
            mismatches.append(f"{path} missing from config")
        elif int(configured) != requested:
            mismatches.append(f"{path}={configured} but CLI requested {requested}")
    if mismatches:
        raise ValueError("CLI/config mismatch:\n- " + "\n- ".join(mismatches))


def run_folder_for_tag(output_root: Path, scenario_id: str, run_tag: str) -> Path:
    return output_root / "lls" / scenario_id / run_tag


def batch_command_for_run(
    config_path: Path,
    matlab_output_root: str,
    run_tag: str,
    diary_path: Path,
    workers: int,
    auto_fix_safe_issues: bool,
) -> str:
    root_literal = matlab_literal(str(repo_root()))
    config_literal = matlab_literal(str(config_path.resolve()))
    output_literal = matlab_literal(matlab_output_root)
    run_tag_literal = matlab_literal(run_tag)
    diary_literal = matlab_literal(str(diary_path))
    auto_fix_literal = "true" if auto_fix_safe_issues else "false"
    return (
        f"cd({root_literal}); "
        "setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false); "
        "try, "
        f"summary = run_full_study({config_literal}, {output_literal}, {run_tag_literal}, "
        f"'DiaryPath', {diary_literal}, 'RequestedWorkers', {int(workers)}, "
        f"'AutoFixSafeIssues', {auto_fix_literal}); "
        f"disp('{SUMMARY_START}'); disp(jsonencode(summary)); disp('{SUMMARY_END}'); "
        "catch ME, disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end; exit(0);"
    )


def extract_summary_from_log(log_text: str) -> dict[str, Any]:
    start = log_text.rfind(SUMMARY_START)
    end = log_text.rfind(SUMMARY_END)
    if start == -1 or end == -1 or end <= start:
        return {}
    payload = log_text[start + len(SUMMARY_START):end].strip()
    if not payload:
        return {}
    try:
        return json.loads(payload)
    except json.JSONDecodeError:
        return {}


def mirror_run_folder(repo_run_folder: Path, visible_run_folder: Path) -> None:
    if not repo_run_folder.exists():
        return
    if visible_run_folder.exists():
        shutil.rmtree(visible_run_folder, ignore_errors=True)
    visible_run_folder.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(repo_run_folder, visible_run_folder)


def discover_latest_crash_dump(started_at: float) -> str:
    candidates: list[Path] = []
    for root in {
        Path(tempfile.gettempdir()),
        Path.home(),
        Path.home() / "AppData" / "Local" / "Temp",
    }:
        if not root.exists():
            continue
        for pattern in ("matlab_crash_dump.*", "java.log.*", "hs_err_pid*.log"):
            candidates.extend(root.glob(pattern))
    fresh = [
        path for path in candidates
        if path.is_file() and path.stat().st_mtime >= started_at - 5
    ]
    if not fresh:
        return ""
    fresh.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    return str(fresh[0])


def run_attempt(
    name: str,
    config_path: Path,
    requested_output_root: Path,
    visible_output_root: Path,
    matlab_output_root: str,
    scenario_id: str,
    run_tag: str,
    workers: int,
    auto_fix_safe_issues: bool,
    timeout_s: int,
    mirror_mode: bool,
) -> AttemptResult:
    log_dir = repo_root() / "reports" / "logs" / "actual_mobile_2ue"
    log_dir.mkdir(parents=True, exist_ok=True)
    stdout_log = log_dir / f"{utc_stamp()}_{name}_{run_tag}.log"
    diary_path = log_dir / f"{run_tag}_diary.tmp.log"
    batch = batch_command_for_run(
        config_path=config_path,
        matlab_output_root=matlab_output_root,
        run_tag=run_tag,
        diary_path=diary_path,
        workers=workers,
        auto_fix_safe_issues=auto_fix_safe_issues,
    )
    cmd = [matlab_exe(), *matlab_flags(), "-batch", batch]

    repo_run_folder = run_folder_for_tag(repo_results_root(), scenario_id, run_tag)
    visible_run_folder = run_folder_for_tag(visible_output_root, scenario_id, run_tag)

    started_dt = datetime.now(timezone.utc)
    started_ts = time.time()
    timed_out = False
    return_code = 0
    with stdout_log.open("w", encoding="utf-8", errors="replace") as handle:
        try:
            completed = subprocess.run(
                cmd,
                cwd=repo_root(),
                text=True,
                stdout=handle,
                stderr=subprocess.STDOUT,
                timeout=timeout_s,
                check=False,
            )
            return_code = int(completed.returncode)
        except subprocess.TimeoutExpired:
            timed_out = True
            return_code = 124
            handle.write("\nTIMEOUT: MATLAB run exceeded timeout.\n")

    log_text = stdout_log.read_text(encoding="utf-8", errors="replace")
    crashed = return_code in {3221225477, -1073741819} or any(
        pattern in log_text.lower() for pattern in CRASH_PATTERNS
    )
    summary = extract_summary_from_log(log_text)
    if mirror_mode:
        mirror_run_folder(repo_run_folder, visible_run_folder)
    crash_dump = discover_latest_crash_dump(started_ts) if crashed or timed_out else ""

    ended_dt = datetime.now(timezone.utc)
    ok = return_code == 0 and not timed_out and not crashed and bool(summary)
    return AttemptResult(
        name=name,
        ok=ok,
        return_code=return_code,
        timed_out=timed_out,
        crashed=crashed,
        config_path=str(config_path.resolve()),
        matlab_output_root=matlab_output_root,
        requested_output_root=str(requested_output_root),
        repo_run_folder=str(repo_run_folder),
        visible_run_folder=str(visible_run_folder),
        batch_command=batch,
        matlab_command=cmd,
        stdout_log=str(stdout_log),
        summary=summary,
        crash_dump=crash_dump,
        started_utc=started_dt.isoformat(),
        ended_utc=ended_dt.isoformat(),
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, help="Authoritative scenario YAML.")
    parser.add_argument("--output-root", required=True, help="User-visible results root, e.g. /results.")
    parser.add_argument("--workers", type=int, required=True)
    parser.add_argument("--slots", type=int, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--capture-level", default="exhaustive")
    parser.add_argument("--profile", type=parse_bool, required=True)
    parser.add_argument("--stage-timers", type=parse_bool, required=True)
    parser.add_argument("--readback-every-output", type=parse_bool, required=True)
    parser.add_argument("--read-every-csv", type=parse_bool, required=True)
    parser.add_argument("--detect-unused-processes", type=parse_bool, required=True)
    parser.add_argument("--detect-bypasses", type=parse_bool, required=True)
    parser.add_argument("--auto-fix-safe-issues", type=parse_bool, required=True)
    parser.add_argument("--rerun-after-fix", type=parse_bool, required=True)
    parser.add_argument("--strict", type=parse_bool, required=True)
    parser.add_argument("--smoke-slots", type=int, default=5)
    parser.add_argument("--smoke-timeout", type=int, default=1800)
    parser.add_argument("--full-timeout", type=int, default=21600)
    args = parser.parse_args(argv)

    config_path = (repo_root() / args.config).resolve() if not Path(args.config).is_absolute() else Path(args.config).resolve()
    if not config_path.exists():
        raise FileNotFoundError(f"Config YAML not found: {config_path}")

    cfg = load_yaml(config_path)
    validate_full_run_request(cfg, args)
    scenario_id = scenario_id_from_config(cfg)

    visible_output_root = normalize_visible_output_root(args.output_root)
    repo_output_root = repo_results_root()
    alias_mode = ensure_visible_results_root(visible_output_root, repo_output_root)
    mirror_mode = alias_mode == "mirror"

    smoke_cfg_path = build_smoke_override(config_path, cfg, int(args.smoke_slots))
    matlab_output_root = "results"
    full_tag = f"actual_mobile_2ue_full_{utc_stamp()}"
    smoke_tag = f"actual_mobile_2ue_smoke_{utc_stamp()}"

    smoke_result = run_attempt(
        name="smoke",
        config_path=smoke_cfg_path,
        requested_output_root=visible_output_root,
        visible_output_root=visible_output_root,
        matlab_output_root=matlab_output_root,
        scenario_id=scenario_id,
        run_tag=smoke_tag,
        workers=int(args.workers),
        auto_fix_safe_issues=bool(args.auto_fix_safe_issues),
        timeout_s=int(args.smoke_timeout),
        mirror_mode=mirror_mode,
    )
    full_result: AttemptResult | None = None
    if smoke_result.ok:
        full_result = run_attempt(
            name="full",
            config_path=config_path,
            requested_output_root=visible_output_root,
            visible_output_root=visible_output_root,
            matlab_output_root=matlab_output_root,
            scenario_id=scenario_id,
            run_tag=full_tag,
            workers=int(args.workers),
            auto_fix_safe_issues=bool(args.auto_fix_safe_issues),
            timeout_s=int(args.full_timeout),
            mirror_mode=mirror_mode,
        )

    summary = {
        "requested_command": " ".join(shlex.quote(part) for part in [sys.executable, *argv]),
        "config_path": str(config_path),
        "scenario_id": scenario_id,
        "requested_output_root": str(visible_output_root),
        "repo_output_root": str(repo_output_root),
        "alias_mode": alias_mode,
        "matlab_output_root": matlab_output_root,
        "smoke_config_path": str(smoke_cfg_path),
        "smoke": asdict(smoke_result),
        "full": asdict(full_result) if full_result is not None else None,
    }

    summary_path = runner_summary_path()
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))

    full_ok = full_result is not None and full_result.ok
    return 0 if smoke_result.ok and full_ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
