function cfg = raStrictAnchorConfig()
%RASTRICTANCHORCONFIG Explicit strict four-step RA anchor config for tests.
cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.run.seed = 240611;
cfg.scenario.name = "lls_ra_four_step_strict_mini_anchor";
cfg.scenario.objectives = ["random_access_four_step"];
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.NSizeGrid = 52;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.SubcarrierSpacing_kHz = 30;
cfg.random_access = struct();
cfg.random_access.enabled = true;
cfg.random_access.binding_source = "scenario_config_pending_sib1";
cfg.random_access.prach_format = "0";
cfg.random_access.configuration_index = 16;
cfg.random_access.subcarrier_spacing_khz = 1.25;
cfg.random_access.root_sequence_index = 1;
cfg.random_access.zero_correlation_zone = 8;
cfg.random_access.restricted_set = "UnrestrictedSet";
cfg.random_access.frequency_start = 0;
cfg.random_access.preamble_index = 7;
cfg.random_access.occasion = struct("frame", 0, "slot", 0, "symbol", 0, "frequency_index", 0);
cfg.random_access.ra_response_window_slots = 8;
cfg.random_access.ra_contention_resolution_timer_slots = 64;
cfg.random_access.preamble_trans_max = 1;
cfg.random_access.power_ramping_step_db = 2;
cfg.random_access.preamble_received_target_power_dbm = -100;
cfg.random_access.temp_crnti = 4660;
cfg.random_access.final_crnti = 4660;
cfg.random_access.msg2_slot = 1;
cfg.random_access.msg3_slot = 2;
cfg.random_access.msg4_slot = 3;
cfg.random_access.dci_payload_bits = 32;
cfg.random_access.detection_threshold_mode = "fixed";
cfg.random_access.detection_threshold = 0.02;
cfg.random_access.msg2_pdsch = localDLSched();
cfg.random_access.msg3_pusch = localULSched();
cfg.random_access.msg4_pdsch = localDLSched();
end

function s = localDLSched()
s = struct("prb_start", 0, "num_prb", 24, "symbol_start", 2, "num_symbols", 12, ...
    "mcs", 0, "modulation", "QPSK", "target_code_rate", 120/1024, ...
    "rv", 0, "n_layers", 1);
end

function s = localULSched()
s = struct("prb_start", 0, "num_prb", 24, "symbol_start", 0, "num_symbols", 14, ...
    "mcs", 0, "modulation", "QPSK", "target_code_rate", 120/1024, ...
    "rv", 0, "n_layers", 1);
end
