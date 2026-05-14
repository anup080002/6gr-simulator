function status = validatePlotData(plotType, x, y, varargin)
%VALIDATEPLOTDATA Determine whether a plot may be rendered honestly.
%   STATUS = validatePlotData(PLOTTYPE, X, Y) returns row-count and
%   sufficiency metadata for relation, trace, CDF, histogram, heatmap, and
%   summary plots.

opts = struct( ...
    "MinimumRows", NaN, ...
    "MinimumUniqueX", NaN, ...
    "MinimumNonNaNY", NaN);
if rem(numel(varargin), 2) ~= 0
    error("sixgr:visual:validatePlotData:BadNV", "Name-value inputs must come in pairs.");
end
for i = 1:2:numel(varargin)
    name = string(varargin{i});
    if isfield(opts, name)
        opts.(name) = varargin{i + 1};
    else
        error("sixgr:visual:validatePlotData:BadOpt", "Unknown option: %s", char(name));
    end
end

plotType = lower(string(plotType));
x = double(x(:));
y = double(y(:));
originalXCount = numel(x);
originalYCount = numel(y);
pairCount = min(numel(x), numel(y));
if pairCount > 0
    x = x(1:pairCount);
    y = y(1:pairCount);
else
    x = zeros(0, 1);
    y = zeros(0, 1);
end

pairMask = isfinite(y);
if ~isempty(x)
    pairMask = pairMask & isfinite(x);
end

status = struct();
status.PlotType = plotType;
status.RowCount = double(max(originalYCount, originalXCount));
status.PairRowCount = double(sum(pairMask));
if isempty(x) || isempty(pairMask)
    status.UniqueXCount = 0;
else
    status.UniqueXCount = double(numel(unique(x(pairMask))));
end
status.NonNaNYCount = double(sum(isfinite(y)));
status.PlotRenderStatus = "rendered";
status.PlotSuppressionReason = "";
status.CountsAsRealPlot = true;
status.IsUnavailableCard = false;

switch plotType
    case {"relation", "scatter", "vs"}
        minRows = localDefaultOr(opts.MinimumRows, 2);
        minUniqueX = localDefaultOr(opts.MinimumUniqueX, 2);
        minNonNaNY = localDefaultOr(opts.MinimumNonNaNY, 2);
        if status.PairRowCount < minRows
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_rows");
        elseif status.UniqueXCount < minUniqueX
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_unique_x");
        elseif status.NonNaNYCount < minNonNaNY
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_non_nan_y");
        end
    case {"trace", "timeline"}
        minRows = localDefaultOr(opts.MinimumRows, 2);
        minNonNaNY = localDefaultOr(opts.MinimumNonNaNY, 2);
        if status.RowCount < minRows
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_rows");
        elseif status.NonNaNYCount < minNonNaNY
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_non_nan_y");
        end
    case {"cdf", "histogram"}
        minRows = localDefaultOr(opts.MinimumRows, 2);
        if status.NonNaNYCount < minRows
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_rows");
        end
    case "heatmap"
        if status.NonNaNYCount < localDefaultOr(opts.MinimumNonNaNY, 1)
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("empty_or_all_nan_heatmap");
        end
    otherwise
        if status.NonNaNYCount < localDefaultOr(opts.MinimumNonNaNY, 1)
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_non_nan_y");
        end
end
end

function value = localDefaultOr(candidate, fallback)
if isempty(candidate) || ~isfinite(double(candidate))
    value = double(fallback);
else
    value = double(candidate);
end
end

function [renderStatus, reason] = localSuppressed(reason)
renderStatus = "suppressed";
reason = string(reason);
end
