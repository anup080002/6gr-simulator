"""Server handoff orchestration tests; mock MATLAB, never execute a scenario."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import zipfile

import pytest

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / (name + ".py"))
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


launch = module("run_server_lls")
collect = module("collect_server_evidence")


@pytest.fixture
def launcher(tmp_path, monkeypatch):
    root = tmp_path / "repo with space"
    root.mkdir()
    (root / "case.yaml").write_text("meta: {scenario_id: fixture}\n", encoding="utf-8")
    monkeypatch.setattr(launch, "ROOT", root)
    state = {"dirty": "", "commit": "a" * 40}

    def git(*args):
        if args[0] == "status":
            return state["dirty"]
        if args[0] == "rev-parse":
            return state["commit"]
        return "case.yaml"

    monkeypatch.setattr(launch, "git", git)
    monkeypatch.setattr(launch.shutil, "which", lambda _: "C:/Program Files/MATLAB/bin/matlab.exe")
    calls = []

    def run(command, **kwargs):
        calls.append((command, kwargs))
        return subprocess.CompletedProcess(command, 0)

    monkeypatch.setattr(launch.subprocess, "run", run)
    args = argparse.Namespace(tag="server_01", scenario="case.yaml", results="results", matlab="matlab", plan=False)
    return root, args, state, calls


def test_plan_is_read_only_even_on_dirty_checkout(launcher):
    root, args, state, calls = launcher
    args.plan = True
    state["dirty"] = " M core.m"
    assert launch.execute(args) == 0
    assert not calls and not (root / "logs").exists() and not (root / "results").exists()


def test_dirty_checkout_does_not_launch(launcher):
    root, args, state, calls = launcher
    state["dirty"] = " M core.m"
    with pytest.raises(ValueError, match="dirty"):
        launch.execute(args)
    assert not calls and not (root / "logs").exists()


@pytest.mark.parametrize("tag", ["../old", "bad;quit", "tag with spaces", ""])
def test_invalid_tags_fail_before_execution(launcher, tag):
    _, args, _, calls = launcher
    args.tag = tag
    with pytest.raises(ValueError):
        launch.execute(args)
    assert not calls


@pytest.mark.parametrize("ok,returncode,change,expected", [
    (True, 0, False, "scenario_passed"),
    (False, 0, False, "failed_or_incomplete"),
    (True, 1, False, "failed_or_incomplete"),
    (None, 0, False, "failed_or_incomplete"),
    (True, 0, True, "failed_or_incomplete"),
])
def test_terminal_pass_requires_receipt_exit_and_frozen_source(launcher, monkeypatch, ok, returncode, change, expected):
    root, args, state, _ = launcher
    log = root / "logs/server/server_01"

    def run(command, **kwargs):
        if "-batch" in command:
            assert kwargs["cwd"] == root and kwargs["env"]["SIXGR_OUTPUT_BACKEND_OVERRIDE"] == "filesystem"
            assert "shell" not in kwargs and "-wait" in command
            if ok is not None:
                (log / "scenario_receipt.json").write_text(json.dumps({"Ok": ok, "RunFolder": "fixture"}), encoding="utf-8")
            if change:
                state["dirty"] = " M core.m"
            return subprocess.CompletedProcess(command, returncode)
        return subprocess.CompletedProcess(command, 0)

    monkeypatch.setattr(launch.subprocess, "run", run)
    assert launch.execute(args) == (0 if expected == "scenario_passed" else 1)
    saved = json.loads((log / "launcher.json").read_text())
    assert saved["status"] == expected and saved["scenario_sha256"]
    assert saved["scope"].startswith("fresh_single_lls_not_testall")


def test_existing_attempt_is_preserved(launcher):
    root, args, _, calls = launcher
    log = root / "logs/server/server_01"
    log.mkdir(parents=True)
    receipt = log / "launcher.json"
    receipt.write_text("original", encoding="utf-8")
    with pytest.raises(FileExistsError):
        launch.execute(args)
    assert receipt.read_text() == "original"
    assert all("-batch" not in command for command, _ in calls)


def test_batch_has_freshness_checks_and_literal_quoting(tmp_path):
    command = launch.batch_command("scenario's.yaml", tmp_path, "run01", tmp_path)
    assert "scenario''s.yaml" in command
    assert "runtime_checkpoint_resume_from" in command
    assert "assert(~isfolder(target)" in command
    assert command.index("assert(~isfolder(target)") < command.index("out=run_6g_phy_lls_single")
    assert "assert(out.Ok" in command and "rethrow(err)" in command


def evidence_tree(tmp_path):
    run, logs = tmp_path / "run", tmp_path / "logs"
    (run / "meta").mkdir(parents=True)
    (run / "air_interface/csv").mkdir(parents=True)
    logs.mkdir()
    (run / "meta/config.json").write_bytes(b'{"scenario":"fixture"}\r\n')
    (run / "air_interface/csv/trials.csv").write_bytes(b"Slot,CRC\r\n45,0\r\n")
    (run / "raw.mat").write_bytes(b"retained only at source")
    (run / "large.csv").write_bytes(b"x" * 500)
    (run / ".env.auth").write_bytes(b"password=fixture-do-not-copy")
    (logs / "matlab.log").write_bytes(b"test-fixture failure\r\n")
    return run, logs


def test_package_preserves_exact_bytes_and_explicit_omissions(tmp_path):
    run, logs = evidence_tree(tmp_path)
    output = tmp_path / "evidence.zip"
    original = {str(p): p.read_bytes() for p in run.rglob("*") if p.is_file()}
    manifest = collect.package(run, [logs], output, 100, 2000)
    assert manifest["included_count"] == 3 and manifest["omitted_count"] == 3
    rows = {r["path"]: r for r in manifest["files"]}
    assert rows["run/large.csv"]["reason"] == "per_file_limit"
    assert rows["run/raw.mat"]["reason"] == "binary_or_non_diagnostic_extension"
    assert rows["run/.env.auth"]["reason"] == "private_configuration_excluded"
    with zipfile.ZipFile(output) as archive:
        for name, row in rows.items():
            if row["status"] == "included":
                raw = archive.read(name)
                assert raw == Path(row["source"]).read_bytes()
                assert hashlib.sha256(raw).hexdigest() == row["sha256"]
        assert json.loads(archive.read("manifest.json"))["scope"].endswith("not_resumable_checkpoint")
    assert hashlib.sha256(output.read_bytes()).hexdigest() == output.with_suffix(".zip.sha256").read_text().strip()
    assert all(Path(path).read_bytes() == raw for path, raw in original.items())


def test_total_limit_never_truncates_a_file(tmp_path):
    run, logs = evidence_tree(tmp_path)
    result = collect.package(run, [logs], tmp_path / "small.zip", 1000, 32)
    assert result["included_bytes"] <= 32
    assert any(r["reason"] == "total_limit" for r in result["files"])


def test_package_refuses_source_destination_and_existing_zip(tmp_path):
    run, logs = evidence_tree(tmp_path)
    with pytest.raises(ValueError, match="outside"):
        collect.package(run, [logs], run / "evidence.zip", 100, 1000)
    output = tmp_path / "preserve.zip"
    output.write_bytes(b"original")
    with pytest.raises(FileExistsError):
        collect.package(run, [logs], output, 100, 1000)
    assert output.read_bytes() == b"original"


def test_reparse_directory_is_not_followed(tmp_path, monkeypatch):
    run, logs = evidence_tree(tmp_path)
    archive = run / "channel/mat"
    archive.mkdir(parents=True)
    (archive / "channel.csv").write_text("must not enter junction", encoding="utf-8")
    real = collect.linked
    monkeypatch.setattr(collect, "linked", lambda path: path == archive or real(path))
    result = collect.package(run, [logs], tmp_path / "links.zip", 100, 2000)
    assert any(r["path"] == "run/channel/mat" and r["reason"] == "linked_directory_not_copied" for r in result["files"])
    assert not any(r["path"].endswith("channel.csv") for r in result["files"])


def test_modifying_source_aborts_package_without_complete_manifest(tmp_path, monkeypatch):
    run, logs = evidence_tree(tmp_path)
    source = run / "air_interface/csv/trials.csv"
    real_open = Path.open

    def opening(path, mode="r", *args, **kwargs):
        if path == source and mode == "rb":
            with real_open(path, "ab") as stream:
                stream.write(b"changed\n")
        return real_open(path, mode, *args, **kwargs)

    monkeypatch.setattr(Path, "open", opening)
    output = tmp_path / "changed.zip"
    with pytest.raises(ValueError, match="changed"):
        collect.package(run, [logs], output, 100, 2000)
    assert not output.with_suffix(".zip.sha256").exists()
    with zipfile.ZipFile(output) as archive:
        assert "manifest.json" not in archive.namelist()
