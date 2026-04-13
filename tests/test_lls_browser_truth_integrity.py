from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    header_cases = {
        "!Case": "Case",
        "!Direction": "Direction",
        "!ScenarioID": "ScenarioID",
        "+Direction": "Direction",
        "QStageOrder": "StageOrder",
        "ZCase": "Case",
        "c/uRelativePath": "RelativePath",
    }
    for raw, expected in header_cases.items():
        actual = dash.normalize_csv_header_name(raw)
        assert actual == expected, f"header normalization mismatch: {raw!r} -> {actual!r}, expected {expected!r}"

    artifacts = [
        {"logical_path": "reports/csv/scenario_summary.csv", "artifact_id": 10, "byte_size": 128},
        {"logical_path": "reports/csv/scenario_summary.csv", "artifact_id": 11, "byte_size": 0},
        {"logical_path": "reports/csv/scenario_summary.csv", "artifact_id": 12, "byte_size": 256},
        {"logical_path": "reports/csv/runtime_operating_mode.csv", "artifact_id": 7, "byte_size": 64},
    ]
    selected = dash.find_artifact_by_logical_path(artifacts, "reports/csv/scenario_summary.csv")
    assert selected is not None, "canonical artifact lookup failed to return a matching row"
    assert int(selected["artifact_id"]) == 12, "canonical artifact lookup must prefer the newest non-empty artifact"

    payload = {
        "frame": {"scs_khz": 15},
        "frequency": {"n_size_grid": 106},
        "bandwidth_operation": {"active_bandwidth_mode": "fullband", "supports_partial_band_activation": False},
        "resource_grid": {"num_rbs": 51},
        "global_radio_scope": {"numerology_mu": 1},
        "frame_timing": {"slot_duration_ms": 0.5, "slots_per_frame": 20},
    }
    resolved = dash.canonicalize_browser_config_payload(payload, keep_legacy_aliases=False)
    assert resolved["global_radio_scope"]["numerology_mu"] == 0, "browser canonicalization must derive mu from frame.scs_khz"
    assert resolved["frame_timing"]["slot_duration_ms"] == 1.0, "browser canonicalization must derive slot duration from mu"
    assert resolved["frame_timing"]["slots_per_frame"] == 10, "browser canonicalization must derive slots/frame from mu"
    assert resolved["frame_timing"]["symbols_per_slot"] == 14, "browser canonicalization must expose normal-CP symbols/slot explicitly"
    assert resolved["resource_grid"]["num_rbs"] == 106, "browser canonicalization must align the full-band grid with frequency.n_size_grid"

    runtime_rows = [
        {
            "Direction": "DL",
            "ConfiguredLinkAdaptationMode": "adaptive",
            "LinkAdaptationMode": "scheduler_grant_replay",
            "ConfiguredMCSSelectionPolicy": "cqi_driven",
            "ConfiguredMCSSelectionMode": "cqi_driven",
            "ActualMCSSelectionMode": "scheduler_grant",
            "SchedulerGrantMCSSelectionMode": "cqi_table",
            "RequestedOperatingPointSource": "cqi_link_adaptation",
            "AppliedOperatingPointSource": "scheduler_grant",
            "CQITable": "table1",
            "MCSTable": "qam64_table1",
            "ExecutionBackend": "WAVEFORM_LINK_BUNDLE",
            "PHYMode": "COUPLED_WAVEFORM_GRANT_EXECUTION",
            "WaveformPHYActive": "1",
            "ProxyPHYActive": "0",
            "FallbackUsed": "0",
            "TrafficFlowSource": "traffic.scalar_profile_fields",
            "TrafficFlowDerivationMode": "derived_from_scalar_traffic_config",
            "TrafficFlowResolvedFlag": "1",
        }
    ]

    orig_load_small = dash.load_small_csv_rows
    orig_load_first = dash.load_first_available_csv_rows
    try:
        def fake_load_small(artifacts_arg, logical_path, *, max_rows=64):
            if logical_path == "reports/csv/runtime_operating_mode.csv":
                return runtime_rows
            if logical_path == "reports/csv/truth_contract_summary.csv":
                return [{
                    "RuntimeTruthContractOk": "1",
                    "NoProxyPHYOk": "1",
                    "SyntheticBLERFallbackOk": "1",
                    "RawLifecycleOk": "1",
                    "FERRunScopeIdentityOk": "1",
                    "AMCNamingOk": "1",
                    "StrictTruthFailureCount": "0",
                }]
            if logical_path == "reports/csv/truth_contract_failures.csv":
                return []
            return []

        dash.load_small_csv_rows = fake_load_small
        dash.load_first_available_csv_rows = lambda artifacts_arg, logical_paths, *, max_rows=64: []

        run_row = {"run_id": 99, "status_text": "completed", "config_json": "{}"}
        runtime_context = dash.extract_runtime_context(
            run_row,
            artifacts=[
                {"logical_path": "reports/csv/runtime_operating_mode.csv", "artifact_id": 100, "byte_size": 128, "created_utc": "2026-04-12T00:00:00Z", "artifact_kind": "table_csv"},
                {"logical_path": "reports/csv/truth_contract_summary.csv", "artifact_id": 101, "byte_size": 256, "created_utc": "2026-04-12T00:00:00Z", "artifact_kind": "table_csv"},
                {"logical_path": "reports/csv/truth_contract_failures.csv", "artifact_id": 102, "byte_size": 64, "created_utc": "2026-04-12T00:00:00Z", "artifact_kind": "table_csv"},
            ],
        )
        assert runtime_context["operating_mode"][0]["ConfiguredMCSSelectionPolicy"] == "cqi_driven", (
            "browser live payload must preserve configured AMC policy separately from applied runtime fields"
        )
        assert runtime_context["operating_mode"][0]["ActualMCSSelectionMode"] == "scheduler_grant", (
            "browser live payload must preserve applied runtime AMC mode from runtime_operating_mode.csv"
        )
        assert runtime_context["truth_modes"]["execution_backend"] == "WAVEFORM_LINK_BUNDLE", (
            "browser live payload must expose waveform backend proof from runtime_operating_mode.csv"
        )
        assert runtime_context["truth_modes"]["waveform_phy_active"] is True, (
            "browser live payload must expose waveform PHY as active"
        )
        assert runtime_context["truth_modes"]["proxy_phy_active"] is False, (
            "browser live payload must expose proxy PHY as inactive"
        )
        assert runtime_context["truth_modes"]["fallback_used"] is False, (
            "browser live payload must expose fallback as unused"
        )
        assert runtime_context["truth_modes"]["traffic_flow_source"] == "traffic.scalar_profile_fields", (
            "browser live payload must expose traffic-flow ownership source from runtime_operating_mode.csv"
        )
        assert runtime_context["truth_modes"]["traffic_flow_derivation_mode"] == "derived_from_scalar_traffic_config", (
            "browser live payload must expose derived-vs-explicit traffic-flow mode"
        )
        assert runtime_context["truth_modes"]["traffic_flow_resolved_flag"] is True, (
            "browser live payload must expose resolved traffic-flow proof"
        )
        assert any("Scheduler grants are the applied operating-point authority" in note for note in runtime_context["notes"]), (
            "browser runtime notes must explain scheduler-grant applied authority without relabeling configured policy as actual"
        )
        assert runtime_context["truth_contract"]["summary"]["NoProxyPHYOk"] == "1", (
            "browser live payload must expose truth_contract_summary.csv from canonical artifacts"
        )
        assert runtime_context["truth_contract"]["failure_rows"] == [], (
            "browser live payload must not fabricate truth-contract failure rows when the failure artifact is empty"
        )
        assert any("Final truth-contract artifacts" in note for note in runtime_context["notes"]), (
            "browser runtime notes must explain final truth-contract artifacts are canonical DB-backed CSVs"
        )

        metrics = dash.extract_metric_cards(run_row, artifacts=[], runtime_context=runtime_context)
        metric_map = {item["label"]: item["value"] for item in metrics}
        assert metric_map["DL AMC Policy"] == "cqi_driven", "browser metric cards must surface configured AMC policy explicitly"
        assert metric_map["DL Requested Operating Point"] == "cqi_link_adaptation", (
            "browser metric cards must preserve requested operating-point source explicitly"
        )
        assert metric_map["DL Applied AMC Mode"] == "scheduler_grant", (
            "browser metric cards must not replace applied AMC mode with configured policy"
        )
        assert metric_map["DL Applied Operating Point"] == "scheduler_grant", (
            "browser metric cards must preserve applied operating-point authority explicitly"
        )
        assert metric_map["DL Scheduler AMC Mode"] == "cqi_table", (
            "browser metric cards must preserve scheduler-grant AMC mode when present"
        )
        assert metric_map["Execution Backend"] == "WAVEFORM_LINK_BUNDLE", (
            "browser metric cards must surface runtime execution backend proof"
        )
        assert metric_map["Waveform PHY Active"] == "True", (
            "browser metric cards must surface active waveform PHY proof"
        )
        assert metric_map["Proxy PHY Active"] == "False", (
            "browser metric cards must surface inactive proxy PHY proof"
        )
        assert metric_map["Fallback Used"] == "False", (
            "browser metric cards must surface fallback-unused proof"
        )
        assert metric_map["Traffic Flow Source"] == "traffic.scalar_profile_fields", (
            "browser metric cards must surface traffic-flow ownership source"
        )
        assert metric_map["Traffic Flow Mode"] == "derived_from_scalar_traffic_config", (
            "browser metric cards must surface traffic-flow derivation mode"
        )
        assert metric_map["Traffic Flow Resolved"] == "True", (
            "browser metric cards must surface resolved traffic-flow proof"
        )
    finally:
        dash.load_small_csv_rows = orig_load_small
        dash.load_first_available_csv_rows = orig_load_first


if __name__ == "__main__":
    main()
