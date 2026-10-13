from __future__ import annotations

import sys
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


SNR_SWEEP_SCENARIO = "master_sinr_sweep.yaml"
GEOMETRY_SCENARIO = "master_geometry_based.yaml"


def _merge_dicts(base: dict, overlay: dict) -> dict:
    merged = dict(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _merge_dicts(merged[key], value)
        else:
            merged[key] = value
    return merged


def _schema_paths(value: object, prefix: str = "") -> set[str]:
    paths: set[str] = set()
    if isinstance(value, dict):
        for key, child in value.items():
            path = f"{prefix}.{key}" if prefix else str(key)
            paths.add(path)
            paths.update(_schema_paths(child, path))
    elif isinstance(value, list):
        for child in value:
            if isinstance(child, (dict, list)):
                paths.update(_schema_paths(child, f"{prefix}[]"))
    return paths


def _load_master(name: str) -> dict:
    path = REPO_ROOT / "simulator" / "configs" / "scenarios" / name
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def test_webgui_lists_new_lls_scenario_modes() -> None:
    scenarios = dash.list_scenarios()
    assert SNR_SWEEP_SCENARIO in scenarios
    assert GEOMETRY_SCENARIO in scenarios
    assert dash.OPERATOR_MASTER_SCENARIOS == (
        SNR_SWEEP_SCENARIO,
        GEOMETRY_SCENARIO,
    )
    assert dash.DEFAULT_SCENARIO == SNR_SWEEP_SCENARIO
    assert tuple(item["id"] for item in dash.PRODUCT_SCENARIO_MODES) == (
        "sinr_sweep",
        "geometry_based",
    )
    assert not any(name.endswith("_smoke.yaml") for name in scenarios)


def test_operator_masters_have_complete_identical_parameter_surfaces() -> None:
    scenario_root = REPO_ROOT / "simulator" / "configs" / "scenarios"
    assert sorted(path.name for path in scenario_root.glob("master_*.yaml")) == [
        GEOMETRY_SCENARIO,
        SNR_SWEEP_SCENARIO,
    ]

    fixed = _load_master(SNR_SWEEP_SCENARIO)
    geometry = _load_master(GEOMETRY_SCENARIO)
    assert _schema_paths(fixed) == _schema_paths(geometry)
    for master in (fixed, geometry):
        probe = master["pucch_resources"]["component_probe"]
        assert probe["enabled"] is False
        assert probe["evidence_scope"] == "isolated_known_payload_not_causal_feedback"

    fixed_overrides = [
        row["path"] for row in fixed["canonical_control"]["runtime_overrides"]
    ]
    geometry_overrides = [
        row["path"] for row in geometry["canonical_control"]["runtime_overrides"]
    ]
    assert len(fixed_overrides) == len(set(fixed_overrides))
    assert len(geometry_overrides) == len(set(geometry_overrides))
    assert set(fixed_overrides) == set(geometry_overrides)

    schema_root = REPO_ROOT / "simulator" / "configs" / "schema"
    catalog: dict = {}
    catalog_paths = [schema_root / "scenario_parameter_catalog.yaml"]
    catalog_paths.extend(sorted(schema_root.glob("scenario_parameter_catalog_extension_*.yaml")))
    for path in catalog_paths:
        catalog = _merge_dicts(
            catalog,
            yaml.safe_load(path.read_text(encoding="utf-8")) or {},
        )

    for name, master in ((SNR_SWEEP_SCENARIO, fixed), (GEOMETRY_SCENARIO, geometry)):
        for section, payload in master.items():
            parameters = catalog.get("sections", {}).get(section, {}).get("parameters", {})
            if not parameters or not isinstance(payload, dict):
                continue
            expected = set(parameters)
            if section in {"pdsch", "pusch"}:
                # The catalog's PRB-list representation is mutually exclusive
                # with this master's explicit contiguous start/count allocation.
                expected.remove("prb_set")
                assert {"prb_start", "num_prb"} <= set(payload)
            assert not (expected - set(payload)), (
                name,
                section,
                sorted(expected - set(payload)),
            )


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


def test_component_probe_policy_survives_browser_roundtrip() -> None:
    for name in (SNR_SWEEP_SCENARIO, GEOMETRY_SCENARIO):
        authored = _load_master(name)
        expected = authored["pucch_resources"]["component_probe"].copy()
        resolved = dash.canonicalize_browser_config_payload(authored, keep_legacy_aliases=True)
        assert resolved["pucch_resources"]["component_probe"] == expected
        assert authored["pucch_resources"]["component_probe"] == expected


def test_webgui_blocks_geometry_flags_in_sinr_master_payload() -> None:
    payload, _ = dash.load_resolved_config_payload(SNR_SWEEP_SCENARIO)
    dash.path_set(payload, "canonical_control.launch.geometry_enabled", True)
    contract = dash.scenario_launch_contract(payload, SNR_SWEEP_SCENARIO)

    assert contract["launch_allowed"] is False
    assert contract["launch_contract"] == "blocked_mixed_sinr_geometry_mode"


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


def test_h4_connected_configuration_retains_fullband_adaptive_authority() -> None:
    # Configuration transport only; this is not waveform/rank qualification.
    for name in (
        "h4_100_cdlc100_connected_impaired_40db_gate.yaml",
        "h4_100_cdlc100_connected_impaired_snr_sweep.yaml",
    ):
        payload, _ = dash.load_resolved_config_payload(name)
        for _ in range(2):
            payload = dash.canonicalize_browser_config_payload(payload)
            for key in ("system.scheduler.maxPRBAllocationPerUE",
                        "scheduler.max_prbs_per_grant"):
                assert dash.path_get(payload, key) == 273
            assert dash.path_get(payload, "traffic.flows") == []
            assert dash.path_get(payload, "traffic.targetRate_Mbps") == 10000
            assert dash.path_get(payload, "canonical_control.mimo.max_dl_layers") == 4
            assert dash.path_get(payload, "canonical_control.mimo.max_ul_layers") == 4
            assert dash.path_get(payload, "link_adaptation.inner_loop_flag") is True
            assert dash.path_get(payload, "link_adaptation.outer_loop_flag") is True
            assert dash.path_get(payload, "link_adaptation.rank_adaptation_policy") == "measured_ri"
            assert dash.path_get(payload, "mimo_and_beam_management.ssb_beam_count") == 4
            assert dash.path_get(payload, "mimo_and_beam_management.csi_rs_beam_count") == 8
            assert dash.path_get(payload, "antenna_and_array.bs_num_txrus") == 64
            assert dash.path_get(payload, "antenna_and_array.ue_num_rxrus") == 4
            assert dash.path_get(payload, "antenna_and_array.ue_num_txrus") == 4
