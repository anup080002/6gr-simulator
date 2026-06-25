function acct = computeResourceAccounting(channel, carrier, cfgObj, varargin)
%COMPUTERESOURCEACCOUNTING Exact PDSCH/PUSCH RE, G, and TBS dimensions.
%
%   ACCT = sixgr.phy.resource.computeResourceAccounting(CHANNEL,CARRIER,CFGOBJ,...)
%   centralizes the dimensional contract returned by nrPDSCHIndices and
%   nrPUSCHIndices. Gd is treated as the layer-domain data RE count for TBS
%   and rate matching; port-index cells are reported separately.

ip = inputParser;
ip.addParameter("ChannelIndices", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("AllocationInfo", struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter("IndexBase", "1based", @(x) ischar(x) || isstring(x));
ip.addParameter("DMRSIndices", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("PTRSIndices", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("ReservedIndices", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("TargetCodeRate", NaN, @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("XOverhead", NaN, @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;

channel = upper(string(channel));
if channel ~= "PDSCH" && channel ~= "PUSCH"
    error("sixgr:phy:resource:BadChannel", ...
        "Resource accounting channel must be PDSCH or PUSCH, not '%s'.", char(channel));
end

idxInfo = localIndicesInfo(opt.AllocationInfo, channel);
modulation = localObjectValue(cfgObj, "Modulation", "");
numLayers = localPositiveInteger(localObjectValue(cfgObj, "NumLayers", NaN), 1);
prbSet = localObjectValue(cfgObj, "PRBSet", []);
nPRB = double(numel(prbSet));
if ~(isfinite(nPRB) && nPRB > 0)
    nPRB = localPositiveInteger(sixgr.util.structGet(opt.AllocationInfo, "PRBCount", NaN), 1);
end
qm = localModulationOrder(modulation);

layerDataRE = localFirstFiniteNonnegative([ ...
    sixgr.util.structGet(idxInfo, "Gd", NaN), ...
    sixgr.util.structGet(idxInfo, "NRE", NaN), ...
    sixgr.util.structGet(opt.AllocationInfo, "LayerDataRE", NaN), ...
    sixgr.util.structGet(opt.AllocationInfo, "Gd", NaN)]);
if ~isfinite(layerDataRE)
    dataIdx = opt.ChannelIndices;
    if ~isempty(dataIdx)
        layerDataRE = double(size(dataIdx, 1));
    end
end

nrePerPRB = localFirstFiniteNonnegative([ ...
    sixgr.util.structGet(idxInfo, "NREPerPRB", NaN), ...
    sixgr.util.structGet(opt.AllocationInfo, "NREPerPRB", NaN), ...
    sixgr.util.structGet(opt.AllocationInfo, "NREPerPRBForTBS", NaN)]);
if ~isfinite(nrePerPRB) && isfinite(layerDataRE) && layerDataRE >= 0 && nPRB > 0
    quotient = double(layerDataRE) / double(nPRB);
    if abs(quotient - round(quotient)) <= 1e-9
        nrePerPRB = round(quotient);
    else
        nrePerPRB = floor(quotient);
    end
end

gBits = localFirstFiniteNonnegative([ ...
    sixgr.util.structGet(idxInfo, "G", NaN), ...
    sixgr.util.structGet(opt.AllocationInfo, "G", NaN), ...
    sixgr.util.structGet(opt.AllocationInfo, "CodedBitCountG", NaN)]);
if ~isfinite(gBits) && isfinite(layerDataRE) && layerDataRE >= 0
    gBits = double(layerDataRE) * double(qm) * double(numLayers);
end

if ~(isfinite(layerDataRE) && layerDataRE >= 0)
    error("sixgr:phy:resource:MissingLayerDataRE", ...
        "%s resource accounting could not resolve layer-domain data RE from nr%sIndices evidence.", ...
        char(channel), char(channel));
end
if ~(isfinite(nrePerPRB) && nrePerPRB >= 0)
    error("sixgr:phy:resource:MissingNREPerPRB", ...
        "%s resource accounting could not resolve NREPerPRB from nr%sIndices evidence.", ...
        char(channel), char(channel));
end
if ~(isfinite(gBits) && gBits >= 0)
    error("sixgr:phy:resource:MissingG", ...
        "%s resource accounting could not resolve coded-bit count G from nr%sIndices evidence.", ...
        char(channel), char(channel));
end

dmrsIdx = opt.DMRSIndices;
if isempty(dmrsIdx) && localCanComputeReferenceIndices(cfgObj)
    dmrsIdx = localReferenceIndices(channel, "DMRS", carrier, cfgObj, opt.IndexBase);
end
ptrsIdx = opt.PTRSIndices;
if isempty(ptrsIdx) && localCanComputeReferenceIndices(cfgObj) && localPTRSEnabled(cfgObj)
    ptrsIdx = localReferenceIndices(channel, "PTRS", carrier, cfgObj, opt.IndexBase);
end
reservedIdx = opt.ReservedIndices;
if isempty(reservedIdx) && channel == "PDSCH" && localCanComputeReferenceIndices(cfgObj)
    reservedIdx = localReservedIndices(carrier, cfgObj, opt.IndexBase);
end

[nSC, nSym] = localCarrierGridShape(carrier);
dataLin = localLinearIndices(opt.ChannelIndices, opt.IndexBase);
dmrsLin = localLinearIndices(dmrsIdx, opt.IndexBase);
ptrsLin = localLinearIndices(ptrsIdx, opt.IndexBase);
reservedLin = localLinearIndices(reservedIdx, opt.IndexBase);
dataBase = localBaseIndices(dataLin, nSC, nSym);
dmrsBase = localBaseIndices(dmrsLin, nSC, nSym);
ptrsBase = localBaseIndices(ptrsLin, nSC, nSym);
reservedBase = localBaseIndices(reservedLin, nSC, nSym);

dupData = max(0, numel(dataLin) - numel(unique(dataLin)));
dupDMRS = max(0, numel(dmrsLin) - numel(unique(dmrsLin)));
dupPTRS = max(0, numel(ptrsLin) - numel(unique(ptrsLin)));
overlaps = struct( ...
    "DataDMRS", double(numel(intersect(dataBase, dmrsBase))), ...
    "DataPTRS", double(numel(intersect(dataBase, ptrsBase))), ...
    "DataReserved", double(numel(intersect(dataBase, reservedBase))), ...
    "DMRSPTRS", double(numel(intersect(dmrsBase, ptrsBase))), ...
    "DMRSReserved", double(numel(intersect(dmrsBase, reservedBase))), ...
    "PTRSReserved", double(numel(intersect(ptrsBase, reservedBase))));
overlapTotal = localStructSum(overlaps);

acct = struct();
acct.Channel = char(channel);
acct.IndexBase = char(string(opt.IndexBase));
acct.Modulation = char(string(modulation));
acct.Qm = double(qm);
acct.NumLayers = double(numLayers);
acct.PRBSet = double(prbSet(:).');
acct.PRBCount = double(nPRB);
acct.SymbolAllocation = double(localObjectValue(cfgObj, "SymbolAllocation", []));
acct.LayerDataRE = double(layerDataRE);
acct.PortMappedRE = double(numel(dataLin));
acct.ModulationSymbolCount = double(layerDataRE) * double(numLayers);
acct.CodedBitCountG = double(gBits);
acct.DMRSRE = double(numel(unique(dmrsBase)));
acct.PTRSRE = double(numel(unique(ptrsBase)));
acct.ReservedRE = double(numel(unique(reservedBase)));
acct.DMRSLinearRE = double(numel(dmrsLin));
acct.PTRSLinearRE = double(numel(ptrsLin));
acct.ReservedLinearRE = double(numel(reservedLin));
acct.NREPerPRBForTBS = double(nrePerPRB);
acct.GFromLayerRE = double(layerDataRE) * double(qm) * double(numLayers);
acct.GMatchesLayerRE = abs(double(gBits) - acct.GFromLayerRE) <= 1e-9;
acct.DuplicateDataIndices = double(dupData);
acct.DuplicateDMRSIndices = double(dupDMRS);
acct.DuplicatePTRSIndices = double(dupPTRS);
acct.OverlapCounts = overlaps;
acct.OverlapCount = double(overlapTotal);
acct.DisjointMasks = overlapTotal == 0 && dupData == 0 && dupDMRS == 0 && dupPTRS == 0;
acct.Indices = struct( ...
    "DataLinear", dataLin, ...
    "DataBase", dataBase, ...
    "DMRSLinear", dmrsLin, ...
    "DMRSBase", dmrsBase, ...
    "PTRSLinear", ptrsLin, ...
    "PTRSBase", ptrsBase, ...
    "ReservedLinear", reservedLin, ...
    "ReservedBase", reservedBase);
acct.Masks = localMasks(nSC, nSym, dataBase, dmrsBase, ptrsBase, reservedBase);
acct.TBSInputs = struct( ...
    "Modulation", char(string(modulation)), ...
    "NumLayers", double(numLayers), ...
    "NPRB", double(nPRB), ...
    "NREPerPRB", double(nrePerPRB), ...
    "TargetCodeRate", double(opt.TargetCodeRate), ...
    "XOverhead", double(opt.XOverhead));
acct.Source = sprintf("nr%sIndices_Gd_G_NREPerPRB", char(channel));
end

function idxInfo = localIndicesInfo(info, channel)
idxInfo = struct();
if ~isstruct(info)
    return;
end
if isfield(info, "IndicesInfo")
    idxInfo = info.IndicesInfo;
elseif channel == "PUSCH" && isfield(info, "PUSCHIndicesInfo")
    idxInfo = info.PUSCHIndicesInfo;
elseif channel == "PDSCH" && isfield(info, "PDSCHIndicesInfo")
    idxInfo = info.PDSCHIndicesInfo;
else
    idxInfo = info;
end
end

function value = localObjectValue(obj, fieldName, defaultValue)
value = defaultValue;
if isempty(obj)
    return;
end
try
    value = obj.(fieldName);
catch
end
if isempty(value)
    value = defaultValue;
end
end

function value = localPositiveInteger(raw, defaultValue)
value = defaultValue;
try
    raw = double(raw);
catch
    return;
end
raw = raw(:);
raw = raw(isfinite(raw));
if isempty(raw)
    return;
end
value = max(1, round(raw(1)));
end

function value = localFirstFiniteNonnegative(values)
value = NaN;
values = double(values(:));
idx = find(isfinite(values) & values >= 0, 1, "first");
if ~isempty(idx)
    value = values(idx);
end
end

function qm = localModulationOrder(modulation)
token = upper(strrep(strtrim(char(string(modulation))), " ", ""));
switch token
    case {"PI/2-BPSK","PI2-BPSK","BPSK"}
        qm = 1;
    case "QPSK"
        qm = 2;
    case "16QAM"
        qm = 4;
    case "64QAM"
        qm = 6;
    case "256QAM"
        qm = 8;
    case "1024QAM"
        qm = 10;
    case "4096QAM"
        qm = 12;
    otherwise
        error("sixgr:phy:resource:BadModulation", ...
            "Unsupported modulation for resource accounting: '%s'.", char(string(modulation)));
end
end

function idx = localReferenceIndices(channel, refType, carrier, cfgObj, indexBase)
idx = [];
try
    if channel == "PDSCH" && refType == "DMRS"
        idx = nrPDSCHDMRSIndices(carrier, cfgObj, "IndexBase", indexBase);
    elseif channel == "PDSCH" && refType == "PTRS"
        idx = nrPDSCHPTRSIndices(carrier, cfgObj, "IndexBase", indexBase);
    elseif channel == "PUSCH" && refType == "DMRS"
        idx = nrPUSCHDMRSIndices(carrier, cfgObj, "IndexBase", indexBase);
    elseif channel == "PUSCH" && refType == "PTRS"
        idx = nrPUSCHPTRSIndices(carrier, cfgObj, "IndexBase", indexBase);
    end
catch ME
    if refType == "PTRS" && ~localPTRSEnabled(cfgObj)
        idx = [];
        return;
    end
    error("sixgr:phy:resource:ReferenceIndexFailure", ...
        "Failed to compute %s %s indices for resource accounting: %s", ...
        char(channel), char(refType), ME.message);
end
end

function tf = localPTRSEnabled(cfgObj)
tf = false;
try
    tf = logical(cfgObj.EnablePTRS);
catch
end
end

function tf = localCanComputeReferenceIndices(cfgObj)
tf = isobject(cfgObj);
end

function idx = localReservedIndices(carrier, pdsch, indexBase)
idx = [];
try
    reserved = pdsch.ReservedPRB;
catch
    reserved = {};
end
if isempty(reserved)
    return;
end
if ~iscell(reserved)
    reserved = {reserved};
end
[nSC, nSym] = localCarrierGridShape(carrier);
symAlloc = double(localObjectValue(pdsch, "SymbolAllocation", [0 nSym]));
if numel(symAlloc) < 2
    symAlloc = [0 nSym];
end
allocSyms = symAlloc(1):(symAlloc(1) + symAlloc(2) - 1);
prbSet = double(localObjectValue(pdsch, "PRBSet", []));
layers = localPositiveInteger(localObjectValue(pdsch, "NumLayers", 1), 1);
lin = [];
for i = 1:numel(reserved)
    r = reserved{i};
    if isempty(r)
        continue;
    end
    rPRB = double(localObjectValue(r, "PRBSet", []));
    rSym = double(localObjectValue(r, "SymbolSet", []));
    if isempty(rPRB) || isempty(rSym)
        continue;
    end
    usePRB = intersect(prbSet(:).', rPRB(:).');
    useSym = intersect(allocSyms(:).', rSym(:).');
    if isempty(usePRB) || isempty(useSym)
        continue;
    end
    for p = usePRB(:).'
        sc = double(p) * 12 + (1:12);
        sc = sc(sc >= 1 & sc <= nSC);
        for s = useSym(:).'
            sym1 = double(s) + 1;
            if sym1 < 1 || sym1 > nSym
                continue;
            end
            for layer = 1:layers
                lin = [lin; sub2ind([nSC nSym max(layers,1)], sc(:), repmat(sym1, numel(sc), 1), repmat(layer, numel(sc), 1))]; %#ok<AGROW>
            end
        end
    end
end
idx = lin;
if string(indexBase) == "0based"
    idx = idx - 1;
end
end

function [nSC, nSym] = localCarrierGridShape(carrier)
nSC = 0;
nSym = 14;
try
    nSC = double(carrier.NSizeGrid) * 12;
catch
end
try
    nSym = double(carrier.SymbolsPerSlot);
catch
end
if ~(isfinite(nSC) && nSC > 0)
    nSC = 1;
end
if ~(isfinite(nSym) && nSym > 0)
    nSym = 14;
end
nSC = round(nSC);
nSym = round(nSym);
end

function lin = localLinearIndices(idx, indexBase)
if isempty(idx)
    lin = zeros(0, 1);
    return;
end
lin = double(idx(:));
lin = lin(isfinite(lin));
lin = round(lin);
if string(indexBase) == "0based"
    lin = lin + 1;
end
lin = lin(lin > 0);
lin = lin(:);
end

function base = localBaseIndices(lin, nSC, nSym)
if isempty(lin)
    base = zeros(0, 1);
    return;
end
plane = max(1, double(nSC) * double(nSym));
base = mod(double(lin(:)) - 1, plane) + 1;
base = unique(round(base(:)));
end

function masks = localMasks(nSC, nSym, dataBase, dmrsBase, ptrsBase, reservedBase)
gridSize = max(1, double(nSC) * double(nSym));
masks = struct();
masks.Shape = [double(nSC), double(nSym)];
masks.Data = false(gridSize, 1);
masks.DMRS = false(gridSize, 1);
masks.PTRS = false(gridSize, 1);
masks.Reserved = false(gridSize, 1);
masks.Data(dataBase(dataBase >= 1 & dataBase <= gridSize)) = true;
masks.DMRS(dmrsBase(dmrsBase >= 1 & dmrsBase <= gridSize)) = true;
masks.PTRS(ptrsBase(ptrsBase >= 1 & ptrsBase <= gridSize)) = true;
masks.Reserved(reservedBase(reservedBase >= 1 & reservedBase <= gridSize)) = true;
end

function total = localStructSum(s)
total = 0;
names = fieldnames(s);
for i = 1:numel(names)
    total = total + double(s.(names{i}));
end
end
