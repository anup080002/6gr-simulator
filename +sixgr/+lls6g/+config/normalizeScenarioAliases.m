function cfg = normalizeScenarioAliases(cfg, varargin)
%NORMALIZESCENARIOALIASES Synchronize extended top-level 6G sections with legacy runtime sections.

ip = inputParser;
ip.addRequired("cfg", @(x)builtin("isstruct", x) && isscalar(x));
ip.addParameter("SourceFiles", strings(0,1), @(x)isstring(x) || iscellstr(x) || ischar(x));
ip.addParameter("ConfigPath", "", @(x)ischar(x) || isstring(x));
ip.parse(cfg, varargin{:});
opt = ip.Results;

newBase = localNewDefaults();
oldBase = localLegacyDefaults();

cfg = localEnsureConfigInheritance(cfg, string(opt.SourceFiles(:)), string(opt.ConfigPath));
cfg = localEnsureScenarioSchemaVersion(cfg);
cfg = localExpandCanonicalControl(cfg, sixgr.util.mergeStruct(newBase, oldBase));

cfg = localSyncValue(cfg, newBase, oldBase, "meta.scenario_id", "meta.scenario_id", "identity");
cfg = localSyncMetadataAlias(cfg, "meta.scenario_name", "meta.description");
cfg = localSyncValue(cfg, newBase, oldBase, "meta.scenario_family", "meta.scenario_group", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "meta.author", "meta.owner", "identity");
cfg = localSyncMetadataAlias(cfg, "meta.study_status", "meta.maturity_tag");
cfg = localSyncValue(cfg, newBase, oldBase, "run_control.seed", "simulation.random_seed", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "run_control.deterministic_mode", "simulation.deterministic_mode", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "run_control.time_profiling_enable", "output.profiler_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "analytics.export_time_profile", "output.profiler_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.carrier_frequency_hz", "frequency.center_frequency_hz", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.frequency_range_label", "frequency.range_name", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.channel_bandwidth_hz", "frequency.bandwidth_hz", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.simulation_bandwidth_hz", "frequency.bandwidth_hz", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.duplex_mode", "frequency.duplex_mode", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.scs_hz", "frame.scs_khz", "hz_to_khz");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.cp_type", "frame.cp_type", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.sample_rate_hz", "waveform.sample_rate_hz", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.fft_size", "waveform.fft_size", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "frame_timing.tdd_pattern", "frame.tdd_pattern", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "frame_timing.special_slot_downlink_symbols", "frame.special_slot_downlink_symbols", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "frame_timing.ul_dl_guard_symbols", "frame.ul_dl_guard_symbols", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "frame_timing.special_slot_uplink_symbols", "frame.special_slot_uplink_symbols", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "deployment_topology.num_ues", "users.n_users", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "deployment_topology.inter_site_distance_m", "deployment_topology.inter_site_distance", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "deployment_topology.sector_azimuth_offsets_deg", "deployment_topology.sector_azimuths_deg", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.ue.distribution.indoor_fraction", "deployment_topology.indoor_ue_fraction", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.ue.distribution.min_bs_dist_m", "deployment_topology.min_ue_distance_from_bs_m", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.ue.distribution.max_bs_dist_m", "deployment_topology.max_ue_distance_from_bs_m", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.ue.distribution.indoor_fraction", "scenario.ue.indoorFraction", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "mobility.ue_speed_kmh", "channels.mobility_kmph", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.mobility.speed_kmh", "mobility.ue_speed_kmh", "first_numeric");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.mobility.model", "mobility.trajectory_model", "mobility_model");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.mobility.update_period_s", "mobility.update_period_s", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "mobility.spatial_consistency_flag", "channels.spatial_consistency_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "antenna_and_array.bs_num_antenna_elements", "mimo.n_tx_ant", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "antenna_and_array.ue_num_antenna_elements", "mimo.n_rx_ant", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.bs.nTxAnt", "mimo.n_tx_ant", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.ue.nRxAnt", "mimo.n_rx_ant", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.bs.antenna.n_elements", "antenna_and_array.bs_num_antenna_elements", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.ue.nRxAnt", "antenna_and_array.ue_num_antenna_elements", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.bs.downtilt_deg", "antenna_and_array.bs_mechanical_tilt_deg", "negative_tilt");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.bs.antenna.type", "antenna_and_array.bs_array_geometry", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.ue.antenna.type", "antenna_and_array.ue_array_geometry", "ue_array_geometry");
cfg = localSyncAntennaElementSpacing(cfg, newBase, oldBase);
cfg = localSyncValue(cfg, newBase, oldBase, "antenna_and_array.digital_precoder_family", "mimo.precoder_type", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.bs.txPower_dBm", "power_and_rf_frontend.bs_tx_power_dbm", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "air_interface.bs_tx_power_per_sector_dBm", "power_and_rf_frontend.bs_tx_power_dbm", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.ue.txPower_dBm", "power_and_rf_frontend.ue_tx_power_dbm", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "air_interface.ue_tx_power_dBm", "power_and_rf_frontend.ue_tx_power_dbm", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.ue.noiseFigure_dB", "power_and_rf_frontend.ue_noise_figure_db", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "air_interface.ue_noise_figure_dB", "power_and_rf_frontend.ue_noise_figure_db", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "scenario.bs.noiseFigure_dB", "power_and_rf_frontend.bs_noise_figure_db", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "air_interface.bs_noise_figure_dB", "power_and_rf_frontend.bs_noise_figure_db", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "power_and_rf_frontend.bs_tx_power_dbm", "energy_efficiency.tx_power_dbm", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "waveform.dl_waveform", "waveform.dl_waveform", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "waveform.ul_waveform", "waveform.ul_waveform", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "waveform.ul_waveform_dft_s_ofdm_enable", "waveform.transform_precoding_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "waveform.transform_precoding", "waveform.transform_precoding_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "waveform.windowing", "waveform.windowing_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "waveform.windowing_percent", "waveform.windowing_percent", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "channel_model.model_family", "channels.model_type", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "channel_model.scenario_label", "channels.profile", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "channel_model.delay_spread_ns", "channels.delay_spread_ns", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "channel_model.doppler_hz", "channels.doppler_hz", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "channel_model.doppler_source_mode", "channels.doppler_source_mode", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "channels.carrier_frequency_hz", "frequency.center_frequency_hz", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "channels.pathloss_scenario", "deployment_topology.cell_type", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "channels.max_doppler_hz", "channels.doppler_hz", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "channels.o2i_loss_model", "channels.o2i_model", "o2i_model");
  cfg = localSyncValue(cfg, newBase, oldBase, "channels.o2i_loss_db", "channels.o2i_loss_db", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo_and_beam_management.beam_sweeping", "mimo.beam_sweep_enabled", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo_and_beam_management.rank_set", "mimo.n_layers", "first_numeric");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo_and_beam_management.codebook_family", "mimo.codebook_type", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo_and_beam_management.mtrp_coordination", "mimo.mtrp_ready", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo.beam_management_enable", "mimo.beam_sweep_enabled", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo.beam_codebook_type", "mimo.codebook_type", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo.beam_codebook_size_dl", "system.beam.numBeams", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo.beam_update_period_ms", "system.beam.updatePeriod_ms", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo.digital_precoder_family", "mimo.precoder_type", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo.max_dl_layers", "mimo.n_layers", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo.max_simultaneous_ue_dl", "system.scheduler.maxActiveUEsPerCellPerSlotDL", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo.max_simultaneous_ue_ul", "system.scheduler.maxActiveUEsPerCellPerSlotUL", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "scheduler.type", "system.scheduler.type", "scheduler_type");
  cfg = localSyncValue(cfg, newBase, oldBase, "scheduler.dl_max_ues_per_slot", "system.scheduler.maxActiveUEsPerCellPerSlotDL", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "scheduler.ul_max_ues_per_slot", "system.scheduler.maxActiveUEsPerCellPerSlotUL", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "scheduler.max_prbs_per_grant", "system.scheduler.maxPRBAllocationPerUE", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "scheduler.pf_alpha", "system.scheduler.fairnessAlpha", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.cqi_policy", "reference_signals.cqi_reporting_enabled", "policy_to_bool");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.pmi_policy", "reference_signals.pmi_reporting_enabled", "policy_to_bool");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.ri_policy", "reference_signals.ri_reporting_enabled", "policy_to_bool");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.cri_policy", "reference_signals.cri_reporting_enabled", "policy_to_bool");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.channel_state_information_mode", "reference_signals.csi_feedback_mode", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.dl_csi_mode", "reference_signals.csi_feedback_mode", "csi_mode");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.csi_report_type", "reference_signals.csi_feedback_mode", "csi_report_type");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.csi_report_periodicity_slots", "reference_signals.csi_report_periodicity_slots", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.csi_reporting_delay_slots", "reference_signals.csi_reporting_delay_slots", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.cqi_table", "reference_signals.cqi_table", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.pmi_codebook_mode", "reference_signals.pmi_codebook_mode", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.dl_csi_enabled", "reference_signals.csi_reporting_enabled", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "channel_coding.data_channel_family", "coding.data_code_type", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "channel_coding.control_channel_family", "coding.control_code_type", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "channel_coding.ldpc_base_graph", "coding.base_graph", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "coding.dl_coding_scheme", "coding.data_code_type", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "coding.control_coding_scheme", "coding.control_code_type", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "coding.ldpc_max_iterations", "receiver_algorithms.decoder_iterations", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "modulation.dl_max_modulation", "modulation.dl_modulation_order", "modulation_to_order");
cfg = localSyncValue(cfg, newBase, oldBase, "modulation.ul_max_modulation", "modulation.ul_modulation_order", "modulation_to_order");
cfg = localSyncValue(cfg, newBase, oldBase, "modulation.dl_mcs_table", "modulation.mcs_table", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "modulation.cqi_table", "reference_signals.cqi_table", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "modulation.pi2_bpsk_enable", "modulation.pi2_bpsk_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "modulation.constellation_shaping_enable", "modulation.constellation_shaping_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "modulation_and_mapping.dl_max_modulation", "modulation.dl_modulation_order", "modulation_to_order");
cfg = localSyncValue(cfg, newBase, oldBase, "modulation_and_mapping.ul_max_modulation", "modulation.ul_modulation_order", "modulation_to_order");
cfg = localSyncValue(cfg, newBase, oldBase, "modulation_and_mapping.dl_mcs_table", "modulation.mcs_table", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "modulation_and_mapping.ul_mcs_table", "modulation.mcs_table", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "modulation_and_mapping.mcs_table", "modulation.mcs_table", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "modulation_and_mapping.dl_mcs_index", "modulation.dl_mcs_index", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "modulation_and_mapping.ul_mcs_index", "modulation.ul_mcs_index", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "modulation_and_mapping.cqi_table", "reference_signals.cqi_table", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "harq.enabled", "harq.enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "harq.enable", "harq.enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "harq.process_count", "harq.process_count", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "harq.n_harq_processes_dl", "harq.process_count", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "harq.rv_sequence", "harq.rv_sequence", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "harq.combining_mode", "harq.combining_mode", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "harq.combining_type", "harq.combining_mode", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "harq.max_retransmissions", "harq.max_retx", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "harq.k1", "harq.feedback_timing_slots", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "harq.k2", "harq.k2", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "ai_ml.enabled", "ai_ml.enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "ai_ml.use_case", "ai_ml.use_case", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "ai_ml.model_name", "ai_ml.model_id", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "ai_ml.fallback_mode", "ai_ml.fallback_enabled", "string_to_bool");
cfg = localSyncValue(cfg, newBase, oldBase, "energy_and_complexity.throughput_per_watt", "kpis.energy_per_bit", "bool_to_metric");
cfg = localSyncValue(cfg, newBase, oldBase, "energy_efficiency.enable", "kpis.energy_per_bit", "bool_to_metric");
cfg = localSyncValue(cfg, newBase, oldBase, "kpi_spec.mandatory_kpis", "kpis", "kpi_list_to_struct");
cfg = localSyncValue(cfg, newBase, oldBase, "output_control.save_intermediate", "logging.save_intermediate", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "output_control.save_plots", "output.save_figures", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "output_control.save_plots", "output.save_png", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "output_control.save_resolved_config", "output.save_yaml_snapshot", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "output_control.save_resolved_config", "output.save_json_snapshot", "identity");
if isempty(sixgr.util.structGet(cfg, "run.controlGating.preAttachUEsBeforeMeasurement", []))
    cfg = sixgr.util.structSet(cfg, "run.controlGating.preAttachUEsBeforeMeasurement", false);
end
if isempty(sixgr.util.structGet(cfg, "control_gating.pre_attach_ues_before_measurement", []))
    cfg = sixgr.util.structSet(cfg, "control_gating.pre_attach_ues_before_measurement", ...
        logical(sixgr.util.structGet(cfg, "run.controlGating.preAttachUEsBeforeMeasurement", false)));
end

cfg = localSyncNestedFlag(cfg, newBase, oldBase, "signals_and_channels_common.ssb.enable_flag", "reference_signals.ssb_enabled");
cfg = localSyncNestedFlag(cfg, newBase, oldBase, "signals_and_channels_common.pbch.enable_flag", "reference_signals.pbch_enabled");
cfg = localSyncNestedFlag(cfg, newBase, oldBase, "reference_signals.pdcch_dmrs.enabled", "reference_signals.pdcch_dmrs_enabled");
cfg = localSyncNestedFlag(cfg, newBase, oldBase, "reference_signals.nzp_csi_rs.enabled", "reference_signals.csi_rs_enabled");
cfg = localSyncNestedFlag(cfg, newBase, oldBase, "reference_signals.srs.enabled", "reference_signals.srs_enabled");
cfg = localSyncNestedFlag(cfg, newBase, oldBase, "reference_signals.trs.enabled", "reference_signals.trs_enabled");
cfg = localSyncNestedFlag(cfg, newBase, oldBase, "reference_signals.tracking_rs.enabled", "reference_signals.tracking_rs_enabled");
cfg = localSyncNestedFlag(cfg, newBase, oldBase, "reference_signals.ptrs.enabled", "reference_signals.ptrs_enabled");
cfg = localSyncValue(cfg, newBase, oldBase, "reference_signals.ssb_Lmax", "reference_signals.ssb_lmax", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "reference_signals.ssb_beam_count", "reference_signals.ssb_beam_count", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "reference_signals.csi_rs_port_count", "reference_signals.csi_rs_ports", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "reference_signals.csi_rs_periodicity_ms", "reference_signals.csi_rs_periodicity_ms", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "reference_signals.trs_periodicity_ms", "reference_signals.trs_periodicity_ms", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "reference_signals.pdsch_dmrs.num_ports", "reference_signals.pdsch_dmrs_ports", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "reference_signals.pusch_dmrs.num_ports", "reference_signals.pusch_dmrs_ports", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "reference_signals.srs.num_ports", "reference_signals.srs_ports", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "reference_signals.srs.sequence_type", "reference_signals.srs_sequence_family", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "reference_signals.srs.periodicity", "reference_signals.srs_periodicity_ms", "numeric_string");
cfg = localSyncValue(cfg, newBase, oldBase, "pdcch.enabled", "control.pdcch_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "pdcch.coreset_duration_symbols", "control.coreset_duration", "identity");
cfg = localApplyPDCCHCoresetBandwidthAlias(cfg);
cfg = localSyncValue(cfg, newBase, oldBase, "pdcch.aggregation_levels", "control.aggregation_levels", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "pdcch.search_space_type", "control.search_space_type", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "pdcch.dci_format_dl", "control.dci_formats", "single_to_cell");
cfg = localSyncValue(cfg, newBase, oldBase, "pucch.enabled", "control.pucch_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.enabled", "random_access.enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.enable", "random_access.enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.configuration_index", "random_access.configuration_index", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.format", "random_access.prach_format", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.subcarrier_spacing_khz", "random_access.subcarrier_spacing_khz", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.zero_correlation_zone", "random_access.zero_correlation_zone", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.root_sequence_index", "random_access.root_sequence_index", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.preamble_count", "random_access.preamble_count", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.msg3_enabled", "random_access.msg3_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.detection_threshold_mode", "random_access.detection_threshold_mode", "threshold_mode");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.false_alarm_candidate_scope", "random_access.false_alarm_candidate_scope", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.sequence_family", "random_access.prach_sequence_family", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.format_set", "random_access.prach_format", "first_string");
cfg = localSyncValue(cfg, newBase, oldBase, "traffic.flow_direction", "traffic.flowDirection", "direction_token");
cfg = localSyncValue(cfg, newBase, oldBase, "traffic.dl_load_fraction", "traffic.dlRatio", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "traffic.ul_load_fraction", "traffic.ulRatio", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "traffic.packet_delay_budget_ms", "traffic.packetDelayBudget_ms", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "traffic.target_rate_mbps", "traffic.targetRate_Mbps", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "traffic.packet_size_bytes", "traffic.packetSize_bytes", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "power_control.ue_max_power_dBm", "power_and_rf_frontend.ue_tx_power_dbm", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "power_control.pcmax_dBm", "power_and_rf_frontend.ue_max_power_dbm", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "impairments.cfo_enabled", "impairments.cfo.enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "impairments.cfo_max_hz", "impairments.cfo.value_hz", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "impairments.timing_offset_enabled", "impairments.to.enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "impairments.timing_offset_max_samples", "impairments.to.value_samples", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "impairments.phase_noise_enabled", "impairments.phase_noise.enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "impairments.phase_noise_model", "impairments.phase_noise.model", "identity");
cfg = localPreferModernRuntimeValue(cfg, "simulation.monte_carlo_iterations", "run.monte_carlo_iterations", "identity");
cfg = localApplyBrowserOverlayDurationAliases(cfg, string(opt.SourceFiles(:)), string(opt.ConfigPath));
cfg = localNormalizeFixedLinkCalibrationMode(cfg);
cfg = localNormalizeFixedSNRSweepRunClass(cfg);
cfg = localApplyDerivedRadioAliases(cfg, newBase);
end

function cfg = localExpandCanonicalControl(cfg, newBase)
if ~isfield(cfg, "canonical_control") || ~isstruct(cfg.canonical_control) || ~isscalar(cfg.canonical_control)
    return;
end

cfg = sixgr.util.mergeStruct(newBase, cfg);
control = cfg.canonical_control;

mappings = {
    "identity.scenario_id", "meta.scenario_id", "identity"
    "identity.scenario_id", "meta.scenario_family", "identity"
    "identity.scenario_id", "meta.scenario_group", "identity"
    "identity.scenario_name", "meta.scenario_name", "identity"
    "identity.description", "meta.description", "identity"
    "identity.version", "meta.version", "identity"
    "identity.owner", "meta.owner", "identity"
    "identity.owner", "meta.author", "identity"
    "identity.research_class", "meta.research_class", "identity"
    "identity.maturity_tag", "meta.maturity_tag", "identity"
    "identity.maturity_tag", "meta.study_status", "identity"
    "identity.tags", "meta.tags", "identity"
    "identity.purpose", "meta.purpose", "identity"
    "identity.release_reference", "meta.release_reference", "identity"
    "identity.source_reference", "meta.source_reference", "identity"
    "identity.created_at", "meta.created_at", "identity"
    "identity.notes", "meta.notes", "identity"
    "identity.baseline_reference_name", "meta.baseline_reference_name", "identity"
    "identity.comparison_group_name", "meta.comparison_group_name", "identity"
    "launch.runner_profile", "scenario.runner_profile", "identity"
    "launch.target_cases", "scenario.target_cases", "identity"
    "launch.bundle_anchor_cases", "scenario.bundle_anchor_cases", "identity"
    "launch.expected_outputs", "scenario.expected_outputs", "identity"
    "launch.honesty_mode", "scenario.honesty_mode", "identity"
    "launch.unsupported_output_policy", "scenario.unsupported_output_policy", "identity"
    "launch.provenance_logging", "scenario.provenance_logging", "identity"
    "launch.notes", "scenario.notes", "identity"
    "launch.run_class", "validation.run_class", "identity"
    "launch.run_class", "validation.RunClass", "identity"
    "identity.scenario_id", "scenario.name", "identity"
    "identity.description", "scenario.description", "identity"
    "validation.run_class", "validation.run_class", "identity"
    "validation.run_class", "validation.RunClass", "identity"
    "run.seed", "simulation.random_seed", "identity"
    "run.seed", "run_control.seed", "identity"
    "run.seed", "run_control.random_seed_master", "identity"
    "run.deterministic_mode", "simulation.deterministic_mode", "identity"
    "run.deterministic_mode", "run_control.deterministic_mode", "identity"
    "run.link_direction", "simulation.link_direction", "identity"
    "run.n_frames", "simulation.n_frames", "identity"
    "run.total_slots", "simulation.n_slots", "identity"
    "run.n_subframes", "simulation.n_subframes", "identity"
    "run.monte_carlo_iterations", "simulation.monte_carlo_iterations", "identity"
    "run.snr_db", "simulation.snr_db", "identity"
    "run.noise_operating_mode", "simulation.noise_operating_mode", "identity"
    "run.min_duration_s", "simulation.min_duration_s", "identity"
    "run.snr_sweep_offsets_db", "simulation.snr_sweep_offsets_db", "identity"
    "run.execution_mode", "run_control.execution_mode", "identity"
    "run.study_mode", "run_control.study_mode", "identity"
    "run.simulation_mode", "run_control.simulation_mode", "identity"
    "run.run_profile", "run_control.run_profile", "identity"
    "run.fixed_link_campaign_enabled", "sweeps_and_matrix.fixed_link_calibration.enabled", "identity"
    "run.fixed_link_campaign_only", "sweeps_and_matrix.fixed_link_calibration.only", "identity"
    "run.fixed_link_snr_grid_db", "sweeps_and_matrix.fixed_link_calibration.snr_db", "identity"
    "run.fixed_link_snr_grid_db", "sweeps_and_matrix.snr_sweep.values_db", "identity"
    "run.min_trials_per_sinr_bin", "sweeps_and_matrix.fixed_link_calibration.min_trials", "identity"
    "run.max_trials_per_sinr_bin", "sweeps_and_matrix.fixed_link_calibration.max_trials", "identity"
    "run.max_ci_width", "sweeps_and_matrix.fixed_link_calibration.ci_width_target", "identity"
    "run.confidence_level", "sweeps_and_matrix.fixed_link_calibration.confidence_level", "identity"
    "run.total_slots", "run_control.total_slots", "identity"
    "run.warmup_slots", "run_control.warmup_slots", "identity"
    "run.measurement_slots", "run_control.measurement_slots", "identity"
    "run.num_workers", "run_control.num_workers", "identity"
    "run.batch_size_links", "run_control.batch_size_links", "identity"
    "run.auto_start_parallel_pool", "run_control.auto_start_parallel_pool", "identity"
    "run.trace_capture_level", "run_control.trace_capture_level", "identity"
    "run.save_intermediate", "run_control.save_intermediate", "identity"
    "radio.range_name", "frequency.range_name", "identity"
    "radio.band_name", "frequency.band_name", "identity"
    "radio.center_frequency_hz", "frequency.center_frequency_hz", "identity"
    "radio.bandwidth_hz", "frequency.bandwidth_hz", "identity"
    "radio.bandwidth_options_hz", "frequency.bandwidth_options_hz", "identity"
    "radio.duplex_mode", "frequency.duplex_mode", "identity"
    "radio.carrier_count", "frequency.carrier_count", "identity"
    "radio.carrier_aggregation_enabled", "frequency.carrier_aggregation_enabled", "identity"
    "radio.numerology_options_khz", "frequency.numerology_options_khz", "identity"
    "radio.max_mimo_size", "frequency.max_mimo_size", "identity"
    "radio.mobility_defaults_kmph", "frequency.mobility_defaults_kmph", "identity"
    "radio.channel_model_defaults", "frequency.channel_model_defaults", "identity"
    "radio.reference_signal_defaults", "frequency.reference_signal_defaults", "identity"
    "radio.power_model_defaults", "frequency.power_model_defaults", "identity"
    "radio.energy_model_defaults", "frequency.energy_model_defaults", "identity"
    "radio.rf_impairment_defaults", "frequency.rf_impairment_defaults", "identity"
    "radio.n_size_grid", "frequency.n_size_grid", "identity"
    "radio.center_frequency_hz", "global_radio_scope.carrier_frequency_hz", "identity"
    "radio.bandwidth_hz", "global_radio_scope.channel_bandwidth_hz", "identity"
    "radio.bandwidth_hz", "global_radio_scope.simulation_bandwidth_hz", "identity"
    "radio.occupied_bandwidth_hz", "global_radio_scope.occupied_bandwidth_hz", "identity"
    "radio.duplex_mode", "global_radio_scope.duplex_mode", "identity"
    "radio.range_name", "global_radio_scope.frequency_range_label", "identity"
    "radio.scs_khz", "frame.scs_khz", "identity"
    "radio.scs_khz", "global_radio_scope.scs_hz", "khz_to_hz"
    "radio.cp_type", "frame.cp_type", "identity"
    "radio.cp_type", "global_radio_scope.cp_type", "identity"
    "radio.slot_format", "frame.slot_format", "identity"
    "radio.tdd_pattern", "frame.tdd_pattern", "identity"
    "radio.tdd_pattern", "frame_timing.tdd_pattern", "identity"
    "radio.special_slot_downlink_symbols", "frame.special_slot_downlink_symbols", "identity"
    "radio.special_slot_downlink_symbols", "frame_timing.special_slot_downlink_symbols", "identity"
    "radio.ul_dl_guard_symbols", "frame.ul_dl_guard_symbols", "identity"
    "radio.ul_dl_guard_symbols", "frame_timing.ul_dl_guard_symbols", "identity"
    "radio.special_slot_uplink_symbols", "frame.special_slot_uplink_symbols", "identity"
    "radio.special_slot_uplink_symbols", "frame_timing.special_slot_uplink_symbols", "identity"
    "radio.sample_rate_hz", "waveform.sample_rate_hz", "identity"
    "radio.sample_rate_hz", "global_radio_scope.sample_rate_hz", "identity"
    "radio.fft_size", "waveform.fft_size", "identity"
    "radio.fft_size", "waveform.dft_size", "identity"
    "radio.fft_size", "global_radio_scope.fft_size", "identity"
    "radio.fft_size", "global_radio_scope.ifft_size", "identity"
    "radio.dl_waveform", "waveform.dl_waveform", "identity"
    "radio.ul_waveform", "waveform.ul_waveform", "identity"
    "radio.transform_precoding_enabled", "waveform.transform_precoding_enabled", "identity"
    "radio.transform_precoding_enabled", "waveform.transform_precoding", "identity"
    "radio.windowing_enabled", "waveform.windowing_enabled", "identity"
    "radio.windowing_enabled", "waveform.windowing", "identity"
    "radio.n_size_grid", "resource_grid.num_rbs", "identity"
    "channel.model_type", "channels.model_type", "identity"
    "channel.model_type", "channel_model.model_family", "identity"
    "channel.profile", "channels.profile", "identity"
    "channel.profile", "channel_model.scenario_label", "identity"
    "channel.delay_spread_ns", "channels.delay_spread_ns", "identity"
    "channel.delay_spread_ns", "channel_model.delay_spread_ns", "identity"
    "channel.doppler_hz", "channels.doppler_hz", "identity"
    "channel.doppler_hz", "channel_model.doppler_hz", "identity"
    "channel.doppler_source_mode", "channels.doppler_source_mode", "identity"
    "channel.doppler_source_mode", "channel_model.doppler_source_mode", "identity"
    "channel.los_enabled", "channels.los_enabled", "identity"
    "channel.spatial_consistency_enabled", "channels.spatial_consistency_enabled", "identity"
    "channel.pathloss_enabled", "channels.pathloss_enabled", "identity"
    "channel.shadow_fading_enabled", "channels.shadow_fading_enabled", "identity"
    "channel.pathloss_model", "channels.pathloss_model", "identity"
    "channel.pathloss_model", "channel_model.pathloss_model", "identity"
    "channel.shadow_fading_std_db", "channels.shadow_fading_std_db", "identity"
    "channel.mobility_kmph", "channels.mobility_kmph", "identity"
    "channel.inter_cell_execution_mode", "interference.inter_cell_execution_mode", "identity"
    "mobility.ue_speed_kmh", "mobility.ue_speed_kmh", "identity"
    "mobility.ue_speed_kmh", "channels.mobility_kmph", "identity"
    "mobility.speed_profile", "mobility.speed_profile", "identity"
    "mobility.direction_model", "mobility.direction_model", "identity"
    "mobility.trajectory_model", "mobility.trajectory_model", "identity"
    "mobility.update_period_s", "mobility.update_period_s", "identity"
    "mobility.spatial_consistency_flag", "mobility.spatial_consistency_flag", "identity"
    "mobility.spatial_consistency_flag", "channels.spatial_consistency_enabled", "identity"
    "antenna.bs_array_geometry", "antenna_and_array.bs_array_geometry", "identity"
    "antenna.ue_array_geometry", "antenna_and_array.ue_array_geometry", "identity"
    "antenna.bs_num_antenna_elements", "antenna_and_array.bs_num_antenna_elements", "identity"
    "antenna.ue_num_antenna_elements", "antenna_and_array.ue_num_antenna_elements", "identity"
    "antenna.bs_num_antenna_elements", "mimo.n_tx_ant", "identity"
    "antenna.ue_num_antenna_elements", "mimo.n_rx_ant", "identity"
    "antenna.polarization", "antenna_and_array.polarization", "identity"
    "antenna.element_spacing_h", "antenna_and_array.element_spacing_h", "identity"
    "antenna.element_spacing_v", "antenna_and_array.element_spacing_v", "identity"
    "antenna.digital_precoder_family", "antenna_and_array.digital_precoder_family", "identity"
    "antenna.digital_precoder_family", "mimo.precoder_type", "identity"
    "antenna.bs_mechanical_tilt_deg", "antenna_and_array.bs_mechanical_tilt_deg", "identity"
    "power.bs_tx_power_dbm", "power_and_rf_frontend.bs_tx_power_dbm", "identity"
    "power.bs_tx_power_dbm", "energy_efficiency.tx_power_dbm", "identity"
    "power.ue_tx_power_dbm", "power_and_rf_frontend.ue_tx_power_dbm", "identity"
    "power.ue_noise_figure_db", "power_and_rf_frontend.ue_noise_figure_db", "identity"
    "power.bs_noise_figure_db", "power_and_rf_frontend.bs_noise_figure_db", "identity"
    "mimo.n_tx_ant", "mimo.n_tx_ant", "identity"
    "mimo.n_rx_ant", "mimo.n_rx_ant", "identity"
    "mimo.n_layers", "mimo.n_layers", "identity"
    "mimo.max_dl_layers", "mimo.max_dl_layers", "identity"
    "mimo.max_ul_layers", "mimo.max_ul_layers", "identity"
    "mimo.precoder_type", "mimo.precoder_type", "identity"
    "mimo.codebook_type", "mimo.codebook_type", "identity"
    "mimo.reciprocity_mode", "mimo.reciprocity_mode", "identity"
    "mimo.beam_sweep_enabled", "mimo.beam_sweep_enabled", "identity"
    "mimo.beam_count", "mimo.beam_count", "identity"
    "mimo.mtrp_ready", "mimo.mtrp_ready", "identity"
    "mimo.multi_panel_ready", "mimo.multi_panel_ready", "identity"
    "mimo.panel_count", "mimo.panel_count", "identity"
    "mimo.trp_count", "mimo.trp_count", "identity"
    "mimo.mu_mimo_enable", "mimo.mu_mimo_enable", "identity"
    "mimo.mu_mimo_max_users_per_prb", "mimo.mu_mimo_max_users_per_prb", "identity"
    "scheduler.type", "system.scheduler.type", "identity"
    "scheduler.max_active_ues_per_slot", "system.scheduler.maxActiveUEsPerSlot", "identity"
    "scheduler.max_active_ues_per_cell_per_slot", "system.scheduler.maxActiveUEsPerCellPerSlot", "identity"
    "scheduler.max_active_ues_per_cell_per_slot_dl", "system.scheduler.maxActiveUEsPerCellPerSlotDL", "identity"
    "scheduler.max_active_ues_per_cell_per_slot_ul", "system.scheduler.maxActiveUEsPerCellPerSlotUL", "identity"
    "scheduler.max_prb_allocation_per_ue", "system.scheduler.maxPRBAllocationPerUE", "identity"
    "scheduler.fairness_alpha", "system.scheduler.fairnessAlpha", "identity"
    "scheduler.proportional_fair_window_ms", "system.scheduler.proportionalFairWindow_ms", "identity"
    "scheduler.beam_aware", "system.scheduler.beamAware", "identity"
    "scheduler.energy_aware", "system.scheduler.energyAware", "identity"
    "scheduler.qos_aware", "system.scheduler.qosAware", "identity"
    "scheduler.slice_aware", "system.scheduler.sliceAware", "identity"
    "scheduler.starvation_guard", "system.scheduler.starvationGuard", "identity"
    "scheduler.cell_edge_boost", "system.scheduler.cellEdgeBoost", "identity"
    "scheduler.queue_max_bits", "system.queueMaxBits", "identity"
    "scheduler.large_scale_update_period_slots", "system.largeScaleUpdatePeriod_slots", "identity"
    "scheduler.beam_update_period_slots", "system.beam.updatePeriod_slots", "identity"
    "scheduler.beam_count", "system.beam.numBeams", "identity"
    "traffic.model", "traffic.model", "identity"
    "traffic.transport", "traffic.transport", "identity"
    "traffic.flow_direction", "traffic.flowDirection", "identity"
    "traffic.dl_ratio", "traffic.dlRatio", "identity"
    "traffic.ul_ratio", "traffic.ulRatio", "identity"
    "traffic.packet_delay_budget_ms", "traffic.packetDelayBudget_ms", "identity"
    "traffic.packet_size_bytes", "traffic.packetSize_bytes", "identity"
    "traffic.packet_interval_ms", "traffic.packetInterval_ms", "identity"
    "traffic.target_rate_mbps", "traffic.targetRate_Mbps", "identity"
    "traffic.full_buffer_bits_per_tti", "traffic.fullBufferBitsPerTTI", "identity"
    "reference_signals.ssb_enabled", "reference_signals.ssb_enabled", "identity"
    "reference_signals.pbch_enabled", "reference_signals.pbch_enabled", "identity"
    "reference_signals.pdcch_dmrs_enabled", "reference_signals.pdcch_dmrs_enabled", "identity"
    "reference_signals.csi_rs_enabled", "reference_signals.csi_rs_enabled", "identity"
    "reference_signals.srs_enabled", "reference_signals.srs_enabled", "identity"
    "reference_signals.trs_enabled", "reference_signals.trs_enabled", "identity"
    "reference_signals.ptrs_enabled", "reference_signals.ptrs_enabled", "identity"
    "reference_signals.csi_feedback_mode", "reference_signals.csi_feedback_mode", "identity"
    "reference_signals.cqi_reporting_enabled", "reference_signals.cqi_reporting_enabled", "identity"
    "reference_signals.pmi_reporting_enabled", "reference_signals.pmi_reporting_enabled", "identity"
    "reference_signals.ri_reporting_enabled", "reference_signals.ri_reporting_enabled", "identity"
    "reference_signals.pdsch_dmrs_ports", "reference_signals.pdsch_dmrs_ports", "identity"
    "reference_signals.pusch_dmrs_ports", "reference_signals.pusch_dmrs_ports", "identity"
    "reference_signals.csi_rs_ports", "reference_signals.csi_rs_ports", "identity"
    "reference_signals.srs_ports", "reference_signals.srs_ports", "identity"
    "reference_signals.trs_ports", "reference_signals.trs.num_ports", "identity"
    "reference_signals.trs_scrambling_id", "reference_signals.trs.scrambling_id", "identity"
    "reference_signals.srs_periodicity_ms", "reference_signals.srs_periodicity_ms", "identity"
    "reference_signals.srs_slot_within_period", "reference_signals.srs_slot_within_period", "identity"
    "reference_signals.srs_max_ues_per_slot", "reference_signals.srs_max_ues_per_slot", "identity"
    "reference_signals.srs_scheduling_policy", "reference_signals.srs_scheduling_policy", "identity"
    "reference_signals.trs_periodicity_ms", "reference_signals.trs_periodicity_ms", "identity"
    "reference_signals.ptrs_enabled", "reference_signals.ptrs.enabled", "identity"
    "reference_signals.csi_rs_enabled", "reference_signals.nzp_csi_rs.enabled", "identity"
    "reference_signals.srs_enabled", "reference_signals.srs.enabled", "identity"
    "reference_signals.trs_enabled", "reference_signals.trs.enabled", "identity"
    "csi.dl_csi_enabled", "csi_acquisition_and_reporting.dl_csi_enabled", "identity"
    "csi.ul_csi_enabled", "csi_acquisition_and_reporting.ul_csi_enabled", "identity"
    "csi.cqi_policy", "csi_acquisition_and_reporting.cqi_policy", "identity"
    "csi.pmi_policy", "csi_acquisition_and_reporting.pmi_policy", "identity"
    "csi.ri_policy", "csi_acquisition_and_reporting.ri_policy", "identity"
    "csi.report_payload_mode", "csi_acquisition_and_reporting.report_payload_mode", "identity"
    "csi.crc_attached_mode", "csi_acquisition_and_reporting.crc_attached_mode", "identity"
    "csi.crc_free_mode", "csi_acquisition_and_reporting.crc_free_mode", "identity"
    "control.pdcch_enabled", "control.pdcch_enabled", "identity"
    "control.pdcch_enabled", "pdcch.enabled", "identity"
    "control.pucch_enabled", "control.pucch_enabled", "identity"
    "control.pucch_enabled", "pucch.enabled", "identity"
    "control.pucch_format", "control.pucch_format", "identity"
    "control.pdcch_payload_bits", "control.pdcch_payload_bits", "identity"
    "control.blind_decode_list_length", "control.blind_decode_list_length", "identity"
    "control.aggregation_levels", "control.aggregation_levels", "identity"
    "control.aggregation_levels", "pdcch.aggregation_levels", "identity"
    "control.coreset_duration", "control.coreset_duration", "identity"
    "control.coreset_frequency_resources", "control.coreset_frequency_resources", "identity"
    "control.pbch_required", "control_gating.pbch_required", "identity"
    "control.prach_required", "control_gating.prach_required", "identity"
    "control.pdcch_required", "control_gating.pdcch_required", "identity"
    "control.srs_required", "control_gating.srs_required", "identity"
    "control.trs_required", "control_gating.trs_required", "identity"
    "control.srs_max_age_slots", "control_gating.srs_max_age_slots", "identity"
    "control.trs_max_age_slots", "control_gating.trs_max_age_slots", "identity"
    "random_access.enabled", "random_access.enabled", "identity"
    "random_access.enabled", "prach.enabled", "identity"
    "random_access.preamble_count", "random_access.preamble_count", "identity"
    "random_access.zero_correlation_zone", "random_access.zero_correlation_zone", "identity"
    "random_access.detection_threshold", "random_access.detection_threshold", "identity"
    "random_access.detection_threshold_mode", "random_access.detection_threshold_mode", "identity"
    "random_access.four_step_ra_required", "random_access.four_step_ra_required", "identity"
    "random_access.msg4_contention_resolution_required", "random_access.msg4_contention_resolution_required", "identity"
    "random_access.msg3_enabled", "random_access.msg3_enabled", "identity"
    "random_access.min_detection_trials", "random_access.min_detection_trials", "identity"
    "random_access.configuration_index", "random_access.configuration_index", "identity"
    "random_access.subcarrier_spacing_khz", "random_access.subcarrier_spacing_khz", "identity"
    "random_access.n_cell_id", "random_access.n_cell_id", "identity"
    "random_access.root_sequence_index", "random_access.root_sequence_index", "identity"
    "random_access.sequence_index", "random_access.sequence_index", "identity"
    "random_access.logical_root_sequence_index", "random_access.logical_root_sequence_index", "identity"
    "random_access.restricted_set", "random_access.restricted_set", "identity"
    "random_access.frequency_start", "random_access.frequency_start", "identity"
    "random_access.preamble_index", "random_access.preamble_index", "identity"
    "random_access.prach_format", "random_access.prach_format", "identity"
    "random_access.prach_format", "prach.format", "identity"
    "random_access.channel_model", "random_access.channel_model", "identity"
    "random_access.delay_spread_ns", "random_access.delay_spread_ns", "identity"
    "random_access.speed_kmh", "random_access.speed_kmh", "identity"
    "random_access.num_rx_antennas", "random_access.num_rx_antennas", "identity"
    "random_access.num_tx_antennas", "random_access.num_tx_antennas", "identity"
    "random_access.timing_tolerance_us", "random_access.timing_tolerance_us", "identity"
    "random_access.preamble_length_mode", "random_access.preamble_length_mode", "identity"
    "random_access.num_prach_occasions", "random_access.num_prach_occasions", "identity"
    "random_access.timing_offset_sweep_samples", "random_access.timing_offset_sweep_samples", "identity"
    "random_access.frequency_offset_sweep_hz", "random_access.frequency_offset_sweep_hz", "identity"
    "random_access.binding_source", "random_access.binding_source", "identity"
    "random_access.ra_response_window_slots", "random_access.ra_response_window_slots", "identity"
    "random_access.ra_contention_resolution_timer_slots", "random_access.ra_contention_resolution_timer_slots", "identity"
    "random_access.preamble_trans_max", "random_access.preamble_trans_max", "identity"
    "random_access.power_ramping_step_db", "random_access.power_ramping_step_db", "identity"
    "random_access.preamble_received_target_power_dbm", "random_access.preamble_received_target_power_dbm", "identity"
    "random_access.temp_crnti", "random_access.temp_crnti", "identity"
    "random_access.final_crnti", "random_access.final_crnti", "identity"
    "random_access.msg2_slot", "random_access.msg2_slot", "identity"
    "random_access.msg3_slot", "random_access.msg3_slot", "identity"
    "random_access.msg4_slot", "random_access.msg4_slot", "identity"
    "random_access.dci_payload_bits", "random_access.dci_payload_bits", "identity"
    "random_access.msg2_pdsch", "random_access.msg2_pdsch", "identity"
    "random_access.msg3_pusch", "random_access.msg3_pusch", "identity"
    "random_access.msg4_pdsch", "random_access.msg4_pdsch", "identity"
    "random_access_evidence.four_step_ra_required", "random_access_evidence.four_step_ra_required", "identity"
    "random_access_evidence.msg1_prach_required", "random_access_evidence.msg1_prach_required", "identity"
    "random_access_evidence.msg2_rar_pdcch_pdsch_required", "random_access_evidence.msg2_rar_pdcch_pdsch_required", "identity"
    "random_access_evidence.msg3_pusch_required", "random_access_evidence.msg3_pusch_required", "identity"
    "random_access_evidence.msg4_contention_resolution_required", "random_access_evidence.msg4_contention_resolution_required", "identity"
    "random_access_evidence.ra_rnti_decode_required", "random_access_evidence.ra_rnti_decode_required", "identity"
    "random_access_evidence.rar_mac_ce_decode_required", "random_access_evidence.rar_mac_ce_decode_required", "identity"
    "random_access_evidence.timing_advance_required", "random_access_evidence.timing_advance_required", "identity"
    "random_access_evidence.contention_resolution_identity_required", "random_access_evidence.contention_resolution_identity_required", "identity"
    "random_access_evidence.preamble_collision_test_enabled", "random_access_evidence.preamble_collision_test_enabled", "identity"
    "random_access_evidence.false_alarm_test_enabled", "random_access_evidence.false_alarm_test_enabled", "identity"
    "random_access_evidence.missed_detection_test_enabled", "random_access_evidence.missed_detection_test_enabled", "identity"
    "coding.data_code_type", "coding.data_code_type", "identity"
    "coding.control_code_type", "coding.control_code_type", "identity"
    "coding.base_graph", "coding.base_graph", "identity"
    "coding.max_decoder_iterations", "coding.max_decoder_iterations", "identity"
    "modulation.dl_modulation_order", "modulation.dl_modulation_order", "identity"
    "modulation.ul_modulation_order", "modulation.ul_modulation_order", "identity"
    "modulation.dl_mcs_index", "modulation.dl_mcs_index", "identity"
    "modulation.ul_mcs_index", "modulation.ul_mcs_index", "identity"
    "modulation.mcs_table", "modulation.mcs_table", "identity"
    "modulation.pi2_bpsk_enabled", "modulation.pi2_bpsk_enabled", "identity"
    "modulation.constellation_shaping_enabled", "modulation.constellation_shaping_enabled", "identity"
    "harq.enabled", "harq.enabled", "identity"
    "harq.process_count", "harq.process_count", "identity"
    "harq.max_retx", "harq.max_retx", "identity"
    "harq.rv_sequence", "harq.rv_sequence", "identity"
    "harq.combining_mode", "harq.combining_mode", "identity"
    "harq.feedback_timing_slots", "harq.feedback_timing_slots", "identity"
    "receiver.channel_estimator", "receiver_algorithms.channel_estimator", "identity"
    "receiver.interpolation_method", "receiver_algorithms.interpolation_method", "identity"
    "receiver.equalizer", "receiver_algorithms.equalizer", "identity"
    "receiver.decoder_iterations", "receiver_algorithms.decoder_iterations", "identity"
    "ai_ml.enabled", "ai_ml.enabled", "identity"
    "ai_ml.use_case", "ai_ml.use_case", "identity"
    "ai_ml.mode", "ai_ml.mode", "identity"
    "ai_ml.model_path", "ai_ml.model_path", "identity"
    "ai_ml.model_id", "ai_ml.model_id", "identity"
    "ai_ml.model_version", "ai_ml.model_version", "identity"
    "ai_ml.fallback_enabled", "ai_ml.fallback_enabled", "identity"
    "energy.enabled", "energy_efficiency.enabled", "identity"
    "energy.tx_power_dbm", "energy_efficiency.tx_power_dbm", "identity"
    "energy.pa_efficiency", "energy_efficiency.pa_efficiency", "identity"
    "energy.rf_chain_count", "energy_efficiency.rf_chain_count", "identity"
    "kpis.enabled", "kpis", "kpi_flags"
    "output.output_dir", "output_control.output_dir", "identity"
    "output.artifact_formats", "output_control.artifact_formats", "identity"
    "output.save_csv", "output.save_csv", "identity"
    "output.save_mat", "output.save_mat", "identity"
    "output.save_figures", "output.save_figures", "identity"
    "output.save_png", "output.save_png", "identity"
    "output.save_yaml_snapshot", "output.save_yaml_snapshot", "identity"
    "output.save_json_snapshot", "output.save_json_snapshot", "identity"
    "output.save_resolved_config", "output_control.save_resolved_config", "identity"
    "output.save_plots", "output_control.save_plots", "identity"
    "output.save_report", "output_control.save_report", "identity"
    "output.backend", "output.backend", "identity"
    "output.profile", "output.profile", "identity"
    "output.persistence_mode", "output.persistence_mode", "identity"
    "output.persistence_mode", "output_control.output_persistence_mode", "identity"
    "output.profiler_enabled", "output.profiler_enabled", "identity"
    "output.profiler_top_functions", "output.profiler_top_functions", "identity"
    "output.profiler_top_edges", "output.profiler_top_edges", "identity"
    "output.live_publish_frame_interval", "output.live_publish_frame_interval", "identity"
    "output.live_heavy_refresh_interval_frames", "output.live_heavy_refresh_interval_frames", "identity"
    "output.emit_placeholder_artifacts", "output.emit_placeholder_artifacts", "identity"
    "logging.level", "logging.level", "identity"
    "logging.save_logs", "logging.save_logs", "identity"
    "logging.save_intermediate", "logging.save_intermediate", "identity"
    "logging.strict_validation", "logging.strict_validation", "identity"
    "logging.include_git_hash", "logging.include_git_hash", "identity"
    "logging.echo_to_console", "logging.echo_to_console", "identity"
    };

for i = 1:size(mappings, 1)
    cfg = localSetCanonicalValue(cfg, control, mappings{i,1}, mappings{i,2}, mappings{i,3});
end

cfg = localApplyCanonicalTopology(cfg, control);
cfg = localApplyCanonicalRuntimeOverrides(cfg, control);
end

function cfg = localSetCanonicalValue(cfg, control, sourcePath, targetPath, mode)
[value, found] = localTryGetNestedValue(control, sourcePath);
if ~found
    return;
end
cfg = sixgr.util.structSet(cfg, targetPath, localCanonicalConvert(value, mode));
end

function out = localCanonicalConvert(value, mode)
switch string(mode)
    case "khz_to_hz"
        out = double(value) * 1e3;
    case "kpi_flags"
        out = localCanonicalKPIFlags(value);
    otherwise
        out = value;
end
end

function s = localCanonicalKPIFlags(value)
if isstruct(value)
    s = value;
    return;
end
s = struct();
if isstring(value) || iscellstr(value)
    items = string(value(:));
    for i = 1:numel(items)
        key = matlab.lang.makeValidName(char(items(i)));
        if strlength(strtrim(items(i))) > 0
            s.(key) = true;
        end
    end
end
end

function cfg = localApplyCanonicalTopology(cfg, control)
sites = localCanonicalPositiveInt(sixgr.util.structGet(control, "topology.num_sites", []), 1);
sectors = localCanonicalPositiveInt(sixgr.util.structGet(control, "topology.num_sectors_per_site", []), NaN);
cells = localCanonicalPositiveInt(sixgr.util.structGet(control, "topology.num_cells", []), NaN);
if ~isfinite(sectors)
    if isfinite(cells)
        sectors = max(1, ceil(cells / max(1, sites)));
    else
        sectors = 1;
    end
end
if ~isfinite(cells)
    cells = max(1, sites * sectors);
end
trps = localCanonicalPositiveInt(sixgr.util.structGet(control, "topology.num_trps", []), cells);
ues = localCanonicalPositiveInt(sixgr.util.structGet(control, "topology.num_ues", []), 1);
azimuths = localCanonicalSectorAzimuths(control, sectors);

derived = {
    "deployment_topology.num_sites", sites
    "deployment_topology.num_base_stations", sites
    "deployment_topology.num_sectors_per_site", sectors
    "deployment_topology.num_cells", cells
    "deployment_topology.num_trps", trps
    "deployment_topology.num_ues", ues
    "deployment_topology.sector_azimuth_offsets_deg", azimuths
    "deployment_topology.sector_azimuths_deg", azimuths
    "scenario.layout.nSites", sites
    "scenario.layout.nSectorsPerSite", sectors
    "scenario.layout.nCells", cells
    "scenario.sectorization.azimOffsets_deg", azimuths
    "scenario.ue.nUE", ues
    "users.n_users", ues
    };
for i = 1:size(derived, 1)
    cfg = sixgr.util.structSet(cfg, derived{i,1}, derived{i,2});
end

mappings = {
    "topology.site_layout", "deployment_topology.site_layout"
    "topology.cell_type", "deployment_topology.cell_type"
    "topology.inter_site_distance_m", "deployment_topology.inter_site_distance"
    "topology.inter_site_distance_m", "scenario.layout.interSiteDistance_m"
    "topology.wraparound_enabled", "deployment_topology.wraparound_enabled"
    "topology.wraparound_enabled", "scenario.layout.wrapAround"
    "topology.area_m", "scenario.geometry.area_m"
    "topology.bs_height_m", "scenario.bs.height_m"
    "topology.indoor_ue_fraction", "deployment_topology.indoor_ue_fraction"
    "topology.min_ue_distance_from_bs_m", "deployment_topology.min_ue_distance_from_bs_m"
    "topology.max_ue_distance_from_bs_m", "deployment_topology.max_ue_distance_from_bs_m"
    "topology.users_enabled", "users.enabled"
    "topology.rnti_start", "users.rnti_start"
    "topology.seed_stride", "users.seed_stride"
    "topology.execution_model", "users.execution_model"
    "topology.beam_selection_strategy", "users.beam_selection_strategy"
    "topology.save_user_tables", "users.save_user_tables"
    "topology.trp_topology", "deployment_topology.trp_topology"
    "topology.trp_sync_mode", "deployment_topology.trp_sync_mode"
    "topology.trp_switching_mode", "deployment_topology.trp_switching_mode"
    "topology.cell_free_flag", "deployment_topology.cell_free_flag"
    "topology.full_duplex_flag", "deployment_topology.full_duplex_flag"
    "topology.self_interference_path_model", "deployment_topology.self_interference_path_model"
    };
for i = 1:size(mappings, 1)
    cfg = localSetCanonicalValue(cfg, control, mappings{i,1}, mappings{i,2}, "identity");
end
end

function value = localCanonicalPositiveInt(raw, defaultValue)
value = defaultValue;
if isempty(raw) || ~(isnumeric(raw) || islogical(raw))
    return;
end
raw = double(raw(:));
raw = raw(isfinite(raw));
if ~isempty(raw)
    value = max(1, round(raw(1)));
end
end

function azimuths = localCanonicalSectorAzimuths(control, sectors)
[configured, found] = localTryGetNestedValue(control, "topology.sector_azimuth_offsets_deg");
if found && isnumeric(configured) && ~isempty(configured)
    vals = double(configured(:)).';
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        azimuths = vals;
        return;
    end
end
sectors = max(1, round(double(sectors)));
azimuths = (0:(sectors-1)) .* (360 / sectors);
end

function cfg = localApplyCanonicalRuntimeOverrides(cfg, control)
overrides = sixgr.util.structGet(control, "runtime_overrides", []);
if isempty(overrides) || ~isstruct(overrides)
    return;
end
for i = 1:numel(overrides)
    if ~isfield(overrides(i), "path") || ~isfield(overrides(i), "value")
        continue;
    end
    target = strtrim(string(overrides(i).path));
    if strlength(target) == 0
        continue;
    end
    cfg = sixgr.util.structSet(cfg, char(target), overrides(i).value);
end
end

function cfg = localEnsureConfigInheritance(cfg, sourceFiles, configPath)
parents = strings(0,1);
if numel(sourceFiles) > 1
    parents = sourceFiles(1:end-1);
end
prov = struct();
prov.source_files = cellstr(sourceFiles);
prov.config_path = char(configPath);
prov.resolved_at_loader = true;
prov.source_kind = char(localInferSourceKind(configPath, sourceFiles));
cfg = sixgr.util.structSet(cfg, "config_inheritance.parents", cellstr(parents));
cfg = sixgr.util.structSet(cfg, "config_inheritance.merge_policy", "deep_merge_last_writer_wins");
cfg = sixgr.util.structSet(cfg, "config_inheritance.locked_fields", cell(0,1));
cfg = sixgr.util.structSet(cfg, "config_inheritance.overridden_fields", cell(0,1));
cfg = sixgr.util.structSet(cfg, "config_inheritance.provenance", prov);
end

function kind = localInferSourceKind(configPath, sourceFiles)
kind = "scenario_config_file";
if localIsBrowserOverlayPath(configPath)
    kind = "browser_runtime_overlay";
    return;
end
for i = 1:numel(sourceFiles)
    if localIsBrowserOverlayPath(sourceFiles(i))
        kind = "browser_runtime_overlay";
        return;
    end
end
end

function tf = localIsBrowserOverlayPath(candidate)
candidate = string(candidate);
tf = false;
if strlength(candidate) == 0
    return;
end
[~, name, ext] = fileparts(char(candidate));
tf = startsWith(string(name), "__web_runtime_", "IgnoreCase", true) && any(strcmpi(string(ext), [".yaml",".yml",".json"]));
end

function cfg = localApplyBrowserOverlayDurationAliases(cfg, sourceFiles, configPath)
overlayPath = localBrowserOverlayPath(sourceFiles, configPath);
if strlength(overlayPath) == 0
    return;
end
overlay = localReadBrowserOverlayStruct(overlayPath);
if ~isstruct(overlay) || ~isscalar(overlay)
    return;
end

cfg = localMirrorOverlayNumeric(cfg, overlay, "simulation.n_slots", ...
    ["simulation.n_slots", "run_control.total_slots"]);
cfg = localMirrorOverlayNumeric(cfg, overlay, "run_control.total_slots", ...
    ["run_control.total_slots", "simulation.n_slots"]);
cfg = localMirrorOverlayNumeric(cfg, overlay, "run_control.warmup_slots", ...
    "run_control.warmup_slots");
cfg = localMirrorOverlayNumeric(cfg, overlay, "run_control.measurement_slots", ...
    "run_control.measurement_slots");
end

function overlayPath = localBrowserOverlayPath(sourceFiles, configPath)
overlayPath = "";
if localIsBrowserOverlayPath(configPath)
    overlayPath = string(configPath);
    return;
end
for i = numel(sourceFiles):-1:1
    if localIsBrowserOverlayPath(sourceFiles(i))
        overlayPath = string(sourceFiles(i));
        return;
    end
end
end

function overlay = localReadBrowserOverlayStruct(pathStr)
overlay = struct();
try
    overlay = sixgr.lls6g.config.readConfigFile(char(string(pathStr)));
catch
    overlay = struct();
end
if isstruct(overlay) && isscalar(overlay) && isfield(overlay, "inherits")
    overlay = rmfield(overlay, "inherits");
end
end

function cfg = localMirrorOverlayNumeric(cfg, overlay, overlayPath, targetPaths)
[value, found] = localTryGetNestedValue(overlay, overlayPath);
value = localOverlayNumericScalar(value);
if ~found || ~(isfinite(value) && value >= 0)
    return;
end
for i = 1:numel(targetPaths)
        cfg = sixgr.util.structSet(cfg, char(string(targetPaths(i))), double(value));
end
end

function cfg = localNormalizeFixedLinkCalibrationMode(cfg)
if ~logical(sixgr.util.structGet(cfg, "sweeps_and_matrix.fixed_link_calibration.only", false))
    return;
end
mode = strtrim(string(sixgr.util.structGet(cfg, "simulation.noise_operating_mode", "")));
if mode == "standalone_awgn_snr_argument"
    return;
end
cfg = sixgr.util.structSet(cfg, "simulation.noise_operating_mode", "standalone_awgn_snr_argument");
cfg = localRecordNormalizationAudit(cfg, "simulation.noise_operating_mode", ...
    "Auto-normalized simulation.noise_operating_mode to standalone_awgn_snr_argument because sweeps_and_matrix.fixed_link_calibration.only=true.");
end

function cfg = localNormalizeFixedSNRSweepRunClass(cfg)
runClass = lower(strtrim(localFirstNonEmptyString([
    sixgr.util.structGet(cfg, "validation.run_class", "")
    sixgr.util.structGet(cfg, "validation.RunClass", "")
    sixgr.util.structGet(cfg, "canonical_control.validation.run_class", "")
    sixgr.util.structGet(cfg, "canonical_control.validation.RunClass", "")
    sixgr.util.structGet(cfg, "canonical_control.launch.run_class", "")
    ])));
sweepEnabledByLaunch = logical(sixgr.util.structGet(cfg, "canonical_control.launch.sweep_enabled", false));
if runClass ~= "fixed_snr_sweep_lls" && ~sweepEnabledByLaunch
    return;
end

cfg = sixgr.util.structSet(cfg, "sweeps_and_matrix.snr_sweep.enabled", true);
cfg = localRecordNormalizationAudit(cfg, "sweeps_and_matrix.snr_sweep.enabled", ...
    "Re-enabled sweeps_and_matrix.snr_sweep.enabled for validation.run_class=fixed_snr_sweep_lls after canonical runtime overrides were applied.");

snrGrid = localFirstFiniteVector( ...
    sixgr.util.structGet(cfg, "sweeps_and_matrix.fixed_link_calibration.snr_db", []), ...
    sixgr.util.structGet(cfg, "validation.fixed_link_campaign.snr_db", []), ...
    sixgr.util.structGet(cfg, "sweeps_and_matrix.snr_sweep.values_db", []));
if ~isempty(snrGrid)
    cfg = sixgr.util.structSet(cfg, "sweeps_and_matrix.snr_sweep.values_db", snrGrid);
    cfg = localRecordNormalizationAudit(cfg, "sweeps_and_matrix.snr_sweep.values_db", ...
        "Mirrored fixed-link SNR grid into sweeps_and_matrix.snr_sweep.values_db for validation.run_class=fixed_snr_sweep_lls.");
end
end

function cfg = localRecordNormalizationAudit(cfg, fieldPath, note)
cfg = sixgr.util.structSet(cfg, "config_inheritance.overridden_fields", ...
    localAppendStringListEntry(sixgr.util.structGet(cfg, "config_inheritance.overridden_fields", {}), fieldPath));
cfg = sixgr.util.structSet(cfg, "config_inheritance.provenance.auto_normalized_fields", ...
    localAppendStringListEntry(sixgr.util.structGet(cfg, "config_inheritance.provenance.auto_normalized_fields", {}), fieldPath));
cfg = sixgr.util.structSet(cfg, "config_inheritance.provenance.auto_normalization_notes", ...
    localAppendStringListEntry(sixgr.util.structGet(cfg, "config_inheritance.provenance.auto_normalization_notes", {}), note));
end

function values = localAppendStringListEntry(existing, entry)
values = string.empty(0,1);
if iscellstr(existing)
    values = string(existing(:));
elseif isstring(existing)
    values = existing(:);
elseif ischar(existing)
    values = string(existing);
end
candidate = strtrim(string(entry));
if strlength(candidate) > 0 && ~any(values == candidate)
    values(end+1,1) = candidate; %#ok<AGROW>
end
values = values(strlength(strtrim(values)) > 0);
values = cellstr(values);
end

function value = localFirstNonEmptyString(values)
value = "";
values = string(values(:));
for i = 1:numel(values)
    candidate = strtrim(values(i));
    if strlength(candidate) > 0
        value = candidate;
        return;
    end
end
end

function values = localFirstFiniteVector(varargin)
values = [];
for i = 1:nargin
    candidate = varargin{i};
    if isempty(candidate) || ~(isnumeric(candidate) || islogical(candidate))
        continue;
    end
    candidate = double(candidate(:)).';
    candidate = candidate(isfinite(candidate));
    if ~isempty(candidate)
        values = candidate;
        return;
    end
end
end

function value = localOverlayNumericScalar(raw)
value = NaN;
if isempty(raw) || ~(isnumeric(raw) || islogical(raw))
    return;
end
raw = double(raw(:));
raw = raw(isfinite(raw));
if ~isempty(raw)
    value = double(raw(1));
end
end

function [value, found] = localTryGetNestedValue(s, pathStr)
value = [];
found = false;
node = s;
parts = split(string(pathStr), ".");
for i = 1:numel(parts)
    key = char(parts(i));
    if ~(isstruct(node) && isscalar(node) && isfield(node, key))
        return;
    end
    node = node.(key);
end
value = node;
found = true;
end

function cfg = localSyncNestedFlag(cfg, newBase, oldBase, newPath, oldPath)
cfg = localSyncValue(cfg, newBase, oldBase, newPath, oldPath, "identity");
end

function cfg = localApplyPDCCHCoresetBandwidthAlias(cfg)
bandwidthRB = double(sixgr.util.structGet(cfg, "pdcch.coreset_bandwidth_rb", NaN));
if ~(isscalar(bandwidthRB) && isfinite(bandwidthRB) && bandwidthRB > 0)
    return;
end
resourceBlockGroupCount = max(1, ceil(bandwidthRB / 6));
cfg = sixgr.util.structSet(cfg, "control.coreset_frequency_resources", ones(1, resourceBlockGroupCount));
end

function cfg = localApplyDerivedRadioAliases(cfg, newBase)
scsKHz = localFirstFiniteScalar(sixgr.util.structGet(cfg, "frame.scs_khz", NaN), NaN);
if ~(isfinite(scsKHz) && scsKHz > 0)
    return;
end

mu = log2(scsKHz / 15);
if isfinite(mu)
    mu = round(mu);
end

function value = localFirstFiniteScalar(raw, defaultValue)
if nargin < 2
    defaultValue = NaN;
end
value = defaultValue;
if isempty(raw) || ~(isnumeric(raw) || islogical(raw))
    return;
end
raw = double(raw(:));
raw = raw(isfinite(raw));
if ~isempty(raw)
    value = double(raw(1));
end
end
if ~(isfinite(mu) && mu >= 0)
    return;
end

slotDurationMs = 1 / 2^double(mu);
slotsPerFrame = 10 * 2^double(mu);
totalSlots = localFirstFiniteScalar(sixgr.util.structGet(cfg, "run_control.total_slots", ...
    sixgr.util.structGet(cfg, "simulation.n_slots", NaN)), NaN);
if isfinite(totalSlots) && totalSlots > 0
    cfg = sixgr.util.structSet(cfg, "run_control.total_time_ms", double(totalSlots) * slotDurationMs);
    cfg = sixgr.util.structSet(cfg, "simulation.n_slots", double(totalSlots));
end
warmupSlots = localFirstFiniteScalar(sixgr.util.structGet(cfg, "run_control.warmup_slots", NaN), NaN);
if isfinite(warmupSlots) && warmupSlots >= 0
    cfg = sixgr.util.structSet(cfg, "run_control.warmup_time_ms", double(warmupSlots) * slotDurationMs);
end
measurementSlots = localFirstFiniteScalar(sixgr.util.structGet(cfg, "run_control.measurement_slots", NaN), NaN);
if isfinite(measurementSlots) && measurementSlots >= 0
    cfg = sixgr.util.structSet(cfg, "run_control.measurement_time_ms", double(measurementSlots) * slotDurationMs);
end

cfg = localReplaceIfDefaultOrMissing(cfg, newBase, "global_radio_scope.scs_hz", scsKHz * 1e3);
cfg = localReplaceIfDefaultOrMissing(cfg, newBase, "global_radio_scope.numerology_mu", mu);
cfg = localReplaceIfDefaultOrMissing(cfg, newBase, "frame_timing.slot_duration_ms", slotDurationMs);
cfg = localReplaceIfDefaultOrMissing(cfg, newBase, "frame_timing.slots_per_frame", slotsPerFrame);
cfg = localReplaceIfDefaultOrMissing(cfg, newBase, "frame_timing.symbols_per_slot", 14);

carrierGrid = double(sixgr.util.structGet(cfg, "frequency.n_size_grid", NaN));
activeMode = lower(strtrim(string(sixgr.util.structGet(cfg, "bandwidth_operation.active_bandwidth_mode", "fullband"))));
supportsPartial = logical(sixgr.util.structGet(cfg, "bandwidth_operation.supports_partial_band_activation", false));
if isfinite(carrierGrid) && carrierGrid > 0 && (~supportsPartial || activeMode == "fullband")
    cfg = localReplaceIfDefaultOrMissing(cfg, newBase, "resource_grid.num_rbs", round(carrierGrid));
end

cfg = localApplyCanonicalMobilityAuthority(cfg);

dopplerMode = lower(strtrim(string(sixgr.util.structGet(cfg, "channels.doppler_source_mode", ...
    sixgr.util.structGet(cfg, "channel_model.doppler_source_mode", "")))));
if dopplerMode == "derive_from_ue_speed"
    speedKmh = localFirstFiniteScalar(sixgr.util.structGet(cfg, "mobility.ue_speed_kmh", ...
        sixgr.util.structGet(cfg, "channels.mobility_kmph", NaN)), NaN);
    fcHz = localFirstFiniteScalar(sixgr.util.structGet(cfg, "frequency.center_frequency_hz", ...
        sixgr.util.structGet(cfg, "global_radio_scope.carrier_frequency_hz", NaN)), NaN);
    if isfinite(speedKmh) && speedKmh >= 0 && isfinite(fcHz) && fcHz >= 0
        dopplerHz = (double(speedKmh) / 3.6) * double(fcHz) / 299792458;
        cfg = sixgr.util.structSet(cfg, "channels.doppler_hz", dopplerHz);
        cfg = sixgr.util.structSet(cfg, "channel_model.doppler_hz", dopplerHz);
        cfg = sixgr.util.structSet(cfg, "channels.max_doppler_hz", dopplerHz);
    end
end
end

function cfg = localApplyCanonicalMobilityAuthority(cfg)
control = sixgr.util.structGet(cfg, "canonical_control", struct());
speedKmh = localCanonicalFiniteScalar(sixgr.util.structGet(control, "mobility.ue_speed_kmh", NaN));
if ~(isfinite(speedKmh) && speedKmh >= 0)
    speedKmh = localCanonicalFiniteScalar(sixgr.util.structGet(control, "channel.mobility_kmph", NaN));
end
if ~(isfinite(speedKmh) && speedKmh >= 0)
    return;
end
cfg = sixgr.util.structSet(cfg, "mobility.ue_speed_kmh", double(speedKmh));
cfg = sixgr.util.structSet(cfg, "scenario.mobility.speed_kmh", double(speedKmh));
cfg = sixgr.util.structSet(cfg, "channels.mobility_kmph", double(speedKmh));
end

function value = localCanonicalFiniteScalar(raw)
value = NaN;
if isempty(raw) || ~(isnumeric(raw) || islogical(raw))
    return;
end
raw = double(raw(:));
raw = raw(isfinite(raw));
if ~isempty(raw)
    value = double(raw(1));
end
end

function cfg = localEnsureScenarioSchemaVersion(cfg)
current = sixgr.lls6g.config.currentVersion();
if isempty(sixgr.util.structGet(cfg, "meta.schema_version", []))
    cfg = sixgr.util.structSet(cfg, "meta.schema_version", char(current));
end
if isempty(sixgr.util.structGet(cfg, "meta.schemaVersion", []))
    cfg = sixgr.util.structSet(cfg, "meta.schemaVersion", char(current));
end
end

function cfg = localReplaceIfDefaultOrMissing(cfg, baseCfg, pathStr, value)
current = sixgr.util.structGet(cfg, pathStr, []);
baseValue = sixgr.util.structGet(baseCfg, pathStr, []);
if isempty(current) || isequaln(current, baseValue)
    cfg = sixgr.util.structSet(cfg, pathStr, value);
end
end

function cfg = localSyncValue(cfg, newBase, oldBase, newPath, oldPath, mode)
newVal = sixgr.util.structGet(cfg, newPath, []);
oldVal = sixgr.util.structGet(cfg, oldPath, []);
newBaseVal = sixgr.util.structGet(newBase, newPath, []);
oldBaseVal = sixgr.util.structGet(oldBase, oldPath, []);

newDiff = ~isequaln(newVal, newBaseVal);
oldDiff = ~isequaln(oldVal, oldBaseVal);
newMissing = localAliasMissing(newVal);
oldMissing = localAliasMissing(oldVal);

newToOld = localConvert(newVal, mode, "new_to_old");
oldToNew = localConvert(oldVal, mode, "old_to_new");

if newDiff && (oldMissing || ~oldDiff)
    cfg = sixgr.util.structSet(cfg, oldPath, newToOld);
elseif oldDiff && (newMissing || ~newDiff)
    cfg = sixgr.util.structSet(cfg, newPath, oldToNew);
elseif newDiff && oldDiff
    if ~isequaln(oldVal, newToOld) && ~isequaln(newVal, oldToNew)
        cfg = sixgr.util.structSet(cfg, oldPath, newToOld);
    end
end
end

function cfg = localPreferModernRuntimeValue(cfg, newPath, oldPath, mode)
newVal = sixgr.util.structGet(cfg, newPath, []);
oldVal = sixgr.util.structGet(cfg, oldPath, []);
if localAliasMissing(newVal) || localAliasMissing(oldVal)
    return;
end
newToOld = localConvert(newVal, mode, "new_to_old");
if ~isequaln(oldVal, newToOld)
    cfg = sixgr.util.structSet(cfg, oldPath, newToOld);
end
end

function cfg = localSyncAntennaElementSpacing(cfg, newBase, oldBase)
hPath = "antenna_and_array.element_spacing_h";
vPath = "antenna_and_array.element_spacing_v";
legacyPath = "scenario.bs.antenna.element_spacing_wavelengths";

hVal = sixgr.util.structGet(cfg, hPath, []);
vVal = sixgr.util.structGet(cfg, vPath, []);
legacyVal = sixgr.util.structGet(cfg, legacyPath, []);
hBaseVal = sixgr.util.structGet(newBase, hPath, []);
vBaseVal = sixgr.util.structGet(newBase, vPath, []);
legacyBaseVal = sixgr.util.structGet(oldBase, legacyPath, []);

hDiff = ~isequaln(hVal, hBaseVal);
vDiff = ~isequaln(vVal, vBaseVal);
legacyDiff = ~isequaln(legacyVal, legacyBaseVal);

legacySpacing = localSpacingVector(legacyVal);
if legacyDiff && ~isempty(legacySpacing)
    if (localAliasMissing(hVal) || ~hDiff) && numel(legacySpacing) >= 1
        cfg = sixgr.util.structSet(cfg, hPath, legacySpacing(1));
        hVal = legacySpacing(1);
        hDiff = true;
    end
    if localAliasMissing(vVal) || ~vDiff
        if numel(legacySpacing) >= 2
            cfg = sixgr.util.structSet(cfg, vPath, legacySpacing(2));
            vVal = legacySpacing(2);
            vDiff = true;
        elseif numel(legacySpacing) == 1
            cfg = sixgr.util.structSet(cfg, vPath, legacySpacing(1));
            vVal = legacySpacing(1);
            vDiff = true;
        end
    end
end

if hDiff || vDiff
    hScalar = localNumericScalar(hVal);
    vScalar = localNumericScalar(vVal);
    if isfinite(hScalar) && isfinite(vScalar)
        cfg = sixgr.util.structSet(cfg, legacyPath, [hScalar vScalar]);
    elseif isfinite(hScalar)
        cfg = sixgr.util.structSet(cfg, legacyPath, hScalar);
    elseif isfinite(vScalar)
        cfg = sixgr.util.structSet(cfg, legacyPath, vScalar);
    end
end
end

function values = localSpacingVector(value)
values = [];
if isnumeric(value) || islogical(value)
    values = double(value(:).');
    values = values(isfinite(values));
end
end

function value = localNumericScalar(raw)
value = NaN;
if (isnumeric(raw) || islogical(raw)) && isscalar(raw) && isfinite(double(raw))
    value = double(raw);
end
end

function cfg = localSyncMetadataAlias(cfg, newPath, oldPath)
newVal = sixgr.util.structGet(cfg, newPath, []);
oldVal = sixgr.util.structGet(cfg, oldPath, []);
newMissing = localAliasMissing(newVal);
oldMissing = localAliasMissing(oldVal);
if newMissing && ~oldMissing
    cfg = sixgr.util.structSet(cfg, newPath, oldVal);
elseif oldMissing && ~newMissing
    cfg = sixgr.util.structSet(cfg, oldPath, newVal);
end
end

function tf = localAliasMissing(value)
tf = isempty(value) && ~(ischar(value) || isstring(value) || iscell(value) || builtin("isstruct", value));
end

function out = localConvert(value, mode, direction)
switch mode
    case "identity"
        out = value;
    case "hz_to_khz"
        if direction == "new_to_old"
            out = double(value) / 1e3;
        else
            out = double(value) * 1e3;
        end
    case "first_numeric"
        if isnumeric(value) && ~isempty(value)
            if direction == "new_to_old"
                out = double(value(1));
            else
                out = double(value);
            end
        else
            out = value;
        end
    case "first_string"
        if (isstring(value) || iscellstr(value)) && ~isempty(value)
            if direction == "new_to_old"
                out = char(string(value(1)));
            else
                out = string(value);
            end
        else
            out = value;
        end
    case "string_to_bool"
        if direction == "new_to_old"
            out = ~ismember(lower(string(value)), ["disabled","none","off","false"]);
        else
            if logical(value)
                out = "enabled";
            else
                out = "disabled";
            end
        end
    case "bool_to_metric"
        if direction == "new_to_old"
            out = logical(value);
        else
            out = logical(value);
        end
    case "policy_to_bool"
        if direction == "new_to_old"
            out = ~ismember(lower(string(value)), ["disabled","none","off","false"]);
        else
            if logical(value)
                out = "baseline";
            else
                out = "disabled";
            end
        end
    case "kpi_list_to_struct"
        if direction == "new_to_old"
            out = localKPIListToStruct(value);
        else
            out = value;
        end
    case "numeric_string"
        if direction == "new_to_old"
            numericValue = str2double(string(value));
            if isfinite(numericValue)
                out = numericValue;
            else
                out = value;
            end
        else
            out = char(string(value));
        end
    case "modulation_to_order"
        if direction == "new_to_old"
            out = localModulationToOrder(value);
        else
            out = localOrderToModulation(value);
        end
    case "scheduler_type"
        if direction == "new_to_old"
            out = localSchedulerTypeToken(value);
        else
            out = value;
        end
    case "mobility_model"
        out = localMobilityModelToken(value);
    case "negative_tilt"
        numericValue = double(value);
        if isfinite(numericValue)
            if direction == "new_to_old"
                out = -abs(numericValue);
            else
                out = abs(numericValue);
            end
        else
            out = value;
        end
    case "ue_array_geometry"
        txt = lower(strtrim(string(value)));
        if contains(txt, "isotropic")
            out = "ULA";
        else
            out = value;
        end
    case "csi_mode"
        txt = lower(strtrim(string(value)));
        if txt == "type1_codebook"
            out = "PMI+CQI+RI";
        elseif txt == "disabled"
            out = "none";
        else
            out = value;
        end
    case "csi_report_type"
        txt = lower(strtrim(string(value)));
        if txt == "periodic"
            out = "PMI+CQI+RI";
        else
            out = value;
        end
    case "single_to_cell"
        if direction == "new_to_old"
            out = cellstr(string(value));
        else
            if iscell(value) || isstring(value)
                vals = string(value);
                out = char(vals(1));
            else
                out = value;
            end
        end
    case "threshold_mode"
        txt = lower(strtrim(string(value)));
        if txt == "fa_probability_calibrated"
            out = "auto";
        else
            out = value;
        end
    case "direction_token"
        txt = upper(strtrim(string(value)));
        if txt == "BIDIRECTIONAL"
            out = "BIDIR";
        else
            out = value;
        end
    case "o2i_model"
        txt = lower(strtrim(string(value)));
        if ismember(txt, ["", "none", "off", "disabled", "disable"])
            out = "none";
        elseif ismember(txt, ["low", "low_loss", "low-loss", "lowloss"])
            out = "low";
        elseif ismember(txt, ["high", "high_loss", "high-loss", "highloss"])
            out = "high";
        elseif txt == "custom"
            out = "custom";
        else
            out = value;
        end
    otherwise
        out = value;
end
end

function order = localModulationToOrder(value)
token = lower(strtrim(string(value)));
token = erase(token, ["-", "_", " "]);
switch token
    case {"pi2bpsk","bpsk"}
        order = 1;
    case {"qpsk","4qam","qam4"}
        order = 2;
    case {"16qam","qam16"}
        order = 4;
    case {"64qam","qam64"}
        order = 6;
    case {"256qam","qam256"}
        order = 8;
    case {"1024qam","qam1024"}
        order = 10;
    case {"4096qam","qam4096"}
        order = 12;
    otherwise
        if isnumeric(value) && isscalar(value)
            order = double(value);
        else
            order = value;
        end
end
end

function token = localOrderToModulation(value)
if ~(isnumeric(value) && isscalar(value) && isfinite(double(value)))
    token = value;
    return;
end
switch round(double(value))
    case 1
        token = "pi/2-BPSK";
    case 2
        token = "QPSK";
    case 4
        token = "16QAM";
    case 6
        token = "64QAM";
    case 8
        token = "256QAM";
    case 10
        token = "1024QAM";
    case 12
        token = "4096QAM";
    otherwise
        token = value;
end
end

function token = localSchedulerTypeToken(value)
txt = lower(strtrim(string(value)));
switch txt
    case {"proportional_fair","proportionalfair","pf"}
        token = "PF";
    case {"round_robin","roundrobin","rr"}
        token = "RR";
    case {"max_cqi","maxcqi"}
        token = "MAX_CQI";
    otherwise
        token = value;
end
end

function token = localMobilityModelToken(value)
txt = lower(strtrim(string(value)));
switch txt
    case {"random_waypoint","randomwaypoint","waypoint"}
        token = "randomWaypoint";
    case {"straight_line","straightline"}
        token = "straightLine";
    case "linear"
        token = "linear";
    otherwise
        token = value;
end
end

function s = localKPIListToStruct(value)
s = struct();
if isstring(value) || iscellstr(value)
    items = string(value(:));
    for i = 1:numel(items)
        key = matlab.lang.makeValidName(char(items(i)));
        s.(key) = true;
    end
elseif builtin("isstruct", value)
    s = value;
end
end

function cfg = localNewDefaults()
persistent cached
if isempty(cached)
    cached = struct();
    paths = localNewDefaultsPaths();
    for i = 1:numel(paths)
        raw = sixgr.lls6g.config.readConfigFile(paths(i));
        if isfield(raw, "inherits")
            raw = rmfield(raw, "inherits");
        end
        cached = sixgr.util.mergeStruct(cached, raw);
    end
end
cfg = cached;
end

function cfg = localLegacyDefaults()
persistent cached
if isempty(cached)
    raw = sixgr.lls6g.config.readConfigFile(localLegacyDefaultsPath());
    if isfield(raw, "inherits")
        raw = rmfield(raw, "inherits");
    end
    cached = raw;
end
cfg = cached;
end

function paths = localNewDefaultsPaths()
root = localRepoRoot();
paths = [ ...
    string(fullfile(root, "simulator", "configs", "defaults", "top_level_required_sections_01.yaml"))
    string(fullfile(root, "simulator", "configs", "defaults", "top_level_required_sections_02.yaml"))
    string(fullfile(root, "simulator", "configs", "defaults", "top_level_required_sections_03.yaml"))
    string(fullfile(root, "simulator", "configs", "defaults", "processing_chains.yaml"))
    ];
end

function p = localLegacyDefaultsPath()
root = localRepoRoot();
p = fullfile(root, "simulator", "configs", "defaults", "global.yaml");
end

function root = localRepoRoot()
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(fileparts(here)));
end
