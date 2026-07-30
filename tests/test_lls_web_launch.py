from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

pytestmark = pytest.mark.webgui_unit


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402

DEFAULT_WAVEFORM_SCENARIO = "master_geometry_based.yaml"
MASTER_SCENARIO = "master_geometry_based.yaml"


def main() -> None:
    text = (REPO_ROOT / "apps" / "lls_web_dashboard.py").read_text(encoding="utf-8")
    assert 'parsed.path != "/run"' in text
    assert 'launch_run_from_yaml(scenario_name, yaml_text, run_tag)' in text
    assert "enforce_browser_launch_contract" in text
    assert "run_6g_phy_lls_single" in text
    assert dash.DEFAULT_SCENARIO == DEFAULT_WAVEFORM_SCENARIO
    assert dash.DEFAULT_DASHBOARD_HOST == "0.0.0.0"
    assert dash.DEFAULT_DASHBOARD_PORT == 62906
    assert 'dashboard_listener.json' in text
    assert '"/api/parameter-constraints"' in text
    assert "dashboard_browser_url" in text
    assert "webbrowser.open(browser_url)" in text
    local_url, intranet_url, _ = dash.resolve_dashboard_urls("0.0.0.0", dash.DEFAULT_DASHBOARD_PORT, "10.64.253.106")
    assert local_url == "http://127.0.0.1:62906/"
    assert intranet_url == "http://10.64.253.106:62906/"
    assert dash.dashboard_browser_url("0.0.0.0", local_url, intranet_url, "") == intranet_url
    assert dash.dashboard_browser_url("localhost", local_url, intranet_url, "") == local_url
    payload = {
        "run_control": {"execution_mode": "LLS", "total_slots": 100},
        "simulation": {"n_slots": 100, "n_frames": 5},
        "_download_metadata": {"scenario": dash.DEFAULT_SCENARIO},
    }
    normalized = dash.normalize_run_yaml(
        __import__("json").dumps(payload),
        dash.DEFAULT_SCENARIO,
    )
    assert "_download_metadata" not in normalized
    assert '"total_slots": 100' in normalized
    assert '"n_slots": 100' in normalized
    original_mysql_available = dash.dashboard_mysql_available
    try:
        dash.dashboard_mysql_available = lambda: (True, "connected")
        catalog_runtime = json.loads(dash.normalize_run_yaml("", dash.DEFAULT_SCENARIO))
    finally:
        dash.dashboard_mysql_available = original_mysql_available
    assert catalog_runtime["inherits"] == [f"./{dash.DEFAULT_SCENARIO}"]
    assert catalog_runtime["output"]["backend"] == "mysql_web"
    assert catalog_runtime["output"]["persistence_mode"] == "both"
    assert catalog_runtime["output"]["persist_to_database"] is True

    master_base, _ = dash.load_resolved_config_payload(MASTER_SCENARIO)
    assert dash.path_get(master_base, "deployment_topology.num_cells") == 2
    assert dash.path_get(master_base, "deployment_topology.num_ues") == 2
    assert dash.path_get(master_base, "prach.configuration_index") == 157
    assert dash.path_get(master_base, "prach.format") == "B4"
    master_runtime_request = {
        "inherits": [f"./{MASTER_SCENARIO}"],
        "canonical_control": {
            "identity": {
                "scenario_name": "WebGUI inherited master regression",
                "description": "Runtime overlay changes slots and mobility only.",
            },
            "run": {
                "n_frames": 5,
                "total_slots": 100,
                "warmup_slots": 0,
                "measurement_slots": 100,
                "n_subframes": 50,
                "min_duration_s": 0.05,
            },
            "channel": {
                "mobility_kmph": 200,
                "doppler_hz": 741.2535448847824,
            },
            "mobility": {
                "ue_speed_kmh": 200,
                "speed_profile": "linear_200kmph",
            },
            "runtime_overrides": [
                {"path": "channels.max_doppler_hz", "value": 741.2535448847824},
                {"path": "scenario.mobility.speed_kmh", "value": 200},
                {"path": "random_access.speed_kmh", "value": 100},
            ],
        },
        "output": {"persistence_mode": "both"},
    }
    try:
        dash.dashboard_mysql_available = lambda: (True, "connected")
        master_runtime = json.loads(
            dash.normalize_run_yaml(
                __import__("yaml").safe_dump(master_runtime_request, sort_keys=False),
                MASTER_SCENARIO,
            )
        )
    finally:
        dash.dashboard_mysql_available = original_mysql_available
    assert master_runtime["inherits"] == [f"./{MASTER_SCENARIO}"]
    assert dash.path_get(master_runtime, "deployment_topology.num_cells") is dash.PATH_MISSING
    assert dash.path_get(master_runtime, "deployment_topology.num_ues") is dash.PATH_MISSING
    assert dash.path_get(master_runtime, "random_access.configuration_index") is dash.PATH_MISSING
    assert dash.path_get(master_runtime, "random_access.prach_format") is dash.PATH_MISSING
    assert dash.path_get(master_runtime, "random_access.channel_model") is dash.PATH_MISSING
    assert dash.path_get(master_runtime, "mobility.ue_speed_kmh") == 200
    runtime_overrides = dash.path_get(master_runtime, "canonical_control.runtime_overrides", [])
    by_path = {
        str(item.get("path")): item.get("value")
        for item in runtime_overrides
        if isinstance(item, dict) and item.get("path")
    }
    assert by_path["sweeps_and_matrix.snr_sweep.enabled"] is False
    assert by_path["sweeps_and_matrix.snr_sweep.values_db"] == []
    assert by_path["channels.max_doppler_hz"] == 741.2535448847824
    assert by_path["scenario.mobility.speed_kmh"] == 200

    honest_payload, _ = dash.load_resolved_config_payload(dash.DEFAULT_SCENARIO)
    honest_contract = dash.scenario_launch_contract(honest_payload, dash.DEFAULT_SCENARIO)
    assert honest_contract["launch_allowed"] is True
    assert honest_contract["launch_contract"] == "waveform_bundle_truth"

    legacy_payload, _ = dash.load_resolved_config_payload(dash.LEGACY_WAVEFORM_HONEST_SCENARIO)
    legacy_contract = dash.scenario_launch_contract(legacy_payload, dash.LEGACY_WAVEFORM_HONEST_SCENARIO)
    assert legacy_contract["launch_allowed"] is False
    assert legacy_contract["launch_contract"] == "blocked_mislabeled_waveform_truth"

    overridden = dash.canonicalize_browser_config_payload(dict(legacy_payload))
    dash.path_set(overridden, "scenario.runner_profile", "waveform_bundle")
    promoted_contract = dash.scenario_launch_contract(overridden, dash.LEGACY_WAVEFORM_HONEST_SCENARIO)
    assert promoted_contract["launch_allowed"] is True
    assert promoted_contract["launch_contract"] == "waveform_bundle_truth"
    assert "canonical slot accounting" in promoted_contract["launch_reason"]

    single_user_waveform = dash.canonicalize_browser_config_payload(dict(legacy_payload))
    dash.path_set(single_user_waveform, "scenario.runner_profile", "waveform_bundle")
    dash.path_set(single_user_waveform, "users.n_users", 1)
    dash.path_set(single_user_waveform, "deployment_topology.num_ues", 1)
    dash.path_set(single_user_waveform, "users.execution_model", "independent_link_sweep")
    single_user_contract = dash.scenario_launch_contract(single_user_waveform, dash.LEGACY_WAVEFORM_HONEST_SCENARIO)
    assert single_user_contract["launch_allowed"] is True
    assert single_user_contract["launch_contract"] == "waveform_bundle_truth"


if __name__ == "__main__":
    main()
