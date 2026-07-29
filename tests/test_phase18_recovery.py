from __future__ import annotations

import csv
import json
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


SOURCE_ROOT = (
    REPO_ROOT
    / "results"
    / "lls"
    / "lls_webgui_full_stack_sinr_geometry_qualification"
    / "phase18_actual_20260728_04"
)
REANALYSIS_ROOT = SOURCE_ROOT.with_name(
    "phase18_actual_20260728_04_reanalysis"
)


def _csv(name: str) -> list[dict[str, str]]:
    path = REANALYSIS_ROOT / "reports" / "csv" / name
    assert path.is_file(), f"missing recovery artifact: {path}"
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def _manifest() -> dict:
    path = (
        REANALYSIS_ROOT
        / "reports"
        / "json"
        / "phase18_reanalysis_manifest.json"
    )
    assert path.is_file(), f"missing recovery manifest: {path}"
    return json.loads(path.read_text(encoding="utf-8"))


def test_artifact_manifest_path_resolution_is_exact() -> None:
    rows = _csv("phase18_artifact_resolution_trace.csv")
    manifest = next(
        row for row in rows if row["RequestedIdentity"] == "full_stack_run_manifest.csv"
    )
    assert manifest["Resolved"] in {"1", "true"}
    assert (
        manifest["RelativePath"]
        == "reports/csv/full_stack_run_manifest.csv"
    )
    assert manifest["ResolutionMethod"] == "MANIFEST_ARTIFACT_ID"
    assert len(manifest["ActualSHA256"]) == 64
    assert all("SUBSTRING" not in row["ResolutionMethod"] for row in rows)
    assert all(not Path(row["RelativePath"]).is_absolute() for row in rows)


def test_schema_adapter_registry_metadata_is_complete() -> None:
    rows = _csv("phase18_schema_adapter_results.csv")
    assert rows
    required = {
        "AdapterID",
        "SourceSchemaID",
        "TargetSchemaID",
        "SourceColumns",
        "TargetColumns",
        "TransformationFormula",
        "Lossless",
        "SourceArtifactSHA256",
        "AdapterVersion",
        "OutputArtifactSHA256",
    }
    assert required <= rows[0].keys()
    assert all(row["Lossless"] in {"1", "true"} for row in rows)
    assert all(len(row["SourceArtifactSHA256"]) == 64 for row in rows)
    assert all(len(row["OutputArtifactSHA256"]) == 64 for row in rows)
    assert all(row["SourceColumns"] for row in rows)
    assert all(
        "fill_from_config" not in row["TransformationFormula"].lower()
        and "configured_value_substitution" not in row[
            "TransformationFormula"
        ].lower()
        for row in rows
    )


def test_reanalysis_result_schemas_and_contract_counts() -> None:
    expected = {
        "phase18_recomputed_value_results.csv": (107, "CheckID"),
        "phase18_recomputed_component_results.csv": (163, "ComponentID"),
        "phase18_recomputed_subcase_results.csv": (31, "SubcaseID"),
        "phase18_recomputed_acceptance_results.csv": (387, "RuleID"),
    }
    for name, (count, key) in expected.items():
        rows = _csv(name)
        assert len(rows) == count
        assert key in rows[0]
        assert "Status" in rows[0]
        assert len({row[key] for row in rows}) == count
    triage = _csv("phase18_failure_triage.csv")
    allowed = {
        "EVALUATOR_BUG",
        "STATUS_REDUCER_BUG",
        "ARTIFACT_RESOLUTION_BUG",
        "SCHEMA_ADAPTER_MISSING",
        "FINALIZATION_ORDER_BUG",
        "ARTIFACT_MISSING",
        "DOMAIN_RUNTIME_FAILURE",
        "DOMAIN_NUMERICAL_FAILURE",
        "INTERRUPTED_REGRESSION",
        "CONTRACT_DEFECT_PROVEN",
        "UNCLASSIFIED",
    }
    assert triage
    assert {row["FailureClass"] for row in triage} <= allowed
    assert all(row["FailureClass"] for row in triage)


def test_parent_child_status_consistency() -> None:
    subcases = _csv("phase18_recomputed_subcase_results.csv")
    components = _csv("phase18_recomputed_component_results.csv")
    values = _csv("phase18_recomputed_value_results.csv")
    for subcase in subcases:
        if subcase["Status"] != "PASS":
            continue
        subcase_id = subcase["SubcaseID"]
        mandatory_components = [
            row
            for row in components
            if row["SubcaseID"] == subcase_id
            and row["Mandatory"] in {"1", "true"}
        ]
        mandatory_values = [
            row
            for row in values
            if row["SubcaseID"] == subcase_id
            and row["Required"] in {"1", "true"}
        ]
        assert all(row["Status"] == "PASS" for row in mandatory_components)
        assert all(
            row["CorrectnessChecked"] in {"1", "true"}
            for row in mandatory_components
        )
        assert all(row["Status"] == "PASS" for row in mandatory_values)


def test_source_run_hashes_were_not_mutated() -> None:
    manifest = _manifest()
    assert manifest["Completed"] is True
    assert manifest["ReadOnlySource"] is True
    assert manifest["SourceRunUnchanged"] is True
    assert manifest["SourceFileCount"] == 461
    assert (
        manifest["SourceInventorySHA256Before"]
        == manifest["SourceInventorySHA256After"]
    )
    assert len(manifest["SourceInventorySHA256After"]) == 64
    assert SOURCE_ROOT.is_dir()


def test_webgui_distinguishes_reanalysis_from_original() -> None:
    original = dash.filesystem_run_row_from_folder(SOURCE_ROOT)
    reanalysis = dash.filesystem_run_row_from_folder(REANALYSIS_ROOT)
    assert original is not None
    assert reanalysis is not None
    assert original["run_id"] != reanalysis["run_id"]
    assert original["profile_name"] == "full_stack_qualification"
    assert reanalysis["profile_name"] == "full_stack_qualification_reanalysis"
    status = json.loads(reanalysis["status_json"])
    assert status["qualification_reanalysis"] is True
    assert status["source_run_id"] == "phase18_actual_20260728_04"
    assert status["source_run_unchanged"] is True
    page = dash.build_product_frontend_page(
        "qualification",
        dash.FULL_STACK_QUALIFICATION_SCENARIO,
        user_profile=None,
    ).decode("utf-8")
    assert "Phase-18 read-only reanalysis" in page
    assert "Original → recomputed PASS" in page


def test_regression_helper_emits_progress_heartbeat(tmp_path: Path) -> None:
    helper = REPO_ROOT / "tools" / "run_bounded_command.py"
    log = tmp_path / "bounded.log"
    heartbeat = tmp_path / "heartbeat.json"
    result = subprocess.run(
        [
            sys.executable,
            str(helper),
            "--timeout-seconds",
            "2",
            "--heartbeat-seconds",
            "0.05",
            "--heartbeat-file",
            str(heartbeat),
            "--log",
            str(log),
            "--",
            sys.executable,
            "-c",
            "import time; time.sleep(0.25)",
        ],
        check=False,
    )
    assert result.returncode == 0
    payload = json.loads(heartbeat.read_text(encoding="utf-8"))
    assert payload["status"] == "RUNNING"
    assert payload["elapsed_seconds"] > 0
    assert payload["timeout_seconds"] == 2


def test_regression_helper_enforces_per_test_timeout(tmp_path: Path) -> None:
    helper = REPO_ROOT / "tools" / "run_bounded_command.py"
    log = tmp_path / "per_test.log"
    heartbeat = tmp_path / "per_test_heartbeat.json"
    child = (
        "import time; "
        "print('FULLSTACK_TEST_START deliberately_slow', flush=True); "
        "time.sleep(1)"
    )
    result = subprocess.run(
        [
            sys.executable,
            str(helper),
            "--timeout-seconds",
            "5",
            "--per-test-timeout-seconds",
            "0.15",
            "--heartbeat-seconds",
            "0.03",
            "--heartbeat-file",
            str(heartbeat),
            "--log",
            str(log),
            "--",
            sys.executable,
            "-c",
            child,
        ],
        check=False,
    )
    assert result.returncode == 125
    content = log.read_text(encoding="utf-8")
    assert "FULLSTACK:PerTestTimeout" in content
    assert "deliberately_slow" in content
