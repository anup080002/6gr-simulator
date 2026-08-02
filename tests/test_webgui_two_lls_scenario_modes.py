from __future__ import annotations

import sys
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


SNR_SWEEP_SCENARIO = "master_sinr_sweep.yaml"
GEOMETRY_SCENARIO = "master_geometry_based.yaml"
FULL_STACK_SCENARIO = "lls_webgui_full_stack_sinr_geometry_qualification.yaml"


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
        FULL_STACK_SCENARIO,
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
