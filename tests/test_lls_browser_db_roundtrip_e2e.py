from __future__ import annotations

import sys
import time
import uuid
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


SCENARIO = "lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml"
TERMINAL_STATUSES = {"completed", "completed_with_failures", "failed", "aborted"}
ROUNDTRIP_ARTIFACTS = (
    "reports/csv/config_roundtrip_verification.csv",
    "reports/csv/browser_runtime_db_consistency.csv",
    "reports/csv/summary_vs_raw_consistency.csv",
    "reports/csv/value_source_audit.csv",
    "reports/csv/scenario_summary.csv",
    "reports/csv/truth_contract_summary.csv",
    "reports/csv/truth_contract_failures.csv",
)


def _read_log_tail(log_file: Path | None, limit: int = 80) -> str:
    if log_file is None or not log_file.is_file():
        return ""
    lines = log_file.read_text(encoding="utf-8", errors="replace").splitlines()
    return "\n".join(lines[-limit:])


def _require_db_available() -> None:
    try:
        with dash.db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
    except Exception as exc:  # pragma: no cover - failure path prints real environment issue.
        raise AssertionError(
            "Real browser->DB roundtrip test requires the configured MySQL database; "
            f"connection failed for {dash.MYSQL_HOST}:{dash.MYSQL_PORT}/{dash.MYSQL_DATABASE}: {exc}"
        ) from exc


def _bounded_roundtrip_payload() -> dict:
    payload, _ = dash.load_resolved_config_payload(SCENARIO)
    payload.setdefault("simulation", {}).update(
        {
            "n_frames": 1,
            "n_slots": 1,
            "n_subframes": 1,
            "monte_carlo_iterations": 1,
            "random_seed": 73040,
            "snr_db": 8,
            "snr_sweep_offsets_db": [0],
            "noise_operating_mode": "receiver_noise_figure_thermal_noise",
        }
    )
    payload.setdefault("run_control", {}).update(
        {
            "execution_mode": "LLS",
            "num_workers": 1,
            "batch_size_links": 1,
        }
    )
    payload.setdefault("deployment_topology", {}).update(
        {
            "layout_type": "hex_grid",
            "inter_site_distance": 640,
            "num_cells": 3,
            "num_ues": 4,
            "num_trps": 3,
        }
    )
    payload.setdefault("users", {}).update(
        {
            "enabled": True,
            "n_users": 4,
            "execution_model": "slot_coupled_truth",
            "beam_selection_strategy": "fixed_first_beam",
            "save_user_tables": True,
        }
    )
    payload.setdefault("mobility", {}).update(
        {
            "ue_speed_kmh": 42,
            "trajectory_model": "zigzag",
            "update_period_s": 0.001,
        }
    )
    payload.setdefault("channels", {}).update(
        {
            "doppler_source_mode": "derive_from_ue_speed",
            "mobility_kmph": 42,
        }
    )
    payload.setdefault("interference", {}).update(
        {"inter_cell_execution_mode": "full_per_link_channel_waveform_sum"}
    )
    payload.setdefault("receiver", {}).update({"use_ideal_timing_sync": True})
    payload.setdefault("control_gating", {}).update(
        {
            "pbch_required": True,
            "prach_required": True,
            "pdcch_required": True,
            "srs_required": True,
            "srs_max_age_slots": 5,
            "trs_required": True,
            "trs_max_age_slots": 6,
        }
    )
    payload.setdefault("csi_acquisition_and_reporting", {}).update(
        {
            "channel_state_information_mode": "PMI+CQI",
            "cqi_policy": "baseline",
            "pmi_policy": "baseline",
            "ri_policy": "disabled",
            "cri_policy": "disabled",
            "report_payload_mode": "compressed",
            "crc_attached_mode": True,
            "crc_free_mode": False,
            "pmi_codebook_mode": "type1_su_mimo",
        }
    )
    payload.setdefault("reference_signals", {}).update(
        {
            "channel_state_information_mode": "PMI+CQI",
            "csi_feedback_mode": "PMI+CQI",
            "cqi_reporting_enabled": True,
            "pmi_reporting_enabled": True,
            "ri_reporting_enabled": False,
            "cri_reporting_enabled": False,
        }
    )
    payload.setdefault("link_adaptation", {}).update({"cqi_table": "table2"})
    payload.setdefault("output", {}).update(
        {
            "profile": "lls_config_roundtrip_runtime_artifacts",
            "save_figures": False,
            "save_png": False,
            "save_mat": False,
        }
    )
    return payload


def _wait_for_terminal_run(run_tag: str, log_file: Path, timeout_s: int = 480) -> dict:
    deadline = time.monotonic() + timeout_s
    last_row: dict | None = None
    while time.monotonic() < deadline:
        rows = dash.fetch_runs(limit=5, run_tag=run_tag)
        if rows:
            last_row = rows[0]
            status = str(last_row.get("status_text") or "").strip().lower()
            if status in TERMINAL_STATUSES:
                return last_row
        time.sleep(3)
    raise AssertionError(
        f"Timed out waiting for browser-owned DB run tag {run_tag!r}. "
        f"Last DB row: {last_row!r}\nMATLAB log tail:\n{_read_log_tail(log_file)}"
    )


def _row_by_name(rows: list[dict], parameter_name: str) -> dict:
    for row in rows:
        if str(row.get("ParameterName") or "") == parameter_name:
            return row
    raise AssertionError(f"Missing roundtrip row for {parameter_name!r}.")


def _text(value) -> str:
    return str(value if value is not None else "").strip()


def _is_one(value) -> bool:
    try:
        return abs(float(value) - 1.0) < 1e-9
    except (TypeError, ValueError):
        return _text(value).lower() == "true"


def _is_zero(value) -> bool:
    try:
        return abs(float(value)) < 1e-9
    except (TypeError, ValueError):
        return _text(value).lower() in {"false", ""}


def _assert_no_roundtrip_mismatches(roundtrip: dict) -> None:
    summary = roundtrip["summary"]
    for key in (
        "config_roundtrip_mismatches",
        "browser_runtime_db_mismatches",
        "summary_vs_raw_mismatches",
        "value_source_audit_mismatches",
    ):
        assert int(summary.get(key) or 0) == 0, f"{key} must be zero for the clean DB/browser roundtrip."
    for family, rows in roundtrip["mismatch_rows"].items():
        assert rows == [], f"{family} must not expose mismatch rows: {rows!r}"


def main() -> None:
    _require_db_available()
    run_tag = f"test_browser_db_roundtrip_{uuid.uuid4().hex[:12]}"
    payload = _bounded_roundtrip_payload()
    yaml_text = yaml.safe_dump(payload, sort_keys=False)

    runtime_path: Path | None = None
    try:
        token, log_file, runtime_path = dash.launch_run_from_yaml(SCENARIO, yaml_text, run_tag)
        assert token == run_tag, "The browser run token must match the unique run tag used for DB polling."
        assert runtime_path.is_file(), "Browser runtime overlay/YAML snapshot must be written before MATLAB launch."

        run_index_row = _wait_for_terminal_run(run_tag, log_file)
        run_id = int(run_index_row["run_id"])
        run_row = dash.fetch_run(run_id)
        assert run_row is not None, f"Run {run_id} must be fetchable from the DB."
        assert str(run_row.get("status_text") or "").strip().lower() == "completed", (
            f"Browser-owned run must complete cleanly. DB row: {run_row!r}\nMATLAB log tail:\n{_read_log_tail(log_file)}"
        )
    finally:
        if runtime_path is not None:
            runtime_path.unlink(missing_ok=True)

    stored_config = dash.parse_config_json(run_row)
    submitted = stored_config.get("lls6g", {}).get("submittedScenarioConfig", {})
    assert submitted.get("deployment_topology", {}).get("layout_type") == "hex_grid", (
        "DB sim_runs.config_json must store the browser-submitted layout_type, not only a filesystem artifact."
    )
    assert submitted.get("run_control", {}).get("num_workers") == 1, (
        "DB sim_runs.config_json must store browser-submitted num_workers=1."
    )

    dash.clear_dashboard_caches(run_id)
    artifacts = dash.fetch_artifacts(run_id)
    artifact_paths = {str(artifact.get("logical_path") or "") for artifact in artifacts}
    for logical_path in ROUNDTRIP_ARTIFACTS:
        assert logical_path in artifact_paths, f"DB artifact store must contain canonical artifact {logical_path}."

    live_payload = dash.build_live_payload(run_id)
    runtime_context = live_payload["runtime_context"]
    roundtrip = runtime_context["roundtrip_artifacts"]
    _assert_no_roundtrip_mismatches(roundtrip)
    truth_contract = runtime_context["truth_contract"]
    truth_summary = truth_contract["summary"]
    assert truth_summary, "Browser runtime context must expose truth_contract.summary from the canonical DB artifact."
    assert _is_one(truth_summary.get("RuntimeTruthContractOk")), "truth_contract_summary.csv must report RuntimeTruthContractOk=1 for the clean E2E run."
    assert _is_one(truth_summary.get("NoProxyPHYOk")), "truth_contract_summary.csv must prove no proxy PHY is active."
    assert _is_one(truth_summary.get("SyntheticBLERFallbackOk")), "truth_contract_summary.csv must prove no synthetic BLER fallback is active."
    assert _is_one(truth_summary.get("RawLifecycleOk")), "truth_contract_summary.csv must prove raw trial lifecycle finalization is OK."
    assert _is_one(truth_summary.get("FERRunScopeIdentityOk")), "truth_contract_summary.csv must prove run-scope FER identity is clean."
    assert _is_one(truth_summary.get("AMCNamingOk")), "truth_contract_summary.csv must prove AMC naming/source separation is OK."
    assert truth_contract["failure_rows"] == [], "Clean E2E run must not fabricate truth-contract failure rows."

    summary = live_payload["summary"]
    assert _is_one(summary.get("result_ok")), "Browser summary must report ResultOk=1 only for a clean truth contract."
    assert _is_zero(summary.get("required_failure_count")), "Browser summary must show RequiredFailureCount=0."
    assert _is_one(summary.get("runtime_truth_contract_ok")), "Browser summary must show RuntimeTruthContractOk=1."
    assert _is_zero(summary.get("roundtrip_mismatch_count")), "Browser summary must show RoundtripMismatchCount=0."

    config_rows = roundtrip["config_roundtrip_verification"]
    layout_row = _row_by_name(config_rows, "deployment_topology.layout_type")
    assert layout_row["BrowserSubmittedValue"] == "hex_grid"
    assert layout_row["RuntimeOverlayValue"] == "hex_grid"
    assert layout_row["ResolvedMATLABValue"] == "hex_grid"
    assert layout_row["RuntimeEvidenceField"] == "LayoutType", (
        "layout_type must be compared against LayoutType runtime evidence, not NumSites or another concept."
    )
    assert layout_row["RuntimeEvidenceValue"] == "hex_grid"

    workers_row = _row_by_name(config_rows, "run_control.num_workers")
    assert _is_one(workers_row["BrowserSubmittedValue"])
    assert _is_one(workers_row["RuntimeOverlayValue"])
    assert _is_one(workers_row["ResolvedMATLABValue"])
    assert workers_row["RuntimeEvidenceField"] == "ConfiguredWorkers"
    assert _is_one(workers_row["RuntimeEvidenceValue"]), "num_workers must not resolve 1 -> 0 in runtime evidence."

    for parameter_name, expected_policy, expected_derived in (
        ("csi_acquisition_and_reporting.cqi_policy", "baseline", "1"),
        ("csi_acquisition_and_reporting.pmi_policy", "baseline", "1"),
        ("csi_acquisition_and_reporting.ri_policy", "disabled", "0"),
        ("csi_acquisition_and_reporting.cri_policy", "disabled", "0"),
    ):
        row = _row_by_name(config_rows, parameter_name)
        assert row["ResolvedMATLABValue"] == expected_policy, (
            f"{parameter_name} must remain a policy token and not collapse into a boolean."
        )
        assert row["ResolvedMATLABValueRole"] == "resolved"
        assert abs(float(row["DerivedValue"]) - float(expected_derived)) < 1e-9
        assert row["DerivedValueRole"] == "derived"

    assert runtime_context["config_snapshot"]["submitted_present"], (
        "Browser payload must show the DB-backed submitted config snapshot is present."
    )
    assert any("Roundtrip verifier artifacts" in note for note in runtime_context["notes"]), (
        "Browser runtime context must explicitly state that roundtrip verifier artifacts are surfaced."
    )


if __name__ == "__main__":
    main()
