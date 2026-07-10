from __future__ import annotations

import re
from typing import Any


BASE_CONTEXT_COLUMNS = """
direction ue_id bs_id sfn slot symbol run_id trial_id run_uuid run_tag scenario_id timestamp_utc
data_origin status value_role value_source value_status finalized_flag partial_row_flag fallback_flag
placeholder_flag config_only_flag cell_id sector_id site_id trp_id link_id carrier_id bwp_id numerology
scs_khz bandwidth_hz center_frequency_hz duplex_mode beam_id layer_id codeword_id harq_process_id rv
channel_name signal_name block_name function_name stage_name metric_name metric_value metric_unit artifact_id
git_sha build_id config_hash seed source_system source_db source_schema source_table source_pk na_reason
""".split()

MANDATORY_CONTEXT_COLUMNS = "direction ue_id bs_id sfn slot symbol".split()
ANALYTICS_CONTEXT_COLUMNS = "formula_id formula valid_sample_count missing_sample_count baseline_run_id candidate_run_id".split()
VALUE_ROLES = "configured resolved applied measured estimated derived aggregated placeholder unavailable fallback_substituted".split()
VALUE_STATUSES = "OK MISSING NOT_AVAILABLE PLACEHOLDER FALLBACK_USED PARTIAL CRASHED UNSUPPORTED REVIEW_REQUIRED".split()

DOMAIN_COLUMNS = {
    "run_overview": "runner_profile run_completion result_ok partial_ok status_authority required_case_count required_failure_count optional_pruned_count failing_case_count active_ue_count bs_count cell_count link_count observed_row_count derived_row_count config_only_row_count placeholder_row_count truth_violation_count fallback_event_count warning_count error_count last_write_timestamp_utc",
    "geometry": "SiteID SectorID TRPID x_m y_m z_m lat lon CoordinateMode MapAnchorLabel indoor_flag o2i_flag los_flag serving_site serving_sector serving_cell_id candidate_cell_id candidate_rank distance_m azimuth_deg elevation_deg aoa_deg aod_deg path_id path_group_id geometry_epoch coverage_score geometry_source_lineage",
    "mobility": "serving_cell_id selected_beam_id speed_mps speed_kmh heading_deg acceleration_mps2 trajectory_id waypoint_id DopplerHz DopplerSourceMode DopplerValueRole EstimatedDopplerHz DopplerError_Hz event_a1_flag event_a2_flag event_a3_flag event_a4_flag event_a5_flag hysteresis_db time_to_trigger_ms handover_candidate_flag selection_metric reselection_metric state_before state_after action_taken reason AccessState CellAcquisitionState control_gating_state",
    "air_interface": "Numerology_mu SCS_kHz SlotDuration_ms SlotsPerFrame SymbolsPerSlot ActiveGridNumRBs ConfiguredGridNumRBs ActiveGridSource ActiveDuplexMode ConfiguredTDDPattern ActiveTDDPattern TDDPatternApplicable fft_size cp_type cp_length sample_rate_hz coreset_id search_space_id ssb_index prach_occasion_id PRBStart PRBCount SymbolStart NumSymbols re_range timing_relation_status timing_estimate_used use_ideal_timing_sync_flag",
    "scheduler_mac": "scheduler_name scheduler_policy scheduler_cycle_id GrantContextId grant_id GrantReason IsRetransmission HarqID NDI RV PRBStart PRBCount AllocatedPRBCount SymbolStart NumSymbols TBSBits TBSBytes MCSIndex Modulation TargetCodeRate ActualMCSSelectionMode CQISource WidebandCQI CQIDerivedMCS CQIDerivedModulation CQIDerivedTargetCodeRate RIUsed PMI CRI RankIndicator RankEstimate QueueBytesBefore QueueBytesAfter queue_packets HOLDelay_ms logical_channel_id qos_class delay_budget_ms bsr_amount sr_state phr_db power_control_command ControlEligible ControlDecodeOk GrantControlState WorkerID HostThreadID CoordinatorState CommitMode GrantWorkerSafe GrantSharedStateCommitMode",
    "harq": "new_tx_or_retx retransmission_attempt_count crc_result ack_nack combining_enabled_flag combining_gain_db residual_bler_estimate soft_buffer_id soft_buffer_bytes harq_rtt_ms harq_state error_reason tb_id",
    "control_phy": "payload_bits payload_length_bits crc_length_bits polar_K polar_E polar_N scrambling_id qam_order coreset_id search_space_id cce_start aggregation_level mapped_re_count dmrs_re_count iq_artifact_id stage_latency_ms stage_status",
    "pdsch": "TBSize_bits TBCRCLength_bits TBLengthWithCRC_bits NumCodeBlocks CodeBlockLength_bits SegmentationOccurred SegmentationPaddingBits BaseGraph EncodedBits RateMatchedBits RateMatchPunctureBits RateMatchRepetitionBits MCSIndex Modulation TargetCodeRate Layers Rank codeword_count PMI CRI ConfiguredBeamSelectionStrategy BeamSelectionStrategy BeamIndexSet AppliedBeamIndexSet AppliedPrecoderPMI AppliedPrecoderPMIType AppliedPrecoderCodebookMode PrecodingNumPorts PrecodingNumLayers PrecodingMatrixRows PrecodingMatrixCols PrecodingActive BeamformingApplied TransformPrecodingApplied ExplicitBeamWeightsApplied dmrs_type dmrs_ports dmrs_symbol_mask ptrs_enabled_flag ptrs_re_count mapped_prb_count mapped_re_count iq_artifact_id resource_grid_artifact_id stage_latency_ms stage_status",
    "pusch": "ul_iq_artifact_id dmrs_sequence_id channel_estimator_type channel_estimate_artifact_id timing_advance_estimate timing_advance_compensation_flag equalizer_type phase_noise_estimation_flag phase_noise_compensation_flag re_demapping_state layer_demapping_state demapper_type descrambling_id uci_on_pusch_present uci_on_pusch_decode_status NumCodeBlocks decoder_iterations harq_combining_enabled harq_combining_gain_db cb_crc_pass_count cb_crc_fail_count tb_crc_pass_flag mac_payload_bits mac_payload_artifact_id LLRMeanAbs LLRStdAbs LLRImbalance stage_latency_ms stage_status",
    "pucch": "RequestedFormat ResolvedFormat FormatAdapted UCIType UCIBitCount PUCCHResourceId PUCCHPRBStart PUCCHPRBCount PUCCHSymbolStart PUCCHNumSymbols ControlResourceSource ExpectedAck ObservedAck PUCCHDecodeOk RuntimeStateUpdated RuntimeStateConsumer StateChangeApplied ControlStage Crash low_papr_sequence_id detector_metric noise_estimate dtx_detection idft_applied_flag blockwise_despreading_flag stage_latency_ms stage_status",
    "prach": "preamble_id root_sequence_index cyclic_shift prach_format prach_occasion_id zc_sequence_artifact_id correlation_artifact_id ifft_artifact_id power_metric noise_floor peak_index peak_value detected_flag false_alarm_flag missed_detection_flag timing_advance_estimate mac_access_state_output stage_latency_ms stage_status",
    "srs": "srs_seq_id port_count comb estimator_type channel_estimate_artifact_id csi_output_artifact_id scheduler_consumed_flag beam_training_consumed_flag stage_latency_ms stage_status",
    "channel": "ChannelModel RequestedChannelModel ObservedChannelModel serving_interferer_role pathloss_db shadowing_db o2i_db delay_spread angle_spread DopplerHz DopplerSourceMode DopplerValueRole EstimatedDopplerHz DopplerError_Hz InjectedCFO_Hz TrueCFO_Hz EstimatedCFO_PreCorrection_Hz EstimatedCFO_Hz ResidualCFO_PostCorrection_Hz CFOError_Hz true_timing_offset estimated_timing_offset residual_timing_offset phase_tracking_error phase_noise iq_imbalance pa_nonlinearity clipping quantization InterferenceMode ResidualInterferencePower_dB InterferenceContributorCount InterferenceAggregatedRxPower_dBm InterferencePowerSource FullInterfererChannelTruthUsed ChannelAgingLoss_dB InterpolationLoss_dB MismatchSensitivity_dB channel_tensor_artifact_id interferer_waveform_artifact_id impairment_order_trace stage_latency_ms stage_status",
    "measurement": "ConfiguredSNR_dB ConfiguredSNRSource SNRValueRole AppliedAWGNSNR_dB DesiredSignalPowerBeforeNoise CompositeSignalPowerBeforeNoise AppliedNoiseSNR_dB NoiseVariance NoiseVarianceSource NoiseVarStatus NoiseVarSource PostEqSINR_dB PostEqSINRSource PostEqSINRValueRole PostEqSINRValueStatus PostEqSINRNAReason PostEqWidebandSINR_dB EVMProxySINR_dB EVMProxySINRSource EVMProxySINRValueRole ReceiverHestSINR_dB ReceiverHestSINRSource ReceiverHestSINRValueStatus ReceiverHestWidebandSINR_dB DecoderTruthProxyWidebandSINR_dB MeasuredTrialSINR_dB MeasuredTrialSINRSource MeasuredTrialSINRValueStatus EstimatedWidebandSINR_dB MeasuredWidebandSINR_dB LargeScaleWidebandSINR_dB LargeScaleSINR_dB LargeScaleSINRSource ServingRSRP_dBm ServingRSRPSource RSRP_dBm RSRPSource CSI_RSRP_dB CSI_RSRPSource AppliedLargeScaleGain_dB AppliedLargeScaleGainSource WidebandSINRSource WidebandSINRValueRole WidebandSINRValueStatus WidebandCQI PMI RI CRI SSBRI RankEstimate measurement_window_id filter_id report_trigger_reason report_status",
    "beam_mimo": "ConfiguredBeamSelectionStrategy BeamSelectionStrategy BeamIndexSet AppliedBeamIndexSet SelectedBeamIndex BestBeamIndex BeamHit TopKBeamHit BeamCandidateCount SelectedBeamGain_dB BestBeamGain_dB BeamGainGap_dB PrecoderSource PrecodingMode PrecodingApplicationStage PrecodingActive BeamformingApplied TransformPrecodingApplied ExplicitBeamWeightsApplied AppliedPrecoderPMI AppliedPrecoderPMIType AppliedPrecoderCodebookMode PrecodingNumPorts PrecodingNumLayers PrecodingMatrixRows PrecodingMatrixCols RankEstimate ConditionNumber_dB user_group_id calibration_flag reciprocity_flag stage_latency_ms stage_status",
    "ue_state": "selected_cell_id selected_beam_id measurement_filtering_state csi_report_generation_state sr_state bsr_state uci_state drx_state ue_tx_power_dbm ue_power_headroom_db ue_battery_state ue_energy_proxy access_state uplink_control_state ue_side_decode_latency_ms ue_side_report_latency_ms",
    "gnb_state": "coordinator_state phy_mac_api_ingress_message_id phy_mac_api_egress_message_id per_slot_orchestration_state thread_id worker_id context_state_before context_state_after api_parse_latency_ms api_generate_latency_ms mailbox_status queue_status",
    "power_energy": "dl_tx_power_dbm ul_tx_power_dbm power_control_command pa_backoff_db rf_chain_power_w digital_baseband_power_w cpu_power_w memory_bandwidth_bytes_s memory_utilization ComputeLatency_ms DecodeLatency_ms AirInterfaceTTI_ms AirInterfaceObservation_ms ProcedureDelay_ms Latency_ms cpu_cycles memory_bytes queue_depth lock_wait_ms contention_count AreaEfficiencyProxy PAPR_dB PeakClippingEvents energy_per_bit_j joules_per_gb cell_energy_efficiency ue_energy_efficiency sleep_state thermal_state throttling_flag",
    "persistence": "sink_type sink_name target_table target_file artifact_path rows_written write_latency_ms retry_count export_lag_ms duplicate_write_flag data_loss_flag browser_surface_name consistency_check_status source_stage_linkage",
    "investigator": "stage_exec_id scalar_value enum_value artifact_logical_path lineage_edge truth_violation_category missing_or_partial_reason conflict_reason coverage_reason rollup_explanation",
}


def _s(slug: str, title: str, domain: str, column_key: str, tables: str, charts: str) -> dict[str, Any]:
    return {"slug": slug, "title": title, "domain": domain, "column_key": column_key, "tables": tables.split(), "charts": [c.strip() for c in charts.split(";") if c.strip()]}


REPORT_SECTIONS = [
    _s("run-trial-scenario-overview", "Run / Trial / Scenario Overview", "run_overview", "run_overview", "live_run_overview live_trial_overview live_scenario_overview live_case_status live_required_vs_optional_case_status live_truth_policy_status", "run health timeline;error/warning/fallback stacked time series;required vs failed case bar chart;truth policy violations by category"),
    _s("scenario-geometry-topology-layout", "Scenario / Geometry / Topology / Layout", "geometry", "geometry", "live_site_table live_sector_table live_trp_table live_cell_table live_ue_table live_link_table live_path_geometry_table live_candidate_cell_table", "BS/sector/UE topology scatter plot;UE trajectory overlay;serving cell map;candidate cell rank heatmap;distance distribution histogram;azimuth/elevation rose plots;path geometry summary charts"),
    _s("mobility-access-cell-selection-reselection-handover", "Mobility / Access / Cell Selection / Reselection / Handover", "mobility", "mobility", "live_mobility_state live_measurement_filter_state live_selection_state live_reselection_state live_handover_state live_event_trigger_table live_access_state", "serving cell timeline;selected beam timeline;mobility event timeline;hysteresis / TTT scatter;access state transition Sankey;Doppler vs speed plot;selection/reselection trigger histogram"),
    _s("air-interface-frame-slot-symbol-grid", "Air Interface / Frame / Slot / Symbol / Grid", "air_interface", "air_interface", "live_carrier_config live_numerology_state live_frame_grid_state live_bwp_state live_coreset_state live_search_space_state live_ssb_occasion_state live_prach_occasion_state live_prb_allocation_snapshot live_re_allocation_snapshot", "frame/slot/symbol occupancy timeline;PRB heatmap;RE occupancy heatmap;DL/UL/guard slot pattern chart;SSB occasion timeline;PRACH occasion timeline;CORESET/search-space occupancy chart"),
    _s("scheduler-mac-queue-qos-power-control-uci-flow", "Scheduler / MAC / Queue / QoS / Power Control / UCI Flow", "scheduler_mac", "scheduler_mac", "live_scheduler_cycle live_dl_scheduler_grants live_ul_scheduler_grants live_queue_state live_buffer_status live_hol_delay_state live_qos_state live_mac_pdu_summary live_power_control_state live_phr_state live_sr_state live_bsr_state live_mac_ce_state", "scheduled PRBs per UE over time;MCS over time;CQI vs selected MCS;queue depth over time;HOL delay over time;scheduler fairness over time;SR/BSR event timeline;power control command timeline;PHR distribution;grant reason distribution"),
    _s("harq-ack-nack-retransmission", "HARQ / ACK-NACK / Retransmission", "harq", "harq", "live_harq_process_table live_harq_timeline live_ack_nack_table live_soft_buffer_table", "HARQ process timeline;RV usage distribution;retransmission count histogram;ACK/NACK timeline;residual BLER by HARQ process;combining gain histogram"),
    _s("dl-control-phy-pdcch", "DL Control PHY - PDCCH", "control_phy", "control_phy", "live_pdcch_stage_table live_pdcch_summary live_pdcch_dmrs_table", "PDCCH stage latency waterfall;aggregation level distribution;CCE usage heatmap;PDCCH DMRS occupancy;PDCCH decode success/failure trend if applicable"),
    _s("ssb-pbch-pss-sss", "SSB / PBCH / PSS / SSS", "control_phy", "control_phy", "live_ssb_stage_table live_pbch_summary live_sync_signal_state", "SSB index timeline;PBCH stage latency;SSB/PBCH occupancy map;sync success/failure timeline if available"),
    _s("csi-rs", "CSI-RS", "control_phy", "control_phy", "live_csirs_stage_table live_csirs_resource_table", "CSI-RS resource occupancy;port usage chart;CSI-RS latency trend"),
    _s("pdsch-dl-data-chain", "PDSCH / DL Data Chain", "pdsch", "pdsch", "live_pdsch_stage_table live_pdsch_transport_block_table live_pdsch_code_block_table live_pdsch_mapping_table live_pdsch_dmrs_ptrs_table", "TB size over time;MCS/code-rate timeline;code-block count histogram;LDPC stage latency waterfall;DMRS/PTRS occupancy plot;precoder / beam selection timeline;DL resource-grid heatmap"),
    _s("pusch-ul-data-chain", "PUSCH / UL Data Chain", "pusch", "pusch", "live_pusch_stage_table live_pusch_rx_summary live_ul_dmrs_table live_llr_summary live_decoder_summary", "channel estimation latency;equalizer latency;decoder iteration histogram;TA estimate timeline;LLR statistics over time;UL resource-grid / equalized symbol summaries"),
    _s("pucch-f0-f1-f2-f3-f4", "PUCCH F0 / F1 / F2 / F3 / F4", "pucch", "pucch", "live_pucch_summary live_pucch_f0_table live_pucch_f1_table live_pucch_f2_table live_pucch_f3_table live_pucch_f4_table live_uci_table", "requested vs resolved format confusion matrix;PUCCH decode success/failure trend;ACK/NACK match chart;DTX detection chart;per-format latency histograms;crash/error timeline;UCI bit count distribution"),
    _s("prach-random-access", "PRACH / Random Access", "prach", "prach", "live_prach_stage_table live_prach_detection_table live_random_access_state", "PRACH peak search timeline;noise floor trend;peak value histogram;preamble usage chart;TA estimate trend;access attempt/success timeline"),
    _s("srs-ul-sounding-massive-mimo-inputs", "SRS / UL Sounding / Massive MIMO Inputs", "srs", "srs", "live_srs_stage_table live_srs_channel_estimation_table live_csi_output_table", "SRS validity timeline;channel estimate quality trend;SRS consumption by scheduler/beam module"),
    _s("channel-interference-impairments", "Channel / Interference / Impairments", "channel", "channel", "live_channel_realization_table live_interference_table live_impairment_table live_tracking_table", "channel quality timeline;CFO true vs estimated vs residual;timing offset true vs estimated vs residual;pathloss/shadowing distributions;interference power timeline;impairment contribution bar chart;channel heatmap artifact links"),
    _s("measurements-csi-link-adaptation-inputs", "Measurements / CSI / Link Adaptation Inputs", "measurement", "measurement", "live_measurement_table live_csi_feedback_table live_link_adaptation_input_table", "applied vs measured runtime SNR/SINR comparison;RSRP/CSI-RSRP timeline;CQI / PMI / RI / CRI timeline;measurement source coverage chart;config-vs-measured conflict dashboard"),
    _s("beamforming-precoding-mimo-massive-mimo", "Beamforming / Precoding / MIMO / Massive MIMO", "beam_mimo", "beam_mimo", "live_beam_selection_table live_precoder_table live_combiner_table live_mimo_state_table live_user_grouping_table", "selected vs best beam timeline;beam gain gap histogram;beam hit rate timeline;rank distribution;condition number distribution;MU grouping summary;precoder mode distribution"),
    _s("ue-side-state-ue-power-ue-control", "UE-Side State / UE Power / UE Control", "ue_state", "ue_state", "live_ue_state_table live_ue_measurement_state live_ue_control_state live_ue_power_state live_drx_state", "UE Tx power timeline;UE power headroom timeline;UE control/report timeline;DRX state timeline;UE energy proxy timeline"),
    _s("gnb-side-state-thread-coordinator-phy-mac-api", "gNB-Side State / Thread / Coordinator / PHY-MAC API", "gnb_state", "gnb_state", "live_gnb_state_table live_per_cell_context live_per_ue_context live_phy_mac_api_table live_thread_orchestration_table", "per-cell context health timeline;API message rate;orchestration latency chart;per-worker workload chart"),
    _s("power-energy-thermal-compute-runtime", "Power / Energy / Thermal / Compute / Runtime", "power_energy", "power_energy", "live_power_runtime_table live_rf_power_table live_bb_power_table live_energy_efficiency_table live_sleep_state_table", "TX power timeline per cell;TX power timeline per UE;power vs throughput;power vs BLER;energy per bit over time;joules/GB over time;CPU cycles and memory usage time series;latency breakdown stacked chart;PAPR distribution;sleep-state timeline;efficiency scatter plots"),
    _s("persistence-export-consistency-browser-health", "Persistence / Export / Consistency / Browser Health", "persistence", "persistence", "live_db_write_table live_csv_write_table live_artifact_write_table live_browser_surface_integrity_table live_consistency_check_table", "DB write latency over time;export lag over time;duplicate write count trend;consistency failure trend;artifact creation rate"),
    _s("fixed-snr-sinr-sweep-validation", "Fixed SNR / SINR Sweep", "measurement", "measurement", "fixed_snr_sweep_audit fixed_snr_sweep_curve_summary dl_fixed_snr_bler_curve ul_fixed_snr_bler_curve", "dl_bler_vs_snr;ul_bler_vs_snr;dl_ber_vs_snr;ul_ber_vs_snr;throughput_vs_snr;measured_sinr_vs_configured_snr"),
    _s("geometry-mobility-validation", "Geometry / Mobility", "mobility", "mobility", "geometry_runtime_audit trajectory_geometry doppler_reconciliation", "topology_map;ue_trajectory_xy;doppler_vs_slot;measured_sinr_vs_slot"),
    _s("artifact-audit-validation", "Artifact Audit", "persistence", "persistence", "all_csv_artifact_audit all_image_artifact_audit", ""),
    _s("generic-investigator-views", "Generic Investigator Views", "investigator", "investigator", "reports_all_stage_exec_v reports_all_scalars_v reports_all_enums_v reports_all_artifacts_v reports_stage_lineage_v reports_truth_violations_v reports_partial_or_missing_v reports_config_vs_measured_conflicts_v reports_value_semantics_coverage_v reports_status_rollup_explanations_v", "investigator stage lineage graph;truth violation rollup;partial or missing data dashboard;config vs measured conflict dashboard;value semantics coverage chart"),
]

ANALYTICS_SECTIONS = [
    _s("waveform-time-domain-analytics", "Waveform / Time Domain Analytics", "waveform", "air_interface", "waveform_analytics waveform_comparison_analytics waveform_stage_overlay_analytics", "Tx waveform;Rx waveform;pre-channel waveform;post-channel waveform;post-impairment waveform;magnitude vs sample;phase vs sample;power vs sample;stage overlay plots;UE-wise / link-wise waveform comparison"),
    _s("spectrum-psd-papr-analytics", "Spectrum / PSD / PAPR Analytics", "spectrum", "power_energy", "spectrum_analytics papr_analytics clipping_analytics", "PSD;occupied bandwidth;out-of-band spectral summaries if measurable;PAPR histogram / CDF;clipping event histogram;power spectral comparison before/after impairment"),
    _s("constellation-evm-analytics", "Constellation / EVM Analytics", "constellation", "pusch", "constellation_analytics evm_analytics", "pre-equalization constellation;post-equalization constellation;constellation per layer;constellation per codeword;constellation per modulation order;EVM RMS;EVM per symbol;EVM per subcarrier;EVM per layer;symbol decision error histogram"),
    _s("resource-grid-re-occupancy-analytics", "Resource Grid / RE Occupancy Analytics", "resource_grid", "air_interface", "resource_grid_analytics re_collision_analytics", "RE occupancy heatmap;PRB heatmap;PDCCH map;PBCH/SSB map;CSI-RS map;PDSCH map;PUSCH map;PUCCH map;PRACH opportunity map;SRS map;DMRS/PTRS occupancy map;RE collision heatmap / table"),
    _s("channel-estimation-propagation-analytics", "Channel Estimation / Propagation Analytics", "channel", "channel", "channel_estimation_analytics channel_quality_analytics propagation_analytics", "true H(tau) if available;estimated Hhat(tau);channel impulse response;true H(f) if available;estimated Hhat(f);channel magnitude heatmap;channel phase heatmap;tap power profile;delay spread chart;angle spread chart;pathloss distribution;shadowing distribution;O2I distribution;noise variance trend;NMSE vs SNR / SINR;estimator bias / variance summaries;serving vs interferer decomposition"),
    _s("detection-control-analytics", "Detection / Control Analytics", "control", "control_phy", "detection_analytics control_decode_analytics random_access_detection_analytics", "P_FA;FAR;P_MD;P_D;PRACH correlation peak distributions;PRACH noise floor distributions;PRACH peak search results;SSB detection statistics;PUCCH DTX statistics;control decode success/failure tables;threshold sweep plots if data exists;PBCH/PDCCH/PUCCH detection and decode timelines"),
    _s("error-reliability-analytics", "Error / Reliability Analytics", "reliability", "harq", "error_rate_analytics decoder_analytics codeblock_analytics", "BER;BLER;FER;CRC pass/fail rates;code-block error rates;CBG error rates;residual BLER after HARQ;decoder iteration distributions;per-channel reliability breakdown;per-format reliability breakdown;per-UE and per-cell reliability;BLER vs SNR;BLER vs SINR;BLER vs MCS;BER vs SNR;FER vs SNR"),
    _s("throughput-goodput-spectral-efficiency-analytics", "Throughput / Goodput / Spectral Efficiency Analytics", "throughput", "scheduler_mac", "throughput_analytics goodput_analytics spectral_efficiency_analytics fairness_analytics", "throughput;offered throughput;goodput;spectral efficiency;throughput over time;goodput over time;throughput vs SNR;throughput vs SINR;throughput vs load;goodput vs retransmissions;per-UE throughput;per-cell throughput;throughput percentile plots;throughput CDF;fairness index trend"),
    _s("measurement-csi-link-adaptation-analytics", "Measurement / CSI / Link Adaptation Analytics", "measurement", "measurement", "measurement_feedback_analytics link_adaptation_analytics cqi_mcs_consistency_analytics", "applied AWGN SNR vs measured runtime SINR comparison;ServingRSRP / RSRP / CSI-RSRP trends;CQI / PMI / RI / CRI / SSBRI trends;CQI-to-MCS mapping plot;selected MCS distribution;selected vs derived MCS confusion matrix;quality-vs-selected-MCS mismatch plot;per-beam quality plot;per-layer quality plot;config-vs-measured conflict dashboard"),
    _s("harq-analytics", "HARQ Analytics", "harq", "harq", "harq_analytics harq_process_analytics soft_buffer_analytics", "HARQ process timeline;retransmission count histogram;retransmission rate trend;HARQ RTT distribution;HARQ combining gain distribution;newTx vs retx comparison;residual failure patterns"),
    _s("beamforming-precoding-mimo-analytics", "Beamforming / Precoding / MIMO Analytics", "beam_mimo", "beam_mimo", "beam_analytics mimo_analytics user_grouping_analytics precoder_analytics", "antenna element layout;antenna radiation pattern;beam pattern 3d;beam id timeline;beam pair timeline;selected vs best beam gap;beam hit rate / top-K hit rate;beam gain gap histogram;precoder mode distribution;combiner summary;rank distribution;per-layer SINR;inter-user leakage;MU grouping analytics;condition number distribution;calibration / reciprocity diagnostics if modeled"),
    _s("mobility-selection-reselection-handover-analytics", "Mobility / Selection / Reselection / Handover Analytics", "mobility", "mobility", "mobility_analytics selection_reselection_analytics handover_analytics", "UE trajectory views;serving cell timeline;neighbor ranking timeline;selection/reselection trigger tables;hysteresis / TTT studies;mobility robustness summaries;access delay vs mobility;measurement filtering analytics;handover event timeline"),
    _s("random-access-prach-analytics", "Random Access / PRACH Analytics", "random_access", "prach", "random_access_analytics prach_analytics", "detection rate;false alarm rate;missed detection rate;access latency;retry count distribution;timing advance distribution;preamble/root/cyclic-shift usage summary;collision summary if modeled"),
    _s("impairments-tracking-analytics", "Impairments / Tracking Analytics", "impairments", "channel", "impairment_analytics tracking_analytics", "CFO true vs estimated vs residual;timing offset true vs estimated vs residual;phase noise summary;IQ imbalance summary;PA nonlinearity summary;clipping summary;quantization summary;impairment order trace;contribution decomposition if measurable"),
    _s("power-energy-efficiency-analytics", "Power / Energy / Efficiency Analytics", "power_energy", "power_energy", "power_analytics energy_efficiency_analytics runtime_power_analytics sleep_state_analytics", "DL Tx power per cell / beam / UE;UL Tx power per UE;power control behavior;PA backoff distribution;RF chain power;baseband power;CPU power if available;power vs throughput;power vs BLER;active bandwidth vs power;active rank vs power;energy/bit;energy per bit histogram;joules/GB;energy efficiency by UE;energy efficiency by cell;sleep/idle/active state occupancy;PAPR vs power;thermal/throttling analytics if available"),
    _s("runtime-compute-complexity-parallelism-analytics", "Runtime / Compute / Complexity / Parallelism Analytics", "runtime", "power_energy", "compute_analytics runtime_latency_analytics determinism_analytics parallelism_analytics", "block execution time;stage latency;end-to-end latency;latency CDF;compute latency;decode latency;CPU cycles;memory usage;worker timelines;lock/contention observations;DB write latency;export lag;single-thread vs multi-thread determinism;dropped row / duplicate write analytics;decoder complexity units;normalized decoder complexity"),
    _s("export-consistency-truth-analytics", "Export / Consistency / Truth Analytics", "export_consistency", "persistence", "export_consistency_analytics truth_policy_analytics schema_drift_analytics", "CSV vs DB consistency;DB vs browser consistency;source row count vs analytics row count;missing-field audits;schema drift;config drift;truth-policy violation counts;smoke exposure checks;placeholder exposure checks;fallback event summaries;assumption usage summaries;run status truth checks;summary-vs-raw contradiction checks"),
    _s("regression-baseline-vs-candidate-analytics", "Regression / Baseline vs Candidate Analytics", "regression", "persistence", "regression_analytics regression_baseline_view regression_candidate_view regression_delta_view change_impact_analytics", "KPI delta tables;baseline vs candidate overlays;throughput delta;BLER delta;BER delta;EVM delta;NMSE delta;P_FA / P_MD delta;HARQ delta;beam hit/gap delta;latency delta;power / energy delta;determinism delta;schema drift delta;fallback / placeholder / smoke regressions"),
    _s("optional-6g-extension-analytics", "Optional 6G Extension Analytics", "optional_6g", "investigator", "ai_inference_analytics sensing_analytics localization_analytics ntn_haps_uav_analytics ris_analytics cell_free_mimo_analytics sub_thz_impairment_analytics", "AI inference confidence / latency;sensing P_D / P_FA;localization RMSE;NTN/HAPS/UAV delay and Doppler;RIS state summaries;cell-free / distributed MIMO combining gains;sub-THz impairment studies"),
]


def _unique(items: list[str]) -> list[str]:
    out: list[str] = []
    for item in items:
        if item not in out:
            out.append(item)
    return out


def _view_name(kind: str, slug: str) -> str:
    return f"{kind}_{re.sub(r'[^a-z0-9]+', '_', slug.lower()).strip('_')}_v"


def _sections(kind: str) -> list[dict[str, Any]]:
    return REPORT_SECTIONS if kind == "reports" else ANALYTICS_SECTIONS


def iter_table_specs(kind: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for section in _sections(kind):
        columns = _unique(BASE_CONTEXT_COLUMNS + (ANALYTICS_CONTEXT_COLUMNS if kind == "analytics" else []) + DOMAIN_COLUMNS.get(section["column_key"], "").split())
        for table in section["tables"]:
            rows.append({
                "kind": kind,
                "section_slug": section["slug"],
                "section_title": section["title"],
                "domain": section["domain"],
                "table_name": table,
                "mysql_view_name": table if table.endswith("_v") else f"{table}_v",
                "section_view_name": _view_name(kind, section["slug"]),
                "route": f"/{kind}/{section['slug']}/tables/{table}",
                "logical_path": f"{kind}/csv/{table}.csv",
                "required_columns": columns,
                "mandatory_context_columns": list(MANDATORY_CONTEXT_COLUMNS),
                "value_roles": list(VALUE_ROLES),
                "value_statuses": list(VALUE_STATUSES),
                "lineage_required": True,
                "smoke_visible_default": False,
                "placeholder_flag_default": False,
                "fallback_flag_default": False,
                "default_status": "unavailable_until_canonical_artifact_or_db_view_exists",
                "value_definition": f"{section['title']} canonical fact table: {table}.",
            })
    return rows


def iter_chart_specs(kind: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for section in _sections(kind):
        for chart in section["charts"]:
            chart_slug = re.sub(r"[^a-z0-9]+", "-", chart.lower()).strip("-")
            rows.append({
                "kind": kind,
                "section_slug": section["slug"],
                "section_title": section["title"],
                "domain": section["domain"],
                "chart_name": chart,
                "route": f"/{kind}/{section['slug']}/charts/{chart_slug}",
                "requires_real_data": True,
                "lineage_required": True,
                "artifact_id_required_when_generated": True,
                "placeholder_chart_allowed": False,
                "smoke_visible_default": False,
                "default_status": "unavailable_until_source_table_has_real_rows",
            })
    return rows


def route_map(kind: str) -> dict[str, str]:
    return {f"/{kind}": kind} | {f"/{kind}/{section['slug']}": kind for section in _sections(kind)}


def section_by_slug(kind: str, slug: str | None) -> dict[str, Any] | None:
    for section in _sections(kind):
        if section["slug"] == slug:
            return section
    return None


def product_sections_payload(kind: str) -> list[dict[str, Any]]:
    table_specs = iter_table_specs(kind)
    chart_specs = iter_chart_specs(kind)
    payload: list[dict[str, Any]] = []
    for section in _sections(kind):
        payload.append({
            **section,
            "href": f"/{kind}/{section['slug']}",
            "tables": [row for row in table_specs if row["section_slug"] == section["slug"]],
            "charts": [row for row in chart_specs if row["section_slug"] == section["slug"]],
        })
    return payload
