from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


SNR_SWEEP_SCENARIO = "master_sinr_sweep.yaml"
GEOMETRY_SCENARIO = "master_geometry_based.yaml"


def test_webgui_lists_new_lls_scenario_modes() -> None:
    scenarios = dash.list_scenarios()
    assert SNR_SWEEP_SCENARIO in scenarios
    assert GEOMETRY_SCENARIO in scenarios
    assert dash.OPERATOR_MASTER_SCENARIOS == (
        SNR_SWEEP_SCENARIO,
        GEOMETRY_SCENARIO,
    )
    assert not any(name.endswith("_smoke.yaml") for name in scenarios)


def test_webgui_snr_sweep_metadata_and_label() -> None:
    meta = dash.scenario_catalog_metadata(SNR_SWEEP_SCENARIO)

    assert meta["run_class"] == "fixed_snr_sweep_lls"
    assert meta["runner_profile"] == "waveform_bundle"
    assert meta["launch_allowed"] is True
    assert meta["sweep_enabled"] is True
    assert meta["fixed_link_campaign_enabled"] is True
    assert meta["geometry_enabled"] is False
    assert meta["channel_model"] == "AWGN"
    assert meta["num_ues"] == 1

    label = dash.scenario_dropdown_label(SNR_SWEEP_SCENARIO)
    assert "SNR" in label or "SINR" in label
    assert "AWGN" in label
    assert "1 UE" in label


def test_webgui_geometry_metadata_and_label() -> None:
    meta = dash.scenario_catalog_metadata(GEOMETRY_SCENARIO)

    assert meta["run_class"] == "ue_placement_geometry_lls"
    assert meta["runner_profile"] == "waveform_bundle"
    assert meta["launch_allowed"] is True
    assert meta["sweep_enabled"] is False
    assert meta["geometry_enabled"] is True
    assert meta["num_cells"] == 2
    assert meta["num_ues"] == 2
    assert meta["speed_kmh"] == 200

    label = dash.scenario_dropdown_label(GEOMETRY_SCENARIO)
    assert "Geometry" in label
    assert "2 Cell" in label
    assert "2 UE" in label
    assert "200 km/h" in label


def test_home_page_surfaces_scenario_validation_mode_panel() -> None:
    page = dash.build_home_page(SNR_SWEEP_SCENARIO).decode("utf-8")

    assert "Scenario Validation Mode" in page
    assert SNR_SWEEP_SCENARIO in page
    assert "Fixed SNR/SINR Sweep" in page
