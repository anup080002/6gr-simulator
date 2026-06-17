from __future__ import annotations

from tests._actual_lls_test_helper import run_isolated_matlab_test


def test_no_label_only_success() -> None:
    run_isolated_matlab_test("tests/testNoLabelOnlySuccess.m")
