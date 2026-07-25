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
ip.addParameter("TargetCodeRate", NaN, ...
    @(x) isempty(x) || (isnumeric(x) && isvector(x)));
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
numLayers = localRequiredInteger( ...
    localObjectValue(cfgObj, "NumLayers", NaN), "NumLayers", 1, 8);
expectedCodewords = 1 + double(numLayers > 4);
rawCodewords = localObjectValue(cfgObj, "NumCodewords", []);
if isempty(rawCodewords)
    nCodewords = expectedCodewords;
else
    nCodewords = localRequiredInteger( ...
        rawCodewords, "NumCodewords", 1, 2);
end
if nCodewords ~= expectedCodewords
    error("sixgr:phy:resource:CodewordLayerMismatch", ...
        "%s rank %d requires NumCodewords=%d, not %d.", ...
        char(channel), numLayers, expectedCodewords, nCodewords);
end
prbSet = localObjectValue(cfgObj, "PRBSet", []);
nPRB = double(numel(prbSet));
if ~(isfinite(nPRB) && nPRB > 0) || any(~isfinite(double(prbSet(:)))) ...
        || any(double(prbSet(:)) ~= fix(double(prbSet(:)))) ...
        || any(double(prbSet(:)) < 0) ...
        || numel(unique(double(prbSet(:)))) ~= nPRB
    error("sixgr:phy:resource:MissingPRBSet", ...
        "%s exact resource accounting requires a nonempty unique nonnegative-integer PRBSet.", ...
        char(channel));
end
qmPerCodeword = localModulationOrderVector(modulation, nCodewords);
qm = qmPerCodeword(1);
layerCountPerCodeword = localLayerCountPerCodeword(numLayers, nCodewords);

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

gBitsPerCodeword = localFirstFiniteNonnegativeVector( ...
    sixgr.util.structGet(idxInfo, "G", NaN), ...
    sixgr.util.structGet(opt.AllocationInfo, "GPerCodeword", NaN), ...
    sixgr.util.structGet(opt.AllocationInfo, "CodedBitCountGPerCodeword", NaN), ...
    sixgr.util.structGet(opt.AllocationInfo, "RateMatchedBitCountPerCodeword", NaN));
if isempty(gBitsPerCodeword)
    gBitsScalar = localFirstFiniteNonnegative([ ...
        sixgr.util.structGet(idxInfo, "G", NaN), ...
        sixgr.util.structGet(opt.AllocationInfo, "G", NaN), ...
        sixgr.util.structGet(opt.AllocationInfo, "CodedBitCountG", NaN)]);
    if isfinite(gBitsScalar)
        gBitsPerCodeword = double(gBitsScalar);
    end
end

if ~(isfinite(layerDataRE) && layerDataRE >= 0)
    error("sixgr:phy:resource:MissingLayerDataRE", ...
        "%s resource accounting could not resolve layer-domain data RE from nr%sIndices evidence.", ...
        char(channel), char(channel));
end
if layerDataRE ~= fix(layerDataRE)
    error("sixgr:phy:resource:NonintegerLayerDataRE", ...
        "%s exact resource accounting requires an integer layer-domain data RE count.", ...
        char(channel));
end
if ~isempty(opt.ChannelIndices) && size(opt.ChannelIndices, 1) ~= layerDataRE
    error("sixgr:phy:resource:LayerDataREIndexMismatch", ...
        "%s index rows (%d) disagree with the reported layer-domain data RE count (%d).", ...
        char(channel), size(opt.ChannelIndices, 1), layerDataRE);
end
if ~(isfinite(nrePerPRB) && nrePerPRB >= 0 && nrePerPRB == fix(nrePerPRB))
    error("sixgr:phy:resource:MissingNREPerPRB", ...
        "%s resource accounting could not resolve an integer NREPerPRB from nr%sIndices evidence.", ...
        char(channel), char(channel));
end
if isempty(gBitsPerCodeword) || ~all(isfinite(gBitsPerCodeword) ...
        & gBitsPerCodeword >= 0 & gBitsPerCodeword == fix(gBitsPerCodeword))
    error("sixgr:phy:resource:MissingG", ...
        "%s resource accounting could not resolve integer coded-bit count G from nr%sIndices evidence.", ...
        char(channel), char(channel));
end
gBitsPerCodeword = double(gBitsPerCodeword(:).');
if numel(gBitsPerCodeword) ~= nCodewords
    error("sixgr:phy:resource:MissingCodewordSpecificG", ...
        "%s exact accounting requires one G value per codeword.", char(channel));
end
gBits = sum(gBitsPerCodeword);
expectedGPerCodeword = double(layerDataRE) .* ...
    double(qmPerCodeword(:).') .* double(layerCountPerCodeword(:).');
if any(gBitsPerCodeword ~= expectedGPerCodeword)
    error("sixgr:phy:resource:GIndexMapMismatch", ...
        ["%s reported per-codeword G=%s disagrees with exact data-index " ...
        "accounting %s."], char(channel), mat2str(gBitsPerCodeword), ...
        mat2str(expectedGPerCodeword));
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
acct.Modulation = char(localModulationText(modulation));
acct.Qm = double(qm);
acct.QmPerCodeword = double(qmPerCodeword);
acct.NumLayers = double(numLayers);
acct.NumCodewords = double(nCodewords);
acct.LayerCountPerCodeword = double(layerCountPerCodeword);
acct.PRBSet = double(prbSet(:).');
acct.PRBCount = double(nPRB);
acct.SymbolAllocation = double(localObjectValue(cfgObj, "SymbolAllocation", []));
acct.LayerDataRE = double(layerDataRE);
acct.PortMappedRE = double(numel(dataLin));
acct.ModulationSymbolCount = double(layerDataRE) * double(numLayers);
acct.CodedBitCountG = double(gBits);
acct.CodedBitCountGPerCodeword = double(gBitsPerCodeword);
acct.GPerCodeword = double(gBitsPerCodeword);
acct.DMRSRE = double(numel(unique(dmrsBase)));
acct.PTRSRE = double(numel(unique(ptrsBase)));
acct.ReservedRE = double(numel(unique(reservedBase)));
acct.DMRSLinearRE = double(numel(dmrsLin));
acct.PTRSLinearRE = double(numel(ptrsLin));
acct.ReservedLinearRE = double(numel(reservedLin));
acct.NREPerPRBForTBS = double(nrePerPRB);
acct.GFromLayerREPerCodeword = expectedGPerCodeword;
acct.GFromLayerRE = sum(acct.GFromLayerREPerCodeword);
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
    "Modulation", char(localModulationText(modulation)), ...
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

function value = localRequiredInteger(raw, name, minimum, maximum)
try
    raw = double(raw);
catch
    error("sixgr:phy:resource:BadInteger", ...
        "%s must be a finite integer scalar.", char(string(name)));
end
if ~(isscalar(raw) && isfinite(raw) && raw == fix(raw) ...
        && raw >= minimum && raw <= maximum)
    error("sixgr:phy:resource:BadInteger", ...
        "%s must be an integer in [%d,%d].", ...
        char(string(name)), minimum, maximum);
end
value = double(raw);
end

function value = localFirstFiniteNonnegative(values)
value = NaN;
values = double(values(:));
idx = find(isfinite(values) & values >= 0, 1, "first");
if ~isempty(idx)
    value = values(idx);
end
end

function value = localFirstFiniteNonnegativeVector(varargin)
value = [];
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw) || ~(isnumeric(raw) || islogical(raw))
        continue;
    end
    raw = double(raw(:).');
    if ~isempty(raw) && all(isfinite(raw) & raw >= 0)
        value = raw;
        return;
    end
end
end

function qm = localModulationOrderVector(modulation, nCodewords)
tokens = string(modulation);
tokens = tokens(:).';
if isempty(tokens) || any(strlength(strtrim(tokens)) == 0)
    error("sixgr:phy:resource:MissingCodewordSpecificModulation", ...
        "Exact resource accounting requires one nonempty modulation token per codeword.");
end
if numel(tokens) ~= nCodewords
    error("sixgr:phy:resource:MissingCodewordSpecificModulation", ...
        "Expected exactly NumCodewords=%d modulation tokens; received %d.", ...
        nCodewords, numel(tokens));
end
qm = zeros(1, nCodewords);
for i = 1:nCodewords
    qm(i) = localModulationOrder(tokens(i));
end
end

function counts = localLayerCountPerCodeword(numLayers, numCodewords)
numLayers = localRequiredInteger(numLayers, "NumLayers", 1, 8);
numCodewords = localRequiredInteger(numCodewords, "NumCodewords", 1, 2);
expectedCodewords = 1 + double(numLayers > 4);
if numCodewords ~= expectedCodewords
    error("sixgr:phy:resource:BadCodewordLayerMapping", ...
        "Rank %d requires NumCodewords=%d, not %d.", ...
        numLayers, expectedCodewords, numCodewords);
end
if numCodewords == 1
    counts = double(numLayers);
    return;
end
switch numLayers
    case 5
        counts = [2 3];
    case 6
        counts = [3 3];
    case 7
        counts = [3 4];
    case 8
        counts = [4 4];
    otherwise
        error("sixgr:phy:resource:BadCodewordLayerMapping", ...
            "PDSCH two-codeword resource accounting supports ranks 5-8. Got NumLayers=%d NumCodewords=%d.", ...
            numLayers, numCodewords);
end
if numel(counts) ~= numCodewords
    error("sixgr:phy:resource:BadCodewordCount", ...
        "PDSCH rank-%d requires %d codeword layer counts, but NumCodewords=%d.", ...
        numLayers, numel(counts), numCodewords);
end
end

function text = localModulationText(modulation)
if iscell(modulation)
    tokens = string(modulation);
else
    tokens = string(modulation);
end
tokens = tokens(:).';
tokens = tokens(strlength(strtrim(tokens)) > 0);
if isempty(tokens)
    text = "";
else
    text = strjoin(tokens, "|");
end
end

function qm = localModulationOrder(modulation)
tokens = string(modulation);
tokens = tokens(:);
if numel(tokens) ~= 1 || strlength(strtrim(tokens)) == 0
    error("sixgr:phy:resource:BadModulation", ...
        "Each codeword requires one nonempty modulation token.");
end
token = tokens(1);
token = upper(strrep(strtrim(char(token)), " ", ""));
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
    otherwise
        error("sixgr:phy:resource:UnsupportedNRModulation", ...
            "Unsupported NR modulation for resource accounting: '%s'.", ...
            char(string(modulation)));
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
symAlloc = double(localObjectValue(pdsch, "SymbolAllocation", []));
if numel(symAlloc) ~= 2 || any(~isfinite(symAlloc)) ...
        || any(symAlloc ~= fix(symAlloc)) || symAlloc(1) < 0 ...
        || symAlloc(2) < 1 || sum(symAlloc) > nSym
    error("sixgr:phy:resource:BadSymbolAllocation", ...
        "Reserved-resource accounting requires a valid explicit [start length] allocation.");
end
allocSyms = symAlloc(1):(symAlloc(1) + symAlloc(2) - 1);
prbSet = double(localObjectValue(pdsch, "PRBSet", []));
layers = localRequiredInteger( ...
    localObjectValue(pdsch, "NumLayers", NaN), "NumLayers", 1, 8);
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
