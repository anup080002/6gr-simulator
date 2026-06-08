from __future__ import annotations

import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402

DEFAULT_WAVEFORM_SCENARIO = "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_19site_57cell_570ue_60slot.yaml"


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
