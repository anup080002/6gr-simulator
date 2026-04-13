function [servingIdx, servingMetric_dBm, metricSource] = selectServingCellsFromPower(metric_dBm, varargin)
% sixgr.system.selectServingCellsFromPower
% Select the strongest serving cell per UE from a KxN power table.

opt = struct();
opt.FallbackMetric_dBm = [];

if mod(numel(varargin), 2) ~= 0
    error("sixgr:system:selectServingCellsFromPower:BadNV", ...
        "Name-value inputs must come in pairs.");
end
for i = 1:2:numel(varargin)
    name = string(varargin{i});
    value = varargin{i+1};
    switch lower(name)
        case {"fallbackmetric_dbm","fallbackmetric","fallback"}
            opt.FallbackMetric_dBm = double(value);
        otherwise
            error("sixgr:system:selectServingCellsFromPower:UnknownOpt", ...
                "Unknown option: %s", name);
    end
end

metric_dBm = double(metric_dBm);
if ndims(metric_dBm) ~= 2
    error("sixgr:system:selectServingCellsFromPower:BadMetric", ...
        "metric_dBm must be a KxN matrix.");
end

[K, nCells] = size(metric_dBm);
if nCells < 1
    error("sixgr:system:selectServingCellsFromPower:BadMetric", ...
        "metric_dBm must include at least one cell column.");
end

if isempty(opt.FallbackMetric_dBm)
    fallback_dBm = [];
else
    fallback_dBm = double(opt.FallbackMetric_dBm);
    if ~isequal(size(fallback_dBm), size(metric_dBm))
        error("sixgr:system:selectServingCellsFromPower:BadFallbackMetric", ...
            "FallbackMetric_dBm must match the size of metric_dBm.");
    end
end

servingIdx = ones(K, 1);
servingMetric_dBm = NaN(K, 1);
metricSource = repmat("none", K, 1);

for u = 1:K
    [servingIdx(u), servingMetric_dBm(u), metricSource(u)] = localSelectBestCell( ...
        metric_dBm(u, :), fallback_dBm, u);
end
end

function [bestIdx, bestMetric_dBm, source] = localSelectBestCell(metricRow_dBm, fallback_dBm, rowIdx)
bestIdx = 1;
bestMetric_dBm = NaN;
source = "none";

finiteMask = isfinite(metricRow_dBm);
if any(finiteMask)
    candidate = metricRow_dBm;
    candidate(~finiteMask) = -Inf;
    [bestMetric_dBm, bestIdx] = max(candidate, [], 2);
    source = "primary";
    return;
end

if isempty(fallback_dBm)
    return;
end

fallbackRow_dBm = fallback_dBm(rowIdx, :);
finiteMask = isfinite(fallbackRow_dBm);
if any(finiteMask)
    candidate = fallbackRow_dBm;
    candidate(~finiteMask) = -Inf;
    [bestMetric_dBm, bestIdx] = max(candidate, [], 2);
    source = "fallback";
end
end
