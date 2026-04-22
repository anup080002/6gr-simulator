function ok = testPRACHRunnerIntegration()
%TESTPRACHRUNNERINTEGRATION Short integration test for config->runner->artifact PRACH flow.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
cleanupObj = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

repoRoot = fileparts(fileparts(mfilename("fullpath")));
baseScenario = strrep(fullfile(repoRoot, "simulator", "configs", "scenarios", "prach_detection.yaml"), "\", "/");
scenarioPath = fullfile(tmp, "prach_runner_smoke.yaml");
scenarioCfg = struct();
scenarioCfg.inherits = {baseScenario};
scenarioCfg.meta = struct( ...
    "scenario_id", "prach_runner_smoke", ...
    "description", "Short PRACH runner integration smoke.");
scenarioCfg.simulation = struct( ...
    "monte_carlo_iterations", 1, ...
    "snr_db", 18);
scenarioCfg.random_access = struct( ...
    "min_detection_trials", 1, ...
    "num_prach_occasions", 1, ...
    "num_slots", 40, ...
    "num_subframes", 20, ...
    "snr_sweep_db", 18, ...
    "threshold_sweep", 0.5, ...
    "detection_threshold", 0.5, ...
    "active_preamble_pattern", 1);
localWriteJSON(scenarioPath, scenarioCfg);

out = sixgr.lls6g.runners.runSingle(scenarioPath, tmp, "prach_runner_smoke");
assert(logical(out.Ok), "PRACH runner integration smoke must complete successfully.");

runFolder = char(out.RunFolder);
ctrlPath = fullfile(runFolder, "control", "csv", "prach_trials.csv");
airPath = fullfile(runFolder, "air_interface", "csv", "prach_trials.csv");
reportPath = fullfile(runFolder, "reports", "csv", "initial_access_random_access_outputs.csv");
summaryBySNRPath = fullfile(runFolder, "reports", "csv", "prach_summary_by_snr.csv");
corrPath = fullfile(runFolder, "reports", "csv", "prach_correlation_traces.csv");
rawTrialPath = fullfile(runFolder, "control", "csv", "prach_detection_trials.csv");

assert(exist(ctrlPath, "file") == 2, "Runner must export control/csv/prach_trials.csv.");
assert(exist(airPath, "file") == 2, "Runner must export air_interface/csv/prach_trials.csv.");
assert(exist(reportPath, "file") == 2, "Runner must export reports/csv/initial_access_random_access_outputs.csv.");
assert(exist(summaryBySNRPath, "file") == 2, "Runner must export reports/csv/prach_summary_by_snr.csv.");
assert(exist(corrPath, "file") == 2, "Runner must export reports/csv/prach_correlation_traces.csv.");
assert(exist(rawTrialPath, "file") == 2, "Runner must preserve control/csv/prach_detection_trials.csv.");

ctrlT = readtable(ctrlPath, "VariableNamingRule", "preserve");
airT = readtable(airPath, "VariableNamingRule", "preserve");
reportT = readtable(reportPath, "VariableNamingRule", "preserve");
summaryBySNRT = readtable(summaryBySNRPath, "VariableNamingRule", "preserve");
corrT = readtable(corrPath, "VariableNamingRule", "preserve");

assert(~isempty(ctrlT), "PRACH control trial export must not be empty.");
assert(~isempty(airT), "PRACH air-interface trial export must not be empty.");
assert(~isempty(reportT), "PRACH report summary export must not be empty.");
assert(~isempty(summaryBySNRT), "PRACH summary-by-SNR export must not be empty.");
assert(~isempty(corrT), "PRACH correlation trace export must not be empty.");
assert(all(ismember(["Status","ComputeLatency_ms","AirInterfaceObservation_ms","AcquisitionTime_ms", ...
    "CRCPass","TrueTimingOffset_samples","DetectionMetric","FalseAlarmFlag","CollisionFlag"], ...
    string(ctrlT.Properties.VariableNames))), ...
    "PRACH control export must include truthful control and detection semantics.");
assert(all(ismember(["CategoryKey","MetricKey","Availability","SourceArtifact"], ...
    string(reportT.Properties.VariableNames))), ...
    "PRACH report metric table must expose category/metric/source semantics.");
assert(all(ismember(["DetectionProbability","FalseAlarmProbability","MissDetectionProbability"], ...
    string(summaryBySNRT.Properties.VariableNames))), ...
    "PRACH summary-by-SNR export must expose the core PRACH KPIs.");
assert(all(ismember(["DetectionMetric","Status","SourceArtifact"], string(corrT.Properties.VariableNames))), ...
    "PRACH correlation trace export must expose plot-ready trace columns.");

ok = true;
end

function localWriteJSON(filePath, s)
fid = fopen(filePath, "w");
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s", jsonencode(s));
end
