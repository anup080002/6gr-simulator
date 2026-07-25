function [out, info] = CodewordLayerMapper(input, varargin)
%CODEWORDLAYERMAPPER Map PDSCH codeword symbols to ranks one through eight.
%
%   LAYERS = CodewordLayerMapper(CODEWORDS,RANK)
%   CODEWORDS = CodewordLayerMapper(LAYERS,RANK,"Operation","demap")
%
% CODEWORDS is a vector for ranks one through four or a two-element cell
% for ranks five through eight.  LAYERS is returned as an N-by-RANK matrix
% when all layer streams have equal length; otherwise it is a cell vector.
%
if isstruct(input) && isempty(varargin)
    error("sixgr:pdsch:CodewordLayerMapper:LegacyMetadataForbidden", ...
        "Codeword-layer mapping requires materialized codeword symbols and an explicit rank; configuration-only metadata inference is forbidden.");
end
if isempty(varargin)
    error("sixgr:pdsch:CodewordLayerMapper:MissingRank", ...
        "PDSCH codeword-layer mapping requires an explicit rank.");
end

rank = varargin{1};
options = localParseOptions(varargin(2:end));
layerCounts = localLayerCounts(rank);
expectedCodewords = numel(layerCounts);

switch options.Operation
    case {"map", "codeword-to-layer"}
        codewords = localNormalizeCodewords(input, expectedCodewords);
        layerCells = localMap(codewords, layerCounts);
        out = localPackLayers(layerCells);
    case {"demap", "layer-to-codeword"}
        layerCells = localNormalizeLayers(input, rank);
        out = localDemap(layerCells, layerCounts);
    otherwise
        error("sixgr:pdsch:CodewordLayerMapper:UnsupportedOperation", ...
            "Unsupported codeword-layer operation '%s'.", options.Operation);
end

info = struct();
info.Operation = options.Operation;
info.Rank = rank;
info.NumCodewords = expectedCodewords;
info.LayerCountPerCodeword = layerCounts;
info.CodewordIndexPerLayer = localCodewordIndexPerLayer(layerCounts);
info.LayerIndexConvention = "zero_based";
info.Mapping = "ts_38_211_clause_7_3_1_3";
end

function options = localParseOptions(nv)
options = struct("Operation", "map");
if mod(numel(nv), 2) ~= 0
    error("sixgr:pdsch:CodewordLayerMapper:BadNameValue", ...
        "Codeword-layer options must be supplied as name-value pairs.");
end
for idx = 1:2:numel(nv)
    name = lower(strtrim(string(nv{idx})));
    switch name
        case "operation"
            options.Operation = lower(strtrim(string(nv{idx + 1})));
        otherwise
            error("sixgr:pdsch:CodewordLayerMapper:UnknownOption", ...
                "Unknown codeword-layer option '%s'.", name);
    end
end
end

function counts = localLayerCounts(rank)
if ~(isnumeric(rank) && isscalar(rank) && isfinite(rank) ...
        && rank == fix(rank) && rank >= 1 && rank <= 8)
    error("sixgr:pdsch:CodewordLayerMapper:RankOutOfRange", ...
        "PDSCH rank must be an integer in [1,8].");
end
switch rank
    case {1, 2, 3, 4}
        counts = double(rank);
    case 5
        counts = [2 3];
    case 6
        counts = [3 3];
    case 7
        counts = [3 4];
    case 8
        counts = [4 4];
end
end

function codewords = localNormalizeCodewords(input, expectedCount)
if expectedCount == 1 && ~iscell(input)
    codewords = {input};
elseif iscell(input)
    codewords = input(:).';
else
    codewords = {input};
end
if numel(codewords) ~= expectedCount
    error("sixgr:pdsch:CodewordLayerMapper:CodewordCountMismatch", ...
        "PDSCH mapping requires %d codeword(s), but %d were supplied.", ...
        expectedCount, numel(codewords));
end
for idx = 1:numel(codewords)
    if ~(isnumeric(codewords{idx}) || islogical(codewords{idx}))
        error("sixgr:pdsch:CodewordLayerMapper:InvalidCodewordSymbols", ...
            "Codeword %d must be a numeric or logical symbol vector.", idx - 1);
    end
    codewords{idx} = codewords{idx}(:);
end
end

function layers = localMap(codewords, layerCounts)
layers = cell(sum(layerCounts), 1);
layerOffset = 0;
for codewordIndex = 1:numel(codewords)
    count = layerCounts(codewordIndex);
    stream = codewords{codewordIndex};
    if mod(numel(stream), count) ~= 0
        error("sixgr:pdsch:CodewordLayerMapper:SymbolCountMismatch", ...
            "Codeword %d symbol count %d is not divisible by its %d layers.", ...
            codewordIndex - 1, numel(stream), count);
    end
    for localLayer = 1:count
        layers{layerOffset + localLayer} = stream(localLayer:count:end);
    end
    layerOffset = layerOffset + count;
end
end

function out = localPackLayers(layers)
lengths = cellfun(@numel, layers);
if isempty(layers) || all(lengths == lengths(1))
    out = horzcat(layers{:});
else
    out = layers;
end
end

function layers = localNormalizeLayers(input, rank)
if iscell(input)
    layers = input(:);
elseif isnumeric(input) || islogical(input)
    if isvector(input) && rank == 1
        layers = {input(:)};
    elseif ismatrix(input) && size(input, 2) == rank
        layers = cell(rank, 1);
        for idx = 1:rank
            layers{idx} = input(:, idx);
        end
    else
        error("sixgr:pdsch:CodewordLayerMapper:LayerCountMismatch", ...
            "Layer matrix must have exactly rank=%d columns.", rank);
    end
else
    error("sixgr:pdsch:CodewordLayerMapper:InvalidLayerSymbols", ...
        "Layer symbols must be a numeric matrix or a cell vector.");
end
if numel(layers) ~= rank
    error("sixgr:pdsch:CodewordLayerMapper:LayerCountMismatch", ...
        "PDSCH demapping requires %d layers, but %d were supplied.", ...
        rank, numel(layers));
end
for idx = 1:numel(layers)
    if ~(isnumeric(layers{idx}) || islogical(layers{idx}))
        error("sixgr:pdsch:CodewordLayerMapper:InvalidLayerSymbols", ...
            "Layer %d must contain numeric or logical symbols.", idx - 1);
    end
    layers{idx} = layers{idx}(:);
end
end

function codewords = localDemap(layers, layerCounts)
codewords = cell(1, numel(layerCounts));
layerOffset = 0;
for codewordIndex = 1:numel(layerCounts)
    count = layerCounts(codewordIndex);
    selected = layers(layerOffset + (1:count));
    lengths = cellfun(@numel, selected);
    if ~all(lengths == lengths(1))
        error("sixgr:pdsch:CodewordLayerMapper:LayerLengthMismatch", ...
            "Layers belonging to codeword %d must have equal symbol counts.", ...
            codewordIndex - 1);
    end
    matrix = horzcat(selected{:});
    codewords{codewordIndex} = reshape(matrix.', [], 1);
    layerOffset = layerOffset + count;
end
if numel(codewords) == 1
    codewords = codewords{1};
end
end

function indices = localCodewordIndexPerLayer(layerCounts)
indices = zeros(1, sum(layerCounts));
offset = 0;
for idx = 1:numel(layerCounts)
    indices(offset + (1:layerCounts(idx))) = idx - 1;
    offset = offset + layerCounts(idx);
end
end
