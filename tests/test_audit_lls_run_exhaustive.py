from __future__ import annotations

import csv
import importlib.util
import json
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
AUDIT_TOOL = REPO_ROOT / "tools" / "audit_lls_run_exhaustive.py"
SPEC = importlib.util.spec_from_file_location("audit_lls_run_exhaustive", AUDIT_TOOL)
assert SPEC is not None and SPEC.loader is not None
AUDIT_MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT_MODULE)


def run_audit(run: Path, output: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(AUDIT_TOOL), str(run), str(output)],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


def test_header_only_result_is_schema_valid_observation(tmp_path: Path) -> None:
    run = tmp_path / "run"
    output = tmp_path / "audit"
    source = run / "reports" / "csv" / "truth_contract_failures.csv"
    source.parent.mkdir(parents=True)
    source.write_text("FailureCode,Reason\n", encoding="utf-8")

    proc = run_audit(run, output)
    assert proc.returncode == 0, proc.stderr + proc.stdout
    summary = json.loads((output / "audit_summary.json").read_text(encoding="utf-8"))
    assert summary["csv_empty_files"] == 1
    assert summary["csv_structural_issue_files"] == 0
    with (output / "all_csv_file_audit.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        row = next(csv.DictReader(handle))
    assert row["schema_only"] == "True"
    assert row["observations"] == "header_only_no_rows"
    assert row["issues"] == ""


def test_missing_header_remains_a_structural_failure(tmp_path: Path) -> None:
    run = tmp_path / "run"
    output = tmp_path / "audit"
    source = run / "reports" / "csv" / "broken.csv"
    source.parent.mkdir(parents=True)
    source.write_bytes(b"")

    proc = run_audit(run, output)
    assert proc.returncode == 1
    summary = json.loads((output / "audit_summary.json").read_text(encoding="utf-8"))
    assert summary["csv_parse_failures"] == 1
    assert summary["csv_structural_issue_files"] == 1


def test_row_width_mismatch_remains_a_structural_failure(tmp_path: Path) -> None:
    run = tmp_path / "run"
    output = tmp_path / "audit"
    source = run / "reports" / "csv" / "broken_width.csv"
    source.parent.mkdir(parents=True)
    source.write_text("A,B\n1\n", encoding="utf-8")

    proc = run_audit(run, output)
    assert proc.returncode == 1
    summary = json.loads((output / "audit_summary.json").read_text(encoding="utf-8"))
    assert summary["csv_parse_failures"] == 0
    assert summary["csv_structural_issue_files"] == 1


def test_zero_and_nan_columns_are_classified_not_hidden(tmp_path: Path) -> None:
    run = tmp_path / "run"
    output = tmp_path / "audit"
    source = run / "reports" / "csv" / "measurements.csv"
    source.parent.mkdir(parents=True)
    source.write_text("AlwaysZero,PartlyMissing,Useful\n0,NaN,2\n0,3,4\n", encoding="utf-8")

    proc = run_audit(run, output)
    assert proc.returncode == 0, proc.stderr + proc.stdout
    with (output / "zero_nan_column_classification.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        rows = {row["column_name"]: row for row in csv.DictReader(handle)}
    assert rows["AlwaysZero"]["value_population_class"] == "all_zero_finite"
    assert rows["PartlyMissing"]["value_population_class"] == "mixed_finite_and_missing"
    assert rows["PartlyMissing"]["nan_token_count"] == "1"

    with (output / "all_csv_first_three_rows.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        previews = list(csv.DictReader(handle))
    assert len(previews) == 2
    assert previews[0]["source_row_number"] == "1"
    assert previews[0]["missing_or_nan_cell_count"] == "1"
    assert previews[0]["zero_numeric_cell_count"] == "1"
    assert json.loads(previews[0]["values_json"]) == ["0", "NaN", "2"]


def test_header_only_csv_has_explicit_first_row_preview_state(tmp_path: Path) -> None:
    run = tmp_path / "run"
    output = tmp_path / "audit"
    source = run / "reports" / "csv" / "no_failures.csv"
    source.parent.mkdir(parents=True)
    source.write_text("FailureCode,Reason\n", encoding="utf-8")

    proc = run_audit(run, output)
    assert proc.returncode == 0, proc.stderr + proc.stdout
    with (output / "all_csv_first_three_rows.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        preview = next(csv.DictReader(handle))
    assert preview["preview_state"] == "header_only_no_rows"
    assert json.loads(preview["header_json"]) == ["FailureCode", "Reason"]
    assert json.loads(preview["values_json"]) == []


def test_none_is_an_explicit_value_not_a_missing_token(tmp_path: Path) -> None:
    run = tmp_path / "run"
    output = tmp_path / "audit"
    source = run / "reports" / "csv" / "execution_lineage.csv"
    source.parent.mkdir(parents=True)
    source.write_text("ApproximationMode\nnone\n", encoding="utf-8")

    proc = run_audit(run, output)
    assert proc.returncode == 0, proc.stderr + proc.stdout
    with (output / "all_csv_column_audit.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        row = next(csv.DictReader(handle))
    assert row["blank_count"] == "0"
    assert row["value_population_class"] == "categorical_population"


def test_every_csv_receives_an_explicit_file_disposition(tmp_path: Path) -> None:
    run = tmp_path / "run"
    output = tmp_path / "audit"
    source = run / "reports" / "csv" / "measurements.csv"
    source.parent.mkdir(parents=True)
    source.write_text("Metric,Value\nruntime_measurement,0\n", encoding="utf-8")

    proc = run_audit(run, output)
    assert proc.returncode == 0, proc.stderr + proc.stdout
    with (output / "csv_file_semantic_disposition.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        rows = list(csv.DictReader(handle))
    assert len(rows) == 1
    assert rows[0]["relative_path"] == "reports/csv/measurements.csv"
    assert rows[0]["audit_disposition"] == "PARSED_UNCONTRACTED_REQUIRES_DOMAIN_REVIEW"


def test_infinite_invariant_bound_is_not_mislabeled_as_runtime_nan(tmp_path: Path) -> None:
    run = tmp_path / "run"
    output = tmp_path / "audit"
    source = run / "reports" / "csv" / "phy_value_invariant_checks.csv"
    source.parent.mkdir(parents=True)
    source.write_text("Metric,ExpectedMin,ExpectedMax\nBER,0,Inf\n", encoding="utf-8")

    proc = run_audit(run, output)
    assert proc.returncode == 0, proc.stderr + proc.stdout
    with (output / "zero_nan_column_classification.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        rows = {row["column_name"]: row for row in csv.DictReader(handle)}
    assert rows["ExpectedMax"]["semantic_attention"] == (
        "unbounded_acceptance_limit_not_runtime_measurement"
    )


def test_semantically_checked_control_and_exact_duplicate_receive_pass_dispositions(
    tmp_path: Path,
) -> None:
    run = tmp_path / "run"
    canonical = "air_interface/csv/prach_trials.csv"
    duplicate = "control/csv/prach_trials.csv"
    digest = "a" * 64
    csv_rows = [
        {
            "relative_path": canonical,
            "sha256": digest,
            "row_count": 2,
            "column_count": 3,
            "issue_count": 0,
            "parse_ok": True,
        },
        {
            "relative_path": duplicate,
            "sha256": digest,
            "row_count": 2,
            "column_count": 3,
            "issue_count": 0,
            "parse_ok": True,
        },
    ]
    semantic_audit = {
        "canonical_csv_semantic_audit": [
            {
                "artifact_path": canonical,
                "category": "control_runtime",
                "required": True,
                "evaluated": True,
                "passed": True,
            }
        ],
        "chart_source_semantic_audit": [],
    }
    rows = AUDIT_MODULE.build_csv_file_dispositions(
        run, csv_rows, [], semantic_audit
    )
    by_path = {row["relative_path"]: row for row in rows}
    assert by_path[canonical]["audit_disposition"] == "PASS_CONTROL_RUNTIME_SEMANTICS"
    assert by_path[duplicate]["audit_disposition"] == (
        "PASS_BYTE_IDENTICAL_SEMANTIC_DUPLICATE"
    )
    assert by_path[duplicate]["canonical_source"] == canonical


def test_equal_bytes_with_different_basename_do_not_inherit_domain_contract(
    tmp_path: Path,
) -> None:
    run = tmp_path / "run"
    digest = "b" * 64
    csv_rows = [
        {
            "relative_path": "air_interface/csv/prach_trials.csv",
            "sha256": digest,
            "row_count": 1,
            "column_count": 1,
            "issue_count": 0,
            "parse_ok": True,
        },
        {
            "relative_path": "analytics/csv/unrelated_metric.csv",
            "sha256": digest,
            "row_count": 1,
            "column_count": 1,
            "issue_count": 0,
            "parse_ok": True,
        },
    ]
    semantic_audit = {
        "canonical_csv_semantic_audit": [
            {
                "artifact_path": "air_interface/csv/prach_trials.csv",
                "category": "control_runtime",
                "required": True,
                "evaluated": True,
                "passed": True,
            }
        ],
        "chart_source_semantic_audit": [],
    }
    rows = AUDIT_MODULE.build_csv_file_dispositions(
        run, csv_rows, [], semantic_audit
    )
    by_path = {row["relative_path"]: row for row in rows}
    assert by_path["analytics/csv/unrelated_metric.csv"]["audit_disposition"] == (
        "PARSED_UNCONTRACTED_REQUIRES_DOMAIN_REVIEW"
    )
