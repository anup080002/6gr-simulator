"""Exact persisted download contract; no MATLAB, database or server execution."""
from __future__ import annotations

import hashlib
import inspect
import json
import sys
from functools import lru_cache
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as dash


@pytest.fixture
def saved_run(monkeypatch):
    # Declared producer-shaped snapshots, not a claim of executed PHY.
    raw_yaml = b'# original bytes\r\nmeta:\r\n  scenario_id: "fixture"\r\nvalue: 1.0e-06\r\n'
    raw_json = b'{"meta":{"scenario_id":"fixture"},"value":1e-6}\n'
    identity = {
        "SchemaVersion": "sixgr_resolved_config_identity/v1",
        "ScenarioID": "fixture", "ConfigHash": "declared-not-executed",
        "ResolvedJSONSHA256": hashlib.sha256(raw_json).hexdigest(),
        "ResolvedYAMLSHA256": hashlib.sha256(raw_yaml).hexdigest(),
        "RuntimeViewJSONSHA256": "", "RuntimeViewYAMLSHA256": "",
    }
    blobs = {1: json.dumps(identity).encode(), 2: raw_yaml, 3: raw_json}
    paths = ["meta/scenario_config_identity.json", "meta/scenario_config_resolved.yaml",
             "meta/scenario_config_resolved.json"]
    artifacts = [{"artifact_id": i, "run_id": 41, "logical_path": path,
                  "byte_size": len(blobs[i])} for i, path in enumerate(paths, 1)]
    run = {"run_id": 41, "run_tag": "retained", "config_json": "{}"}
    monkeypatch.setattr(dash, "fetch_run", lambda run_id: run if run_id == 41 else None)
    monkeypatch.setattr(dash, "fetch_artifacts", lambda run_id: artifacts)
    monkeypatch.setattr(dash, "merge_db_and_filesystem_artifacts", lambda rows, _: rows)
    monkeypatch.setattr(dash, "fetch_artifact_bytes", lambda artifact_id: blobs[artifact_id])

    def forbidden(*args, **kwargs):
        raise AssertionError("Must not regenerate a persisted input from source/draft")

    monkeypatch.setattr(dash, "load_resolved_config_payload", forbidden)
    monkeypatch.setattr(dash, "parse_config_json", forbidden)
    return blobs, artifacts, identity


@pytest.mark.parametrize("fmt,index", [("yaml", 2), ("json", 3)])
def test_returns_exact_saved_bytes_not_wrapper(saved_run, fmt, index):
    blobs, _, _ = saved_run
    before = {key: hashlib.sha256(value).hexdigest() for key, value in blobs.items()}
    content, mime, filename = dash.build_run_resolved_input_download(41, fmt)
    assert content == blobs[index]
    assert filename == f"retained_resolved_input.{fmt}"
    assert mime == ("text/yaml; charset=utf-8" if fmt == "yaml" else "application/json; charset=utf-8")
    assert {key: hashlib.sha256(value).hexdigest() for key, value in blobs.items()} == before


@pytest.mark.parametrize("index", [1, 2, 3])
def test_missing_original_artifact_rejected(saved_run, index):
    _, artifacts, _ = saved_run
    artifacts[:] = [row for row in artifacts if row["artifact_id"] != index]
    with pytest.raises(ValueError, match="unavailable"):
        dash.build_run_resolved_input_download(41, "json" if index == 3 else "yaml")


@pytest.mark.parametrize("index,fmt", [(2, "yaml"), (3, "json")])
def test_changed_original_bytes_rejected(saved_run, index, fmt):
    blobs, _, _ = saved_run
    blobs[index] += b" "
    with pytest.raises(ValueError, match="SHA256 mismatch"):
        dash.build_run_resolved_input_download(41, fmt)


@pytest.mark.parametrize("field,value", [
    ("SchemaVersion", "unknown"), ("ResolvedYAMLSHA256", ""),
    ("ResolvedYAMLSHA256", 1), ("ResolvedYAMLSHA256", "z" * 64),
])
def test_invalid_identity_rejected(saved_run, field, value):
    blobs, _, identity = saved_run
    identity[field] = value
    blobs[1] = json.dumps(identity).encode()
    with pytest.raises(ValueError):
        dash.build_run_resolved_input_download(41, "yaml")


@pytest.mark.parametrize("index", [1, 2])
def test_empty_artifact_rejected(saved_run, index):
    blobs, _, _ = saved_run
    blobs[index] = b""
    with pytest.raises(ValueError, match="empty"):
        dash.build_run_resolved_input_download(41, "yaml")


def test_wrong_run_artifact_rejected(saved_run):
    _, artifacts, _ = saved_run
    artifacts[1]["run_id"] = 42
    with pytest.raises(ValueError, match="different run"):
        dash.build_run_resolved_input_download(41, "yaml")


def test_corruption_cannot_hide_in_preview_cache(saved_run, monkeypatch):
    blobs, _, _ = saved_run

    @lru_cache(maxsize=3)
    def cached_bytes(artifact_id):
        return blobs[artifact_id]

    assert cached_bytes(2) == blobs[2]
    monkeypatch.setattr(dash, "fetch_artifact_bytes", cached_bytes)
    blobs[2] += b"changed since preview"
    with pytest.raises(ValueError, match="SHA256 mismatch"):
        dash.build_run_resolved_input_download(41, "yaml")


def test_invalid_format_and_missing_run(saved_run):
    with pytest.raises(ValueError, match="format"):
        dash.build_run_resolved_input_download(41, "zip")
    with pytest.raises(KeyError, match="not found"):
        dash.build_run_resolved_input_download(42, "yaml")


def test_catalog_source_keeps_original_inheritance(monkeypatch):
    source = 'inherits: ["./original_parent.yaml"]\nmeta:\n  scenario_id: child\n'
    monkeypatch.setattr(dash, "load_scenario_text", lambda _: source)
    result, _, filename = dash.build_scenario_download("child.yaml", "yaml")
    assert result == source.encode() and filename == "child.yaml"


def test_route_and_labels_keep_evidence_separate():
    # Static routing/label guard only; no browser/server or replay claim.
    source = inspect.getsource(dash)
    assert 'if parsed.path == "/run-config/resolved-input":' in source
    assert "build_run_resolved_input_download(" in source
    assert ">Download executed config</a>" not in source
    assert "Download original resolved input YAML" in source
    assert "Download config evidence YAML" in source
    assert "audit wrapper, not a runnable scenario" in source
    assert "Source YAML (inheritance required)" in source


def test_actual_filesystem_artifact_download_and_mutation(tmp_path, monkeypatch):
    """Real filesystem registry/byte reader, with only run discovery isolated."""
    meta = tmp_path / "meta"
    meta.mkdir()
    original = b'# preserved CRLF\r\nmeta:\r\n  scenario_id: fixture\r\n'
    yaml_path = meta / "scenario_config_resolved.yaml"
    yaml_path.write_bytes(original)
    (meta / "alternate_source.yml").write_bytes(b"inherits: [original.yaml]\n")
    identity_path = meta / "scenario_config_identity.json"
    identity_path.write_text(json.dumps({
        "SchemaVersion": "sixgr_resolved_config_identity/v1",
        "ScenarioID": "fixture", "ConfigHash": "declared-filesystem-test",
        "ResolvedYAMLSHA256": hashlib.sha256(original).hexdigest(),
        "ResolvedJSONSHA256": "",
    }), encoding="utf-8")
    identity_before = identity_path.read_bytes()
    run_id = dash._filesystem_run_id_for_folder(tmp_path)
    run = {"run_id": run_id, "run_tag": "original_fs",
           "run_folder": str(tmp_path), "status_text": "completed"}
    monkeypatch.setattr(dash, "fetch_run", lambda requested: run if requested == run_id else None)
    monkeypatch.setattr(dash, "fetch_artifacts", lambda _: [])
    monkeypatch.setattr(dash, "filesystem_run_rows", lambda **_: [run])
    monkeypatch.setattr(dash, "FILESYSTEM_ARTIFACT_CACHE", {})

    def no_database(*args, **kwargs):
        raise AssertionError("Filesystem download must not access external database")

    monkeypatch.setattr(dash, "db_connection", no_database)
    artifacts = dash.filesystem_artifacts_for_run(run)
    alternate = dash.find_artifact_by_logical_path(artifacts, "meta/alternate_source.yml")
    assert alternate and alternate["artifact_kind"] == "yaml"
    assert alternate["mime_type"] == "application/x-yaml"
    art = dash.find_artifact_by_logical_path(artifacts, "meta/scenario_config_resolved.yaml")
    assert art and dash.is_filesystem_virtual_artifact_id(art["artifact_id"])
    assert art["artifact_kind"] == "yaml" and art["mime_type"] == "application/x-yaml"
    assert Path(dash.filesystem_artifact_by_id(art["artifact_id"])["filesystem_path"]) == yaml_path
    # Prime the real preview cache, then prove download bypasses stale bytes.
    assert dash.fetch_artifact_bytes(art["artifact_id"]) == original
    content, _, name = dash.build_run_resolved_input_download(run_id, "yaml")
    assert content == original and name == "original_fs_resolved_input.yaml"
    assert yaml_path.read_bytes() == original
    assert identity_path.read_bytes() == identity_before
    changed = original.replace(b"fixture", b"changed")  # Same file length.
    yaml_path.write_bytes(changed)
    with pytest.raises(ValueError, match="SHA256 mismatch"):
        dash.build_run_resolved_input_download(run_id, "yaml")
    assert yaml_path.read_bytes() == changed  # No repair/rewrite by downloader.
    assert identity_path.read_bytes() == identity_before
