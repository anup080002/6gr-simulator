# UE / gNB / Air Interface Output Spec

This document is additive-only. It does not declare that historical tables, CSVs, artifacts, browser pages, or plots should be deleted.

Runtime truth lives under `/reports`; derived study views live under `/analytics`. Missing outputs stay unavailable until a canonical DB row or artifact exists.

All major fact tables require the base context columns and value semantics from `apps/lls_output_contract.py`.

## Value Semantics

- value_role values: configured, resolved, applied, measured, estimated, derived, aggregated, placeholder, unavailable, fallback_substituted
- value_status values: OK, MISSING, NOT_AVAILABLE, PLACEHOLDER, FALLBACK_USED, PARTIAL, CRASHED, UNSUPPORTED, REVIEW_REQUIRED
- configured/resolved/applied/measured/derived values must keep explicit `value_source` and `value_definition` lineage.
- charts are never generated from smoke rows or placeholders by default.

## Sections


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

### SRS / UL Sounding / Massive MIMO Inputs

- Route: `/reports/srs-ul-sounding-massive-mimo-inputs`
- Table `live_srs_channel_estimation_table`: route `/reports/srs-ul-sounding-massive-mimo-inputs/tables/live_srs_channel_estimation_table`, view `live_srs_channel_estimation_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Channel / Interference / Impairments

- Route: `/reports/channel-interference-impairments`
- Table `live_channel_realization_table`: route `/reports/channel-interference-impairments/tables/live_channel_realization_table`, view `live_channel_realization_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_interference_table`: route `/reports/channel-interference-impairments/tables/live_interference_table`, view `live_interference_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_impairment_table`: route `/reports/channel-interference-impairments/tables/live_impairment_table`, view `live_impairment_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `live_tracking_table`: route `/reports/channel-interference-impairments/tables/live_tracking_table`, view `live_tracking_table_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

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

### Generic Investigator Views

- Route: `/reports/generic-investigator-views`
- Table `reports_value_semantics_coverage_v`: route `/reports/generic-investigator-views/tables/reports_value_semantics_coverage_v`, view `reports_value_semantics_coverage_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

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

### PUSCH / UL Data Chain

- Route: `/reports/pusch-ul-data-chain`
- Chart `channel estimation latency`: route `/reports/pusch-ul-data-chain/charts/channel-estimation-latency`, status `unavailable_until_source_table_has_real_rows`.

### PUCCH F0 / F1 / F2 / F3 / F4

- Route: `/reports/pucch-f0-f1-f2-f3-f4`
- Chart `requested vs resolved format confusion matrix`: route `/reports/pucch-f0-f1-f2-f3-f4/charts/requested-vs-resolved-format-confusion-matrix`, status `unavailable_until_source_table_has_real_rows`.

### PRACH / Random Access

- Route: `/reports/prach-random-access`
- Chart `peak value histogram`: route `/reports/prach-random-access/charts/peak-value-histogram`, status `unavailable_until_source_table_has_real_rows`.

### SRS / UL Sounding / Massive MIMO Inputs

- Route: `/reports/srs-ul-sounding-massive-mimo-inputs`
- Chart `channel estimate quality trend`: route `/reports/srs-ul-sounding-massive-mimo-inputs/charts/channel-estimate-quality-trend`, status `unavailable_until_source_table_has_real_rows`.

### Channel / Interference / Impairments

- Route: `/reports/channel-interference-impairments`
- Chart `channel quality timeline`: route `/reports/channel-interference-impairments/charts/channel-quality-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CFO true vs estimated vs residual`: route `/reports/channel-interference-impairments/charts/cfo-true-vs-estimated-vs-residual`, status `unavailable_until_source_table_has_real_rows`.
- Chart `timing offset true vs estimated vs residual`: route `/reports/channel-interference-impairments/charts/timing-offset-true-vs-estimated-vs-residual`, status `unavailable_until_source_table_has_real_rows`.
- Chart `pathloss/shadowing distributions`: route `/reports/channel-interference-impairments/charts/pathloss-shadowing-distributions`, status `unavailable_until_source_table_has_real_rows`.
- Chart `interference power timeline`: route `/reports/channel-interference-impairments/charts/interference-power-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `impairment contribution bar chart`: route `/reports/channel-interference-impairments/charts/impairment-contribution-bar-chart`, status `unavailable_until_source_table_has_real_rows`.
- Chart `channel heatmap artifact links`: route `/reports/channel-interference-impairments/charts/channel-heatmap-artifact-links`, status `unavailable_until_source_table_has_real_rows`.

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

### Generic Investigator Views

- Route: `/reports/generic-investigator-views`
- Chart `value semantics coverage chart`: route `/reports/generic-investigator-views/charts/value-semantics-coverage-chart`, status `unavailable_until_source_table_has_real_rows`.

### Channel Estimation / Propagation Analytics

- Route: `/analytics/channel-estimation-propagation-analytics`
- Table `channel_estimation_analytics`: route `/analytics/channel-estimation-propagation-analytics/tables/channel_estimation_analytics`, view `channel_estimation_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `channel_quality_analytics`: route `/analytics/channel-estimation-propagation-analytics/tables/channel_quality_analytics`, view `channel_quality_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `propagation_analytics`: route `/analytics/channel-estimation-propagation-analytics/tables/propagation_analytics`, view `propagation_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Throughput / Goodput / Spectral Efficiency Analytics

- Route: `/analytics/throughput-goodput-spectral-efficiency-analytics`
- Table `fairness_analytics`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/tables/fairness_analytics`, view `fairness_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Mobility / Selection / Reselection / Handover Analytics

- Route: `/analytics/mobility-selection-reselection-handover-analytics`
- Table `mobility_analytics`: route `/analytics/mobility-selection-reselection-handover-analytics/tables/mobility_analytics`, view `mobility_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `selection_reselection_analytics`: route `/analytics/mobility-selection-reselection-handover-analytics/tables/selection_reselection_analytics`, view `selection_reselection_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `handover_analytics`: route `/analytics/mobility-selection-reselection-handover-analytics/tables/handover_analytics`, view `handover_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Impairments / Tracking Analytics

- Route: `/analytics/impairments-tracking-analytics`
- Table `impairment_analytics`: route `/analytics/impairments-tracking-analytics/tables/impairment_analytics`, view `impairment_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `tracking_analytics`: route `/analytics/impairments-tracking-analytics/tables/tracking_analytics`, view `tracking_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Optional 6G Extension Analytics

- Route: `/analytics/optional-6g-extension-analytics`
- Table `cell_free_mimo_analytics`: route `/analytics/optional-6g-extension-analytics/tables/cell_free_mimo_analytics`, view `cell_free_mimo_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `sub_thz_impairment_analytics`: route `/analytics/optional-6g-extension-analytics/tables/sub_thz_impairment_analytics`, view `sub_thz_impairment_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Waveform / Time Domain Analytics

- Route: `/analytics/waveform-time-domain-analytics`
- Chart `pre-channel waveform`: route `/analytics/waveform-time-domain-analytics/charts/pre-channel-waveform`, status `unavailable_until_source_table_has_real_rows`.
- Chart `post-channel waveform`: route `/analytics/waveform-time-domain-analytics/charts/post-channel-waveform`, status `unavailable_until_source_table_has_real_rows`.
- Chart `post-impairment waveform`: route `/analytics/waveform-time-domain-analytics/charts/post-impairment-waveform`, status `unavailable_until_source_table_has_real_rows`.
- Chart `UE-wise / link-wise waveform comparison`: route `/analytics/waveform-time-domain-analytics/charts/ue-wise-link-wise-waveform-comparison`, status `unavailable_until_source_table_has_real_rows`.

### Spectrum / PSD / PAPR Analytics

- Route: `/analytics/spectrum-psd-papr-analytics`
- Chart `power spectral comparison before/after impairment`: route `/analytics/spectrum-psd-papr-analytics/charts/power-spectral-comparison-before-after-impairment`, status `unavailable_until_source_table_has_real_rows`.

### Channel Estimation / Propagation Analytics

- Route: `/analytics/channel-estimation-propagation-analytics`
- Chart `true H(tau) if available`: route `/analytics/channel-estimation-propagation-analytics/charts/true-h-tau-if-available`, status `unavailable_until_source_table_has_real_rows`.
- Chart `estimated Hhat(tau)`: route `/analytics/channel-estimation-propagation-analytics/charts/estimated-hhat-tau`, status `unavailable_until_source_table_has_real_rows`.
- Chart `true H(f) if available`: route `/analytics/channel-estimation-propagation-analytics/charts/true-h-f-if-available`, status `unavailable_until_source_table_has_real_rows`.
- Chart `estimated Hhat(f)`: route `/analytics/channel-estimation-propagation-analytics/charts/estimated-hhat-f`, status `unavailable_until_source_table_has_real_rows`.
- Chart `channel magnitude heatmap`: route `/analytics/channel-estimation-propagation-analytics/charts/channel-magnitude-heatmap`, status `unavailable_until_source_table_has_real_rows`.
- Chart `channel phase heatmap`: route `/analytics/channel-estimation-propagation-analytics/charts/channel-phase-heatmap`, status `unavailable_until_source_table_has_real_rows`.
- Chart `tap power profile`: route `/analytics/channel-estimation-propagation-analytics/charts/tap-power-profile`, status `unavailable_until_source_table_has_real_rows`.
- Chart `delay spread chart`: route `/analytics/channel-estimation-propagation-analytics/charts/delay-spread-chart`, status `unavailable_until_source_table_has_real_rows`.
- Chart `angle spread chart`: route `/analytics/channel-estimation-propagation-analytics/charts/angle-spread-chart`, status `unavailable_until_source_table_has_real_rows`.
- Chart `pathloss distribution`: route `/analytics/channel-estimation-propagation-analytics/charts/pathloss-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `shadowing distribution`: route `/analytics/channel-estimation-propagation-analytics/charts/shadowing-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `O2I distribution`: route `/analytics/channel-estimation-propagation-analytics/charts/o2i-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `noise variance trend`: route `/analytics/channel-estimation-propagation-analytics/charts/noise-variance-trend`, status `unavailable_until_source_table_has_real_rows`.
- Chart `NMSE vs SNR / SINR`: route `/analytics/channel-estimation-propagation-analytics/charts/nmse-vs-snr-sinr`, status `unavailable_until_source_table_has_real_rows`.
- Chart `estimator bias / variance summaries`: route `/analytics/channel-estimation-propagation-analytics/charts/estimator-bias-variance-summaries`, status `unavailable_until_source_table_has_real_rows`.
- Chart `serving vs interferer decomposition`: route `/analytics/channel-estimation-propagation-analytics/charts/serving-vs-interferer-decomposition`, status `unavailable_until_source_table_has_real_rows`.

### Error / Reliability Analytics

- Route: `/analytics/error-reliability-analytics`
- Chart `per-channel reliability breakdown`: route `/analytics/error-reliability-analytics/charts/per-channel-reliability-breakdown`, status `unavailable_until_source_table_has_real_rows`.
- Chart `per-UE and per-cell reliability`: route `/analytics/error-reliability-analytics/charts/per-ue-and-per-cell-reliability`, status `unavailable_until_source_table_has_real_rows`.

### Throughput / Goodput / Spectral Efficiency Analytics

- Route: `/analytics/throughput-goodput-spectral-efficiency-analytics`
- Chart `per-UE throughput`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/per-ue-throughput`, status `unavailable_until_source_table_has_real_rows`.
- Chart `per-cell throughput`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/per-cell-throughput`, status `unavailable_until_source_table_has_real_rows`.
- Chart `fairness index trend`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/fairness-index-trend`, status `unavailable_until_source_table_has_real_rows`.

### Beamforming / Precoding / MIMO Analytics

- Route: `/analytics/beamforming-precoding-mimo-analytics`
- Chart `beam pair timeline`: route `/analytics/beamforming-precoding-mimo-analytics/charts/beam-pair-timeline`, status `unavailable_until_source_table_has_real_rows`.

### Mobility / Selection / Reselection / Handover Analytics

- Route: `/analytics/mobility-selection-reselection-handover-analytics`
- Chart `UE trajectory views`: route `/analytics/mobility-selection-reselection-handover-analytics/charts/ue-trajectory-views`, status `unavailable_until_source_table_has_real_rows`.
- Chart `serving cell timeline`: route `/analytics/mobility-selection-reselection-handover-analytics/charts/serving-cell-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `neighbor ranking timeline`: route `/analytics/mobility-selection-reselection-handover-analytics/charts/neighbor-ranking-timeline`, status `unavailable_until_source_table_has_real_rows`.
- Chart `selection/reselection trigger tables`: route `/analytics/mobility-selection-reselection-handover-analytics/charts/selection-reselection-trigger-tables`, status `unavailable_until_source_table_has_real_rows`.
- Chart `hysteresis / TTT studies`: route `/analytics/mobility-selection-reselection-handover-analytics/charts/hysteresis-ttt-studies`, status `unavailable_until_source_table_has_real_rows`.
- Chart `mobility robustness summaries`: route `/analytics/mobility-selection-reselection-handover-analytics/charts/mobility-robustness-summaries`, status `unavailable_until_source_table_has_real_rows`.
- Chart `access delay vs mobility`: route `/analytics/mobility-selection-reselection-handover-analytics/charts/access-delay-vs-mobility`, status `unavailable_until_source_table_has_real_rows`.
- Chart `measurement filtering analytics`: route `/analytics/mobility-selection-reselection-handover-analytics/charts/measurement-filtering-analytics`, status `unavailable_until_source_table_has_real_rows`.
- Chart `handover event timeline`: route `/analytics/mobility-selection-reselection-handover-analytics/charts/handover-event-timeline`, status `unavailable_until_source_table_has_real_rows`.

### Impairments / Tracking Analytics

- Route: `/analytics/impairments-tracking-analytics`
- Chart `CFO true vs estimated vs residual`: route `/analytics/impairments-tracking-analytics/charts/cfo-true-vs-estimated-vs-residual`, status `unavailable_until_source_table_has_real_rows`.
- Chart `timing offset true vs estimated vs residual`: route `/analytics/impairments-tracking-analytics/charts/timing-offset-true-vs-estimated-vs-residual`, status `unavailable_until_source_table_has_real_rows`.
- Chart `phase noise summary`: route `/analytics/impairments-tracking-analytics/charts/phase-noise-summary`, status `unavailable_until_source_table_has_real_rows`.
- Chart `IQ imbalance summary`: route `/analytics/impairments-tracking-analytics/charts/iq-imbalance-summary`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PA nonlinearity summary`: route `/analytics/impairments-tracking-analytics/charts/pa-nonlinearity-summary`, status `unavailable_until_source_table_has_real_rows`.
- Chart `clipping summary`: route `/analytics/impairments-tracking-analytics/charts/clipping-summary`, status `unavailable_until_source_table_has_real_rows`.
- Chart `quantization summary`: route `/analytics/impairments-tracking-analytics/charts/quantization-summary`, status `unavailable_until_source_table_has_real_rows`.
- Chart `impairment order trace`: route `/analytics/impairments-tracking-analytics/charts/impairment-order-trace`, status `unavailable_until_source_table_has_real_rows`.
- Chart `contribution decomposition if measurable`: route `/analytics/impairments-tracking-analytics/charts/contribution-decomposition-if-measurable`, status `unavailable_until_source_table_has_real_rows`.

### Power / Energy / Efficiency Analytics

- Route: `/analytics/power-energy-efficiency-analytics`
- Chart `DL Tx power per cell / beam / UE`: route `/analytics/power-energy-efficiency-analytics/charts/dl-tx-power-per-cell-beam-ue`, status `unavailable_until_source_table_has_real_rows`.
- Chart `UL Tx power per UE`: route `/analytics/power-energy-efficiency-analytics/charts/ul-tx-power-per-ue`, status `unavailable_until_source_table_has_real_rows`.
- Chart `energy efficiency by UE`: route `/analytics/power-energy-efficiency-analytics/charts/energy-efficiency-by-ue`, status `unavailable_until_source_table_has_real_rows`.
- Chart `energy efficiency by cell`: route `/analytics/power-energy-efficiency-analytics/charts/energy-efficiency-by-cell`, status `unavailable_until_source_table_has_real_rows`.

### Optional 6G Extension Analytics

- Route: `/analytics/optional-6g-extension-analytics`
- Chart `cell-free / distributed MIMO combining gains`: route `/analytics/optional-6g-extension-analytics/charts/cell-free-distributed-mimo-combining-gains`, status `unavailable_until_source_table_has_real_rows`.
- Chart `sub-THz impairment studies`: route `/analytics/optional-6g-extension-analytics/charts/sub-thz-impairment-studies`, status `unavailable_until_source_table_has_real_rows`.
