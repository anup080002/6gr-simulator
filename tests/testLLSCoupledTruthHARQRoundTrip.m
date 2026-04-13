function ok = testLLSCoupledTruthHARQRoundTrip()
%TESTLLSCOUPLEDTRUTHHARQROUNDTRIP Ensure coupled-truth HARQ replay completes end to end.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

baseScenario = fullfile(pwd, "simulator", "configs", "scenarios", "lls_harq_retransmission_exercise.yaml");
scenarioPath = fullfile(tmp, "lls_coupled_truth_harq_roundtrip.yaml");
fid = fopen(scenarioPath, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(baseScenario, '\', '\\') '"],' ...
    '"meta":{"scenario_id":"lls_coupled_truth_harq_roundtrip","description":"coupled truth HARQ replay regression","version":"1","owner":"test","maturity_tag":"regression"},' ...
    '"simulation":{"link_direction":"both","n_frames":6,"n_slots":6,"monte_carlo_iterations":6,"random_seed":41,"snr_db":-12,"snr_sweep_offsets_db":[0]},' ...
    '"users":{"enabled":true,"n_users":2,"rnti_start":401,"seed_stride":11,"execution_model":"slot_coupled_truth","beam_selection_strategy":"fixed_first_beam","save_user_tables":true},' ...
    '"harq":{"enabled":true,"feedback_timing_slots":1,"max_retx":3},' ...
    '"output":{"save_figures":false,"save_mat":false,"save_png":false,"profile":"lls_coupled_truth_harq_roundtrip"}}']);
fclose(fid);

out = run_6g_phy_lls_single(scenarioPath, tmp, "roundtrip");
assert(out.Ok, "Coupled-truth HARQ roundtrip scenario should complete cleanly.");

runFolder = char(string(out.RunFolder));
dlFile = fullfile(runFolder, "air_interface", "csv", "dl_pdsch_trials.csv");
ulFile = fullfile(runFolder, "air_interface", "csv", "ul_pusch_trials.csv");
harqFile = fullfile(runFolder, "harq", "csv", "live_harq_observation_timeline.csv");
stageFile = fullfile(runFolder, "air_interface", "reports", "csv", "live_stage_status.csv");

assert(exist(dlFile, "file") == 2, "Coupled-truth HARQ roundtrip must write DL trials.");
assert(exist(ulFile, "file") == 2, "Coupled-truth HARQ roundtrip must write UL trials.");
assert(exist(harqFile, "file") == 2, "Coupled-truth HARQ roundtrip must write live HARQ timeline.");
assert(exist(stageFile, "file") == 2, "Coupled-truth HARQ roundtrip must write live stage status.");

dl = readtable(dlFile, "VariableNamingRule", "preserve");
ul = readtable(ulFile, "VariableNamingRule", "preserve");
harq = readtable(harqFile, "VariableNamingRule", "preserve");
stage = readtable(stageFile, "VariableNamingRule", "preserve");

assert(~isempty(dl), "Coupled-truth HARQ roundtrip DL trials must not be empty.");
assert(~isempty(ul), "Coupled-truth HARQ roundtrip UL trials must not be empty.");
assert(~isempty(harq), "Coupled-truth HARQ roundtrip HARQ timeline must not be empty.");
assert(any(logical(harq.IsRetransmission)), "Coupled-truth HARQ roundtrip must exercise a real retransmission.");
assert(max(double(stage.DLCompletedFrames)) >= 1, "Coupled-truth HARQ roundtrip must advance DL frames.");
assert(max(double(stage.ULCompletedFrames)) >= 1, "Coupled-truth HARQ roundtrip must advance UL frames.");

ok = true;
end
