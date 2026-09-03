from __future__ import annotations

import csv
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


pytestmark = pytest.mark.phase18_recovery


DEFAULT_SOURCE_ROOT = (
    REPO_ROOT
    / "results"
    / "lls"
    / "lls_webgui_full_stack_sinr_geometry_qualification"
    / "phase18_actual_20260729_01"
)
SOURCE_ROOT = Path(
    os.environ.get("SIXGR_PHASE18_SOURCE_ROOT", DEFAULT_SOURCE_ROOT)
).resolve()
RECOVERY_ROOT = Path(
    os.environ.get(
        "SIXGR_PHASE18_RECOVERY_ROOT",
        SOURCE_ROOT.with_name(f"{SOURCE_ROOT.name}_recovery"),
    )
).resolve()


def _csv(name: str) -> list[dict[str, str]]:
    path = RECOVERY_ROOT / "reports" / "csv" / name
    assert path.is_file(), f"missing recovery artifact: {path}"
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def _manifest() -> dict:
    path = RECOVERY_ROOT / "meta" / "recovery_manifest.json"
    assert path.is_file(), f"missing recovery manifest: {path}"
    return json.loads(path.read_text(encoding="utf-8"))


def test_artifact_manifest_path_resolution_is_exact() -> None:
    rows = _csv("artifact_path_resolution.csv")
    assert rows
    resolved = [row for row in rows if row["Status"] == "PASS"]
    assert resolved
    assert all(
        "SUBSTRING" not in row["ResolutionMethod"].upper() for row in rows
    )
    assert all(
        not Path(row["ResolvedRelativePath"]).is_absolute()
        for row in resolved
    )
    assert all(
        ".." not in Path(row["ResolvedRelativePath"]).parts for row in resolved
    )
    run_manifest = next(
        row
        for row in rows
        if row["RequestedFileName"] == "full_stack_run_manifest.csv"
    )
    assert run_manifest["Status"] == "PASS"
    assert (
        run_manifest["ResolvedRelativePath"]
        == "reports/csv/full_stack_run_manifest.csv"
    )
    assert run_manifest["ResolutionMethod"] in {
        "MANIFEST_ARTIFACT_ID",
        "EXACT_RELATIVE_PATH",
        "SOURCE_MANIFEST_ARTIFACT_ID_CURRENT_SNAPSHOT",
    }


def test_schema_adapter_registry_metadata_is_complete() -> None:
    rows = _csv("domain_adapter_results.csv")
    assert rows
    required = {
        "Domain",
        "SourceArtifact",
        "TargetArtifact",
        "SourceSchema",
        "TargetSchema",
        "RowsIn",
        "RowsOut",
        "Lossless",
        "DerivedColumns",
        "Status",
        "FailureCode",
        "SourceSHA256",
        "TargetSHA256",
    }
    assert required <= rows[0].keys()
    assert all(len(row["SourceSHA256"]) == 64 for row in rows)
    lossless = [
        row for row in rows if row["Lossless"].lower() in {"1", "true"}
    ]
    unsupported = [
        row for row in rows if row["Lossless"].lower() in {"0", "false"}
    ]
    assert lossless
    assert all(row["Status"] == "PASS" for row in lossless)
    assert all(len(row["TargetSHA256"]) == 64 for row in lossless)
    assert all(row["RowsOut"] for row in lossless)
    assert all(
        row["Status"] == "UNSUPPORTED"
        and row["FailureCode"] == "FULLSTACK:SchemaAdapterUnsupported"
        for row in unsupported
    )
    serialized = json.dumps(rows).lower()
    assert "fill_from_config" not in serialized
    assert "configured_value_substitution" not in serialized


def test_recovery_result_schemas_and_contract_counts() -> None:
    expected = {
        "full_stack_value_correctness_results.csv": (107, "CheckID"),
        "full_stack_component_coverage_results.csv": (163, "ComponentID"),
        "full_stack_subcase_status.csv": (31, "SubcaseID"),
        "full_stack_acceptance_results.csv": (387, "RuleID"),
        "full_stack_image_semantic_audit.csv": (10, "ImageFile"),
    }
    for name, (count, key) in expected.items():
        rows = _csv(name)
        assert len(rows) == count
        assert key in rows[0]
        assert "Status" in rows[0]
        assert len({row[key] for row in rows}) == count

    manifest = _csv("recovered_artifact_manifest.csv")
    assert manifest
    canonical = {
        "SchemaVersion",
        "RunID",
        "ArtifactID",
        "Domain",
        "SubcaseID",
        "RelativePath",
        "ArtifactType",
        "MIMEType",
        "Required",
        "Present",
        "Valid",
        "Status",
        "FailureCode",
        "SHA256",
        "ByteCount",
        "GeneratedUTC",
        "SourceArtifactIDs",
        "SourceCSVRelativePath",
        "SourceCSV_SHA256",
        "SemanticAuditStatus",
        "ProvenanceClass",
        "PublicationStatus",
        "ArtifactTypeSource",
    }
    assert canonical <= manifest[0].keys()
    present = [row for row in manifest if row["Present"].lower() in {"1", "true"}]
    assert all(
        row["ArtifactType"]
        in {
            "CSV",
            "PNG",
            "JSON",
            "YAML",
            "MAT",
            "LOG",
            "MARKDOWN",
            "TEXT",
            "OTHER",
        }
        for row in present
    )
    assert all(len(row["SHA256"]) == 64 for row in present)


def test_parent_child_status_consistency() -> None:
    subcases = _csv("full_stack_subcase_status.csv")
    components = _csv("full_stack_component_coverage_results.csv")
    values = _csv("full_stack_value_correctness_results.csv")
    for subcase in subcases:
        if subcase["Status"] != "PASS":
            continue
        subcase_id = subcase["SubcaseID"]
        mandatory_components = [
            row
            for row in components
            if row["SubcaseID"] == subcase_id
            and row["Mandatory"].lower() in {"1", "true"}
        ]
        mandatory_values = [
            row
            for row in values
            if row["SubcaseID"] == subcase_id
            and row["Required"].lower() in {"1", "true"}
        ]
        assert mandatory_components
        assert mandatory_values
        assert all(row["Status"] == "PASS" for row in mandatory_components)
        assert all(
            row["CorrectnessChecked"].lower() in {"1", "true"}
            for row in mandatory_components
        )
        assert all(row["Status"] == "PASS" for row in mandatory_values)


def test_source_run_hashes_were_not_mutated() -> None:
    manifest = _manifest()
    lock = json.loads(
        (RECOVERY_ROOT / "meta" / "source_run_lock.json").read_text(
            encoding="utf-8"
        )
    )
    assert manifest["ExecutionCompletionStatus"] == "COMPLETED"
    assert lock["ReadOnly"] is True
    assert len(lock["SourceInventorySHA256"]) == 64
    assert (
        manifest["SourceInventorySHA256"]
        == lock["SourceInventorySHA256"]
    )
    assert manifest["SourceRunID"] == SOURCE_ROOT.name
    assert SOURCE_ROOT.is_dir()


def test_webgui_distinguishes_recovery_from_original() -> None:
    original = dash.filesystem_run_row_from_folder(SOURCE_ROOT)
    recovery = dash.filesystem_run_row_from_folder(RECOVERY_ROOT)
    assert original is not None
    assert recovery is not None
    assert original["run_id"] != recovery["run_id"]
    assert original["profile_name"] == "full_stack_qualification"
    assert recovery["profile_name"] == "full_stack_qualification_recovery"
    status = json.loads(recovery["status_json"])
    assert status["qualification_recovery"] is True
    assert status["source_run_id"] == SOURCE_ROOT.name
    assert status["source_run_unchanged"] is True
    assert len(status["source_inventory_sha256"]) == 64


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
