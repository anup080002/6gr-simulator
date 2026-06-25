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
%     "PRBSet"           - vector of PRB indices or [start end]
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
info.Modulation = string(pdsch.Modulation);
info.NumLayers = pdsch.NumLayers;
info.IndicesInfo = indInfo;
info.ResourceAccounting = sixgr.phy.resource.computeResourceAccounting("PDSCH", carrier, pdsch, ...
    "ChannelIndices", pdschInd, ...
    "AllocationInfo", info, ...
    "IndexBase", opts.IndexBase);
info.LayerDataRE = info.ResourceAccounting.LayerDataRE;
info.PortMappedRE = info.ResourceAccounting.PortMappedRE;
info.ModulationSymbolCount = info.ResourceAccounting.ModulationSymbolCount;
info.CodedBitCountG = info.ResourceAccounting.CodedBitCountG;
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
opts.Modulation = "";
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
            opts.Modulation = string(val);
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
% Build nrPDSCHConfig from SixGR cfg. Keep defaults where fields are absent.

pdsch = nrPDSCHConfig;

% Defaults from cfg
modStr = "16QAM";
numLayers = 1;
rnti = 1;
nid = [];
mapType = "A";
prbSetCfg = [];
symAllocCfg = [0 14];
mapTypeExplicit = false;

if isstruct(cfg)
    modStr = string(sixgr.util.structGet(cfg, "phy.pdsch.modulation", modStr));
    numLayers = double(sixgr.util.structGet(cfg, "phy.pdsch.numLayers", numLayers));
    rnti = double(sixgr.util.structGet(cfg, "phy.pdsch.RNTI", rnti));
    nid = sixgr.util.structGet(cfg, "phy.pdsch.NID", ...
        sixgr.util.structGet(cfg, "phy.pdsch.nid", nid));
    rawMapType = string(sixgr.util.structGet(cfg, "phy.pdsch.mappingType", ""));
    if strlength(strtrim(rawMapType)) > 0
        mapType = rawMapType;
        mapTypeExplicit = true;
    end
    prbSetCfg = sixgr.util.structGet(cfg, "phy.pdsch.prbSet", prbSetCfg);
    symAllocCfg = sixgr.util.structGet(cfg, "phy.pdsch.symbolAllocation", symAllocCfg);
end

% Apply overrides
if strlength(opts.Modulation) > 0, modStr = opts.Modulation; end
if ~isempty(opts.NumLayers), numLayers = double(opts.NumLayers); end
if ~isempty(opts.RNTI), rnti = double(opts.RNTI); end
if ~isempty(opts.NID), nid = opts.NID; end
if strlength(opts.MappingType) > 0
    mapType = opts.MappingType;
    mapTypeExplicit = logical(opts.MappingTypeExplicit);
end
if ~isempty(opts.PRBSet), prbSetCfg = opts.PRBSet; end
if ~isempty(opts.SymbolAllocation), symAllocCfg = opts.SymbolAllocation; end

% Assign
pdsch.Modulation = char(modStr);
pdsch.NumLayers = numLayers;
pdsch.RNTI = rnti;

prbVec = localExpandPRBSet(prbSetCfg, carrier.NSizeGrid);
pdsch.PRBSet = prbVec;

pdsch.SymbolAllocation = double(symAllocCfg(:).');
pdsch = localApplyPDSCHDMRSConfig(pdsch, cfg);
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

% Make DMRS ports consistent with NumLayers to avoid downstream errors.
try
    if isprop(pdsch, "DMRS") && isprop(pdsch.DMRS, "DMRSPortSet")
        pdsch.DMRS.DMRSPortSet = 0:(pdsch.NumLayers-1);
    end
catch
end

pdsch = localReserveCSIRSResources(carrier, pdsch, cfg);

end

function prbVec = localExpandPRBSet(prbSetCfg, nSizeGrid)
% Accept [] -> full grid, [start end] -> start:end, else vector.

if isempty(prbSetCfg)
    prbVec = 0:(nSizeGrid-1);
    return;
end

prbSetCfg = double(prbSetCfg(:).');

if numel(prbSetCfg) == 2 && prbSetCfg(2) >= prbSetCfg(1)
    prbVec = prbSetCfg(1):prbSetCfg(2);
else
    prbVec = prbSetCfg;
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
    dmrs.DMRSTypeAPosition = max(2, min(3, round(double(typeAPos))));
end

configType = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.configurationType", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.configType", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.DMRSConfigurationType", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.configurationType", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.configType", []), ...
    []);
if ~isempty(configType) && isprop(dmrs, "DMRSConfigurationType")
    dmrs.DMRSConfigurationType = max(1, min(2, round(double(configType))));
end

addPos = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.additionalPositions", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.additionalPosition", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.DMRSAdditionalPosition", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.additionalPositions", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.DMRSAdditionalPosition", []), ...
    []);
if ~isempty(addPos) && isprop(dmrs, "DMRSAdditionalPosition")
    dmrs.DMRSAdditionalPosition = max(0, min(3, round(double(addPos))));
end

dmrsLength = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.maxLength", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.length", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.DMRSLength", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.maxLength", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.DMRSLength", []), ...
    []);
if ~isempty(dmrsLength) && isprop(dmrs, "DMRSLength")
    dmrs.DMRSLength = max(1, min(2, round(double(dmrsLength))));
end

numCDM = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.numCDMGroupsWithoutData", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.NumCDMGroupsWithoutData", []), ...
    sixgr.util.structGet(cfg, "phy.dmrs.numCDMGroupsWithoutData", []), ...
    []);
if ~isempty(numCDM) && isprop(dmrs, "NumCDMGroupsWithoutData")
    dmrs.NumCDMGroupsWithoutData = max(1, min(3, round(double(numCDM))));
end

pdsch.DMRS = dmrs;
end

function pdsch = localApplyPDSCHPTRSConfig(pdsch, cfg)
if ~(isstruct(cfg) && isprop(pdsch, "EnablePTRS"))
    return;
end

enabled = logical(sixgr.util.structGet(cfg, "phy.pdsch.enablePTRS", ...
    sixgr.util.structGet(cfg, "phy.ptrs.enable", ...
    sixgr.util.structGet(cfg, "pdsch6gr.EnablePTRS", false))));
pdsch.EnablePTRS = enabled;
if ~enabled || ~isprop(pdsch, "PTRS")
    return;
end

ptrs = pdsch.PTRS;
timeDensity = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pdsch.ptrs.timeDensity", []), ...
    sixgr.util.structGet(cfg, "phy.ptrs.timeDensity", []), ...
    sixgr.util.structGet(cfg, "pdsch6gr.PTRSTimeDensity", []), ...
    2);
freqDensity = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pdsch.ptrs.frequencyDensity", []), ...
    sixgr.util.structGet(cfg, "phy.ptrs.frequencyDensity", []), ...
    sixgr.util.structGet(cfg, "pdsch6gr.PTRSFrequencyDensity", []), ...
    2);
reOffset = string(sixgr.util.structGet(cfg, "phy.pdsch.ptrs.reOffset", ...
    sixgr.util.structGet(cfg, "phy.ptrs.reOffset", ...
    sixgr.util.structGet(cfg, "pdsch6gr.PTRSREOffset", "00"))));
portSet = sixgr.util.structGet(cfg, "phy.pdsch.ptrs.portSet", ...
    sixgr.util.structGet(cfg, "phy.ptrs.portSet", []));

try
    if isprop(ptrs, "TimeDensity")
        ptrs.TimeDensity = max(1, round(double(timeDensity)));
    end
    if isprop(ptrs, "FrequencyDensity")
        ptrs.FrequencyDensity = max(1, round(double(freqDensity)));
    end
    if isprop(ptrs, "REOffset")
        ptrs.REOffset = char(reOffset);
    end
    if isprop(ptrs, "PTRSPortSet")
        if isempty(portSet)
            ptrs.PTRSPortSet = 0;
        else
            ptrs.PTRSPortSet = max(0, round(double(portSet(:).')));
        end
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
    symAlloc = [0 14];
end
startSym = max(0, round(double(symAlloc(1))));
typeAPos = 2;
try
    if isprop(pdsch, "DMRS") && isprop(pdsch.DMRS, "DMRSTypeAPosition")
        typeAPos = round(double(pdsch.DMRS.DMRSTypeAPosition));
    end
catch
end
typeAPos = max(2, min(3, round(double(typeAPos))));

if mapType == "A" && startSym > typeAPos
    if logical(explicitMapType) || logical(fixedReferenceMode)
        error("sixgr:phy:grid:allocREsPDSCH:InvalidTypeADMRSSymbol", ...
            "PDSCH MappingType A starts at symbol %d after configured DMRSTypeAPosition=%d. Configure DMRSTypeAPosition=3 when legal, choose MappingType B, or move PDSCH earlier.", ...
            round(double(startSym)), round(double(typeAPos)));
    end
    mapType = "B";
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

function pdsch = localReserveCSIRSResources(carrier, pdsch, cfg)
if ~(isstruct(cfg) && logical(sixgr.util.structGet(cfg, "phy.csirs.enable", false)))
    return;
end
try
    [~, csirsSym, csirsInfo, csirs] = sixgr.phy.refsig.csirs(carrier, cfg);
catch ME
    error("sixgr:phy:grid:allocREsPDSCH:CSIRSReservationFailed", ...
        "CSI-RS is enabled but runtime CSI-RS resources could not be generated for PDSCH reservation: %s", ME.message);
end
if isempty(csirsSym) || ~isstruct(csirsInfo) || ~logical(sixgr.util.structGet(csirsInfo, "Enabled", false))
    return;
end
try
    res = nrPDSCHReservedConfig;
    rbOffset = double(csirs.RBOffset);
    numRB = double(csirs.NumRB);
    res.PRBSet = rbOffset:(rbOffset + max(0, numRB - 1));
    res.SymbolSet = double(csirs.SymbolLocations(:).');
    period = sixgr.util.structGet(cfg, "phy.csirs.pdschReservationPeriod", []);
    if ~isempty(period)
        res.Period = double(period);
    end

    existing = pdsch.ReservedPRB;
    if isempty(existing)
        pdsch.ReservedPRB = {res};
    elseif iscell(existing)
        pdsch.ReservedPRB = [existing(:).' {res}];
    else
        pdsch.ReservedPRB = {existing, res};
    end
catch ME
    error("sixgr:phy:grid:allocREsPDSCH:CSIRSReservationApplyFailed", ...
        "CSI-RS runtime resources were generated but could not be reserved in the PDSCH allocation: %s", ME.message);
end
end
