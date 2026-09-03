function ok = testCausalWiringSharedDuplexAuthority()
%TESTCAUSALWIRINGSHAREDDUPLEXAUTHORITY Guard shared PHY authority for FDD/TDD.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
root = fileparts(fileparts(mfilename("fullpath")));
scenarioDir = fullfile(root, "simulator", "configs", "scenarios");
paths = [ ...
    fullfile(scenarioDir, "lls_causal_access_to_data_wiring.yaml"), ...
    fullfile(scenarioDir, "lls_causal_access_to_data_wiring_tdd.yaml")];
expectedDuplex = ["FDD", "TDD"];
cfgs = cell(1, numel(paths));

for idx = 1:numel(paths)
    scenario = sixgr.lls6g.config.loadScenarioConfig(paths(idx));
    raw = scenario.toStruct();
    cfgs{idx} = sixgr.lls6g.buildInternalConfig(scenario, string(tempname));
    cfg = cfgs{idx};
    assert(upper(string(raw.frequency.duplex_mode)) == expectedDuplex(idx));
    assert(upper(string(cfg.phy.duplex.mode)) == expectedDuplex(idx));
    monitoredFormats = string(cfg.phy.pdcch.dciFormats(:));
    monitoredFormats = erase(monitoredFormats, "DCI_");
    assert(all(ismember(["0_1"; "1_1"], monitoredFormats)), ...
        "%s causal profile must monitor the paired advanced UL/DL DCI formats.", ...
        expectedDuplex(idx));
    assert(isfield(cfg.phy, "schedulingTiming"), ...
        "%s must resolve a duplex-owned scheduling timing contract.", expectedDuplex(idx));
    assert(double(cfg.phy.schedulingTiming.timingAdvanceTicks) == 0, ...
        "%s must inherit an explicit zero timing-advance command, not omit timing authority.", ...
        expectedDuplex(idx));
    if expectedDuplex(idx) == "TDD"
        assert(double(raw.mimo.n_layers) == 1 && ...
            double(raw.mimo.max_dl_layers) == 2, ...
            "TDD active rank must remain distinct from rank capability.");
        assert(double(cfg.phy.pdsch.nLayers) == 1 && ...
            double(cfg.runtime.phy.dl.NumLayers) == 1, ...
            "TDD rank-one authority was overwritten by max_dl_layers.");
    end
    assert(logical(raw.rf_frontend.ul_power_control.require_measured_reference_rs));
    assert(logical(raw.rf_frontend.ul_power_control.configured_snr_pathloss_forbidden));
    assert(string(raw.rf_frontend.ul_power_control.tpc_source) == ...
        "decoded_control_event");
    assert(string(raw.rf_frontend.ul_power_control.tpc_mode) == "accumulation");
    assert(logical(raw.rf_frontend.ul_power_control.enabled));
    assert(logical(raw.rf_frontend.ul_power_control.open_loop_enabled));
    assert(~logical(raw.rf_frontend.ul_power_control.closed_loop_enabled));
    assert(logical(raw.rf_frontend.ul_power_control.phr_report_enabled));
    assert(logical(cfg.phy.pusch.powerControl.enabled));
    assert(logical(cfg.phy.pusch.powerControl.openLoopEnabled));
    assert(~logical(cfg.phy.pusch.powerControl.closedLoopEnabled));
    assert(logical(cfg.phy.pusch.powerControl.phrReportEnabled));
    assert(logical(cfg.phy.pusch.powerControl.requireMeasuredReferenceRS));
    assert(string(cfg.phy.pusch.powerControl.adjustmentMode) == "accumulated");
    assert(double(cfg.phy.pusch.powerControl.maxPathlossMeasurementAgeSlots) == ...
        double(raw.rf_frontend.ul_power_control.max_pathloss_measurement_age_slots));
    assert(logical(cfg.phy.pusch.power_control.require_measured_reference_rs));
    assert(string(cfg.phy.pusch.power_control.adjustment_mode) == "accumulated");
    assert(double(cfg.phy.pusch.power_control.max_pathloss_measurement_age_slots) == ...
        double(raw.rf_frontend.ul_power_control.max_pathloss_measurement_age_slots));
    assert(logical(cfg.powerAndRF.puschPowerControlEnabled));
    assert(string(raw.power_and_rf_frontend.downlink_power_normalization_policy) == ...
        "fixed_epre_over_configured_bwp" && ...
        string(raw.power_and_rf_frontend.uplink_power_normalization_policy) == ...
        "active_ofdm_total_power", ...
        "%s YAML must explicitly own the DL and UL power reference planes.", ...
        expectedDuplex(idx));
    assert(string(cfg.lls6g.resolvedConfig.power_and_rf_frontend.downlink_power_normalization_policy) == ...
        "fixed_epre_over_configured_bwp" && ...
        string(cfg.lls6g.resolvedConfig.power_and_rf_frontend.uplink_power_normalization_policy) == ...
        "active_ofdm_total_power", ...
        "%s runtime config lost the YAML-owned waveform power policy.", ...
        expectedDuplex(idx));
    assert(~logical(raw.pdsch.use_exact_flat_static_mimo_prg_estimator));
    assert(~logical(cfg.phy.pdsch.dmrs.useExactFlatStaticMIMOPRGEstimator), ...
        "%s must preserve the YAML-owned flat/static PRG-estimator policy.", ...
        expectedDuplex(idx));
    assert(double(cfg.phy.pusch.powerControl.p0PUSCH_dBm) == ...
        double(raw.rf_frontend.ul_power_control.pusch.p0_dbm));
    assert(double(cfg.phy.pusch.powerControl.alpha) == ...
        double(raw.rf_frontend.ul_power_control.pusch.alpha));
    assert(double(cfg.phy.pusch.powerControl.deltaTF_dB) == ...
        double(raw.rf_frontend.ul_power_control.pusch.delta_tf_db));
    assert(double(cfg.phy.pusch.powerControl.pcmax_dBm) == ...
        double(raw.rf_frontend.ul_power_control.pusch.pcmax_dbm));
    assert(double(cfg.rf.frontend.configuration_epoch) == 1);
    ollaPolicy = sixgr.link.resolveOLLAConfig(cfg);
    assert(logical(ollaPolicy.Enabled), ...
        "%s causal profile must execute ACK/NACK-driven OLLA.", expectedDuplex(idx));
    assert(abs(double(ollaPolicy.ImpliedTargetBLER) - 0.1) < 1e-12, ...
        "%s OLLA steps must implement the configured 10%% BLER equilibrium.", expectedDuplex(idx));
    channels = ["pusch", "pucch", "srs", "prach"];
    for channel = channels
        rawPc = raw.rf_frontend.ul_power_control.(char(channel));
        cfgPc = cfg.rf.frontend.ul_power_control.(char(channel));
        assert(double(cfgPc.p0_dbm) == double(rawPc.p0_dbm));
        assert(double(cfgPc.alpha) == double(rawPc.alpha));
        assert(double(cfgPc.delta_tf_db) == double(rawPc.delta_tf_db));
        assert(double(cfgPc.pcmax_dbm) == double(rawPc.pcmax_dbm));
    end
end

% Duplex selection changes legal occasions, not the PHY/power equations.
for channel = ["pusch", "pucch", "srs", "prach"]
    fddPc = cfgs{1}.rf.frontend.ul_power_control.(char(channel));
    tddPc = cfgs{2}.rf.frontend.ul_power_control.(char(channel));
    assert(isequaln(fddPc, tddPc));
end
assert(~isfield(cfgs{1}.phy.duplex, "tddCommon"));
assert(isfield(cfgs{2}.phy.duplex, "tddCommon"));
assert(string(cfgs{1}.lls6g.scheduling_timing_source) == "scheduling_timing", ...
    "FDD must resolve timing from scheduling_timing YAML authority.");
assert(string(cfgs{2}.lls6g.scheduling_timing_source) == "tdd_timing", ...
    "TDD must resolve timing from tdd_timing YAML authority.");
assert(cfgs{2}.run.totalSlots == 25);
assert(cfgs{2}.run.measurementSlots == 25);

ok = true;
fprintf("[PASS] testCausalWiringSharedDuplexAuthority FDD/TDD common PHY authority retained.\n");
end
