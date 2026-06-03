function ok = testLLSLargeRunRuntimeTuning()
%TESTLLSLARGERUNRUNTIMETUNING Large multi-user truth runs should auto-tune.

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
    '"simulation":{"n_frames":72,"n_slots":72,"monte_carlo_iterations":1,"random_seed":19,"snr_db":-10,"min_duration_s":0.072,"link_direction":"both","snr_sweep_offsets_db":[0,5,10,15,20,25]},' ...
    '"users":{"enabled":true,"n_users":100,"rnti_start":101,"seed_stride":29,' ...
    '"execution_model":"slot_coupled_truth","beam_selection_strategy":"fixed_first_beam","save_user_tables":true},' ...
    '"output":{"save_figures":false,"save_mat":false,"profile":"lls_large_runtime_tuning"}}']);
fclose(fid);

scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
snrGrid = [-10 -5 0 5 10 15];
tuning = sixgr.lls6g.runners.resolveWaveformBundleRuntimeTuning(scfg, cfg, snrGrid);

assert(logical(tuning.AutoTuned), "Large 100-UE truth run should auto-tune its runtime budget.");
assert(double(tuning.PrimaryTrialsPerSNR) < double(tuning.RequestedPrimaryTrialsPerSNR), ...
    "Large 100-UE truth run should reduce primary trials per SNR.");
assert(~logical(tuning.ReferenceSweepEnabled), ...
    "Large 100-UE truth run should gate the fixed-reference sweep.");
assert(~logical(tuning.HARQDiagnosticsEnabled), ...
    "Large 100-UE truth run should gate HARQ diagnostics.");
assert(~logical(tuning.AdaptiveSweepEnabled), ...
    "Large 100-UE truth run should gate adaptive refinement.");
assert(contains(string(tuning.Notes), "reduced_primary_trials_per_snr"), ...
    "Large-run tuning should explain the reduced primary trial budget.");

ok = true;
end
