from __future__ import annotations

from tests._actual_lls_test_helper import run_isolated_matlab_test


def test_phy_value_invariants() -> None:
    run_isolated_matlab_test("tests/testPHYValueInvariantChecks.m")
