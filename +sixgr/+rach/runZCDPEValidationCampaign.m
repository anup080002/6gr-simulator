function out = runZCDPEValidationCampaign(baseCfg, varargin)
%RUNZCDPEVALIDATIONCAMPAIGN Execute explicit ZC-DPE validation vectors.
%
% This entry point is an isolated research/validation campaign.  Reusable
% ZC-DPE waveform behavior lives in the canonical PRACH runtime and is
% enabled through resolved YAML; this fixed matrix never supplies runtime
% scenario defaults.

p = inputParser;
p.FunctionName = "sixgr.rach.runZCDPEValidationCampaign";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "WriteOutputs", true, @(x) islogical(x) || isnumeric(x));
addParameter(p, "ScenarioMatrix", struct([]), @(x) isstruct(x));
addParameter(p, "Verbose", false, @(x) islogical(x) || isnumeric(x));
parse(p, baseCfg, varargin{:});

cfg = localBaseStruct(baseCfg);
cfg = sixgr.util.structSet(cfg, "ZCDPE.Enable", true);
cfg = sixgr.util.structSet(cfg, "random_access.prach_design", "zcdpe");
if isempty(sixgr.util.structGet(cfg, "prach_lls.OutputDir", []))
    cfg = sixgr.util.structSet(cfg, "prach_lls.OutputDir", localResolveOutputDir(cfg));
end

scenarioMatrix = p.Results.ScenarioMatrix;
if isempty(scenarioMatrix)
    scenarioMatrix = localDefaultScenarioMatrix();
end

out = sixgr.rach.runPRACHLLS(cfg, ...
    "WriteOutputs", logical(p.Results.WriteOutputs), ...
    "ScenarioMatrix", scenarioMatrix, ...
    "Verbose", logical(p.Results.Verbose));
out.ZCDPEMetrics = sixgr.rach.ZCDPEMetrics(out.TrialTable, out.ROTable, ...
    localMetricConfig(out), "WriteOutputs", false);
end

function cfg = localBaseStruct(baseCfg)
if isstruct(baseCfg)
    cfg = baseCfg;
elseif isobject(baseCfg)
    cfg = struct(baseCfg);
else
    error("sixgr:rach:runZCDPEValidationCampaign:BadInput", ...
        "Unsupported base PRACH config input.");
end
end

function outDir = localResolveOutputDir(~)
timestamp = char(datetime("now", "TimeZone", "local", "Format", "yyyyMMdd_HHmmss"));
outDir = fullfile(localRepoRoot(), "results", "zcdpe_lls_" + string(timestamp));
end

function cfg = localMetricConfig(out)
cfg = struct();
cfg.OutputDir = out.OutputDir;
if isfield(out, "ScenarioConfigs") && ~isempty(out.ScenarioConfigs)
    try
        cfg = out.ScenarioConfigs(1).Config;
        cfg.OutputDir = out.OutputDir;
    catch
    end
end
end

function scenarioMatrix = localDefaultScenarioMatrix()
rows = repmat(localScenario(), 15, 1);
rows(1) = localScenario("ScenarioName", "zcdpe_fr1_700mhz_fdd_tdlc_3kmh", "CarrierFrequencyHz", 700e6, "DuplexMode", "FDD", "PRACHConfigurationIndex", 16, "PRACHSubcarrierSpacing", 1.25, "PRACHFormat", "0", "ChannelModel", "TDL-C", "Speed_kmh", 3, "ZCDPE", struct("Enable", true, "DPI_D", 4, "DPI_d", 0, "NumSymbols", 1));
rows(2) = localScenario("ScenarioName", "zcdpe_fr1_2ghz_fdd_cfo_enabled", "CarrierFrequencyHz", 2e9, "DuplexMode", "FDD", "PRACHConfigurationIndex", 16, "PRACHSubcarrierSpacing", 1.25, "PRACHFormat", "0", "ChannelModel", "TDL-C", "EnableFrequencyOffset", true, "EnableFrequencyEstimationMetric", true, "UEFrequencyOffsetHz", 450, "ZCDPE", struct("Enable", true, "DPI_D", 4, "DPI_d", 0, "NumSymbols", 1));
rows(3) = localScenario("ScenarioName", "zcdpe_midband_4ghz_tdd_timing_uncertainty", "EnableTimingUncertainty", true, "TimingUncertaintyMax_us", 1.5, "ZCDPE", struct("Enable", true, "DPI_D", 4, "DPI_d", 1, "NumSymbols", 2));
rows(4) = localScenario("ScenarioName", "zcdpe_7ghz_tdd_high_doppler", "CarrierFrequencyHz", 7e9, "Speed_kmh", 120, "ZCDPE", struct("Enable", true, "DPI_D", 4, "DPI_d", 2, "NumSymbols", 2));
rows(5) = localScenario("ScenarioName", "zcdpe_collision_2ue_per_ro", "NumUEsPerRO", 2, "EnableCollisionMode", true, "ZCDPE", struct("Enable", true, "DPI_D", 4, "DPI_d", [0 2], "NumSymbols", 2));
rows(6) = localScenario("ScenarioName", "zcdpe_false_alarm_noise_only", "ChannelModel", "AWGN", "NumUEsPerRO", 0, "ActivePreamblePattern", false, "ZCDPE", struct("Enable", true, "DPI_D", 4, "DPI_d", 0, "NumSymbols", 2));
rows(7) = localScenario("ScenarioName", "zcdpe_intercell_interference_optional", "EnableInterCellInterference", true, "ZCDPE", struct("Enable", true, "DPI_D", 4, "DPI_d", 1, "NumSymbols", 2));
rows(8) = localScenario("ScenarioName", "zcdpe_b4_backward_compat_d0", "PRACHFormat", "B4", "PRACHConfigurationIndex", 159, "ChannelModel", "AWGN", "ZCDPE", struct("Enable", true, "DPI_D", 4, "DPI_d", 0, "NumSymbols", 12));
rows(9) = localScenario("ScenarioName", "zcdpe_b4_d1_awgn", "PRACHFormat", "B4", "PRACHConfigurationIndex", 159, "ChannelModel", "AWGN", "ZCDPE", struct("Enable", true, "DPI_D", 4, "DPI_d", 1, "NumSymbols", 12));
rows(10) = localScenario("ScenarioName", "zcdpe_b4_d2_tdlc", "PRACHFormat", "B4", "PRACHConfigurationIndex", 159, "ChannelModel", "TDL-C", "DelaySpread_ns", 300, "Speed_kmh", 30, "ZCDPE", struct("Enable", true, "DPI_D", 4, "DPI_d", 2, "NumSymbols", 12));
rows(11) = localScenario("ScenarioName", "zcdpe_hst_500kmh_d3", "PRACHFormat", "B4", "PRACHConfigurationIndex", 159, "ChannelModel", "TDL-C", "DelaySpread_ns", 100, "Speed_kmh", 500, "ZCDPE", struct("Enable", true, "DPI_D", 4, "DPI_d", 3, "NumSymbols", 12));
rows(12) = localScenario("ScenarioName", "zcdpe_ntn_1000kmh_d0", "PRACHFormat", "0", "PRACHConfigurationIndex", 16, "PRACHSubcarrierSpacing", 1.25, "ChannelModel", "TDL-C", "DelaySpread_ns", 1000, "Speed_kmh", 1000, "ZCDPE", struct("Enable", true, "DPI_D", 4, "DPI_d", 0, "NumSymbols", 12, "ResidualFreqBound_Hz", 1));
rows(13) = localScenario("ScenarioName", "zcdpe_2ue_dpi_orthogonality", "NumUEsPerRO", 2, "EnableCollisionMode", false, "ChannelModel", "AWGN", "ZCDPE", struct("Enable", true, "DPI_D", 4, "DPI_d", [0 2], "NumSymbols", 4));
rows(14) = localScenario("ScenarioName", "zcdpe_d5_m12_nonorthogonal_stress", "ChannelModel", "AWGN", "ZCDPE", struct("Enable", true, "DPI_D", 5, "DPI_d", 0, "NumSymbols", 12));
rows(15) = localScenario("ScenarioName", "zcdpe_d6_m12_orthogonal", "ChannelModel", "TDL-C", "DelaySpread_ns", 300, "Speed_kmh", 120, "ZCDPE", struct("Enable", true, "DPI_D", 6, "DPI_d", 3, "NumSymbols", 12));
scenarioMatrix = rows;
end

function cfg = localScenario(varargin)
cfg = struct( ...
    "ScenarioName", "zcdpe_prach", ...
    "CarrierFrequencyHz", 4e9, ...
    "DuplexMode", "TDD", ...
    "CarrierSCSkHz", 30, ...
    "NSizeGrid", 273, ...
    "PRACHConfigurationIndex", 86, ...
    "PRACHSubcarrierSpacing", 15, ...
    "PRACHFormat", "A1", ...
    "ChannelModel", "AWGN", ...
    "DelaySpread_ns", 300, ...
    "Speed_kmh", 3, ...
    "EnableFrequencyOffset", false, ...
    "EnableFrequencyEstimationMetric", false, ...
    "UEFrequencyOffsetHz", 0, ...
    "EnableTimingUncertainty", false, ...
    "TimingUncertaintyMax_us", 0, ...
    "NumUEsPerRO", 1, ...
    "EnableCollisionMode", false, ...
    "EnableInterCellInterference", false, ...
    "ActivePreamblePattern", true, ...
    "NumPRACHOccasions", 1, ...
    "NumSlots", 80, ...
    "NumSubframes", 40, ...
    "NumTrials", 2, ...
    "SNRSweep_dB", 18, ...
    "ThresholdSweep", 0.05, ...
    "ZCDPE", struct("Enable", true, "DPI_D", 4, "DPI_d", 0, "NumSymbols", 2));
for iArg = 1:2:numel(varargin)
    cfg.(varargin{iArg}) = varargin{iArg + 1};
end
end

function repoRoot = localRepoRoot()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
