"""Filesystem fixtures only; no MAT/PHY qualification is claimed."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid

import pytest

pytestmark = pytest.mark.skipif(os.name != "nt", reason="Windows junction storage contract")
SCRIPT = Path(__file__).resolve().parents[1] / "scripts/move_lls_channel_archives.ps1"


def extended(path):
    return Path("\\\\?\\" + os.path.normpath(os.path.abspath(path)))


def fixture(root):
    run = root / "declared_storage_fixture_not_phy"
    folder = run / "channel/mat"
    extended(folder).mkdir(parents=True)
    extended(run / "meta").mkdir()
    extended(run / "meta/scenario_config_identity.json").write_text('{"Scope":"storage_fixture"}')
    name = "channel_observation_" + "a" * 64 + ".mat"
    # Opaque bytes exercise exact relocation, not MATLAB deserialization.
    payload = bytes(range(256)) * 32
    extended(folder / name).write_bytes(payload)
    return run, name, payload


def invoke(run, destination, *options):
    return subprocess.run(
        [shutil.which("pwsh") or "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
         "-File", str(SCRIPT), "-RunFolder", str(run), "-ArchiveFolder", str(destination), *options],
        capture_output=True, text=True, timeout=40,
    )


@pytest.mark.parametrize("long_path", [False, True])
def test_archive_move_is_hash_exact_and_keeps_original_logical_path(tmp_path, long_path):
    root = tmp_path / ("long_storage_" * 9) if long_path else tmp_path
    run, name, payload = fixture(root)
    external_test_root = os.environ.get("SIXGR_TEST_ARCHIVE_ROOT")
    destination = (Path(external_test_root) / str(uuid.uuid4()) if external_test_root else
                   tmp_path / "external_archive_destination")
    if long_path:
        assert len(str(run / "channel/mat" / name)) > 260
    plan = invoke(run, destination, "-PlanOnly")
    assert plan.returncode == 0, plan.stderr
    assert json.loads(plan.stdout)["Status"] == "plan_only_no_files_changed"
    assert not destination.exists() and extended(run / "channel/mat" / name).read_bytes() == payload
    result = invoke(run, destination)
    assert result.returncode == 0, result.stderr
    receipt = json.loads(result.stdout)
    assert receipt["Status"] == "verified" and not receipt["ScientificDataChanged"]
    assert not receipt["SourceCodeMoved"]
    assert receipt["Files"][0]["SHA256"] == hashlib.sha256(payload).hexdigest()
    assert (destination / name).read_bytes() == payload
    assert extended(run / "channel/mat" / name).read_bytes() == payload
    assert os.path.samefile(extended(run / "channel/mat"), extended(destination))
    assert not list(extended(run / "channel").glob("mat_relocation_backup_*"))
    assert json.loads(extended(run / "meta/channel_archive_storage.json").read_text()) == receipt


@pytest.mark.parametrize("condition", ["destination_exists", "temporary_archive", "overlap"])
def test_archive_move_rejects_unsafe_plan_without_touching_original(tmp_path, condition):
    run, name, payload = fixture(tmp_path)
    destination = tmp_path / "external_destination"
    if condition == "destination_exists":
        destination.mkdir()
        (destination / "keep.txt").write_text("unrelated retained evidence")
    elif condition == "temporary_archive":
        extended(run / "channel/mat/m_partial.mat").write_bytes(b"incomplete")
    else:
        destination = run / "nested_destination"
    result = invoke(run, destination)
    assert result.returncode != 0
    assert extended(run / "channel/mat" / name).read_bytes() == payload
    assert not extended(run / "meta/channel_archive_storage.json").exists()
    if condition == "destination_exists":
        assert (destination / "keep.txt").read_text() == "unrelated retained evidence"
