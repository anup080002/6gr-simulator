from __future__ import annotations

import cmath
import csv
import hashlib
import html
import io
import json
import math
import os
import re
from collections import Counter, defaultdict
from contextlib import contextmanager, nullcontext
from pathlib import Path
from typing import Any, Callable

import resvg_py
from PIL import Image, UnidentifiedImageError
from PIL.PngImagePlugin import PngInfo

import lls_output_contract as output_contract
from lls_contract_aliases import (
    CONTRACT_CHART_ALIAS_PATHS,
    CONTRACT_TABLE_ALIAS_PATHS,
    OPTIONAL_6G_CHARTS,
    OPTIONAL_6G_TABLES,
)


MATERIALIZER_VERSION = "2026-09-07-contract-v57-physical-csi-rssi-evidence"
FILESYSTEM_CONTRACT_CACHE_PATH = (
    "artifact_generation/browser_contract_exact_source_cache.json"
)
MAX_PREVIEW_ROWS = 180
MIN_EXPLANATORY_CHART_POINTS = 2
MIN_TREND_CHART_POINTS = 3
OPTIONAL_6G_POLICY_KEYS = (
    "ai_enabled",
    "ntn_enabled",
    "sensing_enabled",
    "localization_enabled",
    "ris_enabled",
    "cell_free_enabled",
    "sub_thz_enabled",
)
OPTIONAL_6G_TABLE_POLICY = {
    "ai_inference_analytics": "ai_enabled",
    "sensing_analytics": "sensing_enabled",
    "localization_analytics": "localization_enabled",
    "ntn_haps_uav_analytics": "ntn_enabled",
    "ris_analytics": "ris_enabled",
    "cell_free_mimo_analytics": "cell_free_enabled",
    "sub_thz_impairment_analytics": "sub_thz_enabled",
}
OPTIONAL_6G_CHART_POLICY = {
    "ai inference confidence / latency": "ai_enabled",
    "sensing p_d / p_fa": "sensing_enabled",
    "localization rmse": "localization_enabled",
    "ntn/haps/uav delay and doppler": "ntn_enabled",
    "ris state summaries": "ris_enabled",
    "cell-free / distributed mimo combining gains": "cell_free_enabled",
    "sub-thz impairment studies": "sub_thz_enabled",
}
EXACT_CHART_FAMILY_CONTRACTS: dict[str, dict[str, Any]] = {
    "heatmap": {
        "source_table": "explicit_direct_alias_only",
        "required_columns": ("x_value", "y_value", "z_value"),
        "allowed_modes": ("heatmap",),
    },
    "timeline": {
        "source_table": "explicit_direct_alias_only",
        "required_columns": ("x_value", "y_value"),
        "allowed_modes": ("line", "scatter"),
    },
    "cdf": {
        "source_table": "explicit_direct_alias_only",
        "required_columns": ("x_value", "y_value"),
        "allowed_modes": ("cdf", "line"),
    },
    "distribution": {
        "source_table": "explicit_direct_alias_only",
        "required_columns": ("x_value", "y_value"),
        "allowed_modes": ("bar", "histogram", "cdf"),
    },
    "scatter": {
        "source_table": "explicit_direct_alias_only",
        "required_columns": ("x_value", "y_value"),
        "allowed_modes": ("scatter",),
    },
    "summary": {
        "source_table": "explicit_direct_alias_only",
        "required_columns": ("x_value", "y_value"),
        "allowed_modes": ("bar", "scatter"),
    },
}


def slugify(value: str) -> str:
    token = re.sub(r"[^a-z0-9]+", "-", str(value or "").strip().lower()).strip("-")
    return token or "contract"


def table_contract_path(table_spec: dict[str, Any]) -> str:
    return str(table_spec.get("logical_path") or "").strip()


def chart_contract_csv_path(chart_spec: dict[str, Any]) -> str:
    kind = str(chart_spec.get("kind") or "reports").strip().lower() or "reports"
    section_slug = str(chart_spec.get("section_slug") or "section").strip().lower() or "section"
    chart_slug = slugify(str(chart_spec.get("chart_name") or "chart"))
    return f"{kind}/csv/contract__{section_slug}__{chart_slug}.csv"


def chart_contract_image_path(chart_spec: dict[str, Any]) -> str:
    kind = str(chart_spec.get("kind") or "reports").strip().lower() or "reports"
    section_slug = str(chart_spec.get("section_slug") or "section").strip().lower() or "section"
    chart_slug = slugify(str(chart_spec.get("chart_name") or "chart"))
    return f"{kind}/image/contract__{section_slug}__{chart_slug}.png"


def optional_6g_features_enabled(feature_policy: dict[str, Any] | None) -> bool:
    policy = feature_policy or {}
    return any(bool(policy.get(key, False)) for key in OPTIONAL_6G_POLICY_KEYS)


def contract_artifact_is_policy_filtered(
    logical_path: str,
    feature_policy: dict[str, Any] | None,
    *,
    contract_name: str = "",
) -> bool:
    """Return whether a contract item is genuinely inapplicable to this run.

    This is configuration-driven only.  It never hides a missing artifact merely
    because no source rows happened to be written: an enabled objective with
    missing runtime evidence must remain missing and fail strict materialization.
    """
    policy = feature_policy or {}
    path = str(logical_path or "").strip().lower().replace("\\", "/")
    name = str(contract_name or "").strip().lower()
    identity = f"{path}|{name}"

    # Component runners execute and qualify one explicit PHY family.  They
    # are not incomplete full-stack runs.  Apply scope only to entries in
    # the canonical browser table catalog; raw component evidence and every
    # table in the owning PDCCH/detection sections remain strict.  This does
    # not inspect whether rows happened to exist and cannot convert missing
    # PDCCH evidence into a pass.
    runner_profile = str(policy.get("runner_profile") or "").strip().lower()
    component_section_ownership = {
        "pdcch_blind_decode_sweep": {
            "dl-control-phy-pdcch",
            "detection-control-analytics",
        },
        "pdcch_strict_validation": {
            "dl-control-phy-pdcch",
            "detection-control-analytics",
        },
        "ctrl6gr_pdcch_study": {
            "dl-control-phy-pdcch",
            "detection-control-analytics",
        },
        "prach_detection": {
            "prach-random-access",
            "detection-control-analytics",
            "random-access-prach-analytics",
        },
        "prach_strict_validation": {
            "prach-random-access",
            "detection-control-analytics",
            "random-access-prach-analytics",
        },
        "srs_strict_validation": {
            "srs-ul-sounding-massive-mimo-inputs",
            "channel-estimation-propagation-analytics",
        },
        "trs_strict_validation": {
            "channel-interference-impairments",
            "channel-estimation-propagation-analytics",
            "impairments-tracking-analytics",
        },
        "pdsch6gr_truth_study": {
            "pdsch-dl-data-chain",
            "channel-interference-impairments",
            "measurements-csi-link-adaptation-inputs",
            "channel-estimation-propagation-analytics",
            "error-reliability-analytics",
            "throughput-goodput-spectral-efficiency-analytics",
            "measurement-csi-link-adaptation-analytics",
            "beamforming-precoding-mimo-analytics",
        },
        "channel_rf_strict_validation": {
            "pdsch-dl-data-chain",
            "pusch-ul-data-chain",
            "channel-interference-impairments",
            "measurements-csi-link-adaptation-inputs",
            "channel-estimation-propagation-analytics",
            "impairments-tracking-analytics",
            "error-reliability-analytics",
        },
        "random_access_four_step": {
            "ssb-pbch-pss-sss",
            "prach-random-access",
            "pucch-f0-f1-f2-f3-f4",
            "detection-control-analytics",
            "random-access-prach-analytics",
        },
        "ai_benchmark": {
            "channel-estimation-propagation-analytics",
            "optional-6g-extension-analytics",
        },
    }
    sweep_base_profile = str(policy.get("sweep_base_profile") or "").strip().lower()
    scoped_runner_profile = (
        sweep_base_profile
        if runner_profile == "generic_sweep"
        and sweep_base_profile in component_section_ownership
        else runner_profile
    )
    if scoped_runner_profile in component_section_ownership:
        table_name = Path(path).stem
        matching_specs = [
            spec
            for kind in ("reports", "analytics")
            for spec in output_contract.iter_table_specs(kind)
            if str(spec.get("table_name") or "").strip().lower() == table_name
        ]
        allowed_sections = {
            "run-trial-scenario-overview",
            "persistence-export-consistency-browser-health",
            "artifact-audit-validation",
            "generic-investigator-views",
            "export-consistency-truth-analytics",
        } | component_section_ownership[scoped_runner_profile]
        if matching_specs and all(
            str(spec.get("section_slug") or "") not in allowed_sections
            for spec in matching_specs
        ):
            return True
        # Chart datasets use generated ``contract__<section>__<chart>``
        # paths, so their stems can never match a table name.  Scope them
        # against the chart catalog explicitly.  The prior table-only
        # lookup left every unrelated chart mandatory for component runs
        # (for example a PRACH-only run was required to publish PDSCH,
        # scheduler, HARQ, beam and RF charts).  Applicability still comes
        # solely from the resolved runner profile and catalog ownership;
        # it never depends on whether runtime rows happened to be absent.
        matching_chart_specs = [
            spec
            for spec in _chart_specs()
            if (
                str(spec.get("chart_name") or "").strip().lower() == name
                or chart_contract_csv_path(spec).lower() == path
            )
        ]
        if matching_chart_specs and all(
            str(spec.get("section_slug") or "") not in allowed_sections
            for spec in matching_chart_specs
        ):
            return True

        # The detection-control section spans several distinct physical
        # channels.  A PRACH-only runner must still publish detector, timing,
        # and noise evidence, but it does not execute a PUCCH receiver or a
        # PBCH/PDCCH/PUCCH decode campaign.  Scope only those named charts;
        # never infer applicability from missing runtime rows.
        if scoped_runner_profile in {"prach_detection", "prach_strict_validation"} and name in {
            "config vs measured conflict dashboard",
            "reports_config_vs_measured_conflicts_v",
            "pucch dtx statistics",
            "control decode success/failure tables",
        }:
            return True

        # A PDCCH component campaign owns PDCCH detection probabilities, CCE
        # monitoring and PDCCH DM-RS evidence. It does not execute PRACH,
        # PUCCH or a complete connected-link config-vs-measured audit. Narrow
        # the shared detection section using the declared component profile;
        # never infer applicability from missing runtime rows.
        if scoped_runner_profile in {
            "pdcch_blind_decode_sweep",
            "pdcch_strict_validation",
            "ctrl6gr_pdcch_study",
        } and name in {
            "config vs measured conflict dashboard",
            "prach correlation peak distributions",
            "prach noise floor distributions",
            "prach peak search results",
            "pucch dtx statistics",
        }:
            return True

        # The AI channel-estimation benchmark owns estimator input/output and
        # quality evidence, but it does not execute a propagation/channel
        # realization.  Requiring the propagation aggregate would either
        # force fabricated path evidence or fail every valid AI-only run.
        # Scope this from the declared runner profile, never from missing rows.
        if scoped_runner_profile == "ai_benchmark" and name in {
            "propagation_analytics",
            "config vs measured conflict dashboard",
            "reports_config_vs_measured_conflicts_v",
            "value semantics coverage chart",
            "reports_value_semantics_coverage_v",
        }:
            return True

    # Raster output is controlled by the resolved YAML.  Chart contract
    # entries use a generated ``contract__`` CSV plus its PNG, so filtering
    # the chart dataset here disables the complete chart pair without hiding
    # any primary runtime table.  Publication-enabled runs remain strict.
    if (
        policy.get("raster_output_enabled") is False
        and "/csv/contract__" in path
    ):
        return True

    feature_key = OPTIONAL_6G_TABLE_POLICY.get(name)
    if feature_key is None:
        feature_key = OPTIONAL_6G_CHART_POLICY.get(name)
    if feature_key is not None:
        return not bool(policy.get(feature_key, False))

    if not bool(policy.get("fixed_link_campaign_enabled", False)) and name in {
        "fixed_snr_sweep_audit",
        "fixed_snr_sweep_curve_summary",
        "dl_fixed_snr_bler_curve",
        "ul_fixed_snr_bler_curve",
    }:
        return True

    if bool(policy.get("fixed_link_campaign_only", False)) and (
        name in {
            "distance_vs_sinr",
            "distance vs sinr",
            "distance vs sinr scatter",
            "topology_map",
            "ue_trajectory_xy",
        }
        or "distance_vs_sinr.csv" in path
    ):
        return True

    # Pairwise UE-distance evidence is mathematically undefined for a
    # single-UE scenario.  Applicability comes exclusively from the resolved
    # YAML user count; absence of runtime rows is never used as a filter.
    if (
        int(policy.get("num_ues", 0) or 0) == 1
        and (
            name == "inter_ue_distance_validation"
            or Path(path).name == "inter_ue_distance_validation.csv"
        )
    ):
        return True

    # A fixed-link calibration campaign directly exercises transport blocks
    # at controlled SNR points. It has no connected-mode mobility state,
    # packet queues, MAC scheduler cycles, per-UE traffic timeline, DRX or
    # PHY/MAC API exchange. These are configuration-inapplicable, not
    # missing waveform evidence. Enabled PHY measurement, grid, RF and
    # energy families are deliberately not included here.
    if bool(policy.get("fixed_link_campaign_only", False)):
        fixed_link_inapplicable_tables = {
            "live_candidate_cell_table.csv",
            "live_mobility_state.csv",
            "live_measurement_filter_state.csv",
            "live_selection_state.csv",
            "live_reselection_state.csv",
            "live_event_trigger_table.csv",
            "live_prb_allocation_snapshot.csv",
            "live_re_allocation_snapshot.csv",
            "live_scheduler_cycle.csv",
            "live_dl_scheduler_grants.csv",
            "live_ul_scheduler_grants.csv",
            "live_queue_state.csv",
            "live_buffer_status.csv",
            "live_hol_delay_state.csv",
            "live_qos_state.csv",
            "live_bsr_state.csv",
            "live_ack_nack_table.csv",
            "live_soft_buffer_table.csv",
            "live_pdsch_mapping_table.csv",
            "live_uci_table.csv",
            "live_ue_state_table.csv",
            "live_ue_measurement_state.csv",
            "live_ue_power_state.csv",
            "live_drx_state.csv",
            "live_per_ue_context.csv",
            "live_phy_mac_api_table.csv",
            "doppler_reconciliation.csv",
            "fairness_analytics.csv",
            "mobility_analytics.csv",
            "selection_reselection_analytics.csv",
            # Fixed-link calibration has no geometry/system-user state.  These
            # tables are valid only when their owning runtime family executes;
            # a schema-only file is not missing evidence for this run class.
            "live_coverage_layer.csv",
            "live_user_performance_snapshot.csv",
        }
        if Path(path).name in fixed_link_inapplicable_tables:
            return True
        fixed_link_inapplicable_charts = {
            "candidate cell rank heatmap",
            "scheduled prbs per ue over time",
            "queue depth over time",
            "hol delay over time",
            "scheduler fairness over time",
            "sr/bsr event timeline",
            "grant reason distribution",
            "rv usage distribution",
            "aggregation level distribution",
            "cce usage heatmap",
            "ue tx power timeline",
            "drx state timeline",
            "ue energy proxy timeline",
            "per-cell context health timeline",
            "throughput over time",
            "goodput over time",
            "per-ue throughput",
            "throughput percentile plots",
            "throughput cdf",
            "fairness index trend",
            # Fixed-link calibration has no executed cell identity.  A gNB
            # aggregate can support system energy/bit, but calling that value
            # "by cell" would invent a cell grouping that is absent from the
            # runtime rows.
            "energy efficiency by cell",
        }
        if name in fixed_link_inapplicable_charts:
            return True

    if not bool(policy.get("scheduler_runtime_enabled", False)) and (
        "scheduler" in name
        or name in {
            "mcs over time",
            "sr/bsr event timeline",
            "grant reason distribution",
            "rv usage distribution",
        }
    ):
        return True

    if not bool(policy.get("traffic_runtime_enabled", False)) and name in {
        "throughput over time",
        "goodput over time",
        "per-ue throughput",
        "throughput percentile plots",
        "throughput cdf",
        "fairness index trend",
    }:
        return True

    table_name = Path(path).name
    if not bool(policy.get("geometry_enabled", False)) and table_name in {
        "live_site_table.csv",
        "live_sector_table.csv",
        "live_trp_table.csv",
        "live_cell_table.csv",
        "live_ue_table.csv",
        "live_link_table.csv",
        "live_path_geometry_table.csv",
        "live_candidate_cell_table.csv",
    }:
        return True
    if not bool(policy.get("raw_grid_capture_enabled", False)) and table_name == "live_re_allocation_snapshot.csv":
        return True
    if (
        not bool(policy.get("csi_enabled", False))
        and table_name == "live_csirs_stats.csv"
    ):
        return True
    if (
        not bool(policy.get("beam_adaptation_enabled", False))
        and int(policy.get("beam_count", 1) or 1) <= 1
        and table_name == "live_beam_p1_acquisition_stats.csv"
    ):
        return True
    if not bool(policy.get("power_control_enabled", False)) and table_name == "live_power_control_state.csv":
        return True
    if bool(policy.get("fixed_mcs_mode", False)) and table_name in {
        "live_link_adaptation_input_table.csv",
        "link_adaptation_analytics.csv",
        "cqi_mcs_consistency_analytics.csv",
    }:
        return True
    if not bool(policy.get("csi_enabled", False)) and table_name == "measurement_feedback_analytics.csv":
        return True
    if not bool(policy.get("raw_iq_capture_enabled", False)) and table_name in {
        "waveform_analytics.csv",
        "waveform_stage_overlay_analytics.csv",
    }:
        return True
    if not bool(policy.get("constellation_capture_enabled", False)) and table_name == "constellation_analytics.csv":
        return True
    if not bool(policy.get("raw_grid_capture_enabled", False)) and table_name == "resource_grid_analytics.csv":
        return True
    if not bool(policy.get("prach_collision_enabled", False)) and table_name == "re_collision_analytics.csv":
        return True
    if not bool(policy.get("harq_enabled", False)) and table_name == "soft_buffer_analytics.csv":
        return True
    if not bool(policy.get("profiler_enabled", False)) and table_name == "runtime_latency_analytics.csv":
        return True
    if not bool(policy.get("energy_enabled", False)) and table_name in {
        "live_power_runtime_table.csv",
        "live_rf_power_table.csv",
        "live_bb_power_table.csv",
        "live_energy_efficiency_table.csv",
        "live_sleep_state_table.csv",
        "power_analytics.csv",
        "energy_efficiency_analytics.csv",
        "runtime_power_analytics.csv",
        "sleep_state_analytics.csv",
    }:
        return True
    if policy.get("storage_backend", "") == "filesystem" and table_name == "reports_all_stage_exec_v.csv":
        return True

    if (
        bool(policy.get("fixed_link_campaign_only", False))
        and not bool(policy.get("beam_adaptation_enabled", False))
        and int(policy.get("beam_count", 1) or 1) <= 1
        and name in {
            "selected beam timeline",
            "precoder / beam selection timeline",
            "selected vs best beam timeline",
            "beam gain gap histogram",
            "beam hit rate timeline",
            "per-beam quality plot",
            "beam id timeline",
            "beam pair timeline",
            "selected vs best beam gap",
            "beam hit rate / top-k hit rate",
        }
    ):
        return True

    if not bool(policy.get("csi_enabled", False)) and name in {
        "cqi / pmi / ri / cri timeline",
        "cqi / pmi / ri / cri / ssbri trends",
        "cqi vs selected mcs",
        "csi-rs resource occupancy",
        "csi-rs map",
        "cqi-to-mcs mapping plot",
        "selected mcs distribution",
        "selected vs derived mcs confusion matrix",
        "quality-vs-selected-mcs mismatch plot",
    }:
        return True

    if (
        bool(policy.get("fixed_link_campaign_only", False))
        and not bool(policy.get("rank_adaptation_enabled", False))
        and int(policy.get("max_spatial_rank", 1) or 1) <= 1
        and name in {"rank distribution", "active rank vs power", "port usage chart"}
    ):
        return True

    if (
        bool(policy.get("fixed_link_campaign_only", False))
        and int(policy.get("max_spatial_rank", 1) or 1) <= 1
        and not bool(policy.get("beam_adaptation_enabled", False))
        and name in {
            "condition number distribution",
            "mu grouping summary",
            "mu grouping analytics",
            "antenna element layout",
            "antenna radiation pattern",
            "beam pattern 3d",
        }
    ):
        return True

    # A channel-condition-number distribution is not a scalar-rank KPI.  In
    # a rank-one-only campaign the effective channel is a vector and the
    # matrix condition number is mathematically undefined (the MATLAB PHY
    # exporter records ConditionNumberStatus=not_applicable_rank_deficient).
    # Disable this chart from authoritative rank policy rather than emitting
    # a placeholder, replacing NaN with a made-up number, or failing the
    # browser contract for evidence that cannot exist in this campaign.
    if int(policy.get("max_spatial_measurement_rank", policy.get("max_spatial_rank", 1)) or 1) <= 1 and name == "condition number distribution":
        return True

    if not bool(policy.get("absolute_rx_power_calibrated", False)) and name in {
        "rsrp/csi-rsrp timeline",
        "servingrsrp / rsrp / csi-rsrp trends",
    }:
        return True

    if not bool(policy.get("geometry_enabled", False)) and (
        name == "geometry_runtime_audit"
        or "geometry_runtime_audit.csv" in path
        or name in {
            "topology_map",
            "ue_trajectory_xy",
            "bs/sector/ue topology scatter plot",
            "serving cell map",
            "candidate cell rank heatmap",
            "distance distribution histogram",
            "azimuth/elevation rose plots",
            "path geometry summary charts",
        }
    ):
        return True

    if not bool(policy.get("mobility_enabled", False)) and name in {
        "ue trajectory overlay",
        "mobility event timeline",
        "doppler vs speed plot",
        "doppler_vs_slot",
        "ue_trajectory_xy",
        "ue trajectory views",
        "serving cell timeline",
        "neighbor ranking timeline",
        "selection/reselection trigger tables",
        "selection/reselection trigger histogram",
        "hysteresis / ttt scatter",
        "hysteresis / ttt studies",
        "mobility robustness summaries",
        "access delay vs mobility",
        "measurement filtering analytics",
    }:
        return True

    if not bool(policy.get("handover_enabled", False)) and (
        "handover" in identity or name == "live_handover_state"
    ):
        return True

    if not bool(policy.get("comparison_enabled", False)) and name in {
        "kpi delta tables",
        "baseline vs candidate overlays",
        "throughput delta",
        "bler delta",
        "ber delta",
        "evm delta",
        "nmse delta",
        "p_fa / p_md delta",
        "harq delta",
        "beam hit/gap delta",
        "latency delta",
        "power / energy delta",
        "determinism delta",
        "schema drift delta",
        "fallback / placeholder / smoke regressions",
    }:
        return True

    if not bool(policy.get("harq_enabled", False)) and (
        "harq" in name
        or name in {
            "combining gain histogram",
            "retransmission count histogram",
            "ack/nack timeline",
            "retransmission rate trend",
            "newtx vs retx comparison",
            "residual failure patterns",
            "residual bler after harq",
            "goodput vs retransmissions",
            "combiner summary",
        }
    ):
        return True

    if not bool(policy.get("profiler_enabled", False)) and name in {
        "pdcch stage latency waterfall",
        "pbch stage latency",
        "csi-rs latency trend",
        "ldpc stage latency waterfall",
        "channel estimation latency",
        "equalizer latency",
        "per-format latency histograms",
        "api message rate",
        "orchestration latency chart",
        "per-worker workload chart",
        "cpu cycles and memory usage time series",
        "latency breakdown stacked chart",
        "db write latency over time",
        "export lag over time",
        "artifact creation rate",
        "block execution time",
        "stage latency",
        "end-to-end latency",
        "compute latency",
        "decode latency",
        "cpu cycles",
        "memory usage",
        "worker timelines",
        "lock/contention observations",
        "db write latency",
        "export lag",
        "single-thread vs multi-thread determinism",
    }:
        return True

    # A distribution across users is undefined for a one-UE run.  Keep the
    # measured per-UE operating point, but do not manufacture a singleton CDF
    # or percentile distribution and present it as population evidence.
    if int(policy.get("num_ues", 0) or 0) < 2 and name in {
        "throughput cdf",
        "throughput percentile plots",
    }:
        return True

    # The MATLAB profiler captures elapsed time and call counts only.  These
    # contracts require separate operating-system, worker, persistence or
    # paired-run instrumentation.  They are inapplicable unless an explicit
    # scenario authority enables that measurement family; profiler_enabled
    # alone must not imply measurements that MATLAB did not take.
    if not bool(policy.get("resource_profiler_enabled", False)) and name in {
        "cpu power if available",
        "cpu cycles and memory usage time series",
        "cpu cycles",
        "memory usage",
    }:
        return True
    if not bool(policy.get("worker_profiler_enabled", False)) and name in {
        "per-worker workload chart",
        "worker timelines",
        "lock/contention observations",
    }:
        return True
    if not bool(policy.get("database_profiler_enabled", False)) and name in {
        "db write latency over time",
        "db write latency",
    }:
        return True
    if not bool(policy.get("artifact_timing_enabled", False)) and name in {
        "export lag over time",
        "artifact creation rate",
        "export lag",
    }:
        return True
    if not bool(policy.get("api_profiler_enabled", False)) and name == "api message rate":
        return True
    if not bool(policy.get("parallel_determinism_enabled", False)) and name == "single-thread vs multi-thread determinism":
        return True

    if not bool(policy.get("rf_impairments_enabled", False)) and name in {
        "impairment contribution bar chart",
        "iq imbalance summary",
        "phase noise summary",
        "pa nonlinearity summary",
        "clipping summary",
        "quantization summary",
        "impairment order trace",
        "contribution decomposition if measurable",
        "pa backoff distribution",
        "rf chain power",
        "thermal/throttling analytics if available",
    }:
        return True

    if not bool(policy.get("power_control_enabled", False)) and name in {
        "power control command timeline",
        "phr distribution",
        "ue power headroom timeline",
        "ul tx power per ue",
        "power control behavior",
    }:
        return True

    if not bool(policy.get("raw_iq_capture_enabled", False)) and name in {
        "pre-channel waveform",
        "post-channel waveform",
        "post-impairment waveform",
        "stage overlay plots",
        "ue-wise / link-wise waveform comparison",
        "pre-equalization constellation",
        "tx waveform",
        "rx waveform",
        "magnitude vs sample",
        "phase vs sample",
        "power vs sample",
        "psd",
        "occupied bandwidth",
        "out-of-band spectral summaries if measurable",
        "power spectral comparison before/after impairment",
    }:
        return True

    if not bool(policy.get("constellation_capture_enabled", False)) and name in {
        "post-equalization constellation",
        "constellation per layer",
        "constellation per codeword",
        "constellation per modulation order",
        "evm per symbol",
        "evm per subcarrier",
        "evm per layer",
        "symbol decision error histogram",
    }:
        return True

    if not bool(policy.get("raw_grid_capture_enabled", False)) and name in {
        "dmrs/ptrs occupancy plot",
        "dmrs/ptrs occupancy map",
        "frame/slot/symbol occupancy timeline",
        "prb heatmap",
        "re occupancy heatmap",
        "dl/ul/guard slot pattern chart",
        "dl resource-grid heatmap",
        "ul resource-grid / equalized symbol summaries",
        "pdsch map",
        "pusch map",
    }:
        return True

    if not bool(policy.get("channel_snapshot_capture_enabled", False)) and name in {
        "true h(tau) if available",
        "estimated hhat(tau)",
        "channel impulse response",
        "true h(f) if available",
        "estimated hhat(f)",
        "channel magnitude heatmap",
        "channel phase heatmap",
        "tap power profile",
        "channel heatmap artifact links",
    }:
        return True

    if not bool(policy.get("pathloss_enabled", False)) and name in {
        "distance distribution histogram",
        "azimuth/elevation rose plots",
        "path geometry summary charts",
        "pathloss/shadowing distributions",
        "pathloss distribution",
        "o2i distribution",
    }:
        return True

    if not bool(policy.get("shadowing_enabled", False)) and name == "shadowing distribution":
        return True

    if not bool(policy.get("o2i_enabled", False)) and name == "o2i distribution":
        return True

    if not bool(policy.get("interference_enabled", False)) and name in {
        "interference power timeline",
        "serving vs interferer decomposition",
        "inter-user leakage",
    }:
        return True

    if not bool(policy.get("initial_access_enabled", False)) and (
        any(token in name for token in ("ssb", "pbch", "access latency", "retry count", "timing advance"))
        or "initial-access" in path
    ):
        return True

    pdcch_component_detection_metric = (
        scoped_runner_profile
        in {
            "pdcch_blind_decode_sweep",
            "pdcch_strict_validation",
            "ctrl6gr_pdcch_study",
        }
        and name in {"p_fa", "far", "p_md", "p_d"}
    )
    if not bool(policy.get("prach_enabled", False)) and not pdcch_component_detection_metric and (
        "prach" in name
        or "preamble" in name
        or name in {
            "peak value histogram",
            "noise floor trend",
            "access attempt/success timeline",
            "collision summary if modeled",
            "p_fa",
            "far",
            "p_md",
            "p_d",
            "detection rate",
            "false alarm rate",
            "missed detection rate",
        }
    ):
        return True

    if not bool(policy.get("prach_runtime_required", True)) and name in {
        "prach peak search timeline",
        "noise floor trend",
        "peak value histogram",
        "preamble usage chart",
        "ta estimate trend",
        "access attempt/success timeline",
        "prach correlation peak distributions",
        "prach noise floor distributions",
        "prach peak search results",
        "threshold sweep plots if data exists",
        "access latency",
        "retry count distribution",
        "timing advance distribution",
        "preamble/root/cyclic-shift usage summary",
        "timing offset true vs estimated vs residual",
        "ta estimate timeline",
        "prach opportunity map",
    }:
        return True

    if not bool(policy.get("pbch_runtime_required", True)) and name == "pbch decode retry timeline":
        return True

    if not bool(policy.get("fading_enabled", False)) and name in {
        "delay spread chart",
        "angle spread chart",
    }:
        return True

    if not bool(policy.get("prach_collision_enabled", True)) and name in {
        "collision summary if modeled",
        "re collision heatmap / table",
    }:
        return True

    if (
        not bool(policy.get("prach_threshold_sweep_enabled", True))
        and name == "threshold sweep plots if data exists"
    ):
        return True

    if (
        not bool(policy.get("reciprocity_calibration_enabled", True))
        and name == "calibration / reciprocity diagnostics if modeled"
    ):
        return True

    if not bool(policy.get("profiler_enabled", False)) and name == "cpu power if available":
        return True

    if not bool(policy.get("pdcch_enabled", False)) and (
        "pdcch" in name or "coreset" in name
    ):
        return True

    if not bool(policy.get("initial_access_enabled", False)) and name == "sync success/failure timeline if available":
        return True

    if (
        not bool(policy.get("pdcch_enabled", False))
        and not bool(policy.get("pucch_enabled", False))
        and not bool(policy.get("initial_access_enabled", False))
        and name == "control decode success/failure tables"
    ):
        return True

    if not bool(policy.get("pucch_enabled", False)) and "pucch" in name:
        return True
    if not bool(policy.get("pucch_enabled", False)) and name == "uci bit count distribution":
        return True

    # Standalone PUCCH and UCI transferred onto PUSCH are different PHY
    # evidence families. Only an explicit YAML runtime gate may make the
    # standalone PUCCH contracts inapplicable; absence of rows alone never
    # hides them.
    if not bool(policy.get("pucch_runtime_required", policy.get("pucch_enabled", False))):
        if path.endswith("/pucch_trials.csv") or name in {
            "live_pucch_summary",
            "live_pucch_f0_table",
            "live_pucch_f1_table",
            "live_pucch_f2_table",
            "live_pucch_f3_table",
            "live_pucch_f4_table",
            "requested vs resolved format confusion matrix",
            "pucch decode success/failure trend",
            "ack/nack match chart",
            "dtx detection chart",
            "pucch dtx statistics",
            "per-format latency histograms",
            "per-format reliability breakdown",
        }:
            return True

    if not bool(policy.get("srs_enabled", False)) and "srs" in name:
        return True

    if not bool(policy.get("energy_enabled", False)) and (
        "energy" in name
        or "power vs" in name
        or name in {"joules/gb", "papr vs power", "sleep-state timeline", "sleep/idle/active state occupancy"}
    ):
        return True

    match = re.fullmatch(r"live_pucch_f([0-4])_table", name)
    if match:
        enabled_formats = {
            str(value).strip()
            for value in policy.get("active_pucch_formats", ["0"])
        }
        return match.group(1) not in enabled_formats
    return False


def manifest_logical_path() -> str:
    return "reports/csv/contract_materialization_manifest.csv"


def coverage_logical_path() -> str:
    return "reports/csv/contract_materialization_coverage.csv"


def plot_lineage_logical_path() -> str:
    return "reports/csv/contract_plot_lineage.csv"


def _contract_plot_lineage_row(
    plot_id: str,
    image_path: str,
    source_csv_path: str,
    image_bytes: bytes,
    source_csv_bytes: bytes,
) -> list[Any]:
    """Build exact raster-to-dataset lineage for one browser contract chart."""
    with Image.open(io.BytesIO(image_bytes)) as image:
        image.load()
        width, height = image.size
        mime_type = Image.MIME.get(image.format or "", "image/png")
    return [
        str(plot_id),
        str(image_path),
        str(source_csv_path),
        hashlib.sha256(source_csv_bytes).hexdigest(),
        hashlib.sha256(image_bytes).hexdigest(),
        int(width),
        int(height),
        str(mime_type or "image/png"),
        1,
        1,
        "apps.lls_contract_materializer",
        "pass",
        "",
    ]


def _append_filesystem_contract_alias_lineage(
    run_folder: str,
    plot_lineage_rows: list[list[Any]],
) -> None:
    """Bind persisted contract-name aliases to their exact CSV and PNG bytes.

    A small set of browser compatibility names is published in addition to
    the canonical chart catalog name (for example ``bler-vs-measured-sinr``).
    They are real raster aliases, not new scientific plots.  Filesystem
    publication must nevertheless bind each alias to its same-stem runtime
    dataset so the recursive visual audit never treats it as unmanifested.
    """

    root = Path(str(run_folder or ""))
    if not root.is_dir():
        return
    already_lineaged = {
        str(row[1]).replace("\\", "/")
        for row in plot_lineage_rows
        if len(row) > 1
    }
    for image_path in sorted(root.rglob("contract__*.png")):
        try:
            image_relative = image_path.relative_to(root).as_posix()
        except ValueError:
            continue
        if image_relative in already_lineaged:
            continue
        parts = list(Path(image_relative).parts)
        if "image" not in parts:
            continue
        image_index = parts.index("image")
        parts[image_index] = "csv"
        parts[-1] = f"{image_path.stem}.csv"
        source_relative = Path(*parts).as_posix()
        source_path = root / Path(*parts)
        if not source_path.is_file():
            continue
        image_bytes = _windows_long_path(image_path).read_bytes()
        source_bytes = _windows_long_path(source_path).read_bytes()
        plot_lineage_rows.append(
            _contract_plot_lineage_row(
                f"contract_alias__{slugify(image_path.stem)}",
                image_relative,
                source_relative,
                image_bytes,
                source_bytes,
            )
        )
        already_lineaged.add(image_relative)


def _decode_csv(data: bytes) -> tuple[list[str], list[list[str]]]:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        text = data.decode("utf-8", "ignore")
    with _csv_field_limit_for_payload(data):
        rows = list(csv.reader(io.StringIO(text)))
    if not rows:
        return [], []
    return [str(item) for item in rows[0]], [[str(cell) for cell in row] for row in rows[1:]]


def _encode_csv(header: list[str], rows: list[list[Any]]) -> bytes:
    buf = io.StringIO()
    writer = csv.writer(buf, lineterminator="\n")
    writer.writerow(header)
    for row in rows:
        writer.writerow(list(row))
    return buf.getvalue().encode("utf-8")


def _coerce_float(value: Any) -> float | None:
    if value in (None, ""):
        return None
    try:
        number = float(value)
    except Exception:
        return None
    if not math.isfinite(number):
        return None
    return number


def _column_values(rows: list[list[str]], idx: int) -> list[str]:
    return [row[idx] if idx < len(row) else "" for row in rows]


def _column_index(header: list[str], *names: str) -> int | None:
    exact = {str(name or "").strip().lower(): idx for idx, name in enumerate(header)}
    normalized = {_normalized_header_token(name): idx for idx, name in enumerate(header)}
    for name in names:
        key = str(name or "").strip().lower()
        if key in exact:
            return exact[key]
        norm_key = _normalized_header_token(name)
        if norm_key in normalized:
            return normalized[norm_key]
    return None


def _normalized_header_token(name: Any) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(name or "").strip().lower())


def _chart_family(chart_name: str) -> str:
    text = str(chart_name or "").strip().lower()
    if "heatmap" in text or re.search(r"(^|[^a-z])map([^a-z]|$)", text):
        return "heatmap"
    if "timeline" in text or "over time" in text or "trend" in text or "time series" in text:
        return "timeline"
    if "cdf" in text:
        return "cdf"
    if "histogram" in text or "distribution" in text:
        return "distribution"
    if "scatter" in text or " vs " in text or " plot" in text or text.endswith("plot"):
        return "scatter"
    return "summary"


def _dataset_from_exact_chart_contract(
    chart_name: str,
    source_table_path: str,
    header: list[str],
    rows: list[list[str]],
) -> tuple[dict[str, Any] | None, str, str]:
    """Build a chart only from declared canonical chart columns.

    The materializer intentionally refuses free-form numeric-column discovery in
    strict/conformance output. A direct source may render only when it already
    exposes a canonical chart dataset schema; otherwise the caller emits an
    unavailable/invalid reason card.
    """
    if not header or not rows:
        return None, "unavailable", "The direct chart source table is missing or empty."

    family = _chart_family(chart_name)
    contract = EXACT_CHART_FAMILY_CONTRACTS.get(family, EXACT_CHART_FAMILY_CONTRACTS["summary"])
    required_columns = tuple(str(name) for name in contract["required_columns"])
    missing_columns = [name for name in required_columns if _column_index(header, name) is None]
    if missing_columns:
        return None, "invalid", (
            f"{family} charts require an explicit direct source table with exact columns "
            f"{', '.join(required_columns)}. Missing: {', '.join(missing_columns)}. "
            "Generic numeric-column inference is disabled."
        )
    x_idx = _column_index(header, "x_value")
    y_idx = _column_index(header, "y_value")
    z_idx = _column_index(header, "z_value")
    mode_idx = _column_index(header, "chart_mode")
    label_x_idx = _column_index(header, "x_label")
    label_y_idx = _column_index(header, "y_label")
    label_z_idx = _column_index(header, "z_label")

    if family == "heatmap":
        if x_idx is None or y_idx is None or z_idx is None:
            return None, "invalid", (
                "Heatmap/map charts require an exact direct source with x_value, "
                "y_value, and z_value columns; generic numeric table columns are not accepted."
            )
        raw_rows: list[dict[str, Any]] = []
        for row in rows:
            x_raw = row[x_idx] if x_idx < len(row) else ""
            y_raw = row[y_idx] if y_idx < len(row) else ""
            z_val = _coerce_float(row[z_idx] if z_idx < len(row) else "")
            if not str(x_raw).strip() or not str(y_raw).strip() or z_val is None:
                continue
            raw_rows.append({"x_value": str(x_raw), "y_value": str(y_raw), "z_value": float(z_val)})
        if not raw_rows:
            return None, "invalid", "The exact heatmap source columns exist, but no finite z_value samples were present."
        x_labels, y_labels, matrix = _grid_rows_to_heatmap(raw_rows, "x_value", "y_value", "z_value")
        if not x_labels or not y_labels or not matrix:
            return None, "invalid", "The exact heatmap source could not form a non-empty x/y/z grid."
        x_label = _first_nonblank_column_value(rows, label_x_idx) or "x_value"
        y_label = _first_nonblank_column_value(rows, label_y_idx) or "y_value"
        z_label = _first_nonblank_column_value(rows, label_z_idx) or "z_value"
        points = [[row["x_value"], row["y_value"], row["z_value"]] for row in raw_rows[:MAX_PREVIEW_ROWS]]
        return {
            "mode": "heatmap",
            "x_label": x_label,
            "y_label": y_label,
            "z_label": z_label,
            "x_labels": x_labels,
            "y_labels": y_labels,
            "matrix": matrix,
            "points": points,
        }, "exact", f"Exact heatmap/map source mapping from {source_table_path}."

    points: list[list[float]] = []
    for row in rows:
        x_val = _coerce_float(row[x_idx] if x_idx < len(row) else "")
        y_val = _coerce_float(row[y_idx] if y_idx < len(row) else "")
        if x_val is None or y_val is None:
            continue
        points.append([float(x_val), float(y_val)])
    if not points:
        return None, "invalid", "The exact x_value/y_value source columns exist, but no finite samples were present."

    unique_y = {round(point[1], 12) for point in points}
    if len(unique_y) <= 1 and len(points) > 1:
        return None, "invalid", "The exact source has a constant/single y-series, so it is not rendered as a real chart."

    mode = _first_nonblank_column_value(rows, mode_idx).lower()
    if not mode:
        mode = "line" if family == "timeline" else "scatter"
    allowed_modes = set(str(mode) for mode in contract["allowed_modes"])
    if mode not in allowed_modes:
        mode = "scatter" if "scatter" in allowed_modes else sorted(allowed_modes)[0]
    if mode == "line":
        unique_x = {round(point[0], 12) for point in points}
        if len(points) < 3 or len(unique_x) < 3:
            return None, "invalid", "Line charts require at least three finite points and three unique x values."

    x_label = _first_nonblank_column_value(rows, label_x_idx) or "x_value"
    y_label = _first_nonblank_column_value(rows, label_y_idx) or "y_value"
    return {
        "mode": mode,
        "x_label": x_label,
        "y_label": y_label,
        "points": points[:MAX_PREVIEW_ROWS],
    }, "exact", f"Exact canonical x/y source mapping from {source_table_path}."


def _first_nonblank_column_value(rows: list[list[str]], idx: int | None) -> str:
    if idx is None:
        return ""
    for row in rows:
        if idx < len(row):
            value = str(row[idx] or "").strip()
            if value:
                return value
    return ""


def _source_mapping_status_for_status(*statuses: str) -> str:
    text = " ".join(str(status or "").strip().lower() for status in statuses)
    if "invalid" in text:
        return "invalid"
    if (
        "unavailable" in text
        or "missing" in text
        or "empty" in text
        or "placeholder" in text
        or "reason_svg" in text
        or "source_artifact_present_but_empty" in text
    ):
        return "unavailable"
    return "exact"


def _ensure_source_mapping_status_csv(data: bytes, source_mapping_status: str) -> bytes:
    header, rows = _decode_csv(data)
    if not header:
        return data
    status = str(source_mapping_status or "unavailable").strip().lower()
    if status not in {"exact", "unavailable", "invalid"}:
        status = "unavailable"
    lower = [str(name or "").strip().lower() for name in header]
    if "source_mapping_status" in lower:
        idx = lower.index("source_mapping_status")
        for row in rows:
            while len(row) <= idx:
                row.append("")
            if not str(row[idx] or "").strip():
                row[idx] = status
        return _encode_csv(header, rows)
    return _encode_csv(header + ["source_mapping_status"], [row + [status] for row in rows])


def _finalize_chart_materialization_result(result: dict[str, Any] | None) -> dict[str, Any] | None:
    if result is None:
        return None
    out = dict(result)
    source_mapping_status = str(out.get("source_mapping_status") or "").strip().lower()
    if source_mapping_status not in {"exact", "unavailable", "invalid"}:
        source_mapping_status = _source_mapping_status_for_status(out.get("csv_status", ""), out.get("image_status", ""))
    out["source_mapping_status"] = source_mapping_status
    if "csv_bytes" in out:
        out["csv_bytes"] = _ensure_source_mapping_status_csv(bytes(out["csv_bytes"]), source_mapping_status)
    return out


def _rasterize_contract_png(
    image_bytes: bytes,
    *,
    source_mime_type: str = "",
    source_logical_path: str = "",
) -> bytes:
    """Return a validated PNG for every persisted contract image.

    Contract renderers intentionally remain vector-first internally so text and
    axes stay easy to compose.  This function is the persistence boundary: SVG,
    JPEG, and other Pillow-readable image inputs are decoded and re-encoded as
    real PNG bytes.  Invalid or unsupported image evidence fails loudly instead
    of being copied beneath a misleading ``.png`` suffix.
    """
    payload = bytes(image_bytes or b"")
    if not payload:
        raise ValueError("Cannot persist an empty contract image as PNG.")

    mime = str(source_mime_type or "").strip().lower()
    path = str(source_logical_path or "").strip().lower()
    prefix = payload.lstrip()[:256].lower()
    is_svg = (
        mime == "image/svg+xml"
        or path.endswith(".svg")
        or prefix.startswith(b"<svg")
        or b"<svg" in prefix
    )
    semantic_description = ""
    try:
        if is_svg:
            svg_text = payload.decode("utf-8-sig")
            semantic_description = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", svg_text))).strip()[:12000]
            png_bytes = resvg_py.svg_to_bytes(
                svg_string=svg_text,
                background="#ffffff",
                text_rendering="optimize_legibility",
                image_rendering="optimize_quality",
            )
        else:
            with Image.open(io.BytesIO(payload)) as source_image:
                source_image.load()
                if source_image.mode not in {"RGB", "RGBA"}:
                    source_image = source_image.convert("RGBA" if "transparency" in source_image.info else "RGB")
                output = io.BytesIO()
                source_image.save(output, format="PNG", optimize=False, compress_level=6)
                png_bytes = output.getvalue()
    except (OSError, UnicodeDecodeError, UnidentifiedImageError, ValueError) as exc:
        identity = source_logical_path or source_mime_type or "unknown image source"
        raise ValueError(f"Failed to rasterize contract image from {identity}: {exc}") from exc

    if semantic_description:
        with Image.open(io.BytesIO(png_bytes)) as rendered_image:
            rendered_image.load()
            png_info = PngInfo()
            png_info.add_text("sixgr_visual_semantics", semantic_description, zip=False)
            output = io.BytesIO()
            rendered_image.save(output, format="PNG", pnginfo=png_info, optimize=False, compress_level=6)
            png_bytes = output.getvalue()

    if not png_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("Contract image rasterizer did not produce a PNG signature.")
    try:
        with Image.open(io.BytesIO(png_bytes)) as check:
            check.verify()
            width, height = check.size
    except (OSError, UnidentifiedImageError) as exc:
        raise ValueError(f"Contract image rasterizer produced an invalid PNG: {exc}") from exc
    if width <= 0 or height <= 0:
        raise ValueError(f"Contract image rasterizer produced invalid dimensions {width}x{height}.")
    return png_bytes


def _png_low_information_reason(image_bytes: bytes) -> str:
    """Return the renderer's explicit low-information gate, if present."""

    try:
        with Image.open(io.BytesIO(bytes(image_bytes or b""))) as image:
            image.load()
            semantics = str(image.info.get("sixgr_visual_semantics") or "")
    except (OSError, UnidentifiedImageError):
        return "invalid_png_semantics"
    match = re.search(r"\bvisual_gate=([^\s]+)", semantics, flags=re.IGNORECASE)
    if match:
        return str(match.group(1)).strip().lower()
    if "Unavailable Without Faking".lower() in semantics.lower():
        return "unavailable_without_faking"
    return ""


def _chart_image_from_dataset(chart_name: str, subtitle: str, dataset: dict[str, Any] | None, summary_lines: list[str]) -> bytes:
    if dataset and dataset.get("mode") == "heatmap":
        return _render_heatmap_svg(
            chart_name,
            subtitle,
            [str(value) for value in dataset.get("x_labels", [])],
            [str(value) for value in dataset.get("y_labels", [])],
            dataset.get("matrix", []),
            summary_lines,
            str(dataset.get("x_label") or "x_value"),
            str(dataset.get("y_label") or "y_value"),
        )
    return _render_svg_plot(chart_name, subtitle, dataset, summary_lines)


def _downsample_points(points: list[list[float]], max_points: int = MAX_PREVIEW_ROWS) -> list[list[float]]:
    if len(points) <= max_points:
        return points
    step = max(1, math.ceil(len(points) / max_points))
    sampled = points[::step]
    if sampled and sampled[-1] != points[-1]:
        sampled.append(points[-1])
    return sampled[:max_points]


def _bin_mean_points(pairs: list[tuple[float, float]], max_bins: int = 18) -> list[list[float]]:
    filtered = [(float(x), float(y)) for x, y in pairs if math.isfinite(float(x)) and math.isfinite(float(y))]
    if not filtered:
        return []
    filtered.sort(key=lambda item: item[0])
    unique_x = sorted({round(item[0], 9) for item in filtered})
    if len(unique_x) <= max_bins:
        grouped: dict[float, list[float]] = defaultdict(list)
        for x_val, y_val in filtered:
            grouped[round(x_val, 9)].append(y_val)
        return [[float(x_val), sum(values) / max(len(values), 1)] for x_val, values in sorted(grouped.items())]
    min_x = min(item[0] for item in filtered)
    max_x = max(item[0] for item in filtered)
    if math.isclose(min_x, max_x):
        return [[min_x, sum(item[1] for item in filtered) / len(filtered)]]
    width = (max_x - min_x) / max(max_bins, 1)
    buckets: list[list[float]] = [[] for _ in range(max_bins)]
    for x_val, y_val in filtered:
        idx = min(max_bins - 1, max(0, int((x_val - min_x) / max(width, 1e-12))))
        buckets[idx].append(y_val)
    points: list[list[float]] = []
    for idx, values in enumerate(buckets):
        if not values:
            continue
        center = min_x + width * (idx + 0.5)
        points.append([center, sum(values) / len(values)])
    return points


def _honest_chart_mode(points: list[list[float]], preferred: str = "line", min_line_points: int = 3) -> str:
    """Avoid implying a time/quality trend when only sparse samples exist."""
    if preferred != "line":
        return preferred
    numeric_points = [
        (float(point[0]), float(point[1]))
        for point in points
        if isinstance(point, (list, tuple))
        and len(point) >= 2
        and _coerce_float(point[0]) is not None
        and _coerce_float(point[1]) is not None
    ]
    distinct_x = {round(point[0], 9) for point in numeric_points}
    if len(numeric_points) < min_line_points or len(distinct_x) < min_line_points:
        return "scatter"
    return "line"


def _finite_dataset_points(dataset: dict[str, Any] | None) -> list[tuple[float, float]]:
    if not isinstance(dataset, dict):
        return []
    out: list[tuple[float, float]] = []
    for row in dataset.get("points") or []:
        if not isinstance(row, (list, tuple)) or len(row) < 2:
            continue
        x_val = _coerce_float(row[0])
        y_val = _coerce_float(row[1])
        if x_val is None or y_val is None:
            continue
        out.append((float(x_val), float(y_val)))
    return out


def _unique_numeric_count(values: list[float]) -> int:
    return len({round(float(value), 9) for value in values if math.isfinite(float(value))})


def _dataset_low_information_reason(dataset: dict[str, Any] | None) -> tuple[str, list[str]]:
    points = _finite_dataset_points(dataset)
    if not points:
        return "no_finite_chart_points", ["No finite x/y points were available in the chart source."]
    mode = str((dataset or {}).get("mode") or "line").strip().lower()
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    unique_x = _unique_numeric_count(xs)
    unique_y = _unique_numeric_count(ys)
    stats = [
        f"finite_points={len(points)}",
        f"unique_x={unique_x}",
        f"unique_y={unique_y}",
        f"chart_mode={mode or 'unknown'}",
    ]
    evidence_shape_policy = str(
        (dataset or {}).get("evidence_shape_policy") or ""
    ).strip().lower()
    sample_count = int(
        max(
            0,
            _coerce_float((dataset or {}).get("sample_count"))
            or len(points),
        )
    )
    if evidence_shape_policy:
        stats.extend(
            [
                f"evidence_shape_policy={evidence_shape_policy}",
                f"source_sample_count={sample_count}",
            ]
        )
    # Constant and single-state observations are not inherently low quality.
    # A flat runtime trace proves that a measured state stayed constant; a
    # one-bucket histogram proves that every observed sample occupied the same
    # state; and one spatial coordinate may legitimately be constant for a
    # linear antenna array.  These narrowly scoped policies let the producer
    # state that semantics explicitly.  They do *not* permit a one-point SNR
    # sweep or a one-axis table to masquerade as a curve/2-D heatmap.
    if evidence_shape_policy == "observed_timeline":
        if sample_count >= 2 and len(points) >= 2 and unique_x >= 2:
            return "", stats + [
                "A constant measured state is retained as an observed flat timeline."
            ]
    elif evidence_shape_policy == "observed_distribution":
        if sample_count >= 1 and len(points) >= 1:
            return "", stats + [
                "A one-state measured population is retained as an exact categorical distribution."
            ]
    elif evidence_shape_policy == "observed_geometry":
        if sample_count >= 2 and len(points) >= 2 and (unique_x >= 2 or unique_y >= 2):
            return "", stats + [
                "A constant spatial coordinate is valid for a measured/configured linear array geometry."
            ]
    elif evidence_shape_policy == "measured_scalar":
        if sample_count >= 1 and len(points) == 1:
            return "", stats + [
                "The chart is an explicitly labeled measured scalar, not a trend or fitted curve."
            ]
    elif evidence_shape_policy == "empirical_cdf":
        if sample_count >= 2 and len(points) >= 2:
            return "", stats + [
                "This is the exact empirical CDF of the persisted sample population; no fitted distribution is claimed."
            ]
    elif evidence_shape_policy == "observed_relation":
        if sample_count >= 2 and len(points) >= 2 and unique_x >= 2:
            return "", stats + [
                "Exact paired observations are shown; a constant response is retained and no regression/correlation is inferred."
            ]
    elif evidence_shape_policy == "operating_point":
        if sample_count >= 1 and len(points) >= 1:
            return "", stats + [
                "This is an explicitly labeled bounded operating-point observation, not a sweep curve."
            ]
    if all(math.isclose(y, 0.0, abs_tol=1e-15) for y in ys):
        return "all_zero_metric_values", stats + ["Every plotted metric value is zero."]
    if mode in {"line", "cdf"}:
        if len(points) < MIN_TREND_CHART_POINTS:
            return "insufficient_points_for_trend", stats + ["At least three finite points are required for a trend/CDF curve."]
        if unique_x < MIN_TREND_CHART_POINTS:
            return "insufficient_unique_x_for_trend", stats + ["The x-axis does not contain enough independent values for a trend."]
        if mode == "line" and unique_y < 2:
            return "constant_y_for_trend", stats + ["The y-axis is constant; a line would imply movement that is not present."]
    elif mode in {"scatter", "relation", "vs"}:
        if len(points) < MIN_EXPLANATORY_CHART_POINTS:
            return "insufficient_points_for_relation", stats + ["At least two finite points are required for a relation/scatter chart."]
        if unique_x < 2:
            return "constant_x_for_relation", stats + ["The x-axis is constant; no relationship can be inferred."]
        if unique_y < 2:
            return "constant_y_for_relation", stats + ["The y-axis is constant; no relationship can be inferred."]
    elif mode in {"histogram", "bar"}:
        if len(points) < MIN_EXPLANATORY_CHART_POINTS:
            return "single_bucket_distribution", stats + ["Only one bucket/category exists; render an explanation card instead of a misleading distribution."]
    return "", stats


def _bar_dataset_from_named_values(
    x_label: str,
    y_label: str,
    named_values: list[tuple[str, float]],
) -> tuple[dict[str, Any], list[str]]:
    points = [[float(idx + 1), float(value)] for idx, (_name, value) in enumerate(named_values)]
    summary = [f"bucket_{idx + 1}={name}" for idx, (name, _value) in enumerate(named_values)]
    return {
        "mode": "bar",
        "x_label": x_label,
        "y_label": y_label,
        "points": points,
        "evidence_shape_policy": "observed_distribution",
        "sample_count": len(named_values),
    }, summary


def _format_axis_tick(value: float) -> str:
    value = 0.0 if math.isclose(float(value), 0.0, abs_tol=1e-12) else float(value)
    magnitude = abs(value)
    if magnitude >= 10000 or (magnitude > 0 and magnitude < 0.001):
        return f"{value:.2e}"
    return f"{value:.4g}"


def _ellipsize_svg_text(value: Any, max_chars: int) -> str:
    text = str(value or "")
    limit = max(4, int(max_chars))
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "…"


def _axis_tick_values(minimum: float, maximum: float, count: int = 5) -> list[float]:
    if count <= 1 or math.isclose(minimum, maximum):
        return [float(minimum)]
    span = float(maximum) - float(minimum)
    raw_step = span / max(int(count) - 1, 1)
    exponent = math.floor(math.log10(raw_step))
    scale = 10.0**exponent
    fraction = raw_step / scale
    if fraction <= 1.0:
        nice_fraction = 1.0
    elif fraction <= 2.0:
        nice_fraction = 2.0
    elif fraction <= 2.5:
        nice_fraction = 2.5
    elif fraction <= 5.0:
        nice_fraction = 5.0
    else:
        nice_fraction = 10.0
    step = nice_fraction * scale
    epsilon = max(abs(minimum), abs(maximum), 1.0) * 1e-12
    first = math.ceil((float(minimum) - epsilon) / step) * step
    last = math.floor((float(maximum) + epsilon) / step) * step
    if first > last:
        return [float(minimum), float(maximum)]
    tick_count = int(round((last - first) / step)) + 1
    ticks = [first + idx * step for idx in range(tick_count)]
    if len(ticks) < 2:
        return [float(minimum), float(maximum)]
    return [0.0 if math.isclose(value, 0.0, abs_tol=epsilon) else value for value in ticks]


def _explicit_axis_ticks(values: Iterable[float], maximum_count: int = 8) -> list[float] | None:
    """Use exact sample ticks only when their labels will remain visually distinct."""

    ticks = sorted({float(value) for value in values if math.isfinite(float(value))})
    if not ticks or len(ticks) > max(1, int(maximum_count)):
        return None
    if len(ticks) <= 1:
        return ticks
    span = ticks[-1] - ticks[0]
    if not math.isfinite(span) or span <= 0.0:
        return ticks
    minimum_gap = min(right - left for left, right in zip(ticks, ticks[1:]))
    # Eight full-width engineering labels need roughly one tenth of the axis each.
    # Close DL/UL measured-SINR pairs therefore use rounded engineering ticks.
    if minimum_gap < span / 10.0:
        return None
    return ticks


def _append_y_axis_ticks(
    parts: list[str],
    axis_left: float,
    axis_right: float,
    axis_top: float,
    axis_bottom: float,
    min_y: float,
    max_y: float,
) -> None:
    for value in _axis_tick_values(min_y, max_y):
        y_px = axis_bottom - ((value - min_y) / (max_y - min_y)) * (axis_bottom - axis_top)
        parts.append(f'<line x1="{axis_left}" y1="{y_px:.2f}" x2="{axis_right}" y2="{y_px:.2f}" stroke="#e2e8f0" stroke-width="1"/>')
        parts.append(f'<line x1="{axis_left - 5}" y1="{y_px:.2f}" x2="{axis_left}" y2="{y_px:.2f}" stroke="#64748b"/>')
        parts.append(f'<text x="{axis_left - 9}" y="{y_px + 4:.2f}" text-anchor="end" font-family="Consolas,Segoe UI Mono,monospace" font-size="10" fill="#475569">{html.escape(_format_axis_tick(value))}</text>')


def _append_numeric_axis_ticks(
    parts: list[str],
    axis_left: float,
    axis_right: float,
    axis_top: float,
    axis_bottom: float,
    min_x: float,
    max_x: float,
    min_y: float,
    max_y: float,
    x_tick_values: list[float] | None = None,
) -> None:
    _append_y_axis_ticks(parts, axis_left, axis_right, axis_top, axis_bottom, min_y, max_y)
    requested_ticks = [
        float(value) for value in (x_tick_values or [])
        if math.isfinite(float(value)) and min_x <= float(value) <= max_x
    ]
    ticks = sorted(set(requested_ticks)) if requested_ticks else _axis_tick_values(min_x, max_x)
    for value in ticks:
        x_px = axis_left + ((value - min_x) / (max_x - min_x)) * (axis_right - axis_left)
        parts.append(f'<line x1="{x_px:.2f}" y1="{axis_top}" x2="{x_px:.2f}" y2="{axis_bottom}" stroke="#e2e8f0" stroke-width="1"/>')
        parts.append(f'<line x1="{x_px:.2f}" y1="{axis_bottom}" x2="{x_px:.2f}" y2="{axis_bottom + 5}" stroke="#64748b"/>')
        parts.append(f'<text x="{x_px:.2f}" y="{axis_bottom + 18}" text-anchor="middle" font-family="Consolas,Segoe UI Mono,monospace" font-size="10" fill="#475569">{html.escape(_format_axis_tick(value))}</text>')


def _display_axis_label(value: Any) -> str:
    """Convert persisted schema names into publication-facing axis labels."""

    raw = str(value or "").strip()
    normalized = re.sub(r"[^a-z0-9]+", "", raw.lower())
    labels = {
        "appliedawgnsnrdb": "Applied AWGN SNR (dB)",
        "appliedsnrdb": "Applied SNR (dB)",
        "configuredsnrdb": "Configured SNR (dB)",
        "snrdb": "SNR (dB)",
        "posteqsinrdb": "Post-equalization SINR (dB)",
        "measuredtrialsinrdb": "Measured trial SINR (dB)",
        "measuredsinrdb": "Measured SINR (dB)",
        "measuredposteqsinrdb": "Measured post-equalization SINR (dB)",
        "meanmeasuredsinrdb": "Mean measured post-equalization SINR (dB)",
        "measuredwidebandsinrdb": "Measured wideband SINR (dB)",
        "throughputmbps": "Throughput (Mbit/s)",
        "goodputmbps": "Goodput (Mbit/s)",
        "spectralefficiencybpshz": "Spectral efficiency (bit/s/Hz)",
        "allocatedprbcount": "Allocated PRBs",
        "harqretxcount": "HARQ retransmissions",
        "bler": "Block error rate (BLER)",
        "ber": "Bit error rate (BER)",
        "fer": "Frame error rate (FER)",
    }
    if normalized in labels:
        return labels[normalized]
    cleaned = raw.replace("_dB", " (dB)").replace("_Mbps", " (Mbit/s)")
    cleaned = cleaned.replace("_", " ").strip()
    return cleaned or "Value"


def _display_chart_title(value: Any) -> str:
    raw = str(value or "Chart").strip()
    if "_" not in raw and raw != raw.lower() and raw[:1].isupper():
        return raw
    words = raw.replace("_", " ").split()
    acronyms = {"dl", "ul", "snr", "sinr", "awgn", "bler", "ber", "fer", "mcs", "harq", "pdcch", "pdsch", "pucch", "pusch", "prach", "csi", "srs", "ssb", "pbch", "evm"}
    rendered = [
        word.upper() if word.lower() in acronyms
        else ("vs" if word.lower() == "vs" else word.capitalize())
        for word in words
    ]
    return " ".join(rendered) or "Chart"


def _dataset_evidence_summary(
    dataset: dict[str, Any] | None,
    points: list[list[float]],
) -> list[str]:
    if not isinstance(dataset, dict) or not points:
        return []
    xs = [float(point[0]) for point in points]
    ys = [float(point[1]) for point in points]
    lines = [
        f"Plotted points: {len(points)}",
        f"X range: {_format_axis_tick(min(xs))} to {_format_axis_tick(max(xs))}",
        f"Y range: {_format_axis_tick(min(ys))} to {_format_axis_tick(max(ys))}",
    ]
    sample_count = _coerce_float(dataset.get("sample_count"))
    if sample_count is not None:
        lines.append(f"Runtime samples: {int(max(0, sample_count))}")
    policy = str(dataset.get("evidence_shape_policy") or "").strip()
    if policy:
        lines.append(f"Evidence shape: {policy.replace('_', ' ')}")
    return lines


def _render_multi_series_svg(
    title: str,
    subtitle: str,
    series: list[dict[str, Any]],
    summary_lines: list[str],
    *,
    x_label: str,
    y_label: str,
    mode: str = "line",
    target_line: float | None = None,
    evidence_shape_policy: str = "",
) -> bytes:
    width = 1280
    height = 720
    left = 72
    top = 108
    plot_w = 820
    plot_h = 458
    info_x = 930
    legend_limit = len(series) if evidence_shape_policy == "operating_point" else 8
    info_h = max(plot_h, 100 + 22 * (min(len(summary_lines) + 6, 14) + legend_limit))
    height = max(height, top + info_h + 64)
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#f8fafc"/>',
        f'<rect x="0" y="0" width="10" height="{height}" fill="#0f766e"/>',
        '<rect x="40" y="24" width="190" height="24" rx="12" fill="#ccfbf1"/>',
        '<text x="135" y="41" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="11" font-weight="700" letter-spacing="1.2" fill="#115e59">RUNTIME MEASUREMENT</text>',
        f'<text x="40" y="76" font-family="Segoe UI,Arial,sans-serif" font-size="29" font-weight="700" fill="#0f172a">{html.escape(_display_chart_title(title))}</text>',
        f'<text x="40" y="99" font-family="Segoe UI,Arial,sans-serif" font-size="14" fill="#475569">{html.escape(_ellipsize_svg_text(subtitle, 132))}</text>',
        f'<rect x="{left}" y="{top}" width="{plot_w}" height="{plot_h}" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>',
        f'<rect x="{info_x}" y="{top}" width="310" height="{info_h}" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>',
    ]
    prepared: list[dict[str, Any]] = []
    palette = ["#0f766e", "#2563eb", "#dc2626", "#7c3aed", "#d97706", "#0891b2",
               "#4d7c0f", "#db2777", "#78350f", "#334155", "#4338ca", "#be185d",
               "#15803d", "#a16207", "#075985", "#a21caf"]
    all_points: list[tuple[float, float]] = []
    for idx, item in enumerate(series):
        raw_points = [
            (float(point[0]), float(point[1]))
            for point in (item.get("points") or [])
            if isinstance(point, (list, tuple))
            and len(point) >= 2
            and _coerce_float(point[0]) is not None
            and _coerce_float(point[1]) is not None
        ]
        if not raw_points:
            continue
        sampled = _downsample_points([[x_val, y_val] for x_val, y_val in raw_points], MAX_PREVIEW_ROWS)
        sampled_pairs = [(float(point[0]), float(point[1])) for point in sampled]
        prepared.append(
            {
                "name": str(item.get("name") or f"Series {idx + 1}"),
                "color": str(item.get("color") or palette[idx % len(palette)]),
                "dasharray": str(item.get("dasharray") or ("" if idx == 0 else "8 5")),
                "marker": str(item.get("marker") or ("circle" if idx == 0 else "square")),
                "points": sampled_pairs,
                "error_bars": [
                    [float(bar[0]), float(bar[1]), float(bar[2])]
                    for bar in (item.get("error_bars") or [])
                    if isinstance(bar, (list, tuple))
                    and len(bar) >= 3
                    and all(_coerce_float(value) is not None for value in bar[:3])
                ],
            }
        )
        all_points.extend(sampled_pairs)
    if not prepared or not all_points:
        return _render_reason_svg(title, subtitle, summary_lines + ["No numeric multi-series rows were available for this chart."])
    low_info_reason, low_info_lines = _dataset_low_information_reason(
        {"mode": mode, "points": [[x_val, y_val] for x_val, y_val in all_points],
         "evidence_shape_policy": evidence_shape_policy}
    )
    if low_info_reason:
        return _render_reason_svg(
            title,
            "Exact runtime source rows exist, but this visual would not support a defensible trend conclusion.",
            summary_lines + [f"visual_gate={low_info_reason}"] + low_info_lines,
        )
    xs = [point[0] for point in all_points]
    ys = [point[1] for point in all_points]
    min_x = min(xs)
    max_x = max(xs)
    min_y = min(ys)
    max_y = max(ys)
    if math.isclose(min_x, max_x):
        max_x = min_x + 1.0
    if math.isclose(min_y, max_y):
        max_y = min_y + 1.0
    axis_left = left + 54
    axis_bottom = top + plot_h - 42
    axis_top = top + 26
    axis_right = left + plot_w - 24
    _append_numeric_axis_ticks(
        parts,
        axis_left,
        axis_right,
        axis_top,
        axis_bottom,
        min_x,
        max_x,
        min_y,
        max_y,
        _explicit_axis_ticks(xs),
    )
    parts.append(f'<line x1="{axis_left}" y1="{axis_bottom}" x2="{axis_right}" y2="{axis_bottom}" stroke="#94a3b8" stroke-width="1.2"/>')
    parts.append(f'<line x1="{axis_left}" y1="{axis_top}" x2="{axis_left}" y2="{axis_bottom}" stroke="#94a3b8" stroke-width="1.2"/>')
    for prepared_series in prepared:
        coords: list[tuple[float, float]] = []
        for x_val, y_val in prepared_series["points"]:
            x_px = axis_left + ((x_val - min_x) / (max_x - min_x)) * (axis_right - axis_left)
            y_px = axis_bottom - ((y_val - min_y) / (max_y - min_y)) * (axis_bottom - axis_top)
            coords.append((x_px, y_px))
        if mode == "scatter":
            for x_px, y_px in coords:
                if prepared_series["marker"] == "square":
                    parts.append(f'<rect x="{x_px - 3:.2f}" y="{y_px - 3:.2f}" width="6" height="6" fill="none" stroke="{prepared_series["color"]}" stroke-width="1.4"/>')
                else:
                    parts.append(f'<circle cx="{x_px:.2f}" cy="{y_px:.2f}" r="2.6" fill="{prepared_series["color"]}" fill-opacity="0.7" />')
        else:
            poly = " ".join(f"{x:.1f},{y:.1f}" for x, y in coords)
            dash_attr = (
                f' stroke-dasharray="{html.escape(prepared_series["dasharray"])}"'
                if prepared_series["dasharray"]
                else ""
            )
            parts.append(
                f'<polyline fill="none" stroke="{prepared_series["color"]}" stroke-width="2.2"{dash_attr} points="{poly}"/>'
            )
            for x_px, y_px in coords[:: max(1, len(coords) // 16)]:
                if prepared_series["marker"] == "square":
                    parts.append(
                        f'<rect x="{x_px - 3.2:.2f}" y="{y_px - 3.2:.2f}" width="6.4" height="6.4" fill="#ffffff" stroke="{prepared_series["color"]}" stroke-width="2" />'
                    )
                else:
                    parts.append(f'<circle cx="{x_px:.2f}" cy="{y_px:.2f}" r="2.8" fill="#ffffff" stroke="{prepared_series["color"]}" stroke-width="2" />')
        for x_val, low_val, high_val in prepared_series["error_bars"]:
            if not (min_x <= x_val <= max_x):
                continue
            x_px = axis_left + ((x_val - min_x) / (max_x - min_x)) * (axis_right - axis_left)
            low_px = axis_bottom - ((low_val - min_y) / (max_y - min_y)) * (axis_bottom - axis_top)
            high_px = axis_bottom - ((high_val - min_y) / (max_y - min_y)) * (axis_bottom - axis_top)
            low_px = min(axis_bottom, max(axis_top, low_px))
            high_px = min(axis_bottom, max(axis_top, high_px))
            color = prepared_series["color"]
            parts.append(f'<line x1="{x_px:.1f}" y1="{high_px:.1f}" x2="{x_px:.1f}" y2="{low_px:.1f}" stroke="{color}" stroke-width="1.4" opacity="0.75"/>')
            parts.append(f'<line x1="{x_px - 4:.1f}" y1="{high_px:.1f}" x2="{x_px + 4:.1f}" y2="{high_px:.1f}" stroke="{color}" stroke-width="1.4"/>')
            parts.append(f'<line x1="{x_px - 4:.1f}" y1="{low_px:.1f}" x2="{x_px + 4:.1f}" y2="{low_px:.1f}" stroke="{color}" stroke-width="1.4"/>')
    target_value = _coerce_float(target_line)
    if target_value is not None and min_y <= target_value <= max_y:
        target_y = axis_bottom - ((target_value - min_y) / (max_y - min_y)) * (axis_bottom - axis_top)
        parts.append(f'<line x1="{axis_left}" y1="{target_y:.1f}" x2="{axis_right}" y2="{target_y:.1f}" stroke="#dc2626" stroke-width="1.5" stroke-dasharray="7 6"/>')
        parts.append(f'<text x="{axis_right - 4}" y="{target_y - 6:.1f}" text-anchor="end" font-family="Segoe UI,Arial,sans-serif" font-size="11" fill="#b91c1c">Target {_format_axis_tick(target_value)}</text>')
    parts.append(
        f'<text x="{left + plot_w / 2:.1f}" y="{top + plot_h + 26}" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="14" font-weight="600" fill="#334155">{html.escape(_display_axis_label(x_label))}</text>'
    )
    parts.append(
        f'<text x="{left + 13}" y="{top + plot_h / 2:.1f}" text-anchor="middle" transform="rotate(-90 {left + 13} {top + plot_h / 2:.1f})" font-family="Segoe UI,Arial,sans-serif" font-size="14" font-weight="600" fill="#334155">{html.escape(_display_axis_label(y_label))}</text>'
    )
    parts.append(f'<text x="{info_x + 18}" y="{top + 30}" font-family="Segoe UI,Arial,sans-serif" font-size="18" font-weight="700" fill="#0f172a">Evidence Summary</text>')
    y_cursor = top + 58
    evidence_lines = list(summary_lines) + _dataset_evidence_summary(
        {"evidence_shape_policy": evidence_shape_policy or "observed_relation"},
        [[point[0], point[1]] for point in all_points],
    )
    for line in evidence_lines[:14]:
        parts.append(f'<text x="{info_x + 18}" y="{y_cursor}" font-family="Segoe UI,Arial,sans-serif" font-size="12.5" fill="#334155">{html.escape(_ellipsize_svg_text(line, 42))}</text>')
        y_cursor += 22
    y_cursor += 12
    for prepared_series in prepared[:legend_limit]:
        dash_attr = (
            f' stroke-dasharray="{html.escape(prepared_series["dasharray"])}"'
            if prepared_series["dasharray"]
            else ""
        )
        if mode == "scatter":
            if prepared_series["marker"] == "square":
                parts.append(f'<rect x="{info_x + 23}" y="{y_cursor - 4}" width="8" height="8" fill="none" stroke="{prepared_series["color"]}" stroke-width="1.4"/>')
            else:
                parts.append(f'<circle cx="{info_x + 27}" cy="{y_cursor}" r="3" fill="{prepared_series["color"]}"/>')
        else:
            parts.append(f'<line x1="{info_x + 18}" y1="{y_cursor}" x2="{info_x + 36}" y2="{y_cursor}" stroke="{prepared_series["color"]}" stroke-width="3"{dash_attr}/>')
        parts.append(f'<text x="{info_x + 46}" y="{y_cursor + 4}" font-family="Segoe UI,Arial,sans-serif" font-size="13" fill="#334155">{html.escape(_ellipsize_svg_text(prepared_series["name"], 28))}</text>')
        y_cursor += 22
    parts.append('</svg>')
    return "".join(parts).encode("utf-8")


def _render_svg_plot(title: str, subtitle: str, dataset: dict[str, Any] | None, summary_lines: list[str]) -> bytes:
    width = 1280
    height = 720
    left = 72
    top = 108
    plot_w = 820
    plot_h = 458
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#f8fafc"/>',
        '<rect x="0" y="0" width="10" height="720" fill="#0f766e"/>',
        '<rect x="40" y="24" width="190" height="24" rx="12" fill="#ccfbf1"/>',
        '<text x="135" y="41" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="11" font-weight="700" letter-spacing="1.2" fill="#115e59">RUNTIME MEASUREMENT</text>',
        f'<text x="40" y="76" font-family="Segoe UI,Arial,sans-serif" font-size="29" font-weight="700" fill="#0f172a">{html.escape(_display_chart_title(title))}</text>',
        f'<text x="40" y="99" font-family="Segoe UI,Arial,sans-serif" font-size="14" fill="#475569">{html.escape(_ellipsize_svg_text(subtitle, 132))}</text>',
        f'<rect x="{left}" y="{top}" width="{plot_w}" height="{plot_h}" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>',
    ]
    if dataset and dataset.get("points"):
        low_info_reason, low_info_lines = _dataset_low_information_reason(dataset)
        if low_info_reason:
            return _render_reason_svg(
                title,
                "Exact runtime source rows exist, but this visual would not support a defensible chart conclusion.",
                summary_lines + [f"visual_gate={low_info_reason}"] + low_info_lines,
            )
        points = [[float(row[0]), float(row[1])] for row in dataset.get("points", []) if len(row) >= 2]
        xs = [row[0] for row in points]
        ys = [row[1] for row in points]
        min_x = min(xs)
        max_x = max(xs)
        min_y = min(ys)
        max_y = max(ys)
        requested_y_min = dataset.get("y_axis_min")
        requested_y_max = dataset.get("y_axis_max")
        if requested_y_min is not None and requested_y_max is not None:
            requested_y_min = float(requested_y_min)
            requested_y_max = float(requested_y_max)
            if (
                math.isfinite(requested_y_min)
                and math.isfinite(requested_y_max)
                and requested_y_min < requested_y_max
                and min_y >= requested_y_min
                and max_y <= requested_y_max
            ):
                min_y = requested_y_min
                max_y = requested_y_max
        if math.isclose(min_x, max_x):
            max_x = min_x + 1.0
        if math.isclose(min_y, max_y):
            constant_value = float(min_y)
            y_semantics = str(dataset.get("y_label") or "").strip().lower()
            bounded_unit_metric = any(
                token in y_semantics
                for token in ("rate", "bler", "ber", "fer", "probability", "flag", "hit")
            )
            discrete_index_metric = any(
                token in y_semantics
                for token in ("beam", "rank", "layer", "pmi", "cri", "index")
            )
            if bounded_unit_metric and 0.0 <= constant_value <= 1.0:
                min_y, max_y = 0.0, 1.0
            elif discrete_index_metric:
                min_y = max(0.0, constant_value - 1.0)
                max_y = constant_value + 1.0
            else:
                padding = max(abs(constant_value) * 0.1, 1.0)
                min_y = constant_value - padding
                max_y = constant_value + padding
        is_bar = dataset.get("mode") == "bar"
        if is_bar:
            if min_y > 0:
                min_y = 0.0
            if math.isclose(min_y, max_y):
                max_y = min_y + max(abs(min_y) * 0.1, 1.0)
        axis_left = left + 45
        axis_right = left + plot_w - 24
        axis_top = top + 24
        axis_bottom = top + plot_h - 38
        if not is_bar:
            _append_numeric_axis_ticks(
                parts,
                axis_left,
                axis_right,
                axis_top,
                axis_bottom,
                min_x,
                max_x,
                min_y,
                max_y,
                _explicit_axis_ticks(xs),
            )
        else:
            _append_y_axis_ticks(parts, axis_left, axis_right, axis_top, axis_bottom, min_y, max_y)
        parts.append(f'<line x1="{axis_left}" y1="{axis_bottom}" x2="{axis_right}" y2="{axis_bottom}" stroke="#94a3b8" stroke-width="1.2"/>')
        parts.append(f'<line x1="{axis_left}" y1="{axis_top}" x2="{axis_left}" y2="{axis_bottom}" stroke="#94a3b8" stroke-width="1.2"/>')
        if is_bar:
            bar_w = max(8.0, (plot_w - 100) / max(len(points), 1) * 0.7)
            for idx, (x_val, y_val) in enumerate(points):
                x_px = left + 55 + idx * max(bar_w + 4, (plot_w - 100) / max(len(points), 1))
                y_px = axis_bottom - ((y_val - min_y) / (max_y - min_y)) * (axis_bottom - axis_top)
                parts.append(f'<rect x="{x_px:.1f}" y="{y_px:.1f}" width="{bar_w:.1f}" height="{(axis_bottom - y_px):.1f}" fill="#0f766e" opacity="0.88"/>')
                tick_labels = dataset.get("tick_labels") or []
                label = str(tick_labels[idx])[:14] if idx < len(tick_labels) else _format_axis_tick(x_val)
                parts.append(f'<line x1="{x_px + bar_w/2:.1f}" y1="{axis_bottom}" x2="{x_px + bar_w/2:.1f}" y2="{axis_bottom + 5}" stroke="#64748b"/>')
                parts.append(f'<text x="{x_px + bar_w/2:.1f}" y="{axis_bottom + 18}" text-anchor="middle" font-family="Consolas,Segoe UI Mono,monospace" font-size="10" fill="#475569">{html.escape(label)}</text>')
        elif dataset.get("mode") == "scatter":
            for x_val, y_val in points:
                x_px = left + 45 + ((x_val - min_x) / (max_x - min_x)) * (plot_w - 70)
                y_px = top + plot_h - 38 - ((y_val - min_y) / (max_y - min_y)) * (plot_h - 62)
                parts.append(f'<circle cx="{x_px:.1f}" cy="{y_px:.1f}" r="3.0" fill="#0f766e" fill-opacity="0.72"/>')
        else:
            coords = []
            for x_val, y_val in points:
                x_px = left + 45 + ((x_val - min_x) / (max_x - min_x)) * (plot_w - 70)
                y_px = top + plot_h - 38 - ((y_val - min_y) / (max_y - min_y)) * (plot_h - 62)
                coords.append((x_px, y_px))
            poly = " ".join(f"{x:.1f},{y:.1f}" for x, y in coords)
            parts.append(f'<polyline fill="none" stroke="#0f766e" stroke-width="3" points="{poly}"/>')
            for x_px, y_px in coords[:: max(1, len(coords) // 24)]:
                parts.append(f'<circle cx="{x_px:.1f}" cy="{y_px:.1f}" r="3.5" fill="#0f766e"/>')
        for error_bar in dataset.get("error_bars", []) or []:
            if not isinstance(error_bar, (list, tuple)) or len(error_bar) < 3:
                continue
            x_val = _coerce_float(error_bar[0])
            low_val = _coerce_float(error_bar[1])
            high_val = _coerce_float(error_bar[2])
            if x_val is None or low_val is None or high_val is None:
                continue
            x_px = axis_left + ((float(x_val) - min_x) / (max_x - min_x)) * (axis_right - axis_left)
            low_px = axis_bottom - ((float(low_val) - min_y) / (max_y - min_y)) * (axis_bottom - axis_top)
            high_px = axis_bottom - ((float(high_val) - min_y) / (max_y - min_y)) * (axis_bottom - axis_top)
            low_px = min(axis_bottom, max(axis_top, low_px))
            high_px = min(axis_bottom, max(axis_top, high_px))
            parts.append(f'<line x1="{x_px:.1f}" y1="{high_px:.1f}" x2="{x_px:.1f}" y2="{low_px:.1f}" stroke="#0f766e" stroke-width="1.6" opacity="0.8"/>')
            parts.append(f'<line x1="{x_px - 5:.1f}" y1="{high_px:.1f}" x2="{x_px + 5:.1f}" y2="{high_px:.1f}" stroke="#0f766e" stroke-width="1.6"/>')
            parts.append(f'<line x1="{x_px - 5:.1f}" y1="{low_px:.1f}" x2="{x_px + 5:.1f}" y2="{low_px:.1f}" stroke="#0f766e" stroke-width="1.6"/>')
        target_line = _coerce_float(dataset.get("target_line"))
        if target_line is not None and min_y <= target_line <= max_y:
            target_y = axis_bottom - ((target_line - min_y) / (max_y - min_y)) * (axis_bottom - axis_top)
            parts.append(f'<line x1="{axis_left}" y1="{target_y:.1f}" x2="{axis_right}" y2="{target_y:.1f}" stroke="#dc2626" stroke-width="1.5" stroke-dasharray="7 6"/>')
            parts.append(f'<text x="{axis_right - 4}" y="{target_y - 6:.1f}" text-anchor="end" font-family="Segoe UI,Arial,sans-serif" font-size="11" fill="#b91c1c">Target {_format_axis_tick(target_line)}</text>')
        parts.append(f'<text x="{left + plot_w / 2:.1f}" y="{top + plot_h + 26}" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="14" font-weight="600" fill="#334155">{html.escape(_display_axis_label(dataset.get("x_label") or "X"))}</text>')
        parts.append(f'<text x="{left + 13}" y="{top + plot_h / 2:.1f}" text-anchor="middle" transform="rotate(-90 {left + 13} {top + plot_h / 2:.1f})" font-family="Segoe UI,Arial,sans-serif" font-size="14" font-weight="600" fill="#334155">{html.escape(_display_axis_label(dataset.get("y_label") or "Y"))}</text>')
    else:
        parts.append(f'<text x="{left + 45}" y="{top + 50}" font-family="Segoe UI,Arial,sans-serif" font-size="18" fill="#334155">No numeric series could be derived for this chart family.</text>')
    info_x = 930
    parts.append(f'<rect x="{info_x}" y="{top}" width="310" height="{plot_h}" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>')
    parts.append(f'<text x="{info_x + 18}" y="{top + 32}" font-family="Segoe UI,Arial,sans-serif" font-size="18" font-weight="700" fill="#0f172a">Evidence Summary</text>')
    y = top + 60
    points_for_summary = points if dataset and dataset.get("points") else []
    combined_summary = list(summary_lines) + _dataset_evidence_summary(dataset, points_for_summary)
    for line in combined_summary[:17]:
        parts.append(f'<text x="{info_x + 18}" y="{y}" font-family="Segoe UI,Arial,sans-serif" font-size="12.5" fill="#334155">{html.escape(_ellipsize_svg_text(line, 42))}</text>')
        y += 22
    extra_lines = dataset.get("summary_lines", []) if isinstance(dataset, dict) else []
    for line in extra_lines[: max(0, 17 - len(combined_summary))]:
        parts.append(f'<text x="{info_x + 18}" y="{y}" font-family="Segoe UI,Arial,sans-serif" font-size="12.5" fill="#334155">{html.escape(_ellipsize_svg_text(line, 42))}</text>')
        y += 22
    parts.append('</svg>')
    return "".join(parts).encode("utf-8")


def _chart_dataset_csv(
    run_id: int,
    chart_name: str,
    dataset: dict[str, Any] | None,
    source_table_path: str,
    source_row_count: int,
    materialization_status: str,
    note: str,
    source_mapping_status: str | None = None,
) -> bytes:
    mapping_status = str(source_mapping_status or _source_mapping_status_for_status(materialization_status)).strip().lower()
    if mapping_status not in {"exact", "unavailable", "invalid"}:
        mapping_status = "unavailable"
    header = [
        "run_id",
        "chart_name",
        "chart_mode",
        "x_label",
        "y_label",
        "point_index",
        "x_value",
        "y_value",
        "z_label",
        "z_value",
        "source_table_logical_path",
        "source_row_count",
        "materialization_status",
        "lineage_note",
        "source_mapping_status",
        "evidence_shape_policy",
        "source_sample_count",
    ]
    rows: list[list[Any]] = []
    if dataset and dataset.get("points"):
        for idx, point in enumerate(dataset.get("points", []), start=1):
            x_val = point[0] if len(point) > 0 else ""
            y_val = point[1] if len(point) > 1 else ""
            z_val = point[2] if len(point) > 2 else ""
            rows.append(
                [
                    run_id,
                    chart_name,
                    str(dataset.get("mode") or ""),
                    str(dataset.get("x_label") or ""),
                    str(dataset.get("y_label") or ""),
                    idx,
                    x_val,
                    y_val,
                    str(dataset.get("z_label") or ""),
                    z_val,
                    source_table_path,
                    source_row_count,
                    materialization_status,
                    note,
                    mapping_status,
                    str(dataset.get("evidence_shape_policy") or ""),
                    int(max(0, _coerce_float(dataset.get("sample_count")) or source_row_count)),
                ]
            )
    else:
        rows.append(
            [
                run_id,
                chart_name,
                str(dataset.get("mode") or "unavailable_reason_summary") if isinstance(dataset, dict) else "unavailable_reason_summary",
                str(dataset.get("x_label") or "not_available") if isinstance(dataset, dict) else "not_available",
                str(dataset.get("y_label") or "not_available") if isinstance(dataset, dict) else "not_available",
                0,
                "not_available",
                "not_available",
                str(dataset.get("z_label") or "not_available") if isinstance(dataset, dict) else "not_available",
                "not_available",
                source_table_path or "not_published_by_runtime",
                source_row_count,
                materialization_status,
                note,
                mapping_status,
                str(dataset.get("evidence_shape_policy") or "") if isinstance(dataset, dict) else "",
                int(max(0, _coerce_float(dataset.get("sample_count")) or source_row_count)) if isinstance(dataset, dict) else int(max(0, source_row_count)),
            ]
        )
    return _encode_csv(header, rows)


def _decode_csv_dicts(data: bytes) -> tuple[list[str], list[dict[str, str]]]:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        text = data.decode("utf-8", "ignore")
    with _csv_field_limit_for_payload(data):
        reader = csv.DictReader(io.StringIO(text))
        rows = [{str(k): str(v) for k, v in row.items()} for row in reader]
        return list(reader.fieldnames or []), rows


@contextmanager
def _csv_field_limit_for_payload(data: bytes):
    """Temporarily admit legitimate long scalar fields in one loaded CSV.

    Receiver truth tables can contain quoted LDPC/vector fields larger than
    Python's 128-KiB implementation default.  The payload is already bounded
    by the artifact file read, so its byte length is a safe per-decode upper
    bound.  Restore the process-wide parser setting after either decoder.
    """
    prior_limit = csv.field_size_limit()
    required_limit = max(prior_limit, len(data) + 1)
    if required_limit != prior_limit:
        csv.field_size_limit(required_limit)
    try:
        yield
    finally:
        if required_limit != prior_limit:
            csv.field_size_limit(prior_limit)


def _scope_token_for_logical_path(logical_path: str) -> str:
    token = str(logical_path or "").strip().lower()
    mapping = {
        "air_interface/csv/pdcch_trials.csv": "pdcch",
        "air_interface/csv/pbch_trials.csv": "pbch",
        "air_interface/csv/prach_trials.csv": "prach",
        "air_interface/csv/pucch_trials.csv": "pucch",
        "air_interface/csv/srs_trials.csv": "srs",
        "air_interface/csv/trs_trials.csv": "trs",
        "air_interface/csv/dl_pdsch_trials.csv": "dl_pdsch_trials",
        "air_interface/csv/ul_pusch_trials.csv": "ul_pusch_trials",
        "reports/csv/live_modulation_demodulation_trace.csv": "modulation_demodulation",
        "reports/csv/live_channel_estimation_tti.csv": "channel_estimation",
        "reports/csv/live_channel_state_tti.csv": "channel_state",
        "reports/csv/live_tx_rx_stage_trace.csv": "tx_rx_stage_trace",
    }
    if token in mapping:
        return mapping[token]
    basename = Path(token).name
    generic_patterns = [
        (r"pdcch", "pdcch"),
        (r"(pbch|ssb|sync_signal)", "pbch"),
        (r"prach", "prach"),
        (r"pucch", "pucch"),
        (r"csi[_-]?rs|csirs", "csirs"),
        (r"\bsrs\b", "srs"),
        (r"\btrs\b|receiver_tracking", "trs"),
        (r"pdsch|dl_scheduler|scheduler_cycle|queue|buffer|hol_delay|mac_ce|bsr|qos", "dl_pdsch_trials"),
        (r"pusch|ul_scheduler|llr|decoder", "ul_pusch_trials"),
        (r"rf_|power_|energy_|sleep_state|bb_power", "rf_runtime"),
        (r"beam|precoder|mimo", "beam_runtime"),
        (r"channel|interference|measurement|link_adaptation", "channel_runtime"),
    ]
    for pattern, scope in generic_patterns:
        if re.search(pattern, basename):
            return scope
    if basename:
        cleaned = re.sub(r"[^a-z0-9]+", "_", basename.replace(".csv", "")).strip("_")
        if cleaned:
            return cleaned
    return "runtime"


def _nonblank_text(value: Any) -> bool:
    text = str(value or "").strip()
    return text not in {"", "NaN", "nan", "<missing>", "missing"}


def _semantic_companion_mask(rows: list[dict[str, str]], field_name: str) -> list[bool]:
    base = re.sub(r"(source|valuerole|valuestatus|nareason|definition)$", "", field_name.lower())
    if not base:
        return [False] * len(rows)
    masks: list[bool] = []
    for row in rows:
        present = False
        for candidate, raw_value in row.items():
            cand = str(candidate or "").lower()
            if cand == field_name.lower():
                continue
            if cand != base and not cand.startswith(base):
                continue
            if re.search(r"(source|valuerole|valuestatus|nareason|definition)$", cand):
                continue
            if _nonblank_text(raw_value):
                present = True
                break
        masks.append(present)
    return masks


def _semantic_fill_value(field_name: str, scope_token: str, companion_present: bool) -> str:
    field = field_name.lower()
    scope = scope_token or "runtime"
    direct_string_fields = {
        "mcs",
        "fixedmcsindex",
        "prbs",
        "layers",
        "targetcoderate",
        "tbsize_bits",
        "tbsizebits",
        "decoderiterations",
        "evm_rms",
        "nmse_db",
        "measuredsinr_db",
        "receiverhestsinr_db",
        "decodertruthproxysinr_db",
        "widebandcqi",
        "cqiderivedmcs",
        "cqiderivedtargetcoderate",
        "rankindicator",
        "pmi",
        "cri",
        "meancri",
        "csipayloadbitlength",
        "precodingnumports",
        "precodingnumlayers",
        "precodingmatrixrows",
        "precodingmatrixcols",
        "falsealarmflag",
        "blockingflag",
        "blinddecodecount",
        "availableccecount",
        "usedccecount",
        "nonoverlappedcceusage",
        "aggregationlevel",
        "dcisize_bits",
        "dcisizebits",
        "controlcapacitybits",
        "controlcapacityutilization",
        "coresetutilization",
        "controllatency_ms",
        "configuredcri",
        "proceduredelay_ms",
        "airinterfaceobservation_ms",
        "latency_ms",
        "estimatedcfo_precorrection_hz",
        "residualcfo_postcorrection_hz",
        "estimatedcfo_hz",
        "cfoerror_hz",
        "acquisitiontime_ms",
        "trackingfailureprobability",
        "airinterfacetti_ms",
        "modulation",
        "cqiderivedmodulation",
        "linkadaptationmode",
        "configuredlinkadaptationmode",
        "actualmcsselectionmode",
        "configuredmcsselectionpolicy",
        "schedulergrantmcsselectionmode",
        "requestedoperatingpointsource",
        "cqitable",
        "mcstable",
        "pmitype",
        "pmicodebookmode",
        "csireportmode",
        "csipayloadhex",
        "configuredbeamselectionstrategy",
        "precodersource",
        "precodingmode",
        "precodingapplicationstage",
        "appliedbeamindexset",
        "appliedprecoderpmitype",
        "appliedprecodercodebookmode",
        "requestedvsappliedprecoderpmimatchstatus",
        "iqimbalancemodel",
        "iqimbalancemeasurementsource",
        "iqimbalancemeasurementstatus",
        "trackingestimatesource",
        "measuredtrialsinrsource",
        "largescalesinrsource",
        "servingrsrpsource",
        "csi_rsrpsource",
        "appliedlargescalegainsource",
        "interferencemode",
        "interfererprecodersourceset",
        "interfererprecodingmodeset",
        "interfererbeamindexsetsummary",
        "mcsauthority",
        "modulationauthority",
        "grantoperatingpointsource",
        "appliedoperatingpointsource",
        "trsreceiverintegrationstatus",
        "trsreceiverintegrationblocker",
        "trsstatesource",
        "trsruntimeconsumer",
        "trsupdateoutcome",
        "trsruntimeevidencesource",
        "trsvaliditystate",
        "trsreceiverconsumertype",
        "trstrackingstatebefore",
        "trstrackingstateafter",
        "trschanneltrackingfreshnessstate",
        "trsfrequencytrackingstate",
        "trstimingtrackingstate",
        "cfoestimateavailability",
        "grantcontextid",
        "grantsharedstatecommitmode",
        "interferencepowersource",
        "nareason",
        "unavailablereason",
    }
    if field.endswith("source"):
        return f"active_{scope}_runtime_table" if companion_present else f"not_emitted_by_active_{scope}_runtime"
    if field.endswith("valuerole"):
        return "runtime_observation" if companion_present else "not_available"
    if field.endswith("valuestatus"):
        return "available" if companion_present else f"not_emitted_by_active_{scope}_runtime"
    if field.endswith("nareason") or field == "nareason" or field == "unavailablereason":
        return "not_required_when_metric_present" if companion_present else f"field_not_emitted_by_active_{scope}_runtime"
    if field.endswith("definition"):
        return f"derived_from_active_{scope}_runtime_table" if companion_present else f"not_emitted_by_active_{scope}_runtime"
    if "blocker" in field:
        return f"not_blocked_in_active_{scope}_runtime"
    if "limitation" in field:
        return f"no_additional_{scope}_limitation_recorded"
    if (
        field in direct_string_fields
        or "beam" in field
        or "precoder" in field
        or "interferer" in field
        or "antenna" in field
        or "channelarray" in field
        or "geometryadapter" in field
        or "authority" in field
        or "interference" in field
    ):
        return f"not_recorded_by_active_{scope}_runtime"
    return ""


def _fill_numeric_text_companions(dict_rows: list[dict[str, str]], header: list[str]) -> None:
    header_lookup = {str(col).lower(): str(col) for col in header}
    companion_pairs = [
        ("value", "textvalue"),
        ("valuenumeric", "valuetext"),
        ("metric_value", "metric_text"),
    ]
    for numeric_key, text_key in companion_pairs:
        numeric_col = header_lookup.get(numeric_key)
        text_col = header_lookup.get(text_key)
        if not numeric_col or not text_col:
            continue
        for row in dict_rows:
            text_value = str(row.get(text_col, "") or "").strip()
            numeric_value = str(row.get(numeric_col, "") or "").strip()
            if text_value not in {"", "NaN", "nan", "<missing>", "missing"}:
                continue
            number = _coerce_float(numeric_value)
            if number is None:
                continue
            row[text_col] = numeric_value or f"{number:.12g}"


def _drop_all_blank_columns(header: list[str], rows: list[list[str]]) -> tuple[list[str], list[list[str]]]:
    if not header or not rows:
        return header, rows
    keep_indices: list[int] = []
    for idx, _name in enumerate(header):
        values = _column_values(rows, idx)
        if all(str(value or "").strip() in {"", "NaN", "nan", "<missing>", "missing"} for value in values):
            continue
        keep_indices.append(idx)
    if not keep_indices:
        return header, rows
    trimmed_header = [header[idx] for idx in keep_indices]
    trimmed_rows = [[row[idx] if idx < len(row) else "" for idx in keep_indices] for row in rows]
    return trimmed_header, trimmed_rows


def _canonicalize_contract_source_rows(logical_path: str, header: list[str], rows: list[list[str]]) -> tuple[bytes, list[str], list[list[str]]]:
    scope = _scope_token_for_logical_path(logical_path)
    if not header:
        return _encode_csv(header, rows), header, rows
    if not rows:
        trimmed_header, trimmed_rows = _drop_all_blank_columns(header, rows)
        return _encode_csv(trimmed_header, trimmed_rows), trimmed_header, trimmed_rows
    dict_rows = [{str(header[idx]): str(row[idx]) if idx < len(row) else "" for idx in range(len(header))} for row in rows]
    _fill_numeric_text_companions(dict_rows, header)
    for field_name in header:
        lower_name = str(field_name or "").lower()
        companion_mask = _semantic_companion_mask(dict_rows, lower_name)
        for row_idx, row in enumerate(dict_rows):
            current = str(row.get(field_name, "") or "").strip()
            if current not in {"", "NaN", "nan", "<missing>", "missing"}:
                continue
            fill_value = _semantic_fill_value(lower_name, scope, companion_mask[row_idx])
            if fill_value:
                row[field_name] = fill_value
    normalized_rows = [[row.get(col, "") for col in header] for row in dict_rows]
    trimmed_header, trimmed_rows = _drop_all_blank_columns(header, normalized_rows)
    return _encode_csv(trimmed_header, trimmed_rows), trimmed_header, trimmed_rows


_ROW_FIELD_ALIASES: dict[str, tuple[str, ...]] = {
    "acknack": ("acknackstate", "acknack_state", "ack_nack_state", "finalstate", "final_state"),
    "acknackstate": ("acknack", "ack_nack", "finalstate", "final_state"),
    "aggregationlevel": ("aggregation_level", "al"),
    "blinddecodecount": ("blind_decode_count", "blinddecodes", "blind_decode_attempts"),
    "cellid": ("cell_id", "servingcell", "serving_cell", "sectorid", "sector_id"),
    "combineddecodeok": ("combined_decode_ok", "combineddecodepass", "combined_decode_pass", "finalstate", "final_state", "acknackstate", "ack_nack_state"),
    "combinedrounds": ("combined_rounds", "txcount", "tx_count"),
    "cqiused": ("widebandcqi", "wideband_cqi", "cqiinput", "cqi_input"),
    "crcpas": ("crcpass", "crc_pass", "status"),
    "crcpass": ("crc_pass", "decode_success", "decodesuccess", "status"),
    "currentdecodeok": ("current_decode_ok", "crcpass", "crc_pass", "status"),
    "decoderiterations": ("decoder_iterations", "ldpciterations", "ldpc_iterations", "iterations"),
    "detectionmetric": ("detection_metric", "peakmetric", "peak_metric"),
    "detectionoutcome": ("detection_outcome", "detectoutcome", "status"),
    "direction": ("linkdirection", "link_direction"),
    "frame": ("frameindex", "frame_idx"),
    "grantreason": ("grant_reason", "schedulerreason", "scheduler_reason"),
    "harqid": ("harq_id", "harqprocess", "harq_process", "harqprocessid", "harq_process_id"),
    "harqprocess": ("harqid", "harq_id", "harq_process", "harqprocessid", "harq_process_id"),
    "isretransmission": ("is_retransmission", "newtx_or_retx", "new_tx_or_retx", "tx_type"),
    "layers": ("numlayers", "num_layers", "rank", "rankindicator", "rank_indicator", "precodingnumlayers", "precoding_num_layers"),
    "mcsindex": ("mcs", "mcs_index", "selectedmcs", "selected_mcs", "mcsselected", "mcs_selected"),
    "occupancyfraction": ("occupancy_fraction", "occupancycount", "occupancy_count", "reoccupancyfraction", "re_occupancy_fraction", "allocationfraction", "allocation_fraction", "value", "metricvalue", "metric_value"),
    "pmi": ("appliedprecoderpmi", "applied_precoder_pmi", "requestedprecoderpmi", "requested_precoder_pmi"),
    "rankindicator": ("rank_indicator", "rank", "layers", "precodingnumlayers", "precoding_num_layers"),
    "rv": ("redundancyversion", "redundancy_version"),
    "slot": ("slotindex", "slot_idx"),
    "sourceartifact": ("source_artifact", "source_table_logical_path"),
    "txcount": ("tx_count", "transmissioncount", "transmission_count", "combinedrounds", "combined_rounds"),
    "ueid": ("ue_id", "ueindex", "ue_index", "rnti"),
    "ueindex": ("ue_id", "ueid", "ue_index", "rnti"),
    "widebandcqi": ("wideband_cqi", "cqi", "cqiused", "cqi_input", "cqiinput"),
}


def _normalized_row_key(name: Any) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(name or "").strip().lower())


def _row_candidate_keys(*names: str) -> list[str]:
    ordered: list[str] = []
    seen: set[str] = set()
    for name in names:
        key = _normalized_row_key(name)
        if key and key not in seen:
            ordered.append(key)
            seen.add(key)
        for alias in _ROW_FIELD_ALIASES.get(key, ()):
            alias_key = _normalized_row_key(alias)
            if alias_key and alias_key not in seen:
                ordered.append(alias_key)
                seen.add(alias_key)
    return ordered


def _row_value(row: dict[str, str], *names: str) -> Any:
    blank_exact: Any = None
    for name in names:
        if name in row:
            value = row.get(name)
            if _nonblank_text(value):
                return value
            if blank_exact is None:
                blank_exact = value
    wanted = set(_row_candidate_keys(*names))
    if not wanted:
        return blank_exact
    blank_alias: Any = None
    for key, value in row.items():
        if _normalized_row_key(key) in wanted:
            if _nonblank_text(value):
                return value
            if blank_alias is None:
                blank_alias = value
    if blank_exact is not None:
        return blank_exact
    return blank_alias


def _row_float(row: dict[str, str], *names: str) -> float | None:
    value = _row_value(row, *names)
    if value is None:
        return None
    return _coerce_float(value)


def _row_quality_axis_value(row: dict[str, str], *, allow_receiver_hest: bool = False) -> tuple[float | None, str]:
    """Return the best runtime-quality x-axis value.

    ConfiguredSNR_dB/SNR_dB are scenario metadata, not measurements. Strict
    chart materialization must not use them as a last-resort axis because that
    creates constant "curves" from incomplete evidence.
    """
    candidates = [
        ("PostEqSINR_dB", "PostEqSINR_dB"),
        ("MeasuredTrialSINR_dB", "MeasuredTrialSINR_dB"),
        ("MeasuredSINR_dB", "MeasuredSINR_dB"),
        ("MeasuredWidebandSINR_dB", "MeasuredWidebandSINR_dB"),
        ("LargeScaleSINR_dB", "LargeScaleSINR_dB"),
    ]
    if allow_receiver_hest:
        candidates.insert(2, ("ReceiverHestSINR_dB", "ReceiverHestSINR_dB"))
    for field_name, label in candidates:
        value = _row_float(row, field_name)
        if value is not None:
            return float(value), label
    return None, ""


def _row_snr_axis_value(row: dict[str, str]) -> tuple[float | None, str]:
    """Return the controlled channel operating point for an SNR-axis plot."""

    for field_name in ("AppliedAWGNSNR_dB", "AppliedSNR_dB", "ConfiguredSNR_dB", "SNR_dB"):
        value = _row_float(row, field_name)
        if value is not None and math.isfinite(float(value)):
            return float(value), field_name
    return None, ""


def _percentile(sorted_vals: list[float], fraction: float) -> float:
    if not sorted_vals:
        return float("nan")
    if len(sorted_vals) == 1:
        return float(sorted_vals[0])
    pos = max(0.0, min(1.0, float(fraction))) * (len(sorted_vals) - 1)
    low = int(math.floor(pos))
    high = int(math.ceil(pos))
    if low == high:
        return float(sorted_vals[low])
    weight = pos - low
    return float(sorted_vals[low] * (1.0 - weight) + sorted_vals[high] * weight)


def _row_text(row: dict[str, str], *names: str) -> str:
    value = _row_value(row, *names)
    if value is not None:
        text = str(value or "").strip()
        if text:
            return text
    return ""


def _normalize_drx_state(value: str) -> str:
    text = str(value or "").strip().lower()
    if not text or text in {"nan", "<missing>", "missing"}:
        return "unknown"
    if "sleep" in text or text in {"drx_sleep", "asleep"}:
        return "sleep"
    if "idle" in text or text in {"inactive", "rx_idle"}:
        return "idle"
    if "active" in text or text in {"tx", "rx", "active_tx", "active_rx", "pdcch_monitoring"}:
        return "active"
    return text


def _row_flag(row: dict[str, str], *names: str) -> bool | None:
    truthy = {"1", "true", "pass", "passed", "ok", "success", "detected", "observed", "yes", "available"}
    falsy = {"0", "false", "fail", "failed", "error", "miss", "missed", "no", "unavailable", "not_detected"}
    for name in names:
        raw_value = _row_value(row, name)
        if raw_value is None:
            continue
        text = str(raw_value).strip().lower()
        if not text or text in {"nan", "<missing>", "missing"}:
            continue
        if text in truthy:
            return True
        if text in falsy:
            return False
        number = _coerce_float(raw_value)
        if number is not None:
            return not math.isclose(float(number), 0.0)
    return None


def _parse_index_tokens(value: Any) -> list[int]:
    text = str(value or "").strip()
    if not text or text.lower() in {"nan", "<missing>", "missing"}:
        return []
    tokens = []
    for match in re.findall(r"-?\d+", text):
        try:
            tokens.append(int(match))
        except Exception:
            continue
    return tokens


def _render_reason_svg(title: str, subtitle: str, lines: list[str]) -> bytes:
    width = 1100
    height = 520
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#f8fafc"/>',
        '<rect x="40" y="40" width="1020" height="440" rx="18" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>',
        f'<text x="72" y="96" font-family="Segoe UI,Arial,sans-serif" font-size="28" font-weight="700" fill="#0f172a">{html.escape(title)}</text>',
        f'<text x="72" y="126" font-family="Segoe UI,Arial,sans-serif" font-size="15" fill="#475569">{html.escape(subtitle)}</text>',
        '<text x="72" y="176" font-family="Segoe UI,Arial,sans-serif" font-size="18" font-weight="700" fill="#7c2d12">Unavailable Without Faking</text>',
    ]
    y = 214
    for line in lines[:12]:
        parts.append(
            f'<text x="72" y="{y}" font-family="Consolas,Segoe UI Mono,monospace" font-size="14" fill="#334155">{html.escape(line)}</text>'
        )
        y += 28
    parts.append('</svg>')
    return "".join(parts).encode("utf-8")


def _format_card_number(value: Any, unit: str = "") -> str:
    number = _coerce_float(value)
    if number is None or not math.isfinite(float(number)):
        return "n/a"
    value_f = float(number)
    if math.isclose(value_f, round(value_f), abs_tol=1e-12):
        text = f"{int(round(value_f))}"
    elif abs(value_f) >= 1000 or (abs(value_f) > 0 and abs(value_f) < 1e-3):
        text = f"{value_f:.4e}"
    else:
        text = f"{value_f:.6g}"
    return f"{text} {unit}".strip()


def _render_kpi_card_svg(
    title: str,
    subtitle: str,
    kpis: list[tuple[str, Any, str]],
    summary_lines: list[str],
    *,
    visual_gate: str,
) -> bytes:
    width = 1120
    height = 620
    card_w = 320
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#f8fafc"/>',
        f'<text x="42" y="50" font-family="Segoe UI,Arial,sans-serif" font-size="28" font-weight="700" fill="#0f172a">{html.escape(title)}</text>',
        f'<text x="42" y="78" font-family="Segoe UI,Arial,sans-serif" font-size="15" fill="#475569">{html.escape(subtitle)}</text>',
        '<text x="42" y="112" font-family="Consolas,Segoe UI Mono,monospace" font-size="13" fill="#7c2d12">'
        + html.escape(f"visual_gate={visual_gate}")
        + "</text>",
    ]
    for idx, (label, value, unit) in enumerate(kpis[:3]):
        x = 42 + idx * (card_w + 22)
        parts.extend(
            [
                f'<rect x="{x}" y="140" width="{card_w}" height="148" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>',
                f'<text x="{x + 24}" y="178" font-family="Segoe UI,Arial,sans-serif" font-size="16" font-weight="700" fill="#334155">{html.escape(str(label))}</text>',
                f'<text x="{x + 24}" y="238" font-family="Segoe UI,Arial,sans-serif" font-size="40" font-weight="800" fill="#0f766e">{html.escape(_format_card_number(value, unit))}</text>',
            ]
        )
    parts.extend(
        [
            '<rect x="42" y="320" width="1030" height="240" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>',
            '<text x="66" y="358" font-family="Segoe UI,Arial,sans-serif" font-size="18" font-weight="700" fill="#0f172a">Exact Source Summary</text>',
        ]
    )
    y = 390
    for line in summary_lines[:8]:
        parts.append(f'<text x="66" y="{y}" font-family="Consolas,Segoe UI Mono,monospace" font-size="14" fill="#334155">{html.escape(str(line))}</text>')
        y += 25
    parts.append('</svg>')
    return "".join(parts).encode("utf-8")


def _render_prach_rate_card_svg(
    title: str,
    metric_label: str,
    rate_value: float,
    positive_count: float,
    sample_count: int,
    summary_lines: list[str],
) -> bytes:
    return _render_kpi_card_svg(
        title,
        "PRACH rate evidence is a scalar run aggregate, not a sweep or trend.",
        [
            (metric_label, rate_value, ""),
            ("Positive trials", positive_count, ""),
            ("Samples", sample_count, ""),
        ],
        summary_lines + ["chart_decision=scalar_prach_rate_card"],
        visual_gate="scalar_prach_rate_kpi",
    )


def _render_reliability_card_svg(
    title: str,
    metric_value: float,
    sample_count: int,
    summary_lines: list[str],
) -> bytes:
    return _render_kpi_card_svg(
        title,
        "Reliability evidence is a scalar run summary. A curve requires controlled SNR/SINR/MCS buckets.",
        [(title, metric_value, ""), ("Samples", sample_count, ""), ("Curve points", 1, "")],
        summary_lines + ["chart_decision=scalar_reliability_card"],
        visual_gate="scalar_reliability_kpi",
    )


def _render_prach_peak_summary_svg(
    title: str,
    values: list[float],
    status_counts: Counter[str],
    summary_lines: list[str],
) -> bytes:
    clean = sorted(float(value) for value in values if math.isfinite(float(value)))
    if clean:
        kpis = [
            ("Peak samples", len(clean), ""),
            ("Peak min", clean[0], ""),
            ("Peak max", clean[-1], ""),
        ]
        median = _percentile(clean, 0.5)
        detail = [f"peak_p50={median:.6g}", f"peak_span={clean[-1] - clean[0]:.6g}"]
    else:
        kpis = [("Peak samples", 0, ""), ("Peak min", "", ""), ("Peak max", "", "")]
        detail = ["peak_values=none"]
    detail.extend(f"status_{idx + 1}={label}:{count}" for idx, (label, count) in enumerate(status_counts.most_common(4)))
    return _render_kpi_card_svg(
        title,
        "PRACH peak evidence is too sparse for a histogram/timeline, so exact summary statistics are shown.",
        kpis,
        summary_lines + detail + ["chart_decision=prach_peak_summary_card"],
        visual_gate="sparse_prach_peak_evidence",
    )


def _render_resource_occupancy_card_svg(
    title: str,
    *,
    occupied_cells: int,
    x_count: int,
    y_count: int,
    value_sum: float,
    summary_lines: list[str],
) -> bytes:
    return _render_kpi_card_svg(
        title,
        "Resource occupancy has only one independent map axis in this run, so a heatmap would imply missing 2-D variation.",
        [
            ("Occupied cells", occupied_cells, ""),
            ("Unique x-axis", x_count, ""),
            ("Unique y-axis", y_count, ""),
        ],
        summary_lines + [f"occupancy_sum={value_sum:.6g}", "chart_decision=single_axis_resource_card"],
        visual_gate="single_axis_resource_occupancy",
    )


def _render_waveform_flat_card_svg(
    title: str,
    series: list[dict[str, Any]],
    summary_lines: list[str],
) -> bytes:
    sample_count = sum(len(item.get("points") or []) for item in series)
    max_abs = 0.0
    for item in series:
        for point in item.get("points") or []:
            if isinstance(point, (list, tuple)) and len(point) >= 2 and _coerce_float(point[1]) is not None:
                max_abs = max(max_abs, abs(float(point[1])))
    return _render_kpi_card_svg(
        title,
        "The exported waveform preview is flat, so the image reports amplitude evidence instead of drawing a meaningless trace.",
        [("Preview samples", sample_count, ""), ("Max abs amplitude", max_abs, ""), ("Active series", len(series), "")],
        summary_lines + ["chart_decision=flat_waveform_card"],
        visual_gate="flat_waveform_preview",
    )


def _heat_color(value: float, max_value: float) -> str:
    if max_value <= 0:
        return "#e2e8f0"
    ratio = max(0.0, min(1.0, value / max_value))
    r = int(230 - 170 * ratio)
    g = int(244 - 70 * ratio)
    b = int(255 - 165 * ratio)
    return f"rgb({r},{g},{b})"


def _render_heatmap_svg(
    title: str,
    subtitle: str,
    x_labels: list[str],
    y_labels: list[str],
    matrix: list[list[float]],
    summary_lines: list[str],
    x_axis_title: str,
    y_axis_title: str,
    *,
    allow_singleton_observation: bool = False,
) -> bytes:
    width = 1180
    height = 760
    left = 90
    top = 96
    plot_w = 710
    plot_h = 560
    info_x = 840
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#f8fafc"/>',
        f'<text x="44" y="50" font-family="Segoe UI,Arial,sans-serif" font-size="28" font-weight="700" fill="#0f172a">{html.escape(title)}</text>',
        f'<text x="44" y="76" font-family="Segoe UI,Arial,sans-serif" font-size="15" fill="#475569">{html.escape(_ellipsize_svg_text(subtitle, 116))}</text>',
        f'<rect x="{left}" y="{top}" width="{plot_w}" height="{plot_h}" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>',
        f'<rect x="{info_x}" y="{top}" width="300" height="{plot_h}" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>',
    ]
    if not x_labels or not y_labels or not matrix:
        return _render_reason_svg(title, subtitle, summary_lines + ["No heatmap cells were derived from the persisted runtime source rows."])
    if (len(x_labels) < 2 or len(y_labels) < 2) and not allow_singleton_observation:
        return _render_reason_svg(
            title,
            "Exact runtime source rows exist, but a heatmap requires two independent axes.",
            summary_lines + [
                "visual_gate=insufficient_heatmap_axes",
                f"unique_x_labels={len(x_labels)}",
                f"unique_y_labels={len(y_labels)}",
            ],
        )
    max_value = max((value for row in matrix for value in row), default=0.0)
    if max_value <= 0.0:
        return _render_reason_svg(
            title,
            "Exact runtime source rows exist, but every heatmap cell is zero.",
            summary_lines + ["visual_gate=all_zero_heatmap_cells"],
        )
    n_x = max(len(x_labels), 1)
    n_y = max(len(y_labels), 1)
    cell_w = (plot_w - 80) / n_x
    cell_h = (plot_h - 70) / n_y
    base_x = left + 56
    base_y = top + 24
    for y_idx, row in enumerate(matrix):
        for x_idx, value in enumerate(row):
            x = base_x + x_idx * cell_w
            y = base_y + y_idx * cell_h
            parts.append(
                f'<rect x="{x:.2f}" y="{y:.2f}" width="{cell_w + 0.2:.2f}" height="{cell_h + 0.2:.2f}" fill="{_heat_color(value, max_value)}" />'
            )
    parts.append(f'<text x="{left + plot_w / 2:.1f}" y="{top + plot_h + 28}" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="14" fill="#334155">{html.escape(x_axis_title)}</text>')
    parts.append(f'<text x="{left + 8}" y="{top + 14}" font-family="Segoe UI,Arial,sans-serif" font-size="14" fill="#334155">{html.escape(y_axis_title)}</text>')
    x_tick_count = min(8, len(x_labels))
    for idx in range(x_tick_count):
        pos = round(idx * (len(x_labels) - 1) / max(x_tick_count - 1, 1))
        x = base_x + pos * cell_w + cell_w / 2
        parts.append(f'<text x="{x:.1f}" y="{top + plot_h + 10}" text-anchor="middle" font-family="Consolas,Segoe UI Mono,monospace" font-size="11" fill="#475569">{html.escape(str(x_labels[pos]))}</text>')
    y_tick_count = min(10, len(y_labels))
    for idx in range(y_tick_count):
        pos = round(idx * (len(y_labels) - 1) / max(y_tick_count - 1, 1))
        y = base_y + pos * cell_h + 4
        parts.append(f'<text x="{left + 46}" y="{y:.1f}" text-anchor="end" font-family="Consolas,Segoe UI Mono,monospace" font-size="11" fill="#475569">{html.escape(str(y_labels[pos]))}</text>')
    parts.append(f'<text x="{info_x + 18}" y="{top + 30}" font-family="Segoe UI,Arial,sans-serif" font-size="18" font-weight="700" fill="#0f172a">Run Summary</text>')
    y = top + 60
    for line in summary_lines[:18]:
        parts.append(f'<text x="{info_x + 18}" y="{y}" font-family="Consolas,Segoe UI Mono,monospace" font-size="13" fill="#334155">{html.escape(_ellipsize_svg_text(line, 36))}</text>')
        y += 22
    parts.append('</svg>')
    return "".join(parts).encode("utf-8")


def _render_heatmap_or_projection_svg(
    title: str,
    subtitle: str,
    x_labels: list[str],
    y_labels: list[str],
    matrix: list[list[float]],
    summary_lines: list[str],
    x_axis_title: str,
    y_axis_title: str,
) -> tuple[bytes, str]:
    """Render a 2-D heatmap or an explicitly labeled 1-D projection.

    A single-cell/single-UE run often has only one spatial category.  Rejecting
    that data as unavailable loses useful occupancy evidence; duplicating the
    category would fake a second axis.  The exact marginal projection is the
    scientifically honest visualization in that case.
    """
    if len(x_labels) >= 2 and len(y_labels) >= 2:
        return (
            _render_heatmap_svg(
                title, subtitle, x_labels, y_labels, matrix, summary_lines,
                x_axis_title, y_axis_title,
            ),
            "generated_specialized_runtime_heatmap_svg",
        )
    if not x_labels or not y_labels or not matrix:
        return (
            _render_reason_svg(
                title, subtitle,
                summary_lines + ["No finite occupancy cells were available."],
            ),
            "generated_unavailable_reason_svg",
        )
    if len(x_labels) >= 2:
        values = [
            sum(float(row[index]) for row in matrix if index < len(row))
            for index in range(len(x_labels))
        ]
        labels = [str(value) for value in x_labels]
        axis_label = x_axis_title
    elif len(y_labels) >= 2:
        values = [sum(float(value) for value in row) for row in matrix]
        labels = [str(value) for value in y_labels]
        axis_label = y_axis_title
    else:
        values = [sum(float(value) for row in matrix for value in row)]
        labels = [f"{x_labels[0]} / {y_labels[0]}"]
        axis_label = f"{x_axis_title} / {y_axis_title}"
    dataset = {
        "mode": "bar",
        "x_label": f"{axis_label} projection",
        "y_label": "Summed occupancy",
        "points": [[float(index + 1), value] for index, value in enumerate(values)],
        "tick_labels": labels,
        "evidence_shape_policy": "observed_distribution" if len(values) > 1 else "measured_scalar",
        "sample_count": max(1, sum(1 for row in matrix for _value in row)),
    }
    return (
        _render_svg_plot(
            title,
            f"{subtitle} One axis has one observed category, so the exact marginal projection is shown instead of inventing a 2-D surface.",
            dataset,
            summary_lines + [
                "view=exact_1d_projection",
                f"unique_{x_axis_title.lower().replace(' ', '_')}={len(x_labels)}",
                f"unique_{y_axis_title.lower().replace(' ', '_')}={len(y_labels)}",
            ],
        ),
        "generated_specialized_runtime_projection_svg",
    )


def _render_scatter_panels_svg(
    title: str,
    subtitle: str,
    panels: list[tuple[str, list[tuple[float, float, str]], list[tuple[float, float]]]],
    summary_lines: list[str],
) -> bytes:
    width = 1180
    height = 760
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#f8fafc"/>',
        f'<text x="40" y="48" font-family="Segoe UI,Arial,sans-serif" font-size="28" font-weight="700" fill="#0f172a">{html.escape(title)}</text>',
        f'<text x="40" y="74" font-family="Segoe UI,Arial,sans-serif" font-size="15" fill="#475569">{html.escape(_ellipsize_svg_text(subtitle, 116))}</text>',
    ]
    if not panels:
        return _render_reason_svg(title, subtitle, summary_lines + ["No constellation preview samples were available for this chart."])
    panel_w = 320
    panel_h = 250
    base_x = 44
    base_y = 110
    colors = {"DL": "#0f766e", "UL": "#1d4ed8"}
    for idx, (panel_title, points, ideal_points) in enumerate(panels[:3]):
        row = idx // 2
        col = idx % 2
        x0 = base_x + col * (panel_w + 28)
        y0 = base_y + row * (panel_h + 28)
        parts.append(f'<rect x="{x0}" y="{y0}" width="{panel_w}" height="{panel_h}" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>')
        parts.append(f'<text x="{x0 + 16}" y="{y0 + 26}" font-family="Segoe UI,Arial,sans-serif" font-size="16" font-weight="700" fill="#0f172a">{html.escape(panel_title)}</text>')
        cx = x0 + panel_w / 2
        cy = y0 + panel_h / 2 + 12
        radius = 86
        numeric = [(x_val, y_val) for x_val, y_val, _direction in points] + list(ideal_points)
        observed_max = max((max(abs(x_val), abs(y_val)) for x_val, y_val in numeric), default=1.0)
        axis_limit = max(1.0, math.ceil(observed_max * 2.0) / 2.0)
        for tick in _axis_tick_values(-axis_limit, axis_limit):
            px = cx + (tick / axis_limit) * radius
            py = cy - (tick / axis_limit) * radius
            parts.append(f'<line x1="{px:.2f}" y1="{cy - radius}" x2="{px:.2f}" y2="{cy + radius}" stroke="#e2e8f0" stroke-width="1"/>')
            parts.append(f'<line x1="{cx - radius}" y1="{py:.2f}" x2="{cx + radius}" y2="{py:.2f}" stroke="#e2e8f0" stroke-width="1"/>')
            parts.append(f'<text x="{px:.2f}" y="{cy + radius + 14}" text-anchor="middle" font-family="Consolas,Segoe UI Mono,monospace" font-size="9" fill="#64748b">{html.escape(_format_axis_tick(tick))}</text>')
            parts.append(f'<text x="{cx - radius - 7}" y="{py + 3:.2f}" text-anchor="end" font-family="Consolas,Segoe UI Mono,monospace" font-size="9" fill="#64748b">{html.escape(_format_axis_tick(tick))}</text>')
        parts.append(f'<line x1="{cx - radius}" y1="{cy}" x2="{cx + radius}" y2="{cy}" stroke="#94a3b8" stroke-width="1.1"/>')
        parts.append(f'<line x1="{cx}" y1="{cy - radius}" x2="{cx}" y2="{cy + radius}" stroke="#94a3b8" stroke-width="1.1"/>')
        parts.append(f'<text x="{cx}" y="{y0 + panel_h - 8}" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="11" fill="#334155">In-phase</text>')
        parts.append(f'<text x="{x0 + 14}" y="{cy}" text-anchor="middle" transform="rotate(-90 {x0 + 14} {cy})" font-family="Segoe UI,Arial,sans-serif" font-size="11" fill="#334155">Quadrature</text>')
        for ix, iy in ideal_points[:64]:
            px = cx + (ix / axis_limit) * radius
            py = cy - (iy / axis_limit) * radius
            parts.append(f'<circle cx="{px:.2f}" cy="{py:.2f}" r="4.0" fill="#cbd5e1" />')
        for x_val, y_val, direction in points[:420]:
            px = cx + (x_val / axis_limit) * radius
            py = cy - (y_val / axis_limit) * radius
            color = colors.get(direction, "#475569")
            parts.append(f'<circle cx="{px:.2f}" cy="{py:.2f}" r="2.0" fill="{color}" fill-opacity="0.72" />')
    info_x = 740
    parts.append(f'<rect x="{info_x}" y="{base_y}" width="396" height="548" rx="14" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.5"/>')
    parts.append(f'<text x="{info_x + 18}" y="{base_y + 30}" font-family="Segoe UI,Arial,sans-serif" font-size="18" font-weight="700" fill="#0f172a">Run Summary</text>')
    y = base_y + 60
    for line in summary_lines[:20]:
        parts.append(f'<text x="{info_x + 18}" y="{y}" font-family="Consolas,Segoe UI Mono,monospace" font-size="13" fill="#334155">{html.escape(line)}</text>')
        y += 22
    parts.append(f'<circle cx="{info_x + 24}" cy="{y + 16}" r="5" fill="#0f766e"/><text x="{info_x + 38}" y="{y + 20}" font-family="Segoe UI,Arial,sans-serif" font-size="13" fill="#334155">DL equalized symbols</text>')
    parts.append(f'<circle cx="{info_x + 24}" cy="{y + 42}" r="5" fill="#1d4ed8"/><text x="{info_x + 38}" y="{y + 46}" font-family="Segoe UI,Arial,sans-serif" font-size="13" fill="#334155">UL equalized symbols</text>')
    parts.append(f'<circle cx="{info_x + 24}" cy="{y + 68}" r="5" fill="#cbd5e1"/><text x="{info_x + 38}" y="{y + 72}" font-family="Segoe UI,Arial,sans-serif" font-size="13" fill="#334155">Ideal constellation points</text>')
    parts.append('</svg>')
    return "".join(parts).encode("utf-8")


def _summary_csv_rows(
    run_id: int,
    section_title: str,
    label_name: str,
    status: str,
    source_artifact: str,
    source_row_count: int,
    note: str,
) -> tuple[list[str], list[list[Any]]]:
    header = [
        "run_id",
        "section_title",
        "label_name",
        "contract_materialization_status",
        "source_artifact",
        "source_row_count",
        "lineage_note",
    ]
    rows = [[run_id, section_title, label_name, status, source_artifact or "not_published_by_runtime", source_row_count, note]]
    return header, rows


def _contract_artifact_paths() -> set[str]:
    """Return artifacts whose bytes are owned by this materializer.

    Some catalog tables intentionally use their MATLAB producer path as the
    canonical browser path (for example the recursive CSV/image audits).  A
    forced materialization preserves those direct aliases, so the filesystem
    cache must classify them as producer inputs as well.  Treating them as
    derived outputs hides producer changes from the source digest and makes
    the cache disagree with the replacement transaction.
    """
    paths = {
        manifest_logical_path(),
        coverage_logical_path(),
        plot_lineage_logical_path(),
        FILESYSTEM_CONTRACT_CACHE_PATH,
    }
    for table_spec in _table_specs():
        target = table_contract_path(table_spec)
        table_name = str(table_spec.get("table_name") or "")
        direct_sources = {
            str(path or "").strip().lower()
            for path in _table_sources(table_name)
        }
        if target and str(target).strip().lower() not in direct_sources:
            paths.add(target)
    for chart_spec in _chart_specs():
        paths.add(chart_contract_csv_path(chart_spec))
        paths.add(chart_contract_image_path(chart_spec))
    return paths


def _filesystem_artifact_sha256(artifact: dict[str, Any]) -> str:
    filesystem_path = str(artifact.get("filesystem_path") or "").strip()
    if not filesystem_path:
        return ""
    path = _windows_long_path(Path(filesystem_path))
    if not path.is_file():
        return ""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def _filesystem_inventory_digest(
    artifacts: list[dict[str, Any]],
    *,
    include_contract_owned: bool,
) -> tuple[str, dict[str, str]]:
    """Hash exact filesystem bytes, separated by producer/contract authority."""
    contract_paths = _contract_artifact_paths()
    rows: list[tuple[str, int, str]] = []
    hashes: dict[str, str] = {}
    for artifact in artifacts:
        logical_path = str(artifact.get("logical_path") or "").strip().lower()
        if not logical_path or logical_path == FILESYSTEM_CONTRACT_CACHE_PATH:
            continue
        is_contract = logical_path in contract_paths
        if is_contract != bool(include_contract_owned):
            continue
        digest = _filesystem_artifact_sha256(artifact)
        if not digest:
            continue
        hashes[logical_path] = digest
        rows.append((logical_path, int(artifact.get("byte_size") or 0), digest))
    canonical = json.dumps(sorted(rows), separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest(), hashes


def filesystem_contract_cache_current(
    run_folder: Path,
    artifacts: list[dict[str, Any]],
    feature_policy: dict[str, bool] | None = None,
) -> bool:
    """Return true only when sources and every cached contract byte match."""
    cache_path = _windows_long_path(
        Path(run_folder) / Path(FILESYSTEM_CONTRACT_CACHE_PATH)
    )
    if not cache_path.is_file():
        return False
    try:
        cache = json.loads(cache_path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return False
    if str(cache.get("materializer_version") or "") != MATERIALIZER_VERSION:
        return False
    coverage = coverage_summary(artifacts, dict(feature_policy or {}))
    if coverage.get("missing_table_paths") or coverage.get("missing_chart_names"):
        return False
    source_digest, _ = _filesystem_inventory_digest(
        artifacts, include_contract_owned=False
    )
    contract_digest, contract_hashes = _filesystem_inventory_digest(
        artifacts, include_contract_owned=True
    )
    return (
        str(cache.get("source_inventory_sha256") or "") == source_digest
        and str(cache.get("contract_inventory_sha256") or "") == contract_digest
        and dict(cache.get("contract_artifact_sha256") or {}) == contract_hashes
    )


def write_filesystem_contract_cache(
    run_folder: Path,
    artifacts: list[dict[str, Any]],
    feature_policy: dict[str, bool] | None = None,
) -> dict[str, Any]:
    """Seal exact producer inputs and derived contract bytes for safe reuse."""
    coverage = coverage_summary(artifacts, dict(feature_policy or {}))
    if coverage.get("missing_table_paths") or coverage.get("missing_chart_names"):
        raise RuntimeError(
            "Refusing to cache an incomplete browser contract: "
            f"tables={len(coverage.get('missing_table_paths') or [])} "
            f"charts={len(coverage.get('missing_chart_names') or [])}."
        )
    source_digest, source_hashes = _filesystem_inventory_digest(
        artifacts, include_contract_owned=False
    )
    contract_digest, contract_hashes = _filesystem_inventory_digest(
        artifacts, include_contract_owned=True
    )
    payload = {
        "schema_version": 1,
        "materializer_version": MATERIALIZER_VERSION,
        "source_inventory_sha256": source_digest,
        "source_artifact_count": len(source_hashes),
        "contract_inventory_sha256": contract_digest,
        "contract_artifact_count": len(contract_hashes),
        "contract_artifact_sha256": contract_hashes,
    }
    target = _windows_long_path(
        Path(run_folder) / Path(FILESYSTEM_CONTRACT_CACHE_PATH)
    )
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return payload


def _artifact_is_contract_owned(
    artifact: dict[str, Any] | None,
    db_connection_factory: Callable[[], Any],
) -> bool:
    if not artifact:
        return False
    logical_path = str(artifact.get("logical_path") or "").strip()
    if not logical_path:
        return False
    if logical_path in {
        manifest_logical_path(),
        coverage_logical_path(),
        plot_lineage_logical_path(),
    }:
        return True
    # All chart contract artifacts live in a dedicated contract__ namespace and
    # can be safely treated as materializer-owned even if their metadata is old.
    if "/contract__" in logical_path:
        return True
    payload = _artifact_metadata_json(artifact, db_connection_factory)
    if not payload:
        return False
    lower_payload = payload.lower()
    return (
        '"materializer_version"' in lower_payload
        or '"contract_table"' in lower_payload
        or '"chart_name"' in lower_payload
    )


def _contract_owned_paths(
    artifacts: list[dict[str, Any]],
    db_connection_factory: Callable[[], Any],
) -> set[str]:
    owned: set[str] = set()
    for artifact in artifacts:
        if _artifact_is_contract_owned(artifact, db_connection_factory):
            logical_path = str(artifact.get("logical_path") or "").strip()
            if logical_path:
                owned.add(logical_path)
    return owned


def _source_artifact_high_watermark(
    artifacts: list[dict[str, Any]],
    db_connection_factory: Callable[[], Any],
) -> int:
    contract_paths = _contract_owned_paths(artifacts, db_connection_factory)
    return max(
        (
            int(art.get("artifact_id") or 0)
            for art in artifacts
            if str(art.get("logical_path") or "") not in contract_paths
        ),
        default=0,
    )


def _specialized_table_materialization(
    table_name: str,
    source_lookup: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
    section_title: str,
    run_row: dict[str, Any] | None = None,
    feature_policy: dict[str, bool] | None = None,
) -> dict[str, Any] | None:
    generic = _specialized_live_report_table(
        table_name,
        source_lookup,
        fetch_artifact_bytes,
        run_id,
        run_row,
        feature_policy,
    )
    if generic is not None:
        return generic
    if str(table_name or "").strip() == "fairness_analytics":
        source_path = ""
        for candidate in (
            "reports/csv/live_user_performance_snapshot.csv",
            "system/csv/system_ue_summary.csv",
            "system/summaries/system_kpi_summary.csv",
        ):
            if candidate in source_lookup:
                source_path = candidate
                break
        if not source_path:
            return None
        _, rows = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, source_path)
        if not rows:
            return None
        fairness_rows: list[dict[str, Any]] = []
        for metric_name, direction in (
            ("DL_Throughput_Mbps", "DL"),
            ("UL_Throughput_Mbps", "UL"),
            ("UserThroughput_Mbps", "Combined"),
        ):
            values: list[float] = []
            for row in rows:
                value = _row_float(row, metric_name)
                if value is not None and math.isfinite(value):
                    values.append(float(value))
            if not values:
                continue
            sorted_vals = sorted(values)
            count = len(sorted_vals)
            total = sum(sorted_vals)
            total_sq = sum(v * v for v in sorted_vals)
            fairness = (total * total) / (count * total_sq) if count > 0 and total_sq > 0 else 0.0
            fairness_rows.append({
                "run_id": run_id,
                "direction": direction,
                "metric_name": metric_name,
                "sample_count": count,
                "mean_mbps": total / count,
                "p05_mbps": _percentile(sorted_vals, 0.05),
                "p50_mbps": _percentile(sorted_vals, 0.50),
                "p95_mbps": _percentile(sorted_vals, 0.95),
                "min_mbps": sorted_vals[0],
                "max_mbps": sorted_vals[-1],
                "jain_fairness_index": fairness,
                "zero_throughput_user_count": sum(1 for value in sorted_vals if math.isclose(value, 0.0, abs_tol=1e-12)),
                "source_artifact": source_path,
            })
        if not fairness_rows:
            return None
        header = list(fairness_rows[0].keys())
        return {
            "data": _encode_dict_rows(header, fairness_rows),
            "status": "specialized_runtime_fairness_summary",
            "note": "Fairness analytics derived from truthful per-UE throughput evidence.",
            "source_logical_path": source_path,
            "source_row_count": len(rows),
        }
    match = re.fullmatch(r"live_pucch_f([0-4])_table", str(table_name or "").strip())
    if not match:
        return None
    target_format = match.group(1)
    candidate_paths = (
        "air_interface/csv/pucch_trials.csv",
        "packet_flow/csv/live_pucch_grants.csv",
        "control/csv/pucch_table.csv",
    )

    def normalized_pucch_format(row: dict[str, Any]) -> str:
        token = _row_text(
            row,
            "ResolvedFormat",
            "RequestedFormat",
            "PUCCHFormat",
            "Format",
        ).strip().upper().replace(" ", "").replace("_", "").replace("-", "")
        matched = re.fullmatch(r"(?:PUCCH)?(?:FORMAT|F)?([0-4])", token)
        return matched.group(1) if matched else ""

    available_path = ""
    available_header: list[str] = []
    available_rows: list[dict[str, str]] = []
    source_path = ""
    header: list[str] = []
    rows: list[dict[str, str]] = []
    filtered_rows: list[dict[str, str]] = []
    for candidate_path in candidate_paths:
        artifact = source_lookup.get(candidate_path)
        if artifact is None:
            continue
        candidate_header, candidate_rows = _decode_csv_dicts(
            fetch_artifact_bytes(int(artifact["artifact_id"]))
        )
        if not available_path:
            available_path = candidate_path
            available_header = candidate_header
            available_rows = candidate_rows
        candidate_filtered = [
            row for row in candidate_rows
            if normalized_pucch_format(row) == target_format
        ]
        if candidate_filtered:
            source_path = candidate_path
            header = candidate_header
            rows = candidate_rows
            filtered_rows = candidate_filtered
            break
    if not available_path:
        return None
    if not source_path:
        source_path = available_path
        header = available_header
        rows = available_rows
    if not rows:
        summary_header, summary_rows = _summary_csv_rows(
            run_id,
            section_title,
            table_name,
            "source_artifact_present_but_empty",
            source_path,
            0,
            "The canonical PUCCH control table exists for this run, but it has no real rows.",
        )
        return {
            "data": _encode_csv(summary_header, summary_rows),
            "status": "empty_source_summary",
            "note": "Canonical contract table summarizes an empty PUCCH control source artifact.",
            "source_logical_path": source_path,
            "source_row_count": 0,
        }
    if not filtered_rows:
        summary_header, summary_rows = _summary_csv_rows(
            run_id,
            section_title,
            table_name,
            "source_artifact_present_but_empty",
            source_path,
            0,
            f"No runtime PUCCH rows resolved to format {target_format} in this bounded run.",
        )
        return {
            "data": _encode_csv(summary_header, summary_rows),
            "status": "empty_source_summary",
            "note": f"Canonical contract table records that no PUCCH format {target_format} rows were observed for this run.",
            "source_logical_path": source_path,
            "source_row_count": 0,
        }
    encoded_rows = [[row.get(col, "") for col in header] for row in filtered_rows]
    return {
        "data": _encode_csv(header, encoded_rows),
        "status": "specialized_runtime_pucch_format_table",
        "note": f"Canonical contract table filtered the runtime PUCCH control rows to resolved format {target_format}.",
        "source_logical_path": source_path,
        "source_row_count": len(filtered_rows),
    }


def _artifact_rows_by_path(
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    logical_path: str,
) -> tuple[list[str], list[dict[str, str]]]:
    art = existing.get(logical_path)
    if not art:
        return [], []
    return _decode_csv_dicts(fetch_artifact_bytes(int(art["artifact_id"])))


def _json_object(payload: Any) -> dict[str, Any]:
    if isinstance(payload, dict):
        return payload
    text = str(payload or "").strip()
    if not text:
        return {}
    try:
        decoded = json.loads(text)
    except Exception:
        return {}
    return decoded if isinstance(decoded, dict) else {}


def _nested_value(payload: dict[str, Any], path: str, default: Any = None) -> Any:
    current: Any = payload
    for part in str(path or "").split("."):
        if not isinstance(current, dict) or part not in current:
            return default
        current = current.get(part)
    return current


def _first_config_value(
    payload: dict[str, Any], *paths: str, default: Any = ""
) -> Any:
    """Resolve one persisted configuration value across supported schemas.

    WebGUI rows can contain the submitted master YAML, the normalized runtime
    config, or a wrapper carrying either under ``lls6g``.  Returning the first
    nonblank value keeps the adapter versioned and explicit without replacing
    missing runtime values with presentation defaults.
    """

    views = [
        payload,
        _json_object(_nested_value(payload, "lls6g.resolvedConfig", {})),
        _json_object(_nested_value(payload, "lls6g.submittedScenarioConfig", {})),
    ]
    for view in views:
        for path in paths:
            value = _nested_value(view, path, None)
            if value is None:
                continue
            if isinstance(value, str) and not value.strip():
                continue
            return value
    return default


def _run_allows_placeholder_artifacts(run_row: dict[str, Any]) -> bool:
    config = _json_object(run_row.get("config_json"))
    candidates = [
        _nested_value(config, "output.emit_placeholder_artifacts", None),
        _nested_value(config, "lls6g.resolvedConfig.output.emit_placeholder_artifacts", None),
        _nested_value(config, "lls6g.submittedScenarioConfig.output.emit_placeholder_artifacts", None),
    ]
    for value in candidates:
        if isinstance(value, bool):
            return bool(value)
        if isinstance(value, str) and value.strip():
            return value.strip().lower() in {"1", "true", "yes", "on"}
    return False


def _is_placeholder_materialization_status(status: str) -> bool:
    return str(status or "").strip().lower() in {
        "source_artifact_missing",
        "source_artifact_present_but_empty",
        "empty_source_summary",
        "missing_source_summary",
        "generated_unavailable_reason_svg",
        "generated_unavailable_reason_png",
        "generated_low_information_reason_png",
    }


def _first_available_rows(
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    candidates: list[str] | tuple[str, ...],
) -> tuple[str, list[dict[str, str]]]:
    for logical_path in candidates:
        _header, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, logical_path)
        if rows and not _is_absence_placeholder_rows(rows):
            return str(logical_path), rows
    return "", []


def _all_available_rows(
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    candidates: list[str] | tuple[str, ...],
) -> list[tuple[str, list[dict[str, str]]]]:
    out: list[tuple[str, list[dict[str, str]]]] = []
    for logical_path in candidates:
        _header, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, logical_path)
        if rows and not _is_absence_placeholder_rows(rows):
            out.append((str(logical_path), rows))
    return out


def _is_absence_placeholder_rows(rows: list[dict[str, str]]) -> bool:
    status = _table_placeholder_summary_status(rows)
    if status in {"source_artifact_missing", "source_artifact_present_but_empty"}:
        return True
    if len(rows) != 1:
        return False
    source_artifact = _row_text(rows[0], "source_artifact").lower()
    if source_artifact == "not_published_by_runtime":
        return True
    truth_status = _row_text(rows[0], "truth_status", "value_status").lower()
    if truth_status in {"not_available", "unavailable", "not_emitted"}:
        return True
    return False


def _count_trueish(rows: list[dict[str, str]], *names: str) -> int:
    true_tokens = {"1", "true", "yes", "ok", "pass", "passed", "succeeded", "success"}
    count = 0
    for row in rows:
        value = _row_text(row, *names).lower()
        if value in true_tokens:
            count += 1
    return count


def _count_nonempty(rows: list[dict[str, str]], *names: str) -> int:
    return sum(1 for row in rows if _row_text(row, *names))


def _mean_numeric(rows: list[dict[str, str]], *names: str) -> float | None:
    vals = [value for value in (_row_float(row, *names) for row in rows) if value is not None]
    if not vals:
        return None
    return float(sum(vals) / len(vals))


def _sum_numeric(rows: list[dict[str, str]], *names: str) -> float | None:
    vals = [value for value in (_row_float(row, *names) for row in rows) if value is not None]
    if not vals:
        return None
    return float(sum(vals))


def _distinct_join(rows: list[dict[str, str]], *names: str, limit: int = 8) -> str:
    seen: list[str] = []
    for row in rows:
        token = _row_text(row, *names)
        if token and token not in seen:
            seen.append(token)
        if len(seen) >= limit:
            break
    return "|".join(seen)


def _encode_rows_from_dicts(rows: list[dict[str, Any]]) -> bytes:
    if not rows:
        return _encode_csv([], [])
    header = list(rows[0].keys())
    return _encode_dict_rows(header, rows)


def _artifact_inventory_rows(
    source_lookup: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for art in sorted(source_lookup.values(), key=lambda item: int(item.get("artifact_id") or 0)):
        logical_path = str(art.get("logical_path") or "")
        rows.append(
            {
                "artifact_id": int(art.get("artifact_id") or 0),
                "logical_path": logical_path,
                "artifact_kind": str(art.get("artifact_kind") or ""),
                "mime_type": str(art.get("mime_type") or ""),
                "scope": logical_path.split("/", 1)[0] if "/" in logical_path else logical_path,
                "family": logical_path.split("/", 2)[1] if logical_path.count("/") >= 1 else "",
            }
        )
    return rows


def _numeric_csv_audit_counts(
    header: list[str], rows: list[dict[str, str]],
) -> tuple[int, int, int, list[str]]:
    """Compute conservative numeric/missing counts from persisted CSV text.

    A column is classified numeric only when every nonblank token parses as
    a finite or explicit nonfinite number. This avoids inventing type
    information that is not present in the DB artifact schema.
    """
    numeric_count = 0
    finite_count = 0
    missing_count = 0
    blank_columns: list[str] = []
    for column in header:
        tokens = [str(row.get(column, "") or "").strip() for row in rows]
        nonblank = [token for token in tokens if token]
        if not nonblank:
            blank_columns.append(column)
            continue
        parsed: list[float] = []
        numeric = True
        for token in nonblank:
            try:
                parsed.append(float(token))
            except (TypeError, ValueError):
                numeric = False
                break
        if not numeric:
            continue
        numeric_count += 1
        finite_count += sum(1 for value in parsed if math.isfinite(value))
        missing_count += sum(1 for token in tokens if not token)
    return numeric_count, finite_count, missing_count, blank_columns


def _db_artifact_audit_table(
    table_name: str,
    source_lookup: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    """Audit persisted DB artifacts without fabricating filesystem evidence."""
    is_csv = table_name == "all_csv_artifact_audit"
    is_image = table_name == "all_image_artifact_audit"
    if not (is_csv or is_image):
        return None
    rows: list[dict[str, Any]] = []
    for artifact in sorted(source_lookup.values(), key=lambda item: int(item.get("artifact_id") or 0)):
        artifact_id = int(artifact.get("artifact_id") or 0)
        logical_path = str(artifact.get("logical_path") or "").strip()
        kind = str(artifact.get("artifact_kind") or "").strip().lower()
        mime = str(artifact.get("mime_type") or "").strip().lower()
        if artifact_id <= 0 or not logical_path:
            continue
        if is_csv and not (kind == "table_csv" or logical_path.lower().endswith(".csv")):
            continue
        if is_image and not (
            kind.startswith("image_")
            or mime.startswith("image/")
            or logical_path.lower().endswith((".png", ".jpg", ".jpeg", ".svg"))
        ):
            continue
        try:
            payload = bytes(fetch_artifact_bytes(artifact_id))
        except Exception:
            continue
        digest = hashlib.sha256(payload).hexdigest()
        if is_csv:
            header, csv_rows = _decode_csv_dicts(payload)
            numeric_columns, finite_values, missing_values, blank_columns = _numeric_csv_audit_counts(header, csv_rows)
            rows.append({
                "run_id": run_id,
                "path": f"db://sim_artifacts/{artifact_id}",
                "relative_path": logical_path,
                "bytes": len(payload),
                "sha256": digest,
                "readable_by_readtable": int(bool(header)),
                "row_count": len(csv_rows),
                "column_count": len(header),
                "column_names_json": json.dumps(header, ensure_ascii=False),
                "numeric_column_count": numeric_columns,
                "finite_numeric_count": finite_values,
                "missing_numeric_count": missing_values,
                "all_blank_columns_json": json.dumps(blank_columns, ensure_ascii=False),
                "has_required_columns": "",
                "status": "observed" if header else "unreadable",
                "failure_code": "" if header else "csv_header_unreadable",
                "first_issue": "" if header else "persisted_csv_has_no_decodable_header",
                "required": "",
                "artifact_spec": "db_persisted_artifact_inventory",
                "required_columns_json": "[]",
                "audit_scope": "mysql_web_persisted_bytes",
            })
            continue
        width = ""
        height = ""
        fmt = ""
        readable = False
        if payload.startswith(b"\x89PNG\r\n\x1a\n") and len(payload) >= 24:
            fmt = "png"
            width = int.from_bytes(payload[16:20], "big")
            height = int.from_bytes(payload[20:24], "big")
            readable = width > 0 and height > 0
        elif b"<svg" in payload[:4096].lower():
            fmt = "svg"
            text = payload[:8192].decode("utf-8", errors="ignore")
            width_match = re.search(r"\bwidth=[\"']([0-9.]+)", text, re.IGNORECASE)
            height_match = re.search(r"\bheight=[\"']([0-9.]+)", text, re.IGNORECASE)
            width = float(width_match.group(1)) if width_match else ""
            height = float(height_match.group(1)) if height_match else ""
            readable = True
        elif payload[:2] == b"\xff\xd8":
            fmt = "jpeg"
            readable = True
        rows.append({
            "run_id": run_id,
            "path": f"db://sim_artifacts/{artifact_id}",
            "relative_path": logical_path,
            "bytes": len(payload),
            "sha256": digest,
            "format": fmt,
            "width_px": width,
            "height_px": height,
            "readable": int(readable),
            "color_or_grayscale": "not_evaluated_from_db_bytes",
            "estimated_unique_color_count": "",
            "pixel_std": "",
            "blank_or_low_information": "",
            "source_csv": "",
            "source_csv_exists": "",
            "status": "observed" if readable else "unreadable",
            "failure_code": "" if readable else "image_header_unreadable",
            "first_issue": "" if readable else "persisted_image_has_no_supported_header",
            "required": "",
            "audit_scope": "mysql_web_persisted_bytes",
        })
    if not rows:
        return None
    return {
        "data": _encode_rows_from_dicts(rows),
        "status": "specialized_db_artifact_audit",
        "note": (
            "Artifact audit is computed from exact persisted sim_artifacts bytes; "
            "unknown requirement or image-content classifications remain blank rather than inferred."
        ),
        "source_logical_path": "sim_artifacts",
        "source_row_count": len(rows),
    }


def _table_source_health(
    table_name: str,
    source_lookup: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for logical_path in _table_sources(table_name):
        _header, source_rows = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, logical_path)
        rows.append(
            {
                "contract_table": table_name,
                "source_logical_path": logical_path,
                "source_present": int(logical_path in source_lookup),
                "source_row_count": len(source_rows),
            }
        )
    return rows


def _table_placeholder_summary_status(rows: list[dict[str, str]]) -> str:
    if len(rows) != 1:
        return ""
    return _row_text(
        rows[0],
        "contract_materialization_status",
        "materialization_status",
        "status",
    )


def _specialized_live_report_table(
    table_name: str,
    source_lookup: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
    run_row: dict[str, Any] | None,
    feature_policy: dict[str, bool] | None,
) -> dict[str, Any] | None:
    run_row = dict(run_row or {})
    feature_policy = dict(feature_policy or {})
    status_payload = _json_object(run_row.get("status_json"))
    config_payload = _json_object(run_row.get("config_json"))
    raw_sources = {
        "dl_pdsch": "air_interface/csv/dl_pdsch_trials.csv",
        "ul_pusch": "air_interface/csv/ul_pusch_trials.csv",
        "pdcch": "air_interface/csv/pdcch_trials.csv",
        "pbch": "air_interface/csv/pbch_trials.csv",
        "prach": "air_interface/csv/prach_trials.csv",
        "pucch": "air_interface/csv/pucch_trials.csv",
        "srs": "air_interface/csv/srs_trials.csv",
        "trs": "air_interface/csv/trs_trials.csv",
    }
    raw_rows = {
        key: _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, logical_path)[1]
        for key, logical_path in raw_sources.items()
    }
    dl_grants = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, "packet_flow/csv/live_dl_scheduler_grants.csv")[1]
    ul_grants = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, "packet_flow/csv/live_ul_scheduler_grants.csv")[1]
    pucch_grants = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, "packet_flow/csv/live_pucch_grants.csv")[1]
    slot_trace = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, "packet_flow/csv/slot_trace.csv")[1]
    beam_probe = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, "beamforming/csv/probe_beam_mimo.csv")[1]
    energy_rows = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, "rf/csv/energy_timeline_trace.csv")[1]
    artifact_rows = _artifact_inventory_rows(source_lookup)

    artifact_audit = _db_artifact_audit_table(
        table_name, source_lookup, fetch_artifact_bytes, run_id
    )
    if artifact_audit is not None:
        return artifact_audit

    if table_name == "live_run_overview":
        rows = [{
            "run_id": run_id,
            "run_uuid": str(run_row.get("run_uuid") or ""),
            "scenario_id": str(run_row.get("scenario_id") or ""),
            "run_tag": str(run_row.get("run_tag") or ""),
            "backend": str(run_row.get("backend") or ""),
            "profile_name": str(run_row.get("profile_name") or ""),
            "status_text": str(run_row.get("status_text") or ""),
            "stage": str(status_payload.get("stage") or ""),
            "current_direction": str(status_payload.get("current_direction") or ""),
            "current_frame": status_payload.get("current_frame", ""),
            "total_frames": status_payload.get("total_frames", ""),
            "current_slot": status_payload.get("current_slot", ""),
            "total_slots": status_payload.get("total_slots", ""),
            "run_completion": status_payload.get("run_completion", ""),
            "active_ue_count": status_payload.get("active_ue_count", ""),
            "total_users": status_payload.get("total_users", ""),
            "dl_trial_rows": status_payload.get("dl_trial_rows", len(raw_rows["dl_pdsch"])),
            "ul_trial_rows": status_payload.get("ul_trial_rows", len(raw_rows["ul_pusch"])),
            "notes": str(status_payload.get("notes") or ""),
            "source_artifact": "sim_runs.status_json",
        }]
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_run_overview",
            "note": "Run overview derived from sim_runs metadata and live raw trial counters.",
            "source_logical_path": "sim_runs.status_json",
            "source_row_count": 1,
        }
    if table_name == "live_scenario_overview":
        profile_name = str(run_row.get("profile_name") or "").strip().lower()
        component_slot_path = (
            "random_access.num_slots" if profile_name in {"prach_detection", "prach_validation"} else ""
        )
        total_slot_paths = [
            "run.totalSlots",
            "run_control.total_slots",
            "canonical_control.run.total_slots",
            "simulation.n_slots",
        ]
        if component_slot_path:
            # A PRACH component campaign advances its own configured occasion
            # window.  Generic simulation defaults are inherited but are not
            # the executed time base for this runner.
            total_slot_paths.insert(0, component_slot_path)
        total_slots = status_payload.get("total_slots", "")
        if total_slots in {None, ""}:
            total_slots = _first_config_value(config_payload, *total_slot_paths)

        num_frame_paths = [
            "run.numFrames",
            "run_control.num_frames",
            "canonical_control.run.num_frames",
            "simulation.n_frames",
        ]
        # For component-specific slot windows, derive the executed frame count
        # below rather than publishing an unrelated inherited simulation
        # default as runtime truth.
        num_frames = "" if component_slot_path else _first_config_value(
            config_payload, *num_frame_paths
        )
        if num_frames == "":
            slots_per_frame = _first_config_value(
                config_payload,
                "frame_timing.slots_per_frame",
                "frame.slots_per_frame",
                "canonical_control.frame.slots_per_frame",
            )
            if slots_per_frame == "":
                scs_value = _first_config_value(
                    config_payload,
                    "carrier.scsKHz",
                    "frame.scs_khz",
                    "random_access.carrier_scs_khz",
                    "canonical_control.radio.scs_khz",
                )
                try:
                    scs_khz = float(scs_value)
                    mu = round(math.log2(scs_khz / 15.0))
                    if mu >= 0 and math.isclose(scs_khz, 15.0 * (2.0 ** mu), rel_tol=0.0, abs_tol=1e-9):
                        slots_per_frame = 10 * (2 ** mu)
                except (TypeError, ValueError, OverflowError):
                    slots_per_frame = ""
            try:
                if float(total_slots) > 0 and float(slots_per_frame) > 0:
                    num_frames = float(total_slots) / float(slots_per_frame)
                    if float(num_frames).is_integer():
                        num_frames = int(num_frames)
            except (TypeError, ValueError, ZeroDivisionError):
                pass
        rows = [{
            "run_id": run_id,
            "scenario_id": str(run_row.get("scenario_id") or ""),
            "layout_type": _first_config_value(
                config_payload, "scenario.layout.type", "deployment_topology.layout_type"
            ),
            "num_sites": _first_config_value(
                config_payload, "scenario.layout.nSites", "deployment_topology.num_sites"
            ),
            "sectors_per_site": _first_config_value(
                config_payload,
                "scenario.layout.nSectorsPerSite",
                "deployment_topology.sectors_per_site",
            ),
            "intersite_distance_m": _first_config_value(
                config_payload,
                "scenario.layout.interSiteDistance_m",
                "deployment_topology.inter_site_distance_m",
            ),
            "wrap_around": _first_config_value(
                config_payload,
                "scenario.layout.wrapAround",
                "deployment_topology.wrap_around",
            ),
            "configured_ue_count": _first_config_value(
                config_payload, "scenario.ue.nUE", "deployment_topology.num_ues"
            ),
            "center_frequency_hz": _first_config_value(
                config_payload,
                "carrier.centerFrequencyHz",
                "global_radio_scope.carrier_frequency_hz",
                "frequency.center_frequency_hz",
                "canonical_control.radio.center_frequency_hz",
            ),
            "bandwidth_hz": _first_config_value(
                config_payload,
                "carrier.bandwidthHz",
                "global_radio_scope.channel_bandwidth_hz",
                "frequency.bandwidth_hz",
                "canonical_control.radio.bandwidth_hz",
            ),
            "scs_khz": _first_config_value(
                config_payload,
                "carrier.scsKHz",
                "frame.scs_khz",
                "canonical_control.radio.scs_khz",
            ),
            "n_rb": _first_config_value(
                config_payload,
                "carrier.nRB",
                "resource_grid.num_rbs",
                "canonical_control.reference_signals.num_rb",
            ),
            "duplex_mode": _first_config_value(
                config_payload,
                "carrier.duplexMode",
                "global_radio_scope.duplex_mode",
                "frequency.duplex_mode",
                "canonical_control.radio.duplex_mode",
            ),
            "num_frames": num_frames,
            "total_slots": total_slots,
            "strict_mode": _first_config_value(
                config_payload,
                "run.strictMode",
                "logging.strict_validation",
                "validation.strict_after_run_artifact_audit",
            ),
            "honesty_mode": _first_config_value(
                config_payload,
                "run.honestyMode",
                "scenario.honesty_mode",
                "canonical_control.launch.honesty_mode",
            ),
            "source_artifact": "sim_runs.config_json:versioned_multi_schema_adapter",
        }]
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_scenario_overview",
            "note": "Scenario overview derived from the resolved run configuration stored in sim_runs.",
            "source_logical_path": "sim_runs.config_json",
            "source_row_count": 1,
        }
    if table_name == "live_trial_overview":
        rows: list[dict[str, Any]] = []
        for family, logical_path in raw_sources.items():
            family_rows = raw_rows.get(family, [])
            if not family_rows:
                continue
            rows.append({
                "run_id": run_id,
                "trial_family": family,
                "source_artifact": logical_path,
                "observed_rows": len(family_rows),
                "success_count": _count_trueish(family_rows, "CRCPass", "CombinedDecodeOK", "CurrentDecodeOK", "Detected", "DetectedFlag"),
                "failure_count": len(family_rows) - _count_trueish(family_rows, "CRCPass", "CombinedDecodeOK", "CurrentDecodeOK", "Detected", "DetectedFlag"),
                "mean_measured_sinr_db": _mean_numeric(family_rows, "PostEqSINR_dB", "MeasuredTrialSINR_dB", "MeasuredSINR_dB"),
                "mean_cqi": _mean_numeric(family_rows, "WidebandCQI"),
                "mean_mcs": _mean_numeric(family_rows, "MCS", "CQIDerivedMCS"),
                "modulation_set": _distinct_join(family_rows, "Modulation"),
            })
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_trial_overview",
                "note": "Trial-family overview aggregated from persisted waveform/control trial artifacts.",
                "source_logical_path": "|".join(logical_path for logical_path, family_rows in ((raw_sources[key], raw_rows[key]) for key in raw_sources) if family_rows),
                "source_row_count": sum(int(row["observed_rows"]) for row in rows),
            }
    if table_name == "live_pdsch_code_block_table" and raw_rows["dl_pdsch"]:
        rows = [{
            "run_id": run_id,
            "direction": "DL",
            "frame": _row_text(row, "Frame", "SFN"),
            "slot": _row_text(row, "Slot"),
            "ue_id": _row_text(row, "UEID", "UEIndex", "RNTI"),
            "rnti": _row_text(row, "RNTI"),
            "cell_id": _row_text(row, "BaseStationID", "ServingCell", "CellID"),
            "harq_process_id": _row_text(row, "HARQProcessId", "HARQProcess", "HarqID"),
            "rv": _row_text(row, "RV", "HARQRV"),
            "tb_size_bits": _row_text(row, "TBSize_bits", "TBSBits"),
            "tb_crc_length_bits": _row_text(row, "TBCRCLength_bits"),
            "tb_length_with_crc_bits": _row_text(row, "TBLengthWithCRC_bits"),
            "num_code_blocks": _row_text(row, "NumCodeBlocks", "CodeBlockCount"),
            "code_block_count": _row_text(row, "CodeBlockCount", "NumCodeBlocks"),
            "code_block_length_bits": _row_text(row, "CodeBlockLength_bits"),
            "segmentation_occurred": _row_text(row, "SegmentationOccurred"),
            "segmentation_padding_bits": _row_text(row, "SegmentationPaddingBits"),
            "base_graph": _row_text(row, "BaseGraph"),
            "encoded_bits": _row_text(row, "EncodedBits"),
            "rate_matched_bits": _row_text(row, "RateMatchedBits"),
            "rate_match_puncture_bits": _row_text(row, "RateMatchPunctureBits"),
            "rate_match_repetition_bits": _row_text(row, "RateMatchRepetitionBits"),
            "code_block_errors": _row_text(row, "CodeBlockErrors"),
            "code_block_bler": _row_text(row, "CodeBlockBLER"),
            "cbg_errors": _row_text(row, "CBGErrors"),
            "cbg_count": _row_text(row, "CBGCount"),
            "cbg_bler": _row_text(row, "CBGBLER"),
            "crc_pass": _row_text(row, "CRCPass", "CombinedDecodeOK"),
            "value_source": raw_sources["dl_pdsch"],
            "value_status": "runtime_trial_code_block_segmentation_evidence",
        } for row in raw_rows["dl_pdsch"][:2048]]
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_pdsch_code_block_table",
            "note": "PDSCH code-block table is derived from actual DL PDSCH trial rows; no grant-level TBS is synthesized.",
            "source_logical_path": raw_sources["dl_pdsch"],
            "source_row_count": len(rows),
        }
    if table_name == "live_impairment_table":
        selected_sources = [
            (raw_sources["dl_pdsch"], raw_rows["dl_pdsch"]),
            (raw_sources["ul_pusch"], raw_rows["ul_pusch"]),
            (raw_sources["srs"], raw_rows["srs"]),
            (raw_sources["trs"], raw_rows["trs"]),
            (raw_sources["prach"], raw_rows["prach"]),
        ]
        rows: list[dict[str, Any]] = []
        for logical_path, source_rows in selected_sources:
            for row in source_rows[:1024]:
                rows.append({
                    "run_id": run_id,
                    "direction": _row_text(row, "Direction"),
                    "frame": _row_text(row, "Frame", "SFN"),
                    "slot": _row_text(row, "Slot"),
                    "ue_id": _row_text(row, "UEID", "UEIndex", "RNTI"),
                    "cell_id": _row_text(row, "BaseStationID", "ServingCell", "CellID"),
                    "channel_model": _row_text(row, "ChannelModel"),
                    "pathloss_db": _row_text(row, "AppliedPathloss_dB", "Pathloss_dB"),
                    "shadowing_db": _row_text(row, "AppliedShadowFading_dB", "ShadowFading_dB"),
                    "o2i_loss_db": _row_text(row, "AppliedO2I_dB", "O2ILoss_dB", "O2I_dB"),
                    "large_scale_gain_db": _row_text(row, "AppliedLargeScaleGain_dB"),
                    "large_scale_gain_source": _row_text(row, "AppliedLargeScaleGainSource"),
                    "injected_cfo_hz": _row_text(row, "InjectedCFO_Hz"),
                    "estimated_cfo_hz": _row_text(row, "EstimatedCFO_Hz"),
                    "true_cfo_hz": _row_text(row, "TrueCFO_Hz"),
                    "cfo_error_hz": _row_text(row, "CFOError_Hz"),
                    "carrier_phase_offset_deg": _row_text(row, "InjectedCarrierPhaseOffset_deg"),
                    "carrier_phase_offset_applied": _row_text(row, "CarrierPhaseOffsetApplied"),
                    "carrier_phase_offset_status": _row_text(row, "CarrierPhaseOffsetExecutionStatus"),
                    "phase_tracking_error_deg": _row_text(row, "PhaseTrackingError_deg"),
                    "phase_noise_status": _row_text(row, "PhaseNoiseExecutionStatus"),
                    "injected_timing_offset_samples": _row_text(row, "InjectedTimingOffset_samples"),
                    "timing_error_samples": _row_text(row, "TimingError_samples"),
                    "doppler_hz": _row_text(row, "DopplerHz", "InjectedDoppler_Hz"),
                    "estimated_doppler_hz": _row_text(row, "EstimatedDopplerHz"),
                    "doppler_error_hz": _row_text(row, "DopplerError_Hz"),
                    "iq_imbalance_configured": _row_text(row, "IQImbalanceConfigured"),
                    "iq_imbalance_applied": _row_text(row, "IQImbalanceApplied"),
                    "iq_gain_imbalance_db": _row_text(row, "ConfiguredIQGainImbalance_dB"),
                    "iq_phase_imbalance_deg": _row_text(row, "ConfiguredIQPhaseImbalance_deg"),
                    "iq_measurement_status": _row_text(row, "IQImbalanceMeasurementStatus"),
                    "interference_mode": _row_text(row, "InterferenceMode"),
                    "residual_interference_power_db": _row_text(row, "ResidualInterferencePower_dB"),
                    "source_artifact": logical_path,
                    "value_status": "runtime_waveform_impairment_evidence",
                })
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_impairment_table",
                "note": "Impairment table is derived from persisted waveform/control trial evidence, including RF offsets, pathloss/O2I, Doppler, timing, IQ, and interference fields when measured.",
                "source_logical_path": "|".join(path for path, source_rows in selected_sources if source_rows),
                "source_row_count": len(rows),
            }
    if table_name == "live_beam_selection_table":
        selected_sources = [
            ("beamforming/csv/probe_beam_mimo.csv", beam_probe),
            (raw_sources["dl_pdsch"], raw_rows["dl_pdsch"]),
            (raw_sources["ul_pusch"], raw_rows["ul_pusch"]),
        ]
        rows: list[dict[str, Any]] = []
        tci_cfg = config_payload.get("tci", {}) if isinstance(config_payload.get("tci"), dict) else {}
        qcl_cfg = config_payload.get("qcl", {}) if isinstance(config_payload.get("qcl"), dict) else {}
        near_field_cfg = config_payload.get("near_field", {}) if isinstance(config_payload.get("near_field"), dict) else {}
        for logical_path, source_rows in selected_sources:
            for row in source_rows[:1024]:
                qcl_accuracy = _row_text(row, "QCLAccuracy")
                tci_value = _row_text(row, "TCIState", "TCIStateID") or str(tci_cfg.get("state_id") or "")
                rows.append({
                    "run_id": run_id,
                    "direction": _row_text(row, "Direction"),
                    "frame": _row_text(row, "Frame", "SFN"),
                    "slot": _row_text(row, "Slot"),
                    "ue_id": _row_text(row, "UEID", "UEIndex", "RNTI"),
                    "cell_id": _row_text(row, "BaseStationID", "ServingCell", "CellID"),
                    "selected_beam_index": _row_text(row, "SelectedBeamIndex"),
                    "best_beam_index": _row_text(row, "BestBeamIndex"),
                    "beam_hit": _row_text(row, "BeamHit"),
                    "topk_beam_hit": _row_text(row, "TopKBeamHit"),
                    "beam_candidate_count": _row_text(row, "BeamCandidateCount"),
                    "selected_beam_gain_db": _row_text(row, "SelectedBeamGain_dB"),
                    "best_beam_gain_db": _row_text(row, "BestBeamGain_dB"),
                    "beam_gain_gap_db": _row_text(row, "BeamGainGap_dB"),
                    "beam_selection_strategy": _row_text(row, "BeamSelectionStrategy", "ConfiguredBeamSelectionStrategy"),
                    "applied_beam_index_set": _row_text(row, "AppliedBeamIndexSet"),
                    "beamforming_applied": _row_text(row, "BeamformingApplied"),
                    "precoding_active": _row_text(row, "PrecodingActive"),
                    "precoder_source": _row_text(row, "PrecoderSource", "AppliedPrecoderSource"),
                    "precoding_mode": _row_text(row, "PrecodingMode"),
                    "applied_precoder_pmi": _row_text(row, "AppliedPrecoderPMI"),
                    "applied_precoder_pmi_type": _row_text(row, "AppliedPrecoderPMIType"),
                    "applied_precoder_codebook_mode": _row_text(row, "AppliedPrecoderCodebookMode"),
                    "qcl_accuracy": qcl_accuracy,
                    "qcl_type": _row_text(row, "QCLType", "QCLTypes") or str(qcl_cfg.get("type") or qcl_cfg.get("types") or ""),
                    "qcl_source_rs": _row_text(row, "QCLSourceRS") or str(qcl_cfg.get("source_rs") or ""),
                    "qcl_status": _row_text(row, "QCLStatus") or ("runtime_qcl_accuracy_measured" if qcl_accuracy else "not_materialized_in_active_truth_path"),
                    "tci_state_id": tci_value,
                    "unified_tci_state_id": _row_text(row, "UnifiedTCIStateID") or str(tci_cfg.get("unified_state_id") or ""),
                    "tci_validity_timer_slots": _row_text(row, "TCIValidityTimerSlots") or str(tci_cfg.get("validity_timer_slots") or ""),
                    "tci_status": _row_text(row, "TCIStatus") or ("configured_or_runtime_field_present" if (tci_cfg or tci_value) else "not_materialized_in_active_truth_path"),
                    "fraunhofer_boundary_m": _row_text(row, "FraunhoferBoundary_m") or str(near_field_cfg.get("fraunhofer_boundary_m") or ""),
                    "near_field_focal_point_m": _row_text(row, "NearFieldFocalPoint_m", "FocalPoint_m") or str(near_field_cfg.get("focal_point_m") or ""),
                    "near_field_status": _row_text(row, "NearFieldStatus") or ("configured" if near_field_cfg else "not_materialized_in_active_truth_path"),
                    "source_artifact": logical_path,
                    "value_status": "runtime_beamforming_and_precoder_evidence",
                })
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_beam_selection_table",
                "note": "Beam table is derived from runtime beam/precoder rows and includes explicit TCI/QCL/near-field status fields without fabricating unavailable behavior.",
                "source_logical_path": "|".join(path for path, source_rows in selected_sources if source_rows),
                "source_row_count": len(rows),
            }
    if table_name in {"live_case_status", "live_required_vs_optional_case_status", "live_truth_policy_status"}:
        block_paths = {
            "pdcch": raw_sources["pdcch"],
            "ssb_pbch": raw_sources["pbch"],
            "prach": raw_sources["prach"],
            "pdsch": raw_sources["dl_pdsch"],
            "pusch": raw_sources["ul_pusch"],
            "pucch": raw_sources["pucch"],
            "srs": raw_sources["srs"],
            "trs": raw_sources["trs"],
            "beamforming": "beamforming/csv/probe_beam_mimo.csv",
            "energy": "rf/csv/probe_rf_energy.csv",
        }
        rows: list[dict[str, Any]] = []
        for block_name, logical_path in block_paths.items():
            _header, block_rows = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, logical_path)
            rows.append({
                "run_id": run_id,
                "block_name": block_name,
                "required_flag": 1,
                "policy_state": "required",
                "status": "generated" if block_rows else "missing",
                "observed_rows": len(block_rows),
                "source_artifact": logical_path,
                "placeholder_rows": _count_trueish(block_rows, "PlaceholderFlag"),
                "fallback_rows": _count_trueish(block_rows, "FallbackFlag"),
            })
        if table_name == "live_required_vs_optional_case_status":
            for feature_name, enabled in sorted(feature_policy.items()):
                rows.append({
                    "run_id": run_id,
                    "block_name": feature_name,
                    "required_flag": 0,
                    "policy_state": "enabled" if enabled else "policy_disabled",
                    "status": "policy_disabled" if not enabled else "not_observed",
                    "observed_rows": 0,
                    "source_artifact": "feature_policy",
                    "placeholder_rows": 0,
                    "fallback_rows": 0,
                })
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_case_status",
                "note": "Case and truth-policy rows derived from direct artifact presence plus runtime placeholder/fallback flags.",
                "source_logical_path": "sim_runs.status_json",
                "source_row_count": len(rows),
            }
    if table_name in {"live_cell_table", "live_per_cell_context"}:
        rows_by_cell: dict[tuple[str, str], dict[str, Any]] = {}
        for direction, grant_rows in (("DL", dl_grants), ("UL", ul_grants)):
            for row in grant_rows:
                cell_id = _row_text(row, "ServingCell", "CellID") or "unknown"
                bs_id = _row_text(row, "BaseStationID", "BSID") or "unknown"
                key = (cell_id, bs_id)
                entry = rows_by_cell.setdefault(key, {"run_id": run_id, "cell_id": cell_id, "bs_id": bs_id, "dl_grant_count": 0, "ul_grant_count": 0, "ue_set": set(), "cqi_sum": 0.0, "cqi_count": 0, "tbs_sum": 0.0, "tbs_count": 0})
                entry["ue_set"].add(_row_text(row, "UEID", "UEIndex", "RNTI"))
                if direction == "DL":
                    entry["dl_grant_count"] += 1
                else:
                    entry["ul_grant_count"] += 1
                cqi = _row_float(row, "CQIUsed")
                if cqi is not None:
                    entry["cqi_sum"] += cqi
                    entry["cqi_count"] += 1
                tbs = _row_float(row, "TBSBits")
                if tbs is not None:
                    entry["tbs_sum"] += tbs
                    entry["tbs_count"] += 1
        rows = [{
            "run_id": entry["run_id"],
            "cell_id": entry["cell_id"],
            "bs_id": entry["bs_id"],
            "dl_grant_count": entry["dl_grant_count"],
            "ul_grant_count": entry["ul_grant_count"],
            "unique_ue_count": len(entry["ue_set"]),
            "mean_cqi": (entry["cqi_sum"] / entry["cqi_count"]) if entry["cqi_count"] else "",
            "mean_tbs_bits": (entry["tbs_sum"] / entry["tbs_count"]) if entry["tbs_count"] else "",
            "source_artifact": "packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv",
        } for entry in rows_by_cell.values()]
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_cell_summary",
                "note": "Per-cell context derived from persisted DL and UL scheduler grants.",
                "source_logical_path": "packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv",
                "source_row_count": len(dl_grants) + len(ul_grants),
            }
    if table_name == "live_link_table":
        rows: list[dict[str, Any]] = []
        for family in ("dl_pdsch", "ul_pusch", "pdcch", "pbch"):
            logical_path = raw_sources[family]
            for row in raw_rows.get(family, [])[:512]:
                rows.append({
                    "run_id": run_id,
                    "direction": _row_text(row, "Direction"),
                    "ue_id": _row_text(row, "UEID", "UEIndex", "RNTI"),
                    "cell_id": _row_text(row, "ServingCell", "CellID", "BaseStationID"),
                    "frame": _row_text(row, "Frame"),
                    "slot": _row_text(row, "Slot"),
                    "measured_sinr_db": _row_text(row, "PostEqSINR_dB", "MeasuredTrialSINR_dB", "MeasuredSINR_dB"),
                    "wideband_cqi": _row_text(row, "WidebandCQI"),
                    "mcs": _row_text(row, "MCS", "CQIDerivedMCS"),
                    "tb_size_bits": _row_text(row, "TBSize_bits"),
                    "channel_gain_db": _row_text(row, "ChannelGain_dB"),
                    "source_artifact": logical_path,
                })
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_link_table",
                "note": "Per-link rows emitted directly from truthful trial artifacts.",
                "source_logical_path": "|".join(raw_sources[family] for family in ("dl_pdsch", "ul_pusch", "pdcch", "pbch")),
                "source_row_count": len(rows),
            }
    if table_name == "live_measurement_table":
        # Measurement evidence belongs to the receiver rows that produced it.
        # Preserve configured, applied, and receiver-measured quantities as
        # separate fields so no configured value is relabeled as measured.
        selected_sources = [
            (raw_sources["dl_pdsch"], raw_rows["dl_pdsch"]),
            (raw_sources["ul_pusch"], raw_rows["ul_pusch"]),
        ]
        rows: list[dict[str, Any]] = []
        for logical_path, source_rows in selected_sources:
            for row in source_rows[:4096]:
                rows.append({
                    "run_id": run_id,
                    "direction": _row_text(row, "Direction"),
                    "frame": _row_text(row, "Frame", "SFN"),
                    "slot": _row_text(row, "Slot"),
                    "ue_id": _row_text(row, "UEID", "UEIndex", "RNTI"),
                    "cell_id": _row_text(row, "BaseStationID", "ServingCell", "CellID"),
                    "configured_snr_db": _row_text(row, "ConfiguredSNR_dB", "SNR_dB"),
                    "applied_awgn_snr_db": _row_text(row, "AppliedAWGNSNR_dB", "AppliedNoiseSNR_dB"),
                    "posteq_sinr_db": _row_text(row, "PostEqSINR_dB", "MeasuredTrialSINR_dB", "MeasuredSINR_dB"),
                    "posteq_sinr_source": _row_text(row, "PostEqSINRSource", "MeasuredTrialSINRSource", "SINRSource"),
                    "posteq_sinr_status": _row_text(row, "PostEqSINRValueStatus", "MeasuredTrialSINRValueStatus", "SINRValueStatus"),
                    "receiver_hest_sinr_db": _row_text(row, "ReceiverHestSINR_dB"),
                    "receiver_hest_sinr_source": _row_text(row, "ReceiverHestSINRSource"),
                    "serving_rsrp_dbm": _row_text(row, "ServingRSRP_dBm"),
                    "csi_rsrp_dbm": _row_text(row, "CSI_RSRP_dBm"),
                    "csi_rsrp_relative_db": _row_text(row, "CSI_RSRP_dB"),
                    "thermal_noise_power_dbm": _row_text(row, "ThermalNoisePower_dBm"),
                    "noise_variance": _row_text(row, "NoiseVariance", "LLRNoiseVariance"),
                    "wideband_cqi": _row_text(row, "WidebandCQI"),
                    "pmi": _row_text(row, "PMI", "AppliedPrecoderPMI"),
                    "ri": _row_text(row, "RankIndicator", "Rank", "Layers"),
                    "cri": _row_text(row, "CRI"),
                    "mcs": _row_text(row, "MCS", "MCSIndex"),
                    "modulation": _row_text(row, "Modulation"),
                    "target_code_rate": _row_text(row, "TargetCodeRate"),
                    "channel_model": _row_text(row, "ChannelModel", "ChannelModelApplied"),
                    "channel_estimate_attempted": _row_text(row, "ChannelEstimateAttempted"),
                    "channel_estimate_available": _row_text(row, "ChannelEstimateAvailable"),
                    "channel_estimate_source": _row_text(row, "ChannelEstimateSource"),
                    "nmse_db": _row_text(row, "NMSE_dB", "TrueChannelNMSE_dB"),
                    "crc_pass": _row_text(row, "CRCPass", "CombinedDecodeOK"),
                    "source_artifact": logical_path,
                    "value_status": "runtime_receiver_measurement_evidence",
                })
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_measurement_table",
                "note": "Measurement rows preserve configured/applied SNR and receiver-derived SINR, RSRP, CQI, channel-estimation, and CRC fields from the same PDSCH/PUSCH trials.",
                "source_logical_path": "|".join(path for path, source_rows in selected_sources if source_rows),
                "source_row_count": len(rows),
            }
    if table_name == "live_path_geometry_table":
        scenario_cfg = _json_object(config_payload.get("scenario"))
        layout_cfg = _json_object(scenario_cfg.get("layout"))
        ue_cfg = _json_object(scenario_cfg.get("ue"))
        dist_cfg = _json_object(ue_cfg.get("distribution"))
        rows = [
            {"run_id": run_id, "entity_type": "layout", "layout_type": str(layout_cfg.get("type") or ""), "n_sites": layout_cfg.get("nSites", ""), "sectors_per_site": layout_cfg.get("nSectorsPerSite", ""), "intersite_distance_m": layout_cfg.get("interSiteDistance_m", ""), "wrap_around": layout_cfg.get("wrapAround", ""), "source_artifact": "sim_runs.config_json"},
            {"run_id": run_id, "entity_type": "ue_distribution", "layout_type": str(dist_cfg.get("type") or ""), "n_sites": ue_cfg.get("nUE", ""), "sectors_per_site": dist_cfg.get("indoorFraction", ""), "intersite_distance_m": dist_cfg.get("minBSdist_m", ""), "wrap_around": dist_cfg.get("maxBSdist_m", ""), "source_artifact": "sim_runs.config_json"},
        ]
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_geometry_summary",
            "note": "Geometry summary derived from the resolved scenario configuration because explicit topology coordinate tables were not published for this running web launch.",
            "source_logical_path": "sim_runs.config_json",
            "source_row_count": len(rows),
        }
    if table_name in {"live_prb_allocation_snapshot", "live_re_allocation_snapshot"}:
        direct_path = "reports/csv/live_re_allocation_snapshot.csv" if table_name == "live_re_allocation_snapshot" else "packet_flow/csv/live_prb_allocation.csv"
        direct_header, direct_rows = _artifact_rows_by_path(source_lookup, fetch_artifact_bytes, direct_path)
        if direct_header and direct_rows:
            return {
                "data": _encode_rows_from_dicts(direct_rows),
                "status": "direct_runtime_allocation_snapshot",
                "note": "Allocation snapshot emitted directly by the MATLAB runtime/export path.",
                "source_logical_path": direct_path,
                "source_row_count": len(direct_rows),
            }
        rows: list[dict[str, Any]] = []
        for direction, grant_rows in (("DL", dl_grants), ("UL", ul_grants)):
            for row in grant_rows:
                prb_count = _row_float(row, "PRBCount", "AllocatedPRBCount")
                num_symbols = _row_float(row, "NumSymbols")
                rows.append({
                    "run_id": run_id,
                    "direction": direction,
                    "frame": _row_text(row, "Frame", "SFN"),
                    "slot": _row_text(row, "Slot"),
                    "ue_id": _row_text(row, "UEID", "UEIndex", "RNTI"),
                    "cell_id": _row_text(row, "ServingCell"),
                    "prb_start": _row_text(row, "PRBStart"),
                    "prb_count": prb_count if prb_count is not None else "",
                    "symbol_start": _row_text(row, "SymbolStart"),
                    "num_symbols": num_symbols if num_symbols is not None else "",
                    "derived_re_count": (prb_count * num_symbols * 12.0) if prb_count is not None and num_symbols is not None else "",
                    "source_artifact": "packet_flow/csv/live_dl_scheduler_grants.csv" if direction == "DL" else "packet_flow/csv/live_ul_scheduler_grants.csv",
                })
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_allocation_snapshot",
                "note": "Allocation snapshots derived from truthful scheduler grant rows.",
                "source_logical_path": "packet_flow/csv/live_dl_scheduler_grants.csv|packet_flow/csv/live_ul_scheduler_grants.csv",
                "source_row_count": len(rows),
            }
    if table_name in {"live_mac_pdu_summary", "live_mac_ce_state", "live_pusch_rx_summary", "live_llr_summary", "live_decoder_summary", "live_channel_realization_table", "live_interference_table", "live_tracking_table"}:
        if table_name == "live_mac_ce_state":
            rows = [{
                "run_id": run_id,
                "direction": _row_text(row, "Direction", "FeedbackForDirection"),
                "ue_id": _row_text(row, "UEID", "UEIndex", "RNTI"),
                "frame": _row_text(row, "Frame"),
                "slot": _row_text(row, "Slot"),
                "uci_type": _row_text(row, "UCIType"),
                "expected_ack": _row_text(row, "ExpectedAck"),
                "observed_ack": _row_text(row, "ObservedAck"),
                "pucch_decode_ok": _row_text(row, "PUCCHDecodeOk"),
                "source_artifact": "packet_flow/csv/live_pucch_grants.csv",
            } for row in pucch_grants]
            if rows:
                return {
                    "data": _encode_rows_from_dicts(rows),
                    "status": "specialized_runtime_mac_ce_state",
                    "note": "MAC control-element state derived from persisted PUCCH grant and UCI observations.",
                    "source_logical_path": "packet_flow/csv/live_pucch_grants.csv",
                    "source_row_count": len(rows),
                }
        selected_sources: list[tuple[str, list[dict[str, str]]]] = []
        if table_name == "live_mac_pdu_summary":
            selected_sources = [(raw_sources["dl_pdsch"], raw_rows["dl_pdsch"]), (raw_sources["ul_pusch"], raw_rows["ul_pusch"])]
        elif table_name == "live_pusch_rx_summary":
            selected_sources = [(raw_sources["ul_pusch"], raw_rows["ul_pusch"])]
        elif table_name == "live_llr_summary":
            selected_sources = [(raw_sources["dl_pdsch"], raw_rows["dl_pdsch"]), (raw_sources["ul_pusch"], raw_rows["ul_pusch"])]
        elif table_name == "live_decoder_summary":
            selected_sources = [(raw_sources["dl_pdsch"], raw_rows["dl_pdsch"]), (raw_sources["ul_pusch"], raw_rows["ul_pusch"]), (raw_sources["pdcch"], raw_rows["pdcch"]), (raw_sources["pbch"], raw_rows["pbch"])]
        elif table_name == "live_channel_realization_table":
            selected_sources = [(logical_path, raw_rows[key]) for key, logical_path in raw_sources.items()]
        elif table_name == "live_interference_table":
            selected_sources = [(raw_sources["dl_pdsch"], raw_rows["dl_pdsch"]), (raw_sources["ul_pusch"], raw_rows["ul_pusch"]), (raw_sources["pdcch"], raw_rows["pdcch"]), (raw_sources["pbch"], raw_rows["pbch"])]
        elif table_name == "live_tracking_table":
            selected_sources = [(raw_sources["dl_pdsch"], raw_rows["dl_pdsch"]), (raw_sources["ul_pusch"], raw_rows["ul_pusch"]), (raw_sources["trs"], raw_rows["trs"])]
        rows: list[dict[str, Any]] = []
        for logical_path, source_rows in selected_sources:
            for row in source_rows[:512]:
                out_row = {
                    "run_id": run_id,
                    "direction": _row_text(row, "Direction"),
                    "ue_id": _row_text(row, "UEID", "UEIndex", "RNTI"),
                    "frame": _row_text(row, "Frame"),
                    "slot": _row_text(row, "Slot"),
                    "source_artifact": logical_path,
                }
                if table_name in {"live_mac_pdu_summary", "live_pusch_rx_summary"}:
                    out_row.update({
                        "tb_size_bits": _row_text(row, "TBSize_bits"),
                        "mcs": _row_text(row, "MCS", "CQIDerivedMCS"),
                        "modulation": _row_text(row, "Modulation", "CQIDerivedModulation"),
                        "crc_pass": _row_text(row, "CRCPass", "CombinedDecodeOK", "CurrentDecodeOK"),
                        "goodput_mbps": _row_text(row, "Goodput_Mbps"),
                    })
                elif table_name == "live_llr_summary":
                    out_row.update({
                        "llr_mean_abs": _row_text(row, "LLRMeanAbs"),
                        "llr_std_abs": _row_text(row, "LLRStdAbs"),
                        "llr_imbalance": _row_text(row, "LLRImbalance"),
                        "decoder_iterations": _row_text(row, "DecoderIterations"),
                    })
                elif table_name == "live_decoder_summary":
                    out_row.update({
                        "decoder_iterations": _row_text(row, "DecoderIterations"),
                        "crc_pass": _row_text(row, "CRCPass", "CombinedDecodeOK", "CurrentDecodeOK"),
                        "codeblock_bler": _row_text(row, "CodeBlockBLER"),
                        "cbg_bler": _row_text(row, "CBGBLER"),
                    })
                elif table_name == "live_channel_realization_table":
                    out_row.update({
                        "channel_model": _row_text(row, "ChannelModel"),
                        "channel_gain_db": _row_text(row, "ChannelGain_dB"),
                        "applied_pathloss_db": _row_text(row, "AppliedPathloss_dB"),
                        "applied_shadow_fading_db": _row_text(row, "AppliedShadowFading_dB"),
                        "doppler_hz": _row_text(row, "DopplerHz"),
                    })
                elif table_name == "live_interference_table":
                    out_row.update({
                        "interference_mode": _row_text(row, "InterferenceMode"),
                        "interference_contributor_count": _row_text(row, "InterferenceContributorCount"),
                        "interference_rx_power_dbm": _row_text(row, "InterferenceAggregatedRxPower_dBm"),
                        "residual_interference_power_db": _row_text(row, "ResidualInterferencePower_dB"),
                        "interference_power_source": _row_text(row, "InterferencePowerSource"),
                    })
                elif table_name == "live_tracking_table":
                    out_row.update({
                        "estimated_cfo_hz": _row_text(row, "EstimatedCFO_Hz"),
                        "residual_cfo_post_correction_hz": _row_text(row, "ResidualCFO_PostCorrection_Hz"),
                        "true_cfo_hz": _row_text(row, "TrueCFO_Hz"),
                        "estimated_timing_offset_samples": _row_text(row, "EstimatedTimingOffset_PreCorrection_samples", "TimingOffset_samples"),
                        "residual_timing_error_samples": _row_text(row, "ResidualTimingError_PostCorrection_samples"),
                        "true_timing_offset_samples": _row_text(row, "TrueTimingOffset_samples"),
                    })
                rows.append(out_row)
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_signal_summary",
                "note": "Signal and decoder summaries derived directly from persisted truthful waveform trial exports.",
                "source_logical_path": "|".join(logical_path for logical_path, source_rows in selected_sources if source_rows),
                "source_row_count": len(rows),
            }
    if table_name in {"live_precoder_table", "live_combiner_table", "live_mimo_state_table", "live_user_grouping_table"} and beam_probe:
        rows: list[dict[str, Any]] = []
        for row in beam_probe[:1027]:
            out_row = {
                "run_id": run_id,
                "direction": _row_text(row, "Direction"),
                "ue_id": _row_text(row, "UEIndex", "RNTI"),
                "frame": _row_text(row, "Frame"),
                "slot": _row_text(row, "Slot"),
                "source_artifact": "beamforming/csv/probe_beam_mimo.csv",
            }
            if table_name == "live_precoder_table":
                out_row.update({
                    "precoder_source": _row_text(row, "PrecoderSource"),
                    "precoding_mode": _row_text(row, "PrecodingMode"),
                    "application_stage": _row_text(row, "PrecodingApplicationStage"),
                    "applied_precoder_pmi": _row_text(row, "AppliedPrecoderPMI"),
                    "codebook_mode": _row_text(row, "AppliedPrecoderCodebookMode"),
                    "num_ports": _row_text(row, "PrecodingNumPorts"),
                    "num_layers": _row_text(row, "PrecodingNumLayers"),
                })
            elif table_name == "live_combiner_table":
                out_row.update({
                    "num_rx_antennas": _row_text(row, "NumRxAntennas", "ConfiguredRxAntennas"),
                    "condition_number_db": _row_text(row, "ConditionNumber_dB"),
                    "selected_beam_index": _row_text(row, "SelectedBeamIndex"),
                    "best_beam_index": _row_text(row, "BestBeamIndex"),
                })
            elif table_name == "live_mimo_state_table":
                out_row.update({
                    "configured_layers": _row_text(row, "ConfiguredLayers", "Layers"),
                    "rank_indicator": _row_text(row, "RankIndicator"),
                    "rank_estimate": _row_text(row, "RankEstimate"),
                    "num_tx_ports": _row_text(row, "NumTxPorts", "PrecodingNumPorts"),
                    "beamforming_applied": _row_text(row, "BeamformingApplied"),
                })
            else:
                out_row.update({
                    "beam_selection_strategy": _row_text(row, "BeamSelectionStrategy"),
                    "selected_beam_index": _row_text(row, "SelectedBeamIndex"),
                    "beam_hit": _row_text(row, "BeamHit"),
                    "topk_beam_hit": _row_text(row, "TopKBeamHit"),
                    "beam_candidate_count": _row_text(row, "BeamCandidateCount"),
                })
            rows.append(out_row)
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_beam_table",
            "note": "Beamforming and MIMO report tables derived from persisted runtime beam-management evidence.",
            "source_logical_path": "beamforming/csv/probe_beam_mimo.csv",
            "source_row_count": len(rows),
        }
    if table_name == "live_drx_state" and energy_rows:
        grouped: dict[str, Counter[str]] = defaultdict(Counter)
        for row in energy_rows:
            ue_id = _row_text(row, "UEID", "EntityID") or "unknown"
            grouped[ue_id][_normalize_drx_state(_row_text(row, "State"))] += 1
        rows = [{
            "run_id": run_id,
            "ue_id": ue_id,
            "dominant_state": counter.most_common(1)[0][0] if counter else "",
            "state_sample_count": sum(counter.values()),
            "active_samples": counter.get("active", 0),
            "sleep_samples": counter.get("sleep", 0),
            "idle_samples": counter.get("idle", 0),
            "source_artifact": "rf/csv/energy_timeline_trace.csv",
        } for ue_id, counter in list(grouped.items())[:1024]]
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_drx_state",
            "note": "UE DRX-like occupancy derived from the persisted runtime energy-state trace.",
            "source_logical_path": "rf/csv/energy_timeline_trace.csv",
            "source_row_count": len(rows),
        }
    if table_name == "live_phy_mac_api_table" and slot_trace:
        rows = [{
            "run_id": run_id,
            "canonical_slot": _row_text(row, "CanonicalSlot", "Slot"),
            "frame": _row_text(row, "Frame"),
            "dl_grant_count": _row_text(row, "DLGrantCount"),
            "ul_grant_count": _row_text(row, "ULGrantCount"),
            "dl_trial_rows": _row_text(row, "DLTrialRows"),
            "ul_trial_rows": _row_text(row, "ULTrialRows"),
            "scheduler_source": _row_text(row, "SchedulerSource"),
            "phy_source": _row_text(row, "PHYSource"),
            "report_source": _row_text(row, "ReportSource"),
            "trace_status": _row_text(row, "TraceStatus"),
            "source_artifact": "packet_flow/csv/slot_trace.csv",
        } for row in slot_trace]
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_phy_mac_api_table",
            "note": "gNB-side orchestration view derived from the persisted slot trace.",
            "source_logical_path": "packet_flow/csv/slot_trace.csv",
            "source_row_count": len(rows),
        }
    if table_name in {"live_db_write_table", "live_csv_write_table", "live_artifact_write_table", "reports_all_artifacts_v"}:
        rows: list[dict[str, Any]] = []
        for art in artifact_rows:
            logical_path = str(art.get("logical_path") or "")
            if table_name == "live_csv_write_table" and not logical_path.startswith(("reports/", "analytics/")):
                continue
            rows.append({
                "run_id": run_id,
                "artifact_id": art["artifact_id"],
                "logical_path": logical_path,
                "artifact_kind": art["artifact_kind"],
                "mime_type": art["mime_type"],
                "sink_type": "db_artifact" if table_name != "live_csv_write_table" else "filesystem_projection",
                "target_table": logical_path if table_name == "live_db_write_table" else "",
                "target_file": logical_path if table_name != "live_db_write_table" else "",
            })
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_artifact_inventory",
                "note": "Artifact inventory derived from the DB-backed artifact store visible to the browser.",
                "source_logical_path": "sim_artifacts",
                "source_row_count": len(rows),
            }
    if table_name in {"live_browser_surface_integrity_table", "live_consistency_check_table", "reports_partial_or_missing_v", "reports_truth_violations_v", "reports_status_rollup_explanations_v"}:
        rows = []
        for spec in output_contract.iter_table_specs("reports"):
            source_rows = _table_source_health(str(spec.get("table_name") or ""), source_lookup, fetch_artifact_bytes)
            present_rows = sum(int(item["source_row_count"]) for item in source_rows)
            rows.append({
                "run_id": run_id,
                "section_slug": str(spec.get("section_slug") or ""),
                "contract_table": str(spec.get("table_name") or ""),
                "status": "generated" if present_rows > 0 else "missing_source_evidence",
                "source_paths_checked": "|".join(item["source_logical_path"] for item in source_rows),
                "present_source_count": sum(int(item["source_present"]) for item in source_rows),
                "source_row_count": present_rows,
                "rollup_explanation": "At least one truthful source artifact exists for this contract table." if present_rows > 0 else "No direct aliased source artifact was published for this run.",
            })
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_integrity_table",
            "note": "Integrity and partial/missing investigator views derived from direct alias-health checks.",
            "source_logical_path": "sim_artifacts",
            "source_row_count": len(rows),
        }
    if table_name == "reports_all_scalars_v":
        rows = [
            {"run_id": run_id, "metric_name": "run_completion", "metric_value": status_payload.get("run_completion", ""), "metric_unit": "ratio", "source_artifact": "sim_runs.status_json"},
            {"run_id": run_id, "metric_name": "dl_trial_rows", "metric_value": len(raw_rows["dl_pdsch"]), "metric_unit": "rows", "source_artifact": raw_sources["dl_pdsch"]},
            {"run_id": run_id, "metric_name": "ul_trial_rows", "metric_value": len(raw_rows["ul_pusch"]), "metric_unit": "rows", "source_artifact": raw_sources["ul_pusch"]},
            {"run_id": run_id, "metric_name": "dl_mean_measured_sinr_db", "metric_value": _mean_numeric(raw_rows["dl_pdsch"], "PostEqSINR_dB", "MeasuredTrialSINR_dB", "MeasuredSINR_dB"), "metric_unit": "dB", "source_artifact": raw_sources["dl_pdsch"]},
            {"run_id": run_id, "metric_name": "ul_mean_measured_sinr_db", "metric_value": _mean_numeric(raw_rows["ul_pusch"], "PostEqSINR_dB", "MeasuredTrialSINR_dB", "MeasuredSINR_dB"), "metric_unit": "dB", "source_artifact": raw_sources["ul_pusch"]},
            {"run_id": run_id, "metric_name": "energy_rows", "metric_value": len(energy_rows), "metric_unit": "rows", "source_artifact": "rf/csv/energy_timeline_trace.csv"},
        ]
        return {
            "data": _encode_rows_from_dicts(rows),
            "status": "specialized_runtime_scalar_view",
            "note": "Scalar investigator view derived from run status and raw artifact summaries.",
            "source_logical_path": "sim_runs.status_json",
            "source_row_count": len(rows),
        }
    if table_name in {"reports_all_enums_v", "reports_value_semantics_coverage_v"}:
        counts: Counter[tuple[str, str, str]] = Counter()
        # Keep this vocabulary broad enough for component runners while only
        # publishing categories that are physically present in their raw
        # runtime rows.  PRACH, for example, has detector/status provenance but
        # no post-equalization SINR or modulation; omitting its native fields
        # made a valid PRACH campaign look evidence-free.
        field_names = (
            "Direction", "Modulation", "GrantReason", "ValueSource",
            "ValueRole", "ValueStatus", "SINRSource", "SINRValueRole",
            "SINRValueStatus", "Status", "ThresholdMode", "Notes",
            "EvidenceScope", "ChannelModelApplied", "PRACHDesign",
        )
        for family, source_rows in raw_rows.items():
            for row in source_rows:
                for field_name in field_names:
                    token = _row_text(row, field_name)
                    if token:
                        counts[(family, field_name, token)] += 1
        rows = [{
            "run_id": run_id,
            "artifact_family": family,
            "field_name": field_name,
            "enum_value": token,
            "observation_count": count,
        } for (family, field_name, token), count in counts.most_common(1024)]
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_enum_view",
                "note": "Enum and value-semantics coverage views derived from distinct categorical values in raw runtime artifacts.",
                "source_logical_path": "|".join(raw_sources.values()),
                "source_row_count": len(rows),
            }
    if table_name == "reports_config_vs_measured_conflicts_v":
        status_configured_snr = _coerce_float(status_payload.get("ConfiguredSNR_dB") or "")
        rows = []
        for family in ("dl_pdsch", "ul_pusch", "pdcch"):
            source_rows = raw_rows[family]
            if not source_rows:
                continue
            configured_snr = _mean_numeric(
                source_rows, "ConfiguredSNR_dB", "SNR_dB"
            )
            if configured_snr is None:
                configured_snr = status_configured_snr
            measured_sinr = _mean_numeric(
                source_rows, "PostEqSINR_dB", "MeasuredTrialSINR_dB",
                "MeasuredSINR_dB"
            )
            delta = ""
            if configured_snr is not None and measured_sinr is not None:
                delta = float(measured_sinr) - float(configured_snr)
            rows.append({
                "run_id": run_id,
                "artifact_family": family,
                "source_artifact": raw_sources[family],
                "configured_snr_db": configured_snr if configured_snr is not None else "",
                "mean_measured_sinr_db": measured_sinr,
                "measured_minus_configured_snr_db": delta,
                "mean_serving_rsrp_dbm": _mean_numeric(source_rows, "ServingRSRP_dBm"),
                "mean_csi_rsrp_dbm": _mean_numeric(
                    source_rows, "CSI_RSRP_dBm", "MeasuredCSIRSRP_dBm"
                ),
                "lineage_note": (
                    "Configured launch SNR and measured post-equalization SINR "
                    "remain source-labelled; their delta is not treated as a "
                    "pass/fail equality when power-control or link-budget "
                    "reference planes differ."
                ),
            })
        if rows:
            return {
                "data": _encode_rows_from_dicts(rows),
                "status": "specialized_runtime_config_measured_view",
                "note": "Configured-vs-measured comparison derived from persisted trial artifacts.",
                "source_logical_path": "|".join(raw_sources[family] for family in ("dl_pdsch", "ul_pusch", "pdcch")),
                "source_row_count": len(rows),
            }
    return None


def _select_source_table_artifact(
    source_paths: list[str],
    source_lookup: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
) -> tuple[dict[str, Any] | None, bytes, list[str], list[list[str]]]:
    fallback: tuple[dict[str, Any] | None, bytes, list[str], list[list[str]]] = (None, b"", [], [])
    for path in source_paths:
        art = source_lookup.get(path)
        if not art or str(art.get("artifact_kind") or "") != "table_csv":
            continue
        source_data = fetch_artifact_bytes(int(art["artifact_id"]))
        header, rows = _decode_csv(source_data)
        source_data, header, rows = _canonicalize_contract_source_rows(path, header, rows)
        if not fallback[0]:
            fallback = (art, source_data, header, rows)
        if not rows:
            continue
        _, dict_rows = _decode_csv_dicts(source_data)
        if _table_placeholder_summary_status(dict_rows) in {"source_artifact_missing", "source_artifact_present_but_empty"}:
            continue
        return art, source_data, header, rows
    return fallback


def _selected_cell(records: list[dict[str, str]], *cell_names: str) -> str:
    counts: dict[str, int] = {}
    for row in records:
        token = _row_text(row, *cell_names)
        if token:
            counts[token] = counts.get(token, 0) + 1
    if not counts:
        return ""
    return max(counts.items(), key=lambda item: (item[1], item[0]))[0]


def _build_grid_heatmap_records(
    records: list[dict[str, str]],
    *,
    cell_names: tuple[str, ...],
    slot_names: tuple[str, ...],
    rb_names: tuple[str, ...],
    occ_names: tuple[str, ...],
) -> tuple[list[dict[str, Any]], str]:
    chosen_cell = _selected_cell(records, *cell_names)
    filtered = [row for row in records if _row_text(row, *cell_names) == chosen_cell] if chosen_cell else list(records)
    points: dict[tuple[int, int], float] = {}
    out_rows: list[dict[str, Any]] = []
    for row in filtered:
        slot_v = _row_float(row, *slot_names)
        rb_v = _row_float(row, *rb_names)
        occ_v = _row_float(row, *occ_names)
        if slot_v is None or rb_v is None:
            continue
        value = occ_v if occ_v is not None else 1.0
        slot_i = int(round(slot_v))
        rb_i = int(round(rb_v))
        points[(slot_i, rb_i)] = points.get((slot_i, rb_i), 0.0) + float(value)
        out_rows.append({"cell_id": chosen_cell, "slot": slot_i, "rb_index": rb_i, "occupancy_value": float(value)})
    return out_rows, chosen_cell


def _grid_rows_to_heatmap(
    rows: list[dict[str, Any]],
    x_name: str,
    y_name: str,
    value_name: str,
) -> tuple[list[str], list[str], list[list[float]]]:
    def _token_sort_key(token: str) -> tuple[int, Any, str]:
        numeric = _coerce_float(token)
        if numeric is not None:
            return (0, float(numeric), token)
        return (1, token.lower(), token)

    x_values = sorted({int(round(float(row[x_name]))) for row in rows if row.get(x_name) is not None})
    y_values = sorted({str(row[y_name]) for row in rows if str(row.get(y_name, "")).strip()}, key=_token_sort_key)
    if not x_values or not y_values:
        return [], [], []
    x_index = {value: idx for idx, value in enumerate(x_values)}
    y_index = {value: idx for idx, value in enumerate(y_values)}
    matrix = [[0.0 for _ in x_values] for _ in y_values]
    for row in rows:
        try:
            x_val = int(round(float(row[x_name])))
            y_val = str(row[y_name])
            v = float(row.get(value_name) or 0.0)
        except Exception:
            continue
        matrix[y_index[y_val]][x_index[x_val]] += v
    return [str(value) for value in x_values], y_values, matrix


def _encode_dict_rows(header: list[str], rows: list[dict[str, Any]]) -> bytes:
    return _encode_csv(header, [[row.get(col, "") for col in header] for row in rows])


def _trial_row_bler(row: dict[str, str]) -> float | None:
    crc_pass = _row_text(row, "CRCPass")
    if crc_pass:
        return 0.0 if crc_pass.lower() in {"1", "true", "pass", "passed", "ok", "ack"} else 1.0
    codeblock_bler = _row_float(row, "CodeBlockBLER")
    if codeblock_bler is not None:
        return float(codeblock_bler)
    return None


def _trial_row_ber(row: dict[str, str]) -> float | None:
    bit_errors = _row_float(row, "BitErrors")
    bits_compared = _row_float(row, "BitsCompared")
    if bit_errors is None or bits_compared is None or bits_compared <= 0:
        return None
    return float(bit_errors) / float(bits_compared)


def _trial_row_fer(row: dict[str, str]) -> float | None:
    token = _row_text(row, "CRCPass", "DecodeSuccess", "CombinedDecodeOK", "CurrentDecodeOK")
    if not token:
        return None
    return 0.0 if token.lower() in {"1", "true", "pass", "passed", "ok", "ack"} else 1.0


def _parse_float_vector(value: Any) -> list[float]:
    text = str(value or "").strip()
    if not text or text.lower() in {"nan", "<missing>", "missing", "unavailable"}:
        return []
    out: list[float] = []
    for token in re.findall(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", text):
        number = _coerce_float(token)
        if number is not None:
            out.append(float(number))
    return out


def _data_channel_trial_rows(trial_rows: list[tuple[str, dict[str, str]]]) -> list[tuple[str, dict[str, str]]]:
    return [
        (source_path, row)
        for source_path, row in trial_rows
        if "dl_pdsch_trials.csv" in source_path or "ul_pusch_trials.csv" in source_path
    ]


def _trial_rows_with_paths(
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    candidates: list[str] | tuple[str, ...],
) -> list[tuple[str, dict[str, str]]]:
    out: list[tuple[str, dict[str, str]]] = []
    for logical_path in candidates:
        _header, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, logical_path)
        for row in rows:
            out.append((str(logical_path), row))
    return out


def _wilson_score_interval(success_count: float, sample_count: int, z_value: float = 1.959963984540054) -> tuple[float, float]:
    """Return a two-sided Wilson interval for a Bernoulli proportion."""
    n = max(0, int(sample_count))
    if n <= 0:
        return math.nan, math.nan
    successes = min(max(float(success_count), 0.0), float(n))
    proportion = successes / float(n)
    z2 = float(z_value) ** 2
    denominator = 1.0 + z2 / float(n)
    center = (proportion + z2 / (2.0 * float(n))) / denominator
    half_width = (
        float(z_value)
        * math.sqrt(
            proportion * (1.0 - proportion) / float(n)
            + z2 / (4.0 * float(n) ** 2)
        )
        / denominator
    )
    return max(0.0, center - half_width), min(1.0, center + half_width)


def _prach_rate_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    chart_key = str(chart_name or "").strip().lower()
    metric_specs = {
        "detection rate": {
            "metric_label": "Detection rate",
            "metric_keys": {"prach_detection_probability"},
            "trial_flag": lambda row: _row_flag(row, "DecodeSuccess", "SuccessFlag")
            if _row_flag(row, "DecodeSuccess", "SuccessFlag") is not None
            else (_row_text(row, "Status").strip().lower() in {"pass", "detected", "success"})
            if _row_text(row, "Status")
            else (_row_float(row, "DetectionMetric") or 0.0) > 0.0,
        },
        "p_d": {
            "metric_label": "Detection probability",
            "metric_keys": {"prach_detection_probability"},
            "trial_flag": lambda row: _row_flag(row, "DecodeSuccess", "SuccessFlag")
            if _row_flag(row, "DecodeSuccess", "SuccessFlag") is not None
            else (_row_text(row, "Status").strip().lower() in {"pass", "detected", "success"})
            if _row_text(row, "Status")
            else (_row_float(row, "DetectionMetric") or 0.0) > 0.0,
        },
        "false alarm rate": {
            "metric_label": "False alarm rate",
            "metric_keys": {"prach_false_alarm"},
            "trial_flag": lambda row: _row_flag(row, "FalseAlarmFlag"),
        },
        "far": {
            "metric_label": "False alarm rate",
            "metric_keys": {"prach_false_alarm"},
            "trial_flag": lambda row: _row_flag(row, "FalseAlarmFlag"),
        },
        "p_fa": {
            "metric_label": "False alarm probability",
            "metric_keys": {"prach_false_alarm"},
            "trial_flag": lambda row: _row_flag(row, "FalseAlarmFlag"),
        },
        "missed detection rate": {
            "metric_label": "Missed detection rate",
            "metric_keys": {"prach_missed_detection"},
            "trial_flag": lambda row: (
                _row_flag(row, "MissedDetectionFlag")
                if _row_flag(row, "MissedDetectionFlag") is not None
                else (
                    not bool(
                        _row_flag(row, "DecodeSuccess", "SuccessFlag")
                        if _row_flag(row, "DecodeSuccess", "SuccessFlag") is not None
                        else (_row_text(row, "Status").strip().lower() in {"pass", "detected", "success"})
                        if _row_text(row, "Status")
                        else (_row_float(row, "DetectionMetric") or 0.0) > 0.0
                    )
                    and not bool(_row_flag(row, "FalseAlarmFlag"))
                )
            ),
        },
        "p_md": {
            "metric_label": "Missed detection probability",
            "metric_keys": {"prach_missed_detection"},
            "trial_flag": lambda row: (
                _row_flag(row, "MissedDetectionFlag")
                if _row_flag(row, "MissedDetectionFlag") is not None
                else (
                    not bool(
                        _row_flag(row, "DecodeSuccess", "SuccessFlag")
                        if _row_flag(row, "DecodeSuccess", "SuccessFlag") is not None
                        else (_row_text(row, "Status").strip().lower() in {"pass", "detected", "success"})
                        if _row_text(row, "Status")
                        else (_row_float(row, "DetectionMetric") or 0.0) > 0.0
                    )
                    and not bool(_row_flag(row, "FalseAlarmFlag"))
                )
            ),
        },
    }
    spec = metric_specs.get(chart_key)
    if spec is None:
        return None

    trial_path, trial_rows = _first_available_rows(
        existing,
        fetch_artifact_bytes,
        ["air_interface/csv/prach_trials.csv", "control/csv/prach_trials.csv", "control/csv/prach_detection_trials.csv"],
    )
    grouped: dict[float | None, list[float]] = defaultdict(list)
    if trial_rows:
        for row in trial_rows:
            flag_value = spec["trial_flag"](row)
            if flag_value is None:
                continue
            snr_value, _snr_source = _row_quality_axis_value(row, allow_receiver_hest=False)
            bucket = float(snr_value) if snr_value is not None and math.isfinite(float(snr_value)) else None
            grouped[bucket].append(1.0 if bool(flag_value) else 0.0)
    if grouped:
        ordered = sorted(grouped.items(), key=lambda item: (-9999.0 if item[0] is None else float(item[0])))
        points: list[list[float]] = []
        tick_labels: list[str] = []
        csv_rows: list[dict[str, Any]] = []
        total_samples = 0
        total_positive = 0.0
        for idx, (snr_bucket, values) in enumerate(ordered, start=1):
            if not values:
                continue
            rate_value = sum(values) / len(values)
            point_x = float(idx) if snr_bucket is None else float(snr_bucket)
            tick_label = "Observed PRACH" if snr_bucket is None else f"{snr_bucket:.3g} dB"
            points.append([point_x, float(rate_value)])
            tick_labels.append(tick_label)
            total_samples += len(values)
            total_positive += sum(values)
            ci95_lower, ci95_upper = _wilson_score_interval(sum(values), len(values))
            csv_rows.append(
                {
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "bucket_name": tick_label,
                    "snr_db": "" if snr_bucket is None else snr_bucket,
                    "metric_value": rate_value,
                    "sample_count": len(values),
                    "ci95_lower": ci95_lower,
                    "ci95_upper": ci95_upper,
                    "source_table_logical_path": trial_path,
                }
            )
        if points:
            dataset = {
                "mode": "bar" if len(points) <= 8 else "line",
                "x_label": "PRACH SNR (dB)" if any(item[0] is not None for item in ordered) else "Observation bucket",
                "y_label": str(spec["metric_label"]),
                "points": points,
                "y_axis_min": 0.0,
                "y_axis_max": 1.0,
                "evidence_shape_policy": "observed_distribution" if len(points) == 1 else "observed_timeline",
                "sample_count": total_samples,
            }
            if dataset["mode"] == "bar":
                dataset["tick_labels"] = tick_labels
            summary = [
                f"source={trial_path}",
                f"trial_rows={len(trial_rows)}",
                f"samples_used={total_samples}",
                f"mean_rate={total_positive / max(total_samples, 1):.6f}",
            ]
            overall_lower, overall_upper = _wilson_score_interval(total_positive, total_samples)
            summary.extend([
                f"wilson95_lower={overall_lower:.6f}",
                f"wilson95_upper={overall_upper:.6f}",
            ])
            img_bytes = _render_svg_plot(
                chart_name,
                "Observed PRACH Bernoulli rate from persisted trials; Wilson 95% bounds are reported in the summary.",
                dataset,
                summary,
            )
            return {
                "csv_bytes": _encode_dict_rows(
                    ["run_id", "chart_name", "bucket_name", "snr_db", "metric_value", "sample_count", "ci95_lower", "ci95_upper", "source_table_logical_path"],
                    csv_rows,
                ),
                "img_bytes": img_bytes,
                "csv_status": "specialized_runtime_detection_dataset",
                "image_status": "generated_specialized_runtime_summary_svg",
                "source_table_path": trial_path,
                "source_row_count": len(trial_rows),
                "note": "Detection-rate chart derived from truthful PRACH trial flags grouped by observed SNR.",
            }

    summary_path, summary_rows = _first_available_rows(
        existing,
        fetch_artifact_bytes,
        ["reports/csv/initial_access_random_access_outputs.csv", "analytics/csv/random_access_analytics.csv"],
    )
    if not summary_rows:
        return None
    rate_value = None
    count_value = None
    for row in summary_rows:
        metric_key = _row_text(row, "MetricKey").strip().lower()
        metric_name = _row_text(row, "MetricName").strip().lower()
        statistic = _row_text(row, "Statistic").strip().lower()
        if metric_key not in spec["metric_keys"] and not any(token in metric_name for token in chart_key.split()):
            continue
        if statistic == "rate":
            rate_value = _row_float(row, "ValueNumeric", "Value")
        elif statistic == "count":
            count_value = _row_float(row, "ValueNumeric", "Value")
    if rate_value is None:
        return None
    dataset = {
        "mode": "bar",
        "x_label": "Observation bucket",
        "y_label": str(spec["metric_label"]),
        "points": [[1.0, float(rate_value)]],
        "y_axis_min": 0.0,
        "y_axis_max": 1.0,
        "tick_labels": ["Observed PRACH"],
        "evidence_shape_policy": "measured_scalar",
        "sample_count": int(round(count_value)) if count_value is not None else 1,
    }
    csv_rows = [
        {
            "run_id": run_id,
            "chart_name": chart_name,
            "bucket_name": "Observed PRACH",
            "snr_db": "",
            "metric_value": float(rate_value),
            "sample_count": "" if count_value is None else count_value,
            "ci95_lower": "",
            "ci95_upper": "",
            "source_table_logical_path": summary_path,
        }
    ]
    summary = [f"source={summary_path}", f"observed_rate={float(rate_value):.6f}"]
    if count_value is not None:
        summary.append(f"sample_count={int(round(count_value))}")
    img_bytes = _render_svg_plot(
        chart_name,
        "Observed PRACH summary rate from persisted runtime metrics; no SNR curve is implied.",
        dataset,
        summary,
    )
    return {
        "csv_bytes": _encode_dict_rows(
            ["run_id", "chart_name", "bucket_name", "snr_db", "metric_value", "sample_count", "ci95_lower", "ci95_upper", "source_table_logical_path"],
            csv_rows,
        ),
        "img_bytes": img_bytes,
        "csv_status": "specialized_summary_detection_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": summary_path,
        "source_row_count": len(summary_rows),
        "note": "Detection-rate chart derived from the persisted PRACH summary metrics artifact.",
    }


def _prach_peak_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    chart_key = str(chart_name or "").strip().lower()
    if chart_key not in {
        "prach peak search timeline",
        "prach correlation peak distributions",
        "prach peak search results",
        "peak value histogram",
        "noise floor trend",
        "prach noise floor distributions",
    }:
        return None
    source_path, records = _first_available_rows(
        existing,
        fetch_artifact_bytes,
        [
            "reports/csv/prach_correlation_trace.csv",
            "reports/csv/prach_correlation_traces.csv",
            "air_interface/csv/prach_trials.csv",
            "control/csv/prach_trials.csv",
        ],
    )
    if not records:
        return None
    csv_rows: list[dict[str, Any]] = []
    values: list[float] = []
    points: list[list[float]] = []
    status_counts: Counter[str] = Counter()
    for idx, row in enumerate(records, start=1):
        slot = _row_float(row, "trial_id", "Slot")
        if slot is None:
            slot = float(idx)
        peak_value = _row_float(row, "correlation_abs", "PeakValue", "peak_value", "DetectionMetric", "detection_metric")
        noise_floor = _row_float(
            row, "noise_floor", "NoiseFloor", "PDPAverageNoiseFloor",
            "DetectorNoiseFloor", "NoiseVariance", "noise_variance",
        )
        metric = noise_floor if "noise floor" in chart_key else peak_value
        if metric is None or not math.isfinite(float(metric)):
            continue
        values.append(float(metric))
        points.append([float(slot), float(metric)])
        status_text = _row_text(row, "Status", "DetectionOutcome") or "unknown"
        status_counts[status_text] += 1
        csv_rows.append(
            {
                "run_id": run_id,
                "chart_name": chart_name,
                "slot": slot,
                "peak_index": _row_float(row, "peak_lag_samples", "lag_samples", "PeakIndex", "peak_index"),
                "peak_value": peak_value,
                "noise_floor": noise_floor,
                "detection_metric": _row_float(row, "correlation_abs", "DetectionMetric", "detection_metric"),
                "timing_error_samples": _row_float(row, "timing_advance_samples", "TimingError_samples", "timing_error_samples"),
                "status": _row_text(row, "Status", "DetectionOutcome"),
                "source_table_logical_path": source_path,
            }
        )
    if not csv_rows:
        return None
    unique_slots = _unique_numeric_count([point[0] for point in points])
    timeline_points = points
    timeline_x_label = "Slot/sample"
    if unique_slots < 2:
        timeline_points = [[float(index), float(point[1])] for index, point in enumerate(points, start=1)]
        timeline_x_label = "PRACH observation index"
    is_distribution_chart = "histogram" in chart_key or "distributions" in chart_key or "results" in chart_key
    if is_distribution_chart:
        dataset = {
            "mode": "bar",
            "x_label": "Noise floor" if "noise floor" in chart_key else "PRACH peak metric",
            "y_label": "Count",
            "points": _histogram_points(values, 18),
            "evidence_shape_policy": "observed_distribution",
            "sample_count": len(values),
        }
    else:
        dataset = {
            "mode": "scatter" if len(points) < 3 else "line",
            "x_label": timeline_x_label,
            "y_label": "Noise floor" if "noise floor" in chart_key else "PRACH peak metric",
            "points": timeline_points[:MAX_PREVIEW_ROWS],
            "evidence_shape_policy": "observed_timeline",
            "sample_count": len(values),
        }
    unique_values = _unique_numeric_count(values)
    summary = [f"source={source_path}", f"rows={len(csv_rows)}"]
    img_bytes = _render_svg_plot(
        chart_name,
        "PRACH peak/noise observations from persisted runtime rows; sparse samples are rendered as points or exact categorical counts.",
        dataset,
        summary + [f"unique_slots={unique_slots}", f"unique_values={unique_values}"],
    )
    return {
        "csv_bytes": _encode_dict_rows(
            ["run_id", "chart_name", "slot", "peak_index", "peak_value", "noise_floor", "detection_metric", "timing_error_samples", "status", "source_table_logical_path"],
            csv_rows,
        ),
        "img_bytes": img_bytes,
        "csv_status": "specialized_runtime_prach_peak_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": source_path,
        "source_row_count": len(records),
        "note": "PRACH peak-search chart uses exported detection metric/peak/noise fields only; unavailable peak-index/noise columns are left blank in the CSV.",
    }


def _pucch_dtx_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    if str(chart_name or "").strip().lower() != "pucch dtx statistics":
        return None
    source_path, records = _first_available_rows(existing, fetch_artifact_bytes, ["air_interface/csv/pucch_trials.csv", "control/csv/pucch_trials.csv"])
    if not records:
        return None
    counts: Counter[str] = Counter()
    csv_rows: list[dict[str, Any]] = []
    for row in records:
        outcome = _row_text(row, "DetectionOutcome", "Status").strip().lower()
        bits_compared = _row_float(row, "BitsCompared")
        detection_attempted = _row_flag(row, "DetectionAttempted")
        dtx_flag = _row_flag(row, "DTXFlag", "DTX", "DtxDetected")
        missed_flag = _row_flag(row, "MissedDetection", "MissedDetectionFlag")
        false_alarm_flag = _row_flag(row, "FalseAlarm", "FalseAlarmFlag")
        decode_ok = _row_flag(row, "CRCPass", "DecodeSuccess", "PUCCHDecodeOk", "DetectionUsable")
        if dtx_flag is True or outcome in {"dtx", "not_detected", "no_signal"}:
            bucket = "DTX"
        elif false_alarm_flag is True:
            bucket = "False alarm"
        elif missed_flag is True or outcome in {"missed", "miss"}:
            bucket = "Missed detection"
        elif detection_attempted is False:
            bucket = "Detection not attempted"
        elif decode_ok is True or outcome in {"detected", "pass", "ok", "success", "ack", "nack"}:
            bucket = "Decoded/observed"
        elif decode_ok is False or outcome in {"failed", "fail", "crc_fail", "decode_fail"}:
            bucket = "Decode failure"
        else:
            bucket = "Unavailable"
        counts[bucket] += 1
        csv_rows.append(
            {
                "run_id": run_id,
                "chart_name": chart_name,
                "slot": _row_float(row, "Slot"),
                "ue_id": _row_text(row, "UEID", "UEIndex", "RNTI"),
                "dtx_bucket": bucket,
                "detection_outcome": outcome,
                "bits_compared": bits_compared,
                "dtx_flag": "" if dtx_flag is None else int(bool(dtx_flag)),
                "missed_detection_flag": "" if missed_flag is None else int(bool(missed_flag)),
                "false_alarm_flag": "" if false_alarm_flag is None else int(bool(false_alarm_flag)),
                "decode_ok": "" if decode_ok is None else int(bool(decode_ok)),
                "source_table_logical_path": source_path,
            }
        )
    dataset, summary = _bar_dataset_from_named_values("PUCCH feedback bucket", "Count", [(key, float(value)) for key, value in counts.items()])
    summary.append(f"source={source_path}")
    return {
        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "slot", "ue_id", "dtx_bucket", "detection_outcome", "bits_compared", "dtx_flag", "missed_detection_flag", "false_alarm_flag", "decode_ok", "source_table_logical_path"], csv_rows),
        "img_bytes": _render_svg_plot(chart_name, "PUCCH DTX/miss/detect statistics from persisted PUCCH waveform trials.", dataset, summary),
        "csv_status": "specialized_runtime_pucch_dtx_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": source_path,
        "source_row_count": len(records),
        "note": "PUCCH buckets are derived from explicit DTX/missed/false-alarm/decode fields; zero compared bits alone is not treated as a DTX event.",
    }


def _beam_mimo_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    chart_key = str(chart_name or "").strip().lower()
    handled = {
        "selected vs best beam timeline",
        "beam id timeline",
        "beam pair timeline",
        "selected vs best beam gap",
        "beam gain gap histogram",
        "beam hit rate / top-k hit rate",
        "beam hit rate timeline",
        "rank distribution",
        "condition number distribution",
        "precoder mode distribution",
    }
    if chart_key not in handled:
        return None
    source_rows = _all_available_rows(
        existing,
        fetch_artifact_bytes,
        [
            "beamforming/csv/beam_precoder_table.csv",
            "beamforming/csv/probe_beam_mimo.csv",
            "beamforming/csv/probe_beam_management.csv",
            "air_interface/csv/dl_pdsch_trials.csv",
            "air_interface/csv/ul_pusch_trials.csv",
            "air_interface/csv/csi_rs_trials.csv",
            "reports/csv/channel_snapshots.csv",
        ],
    )
    if not source_rows:
        return None
    flat_rows = [(source_path, row) for source_path, rows in source_rows for row in rows]
    csv_rows: list[dict[str, Any]] = []
    if chart_key in {"selected vs best beam timeline", "beam id timeline", "beam pair timeline"}:
        points: list[list[float]] = []
        for idx, (source_path, row) in enumerate(flat_rows, start=1):
            selected = _row_float(row, "SelectedBeamIndex", "selected_beam_index", "BeamIndex")
            best = _row_float(row, "BestBeamIndex", "best_beam_index")
            slot = _row_float(row, "Slot")
            if slot is None:
                slot = float(idx)
            if selected is None:
                continue
            points.append([float(slot), float(selected)])
            csv_rows.append(
                {
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "slot": slot,
                    "selected_beam_index": selected,
                    "best_beam_index": best,
                    "source_table_logical_path": source_path,
                }
            )
        if not csv_rows:
            return None
        dataset = {
            "mode": "line",
            "x_label": "Slot/sample",
            "y_label": "Selected beam index",
            "points": points[:MAX_PREVIEW_ROWS],
            "evidence_shape_policy": "observed_timeline",
            "sample_count": len(csv_rows),
        }
        return {
            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "slot", "selected_beam_index", "best_beam_index", "source_table_logical_path"], csv_rows),
            "img_bytes": _render_svg_plot(chart_name, "Selected beam timeline from runtime beam/precoder rows.", dataset, [f"rows={len(csv_rows)}"]),
            "csv_status": "specialized_runtime_beam_dataset",
            "image_status": "generated_specialized_runtime_summary_svg",
            "source_table_path": "|".join(sorted({row["source_table_logical_path"] for row in csv_rows})),
            "source_row_count": len(csv_rows),
            "note": "Beam timeline uses exported selected/best beam indices only.",
        }
    if chart_key in {"selected vs best beam gap", "beam gain gap histogram"}:
        values: list[float] = []
        for source_path, row in flat_rows:
            gap = _row_float(row, "BeamGainGap_dB", "beam_gain_gap_db", "SelectedVsBestBeamGap_dB")
            if gap is None or not math.isfinite(float(gap)):
                continue
            values.append(float(gap))
            csv_rows.append({"run_id": run_id, "chart_name": chart_name, "beam_gap_value": float(gap), "source_table_logical_path": source_path})
        if not csv_rows:
            reason = "No physical BeamGainGap_dB field was exported. Beam-index distance is not a dB gain gap, so this chart is unavailable rather than substituted."
            return {
                "csv_bytes": _encode_csv(["run_id", "chart_name", "status", "reason", "checked_sources"], [[run_id, chart_name, "unavailable_exact_reason", reason, "|".join(sorted({path for path, _row in flat_rows}))]]),
                "img_bytes": _render_reason_svg(chart_name, "Beam gain gap needs measured selected-vs-best beam gain evidence.", [reason]),
                "csv_status": "unavailable_exact_reason",
                "image_status": "generated_unavailable_reason_svg",
                "source_table_path": "|".join(sorted({path for path, _row in flat_rows})),
                "source_row_count": len(flat_rows),
                "note": reason,
            }
        dataset = {
            "mode": "bar",
            "x_label": "Beam gain gap dB",
            "y_label": "Count",
            "points": _histogram_points(values, 18),
            "evidence_shape_policy": "observed_distribution",
            "sample_count": len(values),
        }
        return {
            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "beam_gap_value", "source_table_logical_path"], csv_rows),
            "img_bytes": _render_svg_plot(chart_name, "Beam gap distribution from exported runtime beam metrics.", dataset, [f"samples={len(values)}"]),
            "csv_status": "specialized_runtime_beam_dataset",
            "image_status": "generated_specialized_runtime_summary_svg",
            "source_table_path": "|".join(sorted({row["source_table_logical_path"] for row in csv_rows})),
            "source_row_count": len(csv_rows),
            "note": "Uses only physical BeamGainGap_dB exported by runtime beam evidence.",
        }
    if chart_key in {"beam hit rate / top-k hit rate", "beam hit rate timeline"}:
        grouped: dict[int, list[float]] = defaultdict(list)
        for idx, (_source_path, row) in enumerate(flat_rows, start=1):
            hit = _row_flag(row, "BeamHit", "beam_hit", "TopKHit")
            if hit is None:
                continue
            slot = _row_float(row, "Slot")
            if slot is None:
                slot = float(idx)
            grouped[int(round(slot))].append(1.0 if hit else 0.0)
        points = [[float(slot), sum(vals) / len(vals)] for slot, vals in sorted(grouped.items()) if vals]
        if not points:
            return None
        csv_rows = [{"run_id": run_id, "chart_name": chart_name, "slot": slot, "beam_hit_rate": value, "source_table_logical_path": "runtime_beam_sources"} for slot, value in points]
        dataset = {
            "mode": "line",
            "x_label": "Slot/sample",
            "y_label": "Beam hit rate",
            "points": points,
            "evidence_shape_policy": "observed_timeline",
            "sample_count": len(flat_rows),
        }
        return {
            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "slot", "beam_hit_rate", "source_table_logical_path"], csv_rows),
            "img_bytes": _render_svg_plot(chart_name, "Beam hit-rate trend from exported beam-hit flags.", dataset, [f"points={len(points)}"]),
            "csv_status": "specialized_runtime_beam_dataset",
            "image_status": "generated_specialized_runtime_summary_svg",
            "source_table_path": "runtime_beam_sources",
            "source_row_count": len(flat_rows),
            "note": "Beam hit-rate trend uses explicit BeamHit/top-K hit flags only.",
        }
    if chart_key == "rank distribution":
        counts: Counter[int] = Counter()
        for _source_path, row in flat_rows:
            rank = _row_float(row, "RankIndicator", "Layers", "precoding_num_layers", "NumLayers")
            if rank is not None and math.isfinite(float(rank)):
                counts[int(round(float(rank)))] += 1
        if not counts:
            return None
        dataset, summary = _bar_dataset_from_named_values("Rank/layer count", "Count", [(str(rank), float(count)) for rank, count in sorted(counts.items())])
        csv_rows = [{"run_id": run_id, "chart_name": chart_name, "rank": rank, "count": count, "source_table_logical_path": "runtime_beam_and_trial_sources"} for rank, count in sorted(counts.items())]
        return {
            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "rank", "count", "source_table_logical_path"], csv_rows),
            "img_bytes": _render_svg_plot(chart_name, "Rank/layer distribution from runtime MIMO and trial rows.", dataset, summary),
            "csv_status": "specialized_runtime_rank_dataset",
            "image_status": "generated_specialized_runtime_summary_svg",
            "source_table_path": "runtime_beam_and_trial_sources",
            "source_row_count": len(flat_rows),
            "note": "Rank distribution uses RankIndicator/Layers/precoding_num_layers columns from persisted runtime rows.",
        }
    if chart_key == "condition number distribution":
        values = [float(value) for _source_path, row in flat_rows for value in [_row_float(row, "ConditionNumber_dB", "condition_number_db")] if value is not None and math.isfinite(float(value))]
        if not values:
            return None
        csv_rows = [{"run_id": run_id, "chart_name": chart_name, "condition_number_db": value, "source_table_logical_path": "runtime_channel_trial_sources"} for value in values]
        dataset = {"mode": "bar", "x_label": "Condition number (dB)", "y_label": "Count", "points": _histogram_points(values, 18)}
        return {
            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "condition_number_db", "source_table_logical_path"], csv_rows),
            "img_bytes": _render_svg_plot(chart_name, "Condition-number distribution from exported channel/trial metrics.", dataset, [f"samples={len(values)}"]),
            "csv_status": "specialized_runtime_condition_dataset",
            "image_status": "generated_specialized_runtime_summary_svg",
            "source_table_path": "runtime_channel_trial_sources",
            "source_row_count": len(values),
            "note": "Condition-number distribution uses only exported ConditionNumber_dB fields.",
        }
    if chart_key == "precoder mode distribution":
        counts = Counter()
        for _source_path, row in flat_rows:
            mode = _row_text(row, "AppliedPrecoderSource", "applied_precoder_source", "PrecoderSource", "precoder_source")
            if mode:
                counts[mode] += 1
        if not counts:
            return None
        dataset, summary = _bar_dataset_from_named_values("Precoder mode bucket", "Count", [(name, float(count)) for name, count in counts.most_common(16)])
        csv_rows = [{"run_id": run_id, "chart_name": chart_name, "precoder_mode": name, "count": count, "source_table_logical_path": "runtime_beam_sources"} for name, count in counts.items()]
        return {
            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "precoder_mode", "count", "source_table_logical_path"], csv_rows),
            "img_bytes": _render_svg_plot(chart_name, "Precoder-source distribution from runtime beam/precoder rows.", dataset, summary),
            "csv_status": "specialized_runtime_precoder_dataset",
            "image_status": "generated_specialized_runtime_summary_svg",
            "source_table_path": "runtime_beam_sources",
            "source_row_count": len(flat_rows),
            "note": "Precoder mode distribution uses exported runtime precoder-source labels.",
        }
    return None


def _pdcch_control_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    chart_key = str(chart_name or "").strip().lower()
    if chart_key not in {
        "aggregation level distribution",
        "cce usage heatmap",
        "pdcch decode success/failure trend if applicable",
        "pdcch dmrs occupancy",
    }:
        return None

    if chart_key == "cce usage heatmap":
        source_path, candidate_rows = _first_available_rows(
            existing,
            fetch_artifact_bytes,
            [
                "reports/csv/pdcch6gr_per_candidate_results.csv",
                "air_interface/csv/pdcch_trials.csv",
                "control/csv/pdcch_trials.csv",
            ],
        )
        usage_rows: list[dict[str, Any]] = []
        for row_index, row in enumerate(candidate_rows, start=1):
            start_cce = _row_float(row, "start_cce", "StartCCE", "CCEIndex")
            aggregation = _row_float(row, "AL", "AggregationLevel", "aggregation_level")
            trial = _row_float(row, "TrialIndex", "Slot", "slot_number")
            if start_cce is None:
                continue
            aggregation_i = max(1, int(round(float(aggregation or 1.0))))
            trial_i = int(round(float(trial if trial is not None else row_index)))
            for cce_index in range(
                int(round(float(start_cce))),
                int(round(float(start_cce))) + aggregation_i,
            ):
                usage_rows.append(
                    {
                        "trial_index": trial_i,
                        "cce_index": cce_index,
                        "occupancy_count": 1.0,
                    }
                )
        if not usage_rows:
            return None
        x_labels, y_labels, matrix = _grid_rows_to_heatmap(
            usage_rows, "trial_index", "cce_index", "occupancy_count"
        )
        image_bytes, image_status = _render_heatmap_or_projection_svg(
            chart_name,
            "Monitored CCE occupancy expanded from persisted candidate start-CCE and aggregation-level rows.",
            x_labels,
            y_labels,
            matrix,
            [f"source={source_path}", f"candidate_cce_rows={len(usage_rows)}"],
            "Trial / slot",
            "CCE index",
        )
        csv_rows = [
            {
                **row,
                "run_id": run_id,
                "chart_name": chart_name,
                "source_table_logical_path": source_path,
            }
            for row in usage_rows
        ]
        return {
            "csv_bytes": _encode_dict_rows(
                ["run_id", "chart_name", "trial_index", "cce_index", "occupancy_count", "source_table_logical_path"],
                csv_rows,
            ),
            "img_bytes": image_bytes,
            "csv_status": "specialized_runtime_pdcch_cce_dataset",
            "image_status": image_status,
            "source_table_path": source_path,
            "source_row_count": len(candidate_rows),
            "note": "CCE occupancy is derived only from actual monitored candidate start-CCE and AL fields.",
        }

    if chart_key == "pdcch dmrs occupancy":
        exact_source, exact_records = _first_available_rows(
            existing,
            fetch_artifact_bytes,
            ["reports/csv/pdcch6gr_dmrs_locations.csv"],
        )
        exact_rows: list[dict[str, Any]] = []
        for row in exact_records:
            slot = _row_float(row, "SlotIndex", "Slot")
            symbol = _row_float(row, "Symbol", "SymbolIndex")
            subcarrier = _row_float(row, "Subcarrier", "SubcarrierIndex")
            port = _row_float(row, "Port", "PortIndex")
            if slot is None or symbol is None or subcarrier is None:
                continue
            slot_i = int(round(float(slot)))
            symbol_i = int(round(float(symbol)))
            exact_rows.append(
                {
                    "absolute_symbol": slot_i * 14 + symbol_i,
                    "slot_index": slot_i,
                    "symbol_index": symbol_i,
                    "subcarrier_index": int(round(float(subcarrier))),
                    "port_index": int(round(float(port or 0.0))),
                    "occupancy_count": 1.0,
                }
            )
        if exact_rows:
            x_labels, y_labels, matrix = _grid_rows_to_heatmap(
                exact_rows, "absolute_symbol", "subcarrier_index", "occupancy_count"
            )
            image_bytes, image_status = _render_heatmap_or_projection_svg(
                chart_name,
                "Exact PDCCH DM-RS RE occupancy from persisted slot, symbol, subcarrier and port coordinates.",
                x_labels,
                y_labels,
                matrix,
                [f"source={exact_source}", f"dmrs_re_rows={len(exact_rows)}"],
                "Absolute OFDM symbol (14*slot + symbol)",
                "Subcarrier",
            )
            csv_rows = [
                {
                    **row,
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "source_table_logical_path": exact_source,
                }
                for row in exact_rows
            ]
            return {
                "csv_bytes": _encode_dict_rows(
                    [
                        "run_id", "chart_name", "absolute_symbol", "slot_index",
                        "symbol_index", "subcarrier_index", "port_index",
                        "occupancy_count", "source_table_logical_path",
                    ],
                    csv_rows,
                ),
                "img_bytes": image_bytes,
                "csv_status": "specialized_runtime_pdcch_exact_dmrs_dataset",
                "image_status": image_status,
                "source_table_path": exact_source,
                "source_row_count": len(exact_records),
                "note": "PDCCH DM-RS occupancy uses exact exported RE coordinates; no occupancy was inferred.",
            }
    source_path, records = _first_available_rows(
        existing,
        fetch_artifact_bytes,
        [
            "reports/csv/pdcch6gr_per_candidate_results.csv",
            "air_interface/csv/pdcch_trials.csv",
            "control/csv/pdcch_trials.csv",
            "reports/csv/live_pdcch_stage_table.csv",
        ],
    )
    if not records:
        return None
    if chart_key == "aggregation level distribution":
        counts = Counter()
        for row in records:
            al = _row_float(row, "AggregationLevel", "aggregation_level")
            if al is not None and math.isfinite(float(al)):
                counts[int(round(float(al)))] += 1
        if not counts:
            return None
        dataset, summary = _bar_dataset_from_named_values("Aggregation level", "Count", [(str(al), float(count)) for al, count in sorted(counts.items())])
        csv_rows = [{"run_id": run_id, "chart_name": chart_name, "aggregation_level": al, "count": count, "source_table_logical_path": source_path} for al, count in sorted(counts.items())]
        return {
            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "aggregation_level", "count", "source_table_logical_path"], csv_rows),
            "img_bytes": _render_svg_plot(chart_name, "PDCCH aggregation-level distribution from persisted control trials.", dataset, summary),
            "csv_status": "specialized_runtime_pdcch_dataset",
            "image_status": "generated_specialized_runtime_summary_svg",
            "source_table_path": source_path,
            "source_row_count": len(records),
            "note": "Aggregation-level distribution uses exported PDCCH AggregationLevel fields.",
        }
    if chart_key == "pdcch decode success/failure trend if applicable":
        grouped: dict[int, list[float]] = defaultdict(list)
        for idx, row in enumerate(records, start=1):
            ok = _row_flag(row, "CRCPass", "DecodeSuccess", "Status")
            if ok is None:
                continue
            slot = _row_float(row, "Slot")
            if slot is None:
                slot = float(idx)
            grouped[int(round(slot))].append(1.0 if ok else 0.0)
        points = [[float(slot), sum(vals) / len(vals)] for slot, vals in sorted(grouped.items()) if vals]
        if not points:
            return None
        csv_rows = [{"run_id": run_id, "chart_name": chart_name, "slot": slot, "decode_success_rate": value, "source_table_logical_path": source_path} for slot, value in points]
        dataset = {
            "mode": "line",
            "x_label": "Slot/sample",
            "y_label": "PDCCH decode success rate",
            "points": points,
            "evidence_shape_policy": "observed_timeline",
            "sample_count": len(records),
        }
        return {
            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "slot", "decode_success_rate", "source_table_logical_path"], csv_rows),
            "img_bytes": _render_svg_plot(chart_name, "PDCCH decode success trend from persisted control trials.", dataset, [f"source={source_path}", f"points={len(points)}"]),
            "csv_status": "specialized_runtime_pdcch_dataset",
            "image_status": "generated_specialized_runtime_summary_svg",
            "source_table_path": source_path,
            "source_row_count": len(records),
            "note": "PDCCH decode trend uses explicit CRC/decode/status fields only.",
        }
    dmrs_rows: list[dict[str, Any]] = []
    for row in records:
        slot = _row_float(row, "Slot")
        cell = _row_text(row, "CellID", "BaseStationID", "ServingCell") or "cell"
        dmrs_re = _row_float(row, "DMRSRECount", "PDCCHDMRSRECount", "dmrs_re_count")
        if slot is None or dmrs_re is None:
            continue
        dmrs_rows.append({"slot": int(round(slot)), "cell_id": cell, "occupancy_value": float(dmrs_re), "dmrs_re_count": float(dmrs_re)})
    if not dmrs_rows:
        return None
    x_labels, y_labels, matrix = _grid_rows_to_heatmap(dmrs_rows, "slot", "cell_id", "occupancy_value")
    csv_rows = [{**row, "run_id": run_id, "chart_name": chart_name, "source_table_logical_path": source_path} for row in dmrs_rows]
    if len(x_labels) < 2 or len(y_labels) < 2:
        by_slot: dict[int, list[float]] = defaultdict(list)
        for row in dmrs_rows:
            by_slot[int(row["slot"])].append(float(row["occupancy_value"]))
        projection = {
            "mode": "line",
            "x_label": "Slot",
            "y_label": "PDCCH DMRS RE count",
            "points": [[float(slot), sum(values) / len(values)] for slot, values in sorted(by_slot.items())],
            "evidence_shape_policy": "observed_timeline",
            "sample_count": len(dmrs_rows),
        }
        image_bytes = _render_svg_plot(
            chart_name,
            "Exact one-cell PDCCH DMRS occupancy projection; no second spatial axis was invented.",
            projection,
            [f"source={source_path}", f"rows={len(dmrs_rows)}", "view=slot_projection"],
        )
        image_status = "generated_specialized_runtime_summary_svg"
    else:
        image_bytes = _render_heatmap_svg(chart_name, "PDCCH DMRS RE occupancy by slot/cell from exported control rows.", x_labels, y_labels, matrix, [f"source={source_path}", f"rows={len(dmrs_rows)}"], "Slot", "Cell")
        image_status = "generated_specialized_runtime_heatmap_svg"
    return {
        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "slot", "cell_id", "dmrs_re_count", "source_table_logical_path"], csv_rows),
        "img_bytes": image_bytes,
        "csv_status": "specialized_runtime_pdcch_dataset",
        "image_status": image_status,
        "source_table_path": source_path,
        "source_row_count": len(records),
        "note": "PDCCH DMRS occupancy requires exported DMRS RE count columns; no occupancy is inferred from unrelated CCE counts.",
    }


def _pdcch_detection_probability_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    chart_key = str(chart_name or "").strip().lower()
    metric_fields = {
        "p_fa": ("mean_FalseAlarmProbability", "FalseAlarmProbability"),
        "far": ("mean_FalseAlarmProbability", "FalseAlarmProbability"),
        "p_md": ("mean_MissProbability", "MissProbability"),
        "p_d": ("mean_DetectionProbability", "DetectionProbability"),
    }
    if chart_key not in metric_fields:
        return None
    source_path, records = _first_available_rows(
        existing,
        fetch_artifact_bytes,
        [
            "reports/csv/pdcch6gr_summary_by_snr.csv",
            "reports/csv/pdcch6gr_summary_by_scenario.csv",
            "reports/csv/pdcch_control_outputs.csv",
        ],
    )
    if not records:
        return None
    primary_field, fallback_field = metric_fields[chart_key]
    points: list[list[float]] = []
    csv_rows: list[dict[str, Any]] = []
    for index, row in enumerate(records, start=1):
        value = _row_float(row, primary_field, fallback_field)
        if value is None or not math.isfinite(float(value)):
            continue
        snr = _row_float(row, "SNRdB", "AppliedSNR_dB", "ConfiguredSNR_dB")
        if snr is None:
            snr = float(index)
        probability = float(value)
        if probability < 0.0 or probability > 1.0:
            continue
        points.append([float(snr), probability])
        csv_rows.append(
            {
                "run_id": run_id,
                "chart_name": chart_name,
                "snr_db": float(snr),
                "probability": probability,
                "metric_field": primary_field,
                "source_table_logical_path": source_path,
            }
        )
    if not points:
        return None
    points.sort(key=lambda point: point[0])
    dataset = {
        "mode": "line" if len(points) > 1 else "bar",
        "x_label": "SNR (dB)" if _row_float(records[0], "SNRdB") is not None else "Operating point",
        "y_label": chart_name,
        "points": points,
        "evidence_shape_policy": "observed_probability_points",
        "sample_count": len(records),
    }
    return {
        "csv_bytes": _encode_dict_rows(
            ["run_id", "chart_name", "snr_db", "probability", "metric_field", "source_table_logical_path"],
            csv_rows,
        ),
        "img_bytes": _render_svg_plot(
            chart_name,
            "Observed PDCCH detection statistic from persisted waveform-study aggregation.",
            dataset,
            [f"source={source_path}", f"operating_points={len(points)}", f"metric={primary_field}"],
        ),
        "csv_status": "specialized_runtime_pdcch_probability_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": source_path,
        "source_row_count": len(records),
        "note": "Probability values are copied from persisted PDCCH waveform-study aggregates; no curve interpolation is performed.",
    }


def _ssb_index_timeline_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    if str(chart_name or "").strip().lower() != "ssb index timeline":
        return None
    source_path, records = _first_available_rows(
        existing,
        fetch_artifact_bytes,
        ["reports/csv/live_ssb_stage_table.csv", "air_interface/csv/pbch_trials.csv", "control/csv/cell_search_trials.csv"],
    )
    if not records:
        return None
    csv_rows: list[dict[str, Any]] = []
    points: list[list[float]] = []
    for idx, row in enumerate(records, start=1):
        slot = _row_float(row, "Slot")
        if slot is None:
            slot = float(idx)
        ssb = _row_float(row, "SSBIndex", "SSBIdx", "SelectedBeamIndex")
        if ssb is None:
            match = re.search(r"SSBIdx=(\d+)", _row_text(row, "Notes"))
            if match:
                ssb = float(match.group(1))
        if ssb is None:
            continue
        points.append([float(slot), float(ssb)])
        csv_rows.append({"run_id": run_id, "chart_name": chart_name, "slot": slot, "ssb_index": ssb, "source_table_logical_path": source_path})
    if not csv_rows:
        return None
    unique_slots = _unique_numeric_count([point[0] for point in points])
    if unique_slots < 2:
        chart_points = [[float(index), float(point[1])] for index, point in enumerate(points, start=1)]
        x_label = "Observed SSB event index"
    else:
        chart_points = points
        x_label = "Slot/sample"
    dataset = {
        "mode": "scatter" if len(points) < 3 else "line",
        "x_label": x_label,
        "y_label": "SSB index",
        "points": chart_points[:MAX_PREVIEW_ROWS],
        "evidence_shape_policy": "observed_timeline",
        "sample_count": len(csv_rows),
    }
    summary = [f"source={source_path}", f"rows={len(csv_rows)}"]
    unique_ssb = _unique_numeric_count([point[1] for point in points])
    img_bytes = _render_svg_plot(
        chart_name,
        "SSB index events parsed from runtime SSB/PBCH stage rows; sparse observations are shown as measured points.",
        dataset,
        summary + [f"unique_slots={unique_slots}", f"unique_ssb={unique_ssb}"],
    )
    return {
        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "slot", "ssb_index", "source_table_logical_path"], csv_rows),
        "img_bytes": img_bytes,
        "csv_status": "specialized_runtime_ssb_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": source_path,
        "source_row_count": len(records),
        "note": "SSB index timeline uses exported SSBIndex/SSBIdx fields or the SSBIdx token in runtime Notes.",
    }


def _csirs_map_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    source_path = "air_interface/csv/csi_rs_trials.csv"
    _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path)
    if not records:
        return None
    chosen_cell = _selected_cell(records, "CellID", "BaseStationID", "ServingCell")
    filtered = [row for row in records if not chosen_cell or _row_text(row, "CellID", "BaseStationID", "ServingCell") == chosen_cell]
    slot_counts: Counter[int] = Counter()
    for row in filtered:
        slot_v = _row_float(row, "Slot")
        if slot_v is None:
            continue
        slot_counts[int(round(slot_v))] += 1
    if not slot_counts:
        return None
    selected_slot = max(slot_counts.items(), key=lambda item: (item[1], -item[0]))[0]
    seen_resources: set[tuple[Any, ...]] = set()
    grid_rows: list[dict[str, Any]] = []
    rsrp_values: list[float] = []
    for row in filtered:
        slot_v = _row_float(row, "Slot")
        if slot_v is None or int(round(slot_v)) != selected_slot:
            continue
        rb_start = _row_float(row, "RBOffset", "PRBStart")
        num_rb = _row_float(row, "NumRB", "AllocatedPRBCount", "PRBs")
        if rb_start is None or num_rb is None or num_rb <= 0:
            continue
        symbols = _parse_index_tokens(_row_text(row, "SymbolLocations")) or [0]
        resource_key = (
            _row_text(row, "CellID", "BaseStationID", "ServingCell"),
            int(round(slot_v)),
            _row_text(row, "ResourceSetID"),
            _row_text(row, "ResourceID"),
            int(round(rb_start)),
            int(round(num_rb)),
            tuple(symbols),
        )
        if resource_key in seen_resources:
            continue
        seen_resources.add(resource_key)
        nre_value = _row_float(row, "NRE")
        tile_value = float(nre_value) / max(int(round(num_rb)) * max(len(symbols), 1) * 12, 1) if nre_value is not None else 1.0
        rsrp_value = _row_float(row, "MeasurementRSRP_dB")
        if rsrp_value is not None:
            rsrp_values.append(float(rsrp_value))
        for symbol_index in symbols:
            for rb_index in range(int(round(rb_start)), int(round(rb_start + num_rb))):
                grid_rows.append(
                    {
                        "cell_id": chosen_cell,
                        "slot": selected_slot,
                        "symbol_index": int(symbol_index),
                        "rb_index": rb_index,
                        "occupancy_value": tile_value,
                        "resource_id": _row_text(row, "ResourceID"),
                        "resource_set_id": _row_text(row, "ResourceSetID"),
                        "source_table_logical_path": source_path,
                    }
                )
    if not grid_rows:
        return None
    x_labels, y_labels, matrix = _grid_rows_to_heatmap(grid_rows, "symbol_index", "rb_index", "occupancy_value")
    summary = [
        f"source={source_path}",
        f"selected_cell={chosen_cell or 'all'}",
        f"selected_slot={selected_slot}",
        f"unique_resources={len(seen_resources)}",
    ]
    if rsrp_values:
        summary.append(f"mean_measurement_rsrp_db={sum(rsrp_values) / len(rsrp_values):.3f}")
    summary.append("exact_subcarrier_pattern=normalized_from_exported_nre_per_rb_symbol")
    occupied_cells = sum(1 for row in matrix for value in row if value > 0.0)
    value_sum = sum(value for row in matrix for value in row)
    img_bytes, image_status = _render_heatmap_or_projection_svg(
        chart_name,
        "CSI-RS resource occupancy for the most active cell/slot, normalized from the exported runtime mapping evidence.",
        x_labels,
        y_labels,
        matrix,
        summary,
        "OFDM symbol",
        "RB index",
    )
    return {
        "csv_bytes": _encode_dict_rows(
            [
                "run_id",
                "chart_name",
                "cell_id",
                "slot",
                "symbol_index",
                "rb_index",
                "occupancy_value",
                "resource_id",
                "resource_set_id",
                "source_table_logical_path",
            ],
            [{**row, "run_id": run_id, "chart_name": chart_name} for row in grid_rows],
        ),
        "img_bytes": img_bytes,
        "csv_status": "specialized_runtime_grid_dataset",
        "image_status": image_status,
        "source_table_path": source_path,
        "source_row_count": len(grid_rows),
        # A configured CSI-RS resource can legitimately occupy one OFDM
        # symbol with uniform density across every allocated RB.  Uniformity
        # is the measured result here, not a reason-card or fabricated flat
        # metric, so the raster-level low-information heuristic must not
        # discard it.
        "uniform_runtime_evidence_is_valid": True,
        "note": "CSI-RS map derived from exported CSI-RS runtime rows without fabricating RE-level detail beyond the exported RB/symbol span.",
    }


def _srs_map_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    source_path = "air_interface/csv/srs_trials.csv"
    _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path)
    if not records:
        return None
    chosen_cell = _selected_cell(records, "BaseStationID", "TRSAssociatedCell", "ServingCell")
    grid_rows: list[dict[str, Any]] = []
    nmse_values: list[float] = []
    for row in records:
        cell_value = _row_text(row, "BaseStationID", "TRSAssociatedCell", "ServingCell")
        if chosen_cell and cell_value and cell_value != chosen_cell:
            continue
        slot_v = _row_float(row, "Slot")
        ue_v = _row_float(row, "UEIndex", "UEID", "RNTI")
        if slot_v is None or ue_v is None:
            continue
        success_flag = _row_flag(row, "SuccessFlag", "DecodeSuccess")
        if success_flag is None:
            status_text = _row_text(row, "Status").strip().lower()
            success_flag = status_text in {"pass", "detected", "success"} if status_text else True
        nmse_db = _row_float(row, "NMSE_dB")
        if nmse_db is not None:
            nmse_values.append(float(nmse_db))
        grid_rows.append(
            {
                "slot": int(round(slot_v)),
                "ue_index": int(round(ue_v)),
                "occupancy_value": 1.0 if success_flag else 0.0,
                "nmse_db": "" if nmse_db is None else nmse_db,
                "success_flag": 1 if success_flag else 0,
                "source_table_logical_path": source_path,
            }
        )
    if not grid_rows:
        return None
    x_labels, y_labels, matrix = _grid_rows_to_heatmap(grid_rows, "slot", "ue_index", "occupancy_value")
    summary = [
        f"source={source_path}",
        f"selected_cell={chosen_cell or 'all'}",
        f"runtime_rows={len(grid_rows)}",
        f"successful_rows={sum(int(row['success_flag']) for row in grid_rows)}",
    ]
    if nmse_values:
        summary.append(f"mean_nmse_db={sum(nmse_values) / len(nmse_values):.3f}")
    summary.append("exact_srs_rb_symbol_map=not_exported_by_runtime")
    image_bytes, image_status = _render_heatmap_or_projection_svg(
        chart_name,
        "Exact SRS RE placement is not exported for this run, so the view shows truthful per-UE SRS observation success by slot.",
        x_labels, y_labels, matrix, summary, "Slot", "UE index",
    )
    return {
        "csv_bytes": _encode_dict_rows(
            ["run_id", "chart_name", "slot", "ue_index", "occupancy_value", "nmse_db", "success_flag", "source_table_logical_path"],
            [{**row, "run_id": run_id, "chart_name": chart_name} for row in grid_rows],
        ),
        "img_bytes": image_bytes,
        "csv_status": "specialized_runtime_srs_dataset",
        "image_status": "generated_specialized_runtime_heatmap_svg",
        "source_table_path": source_path,
        "source_row_count": len(grid_rows),
        "note": "SRS map derived from truthful per-UE/per-slot SRS runtime observations without inventing absent RE-level coordinates.",
    }


def _metric_rows_by_exact_x(
    rows: list[tuple[float, float]],
    *,
    x_label: str,
    y_label: str,
    chart_name: str,
    run_id: int,
    source_path: str,
) -> tuple[bytes, dict[str, Any]]:
    grouped: dict[float, list[float]] = defaultdict(list)
    for x_val, y_val in rows:
        grouped[round(float(x_val), 6)].append(float(y_val))
    points = [[float(x_val), sum(values) / max(len(values), 1)] for x_val, values in sorted(grouped.items())]
    csv_rows = [
        {
            "run_id": run_id,
            "chart_name": chart_name,
            x_label: point[0],
            y_label: point[1],
            "source_table_logical_path": source_path,
        }
        for point in points
    ]
    preferred_mode = "scatter" if len(points) > 18 else "line"
    dataset = {"mode": _honest_chart_mode(points, preferred_mode), "x_label": x_label, "y_label": y_label, "points": points}
    return _encode_dict_rows(["run_id", "chart_name", x_label, y_label, "source_table_logical_path"], csv_rows), dataset


def _metric_rows_by_binned_x(
    rows: list[tuple[float, float]],
    *,
    x_label: str,
    y_label: str,
    chart_name: str,
    run_id: int,
    source_path: str,
    bin_width: float = 1.0,
    max_bins: int = 40,
) -> tuple[bytes, dict[str, Any]]:
    filtered = [(float(x), float(y)) for x, y in rows if math.isfinite(float(x)) and math.isfinite(float(y))]
    if not filtered:
        return b"", {"mode": "line", "x_label": x_label, "y_label": y_label, "points": []}
    min_x = min(x for x, _y in filtered)
    max_x = max(x for x, _y in filtered)
    if not (math.isfinite(bin_width) and bin_width > 0):
        bin_width = 1.0
    if math.isclose(min_x, max_x):
        buckets: dict[int, list[float]] = {0: [y for _x, y in filtered]}
        bucket_edges = {0: (min_x, max_x)}
    else:
        span = max_x - min_x
        bins = max(1, min(max_bins, int(math.ceil(span / bin_width))))
        width = span / bins if bins > 0 else bin_width
        buckets = defaultdict(list)
        bucket_edges = {}
        for x_val, y_val in filtered:
            idx = min(bins - 1, max(0, int((x_val - min_x) / max(width, 1e-12))))
            buckets[idx].append(y_val)
        for idx in buckets:
            lo = min_x + width * idx
            hi = min_x + width * (idx + 1)
            bucket_edges[idx] = (lo, hi)
    points: list[list[float]] = []
    csv_rows: list[dict[str, Any]] = []
    for idx in sorted(buckets):
        values = buckets[idx]
        if not values:
            continue
        lo, hi = bucket_edges[idx]
        center = (float(lo) + float(hi)) / 2.0
        mean_value = sum(values) / max(len(values), 1)
        points.append([center, mean_value])
        csv_rows.append(
            {
                "run_id": run_id,
                "chart_name": chart_name,
                x_label: center,
                y_label: mean_value,
                "x_bin_min": float(lo),
                "x_bin_max": float(hi),
                "sample_count": len(values),
                "source_table_logical_path": source_path,
            }
        )
    dataset = {"mode": _honest_chart_mode(points), "x_label": x_label, "y_label": y_label, "points": points}
    header = ["run_id", "chart_name", x_label, y_label, "x_bin_min", "x_bin_max", "sample_count", "source_table_logical_path"]
    return _encode_dict_rows(header, csv_rows), dataset


def _timeline_axis_value(row: dict[str, str], fallback_index: int) -> float:
    timestamp = _row_float(row, "TimestampSim_ms", "Time_ms")
    if timestamp is not None:
        return float(timestamp)
    slot = _row_float(row, "Slot", "CanonicalSlot", "ScheduledAbsoluteSlot")
    if slot is not None:
        return float(slot)
    return float(fallback_index)


def _truthy_decode_token(value: str) -> bool:
    return str(value or "").strip().lower() in {"1", "true", "yes", "ok", "pass", "passed", "ack", "success"}


def _runtime_throughput_timeline_chart(
    chart_name: str,
    trial_sources: list[tuple[str, list[dict[str, str]]]],
    run_id: int,
) -> dict[str, Any] | None:
    y_field = "Goodput_Mbps" if "goodput" in chart_name.lower() else "Throughput_Mbps"
    y_label = "Goodput (Mbps)" if y_field == "Goodput_Mbps" else "Throughput (Mbps)"
    grouped: dict[tuple[str, float], dict[str, Any]] = {}
    source_paths: list[str] = []
    samples = 0
    for source_path, rows in trial_sources:
        if source_path not in source_paths:
            source_paths.append(source_path)
        direction = "DL" if "dl_pdsch" in source_path else "UL"
        for row_index, row in enumerate(rows, start=1):
            value = _row_float(row, y_field, "MeasuredThroughput_Mbps", "OfferedThroughput_Mbps", "Goodput_Mbps")
            if value is None:
                continue
            x_val = _timeline_axis_value(row, row_index)
            key = (direction, round(float(x_val), 9))
            bucket = grouped.setdefault(
                key,
                {
                    "direction": direction,
                    "slot_or_time": float(x_val),
                    "metric_sum": 0.0,
                    "sample_count": 0,
                    "source_table_logical_path": source_path,
                },
            )
            bucket["metric_sum"] += float(value)
            bucket["sample_count"] += 1
            samples += 1
    if not grouped:
        return None
    rows = []
    series_map: dict[str, list[list[float]]] = defaultdict(list)
    for (_direction, _x_val), bucket in sorted(grouped.items(), key=lambda item: (item[0][0], item[0][1])):
        direction = str(bucket["direction"])
        x_val = float(bucket["slot_or_time"])
        metric_sum = float(bucket["metric_sum"])
        sample_count = int(bucket["sample_count"])
        rows.append(
            {
                "run_id": run_id,
                "chart_name": chart_name,
                "series_name": direction,
                "chart_mode": "line",
                "x_label": "Slot / time sample",
                "y_label": y_label,
                "x_value": x_val,
                "y_value": metric_sum,
                "direction": direction,
                "slot_or_time": x_val,
                "aggregate_mbps": metric_sum,
                "sample_count": sample_count,
                "aggregation": "sum_over_runtime_trials_in_same_direction_and_slot",
                "source_table_logical_path": bucket["source_table_logical_path"],
            }
        )
        series_map[direction].append([x_val, metric_sum])
    series = [
        {"name": direction, "points": _downsample_points(points, 160)}
        for direction, points in sorted(series_map.items())
        if points
    ]
    if not series:
        return None
    render_mode = _honest_chart_mode([point for item in series for point in item["points"]])
    for row in rows:
        row["chart_mode"] = render_mode
    return {
        "csv_bytes": _encode_dict_rows(
            [
                "run_id",
                "chart_name",
                "series_name",
                "chart_mode",
                "x_label",
                "y_label",
                "x_value",
                "y_value",
                "direction",
                "slot_or_time",
                "aggregate_mbps",
                "sample_count",
                "aggregation",
                "source_table_logical_path",
            ],
            rows,
        ),
        "img_bytes": _render_multi_series_svg(
            chart_name,
            "Slot/time throughput trend derived by summing persisted waveform trial rates per direction and scheduling instant.",
            series,
            [f"samples={samples}", f"source={ '|'.join(source_paths) }"],
            x_label="Slot / time sample",
            y_label=y_label,
            mode=render_mode,
        ),
        "csv_status": "specialized_runtime_throughput_timeline_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": "|".join(source_paths),
        "source_row_count": samples,
        "note": "Timeline derived from truthful PDSCH/PUSCH trial rows; no missing slots or users are fabricated.",
    }


def _runtime_bler_vs_mcs_chart(
    trial_rows: list[tuple[str, dict[str, str]]],
    run_id: int,
) -> dict[str, Any] | None:
    grouped: dict[int, list[float]] = defaultdict(list)
    source_token = ""
    for source_path, row in trial_rows:
        mcs = _row_float(row, "MCS", "MCSIndex", "SelectedMCS")
        bler = _trial_row_bler(row)
        if mcs is None or bler is None:
            continue
        grouped[int(round(float(mcs)))].append(float(bler))
        source_token = source_token or source_path
    if not grouped:
        return None
    csv_rows = []
    points = []
    sample_count = 0
    for mcs, values in sorted(grouped.items()):
        mean_bler = sum(values) / len(values)
        sample_count += len(values)
        points.append([float(mcs), float(mean_bler)])
        csv_rows.append(
            {
                "run_id": run_id,
                "chart_name": "BLER vs MCS",
                "mcs": mcs,
                "bler": mean_bler,
                "sample_count": len(values),
                "source_table_logical_path": source_token or "multiple_runtime_trials",
            }
        )
    dataset = {
        "mode": "bar" if len(points) == 1 else _honest_chart_mode(points),
        "x_label": "MCS",
        "y_label": "BLER",
        "points": points,
        "evidence_shape_policy": "operating_point" if len(points) == 1 else "observed_relation",
        "sample_count": sample_count,
    }
    return {
        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "mcs", "bler", "sample_count", "source_table_logical_path"], csv_rows),
        "img_bytes": _render_svg_plot("BLER vs MCS", "BLER by selected runtime MCS from persisted waveform trials.", dataset, [f"samples={sample_count}"]),
        "csv_status": "specialized_runtime_reliability_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": source_token or "multiple_runtime_trials",
        "source_row_count": sample_count,
        "note": "BLER-vs-MCS derived from actual CRC outcome rows grouped by selected runtime MCS.",
    }


def _runtime_latency_cdf_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    candidates = [
        "air_interface/csv/dl_pdsch_trials.csv",
        "air_interface/csv/ul_pusch_trials.csv",
        "air_interface/csv/pdcch_trials.csv",
        "air_interface/csv/pucch_trials.csv",
        "reports/csv/live_pdsch_stage_table.csv",
        "reports/csv/live_pusch_stage_table.csv",
        "reports/csv/live_pdcch_stage_table.csv",
        "reports/csv/live_pucch_stage_table.csv",
        "system/csv/system_algo_processing.csv",
    ]
    latency_rows: list[dict[str, Any]] = []
    source_counts: Counter[str] = Counter()
    for source_path, rows in _all_available_rows(existing, fetch_artifact_bytes, candidates):
        for row in rows:
            latency = _row_float(row, "Latency_ms", "ComputeLatency_ms", "DecodeLatency_ms", "ProcedureDelay_ms", "StageLatency_ms", "ControlLatency_ms")
            if latency is None:
                continue
            latency_rows.append(
                {
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "latency_ms": float(latency),
                    "source_table_logical_path": source_path,
                }
            )
            source_counts[source_path] += 1
    if not latency_rows:
        return None
    values = sorted(float(row["latency_ms"]) for row in latency_rows)
    points = [[value, (idx + 1) / len(values)] for idx, value in enumerate(values)]
    dataset = {"mode": "line", "x_label": "Latency (ms)", "y_label": "CDF", "points": _downsample_points(points, 180)}
    for idx, row in enumerate(sorted(latency_rows, key=lambda item: float(item["latency_ms"])), start=1):
        row["cdf_probability"] = idx / len(latency_rows)
        row["chart_mode"] = "line"
        row["x_label"] = "Latency (ms)"
        row["y_label"] = "CDF"
        row["x_value"] = row["latency_ms"]
        row["y_value"] = row["cdf_probability"]
    sources = "|".join(source_counts.keys())
    return {
        "csv_bytes": _encode_dict_rows(
            ["run_id", "chart_name", "chart_mode", "x_label", "y_label", "x_value", "y_value", "latency_ms", "cdf_probability", "source_table_logical_path"],
            latency_rows,
        ),
        "img_bytes": _render_svg_plot(chart_name, "Latency CDF derived from persisted trial/stage latency fields.", dataset, [f"samples={len(values)}", f"sources={len(source_counts)}"]),
        "csv_status": "specialized_runtime_latency_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": sources,
        "source_row_count": len(values),
        "note": "Latency CDF uses only real exported latency fields; missing stages are not backfilled.",
    }


def _histogram_points(values: list[float], max_bins: int = 18) -> list[list[float]]:
    clean = [float(value) for value in values if math.isfinite(float(value))]
    if not clean:
        return []
    min_v = min(clean)
    max_v = max(clean)
    if math.isclose(min_v, max_v):
        return [[min_v, float(len(clean))]]
    bins = max(1, min(max_bins, int(math.ceil(math.sqrt(len(clean))))))
    width = (max_v - min_v) / bins
    counts = [0 for _ in range(bins)]
    for value in clean:
        idx = min(bins - 1, max(0, int((value - min_v) / max(width, 1e-18))))
        counts[idx] += 1
    return [[min_v + width * (idx + 0.5), float(count)] for idx, count in enumerate(counts) if count > 0]


def _runtime_energy_histogram_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    values: list[float] = []
    csv_rows: list[dict[str, Any]] = []
    source_counts: Counter[str] = Counter()
    for source_path, rows in _all_available_rows(
        existing,
        fetch_artifact_bytes,
        ["rf/csv/energy_timeline_trace.csv", "reports/csv/live_energy_efficiency_table.csv", "analytics/csv/energy_efficiency_analytics.csv"],
    ):
        for row in rows:
            value = _row_float(row, "EnergyPerBit_J", "energy_per_bit_j", "Energy_per_bit_J", "UEEnergyPerBit_J", "GNBEnergyPerBit_J")
            if value is None:
                energy = _row_float(row, "Energy_J")
                bits = _row_float(row, "SuccessfulBits", "GoodBits")
                if energy is not None and bits is not None and bits > 0:
                    value = float(energy) / float(bits)
            if value is None or value <= 0:
                continue
            values.append(float(value))
            csv_rows.append(
                {
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "energy_per_bit_j": float(value),
                    "source_table_logical_path": source_path,
                }
            )
            source_counts[source_path] += 1
    if not values:
        return None
    points = _histogram_points(values, 18)
    if not points:
        return None
    dataset = {"mode": "bar", "x_label": "Energy per bit (J)", "y_label": "Count", "points": points}
    bin_rows = [
        {
            "run_id": run_id,
            "chart_name": chart_name,
            "chart_mode": "bar",
            "x_label": "Energy per bit (J)",
            "y_label": "Count",
            "point_index": idx,
            "x_value": center,
            "y_value": count,
            "sample_count": len(values),
            "source_table_logical_path": "|".join(source_counts.keys()),
        }
        for idx, (center, count) in enumerate(points, start=1)
    ]
    return {
        "csv_bytes": _encode_dict_rows(
            ["run_id", "chart_name", "chart_mode", "x_label", "y_label", "point_index", "x_value", "y_value", "sample_count", "source_table_logical_path"],
            bin_rows,
        ),
        "img_bytes": _render_svg_plot(chart_name, "Energy-per-bit histogram derived from runtime energy and successful-bit evidence.", dataset, [f"samples={len(values)}", f"sources={len(source_counts)}"]),
        "csv_status": "specialized_runtime_energy_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": "|".join(source_counts.keys()),
        "source_row_count": len(values),
        "note": "Energy-per-bit values are directly exported or computed as Energy_J/SuccessfulBits when both fields are present.",
    }


def _runtime_power_scatter_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    chart_key = chart_name.lower()
    if "bandwidth" in chart_key:
        x_names = ("ActiveBWFraction", "ActiveBandwidthFraction", "ActiveBW")
        x_label = "Active bandwidth fraction"
    else:
        x_names = ("ActiveRank", "Rank", "Layers")
        x_label = "Active rank"
    pairs: list[tuple[float, float]] = []
    csv_rows: list[dict[str, Any]] = []
    source_counts: Counter[str] = Counter()
    for source_path, rows in _all_available_rows(existing, fetch_artifact_bytes, ["rf/csv/energy_timeline_trace.csv", "reports/csv/live_power_runtime_table.csv"]):
        for row in rows:
            x_val = _row_float(row, *x_names)
            y_val = _row_float(row, "Power_W", "TxPower_W", "BBPower_W", "RFPower_W")
            if x_val is None or y_val is None:
                continue
            pairs.append((float(x_val), float(y_val)))
            csv_rows.append(
                {
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "chart_mode": "scatter",
                    "x_label": x_label,
                    "y_label": "Power (W)",
                    "x_value": float(x_val),
                    "y_value": float(y_val),
                    "power_w": float(y_val),
                    "source_table_logical_path": source_path,
                }
            )
            source_counts[source_path] += 1
    if not pairs:
        return None
    points = _bin_mean_points(pairs, 18)
    if not points:
        return None
    unique_x = _unique_numeric_count([point[0] for point in points])
    dataset = {
        "mode": "bar" if unique_x <= 1 else "scatter",
        "x_label": x_label,
        "y_label": "Mean power (W)",
        "points": points,
        "evidence_shape_policy": "operating_point" if unique_x <= 1 else "observed_relation",
        "sample_count": len(pairs),
    }
    return {
        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "chart_mode", "x_label", "y_label", "x_value", "y_value", "power_w", "source_table_logical_path"], csv_rows),
        "img_bytes": _render_svg_plot(chart_name, "Power relationship derived from runtime energy timeline rows.", dataset, [f"samples={len(pairs)}", f"sources={len(source_counts)}"]),
        "csv_status": "specialized_runtime_power_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": "|".join(source_counts.keys()),
        "source_row_count": len(pairs),
        "note": "Power scatter uses exported ActiveBWFraction/ActiveRank and Power_W fields only.",
    }


def _select_runtime_antenna_config(
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
) -> dict[str, Any] | None:
    candidates = [
        "reports/csv/antenna_config_resolved.csv",
        "reports/csv/antenna_runtime_evidence.csv",
        "reports/csv/live_channel_state_tti.csv",
    ]
    for source_path, rows in _all_available_rows(existing, fetch_artifact_bytes, candidates):
        for row in rows:
            node_type = _row_text(row, "NodeType") or ("BS" if _row_float(row, "BSAntennaRows") is not None else "")
            if node_type and str(node_type).strip().upper() not in {"BS", "GNB", "BASESTATION"}:
                continue
            n_rows = _row_float(row, "NumRows", "BSAntennaRows")
            n_cols = _row_float(row, "NumCols", "BSAntennaCols")
            n_ports = _row_float(row, "NumPorts", "BSAntennaNumPorts", "PrecodingNumPorts", "num_ports")
            spacing_h = _row_float(row, "SpacingH_lambda", "BSAntennaSpacingH_lambda")
            spacing_v = _row_float(row, "SpacingV_lambda", "BSAntennaSpacingV_lambda")
            if n_rows is None or n_cols is None:
                continue
            n_rows_i = max(1, int(round(float(n_rows))))
            n_cols_i = max(1, int(round(float(n_cols))))
            return {
                "source_path": source_path,
                "node_type": str(node_type or "BS"),
                "array_type": _row_text(row, "ArrayType", "BSAntennaArrayType") or "runtime_array",
                "array_class": _row_text(row, "ArrayClass", "BSAntennaArrayClass"),
                "element_class": _row_text(row, "ElementClass", "BSAntennaElementClass"),
                "rows": n_rows_i,
                "cols": n_cols_i,
                "ports": max(1, int(round(float(n_ports)))) if n_ports is not None else n_rows_i * n_cols_i,
                "spacing_h": float(spacing_h) if spacing_h is not None else 0.5,
                "spacing_v": float(spacing_v) if spacing_v is not None else 0.5,
            }
    return None


def _runtime_antenna_layout_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    cfg = _select_runtime_antenna_config(existing, fetch_artifact_bytes)
    if cfg is None:
        return {
            "csv_bytes": _encode_csv(["run_id", "chart_name", "status", "reason"], [[run_id, chart_name, "unavailable_exact_reason", "No runtime antenna_config_resolved or antenna_runtime_evidence rows were exported."]]),
            "img_bytes": _render_reason_svg(chart_name, "Antenna layout requires runtime array geometry evidence.", ["No antenna geometry rows were available.", "No synthetic array layout was generated."]),
            "csv_status": "unavailable_exact_reason",
            "image_status": "generated_unavailable_reason_svg",
            "source_table_path": "reports/csv/antenna_config_resolved.csv|reports/csv/antenna_runtime_evidence.csv",
            "source_row_count": 0,
            "note": "Antenna layout was not materialized because the required runtime geometry evidence was absent.",
        }
    points: list[list[float]] = []
    rows: list[dict[str, Any]] = []
    n_rows = int(cfg["rows"])
    n_cols = int(cfg["cols"])
    spacing_h = float(cfg["spacing_h"])
    spacing_v = float(cfg["spacing_v"])
    element_index = 0
    for r in range(n_rows):
        for c in range(n_cols):
            element_index += 1
            y_lambda = (c - (n_cols - 1) / 2.0) * spacing_h
            z_lambda = (r - (n_rows - 1) / 2.0) * spacing_v
            points.append([y_lambda, z_lambda])
            rows.append(
                {
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "element_index": element_index,
                    "node_type": cfg["node_type"],
                    "array_type": cfg["array_type"],
                    "array_class": cfg["array_class"],
                    "element_class": cfg["element_class"],
                    "row_index": r + 1,
                    "col_index": c + 1,
                    "y_lambda": y_lambda,
                    "z_lambda": z_lambda,
                    "source_table_logical_path": cfg["source_path"],
                }
            )
    dataset = {
        "mode": "scatter",
        "x_label": "Horizontal position (lambda)",
        "y_label": "Vertical position (lambda)",
        "points": points,
        "evidence_shape_policy": "observed_geometry",
        "sample_count": len(rows),
    }
    return {
        "csv_bytes": _encode_dict_rows(
            ["run_id", "chart_name", "element_index", "node_type", "array_type", "array_class", "element_class", "row_index", "col_index", "y_lambda", "z_lambda", "source_table_logical_path"],
            rows,
        ),
        "img_bytes": _render_svg_plot(chart_name, "Runtime BS array element coordinates from antenna_config_resolved evidence.", dataset, [f"array={cfg['array_type']}", f"shape={n_rows}x{n_cols}", f"spacing={spacing_h:g}/{spacing_v:g} lambda"]),
        "csv_status": "specialized_runtime_antenna_layout_dataset",
        "image_status": "generated_specialized_runtime_antenna_svg",
        "source_table_path": str(cfg["source_path"]),
        "source_row_count": len(rows),
        "note": "Antenna layout uses only runtime antenna geometry rows; positions are in wavelengths.",
    }


def _runtime_antenna_radiation_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    sample_candidates = [
        "reports/csv/antenna_pattern_samples.csv",
        "beamforming/csv/antenna_pattern_samples.csv",
    ]
    sample_path, sample_rows = _first_available_rows(
        existing, fetch_artifact_bytes, sample_candidates
    )
    exact_rows = [
        row for row in sample_rows
        if _row_text(row, "truth_status").strip().lower()
        == "real_runtime_object_evidence"
        and _row_text(row, "PatternSource").strip()
        == "actual_CoupledTruthRuntime_phased_NRRectangularPanelArray"
        and _row_float(row, "Azimuth_deg") is not None
        and _row_float(row, "Elevation_deg") is not None
        and _row_float(row, "Directivity_dBi") is not None
    ]
    if exact_rows:
        node_keys = sorted({
            (_row_text(row, "NodeType"), _row_text(row, "NodeIndex"))
            for row in exact_rows
        })
        selected_node = node_keys[0]
        raster_rows = [
            row for row in exact_rows
            if (_row_text(row, "NodeType"), _row_text(row, "NodeIndex"))
            == selected_node
        ]
        azimuths = sorted({float(_row_float(row, "Azimuth_deg")) for row in raster_rows})
        elevations = sorted({float(_row_float(row, "Elevation_deg")) for row in raster_rows})
        sample_map = {
            (float(_row_float(row, "Elevation_deg")), float(_row_float(row, "Azimuth_deg"))):
            float(_row_float(row, "Directivity_dBi"))
            for row in raster_rows
        }
        directivity_values = list(sample_map.values())
        min_directivity = min(directivity_values)
        color_offset = -min_directivity + 1e-9 if min_directivity <= 0 else 0.0
        matrix = [
            [sample_map[(elevation, azimuth)] + color_offset for azimuth in azimuths]
            for elevation in elevations
        ]
        csv_rows = []
        for row in exact_rows:
            csv_rows.append({
                "run_id": run_id,
                "chart_name": chart_name,
                "node_type": _row_text(row, "NodeType"),
                "node_index": _row_text(row, "NodeIndex"),
                "base_station_id": _row_text(row, "BaseStationID"),
                "ue_index": _row_text(row, "UEIndex"),
                "frequency_hz": _row_text(row, "Frequency_Hz"),
                "azimuth_deg": _row_text(row, "Azimuth_deg"),
                "elevation_deg": _row_text(row, "Elevation_deg"),
                "directivity_dbi": _row_text(row, "Directivity_dBi"),
                "array_class": _row_text(row, "ArrayClass"),
                "element_class": _row_text(row, "ElementClass"),
                "element_model": _row_text(row, "ElementModel"),
                "boresight_azimuth_deg": _row_text(row, "BoresightAzimuth_deg"),
                "boresight_elevation_deg": _row_text(row, "BoresightElevation_deg"),
                "boresight_slant_deg": _row_text(row, "BoresightSlant_deg"),
                "pattern_kind": _row_text(row, "PatternKind"),
                "pattern_sha256": _row_text(row, "PatternSHA256"),
                "truth_status": _row_text(row, "truth_status"),
                "source_table_logical_path": sample_path,
            })
        return {
            "csv_bytes": _encode_dict_rows(
                [
                    "run_id", "chart_name", "node_type", "node_index",
                    "base_station_id", "ue_index", "frequency_hz",
                    "azimuth_deg", "elevation_deg", "directivity_dbi",
                    "array_class", "element_class", "element_model",
                    "boresight_azimuth_deg", "boresight_elevation_deg",
                    "boresight_slant_deg", "pattern_kind", "pattern_sha256",
                    "truth_status", "source_table_logical_path",
                ],
                csv_rows,
            ),
            "img_bytes": _render_heatmap_svg(
                chart_name,
                "Directivity sampled from the actual phased.NRRectangularPanelArray installed on the runtime channel.",
                [f"{value:g}" for value in azimuths],
                [f"{value:g}" for value in elevations],
                matrix,
                [
                    f"raster_node={selected_node[0]}-{selected_node[1]}",
                    f"frequency_hz={_row_text(raster_rows[0], 'Frequency_Hz')}",
                    f"array={_row_text(raster_rows[0], 'ArrayClass')}",
                    f"element={_row_text(raster_rows[0], 'ElementClass')}",
                    f"all_runtime_rows_in_csv={len(csv_rows)}",
                    f"color_offset={color_offset:.6g}",
                    f"source={sample_path}",
                    "selected_beam_taper=not_applied_separate_evidence",
                ],
                "Azimuth (deg)",
                "Elevation (deg)",
            ),
            "csv_status": "specialized_actual_runtime_antenna_pattern_dataset",
            "image_status": "generated_actual_runtime_antenna_pattern_heatmap_svg",
            "source_table_path": sample_path,
            "source_row_count": len(csv_rows),
            "source_mapping_status": "exact",
            "note": "The raster selects one declared runtime node; the CSV retains all BS/UE samples. Directivity color offset is visualization-only and explicitly reported.",
        }

    cfg = _select_runtime_antenna_config(existing, fetch_artifact_bytes)
    if cfg is None:
        return None
    element_class = str(cfg.get("element_class") or "").strip()
    if "isotropic" not in element_class.lower():
        reason = f"Runtime element class {element_class or 'unknown'} did not export sampled radiation-pattern gains."
        return {
            "csv_bytes": _encode_csv(["run_id", "chart_name", "status", "reason", "source_table_logical_path"], [[run_id, chart_name, "unavailable_exact_reason", reason, cfg["source_path"]]]),
            "img_bytes": _render_reason_svg(chart_name, "Radiation pattern requires element-pattern evidence.", [reason, "No synthetic non-isotropic element pattern was generated.", "Beam/array-factor charts are materialized separately from the element pattern."]),
            "csv_status": "unavailable_exact_reason",
            "image_status": "generated_unavailable_reason_svg",
            "source_table_path": str(cfg["source_path"]),
            "source_row_count": 0,
            "note": reason,
        }
    rows: list[dict[str, Any]] = []
    points: list[list[float]] = []
    for az in range(-180, 181, 5):
        gain_dbi = 0.0
        points.append([float(az), gain_dbi])
        rows.append(
            {
                "run_id": run_id,
                "chart_name": chart_name,
                "azimuth_deg": az,
                "element_gain_dbi": gain_dbi,
                "element_class": element_class,
                "source_table_logical_path": cfg["source_path"],
            }
        )
    dataset = {
        "mode": "line",
        "x_label": "Azimuth (deg)",
        "y_label": "Element gain (dBi)",
        "points": points,
        "evidence_shape_policy": "observed_timeline",
        "sample_count": len(rows),
    }
    return {
        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "azimuth_deg", "element_gain_dbi", "element_class", "source_table_logical_path"], rows),
        "img_bytes": _render_svg_plot(chart_name, "Configured phased.IsotropicAntennaElement radiation pattern.", dataset, ["element=isotropic", "gain=0 dBi all azimuths", "array factor shown in beam pattern chart"]),
        "csv_status": "specialized_runtime_antenna_radiation_dataset",
        "image_status": "generated_specialized_runtime_antenna_svg",
        "source_table_path": str(cfg["source_path"]),
        "source_row_count": len(rows),
        "note": "The runtime antenna element is isotropic, so the correct element radiation cut is flat 0 dBi. This is not a beamforming array-factor plot.",
    }


def _first_runtime_precoder_pmi(
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
) -> tuple[float, str, str]:
    candidates = [
        "beamforming/csv/beam_precoder_table.csv",
        "reports/csv/live_precoder_table.csv",
        "reports/csv/antenna_runtime_evidence.csv",
        "reports/csv/live_channel_state_tti.csv",
    ]
    for source_path, rows in _all_available_rows(existing, fetch_artifact_bytes, candidates):
        for row in rows:
            pmi = _row_float(row, "applied_precoder_pmi", "AppliedPrecoderPMI", "requested_precoder_pmi", "RequestedPrecoderPMI", "PMI")
            if pmi is not None and math.isfinite(float(pmi)):
                source = _row_text(row, "precoder_source", "PrecoderSource", "AppliedPrecoderSource") or "runtime_precoder"
                return float(pmi), source_path, source
    return 0.0, "", "default_first_precoder_when_no_runtime_pmi_row"


def _runtime_beam_pattern_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    cfg = _select_runtime_antenna_config(existing, fetch_artifact_bytes)
    if cfg is None:
        return None
    n_rows = int(cfg["rows"])
    n_cols = int(cfg["cols"])
    spacing_h = float(cfg["spacing_h"])
    spacing_v = float(cfg["spacing_v"])
    positions: list[tuple[float, float]] = []
    for r in range(n_rows):
        for c in range(n_cols):
            y_lambda = (c - (n_cols - 1) / 2.0) * spacing_h
            z_lambda = (r - (n_rows - 1) / 2.0) * spacing_v
            positions.append((y_lambda, z_lambda))
    if not positions:
        return None
    pmi, pmi_source_path, precoder_source = _first_runtime_precoder_pmi(existing, fetch_artifact_bytes)
    n_ports = len(positions)
    beam_idx = int(round(pmi)) % max(n_ports, 1)
    weights = [complex(math.cos(-2.0 * math.pi * n * beam_idx / max(n_ports, 1)), math.sin(-2.0 * math.pi * n * beam_idx / max(n_ports, 1))) / math.sqrt(max(n_ports, 1)) for n in range(n_ports)]
    az_values = list(range(-90, 91, 5))
    el_values = list(range(-60, 61, 5))
    raw_gain: list[tuple[int, int, float]] = []
    max_gain = 0.0
    for el in el_values:
        el_rad = math.radians(el)
        for az in az_values:
            az_rad = math.radians(az)
            steering_sum = 0j
            for idx, (y_lambda, z_lambda) in enumerate(positions):
                phase = 2.0 * math.pi * (y_lambda * math.cos(el_rad) * math.sin(az_rad) + z_lambda * math.sin(el_rad))
                response = complex(math.cos(phase), math.sin(phase))
                steering_sum += weights[idx].conjugate() * response
            gain = abs(steering_sum) ** 2
            max_gain = max(max_gain, gain)
            raw_gain.append((az, el, gain))
    if max_gain <= 0:
        return None
    matrix: list[list[float]] = []
    csv_rows: list[dict[str, Any]] = []
    by_el: dict[int, list[float]] = defaultdict(list)
    for az, el, gain in raw_gain:
        gain_db = 10.0 * math.log10(max(gain / max_gain, 1e-12))
        # The generic heatmap renderer expects non-negative magnitudes. Keep
        # the CSV in normalized dB, and use a 40 dB display floor for color.
        by_el[el].append(max(gain_db, -40.0) + 40.0)
        csv_rows.append(
            {
                "run_id": run_id,
                "chart_name": chart_name,
                "azimuth_deg": az,
                "elevation_deg": el,
                "normalized_gain_db": gain_db,
                "applied_precoder_pmi": beam_idx,
                "array_rows": n_rows,
                "array_cols": n_cols,
                "precoder_source": precoder_source,
                "source_table_logical_path": "|".join(filter(None, [str(cfg["source_path"]), pmi_source_path])),
            }
        )
    for el in el_values:
        matrix.append(by_el[el])
    return {
        "csv_bytes": _encode_dict_rows(
            ["run_id", "chart_name", "azimuth_deg", "elevation_deg", "normalized_gain_db", "applied_precoder_pmi", "array_rows", "array_cols", "precoder_source", "source_table_logical_path"],
            csv_rows,
        ),
        "img_bytes": _render_heatmap_svg(
            chart_name,
            "Runtime DFT-codebook array-factor gain sampled over azimuth/elevation.",
            [str(value) for value in az_values],
            [str(value) for value in el_values],
            matrix,
            [f"array={n_rows}x{n_cols}", f"spacing={spacing_h:g}/{spacing_v:g} lambda", f"pmi={beam_idx}", "color=floor(normalized_gain_db,-40)+40"],
            "Azimuth (deg)",
            "Elevation (deg)",
        ),
        "csv_status": "specialized_runtime_beam_pattern_dataset",
        "image_status": "generated_specialized_runtime_beam_pattern_svg",
        "source_table_path": "|".join(filter(None, [str(cfg["source_path"]), pmi_source_path])),
        "source_row_count": len(csv_rows),
        "note": "Beam pattern is a deterministic array-factor reconstruction from exported runtime array geometry and applied DFT-codebook PMI. It is not relabeled as a measured over-the-air radiation pattern.",
    }


def _runtime_channel_impulse_response_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    source_candidates = [
        "reports/csv/channel_impulse_response.csv",
        "reports/csv/channel_tap_response.csv",
        "reports/csv/channel_snapshots.csv",
        "reports/csv/live_channel_state_tti.csv",
    ]
    requires_estimated_hhat = chart_name == "estimated Hhat(tau)"
    requires_true_complex_h = chart_name == "true H(tau) if available"
    explicit_delay_fields = ("TapDelay_s", "PathDelay_s", "tap_delay_s", "path_delay_s")
    explicit_power_fields = ("TapPower_dB", "PathPower_dB", "tap_power_db", "path_power_db", "TapMagnitude_dB", "PathMagnitude_dB")
    for source_path, rows in _all_available_rows(existing, fetch_artifact_bytes, source_candidates):
        csv_rows: list[dict[str, Any]] = []
        points: list[list[float]] = []
        for row in rows:
            response_type = _row_text(row, "ResponseType", "response_type")
            response_key = response_type.lower()
            if requires_estimated_hhat and not any(token in response_key for token in ("hhat", "estimated", "channel_estimate")):
                continue
            if requires_true_complex_h and "true_complex" not in response_key and "instantaneous_h" not in response_key:
                continue
            delay_s = _row_float(row, *explicit_delay_fields)
            power_db = _row_float(row, *explicit_power_fields)
            if delay_s is None or power_db is None:
                continue
            delay_ns = float(delay_s) * 1e9
            points.append([delay_ns, float(power_db)])
            csv_rows.append(
                {
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "direction": _row_text(row, "Direction", "direction"),
                    "response_type": response_type,
                    "delay_ns": delay_ns,
                    "tap_power_db": float(power_db),
                    "source_table_logical_path": source_path,
                }
            )
        if csv_rows:
            dataset = {"mode": "bar", "x_label": "Delay (ns)", "y_label": "Tap power (dB)", "points": points[:MAX_PREVIEW_ROWS]}
            return {
                "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "direction", "response_type", "delay_ns", "tap_power_db", "source_table_logical_path"], csv_rows),
                "img_bytes": _render_svg_plot(chart_name, "Explicit tap-delay/tap-power impulse response exported by the runtime.", dataset, [f"taps={len(csv_rows)}", f"source={source_path}"]),
                "csv_status": "specialized_runtime_channel_impulse_dataset",
                "image_status": "generated_specialized_runtime_summary_svg",
                "source_table_path": source_path,
                "source_row_count": len(csv_rows),
                "note": "Channel impulse response uses only explicit tap delay and tap power rows.",
            }
    reason = "No explicit tap-delay/tap-power table was exported. Channel summary rows such as pathloss, propagation delay, or Hest SINR are not a channel impulse response."
    return {
        "csv_bytes": _encode_csv(["run_id", "chart_name", "status", "reason", "checked_sources"], [[run_id, chart_name, "unavailable_exact_reason", reason, "|".join(source_candidates)]]),
        "img_bytes": _render_reason_svg(chart_name, "The materializer refuses to draw a fake H(tau).", [reason, "Export channel tap rows to materialize this plot honestly."]),
        "csv_status": "unavailable_exact_reason",
        "image_status": "generated_unavailable_reason_svg",
        "source_table_path": "|".join(source_candidates),
        "source_row_count": 0,
        "note": reason,
    }


def _runtime_delay_spread_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    source_path, rows = _first_available_rows(
        existing,
        fetch_artifact_bytes,
        ["reports/csv/channel_impulse_response.csv", "reports/csv/channel_tap_response.csv"],
    )
    if not rows:
        return None
    grouped: dict[str, list[tuple[float, float]]] = defaultdict(list)
    configured_spread: dict[str, float] = {}
    for row in rows:
        direction = _row_text(row, "Direction", "direction") or "channel"
        delay_s = _row_float(row, "TapDelay_s", "PathDelay_s", "tap_delay_s", "path_delay_s")
        power_lin = _row_float(row, "NormalizedTapPower", "TapLinearPower", "tap_linear_power", "normalized_tap_power")
        power_db = _row_float(row, "TapPower_dB", "PathPower_dB", "tap_power_db", "path_power_db")
        configured = _row_float(row, "DelaySpread_s", "delay_spread_s")
        if configured is not None and math.isfinite(float(configured)):
            configured_spread[direction] = float(configured)
        if delay_s is None:
            continue
        if power_lin is None and power_db is not None:
            power_lin = 10.0 ** (float(power_db) / 10.0)
        if power_lin is None or not math.isfinite(float(power_lin)) or float(power_lin) <= 0.0:
            continue
        grouped[direction].append((float(delay_s), float(power_lin)))
    csv_rows: list[dict[str, Any]] = []
    named_values: list[tuple[str, float]] = []
    for direction, samples in sorted(grouped.items()):
        total_power = sum(power for _delay, power in samples)
        if total_power <= 0.0:
            continue
        mean_delay = sum(delay * power for delay, power in samples) / total_power
        rms_delay = math.sqrt(max(sum(((delay - mean_delay) ** 2) * power for delay, power in samples) / total_power, 0.0))
        named_values.append((direction, rms_delay * 1e9))
        csv_rows.append(
            {
                "run_id": run_id,
                "chart_name": chart_name,
                "direction": direction,
                "rms_delay_spread_ns": rms_delay * 1e9,
                "configured_delay_spread_ns": configured_spread.get(direction, float("nan")) * 1e9 if direction in configured_spread else float("nan"),
                "tap_count": len(samples),
                "source_table_logical_path": source_path,
            }
        )
    if not csv_rows:
        return None
    dataset, summary = _bar_dataset_from_named_values("Direction", "RMS delay spread (ns)", named_values)
    summary.append(f"source={source_path}")
    return {
        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "direction", "rms_delay_spread_ns", "configured_delay_spread_ns", "tap_count", "source_table_logical_path"], csv_rows),
        "img_bytes": _render_svg_plot(chart_name, "RMS delay spread computed from exported tap-delay/tap-power rows.", dataset, summary),
        "csv_status": "specialized_runtime_delay_spread_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": source_path,
        "source_row_count": len(rows),
        "note": "Delay spread is derived from the persisted channel tap profile; no placeholder taps are created.",
    }


def _histogram_dataset(values: list[float], *, x_label: str, bins: int = 12) -> tuple[dict[str, Any], list[tuple[float, float, int]]]:
    finite = sorted(float(value) for value in values if math.isfinite(float(value)))
    if not finite:
        return {}, []
    lo = finite[0]
    hi = finite[-1]
    if math.isclose(lo, hi, rel_tol=0.0, abs_tol=1e-12):
        rows = [(lo, hi, len(finite))]
    else:
        count = max(1, min(int(bins), len(finite)))
        width = (hi - lo) / count
        counts = [0] * count
        for value in finite:
            index = min(count - 1, max(0, int((value - lo) / width)))
            counts[index] += 1
        rows = [
            (lo + index * width, lo + (index + 1) * width, value_count)
            for index, value_count in enumerate(counts)
            if value_count > 0
        ]
    points = [[(left + right) / 2.0, float(value_count)] for left, right, value_count in rows]
    return {
        "mode": "bar",
        "x_label": x_label,
        "y_label": "Observed count",
        "points": points,
        "evidence_shape_policy": "observed_distribution",
        "sample_count": len(finite),
    }, rows


def _runtime_geometry_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    key = str(chart_name or "").strip().lower()
    supported = {
        "ue trajectory overlay",
        "ue_trajectory_xy",
        "topology_map",
        "doppler_vs_slot",
        "distance distribution histogram",
        "azimuth/elevation rose plots",
        "path geometry summary charts",
        "pathloss/shadowing distributions",
        "pathloss distribution",
    }
    if key not in supported:
        return None

    trajectory_path = "geometry/csv/trajectory_geometry.csv"
    _trajectory_header, trajectory = _artifact_rows_by_path(
        existing, fetch_artifact_bytes, trajectory_path
    )
    topology_path = "geometry/csv/topology_nodes.csv"
    _topology_header, topology = _artifact_rows_by_path(
        existing, fetch_artifact_bytes, topology_path
    )

    if key in {"ue trajectory overlay", "ue_trajectory_xy"} and trajectory:
        series_map: dict[str, list[list[float]]] = defaultdict(list)
        csv_rows: list[dict[str, Any]] = []
        for row in trajectory:
            x_m = _row_float(row, "X_m")
            y_m = _row_float(row, "Y_m")
            if x_m is None or y_m is None:
                continue
            ue_id = _row_text(row, "UEID", "UeId") or "unknown"
            slot = _row_float(row, "CanonicalSlot")
            series_map[f"UE {ue_id}"].append([float(x_m), float(y_m)])
            csv_rows.append({
                "run_id": run_id,
                "chart_name": chart_name,
                "ue_id": ue_id,
                "canonical_slot": "" if slot is None else slot,
                "x_m": x_m,
                "y_m": y_m,
                "source_table_logical_path": trajectory_path,
            })
        series = [{"name": name, "points": points} for name, points in sorted(series_map.items()) if points]
        if series:
            return {
                "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "ue_id", "canonical_slot", "x_m", "y_m", "source_table_logical_path"], csv_rows),
                "img_bytes": _render_multi_series_svg(chart_name, "Runtime UE trajectory in the simulator Cartesian frame.", series, [f"runtime_rows={len(csv_rows)}", f"source={trajectory_path}"], x_label="X position (m)", y_label="Y position (m)", mode="scatter"),
                "csv_status": "specialized_runtime_geometry_dataset",
                "image_status": "generated_specialized_runtime_geometry_svg",
                "source_table_path": trajectory_path,
                "source_row_count": len(csv_rows),
                "note": "Every point is a persisted runtime trajectory coordinate; no map projection or configured substitute is used.",
            }

    if key == "topology_map" and topology:
        series_map: dict[str, list[list[float]]] = defaultdict(list)
        csv_rows: list[dict[str, Any]] = []
        for row in topology:
            x_m = _row_float(row, "X_m")
            y_m = _row_float(row, "Y_m")
            if x_m is None or y_m is None:
                continue
            node_class = _row_text(row, "NodeClass") or "node"
            node_id = _row_text(row, "NodeId", "UeId", "CellId")
            series_map[node_class.upper()].append([float(x_m), float(y_m)])
            csv_rows.append({
                "run_id": run_id,
                "chart_name": chart_name,
                "node_class": node_class,
                "node_id": node_id,
                "x_m": x_m,
                "y_m": y_m,
                "source_table_logical_path": topology_path,
            })
        series = [{"name": name, "points": points} for name, points in sorted(series_map.items()) if points]
        if series:
            return {
                "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "node_class", "node_id", "x_m", "y_m", "source_table_logical_path"], csv_rows),
                "img_bytes": _render_multi_series_svg(chart_name, "Cell and UE locations from the persisted topology table.", series, [f"nodes={len(csv_rows)}", f"source={topology_path}"], x_label="X position (m)", y_label="Y position (m)", mode="scatter"),
                "csv_status": "specialized_runtime_geometry_dataset",
                "image_status": "generated_specialized_runtime_geometry_svg",
                "source_table_path": topology_path,
                "source_row_count": len(csv_rows),
                "note": "Topology uses the simulator Cartesian frame and does not claim surveyed geographic coordinates.",
            }

    if key == "doppler_vs_slot" and trajectory:
        series_map: dict[str, list[list[float]]] = defaultdict(list)
        csv_rows: list[dict[str, Any]] = []
        for row in trajectory:
            slot = _row_float(row, "CanonicalSlot")
            doppler = _row_float(row, "AppliedDopplerHz")
            if slot is None or doppler is None:
                continue
            ue_id = _row_text(row, "UEID", "UeId") or "unknown"
            series_map[f"UE {ue_id}"].append([float(slot), float(doppler)])
            csv_rows.append({"run_id": run_id, "chart_name": chart_name, "ue_id": ue_id, "canonical_slot": slot, "applied_doppler_hz": doppler, "source_table_logical_path": trajectory_path})
        series = [{"name": name, "points": points} for name, points in sorted(series_map.items()) if points]
        if series:
            return {
                "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "ue_id", "canonical_slot", "applied_doppler_hz", "source_table_logical_path"], csv_rows),
                "img_bytes": _render_multi_series_svg(chart_name, "Applied runtime Doppler by UE and canonical slot.", series, [f"runtime_rows={len(csv_rows)}", f"source={trajectory_path}"], x_label="Canonical slot", y_label="Applied Doppler (Hz)"),
                "csv_status": "specialized_runtime_geometry_dataset",
                "image_status": "generated_specialized_runtime_geometry_svg",
                "source_table_path": trajectory_path,
                "source_row_count": len(csv_rows),
                "note": "Doppler values are the applied runtime channel values, not speed-only configured estimates.",
            }

    if key == "distance distribution histogram" and trajectory:
        values = [float(value) for value in (_row_float(row, "Distance3D_m") for row in trajectory) if value is not None]
        dataset, bins = _histogram_dataset(values, x_label="3D link distance (m)")
        if bins:
            csv_rows = [{"run_id": run_id, "chart_name": chart_name, "bin_min_m": left, "bin_max_m": right, "observed_count": count, "source_table_logical_path": trajectory_path} for left, right, count in bins]
            return {
                "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "bin_min_m", "bin_max_m", "observed_count", "source_table_logical_path"], csv_rows),
                "img_bytes": _render_svg_plot(chart_name, "Distribution of persisted runtime 3D serving-link distances.", dataset, [f"samples={len(values)}", f"source={trajectory_path}"]),
                "csv_status": "specialized_runtime_geometry_distribution_dataset",
                "image_status": "generated_specialized_runtime_geometry_svg",
                "source_table_path": trajectory_path,
                "source_row_count": len(values),
                "note": "Histogram bins contain only observed runtime distance samples.",
            }

    if key == "path geometry summary charts" and trajectory:
        series_map: dict[str, list[list[float]]] = {"Distance 2D": [], "Distance 3D": []}
        csv_rows: list[dict[str, Any]] = []
        for index, row in enumerate(trajectory, start=1):
            slot = _row_float(row, "CanonicalSlot")
            slot = float(index) if slot is None else float(slot)
            d2 = _row_float(row, "Distance2D_m")
            d3 = _row_float(row, "Distance3D_m")
            if d2 is not None:
                series_map["Distance 2D"].append([slot, float(d2)])
            if d3 is not None:
                series_map["Distance 3D"].append([slot, float(d3)])
            if d2 is not None or d3 is not None:
                csv_rows.append({"run_id": run_id, "chart_name": chart_name, "canonical_slot": slot, "distance_2d_m": "" if d2 is None else d2, "distance_3d_m": "" if d3 is None else d3, "source_table_logical_path": trajectory_path})
        series = [{"name": name, "points": points} for name, points in series_map.items() if points]
        if series:
            return {
                "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "canonical_slot", "distance_2d_m", "distance_3d_m", "source_table_logical_path"], csv_rows),
                "img_bytes": _render_multi_series_svg(chart_name, "Persisted two-dimensional and three-dimensional serving-link geometry by slot.", series, [f"runtime_rows={len(csv_rows)}", f"source={trajectory_path}"], x_label="Canonical slot", y_label="Distance (m)"),
                "csv_status": "specialized_runtime_geometry_dataset",
                "image_status": "generated_specialized_runtime_geometry_svg",
                "source_table_path": trajectory_path,
                "source_row_count": len(csv_rows),
                "note": "Geometry summary is directly tied to the runtime trajectory table.",
            }

    if key in {"pathloss/shadowing distributions", "pathloss distribution"} and trajectory:
        pathloss = [float(value) for value in (_row_float(row, "Pathloss_dB") for row in trajectory) if value is not None]
        dataset, bins = _histogram_dataset(pathloss, x_label="Pathloss (dB)")
        if bins:
            csv_rows = [{"run_id": run_id, "chart_name": chart_name, "metric_name": "Pathloss_dB", "bin_min": left, "bin_max": right, "observed_count": count, "source_table_logical_path": trajectory_path} for left, right, count in bins]
            return {
                "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "metric_name", "bin_min", "bin_max", "observed_count", "source_table_logical_path"], csv_rows),
                "img_bytes": _render_svg_plot(chart_name, "Distribution of applied runtime serving-link pathloss.", dataset, [f"samples={len(pathloss)}", "shadowing omitted when disabled by YAML", f"source={trajectory_path}"]),
                "csv_status": "specialized_runtime_geometry_distribution_dataset",
                "image_status": "generated_specialized_runtime_geometry_svg",
                "source_table_path": trajectory_path,
                "source_row_count": len(pathloss),
                "note": "Pathloss is observed runtime evidence; disabled shadowing is not added as a synthetic distribution.",
            }

    if key == "azimuth/elevation rose plots":
        angle_path = "reports/csv/channel_impulse_response.csv"
        _angle_header, angle_rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, angle_path)
        series_map: dict[str, list[list[float]]] = defaultdict(list)
        csv_rows: list[dict[str, Any]] = []
        for index, row in enumerate(angle_rows, start=1):
            power = _row_float(row, "NormalizedTapPower", "TapLinearPower")
            if power is None:
                continue
            for series_name, field_name in (
                ("AoD azimuth", "AzimuthDeparture_deg"),
                ("AoA azimuth", "AzimuthArrival_deg"),
                ("ZoD", "ZenithDeparture_deg"),
                ("ZoA", "ZenithArrival_deg"),
            ):
                angle = _row_float(row, field_name)
                if angle is None:
                    continue
                series_map[series_name].append([float(angle), float(power)])
                csv_rows.append({"run_id": run_id, "chart_name": chart_name, "path_index": index, "angle_type": series_name, "angle_deg": angle, "normalized_path_power": power, "source_table_logical_path": angle_path})
        series = [{"name": name, "points": points} for name, points in sorted(series_map.items()) if points]
        if series:
            return {
                "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "path_index", "angle_type", "angle_deg", "normalized_path_power", "source_table_logical_path"], csv_rows),
                "img_bytes": _render_multi_series_svg(chart_name, "Angular power samples from the runtime channel profile; CSV preserves AoD/AoA/ZoD/ZoA identity.", series, [f"angle_power_rows={len(csv_rows)}", f"source={angle_path}"], x_label="Angle (deg)", y_label="Normalized path power", mode="scatter"),
                "csv_status": "specialized_runtime_channel_angle_dataset",
                "image_status": "generated_specialized_runtime_geometry_svg",
                "source_table_path": angle_path,
                "source_row_count": len(csv_rows),
                "note": "Angles and path powers come from runtime nrCDLChannel profile information; no angular samples are invented.",
            }
    return None


def _runtime_profile_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    key = str(chart_name or "").strip().lower()
    stage_names = {
        "block execution time",
        "stage latency",
        "end-to-end latency",
        "orchestration latency chart",
        "latency breakdown stacked chart",
    }
    if key in stage_names:
        source_path = "reports/csv/runtime_stage_profile.csv"
        _header, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path)
        observed: list[dict[str, Any]] = []
        for row in rows:
            elapsed_s = _row_float(row, "StageElapsed_s")
            cumulative_s = _row_float(row, "BundleElapsed_s")
            order = _row_float(row, "StageOrder")
            stage = _row_text(row, "StageName")
            if elapsed_s is None or not stage:
                continue
            observed.append({
                "run_id": run_id,
                "chart_name": chart_name,
                "stage_order": len(observed) + 1 if order is None else order,
                "stage_name": stage,
                "stage_elapsed_ms": float(elapsed_s) * 1000.0,
                "bundle_elapsed_ms": "" if cumulative_s is None else float(cumulative_s) * 1000.0,
                "source_table_logical_path": source_path,
            })
        if not observed:
            return None
        if key in {"end-to-end latency", "orchestration latency chart"}:
            final_ms = max(float(row["bundle_elapsed_ms"]) for row in observed if row["bundle_elapsed_ms"] != "")
            dataset = {"mode": "bar", "x_label": "Runtime bundle", "y_label": "Elapsed time (ms)", "points": [[1.0, final_ms]], "evidence_shape_policy": "operating_point", "sample_count": len(observed)}
            subtitle = "Measured cumulative runtime bundle latency from the production stage profiler."
        else:
            dataset = {"mode": "bar", "x_label": "Stage order", "y_label": "Stage elapsed time (ms)", "points": [[float(row["stage_order"]), float(row["stage_elapsed_ms"])] for row in observed], "evidence_shape_policy": "observed_distribution", "sample_count": len(observed)}
            subtitle = "Measured elapsed time for each production runtime stage."
        return {
            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "stage_order", "stage_name", "stage_elapsed_ms", "bundle_elapsed_ms", "source_table_logical_path"], observed),
            "img_bytes": _render_svg_plot(chart_name, subtitle, dataset, [f"stages={len(observed)}", f"source={source_path}"]),
            "csv_status": "specialized_runtime_profile_dataset",
            "image_status": "generated_specialized_runtime_profile_svg",
            "source_table_path": source_path,
            "source_row_count": len(observed),
            "note": "Timing values are measured MATLAB profiler/runtime-stage observations; no CPU-cycle or resource-use estimate is substituted.",
        }

    if key == "per-format latency histograms":
        source_path = "air_interface/csv/pucch_trials.csv"
        _header, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path)
        by_format: dict[str, list[float]] = defaultdict(list)
        raw_rows: list[dict[str, Any]] = []
        for row in rows:
            latency = _row_float(row, "ReceiverPipelineLatency_ms", "DecodeLatency_ms", "ComputeLatency_ms")
            format_value = _row_text(row, "PUCCHFormat", "Format", "ResolvedFormat")
            if latency is None or not format_value:
                continue
            by_format[format_value].append(float(latency))
            raw_rows.append({
                "run_id": run_id, "chart_name": chart_name, "pucch_format": format_value,
                "latency_ms": float(latency), "slot": _row_text(row, "Slot"),
                "ue_index": _row_text(row, "UEIndex"),
                "latency_source": _row_text(row, "ReceiverStageLatencySource"),
                "source_table_logical_path": source_path,
            })
        if not raw_rows:
            return None
        all_values = [value for values in by_format.values() for value in values]
        minimum = min(all_values)
        maximum = max(all_values)
        bin_count = max(1, min(12, int(math.ceil(math.sqrt(len(all_values))))))
        width = (maximum - minimum) / bin_count if maximum > minimum else 1.0
        series = []
        for format_value, values in sorted(by_format.items()):
            counts = [0] * bin_count
            for value in values:
                index = min(bin_count - 1, max(0, int((value - minimum) / width))) if maximum > minimum else 0
                counts[index] += 1
            points = [[minimum + (index + 0.5) * width, float(count)] for index, count in enumerate(counts)]
            series.append({"name": f"PUCCH format {format_value}", "points": points})
        return {
            "csv_bytes": _encode_dict_rows(
                ["run_id", "chart_name", "pucch_format", "latency_ms", "slot", "ue_index", "latency_source", "source_table_logical_path"], raw_rows,
            ),
            "img_bytes": _render_multi_series_svg(
                chart_name, "Measured PUCCH receiver latency distribution separated by the actually executed format.",
                series, [f"samples={len(raw_rows)}", f"formats={len(by_format)}", f"source={source_path}"],
                x_label="Receiver latency bin center (ms)", y_label="Observed trial count", mode="bar",
            ),
            "csv_status": "specialized_runtime_pucch_format_latency_dataset",
            "image_status": "generated_specialized_runtime_profile_svg",
            "source_table_path": source_path,
            "source_row_count": len(raw_rows),
            "source_mapping_status": "exact",
            "note": "Histogram bins contain only measured PUCCH receiver latencies and preserve every raw observation in the contract CSV.",
        }

    latency_sources: dict[str, tuple[list[str], tuple[str, ...], str]] = {
        "pdcch stage latency waterfall": (["reports/csv/live_pdcch_stage_table.csv", "air_interface/csv/pdcch_trials.csv"], ("ControlLatency_ms", "ComputeLatency_ms", "DecodeLatency_ms"), "PDCCH"),
        "pbch stage latency": (["air_interface/csv/pbch_trials.csv", "control/csv/pbch_recovery_trials.csv"], ("ComputeLatency_ms", "DecodeLatency_ms", "ReceiverPipelineLatency_ms"), "PBCH"),
        "csi-rs latency trend": (["air_interface/csv/csi_rs_trials.csv"], ("ComputeLatency_ms", "DecodeLatency_ms", "ReceiverPipelineLatency_ms"), "CSI-RS"),
        "channel estimation latency": (["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv", "air_interface/csv/csi_rs_trials.csv", "air_interface/csv/pucch_trials.csv"], ("ChannelEstimationLatency_ms",), "Channel estimation"),
        "equalizer latency": (["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv", "air_interface/csv/pucch_trials.csv"], ("EqualizationLatency_ms",), "Equalizer"),
        "ldpc stage latency waterfall": (["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"], ("DecodeLatency_ms",), "LDPC decode"),
        "compute latency": (["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv", "air_interface/csv/pdcch_trials.csv"], ("ComputeLatency_ms",), "Compute"),
        "decode latency": (["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv", "air_interface/csv/pbch_trials.csv"], ("DecodeLatency_ms",), "Decode"),
    }
    if key not in latency_sources:
        return None
    candidates, fields, label = latency_sources[key]
    csv_rows: list[dict[str, Any]] = []
    points: list[list[float]] = []
    for source_path, rows in _all_available_rows(existing, fetch_artifact_bytes, candidates):
        for row in rows:
            latency = _row_float(row, *fields)
            if latency is None:
                continue
            sample_index = len(points) + 1
            points.append([float(sample_index), float(latency)])
            csv_rows.append({"run_id": run_id, "chart_name": chart_name, "sample_index": sample_index, "latency_ms": latency, "source_table_logical_path": source_path})
    if not csv_rows:
        return None
    dataset = {"mode": "bar" if len(points) == 1 else "line", "x_label": "Runtime sample", "y_label": f"{label} latency (ms)", "points": points, "evidence_shape_policy": "operating_point" if len(points) == 1 else "observed_timeline", "sample_count": len(points)}
    return {
        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "sample_index", "latency_ms", "source_table_logical_path"], csv_rows),
        "img_bytes": _render_svg_plot(chart_name, f"{label} latency from explicit persisted runtime latency fields.", dataset, [f"samples={len(points)}"]),
        "csv_status": "specialized_runtime_profile_dataset",
        "image_status": "generated_specialized_runtime_profile_svg",
        "source_table_path": "|".join(candidates),
        "source_row_count": len(csv_rows),
        "note": "Only explicit measured latency fields are used; absent stage timings remain unavailable.",
    }


def _persisted_fixed_sweep_curve_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    """Prefer the finalized fixed-sweep table because it carries CIs and scope."""

    chart_key = re.sub(
        r"[^a-z0-9]+", "_", str(chart_name or "").strip().lower()
    ).strip("_")
    direction = "DL" if chart_key.startswith("dl_") else ("UL" if chart_key.startswith("ul_") else "")
    x_axis_mode = "applied_snr"
    if chart_key == "bler_vs_sinr":
        metric_name, source_metric_name = "BLER", "BLER"
        low_name, high_name = "BLER_CI_Low", "BLER_CI_High"
        x_axis_mode = "measured_sinr"
    elif chart_key == "fer_vs_snr":
        # A fixed-link campaign executes one transport block per recorded
        # frame/trial, so the observed frame-error indicator is the TB CRC
        # failure indicator. Preserve that one-to-one scope explicitly.
        metric_name, source_metric_name = "FER", "BLER"
        low_name, high_name = "BLER_CI_Low", "BLER_CI_High"
    elif chart_key.endswith("bler_vs_snr"):
        metric_name, source_metric_name = "BLER", "BLER"
        low_name, high_name = "BLER_CI_Low", "BLER_CI_High"
    elif chart_key.endswith("ber_vs_snr"):
        metric_name, source_metric_name = "BER", "BER"
        low_name, high_name = "BER_CI_Low", "BER_CI_High"
    elif chart_key.endswith("throughput_vs_snr"):
        metric_name, source_metric_name = "Throughput_Mbps", "Throughput_Mbps"
        low_name, high_name = "", ""
    elif chart_key in {
        "measured_sinr_vs_configured_snr",
        "applied_awgn_snr_vs_measured_runtime_sinr_comparison",
        "applied_vs_measured_runtime_snr_sinr_comparison",
    }:
        metric_name, source_metric_name = "MeanMeasuredSINR_dB", "MeanMeasuredSINR_dB"
        low_name, high_name = "", ""
    else:
        return None

    candidate_paths: list[str] = []
    if direction and source_metric_name in {"BLER", "BER"}:
        direction_token = direction.lower()
        curve_token = "bler" if source_metric_name == "BLER" else "ber"
        candidate_paths.append(f"reports/csv/{direction_token}_fixed_snr_{curve_token}_curve.csv")
    candidate_paths.append("reports/csv/fixed_snr_sweep_curve_summary.csv")
    source_path, rows = _first_available_rows(existing, fetch_artifact_bytes, candidate_paths)
    if not rows:
        return None

    selected_rows: list[dict[str, str]] = []
    for row in rows:
        row_direction = _row_text(row, "Direction").upper()
        if direction and row_direction != direction:
            continue
        if x_axis_mode == "measured_sinr":
            x_value = _row_float(row, "MeanMeasuredSINR_dB")
        else:
            x_value, _x_source = _row_snr_axis_value(row)
        y_value = _row_float(row, source_metric_name)
        if x_value is None or y_value is None:
            continue
        selected_rows.append(row)
    if not selected_rows:
        return None

    csv_rows: list[dict[str, Any]] = []
    grouped_points: dict[str, list[list[float]]] = defaultdict(list)
    grouped_error_bars: dict[str, list[list[float]]] = defaultdict(list)
    trials_total = 0
    for row in selected_rows:
        row_direction = _row_text(row, "Direction").upper() or direction or "DL+UL"
        if x_axis_mode == "measured_sinr":
            x_value = _row_float(row, "MeanMeasuredSINR_dB")
            x_source = "MeanMeasuredSINR_dB"
        else:
            x_value, x_source = _row_snr_axis_value(row)
        y_value = _row_float(row, source_metric_name)
        assert x_value is not None and y_value is not None
        low_value = _row_float(row, low_name) if low_name else None
        high_value = _row_float(row, high_name) if high_name else None
        trial_count = int(max(0, _row_float(row, "TrialCount") or 0))
        trials_total += trial_count
        grouped_points[row_direction].append([float(x_value), float(y_value)])
        if low_value is not None and high_value is not None:
            grouped_error_bars[row_direction].append([float(x_value), float(low_value), float(high_value)])
        csv_rows.append(
            {
                "run_id": run_id,
                "chart_name": chart_name,
                "direction": row_direction,
                "snr_axis_field": x_source,
                "snr_db": float(x_value),
                "metric": metric_name,
                "metric_value": float(y_value),
                "ci_low": low_value if low_value is not None else "",
                "ci_high": high_value if high_value is not None else "",
                "trial_count": trial_count,
                "failure_count": int(max(0, _row_float(row, "TBFailCount", "FailureCount") or 0)),
                "mcs": _row_text(row, "MCS", "MCSIndex"),
                "modulation": _row_text(row, "Modulation"),
                "rank": _row_text(row, "Rank", "ConfiguredRank"),
                "layers": _row_text(row, "Layers", "ConfiguredLayers"),
                "channel_model": _row_text(row, "ChannelModel", "ConfiguredChannelModel"),
                "point_status": _row_text(row, "Status", "StopReason"),
                "source_table_logical_path": source_path,
            }
        )

    for points in grouped_points.values():
        points.sort(key=lambda point: point[0])
    first_row = selected_rows[0]
    summary = [
        f"Runtime trials: {trials_total}",
        f"SNR points: {sum(len(points) for points in grouped_points.values())}",
        f"MCS: {_row_text(first_row, 'MCS', 'MCSIndex') or 'mixed'}",
        f"Modulation: {_row_text(first_row, 'Modulation') or 'mixed'}",
        f"Rank / layers: {_row_text(first_row, 'Rank', 'ConfiguredRank') or '?'} / {_row_text(first_row, 'Layers', 'ConfiguredLayers') or '?'}",
        f"Channel: {_row_text(first_row, 'ChannelModel', 'ConfiguredChannelModel') or 'unknown'}",
        f"Source CSV: {source_path.rsplit('/', 1)[-1]}",
    ]
    target = _row_float(first_row, "TargetBLER") if metric_name in {"BLER", "FER"} else None
    transition_brackets: list[str] = []
    coarse_transition = False
    if target is not None:
        for series_direction, points in sorted(grouped_points.items()):
            ordered = sorted(points, key=lambda point: point[0])
            for left_point, right_point in zip(ordered, ordered[1:]):
                left_delta = float(left_point[1]) - float(target)
                right_delta = float(right_point[1]) - float(target)
                if left_delta == 0.0 or right_delta == 0.0 or left_delta * right_delta < 0.0:
                    gap_db = float(right_point[0]) - float(left_point[0])
                    if gap_db > 0.0:
                        transition_brackets.append(
                            f"{series_direction}: {_format_axis_tick(left_point[0])} to {_format_axis_tick(right_point[0])} dB ({_format_axis_tick(gap_db)} dB bracket)"
                        )
                        coarse_transition = coarse_transition or gap_db > 2.0
                    break
    if transition_brackets:
        summary.append("Target bracket: " + " | ".join(transition_brackets))
    if coarse_transition:
        summary.append("WARNING: transition unresolved; refine SNR grid to <=2 dB spacing")

    y_axis_label = "Delivered goodput (Mbit/s)" if metric_name == "Throughput_Mbps" else metric_name
    x_axis_label = "MeanMeasuredSINR_dB" if x_axis_mode == "measured_sinr" else "AppliedAWGNSNR_dB"
    render_mode = "scatter" if coarse_transition else "line"
    if metric_name == "Throughput_Mbps":
        summary.append("Throughput definition: CRC-delivered TB bits / observed air time")
        for series_direction, points in sorted(grouped_points.items()):
            endpoint = max(points, key=lambda point: point[0])
            summary.append(
                f"{series_direction} at {_format_axis_tick(endpoint[0])} dB: "
                f"{_format_axis_tick(endpoint[1])} Mbit/s"
            )
    if len(grouped_points) == 1:
        only_direction = next(iter(grouped_points))
        points = grouped_points[only_direction]
        dataset: dict[str, Any] = {
            "mode": _honest_chart_mode(points, render_mode),
            "x_label": x_axis_label,
            "y_label": y_axis_label,
            "points": points,
            "error_bars": grouped_error_bars.get(only_direction, []),
            "sample_count": trials_total,
            "evidence_shape_policy": "observed_relation" if len(points) > 1 else "operating_point",
        }
        if metric_name in {"BLER", "BER", "FER"}:
            dataset["y_axis_min"] = 0.0
            dataset["y_axis_max"] = 1.0
        if target is not None:
            dataset["target_line"] = target
        image = _render_svg_plot(
            chart_name,
            "CRC-delivered fixed-link goodput from measured transport-block outcomes; unresolved target brackets are shown as unconnected points."
            if metric_name == "Throughput_Mbps"
            else "Measured fixed-link operating points; unresolved target brackets are shown as unconnected points.",
            dataset,
            [f"Direction: {only_direction}"] + summary,
        )
    else:
        series = [
            {
                "name": key,
                "points": value,
                "error_bars": grouped_error_bars.get(key, []),
            }
            for key, value in sorted(grouped_points.items())
        ]
        image = _render_multi_series_svg(
            chart_name,
            "Directional CRC-delivered goodput; solid-circle DL and dashed-square UL remain distinguishable when values overlap."
            if metric_name == "Throughput_Mbps"
            else "Directional fixed-link operating points; unresolved target brackets are not interpolated.",
            series,
            summary,
            x_label=x_axis_label,
            y_label=y_axis_label,
            mode=render_mode,
            target_line=target,
        )

    header = [
        "run_id", "chart_name", "direction", "snr_axis_field", "snr_db",
        "metric", "metric_value", "ci_low", "ci_high", "trial_count",
        "failure_count", "mcs", "modulation", "rank", "layers",
        "channel_model", "point_status", "source_table_logical_path",
    ]
    return {
        "csv_bytes": _encode_dict_rows(header, csv_rows),
        "img_bytes": image,
        "csv_status": "specialized_finalized_fixed_sweep_dataset",
        "image_status": "generated_finalized_fixed_sweep_svg",
        "source_table_path": source_path,
        "source_row_count": len(selected_rows),
        "source_mapping_status": "exact",
        "note": "Finalized fixed-sweep rows provide applied SNR, measured metric, trial counts, operating point status, and confidence limits without re-estimation.",
    }


def _persisted_fixed_sweep_crc_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    source_path, rows = _first_available_rows(
        existing,
        fetch_artifact_bytes,
        ["reports/csv/fixed_snr_sweep_curve_summary.csv"],
    )
    if not rows:
        return None
    csv_rows: list[dict[str, Any]] = []
    grouped_points: dict[str, list[list[float]]] = defaultdict(list)
    grouped_error_bars: dict[str, list[list[float]]] = defaultdict(list)
    trial_total = 0
    for row in rows:
        direction = _row_text(row, "Direction").upper()
        snr_db, snr_source = _row_snr_axis_value(row)
        trial_count = int(max(0, _row_float(row, "TrialCount") or 0))
        fail_count = int(max(0, _row_float(row, "TBFailCount", "FailureCount") or 0))
        if not direction or snr_db is None or trial_count <= 0 or fail_count > trial_count:
            continue
        pass_count = trial_count - fail_count
        pass_rate = pass_count / trial_count
        ci_low, ci_high = _wilson_score_interval(pass_count, trial_count)
        grouped_points[direction].append([float(snr_db), float(pass_rate)])
        grouped_error_bars[direction].append([float(snr_db), ci_low, ci_high])
        trial_total += trial_count
        csv_rows.append(
            {
                "run_id": run_id,
                "chart_name": chart_name,
                "direction": direction,
                "snr_axis_field": snr_source,
                "snr_db": float(snr_db),
                "crc_pass_count": pass_count,
                "crc_fail_count": fail_count,
                "trial_count": trial_count,
                "crc_pass_rate": pass_rate,
                "ci95_lower": ci_low,
                "ci95_upper": ci_high,
                "source_table_logical_path": source_path,
            }
        )
    if not csv_rows:
        return None
    for points in grouped_points.values():
        points.sort(key=lambda point: point[0])
    series = [
        {
            "name": f"{direction} pass rate",
            "points": points,
            "error_bars": grouped_error_bars.get(direction, []),
        }
        for direction, points in sorted(grouped_points.items())
    ]
    image = _render_multi_series_svg(
        "CRC Pass Rate vs SNR",
        "CRC outcomes stratified by direction and applied SNR; aggregate low-SNR failures are not mixed with high-SNR results.",
        series,
        [
            f"Runtime trials: {trial_total}",
            f"Directional SNR points: {len(csv_rows)}",
            "Interval: Wilson 95%",
            f"Source CSV: {source_path.rsplit('/', 1)[-1]}",
        ],
        x_label="AppliedAWGNSNR_dB",
        y_label="CRC pass rate",
        mode="scatter",
    )
    return {
        "csv_bytes": _encode_dict_rows(
            [
                "run_id", "chart_name", "direction", "snr_axis_field", "snr_db",
                "crc_pass_count", "crc_fail_count", "trial_count", "crc_pass_rate",
                "ci95_lower", "ci95_upper", "source_table_logical_path",
            ],
            csv_rows,
        ),
        "img_bytes": image,
        "csv_status": "specialized_fixed_sweep_crc_by_direction_and_snr",
        "image_status": "generated_fixed_sweep_crc_by_direction_and_snr_svg",
        "source_table_path": source_path,
        "source_row_count": len(rows),
        "source_mapping_status": "exact",
        "note": "CRC pass/fail counts and Wilson intervals come directly from finalized fixed-sweep trial/failure counts at each direction and SNR.",
    }


def _configured_sweep_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    """Materialize configured-SNR plots only from persisted waveform trials."""
    chart_key = re.sub(
        r"[^a-z0-9]+", "_", str(chart_name or "").strip().lower()
    ).strip("_")
    supported = {
        "dl_bler_vs_snr",
        "ul_bler_vs_snr",
        "dl_ber_vs_snr",
        "ul_ber_vs_snr",
        "bler_vs_snr",
        "bler_vs_sinr",
        "ber_vs_snr",
        "fer_vs_snr",
        "crc_pass_fail_rates",
        "throughput_vs_snr",
        "measured_sinr_vs_configured_snr",
        "applied_awgn_snr_vs_measured_runtime_sinr_comparison",
        "applied_vs_measured_runtime_snr_sinr_comparison",
    }
    if chart_key not in supported:
        return None

    if chart_key == "crc_pass_fail_rates":
        return _persisted_fixed_sweep_crc_chart(
            chart_name, existing, fetch_artifact_bytes, run_id
        )

    finalized = _persisted_fixed_sweep_curve_chart(
        chart_name, existing, fetch_artifact_bytes, run_id
    )
    if finalized is not None:
        return finalized
    if chart_key in {"bler_vs_sinr", "fer_vs_snr"}:
        # Without the finalized sweep summary, defer to the trial-level
        # reliability renderer below. Do not misroute these names through the
        # generic configured-SNR-vs-measured-SINR comparison.
        return None

    trial_sources = _all_available_rows(
        existing,
        fetch_artifact_bytes,
        ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"],
    )
    if not trial_sources:
        return None

    required_direction = "DL" if chart_key.startswith("dl_") else ("UL" if chart_key.startswith("ul_") else "")
    pairs: list[tuple[float, float]] = []
    used_paths: list[str] = []
    selected_x_labels: Counter[str] = Counter()
    for source_path, rows in trial_sources:
        source_direction = "DL" if "dl_pdsch" in source_path else "UL"
        if required_direction and source_direction != required_direction:
            continue
        source_used = False
        for row in rows:
            configured_snr, row_x_label = _row_snr_axis_value(row)
            if configured_snr is None or not math.isfinite(float(configured_snr)):
                continue
            selected_x_labels[row_x_label] += 1
            if chart_key.endswith("bler_vs_snr"):
                metric = _trial_row_bler(row)
            elif chart_key.endswith("ber_vs_snr"):
                metric = _trial_row_ber(row)
            elif chart_key == "throughput_vs_snr":
                metric = _row_float(row, "Throughput_Mbps", "MeasuredThroughput_Mbps", "Goodput_Mbps")
            else:
                metric, _metric_source = _row_quality_axis_value(row, allow_receiver_hest=False)
            if metric is None or not math.isfinite(float(metric)):
                continue
            pairs.append((float(configured_snr), float(metric)))
            source_used = True
        if source_used:
            used_paths.append(source_path)
    if not pairs:
        return None

    if chart_key.endswith("bler_vs_snr"):
        y_label = "BLER"
    elif chart_key.endswith("ber_vs_snr"):
        y_label = "BER"
    elif chart_key == "throughput_vs_snr":
        y_label = "Throughput_Mbps"
    else:
        y_label = "MeasuredPostEqSINR_dB"
    x_label = selected_x_labels.most_common(1)[0][0] if selected_x_labels else "ConfiguredSNR_dB"
    source_path_text = "|".join(used_paths)
    csv_bytes, dataset = _metric_rows_by_exact_x(
        pairs,
        x_label=x_label,
        y_label=y_label,
        chart_name=chart_name,
        run_id=run_id,
        source_path=source_path_text,
    )
    point_count = len(dataset.get("points", []))
    dataset["sample_count"] = len(pairs)
    if chart_key.endswith("bler_vs_snr") or chart_key.endswith("ber_vs_snr"):
        dataset["y_axis_min"] = 0.0
        dataset["y_axis_max"] = 1.0
    if point_count == 1:
        dataset["mode"] = "bar"
        dataset["evidence_shape_policy"] = "operating_point"
        chart_scope = "single_operating_point_not_a_sweep_curve"
    else:
        dataset["mode"] = _honest_chart_mode(dataset.get("points", []), "line")
        dataset["evidence_shape_policy"] = "observed_relation"
        chart_scope = "measured_sweep_points"
    return {
        "csv_bytes": csv_bytes,
        "img_bytes": _render_svg_plot(
            chart_name,
            "Configured operating-point sweep aggregated only from persisted waveform trial measurements.",
            dataset,
            [
                f"Direction: {required_direction or 'DL+UL'}",
                f"Runtime samples: {len(pairs)}",
                f"X axis: {_display_axis_label(x_label)}",
                f"Scope: {chart_scope.replace('_', ' ')}",
            ],
        ),
        "csv_status": "specialized_runtime_configured_sweep_dataset",
        "image_status": "generated_specialized_runtime_sweep_svg",
        "source_table_path": source_path_text,
        "source_row_count": len(pairs),
        "note": (
            "Configured SNR is the explicit operating-point axis. Metrics come from real PDSCH/PUSCH trial rows; "
            "measured SINR uses receiver post-equalization evidence. A one-point run is labeled as an operating point, not a sweep curve."
        ),
    }


def _explicit_runtime_metric_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    """Render explicitly mapped runtime metrics without numeric-column guessing."""
    specs: dict[str, dict[str, Any]] = {
        "TB size over time": {"sources": ["reports/csv/live_pdsch_transport_block_table.csv"], "fields": ["tbs_bits", "TBSBits", "TBSize_bits"], "kind": "timeline", "label": "Transport block size (bits)"},
        "MCS/code-rate timeline": {"sources": ["reports/csv/live_pdsch_transport_block_table.csv", "air_interface/csv/dl_pdsch_trials.csv"], "fields": ["code_rate", "TargetCodeRate"], "kind": "timeline", "label": "Target code rate"},
        "code-block count histogram": {"sources": ["reports/csv/live_pdsch_code_block_table.csv", "air_interface/csv/dl_pdsch_trials.csv"], "fields": ["num_code_blocks", "NumCodeBlocks", "CodeBlockCount"], "kind": "distribution", "label": "Code-block count"},
        "decoder iteration histogram": {"sources": ["reports/csv/live_decoder_summary.csv", "air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"], "fields": ["decoder_iterations", "DecoderIterations"], "kind": "distribution", "label": "Decoder iterations"},
        "LLR statistics over time": {"sources": ["reports/csv/live_llr_summary.csv"], "fields": ["llr_mean_abs", "LLRMeanAbs"], "kind": "timeline", "label": "Mean absolute LLR"},
        "PUCCH decode success/failure trend": {"sources": ["reports/csv/live_pucch_summary.csv", "air_interface/csv/pucch_trials.csv"], "fields": ["PUCCHDecodeOk", "DecodeSuccess", "SuccessFlag"], "kind": "timeline", "label": "Decode success flag"},
        "ACK/NACK match chart": {"sources": ["reports/csv/live_uci_table.csv", "air_interface/csv/pucch_trials.csv"], "fields": ["UCIContentMatch"], "kind": "timeline", "label": "ACK/NACK content match"},
        "DTX detection chart": {"sources": ["reports/csv/live_uci_table.csv", "air_interface/csv/pucch_trials.csv"], "fields": ["DTXFlag"], "kind": "distribution", "label": "DTX flag"},
        "UCI bit count distribution": {"sources": ["reports/csv/live_uci_table.csv", "air_interface/csv/pucch_trials.csv"], "fields": ["UCIBitCount", "ExpectedBitCount"], "kind": "distribution", "label": "UCI bit count"},
        "SRS validity timeline": {"sources": ["reports/csv/live_srs_stage_table.csv", "air_interface/csv/srs_trials.csv"], "fields": ["SRSRuntimeEvidenceUsable", "MeasurementUsable", "DetectionUsable"], "kind": "timeline", "label": "SRS usable flag"},
        "channel estimate quality trend": {"sources": ["reports/csv/live_srs_channel_estimation_table.csv", "air_interface/csv/srs_trials.csv", "reports/csv/live_measurement_table.csv"], "fields": ["NMSE_dB", "TrueChannelNMSE_dB", "nmse_db"], "kind": "timeline", "label": "Channel-estimate NMSE (dB)"},
        "RSRP/CSI-RSRP timeline": {"sources": ["reports/csv/live_rsrp_serving_trace.csv", "air_interface/csv/dl_pdsch_trials.csv"], "fields": ["ServingRSRP_dBm", "RSRP_dBm", "CSI_RSRP_dBm"], "kind": "timeline", "label": "RSRP / CSI-RSRP (dBm)"},
        "CQI / PMI / RI / CRI timeline": {"sources": ["reports/csv/live_measurement_table.csv", "reports/csv/live_link_adaptation_input_table.csv"], "fields": ["wideband_cqi", "WidebandCQI", "ri", "RI"], "kind": "timeline", "label": "Reported CQI / RI"},
        "MU grouping summary": {"sources": ["packet_flow/csv/live_dl_scheduler_grants.csv", "packet_flow/csv/live_ul_scheduler_grants.csv"], "fields": ["MUMIMOGroupSize"], "kind": "distribution", "label": "MU-MIMO group size"},
        "UE Tx power timeline": {"sources": ["reports/csv/live_ue_power_state.csv", "reports/csv/live_power_runtime_table.csv"], "fields": ["ul_tx_power_dbm"], "kind": "timeline", "label": "UE Tx power (dBm)"},
        "TX power timeline per cell": {"sources": ["reports/csv/live_power_runtime_table.csv"], "fields": ["dl_tx_power_dbm"], "kind": "timeline", "label": "Cell Tx power (dBm)"},
        "TX power timeline per UE": {"sources": ["reports/csv/live_power_runtime_table.csv"], "fields": ["ul_tx_power_dbm"], "kind": "timeline", "label": "UE Tx power (dBm)"},
        "energy per bit over time": {"sources": ["reports/csv/live_energy_efficiency_table.csv", "reports/csv/live_power_runtime_table.csv"], "fields": ["energy_per_bit_j"], "kind": "timeline", "label": "Energy per bit (J/bit)"},
        "joules/GB over time": {"sources": ["reports/csv/live_energy_efficiency_table.csv", "reports/csv/live_power_runtime_table.csv"], "fields": ["joules_per_gb"], "kind": "timeline", "label": "Energy (J/GB)"},
        "PAPR distribution": {"sources": ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"], "fields": ["PAPR_dB"], "kind": "distribution", "label": "PAPR (dB)"},
        "measured_sinr_vs_slot": {"sources": ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"], "fields": ["PostEqSINR_dB", "MeasuredTrialSINR_dB"], "kind": "timeline", "label": "Measured post-equalization SINR (dB)"},
        "noise variance trend": {"sources": ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"], "fields": ["NoiseVariance", "LLRNoiseVariance"], "kind": "timeline", "label": "Noise variance"},
        "clipping event histogram": {"sources": ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"], "fields": ["PeakClippingEvents"], "kind": "distribution", "label": "Clipping events"},
        "code-block error rates": {"sources": ["reports/csv/live_pdsch_code_block_table.csv", "air_interface/csv/dl_pdsch_trials.csv"], "fields": ["code_block_bler", "CodeBlockBLER"], "kind": "distribution", "label": "Code-block BLER"},
        "CBG error rates": {"sources": ["reports/csv/live_pdsch_code_block_table.csv", "air_interface/csv/dl_pdsch_trials.csv"], "fields": ["cbg_bler", "CBGBLER"], "kind": "distribution", "label": "CBG BLER"},
        "per-layer SINR": {"sources": ["beamforming/csv/mimo_layer_metrics.csv"], "fields": ["PostEqSINRdB", "MeasuredSINR_dB", "LayerSINR_dB"], "kind": "distribution", "label": "Layer SINR (dB)"},
        "PAPR vs power": {"sources": ["rf/csv/energy_timeline_trace.csv"], "fields": ["PAPR_dB"], "kind": "timeline", "label": "PAPR (dB)"},
        "run health timeline": {"sources": ["reports/csv/live_run_overview.csv"], "fields": ["run_completion"], "status_fields": ["status_text"], "kind": "timeline", "label": "Run healthy/completed flag"},
        "error/warning/fallback stacked time series": {"sources": ["reports/csv/live_case_status.csv"], "fields": ["fallback_rows", "placeholder_rows"], "kind": "timeline", "label": "Fallback/placeholder rows"},
        "truth policy violations by category": {"sources": ["analytics/csv/truth_policy_analytics.csv"], "fields": ["StrictTruthFailureCount", "StrictProxyGuardFailureCount"], "kind": "distribution", "label": "Truth-policy violation count"},
        "frame/slot/symbol occupancy timeline": {"sources": ["reports/csv/slot_trace.csv"], "fields": ["DLNumSymbols", "ULNumSymbols", "GuardNumSymbols"], "x_fields": ["CanonicalSlot"], "kind": "timeline", "label": "Occupied symbols"},
        "DL/UL/guard slot pattern chart": {"sources": ["reports/csv/slot_trace.csv"], "fields": ["DLNumSymbols", "ULNumSymbols", "GuardNumSymbols"], "x_fields": ["CanonicalSlot"], "kind": "timeline", "label": "DL/UL/guard symbols"},
        "SSB occasion timeline": {"sources": ["reports/csv/live_ssb_occasion_state.csv"], "fields": ["SSBIndex", "BeamIndex"], "x_fields": ["Slot"], "kind": "timeline", "label": "SSB index"},
        "PRACH occasion timeline": {"sources": ["reports/csv/live_prach_occasion_state.csv"], "fields": ["PRACHCarrierSlot"], "x_fields": ["Slot"], "kind": "timeline", "label": "PRACH carrier slot"},
        "CORESET/search-space occupancy chart": {"sources": ["reports/csv/live_coreset_state.csv", "air_interface/csv/pdcch_trials.csv"], "fields": ["UsedCCECount", "CORESETUtilization", "ControlCapacityUtilization", "AggregationLevel"], "x_fields": ["Slot"], "kind": "timeline", "label": "Used CCE / aggregation level"},
        "SR/BSR event timeline": {"sources": ["reports/csv/live_sr_state.csv", "reports/csv/live_bsr_state.csv"], "fields": ["RuntimeStateUpdated", "TBSBits"], "x_fields": ["Slot"], "kind": "timeline", "label": "SR/BSR runtime event"},
        "sync success/failure timeline if available": {"sources": ["reports/csv/live_ssb_stage_table.csv", "air_interface/csv/pbch_trials.csv"], "fields": ["DecodeSuccess", "BCHCrcPass", "CRCPass"], "x_fields": ["Slot"], "kind": "timeline", "label": "Synchronization success"},
        "port usage chart": {"sources": ["reports/csv/live_mimo_state_table.csv", "beamforming/csv/rank_layer_trials.csv"], "fields": ["num_tx_ports", "NumTxPorts"], "x_fields": ["slot", "Slot"], "kind": "timeline", "label": "Logical transmit ports"},
        "precoder / beam selection timeline": {"sources": ["reports/csv/live_beam_selection_table.csv", "reports/csv/live_precoder_table.csv"], "fields": ["selected_beam_index", "applied_precoder_pmi"], "x_fields": ["slot"], "kind": "timeline", "label": "Selected beam / PMI"},
        "crash/error timeline": {"sources": ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"], "fields": ["Crash", "FailureFlag"], "x_fields": ["Slot"], "kind": "timeline", "label": "Crash/error flag"},
        "SRS consumption by scheduler/beam module": {"sources": ["reports/csv/live_srs_stage_table.csv", "air_interface/csv/srs_trials.csv"], "fields": ["SRSOccupiedPRBCount", "SRSRuntimeEvidenceUsable"], "x_fields": ["Slot"], "kind": "timeline", "label": "SRS resources / usable evidence"},
        "channel quality timeline": {"sources": ["reports/csv/live_channel_state_tti.csv", "air_interface/csv/dl_pdsch_trials.csv"], "fields": ["PostEqSINR_dB", "MeasuredTrialSINR_dB"], "x_fields": ["Slot"], "kind": "timeline", "label": "Measured post-equalization SINR (dB)"},
        "interference power timeline": {"sources": ["reports/csv/live_interference_table.csv"], "fields": ["interference_rx_power_dbm", "residual_interference_power_db"], "x_fields": ["slot"], "kind": "timeline", "label": "Interference power (dB/dBm)"},
        "measurement source coverage chart": {"sources": ["reports/csv/measurement_output_integrity_audit.csv"], "fields": ["MeasurementRows"], "kind": "distribution", "label": "Measurement rows by source"},
        "config-vs-measured conflict dashboard": {"sources": ["reports/csv/reports_config_vs_measured_conflicts_v.csv"], "fields": ["measured_minus_configured_snr_db", "mean_measured_sinr_db"], "kind": "timeline", "label": "Measured minus configured SNR/SINR (dB)"},
        "config vs measured conflict dashboard": {"sources": ["reports/csv/reports_config_vs_measured_conflicts_v.csv"], "fields": ["measured_minus_configured_snr_db", "mean_measured_sinr_db"], "kind": "timeline", "label": "Measured minus configured SNR/SINR (dB)"},
        "UE control/report timeline": {"sources": ["reports/csv/live_ue_control_state.csv"], "fields": ["ValueNumeric"], "kind": "timeline", "label": "UE control/report metric"},
        "DRX state timeline": {"sources": ["reports/csv/live_drx_state.csv"], "fields": ["active_samples", "sleep_samples", "idle_samples"], "kind": "timeline", "label": "DRX state samples"},
        "UE energy proxy timeline": {"sources": ["reports/csv/live_ue_power_state.csv"], "fields": ["energy_per_bit_j", "cumulative_energy_j"], "x_fields": ["slot", "timestamp_sim_ms"], "kind": "timeline", "label": "UE measured energy"},
        "per-cell context health timeline": {"sources": ["reports/csv/live_per_cell_context.csv"], "fields": ["dl_grant_count", "ul_grant_count"], "kind": "timeline", "label": "Per-cell executed grant count"},
        "sleep-state timeline": {"sources": ["reports/csv/live_sleep_state_table.csv"], "fields": ["metric_value", "energy_per_bit_j"], "x_fields": ["slot", "timestamp_sim_ms"], "kind": "timeline", "label": "Sleep-state runtime metric"},
        "efficiency scatter plots": {"sources": ["analytics/csv/energy_efficiency_analytics.csv"], "fields": ["ue_energy_efficiency", "cell_energy_efficiency"], "x_fields": ["ue_id", "cell_id"], "kind": "timeline", "label": "Energy efficiency"},
        "truth violation rollup": {"sources": ["analytics/csv/truth_policy_analytics.csv"], "fields": ["StrictTruthFailureCount", "StrictProxyGuardFailureCount", "CanonicalArtifactGapCount"], "kind": "distribution", "label": "Truth violation count"},
        "partial or missing data dashboard": {"sources": ["reports/csv/reports_partial_or_missing_v.csv"], "fields": ["source_row_count", "present_source_count"], "kind": "distribution", "label": "Persisted source rows"},
        "value semantics coverage chart": {"sources": ["reports/csv/reports_value_semantics_coverage_v.csv"], "fields": ["observation_count"], "kind": "distribution", "label": "Categorical runtime observation count"},
        "NMSE vs SNR / SINR": {"sources": ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"], "fields": ["NMSE_dB"], "x_fields": ["ConfiguredSNR_dB"], "kind": "timeline", "label": "Channel-estimate NMSE (dB)"},
        "estimator bias / variance summaries": {"sources": ["reports/csv/live_channel_estimation_stats.csv", "air_interface/csv/dl_pdsch_trials.csv"], "fields": ["NMSE_dB", "MeanNMSE_dB"], "kind": "distribution", "label": "Estimator error (dB)"},
        "angle spread chart": {"sources": ["reports/csv/channel_rf_cdlc_realization_table.csv", "channel/csv/path_gains.csv"], "fields": ["AngleAoD_deg", "AngleAoA_deg", "AngleZoD_deg", "AngleZoA_deg"], "kind": "distribution", "label": "Runtime channel path angle (deg)"},
        "serving vs interferer decomposition": {"sources": ["reports/csv/live_interference_table.csv"], "fields": ["interference_rx_power_dbm", "residual_interference_power_db"], "x_fields": ["slot"], "kind": "timeline", "label": "Interference contribution (dB/dBm)"},
        "SSB detection statistics": {"sources": ["air_interface/csv/pbch_trials.csv"], "fields": ["DecodeSuccess", "BCHCrcPass", "CRCPass"], "kind": "distribution", "label": "SSB/PBCH detection success"},
        "control decode success/failure tables": {"sources": ["air_interface/csv/pdcch_trials.csv", "air_interface/csv/pucch_trials.csv", "air_interface/csv/pbch_trials.csv"], "fields": ["DecodeSuccess", "CRCPass", "PUCCHDecodeOk"], "kind": "distribution", "label": "Control decode success"},
        "PBCH/PDCCH/PUCCH detection and decode timelines": {"sources": ["air_interface/csv/pbch_trials.csv", "air_interface/csv/pdcch_trials.csv", "air_interface/csv/pucch_trials.csv"], "fields": ["DecodeSuccess", "CRCPass", "PUCCHDecodeOk"], "x_fields": ["Slot"], "kind": "timeline", "label": "Control decode success"},
        "per-channel reliability breakdown": {"sources": ["reports/csv/control_pass_rates.csv"], "fields": ["PassRate", "SuccessRate", "Rate"], "kind": "distribution", "label": "Channel reliability"},
        "per-format reliability breakdown": {"sources": ["air_interface/csv/pucch_trials.csv"], "fields": ["PUCCHDecodeOk", "DecodeSuccess", "CRCPass"], "kind": "distribution", "label": "PUCCH format reliability"},
        "ServingRSRP / RSRP / CSI-RSRP trends": {"sources": ["reports/csv/live_rsrp_serving_trace.csv", "air_interface/csv/dl_pdsch_trials.csv"], "fields": ["ServingRSRP_dBm", "RSRP_dBm", "CSI_RSRP_dBm"], "x_fields": ["Slot"], "kind": "timeline", "label": "RSRP / CSI-RSRP (dBm)"},
        "per-beam quality plot": {"sources": ["reports/csv/live_beam_selection_table.csv"], "fields": ["selected_beam_gain_db", "best_beam_gain_db", "beam_gain_gap_db"], "x_fields": ["selected_beam_index"], "kind": "timeline", "label": "Beam quality (dB)"},
        "per-layer quality plot": {"sources": ["beamforming/csv/mimo_layer_metrics.csv"], "fields": ["PostEqSINRdB", "ChannelEstimateNMSEdB"], "x_fields": ["LayerIndex"], "kind": "timeline", "label": "Per-layer quality (dB)"},
        "inter-user leakage": {"sources": ["reports/csv/live_interference_table.csv"], "fields": ["residual_interference_power_db", "interference_rx_power_dbm"], "x_fields": ["slot"], "kind": "timeline", "label": "Inter-user leakage (dB/dBm)"},
        "MU grouping analytics": {"sources": ["packet_flow/csv/live_dl_scheduler_grants.csv", "packet_flow/csv/live_ul_scheduler_grants.csv"], "fields": ["MUMIMOGroupSize"], "kind": "distribution", "label": "MU-MIMO group size"},
        "baseband power": {"sources": ["reports/csv/live_bb_power_table.csv"], "fields": ["digital_baseband_power_w", "metric_value"], "x_fields": ["slot"], "kind": "timeline", "label": "Baseband power (W)"},
        "energy/bit": {"sources": ["reports/csv/live_energy_efficiency_table.csv"], "fields": ["energy_per_bit_j"], "kind": "distribution", "label": "Energy per bit (J/bit)"},
        "joules/GB": {"sources": ["reports/csv/live_energy_efficiency_table.csv"], "fields": ["joules_per_gb"], "kind": "distribution", "label": "Energy (J/GB)"},
        "energy efficiency by UE": {"sources": ["analytics/csv/energy_efficiency_analytics.csv"], "fields": ["ue_energy_efficiency"], "x_fields": ["ue_id"], "kind": "timeline", "label": "UE energy efficiency"},
        "energy efficiency by cell": {"sources": ["analytics/csv/energy_efficiency_analytics.csv"], "fields": ["cell_energy_efficiency"], "x_fields": ["cell_id"], "kind": "timeline", "label": "Cell energy efficiency"},
        "sleep/idle/active state occupancy": {"sources": ["reports/csv/live_drx_state.csv"], "fields": ["active_samples", "sleep_samples", "idle_samples"], "kind": "distribution", "label": "State occupancy samples"},
        "decoder complexity units": {"sources": ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"], "fields": ["DecoderComplexityUnits"], "kind": "distribution", "label": "Decoder complexity units"},
        "normalized decoder complexity": {"sources": ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"], "fields": ["NormalizedDecoderComplexity"], "kind": "distribution", "label": "Normalized decoder complexity"},
        "CSV vs DB consistency": {"sources": ["analytics/csv/export_consistency_analytics.csv"], "fields": ["BrowserVisible"], "kind": "distribution", "label": "CSV/DB consistency observation"},
        "DB vs browser consistency": {"sources": ["reports/csv/browser_runtime_db_consistency.csv"], "fields": ["BrowserVisible"], "kind": "distribution", "label": "DB/browser consistency observation"},
        "source row count vs analytics row count": {"sources": ["reports/csv/output_completeness_table.csv"], "fields": ["actual_row_count", "expected_row_count"], "kind": "timeline", "label": "Source/analytics row count"},
        "missing-field audits": {"sources": ["reports/csv/all_csv_artifact_audit.csv"], "fields": ["missing_numeric_count"], "kind": "distribution", "label": "Missing numeric field count"},
        "schema drift": {"sources": ["analytics/csv/schema_drift_analytics.csv"], "fields": ["FinalizedFlag"], "kind": "distribution", "label": "Observed schema field"},
        "config drift": {"sources": ["reports/csv/config_roundtrip_verification.csv"], "fields": ["Match", "MismatchFlag"], "kind": "distribution", "label": "Configuration round-trip match"},
        "truth-policy violation counts": {"sources": ["analytics/csv/truth_policy_analytics.csv"], "fields": ["StrictTruthFailureCount", "StrictProxyGuardFailureCount"], "kind": "distribution", "label": "Truth-policy violations"},
        "placeholder exposure checks": {"sources": ["reports/csv/live_case_status.csv"], "fields": ["placeholder_rows"], "kind": "distribution", "label": "Placeholder exposure rows"},
        "fallback event summaries": {"sources": ["reports/csv/live_case_status.csv"], "fields": ["fallback_rows"], "kind": "distribution", "label": "Fallback rows"},
        "run status truth checks": {"sources": ["reports/csv/result_status_summary.csv"], "fields": ["ResultOk", "RuntimeTruthContractOk", "ConfiguredEffectiveOk"], "kind": "distribution", "label": "Run truth status"},
        "summary-vs-raw contradiction checks": {"sources": ["reports/csv/summary_vs_raw_consistency.csv"], "fields": ["SummaryValue", "RawDerivedValue"], "kind": "timeline", "label": "Summary/raw value"},
    }
    spec = specs.get(str(chart_name or ""))
    if spec is None:
        return None

    source_path = ""
    samples: list[tuple[float, float]] = []
    raw_values: list[float] = []
    selected_rows: list[dict[str, str]] = []
    for candidate in spec["sources"]:
        _header, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, candidate)
        candidate_samples: list[tuple[float, float]] = []
        candidate_values: list[float] = []
        for index, row in enumerate(rows, start=1):
            value = _row_float(row, *spec["fields"])
            if value is None:
                status_token = ""
                for status_field in spec.get("status_fields", []):
                    status_token = _row_text(row, status_field).strip().lower()
                    if status_token:
                        break
                if status_token:
                    positive = {
                        "ok", "pass", "passed", "complete", "completed",
                        "generated", "available", "observed", "consistent",
                        "implemented", "success", "succeeded", "true",
                    }
                    negative = {
                        "fail", "failed", "error", "missing", "unavailable",
                        "incomplete", "false", "crash", "crashed",
                    }
                    if status_token in positive:
                        value = 1.0
                    elif status_token in negative:
                        value = 0.0
                    elif any(token in status_token for token in ("fail", "error", "crash", "missing")):
                        value = 0.0
                    elif any(token in status_token for token in ("complete", "pass", "success")):
                        value = 1.0
            if value is None or not math.isfinite(float(value)):
                continue
            x_value = _row_float(row, *spec.get("x_fields", []))
            if x_value is None:
                x_value = _timeline_axis_value(row, index)
            candidate_values.append(float(value))
            candidate_samples.append((float(x_value), float(value)))
        if candidate_values:
            source_path = candidate
            samples = candidate_samples
            raw_values = candidate_values
            selected_rows = rows
            break
    if not raw_values:
        return None

    if spec["kind"] == "distribution":
        counts = Counter(round(float(value), 9) for value in raw_values)
        if len(counts) <= 16:
            points = [[float(value), float(count)] for value, count in sorted(counts.items())]
        else:
            min_value = min(raw_values)
            max_value = max(raw_values)
            if math.isclose(min_value, max_value):
                points = [[float(min_value), float(len(raw_values))]]
            else:
                width = (max_value - min_value) / 16.0
                bins = [0] * 16
                for value in raw_values:
                    idx = min(15, max(0, int((value - min_value) / max(width, 1e-12))))
                    bins[idx] += 1
                points = [[min_value + width * (idx + 0.5), float(count)] for idx, count in enumerate(bins) if count]
        dataset = {
            "mode": "bar",
            "x_label": spec["label"],
            "y_label": "Sample count",
            "points": points,
            "evidence_shape_policy": "observed_distribution",
            "sample_count": len(raw_values),
        }
    else:
        grouped: dict[float, list[float]] = defaultdict(list)
        for x_value, metric_value in samples:
            grouped[round(float(x_value), 9)].append(float(metric_value))
        points = [[x_value, sum(values) / len(values)] for x_value, values in sorted(grouped.items())]
        mode = _honest_chart_mode(points)
        if len(points) == 1:
            # One persisted runtime row is a state snapshot, not a trend.
            mode = "bar"
            evidence_shape_policy = "measured_scalar"
        else:
            evidence_shape_policy = "observed_timeline"
        dataset = {
            "mode": mode,
            "x_label": "Slot / runtime sample",
            "y_label": spec["label"],
            "points": points,
            "evidence_shape_policy": evidence_shape_policy,
            "sample_count": len(raw_values),
        }
    if not dataset.get("points"):
        return None
    render_title = chart_name
    extra_summary: list[str] = []
    if chart_name == "MCS/code-rate timeline":
        dataset["y_axis_min"] = 0.0
        dataset["y_axis_max"] = 1.0
        mcs_values = sorted(
            {
                int(round(value))
                for value in (
                    _row_float(row, "mcs", "MCS", "mcs_index", "MCSIndex")
                    for row in selected_rows
                )
                if value is not None and math.isfinite(float(value))
            }
        )
        _trial_header, trial_rows = _artifact_rows_by_path(
            existing, fetch_artifact_bytes, "air_interface/csv/dl_pdsch_trials.csv"
        )
        fixed_tokens = {
            _row_text(row, "ActualMCSSelectionMode", "LinkAdaptationMode").strip().lower()
            for row in trial_rows
            if _row_text(row, "ActualMCSSelectionMode", "LinkAdaptationMode").strip()
        }
        fixed_policy = bool(fixed_tokens) and fixed_tokens.issubset(
            {"configured_fixed", "fixed", "configured_fixed_mcs"}
        )
        if fixed_policy:
            render_title = "Fixed MCS / Code-Rate Verification"
            extra_summary.append("Policy: configured fixed operating point")
        if mcs_values:
            extra_summary.append("Observed MCS: " + ", ".join(str(value) for value in mcs_values))
        extra_summary.append(
            "Observed code rate: "
            + ", ".join(_format_axis_tick(value) for value in sorted(set(raw_values)))
        )
    return {
        "csv_bytes": _chart_dataset_csv(
            run_id, chart_name, dataset, source_path, len(raw_values),
            "explicit_runtime_metric_dataset",
            f"Explicit {spec['label']} mapping from {source_path}.",
        ),
        "img_bytes": _render_svg_plot(
            render_title,
            f"{spec['label']} derived from explicitly mapped persisted runtime fields.",
            dataset,
            [f"samples={len(raw_values)}", f"source={source_path}"] + extra_summary,
        ),
        "csv_status": "explicit_runtime_metric_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": source_path,
        "source_row_count": len(raw_values),
        "note": "Only explicitly named runtime fields are used; no generic numeric-column inference or placeholder rows are allowed.",
    }


def _runtime_point_chart(
    chart_name: str,
    run_id: int,
    source_path: str,
    points: list[list[float]],
    x_label: str,
    y_label: str,
    note: str,
    *,
    mode: str = "line",
    evidence_shape_policy: str = "",
) -> dict[str, Any] | None:
    finite = [
        [float(point[0]), float(point[1])]
        for point in points
        if len(point) >= 2
        and _coerce_float(point[0]) is not None
        and _coerce_float(point[1]) is not None
    ]
    if not finite:
        return None
    csv_rows = [
        {
            "run_id": run_id,
            "chart_name": chart_name,
            "point_index": index,
            "x_value": point[0],
            "y_value": point[1],
            "source_table_logical_path": source_path,
        }
        for index, point in enumerate(finite, start=1)
    ]
    dataset = {
        "mode": mode,
        "x_label": x_label,
        "y_label": y_label,
        "points": _downsample_points(finite, 256),
        "sample_count": len(finite),
    }
    if evidence_shape_policy:
        dataset["evidence_shape_policy"] = str(evidence_shape_policy)
    return {
        "csv_bytes": _encode_dict_rows(
            ["run_id", "chart_name", "point_index", "x_value", "y_value", "source_table_logical_path"],
            csv_rows,
        ),
        "img_bytes": _render_svg_plot(
            chart_name,
            note,
            dataset,
            [f"source={source_path}", f"observations={len(finite)}"],
        ),
        "csv_status": "specialized_runtime_exact_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": source_path,
        "source_row_count": len(finite),
        "note": note,
    }


def _runtime_resource_occupancy_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    supported = {
        "PRB heatmap",
        "RE occupancy heatmap",
        "SSB/PBCH occupancy map",
        "DMRS/PTRS occupancy plot",
        "DMRS/PTRS occupancy map",
        "PRACH opportunity map",
    }
    if chart_name not in supported:
        return None
    if chart_name == "PRB heatmap":
        source_path = "reports/csv/prb_allocation_heatmap.csv"
    else:
        source_path = "reports/csv/live_re_allocation_snapshot.csv"
    _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path)
    if not records:
        return None
    token_filters: tuple[str, ...] = ()
    if chart_name == "SSB/PBCH occupancy map":
        token_filters = ("SSB", "PBCH", "PSS", "SSS")
    elif chart_name in {"DMRS/PTRS occupancy plot", "DMRS/PTRS occupancy map"}:
        token_filters = ("DMRS", "PTRS")
    elif chart_name == "PRACH opportunity map":
        token_filters = ("PRACH",)
    # The current runtime exporter persists exact contiguous RE runs.  Older
    # runs used an already-aggregated slot/RB schema, so accept both without
    # inventing allocations for either representation.
    exact_re_schema = bool(records) and all(
        any(str(key).lower() == required for key in records[0])
        for required in (
            "absolute_slot",
            "symbol_index",
            "subcarrier_start",
            "subcarrier_count",
        )
    )
    aggregate: dict[tuple[int, int], float] = defaultdict(float)
    ports_by_cell: dict[tuple[int, int], set[int]] = defaultdict(set)
    channels_by_cell: dict[tuple[int, int], set[str]] = defaultdict(set)
    chosen_cell = _selected_cell(records, "cell_id", "CellID", "BaseStationID")
    for row in records:
        if chosen_cell and _row_text(row, "cell_id", "CellID", "BaseStationID") != chosen_cell:
            continue
        family = " ".join(
            _row_text(row, field).upper()
            for field in ("signal_family", "channel", "signal_name", "occupancy_role")
        )
        if token_filters and not any(token in family for token in token_filters):
            continue
        if exact_re_schema:
            absolute_slot = _row_float(row, "absolute_slot")
            symbol_index = _row_float(row, "symbol_index")
            subcarrier_start = _row_float(row, "subcarrier_start")
            subcarrier_count = _row_float(row, "subcarrier_count")
            if (
                absolute_slot is None
                or symbol_index is None
                or subcarrier_start is None
                or subcarrier_count is None
                or subcarrier_count <= 0
            ):
                continue
            slot_i = int(round(absolute_slot))
            symbol_i = int(round(symbol_index))
            time_symbol = slot_i * 14 + symbol_i
            sc_first = int(round(subcarrier_start))
            sc_after_last = sc_first + int(round(subcarrier_count))
            port_value = _row_float(row, "port_index")
            port_i = int(round(port_value)) if port_value is not None else 0
            channel_name = _row_text(row, "channel", "signal_family")
            first_prb = sc_first // 12
            last_prb = (sc_after_last - 1) // 12
            for rb_i in range(first_prb, last_prb + 1):
                overlap = max(
                    0,
                    min(sc_after_last, (rb_i + 1) * 12) - max(sc_first, rb_i * 12),
                )
                if overlap <= 0:
                    continue
                key = (time_symbol, rb_i)
                # Sum exact occupied REs across physical/logical ports.  This
                # preserves port multiplicity while the companion fields keep
                # the number of contributing ports and channels auditable.
                aggregate[key] += float(overlap)
                ports_by_cell[key].add(port_i)
                if channel_name:
                    channels_by_cell[key].add(channel_name)
        else:
            slot = _row_float(row, "slot", "Slot", "sfn")
            rb = _row_float(row, "rb_index", "PRBStart")
            occupancy = _row_float(row, "occupancy_value", "occupancy_count", "count")
            if slot is None or rb is None or occupancy is None:
                continue
            key = (int(round(slot)), int(round(rb)))
            aggregate[key] = max(aggregate[key], float(occupancy))
    if exact_re_schema:
        grid_rows = [
            {
                "time_symbol": time_symbol,
                "absolute_slot": time_symbol // 14,
                "symbol_index": time_symbol % 14,
                "rb_index": rb,
                "occupancy_value": value,
                "port_count": len(ports_by_cell[(time_symbol, rb)]),
                "channels": "|".join(sorted(channels_by_cell[(time_symbol, rb)])),
            }
            for (time_symbol, rb), value in sorted(aggregate.items())
        ]
        x_field = "time_symbol"
        x_axis_label = "Absolute OFDM symbol (slot x 14 + symbol)"
    else:
        grid_rows = [
            {"slot": slot, "rb_index": rb, "occupancy_value": value}
            for (slot, rb), value in sorted(aggregate.items())
        ]
        x_field = "slot"
        x_axis_label = "Slot"
    if not grid_rows:
        return None
    x_labels, y_labels, matrix = _grid_rows_to_heatmap(
        grid_rows, x_field, "rb_index", "occupancy_value"
    )
    csv_rows = [
        {
            "run_id": run_id,
            "chart_name": chart_name,
            "cell_id": chosen_cell,
            **row,
            "source_table_logical_path": source_path,
        }
        for row in grid_rows
    ]
    image_bytes, image_status = _render_heatmap_or_projection_svg(
        chart_name,
        "Resource occupancy aggregated from persisted runtime RE-allocation rows.",
        x_labels,
        y_labels,
        matrix,
        [f"source={source_path}", f"cell={chosen_cell or 'all'}", f"occupied_slot_rb_pairs={len(grid_rows)}"],
        x_axis_label,
        "RB index",
    )
    return {
        "csv_bytes": _encode_dict_rows(
            (
                [
                    "run_id",
                    "chart_name",
                    "cell_id",
                    "time_symbol",
                    "absolute_slot",
                    "symbol_index",
                    "rb_index",
                    "occupancy_value",
                    "port_count",
                    "channels",
                    "source_table_logical_path",
                ]
                if exact_re_schema
                else [
                    "run_id",
                    "chart_name",
                    "cell_id",
                    "slot",
                    "rb_index",
                    "occupancy_value",
                    "source_table_logical_path",
                ]
            ),
            csv_rows,
        ),
        "img_bytes": image_bytes,
        "csv_status": "specialized_runtime_re_occupancy_dataset",
        "image_status": image_status,
        "source_table_path": source_path,
        "source_row_count": len(grid_rows),
        "source_mapping_status": "exact",
        "note": (
            "Exact subcarrier runs are projected onto slot-symbol/PRB cells; "
            "occupied RE counts preserve observed port multiplicity. No inferred "
            "allocations are added."
            if exact_re_schema
            else "No inferred allocations are added; every occupied slot/RB pair has a persisted runtime allocation row."
        ),
    }


def _runtime_dl_tx_power_per_entity_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    if chart_name != "DL Tx power per cell / beam / UE":
        return None
    power_path = "reports/csv/live_power_runtime_table.csv"
    grant_path = "packet_flow/csv/live_dl_scheduler_grants.csv"
    _, power_rows = _artifact_rows_by_path(
        existing, fetch_artifact_bytes, power_path
    )
    _, grant_rows = _artifact_rows_by_path(
        existing, fetch_artifact_bytes, grant_path
    )
    beam_by_key: dict[tuple[int, int, str], str] = {}
    for row in grant_rows:
        frame = _row_float(row, "Frame", "SFN")
        slot = _row_float(row, "Slot")
        ue_id = _row_text(row, "UEID", "UEIndex", "ue_id")
        if frame is None or slot is None or not ue_id:
            continue
        beam_by_key[(int(round(frame)), int(round(slot)), ue_id)] = _row_text(
            row, "AppliedBeamIndexSet", "BeamIndex", "SelectedBeamIndex"
        )
    grouped: dict[tuple[str, str, str], list[float]] = defaultdict(list)
    for row in power_rows:
        if _row_text(row, "direction", "Direction").upper() != "DL":
            continue
        if "active_tx" not in _row_text(row, "state", "State").lower():
            continue
        power_dbm = _row_float(row, "dl_tx_power_dbm", "DLTxPower_dBm")
        if power_dbm is None:
            continue
        cell_id = _row_text(row, "cell_id", "CellID", "bs_id", "BaseStationID")
        ue_id = _row_text(row, "ue_id", "UEID", "UEIndex")
        frame = _row_float(row, "frame", "Frame", "sfn", "SFN")
        slot = _row_float(row, "slot", "Slot")
        beam = ""
        if frame is not None and slot is not None and ue_id:
            beam = beam_by_key.get(
                (int(round(frame)), int(round(slot)), ue_id), ""
            )
        grouped[(cell_id or "unknown", beam or "not_exported", ue_id or "unknown")].append(
            float(power_dbm)
        )
    if not grouped:
        return None
    rows_out: list[dict[str, Any]] = []
    named_values: list[tuple[str, float]] = []
    for index, ((cell_id, beam_id, ue_id), values) in enumerate(
        sorted(grouped.items()), start=1
    ):
        mean_power_dbm = sum(values) / len(values)
        label = f"cell={cell_id};beam={beam_id};ue={ue_id}"
        named_values.append((label, mean_power_dbm))
        rows_out.append({
            "run_id": run_id,
            "chart_name": chart_name,
            "x_value": index,
            "y_value": mean_power_dbm,
            "cell_id": cell_id,
            "beam_id": beam_id,
            "ue_id": ue_id,
            "sample_count": len(values),
            "aggregation": "arithmetic_mean_of_runtime_dl_active_tx_power_dbm",
            "source_table_logical_path": f"{power_path}|{grant_path}",
        })
    dataset, summary = _bar_dataset_from_named_values(
        "Cell / beam / UE", "Mean DL TX power (dBm)", named_values
    )
    dataset["tick_labels"] = [label for label, _value in named_values]
    return {
        "csv_bytes": _encode_dict_rows(
            [
                "run_id", "chart_name", "x_value", "y_value", "cell_id",
                "beam_id", "ue_id", "sample_count", "aggregation",
                "source_table_logical_path",
            ],
            rows_out,
        ),
        "img_bytes": _render_svg_plot(
            chart_name,
            "Runtime DL active-transmit power grouped by the exact cell, beam, and UE identities exported by the coupled PHY/scheduler chain.",
            dataset,
            summary + [f"power_source={power_path}", f"beam_source={grant_path}"],
        ),
        "csv_status": "specialized_runtime_dl_tx_power_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": f"{power_path}|{grant_path}",
        "source_row_count": sum(len(values) for values in grouped.values()),
        "source_mapping_status": "exact",
        "note": "No configured power or beam value is substituted; absent runtime beam identity remains not_exported.",
    }


def _preview_spectrum(
    samples: list[complex], sample_rate_hz: float
) -> list[list[float]]:
    n = len(samples)
    if n < 4 or not math.isfinite(sample_rate_hz) or sample_rate_hz <= 0:
        return []
    window = [0.5 - 0.5 * math.cos(2.0 * math.pi * index / max(n - 1, 1)) for index in range(n)]
    spectrum: list[tuple[float, float]] = []
    for k in range(n):
        value = sum(
            samples[t] * window[t] * cmath.exp(-2j * math.pi * k * t / n)
            for t in range(n)
        )
        power = (abs(value) ** 2) / max(sum(weight * weight for weight in window), 1e-15)
        frequency = ((k + n // 2) % n - n // 2) * sample_rate_hz / n
        spectrum.append((frequency, power))
    spectrum.sort(key=lambda item: item[0])
    peak = max((power for _, power in spectrum), default=0.0)
    if peak <= 0:
        return []
    return [[frequency / 1e6, 10.0 * math.log10(max(power / peak, 1e-15))] for frequency, power in spectrum]


def _runtime_spectral_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    if chart_name not in {
        "PSD",
        "occupied bandwidth",
        "out-of-band spectral summaries if measurable",
        "power spectral comparison before/after impairment",
    }:
        return None
    source_path = "reports/csv/live_waveform_preview.csv"
    _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path)
    if not records:
        return None
    records = sorted(records, key=lambda row: _row_float(row, "SampleIndex") or 0.0)[:256]
    time_values = [value for value in (_row_float(row, "Time_s") for row in records) if value is not None]
    deltas = [b - a for a, b in zip(time_values, time_values[1:]) if b > a]
    sample_rate_hz = 1.0 / (sum(deltas) / len(deltas)) if deltas else float("nan")
    tx = [complex(_row_float(row, "TxReal") or 0.0, _row_float(row, "TxImag") or 0.0) for row in records]
    rx = [complex(_row_float(row, "RxReal") or 0.0, _row_float(row, "RxImag") or 0.0) for row in records]
    tx_psd = _preview_spectrum(tx, sample_rate_hz)
    rx_psd = _preview_spectrum(rx, sample_rate_hz)
    if not tx_psd and not rx_psd:
        return None
    series = []
    csv_rows: list[dict[str, Any]] = []
    for name, values in (("TX", tx_psd), ("RX", rx_psd)):
        if not values:
            continue
        series.append({"name": name, "points": values})
        for frequency_mhz, psd_db in values:
            csv_rows.append(
                {
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "series_name": name,
                    "frequency_mhz": frequency_mhz,
                    "relative_psd_db": psd_db,
                    "source_table_logical_path": source_path,
                }
            )
    note = "Preview-sample periodogram; it is not relabeled as a full raw-IQ spectral mask measurement."
    if chart_name in {"occupied bandwidth", "out-of-band spectral summaries if measurable"}:
        # Estimate the 99-percent occupied bandwidth from the actual preview periodogram.
        linear = [(point[0], 10.0 ** (point[1] / 10.0)) for point in tx_psd]
        total = sum(power for _, power in linear)
        ordered = sorted(linear, key=lambda item: abs(item[0]))
        cumulative = 0.0
        half_band_mhz = 0.0
        for frequency_mhz, power in ordered:
            cumulative += power
            half_band_mhz = max(half_band_mhz, abs(frequency_mhz))
            if total > 0 and cumulative / total >= 0.99:
                break
        occupied_mhz = 2.0 * half_band_mhz
        in_band = sum(power for frequency, power in linear if abs(frequency) <= half_band_mhz)
        out_band = max(total - in_band, 0.0)
        metric_points = [[0.0, occupied_mhz]] if chart_name == "occupied bandwidth" else [[0.0, 10.0 * math.log10(max(out_band / max(in_band, 1e-15), 1e-15))]]
        return _runtime_point_chart(
            chart_name,
            run_id,
            source_path,
            metric_points,
            "Preview measurement",
            "99% occupied bandwidth (MHz)" if chart_name == "occupied bandwidth" else "Out/in-band power ratio (dB)",
            note,
            mode="bar",
            evidence_shape_policy="measured_scalar",
        )
    return {
        "csv_bytes": _encode_dict_rows(
            ["run_id", "chart_name", "series_name", "frequency_mhz", "relative_psd_db", "source_table_logical_path"],
            csv_rows,
        ),
        "img_bytes": _render_multi_series_svg(
            chart_name,
            note,
            series,
            [f"source={source_path}", f"sample_rate_hz={sample_rate_hz:.9g}", f"samples={len(records)}"],
            x_label="Frequency (MHz)",
            y_label="Relative PSD (dB)",
        ),
        "csv_status": "specialized_runtime_preview_periodogram_dataset",
        "image_status": "generated_specialized_runtime_spectrum_svg",
        "source_table_path": source_path,
        "source_row_count": len(records),
        "note": note,
    }


def _runtime_contract_gap_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    if chart_name == "required vs failed case bar chart":
        source = "reports/csv/live_required_vs_optional_case_status.csv"
        _, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, source)
        counts = Counter()
        for row in rows:
            required = bool((_row_float(row, "required_flag") or 0.0) > 0.5)
            status = _row_text(row, "status").lower()
            failed = any(token in status for token in ("fail", "missing", "error", "unavailable"))
            counts[(required, failed)] += 1
        points = [[float(index), float(counts[key])] for index, key in enumerate(((True, False), (True, True), (False, False), (False, True)))]
        return _runtime_point_chart(chart_name, run_id, source, points, "Required/pass category", "Case count", "Counts are reduced from persisted required_flag and status fields.", mode="bar", evidence_shape_policy="observed_distribution")
    if chart_name == "HOL delay over time":
        source = "packet_flow/csv/live_application_packet_delivery_ledger.csv"
        _, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, source)
        points = []
        for index, row in enumerate(rows, start=1):
            enqueue = _row_float(row, "EnqueueTime_s")
            first_grant = _row_float(row, "FirstGrantTime_s")
            if enqueue is not None and first_grant is not None and first_grant >= enqueue:
                points.append([float(index), 1000.0 * (first_grant - enqueue)])
        return _runtime_point_chart(chart_name, run_id, source, points, "Packet observation", "HOL-to-first-grant delay (ms)", "Derived exactly as FirstGrantTime_s minus EnqueueTime_s for persisted application packets.")
    if chart_name in {"duplicate write count trend", "dropped row / duplicate write analytics"}:
        source = "reports/csv/artifact_inventory.csv"
        _, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, source)
        paths = [_row_text(row, "RelativePath") for row in rows if _row_text(row, "RelativePath")]
        counts = Counter(paths)
        points = [[float(index), float(max(counts[path] - 1, 0))] for index, path in enumerate(paths, start=1)]
        return _runtime_point_chart(chart_name, run_id, source, points, "Inventory row", "Duplicate write count", "Duplicate counts are exact RelativePath multiplicities in the persisted artifact inventory.", evidence_shape_policy="observed_timeline")
    if chart_name == "consistency failure trend":
        source = "reports/csv/live_consistency_check_table.csv"
        _, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, source)
        points = []
        for index, row in enumerate(rows, start=1):
            status = _row_text(row, "status").lower()
            points.append([float(index), float(any(token in status for token in ("fail", "missing", "error", "invalid")))])
        return _runtime_point_chart(chart_name, run_id, source, points, "Consistency check", "Failure flag", "Failure flags are reduced from persisted consistency-check status values.", evidence_shape_policy="observed_timeline")
    if chart_name == "investigator stage lineage graph":
        source = "reports/csv/raw_to_derived_lineage.csv"
        _, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, source)
        points = []
        for index, row in enumerate(rows, start=1):
            status = (_row_text(row, "RuntimeEvidenceStatus") + " " + _row_text(row, "DerivationStatus")).lower()
            points.append([float(index), 0.0 if any(token in status for token in ("fail", "missing", "unavailable")) else 1.0])
        return _runtime_point_chart(chart_name, run_id, source, points, "Lineage edge", "Published/derived flag", "Each point is an exact raw-to-derived lineage edge and its persisted evidence/derivation status.", evidence_shape_policy="observed_timeline")
    if chart_name == "config drift":
        source = "reports/csv/config_roundtrip_verification.csv"
        _, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, source)
        points = []
        for index, row in enumerate(rows, start=1):
            status = _row_text(row, "ConsistencyStatus").lower()
            points.append([float(index), 0.0 if status in {"consistent", "match", "matched", "ok", "pass", "passed"} else 1.0])
        return _runtime_point_chart(chart_name, run_id, source, points, "Configured field", "Drift flag", "Drift is reduced only from persisted configuration round-trip consistency status.", evidence_shape_policy="observed_timeline")
    if chart_name == "smoke exposure checks":
        source = "reports/csv/run_classification.csv"
        _, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, source)
        points = [[float(index), float("smoke" in _row_text(row, "RunClass").lower())] for index, row in enumerate(rows, start=1)]
        return _runtime_point_chart(chart_name, run_id, source, points, "Run classification", "Smoke classification flag", "Smoke exposure is derived only from the persisted RunClass token.", mode="bar", evidence_shape_policy="measured_scalar")
    if chart_name == "assumption usage summaries":
        source = "reports/csv/value_source_audit.csv"
        _, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, source)
        roles = Counter(_row_text(row, "ValueRole") or "unspecified" for row in rows)
        points = [[float(index), float(count)] for index, (_role, count) in enumerate(sorted(roles.items()), start=1)]
        return _runtime_point_chart(chart_name, run_id, source, points, "Value-role category", "Audited field count", "Counts come from explicit ValueRole classifications in the persisted value-source audit.", mode="bar", evidence_shape_policy="observed_distribution")
    return None


def _runtime_energy_relation_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    if chart_name not in {"power vs throughput", "power vs BLER", "PAPR vs power"}:
        return None
    energy_path = "rf/csv/energy_timeline_trace.csv"
    _, energy_rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, energy_path)
    trial_sources = _all_available_rows(existing, fetch_artifact_bytes, ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"])
    tx_power: dict[tuple[str, int, int], list[float]] = defaultdict(list)
    for row in energy_rows:
        if "tx" not in _row_text(row, "State").lower():
            continue
        direction = _row_text(row, "Direction").upper()
        frame = _row_float(row, "Frame")
        slot = _row_float(row, "Slot")
        power = _row_float(row, "Power_W")
        if direction and frame is not None and slot is not None and power is not None:
            tx_power[(direction, int(round(frame)), int(round(slot)))].append(float(power))
    points: list[list[float]] = []
    for source_path, rows in trial_sources:
        default_direction = "DL" if "dl_pdsch" in source_path else "UL"
        for row in rows:
            direction = _row_text(row, "Direction").upper() or default_direction
            frame = _row_float(row, "Frame")
            slot = _row_float(row, "Slot")
            if frame is None or slot is None:
                continue
            powers = tx_power.get((direction, int(round(frame)), int(round(slot))), [])
            if not powers:
                continue
            power = sum(powers) / len(powers)
            if chart_name == "power vs throughput":
                metric = _row_float(row, "Goodput_Mbps", "Throughput_Mbps")
                if metric is None:
                    bits = _row_float(row, "GoodBits")
                    duration_ms = _row_float(row, "AirInterfaceTTI_ms")
                    metric = bits / max(duration_ms, 1e-12) / 1000.0 if bits is not None and duration_ms is not None else None
            elif chart_name == "power vs BLER":
                metric = _trial_row_bler(row)
            else:
                metric = _row_float(row, "PAPR_dB")
            if metric is not None:
                points.append([power, float(metric)])
    y_label = {"power vs throughput": "Goodput (Mbps)", "power vs BLER": "BLER", "PAPR vs power": "PAPR (dB)"}[chart_name]
    unique_power = _unique_numeric_count([point[0] for point in points])
    return _runtime_point_chart(
        chart_name,
        run_id,
        energy_path + "|air_interface/csv/*_trials.csv",
        points,
        "TX power (W)",
        y_label,
        "Power is joined to waveform trial metrics by exact direction/frame/slot keys; constant BLER remains a measured outcome and no correlation fit is claimed.",
        mode="bar" if unique_power <= 1 else "scatter",
        evidence_shape_policy="operating_point" if unique_power <= 1 else "observed_relation",
    )


def _runtime_cfo_tracking_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    if str(chart_name or "").strip() != "CFO true vs estimated vs residual":
        return None
    source_path, rows = _first_available_rows(
        existing,
        fetch_artifact_bytes,
        ["reports/csv/cfo_to_tracking_traces.csv"],
    )
    if not rows:
        return None
    csv_rows: list[dict[str, Any]] = []
    series: dict[str, list[tuple[float, float]]] = {
        "True CFO": [],
        "Estimated CFO": [],
        "Residual CFO": [],
    }
    for row in rows:
        true_cfo = _row_float(row, "TrueCFO_Hz")
        estimated_cfo = _row_float(
            row, "EstimatedCFO_PreCorrection_Hz", "EstimatedCFO_Hz"
        )
        residual_cfo = _row_float(row, "ResidualCFO_PostCorrection_Hz")
        if true_cfo is None and estimated_cfo is None and residual_cfo is None:
            continue
        sample_index = float(len(csv_rows) + 1)
        csv_rows.append({
            "run_id": run_id,
            "chart_name": chart_name,
            "sample_index": int(sample_index),
            "trace_source": _row_text(row, "TraceSource"),
            "direction": _row_text(row, "Direction"),
            "frame": _row_text(row, "Frame"),
            "slot": _row_text(row, "Slot"),
            "true_cfo_hz": "" if true_cfo is None else float(true_cfo),
            "estimated_cfo_hz": "" if estimated_cfo is None else float(estimated_cfo),
            "residual_cfo_hz": "" if residual_cfo is None else float(residual_cfo),
            "source_table_logical_path": source_path,
        })
        if true_cfo is not None:
            series["True CFO"].append((sample_index, float(true_cfo)))
        if estimated_cfo is not None:
            series["Estimated CFO"].append((sample_index, float(estimated_cfo)))
        if residual_cfo is not None:
            series["Residual CFO"].append((sample_index, float(residual_cfo)))
    if not csv_rows or any(not series[name] for name in series):
        return None
    summary = [
        f"source={source_path}",
        f"rows={len(csv_rows)}",
        "missing values remain blank",
        "no configured-value substitution",
    ]
    return {
        "csv_bytes": _encode_dict_rows(
            [
                "run_id", "chart_name", "sample_index", "trace_source",
                "direction", "frame", "slot", "true_cfo_hz",
                "estimated_cfo_hz", "residual_cfo_hz",
                "source_table_logical_path",
            ],
            csv_rows,
        ),
        "img_bytes": _render_multi_series_svg(
            chart_name,
            "Persisted runtime CFO truth, receiver estimate, and post-correction residual.",
            [
                {"name": name, "points": [[x, y] for x, y in points]}
                for name, points in series.items()
            ],
            summary,
            x_label="Runtime observation index",
            y_label="CFO (Hz)",
        ),
        "csv_status": "explicit_runtime_cfo_tracking_dataset",
        "image_status": "generated_runtime_cfo_tracking_svg",
        "source_table_path": source_path,
        "source_row_count": len(csv_rows),
        "source_mapping_status": "exact",
        "note": "CFO series use only persisted runtime truth, estimate, and residual fields.",
    }


def _runtime_reference_signal_occupancy_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    if str(chart_name or "").lower() not in {
        "dmrs/ptrs occupancy plot", "dmrs/ptrs occupancy map"
    }:
        return None
    sources = _all_available_rows(
        existing,
        fetch_artifact_bytes,
        ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"],
    )
    csv_rows: list[dict[str, Any]] = []
    totals: Counter[str] = Counter()
    for source_path, rows in sources:
        direction_default = "DL" if "dl_pdsch" in source_path else "UL"
        for index, row in enumerate(rows, start=1):
            dmrs = _row_float(row, "DMRSRECount", "MeasuredDMRSRECount")
            ptrs = _row_float(row, "PTRSRECount")
            data = _row_float(row, "DataRECount", "TotalDataRECount")
            if dmrs is None and ptrs is None:
                continue
            direction = _row_text(row, "Direction").upper() or direction_default
            dmrs_value = float(dmrs or 0.0)
            ptrs_value = float(ptrs or 0.0)
            totals[f"{direction} DM-RS"] += dmrs_value
            totals[f"{direction} PT-RS"] += ptrs_value
            csv_rows.append({
                "run_id": run_id,
                "chart_name": chart_name,
                "direction": direction,
                "trial_index": index,
                "frame": _row_text(row, "Frame"),
                "slot": _row_text(row, "Slot"),
                "dmrs_re_count": dmrs_value,
                "ptrs_re_count": ptrs_value,
                "data_re_count": "" if data is None else float(data),
                "ptrs_configured_enabled": _row_text(row, "PTRSConfiguredEnabled"),
                "source_table_logical_path": source_path,
            })
    if not csv_rows:
        return None
    named_values = [(name, float(value)) for name, value in sorted(totals.items())]
    dataset, labels = _bar_dataset_from_named_values(
        "Direction/reference-signal bucket", "Occupied RE count", named_values
    )
    dataset["tick_labels"] = [name for name, _value in named_values]
    return {
        "csv_bytes": _encode_dict_rows(
            [
                "run_id", "chart_name", "direction", "trial_index", "frame",
                "slot", "dmrs_re_count", "ptrs_re_count", "data_re_count",
                "ptrs_configured_enabled", "source_table_logical_path",
            ],
            csv_rows,
        ),
        "img_bytes": _render_svg_plot(
            chart_name,
            "Measured DM-RS/PT-RS resource occupancy from executed PDSCH/PUSCH trials.",
            dataset,
            labels + [f"runtime_trials={len(csv_rows)}"],
        ),
        "csv_status": "specialized_runtime_rs_occupancy_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": "|".join(path for path, _rows in sources),
        "source_row_count": len(csv_rows),
        "source_mapping_status": "exact",
        "note": "Occupancy uses measured DMRSRECount/PTRSRECount fields from the executed waveform chain.",
    }


def _runtime_papr_distribution_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    if str(chart_name or "").lower() != "papr histogram / cdf":
        return None
    sources = _all_available_rows(
        existing,
        fetch_artifact_bytes,
        ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"],
    )
    values: list[float] = []
    rows_out: list[dict[str, Any]] = []
    for source_path, rows in sources:
        for index, row in enumerate(rows, start=1):
            value = _row_float(row, "PAPR_dB")
            if value is None or not math.isfinite(float(value)):
                continue
            values.append(float(value))
            rows_out.append({
                "run_id": run_id,
                "chart_name": chart_name,
                "trial_index": index,
                "direction": _row_text(row, "Direction"),
                "frame": _row_text(row, "Frame"),
                "slot": _row_text(row, "Slot"),
                "papr_db": float(value),
                "source_table_logical_path": source_path,
            })
    if not values:
        return None
    points = _histogram_points(values, min(18, max(2, len(values))))
    dataset = {"mode": "bar", "x_label": "PAPR (dB)", "y_label": "Trial count", "points": points}
    summary = [
        f"runtime_trials={len(values)}",
        f"min_papr_db={min(values):.6g}",
        f"mean_papr_db={sum(values)/len(values):.6g}",
        f"max_papr_db={max(values):.6g}",
    ]
    return {
        "csv_bytes": _encode_dict_rows(
            ["run_id", "chart_name", "trial_index", "direction", "frame", "slot", "papr_db", "source_table_logical_path"],
            rows_out,
        ),
        "img_bytes": _render_svg_plot(
            chart_name,
            "PAPR distribution from the actual executed PDSCH/PUSCH waveform trials.",
            dataset,
            summary,
        ),
        "csv_status": "specialized_runtime_papr_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": "|".join(path for path, _rows in sources),
        "source_row_count": len(values),
        "source_mapping_status": "exact",
        "note": "PAPR distribution uses only finite PAPR_dB fields from executed waveform trials.",
    }


def _runtime_prach_operational_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    chart_key = str(chart_name or "").strip().lower()
    handled = {
        "prach occasion timeline", "ta estimate timeline", "preamble usage chart",
        "ta estimate trend", "access attempt/success timeline",
        "timing offset true vs estimated vs residual", "prach opportunity map",
        "access latency", "retry count distribution", "timing advance distribution",
        "preamble/root/cyclic-shift usage summary",
        "prach peak search timeline", "noise floor trend",
    }
    if chart_key not in handled:
        return None
    source_path, records = _first_available_rows(
        existing,
        fetch_artifact_bytes,
        [
            "air_interface/csv/prach_trials.csv",
            "control/csv/prach_trials.csv",
            "components/prach/csv/prach_detection_trials.csv",
        ],
    )
    if not records:
        return None
    out_rows: list[dict[str, Any]] = []
    for index, row in enumerate(records, start=1):
        occasion_frame = _row_float(row, "PRACHOccasionFrame", "SFN")
        occasion_slot = _row_float(row, "PRACHOccasionSlot", "Slot")
        occasion_symbol = _row_float(row, "PRACHOccasionSymbol")
        occasion_frequency = _row_float(row, "PRACHFrequencyIndex")
        attempt = _row_float(row, "PreambleAttemptNumber", "RAAttemptId")
        success_flag = _row_flag(row, "RACompleted", "PreambleDetected", "Detected", "DecodeSuccess")
        true_timing = _row_float(row, "PRACHTrueTimingOffset_samples", "TrueTimingOffset_samples")
        estimate = _row_float(
            row,
            "PRACHRawTimingEstimate_samples",
            "TimingEstimate_samples",
            "EstimatedTimingOffset_samples",
        )
        timing_error = _row_float(row, "PRACHTimingError_samples", "TimingError_samples")
        correlation_peak = _row_float(row, "CorrelationPeak", "DetectionMetric", "PreambleDetectionMetric")
        detection_threshold = _row_float(row, "DetectionThreshold", "PreambleDetectionThreshold")
        noise_floor = _row_float(
            row,
            "PDPAverageNoiseFloor",
            "ThresholdBackgroundComponent",
            "DetectorNoiseFloor",
        )
        peak_lag = _row_float(row, "DetectorPeakLagSamples", "PRACHRawTimingEstimate_samples")
        setup_slot = _row_float(row, "SetupCompleteScheduledSlot")
        latency_slots = None
        if setup_slot is not None and occasion_slot is not None:
            latency_slots = float(setup_slot) - float(occasion_slot)
        out_rows.append({
            "run_id": run_id,
            "chart_name": chart_name,
            "observation_index": index,
            "ue_id": _row_text(row, "RAUEId", "UEIndex", "UEId"),
            "occasion_id": _row_text(row, "PRACHOccasionID", "OccasionID"),
            "occasion_frame": "" if occasion_frame is None else float(occasion_frame),
            "occasion_slot": "" if occasion_slot is None else float(occasion_slot),
            "occasion_symbol": "" if occasion_symbol is None else float(occasion_symbol),
            "occasion_frequency_index": "" if occasion_frequency is None else float(occasion_frequency),
            "preamble_index_tx": _row_text(row, "PreambleIndexTx", "PreambleIndex"),
            "preamble_index_detected": _row_text(row, "PreambleIndexDetected", "DetectedPreambleIndex"),
            "root_sequence_index": _row_text(row, "RootSequenceIndex", "PRACHRootSequenceIndex"),
            "cyclic_shift_ncs": _row_text(row, "CyclicShift", "NCS", "n_cs"),
            "attempt_number": "" if attempt is None else float(attempt),
            "success_flag": "" if success_flag is None else int(bool(success_flag)),
            "true_timing_offset_samples": "" if true_timing is None else float(true_timing),
            "estimated_timing_offset_samples": "" if estimate is None else float(estimate),
            "timing_error_samples": "" if timing_error is None else float(timing_error),
            "correlation_peak": "" if correlation_peak is None else float(correlation_peak),
            "detection_threshold": "" if detection_threshold is None else float(detection_threshold),
            "noise_floor": "" if noise_floor is None else float(noise_floor),
            "detector_peak_lag_samples": "" if peak_lag is None else float(peak_lag),
            "timing_advance_command": _row_text(row, "TimingAdvanceCommand"),
            "access_latency_slots": "" if latency_slots is None else latency_slots,
            "source_table_logical_path": source_path,
        })

    dataset: dict[str, Any] | None = None
    summary: list[str] = [f"source={source_path}", f"runtime_rows={len(out_rows)}"]
    if chart_key in {"prach occasion timeline", "prach opportunity map"}:
        counts = Counter(str(row["occasion_id"] or f"frame={row['occasion_frame']}|slot={row['occasion_slot']}|symbol={row['occasion_symbol']}") for row in out_rows)
        named = list(counts.items())
        dataset, labels = _bar_dataset_from_named_values("PRACH occasion", "Attempts", [(key, float(value)) for key, value in named])
        dataset["tick_labels"] = [key for key, _value in named]
        summary.extend(labels)
    elif chart_key in {"ta estimate timeline", "ta estimate trend"}:
        points = [[float(row["observation_index"]), float(row["estimated_timing_offset_samples"])] for row in out_rows if row["estimated_timing_offset_samples"] != ""]
        dataset = {"mode": "bar", "x_label": "PRACH observation", "y_label": "Timing estimate (samples)", "points": points, "evidence_shape_policy": "observed_distribution", "sample_count": len(points)}
    elif chart_key == "preamble usage chart":
        counts = Counter(str(row["preamble_index_tx"]) for row in out_rows if str(row["preamble_index_tx"]))
        named = list(sorted(counts.items()))
        dataset, labels = _bar_dataset_from_named_values("Preamble index", "Uses", [(key, float(value)) for key, value in named])
        dataset["tick_labels"] = [key for key, _value in named]
        summary.extend(labels)
    elif chart_key == "access attempt/success timeline":
        successes = sum(int(row["success_flag"]) for row in out_rows if row["success_flag"] != "")
        dataset, labels = _bar_dataset_from_named_values("Access outcome", "Count", [("Attempts", len(out_rows)), ("Successful", successes)])
        dataset["tick_labels"] = ["Attempts", "Successful"]
        summary.extend(labels)
    elif chart_key == "timing offset true vs estimated vs residual":
        true_values = [float(row["true_timing_offset_samples"]) for row in out_rows if row["true_timing_offset_samples"] != ""]
        estimated_values = [float(row["estimated_timing_offset_samples"]) for row in out_rows if row["estimated_timing_offset_samples"] != ""]
        residual_values = [float(row["timing_error_samples"]) for row in out_rows if row["timing_error_samples"] != ""]
        named = [
            ("True", sum(true_values) / len(true_values) if true_values else 0.0),
            ("Estimated", sum(estimated_values) / len(estimated_values) if estimated_values else 0.0),
            ("Residual", sum(residual_values) / len(residual_values) if residual_values else 0.0),
        ]
        dataset, labels = _bar_dataset_from_named_values("Timing quantity", "Mean samples", named)
        dataset["tick_labels"] = [name for name, _value in named]
        summary.extend(labels)
    elif chart_key == "access latency":
        points = [[float(row["observation_index"]), float(row["access_latency_slots"])] for row in out_rows if row["access_latency_slots"] != ""]
        dataset = {"mode": "bar", "x_label": "UE access observation", "y_label": "Msg1-to-SetupComplete slots", "points": points, "evidence_shape_policy": "observed_distribution", "sample_count": len(points)}
    elif chart_key == "retry count distribution":
        retries = [max(int(round(float(row["attempt_number"]))) - 1, 0) for row in out_rows if row["attempt_number"] != ""]
        counts = Counter(retries)
        dataset, labels = _bar_dataset_from_named_values("Retry count", "UE count", [(str(key), float(value)) for key, value in sorted(counts.items())])
        dataset["tick_labels"] = [str(key) for key in sorted(counts)]
        summary.extend(labels)
    elif chart_key == "timing advance distribution":
        values = [float(row["timing_advance_command"]) for row in out_rows if _coerce_float(row["timing_advance_command"]) is not None]
        counts = Counter(values)
        dataset, labels = _bar_dataset_from_named_values("Timing-advance command", "UE count", [(str(key), float(value)) for key, value in sorted(counts.items())])
        dataset["tick_labels"] = [str(key) for key in sorted(counts)]
        summary.extend(labels)
    elif chart_key == "preamble/root/cyclic-shift usage summary":
        preambles = {str(row["preamble_index_tx"]) for row in out_rows if str(row["preamble_index_tx"])}
        roots = {str(row["root_sequence_index"]) for row in out_rows if str(row["root_sequence_index"])}
        shifts = {str(row["cyclic_shift_ncs"]) for row in out_rows if str(row["cyclic_shift_ncs"])}
        dataset, labels = _bar_dataset_from_named_values(
            "PRACH identity field",
            "Distinct observed values",
            [
                ("Preambles", float(len(preambles))),
                ("Roots", float(len(roots))),
                ("Cyclic shifts", float(len(shifts))),
            ],
        )
        dataset["tick_labels"] = ["Preambles", "Roots", "Cyclic shifts"]
        summary.extend(labels)
        summary.extend(["missing root/shift values remain unavailable", "configured values are not substituted"])
    elif chart_key == "prach peak search timeline":
        peak_points = [[float(row["observation_index"]), float(row["correlation_peak"])] for row in out_rows if row["correlation_peak"] != ""]
        threshold_points = [[float(row["observation_index"]), float(row["detection_threshold"])] for row in out_rows if row["detection_threshold"] != ""]
        if len(out_rows) == 1 and peak_points and threshold_points:
            dataset = {
                "mode": "bar",
                "x_label": "Detector quantity",
                "y_label": "Detector metric",
                "points": [[1.0, peak_points[0][1]], [2.0, threshold_points[0][1]]],
                "tick_labels": ["Correlation peak", "Detection threshold"],
                "sample_count": 1,
                "evidence_shape_policy": "operating_point",
            }
            summary.extend(["bucket_1=Correlation peak", "bucket_2=Detection threshold"])
        elif peak_points:
            dataset = {
                "mode": "line",
                "x_label": "PRACH observation",
                "y_label": "Correlation peak",
                "points": peak_points,
                "sample_count": len(peak_points),
                "evidence_shape_policy": "observed_timeline",
            }
    elif chart_key == "noise floor trend":
        points = [[float(row["observation_index"]), float(row["noise_floor"])] for row in out_rows if row["noise_floor"] != ""]
        dataset = {"mode": "line" if len(points) > 1 else "bar", "x_label": "PRACH observation", "y_label": "Measured PDP noise floor", "points": points, "evidence_shape_policy": "operating_point" if len(points) == 1 else "observed_timeline", "sample_count": len(points)}

    if dataset and dataset.get("points"):
        dataset.setdefault("sample_count", len(out_rows))
        dataset.setdefault("evidence_shape_policy", "observed_distribution")
        img_bytes = _render_svg_plot(
            chart_name,
            "Exact PRACH/initial-access observations from the executed four-step waveform chain.",
            dataset,
            summary,
        )
    else:
        return None
    return {
        "csv_bytes": _encode_dict_rows(
            [
                "run_id", "chart_name", "observation_index", "ue_id", "occasion_id",
                "occasion_frame", "occasion_slot", "occasion_symbol", "occasion_frequency_index",
                "preamble_index_tx", "preamble_index_detected", "root_sequence_index",
                "cyclic_shift_ncs", "attempt_number", "success_flag",
                "true_timing_offset_samples", "estimated_timing_offset_samples",
                "timing_error_samples", "correlation_peak", "detection_threshold",
                "noise_floor", "detector_peak_lag_samples", "timing_advance_command", "access_latency_slots",
                "source_table_logical_path",
            ],
            out_rows,
        ),
        "img_bytes": img_bytes,
        "csv_status": "specialized_runtime_prach_operational_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": source_path,
        "source_row_count": len(records),
        "source_mapping_status": "exact",
        "note": "PRACH operational view uses only executed four-step random-access runtime rows.",
    }


def _runtime_sensing_probability_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    """Materialize operational ISAC detection rates from persisted runtime rows.

    The false-alarm value is intentionally a per-evaluated-CFAR-cell fraction,
    not a Monte-Carlo P_FA claim.  This keeps a single-scene diagnostic honest
    while exposing the exact numerator and denominator needed for audit.
    """
    if str(chart_name or "") != "sensing P_D / P_FA":
        return None

    runtime_path, runtime_rows = _first_available_rows(
        existing, fetch_artifact_bytes, ["isac/csv/isac_runtime_evidence.csv"]
    )
    target_path, target_rows = _first_available_rows(
        existing, fetch_artifact_bytes, ["isac/csv/isac_target_truth.csv"]
    )
    detection_path, detection_rows = _first_available_rows(
        existing, fetch_artifact_bytes, ["isac/csv/isac_detections.csv"]
    )
    cfar_path, cfar_rows = _first_available_rows(
        existing, fetch_artifact_bytes, ["isac/csv/isac_cfar_thresholds.csv"]
    )
    if not runtime_rows or not target_rows or not cfar_rows:
        return None

    target_ids = {
        _row_text(row, "TargetId") for row in target_rows if _row_text(row, "TargetId")
    }
    matched_target_ids = {
        _row_text(row, "MatchedTargetId")
        for row in detection_rows
        if (_row_float(row, "AcceptanceMatch") or 0.0) > 0.0
        and _row_text(row, "MatchedTargetId")
    }
    target_count = len(target_ids)
    matched_target_count = len(matched_target_ids.intersection(target_ids))
    raw_detection_count = sum(
        1 for row in cfar_rows if (_row_float(row, "RawDetection") or 0.0) > 0.0
    )
    accepted_detection_count = sum(
        1 for row in detection_rows if (_row_float(row, "AcceptanceMatch") or 0.0) > 0.0
    )
    false_alarm_count = max(raw_detection_count - accepted_detection_count, 0)
    false_alarm_opportunities = max(len(cfar_rows) - target_count, 1)
    detection_fraction = matched_target_count / target_count if target_count else 0.0
    false_alarm_cell_fraction = false_alarm_count / false_alarm_opportunities

    source_paths = ";".join(
        [runtime_path, target_path, detection_path, cfar_path]
    )
    csv_rows = [
        {
            "run_id": run_id,
            "chart_name": chart_name,
            "metric": "observed_target_detection_fraction",
            "value": detection_fraction,
            "numerator": matched_target_count,
            "denominator": target_count,
            "statistical_scope": "single_runtime_scene_not_monte_carlo_probability",
            "source_table_logical_paths": source_paths,
        },
        {
            "run_id": run_id,
            "chart_name": chart_name,
            "metric": "observed_false_alarm_cell_fraction",
            "value": false_alarm_cell_fraction,
            "numerator": false_alarm_count,
            "denominator": false_alarm_opportunities,
            "statistical_scope": "evaluated_range_angle_cfar_cells_not_campaign_pfa",
            "source_table_logical_paths": source_paths,
        },
    ]
    dataset = {
        "mode": "bar",
        "x_label": "Operational metric",
        "y_label": "Observed fraction",
        "points": [[1.0, detection_fraction], [2.0, false_alarm_cell_fraction]],
        "tick_labels": ["target detect", "false-alarm cells"],
    }
    summary = [
        f"targets={target_count}",
        f"matched_targets={matched_target_count}",
        f"cfar_cells={len(cfar_rows)}",
        f"raw_detections={raw_detection_count}",
        f"accepted_detections={accepted_detection_count}",
        "scope=single runtime scene",
        "P_FA campaign claim=not made",
    ]
    return {
        "csv_bytes": _encode_dict_rows(
            [
                "run_id", "chart_name", "metric", "value", "numerator",
                "denominator", "statistical_scope", "source_table_logical_paths",
            ],
            csv_rows,
        ),
        "img_bytes": _render_svg_plot(
            chart_name,
            "Actual ISAC target detection and evaluated-CFAR-cell false alarms",
            dataset,
            summary,
        ),
        "csv_status": "explicit_runtime_isac_detection_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": runtime_path,
        "source_row_count": len(runtime_rows) + len(target_rows) + len(detection_rows) + len(cfar_rows),
        "source_mapping_status": "exact",
        "note": (
            "Detection fraction and false-alarm cell fraction use only persisted ISAC runtime rows; "
            "the single-scene result is not labeled as a Monte-Carlo P_D/P_FA qualification."
        ),
    }


def _runtime_energy_summary_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    """Build energy charts only from persisted runtime accounting rows.

    The energy summary contains state-conditioned engineering-model values
    whose denominators are observed successful transport blocks.  The state
    timeline is the corresponding per-observation runtime ledger.  This
    adapter deliberately omits unavailable metrics and unobserved states;
    it never creates zero-valued sleep/idle samples to fill a chart shape.
    """

    supported = {
        "sleep-state timeline",
        "sleep/idle/active state occupancy",
        "efficiency scatter plots",
        "energy/bit",
        "joules/GB",
        "energy efficiency by UE",
        "energy efficiency by cell",
    }
    if chart_name not in supported:
        return None

    summary_path = "reports/csv/live_energy_efficiency_table.csv"
    timeline_paths = [
        "rf/csv/energy_timeline_trace.csv",
        "reports/csv/live_sleep_state_table.csv",
    ]
    _summary_header, summary_rows = _artifact_rows_by_path(
        existing, fetch_artifact_bytes, summary_path
    )
    timeline_path, timeline_rows = _first_available_rows(
        existing, fetch_artifact_bytes, timeline_paths
    )

    def available_metric(metric_key: str, entity: str) -> tuple[float, dict[str, str]] | None:
        for row in summary_rows:
            if _row_text(row, "MetricKey").strip().lower() != metric_key.lower():
                continue
            if _row_text(row, "Entity").strip().lower() != entity.lower():
                continue
            availability = _row_text(row, "Availability").strip().lower()
            value = _row_float(row, "Value")
            if availability not in {"", "available"} or value is None or not math.isfinite(value):
                continue
            return float(value), row
        return None

    if chart_name in {
        "energy/bit", "joules/GB", "energy efficiency by UE",
        "energy efficiency by cell",
    }:
        requested_entities = {
            "energy/bit": [("UE", "ue_energy_per_successful_bit"), ("gNB", "gnb_energy_per_successful_bit")],
            "joules/GB": [("UE", "ue_energy_per_successful_bit"), ("gNB", "gnb_energy_per_successful_bit")],
            "energy efficiency by UE": [("UE aggregate", "ue_energy_per_successful_bit")],
            "energy efficiency by cell": [("gNB aggregate", "gnb_energy_per_successful_bit")],
        }[chart_name]
        rows_out: list[dict[str, Any]] = []
        points: list[list[float]] = []
        tick_labels: list[str] = []
        for label, metric_key in requested_entities:
            source_entity = "UE" if metric_key.startswith("ue_") else "gNB"
            matched = available_metric(metric_key, source_entity)
            if matched is None:
                continue
            joules_per_bit, source_row = matched
            if not (joules_per_bit > 0):
                continue
            if chart_name == "joules/GB":
                value = joules_per_bit * 8.0e9
                unit = "J/GB"
                statistic = "runtime_energy_per_decimal_gigabyte"
            elif chart_name.startswith("energy efficiency by"):
                value = 1.0 / joules_per_bit
                unit = "bit/J"
                statistic = "runtime_successful_bit_energy_efficiency"
            else:
                value = joules_per_bit
                unit = "J/bit"
                statistic = "runtime_energy_per_successful_bit"
            bucket = len(points) + 1
            points.append([float(bucket), float(value)])
            tick_labels.append(label)
            rows_out.append({
                "run_id": run_id,
                "chart_name": chart_name,
                "entity": label,
                "metric": statistic,
                "value": value,
                "unit": unit,
                "source_metric_key": metric_key,
                "source_evidence_type": _row_text(source_row, "EvidenceType"),
                "source_model_version": _row_text(source_row, "ModelVersion"),
                "source_table_logical_path": summary_path,
            })
        if not rows_out:
            return None
        y_label = rows_out[0]["unit"]
        dataset = {
            "mode": "bar",
            "x_label": "Runtime energy-accounting entity",
            "y_label": y_label,
            "points": points,
            "tick_labels": tick_labels,
            "evidence_shape_policy": "observed_distribution",
            "sample_count": len(rows_out),
        }
        return {
            "csv_bytes": _encode_dict_rows(
                [
                    "run_id", "chart_name", "entity", "metric", "value",
                    "unit", "source_metric_key", "source_evidence_type",
                    "source_model_version", "source_table_logical_path",
                ],
                rows_out,
            ),
            "img_bytes": _render_svg_plot(
                chart_name,
                "Runtime-conditioned energy accounting divided by observed successful transport-block bits.",
                dataset,
                [
                    f"entities={len(rows_out)}",
                    f"source={summary_path}",
                    "configured circuit terms + measured runtime state durations",
                ],
            ),
            "csv_status": "specialized_runtime_energy_summary_dataset",
            "image_status": "generated_specialized_runtime_summary_svg",
            "source_table_path": summary_path,
            "source_row_count": len(rows_out),
            "source_mapping_status": "exact",
            "note": "Unavailable energy metrics and unobserved entity groups are omitted rather than replaced with configured or zero-valued rows.",
        }

    if not timeline_rows or not timeline_path:
        return None

    if chart_name == "sleep-state timeline":
        observed: list[tuple[dict[str, str], str, float, float]] = []
        states: list[str] = []
        for row in timeline_rows:
            duration = _row_float(row, "Duration_s")
            state = _row_text(row, "State")
            if duration is None or duration <= 0 or not state:
                continue
            normalized = _normalize_drx_state(state)
            if normalized not in states:
                states.append(normalized)
            timestamp = _row_float(row, "TimestampSim_ms")
            observed.append((row, normalized, float(timestamp or 0.0), float(duration)))
        if not observed:
            return None
        state_codes = {state: index + 1 for index, state in enumerate(states)}
        rows_out = []
        points = []
        for event_index, (row, state, timestamp, duration) in enumerate(observed, 1):
            state_code = state_codes[state]
            points.append([float(event_index), float(state_code)])
            rows_out.append({
                "run_id": run_id,
                "chart_name": chart_name,
                "event_index": event_index,
                "timestamp_sim_ms": timestamp,
                "entity": _row_text(row, "Entity"),
                "direction": _row_text(row, "Direction"),
                "observed_state": _row_text(row, "State"),
                "normalized_state": state,
                "state_code": state_code,
                "duration_s": duration,
                "transport_block_id": _row_text(row, "TransportBlockId"),
                "source_table_logical_path": timeline_path,
            })
        dataset = {
            "mode": "line",
            "x_label": "Runtime observation event",
            "y_label": "Observed state code",
            "points": points,
            "evidence_shape_policy": "observed_timeline",
            "sample_count": len(points),
        }
        state_summary = [f"state_{code}={state}" for state, code in state_codes.items()]
        return {
            "csv_bytes": _encode_dict_rows(
                [
                    "run_id", "chart_name", "event_index", "timestamp_sim_ms",
                    "entity", "direction", "observed_state", "normalized_state",
                    "state_code", "duration_s", "transport_block_id",
                    "source_table_logical_path",
                ], rows_out,
            ),
            "img_bytes": _render_svg_plot(
                chart_name,
                "State sequence from the persisted runtime energy ledger; state codes are listed in the evidence summary.",
                dataset,
                state_summary + [f"events={len(points)}", f"source={timeline_path}"],
            ),
            "csv_status": "specialized_runtime_energy_state_timeline_dataset",
            "image_status": "generated_specialized_runtime_summary_svg",
            "source_table_path": timeline_path,
            "source_row_count": len(points),
            "source_mapping_status": "exact",
            "note": "Only observed states are plotted; no idle or sleep event is synthesized.",
        }

    if chart_name == "sleep/idle/active state occupancy":
        duration_by_state: dict[str, float] = {}
        event_count_by_state: dict[str, int] = {}
        for row in timeline_rows:
            duration = _row_float(row, "Duration_s")
            state = _row_text(row, "State")
            if duration is None or duration <= 0 or not state:
                continue
            normalized = _normalize_drx_state(state)
            duration_by_state[normalized] = duration_by_state.get(normalized, 0.0) + float(duration)
            event_count_by_state[normalized] = event_count_by_state.get(normalized, 0) + 1
        total_duration = sum(duration_by_state.values())
        if total_duration <= 0:
            return None
        rows_out = []
        points = []
        tick_labels = []
        for bucket, state in enumerate(sorted(duration_by_state), 1):
            fraction = duration_by_state[state] / total_duration
            points.append([float(bucket), float(fraction)])
            tick_labels.append(state)
            rows_out.append({
                "run_id": run_id,
                "chart_name": chart_name,
                "state": state,
                "event_count": event_count_by_state[state],
                "duration_s": duration_by_state[state],
                "occupancy_fraction": fraction,
                "source_table_logical_path": timeline_path,
            })
        dataset = {
            "mode": "bar",
            "x_label": "Observed runtime state",
            "y_label": "Duration-weighted occupancy fraction",
            "points": points,
            "tick_labels": tick_labels,
            "y_axis_min": 0.0,
            "y_axis_max": 1.0,
            "evidence_shape_policy": "observed_distribution",
            "sample_count": sum(event_count_by_state.values()),
        }
        return {
            "csv_bytes": _encode_dict_rows(
                [
                    "run_id", "chart_name", "state", "event_count",
                    "duration_s", "occupancy_fraction", "source_table_logical_path",
                ], rows_out,
            ),
            "img_bytes": _render_svg_plot(
                chart_name,
                "Duration-weighted occupancy of states present in the runtime energy ledger.",
                dataset,
                [f"observed_states={len(rows_out)}", f"runtime_events={dataset['sample_count']}", f"source={timeline_path}"],
            ),
            "csv_status": "specialized_runtime_energy_state_occupancy_dataset",
            "image_status": "generated_specialized_runtime_summary_svg",
            "source_table_path": timeline_path,
            "source_row_count": int(dataset["sample_count"]),
            "source_mapping_status": "exact",
            "note": "Occupancy is normalized across observed state-duration rows only; absent states are not assigned artificial zero rows.",
        }

    # Energy-versus-delivered-bits scatter uses one transmitter-side row per
    # executed transport-block observation. Receiver duplicates are excluded.
    rows_out = []
    points = []
    for row in timeline_rows:
        entity = _row_text(row, "Entity").strip().upper()
        direction = _row_text(row, "Direction").strip().upper()
        if not ((direction == "DL" and entity == "GNB") or (direction == "UL" and entity == "UE")):
            continue
        energy_j = _row_float(row, "Energy_J")
        successful_bits = _row_float(row, "SuccessfulBits")
        if energy_j is None or energy_j < 0 or successful_bits is None or successful_bits < 0:
            continue
        points.append([float(energy_j), float(successful_bits)])
        rows_out.append({
            "run_id": run_id,
            "chart_name": chart_name,
            "event_index": len(points),
            "entity": _row_text(row, "Entity"),
            "direction": _row_text(row, "Direction"),
            "energy_j": energy_j,
            "successful_bits": successful_bits,
            "successful_bits_per_joule": (successful_bits / energy_j) if energy_j > 0 else float("nan"),
            "transport_block_id": _row_text(row, "TransportBlockId"),
            "source_table_logical_path": timeline_path,
        })
    if not rows_out:
        return None
    dataset = {
        "mode": "scatter",
        "x_label": "Runtime event energy (J)",
        "y_label": "Successfully delivered bits",
        "points": points,
        "evidence_shape_policy": "observed_relation",
        "sample_count": len(points),
    }
    return {
        "csv_bytes": _encode_dict_rows(
            [
                "run_id", "chart_name", "event_index", "entity", "direction",
                "energy_j", "successful_bits", "successful_bits_per_joule",
                "transport_block_id", "source_table_logical_path",
            ], rows_out,
        ),
        "img_bytes": _render_svg_plot(
            chart_name,
            "Transmitter-side runtime event energy versus observed successfully delivered bits.",
            dataset,
            [f"transmitter_events={len(points)}", f"source={timeline_path}"],
        ),
        "csv_status": "specialized_runtime_energy_efficiency_scatter_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": timeline_path,
        "source_row_count": len(points),
        "source_mapping_status": "exact",
        "note": "Each point is a persisted transmitter-side waveform observation; failed deliveries remain at zero delivered bits.",
    }


def _runtime_phy_signal_diagnostic_chart(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    """Materialize plots from the bounded same-trial PHY array capture.

    The producer writes this table while the actual transmitter waveform,
    receiver-input waveform, and receiver channel estimate coexist in memory.
    This adapter deliberately does not use configured SNR, aggregate trial
    metrics, or preview/fallback rows to reconstruct missing sample arrays.
    """
    supported = {
        "pre-channel waveform",
        "post-channel waveform",
        "post-impairment waveform",
        "stage overlay plots",
        "UE-wise / link-wise waveform comparison",
        "true H(tau) if available",
        "estimated Hhat(tau)",
        "true H(f) if available",
        "estimated Hhat(f)",
        "channel heatmap artifact links",
        "channel magnitude heatmap",
        "channel phase heatmap",
    }
    if chart_name not in supported:
        return None

    source_path = "reports/csv/phy_signal_diagnostic_source.csv"
    _header, rows = _artifact_rows_by_path(
        existing, fetch_artifact_bytes, source_path
    )
    if not rows or _is_absence_placeholder_rows(rows):
        return None

    exact_rows = [
        row for row in rows
        if _row_text(row, "Status").strip().lower() == "available"
        and _row_text(row, "truth_status").strip().lower() == "real_lls_evidence"
        and _row_text(row, "SourceArtifact").strip().lower()
        == "runtime_phy_arrays_same_trial"
    ]
    if not exact_rows:
        return None

    if chart_name in {
        "pre-channel waveform", "post-channel waveform", "post-impairment waveform",
        "stage overlay plots", "UE-wise / link-wise waveform comparison",
    }:
        wanted_series = {
            "pre-channel waveform": {"tx"},
            "post-channel waveform": {"post_channel"},
            "post-impairment waveform": {"rx"},
            "stage overlay plots": {"tx", "rx"},
            "UE-wise / link-wise waveform comparison": {"tx", "post_channel", "rx"},
        }[chart_name]
        time_rows = [
            row for row in exact_rows
            if _row_text(row, "Panel") == "time_domain"
            and _row_text(row, "Series").lower() in wanted_series
        ]
        if not time_rows:
            return None

        # Keep one actual capture per direction.  Combining successive trials
        # on a shared zero-based sample axis would create a visually plausible
        # but physically meaningless average waveform.
        selected_snapshots: dict[str, str] = {}
        for row in time_rows:
            direction = _row_text(row, "Direction").upper() or "UNKNOWN"
            ue_index = _row_text(row, "UEIndex") or "UNKNOWN"
            selection_key = f"{direction}|{ue_index}" if chart_name == "UE-wise / link-wise waveform comparison" else direction
            snapshot_id = _row_text(row, "SnapshotID")
            if snapshot_id and selection_key not in selected_snapshots:
                selected_snapshots[selection_key] = snapshot_id
        time_rows = [
            row for row in time_rows
            if _row_text(row, "SnapshotID")
            == selected_snapshots.get(
                (f"{_row_text(row, 'Direction').upper() or 'UNKNOWN'}|{_row_text(row, 'UEIndex') or 'UNKNOWN'}"
                 if chart_name == "UE-wise / link-wise waveform comparison"
                 else (_row_text(row, "Direction").upper() or "UNKNOWN")),
                "",
            )
        ]

        csv_rows: list[dict[str, Any]] = []
        series_points: dict[str, list[list[float]]] = defaultdict(list)
        for row in time_rows:
            x_value = _row_float(row, "XValue")
            i_value = _row_float(row, "IValue")
            q_value = _row_float(row, "QValue")
            if x_value is None or i_value is None or q_value is None:
                continue
            direction = _row_text(row, "Direction").upper() or "UNKNOWN"
            endpoint = _row_text(row, "Series").lower()
            ue_index = _row_text(row, "UEIndex") or "UNKNOWN"
            snapshot_id = _row_text(row, "SnapshotID")
            magnitude = math.hypot(float(i_value), float(q_value))
            if chart_name in {"stage overlay plots", "UE-wise / link-wise waveform comparison"}:
                prefix = f"{direction} UE {ue_index}" if chart_name == "UE-wise / link-wise waveform comparison" else direction
                series_points[f"{prefix} {endpoint} magnitude"].append(
                    [float(x_value), magnitude]
                )
            else:
                series_points[f"{direction} {endpoint} I"].append(
                    [float(x_value), float(i_value)]
                )
                series_points[f"{direction} {endpoint} Q"].append(
                    [float(x_value), float(q_value)]
                )
            csv_rows.append({
                "run_id": run_id,
                "chart_name": chart_name,
                "snapshot_id": snapshot_id,
                "direction": direction,
                "ue_index": _row_text(row, "UEIndex"),
                "cell_id": _row_text(row, "CellID"),
                "sfn": _row_text(row, "SFN"),
                "slot": _row_text(row, "Slot"),
                "sample_index": _row_text(row, "SampleIndex"),
                "time_s": float(x_value),
                "endpoint": endpoint,
                "i_value": float(i_value),
                "q_value": float(q_value),
                "magnitude": magnitude,
                "phase_rad": math.atan2(float(q_value), float(i_value)),
                "sample_rate_hz": _row_text(row, "SampleRate_Hz"),
                "source_table_logical_path": source_path,
            })
        if not csv_rows or not series_points:
            return None
        plot_series = [
            {"name": name, "points": _downsample_points(points, 512)}
            for name, points in sorted(series_points.items())
        ]
        subtitle = {
            "pre-channel waveform": (
                "Exact transmitter output at the pre-channel boundary from the same PHY trial."
            ),
            "post-impairment waveform": (
                "Exact waveform presented to the receiver after channel, noise, and the configured receiver front end."
            ),
            "post-channel waveform": (
                "Exact executed channel output before receiver noise/front-end processing from the same PHY trial."
            ),
            "stage overlay plots": (
                "Exact transmitter pre-channel and receiver-input endpoint magnitudes; no unobserved intermediate stage is invented."
            ),
            "UE-wise / link-wise waveform comparison": (
                "Per-UE and per-direction exact waveform boundary magnitudes from persisted same-trial PHY arrays."
            ),
        }[chart_name]
        return {
            "csv_bytes": _encode_dict_rows(
                [
                    "run_id", "chart_name", "snapshot_id", "direction", "ue_index",
                    "cell_id", "sfn", "slot", "sample_index", "time_s", "endpoint",
                    "i_value", "q_value", "magnitude", "phase_rad", "sample_rate_hz",
                    "source_table_logical_path",
                ],
                csv_rows,
            ),
            "img_bytes": _render_multi_series_svg(
                chart_name, subtitle, plot_series,
                [
                    f"runtime_samples={len(csv_rows)}",
                    f"snapshots={len(set(row['snapshot_id'] for row in csv_rows))}",
                    f"source={source_path}",
                    "evidence=runtime_same_trial_phy_arrays",
                ],
                x_label="Time (s)", y_label="Complex amplitude" if chart_name != "stage overlay plots" else "Magnitude",
            ),
            "csv_status": "specialized_runtime_exact_phy_waveform_dataset",
            "image_status": "generated_specialized_runtime_waveform_svg",
            "source_table_path": source_path,
            "source_row_count": len(csv_rows),
            "source_mapping_status": "exact",
            "note": subtitle,
        }

    if chart_name in {"true H(tau) if available", "estimated Hhat(tau)"}:
        panel = (
            "true_channel_impulse_response"
            if chart_name == "true H(tau) if available"
            else "estimated_channel_impulse_response"
        )
        response_rows = [row for row in exact_rows if _row_text(row, "Panel") == panel]
        if not response_rows:
            return None
        snapshot_id = _row_text(response_rows[0], "SnapshotID")
        response_rows = [row for row in response_rows if _row_text(row, "SnapshotID") == snapshot_id]
        csv_rows: list[dict[str, Any]] = []
        magnitude_points: list[list[float]] = []
        phase_points: list[list[float]] = []
        for row in response_rows:
            delay_s = _row_float(row, "XValue")
            i_value = _row_float(row, "IValue")
            q_value = _row_float(row, "QValue")
            magnitude_db = _row_float(row, "Magnitude_dB")
            phase_deg = _row_float(row, "Phase_deg")
            if delay_s is None or i_value is None or q_value is None or magnitude_db is None or phase_deg is None:
                continue
            delay_ns = float(delay_s) * 1e9
            magnitude_points.append([delay_ns, float(magnitude_db)])
            phase_points.append([delay_ns, float(phase_deg)])
            csv_rows.append({
                "run_id": run_id, "chart_name": chart_name, "snapshot_id": snapshot_id,
                "direction": _row_text(row, "Direction"), "ue_index": _row_text(row, "UEIndex"),
                "cell_id": _row_text(row, "CellID"), "sfn": _row_text(row, "SFN"),
                "slot": _row_text(row, "Slot"), "series": _row_text(row, "Series"),
                "delay_s": float(delay_s), "delay_ns": delay_ns,
                "i_value": float(i_value), "q_value": float(q_value),
                "magnitude_db": float(magnitude_db), "phase_deg": float(phase_deg),
                "tensor_sha256": _row_text(row, "GridSHA256"),
                "source_table_logical_path": source_path,
            })
        if not csv_rows:
            return None
        evidence = "executed_runtime_path_gain_tensor" if panel.startswith("true_") else "receiver_channel_estimate_ifft"
        return {
            "csv_bytes": _encode_dict_rows(
                ["run_id", "chart_name", "snapshot_id", "direction", "ue_index", "cell_id", "sfn", "slot", "series", "delay_s", "delay_ns", "i_value", "q_value", "magnitude_db", "phase_deg", "tensor_sha256", "source_table_logical_path"],
                csv_rows,
            ),
            "img_bytes": _render_multi_series_svg(
                chart_name,
                "Executed complex channel impulse response." if panel.startswith("true_") else "Bandwidth-limited impulse response of the receiver's own complex channel estimate.",
                [
                    {"name": "Magnitude (dB)", "points": magnitude_points},
                    {"name": "Phase (deg)", "points": phase_points},
                ],
                [f"snapshot={snapshot_id}", f"points={len(csv_rows)}", f"source={source_path}", f"evidence={evidence}"],
                x_label="Excess delay (ns)", y_label="Magnitude (dB) / phase (deg)",
            ),
            "csv_status": "specialized_runtime_exact_channel_impulse_dataset",
            "image_status": "generated_specialized_runtime_channel_response_svg",
            "source_table_path": source_path,
            "source_row_count": len(csv_rows),
            "source_mapping_status": "exact",
            "note": "True and estimated channel responses remain explicitly distinguished; neither is reconstructed from configured PDP summaries.",
        }

    if chart_name == "true H(f) if available":
        response_rows = [
            row for row in exact_rows
            if _row_text(row, "Panel") == "true_channel_frequency_response"
        ]
        if not response_rows:
            return None
        snapshot_id = _row_text(response_rows[0], "SnapshotID")
        response_rows = [row for row in response_rows if _row_text(row, "SnapshotID") == snapshot_id]
        csv_rows: list[dict[str, Any]] = []
        magnitude_points: list[list[float]] = []
        phase_points: list[list[float]] = []
        for row in response_rows:
            frequency_hz = _row_float(row, "XValue", "FrequencyOffset_Hz")
            i_value = _row_float(row, "IValue")
            q_value = _row_float(row, "QValue")
            magnitude_db = _row_float(row, "Magnitude_dB", "YValue")
            phase_deg = _row_float(row, "Phase_deg")
            if frequency_hz is None or i_value is None or q_value is None or magnitude_db is None or phase_deg is None:
                continue
            frequency_mhz = float(frequency_hz) / 1e6
            magnitude_points.append([frequency_mhz, float(magnitude_db)])
            phase_points.append([frequency_mhz, float(phase_deg)])
            csv_rows.append({
                "run_id": run_id, "chart_name": chart_name, "snapshot_id": snapshot_id,
                "direction": _row_text(row, "Direction"), "ue_index": _row_text(row, "UEIndex"),
                "cell_id": _row_text(row, "CellID"), "sfn": _row_text(row, "SFN"),
                "slot": _row_text(row, "Slot"), "frequency_offset_hz": float(frequency_hz),
                "i_value": float(i_value), "q_value": float(q_value),
                "magnitude_db": float(magnitude_db), "phase_deg": float(phase_deg),
                "tensor_sha256": _row_text(row, "GridSHA256"),
                "source_table_logical_path": source_path,
            })
        if not csv_rows:
            return None
        return {
            "csv_bytes": _encode_dict_rows(
                ["run_id", "chart_name", "snapshot_id", "direction", "ue_index", "cell_id", "sfn", "slot", "frequency_offset_hz", "i_value", "q_value", "magnitude_db", "phase_deg", "tensor_sha256", "source_table_logical_path"],
                csv_rows,
            ),
            "img_bytes": _render_multi_series_svg(
                chart_name, "Executed H(f) calculated from the same captured complex runtime path gains and delays.",
                [
                    {"name": "Magnitude (dB)", "points": magnitude_points},
                    {"name": "Unwrapped phase (deg)", "points": phase_points},
                ],
                [f"snapshot={snapshot_id}", f"points={len(csv_rows)}", f"source={source_path}", "evidence=executed_runtime_path_gain_tensor"],
                x_label="Frequency offset (MHz)", y_label="Magnitude (dB) / phase (deg)",
            ),
            "csv_status": "specialized_runtime_exact_true_channel_frequency_dataset",
            "image_status": "generated_specialized_runtime_channel_response_svg",
            "source_table_path": source_path,
            "source_row_count": len(csv_rows),
            "source_mapping_status": "exact",
            "note": "H(f) is derived only from executed complex runtime path gains and delays captured from the channel object.",
        }

    if chart_name == "estimated Hhat(f)":
        h_rows = [
            row for row in exact_rows
            if _row_text(row, "Panel") == "channel_estimate"
            and _row_text(row, "Series") == "hest"
        ]
        if not h_rows:
            return None
        snapshot_id = _row_text(h_rows[0], "SnapshotID")
        h_rows = [row for row in h_rows if _row_text(row, "SnapshotID") == snapshot_id]
        csv_rows: list[dict[str, Any]] = []
        magnitude_points: list[list[float]] = []
        phase_points: list[list[float]] = []
        for row in h_rows:
            subcarrier = _row_float(row, "SubcarrierIndex", "XValue")
            magnitude_db = _row_float(row, "Magnitude_dB", "YValue")
            phase_deg = _row_float(row, "Phase_deg")
            if subcarrier is None or magnitude_db is None or phase_deg is None:
                continue
            magnitude_points.append([float(subcarrier), float(magnitude_db)])
            phase_points.append([float(subcarrier), float(phase_deg)])
            csv_rows.append({
                "run_id": run_id,
                "chart_name": chart_name,
                "snapshot_id": snapshot_id,
                "direction": _row_text(row, "Direction"),
                "cell_id": _row_text(row, "CellID"),
                "ue_index": _row_text(row, "UEIndex"),
                "sfn": _row_text(row, "SFN"),
                "slot": _row_text(row, "Slot"),
                "ofdm_symbol_index": _row_text(row, "OFDMSymbolIndex"),
                "subcarrier_index": float(subcarrier),
                "magnitude_db": float(magnitude_db),
                "phase_deg": float(phase_deg),
                "channel_estimate_source": _row_text(row, "ChannelEstimateSource"),
                "channel_estimate_method": _row_text(row, "ChannelEstimateMethod"),
                "source_table_logical_path": source_path,
            })
        if not csv_rows:
            return None
        return {
            "csv_bytes": _encode_dict_rows(
                [
                    "run_id", "chart_name", "snapshot_id", "direction", "cell_id",
                    "ue_index", "sfn", "slot", "ofdm_symbol_index", "subcarrier_index",
                    "magnitude_db", "phase_deg", "channel_estimate_source",
                    "channel_estimate_method", "source_table_logical_path",
                ], csv_rows,
            ),
            "img_bytes": _render_multi_series_svg(
                chart_name,
                "Receiver-estimated complex channel response from the executed PHY trial.",
                [
                    {"name": "Magnitude (dB)", "points": _downsample_points(magnitude_points, 512)},
                    {"name": "Unwrapped phase (deg)", "points": _downsample_points(phase_points, 512)},
                ],
                [
                    f"snapshot={snapshot_id}", f"points={len(csv_rows)}",
                    f"source={source_path}", "evidence=receiver_Hest",
                ],
                x_label="Zero-based subcarrier index", y_label="Magnitude (dB) / phase (deg)",
            ),
            "csv_status": "specialized_runtime_exact_hhat_frequency_dataset",
            "image_status": "generated_specialized_runtime_channel_response_svg",
            "source_table_path": source_path,
            "source_row_count": len(csv_rows),
            "source_mapping_status": "exact",
            "note": "Hhat(f) uses the receiver's persisted complex channel estimate; configured channel profile values are not substituted.",
        }

    grid_rows = [
        row for row in exact_rows
        if _row_text(row, "Panel") == "channel_estimate_grid"
        and _row_text(row, "Series") == "receiver_hest_exact_tensor"
    ]
    if not grid_rows:
        return None
    # Select one exact snapshot and one Rx/Tx port pair for the raster.  The
    # derived CSV retains every persisted port row for independent replotting.
    snapshot_counts: dict[str, int] = defaultdict(int)
    for row in grid_rows:
        snapshot_counts[_row_text(row, "SnapshotID")] += 1
    snapshot_id = max(snapshot_counts, key=snapshot_counts.get)
    selected = [row for row in grid_rows if _row_text(row, "SnapshotID") == snapshot_id]
    port_pairs = sorted({
        (_row_text(row, "RxPortIndex0Based"), _row_text(row, "TxPortIndex0Based"))
        for row in selected
    })
    raster_pair = port_pairs[0] if port_pairs else ("0", "0")
    raster_rows = [
        row for row in selected
        if (_row_text(row, "RxPortIndex0Based"), _row_text(row, "TxPortIndex0Based"))
        == raster_pair
    ]
    x_values = sorted({
        float(value) for row in raster_rows
        if (value := _row_float(row, "SubcarrierIndex")) is not None
    })
    y_values = sorted({
        float(value) for row in raster_rows
        if (value := _row_float(row, "OFDMSymbolIndex")) is not None
    })
    if not x_values or not y_values:
        return None
    x_index = {value: index for index, value in enumerate(x_values)}
    y_index = {value: index for index, value in enumerate(y_values)}
    value_field = "Phase_deg" if chart_name == "channel phase heatmap" else "Magnitude_dB"
    values_by_coordinate: dict[tuple[float, float], float] = {}
    for row in raster_rows:
        x_value = _row_float(row, "SubcarrierIndex")
        y_value = _row_float(row, "OFDMSymbolIndex")
        metric = _row_float(row, value_field)
        if x_value is None or y_value is None or metric is None:
            continue
        values_by_coordinate[(float(x_value), float(y_value))] = float(metric)
    if not values_by_coordinate:
        return None
    raw_values = list(values_by_coordinate.values())
    minimum = min(raw_values)
    # The generic renderer uses a zero-based sequential color scale.  Shift
    # only the raster color coordinate; the exported CSV keeps the exact dB or
    # phase value and records the color offset explicitly.
    color_offset = -minimum if minimum <= 0.0 else 0.0
    matrix = [[0.0 for _ in x_values] for _ in y_values]
    for (x_value, y_value), metric in values_by_coordinate.items():
        matrix[y_index[y_value]][x_index[x_value]] = metric + color_offset

    csv_rows = []
    for row in selected:
        magnitude_db = _row_float(row, "Magnitude_dB")
        phase_deg = _row_float(row, "Phase_deg")
        if magnitude_db is None or phase_deg is None:
            continue
        csv_rows.append({
            "run_id": run_id,
            "chart_name": chart_name,
            "snapshot_id": snapshot_id,
            "direction": _row_text(row, "Direction"),
            "cell_id": _row_text(row, "CellID"),
            "ue_index": _row_text(row, "UEIndex"),
            "sfn": _row_text(row, "SFN"),
            "slot": _row_text(row, "Slot"),
            "subcarrier_index": _row_text(row, "SubcarrierIndex"),
            "resource_block_index": _row_text(row, "ResourceBlockIndex"),
            "subcarrier_in_resource_block": _row_text(row, "SubcarrierInResourceBlock"),
            "ofdm_symbol_index": _row_text(row, "OFDMSymbolIndex"),
            "rx_port_index_0based": _row_text(row, "RxPortIndex0Based"),
            "tx_port_index_0based": _row_text(row, "TxPortIndex0Based"),
            "i_value": _row_text(row, "IValue"),
            "q_value": _row_text(row, "QValue"),
            "magnitude_db": float(magnitude_db),
            "phase_deg": float(phase_deg),
            "wrapped_phase_rad": _row_text(row, "WrappedPhase_rad"),
            "unwrapped_phase_frequency_rad": _row_text(row, "UnwrappedPhaseFrequency_rad"),
            "unwrapped_phase_time_rad": _row_text(row, "UnwrappedPhaseTime_rad"),
            "phase_delta_frequency_rad": _row_text(row, "PhaseDeltaFrequency_rad"),
            "phase_delta_time_rad": _row_text(row, "PhaseDeltaTime_rad"),
            "grid_sha256": _row_text(row, "GridSHA256"),
            "raster_color_offset": color_offset,
            "source_table_logical_path": source_path,
        })
    if not csv_rows:
        return None
    metric_label = "Receiver Hest phase (deg)" if value_field == "Phase_deg" else "Receiver Hest magnitude (dB)"
    return {
        "csv_bytes": _encode_dict_rows(
            [
                "run_id", "chart_name", "snapshot_id", "direction", "cell_id", "ue_index",
                "sfn", "slot", "subcarrier_index", "resource_block_index",
                "subcarrier_in_resource_block", "ofdm_symbol_index", "rx_port_index_0based",
                "tx_port_index_0based", "i_value", "q_value", "magnitude_db", "phase_deg",
                "wrapped_phase_rad", "unwrapped_phase_frequency_rad", "unwrapped_phase_time_rad",
                "phase_delta_frequency_rad", "phase_delta_time_rad", "grid_sha256",
                "raster_color_offset", "source_table_logical_path",
            ], csv_rows,
        ),
        "img_bytes": _render_heatmap_svg(
            chart_name,
            f"{metric_label} across subcarrier and OFDM symbol for one explicitly identified Rx/Tx port pair.",
            [str(int(value)) for value in x_values],
            [str(int(value)) for value in y_values],
            matrix,
            [
                f"snapshot={snapshot_id}",
                f"raster_rx_port={raster_pair[0]}", f"raster_tx_port={raster_pair[1]}",
                f"all_port_rows_in_csv={len(csv_rows)}", f"color_offset={color_offset:.6g}",
                f"source={source_path}", "evidence=receiver_Hest_exact_tensor",
            ],
            "Zero-based subcarrier index", "Zero-based OFDM symbol index",
        ),
        "csv_status": "specialized_runtime_exact_hest_grid_dataset",
        "image_status": "generated_specialized_runtime_hest_heatmap_svg",
        "source_table_path": source_path,
        "source_row_count": len(csv_rows),
        "source_mapping_status": "exact",
        "note": "The raster uses one declared Rx/Tx port pair; the CSV retains the full persisted complex Hest tensor across ports, symbols, and subcarriers.",
    }


def _runtime_evm_profile_chart(chart_name, existing, fetch_artifact_bytes, run_id):
    required_direction = "DL" if chart_name.startswith("PDSCH ") else "UL" if chart_name.startswith("PUSCH ") else ""
    profile_name = chart_name.removeprefix("PDSCH ").removeprefix("PUSCH ")
    axis_field = {
        "EVM per symbol": "OFDMSymbolIndex",
        "EVM per subcarrier": "SubcarrierIndex",
        "EVM per layer": "LayerIndex",
    }[profile_name]
    sources = _all_available_rows(existing, fetch_artifact_bytes, [
        "air_interface/csv/dl_constellation_samples.csv",
        "air_interface/csv/ul_constellation_samples.csv",
        "air_interface/csv/dl_constellation_preview.csv",
        "air_interface/csv/ul_constellation_preview.csv",
        "reports/csv/equalized_constellations.csv",
    ])
    # Canonical captures and report aliases can contain the same samples.
    # Choose one source per direction, without counting aliases twice.
    selected_source = {}
    buckets = {}
    observations = {}
    for source_path, rows in sources:
        default_direction = "DL" if "/dl_" in source_path else "UL" if "/ul_" in source_path else ""
        for row in rows:
            direction = _row_text(row, "Direction", "RuntimeDirection").upper() or default_direction
            if direction not in {"DL", "UL"}:
                continue
            if required_direction and direction != required_direction:
                continue
            selected_source.setdefault(direction, source_path)
            if selected_source[direction] != source_path:
                continue
            # Older producers stored payload-gain-fitted values in Equalized*,
            # but preserved the real receiver output in RawEqualized*. Never
            # mistake that fitted constellation for a receiver measurement.
            if "RawEqualizedReal" in row or "RawEqualizedImag" in row:
                measured_fields = ("RawEqualizedReal", "RawEqualizedImag")
                sample_source = "raw_receiver_equalized_before_reporter_payload_fit"
            elif _row_text(row, "EqualizationSource") == "receiver_output_without_payload_gain_or_phase_fit":
                measured_fields = ("EqualizedReal", "EqualizedImag")
                sample_source = "explicit_receiver_output_without_payload_fit"
            else:
                return None
            values = [_row_float(row, name) for name in (
                axis_field, *measured_fields, "ReferenceSymbolReal", "ReferenceSymbolImag"
            )]
            if any(value is None for value in values):
                return None  # Scalar EVM is not enough to recover energy sums or peaks.
            x_value, eq_r, eq_i, ref_r, ref_i = values
            if x_value != int(x_value):
                return None
            slot = _row_text(row, "RuntimeSlot", "Slot")
            ue = _row_text(row, "UEIndex", "UEID", "ue_id")
            frame = _row_text(row, "Frame")
            sfn = _row_text(row, "SFN")
            cell = _row_text(row, "CellID", "ServingCell", "BaseStationID")
            layer = _row_text(row, "LayerIndex")
            codeword = _row_text(row, "CodewordIndex")
            tb = _row_text(row, "TBId", "tb_id")
            normalization = _row_text(row, "RuntimeNormalization", "normalization")
            truth = _row_text(row, "TruthStatus", "truth_status").lower()
            comparison_domain = _row_text(row, "SymbolComparisonDomain")
            ordering = _row_text(row, "SymbolOrdering")
            ordering_status = _row_text(row, "SymbolOrderingStatus")
            coordinate_domain = _row_text(row, "SymbolCoordinateDomain")
            if axis_field == "SubcarrierIndex" and coordinate_domain == "pre_transform_qam_positions":
                return None  # Inverse-DFT QAM positions are not per-subcarrier measurements.
            if not slot or not ue or not (frame or sfn) or not layer or codeword == "":
                return None
            if any(token in truth for token in ("proxy", "fallback", "synthetic", "unavailable")):
                return None
            if any(token in ordering_status.lower() for token in ("unmatched", "mismatch", "unavailable", "invalid")):
                return None
            scope = _row_text(row, "CaptureScope")
            full = scope == "full_allocation_paired_symbols"
            observation_key = (direction, ue, frame, sfn, slot, cell, tb)
            observation = observations.setdefault(observation_key, {"full": full, "expected": None, "indices": set(), "resources": set()})
            if observation["full"] != full:
                return None  # Mixed full/preview rows cannot establish coverage.
            if full:
                count = _row_float(row, "ObservationSymbolCount")
                captured = _row_float(row, "CapturedSymbolCount")
                index = _row_float(row, "SampleIndex")
                resource = tuple(_row_float(row, f) for f in ("LayerIndex", "OFDMSymbolIndex", "SubcarrierIndex"))
                if count is None or count < 1 or count != int(count) or captured != count:
                    return None
                if index is None or index != int(index) or not 1 <= index <= count:
                    return None
                if any(v is None or v < 1 or v != int(v) for v in resource):
                    return None
                if observation["expected"] not in (None, count) or index in observation["indices"] or resource in observation["resources"]:
                    return None
                observation["expected"] = count
                observation["indices"].add(index)
                observation["resources"].add(resource)
            key = (direction, ue, frame, sfn, slot, cell, tb,
                   layer if axis_field != "LayerIndex" else "", codeword, normalization,
                   comparison_domain, ordering, ordering_status, sample_source, coordinate_domain, int(x_value))
            bucket = buckets.setdefault(key, {
                "run_id": run_id, "chart_name": chart_name, "direction": direction,
                "ue_index": ue, "frame": frame, "sfn": sfn, "slot": slot,
                "cell_id": cell, "tb_id": tb, "layer_index": layer,
                "codeword_index": codeword, axis_field: int(x_value),
                "sample_count": 0, "error_energy": 0.0, "reference_energy": 0.0,
                "peak_error_power": 0.0, "input_normalization": normalization,
                "comparison_domain": comparison_domain, "symbol_ordering": ordering,
                "symbol_ordering_status": ordering_status,
                "measured_sample_source": sample_source,
                "symbol_coordinate_domain": coordinate_domain,
                "measurement_scope": "full_allocation_paired_symbols" if full else "persisted_paired_sample_subset",
                "evm_normalization": "average_reference_signal_power_in_bucket",
                "source_table_logical_path": source_path,
            })
            error_power = (eq_r - ref_r) ** 2 + (eq_i - ref_i) ** 2
            bucket["sample_count"] += 1
            bucket["error_energy"] += error_power
            bucket["reference_energy"] += ref_r ** 2 + ref_i ** 2
            bucket["peak_error_power"] = max(bucket["peak_error_power"], error_power)
    if any(obs["full"] and len(obs["indices"]) != obs["expected"] for obs in observations.values()):
        return None  # Missing rows invalidate full coverage; do not relabel as a subset.
    if not buckets:
        return None
    csv_rows = list(buckets.values())
    plot_points = defaultdict(list)
    for row in csv_rows:
        if row["reference_energy"] <= 0:
            return None
        row["rms_evm_pct"] = 100 * math.sqrt(row["error_energy"] / row["reference_energy"])
        row["peak_evm_pct"] = 100 * math.sqrt(
            row["peak_error_power"] / (row["reference_energy"] / row["sample_count"])
        )
        # Keep slots separate; a symbol index repeats in every slot. No
        # hardcoded 14-symbol numerology or fabricated absolute time axis.
        label = (f"{row['direction']} U{row['ue_index']} S{row['slot']} "
                 f"F{row['frame'] or row['sfn']} CW{row['codeword_index']}")
        if axis_field != "LayerIndex":
            label += f" L{row['layer_index']}"
        if row["cell_id"]:
            label += f" C{row['cell_id']}"
        if row["tb_id"]:
            label += f" TB{row['tb_id']}"
        for metric, name in (("rms_evm_pct", "RMS"), ("peak_evm_pct", "Peak")):
            plot_points[f"{name} {label}"].append([row[axis_field], row[metric]])
    series = [{"name": name, "points": sorted(points), "marker": "circle" if name.startswith("RMS") else "square"}
              for name, points in plot_points.items()]
    all_full = all(obs["full"] for obs in observations.values())
    coverage = "Full paired-allocation coverage verified by sample/resource identities and transmitter counts." if all_full else "Contains persisted sample subsets; not full-allocation coverage."
    note = ("RMS and Peak EVM from actual receiver symbols without reporter payload gain/phase fitting; average reference-power normalization "
            "within each UE/frame/slot/TB/codeword/layer bucket. " + coverage + " Not RF conformance EVM.")
    summary = [f"paired_samples={sum(row['sample_count'] for row in csv_rows)}",
               "normalization=average reference power", "scope=full paired allocation" if all_full else "scope=contains sample subsets"]
    image_bytes = _render_multi_series_svg(chart_name, note, series, summary,
        x_label={"OFDMSymbolIndex": "OFDM symbol index (within slot)",
                 "SubcarrierIndex": "Subcarrier index", "LayerIndex": "Layer index"}[axis_field],
        y_label="EVM (%)", mode="scatter",
        evidence_shape_policy="operating_point")
    return {
        "csv_bytes": _encode_dict_rows(list(csv_rows[0]), csv_rows),
        "img_bytes": image_bytes,
        "csv_status": "specialized_runtime_evm_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": "|".join(sorted(set(row["source_table_logical_path"] for row in csv_rows))),
        "source_row_count": sum(row["sample_count"] for row in csv_rows),
        "note": note,
    }


def _runtime_throughput_sinr_chart(existing, fetch_artifact_bytes, run_id):
    """Preserve individual scheduled-TB/goodput observations, including failures.

    Throughput_Mbps is the runtime scheduled TB bitrate, not delivered traffic.
    Never pool equal-SINR trials across directions, ranks, MCSs or HARQ states.
    """
    chart_name = "throughput vs SINR"
    sources = _all_available_rows(existing, fetch_artifact_bytes, [
        "air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv",
    ])
    csv_rows = []
    plot_points = defaultdict(list)
    for source_path, rows in sources:
        source_direction = "DL" if "dl_pdsch" in source_path else "UL"
        for row_index, row in enumerate(rows, 1):
            direction = _row_text(row, "RuntimeDirection", "Direction").upper() or source_direction
            truth = _row_text(row, "TruthStatus", "truth_status").lower()
            reason = ""
            if direction != source_direction:
                reason = "direction_conflicts_with_canonical_trial_source"
            elif any(token in truth for token in ("proxy", "fallback", "synthetic", "unavailable")):
                reason = "non_runtime_evidence"
            if reason:
                # Reject the chart at its source boundary. Non-runtime values
                # must not become numeric rows in a primary measured dataset.
                return {
                    "csv_bytes": _encode_csv(["run_id", "chart_name", "status", "reason", "source_table_logical_path", "source_row_index"],
                        [[run_id, chart_name, "unavailable_exact_reason", reason, source_path, row_index]]),
                    "img_bytes": _render_reason_svg(chart_name, "Runtime source integrity check failed.",
                        [reason, source_path, f"source_row_index={row_index}"]),
                    "csv_status": "unavailable_exact_reason", "image_status": "generated_unavailable_reason_svg",
                    "source_table_path": source_path, "source_row_count": 0, "note": reason,
                }
            sinr, sinr_field = None, ""
            # No configured SNR, geometry-only SINR, or inferred EVM-to-SINR.
            for field in ("PostEqSINR_dB", "MeasuredTrialSINR_dB", "MeasuredSINR_dB", "MeasuredWidebandSINR_dB"):
                candidate = _row_float(row, field)
                if candidate is not None:
                    sinr, sinr_field = candidate, field
                    break
            throughput = _row_float(row, "Throughput_Mbps")
            goodput = _row_float(row, "Goodput_Mbps")
            source_fields = {
                "PostEqSINR_dB": ("PostEqSINRSource", "PostEqSINRValueStatus"),
                "MeasuredTrialSINR_dB": ("MeasuredTrialSINRSource", "MeasuredTrialSINRValueStatus"),
                "MeasuredSINR_dB": ("SINRSource", "SINRValueStatus"),
                "MeasuredWidebandSINR_dB": ("MeasuredWidebandSINRSource", "MeasuredWidebandSINRValueStatus"),
            }
            sinr_source, sinr_status = ([_row_text(row, name) for name in source_fields[sinr_field]]
                                        if sinr_field else ["", ""])
            if sinr is None:
                reason = reason or "measured_sinr_unavailable"
            elif throughput is None and goodput is None:
                reason = reason or "runtime_bitrates_unavailable"
            elif any(value is not None and value < 0 for value in (throughput, goodput)):
                reason = reason or "negative_runtime_bitrate"
            if any(token in (sinr_source + " " + sinr_status).lower()
                   for token in ("proxy", "synthetic", "fallback", "unavailable", "not_available")):
                reason = reason or "sinr_source_not_measured_evidence"
                sinr = None  # Do not carry a proxy value into the measured SINR column.
            output = {
                "run_id": run_id, "chart_name": chart_name, "direction": direction,
                "ue_index": _row_text(row, "UEIndex", "UEID", "ue_id"),
                "frame": _row_text(row, "Frame"), "sfn": _row_text(row, "SFN"),
                "slot": _row_text(row, "RuntimeSlot", "Slot"),
                "cell_id": _row_text(row, "CellID", "ServingCell", "BaseStationID"),
                "tb_id": _row_text(row, "TBId", "tb_id"),
                "grant_id": _row_text(row, "GrantID"),
                "mcs": _row_text(row, "MCS", "MCSIndex"),
                "layers": _row_text(row, "Layers", "NumLayers"),
                "crc_pass": _row_text(row, "CRCPass"),
                "sinr_db": sinr, "sinr_source_field": sinr_field,
                "sinr_measurement_source": sinr_source, "sinr_value_status": sinr_status,
                "sinr_measurement_domain": _row_text(row, "SINRMeasurementDomain"),
                "throughput_mbps": throughput, "goodput_mbps": goodput,
                "throughput_value_status": "available" if throughput is not None else "unavailable_in_source",
                "goodput_value_status": "available" if goodput is not None else "unavailable_in_source",
                "rate_semantics": "scheduled_TB_bitrate_and_runtime_goodput",
                "measurement_scope": "individual_runtime_trial_not_sweep_curve",
                "value_status": reason or "available",
                "source_truth_status": truth,
                "source_table_logical_path": source_path, "source_row_index": row_index,
            }
            csv_rows.append(output)
            if reason:
                continue
            for metric, name in ((throughput, "TB bitrate"), (goodput, "Goodput")):
                if metric is not None:
                    domain = {"PostEqSINR_dB": "post-EQ", "MeasuredTrialSINR_dB": "trial",
                              "MeasuredSINR_dB": "measured", "MeasuredWidebandSINR_dB": "wideband"}[sinr_field]
                    plot_points[f"{direction} {name} [{domain}]"].append([sinr, metric])
    note = ("Individual DL/UL trial observations: scheduled TB bitrate and delivered goodput. "
            "No fitted curve, no DL/UL averaging; SINR field, MCS, layers and CRC retained in CSV.")
    summary = [f"runtime_trials={len(csv_rows)}",
               f"unplotted_trials={sum(row['value_status'] != 'available' for row in csv_rows)}",
               "TB bitrate is not delivered goodput", "No interpolation or sweep claim"]
    series = [{"name": name, "points": points, "marker": "square" if "Goodput" in name else "circle"}
              for name, points in plot_points.items()]
    if not series:
        return {
            "csv_bytes": _encode_dict_rows(list(csv_rows[0]), csv_rows) if csv_rows else
                _encode_csv(["run_id", "chart_name", "status", "reason"], [[run_id, chart_name,
                    "unavailable_exact_reason", "No runtime trial with a measured SINR and bitrate was exported."]]),
            "img_bytes": _render_reason_svg(chart_name, "Measured trial evidence unavailable.", summary),
            "csv_status": "unavailable_exact_reason", "image_status": "generated_unavailable_reason_svg",
            "source_table_path": "|".join(path for path, _ in sources),
            "source_row_count": len(csv_rows), "note": note,
        }
    return {
        "csv_bytes": _encode_dict_rows(list(csv_rows[0]), csv_rows),
        "img_bytes": _render_multi_series_svg(chart_name, note, series, summary,
            x_label="Measured SINR (dB); source domain in legend/CSV", y_label="Bitrate / goodput (Mbit/s)",
            mode="scatter", evidence_shape_policy="operating_point"),
        "csv_status": "specialized_runtime_throughput_dataset",
        "image_status": "generated_specialized_runtime_summary_svg",
        "source_table_path": "|".join(path for path, _ in sources),
        "source_row_count": len(csv_rows), "note": note,
    }


def _specialized_chart_materialization(
    chart_name: str,
    existing: dict[str, dict[str, Any]],
    fetch_artifact_bytes: Callable[[int], bytes],
    run_id: int,
) -> dict[str, Any] | None:
    chart_name = str(chart_name or "")
    from lls_radio_measurement_plots import radio_measurement_chart
    radio_chart = radio_measurement_chart(chart_name, existing, fetch_artifact_bytes, run_id)
    if radio_chart is not None:
        return radio_chart
    if chart_name == "throughput vs SINR":
        return _runtime_throughput_sinr_chart(existing, fetch_artifact_bytes, run_id)
    phy_signal_chart = _runtime_phy_signal_diagnostic_chart(
        chart_name, existing, fetch_artifact_bytes, run_id
    )
    if phy_signal_chart is not None:
        return phy_signal_chart
    geometry_chart = _runtime_geometry_chart(
        chart_name, existing, fetch_artifact_bytes, run_id
    )
    if geometry_chart is not None:
        return geometry_chart
    profile_chart = _runtime_profile_chart(
        chart_name, existing, fetch_artifact_bytes, run_id
    )
    if profile_chart is not None:
        return profile_chart
    energy_chart = _runtime_energy_summary_chart(
        chart_name, existing, fetch_artifact_bytes, run_id
    )
    if energy_chart is not None:
        return energy_chart
    if chart_name == "per-channel reliability breakdown":
        channel_sources = [
            ("PDSCH", "air_interface/csv/dl_pdsch_trials.csv"),
            ("PUSCH", "air_interface/csv/ul_pusch_trials.csv"),
            ("PDCCH", "air_interface/csv/pdcch_trials.csv"),
            ("PUCCH", "air_interface/csv/pucch_trials.csv"),
            ("PBCH", "air_interface/csv/pbch_trials.csv"),
            ("PRACH", "air_interface/csv/prach_trials.csv"),
            ("SRS", "air_interface/csv/srs_trials.csv"),
        ]
        rows_out: list[dict[str, Any]] = []
        points: list[list[float]] = []
        summary: list[str] = []
        source_paths: list[str] = []
        for label, logical_path in channel_sources:
            _header, source_rows = _artifact_rows_by_path(
                existing, fetch_artifact_bytes, logical_path
            )
            if not source_rows:
                continue
            outcomes: list[bool] = []
            for row in source_rows:
                outcome = _row_flag(
                    row,
                    "CRCPass", "CombinedDecodeOK", "CurrentDecodeOK",
                    "DecodeSuccess", "PUCCHDecodeOk", "DetectedFlag",
                    "Detected", "SuccessFlag", "ControlDecodeOk",
                )
                if outcome is None:
                    status = _row_text(row, "Status").strip().lower()
                    if status in {"pass", "passed", "success", "detected", "ack"}:
                        outcome = True
                    elif status in {"fail", "failed", "error", "missed", "nack"}:
                        outcome = False
                if outcome is not None:
                    outcomes.append(bool(outcome))
            if not outcomes:
                continue
            passed = sum(1 for value in outcomes if value)
            trials = len(outcomes)
            rate = passed / trials
            ci_low, ci_high = _wilson_score_interval(passed, trials)
            bucket = len(points) + 1
            points.append([float(bucket), float(rate)])
            rows_out.append({
                "run_id": run_id,
                "chart_name": chart_name,
                "channel": label,
                "pass_count": passed,
                "fail_count": trials - passed,
                "trial_count": trials,
                "pass_rate": rate,
                "ci95_lower": ci_low,
                "ci95_upper": ci_high,
                "source_table_logical_path": logical_path,
            })
            summary.append(f"bucket_{bucket}={label}")
            source_paths.append(logical_path)
        if rows_out:
            dataset = {
                "mode": "bar",
                "x_label": "Physical channel bucket",
                "y_label": "Observed pass rate",
                "points": points,
                "y_axis_min": 0.0,
                "y_axis_max": 1.0,
                "evidence_shape_policy": "observed_distribution",
                "sample_count": sum(int(row["trial_count"]) for row in rows_out),
            }
            return {
                "csv_bytes": _encode_dict_rows(
                    ["run_id", "chart_name", "channel", "pass_count", "fail_count", "trial_count", "pass_rate", "ci95_lower", "ci95_upper", "source_table_logical_path"],
                    rows_out,
                ),
                "img_bytes": _render_svg_plot(
                    chart_name,
                    "Observed decode/detection reliability by executed physical channel with Wilson 95% intervals in the CSV.",
                    dataset,
                    summary + [f"runtime_trials={dataset['sample_count']}"]
                ),
                "csv_status": "specialized_runtime_channel_reliability_dataset",
                "image_status": "generated_specialized_runtime_summary_svg",
                "source_table_path": "|".join(source_paths),
                "source_row_count": int(dataset["sample_count"]),
                "source_mapping_status": "exact",
                "note": "Per-channel reliability uses only persisted physical-channel outcome rows; absent channel families are omitted rather than synthesized.",
            }
    sensing = _runtime_sensing_probability_chart(
        chart_name, existing, fetch_artifact_bytes, run_id
    )
    if sensing is not None:
        return sensing
    for runtime_chart_builder in (
        _runtime_reference_signal_occupancy_chart,
        _runtime_papr_distribution_chart,
        _runtime_prach_operational_chart,
        _runtime_dl_tx_power_per_entity_chart,
    ):
        runtime_chart = runtime_chart_builder(
            chart_name, existing, fetch_artifact_bytes, run_id
        )
        if runtime_chart is not None:
            return runtime_chart
    cfo_tracking = _runtime_cfo_tracking_chart(
        chart_name, existing, fetch_artifact_bytes, run_id
    )
    if cfo_tracking is not None:
        return cfo_tracking
    configured_sweep = _configured_sweep_chart_materialization(
        chart_name, existing, fetch_artifact_bytes, run_id
    )
    if configured_sweep is not None:
        return configured_sweep
    explicit_metric = _explicit_runtime_metric_chart_materialization(
        chart_name, existing, fetch_artifact_bytes, run_id
    )
    if explicit_metric is not None:
        return explicit_metric
    resource_occupancy = _runtime_resource_occupancy_chart(
        chart_name, existing, fetch_artifact_bytes, run_id
    )
    if resource_occupancy is not None:
        return resource_occupancy
    spectral = _runtime_spectral_chart(chart_name, existing, fetch_artifact_bytes, run_id)
    if spectral is not None:
        return spectral
    contract_gap = _runtime_contract_gap_chart(
        chart_name, existing, fetch_artifact_bytes, run_id
    )
    if contract_gap is not None:
        return contract_gap
    energy_relation = _runtime_energy_relation_chart(
        chart_name, existing, fetch_artifact_bytes, run_id
    )
    if energy_relation is not None:
        return energy_relation
    if chart_name == "antenna element layout":
        return _runtime_antenna_layout_chart(chart_name, existing, fetch_artifact_bytes, run_id)
    if chart_name == "antenna radiation pattern":
        return _runtime_antenna_radiation_chart(chart_name, existing, fetch_artifact_bytes, run_id)
    if chart_name == "beam pattern 3d":
        return _runtime_beam_pattern_chart(chart_name, existing, fetch_artifact_bytes, run_id)
    if chart_name in {"channel impulse response", "true H(tau) if available", "estimated Hhat(tau)", "tap power profile"}:
        return _runtime_channel_impulse_response_chart(chart_name, existing, fetch_artifact_bytes, run_id)
    if chart_name == "delay spread chart":
        return _runtime_delay_spread_chart(chart_name, existing, fetch_artifact_bytes, run_id)
    prach_rate_chart = _prach_rate_chart_materialization(chart_name, existing, fetch_artifact_bytes, run_id)
    if prach_rate_chart is not None:
        return prach_rate_chart
    prach_peak_chart = _prach_peak_chart_materialization(chart_name, existing, fetch_artifact_bytes, run_id)
    if prach_peak_chart is not None:
        return prach_peak_chart
    pucch_dtx_chart = _pucch_dtx_chart_materialization(chart_name, existing, fetch_artifact_bytes, run_id)
    if pucch_dtx_chart is not None:
        return pucch_dtx_chart
    beam_mimo_chart = _beam_mimo_chart_materialization(chart_name, existing, fetch_artifact_bytes, run_id)
    if beam_mimo_chart is not None:
        return beam_mimo_chart
    pdcch_control_chart = _pdcch_control_chart_materialization(chart_name, existing, fetch_artifact_bytes, run_id)
    if pdcch_control_chart is not None:
        return pdcch_control_chart
    pdcch_probability_chart = _pdcch_detection_probability_chart_materialization(
        chart_name, existing, fetch_artifact_bytes, run_id
    )
    if pdcch_probability_chart is not None:
        return pdcch_probability_chart
    ssb_index_chart = _ssb_index_timeline_chart_materialization(chart_name, existing, fetch_artifact_bytes, run_id)
    if ssb_index_chart is not None:
        return ssb_index_chart
    if chart_name in {"CSI-RS map", "CSI-RS resource occupancy"}:
        csirs_chart = _csirs_map_chart_materialization(chart_name, existing, fetch_artifact_bytes, run_id)
        if csirs_chart is not None:
            return csirs_chart
    if chart_name == "SRS map":
        srs_chart = _srs_map_chart_materialization(chart_name, existing, fetch_artifact_bytes, run_id)
        if srs_chart is not None:
            return srs_chart
    scheduler_chart_names = {
        "scheduled PRBs per UE over time",
        "MCS over time",
        "CQI vs selected MCS",
        "queue depth over time",
        "SR/BSR event timeline",
        "power control command timeline",
        "PHR distribution",
        "grant reason distribution",
    }
    harq_chart_names = {
        "HARQ process timeline",
        "RV usage distribution",
        "retransmission count histogram",
        "ACK/NACK timeline",
        "residual BLER by HARQ process",
        "combining gain histogram",
        "HARQ combining gain distribution",
        "retransmission rate trend",
        "HARQ RTT distribution",
        "newTx vs retx comparison",
        "residual failure patterns",
        "residual BLER after HARQ",
        "goodput vs retransmissions",
        "combiner summary",
    }
    if chart_name in scheduler_chart_names:
        scheduler_sources = {
            "scheduled PRBs per UE over time": [
                "packet_flow/csv/live_dl_scheduler_grants.csv",
                "packet_flow/csv/live_ul_scheduler_grants.csv",
                "reports/csv/live_scheduler_cycle.csv",
            ],
            "queue depth over time": [
                "reports/csv/live_queue_state.csv",
                "packet_flow/csv/live_dl_scheduler_grants.csv",
                "packet_flow/csv/live_ul_scheduler_grants.csv",
            ],
            "SR/BSR event timeline": [
                "reports/csv/live_bsr_state.csv",
                "reports/csv/live_sr_state.csv",
                "reports/csv/live_scheduler_cycle.csv",
            ],
            "power control command timeline": [
                "reports/csv/live_power_control_state.csv",
                "packet_flow/csv/live_ul_scheduler_grants.csv",
                "reports/csv/live_scheduler_cycle.csv",
            ],
            "PHR distribution": [
                "reports/csv/live_phr_state.csv",
                "packet_flow/csv/live_ul_scheduler_grants.csv",
                "reports/csv/live_scheduler_cycle.csv",
            ],
        }.get(
            chart_name,
            [
                "reports/csv/live_scheduler_cycle.csv",
                "packet_flow/csv/live_dl_scheduler_grants.csv",
                "packet_flow/csv/live_ul_scheduler_grants.csv",
            ],
        )
        source_path, records = _first_available_rows(
            existing,
            fetch_artifact_bytes,
            scheduler_sources,
        )
        if records:
            dataset = None
            note = "Scheduler chart derived from persisted scheduler-cycle or grant runtime rows."
            if chart_name == "scheduled PRBs per UE over time":
                grouped: dict[int, list[float]] = defaultdict(list)
                for row in records:
                    slot = _row_float(row, "Slot", "ScheduledAbsoluteSlot")
                    prb_count = _row_float(row, "AllocatedPRBCount", "PRBCount", "prb_count")
                    if slot is None or prb_count is None:
                        continue
                    grouped[int(round(slot))].append(float(prb_count))
                points = [[float(slot), sum(vals) / len(vals)] for slot, vals in sorted(grouped.items())]
                dataset = {"mode": _honest_chart_mode(points), "x_label": "Slot", "y_label": "Mean scheduled PRBs per grant", "points": points}
            elif chart_name == "MCS over time":
                points = [[idx + 1, float(_row_float(row, "MCSIndex") or 0.0)] for idx, row in enumerate(records[:MAX_PREVIEW_ROWS]) if _row_float(row, "MCSIndex") is not None]
                dataset = {"mode": _honest_chart_mode(points), "x_label": "Grant sample", "y_label": "MCSIndex", "points": points}
            elif chart_name == "CQI vs selected MCS":
                grouped: dict[int, list[float]] = defaultdict(list)
                paired_observation_count = 0
                for row in records:
                    cqi = _row_float(row, "CQIUsed", "WidebandCQI")
                    mcs = _row_float(row, "MCSIndex")
                    if cqi is None or mcs is None:
                        continue
                    paired_observation_count += 1
                    grouped[int(round(cqi))].append(float(mcs))
                points = [[float(cqi), sum(vals) / len(vals)] for cqi, vals in sorted(grouped.items())]
                dataset = {
                    "mode": _honest_chart_mode(points),
                    "x_label": "CQI",
                    "y_label": "Mean selected MCS",
                    "points": points,
                    "evidence_shape_policy": (
                        "observed_relation" if len(points) >= 2 else "operating_point"
                    ),
                    "sample_count": paired_observation_count,
                }
                if len(points) == 1:
                    note += " One measured CQI/MCS operating point is shown as a scalar observation; no relation or sweep is inferred."
            elif chart_name == "queue depth over time":
                grouped: dict[int, list[float]] = defaultdict(list)
                for row in records:
                    slot = _row_float(row, "Slot")
                    q_bytes = _row_float(row, "QueueBytesBefore", "QueueBytesAfter")
                    if slot is None or q_bytes is None:
                        continue
                    grouped[int(round(slot))].append(float(q_bytes))
                points = [[float(slot), sum(vals) / len(vals)] for slot, vals in sorted(grouped.items())]
                dataset = {"mode": _honest_chart_mode(points), "x_label": "Slot", "y_label": "Queue bytes", "points": points}
            elif chart_name == "SR/BSR event timeline":
                grouped: Counter[int] = Counter()
                for row in records:
                    slot = _row_float(row, "Slot")
                    if slot is None:
                        continue
                    if _row_text(row, "sr_state") or (_row_float(row, "bsr_amount") or 0.0) > 0.0:
                        grouped[int(round(slot))] += 1
                points = [[float(slot), float(count)] for slot, count in sorted(grouped.items())]
                dataset = {"mode": _honest_chart_mode(points), "x_label": "Slot", "y_label": "SR/BSR events", "points": points}
            elif chart_name == "power control command timeline":
                grouped: Counter[int] = Counter()
                for row in records:
                    slot = _row_float(row, "Slot")
                    if slot is None:
                        continue
                    if _row_text(row, "power_control_command"):
                        grouped[int(round(slot))] += 1
                points = [[float(slot), float(count)] for slot, count in sorted(grouped.items())]
                dataset = {"mode": _honest_chart_mode(points), "x_label": "Slot", "y_label": "Power-control commands", "points": points}
            elif chart_name == "PHR distribution":
                values = []
                for row in records:
                    metric_token = _row_text(row, "MetricKey", "MetricName").strip().lower()
                    if metric_token and "phr" not in metric_token and "headroom" not in metric_token:
                        continue
                    value = _row_float(row, "phr_db", "ValueNumeric")
                    if value is not None:
                        values.append(float(value))
                if values:
                    bins = min(12, max(3, len(values)))
                    lo = min(values)
                    hi = max(values)
                    width = ((hi - lo) / bins) if not math.isclose(lo, hi) else 1.0
                    points = []
                    for bin_idx in range(bins):
                        center = lo + width * (bin_idx + 0.5)
                        count = sum(1 for value in values if (bin_idx == bins - 1 and value <= hi) or (lo + width * bin_idx <= value < lo + width * (bin_idx + 1)))
                        points.append([center, float(count)])
                    dataset = {"mode": "bar", "x_label": "PHR dB", "y_label": "Count", "points": points}
            elif chart_name == "grant reason distribution":
                counts = Counter(_row_text(row, "GrantReason") for row in records if _row_text(row, "GrantReason"))
                ordered = counts.most_common(16)
                points = [[float(idx + 1), float(count)] for idx, (_label, count) in enumerate(ordered)]
                note += " x-axis buckets correspond to the listed grant-reason order in the SVG summary."
                dataset = {"mode": "bar", "x_label": "Grant-reason bucket", "y_label": "Count", "points": points}
            if dataset and dataset.get("points"):
                dataset.setdefault("sample_count", len(records))
                if chart_name in {"PHR distribution", "grant reason distribution"}:
                    dataset["evidence_shape_policy"] = "observed_distribution"
                elif chart_name != "CQI vs selected MCS":
                    dataset["evidence_shape_policy"] = "observed_timeline"
                summary = [f"source_table={source_path}", f"source_rows={len(records)}", f"chart={chart_name}"]
                if chart_name == "grant reason distribution":
                    counts = Counter(_row_text(row, "GrantReason") for row in records if _row_text(row, "GrantReason"))
                    summary.extend([f"bucket_{idx+1}={label}" for idx, (label, _count) in enumerate(counts.most_common(8))])
                csv_bytes = _chart_dataset_csv(run_id, chart_name, dataset, source_path, len(records), "derived_chart_dataset", note)
                img_bytes = _render_svg_plot(chart_name, "Runtime scheduler evidence rendered from persisted truthful rows.", dataset, summary)
                return {
                    "csv_bytes": csv_bytes,
                    "img_bytes": img_bytes,
                    "csv_status": "derived_chart_dataset",
                    "image_status": "generated_specialized_runtime_summary_svg",
                    "source_table_path": source_path,
                    "source_row_count": len(records),
                    "note": note,
                }
    if chart_name in harq_chart_names:
        harq_sources = [
            "harq/csv/live_harq_observation_timeline.csv",
            "reports/csv/live_harq_process_table.csv",
            "harq/csv/live_harq_observation_summary.csv",
        ]
        if chart_name == "HARQ RTT distribution":
            # RTT belongs to the canonical per-attempt HARQ timeline. The
            # generic live observation table intentionally contains decoder
            # outcomes only and cannot be used to manufacture feedback timing.
            harq_sources = [
                "harq/csv/harq_process_timeline.csv",
                "harq/csv/probe_harq_packets.csv",
                *harq_sources,
            ]
        source_path, records = _first_available_rows(
            existing,
            fetch_artifact_bytes,
            harq_sources,
        )
        if records:
            dataset = None
            img_bytes_override: bytes | None = None
            note = "HARQ chart derived from persisted runtime HARQ observation rows."
            if chart_name == "HARQ process timeline":
                points = []
                for index, row in enumerate(records, start=1):
                    slot = _row_float(row, "Slot", "last_tx_time", "LastTxTime")
                    process_id = _row_float(row, "HarqID", "HARQProcess", "harq_id")
                    if process_id is None:
                        continue
                    points.append([float(slot) if slot is not None else float(index), float(process_id)])
                dataset = {"mode": "scatter", "x_label": "Slot / transmission index", "y_label": "HARQ process", "points": points}
            elif chart_name == "RV usage distribution":
                counts = Counter(
                    int(round(float(rv_value)))
                    for row in records
                    for rv_value in [_row_float(row, "RV")]
                    if rv_value is not None
                )
                points = [[float(rv), float(count)] for rv, count in sorted((rv, count) for rv, count in counts.items() if rv >= 0)]
                dataset = {"mode": "bar", "x_label": "RV", "y_label": "Count", "points": points}
            elif chart_name == "retransmission count histogram":
                tx_count_values = [int(round(value)) for value in (_row_float(row, "TxCount", "tx_count") for row in records) if value is not None and math.isfinite(float(value))]
                if tx_count_values:
                    counts = Counter(max(value - 1, 0) for value in tx_count_values)
                else:
                    per_process: dict[str, int] = defaultdict(int)
                    for idx, row in enumerate(records):
                        key = f"{_row_text(row, 'UEIndex', 'UEID', 'RNTI') or idx}|{_row_text(row, 'HarqID', 'HARQProcess') or idx}"
                        is_retx = _row_text(row, "IsRetransmission", "new_tx_or_retx").lower() in {"1", "true", "retx", "retransmission"}
                        per_process.setdefault(key, 0)
                        if is_retx:
                            per_process[key] += 1
                    counts = Counter(per_process.values())
                points = [[float(count_value), float(bucket_count)] for count_value, bucket_count in sorted(counts.items())]
                dataset = {"mode": "bar", "x_label": "Retransmissions per HARQ context", "y_label": "Count", "points": points}
            elif chart_name == "retransmission rate trend":
                grouped: dict[int, list[float]] = defaultdict(list)
                for idx, row in enumerate(records):
                    slot = _row_float(row, "Slot", "last_tx_time", "LastTxTime")
                    if slot is None:
                        slot = float(idx + 1)
                    tx_count = _row_float(row, "TxCount", "tx_count")
                    is_retx = _row_text(row, "IsRetransmission", "new_tx_or_retx").lower() in {"1", "true", "retx", "retransmission"}
                    if tx_count is not None:
                        is_retx = float(tx_count) > 1.0
                    grouped[int(round(slot))].append(1.0 if is_retx else 0.0)
                points = [[float(slot), sum(vals) / len(vals)] for slot, vals in sorted(grouped.items()) if vals]
                dataset = {"mode": _honest_chart_mode(points), "x_label": "Slot/sample", "y_label": "Retransmission rate", "points": points}
            elif chart_name == "HARQ RTT distribution":
                values: list[float] = []
                values_are_ms = False
                for row in records:
                    rtt = _row_float(row, "HARQRTT_ms", "harq_rtt_ms", "RTT_ms")
                    if rtt is not None:
                        values_are_ms = True
                    if rtt is None:
                        tx_slot = _row_float(row, "Slot")
                        feedback_slot = _row_float(row, "FeedbackDueSlot")
                        if tx_slot is not None and feedback_slot is not None:
                            rtt = max(0.0, float(feedback_slot) - float(tx_slot))
                    if rtt is None:
                        first_tx = _row_float(row, "first_tx_time", "FirstTxTime")
                        last_tx = _row_float(row, "last_tx_time", "LastTxTime")
                        if first_tx is not None and last_tx is not None:
                            rtt = max(0.0, float(last_tx) - float(first_tx))
                    if rtt is not None and math.isfinite(float(rtt)):
                        values.append(float(rtt))
                points = _histogram_points(values, 16)
                rtt_axis = "HARQ RTT (ms)" if values_are_ms else "HARQ RTT (slot/sample units)"
                dataset = {"mode": "bar", "x_label": rtt_axis, "y_label": "Count", "points": points}
            elif chart_name == "newTx vs retx comparison":
                counts = Counter()
                for row in records:
                    tx_count = _row_float(row, "TxCount", "tx_count")
                    is_retx = _row_text(row, "IsRetransmission", "new_tx_or_retx").lower() in {"1", "true", "retx", "retransmission"}
                    if tx_count is not None:
                        is_retx = float(tx_count) > 1.0
                    counts["retx" if is_retx else "newTx"] += 1
                dataset, _summary = _bar_dataset_from_named_values("HARQ transmission type", "Count", [(key, float(value)) for key, value in counts.items()])
            elif chart_name == "goodput vs retransmissions":
                goodput_by_type: dict[str, list[float]] = defaultdict(list)
                for row in records:
                    goodput = _row_float(row, "Goodput_Mbps", "goodput_mbps")
                    if goodput is None or not math.isfinite(float(goodput)):
                        continue
                    tx_count = _row_float(row, "TxCount", "tx_count")
                    is_retx = _row_text(
                        row, "IsRetransmission", "new_tx_or_retx"
                    ).lower() in {"1", "true", "retx", "retransmission"}
                    if tx_count is not None:
                        is_retx = float(tx_count) > 1.0
                    goodput_by_type["retx" if is_retx else "newTx"].append(float(goodput))
                named_values = [
                    (key, sum(values) / len(values))
                    for key, values in sorted(goodput_by_type.items()) if values
                ]
                dataset, _summary = _bar_dataset_from_named_values(
                    "HARQ transmission type", "Mean goodput (Mbps)", named_values
                )
            elif chart_name == "residual failure patterns":
                counts = Counter(_row_text(row, "final_state", "FinalState", "ack_nack_state", "ACKNACKState") or "unknown" for row in records)
                dataset, _summary = _bar_dataset_from_named_values("Final HARQ state", "Count", [(key, float(value)) for key, value in counts.items()])
            elif chart_name == "ACK/NACK timeline":
                grouped: dict[int, list[float]] = defaultdict(list)
                for row in records:
                    slot = _row_float(row, "Slot")
                    decode_ok = _row_text(row, "CombinedDecodeOK", "CurrentDecodeOK", "ack_nack")
                    if slot is None or not decode_ok:
                        continue
                    grouped[int(round(slot))].append(1.0 if decode_ok.lower() in {"1", "true", "ack", "ok"} else 0.0)
                points = [[float(slot), sum(vals) / len(vals)] for slot, vals in sorted(grouped.items())]
                dataset = {"mode": _honest_chart_mode(points), "x_label": "Slot", "y_label": "ACK ratio", "points": points}
            elif chart_name == "residual BLER by HARQ process":
                grouped: dict[int, list[float]] = defaultdict(list)
                for row in records:
                    harq_id = _row_float(row, "HarqID", "HARQProcess")
                    decode_ok = _row_text(row, "CombinedDecodeOK", "CurrentDecodeOK", "crc_result")
                    if harq_id is None or not decode_ok:
                        continue
                    grouped[int(round(harq_id))].append(0.0 if decode_ok.lower() in {"1", "true", "ack", "ok", "pass"} else 1.0)
                points = [[float(harq_id), sum(vals) / len(vals)] for harq_id, vals in sorted(grouped.items())]
                dataset = {"mode": "bar", "x_label": "HARQ process", "y_label": "Residual BLER", "points": points}
            elif chart_name == "residual BLER after HARQ":
                grouped: dict[str, list[float]] = defaultdict(list)
                for row in records:
                    direction = _row_text(row, "Direction").upper() or "UNSPECIFIED"
                    decode_ok = _row_text(
                        row, "CombinedDecodeOK", "CurrentDecodeOK", "crc_result"
                    )
                    if not decode_ok:
                        continue
                    grouped[direction].append(
                        0.0 if decode_ok.lower() in {"1", "true", "ack", "ok", "pass"} else 1.0
                    )
                named_values = [
                    (direction, sum(values) / len(values))
                    for direction, values in sorted(grouped.items()) if values
                ]
                dataset, _summary = _bar_dataset_from_named_values(
                    "Direction", "Residual BLER after HARQ", named_values
                )
            elif chart_name in {"combining gain histogram", "HARQ combining gain distribution"}:
                gains_db: list[float] = []
                for row in records:
                    gain = _row_float(
                        row, "CombiningGain_dB", "combining_gain_db",
                        "HARQCombiningGain_dB", "harq_combining_gain_db",
                        "LLRCombiningGain_dB",
                    )
                    if gain is not None and math.isfinite(float(gain)):
                        gains_db.append(float(gain))
                if gains_db:
                    points = _histogram_points(gains_db, 16)
                    dataset = {"mode": "bar", "x_label": "HARQ combining gain (dB)", "y_label": "Count", "points": points}
                else:
                    reason = "No dB-valued HARQ combining gain field is present in the runtime HARQ artifacts; the materializer will not substitute tx_count or binary ACK improvement as a physical combining gain."
                    return {
                        "csv_bytes": _encode_csv(["run_id", "chart_name", "status", "reason", "checked_source"], [[run_id, chart_name, "unavailable_exact_reason", reason, source_path]]),
                        "img_bytes": _render_reason_svg(chart_name, "No measured HARQ combining gain evidence was exported.", [reason]),
                        "csv_status": "unavailable_exact_reason",
                        "image_status": "generated_unavailable_reason_svg",
                        "source_table_path": source_path,
                        "source_row_count": len(records),
                        "note": reason,
                    }
            elif chart_name == "combiner summary":
                gain_values = [
                    float(value)
                    for value in (
                        _row_float(row, "LLRCombiningGain_dB", "HARQCombiningGain_dB")
                        for row in records
                    )
                    if value is not None and math.isfinite(float(value))
                ]
                combining_rows = sum(
                    1 for row in records
                    if bool(_row_flag(row, "HARQCombiningApplied"))
                )
                previous_llrs = sum(
                    float(_row_float(row, "PreviousLLRCount") or 0.0)
                    for row in records
                )
                current_llrs = sum(
                    float(_row_float(row, "CurrentLLRCount") or 0.0)
                    for row in records
                )
                combined_llrs = sum(
                    float(_row_float(row, "CombinedLLRCount") or 0.0)
                    for row in records
                )
                dataset, _summary = _bar_dataset_from_named_values(
                    "LLR accounting", "Count",
                    [("previous", previous_llrs), ("current", current_llrs), ("combined", combined_llrs)],
                )
            if dataset and dataset.get("points"):
                dataset["sample_count"] = len(records)
                if chart_name in {
                    "HARQ process timeline", "ACK/NACK timeline",
                    "retransmission rate trend",
                }:
                    dataset["evidence_shape_policy"] = "observed_timeline"
                else:
                    dataset["evidence_shape_policy"] = "observed_distribution"
                summary = [f"source_table={source_path}", f"source_rows={len(records)}", f"chart={chart_name}"]
                csv_bytes = _chart_dataset_csv(run_id, chart_name, dataset, source_path, len(records), "derived_chart_dataset", note)
                img_bytes = img_bytes_override or _render_svg_plot(chart_name, "Runtime HARQ evidence rendered from persisted truthful rows.", dataset, summary)
                return {
                    "csv_bytes": csv_bytes,
                    "img_bytes": img_bytes,
                    "csv_status": "derived_chart_dataset",
                    "image_status": "generated_specialized_runtime_summary_svg",
                    "source_table_path": source_path,
                    "source_row_count": len(records),
                    "source_mapping_status": "exact",
                    "note": note,
                }
    if chart_name in {"scheduler fairness over time", "fairness index trend"}:
        source_path = ""
        for candidate in (
            "reports/csv/live_user_performance_snapshot.csv",
            "system/csv/system_ue_summary.csv",
        ):
            if candidate in existing:
                source_path = candidate
                break
        _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path) if source_path else ([], [])
        if records:
            csv_rows: list[dict[str, Any]] = []
            summary_lines: list[str] = []
            point_rows: list[dict[str, Any]] = []
            for metric_name, direction in (
                ("DL_Throughput_Mbps", "DL"),
                ("UL_Throughput_Mbps", "UL"),
                ("UserThroughput_Mbps", "Combined"),
            ):
                values: list[float] = []
                for row in records:
                    value = _row_float(row, metric_name)
                    if value is not None and math.isfinite(value):
                        values.append(float(value))
                if not values:
                    continue
                sorted_vals = sorted(values)
                total = sum(sorted_vals)
                total_sq = sum(v * v for v in sorted_vals)
                fairness = (total * total) / (len(sorted_vals) * total_sq) if sorted_vals and total_sq > 0 else 0.0
                summary_lines.append(
                    f"{direction}: Jain fairness={fairness:.4f}, mean={total/len(sorted_vals):.3f} Mbps, p95={_percentile(sorted_vals, 0.95):.3f} Mbps"
                )
                for idx, value in enumerate(sorted_vals, start=1):
                    row = {
                        "run_id": run_id,
                        "chart_name": chart_name,
                        "direction": direction,
                        "ue_rank": idx,
                        "throughput_mbps": value,
                        "jain_fairness_index": fairness,
                        "source_table_logical_path": source_path,
                    }
                    csv_rows.append(row)
                    if direction == "Combined":
                        point_rows.append(row)
            plot_rows = point_rows or csv_rows
            if plot_rows:
                subtitle = "Per-UE throughput distribution from the runtime fairness source. This run exports a final user snapshot, not a slot-by-slot fairness timeline."
                dataset = {
                    "mode": "bar",
                    "x_label": "UE rank (sorted by throughput)",
                    "y_label": "Throughput (Mbps)",
                    "points": [[float(row["ue_rank"]), float(row["throughput_mbps"])] for row in plot_rows[:MAX_PREVIEW_ROWS]],
                    "evidence_shape_policy": "observed_distribution",
                    "sample_count": len(plot_rows),
                }
                return {
                    "csv_bytes": _encode_dict_rows(
                        ["run_id", "chart_name", "direction", "ue_rank", "throughput_mbps", "jain_fairness_index", "source_table_logical_path"],
                        csv_rows,
                    ),
                    "img_bytes": _render_svg_plot(chart_name, subtitle, dataset, summary_lines),
                    "csv_status": "specialized_runtime_fairness_dataset",
                    "image_status": "generated_specialized_runtime_summary_svg",
                    "source_table_path": source_path,
                    "source_row_count": len(records),
                    "note": "Fairness visualization derived from truthful per-UE runtime throughput evidence.",
                }
    if chart_name == "IQ imbalance summary":
        timeline_path = "rf/csv/iq_imbalance_timeline_trace.csv"
        summary_path = "rf/csv/probe_rf_iq_imbalance.csv"
        _, timeline_records = _artifact_rows_by_path(existing, fetch_artifact_bytes, timeline_path)
        _, summary_records = _artifact_rows_by_path(existing, fetch_artifact_bytes, summary_path)
        if not timeline_records and not summary_records:
            reason = "No dedicated RF IQ-imbalance runtime artifacts were persisted for this run."
            return {
                "csv_bytes": _encode_csv(
                    ["run_id", "chart_name", "status", "reason", "checked_sources"],
                    [[run_id, chart_name, "unavailable_exact_reason", reason, f"{timeline_path}|{summary_path}"]],
                ),
                "img_bytes": _render_reason_svg(chart_name, "The browser is preserving honesty for this RF impairment chart.", [reason]),
                "csv_status": "missing_source_summary",
                "image_status": "generated_unavailable_reason_svg",
                "source_table_path": f"{timeline_path}|{summary_path}",
                "source_row_count": 0,
                "note": reason,
            }
        grouped: dict[tuple[str, int, int], dict[str, Any]] = {}
        measured_rows = 0
        for idx, row in enumerate(timeline_records, start=1):
            mirror = _row_float(row, "IQImbalanceMirrorPowerRatio_dB")
            image_rej = _row_float(row, "IQImbalanceImageRejection_dB")
            corr = _row_float(row, "IQImbalanceIQCorrelation")
            alpha = _row_float(row, "IQImbalanceEstimatedAlphaAbs")
            beta = _row_float(row, "IQImbalanceEstimatedBetaAbs")
            has_measurement = any(value is not None for value in (mirror, image_rej, corr, alpha, beta))
            if not has_measurement:
                continue
            direction = _row_text(row, "Direction") or "NA"
            frame_v = _row_float(row, "Frame")
            slot_v = _row_float(row, "Slot")
            frame_i = int(round(frame_v or 0.0))
            slot_i = int(round(slot_v or idx))
            key = (direction, frame_i, slot_i)
            bucket = grouped.setdefault(
                key,
                {
                    "direction": direction,
                    "frame": frame_i,
                    "slot": slot_i,
                    "sample_count": 0,
                    "image_rejection_sum": 0.0,
                    "image_rejection_count": 0,
                    "mirror_sum": 0.0,
                    "mirror_count": 0,
                    "corr_abs_sum": 0.0,
                    "corr_abs_count": 0,
                    "source_table_logical_path": timeline_path,
                },
            )
            bucket["sample_count"] += 1
            measured_rows += 1
            if image_rej is not None:
                bucket["image_rejection_sum"] += image_rej
                bucket["image_rejection_count"] += 1
            if mirror is not None:
                bucket["mirror_sum"] += mirror
                bucket["mirror_count"] += 1
            if corr is not None:
                bucket["corr_abs_sum"] += abs(corr)
                bucket["corr_abs_count"] += 1
        summary_lines = [f"timeline_source={timeline_path}", f"summary_source={summary_path}", f"timeline_rows={len(timeline_records)}", f"measured_rows={measured_rows}"]
        for row in summary_records[:4]:
            direction = _row_text(row, "Direction") or "ALL"
            availability = _row_text(row, "Availability") or "unknown"
            measured = int(round(_row_float(row, "MeasuredRowCount") or 0.0))
            applied = int(round(_row_float(row, "AppliedRowCount") or 0.0))
            mean_ir = _row_float(row, "MeanImageRejection_dB")
            model_set = _row_text(row, "ModelSet")
            line = f"{direction}: availability={availability} measured={measured} applied={applied}"
            if mean_ir is not None:
                line += f" mean_ir={mean_ir:.3f}dB"
            if model_set:
                line += f" model={model_set}"
            summary_lines.append(line)
        if not grouped:
            reason = "The dedicated IQ timeline exists, but it contains no finite sample-domain IQ-imbalance measurements."
            return {
                "csv_bytes": _encode_csv(
                    ["run_id", "chart_name", "status", "reason", "checked_sources"],
                    [[run_id, chart_name, "unavailable_exact_reason", reason, f"{timeline_path}|{summary_path}"]],
                ),
                "img_bytes": _render_reason_svg(chart_name, "The browser is preserving honesty for this RF impairment chart.", summary_lines + [reason]),
                "csv_status": "unavailable_exact_reason",
                "image_status": "generated_unavailable_reason_svg",
                "source_table_path": f"{timeline_path}|{summary_path}",
                "source_row_count": len(timeline_records),
                "note": reason,
            }
        grouped_rows = sorted(grouped.values(), key=lambda row: (row["frame"], row["slot"], row["direction"]))
        csv_rows: list[dict[str, Any]] = []
        dataset_points: list[list[float]] = []
        for event_index, row in enumerate(grouped_rows, start=1):
            mean_image_rej = (
                row["image_rejection_sum"] / row["image_rejection_count"] if row["image_rejection_count"] else None
            )
            mean_mirror = row["mirror_sum"] / row["mirror_count"] if row["mirror_count"] else None
            mean_abs_corr = row["corr_abs_sum"] / row["corr_abs_count"] if row["corr_abs_count"] else None
            if mean_image_rej is not None:
                dataset_points.append([float(event_index), float(mean_image_rej)])
            csv_rows.append(
                {
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "event_index": event_index,
                    "direction": row["direction"],
                    "frame": row["frame"],
                    "slot": row["slot"],
                    "sample_count": row["sample_count"],
                    "mean_image_rejection_db": mean_image_rej if mean_image_rej is not None else "",
                    "mean_mirror_power_ratio_db": mean_mirror if mean_mirror is not None else "",
                    "mean_abs_iq_correlation": mean_abs_corr if mean_abs_corr is not None else "",
                    "source_table_logical_path": timeline_path,
                }
            )
        dataset = {
            "mode": "line",
            "x_label": "Measured event index",
            "y_label": "Mean Image Rejection (dB)",
            "points": dataset_points,
            "evidence_shape_policy": "observed_timeline",
            "sample_count": len(grouped_rows),
        }
        return {
            "csv_bytes": _encode_dict_rows(
                [
                    "run_id",
                    "chart_name",
                    "event_index",
                    "direction",
                    "frame",
                    "slot",
                    "sample_count",
                    "mean_image_rejection_db",
                    "mean_mirror_power_ratio_db",
                    "mean_abs_iq_correlation",
                    "source_table_logical_path",
                ],
                csv_rows,
            ),
            "img_bytes": _render_svg_plot(chart_name, "Sample-domain IQ-imbalance measurements aggregated from the persisted waveform TX/RX impairment runtime.", dataset, summary_lines),
            "csv_status": "specialized_runtime_iq_imbalance_dataset",
            "image_status": "generated_specialized_runtime_summary_svg",
            "source_table_path": f"{timeline_path}|{summary_path}",
            "source_row_count": len(grouped_rows),
            "note": "IQ-imbalance chart derived from dedicated runtime RF impairment artifacts.",
        }
    if chart_name in {"DL resource-grid heatmap", "PDSCH map", "PUSCH map", "PUCCH map"}:
        if chart_name in {"DL resource-grid heatmap", "PDSCH map"}:
            _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "reports/csv/dl_resource_grid_heatmap.csv")
            source_path = "reports/csv/dl_resource_grid_heatmap.csv"
            if not records:
                _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "packet_flow/csv/live_dl_scheduler_grants.csv")
                source_path = "packet_flow/csv/live_dl_scheduler_grants.csv"
                grid_rows, chosen_cell = _build_grid_heatmap_records(
                    records,
                    cell_names=("CellID", "ServingCell", "BaseStationID"),
                    slot_names=("Slot", "Frame"),
                    rb_names=("PRBStart",),
                    occ_names=("AllocatedPRBCount", "PRBCount"),
                )
            else:
                grid_rows, chosen_cell = _build_grid_heatmap_records(
                    records,
                    cell_names=("cell_id",),
                    slot_names=("slot",),
                    rb_names=("rb_index",),
                    occ_names=("occupancy_fraction", "occupancy_count"),
                )
        elif chart_name == "PUSCH map":
            _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "reports/csv/ul_resource_grid_heatmap.csv")
            source_path = "reports/csv/ul_resource_grid_heatmap.csv"
            if not records:
                _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "packet_flow/csv/live_ul_scheduler_grants.csv")
                source_path = "packet_flow/csv/live_ul_scheduler_grants.csv"
                grid_rows, chosen_cell = _build_grid_heatmap_records(
                    records,
                    cell_names=("CellID", "ServingCell", "BaseStationID"),
                    slot_names=("Slot", "Frame"),
                    rb_names=("PRBStart",),
                    occ_names=("AllocatedPRBCount", "PRBCount"),
                )
            else:
                grid_rows, chosen_cell = _build_grid_heatmap_records(
                    records,
                    cell_names=("cell_id",),
                    slot_names=("slot",),
                    rb_names=("rb_index",),
                    occ_names=("occupancy_fraction", "occupancy_count"),
                )
        else:
            _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "packet_flow/csv/live_pucch_grants.csv")
            source_path = "packet_flow/csv/live_pucch_grants.csv"
            chosen_cell = _selected_cell(records, "ServingCell", "BaseStationID")
            grid_rows = []
            for row in records:
                if chosen_cell and _row_text(row, "ServingCell", "BaseStationID") != chosen_cell:
                    continue
                slot_v = _row_float(row, "Slot")
                start_v = _row_float(row, "PUCCHPRBStart")
                count_v = _row_float(row, "PUCCHPRBCount")
                if slot_v is None or start_v is None or count_v is None:
                    continue
                for rb_idx in range(int(round(start_v)), int(round(start_v + count_v))):
                    grid_rows.append(
                        {
                            "cell_id": chosen_cell,
                            "slot": int(round(slot_v)),
                            "rb_index": rb_idx,
                            "occupancy_value": 1.0,
                        }
                    )
        if not grid_rows:
            return {
                "csv_bytes": _encode_csv(["run_id", "chart_name", "status", "reason"], [[run_id, chart_name, "unavailable", "no_runtime_grid_rows"]]),
                "img_bytes": _render_reason_svg(chart_name, "No real grid rows were available for this run.", [f"source={source_path}", "The requested map was not rendered because no slot/PRB occupancy rows were found."]),
                "csv_status": "unavailable_exact_reason",
                "image_status": "generated_unavailable_reason_svg",
                "source_table_path": source_path,
                "source_row_count": 0,
                "note": "No truthful grid occupancy rows were available.",
            }
        x_labels, y_labels, matrix = _grid_rows_to_heatmap(grid_rows, "slot", "rb_index", "occupancy_value")
        summary = [f"source={source_path}", f"selected_cell={chosen_cell or 'all'}", f"points={len(grid_rows)}"]
        if chart_name == "PUCCH map":
            summary.append("mode=scheduled_pending_execution_from_runtime_pucch_grants")
        csv_header = ["run_id", "chart_name", "cell_id", "slot", "rb_index", "occupancy_value", "source_table_logical_path"]
        csv_rows = [
            {
                "run_id": run_id,
                "chart_name": chart_name,
                "cell_id": row.get("cell_id", ""),
                "slot": row.get("slot", ""),
                "rb_index": row.get("rb_index", ""),
                "occupancy_value": row.get("occupancy_value", ""),
                "source_table_logical_path": source_path,
            }
            for row in grid_rows
        ]
        image_bytes, image_status = _render_heatmap_or_projection_svg(
            chart_name,
            "Runtime slot/RB occupancy derived from persisted waveform scheduler evidence.",
            x_labels, y_labels, matrix, summary, "Slot", "RB index",
        )
        return {
            "csv_bytes": _encode_dict_rows(csv_header, csv_rows),
            "img_bytes": image_bytes,
            "csv_status": "specialized_runtime_grid_dataset",
            "image_status": image_status,
            "source_table_path": source_path,
            "source_row_count": len(grid_rows),
            "note": "Heatmap built from truthful slot/RB occupancy evidence.",
        }
    if chart_name == "candidate cell rank heatmap":
        source_path = "reports/csv/live_candidate_cell_runtime.csv"
        _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path)
        if not records:
            source_path = "reports/csv/live_cell_measurement_trace.csv"
            _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path)
        rows = []
        for row in records:
            rank_v = _row_float(row, "candidate_rank", "CandidateRank")
            cell_v = _row_text(row, "cell_id", "CellID")
            if rank_v is None or not cell_v:
                continue
            rows.append(
                {
                    "candidate_rank": int(round(rank_v)),
                    "cell_id": cell_v,
                    "observation_count": float(_row_float(row, "candidate_observation_count") or 1.0),
                }
            )
        if not rows:
            return {
                "csv_bytes": _encode_csv(["run_id", "chart_name", "status", "reason"], [[run_id, chart_name, "unavailable", "no_candidate_rank_rows"]]),
                "img_bytes": _render_reason_svg(chart_name, "No candidate-rank rows were persisted for this run.", [f"source={source_path}", "The candidate-cell heatmap was not rendered because no runtime rank observations were found."]),
                "csv_status": "unavailable_exact_reason",
                "image_status": "generated_unavailable_reason_svg",
                "source_table_path": source_path,
                "source_row_count": 0,
                "note": "No truthful candidate-cell rank rows were available.",
            }
        x_labels, y_labels, matrix = _grid_rows_to_heatmap(rows, "candidate_rank", "cell_id", "observation_count")
        summary = [f"source={source_path}", f"rows={len(rows)}", "note=matrix counts candidate-rank observations per cell from persisted runtime measurements."]
        csv_rows = [
            {
                "run_id": run_id,
                "chart_name": chart_name,
                "candidate_rank": row["candidate_rank"],
                "cell_id": row["cell_id"],
                "observation_count": row["observation_count"],
                "source_table_logical_path": source_path,
            }
            for row in rows
        ]
        image_bytes, image_status = _render_heatmap_or_projection_svg(
            chart_name,
            "Runtime candidate-cell ranking density derived from persisted measurement-trace observations.",
            x_labels, y_labels, matrix, summary, "Candidate rank", "Cell",
        )
        return {
            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "candidate_rank", "cell_id", "observation_count", "source_table_logical_path"], csv_rows),
            "img_bytes": image_bytes,
            "csv_status": "specialized_runtime_candidate_rank_dataset",
            "image_status": image_status,
            "source_table_path": source_path,
            "source_row_count": len(rows),
            "note": "Candidate-cell heatmap derived from real per-UE measurement-trace ranking rows.",
        }
    if chart_name in {"PDCCH map", "CCE usage heatmap"}:
        _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "air_interface/csv/pdcch_trials.csv")
        rows = []
        for row in records:
            slot_v = _row_float(row, "Slot")
            cell_v = _row_text(row, "BaseStationID", "CellID", "ServingCell")
            used_v = _row_float(row, "UsedCCECount")
            util_v = _row_float(row, "CORESETUtilization", "ControlCapacityUtilization")
            if slot_v is None or not cell_v:
                continue
            rows.append({"slot": int(round(slot_v)), "cell_id": cell_v, "occupancy_value": util_v if util_v is not None else float(used_v or 0.0), "UsedCCECount": used_v or 0.0})
        if not rows:
            return None
        x_labels, y_labels, matrix = _grid_rows_to_heatmap(rows, "slot", "cell_id", "occupancy_value")
        summary = ["source=air_interface/csv/pdcch_trials.csv", f"rows={len(rows)}", "note=exact CCE-to-REG placement is not exported; this view uses runtime used-CCE / control utilization."]
        csv_header = ["run_id", "chart_name", "cell_id", "slot", "occupancy_value", "UsedCCECount", "source_table_logical_path"]
        csv_rows = [{**row, "run_id": run_id, "chart_name": chart_name, "source_table_logical_path": "air_interface/csv/pdcch_trials.csv"} for row in rows]
        image_bytes, image_status = _render_heatmap_or_projection_svg(
            chart_name,
            "Runtime PDCCH control occupancy by slot and serving cell.",
            x_labels, y_labels, matrix, summary, "Slot", "Cell",
        )
        return {
            "csv_bytes": _encode_dict_rows(csv_header, csv_rows),
            "img_bytes": image_bytes,
            "csv_status": "specialized_runtime_control_dataset",
            "image_status": image_status,
            "source_table_path": "air_interface/csv/pdcch_trials.csv",
            "source_row_count": len(rows),
            "note": "Control-region occupancy derived from PDCCH runtime trials.",
        }
    if chart_name in {"PBCH/SSB map", "SSB/PBCH occupancy map"}:
        _, records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "air_interface/csv/pbch_trials.csv")
        rows = []
        for row in records:
            slot_v = _row_float(row, "Slot")
            cell_v = _row_text(row, "BaseStationID", "CellID", "ServingCell")
            note_text = _row_text(row, "Notes")
            if not cell_v or cell_v.lower() == "not_applicable":
                note_match = re.search(r"NCellID=(\d+)", note_text)
                if note_match:
                    cell_v = note_match.group(1)
            success_v = _row_float(row, "DecodeSuccess", "CRCPass")
            beam_v = _row_text(row, "SelectedBeamIndex")
            if not beam_v or beam_v.lower() == "not_applicable":
                ssb_match = re.search(r"SSBIdx=(\d+)", note_text)
                if ssb_match:
                    beam_v = ssb_match.group(1)
            if slot_v is None or not cell_v:
                continue
            rows.append({"slot": int(round(slot_v)), "cell_id": cell_v, "occupancy_value": float(success_v or 0.0), "SelectedBeamIndex": beam_v})
        if not rows:
            return None
        x_labels, y_labels, matrix = _grid_rows_to_heatmap(rows, "slot", "cell_id", "occupancy_value")
        summary = ["source=air_interface/csv/pbch_trials.csv", f"rows={len(rows)}", "note=exact SSB RE mapping is not exported; this view shows runtime PBCH/SSB observation density and decode success."]
        csv_header = ["run_id", "chart_name", "cell_id", "slot", "occupancy_value", "SelectedBeamIndex", "source_table_logical_path"]
        csv_rows = [{**row, "run_id": run_id, "chart_name": chart_name, "source_table_logical_path": "air_interface/csv/pbch_trials.csv"} for row in rows]
        img_bytes, image_status = _render_heatmap_or_projection_svg(
            chart_name,
            "Runtime PBCH/SSB observations by slot and cell.",
            x_labels, y_labels, matrix, summary, "Slot", "Cell",
        )
        return {
            "csv_bytes": _encode_dict_rows(csv_header, csv_rows),
            "img_bytes": img_bytes,
            "csv_status": "specialized_runtime_control_dataset",
            "image_status": image_status,
            "source_table_path": "air_interface/csv/pbch_trials.csv",
            "source_row_count": len(rows),
            "note": "PBCH/SSB occupancy summary derived from runtime PBCH observations.",
        }
    if chart_name == "UL resource-grid / equalized symbol summaries":
        _, grid_records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "reports/csv/ul_resource_grid_heatmap.csv")
        _, preview_records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "air_interface/csv/ul_constellation_preview.csv")
        _, trial_records = _artifact_rows_by_path(existing, fetch_artifact_bytes, "air_interface/csv/ul_pusch_trials.csv")
        grid_rows, chosen_cell = _build_grid_heatmap_records(
            grid_records,
            cell_names=("cell_id",),
            slot_names=("slot",),
            rb_names=("rb_index",),
            occ_names=("occupancy_fraction", "occupancy_count"),
        )
        if not grid_rows:
            return None
        x_labels, y_labels, matrix = _grid_rows_to_heatmap(grid_rows, "slot", "rb_index", "occupancy_value")
        mean_evm = [row for row in trial_records if _row_float(row, "EVM_rms") is not None]
        mean_evm_value = sum(_row_float(row, "EVM_rms") or 0.0 for row in mean_evm) / max(len(mean_evm), 1)
        ul_points = []
        ul_reference = []
        for r in preview_records:
            eq_r = _row_float(r, "EqualizedReal")
            eq_i = _row_float(r, "EqualizedImag")
            if eq_r is not None and eq_i is not None:
                ul_points.append((float(eq_r), float(eq_i), "UL"))
            ref_r = _row_float(r, "ReferenceSymbolReal")
            ref_i = _row_float(r, "ReferenceSymbolImag")
            if ref_r is not None and ref_i is not None:
                ul_reference.append((float(ref_r), float(ref_i)))
        panels = [("UL equalized symbols", ul_points[:600], ul_reference[:64])]
        summary = ["grid_source=reports/csv/ul_resource_grid_heatmap.csv", "preview_source=air_interface/csv/ul_constellation_preview.csv", f"selected_cell={chosen_cell or 'all'}", f"trial_rows={len(trial_records)}", f"mean_evm_rms={mean_evm_value:.6f}"]
        image = _render_scatter_panels_svg(chart_name, "UL resource occupancy plus equalized-symbol preview from real waveform runtime exports.", panels, summary)
        csv_rows = []
        for row in trial_records:
            csv_rows.append(
                {
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "frame": _row_float(row, "Frame"),
                    "slot": _row_float(row, "Slot"),
                    "MeasuredSINR_dB": _row_float(row, "MeasuredSINR_dB"),
                    "EVM_rms": _row_float(row, "EVM_rms"),
                    "DecoderIterations": _row_float(row, "DecoderIterations"),
                    "Modulation": _row_text(row, "Modulation"),
                    "source_table_logical_path": "air_interface/csv/ul_pusch_trials.csv",
                }
            )
        return {
            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "frame", "slot", "MeasuredSINR_dB", "EVM_rms", "DecoderIterations", "Modulation", "source_table_logical_path"], csv_rows),
            "img_bytes": image,
            "csv_status": "specialized_runtime_summary_dataset",
            "image_status": "generated_specialized_runtime_summary_svg",
            "source_table_path": "air_interface/csv/ul_pusch_trials.csv|air_interface/csv/ul_constellation_preview.csv",
            "source_row_count": len(csv_rows),
            "note": "UL summary built from real PUSCH trials and equalized-symbol preview samples.",
        }
    if chart_name == "constellation per modulation order":
        all_records: list[tuple[str, str, dict[str, str]]] = []
        for source_path in (
            "reports/csv/equalized_constellations.csv",
            "analytics/csv/constellation_analytics.csv",
            "air_interface/csv/dl_constellation_preview.csv",
            "air_interface/csv/ul_constellation_preview.csv",
        ):
            _, rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path)
            for row in rows:
                direction = _row_text(row, "Direction")
                if not direction:
                    direction = "DL" if "/dl_" in source_path else ("UL" if "/ul_" in source_path else "")
                if direction:
                    all_records.append((direction, source_path, row))
        panels: list[tuple[str, list[tuple[float, float, str]], list[tuple[float, float]]]] = []
        csv_rows: list[dict[str, Any]] = []
        for modulation in ("QPSK", "16QAM", "64QAM", "256QAM"):
            points: list[tuple[float, float, str]] = []
            ideal: list[tuple[float, float]] = []
            for direction, source_path, row in all_records:
                if _row_text(row, "Modulation").upper() != modulation:
                    continue
                eq_r = _row_float(row, "EqualizedReal", "PostEqualizedReal", "RawEqualizedReal")
                eq_i = _row_float(row, "EqualizedImag", "PostEqualizedImag", "RawEqualizedImag")
                ref_r = _row_float(row, "ReferenceSymbolReal", "TxReal")
                ref_i = _row_float(row, "ReferenceSymbolImag", "TxImag")
                if eq_r is None or eq_i is None:
                    continue
                points.append((eq_r, eq_i, direction))
                if ref_r is not None and ref_i is not None:
                    ideal.append((ref_r, ref_i))
                csv_rows.append(
                    {
                        "run_id": run_id,
                        "chart_name": chart_name,
                        "direction": direction,
                        "modulation": modulation,
                        "EqualizedReal": eq_r,
                        "EqualizedImag": eq_i,
                        "ReferenceSymbolReal": ref_r,
                        "ReferenceSymbolImag": ref_i,
                        "source_table_logical_path": source_path,
                    }
                )
            if points:
                panels.append((modulation, points[:500], ideal[:64]))
        if not panels:
            return None
        source_summary = "|".join(sorted({str(row["source_table_logical_path"]) for row in csv_rows}))
        summary = [f"source={source_summary}", f"points={len(csv_rows)}"]
        return {
            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "direction", "modulation", "EqualizedReal", "EqualizedImag", "ReferenceSymbolReal", "ReferenceSymbolImag", "source_table_logical_path"], csv_rows),
            "img_bytes": _render_scatter_panels_svg(chart_name, "Equalized runtime constellation samples grouped by modulation order.", panels, summary),
            "csv_status": "specialized_runtime_constellation_dataset",
            "image_status": "generated_specialized_runtime_constellation_svg",
            "source_table_path": source_summary,
            "source_row_count": len(csv_rows),
            "note": "Constellation grouped by modulation order using runtime equalized samples.",
        }
    if chart_name in {
        "Tx waveform",
        "Rx waveform",
        "magnitude vs sample",
        "phase vs sample",
        "power vs sample",
        "pre-channel waveform",
        "post-channel waveform",
        "post-impairment waveform",
        "stage overlay plots",
        "UE-wise / link-wise waveform comparison",
    }:
        source_path, records = _first_available_rows(
            existing,
            fetch_artifact_bytes,
            ["analytics/csv/waveform_analytics.csv", "reports/csv/live_waveform_preview.csv", "reports/csv/live_tx_rx_stage_trace.csv"],
        )
        if records:
            csv_rows: list[dict[str, Any]] = []
            use_time_axis = any(_row_float(row, "Time_s") is not None for row in records)
            x_label = "Time_s" if use_time_axis else "SampleIndex"
            series: list[dict[str, Any]] = []
            summary = [f"source={source_path}", f"rows={len(records)}"]
            if chart_name in {"Tx waveform", "Rx waveform", "magnitude vs sample", "phase vs sample", "power vs sample"}:
                metric_specs: list[tuple[str, str, Callable[[dict[str, str]], float | None]]] = []
                if chart_name == "Tx waveform":
                    metric_specs = [
                        ("Tx real", "TxReal", lambda row: _row_float(row, "TxReal")),
                        ("Tx imag", "TxImag", lambda row: _row_float(row, "TxImag")),
                    ]
                elif chart_name == "Rx waveform":
                    metric_specs = [
                        ("Rx real", "RxReal", lambda row: _row_float(row, "RxReal")),
                        ("Rx imag", "RxImag", lambda row: _row_float(row, "RxImag")),
                    ]
                elif chart_name == "magnitude vs sample":
                    metric_specs = [
                        ("Tx magnitude", "TxMagnitude", lambda row: _row_float(row, "TxMagnitude")),
                        ("Rx magnitude", "RxMagnitude", lambda row: _row_float(row, "RxMagnitude")),
                    ]
                elif chart_name == "phase vs sample":
                    metric_specs = [
                        ("Tx phase", "TxPhase_rad", lambda row: math.atan2(_row_float(row, "TxImag") or 0.0, _row_float(row, "TxReal") or 0.0) if _row_float(row, "TxReal", "TxImag") is not None else None),
                        ("Rx phase", "RxPhase_rad", lambda row: math.atan2(_row_float(row, "RxImag") or 0.0, _row_float(row, "RxReal") or 0.0) if _row_float(row, "RxReal", "RxImag") is not None else None),
                    ]
                else:
                    metric_specs = [
                        ("Tx power", "TxPower", lambda row: (_row_float(row, "TxMagnitude") or 0.0) ** 2 if _row_float(row, "TxMagnitude") is not None else None),
                        ("Rx power", "RxPower", lambda row: (_row_float(row, "RxMagnitude") or 0.0) ** 2 if _row_float(row, "RxMagnitude") is not None else None),
                    ]
                for series_name, metric_name, resolver in metric_specs:
                    points: list[list[float]] = []
                    for row in records:
                        x_val = _row_float(row, x_label) if use_time_axis else _row_float(row, "SampleIndex")
                        if x_val is None:
                            continue
                        y_val = resolver(row)
                        if y_val is None or not math.isfinite(y_val):
                            continue
                        points.append([float(x_val), float(y_val)])
                        csv_rows.append(
                            {
                                "run_id": run_id,
                                "chart_name": chart_name,
                                x_label: x_val,
                                "series_name": series_name,
                                "metric_name": metric_name,
                                "metric_value": y_val,
                                "source_table_logical_path": source_path,
                            }
                        )
                    if points:
                        series.append({"name": series_name, "points": _downsample_points(points, 256)})
                if series:
                    flat_values = [
                        abs(float(point[1]))
                        for item in series
                        for point in (item.get("points") or [])
                        if isinstance(point, (list, tuple)) and len(point) >= 2 and _coerce_float(point[1]) is not None
                    ]
                    if flat_values and max(flat_values) <= 1e-15:
                        img_bytes = _render_waveform_flat_card_svg(chart_name, series, summary)
                    else:
                        img_bytes = _render_multi_series_svg(chart_name, "Sample-domain waveform traces rendered from persisted runtime preview samples.", series, summary, x_label=x_label, y_label="Amplitude / derived value")
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", x_label, "series_name", "metric_name", "metric_value", "source_table_logical_path"], csv_rows),
                        "img_bytes": img_bytes,
                        "csv_status": "specialized_runtime_waveform_dataset",
                        "image_status": "generated_specialized_runtime_waveform_svg",
                        "source_table_path": source_path,
                        "source_row_count": len(csv_rows),
                        "note": "Waveform chart derived from actual exported TX/RX preview samples.",
                    }
            if chart_name in {"pre-channel waveform", "post-channel waveform", "post-impairment waveform", "stage overlay plots", "UE-wise / link-wise waveform comparison"}:
                stage_rows = [row for row in records if _row_text(row, "Stage", "stage_name", "TraceStage")]
                if stage_rows:
                    wanted_stage_tokens = {
                        "pre-channel waveform": ("prechannel", "tx"),
                        "post-channel waveform": ("postchannel", "channel"),
                        "post-impairment waveform": ("postimpairment", "impairment"),
                    }
                    grouped: dict[str, list[list[float]]] = defaultdict(list)
                    for row in stage_rows:
                        stage_name = _row_text(row, "Stage", "stage_name", "TraceStage")
                        stage_token = re.sub(r"[^a-z0-9]+", "", stage_name.lower())
                        if chart_name in wanted_stage_tokens and not any(token in stage_token for token in wanted_stage_tokens[chart_name]):
                            continue
                        x_val = _row_float(row, "Time_s", "SampleIndex", "Slot", "Frame")
                        y_val = _row_float(row, "Magnitude", "Value", "Amplitude", "SignalValue")
                        if x_val is None or y_val is None:
                            continue
                        grouped[stage_name].append([float(x_val), float(y_val)])
                    if grouped:
                        stage_series = [{"name": name, "points": _downsample_points(points, 180)} for name, points in list(grouped.items())[:5] if points]
                        csv_rows = []
                        for name, points in grouped.items():
                            for x_val, y_val in points[:MAX_PREVIEW_ROWS]:
                                csv_rows.append({"run_id": run_id, "chart_name": chart_name, "stage_name": name, "x_value": x_val, "metric_value": y_val, "source_table_logical_path": source_path})
                        return {
                            "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "stage_name", "x_value", "metric_value", "source_table_logical_path"], csv_rows),
                            "img_bytes": _render_multi_series_svg(chart_name, "Stage-wise waveform evidence derived only from persisted stage-trace samples.", stage_series, summary, x_label="Time / sample", y_label="Magnitude"),
                            "csv_status": "specialized_runtime_stage_waveform_dataset",
                            "image_status": "generated_specialized_runtime_waveform_svg",
                            "source_table_path": source_path,
                            "source_row_count": len(csv_rows),
                            "note": "Stage waveform chart derived from persisted stage-trace samples when exported by runtime.",
                        }
    if chart_name in {"pre-equalization constellation", "post-equalization constellation", "EVM RMS", "symbol decision error histogram"}:
        dl_preview_path = "air_interface/csv/dl_constellation_preview.csv"
        ul_preview_path = "air_interface/csv/ul_constellation_preview.csv"
        _, dl_preview = _artifact_rows_by_path(existing, fetch_artifact_bytes, dl_preview_path)
        _, ul_preview = _artifact_rows_by_path(existing, fetch_artifact_bytes, ul_preview_path)
        preview_rows = [("DL", row, dl_preview_path) for row in dl_preview] + [("UL", row, ul_preview_path) for row in ul_preview]
        for source_path in ("reports/csv/equalized_constellations.csv", "analytics/csv/constellation_analytics.csv"):
            _, constellation_rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, source_path)
            for row in constellation_rows:
                direction = _row_text(row, "Direction").upper()
                if direction not in {"DL", "UL"}:
                    direction = "DL" if "dl_" in str(_row_text(row, "SourceArtifact")).lower() else "UL"
                preview_rows.append((direction, row, source_path))
        if chart_name in {"pre-equalization constellation", "post-equalization constellation"} and preview_rows:
            panels: list[tuple[str, list[tuple[float, float, str]], list[tuple[float, float]]]] = []
            csv_rows: list[dict[str, Any]] = []
            for direction in ("DL", "UL"):
                points: list[tuple[float, float, str]] = []
                ideal: list[tuple[float, float]] = []
                for row_direction, row, source_path in preview_rows:
                    if row_direction != direction:
                        continue
                    if chart_name == "pre-equalization constellation":
                        x_val = _row_float(row, "ReceivedReal", "RxReal", "RawEqualizedReal", "DetectorOutputReal")
                        y_val = _row_float(row, "ReceivedImag", "RxImag", "RawEqualizedImag", "DetectorOutputImag")
                    else:
                        x_val = _row_float(row, "EqualizedReal")
                        y_val = _row_float(row, "EqualizedImag")
                    if x_val is None or y_val is None:
                        continue
                    ref_r = _row_float(row, "ReferenceSymbolReal")
                    ref_i = _row_float(row, "ReferenceSymbolImag")
                    points.append((float(x_val), float(y_val), direction))
                    if ref_r is not None and ref_i is not None:
                        ideal.append((float(ref_r), float(ref_i)))
                    csv_rows.append(
                        {
                            "run_id": run_id,
                            "chart_name": chart_name,
                            "direction": direction,
                            "x_value": x_val,
                            "y_value": y_val,
                            "reference_x": ref_r if ref_r is not None else "",
                            "reference_y": ref_i if ref_i is not None else "",
                            "source_table_logical_path": source_path,
                        }
                    )
                if points:
                    panels.append((f"{direction} {chart_name.replace(' constellation', '')}", points[:450], ideal[:64]))
            if panels:
                direction_counts = Counter(str(row["direction"]) for row in csv_rows)
                return {
                    "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "direction", "x_value", "y_value", "reference_x", "reference_y", "source_table_logical_path"], csv_rows),
                    "img_bytes": _render_scatter_panels_svg(chart_name, "Constellation cloud from real runtime preview samples. Grey markers show ideal reference symbols when exported.", panels, [f"dl_rows={direction_counts['DL']}", f"ul_rows={direction_counts['UL']}"]),
                    "csv_status": "specialized_runtime_constellation_dataset",
                    "image_status": "generated_specialized_runtime_constellation_svg",
                    "source_table_path": f"{dl_preview_path}|{ul_preview_path}",
                    "source_row_count": len(csv_rows),
                    "note": "Constellation chart derived directly from persisted preview samples.",
                }
        if chart_name == "EVM RMS":
            trial_sources = _all_available_rows(existing, fetch_artifact_bytes, ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"])
            named_values: list[tuple[str, float]] = []
            csv_rows: list[dict[str, Any]] = []
            for source_path, rows in trial_sources:
                direction = "DL" if "dl_pdsch" in source_path else "UL"
                evm_values = [float(value) for value in (_row_float(row, "EVM_rms") for row in rows) if value is not None]
                if not evm_values:
                    continue
                mean_evm = sum(evm_values) / len(evm_values)
                named_values.append((direction, mean_evm))
                csv_rows.append({"run_id": run_id, "chart_name": chart_name, "direction": direction, "mean_evm_rms": mean_evm, "sample_count": len(evm_values), "source_table_logical_path": source_path})
            if named_values:
                dataset, summary = _bar_dataset_from_named_values("Direction bucket", "Mean EVM RMS", named_values)
                return {
                    "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "direction", "mean_evm_rms", "sample_count", "source_table_logical_path"], csv_rows),
                    "img_bytes": _render_svg_plot(chart_name, "Mean trial-level EVM from persisted waveform trials.", dataset, summary),
                    "csv_status": "specialized_runtime_evm_dataset",
                    "image_status": "generated_specialized_runtime_summary_svg",
                    "source_table_path": "|".join(source_path for source_path, _rows in trial_sources),
                    "source_row_count": len(csv_rows),
                    "note": "EVM RMS chart derived from trial-level runtime EVM fields.",
                }
        if chart_name == "symbol decision error histogram" and preview_rows:
            values: list[float] = []
            csv_rows: list[dict[str, Any]] = []
            for direction, row, source_path in preview_rows:
                eq_r = _row_float(row, "EqualizedReal")
                eq_i = _row_float(row, "EqualizedImag")
                ref_r = _row_float(row, "ReferenceSymbolReal")
                ref_i = _row_float(row, "ReferenceSymbolImag")
                if None in {eq_r, eq_i, ref_r, ref_i}:
                    continue
                error_mag = math.sqrt((float(eq_r) - float(ref_r)) ** 2 + (float(eq_i) - float(ref_i)) ** 2)
                values.append(error_mag)
                csv_rows.append({"run_id": run_id, "chart_name": chart_name, "direction": direction, "decision_error_magnitude": error_mag, "source_table_logical_path": source_path})
            if values:
                bins = _bin_mean_points([(value, 1.0) for value in values], 16)
                dataset = {"mode": "bar", "x_label": "Decision error magnitude", "y_label": "Mean count per bin", "points": bins}
                return {
                    "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "direction", "decision_error_magnitude", "source_table_logical_path"], csv_rows),
                    "img_bytes": _render_svg_plot(chart_name, "Histogram of equalized-symbol distance to the nearest exported reference symbol.", dataset, [f"samples={len(values)}"]),
                    "csv_status": "specialized_runtime_symbol_error_dataset",
                    "image_status": "generated_specialized_runtime_summary_svg",
                    "source_table_path": f"{dl_preview_path}|{ul_preview_path}",
                    "source_row_count": len(csv_rows),
                    "note": "Decision-error histogram derived from preview equalized and reference symbols.",
                }
    if chart_name in {"BER", "BLER", "FER", "BLER vs SNR", "BLER vs SINR", "BLER vs MCS", "BER vs SNR", "FER vs SNR", "CRC pass/fail rates", "decoder iteration distributions", "per-UE and per-cell reliability"}:
        trial_rows = _trial_rows_with_paths(
            existing,
            fetch_artifact_bytes,
            ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv", "air_interface/csv/pdcch_trials.csv", "air_interface/csv/pucch_trials.csv", "air_interface/csv/pbch_trials.csv"],
        )
        if trial_rows:
            data_trial_rows = _data_channel_trial_rows(trial_rows)
            reliability_rows = data_trial_rows if chart_name in {"BER", "BLER", "BLER vs SNR", "BLER vs SINR", "BLER vs MCS", "BER vs SNR"} else trial_rows
            if chart_name == "BLER vs MCS":
                mcs_chart = _runtime_bler_vs_mcs_chart(data_trial_rows, run_id)
                if mcs_chart is not None:
                    return mcs_chart
            if chart_name in {"BLER vs SNR", "BLER vs SINR", "BER vs SNR", "FER vs SNR"}:
                pairs: list[tuple[float, float]] = []
                used_source_path = ""
                is_snr_axis = chart_name.endswith("vs SNR")
                x_label = "AppliedAWGNSNR_dB" if is_snr_axis else "PostEqSINR_dB"
                y_label = "BLER" if "BLER" in chart_name else ("FER" if "FER" in chart_name else "BER")
                selected_x_labels: Counter[str] = Counter()
                for source_path, row in reliability_rows:
                    if is_snr_axis:
                        x_val, row_x_label = _row_snr_axis_value(row)
                    else:
                        x_val, row_x_label = _row_quality_axis_value(row, allow_receiver_hest=False)
                    if x_val is None:
                        continue
                    selected_x_labels[row_x_label] += 1
                    if y_label == "BER":
                        y_val = _trial_row_ber(row)
                    elif y_label == "FER":
                        y_val = _trial_row_fer(row)
                    else:
                        y_val = _trial_row_bler(row)
                    if y_val is None:
                        continue
                    pairs.append((float(x_val), float(y_val)))
                    used_source_path = used_source_path or source_path
                if pairs:
                    if selected_x_labels:
                        x_label = selected_x_labels.most_common(1)[0][0]
                    if not is_snr_axis:
                        csv_bytes, dataset = _metric_rows_by_binned_x(pairs, x_label=x_label, y_label=y_label, chart_name=chart_name, run_id=run_id, source_path=used_source_path or "multiple_runtime_trials", bin_width=1.0)
                        chart_note = "Reliability-vs-SINR curve binned by data-domain trial SINR where available; receiver-Hest diagnostic SINR is intentionally not used as the x-axis fallback."
                    else:
                        csv_bytes, dataset = _metric_rows_by_exact_x(pairs, x_label=x_label, y_label=y_label, chart_name=chart_name, run_id=run_id, source_path=used_source_path or "multiple_runtime_trials")
                        chart_note = "Reliability-vs-SNR curve uses the applied channel-noise operating point and actual trial BER/BLER/FER outcomes."
                    if y_label in {"BLER", "BER", "FER"}:
                        dataset["y_axis_min"] = 0.0
                        dataset["y_axis_max"] = 1.0
                    dataset["mode"] = _honest_chart_mode(dataset.get("points", []), str(dataset.get("mode") or "line"))
                    dataset["sample_count"] = len(pairs)
                    if len(dataset.get("points", [])) == 1:
                        dataset["mode"] = "bar"
                        dataset["evidence_shape_policy"] = "operating_point"
                    else:
                        dataset["evidence_shape_policy"] = "observed_relation"
                    return {
                        "csv_bytes": csv_bytes,
                        "img_bytes": _render_svg_plot(chart_name, "Reliability metric aggregated from truthful trial rows.", dataset, [f"Runtime samples: {len(pairs)}", f"X axis: {_display_axis_label(x_label)}", f"Y axis: {_display_axis_label(y_label)}"]),
                        "csv_status": "specialized_runtime_reliability_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": used_source_path or "multiple_runtime_trials",
                        "source_row_count": len(pairs),
                        "note": chart_note,
                    }
            if chart_name in {"BER", "BLER", "FER", "CRC pass/fail rates"}:
                counts: Counter[str] = Counter()
                source_counter: Counter[str] = Counter()
                for source_path, row in reliability_rows:
                    source_counter[source_path] += 1
                    if chart_name == "BER":
                        bit_errors = _row_float(row, "BitErrors")
                        bits_compared = _row_float(row, "BitsCompared")
                        if bit_errors is not None and bits_compared is not None and bits_compared > 0:
                            counts["BER errors"] += max(0.0, float(bit_errors))
                            counts["BER denominator"] += float(bits_compared)
                    elif chart_name == "BLER":
                        value = _trial_row_bler(row)
                        if value is not None:
                            counts["BLER errors"] += float(value)
                            counts["BLER denominator"] += 1
                    elif chart_name == "FER":
                        value = _trial_row_fer(row)
                        if value is not None:
                            counts["FER errors"] += float(value)
                            counts["FER denominator"] += 1
                    else:
                        token = _row_text(row, "CRCPass", "DecodeSuccess", "CombinedDecodeOK")
                        if token:
                            counts["Pass"] += 1 if token.lower() in {"1", "true", "pass", "passed", "ok", "ack"} else 0
                            counts["Fail"] += 0 if token.lower() in {"1", "true", "pass", "passed", "ok", "ack"} else 1
                named_values: list[tuple[str, float]] = []
                if chart_name == "CRC pass/fail rates":
                    named_values = [(key, float(value)) for key, value in counts.items() if key in {"Pass", "Fail"}]
                else:
                    denominator = float(counts.get(f"{chart_name} denominator", 0.0))
                    errors = float(counts.get(f"{chart_name} errors", 0.0))
                    if denominator > 0:
                        named_values = [(chart_name, errors / denominator)]
                if named_values:
                    source_path_text = "|".join(source_counter.keys()) if source_counter else "multiple_runtime_trials"
                    if chart_name in {"BER", "BLER", "FER"}:
                        sample_count = int(round(float(counts.get(f"{chart_name} denominator", 0.0))))
                        error_count = float(counts.get(f"{chart_name} errors", 0.0))
                        ci95_lower, ci95_upper = _wilson_score_interval(error_count, sample_count)
                        observed_rate = float(named_values[0][1])
                        dataset, summary = _bar_dataset_from_named_values(
                            "Reliability statistic",
                            chart_name,
                            [("95% lower", ci95_lower), ("Observed", observed_rate), ("95% upper", ci95_upper)],
                        )
                        dataset["tick_labels"] = ["95% lower", "Observed", "95% upper"]
                        dataset["sample_count"] = sample_count
                        csv_rows = [{
                            "run_id": run_id,
                            "chart_name": chart_name,
                            "metric_name": chart_name,
                            "metric_value": observed_rate,
                            "error_count": error_count,
                            "sample_count": sample_count,
                            "ci95_lower": ci95_lower,
                            "ci95_upper": ci95_upper,
                            "source_table_logical_path": source_path_text,
                        }]
                        summary.extend([
                            f"errors={error_count:g}",
                            f"denominator={sample_count}",
                            "interval=Wilson 95%",
                        ])
                    else:
                        dataset, summary = _bar_dataset_from_named_values("CRC outcome", "Count", named_values)
                        sample_count = int(counts.get("Pass", 0) + counts.get("Fail", 0))
                        csv_rows = [{
                            "run_id": run_id,
                            "chart_name": chart_name,
                            "metric_name": name,
                            "metric_value": value,
                            "error_count": "",
                            "sample_count": sample_count,
                            "ci95_lower": "",
                            "ci95_upper": "",
                            "source_table_logical_path": source_path_text,
                        } for name, value in named_values]
                    summary.extend([f"{path}={count}" for path, count in source_counter.most_common(4)])
                    img_bytes = _render_svg_plot(
                        chart_name,
                        "Observed reliability from persisted waveform/control trials with exact denominator and Wilson interval where applicable.",
                        dataset,
                        summary,
                    )
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "metric_name", "metric_value", "error_count", "sample_count", "ci95_lower", "ci95_upper", "source_table_logical_path"], csv_rows),
                        "img_bytes": img_bytes,
                        "csv_status": "specialized_runtime_reliability_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": source_path_text,
                        "source_row_count": sum(source_counter.values()),
                        "note": "BER is a bit-error-weighted ratio; BLER/FER are error-count ratios. Wilson 95% intervals use the exact persisted denominator.",
                    }
            if chart_name == "decoder iteration distributions":
                values = [float(value) for _source_path, row in trial_rows for value in [_row_float(row, "DecoderIterations")] if value is not None]
                if values:
                    dataset = {
                        "mode": "bar",
                        "x_label": "Decoder iterations",
                        "y_label": "Mean count per bin",
                        "points": _bin_mean_points([(value, 1.0) for value in values], 14),
                        "evidence_shape_policy": "observed_distribution",
                        "sample_count": len(values),
                    }
                    csv_rows = [{"run_id": run_id, "chart_name": chart_name, "decoder_iterations": value, "source_table_logical_path": "multiple_runtime_trials"} for value in values]
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "decoder_iterations", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_svg_plot(chart_name, "Decoder-iteration distribution from persisted waveform trial rows.", dataset, [f"samples={len(values)}"]),
                        "csv_status": "specialized_runtime_decoder_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": "multiple_runtime_trials",
                        "source_row_count": len(csv_rows),
                        "note": "Decoder iteration histogram derived from runtime decoder-trial rows.",
                    }
            if chart_name == "per-UE and per-cell reliability":
                reliability_rows: list[dict[str, Any]] = []
                grouped: dict[str, list[float]] = defaultdict(list)
                for source_path, row in trial_rows:
                    key = _row_text(row, "UEID", "UEIndex", "RNTI", "BaseStationID", "CellID", "ServingCell")
                    value = _trial_row_bler(row)
                    if not key or value is None:
                        continue
                    grouped[key].append(float(value))
                named_values = [(name, sum(values) / len(values)) for name, values in sorted(grouped.items(), key=lambda item: item[0])[:12] if values]
                if named_values:
                    dataset, summary = _bar_dataset_from_named_values("Entity bucket", "Mean BLER", named_values)
                    reliability_rows = [{"run_id": run_id, "chart_name": chart_name, "entity_name": name, "mean_bler": value, "source_table_logical_path": "multiple_runtime_trials"} for name, value in named_values]
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "entity_name", "mean_bler", "source_table_logical_path"], reliability_rows),
                        "img_bytes": _render_svg_plot(chart_name, "Mean BLER by UE or serving-cell identifier from persisted trial rows.", dataset, summary),
                        "csv_status": "specialized_runtime_reliability_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": "multiple_runtime_trials",
                        "source_row_count": len(reliability_rows),
                        "note": "Per-entity reliability summary derived from runtime trial outcomes.",
                    }
    if chart_name in {
        "throughput",
        "offered throughput",
        "goodput",
        "spectral efficiency",
        "throughput over time",
        "goodput over time",
        "throughput vs SNR",
        "throughput vs load",
        "goodput vs retransmissions",
        "per-UE throughput",
        "per-cell throughput",
        "throughput percentile plots",
        "throughput CDF",
    }:
        trial_sources = _all_available_rows(existing, fetch_artifact_bytes, ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"])
        _, user_rows = _artifact_rows_by_path(existing, fetch_artifact_bytes, "reports/csv/live_user_performance_snapshot.csv")
        if trial_sources or user_rows:
            if chart_name in {"throughput over time", "goodput over time"} and trial_sources:
                timeline_chart = _runtime_throughput_timeline_chart(chart_name, trial_sources, run_id)
                if timeline_chart is not None:
                    return timeline_chart
            if chart_name in {"throughput", "offered throughput", "goodput", "spectral efficiency"}:
                named_values: list[tuple[str, float]] = []
                csv_rows: list[dict[str, Any]] = []
                for source_path, rows in trial_sources:
                    direction = "DL" if "dl_pdsch" in source_path else "UL"
                    if chart_name == "throughput":
                        values = [float(value) for value in (_row_float(row, "Throughput_Mbps", "MeasuredThroughput_Mbps", "OfferedThroughput_Mbps") for row in rows) if value is not None]
                    elif chart_name == "offered throughput":
                        values = [float(value) for value in (_row_float(row, "OfferedThroughput_Mbps") for row in rows) if value is not None]
                    elif chart_name == "goodput":
                        values = [float(value) for value in (_row_float(row, "Goodput_Mbps") for row in rows) if value is not None]
                    else:
                        values = [float(value) / 100.0 for value in (_row_float(row, "Goodput_Mbps", "Throughput_Mbps") for row in rows) if value is not None]
                    if not values:
                        continue
                    metric_value = sum(values) / len(values)
                    named_values.append((direction, metric_value))
                    csv_rows.append({"run_id": run_id, "chart_name": chart_name, "direction": direction, "metric_value": metric_value, "sample_count": len(values), "source_table_logical_path": source_path})
                if named_values:
                    y_label = "Mean spectral efficiency (b/s/Hz)" if chart_name == "spectral efficiency" else f"Mean {chart_name} (Mbps)"
                    dataset, summary = _bar_dataset_from_named_values("Direction bucket", y_label, named_values)
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "direction", "metric_value", "sample_count", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_svg_plot(chart_name, "Direction-wise summary derived from persisted throughput/goodput trial rows.", dataset, summary),
                        "csv_status": "specialized_runtime_throughput_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": "|".join(source_path for source_path, _rows in trial_sources),
                        "source_row_count": len(csv_rows),
                        "note": "Summary derived from truthful trial throughput/goodput fields.",
                    }
            if chart_name in {"throughput vs SNR", "throughput vs load", "goodput vs retransmissions"}:
                pairs: list[tuple[float, float]] = []
                source_token = ""
                if chart_name == "throughput vs SNR":
                    x_label = "AppliedAWGNSNR_dB"
                    y_label = "Throughput_Mbps"
                elif chart_name == "throughput vs load":
                    x_label = "AllocatedPRBCount"
                    y_label = "Throughput_Mbps"
                else:
                    x_label = "HARQRetxCount"
                    y_label = "Goodput_Mbps"
                selected_x_labels: Counter[str] = Counter()
                for source_path, rows in trial_sources:
                    for row in rows:
                        if chart_name == "throughput vs SNR":
                            x_val, row_x_label = _row_snr_axis_value(row)
                            if row_x_label:
                                selected_x_labels[row_x_label] += 1
                        elif chart_name == "throughput vs load":
                            x_val = _row_float(row, "AllocatedPRBCount", "PRBCount", "NumPRB", "ScheduledPRBs")
                        else:
                            x_val = _row_float(row, "HARQRetxCount", "RetxCount", "RetransmissionCount")
                        if x_val is None:
                            continue
                        y_val = _row_float(row, y_label, "Goodput_Mbps", "Throughput_Mbps")
                        if y_val is None:
                            continue
                        pairs.append((float(x_val), float(y_val)))
                        source_token = source_token or source_path
                if pairs:
                    if chart_name == "throughput vs SNR" and selected_x_labels:
                        x_label = selected_x_labels.most_common(1)[0][0]
                    csv_bytes, dataset = _metric_rows_by_exact_x(pairs, x_label=x_label, y_label=y_label, chart_name=chart_name, run_id=run_id, source_path=source_token or "multiple_runtime_trials")
                    dataset["sample_count"] = len(pairs)
                    if len(dataset.get("points", [])) == 1:
                        dataset["mode"] = "bar"
                        dataset["evidence_shape_policy"] = "operating_point"
                    else:
                        dataset["mode"] = "scatter"
                        dataset["evidence_shape_policy"] = "observed_relation"
                    subtitle = "Correlation view derived directly from persisted runtime throughput/goodput trials."
                    if chart_name == "throughput vs SNR":
                        subtitle = "Throughput versus the applied channel-noise SNR operating point from persisted runtime trials."
                    if chart_name == "throughput vs load":
                        subtitle = "Load view uses scheduled PRB count as the honest load proxy because this run exports one high-load operating point, not a sweep campaign."
                    return {
                        "csv_bytes": csv_bytes,
                        "img_bytes": _render_svg_plot(chart_name, subtitle, dataset, [f"samples={len(pairs)}"]),
                        "csv_status": "specialized_runtime_throughput_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": source_token or "multiple_runtime_trials",
                        "source_row_count": len(pairs),
                        "note": "Throughput relationship chart derived from truthful trial fields.",
                    }
            if chart_name in {"per-UE throughput", "throughput percentile plots", "throughput CDF"} and user_rows:
                values: list[float] = []
                csv_rows: list[dict[str, Any]] = []
                for row in user_rows:
                    ue_name = _row_text(row, "UEID", "UEIndex", "RNTI")
                    throughput = _row_float(row, "UserThroughput_Mbps", "DL_Throughput_Mbps", "UL_Throughput_Mbps")
                    if throughput is None:
                        continue
                    values.append(float(throughput))
                    csv_rows.append({"run_id": run_id, "chart_name": chart_name, "ue_name": ue_name or f"UE{len(csv_rows)+1}", "throughput_mbps": throughput, "source_table_logical_path": "reports/csv/live_user_performance_snapshot.csv"})
                if values:
                    sorted_values = sorted(values)
                    if chart_name == "per-UE throughput":
                        dataset = {
                            "mode": "bar",
                            "x_label": "UE rank",
                            "y_label": "Throughput (Mbps)",
                            "points": [[float(idx + 1), value] for idx, value in enumerate(sorted_values[:MAX_PREVIEW_ROWS])],
                            "evidence_shape_policy": "operating_point" if len(sorted_values) == 1 else "observed_distribution",
                            "sample_count": len(sorted_values),
                        }
                    elif chart_name == "throughput percentile plots":
                        percentiles = [(5, _percentile(sorted_values, 0.05)), (25, _percentile(sorted_values, 0.25)), (50, _percentile(sorted_values, 0.50)), (75, _percentile(sorted_values, 0.75)), (95, _percentile(sorted_values, 0.95))]
                        dataset = {"mode": "bar", "x_label": "Percentile", "y_label": "Throughput (Mbps)", "points": [[float(p), float(v)] for p, v in percentiles]}
                    else:
                        dataset = {
                            "mode": "cdf",
                            "x_label": "Throughput (Mbps)",
                            "y_label": "Empirical CDF",
                            "points": [[value, (idx + 1) / len(sorted_values)] for idx, value in enumerate(sorted_values[:MAX_PREVIEW_ROWS])],
                            "evidence_shape_policy": "empirical_cdf",
                            "sample_count": len(sorted_values),
                        }
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "ue_name", "throughput_mbps", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_svg_plot(chart_name, "Per-UE throughput distribution derived from the exported runtime user snapshot.", dataset, [f"ue_samples={len(values)}"]),
                        "csv_status": "specialized_runtime_throughput_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": "reports/csv/live_user_performance_snapshot.csv",
                        "source_row_count": len(csv_rows),
                        "note": "User distribution view derived from truthful user-performance snapshot rows.",
                    }
            if chart_name == "per-cell throughput":
                grouped: dict[str, list[float]] = defaultdict(list)
                for source_path, rows in trial_sources:
                    for row in rows:
                        cell_name = _row_text(row, "BaseStationID", "ServingCell", "CellID")
                        throughput = _row_float(row, "Throughput_Mbps", "Goodput_Mbps", "MeasuredThroughput_Mbps")
                        if not cell_name or throughput is None:
                            continue
                        grouped[cell_name].append(float(throughput))
                named_values = [(cell_name, sum(values) / len(values)) for cell_name, values in sorted(grouped.items())[:12] if values]
                if named_values:
                    dataset, summary = _bar_dataset_from_named_values("Cell bucket", "Mean throughput (Mbps)", named_values)
                    csv_rows = [{"run_id": run_id, "chart_name": chart_name, "cell_name": name, "throughput_mbps": value, "source_table_logical_path": "multiple_runtime_trials"} for name, value in named_values]
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "cell_name", "throughput_mbps", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_svg_plot(chart_name, "Per-cell throughput derived from persisted runtime trials.", dataset, summary),
                        "csv_status": "specialized_runtime_throughput_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": "multiple_runtime_trials",
                        "source_row_count": len(csv_rows),
                        "note": "Cell aggregation derived from truthful trial throughput rows.",
                    }
    if chart_name in {
        "latency CDF",
    }:
        latency_chart = _runtime_latency_cdf_chart(chart_name, existing, fetch_artifact_bytes, run_id)
        if latency_chart is not None:
            return latency_chart
    if chart_name in {
        "energy per bit histogram",
    }:
        energy_chart = _runtime_energy_histogram_chart(chart_name, existing, fetch_artifact_bytes, run_id)
        if energy_chart is not None:
            return energy_chart
    if chart_name in {"active bandwidth vs power", "active rank vs power"}:
        power_chart = _runtime_power_scatter_chart(chart_name, existing, fetch_artifact_bytes, run_id)
        if power_chart is not None:
            return power_chart
    if chart_name in {
        "applied AWGN SNR vs measured runtime SINR comparison",
        "applied vs measured runtime SNR/SINR comparison",
        "ServingRSRP / RSRP / CSI-RSRP trends",
        "CQI / PMI / RI / CRI / SSBRI trends",
        "CQI-to-MCS mapping plot",
        "selected MCS distribution",
        "selected vs derived MCS confusion matrix",
        "quality-vs-selected-MCS mismatch plot",
        "per-beam quality plot",
        "per-layer quality plot",
    }:
        la_path, la_rows = _first_available_rows(
            existing,
            fetch_artifact_bytes,
            ["reports/csv/live_link_adaptation_input_table.csv", "reports/csv/table_cqi_pmi_ri.csv", "reports/csv/live_rsrp_serving_trace.csv"],
        )
        if la_rows:
            if chart_name in {"applied AWGN SNR vs measured runtime SINR comparison", "applied vs measured runtime SNR/SINR comparison"}:
                series_specs = [
                    ("Applied AWGN SNR", "AppliedAWGNSNR_dB"),
                    ("Post-eq SINR", "PostEqSINR_dB"),
                    ("Measured wideband SINR", "MeasuredWidebandSINR_dB"),
                ]
                series: list[dict[str, Any]] = []
                csv_rows: list[dict[str, Any]] = []
                for series_name, field_name in series_specs:
                    points: list[list[float]] = []
                    for idx, row in enumerate(la_rows, start=1):
                        x_val = _row_float(row, "Slot", "Frame")
                        if x_val is None:
                            x_val = float(idx)
                        y_val = _row_float(row, field_name)
                        if y_val is None:
                            continue
                        points.append([float(x_val), float(y_val)])
                        csv_rows.append({"run_id": run_id, "chart_name": chart_name, "slot_or_sample": x_val, "series_name": series_name, "metric_value_db": y_val, "source_table_logical_path": la_path})
                    if points:
                        series.append({"name": series_name, "points": _downsample_points(points, 160)})
                if series:
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "slot_or_sample", "series_name", "metric_value_db", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_multi_series_svg(chart_name, "Runtime-applied noise calibration and measured SINR are plotted from execution export fields; configured and large-scale preview values are excluded from this quality chart.", series, [f"rows={len(la_rows)}"], x_label="Slot / sample", y_label="dB"),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(csv_rows),
                        "note": "Comparison chart derived only from runtime-applied noise calibration and measured SINR fields; configured, proxy, and large-scale preview values are not charted as quality.",
                    }
            if chart_name == "ServingRSRP / RSRP / CSI-RSRP trends":
                rsrp_rows = la_rows
                # Absolute RSRP is a power-per-reference-RE quantity in dBm.
                # CSI_RSRP_dB is a relative digital-grid power and must never
                # be mixed with calibrated dBm values on this axis.
                series_specs = [("Serving RSRP", "ServingRSRP_dBm"), ("RSRP", "RSRP_dBm"), ("CSI-RSRP", "CSI_RSRP_dBm")]
                series: list[dict[str, Any]] = []
                csv_rows: list[dict[str, Any]] = []
                for series_name, field_name in series_specs:
                    points: list[list[float]] = []
                    for idx, row in enumerate(rsrp_rows, start=1):
                        x_val = _row_float(row, "Slot", "Frame")
                        if x_val is None:
                            x_val = float(idx)
                        y_val = _row_float(row, field_name)
                        if y_val is None:
                            continue
                        points.append([float(x_val), float(y_val)])
                        csv_rows.append({"run_id": run_id, "chart_name": chart_name, "slot_or_sample": x_val, "series_name": series_name, "metric_value": y_val, "source_table_logical_path": la_path})
                    if points:
                        series.append({"name": series_name, "points": _downsample_points(points, 160)})
                if series:
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "slot_or_sample", "series_name", "metric_value", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_multi_series_svg(chart_name, "Calibrated serving RSRP and CSI-RSRP power per reference RE from runtime measurement exports.", series, [f"rows={len(rsrp_rows)}", "Unit authority: absolute dBm only"], x_label="Slot / sample", y_label="RSRP per reference RE (dBm)"),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(csv_rows),
                        "note": "RSRP trend chart contains only calibrated absolute dBm fields; relative digital-grid CSI_RSRP_dB is excluded.",
                    }
            if chart_name == "CQI / PMI / RI / CRI / SSBRI trends":
                series_specs = [("CQI", "WidebandCQI"), ("PMI", "PMI"), ("RI", "RI"), ("CRI", "CRI"), ("SSBRI", "SSBRI")]
                series: list[dict[str, Any]] = []
                csv_rows: list[dict[str, Any]] = []
                for series_name, field_name in series_specs:
                    points: list[list[float]] = []
                    for idx, row in enumerate(la_rows, start=1):
                        x_val = _row_float(row, "Slot", "Frame")
                        if x_val is None:
                            x_val = float(idx)
                        y_val = _row_float(row, field_name)
                        if y_val is None:
                            continue
                        points.append([float(x_val), float(y_val)])
                        csv_rows.append({"run_id": run_id, "chart_name": chart_name, "slot_or_sample": x_val, "series_name": series_name, "metric_value": y_val, "source_table_logical_path": la_path})
                    if points:
                        series.append({"name": series_name, "points": _downsample_points(points, 160)})
                if series:
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "slot_or_sample", "series_name", "metric_value", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_multi_series_svg(chart_name, "CQI/PMI/RI/CRI/SSBRI trends from runtime link-adaptation inputs.", series, [f"rows={len(la_rows)}"], x_label="Slot / sample", y_label="Index / reported value"),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(csv_rows),
                        "note": "CSI feedback trend chart derived from runtime measurement rows.",
                    }
            if chart_name == "CQI-to-MCS mapping plot":
                pairs = [(float(cqi), float(mcs)) for row in la_rows for cqi, mcs in [(_row_float(row, "WidebandCQI"), _row_float(row, "CQIDerivedMCS", "MCSIndex"))] if cqi is not None and mcs is not None]
                if pairs:
                    csv_bytes, dataset = _metric_rows_by_exact_x(pairs, x_label="WidebandCQI", y_label="DerivedOrSelectedMCS", chart_name=chart_name, run_id=run_id, source_path=la_path)
                    return {
                        "csv_bytes": csv_bytes,
                        "img_bytes": _render_svg_plot(chart_name, "CQI-to-MCS mapping observed in runtime link-adaptation rows.", dataset, [f"samples={len(pairs)}"]),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(pairs),
                        "note": "CQI-to-MCS mapping derived from runtime CQI and MCS fields.",
                    }
            if chart_name == "selected MCS distribution":
                values = [float(value) for value in (_row_float(row, "MCSIndex", "CQIDerivedMCS") for row in la_rows) if value is not None]
                if values:
                    dataset = {"mode": "bar", "x_label": "MCS", "y_label": "Mean count per bin", "points": _bin_mean_points([(value, 1.0) for value in values], 18)}
                    csv_rows = [{"run_id": run_id, "chart_name": chart_name, "mcs_index": value, "source_table_logical_path": la_path} for value in values]
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "mcs_index", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_svg_plot(chart_name, "Distribution of selected runtime MCS values.", dataset, [f"samples={len(values)}"]),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(csv_rows),
                        "note": "MCS distribution derived from runtime link-adaptation rows.",
                    }
            if chart_name == "selected vs derived MCS confusion matrix":
                matrix_rows: list[dict[str, Any]] = []
                raw_rows: list[dict[str, Any]] = []
                for row in la_rows:
                    selected = _row_float(row, "MCSIndex")
                    derived = _row_float(row, "CQIDerivedMCS")
                    if selected is None or derived is None:
                        continue
                    raw_rows.append({"selected_mcs": int(round(selected)), "derived_mcs": int(round(derived)), "count": 1.0})
                if raw_rows:
                    x_labels, y_labels, matrix = _grid_rows_to_heatmap(raw_rows, "derived_mcs", "selected_mcs", "count")
                    matrix_rows = [{"run_id": run_id, "chart_name": chart_name, "selected_mcs": row["selected_mcs"], "derived_mcs": row["derived_mcs"], "count": row["count"], "source_table_logical_path": la_path} for row in raw_rows]
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "selected_mcs", "derived_mcs", "count", "source_table_logical_path"], matrix_rows),
                        "img_bytes": _render_heatmap_svg(chart_name, "Confusion matrix between applied MCS and CQI-derived MCS from runtime rows.", x_labels, y_labels, matrix, [f"samples={len(raw_rows)}"], "Derived MCS", "Selected MCS"),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_heatmap_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(matrix_rows),
                        "note": "Selected-versus-derived MCS matrix derived from runtime link-adaptation rows.",
                    }
            if chart_name == "quality-vs-selected-MCS mismatch plot":
                pairs = [(float(quality), float(mcs)) for row in la_rows for quality, mcs in [(_row_float(row, "PostEqSINR_dB", "MeasuredTrialSINR_dB", "MeasuredSINR_dB"), _row_float(row, "MCSIndex"))] if quality is not None and mcs is not None]
                if pairs:
                    csv_bytes, dataset = _metric_rows_by_exact_x(pairs, x_label="MeasuredQuality_dB", y_label="SelectedMCS", chart_name=chart_name, run_id=run_id, source_path=la_path)
                    return {
                        "csv_bytes": csv_bytes,
                        "img_bytes": _render_svg_plot(chart_name, "Quality-to-selected-MCS trend from runtime adaptation rows.", dataset, [f"samples={len(pairs)}"]),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(pairs),
                        "note": "Mismatch/trend plot derived only from measured trial SINR and selected MCS; proxy, configured, and large-scale SINR values are not used as chart fallbacks.",
                    }
            if chart_name in {"per-beam quality plot", "per-layer quality plot"}:
                field_name = "BeamIndex" if chart_name == "per-beam quality plot" else "LayerIndex"
                grouped: dict[int, list[float]] = defaultdict(list)
                for row in la_rows:
                    if chart_name == "per-layer quality plot":
                        vector_values = _parse_float_vector(
                            _row_value(row, "PostEqSINRPerLayer_dB", "PerLayerSINR_dB", "LayerSINR_dB", "MeasuredPerLayerSINR_dB")
                        )
                        if vector_values:
                            for layer_idx, quality in enumerate(vector_values, start=1):
                                grouped[layer_idx].append(float(quality))
                            continue
                        group_value = _row_float(row, "LayerIndex")
                    else:
                        group_value = _row_float(row, field_name, "SelectedBeamIndex")
                    quality = _row_float(row, "PostEqSINR_dB", "MeasuredTrialSINR_dB", "MeasuredSINR_dB")
                    if group_value is None or quality is None:
                        continue
                    grouped[int(round(group_value))].append(float(quality))
                named_values = [(str(name), sum(values) / len(values)) for name, values in sorted(grouped.items()) if values]
                if named_values:
                    dataset, summary = _bar_dataset_from_named_values("Bucket", "Mean quality (dB)", named_values[:16])
                    csv_rows = [{"run_id": run_id, "chart_name": chart_name, "bucket_name": name, "mean_quality_db": value, "source_table_logical_path": la_path} for name, value in named_values[:16]]
                    return {
                        "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "bucket_name", "mean_quality_db", "source_table_logical_path"], csv_rows),
                        "img_bytes": _render_svg_plot(chart_name, "Mean quality grouped by exported beam or layer identifier.", dataset, summary),
                        "csv_status": "specialized_runtime_measurement_dataset",
                        "image_status": "generated_specialized_runtime_summary_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(csv_rows),
                        "note": "Grouped quality chart derived from measured trial SINR plus runtime beam identifiers or explicit per-layer SINR vectors; proxy, configured, large-scale SINR, and rank-as-layer substitutes are not used.",
                    }
                if chart_name == "per-layer quality plot":
                    reason = "No explicit LayerIndex or per-layer SINR vector was exported. Rank/Layers is not a per-layer quality measurement, so the chart is unavailable."
                    return {
                        "csv_bytes": _encode_csv(["run_id", "chart_name", "status", "reason", "checked_source"], [[run_id, chart_name, "unavailable_exact_reason", reason, la_path]]),
                        "img_bytes": _render_reason_svg(chart_name, "Per-layer quality requires layer-indexed runtime receiver evidence.", [reason]),
                        "csv_status": "unavailable_exact_reason",
                        "image_status": "generated_unavailable_reason_svg",
                        "source_table_path": la_path,
                        "source_row_count": len(la_rows),
                        "note": reason,
                    }
    if chart_name in {"BS/sector/UE topology scatter plot", "serving cell map"}:
        site_path, site_rows = _first_available_rows(existing, fetch_artifact_bytes, ["reports/csv/sites.csv"])
        ue_path, ue_rows = _first_available_rows(existing, fetch_artifact_bytes, ["reports/csv/live_rsrp_serving_trace.csv", "reports/csv/live_ue_table.csv"])
        if site_rows or ue_rows:
            use_geo = any(_row_float(row, "Lon") is not None and _row_float(row, "Lat") is not None for row in ue_rows[:8] + site_rows[:8])
            x_names = ("Lon", "X_m") if use_geo else ("X_m", "Lon")
            y_names = ("Lat", "Y_m") if use_geo else ("Y_m", "Lat")
            x_label = "Longitude" if use_geo else "X (m)"
            y_label = "Latitude" if use_geo else "Y (m)"
            series: list[dict[str, Any]] = []
            csv_rows: list[dict[str, Any]] = []
            site_points: list[list[float]] = []
            for row in site_rows:
                x_val = _row_float(row, *x_names)
                y_val = _row_float(row, *y_names)
                if x_val is None or y_val is None:
                    continue
                site_points.append([float(x_val), float(y_val)])
                csv_rows.append({
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "series_name": "Sites",
                    "x_value": x_val,
                    "y_value": y_val,
                    "label": _row_text(row, "SiteID", "MapAnchorLabel"),
                    "source_table_logical_path": site_path,
                })
            if site_points:
                series.append({"name": "Sites", "points": site_points[:32]})
            latest_ue: dict[str, dict[str, str]] = {}
            for row in ue_rows:
                ue_key = _row_text(row, "UEID", "UEIndex", "RNTI")
                if ue_key:
                    latest_ue[ue_key] = row
            if chart_name == "BS/sector/UE topology scatter plot":
                ue_points: list[list[float]] = []
                for row in latest_ue.values():
                    x_val = _row_float(row, *x_names)
                    y_val = _row_float(row, *y_names)
                    if x_val is None or y_val is None:
                        continue
                    ue_points.append([float(x_val), float(y_val)])
                    csv_rows.append({
                        "run_id": run_id,
                        "chart_name": chart_name,
                        "series_name": "UEs",
                        "x_value": x_val,
                        "y_value": y_val,
                        "label": _row_text(row, "UEID", "UEIndex"),
                        "source_table_logical_path": ue_path,
                    })
                if ue_points:
                    series.append({"name": "UEs", "points": _downsample_points(ue_points, 220), "color": "#2563eb"})
            else:
                grouped_points: dict[str, list[list[float]]] = defaultdict(list)
                for row in latest_ue.values():
                    x_val = _row_float(row, *x_names)
                    y_val = _row_float(row, *y_names)
                    if x_val is None or y_val is None:
                        continue
                    cell_name = _row_text(row, "ServingCell", "ServingSector", "ServingSite") or "Unknown cell"
                    grouped_points[cell_name].append([float(x_val), float(y_val)])
                    csv_rows.append({
                        "run_id": run_id,
                        "chart_name": chart_name,
                        "series_name": cell_name,
                        "x_value": x_val,
                        "y_value": y_val,
                        "label": _row_text(row, "UEID", "UEIndex"),
                        "source_table_logical_path": ue_path,
                    })
                for idx, (cell_name, points) in enumerate(sorted(grouped_points.items())[:8]):
                    series.append({"name": f"Cell {cell_name}", "points": _downsample_points(points, 70)})
            if series:
                summary = [
                    f"sites={len(site_points)}",
                    f"ue_points={max(0, len(csv_rows) - len(site_points))}",
                    f"coordinate_mode={'geo' if use_geo else 'projected'}",
                ]
                return {
                    "csv_bytes": _encode_dict_rows(
                        ["run_id", "chart_name", "series_name", "x_value", "y_value", "label", "source_table_logical_path"],
                        csv_rows,
                    ),
                    "img_bytes": _render_multi_series_svg(
                        chart_name,
                        "Topology and serving-cell placement derived from persisted runtime geometry and measurement rows.",
                        series,
                        summary,
                        x_label=x_label,
                        y_label=y_label,
                        mode="scatter",
                    ),
                    "csv_status": "specialized_runtime_geometry_dataset",
                    "image_status": "generated_specialized_runtime_summary_svg",
                    "source_table_path": "|".join(path for path in [site_path, ue_path] if path),
                    "source_row_count": len(csv_rows),
                    "note": "Scatter/map view derived from persisted site geometry and UE placement rows.",
                }
    if chart_name == "requested vs resolved format confusion matrix":
        pucch_path, pucch_rows = _first_available_rows(existing, fetch_artifact_bytes, ["air_interface/csv/pucch_trials.csv"])
        if pucch_rows:
            raw_rows: list[dict[str, Any]] = []
            csv_rows: list[dict[str, Any]] = []
            for row in pucch_rows:
                requested = _row_float(row, "RequestedFormat")
                resolved = _row_text(row, "ResolvedFormat")
                if requested is None or not resolved:
                    continue
                raw_rows.append({"requested_format": int(round(requested)), "resolved_format": resolved, "count": 1.0})
                csv_rows.append({
                    "run_id": run_id,
                    "chart_name": chart_name,
                    "requested_format": int(round(requested)),
                    "resolved_format": resolved,
                    "count": 1,
                    "source_table_logical_path": pucch_path,
                })
            if raw_rows:
                x_labels, y_labels, matrix = _grid_rows_to_heatmap(raw_rows, "requested_format", "resolved_format", "count")
                return {
                    "csv_bytes": _encode_dict_rows(
                        ["run_id", "chart_name", "requested_format", "resolved_format", "count", "source_table_logical_path"],
                        csv_rows,
                    ),
                    "img_bytes": _render_heatmap_svg(
                        chart_name,
                        "Requested-vs-resolved PUCCH format usage from persisted runtime trials.",
                        x_labels,
                        y_labels,
                        matrix,
                        [
                            f"samples={len(raw_rows)}",
                            "A singleton matrix is the exact observed PUCCH format population; no absent format categories are synthesized.",
                        ],
                        "Requested format",
                        "Resolved format",
                        allow_singleton_observation=True,
                    ),
                    "csv_status": "specialized_runtime_pucch_dataset",
                    "image_status": "generated_specialized_runtime_heatmap_svg",
                    "source_table_path": pucch_path,
                    "source_row_count": len(csv_rows),
                    "note": "PUCCH format confusion matrix derived from truthful runtime trial rows.",
                }
    if chart_name in {"constellation per codeword", "constellation per layer"}:
        preview_sources = _all_available_rows(
            existing,
            fetch_artifact_bytes,
            ["air_interface/csv/dl_constellation_preview.csv", "air_interface/csv/ul_constellation_preview.csv", "reports/csv/equalized_constellations.csv"],
        )
        group_field = "CodewordIndex" if chart_name == "constellation per codeword" else "LayerIndex"
        panels: list[tuple[str, list[tuple[float, float, str]], list[tuple[float, float]]]] = []
        csv_rows: list[dict[str, Any]] = []
        grouped_points: dict[str, list[tuple[float, float, str]]] = defaultdict(list)
        grouped_ideal: dict[str, list[tuple[float, float]]] = defaultdict(list)
        for source_path, rows in preview_sources:
            default_direction = "DL" if "/dl_" in source_path else ("UL" if "/ul_" in source_path else "")
            for row in rows:
                group_value = _row_float(row, group_field)
                eq_r = _row_float(row, "EqualizedReal")
                eq_i = _row_float(row, "EqualizedImag")
                if group_value is None or eq_r is None or eq_i is None:
                    continue
                direction = _row_text(row, "Direction") or default_direction
                group_name = f"{direction or 'link'} {group_field} {int(round(group_value))}"
                grouped_points[group_name].append((float(eq_r), float(eq_i), direction or "link"))
                ref_r = _row_float(row, "ReferenceSymbolReal")
                ref_i = _row_float(row, "ReferenceSymbolImag")
                if ref_r is not None and ref_i is not None:
                    grouped_ideal[group_name].append((float(ref_r), float(ref_i)))
                csv_rows.append(
                    {
                        "run_id": run_id,
                        "chart_name": chart_name,
                        "direction": direction,
                        group_field: int(round(group_value)),
                        "EqualizedReal": eq_r,
                        "EqualizedImag": eq_i,
                        "ReferenceSymbolReal": ref_r if ref_r is not None else "",
                        "ReferenceSymbolImag": ref_i if ref_i is not None else "",
                        "source_table_logical_path": source_path,
                    }
                )
        for group_name, points in list(grouped_points.items())[:8]:
            panels.append((group_name, points[:450], grouped_ideal.get(group_name, [])[:64]))
        if panels:
            return {
                "csv_bytes": _encode_dict_rows(["run_id", "chart_name", "direction", group_field, "EqualizedReal", "EqualizedImag", "ReferenceSymbolReal", "ReferenceSymbolImag", "source_table_logical_path"], csv_rows),
                "img_bytes": _render_scatter_panels_svg(chart_name, "Equalized constellation samples grouped by runtime RE-mapped codeword/layer coordinates.", panels, [f"samples={len(csv_rows)}"]),
                "csv_status": "specialized_runtime_constellation_dataset",
                "image_status": "generated_specialized_runtime_constellation_svg",
                "source_table_path": "|".join(source_path for source_path, _rows in preview_sources),
                "source_row_count": len(csv_rows),
                "note": "Constellation grouping uses codeword/layer coordinates exported by the PHY runtime preview.",
            }
    if chart_name in {"EVM per symbol", "PDSCH EVM per symbol", "PUSCH EVM per symbol", "EVM per subcarrier", "EVM per layer"}:
        evm_chart = _runtime_evm_profile_chart(chart_name, existing, fetch_artifact_bytes, run_id)
        if evm_chart is not None:
            return evm_chart
    unavailable_reasons = {
        "pre-equalization constellation": "The run does not export raw pre-equalization I/Q sample clouds, so a pre-equalization constellation plot cannot be reconstructed honestly.",
        "pre-channel waveform": "The run does not export stage-resolved pre-channel sample traces, so this stage-specific waveform view cannot be reconstructed honestly.",
        "post-channel waveform": "The run does not export stage-resolved post-channel sample traces, so this stage-specific waveform view cannot be reconstructed honestly.",
        "post-impairment waveform": "The run does not export stage-resolved post-impairment sample traces, so this stage-specific waveform view cannot be reconstructed honestly.",
        "stage overlay plots": "The run does not export enough stage-resolved sample traces to build an honest overlay of internal waveform stages.",
        "UE-wise / link-wise waveform comparison": "The run exports a single runtime waveform preview, not a full UE-by-UE waveform sample bank suitable for an honest comparison chart.",
        "constellation per codeword": "No codeword identifier is exported in the runtime constellation preview rows for this run.",
        "constellation per layer": "No per-layer equalized constellation samples are exported in the runtime preview rows for this run.",
        "EVM per symbol": "No complete finite paired-sample evidence with UE/frame/slot/layer/codeword and OFDM-symbol coordinates is available; scalar EVM cannot recover energy sums or peaks.",
        "PDSCH EVM per symbol": "No complete DL paired-sample evidence with UE/frame/slot/layer/codeword and OFDM-symbol coordinates is available.",
        "PUSCH EVM per symbol": "No complete UL paired-sample evidence with UE/frame/slot/layer/codeword and OFDM-symbol coordinates is available.",
        "EVM per subcarrier": "The run does not export subcarrier-indexed equalized/reference preview rows.",
        "EVM per layer": "The run does not export layer-indexed equalized/reference preview rows.",
    }
    if chart_name in unavailable_reasons:
        reason = unavailable_reasons[chart_name]
        csv_bytes = _encode_csv(
            ["run_id", "chart_name", "status", "reason", "checked_sources"],
            [[run_id, chart_name, "unavailable_exact_reason", reason, "air_interface/csv/dl_constellation_preview.csv|air_interface/csv/ul_constellation_preview.csv|air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv"]],
        )
        return {
            "csv_bytes": csv_bytes,
            "img_bytes": _render_reason_svg(chart_name, "The browser is preserving honesty for this chart family.", [reason, "No synthetic per-layer/per-codeword/per-symbol/per-subcarrier values were generated."]),
            "csv_status": "unavailable_exact_reason",
            "image_status": "generated_unavailable_reason_svg",
            "source_table_path": "air_interface/csv/dl_constellation_preview.csv|air_interface/csv/ul_constellation_preview.csv|air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv",
            "source_row_count": 0,
            "note": reason,
        }
    return None


def _windows_long_path(path: Path) -> Path:
    """Return an extended-length absolute path for Windows file I/O."""
    absolute = str(path.absolute())
    if os.name != "nt" or absolute.startswith("\\\\?\\"):
        return Path(absolute)
    if absolute.startswith("\\\\"):
        return Path("\\\\?\\UNC\\" + absolute[2:])
    return Path("\\\\?\\" + absolute)


def _write_file_if_possible(run_folder: str | None, logical_path: str, data: bytes) -> None:
    root = str(run_folder or "").strip()
    if not root:
        return
    target = Path(root) / Path(*str(logical_path).split("/"))
    io_target = _windows_long_path(target)
    try:
        io_target.parent.mkdir(parents=True, exist_ok=True)
        io_target.write_bytes(data)
    except OSError as exc:
        raise OSError(
            f"Cannot persist browser contract artifact {logical_path!r} "
            f"under {root!r}: {exc}"
        ) from exc


def _remove_materializer_owned_file(run_folder: str | None, logical_path: str) -> None:
    """Remove only a previously indexed contract__ output below one run.

    Source/runtime evidence is never eligible.  This prevents a contract
    version change from leaving an old chart on disk with no lineage row in
    the new manifest.
    """

    root_text = str(run_folder or "").strip()
    normalized = str(logical_path or "").replace("\\", "/").strip("/")
    if not root_text or "/contract__" not in f"/{normalized}" or ".." in Path(normalized).parts:
        return
    root = Path(root_text).resolve()
    target = (root / Path(*normalized.split("/"))).resolve()
    try:
        target.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"Contract cleanup escaped the run folder: {logical_path}") from exc
    io_target = _windows_long_path(target)
    if io_target.is_file():
        io_target.unlink()


def _store_artifact(
    db_connection_factory: Callable[[], Any],
    run_id: int,
    logical_path: str,
    artifact_kind: str,
    mime_type: str,
    data: bytes,
    metadata: dict[str, Any],
) -> int:
    payload = json.dumps(metadata, ensure_ascii=False, default=str)
    with db_connection_factory() as conn:
        with conn.cursor(buffered=True) as cur:
            cur.execute(
                "SELECT artifact_id FROM sim_artifacts WHERE run_id=%s AND logical_path=%s",
                (run_id, logical_path),
            )
            rows = cur.fetchall()
            for row in rows:
                artifact_id = int(row[0] if isinstance(row, (tuple, list)) else row.get("artifact_id"))
                cur.execute("DELETE FROM sim_artifact_chunks WHERE artifact_id=%s", (artifact_id,))
                cur.execute("DELETE FROM sim_artifacts WHERE artifact_id=%s", (artifact_id,))
            cur.execute(
                """
                INSERT INTO sim_artifacts
                (run_id, logical_path, artifact_kind, mime_type, byte_size, metadata_json, created_utc)
                VALUES (%s, %s, %s, %s, %s, %s, UTC_TIMESTAMP())
                """,
                (run_id, logical_path, artifact_kind, mime_type, len(data), payload),
            )
            artifact_id = int(cur.lastrowid)
            chunk_size = 512 * 1024
            for chunk_index, start in enumerate(range(0, len(data), chunk_size), start=1):
                cur.execute(
                    """
                    INSERT INTO sim_artifact_chunks (artifact_id, chunk_index, chunk_data)
                    VALUES (%s, %s, %s)
                    """,
                    (artifact_id, chunk_index, data[start : start + chunk_size]),
                )
        conn.commit()
    return artifact_id


def _table_specs() -> list[dict[str, Any]]:
    return output_contract.iter_table_specs("reports") + output_contract.iter_table_specs("analytics")


def _chart_specs() -> list[dict[str, Any]]:
    return output_contract.iter_chart_specs("reports") + output_contract.iter_chart_specs("analytics")


def _table_sources(table_name: str) -> list[str]:
    return list(CONTRACT_TABLE_ALIAS_PATHS.get(str(table_name or "").strip(), []))


def _chart_sources(chart_name: str) -> list[str]:
    return list(CONTRACT_CHART_ALIAS_PATHS.get(str(chart_name or "").strip(), []))


def _artifact_metadata_json(
    artifact: dict[str, Any] | None,
    db_connection_factory: Callable[[], Any],
) -> str:
    if not artifact:
        return ""
    inline = str(artifact.get("metadata_json") or "").strip()
    if inline:
        return inline
    artifact_id = int(artifact.get("artifact_id") or 0)
    if artifact_id <= 0:
        return ""
    with db_connection_factory() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT metadata_json FROM sim_artifacts WHERE artifact_id=%s", (artifact_id,))
            row = cur.fetchone()
    if row is None:
        return ""
    return str(row[0] if isinstance(row, (tuple, list)) else row.get("metadata_json") or "").strip()


def _fetch_run_artifacts(
    run_id: int,
    db_connection_factory: Callable[[], Any],
) -> list[dict[str, Any]]:
    with db_connection_factory() as conn:
        with conn.cursor(dictionary=True) as cur:
            cur.execute(
                """
                SELECT artifact_id, run_id, logical_path, artifact_kind, mime_type,
                       byte_size, created_utc
                FROM sim_artifacts
                WHERE run_id = %s
                ORDER BY artifact_id ASC
                """,
                (run_id,),
            )
            return [dict(row or {}) for row in cur.fetchall()]


@contextmanager
def _materialization_lock(
    run_id: int,
    db_connection_factory: Callable[[], Any],
    timeout_seconds: int,
):
    lock_name = f"sixgr_contract_materialize_run_{int(run_id)}"
    acquired = False
    conn = db_connection_factory()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT GET_LOCK(%s, %s)", (lock_name, max(0, int(timeout_seconds))))
            row = cur.fetchone()
            acquired = bool(row) and int((row[0] if isinstance(row, (tuple, list)) else row.get("GET_LOCK(%s, %s)")) or 0) == 1
        yield acquired
    finally:
        if acquired:
            try:
                with conn.cursor() as cur:
                    cur.execute("SELECT RELEASE_LOCK(%s)", (lock_name,))
                    cur.fetchone()
            except Exception:
                pass
        try:
            conn.close()
        except Exception:
            pass


def _artifact_has_current_materializer_version(
    artifact: dict[str, Any] | None,
    db_connection_factory: Callable[[], Any],
) -> bool:
    payload = _artifact_metadata_json(artifact, db_connection_factory)
    return bool(payload) and payload.find(MATERIALIZER_VERSION) >= 0


def _existing_contract_artifacts_current(
    existing: dict[str, dict[str, Any]],
    db_connection_factory: Callable[[], Any],
    feature_policy: dict[str, bool] | None = None,
) -> bool:
    feature_policy = dict(feature_policy or {})
    for table_spec in _table_specs():
        table_name = str(table_spec.get("table_name") or "")
        if contract_artifact_is_policy_filtered(
            table_contract_path(table_spec), feature_policy, contract_name=table_name
        ):
            continue
        artifact = existing.get(table_contract_path(table_spec))
        if artifact is None or not _artifact_has_current_materializer_version(artifact, db_connection_factory):
            return False
    for chart_spec in _chart_specs():
        chart_name = str(chart_spec.get("chart_name") or "")
        if contract_artifact_is_policy_filtered(
            chart_contract_csv_path(chart_spec), feature_policy, contract_name=chart_name
        ):
            continue
        csv_artifact = existing.get(chart_contract_csv_path(chart_spec))
        image_artifact = existing.get(chart_contract_image_path(chart_spec))
        if csv_artifact is None or image_artifact is None:
            return False
        if not _artifact_has_current_materializer_version(csv_artifact, db_connection_factory):
            return False
        if not _artifact_has_current_materializer_version(image_artifact, db_connection_factory):
            return False
    return True


def coverage_summary(
    artifacts: list[dict[str, Any]],
    feature_policy: dict[str, bool] | None = None,
) -> dict[str, Any]:
    feature_policy = dict(feature_policy or {})
    logical_paths = {str(art.get("logical_path") or "").strip() for art in artifacts if str(art.get("logical_path") or "").strip()}
    table_specs = _table_specs()
    chart_specs = _chart_specs()
    missing_tables: list[str] = []
    missing_charts: list[str] = []
    policy_disabled_tables = 0
    policy_disabled_charts = 0
    for table_spec in table_specs:
        table_name = str(table_spec.get("table_name") or "")
        target_path = table_contract_path(table_spec)
        if contract_artifact_is_policy_filtered(
            target_path, feature_policy, contract_name=table_name
        ):
            policy_disabled_tables += 1
            continue
        if target_path not in logical_paths:
            missing_tables.append(target_path)
    for chart_spec in chart_specs:
        chart_name = str(chart_spec.get("chart_name") or "")
        csv_path = chart_contract_csv_path(chart_spec)
        if contract_artifact_is_policy_filtered(
            csv_path, feature_policy, contract_name=chart_name
        ):
            policy_disabled_charts += 1
            continue
        img_path = chart_contract_image_path(chart_spec)
        if csv_path not in logical_paths or img_path not in logical_paths:
            missing_charts.append(chart_name)
    return {
        "tables_total": len(table_specs),
        "tables_policy_disabled": policy_disabled_tables,
        "tables_available": len(table_specs) - policy_disabled_tables - len(missing_tables),
        "charts_total": len(chart_specs),
        "charts_policy_disabled": policy_disabled_charts,
        "charts_available": len(chart_specs) - policy_disabled_charts - len(missing_charts),
        "missing_table_paths": missing_tables,
        "missing_chart_names": missing_charts,
    }


def materialize_run_contract_artifacts(
    run_row: dict[str, Any],
    artifacts: list[dict[str, Any]],
    *,
    fetch_artifact_bytes: Callable[[int], bytes],
    db_connection_factory: Callable[[], Any] | None,
    feature_policy: dict[str, bool] | None = None,
    force: bool = False,
    lock_timeout_seconds: int = 0,
    filesystem_only: bool = False,
) -> dict[str, Any]:
    run_id = int(run_row.get("run_id") or 0)
    run_folder = str(run_row.get("run_folder") or "")
    created: list[dict[str, Any]] = []
    manifest_rows: list[list[Any]] = []
    plot_lineage_rows: list[list[Any]] = []
    feature_policy = dict(feature_policy or {})
    allow_placeholder_artifacts = _run_allows_placeholder_artifacts(run_row)
    filesystem_payloads: dict[int, bytes] = {}
    next_filesystem_artifact_id = max(
        (int(artifact.get("artifact_id") or 0) for artifact in artifacts),
        default=0,
    ) + 1
    source_fetch_artifact_bytes = fetch_artifact_bytes

    def effective_fetch_artifact_bytes(artifact_id: int) -> bytes:
        artifact_id = int(artifact_id)
        if artifact_id in filesystem_payloads:
            return filesystem_payloads[artifact_id]
        return bytes(source_fetch_artifact_bytes(artifact_id))

    def persist_artifact(
        logical_path: str,
        artifact_kind: str,
        mime_type: str,
        data: bytes,
        metadata: dict[str, Any],
    ) -> int:
        nonlocal next_filesystem_artifact_id
        if not filesystem_only:
            if db_connection_factory is None:
                raise RuntimeError("A database connection factory is required for database materialization.")
            return _store_artifact(
                db_connection_factory,
                run_id,
                logical_path,
                artifact_kind,
                mime_type,
                data,
                metadata,
            )
        artifact_id = next_filesystem_artifact_id
        next_filesystem_artifact_id += 1
        filesystem_payloads[artifact_id] = bytes(data)
        return artifact_id

    # Rebind locally so every downstream source-table/chart helper can read
    # artifacts created earlier in this same filesystem transaction.
    fetch_artifact_bytes = effective_fetch_artifact_bytes
    lock_context = (
        nullcontext(True)
        if filesystem_only
        else _materialization_lock(
            run_id,
            db_connection_factory,
            int(lock_timeout_seconds),
        )
    )
    with lock_context as lock_acquired:
        if not lock_acquired:
            return {
                "created": created,
                "manifest_path": manifest_logical_path(),
                "coverage_path": coverage_logical_path(),
                "coverage": coverage_summary(artifacts, feature_policy),
                "skipped": True,
                "lock_busy": True,
            }
        if filesystem_only:
            artifacts = [dict(artifact or {}) for artifact in artifacts]
        else:
            if db_connection_factory is None:
                raise RuntimeError("A database connection factory is required for database materialization.")
            artifacts = _fetch_run_artifacts(run_id, db_connection_factory)
        existing = {str(art.get("logical_path") or ""): art for art in artifacts}
        source_lookup = dict(existing)
        contract_owned_paths = _contract_owned_paths(artifacts, db_connection_factory)

        manifest_art = existing.get(manifest_logical_path())
        manifest_meta_json = _artifact_metadata_json(manifest_art, db_connection_factory)
        try:
            manifest_meta = json.loads(manifest_meta_json) if manifest_meta_json else {}
        except Exception:
            manifest_meta = {}
        run_status = str(run_row.get("status_text") or "").strip().lower()
        current_source_watermark = _source_artifact_high_watermark(artifacts, db_connection_factory)
        manifest_current = (
            manifest_art
            and manifest_meta_json.find(MATERIALIZER_VERSION) >= 0
            and int(manifest_meta.get("source_artifact_high_watermark") or 0) >= current_source_watermark
        )
        coverage_art = existing.get(coverage_logical_path())
        coverage_meta_json = _artifact_metadata_json(coverage_art, db_connection_factory)
        coverage_current = bool(coverage_art) and coverage_meta_json.find(MATERIALIZER_VERSION) >= 0
        coverage_snapshot = coverage_summary(list(existing.values()), feature_policy)
        if manifest_current and coverage_current and not force:
            return {
                "created": created,
                "manifest_path": manifest_logical_path(),
                "coverage_path": coverage_logical_path(),
                "coverage": coverage_snapshot,
                "skipped": True,
            }
        if manifest_art is not None:
            if filesystem_only:
                for path in sorted(contract_owned_paths):
                    _remove_materializer_owned_file(run_folder, path)
            for path in list(contract_owned_paths):
                existing.pop(path, None)
            source_lookup = dict(existing)

        if force:
            # Filesystem indexing has no artifact metadata, so materialized
            # report/analytics aliases cannot be recognized by
            # ``_artifact_is_contract_owned``.  A forced terminal refresh
            # must nevertheless rebuild every derived table from its final
            # canonical source.  Preserve only a target that is explicitly
            # one of its own runtime-source aliases; those are producer-owned
            # primary tables and must never be replaced by the browser.
            for table_spec in _table_specs():
                table_name = str(table_spec.get("table_name") or "")
                target_path = table_contract_path(table_spec)
                if not target_path or target_path in _table_sources(table_name):
                    continue
                existing.pop(target_path, None)
                source_lookup.pop(target_path, None)

        for table_spec in _table_specs():
            table_name = str(table_spec.get("table_name") or "")
            target_path = table_contract_path(table_spec)
            if contract_artifact_is_policy_filtered(
                target_path, feature_policy, contract_name=table_name
            ):
                continue
            if not target_path or target_path in existing:
                continue
            source_art = None
            special = _specialized_table_materialization(
                table_name,
                source_lookup,
                fetch_artifact_bytes,
                run_id,
                str(table_spec.get("section_title") or ""),
                run_row=run_row,
                feature_policy=feature_policy,
            )
            if special is not None:
                data = bytes(special["data"])
                status = str(special.get("status") or "specialized_runtime_table")
                note = str(special.get("note") or "")
                source_row_count = int(special.get("source_row_count") or 0)
                source_logical_path = str(special.get("source_logical_path") or "")
            else:
                source_paths = _table_sources(table_name)
                source_art, source_data, header, rows = _select_source_table_artifact(source_paths, source_lookup, fetch_artifact_bytes)
                source_logical_path = str(source_art.get("logical_path") or "") if source_art else ""
                if source_art and str(source_art.get("artifact_kind") or "") == "table_csv":
                    if rows:
                        data = source_data
                        status = "copied_source_table"
                        note = f"Canonical contract table copied from {source_art['logical_path']}."
                        source_row_count = len(rows)
                    else:
                        header, summary_rows = _summary_csv_rows(
                            run_id,
                            str(table_spec.get("section_title") or ""),
                            table_name,
                            "source_artifact_present_but_empty",
                            source_logical_path,
                            0,
                            "The source artifact exists for this run, but it has no real rows.",
                        )
                        data = _encode_csv(header, summary_rows)
                        status = "empty_source_summary"
                        note = "Canonical contract table summarizes an empty source artifact."
                        source_row_count = 0
                else:
                    header, summary_rows = _summary_csv_rows(
                        run_id,
                        str(table_spec.get("section_title") or ""),
                        table_name,
                        "source_artifact_missing",
                        "",
                        0,
                        "No direct aliased source artifact was published for this run, so this contract table records the absence explicitly.",
                    )
                    data = _encode_csv(header, summary_rows)
                    status = "missing_source_summary"
                    note = "Canonical contract table records missing source evidence."
                    source_row_count = 0
            metadata = {
                "materializer_version": MATERIALIZER_VERSION,
                "contract_table": table_name,
                "section_slug": table_spec.get("section_slug"),
                "source_logical_path": source_logical_path,
                "source_row_count": source_row_count,
                "materialization_status": status,
            }
            if not allow_placeholder_artifacts and _is_placeholder_materialization_status(status):
                manifest_rows.append([target_path, "table_csv", "suppressed_placeholder_artifact", source_logical_path, note])
                continue
            _write_file_if_possible(run_folder, target_path, data)
            artifact_id = persist_artifact(
                target_path,
                "table_csv",
                "text/csv; charset=UTF-8",
                data,
                metadata,
            )
            created.append({"logical_path": target_path, "artifact_id": artifact_id, "status": status})
            manifest_rows.append([target_path, "table_csv", status, metadata.get("source_logical_path", ""), note])
            new_artifact = {
                "artifact_id": artifact_id,
                "logical_path": target_path,
                "artifact_kind": "table_csv",
                "mime_type": "text/csv; charset=UTF-8",
            }
            existing[target_path] = new_artifact
            source_lookup[target_path] = new_artifact

        for chart_spec in _chart_specs():
            chart_name = str(chart_spec.get("chart_name") or "")
            target_csv = chart_contract_csv_path(chart_spec)
            if contract_artifact_is_policy_filtered(
                target_csv, feature_policy, contract_name=chart_name
            ):
                continue
            target_img = chart_contract_image_path(chart_spec)
            if target_csv in existing and target_img in existing:
                plot_lineage_rows.append(
                    _contract_plot_lineage_row(
                        f"contract__{chart_spec.get('section_slug') or 'section'}__{slugify(chart_name)}",
                        target_img,
                        target_csv,
                        fetch_artifact_bytes(int(existing[target_img]["artifact_id"])),
                        fetch_artifact_bytes(int(existing[target_csv]["artifact_id"])),
                    )
                )
                continue
            special = _finalize_chart_materialization_result(
                _specialized_chart_materialization(chart_name, source_lookup, fetch_artifact_bytes, run_id)
            )
            if special is not None:
                chart_csv_bytes = bytes(special["csv_bytes"])
                image_bytes = _rasterize_contract_png(
                    bytes(special["img_bytes"]),
                    source_mime_type="image/svg+xml",
                    source_logical_path=f"internal://specialized/{slugify(chart_name)}.vector",
                )
                csv_status = str(special.get("csv_status") or "specialized_contract_dataset")
                image_status = str(special.get("image_status") or "generated_specialized_contract_image").replace("_svg", "_png")
                low_information_reason = ""
                if not bool(special.get("uniform_runtime_evidence_is_valid", False)):
                    low_information_reason = _png_low_information_reason(image_bytes)
                if low_information_reason:
                    image_status = "generated_low_information_reason_png"
                source_table_path = str(special.get("source_table_path") or "")
                source_mapping_status = str(special.get("source_mapping_status") or _source_mapping_status_for_status(csv_status, image_status))
                source_row_count = int(special.get("source_row_count") or 0)
                chart_csv_note = str(special.get("note") or "")
                image_kind = "image_png"
                image_mime = "image/png"
                source_image = None
                source_table = source_lookup.get(source_table_path)
                csv_meta = {
                    "materializer_version": MATERIALIZER_VERSION,
                    "chart_name": chart_name,
                    "section_slug": chart_spec.get("section_slug"),
                    "source_table_logical_path": source_table_path,
                    "source_row_count": source_row_count,
                    "materialization_status": csv_status,
                    "source_mapping_status": source_mapping_status,
                }
                img_meta = {
                    "materializer_version": MATERIALIZER_VERSION,
                    "chart_name": chart_name,
                    "section_slug": chart_spec.get("section_slug"),
                    "source_image_logical_path": "",
                    "source_table_logical_path": source_table_path,
                    "materialization_status": image_status,
                    "source_mapping_status": source_mapping_status,
                    "output_format": "png",
                }
                if (
                    not allow_placeholder_artifacts
                    and (
                        _is_placeholder_materialization_status(csv_status)
                        or _is_placeholder_materialization_status(image_status)
                    )
                ):
                    manifest_rows.append([target_csv, "table_csv", "suppressed_placeholder_artifact", source_table_path, chart_name])
                    manifest_rows.append([target_img, image_kind, "suppressed_placeholder_artifact", source_table_path, chart_name])
                    continue
                _write_file_if_possible(run_folder, target_csv, chart_csv_bytes)
                csv_artifact_id = persist_artifact(
                    target_csv,
                    "table_csv",
                    "text/csv; charset=UTF-8",
                    chart_csv_bytes,
                    csv_meta,
                )
                _write_file_if_possible(run_folder, target_img, image_bytes)
                img_artifact_id = persist_artifact(
                    target_img,
                    image_kind,
                    image_mime,
                    image_bytes,
                    img_meta,
                )
                created.append({"logical_path": target_csv, "artifact_id": csv_artifact_id, "status": csv_status})
                created.append({"logical_path": target_img, "artifact_id": img_artifact_id, "status": image_status})
                manifest_rows.append([target_csv, "table_csv", csv_status, source_table_path, chart_name])
                manifest_rows.append([target_img, image_kind, image_status, source_table_path, chart_name])
                plot_lineage_rows.append(
                    _contract_plot_lineage_row(
                        f"contract__{chart_spec.get('section_slug') or 'section'}__{slugify(chart_name)}",
                        target_img,
                        target_csv,
                        image_bytes,
                        chart_csv_bytes,
                    )
                )
                csv_artifact = {
                    "artifact_id": csv_artifact_id,
                    "logical_path": target_csv,
                    "artifact_kind": "table_csv",
                    "mime_type": "text/csv; charset=UTF-8",
                }
                img_artifact = {
                    "artifact_id": img_artifact_id,
                    "logical_path": target_img,
                    "artifact_kind": image_kind,
                    "mime_type": image_mime,
                }
                existing[target_csv] = csv_artifact
                existing[target_img] = img_artifact
                source_lookup[target_csv] = csv_artifact
                source_lookup[target_img] = img_artifact
                continue
            source_image = next(
                (
                    source_lookup[path]
                    for path in _chart_sources(chart_name)
                    if path in source_lookup and str(source_lookup[path].get("mime_type") or "").startswith("image/")
                ),
                None,
            )
            source_table = next(
                (
                    source_lookup[path]
                    for path in _chart_sources(chart_name)
                    if path in source_lookup and str(source_lookup[path].get("artifact_kind") or "") == "table_csv"
                ),
                None,
            )
            summary_lines = [
                f"chart={chart_name}",
                f"section={chart_spec.get('section_title') or ''}",
                f"kind={chart_spec.get('kind') or ''}",
                f"source_image={source_image.get('logical_path') if source_image else ''}",
                f"source_table={source_table.get('logical_path') if source_table else ''}",
            ]
            dataset = None
            chart_csv_bytes: bytes
            csv_status = "lineage_summary"
            source_table_path = str(source_table.get("logical_path") or "") if source_table else ""
            source_row_count = 0
            source_mapping_status = "unavailable"
            chart_csv_note = "No direct source table was published for this chart family in the selected run."
            if source_table:
                source_table_bytes = fetch_artifact_bytes(int(source_table["artifact_id"]))
                header, rows = _decode_csv(source_table_bytes)
                if rows:
                    source_row_count = len(rows)
                    summary_lines.append(f"source_rows={source_row_count}")
                    dict_rows = [{str(header[idx]): str(row[idx]) if idx < len(row) else "" for idx in range(len(header))} for row in rows]
                    placeholder_status = _table_placeholder_summary_status(dict_rows)
                    if placeholder_status in {"source_artifact_missing", "source_artifact_present_but_empty"}:
                        dataset = None
                        csv_status = placeholder_status
                        chart_csv_note = _row_text(dict_rows[0], "lineage_note", "reason") or (
                            "The aliased source table is itself a placeholder summary, so no truthful numeric chart was materialized."
                        )
                        summary_lines.append(f"placeholder_status={placeholder_status}")
                    else:
                        dataset, source_mapping_status, chart_csv_note = _dataset_from_exact_chart_contract(
                            chart_name,
                            source_table_path,
                            header,
                            rows,
                        )
                        csv_status = "derived_exact_chart_dataset" if source_mapping_status == "exact" else "invalid_source_mapping"
                        summary_lines.append(f"source_mapping_status={source_mapping_status}")
                else:
                    chart_csv_note = "The source chart table exists but has no rows for this run."
                    summary_lines.append("source_rows=0")
                    csv_status = "empty_source_summary"
            else:
                summary_lines.append("source_rows=0")
                csv_status = "missing_source_summary"
                if source_image:
                    source_mapping_status = "exact"
                    csv_status = "copied_source_image_lineage"
                    chart_csv_note = "A direct source image mapping exists; no numeric contract dataset was inferred."
            chart_csv_bytes = _chart_dataset_csv(
                run_id,
                chart_name,
                dataset,
                source_table_path,
                source_row_count,
                csv_status,
                chart_csv_note,
                source_mapping_status,
            )
            if source_image:
                source_image_mime = str(source_image.get("mime_type") or "")
                source_image_path = str(source_image.get("logical_path") or "")
                image_bytes = _rasterize_contract_png(
                    fetch_artifact_bytes(int(source_image["artifact_id"])),
                    source_mime_type=source_image_mime,
                    source_logical_path=source_image_path,
                )
                image_kind = "image_png"
                image_mime = "image/png"
                image_status = "rasterized_source_image_png"
            elif csv_status in {
                "source_artifact_missing",
                "source_artifact_present_but_empty",
                "empty_source_summary",
                "missing_source_summary",
                "invalid_source_mapping",
            }:
                image_bytes = _rasterize_contract_png(
                    _render_reason_svg(
                        chart_name,
                        "No truthful numeric chart was materialized from the selected source table for this run.",
                        summary_lines + [chart_csv_note],
                    ),
                    source_mime_type="image/svg+xml",
                    source_logical_path=f"internal://unavailable/{slugify(chart_name)}.vector",
                )
                image_kind = "image_png"
                image_mime = "image/png"
                image_status = "generated_unavailable_reason_png"
            else:
                image_bytes = _rasterize_contract_png(
                    _chart_image_from_dataset(
                        chart_name,
                        "Canonical post-run chart materialized from the selected run's persisted source artifacts.",
                        dataset,
                        summary_lines,
                    ),
                    source_mime_type="image/svg+xml",
                    source_logical_path=f"internal://contract/{slugify(chart_name)}.vector",
                )
                image_kind = "image_png"
                image_mime = "image/png"
                image_status = "generated_contract_summary_png"

            low_information_reason = _png_low_information_reason(image_bytes)
            if low_information_reason:
                image_status = "generated_low_information_reason_png"

            csv_meta = {
                "materializer_version": MATERIALIZER_VERSION,
                "chart_name": chart_name,
                "section_slug": chart_spec.get("section_slug"),
                "source_table_logical_path": source_table_path,
                "source_row_count": source_row_count,
                "materialization_status": csv_status,
                "source_mapping_status": source_mapping_status,
            }
            img_meta = {
                "materializer_version": MATERIALIZER_VERSION,
                "chart_name": chart_name,
                "section_slug": chart_spec.get("section_slug"),
                "source_image_logical_path": str(source_image.get("logical_path") or "") if source_image else "",
                "source_table_logical_path": str(source_table.get("logical_path") or "") if source_table else "",
                "materialization_status": image_status,
                "source_mapping_status": source_mapping_status,
                "source_image_mime_type": str(source_image.get("mime_type") or "") if source_image else "",
                "output_format": "png",
            }
            if (
                not allow_placeholder_artifacts
                and (
                    _is_placeholder_materialization_status(csv_status)
                    or _is_placeholder_materialization_status(image_status)
                )
            ):
                manifest_rows.append([target_csv, "table_csv", "suppressed_placeholder_artifact", source_table_path, chart_name])
                manifest_rows.append([target_img, image_kind, "suppressed_placeholder_artifact", source_table_path, chart_name])
                continue
            _write_file_if_possible(run_folder, target_csv, chart_csv_bytes)
            csv_artifact_id = persist_artifact(
                target_csv,
                "table_csv",
                "text/csv; charset=UTF-8",
                chart_csv_bytes,
                csv_meta,
            )
            _write_file_if_possible(run_folder, target_img, image_bytes)
            img_artifact_id = persist_artifact(
                target_img,
                image_kind,
                image_mime,
                image_bytes,
                img_meta,
            )
            created.append({"logical_path": target_csv, "artifact_id": csv_artifact_id, "status": csv_status})
            created.append({"logical_path": target_img, "artifact_id": img_artifact_id, "status": image_status})
            manifest_rows.append([target_csv, "table_csv", csv_status, csv_meta.get("source_table_logical_path", ""), chart_name])
            manifest_rows.append([target_img, image_kind, image_status, img_meta.get("source_image_logical_path", "") or img_meta.get("source_table_logical_path", ""), chart_name])
            plot_lineage_rows.append(
                _contract_plot_lineage_row(
                    f"contract__{chart_spec.get('section_slug') or 'section'}__{slugify(chart_name)}",
                    target_img,
                    target_csv,
                    image_bytes,
                    chart_csv_bytes,
                )
            )
            csv_artifact = {
                "artifact_id": csv_artifact_id,
                "logical_path": target_csv,
                "artifact_kind": "table_csv",
                "mime_type": "text/csv; charset=UTF-8",
            }
            img_artifact = {
                "artifact_id": img_artifact_id,
                "logical_path": target_img,
                "artifact_kind": image_kind,
                "mime_type": image_mime,
            }
            existing[target_csv] = csv_artifact
            existing[target_img] = img_artifact
            source_lookup[target_csv] = csv_artifact
            source_lookup[target_img] = img_artifact

    # The image audit is intrinsically a post-render artifact.  During a
    # filesystem replacement transaction every old raster is intentionally
    # absent while the table loop above runs, so attempting this audit there
    # can only produce a false "missing" result.  Revisit the exact contract
    # after every eligible chart has been rendered and registered in the
    # transaction-local source lookup.  The resulting table is computed from
    # the actual PNG bytes; it is neither a placeholder nor configured-value
    # evidence.
    late_image_audit_name = "all_image_artifact_audit"
    late_image_audit_spec = next(
        (
            spec
            for spec in _table_specs()
            if str(spec.get("table_name") or "") == late_image_audit_name
        ),
        None,
    )
    if late_image_audit_spec is not None:
        late_image_audit_path = table_contract_path(late_image_audit_spec)
        late_image_audit_filtered = contract_artifact_is_policy_filtered(
            late_image_audit_path,
            feature_policy,
            contract_name=late_image_audit_name,
        )
        if late_image_audit_path and not late_image_audit_filtered:
            late_image_audit = _db_artifact_audit_table(
                late_image_audit_name,
                source_lookup,
                fetch_artifact_bytes,
                run_id,
            )
            if late_image_audit is not None:
                late_image_audit_data = bytes(late_image_audit["data"])
                late_image_audit_status = str(
                    late_image_audit.get("status")
                    or "post_render_exact_image_artifact_audit"
                )
                late_image_audit_note = str(
                    late_image_audit.get("note")
                    or "Exact post-render image-byte audit."
                )
                late_image_audit_meta = {
                    "materializer_version": MATERIALIZER_VERSION,
                    "contract_table": late_image_audit_name,
                    "section_slug": late_image_audit_spec.get("section_slug"),
                    "source_logical_path": "generated contract PNG artifacts",
                    "materialization_status": late_image_audit_status,
                    "post_render_audit": True,
                }
                _write_file_if_possible(
                    run_folder,
                    late_image_audit_path,
                    late_image_audit_data,
                )
                late_image_audit_id = persist_artifact(
                    late_image_audit_path,
                    "table_csv",
                    "text/csv; charset=UTF-8",
                    late_image_audit_data,
                    late_image_audit_meta,
                )
                created.append(
                    {
                        "logical_path": late_image_audit_path,
                        "artifact_id": late_image_audit_id,
                        "status": late_image_audit_status,
                    }
                )
                manifest_rows.append(
                    [
                        late_image_audit_path,
                        "table_csv",
                        late_image_audit_status,
                        "generated contract PNG artifacts",
                        late_image_audit_note,
                    ]
                )
                late_image_audit_artifact = {
                    "artifact_id": late_image_audit_id,
                    "logical_path": late_image_audit_path,
                    "artifact_kind": "table_csv",
                    "mime_type": "text/csv; charset=UTF-8",
                }
                existing[late_image_audit_path] = late_image_audit_artifact
                source_lookup[late_image_audit_path] = late_image_audit_artifact

    if filesystem_only:
        _append_filesystem_contract_alias_lineage(
            run_folder, plot_lineage_rows
        )

    lineage_header = [
        "PlotId", "ImagePath", "SourceCSV", "SourceCSV_SHA256",
        "ImageSHA256", "Width", "Height", "MimeType", "ImageExists",
        "SourceExists", "ProducerModule", "Status", "FailureReason",
    ]
    lineage_bytes = _encode_csv(lineage_header, plot_lineage_rows)
    lineage_path = plot_lineage_logical_path()
    lineage_meta = {
        "materializer_version": MATERIALIZER_VERSION,
        "materialization_status": "exact_contract_plot_lineage",
        "plot_count": len(plot_lineage_rows),
    }
    _write_file_if_possible(run_folder, lineage_path, lineage_bytes)
    lineage_artifact_id = persist_artifact(
        lineage_path,
        "table_csv",
        "text/csv; charset=UTF-8",
        lineage_bytes,
        lineage_meta,
    )
    created.append({
        "logical_path": lineage_path,
        "artifact_id": lineage_artifact_id,
        "status": "exact_contract_plot_lineage",
    })
    existing[lineage_path] = {
        "artifact_id": lineage_artifact_id,
        "logical_path": lineage_path,
        "artifact_kind": "table_csv",
        "mime_type": "text/csv; charset=UTF-8",
    }
    manifest_rows.append([
        lineage_path,
        "table_csv",
        "exact_contract_plot_lineage",
        "paired contract__ chart CSV datasets",
        f"Exact source and image hashes for {len(plot_lineage_rows)} raster charts.",
    ])

    manifest_header = ["logical_path", "artifact_kind", "materialization_status", "source_logical_path", "note"]
    manifest_bytes = _encode_csv(manifest_header, manifest_rows or [[manifest_logical_path(), "table_csv", "no_changes", "", "All canonical contract artifacts already existed for this run."]])
    manifest_meta = {
        "materializer_version": MATERIALIZER_VERSION,
        "created_count": len(created),
        "source_artifact_high_watermark": current_source_watermark,
    }
    _write_file_if_possible(run_folder, manifest_logical_path(), manifest_bytes)
    persist_artifact(
        manifest_logical_path(),
        "table_csv",
        "text/csv; charset=UTF-8",
        manifest_bytes,
        manifest_meta,
    )
    final_artifacts = list(existing.values())
    coverage = coverage_summary(final_artifacts, feature_policy)
    coverage_bytes = _encode_csv(
        [
            "run_id",
            "materializer_version",
            "tables_total",
            "tables_available",
            "tables_policy_disabled",
            "tables_missing",
            "charts_total",
            "charts_available",
            "charts_policy_disabled",
            "charts_missing",
            "missing_table_paths",
            "missing_chart_names",
        ],
        [[
            run_id,
            MATERIALIZER_VERSION,
            coverage["tables_total"],
            coverage["tables_available"],
            coverage["tables_policy_disabled"],
            len(coverage["missing_table_paths"]),
            coverage["charts_total"],
            coverage["charts_available"],
            coverage["charts_policy_disabled"],
            len(coverage["missing_chart_names"]),
            "; ".join(coverage["missing_table_paths"]) or "[]",
            "; ".join(coverage["missing_chart_names"]) or "[]",
        ]],
    )
    coverage_meta = {
        "materializer_version": MATERIALIZER_VERSION,
        "tables_missing_count": len(coverage["missing_table_paths"]),
        "charts_missing_count": len(coverage["missing_chart_names"]),
    }
    _write_file_if_possible(run_folder, coverage_logical_path(), coverage_bytes)
    persist_artifact(
        coverage_logical_path(),
        "table_csv",
        "text/csv; charset=UTF-8",
        coverage_bytes,
        coverage_meta,
    )
    return {
        "created": created,
        "manifest_path": manifest_logical_path(),
        "coverage_path": coverage_logical_path(),
        "coverage": coverage,
        "skipped": False,
    }


def materialize_filesystem_run_contract_artifacts(
    run_row: dict[str, Any],
    artifacts: list[dict[str, Any]],
    *,
    feature_policy: dict[str, bool] | None = None,
    force: bool = False,
) -> dict[str, Any]:
    """Materialize the browser contract directly into a results-folder run.

    The source bytes are the exact persisted files indexed by the dashboard.
    The normal materializer owns source selection, placeholder suppression,
    lineage, raster PNG validation, and coverage.  No database or configured-
    value substitution is involved.
    """
    artifact_paths = {
        int(artifact.get("artifact_id") or 0): Path(
            str(artifact.get("filesystem_path") or "")
        )
        for artifact in artifacts
        if int(artifact.get("artifact_id") or 0) > 0
        and str(artifact.get("filesystem_path") or "").strip()
    }

    def fetch_artifact_bytes(artifact_id: int) -> bytes:
        path = artifact_paths.get(int(artifact_id))
        if path is None:
            raise FileNotFoundError(
                f"Filesystem artifact {int(artifact_id)} has no indexed path."
            )
        return _windows_long_path(path).read_bytes()

    return materialize_run_contract_artifacts(
        run_row,
        artifacts,
        fetch_artifact_bytes=fetch_artifact_bytes,
        db_connection_factory=None,
        feature_policy=feature_policy,
        force=force,
        lock_timeout_seconds=0,
        filesystem_only=True,
    )
