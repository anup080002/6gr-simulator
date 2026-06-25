function traceT = CodewordLayerMapper(cfg, varargin)
%CodewordLayerMapper Trace the active NR-baseline codeword-to-layer mapping.

rank = max(1, round(double(sixgr.util.structGet(cfg, "CodewordLayer.Rank", sixgr.util.structGet(cfg, "NumLayers", 1)))));
numCodewords = max(1, round(double(sixgr.util.structGet(cfg, "CodewordLayer.NumCodewords", 1))));
if rank < 1 || rank > 8
    error("sixgr:pdsch:CodewordLayerMapper:BadRank", ...
        "PDSCH codeword-layer mapping supports ranks 1-8. Requested rank %d.", rank);
end
expectedCodewords = 1 + double(rank > 4);
if numCodewords ~= expectedCodewords
    error("sixgr:pdsch:CodewordLayerMapper:BadCodewordLayerMapping", ...
        "PDSCH rank-%d requires %d codeword(s). Requested %d.", rank, expectedCodewords, numCodewords);
end

layers = (0:rank-1).';
layerCounts = localLayerCountPerCodeword(rank, numCodewords);
codewordIndex = zeros(rank, 1);
layerWithinCodeword = zeros(rank, 1);
layerCountForCodeword = zeros(rank, 1);
pos = 1;
for cw = 1:numCodewords
    idx = pos:(pos + layerCounts(cw) - 1);
    codewordIndex(idx) = cw - 1;
    layerWithinCodeword(idx) = 0:(layerCounts(cw) - 1);
    layerCountForCodeword(idx) = layerCounts(cw);
    pos = pos + layerCounts(cw);
end
traceT = table( ...
    codewordIndex, ...
    layers, ...
    layerWithinCodeword, ...
    layerCountForCodeword, ...
    repmat("spatial_first_frequency_second_time_third", numel(layers), 1), ...
    repmat(localBaselineMode(numCodewords), numel(layers), 1), ...
    'VariableNames', {'CodewordIndex','LayerIndex','LayerIndexWithinCodeword','LayerCountForCodeword','MappingOrder','BaselineMode'});
end

function counts = localLayerCountPerCodeword(rank, numCodewords)
if numCodewords == 1
    counts = double(rank);
    return;
end
switch rank
    case 5
        counts = [2 3];
    case 6
        counts = [3 3];
    case 7
        counts = [3 4];
    case 8
        counts = [4 4];
    otherwise
        error("sixgr:pdsch:CodewordLayerMapper:BadCodewordLayerMapping", ...
            "Two-codeword PDSCH mapping is defined for ranks 5-8. Requested rank %d.", rank);
end
end

function mode = localBaselineMode(numCodewords)
if numCodewords == 1
    mode = "nr_baseline_single_codeword";
else
    mode = "nr_baseline_two_codeword";
end
end
