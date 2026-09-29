from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps"))

import lls_web_dashboard as dashboard  # noqa: E402


def test_ul_preview_keeps_codebook_ports_distinct_from_spatial_beams() -> None:
    labels = dict(dashboard.DATA_TRIAL_PREVIEW_COLUMNS["ul_trials"])
    assert labels["AppliedPrecoderPMI"] == "Applied TPMI"
    assert labels["AppliedCodebookPortIndexSet"] == "Codebook ports (1-based)"
    assert labels["PrecodingNumLogicalPorts"] == "Logical ports"
    assert labels["AppliedBeamIndexSet"] == "Applied spatial beam"
    assert "AppliedCodebookPortIndexSet" not in dict(dashboard.DATA_TRIAL_PREVIEW_COLUMNS["dl_trials"])


def test_access_and_beam_previews_retain_exact_runtime_identity() -> None:
    msg1 = dashboard.summarize_procedure_preview_rows(
        "msg1_detection",
        [{
            "UEId": 1,
            "Slot": 9,
            "AssociatedSSBIndex": 1,
            "RootSequenceIndex": 7,
            "PreambleIndexTx": 11,
            "PreambleIndexDetected": 11,
            "FrequencyEstimationEnabled": 1,
            "FrequencyEstimate_Hz": -125.0,
            "FrequencyEstimateValid": 1,
            "RawTimingEstimate_samples": 1258,
            "TimingOffsetSamples": 22,
            "TimingAdvanceCommand": 1,
            "RARNTI": 127,
            "Status": "OK",
        }],
    )
    assert msg1 == [{
        "UE": 1,
        "Slot": 9,
        "Associated SSB beam": 1,
        "Root sequence index (RSI)": 7,
        "TX preamble": 11,
        "Detected preamble": 11,
        "Frequency estimate enabled": 1,
        "Detected frequency offset Hz": -125.0,
        "Frequency estimate valid": 1,
        "Raw timing samples": 1258,
        "Propagation timing samples": 22,
        "RAR TA command": 1,
        "RA-RNTI": 127,
        "Status": "OK",
    }]
    beam = dashboard.summarize_procedure_preview_rows(
        "beam_state",
        [{
            "EventSequence": 4,
            "UEIndex": 1,
            "Slot": 28,
            "FromState": "P2_MEASURING",
            "Event": "TCI_ACTIVATED",
            "ToState": "ACTIVE",
            "MeasuredResourceID": "CSI-RS-3",
            "ActivatedTCIState": 3,
            "GeometryOracleUsed": 0,
            "SelectionAuthority": "receiver_measurement_and_decoded_control",
        }],
    )
    assert beam[0]["Measured RS/beam"] == "CSI-RS-3"
    assert beam[0]["Activated TCI state"] == 3
    assert beam[0]["Geometry oracle used"] == 0


def test_ssb_sync_preview_separates_injection_estimate_correction_and_residual() -> None:
    labels = dict(dashboard.CONTROL_TRIAL_PREVIEW_COLUMNS["pbch_trials"])
    assert labels["InjectedCFO_Hz"] == "Configured / injected CFO (Hz)"
    assert labels["EstimatedCFO_PreCorrection_Hz"] == "Estimated CFO (Hz)"
    assert labels["CFOEstimateAvailability"] == "CFO estimate availability"
    assert labels["SIB1CFOCorrectionApplied_Hz"] == "Applied CFO correction (Hz)"
    assert labels["ResidualCFO_PostCorrection_Hz"] == "Residual CFO (Hz)"
    assert labels["ResidualCFOMeasurementStatus"] == "Residual CFO status"
    assert labels["AppliedTimingCorrection_samples"] == "Applied timing correction (samples)"


def test_waveform_quality_previews_expose_evm_nmse_and_receiver_plane() -> None:
    for key in ("pbch_trials", "pdcch_trials", "pucch_trials", "srs_trials", "trs_trials"):
        labels = dict(dashboard.CONTROL_TRIAL_PREVIEW_COLUMNS[key])
        assert "EVM_rms" in labels
        assert "NMSE_dB" in labels
    for key in ("dl_trials", "ul_trials"):
        labels = dict(dashboard.DATA_TRIAL_PREVIEW_COLUMNS[key])
        assert labels["EVM_rms"] == "EVM rms"
        assert labels["NMSE_dB"] == "NMSE dB"
        assert labels["ChannelEstimateAvailable"] == "Channel estimate available"
        assert labels["EqualizationAvailable"] == "Equalization available"


def test_trs_preview_separates_scheduler_tracking_and_qualification() -> None:
    labels = dict(dashboard.CONTROL_TRIAL_PREVIEW_COLUMNS["trs_trials"])
    assert labels["TrackingEligibility"] == "Scheduler usable"
    assert labels["TRSValidityState"] == "Tracking state"
    assert labels["StrictOk"] == "Qualification pass"


def test_beam_power_preview_keeps_absolute_and_normalized_units_distinct() -> None:
    labels = dict(dashboard.PROCEDURE_PREVIEW_COLUMNS["beam_state"])
    assert labels["MeasuredRSRPDBM"] == "Legacy RSRP column (unit not inferred)"
    assert labels["MeasuredRSRPDBReUnitOccupiedREEs"] == "Measured SS-RSRP (dB re unit Es)"
    assert labels["MeasuredPowerUnit"] == "Measured power unit"
    assert labels["PowerReferencePlane"] == "Power reference plane"


def test_qcl_tci_and_srs_angle_labels_do_not_upgrade_model_metadata() -> None:
    dl = dashboard.summarize_data_trial_preview_rows(
        "dl_trials",
        [{
            "Slot": 31,
            "UEID": 1,
            "QCLStatus": "bound_received_reference_timing_prior",
            "QCLType": "A",
            "QCLSourceRS": "NZP-CSI-RS/TRS",
            "QCLSourceResourceID": 3000,
            "QCLTimingPriorUsed": 1,
            "TCIStateID": 3,
            "TCICodepoint": 1,
            "TCIStatus": "received_codepoint_bound_to_preconfigured_state",
        }],
    )[0]
    assert dl["QCL source RS"] == "NZP-CSI-RS/TRS"
    assert dl["TCI state ID"] == 3
    angles = dashboard.summarize_procedure_preview_rows(
        "channel_angles",
        [{
            "Direction": "UL",
            "TapIndex": 1,
            "AzimuthDeparture_deg": -46.6,
            "ZenithDeparture_deg": 97.2,
            "AzimuthArrival_deg": -101.0,
            "ZenithArrival_deg": 87.6,
            "AngleCoordinateFrame": "3gpp_tr38901_global_coordinate_system",
            "Source": "sixgr.channel.ChannelFactory.info.model_profile_metadata_not_in_path_realization",
        }],
    )[0]
    assert angles["AoD azimuth deg"] == -46.6
    assert "model_profile_metadata" in angles["Source"]


def artifact(path: str, mime_type: str = "text/csv", artifact_id: int = 1) -> dict:
    return {
        "artifact_id": artifact_id,
        "logical_path": path,
        "mime_type": mime_type,
        "artifact_kind": "table_csv" if path.endswith(".csv") else "image",
        "created_utc": "2026-08-02T00:00:00Z",
        "byte_size": 10,
    }


def test_component_dashboard_separates_raster_from_legacy_svg() -> None:
    rows = dashboard.build_realtime_component_dashboard(
        [
            artifact("air_interface/csv/prach_trials.csv", artifact_id=1),
            artifact("reports/image/prach_correlation.png", "image/png", 2),
            artifact("reports/image/prach_legacy.svg", "image/svg+xml", 3),
            artifact("air_interface/csv/dl_pdsch_trials.csv", artifact_id=4),
            artifact("prach/csv/prach_trials.csv", artifact_id=5),
            artifact("reports/csv/mac_harq_trials.csv", artifact_id=6),
            artifact("reports/image/channel_geometry.png", "image/png", 7),
        ],
        "completed",
    )
    by_id = {row["component_id"]: row for row in rows}
    assert len(rows) == 24
    assert len(by_id) == len(rows)
    assert by_id["prach_rach"]["status"] == "evidence_available"
    assert by_id["prach_rach"]["csv_count"] == 1
    assert by_id["prach_rach"]["image_count"] == 1
    assert by_id["prach_rach"]["legacy_svg_count"] == 1
    assert by_id["prach_rach"]["planned_folder"] == "prach"
    assert "pass" not in by_id["prach_rach"]["status"]
    assert by_id["l3"]["status"] == "not_published"
    assert by_id["mac_harq_scheduler"]["csv_count"] == 1
    assert by_id["channel"]["image_count"] == 1
    assert dashboard.is_component_view_artifact_path("prach/csv/prach_trials.csv")
    assert not dashboard.is_component_view_artifact_path(
        "control/csv/prach_trials.csv"
    )


def test_canonical_component_dashboard_uses_exact_folder_ownership() -> None:
    rows = dashboard.build_realtime_component_dashboard(
        [
            artifact(
                "components/initial_access/qualification/csv/type0_coreset_resolution.csv",
                artifact_id=1,
            ),
            artifact(
                "components/pdcch/qualification/csv/pdcch_detection_trials.csv",
                artifact_id=2,
            ),
            artifact(
                "components/frame_grid/qualification/png/channel_grid.png",
                "image/png",
                3,
            ),
            artifact(
                "artifact_generation/component_qualification_manifest.csv",
                artifact_id=4,
            ),
        ],
        "completed_with_failures",
    )
    by_id = {row["component_id"]: row for row in rows}
    assert by_id["pdcch"]["artifact_count"] == 1
    assert by_id["pdcch"]["latest_artifacts"][0]["logical_path"].startswith(
        "components/pdcch/"
    )
    assert by_id["channel"]["artifact_count"] == 0
    assert by_id["channel"]["status"] == "not_published"
    assert by_id["mimo"]["artifact_count"] == 0
    assert by_id["frame_grid"]["artifact_count"] == 1


def test_ue_status_merges_control_and_performance_without_upgrading_fidelity() -> None:
    metric_explorer = {
        "ue_summaries": {
            "1": {
                "ueid": 1,
                "dl_bler": 0.0,
                "ul_bler": 0.25,
                "dl_mean_measured_sinr_dB": 12.5,
                "ul_mean_measured_sinr_dB": 7.0,
                "source_table": "reports/csv/live_user_performance_snapshot.csv",
                "fidelity_level": "abstraction_level",
            }
        }
    }
    runtime = {
        "control_state_preview": [
            {
                "UEIndex": 1,
                "ServingCell": 3,
                "SchedulingEligibility": 1,
                "AccessState": "connected",
                "LastPDCCHStatus": "control_ok",
                "SRSValidityState": "valid",
                "CSIValidityState": "fresh_srs",
                "TRSValidityState": "valid",
            }
        ]
    }
    rows = dashboard.build_realtime_ue_status(metric_explorer, runtime)
    assert len(rows) == 1
    assert rows[0]["ue_id"] == "1"
    assert rows[0]["health"] == "attention"
    assert rows[0]["scheduling_eligible"] is True
    assert rows[0]["performance_fidelity"] == "abstraction_level"
    assert rows[0]["control_source"] == "reports/csv/live_control_gating_state.csv"


def test_ue_status_keeps_serving_ss_and_csi_measurements_distinct() -> None:
    sources = {
        "serving": [{"UEID": 1, "Slot": 8, "ServingRSRP_dBm": -82.5}],
        "csi": [
            {
                "UEIndex": 1,
                "Slot": 8,
                "MeasurementRSRP_dBm": -86.25,
                "MeasurementRelativeRSRP_dB": 23.0,
                "MeasurementRSRPPerReceiveAntenna_dBm": "[-85.5,-87.2]",
                "SINR_dB": 11.75,
                "SINRMeasurementDomain": "csi_rs_resource_selective_channel_estimate",
                "PhysicalMeasurementStatus": "available",
                "MeasurementSource": "nrCSIRSMeasurements_runtime_received_grid",
                "MeasurementPowerUnit": "dB_re_unit_occupied_RE_Es",
                "PowerReferencePlane": "normalized_fixed_snr_occupied_re",
            }
        ],
        "ssb": [
            {
                "UEID": 1,
                "Slot": 2,
                "SS_RSRP_dBm": -91.0,
                "SS_SINR_dB": 7.5,
                "ConfiguredSNR_dB": 3.0,
                "MeasuredReferenceSignalChannelGain_dB": 4.25,
                "SSSINRMeasurementMethod": "ts38215_received_reference_disturbance",
                "SSBReceivedPower_dB": -3.0,
                "MeasuredTrialSINR_dB": 9.25,
            }
        ],
        "ul": [{"UEID": 1, "Slot": 9, "PUSCHPowerHeadroom_dB": 13.5}],
        "dl": [{"UEID": 1, "Slot": 8, "CSI_RSRP_dB": 99.0}],
        "cell_paths": [
            {
                "UEID": 1,
                "Slot": 8,
                "CandidateRank": 1,
                "CellID": 3,
                "Pathloss_dB": 104.0,
                "RSRP_dBm": -82.5,
                "BeamIndex": 2,
                "PathlossModelSource": "nrPathLoss",
                "PathlossComplianceStatus": "available",
            },
            {
                "UEID": 1,
                "Slot": 8,
                "CandidateRank": 2,
                "CellID": 4,
                "Pathloss_dB": 0,
                "RSRP_dBm": -110.0,
                "PathlossModelSource": "pathloss_disabled",
                "PathlossComplianceStatus": "unsupported_pathloss_configuration",
            },
        ],
    }
    rows = dashboard.build_realtime_ue_status({}, {}, sources)
    assert len(rows) == 1
    ue = rows[0]
    assert ue["serving_rsrp_dbm"] == -82.5
    assert ue["ss_rsrp_dbm"] == -91.0
    assert ue["ss_sinr_db"] == 7.5
    assert ue["configured_snr_db"] == 3.0
    assert ue["ss_sinr_delta_db"] == 4.5
    assert ue["ss_channel_gain_db"] == 4.25
    assert ue["ss_sinr_method"] == "ts38215_received_reference_disturbance"
    assert ue["pbch_dmrs_sinr_db"] == 9.25
    assert ue["csi_rsrp_dbm"] == -86.25
    assert ue["csi_rsrp_relative_db"] == 23.0
    assert ue["csi_power_unit"] == "dB_re_unit_occupied_RE_Es"
    assert ue["csi_power_reference_plane"] == "normalized_fixed_snr_occupied_re"
    assert ue["csi_sinr_db"] == 11.75
    assert ue["ue_phr_db"] == 13.5
    assert ue["pathloss_paths"][0]["pathloss_db"] == 104.0
    assert ue["pathloss_paths"][1]["pathloss_db"] is None
    assert ue["pathloss_paths"][1]["raw_pathloss_db"] == 0
    assert ue["pathloss_paths"][1]["beam_index"] is None
    assert ue["pathloss_paths"][1]["beam_gain_db"] is None


def test_post_equalization_csi_row_is_not_relabelled_as_csi_sinr() -> None:
    sources = {
        "csi": [
            {
                "UEIndex": 1,
                "Slot": 1,
                "SINR_dB": 18.0,
                "SINRMeasurementDomain": "pdsch_post_equalization_data_re",
            }
        ]
    }
    ue = dashboard.build_realtime_ue_status({}, {}, sources)[0]
    assert ue["csi_sinr_db"] is None


def test_runtime_log_component_annotation_preserves_original_message() -> None:
    source = [{"level_str": "INFO", "message_text": "PDCCH DCI decoded for UE 2"}]
    rows = dashboard.annotate_realtime_logs(source)
    assert rows[0]["component"] == "pdcch"
    assert rows[0]["message_text"] == source[0]["message_text"]
    assert "component" not in source[0]


def test_ra_stage_preview_exposes_zero_and_one_based_slot_coordinates() -> None:
    rows = dashboard.summarize_procedure_preview_rows(
        "ra_stage_waveforms",
        [{"UEId": 1, "StageName": "Msg1", "StageSlot": 9}],
    )
    assert rows == [{
        "UE": 1,
        "Stage": "Msg1",
        "Absolute slot (0-based)": 9,
        "Runtime slot (1-based)": 10,
    }]


def test_large_header_only_csv_does_not_advance_live_stage() -> None:
    artifacts = [artifact("air_interface/csv/ul_pusch_trials.csv", artifact_id=91)]
    artifacts[0]["byte_size"] = 50_000
    original = dashboard.load_small_csv_rows
    try:
        dashboard.load_small_csv_rows = lambda *_args, **_kwargs: []
        stage = dashboard.infer_effective_live_stage({"Stage": "pre_raw_sweep"}, artifacts)
        assert stage["Stage"] == "control_access_pending"
        assert stage["SourceStage"] == "pre_raw_sweep"
        assert stage["ULTrialsReady"] == 0

        dashboard.load_small_csv_rows = lambda *_args, **_kwargs: [{"Slot": 1}]
        stage = dashboard.infer_effective_live_stage({"Stage": "pre_raw_sweep"}, artifacts)
        assert stage["Stage"] == "ul_raw_trials_streaming"
        assert stage["ULTrialsReady"] == 1
    finally:
        dashboard.load_small_csv_rows = original


def test_publisher_raw_streaming_label_requires_parsed_trial_rows() -> None:
    artifacts = [artifact("air_interface/csv/ul_pusch_trials.csv", artifact_id=92)]
    artifacts[0]["byte_size"] = 50_000
    original = dashboard.load_small_csv_rows
    try:
        dashboard.load_small_csv_rows = lambda *_args, **_kwargs: []
        stage = dashboard.infer_effective_live_stage(
            {"Stage": "dl_ul_raw_trials_streaming", "DLTrialRows": 0, "ULTrialRows": 0},
            artifacts,
        )
        assert stage["Stage"] == "control_access_pending"
        assert stage["SourceStage"] == "dl_ul_raw_trials_streaming"
        assert stage["DLTrialsReady"] == 0
        assert stage["ULTrialsReady"] == 0
    finally:
        dashboard.load_small_csv_rows = original


def test_artifact_content_version_changes_for_stable_id_in_place_update(tmp_path: Path) -> None:
    run_folder = tmp_path / "run"
    live_path = run_folder / "reports" / "csv" / "live_control_gating_state.csv"
    live_path.parent.mkdir(parents=True)
    live_path.write_text("Slot,State\n1,old\n", encoding="utf-8")
    row = artifact("reports/csv/live_control_gating_state.csv", artifact_id=77)
    row["filesystem_path"] = str(live_path)
    row["byte_size"] = live_path.stat().st_size
    run = {"run_folder": str(run_folder)}
    first = dashboard.artifact_content_version([row], run)

    live_path.write_text("Slot,State\n2,new\n", encoding="utf-8")
    second = dashboard.artifact_content_version([row], run)
    assert first != second


def test_data_preview_retains_crc_and_measured_beam_fields() -> None:
    rows = dashboard.summarize_data_trial_preview_rows(
        "dl_trials",
        [
            {
                "Slot": 7,
                "UEID": 2,
                "Direction": "DL",
                "MCSIndex": 11,
                "Modulation": "64QAM",
                "MeasuredTrialSINR_dB": 13.25,
                "CRCPass": 1,
                "SchedulerCQIRawCQI": 7,
                "AppliedLinkAdaptationMCS": 11,
                "SelectedBeamIndex": 3,
                "PMI": 2,
                "AppliedPrecoderPMI": 2,
                "RequestedPrecoderPMI": 3,
                "RequestedPrecoderSource": "delayed_csi_report_pmi",
                "RequestedVsAppliedPrecoderPMIMatchStatus": "requested_equals_runtime_applied_matrix_after_csirs_basis_composition",
                "AppliedPrecoderPMITruthClassification": "applied_runtime_value",
                "AppliedBeamIndexSet": "3",
                "SelectedBeamGain_dB": 8.75,
                "BestBeamIndex": 4,
                "BestBeamGain_dB": 9.25,
                "BeamGainGap_dB": 0.5,
            }
        ],
    )
    assert rows == [
        {
            "Direction": "DL",
            "Slot": 7,
            "UE": 2,
            "MCS": 11,
            "Modulation": "64QAM",
            "Measured SINR dB": 13.25,
            "CRC pass": 1,
            "Scheduler CQI used": 7,
            "LA MCS": 11,
            "Beam": 3,
            "PMI": 2,
            "Requested CSI PMI": 3,
            "PMI request source": "delayed_csi_report_pmi",
            "Applied basis PMI": 2,
            "Applied beam": "3",
            "Precoder match": "requested_equals_runtime_applied_matrix_after_csirs_basis_composition",
            "Applied PMI status": "applied_runtime_value",
            "Applied beam gain dB": 8.75,
            "Best measured beam": 4,
            "Best beam gain dB": 9.25,
            "Beam gap dB": 0.5,
        }
    ]


def test_component_view_detection_does_not_hide_canonical_roots() -> None:
    assert not dashboard.is_component_view_artifact_path(
        "air_interface/csv/dl_pdsch_trials.csv"
    )
    assert not dashboard.is_component_view_artifact_path(
        "system/image/system_topology.png"
    )
    assert dashboard.is_component_view_artifact_path(
        "pdsch/image/dl_bler_vs_snr.png"
    )
    assert dashboard.is_component_view_artifact_path(
        "components/pdsch/png/pdsch_bler_vs_snr.png"
    )
    assert dashboard.is_contract_component_artifact_path(
        "components/pdsch/png/pdsch_bler_vs_snr.png"
    )
    assert dashboard.is_contract_component_artifact_path(
        "components/frame_grid/qualification/png/resource_grid.png"
    )
    assert dashboard.is_runtime_contract_component_artifact_path(
        "components/pdsch/png/pdsch_bler_vs_snr.png"
    )
    assert not dashboard.is_runtime_contract_component_artifact_path(
        "components/frame_grid/qualification/png/resource_grid.png"
    )
    assert dashboard.is_component_qualification_artifact_path(
        "components/frame_grid/qualification/png/resource_grid.png"
    )
    for phase_component in ("mac", "protocol", "rsla", "integration"):
        assert dashboard.is_component_qualification_artifact_path(
            f"components/{phase_component}/qualification/csv/evidence.csv"
        )
    assert not dashboard.is_contract_component_artifact_path(
        "pdsch/image/dl_bler_vs_snr.png"
    )


def test_manifest_hides_mirrors_from_primary_gallery_only() -> None:
    rows = [
        artifact("air_interface/csv/dl_pdsch_trials.csv", artifact_id=1),
        artifact("pdsch/csv/dl_pdsch_trials.csv", artifact_id=2),
    ]
    assert dashboard.prefer_canonical_artifacts_over_component_views(rows, None) == rows
    filtered = dashboard.prefer_canonical_artifacts_over_component_views(
        rows, artifact("reports/csv/component_artifact_publication_manifest.csv", artifact_id=3)
    )
    assert [row["artifact_id"] for row in filtered] == [1]


def test_completed_contract_tree_replaces_legacy_results_authority() -> None:
    rows = [
        artifact("air_interface/csv/dl_pdsch_trials.csv", artifact_id=1),
        artifact("reports/image/dl_bler_old.png", "image/png", 2),
        artifact("components/pdsch/csv/pdsch_bler_curve.csv", artifact_id=3),
        artifact(
            "components/pdsch/png/pdsch_bler_vs_snr.png", "image/png", 4
        ),
        artifact(
            "artifact_generation/canonical_component_manifest.csv", artifact_id=5
        ),
    ]
    selected, authority = dashboard.select_primary_result_artifacts(rows)
    selected_paths = {row["logical_path"] for row in selected}
    assert authority["status"] == "contract_components_authoritative"
    assert authority["evidence_scope"] == "in_path_runtime"
    assert authority["canonical_count"] == 2
    assert authority["legacy_diagnostic_count"] == 2
    assert "components/pdsch/csv/pdsch_bler_curve.csv" in selected_paths
    assert "components/pdsch/png/pdsch_bler_vs_snr.png" in selected_paths
    assert "air_interface/csv/dl_pdsch_trials.csv" not in selected_paths
    assert "reports/image/dl_bler_old.png" not in selected_paths


def test_generation_audit_without_atomic_component_payload_is_not_authority() -> None:
    rows = [
        artifact("reports/csv/scenario_summary.csv", artifact_id=1),
        artifact(
            "artifact_generation/artifact_generation_results.csv", artifact_id=2
        ),
        artifact("components/pdsch/csv/partial.csv", artifact_id=3),
    ]
    selected, authority = dashboard.select_primary_result_artifacts(rows)
    assert selected == []
    assert authority["status"] == "no_atomic_result_authority"
    assert authority["evidence_scope"] == "unaccepted_diagnostics"
    assert authority["canonical_count"] == 0
    assert authority["legacy_diagnostic_count"] == len(rows)


def test_atomic_qualification_manifest_selects_only_scoped_qualification() -> None:
    rows = [
        artifact("reports/csv/scenario_summary.csv", artifact_id=1),
        artifact(
            "components/frame_grid/qualification/csv/allocation_legality.csv",
            artifact_id=2,
        ),
        artifact(
            "components/frame_grid/qualification/png/resource_grid.png",
            "image/png",
            3,
        ),
        artifact(
            "artifact_generation/component_qualification_manifest.csv",
            artifact_id=4,
        ),
        artifact(
            "artifact_generation/component_qualification_summary.csv",
            artifact_id=5,
        ),
    ]
    selected, authority = dashboard.select_primary_result_artifacts(rows)
    selected_paths = {row["logical_path"] for row in selected}
    assert authority["status"] == "component_qualification_evidence_only"
    assert authority["evidence_scope"] == "component_validation_campaign"
    assert authority["canonical_count"] == 2
    assert "reports/csv/scenario_summary.csv" not in selected_paths
    assert len(selected) == 4
