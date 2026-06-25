function strictCfg = buildSRSConfigFromScenario(baseCfg, varargin)
%BUILDSRSCONFIGFROMSCENARIO Resolve fail-closed NR SRS config.

p = inputParser;
p.FunctionName = "sixgr.phy.srs.buildSRSConfigFromScenario";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "RunFolder", "", @(x) ischar(x) || isstring(x));
addParameter(p, "RunId", "srs_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioName", "srs_strict_validation", @(x) ischar(x) || isstring(x));
parse(p, baseCfg, varargin{:});
opt = p.Results;

cfg = baseCfg;
mandatory = ["phy.carrier.NCellID","phy.carrier.NSizeGrid","phy.numerology.scs_kHz"];
missing = strings(0, 1);
for ii = 1:numel(mandatory)
    if isempty(sixgr.util.structGet(cfg, mandatory(ii), []))
        missing(end+1, 1) = mandatory(ii); %#ok<AGROW>
    end
end
if ~isempty(missing)
    error("sixgr:phy:srs:MissingStrictConfigField", ...
        "Strict SRS config is missing mandatory fields: %s", strjoin(missing, ", "));
end

nSizeGrid = max(1, round(double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 24))));
nStartGrid = max(0, round(double(sixgr.util.structGet(cfg, "phy.carrier.NStartGrid", 0))));
nCellID = max(0, round(double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", 0))));
scsKHz = double(sixgr.util.structGet(cfg, "phy.numerology.scs_kHz", 30));
nPorts = max(1, round(double(sixgr.util.structGet(cfg, "phy.srs.nPorts", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.num_ports", ...
    sixgr.util.structGet(cfg, "reference_signals.srs_ports", 1))))));
slotNumbers = sixgr.util.structGet(cfg, "phy.srs.slotNumbers", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.slot_numbers", [0 4]));
slotNumbers = unique(max(0, round(double(slotNumbers(:).'))), "stable");
if isempty(slotNumbers)
    slotNumbers = 0;
end

resourceType = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.srs.resourceType", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.resource_type", "periodic")))));
usage = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.srs.resourceSetUsage", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.resource_set_usage", "noncodebook")))));
coverageRequirement = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.srs.coverageRequirement", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.coverage_requirement", "configured_band")))));
fullRequired = logical(sixgr.util.structGet(cfg, "phy.srs.fullCarrierSoundingRequired", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.full_carrier_sounding_required", coverageRequirement == "full_carrier")));
expectedNumRBExplicit = localHasPath(cfg, "lls6g.reference_signals.srs.expected_num_rb");
expectedPctExplicit = localHasPath(cfg, "lls6g.reference_signals.srs.expected_bandwidth_coverage_percent");

strictCfg = struct();
strictCfg.RunId = string(opt.RunId);
strictCfg.ScenarioName = string(opt.ScenarioName);
strictCfg.RunFolder = string(opt.RunFolder);
strictCfg.CellId = 1;
strictCfg.UEId = 1;
strictCfg.BindingSource = string(sixgr.util.structGet(cfg, "phy.srs.bindingSource", "scenario_config"));
strictCfg.ReferenceSignalFamily = "SRS";
strictCfg.CarrierFrequencyHz = double(sixgr.util.structGet(cfg, "frequency.center_frequency_hz", ...
    sixgr.util.structGet(cfg, "channel.carrier_frequency_hz", NaN)));
strictCfg.FrequencyRange = string(sixgr.util.structGet(cfg, "frequency.range_name", "FR1"));
strictCfg.DuplexMode = string(sixgr.util.structGet(cfg, "phy.duplex.mode", ...
    sixgr.util.structGet(cfg, "frequency.duplex_mode", "FDD")));
strictCfg.NCellID = double(nCellID);
strictCfg.NSizeGrid = double(nSizeGrid);
strictCfg.NStartGrid = double(nStartGrid);
strictCfg.SubcarrierSpacingKHz = double(scsKHz);
strictCfg.CyclicPrefix = string(sixgr.util.structGet(cfg, "phy.numerology.cyclicPrefix", ...
    sixgr.util.structGet(cfg, "frame.cp_type", "normal")));
strictCfg.ULCarrierType = string(sixgr.util.structGet(cfg, "phy.srs.ulCarrierType", "NUL"));
strictCfg.BWPId = double(sixgr.util.structGet(cfg, "phy.srs.bwpId", 0));
strictCfg.BWPStart = double(sixgr.util.structGet(cfg, "phy.srs.bwpStart", 0));
strictCfg.BWPSize = double(sixgr.util.structGet(cfg, "phy.srs.bwpSize", nSizeGrid));
strictCfg.ResourceSetId = double(sixgr.util.structGet(cfg, "phy.srs.resourceSetId", 0));
strictCfg.ResourceSetUsage = string(usage);
strictCfg.ResourceType = string(resourceType);
strictCfg.Periodicity = double(sixgr.util.structGet(cfg, "phy.srs.period_slots", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.periodicity_slots", 4)));
strictCfg.Offset = double(sixgr.util.structGet(cfg, "phy.srs.period_offset", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.period_offset", 0)));
strictCfg.AperiodicTriggerState = string(sixgr.util.structGet(cfg, "phy.srs.aperiodicTriggerState", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.aperiodic_trigger_state", "")));
strictCfg.DCITriggerReferenceId = string(sixgr.util.structGet(cfg, "phy.srs.dciTriggerReferenceId", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.dci_trigger_reference_id", "")));
strictCfg.ActivationMACCEReferenceId = string(sixgr.util.structGet(cfg, "phy.srs.activationMACCEReferenceId", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.activation_mac_ce_reference_id", "")));
strictCfg.ResourceIds = double(sixgr.util.structGet(cfg, "phy.srs.resourceIds", 0));
strictCfg.NumResources = double(numel(strictCfg.ResourceIds));
strictCfg.ResourceId = double(strictCfg.ResourceIds(1));
strictCfg.NumSRSPorts = double(nPorts);
strictCfg.PortSet = 0:(nPorts-1);
strictCfg.SymbolStart = double(sixgr.util.structGet(cfg, "phy.srs.SymbolStart", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.symbol_start", 13)));
strictCfg.NumSRSSymbols = double(sixgr.util.structGet(cfg, "phy.srs.NumSRSSymbols", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.num_srs_symbols", 1)));
strictCfg.RepetitionFactor = double(sixgr.util.structGet(cfg, "phy.srs.Repetition", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.repetition_factor", 1)));
strictCfg.CombNumber = double(sixgr.util.structGet(cfg, "phy.srs.KTC", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.comb_number", 2)));
strictCfg.CombOffset = double(sixgr.util.structGet(cfg, "phy.srs.KBarTC", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.comb_offset", 0)));
strictCfg.CyclicShift = double(sixgr.util.structGet(cfg, "phy.srs.CyclicShift", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.cyclic_shift", 0)));
strictCfg.SequenceId = double(sixgr.util.structGet(cfg, "phy.srs.NSRSID", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.sequence_id", nCellID)));
strictCfg.GroupOrSequenceHopping = string(sixgr.util.structGet(cfg, "phy.srs.GroupSeqHopping", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.group_or_sequence_hopping", "neither")));
strictCfg.FrequencyPosition = double(sixgr.util.structGet(cfg, "phy.srs.FrequencyStart", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.frequency_position", 0)));
strictCfg.FrequencyShift = double(sixgr.util.structGet(cfg, "phy.srs.FrequencyShift", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.frequency_shift", 0)));
strictCfg.FrequencyHopping = string(sixgr.util.structGet(cfg, "phy.srs.FrequencyHopping", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.frequency_hopping", "neither")));
strictCfg.BHop = double(sixgr.util.structGet(cfg, "phy.srs.BHop", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.b_hop", 0)));
strictCfg.C_SRS = double(sixgr.util.structGet(cfg, "phy.srs.CSRS", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.c_srs", NaN)));
strictCfg.B_SRS = double(sixgr.util.structGet(cfg, "phy.srs.BSRS", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.b_srs", NaN)));
strictCfg.BWPRelativeRBStart = double(sixgr.util.structGet(cfg, "phy.srs.bwpRelativeRBStart", 0));
strictCfg.NumRB = double(sixgr.util.structGet(cfg, "phy.srs.bandwidthRB", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.num_rb", nSizeGrid)));
strictCfg.ExpectedRBStart = double(sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.expected_rb_start", strictCfg.BWPRelativeRBStart));
strictCfg.ExpectedNumRB = double(sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.expected_num_rb", strictCfg.NumRB));
strictCfg.ExpectedBandwidthCoveragePercent = double(sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.expected_bandwidth_coverage_percent", ...
    100 * min(strictCfg.ExpectedNumRB, nSizeGrid) / nSizeGrid));
strictCfg.ExpectedSlotSet = double(slotNumbers);
strictCfg.ExpectedSymbolSet = double(strictCfg.SymbolStart + (0:strictCfg.NumSRSSymbols-1));
strictCfg.ExpectedRECount = NaN;
strictCfg.FullCarrierSoundingRequired = logical(fullRequired);
strictCfg.CoverageRequirement = string(coverageRequirement);
strictCfg.SpatialRelationInfo = string(sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.spatial_relation_info", ""));
strictCfg.PathlossReferenceRS = string(sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.pathloss_reference_rs", ""));
strictCfg.PowerControlAlpha = double(sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.power_control_alpha", NaN));
strictCfg.P0 = double(sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.p0", NaN));
strictCfg.DetectionThreshold = double(sixgr.util.structGet(cfg, "phy.srs.detectionThreshold", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.detection_threshold", 0.72)));
strictCfg.ChannelNMSEThresholddB = double(sixgr.util.structGet(cfg, "phy.srs.channelNMSEThresholddB", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.channel_nmse_threshold_db", -8)));
strictCfg.ChannelEstimatorAlgorithm = string(sixgr.util.structGet(cfg, "phy.srs.channelEstimatorAlgorithm", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.channel_estimator_algorithm", ...
    sixgr.util.structGet(cfg, "channel_estimation.algorithm", "mmse_wiener"))));
strictCfg.ChannelEstimatorInterpolation = string(sixgr.util.structGet(cfg, "phy.srs.channelEstimatorInterpolation", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.interpolation_method", ...
    sixgr.util.structGet(cfg, "channel_estimation.interpolation_method", "mmse_2d"))));
strictCfg.MMSEFrequencySmoothingBins = double(sixgr.util.structGet(cfg, "phy.srs.mmseFrequencySmoothingBins", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.mmse_frequency_smoothing_bins", ...
    sixgr.util.structGet(cfg, "channel_estimation.filter_length_freq", 9))));
strictCfg.MMSETimeSmoothingSymbols = double(sixgr.util.structGet(cfg, "phy.srs.mmseTimeSmoothingSymbols", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.mmse_time_smoothing_symbols", ...
    sixgr.util.structGet(cfg, "channel_estimation.filter_length_time", 1))));
strictCfg.DFTDelayTapKeepCount = double(sixgr.util.structGet(cfg, "phy.srs.dftDelayTapKeepCount", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.dft_delay_tap_keep_count", ...
    sixgr.util.structGet(cfg, "channels.channel_filter_length_samples", 32))));
strictCfg.TimingToleranceSamples = double(sixgr.util.structGet(cfg, "phy.srs.timingToleranceSamples", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.timing_tolerance_samples", 3)));
strictCfg.HighSNRdB = double(sixgr.util.structGet(cfg, "channel.snr_dB", 35));
strictCfg.LowSNRSweepdB = double(sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.low_snr_sweep_db", [-20 -12 0 20 35]));
strictCfg.TimingOffsetSweepSamples = double(sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.timing_offset_sweep_samples", [0 2 4]));
strictCfg.Seed = double(sixgr.util.structGet(cfg, "run.seed", 240619));
strictCfg.ChannelModel = string(sixgr.util.structGet(cfg, "channel.model", "AWGN"));
strictCfg.StrictUnsupportedReason = "";
strictCfg.BaseConfig = cfg;

resourceSet = sixgr.phy.srs.buildSRSResourceSetStrict(strictCfg);
strictCfg.ToolboxCarrier = resourceSet.Carrier;
strictCfg.ToolboxSRS = resourceSet.SRS;
strictCfg.C_SRS = double(resourceSet.SRS.CSRS);
strictCfg.B_SRS = double(resourceSet.SRS.BSRS);
strictCfg.NumRB = double(resourceSet.SRS.NRBPerTransmission);
if ~expectedNumRBExplicit
    strictCfg.ExpectedNumRB = double(strictCfg.NumRB);
end
if ~expectedPctExplicit
    strictCfg.ExpectedBandwidthCoveragePercent = 100 * min(double(strictCfg.ExpectedNumRB), nSizeGrid) / nSizeGrid;
end
strictCfg.ConfigHash = sixgr.phy.srs.hashSRSConfig(strictCfg);
strictCfg.StrictValidation = sixgr.phy.srs.validateSRSConfigStrict(strictCfg);
strictCfg.ConfigExport = rmfield(strictCfg, intersect(fieldnames(strictCfg), ...
    {'ToolboxCarrier','ToolboxSRS','BaseConfig','ConfigExport','StrictValidation'}));
end

function tf = localHasPath(s, path)
tf = false;
if ~(isstruct(s) && isscalar(s))
    return;
end
parts = split(string(path), ".");
cur = s;
for ii = 1:numel(parts)
    key = char(parts(ii));
    if ~(isstruct(cur) && isscalar(cur) && isfield(cur, key))
        return;
    end
    cur = cur.(key);
end
tf = true;
end
