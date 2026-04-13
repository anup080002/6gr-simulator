function [puschInd, info, pusch] = allocREsPUSCH(carrier, cfgOrPusch, varargin)
%ALLOCRESPUSCH PUSCH RE allocation indices from config.
%
%   [ind,info,pusch] = sixgr.phy.grid.allocREsPUSCH(carrier,cfg) creates an
%   nrPUSCHConfig from cfg.phy.pusch and calls nrPUSCHIndices.
%
%   [ind,info,pusch] = sixgr.phy.grid.allocREsPUSCH(carrier,puschCfg) uses
%   the provided nrPUSCHConfig.
%
%   Name-Value overrides (all optional):
%     "IndexBase"        - "1based" (default) or "0based"
%     "PRBSet"           - PRB set vector or [start end]
%     "SymbolAllocation" - [startSym nSym]
%     "Modulation"       - e.g., "QPSK", "16QAM"
%     "NumLayers"        - number of layers
%     "RNTI"             - UE RNTI
%     "TransformPrecoding"- true/false

opts.IndexBase = '1based';
opts.PRBSet = [];
opts.SymbolAllocation = [];
opts.Modulation = '';
opts.NumLayers = [];
opts.RNTI = [];
opts.TransformPrecoding = [];

for i = 1:2:numel(varargin)
    if i+1 > numel(varargin), break; end
    key = varargin{i};
    val = varargin{i+1};
    if ~(ischar(key) || isstring(key)), continue; end
    k = lower(char(key));
    switch k
        case 'indexbase'
            opts.IndexBase = char(val);
        case 'prbset'
            opts.PRBSet = val;
        case 'symbolallocation'
            opts.SymbolAllocation = val;
        case 'modulation'
            opts.Modulation = char(val);
        case 'numlayers'
            opts.NumLayers = val;
        case 'rnti'
            opts.RNTI = val;
        case 'transformprecoding'
            opts.TransformPrecoding = val;
    end
end

if isa(cfgOrPusch, 'nrPUSCHConfig')
    pusch = cfgOrPusch;
else
    pusch = localBuildFromCfg(carrier, cfgOrPusch, opts);
end

try
    [puschInd, puschIndInfo] = nrPUSCHIndices(carrier, pusch, 'IndexStyle', 'index', 'IndexBase', opts.IndexBase);
catch
    [puschInd, puschIndInfo] = nrPUSCHIndices(carrier, pusch, 'IndexBase', opts.IndexBase);
end

info = struct();
info.Channel = 'PUSCH';
info.IndexBase = opts.IndexBase;
info.Modulation = char(string(pusch.Modulation));
info.NumLayers = double(pusch.NumLayers);
info.RNTI = double(pusch.RNTI);
info.TransformPrecoding = logical(pusch.TransformPrecoding);
info.PRBSet = pusch.PRBSet;
info.SymbolAllocation = pusch.SymbolAllocation;
info.NRE = size(puschInd, 1);
info.PUSCHIndicesInfo = puschIndInfo;

end

function pusch = localBuildFromCfg(carrier, cfg, opts)
% Build nrPUSCHConfig with safe defaults.

pusch = nrPUSCHConfig;

% Basic PHY settings
mod = char(string(sixgr.util.structGet(cfg, 'phy.pusch.modulation', '16QAM')));
nl  = double(sixgr.util.structGet(cfg, 'phy.pusch.numLayers', 1));
rnti = double(sixgr.util.structGet(cfg, 'phy.pusch.RNTI', 1));
prb = sixgr.util.structGet(cfg, 'phy.pusch.prbSet', []);
symAlloc = sixgr.util.structGet(cfg, 'phy.pusch.symbolAllocation', [0 14]);
tp = logical(sixgr.util.structGet(cfg, 'phy.pusch.transformPrecoding', false));
mapType = upper(char(string(sixgr.util.structGet(cfg, 'phy.pusch.mappingType', ...
    sixgr.util.structGet(cfg, 'phy.pusch.MappingType', 'A')))));

% Apply overrides
if ~isempty(opts.Modulation), mod = char(opts.Modulation); end
if ~isempty(opts.NumLayers), nl = double(opts.NumLayers); end
if ~isempty(opts.RNTI), rnti = double(opts.RNTI); end
if ~isempty(opts.PRBSet), prb = opts.PRBSet; end
if ~isempty(opts.SymbolAllocation), symAlloc = opts.SymbolAllocation; end
if ~isempty(opts.TransformPrecoding), tp = logical(opts.TransformPrecoding); end

pusch.Modulation = mod;
pusch.NumLayers = nl;
pusch.RNTI = rnti;
pusch.TransformPrecoding = tp;

prbVec = localExpandPRBSet(prb, carrier.NSizeGrid);
pusch.PRBSet = prbVec;
pusch.SymbolAllocation = symAlloc;
pusch = localNormalizePUSCHMapping(pusch, mapType);

% Scrambling NID if available
try
    if isprop(pusch, 'NID')
        pusch.NID = carrier.NCellID;
    end
catch
end

% DMRS ports to match layers (avoid default mismatch)
try
    pusch.DMRS.DMRSPortSet = 0:(pusch.NumLayers-1);
catch
end

end

function pusch = localNormalizePUSCHMapping(pusch, mapType)
if nargin < 2 || strlength(string(mapType)) == 0
    mapType = "A";
end

symAlloc = [0 14];
try
    if isprop(pusch, "SymbolAllocation") && ~isempty(pusch.SymbolAllocation)
        symAlloc = double(pusch.SymbolAllocation(:).');
    end
catch
end
startSym = 0;
if ~isempty(symAlloc)
    startSym = max(0, round(symAlloc(1)));
end

mapType = upper(char(string(mapType)));
if startSym > 3 && strcmp(mapType, "A")
    mapType = "B";
end

try
    if isprop(pusch, "MappingType")
        pusch.MappingType = char(mapType);
    end
catch
end
end

function prbVec = localExpandPRBSet(prb, nSizeGrid)
% Expand PRB set inputs.
if isempty(prb)
    prbVec = 0:(nSizeGrid-1);
    return;
end
if isnumeric(prb)
    prb = double(prb(:).');
    if numel(prb) == 2 && prb(2) >= prb(1)
        prbVec = prb(1):prb(2);
        return;
    end
    prbVec = prb;
    return;
end

% Fallback: default full-band
prbVec = 0:(nSizeGrid-1);
end
