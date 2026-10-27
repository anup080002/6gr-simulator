function ok=testSRSPathPowerPolicy()
defaults=jsondecode(fileread('simulator/configs/defaults/top_level_required_sections_03.yaml'));
block=defaults.kpi_spec.srs_path_power;
policy=sixgr.lls6g.config.resolveSRSPathPowerPolicy(block);
absent=sixgr.lls6g.config.resolveSRSPathPowerPolicy();
assert(~policy.Enabled&&~absent.Enabled);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
s=scenario.toStruct(); original=s.reference_signals.srs;
s.kpi_spec.srs_path_power.enabled=true;
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.measurements.srsPathPower.Enabled&&isequaln(original,s.reference_signals.srs));
for mutation=1:5
    bad=block;
    switch mutation
        case 1, bad.enabled=1;
        case 2, bad.delay_max_us=bad.delay_min_us;
        case 3, bad.maximum_paths=1.5;
        case 4, bad=rmfield(bad,'noise_threshold_db');
        case 5, bad.assumed_antenna_connector=true;
    end
    rejected=false;
    try, sixgr.lls6g.config.resolveSRSPathPowerPolicy(bad);
    catch cause, rejected=strcmp(cause.identifier,'sixgr:lls6g:config:SRSPathPowerPolicy'); end
    assert(rejected,'test:SRSPathPolicyGuard','Malformed or invented measurement policy must fail.');
end
ok=true; fprintf('testSRSPathPowerPolicy PASS\n');
end
