# Complete Reports Output Spec

This document is additive-only. It does not declare that historical tables, CSVs, artifacts, browser pages, or plots should be deleted.

Runtime truth lives under `/reports`; derived study views live under `/analytics`. Missing outputs stay unavailable until a canonical DB row or artifact exists.

All major fact tables require the base context columns and value semantics from `apps/lls_output_contract.py`.

## Value Semantics

- value_role values: configured, resolved, applied, measured, estimated, derived, aggregated, placeholder, unavailable, fallback_substituted
- value_status values: OK, MISSING, NOT_AVAILABLE, PLACEHOLDER, FALLBACK_USED, PARTIAL, CRASHED, UNSUPPORTED, REVIEW_REQUIRED
- configured/resolved/applied/measured/derived values must keep explicit `value_source` and `value_definition` lineage.
- charts are never generated from smoke rows or placeholders by default.

## Sections


### Run / Trial / Scenario Overview

- Route: `/reports/run-trial-scenario-overview`
- Table `live_run_overview`: route `/reports/run-trial-scenario-overview/tables/live_run_overview`, view `live_run_overview_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_trial_overview`: route `/reports/run-trial-scenario-overview/tables/live_trial_overview`, view `live_trial_overview_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_scenario_overview`: route `/reports/run-trial-scenario-overview/tables/live_scenario_overview`, view `live_scenario_overview_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_case_status`: route `/reports/run-trial-scenario-overview/tables/live_case_status`, view `live_case_status_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_required_vs_optional_case_status`: route `/reports/run-trial-scenario-overview/tables/live_required_vs_optional_case_status`, view `live_required_vs_optional_case_status_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_truth_policy_status`: route `/reports/run-trial-scenario-overview/tables/live_truth_policy_status`, view `live_truth_policy_status_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Scenario / Geometry / Topology / Layout

- Route: `/reports/scenario-geometry-topology-layout`
- Table `live_site_table`: route `/reports/scenario-geometry-topology-layout/tables/live_site_table`, view `live_site_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_sector_table`: route `/reports/scenario-geometry-topology-layout/tables/live_sector_table`, view `live_sector_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_trp_table`: route `/reports/scenario-geometry-topology-layout/tables/live_trp_table`, view `live_trp_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_cell_table`: route `/reports/scenario-geometry-topology-layout/tables/live_cell_table`, view `live_cell_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_ue_table`: route `/reports/scenario-geometry-topology-layout/tables/live_ue_table`, view `live_ue_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_link_table`: route `/reports/scenario-geometry-topology-layout/tables/live_link_table`, view `live_link_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_path_geometry_table`: route `/reports/scenario-geometry-topology-layout/tables/live_path_geometry_table`, view `live_path_geometry_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_candidate_cell_table`: route `/reports/scenario-geometry-topology-layout/tables/live_candidate_cell_table`, view `live_candidate_cell_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Mobility / Access / Cell Selection / Reselection / Handover

- Route: `/reports/mobility-access-cell-selection-reselection-handover`
- Table `live_mobility_state`: route `/reports/mobility-access-cell-selection-reselection-handover/tables/live_mobility_state`, view `live_mobility_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_measurement_filter_state`: route `/reports/mobility-access-cell-selection-reselection-handover/tables/live_measurement_filter_state`, view `live_measurement_filter_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_selection_state`: route `/reports/mobility-access-cell-selection-reselection-handover/tables/live_selection_state`, view `live_selection_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_reselection_state`: route `/reports/mobility-access-cell-selection-reselection-handover/tables/live_reselection_state`, view `live_reselection_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_handover_state`: route `/reports/mobility-access-cell-selection-reselection-handover/tables/live_handover_state`, view `live_handover_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_event_trigger_table`: route `/reports/mobility-access-cell-selection-reselection-handover/tables/live_event_trigger_table`, view `live_event_trigger_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_access_state`: route `/reports/mobility-access-cell-selection-reselection-handover/tables/live_access_state`, view `live_access_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Air Interface / Frame / Slot / Symbol / Grid

- Route: `/reports/air-interface-frame-slot-symbol-grid`
- Table `live_carrier_config`: route `/reports/air-interface-frame-slot-symbol-grid/tables/live_carrier_config`, view `live_carrier_config_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_numerology_state`: route `/reports/air-interface-frame-slot-symbol-grid/tables/live_numerology_state`, view `live_numerology_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_frame_grid_state`: route `/reports/air-interface-frame-slot-symbol-grid/tables/live_frame_grid_state`, view `live_frame_grid_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_bwp_state`: route `/reports/air-interface-frame-slot-symbol-grid/tables/live_bwp_state`, view `live_bwp_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_coreset_state`: route `/reports/air-interface-frame-slot-symbol-grid/tables/live_coreset_state`, view `live_coreset_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_search_space_state`: route `/reports/air-interface-frame-slot-symbol-grid/tables/live_search_space_state`, view `live_search_space_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_ssb_occasion_state`: route `/reports/air-interface-frame-slot-symbol-grid/tables/live_ssb_occasion_state`, view `live_ssb_occasion_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_prach_occasion_state`: route `/reports/air-interface-frame-slot-symbol-grid/tables/live_prach_occasion_state`, view `live_prach_occasion_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_prb_allocation_snapshot`: route `/reports/air-interface-frame-slot-symbol-grid/tables/live_prb_allocation_snapshot`, view `live_prb_allocation_snapshot_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_re_allocation_snapshot`: route `/reports/air-interface-frame-slot-symbol-grid/tables/live_re_allocation_snapshot`, view `live_re_allocation_snapshot_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Scheduler / MAC / Queue / QoS / Power Control / UCI Flow

- Route: `/reports/scheduler-mac-queue-qos-power-control-uci-flow`
- Table `live_scheduler_cycle`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/tables/live_scheduler_cycle`, view `live_scheduler_cycle_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_dl_scheduler_grants`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/tables/live_dl_scheduler_grants`, view `live_dl_scheduler_grants_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_ul_scheduler_grants`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/tables/live_ul_scheduler_grants`, view `live_ul_scheduler_grants_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_queue_state`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/tables/live_queue_state`, view `live_queue_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_buffer_status`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/tables/live_buffer_status`, view `live_buffer_status_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_hol_delay_state`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/tables/live_hol_delay_state`, view `live_hol_delay_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_qos_state`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/tables/live_qos_state`, view `live_qos_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_mac_pdu_summary`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/tables/live_mac_pdu_summary`, view `live_mac_pdu_summary_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_power_control_state`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/tables/live_power_control_state`, view `live_power_control_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_phr_state`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/tables/live_phr_state`, view `live_phr_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_sr_state`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/tables/live_sr_state`, view `live_sr_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_bsr_state`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/tables/live_bsr_state`, view `live_bsr_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_mac_ce_state`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/tables/live_mac_ce_state`, view `live_mac_ce_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### HARQ / ACK-NACK / Retransmission

- Route: `/reports/harq-ack-nack-retransmission`
- Table `live_harq_process_table`: route `/reports/harq-ack-nack-retransmission/tables/live_harq_process_table`, view `live_harq_process_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_harq_timeline`: route `/reports/harq-ack-nack-retransmission/tables/live_harq_timeline`, view `live_harq_timeline_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_ack_nack_table`: route `/reports/harq-ack-nack-retransmission/tables/live_ack_nack_table`, view `live_ack_nack_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_soft_buffer_table`: route `/reports/harq-ack-nack-retransmission/tables/live_soft_buffer_table`, view `live_soft_buffer_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### DL Control PHY - PDCCH

- Route: `/reports/dl-control-phy-pdcch`
- Table `live_pdcch_stage_table`: route `/reports/dl-control-phy-pdcch/tables/live_pdcch_stage_table`, view `live_pdcch_stage_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_pdcch_summary`: route `/reports/dl-control-phy-pdcch/tables/live_pdcch_summary`, view `live_pdcch_summary_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_pdcch_dmrs_table`: route `/reports/dl-control-phy-pdcch/tables/live_pdcch_dmrs_table`, view `live_pdcch_dmrs_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### SSB / PBCH / PSS / SSS

- Route: `/reports/ssb-pbch-pss-sss`
- Table `live_ssb_stage_table`: route `/reports/ssb-pbch-pss-sss/tables/live_ssb_stage_table`, view `live_ssb_stage_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_pbch_summary`: route `/reports/ssb-pbch-pss-sss/tables/live_pbch_summary`, view `live_pbch_summary_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_sync_signal_state`: route `/reports/ssb-pbch-pss-sss/tables/live_sync_signal_state`, view `live_sync_signal_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### CSI-RS

- Route: `/reports/csi-rs`
- Table `live_csirs_stage_table`: route `/reports/csi-rs/tables/live_csirs_stage_table`, view `live_csirs_stage_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_csirs_resource_table`: route `/reports/csi-rs/tables/live_csirs_resource_table`, view `live_csirs_resource_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### PDSCH / DL Data Chain

- Route: `/reports/pdsch-dl-data-chain`
- Table `live_pdsch_stage_table`: route `/reports/pdsch-dl-data-chain/tables/live_pdsch_stage_table`, view `live_pdsch_stage_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_pdsch_transport_block_table`: route `/reports/pdsch-dl-data-chain/tables/live_pdsch_transport_block_table`, view `live_pdsch_transport_block_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_pdsch_code_block_table`: route `/reports/pdsch-dl-data-chain/tables/live_pdsch_code_block_table`, view `live_pdsch_code_block_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_pdsch_mapping_table`: route `/reports/pdsch-dl-data-chain/tables/live_pdsch_mapping_table`, view `live_pdsch_mapping_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_pdsch_dmrs_ptrs_table`: route `/reports/pdsch-dl-data-chain/tables/live_pdsch_dmrs_ptrs_table`, view `live_pdsch_dmrs_ptrs_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### PUSCH / UL Data Chain

- Route: `/reports/pusch-ul-data-chain`
- Table `live_pusch_stage_table`: route `/reports/pusch-ul-data-chain/tables/live_pusch_stage_table`, view `live_pusch_stage_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_pusch_rx_summary`: route `/reports/pusch-ul-data-chain/tables/live_pusch_rx_summary`, view `live_pusch_rx_summary_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_ul_dmrs_table`: route `/reports/pusch-ul-data-chain/tables/live_ul_dmrs_table`, view `live_ul_dmrs_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_llr_summary`: route `/reports/pusch-ul-data-chain/tables/live_llr_summary`, view `live_llr_summary_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_decoder_summary`: route `/reports/pusch-ul-data-chain/tables/live_decoder_summary`, view `live_decoder_summary_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### PUCCH F0 / F1 / F2 / F3 / F4

- Route: `/reports/pucch-f0-f1-f2-f3-f4`
- Table `live_pucch_summary`: route `/reports/pucch-f0-f1-f2-f3-f4/tables/live_pucch_summary`, view `live_pucch_summary_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_pucch_f0_table`: route `/reports/pucch-f0-f1-f2-f3-f4/tables/live_pucch_f0_table`, view `live_pucch_f0_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_pucch_f1_table`: route `/reports/pucch-f0-f1-f2-f3-f4/tables/live_pucch_f1_table`, view `live_pucch_f1_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_pucch_f2_table`: route `/reports/pucch-f0-f1-f2-f3-f4/tables/live_pucch_f2_table`, view `live_pucch_f2_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_pucch_f3_table`: route `/reports/pucch-f0-f1-f2-f3-f4/tables/live_pucch_f3_table`, view `live_pucch_f3_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_pucch_f4_table`: route `/reports/pucch-f0-f1-f2-f3-f4/tables/live_pucch_f4_table`, view `live_pucch_f4_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_uci_table`: route `/reports/pucch-f0-f1-f2-f3-f4/tables/live_uci_table`, view `live_uci_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### PRACH / Random Access

- Route: `/reports/prach-random-access`
- Table `live_prach_stage_table`: route `/reports/prach-random-access/tables/live_prach_stage_table`, view `live_prach_stage_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_prach_detection_table`: route `/reports/prach-random-access/tables/live_prach_detection_table`, view `live_prach_detection_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_random_access_state`: route `/reports/prach-random-access/tables/live_random_access_state`, view `live_random_access_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### SRS / UL Sounding / Massive MIMO Inputs

- Route: `/reports/srs-ul-sounding-massive-mimo-inputs`
- Table `live_srs_stage_table`: route `/reports/srs-ul-sounding-massive-mimo-inputs/tables/live_srs_stage_table`, view `live_srs_stage_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_srs_channel_estimation_table`: route `/reports/srs-ul-sounding-massive-mimo-inputs/tables/live_srs_channel_estimation_table`, view `live_srs_channel_estimation_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_csi_output_table`: route `/reports/srs-ul-sounding-massive-mimo-inputs/tables/live_csi_output_table`, view `live_csi_output_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Channel / Interference / Impairments

- Route: `/reports/channel-interference-impairments`
- Table `live_channel_realization_table`: route `/reports/channel-interference-impairments/tables/live_channel_realization_table`, view `live_channel_realization_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_interference_table`: route `/reports/channel-interference-impairments/tables/live_interference_table`, view `live_interference_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_impairment_table`: route `/reports/channel-interference-impairments/tables/live_impairment_table`, view `live_impairment_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_tracking_table`: route `/reports/channel-interference-impairments/tables/live_tracking_table`, view `live_tracking_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Measurements / CSI / Link Adaptation Inputs

- Route: `/reports/measurements-csi-link-adaptation-inputs`
- Table `live_measurement_table`: route `/reports/measurements-csi-link-adaptation-inputs/tables/live_measurement_table`, view `live_measurement_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_csi_feedback_table`: route `/reports/measurements-csi-link-adaptation-inputs/tables/live_csi_feedback_table`, view `live_csi_feedback_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_link_adaptation_input_table`: route `/reports/measurements-csi-link-adaptation-inputs/tables/live_link_adaptation_input_table`, view `live_link_adaptation_input_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Beamforming / Precoding / MIMO / Massive MIMO

- Route: `/reports/beamforming-precoding-mimo-massive-mimo`
- Table `live_beam_selection_table`: route `/reports/beamforming-precoding-mimo-massive-mimo/tables/live_beam_selection_table`, view `live_beam_selection_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_precoder_table`: route `/reports/beamforming-precoding-mimo-massive-mimo/tables/live_precoder_table`, view `live_precoder_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_combiner_table`: route `/reports/beamforming-precoding-mimo-massive-mimo/tables/live_combiner_table`, view `live_combiner_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_mimo_state_table`: route `/reports/beamforming-precoding-mimo-massive-mimo/tables/live_mimo_state_table`, view `live_mimo_state_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_user_grouping_table`: route `/reports/beamforming-precoding-mimo-massive-mimo/tables/live_user_grouping_table`, view `live_user_grouping_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### UE-Side State / UE Power / UE Control

- Route: `/reports/ue-side-state-ue-power-ue-control`
- Table `live_ue_state_table`: route `/reports/ue-side-state-ue-power-ue-control/tables/live_ue_state_table`, view `live_ue_state_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_ue_measurement_state`: route `/reports/ue-side-state-ue-power-ue-control/tables/live_ue_measurement_state`, view `live_ue_measurement_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_ue_control_state`: route `/reports/ue-side-state-ue-power-ue-control/tables/live_ue_control_state`, view `live_ue_control_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_ue_power_state`: route `/reports/ue-side-state-ue-power-ue-control/tables/live_ue_power_state`, view `live_ue_power_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_drx_state`: route `/reports/ue-side-state-ue-power-ue-control/tables/live_drx_state`, view `live_drx_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### gNB-Side State / Thread / Coordinator / PHY-MAC API

- Route: `/reports/gnb-side-state-thread-coordinator-phy-mac-api`
- Table `live_gnb_state_table`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/tables/live_gnb_state_table`, view `live_gnb_state_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_per_cell_context`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/tables/live_per_cell_context`, view `live_per_cell_context_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_per_ue_context`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/tables/live_per_ue_context`, view `live_per_ue_context_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_phy_mac_api_table`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/tables/live_phy_mac_api_table`, view `live_phy_mac_api_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_thread_orchestration_table`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/tables/live_thread_orchestration_table`, view `live_thread_orchestration_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Power / Energy / Thermal / Compute / Runtime

- Route: `/reports/power-energy-thermal-compute-runtime`
- Table `live_power_runtime_table`: route `/reports/power-energy-thermal-compute-runtime/tables/live_power_runtime_table`, view `live_power_runtime_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_rf_power_table`: route `/reports/power-energy-thermal-compute-runtime/tables/live_rf_power_table`, view `live_rf_power_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_bb_power_table`: route `/reports/power-energy-thermal-compute-runtime/tables/live_bb_power_table`, view `live_bb_power_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_energy_efficiency_table`: route `/reports/power-energy-thermal-compute-runtime/tables/live_energy_efficiency_table`, view `live_energy_efficiency_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_sleep_state_table`: route `/reports/power-energy-thermal-compute-runtime/tables/live_sleep_state_table`, view `live_sleep_state_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Persistence / Export / Consistency / Browser Health

- Route: `/reports/persistence-export-consistency-browser-health`
- Table `live_db_write_table`: route `/reports/persistence-export-consistency-browser-health/tables/live_db_write_table`, view `live_db_write_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_csv_write_table`: route `/reports/persistence-export-consistency-browser-health/tables/live_csv_write_table`, view `live_csv_write_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_artifact_write_table`: route `/reports/persistence-export-consistency-browser-health/tables/live_artifact_write_table`, view `live_artifact_write_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_browser_surface_integrity_table`: route `/reports/persistence-export-consistency-browser-health/tables/live_browser_surface_integrity_table`, view `live_browser_surface_integrity_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_consistency_check_table`: route `/reports/persistence-export-consistency-browser-health/tables/live_consistency_check_table`, view `live_consistency_check_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Generic Investigator Views

- Route: `/reports/generic-investigator-views`
- Table `reports_all_stage_exec_v`: route `/reports/generic-investigator-views/tables/reports_all_stage_exec_v`, view `reports_all_stage_exec_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `reports_all_scalars_v`: route `/reports/generic-investigator-views/tables/reports_all_scalars_v`, view `reports_all_scalars_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `reports_all_enums_v`: route `/reports/generic-investigator-views/tables/reports_all_enums_v`, view `reports_all_enums_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `reports_all_artifacts_v`: route `/reports/generic-investigator-views/tables/reports_all_artifacts_v`, view `reports_all_artifacts_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `reports_stage_lineage_v`: route `/reports/generic-investigator-views/tables/reports_stage_lineage_v`, view `reports_stage_lineage_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `reports_truth_violations_v`: route `/reports/generic-investigator-views/tables/reports_truth_violations_v`, view `reports_truth_violations_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `reports_partial_or_missing_v`: route `/reports/generic-investigator-views/tables/reports_partial_or_missing_v`, view `reports_partial_or_missing_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `reports_config_vs_measured_conflicts_v`: route `/reports/generic-investigator-views/tables/reports_config_vs_measured_conflicts_v`, view `reports_config_vs_measured_conflicts_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `reports_value_semantics_coverage_v`: route `/reports/generic-investigator-views/tables/reports_value_semantics_coverage_v`, view `reports_value_semantics_coverage_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `reports_status_rollup_explanations_v`: route `/reports/generic-investigator-views/tables/reports_status_rollup_explanations_v`, view `reports_status_rollup_explanations_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Run / Trial / Scenario Overview

- Route: `/reports/run-trial-scenario-overview`
- Chart `run health timeline`: route `/reports/run-trial-scenario-overview/charts/run-health-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `error/warning/fallback stacked time series`: route `/reports/run-trial-scenario-overview/charts/error-warning-fallback-stacked-time-series`, status `unavailable_until_source_table_has_real_rows`.
- Chart `required vs failed case bar chart`: route `/reports/run-trial-scenario-overview/charts/required-vs-failed-case-bar-chart`, status `unavailable_until_source_table_has_real_rows`.
- Chart `truth policy violations by category`: route `/reports/run-trial-scenario-overview/charts/truth-policy-violations-by-category`, status `unavailable_until_source_table_has_real_rows`.

### Scenario / Geometry / Topology / Layout

- Route: `/reports/scenario-geometry-topology-layout`
- Chart `BS/sector/UE topology scatter plot`: route `/reports/scenario-geometry-topology-layout/charts/bs-sector-ue-topology-scatter-plot`, status `unavailable_until_source_table_has_real_rows`.
- Chart `UE trajectory overlay`: route `/reports/scenario-geometry-topology-layout/charts/ue-trajectory-overlay`, status `unavailable_until_source_table_has_real_rows`.
- Chart `serving cell map`: route `/reports/scenario-geometry-topology-layout/charts/serving-cell-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `candidate cell rank heatmap`: route `/reports/scenario-geometry-topology-layout/charts/candidate-cell-rank-heatmap`, status `unavailable_until_source_table_has_real_rows`.
- Chart `distance distribution histogram`: route `/reports/scenario-geometry-topology-layout/charts/distance-distribution-histogram`, status `unavailable_until_source_table_has_real_rows`.
- Chart `azimuth/elevation rose plots`: route `/reports/scenario-geometry-topology-layout/charts/azimuth-elevation-rose-plots`, status `unavailable_until_source_table_has_real_rows`.
- Chart `path geometry summary charts`: route `/reports/scenario-geometry-topology-layout/charts/path-geometry-summary-charts`, status `unavailable_until_source_table_has_real_rows`.

### Mobility / Access / Cell Selection / Reselection / Handover

- Route: `/reports/mobility-access-cell-selection-reselection-handover`
- Chart `serving cell timeline`: route `/reports/mobility-access-cell-selection-reselection-handover/charts/serving-cell-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `selected beam timeline`: route `/reports/mobility-access-cell-selection-reselection-handover/charts/selected-beam-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `mobility event timeline`: route `/reports/mobility-access-cell-selection-reselection-handover/charts/mobility-event-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `hysteresis / TTT scatter`: route `/reports/mobility-access-cell-selection-reselection-handover/charts/hysteresis-ttt-scatter`, status `unavailable_until_source_table_has_real_rows`.
- Chart `access state transition Sankey`: route `/reports/mobility-access-cell-selection-reselection-handover/charts/access-state-transition-sankey`, status `unavailable_until_source_table_has_real_rows`.
- Chart `Doppler vs speed plot`: route `/reports/mobility-access-cell-selection-reselection-handover/charts/doppler-vs-speed-plot`, status `unavailable_until_source_table_has_real_rows`.
- Chart `selection/reselection trigger histogram`: route `/reports/mobility-access-cell-selection-reselection-handover/charts/selection-reselection-trigger-histogram`, status `unavailable_until_source_table_has_real_rows`.

### Air Interface / Frame / Slot / Symbol / Grid

- Route: `/reports/air-interface-frame-slot-symbol-grid`
- Chart `frame/slot/symbol occupancy timeline`: route `/reports/air-interface-frame-slot-symbol-grid/charts/frame-slot-symbol-occupancy-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PRB heatmap`: route `/reports/air-interface-frame-slot-symbol-grid/charts/prb-heatmap`, status `unavailable_until_source_table_has_real_rows`.
- Chart `RE occupancy heatmap`: route `/reports/air-interface-frame-slot-symbol-grid/charts/re-occupancy-heatmap`, status `unavailable_until_source_table_has_real_rows`.
- Chart `DL/UL/guard slot pattern chart`: route `/reports/air-interface-frame-slot-symbol-grid/charts/dl-ul-guard-slot-pattern-chart`, status `unavailable_until_source_table_has_real_rows`.
- Chart `SSB occasion timeline`: route `/reports/air-interface-frame-slot-symbol-grid/charts/ssb-occasion-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PRACH occasion timeline`: route `/reports/air-interface-frame-slot-symbol-grid/charts/prach-occasion-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CORESET/search-space occupancy chart`: route `/reports/air-interface-frame-slot-symbol-grid/charts/coreset-search-space-occupancy-chart`, status `unavailable_until_source_table_has_real_rows`.

### Scheduler / MAC / Queue / QoS / Power Control / UCI Flow

- Route: `/reports/scheduler-mac-queue-qos-power-control-uci-flow`
- Chart `scheduled PRBs per UE over time`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/charts/scheduled-prbs-per-ue-over-time`, status `unavailable_until_source_table_has_real_rows`.
- Chart `MCS over time`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/charts/mcs-over-time`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CQI vs selected MCS`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/charts/cqi-vs-selected-mcs`, status `unavailable_until_source_table_has_real_rows`.
- Chart `queue depth over time`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/charts/queue-depth-over-time`, status `unavailable_until_source_table_has_real_rows`.
- Chart `HOL delay over time`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/charts/hol-delay-over-time`, status `unavailable_until_source_table_has_real_rows`.
- Chart `scheduler fairness over time`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/charts/scheduler-fairness-over-time`, status `unavailable_until_source_table_has_real_rows`.
- Chart `SR/BSR event timeline`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/charts/sr-bsr-event-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `power control command timeline`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/charts/power-control-command-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PHR distribution`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/charts/phr-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `grant reason distribution`: route `/reports/scheduler-mac-queue-qos-power-control-uci-flow/charts/grant-reason-distribution`, status `unavailable_until_source_table_has_real_rows`.

### HARQ / ACK-NACK / Retransmission

- Route: `/reports/harq-ack-nack-retransmission`
- Chart `HARQ process timeline`: route `/reports/harq-ack-nack-retransmission/charts/harq-process-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `RV usage distribution`: route `/reports/harq-ack-nack-retransmission/charts/rv-usage-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `retransmission count histogram`: route `/reports/harq-ack-nack-retransmission/charts/retransmission-count-histogram`, status `unavailable_until_source_table_has_real_rows`.
- Chart `ACK/NACK timeline`: route `/reports/harq-ack-nack-retransmission/charts/ack-nack-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `residual BLER by HARQ process`: route `/reports/harq-ack-nack-retransmission/charts/residual-bler-by-harq-process`, status `unavailable_until_source_table_has_real_rows`.
- Chart `combining gain histogram`: route `/reports/harq-ack-nack-retransmission/charts/combining-gain-histogram`, status `unavailable_until_source_table_has_real_rows`.

### DL Control PHY - PDCCH

- Route: `/reports/dl-control-phy-pdcch`
- Chart `PDCCH stage latency waterfall`: route `/reports/dl-control-phy-pdcch/charts/pdcch-stage-latency-waterfall`, status `unavailable_until_source_table_has_real_rows`.
- Chart `aggregation level distribution`: route `/reports/dl-control-phy-pdcch/charts/aggregation-level-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CCE usage heatmap`: route `/reports/dl-control-phy-pdcch/charts/cce-usage-heatmap`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PDCCH DMRS occupancy`: route `/reports/dl-control-phy-pdcch/charts/pdcch-dmrs-occupancy`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PDCCH decode success/failure trend if applicable`: route `/reports/dl-control-phy-pdcch/charts/pdcch-decode-success-failure-trend-if-applicable`, status `unavailable_until_source_table_has_real_rows`.

### SSB / PBCH / PSS / SSS

- Route: `/reports/ssb-pbch-pss-sss`
- Chart `SSB index timeline`: route `/reports/ssb-pbch-pss-sss/charts/ssb-index-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PBCH stage latency`: route `/reports/ssb-pbch-pss-sss/charts/pbch-stage-latency`, status `unavailable_until_source_table_has_real_rows`.
- Chart `SSB/PBCH occupancy map`: route `/reports/ssb-pbch-pss-sss/charts/ssb-pbch-occupancy-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `sync success/failure timeline if available`: route `/reports/ssb-pbch-pss-sss/charts/sync-success-failure-timeline-if-available`, status `unavailable_until_source_table_has_real_rows`.

### CSI-RS

- Route: `/reports/csi-rs`
- Chart `CSI-RS resource occupancy`: route `/reports/csi-rs/charts/csi-rs-resource-occupancy`, status `unavailable_until_source_table_has_real_rows`.
- Chart `port usage chart`: route `/reports/csi-rs/charts/port-usage-chart`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CSI-RS latency trend`: route `/reports/csi-rs/charts/csi-rs-latency-trend`, status `unavailable_until_source_table_has_real_rows`.

### PDSCH / DL Data Chain

- Route: `/reports/pdsch-dl-data-chain`
- Chart `TB size over time`: route `/reports/pdsch-dl-data-chain/charts/tb-size-over-time`, status `unavailable_until_source_table_has_real_rows`.
- Chart `MCS/code-rate timeline`: route `/reports/pdsch-dl-data-chain/charts/mcs-code-rate-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `code-block count histogram`: route `/reports/pdsch-dl-data-chain/charts/code-block-count-histogram`, status `unavailable_until_source_table_has_real_rows`.
- Chart `LDPC stage latency waterfall`: route `/reports/pdsch-dl-data-chain/charts/ldpc-stage-latency-waterfall`, status `unavailable_until_source_table_has_real_rows`.
- Chart `DMRS/PTRS occupancy plot`: route `/reports/pdsch-dl-data-chain/charts/dmrs-ptrs-occupancy-plot`, status `unavailable_until_source_table_has_real_rows`.
- Chart `precoder / beam selection timeline`: route `/reports/pdsch-dl-data-chain/charts/precoder-beam-selection-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `DL resource-grid heatmap`: route `/reports/pdsch-dl-data-chain/charts/dl-resource-grid-heatmap`, status `unavailable_until_source_table_has_real_rows`.

### PUSCH / UL Data Chain

- Route: `/reports/pusch-ul-data-chain`
- Chart `channel estimation latency`: route `/reports/pusch-ul-data-chain/charts/channel-estimation-latency`, status `unavailable_until_source_table_has_real_rows`.
- Chart `equalizer latency`: route `/reports/pusch-ul-data-chain/charts/equalizer-latency`, status `unavailable_until_source_table_has_real_rows`.
- Chart `decoder iteration histogram`: route `/reports/pusch-ul-data-chain/charts/decoder-iteration-histogram`, status `unavailable_until_source_table_has_real_rows`.
- Chart `TA estimate timeline`: route `/reports/pusch-ul-data-chain/charts/ta-estimate-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `LLR statistics over time`: route `/reports/pusch-ul-data-chain/charts/llr-statistics-over-time`, status `unavailable_until_source_table_has_real_rows`.
- Chart `UL resource-grid / equalized symbol summaries`: route `/reports/pusch-ul-data-chain/charts/ul-resource-grid-equalized-symbol-summaries`, status `unavailable_until_source_table_has_real_rows`.

### PUCCH F0 / F1 / F2 / F3 / F4

- Route: `/reports/pucch-f0-f1-f2-f3-f4`
- Chart `requested vs resolved format confusion matrix`: route `/reports/pucch-f0-f1-f2-f3-f4/charts/requested-vs-resolved-format-confusion-matrix`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PUCCH decode success/failure trend`: route `/reports/pucch-f0-f1-f2-f3-f4/charts/pucch-decode-success-failure-trend`, status `unavailable_until_source_table_has_real_rows`.
- Chart `ACK/NACK match chart`: route `/reports/pucch-f0-f1-f2-f3-f4/charts/ack-nack-match-chart`, status `unavailable_until_source_table_has_real_rows`.
- Chart `DTX detection chart`: route `/reports/pucch-f0-f1-f2-f3-f4/charts/dtx-detection-chart`, status `unavailable_until_source_table_has_real_rows`.
- Chart `per-format latency histograms`: route `/reports/pucch-f0-f1-f2-f3-f4/charts/per-format-latency-histograms`, status `unavailable_until_source_table_has_real_rows`.
- Chart `crash/error timeline`: route `/reports/pucch-f0-f1-f2-f3-f4/charts/crash-error-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `UCI bit count distribution`: route `/reports/pucch-f0-f1-f2-f3-f4/charts/uci-bit-count-distribution`, status `unavailable_until_source_table_has_real_rows`.

### PRACH / Random Access

- Route: `/reports/prach-random-access`
- Chart `PRACH peak search timeline`: route `/reports/prach-random-access/charts/prach-peak-search-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `noise floor trend`: route `/reports/prach-random-access/charts/noise-floor-trend`, status `unavailable_until_source_table_has_real_rows`.
- Chart `peak value histogram`: route `/reports/prach-random-access/charts/peak-value-histogram`, status `unavailable_until_source_table_has_real_rows`.
- Chart `preamble usage chart`: route `/reports/prach-random-access/charts/preamble-usage-chart`, status `unavailable_until_source_table_has_real_rows`.
- Chart `TA estimate trend`: route `/reports/prach-random-access/charts/ta-estimate-trend`, status `unavailable_until_source_table_has_real_rows`.
- Chart `access attempt/success timeline`: route `/reports/prach-random-access/charts/access-attempt-success-timeline`, status `unavailable_until_source_table_has_real_rows`.

### SRS / UL Sounding / Massive MIMO Inputs

- Route: `/reports/srs-ul-sounding-massive-mimo-inputs`
- Chart `SRS validity timeline`: route `/reports/srs-ul-sounding-massive-mimo-inputs/charts/srs-validity-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `channel estimate quality trend`: route `/reports/srs-ul-sounding-massive-mimo-inputs/charts/channel-estimate-quality-trend`, status `unavailable_until_source_table_has_real_rows`.
- Chart `SRS consumption by scheduler/beam module`: route `/reports/srs-ul-sounding-massive-mimo-inputs/charts/srs-consumption-by-scheduler-beam-module`, status `unavailable_until_source_table_has_real_rows`.

### Channel / Interference / Impairments

- Route: `/reports/channel-interference-impairments`
- Chart `channel quality timeline`: route `/reports/channel-interference-impairments/charts/channel-quality-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CFO true vs estimated vs residual`: route `/reports/channel-interference-impairments/charts/cfo-true-vs-estimated-vs-residual`, status `unavailable_until_source_table_has_real_rows`.
- Chart `timing offset true vs estimated vs residual`: route `/reports/channel-interference-impairments/charts/timing-offset-true-vs-estimated-vs-residual`, status `unavailable_until_source_table_has_real_rows`.
- Chart `pathloss/shadowing distributions`: route `/reports/channel-interference-impairments/charts/pathloss-shadowing-distributions`, status `unavailable_until_source_table_has_real_rows`.
- Chart `interference power timeline`: route `/reports/channel-interference-impairments/charts/interference-power-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `impairment contribution bar chart`: route `/reports/channel-interference-impairments/charts/impairment-contribution-bar-chart`, status `unavailable_until_source_table_has_real_rows`.
- Chart `channel heatmap artifact links`: route `/reports/channel-interference-impairments/charts/channel-heatmap-artifact-links`, status `unavailable_until_source_table_has_real_rows`.

### Measurements / CSI / Link Adaptation Inputs

- Route: `/reports/measurements-csi-link-adaptation-inputs`
- Chart `configured vs applied vs measured SNR/SINR comparison`: route `/reports/measurements-csi-link-adaptation-inputs/charts/configured-vs-applied-vs-measured-snr-sinr-comparison`, status `unavailable_until_source_table_has_real_rows`.
- Chart `RSRP/CSI-RSRP timeline`: route `/reports/measurements-csi-link-adaptation-inputs/charts/rsrp-csi-rsrp-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CQI / PMI / RI / CRI timeline`: route `/reports/measurements-csi-link-adaptation-inputs/charts/cqi-pmi-ri-cri-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `measurement source coverage chart`: route `/reports/measurements-csi-link-adaptation-inputs/charts/measurement-source-coverage-chart`, status `unavailable_until_source_table_has_real_rows`.
- Chart `config-vs-measured conflict dashboard`: route `/reports/measurements-csi-link-adaptation-inputs/charts/config-vs-measured-conflict-dashboard`, status `unavailable_until_source_table_has_real_rows`.

### Beamforming / Precoding / MIMO / Massive MIMO

- Route: `/reports/beamforming-precoding-mimo-massive-mimo`
- Chart `selected vs best beam timeline`: route `/reports/beamforming-precoding-mimo-massive-mimo/charts/selected-vs-best-beam-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `beam gain gap histogram`: route `/reports/beamforming-precoding-mimo-massive-mimo/charts/beam-gain-gap-histogram`, status `unavailable_until_source_table_has_real_rows`.
- Chart `beam hit rate timeline`: route `/reports/beamforming-precoding-mimo-massive-mimo/charts/beam-hit-rate-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `rank distribution`: route `/reports/beamforming-precoding-mimo-massive-mimo/charts/rank-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `condition number distribution`: route `/reports/beamforming-precoding-mimo-massive-mimo/charts/condition-number-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `MU grouping summary`: route `/reports/beamforming-precoding-mimo-massive-mimo/charts/mu-grouping-summary`, status `unavailable_until_source_table_has_real_rows`.
- Chart `precoder mode distribution`: route `/reports/beamforming-precoding-mimo-massive-mimo/charts/precoder-mode-distribution`, status `unavailable_until_source_table_has_real_rows`.

### UE-Side State / UE Power / UE Control

- Route: `/reports/ue-side-state-ue-power-ue-control`
- Chart `UE Tx power timeline`: route `/reports/ue-side-state-ue-power-ue-control/charts/ue-tx-power-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `UE power headroom timeline`: route `/reports/ue-side-state-ue-power-ue-control/charts/ue-power-headroom-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `UE control/report timeline`: route `/reports/ue-side-state-ue-power-ue-control/charts/ue-control-report-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `DRX state timeline`: route `/reports/ue-side-state-ue-power-ue-control/charts/drx-state-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `UE energy proxy timeline`: route `/reports/ue-side-state-ue-power-ue-control/charts/ue-energy-proxy-timeline`, status `unavailable_until_source_table_has_real_rows`.

### gNB-Side State / Thread / Coordinator / PHY-MAC API

- Route: `/reports/gnb-side-state-thread-coordinator-phy-mac-api`
- Chart `per-cell context health timeline`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/charts/per-cell-context-health-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `API message rate`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/charts/api-message-rate`, status `unavailable_until_source_table_has_real_rows`.
- Chart `orchestration latency chart`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/charts/orchestration-latency-chart`, status `unavailable_until_source_table_has_real_rows`.
- Chart `per-worker workload chart`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/charts/per-worker-workload-chart`, status `unavailable_until_source_table_has_real_rows`.

### Power / Energy / Thermal / Compute / Runtime

- Route: `/reports/power-energy-thermal-compute-runtime`
- Chart `TX power timeline per cell`: route `/reports/power-energy-thermal-compute-runtime/charts/tx-power-timeline-per-cell`, status `unavailable_until_source_table_has_real_rows`.
- Chart `TX power timeline per UE`: route `/reports/power-energy-thermal-compute-runtime/charts/tx-power-timeline-per-ue`, status `unavailable_until_source_table_has_real_rows`.
- Chart `power vs throughput`: route `/reports/power-energy-thermal-compute-runtime/charts/power-vs-throughput`, status `unavailable_until_source_table_has_real_rows`.
- Chart `power vs BLER`: route `/reports/power-energy-thermal-compute-runtime/charts/power-vs-bler`, status `unavailable_until_source_table_has_real_rows`.
- Chart `energy per bit over time`: route `/reports/power-energy-thermal-compute-runtime/charts/energy-per-bit-over-time`, status `unavailable_until_source_table_has_real_rows`.
- Chart `joules/GB over time`: route `/reports/power-energy-thermal-compute-runtime/charts/joules-gb-over-time`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CPU cycles and memory usage time series`: route `/reports/power-energy-thermal-compute-runtime/charts/cpu-cycles-and-memory-usage-time-series`, status `unavailable_until_source_table_has_real_rows`.
- Chart `latency breakdown stacked chart`: route `/reports/power-energy-thermal-compute-runtime/charts/latency-breakdown-stacked-chart`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PAPR distribution`: route `/reports/power-energy-thermal-compute-runtime/charts/papr-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `sleep-state timeline`: route `/reports/power-energy-thermal-compute-runtime/charts/sleep-state-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `efficiency scatter plots`: route `/reports/power-energy-thermal-compute-runtime/charts/efficiency-scatter-plots`, status `unavailable_until_source_table_has_real_rows`.

### Persistence / Export / Consistency / Browser Health

- Route: `/reports/persistence-export-consistency-browser-health`
- Chart `DB write latency over time`: route `/reports/persistence-export-consistency-browser-health/charts/db-write-latency-over-time`, status `unavailable_until_source_table_has_real_rows`.
- Chart `export lag over time`: route `/reports/persistence-export-consistency-browser-health/charts/export-lag-over-time`, status `unavailable_until_source_table_has_real_rows`.
- Chart `duplicate write count trend`: route `/reports/persistence-export-consistency-browser-health/charts/duplicate-write-count-trend`, status `unavailable_until_source_table_has_real_rows`.
- Chart `consistency failure trend`: route `/reports/persistence-export-consistency-browser-health/charts/consistency-failure-trend`, status `unavailable_until_source_table_has_real_rows`.
- Chart `artifact creation rate`: route `/reports/persistence-export-consistency-browser-health/charts/artifact-creation-rate`, status `unavailable_until_source_table_has_real_rows`.

### Generic Investigator Views

- Route: `/reports/generic-investigator-views`
- Chart `investigator stage lineage graph`: route `/reports/generic-investigator-views/charts/investigator-stage-lineage-graph`, status `unavailable_until_source_table_has_real_rows`.
- Chart `truth violation rollup`: route `/reports/generic-investigator-views/charts/truth-violation-rollup`, status `unavailable_until_source_table_has_real_rows`.
- Chart `partial or missing data dashboard`: route `/reports/generic-investigator-views/charts/partial-or-missing-data-dashboard`, status `unavailable_until_source_table_has_real_rows`.
- Chart `config vs measured conflict dashboard`: route `/reports/generic-investigator-views/charts/config-vs-measured-conflict-dashboard`, status `unavailable_until_source_table_has_real_rows`.
- Chart `value semantics coverage chart`: route `/reports/generic-investigator-views/charts/value-semantics-coverage-chart`, status `unavailable_until_source_table_has_real_rows`.
