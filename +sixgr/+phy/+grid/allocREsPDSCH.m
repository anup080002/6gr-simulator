function [pdschInd, info, pdsch] = allocREsPDSCH(carrier, cfgOrPdsch, varargin)
%ALLOCRESPDSCH PDSCH RE allocation indices from config.
%
%   [ind,info,pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier,cfg) creates an
%   nrPDSCHConfig from cfg.phy.pdsch and calls nrPDSCHIndices.
%
%   [ind,info,pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier,pdschCfg) uses
%   the provided nrPDSCHConfig.
%
%   Name-Value overrides (all optional):
%     "IndexBase"        - "1based" (default) or "0based"
%     "PRBSet"           - explicit vector of zero-based PRB indices
%     "SymbolAllocation" - [startSym nSym]
%     "FixedReferenceMode" - true rejects implicit mapping mutations

opts = localParseOpts(varargin{:});

if isa(cfgOrPdsch, "nrPDSCHConfig")
    pdsch = cfgOrPdsch;
else
    pdsch = localBuildFromCfg(carrier, cfgOrPdsch, opts);
end

try
    [pdschInd, indInfo] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index", "IndexBase", opts.IndexBase);
catch
    [pdschInd, indInfo] = nrPDSCHIndices(carrier, pdsch, "IndexBase", opts.IndexBase);
end

info = struct();
info.Channel = "PDSCH";
info.IndexBase = opts.IndexBase;
info.NRE = size(pdschInd, 1);
info.PRBSet = pdsch.PRBSet;
info.SymbolAllocation = pdsch.SymbolAllocation;
info.Modulation = localModulationText(pdsch.Modulation);
info.NumLayers = pdsch.NumLayers;
info.NumCodewords = double(pdsch.NumCodewords);
info.IndicesInfo = indInfo;
info.ResourceAccounting = sixgr.phy.resource.computeResourceAccounting("PDSCH", carrier, pdsch, ...
    "ChannelIndices", pdschInd, ...
    "AllocationInfo", info, ...
    "IndexBase", opts.IndexBase);
if double(info.ResourceAccounting.DMRSRE) <= 0
    error("sixgr:pdsch:NoDMRSResources", ...
        "The configured PDSCH mapping and symbol allocation produce no " + ...
        "DM-RS resource elements. Cross-check TS 38.211 mapping type, " + ...
        "allocation duration, and DM-RS position parameters.");
end
info.LayerDataRE = info.ResourceAccounting.LayerDataRE;
info.PortMappedRE = info.ResourceAccounting.PortMappedRE;
info.ModulationSymbolCount = info.ResourceAccounting.ModulationSymbolCount;
info.CodedBitCountG = info.ResourceAccounting.CodedBitCountG;
info.CodedBitCountGPerCodeword = info.ResourceAccounting.CodedBitCountGPerCodeword;
info.GPerCodeword = info.ResourceAccounting.GPerCodeword;
info.G = info.ResourceAccounting.CodedBitCountG;
info.NREPerPRB = info.ResourceAccounting.NREPerPRBForTBS;
info.DMRSRE = info.ResourceAccounting.DMRSRE;
info.PTRSRE = info.ResourceAccounting.PTRSRE;
info.ReservedRE = info.ResourceAccounting.ReservedRE;

end

function opts = localParseOpts(varargin)
opts = struct();
opts.IndexBase = "1based";
opts.PRBSet = [];
opts.SymbolAllocation = [];
opts.RNTI = [];
opts.NumLayers = [];
opts.Modulation = [];
opts.MappingType = "";
opts.MappingTypeExplicit = false;
opts.NID = [];
opts.FixedReferenceMode = false;

if mod(numel(varargin),2) ~= 0
    error("sixgr:allocREsPDSCH:InvalidNV", "Name-Value arguments must come in pairs.");
end

for i = 1:2:numel(varargin)
    name = varargin{i};
    val  = varargin{i+1};
    if ~(ischar(name) || isstring(name))
        continue;
    end
    n = char(lower(string(name)));
    switch n
        case "indexbase"
            opts.IndexBase = string(val);
        case "prbset"
            opts.PRBSet = val;
        case "symbolallocation"
            opts.SymbolAllocation = val;
        case "rnti"
            opts.RNTI = val;
        case "numlayers"
            opts.NumLayers = val;
        case "modulation"
            opts.Modulation = val;
        case "mappingtype"
            opts.MappingType = string(val);
            opts.MappingTypeExplicit = true;
        case "nid"
            opts.NID = val;
        case "fixedreferencemode"
            opts.FixedReferenceMode = logical(val);
    end
end

if opts.IndexBase ~= "0based" && opts.IndexBase ~= "1based"
    % IMPORTANT: Do NOT use C-style escaping (\") inside MATLAB string literals.
    % MATLAB interprets 0b... as a binary literal prefix, and something like
    % 0based (without quotes) will throw: "Invalid digit in binary literal".
    % Use a char vector where embedded double-quotes are literal characters.
    error("sixgr:allocREsPDSCH:BadIndexBase", 'IndexBase must be "0based" or "1based".');
end

end

function pdsch = localBuildFromCfg(carrier, cfg, opts)
% Build nrPDSCHConfig from an explicit calibration configuration. Strict
% connected/SPS execution materializes from PDSCHSchedulingAssignment.

pdsch = nrPDSCHConfig;

% Defaults from cfg
modStr = "";
numLayers = 1;
rnti = 1;
nid = [];
mapType = "A";
prbSetCfg = [];
symAllocCfg = [];
mapTypeExplicit = false;
tdraID = "";

if isstruct(cfg)
    modStr = sixgr.util.structGet(cfg, "phy.pdsch.modulation", modStr);
    numLayers = double(sixgr.util.structGet(cfg, "phy.pdsch.numLayers", numLayers));
    rnti = double(sixgr.util.structGet(cfg, "phy.pdsch.RNTI", rnti));
    nid = sixgr.util.structGet(cfg, "phy.pdsch.NID", ...
        sixgr.util.structGet(cfg, "phy.pdsch.nid", nid));
    rawMapType = string(sixgr.util.structGet(cfg, "phy.pdsch.mappingType", ...
        sixgr.util.structGet(cfg, "phy.pdsch.MappingType", "")));
    if strlength(strtrim(rawMapType)) > 0
        mapType = rawMapType;
        mapTypeExplicit = true;
    end
    prbSetCfg = sixgr.util.structGet(cfg, "phy.pdsch.prbSet", prbSetCfg);
    symAllocCfg = sixgr.util.structGet(cfg, "phy.pdsch.symbolAllocation", symAllocCfg);
    tdraID = string(sixgr.util.structGet(cfg, "phy.pdsch.tdraId", ...
        sixgr.util.structGet(cfg, "phy.pdsch.TDRAID", "")));
end

% Apply overrides
if ~isempty(opts.NumLayers), numLayers = double(opts.NumLayers); end
if ~isempty(opts.Modulation), modStr = opts.Modulation; end
if ~isempty(opts.RNTI), rnti = double(opts.RNTI); end
if ~isempty(opts.NID), nid = opts.NID; end
if strlength(opts.MappingType) > 0
    mapType = opts.MappingType;
    mapTypeExplicit = logical(opts.MappingTypeExplicit);
end
if ~isempty(opts.PRBSet), prbSetCfg = opts.PRBSet; end
if ~isempty(opts.SymbolAllocation), symAllocCfg = opts.SymbolAllocation; end

[symAllocCfg, mapType, mapTypeExplicit] = localResolvePDSCHTDRA( ...
    carrier, cfg, tdraID, symAllocCfg, mapType, mapTypeExplicit, ...
    opts.FixedReferenceMode);

% Assign
if isempty(modStr) || all(strlength(strtrim(string(modStr))) == 0)
    error("sixgr:pdsch:MissingCodewordSpecificModulation", ...
        "PDSCH modulation must be explicit for every codeword.");
end
pdsch.Modulation = localNormalizeModulationForCodewords(modStr, 1 + (double(numLayers) > 4));
pdsch.NumLayers = numLayers;
pdsch.RNTI = rnti;

prbVec = localExpandPRBSet(prbSetCfg, carrier.NSizeGrid);
pdsch.PRBSet = prbVec;

pdsch.SymbolAllocation = double(symAllocCfg(:).');
pdsch = localApplyPDSCHDMRSConfig(pdsch, cfg);
% Preserve an explicitly configured logical DM-RS port set. The Toolbox
% object may retain its own empty calibration value, but a valid supplied
% set is never overwritten or renumbered.  Resolve this before PT-RS so
% first_scheduled_dmrs_port observes the actual scheduled port set.
configuredDMRSPorts = sixgr.phy.grant.resolveScheduledDMRSPortSet( ...
    cfg, "DL", pdsch.NumLayers, struct());
maxLogicalPort = 11;
if isprop(pdsch.DMRS, "DMRSEnhancedR18") && ...
        logical(pdsch.DMRS.DMRSEnhancedR18)
    maxLogicalPort = 23;
end
localValidateDMRSPortSet( ...
    configuredDMRSPorts,pdsch.NumLayers,maxLogicalPort);
pdsch.DMRS.DMRSPortSet = double(configuredDMRSPorts(:).');

pdsch = localApplyPDSCHPTRSConfig(pdsch, cfg);
pdsch = localNormalizePDSCHMapping(pdsch, mapType, mapTypeExplicit, opts.FixedReferenceMode);

% Optional NID (scrambling)
try
    if isprop(pdsch, "NID")
        if isempty(nid)
            nid = carrier.NCellID;
        end
        pdsch.NID = double(nid);
    end
catch
end

pdsch = localReserveCSIRSResources(carrier, pdsch, cfg);
pdsch = localReserveTRSResources(carrier, pdsch, cfg);

end

function [symbolAllocation, mappingType, mappingExplicit] = ...
        localResolvePDSCHTDRA(carrier, cfg, tdraID, ...
        symbolAllocation, mappingType, mappingExplicit, fixedReferenceMode)
strict = logical(fixedReferenceMode);
if isstruct(cfg)
    strict = strict || ...
        logical(sixgr.util.structGet(cfg, "run.strictMode", false)) || ...
        logical(sixgr.util.structGet(cfg, "validation.strict", false));
end
symbolsPerSlot = localSymbolsPerSlot(carrier);
tdraID = strtrim(string(tdraID));
if strlength(tdraID) > 0
    raw = struct( ...
        "TDRAID", tdraID, ...
        "Channel", "PDSCH", ...
        "DMRSTypeAPosition", localPDSCHDMRSTypeAPosition(cfg));
    if ~isempty(symbolAllocation)
        raw.StartSymbol = double(symbolAllocation(1));
        if numel(symbolAllocation) >= 2
            raw.NumSymbols = double(symbolAllocation(2));
        end
    end
    if logical(mappingExplicit)
        raw.MappingType = mappingType;
    end
    tdra = sixgr.phy.frame.ResourceAllocationValidator.resolveTDRA( ...
        raw, symbolsPerSlot);
    symbolAllocation = [tdra.StartSymbol tdra.NumSymbols];
    mappingType = tdra.MappingType;
    mappingExplicit = true;
    return;
end

if isempty(symbolAllocation)
    error("sixgr:phy:grid:allocREsPDSCH:MissingExplicitTDRA", ...
        "PDSCH transmission requires phy.pdsch.tdraId or an explicit " + ...
        "phy.pdsch.symbolAllocation test/configuration grant. A missing " + ...
        "allocation is not expanded to a full slot.");
end
if numel(symbolAllocation) ~= 2
    error("sixgr:phy:grid:allocREsPDSCH:InvalidTDRA", ...
        "PDSCH SymbolAllocation must be [zeroBasedStart positiveLength].");
end
if strict && ~logical(mappingExplicit)
    error("sixgr:phy:grid:allocREsPDSCH:MissingExplicitTDRA", ...
        "Strict PDSCH transmission requires an explicit TDRA MappingType A or B.");
end
raw = struct( ...
    "StartSymbol", double(symbolAllocation(1)), ...
    "NumSymbols", double(symbolAllocation(2)), ...
    "MappingType", string(mappingType));
tdra = sixgr.phy.frame.ResourceAllocationValidator.resolveTDRA( ...
    raw, symbolsPerSlot);
symbolAllocation = [tdra.StartSymbol tdra.NumSymbols];
mappingType = tdra.MappingType;
end

function position = localPDSCHDMRSTypeAPosition(cfg)
position = 2;
if ~isstruct(cfg)
    return;
end
candidate = sixgr.util.structGet(cfg, ...
    "phy.pdsch.dmrs.typeAPosition", ...
    sixgr.util.structGet(cfg, ...
    "phy.pdsch.dmrs.DMRSTypeAPosition", []));
if ~isempty(candidate)
    position = double(candidate);
end
end

function count = localSymbolsPerSlot(carrier)
numerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
    double(carrier.SubcarrierSpacing), string(carrier.CyclicPrefix), ...
    "generic_waveform_test", "");
count = double(numerology.SymbolsPerSlot);
end

function prbVec = localExpandPRBSet(prbSetCfg, nSizeGrid)
% Preserve the exact explicit PRB vector. Range interpretation belongs to
% the decoded FDRA allocator and is not inferred from a two-element vector.

if isempty(prbSetCfg)
    error("sixgr:phy:grid:allocREsPDSCH:MissingPRBSet", ...
        "PDSCH transmission requires an explicit nonempty PRBSet. A " + ...
        "missing allocation is not expanded to the full carrier grid.");
end
if ~(isnumeric(prbSetCfg) && isreal(prbSetCfg))
    error("sixgr:phy:grid:allocREsPDSCH:InvalidPRBSet", ...
        "PDSCH PRBSet must be a real numeric vector.");
end

prbSetCfg = double(prbSetCfg(:).');
if any(~isfinite(prbSetCfg)) || any(prbSetCfg ~= fix(prbSetCfg)) || ...
        any(prbSetCfg < 0) || any(prbSetCfg >= double(nSizeGrid)) || ...
        numel(unique(prbSetCfg)) ~= numel(prbSetCfg)
    error("sixgr:phy:grid:allocREsPDSCH:InvalidPRBSet", ...
        "PDSCH PRBSet must contain unique integer indices in [0,%d].", ...
        round(double(nSizeGrid)) - 1);
end
prbVec = prbSetCfg;
if isempty(prbVec)
    error("sixgr:phy:grid:allocREsPDSCH:MissingPRBSet", ...
        "PDSCH transmission requires an explicit nonempty PRBSet.");
end

end

function modulation = localNormalizeModulationForCodewords(raw, nCodewords)
if ~(isnumeric(nCodewords) && isreal(nCodewords) && isscalar(nCodewords) ...
        && isfinite(nCodewords) && nCodewords == fix(nCodewords) ...
        && any(nCodewords == [1 2]))
    error("sixgr:pdsch:InvalidCodewordCount", ...
        "PDSCH NumCodewords must be exactly 1 or 2.");
end
nCodewords = double(nCodewords);
if iscell(raw)
    tokens = string(raw);
else
    tokens = string(raw);
end
tokens = tokens(:).';
if isempty(tokens) || any(strlength(strtrim(tokens)) == 0)
    error("sixgr:pdsch:MissingCodewordSpecificModulation", ...
        "PDSCH modulation must be explicit for every codeword.");
end
if numel(tokens) ~= nCodewords
    error("sixgr:pdsch:MissingCodewordSpecificModulation", ...
        "PDSCH rank requires %d codeword modulation value(s); received %d.", ...
        nCodewords, numel(tokens));
end
tokens = upper(strrep(strtrim(tokens), " ", ""));
supported = ["QPSK","16QAM","64QAM","256QAM","1024QAM"];
if any(~ismember(tokens, supported))
    bad = tokens(find(~ismember(tokens, supported), 1));
    error("sixgr:pdsch:UnsupportedNRModulation", ...
        "Unsupported strict NR PDSCH modulation '%s'.", bad);
end
if nCodewords == 1
    modulation = char(tokens(1));
else
    modulation = cellstr(tokens);
end
end

function text = localModulationText(raw)
if iscell(raw)
    tokens = string(raw);
else
    tokens = string(raw);
end
tokens = tokens(:).';
tokens = tokens(strlength(strtrim(tokens)) > 0);
if isempty(tokens)
    text = "";
else
    text = strjoin(tokens, "|");
end
end

function pdsch = localApplyPDSCHDMRSConfig(pdsch, cfg)
if ~(isstruct(cfg) && isprop(pdsch, "DMRS"))
    return;
end

dmrs = pdsch.DMRS;

typeAPos = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.typeAPosition", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.typeApos", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.DMRSTypeAPosition", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.typeAPosition", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.typeApos", []), ...
    []);
if ~isempty(typeAPos) && isprop(dmrs, "DMRSTypeAPosition")
    localValidateIntegerMember(typeAPos, [2 3], "InvalidDMRSTypeAPosition");
    dmrs.DMRSTypeAPosition = double(typeAPos);
end

configType = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.configurationType", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.configType", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.DMRSConfigurationType", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.configurationType", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.configType", []), ...
    []);
if ~isempty(configType) && isprop(dmrs, "DMRSConfigurationType")
    localValidateIntegerMember(configType, [1 2], "InvalidDMRSConfigurationType");
    dmrs.DMRSConfigurationType = double(configType);
end

addPos = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.additionalPositions", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.additionalPosition", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.DMRSAdditionalPosition", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.additionalPositions", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.DMRSAdditionalPosition", []), ...
    []);
if ~isempty(addPos) && isprop(dmrs, "DMRSAdditionalPosition")
    localValidateIntegerMember(addPos, 0:3, "InvalidDMRSAdditionalPosition");
    dmrs.DMRSAdditionalPosition = double(addPos);
end

dmrsLength = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.maxLength", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.length", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.DMRSLength", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.maxLength", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.DMRSLength", []), ...
    []);
if ~isempty(dmrsLength) && isprop(dmrs, "DMRSLength")
    localValidateIntegerMember(dmrsLength, [1 2], "InvalidDMRSLength");
    dmrs.DMRSLength = double(dmrsLength);
end

numCDM = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.numCDMGroupsWithoutData", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.NumCDMGroupsWithoutData", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.numCDMGroupsWithoutData", []), ...
    []);
if ~isempty(numCDM) && isprop(dmrs, "NumCDMGroupsWithoutData")
    localValidateIntegerMember(numCDM, 1:3, "InvalidNumCDMGroupsWithoutData");
    dmrs.NumCDMGroupsWithoutData = double(numCDM);
end

enhancedR18 = sixgr.util.structGet( ...
    cfg, "phy.pdsch.dmrs.enhancedR18", ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.DMRSEnhancedR18", []));
if ~isempty(enhancedR18)
    if ~((islogical(enhancedR18) || isnumeric(enhancedR18)) ...
            && isscalar(enhancedR18) && isfinite(double(enhancedR18)) ...
            && any(double(enhancedR18) == [0 1]))
        error("sixgr:pdsch:InvalidDMRSEnhancedR18", ...
            "DMRSEnhancedR18 must be an explicit logical scalar.");
    end
    if isprop(dmrs, "DMRSEnhancedR18")
        dmrs.DMRSEnhancedR18 = logical(enhancedR18);
    elseif logical(enhancedR18)
        error("sixgr:pdsch:DMRSEnhancedR18Unavailable", ...
            "The installed 5G Toolbox does not expose DMRSEnhancedR18.");
    end
end

pdsch.DMRS = dmrs;
end

function pdsch = localApplyPDSCHPTRSConfig(pdsch, cfg)
if ~(isstruct(cfg) && isprop(pdsch, "EnablePTRS"))
    return;
end

enabled = logical(sixgr.util.structGet(cfg, "phy.pdsch.enablePTRS", ...
    sixgr.util.structGet(cfg, "phy.ptrs.enable", ...
    sixgr.util.structGet(cfg, "pdsch6gr.EnablePTRS", ...
    sixgr.util.structGet(cfg, "PTRS.PTRSEnabled", false)))));
pdsch.EnablePTRS = enabled;
if ~enabled || ~isprop(pdsch, "PTRS")
    return;
end

ptrs = pdsch.PTRS;
timeDensity = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pdsch.ptrs.timeDensity", []), ...
    sixgr.util.structGet(cfg, "phy.ptrs.timeDensity", []), ...
    sixgr.util.structGet(cfg, "pdsch6gr.PTRSTimeDensity", []), ...
    sixgr.util.structGet(cfg, "PTRS.TimeDensity", []));
freqDensity = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pdsch.ptrs.frequencyDensity", []), ...
    sixgr.util.structGet(cfg, "phy.ptrs.frequencyDensity", []), ...
    sixgr.util.structGet(cfg, "pdsch6gr.PTRSFrequencyDensity", []), ...
    sixgr.util.structGet(cfg, "PTRS.FrequencyDensity", []));
reOffset = string(sixgr.util.structGet(cfg, "phy.pdsch.ptrs.reOffset", ...
    sixgr.util.structGet(cfg, "phy.ptrs.reOffset", ...
    sixgr.util.structGet(cfg, "pdsch6gr.PTRSREOffset", ...
    sixgr.util.structGet(cfg, "PTRS.REOffset", "")))));
portSet = sixgr.util.structGet(cfg, "phy.pdsch.ptrs.portSet", ...
    sixgr.util.structGet(cfg, "phy.ptrs.portSet", ...
    sixgr.util.structGet(cfg, "pdsch6gr.PTRSPortSet", ...
    sixgr.util.structGet(cfg, "DMRS.PortSet", []))));
scheduledDMRSPorts = [];
try
    if isprop(pdsch, "DMRS") && isprop(pdsch.DMRS, "DMRSPortSet")
        scheduledDMRSPorts = double(pdsch.DMRS.DMRSPortSet(:).');
    end
catch
    scheduledDMRSPorts = [];
end
% Use the same YAML-owned association resolver as grant freezing.  This
% keeps direct PHY-calibration execution and scheduled execution identical:
% first_scheduled_dmrs_port follows the actual allocation, whereas
% configured_absolute_port must name an exact scheduled DM-RS port.
[~, portSet] = sixgr.phy.grant.resolveScheduledPTRSPortSet( ...
    cfg, "DL", scheduledDMRSPorts, struct("PTRSPortSet", portSet));

if isempty(timeDensity)
    error("sixgr:pdsch:MissingPTRSTimeDensity", ...
        "Enabled PDSCH PT-RS requires explicit time density.");
end
if isempty(freqDensity)
    error("sixgr:pdsch:MissingPTRSFrequencyDensity", ...
        "Enabled PDSCH PT-RS requires explicit frequency density.");
end
if strlength(strtrim(reOffset)) == 0
    error("sixgr:pdsch:MissingPTRSREOffset", ...
        "Enabled PDSCH PT-RS requires an explicit RE offset.");
end
if isempty(portSet)
    error("sixgr:pdsch:MissingPTRSPortSet", ...
        ["Enabled PDSCH PT-RS with configured_absolute_port policy " ...
         "requires an explicit associated DM-RS port."]);
end
localValidateIntegerMember(timeDensity, [1 2 4 8], "InvalidPTRSTimeDensity");
localValidateIntegerMember(freqDensity, [2 4], "InvalidPTRSFrequencyDensity");
portSet = double(portSet(:).');
if any(~isfinite(portSet)) || any(portSet ~= fix(portSet)) || ...
        any(portSet < 0) || numel(unique(portSet)) ~= numel(portSet)
    error("sixgr:pdsch:InvalidPTRSPortAssociation", ...
        "PT-RS ports must be unique zero-based integer DM-RS ports.");
end
try
    if isprop(ptrs, "TimeDensity")
        ptrs.TimeDensity = double(timeDensity);
    end
    if isprop(ptrs, "FrequencyDensity")
        ptrs.FrequencyDensity = double(freqDensity);
    end
    if isprop(ptrs, "REOffset")
        ptrs.REOffset = char(reOffset);
    end
    if isprop(ptrs, "PTRSPortSet")
        ptrs.PTRSPortSet = portSet;
    end
    pdsch.PTRS = ptrs;
catch ME
    error("sixgr:phy:grid:allocREsPDSCH:BadPTRSConfig", ...
        "Invalid PDSCH PTRS runtime configuration: %s", ME.message);
end
end

function pdsch = localNormalizePDSCHMapping(pdsch, mapType, explicitMapType, fixedReferenceMode)
if nargin < 2 || strlength(string(mapType)) == 0
    mapType = "A";
end
if nargin < 3
    explicitMapType = false;
end
if nargin < 4
    fixedReferenceMode = false;
end

mapType = upper(strtrim(string(mapType)));
if strlength(mapType) == 0
    mapType = "A";
end

symAlloc = double(pdsch.SymbolAllocation(:).');
if numel(symAlloc) < 2
    error("sixgr:phy:grid:allocREsPDSCH:MissingExplicitTDRA", ...
        "PDSCH SymbolAllocation must be present before mapping validation.");
end
startSym = double(symAlloc(1));
typeAPos = 2;
try
    if isprop(pdsch, "DMRS") && isprop(pdsch.DMRS, "DMRSTypeAPosition")
        typeAPos = double(pdsch.DMRS.DMRSTypeAPosition);
    end
catch
end
localValidateIntegerMember(typeAPos, [2 3], "InvalidDMRSTypeAPosition");

if mapType == "A" && startSym > typeAPos
    error("sixgr:phy:grid:allocREsPDSCH:InvalidTypeADMRSSymbol", ...
        "PDSCH MappingType A starts at symbol %d after configured DMRSTypeAPosition=%d.", ...
        round(double(startSym)), round(double(typeAPos)));
end

try
    if isprop(pdsch, "MappingType")
        pdsch.MappingType = char(mapType);
    end
catch ME
    error("sixgr:phy:grid:allocREsPDSCH:BadMappingType", ...
        "Invalid PDSCH MappingType '%s': %s", char(mapType), ME.message);
end
end

function val = localFirstFiniteScalar(varargin)
val = [];
for i = 1:numel(varargin)
    candidate = varargin{i};
    if isempty(candidate)
        continue;
    end
    if isnumeric(candidate) && isscalar(candidate) && isfinite(double(candidate))
        val = double(candidate);
        return;
    end
end
end

function value = localFirstNonemptyNumeric(varargin)
value = [];
for idx = 1:nargin
    candidate = varargin{idx};
    if isnumeric(candidate) && ~isempty(candidate)
        value = candidate;
        return;
    end
end
end

function localValidateIntegerMember(value, allowed, token)
if ~(isnumeric(value) && isscalar(value) && isfinite(value) && ...
        value == fix(value) && ismember(double(value), double(allowed)))
    error("sixgr:pdsch:" + string(token), ...
        "Configured PDSCH value %s is invalid.", mat2str(value));
end
end

function localValidateDMRSPortSet(ports, numLayers, maxLogicalPort)
ports = double(ports(:).');
if nargin < 3
    maxLogicalPort = 11;
end
if any(~isfinite(ports)) || any(ports ~= fix(ports)) || ...
        any(ports < 0) || any(ports > double(maxLogicalPort)) || ...
        numel(unique(ports)) ~= numel(ports) || ...
        numel(ports) ~= double(numLayers)
    error("sixgr:pdsch:InvalidDMRSPortSet", ...
        "DM-RS port set must contain one unique logical port per layer.");
end
end

function pdsch = localReserveCSIRSResources(carrier, pdsch, cfg)
if ~(isstruct(cfg) && logical(sixgr.util.structGet(cfg, "phy.csirs.enable", false)))
    return;
end
try
    [csirsInd, csirsSym, csirsInfo] = sixgr.phy.refsig.csirs( ...
        carrier, cfg, "IndexBase", "0based");
catch ME
    error("sixgr:phy:grid:allocREsPDSCH:CSIRSReservationFailed", ...
        "CSI-RS is enabled but runtime CSI-RS resources could not be generated for PDSCH reservation: %s", ME.message);
end
if isempty(csirsSym) || ~isstruct(csirsInfo) || ~logical(sixgr.util.structGet(csirsInfo, "Enabled", false))
    return;
end

% CSI-RS is sparse inside each configured RB.  Reserving an entire PRB for
% every CSI-RS symbol removes unrelated PDSCH data and can remove every
% active DM-RS RE from a narrow scheduler grant.  nrPDSCHConfig.ReservedRE
% is zero-based, so project the physical multi-port CSI-RS indices onto one
% resource-grid plane and retain only REs inside this PDSCH allocation.
plane = double(carrier.NSizeGrid) * 12 * double(carrier.SymbolsPerSlot);
csirsBaseZero = unique(mod(double(csirsInd(:)), plane), "sorted");
prbs = double(pdsch.PRBSet(:).');
symbolAllocation = double(pdsch.SymbolAllocation(:).');
subcarriers = reshape(12 .* prbs + (0:11).', 1, []);
scheduledSymbols = symbolAllocation(1) + (0:(symbolAllocation(2) - 1));
[k, l] = ndgrid(subcarriers, scheduledSymbols);
allocationZero = double(k(:) + 12 .* double(carrier.NSizeGrid) .* l(:));
reservedZero = intersect(csirsBaseZero, allocationZero, "sorted");
if isempty(reservedZero)
    return;
end

% PDSCH data can be rate-matched around exact CSI-RS REs, but PDSCH DM-RS
% cannot be punctured by CSI-RS.  Reject a colliding YAML schedule before
% the Toolbox silently deactivates the receiver's channel-estimation
% reference symbols.
dmrsSub = nrPDSCHDMRSIndices(carrier, pdsch, ...
    "IndexStyle", "subscript", "IndexBase", "0based");
dmrsBaseZero = unique(double(dmrsSub(:,1) + ...
    12 .* double(carrier.NSizeGrid) .* dmrsSub(:,2)), "sorted");
dmrsCollision = intersect(reservedZero, dmrsBaseZero, "sorted");
if ~isempty(dmrsCollision)
    error("sixgr:phy:grid:allocREsPDSCH:CSIRSDMRSCollision", ...
        ['Configured CSI-RS overlaps %d active PDSCH DM-RS RE(s) in slot %d. ' ...
         'Move the YAML-owned CSI-RS resource(s) off the DM-RS symbols; ' ...
         'DM-RS puncturing is not permitted.'], ...
        numel(dmrsCollision), double(carrier.NSlot));
end

try
    existing = double(pdsch.ReservedRE(:));
    pdsch.ReservedRE = unique([existing; reservedZero(:)], "sorted");
catch ME
    error("sixgr:phy:grid:allocREsPDSCH:CSIRSReservationApplyFailed", ...
        "CSI-RS runtime resources were generated but could not be reserved in the PDSCH allocation: %s", ME.message);
end
end

function pdsch = localReserveTRSResources(carrier, pdsch, cfg)
% TRS is an NZP-CSI-RS resource and owns exact REs on its configured
% occasions. The PDSCH encoder must rate-match around those REs before G
% and TBS are frozen; removing collisions only from an exported grid would
% leave the transmitted codeword and receiver allocation inconsistent.
if ~(isstruct(cfg) && logical(sixgr.util.structGet(cfg, ...
        "phy.trs.enable", false)))
    return;
end

try
    strictTRS = sixgr.phy.trs.buildTRSConfigFromScenario(cfg, ...
        "RunId", "pdsch_exact_trs_reservation", ...
        "ScenarioName", "pdsch_exact_trs_reservation");
catch ME
    error("sixgr:phy:grid:allocREsPDSCH:TRSReservationFailed", ...
        "TRS is enabled but its exact NZP-CSI-RS resource could not be resolved for PDSCH reservation: %s", ...
        ME.message);
end

slotsPerFrame = round(double(carrier.SlotsPerFrame));
slot0 = mod(round(double(carrier.NSlot)), slotsPerFrame);
configuredSlots0 = unique(mod(round(double(strictTRS.SlotNumbers(:))), ...
    slotsPerFrame), "stable");
if ~ismember(slot0, configuredSlots0)
    return;
end

try
    trsCarrier = carrier;
    trsCarrier.NSlot = slot0;
    trsIndices = nrCSIRSIndices(trsCarrier, strictTRS.ToolboxCSIRS, ...
        "IndexStyle", "index", "IndexBase", "0based");
catch ME
    error("sixgr:phy:grid:allocREsPDSCH:TRSReservationFailed", ...
        "The active TRS occasion in carrier slot %d could not be materialized for exact PDSCH reservation: %s", ...
        slot0, ME.message);
end

if isempty(trsIndices)
    error("sixgr:phy:grid:allocREsPDSCH:EmptyActiveTRSReservation", ...
        "TRS is active in carrier slot %d but produced no exact REs.", slot0);
end

plane = double(carrier.NSizeGrid) * 12 * double(carrier.SymbolsPerSlot);
trsBaseZero = unique(mod(double(trsIndices(:)), plane), "sorted");
reservedZero = localReferenceREInsidePDSCHAllocation( ...
    trsBaseZero, carrier, pdsch);
if isempty(reservedZero)
    return;
end

localRejectReferenceDMRSCollision( ...
    reservedZero, carrier, pdsch, "TRS", ...
    "sixgr:phy:grid:allocREsPDSCH:TRSDMRSCollision");
try
    pdsch.ReservedRE = unique([double(pdsch.ReservedRE(:)); ...
        reservedZero(:)], "sorted");
catch ME
    error("sixgr:phy:grid:allocREsPDSCH:TRSReservationApplyFailed", ...
        "Exact TRS REs were resolved but could not be installed in PDSCH ReservedRE: %s", ...
        ME.message);
end
end

function reservedZero = localReferenceREInsidePDSCHAllocation( ...
        referenceBaseZero, carrier, pdsch)
prbs = double(pdsch.PRBSet(:).');
symbolAllocation = double(pdsch.SymbolAllocation(:).');
subcarriers = reshape(12 .* prbs + (0:11).', 1, []);
scheduledSymbols = symbolAllocation(1) + ...
    (0:(symbolAllocation(2) - 1));
[k, l] = ndgrid(subcarriers, scheduledSymbols);
allocationZero = double(k(:) + ...
    12 .* double(carrier.NSizeGrid) .* l(:));
reservedZero = intersect(double(referenceBaseZero(:)), ...
    allocationZero, "sorted");
end

function localRejectReferenceDMRSCollision( ...
        reservedZero, carrier, pdsch, signalName, identifier)
dmrsSub = nrPDSCHDMRSIndices(carrier, pdsch, ...
    "IndexStyle", "subscript", "IndexBase", "0based");
dmrsBaseZero = unique(double(dmrsSub(:,1) + ...
    12 .* double(carrier.NSizeGrid) .* dmrsSub(:,2)), "sorted");
dmrsCollision = intersect(double(reservedZero(:)), ...
    dmrsBaseZero, "sorted");
if ~isempty(dmrsCollision)
    error(identifier, ...
        ['Configured %s overlaps %d active PDSCH DM-RS RE(s) in slot %d. ' ...
         'Move the YAML-owned reference resource off the DM-RS symbols; ' ...
         'DM-RS puncturing is not permitted.'], ...
        signalName, numel(dmrsCollision), double(carrier.NSlot));
end
end
