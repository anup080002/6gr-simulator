function artifacts = publishReferenceQualificationArtifacts(runFolder, pointTable)
%PUBLISHREFERENCEQUALIFICATIONARTIFACTS Publish CSV-backed FRC raster plots.

arguments
    runFolder {mustBeTextScalar}
    pointTable table
end

% This publisher is also a public entry point, so do not rely on its caller
% to have canonicalized a relative run root.  All image/source paths below
% must be absolute until writeComponentPlotLineage reduces them exactly
% once to run-relative portable paths.
runFolder = char(sixgr.util.canonicalPath(runFolder));
layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.ReportImageDir);
masterCSV = fullfile(layout.ReportCSVDir, "frc_reference_points.csv");
subsetDir = fullfile(layout.ReportCSVDir, "frc_reference_points");
sixgr.util.ensureFolder(subsetDir);

required = ["EntryId","FRC","Condition","Metric","SNR_dB", ...
    "MetricEstimate","ConfidenceLower","ConfidenceUpper", ...
    "TargetFraction","RequiredSNR_dB","TransportBlocks", ...
    "ExecutionBackend","ApproximationMode","Source", ...
    "ProxyUsed","FallbackUsed"];
missing = required(~ismember(required, ...
    string(pointTable.Properties.VariableNames)));
if ~isempty(missing)
    error("sixgr:conformance:FRCPointArtifactSchemaInvalid", ...
        "FRC point table is missing column(s): %s.", strjoin(missing, ", "));
end
if isempty(pointTable)
    artifacts = struct( ...
        "PointCSV", "", "ImagePaths", strings(0, 1), ...
        "SubsetCSVs", strings(0, 1), "PlotLineageCSV", "");
    return;
end
localValidatePointRows(pointTable);
sixgr.util.csvWriteTable(masterCSV, pointTable, "PreserveSchema", true);

entryIds = unique(string(pointTable.EntryId), "stable");
imagePaths = strings(numel(entryIds), 1);
subsetCSVs = strings(numel(entryIds), 1);
plotIds = strings(numel(entryIds), 1);
plotMetrics = strings(numel(entryIds), 1);
plotYScales = strings(numel(entryIds), 1);
plotFloors = nan(numel(entryIds), 1);
zeroEstimateCounts = zeros(numel(entryIds), 1);
for index = 1:numel(entryIds)
    entryId = entryIds(index);
    token = localSafeToken(entryId);
    subsetPath = fullfile(subsetDir, token + ".csv");
    subset = pointTable(string(pointTable.EntryId) == entryId, :);
    sixgr.util.csvWriteTable(subsetPath, subset, "PreserveSchema", true);

    % Plot only after re-reading the persisted source.  This makes the PNG
    % a reproducible view of the canonical CSV rather than an in-memory
    % side channel that can diverge from published numerical evidence.
    persisted = readtable(subsetPath, "TextType", "string", ...
        "VariableNamingRule", "preserve", "Delimiter", ",");
    localValidatePointRows(persisted);
    imagePath = fullfile(layout.ReportImageDir, ...
        token + "_reference_point.png");
    plotMeta = localPlotPointTable(persisted, imagePath);
    imagePaths(index) = string(imagePath);
    subsetCSVs(index) = string(subsetPath);
    plotIds(index) = "frc_reference_point_" + string(token);
    plotMetrics(index) = string(plotMeta.Metric);
    plotYScales(index) = string(plotMeta.YScale);
    plotFloors(index) = double(plotMeta.ZeroEstimatePlotFloor);
    zeroEstimateCounts(index) = double(plotMeta.ZeroEstimateCount);
end

lineagePath = fullfile(layout.ReportCSVDir, ...
    "frc_reference_plot_lineage.csv");
sixgr.visual.writeComponentPlotLineage(runFolder, lineagePath, ...
    plotIds, imagePaths, subsetCSVs, ...
    "sixgr.conformance.publishReferenceQualificationArtifacts", ...
    "SourcesAlreadyFinalized", true);
lineage = readtable(lineagePath, "TextType", "string", ...
    "VariableNamingRule", "preserve", "Delimiter", ",");
lineage.Metric = strings(height(lineage), 1);
lineage.YScale = strings(height(lineage), 1);
lineage.ZeroEstimatePlotFloor = nan(height(lineage), 1);
lineage.ZeroEstimateCount = zeros(height(lineage), 1);
lineage.PlotSemantics = strings(height(lineage), 1);
for index = 1:numel(plotIds)
    match = string(lineage.PlotId) == plotIds(index);
    if nnz(match) ~= 1
        error("sixgr:conformance:FRCPlotLineageIdentityMismatch", ...
            "Expected exactly one lineage row for plot '%s'.", plotIds(index));
    end
    lineage.Metric(match) = plotMetrics(index);
    lineage.YScale(match) = plotYScales(index);
    lineage.ZeroEstimatePlotFloor(match) = plotFloors(index);
    lineage.ZeroEstimateCount(match) = zeroEstimateCounts(index);
    if plotYScales(index) == "log"
        lineage.PlotSemantics(match) = ...
            "observed_zero_retained_in_csv_and_rendered_at_disclosed_positive_floor";
    else
        lineage.PlotSemantics(match) = "direct_linear_render_of_persisted_values";
    end
end
sixgr.util.csvWriteTable(lineagePath, lineage, "PreserveSchema", true);
artifacts = struct( ...
    "PointCSV", string(masterCSV), ...
    "ImagePaths", imagePaths, ...
    "SubsetCSVs", subsetCSVs, ...
    "PlotLineageCSV", string(lineagePath));
end

function localValidatePointRows(T)
snr = localNumeric(T, "SNR_dB");
metric = localNumeric(T, "MetricEstimate");
lowerBound = localNumeric(T, "ConfidenceLower");
upperBound = localNumeric(T, "ConfidenceUpper");
target = localNumeric(T, "TargetFraction");
requiredSNR = localNumeric(T, "RequiredSNR_dB");
transportBlocks = localNumeric(T, "TransportBlocks");
if any(~isfinite(snr) | ~isfinite(metric) | ~isfinite(lowerBound) | ...
        ~isfinite(upperBound) | ~isfinite(target) | ...
        ~isfinite(requiredSNR) | ~isfinite(transportBlocks) | ...
        transportBlocks <= 0 | transportBlocks ~= fix(transportBlocks) | ...
        lowerBound > metric | metric > upperBound)
    error("sixgr:conformance:FRCPointArtifactValuesInvalid", ...
        ("FRC point artifacts require finite measured values, positive " + ...
        "integer TB counts, and confidence intervals containing the estimate."));
end
if any(localLogical(T.ProxyUsed)) || any(localLogical(T.FallbackUsed)) || ...
        any(lower(strtrim(string(T.ApproximationMode))) ~= "none")
    error("sixgr:conformance:FRCPointArtifactNotTruth", ...
        "Proxy or fallback rows cannot be published as FRC point evidence.");
end
end

function plotMeta = localPlotPointTable(T, imagePath)
[snr, order] = sort(localNumeric(T, "SNR_dB"));
metric = localNumeric(T, "MetricEstimate"); metric = metric(order);
lower = localNumeric(T, "ConfidenceLower"); lower = lower(order);
upper = localNumeric(T, "ConfidenceUpper"); upper = upper(order);
target = localNumeric(T, "TargetFraction"); target = target(order);
requiredSNR = localNumeric(T, "RequiredSNR_dB"); requiredSNR = requiredSNR(order);
tb = localNumeric(T, "TransportBlocks"); tb = tb(order);
frc = string(T.FRC(order(1)));
condition = string(T.Condition(order(1)));
metricName = string(T.Metric(order(1)));

fig = figure("Visible", "off", "Color", "white", ...
    "Position", [100 100 1600 900], "InvertHardcopy", "off");
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
useLogReliabilityScale = strcmpi(strtrim(metricName), ...
    "block_error_rate") && min(target) <= 0.01;
zeroEstimatePlotFloor = NaN;
plotMetric = metric;
plotLower = lower;
plotUpper = upper;
if useLogReliabilityScale
    positiveReference = [target(target > 0); metric(metric > 0); ...
        lower(lower > 0); upper(upper > 0)];
    zeroEstimatePlotFloor = 10 ^ (floor(log10(min(positiveReference))) - 1);
    zeroEstimatePlotFloor = max(zeroEstimatePlotFloor, realmin("double"));
    plotMetric = max(metric, zeroEstimatePlotFloor);
    plotLower = max(lower, zeroEstimatePlotFloor);
    plotUpper = max(upper, zeroEstimatePlotFloor);
end
negativeError = max(plotMetric - plotLower, 0);
positiveError = max(plotUpper - plotMetric, 0);
errorbar(ax, snr, plotMetric, negativeError, positiveError, "o-", ...
    "LineWidth", 2.2, "MarkerSize", 7, ...
    "Color", [0.05 0.47 0.44], "MarkerFaceColor", [0.05 0.47 0.44], ...
    "DisplayName", "Measured truth + confidence interval");
yline(ax, target(1), "--", "Target " + compose("%.3g", target(1)), ...
    "Color", [0.85 0.20 0.20], "LineWidth", 1.5, ...
    "LabelHorizontalAlignment", "left", "DisplayName", "Requirement target");
xline(ax, requiredSNR(1), ":", ...
    "Required SNR " + compose("%.3g dB", requiredSNR(1)), ...
    "Color", [0.25 0.35 0.70], "LineWidth", 1.5, ...
    "LabelVerticalAlignment", "bottom", "DisplayName", "Required SNR");
grid(ax, "on");
box(ax, "on");
xlabel(ax, "Applied SNR (dB)", "Color", [0.08 0.12 0.18]);
ylabel(ax, localMetricLabel(metricName), "Color", [0.08 0.12 0.18]);
title(ax, frc + " — " + condition, "Interpreter", "none", ...
    "Color", [0.06 0.09 0.14], "FontWeight", "bold");
subtitle(ax, sprintf("Runtime truth; %d TB across %d measured point(s)", ...
    sum(tb), height(T)), "Color", [0.20 0.25 0.33]);
if useLogReliabilityScale
    subtitle(ax, sprintf("Runtime truth; %d TB across %d measured point(s). " + ...
        "Observed zero shown at %.3g plotting floor; CSV value remains zero.", ...
        sum(tb), height(T), zeroEstimatePlotFloor), ...
        "Color", [0.20 0.25 0.33]);
end
lgd = legend(ax, "Location", "best");
set(lgd, "Color", "white", "TextColor", [0.08 0.12 0.18], ...
    "EdgeColor", [0.65 0.70 0.78]);
if useLogReliabilityScale
    set(ax, "YScale", "log");
    ylim(ax, [zeroEstimatePlotFloor 1]);
elseif all(metric >= 0 & metric <= 1) && all(lower >= 0 & upper <= 1)
    ylim(ax, [0 1]);
end
set(ax, "FontName", "Arial", "FontSize", 12, ...
    "LineWidth", 1, "Color", [0.985 0.99 1], ...
    "XColor", [0.12 0.16 0.22], "YColor", [0.12 0.16 0.22], ...
    "GridColor", [0.75 0.79 0.85], "GridAlpha", 0.55);
sixgr.visual.exportRasterAtomic(fig, string(imagePath), 150);
plotMeta = struct( ...
    "Metric", metricName, ...
    "YScale", localScaleName(useLogReliabilityScale), ...
    "ZeroEstimatePlotFloor", double(zeroEstimatePlotFloor), ...
    "ZeroEstimateCount", double(nnz(metric == 0)));
end

function value = localScaleName(useLogReliabilityScale)
if useLogReliabilityScale
    value = "log";
else
    value = "linear";
end
end

function label = localMetricLabel(metricName)
switch lower(strtrim(string(metricName)))
    case "fraction_of_maximum_throughput"
        label = "Fraction of maximum throughput";
    case "block_error_rate"
        label = "Block error rate (BLER)";
    otherwise
        label = char(strrep(string(metricName), "_", " "));
end
end

function values = localNumeric(T, name)
raw = T.(char(name));
if isnumeric(raw) || islogical(raw)
    values = double(raw(:));
else
    values = str2double(string(raw(:)));
end
end

function values = localLogical(raw)
if islogical(raw)
    values = raw(:);
elseif isnumeric(raw)
    values = isfinite(double(raw(:))) & double(raw(:)) ~= 0;
else
    values = ismember(lower(strtrim(string(raw(:)))), ...
        ["1","true","yes","on","pass","passed"]);
end
end

function token = localSafeToken(value)
token = regexprep(char(lower(string(value))), "[^a-z0-9_-]+", "_");
token = regexprep(token, "_+", "_");
token = regexprep(token, "^_+|_+$", "");
if isempty(token)
    error("sixgr:conformance:InvalidFRCPointArtifactToken", ...
        "FRC entry id '%s' cannot be converted to an artifact token.", value);
end
end
