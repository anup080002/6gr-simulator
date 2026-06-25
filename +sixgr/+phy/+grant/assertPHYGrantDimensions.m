function contract = assertPHYGrantDimensions(phyGrant, stage, varargin)
%ASSERTPHYGRANTDIMENSIONS Validate frozen PHYGrant dimensional invariants.
% Keep this file ASCII-only.

if nargin < 2 || strlength(string(stage)) == 0
    stage = "unspecified";
end

opts = localParseOpts(varargin{:});
localRequire(isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)), ...
    "BadPHYGrant", "PHYGrant must be a non-empty struct at stage '%s'.", stage);
localRequire(logical(sixgr.util.structGet(phyGrant, "IsFrozen", false)), ...
    "NotFrozen", "PHYGrant must be frozen before stage '%s'.", stage);

direction = upper(string(sixgr.util.structGet(phyGrant, "Direction", "")));
localRequire(direction == "DL" || direction == "UL", ...
    "BadDirection", "PHYGrant direction must be DL or UL at stage '%s'.", stage);

ant = sixgr.util.structGet(phyGrant, "AntennaArchitecture", struct());
ra = sixgr.util.structGet(phyGrant, "ResourceAllocation", struct());
cl = sixgr.util.structGet(phyGrant, "CodingLayout", struct());
prec = sixgr.util.structGet(phyGrant, "PrecodingState", struct());

numElements = localPositiveScalar(ant, "NumElements", stage);
numLogicalPorts = localPositiveScalar(ant, "NumLogicalPorts", stage);
numLayers = localPositiveScalar(ant, "NumLayers", stage);
numCodewords = localPositiveScalar(ant, "NumCodewords", stage);
numWaveformColumns = localPositiveScalar(ant, "NumWaveformColumns", stage);
numRxAntennas = localPositiveScalar(ant, "NumRxAntennas", stage);

localRequire(numLayers <= numLogicalPorts, ...
    "LayerPortMismatch", "PHYGrant has %d layer(s) but only %d logical port(s) at stage '%s'.", ...
    numLayers, numLogicalPorts, stage);
localRequire(numLogicalPorts <= max(numElements, numLogicalPorts), ...
    "PortElementMismatch", "PHYGrant logical ports exceed element count at stage '%s'.", stage);
localRequire(numWaveformColumns == numLogicalPorts, ...
    "WaveformColumnMismatch", ...
    "PHYGrant NumWaveformColumns=%d must equal NumLogicalPorts=%d at stage '%s'.", ...
    numWaveformColumns, numLogicalPorts, stage);
localRequire(numCodewords >= 1, ...
    "BadCodewordCount", "PHYGrant NumCodewords must be positive at stage '%s'.", stage);
localRequire(localScalar(cl, "NumLayers", numLayers) == numLayers, ...
    "CodingLayerMismatch", "CodingLayout.NumLayers does not match AntennaArchitecture.NumLayers at stage '%s'.", stage);
localRequire(localScalar(cl, "NumCodewords", numCodewords) == numCodewords, ...
    "CodingCodewordMismatch", "CodingLayout.NumCodewords does not match AntennaArchitecture.NumCodewords at stage '%s'.", stage);

prbSet = double(sixgr.util.structGet(ra, "PRBSet", []));
prbSet = prbSet(:).';
localRequire(~isempty(prbSet) && all(isfinite(prbSet)) && all(prbSet >= 0), ...
    "BadPRBSet", "PHYGrant requires a finite non-empty PRBSet at stage '%s'.", stage);
prbCount = round(localScalar(ra, "PRBCount", numel(prbSet)));
localRequire(prbCount == numel(prbSet), ...
    "PRBCountMismatch", "ResourceAllocation.PRBCount=%d but PRBSet has %d entries at stage '%s'.", ...
    prbCount, numel(prbSet), stage);
symAlloc = double(sixgr.util.structGet(ra, "SymbolAllocation", []));
localRequire(numel(symAlloc) >= 2 && all(isfinite(symAlloc(1:2))) && symAlloc(2) >= 1, ...
    "BadSymbolAllocation", "PHYGrant requires SymbolAllocation [start numSymbols] at stage '%s'.", stage);

W = sixgr.util.structGet(prec, "Matrix", []);
localRequire(isnumeric(W) && ismatrix(W), ...
    "BadPrecodingMatrix", "PrecodingState.Matrix must be a numeric 2-D matrix at stage '%s'.", stage);
localRequire(size(W, 1) == numLogicalPorts && size(W, 2) == numLayers, ...
    "PrecodingMatrixShapeMismatch", ...
    "PrecodingState.Matrix is %dx%d but expected %dx%d at stage '%s'.", ...
    size(W, 1), size(W, 2), numLogicalPorts, numLayers, stage);
localRequire(localScalar(prec, "NumPorts", numLogicalPorts) == numLogicalPorts, ...
    "PrecodingPortMismatch", "PrecodingState.NumPorts does not match NumLogicalPorts at stage '%s'.", stage);
localRequire(localScalar(prec, "NumLayers", numLayers) == numLayers, ...
    "PrecodingLayerMismatch", "PrecodingState.NumLayers does not match NumLayers at stage '%s'.", stage);

if ~isempty(opts.NumTxAnt)
    numTxAnt = max(1, round(double(opts.NumTxAnt)));
    localRequire(numTxAnt == numWaveformColumns, ...
        "TxAntennaCountMismatch", ...
        "TX requested %d waveform column(s), frozen PHYGrant requires %d at stage '%s'.", ...
        numTxAnt, numWaveformColumns, stage);
end

if ~isempty(opts.Waveform)
    localRequire(isnumeric(opts.Waveform), ...
        "BadWaveform", "Waveform must be numeric at stage '%s'.", stage);
    localRequire(size(opts.Waveform, 2) == numWaveformColumns, ...
        "WaveformColumnMismatch", ...
        "Waveform has %d column(s), frozen PHYGrant requires %d at stage '%s'.", ...
        size(opts.Waveform, 2), numWaveformColumns, stage);
end

if ~isempty(opts.Grid)
    localRequire(isnumeric(opts.Grid), ...
        "BadGrid", "Resource grid must be numeric at stage '%s'.", stage);
    localRequire(size(opts.Grid, 3) >= numWaveformColumns, ...
        "GridPageMismatch", ...
        "Resource grid has %d page(s), frozen PHYGrant requires at least %d at stage '%s'.", ...
        size(opts.Grid, 3), numWaveformColumns, stage);
end

if ~isempty(opts.PDSCH)
    localAssertChannelConfig(opts.PDSCH, "PDSCH", prbSet, symAlloc, numLayers, stage);
end
if ~isempty(opts.PUSCH)
    localAssertChannelConfig(opts.PUSCH, "PUSCH", prbSet, symAlloc, numLayers, stage);
    puschPorts = localObjectValue(opts.PUSCH, "NumAntennaPorts", NaN);
    if isfinite(puschPorts)
        localRequire(round(double(puschPorts)) == numLogicalPorts, ...
            "PUSCHPortMismatch", ...
            "PUSCH.NumAntennaPorts=%d but frozen PHYGrant requires %d at stage '%s'.", ...
            round(double(puschPorts)), numLogicalPorts, stage);
    end
end
if ~isempty(opts.Precoding)
    localAssertRuntimePrecoding(opts.Precoding, numLogicalPorts, numLayers, direction, stage);
end

contract = struct( ...
    "Stage", char(string(stage)), ...
    "Direction", char(direction), ...
    "NumElements", double(numElements), ...
    "NumLogicalPorts", double(numLogicalPorts), ...
    "NumLayers", double(numLayers), ...
    "NumCodewords", double(numCodewords), ...
    "NumWaveformColumns", double(numWaveformColumns), ...
    "NumRxAntennas", double(numRxAntennas), ...
    "PRBCount", double(numel(prbSet)), ...
    "SymbolStart", double(symAlloc(1)), ...
    "NumSymbols", double(symAlloc(2)), ...
    "PrecodingMatrixRows", double(size(W, 1)), ...
    "PrecodingMatrixCols", double(size(W, 2)), ...
    "Validated", true);
end

function opts = localParseOpts(varargin)
opts = struct("PDSCH", [], "PUSCH", [], "Precoding", [], ...
    "NumTxAnt", [], "Waveform", [], "Grid", []);
if mod(numel(varargin), 2) ~= 0
    error("sixgr:phy:grant:BadAssertNV", "Name-value arguments must come in pairs.");
end
for i = 1:2:numel(varargin)
    key = lower(string(varargin{i}));
    val = varargin{i + 1};
    switch key
        case "pdsch"
            opts.PDSCH = val;
        case "pusch"
            opts.PUSCH = val;
        case "precoding"
            opts.Precoding = val;
        case "numtxant"
            opts.NumTxAnt = val;
        case "waveform"
            opts.Waveform = val;
        case "grid"
            opts.Grid = val;
        otherwise
            error("sixgr:phy:grant:BadAssertNV", ...
                "Unknown PHYGrant assertion option '%s'.", char(key));
    end
end
end

function localAssertChannelConfig(ch, label, prbSet, symAlloc, numLayers, stage)
localRequire(isobject(ch), "BadChannelConfig", "%s must be an NR config object at stage '%s'.", label, stage);
layers = localObjectValue(ch, "NumLayers", NaN);
localRequire(isfinite(layers) && round(double(layers)) == numLayers, ...
    "ChannelLayerMismatch", "%s.NumLayers=%g but frozen PHYGrant requires %d at stage '%s'.", ...
    label, double(layers), numLayers, stage);
chPRB = double(localObjectValue(ch, "PRBSet", []));
localRequire(numel(chPRB) == numel(prbSet) && all(double(chPRB(:).') == double(prbSet(:).')), ...
    "ChannelPRBMismatch", "%s.PRBSet does not match frozen PHYGrant at stage '%s'.", label, stage);
chSym = double(localObjectValue(ch, "SymbolAllocation", []));
localRequire(numel(chSym) >= 2 && all(double(chSym(1:2)) == double(symAlloc(1:2))), ...
    "ChannelSymbolMismatch", "%s.SymbolAllocation does not match frozen PHYGrant at stage '%s'.", label, stage);
end

function localAssertRuntimePrecoding(prec, numPorts, numLayers, direction, stage)
localRequire(isstruct(prec), "BadPrecodingInfo", "Runtime precoding info must be struct at stage '%s'.", stage);
runtimeLayers = localScalar(prec, "NumLayers", numLayers);
localRequire(round(runtimeLayers) == numLayers, ...
    "RuntimePrecodingLayerMismatch", ...
    "Runtime precoding NumLayers=%g but frozen PHYGrant requires %d at stage '%s'.", ...
    runtimeLayers, numLayers, stage);
runtimePorts = localScalar(prec, "NumPorts", numPorts);
if direction == "DL" || logical(sixgr.util.structGet(prec, "NativeCodebookApplied", false)) || ...
        logical(sixgr.util.structGet(prec, "TransformPrecodingApplied", false))
    localRequire(round(runtimePorts) == numPorts, ...
        "RuntimePrecodingPortMismatch", ...
        "Runtime precoding NumPorts=%g but frozen PHYGrant requires %d at stage '%s'.", ...
        runtimePorts, numPorts, stage);
end
matrixRows = localScalar(prec, "MatrixRows", NaN);
matrixCols = localScalar(prec, "MatrixCols", NaN);
if isfinite(matrixRows)
    localRequire(round(matrixRows) == numPorts, ...
        "RuntimePrecodingMatrixRowsMismatch", ...
        "Runtime precoding MatrixRows=%g but frozen PHYGrant requires %d at stage '%s'.", ...
        matrixRows, numPorts, stage);
end
if isfinite(matrixCols)
    localRequire(round(matrixCols) == numLayers, ...
        "RuntimePrecodingMatrixColsMismatch", ...
        "Runtime precoding MatrixCols=%g but frozen PHYGrant requires %d at stage '%s'.", ...
        matrixCols, numLayers, stage);
end
end

function value = localPositiveScalar(s, fieldName, stage)
value = localScalar(s, fieldName, NaN);
localRequire(isfinite(value) && value >= 1 && round(value) == value, ...
    "BadPositiveInteger", "%s must be a positive integer at stage '%s'.", fieldName, stage);
end

function value = localScalar(s, fieldName, fallback)
raw = sixgr.util.structGet(s, fieldName, fallback);
if isempty(raw) || ~(isnumeric(raw) || islogical(raw))
    value = fallback;
    return;
end
raw = double(raw(:));
raw = raw(isfinite(raw));
if isempty(raw)
    value = fallback;
else
    value = raw(1);
end
end

function value = localObjectValue(obj, propName, fallback)
value = fallback;
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

function localRequire(condition, suffix, msg, varargin)
if condition
    return;
end
error(char("sixgr:phy:grant:" + string(suffix)), msg, varargin{:});
end
