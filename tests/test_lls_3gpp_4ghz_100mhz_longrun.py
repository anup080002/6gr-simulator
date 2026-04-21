from __future__ import annotations

import sys
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


SCENARIO = "lls_3gpp_rel20_anchor_4ghz_100mhz_system_level_honest_200ue_1000slot.yaml"


def main() -> None:
    scenario_path = REPO_ROOT / "simulator" / "configs" / "scenarios" / SCENARIO
    assert scenario_path.is_file(), f"Missing locked scenario: {scenario_path}"
    alias_path = REPO_ROOT / "configs" / "scenarios" / SCENARIO
    assert alias_path.is_file(), f"Missing compatibility alias: {alias_path}"

    raw = yaml.safe_load(scenario_path.read_text(encoding="utf-8"))
    assert raw["inherits"] == ["./lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1000slot.yaml"]
    assert raw["meta"]["scenario_id"] == "lls_3gpp_rel20_anchor_4ghz_100mhz_system_level_honest_200ue_1000slot"
    assert raw["scenario"]["name"] == "lls_3gpp_rel20_anchor_4ghz_100mhz_system_level_honest_200ue_1000slot"
    assert raw["scenario"]["runner_profile"] == "system_level_lls"
    assert raw["output"]["profile"] == "lls_3gpp_rel20_anchor_4ghz_100mhz_system_level_honest_200ue_1000slot"

    assert dash.HONEST_SYSTEM_LEVEL_DEFAULT_SCENARIO == SCENARIO
    assert dash.DEFAULT_SCENARIO == dash.WAVEFORM_TRUTH_DEFAULT_SCENARIO
    resolved, chain = dash.load_resolved_config_payload(SCENARIO)
    assert chain
    assert dash.path_get(resolved, "meta.scenario_id") == "lls_3gpp_rel20_anchor_4ghz_100mhz_system_level_honest_200ue_1000slot"
    assert dash.path_get(resolved, "global_radio_scope.carrier_frequency_hz") == 4_000_000_000
    assert dash.path_get(resolved, "global_radio_scope.channel_bandwidth_hz") == 100_000_000
    assert dash.path_get(resolved, "global_radio_scope.numerology_mu") == 1
    assert dash.path_get(resolved, "resource_grid.num_rbs") == 273
    assert dash.path_get(resolved, "deployment_topology.num_sites") == 7
    assert dash.path_get(resolved, "deployment_topology.num_cells") == 21
    assert dash.path_get(resolved, "deployment_topology.num_ues") == 200
    assert dash.path_get(resolved, "traffic.model") == "fullBuffer"
    assert dash.path_get(resolved, "output.backend") == "mysql_web"


if __name__ == "__main__":
    main()
