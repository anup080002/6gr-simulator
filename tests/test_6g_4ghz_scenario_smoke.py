from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    baseline, _ = dash.load_resolved_config_payload(dash.DEFAULT_SCENARIO)
    browser_payload = dash.canonicalize_browser_config_payload(baseline, keep_legacy_aliases=False)

    assert str(dash.path_get(browser_payload, "meta.scenario_group", "")) == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    assert int(dash.path_get(browser_payload, "global_radio_scope.carrier_frequency_hz", 0)) == 4_000_000_000
    assert int(dash.path_get(browser_payload, "global_radio_scope.channel_bandwidth_hz", 0)) == 100_000_000
    assert int(dash.path_get(browser_payload, "deployment_topology.num_sites", 0)) == 7
    assert int(dash.path_get(browser_payload, "deployment_topology.num_cells", 0)) == 21
    assert int(dash.path_get(browser_payload, "deployment_topology.num_ues", 0)) == 200
    assert str(dash.path_get(browser_payload, "system.scheduler.type", "")) == "PF"
    assert str(dash.path_get(browser_payload, "traffic.model", "")) == "fullBuffer"
    assert str(dash.path_get(browser_payload, "run_control.simulation_mode", "")) == "full_phy"
    assert str(dash.path_get(browser_payload, "run_control.run_profile", "")) == "exhaustive"
    assert int(dash.path_get(browser_payload, "run_control.total_slots", 0)) == 20
    assert str(dash.path_get(browser_payload, "users.beam_selection_strategy", "")) == "runtime_best_beam_per_link"
    contract = dash.scenario_launch_contract(browser_payload, dash.DEFAULT_SCENARIO)
    assert contract["presentation_label"] == "Waveform bundle truth"
    assert contract["launch_allowed"] is True

    active_paths = [
        "run_control.study_mode",
        "run_control.simulation_mode",
        "frequency.center_frequency_hz",
        "deployment_topology.num_sites",
        "users.n_users",
        "users.beam_selection_strategy",
        "system.scheduler.type",
        "traffic.model",
        "traffic.fullBufferBitsPerTTI",
        "interference.inter_cell_interference_flag",
        "reference_signals.trs_enabled",
        "energy_efficiency.tx_power_dbm",
    ]
    for path in active_paths:
        state, note = dash.classify_browser_field_support(path)
        assert state == "active", f"{path} should be browser-active for the 6G study family"
        assert note, f"{path} should carry a browser support explanation"

    handover_state, _ = dash.classify_browser_field_support("system.handover.enable")
    assert handover_state == "secondary", (
        "Handover control should stay clearly labeled as resolved/secondary until the coupled runtime owns full A3-style interruption semantics."
    )

    page = dash.build_home_page(dash.DEFAULT_SCENARIO, "", user_profile=None).decode("utf-8", errors="ignore")
    assert "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame" in page, "Home page must surface the locked scenario identity."
    assert "Waveform bundle truth" in page
    for token in (
        "run_control.study_mode",
        "run_control.simulation_mode",
        "deployment_topology.num_sites",
        "deployment_topology.num_cells",
        "users.n_users",
        "system.scheduler.type",
        "traffic.model",
    ):
        assert token in page, f"Home page must expose {token} for browser editing."


if __name__ == "__main__":
    main()
