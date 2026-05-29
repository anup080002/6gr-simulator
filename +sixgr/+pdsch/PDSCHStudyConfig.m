function cfg = PDSCHStudyConfig(inputCfg, varargin)
%PDSCHStudyConfig Resolve and validate the 6GR PDSCH truth-study config.
%
% The active truth path intentionally reuses the repository's waveform-
% accurate PDSCH Tx/Rx blocks. Study knobs that are not yet materialized in
% that path remain explicit in this config and are labeled honestly.

opts = struct("RunFolder", "", "ScenarioID", "pdsch6gr_truth_study");
for i = 1:2:numel(varargin)
    if i + 1 <= numel(varargin)
        opts.(char(string(varargin{i}))) = varargin{i + 1};
    end
end

if ~isstruct(inputCfg)
    error("sixgr:pdsch:PDSCHStudyConfig:BadInput", ...
        "PDSCHStudyConfig expects a resolved internal cfg struct.");
end

pdsch6gr = sixgr.util.structGet(inputCfg, "pdsch6gr", struct());
phy = sixgr.util.structGet(inputCfg, "phy", struct());
channel = sixgr.util.structGet(inputCfg, "channel", struct());
run = sixgr.util.structGet(inputCfg, "run", struct());

cfg = struct();
cfg.CellID = double(sixgr.util.structGet(phy, "carrier.NCellID", 1));
cfg.RNTI = double(sixgr.util.structGet(pdsch6gr, "RNTI", sixgr.util.structGet(phy, "pdsch.RNTI", 1)));
cfg.FrameNumber = double(sixgr.util.structGet(pdsch6gr, "FrameNumber", 0));
cfg.SlotNumber = double(sixgr.util.structGet(pdsch6gr, "SlotNumber", 0));
cfg.Numerology = double(sixgr.util.structGet(pdsch6gr, "Numerology", sixgr.util.structGet(phy, "numerology.mu", 1)));
cfg.CarrierFrequencyHz = double(sixgr.util.structGet(pdsch6gr, "CarrierFrequencyHz", sixgr.util.structGet(inputCfg, "phy.fc_Hz", 2e9)));
cfg.DuplexMode = char(upper(string(sixgr.util.structGet(pdsch6gr, "DuplexMode", sixgr.util.structGet(phy, "duplex.mode", "FDD")))));
cfg.NSizeGrid = double(sixgr.util.structGet(pdsch6gr, "NSizeGrid", sixgr.util.structGet(phy, "carrier.NSizeGrid", 52)));
cfg.ChannelBandwidthMHz = double(sixgr.util.structGet(pdsch6gr, "ChannelBandwidthMHz", 20));
cfg.NTx = max(1, round(double(sixgr.util.structGet(pdsch6gr, "NTx", sixgr.util.structGet(channel, "nTxAnt", 1)))));
cfg.NRx = max(1, round(double(sixgr.util.structGet(pdsch6gr, "NRx", sixgr.util.structGet(channel, "nRxAnt", 1)))));
cfg.NumLayers = max(1, round(double(sixgr.util.structGet(pdsch6gr, "NumLayers", sixgr.util.structGet(phy, "pdsch.nLayers", 1)))));
cfg.NumCodewords = max(1, round(double(sixgr.util.structGet(pdsch6gr, "NumCodewords", 1))));
cfg.ModulationPerCodeword = localStringList(sixgr.util.structGet(pdsch6gr, "ModulationPerCodeword", {"16QAM"}));
cfg.TargetCodeRatePerCodeword = double(localNumericRow(sixgr.util.structGet(pdsch6gr, "TargetCodeRatePerCodeword", 0.4785)));
cfg.MCSMode = char(lower(string(sixgr.util.structGet(pdsch6gr, "MCSMode", "fixed"))));
cfg.FixedMCS = max(0, round(double(sixgr.util.structGet(pdsch6gr, "FixedMCS", 10))));
cfg.LinkAdaptationMode = char(lower(string(sixgr.util.structGet(pdsch6gr, "LinkAdaptationMode", "actual_bler_based"))));
cfg.HARQEnabled = logical(sixgr.util.structGet(pdsch6gr, "HARQEnabled", true));
cfg.HARQProcessCount = max(1, round(double(sixgr.util.structGet(pdsch6gr, "HARQProcessCount", 4))));
cfg.MaxHARQTx = max(1, round(double(sixgr.util.structGet(pdsch6gr, "MaxHARQTx", 1))));
cfg.EnableCrossSlotPDSCH = logical(sixgr.util.structGet(pdsch6gr, "EnableCrossSlotPDSCH", false));
cfg.CrossSlotMode = char(lower(string(sixgr.util.structGet(pdsch6gr, "CrossSlotMode", "disabled"))));
cfg.EnablePDSCHRepetition = logical(sixgr.util.structGet(pdsch6gr, "EnablePDSCHRepetition", false));
cfg.RepetitionMode = char(lower(string(sixgr.util.structGet(pdsch6gr, "RepetitionMode", "none"))));
cfg.RepetitionCount = max(1, round(double(sixgr.util.structGet(pdsch6gr, "RepetitionCount", 1))));
cfg.EnablePTRS = logical(sixgr.util.structGet(pdsch6gr, "EnablePTRS", false));
cfg.PTRSBandPolicy = char(lower(string(sixgr.util.structGet(pdsch6gr, "PTRSBandPolicy", "disabled"))));
cfg.ChannelEstimationMode = char(lower(string(sixgr.util.structGet(pdsch6gr, "ChannelEstimationMode", "realistic"))));
cfg.ParameterEstimationMode = char(lower(string(sixgr.util.structGet(pdsch6gr, "ParameterEstimationMode", "practical"))));
cfg.ReceiverType = char(upper(string(sixgr.util.structGet(pdsch6gr, "ReceiverType", "MMSE_IRC"))));
cfg.EnableMUMIMOStudy = logical(sixgr.util.structGet(pdsch6gr, "EnableMUMIMOStudy", false));
cfg.EnableMRSS = logical(sixgr.util.structGet(pdsch6gr, "EnableMRSS", false));
cfg.EnablePhaseNoise = logical(sixgr.util.structGet(pdsch6gr, "EnablePhaseNoise", false));
cfg.EnableWidebandUncalibratedPhaseErrors = logical(sixgr.util.structGet(pdsch6gr, "EnableWidebandUncalibratedPhaseErrors", false));
cfg.QueueBits = max(1, round(double(sixgr.util.structGet(pdsch6gr, "QueueBits", 1e6))));
cfg.Seed = double(sixgr.util.structGet(pdsch6gr, "Seed", sixgr.util.structGet(run, "seed", 1)));
cfg.OutputDir = char(string(sixgr.util.structGet(pdsch6gr, "OutputDir", opts.RunFolder)));
cfg.ScenarioID = char(string(opts.ScenarioID));
cfg.ChannelModel = char(string(sixgr.util.structGet(pdsch6gr, "ChannelModel", sixgr.util.structGet(channel, "model", "AWGN"))));
cfg.DelaySpread_s = double(sixgr.util.structGet(pdsch6gr, "DelaySpread_s", sixgr.util.structGet(channel, "fading.delaySpread_s", 30e-9)));
cfg.DelaySpreadCandidates_ns = double(localNumericRow(sixgr.util.structGet(pdsch6gr, "DelaySpreadCandidates_ns", [30 100 300])));
cfg.SpeedKmh = double(sixgr.util.structGet(pdsch6gr, "SpeedKmh", 3));
cfg.SpeedCandidates_kmh = double(localNumericRow(sixgr.util.structGet(pdsch6gr, "SpeedCandidates_kmh", [3 30 120])));
cfg.SNRdB = double(sixgr.util.structGet(pdsch6gr, "SNRdB", sixgr.util.structGet(channel, "snr_dB", 15)));
cfg.SNRSweep_dB = double(localNumericRow(sixgr.util.structGet(pdsch6gr, "SNRSweep_dB", cfg.SNRdB)));
cfg.DopplerHz = double(sixgr.util.structGet(pdsch6gr, "DopplerHz", sixgr.util.structGet(channel, "doppler_Hz", 0)));
cfg.FDRA = localResolveFDRAConfig(pdsch6gr, cfg);
cfg.TDRA = localResolveTDRAConfig(pdsch6gr, cfg);
cfg.DMRS = localResolveDMRSConfig(pdsch6gr);
cfg.PTRS = localResolvePTRSConfig(pdsch6gr, cfg);
cfg.CodewordLayer = localResolveCodewordLayerConfig(pdsch6gr, cfg);
cfg.MRSS = localResolveMRSSConfig(pdsch6gr);
cfg.StudySweep = localResolveStudySweep(pdsch6gr, cfg);

cfg.BaselineNotes = "Truth path uses repository waveform-accurate PDSCH Tx/Rx; unsupported study knobs remain explicit.";
cfg.CrossSlotMaterializationStatus = localCrossSlotStatus(cfg);
cfg.MultiCodewordMaterializationStatus = localMultiCodewordStatus(cfg);
cfg.MUMIMOMaterializationStatus = localMUMIMOStatus(cfg);

localValidate(cfg);
end

function fdra = localResolveFDRAConfig(pdsch6gr, cfg)
fdra = struct();
fdra.FDRAType = char(lower(string(sixgr.util.structGet(pdsch6gr, "FDRAType", "type1_riv"))));
fdra.RBBitmap = double(localNumericRow(sixgr.util.structGet(pdsch6gr, "RBBitmap", [])));
fdra.RIV = double(sixgr.util.structGet(pdsch6gr, "RIV", 0));
fdra.NumRB = max(1, round(double(sixgr.util.structGet(pdsch6gr, "NumRB", cfg.NSizeGrid))));
fdra.RBStart = max(0, round(double(sixgr.util.structGet(pdsch6gr, "RBStart", 0))));
fdra.GranularityRB = max(1, round(double(sixgr.util.structGet(pdsch6gr, "GranularityRB", 1))));
fdra.PhysicalCarrierID = max(0, round(double(sixgr.util.structGet(pdsch6gr, "PhysicalCarrierID", 0))));
fdra.SingleCarrierOnly = logical(sixgr.util.structGet(pdsch6gr, "SingleCarrierOnly", true));
fdra.EnableWidebandGranularityStudy = logical(sixgr.util.structGet(pdsch6gr, "EnableWidebandGranularityStudy", false));
end

function tdra = localResolveTDRAConfig(pdsch6gr, cfg)
tdra = struct();
tdra.MappingType = char(lower(string(sixgr.util.structGet(pdsch6gr, "MappingType", "single_mapping_type_baseline"))));
tdra.StartSymbol = max(0, round(double(sixgr.util.structGet(pdsch6gr, "StartSymbol", 2))));
tdra.NumSymbols = max(1, round(double(sixgr.util.structGet(pdsch6gr, "NumSymbols", 10))));
tdra.SymbolGranularity = max(1, round(double(sixgr.util.structGet(pdsch6gr, "SymbolGranularity", 1))));
tdra.EnableFlexibleStartSymbol = logical(sixgr.util.structGet(pdsch6gr, "EnableFlexibleStartSymbol", true));
tdra.EnableCrossSlot = logical(sixgr.util.structGet(pdsch6gr, "EnableCrossSlot", cfg.EnableCrossSlotPDSCH));
tdra.CrossSlotMaxSymbols = max(tdra.NumSymbols, round(double(sixgr.util.structGet(pdsch6gr, "CrossSlotMaxSymbols", tdra.NumSymbols))));
tdra.CrossSlotContiguityMode = char(lower(string(sixgr.util.structGet(pdsch6gr, "CrossSlotContiguityMode", "disabled"))));
tdra.SchedulingOffsetSymbols = max(0, round(double(sixgr.util.structGet(pdsch6gr, "SchedulingOffsetSymbols", 0))));
tdra.SchedulingOffsetSlots = max(0, round(double(sixgr.util.structGet(pdsch6gr, "SchedulingOffsetSlots", 0))));
tdra.EnableRepetitionStudy = logical(sixgr.util.structGet(pdsch6gr, "EnableRepetitionStudy", cfg.EnablePDSCHRepetition));
end

function dmrs = localResolveDMRSConfig(pdsch6gr)
dmrs = struct();
dmrs.DMRSEnabled = logical(sixgr.util.structGet(pdsch6gr, "DMRSEnabled", true));
dmrs.ConfigType = max(1, round(double(sixgr.util.structGet(pdsch6gr, "DMRSConfigType", 1))));
dmrs.TypeAorB = char(upper(string(sixgr.util.structGet(pdsch6gr, "DMRSTypeAorB", "A"))));
dmrs.AdditionalPosition = max(0, round(double(sixgr.util.structGet(pdsch6gr, "DMRSAdditionalPosition", 1))));
dmrs.SymbolSet = double(localNumericRow(sixgr.util.structGet(pdsch6gr, "DMRSSymbolSet", [])));
dmrs.CDMGroupCount = max(1, round(double(sixgr.util.structGet(pdsch6gr, "DMRSCDMGroupCount", 1))));
dmrs.CDMGroupsWithoutData = max(1, round(double(sixgr.util.structGet(pdsch6gr, "DMRSCDMGroupsWithoutData", 1))));
dmrs.FDOCCLength = max(1, round(double(sixgr.util.structGet(pdsch6gr, "DMRSFDOCCLength", 1))));
dmrs.TDOCCLength = max(1, round(double(sixgr.util.structGet(pdsch6gr, "DMRSTDOCCLength", 1))));
dmrs.OCCStructure = char(lower(string(sixgr.util.structGet(pdsch6gr, "DMRSOCCStructure", "comb"))));
dmrs.NumPorts = max(1, round(double(sixgr.util.structGet(pdsch6gr, "DMRSNumPorts", 1))));
dmrs.PortSet = double(localNumericRow(sixgr.util.structGet(pdsch6gr, "DMRSPortSet", 0:(dmrs.NumPorts-1))));
dmrs.Density = char(lower(string(sixgr.util.structGet(pdsch6gr, "DMRSDensity", "baseline_nr"))));
dmrs.Pattern = char(lower(string(sixgr.util.structGet(pdsch6gr, "DMRSPattern", "baseline_nr"))));
dmrs.SequenceInitMode = char(lower(string(sixgr.util.structGet(pdsch6gr, "DMRSSequenceInitMode", "ncellid"))));
dmrs.ScramblingID = double(sixgr.util.structGet(pdsch6gr, "DMRSScramblingID", NaN));
dmrs.CoScheduledUEAssumptionMode = char(lower(string(sixgr.util.structGet(pdsch6gr, "DMRSCoScheduledUEAssumptionMode", "not_materialized_in_active_truth_path"))));
dmrs.QCLTCIHintMode = char(lower(string(sixgr.util.structGet(pdsch6gr, "DMRSQCLTCIHintMode", "not_materialized_in_active_truth_path"))));
dmrs.PRGAllocationHintMode = char(lower(string(sixgr.util.structGet(pdsch6gr, "DMRSPRGAllocationHintMode", "not_materialized_in_active_truth_path"))));
dmrs.OCCDespreadingHintMode = char(lower(string(sixgr.util.structGet(pdsch6gr, "DMRSOCCDespreadingHintMode", "not_materialized_in_active_truth_path"))));
end

function ptrs = localResolvePTRSConfig(pdsch6gr, cfg)
ptrs = struct();
ptrs.PTRSEnabled = logical(sixgr.util.structGet(pdsch6gr, "PTRSEnabled", cfg.EnablePTRS));
ptrs.PTRSForFR2 = logical(sixgr.util.structGet(pdsch6gr, "PTRSForFR2", true));
ptrs.PTRSForFR1or7GHz = logical(sixgr.util.structGet(pdsch6gr, "PTRSForFR1or7GHz", false));
ptrs.TimeDensity = max(1, round(double(sixgr.util.structGet(pdsch6gr, "PTRSTimeDensity", 2))));
ptrs.FrequencyDensity = max(1, round(double(sixgr.util.structGet(pdsch6gr, "PTRSFrequencyDensity", 2))));
ptrs.REOffset = char(string(sixgr.util.structGet(pdsch6gr, "PTRSREOffset", "00")));
ptrs.PowerScalingMode = char(lower(string(sixgr.util.structGet(pdsch6gr, "PTRSPowerScalingMode", "baseline_nr"))));
end

function cw = localResolveCodewordLayerConfig(pdsch6gr, cfg)
cw = struct();
cw.Rank = max(1, round(double(sixgr.util.structGet(pdsch6gr, "Rank", cfg.NumLayers))));
cw.NumCodewords = max(1, round(double(sixgr.util.structGet(pdsch6gr, "CodewordNumCodewords", cfg.NumCodewords))));
cw.MaxRankPerCodeword = max(1, round(double(sixgr.util.structGet(pdsch6gr, "MaxRankPerCodeword", 4))));
cw.SpatialFreqTimeMappingOrder = char(lower(string(sixgr.util.structGet(pdsch6gr, "SpatialFreqTimeMappingOrder", "spatial_first_frequency_second_time_third"))));
cw.BaselineMode = char(lower(string(sixgr.util.structGet(pdsch6gr, "CodewordBaselineMode", "nr_baseline"))));
cw.TBToResourceMappingMode = char(lower(string(sixgr.util.structGet(pdsch6gr, "TBToResourceMappingMode", "baseline_nr"))));
end

function mrss = localResolveMRSSConfig(pdsch6gr)
mrss = struct();
mrss.Enabled = logical(sixgr.util.structGet(pdsch6gr, "EnableMRSS", false));
mrss.Mode = char(lower(string(sixgr.util.structGet(pdsch6gr, "MRSSMode", "exclusive_6gr"))));
mrss.ExternalOccupancyMask = double(localNumericRow(sixgr.util.structGet(pdsch6gr, "MRSSExternalOccupancyMask", [])));
mrss.Notes = char(string(sixgr.util.structGet(pdsch6gr, "MRSSNotes", "NW-side sharing only; UE remains transparent.")));
end

function sweep = localResolveStudySweep(pdsch6gr, cfg)
sweep = struct();
sweep.SNRdB = double(localNumericRow(sixgr.util.structGet(pdsch6gr, "StudySNRdB", cfg.SNRSweep_dB)));
sweep.FDRATypes = localStringList(sixgr.util.structGet(pdsch6gr, "StudyFDRATypes", {cfg.FDRA.FDRAType}));
sweep.MappingStarts = double(localNumericRow(sixgr.util.structGet(pdsch6gr, "StudyStartSymbols", cfg.TDRA.StartSymbol)));
sweep.NumSymbols = double(localNumericRow(sixgr.util.structGet(pdsch6gr, "StudyNumSymbols", cfg.TDRA.NumSymbols)));
sweep.RepetitionModes = localStringList(sixgr.util.structGet(pdsch6gr, "StudyRepetitionModes", {cfg.RepetitionMode}));
sweep.ChannelModels = localStringList(sixgr.util.structGet(pdsch6gr, "StudyChannelModels", {cfg.ChannelModel}));
sweep.DelaySpread_ns = double(localNumericRow(sixgr.util.structGet(pdsch6gr, "StudyDelaySpread_ns", cfg.DelaySpreadCandidates_ns)));
sweep.SpeedKmh = double(localNumericRow(sixgr.util.structGet(pdsch6gr, "StudySpeedKmh", cfg.SpeedCandidates_kmh)));
sweep.Ranks = double(localNumericRow(sixgr.util.structGet(pdsch6gr, "StudyRanks", cfg.CodewordLayer.Rank)));
sweep.PTRSModes = localStringList(sixgr.util.structGet(pdsch6gr, "StudyPTRSModes", {localPTRSMode(cfg)}));
sweep.DMRSAdditionalPositions = double(localNumericRow(sixgr.util.structGet(pdsch6gr, "StudyDMRSAdditionalPositions", cfg.DMRS.AdditionalPosition)));
sweep.NumTrials = max(1, round(double(sixgr.util.structGet(pdsch6gr, "StudyNumTrials", 1))));
end

function out = localNumericRow(value)
if isempty(value)
    out = [];
else
    out = double(value(:).');
end
end

function out = localStringList(value)
if ischar(value) || isstring(value)
    out = cellstr(string(value(:)));
elseif iscell(value)
    out = cellfun(@char, cellstr(string(value(:))), "UniformOutput", false);
else
    out = {};
end
end

function mode = localPTRSMode(cfg)
if logical(cfg.EnablePTRS)
    mode = "enabled";
else
    mode = "disabled";
end
end

function status = localCrossSlotStatus(cfg)
if ~logical(cfg.EnableCrossSlotPDSCH)
    status = "disabled";
else
    status = "study_hook_not_materialized_in_active_truth_path";
end
end

function status = localMultiCodewordStatus(cfg)
if cfg.NumCodewords <= 1
    status = "materialized_single_codeword_baseline";
else
    status = "study_hook_not_materialized_in_active_truth_path";
end
end

function status = localMUMIMOStatus(cfg)
if logical(cfg.EnableMUMIMOStudy)
    status = "study_hook_not_materialized_in_active_truth_path";
else
    status = "disabled";
end
end

function localValidate(cfg)
if cfg.NumCodewords > 1
    error("sixgr:pdsch:PDSCHStudyConfig:MultiCodewordUnsupported", ...
        "The active truth path supports one codeword only. NumCodewords=%d is a study hook, not a materialized truth path.", cfg.NumCodewords);
end
if cfg.NumLayers > 4
    error("sixgr:pdsch:PDSCHStudyConfig:TooManyLayers", ...
        "The active truth path supports up to 4 layers. Requested %d.", cfg.NumLayers);
end
if ~ismember(cfg.MCSMode, ["fixed","amc"])
    error("sixgr:pdsch:PDSCHStudyConfig:BadMCSMode", ...
        "MCSMode must be 'fixed' or 'amc'.");
end
if ~ismember(cfg.LinkAdaptationMode, ["actual_bler_based","calibration_only"])
    error("sixgr:pdsch:PDSCHStudyConfig:BadLAMode", ...
        "LinkAdaptationMode must be actual_bler_based or calibration_only.");
end
if ~ismember(cfg.ChannelEstimationMode, ["realistic","ideal_calibration"])
    error("sixgr:pdsch:PDSCHStudyConfig:BadChannelEstimationMode", ...
        "ChannelEstimationMode must be realistic or ideal_calibration.");
end
if ~ismember(cfg.ParameterEstimationMode, ["practical","off"])
    error("sixgr:pdsch:PDSCHStudyConfig:BadParameterEstimationMode", ...
        "ParameterEstimationMode must be practical or off.");
end
if ~ismember(cfg.RepetitionMode, ["none","intra_slot","inter_slot"])
    error("sixgr:pdsch:PDSCHStudyConfig:BadRepetitionMode", ...
        "RepetitionMode must be none, intra_slot, or inter_slot.");
end
if cfg.EnablePDSCHRepetition && cfg.RepetitionCount < 2
    error("sixgr:pdsch:PDSCHStudyConfig:BadRepetitionCount", ...
        "EnablePDSCHRepetition requires RepetitionCount >= 2.");
end
if cfg.EnableCrossSlotPDSCH
    error("sixgr:pdsch:PDSCHStudyConfig:CrossSlotNotMaterialized", ...
        "Cross-slot PDSCH remains a study hook and is not materialized in the active truth path.");
end
if cfg.EnableMUMIMOStudy
    error("sixgr:pdsch:PDSCHStudyConfig:MUMIMONotMaterialized", ...
        "MU-MIMO study assumptions are exposed for reporting only and are not materialized in the active truth path.");
end
end
