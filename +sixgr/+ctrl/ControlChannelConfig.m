function cfg = ControlChannelConfig(inputCfg, varargin)
%ControlChannelConfig Resolve and validate the 6GR PDCCH study configuration.
%
% This resolver keeps the study knobs explicit. Baseline assumptions are
% tagged honestly in the returned struct so later reporting can distinguish
% agreed baselines from study-time placeholders.

opts = struct("RunFolder", "", "ScenarioID", "ctrl6gr_pdcch_study");
for i = 1:2:numel(varargin)
    if i + 1 <= numel(varargin)
        opts.(char(string(varargin{i}))) = varargin{i + 1};
    end
end

if isstruct(inputCfg)
    fullCfg = inputCfg;
else
    error("sixgr:ctrl:ControlChannelConfig:BadInput", ...
        "ControlChannelConfig expects a resolved internal cfg struct.");
end

ctrl = sixgr.util.structGet(fullCfg, "ctrl6gr", struct());
phy = sixgr.util.structGet(fullCfg, "phy", struct());
channel = sixgr.util.structGet(fullCfg, "channel", struct());

cfg = struct();
cfg.Enable6GRPDCCH = logical(sixgr.util.structGet(ctrl, "enable", true));
cfg.CellID = double(sixgr.util.structGet(phy, "carrier.NCellID", 1));
cfg.RNTI = double(sixgr.util.structGet(ctrl, "RNTI", sixgr.util.structGet(phy, "pdcch.rnti", 4660)));
cfg.SlotNumber = double(sixgr.util.structGet(ctrl, "SlotNumber", 0));
cfg.FrameNumber = double(sixgr.util.structGet(ctrl, "FrameNumber", 0));
configuredMu = double(sixgr.util.structGet(phy, "numerology.mu", NaN));
configuredSCS = double(sixgr.util.structGet(phy, "carrier.SubcarrierSpacing", ...
    sixgr.util.structGet(phy, "carrier.SubcarrierSpacing_kHz", NaN)));
configuredCP = string(sixgr.util.structGet(phy, "carrier.CyclicPrefix", "normal"));
numerology = localResolveNumerology(configuredSCS, configuredMu, configuredCP);
cfg.Numerology = double(numerology.Mu);
cfg.SlotsPerFrame = double(numerology.SlotsPerFrame);
configuredSlotsPerFrame = double(sixgr.util.structGet(ctrl, "SlotsPerFrame", NaN));
if isfinite(configuredSlotsPerFrame) && ...
        configuredSlotsPerFrame ~= cfg.SlotsPerFrame
    error("sixgr:ctrl:ControlChannelConfig:NumerologyMismatch", ...
        "ctrl6gr.SlotsPerFrame=%g conflicts with the canonical value %g for SCS=%g kHz.", ...
        configuredSlotsPerFrame, cfg.SlotsPerFrame, ...
        double(numerology.SubcarrierSpacingKHz));
end
cfg.SubcarrierSpacing_kHz = double(numerology.SubcarrierSpacingKHz);
cfg.CyclicPrefix = char(string(numerology.CyclicPrefix));
cfg.CarrierFrequencyHz = double(sixgr.util.structGet(fullCfg, "phy.fc_Hz", sixgr.util.structGet(channel, "fc_Hz", 4e9)));
cfg.NSizeGrid = double(sixgr.util.structGet(phy, "carrier.NSizeGrid", 51));
cfg.NSlotGrid = max(1, round(double(sixgr.util.structGet(ctrl, "NumSlots", sixgr.util.structGet(fullCfg, "run.totalSlots", 1)))));
cfg.NTx = max(1, round(double(sixgr.util.structGet(ctrl, "NTx", 1))));
cfg.NRx = max(1, round(double(sixgr.util.structGet(ctrl, "NRx", sixgr.util.structGet(channel, "nRxAnt", 1)))));
cfg.ChannelModel = char(string(sixgr.util.structGet(ctrl, "ChannelModel", sixgr.util.structGet(channel, "model", "AWGN"))));
cfg.DelaySpread = double(sixgr.util.structGet(ctrl, "DelaySpread", sixgr.util.structGet(channel, "fading.delaySpread_s", 100e-9)));
cfg.DopplerHz = double(sixgr.util.structGet(ctrl, "DopplerHz", sixgr.util.structGet(channel, "doppler_Hz", 0)));
cfg.SNRdB = double(sixgr.util.structGet(ctrl, "SNRdB", sixgr.util.structGet(channel, "snr_dB", 20)));
cfg.NoiseVarianceMode = char(string(sixgr.util.structGet(ctrl, "NoiseVarianceMode", "from_snr_db")));
cfg.ChannelEstimationMode = char(string(sixgr.util.structGet(ctrl, "ChannelEstimationMode", "realistic")));
cfg.EqualizerType = char(string(sixgr.util.structGet(ctrl, "EqualizerType", "MMSE")));
cfg.BlindDetectionEnabled = logical(sixgr.util.structGet(ctrl, "BlindDetectionEnabled", true));
cfg.MonitoringPeriodicitySlots = max(1, round(double(sixgr.util.structGet(ctrl, "MonitoringPeriodicitySlots", 1))));
cfg.EnableCSS = logical(sixgr.util.structGet(ctrl, "EnableCSS", true));
cfg.EnableUSS = logical(sixgr.util.structGet(ctrl, "EnableUSS", true));
cfg.EnableMRSS = logical(sixgr.util.structGet(ctrl, "EnableMRSS", false));
cfg.EnableRepetition = logical(sixgr.util.structGet(ctrl, "EnableRepetition", false));
cfg.RepetitionMode = char(string(sixgr.util.structGet(ctrl, "RepetitionMode", "none")));
cfg.RepetitionCount = max(1, round(double(sixgr.util.structGet(ctrl, "RepetitionCount", 1))));
cfg.EnableTransmitDiversity = logical(sixgr.util.structGet(ctrl, "EnableTransmitDiversity", false));
cfg.DiversityMode = char(string(sixgr.util.structGet(ctrl, "DiversityMode", "single_port_baseline")));
cfg.AllowStubModes = logical(sixgr.util.structGet(ctrl, "AllowStubModes", false));
cfg.AllowUndefined6GNumerologyCandidateLimit = logical(sixgr.util.structGet(ctrl, ...
    "AllowUndefined6GNumerologyCandidateLimit", false));
cfg.PrecoderGranularity = char(string(sixgr.util.structGet(ctrl, "PrecoderGranularity", "none")));
cfg.OutputDir = char(string(sixgr.util.structGet(ctrl, "OutputDir", opts.RunFolder)));
cfg.Seed = double(sixgr.util.structGet(ctrl, "Seed", sixgr.util.structGet(fullCfg, "run.seed", 1)));
cfg.PayloadLengthBits = max(1, round(double(sixgr.util.structGet(ctrl, "PayloadLengthBits", sixgr.util.structGet(phy, "pdcch.dciPayloadBits", 64)))));
cfg.Modulation = char(string(sixgr.util.structGet(ctrl, "Modulation", "QPSK")));
cfg.CRCPolynomial = char(string(sixgr.util.structGet(ctrl, "CRCPolynomial", "24C")));
cfg.CRCScramblingEnabled = logical(sixgr.util.structGet(ctrl, "CRCScramblingEnabled", true));
cfg.PayloadScramblingEnabled = logical(sixgr.util.structGet(ctrl, "PayloadScramblingEnabled", true));
cfg.PayloadSequenceInit = double(sixgr.util.structGet(ctrl, "PayloadSequenceInit", cfg.CellID));
cfg.PDCCHScramblingID = double(sixgr.util.structGet(ctrl, "PDCCHScramblingID", ...
    sixgr.util.structGet(ctrl, "CORESETScramblingID", ...
    sixgr.util.structGet(ctrl, "DataScramblingIdentityPDCCH", cfg.PayloadSequenceInit))));
cfg.DMRSScramblingID = double(sixgr.util.structGet(ctrl, "DMRSScramblingID", cfg.CellID));
cfg.WaveformMode = char(string(sixgr.util.structGet(ctrl, "WaveformMode", "full_ofdm")));
cfg.RepetitionCombiningMode = char(string(sixgr.util.structGet(ctrl, "RepetitionCombiningMode", "coherent")));
cfg.StudyClassification = "study_item_candidate";
cfg.ApproximationNotes = "6GR PDCCH baseline study framework with honest FFS hooks.";
cfg.ScenarioID = char(string(opts.ScenarioID));
if strcmpi(cfg.DiversityMode, "nontransparent_stub")
    cfg.PDCCHImplementationStatus = "stub_mode_requested_not_decodable";
    cfg.PDCCHImplementationBlocker = "nontransparent_stub_is_a_future_study_hook_without_receiver_support";
else
    cfg.PDCCHImplementationStatus = "waveform_baseline_decodable";
    cfg.PDCCHImplementationBlocker = "";
end

cfg.CORESET = sixgr.ctrl.CORESETConfig(sixgr.util.structGet(ctrl, "CORESET", struct()), cfg);

rawSearchSpaces = sixgr.util.structGet(ctrl, "SearchSpaces", struct([]));
if isempty(rawSearchSpaces)
    rawSearchSpaces = localDefaultSearchSpaces(cfg);
end
searchSpacesResolved = cell(0,1);
for i = 1:numel(rawSearchSpaces)
    ss = sixgr.ctrl.SearchSpaceConfig(rawSearchSpaces(i), cfg, cfg.CORESET);
    if (ss.SearchSpaceType == "CSS" && cfg.EnableCSS) || (ss.SearchSpaceType == "USS" && cfg.EnableUSS)
        searchSpacesResolved{end+1,1} = ss; %#ok<AGROW>
    end
end
if isempty(searchSpacesResolved)
    error("sixgr:ctrl:ControlChannelConfig:NoSearchSpace", ...
        "At least one enabled CSS or USS search space is required.");
end
cfg.SearchSpaces = vertcat(searchSpacesResolved{:});

cfg.StudySweep = localResolveStudySweep(ctrl, cfg);
cfg.AggregationLevels = unique(double([cfg.SearchSpaces.AggregationLevels]), "stable");
cfg.AggregationLevelSelectionMode = char(string(sixgr.util.structGet(ctrl, ...
    "AggregationLevelSelectionMode", "measured_sinr_gated")));
cfg.AggregationLevelSelectionSource = "search_space_configured_levels_plus_measured_control_sinr";
cfg.AggregationLevelSelectionAllowConfiguredSNR = logical(sixgr.util.structGet(ctrl, ...
    "AggregationLevelSelectionAllowConfiguredSNR", false));
cfg.effectiveAggregationLevels = @(sinr_dB) localEffectiveAggregationLevels(cfg.AggregationLevels, sinr_dB);
localValidate(cfg);
end

function levels = localEffectiveAggregationLevels(allLevels, sinr_dB)
allLevels = unique(round(double(allLevels(:).')), "stable");
allLevels = allLevels(isfinite(allLevels) & allLevels > 0);
if isempty(allLevels)
    allLevels = [1 2 4 8 16];
end
if ~(isnumeric(sinr_dB) && isscalar(sinr_dB) && isfinite(sinr_dB))
    levels = allLevels;
    return;
end
if sinr_dB > 10
    maxAL = 1;
elseif sinr_dB > 5
    maxAL = 2;
elseif sinr_dB > 0
    maxAL = 4;
elseif sinr_dB > -5
    maxAL = 8;
else
    maxAL = 16;
end
levels = allLevels(allLevels <= maxAL);
if isempty(levels)
    levels = min(allLevels);
end
end

function out = localDefaultSearchSpaces(cfg)
defaultCandidates = struct("AL1", 8, "AL2", 4, "AL4", 2, "AL8", 1, "AL16", 1);
base = struct( ...
    "SearchSpaceID", 1, ...
    "SearchSpaceType", "CSS", ...
    "AssociatedCORESETID", cfg.CORESET.CORESETID, ...
    "MonitoringSymbolsWithinSlot", cfg.CORESET.StartSymbol + (0:cfg.CORESET.DurationSymbols-1), ...
    "MonitoringSlotsPeriodicity", cfg.MonitoringPeriodicitySlots, ...
    "MonitoringSlotOffset", 0, ...
    "CandidateCountPerAL", defaultCandidates, ...
    "AggregationLevels", [1 2 4 8 16], ...
    "HashFunctionMode", "baseline_hash", ...
    "EnableSlotLevelMonitoring", true, ...
    "EnableNonSlotMonitoringStudy", false, ...
    "UETransparentToMRSS", true);
out = base;
if cfg.EnableUSS
    out(2) = base; %#ok<AGROW>
    out(2).SearchSpaceID = 2;
    out(2).SearchSpaceType = "USS";
end
end

function sweep = localResolveStudySweep(ctrl, cfg)
sweep = struct();
sweep.AggregationLevels = localVectorOrDefault(ctrl, "StudyAggregationLevels", [1 2 4 8 16]);
sweep.CORESETDurations = localVectorOrDefault(ctrl, "StudyCORESETDurations", cfg.CORESET.DurationSymbols);
sweep.MappingTypes = string(localCellOrDefault(ctrl, "StudyMappingTypes", {cfg.CORESET.MappingType}));
sweep.FrequencyAllocationModes = string(localCellOrDefault(ctrl, "StudyFrequencyAllocationModes", {cfg.CORESET.FrequencyAllocationMode}));
sweep.RepetitionModes = string(localCellOrDefault(ctrl, "StudyRepetitionModes", {cfg.RepetitionMode}));
sweep.SNRdB = localVectorOrDefault(ctrl, "StudySNRdB", cfg.SNRdB);
sweep.ChannelModels = string(localCellOrDefault(ctrl, "StudyChannelModels", {cfg.ChannelModel}));
sweep.SearchSpaceTypes = string(localCellOrDefault(ctrl, "StudySearchSpaceTypes", {"CSS","USS"}));
sweep.DMRSVariants = string(localCellOrDefault(ctrl, "StudyDMRSVariants", {cfg.CORESET.DMRSConfigType}));
sweep.CRCScrambling = logical(localVectorOrDefault(ctrl, "StudyCRCScrambling", double(cfg.CRCScramblingEnabled)));
sweep.PayloadScrambling = logical(localVectorOrDefault(ctrl, "StudyPayloadScrambling", double(cfg.PayloadScramblingEnabled)));
sweep.REGBundleSizes = localVectorOrDefault(ctrl, "StudyREGBundleSizes", cfg.CORESET.REGBundleSize);
sweep.NumREGPerCCE = localVectorOrDefault(ctrl, "StudyNumREGPerCCE", cfg.CORESET.NumREGPerCCE);
sweep.MRSSModes = string(localCellOrDefault(ctrl, "StudyMRSSModes", {"exclusive_6gr"}));
end

function values = localVectorOrDefault(s, fieldName, defaultVal)
values = sixgr.util.structGet(s, fieldName, defaultVal);
if isscalar(values)
    values = double(values);
else
    values = double(values(:).');
end
end

function values = localCellOrDefault(s, fieldName, defaultVal)
values = sixgr.util.structGet(s, fieldName, defaultVal);
if isstring(values)
    values = cellstr(values(:));
elseif ischar(values)
    values = {char(values)};
elseif ~iscell(values)
    values = defaultVal;
end
end

function localValidate(cfg)
if ~strcmpi(cfg.Modulation, "QPSK")
    error("sixgr:ctrl:ControlChannelConfig:UnsupportedModulation", ...
        "Baseline implementation currently supports QPSK only. Requested '%s'.", cfg.Modulation);
end

if ~ismember(lower(string(cfg.ChannelEstimationMode)), ["realistic","ideal"])
    error("sixgr:ctrl:ControlChannelConfig:BadEstimationMode", ...
        "ChannelEstimationMode must be 'realistic' or 'ideal'.");
end
if ~ismember(upper(string(cfg.EqualizerType)), ["MMSE","ZF","MMSE-IRC"])
    error("sixgr:ctrl:ControlChannelConfig:BadEqualizer", ...
        "EqualizerType must be MMSE, ZF, or MMSE-IRC.");
end
if cfg.EnableRepetition && ~ismember(lower(string(cfg.RepetitionMode)), ["none","intra_slot","inter_slot"])
    error("sixgr:ctrl:ControlChannelConfig:BadRepetitionMode", ...
        "RepetitionMode must be none, intra_slot, or inter_slot.");
end
if cfg.EnableRepetition && cfg.RepetitionCount < 2
    error("sixgr:ctrl:ControlChannelConfig:BadRepetitionCount", ...
        "EnableRepetition requires RepetitionCount >= 2.");
end
if ~ismember(lower(string(cfg.DiversityMode)), ["single_port_baseline","transparent","nontransparent_stub"])
    error("sixgr:ctrl:ControlChannelConfig:BadDiversityMode", ...
        "DiversityMode must be single_port_baseline, transparent, or nontransparent_stub.");
end
if strcmpi(cfg.DiversityMode, "nontransparent_stub") && ~logical(cfg.AllowStubModes)
    error("sixgr:ctrl:ControlChannelConfig:StubModeDisabled", ...
        "nontransparent_stub is a future-study hook. Set ctrl6gr.AllowStubModes=true to acknowledge the non-decoding stub path explicitly.");
end
if ~ismember(lower(string(cfg.PrecoderGranularity)), ["none","reg_bundle"])
    error("sixgr:ctrl:ControlChannelConfig:BadPrecoderGranularity", ...
        "PrecoderGranularity must be none or reg_bundle.");
end
if ~ismember(lower(string(cfg.WaveformMode)), ["full_ofdm","grid_mode"])
    error("sixgr:ctrl:ControlChannelConfig:BadWaveformMode", ...
        "WaveformMode must be full_ofdm or grid_mode.");
end
end

function numerology = localResolveNumerology(scsKHz, mu, cyclicPrefix)
if isfinite(scsKHz)
    numerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
        scsKHz, cyclicPrefix, "generic_waveform_test", "");
    if isfinite(mu) && double(mu) ~= double(numerology.Mu)
        error("sixgr:ctrl:ControlChannelConfig:NumerologyMismatch", ...
            "Configured mu=%g conflicts with SCS=%g kHz (canonical mu=%g).", ...
            mu, scsKHz, double(numerology.Mu));
    end
    return;
end
if ~isfinite(mu)
    error("sixgr:ctrl:ControlChannelConfig:MissingNumerology", ...
        "Control-channel configuration requires an explicit carrier SCS or mu.");
end
spec = sixgr.phy.frame.AbsoluteTime.resolveNumerology(mu);
numerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
    spec.SCSKHz, cyclicPrefix, "generic_waveform_test", "");
end
