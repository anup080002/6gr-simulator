from __future__ import annotations

import sys
import csv
import hashlib
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "tools"))

from lls_csv_semantics import (  # noqa: E402
    audit_run,
    _audit_control_table,
    _audit_derived_link_table,
    _audit_domain_runtime_tables,
    _audit_dynamic_tdd_runtime_channel_reciprocity,
    _audit_frc_point_table,
    _audit_component_bler_curve,
    _audit_link_table,
    _audit_manifest_integrity,
    _audit_metric_output_tables,
    _audit_metric_coverage_table,
    _find_named_files,
    _io_path,
    _audit_mimo_rank_layer_table,
    _audit_mimo_beam_codebook_table,
    _audit_beam_precoder_table,
    _audit_beamforming_analytics_table,
    _audit_mimo_antenna_array_table,
    _audit_mimo_antenna_port_mapping_table,
    _audit_mimo_config_strict_table,
    _audit_mimo_config_validation_table,
    _audit_mimo_configured_effective_table,
    _audit_mimo_layer_metrics_table,
    _audit_mimo_per_trial_companion,
    _audit_mimo_rank_coverage_table,
    _audit_harq_observation_tables,
    _audit_kpi_delivery_direction,
    _kpi_transport_block_keys,
    _audit_runtime_call_ledger,
    _audit_status_reduction,
    _audit_phase7_reducer,
    _audit_reconciliation_reducers,
    _audit_production_qualification_reducer,
    _audit_gate_row_table,
    _audit_measurement_sidecar_manifest,
    _audit_observed_re_allocation,
    _audit_canonical_component_manifest,
    _audit_mcs_cqi_reference_tables,
    _audit_dut_reference_comparison,
    _audit_chart_lineage,
    _domain_table_applicability,
    _empty_domain_table_is_valid_zero_event,
    _audit_fixed_snr_reporting_tables,
    _audit_kpi_reporting_tables,
    _clopper_pearson_two_sided,
    PHASE7_GATE_NAMES,
    PHASE7_PHASE_MEMBERS,
    PRODUCTION_GATE_ORDER,
    RECONCILIATION_PHASE7_FLAGS,
)


def _dynamic_tdd_channel_trial(direction: str) -> dict[str, str]:
    direction = direction.upper()
    return {
        "Direction": direction,
        "RuntimeChannelStateKey": "tdd_reciprocal;endpoint_a=gnb1;endpoint_b=ue1",
        "RuntimeChannelLinkKey": f"dir={direction};tx={'gnb1' if direction == 'DL' else 'ue1'};rx={'ue1' if direction == 'DL' else 'gnb1'}",
        "RuntimeChannelSeed": "4702601",
        "RuntimeChannelReciprocityExact": "1",
        "RuntimeChannelReciprocityDirection": direction,
        "RuntimeChannelReciprocitySource": "matlab_nr_channel_swapTransmitAndReceive_shared_fading_timeline",
        "RuntimeChannelReciprocityApproximationMode": "none_dynamic_exact",
        "RuntimeChannelTransmitAndReceiveSwapped": "1" if direction == "UL" else "0",
        "RuntimeChannelStartSample": "1024" if direction == "UL" else "0",
        "RuntimeChannelEndSample": "2048" if direction == "UL" else "1024",
        "RuntimeChannelCanonicalInputSamples": "1024",
        "RuntimeChannelAlignmentLookaheadSamples": "17",
        "RuntimeChannelAlignmentLookaheadExecutedOnFork": "1",
        "RuntimeChannelObjectClockExact": "1",
        "RuntimeChannelPathGainsSHA256": ("b" if direction == "UL" else "a") * 64,
    }


def _dynamic_tdd_angle_row(
    direction: str,
    *,
    aod: float,
    aoa: float,
    zod: float,
    zoa: float,
) -> dict[str, str]:
    direction = direction.upper()
    return {
        "Panel": "runtime_channel_angles",
        "SnapshotID": f"snapshot-{direction.lower()}",
        "Direction": direction,
        "CellID": "1",
        "UEIndex": "1",
        "RNTI": "1",
        "SFN": "0",
        "Slot": "1" if direction == "DL" else "5",
        "AbsoluteSlot": "1" if direction == "DL" else "5",
        "PathIndex": "1",
        "PathDelay_s": "1e-7",
        "AzimuthDeparture_deg": str(aod),
        "AzimuthArrival_deg": str(aoa),
        "ZenithDeparture_deg": str(zod),
        "ZenithArrival_deg": str(zoa),
        "PowerLinear": "0.25",
        "Power_dB": "-6.020599913279624",
        "AngleCoordinateFrame": "3gpp_tr38901_global_coordinate_system",
        "AngleEvidenceSource": "info_on_same_executed_runtime_channel_object",
        "RuntimeChannelStateKey": "tdd_reciprocal;endpoint_a=gnb1;endpoint_b=ue1",
        "RuntimeChannelLinkKey": f"dir={direction};tx={'gnb1' if direction == 'DL' else 'ue1'};rx={'ue1' if direction == 'DL' else 'gnb1'}",
        "RuntimeChannelSeed": "4702601",
        "RuntimeChannelReciprocityExact": "1",
        "RuntimeChannelReciprocityDirection": direction,
        "RuntimeChannelReciprocitySource": "matlab_nr_channel_swapTransmitAndReceive_shared_fading_timeline",
        "RuntimeChannelReciprocityApproximationMode": "none_dynamic_exact",
        "RuntimeChannelTransmitAndReceiveSwapped": "1" if direction == "UL" else "0",
        "GridSHA256": ("b" if direction == "UL" else "a") * 64,
    }


def test_dynamic_tdd_reciprocity_requires_shared_state_and_executed_path_angles(
    tmp_path: Path,
) -> None:
    config_path = tmp_path / "meta/scenario_config_resolved.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps({
        "frequency": {"duplex_mode": "TDD"},
        "channels": {"model_type": "CDL", "profile": "CDL-A", "max_doppler_hz": 6.5},
        "output": {"phy_signal_diagnostic_enabled": True},
    }), encoding="utf-8")
    link_rows = {
        "DL": [_dynamic_tdd_channel_trial("DL")],
        "UL": [_dynamic_tdd_channel_trial("UL")],
    }
    _write_rows(
        tmp_path / "reports/csv/phy_signal_diagnostic_source.csv",
        [
            _dynamic_tdd_angle_row("DL", aod=-32, aoa=18, zod=92, zoa=88),
            _dynamic_tdd_angle_row("UL", aod=18, aoa=-32, zod=88, zoa=92),
        ],
    )
    checks = _audit_dynamic_tdd_runtime_channel_reciprocity(tmp_path, link_rows)
    assert len(checks) == 2
    assert all(check.passed for check in checks), [check.details for check in checks]

    link_rows["UL"][0]["RuntimeChannelStateKey"] = "independent-ul-state"
    angle_rows = [
        _dynamic_tdd_angle_row("DL", aod=-32, aoa=18, zod=92, zoa=88),
        _dynamic_tdd_angle_row("UL", aod=19, aoa=-32, zod=88, zoa=92),
    ]
    _write_rows(tmp_path / "reports/csv/phy_signal_diagnostic_source.csv", angle_rows)
    checks = _audit_dynamic_tdd_runtime_channel_reciprocity(tmp_path, link_rows)
    failed = {check.check_id: check.details for check in checks if not check.passed}
    assert "shared_state_key_count=2" in failed["dynamic_TDD_shared_exact_fading_state"]
    assert "reciprocal_swap_mismatch" in failed[
        "executed_path_AoA_AoD_reciprocity_and_power"
    ]


def test_chart_lineage_accepts_explicit_measured_operating_point(
    tmp_path: Path,
) -> None:
    from PIL import Image, PngImagePlugin

    source_rel = "reports/csv/cqi_mcs_operating_point.csv"
    image_rel = "reports/image/cqi_mcs_operating_point.png"
    source_path = tmp_path / source_rel
    image_path = tmp_path / image_rel
    _write_rows(source_path, [{
        "run_id": "run",
        "chart_name": "CQI vs selected MCS",
        "chart_mode": "scatter",
        "x_label": "CQI",
        "y_label": "Mean selected MCS",
        "point_index": "1",
        "x_value": "9",
        "y_value": "15",
        "source_mapping_status": "exact",
        "evidence_shape_policy": "operating_point",
        "source_sample_count": "3",
    }])
    image_path.parent.mkdir(parents=True, exist_ok=True)
    png_info = PngImagePlugin.PngInfo()
    png_info.add_text(
        "sixgr_visual_semantics",
        "evidence_shape_policy=operating_point; no relation or sweep is inferred",
    )
    Image.new("RGB", (16, 16), "white").save(image_path, pnginfo=png_info)
    _write_rows(tmp_path / "reports/csv/contract_plot_lineage.csv", [{
        "PlotId": "cqi_mcs_operating_point",
        "ImagePath": image_rel,
        "SourceCSV": source_rel,
        "Status": "PASS",
        "ImageSHA256": hashlib.sha256(image_path.read_bytes()).hexdigest(),
        "SourceCSV_SHA256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
    }])

    checks = _audit_chart_lineage(tmp_path)
    point_check = next(
        item for item in checks if item.check_id == "cqi_mcs_operating_point"
    )
    assert point_check.passed, point_check.details


def _observed_re_row(
    direction: str, channel: str, allocation_id: str, ue_id: int = 1
) -> dict[str, str]:
    return {
        "ScenarioID": "fdd_re_ownership",
        "ConfigHash": "a" * 64,
        "absolute_slot": "0",
        "sfn": "0",
        "slot_within_frame": "0",
        "direction": direction,
        "channel": channel,
        "subcarrier_start": "0",
        "subcarrier_count": "1",
        "symbol_index": "0",
        "port_index": "0",
        "re_count": "1",
        "cell_id": "1",
        "ue_id": str(ue_id),
        "authority": "executed_tx_toolbox_config_and_indices",
        "resolver": "focused_exact_test",
        "allocation_id": allocation_id,
        "coordinate_precision": "exact_contiguous_re_run",
        "evidence_scope": "runtime_observed_tx_occupancy",
        "run_tag": "focused",
        "status_classification": "implemented",
        "active_flag": "1",
    }


def _observed_grid_checks(tmp_path: Path, rows: list[dict[str, str]]):
    config = {"frame": {"duplex": "FDD", "scs_khz": 15}, "bwp": {"dl": {"n_size_bwp": 1}}}
    path = tmp_path / "meta/scenario_config_resolved.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(config), encoding="utf-8")
    _write_rows(tmp_path / "frame_grid/csv/observed_re_allocation.csv", rows)
    return _audit_observed_re_allocation(tmp_path)


def test_observed_si_broadcast_requires_executed_grid_and_interval(tmp_path: Path) -> None:
    # Declared validator inputs, not PHY measurements or qualification rows.
    row = _observed_re_row("DL", "PDSCH", "sib1_component")
    row.update({
        "ue_id": "", "rnti": "65535", "associated_ssb_index0": "0",
        "authority": "executed_broadcast_tx_grid_and_committed_waveform_interval",
        "waveform_port_domain": "physical_element_domain", "transmit_grid_sha256": "b" * 64,
        "broadcast_start_sample": "0", "broadcast_end_sample_exclusive": "7680",
        "observation_sample_rate_hz": "7680000",
    })
    assert all(check.passed for check in _observed_grid_checks(tmp_path, [row]))
    for field, value in [
        ("rnti", "1"), ("authority", "executed_tx_toolbox_config_and_indices"),
        ("waveform_port_domain", "logical_port"), ("transmit_grid_sha256", ""),
        ("associated_ssb_index0", "NaN"), ("broadcast_start_sample", "1"),
        ("broadcast_end_sample_exclusive", "7679"), ("observation_sample_rate_hz", "0"),
        ("channel", "PUSCH"),
    ]:
        bad = dict(row, **{field: value})
        checks = _observed_grid_checks(tmp_path, [bad])
        assert any(not check.passed and "data_allocation_missing_UE_identity" in check.details for check in checks), field
    checks = _observed_grid_checks(tmp_path, [dict(row, ue_id="1")])
    assert any("cell_broadcast_must_not_claim_unicast_UE" in check.details for check in checks)


def test_observed_grid_collisions_are_cell_scoped(tmp_path: Path) -> None:
    first = _observed_re_row("DL", "PDSCH", "cell1")
    second = dict(_observed_re_row("DL", "PDSCH", "cell2"), cell_id="2")
    assert all(check.passed for check in _observed_grid_checks(tmp_path, [first, second]))
    second["cell_id"] = "1"
    assert any("RE_collision_with" in check.details for check in _observed_grid_checks(tmp_path, [first, second]))
    second["cell_id"] = ""
    assert any("missing_or_invalid_cell_identity" in check.details for check in _observed_grid_checks(tmp_path, [second]))


def test_native_prach_cannot_be_audited_as_carrier_re(tmp_path: Path) -> None:
    for channel, domain in [("PRACH", ""), ("PRACH", "carrier_cp_ofdm"), ("PUSCH", "prach_native_ofdm")]:
        row = dict(_observed_re_row("UL", channel, "native"), grid_domain=domain)
        assert any("noncarrier_native_grid_in_carrier_RE_table" in check.details
                   for check in _observed_grid_checks(tmp_path, [row]))


def test_fdd_opposite_direction_re_coordinates_are_distinct_rf_carriers(
    tmp_path: Path,
) -> None:
    config = {
        "frame": {"duplex": "FDD", "scs_khz": 15},
        "bwp": {"dl": {"n_size_bwp": 1}},
    }
    config_path = tmp_path / "meta/scenario_config_resolved.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(config), encoding="utf-8")
    _write_rows(
        tmp_path / "frame_grid/csv/observed_re_allocation.csv",
        [
            _observed_re_row("DL", "PDSCH", "dl_grant"),
            _observed_re_row("UL", "PUSCH", "ul_grant"),
        ],
    )
    checks = _audit_observed_re_allocation(tmp_path)
    assert checks and all(check.passed for check in checks), [
        check.details for check in checks
    ]


def test_same_direction_distinct_allocations_cannot_claim_the_same_re(
    tmp_path: Path,
) -> None:
    config = {
        "frame": {"duplex": "FDD", "scs_khz": 15},
        "bwp": {"dl": {"n_size_bwp": 1}},
    }
    config_path = tmp_path / "meta/scenario_config_resolved.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(config), encoding="utf-8")
    _write_rows(
        tmp_path / "frame_grid/csv/observed_re_allocation.csv",
        [
            _observed_re_row("DL", "PDSCH", "grant_a"),
            _observed_re_row("DL", "PDCCH", "grant_b"),
        ],
    )
    checks = _audit_observed_re_allocation(tmp_path)
    collision = next(
        check for check in checks
        if check.check_id == "exact_RE_bounds_direction_and_collision"
    )
    assert not collision.passed
    assert "RE_collision_with=PDSCH:grant_a" in collision.details


def test_complete_finalized_mu_group_may_share_exact_data_res(
    tmp_path: Path,
) -> None:
    config = {
        "frame": {"duplex": "FDD", "scs_khz": 15},
        "bwp": {"dl": {"n_size_bwp": 1}},
    }
    config_path = tmp_path / "meta/scenario_config_resolved.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(config), encoding="utf-8")
    _write_rows(
        tmp_path / "frame_grid/csv/observed_re_allocation.csv",
        [
            _observed_re_row("DL", "PDSCH", "grant_ue1", 1),
            _observed_re_row("DL", "PDSCH", "grant_ue2", 2),
        ],
    )
    trial_rows = []
    for ue_id in (1, 2):
        trial_rows.append(
            {
                "Direction": "DL",
                "Slot": "1",
                "UEIndex": str(ue_id),
                "GrantContextId": f"grant_ue{ue_id}",
                "MUMIMOEnabled": "1",
                "MUMIMOGroupId": "5000001",
                "MUMIMOGroupSize": "2",
                "FinalizedFlag": "1",
                "FallbackFlag": "0",
                "PlaceholderFlag": "0",
            }
        )
    _write_rows(
        tmp_path / "air_interface/csv/dl_pdsch_trials.csv", trial_rows
    )
    checks = _audit_observed_re_allocation(tmp_path)
    assert checks and all(check.passed for check in checks), [
        check.details for check in checks
    ]


def test_incomplete_mu_group_cannot_excuse_exact_re_collision(
    tmp_path: Path,
) -> None:
    config = {
        "frame": {"duplex": "FDD", "scs_khz": 15},
        "bwp": {"dl": {"n_size_bwp": 1}},
    }
    config_path = tmp_path / "meta/scenario_config_resolved.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(config), encoding="utf-8")
    _write_rows(
        tmp_path / "frame_grid/csv/observed_re_allocation.csv",
        [
            _observed_re_row("DL", "PDSCH", "grant_ue1", 1),
            _observed_re_row("DL", "PDSCH", "grant_ue2", 2),
        ],
    )
    _write_rows(
        tmp_path / "air_interface/csv/dl_pdsch_trials.csv",
        [
            {
                "Direction": "DL",
                "Slot": "1",
                "UEIndex": "1",
                "GrantContextId": "grant_ue1",
                "MUMIMOEnabled": "1",
                "MUMIMOGroupId": "5000001",
                "MUMIMOGroupSize": "2",
                "FinalizedFlag": "1",
                "FallbackFlag": "0",
                "PlaceholderFlag": "0",
            }
        ],
    )
    checks = _audit_observed_re_allocation(tmp_path)
    collision = next(
        check for check in checks
        if check.check_id == "exact_RE_bounds_direction_and_collision"
    )
    assert not collision.passed
    assert "RE_collision_with=PDSCH:grant_ue1" in collision.details


def test_optional_runtime_tables_follow_resolved_feature_applicability(
    tmp_path: Path,
) -> None:
    summary: dict[str, str] = {}
    disabled: dict[str, object] = {
        "initial_access": {"enabled": False},
        "random_access": {"enabled": False},
        "random_access_evidence": {
            "preamble_collision_test_enabled": False,
            "four_step_negative_test_enabled": False,
        },
        "control_gating": {
            "pbch_required": False,
            "prach_required": False,
            "srs_required": False,
            "trs_required": False,
        },
        "reference_signals": {
            "srs_enabled": False,
            "trs_enabled": False,
            "csi_rs_enabled": False,
        },
        "mimo_and_beam_management": {
            "beam_sweeping": False,
            "beam_refinement": False,
            "beam_switching": False,
            "beam_tracking": False,
        },
        "system": {"beam": {"enable": False}},
    }
    optional_paths = (
        "control/csv/access_state_timeline.csv",
        "control/csv/access_transition_ledger.csv",
        "reports/csv/access_state_timeline.csv",
        "reports/csv/access_transition_ledger.csv",
        "control/csv/pbch_trials.csv",
        "control/csv/prach_trials.csv",
        "control/csv/ra_collision_trials.csv",
        "control/csv/ra_negative_trials.csv",
        "control/csv/csi_rs_trials.csv",
        "control/csv/srs_trials.csv",
        "control/csv/trs_trials.csv",
        "reports/csv/live_receiver_tracking_trace.csv",
        "reports/csv/live_beam_p1_acquisition_stats.csv",
        "reports/csv/beam_management_outputs.csv",
        "reports/csv/live_csirs_stats.csv",
    )
    for relative in optional_paths:
        assert _domain_table_applicability(
            relative, tmp_path, summary, disabled
        ) == (False, False)

    assert _empty_domain_table_is_valid_zero_event(
        "reports/csv/raster_replacement_inventory.csv", tmp_path
    )

    for relative, header in (
        ("reports/csv/access_state_timeline.csv", "UEIndex,Slot,State\n"),
        ("reports/csv/access_transition_ledger.csv", "UEIndex,Slot,Transition\n"),
        (
            "reports/csv/raster_replacement_inventory.csv",
            "relative_path,extension,bytes,sha256,width_px,height_px,format\n",
        ),
    ):
        path = tmp_path / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(header, encoding="utf-8")
    empty_checks = {
        check.artifact_path: check
        for check in _audit_domain_runtime_tables(tmp_path, summary)
        if check.check_id == "schema_and_runtime_rows"
    }
    for relative in (
        "reports/csv/access_state_timeline.csv",
        "reports/csv/access_transition_ledger.csv",
    ):
        check = empty_checks[relative]
        assert not check.required and not check.evaluated and check.failure_count == 0
    raster_check = empty_checks["reports/csv/raster_replacement_inventory.csv"]
    assert raster_check.required and raster_check.evaluated and raster_check.passed

    enabled = json.loads(json.dumps(disabled))
    enabled["initial_access"]["enabled"] = True
    enabled["random_access"]["enabled"] = True
    enabled["random_access_evidence"]["preamble_collision_test_enabled"] = True
    enabled["random_access_evidence"]["four_step_negative_test_enabled"] = True
    enabled["control_gating"].update({
        "pbch_required": True,
        "prach_required": True,
        "srs_required": True,
        "trs_required": True,
    })
    enabled["reference_signals"]["srs_enabled"] = True
    enabled["reference_signals"]["trs_enabled"] = True
    enabled["reference_signals"]["csi_rs_enabled"] = True
    enabled["mimo_and_beam_management"]["beam_sweeping"] = True
    for relative in optional_paths:
        assert _domain_table_applicability(
            relative, tmp_path, summary, enabled
        ) == (True, True)


def test_geometry_plot_lineage_is_required_only_when_governed_raster_exists(
    tmp_path: Path,
) -> None:
    relative = "reports/csv/geometry_plot_lineage.csv"
    summary: dict[str, str] = {}
    assert _domain_table_applicability(
        relative, tmp_path, summary, {}
    ) == (False, False)

    path = tmp_path / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "PlotId,ImagePath,SourceCSV,SourceCSV_SHA256,ImageSHA256,Status,Producer,SourceRows\n",
        encoding="utf-8",
    )
    check = next(
        item for item in _audit_domain_runtime_tables(tmp_path, summary)
        if item.artifact_path == relative
        and item.check_id == "schema_and_runtime_rows"
    )
    assert not check.required and not check.evaluated
    assert check.failure_count == 0 and check.details == ""

    raster = tmp_path / "geometry/image/topology_map.png"
    raster.parent.mkdir(parents=True, exist_ok=True)
    raster.write_bytes(b"runtime-raster")
    assert _domain_table_applicability(
        relative, tmp_path, summary, {}
    ) == (True, True)
    failed = next(
        item for item in _audit_domain_runtime_tables(tmp_path, summary)
        if item.artifact_path == relative
        and item.check_id == "schema_and_runtime_rows"
    )
    assert failed.required and failed.evaluated and not failed.passed
    assert "missing_runtime_rows" in failed.details


def test_cdlc_realization_table_requires_exact_cdlc_profile(tmp_path: Path) -> None:
    summary: dict[str, str] = {}
    relatives = (
        "reports/csv/channel_rf_cdlc_realization_table.csv",
        "component_anchors/channel_rf/reports/csv/channel_rf_cdlc_realization_table.csv",
    )
    for relative in relatives:
        assert _domain_table_applicability(
            relative, tmp_path, summary, {"channels": {"profile": "CDL-A"}}
        ) == (False, False)
        assert _domain_table_applicability(
            relative, tmp_path, summary, {"channels": {"profile": "CDL-C"}}
        ) == (True, True)

    relative = relatives[1]
    path = tmp_path / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("RunId,PathIndex,Delay_s,AveragePathGain_dB\n", encoding="utf-8")
    config_path = tmp_path / "meta/scenario_config_resolved.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(
        json.dumps({"channels": {"profile": "CDL-A"}}), encoding="utf-8"
    )
    check = next(
        item for item in _audit_domain_runtime_tables(tmp_path, summary)
        if item.artifact_path == relative
        and item.check_id == "schema_and_runtime_rows"
    )
    assert not check.required and not check.evaluated
    assert check.failure_count == 0 and check.details == ""


def _component_primary_rows(direction: str) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for trial, crc_pass in enumerate(("1", "1", "1", "0"), start=1):
        row = {
            "RunID": "run-1",
            "ScenarioID": "scenario-1",
            "ConfigHash": "a" * 64,
            "ExecutionID": "execution-1",
            "ConfiguredSNR_dB": "5",
            "ChannelModelApplied": "AWGN",
            "Rank": "1",
            "MCSIndex": "10",
            "Modulation": "16QAM",
            "CRCPass": crc_pass,
            "FinalizedFlag": "1",
            "CRCApplicable": "1",
            "DecodeAttempted": "1",
            "FallbackFlag": "0",
            "PlaceholderFlag": "0",
            "TruthStatus": "real_lls_evidence",
            "Frame": str(trial),
            "Slot": str(trial),
            "UEID": "1",
        }
        if direction == "UL":
            row.update({
                "TransformPrecodingApplied": "0",
                "FrequencyHoppingApplied": "0",
                "FrequencyHoppingMode": "none",
            })
        rows.append(row)
    return rows


def _component_curve_row(direction: str) -> dict[str, str]:
    key = "snr=5|channel=AWGN|rank=1|mcs=10|mod=16QAM"
    if direction == "UL":
        key += "|tp=0|hop=none"
    row = {
        "CampaignID": "run-1",
        "OperatingPointID": hashlib.sha256(key.encode("utf-8")).hexdigest(),
        "SNRdB": "5",
        "ChannelModel": "AWGN",
        "Rank": "1",
        "MCSIndex": "10",
        "Modulation": "16QAM",
        "Trials": "4",
        "TBErrors": "1",
        "BLER": "0.25",
        "ConfidenceLevel": "0.95",
        "CILower": "0.006309463209709866",
        "CIUpper": "0.8058795503167565",
        "CIHalfWidth": "0.39978504355352334",
        "MinErrorsRequired": "0",
        "QualificationProfile": "diagnostic",
        "PublicationQualificationRequested": "0",
        "PublicationEligible": "0",
        "StopReason": "diagnostic_profile_design_criteria_reached",
        "Incomplete": "0",
        "Status": "MEASURED",
        "ScenarioID": "scenario-1",
        "ConfigHash": "a" * 64,
        "EvidenceScope": "in_path",
        "EvidenceOrigin": "current_runtime_memory",
        "RunID": "run-1",
        "ExecutionID": "execution-1",
        "CenterFrequencyHz": "3500000000",
        "BandwidthHz": "100000000",
        "SubcarrierSpacingHz": "30000",
        "IntervalMethod": "CLOPPER_PEARSON_TWO_SIDED",
        "EvidenceUnit": "decoded_transport_block",
    }
    if direction == "UL":
        row.update({"TransformPrecoding": "0", "FrequencyHopping": "none"})
    return row


def test_component_bler_semantics_recompute_raw_counts_and_exact_interval() -> None:
    summary = {"ScenarioID": "scenario-1", "ConfigHash": "a" * 64}
    for direction, path in (
        ("DL", "components/pdsch/csv/pdsch_bler_curve.csv"),
        ("UL", "components/pusch/csv/pusch_bler_curve.csv"),
    ):
        row = _component_curve_row(direction)
        checks = _audit_component_bler_curve(
            path, list(row), [row], direction,
            _component_primary_rows(direction), summary,
        )
        assert all(check.passed for check in checks), [check.details for check in checks]


def test_component_bler_semantics_reject_corrupt_interval_origin_and_counts() -> None:
    row = _component_curve_row("DL")
    row["TBErrors"] = "2"
    row["CILower"] = "0.1"
    row["EvidenceOrigin"] = "reconstructed_from_chart"
    checks = _audit_component_bler_curve(
        "components/pdsch/csv/pdsch_bler_curve.csv",
        list(row), [row], "DL", _component_primary_rows("DL"),
        {"ScenarioID": "scenario-1", "ConfigHash": "a" * 64},
    )
    failed = {check.check_id: check.details for check in checks if not check.passed}
    assert "EvidenceOrigin_invalid" in failed["runtime_identity_and_truth_origin"]
    assert "bler_count_or_interval_arithmetic_invalid" in failed[
        "operating_point_bler_and_exact_interval"
    ]
    assert "TBErrors_not_source_crc_fail_count" in failed[
        "exact_primary_trial_reconciliation"
    ]


def _mimo_source_and_rank_row() -> tuple[dict[str, str], dict[str, str]]:
    raw = {
        "RunID": "run-1", "ScenarioID": "scenario-1", "Direction": "DL",
        # Canonical primary trials may expose a descriptive UEID alongside a
        # numeric UEIndex.  Numeric reconciliation must try the next alias.
        "Frame": "1", "Slot": "2", "UEID": "UE3", "UEIndex": "3", "CRCPass": "0",
        "Layers": "1", "MCSIndex": "10", "Modulation": "16QAM",
        "IsWarmupFrame": "0", "MeasuredDMRSPortCount": "1",
    }
    row = {
        "RunId": "run-1", "ScenarioName": "scenario-1", "TrialId": "1",
        "Direction": "DL", "CellId": "1", "UEId": "3", "Frame": "1",
        "Slot": "2", "ConfiguredRank": "1", "ConfiguredLayers": "1",
        "ConfiguredMaximumRank": "1", "ConfiguredMaximumLayers": "1",
        "ScheduledRank": "1", "ScheduledLayers": "1", "TransmittedRank": "1",
        "TransmittedLayers": "1", "ReceiverEstimatedRank": "1",
        "SpatialChannelRankEstimate": "1", "SpatialChannelTxPorts": "2",
        "SpatialChannelRxAntennas": "2",
        "SpatialChannelRankDomain": "dl_scheduled_data_port_channel",
        "SpatialChannelRankSource": "runtime_dmrs_channel_estimate",
        "EffectiveDecodedRank": "0", "EffectiveDecodedLayers": "0",
        "NumRxAntennas": "2", "NumTxPorts": "2", "TxWaveformColumns": "2",
        "PhysicalTxAntennas": "2", "RxWaveformBranches": "2",
        "PhysicalRxAntennas": "2", "LogicalTxPortCount": "1",
        "LogicalRxBranchCount": "2", "ConfiguredModulation": "16QAM",
        "ScheduledModulation": "16QAM", "TransmittedModulation": "16QAM",
        "EffectiveDecodedModulation": "16QAM", "ConfiguredMCS": "10",
        "ConfiguredInitialMCS": "10", "ConfiguredMaximumMCS": "10",
        "ScheduledMCS": "10", "TransmittedMCS": "10",
        "EffectiveDecodedMCS": "10", "DMRSPorts": "0", "MeasuredDMRSPortCount": "1",
        "ConfiguredMCSSelectionPolicy": "fixed",
        "ActualMCSSelectionMode": "configured_fixed",
        "MCSSelectionSource": "configured_fixed_mcs",
        "MCSAuthority": "configured_fixed_mcs",
        "ModulationAuthority": "configured_fixed_mcs",
        "AppliedOperatingPointSource": "configured_fixed_mcs",
        "LinkAdaptationScheduled": "0", "LinkAdaptationApplied": "0",
        "WidebandCQI": "NaN", "CQIDerivedMCS": "NaN",
        "AdaptiveFeedbackDecisionObserved": "0",
        "AppliedPrecoderMatrixSHA256": "b" * 64, "LayerSINRdB": "8.5",
        "PrecoderId": "0", "BeamId": "1",
        "DecodeCrcPass": "0", "ExactSpatialMatch": "1",
        "SpatialContractMatch": "1", "ExactOperatingPointMatch": "1",
        "FixedOperatingPointMatch": "1", "AdaptivePolicyRequired": "0",
        "AdaptivePolicyMatch": "1", "AdaptivePolicyConformance": "1",
        "AdaptivePolicyFailureReason": "not_applicable_fixed_operating_point",
        "OperatingPointContractMatch": "1", "MUExecutionRequired": "0",
        "RequiredMUUserCount": "2", "RequiredMULeakageThreshold_dB": "-15",
        "RequiredMUExecutionMode": "none", "MUMIMOEnabled": "0",
        "InterferenceContributorCount": "0", "MUExecutionMatch": "1",
        "ExactConfiguredMatch": "1", "ExecutionContractMatch": "1",
        "AdaptiveMode": "0", "AdaptationEvidenceId": "",
        "FixedAnchorMode": "1", "StrictEligible": "1",
        "ExecutionContractOk": "1", "DecodeReliabilityOk": "0",
        "DecodeReliabilityStatus": "crc_fail", "StrictOk": "1",
        "SourceArtifactRef": "air_interface/csv/dl_pdsch_trials.csv",
        "SourceRowsHash": "c" * 64, "Status": "pass", "FailureReason": "",
    }
    return raw, row


def test_mimo_rank_semantics_keep_crc_failure_separate_from_execution() -> None:
    raw, row = _mimo_source_and_rank_row()
    checks = _audit_mimo_rank_layer_table(
        "beamforming/csv/rank_layer_trials.csv", list(row), [row],
        {"DL": [raw], "UL": []},
    )
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_mimo_configured_effective_decoded_rank_ignores_crc_failure_sentinel() -> None:
    _raw, failed = _mimo_source_and_rank_row()
    failed["EffectiveDecodedRank"] = "0"
    failed["EffectiveDecodedLayers"] = "0"
    failed["DecodeCrcPass"] = "0"
    failed["DecodeReliabilityOk"] = "0"
    failed["DecodeReliabilityStatus"] = "crc_fail"

    successful = dict(failed)
    successful["TrialId"] = "2"
    successful["EffectiveDecodedRank"] = "1"
    successful["EffectiveDecodedLayers"] = "1"
    successful["DecodeCrcPass"] = "1"
    successful["DecodeReliabilityOk"] = "1"
    successful["DecodeReliabilityStatus"] = "crc_pass"

    summary = _mimo_configured_effective_row()
    summary["DominantEffectiveDecodedRank"] = "1"
    summary["DominantEffectiveDecodedLayers"] = "1"
    summary["StrictEligibleRowCount"] = "2"
    summary["RuntimeTrialCount"] = "2"
    summary["ExactMatchRowCount"] = "2"
    summary["ExactSpatialMatchRowCount"] = "2"
    summary["ExactOperatingPointMatchRowCount"] = "2"
    summary["AdaptivePolicyMatchRowCount"] = "2"
    summary["ExecutionContractMatchRowCount"] = "2"

    checks = _audit_mimo_configured_effective_table(
        "beamforming/csv/mimo_configured_vs_effective.csv",
        list(summary), [summary], [failed, successful],
    )
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_mimo_missing_beam_uses_explicit_not_selected_category() -> None:
    raw, rank = _mimo_source_and_rank_row()
    raw["RequestedBeamIndexSet"] = "not_recorded_by_active_ul_pusch_trials_runtime"
    raw["AppliedBeamIndexSet"] = ""
    rank["BeamId"] = ""
    rank["ConfiguredLayers"] = "1"
    beam_row = {
        "RunId": rank["RunId"], "TrialId": rank["TrialId"],
        "Direction": rank["Direction"], "SelectedBeamId": "not_selected",
        "CSIReportId": "", "MeasurementSource": "air_interface_trial_row",
        "SourceRowsHash": rank["SourceRowsHash"], "Status": "pass",
        "FailureReason": "",
    }
    checks = _audit_mimo_per_trial_companion(
        "beamforming/csv/beam_sweep_measurements.csv", list(beam_row),
        [beam_row], [rank],
    )
    assert all(check.passed for check in checks), [check.details for check in checks]

    _raw, output = _beam_primary_and_output()
    _raw["RequestedBeamIndexSet"] = raw["RequestedBeamIndexSet"]
    _raw["AppliedBeamIndexSet"] = raw["AppliedBeamIndexSet"]
    output["requested_beam_index_set"] = "not_selected"
    output["applied_beam_index_set"] = "not_selected"
    checks = _audit_beam_precoder_table(
        "beamforming/csv/beam_precoder_table.csv", list(output), [output],
        {"DL": [_raw], "UL": []},
    )
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_mimo_rank_semantics_reject_execution_and_decode_status_corruption() -> None:
    raw, row = _mimo_source_and_rank_row()
    row["TransmittedRank"] = "2"
    row["StrictOk"] = "0"
    row["DecodeReliabilityOk"] = "1"
    row["EffectiveDecodedRank"] = "1"
    checks = _audit_mimo_rank_layer_table(
        "beamforming/csv/rank_layer_trials.csv", list(row), [row],
        {"DL": [raw], "UL": []},
    )
    failed = {check.check_id: check.details for check in checks if not check.passed}
    assert "ExactSpatialMatch_mismatch" in failed["execution_contract_boolean_reduction"]
    assert "DecodeReliabilityOk_mismatch" in failed[
        "decode_reliability_separate_from_execution"
    ]
    assert "crc_fail_decoded_rank_layers_not_zero" in failed[
        "decode_reliability_separate_from_execution"
    ]
    assert "TransmittedRank_not_primary_source" in failed[
        "ordered_primary_trial_and_lineage_reconciliation"
    ]


def _mimo_configured_effective_row() -> dict[str, str]:
    return {
        "RunId": "run-1", "ScenarioName": "scenario-1", "Direction": "DL",
        "ConfiguredRank": "1", "DominantScheduledRank": "1",
        "DominantTransmittedRank": "1", "DominantEffectiveDecodedRank": "0",
        "ConfiguredLayers": "1", "DominantScheduledLayers": "1",
        "DominantTransmittedLayers": "1", "DominantEffectiveDecodedLayers": "0",
        "ConfiguredModulation": "16QAM", "DominantEffectiveModulation": "16QAM",
        "ConfiguredMCS": "10", "ConfiguredInitialMCS": "10",
        "ConfiguredMaximumMCS": "10", "DominantEffectiveMCS": "10",
        "AdaptiveMode": "0", "StrictEligibleRowCount": "1",
        "ExactMatchRowCount": "1", "ExactMatchPercent": "1",
        "ExactSpatialMatchRowCount": "1", "ExactSpatialMatchPercent": "1",
        "ExactOperatingPointMatchRowCount": "1", "ExactOperatingPointMatchPercent": "1",
        "AdaptivePolicyMatchRowCount": "1", "AdaptivePolicyMatchPercent": "1",
        "AdaptiveFeedbackDecisionRowCount": "0",
        "ExecutionContractMatchRowCount": "1", "ExecutionContractMatchPercent": "1",
        "SpatialContractRequired": "1", "SpatialContractMatch": "1",
        "FixedOperatingPointRequired": "1", "FixedOperatingPointMatch": "1",
        "AdaptivePolicyRequired": "0", "AdaptivePolicyConformance": "1",
        "MUExecutionRequired": "0", "RequiredMUUserCount": "2",
        "RequiredMULeakageThreshold_dB": "-15", "RequiredMUExecutionMode": "none",
        "MUExecutedTrialRowCount": "0", "MUExecutedDistinctGroupCount": "0",
        "MUExecutionMatch": "1", "MUExecutionFailureReason": "not_applicable_mu_disabled",
        "RequiredExactMatchPercent": "0.999",
        "RequiredExecutionContractMatchPercent": "0.999",
        "ScenarioObjectivePass": "1", "RuntimePopulated": "1",
        "RuntimeTrialCount": "1", "RuntimeRank2Fraction": "0",
        "RuntimeExactMatchFraction": "1",
        "RuntimeEvidenceSource": "rank_layer_trials_from_air_interface_raw_trials",
        "EvidenceClass": "DIRECT_RUNTIME_EVIDENCE", "Status": "pass",
        "FailureReason": "",
    }


def _mimo_companion_rows() -> dict[str, dict[str, str]]:
    return {
        "beamforming/csv/beam_sweep_measurements.csv": {
            "RunId": "run-1", "TrialId": "1", "Direction": "DL",
            "SelectedBeamId": "1", "MeasurementSource": "air_interface_trial_row",
            "SourceRowsHash": "c" * 64, "Status": "pass", "FailureReason": "",
        },
        "beamforming/csv/mimo_oracle_guard.csv": {
            "RunId": "run-1", "Direction": "DL", "TrialId": "1",
            "CellId": "1", "UEId": "3", "Stage": "effective_rank_derivation",
            "OracleFieldName": "ConfiguredRank", "WasAccessed": "0",
            "Allowed": "0", "Violation": "0", "Status": "pass",
            "FailureReason": "",
        },
        "beamforming/csv/precoder_evidence.csv": {
            "RunId": "run-1", "TrialId": "1", "Direction": "DL",
            "PrecoderId": "matrix_sha256:" + "b" * 64, "PMI": "0",
            "AppliedPrecoderMatrixSHA256": "b" * 64,
            "EvidenceType": "pmi_and_applied_matrix",
            "PrecoderSource": "air_interface_trial_applied_precoder_matrix_sha256",
            "PrecodingActive": "1", "SourceRowsHash": "c" * 64,
            "Status": "pass", "FailureReason": "",
        },
    }


def test_mimo_companion_semantics_reconcile_all_direct_rank_derivatives() -> None:
    _raw, rank = _mimo_source_and_rank_row()
    summary = _mimo_configured_effective_row()
    checks = _audit_mimo_configured_effective_table(
        "beamforming/csv/mimo_configured_vs_effective.csv",
        list(summary), [summary], [rank],
    )
    assert all(check.passed for check in checks), [check.details for check in checks]

    layer = {
        "RunId": "run-1", "TrialId": "1", "CellId": "1", "UEId": "3",
        "Direction": "DL", "Slot": "2", "LayerIndex": "1",
        "CodewordIndex": "1", "DMRSPort": "0", "PostEqSINRdB": "8.5",
        "EVMdB": "-20", "ChannelEstimateNMSEdB": "-30", "LLRMeanAbs": "5",
        "DecodeCrcPass": "0", "BER": "0.1", "BLERContribution": "1",
        "Status": "pass",
    }
    checks = _audit_mimo_layer_metrics_table(
        "beamforming/csv/mimo_layer_metrics.csv", list(layer), [layer], [rank]
    )
    assert all(check.passed for check in checks), [check.details for check in checks]

    for path, row in _mimo_companion_rows().items():
        checks = _audit_mimo_per_trial_companion(path, list(row), [row], [rank])
        assert all(check.passed for check in checks), [check.details for check in checks]

    codebook = {
        "RunId": "run-1", "Direction": "DL", "BeamId": "1",
        "WeightVectorHash": "d" * 64, "SourceRowsHash": "c" * 64,
        "Status": "pass", "FailureReason": "",
    }
    checks = _audit_mimo_beam_codebook_table(
        "beamforming/csv/beam_codebook.csv", list(codebook), [codebook], [rank]
    )
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_mimo_summary_accepts_causal_bootstrap_before_complete_shared_mu_group() -> None:
    _raw, bootstrap = _mimo_source_and_rank_row()
    bootstrap.update({
        "UEId": "1", "TrialId": "1", "MUExecutionRequired": "1",
        "RequiredMUExecutionMode": "shared_slot_waveform_superposition",
        "MUMIMOEnabled": "0", "MUMIMOGroupSize": "1",
        "MUMIMOGroupId": "", "MUExecutionMatch": "0",
        "PRBStart": "0", "PRBCount": "24", "SymbolStart": "2",
        "NumSymbols": "12",
    })
    mu_ue1 = dict(bootstrap)
    mu_ue1.update({
        "TrialId": "2", "UEId": "1", "MUMIMOEnabled": "1",
        "MUMIMOGroupSize": "2", "MUMIMOGroupId": "7",
        "MUExecutionMatch": "1",
    })
    mu_ue2 = dict(mu_ue1)
    mu_ue2.update({"TrialId": "3", "UEId": "2"})
    rank_rows = [bootstrap, mu_ue1, mu_ue2]

    summary = _mimo_configured_effective_row()
    summary.update({
        "StrictEligibleRowCount": "3", "RuntimeTrialCount": "3",
        "ExactMatchRowCount": "3", "ExactMatchPercent": "1",
        "ExactSpatialMatchRowCount": "3", "ExactSpatialMatchPercent": "1",
        "ExactOperatingPointMatchRowCount": "3",
        "ExactOperatingPointMatchPercent": "1",
        "AdaptivePolicyMatchRowCount": "3", "AdaptivePolicyMatchPercent": "1",
        "ExecutionContractMatchRowCount": "3",
        "ExecutionContractMatchPercent": "1",
        "MUExecutionRequired": "1", "RequiredMUUserCount": "2",
        "RequiredMUExecutionMode": "shared_slot_waveform_superposition",
        "MUExecutedTrialRowCount": "2", "MUExecutedDistinctGroupCount": "1",
        "MUExecutionMatch": "1", "MUExecutionFailureReason": "",
        "ScenarioObjectivePass": "1", "Status": "pass", "FailureReason": "",
    })
    checks = _audit_mimo_configured_effective_table(
        "beamforming/csv/mimo_configured_vs_effective.csv",
        list(summary), [summary], rank_rows,
    )
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_mimo_companion_semantics_reject_corrupt_derived_values() -> None:
    _raw, rank = _mimo_source_and_rank_row()
    summary = _mimo_configured_effective_row()
    summary["ExactMatchRowCount"] = "0"
    checks = _audit_mimo_configured_effective_table(
        "beamforming/csv/mimo_configured_vs_effective.csv",
        list(summary), [summary], [rank],
    )
    assert "ExactMatchRowCount_mismatch" in next(
        check.details for check in checks if not check.passed
    )

    layer = {
        "RunId": "run-1", "TrialId": "1", "CellId": "1", "UEId": "3",
        "Direction": "DL", "Slot": "2", "LayerIndex": "1",
        "CodewordIndex": "1", "DMRSPort": "0", "PostEqSINRdB": "8.5",
        "EVMdB": "-20", "ChannelEstimateNMSEdB": "-30", "LLRMeanAbs": "5",
        "DecodeCrcPass": "0", "BER": "0.1", "BLERContribution": "0",
        "Status": "pass",
    }
    checks = _audit_mimo_layer_metrics_table(
        "beamforming/csv/mimo_layer_metrics.csv", list(layer), [layer], [rank]
    )
    assert "BLERContribution_not_crc_inverse" in next(
        check.details for check in checks if not check.passed
    )

    companions = _mimo_companion_rows()
    companions["beamforming/csv/beam_sweep_measurements.csv"]["SelectedBeamId"] = "2"
    companions["beamforming/csv/mimo_oracle_guard.csv"]["Violation"] = "1"
    companions["beamforming/csv/precoder_evidence.csv"]["AppliedPrecoderMatrixSHA256"] = "e" * 64
    expected_tokens = {
        "beamforming/csv/beam_sweep_measurements.csv": "SelectedBeamId_not_rank_source",
        "beamforming/csv/mimo_oracle_guard.csv": "Violation_formula_mismatch",
        "beamforming/csv/precoder_evidence.csv": "matrix_hash_not_rank_source",
    }
    for path, row in companions.items():
        checks = _audit_mimo_per_trial_companion(path, list(row), [row], [rank])
        assert expected_tokens[path] in next(
            check.details for check in checks if not check.passed
        )

    codebook = {
        "RunId": "run-1", "Direction": "DL", "BeamId": "2",
        "WeightVectorHash": "d" * 64, "SourceRowsHash": "c" * 64,
        "Status": "pass", "FailureReason": "",
    }
    checks = _audit_mimo_beam_codebook_table(
        "beamforming/csv/beam_codebook.csv", list(codebook), [codebook], [rank]
    )
    assert "direction_beam_set_mismatch" in next(
        check.details for check in checks if not check.passed
    )


def _strict_mimo_config_row() -> dict[str, str]:
    return {
        "RunId": "run-1", "ScenarioName": "scenario-1", "Direction": "DL",
        "CellId": "NaN", "UEId": "NaN", "NCellID": "1", "NSizeGrid": "273",
        "SubcarrierSpacingKHz": "30", "PhysicalTxAntennaCount": "2",
        "PhysicalRxAntennaCount": "2", "TxRFChainCount": "2",
        "RxRFChainCount": "2", "TxAntennaPortCount": "1",
        "RxAntennaPortCount": "2", "FullElementDomainRequired": "0",
        "DMRSPorts": "0", "DMRSPortCount": "1", "ConfiguredRank": "1",
        "ConfiguredLayers": "1", "ConfiguredCodewords": "1",
        "ConfiguredModulation": "16QAM", "ConfiguredMCS": "10",
        "ConfiguredInitialMCS": "10", "ConfiguredMaximumMCS": "10",
        "ConfiguredMCSSelectionPolicy": "fixed", "ConfiguredMUMIMOEnabled": "0",
        "ConfiguredMUUsersPerPRB": "2", "ConfiguredMUMIMOLeakageThreshold_dB": "-15",
        "ConfiguredMUMIMOExecutionMode": "none", "ConfiguredMCSTable": "qam64_table1",
        "ConfiguredTransmissionScheme": "nonCodebook", "CodebookType": "type1",
        "CodebookMode": "type1_su_mimo", "PrecodingMode": "explicit-wideband",
        "ConfiguredPMI": "0", "FixedAnchorMode": "1", "AdaptiveMode": "0",
        "RankSelectionSource": "fixed_anchor", "PrecoderSelectionSource": "configured_pmi",
        "BeamSelectionSource": "fixed_first_beam", "StrictUnsupportedReason": "",
        "ConfigHash": "d" * 64, "Status": "pass", "RuntimePopulated": "1",
        "RuntimeTrialCount": "1", "RuntimeRank2Fraction": "0",
        "RuntimeExactMatchFraction": "1",
        "RuntimeEvidenceSource": "rank_layer_trials_from_air_interface_raw_trials",
        "EvidenceClass": "CONFIGURATION_WITH_DIRECT_RUNTIME_TRIAL_EVIDENCE",
    }


def _mimo_validation_rows(config: dict[str, str]) -> list[dict[str, str]]:
    rules = (
        "physical_antenna_counts_present", "antenna_ports_present",
        "configured_rank_supported_by_ports", "configured_layers_supported_by_ports",
        "dmrs_ports_cover_layers", "unsupported_codebook_modes_fail_closed",
    )
    return [{
        "RunId": config["RunId"], "ScenarioName": config["ScenarioName"],
        "Direction": config["Direction"], "ValidationRule": rule, "Pass": "1",
        "Status": "pass", "FailureReason": "", "ConfigHash": config["ConfigHash"],
    } for rule in rules]


def _antenna_array_row(config: dict[str, str]) -> dict[str, str]:
    return {
        "RunId": "run-1", "ScenarioName": "scenario-1", "Direction": "DL",
        "ArrayGeometryId": "scenario_config_array_counts",
        "PhysicalTxAntennaCount": "2", "PhysicalRxAntennaCount": "2",
        "TxRFChainCount": "2", "RxRFChainCount": "2",
        "TxAntennaPortCount": "1", "RxAntennaPortCount": "2",
        "ObservedTxPortCount": "2", "ObservedRxAntennaCount": "2",
        "RuntimePopulated": "1", "FullElementDomainRequired": "0",
        "ExpectedRuntimeTxCount": "1", "ExpectedRuntimeRxCount": "2",
        "ExactRuntimeAntennaMatch": "1", "ObservedPhysicalTxAntennaCount": "2",
        "ObservedPhysicalRxAntennaCount": "2", "ObservedLogicalTxPortCount": "1",
        "ObservedLogicalRxBranchCount": "2", "LogicalPortLayerMatch": "1",
        "RuntimeAntennaObjectCreated": "1",
        "ChannelUsesSameRuntimeAntennaAssumptions": "0",
        "NominalCapabilityOnly": "0",
        "EvidenceClass": "CONFIGURATION_WITH_DIRECT_RUNTIME_TRIAL_EVIDENCE",
        "RuntimeEvidenceSource": "rank_layer_trials_from_air_interface_raw_trials",
        "SourceHash": config["ConfigHash"], "Status": "pass", "FailureReason": "",
    }


def _antenna_port_row() -> dict[str, str]:
    return {
        "RunId": "run-1", "ScenarioName": "scenario-1", "Direction": "DL",
        "TxAntennaPortCount": "1", "RxAntennaPortCount": "2", "DMRSPorts": "0",
        "DMRSPortCount": "1", "ConfiguredLayers": "1",
        "ObservedTransmittedLayers": "1", "ObservedEffectiveDecodedLayers": "0",
        "MappingEvidenceSource": "air_interface/csv/dl_pdsch_trials.csv",
        "SourceRowsHash": "c" * 64, "Status": "pass", "FailureReason": "",
    }


def _beam_primary_and_output() -> tuple[dict[str, str], dict[str, str]]:
    raw, _rank = _mimo_source_and_rank_row()
    raw.update({
        "RunTag": "run-1", "ConfigHash": "a" * 64, "RNTI": "3", "CellID": "1",
        "ConfiguredBeamSelectionStrategy": "fixed_first_beam",
        "BeamSelectionStrategy": "fixed_first_beam", "SelectedBeamIndex": "1",
        "BestBeamIndex": "1", "BeamHit": "1", "RequestedBeamIndexSet": "1",
        "RequestedBeamTruthClassification": "requested_reference",
        "PrecoderSource": "pmi-codebook", "AppliedPrecoderSource": "pmi-codebook",
        "RequestedPrecoderPMI": "0",
        "RequestedPrecoderPMITruthClassification": "requested_reference",
        "AppliedPrecoderPMI": "0", "AppliedPrecoderPMIType": "type1",
        "AppliedPrecoderCodebookMode": "type1_su_mimo",
        "RequestedVsAppliedPrecoderPMIMatchStatus": "requested_matches_runtime_applied",
        "BeamformingApplied": "1", "AppliedBeamIndexSet": "1",
        "AppliedBeamApplicationSource": "pmi-codebook",
        "AppliedBeamTruthClassification": "applied_runtime_value",
        "AppliedPrecoderPMIApplicationSource": "pmi-codebook",
        "AppliedPrecoderPMITruthClassification": "applied_runtime_value",
        "PrecodingMode": "explicit-wideband",
        "PrecodingApplicationStage": "nrPDSCHPrecode_before_RE_mapping",
        "PrecodingActive": "1", "ExplicitBeamWeightsApplied": "1",
        "TransformPrecodingApplied": "0", "PrecodingNumPorts": "1",
        "PrecodingNumLayers": "1", "PrecodingMatrixRows": "1",
        "PrecodingMatrixCols": "1", "QCLAccuracy": "1",
    })
    output = {
        "timestamp_sim_ms": "NaN", "frame": "1", "slot": "2", "direction": "DL",
        "ue_id": "3", "rnti": "3", "cell_id": "1",
        "configured_beam_selection_strategy": "fixed_first_beam",
        "beam_selection_strategy": "fixed_first_beam", "selected_beam_index": "1",
        "best_beam_index": "1", "beam_hit": "1", "requested_beam_index_set": "1",
        "requested_beam_truth_classification": "requested_reference",
        "precoder_source": "pmi-codebook", "applied_precoder_source": "pmi-codebook",
        "requested_precoder_pmi": "0",
        "requested_precoder_pmi_truth_classification": "requested_reference",
        "applied_precoder_pmi": "0", "applied_precoder_pmi_type": "type1",
        "applied_precoder_codebook_mode": "type1_su_mimo",
        "requested_vs_applied_precoder_pmi_match_status": "requested_matches_runtime_applied",
        "beamforming_applied": "1", "applied_beam_index_set": "1",
        "applied_beam_application_source": "pmi-codebook",
        "applied_beam_truth_classification": "applied_runtime_value",
        "applied_precoder_pmi_application_source": "pmi-codebook",
        "applied_precoder_pmi_truth_classification": "applied_runtime_value",
        "precoding_mode": "explicit-wideband",
        "precoding_application_stage": "nrPDSCHPrecode_before_RE_mapping",
        "precoding_active": "1", "explicit_beam_weights_applied": "1",
        "transform_precoding_applied": "0", "precoding_num_ports": "1",
        "precoding_num_layers": "1", "precoding_matrix_rows": "1",
        "precoding_matrix_cols": "1", "qcl_accuracy": "1",
        "qcl_type": "", "qcl_source_rs": "", "tci_state_id": "",
        "unified_tci_state_id": "", "tci_validity_timer_slots": "",
        "qcl_status": "runtime_qcl_accuracy_measured",
        "tci_status": "not_materialized_in_active_truth_path",
        "near_field_status": "not_materialized_in_active_truth_path",
        "runtime_evidence": "persisted_air_interface_trial_row",
        "source_artifact_ref": "air_interface/csv/dl_pdsch_trials.csv",
        "run_tag": "run-1", "scenario_id": "scenario-1", "config_hash": "a" * 64,
        "code_commit": "1" * 40, "seed": "1",
        "producer_module": "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildBeamPrecoderTable",
        "status_code": "implemented", "status_classification": "runtime_beam_precoder_trial_rows",
        "derived_flag": "0", "active_flag": "1",
    }
    return raw, output


def _beam_aggregate_rows() -> tuple[dict[str, str], dict[str, str], dict[str, str]]:
    analytics = {
        "direction": "DL", "cell_id": "1", "ue_id": "3", "trial_row_count": "1",
        "beamforming_applied_count": "1", "runtime_applied_beam_rows": "1",
        "runtime_applied_pmi_rows": "1", "beam_hit_rate": "1",
        "mean_precoding_ports": "1", "mean_precoding_layers": "1",
        "analytics_value_source": "beamforming/csv/beam_precoder_table.csv",
        "producer_module": "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildBeamformingAnalyticsTable",
        "status_code": "implemented", "status_classification": "derived_beamforming_analytics",
        "source_artifact_ref": "beamforming/csv/beam_precoder_table.csv",
        "derived_flag": "1", "active_flag": "1",
    }
    utilization = {
        "direction": "DL", "cell_id": "1", "rank_or_layer_count": "1",
        "trial_row_count": "1", "utilization_fraction": "1",
        "source_artifact_ref": "beamforming/csv/beam_precoder_table.csv",
        "producer_module": "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildMIMORankUtilizationTable",
        "status_code": "implemented", "status_classification": "derived_mimo_rank_utilization",
        "derived_flag": "1", "active_flag": "1",
    }
    histogram = dict(utilization)
    histogram.update({
        "histogram_definition": "rank/layer usage histogram from runtime beam-precoder rows",
        "producer_module": "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildRankLayerUsageHistogram",
        "status_classification": "derived_rank_layer_histogram",
    })
    return analytics, utilization, histogram


def test_antenna_audit_checks_each_adaptive_trial_not_bootstrap_layers() -> None:
    for direction in ("DL", "UL"):
        config = _strict_mimo_config_row()
        config.update({"Direction": direction, "TxAntennaPortCount": "4"})
        array = _antenna_array_row(config)
        array.update({
            "Direction": direction, "TxAntennaPortCount": "4",
            "ExpectedRuntimeTxCount": "4", "ObservedLogicalTxPortCount": "4",
            "ObservedLogicalRxBranchCount": "4",
        })
        ranks = []
        for layers in (1, 2, 4):
            _, rank = _mimo_source_and_rank_row()
            rank.update({
                "Direction": direction, "TransmittedLayers": str(layers),
                "LogicalTxPortCount": "4", "LogicalRxBranchCount": "4",
                "AntennaRuntimeObjectCreated": "1",
                "ChannelUsesSameRuntimeAntennaAssumptions": "0",
            })
            ranks.append(rank)
        checks = _audit_mimo_antenna_array_table(
            "beamforming/csv/antenna_array_config.csv", list(array), [array], ranks, [config]
        )
        assert all(check.passed for check in checks), [check.details for check in checks]
        # A single invalid trial must not disappear behind the valid modal count.
        for field, value in (
            ("LogicalTxPortCount", "1"), ("LogicalTxPortCount", "5"),
            ("LogicalRxBranchCount", "1"), ("LogicalRxBranchCount", "NaN"),
            ("TransmittedLayers", "1.5"), ("TransmittedLayers", "0"),
        ):
            corrupt = [dict(rank) for rank in ranks]
            corrupt[1][field] = value
            checks = _audit_mimo_antenna_array_table(
                "beamforming/csv/antenna_array_config.csv", list(array), [array], corrupt, [config]
            )
            failures = " | ".join(check.details for check in checks if not check.passed)
            assert "LogicalPortLayerMatch_formula_mismatch" in failures, (field, value, failures)


def test_runtime_dmrs_mapping_uses_every_measured_count_not_nominal_rank() -> None:
    config = _strict_mimo_config_row()
    mapping = _antenna_port_row()
    ranks = []
    for layers in (1, 2, 4):
        _, rank = _mimo_source_and_rank_row()
        rank.update({"TransmittedLayers": str(layers), "MeasuredDMRSPortCount": str(layers)})
        ranks.append(rank)
    # Modal transmitted count is still one. A deficient rank-four trial
    # must fail even though the old nominal/modal comparison would pass.
    checks = _audit_mimo_antenna_port_mapping_table(
        "beamforming/csv/antenna_port_mapping.csv", list(mapping), [mapping], ranks, [config]
    )
    assert all(check.passed for check in checks), [check.details for check in checks]
    adaptive = dict(mapping)
    adaptive["ObservedTransmittedLayers"] = "4"
    checks = _audit_mimo_antenna_port_mapping_table(
        "beamforming/csv/antenna_port_mapping.csv", list(adaptive), [adaptive], [ranks[-1]], [config]
    )
    assert all(check.passed for check in checks), [check.details for check in checks]
    for invalid in ("1", "1.5", "0", "NaN", "Inf", ""):
        corrupt = [dict(rank) for rank in ranks]
        corrupt[2]["MeasuredDMRSPortCount"] = invalid
        checks = _audit_mimo_antenna_port_mapping_table(
            "beamforming/csv/antenna_port_mapping.csv", list(mapping), [mapping], corrupt, [config]
        )
        failures = " | ".join(check.details for check in checks if not check.passed)
        assert "Status_formula_mismatch" in failures, (invalid, failures)


def test_runtime_dmrs_count_cannot_be_invented_by_rank_export() -> None:
    raw, rank = _mimo_source_and_rank_row()
    rank["MeasuredDMRSPortCount"] = "2"
    checks = _audit_mimo_rank_layer_table(
        "beamforming/csv/rank_layer_trials.csv", list(rank), [rank], {"DL": [raw]}
    )
    failures = " | ".join(check.details for check in checks if not check.passed)
    assert "MeasuredDMRSPortCount_not_primary_source" in failures


def test_dmrs_count_does_not_require_or_invent_port_identities() -> None:
    raw, rank = _mimo_source_and_rank_row()
    rank["DMRSPorts"] = ""
    checks = _audit_mimo_rank_layer_table(
        "beamforming/csv/rank_layer_trials.csv", list(rank), [rank], {"DL": [raw]}
    )
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_nominal_dmrs_audit_is_independent_of_adaptive_runtime_ports() -> None:
    for direction in ("DL", "UL"):
        config = _strict_mimo_config_row()
        config["Direction"] = direction
        validation = _mimo_validation_rows(config)
        configured = _mimo_configured_effective_row()
        configured["Direction"] = direction
        _, rank = _mimo_source_and_rank_row()
        rank.update({
            "Direction": direction, "DMRSPorts": "0|1|2|3",
            "TransmittedLayers": "4", "TransmittedRank": "4",
            "AdaptiveMode": "1", "FixedAnchorMode": "0",
        })
        config.update({"AdaptiveMode": "1", "FixedAnchorMode": "0"})
        checks = _audit_mimo_config_strict_table(
            "beamforming/csv/mimo_config_strict.csv", list(config), [config],
            [rank], [configured], validation,
        )
        assert all(check.passed for check in checks), [check.details for check in checks]
        for field, value in (
            ("DMRSPorts", ""), ("DMRSPorts", "0|0"), ("DMRSPorts", "1"),
            ("DMRSPorts", "0|1|2|3"), ("DMRSPortCount", "4"),
        ):
            corrupt = dict(config)
            corrupt[field] = value
            checks = _audit_mimo_config_strict_table(
                "beamforming/csv/mimo_config_strict.csv", list(corrupt), [corrupt],
                [rank], [configured], validation,
            )
            failures = " | ".join(check.details for check in checks if not check.passed)
            assert "nominal_DMRS_configuration_mismatch" in failures, (field, value, failures)


def test_remaining_mimo_tables_reconcile_config_rank_and_primary_trials() -> None:
    raw, rank = _mimo_source_and_rank_row()
    rank.update({
        "BSAntennaElements": "2", "UEAntennaElements": "2",
        "BSAntennaNumPorts": "1", "UEAntennaNumPorts": "2",
        "AntennaRuntimeObjectCreated": "1",
        "ChannelUsesSameRuntimeAntennaAssumptions": "0",
    })
    config = _strict_mimo_config_row()
    validation = _mimo_validation_rows(config)
    configured = _mimo_configured_effective_row()
    array = _antenna_array_row(config)
    port = _antenna_port_row()
    beam_raw, beam = _beam_primary_and_output()
    analytics, utilization, histogram = _beam_aggregate_rows()
    invocations = (
        _audit_mimo_antenna_array_table("beamforming/csv/antenna_array_config.csv", list(array), [array], [rank], [config]),
        _audit_mimo_antenna_port_mapping_table("beamforming/csv/antenna_port_mapping.csv", list(port), [port], [rank], [config]),
        _audit_mimo_config_validation_table("beamforming/csv/mimo_config_validation.csv", list(validation[0]), validation, [config]),
        _audit_mimo_config_strict_table("beamforming/csv/mimo_config_strict.csv", list(config), [config], [rank], [configured], validation),
        _audit_beam_precoder_table("beamforming/csv/beam_precoder_table.csv", list(beam), [beam], {"DL": [beam_raw], "UL": []}),
        _audit_beamforming_analytics_table("beamforming/csv/beamforming_analytics_table.csv", list(analytics), [analytics], [beam]),
        _audit_mimo_rank_coverage_table("beamforming/csv/mimo_rank_utilization_table.csv", list(utilization), [utilization], [beam], histogram=False),
        _audit_mimo_rank_coverage_table("beamforming/csv/rank_layer_usage_histogram.csv", list(histogram), [histogram], [beam], histogram=True),
    )
    for checks in invocations:
        assert all(check.passed for check in checks), [check.details for check in checks]


def test_remaining_mimo_tables_reject_corrupt_values_in_every_contract() -> None:
    _raw, rank = _mimo_source_and_rank_row()
    rank.update({
        "BSAntennaElements": "2", "UEAntennaElements": "2",
        "BSAntennaNumPorts": "1", "UEAntennaNumPorts": "2",
        "AntennaRuntimeObjectCreated": "1",
        "ChannelUsesSameRuntimeAntennaAssumptions": "0",
    })
    config = _strict_mimo_config_row()
    validation = _mimo_validation_rows(config)
    configured = _mimo_configured_effective_row()
    array = _antenna_array_row(config)
    array["ExactRuntimeAntennaMatch"] = "0"
    port = _antenna_port_row()
    port["ObservedTransmittedLayers"] = "2"
    validation_corrupt = [dict(row) for row in validation]
    validation_corrupt[0]["Pass"] = "0"
    config_corrupt = dict(config)
    config_corrupt["RuntimeTrialCount"] = "99"
    beam_raw, beam = _beam_primary_and_output()
    beam["selected_beam_index"] = "2"
    analytics, utilization, histogram = _beam_aggregate_rows()
    analytics["beam_hit_rate"] = "0"
    utilization["utilization_fraction"] = "0.5"
    histogram["trial_row_count"] = "2"
    cases = (
        (_audit_mimo_antenna_array_table("beamforming/csv/antenna_array_config.csv", list(array), [array], [rank], [config]), "ExactRuntimeAntennaMatch_formula_mismatch"),
        (_audit_mimo_antenna_port_mapping_table("beamforming/csv/antenna_port_mapping.csv", list(port), [port], [rank], [config]), "ObservedTransmittedLayers_not_rank_source"),
        (_audit_mimo_config_validation_table("beamforming/csv/mimo_config_validation.csv", list(validation_corrupt[0]), validation_corrupt, [config]), "pass_status_formula_mismatch"),
        (_audit_mimo_config_strict_table("beamforming/csv/mimo_config_strict.csv", list(config_corrupt), [config_corrupt], [rank], [configured], validation), "runtime_population_mismatch"),
        (_audit_beam_precoder_table("beamforming/csv/beam_precoder_table.csv", list(beam), [beam], {"DL": [beam_raw], "UL": []}), "selected_beam_index_not_primary_source"),
        (_audit_beamforming_analytics_table("beamforming/csv/beamforming_analytics_table.csv", list(analytics), [analytics], [_beam_primary_and_output()[1]]), "beam_hit_rate_aggregate_mismatch"),
        (_audit_mimo_rank_coverage_table("beamforming/csv/mimo_rank_utilization_table.csv", list(utilization), [utilization], [_beam_primary_and_output()[1]], histogram=False), "utilization_fraction_aggregate_mismatch"),
        (_audit_mimo_rank_coverage_table("beamforming/csv/rank_layer_usage_histogram.csv", list(histogram), [histogram], [_beam_primary_and_output()[1]], histogram=True), "trial_row_count_aggregate_mismatch"),
    )
    for checks, token in cases:
        failures = " | ".join(check.details for check in checks if not check.passed)
        assert token in failures


def _frc_point_row() -> dict[str, str]:
    return {
        "EntryId": "dl_rank4_tdla",
        "FRC": "R.PDSCH.1-2.4 FDD",
        "Condition": "TDL-A 30ns 10Hz",
        "Direction": "DL",
        "PhysicalChannel": "PDSCH",
        "Profile": "diagnostic",
        "Metric": "fraction_max_throughput",
        "RequiredSNR_dB": "15.6",
        "TargetFraction": "0.7",
        "SNR_dB": "15.6",
        "RequiredPoint": "1",
        "ExperimentSeed": "38104",
        "MetricEstimate": "0.8",
        "ConfidenceLower": "0.741744938411775",
        "ConfidenceUpper": "0.897599323883307",
        "OneSidedLower": "0.754273569428739",
        "OneSidedUpper": "1",
        "TransportBlocks": "4",
        "DeliveredTransportBlocks": "4",
        "FailedTransportBlocks": "0",
        "Transmissions": "5",
        "FailedTransmissionAttempts": "1",
        "PointEstimatePass": "1",
        "ObservedConfidenceBoundSupportsPass": "1",
        "ConfidenceSupportsPass": "0",
        "ConfidenceQualificationEligible": "0",
        "ConfidenceMethod": "clopper_pearson",
        "StopReason": "diagnostic_transport_block_cap",
        "StandardDocument": "TS 38.101-4",
        "StandardVersion": "18.7.0",
        "StandardRelease": "18",
        "StandardSourceURL": "https://www.3gpp.org/ftp/Specs/archive/38_series/38.101-4/",
        "FRCDefinitionClause": "Annex A",
        "FRCDefinitionTable": "Table A.3.2.2-1",
        "RequirementClause": "Clause 7.3",
        "RequirementTables": "Table 7.3.2-1",
        "ConfidenceLevel": "0.95",
        "RequiredQualificationTransportBlocks": "9604",
        "ConfidenceSamplingPlan": "one_sided_binomial",
        "StatisticalUnit": "transport_block",
        "ConfiguredModulation": "64QAM",
        "ConfiguredMCSTable": "qam64_table1",
        "ConfiguredMCSIndex": "20",
        "ConfiguredTargetCodeRate": "0.6015625",
        "EffectiveTargetCodeRate": "0.6015625",
        "ConfiguredTBSBits": "24456",
        "EffectiveTBSBits": "24456",
        "ConfiguredCodedBitsPerSlot": "40640",
        "EffectiveCodedBitsPerSlot": "40640",
        "ConfiguredLayers": "4",
        "ConfiguredTxAntennas": "4",
        "ConfiguredRxAntennas": "4",
        "EffectiveLayers": "4",
        "EffectiveTxPorts": "4",
        "NoiseVarSource": "waveform_awgn_variance",
        "DecoderNoiseVar": "0.0123",
        "PostEqSINR_dB": "14.8",
        "LastTBReceiverOk": "1",
        "LastTBCRCError": "0",
        "ChannelExecutionMode": "streamed_complete_sequence",
        "ChannelChunkSlots": "1",
        "ChannelChunkSamples": "15360",
        "ChannelCallCount": "21",
        "ChannelMaximumInputRows": "15360",
        "ChannelFullSequenceProcessed": "1",
        "ExecutionBackend": "matlab_5g_toolbox_waveform",
        "ApproximationMode": "none",
        "Source": "sixgr.conformance.runFRCPoint",
        "FullStandardExecutionExact": "0",
        "DataChannelExact": "1",
        "ProxyUsed": "0",
        "FallbackUsed": "0",
        "EvidenceClass": "SELECTED_DATA_CHANNEL_TRUTH_EXECUTION",
        "CatalogSHA256": "a" * 64,
    }


def test_frc_point_semantics_accept_exact_runtime_truth() -> None:
    row = _frc_point_row()
    checks = _audit_frc_point_table(
        "reports/csv/frc_reference_points.csv", list(row), [row]
    )
    assert checks
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_frc_point_semantics_reject_count_and_effective_rank_corruption() -> None:
    row = _frc_point_row()
    row["DeliveredTransportBlocks"] = "5"
    row["EffectiveLayers"] = "1"
    checks = _audit_frc_point_table(
        "reports/csv/frc_reference_points.csv", list(row), [row]
    )
    failed = {check.check_id: check.details for check in checks if not check.passed}
    assert "transport_block_arithmetic_mismatch" in failed[
        "metric_confidence_and_tb_arithmetic"
    ]
    assert "configured_effective_phy_mismatch" in failed[
        "configured_effective_phy_and_receiver"
    ]


def test_frc_only_run_is_not_skipped_by_semantic_audit(tmp_path: Path) -> None:
    row = _frc_point_row()
    _write_rows(tmp_path / "reports/csv/frc_reference_points.csv", [row])
    audit = audit_run(tmp_path)
    assert audit["summary"][0]["semantic_check_count"] >= 4
    assert audit["summary"][0]["semantic_required_failure_count"] == 0
    assert all(check["passed"] for check in audit["canonical_csv_semantic_audit"])
    assert all(
        check["category"] == "frc_reference"
        for check in audit["canonical_csv_semantic_audit"]
    )


def test_unfinished_control_only_run_is_audited_without_data_or_summary(tmp_path: Path) -> None:
    row = {
        "ReceiverHestSINR_dB": "12.26", "ReceiverHestSINRApplicable": "0",
        "ChannelEstimateAvailable": "1", "SourceClassification": "active_integrated",
    }
    for path in ("air_interface/csv/srs_trials.csv", "control/csv/srs_trials.csv"):
        _write_rows(tmp_path / path, [row])
    audit = audit_run(tmp_path)
    checks = audit["canonical_csv_semantic_audit"]
    assert audit["summary"][0]["semantic_check_count"] > 0
    assert not audit["summary"][0]["ok"]
    assert any(check["check_id"] == "run_completion_summary_present" and not check["passed"]
               for check in checks)
    for path in ("air_interface/csv/srs_trials.csv", "control/csv/srs_trials.csv"):
        inconsistent = [check for check in checks if check["artifact_path"] == path
                        and check["check_id"] == "receiver_sinr_applicability"]
        assert len(inconsistent) == 1 and not inconsistent[0]["passed"]
        assert "finite_receiver_sinr_marked_not_applicable" in inconsistent[0]["details"]


def test_unfinished_declared_control_component_does_not_invent_data_requirement(tmp_path: Path) -> None:
    config = tmp_path / "meta/scenario_config_resolved.json"
    config.parent.mkdir(parents=True)
    config.write_text(json.dumps({"scenario": {"runner_profile": "srs_strict_validation"}}),
                      encoding="utf-8")
    _write_rows(tmp_path / "control/csv/srs_trials.csv", [{"ReceiverHestSINR_dB": "12.26"}])
    checks = audit_run(tmp_path)["canonical_csv_semantic_audit"]
    primary = [check for check in checks if check["category"] == "primary_link"]
    assert primary and all(not check["required"] for check in primary)
    assert any(check["check_id"] == "run_completion_summary_present" and not check["passed"]
               for check in checks)


def test_pucch_only_observation_is_not_skipped(tmp_path: Path) -> None:
    path = "air_interface/csv/pucch_trials.csv"
    _write_rows(tmp_path / path, [{"ReceiverHestSINR_dB": "8.5", "FallbackFlag": "1"}])
    checks = audit_run(tmp_path)["canonical_csv_semantic_audit"]
    assert any(check["artifact_path"] == path and "fallback_or_placeholder" in check["details"]
               and not check["passed"] for check in checks)


def test_receiver_sinr_applicability_is_not_signal_detection() -> None:
    row = {"ReceiverHestSINR_dB": "12", "ReceiverHestSINRApplicable": "1",
           "ChannelEstimateAvailable": "1", "DetectionSuccess": "0"}
    checks = _audit_control_table("control/csv/srs_trials.csv", list(row), [row])
    applicability = next(check for check in checks if check.check_id == "receiver_sinr_applicability")
    assert applicability.passed
    for changes, reason in (
        ({"ReceiverHestSINR_dB": "NaN"}, "applicable_receiver_sinr_missing"),
        ({"ChannelEstimateAvailable": "0"}, "receiver_sinr_without_channel_estimate"),
        ({"ReceiverHestSINRApplicable": "unknown"}, "invalid_receiver_sinr_applicability"),
    ):
        changed = row | changes
        check = next(check for check in _audit_control_table("control/csv/srs_trials.csv", list(changed), [changed])
                     if check.check_id == "receiver_sinr_applicability")
        assert not check.passed and reason in check.details


def test_pdcch_component_semantics_require_pdcch_not_data_trials(tmp_path: Path) -> None:
    scenario_hash = "a" * 64
    _write_rows(
        tmp_path / "reports/csv/scenario_summary.csv",
        [{
            "RunnerProfile": "ctrl6gr_pdcch_study",
            "RunCompletion": "completed",
            "RunID": "run-1",
            "RunTag": "run-1",
            "ScenarioID": "pdcch-study",
            "ConfigHash": scenario_hash,
            "ExecutionID": "execution-1",
            "EffectiveDLTrialCount": "0",
            "EffectiveULTrialCount": "0",
        }],
    )
    _write_rows(
        tmp_path / "air_interface/csv/pdcch_trials.csv",
        [{
            "RunID": "run-1",
            "RunTag": "run-1",
            "ScenarioID": "pdcch-study",
            "ScenarioConfigHash": scenario_hash,
            "ExecutionID": "execution-1",
            "EvidenceScope": "in_path",
            "EstimatedSINR_dB": "12.5",
            "CRCPass": "1",
            "FalseAlarmFlag": "0",
        }],
    )
    binding_path = tmp_path / "reports/csv/pdcch_grant_binding_evidence.csv"
    binding_path.parent.mkdir(parents=True, exist_ok=True)
    binding_path.write_text(
        "Direction,Slot,UEIndex,BindingStatus,FailureCode\n",
        encoding="utf-8",
    )

    audit = audit_run(tmp_path)
    checks = audit["canonical_csv_semantic_audit"]
    link_checks = [row for row in checks if row["category"] == "primary_link"]
    assert link_checks
    assert all(not row["required"] for row in link_checks)
    pdcch_checks = [
        row for row in checks if row["artifact_path"] == "air_interface/csv/pdcch_trials.csv"
    ]
    assert pdcch_checks
    assert all(row["passed"] for row in pdcch_checks), pdcch_checks
    binding_checks = [
        row for row in checks
        if row["artifact_path"] == "reports/csv/pdcch_grant_binding_evidence.csv"
    ]
    assert binding_checks
    assert all(
        not row["required"] and not row["evaluated"] and not row["details"]
        for row in binding_checks
    ), binding_checks


def test_prach_component_semantics_require_identity_but_not_full_link_outputs(
    tmp_path: Path,
) -> None:
    scenario_hash = "b" * 64
    identity = {
        "RunID": "prach-run-1",
        "RunTag": "prach-run-1",
        "ScenarioID": "prach-component",
        "ScenarioConfigHash": scenario_hash,
        "ConfigHash": scenario_hash,
        "ExecutionID": "prach-execution-1",
    }
    _write_rows(
        tmp_path / "reports/csv/scenario_summary.csv",
        [{
            **identity,
            "RunnerProfile": "prach_detection",
            "RunCompletion": "completed",
            "EffectiveDLTrialCount": "0",
            "EffectiveULTrialCount": "0",
        }],
    )
    _write_rows(
        tmp_path / "air_interface/csv/prach_trials.csv",
        [{
            **identity,
            "DetectionMetric": "12.75",
            "Status": "PASS",
            "CRCPass": "1",
            "FalseAlarmFlag": "0",
            "MissDetectionFlag": "0",
        }],
    )
    # A generic finalizer may emit a fail-closed DUT row, but it is not a DUT
    # comparison claim for an independent PRACH component runner.
    _write_rows(
        tmp_path / "reports/csv/dut_reference_comparison.csv",
        [{"ReferenceAvailable": "0", "Pass": "0", "FailureReason": "not_applicable"}],
    )

    audit = audit_run(tmp_path)
    failures = [
        row for row in audit["canonical_csv_semantic_audit"]
        if row["required"] and (not row["evaluated"] or not row["passed"])
    ]
    incorrectly_required = [
        row for row in failures
        if row["artifact_path"] in {
            "reports/csv/dut_reference_comparison.csv",
            "reports/csv/lls_reference_comparison_summary.csv",
            "reports/csv/mcs_table_reference.csv",
            "reports/csv/cqi_table_reference.csv",
        }
        or row["check_id"] == "outcome_matches_phase7_and_rows_are_coherent"
    ]
    assert not incorrectly_required, incorrectly_required
    prach_checks = [
        row for row in audit["canonical_csv_semantic_audit"]
        if row["artifact_path"] == "air_interface/csv/prach_trials.csv"
    ]
    assert prach_checks
    assert all(row["passed"] for row in prach_checks), prach_checks


def _mu_check(direction: str, row: dict[str, str]):
    checks = _audit_link_table("trial.csv", list(row), [row], direction, 1)
    return next(check for check in checks if check.check_id == "mu_mimo_receiver_execution")


def _transport_check(row: dict[str, str]):
    checks = _audit_link_table("trial.csv", list(row), [row], "UL", 1)
    return next(
        check for check in checks
        if check.check_id == "transport_crc_ber_goodput_arithmetic"
    )


def _transport_row(*, retransmission: bool, crc_pass: bool) -> dict[str, str]:
    tbs = 1000
    offered = 0 if retransmission else tbs
    good = tbs if crc_pass else 0
    duration_ms = 1.0
    return {
        "Direction": "UL", "Frame": "1", "Slot": "2", "UEID": "1",
        "HARQRound": "2" if retransmission else "1",
        "ExecutionID": "execution-1", "TBSize_bits": str(tbs),
        "OfferedBits": str(offered), "GoodBits": str(good),
        "BitErrors": "0" if crc_pass else "100",
        "BitsCompared": str(tbs), "RawBER": "0" if crc_pass else "0.1",
        "CRCPass": "1" if crc_pass else "0",
        "AirInterfaceObservation_ms": str(duration_ms),
        "OfferedThroughput_Mbps": str(offered / duration_ms / 1000.0),
        "Goodput_Mbps": str(good / duration_ms / 1000.0),
        "TargetCodeRate": "0.5",
        "HARQIsRetransmission": "1" if retransmission else "0",
        "RV": "2" if retransmission else "0",
    }


def test_transport_accounting_accepts_zero_new_offered_bits_on_harq_retransmission() -> None:
    check = _transport_check(_transport_row(retransmission=True, crc_pass=True))
    assert check.passed, check.details


def test_transport_accounting_rejects_double_counted_harq_retransmission_offer() -> None:
    row = _transport_row(retransmission=True, crc_pass=False)
    row["OfferedBits"] = row["TBSize_bits"]
    row["OfferedThroughput_Mbps"] = "1"
    check = _transport_check(row)
    assert not check.passed
    assert "retransmission_offered_bits_nonzero" in check.details


def test_transport_accounting_rejects_new_data_offer_that_differs_from_tbs() -> None:
    row = _transport_row(retransmission=False, crc_pass=False)
    row["OfferedBits"] = "0"
    row["OfferedThroughput_Mbps"] = "0"
    check = _transport_check(row)
    assert not check.passed
    assert "new_data_offered_bits_not_tbs" in check.details


def test_dl_mu_requires_measured_joint_irc_processing_not_fake_combiner() -> None:
    row = {
        "MUMIMOEnabled": "1",
        "MUMIMOGroupSize": "2",
        "InterferenceContributorCount": "1",
        "FullInterfererChannelTruthUsed": "1",
        "InterferenceCovarianceAvailable": "1",
        "InterferenceCovarianceSource": (
            "oracle_separated_shared_slot_per_prb_symbol_"
            "contribution_grid_covariance"
        ),
        "EqualizerType": "MMSE-IRC",
        "MUMIMOReceiveProcessingApplied": "1",
        "MUMIMOReceiveProcessingStatus": "applied_oracle_separated_shared_slot_covariance_resource_selective_per_re_mmse_irc",
        "MUMIMOReceiveProcessingSource": "sixgr.phy.dl.PDSCH_Rx.EqualizationInfo",
        "MUMIMOReceiveProcessingModeApplied": "resource_selective_per_re_mmse_irc",
        "MUMIMOReceiverAlgorithmApplied": "MMSE-IRC",
        "MUMIMOReceiveCombinerApplied": "0",
        "MUMIMOReceiveCombinerStatus": "not_applicable_joint_per_re_mmse_irc_equalizer_no_separate_combiner",
    }
    check = _mu_check("DL", row)
    assert check.passed, check.details


def test_dl_mu_fails_without_applied_receiver_processing() -> None:
    row = {
        "MUMIMOEnabled": "1",
        "MUMIMOGroupSize": "2",
        "InterferenceContributorCount": "1",
        "FullInterfererChannelTruthUsed": "1",
        "InterferenceCovarianceAvailable": "1",
        "EqualizerType": "MMSE-IRC",
        "MUMIMOReceiveProcessingApplied": "0",
        "MUMIMOReceiveCombinerApplied": "0",
        "MUMIMOReceiveCombinerStatus": "not_applicable_joint_per_re_mmse_irc_equalizer_no_separate_combiner",
    }
    check = _mu_check("DL", row)
    assert not check.passed
    assert "mu_receive_processing_not_applied" in check.details


def _write_rows(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def _kpi_source_rows() -> list[dict[str, str]]:
    common = {
        "Direction": "DL",
        "UEIndex": "1",
        "RNTI": "1001",
        "HARQProcessId": "3",
        "NDI": "1",
        "Codeword": "0",
        "TBSize_bits": "1000",
        "AirInterfaceObservation_ms": "1",
        "GrantContextId": "shared-frozen-grant-context",
    }
    return [
        {
            **common,
            "TrialId": "1", "Frame": "1", "Slot": "1", "RV": "0",
            "NewDataFlag": "1", "RetransmissionFlag": "0",
            "CRCPass": "0", "GoodBits": "0",
        },
        {
            **common,
            "TrialId": "2", "Frame": "1", "Slot": "2", "RV": "2",
            "NewDataFlag": "0", "RetransmissionFlag": "1",
            "CRCPass": "1", "GoodBits": "1000",
        },
        {
            **common,
            "TrialId": "3", "Frame": "1", "Slot": "3", "RV": "0",
            "NewDataFlag": "1", "RetransmissionFlag": "0",
            "CRCPass": "1", "GoodBits": "1000",
        },
    ]


def _kpi_trace_rows(source_rows: list[dict[str, str]]) -> list[dict[str, str]]:
    keys = _kpi_transport_block_keys(source_rows, "DL")
    delivered_keys: set[str] = set()
    rows: list[dict[str, str]] = []
    for index, (source, key) in enumerate(zip(source_rows, keys), start=1):
        passed = source["CRCPass"] == "1"
        delivered = passed and float(source["GoodBits"]) > 0
        duplicate = delivered and key in delivered_keys
        first = delivered and not duplicate
        if delivered:
            delivered_keys.add(key)
        counted = float(source["GoodBits"]) if first else 0.0
        status = (
            "duplicate_delivery_not_counted" if duplicate else
            "first_success_delivery_counted" if first else "not_delivered"
        )
        rows.append({
            "RunId": "run-1", "Direction": "DL", "UEId": "1",
            "TransportBlockId": key, "Codeword": "0",
            "AttemptIndex": str(index), "RV": source["RV"], "NDI": "1",
            "NewDataFlag": source["NewDataFlag"],
            "RetransmissionFlag": source["RetransmissionFlag"],
            "ScheduleTime_s": "0", "AttemptStartTime_s": str(index - 1),
            "AttemptEndTime_s": str(index),
            "FirstSuccessTime_s": str(index) if first else "NaN",
            "DeliveryLatency_ms": "1000" if first else "NaN",
            "ScheduledBits": "1000", "TBCrcPass": source["CRCPass"],
            "DeliveredThisAttempt": "1" if delivered else "0",
            "FirstSuccessDelivery": "1" if first else "0",
            "DuplicateDelivery": "1" if duplicate else "0",
            "CountedGoodputBits": format(counted, ".15g"),
            "ScheduledResourceExposureSec": "0.001",
            "MeasurementWindowSec": "0.003",
            "DeliveryStatus": status, "Status": "pass", "FailureReason": "",
        })
    return rows


def _kpi_contribution_rows(
    source_rows: list[dict[str, str]], trace_rows: list[dict[str, str]]
) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for index, (source, trace) in enumerate(zip(source_rows, trace_rows), start=1):
        rows.append({
            "RunId": "run-1", "ScenarioName": "fixture",
            "KPIName": "DL_TB_Delivery_Goodput_Mbps",
            "FormulaId": "DL_TB_Delivery_Goodput_Mbps", "Direction": "DL",
            "SourceTablePath": "air_interface/csv/dl_pdsch_trials.csv",
            "SourceRowIndex": str(index), "CellId": "1", "UEId": "1",
            "TrialId": source["TrialId"], "Slot": source["Slot"],
            "Frame": source["Frame"],
            "TransportBlockId": trace["TransportBlockId"], "RV": source["RV"],
            "NDI": source["NDI"], "NewDataFlag": source["NewDataFlag"],
            "RetransmissionFlag": source["RetransmissionFlag"],
            "TBCrcPass": source["CRCPass"],
            "ScheduledBitsContribution": trace["ScheduledBits"],
            "DeliveredBitsContribution": trace["CountedGoodputBits"],
            "GoodputBitsContribution": trace["CountedGoodputBits"],
            "DurationContributionSec": "0.001",
            "MeasurementWindowContributionSec": "0.003",
            "ScheduleTime_s": "0", "AttemptStartTime_s": str(index - 1),
            "AttemptEndTime_s": str(index),
            "FirstSuccessTime_s": trace["FirstSuccessTime_s"],
            "DeliveryLatency_ms": trace["DeliveryLatency_ms"],
            "FirstSuccessDelivery": trace["FirstSuccessDelivery"],
            "DuplicateDelivery": trace["DuplicateDelivery"],
            "Included": "1", "Status": "pass",
        })
    return rows


def test_kpi_transport_block_identity_ignores_shared_grant_context() -> None:
    keys = _kpi_transport_block_keys(_kpi_source_rows(), "DL")
    assert keys[0] == keys[1]
    assert keys[2] != keys[1]
    assert all(key != "shared-frozen-grant-context" for key in keys)


def test_kpi_delivery_contract_recomputes_harq_identity_and_detects_corruption(
    tmp_path: Path,
) -> None:
    source_rows = _kpi_source_rows()
    trace_rows = _kpi_trace_rows(source_rows)
    _write_rows(tmp_path / "reports/csv/kpi_harq_delivery_trace_dl.csv", trace_rows)
    _write_rows(tmp_path / "reports/csv/kpi_tb_delivery_ledger_dl.csv", trace_rows)
    _write_rows(
        tmp_path / "reports/csv/kpi_row_contributions_dl.csv",
        _kpi_contribution_rows(source_rows, trace_rows),
    )
    checks = _audit_kpi_delivery_direction(
        tmp_path, "DL", source_rows, "air_interface/csv/dl_pdsch_trials.csv"
    )
    assert len(checks) == 6
    assert all(check.passed for check in checks), [check.details for check in checks]

    corrupt = [dict(row) for row in trace_rows]
    corrupt[2]["TransportBlockId"] = source_rows[2]["GrantContextId"]
    _write_rows(tmp_path / "reports/csv/kpi_harq_delivery_trace_dl.csv", corrupt)
    failed = _audit_kpi_delivery_direction(
        tmp_path, "DL", source_rows, "air_interface/csv/dl_pdsch_trials.csv"
    )
    trace_check = next(
        check for check in failed
        if check.check_id == "tb_identity_deduplication_and_goodput_recomputed_from_primary_trials"
    )
    assert not trace_check.passed
    assert "grant_context_improperly_used_as_transport_block_identity" in trace_check.details


def test_harq_observation_contract_recomputes_timeline_and_summary(
    tmp_path: Path,
) -> None:
    source = {
        "DL": [{
            "SNR_dB": "10", "Frame": "1", "Slot": "2", "CRCPass": "1",
            "Status": "PASS", "Crash": "0", "GoodBits": "1000",
            "OfferedBits": "1000", "Goodput_Mbps": "1",
            "ReceiverHestSINR_dB": "9.5", "RankIndicator": "1",
        }],
        "UL": [{
            "SNR_dB": "5", "Frame": "1", "Slot": "3", "CRCPass": "0",
            "Status": "FAIL", "Crash": "0", "GoodBits": "0",
            "OfferedBits": "1000", "Goodput_Mbps": "0",
            "ReceiverHestSINR_dB": "4.5", "RankIndicator": "1",
        }],
    }
    note = "Actual frame-level DL/UL decode outcome for live HARQ visibility."
    timeline = []
    for direction in ("DL", "UL"):
        row = source[direction][0]
        timeline.append({
            "Direction": direction,
            "TraceSource": direction.lower() + "_raw_link_trials",
            **row,
            "Notes": note,
        })
    summary_note = "Live HARQ observation summary derived from the provided runtime HARQ timeline."
    summary = [
        {
            "Direction": "DL", "TraceSource": "dl_raw_link_trials",
            "SNR_dB": "10", "FramesObserved": "1", "CRCPassRate": "1",
            "CRCFailRate": "0", "CrashRate": "0", "MeanGoodput_Mbps": "1",
            "MeanReceiverHestSINR_dB": "9.5", "Notes": summary_note,
        },
        {
            "Direction": "UL", "TraceSource": "ul_raw_link_trials",
            "SNR_dB": "5", "FramesObserved": "1", "CRCPassRate": "0",
            "CRCFailRate": "1", "CrashRate": "0", "MeanGoodput_Mbps": "0",
            "MeanReceiverHestSINR_dB": "4.5", "Notes": summary_note,
        },
    ]
    _write_rows(tmp_path / "harq/csv/live_harq_observation_timeline.csv", timeline)
    _write_rows(tmp_path / "harq/csv/live_harq_observation_summary.csv", summary)
    checks = _audit_harq_observation_tables(tmp_path, source)
    assert len(checks) == 4
    assert all(check.passed for check in checks), [check.details for check in checks]

    summary[1]["CRCFailRate"] = "0"
    _write_rows(tmp_path / "harq/csv/live_harq_observation_summary.csv", summary)
    failed = _audit_harq_observation_tables(tmp_path, source)
    summary_check = next(
        check for check in failed
        if check.check_id == "direction_summary_recomputed_from_timeline"
    )
    assert not summary_check.passed
    assert "CRCFailRate_mismatch" in summary_check.details


def test_terminal_status_reduction_rejects_stale_visual_failure(tmp_path: Path) -> None:
    _write_rows(
        tmp_path / "reports/csv/visual_artifact_integrity.csv",
        [{"IntegrityOk": "1"}],
    )
    _write_rows(
        tmp_path / "reports/csv/visual_artifact_audit.csv",
        [{"audit_ok": "1"}],
    )
    _write_rows(
        tmp_path / "reports/csv/result_status_summary.csv",
        [
            {
                "ResultOk": "0",
                "RuntimeTruthContractOk": "0",
                "VisualArtifactGateOk": "0",
                "VisualArtifactFailureCount": "2",
            }
        ],
    )
    _write_rows(
        tmp_path / "reports/csv/truth_contract_failures.csv",
        [{"FailureCode": "visual_artifact_gate_failed"}],
    )
    summary = {
        "ResultOk": "0",
        "RuntimeTruthContractOk": "0",
        "VisualArtifactIntegrityOk": "0",
        "VisualArtifactIntegrityFailureCount": "2",
        "VisualArtifactGateOk": "0",
        "VisualArtifactFailureCount": "2",
    }
    checks = _audit_status_reduction(tmp_path, "reports/csv/scenario_summary.csv", summary)
    assert any(not check.passed for check in checks)
    assert "retains_visual_failures" in checks[0].details


def test_visual_audit_tables_are_domain_contracted_and_fail_closed(tmp_path: Path) -> None:
    summary = {"ScenarioID": "visual_fixture", "ConfigHash": "a" * 64}
    _write_rows(
        tmp_path / "reports/csv/visual_artifact_integrity.csv",
        [{"ArtifactPath": "reports/image/chart.png", "IntegrityOk": "1"}],
    )
    _write_rows(
        tmp_path / "reports/csv/visual_artifact_audit.csv",
        [{"relative_path": "reports/image/chart.png", "audit_ok": "1"}],
    )
    checks = _audit_domain_runtime_tables(tmp_path, summary)
    selected = [
        check
        for check in checks
        if check.artifact_path
        in {
            "reports/csv/visual_artifact_integrity.csv",
            "reports/csv/visual_artifact_audit.csv",
        }
    ]
    assert len(selected) == 8
    assert all(check.passed for check in selected)

    _write_rows(
        tmp_path / "reports/csv/visual_artifact_integrity.csv",
        [{"ArtifactPath": "reports/image/chart.png", "IntegrityOk": "0"}],
    )
    checks = _audit_domain_runtime_tables(tmp_path, summary)
    # Baseline domain validation classifies and range-checks these tables;
    # terminal pass/fail reduction is enforced separately by
    # _audit_status_reduction against the exact same persisted rows.
    assert any(
        check.artifact_path == "reports/csv/visual_artifact_integrity.csv"
        for check in checks
    )


def test_fer_includes_finalized_warmup_and_unavailable_sinr_trials() -> None:
    for direction in ("DL", "UL"):
        raw = [
            {"UEIndex": "1", "SFN": "3", "IsWarmupFrame": "1", "CRCPass": "0"},
            {"UEIndex": "1", "SFN": "4", "PostEqSINR_dB": "NaN", "CRCPass": "0"},
            {"UEIndex": "1", "SFN": "5", "PostEqSINR_dB": "12", "CRCPass": "1"},
            {"UEIndex": "1", "SFN": "6", "FallbackFlag": "1", "CRCPass": "0"},
            {"UEIndex": "1", "SFN": "7", "FinalizedFlag": "0", "CRCPass": "0"},
        ]
        for scope in ("1", "all"):
            row = {
                "Scope": "executed_frames", "Direction": direction, "UEIndex": scope,
                "ObservedFrames": "3", "ErroredFrames": "2", "FER": str(2 / 3),
                "BLER": str(2 / 3), "BER": "0.1", "TraceSource": "raw_trials",
            }
            checks = _audit_derived_link_table(
                "air_interface/csv/fer_summary.csv", list(row), [row], {direction: raw}
            )
            assert all(check.passed for check in checks), [check.details for check in checks]
            # Dropping failed frames must fail, even when reported FER is internally consistent.
            row.update({"ObservedFrames": "1", "ErroredFrames": "0", "FER": "0"})
            checks = _audit_derived_link_table(
                "air_interface/csv/fer_summary.csv", list(row), [row], {direction: raw}
            )
            failures = " | ".join(check.details for check in checks if not check.passed)
            assert "frame_count_raw_mismatch" in failures
            assert "fer_raw_mismatch" in failures


def test_fer_uses_absolute_frames_and_counts_crashes_without_crc() -> None:
    row = {
        "Scope": "run", "Direction": "DL", "ObservedFrames": "4",
        "ErroredFrames": "3", "FER": "0.75", "BLER": "0", "BER": "0",
        "TraceSource": "dl_frame_grouped_raw_link_trials",
    }
    raw = [
        {"Frame": "1", "SFN": "0", "CRCPass": "1"},
        {"Frame": "1025", "SFN": "0", "CRCPass": "NaN", "Crash": "1"},
        {"Frame": "1026", "SFN": "1", "CRCPass": "NaN", "Status": "CRASH"},
        {"Frame": "1027", "SFN": "2", "CRCPass": "NaN", "Status": "FAIL"},
    ]
    checks = _audit_derived_link_table(
        "air_interface/csv/fer_summary.csv", list(row), [row], {"DL": raw}
    )
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_derived_bler_curve_requires_exact_failure_count_arithmetic() -> None:
    row = {
        "Direction": "DL",
        "PostEqSINR_dB_BinCenter": "10",
        "PostEqSINR_dB_BinMin": "9.5",
        "PostEqSINR_dB_BinMax": "10.5",
        "BLER": "0.25",
        "BLER_CI_Low": "0.05",
        "BLER_CI_High": "0.55",
        "BER": "0.01",
        "TrialCount": "4",
        "FailureCount": "2",
        "SourceArtifact": "dl_pdsch_trials.csv",
    }
    checks = _audit_derived_link_table(
        "air_interface/csv/dl_measured_sinr_bler_curve.csv",
        list(row),
        [row],
        {"DL": [], "UL": []},
    )
    reconciliation = next(
        check for check in checks if check.check_id == "same_trial_population_reconciliation"
    )
    assert not reconciliation.passed
    assert "bler_failure_count_arithmetic_mismatch" in reconciliation.details


def test_derived_link_summary_reconciles_weighted_ber_and_trial_count() -> None:
    raw = [
        {
            "UEIndex": "1",
            "CRCPass": "1",
            "BitErrors": "0",
            "BitsCompared": "100",
            "Throughput_Mbps": "10",
        },
        {
            "UEIndex": "1",
            "CRCPass": "0",
            "BitErrors": "9",
            "BitsCompared": "900",
            "Throughput_Mbps": "20",
        },
    ]
    row = {
        "Direction": "DL",
        "UEIndex": "1",
        "N_Trials": "2",
        "SINR_min_dB": "1",
        "SINR_p5_dB": "1",
        "SINR_median_dB": "2",
        "SINR_p95_dB": "3",
        "SINR_max_dB": "3",
        "BLER_overall": "0.5",
        "BER_overall": "0.009",
        "Throughput_Mbps_mean": "15",
        "Goodput_Mbps_mean": "5",
        "OfferedThroughput_Mbps_mean": "15",
        "SourceArtifact": "dl_pdsch_trials.csv",
    }
    checks = _audit_derived_link_table(
        "air_interface/csv/live_measured_sinr_summary.csv",
        list(row),
        [row],
        {"DL": raw, "UL": []},
    )
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_throughput_curve_checks_harq_conservation_over_complete_population() -> None:
    # The retransmission bin can deliver previously offered bits and therefore
    # exceed the new traffic offered in that individual bin.  The full
    # direction/UE population must nevertheless conserve delivered traffic.
    common = {
        "Direction": "UL",
        "UEIndex": "1",
        "PostEqSINR_dB_BinMin": "0",
        "PostEqSINR_dB_BinMax": "1",
        "Throughput_Mbps_mean": "10",
        "SourceArtifact": "ul_pusch_trials.csv",
    }
    rows = [
        {
            **common,
            "PostEqSINR_dB_BinCenter": "0.25",
            "Goodput_Mbps_mean": "0",
            "OfferedThroughput_Mbps_mean": "10",
            "TrialCount": "1",
        },
        {
            **common,
            "PostEqSINR_dB_BinCenter": "0.75",
            "Goodput_Mbps_mean": "10",
            "OfferedThroughput_Mbps_mean": "0",
            "TrialCount": "1",
        },
    ]
    checks = _audit_derived_link_table(
        "air_interface/csv/ul_measured_sinr_throughput_curve.csv",
        list(rows[0]),
        rows,
        {"DL": [], "UL": []},
    )
    range_check = next(
        check for check in checks if check.check_id == "physical_ranges_and_arithmetic"
    )
    assert range_check.passed, range_check.details

    rows[1]["Goodput_Mbps_mean"] = "11"
    checks = _audit_derived_link_table(
        "air_interface/csv/ul_measured_sinr_throughput_curve.csv",
        list(rows[0]),
        rows,
        {"DL": [], "UL": []},
    )
    range_check = next(
        check for check in checks if check.check_id == "physical_ranges_and_arithmetic"
    )
    assert not range_check.passed
    assert "population_goodput_exceeds_offered" in range_check.details


def test_artifact_manifest_rejects_pass_claim_for_missing_png(tmp_path: Path) -> None:
    rows = [{
        "ContractID": "pdsch|base|png|pdsch_bler_vs_snr.png|runtime_in_path",
        "Domain": "pdsch", "Component": "pdsch", "Profile": "base",
        "ArtifactType": "PNG", "FileName": "pdsch_bler_vs_snr.png", "Required": "1",
        "Status": "PASS", "SourceRows": "2", "OutputRelativePath": "pdsch/png/pdsch_bler_vs_snr.png",
        "SourceSHA256": "a" * 64, "SHA256": "b" * 64, "ByteSize": "123",
        "Width": "1180", "Height": "700", "AxesCount": "1", "SeriesCount": "2",
        "FinitePointCount": "4",
    }]
    _write_rows(tmp_path / "artifact_generation/artifact_generation_results.csv", rows)
    checks = _audit_manifest_integrity(tmp_path)
    result_check = next(check for check in checks if check.check_id == "declared_artifacts_match_filesystem")
    assert not result_check.passed
    assert "pass_claim_missing_canonical_manifest_row" in result_check.details


def test_artifact_manifest_resolves_generator_output_under_components_root(
    tmp_path: Path,
) -> None:
    import hashlib

    contract_id = "pdsch|base|csv|pdsch_bler_curve.csv|all|runtime_in_path"
    output = tmp_path / "components/pdsch/csv/pdsch_bler_curve.csv"
    _write_rows(output, [{"SNR_dB": "20", "BLER": "0"}])
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    result = {
        "ContractID": contract_id,
        "Domain": "pdsch", "Component": "pdsch", "Profile": "base",
        "ArtifactType": "CSV", "FileName": "pdsch_bler_curve.csv",
        "Required": "1", "Status": "PASS", "SourceRows": "1",
        "OutputRelativePath": "pdsch/csv/pdsch_bler_curve.csv",
        "SourceSHA256": digest, "SHA256": digest,
        "ByteSize": str(output.stat().st_size), "Width": "0", "Height": "0",
        "AxesCount": "0", "SeriesCount": "0", "FinitePointCount": "0",
    }
    _write_rows(
        tmp_path / "artifact_generation/artifact_generation_results.csv",
        [result],
    )
    manifest = dict(result)
    manifest["PublishedRelativePath"] = "components/pdsch/csv/pdsch_bler_curve.csv"
    _write_rows(
        tmp_path / "artifact_generation/canonical_component_manifest.csv",
        [manifest],
    )
    summary = {
        "Domain": "pdsch", "Component": "pdsch", "Profile": "base",
        "ArtifactType": "CSV", "ContractCount": "1", "RequiredCount": "1",
        "GeneratedCount": "1", "MissingCount": "0", "FailedCount": "0",
        "RequiredFailureCount": "0", "SourceRowCount": "1",
        "PublishedByteCount": str(output.stat().st_size), "Status": "PASS",
    }
    _write_rows(
        tmp_path / "artifact_generation/artifact_generation_summary.csv",
        [summary],
    )
    checks = _audit_manifest_integrity(tmp_path)
    result_check = next(
        check for check in checks
        if check.check_id == "declared_artifacts_match_filesystem"
    )
    assert result_check.passed, result_check.details


def test_component_summary_rejects_blank_identity(tmp_path: Path) -> None:
    canonical = tmp_path / "reports/csv/source.csv"
    published = tmp_path / "pdsch/csv/source.csv"
    _write_rows(canonical, [{"value": "1"}])
    _write_rows(published, [{"value": "1"}])
    import hashlib

    digest = hashlib.sha256(canonical.read_bytes()).hexdigest()
    _write_rows(
        tmp_path / "reports/csv/component_artifact_publication_manifest.csv",
        [{
            "Component": "pdsch", "ArtifactType": "csv",
            "CanonicalRelativePath": "reports/csv/source.csv",
            "PublishedRelativePath": "pdsch/csv/source.csv", "CanonicalSHA256": digest,
            "PublishedSHA256": digest, "ByteSize": str(canonical.stat().st_size),
            "PublishStatus": "PUBLISHED_HASH_VERIFIED",
        }],
    )
    _write_rows(
        tmp_path / "reports/csv/scenario_summary.csv",
        [{"ScenarioID": "scenario", "ConfigHash": "a" * 64, "RunnerProfile": "waveform_bundle"}],
    )
    _write_rows(
        tmp_path / "reports/csv/component_artifact_publication_summary.csv",
        [{
            "ScenarioID": "", "ConfigHash": "", "RunnerProfile": "", "Component": "pdsch",
            "SourceArtifactCount": "1", "CSVCount": "1", "RasterImageCount": "0",
            "JSONCount": "0", "MATCount": "0", "PublicationStatus": "PUBLISHED_HASH_VERIFIED",
        }],
    )
    checks = _audit_manifest_integrity(tmp_path)
    summary_check = next(check for check in checks if check.check_id == "component_summary_reconciles_manifest")
    assert not summary_check.passed
    assert "scenario_identity_mismatch" in summary_check.details


def test_domain_runtime_contract_checks_identity_probability_and_truth(tmp_path: Path) -> None:
    _write_rows(
        tmp_path / "analytics/csv/example.csv",
        [{
            "ScenarioID": "wrong", "ConfigHash": "b" * 64, "RunID": "run",
            "ExecutionID": "execution", "EvidenceScope": "in_path", "BLER": "1.2",
            "FallbackFlag": "1", "TruthStatus": "fallback", "TrialCount": "2",
        }],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "expected", "ConfigHash": "a" * 64},
    )
    failed = {check.check_id: check.details for check in checks if not check.passed}
    assert "ScenarioID_mismatch_or_missing" in failed["scenario_execution_identity"]
    assert "BLER_outside_unit_interval" in failed["populated_physical_value_ranges"]
    assert "FallbackFlag_true_in_path" in failed["in_path_truth_proxy_separation"]


def test_channel_snapshot_time_requires_physical_sample_clock_and_run_bound(
    tmp_path: Path,
) -> None:
    summary = {"ScenarioID": "scenario", "ConfigHash": "a" * 64}
    _write_rows(
        tmp_path / "reports/csv/live_scenario_overview.csv",
        [{"total_slots": "15", "scs_khz": "15"}],
    )
    relative = "channel/csv/channel_snapshots.csv"
    _write_rows(
        tmp_path / relative,
        [{
            "ScenarioID": "scenario",
            "ScenarioConfigHash": "a" * 64,
            "RunId": "run",
            "ExecutionID": "execution",
            "SampleTimeSec": "5.534023222112865e20",
            "SampleRateHz": "",
            "SampleRateSource": "",
            "EvidenceScope": "in_path",
            "TruthStatus": "real_lls_evidence",
        }],
    )
    checks = _audit_domain_runtime_tables(tmp_path, summary)
    failed = {
        check.check_id: check.details
        for check in checks
        if check.artifact_path == relative and not check.passed
    }
    details = failed["populated_physical_value_ranges"]
    assert "SampleTimeSec_outside_run_duration" in details
    assert "SampleRateHz_missing_or_nonpositive" in details
    assert "SampleRateSource_missing" in details

    _write_rows(
        tmp_path / relative,
        [{
            "ScenarioID": "scenario",
            "ScenarioConfigHash": "a" * 64,
            "RunId": "run",
            "ExecutionID": "execution",
            "SampleTimeSec": "0.006",
            "SampleRateHz": "7680000",
            "SampleRateSource": "resolved_config.phy.waveform.sampleRate_Hz",
            "EvidenceScope": "in_path",
            "TruthStatus": "real_lls_evidence",
        }],
    )
    checks = _audit_domain_runtime_tables(tmp_path, summary)
    assert all(
        check.passed
        for check in checks
        if check.artifact_path == relative
    )


def test_packet_flow_and_report_csvs_cannot_escape_baseline_domain_semantics(
    tmp_path: Path,
) -> None:
    summary = {"ScenarioID": "scenario-a", "ConfigHash": "a" * 64}
    for relative in (
        "packet_flow/csv/new_scheduler_surface.csv",
        "reports/csv/new_runtime_surface.csv",
        "reports/final/new_publication_surface.csv",
    ):
        _write_rows(
            tmp_path / relative,
            [{
                "ScenarioID": "scenario-a",
                "ConfigHash": "a" * 64,
                "TrialCount": "-1",
                "EvidenceScope": "in_path",
                "FallbackFlag": "1",
                "ApproximationMode": "fast_proxy",
            }],
        )
    checks = _audit_domain_runtime_tables(tmp_path, summary)
    by_path: dict[str, list[object]] = {}
    for check in checks:
        by_path.setdefault(check.artifact_path, []).append(check)
    for relative in (
        "packet_flow/csv/new_scheduler_surface.csv",
        "reports/csv/new_runtime_surface.csv",
        "reports/final/new_publication_surface.csv",
    ):
        assert relative in by_path
        assert any(
            check.check_id == "populated_physical_value_ranges" and not check.passed
            for check in by_path[relative]
        )
        assert any(
            check.check_id == "in_path_truth_proxy_separation" and not check.passed
            for check in by_path[relative]
        )


def test_metric_output_contract_accepts_observed_and_unavailable_rows(
    tmp_path: Path,
) -> None:
    _write_rows(
        tmp_path / "air_interface/csv/dl_pdsch_trials.csv",
        [{"CRCPass": "1"}],
    )
    _write_rows(
        tmp_path / "reports/csv/basic_phy_performance_outputs.csv",
        [
            {
                "CategoryCode": "B",
                "CategoryKey": "basic_phy_performance_outputs",
                "CategoryName": "Basic PHY performance outputs",
                "MetricKey": "bler",
                "MetricName": "BLER",
                "Entity": "DL",
                "Statistic": "mean",
                "Availability": "observed",
                "CountsTowardCoverage": "1",
                "ValueNumeric": "0.25",
                "ValueText": "0.25",
                "Unit": "fraction",
                "SourceArtifact": "air_interface/csv/dl_pdsch_trials.csv",
                "Notes": "runtime aggregation",
            },
            {
                "CategoryCode": "B",
                "CategoryKey": "basic_phy_performance_outputs",
                "CategoryName": "Basic PHY performance outputs",
                "MetricKey": "unsupported_metric",
                "MetricName": "Unsupported metric",
                "Entity": "",
                "Statistic": "",
                "Availability": "not_available",
                "CountsTowardCoverage": "0",
                "ValueNumeric": "NaN",
                "ValueText": "",
                "Unit": "",
                "SourceArtifact": "",
                "Notes": "not emitted by this run",
            },
        ],
    )
    checks = _audit_metric_output_tables(tmp_path)
    assert checks
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_metric_output_contract_rejects_false_coverage_and_missing_lineage(
    tmp_path: Path,
) -> None:
    row = {
        "CategoryCode": "B",
        "CategoryKey": "wrong_category",
        "CategoryName": "Basic PHY performance outputs",
        "MetricKey": "bler",
        "MetricName": "BLER",
        "Entity": "DL",
        "Statistic": "mean",
        "Availability": "not_available",
        "CountsTowardCoverage": "1",
        "ValueNumeric": "1.2",
        "ValueText": "0.2",
        "Unit": "fraction",
        "SourceArtifact": "air_interface/csv/missing.csv",
        "Notes": "",
    }
    _write_rows(
        tmp_path / "reports/csv/basic_phy_performance_outputs.csv",
        [row, dict(row)],
    )
    checks = _audit_metric_output_tables(tmp_path)
    failed = {check.check_id: check.details for check in checks if not check.passed}
    assert "CategoryKey_mismatch" in failed["metric_identity_and_unique_key"]
    assert "duplicate_metric_entity_statistic_key" in failed[
        "metric_identity_and_unique_key"
    ]
    assert "coverage_availability_mismatch" in failed[
        "availability_matches_runtime_coverage"
    ]
    assert "ValueNumeric_ValueText_mismatch" in failed[
        "metric_values_and_units_are_coherent"
    ]
    assert "fraction_outside_unit_interval" in failed[
        "metric_values_and_units_are_coherent"
    ]
    assert "counted_metric_source_not_found" in failed[
        "counted_metrics_bind_existing_run_artifacts"
    ]


def test_metric_coverage_contract_recomputes_detail_rollup(tmp_path: Path) -> None:
    detail_rows = [
        {
            "CategoryCode": "B", "CategoryKey": "basic_phy_performance_outputs",
            "CategoryName": "Basic PHY", "MetricKey": "bler", "MetricName": "BLER",
            "Entity": "DL", "Statistic": "mean", "Availability": "observed",
            "CountsTowardCoverage": "1", "ValueNumeric": "0.25", "ValueText": "0.25",
            "Unit": "fraction", "SourceArtifact": "air_interface/csv/dl.csv", "Notes": "",
        },
        {
            "CategoryCode": "B", "CategoryKey": "basic_phy_performance_outputs",
            "CategoryName": "Basic PHY", "MetricKey": "bler", "MetricName": "BLER",
            "Entity": "UL", "Statistic": "mean", "Availability": "not_available",
            "CountsTowardCoverage": "0", "ValueNumeric": "NaN", "ValueText": "",
            "Unit": "fraction", "SourceArtifact": "", "Notes": "not emitted",
        },
    ]
    _write_rows(tmp_path / "reports/csv/lls_output_metric_rows.csv", detail_rows)
    coverage = {
        "CategoryCode": "B", "CategoryKey": "basic_phy_performance_outputs",
        "CategoryName": "Basic PHY", "MetricKey": "bler", "MetricName": "BLER",
        "Availability": "observed", "CountsTowardCoverage": "1",
        "CoveredRowCount": "1", "ObservedRowCount": "1", "DerivedRowCount": "0",
        "ConfigOnlyRowCount": "0", "DisabledRowCount": "0",
        "PlaceholderRowCount": "0", "NotSupportedRowCount": "0",
        "NotAvailableRowCount": "1", "NotExercisedRowCount": "0",
        "SourceArtifacts": "air_interface/csv/dl.csv", "Notes": "",
    }
    _write_rows(tmp_path / "reports/csv/lls_output_spec_coverage.csv", [coverage])
    checks = _audit_metric_coverage_table(tmp_path)
    assert checks and all(check.passed for check in checks), [
        check.details for check in checks
    ]

    coverage["ObservedRowCount"] = "0"
    coverage["CountsTowardCoverage"] = "0"
    _write_rows(tmp_path / "reports/csv/lls_output_spec_coverage.csv", [coverage])
    failed = {
        check.check_id: check.details
        for check in _audit_metric_coverage_table(tmp_path)
        if not check.passed
    }
    assert "ObservedRowCount_mismatch" in failed[
        "coverage_recomputed_from_metric_ledger"
    ]
    assert "CountsTowardCoverage_mismatch" in failed[
        "coverage_recomputed_from_metric_ledger"
    ]


def test_metric_coverage_accepts_fail_closed_unmeasured_catalog_gap(
    tmp_path: Path,
) -> None:
    _write_rows(
        tmp_path / "reports/csv/lls_output_metric_rows.csv",
        [{
            "CategoryCode": "J", "CategoryKey": "beam_management_outputs",
            "CategoryName": "Beam management", "MetricKey": "beam_hit_rate",
            "MetricName": "Beam hit rate", "Entity": "beam", "Statistic": "mean",
            "Availability": "observed", "CountsTowardCoverage": "1",
            "ValueNumeric": "1", "ValueText": "1", "Unit": "fraction",
            "SourceArtifact": "beamforming/csv/beam.csv", "Notes": "",
        }],
    )
    _write_rows(tmp_path / "beamforming/csv/beam.csv", [{"Hit": "1"}])
    base = {
        "CategoryCode": "J", "CategoryKey": "beam_management_outputs",
        "CategoryName": "Beam management", "Availability": "not_available",
        "CountsTowardCoverage": "0", "CoveredRowCount": "0",
        "ObservedRowCount": "0", "DerivedRowCount": "0",
        "ConfigOnlyRowCount": "0", "DisabledRowCount": "0",
        "PlaceholderRowCount": "0", "NotSupportedRowCount": "0",
        "NotAvailableRowCount": "0", "NotExercisedRowCount": "0",
        "SourceArtifacts": "", "Notes": "primary row intentionally suppressed",
    }
    observed = dict(base, MetricKey="beam_hit_rate", MetricName="Beam hit rate",
                    Availability="observed", CountsTowardCoverage="1",
                    CoveredRowCount="1", ObservedRowCount="1",
                    SourceArtifacts="beamforming/csv/beam.csv")
    gap = dict(base, MetricKey="beam_switch_latency", MetricName="Beam switch latency")
    _write_rows(
        tmp_path / "reports/csv/lls_output_spec_coverage.csv",
        [observed, gap],
    )
    checks = _audit_metric_coverage_table(tmp_path)
    assert checks and all(check.passed for check in checks), [
        check.details for check in checks
    ]

    gap["Availability"] = "observed"
    gap["CountsTowardCoverage"] = "1"
    _write_rows(
        tmp_path / "reports/csv/lls_output_spec_coverage.csv",
        [observed, gap],
    )
    failed = {
        check.check_id: check.details
        for check in _audit_metric_coverage_table(tmp_path)
        if not check.passed
    }
    assert "unmeasured_catalog_gap_not_fail_closed" in failed[
        "coverage_recomputed_from_metric_ledger"
    ]


def test_find_named_files_discovers_all_nested_progress_files(tmp_path: Path) -> None:
    paths = [
        tmp_path / "001_dl" / "001_snr" / "frc_reference_progress.csv",
        tmp_path / ("002_" + "x" * 80) / ("001_" + "y" * 80)
        / "frc_reference_progress.csv",
    ]
    for path in paths:
        target = _io_path(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=["EntryId"])
            writer.writeheader()
            writer.writerow({"EntryId": path.parent.parent.name})
    assert [path.resolve() for path in _find_named_files(
        tmp_path, "frc_reference_progress.csv"
    )] == [path.resolve() for path in paths]


def test_live_reselection_event_table_may_be_schema_only_when_no_event_occurred(tmp_path: Path) -> None:
    path = tmp_path / "reports/csv/live_cell_reselection_events.csv"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("ScenarioID,UEID,Slot,Event\n", encoding="utf-8")
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "scenario", "ConfigHash": "a" * 64},
    )
    assert checks
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_fixed_link_disabled_live_domains_are_not_required_but_user_summary_is(
    tmp_path: Path,
) -> None:
    resolved = {
        "validation": {"run_class": "fixed_snr_sweep_lls"},
        "mimo_and_beam_management": {"beam_sweeping": False},
        "system": {"beam": {"enable": False}},
        "reference_signals": {
            "ssb_enabled": False,
            "csi_rs_enabled": False,
            "nzp_csi_rs": {"enabled": False},
        },
    }
    config_path = tmp_path / "meta/scenario_config_resolved.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(resolved), encoding="utf-8")
    for relative in (
        "reports/csv/live_beam_p1_acquisition_stats.csv",
        "reports/csv/live_coverage_layer.csv",
        "reports/csv/live_csirs_stats.csv",
        "reports/csv/live_user_performance_snapshot.csv",
        "geometry/csv/trajectory_geometry.csv",
        "geometry/csv/ue_initial_positions.csv",
        "mobility/csv/trajectory_segment_table.csv",
    ):
        path = tmp_path / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("ScenarioID,ConfigHash\n", encoding="utf-8")
    _write_rows(
        tmp_path / "air_interface/csv/dl_pdsch_trials.csv",
        [{"CRCPass": "1"}],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "fixed", "ConfigHash": "a" * 64},
    )
    by_path = {
        check.artifact_path: check
        for check in checks
        if check.check_id == "schema_and_runtime_rows"
    }
    for relative in (
        "reports/csv/live_beam_p1_acquisition_stats.csv",
        "reports/csv/live_coverage_layer.csv",
        "reports/csv/live_csirs_stats.csv",
        "geometry/csv/trajectory_geometry.csv",
        "geometry/csv/ue_initial_positions.csv",
        "mobility/csv/trajectory_segment_table.csv",
    ):
        assert not by_path[relative].required
        assert not by_path[relative].evaluated
    user = by_path["reports/csv/live_user_performance_snapshot.csv"]
    assert user.required and user.evaluated and not user.passed
    assert "missing_runtime_rows" in user.details


def test_runtime_antenna_rows_require_resolved_antenna_configuration(
    tmp_path: Path,
) -> None:
    _write_rows(
        tmp_path / "reports/csv/antenna_runtime_evidence.csv",
        [{"Direction": "DL", "UEIndex": "1"}],
    )
    resolved = tmp_path / "reports/csv/antenna_config_resolved.csv"
    resolved.parent.mkdir(parents=True, exist_ok=True)
    resolved.write_text("NodeType,NodeIndex,NumElements\n", encoding="utf-8")

    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "fixed", "ConfigHash": "a" * 64},
    )
    check = next(
        item for item in checks
        if item.artifact_path == "reports/csv/antenna_config_resolved.csv"
        and item.check_id == "schema_and_runtime_rows"
    )
    assert check.required and check.evaluated and not check.passed
    assert "missing_runtime_rows" in check.details


def test_failed_truth_contract_cannot_publish_empty_issue_registries(
    tmp_path: Path,
) -> None:
    _write_rows(
        tmp_path / "reports/csv/truth_contract_failures.csv",
        [{"FailureCode": "missing_runtime_rows", "Reason": "evidence absent"}],
    )
    for name in ("active_issue_gate_summary.csv", "result_issue_registry.csv"):
        path = tmp_path / "reports/csv" / name
        path.write_text("IssueCode,Reason\n", encoding="utf-8")

    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "failed", "ConfigHash": "a" * 64},
    )
    failed = {
        item.artifact_path: item
        for item in checks
        if item.check_id == "schema_and_runtime_rows" and not item.passed
    }
    assert "reports/csv/active_issue_gate_summary.csv" in failed
    assert "reports/csv/result_issue_registry.csv" in failed


def test_empty_truth_contract_failure_ledger_requires_matching_pass_receipts(
    tmp_path: Path,
) -> None:
    scenario_id = "truth-zero-event"
    config_hash = "a" * 64
    failure_path = tmp_path / "reports/csv/truth_contract_failures.csv"
    failure_path.parent.mkdir(parents=True, exist_ok=True)
    failure_path.write_text("FailureCode,Reason\n", encoding="utf-8")
    summary = {
        "ScenarioID": scenario_id,
        "ConfigHash": config_hash,
        "ResultOk": "1",
        "RuntimeTruthContractOk": "1",
        "TruthContractOk": "1",
    }
    _write_rows(tmp_path / "reports/csv/scenario_summary.csv", [summary])
    _write_rows(
        tmp_path / "reports/csv/truth_contract_summary.csv",
        [{
            "ScenarioID": scenario_id,
            "ConfigHash": config_hash,
            "ResultOk": "1",
            "RuntimeTruthContractOk": "1",
            "StrictTruthFailureCount": "0",
            "StrictProxyGuardFailureCount": "0",
            "CanonicalArtifactGapCount": "0",
            "RoundtripMismatchCount": "0",
            "RequiredRuntimeEvidenceMissingCount": "0",
        }],
    )
    checks = _audit_domain_runtime_tables(tmp_path, summary)
    check = next(
        item for item in checks
        if item.artifact_path == "reports/csv/truth_contract_failures.csv"
        and item.check_id == "schema_and_runtime_rows"
    )
    assert check.required and check.evaluated and check.passed

    # A later terminal/browser gate may fail the overall run after the PHY
    # truth contract has already evaluated cleanly.  The zero-event truth
    # failure ledger remains valid; no fake failure row may be inserted.
    summary["ResultOk"] = "0"
    _write_rows(tmp_path / "reports/csv/scenario_summary.csv", [summary])
    terminal_failed_checks = _audit_domain_runtime_tables(tmp_path, summary)
    terminal_failed = next(
        item for item in terminal_failed_checks
        if item.artifact_path == "reports/csv/truth_contract_failures.csv"
        and item.check_id == "schema_and_runtime_rows"
    )
    assert terminal_failed.required and terminal_failed.evaluated and terminal_failed.passed

    # A failed PHY truth verdict is different: an empty failure ledger is then
    # contradictory and must fail closed.
    summary["RuntimeTruthContractOk"] = "0"
    summary["TruthContractOk"] = "0"
    _write_rows(tmp_path / "reports/csv/scenario_summary.csv", [summary])
    failed_checks = _audit_domain_runtime_tables(tmp_path, summary)
    failed = next(
        item for item in failed_checks
        if item.artifact_path == "reports/csv/truth_contract_failures.csv"
        and item.check_id == "schema_and_runtime_rows"
    )
    assert failed.required and failed.evaluated and not failed.passed
    assert "missing_runtime_rows" in failed.details


def test_evaluated_empty_issue_registries_are_valid_with_canonical_receipts(
    tmp_path: Path,
) -> None:
    run_id = "evaluated-empty-run"
    config_hash = "a" * 64
    _write_rows(
        tmp_path / "reports/csv/truth_contract_failures.csv",
        [{"FailureCode": "visual_artifact_integrity", "Reason": "terminal visual gate"}],
    )
    for name in ("active_issue_gate_summary.csv", "result_issue_registry.csv"):
        path = tmp_path / "reports/csv" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("IssueCode,Reason\n", encoding="utf-8")
    _write_rows(
        tmp_path / "reports/csv/result_issue_registry_evaluation.csv",
        [{
            "RunId": run_id,
            "ScenarioId": "fixed",
            "ConfigHash": config_hash,
            "EvaluationStatus": "EVALUATED",
            "IssueRowCount": "0",
            "SourceTableCount": "11",
            "RuntimeSourceRowCount": "240",
            "Evaluator": "sixgr.truth.exportLLSOutputCoverageArtifacts/localBuildResultIssueRegistry",
            "SchemaVersion": "result_issue_registry_evaluation_v1",
            "EvaluatedSources": "DLTrials|ULTrials",
        }],
    )
    active_summary = {
        "RunId": run_id,
        "ActiveIssueGateOk": True,
        "ActiveCriticalIssueCount": 0,
        "ActiveHighIssueCount": 0,
        "ActiveMediumIssueCount": 0,
        "ActiveMandatoryIssueCount": 0,
        "IssueRegistryStatus": "PASS",
        "IssueRegistryRowCount": 0,
        "IssueRegistryEvaluationValid": True,
        "IssueRegistryEvaluationAudit": {
            "ObservedRunId": run_id,
            "ObservedConfigHash": config_hash,
            "ObservedIssueRowCount": 0,
            "EvaluationStatus": "EVALUATED",
        },
    }
    summary_path = tmp_path / "reports/json/active_issue_gate_summary.json"
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(json.dumps(active_summary), encoding="utf-8")

    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "fixed", "ConfigHash": config_hash},
    )
    by_path = {
        item.artifact_path: item
        for item in checks
        if item.check_id == "schema_and_runtime_rows"
    }
    assert by_path["reports/csv/active_issue_gate_summary.csv"].passed
    assert by_path["reports/csv/result_issue_registry.csv"].passed


def test_live_scenario_overview_requires_populated_radio_runtime_fields(
    tmp_path: Path,
) -> None:
    _write_rows(
        tmp_path / "reports/csv/live_scenario_overview.csv",
        [{
            "run_id": "run-1", "scenario_id": "scenario", "center_frequency_hz": "",
            "bandwidth_hz": "", "scs_khz": "", "n_rb": "", "duplex_mode": "",
            "num_frames": "", "total_slots": "", "strict_mode": "",
            "honesty_mode": "",
        }],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "scenario", "ConfigHash": "a" * 64},
    )
    value_check = next(
        item for item in checks
        if item.artifact_path == "reports/csv/live_scenario_overview.csv"
        and item.check_id == "populated_physical_value_ranges"
    )
    assert not value_check.passed
    assert "center_frequency_hz_missing_or_nonpositive" in value_check.details
    assert "duplex_mode_missing" in value_check.details


def test_live_scenario_overview_accepts_strict_text_honesty_mode(
    tmp_path: Path,
) -> None:
    _write_rows(
        tmp_path / "reports/csv/live_scenario_overview.csv",
        [{
            "run_id": "run-1", "scenario_id": "scenario",
            "center_frequency_hz": "4000000000", "bandwidth_hz": "100000000",
            "scs_khz": "30", "n_rb": "273", "duplex_mode": "TDD",
            "num_frames": "2", "total_slots": "40", "strict_mode": "true",
            "honesty_mode": "strict",
        }],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "scenario", "ConfigHash": "a" * 64},
    )
    value_check = next(
        item for item in checks
        if item.artifact_path == "reports/csv/live_scenario_overview.csv"
        and item.check_id == "populated_physical_value_ranges"
    )
    assert value_check.passed, value_check.details


def test_enabled_prach_correlation_rejects_unavailable_nan_row(
    tmp_path: Path,
) -> None:
    config = tmp_path / "meta/scenario_config_resolved.json"
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text(
        json.dumps({"control_gating": {"prach_required": True}}),
        encoding="utf-8",
    )
    _write_rows(
        tmp_path / "reports/csv/prach_correlation_trace.csv",
        [{
            "lag_samples": "NaN", "correlation_abs": "NaN",
            "truth_status": "not_available",
        }],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "scenario", "ConfigHash": "a" * 64},
    )
    failed = {
        item.check_id: item.details for item in checks
        if item.artifact_path == "reports/csv/prach_correlation_trace.csv"
        and not item.passed
    }
    assert "lag_samples_missing" in failed["populated_physical_value_ranges"]
    assert "truth_status_not_real_lls_evidence" in failed["in_path_truth_proxy_separation"]


def test_fixed_link_only_audit_uses_declared_campaign_trial_tables(tmp_path: Path) -> None:
    resolved = {
        "sweeps_and_matrix": {"fixed_link_calibration": {"only": True}},
    }
    config_path = tmp_path / "meta/scenario_config_resolved.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(resolved), encoding="utf-8")
    _write_rows(
        tmp_path / "reports/csv/scenario_summary.csv",
        [{
            "ScenarioID": "fixed",
            "ConfigHash": "a" * 64,
            "EffectiveDLTrialCount": "1",
            "EffectiveULTrialCount": "1",
        }],
    )
    for direction, name in (("DL", "dl"), ("UL", "ul")):
        _write_rows(
            tmp_path / f"air_interface/csv/{name}_fixed_link_campaign_trials.csv",
            [{"Direction": direction, "FixedLinkCampaign": "1"}],
        )

    audit = audit_run(tmp_path)
    paths = {
        row["artifact_path"]
        for row in audit["canonical_csv_semantic_audit"]
        if row["category"] == "primary_link"
    }
    assert "air_interface/csv/dl_fixed_link_campaign_trials.csv" in paths
    assert "air_interface/csv/ul_fixed_link_campaign_trials.csv" in paths
    assert "air_interface/csv/dl_pdsch_trials.csv" not in paths
    assert "air_interface/csv/ul_pusch_trials.csv" not in paths


def test_runtime_config_application_evidence_rejects_nan_run_identity(tmp_path: Path) -> None:
    _write_rows(
        tmp_path / "reports/csv/runtime_config_application_evidence.csv",
        [{
            "RunId": "NaN",
            "ScenarioID": "scenario",
            "RunTag": "run_1",
            "ApplicationEventSequence": "1",
            "ApplicationEventID": "config_apply_00000001",
        }],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "scenario", "ConfigHash": "a" * 64},
    )
    failed = {check.check_id: check.details for check in checks if not check.passed}
    assert "RunId_missing" in failed["scenario_execution_identity"]
    assert "RunId_RunTag_mismatch" in failed["runtime_config_application_identity"]


def test_runtime_config_application_evidence_accepts_logical_run_tag_identity(tmp_path: Path) -> None:
    _write_rows(
        tmp_path / "reports/csv/runtime_config_application_evidence.csv",
        [{
            "RunId": "run_1",
            "ScenarioID": "scenario",
            "RunTag": "run_1",
            "ApplicationEventSequence": "1",
            "ApplicationEventID": "config_apply_00000001",
        }],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "scenario", "ConfigHash": "a" * 64},
    )
    assert checks
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_persisted_audit_view_receives_baseline_value_contract(tmp_path: Path) -> None:
    _write_rows(
        tmp_path / "reports/csv/standards_claim_audit.csv",
        [{"ScenarioID": "scenario", "ConfigHash": "a" * 64, "PassRate": "1.2"}],
    )
    checks = _audit_domain_runtime_tables(
        tmp_path,
        {"ScenarioID": "scenario", "ConfigHash": "a" * 64},
    )
    assert any(
        check.artifact_path == "reports/csv/standards_claim_audit.csv"
        and check.check_id == "populated_physical_value_ranges"
        and not check.passed
        for check in checks
    )


def _runtime_row(sequence: str, function_name: str, *, config_hash: str = "a" * 64) -> dict[str, str]:
    return {
        "Sequence": sequence,
        "TimestampUTC": "2026-08-17T00:00:00Z",
        "FunctionName": function_name,
        "Component": "PDSCH" if ".dl." in function_name else "PUSCH",
        "Direction": "DL" if ".dl." in function_name else "UL",
        "Event": "ENTER",
        "RunId": "run-1",
        "ExecutionID": "execution-1",
        "ConfigHash": config_hash,
        "ContextSHA256": "b" * 64,
        "EvidenceClass": "ACTUAL_RUNTIME_ENTRY",
        "ApproximationMode": "none",
    }


def test_runtime_ledger_is_required_when_primary_phy_rows_exist(tmp_path: Path) -> None:
    checks = _audit_runtime_call_ledger(
        tmp_path,
        {"ConfigHash": "a" * 64},
        {"DL": [{"CRCPass": "1"}], "UL": []},
    )
    assert any(check.required and not check.passed for check in checks)
    assert checks[0].check_id == "runtime_call_ledger_present_nonempty"
    assert "header_only" in checks[0].details


def test_runtime_ledger_accepts_exact_identity_bound_dl_ul_entry_points(tmp_path: Path) -> None:
    rows = [
        _runtime_row("1", "sixgr.phy.dl.PDSCH_Tx"),
        _runtime_row("2", "sixgr.phy.dl.PDSCH_Rx"),
        _runtime_row("3", "sixgr.phy.ul.PUSCH_Tx"),
        _runtime_row("4", "sixgr.phy.ul.PUSCH_Rx"),
    ]
    _write_rows(tmp_path / "reports/csv/runtime_call_ledger.csv", rows)
    checks = _audit_runtime_call_ledger(
        tmp_path,
        {"ConfigHash": "a" * 64, "RunID": "run-1", "ExecutionID": "execution-1"},
        {"DL": [{"CRCPass": "1"}], "UL": [{"CRCPass": "1"}]},
    )
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_runtime_ledger_rejects_proxy_identity_and_sequence_corruption(tmp_path: Path) -> None:
    rows = [
        _runtime_row("2", "sixgr.phy.dl.PDSCH_Tx", config_hash="c" * 64),
        _runtime_row("2", "sixgr.phy.dl.PDSCH_Rx", config_hash="c" * 64),
    ]
    rows[0]["EvidenceClass"] = "synthetic_runtime_entry"
    rows[1]["ApproximationMode"] = "fast_proxy"
    rows[1]["ContextSHA256"] = ""
    _write_rows(tmp_path / "reports/csv/runtime_call_ledger.csv", rows)
    checks = _audit_runtime_call_ledger(
        tmp_path,
        {"ConfigHash": "a" * 64},
        {"DL": [{"CRCPass": "1"}], "UL": []},
    )
    failed = {check.check_id: check.details for check in checks if not check.passed}
    assert "duplicate_sequence" in failed["runtime_call_sequence_positive_unique_monotonic"]
    assert "ConfigHash_mismatch" in failed["runtime_call_identity_matches_run"]
    assert "synthetic_runtime_entry" in failed["runtime_call_rows_are_actual_nonproxy_entries"]
    assert "fast_proxy" in failed["runtime_call_rows_are_actual_nonproxy_entries"]


def _complete_phase7_row() -> dict[str, str]:
    row = {name: "1" for name in PHASE7_GATE_NAMES}
    for phase_name in PHASE7_PHASE_MEMBERS:
        row[phase_name] = "1"
    row.update(
        {
            "Phase7Ok": "1",
            "ResultOk": "1",
            "PublicationReadinessOk": "1",
            "ResultOkAuthority": "all_phase_gates_required_no_lower_pass_override",
            "NotApplicableGateNames": "",
            "ApplicabilityAuthority": "operator_run_class_and_concrete_channel_model",
            "ScopeLabel": "SCOPED_IMPLEMENTATION_VALIDATION",
            "FailureCodes": "",
            "PrimaryFailureCode": "",
            "GeneratedAt": "2026-08-20T00:00:00Z",
            "ProducerModule": "sixgr.runtime.Phase7TruthEvaluator",
        }
    )
    return row


def test_phase7_reducer_recomputes_every_gate_and_phase_rollup(tmp_path: Path) -> None:
    row = _complete_phase7_row()
    _write_rows(tmp_path / "reports/csv/phase7_truth_gates.csv", [row])
    checks = _audit_phase7_reducer(tmp_path)
    assert all(check.passed for check in checks), [check.details for check in checks]

    row["InterferenceAccountingOk"] = "0"
    _write_rows(tmp_path / "reports/csv/phase7_truth_gates.csv", [row])
    checks = _audit_phase7_reducer(tmp_path)
    assert not checks[0].passed
    assert "Phase2Ok_rollup_mismatch" in checks[0].details
    assert "Phase7Ok_rollup_mismatch" in checks[0].details
    assert "FailureCodes_do_not_match" in checks[0].details


def test_reconciliation_reducers_match_exact_phase7_fields(tmp_path: Path) -> None:
    _write_rows(
        tmp_path / "reports/csv/phase7_truth_gates.csv",
        [_complete_phase7_row()],
    )
    for relative, mapping in RECONCILIATION_PHASE7_FLAGS.items():
        source_field = mapping[0] if isinstance(mapping, tuple) else mapping
        _write_rows(tmp_path / relative, [{source_field: "1", "FailureReason": ""}])
    checks = _audit_reconciliation_reducers(tmp_path)
    assert all(check.passed for check in checks), [check.details for check in checks]

    _write_rows(
        tmp_path / "reports/csv/throughput_reconciliation.csv",
        [{"ThroughputReconciliationOk": "0", "FailureReason": ""}],
    )
    checks = _audit_reconciliation_reducers(tmp_path)
    throughput = next(
        check
        for check in checks
        if check.artifact_path == "reports/csv/throughput_reconciliation.csv"
    )
    assert not throughput.passed
    assert "phase7_outcome_mismatch" in throughput.details
    assert "failed_reconciliation_reason_missing" in throughput.details


def _production_gate_rows(
    expected: dict[str, bool],
    required: dict[str, bool] | None = None,
) -> list[dict[str, str]]:
    if required is None:
        required = {gate: True for gate in PRODUCTION_GATE_ORDER}
        required["IndependentReferenceComparison"] = False
    rows: list[dict[str, str]] = []
    for gate in PRODUCTION_GATE_ORDER:
        passed = expected[gate]
        status = "PASS" if passed else "FAIL"
        if gate == "IndependentFRCQualification" and not passed:
            status = "NOT_EVALUATED"
        if not required[gate]:
            status = "NOT_EVALUATED"
        rows.append(
            {
                "Gate": gate,
                "Required": "1" if required[gate] else "0",
                "Pass": "1" if passed else "0",
                "Status": status,
                "EvidenceArtifact": "reports/csv/production_qualification_gate.csv",
                "FailureReason": "" if passed or not required[gate] else gate + "_failed",
            }
        )
    return rows


def test_production_gate_cannot_promote_missing_reference_to_pass(tmp_path: Path) -> None:
    _write_rows(
        tmp_path / "reports/csv/result_status_summary.csv",
        [{
            "ResultOk": "1", "ExecutionCompleted": "1",
            "RuntimeTruthContractOk": "1", "MandatorySubsystemsOk": "1",
            "KpiConsistencyOk": "1", "ScenarioObjectiveOk": "1",
        }],
    )
    _write_rows(
        tmp_path / "reports/csv/phy_package_execution_evidence_gate.csv",
        [{"Gate": "runtime", "Required": "1", "Pass": "1"}],
    )
    _write_rows(
        tmp_path / "reports/csv/phase7_truth_gates.csv",
        [_complete_phase7_row()],
    )
    _write_rows(
        tmp_path / "reports/csv/publication_readiness_gate_summary.csv",
        [{
            "TerminalPublicationGatesOk": "1",
            # For a non-campaign run this is the publication roll-up's
            # not-applicable satisfaction, not an executed comparison.
            "PublicationReferenceComparisonOk": "1",
        }],
    )
    expected = {gate: True for gate in PRODUCTION_GATE_ORDER}
    expected["IndependentFRCQualification"] = False
    expected["IndependentReferenceComparison"] = False
    expected["ProductionGrade"] = False
    rows = _production_gate_rows(expected)
    _write_rows(tmp_path / "reports/csv/production_qualification_gate.csv", rows)
    checks = _audit_production_qualification_reducer(tmp_path)
    assert all(check.passed for check in checks), [check.details for check in checks]

    rows[-1]["Pass"] = "1"
    rows[-1]["Status"] = "PASS"
    rows[-1]["FailureReason"] = ""
    _write_rows(tmp_path / "reports/csv/production_qualification_gate.csv", rows)
    checks = _audit_production_qualification_reducer(tmp_path)
    assert not checks[0].passed
    assert "ProductionGrade:Pass=True;expected=False" in checks[0].details


def test_production_gate_honors_explicit_optional_reference_authority(
    tmp_path: Path,
) -> None:
    _write_rows(
        tmp_path / "reports/csv/result_status_summary.csv",
        [{
            "ResultOk": "1", "ExecutionCompleted": "1",
            "RuntimeTruthContractOk": "1", "MandatorySubsystemsOk": "1",
            "KpiConsistencyOk": "1", "ScenarioObjectiveOk": "1",
        }],
    )
    _write_rows(
        tmp_path / "reports/csv/phy_package_execution_evidence_gate.csv",
        [{"Gate": "runtime", "Required": "1", "Pass": "1"}],
    )
    _write_rows(
        tmp_path / "reports/csv/phase7_truth_gates.csv",
        [_complete_phase7_row()],
    )
    _write_rows(
        tmp_path / "reports/csv/publication_readiness_gate_summary.csv",
        [{"TerminalPublicationGatesOk": "1"}],
    )
    config_path = tmp_path / "meta/scenario_config_resolved.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps({
        "validation": {
            "independent_reference_qualification": {
                "required_for_production": False,
            },
        },
    }), encoding="utf-8")

    expected = {gate: True for gate in PRODUCTION_GATE_ORDER}
    expected["IndependentFRCQualification"] = False
    expected["IndependentReferenceComparison"] = False
    required = {gate: True for gate in PRODUCTION_GATE_ORDER}
    required["IndependentFRCQualification"] = False
    required["IndependentReferenceComparison"] = False
    rows = _production_gate_rows(expected, required)
    reference_row = next(
        row for row in rows
        if row["Gate"] == "IndependentFRCQualification"
    )
    _write_rows(tmp_path / "reports/csv/production_qualification_gate.csv", rows)

    checks = _audit_production_qualification_reducer(tmp_path)
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_fixed_snr_reference_comparison_is_independent_of_optional_frc(
    tmp_path: Path,
) -> None:
    _write_rows(
        tmp_path / "reports/csv/result_status_summary.csv",
        [{
            "ResultOk": "1", "ExecutionCompleted": "1",
            "RuntimeTruthContractOk": "1", "MandatorySubsystemsOk": "1",
            "KpiConsistencyOk": "1", "ScenarioObjectiveOk": "1",
        }],
    )
    _write_rows(
        tmp_path / "reports/csv/phy_package_execution_evidence_gate.csv",
        [{"Gate": "runtime", "Required": "1", "Pass": "1"}],
    )
    phase = _complete_phase7_row()
    phase["RunClass"] = "fixed_snr_sweep_lls"
    _write_rows(tmp_path / "reports/csv/phase7_truth_gates.csv", [phase])
    _write_rows(
        tmp_path / "reports/csv/publication_readiness_gate_summary.csv",
        [{
            "PublicationReferenceComparisonOk": "0",
            "TerminalPublicationGatesOk": "0",
        }],
    )
    config_path = tmp_path / "meta/scenario_config_resolved.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps({
        "validation": {
            "independent_reference_qualification": {
                "required_for_production": False,
            },
        },
    }), encoding="utf-8")

    expected = {gate: True for gate in PRODUCTION_GATE_ORDER}
    expected.update({
        "IndependentFRCQualification": False,
        "IndependentReferenceComparison": False,
        "TerminalPublicationEvidence": False,
        "ProductionGrade": False,
    })
    required = {gate: True for gate in PRODUCTION_GATE_ORDER}
    required["IndependentFRCQualification"] = False
    rows = _production_gate_rows(expected, required)
    _write_rows(tmp_path / "reports/csv/production_qualification_gate.csv", rows)
    checks = _audit_production_qualification_reducer(tmp_path)
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_functional_run_statistics_remain_truthfully_not_evaluated(
    tmp_path: Path,
) -> None:
    _write_rows(
        tmp_path / "reports/csv/result_status_summary.csv",
        [{
            "ResultOk": "1", "ExecutionCompleted": "1",
            "RuntimeTruthContractOk": "1", "MandatorySubsystemsOk": "1",
            "KpiConsistencyOk": "1", "ScenarioObjectiveOk": "1",
        }],
    )
    _write_rows(
        tmp_path / "reports/csv/phy_package_execution_evidence_gate.csv",
        [{"Gate": "runtime", "Required": "1", "Pass": "1"}],
    )
    phase = _complete_phase7_row()
    phase["RunClass"] = "functional_waveform_validation"
    for name in (
        "SeedHierarchyOk", "CampaignDesignOk", "CampaignCompletionOk",
        "MultiSeedDropStatisticsOk", "ConfidenceIntervalsOk",
        "SampleAdequacyOk", "SweepDataQualityOk",
    ):
        phase[name] = "0"
    phase["Phase7Ok"] = "0"
    _write_rows(tmp_path / "reports/csv/phase7_truth_gates.csv", [phase])
    _write_rows(
        tmp_path / "reports/csv/statistical_qualification_gate.csv",
        [{
            "Component": "PDCCH", "RequiredForStandardsClaim": "0",
            "StatisticallyQualified": "0", "ReportedStatisticalStatus": "NOT_REQUIRED",
        }],
    )
    _write_rows(
        tmp_path / "reports/csv/publication_readiness_gate_summary.csv",
        [{"TerminalPublicationGatesOk": "0"}],
    )
    expected = {gate: False for gate in PRODUCTION_GATE_ORDER}
    expected.update({
        "FunctionalRun": True,
        "ScenarioObjective": True,
        "RuntimeWiringCoverage": True,
    })
    rows = _production_gate_rows(expected)
    statistical_row = next(
        row for row in rows if row["Gate"] == "StatisticalQualification"
    )
    statistical_row["Status"] = "NOT_EVALUATED"
    _write_rows(tmp_path / "reports/csv/production_qualification_gate.csv", rows)
    checks = _audit_production_qualification_reducer(tmp_path)
    assert all(check.passed for check in checks), [check.details for check in checks]


def test_gate_table_source_row_count_is_recomputed_not_trusted(tmp_path: Path) -> None:
    _write_rows(tmp_path / "reports/csv/source.csv", [{"x": "1"}, {"x": "2"}])
    _write_rows(
        tmp_path / "reports/csv/scenario_objective_gates.csv",
        [{
            "ObjectiveName": "runtime_truth", "Mandatory": "1", "Pass": "1",
            "SourceCsv": "reports/csv/source.csv", "SourceRowCount": "1",
            "FailureReason": "",
        }],
    )
    check = _audit_gate_row_table(
        tmp_path,
        "reports/csv/scenario_objective_gates.csv",
        key_column="ObjectiveName",
        required_column="Mandatory",
        pass_column="Pass",
        evidence_column="SourceCsv",
        source_count_column="SourceRowCount",
    )
    assert not check.passed
    assert "source_row_count_mismatch=1.0!=2" in check.details


def test_measurement_sidecar_manifest_recomputes_persisted_shape(tmp_path: Path) -> None:
    source_rel = "air_interface/csv/dl_pdsch_trials.csv"
    measurement_rel = "reports/csv/measurements/dl_pdsch_measurements.csv"
    provenance_rel = "reports/csv/provenance_sidecars/dl_pdsch_provenance.csv"
    _write_rows(tmp_path / source_rel, [{"TrialId": "1"}, {"TrialId": "2"}])
    _write_rows(
        tmp_path / measurement_rel,
        [
            {"TrialId": "1", "Value": "2", "SourceArtifact": source_rel},
            {"TrialId": "2", "Value": "3", "SourceArtifact": source_rel},
        ],
    )
    _write_rows(
        tmp_path / provenance_rel,
        [
            {"TrialId": "1", "ValueSource": "runtime", "SourceArtifact": source_rel},
            {"TrialId": "2", "ValueSource": "runtime", "SourceArtifact": source_rel},
        ],
    )
    manifest = {
        "SourceArtifact": source_rel,
        "MeasurementArtifact": measurement_rel,
        "ProvenanceArtifact": provenance_rel,
        "SourceRows": "2",
        "MeasurementRows": "2",
        "ProvenanceRows": "2",
        "MeasurementColumnCount": "3",
        "ProvenanceColumnCount": "3",
        "SplitKind": "measurement",
    }
    _write_rows(tmp_path / "reports/csv/measurement_sidecar_manifest.csv", [manifest])
    checks = _audit_measurement_sidecar_manifest(tmp_path)
    assert all(check.passed for check in checks), [check.details for check in checks]

    manifest["MeasurementColumnCount"] = "99"
    _write_rows(tmp_path / "reports/csv/measurement_sidecar_manifest.csv", [manifest])
    checks = _audit_measurement_sidecar_manifest(tmp_path)
    assert not checks[0].passed
    assert "MeasurementColumnCount_mismatch=99.0!=3" in checks[0].details


def test_canonical_component_manifest_binds_catalog_schema_hash_and_rows(tmp_path: Path) -> None:
    published_rel = "components/pdsch/csv/pdsch_bler_curve.csv"
    _write_rows(
        tmp_path / published_rel,
        [
            {"CampaignID": "c", "OperatingPointID": "1", "BLER": "0.5"},
            {"CampaignID": "c", "OperatingPointID": "2", "BLER": "0.1"},
        ],
    )
    payload = (tmp_path / published_rel).read_bytes()
    digest = hashlib.sha256(payload).hexdigest()
    contract_id = "pdsch|base|csv|pdsch_bler_curve.csv|all|runtime_in_path"
    manifest = {
        "ContractID": contract_id,
        "ArtifactType": "CSV",
        "Required": "1",
        "Status": "PASS",
        "SourceRows": "2",
        "PublishedRelativePath": published_rel,
        "SourceSHA256": digest,
        "SHA256": digest,
        "ByteSize": str(len(payload)),
        "Message": "",
    }
    catalog = {
        "ContractID": contract_id,
        "ArtifactType": "CSV",
        "Required": "1",
        "MinimumRows": "1",
        "RequiredColumns": "CampaignID|OperatingPointID|BLER",
        "PrimaryKey": "CampaignID|OperatingPointID",
    }
    _write_rows(tmp_path / "artifact_generation/canonical_component_manifest.csv", [manifest])
    _write_rows(tmp_path / "artifact_generation/contract_catalog_snapshot.csv", [catalog])
    checks = _audit_canonical_component_manifest(tmp_path)
    assert all(check.passed for check in checks), [check.details for check in checks]

    manifest["SHA256"] = "0" * 64
    _write_rows(tmp_path / "artifact_generation/canonical_component_manifest.csv", [manifest])
    checks = _audit_canonical_component_manifest(tmp_path)
    assert not checks[0].passed
    assert "published_sha256_mismatch" in checks[0].details


def test_mcs_cqi_reference_tables_verify_spectral_efficiency(tmp_path: Path) -> None:
    identity = {"ScenarioID": "scenario", "ConfigHash": "a" * 64, "Direction": "DL"}
    mcs_rows = [
        {**identity, "MCSTable": "qam64", "MCSIndex": "0", "Modulation": "QPSK", "TargetCodeRate": "0.25", "SpectralEfficiency": "0.5"},
        {**identity, "MCSTable": "qam64", "MCSIndex": "1", "Modulation": "16QAM", "TargetCodeRate": "0.5", "SpectralEfficiency": "2"},
    ]
    cqi_rows = [
        {**identity, "CQITable": "table1", "CQI": "0", "Modulation": "", "TargetCodeRate": "0", "SpectralEfficiency": "0"},
        {**identity, "CQITable": "table1", "CQI": "1", "Modulation": "QPSK", "TargetCodeRate": "0.25", "SpectralEfficiency": "0.5"},
    ]
    _write_rows(tmp_path / "reports/csv/mcs_table_reference.csv", mcs_rows)
    _write_rows(tmp_path / "reports/csv/cqi_table_reference.csv", cqi_rows)
    checks = _audit_mcs_cqi_reference_tables(tmp_path)
    assert all(check.passed for check in checks), [check.details for check in checks]

    mcs_rows[1]["SpectralEfficiency"] = "9"
    _write_rows(tmp_path / "reports/csv/mcs_table_reference.csv", mcs_rows)
    checks = _audit_mcs_cqi_reference_tables(tmp_path)
    assert not checks[0].passed
    assert "spectral_efficiency_mismatch" in checks[0].details


def test_dut_reference_summary_is_recomputed_from_detail(tmp_path: Path) -> None:
    artifact_rel = "air_interface/csv/dl_pdsch_trials.csv"
    _write_rows(tmp_path / artifact_rel, [{"TBSize_bits": "100"}])
    detail = {
        "RunId": "run", "BlockId": "PDSCH", "DUTValue": "100",
        "ReferenceValue": "100", "DeltaAbs": "0", "ToleranceAbs": "0",
        "ToleranceRel": "0", "Pass": "1", "ReferenceAvailable": "1",
        "ReferenceSource": "nrTBS", "DUTArtifactPath": artifact_rel,
        "FailureReason": "",
    }
    summary = {
        "RunId": "run", "BlockId": "PDSCH", "ReferenceAvailable": "1",
        "ComparisonCount": "1", "PassCount": "1", "FailCount": "0",
        "DUTReferencePass": "1", "ReferenceSources": "nrTBS",
        "MaxAbsDelta": "0", "FailureReason": "",
    }
    _write_rows(tmp_path / "reports/csv/dut_reference_comparison.csv", [detail])
    _write_rows(tmp_path / "reports/csv/lls_reference_comparison_summary.csv", [summary])
    checks = _audit_dut_reference_comparison(tmp_path)
    assert all(check.passed for check in checks), [check.details for check in checks]

    summary["PassCount"] = "0"
    _write_rows(tmp_path / "reports/csv/lls_reference_comparison_summary.csv", [summary])
    checks = _audit_dut_reference_comparison(tmp_path)
    assert not checks[1].passed
    assert "PassCount_mismatch" in checks[1].details


def _fixed_point_fixture(direction: str, crc_pass: bool) -> tuple[dict[str, str], dict[str, str]]:
    failures = 0 if crc_pass else 1
    errors = failures
    bler_low, bler_high = _clopper_pearson_two_sided(failures, 1, 0.95)
    ber_low, ber_high = _clopper_pearson_two_sided(errors, 1, 0.95)
    measured = "1" if direction == "UL" else "0"
    goodput = "2" if crc_pass else "0"
    raw = {
        "FixedLinkPointIndex": "1", "PointSeed": "101",
        "ConfiguredSNR_dB": "0", "AppliedAWGNSNR_dB": "0",
        "MCSIndex": "1", "Modulation": "QPSK", "Rank": "1", "Layers": "1",
        "CRCPass": "1" if crc_pass else "0", "BitErrors": str(errors),
        "BitsCompared": "1", "MeasuredTrialSINR_dB": measured,
        "Goodput_Mbps": goodput,
    }
    summary = {
        "Direction": direction, "PointIndex": "1", "PointSeed": "101",
        "SNR_dB": "0", "ConfiguredSNR_dB": "0", "AppliedSNR_dB": "0",
        "MeanMeasuredSINR_dB": measured, "MedianMeasuredSINR_dB": measured,
        "MCS": "1", "Modulation": "QPSK", "Rank": "1", "Layers": "1",
        "TrialCount": "1", "TBPassCount": "1" if crc_pass else "0",
        "TBFailCount": str(failures), "BLER": str(float(failures)),
        "BLER_CI_Low": str(bler_low), "BLER_CI_High": str(bler_high),
        "BLER_CI_Width": str(bler_high - bler_low),
        "BitErrors": str(errors), "BitsCompared": "1", "BER": str(float(errors)),
        "BER_CI_Low": str(ber_low), "BER_CI_High": str(ber_high),
        "BER_CI_Width": str(ber_high - ber_low),
        "Throughput_Mbps": goodput, "Goodput_Mbps": goodput,
        "PointStatus": "COMPLETE", "Incomplete": "0", "Status": "complete",
    }
    return raw, summary


def test_fixed_snr_reports_are_recomputed_from_primary_trials(tmp_path: Path) -> None:
    dl_raw, dl_summary = _fixed_point_fixture("DL", False)
    ul_raw, ul_summary = _fixed_point_fixture("UL", True)
    ul_summary["PointStatus"] = "CENSORED_COMPLETE"
    summary_rows = [dl_summary, ul_summary]
    summary_rel = "reports/csv/fixed_snr_sweep_curve_summary.csv"
    _write_rows(tmp_path / summary_rel, summary_rows)
    for direction, source in (("dl", dl_summary), ("ul", ul_summary)):
        for metric in ("bler", "ber"):
            _write_rows(
                tmp_path / f"reports/csv/{direction}_fixed_snr_{metric}_curve.csv",
                [source],
            )
            value_field = metric.upper()
            metric_row = {
                "Direction": direction.upper(), "Metric": value_field,
                "PointIndex": "1", "Value": source[value_field],
                "CI_Low": source[value_field + "_CI_Low"],
                "CI_High": source[value_field + "_CI_High"],
                "TrialCount": "1", "FailureCount": source["TBFailCount"],
                "MeasuredSINR_dB": source["MeanMeasuredSINR_dB"],
                "Throughput_Mbps": source["Throughput_Mbps"],
                "Goodput_Mbps": source["Goodput_Mbps"],
            }
            _write_rows(
                tmp_path / f"reports/csv/{direction}_fixed_link_{metric}_curve.csv",
                [metric_row],
            )
    campaign_rows = []
    for direction, source in (("DL", dl_summary), ("UL", ul_summary)):
        campaign_rows.append({
            "Direction": direction, "SNRPointCount": "1", "TotalTBCount": "1",
            "TotalFailureCount": source["TBFailCount"],
            "MaxBLERCIHalfWidth": str(float(source["BLER_CI_Width"]) / 2),
            "IncompletePointCount": "0", "CurvePresent": "1",
        })
    _write_rows(tmp_path / "reports/csv/fixed_link_campaign_summary.csv", campaign_rows)
    _write_rows(
        tmp_path / "reports/csv/fixed_snr_sweep_required_outputs.csv",
        [{
            "ArtifactPath": summary_rel, "Direction": "global", "Required": "1",
            "Present": "1", "Readable": "1", "NonEmpty": "1", "Status": "PASS",
        }],
    )
    _write_rows(
        tmp_path / "reports/csv/fixed_snr_sweep_audit.csv",
        [{
            "CheckName": "curve", "Scope": summary_rel, "RowsChecked": "2",
            "RowsFailed": "0", "Status": "PASS",
        }],
    )
    checks = _audit_fixed_snr_reporting_tables(
        tmp_path, {"DL": [dl_raw], "UL": [ul_raw]}
    )
    assert all(check.passed for check in checks), [check.details for check in checks]

    dl_summary["BLER"] = "0.5"
    _write_rows(tmp_path / summary_rel, [dl_summary, ul_summary])
    checks = _audit_fixed_snr_reporting_tables(
        tmp_path, {"DL": [dl_raw], "UL": [ul_raw]}
    )
    assert not checks[0].passed
    assert "DL:point=1:BLER_mismatch" in checks[0].details


def test_kpi_source_manifest_names_exact_consumed_table(tmp_path: Path) -> None:
    for direction, name in (("DL", "dl_pdsch_trials"), ("UL", "ul_pusch_trials")):
        _write_rows(
            tmp_path / f"air_interface/csv/{name}.csv",
            [{"Direction": direction, "Goodput_Mbps": "1"}],
        )
    manifest_rows = []
    for direction, path in (
        ("UL", "air_interface/csv/ul_pusch_trials.csv"),
        ("DL", "air_interface/csv/dl_pdsch_trials.csv"),
    ):
        manifest_rows.append({
            "RunId": "run", "ScenarioName": "scenario",
            "SourceTablePath": path, "SourceTableName": Path(path).stem,
            "Direction": direction, "Layer": "PHY",
            "RequiredForObjective": "1", "Exists": "1", "RowCount": "1",
            "ColumnCount": "2", "FileHash": "a" * 64,
            "SchemaHash": "kpi_schema_v1", "ProducerModule": "producer",
            "Status": "pass", "FailureReason": "",
        })
    for direction, path, layer in (
        ("PacketSDU", "packet_flow/csv/live_packet_sdu_delivery_ledger.csv", "MAC"),
        ("ApplicationPackets", "packet_flow/csv/live_application_packet_delivery_ledger.csv", "application"),
        ("HARQTimeline", "harq/csv/live_harq_observation_timeline.csv", "HARQ"),
        ("ULGrants", "packet_flow/csv/live_ul_scheduler_grants.csv", "scheduler"),
        ("DLGrants", "packet_flow/csv/live_dl_scheduler_grants.csv", "scheduler"),
        ("SlotTrace", "packet_flow/csv/slot_trace.csv", "scheduler"),
    ):
        manifest_rows.append({
            "RunId": "run", "ScenarioName": "scenario",
            "SourceTablePath": path, "SourceTableName": Path(path).stem,
            "Direction": direction, "Layer": layer,
            "RequiredForObjective": "0", "Exists": "0", "RowCount": "0",
            "ColumnCount": "0", "FileHash": "empty",
            "SchemaHash": "kpi_schema_v1", "ProducerModule": "producer",
            "Status": "not_applicable",
            "FailureReason": "source_not_required_by_resolved_feature_applicability",
        })
    _write_rows(tmp_path / "reports/csv/kpi_source_table_manifest.csv", manifest_rows)
    _write_rows(
        tmp_path / "reports/csv/kpi_formula_registry.csv",
        [{
            "KPIName": "DL_Goodput", "Direction": "DL", "Layer": "PHY",
            "Units": "Mbps", "RequiredSourceTables": "dl_pdsch_trials",
            "Tolerance": "1e-9", "StrictAllowed": "1",
            "FormulaVersion": "v1", "FormulaEquation": "bits/time",
            "ProducerModule": "producer", "Status": "active",
        }],
    )
    checks = _audit_kpi_reporting_tables(tmp_path)
    manifest_check = next(
        check for check in checks if check.artifact_path == "reports/csv/kpi_source_table_manifest.csv"
    )
    assert manifest_check.passed, manifest_check.details

    manifest_rows[1]["SourceTablePath"] = "air_interface/csv/dl_fixed_link_campaign_trials.csv"
    _write_rows(tmp_path / "reports/csv/kpi_source_table_manifest.csv", manifest_rows)
    checks = _audit_kpi_reporting_tables(tmp_path)
    manifest_check = next(
        check for check in checks if check.artifact_path == "reports/csv/kpi_source_table_manifest.csv"
    )
    assert not manifest_check.passed
    assert "persisted_source_shape_or_exists_mismatch" in manifest_check.details


def test_kpi_mixed_harq_source_uses_direction_scoped_manifest_hashes(
    tmp_path: Path,
) -> None:
    timeline_path = "harq/csv/live_harq_observation_timeline.csv"
    _write_rows(
        tmp_path / timeline_path,
        [
            {"Direction": "DL", "CombinedDecodeOK": "1"},
            {"Direction": "UL", "CombinedDecodeOK": "0"},
        ],
    )
    manifest_rows = []
    for direction, path, layer in (
        ("UL", "air_interface/csv/ul_pusch_trials.csv", "PHY"),
        ("DL", "air_interface/csv/dl_pdsch_trials.csv", "PHY"),
        ("PacketSDU", "packet_flow/csv/live_packet_sdu_delivery_ledger.csv", "MAC"),
        ("ApplicationPackets", "packet_flow/csv/live_application_packet_delivery_ledger.csv", "application"),
        ("HARQTimeline", timeline_path, "HARQ"),
        ("ULGrants", "packet_flow/csv/live_ul_scheduler_grants.csv", "scheduler"),
        ("DLGrants", "packet_flow/csv/live_dl_scheduler_grants.csv", "scheduler"),
        ("SlotTrace", "packet_flow/csv/slot_trace.csv", "scheduler"),
    ):
        exists = direction == "HARQTimeline"
        manifest_rows.append({
            "RunId": "run", "ScenarioName": "scenario",
            "SourceTablePath": path, "SourceTableName": Path(path).stem,
            "Direction": direction, "Layer": layer,
            "RequiredForObjective": "1" if exists else "0",
            "Exists": "1" if exists else "0",
            "RowCount": "2" if exists else "0",
            "ColumnCount": "2" if exists else "0",
            "FileHash": "a" * 64 if exists else "empty",
            "DLSubsetRowCount": "1" if exists else "0",
            "DLSubsetRowsHash": "b" * 64 if exists else "empty",
            "ULSubsetRowCount": "1" if exists else "0",
            "ULSubsetRowsHash": "c" * 64 if exists else "empty",
            "SchemaHash": "kpi_schema_v1", "ProducerModule": "producer",
            "Status": "pass" if exists else "not_applicable",
            "FailureReason": "" if exists else "source_not_required",
        })
    _write_rows(tmp_path / "reports/csv/kpi_source_table_manifest.csv", manifest_rows)
    _write_rows(tmp_path / "reports/csv/kpi_formula_registry.csv", [{
        "KPIName": "DL_HARQ_NACK_Rate", "Direction": "DL", "Layer": "HARQ",
        "Units": "ratio", "RequiredSourceTables": "harq_timeline",
        "Tolerance": "1e-9", "StrictAllowed": "1", "FormulaVersion": "v1",
        "FormulaEquation": "nack/events", "ProducerModule": "producer",
        "Status": "active",
    }])
    reconstruction = {
        "KPIName": "DL_HARQ_NACK_Rate", "Direction": "DL",
        "FormulaId": "DL_HARQ_NACK_Rate", "FormulaVersion": "v1",
        "Value": "0", "SourceTablePaths": timeline_path,
        "SourceRowCount": "1", "EligibleRowCount": "1", "ExcludedRowCount": "0",
        "SourceRowsHash": "b" * 64, "MissingRawData": "0",
        "SchemaValid": "1", "Applicable": "1", "ApplicabilityReason": "harq_enabled",
        "FormulaExecuted": "1", "ReconstructionValue": "0",
        "ReconciliationTolerance": "1e-9", "ReconciliationPass": "1",
        "StrictOk": "1", "Status": "pass", "FailureReason": "",
    }
    _write_rows(tmp_path / "reports/csv/kpi_reconstruction_summary.csv", [reconstruction])
    checks = _audit_kpi_reporting_tables(tmp_path)
    check = next(
        item for item in checks
        if item.artifact_path == "reports/csv/kpi_reconstruction_summary.csv"
    )
    assert check.passed, check.details

    reconstruction["SourceRowsHash"] = "d" * 64
    _write_rows(tmp_path / "reports/csv/kpi_reconstruction_summary.csv", [reconstruction])
    checks = _audit_kpi_reporting_tables(tmp_path)
    check = next(
        item for item in checks
        if item.artifact_path == "reports/csv/kpi_reconstruction_summary.csv"
    )
    assert not check.passed
    assert "source_count_or_hash_manifest_mismatch" in check.details
