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


def test_lut_risk_acronym_does_not_match_absolute_or_resolution() -> None:
    for value in ("absolute_zero_based", "receiver_thermal_noise_absolute_sqrt_mW", "trajectory_resolution"):
        assert not AUDIT_MODULE.risk_counts(value)
    for value in ("LUT", "lut_linear_interp", "calibration-lut", "LUT2", "fast_proxy"):
        assert AUDIT_MODULE.risk_counts(value)["proxy"] == 1
    # Mentions of an unavailable proxy stay discoverable. The inventory
    # counts vocabulary, not proof that an approximation executed.
    assert AUDIT_MODULE.risk_counts("unavailable_decoder_truth_proxy_not_materialized")["proxy"] == 1


def run_audit(
    run: Path,
    output: Path,
    *,
    strict_value_closure: bool = False,
    preview_rows: int = 3,
) -> subprocess.CompletedProcess[str]:
    command = [sys.executable, str(AUDIT_TOOL), str(run), str(output)]
    if strict_value_closure:
        command.append("--strict-value-closure")
    if preview_rows != 3:
        command.extend(["--preview-rows", str(preview_rows)])
    return subprocess.run(
        command,
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
    with (output / "first_three_row_value_assessment.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        assessment = next(csv.DictReader(handle))
    assert assessment["value_shape"] == "header_only_no_values"
    assert assessment["value_review_status"] == (
        "HEADER_ONLY_REQUIRES_APPLICABILITY_REVIEW"
    )


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


def test_headerless_keysight_iq_preserves_first_sample(tmp_path: Path) -> None:
    run = tmp_path / "run"
    source = run / "waveform" / "csv" / "final_tx_iq_dl_port1_keysight.csv"
    source.parent.mkdir(parents=True)
    source.write_text("0,0\n0.25,-0.5\n", encoding="utf-8")

    file_row, columns, first_rows = AUDIT_MODULE.audit_csv(source, run)
    assert file_row["parse_ok"] is True
    assert file_row["row_count"] == 2
    assert file_row["column_count"] == 2
    assert file_row["duplicate_header_count"] == 0
    assert "headerless_keysight_iq_contract" in file_row["observations"]
    assert [column["column_name"] for column in columns] == ["I", "Q"]
    assert json.loads(first_rows[0]["values_json"]) == ["0", "0"]


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

    with (output / "first_three_row_value_assessment.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        assessment = next(csv.DictReader(handle))
    assert assessment["observed_preview_row_count"] == "2"
    assert assessment["preview_missing_or_nan_cell_count"] == "1"
    assert assessment["preview_zero_numeric_cell_count"] == "2"
    assert assessment["value_review_status"] == (
        "VALUES_PRESENT_BUT_DOMAIN_CONTRACT_MISSING"
    )


def test_five_row_preview_persists_exactly_five_leading_rows(tmp_path: Path) -> None:
    run = tmp_path / "run"
    output = tmp_path / "audit"
    source = run / "reports" / "csv" / "measurements.csv"
    source.parent.mkdir(parents=True)
    source.write_text(
        "Sample,Value\n" + "".join(f"{index},{index * 2}\n" for index in range(1, 8)),
        encoding="utf-8",
    )

    proc = run_audit(run, output, preview_rows=5)
    assert proc.returncode == 0, proc.stderr + proc.stdout
    with (output / "all_csv_first_five_rows.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        previews = list(csv.DictReader(handle))
    assert [int(row["source_row_number"]) for row in previews] == [1, 2, 3, 4, 5]
    assert json.loads(previews[-1]["values_json"]) == ["5", "10"]
    with (output / "first_five_row_value_assessment.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        assessment = next(csv.DictReader(handle))
    assert assessment["observed_preview_row_count"] == "5"
    summary = json.loads((output / "audit_summary.json").read_text(encoding="utf-8"))
    assert summary["csv_preview_row_limit"] == 5


def test_fixed_link_unscheduled_fields_respect_explicit_not_applicable_status(
    tmp_path: Path,
) -> None:
    run = tmp_path / "run"
    source = run / "air_interface" / "csv" / "dl_fixed_link_campaign_trials.csv"
    source.parent.mkdir(parents=True)
    resolved = run / "meta" / "scenario_config_resolved.json"
    resolved.parent.mkdir(parents=True)
    resolved.write_text(
        json.dumps({"sweeps_and_matrix": {"fixed_link_calibration": {"only": True}}}),
        encoding="utf-8",
    )
    source.write_text(
        "ScheduledMCSIndex,ScheduledModulation,"
        "ScheduledOperatingPointEvidenceStatus\n"
        "NaN,,not_applicable_no_adaptive_scheduled_decision\n"
        "NaN,,not_applicable_no_adaptive_scheduled_decision\n",
        encoding="utf-8",
    )

    _, columns, _ = AUDIT_MODULE.audit_csv(source, run)
    by_name = {row["column_name"]: row for row in columns}
    expected = "explicit_not_applicable_no_adaptive_scheduled_decision"
    assert by_name["ScheduledMCSIndex"]["semantic_attention"] == expected
    assert by_name["ScheduledModulation"]["semantic_attention"] == expected


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


def test_strict_value_closure_fails_unclassified_header_only_csv(
    tmp_path: Path,
) -> None:
    run = tmp_path / "run"
    output = tmp_path / "audit"
    source = run / "reports" / "csv" / "unclassified.csv"
    source.parent.mkdir(parents=True)
    source.write_text("Metric,Value\n", encoding="utf-8")

    proc = run_audit(run, output, strict_value_closure=True)
    assert proc.returncode == 1
    summary = json.loads((output / "audit_summary.json").read_text(encoding="utf-8"))
    assert summary["csv_header_only_unresolved_files"] == 1
    assert not summary["csv_value_review_gate_pass"]


def test_disabled_live_csirs_header_is_not_counted_as_runtime_evidence(
    tmp_path: Path,
) -> None:
    run = tmp_path / "run"
    output = tmp_path / "audit"
    config = run / "meta" / "scenario_config_resolved.json"
    config.parent.mkdir(parents=True)
    config.write_text(
        json.dumps({
            "reference_signals": {
                "csi_rs_enabled": False,
                "nzp_csi_rs": {"enabled": False},
            }
        }),
        encoding="utf-8",
    )
    source = run / "reports" / "csv" / "live_csirs_stats.csv"
    source.parent.mkdir(parents=True)
    source.write_text("ScenarioID,ConfigHash,SampleCount\n", encoding="utf-8")
    (run / "reports" / "csv" / "scenario_summary.csv").write_text(
        "ScenarioID,ConfigHash,RunnerProfile\nscenario," + "a" * 64 + ",waveform_bundle\n",
        encoding="utf-8",
    )

    proc = run_audit(run, output)
    # This deliberately minimal fixture lacks the unrelated primary-link,
    # manifest and chart evidence required by the complete-run auditor.  Its
    # process may therefore fail for those missing contracts; the assertion
    # below is specifically about the CSI-RS zero-row disposition.
    assert proc.returncode in {0, 1}, proc.stderr + proc.stdout
    with (output / "first_three_row_value_assessment.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        assessment = next(csv.DictReader(handle))
    assert assessment["value_review_status"] == "POLICY_DISABLED_NO_OBSERVATIONS"
    assert assessment["semantic_disposition"] == (
        "PASS_POLICY_DISABLED_NO_OBSERVATIONS"
    )


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


def test_frc_reference_contract_receives_explicit_pass_disposition(
    tmp_path: Path,
) -> None:
    run = tmp_path / "run"
    relative = "reports/csv/frc_reference_points.csv"
    csv_rows = [{
        "relative_path": relative,
        "sha256": "c" * 64,
        "row_count": 1,
        "column_count": 70,
        "issue_count": 0,
        "parse_ok": True,
    }]
    semantic_audit = {
        "canonical_csv_semantic_audit": [{
            "artifact_path": relative,
            "category": "frc_reference",
            "required": True,
            "evaluated": True,
            "passed": True,
        }],
        "chart_source_semantic_audit": [],
    }
    rows = AUDIT_MODULE.build_csv_file_dispositions(
        run, csv_rows, [], semantic_audit
    )
    assert rows[0]["audit_disposition"] == "PASS_FRC_REFERENCE_SEMANTICS"


def test_terminal_truth_mirror_mismatch_fails_audit(tmp_path: Path) -> None:
    run = tmp_path / "run"
    output = tmp_path / "audit"
    authority = run / "reports" / "csv" / "truth_contract_summary.csv"
    mirror = run / "analytics" / "csv" / "truth_policy_analytics.csv"
    authority.parent.mkdir(parents=True)
    mirror.parent.mkdir(parents=True)
    header = "ScenarioID,RunTag,RuntimeTruthContractOk,ResultOk,StrictTruthFailureCount\n"
    authority.write_text(header + "scenario,run,1,1,0\n", encoding="utf-8")
    mirror.write_text(header + "scenario,run,0,0,2\n", encoding="utf-8")

    rows = AUDIT_MODULE.audit_terminal_status_mirrors(run)
    mismatches = [row for row in rows if not row["match"]]
    assert {row["field"] for row in mismatches} == {
        "RuntimeTruthContractOk", "ResultOk", "StrictTruthFailureCount"
    }

    proc = run_audit(run, output)
    assert proc.returncode == 1
    summary = json.loads((output / "audit_summary.json").read_text(encoding="utf-8"))
    assert summary["terminal_status_mirror_mismatch_count"] == 3
    with (output / "terminal_status_mirror_audit.csv").open(
        "r", encoding="utf-8", newline=""
    ) as handle:
        persisted = list(csv.DictReader(handle))
    assert any(row["status"] == "FAIL_STALE_TERMINAL_MIRROR" for row in persisted)


def test_terminal_truth_mirror_exact_common_fields_pass(tmp_path: Path) -> None:
    run = tmp_path / "run"
    authority = run / "reports" / "csv" / "truth_contract_summary.csv"
    mirror = run / "analytics" / "csv" / "truth_policy_analytics.csv"
    authority.parent.mkdir(parents=True)
    mirror.parent.mkdir(parents=True)
    header = "ScenarioID,RunTag,RuntimeTruthContractOk,ResultOk,ResultStatusReason\n"
    value = "scenario,run,1,1,all_required_root_gates_passed\n"
    authority.write_text(header + value, encoding="utf-8")
    mirror.write_text(header + value, encoding="utf-8")

    rows = AUDIT_MODULE.audit_terminal_status_mirrors(run)
    assert rows and all(row["match"] for row in rows)


def test_interference_runtime_csv_is_covered_by_domain_semantics(
    tmp_path: Path,
) -> None:
    run = tmp_path / "run"
    relative = "interference/csv/interference_topology.csv"
    source = run / relative
    source.parent.mkdir(parents=True)
    source.write_text(
        "ComputedSINRDb,InterferenceConfigured,InterferenceApplied,StrictOk,"
        "TruthStatus,EvidenceScope\n"
        "8.25,0,0,1,real_lls_evidence,in_path\n",
        encoding="utf-8",
    )
    summary = run / "reports" / "csv" / "scenario_summary.csv"
    summary.parent.mkdir(parents=True)
    summary.write_text(
        "RunnerProfile,ScenarioID\nprach_detection,interference-audit-test\n",
        encoding="utf-8",
    )

    file_row, _columns, _previews = AUDIT_MODULE.audit_csv(source, run)
    semantic_audit = AUDIT_MODULE.audit_csv_semantics(run)
    matching_checks = [
        check for check in semantic_audit["canonical_csv_semantic_audit"]
        if check["artifact_path"] == relative
        and check["category"] == "domain_runtime"
    ]
    assert matching_checks and all(check["passed"] for check in matching_checks)
    rows = AUDIT_MODULE.build_csv_file_dispositions(
        run, [file_row], [], semantic_audit
    )
    assert rows[0]["audit_disposition"] == "PASS_DOMAIN_RUNTIME_SEMANTICS"
