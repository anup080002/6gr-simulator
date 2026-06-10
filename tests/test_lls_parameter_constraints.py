from __future__ import annotations

import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def _rules_by_id() -> dict[str, dict]:
    payload = json.loads(
        (REPO_ROOT / "simulator" / "configs" / "schema" / "parameter_constraints.json").read_text(
            encoding="utf-8"
        )
    )
    assert payload["schema_version"] == "1.0"
    rules = payload["rules"]
    assert isinstance(rules, list) and len(rules) >= 25
    return {str(rule["id"]): rule for rule in rules}


def _case_allowed(rule: dict, key: str) -> list:
    case = rule["cases"][key]
    return case.get("allowed") or case.get("allowed_hz") or case.get("allowed_scs")


def main() -> None:
    rules = _rules_by_id()
    for required in (
        "fr_range_to_bandwidth",
        "bandwidth_fr_to_scs",
        "bw_scs_to_nrb",
        "scs_nrb_to_fft",
        "duplex_to_tdd_pattern",
        "scs_to_prach_format",
        "transform_precoding_to_modulation",
        "channel_model_to_profile",
        "target_bler_to_olla_steps",
        "scs_to_prach_sequence_length",
    ):
        assert required in rules, f"missing constraint rule {required}"

    fr2_bw = _case_allowed(rules["fr_range_to_bandwidth"], "FR2")
    assert fr2_bw == [50000000, 100000000, 200000000, 400000000]

    fr1_5mhz_scs = rules["bandwidth_fr_to_scs"]["matrix"]["FR1"]["5000000"]["allowed"]
    assert fr1_5mhz_scs == [15, 30]
    assert 60 not in fr1_5mhz_scs

    transform_allowed = _case_allowed(rules["transform_precoding_to_modulation"], "true")
    assert "256QAM" not in transform_allowed
    assert {"PI/2-BPSK", "QPSK", "16QAM", "64QAM"}.issubset(set(transform_allowed))

    catalog = dash.load_parameter_constraints_catalog()
    assert catalog["status"] == "loaded"
    assert dash.parameter_constraints_summary()["rule_count"] >= 25

    browser_payload = {
        "run_control": {
            "execution_mode": "LLS",
            "random_seed_master": 123,
            "warmup_ms": 2.5,
            "measurement_ms": 27.5,
        },
        "frequency": {"range_name": "FR1", "center_frequency_hz": 4000000000, "bandwidth_hz": 100000000},
        "frame": {"scs_khz": 30, "cp_type": "normal"},
        "phy": {"duplex": {"mode": "TDD", "tddPattern": "DDDSU"}, "carrier": {"NSizeGrid": 273}},
        "waveform": {"dl": "CP-OFDM", "ul": "DFT-s-OFDM", "transform_precoding_enabled": True},
        "scenario": {
            "layout": {
                "nSites": 2,
                "nSectorsPerSite": 6,
                "interSiteDistance_m": 1000,
                "wrapAround": True,
            },
            "bs": {"nTxAnt": 64, "txPower_dBm": 46},
            "ue": {"nUE": 150, "nRxAnt": 4, "noiseFigure_dB": 7},
            "mobility": {"speed_kmh": 3},
        },
        "scheduler": {"scheduler_type": "pf", "beam_aware_scheduler_enable": True},
        "harq": {"enable": True, "n_harq_processes": 16, "max_retransmissions": 4, "k1": 10},
        "link_adaptation": {"target_bler_dl": 0.1, "target_bler_ul": 0.1},
        "modulation": {"dl_modulation": "64QAM", "ul_modulation": "64QAM"},
        "prach": {"enable": True, "format": "A1", "zero_correlation_zone": 8},
        "reference_signals": {"srs_enabled": True, "srs_ports": 2, "srs_periodicity_ms": 10},
        "channels": {"model": "TDL", "profile": "TDL-C", "spatial_consistency": True},
        "output": {"persistence_mode": "both"},
    }
    canonical = dash.canonicalize_browser_config_payload(browser_payload, keep_legacy_aliases=True)
    assert dash.path_get(canonical, "simulation.random_seed") == 123
    assert dash.path_get(canonical, "run_control.warmup_time_ms") == 2.5
    assert dash.path_get(canonical, "run_control.measurement_time_ms") == 27.5
    assert dash.path_get(canonical, "frequency.duplex_mode") == "TDD"
    assert dash.path_get(canonical, "frame.tdd_pattern") == "DDDSU"
    assert dash.path_get(canonical, "waveform.ul_waveform") == "DFT-s-OFDM"
    assert dash.path_get(canonical, "deployment_topology.num_sites") == 2
    assert dash.path_get(canonical, "deployment_topology.num_sectors_per_site") == 6
    assert dash.path_get(canonical, "deployment_topology.num_ues") == 150
    assert dash.path_get(canonical, "system.scheduler.type") == "pf"
    assert dash.path_get(canonical, "harq.process_count") == 16
    assert dash.path_get(canonical, "modulation.ul_modulation_order") == 6
    assert dash.path_get(canonical, "random_access.prach_format") == "A1"
    assert dash.path_get(canonical, "channels.model_type") == "TDL"

    static_root = REPO_ROOT / "jio_ran_web_design_v7"
    app_text = (static_root / "app.js").read_text(encoding="utf-8")
    assert "mockValue(" not in app_text
    assert "ConfigStore" in app_text
    assert "ConfigFormRenderer" in app_text
    for html_file in static_root.glob("*.html"):
        text = html_file.read_text(encoding="utf-8")
        assert "config-store.js" in text, f"{html_file.name} must load ConfigStore"
        assert "config-form-renderer.js" in text, f"{html_file.name} must load ConfigFormRenderer"
        assert text.index("config-store.js") < text.index("app.js")
        assert text.index("config-form-renderer.js") < text.index("app.js")


if __name__ == "__main__":
    main()
