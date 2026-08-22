function ok = testULPUSCHThroughputExecutionContract()
%TESTULPUSCHTHROUGHPUTEXECUTIONCONTRACT Guard UL execution ownership.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
cfg = sixgr.config.defaultConfig();
cfg.phy.pusch.enable = false;

cfgCalibration = cfg;
cfgCalibration.phy.pusch.executionProfile = "phy_calibration";
cfgCalibration.run.puschExecutionProfile = "phy_calibration";
localAssertIdentifier(@() sixgr.link.runULPUSCHThroughput( ...
    cfgCalibration, "ExecutionProfile", "phy_calibration", ...
    "GrantSnapshot", struct("TBSBits", 128), "NumFrames", 1), ...
    "sixgr:pusch:CalibrationSchedulerOwnershipForbidden");

cfgConflict = cfg;
cfgConflict.phy.pusch.executionProfile = "scheduler_truth";
cfgConflict.run.puschExecutionProfile = "phy_calibration";
localAssertIdentifier(@() sixgr.link.runULPUSCHThroughput( ...
    cfgConflict, "NumFrames", 1), ...
    "sixgr:pusch:ExecutionProfileMismatch");

cfgScheduler = cfg;
cfgScheduler.phy.pusch.executionProfile = "scheduler_truth";
cfgScheduler.run.puschExecutionProfile = "scheduler_truth";
localAssertIdentifier(@() sixgr.link.runULPUSCHThroughput( ...
    cfgScheduler, "ExecutionProfile", "scheduler_truth", "NumFrames", 1), ...
    "sixgr:pusch:MissingSchedulerTruthGrant");
localAssertIdentifier(@() sixgr.link.runULPUSCHThroughput( ...
    cfgScheduler, "ExecutionProfile", "scheduler_truth", ...
    "GrantSnapshot", struct("TBSBits", 128), "NumFrames", 1), ...
    "sixgr:pusch:SchedulerTruthGrantNotFeasible");

calibration = sixgr.link.runULPUSCHThroughput( ...
    cfgCalibration, "ExecutionProfile", "phy_calibration", "NumFrames", 1);
assert(calibration.Ok && calibration.Skipped);
assert(string(calibration.ExecutionProfile) == "phy_calibration");
assert(string(calibration.ExecutionTaxonomy) == "isolated_phy_calibration");
assert(string(calibration.ApproximationMode) == "none");

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "lls_causal_access_to_data_wiring.yaml");
scenario = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
runtimeCfg = sixgr.lls6g.buildInternalConfig(scenario, tempdir);
assert(string(sixgr.util.structGet(runtimeCfg, ...
    "phy.pusch.executionProfile", "")) == "scheduler_truth");
assert(string(sixgr.util.structGet(runtimeCfg, ...
    "run.puschExecutionProfile", "")) == "scheduler_truth");

seed = struct("Slot", 1, "DCI", struct("Format", "0_1"));
job = sixgr.truth.buildGrantPHYJob(runtimeCfg, "UL", 20, 1, ...
    struct(), struct("GrantSnapshot", seed));
assert(string(job.ExecutionProfile) == "scheduler_truth", ...
    "UL scheduler jobs must carry the same explicit ownership as DL jobs.");

ok = true;
end

function localAssertIdentifier(fcn, expected)
try
    fcn();
catch ME
    assert(strcmp(ME.identifier, expected), ...
        "Expected %s, received %s (%s).", expected, ME.identifier, ME.message);
    return;
end
error("Expected %s, but no error was thrown.", expected);
end
