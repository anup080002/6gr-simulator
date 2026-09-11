function ok = testTDDCausalWiringShortYAMLAuthority()
%TESTTDDCAUSALWIRINGSHORTYAMLAUTHORITY Guard the bounded TDD child profile.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
root = fileparts(fileparts(mfilename("fullpath")));
scenarioPath = fullfile(root, "simulator", "configs", "scenarios", ...
    "lls_causal_access_to_data_wiring_tdd_short.yaml");
scenario = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
raw = scenario.toStruct();

assert(string(raw.meta.scenario_id) == ...
    "lls_causal_access_to_data_wiring_tdd_short");
assert(string(raw.frequency.duplex_mode) == "TDD");
assert(string(raw.global_radio_scope.duplex_mode) == "TDD");
assert(double(raw.run_control.total_slots) == 58);
assert(double(raw.run_control.measurement_slots) == 58);
assert(double(raw.simulation.n_frames) == 5);
assert(double(raw.simulation.n_slots) == 58);
assert(double(raw.random_access.num_slots) == 58);
assert(string(raw.canonical_control.integration.run_mode) == "FIXED_SNR_SWEEP");
assert(logical(raw.canonical_control.integration.configured_snr_is_link_authority));
assert(string(raw.simulation.noise_operating_mode) == "standalone_awgn_snr_argument");
assert(double(raw.simulation.snr_db) == 12);
assert(~logical(raw.simulation.reference_sweep_enabled));
assert(~logical(raw.simulation.adaptive_sweep_enabled));
assert(~logical(raw.channels.pathloss_enabled));
assert(logical(raw.channels.normalize_path_gains));
assert(string(raw.channels.o2i_model) == "none");
assert(double(raw.frequency.bandwidth_hz) == 5e6);
assert(double(raw.frequency.n_size_grid) == 25);
assert(logical(raw.initial_access.enabled));
assert(logical(raw.reference_signals.ssb_enabled));
assert(logical(raw.reference_signals.csi_rs_enabled));
assert(logical(raw.reference_signals.srs_enabled));
assert(logical(raw.reference_signals.trs_enabled));
assert(double(raw.control_gating.trs_max_age_slots) == 10);
assert(logical(raw.mimo.beam_sweep_enabled));
assert(~logical(raw.channels.normalize_channel_outputs));
assert(logical(raw.link_adaptation.inner_loop_flag));
assert(logical(raw.link_adaptation.outer_loop_flag));
assert(logical(raw.output.save_csv));
assert(logical(raw.output.save_mat));
assert(logical(raw.output.save_png));
assert(logical(raw.output.save_figures));
assert(logical(raw.output.phy_signal_diagnostic_enabled));
assert(logical(raw.run_control.raw_iq_capture_enable));
assert(logical(raw.run_control.raw_grid_capture_enable));
assert(~logical(raw.output.emit_placeholder_artifacts));
assert(logical(raw.output.artifact_contract_engine.truth_only));
assert(~logical(raw.output.artifact_contract_engine.allow_placeholder_evidence));

cfg = sixgr.lls6g.buildInternalConfig(scenario, string(tempname));
assert(string(cfg.phy.duplex.mode) == "TDD");
assert(isfield(cfg.phy.duplex, "tddCommon"));
assert(~isfield(cfg.phy.duplex, "fdd"));
assert(double(cfg.run.totalSlots) == 58);
assert(double(cfg.run.measurementSlots) == 58);
assert(double(cfg.phy.carrier.NSizeGrid) == 25);
assert(~logical(cfg.channel.normalizeChannelOutputs));
assert(double(cfg.phy.trs.period_slots) == 10);
assert(double(cfg.run.controlGating.trsMaxAgeSlots) >= ...
    double(cfg.phy.trs.period_slots));
assert(sixgr.channel.ChannelFactory.supportsDynamicRuntimeTDDReciprocity(cfg));

frame = sixgr.phy.FrameStructureEngine(cfg, "FrameCoreOnly", true);
assert(frame.DuplexMode == "TDD");
for slot0 = [0 1 2 5 6 7 10 11 12]
    assert(frame.IsDLSlot(slot0) && ~frame.IsULSlot(slot0));
end
for slot0 = [4 9 14]
    assert(frame.IsULSlot(slot0) && ~frame.IsDLSlot(slot0));
end
for slot0 = [3 8 13]
    assert(frame.IsDLSlot(slot0) && frame.IsULSlot(slot0));
end

[allocations, checks] = sixgr.truth.buildPlannedREAllocation(cfg);
sixgr.truth.assertAllocationPreflight(checks);
enabled = logical(checks.enabled);
assert(all(checks.resolved(enabled)));
assert(all(checks.status(enabled) == "PASS"));
assert(all(checks.exact_re_count(enabled) > 0));
assert(~isempty(allocations));

ok = true;
fprintf("[PASS] testTDDCausalWiringShortYAMLAuthority rows=%d exactRE=%d\n", ...
    height(allocations), sum(allocations.re_count));
end
