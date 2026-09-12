from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

TOOL = Path(__file__).resolve().parents[1] / "tools" / "audit_lls_run_exhaustive.py"
SPEC = importlib.util.spec_from_file_location("deep_path_auditor", TOOL)
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


def test_enumeration_includes_deep_checkpoint_and_case_variant(tmp_path: Path) -> None:
    run = tmp_path / "run"
    source = run / ("checkpoint_" + "a" * 80) / ("sources_" + "b" * 80) / ("radio_" + "c" * 80) / "sample.CSV"
    physical = AUDIT.io_path(source)
    physical.parent.mkdir(parents=True)
    physical.write_text("value\n12\n", encoding="utf-8")
    assert source in AUDIT.enumerate_run_files(run)
    proc = subprocess.run(
        [sys.executable, str(TOOL), str(run), str(tmp_path / "audit")],
        capture_output=True, text=True, check=False,
    )
    assert proc.returncode == 0, proc.stderr + proc.stdout
    result = json.loads((tmp_path / "audit" / "audit_summary.json").read_text())
    assert result["csv_file_count"] == 1 and result["csv_total_rows"] == 1


def test_enumeration_raises_traversal_errors(tmp_path: Path, monkeypatch) -> None:
    def inaccessible(_root, *, onerror):
        onerror(PermissionError("checkpoint inaccessible"))
        return []
    monkeypatch.setattr(AUDIT.os, "walk", inaccessible)
    with pytest.raises(PermissionError, match="checkpoint inaccessible"):
        AUDIT.enumerate_run_files(tmp_path)
