function ok = testSLSWaveformTruthScaleValidation()
%TESTSLSWAVEFORMTRUTHSCALEVALIDATION Outcome-level guard for bounded system waveform truth scale profile.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "variants", ...
    "SCN00_BOUNDED_WAVEFORM_TRUTH_SCALE.yaml");
assert(exist(scenarioPath, "file") == 2, "Missing bounded waveform truth scale profile.");

scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, tmp);

assert(string(scfg.get("scenario.runner_profile")) == "system_level_lls", ...
    "Bounded scale validation must use the system-level LLS runner.");
assert(string(scfg.get("scenario.scale_profile")) == "bounded_multicell_waveform_truth_validation", ...
    "Scale profile must be explicit in the scenario config.");
assert(double(scfg.get("frequency.center_frequency_hz")) == 4.0e9, "Center frequency mismatch.");
assert(double(scfg.get("frequency.bandwidth_hz")) == 100.0e6, "Bandwidth mismatch.");
assert(string(scfg.get("frequency.duplex_mode")) == "TDD", "Duplex mode mismatch.");
assert(double(scfg.get("frame.scs_khz")) == 30, "SCS mismatch.");
assert(double(scfg.get("deployment_topology.num_cells")) == 6, "Bounded profile cell count mismatch.");
assert(double(scfg.get("deployment_topology.num_ues")) == 18, "Bounded profile UE count mismatch.");
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "system.phyBackend", ""))), "waveform"), ...
    "Bounded scale validation must keep waveform PHY active.");

out = run_6g_phy_lls_single(scenarioPath, tmp, "sls_waveform_truth_scale_validation");
assert(out.Ok, "Bounded system waveform truth scale validation should complete.");

runFolder = char(string(out.RunFolder));
requiredFiles = { ...
    fullfile(runFolder, "reports", "csv", "runtime_operating_mode.csv"), ...
    fullfile(runFolder, "reports", "csv", "system_waveform_scale_profile.csv"), ...
    fullfile(runFolder, "reports", "csv", "system_waveform_runtime_profile.csv"), ...
    fullfile(runFolder, "reports", "csv", "truth_primary_artifact_scan.csv"), ...
    fullfile(runFolder, "reports", "csv", "runtime_profiler_summary.csv"), ...
    fullfile(runFolder, "reports", "csv", "runtime_function_profile.csv"), ...
    fullfile(runFolder, "reports", "csv", "runtime_function_call_edges.csv"), ...
    fullfile(runFolder, "packet_flow", "csv", "live_dl_scheduler_grants.csv"), ...
    fullfile(runFolder, "packet_flow", "csv", "live_ul_scheduler_grants.csv"), ...
    fullfile(runFolder, "air_interface", "csv", "dl_pdsch_trials.csv"), ...
    fullfile(runFolder, "air_interface", "csv", "ul_pusch_trials.csv")};
for i = 1:numel(requiredFiles)
    assert(exist(requiredFiles{i}, "file") == 2, "Missing scale-validation artifact: %s", requiredFiles{i});
end

runtimeT = localReadCanonicalTable(fullfile(runFolder, "reports", "csv", "runtime_operating_mode.csv"));
assert(all(strcmpi(string(runtimeT.ExecutionBackend), "WAVEFORM_SYSTEM_PHY")), ...
    "Runtime operating mode must stay on waveform system PHY.");
assert(all(logical(runtimeT.WaveformPHYActive)), "Waveform PHY must be active.");
assert(~any(logical(runtimeT.ProxyPHYActive)), "Proxy PHY must not be active.");
assert(~any(logical(runtimeT.FallbackUsed)), "Fallback must not be active.");

scaleT = localReadCanonicalTable(fullfile(runFolder, "reports", "csv", "system_waveform_scale_profile.csv"));
assert(height(scaleT) == 1, "Scale profile table must contain one run-level row.");
assert(string(scaleT.ScaleProfileName(1)) == "bounded_multicell_waveform_truth_validation", ...
    "Scale profile name must be preserved in output.");
assert(string(scaleT.ScaleCategory(1)) == "bounded_multicell", "Scale category must identify multicell validation.");
assert(double(scaleT.NumCells(1)) == 6, "Scale profile must report actual bounded cell count.");
assert(double(scaleT.NumUEs(1)) == 18, "Scale profile must report actual bounded UE count.");
assert(double(scaleT.TotalSlots(1)) == 2, "Scale profile must report the bounded slot count.");
assert(double(scaleT.DLRawTrialRows(1)) + double(scaleT.ULRawTrialRows(1)) > 0, ...
    "Scale profile must be backed by raw waveform trial rows.");

profileT = localReadCanonicalTable(fullfile(runFolder, "reports", "csv", "system_waveform_runtime_profile.csv"));
assert(height(profileT) == 1, "Runtime profile table must contain one run-level row.");
assert(double(profileT.SystemRunnerElapsed_s(1)) > 0, "Runtime profile must publish measured elapsed time.");
assert(double(profileT.SlotsPerSecond(1)) > 0, "Runtime profile must publish measured slots-per-second.");
assert(logical(profileT.MATLABProfilerRequested(1)), "Bounded scale profile must request MATLAB profiling.");
assert(strcmpi(string(profileT.TruthModePolicy(1)), "strict_waveform_only"), ...
    "Runtime profile must preserve strict waveform truth policy.");

profilerT = localReadCanonicalTable(fullfile(runFolder, "reports", "csv", "runtime_profiler_summary.csv"));
assert(height(profilerT) == 1, "Profiler summary must contain one captured session row.");
assert(double(profilerT.ExportedFunctionCount(1)) > 0, "Profiler summary must export at least one function row.");

scanT = localReadCanonicalTable(fullfile(runFolder, "reports", "csv", "truth_primary_artifact_scan.csv"));
assert(~isempty(scanT), "Truth artifact scan must inspect primary artifacts.");
assert(all(double(scanT.IssueCount) == 0), "Truth artifact scan found forbidden active markers.");
assert(any(contains(string(scanT.File), "system_waveform_runtime_profile.csv")), ...
    "Truth artifact scan must include the runtime profile artifact.");
assert(any(contains(string(scanT.File), "live_dl_scheduler_grants.csv")) || ...
       any(contains(string(scanT.File), "live_ul_scheduler_grants.csv")), ...
    "Truth artifact scan must include system scheduler grant artifacts.");

ok = true;
end

function T = localReadCanonicalTable(pathStr)
opts = detectImportOptions(pathStr, "Delimiter", ",");
opts.VariableNamingRule = "preserve";
T = readtable(pathStr, opts);
end
