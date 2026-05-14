from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402

DEFAULT_WAVEFORM_SCENARIO = "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_19site_57cell_570ue_60slot.yaml"


SCENARIO_ROOT = REPO_ROOT / "simulator" / "configs" / "scenarios"
VARIANT_ROOT = SCENARIO_ROOT / "variants"
EXPECTED_VARIANTS = [
    "SCN00_BASELINE_CAPACITY.yaml",
    "SCN01_CELL_EDGE_INTERFERENCE.yaml",
    "SCN02_HIGH_MOBILITY.yaml",
    "SCN03_XR_LATENCY.yaml",
    "SCN04_UL_CSI_SRS_STRESS.yaml",
    "SCN05_ENERGY_AWARE.yaml",
    "SCN06_AI_ML_BENCHMARK.yaml",
    "SCN07_LINK_LEVEL_REFERENCE_EQUIVALENT.yaml",
]


def main() -> None:
    root_yaml = SCENARIO_ROOT / "lls_6g_4ghz_100mhz_19site_3sector_100ue_uma.yaml"
    assert root_yaml.is_file(), f"Missing scenario-family root YAML: {root_yaml}"
    for name in EXPECTED_VARIANTS:
        path = VARIANT_ROOT / name
        assert path.is_file(), f"Missing scenario variant YAML: {path}"

    assert dash.DEFAULT_SCENARIO == DEFAULT_WAVEFORM_SCENARIO, (
        "Browser default scenario must point at the locked 4 GHz / 100 MHz / 19 site / 57 cell / 570 UE / 60 slot waveform scenario."
    )

    baseline, chain = dash.load_resolved_config_payload(dash.DEFAULT_SCENARIO)
    assert chain, "Resolved baseline scenario should retain a non-empty source chain."
    assert str(dash.path_get(baseline, "meta.scenario_group", "")) == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_19site_57cell_570ue_60slot"
    assert str(dash.path_get(baseline, "meta.scenario_id", "")) == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_19site_57cell_570ue_60slot"
    assert int(dash.path_get(baseline, "global_radio_scope.carrier_frequency_hz", 0)) == 4_000_000_000
    assert int(dash.path_get(baseline, "global_radio_scope.channel_bandwidth_hz", 0)) == 100_000_000
    assert str(dash.path_get(baseline, "global_radio_scope.duplex_mode", "")) == "TDD"
    assert int(dash.path_get(baseline, "global_radio_scope.numerology_mu", -1)) == 1
    assert int(dash.path_get(baseline, "frequency.n_size_grid", 0)) == 273
    assert str(dash.path_get(baseline, "frame_timing.tdd_pattern", "")) == "DDDSU"
    assert str(dash.path_get(baseline, "deployment_topology.cell_type", "")) == "UMa"
    assert int(dash.path_get(baseline, "deployment_topology.num_sites", 0)) == 19
    assert int(dash.path_get(baseline, "deployment_topology.num_sectors_per_site", 0)) == 3
    assert int(dash.path_get(baseline, "deployment_topology.num_cells", 0)) == 57
    assert int(dash.path_get(baseline, "deployment_topology.num_ues", 0)) == 570
    assert bool(dash.path_get(baseline, "deployment_topology.wraparound_enabled", False))
    assert bool(dash.path_get(baseline, "interference.inter_cell_interference_flag", False))
    assert str(dash.path_get(baseline, "interference.inter_cell_execution_mode", "")) == "full_per_link_channel_waveform_sum"
    assert str(dash.path_get(baseline, "run_control.execution_mode", "")) == "LLS"
    assert str(dash.path_get(baseline, "run_control.simulation_mode", "")) == "full_phy"
    assert str(dash.path_get(baseline, "run_control.run_profile", "")) == "exhaustive"
    assert dash.path_get(baseline, "run_control.total_frames", None) is None
    assert dash.path_get(baseline, "run_control.warmup_frames", None) is None
    assert dash.path_get(baseline, "run_control.measurement_frames", None) is None
    assert int(dash.path_get(baseline, "run_control.total_slots", 0)) == 60
    assert int(dash.path_get(baseline, "run_control.warmup_slots", 0)) == 1
    assert int(dash.path_get(baseline, "run_control.measurement_slots", 0)) == 59
    assert int(dash.path_get(baseline, "seeds.global_seed", 0)) == 104729
    assert str(dash.path_get(baseline, "scenario.runner_profile", "")) == "waveform_bundle"
    contract = dash.scenario_launch_contract(baseline, dash.DEFAULT_SCENARIO)
    assert contract["launch_allowed"] is True
    assert contract["launch_contract"] == "waveform_bundle_truth"
    assert str(dash.path_get(baseline, "users.beam_selection_strategy", "")) == "runtime_best_beam_per_link"
    assert list(dash.path_get(baseline, "scenario.bundle_anchor_cases", [])) == [
        "cell_search_mib_sib1",
        "prach_detection",
        "dl_pdsch_throughput",
        "ul_pusch_throughput",
        "ul_srs_channelest",
        "ul_lowpapr",
    ]
    assert int(dash.path_get(baseline, "users.n_users", 0)) == 570
    assert str(dash.path_get(baseline, "traffic.model", "")) == "fullBuffer"
    assert str(dash.path_get(baseline, "traffic.transport", "")) == "UDP"
    assert str(dash.path_get(baseline, "traffic.flowDirection", "")) == "BIDIR"
    assert str(dash.path_get(baseline, "output.backend", "")) == "mysql_web"
    assert not bool(dash.path_get(baseline, "output.emit_placeholder_artifacts", True))

    anchor_state, anchor_note = dash.classify_browser_field_support("scenario.bundle_anchor_cases")
    assert anchor_state == "secondary"
    assert "YAML-owned advanced control" in anchor_note

    browser_override = dash.canonicalize_browser_config_payload(dict(baseline))
    dash.path_set(browser_override, "system.scheduler.max_active_ues_per_slot", 1)
    dash.path_set(browser_override, "system.scheduler.fairness_alpha", 0.5)
    browser_override = dash.canonicalize_browser_config_payload(browser_override)
    assert int(dash.path_get(browser_override, "system.scheduler.maxActiveUEsPerSlot", 0)) == 1
    assert abs(float(dash.path_get(browser_override, "system.scheduler.fairnessAlpha", 0.0)) - 0.5) < 1e-9
    assert dash.path_get(browser_override, "system.scheduler.max_active_ues_per_slot", dash.PATH_MISSING) is dash.PATH_MISSING
    assert dash.path_get(browser_override, "system.scheduler.fairness_alpha", dash.PATH_MISSING) is dash.PATH_MISSING

    legacy, _ = dash.load_resolved_config_payload(dash.LEGACY_WAVEFORM_HONEST_SCENARIO)
    legacy_contract = dash.scenario_launch_contract(legacy, dash.LEGACY_WAVEFORM_HONEST_SCENARIO)
    assert legacy_contract["launch_allowed"] is False
    assert legacy_contract["launch_contract"] == "blocked_mislabeled_waveform_truth"

    promoted = dash.canonicalize_browser_config_payload(dict(legacy))
    dash.path_set(promoted, "scenario.runner_profile", "waveform_bundle")
    promoted_contract = dash.scenario_launch_contract(promoted, dash.LEGACY_WAVEFORM_HONEST_SCENARIO)
    assert promoted_contract["launch_allowed"] is True
    assert promoted_contract["launch_contract"] == "waveform_bundle_truth"
    assert "duplex_mode=TDD" in promoted_contract["launch_reason"]

    scn07, _ = dash.load_resolved_config_payload("variants/SCN07_LINK_LEVEL_REFERENCE_EQUIVALENT.yaml")
    assert str(dash.path_get(scn07, "meta.scenario_id", "")) == "SCN07_LINK_LEVEL_REFERENCE_EQUIVALENT"
    assert int(dash.path_get(scn07, "deployment_topology.num_cells", 0)) == 1
    assert int(dash.path_get(scn07, "users.n_users", 0)) == 1
    assert str(dash.path_get(scn07, "channel_model.scenario_label", "")) == "TDL-C"
    assert str(dash.path_get(scn07, "interference.inter_cell_execution_mode", "")) == "full_per_link_channel_waveform_sum"


if __name__ == "__main__":
    main()
