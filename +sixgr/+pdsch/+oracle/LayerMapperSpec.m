function out = LayerMapperSpec(input, rank, varargin)
%LAYERMAPPERSPEC Independent TS 38.211 codeword-layer mapping oracle.
%
%   LAYERS = LayerMapperSpec(CODEWORDS,RANK)
%   CODEWORDS = LayerMapperSpec(LAYERS,RANK,"Operation","demap")
%
% This oracle intentionally calls neither production code nor nr* helpers.

operation = "map";
if mod(numel(varargin), 2) ~= 0
    error("sixgr:pdsch:oracle:LayerMapperSpec:BadNameValue", ...
        "Layer oracle options must be name-value pairs.");
end
for idx = 1:2:numel(varargin)
    if lower(string(varargin{idx})) ~= "operation"
        error("sixgr:pdsch:oracle:LayerMapperSpec:UnknownOption", ...
            "Unknown layer oracle option '%s'.", string(varargin{idx}));
    end
    operation = lower(string(varargin{idx + 1}));
end

counts = localCounts(rank);
if operation == "map"
    codewords = localCodewords(input, numel(counts));
    layers = cell(sum(counts), 1);
    offset = 0;
    for q = 1:numel(counts)
        count = counts(q);
        if mod(numel(codewords{q}), count) ~= 0
            error("sixgr:pdsch:oracle:LayerMapperSpec:SymbolCountMismatch", ...
                "Codeword %d symbol count is not divisible by %d.", q - 1, count);
        end
        for layer = 1:count
            layers{offset + layer} = codewords{q}(layer:count:end);
        end
        offset = offset + count;
    end
    if all(cellfun(@numel, layers) == numel(layers{1}))
        out = horzcat(layers{:});
    else
        out = layers;
    end
elseif operation == "demap"
    layers = localLayers(input, rank);
    codewords = cell(1, numel(counts));
    offset = 0;
    for q = 1:numel(counts)
        selected = layers(offset + (1:counts(q)));
        if ~all(cellfun(@numel, selected) == numel(selected{1}))
            error("sixgr:pdsch:oracle:LayerMapperSpec:LayerLengthMismatch", ...
                "Layers for codeword %d must have equal lengths.", q - 1);
        end
        matrix = horzcat(selected{:});
        codewords{q} = reshape(matrix.', [], 1);
        offset = offset + counts(q);
    end
    if numel(codewords) == 1
        out = codewords{1};
    else
        out = codewords;
    end
else
    error("sixgr:pdsch:oracle:LayerMapperSpec:UnsupportedOperation", ...
        "Unsupported layer oracle operation '%s'.", operation);
end
end

function counts = localCounts(rank)
if ~(isnumeric(rank) && isscalar(rank) && isfinite(rank) ...
        && rank == fix(rank) && rank >= 1 && rank <= 8)
    error("sixgr:pdsch:oracle:LayerMapperSpec:RankOutOfRange", ...
        "Rank must be an integer in [1,8].");
end
if rank <= 4
    counts = rank;
else
    table = {[2 3], [3 3], [3 4], [4 4]};
    counts = table{rank - 4};
end
end

function codewords = localCodewords(input, expected)
if expected == 1 && ~iscell(input)
    codewords = {input(:)};
elseif iscell(input)
    codewords = input(:).';
else
    codewords = {input(:)};
end
if numel(codewords) ~= expected
    error("sixgr:pdsch:oracle:LayerMapperSpec:CodewordCountMismatch", ...
        "Expected %d codeword(s), received %d.", expected, numel(codewords));
end
for idx = 1:numel(codewords)
    codewords{idx} = codewords{idx}(:);
end
end

function layers = localLayers(input, rank)
if iscell(input)
    layers = input(:);
elseif (isnumeric(input) || islogical(input)) && size(input, 2) == rank
    layers = cell(rank, 1);
    for idx = 1:rank
        layers{idx} = input(:, idx);
    end
else
    error("sixgr:pdsch:oracle:LayerMapperSpec:LayerCountMismatch", ...
        "Layer input must provide exactly rank=%d streams.", rank);
end
if numel(layers) ~= rank
    error("sixgr:pdsch:oracle:LayerMapperSpec:LayerCountMismatch", ...
        "Expected %d layers, received %d.", rank, numel(layers));
end
end
