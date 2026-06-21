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
allTrials = localVertcatNonempty(dlT, ulT);
localAssertReplayEvidence(allTrials, "canonical raw trial export");

assert(all(strcmpi(string(allTrials.SystemLevelSINRSource), "system_level_desired_interference_noise_budget")), ...
    "Canonical raw trials must preserve system SINR as a separate runtime budget.");
assert(~any(strcmpi(string(allTrials.SystemLevelSINRSource), string(allTrials.ReceiverHestSINRSource))), ...
    "Receiver-Hest SINR source must not overwrite the system-level SINR source.");
assert(~any(strcmpi(string(allTrials.SystemLevelSINRSource), string(allTrials.DecoderTruthProxySINRSource))), ...
    "Decoder-side SINR proxy source must not be relabeled from the system-level SINR source.");

ok = true;
end

function localAssertReplayEvidence(T, contextLabel)
assert(istable(T) && height(T) > 0, "%s must contain rows.", contextLabel);
required = ["ReceiverHestSINR_dB","PostEqSINR_dB","DecoderIterations", ...
    "ChannelEstimateAvailable","EqualizationAvailable","DecodeAttempted","DecodeAvailable", ...
    "DecoderTruthProxySINR_dB","AppliedPrecoderSource","PrecodingMode"];
rawTrialEvidenceRequired = ["MeasuredDMRSRECount","MeasuredDMRSSymbolCount","MeasuredRateMatchedCodewordLLRBits", ...
    "MeasuredRateRecoveredLLRBits","MeasuredRateRecoveredCodeBlockCount", ...
    "MeasuredLDPCDecoderMeanIterations","MeasuredLDPCIterationVector", ...
    "MeasuredCodeBlockDecodeCount","MeasuredCodeBlockDecodeErrorCount","MeasuredCodeBlockDecodeFailureRate","MeasuredCodeBlockDecodeErrorVector", ...
    "MeasuredCodeBlockCRCCount","MeasuredCodeBlockCRCErrorCount","MeasuredCodeBlockCRCErrorVector"];
if contains(lower(string(contextLabel)), "raw trial")
    required = [required rawTrialEvidenceRequired];
end
for i = 1:numel(required)
    assert(ismember(required(i), string(T.Properties.VariableNames)), ...
        "%s missing replay evidence column '%s'.", contextLabel, required(i));
end
assert(all(isfinite(double(T.ReceiverHestSINR_dB))), ...
    "%s must contain finite receiver-Hest SINR values.", contextLabel);
assert(all(isfinite(double(T.PostEqSINR_dB))), ...
    "%s must contain finite receiver-derived post-equalization SINR.", contextLabel);
assert(all(isfinite(double(T.DecoderIterations))), ...
    "%s must carry decoder iteration evidence from the active receiver.", contextLabel);
if contains(lower(string(contextLabel)), "raw trial")
    assert(all(double(T.MeasuredDMRSRECount) > 0) && all(double(T.MeasuredDMRSSymbolCount) > 0), ...
        "%s must carry measured DMRS resource evidence from the active receiver.", contextLabel);
    assert(all(double(T.MeasuredRateMatchedCodewordLLRBits) > 0) && all(double(T.MeasuredRateRecoveredLLRBits) > 0), ...
        "%s must carry measured rate-matching/rate-recovery LLR evidence.", contextLabel);
    assert(all(double(T.MeasuredRateRecoveredCodeBlockCount) > 0) && all(isfinite(double(T.MeasuredLDPCDecoderMeanIterations))), ...
        "%s must carry measured LDPC code-block and decoder-iteration evidence.", contextLabel);
    assert(all(double(T.MeasuredCodeBlockDecodeCount) > 0) && all(isfinite(double(T.MeasuredCodeBlockDecodeErrorCount))), ...
        "%s must carry measured decoded-code-block outcome counts.", contextLabel);
    assert(all(isfinite(double(T.MeasuredCodeBlockDecodeFailureRate))), ...
        "%s must carry measured decoded-code-block failure rates.", contextLabel);
    assert(all(strlength(strtrim(string(T.MeasuredCodeBlockDecodeErrorVector))) > 0), ...
        "%s must carry compact decoded-code-block outcome vectors.", contextLabel);
    cbCrcCount = double(T.MeasuredCodeBlockCRCCount);
    assert(all(isfinite(cbCrcCount) & cbCrcCount >= 0), ...
        "%s must carry measured code-block CRC count evidence.", contextLabel);
    assert(all(isfinite(double(T.MeasuredCodeBlockCRCErrorCount))), ...
        "%s must carry measured code-block CRC error-count evidence.", contextLabel);
    hasCBCRC = cbCrcCount > 0;
    assert(all(strlength(strtrim(string(T.MeasuredCodeBlockCRCErrorVector(hasCBCRC)))) > 0), ...
        "%s must carry compact code-block CRC vectors when CB CRC checks exist.", contextLabel);
end
assert(all(logical(T.ChannelEstimateAvailable)) && all(logical(T.EqualizationAvailable)), ...
    "%s must carry channel-estimation and equalization availability from the active receiver.", contextLabel);
assert(all(logical(T.DecodeAttempted)) && all(logical(T.DecodeAvailable)), ...
    "%s must carry decode-stage availability from the active receiver.", contextLabel);
assert(all(~isfinite(double(T.DecoderTruthProxySINR_dB))), ...
    "%s must not promote EVM-derived SINR as decoder-truth evidence.", contextLabel);
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
