function ok = testCoupledTruthExecutionProfileAuthority()
%TESTCOUPLEDTRUTHEXECUTIONPROFILEAUTHORITY Preserve scheduler ownership.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "lls_causal_access_to_data_wiring.yaml");
scenario = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
resolved = scenario.toStruct();

cfg = sixgr.lls6g.buildInternalConfig(resolved, tempdir);
assert(string(sixgr.util.structGet(cfg, ...
    "phy.pdsch.executionProfile", "")) == "scheduler_truth");
assert(string(sixgr.util.structGet(cfg, ...
    "run.pdschExecutionProfile", "")) == "scheduler_truth");
assert(string(sixgr.util.structGet(cfg, ...
    "phy.pusch.executionProfile", "")) == "scheduler_truth");
assert(string(sixgr.util.structGet(cfg, ...
    "run.puschExecutionProfile", "")) == "scheduler_truth");

badDL = resolved;
badDL.pdsch.execution_profile = "phy_calibration";
localAssertIdentifier(@() sixgr.lls6g.buildInternalConfig( ...
    badDL, tempdir), ...
    "sixgr:lls6g:config:CoupledTruthPDSCHExecutionProfile");

badUL = resolved;
badUL.pusch.execution_profile = "phy_calibration";
localAssertIdentifier(@() sixgr.lls6g.buildInternalConfig( ...
    badUL, tempdir), ...
    "sixgr:lls6g:config:CoupledTruthPUSCHExecutionProfile");

fprintf([ ...
    'Coupled truth execution-profile authority: scheduler-owned DL/UL ' ...
    'profiles resolved and two conflict guards passed.\n']);
ok = true;
end

function localAssertIdentifier(fcn, expected)
try
    fcn();
catch ME
    assert(strcmp(ME.identifier, expected), ...
        "Expected %s, received %s (%s).", ...
        expected, ME.identifier, ME.message);
    return;
end
error("Expected %s, but no error was thrown.", expected);
end
