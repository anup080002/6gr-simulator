function ok = test6GLLSMultiUserBeamforming()
%TEST6GLLSMULTIUSERBEAMFORMING Ensure config-driven LLS keeps multi-user beamformed MIMO honest.

setup6GRSimToolkit("Verbose", false);

previousScratch = string(getenv("SIXGR_REGRESSION_SCRATCH_ROOT"));
scratchRoot = previousScratch;
ownsScratchRoot = strlength(strtrim(scratchRoot)) == 0;
if ownsScratchRoot
    scratchRoot = string(tempname);
    mkdir(scratchRoot);
    setenv("SIXGR_REGRESSION_SCRATCH_ROOT", scratchRoot);
elseif ~isfolder(scratchRoot)
    mkdir(scratchRoot);
end
scratchCleanup = onCleanup(@() localRestoreScratch(previousScratch, scratchRoot, ownsScratchRoot)); %#ok<NASGU>
tmp = localScratchChild(scratchRoot, "u", ownsScratchRoot);
mkdir(tmp);
c = onCleanup(@() localRemoveFolder(tmp)); %#ok<NASGU>

baseScenario = fullfile(pwd, "simulator", "configs", "scenarios", "lls_mimo4x4_multiuser_beamformed_awgn_validation.yaml");
scenarioPath = fullfile(tmp, "lls_multiuser_smoke.yaml");
fid = fopen(scenarioPath, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(baseScenario, '\', '\\') '"],' ...
    '"meta":{"scenario_id":"lls_multiuser_smoke","description":"multi-user smoke","version":"1","owner":"test","maturity_tag":"smoke"},' ...
    '"simulation":{"n_frames":1,"n_slots":1,"monte_carlo_iterations":1,"random_seed":19,"snr_db":34},' ...
    '"pdsch":{"execution_profile":"phy_calibration"},' ...
    '"users":{"enabled":true,"n_users":2,"rnti_start":101,"seed_stride":29,' ...
    '"execution_model":"independent_link_sweep","beam_selection_strategy":"round_robin_codebook","save_user_tables":true},' ...
    '"output":{"save_figures":false,"save_mat":false,"profile":"lls_multiuser_smoke"}}']);
fclose(fid);

out = run_6g_phy_lls_single(scenarioPath, tmp, "smoke");
assert(out.Ok, "Multi-user beamformed AWGN validation scenario should complete cleanly.");

runFolder = char(string(out.RunFolder));
dlFile = fullfile(runFolder, "air_interface", "csv", "dl_pdsch_trials.csv");
ulFile = fullfile(runFolder, "air_interface", "csv", "ul_pusch_trials.csv");
beamFile = fullfile(runFolder, "beamforming", "csv", "probe_beam_mimo.csv");
summaryFile = fullfile(runFolder, "air_interface", "csv", "multiuser_user_summary.csv");

assert(exist(dlFile, "file") == 2, "Missing multi-user DL trials CSV.");
assert(exist(ulFile, "file") == 2, "Missing multi-user UL trials CSV.");
assert(exist(beamFile, "file") == 2, "Missing multi-user beamforming CSV.");
assert(exist(summaryFile, "file") == 2, "Missing multi-user summary CSV.");

dl = readtable(dlFile, "VariableNamingRule", "preserve");
ul = readtable(ulFile, "VariableNamingRule", "preserve");
beam = readtable(beamFile, "VariableNamingRule", "preserve");
summary = readtable(summaryFile, "VariableNamingRule", "preserve");

assert(ismember("UEIndex", dl.Properties.VariableNames), "DL trials must expose UEIndex.");
assert(ismember("UEIndex", ul.Properties.VariableNames), "UL trials must expose UEIndex.");
assert(numel(unique(double(dl.UEIndex))) >= 2, "DL trials must cover multiple UEs.");
assert(numel(unique(double(ul.UEIndex))) >= 2, "UL trials must cover multiple UEs.");
assert(any(double(dl.ConfiguredTxAntennas) == 4), "DL trials must preserve 4T transmit configuration.");
assert(any(double(ul.ConfiguredTxAntennas) == 4), "UL trials must preserve 4T transmit configuration.");
assert(any(double(dl.ConfiguredLayers) == 2), "DL trials must preserve the configured layer count.");
assert(any(double(ul.ConfiguredLayers) == 2), "UL trials must preserve the configured layer count.");
assert(all(double(dl.Layers) == 2), "DL waveform trials must execute at two layers in this scenario.");
assert(all(double(ul.Layers) == 2), "UL waveform trials must execute at two layers in this scenario.");
assert(ismember("ExecutionProfile", dl.Properties.VariableNames) && ...
    all(string(dl.ExecutionProfile) == "phy_calibration"), ...
    "Independent-link AWGN validation must use phy_calibration, not scheduler_truth without a decoded grant.");
localAssertPerLayerSINR(dl, "DL", 2);
localAssertPerLayerSINR(ul, "UL", 2);
assert(ismember("BeamIndexSet", beam.Properties.VariableNames), "Beam diagnostics must export selected beam indices.");
assert(ismember("PrecoderSource", beam.Properties.VariableNames), "Beam diagnostics must expose precoder provenance.");
assert(any(strlength(string(beam.BeamIndexSet)) > 0), "Beam diagnostics must include selected beam indices.");
assert(any(logical(beam.BeamformingApplied)), "Beam diagnostics must mark applied beamforming.");
assert(ismember("ExecutionModel", summary.Properties.VariableNames), "Multi-user summary must expose execution model.");
assert(all(string(summary.ExecutionModel) == "independent_link_sweep"), ...
    "Multi-user summary must honestly declare the execution model.");

manifest = jsondecode(fileread(fullfile(runFolder, "meta", "scenario_manifest.json")));
assert(isfield(manifest, "ConfiguredUsers") && manifest.ConfiguredUsers == 2, ...
    "Manifest must persist the configured user count.");
assert(isfield(manifest, "ConfiguredLayers") && manifest.ConfiguredLayers == 2, ...
    "Manifest must persist the configured layer count.");
assert(isfield(manifest, "BeamSelectionStrategy"), ...
    "Manifest must persist the beam selection strategy.");
assert(~isempty(summary), "Multi-user summary must not be empty.");

ok = true;
end

function localAssertPerLayerSINR(T, linkLabel, expectedLayers)
vars = string(T.Properties.VariableNames);
assert(ismember("PostEqSINRPerLayer_dB", vars), ...
    "%s trials must export per-layer post-equalization SINR.", linkLabel);

if ismember("Layers", vars)
    rows = find(double(T.Layers) == expectedLayers);
else
    rows = (1:height(T)).';
end
assert(~isempty(rows), "%s trials must include %d-layer rows.", linkLabel, expectedLayers);

tokens = string(T.PostEqSINRPerLayer_dB);
for ii = reshape(rows, 1, [])
    values = localParseNumericVector(tokens(ii));
    assert(numel(values) == expectedLayers, ...
        "%s row %d must expose one post-equalization SINR value per layer; got '%s'.", ...
        linkLabel, ii, char(tokens(ii)));
    assert(all(isfinite(values)), ...
        "%s row %d per-layer post-equalization SINR must be finite.", linkLabel, ii);
end
end

function values = localParseNumericVector(token)
token = string(token);
if ismissing(token) || strlength(strtrim(token)) == 0
    values = [];
    return;
end

raw = char(token);
raw = strrep(raw, "[", "");
raw = strrep(raw, "]", "");
parts = regexp(raw, "[\|\s,;]+", "split");
parts = parts(~cellfun(@isempty, parts));
values = str2double(parts);
end

function localRestoreScratch(previousScratch, scratchRoot, ownsScratchRoot)
setenv("SIXGR_REGRESSION_SCRATCH_ROOT", previousScratch);
if ownsScratchRoot
    localRemoveFolder(scratchRoot);
end
end

function pathValue = localScratchChild(scratchRoot, prefix, ownsScratchRoot)
if ownsScratchRoot
    pathValue = fullfile(scratchRoot, prefix);
else
    token = char(java.util.UUID.randomUUID());
    pathValue = fullfile(scratchRoot, prefix + string(token(1:8)));
end
end

function localRemoveFolder(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
