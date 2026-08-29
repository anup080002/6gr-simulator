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
    assert(logical(raw.rf_frontend.ul_power_control.require_measured_reference_rs));
    assert(logical(raw.rf_frontend.ul_power_control.configured_snr_pathloss_forbidden));
    assert(string(raw.rf_frontend.ul_power_control.tpc_source) == ...
        "decoded_control_event");
    assert(string(raw.rf_frontend.ul_power_control.tpc_mode) == "accumulation");
    assert(double(cfg.rf.frontend.configuration_epoch) == 1);
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
assert(cfgs{2}.run.totalSlots == 15);
assert(cfgs{2}.run.measurementSlots == 15);

ok = true;
fprintf("[PASS] testCausalWiringSharedDuplexAuthority FDD/TDD common PHY authority retained.\n");
end
