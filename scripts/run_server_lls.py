"""Launch ONE fresh LLS YAML on a frozen checkout; never launch testAll/retry."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SCENARIO = "simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml"


def utc():
    return datetime.now(timezone.utc).isoformat()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def literal(value):
    """MATLAB character literal, not shell interpolation."""
    return "'" + str(value).replace("'", "''") + "'"


def batch_command(scenario, results, tag, log_dir):
    return (
        f"cd({literal(ROOT)}); try; setup6GRSimToolkit('Verbose',true); "
        "env=struct('MATLABVersion',version,'Release',version('-release'),"
        "'Computer',computer,'Toolboxes',ver); "
        f"sixgr.util.jsonWrite({literal(log_dir / 'matlab_environment.json')},env); "
        f"cfg=sixgr.lls6g.config.loadScenarioConfig({literal(scenario)}); "
        "assert(strlength(string(cfg.get('run_control.runtime_checkpoint_resume_from','')))==0,"
        "'sixgr:server:FreshOnly','Use reviewed same-host checkpoint instructions for resume.'); "
        f"target=fullfile({literal(results)},'lls',char(cfg.ScenarioID),{literal(tag)}); "
        "assert(~isfolder(target),'sixgr:server:ExistingRun','Preserve existing run; use a new tag.'); "
        f"out=run_6g_phy_lls_single({literal(scenario)},{literal(results)},{literal(tag)}); "
        "result=struct('Ok',logical(out.Ok),'RunFolder',char(out.RunFolder),"
        "'Scope','scenario_acceptance_not_statistical_qualification'); "
        f"sixgr.util.jsonWrite({literal(log_dir / 'scenario_receipt.json')},result); "
        "fprintf('RUN_FOLDER=%s\\n',char(out.RunFolder)); "
        "assert(out.Ok,'sixgr:server:ScenarioFailed','Acceptance failed; preserve evidence.'); "
        "catch err; failure=struct('Identifier',err.identifier,"
        "'Report',getReport(err,'extended','hyperlinks','off')); "
        f"try; sixgr.util.jsonWrite({literal(log_dir / 'matlab_failure.json')},failure); "
        "catch writeErr; fprintf(2,'%s\\n',writeErr.message); end; rethrow(err); end;"
    )


def execute(args):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,95}", args.tag):
        raise ValueError("Use a new simple run tag (letters, digits, underscore, hyphen; max 96).")
    scenario = (ROOT / args.scenario).resolve(strict=True)
    scenario.relative_to(ROOT)
    if scenario.suffix.lower() not in {".yaml", ".yml"}:
        raise ValueError("Scenario must be a YAML in this checkout.")
    git("ls-files", "--error-unmatch", scenario.relative_to(ROOT).as_posix())
    revision = git("rev-parse", "HEAD")
    status = git("status", "--porcelain=v1", "--untracked-files=normal")
    results = (ROOT / args.results).resolve()
    log_dir = ROOT / "logs" / "server" / args.tag
    matlab = shutil.which(args.matlab)
    if not matlab:
        raise ValueError("MATLAB executable not found; supply --matlab with its full path.")
    command = [matlab, "-wait", "-logfile", str(log_dir / "matlab.log"), "-batch",
               batch_command(scenario, results, args.tag, log_dir)]
    metadata = dict(schema="SixGRServerLaunch/v1", status="planned", started_utc=utc(),
                    git_commit=revision, git_status_before=status, repository=str(ROOT),
                    scenario=str(scenario), scenario_sha256=hashlib.sha256(scenario.read_bytes()).hexdigest(),
                    results_root=str(results), log_directory=str(log_dir), run_tag=args.tag,
                    python=sys.executable, python_version=sys.version, os=platform.platform(),
                    output_backend="filesystem", command=command,
                    scope="fresh_single_lls_not_testall_not_statistical_qualification")
    if args.plan:
        metadata["launch_allowed"] = not status and not log_dir.exists()
        print(json.dumps(metadata, indent=2))
        return 0
    if status:
        raise ValueError("Checkout is dirty. Commit/review changes before launch; no MATLAB started.")
    # Check the plotting/YAML environment before starting expensive PHY work.
    subprocess.run([sys.executable, "-c", "import yaml,resvg_py; from PIL import Image"], check=True)
    log_dir.mkdir(parents=True, exist_ok=False)
    results.mkdir(parents=True, exist_ok=True)
    metadata["results_free_bytes_before"] = shutil.disk_usage(results).free
    metadata["status"] = "running"
    receipt_path = log_dir / "launcher.json"

    def persist():
        temporary = receipt_path.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        temporary.replace(receipt_path)

    persist()
    print(f"Revision: {revision}\nLogs: {log_dir}\nResults root: {results}", flush=True)
    environment = os.environ.copy()
    environment.update(SIXGR_OUTPUT_BACKEND_OVERRIDE="filesystem",
                       SIXGR_WEBGUI_PYTHON=sys.executable, PYTHON_EXE=sys.executable)
    exit_code = 1
    try:
        # No shell, detached process, automatic retry, threshold override or testAll.
        completed = subprocess.run(command, cwd=ROOT, env=environment)
        metadata["matlab_exit_code"] = completed.returncode
        metadata["git_commit_after"] = git("rev-parse", "HEAD")
        metadata["git_status_after"] = git("status", "--porcelain=v1", "--untracked-files=normal")
        metadata["source_unchanged"] = (metadata["git_commit_after"] == revision and
                                         metadata["git_status_after"] == status)
        result_path = log_dir / "scenario_receipt.json"
        result = json.loads(result_path.read_text(encoding="utf-8-sig")) if result_path.exists() else {}
        metadata["scenario_receipt"] = result
        passed = completed.returncode == 0 and result.get("Ok") is True and metadata["source_unchanged"]
        metadata["status"] = "scenario_passed" if passed else "failed_or_incomplete"
        exit_code = 0 if passed else 1
    except KeyboardInterrupt:
        metadata["status"] = "interrupted_process_state_must_be_checked"
        exit_code = 130
    except Exception as error:
        metadata["status"] = "failed_or_incomplete"
        metadata["launcher_error"] = str(error)
    finally:
        metadata["finished_utc"] = utc()
        metadata["launcher_exit_code"] = exit_code
        persist()
        print(f"Status: {metadata['status']} | receipt: {receipt_path}", flush=True)
    return exit_code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matlab", required=True)
    parser.add_argument("--scenario", default=DEFAULT_SCENARIO)
    parser.add_argument("--results", default="results")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--plan", action="store_true", help="Print command; do not start MATLAB or write files.")
    args = parser.parse_args()
    try:
        return execute(args)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"No scenario launched: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
