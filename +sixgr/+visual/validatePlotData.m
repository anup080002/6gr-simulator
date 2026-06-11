function status = validatePlotData(plotType, x, y, varargin)
%VALIDATEPLOTDATA Determine whether a plot may be rendered honestly.
%   STATUS = validatePlotData(PLOTTYPE, X, Y) returns row-count and
%   sufficiency metadata for relation, trace, CDF, histogram, heatmap, and
%   summary plots.

opts = struct( ...
    "MinimumRows", NaN, ...
    "MinimumUniqueX", NaN, ...
    "MinimumUniqueY", NaN, ...
    "MinimumNonNaNY", NaN, ...
    "XColumnName", "", ...
    "LLSValidity", "real_lls_evidence");
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
status.UniqueYCount = double(numel(unique(y(pairMask))));
status.VisualValidity = lower(string(opts.LLSValidity));
if status.VisualValidity == "diagnostic_only"
    status.CountsAsRealPlot = false;
    status.WarningBannerText = "DIAGNOSTIC ONLY - not counted as real LLS evidence";
elseif status.VisualValidity == "unavailable"
    status.CountsAsRealPlot = false;
    status.WarningBannerText = "";
else
    status.VisualValidity = "real_lls_evidence";
    status.WarningBannerText = "";
end

switch plotType
    case {"line", "timeseries", "time_series"}
        minRows = localDefaultOr(opts.MinimumRows, 3);
        minUniqueX = localDefaultOr(opts.MinimumUniqueX, 3);
        minNonNaNY = localDefaultOr(opts.MinimumNonNaNY, 3);
        if status.PairRowCount < minRows
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_rows");
        elseif status.UniqueXCount < minUniqueX
            if strcmpi(string(opts.XColumnName), "Frame")
                [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_unique_frame_x_for_line_plot");
            else
                [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_unique_x_for_line_plot");
            end
        elseif status.NonNaNYCount < minNonNaNY
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_non_nan_y");
        elseif ~localMonotonicFiniteX(x(pairMask))
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("non_monotonic_x_for_line_plot");
        elseif localLongestFiniteXRun(x(pairMask)) < 3
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_consecutive_x_for_line_plot");
        end
    case {"relation", "scatter", "vs"}
        minRows = localDefaultOr(opts.MinimumRows, 2);
        minUniqueX = localDefaultOr(opts.MinimumUniqueX, 2);
        minUniqueY = localDefaultOr(opts.MinimumUniqueY, 1);
        minNonNaNY = localDefaultOr(opts.MinimumNonNaNY, 2);
        if status.PairRowCount < minRows
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_rows");
        elseif status.UniqueXCount < minUniqueX
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_unique_x");
        elseif status.UniqueYCount < minUniqueY
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_unique_y");
        elseif status.NonNaNYCount < minNonNaNY
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_non_nan_y");
        end
    case {"trace", "timeline"}
        minRows = localDefaultOr(opts.MinimumRows, 2);
        minUniqueX = localDefaultOr(opts.MinimumUniqueX, 1);
        minUniqueY = localDefaultOr(opts.MinimumUniqueY, 1);
        minNonNaNY = localDefaultOr(opts.MinimumNonNaNY, 2);
        if status.RowCount < minRows
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_rows");
        elseif status.UniqueXCount < minUniqueX
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_unique_x");
        elseif status.UniqueYCount < minUniqueY
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_unique_y");
        elseif status.NonNaNYCount < minNonNaNY
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_non_nan_y");
        end
    case {"cdf", "histogram"}
        minRows = localDefaultOr(opts.MinimumRows, 2);
        minUniqueX = localDefaultOr(opts.MinimumUniqueX, 1);
        minUniqueY = localDefaultOr(opts.MinimumUniqueY, 1);
        if status.NonNaNYCount < minRows
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_rows");
        elseif status.UniqueXCount < minUniqueX
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_unique_x");
        elseif status.UniqueYCount < minUniqueY
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_unique_y");
        end
    case "heatmap"
        minRows = localDefaultOr(opts.MinimumRows, 1);
        minUniqueX = localDefaultOr(opts.MinimumUniqueX, 1);
        minUniqueY = localDefaultOr(opts.MinimumUniqueY, 1);
        if status.NonNaNYCount < localDefaultOr(opts.MinimumNonNaNY, 1) || status.PairRowCount < minRows
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("empty_or_all_nan_heatmap");
        elseif status.UniqueXCount < minUniqueX
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_unique_x");
        elseif status.UniqueYCount < minUniqueY
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_unique_y");
        end
    otherwise
        if status.NonNaNYCount < localDefaultOr(opts.MinimumNonNaNY, 1)
            [status.PlotRenderStatus, status.PlotSuppressionReason] = localSuppressed("insufficient_non_nan_y");
        end
end

if string(status.PlotRenderStatus) ~= "rendered"
    status.CountsAsRealPlot = false;
    status.VisualValidity = "unavailable";
    status.WarningBannerText = "";
end
end

function value = localDefaultOr(candidate, fallback)
if isempty(candidate) || ~isfinite(double(candidate))
    value = double(fallback);
else
    value = double(candidate);
end
end

function tf = localMonotonicFiniteX(x)
x = double(x(:));
x = x(isfinite(x));
if numel(x) < 3
    tf = false;
    return;
end
d = diff(x);
tf = all(d >= 0) || all(d <= 0);
end

function n = localLongestFiniteXRun(x)
x = double(x(:));
x = x(isfinite(x));
if numel(x) < 3
    n = numel(x);
    return;
end
d = diff(x);
validStep = isfinite(d) & d ~= 0;
if ~any(validStep)
    n = 1;
    return;
end
n = 1;
current = 1;
for i = 1:numel(validStep)
    if validStep(i)
        current = current + 1;
    else
        current = 1;
    end
    n = max(n, current);
end
end

function [renderStatus, reason] = localSuppressed(reason)
renderStatus = "suppressed";
reason = string(reason);
end
