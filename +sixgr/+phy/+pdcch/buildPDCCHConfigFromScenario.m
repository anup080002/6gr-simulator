function strictCfg = buildPDCCHConfigFromScenario(baseCfg, varargin)
%BUILDPDCCHCONFIGFROMSCENARIO Resolve a fail-closed strict PDCCH config.

p = inputParser;
p.FunctionName = "sixgr.phy.pdcch.buildPDCCHConfigFromScenario";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "RunFolder", "", @(x) ischar(x) || isstring(x));
addParameter(p, "RunId", "pdcch_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioName", "pdcch_strict_validation", @(x) ischar(x) || isstring(x));
parse(p, baseCfg, varargin{:});
opt = p.Results;

cfg = baseCfg;
operatorControl = sixgr.util.structGet(cfg, "phy.pdcch.operatorControl", struct());
operatorStrict = sixgr.util.structGet(operatorControl, "pdcch_strict", struct());
hasContextualOperatorConfig = isstruct(operatorStrict) && ...
    isfield(operatorStrict, "dci_context") && ...
    isfield(operatorStrict, "coreset") && isfield(operatorStrict, "search_space");
missing = strings(0, 1);
mandatory = [
    "phy.carrier.NCellID"
    "phy.carrier.NSizeGrid"
    "phy.numerology.scs_kHz"
    "phy.pdcch.coreset.duration"
    "phy.pdcch.coreset.frequencyResources"
    "phy.pdcch.searchSpace.numCandidates"
    "phy.pdcch.aggregationLevel"];
for ii = 1:numel(mandatory)
    try
        v = sixgr.util.structGet(cfg, mandatory(ii), []);
    catch
        v = [];
    end
    if isempty(v)
        missing(end + 1, 1) = mandatory(ii); %#ok<AGROW>
    end
end
if ~isempty(missing)
    error("sixgr:phy:pdcch:MissingStrictConfigField", ...
        "Strict PDCCH config is missing mandatory fields: %s", strjoin(missing, ", "));
end

nCellID = double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", 1));
nSizeGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 52));
nStartGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NStartGrid", 0));
scsKHz = double(sixgr.util.structGet(cfg, "phy.numerology.scs_kHz", ...
    sixgr.util.structGet(cfg, "phy.numerology.SubcarrierSpacing_kHz", 30)));
fcHz = double(sixgr.util.structGet(cfg, "phy.fc_Hz", sixgr.util.structGet(cfg, "channel.fc_Hz", 4e9)));
freqRange = string(sixgr.util.structGet(cfg, "frequency.range_name", ...
    sixgr.util.structGet(cfg, "lls6g.frequency.range_name", "FR1")));
duplexMode = string(sixgr.util.structGet(cfg, "frequency.duplex_mode", ...
    sixgr.util.structGet(cfg, "lls6g.frequency.duplex_mode", "FDD")));

rntiType = sixgr.phy.pdcch.normalizeRNTIType(sixgr.util.structGet(cfg, ...
    "phy.pdcch.rntiType", sixgr.util.structGet(operatorStrict, "rnti.type", "C-RNTI")));
rntiValue = double(sixgr.util.structGet(cfg, "phy.pdcch.rnti", ...
    sixgr.util.structGet(operatorStrict, "rnti.value", 4660)));
dciFormats = string(sixgr.util.structGet(cfg, "phy.pdcch.dciFormats", ...
    sixgr.util.structGet(cfg, "phy.pdcch.dciFormat", "1_0")));
dciFormats = unique(upper(strrep(strtrim(dciFormats(:)), "-", "_")), "stable");
aggregationLevel = double(sixgr.util.structGet(cfg, "phy.pdcch.aggregationLevel", 4));
aggregationLevels = double(sixgr.util.structGet(cfg, "phy.pdcch.aggregationLevels", aggregationLevel));
numCand = double(sixgr.util.structGet(cfg, "phy.pdcch.searchSpace.numCandidates", [0 0 1 0 0]));
numCand = reshape(numCand, 1, []);
if numel(numCand) < 5
    numCand(numel(numCand)+1:5) = 0;
end
numCand = numCand(1:5);

strictCfg = struct();
strictCfg.RunId = string(opt.RunId);
strictCfg.ScenarioName = string(opt.ScenarioName);
strictCfg.CellId = 1;
strictCfg.UEId = 1;
strictCfg.CarrierFrequencyHz = fcHz;
strictCfg.FrequencyRange = freqRange;
strictCfg.DuplexMode = duplexMode;
strictCfg.NCellID = nCellID;
strictCfg.NSizeGrid = nSizeGrid;
strictCfg.NStartGrid = nStartGrid;
strictCfg.SubcarrierSpacingKHz = scsKHz;
strictCfg.FrameNumber = 0;
strictCfg.SlotNumber = 0;
strictCfg.CORESETId = double(sixgr.util.structGet(cfg, "phy.pdcch.coreset.id", 0));
strictCfg.CORESETFrequencyDomainResources = double(sixgr.util.structGet(cfg, ...
    "phy.pdcch.coreset.frequencyResources", ones(1, 6)));
strictCfg.CORESETDurationSymbols = double(sixgr.util.structGet(cfg, "phy.pdcch.coreset.duration", 2));
strictCfg.CORESETRBStart = double(sixgr.util.structGet(cfg, "phy.pdcch.coreset.rbStart", 0));
strictCfg.CORESETNumRB = double(6 * nnz(strictCfg.CORESETFrequencyDomainResources));
strictCfg.CCE_REG_MappingType = string(sixgr.util.structGet(cfg, ...
    "phy.pdcch.coreset.mappingType", "noninterleaved"));
strictCfg.REGBundleSize = double(sixgr.util.structGet(cfg, "phy.pdcch.coreset.regBundleSize", 2));
strictCfg.InterleaverSize = double(sixgr.util.structGet(cfg, "phy.pdcch.coreset.interleaverSize", 2));
strictCfg.ShiftIndex = double(sixgr.util.structGet(cfg, "phy.pdcch.coreset.shiftIndex", nCellID));
strictCfg.PrecoderGranularity = string(sixgr.util.structGet(cfg, ...
    "phy.pdcch.coreset.precoderGranularity", "sameAsREG-bundle"));
strictCfg.SearchSpaceId = double(sixgr.util.structGet(cfg, "phy.pdcch.searchSpace.id", 1));
strictCfg.SearchSpaceType = string(sixgr.util.structGet(cfg, "phy.pdcch.searchSpaceType", "ue"));
strictCfg.SearchSpacePeriodicity = double(sixgr.util.structGet(cfg, ...
    "phy.pdcch.searchSpace.slotPeriodAndOffset", [1 0]));
if numel(strictCfg.SearchSpacePeriodicity) >= 2
    strictCfg.SearchSpaceOffset = strictCfg.SearchSpacePeriodicity(2);
    strictCfg.SearchSpacePeriodicity = strictCfg.SearchSpacePeriodicity(1);
else
    strictCfg.SearchSpaceOffset = 0;
end
strictCfg.SearchSpaceDuration = double(sixgr.util.structGet(cfg, "phy.pdcch.searchSpace.duration", 1));
strictCfg.SearchSpaceFirstSymbolWithinSlot = double(sixgr.util.structGet(cfg, ...
    "phy.pdcch.searchSpace.startSymbol", 0));
strictCfg.NumCandidatesAL1 = numCand(1);
strictCfg.NumCandidatesAL2 = numCand(2);
strictCfg.NumCandidatesAL4 = numCand(3);
strictCfg.NumCandidatesAL8 = numCand(4);
strictCfg.NumCandidatesAL16 = numCand(5);
strictCfg.AggregationLevelsEnabled = aggregationLevels(:).';
strictCfg.DCIMonitoringFormats = dciFormats(:).';
strictCfg.RNTIType = rntiType;
strictCfg.RNTIValue = rntiValue;
strictCfg.DCIFormat = dciFormats(1);
if hasContextualOperatorConfig
    coresetRaw = operatorStrict.coreset;
    searchRaw = operatorStrict.search_space;
    strictCfg.CORESETId = double(localRequired(coresetRaw, "id"));
    strictCfg.CORESETDurationSymbols = double(localRequired(coresetRaw, "duration_symbols"));
    strictCfg.CORESETRBStart = double(localRequired(coresetRaw, "rb_start"));
    strictCfg.CORESETNumRB = double(localRequired(coresetRaw, "n_rb"));
    strictCfg.CORESETFrequencyDomainResources = localFrequencyBitmap( ...
        strictCfg.CORESETRBStart, strictCfg.CORESETNumRB);
    strictCfg.CCE_REG_MappingType = string(localRequired(coresetRaw, "mapping_type"));
    strictCfg.REGBundleSize = double(localRequired(coresetRaw, "reg_bundle_size"));
    strictCfg.InterleaverSize = double(localRequired(coresetRaw, "interleaver_size"));
    strictCfg.ShiftIndex = double(localRequired(coresetRaw, "shift_index"));
    strictCfg.PrecoderGranularity = string(localRequired(coresetRaw, "precoder_granularity"));
    strictCfg.SearchSpaceId = double(localRequired(searchRaw, "id"));
    strictCfg.SearchSpaceType = string(localRequired(searchRaw, "type"));
    strictCfg.SearchSpacePeriodicity = double(localRequired(searchRaw, "period_slots"));
    strictCfg.SearchSpaceOffset = double(localRequired(searchRaw, "offset_slots"));
    strictCfg.SearchSpaceDuration = double(localRequired(searchRaw, "duration_slots"));
    bitmap = char(string(localRequired(searchRaw, "monitoring_symbols_within_slot")));
    strictCfg.SearchSpaceFirstSymbolWithinSlot = find(bitmap == '1', 1, "first") - 1;
    numCand = double(localRequired(searchRaw, "num_candidates"));
    strictCfg.NumCandidatesAL1 = numCand(1);
    strictCfg.NumCandidatesAL2 = numCand(2);
    strictCfg.NumCandidatesAL4 = numCand(3);
    strictCfg.NumCandidatesAL8 = numCand(4);
    strictCfg.NumCandidatesAL16 = numCand(5);
end
configuredPayloadBits = double(sixgr.util.structGet(cfg, "phy.pdcch.configuredPayloadBits", ...
    sixgr.util.structGet(cfg, "phy.pdcch.dciPayloadBits", ...
    sixgr.util.structGet(cfg, "lls6g.control.pdcch_payload_bits", NaN))));
contexts = cell(numel(dciFormats), 1);
payloadRows = repmat(struct("DCIFormat", "", "PayloadBits", NaN, ...
    "ContextDigest", ""), numel(dciFormats), 1);
for formatIndex = 1:numel(dciFormats)
    if hasContextualOperatorConfig
        context = sixgr.phy.pdcch.DCIContextFactory.fromOperatorControl( ...
            operatorControl, dciFormats(formatIndex));
    else
        context = sixgr.phy.pdcch.DCIContext.fromLegacy( ...
            struct("NSizeGrid", nSizeGrid, "RNTIType", rntiType, ...
            "RNTIValue", rntiValue, "MonitoredFormats", dciFormats), ...
            dciFormats(formatIndex));
    end
    aligned = sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(context);
    contexts{formatIndex} = context;
    payloadRows(formatIndex).DCIFormat = dciFormats(formatIndex);
    payloadRows(formatIndex).PayloadBits = aligned.Selected.AlignedBits;
    payloadRows(formatIndex).ContextDigest = context.Digest;
end
payloadBits = payloadRows(1).PayloadBits;
[~, payloadDetails] = sixgr.phy.pdcch.dciPayloadSizeBits(nSizeGrid, dciFormats);
strictCfg.ConfiguredDCIPayloadSizeBits = configuredPayloadBits;
strictCfg.DCIPayloadSizeBits = payloadBits;
strictCfg.DCIContexts = contexts;
strictCfg.DCIPayloadSizeRows = payloadRows;
strictCfg.DCIContext = contexts{1};
strictCfg.DCIContextDigest = contexts{1}.Digest;
strictCfg.DCIPayloadFrequencyAssignmentBits = double(payloadDetails.FrequencyResourceAssignmentBits);
strictCfg.DCI10PayloadSizeBits = double(payloadDetails.DCI10PayloadBits);
strictCfg.DCI00UnpaddedPayloadSizeBits = double(payloadDetails.DCI00UnpaddedPayloadBits);
strictCfg.DCI00PaddedPayloadSizeBits = double(payloadDetails.DCI00PaddedPayloadBits);
strictCfg.DCIPayloadSizeSource = string(payloadDetails.SizeSource);
strictCfg.DCIPayloadConfiguredMismatch = isfinite(configuredPayloadBits) && configuredPayloadBits ~= payloadBits;
strictCfg.CandidateCCEIndex = double(sixgr.util.structGet(cfg, "phy.pdcch.candidateCCEIndex", 0));
strictCfg.CandidateIndex = double(sixgr.util.structGet(cfg, "phy.pdcch.candidateIndex", 1));
strictCfg.AggregationLevel = aggregationLevel;
strictCfg.PDCCHDMRSScramblingID = double(sixgr.util.structGet(cfg, ...
    "phy.pdcch.dmrsScramblingID", nCellID));
strictCfg.PowerOffsetdB = double(sixgr.util.structGet(cfg, "phy.pdcch.powerOffsetdB", 0));
strictCfg.BindingSource = string(sixgr.util.structGet(cfg, ...
    "phy.pdcch.bindingSource", sixgr.util.structGet(cfg, ...
    "lls6g.control.pdcch_strict.binding_source", "scenario_config")));
strictCfg.ChannelModel = string(sixgr.util.structGet(cfg, "channel.model", "AWGN"));
strictCfg.BaseConfig = cfg;
strictCfg.ExecutionProfile = string(sixgr.util.structGet( ...
    operatorStrict, "execution_profile", "legacy_explicit_context_adapter"));
strictCfg.KnownLocationFallbackAllowed = logical(sixgr.util.structGet( ...
    operatorStrict, "known_location_fallback", false));
strictCfg.OracleCandidateTimingAllowed = logical(sixgr.util.structGet( ...
    operatorStrict, "oracle_candidate_timing", false));
strictCfg.ValidationCampaign = localValidationCampaign(operatorStrict);

try
    [carrier, ~] = sixgr.phy.grid.makeCarrier(cfg);
catch
    carrier = nrCarrierConfig;
    carrier.NCellID = nCellID;
    carrier.NSizeGrid = nSizeGrid;
    carrier.NStartGrid = nStartGrid;
    carrier.SubcarrierSpacing = scsKHz;
end
strictCfg.ToolboxCarrier = carrier;

coresetDefinition = sixgr.phy.pdcch.CORESETDefinition(struct( ...
    "CORESETID", strictCfg.CORESETId, ...
    "NRB", strictCfg.CORESETNumRB, ...
    "DurationSymbols", strictCfg.CORESETDurationSymbols, ...
    "MappingType", strictCfg.CCE_REG_MappingType, ...
    "REGBundleSize", strictCfg.REGBundleSize, ...
    "InterleaverSize", strictCfg.InterleaverSize, ...
    "ShiftIndex", strictCfg.ShiftIndex, ...
    "RBStart", strictCfg.CORESETRBStart, ...
    "StartSymbol", strictCfg.SearchSpaceFirstSymbolWithinSlot, ...
    "PrecoderGranularity", strictCfg.PrecoderGranularity));
if hasContextualOperatorConfig
    searchRaw = operatorStrict.search_space;
    monitoringBitmap = localRequired(searchRaw, "monitoring_symbols_within_slot");
    allowedRNTITypes = string(localRequired(searchRaw, "allowed_rnti_types"));
    nCI = double(localRequired(searchRaw, "n_ci"));
else
    monitoringBitmap = localMonitoringBitmap(strictCfg.SearchSpaceFirstSymbolWithinSlot);
    allowedRNTITypes = rntiType;
    nCI = 0;
end
searchDefinition = sixgr.phy.pdcch.SearchSpaceDefinition(struct( ...
    "SearchSpaceID", strictCfg.SearchSpaceId, ...
    "SearchSpaceType", strictCfg.SearchSpaceType, ...
    "CORESETID", strictCfg.CORESETId, ...
    "PeriodSlots", strictCfg.SearchSpacePeriodicity, ...
    "OffsetSlots", strictCfg.SearchSpaceOffset, ...
    "DurationSlots", strictCfg.SearchSpaceDuration, ...
    "MonitoringSymbolsWithinSlot", monitoringBitmap, ...
    "NumCandidates", [strictCfg.NumCandidatesAL1 strictCfg.NumCandidatesAL2 ...
    strictCfg.NumCandidatesAL4 strictCfg.NumCandidatesAL8 strictCfg.NumCandidatesAL16], ...
    "MonitoredFormats", strictCfg.DCIMonitoringFormats, ...
    "AllowedRNTITypes", allowedRNTITypes, ...
    "NCI", nCI));
toolbox = sixgr.phy.pdcch.PDCCHToolboxFactory.create(carrier, ...
    coresetDefinition, searchDefinition, strictCfg.AggregationLevel, ...
    rntiValue, nCellID, strictCfg.NStartGrid, strictCfg.NSizeGrid);
strictCfg.CORESETDefinition = coresetDefinition;
strictCfg.SearchSpaceDefinition = searchDefinition;
strictCfg.ToolboxCORESET = toolbox.CORESET;
strictCfg.ToolboxSearchSpace = toolbox.SearchSpace;
strictCfg.ToolboxPDCCH = toolbox.PDCCH;
strictCfg.ConfigHash = sixgr.phy.pdcch.hashPDCCHConfig(strictCfg);
strictCfg.StrictValidation = sixgr.phy.pdcch.validatePDCCHConfigStrict(strictCfg);
strictCfg.ConfigExport = rmfield(strictCfg, intersect(fieldnames(strictCfg), ...
    {'ToolboxCarrier','ToolboxCORESET','ToolboxSearchSpace','ToolboxPDCCH', ...
    'CORESETDefinition','SearchSpaceDefinition','DCIContext','DCIContexts','BaseConfig'}));
end

function campaign = localValidationCampaign(operatorStrict)
raw = localRequired(operatorStrict, "validation_campaign");
campaign = struct( ...
    "TrialsPerOperatingPoint", double(localRequired(raw, ...
        "trials_per_operating_point")), ...
    "NoSignalPeriod", double(localRequired(raw, "no_signal_period")), ...
    "Channels", string(localRequired(raw, "channels")), ...
    "ChannelDopplerHz", double(localRequired(raw, "channel_doppler_hz")), ...
    "SNRByAggregationdB", double(localRequired(raw, ...
        "snr_by_aggregation_db")), ...
    "FadingSNROffsetdB", double(localRequired(raw, ...
        "fading_snr_offset_db")), ...
    "ImpactNumWorkers", double(localRequired(raw, ...
        "impact_num_workers")), ...
    "PhaseNoiseProfiles", string(localRequired(raw, ...
        "phase_noise_profiles")), ...
    "PhaseNoiseStdRadians", double(localRequired(raw, ...
        "phase_noise_std_radians")), ...
    "ImpactWaveformFamilies", string(localRequired(raw, ...
        "impact_waveform_families")));
campaign.Channels = campaign.Channels(:).';
campaign.ChannelDopplerHz = campaign.ChannelDopplerHz(:).';
campaign.SNRByAggregationdB = campaign.SNRByAggregationdB(:).';
campaign.ImpactWaveformFamilies = campaign.ImpactWaveformFamilies(:).';
campaign.PhaseNoiseProfiles = campaign.PhaseNoiseProfiles(:).';
campaign.PhaseNoiseStdRadians = campaign.PhaseNoiseStdRadians(:).';
if campaign.TrialsPerOperatingPoint < 1 || ...
        campaign.TrialsPerOperatingPoint ~= fix(campaign.TrialsPerOperatingPoint)
    error("sixgr:phy:pdcch:invalid_campaign_config", ...
        "trials_per_operating_point must be a positive integer.");
end
if campaign.NoSignalPeriod < 2 || ...
        campaign.NoSignalPeriod ~= fix(campaign.NoSignalPeriod)
    error("sixgr:phy:pdcch:invalid_campaign_config", ...
        "no_signal_period must be an integer of at least two.");
end
if numel(campaign.Channels) ~= numel(campaign.ChannelDopplerHz) || ...
        numel(campaign.SNRByAggregationdB) ~= 5
    error("sixgr:phy:pdcch:invalid_campaign_config", ...
        "Campaign channels/doppler lengths must match and five AL SNRs are required.");
end
if campaign.ImpactNumWorkers < 1 || ...
        campaign.ImpactNumWorkers ~= fix(campaign.ImpactNumWorkers) || ...
        isempty(campaign.ImpactWaveformFamilies) || ...
        numel(campaign.PhaseNoiseProfiles) ~= ...
        numel(campaign.PhaseNoiseStdRadians)
    error("sixgr:phy:pdcch:invalid_campaign_config", ...
        "Impact campaign workers/family selection is invalid.");
end
if any(~ismember(upper(campaign.Channels), ...
        ["AWGN","TDL-A","TDL-B","TDL-C","TDL-D","TDL-E", ...
        "CDL-A","CDL-B","CDL-C","CDL-D","CDL-E"]))
    error("sixgr:phy:pdcch:unsupported_channel_profile", ...
        "Validation campaign contains an unsupported or non-concrete channel profile.");
end
end

function cfg = localApplyStrictConfigToRuntime(cfg, strictCfg)
cfg = sixgr.util.structSet(cfg, "phy.carrier.NCellID", double(strictCfg.NCellID));
cfg = sixgr.util.structSet(cfg, "phy.carrier.NSizeGrid", double(strictCfg.NSizeGrid));
cfg = sixgr.util.structSet(cfg, "phy.carrier.NStartGrid", double(strictCfg.NStartGrid));
cfg = sixgr.util.structSet(cfg, "phy.numerology.scs_kHz", double(strictCfg.SubcarrierSpacingKHz));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.rnti", double(strictCfg.RNTIValue));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.rntiType", char(string(strictCfg.RNTIType)));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.dciPayloadBits", double(strictCfg.DCIPayloadSizeBits));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.KBits", double(strictCfg.DCIPayloadSizeBits));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.dciFormat", char(string(strictCfg.DCIFormat)));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.aggregationLevel", double(strictCfg.AggregationLevel));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.aggregationLevels", double(strictCfg.AggregationLevelsEnabled));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.id", double(strictCfg.CORESETId));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.duration", double(strictCfg.CORESETDurationSymbols));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.frequencyResources", double(strictCfg.CORESETFrequencyDomainResources));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.regBundleSize", double(strictCfg.REGBundleSize));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.interleaverSize", double(strictCfg.InterleaverSize));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.shiftIndex", double(strictCfg.ShiftIndex));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.searchSpace.id", double(strictCfg.SearchSpaceId));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.searchSpace.startSymbol", double(strictCfg.SearchSpaceFirstSymbolWithinSlot));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.searchSpace.duration", double(strictCfg.SearchSpaceDuration));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.searchSpace.slotPeriodAndOffset", ...
    [double(strictCfg.SearchSpacePeriodicity) double(strictCfg.SearchSpaceOffset)]);
cfg = sixgr.util.structSet(cfg, "phy.pdcch.searchSpace.numCandidates", ...
    [double(strictCfg.NumCandidatesAL1) double(strictCfg.NumCandidatesAL2) ...
    double(strictCfg.NumCandidatesAL4) double(strictCfg.NumCandidatesAL8) ...
    double(strictCfg.NumCandidatesAL16)]);
cfg = sixgr.util.structSet(cfg, "phy.pdcch.blindSearch", true);
cfg = sixgr.util.structSet(cfg, "phy.pdcch.nStartBWP", double(strictCfg.NStartGrid));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.nSizeBWP", double(strictCfg.NSizeGrid));
end

function value = localRequired(source, name)
if ~(isstruct(source) && isscalar(source) && isfield(source, name)) || ...
        isempty(source.(name))
    error("sixgr:phy:pdcch:missing_dci_context", ...
        "Strict operator PDCCH configuration is missing '%s'.", name);
end
value = source.(name);
end

function bitmap = localFrequencyBitmap(rbStart, nRB)
if mod(rbStart, 6) ~= 0 || mod(nRB, 6) ~= 0
    error("sixgr:phy:pdcch:invalid_coreset_frequency_resources", ...
        "CORESET RB start and width must align to six-RB frequency groups.");
end
bitmap = zeros(1, (rbStart+nRB)/6);
bitmap(rbStart/6+1:(rbStart+nRB)/6) = 1;
end

function bitmap = localMonitoringBitmap(startSymbol)
bitmap = false(1, 14);
bitmap(double(startSymbol)+1) = true;
end
