function [resolution, cfgSI] = deriveType0PDCCHFromMIB(carrier, cfg, mib, varargin)
%DERIVETYPE0PDCCHFROMMIB Build supported Type0 CSS resources from decoded MIB.
%
% This function is intentionally fail-closed. It implements the currently
% exercised FR1 30 kHz anchor profile for pdcch-ConfigSIB1 value 0
% (controlResourceSetZero=0, searchSpaceZero=0). Unsupported 38.213 table
% entries raise an error instead of silently falling back to YAML.

p = inputParser;
p.addParameter("RNTI", 65535, @(x) isnumeric(x) && isscalar(x));
p.parse(varargin{:});

if ~isstruct(mib)
    error("sixgr:phy:broadcast:InvalidMIB", "Decoded MIB evidence must be a struct.");
end

pdcchConfigSIB1 = double(sixgr.util.structGet(mib, "PDCCHConfigSIB1", NaN));
if ~(isfinite(pdcchConfigSIB1) && pdcchConfigSIB1 >= 0 && pdcchConfigSIB1 <= 255)
    error("sixgr:phy:broadcast:MIBPDCCHConfigMissing", ...
        "Decoded MIB does not contain a valid pdcch-ConfigSIB1 value.");
end
split = sixgr.phy.broadcast.splitPDCCHConfigSIB1(pdcchConfigSIB1, ...
    "Source", string(sixgr.util.structGet(mib, "Source", "decoded_mib")));

coresetIndex = double(split.CORESET0Index);
searchIndex = double(split.SearchSpaceZero);
scsKHz = double(localObjectOrStructField(carrier, "SubcarrierSpacing", ...
    sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing_kHz", NaN)));
if ~(coresetIndex == 0 && searchIndex == 0 && scsKHz == 30)
    error("sixgr:phy:broadcast:UnsupportedType0CSSMIBIndex", ...
        "Supported Phase-3 anchor requires 30 kHz SCS, controlResourceSetZero=0, searchSpaceZero=0; got SCS=%g, CORESET0=%g, SearchSpace0=%g.", ...
        scsKHz, coresetIndex, searchIndex);
end

cfgSI = localNormalizeCommonSIB1Cfg(cfg, double(p.Results.RNTI), split, mib);

coreset = nrCORESETConfig;
try
    coreset.CORESETID = 0;
catch
end
coreset.Duration = 2;
freqBitmap = ones(1, max(1, min(6, ceil(double(carrier.NSizeGrid) / 6))));
coreset.FrequencyResources = freqBitmap;
coreset.REGBundleSize = 6;
coreset.InterleaverSize = 2;
coreset.ShiftIndex = double(carrier.NCellID);

ss = nrSearchSpaceConfig;
try
    ss.SearchSpaceID = 0;
catch
end
ss.CORESETID = 0;
ss.StartSymbolWithinSlot = 0;
ss.SlotPeriodAndOffset = [1 0];
ss.Duration = 1;
ss.NumCandidates = [0 0 1 0 0];

pdcch = nrPDCCHConfig;
try
    pdcch.NCellID = double(carrier.NCellID);
catch
    try
        pdcch.DMRSScramblingID = double(carrier.NCellID);
    catch
    end
end
pdcch.RNTI = 0; % Type0 CSS physical scrambling; DCI CRC still uses SI-RNTI.
pdcch.CORESET = coreset;
pdcch.SearchSpace = ss;
pdcch.AggregationLevel = 4;
try
    pdcch.NStartBWP = double(carrier.NStartGrid);
    pdcch.NSizeBWP = double(carrier.NSizeGrid);
catch
end

rbStart = 0;
numRB = double(min(carrier.NSizeGrid, 6 * numel(freqBitmap)));
resolution = struct();
resolution.PDCCH = pdcch;
resolution.MIB = split;
resolution.PDCCHConfigSIB1 = double(split.PDCCHConfigSIB1);
resolution.CORESET0Index = coresetIndex;
resolution.SearchSpaceZero = searchIndex;
resolution.CORESET0 = struct( ...
    "CORESETID", 0, ...
    "Pattern", "type0_css_anchor_pattern1", ...
    "RBStart", rbStart, ...
    "NumRB", numRB, ...
    "DurationSymbols", double(coreset.Duration), ...
    "FrequencyResourceBitmap", double(freqBitmap), ...
    "REGBundleSize", double(coreset.REGBundleSize), ...
    "InterleaverSize", double(coreset.InterleaverSize), ...
    "ShiftIndex", double(coreset.ShiftIndex));
resolution.SearchSpace0 = struct( ...
    "SearchSpaceID", 0, ...
    "CORESETID", 0, ...
    "StartSymbolWithinSlot", double(ss.StartSymbolWithinSlot), ...
    "SlotPeriod", double(ss.SlotPeriodAndOffset(1)), ...
    "SlotOffset", double(ss.SlotPeriodAndOffset(2)), ...
    "DurationSlots", double(ss.Duration), ...
    "AggregationLevel", double(pdcch.AggregationLevel), ...
    "NumCandidates", double(ss.NumCandidates));
resolution.Type0PDCCHCSS = struct( ...
    "RNTI", double(p.Results.RNTI), ...
    "PDCCHScramblingRNTI", 0, ...
    "DCIFormat", "1_0", ...
    "DCIPayloadBits", 32, ...
    "DerivedFrom", "decoded_mib_pdcch_ConfigSIB1");
cfgSI.phy.sib1.runtimePDCCH = pdcch;
end

function cfgSI = localNormalizeCommonSIB1Cfg(cfg, rnti, split, mib)
cfgSI = cfg;
if ~isfield(cfgSI, "phy")
    cfgSI.phy = struct();
end
if ~isfield(cfgSI.phy, "pdcch")
    cfgSI.phy.pdcch = struct();
end
if ~isfield(cfgSI.phy, "sib1")
    cfgSI.phy.sib1 = struct();
end
cfgSI.phy.pdcch.rnti = double(rnti);
cfgSI.phy.pdcch.scramblingRNTI = 0;
cfgSI.phy.pdcch.dciPayloadBits = 32;
cfgSI.phy.pdcch.KBits = 32;
cfgSI.phy.pdcch.blindSearch = true;
cfgSI.phy.pdcch.aggregationLevel = 4;
cfgSI.phy.pdcch.allowBlindCandidateTimingEstimate = false;
cfgSI.phy.pdcch.searchSpace.numCandidates = [0 0 1 0 0];
cfgSI.phy.pdcch.searchSpace.id = 0;
cfgSI.phy.pdcch.searchSpace.startSymbol = 0;
cfgSI.phy.pdcch.searchSpace.duration = 1;
cfgSI.phy.pdcch.searchSpace.slotPeriodAndOffset = [1 0];
cfgSI.phy.pdcch.coreset.id = 0;
cfgSI.phy.pdcch.coreset.duration = 2;
cfgSI.phy.pdcch.coreset.frequencyResources = ones(1, 6);
cfgSI.phy.sib1.decodedPDCCHConfigSIB1 = double(split.PDCCHConfigSIB1);
cfgSI.phy.sib1.coreset0Index = double(split.CORESET0Index);
cfgSI.phy.sib1.searchSpaceZero = double(split.SearchSpaceZero);
cfgSI.phy.sib1.pdcchConfigSIB1Source = char(string(split.Source));
cfgSI.phy.mib.dmrsTypeAPosition = double(sixgr.util.structGet(mib, "DMRSTypeAPosition", ...
    sixgr.util.structGet(cfgSI, "phy.mib.dmrsTypeAPosition", 2)));
cfgSI.phy.pdsch.RNTI = 65535;
cfgSI.phy.pdsch.rnti = 65535;
cfgSI.phy.pdsch.modulation = "QPSK";
cfgSI.phy.pdsch.numLayers = 1;
cfgSI.phy.pdsch.nLayers = 1;
end

function value = localObjectOrStructField(obj, fieldName, defaultValue)
value = defaultValue;
try
    if isobject(obj) && isprop(obj, fieldName)
        value = obj.(fieldName);
        return;
    end
    if isstruct(obj) && isfield(obj, fieldName)
        value = obj.(fieldName);
    end
catch
    value = defaultValue;
end
end
