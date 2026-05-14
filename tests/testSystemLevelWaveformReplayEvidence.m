function ok = testSystemLevelWaveformReplayEvidence()
%TESTSYSTEMLEVELWAVEFORMREPLAYEVIDENCE Verify system replay exports real SINR/precoder evidence.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.strictMode = false;
cfg.run.useMex = false;
cfg.system.phyBackend = "waveform";
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.outputs.saveFIG = false;

cfg.scenario.layout.nSites = 1;
cfg.scenario.layout.nSectorsPerSite = 1;
cfg.scenario.layout.wrapAround = false;
cfg.scenario.ue.nUE = 2;
cfg.scenario.nUE = 2;
cfg.scenario.bs.nTxAnt = 1;
cfg.scenario.bs.nRxAnt = 1;
cfg.scenario.ue.nTxAnt = 1;
cfg.scenario.ue.nRxAnt = 1;

cfg.channel.awgnOnly = true;
cfg.channel.model = "AWGN";
cfg.channel.fading.enable = false;

cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 0.35;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.codeRate = 0.35;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.nLayers = 1;
cfg.mac.scheduler.type = "rr";
cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);

ctx = sixgr.core.SimContext(cfg);
numTTI = 8;
nUE = 2;
res = sixgr.system.SystemLevelRunner.run(ctx, struct( ...
    "NumTTI", numTTI, ...
    "OfferedBitsDL", repmat(4000, numTTI, nUE), ...
    "OfferedBitsUL", repmat(4000, numTTI, nUE), ...
    "PHYBackend", "waveform"));

assert(res.Ok, "Focused waveform-backed system run must complete.");
assert(isfield(res, "Details") && istable(res.Details.SchedulerGrants), ...
    "Focused waveform-backed system run must expose scheduler grant details.");

grantTrace = res.Details.SchedulerGrants;
localAssertReplayEvidence(grantTrace, "system scheduler grant trace");

scfg = localMakeTestScenarioConfig();
sixgr.truth.exportSystemLevelCanonicalArtifacts(tmp, scfg, cfg, res);

dlT = localReadTable(fullfile(tmp, "air_interface", "csv", "dl_pdsch_trials.csv"));
ulT = localReadTable(fullfile(tmp, "air_interface", "csv", "ul_pusch_trials.csv"));
runtimeT = localReadTable(fullfile(tmp, "reports", "csv", "runtime_operating_mode.csv"));
allTrials = localVertcatNonempty(dlT, ulT);
localAssertReplayEvidence(allTrials, "canonical raw trial export");

assert(all(strcmpi(string(allTrials.SystemLevelSINRSource), "system_level_desired_interference_noise_budget")), ...
    "Canonical raw trials must preserve system SINR as a separate runtime budget.");
assert(~any(strcmpi(string(allTrials.SystemLevelSINRSource), string(allTrials.ReceiverHestSINRSource))), ...
    "Receiver-Hest SINR source must not overwrite the system-level SINR source.");
assert(~any(strcmpi(string(allTrials.SystemLevelSINRSource), string(allTrials.DecoderTruthProxySINRSource))), ...
    "Decoder-side SINR proxy source must not be relabeled from the system-level SINR source.");

assert(all(strcmpi(string(runtimeT.ReceiverHestSINRValueStatus), "OK")), ...
    "Runtime operating mode must summarize receiver-Hest SINR replay availability.");
assert(all(strcmpi(string(runtimeT.DecoderTruthProxySINRValueStatus), "OK")), ...
    "Runtime operating mode must summarize equalizer-EVM SINR replay availability.");
assert(all(strcmpi(string(runtimeT.ExplicitPrecoderReplayStatus), "materialized")), ...
    "Runtime operating mode must summarize per-grant precoder replay materialization.");

ok = true;
end

function localAssertReplayEvidence(T, contextLabel)
assert(istable(T) && height(T) > 0, "%s must contain rows.", contextLabel);
required = ["ReceiverHestSINR_dB","ReceiverHestSINRSource","ReceiverHestSINRValueStatus", ...
    "DecoderTruthProxySINR_dB","DecoderTruthProxySINRSource","DecoderTruthProxySINRValueStatus", ...
    "ExplicitPrecoderReplayStatus","AppliedPrecoderSource","PrecodingMode"];
for i = 1:numel(required)
    assert(ismember(required(i), string(T.Properties.VariableNames)), ...
        "%s missing replay evidence column '%s'.", contextLabel, required(i));
end
assert(all(isfinite(double(T.ReceiverHestSINR_dB))), ...
    "%s must contain finite receiver-Hest SINR values.", contextLabel);
assert(all(strcmpi(string(T.ReceiverHestSINRSource), "receiver_hest_reference_signal_measurement")), ...
    "%s must source receiver-Hest SINR from receiver Hest/CSI feedback.", contextLabel);
assert(all(strcmpi(string(T.ReceiverHestSINRValueStatus), "OK")), ...
    "%s must mark receiver-Hest SINR as OK.", contextLabel);
assert(all(isfinite(double(T.DecoderTruthProxySINR_dB))), ...
    "%s must contain finite equalizer-EVM decoder-side SINR proxy values.", contextLabel);
assert(all(strcmpi(string(T.DecoderTruthProxySINRSource), "post_equalization_evm_proxy")), ...
    "%s must source decoder-side SINR from post-equalization EVM only.", contextLabel);
assert(all(strcmpi(string(T.DecoderTruthProxySINRValueStatus), "OK")), ...
    "%s must mark decoder-side SINR proxy as OK.", contextLabel);
assert(all(strcmpi(string(T.ExplicitPrecoderReplayStatus), "materialized")), ...
    "%s must mark precoder replay metadata as materialized.", contextLabel);
end

function T = localReadTable(pathStr)
opts = detectImportOptions(pathStr, "Delimiter", ",");
opts.VariableNamingRule = "preserve";
T = readtable(pathStr, opts);
end

function T = localVertcatNonempty(varargin)
parts = varargin(cellfun(@(x) istable(x) && height(x) > 0, varargin));
if isempty(parts)
    T = table();
else
    T = vertcat(parts{:});
end
end

function scfg = localMakeTestScenarioConfig()
data = struct();
data.meta = struct("scenario_id", "unit_test_system_level_export");
data.users = struct( ...
    "execution_model", "slot_coupled_truth", ...
    "beam_selection_strategy", "runtime_best_beam_per_link");
data.traffic = struct( ...
    "target_rate_mbps", NaN, ...
    "offered_load_mbps", NaN);
data.deployment_topology = struct( ...
    "num_cells", 1, ...
    "num_ues", 2, ...
    "num_sites", 1, ...
    "num_sectors_per_site", 1, ...
    "layout_type", "hex_grid", ...
    "inter_site_distance", 500, ...
    "num_trps", 1);
data.antenna_and_array = struct( ...
    "bs_array_geometry", "URA", ...
    "ue_array_geometry", "ULA", ...
    "bs_num_antenna_elements", 64, ...
    "ue_num_antenna_elements", 4, ...
    "element_spacing_h", 0.5, ...
    "element_spacing_v", 0.5, ...
    "polarization", "cross_pol");
scfg = sixgr.lls6g.config.ScenarioConfig(data, "ConfigPath", "unit_test_system_level_export");
end
