"""Regression evidence parsing only, not simulator performance evidence."""
import hashlib
import importlib.util
import json
import io
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location(
    "regression_audit", Path(__file__).resolve().parents[1] / "tools/reconcile_matlab_regressions.py")
audit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(audit)


def test_fullstack_summaries_and_nested_probes_are_not_double_counted():
    rows, pending = audit.parse_results(
        "FULLSTACK_TEST_START outer\nFULLSTACK_TEST_START deliberateFailure\n"
        "FULLSTACK_TEST_END deliberateFailure FAIL\n[FAIL] deliberateFailure (0.1s)\n"
        "FULLSTACK_TEST_END outer PASS\n[PASS] outer (2.0s)\n"
        "FULLSTACK_TEST_START ongoing\n")
    assert [(row["test"], row["status"]) for row in rows] == [("outer", "PASS")]
    assert pending == ["ongoing"]


def test_focused_results_require_timed_test_result_lines():
    rows, pending = audit.parse_results("[PASS] component\n[PASS] testOne (1.2s)\n[FAIL] testTwo (3.0s)\n")
    assert [row["test"] for row in rows] == ["testOne", "testTwo"]
    assert not pending


def test_mismatched_markers_are_not_accepted():
    with pytest.raises(ValueError, match="Unmatched terminal"):
        audit.parse_results("FULLSTACK_TEST_START first\nFULLSTACK_TEST_END second PASS\n")


def test_paired_focused_markers_count_only_completed_root_tests():
    rows, pending = audit.parse_results(
        "FOCUSED_START testOuter\nFOCUSED_START negativeProbe\n"
        "FOCUSED_FAIL negativeProbe\n[FAIL] negativeProbe (0.1s)\n"
        "FOCUSED_PASS testOuter\n[PASS] testOuter (1.0s)\n"
        "FOCUSED_START testFailed\nFOCUSED_FAIL testFailed\n"
        "FOCUSED_START testIncomplete\n")
    assert [(r["test"], r["status"]) for r in rows] == [
        ("testOuter", "PASS"), ("testFailed", "FAIL")]
    assert pending == ["testIncomplete"]


def test_nested_focused_markers_do_not_escape_fullstack_ownership():
    rows, pending = audit.parse_results(
        "FULLSTACK_TEST_START testOuter\nFOCUSED_START probe\n"
        "FOCUSED_PASS probe\nFULLSTACK_TEST_END testOuter FAIL\n")
    assert [(r["test"], r["status"]) for r in rows] == [("testOuter", "FAIL")]
    assert not pending


def test_unpaired_focused_pass_is_not_completion_evidence():
    assert audit.parse_results("FOCUSED_PASS testUnknown\n") == ([], [])
    rows, pending = audit.parse_results(
        "FOCUSED_START testOne\nFOCUSED_PASS testOne\nFOCUSED_PASS component\n")
    assert [row["test"] for row in rows] == ["testOne"]
    assert not pending
    with pytest.raises(ValueError, match="Unmatched terminal"):
        audit.parse_results("FOCUSED_START testFirst\nFOCUSED_PASS testOther\n")


def test_later_pass_does_not_erase_failure_or_invent_source_identity(tmp_path):
    first, second = tmp_path / "old.log", tmp_path / "new.log"
    first.write_text("[FAIL] testOne (1.0s)\n")
    second.write_text("[PASS] testOne (1.0s)\n")
    result = audit.reconcile([first, second], tmp_path / "audit")
    assert not result["final_source_accepted"]
    assert result["tests_with_failure_evidence"] == 1
    assert "pass_and_fail_evidence_requires_source_check" in (tmp_path / "audit/failure_reconciliation.csv").read_text()
    assert len(result["evidence"]["testOne"]) == 2
    for log in result["logs"]:
        assert log["executed_source_identity"].startswith("unknown")
        content = (tmp_path / "audit" / log["snapshot"]).read_bytes()
        assert hashlib.sha256(content).hexdigest() == log["snapshot_sha256"]
    assert json.loads((tmp_path / "audit/receipt.json").read_text())["distinct_tests"] == 1


def test_existing_evidence_cannot_be_overwritten(tmp_path):
    with pytest.raises(FileExistsError):
        audit.reconcile([], tmp_path)


def focused_mat(**changes):
    from scipy.io import savemat
    report = dict(ok=0, selected_tests=["testOne", "testTwo"], total_duration_s=3.,
                  results=[dict(name="testOne", ok=1, duration_s=1.),
                           dict(name="testTwo", ok=0, duration_s=2.)])
    report.update(changes)
    buffer = io.BytesIO()
    savemat(buffer, {"retained": report, "unrelated_ok": True})
    return buffer.getvalue()


def test_saved_focused_receipt_counts_actual_outcomes():
    rows, pending = audit.parse_focused_mat(focused_mat())
    assert [(r["test"], r["status"]) for r in rows] == [
        ("testOne", "PASS"), ("testTwo", "FAIL")]
    assert [r["result_index"] for r in rows] == [0, 1]
    assert not pending


def test_single_test_mat_and_snapshot_do_not_invent_source(tmp_path):
    source = tmp_path / "retained.mat"
    source.write_bytes(focused_mat(ok=1, selected_tests="testOne", total_duration_s=1.,
                                 results=dict(name="testOne", ok=1, duration_s=1.)))
    result = audit.reconcile([source], tmp_path / "audit")
    assert result["distinct_tests"] == 1 and not result["final_source_accepted"]
    receipt = result["logs"][0]
    assert receipt["executed_source_identity"].startswith("unknown")
    assert (tmp_path / "audit" / receipt["snapshot"]).read_bytes() == source.read_bytes()


@pytest.mark.parametrize("changes", [
    {"ok": 1}, {"ok": 2}, {"total_duration_s": float("nan")},
    {"total_duration_s": -1}, {"selected_tests": ["testOne"]},
    {"selected_tests": ["testTwo", "testOne"]},
    {"results": [dict(name="testOne", ok=2, duration_s=1.),
                 dict(name="testTwo", ok=0, duration_s=2.)]},
])
def test_invalid_or_partial_mat_cannot_become_pass(changes):
    with pytest.raises(ValueError):
        audit.parse_focused_mat(focused_mat(**changes))


def test_arbitrary_mat_boolean_is_not_a_test_result():
    from scipy.io import savemat
    buffer = io.BytesIO()
    savemat(buffer, {"ok": True})
    with pytest.raises(ValueError, match="No complete"):
        audit.parse_focused_mat(buffer.getvalue())
