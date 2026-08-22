function [candidates, info] = pmiCodebookCandidates(cfg, nLayers, numTxPorts, varargin)
%PMICODEBOOKCANDIDATES Build deterministic wideband PMI/codebook candidates.
%
%   [CANDIDATES,INFO] = sixgr.phy.dl.pmiCodebookCandidates(CFG, NLAYERS, NTX)
%   returns a struct array of wideband precoder candidates for the
%   configured PMI mode. Each element contains:
%     - PMI        : 0-based candidate index
%     - BeamIndices: selected beam indices within the underlying codebook
%     - W          : normalized Ntx-by-Nlayers precoder
%     - PMIType    : "type1", "type2", "etype2", or "noncodebook"
%     - CodebookMode, NumPorts, NumLayers

ip = inputParser;
ip.addParameter("Mode", "", @(x) ischar(x) || isstring(x));
ip.addParameter("MaxCandidates", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
ip.parse(varargin{:});
opt = ip.Results;

nLayers = max(1, round(double(nLayers)));
numTxPorts = max(1, round(double(numTxPorts)));
mode = localResolveMode(cfg, opt.Mode);
strictMIMO = logical(sixgr.util.structGet(cfg,"mimo.strict", ...
    sixgr.util.structGet(cfg,"phy.mimo.strict",false)));
if strictMIMO
    [candidates,info] = localStrictCandidates(cfg,nLayers,numTxPorts,mode);
    return;
end
maxCandidates = localResolveMaxCandidates(mode, opt.MaxCandidates);
cacheKey = localCacheKey(cfg, nLayers, numTxPorts, mode, maxCandidates);
[cacheHit, candidates, info] = localPMICache("lookup", cacheKey);
if cacheHit
    info.CacheHit = true;
    info.CacheKey = string(cacheKey);
    return;
end

if mode == "noncodebook"
    W = eye(numTxPorts, nLayers);
    W = localNormalizeColumns(W);
    candidates = struct( ...
        "PMI", -1, ...
        "BeamIndices", 1:nLayers, ...
        "W", W, ...
        "PMIType", "noncodebook", ...
        "CodebookMode", "noncodebook", ...
        "NumPorts", numTxPorts, ...
        "NumLayers", nLayers, ...
        "NumBeams", numTxPorts, ...
        "StartBeamIndex", 0, ...
        "Stride", 1, ...
        "StrideIndex", 0, ...
        "PhaseVariantIndex", 0, ...
        "PhasePattern", ones(1, nLayers));
    info = struct( ...
        "Mode", "noncodebook", ...
        "PMIType", "noncodebook", ...
        "NumBeams", numTxPorts, ...
        "NumCandidates", 1, ...
        "NumPorts", numTxPorts, ...
        "NumLayers", nLayers, ...
        "StrideSet", 1, ...
        "NumPhaseVariants", 1, ...
        "CacheHit", false, ...
        "CacheKey", string(cacheKey));
    localPMICache("store", cacheKey, candidates, info);
    return;
end

beamCountCfg = round(double(sixgr.util.structGet(cfg, ...
    "phy.beamManagement.dlCodebookSize", ...
    sixgr.util.structGet(cfg, "phy.beamManagement.beamCount", numTxPorts))));
beamCountCfg = max(numTxPorts, beamCountCfg);

switch mode
    case "type1_su_mimo"
        numBeams = max(numTxPorts, beamCountCfg);
        strides = 1;
        phaseVariants = ones(1, nLayers);
    case "type2_mu_mimo"
        numBeams = max(beamCountCfg, 2 * numTxPorts);
        strides = unique(max(1, [1 2 round(numBeams / max(nLayers, 1))]));
        phaseVariants = localPhaseVariants(nLayers);
    case "etype2_candidate"
        numBeams = max(beamCountCfg, 4 * numTxPorts);
        strides = unique(max(1, [1 2 3 round(numBeams / max(nLayers, 1))]));
        phaseVariants = localPhaseVariants(nLayers);
    otherwise
        error("sixgr:phy:dl:PMICodebook:UnsupportedMode", ...
            "Unsupported PMI codebook mode '%s'.", mode);
end

B = localBuildRuntimeAwareCodebook(cfg, numTxPorts, numBeams, mode);
numBeams = size(B, 2);
candidateList = repmat(struct( ...
    "PMI", NaN, ...
    "BeamIndices", [], ...
    "W", zeros(numTxPorts, nLayers), ...
    "PMIType", char(localPMIType(mode)), ...
    "CodebookMode", char(mode), ...
    "NumPorts", numTxPorts, ...
    "NumLayers", nLayers, ...
    "NumBeams", numBeams, ...
    "StartBeamIndex", 0, ...
    "Stride", 1, ...
    "StrideIndex", 0, ...
    "PhaseVariantIndex", 0, ...
    "PhasePattern", ones(1, nLayers), ...
    "BasisBeamCount", 1, ...
    "CoefficientPattern", ""), 0, 1);
seen = containers.Map("KeyType", "char", "ValueType", "logical");
idx0 = 0;
isType2 = any(mode == ["type2_mu_mimo", "etype2_candidate"]);
type2BasisBeamCount = localResolveType2BasisBeamCount(cfg, mode, nLayers, numBeams);

for s = 1:numel(strides)
    stride = strides(s);
    for startIdx = 1:numBeams
        for pv = 1:size(phaseVariants, 1)
            if isType2
                [Wcand, beamIdx, coeffPattern] = localBuildType2CompositeCandidate( ...
                    B, startIdx, stride, nLayers, type2BasisBeamCount, phaseVariants(pv, :), mode);
            else
                beamIdx = 1 + mod((startIdx - 1) + (0:nLayers-1) * stride, numBeams);
                coeffPattern = "";
                if numel(unique(beamIdx)) ~= nLayers
                    continue;
                end
                Wbase = B(:, beamIdx);
                Wcand = Wbase .* phaseVariants(pv, :);
                Wcand = localNormalizeColumns(Wcand);
            end
            if rank(Wcand) < nLayers
                continue;
            end
            key = localCandidateKey(beamIdx, [phaseVariants(pv, :) localCoefficientTokenVector(coeffPattern)]);
            if isKey(seen, key)
                continue;
            end
            seen(key) = true;
            candidateList(end+1, 1) = struct( ... %#ok<AGROW>
                "PMI", double(idx0), ...
                "BeamIndices", double(beamIdx), ...
                "W", Wcand, ...
                "PMIType", char(localPMIType(mode)), ...
                "CodebookMode", char(mode), ...
                "NumPorts", double(numTxPorts), ...
                "NumLayers", double(nLayers), ...
                "NumBeams", double(numBeams), ...
                "StartBeamIndex", double(startIdx - 1), ...
                "Stride", double(stride), ...
                "StrideIndex", double(s - 1), ...
                "PhaseVariantIndex", double(pv - 1), ...
                "PhasePattern", phaseVariants(pv, :), ...
                "BasisBeamCount", double(localTernaryNumeric(isType2, type2BasisBeamCount, 1)), ...
                "CoefficientPattern", char(string(coeffPattern)));
            idx0 = idx0 + 1;
        end
    end
end

candidateList = localLimitCandidates(candidateList, maxCandidates);
candidateList = localRenumberPMI(candidateList);

candidates = candidateList;
info = struct( ...
    "Mode", char(mode), ...
    "PMIType", char(localPMIType(mode)), ...
    "NumBeams", double(numBeams), ...
    "NumCandidates", double(numel(candidates)), ...
    "NumPorts", double(numTxPorts), ...
    "NumLayers", double(nLayers), ...
    "StrideSet", double(strides(:).'), ...
    "NumPhaseVariants", double(size(phaseVariants, 1)), ...
    "Type2BasisBeamCount", double(localTernaryNumeric(isType2, type2BasisBeamCount, 1)), ...
    "CacheHit", false, ...
    "CacheKey", string(cacheKey));
localPMICache("store", cacheKey, candidates, info);
end

function [candidates,info] = localStrictCandidates(cfg,nLayers,numTxPorts,mode)
profileID = string(sixgr.util.structGet(cfg,"phy.mimo.profileID", ...
    sixgr.util.structGet(cfg,"mimo.profileID","")));
if strlength(profileID) == 0
    error("sixgr:mimo:UnsupportedProfile", ...
        "Strict PMI enumeration requires phy.mimo.profileID.");
end
request = struct( ...
    "ProfileID",profileID, ...
    "Direction","DL", ...
    "CodebookType",localStrictCodebookType(mode), ...
    "Ports",numTxPorts, ...
    "Panels",double(sixgr.util.structGet(cfg,"phy.mimo.panels",1)), ...
    "N1",double(sixgr.util.structGet(cfg,"phy.mimo.N1",NaN)), ...
    "N2",double(sixgr.util.structGet(cfg,"phy.mimo.N2",NaN)), ...
    "O1",double(sixgr.util.structGet(cfg,"phy.mimo.O1",NaN)), ...
    "O2",double(sixgr.util.structGet(cfg,"phy.mimo.O2",NaN)), ...
    "Rank",nLayers);
enumeration = sixgr.phy.mimo.CodebookEngine.enumerate(request);
n = size(enumeration.Matrices,3);
candidates = repmat(struct( ...
    "PMI",NaN,"BeamIndices",[],"W",[],"PMIType","", ...
    "CodebookMode","","NumPorts",numTxPorts,"NumLayers",nLayers, ...
    "NumBeams",n,"StartBeamIndex",0,"Stride",1, ...
    "StrideIndex",0,"PhaseVariantIndex",0,"PhasePattern",[], ...
    "BasisBeamCount",1,"CoefficientPattern","", ...
    "MatrixSHA256",""),n,1);
for index = 1:n
    candidates(index).PMI = double(enumeration.CandidateIndices(index));
    candidates(index).BeamIndices = double(enumeration.CandidateIndices(index));
    candidates(index).W = enumeration.Matrices(:,:,index);
    candidates(index).PMIType = char(string(enumeration.CodebookType));
    candidates(index).CodebookMode = char(mode);
    candidates(index).MatrixSHA256 = char(enumeration.MatrixSHA256(index));
end
info = struct( ...
    "Mode",char(mode), ...
    "PMIType",char(string(enumeration.CodebookType)), ...
    "NumBeams",double(n), ...
    "NumCandidates",double(n), ...
    "NumPorts",double(numTxPorts), ...
    "NumLayers",double(nLayers), ...
    "StrideSet",1, ...
    "NumPhaseVariants",1, ...
    "CacheHit",false, ...
    "CacheKey","", ...
    "GenericDFTApproximationUsed",false, ...
    "Specification",enumeration.Specification);
end

function codebookType = localStrictCodebookType(mode)
switch lower(string(mode))
    case "type1_su_mimo"
        codebookType = "typeI-SinglePanel";
    case "type2_mu_mimo"
        codebookType = "typeII";
    case "etype2_candidate"
        codebookType = "enhancedTypeII";
    otherwise
        error("sixgr:mimo:InvalidCodebookType", ...
            "Strict PDSCH does not support codebook mode %s.",mode);
end
end

function maxCandidates = localResolveMaxCandidates(mode, requestedMax)
maxCandidates = requestedMax;
if isempty(maxCandidates)
    switch string(mode)
        case "type1_su_mimo"
            maxCandidates = 64;
        case "type2_mu_mimo"
            maxCandidates = 96;
        otherwise
            maxCandidates = 160;
    end
end
maxCandidates = max(1, round(double(maxCandidates)));
end

function varargout = localPMICache(action, key, candidates, info)
persistent cache
if isempty(cache)
    cache = containers.Map("KeyType", "char", "ValueType", "any");
end
action = lower(string(action));
key = char(string(key));
switch action
    case "lookup"
        hit = isKey(cache, key);
        if hit
            item = cache(key);
            varargout = {true, item.Candidates, item.Info};
        else
            varargout = {false, struct([]), struct()};
        end
    case "store"
        if nargin < 4
            varargout = {};
            return;
        end
        if cache.Count >= 256 && ~isKey(cache, key)
            k = keys(cache);
            remove(cache, k{1});
        end
        cache(key) = struct("Candidates", candidates, "Info", info);
        varargout = {};
    otherwise
        error("sixgr:phy:dl:PMICodebook:BadCacheAction", ...
            "Unsupported PMI cache action '%s'.", action);
end
end

function key = localCacheKey(cfg, nLayers, numTxPorts, mode, maxCandidates)
snapshot = struct();
snapshot.Contract = "sixgr.phy.dl.pmiCodebookCandidates.cache.v1";
snapshot.Mode = char(string(mode));
snapshot.NumLayers = double(nLayers);
snapshot.NumTxPorts = double(numTxPorts);
snapshot.MaxCandidates = double(maxCandidates);
snapshot.BeamCount = double(sixgr.util.structGet(cfg, ...
    "phy.beamManagement.dlCodebookSize", ...
    sixgr.util.structGet(cfg, "phy.beamManagement.beamCount", numTxPorts)));
snapshot.CodebookType = char(string(sixgr.util.structGet(cfg, "phy.csi.codebookType", "")));
snapshot.Type2BasisBeamCount = double(sixgr.util.structGet(cfg, "phy.csi.type2BasisBeamCount", ...
    sixgr.util.structGet(cfg, "csi_acquisition_and_reporting.type2_basis_beam_count", NaN)));
snapshot.DualPolarizedType1 = logical(sixgr.util.structGet(cfg, "phy.csi.dualPolarizedType1", false));
snapshot.AntennaBSPolarization = char(string(sixgr.util.structGet(cfg, "antenna.bs.polarization", "")));
snapshot.AntennaArrayPolarization = char(string(sixgr.util.structGet(cfg, "antenna_and_array.polarization", "")));
snapshot.PhyBSArray = localSerializableValue(sixgr.util.structGet(cfg, "phy.bsArray", []));
snapshot.AntennaBSGeometry = char(string(sixgr.util.structGet(cfg, "antenna.bs.geometry", "")));
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
snapshot.RuntimeServingBSAntenna = localSerializableValue(sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct()));
key = char(sixgr.util.sha256Hex(jsonencode(snapshot)));
end

function value = localSerializableValue(value)
try
    jsonencode(value);
catch
    value = char(string(class(value)));
end
end

function mode = localResolveMode(cfg, overrideMode)
mode = string(overrideMode);
if strlength(strtrim(mode)) == 0
    mode = string(sixgr.util.structGet(cfg, "phy.csi.pmiCodebookMode", ""));
end
if strlength(strtrim(mode)) == 0
    codebookType = lower(string(sixgr.util.structGet(cfg, "phy.csi.codebookType", "type1")));
    switch codebookType
        case "type1"
            mode = "type1_su_mimo";
        case "type2"
            mode = "type2_mu_mimo";
        case "etype2"
            mode = "etype2_candidate";
        otherwise
            mode = "noncodebook";
    end
end
mode = lower(strtrim(mode));
end

function W = localNormalizeColumns(W)
for i = 1:size(W, 2)
    nrm = norm(W(:, i));
    if nrm > 0
        W(:, i) = W(:, i) ./ nrm;
    end
end
end

function phaseVariants = localPhaseVariants(nLayers)
phaseVariants = ones(1, nLayers);
if nLayers <= 1
    return;
end
phaseVariants = [ ...
    ones(1, nLayers); ...
    exp(1j * [0 pi/2 * ones(1, nLayers-1)]); ...
    exp(1j * [0 pi * ones(1, nLayers-1)]); ...
    exp(1j * (0:nLayers-1) * (pi/4))];
end

function B = localOversampledDFTCodebook(numTxPorts, numBeams)
n = (0:(numTxPorts-1)).';
m = 0:(numBeams-1);
B = exp(-1j * 2 * pi * (n * m) / max(numBeams, 1));
B = B ./ sqrt(max(numTxPorts, 1));
end

function B = localBuildRuntimeAwareCodebook(cfg, numTxPorts, numBeams, mode)
B = [];
if string(mode) == "type1_su_mimo"
    B = localBuildType1DualPolarizedCodebook(cfg, numTxPorts, numBeams, false);
elseif any(string(mode) == ["type2_mu_mimo", "etype2_candidate"])
    B = localBuildType1DualPolarizedCodebook(cfg, numTxPorts, numBeams, true);
end
if ~isempty(B)
    return;
end
arr = localResolveRuntimeBSAntenna(cfg, numTxPorts);
if isstruct(arr) && ~isempty(fieldnames(arr))
    [nRow, nCol] = localResolveArrayDims(arr, numTxPorts);
    if nRow > 1 || nCol > 1
        [nBeamsRow, nBeamsCol] = localResolveBeamGrid(nRow, nCol, numBeams);
        try
            B = sixgr.rf.AntennaArrayFactory.dftCodebookURA(nRow, nCol, nBeamsRow, nBeamsCol);
        catch
            B = [];
        end
    end
end
if isempty(B)
    B = localOversampledDFTCodebook(numTxPorts, numBeams);
end
if size(B, 1) > numTxPorts
    B = B(1:numTxPorts, :);
elseif size(B, 1) < numTxPorts
    B(end + 1:numTxPorts, :) = 0;
end
for i = 1:size(B, 2)
    nrm = norm(B(:, i));
    if nrm > 0
        B(:, i) = B(:, i) ./ nrm;
    end
end
end

function B = localBuildType1DualPolarizedCodebook(cfg, numTxPorts, numBeams, forceDualPol)
B = [];
if nargin < 4
    forceDualPol = false;
end
if mod(numTxPorts, 2) ~= 0
    return;
end
if ~forceDualPol && ~localWantsDualPolarizedType1(cfg)
    return;
end
numSpatialPorts = numTxPorts / 2;
arr = localResolveRuntimeBSAntenna(cfg, numTxPorts);
[nRow, nCol] = localResolveArrayDims(arr, numSpatialPorts);
if nRow * nCol ~= numSpatialPorts
    nRow = max(1, floor(sqrt(double(numSpatialPorts))));
    nCol = max(1, ceil(double(numSpatialPorts) / max(nRow, 1)));
    if nRow * nCol ~= numSpatialPorts
        nRow = 1;
        nCol = numSpatialPorts;
    end
end
[nBeamsRow, nBeamsCol] = localResolveBeamGrid(nRow, nCol, max(1, ceil(double(numBeams) / 4)));
try
    spatial = sixgr.rf.AntennaArrayFactory.dftCodebookURA(nRow, nCol, nBeamsRow, nBeamsCol);
catch
    spatial = localOversampledDFTCodebook(numSpatialPorts, max(1, ceil(double(numBeams) / 4)));
end
if size(spatial, 1) > numSpatialPorts
    spatial = spatial(1:numSpatialPorts, :);
elseif size(spatial, 1) < numSpatialPorts
    spatial(end+1:numSpatialPorts, :) = 0;
end
coPhase = exp(1j * [0 pi/2 pi 3*pi/2]);
B = complex(zeros(numTxPorts, size(spatial, 2) * numel(coPhase)));
col = 0;
for b = 1:size(spatial, 2)
    v = spatial(:, b);
    nrm = norm(v);
    if nrm > 0
        v = v ./ nrm;
    end
    for p = 1:numel(coPhase)
        col = col + 1;
        B(:, col) = [v; coPhase(p) .* v] ./ sqrt(2);
    end
end
if size(B, 2) > numBeams
    B = B(:, 1:numBeams);
end
for i = 1:size(B, 2)
    nrm = norm(B(:, i));
    if nrm > 0
        B(:, i) = B(:, i) ./ nrm;
    end
end
end

function basisCount = localResolveType2BasisBeamCount(cfg, mode, nLayers, numBeams)
defaultCount = 2;
if string(mode) == "etype2_candidate"
    defaultCount = 4;
end
basisCount = double(sixgr.util.structGet(cfg, "phy.csi.type2BasisBeamCount", ...
    sixgr.util.structGet(cfg, "csi_acquisition_and_reporting.type2_basis_beam_count", defaultCount)));
basisCount = max(1, min(max(1, floor(double(numBeams) / max(1, double(nLayers)))), round(double(basisCount))));
end

function [W, beamIdx, coeffToken] = localBuildType2CompositeCandidate(B, startIdx, stride, nLayers, basisCount, layerPhase, mode)
numBeams = size(B, 2);
numTxPorts = size(B, 1);
W = complex(zeros(numTxPorts, nLayers));
beamIdx = zeros(1, nLayers * basisCount);
coeffAll = complex(zeros(1, nLayers * basisCount));
qpsk = exp(1j * (0:3) * pi/2);
if string(mode) == "etype2_candidate"
    qpsk = exp(1j * (0:7) * pi/4);
end
cursor = 0;
for layer = 1:nLayers
    group = 1 + mod((startIdx - 1) + (layer - 1) * stride + (0:basisCount-1) * max(1, nLayers), numBeams);
    coeff = complex(zeros(1, basisCount));
    for b = 1:basisCount
        coeff(b) = layerPhase(layer) * qpsk(1 + mod((startIdx - 1) + (layer - 1) + (b - 1), numel(qpsk)));
    end
    coeff = coeff ./ sqrt(max(sum(abs(coeff).^2), eps));
    W(:, layer) = B(:, group) * coeff(:);
    cursorIdx = cursor + (1:basisCount);
    beamIdx(cursorIdx) = group;
    coeffAll(cursorIdx) = coeff;
    cursor = cursor + basisCount;
end
W = localNormalizeColumns(W);
beamIdx = double(beamIdx);
coeffToken = localComplexVectorToken(coeffAll);
end

function token = localComplexVectorToken(x)
parts = strings(1, numel(x));
for i = 1:numel(x)
    parts(i) = sprintf("%.3f%+.3fj", real(x(i)), imag(x(i)));
end
token = char(join(parts, ";"));
end

function v = localCoefficientTokenVector(token)
chars = char(string(token));
if isempty(chars)
    v = 0;
else
    v = double(chars);
end
end

function y = localTernaryNumeric(tf, whenTrue, whenFalse)
if logical(tf)
    y = whenTrue;
else
    y = whenFalse;
end
end

function tf = localWantsDualPolarizedType1(cfg)
tf = logical(sixgr.util.structGet(cfg, "phy.csi.dualPolarizedType1", false));
polTokens = [
    string(sixgr.util.structGet(cfg, "antenna.bs.polarization", "")), ...
    string(sixgr.util.structGet(cfg, "antenna_and_array.polarization", ""))];
for i = 1:numel(polTokens)
    tok = lower(strtrim(polTokens(i)));
    if any(tok == ["dual","dual_pol","dualpolarized","dual-polarized","cross","cross_pol","cross-polarized","cross_polarized"])
        tf = true;
        return;
    end
end
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
runtimeArray = sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct());
if isstruct(runtimeArray)
    nPol = double(sixgr.util.structGet(runtimeArray, "NPol", NaN));
    tf = tf || (isfinite(nPol) && nPol > 1);
end
end

function arr = localResolveRuntimeBSAntenna(cfg, numTxPorts)
arr = struct();
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
candidate = sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct());
if isstruct(candidate) && ~isempty(fieldnames(candidate))
    nant = double(sixgr.util.structGet(candidate, "Nant", NaN));
    if isfinite(nant) && round(nant) == round(double(numTxPorts))
        arr = candidate;
        return;
    end
end
shape = double(sixgr.util.structGet(cfg, "phy.bsArray", [1 numTxPorts 1]));
if numel(shape) < 2
    shape = [1 max(1, round(double(numTxPorts))) 1];
end
arr = struct( ...
    "Size", double(shape(1:2)), ...
    "Nant", double(prod(max(1, round(shape(1:2))))), ...
    "Type", char(string(sixgr.util.structGet(cfg, "antenna.bs.geometry", "ura"))));
end

function [nRow, nCol] = localResolveArrayDims(arr, fallbackPorts)
nRow = 1;
nCol = max(1, round(double(fallbackPorts)));
if isfield(arr, "Size") && isnumeric(arr.Size) && numel(arr.Size) >= 2
    nRow = max(1, round(double(arr.Size(1))));
    nCol = max(1, round(double(arr.Size(2))));
elseif isfield(arr, "nRow") && isfield(arr, "nCol")
    nRow = max(1, round(double(arr.nRow)));
    nCol = max(1, round(double(arr.nCol)));
end
if nRow * nCol ~= max(1, round(double(fallbackPorts)))
    nRow = 1;
    nCol = max(1, round(double(fallbackPorts)));
end
end

function [nBeamsRow, nBeamsCol] = localResolveBeamGrid(nRow, nCol, numBeams)
numBeams = max(1, round(double(numBeams)));
nRow = max(1, round(double(nRow)));
nCol = max(1, round(double(nCol)));
if nRow <= 1
    nBeamsRow = 1;
    nBeamsCol = numBeams;
    return;
end
if nCol <= 1
    nBeamsRow = numBeams;
    nBeamsCol = 1;
    return;
end
targetRatio = nRow / max(nCol, 1);
nBeamsRow = max(1, round(sqrt(numBeams * targetRatio)));
nBeamsCol = max(1, ceil(numBeams / max(nBeamsRow, 1)));
end

function key = localCandidateKey(beamIdx, phaseRow)
beamToken = join(string(beamIdx), "_");
phaseToken = strings(1, numel(phaseRow));
for i = 1:numel(phaseRow)
    phaseToken(i) = string(round(real(phaseRow(i)) * 1000)) + "j" + string(round(imag(phaseRow(i)) * 1000));
end
key = char(beamToken + "|" + join(phaseToken, "_"));
end

function limited = localLimitCandidates(candidates, maxCandidates)
if numel(candidates) <= maxCandidates
    limited = candidates;
    return;
end
pick = unique(round(linspace(1, numel(candidates), maxCandidates)));
limited = candidates(pick);
end

function out = localRenumberPMI(candidates)
out = candidates;
for i = 1:numel(out)
    out(i).PMI = double(i - 1);
end
end

function tag = localPMIType(mode)
switch string(mode)
    case "type1_su_mimo"
        tag = "type1";
    case "type2_mu_mimo"
        tag = "type2";
    case "etype2_candidate"
        tag = "etype2";
    otherwise
        tag = "noncodebook";
end
end
