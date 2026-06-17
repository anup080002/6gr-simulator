from __future__ import annotations

from tests._actual_lls_test_helper import run_isolated_matlab_test


def test_dut_reference_comparison() -> None:
    run_isolated_matlab_test("tests/testDUTReferenceComparison.m")
