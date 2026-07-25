from __future__ import annotations

import copy
import sys
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


SCENARIO = "master_geometry_based.yaml"
SCENARIO_PATH = REPO_ROOT / "simulator" / "configs" / "scenarios" / SCENARIO


RUNTIME_MIRROR_SECTIONS = {
    "meta",
    "scenario",
    "simulation",
    "frequency",
    "frame",
    "global_radio_scope",
    "frame_timing",
    "deployment_topology",
    "users",
    "channels",
    "channel_model",
    "mobility",
    "antenna_and_array",
    "mimo",
    "system",
    "traffic",
    "reference_signals",
    "control",
    "random_access",
    "output",
    "output_control",
    "logging",
}


def test_webgui_geometry_master_is_self_contained_and_launchable() -> None:
    raw = yaml.safe_load(SCENARIO_PATH.read_text(encoding="utf-8"))

    assert "inherits" not in raw
    assert not (set(raw) & RUNTIME_MIRROR_SECTIONS)

    canonical = raw["canonical_control"]
    assert canonical["topology"]["num_cells"] == 2
    assert canonical["topology"]["num_trps"] == 2
    assert canonical["topology"]["num_sectors_per_site"] == 1
    assert canonical["topology"]["num_ues"] == 2
    assert canonical["channel"]["profile"] == "CDL-C"
    assert canonical["output"]["profiler_enabled"] is True
    assert canonical["random_access"]["n_cell_id"] == 1
    assert canonical["random_access"]["channel_model"] == "CDL-C"
    override_paths = [item["path"] for item in canonical["runtime_overrides"]]
    assert len(override_paths) == len(set(override_paths))

    assert SCENARIO in dash.list_scenarios()
    resolved, chain = dash.load_resolved_config_payload(SCENARIO)
    assert chain == ["simulator/configs/scenarios/master_geometry_based.yaml"]
    assert dash.path_get(resolved, "meta.scenario_id") == "master_geometry_based"
    assert dash.path_get(resolved, "scenario.runner_profile") == "waveform_bundle"
    assert dash.path_get(resolved, "deployment_topology.num_cells") == 2
    assert dash.path_get(resolved, "deployment_topology.num_trps") == 2
    assert dash.path_get(resolved, "deployment_topology.num_sectors_per_site") == 1
    assert dash.path_get(resolved, "deployment_topology.num_ues") == 2
    assert dash.path_get(resolved, "users.n_users") == 2
    assert dash.path_get(resolved, "users.execution_model") == "slot_coupled_truth"
    assert dash.path_get(resolved, "simulation.noise_operating_mode") == "receiver_noise_figure_thermal_noise"
    assert dash.path_get(resolved, "global_radio_scope.carrier_frequency_hz") == 4_000_000_000
    assert dash.path_get(resolved, "global_radio_scope.channel_bandwidth_hz") == 100_000_000
    assert dash.path_get(resolved, "channels.profile") == "CDL-C"
    assert dash.path_get(resolved, "channel_model.scenario_label") == "CDL-C"
    assert dash.path_get(resolved, "output.emit_placeholder_artifacts") is False
    assert dash.path_get(resolved, "output.profiler_enabled") is True
    assert dash.path_get(resolved, "output.profiler_top_functions") == 250
    assert dash.path_get(resolved, "output.profiler_top_edges") == 500
    assert dash.path_get(resolved, "output.live_publish_frame_interval") == 1
    assert dash.path_get(resolved, "output.live_heavy_refresh_interval_frames") == 1
    assert dash.path_get(resolved, "random_access.n_cell_id") == 1
    assert dash.path_get(resolved, "random_access.channel_model") == "CDL-C"
    assert dash.path_get(resolved, "random_access.timing_offset_sweep_samples") == [0, 4, 8]
    assert dash.path_get(resolved, "random_access.frequency_offset_sweep_hz") == [0, 100, 250]

    contract = dash.scenario_launch_contract(resolved, SCENARIO)
    assert contract["launch_allowed"] is True
    assert contract["launch_contract"] == "waveform_bundle_truth"


def test_webgui_singlefile_canonical_topology_derives_large_scale_runtime_view() -> None:
    resolved, _ = dash.load_resolved_config_payload(SCENARIO)
    large = copy.deepcopy(resolved)
    topology = large["canonical_control"]["topology"]
    topology["num_sites"] = 50
    topology["num_sectors_per_site"] = 3
    topology.pop("num_cells", None)
    topology.pop("num_trps", None)
    topology.pop("sector_azimuth_offsets_deg", None)
    topology["num_ues"] = 12000

    resolved = dash.canonicalize_browser_config_payload(large)

    assert dash.path_get(resolved, "deployment_topology.num_sites") == 50
    assert dash.path_get(resolved, "deployment_topology.num_sectors_per_site") == 3
    assert dash.path_get(resolved, "deployment_topology.num_cells") == 150
    assert dash.path_get(resolved, "deployment_topology.num_trps") == 150
    assert dash.path_get(resolved, "deployment_topology.num_ues") == 12000
    assert dash.path_get(resolved, "users.n_users") == 12000
    assert dash.path_get(resolved, "scenario.layout.nSites") == 50
    assert dash.path_get(resolved, "scenario.layout.nSectorsPerSite") == 3
    assert dash.path_get(resolved, "scenario.sectorization.azimOffsets_deg") == [0.0, 120.0, 240.0]


def test_webgui_singlefile_high_mobility_derives_cdlc_and_doppler() -> None:
    resolved, _ = dash.load_resolved_config_payload(SCENARIO)
    payload = copy.deepcopy(resolved)
    control = payload["canonical_control"]
    control["mobility"]["ue_speed_kmh"] = 100
    control["channel"]["mobility_kmph"] = 100
    control["channel"]["profile"] = "CDL-D"
    control["channel"]["los_enabled"] = True

    resolved = dash.canonicalize_browser_config_payload(payload)
    expected_doppler_hz = (100 / 3.6) * 4_000_000_000 / 299_792_458

    assert dash.path_get(resolved, "channels.profile") == "CDL-C"
    assert dash.path_get(resolved, "channel_model.scenario_label") == "CDL-C"
    assert abs(float(dash.path_get(resolved, "channels.doppler_hz")) - expected_doppler_hz) < 1e-6
    assert abs(float(dash.path_get(resolved, "channel_model.doppler_hz")) - expected_doppler_hz) < 1e-6
