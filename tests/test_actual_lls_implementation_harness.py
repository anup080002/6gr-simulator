from __future__ import annotations

from tests._actual_lls_test_helper import run_isolated_matlab_test


def test_actual_lls_implementation_harness() -> None:
    run_isolated_matlab_test("tests/testActualLLSImplementationHarness.m")
