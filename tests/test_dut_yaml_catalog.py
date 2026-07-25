from __future__ import annotations

from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
DUT_ROOT = REPO_ROOT / "simulator" / "configs" / "dut"
SCENARIO_ROOT = REPO_ROOT / "simulator" / "configs" / "scenarios"
MASTER_SCENARIO = SCENARIO_ROOT / "master_geometry_based.yaml"

EXPECTED_DUT_FILES = {
    "dut_base.yaml",
    "tx_chain_dut.yaml",
    "ssb_dut.yaml",
    "pss_sss_dut.yaml",
    "pbch_dut.yaml",
    "rach_dut.yaml",
    "pdcch_dut.yaml",
    "pdsch_dut.yaml",
    "pusch_dut.yaml",
    "pucch_dut.yaml",
    "dmrs_dut.yaml",
    "csi_rs_dut.yaml",
    "srs_dut.yaml",
    "trs_dut.yaml",
    "ptrs_dut.yaml",
    "harq_dut.yaml",
    "mimo_beamforming_dut.yaml",
    "channel_estimation_dut.yaml",
    "synchronization_dut.yaml",
    "rf_impairments_dut.yaml",
    "coding_modulation_dut.yaml",
}

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


def _load(name: str) -> dict:
    return yaml.safe_load((DUT_ROOT / name).read_text(encoding="utf-8")) or {}


def test_dut_yaml_catalog_is_complete_and_overlay_only() -> None:
    assert MASTER_SCENARIO.is_file()
    assert {path.name for path in DUT_ROOT.glob("*.yaml")} == EXPECTED_DUT_FILES
    assert not list(SCENARIO_ROOT.glob("*_dut*.yaml"))

    base = _load("dut_base.yaml")
    assert base["dut"]["master_scenario"] == "../scenarios/master_geometry_based.yaml"
    assert base["dut"]["source_of_truth"] == "canonical_control"

    for name in sorted(EXPECTED_DUT_FILES - {"dut_base.yaml"}):
        payload = _load(name)
        assert payload["inherits"] == "dut_base.yaml"
        assert set(payload).isdisjoint(RUNTIME_MIRROR_SECTIONS)
        assert set(payload) == {"inherits", "dut"}

        dut = payload["dut"]
        assert dut["id"] == name.removesuffix(".yaml")
        assert dut["target_cases"]
        assert dut["config_paths"]
        assert len(dut["config_paths"]) == len(set(dut["config_paths"]))

        overrides = dut.get("runtime_overrides", [])
        override_paths = [item["path"] for item in overrides]
        assert len(override_paths) == len(set(override_paths))
