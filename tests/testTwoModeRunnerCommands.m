function testTwoModeRunnerCommands()
%TESTTWOMODERUNNERCOMMANDS Verify two-mode command surfaces and smoke plan wiring.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

tmp = fullfile(tempdir, "sixgr_two_mode_runner_commands");
if exist(tmp, "dir") == 7
    rmdir(tmp, "s");
end
cleanup = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>

smoke = run_two_mode_lls_smoke("PrepareOnly", true, "ResultsRoot", tmp, "WriteSummary", false, "Verbose", false);
assert(smoke.Ok && smoke.Prepared, "Smoke command must support PrepareOnly planning.");
assert(numel(smoke.Runs) == 2, "Smoke plan must include the fixed sweep and geometry scenarios.");
assert(string(smoke.SummaryCSV) == string(fullfile(tmp, "two_mode_smoke_summary.csv")), ...
    "Smoke summary path must resolve under the requested results root.");

snrPlan = smoke.Runs(1);
assert(endsWith(string(snrPlan.BaseScenarioYAML), "lls_true_snr_sweep_awgn_1ue.yaml"), ...
    "Smoke fixed-link plan must target the fixed SNR sweep scenario.");
assert(logical(snrPlan.OverrideApplied), "Smoke fixed-link plan must use a runtime override wrapper.");
assert(any(string(snrPlan.OverridePaths) == "sweeps_and_matrix.fixed_link_calibration.min_trials"), ...
    "Smoke fixed-link plan must reduce min_trials through runtime override.");
assert(any(string(snrPlan.OverridePaths) == "sweeps_and_matrix.fixed_link_calibration.max_trials"), ...
    "Smoke fixed-link plan must reduce max_trials through runtime override.");
assert(any(string(snrPlan.OverridePaths) == "sweeps_and_matrix.fixed_link_calibration.trials_per_drop"), ...
    "Smoke fixed-link plan must reduce trials_per_drop through runtime override.");
assert(any(string(snrPlan.OverridePaths) == "sweeps_and_matrix.snr_sweep.values_db"), ...
    "Smoke fixed-link plan must force the short SNR grid.");
assert(endsWith(string(snrPlan.RuntimeScenarioYAML), ...
    "lls_true_snr_sweep_awgn_1ue_smoke.yaml"), ...
    "Smoke fixed-link policy must live in the checked-in smoke YAML.");
assert(any(string(snrPlan.OverridePaths) == "canonical_control.run.num_workers"), ...
    "Smoke fixed-link config must own the serial worker policy canonically.");
snrSmokeCfg = sixgr.lls6g.config.loadScenarioConfig(snrPlan.RuntimeScenarioYAML);
assert(double(snrSmokeCfg.get("canonical_control.run.num_workers")) == 1 && ...
    double(snrSmokeCfg.get("run_control.num_workers")) == 1 && ...
    ~logical(snrSmokeCfg.get("canonical_control.run.auto_start_parallel_pool")), ...
    "Smoke fixed-link canonical and legacy worker settings must stay synchronized.");

geometryPlan = smoke.Runs(2);
assert(endsWith(string(geometryPlan.BaseScenarioYAML), "lls_true_geometry_2cell_2ue_200kmh.yaml"), ...
    "Smoke geometry plan must target the geometry scenario.");
assert(logical(geometryPlan.OverrideApplied), "Smoke geometry plan must use a runtime override wrapper.");
assert(any(string(geometryPlan.OverridePaths) == "canonical_control.run.total_slots"), ...
    "Smoke geometry plan must reduce total_slots through runtime override.");
assert(any(string(geometryPlan.OverridePaths) == "canonical_control.run.measurement_slots"), ...
    "Smoke geometry plan must reduce measurement_slots through runtime override.");
assert(endsWith(string(geometryPlan.RuntimeScenarioYAML), ...
    "lls_true_geometry_2cell_2ue_200kmh_smoke.yaml"), ...
    "Smoke geometry policy must live in the checked-in smoke YAML.");
geometrySmokeCfg = sixgr.lls6g.config.loadScenarioConfig(geometryPlan.RuntimeScenarioYAML);
assert(double(geometrySmokeCfg.get("canonical_control.run.num_workers")) == 1 && ...
    double(geometrySmokeCfg.get("run_control.num_workers")) == 1 && ...
    ~logical(geometrySmokeCfg.get("run_control.auto_start_parallel_pool")), ...
    "Smoke geometry canonical and legacy worker settings must stay synchronized.");
assert(exist(tmp, "dir") ~= 7, ...
    "PrepareOnly must not create generated runtime YAMLs or result folders.");

fullRun = run_two_mode_lls_full("PrepareOnly", true, "ResultsRoot", tmp, "WriteSummary", false, "Verbose", false);
assert(fullRun.Ok && fullRun.Prepared, "Full command must support PrepareOnly planning.");
assert(numel(fullRun.Runs) == 2, "Full plan must include the fixed sweep and geometry scenarios.");
assert(all(~[fullRun.Runs.OverrideApplied]), "Full plan must use the catalog YAMLs as-is.");
assert(string(fullRun.SummaryCSV) == string(fullfile(tmp, "two_mode_full_summary.csv")), ...
    "Full summary path must resolve under the requested results root.");
assert(exist(tmp, "dir") ~= 7, ...
    "Full PrepareOnly planning must remain read-only.");

docPath = fullfile(pwd, "docs", "6g_lls", "two_mode_webgui_scenarios.md");
assert(exist(docPath, "file") == 2, "Missing two-mode WebGUI scenario documentation.");
docText = string(fileread(docPath));
assert(contains(docText, "run_two_mode_lls_smoke"), "Documentation must mention the smoke command.");
assert(contains(docText, "run_two_mode_lls_full"), "Documentation must mention the full command.");
assert(contains(docText, "lls_true_snr_sweep_awgn_1ue.yaml"), ...
    "Documentation must mention the fixed SNR sweep YAML.");
assert(contains(docText, "lls_true_geometry_2cell_2ue_200kmh.yaml"), ...
    "Documentation must mention the geometry YAML.");
end

function localCleanup(pathValue)
if exist(pathValue, "dir") == 7
    rmdir(pathValue, "s");
end
end
