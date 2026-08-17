function ok = testLLSRuntimeOperatingModeTruth()
%TESTLLSRUNTIMEOPERATINGMODETRUTH Keep configured AMC policy separate from runtime truth in runtime_operating_mode.csv.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

baseScenario = fullfile(pwd, "simulator", "configs", "scenarios", "lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml");
scenarioPath = fullfile(tmp, "lls_runtime_operating_mode_truth.yaml");
fid = fopen(scenarioPath, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(baseScenario, '\', '\\') '"],' ...
    '"meta":{"scenario_id":"lls_runtime_operating_mode_truth","description":"runtime operating mode truth test","version":"1","owner":"test","maturity_tag":"experimental"},' ...
    '"simulation":{"n_frames":1,"n_slots":1,"n_subframes":1,"monte_carlo_iterations":1,"random_seed":73032,"snr_db":10,"snr_sweep_offsets_db":[0]},' ...
    '"run_control":{"execution_mode":"LLS","num_workers":1},' ...
    '"control_gating":{"pbch_required":false,"prach_required":false,"pdcch_required":false,"pucch_required":false,"srs_required":false,"trs_required":false},' ...
    '"users":{"enabled":true,"n_users":2,"execution_model":"slot_coupled_truth","save_user_tables":true},' ...
    '"deployment_topology":{"num_ues":2},' ...
    '"traffic":{"dlRatio":0.5,"ulRatio":0.5},' ...
    '"output_control":{"output_dir":"' strrep(tmp, '\', '\\') '"},' ...
    '"output":{"backend":"filesystem","profile":"lls_runtime_operating_mode_truth","save_figures":false,"save_png":false,"save_mat":false}}']);
fclose(fid);

scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
runFolder = fullfile(tmp, "bundle");
cfg = sixgr.lls6g.buildInternalConfig(scfg, runFolder);
cfg.run.runTag = "focused";
cfg.run.scenarioID = char(string(scfg.ScenarioID));
cfg.run.executionID = "execution-runtime-operating-mode-truth";
cfg.meta.scenarioID = char(string(scfg.ScenarioID));
cfg.meta.executionID = cfg.run.executionID;
cfg.meta.configHash = char(string(scfg.ConfigHash));
cfg.run.numFrames = 6;
cfg.run.useParallel = false;
cfg.run.numWorkers = 1;
cfg.run.parallelRequestedWorkers = 1;
cfg.outputs.saveFigures = false;
cfg.outputs.savePNG = false;

% Stop only after a real UL waveform grant has executed.  This avoids the
% unrelated hundreds-of-artifacts finalization boundary while preserving
% genuine scheduler, PDCCH, PDSCH and PUSCH runtime rows.  The bundle marks
% the probe as profile-stopped and therefore cannot be mistaken for a
% completed production run.
envNames = ["SIXGR_PROFILE_MODE", "SIXGR_STOP_AFTER_FIRST_N_PUSCH_GRANTS"];
priorEnv = strings(size(envNames));
for i = 1:numel(envNames)
    priorEnv(i) = string(getenv(envNames(i)));
end
envCleanup = onCleanup(@() localRestoreEnvironment(envNames, priorEnv)); %#ok<NASGU>
setenv("SIXGR_PROFILE_MODE", "focused_runtime_operating_mode_truth");
setenv("SIXGR_STOP_AFTER_FIRST_N_PUSCH_GRANTS", "1");
slotDuration_s = max(eps, double(sixgr.util.structGet( ...
    cfg, "phy.numerology.slotDuration_ms", 1)) / 1e3);
opt = struct( ...
    "LinkDuration_s", 6 * slotDuration_s, ...
    "LinkMaxSimFrames", 6, ...
    "LinkSNR_dB", double(cfg.channel.snr_dB), ...
    "LinkSNRGrid_dB", double(cfg.channel.snr_dB), ...
    "LinkSweepFrames", 6, ...
    "LinkSweepTrialsPerSNR", 6, ...
    "LinkReferenceSweepFrames", 1, ...
    "LinkSweepMaxPoints", 1, ...
    "LinkAdaptiveSweepEnabled", false, ...
    "LinkAdaptiveSweepMaxPoints", 1, ...
    "LinkAnchorCases", ["dl","ul"], ...
    "SaveFigures", false);
bundle = sixgr.truth.runWaveformLinkBundle(cfg, ...
    fullfile(runFolder, "air_interface"), opt);
assert(logical(sixgr.util.structGet(bundle, "ProfileStoppedEarly", false)), ...
    "The focused truth probe must stop before unrelated heavy publication exports.");

runtimeModeFile = fullfile(runFolder, "reports", "csv", "runtime_operating_mode.csv");
dlFile = fullfile(runFolder, "air_interface", "csv", "dl_pdsch_trials.csv");
ulFile = fullfile(runFolder, "air_interface", "csv", "ul_pusch_trials.csv");
assert(exist(runtimeModeFile, "file") == 2, "Missing runtime operating mode CSV.");
assert(exist(dlFile, "file") == 2, "Missing DL raw trial CSV.");
assert(exist(ulFile, "file") == 2, "Missing UL raw trial CSV.");

runtimeMode = readtable(runtimeModeFile, "VariableNamingRule", "preserve", ...
    "Delimiter", ",", "TextType", "string");
dl = readtable(dlFile, "VariableNamingRule", "preserve", ...
    "Delimiter", ",", "TextType", "string");
ul = readtable(ulFile, "VariableNamingRule", "preserve", ...
    "Delimiter", ",", "TextType", "string");

localAssertDirection(runtimeMode, dl, "DL");
localAssertDirection(runtimeMode, ul, "UL");
ok = true;
end

function localAssertDirection(runtimeMode, trialT, direction)
mask = strcmpi(string(runtimeMode.Direction), direction);
assert(nnz(mask) == 1, "Runtime operating mode CSV must expose a single %s row.", direction);
row = runtimeMode(mask, :);
requiredVars = ["LinkAdaptationMode","ConfiguredLinkAdaptationMode","ActualMCSSelectionMode", ...
    "ConfiguredMCSSelectionPolicy","SchedulerGrantMCSSelectionMode","RequestedOperatingPointSource", ...
    "AppliedOperatingPointSource","ActualMCSSelectionModeAuthority", ...
    "ConfiguredBandwidth_Hz","CyclicPrefix", ...
    "TrafficFlowSource","TrafficFlowDerivationMode","TrafficFlowResolvedFlag"];
assert(all(ismember(requiredVars, string(row.Properties.VariableNames))), ...
    "Runtime operating mode CSV must expose configured/requested/applied AMC truth fields for %s.", direction);
assert(isfinite(double(row.ConfiguredBandwidth_Hz(1))) && ...
    double(row.ConfiguredBandwidth_Hz(1)) > 0, ...
    "Runtime operating mode CSV must expose the applied carrier bandwidth for %s.", direction);
assert(strcmpi(char(string(row.CyclicPrefix(1))), "normal"), ...
    "Runtime operating mode CSV must expose the applied cyclic-prefix mode for %s.", direction);

actualMode = localDominantString(trialT, "ActualMCSSelectionMode");
configuredMode = localDominantString(trialT, "ConfiguredMCSSelectionPolicy");
linkMode = localDominantString(trialT, "LinkAdaptationMode");
appliedSource = localDominantString(trialT, "AppliedOperatingPointSource");
requestedSource = localDominantString(trialT, "RequestedOperatingPointSource");
schedulerMode = localDominantString(trialT, "SchedulerGrantMCSSelectionMode");

assert(strlength(string(row.ConfiguredLinkAdaptationMode(1))) > 0, ...
    "Runtime operating mode CSV must preserve configured link-adaptation mode for %s.", direction);
assert(strcmpi(char(string(row.LinkAdaptationMode(1))), char(linkMode)), ...
    "Runtime operating mode CSV must summarize the same requested runtime link-adaptation path exported by raw %s trials.", direction);
assert(strcmpi(char(string(row.ConfiguredMCSSelectionPolicy(1))), char(configuredMode)), ...
    "Runtime operating mode CSV must preserve the configured AMC policy for %s.", direction);
assert(strcmpi(char(string(row.RequestedOperatingPointSource(1))), char(requestedSource)), ...
    "Runtime operating mode CSV must preserve the requested operating-point source for %s.", direction);
assert(strcmpi(char(string(row.ActualMCSSelectionMode(1))), char(actualMode)), ...
    "Runtime operating mode CSV must summarize the actual runtime selection mode from raw %s trials.", direction);
assert(strcmpi(char(string(row.AppliedOperatingPointSource(1))), char(appliedSource)), ...
    "Runtime operating mode CSV must summarize the applied operating-point source from raw %s trials.", direction);
if strlength(schedulerMode) > 0
    assert(strcmpi(char(string(row.SchedulerGrantMCSSelectionMode(1))), char(schedulerMode)), ...
        "Runtime operating mode CSV must preserve scheduler-grant AMC mode for %s.", direction);
end
assert(~strcmpi(char(string(row.ConfiguredMCSSelectionPolicy(1))), char(string(row.ActualMCSSelectionMode(1)))), ...
    "Runtime operating mode CSV must not relabel configured AMC policy as the actual runtime selection mode for %s.", direction);
assert(strcmpi(char(string(row.ActualMCSSelectionModeAuthority(1))), "raw_trial_runtime_evidence"), ...
    "Runtime operating mode CSV must disclose raw trial runtime evidence as the source authority for %s actual AMC labeling.", direction);
assert(strcmpi(char(string(row.TrafficFlowSource(1))), "traffic.scalar_profile_fields"), ...
    "Runtime operating mode CSV must disclose scalar-derived traffic flow ownership for legacy %s configs.", direction);
assert(strcmpi(char(string(row.TrafficFlowDerivationMode(1))), "derived_from_scalar_traffic_config"), ...
    "Runtime operating mode CSV must disclose derived traffic flow mode for legacy %s configs.", direction);
assert(localTruthy(row.TrafficFlowResolvedFlag(1)), ...
    "Runtime operating mode CSV must show traffic flow resolution for %s.", direction);
end

function value = localDominantString(T, varName)
value = "";
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
slice = T;
if ismember("Direction", string(slice.Properties.VariableNames))
    slice = slice(strcmpi(string(slice.Direction), string(slice.Direction(1))), :);
end
if ismember("IsWarmupFrame", string(slice.Properties.VariableNames))
    warmMask = logical(slice.IsWarmupFrame);
    if any(~warmMask)
        slice = slice(~warmMask, :);
    end
end
values = strtrim(string(slice.(char(varName))));
values = values(strlength(values) > 0);
if isempty(values)
    return;
end
[uniqueValues, ~, idx] = unique(values, "stable");
counts = accumarray(idx, 1);
[~, bestIdx] = max(counts);
value = uniqueValues(bestIdx);
end

function tf = localTruthy(value)
if islogical(value)
    tf = value;
elseif isnumeric(value)
    tf = value ~= 0;
else
    tf = any(lower(strtrim(string(value))) == ["true","1","yes"]);
end
end

function localRestoreEnvironment(names, values)
for i = 1:numel(names)
    setenv(names(i), values(i));
end
end
