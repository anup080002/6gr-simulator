function ok = testPRACHRunnerIntegration()
%TESTPRACHRUNNERINTEGRATION Short integration test for config->runner->artifact PRACH flow.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
cleanupObj = onCleanup(@() rmdir(tmp, "s"));

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
    "snr_sweep_db", [12 18], ...
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
corrPath = fullfile(runFolder, "reports", "csv", "prach_correlation_trace.csv");
corrLegacyPath = fullfile(runFolder, "reports", "csv", "prach_correlation_traces.csv");
probabilitySweepPath = fullfile(runFolder, "reports", "csv", "prach_probability_sweeps.csv");
rawTrialPath = fullfile(runFolder, "control", "csv", "prach_detection_trials.csv");
evidencePath = fullfile(runFolder, "reports", "csv", "runtime_config_application_evidence.csv");
bindingPath = fullfile(runFolder, "reports", "csv", "parameter_binding_matrix.csv");
surfacePath = fullfile(runFolder, "reports", "csv", "browser_config_surface_matrix.csv");
featureIndexPath = fullfile(runFolder, "reports", "csv", "feature_parameter_index.csv");

assert(exist(ctrlPath, "file") == 2, "Runner must export control/csv/prach_trials.csv.");
assert(exist(airPath, "file") == 2, "Runner must export air_interface/csv/prach_trials.csv.");
assert(exist(reportPath, "file") == 2, "Runner must export reports/csv/initial_access_random_access_outputs.csv.");
assert(exist(summaryBySNRPath, "file") == 2, "Runner must export reports/csv/prach_summary_by_snr.csv.");
assert(exist(corrPath, "file") == 2, "Runner must export reports/csv/prach_correlation_trace.csv.");
assert(exist(corrLegacyPath, "file") == 2, "Runner must preserve legacy reports/csv/prach_correlation_traces.csv mirror.");
assert(exist(probabilitySweepPath, "file") == 2, "Runner must export probability sweeps when a real PRACH sweep axis exists.");
assert(exist(rawTrialPath, "file") == 2, "Runner must preserve control/csv/prach_detection_trials.csv.");
assert(exist(evidencePath, "file") == 2, "Runner must export reports/csv/runtime_config_application_evidence.csv.");
assert(exist(bindingPath, "file") == 2, "Runner must export reports/csv/parameter_binding_matrix.csv.");
assert(exist(surfacePath, "file") == 2, "Runner must export reports/csv/browser_config_surface_matrix.csv.");
assert(exist(featureIndexPath, "file") == 2, "Runner must export reports/csv/feature_parameter_index.csv.");

ctrlT = readtable(ctrlPath, "VariableNamingRule", "preserve");
airT = readtable(airPath, "VariableNamingRule", "preserve");
reportT = readtable(reportPath, "VariableNamingRule", "preserve");
summaryBySNRT = readtable(summaryBySNRPath, "VariableNamingRule", "preserve");
corrT = readtable(corrPath, "VariableNamingRule", "preserve");
corrLegacyT = readtable(corrLegacyPath, "VariableNamingRule", "preserve");
probabilitySweepT = readtable(probabilitySweepPath, "VariableNamingRule", "preserve");
evidenceT = readtable(evidencePath, "VariableNamingRule", "preserve");
bindingT = readtable(bindingPath, "VariableNamingRule", "preserve");
surfaceT = readtable(surfacePath, "VariableNamingRule", "preserve");
featureIndexT = readtable(featureIndexPath, "VariableNamingRule", "preserve");

assert(~isempty(ctrlT), "PRACH control trial export must not be empty.");
assert(~isempty(airT), "PRACH air-interface trial export must not be empty.");
assert(~isempty(reportT), "PRACH report summary export must not be empty.");
assert(~isempty(summaryBySNRT), "PRACH summary-by-SNR export must not be empty.");
assert(~isempty(corrT), "PRACH correlation trace export must not be empty.");
assert(isequaln(corrT, corrLegacyT), ...
    "Legacy PRACH correlation trace CSV must mirror the canonical lag-domain table.");
assert(~isempty(probabilitySweepT), "PRACH probability sweep export must not be empty for a two-point SNR sweep.");
assert(~isempty(evidenceT), "PRACH runner must publish real runtime config-application evidence.");
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
assert(all(ismember(localCorrelationTraceColumns(), string(corrT.Properties.VariableNames))), ...
    "PRACH correlation trace export must expose the canonical lag-domain trace schema.");
assert(any(isfinite(double(corrT.lag_samples))) && any(isfinite(double(corrT.correlation_abs))), ...
    "PRACH correlation trace export must contain finite lag and correlation-magnitude samples.");
assert(all(string(corrT.truth_status) == "real_lls_evidence"), ...
    "PRACH correlation trace rows produced by the runner must be measured LLS evidence.");
assert(all(ismember(["sweep_axis","x_value","n_trials","detection_probability", ...
    "miss_detection_probability","false_alarm_probability","truth_status"], ...
    string(probabilitySweepT.Properties.VariableNames))), ...
    "PRACH probability sweep export must expose detection, miss, and false-alarm probability columns.");
assert(any(string(probabilitySweepT.sweep_axis) == "SNR_dB"), ...
    "PRACH probability sweep export must include SNR_dB when snr_sweep_db has multiple values.");
assert(any(strcmp(string(evidenceT.ParameterId), "random_access.configuration_index") & ...
    strcmp(string(evidenceT.ConsumerFunction), "sixgr.rach.PRACHConfig")), ...
    "PRACH runtime evidence must prove configuration_index was applied by PRACHConfig.");
assert(any(strcmp(string(evidenceT.ParameterId), "random_access.detection_threshold") & ...
    strcmp(string(evidenceT.EvidenceStatus), "applied_to_runtime_object")), ...
    "PRACH runtime evidence must prove detection_threshold was applied by the active detector path.");
assert(any(strcmp(string(bindingT.ParameterId), "random_access.configuration_index") & ...
    strcmp(string(bindingT.FinalBindingStatus), "browser_to_runtime_applied")), ...
    "PRACH binding matrix must mark configuration_index as runtime applied.");
assert(any(strcmp(string(surfaceT.ParameterId), "random_access.configuration_index") & ...
    strcmp(string(surfaceT.ApplicationStatus), "applied_to_runtime_object")), ...
    "Browser surface matrix must expose PRACH configuration_index as runtime applied.");
assert(any(strcmp(string(featureIndexT.FeatureFamily), "Random_Access_PRACH")), ...
    "Feature index must include the PRACH family.");

ok = true;
end

function localWriteJSON(filePath, s)
fid = fopen(filePath, "w");
cleanupObj = onCleanup(@() fclose(fid));
fprintf(fid, "%s", jsonencode(s));
end

function cols = localCorrelationTraceColumns()
cols = ["trial_id","preamble_index","root_sequence_index","restricted_set_type","n_cs", ...
    "zero_correlation_zone_config","lag_samples","lag_us","correlation_abs","threshold", ...
    "noise_floor","peak_lag_samples","timing_advance_samples","detection_result", ...
    "false_alarm","missed_detection","snr_db","cfo_hz","seed","truth_status"];
end
