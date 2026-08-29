function ok = testTDDCausalWiringYAMLAuthority()
%TESTTDDCAUSALWIRINGYAMLAUTHORITY Guard the compact TDD wiring profile.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
root = fileparts(fileparts(mfilename("fullpath")));
scenarioPath = fullfile(root, "simulator", "configs", "scenarios", ...
    "lls_causal_access_to_data_wiring_tdd.yaml");
scenario = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
raw = scenario.toStruct();

assert(string(raw.canonical_control.integration.run_mode) == ...
    "GEOMETRY_NETWORK");
assert(double(raw.canonical_control.integration.configuration_epoch) == 1);
assert(string(raw.canonical_control.integration.subprofile) == "connected_network");
assert(logical(raw.canonical_control.launch.geometry_enabled));
assert(~logical(raw.canonical_control.launch.sweep_enabled));
assert(~logical(raw.canonical_control.integration.configured_snr_is_link_authority));
assert(string(raw.frequency.duplex_mode) == "TDD");
assert(string(raw.global_radio_scope.duplex_mode) == "TDD");
assert(~isfield(raw.frequency, "dl_center_frequency_hz"));
assert(~isfield(raw.frequency, "ul_center_frequency_hz"));
assert(double(raw.frequency.center_frequency_hz) == 2.35e9);
assert(double(raw.frequency.bandwidth_hz) == 5e6);
assert(double(raw.frequency.n_size_grid) == 25);
assert(double(raw.global_radio_scope.fft_size) == 512);
assert(double(raw.global_radio_scope.sample_rate_hz) == 7.68e6);
assert(double(raw.tdd_timing.n1_pdsch_processing_time_symbols) == 8);
assert(double(raw.tdd_timing.n2_pusch_preparation_time_symbols) == 10);
assert(double(raw.run_control.total_slots) == 15);
assert(double(raw.run_control.measurement_slots) == 15);
assert(double(raw.link_adaptation.feedback_delay_slots) == 1);
assert(~logical(raw.random_access.statistical_qualification.enabled));
assert(string(raw.validation.strict_component_evidence.execution_scope) == ...
    "in_path");
assert(all(ismember(["prach","srs","trs","sib1"], ...
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
assert(double(cfg.run.totalSlots) == 15);
assert(double(cfg.run.measurementSlots) == 15);
assert(double(cfg.phy.linkAdaptation.feedbackDelaySlots) == 1);
assert(double(cfg.phy.csi.feedbackDelaySlots) == 1);
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
assert(isequal(double(raw.reference_signals.trs.slot_numbers(:)).', [2 7]));
assert(frame.IsDLSlot(1) && frame.IsULSlot(4));
assert(all(arrayfun(@(slot0) frame.IsDLSlot(slot0), ...
    double(raw.reference_signals.trs.slot_numbers))));
assert(logical(raw.pucch_resources.overlap_policy.uci_on_pusch_enabled));
assert(isequal(double(raw.control.search_space_num_candidates(:)).', ...
    [4 2 1 1 0]));
assert(double(raw.pucch_resources.resources(2).occ_length) == 2);
assert(logical(raw.link_adaptation.inner_loop_flag));
assert(logical(raw.link_adaptation.outer_loop_flag));
assert(logical(raw.rf_frontend.ul_power_control.require_measured_reference_rs));
assert(logical(raw.rf_frontend.ul_power_control.configured_snr_pathloss_forbidden));
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

ok = true;
fprintf("[PASS] testTDDCausalWiringYAMLAuthority rows=%d exactRE=%d\n", ...
    height(allocations), sum(allocations.re_count));
end
