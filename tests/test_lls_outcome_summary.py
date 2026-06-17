from __future__ import annotations

from tests._actual_lls_test_helper import run_isolated_matlab_test


def test_lls_outcome_summary() -> None:
    run_isolated_matlab_test("tests/testLLSOutcomeSummary.m")
