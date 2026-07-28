function prachCfg = PRACHConfig(baseCfg, varargin)
%PRACHCONFIG Resolve and validate a waveform-accurate PRACH LLS scenario.
%
%   PRACHCFG = sixgr.rach.PRACHConfig(BASECFG) resolves a serializable
%   configuration struct used by the PRACH waveform Tx/channel/Rx chain.
%   BASECFG can be either a full SixGR simulator config or a focused PRACH
%   study struct.

if nargin < 1 || isempty(baseCfg)
    baseCfg = sixgr.config.defaultConfig();
end

p = inputParser;
p.FunctionName = "sixgr.rach.PRACHConfig";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "FrequencyRange", [], @(x) isempty(x) || ...
    any(strcmpi(string(x), ["FR1","FR2","FR2-1","FR2-2"])));
addParameter(p, "DuplexMode", [], @(x) isempty(x) || ...
    any(strcmpi(string(x), ["FDD","TDD","SUL"])));
addParameter(p, "CarrierFrequencyHz", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x > 0));
addParameter(p, "CarrierSCSkHz", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x > 0));
addParameter(p, "NSizeGrid", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 1));
addParameter(p, "NCellID", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0));
addParameter(p, "PRACHConfigurationIndex", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0));
addParameter(p, "PRACHFormat", [], @(x) isempty(x) || (ischar(x) || (isstring(x) && isscalar(x))));
addParameter(p, "PRACHSubcarrierSpacing", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x > 0));
addParameter(p, "SequenceIndex", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0));
addParameter(p, "LogicalRootSequenceIndex", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0));
addParameter(p, "PreambleIndex", [], @(x) isempty(x) || isnumeric(x));
addParameter(p, "RestrictedSet", [], @(x) isempty(x) || (ischar(x) || (isstring(x) && isscalar(x))));
addParameter(p, "ZeroCorrelationZone", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0));
addParameter(p, "FrequencyStart", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0));
addParameter(p, "Msg1FDM", [], @(x) isempty(x) || ...
    (isscalar(x) && isnumeric(x) && isfinite(x) && any(x == [1 2 4 8])));
addParameter(p, "RBOffset", [], @(x) isempty(x) || ...
    (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0 && x == fix(x)));
addParameter(p, "RBSetOffset", [], @(x) isempty(x) || ...
    (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0 && x == fix(x)));
addParameter(p, "NumPRACHOccasions", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 1));
addParameter(p, "NumSlots", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 1));
addParameter(p, "NumSubframes", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 1));
addParameter(p, "NumTrials", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 1));
addParameter(p, "ActivePreamblePattern", [], @(x) isempty(x) || isnumeric(x) || islogical(x));
addParameter(p, "NumRxAntennas", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 1));
addParameter(p, "NumTxAntennas", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 1));
addParameter(p, "NumUEsPerRO", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0));
addParameter(p, "EnableCollisionMode", [], @(x) isempty(x) || islogical(x) || isnumeric(x));
addParameter(p, "EnableInterCellInterference", [], @(x) isempty(x) || islogical(x) || isnumeric(x));
addParameter(p, "EnableFrequencyOffset", [], @(x) isempty(x) || islogical(x) || isnumeric(x));
addParameter(p, "EnablePhaseNoise", [], @(x) isempty(x) || islogical(x) || isnumeric(x));
addParameter(p, "EnableTimingUncertainty", [], @(x) isempty(x) || islogical(x) || isnumeric(x));
addParameter(p, "EnableFrequencyEstimationMetric", [], @(x) isempty(x) || islogical(x) || isnumeric(x));
addParameter(p, "DetectionThresholdMode", [], @(x) isempty(x) || any(strcmpi(string(x), ["fixed","auto"])));
addParameter(p, "DetectionThreshold", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0));
addParameter(p, "SNRSweep_dB", [], @(x) isempty(x) || isnumeric(x));
addParameter(p, "ThresholdSweep", [], @(x) isempty(x) || isnumeric(x));
addParameter(p, "ChannelModel", [], @(x) isempty(x) || (ischar(x) || (isstring(x) && isscalar(x))));
addParameter(p, "DelaySpread_ns", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0));
addParameter(p, "Speed_kmh", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0));
addParameter(p, "CellRadius_m", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0));
addParameter(p, "TimingUncertaintyMin_us", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x)));
addParameter(p, "TimingUncertaintyMax_us", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x)));
addParameter(p, "UEFrequencyOffsetHz", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x)));
addParameter(p, "TRPFrequencyOffsetHz", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x)));
addParameter(p, "PhaseNoiseStdRad", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0));
addParameter(p, "InterCellRelativePower_dB", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x)));
addParameter(p, "TargetFalseAlarmProbability", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x > 0 && x < 1));
addParameter(p, "TimingTolerance_us", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0));
addParameter(p, "Seed", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x)));
addParameter(p, "OutputDir", [], @(x) isempty(x) || ischar(x) || (isstring(x) && isscalar(x)));
parse(p, baseCfg, varargin{:});
opts = p.Results;

cfg = localStructFromInput(baseCfg);

prachCfg = struct();
prachCfg.ScenarioName = localResolveText(localResolveField(cfg, {"ScenarioName", "scenario.name", "meta.scenario_name"}, "prach_lls"));
prachCfg.FrequencyRange = upper(localResolveText(localFirstNonEmpty(opts.FrequencyRange, ...
    localResolveField(cfg, {"prach_lls.FrequencyRange", "random_access.frequency_range", "phy.prach.frequencyRange"}, ""))));
prachCfg.DuplexMode = upper(localResolveText(localFirstNonEmpty(opts.DuplexMode, ...
    localResolveField(cfg, {"prach_lls.DuplexMode", "random_access.duplex_mode", "phy.duplex.mode", "frequency.duplex_mode"}, "FDD"))));
prachCfg.CarrierFrequencyHz = double(localResolveScalar(localFirstNonEmpty(opts.CarrierFrequencyHz, ...
    localResolveField(cfg, {"prach_lls.CarrierFrequencyHz", "random_access.carrier_frequency_hz", "channel.fc_Hz", "carrier.center_frequency_hz", "frequency.center_frequency_hz"}, 700e6))));
prachCfg.CarrierSCSkHz = double(localResolveScalar(localFirstNonEmpty(opts.CarrierSCSkHz, ...
    localResolveField(cfg, {"prach_lls.CarrierSCSkHz", "random_access.carrier_scs_khz", "phy.carrier.SubcarrierSpacing", "carrier.subcarrier_spacing_khz", "frame.scs_khz"}, 15))));
prachCfg.NSizeGrid = round(double(localResolveScalar(localFirstNonEmpty(opts.NSizeGrid, ...
    localResolveField(cfg, {"prach_lls.NSizeGrid", "random_access.n_size_grid", "phy.carrier.NSizeGrid", "carrier.n_rb", "frequency.n_size_grid"}, 52)))));
prachCfg.NCellID = round(double(localResolveScalar(localFirstNonEmpty(opts.NCellID, ...
    localResolveField(cfg, {"prach_lls.NCellID", "random_access.n_cell_id", "phy.carrier.NCellID", "carrier.n_cell_id"}, 1)))));
prachCfg.PRACHConfigurationIndex = round(double(localResolveScalar(localFirstNonEmpty(opts.PRACHConfigurationIndex, ...
    localResolveField(cfg, {"prach_lls.PRACHConfigurationIndex", "phy.prach.configurationIndex", "random_access.configuration_index"}, 16)))));
prachCfg.RequestedPRACHFormat = upper(localResolveText(localFirstNonEmpty(opts.PRACHFormat, ...
    localResolveField(cfg, {"prach_lls.PRACHFormat", "phy.prach.preambleFormat", "random_access.prach_format"}, ""))));
prachCfg.PRACHSubcarrierSpacing = double(localResolveScalar(localFirstNonEmpty(opts.PRACHSubcarrierSpacing, ...
    localResolveField(cfg, {"prach_lls.PRACHSubcarrierSpacing", "phy.prach.subcarrierSpacing_kHz", "random_access.subcarrier_spacing_khz"}, 1.25))));
prachCfg.SequenceIndex = round(double(localResolveScalar(localFirstNonEmpty(opts.SequenceIndex, opts.LogicalRootSequenceIndex, ...
    localResolveField(cfg, {"prach_lls.SequenceIndex", "prach_lls.LogicalRootSequenceIndex", "random_access.sequence_index", "random_access.logical_root_sequence_index", "phy.prach.rootSeqIndex", "random_access.root_sequence_index"}, 0)))));
prachCfg.LogicalRootSequenceIndex = prachCfg.SequenceIndex;
prachCfg.PreambleIndex = localResolveArray(localFirstNonEmpty(opts.PreambleIndex, ...
    localResolveField(cfg, {"prach_lls.PreambleIndex", "phy.prach.preambleIndex", "random_access.preamble_index"}, 0)));
prachCfg.RestrictedSet = char(localNormalizeRestrictedSet(localFirstNonEmpty(opts.RestrictedSet, ...
    localResolveField(cfg, {"prach_lls.RestrictedSet", "random_access.restricted_set", "phy.prach.restrictedSet"}, "UnrestrictedSet"))));
prachCfg.ZeroCorrelationZone = round(double(localResolveScalar(localFirstNonEmpty(opts.ZeroCorrelationZone, ...
    localResolveField(cfg, {"prach_lls.ZeroCorrelationZone", "phy.prach.zeroCorrelationZone", "random_access.zero_correlation_zone"}, 8)))));
prachCfg.FrequencyStart = round(double(localResolveScalar(localFirstNonEmpty(opts.FrequencyStart, ...
    localResolveField(cfg, {"prach_lls.FrequencyStart", "random_access.frequency_start", "phy.prach.frequencyStart"}, 0)))));
prachCfg.Msg1FDM = round(double(localResolveScalar(localFirstNonEmpty(opts.Msg1FDM, ...
    localResolveField(cfg, {"prach_lls.Msg1FDM", "random_access.msg1_fdm", "phy.prach.msg1FDM"}, 1)))));
prachCfg.RBOffset = round(double(localResolveScalar(localFirstNonEmpty(opts.RBOffset, ...
    localResolveField(cfg, {"prach_lls.RBOffset", "random_access.rb_offset", "phy.prach.RBOffset"}, 0)))));
prachCfg.RBSetOffset = round(double(localResolveScalar(localFirstNonEmpty(opts.RBSetOffset, ...
    localResolveField(cfg, {"prach_lls.RBSetOffset", "random_access.rb_set_offset", "phy.prach.RBSetOffset"}, 0)))));
prachCfg.NumPRACHOccasions = round(double(localResolveScalar(localFirstNonEmpty(opts.NumPRACHOccasions, ...
    localResolveField(cfg, {"prach_lls.NumPRACHOccasions", "random_access.num_prach_occasions"}, 4)))));
prachCfg.NumSlots = round(double(localResolveScalar(localFirstNonEmpty(opts.NumSlots, ...
    localResolveField(cfg, {"prach_lls.NumSlots", "random_access.num_slots", "run.totalSlots", "simulation.n_slots"}, max(20, prachCfg.NumPRACHOccasions * 4))))));
prachCfg.NumSubframes = round(double(localResolveScalar(localFirstNonEmpty(opts.NumSubframes, ...
    localResolveField(cfg, {"prach_lls.NumSubframes", "random_access.num_subframes"}, max(1, ceil(prachCfg.NumSlots / 2)))))));
prachCfg.NumTrials = round(double(localResolveScalar(localFirstNonEmpty(opts.NumTrials, ...
    localResolveField(cfg, {"prach_lls.NumTrials", "random_access.num_trials", "random_access.min_detection_trials"}, 12)))));
prachCfg.ActivePreamblePattern = localResolveArray(localFirstNonEmpty(opts.ActivePreamblePattern, ...
    localResolveField(cfg, {"prach_lls.ActivePreamblePattern", "random_access.active_preamble_pattern"}, true)));
prachCfg.NumRxAntennas = round(double(localResolveScalar(localFirstNonEmpty(opts.NumRxAntennas, ...
    localResolveField(cfg, {"prach_lls.NumRxAntennas", "random_access.num_rx_antennas", ...
    "phy.prach.NumRxAntennas", "scenario.bs.nRxAnt", "scenario.bs.nTxAnt", ...
    "channel.nTxAnt", "mimo.n_tx_ant"}, 1)))));
prachCfg.NumTxAntennas = round(double(localResolveScalar(localFirstNonEmpty(opts.NumTxAntennas, ...
    localResolveField(cfg, {"prach_lls.NumTxAntennas", "random_access.num_tx_antennas", ...
    "phy.prach.NumTxAntennas", "scenario.ue.nTxAnt", "phy.pusch.NumAntennaPorts", ...
    "channel.nRxAnt", "mimo.n_rx_ant"}, 1)))));
prachCfg.NumUEsPerRO = round(double(localResolveScalar(localFirstNonEmpty(opts.NumUEsPerRO, ...
    localResolveField(cfg, {"prach_lls.NumUEsPerRO", "random_access.num_ues_per_ro"}, 1)))));
prachCfg.EnableCollisionMode = logical(localResolveScalar(localFirstNonEmpty(opts.EnableCollisionMode, ...
    localResolveField(cfg, {"prach_lls.EnableCollisionMode", "random_access.enable_collision_mode"}, false))));
prachCfg.EnableInterCellInterference = logical(localResolveScalar(localFirstNonEmpty(opts.EnableInterCellInterference, ...
    localResolveField(cfg, {"prach_lls.EnableInterCellInterference", "random_access.enable_inter_cell_interference"}, false))));
prachCfg.EnableFrequencyOffset = logical(localResolveScalar(localFirstNonEmpty(opts.EnableFrequencyOffset, ...
    localResolveField(cfg, {"prach_lls.EnableFrequencyOffset", "random_access.enable_frequency_offset"}, false))));
prachCfg.EnablePhaseNoise = logical(localResolveScalar(localFirstNonEmpty(opts.EnablePhaseNoise, ...
    localResolveField(cfg, {"prach_lls.EnablePhaseNoise", "random_access.enable_phase_noise"}, false))));
prachCfg.EnableTimingUncertainty = logical(localResolveScalar(localFirstNonEmpty(opts.EnableTimingUncertainty, ...
    localResolveField(cfg, {"prach_lls.EnableTimingUncertainty", "random_access.enable_timing_uncertainty"}, false))));
prachCfg.EnableFrequencyEstimationMetric = logical(localResolveScalar(localFirstNonEmpty(opts.EnableFrequencyEstimationMetric, ...
    localResolveField(cfg, {"prach_lls.EnableFrequencyEstimationMetric", "random_access.enable_frequency_estimation_metric"}, false))));
prachCfg.DetectionThresholdMode = lower(localResolveText(localFirstNonEmpty(opts.DetectionThresholdMode, ...
    localResolveField(cfg, {"prach_lls.DetectionThresholdMode", "random_access.detection_threshold_mode"}, "fixed"))));
prachCfg.DetectionThreshold = double(localResolveScalar(localFirstNonEmpty(opts.DetectionThreshold, ...
    localResolveField(cfg, {"prach_lls.DetectionThreshold", "random_access.detection_threshold", "phy.prach.detectionThreshold"}, 0.02))));
prachCfg.SNRSweep_dB = double(localResolveArray(localFirstNonEmpty(opts.SNRSweep_dB, ...
    localResolveField(cfg, {"prach_lls.SNRSweep_dB", "random_access.snr_sweep_db"}, [-12 -6 0 6 12]))));
prachCfg.ThresholdSweep = double(localResolveArray(localFirstNonEmpty(opts.ThresholdSweep, ...
    localResolveField(cfg, {"prach_lls.ThresholdSweep", "random_access.threshold_sweep"}, prachCfg.DetectionThreshold))));
prachCfg.ChannelModel = upper(localResolveText(localResolveChannelModel(cfg, opts.ChannelModel)));
prachCfg.DelayProfile = prachCfg.ChannelModel;
prachCfg.DelaySpread_ns = double(localResolveScalar(localFirstNonEmpty(opts.DelaySpread_ns, ...
    localResolveField(cfg, {"channel.delaySpread_s", "channel.fading.delaySpread_s", ...
    "prach_lls.DelaySpread_ns", "random_access.delay_spread_ns"}, 100))));
if prachCfg.DelaySpread_ns < 1e-3
    prachCfg.DelaySpread_ns = prachCfg.DelaySpread_ns * 1e9;
end
prachCfg.Speed_kmh = double(localResolveScalar(localFirstNonEmpty(opts.Speed_kmh, ...
    localResolveField(cfg, {"prach_lls.Speed_kmh", "scenario.mobility.speed_kmh", ...
    "mobility.ue_speed_kmh", "channels.mobility_kmph", "random_access.speed_kmh"}, 3))));
prachCfg.MaxDopplerHz = localSpeedToDopplerHz(prachCfg.Speed_kmh, prachCfg.CarrierFrequencyHz);
prachCfg.CellRadius_m = double(localResolveScalar(localFirstNonEmpty(opts.CellRadius_m, ...
    localResolveField(cfg, {"prach_lls.CellRadius_m", "random_access.cell_radius_m"}, 500))));
prachCfg.TimingUncertaintyMin_us = double(localResolveScalar(localFirstNonEmpty(opts.TimingUncertaintyMin_us, ...
    localResolveField(cfg, {"prach_lls.TimingUncertaintyMin_us", "random_access.timing_uncertainty_min_us"}, 0))));
prachCfg.TimingUncertaintyMax_us = double(localResolveScalar(localFirstNonEmpty(opts.TimingUncertaintyMax_us, ...
    localResolveField(cfg, {"prach_lls.TimingUncertaintyMax_us", "random_access.timing_uncertainty_max_us"}, NaN))));
prachCfg.UEFrequencyOffsetHz = double(localResolveScalar(localFirstNonEmpty(opts.UEFrequencyOffsetHz, ...
    localResolveField(cfg, {"prach_lls.UEFrequencyOffsetHz", "random_access.ue_frequency_offset_hz"}, 0))));
prachCfg.TRPFrequencyOffsetHz = double(localResolveScalar(localFirstNonEmpty(opts.TRPFrequencyOffsetHz, ...
    localResolveField(cfg, {"prach_lls.TRPFrequencyOffsetHz", "random_access.trp_frequency_offset_hz"}, 0))));
prachCfg.PhaseNoiseStdRad = double(localResolveScalar(localFirstNonEmpty(opts.PhaseNoiseStdRad, ...
    localResolveField(cfg, {"prach_lls.PhaseNoiseStdRad", "random_access.phase_noise_std_rad"}, 1e-3))));
prachCfg.InterCellRelativePower_dB = double(localResolveScalar(localFirstNonEmpty(opts.InterCellRelativePower_dB, ...
    localResolveField(cfg, {"prach_lls.InterCellRelativePower_dB", "random_access.inter_cell_relative_power_db"}, -3))));
prachCfg.TargetFalseAlarmProbability = double(localResolveScalar(localFirstNonEmpty(opts.TargetFalseAlarmProbability, ...
    localResolveField(cfg, {"prach_lls.TargetFalseAlarmProbability", "random_access.target_false_alarm_probability"}, 1e-3))));
prachCfg.TimingTolerance_us = double(localResolveScalar(localFirstNonEmpty(opts.TimingTolerance_us, ...
    localResolveField(cfg, {"prach_lls.TimingTolerance_us", "random_access.timing_tolerance_us"}, NaN))));
prachCfg.Seed = round(double(localResolveScalar(localFirstNonEmpty(opts.Seed, ...
    localResolveField(cfg, {"prach_lls.Seed", "run.seed"}, 5489)))));

if isempty(opts.OutputDir)
    timestamp = char(datetime("now", "TimeZone", "local", "Format", "yyyyMMdd_HHmmss"));
    prachCfg.OutputDir = fullfile(localRepoRoot(), "results", "prach_lls_" + string(timestamp));
else
    prachCfg.OutputDir = char(string(opts.OutputDir));
end

configuredRange = upper(strtrim(string(prachCfg.FrequencyRange)));
rangeInfo = sixgr.phy.frame.FrequencyRangeResolver.resolve( ...
    "CenterFrequencyHz", prachCfg.CarrierFrequencyHz);
resolvedRange = string(rangeInfo.FrequencyRange);
if strlength(configuredRange) > 0
    if configuredRange == "FR2"
        if ~startsWith(resolvedRange, "FR2")
            error("sixgr:phy:frame:FrequencyRangeMismatch", ...
                "Configured FR2 conflicts with PRACH carrier frequency %.12g Hz.", ...
                prachCfg.CarrierFrequencyHz);
        end
    elseif configuredRange ~= resolvedRange
        error("sixgr:phy:frame:FrequencyRangeMismatch", ...
            "Configured %s conflicts with PRACH carrier-frequency range %s.", ...
            configuredRange, resolvedRange);
    end
end
prachCfg.FrequencyRangeSubtype = char(resolvedRange);
if startsWith(resolvedRange, "FR2")
    prachCfg.FrequencyRange = "FR2";
else
    prachCfg.FrequencyRange = "FR1";
end
if ~any(strcmpi(char(string(prachCfg.DuplexMode)), {'FDD','TDD','SUL'}))
    error("sixgr:phy:frame:InvalidPRACHFrequencyDuplexContext", ...
        "PRACH DuplexMode must be FDD, TDD, or SUL.");
end

localValidateResolvedConfig(prachCfg);
[carrier, prach] = localBuildToolboxConfigs(prachCfg);
localAssertZCZRuntimeResolvable(prachCfg, prach);
[occasionResolution, requiredSlots] = localResolveOccasionPeriod( ...
    prachCfg, carrier, prach);
prachCfg.NumSlots = max(prachCfg.NumSlots, requiredSlots);
[firstOccasion, sampleRateHz, carrier, prach] = ...
    localResolveFirstOccasion(carrier, prach, prachCfg);

prachCfg.ToolboxCarrier = carrier;
prachCfg.ToolboxPRACH = prach;
prachCfg.ResolvedPRACHFormat = upper(strtrim(string(prach.Format)));
prachCfg.PreambleCount = 64;
prachCfg.FirstActiveOccasion = firstOccasion;
prachCfg.PRACHOccasionResolution = occasionResolution;
prachCfg.SampleRate_Hz = double(sampleRateHz);
prachCfg = localValidateZCZRuntimeGuard(prachCfg);
prachCfg.TimingTolerance_us = localResolveTimingTolerance(prachCfg);
prachCfg.ZCDPE = sixgr.rach.ZCDPEConfig(baseCfg, "NumSymbols", localResolveZCDPENumSymbols(prachCfg, baseCfg));
prachCfg.ZCDPEEnabled = localResolveZCDPEEnabled(baseCfg);
prachCfg.ConfigExport = localMakeSerializable(prachCfg);
localPublishConfigEvidence(prachCfg, cfg);
end

function localAssertZCZRuntimeResolvable(cfg, prach)
lra = NaN;
try
    lra = double(prach.LRA);
catch
end
if ~(isscalar(lra) && isfinite(lra) && lra > 0)
    return;
end
localResolveNCS(lra, cfg.ZeroCorrelationZone, cfg.RestrictedSet);
end

function cfg = localValidateZCZRuntimeGuard(cfg)
lra = NaN;
try
    lra = double(cfg.ToolboxPRACH.LRA);
catch
end
if ~(isscalar(lra) && isfinite(lra) && lra > 0)
    cfg.ZCZNCS = NaN;
    cfg.ZCZMaxCyclicShiftsPerRoot = NaN;
    cfg.ZCZValidationStatus = "not_available_no_lra";
    return;
end
ncs = localResolveNCS(lra, cfg.ZeroCorrelationZone, cfg.RestrictedSet);
cfg.ZCZNCS = double(ncs);
if ncs <= 0
    maxPerRoot = 1;
else
    maxPerRoot = max(1, floor(double(lra) / double(ncs)));
end
cfg.ZCZMaxCyclicShiftsPerRoot = double(maxPerRoot);
activeCount = localActivePreambleCountForOneRoot(cfg);
if activeCount > maxPerRoot
    error("sixgr:rach:PRACHConfig:ZCZGuardInsufficient", ...
        "ZeroCorrelationZone=%g gives N_CS=%g for L_RA=%g, allowing %g cyclic shifts per root; configured active preambles per root=%g exceeds that guard.", ...
        double(cfg.ZeroCorrelationZone), double(ncs), double(lra), double(maxPerRoot), double(activeCount));
end
cfg.ZCZValidationStatus = "OK";
end

function count = localActivePreambleCountForOneRoot(cfg)
p = unique(double(cfg.PreambleIndex(:)));
p = p(isfinite(p) & p >= 0);
count = max(1, numel(p));
if logical(cfg.EnableCollisionMode)
    % Collision mode intentionally maps several UEs to the same preamble.
    count = max(1, count);
else
    count = max(count, max(1, round(double(cfg.NumUEsPerRO))));
end
end

function ncs = localResolveNCS(lra, zcz, restrictedSet)
zcz = max(0, min(15, round(double(zcz))));
restrictedSet = localNormalizeRestrictedSet(restrictedSet);
try
    p = nrPRACHConfig;
    tables = p.Tables;
    if round(double(lra)) == 839
        T = tables.NCSFormat012;
        col = char(restrictedSet);
        if ~ismember(col, string(T.Properties.VariableNames))
            error("sixgr:rach:PRACHConfig:BadRestrictedSetColumn", ...
                "RestrictedSet=%s is not present in nrPRACHConfig.Tables.NCSFormat012.", col);
        end
        ncs = double(T.(col)(zcz + 1));
    elseif any(round(double(lra)) == [139 571 1151])
        if restrictedSet ~= "UnrestrictedSet"
            error("sixgr:rach:PRACHConfig:RestrictedSetInvalidForShortFormat", ...
                "Restricted-set PRACH applies to long-sequence formats in this strict profile; L_RA=%g is short-sequence and must use UnrestrictedSet.", ...
                double(lra));
        end
        T = tables.NCSFormatABC;
        col = "LRA_" + string(round(double(lra)));
        if ~ismember(col, string(T.Properties.VariableNames))
            error("sixgr:rach:PRACHConfig:UnsupportedLRAForZCZValidation", ...
                "No nrPRACHConfig N_CS/ZCZ table column is available for L_RA=%g.", double(lra));
        end
        ncs = double(T.(char(col))(zcz + 1));
    else
        error("sixgr:rach:PRACHConfig:UnsupportedLRAForZCZValidation", ...
            "No runtime N_CS/ZCZ validation table is implemented for L_RA=%g.", double(lra));
    end
catch ME
    if startsWith(string(ME.identifier), "sixgr:")
        rethrow(ME);
    end
    error("sixgr:rach:PRACHConfig:NCSResolveFailed", ...
        "Failed to resolve N_CS from nrPRACHConfig tables: %s", ME.message);
end
if ~(isfinite(ncs) && ncs >= 0)
    error("sixgr:rach:PRACHConfig:InvalidRestrictedSetZCZ", ...
        "RestrictedSet=%s with ZeroCorrelationZone=%g has no finite N_CS for L_RA=%g.", ...
        string(restrictedSet), double(zcz), double(lra));
end
end

function cfg = localStructFromInput(baseCfg)
if isstruct(baseCfg)
    cfg = baseCfg;
elseif isobject(baseCfg)
    cfg = struct(baseCfg);
else
    error("sixgr:rach:PRACHConfig:BadInput", "Unsupported PRACH config input.");
end
end

function value = localResolveField(cfg, paths, defaultValue)
value = [];
topLevelNames = strings(0, 1);
for iPath = 1:numel(paths)
    token = string(paths{iPath});
    parts = split(token, ".");
    topLevelNames(end+1, 1) = parts(end); %#ok<AGROW>
end
topLevelNames = unique(topLevelNames);
for iName = 1:numel(topLevelNames)
    name = char(topLevelNames(iName));
    if isfield(cfg, name) && ~isempty(cfg.(name))
        value = cfg.(name);
        return;
    end
end
for iPath = 1:numel(paths)
    candidate = sixgr.util.structGet(cfg, paths{iPath}, []);
    if ~isempty(candidate)
        value = candidate;
        return;
    end
end
value = defaultValue;
end

function value = localResolveText(rawValue)
if isempty(rawValue)
    value = '';
    return;
end
txt = string(rawValue);
if isempty(txt)
    value = '';
else
    value = char(txt(1));
end
end

function value = localNormalizeRestrictedSet(rawValue)
token = lower(strtrim(string(rawValue)));
token = erase(token, "-");
token = erase(token, "_");
token = erase(token, " ");
switch token
    case {"", "unrestricted", "unrestrictedset", "none"}
        value = "UnrestrictedSet";
    case {"restrictedsettypea", "restrictedseta", "restrictedtypea", "restricteda", "typea", "a"}
        value = "RestrictedSetTypeA";
    case {"restrictedsettypeb", "restrictedsetb", "restrictedtypeb", "restrictedb", "typeb", "b"}
        value = "RestrictedSetTypeB";
    otherwise
        error("sixgr:rach:PRACHConfig:BadRestrictedSet", ...
            "RestrictedSet must be UnrestrictedSet, RestrictedSetTypeA, or RestrictedSetTypeB. Got '%s'.", string(rawValue));
end
end

function value = localResolveScalar(rawValue)
value = rawValue;
end

function value = localResolveArray(rawValue)
value = rawValue;
end

function value = localResolveChannelModel(cfg, explicitValue)
if ~isempty(explicitValue)
    value = explicitValue;
    return;
end
value = localResolveField(cfg, {"prach_lls.ChannelModel", "random_access.channel_model", "channel.tdlProfile", "channel.cdlProfile", "channel.model"}, "AWGN");
modelToken = upper(string(value));
if modelToken == "TDL"
    concrete = localResolveField(cfg, {"channel.tdlProfile"}, "");
    if strlength(string(concrete)) > 0
        value = concrete;
    end
elseif modelToken == "CDL"
    concrete = localResolveField(cfg, {"channel.cdlProfile"}, "");
    if strlength(string(concrete)) > 0
        value = concrete;
    end
end
end

function value = localFirstNonEmpty(varargin)
value = [];
for iArg = 1:nargin
    candidate = varargin{iArg};
    if isempty(candidate)
        continue;
    end
    if (ischar(candidate) || isstring(candidate)) && strlength(string(candidate)) == 0
        continue;
    end
    value = candidate;
    return;
end
end

function localValidateResolvedConfig(cfg)
allowedChannels = ["AWGN", ...
    "TDL-A","TDL-B","TDL-C","TDL-D","TDL-E", ...
    "CDL-A","CDL-B","CDL-C","CDL-D","CDL-E"];
if ~any(strcmpi(cfg.ChannelModel, allowedChannels))
    error("sixgr:rach:PRACHConfig:UnsupportedChannelModel", ...
        "ChannelModel must be one of %s.", strjoin(cellstr(allowedChannels), ", "));
end
zcz = double(cfg.ZeroCorrelationZone);
if ~isfinite(zcz) || zcz < 0 || zcz > 15 || zcz ~= round(zcz)
    error("sixgr:rach:PRACHConfig:InvalidZCZ", ...
        "ZeroCorrelationZone must be an integer in [0..15] per TS 38.211 Table 6.3.3.2-2/3. Got: %g", zcz);
end
if zcz == 0
    warning("sixgr:rach:PRACHConfig:ZCZZero", ...
        "ZeroCorrelationZone=0 gives N_CS=0 with no cyclic-shift guard interval; use ZCZ >= 1 for non-zero cell-radius studies.");
end
if strcmpi(cfg.RestrictedSet, "UnrestrictedSet") && isfield(cfg, "Speed_kmh") && double(cfg.Speed_kmh) > 120
    warning("sixgr:rach:PRACHConfig:RestrictedSetRecommended", ...
        "Speed_kmh=%g exceeds 120 km/h while RestrictedSet='UnrestrictedSet'; consider a restricted set for high-Doppler PRACH studies.", ...
        double(cfg.Speed_kmh));
end
if ~(strcmpi(cfg.DetectionThresholdMode, "fixed") || strcmpi(cfg.DetectionThresholdMode, "auto"))
    error("sixgr:rach:PRACHConfig:BadThresholdMode", ...
        "DetectionThresholdMode must be 'fixed' or 'auto'.");
end
if cfg.NumPRACHOccasions < 1 || cfg.NumTrials < 1 || cfg.NumSlots < 1
    error("sixgr:rach:PRACHConfig:BadLoopSize", ...
        "NumPRACHOccasions, NumTrials, and NumSlots must all be >= 1.");
end
if cfg.EnableTimingUncertainty && ~isfinite(cfg.TimingUncertaintyMax_us)
    cfg.TimingUncertaintyMax_us = 1e6 * cfg.CellRadius_m / physconst("LightSpeed");
end
if isfinite(cfg.TimingUncertaintyMax_us) && cfg.TimingUncertaintyMax_us < cfg.TimingUncertaintyMin_us
    error("sixgr:rach:PRACHConfig:BadTimingRange", ...
        "TimingUncertaintyMax_us must be >= TimingUncertaintyMin_us.");
end
end

function [carrier, prach] = localBuildToolboxConfigs(cfg)
carrier = nrCarrierConfig;
carrier.SubcarrierSpacing = double(cfg.CarrierSCSkHz);
carrier.NSizeGrid = double(cfg.NSizeGrid);
carrier.NStartGrid = 0;
carrier.NCellID = double(cfg.NCellID);
carrier.CyclicPrefix = "normal";

prach = nrPRACHConfig;
prach.FrequencyRange = cfg.FrequencyRange;
prach.DuplexMode = cfg.DuplexMode;
prach.ConfigurationIndex = double(cfg.PRACHConfigurationIndex);
prach.SubcarrierSpacing = double(cfg.PRACHSubcarrierSpacing);
prach.SequenceIndex = double(cfg.SequenceIndex);
prach.PreambleIndex = double(localFirstPreamble(cfg.PreambleIndex));
prach.RestrictedSet = char(string(cfg.RestrictedSet));
prach.ZeroCorrelationZone = double(cfg.ZeroCorrelationZone);
prach.FrequencyStart = double(cfg.FrequencyStart);
prach.RBOffset = double(cfg.RBOffset);
prach.RBSetOffset = double(cfg.RBSetOffset);

resolvedFormat = upper(strtrim(string(prach.Format)));
requestedFormat = upper(strtrim(string(sixgr.util.structGet(cfg, "RequestedPRACHFormat", ""))));
if isempty(requestedFormat)
    requestedFormat = "";
else
    requestedFormat = requestedFormat(1);
end
if strlength(requestedFormat) > 0 && resolvedFormat ~= requestedFormat
    error("sixgr:rach:PRACHConfig:FormatMismatch", ...
        "Requested PRACHFormat=%s resolves to toolbox format %s for configuration index %g / PRACH SCS %g kHz.", ...
        requestedFormat, resolvedFormat, double(cfg.PRACHConfigurationIndex), double(cfg.PRACHSubcarrierSpacing));
end
end

function [resolution, requiredSlots] = localResolveOccasionPeriod( ...
        cfg, carrier, prach)
resolution = sixgr.phy.frame.PRACHOccasionResolver.resolve( ...
    "FrequencyRange", cfg.FrequencyRangeSubtype, ...
    "DuplexMode", cfg.DuplexMode, ...
    "ConfigurationIndex", cfg.PRACHConfigurationIndex, ...
    "CarrierSubcarrierSpacingKHz", carrier.SubcarrierSpacing, ...
    "CarrierCyclicPrefix", carrier.CyclicPrefix, ...
    "NSizeGrid", carrier.NSizeGrid, ...
    "NStartGrid", carrier.NStartGrid, ...
    "NCellID", carrier.NCellID, ...
    "PRACHSubcarrierSpacingKHz", prach.SubcarrierSpacing, ...
    "SequenceIndex", prach.SequenceIndex, ...
    "PreambleIndex", prach.PreambleIndex, ...
    "RestrictedSet", prach.RestrictedSet, ...
    "ZeroCorrelationZone", prach.ZeroCorrelationZone, ...
    "Msg1FDM", cfg.Msg1FDM, ...
    "Msg1FrequencyStart", prach.FrequencyStart, ...
    "RBOffset", prach.RBOffset, ...
    "RBSetOffset", prach.RBSetOffset);
occasionsPerPeriod = height(resolution.Occasions);
if occasionsPerPeriod < 1
    error("sixgr:rach:PRACHConfig:NoOccasion", ...
        "Canonical PRACH timing returned no occasion in its exact period.");
end
periodsNeeded = ceil(double(cfg.NumPRACHOccasions) / occasionsPerPeriod);
requiredSlots = ceil(periodsNeeded * double(resolution.PeriodCarrierSlots));
end

function [occasion, sampleRateHz, carrier, prach] = ...
        localResolveFirstOccasion(carrier, prach, cfg)
occasion = sixgr.rach.mapPRACHToOccasion(cfg, ...
    "OccasionIndex", 1, "Carrier", carrier, "PRACH", prach);
carrier.NFrame = double(occasion.Carrier.NFrame);
carrier.NSlot = double(occasion.Carrier.NSlot);
prach.NPRACHSlot = double(occasion.PRACH.NPRACHSlot);
prach.ActivePRACHSlot = double(occasion.PRACH.ActivePRACHSlot);
prach.TimeIndex = double(occasion.PRACH.TimeIndex);
prach.FrequencyIndex = double(occasion.PRACH.FrequencyIndex);
sampleRateHz = localEstimatePRACHSampleRate(carrier, prach);
end

function sampleRateHz = localEstimatePRACHSampleRate(carrier, prach)
info = nrPRACHOFDMInfo(carrier, prach);
sampleRateHz = double(info.SampleRate);
if ~(isscalar(sampleRateHz) && isfinite(sampleRateHz) && sampleRateHz > 0)
    error("sixgr:rach:PRACHConfig:InvalidToolboxSampleRate", ...
        "nrPRACHOFDMInfo did not return a positive finite sample rate.");
end
end

function value = localFirstPreamble(preambleSpec)
arr = double(preambleSpec(:));
arr = arr(isfinite(arr));
if isempty(arr)
    value = 0;
else
    value = arr(1);
end
end

function timingTolUs = localResolveTimingTolerance(cfg)
if isfinite(cfg.TimingTolerance_us)
    timingTolUs = double(cfg.TimingTolerance_us);
    return;
end
samplePeriodUs = 1e6 / max(cfg.SampleRate_Hz, eps);
timingTolUs = max(2 * samplePeriodUs, 0.25);
end

function fdHz = localSpeedToDopplerHz(speedKmh, carrierFrequencyHz)
c_mps = 299792458;
fdHz = max(0, double(speedKmh)) / 3.6 * max(0, double(carrierFrequencyHz)) / c_mps;
if ~(isfinite(fdHz) && fdHz >= 0)
    fdHz = 0;
end
end

function numSymbols = localResolveZCDPENumSymbols(cfg, baseCfg)
[actualSymbols, actualKnown] = localActualZCDPENumSymbols(cfg);
configured = [];
try
    baseStruct = localStructFromInput(baseCfg);
    configured = localResolveField(baseStruct, ...
        {"ZCDPE.NumSymbols", "zcdpe.num_symbols", "random_access.zcdpe_num_symbols"}, []);
catch
end
if ~isempty(configured)
    numSymbols = round(double(configured(1)));
    if actualKnown && numSymbols > actualSymbols
        error("sixgr:rach:PRACHConfig:ZCDPENumSymbolsUnavailable", ...
            "ZC-DPE NumSymbols=%g exceeds the %g repeated PRACH symbol group(s) available for the resolved PRACH format/configuration.", ...
            numSymbols, actualSymbols);
    end
    return;
end
numSymbols = actualSymbols;
end

function [numSymbols, known] = localActualZCDPENumSymbols(cfg)
numSymbols = 1;
known = false;
try
    lra = double(cfg.ToolboxPRACH.LRA);
    symbols = nrPRACH(cfg.FirstActiveOccasion.Carrier, cfg.FirstActiveOccasion.PRACH);
    if isfinite(lra) && lra > 0 && ~isempty(symbols)
        numSymbols = max(1, round(numel(symbols) / lra));
        known = true;
    end
catch
    try
        val = double(cfg.ToolboxPRACH.NumOccupiedSymbols);
        if isfinite(val) && val > 0
            numSymbols = round(val);
            known = true;
        end
    catch
    end
end
end

function tf = localResolveZCDPEEnabled(baseCfg)
design = lower(string(sixgr.util.structGet(baseCfg, "random_access.prach_design", "")));
tf = logical(sixgr.util.structGet(baseCfg, "ZCDPE.Enable", ...
    sixgr.util.structGet(baseCfg, "zcdpe.enable", ...
    sixgr.util.structGet(baseCfg, "random_access.zcdpe_enabled", design == "zcdpe"))));
end

function serializable = localMakeSerializable(cfg)
dropFields = {'ToolboxCarrier','ToolboxPRACH','FirstActiveOccasion','ConfigExport'};
serializable = rmfield(cfg, intersect(fieldnames(cfg), dropFields));
if isfield(serializable, "PreambleIndex")
    serializable.PreambleIndex = double(serializable.PreambleIndex);
end
if isfield(serializable, "ActivePreamblePattern")
    serializable.ActivePreamblePattern = double(serializable.ActivePreamblePattern);
end
end

function localPublishConfigEvidence(prachCfg, cfg)
consumer = "sixgr.rach.PRACHConfig";
scope = "prach_runtime_config";
objectType = "PRACHRuntimeConfig";

sixgr.config.publishConfigApplicationEvidence("record", ...
    "frequency.center_frequency_hz", "Carrier_Numerology_Grid", "channel.fc_Hz", consumer, prachCfg.CarrierFrequencyHz, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.CarrierFrequencyHz", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "frequency.duplex_mode", "Carrier_Numerology_Grid", "phy.duplex.mode", consumer, prachCfg.DuplexMode, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.DuplexMode", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "frame.scs_khz", "Carrier_Numerology_Grid", "phy.carrier.SubcarrierSpacing_kHz", consumer, prachCfg.CarrierSCSkHz, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.CarrierSCSkHz", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "frequency.n_size_grid", "Carrier_Numerology_Grid", "phy.carrier.NSizeGrid", consumer, prachCfg.NSizeGrid, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.NSizeGrid", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "random_access.enabled", "Random_Access_PRACH", "phy.prach.enable", consumer, sixgr.util.structGet(cfg, "phy.prach.enable", true), ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "cfg.phy.prach.enable", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "random_access.prach_format", "Random_Access_PRACH", "phy.prach.preambleFormat", consumer, prachCfg.RequestedPRACHFormat, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.RequestedPRACHFormat", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "random_access.configuration_index", "Random_Access_PRACH", "phy.prach.configurationIndex", consumer, prachCfg.PRACHConfigurationIndex, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.PRACHConfigurationIndex", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "random_access.subcarrier_spacing_khz", "Random_Access_PRACH", "phy.prach.subcarrierSpacing_kHz", consumer, prachCfg.PRACHSubcarrierSpacing, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.PRACHSubcarrierSpacing", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "random_access.root_sequence_index", "Random_Access_PRACH", "phy.prach.rootSeqIndex", consumer, prachCfg.SequenceIndex, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.SequenceIndex", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "random_access.zero_correlation_zone", "Random_Access_PRACH", "phy.prach.zeroCorrelationZone", consumer, prachCfg.ZeroCorrelationZone, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.ZeroCorrelationZone", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "random_access.preamble_index", "Random_Access_PRACH", "phy.prach.preambleIndex", consumer, prachCfg.PreambleIndex, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.PreambleIndex", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "random_access.restricted_set", "Random_Access_PRACH", "phy.prach.restrictedSet", consumer, prachCfg.RestrictedSet, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.RestrictedSet", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "random_access.frequency_start", "Random_Access_PRACH", "phy.prach.frequencyStart", consumer, prachCfg.FrequencyStart, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.FrequencyStart", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "random_access.num_prach_occasions", "Random_Access_PRACH", "prach_lls.NumPRACHOccasions", consumer, prachCfg.NumPRACHOccasions, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.NumPRACHOccasions", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "random_access.min_detection_trials", "Random_Access_PRACH", "prach_lls.NumTrials", consumer, prachCfg.NumTrials, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.NumTrials", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "random_access.detection_threshold_mode", "Random_Access_PRACH", "prach_lls.DetectionThresholdMode", consumer, prachCfg.DetectionThresholdMode, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.DetectionThresholdMode", "ApplicationScope", scope);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "random_access.detection_threshold", "Random_Access_PRACH", "phy.prach.detectionThreshold", consumer, prachCfg.DetectionThreshold, ...
    "RuntimeObjectType", objectType, "RuntimeObjectPath", "prachCfg.DetectionThreshold", "ApplicationScope", scope);
end

function repoRoot = localRepoRoot()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
