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
mapType = "A";
prbSetCfg = [];
symAllocCfg = [0 14];

if isstruct(cfg)
    modStr = string(sixgr.util.structGet(cfg, "phy.pdsch.modulation", modStr));
    numLayers = double(sixgr.util.structGet(cfg, "phy.pdsch.numLayers", numLayers));
    rnti = double(sixgr.util.structGet(cfg, "phy.pdsch.RNTI", rnti));
    mapType = string(sixgr.util.structGet(cfg, "phy.pdsch.mappingType", mapType));
    prbSetCfg = sixgr.util.structGet(cfg, "phy.pdsch.prbSet", prbSetCfg);
    symAllocCfg = sixgr.util.structGet(cfg, "phy.pdsch.symbolAllocation", symAllocCfg);
end

% Apply overrides
if strlength(opts.Modulation) > 0, modStr = opts.Modulation; end
if ~isempty(opts.NumLayers), numLayers = double(opts.NumLayers); end
if ~isempty(opts.RNTI), rnti = double(opts.RNTI); end
if strlength(opts.MappingType) > 0, mapType = opts.MappingType; end
if ~isempty(opts.PRBSet), prbSetCfg = opts.PRBSet; end
if ~isempty(opts.SymbolAllocation), symAllocCfg = opts.SymbolAllocation; end

% Assign
pdsch.Modulation = char(modStr);
pdsch.NumLayers = numLayers;
pdsch.RNTI = rnti;
pdsch.MappingType = char(mapType);

prbVec = localExpandPRBSet(prbSetCfg, carrier.NSizeGrid);
pdsch.PRBSet = prbVec;

pdsch.SymbolAllocation = double(symAllocCfg(:).');

% Optional NID (scrambling)
try
    if isprop(pdsch, "NID")
        pdsch.NID = carrier.NCellID;
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
