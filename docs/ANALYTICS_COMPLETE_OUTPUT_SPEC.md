# Complete Analytics Output Spec

This document is additive-only. It does not declare that historical tables, CSVs, artifacts, browser pages, or plots should be deleted.

Runtime truth lives under `/reports`; derived study views live under `/analytics`. Missing outputs stay unavailable until a canonical DB row or artifact exists.

All major fact tables require the base context columns and value semantics from `apps/lls_output_contract.py`.

## Value Semantics

- value_role values: configured, resolved, applied, measured, estimated, derived, aggregated, placeholder, unavailable, fallback_substituted
- value_status values: OK, MISSING, NOT_AVAILABLE, PLACEHOLDER, FALLBACK_USED, PARTIAL, CRASHED, UNSUPPORTED, REVIEW_REQUIRED
- configured/resolved/applied/measured/derived values must keep explicit `value_source` and `value_definition` lineage.
- charts are never generated from smoke rows or placeholders by default.

## Sections


### Waveform / Time Domain Analytics

- Route: `/analytics/waveform-time-domain-analytics`
- Table `waveform_analytics`: route `/analytics/waveform-time-domain-analytics/tables/waveform_analytics`, view `waveform_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `waveform_comparison_analytics`: route `/analytics/waveform-time-domain-analytics/tables/waveform_comparison_analytics`, view `waveform_comparison_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `waveform_stage_overlay_analytics`: route `/analytics/waveform-time-domain-analytics/tables/waveform_stage_overlay_analytics`, view `waveform_stage_overlay_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Spectrum / PSD / PAPR Analytics

- Route: `/analytics/spectrum-psd-papr-analytics`
- Table `spectrum_analytics`: route `/analytics/spectrum-psd-papr-analytics/tables/spectrum_analytics`, view `spectrum_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `papr_analytics`: route `/analytics/spectrum-psd-papr-analytics/tables/papr_analytics`, view `papr_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `clipping_analytics`: route `/analytics/spectrum-psd-papr-analytics/tables/clipping_analytics`, view `clipping_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Constellation / EVM Analytics

- Route: `/analytics/constellation-evm-analytics`
- Table `constellation_analytics`: route `/analytics/constellation-evm-analytics/tables/constellation_analytics`, view `constellation_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `evm_analytics`: route `/analytics/constellation-evm-analytics/tables/evm_analytics`, view `evm_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Resource Grid / RE Occupancy Analytics

- Route: `/analytics/resource-grid-re-occupancy-analytics`
- Table `resource_grid_analytics`: route `/analytics/resource-grid-re-occupancy-analytics/tables/resource_grid_analytics`, view `resource_grid_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `re_collision_analytics`: route `/analytics/resource-grid-re-occupancy-analytics/tables/re_collision_analytics`, view `re_collision_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Channel Estimation / Propagation Analytics

- Route: `/analytics/channel-estimation-propagation-analytics`
- Table `channel_estimation_analytics`: route `/analytics/channel-estimation-propagation-analytics/tables/channel_estimation_analytics`, view `channel_estimation_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `channel_quality_analytics`: route `/analytics/channel-estimation-propagation-analytics/tables/channel_quality_analytics`, view `channel_quality_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `propagation_analytics`: route `/analytics/channel-estimation-propagation-analytics/tables/propagation_analytics`, view `propagation_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Detection / Control Analytics

- Route: `/analytics/detection-control-analytics`
- Table `detection_analytics`: route `/analytics/detection-control-analytics/tables/detection_analytics`, view `detection_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `control_decode_analytics`: route `/analytics/detection-control-analytics/tables/control_decode_analytics`, view `control_decode_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `random_access_detection_analytics`: route `/analytics/detection-control-analytics/tables/random_access_detection_analytics`, view `random_access_detection_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Error / Reliability Analytics

- Route: `/analytics/error-reliability-analytics`
- Table `error_rate_analytics`: route `/analytics/error-reliability-analytics/tables/error_rate_analytics`, view `error_rate_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `decoder_analytics`: route `/analytics/error-reliability-analytics/tables/decoder_analytics`, view `decoder_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `codeblock_analytics`: route `/analytics/error-reliability-analytics/tables/codeblock_analytics`, view `codeblock_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Throughput / Goodput / Spectral Efficiency Analytics

- Route: `/analytics/throughput-goodput-spectral-efficiency-analytics`
- Table `throughput_analytics`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/tables/throughput_analytics`, view `throughput_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `goodput_analytics`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/tables/goodput_analytics`, view `goodput_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `spectral_efficiency_analytics`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/tables/spectral_efficiency_analytics`, view `spectral_efficiency_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `fairness_analytics`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/tables/fairness_analytics`, view `fairness_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Measurement / CSI / Link Adaptation Analytics

- Route: `/analytics/measurement-csi-link-adaptation-analytics`
- Table `measurement_feedback_analytics`: route `/analytics/measurement-csi-link-adaptation-analytics/tables/measurement_feedback_analytics`, view `measurement_feedback_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `link_adaptation_analytics`: route `/analytics/measurement-csi-link-adaptation-analytics/tables/link_adaptation_analytics`, view `link_adaptation_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `cqi_mcs_consistency_analytics`: route `/analytics/measurement-csi-link-adaptation-analytics/tables/cqi_mcs_consistency_analytics`, view `cqi_mcs_consistency_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

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

### Mobility / Selection / Reselection / Handover Analytics

- Route: `/analytics/mobility-selection-reselection-handover-analytics`
- Table `mobility_analytics`: route `/analytics/mobility-selection-reselection-handover-analytics/tables/mobility_analytics`, view `mobility_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `selection_reselection_analytics`: route `/analytics/mobility-selection-reselection-handover-analytics/tables/selection_reselection_analytics`, view `selection_reselection_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `handover_analytics`: route `/analytics/mobility-selection-reselection-handover-analytics/tables/handover_analytics`, view `handover_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Random Access / PRACH Analytics

- Route: `/analytics/random-access-prach-analytics`
- Table `random_access_analytics`: route `/analytics/random-access-prach-analytics/tables/random_access_analytics`, view `random_access_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `prach_analytics`: route `/analytics/random-access-prach-analytics/tables/prach_analytics`, view `prach_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Impairments / Tracking Analytics

- Route: `/analytics/impairments-tracking-analytics`
- Table `impairment_analytics`: route `/analytics/impairments-tracking-analytics/tables/impairment_analytics`, view `impairment_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `tracking_analytics`: route `/analytics/impairments-tracking-analytics/tables/tracking_analytics`, view `tracking_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Power / Energy / Efficiency Analytics

- Route: `/analytics/power-energy-efficiency-analytics`
- Table `power_analytics`: route `/analytics/power-energy-efficiency-analytics/tables/power_analytics`, view `power_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `energy_efficiency_analytics`: route `/analytics/power-energy-efficiency-analytics/tables/energy_efficiency_analytics`, view `energy_efficiency_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `runtime_power_analytics`: route `/analytics/power-energy-efficiency-analytics/tables/runtime_power_analytics`, view `runtime_power_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `sleep_state_analytics`: route `/analytics/power-energy-efficiency-analytics/tables/sleep_state_analytics`, view `sleep_state_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Runtime / Compute / Complexity / Parallelism Analytics

- Route: `/analytics/runtime-compute-complexity-parallelism-analytics`
- Table `compute_analytics`: route `/analytics/runtime-compute-complexity-parallelism-analytics/tables/compute_analytics`, view `compute_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `runtime_latency_analytics`: route `/analytics/runtime-compute-complexity-parallelism-analytics/tables/runtime_latency_analytics`, view `runtime_latency_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `determinism_analytics`: route `/analytics/runtime-compute-complexity-parallelism-analytics/tables/determinism_analytics`, view `determinism_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `parallelism_analytics`: route `/analytics/runtime-compute-complexity-parallelism-analytics/tables/parallelism_analytics`, view `parallelism_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Export / Consistency / Truth Analytics

- Route: `/analytics/export-consistency-truth-analytics`
- Table `export_consistency_analytics`: route `/analytics/export-consistency-truth-analytics/tables/export_consistency_analytics`, view `export_consistency_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `truth_policy_analytics`: route `/analytics/export-consistency-truth-analytics/tables/truth_policy_analytics`, view `truth_policy_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `schema_drift_analytics`: route `/analytics/export-consistency-truth-analytics/tables/schema_drift_analytics`, view `schema_drift_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Regression / Baseline vs Candidate Analytics

- Route: `/analytics/regression-baseline-vs-candidate-analytics`
- Table `regression_analytics`: route `/analytics/regression-baseline-vs-candidate-analytics/tables/regression_analytics`, view `regression_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `regression_baseline_view`: route `/analytics/regression-baseline-vs-candidate-analytics/tables/regression_baseline_view`, view `regression_baseline_view_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `regression_candidate_view`: route `/analytics/regression-baseline-vs-candidate-analytics/tables/regression_candidate_view`, view `regression_candidate_view_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `regression_delta_view`: route `/analytics/regression-baseline-vs-candidate-analytics/tables/regression_delta_view`, view `regression_delta_view_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `change_impact_analytics`: route `/analytics/regression-baseline-vs-candidate-analytics/tables/change_impact_analytics`, view `change_impact_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Optional 6G Extension Analytics

- Route: `/analytics/optional-6g-extension-analytics`
- Table `ai_inference_analytics`: route `/analytics/optional-6g-extension-analytics/tables/ai_inference_analytics`, view `ai_inference_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `sensing_analytics`: route `/analytics/optional-6g-extension-analytics/tables/sensing_analytics`, view `sensing_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `localization_analytics`: route `/analytics/optional-6g-extension-analytics/tables/localization_analytics`, view `localization_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `ntn_haps_uav_analytics`: route `/analytics/optional-6g-extension-analytics/tables/ntn_haps_uav_analytics`, view `ntn_haps_uav_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `ris_analytics`: route `/analytics/optional-6g-extension-analytics/tables/ris_analytics`, view `ris_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `cell_free_mimo_analytics`: route `/analytics/optional-6g-extension-analytics/tables/cell_free_mimo_analytics`, view `cell_free_mimo_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.
- Table `sub_thz_impairment_analytics`: route `/analytics/optional-6g-extension-analytics/tables/sub_thz_impairment_analytics`, view `sub_thz_impairment_analytics_v`, default status `unavailable_until_canonical_artifact_or_db_view_exists`.

### Waveform / Time Domain Analytics

- Route: `/analytics/waveform-time-domain-analytics`
- Chart `Tx waveform`: route `/analytics/waveform-time-domain-analytics/charts/tx-waveform`, status `unavailable_until_source_table_has_real_rows`.
- Chart `Rx waveform`: route `/analytics/waveform-time-domain-analytics/charts/rx-waveform`, status `unavailable_until_source_table_has_real_rows`.
- Chart `pre-channel waveform`: route `/analytics/waveform-time-domain-analytics/charts/pre-channel-waveform`, status `unavailable_until_source_table_has_real_rows`.
- Chart `post-channel waveform`: route `/analytics/waveform-time-domain-analytics/charts/post-channel-waveform`, status `unavailable_until_source_table_has_real_rows`.
- Chart `post-impairment waveform`: route `/analytics/waveform-time-domain-analytics/charts/post-impairment-waveform`, status `unavailable_until_source_table_has_real_rows`.
- Chart `magnitude vs sample`: route `/analytics/waveform-time-domain-analytics/charts/magnitude-vs-sample`, status `unavailable_until_source_table_has_real_rows`.
- Chart `phase vs sample`: route `/analytics/waveform-time-domain-analytics/charts/phase-vs-sample`, status `unavailable_until_source_table_has_real_rows`.
- Chart `power vs sample`: route `/analytics/waveform-time-domain-analytics/charts/power-vs-sample`, status `unavailable_until_source_table_has_real_rows`.
- Chart `stage overlay plots`: route `/analytics/waveform-time-domain-analytics/charts/stage-overlay-plots`, status `unavailable_until_source_table_has_real_rows`.
- Chart `UE-wise / link-wise waveform comparison`: route `/analytics/waveform-time-domain-analytics/charts/ue-wise-link-wise-waveform-comparison`, status `unavailable_until_source_table_has_real_rows`.

### Spectrum / PSD / PAPR Analytics

- Route: `/analytics/spectrum-psd-papr-analytics`
- Chart `PSD`: route `/analytics/spectrum-psd-papr-analytics/charts/psd`, status `unavailable_until_source_table_has_real_rows`.
- Chart `occupied bandwidth`: route `/analytics/spectrum-psd-papr-analytics/charts/occupied-bandwidth`, status `unavailable_until_source_table_has_real_rows`.
- Chart `out-of-band spectral summaries if measurable`: route `/analytics/spectrum-psd-papr-analytics/charts/out-of-band-spectral-summaries-if-measurable`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PAPR histogram / CDF`: route `/analytics/spectrum-psd-papr-analytics/charts/papr-histogram-cdf`, status `unavailable_until_source_table_has_real_rows`.
- Chart `clipping event histogram`: route `/analytics/spectrum-psd-papr-analytics/charts/clipping-event-histogram`, status `unavailable_until_source_table_has_real_rows`.
- Chart `power spectral comparison before/after impairment`: route `/analytics/spectrum-psd-papr-analytics/charts/power-spectral-comparison-before-after-impairment`, status `unavailable_until_source_table_has_real_rows`.

### Constellation / EVM Analytics

- Route: `/analytics/constellation-evm-analytics`
- Chart `pre-equalization constellation`: route `/analytics/constellation-evm-analytics/charts/pre-equalization-constellation`, status `unavailable_until_source_table_has_real_rows`.
- Chart `post-equalization constellation`: route `/analytics/constellation-evm-analytics/charts/post-equalization-constellation`, status `unavailable_until_source_table_has_real_rows`.
- Chart `constellation per layer`: route `/analytics/constellation-evm-analytics/charts/constellation-per-layer`, status `unavailable_until_source_table_has_real_rows`.
- Chart `constellation per codeword`: route `/analytics/constellation-evm-analytics/charts/constellation-per-codeword`, status `unavailable_until_source_table_has_real_rows`.
- Chart `constellation per modulation order`: route `/analytics/constellation-evm-analytics/charts/constellation-per-modulation-order`, status `unavailable_until_source_table_has_real_rows`.
- Chart `EVM RMS`: route `/analytics/constellation-evm-analytics/charts/evm-rms`, status `unavailable_until_source_table_has_real_rows`.
- Chart `EVM per symbol`: route `/analytics/constellation-evm-analytics/charts/evm-per-symbol`, status `unavailable_until_source_table_has_real_rows`.
- Chart `EVM per subcarrier`: route `/analytics/constellation-evm-analytics/charts/evm-per-subcarrier`, status `unavailable_until_source_table_has_real_rows`.
- Chart `EVM per layer`: route `/analytics/constellation-evm-analytics/charts/evm-per-layer`, status `unavailable_until_source_table_has_real_rows`.
- Chart `symbol decision error histogram`: route `/analytics/constellation-evm-analytics/charts/symbol-decision-error-histogram`, status `unavailable_until_source_table_has_real_rows`.

### Resource Grid / RE Occupancy Analytics

- Route: `/analytics/resource-grid-re-occupancy-analytics`
- Chart `RE occupancy heatmap`: route `/analytics/resource-grid-re-occupancy-analytics/charts/re-occupancy-heatmap`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PRB heatmap`: route `/analytics/resource-grid-re-occupancy-analytics/charts/prb-heatmap`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PDCCH map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/pdcch-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PBCH/SSB map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/pbch-ssb-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CSI-RS map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/csi-rs-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PDSCH map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/pdsch-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PUSCH map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/pusch-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PUCCH map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/pucch-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PRACH opportunity map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/prach-opportunity-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `SRS map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/srs-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `DMRS/PTRS occupancy map`: route `/analytics/resource-grid-re-occupancy-analytics/charts/dmrs-ptrs-occupancy-map`, status `unavailable_until_source_table_has_real_rows`.
- Chart `RE collision heatmap / table`: route `/analytics/resource-grid-re-occupancy-analytics/charts/re-collision-heatmap-table`, status `unavailable_until_source_table_has_real_rows`.

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

### Detection / Control Analytics

- Route: `/analytics/detection-control-analytics`
- Chart `P_FA`: route `/analytics/detection-control-analytics/charts/p-fa`, status `unavailable_until_source_table_has_real_rows`.
- Chart `FAR`: route `/analytics/detection-control-analytics/charts/far`, status `unavailable_until_source_table_has_real_rows`.
- Chart `P_MD`: route `/analytics/detection-control-analytics/charts/p-md`, status `unavailable_until_source_table_has_real_rows`.
- Chart `P_D`: route `/analytics/detection-control-analytics/charts/p-d`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PRACH correlation peak distributions`: route `/analytics/detection-control-analytics/charts/prach-correlation-peak-distributions`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PRACH noise floor distributions`: route `/analytics/detection-control-analytics/charts/prach-noise-floor-distributions`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PRACH peak search results`: route `/analytics/detection-control-analytics/charts/prach-peak-search-results`, status `unavailable_until_source_table_has_real_rows`.
- Chart `SSB detection statistics`: route `/analytics/detection-control-analytics/charts/ssb-detection-statistics`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PUCCH DTX statistics`: route `/analytics/detection-control-analytics/charts/pucch-dtx-statistics`, status `unavailable_until_source_table_has_real_rows`.
- Chart `control decode success/failure tables`: route `/analytics/detection-control-analytics/charts/control-decode-success-failure-tables`, status `unavailable_until_source_table_has_real_rows`.
- Chart `threshold sweep plots if data exists`: route `/analytics/detection-control-analytics/charts/threshold-sweep-plots-if-data-exists`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PBCH/PDCCH/PUCCH detection and decode timelines`: route `/analytics/detection-control-analytics/charts/pbch-pdcch-pucch-detection-and-decode-timelines`, status `unavailable_until_source_table_has_real_rows`.

### Error / Reliability Analytics

- Route: `/analytics/error-reliability-analytics`
- Chart `BER`: route `/analytics/error-reliability-analytics/charts/ber`, status `unavailable_until_source_table_has_real_rows`.
- Chart `BLER`: route `/analytics/error-reliability-analytics/charts/bler`, status `unavailable_until_source_table_has_real_rows`.
- Chart `FER`: route `/analytics/error-reliability-analytics/charts/fer`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CRC pass/fail rates`: route `/analytics/error-reliability-analytics/charts/crc-pass-fail-rates`, status `unavailable_until_source_table_has_real_rows`.
- Chart `code-block error rates`: route `/analytics/error-reliability-analytics/charts/code-block-error-rates`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CBG error rates`: route `/analytics/error-reliability-analytics/charts/cbg-error-rates`, status `unavailable_until_source_table_has_real_rows`.
- Chart `residual BLER after HARQ`: route `/analytics/error-reliability-analytics/charts/residual-bler-after-harq`, status `unavailable_until_source_table_has_real_rows`.
- Chart `decoder iteration distributions`: route `/analytics/error-reliability-analytics/charts/decoder-iteration-distributions`, status `unavailable_until_source_table_has_real_rows`.
- Chart `per-channel reliability breakdown`: route `/analytics/error-reliability-analytics/charts/per-channel-reliability-breakdown`, status `unavailable_until_source_table_has_real_rows`.
- Chart `per-format reliability breakdown`: route `/analytics/error-reliability-analytics/charts/per-format-reliability-breakdown`, status `unavailable_until_source_table_has_real_rows`.
- Chart `per-UE and per-cell reliability`: route `/analytics/error-reliability-analytics/charts/per-ue-and-per-cell-reliability`, status `unavailable_until_source_table_has_real_rows`.
- Chart `BLER vs SNR`: route `/analytics/error-reliability-analytics/charts/bler-vs-snr`, status `unavailable_until_source_table_has_real_rows`.
- Chart `BLER vs SINR`: route `/analytics/error-reliability-analytics/charts/bler-vs-sinr`, status `unavailable_until_source_table_has_real_rows`.
- Chart `BER vs SNR`: route `/analytics/error-reliability-analytics/charts/ber-vs-snr`, status `unavailable_until_source_table_has_real_rows`.
- Chart `FER vs SNR`: route `/analytics/error-reliability-analytics/charts/fer-vs-snr`, status `unavailable_until_source_table_has_real_rows`.

### Throughput / Goodput / Spectral Efficiency Analytics

- Route: `/analytics/throughput-goodput-spectral-efficiency-analytics`
- Chart `throughput`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/throughput`, status `unavailable_until_source_table_has_real_rows`.
- Chart `offered throughput`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/offered-throughput`, status `unavailable_until_source_table_has_real_rows`.
- Chart `goodput`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/goodput`, status `unavailable_until_source_table_has_real_rows`.
- Chart `spectral efficiency`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/spectral-efficiency`, status `unavailable_until_source_table_has_real_rows`.
- Chart `throughput vs SNR`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/throughput-vs-snr`, status `unavailable_until_source_table_has_real_rows`.
- Chart `throughput vs SINR`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/throughput-vs-sinr`, status `unavailable_until_source_table_has_real_rows`.
- Chart `throughput vs load`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/throughput-vs-load`, status `unavailable_until_source_table_has_real_rows`.
- Chart `goodput vs retransmissions`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/goodput-vs-retransmissions`, status `unavailable_until_source_table_has_real_rows`.
- Chart `per-UE throughput`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/per-ue-throughput`, status `unavailable_until_source_table_has_real_rows`.
- Chart `per-cell throughput`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/per-cell-throughput`, status `unavailable_until_source_table_has_real_rows`.
- Chart `throughput percentile plots`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/throughput-percentile-plots`, status `unavailable_until_source_table_has_real_rows`.
- Chart `throughput CDF`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/throughput-cdf`, status `unavailable_until_source_table_has_real_rows`.
- Chart `fairness index trend`: route `/analytics/throughput-goodput-spectral-efficiency-analytics/charts/fairness-index-trend`, status `unavailable_until_source_table_has_real_rows`.

### Measurement / CSI / Link Adaptation Analytics

- Route: `/analytics/measurement-csi-link-adaptation-analytics`
- Chart `configured SNR vs applied AWGN SNR vs measured SINR vs large-scale SINR`: route `/analytics/measurement-csi-link-adaptation-analytics/charts/configured-snr-vs-applied-awgn-snr-vs-measured-sinr-vs-large-scale-sinr`, status `unavailable_until_source_table_has_real_rows`.
- Chart `ServingRSRP / RSRP / CSI-RSRP trends`: route `/analytics/measurement-csi-link-adaptation-analytics/charts/servingrsrp-rsrp-csi-rsrp-trends`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CQI / PMI / RI / CRI / SSBRI trends`: route `/analytics/measurement-csi-link-adaptation-analytics/charts/cqi-pmi-ri-cri-ssbri-trends`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CQI-to-MCS mapping plot`: route `/analytics/measurement-csi-link-adaptation-analytics/charts/cqi-to-mcs-mapping-plot`, status `unavailable_until_source_table_has_real_rows`.
- Chart `selected MCS distribution`: route `/analytics/measurement-csi-link-adaptation-analytics/charts/selected-mcs-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `selected vs derived MCS confusion matrix`: route `/analytics/measurement-csi-link-adaptation-analytics/charts/selected-vs-derived-mcs-confusion-matrix`, status `unavailable_until_source_table_has_real_rows`.
- Chart `quality-vs-selected-MCS mismatch plot`: route `/analytics/measurement-csi-link-adaptation-analytics/charts/quality-vs-selected-mcs-mismatch-plot`, status `unavailable_until_source_table_has_real_rows`.
- Chart `per-beam quality plot`: route `/analytics/measurement-csi-link-adaptation-analytics/charts/per-beam-quality-plot`, status `unavailable_until_source_table_has_real_rows`.
- Chart `per-layer quality plot`: route `/analytics/measurement-csi-link-adaptation-analytics/charts/per-layer-quality-plot`, status `unavailable_until_source_table_has_real_rows`.
- Chart `config-vs-measured conflict dashboard`: route `/analytics/measurement-csi-link-adaptation-analytics/charts/config-vs-measured-conflict-dashboard`, status `unavailable_until_source_table_has_real_rows`.

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
- Chart `power control behavior`: route `/analytics/power-energy-efficiency-analytics/charts/power-control-behavior`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PA backoff distribution`: route `/analytics/power-energy-efficiency-analytics/charts/pa-backoff-distribution`, status `unavailable_until_source_table_has_real_rows`.
- Chart `RF chain power`: route `/analytics/power-energy-efficiency-analytics/charts/rf-chain-power`, status `unavailable_until_source_table_has_real_rows`.
- Chart `baseband power`: route `/analytics/power-energy-efficiency-analytics/charts/baseband-power`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CPU power if available`: route `/analytics/power-energy-efficiency-analytics/charts/cpu-power-if-available`, status `unavailable_until_source_table_has_real_rows`.
- Chart `power vs throughput`: route `/analytics/power-energy-efficiency-analytics/charts/power-vs-throughput`, status `unavailable_until_source_table_has_real_rows`.
- Chart `power vs BLER`: route `/analytics/power-energy-efficiency-analytics/charts/power-vs-bler`, status `unavailable_until_source_table_has_real_rows`.
- Chart `energy/bit`: route `/analytics/power-energy-efficiency-analytics/charts/energy-bit`, status `unavailable_until_source_table_has_real_rows`.
- Chart `joules/GB`: route `/analytics/power-energy-efficiency-analytics/charts/joules-gb`, status `unavailable_until_source_table_has_real_rows`.
- Chart `energy efficiency by UE`: route `/analytics/power-energy-efficiency-analytics/charts/energy-efficiency-by-ue`, status `unavailable_until_source_table_has_real_rows`.
- Chart `energy efficiency by cell`: route `/analytics/power-energy-efficiency-analytics/charts/energy-efficiency-by-cell`, status `unavailable_until_source_table_has_real_rows`.
- Chart `sleep/idle/active state occupancy`: route `/analytics/power-energy-efficiency-analytics/charts/sleep-idle-active-state-occupancy`, status `unavailable_until_source_table_has_real_rows`.
- Chart `PAPR vs power`: route `/analytics/power-energy-efficiency-analytics/charts/papr-vs-power`, status `unavailable_until_source_table_has_real_rows`.
- Chart `thermal/throttling analytics if available`: route `/analytics/power-energy-efficiency-analytics/charts/thermal-throttling-analytics-if-available`, status `unavailable_until_source_table_has_real_rows`.

### Runtime / Compute / Complexity / Parallelism Analytics

- Route: `/analytics/runtime-compute-complexity-parallelism-analytics`
- Chart `block execution time`: route `/analytics/runtime-compute-complexity-parallelism-analytics/charts/block-execution-time`, status `unavailable_until_source_table_has_real_rows`.
- Chart `stage latency`: route `/analytics/runtime-compute-complexity-parallelism-analytics/charts/stage-latency`, status `unavailable_until_source_table_has_real_rows`.
- Chart `end-to-end latency`: route `/analytics/runtime-compute-complexity-parallelism-analytics/charts/end-to-end-latency`, status `unavailable_until_source_table_has_real_rows`.
- Chart `compute latency`: route `/analytics/runtime-compute-complexity-parallelism-analytics/charts/compute-latency`, status `unavailable_until_source_table_has_real_rows`.
- Chart `decode latency`: route `/analytics/runtime-compute-complexity-parallelism-analytics/charts/decode-latency`, status `unavailable_until_source_table_has_real_rows`.
- Chart `CPU cycles`: route `/analytics/runtime-compute-complexity-parallelism-analytics/charts/cpu-cycles`, status `unavailable_until_source_table_has_real_rows`.
- Chart `memory usage`: route `/analytics/runtime-compute-complexity-parallelism-analytics/charts/memory-usage`, status `unavailable_until_source_table_has_real_rows`.
- Chart `worker timelines`: route `/analytics/runtime-compute-complexity-parallelism-analytics/charts/worker-timelines`, status `unavailable_until_source_table_has_real_rows`.
- Chart `lock/contention observations`: route `/analytics/runtime-compute-complexity-parallelism-analytics/charts/lock-contention-observations`, status `unavailable_until_source_table_has_real_rows`.
- Chart `DB write latency`: route `/analytics/runtime-compute-complexity-parallelism-analytics/charts/db-write-latency`, status `unavailable_until_source_table_has_real_rows`.
- Chart `export lag`: route `/analytics/runtime-compute-complexity-parallelism-analytics/charts/export-lag`, status `unavailable_until_source_table_has_real_rows`.
- Chart `single-thread vs multi-thread determinism`: route `/analytics/runtime-compute-complexity-parallelism-analytics/charts/single-thread-vs-multi-thread-determinism`, status `unavailable_until_source_table_has_real_rows`.
- Chart `dropped row / duplicate write analytics`: route `/analytics/runtime-compute-complexity-parallelism-analytics/charts/dropped-row-duplicate-write-analytics`, status `unavailable_until_source_table_has_real_rows`.
- Chart `decoder complexity units`: route `/analytics/runtime-compute-complexity-parallelism-analytics/charts/decoder-complexity-units`, status `unavailable_until_source_table_has_real_rows`.
- Chart `normalized decoder complexity`: route `/analytics/runtime-compute-complexity-parallelism-analytics/charts/normalized-decoder-complexity`, status `unavailable_until_source_table_has_real_rows`.

### Export / Consistency / Truth Analytics

- Route: `/analytics/export-consistency-truth-analytics`
- Chart `CSV vs DB consistency`: route `/analytics/export-consistency-truth-analytics/charts/csv-vs-db-consistency`, status `unavailable_until_source_table_has_real_rows`.
- Chart `DB vs browser consistency`: route `/analytics/export-consistency-truth-analytics/charts/db-vs-browser-consistency`, status `unavailable_until_source_table_has_real_rows`.
- Chart `source row count vs analytics row count`: route `/analytics/export-consistency-truth-analytics/charts/source-row-count-vs-analytics-row-count`, status `unavailable_until_source_table_has_real_rows`.
- Chart `missing-field audits`: route `/analytics/export-consistency-truth-analytics/charts/missing-field-audits`, status `unavailable_until_source_table_has_real_rows`.
- Chart `schema drift`: route `/analytics/export-consistency-truth-analytics/charts/schema-drift`, status `unavailable_until_source_table_has_real_rows`.
- Chart `config drift`: route `/analytics/export-consistency-truth-analytics/charts/config-drift`, status `unavailable_until_source_table_has_real_rows`.
- Chart `truth-policy violation counts`: route `/analytics/export-consistency-truth-analytics/charts/truth-policy-violation-counts`, status `unavailable_until_source_table_has_real_rows`.
- Chart `smoke exposure checks`: route `/analytics/export-consistency-truth-analytics/charts/smoke-exposure-checks`, status `unavailable_until_source_table_has_real_rows`.
- Chart `placeholder exposure checks`: route `/analytics/export-consistency-truth-analytics/charts/placeholder-exposure-checks`, status `unavailable_until_source_table_has_real_rows`.
- Chart `fallback event summaries`: route `/analytics/export-consistency-truth-analytics/charts/fallback-event-summaries`, status `unavailable_until_source_table_has_real_rows`.
- Chart `assumption usage summaries`: route `/analytics/export-consistency-truth-analytics/charts/assumption-usage-summaries`, status `unavailable_until_source_table_has_real_rows`.
- Chart `run status truth checks`: route `/analytics/export-consistency-truth-analytics/charts/run-status-truth-checks`, status `unavailable_until_source_table_has_real_rows`.
- Chart `summary-vs-raw contradiction checks`: route `/analytics/export-consistency-truth-analytics/charts/summary-vs-raw-contradiction-checks`, status `unavailable_until_source_table_has_real_rows`.

### Regression / Baseline vs Candidate Analytics

- Route: `/analytics/regression-baseline-vs-candidate-analytics`
- Chart `KPI delta tables`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/kpi-delta-tables`, status `unavailable_until_source_table_has_real_rows`.
- Chart `baseline vs candidate overlays`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/baseline-vs-candidate-overlays`, status `unavailable_until_source_table_has_real_rows`.
- Chart `throughput delta`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/throughput-delta`, status `unavailable_until_source_table_has_real_rows`.
- Chart `BLER delta`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/bler-delta`, status `unavailable_until_source_table_has_real_rows`.
- Chart `BER delta`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/ber-delta`, status `unavailable_until_source_table_has_real_rows`.
- Chart `EVM delta`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/evm-delta`, status `unavailable_until_source_table_has_real_rows`.
- Chart `NMSE delta`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/nmse-delta`, status `unavailable_until_source_table_has_real_rows`.
- Chart `P_FA / P_MD delta`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/p-fa-p-md-delta`, status `unavailable_until_source_table_has_real_rows`.
- Chart `HARQ delta`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/harq-delta`, status `unavailable_until_source_table_has_real_rows`.
- Chart `beam hit/gap delta`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/beam-hit-gap-delta`, status `unavailable_until_source_table_has_real_rows`.
- Chart `latency delta`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/latency-delta`, status `unavailable_until_source_table_has_real_rows`.
- Chart `power / energy delta`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/power-energy-delta`, status `unavailable_until_source_table_has_real_rows`.
- Chart `determinism delta`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/determinism-delta`, status `unavailable_until_source_table_has_real_rows`.
- Chart `schema drift delta`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/schema-drift-delta`, status `unavailable_until_source_table_has_real_rows`.
- Chart `fallback / placeholder / smoke regressions`: route `/analytics/regression-baseline-vs-candidate-analytics/charts/fallback-placeholder-smoke-regressions`, status `unavailable_until_source_table_has_real_rows`.

### Optional 6G Extension Analytics

- Route: `/analytics/optional-6g-extension-analytics`
- Chart `AI inference confidence / latency`: route `/analytics/optional-6g-extension-analytics/charts/ai-inference-confidence-latency`, status `unavailable_until_source_table_has_real_rows`.
- Chart `sensing P_D / P_FA`: route `/analytics/optional-6g-extension-analytics/charts/sensing-p-d-p-fa`, status `unavailable_until_source_table_has_real_rows`.
- Chart `localization RMSE`: route `/analytics/optional-6g-extension-analytics/charts/localization-rmse`, status `unavailable_until_source_table_has_real_rows`.
- Chart `NTN/HAPS/UAV delay and Doppler`: route `/analytics/optional-6g-extension-analytics/charts/ntn-haps-uav-delay-and-doppler`, status `unavailable_until_source_table_has_real_rows`.
- Chart `RIS state summaries`: route `/analytics/optional-6g-extension-analytics/charts/ris-state-summaries`, status `unavailable_until_source_table_has_real_rows`.
- Chart `cell-free / distributed MIMO combining gains`: route `/analytics/optional-6g-extension-analytics/charts/cell-free-distributed-mimo-combining-gains`, status `unavailable_until_source_table_has_real_rows`.
- Chart `sub-THz impairment studies`: route `/analytics/optional-6g-extension-analytics/charts/sub-thz-impairment-studies`, status `unavailable_until_source_table_has_real_rows`.
