from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


SCENARIO = "lls_webgui_2cell_singlefile_full_lls_4ghz_100mhz.yaml"
SCENARIO_PATH = REPO_ROOT / "simulator" / "configs" / "scenarios" / SCENARIO


def _leaf_count(value: Any) -> int:
    if isinstance(value, dict):
        return sum(_leaf_count(child) for child in value.values())
    if isinstance(value, list):
        return max(1, sum(_leaf_count(child) for child in value))
    return 1


def test_webgui_singlefile_full_lls_yaml_is_self_contained_and_launchable() -> None:
    raw = yaml.safe_load(SCENARIO_PATH.read_text(encoding="utf-8"))

    assert "inherits" not in raw
    assert int(raw["meta"]["single_file_leaf_parameter_count_at_generation"]) >= 2000
    assert _leaf_count(raw) >= 2000
    assert raw["deployment_topology"]["num_cells"] == 2
    assert raw["deployment_topology"]["num_trps"] == 2
    assert raw["deployment_topology"]["num_sectors_per_site"] == 1
    assert raw["output"]["emit_placeholder_artifacts"] is False

    assert SCENARIO in dash.list_scenarios()
    resolved, chain = dash.load_resolved_config_payload(SCENARIO)
    assert chain == ["simulator/configs/scenarios/lls_webgui_2cell_singlefile_full_lls_4ghz_100mhz.yaml"]
    assert dash.path_get(resolved, "meta.scenario_id") == "lls_webgui_2cell_singlefile_full_lls_4ghz_100mhz"
    assert dash.path_get(resolved, "scenario.runner_profile") == "waveform_bundle"
    assert dash.path_get(resolved, "simulation.noise_operating_mode") == "receiver_noise_figure_thermal_noise"
    assert dash.path_get(resolved, "global_radio_scope.carrier_frequency_hz") == 4_000_000_000
    assert dash.path_get(resolved, "global_radio_scope.channel_bandwidth_hz") == 100_000_000

    contract = dash.scenario_launch_contract(resolved, SCENARIO)
    assert contract["launch_allowed"] is True
    assert contract["launch_contract"] == "waveform_bundle_truth"
