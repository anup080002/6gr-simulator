from __future__ import annotations

import sys
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


SCENARIO = "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_4000slot.yaml"


def main() -> None:
    scenario_path = REPO_ROOT / "simulator" / "configs" / "scenarios" / SCENARIO
    assert scenario_path.is_file(), f"Missing locked scenario: {scenario_path}"
    alias_path = REPO_ROOT / "configs" / "scenarios" / SCENARIO
    assert alias_path.is_file(), f"Missing compatibility alias: {alias_path}"

    raw = yaml.safe_load(scenario_path.read_text(encoding="utf-8"))
    assert raw["run_control"]["mode"] == "long_run"
    assert raw["run_control"]["total_slots"] == 4000
    assert raw["run_control"]["warmup_slots"] == 500
    assert raw["run_control"]["measurement_slots"] == 3500
    assert raw["run_control"]["deterministic_replay"] is True
    assert raw["seeds"]["global_seed"] == 104729
    assert raw["seeds"]["ue_placement_seed"] == 104760
    assert raw["frequency"]["center_frequency_hz"] == 4_000_000_000
    assert raw["frequency"]["bandwidth_hz"] == 100_000_000
    assert raw["frequency"]["duplex_mode"] == "TDD"
    assert raw["frame"]["scs_khz"] == 30
    assert raw["frame"]["tdd_pattern"] == "DDDSU"
    assert raw["deployment_topology"]["inter_site_distance"] == 600
    assert raw["deployment_topology"]["num_sites"] == 7
    assert raw["deployment_topology"]["num_cells"] == 21
    assert raw["deployment_topology"]["num_ues"] == 200
    assert raw["users"]["n_users"] == 200
    assert raw["traffic"]["model"] == "full_buffer"
    assert raw["traffic"]["transport"] == "UDP"
    assert raw["output"]["backend"] == "mysql_web"
    assert raw["output"]["emit_placeholder_artifacts"] is False
    assert raw["scenario"]["honesty_mode"] == "strict"
    assert raw["scenario"]["unsupported_output_policy"] == "show_unavailable_with_reason"

    assert dash.DEFAULT_SCENARIO == SCENARIO
    resolved, chain = dash.load_resolved_config_payload(SCENARIO)
    assert chain
    assert dash.path_get(resolved, "meta.scenario_id") == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_4000slot"
    assert dash.path_get(resolved, "global_radio_scope.carrier_frequency_hz") == 4_000_000_000
    assert dash.path_get(resolved, "global_radio_scope.channel_bandwidth_hz") == 100_000_000
    assert dash.path_get(resolved, "global_radio_scope.numerology_mu") == 1
    assert dash.path_get(resolved, "resource_grid.num_rbs") == 273
    assert dash.path_get(resolved, "deployment_topology.num_sites") == 7
    assert dash.path_get(resolved, "deployment_topology.num_cells") == 21
    assert dash.path_get(resolved, "deployment_topology.num_ues") == 200


if __name__ == "__main__":
    main()
