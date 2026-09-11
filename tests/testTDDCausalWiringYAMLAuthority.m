function ok = testTDDCausalWiringYAMLAuthority()
%TESTTDDCAUSALWIRINGYAMLAUTHORITY Guard the compact TDD wiring profile.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
root = fileparts(fileparts(mfilename("fullpath")));
scenarioPath = fullfile(root, "simulator", "configs", "scenarios", ...
    "lls_causal_access_to_data_wiring_tdd.yaml");
scenario = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
raw = scenario.toStruct();

assert(string(raw.canonical_control.integration.run_mode) == ...
    "FIXED_SNR_SWEEP");
assert(double(raw.canonical_control.integration.configuration_epoch) == 1);
assert(string(raw.canonical_control.integration.subprofile) == "connected_control_smoke");
assert(~logical(raw.canonical_control.launch.geometry_enabled));
assert(~logical(raw.canonical_control.launch.sweep_enabled));
assert(~logical(raw.canonical_control.launch.fixed_link_campaign_enabled));
assert(logical(raw.canonical_control.integration.configured_snr_is_link_authority));
assert(string(raw.simulation.noise_operating_mode) == "standalone_awgn_snr_argument");
assert(double(raw.simulation.snr_db) == 12);
assert(~logical(raw.simulation.reference_sweep_enabled));
assert(~logical(raw.simulation.adaptive_sweep_enabled));
assert(string(raw.frequency.duplex_mode) == "TDD");
assert(string(raw.global_radio_scope.duplex_mode) == "TDD");
assert(~isfield(raw.frequency, "dl_center_frequency_hz"));
assert(~isfield(raw.frequency, "ul_center_frequency_hz"));
assert(double(raw.frequency.center_frequency_hz) == 2.35e9);
assert(double(raw.frequency.bandwidth_hz) == 5e6);
assert(double(raw.frequency.n_size_grid) == 25);
assert(double(raw.global_radio_scope.fft_size) == 512);
assert(double(raw.global_radio_scope.sample_rate_hz) == 7.68e6);
expectedDopplerHz = (3/3.6) * double(raw.frequency.center_frequency_hz) / 299792458;
assert(string(raw.channels.model_type) == "CDL");
assert(string(raw.channels.profile) == "CDL-A");
assert(logical(raw.channels.per_sample_fading_enabled));
assert(abs(double(raw.channels.doppler_hz) - expectedDopplerHz) < 1e-12);
assert(string(raw.channels.doppler_source_mode) == "derive_from_ue_speed");
assert(logical(raw.channels.normalize_path_gains));
assert(~logical(raw.channels.normalize_channel_outputs));
assert(~logical(raw.channels.pathloss_enabled));
assert(string(raw.channels.o2i_model) == "none");
assert(double(raw.deployment_topology.indoor_ue_fraction) == 0);
assert(~logical(raw.rf_frontend.enabled));
assert(string(raw.rf_frontend.profile_id) == "ideal_phy_strict");
assert(string(raw.rf_frontend.claim_class) == "IDEAL_PHY");
assert(double(raw.rf_frontend.oscillator.tx_error_hz) == 0);
assert(~logical(raw.rf_frontend.phase_noise.enabled));
assert(~logical(raw.rf_frontend.iq_and_lo_leakage.enabled));
assert(~logical(raw.impairments.cfo_enabled));
assert(~logical(raw.impairments.phase_noise_enabled));
assert(~logical(raw.impairments.iq_imbalance_enabled));
assert(~logical(raw.impairments.adc_quantization_enabled));
assert(double(raw.tdd_timing.n1_pdsch_processing_time_symbols) == 8);
assert(double(raw.tdd_timing.n2_pusch_preparation_time_symbols) == 10);
assert(double(raw.run_control.total_slots) == 58);
assert(double(raw.run_control.measurement_slots) == 58);
assert(double(raw.link_adaptation.feedback_delay_slots) == 1);
assert(double(raw.reference_signals.pdsch_dmrs_ports) == 2);
assert(isequal(double(raw.reference_signals.pdsch_dmrs.port_set(:).'), [0 1]));
assert(double(raw.reference_signals.pusch_dmrs_ports) == 1);
assert(isequal(double(raw.reference_signals.pusch_dmrs.port_set(:).'), 0));
assert(~logical(raw.random_access.statistical_qualification.enabled));
assert(string(raw.validation.strict_component_evidence.execution_scope) == ...
    "in_path");
assert(string(raw.validation.run_class) == "adaptive_system_diagnostic");
assert(logical(raw.validation.causal_phy_chain_audit.enabled));
assert(logical(raw.validation.causal_phy_chain_audit.required));
assert(numel(raw.validation.causal_phy_chain_audit.stages) >= 20);
assert(numel(raw.validation.causal_phy_chain_audit.parameter_bindings) >= 10);
assert(all(ismember(["prach","pdcch","srs","trs","sib1","channel_rf"], ...
    string(raw.validation.strict_component_evidence.required_components))));
assert(logical(raw.random_access_evidence.four_step_ra_required));
assert(logical(raw.random_access_evidence.msg1_prach_required));
assert(logical(raw.random_access_evidence.msg2_rar_pdcch_pdsch_required));
assert(logical(raw.random_access_evidence.msg3_pusch_required));
assert(logical(raw.random_access_evidence.msg4_contention_resolution_required));
assert(logical(raw.random_access_evidence.require_runtime_stage_waveforms));
assert(logical(raw.random_access_evidence.allow_runtime_stage_waveform_composition));
assert(~logical(raw.random_access_evidence.false_alarm_test_enabled));
assert(~logical(raw.random_access_evidence.missed_detection_test_enabled));

cfg = sixgr.lls6g.buildInternalConfig(scenario, string(tempname));
assert(string(cfg.phy.duplex.mode) == "TDD");
assert(isfield(cfg.phy.duplex, "tddCommon"));
assert(~isfield(cfg.phy.duplex, "fdd"));
assert(double(cfg.phy.carrier.NSizeGrid) == 25);
assert(double(cfg.run.totalSlots) == 58);
assert(double(cfg.run.measurementSlots) == 58);
assert(string(cfg.channel.model) == "CDL");
assert(string(cfg.channel.cdlProfile) == "CDL-A");
assert(string(cfg.channel.fading.profile) == "CDL-A");
assert(logical(cfg.channel.fading.enable));
assert(abs(double(cfg.channel.maxDoppler_Hz) - expectedDopplerHz) < 1e-12);
assert(string(cfg.run.noiseOperatingMode) == "standalone_awgn_snr_argument");
assert(double(cfg.channel.snr_dB) == 12);
assert(logical(cfg.channel.normalizePathGains));
assert(~logical(cfg.channel.normalizeChannelOutputs));
assert(~logical(cfg.channel.pathlossEnabled));
assert(~logical(cfg.channel.o2i.enabled));
assert(string(cfg.mimo.rank_adaptation_policy) == "measured_ri");
assert(string(cfg.phy.linkAdaptation.rankPolicy) == "measured_ri");
assert(string(cfg.rf.specification.resolvedProfile.ProfileID) == "ideal_phy_strict");
assert(~logical(cfg.rf.tx.phaseNoise.enable));
assert(~logical(cfg.rf.rx.phaseNoise.enable));
assert(~logical(cfg.rf.tx.iqImbalance.enable));
assert(~logical(cfg.rf.rx.iqImbalance.enable));
assert(double(cfg.rf.tx.cfo_Hz) == 0);
assert(double(cfg.rf.rx.cfo_Hz) == 0);
assert(double(cfg.phy.linkAdaptation.feedbackDelaySlots) == 1);
assert(double(cfg.phy.csi.feedbackDelaySlots) == 1);
assert(double(cfg.phy.pdsch.nLayers) == 1);
assert(double(cfg.phy.pdsch.numPorts) == 2);
assert(isequal(double(cfg.phy.pdsch.dmrs.portSet(:).'), 0));
assert(isequal(double(cfg.phy.pdsch.dmrs.availablePortSet(:).'), [0 1]));
assert(double(cfg.phy.pusch.nLayers) == 1);
assert(double(cfg.phy.pusch.NumAntennaPorts) == 1);
assert(isequal(double(cfg.phy.pusch.dmrs.portSet(:).'), 0));
assert(double(cfg.phy.csirs.nPorts) == 2);
assert(double(cfg.antenna.bs.numElements) == 2);
assert(double(cfg.antenna.bs.numRFChains) == 2);
assert(double(cfg.phy.pdsch.numPorts) >= double(cfg.phy.pdsch.nLayers));
assert(double(cfg.phy.csirs.nPorts) <= double(cfg.phy.pdsch.numPorts));
assert(string(cfg.validation.strict_component_evidence.execution_scope) == ...
    "in_path");
timingPolicy = cfg.phy.frameStructure.TimingContext.Policy;
resolvedTimingPolicy = sixgr.phy.frame.TimingPolicyCatalog.resolveProduction( ...
    timingPolicy, 0, 0, ["K0","K1","K2"]);
assert(double(resolvedTimingPolicy.N1PDSCHProcessingTimeSymbols) == 8);
assert(double(resolvedTimingPolicy.N2PUSCHPreparationTimeSymbols) == 10);

frame = sixgr.phy.FrameStructureEngine(cfg, "FrameCoreOnly", true);
assert(frame.DuplexMode == "TDD");
for slot0 = [0 1 2 5 6 7]
    assert(frame.IsDLSlot(slot0));
    assert(~frame.IsULSlot(slot0));
    assert(frame.IsDLAllocation(slot0, [0 14]));
    assert(~frame.IsULAllocation(slot0, [0 14]));
end
for slot0 = [4 9]
    assert(frame.IsULSlot(slot0));
    assert(~frame.IsDLSlot(slot0));
    assert(frame.IsULAllocation(slot0, [0 14]));
    assert(~frame.IsDLAllocation(slot0, [0 14]));
end
for slot0 = [3 8]
    assert(frame.IsDLSlot(slot0) && frame.IsULSlot(slot0));
    assert(frame.IsDLAllocation(slot0, [0 10]));
    assert(~frame.IsDLAllocation(slot0, [10 4]));
    assert(frame.IsULAllocation(slot0, [12 2]));
    assert(~frame.IsULAllocation(slot0, [0 12]));
end

[allocations, checks] = sixgr.truth.buildPlannedREAllocation(cfg);
sixgr.truth.assertAllocationPreflight(checks);
required = ["FRAME","SSB_PBCH","TYPE0_PDCCH","SIB1_PDSCH", ...
    "PDCCH","PDSCH","CSI_RS","TRS","PRACH","PUCCH","PUSCH","SRS"];
assert(all(ismember(required, string(checks.feature))));
enabled = logical(checks.enabled);
assert(all(checks.resolved(enabled)));
assert(all(checks.status(enabled) == "PASS"));
assert(all(checks.exact_re_count(enabled) > 0));
assert(~isempty(allocations));

assert(raw.reference_signals.csi_rs_offset_slots == 1);
assert(raw.reference_signals.srs.period_offset == 4);
assert(double(raw.pusch.start_symbol) + double(raw.pusch.num_symbols) <= ...
    double(raw.reference_signals.srs.symbol_start), ...
    "The YAML-owned scheduled PUSCH allocation must leave the periodic SRS symbol collision-free.");
assert(string(raw.link_adaptation.ul_srs_to_pusch_layer_sinr_policy) == ...
    "minimum_layer_mean_post_equalization");
assert(double(raw.link_adaptation.ul_reference_signal_scheduling_backoff_db) == 0);
assert(isequal(double(raw.reference_signals.trs.slot_numbers(:)).', [7 8]));
assert(frame.IsDLSlot(1) && frame.IsULSlot(4));
assert(all(arrayfun(@(slot0) frame.IsDLSlot(slot0), ...
    double(raw.reference_signals.trs.slot_numbers))));
assert(logical(raw.pucch_resources.overlap_policy.uci_on_pusch_enabled));
assert(~logical(raw.interference.inter_cell_interference_flag));
assert(~logical(raw.interference.intra_cell_interference_flag));
assert(~logical(raw.interference.mu_mimo_interference_flag));
assert(string(raw.interference.inter_cell_execution_mode) == "none");
assert(string(raw.interference.interference_measurement_policy) == "disabled");
assert(isequal(double(raw.control.search_space_num_candidates(:)).', ...
    [4 2 1 1 0]));
assert(double(raw.pucch_resources.resources(2).occ_length) == 2);
assert(logical(raw.link_adaptation.inner_loop_flag));
assert(logical(raw.link_adaptation.outer_loop_flag));
assert(string(raw.link_adaptation.delta_mcs_policy) == "ack_nack_olla");
assert(string(raw.link_adaptation.cqi_smoothing_mode) == "fixed");
ollaPolicy = sixgr.link.resolveOLLAConfig(cfg);
assert(logical(ollaPolicy.Enabled));
assert(abs(double(ollaPolicy.ImpliedTargetBLER) - 0.1) < 1e-12);
assert(abs(double(ollaPolicy.ConfiguredTargetBLER) - 0.1) < 1e-12);
assert(logical(raw.rf_frontend.ul_power_control.require_measured_reference_rs));
assert(logical(raw.rf_frontend.ul_power_control.configured_snr_pathloss_forbidden));
assert(~logical(raw.rf_frontend.ul_power_control.enabled));
assert(~logical(raw.rf_frontend.ul_power_control.open_loop_enabled));
assert(double(raw.rf_frontend.ul_power_control.srs.p0_dbm) == -80);
assert(double(raw.rf_frontend.ul_power_control.srs.alpha) == 0.8);
assert(double(raw.rf_frontend.ul_power_control.srs.delta_tf_db) == 0);
assert(double(raw.rf_frontend.ul_power_control.srs.pcmax_dbm) == 23);
assert(double(cfg.rf.frontend.ul_power_control.srs.p0_dbm) == -80);
assert(double(cfg.rf.frontend.ul_power_control.srs.alpha) == 0.8);
assert(double(cfg.rf.frontend.ul_power_control.srs.delta_tf_db) == 0);
assert(double(cfg.rf.frontend.ul_power_control.srs.pcmax_dbm) == 23);
assert(logical(raw.run_control.raw_iq_capture_enable));
assert(logical(raw.run_control.raw_grid_capture_enable));
assert(logical(raw.output_control.save_plots));
assert(string(raw.output.artifact_contract_engine.catalog_scope) == ...
    "runtime_in_path");
assert(string(raw.output.artifact_contract_engine.image_format) == "none");
assert(string(raw.output.artifact_contract_engine.raster_authority) == ...
    "post_run_csv_contract_materializer");
assert(logical(raw.output.artifact_contract_engine.fail_on_missing_required));
assert(~logical(raw.output.artifact_contract_engine.allow_placeholder_evidence));
assert(logical(raw.output.profiler_enabled));

ok = true;
fprintf("[PASS] testTDDCausalWiringYAMLAuthority rows=%d exactRE=%d\n", ...
    height(allocations), sum(allocations.re_count));
end
