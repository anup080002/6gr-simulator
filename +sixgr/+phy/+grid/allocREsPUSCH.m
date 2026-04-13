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
%     "TransmissionScheme"- "nonCodeBook" or "codebook"
%     "NumAntennaPorts"  - UL codebook antenna ports
%     "TPMI"             - UL codebook TPMI/PMI

opts.IndexBase = '1based';
opts.PRBSet = [];
opts.SymbolAllocation = [];
opts.Modulation = '';
opts.NumLayers = [];
opts.RNTI = [];
opts.TransformPrecoding = [];
opts.TransmissionScheme = '';
opts.NumAntennaPorts = [];
opts.TPMI = [];

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
        case 'transmissionscheme'
            opts.TransmissionScheme = char(string(val));
        case {'numantennaports','numports','nports'}
            opts.NumAntennaPorts = val;
        case {'tpmi','pmi'}
            opts.TPMI = val;
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
info.TransmissionScheme = char(localObjectValue(pusch, 'TransmissionScheme', ''));
info.NumAntennaPorts = double(localObjectValue(pusch, 'NumAntennaPorts', NaN));
info.TPMI = double(localObjectValue(pusch, 'TPMI', NaN));
info.CodebookType = char(string(localObjectValue(pusch, 'CodebookType', '')));
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
tpmi = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, 'phy.pusch.tpmi', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.TPMI', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.pmi', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.PMI', []));
transmissionScheme = char(string(sixgr.util.structGet(cfg, 'phy.pusch.transmissionScheme', ...
    sixgr.util.structGet(cfg, 'phy.pusch.TransmissionScheme', ''))));
[numAntennaPorts, numAntennaPortsExplicit] = localResolvePUSCHAntennaPorts(cfg);
codebookType = char(string(sixgr.util.structGet(cfg, 'phy.pusch.codebookType', ...
    sixgr.util.structGet(cfg, 'phy.pusch.CodebookType', ''))));
mapType = upper(char(string(sixgr.util.structGet(cfg, 'phy.pusch.mappingType', ...
    sixgr.util.structGet(cfg, 'phy.pusch.MappingType', 'A')))));

% Apply overrides
if ~isempty(opts.Modulation), mod = char(opts.Modulation); end
if ~isempty(opts.NumLayers), nl = double(opts.NumLayers); end
if ~isempty(opts.RNTI), rnti = double(opts.RNTI); end
if ~isempty(opts.PRBSet), prb = opts.PRBSet; end
if ~isempty(opts.SymbolAllocation), symAlloc = opts.SymbolAllocation; end
if ~isempty(opts.TransformPrecoding), tp = logical(opts.TransformPrecoding); end
if ~isempty(opts.TPMI), tpmi = localFirstFiniteScalar(opts.TPMI); end
if ~isempty(opts.TransmissionScheme), transmissionScheme = char(string(opts.TransmissionScheme)); end
if ~isempty(opts.NumAntennaPorts)
    numAntennaPorts = localFirstFiniteScalar(opts.NumAntennaPorts);
    numAntennaPortsExplicit = true;
end
if ~numAntennaPortsExplicit && (~isfinite(numAntennaPorts) || numAntennaPorts < nl)
    numAntennaPorts = nl;
end

pusch.Modulation = mod;
pusch.NumLayers = nl;
pusch.RNTI = rnti;
pusch.TransformPrecoding = tp;

if isempty(strtrim(transmissionScheme)) && ~tp && isfinite(tpmi)
    transmissionScheme = 'codebook';
end
if ~isempty(strtrim(transmissionScheme))
    try
        pusch.TransmissionScheme = char(transmissionScheme);
    catch ME
        error("sixgr:phy:grid:allocREsPUSCH:BadTransmissionScheme", ...
            "Invalid phy.pusch.transmissionScheme '%s': %s", char(transmissionScheme), ME.message);
    end
end
if isfinite(numAntennaPorts)
    try
        pusch.NumAntennaPorts = localNormalizePUSCHAntennaPorts(numAntennaPorts, nl, numAntennaPortsExplicit);
    catch ME
        error("sixgr:phy:grid:allocREsPUSCH:BadNumAntennaPorts", ...
            "Invalid phy.pusch.NumAntennaPorts/numPorts value: %s", ME.message);
    end
end
if strcmpi(char(string(localObjectValue(pusch, 'TransmissionScheme', ''))), 'codebook')
    if isfinite(tpmi)
        try
            pusch.TPMI = round(double(tpmi));
        catch ME
            error("sixgr:phy:grid:allocREsPUSCH:BadTPMI", ...
                "Invalid phy.pusch.PMI/TPMI value %g: %s", double(tpmi), ME.message);
        end
    end
    if ~isempty(strtrim(codebookType))
        try
            pusch.CodebookType = char(codebookType);
        catch ME
            error("sixgr:phy:grid:allocREsPUSCH:BadCodebookType", ...
                "Invalid phy.pusch.CodebookType '%s': %s", char(codebookType), ME.message);
        end
    end
end

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

function value = localObjectValue(obj, propName, defaultValue)
value = defaultValue;
if isempty(obj)
    return;
end
try
    raw = obj.(propName);
catch
    return;
end
if isempty(raw)
    return;
end
value = raw;
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw) || ~isnumeric(raw)
        continue;
    end
    raw = double(raw(:));
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = raw(1);
        return;
    end
end
end

function [value, explicit] = localResolvePUSCHAntennaPorts(cfg)
value = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, 'phy.pusch.numAntennaPorts', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.NumAntennaPorts', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.numPorts', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.nPorts', []));
explicit = isfinite(value);
if explicit
    return;
end

% PUSCH NumAntennaPorts is a UL codebook-port field, not the gNB-wide
% downlink antenna count. Fall back to UL-local port/layer evidence only.
value = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.nPorts', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.numPorts', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.numLayers', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.nLayers', []), ...
    sixgr.util.structGet(cfg, 'scenario.ue.nTxAnt', []));
end

function value = localNormalizePUSCHAntennaPorts(value, numLayers, explicit)
allowed = [1 2 4];
value = max(1, round(double(value)));
minPorts = max(1, round(double(numLayers)));
if explicit && ~any(value == allowed)
    error("explicit NumAntennaPorts=%g is invalid for nrPUSCHConfig; expected one of [1 2 4].", value);
end
value = max(value, minPorts);
idx = find(allowed >= value, 1, 'first');
if isempty(idx)
    if explicit
        error("explicit NumAntennaPorts=%g cannot support NumLayers=%g within nrPUSCHConfig allowed ports [1 2 4].", value, minPorts);
    end
    idx = numel(allowed);
end
value = allowed(idx);
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
