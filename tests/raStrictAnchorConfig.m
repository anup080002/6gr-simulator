function cfg = raStrictAnchorConfig()
%RASTRICTANCHORCONFIG Explicit strict four-step RA anchor config for tests.
cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.run.seed = 240611;
cfg.scenario.name = "lls_ra_four_step_strict_mini_anchor";
cfg.scenario.objectives = ["random_access_four_step"];
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.lls6g.userContext.RuntimeServingPathloss_dB = 100;
cfg.lls6g.userContext.RuntimeServingBasePathloss_dB = 100;
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.NSizeGrid = 51;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.SubcarrierSpacing_kHz = 30;
% The long PRACH occasion starts in slot 2 and spans UL symbols. Keep the
% explicit unit fixture's common map consistent with that actual waveform.
cfg.phy.duplex.tddCommon.Pattern1.NumDownlinkSlots = 2;
cfg.phy.duplex.tddCommon.Pattern1.NumDownlinkSymbols = 0;
cfg.phy.duplex.tddCommon.Pattern1.NumUplinkSlots = 8;
cfg.phy.duplex.tddCommon.Pattern1.NumUplinkSymbols = 0;
cfg.frequency = struct( ...
    "range_name","FR1", ...
    "band_name","n78", ...
    "center_frequency_hz",3.5e9, ...
    "bandwidth_hz",20e6);
% Keep every carrier/bandwidth alias on the same physical operating point.
% FrameStructureEngine legitimately consumes the scenario-frequency fields,
% while strict PHY/channel validation and noise-power accounting consume the
% normalized channel aliases.  Leaving the default 4 GHz/100 MHz values here
% made one test configuration describe two different carriers.
cfg.channel.fc_Hz = 3.5e9;
cfg.channel.bandwidth_Hz = 20e6;
cfg.channel.subcarrierSpacing_kHz = 30;
cfg.channel.propagationScenario = "UMa";
cfg.phy.channelBandwidth_MHz = 20;
cfg.phy.pdcch.enable = true;
cfg.phy.pdcch.blindSearch = true;
cfg.phy.pdcch.dmrs.enable = true;
cfg.phy.pdsch.enable = true;
cfg.phy.pusch.enable = true;
cfg.phy.prach.enable = true;
cfg.initial_access.type0 = struct("monitoring_occasion_ordinal",2);
cfg.initial_access.sib1.pdsch = struct("prb_start",0, ...
    "num_prb",24,"symbol_start",2,"num_symbols",12,"mcs",0,"rv",0);
cfg.initial_access.rrc = struct( ...
    "require_setup_complete", true, ...
    "transaction_id", 0, ...
    "srb1_lcid", 1);
cfg.random_access = struct();
cfg.random_access.enabled = true;
cfg.random_access.rar_grant = struct("field_layout", "licensed_27bit", ...
    "frequency_hopping", false, "time_resource_assignment", 0, "tpc_command", 3);
cfg.random_access.binding_source = "scenario_config_pending_sib1";
cfg.random_access.prach_format = "0";
cfg.random_access.configuration_index = 16;
cfg.random_access.subcarrier_spacing_khz = 1.25;
cfg.random_access.root_sequence_index = 1;
cfg.random_access.zero_correlation_zone = 8;
cfg.random_access.restricted_set = "UnrestrictedSet";
cfg.random_access.msg1_fdm = 1;
cfg.random_access.frequency_start = 0;
cfg.random_access.preamble_index = 7;
cfg.random_access.occasion = struct("frame", 0, "slot", 2, "symbol", 0, "frequency_index", 0);
cfg.random_access.ra_response_window_slots = 8;
cfg.random_access.ra_contention_resolution_timer_slots = 64;
cfg.random_access.preamble_trans_max = 10;
cfg.random_access.power_ramping_step_db = 2;
cfg.random_access.preamble_received_target_power_dbm = -100;
cfg.random_access.ra_rnti_policy = "ts_38_321_ra_rnti_formula";
cfg.random_access.prach_occasion_policy = ...
    "ts_38_211_configuration_index_resolution";
cfg.random_access.temp_crnti = 4660;
cfg.random_access.final_crnti = 4660;
cfg.random_access.timing = struct( ...
    "rar_processing_delay_slots", 1, ...
    "msg3_k2_slots", 1, ...
    "msg4_processing_delay_slots", 1, ...
    "setup_complete_k2_slots", 1);
cfg.random_access.dci_payload_bits = 32;
cfg.random_access.detection_threshold_mode = "fixed";
cfg.random_access.detection_threshold = 0.02;
cfg.random_access.msg2_pdsch = localDLSched();
cfg.random_access.msg3_pusch = localULSched();
cfg.random_access.msg4_pdsch = localDLSched();
cfg.random_access.setup_complete_pusch = localULSched();
end

function s = localDLSched()
s = struct("prb_start", 0, "num_prb", 24, "symbol_start", 2, "num_symbols", 12, ...
    "mcs", 0, "modulation", "QPSK", "target_code_rate", 120/1024, ...
    "rv", 0, "n_layers", 1);
end

function s = localULSched()
s = struct("prb_start", 0, "num_prb", 24, "symbol_start", 0, "num_symbols", 14, ...
    "mcs", 0, "modulation", "QPSK", "target_code_rate", 120/1024, ...
    "rv", 0, "n_layers", 1, "transform_precoding", true);
end
