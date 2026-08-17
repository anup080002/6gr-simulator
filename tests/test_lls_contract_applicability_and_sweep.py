from __future__ import annotations

import io
import json
import sys
from pathlib import Path

from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_contract_materializer as materializer  # noqa: E402
import lls_web_dashboard as dash  # noqa: E402


def test_contract_chart_persistence_is_raster_png_only() -> None:
    chart_spec = {
        "kind": "analytics",
        "section_slug": "waveform-time-domain-analytics",
        "chart_name": "Tx waveform",
    }
    assert materializer.chart_contract_image_path(chart_spec).endswith(".png")

    svg_bytes = materializer._render_svg_plot(  # noqa: SLF001
        "Tx waveform",
        "Persisted runtime preview",
        {
            "mode": "line",
            "x_label": "sample",
            "y_label": "amplitude",
            "points": [[0.0, 0.0], [1.0, 0.5], [2.0, -0.25]],
        },
        ["source=runtime"],
    )
    png_bytes = materializer._rasterize_contract_png(  # noqa: SLF001
        svg_bytes,
        source_mime_type="image/svg+xml",
        source_logical_path="internal://test/tx-waveform.svg",
    )
    assert png_bytes.startswith(b"\x89PNG\r\n\x1a\n")
    with Image.open(io.BytesIO(png_bytes)) as image:
        image.verify()
        assert image.format == "PNG"


def test_config_driven_contract_applicability_does_not_enable_optional_6g() -> None:
    run_row = {
        "config_json": json.dumps(
            {
                "run": {"mode": "link", "timeProfilingEnabled": False},
                "scenario": {"mobility": {"enable": False, "speed_kmh": [0, 0]}},
                "system": {"handover": {"enable": True}},
                "canonical_control": {
                    "launch": {
                        "geometry_enabled": False,
                        "fixed_link_campaign_enabled": False,
                    }
                },
            }
        )
    }
    policy = dash.extract_run_feature_policy(run_row)

    assert policy["geometry_enabled"] is False
    assert policy["mobility_enabled"] is False
    assert policy["handover_enabled"] is False
    assert policy["fixed_link_campaign_enabled"] is False
    assert materializer.optional_6g_features_enabled(policy) is False
    assert materializer.contract_artifact_is_policy_filtered(
        "reports/csv/fixed_snr_sweep_audit.csv",
        policy,
        contract_name="fixed_snr_sweep_audit",
    )
    assert materializer.contract_artifact_is_policy_filtered(
        "reports/csv/live_pucch_f3_table.csv",
        policy,
        contract_name="live_pucch_f3_table",
    )
    assert not materializer.contract_artifact_is_policy_filtered(
        "reports/csv/live_pucch_f0_table.csv",
        policy,
        contract_name="live_pucch_f0_table",
    )
    assert materializer.contract_artifact_is_policy_filtered(
        "analytics/csv/contract__optional-6g-extension-analytics__sensing-p-d-p-fa.csv",
        policy,
        contract_name="sensing P_D / P_FA",
    )


def test_resolved_fixed_link_campaign_authority_and_geometry_exclusion() -> None:
    run_row = {
        "config_json": json.dumps(
            {
                "validation": {"fixed_link_campaign": {"enabled": True}},
                "lls6g": {
                    "resolvedConfig": {
                        "canonical_control": {
                            "run": {"fixed_link_campaign_only": True}
                        },
                        "sweeps_and_matrix": {
                            "fixed_link_calibration": {
                                "enabled": True,
                                "only": True,
                            }
                        },
                    }
                },
            }
        )
    }
    policy = dash.extract_run_feature_policy(run_row)
    assert policy["fixed_link_campaign_enabled"] is True
    assert policy["fixed_link_campaign_only"] is True
    assert not materializer.contract_artifact_is_policy_filtered(
        "reports/csv/dl_fixed_snr_bler_curve.csv",
        policy,
        contract_name="dl_fixed_snr_bler_curve",
    )
    assert materializer.contract_artifact_is_policy_filtered(
        "air_interface/csv/distance_vs_sinr.csv",
        policy,
        contract_name="distance_vs_sinr",
    )


def test_resolved_fixed_link_disables_only_nonexecuted_runtime_families() -> None:
    run_row = {
        "profile_name": "waveform_bundle",
        "config_json": json.dumps(
            {
                "lls6g": {
                    "resolvedConfig": {
                        "canonical_control": {"run": {"fixed_link_campaign_only": True}},
                        "sweeps_and_matrix": {
                            "fixed_link_calibration": {"enabled": True, "only": True}
                        },
                        "run_control": {
                            "save_scheduler_decisions": True,
                            "save_constellations": False,
                            "save_energy_trace": False,
                            "raw_iq_capture_enable": False,
                            "raw_grid_capture_enable": False,
                        },
                        "output": {"backend": "filesystem"},
                        "channels": {
                            "profile": "AWGN",
                            "pathloss_enabled": False,
                            "shadow_fading_enabled": False,
                            "phase10_strict": {"interference": {"execution": "none"}},
                        },
                        "random_access": {
                            "enabled": False,
                            "enable_collision_mode": False,
                            "parameterized_config_enabled": False,
                        },
                        "phy": {"pucch": {"enable": False}},
                        "mimo": {
                            "phase07_strict": {"ul_srs_authority": {"enabled": False}}
                        },
                    }
                }
            }
        ),
    }
    policy = dash.extract_run_feature_policy(run_row)
    assert policy["fixed_link_campaign_only"] is True
    assert policy["scheduler_runtime_enabled"] is False
    assert policy["traffic_runtime_enabled"] is False
    assert policy["pathloss_enabled"] is False
    assert policy["shadowing_enabled"] is False
    assert policy["interference_enabled"] is False
    assert policy["prach_enabled"] is False
    assert policy["pucch_enabled"] is False
    assert policy["energy_enabled"] is False
    assert policy["prach_collision_enabled"] is False
    assert policy["prach_threshold_sweep_enabled"] is False
    assert policy["reciprocity_calibration_enabled"] is False
    assert policy["storage_backend"] == "filesystem"
    assert materializer.contract_artifact_is_policy_filtered(
        "reports/csv/live_scheduler_cycle.csv", policy,
        contract_name="live_scheduler_cycle",
    )
    assert materializer.contract_artifact_is_policy_filtered(
        "analytics/csv/fairness_analytics.csv", policy,
        contract_name="fairness_analytics",
    )
    assert materializer.contract_artifact_is_policy_filtered(
        "analytics/csv/contract__waveform__tx-waveform.csv", policy,
        contract_name="Tx waveform",
    )
    assert materializer.contract_artifact_is_policy_filtered(
        "analytics/csv/resource_grid_analytics.csv", policy,
        contract_name="resource_grid_analytics",
    )
    assert materializer.contract_artifact_is_policy_filtered(
        "analytics/csv/waveform_analytics.csv", policy,
        contract_name="waveform_analytics",
    )
    assert materializer.contract_artifact_is_policy_filtered(
        "reports/csv/reports_all_stage_exec_v.csv", policy,
        contract_name="reports_all_stage_exec_v",
    )


def test_fixed_single_beam_rank1_run_disables_adaptive_spatial_charts() -> None:
    run_row = {
        "config_json": json.dumps(
            {
                "canonical_control": {
                    "launch": {"fixed_link_campaign_enabled": True},
                    "run": {"fixed_link_campaign_only": True},
                },
                "mimo": {
                    "beam_sweep_enabled": False,
                    "beam_count": 1,
                    "n_layers": 1,
                    "max_dl_layers": 1,
                    "max_ul_layers": 1,
                    "rank_adaptation_enable": False,
                },
                "mimo_and_beam_management": {
                    "beam_sweeping": False,
                    "rank_set": [1],
                },
                "csi_acquisition_and_reporting": {
                    "dl_csi_enabled": False,
                    "ul_csi_enabled": False,
                },
                "link_adaptation": {
                    "fixed_or_amc": "fixed",
                    "rank_adaptation_policy": "fixed",
                    "beam_adaptation_policy": "fixed",
                },
            }
        )
    }
    policy = dash.extract_run_feature_policy(run_row)
    assert policy["beam_adaptation_enabled"] is False
    assert policy["beam_count"] == 1
    assert policy["rank_adaptation_enabled"] is False
    assert policy["max_spatial_rank"] == 1
    assert policy["csi_enabled"] is False
    assert policy["fixed_mcs_mode"] is True
    for name in (
        "precoder / beam selection timeline",
        "beam pair timeline",
        "beam hit rate / top-K hit rate",
        "selected vs best beam gap",
        "per-beam quality plot",
        "rank distribution",
        "CQI / PMI / RI / CRI timeline",
    ):
        assert materializer.contract_artifact_is_policy_filtered(
            f"analytics/csv/contract__test__{materializer.slugify(name)}.csv",
            policy,
            contract_name=name,
        )

    # Schema-only component summaries are inapplicable only because the same
    # authoritative YAML disables the owning runtime family.  This must not be
    # inferred from the absence of rows.
    for path in (
        "reports/csv/live_coverage_layer.csv",
        "reports/csv/live_user_performance_snapshot.csv",
        "reports/csv/live_csirs_stats.csv",
        "reports/csv/live_beam_p1_acquisition_stats.csv",
    ):
        assert materializer.contract_artifact_is_policy_filtered(
            path,
            policy,
            contract_name=Path(path).stem,
        )


def test_enabled_csi_beam_and_geometry_tables_remain_required() -> None:
    run_row = {
        "config_json": json.dumps(
            {
                "canonical_control": {
                    "launch": {
                        "fixed_link_campaign_enabled": False,
                        "geometry_enabled": True,
                    },
                    "run": {"fixed_link_campaign_only": False},
                },
                "mimo": {"beam_count": 4},
                "mimo_and_beam_management": {"beam_sweeping": True},
                "csi_acquisition_and_reporting": {"dl_csi_enabled": True},
            }
        )
    }
    policy = dash.extract_run_feature_policy(run_row)
    assert policy["fixed_link_campaign_only"] is False
    assert policy["csi_enabled"] is True
    assert policy["beam_adaptation_enabled"] is True
    for path in (
        "reports/csv/live_coverage_layer.csv",
        "reports/csv/live_user_performance_snapshot.csv",
        "reports/csv/live_csirs_stats.csv",
        "reports/csv/live_beam_p1_acquisition_stats.csv",
    ):
        assert not materializer.contract_artifact_is_policy_filtered(
            path,
            policy,
            contract_name=Path(path).stem,
        )


def test_disabled_runtime_capabilities_filter_only_their_own_contracts() -> None:
    run_row = {
        "config_json": json.dumps(
            {
                "run": {
                    "mode": "link",
                    "timeProfilingEnabled": False,
                    "rawIQCaptureEnabled": False,
                    "rawGridCaptureEnabled": False,
                },
                "phy": {
                    "harq": {"enable": False},
                    "pdcch": {"enable": True},
                    "pucch": {"enable": True},
                    "prach": {"enable": True},
                    "srs": {"enable": True},
                    "pusch": {"power_control": {"enabled": False}},
                },
                "rf": {"enable": False, "frontend": {"enabled": False}},
                "outputs": {"saveChannelSnapshots": False},
                "channel": {
                    "pathlossEnabled": False,
                    "shadowFadingEnabled": False,
                    "interference": {"interCellEnabled": False, "intraCellEnabled": True},
                },
                "initial_access": {"enabled": True},
                "random_access": {"enabled": True},
                "energy": {"enable": True},
            }
        )
    }
    policy = dash.extract_run_feature_policy(run_row)

    assert policy["harq_enabled"] is False
    assert policy["rf_impairments_enabled"] is False
    assert policy["power_control_enabled"] is False
    assert policy["raw_iq_capture_enabled"] is False
    assert policy["raw_grid_capture_enabled"] is False
    assert policy["channel_snapshot_capture_enabled"] is False
    assert policy["fading_enabled"] is False
    assert policy["interference_enabled"] is True
    assert policy["initial_access_enabled"] is True
    assert policy["prach_enabled"] is True
    assert policy["energy_enabled"] is True

    for name in (
        "HARQ process timeline",
        "combining gain histogram",
        "CPU cycles",
        "PDCCH stage latency waterfall",
        "phase noise summary",
        "power control command timeline",
        "pre-channel waveform",
        "DMRS/PTRS occupancy map",
        "true H(tau) if available",
        "pathloss distribution",
        "delay spread chart",
    ):
        assert materializer.contract_artifact_is_policy_filtered(
            f"reports/csv/contract__test__{materializer.slugify(name)}.csv",
            policy,
            contract_name=name,
        )

    for name in (
        "PDCCH decode success trend",
        "PRACH detection probability",
        "interference power timeline",
        "energy per bit over time",
    ):
        assert not materializer.contract_artifact_is_policy_filtered(
            f"reports/csv/contract__test__{materializer.slugify(name)}.csv",
            policy,
            contract_name=name,
        )


def test_resolved_master_yaml_switches_override_dashboard_profile_defaults() -> None:
    run_row = {
        "profile_name": "waveform_bundle",
        "config_json": json.dumps(
            {
                "rf_frontend": {"enabled": False},
                "pusch": {"power_control": {"enabled": False}},
                "output_control": {
                    "save_raw_waveforms": False,
                    "save_channel_snapshots": False,
                },
            }
        ),
    }
    policy = dash.extract_run_feature_policy(run_row)
    assert policy["rf_impairments_enabled"] is False
    assert policy["power_control_enabled"] is False
    assert policy["raw_iq_capture_enabled"] is False
    assert policy["channel_snapshot_capture_enabled"] is False


def test_pusch_uci_policy_does_not_claim_standalone_pucch_artifacts() -> None:
    run_row = {
        "config_json": json.dumps(
            {
                "phy": {"pucch": {"enable": True}, "pusch": {"enable": True}},
                "control_gating": {
                    "pucch_required": False,
                    "pusch_uci_required": True,
                },
            }
        )
    }
    policy = dash.extract_run_feature_policy(run_row)
    assert policy["pucch_enabled"] is True
    assert policy["pucch_runtime_required"] is False
    assert policy["pusch_uci_runtime_required"] is True
    for name in (
        "requested vs resolved format confusion matrix",
        "PUCCH DTX statistics",
        "per-format reliability breakdown",
    ):
        assert materializer.contract_artifact_is_policy_filtered(
            f"control_phy/csv/contract__test__{materializer.slugify(name)}.csv",
            policy,
            contract_name=name,
        )
    assert materializer.contract_artifact_is_policy_filtered(
        "air_interface/csv/pucch_trials.csv", policy, contract_name="pucch_trials"
    )
    assert not materializer.contract_artifact_is_policy_filtered(
        "air_interface/csv/ul_pusch_trials.csv", policy, contract_name="live_uci_table"
    )


def test_optional_6g_contracts_are_filtered_per_feature() -> None:
    policy = {
        "sensing_enabled": True,
        "ntn_enabled": False,
        "ai_enabled": False,
        "localization_enabled": False,
        "ris_enabled": False,
        "cell_free_enabled": False,
        "sub_thz_enabled": False,
    }
    assert not materializer.contract_artifact_is_policy_filtered(
        "analytics/csv/sensing_analytics.csv",
        policy,
        contract_name="sensing_analytics",
    )
    assert not materializer.contract_artifact_is_policy_filtered(
        "analytics/csv/contract__optional-6g-extension-analytics__sensing-p-d-p-fa.csv",
        policy,
        contract_name="sensing P_D / P_FA",
    )
    for contract_name in (
        "ai_inference_analytics",
        "localization_analytics",
        "ntn_haps_uav_analytics",
        "ris_analytics",
        "cell_free_mimo_analytics",
        "sub_thz_impairment_analytics",
        "AI inference confidence / latency",
        "localization RMSE",
        "NTN/HAPS/UAV delay and Doppler",
        "RIS state summaries",
        "cell-free / distributed MIMO combining gains",
        "sub-THz impairment studies",
    ):
        assert materializer.contract_artifact_is_policy_filtered(
            f"analytics/csv/contract__optional__{materializer.slugify(contract_name)}.csv",
            policy,
            contract_name=contract_name,
        )


def test_sensing_chart_uses_runtime_target_detection_and_cfar_cells() -> None:
    sources = {
        1: materializer._encode_csv(  # noqa: SLF001
            ["Executed", "EvidenceValid", "DetectionCount", "MatchedTargetCount"],
            [[1, 1, 1, 1]],
        ),
        2: materializer._encode_csv(  # noqa: SLF001
            ["TargetId", "ExpectedRangeM"], [[1, 41.25]],
        ),
        3: materializer._encode_csv(  # noqa: SLF001
            ["MatchedTargetId", "AcceptanceMatch"], [[1, 1]],
        ),
        4: materializer._encode_csv(  # noqa: SLF001
            ["RangeM", "RawDetection"], [[40, 0], [41, 1], [42, 0]],
        ),
    }
    existing = {
        "isac/csv/isac_runtime_evidence.csv": {"artifact_id": 1},
        "isac/csv/isac_target_truth.csv": {"artifact_id": 2},
        "isac/csv/isac_detections.csv": {"artifact_id": 3},
        "isac/csv/isac_cfar_thresholds.csv": {"artifact_id": 4},
    }
    result = materializer._specialized_chart_materialization(  # noqa: SLF001
        "sensing P_D / P_FA", existing, lambda artifact_id: sources[artifact_id], 19
    )
    assert result is not None
    assert result["source_mapping_status"] == "exact"
    header, rows = materializer._decode_csv(result["csv_bytes"])  # noqa: SLF001
    values = {row[header.index("metric")]: float(row[header.index("value")]) for row in rows}
    assert values["observed_target_detection_fraction"] == 1.0
    assert values["observed_false_alarm_cell_fraction"] == 0.0
    assert b"P_FA campaign claim=not made" in result["img_bytes"]


def test_configured_sweep_charts_use_real_directional_trials() -> None:
    header = [
        "Direction",
        "ConfiguredSNR_dB",
        "CRCPass",
        "BitErrors",
        "BitsCompared",
        "Throughput_Mbps",
        "PostEqSINR_dB",
    ]
    dl_csv = materializer._encode_csv(  # noqa: SLF001
        header,
        [
            ["DL", -20, 0, 900, 1000, 0, -19.5],
            ["DL", 0, 1, 10, 1000, 18, 0.5],
            ["DL", 20, 1, 0, 1000, 36, 19.7],
        ],
    )
    ul_csv = materializer._encode_csv(  # noqa: SLF001
        header,
        [
            ["UL", -20, 0, 800, 1000, 0, -18.8],
            ["UL", 0, 1, 20, 1000, 12, 0.2],
            ["UL", 20, 1, 0, 1000, 24, 19.2],
        ],
    )
    existing = {
        "air_interface/csv/dl_pdsch_trials.csv": {
            "artifact_id": 1,
            "logical_path": "air_interface/csv/dl_pdsch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        },
        "air_interface/csv/ul_pusch_trials.csv": {
            "artifact_id": 2,
            "logical_path": "air_interface/csv/ul_pusch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        },
    }
    payloads = {1: dl_csv, 2: ul_csv}

    dl_bler = materializer._specialized_chart_materialization(  # noqa: SLF001
        "dl_bler_vs_snr", existing, lambda artifact_id: payloads[artifact_id], 91
    )
    ul_ber = materializer._specialized_chart_materialization(  # noqa: SLF001
        "ul_ber_vs_snr", existing, lambda artifact_id: payloads[artifact_id], 91
    )
    measured = materializer._specialized_chart_materialization(  # noqa: SLF001
        "measured_sinr_vs_configured_snr", existing, lambda artifact_id: payloads[artifact_id], 91
    )

    assert dl_bler is not None and ul_ber is not None and measured is not None
    assert dl_bler["source_table_path"] == "air_interface/csv/dl_pdsch_trials.csv"
    assert ul_ber["source_table_path"] == "air_interface/csv/ul_pusch_trials.csv"
    assert "ConfiguredSNR_dB,BLER" in dl_bler["csv_bytes"].decode("utf-8")
    assert "ConfiguredSNR_dB,BER" in ul_ber["csv_bytes"].decode("utf-8")
    measured_csv = measured["csv_bytes"].decode("utf-8")
    assert "MeasuredPostEqSINR_dB" in measured_csv
    assert "-20.0,-19.15" in measured_csv
    assert b"visual_gate=" not in measured["img_bytes"]


def test_snr_and_sinr_chart_titles_use_distinct_runtime_axes() -> None:
    trial_csv = materializer._encode_csv(  # noqa: SLF001
        [
            "Direction",
            "AppliedAWGNSNR_dB",
            "ConfiguredSNR_dB",
            "PostEqSINR_dB",
            "CRCPass",
            "BitErrors",
            "BitsCompared",
            "Throughput_Mbps",
        ],
        [
            ["DL", -15, -14, -13.8, 0, 480, 1000, 0],
            ["DL", -5, -4, -4.7, 0, 300, 1000, 0],
            ["DL", 10, 11, 9.6, 1, 20, 1000, 12],
            ["DL", 20, 21, 19.8, 1, 0, 1000, 24],
        ],
    )
    existing = {
        "air_interface/csv/dl_pdsch_trials.csv": {
            "artifact_id": 1,
            "logical_path": "air_interface/csv/dl_pdsch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    fetch = lambda artifact_id: trial_csv  # noqa: E731, ARG005

    by_snr = materializer._specialized_chart_materialization(  # noqa: SLF001
        "BLER vs SNR", existing, fetch, 92
    )
    by_sinr = materializer._specialized_chart_materialization(  # noqa: SLF001
        "BLER vs SINR", existing, fetch, 92
    )
    throughput = materializer._specialized_chart_materialization(  # noqa: SLF001
        "throughput vs SNR", existing, fetch, 92
    )

    assert by_snr is not None and by_sinr is not None and throughput is not None
    assert "AppliedAWGNSNR_dB,BLER" in by_snr["csv_bytes"].decode("utf-8")
    assert "PostEqSINR_dB,BLER" in by_sinr["csv_bytes"].decode("utf-8")
    assert "AppliedAWGNSNR_dB,Throughput_Mbps" in throughput["csv_bytes"].decode("utf-8")
    assert b"Applied AWGN SNR (dB)" in by_snr["img_bytes"]
    assert b"Post-equalization SINR (dB)" in by_sinr["img_bytes"]
    assert b"Evidence Summary" in by_snr["img_bytes"]


def test_finalized_fixed_sweep_chart_preserves_confidence_intervals() -> None:
    curve_csv = materializer._encode_csv(  # noqa: SLF001
        [
            "Direction",
            "AppliedSNR_dB",
            "BLER",
            "BLER_CI_Low",
            "BLER_CI_High",
            "TrialCount",
            "TBFailCount",
            "MCS",
            "Modulation",
            "Rank",
            "Layers",
            "ChannelModel",
            "TargetBLER",
            "Status",
        ],
        [
            ["DL", -15, 1.0, 0.963, 1.0, 100, 100, 20, "256QAM", 1, 1, "AWGN", 0.1, "complete"],
            ["DL", -5, 0.8, 0.71, 0.86, 100, 80, 20, "256QAM", 1, 1, "AWGN", 0.1, "complete"],
            ["DL", 10, 0.2, 0.13, 0.29, 100, 20, 20, "256QAM", 1, 1, "AWGN", 0.1, "complete"],
            ["DL", 20, 0.0, 0.0, 0.037, 100, 0, 20, "256QAM", 1, 1, "AWGN", 0.1, "complete"],
        ],
    )
    path = "reports/csv/dl_fixed_snr_bler_curve.csv"
    existing = {
        path: {
            "artifact_id": 7,
            "logical_path": path,
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        }
    }
    result = materializer._specialized_chart_materialization(  # noqa: SLF001
        "dl_bler_vs_snr", existing, lambda artifact_id: curve_csv, 93
    )
    assert result is not None
    assert result["csv_status"] == "specialized_finalized_fixed_sweep_dataset"
    csv_text = result["csv_bytes"].decode("utf-8")
    assert "ci_low,ci_high,trial_count,failure_count" in csv_text
    assert ",20.0,BLER,0.0,0.0,0.037,100,0," in csv_text
    assert b"Applied AWGN SNR (dB)" in result["img_bytes"]
    assert b"Target 0.1" in result["img_bytes"]
    assert b"Runtime trials: 400" in result["img_bytes"]


def test_coarse_fixed_sweep_uses_measured_sinr_and_does_not_interpolate_transition() -> None:
    summary_csv = materializer._encode_csv(  # noqa: SLF001
        [
            "Direction", "AppliedSNR_dB", "MeanMeasuredSINR_dB", "BLER",
            "BLER_CI_Low", "BLER_CI_High", "TrialCount", "TBFailCount",
            "MCS", "Modulation", "Rank", "Layers", "ChannelModel", "TargetBLER", "Throughput_Mbps",
        ],
        [
            ["DL", -5, -5.0, 1.0, 0.963, 1.0, 100, 100, 20, "256QAM", 1, 1, "AWGN", 0.1, 0.0],
            ["DL", 10, 10.0, 1.0, 0.963, 1.0, 100, 100, 20, "256QAM", 1, 1, "AWGN", 0.1, 0.0],
            ["DL", 20, 20.04, 0.0, 0.0, 0.037, 100, 0, 20, "256QAM", 1, 1, "AWGN", 0.1, 69.632],
            ["UL", -5, -5.0, 1.0, 0.963, 1.0, 100, 100, 20, "256QAM", 1, 1, "AWGN", 0.1, 0.0],
            ["UL", 10, 9.99, 1.0, 0.963, 1.0, 100, 100, 20, "256QAM", 1, 1, "AWGN", 0.1, 0.0],
            ["UL", 20, 20.00, 0.08, 0.041, 0.15, 100, 8, 20, "256QAM", 1, 1, "AWGN", 0.1, 69.729],
        ],
    )
    path = "reports/csv/fixed_snr_sweep_curve_summary.csv"
    existing = {path: {"artifact_id": 41, "logical_path": path}}
    fetch = lambda artifact_id: summary_csv  # noqa: ARG005, E731

    result = materializer._specialized_chart_materialization(  # noqa: SLF001
        "BLER vs SINR", existing, fetch, 94
    )
    assert result is not None
    csv_text = result["csv_bytes"].decode("utf-8")
    svg_text = result["img_bytes"].decode("utf-8")
    assert "MeanMeasuredSINR_dB" in csv_text
    assert "DL" in svg_text and "UL" in svg_text
    assert "transition unresolved" in svg_text
    assert "polyline" not in svg_text

    crc = materializer._specialized_chart_materialization(  # noqa: SLF001
        "CRC pass/fail rates", existing, fetch, 94
    )
    assert crc is not None
    crc_csv = crc["csv_bytes"].decode("utf-8")
    assert "crc_pass_count,crc_fail_count,trial_count,crc_pass_rate" in crc_csv
    assert "DL pass rate" in crc["img_bytes"].decode("utf-8")

    throughput = materializer._specialized_chart_materialization(  # noqa: SLF001
        "Throughput vs SNR", existing, fetch, 94
    )
    assert throughput is not None
    throughput_svg = throughput["img_bytes"].decode("utf-8")
    assert "Delivered goodput (Mbit/s)" in throughput_svg
    assert "DL at 20 dB" in throughput_svg and "UL at 20 dB" in throughput_svg
    assert 'stroke-dasharray="8 5"' in throughput_svg
    assert "<rect" in throughput_svg and "<circle" in throughput_svg


def test_rsrp_chart_never_mixes_relative_grid_db_with_absolute_dbm() -> None:
    relative_only = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "CSI_RSRP_dB", "CSI_RSRPSource"],
        [[1, 40.0, "relative_digital_grid_power"], [2, 39.8, "relative_digital_grid_power"], [3, 40.1, "relative_digital_grid_power"]],
    )
    trial_path = "air_interface/csv/dl_pdsch_trials.csv"
    relative_existing = {trial_path: {"artifact_id": 71, "logical_path": trial_path}}
    relative_result = materializer._specialized_chart_materialization(  # noqa: SLF001
        "ServingRSRP / RSRP / CSI-RSRP trends",
        relative_existing,
        lambda artifact_id: relative_only,  # noqa: ARG005
        101,
    )
    assert relative_result is None

    absolute = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "ServingRSRP_dBm", "RSRP_dBm"],
        [[1, -103.0, -103.0], [2, -98.0, -98.0], [3, -91.0, -91.0]],
    )
    absolute_path = "reports/csv/live_rsrp_serving_trace.csv"
    absolute_existing = {absolute_path: {"artifact_id": 72, "logical_path": absolute_path}}
    absolute_result = materializer._specialized_chart_materialization(  # noqa: SLF001
        "ServingRSRP / RSRP / CSI-RSRP trends",
        absolute_existing,
        lambda artifact_id: absolute,  # noqa: ARG005
        102,
    )
    assert absolute_result is not None
    svg = absolute_result["img_bytes"].decode("utf-8")
    assert "RSRP / CSI-RSRP (dBm)" in svg
    assert "relative digital" not in svg
    assert "CSI_RSRP_dB" not in absolute_result["csv_bytes"].decode("utf-8")


def test_fixed_awgn_policy_disables_absolute_rsrp_and_static_port_charts() -> None:
    fixed_awgn_policy = {
        "fixed_link_campaign_only": True,
        "rank_adaptation_enabled": False,
        "max_spatial_rank": 1,
        "absolute_rx_power_calibrated": False,
    }
    assert materializer.contract_artifact_is_policy_filtered(
        "reports/csv/contract__measurement__servingrsrp-rsrp-csi-rsrp-trends.csv",
        fixed_awgn_policy,
        contract_name="ServingRSRP / RSRP / CSI-RSRP trends",
    )
    assert materializer.contract_artifact_is_policy_filtered(
        "beamforming/csv/contract__mimo__port-usage-chart.csv",
        fixed_awgn_policy,
        contract_name="port usage chart",
    )


def test_publication_axis_ticks_use_rounded_engineering_values() -> None:
    assert materializer._axis_tick_values(-14.83, 20.04) == [-10.0, 0.0, 10.0, 20.0]
    assert materializer._axis_tick_values(0.0, 1.0) == [0.0, 0.25, 0.5, 0.75, 1.0]
    assert materializer._explicit_axis_ticks([-15.0, -5.0, 10.0, 20.0]) == [-15.0, -5.0, 10.0, 20.0]
    assert materializer._explicit_axis_ticks([-14.829, -14.331, -5.074, -5.007, 9.987, 10.004, 20.0005, 20.039]) is None
    assert materializer._display_axis_label("MeanMeasuredSINR_dB") == "Mean measured post-equalization SINR (dB)"


def test_report_charts_select_semantic_runtime_sources() -> None:
    scheduler_csv = materializer._encode_csv(  # noqa: SLF001
        ["slot", "mcs_index"], [[1, 4], [2, 8], [3, 12]]
    )
    queue_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "QueueBytesBefore"], [[1, 9000], [2, 6000], [3, 3000]]
    )
    tb_csv = materializer._encode_csv(  # noqa: SLF001
        ["slot", "tbs_bits", "code_rate"],
        [[1, 1024, 0.25], [2, 2048, 0.5], [3, 4096, 0.75]],
    )
    fixed_trial_csv = materializer._encode_csv(  # noqa: SLF001
        ["ActualMCSSelectionMode", "MCS", "TargetCodeRate"],
        [["configured_fixed", 20, 0.6665]],
    )
    existing = {
        "reports/csv/live_scheduler_cycle.csv": {
            "artifact_id": 21,
            "logical_path": "reports/csv/live_scheduler_cycle.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        },
        "reports/csv/live_queue_state.csv": {
            "artifact_id": 22,
            "logical_path": "reports/csv/live_queue_state.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        },
        "reports/csv/live_pdsch_transport_block_table.csv": {
            "artifact_id": 23,
            "logical_path": "reports/csv/live_pdsch_transport_block_table.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        },
        "air_interface/csv/dl_pdsch_trials.csv": {
            "artifact_id": 24,
            "logical_path": "air_interface/csv/dl_pdsch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        },
    }
    payloads = {21: scheduler_csv, 22: queue_csv, 23: tb_csv, 24: fixed_trial_csv}
    fetch = lambda artifact_id: payloads[artifact_id]

    queue_chart = materializer._specialized_chart_materialization(  # noqa: SLF001
        "queue depth over time", existing, fetch, 92
    )
    tb_chart = materializer._specialized_chart_materialization(  # noqa: SLF001
        "TB size over time", existing, fetch, 92
    )
    code_rate_chart = materializer._specialized_chart_materialization(  # noqa: SLF001
        "MCS/code-rate timeline", existing, fetch, 92
    )

    assert queue_chart is not None
    assert queue_chart["source_table_path"] == "reports/csv/live_queue_state.csv"
    assert "Queue bytes" in queue_chart["csv_bytes"].decode("utf-8")
    assert tb_chart is not None and "Transport block size" in tb_chart["csv_bytes"].decode("utf-8")
    assert code_rate_chart is not None and "Target code rate" in code_rate_chart["csv_bytes"].decode("utf-8")
    assert b"Fixed MCS / Code-Rate Verification" in code_rate_chart["img_bytes"]
    assert b"Policy: configured fixed operating point" in code_rate_chart["img_bytes"]


def test_runtime_grid_spectrum_and_audit_charts_use_exact_sources() -> None:
    re_csv = materializer._encode_csv(  # noqa: SLF001
        ["slot", "rb_index", "occupancy_value", "signal_family", "channel", "cell_id"],
        [[1, 0, 1, "PDSCH", "PDSCH", 1], [1, 1, 1, "SSB", "PBCH", 1], [2, 0, 1, "PUSCH", "PUSCH", 1]],
    )
    waveform_csv = materializer._encode_csv(  # noqa: SLF001
        ["SampleIndex", "Time_s", "TxReal", "TxImag", "RxReal", "RxImag"],
        [[index + 1, index / 1e6, (-1) ** index, 0, 0.5 * ((-1) ** index), 0] for index in range(16)],
    )
    status_csv = materializer._encode_csv(  # noqa: SLF001
        ["required_flag", "status"],
        [[1, "generated"], [1, "failed"], [0, "generated"]],
    )
    existing = {
        "reports/csv/live_re_allocation_snapshot.csv": {"artifact_id": 31, "logical_path": "reports/csv/live_re_allocation_snapshot.csv"},
        "reports/csv/live_waveform_preview.csv": {"artifact_id": 32, "logical_path": "reports/csv/live_waveform_preview.csv"},
        "reports/csv/live_required_vs_optional_case_status.csv": {"artifact_id": 33, "logical_path": "reports/csv/live_required_vs_optional_case_status.csv"},
    }
    payloads = {31: re_csv, 32: waveform_csv, 33: status_csv}
    fetch = lambda artifact_id: payloads[artifact_id]

    grid = materializer._specialized_chart_materialization(  # noqa: SLF001
        "RE occupancy heatmap", existing, fetch, 93
    )
    spectrum = materializer._specialized_chart_materialization(  # noqa: SLF001
        "PSD", existing, fetch, 93
    )
    status = materializer._specialized_chart_materialization(  # noqa: SLF001
        "required vs failed case bar chart", existing, fetch, 93
    )

    assert grid is not None and grid["source_row_count"] == 3
    assert "rb_index" in grid["csv_bytes"].decode("utf-8")
    assert spectrum is not None and "relative_psd_db" in spectrum["csv_bytes"].decode("utf-8")
    assert status is not None and "x_value,y_value" in status["csv_bytes"].decode("utf-8")


def test_pucch_format_table_prefers_matching_runtime_trials() -> None:
    control_csv = materializer._encode_csv(  # noqa: SLF001
        ["RequestedFormat", "ResolvedFormat", "Source"],
        [[2, 2, "configured_control"]],
    )
    runtime_csv = materializer._encode_csv(  # noqa: SLF001
        ["Slot", "RequestedFormat", "ResolvedFormat", "PUCCHDecodeOk"],
        [[3, "format0", "F0", 1], [4, "format2", "F2", 1]],
    )
    existing = {
        "control/csv/pucch_table.csv": {"artifact_id": 41, "logical_path": "control/csv/pucch_table.csv"},
        "air_interface/csv/pucch_trials.csv": {"artifact_id": 42, "logical_path": "air_interface/csv/pucch_trials.csv"},
    }
    payloads = {41: control_csv, 42: runtime_csv}

    result = materializer._specialized_table_materialization(  # noqa: SLF001
        "live_pucch_f0_table",
        existing,
        lambda artifact_id: payloads[artifact_id],
        94,
        "PUCCH",
    )

    assert result is not None
    assert result["source_logical_path"] == "air_interface/csv/pucch_trials.csv"
    output = result["data"].decode("utf-8")
    assert "format0,F0" in output
    assert "format2,F2" not in output


def test_db_artifact_audits_inventory_exact_persisted_bytes() -> None:
    csv_payload = materializer._encode_csv(  # noqa: SLF001
        ["slot", "measured_value", "label"], [[1, 4.5, "truth"], [2, "", "truth"]]
    )
    svg_payload = b'<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360"></svg>'
    existing = {
        "air_interface/csv/dl_pdsch_trials.csv": {
            "artifact_id": 51,
            "logical_path": "air_interface/csv/dl_pdsch_trials.csv",
            "artifact_kind": "table_csv",
            "mime_type": "text/csv; charset=UTF-8",
        },
        "images/runtime.svg": {
            "artifact_id": 52,
            "logical_path": "images/runtime.svg",
            "artifact_kind": "image_svg",
            "mime_type": "image/svg+xml",
        },
    }
    payloads = {51: csv_payload, 52: svg_payload}
    fetch = lambda artifact_id: payloads[artifact_id]

    csv_audit = materializer._specialized_table_materialization(  # noqa: SLF001
        "all_csv_artifact_audit", existing, fetch, 95, "Artifact audit"
    )
    image_audit = materializer._specialized_table_materialization(  # noqa: SLF001
        "all_image_artifact_audit", existing, fetch, 95, "Artifact audit"
    )

    assert csv_audit is not None and csv_audit["source_row_count"] == 1
    csv_text = csv_audit["data"].decode("utf-8")
    assert "db://sim_artifacts/51" in csv_text
    assert "mysql_web_persisted_bytes" in csv_text
    assert materializer.hashlib.sha256(csv_payload).hexdigest() in csv_text
    assert image_audit is not None and image_audit["source_row_count"] == 1
    image_text = image_audit["data"].decode("utf-8")
    assert "images/runtime.svg" in image_text
    assert ",svg,640.0,360.0,1," in image_text


def test_terminal_run_health_and_cdl_angles_use_runtime_evidence() -> None:
    health_csv = materializer._encode_csv(  # noqa: SLF001
        ["status_text"], [["completed_with_failures"]]
    )
    angle_csv = materializer._encode_csv(  # noqa: SLF001
        ["PathIndex", "AngleAoD_deg", "AngleAoA_deg"],
        [[1, -25.0, 15.0], [2, 30.0, -12.0]],
    )
    existing = {
        "reports/csv/live_run_overview.csv": {"artifact_id": 61, "logical_path": "reports/csv/live_run_overview.csv"},
        "reports/csv/channel_rf_cdlc_realization_table.csv": {
            "artifact_id": 62,
            "logical_path": "reports/csv/channel_rf_cdlc_realization_table.csv",
        },
    }
    payloads = {61: health_csv, 62: angle_csv}
    fetch = lambda artifact_id: payloads[artifact_id]

    health = materializer._specialized_chart_materialization(  # noqa: SLF001
        "run health timeline", existing, fetch, 96
    )
    angles = materializer._specialized_chart_materialization(  # noqa: SLF001
        "angle spread chart", existing, fetch, 96
    )

    assert health is not None
    assert ",0.0" in health["csv_bytes"].decode("utf-8")
    assert angles is not None
    assert angles["source_table_path"] == "reports/csv/channel_rf_cdlc_realization_table.csv"
    assert "Runtime channel path angle (deg)" in angles["csv_bytes"].decode("utf-8")


def test_cfo_chart_uses_persisted_true_estimated_and_residual_series() -> None:
    cfo_csv = materializer._encode_csv(  # noqa: SLF001
        [
            "TraceSource", "Direction", "Frame", "Slot", "TrueCFO_Hz",
            "EstimatedCFO_PreCorrection_Hz", "ResidualCFO_PostCorrection_Hz",
        ],
        [
            ["PDSCH", "DL", 1, 1, 120.0, 118.5, 1.5],
            ["PUSCH", "UL", 1, 2, -80.0, -79.0, -1.0],
            ["PDSCH", "DL", 1, 3, 40.0, 39.75, 0.25],
        ],
    )
    existing = {
        "reports/csv/cfo_to_tracking_traces.csv": {
            "artifact_id": 71,
            "logical_path": "reports/csv/cfo_to_tracking_traces.csv",
        }
    }
    fetch = lambda artifact_id: {71: cfo_csv}[artifact_id]

    chart = materializer._specialized_chart_materialization(  # noqa: SLF001
        "CFO true vs estimated vs residual", existing, fetch, 97
    )

    assert chart is not None
    assert chart["source_mapping_status"] == "exact"
    assert chart["source_table_path"] == "reports/csv/cfo_to_tracking_traces.csv"
    csv_text = chart["csv_bytes"].decode("utf-8")
    svg_text = chart["img_bytes"].decode("utf-8")
    assert "true_cfo_hz,estimated_cfo_hz,residual_cfo_hz" in csv_text
    assert "120.0,118.5,1.5" in csv_text
    assert "True CFO" in svg_text and "Estimated CFO" in svg_text and "Residual CFO" in svg_text


def test_runtime_source_selection_skips_unavailable_mirror_row() -> None:
    unavailable = materializer._encode_csv(  # noqa: SLF001
        ["truth_status", "reason"], [["not_available", "runtime mirror was not published"]]
    )
    actual = materializer._encode_csv(  # noqa: SLF001
        ["PreambleDetectionMetric", "PreambleDetectionThreshold", "PDPAverageNoiseFloor"],
        [[0.91, 0.35, 0.02]],
    )
    existing = {
        "reports/csv/prach_correlation_trace.csv": {"artifact_id": 81},
        "air_interface/csv/prach_trials.csv": {"artifact_id": 82},
    }
    payloads = {81: unavailable, 82: actual}
    source, rows = materializer._first_available_rows(  # noqa: SLF001
        existing,
        lambda artifact_id: payloads[artifact_id],
        ["reports/csv/prach_correlation_trace.csv", "air_interface/csv/prach_trials.csv"],
    )
    assert source == "air_interface/csv/prach_trials.csv"
    assert len(rows) == 1


def test_runtime_prach_rs_papr_and_harq_contract_charts_are_exact() -> None:
    prach = materializer._encode_csv(  # noqa: SLF001
        [
            "RAUEId", "PRACHOccasionID", "PRACHOccasionFrame", "PRACHOccasionSlot",
            "PRACHOccasionSymbol", "PreambleIndexTx", "PreambleIndexDetected",
            "PreambleAttemptNumber", "PreambleDetected", "PRACHTrueTimingOffset_samples",
            "PRACHRawTimingEstimate_samples", "PRACHTimingError_samples", "TimingAdvanceCommand",
            "SetupCompleteScheduledSlot", "PDPAverageNoiseFloor",
        ],
        [[1, "frame=0|slot=0|symbol=0|frequency=0", 0, 0, 0, 3, 3, 1, 1, 0, 5, 5, 0, 4, 0.02]],
    )
    dl = materializer._encode_csv(  # noqa: SLF001
        ["Direction", "Frame", "Slot", "MeasuredDMRSRECount", "PTRSRECount", "DataRECount", "PAPR_dB"],
        [["DL", 1, 16, 1632, 408, 14416, 9.5]],
    )
    ul = materializer._encode_csv(  # noqa: SLF001
        ["Direction", "Frame", "Slot", "MeasuredDMRSRECount", "PTRSRECount", "DataRECount", "PAPR_dB"],
        [["UL", 1, 20, 1632, 408, 19176, 10.5]],
    )
    harq = materializer._encode_csv(  # noqa: SLF001
        [
            "Direction", "Slot", "FeedbackDueSlot", "HarqID", "RV", "IsRetransmission",
            "CombinedDecodeOK", "HARQCombiningApplied", "PreviousLLRCount", "CurrentLLRCount",
            "CombinedLLRCount", "LLRCombiningGain_dB", "Goodput_Mbps",
        ],
        [["DL", 16, 19, 0, 0, 0, 1, 0, 0, 32000, 32000, 0, 11.536]],
    )
    existing = {
        "air_interface/csv/prach_trials.csv": {"artifact_id": 91},
        "air_interface/csv/dl_pdsch_trials.csv": {"artifact_id": 92},
        "air_interface/csv/ul_pusch_trials.csv": {"artifact_id": 93},
        "harq/csv/live_harq_observation_timeline.csv": {"artifact_id": 94},
    }
    payloads = {91: prach, 92: dl, 93: ul, 94: harq}
    fetch = lambda artifact_id: payloads[artifact_id]

    for chart_name in (
        "PRACH occasion timeline",
        "DMRS/PTRS occupancy map",
        "PAPR histogram / CDF",
        "RV usage distribution",
        "HARQ RTT distribution",
        "residual BLER after HARQ",
        "goodput vs retransmissions",
        "combiner summary",
    ):
        chart = materializer._specialized_chart_materialization(  # noqa: SLF001
            chart_name, existing, fetch, 98
        )
        assert chart is not None, chart_name
        assert chart.get("source_mapping_status") == "exact", chart_name
        assert chart["csv_bytes"], chart_name
        assert chart["img_bytes"].startswith(b"<svg"), chart_name

    rv_chart = materializer._specialized_chart_materialization(  # noqa: SLF001
        "RV usage distribution", existing, fetch, 98
    )
    assert rv_chart is not None
    assert ",0.0,1.0," in rv_chart["csv_bytes"].decode("utf-8")


def test_runtime_measurement_table_and_channel_reliability_use_trial_truth() -> None:
    dl = materializer._encode_csv(  # noqa: SLF001
        [
            "Direction", "Frame", "Slot", "ConfiguredSNR_dB",
            "AppliedAWGNSNR_dB", "PostEqSINR_dB", "PostEqSINRSource",
            "NMSE_dB", "CRCPass", "MCS", "Modulation", "TargetCodeRate",
        ],
        [
            ["DL", 1, 1, 10, 10, 8.5, "receiver_equalizer", -18.0, 1, 10, "64QAM", 0.5],
            ["DL", 1, 2, 10, 10, 7.8, "receiver_equalizer", -16.5, 0, 10, "64QAM", 0.5],
        ],
    )
    ul = materializer._encode_csv(  # noqa: SLF001
        [
            "Direction", "Frame", "Slot", "ConfiguredSNR_dB",
            "AppliedAWGNSNR_dB", "PostEqSINR_dB", "PostEqSINRSource",
            "NMSE_dB", "CRCPass", "MCS", "Modulation", "TargetCodeRate",
        ],
        [
            ["UL", 1, 1, 10, 10, 9.1, "receiver_equalizer", -20.0, 1, 10, "64QAM", 0.5],
            ["UL", 1, 2, 10, 10, 8.9, "receiver_equalizer", -19.0, 1, 10, "64QAM", 0.5],
        ],
    )
    existing = {
        "air_interface/csv/dl_pdsch_trials.csv": {"artifact_id": 1},
        "air_interface/csv/ul_pusch_trials.csv": {"artifact_id": 2},
    }
    payloads = {1: dl, 2: ul}
    table_result = materializer._specialized_table_materialization(  # noqa: SLF001
        "live_measurement_table", existing, lambda artifact_id: payloads[artifact_id],
        77, "Measurements", {}, {},
    )
    assert table_result is not None
    header, rows = materializer._decode_csv(table_result["data"])  # noqa: SLF001
    assert len(rows) == 4
    assert "configured_snr_db" in header
    assert "posteq_sinr_db" in header
    assert "nmse_db" in header
    assert "source_artifact" in header

    chart_result = materializer._specialized_chart_materialization(  # noqa: SLF001
        "per-channel reliability breakdown", existing,
        lambda artifact_id: payloads[artifact_id], 77,
    )
    assert chart_result is not None
    chart_header, chart_rows = materializer._decode_csv(chart_result["csv_bytes"])  # noqa: SLF001
    assert len(chart_rows) == 2
    by_channel = {row[chart_header.index("channel")]: row for row in chart_rows}
    assert float(by_channel["PDSCH"][chart_header.index("pass_rate")]) == 0.5
    assert float(by_channel["PUSCH"][chart_header.index("pass_rate")]) == 1.0
    assert chart_result["source_mapping_status"] == "exact"


def test_runtime_energy_charts_use_only_persisted_summary_and_state_rows() -> None:
    summary = materializer._encode_csv(  # noqa: SLF001
        [
            "MetricKey", "Entity", "Statistic", "Value", "TextValue", "Unit",
            "Notes", "Availability", "EvidenceType", "ModelVersion",
        ],
        [
            ["ue_energy_per_successful_bit", "UE", "mean", 2.0e-6, "2e-6", "J/bit", "runtime", "AVAILABLE", "runtime_state_conditioned_engineering_model", "lls_energy_accounting_v2"],
            ["gnb_energy_per_successful_bit", "gNB", "mean", 5.0e-6, "5e-6", "J/bit", "runtime", "AVAILABLE", "runtime_state_conditioned_engineering_model", "lls_energy_accounting_v2"],
            ["race_to_sleep_gains", "system", "fractional_gain", "NaN", "", "fraction", "not evaluated", "NOT_EVALUATED", "unavailable", "lls_energy_accounting_v2"],
        ],
    )
    timeline = materializer._encode_csv(  # noqa: SLF001
        [
            "Entity", "Direction", "TimestampSim_ms", "State", "Duration_s",
            "Energy_J", "SuccessfulBits", "TransportBlockId",
        ],
        [
            ["gNB", "DL", 0.0, "active_tx", 0.001, 0.10, 800, "FIXED|DL|point=1"],
            ["UE", "DL", 0.0, "active_rx", 0.001, 0.002, 800, "FIXED|DL|point=1"],
            ["UE", "UL", 1.0, "active_tx", 0.001, 0.02, 400, "FIXED|UL|point=1"],
            ["gNB", "UL", 1.0, "active_rx", 0.001, 0.03, 400, "FIXED|UL|point=1"],
            ["UE", "", 2.0, "idle", 0.002, 0.001, 0, ""],
        ],
    )
    existing = {
        "reports/csv/live_energy_efficiency_table.csv": {
            "artifact_id": 111,
            "logical_path": "reports/csv/live_energy_efficiency_table.csv",
        },
        "rf/csv/energy_timeline_trace.csv": {
            "artifact_id": 112,
            "logical_path": "rf/csv/energy_timeline_trace.csv",
        },
    }
    payloads = {111: summary, 112: timeline}
    fetch = lambda artifact_id: payloads[artifact_id]

    for chart_name in (
        "sleep-state timeline",
        "sleep/idle/active state occupancy",
        "efficiency scatter plots",
        "energy/bit",
        "joules/GB",
        "energy efficiency by UE",
        "energy efficiency by cell",
    ):
        chart = materializer._specialized_chart_materialization(  # noqa: SLF001
            chart_name, existing, fetch, 110
        )
        assert chart is not None, chart_name
        assert chart["source_mapping_status"] == "exact", chart_name
        assert chart["csv_bytes"], chart_name
        assert chart["img_bytes"].startswith(b"<svg"), chart_name
        assert b"Unavailable Without Faking" not in chart["img_bytes"], chart_name

    occupancy = materializer._specialized_chart_materialization(  # noqa: SLF001
        "sleep/idle/active state occupancy", existing, fetch, 110
    )
    assert occupancy is not None
    occupancy_header, occupancy_rows = materializer._decode_csv(  # noqa: SLF001
        occupancy["csv_bytes"]
    )
    states = {row[occupancy_header.index("state")] for row in occupancy_rows}
    assert states == {"active", "idle"}

    joules_gb = materializer._specialized_chart_materialization(  # noqa: SLF001
        "joules/GB", existing, fetch, 110
    )
    assert joules_gb is not None
    header, rows = materializer._decode_csv(joules_gb["csv_bytes"])  # noqa: SLF001
    values = {row[header.index("entity")]: float(row[header.index("value")]) for row in rows}
    assert values == {"UE": 16000.0, "gNB": 40000.0}

    scatter = materializer._specialized_chart_materialization(  # noqa: SLF001
        "efficiency scatter plots", existing, fetch, 110
    )
    assert scatter is not None
    _header, scatter_rows = materializer._decode_csv(scatter["csv_bytes"])  # noqa: SLF001
    assert len(scatter_rows) == 2  # one transmitter-side row for DL and one for UL
