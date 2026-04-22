from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


SCENARIO = "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_50ue_14slot.yaml"


def main() -> None:
    assert dash.DEFAULT_SCENARIO == SCENARIO
    payload, chain = dash.load_resolved_config_payload(SCENARIO)
    assert chain, "Resolved source chain must not be empty."

    assert str(dash.path_get(payload, "meta.scenario_id", "")) == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_50ue_14slot"
    assert str(dash.path_get(payload, "scenario.runner_profile", "")) == "waveform_bundle"
    assert int(dash.path_get(payload, "global_radio_scope.carrier_frequency_hz", 0)) == 4_000_000_000
    assert int(dash.path_get(payload, "global_radio_scope.channel_bandwidth_hz", 0)) == 100_000_000
    assert int(dash.path_get(payload, "frequency.n_size_grid", 0)) == 273
    assert str(dash.path_get(payload, "frame_timing.tdd_pattern", "")) == "DDDSU"

    assert int(dash.path_get(payload, "deployment_topology.num_sites", 0)) == 2
    assert int(dash.path_get(payload, "deployment_topology.num_base_stations", 0)) == 2
    assert int(dash.path_get(payload, "deployment_topology.num_sectors_per_site", 0)) == 3
    assert int(dash.path_get(payload, "deployment_topology.num_cells", 0)) == 6
    assert int(dash.path_get(payload, "deployment_topology.num_ues", 0)) == 50
    assert bool(dash.path_get(payload, "deployment_topology.wraparound_enabled", False))

    assert int(dash.path_get(payload, "run_control.total_slots", 0)) == 14
    assert int(dash.path_get(payload, "run_control.warmup_slots", 0)) == 1
    assert int(dash.path_get(payload, "simulation.n_slots", 0)) == 14
    assert int(dash.path_get(payload, "simulation.n_frames", 0)) == 1

    assert int(dash.path_get(payload, "users.n_users", 0)) == 50
    assert str(dash.path_get(payload, "users.execution_model", "")) == "slot_coupled_truth"
    assert str(dash.path_get(payload, "traffic.model", "")) == "fullBuffer"
    assert str(dash.path_get(payload, "traffic.transport", "")) == "UDP"
    assert str(dash.path_get(payload, "traffic.flowDirection", "")) == "BIDIR"
    flows = dash.path_get(payload, "traffic.flows", [])
    assert isinstance(flows, list) and flows, "Traffic flow list must be present."
    assert int((flows[0] or {}).get("ue_count", 0)) == 50
    assert str(dash.path_get(payload, "output.backend", "")) == "mysql_web"

    contract = dash.scenario_launch_contract(payload, SCENARIO)
    assert contract["launch_allowed"] is True
    assert contract["launch_contract"] == "waveform_bundle_truth"


if __name__ == "__main__":
    main()
