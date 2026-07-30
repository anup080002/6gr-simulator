"""Regression coverage for Phase-14 oracle publication on deep run paths."""

from __future__ import annotations

import importlib.util
import shutil
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPOSITORY_ROOT / "tools" / "validation" / "generate_independent_oracles.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("phase14_oracles", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_oracle_materializer_supports_deep_recovery_output(tmp_path: Path) -> None:
    module = _load_module()
    output = tmp_path
    while len(str(output / "oracles" / "ldpc_rate_match_analytical_invariant.csv")) <= 280:
        output = output / "phase18_recovery_evidence"
    try:
        registry = module.materialize(REPOSITORY_ROOT, output)
        assert module.io_path(registry).is_file()
        rows = module.io_path(registry).read_text(encoding="utf-8").splitlines()
        assert len(rows) == 33
        assert module.io_path(
            output / "oracles" / "ldpc_rate_match_analytical_invariant.csv"
        ).is_file()
    finally:
        shutil.rmtree(module.io_path(tmp_path), ignore_errors=True)
