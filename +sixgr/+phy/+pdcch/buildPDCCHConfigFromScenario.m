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
    "phy.pdcch.rntiType", sixgr.util.structGet(cfg, "lls6g.control.pdcch_strict.rnti_type", "C-RNTI")));
rntiValue = double(sixgr.util.structGet(cfg, "phy.pdcch.rnti", ...
    sixgr.util.structGet(cfg, "lls6g.control.pdcch_strict.rnti_value", 4660)));
dciFormats = string(sixgr.util.structGet(cfg, "lls6g.control.dci_formats", ...
    sixgr.util.structGet(cfg, "phy.pdcch.dciFormat", "1_0")));
dciFormats = unique(upper(strrep(strtrim(dciFormats(:)), "-", "_")), "stable");
payloadBits = double(sixgr.util.structGet(cfg, "phy.pdcch.dciPayloadBits", ...
    sixgr.util.structGet(cfg, "lls6g.control.pdcch_payload_bits", 64)));
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
strictCfg.DCIPayloadSizeBits = payloadBits;
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

cfgForTx = localApplyStrictConfigToRuntime(cfg, strictCfg);
bits = int8(zeros(payloadBits, 1));
[tx, ~] = sixgr.phy.dl.PDCCH_Tx(cfgForTx, "DCIBits", bits, ...
    "K", payloadBits, "RNTI", rntiValue, "NCellID", nCellID);
strictCfg.ToolboxPDCCH = tx.PDCCH;
strictCfg.ConfigHash = sixgr.phy.pdcch.hashPDCCHConfig(strictCfg);
strictCfg.StrictValidation = sixgr.phy.pdcch.validatePDCCHConfigStrict(strictCfg);
strictCfg.ConfigExport = rmfield(strictCfg, intersect(fieldnames(strictCfg), ...
    {'ToolboxCarrier','ToolboxPDCCH','BaseConfig'}));
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
