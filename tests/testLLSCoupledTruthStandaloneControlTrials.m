function ok = testLLSCoupledTruthStandaloneControlTrials()
%TESTLLSCOUPLEDTRUTHSTANDALONECONTROLTRIALS
% Guard that coupled-truth runs still export real standalone control/reference
% trial families when the sustained traffic loop disables per-slot control gating.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

baseScenario = fullfile(pwd, "simulator", "configs", "scenarios", "lls_mimo4x4_multiuser_beamformed_awgn_validation.yaml");
scenarioPath = fullfile(tmp, "lls_coupled_truth_no_gating.yaml");
fid = fopen(scenarioPath, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(baseScenario, '\', '\\') '"],' ...
    '"meta":{"scenario_id":"lls_coupled_truth_no_gating","description":"coupled truth standalone control trial guard","version":"1","owner":"test","maturity_tag":"smoke"},' ...
    '"simulation":{"link_direction":"both","n_frames":1,"n_slots":1,"monte_carlo_iterations":1,"random_seed":29,"snr_db":24},' ...
    '"random_access":{"enabled":true,"prach_format":"A1","preamble_length_mode":"short","preamble_count":64,"zero_correlation_zone":8,"detection_threshold":0.5,"msg3_enabled":true,"configuration_index":84,"subcarrier_spacing_khz":30,"root_sequence_index":1,"preamble_index":0},' ...
    '"users":{"enabled":true,"n_users":2,"rnti_start":401,"seed_stride":17,' ...
    '"execution_model":"slot_coupled_truth","beam_selection_strategy":"fixed_first_beam","save_user_tables":true},' ...
    '"control_gating":{"pbch_required":false,"prach_required":false,"pdcch_required":false,"srs_required":false,"srs_max_age_slots":4,"trs_required":false,"trs_max_age_slots":4},' ...
    '"output":{"save_figures":false,"save_mat":false,"profile":"lls_coupled_truth_no_gating",' ...
    '"live_publish_frame_interval":1,"live_heavy_refresh_interval_frames":3}}']);
fclose(fid);

out = run_6g_phy_lls_single(scenarioPath, tmp, "smoke");
assert(isfield(out, "RunFolder") && strlength(string(out.RunFolder)) > 0, ...
    "Coupled truth no-gating scenario must still publish a run folder.");

runFolder = char(string(out.RunFolder));
requiredSignals = ["pbch","prach","pdcch","pucch","srs"];
for i = 1:numel(requiredSignals)
    signalName = requiredSignals(i);
    airPath = fullfile(runFolder, "air_interface", "csv", char(signalName + "_trials.csv"));
    ctrlPath = fullfile(runFolder, "control", "csv", char(signalName + "_trials.csv"));
    assert(exist(airPath, "file") == 2, "Missing air-interface %s control/reference trial CSV.", signalName);
    assert(exist(ctrlPath, "file") == 2, "Missing control-plane %s trial CSV.", signalName);
    T = readtable(airPath, "VariableNamingRule", "preserve");
    assert(~isempty(T), "Standalone waveform %s trial family must not be empty when coupled truth disables in-slot gating.", signalName);
end

trsAirPath = fullfile(runFolder, "air_interface", "csv", "trs_trials.csv");
trsCtrlPath = fullfile(runFolder, "control", "csv", "trs_trials.csv");
assert(exist(trsAirPath, "file") == 2, "Missing air-interface TRS trial CSV.");
assert(exist(trsCtrlPath, "file") == 2, "Missing control-plane TRS trial CSV.");
trsT = readtable(trsAirPath, "VariableNamingRule", "preserve");
controlSummaryPath = fullfile(runFolder, "reports", "csv", "live_control_gating_summary.csv");
assert(exist(controlSummaryPath, "file") == 2, "Missing control-gating summary CSV.");
controlSummary = readtable(controlSummaryPath, "VariableNamingRule", "preserve");
assert(~isempty(controlSummary), "Control-gating summary must not be empty.");
assert(~logical(controlSummary.PBCHGatingActive(end)) && ~logical(controlSummary.PRACHGatingActive(end)), ...
    "Smoke scenario explicitly disables PBCH and PRACH gating.");
assert(double(controlSummary.UsersAcquired(end)) == 2, ...
    "When PBCH gating is disabled, both users must count as ready/acquired in the live control summary.");
assert(double(controlSummary.UsersAccessReady(end)) == 2, ...
    "When PRACH gating is disabled, both users must count as ready in the live control summary.");
runtimeModePath = fullfile(runFolder, "reports", "csv", "runtime_operating_mode.csv");
assert(exist(runtimeModePath, "file") == 2, "Missing runtime operating-mode CSV for TRS status validation.");
runtimeMode = readtable(runtimeModePath, "VariableNamingRule", "preserve");
assert(all(ismember(["TRSMode","TRSRuntimeConsumer","TRSReceiverIntegrationStatus"], string(runtimeMode.Properties.VariableNames))), ...
    "Runtime operating mode must expose TRS status semantics.");
if isempty(trsT)
    assert(all(ismember(lower(strtrim(string(runtimeMode.TRSMode))), ["disabled","inactive","unavailable"])) || ...
        all(ismember(lower(strtrim(string(runtimeMode.TRSReceiverIntegrationStatus))), ["inactive","disabled","unavailable"])), ...
        "Empty TRS trials are only honest when runtime status declares TRS disabled/inactive/unavailable.");
end

ok = true;
end
