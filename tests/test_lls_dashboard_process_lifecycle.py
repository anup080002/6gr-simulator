from __future__ import annotations

import json
import sys
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def _write_pid_record(
    run_tag: str,
    *,
    pid: int,
    runtime_yaml: str,
) -> Path:
    pid_path = dash.runtime_pid_file(run_tag)
    assert pid_path is not None
    pid_path.parent.mkdir(parents=True, exist_ok=True)
    pid_path.write_text(
        json.dumps(
            {
                "pid": pid,
                "run_tag": run_tag,
                "runtime_yaml": runtime_yaml,
            }
        ),
        encoding="utf-8",
    )
    return pid_path


def _matching_matlab_command(run_tag: str, runtime_yaml: str) -> str:
    return (
        r'"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -batch '
        f'"run_6g_phy_lls_single('
        f"'simulator/configs/scenarios/{runtime_yaml}','results','{run_tag}');"
        '"'
    )


@pytest.fixture
def isolated_process_registry(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> dict[str, Any]:
    active_processes: dict[str, Any] = {}
    monkeypatch.setattr(dash, "RUNTIME_LOG_DIR", tmp_path)
    monkeypatch.setattr(dash, "ACTIVE_DASHBOARD_PROCESSES", active_processes)
    return active_processes


def test_pid_reuse_requires_matching_matlab_command_identity(
    monkeypatch: pytest.MonkeyPatch,
    isolated_process_registry: dict[str, Any],
) -> None:
    run_tag = "run_alpha_42"
    runtime_yaml = "__web_runtime_run_alpha_42.yaml"
    pid = 424242
    _write_pid_record(run_tag, pid=pid, runtime_yaml=runtime_yaml)

    observed_pids: list[int] = []
    current_command = {"value": ""}

    def fake_command_line(candidate_pid: int) -> str:
        observed_pids.append(candidate_pid)
        return current_command["value"]

    monkeypatch.setattr(dash, "process_command_line_for_pid", fake_command_line)

    invalid_reused_commands = [
        # Matching metadata is insufficient when the reused PID is not MATLAB.
        f'python.exe worker.py --run-tag {run_tag} --config {runtime_yaml}',
        # A MATLAB PID owned by another dashboard run must also be rejected.
        _matching_matlab_command(
            "different_run",
            "__web_runtime_different_run.yaml",
        ),
    ]
    for command_line in invalid_reused_commands:
        current_command["value"] = command_line
        assert dash.dashboard_run_process_active(run_tag) is False

    current_command["value"] = _matching_matlab_command(run_tag, runtime_yaml)
    assert dash.dashboard_run_process_active(run_tag) is True
    assert observed_pids == [pid, pid, pid]


def test_browser_runtime_config_disables_automatic_parallel_pool(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        dash,
        "dashboard_mysql_available",
        lambda: (False, "not needed for this test"),
    )
    source = {
        "canonical_control": {
            "run": {
                "num_workers": 24,
                "batch_size_links": 24,
                "auto_start_parallel_pool": True,
            }
        },
        "run_control": {
            "execution_mode": "LLS",
            "num_workers": 24,
            "batch_size_links": 24,
            "auto_start_parallel_pool": True,
        },
        "run": {
            "num_workers": 24,
            "numWorkers": 24,
            "useParallel": True,
        },
        "output": {"persistence_mode": "results_folder"},
    }

    runtime = json.loads(dash.normalize_run_yaml(json.dumps(source)))

    assert runtime["run_control"]["num_workers"] == 1
    assert runtime["run_control"]["batch_size_links"] == 1
    assert runtime["run_control"]["auto_start_parallel_pool"] is False
    assert runtime["canonical_control"]["run"]["num_workers"] == 1
    assert runtime["canonical_control"]["run"]["batch_size_links"] == 1
    assert runtime["canonical_control"]["run"]["auto_start_parallel_pool"] is False
    assert runtime["run"]["num_workers"] == 1
    assert runtime["run"]["numWorkers"] == 1
    assert runtime["run"]["useParallel"] is False


def test_browser_matlab_child_activates_webgui_database_contract(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    repo_root = tmp_path / "repo"
    scenario_dir = repo_root / "simulator" / "configs" / "scenarios"
    scenario_dir.mkdir(parents=True)
    scenario_path = scenario_dir / "demo.yaml"
    scenario_path.write_text("{}\n", encoding="utf-8")
    matlab_exe = tmp_path / "matlab.exe"
    matlab_exe.write_bytes(b"")
    runtime_logs = repo_root / "tmp_web_runs"

    captured: dict[str, Any] = {}

    class FakeProcess:
        pid = 828282

    def fake_popen(command: list[str], **kwargs: Any) -> FakeProcess:
        captured["command"] = command
        captured["kwargs"] = kwargs
        return FakeProcess()

    monkeypatch.setattr(dash, "REPO_ROOT", repo_root)
    monkeypatch.setattr(dash, "RUNTIME_LOG_DIR", runtime_logs)
    monkeypatch.setattr(dash, "MATLAB_EXE", matlab_exe)
    monkeypatch.setattr(dash, "resolve_scenario_path", lambda _name: scenario_path)
    monkeypatch.setattr(dash, "dashboard_run_process_active", lambda _tag: False)
    monkeypatch.setattr(dash, "cleanup_runtime_yaml", lambda _folder: None)
    monkeypatch.setattr(dash, "normalize_run_yaml", lambda _text, _name=None: "{}")
    monkeypatch.setattr(dash.subprocess, "Popen", fake_popen)
    monkeypatch.setattr(dash, "ACTIVE_DASHBOARD_PROCESSES", {})

    dash._launch_run_from_yaml_locked("demo.yaml", "{}", "webgui_env_contract")

    child_env = captured["kwargs"]["env"]
    assert child_env["SIXGR_WEBGUI_RUN"] == "1"
    assert child_env["MYSQL_HOST"] == dash.MYSQL_HOST
    assert child_env["MYSQL_PORT"] == str(dash.MYSQL_PORT)
    assert child_env["MYSQL_DATABASE"] == dash.MYSQL_DATABASE


def test_terminate_dashboard_run_refuses_unverified_process(
    monkeypatch: pytest.MonkeyPatch,
    isolated_process_registry: dict[str, Any],
) -> None:
    run_tag = "unverified_run"
    pid_path = _write_pid_record(
        run_tag,
        pid=515151,
        runtime_yaml="__web_runtime_unverified_run.yaml",
    )
    isolated_process_registry[run_tag] = object()

    monkeypatch.setattr(
        dash,
        "process_command_line_for_pid",
        lambda _pid: "python.exe unrelated_worker.py",
    )
    stop_attempts: list[Any] = []

    def refuse_stop(*args: Any, **kwargs: Any) -> Any:
        stop_attempts.append((args, kwargs))
        raise AssertionError("An unverified process must never be terminated.")

    monkeypatch.setattr(dash.subprocess, "run", refuse_stop)
    monkeypatch.setattr(
        dash,
        "os",
        SimpleNamespace(name="posix", kill=refuse_stop),
    )

    with pytest.raises(ValueError, match="no longer active"):
        dash.terminate_dashboard_run(run_tag)

    assert stop_attempts == []
    assert not pid_path.exists()
    assert run_tag not in isolated_process_registry


def test_verified_windows_stop_uses_exact_taskkill_and_removes_only_target_record(
    monkeypatch: pytest.MonkeyPatch,
    isolated_process_registry: dict[str, Any],
) -> None:
    run_tag = "verified_run"
    runtime_yaml = "__web_runtime_verified_run.yaml"
    pid = 616161
    target_pid_path = _write_pid_record(
        run_tag,
        pid=pid,
        runtime_yaml=runtime_yaml,
    )
    other_run_tag = "other_run"
    other_pid_path = _write_pid_record(
        other_run_tag,
        pid=717171,
        runtime_yaml="__web_runtime_other_run.yaml",
    )
    other_record_before = other_pid_path.read_bytes()
    target_log = dash.RUNTIME_LOG_DIR / f"{run_tag}.log"
    target_log.write_text("preserve this log", encoding="utf-8")

    target_process = object()
    other_process = object()
    isolated_process_registry.update(
        {
            run_tag: target_process,
            other_run_tag: other_process,
        }
    )

    verified_pids: list[int] = []

    def verified_command_line(candidate_pid: int) -> str:
        verified_pids.append(candidate_pid)
        return _matching_matlab_command(run_tag, runtime_yaml)

    monkeypatch.setattr(dash, "process_command_line_for_pid", verified_command_line)
    monkeypatch.setattr(
        dash,
        "os",
        SimpleNamespace(
            name="nt",
            kill=lambda *_args, **_kwargs: pytest.fail(
                "The Windows branch must use taskkill, not os.kill."
            ),
        ),
    )

    taskkill_calls: list[tuple[list[str], dict[str, Any]]] = []

    def fake_subprocess_run(
        command: list[str],
        **kwargs: Any,
    ) -> SimpleNamespace:
        taskkill_calls.append((command, kwargs))
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(dash.subprocess, "run", fake_subprocess_run)

    assert dash.terminate_dashboard_run(run_tag) == pid
    assert verified_pids == [pid]
    assert taskkill_calls == [
        (
            ["taskkill", "/PID", str(pid), "/T", "/F"],
            {
                "capture_output": True,
                "text": True,
                "timeout": 20,
                "check": False,
            },
        )
    ]
    assert not target_pid_path.exists()
    assert target_log.read_text(encoding="utf-8") == "preserve this log"
    assert other_pid_path.read_bytes() == other_record_before
    assert run_tag not in isolated_process_registry
    assert isolated_process_registry[other_run_tag] is other_process
