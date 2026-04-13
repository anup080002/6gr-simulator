# Scheduler / MAC / PHY Output Spec

This document is additive-only. It does not declare that historical tables, CSVs, artifacts, browser pages, or plots should be deleted.

Runtime truth lives under `/reports`; derived study views live under `/analytics`. Missing outputs stay unavailable until a canonical DB row or artifact exists.

All major fact tables require the base context columns and value semantics from `apps/lls_output_contract.py`.

## Value Semantics

- value_role values: configured, resolved, applied, measured, estimated, derived, aggregated, placeholder, unavailable, fallback_substituted
- value_status values: OK, MISSING, NOT_AVAILABLE, PLACEHOLDER, FALLBACK_USED, PARTIAL, CRASHED, UNSUPPORTED, REVIEW_REQUIRED
- configured/resolved/applied/measured/derived values must keep explicit `value_source` and `value_definition` lineage.
- charts are never generated from smoke rows or placeholders by default.

## Sections


### Air Interface / Frame / Slot / Symbol / Grid

- Route: `/reports/air-interface-frame-slot-symbol-grid`
- Table `live_prach_occasion_state`: route `/reports/air-interface-frame-slot-symbol-grid/tables/live_prach_occasion_state`, view `live_prach_occasion_state_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

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

### Beamforming / Precoding / MIMO / Massive MIMO

- Route: `/reports/beamforming-precoding-mimo-massive-mimo`
- Table `live_beam_selection_table`: route `/reports/beamforming-precoding-mimo-massive-mimo/tables/live_beam_selection_table`, view `live_beam_selection_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_precoder_table`: route `/reports/beamforming-precoding-mimo-massive-mimo/tables/live_precoder_table`, view `live_precoder_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_combiner_table`: route `/reports/beamforming-precoding-mimo-massive-mimo/tables/live_combiner_table`, view `live_combiner_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_mimo_state_table`: route `/reports/beamforming-precoding-mimo-massive-mimo/tables/live_mimo_state_table`, view `live_mimo_state_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_user_grouping_table`: route `/reports/beamforming-precoding-mimo-massive-mimo/tables/live_user_grouping_table`, view `live_user_grouping_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### gNB-Side State / Thread / Coordinator / PHY-MAC API

- Route: `/reports/gnb-side-state-thread-coordinator-phy-mac-api`
- Table `live_gnb_state_table`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/tables/live_gnb_state_table`, view `live_gnb_state_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_per_cell_context`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/tables/live_per_cell_context`, view `live_per_cell_context_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_per_ue_context`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/tables/live_per_ue_context`, view `live_per_ue_context_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_phy_mac_api_table`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/tables/live_phy_mac_api_table`, view `live_phy_mac_api_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_thread_orchestration_table`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/tables/live_thread_orchestration_table`, view `live_thread_orchestration_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Mobility / Access / Cell Selection / Reselection / Handover

- Route: `/reports/mobility-access-cell-selection-reselection-handover`
- Chart `selected beam timeline`: route `/reports/mobility-access-cell-selection-reselection-handover/charts/selected-beam-timeline`, status `unavailable_until_source_table_has_real_rows`.

### Air Interface / Frame / Slot / Symbol / Grid

- Route: `/reports/air-interface-frame-slot-symbol-grid`
- Chart `PRACH occasion timeline`: route `/reports/air-interface-frame-slot-symbol-grid/charts/prach-occasion-timeline`, status `unavailable_until_source_table_has_real_rows`.

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

### Beamforming / Precoding / MIMO / Massive MIMO

- Route: `/reports/beamforming-precoding-mimo-massive-mimo`
- Chart `selected vs best beam timeline`: route `/reports/beamforming-precoding-mimo-massive-mimo/charts/selected-vs-best-beam-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `beam gain gap histogram`: route `/reports/beamforming-precoding-mimo-massive-mimo/charts/beam-gain-gap-histogram`, status `unavailable_until_source_table_has_real_rows`.
- Chart `beam hit rate timeline`: route `/reports/beamforming-precoding-mimo-massive-mimo/charts/beam-hit-rate-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `rank distribution`: route `/reports/beamforming-precoding-mimo-massive-mimo/charts/rank-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `condition number distribution`: route `/reports/beamforming-precoding-mimo-massive-mimo/charts/condition-number-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `MU grouping summary`: route `/reports/beamforming-precoding-mimo-massive-mimo/charts/mu-grouping-summary`, status `unavailable_until_source_table_has_real_rows`.
- Chart `precoder mode distribution`: route `/reports/beamforming-precoding-mimo-massive-mimo/charts/precoder-mode-distribution`, status `unavailable_until_source_table_has_real_rows`.

### gNB-Side State / Thread / Coordinator / PHY-MAC API

- Route: `/reports/gnb-side-state-thread-coordinator-phy-mac-api`
- Chart `per-cell context health timeline`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/charts/per-cell-context-health-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `API message rate`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/charts/api-message-rate`, status `unavailable_until_source_table_has_real_rows`.
- Chart `orchestration latency chart`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/charts/orchestration-latency-chart`, status `unavailable_until_source_table_has_real_rows`.
- Chart `per-worker workload chart`: route `/reports/gnb-side-state-thread-coordinator-phy-mac-api/charts/per-worker-workload-chart`, status `unavailable_until_source_table_has_real_rows`.

### HARQ Analytics

- Route: `/analytics/harq-analytics`
- Table `harq_analytics`: route `/analytics/harq-analytics/tables/harq_analytics`, view `harq_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `harq_process_analytics`: route `/analytics/harq-analytics/tables/harq_process_analytics`, view `harq_process_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `soft_buffer_analytics`: route `/analytics/harq-analytics/tables/soft_buffer_analytics`, view `soft_buffer_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Beamforming / Precoding / MIMO Analytics

- Route: `/analytics/beamforming-precoding-mimo-analytics`
- Table `beam_analytics`: route `/analytics/beamforming-precoding-mimo-analytics/tables/beam_analytics`, view `beam_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `mimo_analytics`: route `/analytics/beamforming-precoding-mimo-analytics/tables/mimo_analytics`, view `mimo_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `user_grouping_analytics`: route `/analytics/beamforming-precoding-mimo-analytics/tables/user_grouping_analytics`, view `user_grouping_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `precoder_analytics`: route `/analytics/beamforming-precoding-mimo-analytics/tables/precoder_analytics`, view `precoder_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Random Access / PRACH Analytics

- Route: `/analytics/random-access-prach-analytics`
- Table `random_access_analytics`: route `/analytics/random-access-prach-analytics/tables/random_access_analytics`, view `random_access_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `prach_analytics`: route `/analytics/random-access-prach-analytics/tables/prach_analytics`, view `prach_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Optional 6G Extension Analytics

- Route: `/analytics/optional-6g-extension-analytics`
- Table `cell_free_mimo_analytics`: route `/analytics/optional-6g-extension-analytics/tables/cell_free_mimo_analytics`, view `cell_free_mimo_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Resource Grid / RE Occupancy Analytics

- Route: `/analytics/resource-grid-re-occupancy-analytics`
- Chart `PDCCH map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/pdcch-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PBCH/SSB map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/pbch-ssb-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PDSCH map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/pdsch-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PUSCH map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/pusch-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PUCCH map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/pucch-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PRACH opportunity map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/prach-opportunity-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `SRS map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/srs-map`, status `unavailable_until_source_table_has_real_rows`.

### Detection / Control Analytics

- Route: `/analytics/detection-control-analytics`
- Chart `PRACH correlation peak distributions`: route `/analytics/detection-control-analytics/charts/prach-correlation-peak-distributions`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PRACH noise floor distributions`: route `/analytics/detection-control-analytics/charts/prach-noise-floor-distributions`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PRACH peak search results`: route `/analytics/detection-control-analytics/charts/prach-peak-search-results`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PUCCH DTX statistics`: route `/analytics/detection-control-analytics/charts/pucch-dtx-statistics`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PBCH/PDCCH/PUCCH detection and decode timelines`: route `/analytics/detection-control-analytics/charts/pbch-pdcch-pucch-detection-and-decode-timelines`, status `unavailable_until_source_table_has_real_rows`.

### Error / Reliability Analytics

- Route: `/analytics/error-reliability-analytics`
- Chart `residual BLER after HARQ`: route `/analytics/error-reliability-analytics/charts/residual-bler-after-harq`, status `unavailable_until_source_table_has_real_rows`.

### Measurement / CSI / Link Adaptation Analytics

- Route: `/analytics/measurement-csi-link-adaptation-analytics`
- Chart `per-beam quality plot`: route `/analytics/measurement-csi-link-adaptation-analytics/charts/per-beam-quality-plot`, status `unavailable_until_source_table_has_real_rows`.

### HARQ Analytics

- Route: `/analytics/harq-analytics`
- Chart `HARQ process timeline`: route `/analytics/harq-analytics/charts/harq-process-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `retransmission count histogram`: route `/analytics/harq-analytics/charts/retransmission-count-histogram`, status `unavailable_until_source_table_has_real_rows`.
- Chart `retransmission rate trend`: route `/analytics/harq-analytics/charts/retransmission-rate-trend`, status `unavailable_until_source_table_has_real_rows`.
- Chart `HARQ RTT distribution`: route `/analytics/harq-analytics/charts/harq-rtt-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `HARQ combining gain distribution`: route `/analytics/harq-analytics/charts/harq-combining-gain-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `newTx vs retx comparison`: route `/analytics/harq-analytics/charts/newtx-vs-retx-comparison`, status `unavailable_until_source_table_has_real_rows`.
- Chart `residual failure patterns`: route `/analytics/harq-analytics/charts/residual-failure-patterns`, status `unavailable_until_source_table_has_real_rows`.

### Beamforming / Precoding / MIMO Analytics

- Route: `/analytics/beamforming-precoding-mimo-analytics`
- Chart `beam id timeline`: route `/analytics/beamforming-precoding-mimo-analytics/charts/beam-id-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `beam pair timeline`: route `/analytics/beamforming-precoding-mimo-analytics/charts/beam-pair-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `selected vs best beam gap`: route `/analytics/beamforming-precoding-mimo-analytics/charts/selected-vs-best-beam-gap`, status `unavailable_until_source_table_has_real_rows`.
- Chart `beam hit rate / top-K hit rate`: route `/analytics/beamforming-precoding-mimo-analytics/charts/beam-hit-rate-top-k-hit-rate`, status `unavailable_until_source_table_has_real_rows`.
- Chart `beam gain gap histogram`: route `/analytics/beamforming-precoding-mimo-analytics/charts/beam-gain-gap-histogram`, status `unavailable_until_source_table_has_real_rows`.
- Chart `precoder mode distribution`: route `/analytics/beamforming-precoding-mimo-analytics/charts/precoder-mode-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `combiner summary`: route `/analytics/beamforming-precoding-mimo-analytics/charts/combiner-summary`, status `unavailable_until_source_table_has_real_rows`.
- Chart `rank distribution`: route `/analytics/beamforming-precoding-mimo-analytics/charts/rank-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `per-layer SINR`: route `/analytics/beamforming-precoding-mimo-analytics/charts/per-layer-sinr`, status `unavailable_until_source_table_has_real_rows`.
- Chart `inter-user leakage`: route `/analytics/beamforming-precoding-mimo-analytics/charts/inter-user-leakage`, status `unavailable_until_source_table_has_real_rows`.
- Chart `MU grouping analytics`: route `/analytics/beamforming-precoding-mimo-analytics/charts/mu-grouping-analytics`, status `unavailable_until_source_table_has_real_rows`.
- Chart `condition number distribution`: route `/analytics/beamforming-precoding-mimo-analytics/charts/condition-number-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `calibration / reciprocity diagnostics if modeled`: route `/analytics/beamforming-precoding-mimo-analytics/charts/calibration-reciprocity-diagnostics-if-modeled`, status `unavailable_until_source_table_has_real_rows`.

### Random Access / PRACH Analytics

- Route: `/analytics/random-access-prach-analytics`
- Chart `detection rate`: route `/analytics/random-access-prach-analytics/charts/detection-rate`, status `unavailable_until_source_table_has_real_rows`.
- Chart `false alarm rate`: route `/analytics/random-access-prach-analytics/charts/false-alarm-rate`, status `unavailable_until_source_table_has_real_rows`.
- Chart `missed detection rate`: route `/analytics/random-access-prach-analytics/charts/missed-detection-rate`, status `unavailable_until_source_table_has_real_rows`.
- Chart `access latency`: route `/analytics/random-access-prach-analytics/charts/access-latency`, status `unavailable_until_source_table_has_real_rows`.
- Chart `retry count distribution`: route `/analytics/random-access-prach-analytics/charts/retry-count-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `timing advance distribution`: route `/analytics/random-access-prach-analytics/charts/timing-advance-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `preamble/root/cyclic-shift usage summary`: route `/analytics/random-access-prach-analytics/charts/preamble-root-cyclic-shift-usage-summary`, status `unavailable_until_source_table_has_real_rows`.
- Chart `collision summary if modeled`: route `/analytics/random-access-prach-analytics/charts/collision-summary-if-modeled`, status `unavailable_until_source_table_has_real_rows`.

### Power / Energy / Efficiency Analytics

- Route: `/analytics/power-energy-efficiency-analytics`
- Chart `DL Tx power per cell / beam / UE`: route `/analytics/power-energy-efficiency-analytics/charts/dl-tx-power-per-cell-beam-ue`, status `unavailable_until_source_table_has_real_rows`.

### Regression / Baseline vs Candidate Analytics

- Route: `/analytics/regression-baseline-vs-candidate-analytics`
- Chart `HARQ delta`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/harq-delta`, status `unavailable_until_source_table_has_real_rows`.
- Chart `beam hit/gap delta`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/beam-hit-gap-delta`, status `unavailable_until_source_table_has_real_rows`.

### Optional 6G Extension Analytics

- Route: `/analytics/optional-6g-extension-analytics`
- Chart `cell-free / distributed MIMO combining gains`: route `/analytics/optional-6g-extension-analytics/charts/cell-free-distributed-mimo-combining-gains`, status `unavailable_until_source_table_has_real_rows`.
