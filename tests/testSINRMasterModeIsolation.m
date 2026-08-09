function ok = testSINRMasterModeIsolation()
%TESTSINRMASTERMODEISOLATION Keep the fixed sweep independent of geometry.

path = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "master_sinr_sweep.yaml");
scenario = sixgr.lls6g.config.loadScenarioConfig(path);
raw = scenario.toStruct();

assert(string(raw.validation.run_class) == "fixed_snr_sweep_lls");
assert(logical(raw.canonical_control.launch.sweep_enabled));
assert(logical(raw.sweeps_and_matrix.snr_sweep.enabled));
assert(~logical(raw.canonical_control.launch.geometry_enabled));
assert(~logical(raw.validation.geometry_evidence_required));
assert(numel(scenario.SourceFiles) == 1 && ...
    endsWith(lower(replace(string(scenario.SourceFiles(1)), "\", "/")), ...
    "/master_sinr_sweep.yaml"), ...
    "The SINR master must be self-contained and must not inherit geometry authority.");

bad = raw;
bad.canonical_control.launch.geometry_enabled = true;
localAssertError(@() sixgr.lls6g.config.validateScenarioConfig( ...
    bad, "Context", "sinr-master-geometry-conflict"), ...
    "sixgr:lls6g:config:RunClassFixedSNRSweepDisallowsGeometry");

ok = true;
end

function localAssertError(fn, identifier)
threw = false;
try
    fn();
catch cause
    threw = true;
    assert(string(cause.identifier) == string(identifier), ...
        "Expected %s, received %s.", identifier, cause.identifier);
end
assert(threw, "Expected %s.", identifier);
end
