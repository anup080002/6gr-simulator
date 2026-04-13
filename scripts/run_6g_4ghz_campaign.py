from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def load_overlay(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".json":
        payload = json.loads(text)
    else:
        payload = yaml.safe_load(text) or {}
    if not isinstance(payload, dict):
        raise ValueError(f"Overlay {path} must decode to a mapping.")
    return payload


def build_bounded_overlay() -> dict[str, Any]:
    return {
        "run_control": {
            "study_mode": "smoke",
            "run_profile": "quick",
            "num_seeds": 1,
            "num_drops": 1,
            "warmup_time_ms": 20,
            "measurement_time_ms": 50,
            "total_time_ms": 70,
            "slot_level_logging_enable": True,
            "symbol_level_logging_enable": False,
            "per_ue_logging_enable": True,
            "per_cell_logging_enable": True,
        },
        "simulation": {
            "n_frames": 1,
            "n_slots": 1,
            "n_subframes": 1,
            "monte_carlo_iterations": 1,
            "min_duration_s": 0.0005,
        },
        "traffic": {
            "targetRate_Mbps": 8,
            "fullBufferBitsPerTTI": 12000,
        },
    }


def wait_for_completion(run_tag: str, poll_s: float, timeout_s: float) -> int:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        runs = dash.fetch_runs(limit=200, run_tag=run_tag)
        if runs:
            row = runs[0]
            status = str(row.get("status_text") or "").strip().lower()
            print(
                json.dumps(
                    {
                        "run_id": row.get("run_id"),
                        "run_tag": row.get("run_tag"),
                        "scenario_id": row.get("scenario_id"),
                        "status_text": row.get("status_text"),
                        "updated_utc": row.get("updated_utc"),
                    },
                    indent=2,
                    default=str,
                )
            )
            if status in {"completed", "failed"}:
                return 0
        time.sleep(max(0.5, poll_s))
    print(f"Timed out waiting for run_tag={run_tag!r}", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Thin launcher for the 6G_4GHz_100MHz_19S3_100UE_UMa family using the existing browser/backend helpers."
    )
    parser.add_argument("--scenario", default="variants/SCN00_BASELINE_CAPACITY.yaml")
    parser.add_argument("--run-tag", default="")
    parser.add_argument("--overlay", type=Path, default=None, help="Optional YAML/JSON overlay merged into the resolved browser payload.")
    parser.add_argument("--bounded", action="store_true", help="Apply a small bounded overlay for quick browser-style validation.")
    parser.add_argument("--wait", action="store_true", help="Poll sim_runs until the launched run completes or fails.")
    parser.add_argument("--poll-seconds", type=float, default=10.0)
    parser.add_argument("--timeout-seconds", type=float, default=1800.0)
    args = parser.parse_args()

    payload, source_chain = dash.load_resolved_config_payload(args.scenario)
    merged = dash.merge_config_dict(payload, {})
    if args.overlay is not None:
        merged = dash.merge_config_dict(merged, load_overlay(args.overlay))
    if args.bounded:
        merged = dash.merge_config_dict(merged, build_bounded_overlay())
    merged = dash.canonicalize_browser_config_payload(merged, keep_legacy_aliases=False)

    run_tag = args.run_tag.strip() or dash.timestamp_tag("6g4ghz")
    yaml_text = yaml.safe_dump(merged, sort_keys=False, allow_unicode=False)
    launch_tag, log_file, runtime_path = dash.launch_run_from_yaml(args.scenario, yaml_text, run_tag)

    print(json.dumps(
        {
            "scenario": args.scenario,
            "run_tag": launch_tag,
            "runtime_yaml": str(runtime_path),
            "stdout_log": str(log_file),
            "source_chain": source_chain,
        },
        indent=2,
        default=str,
    ))

    if args.wait:
        return wait_for_completion(launch_tag, args.poll_seconds, args.timeout_seconds)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
