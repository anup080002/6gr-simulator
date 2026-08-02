function ok = testLLSLargeRunRuntimeTuning()
%TESTLLSLARGERUNRUNTIMETUNING Large truth runs obey exact YAML runtime policy.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

baseScenario = fullfile(pwd, "simulator", "configs", "scenarios", "lls_700mhz_20mhz_2x2_rank2_beam_truth.yaml");
scenarioPath = fullfile(tmp, "lls_large_runtime_tuning.yaml");
fid = fopen(scenarioPath, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(baseScenario, '\', '\\') '"],' ...
    '"meta":{"scenario_id":"lls_large_runtime_tuning","description":"large runtime tuning","version":"1","owner":"test","maturity_tag":"smoke"},' ...
    '"simulation":{"n_frames":72,"n_slots":72,"monte_carlo_iterations":1,"random_seed":19,"snr_db":-10,"min_duration_s":0.072,"link_direction":"both","snr_sweep_offsets_db":[0,5,10,15,20,25],' ...
    '"reference_sweep_enabled":false,"reference_trials_per_snr":0,"harq_diagnostics_enabled":false,' ...
    '"adaptive_sweep_enabled":false,"adaptive_sweep_step_db":1,"adaptive_sweep_max_points":0,"max_raw_rows_per_sweep":0},' ...
    '"reference_signals":{"ptrs_port_association_policy":"first_scheduled_dmrs_port"},' ...
    '"users":{"enabled":true,"n_users":100,"rnti_start":101,"seed_stride":29,' ...
    '"execution_model":"slot_coupled_truth","beam_selection_strategy":"fixed_first_beam","save_user_tables":true},' ...
    '"output":{"save_figures":false,"save_mat":false,"profile":"lls_large_runtime_tuning"}}']);
fclose(fid);

scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
snrGrid = [-10 -5 0 5 10 15];
tuning = sixgr.lls6g.runners.resolveWaveformBundleRuntimeTuning(scfg, cfg, snrGrid);

assert(~logical(tuning.AutoTuned), "Truth runtime must never be silently auto-tuned.");
assert(double(tuning.PrimaryTrialsPerSNR) == double(tuning.RequestedPrimaryTrialsPerSNR), ...
    "Large truth run must execute the exact YAML trial count.");
expectedTrials = double(sixgr.util.structGet(cfg, "run.totalSlots", ...
    sixgr.util.structGet(cfg, "run.numTTI", cfg.run.numFrames))) * ...
    double(scfg.get("simulation.monte_carlo_iterations"));
assert(double(tuning.PrimaryTrialsPerSNR) == expectedTrials, ...
    "Trial count must equal the normalized YAML slot count times Monte Carlo iterations.");
assert(~logical(tuning.ReferenceSweepEnabled), ...
    "Reference sweep must follow its YAML switch.");
assert(~logical(tuning.HARQDiagnosticsEnabled), ...
    "HARQ diagnostics must follow their YAML switch.");
assert(~logical(tuning.AdaptiveSweepEnabled), ...
    "Adaptive refinement must follow its YAML switch.");
assert(string(tuning.Policy) == "yaml_exact_truth_runtime");
assert(string(tuning.Notes) == "exact_yaml_runtime_no_auto_reduction");

budgetCfg = cfg;
budgetCfg.run.maxRawRowsPerSweep = 100;
budgetCfg.runtime.features = cfg.runtime.features;
localAssertThrows(@() sixgr.lls6g.runners.resolveWaveformBundleRuntimeTuning( ...
    scfg, budgetCfg, snrGrid), "sixgr:lls6g:RuntimeRowBudgetExceeded");

ok = true;
end

function localAssertThrows(fcn, identifier)
didThrow = false;
try
    fcn();
catch ME
    didThrow = strcmp(string(ME.identifier), string(identifier));
    if ~didThrow
        rethrow(ME);
    end
end
assert(didThrow, "Expected typed error %s.", identifier);
end
