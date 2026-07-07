function plotInfo = plotFixedSNRSweepCurves(runFolder, varargin)
%PLOTFIXEDSNRSWEEPCURVES Render audited fixed-SNR sweep plots from CSV evidence.

ip = inputParser;
ip.addRequired("runFolder", @(x)ischar(x) || (isstring(x) && isscalar(x)));
ip.parse(runFolder, varargin{:});

rootRunFolder = localResolveRootRunFolder(runFolder);
layout = sixgr.report.resultLayout(rootRunFolder);
sixgr.util.ensureFolder(layout.ReportImageDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);

files = struct( ...
    "Summary", fullfile(layout.ReportCSVDir, "fixed_snr_sweep_curve_summary.csv"), ...
    "DLBLER", fullfile(layout.ReportCSVDir, "dl_fixed_snr_bler_curve.csv"), ...
    "ULBLER", fullfile(layout.ReportCSVDir, "ul_fixed_snr_bler_curve.csv"), ...
    "DLBER", fullfile(layout.ReportCSVDir, "dl_fixed_snr_ber_curve.csv"), ...
    "ULBER", fullfile(layout.ReportCSVDir, "ul_fixed_snr_ber_curve.csv"));

summaryT = localReadOptionalTable(files.Summary);
dlBlerT = localReadOptionalTable(files.DLBLER);
ulBlerT = localReadOptionalTable(files.ULBLER);
dlBerT = localReadOptionalTable(files.DLBER);
ulBerT = localReadOptionalTable(files.ULBER);

lineageRows = repmat(localEmptyLineageRow(), 0, 1);
plotPaths = strings(0, 1);

[paths, rows] = localRenderProbabilityPlot(layout, dlBlerT, files.DLBLER, ...
    "dl_bler_vs_snr", "Downlink BLER vs Configured AWGN SNR", "BLER", ...
    "BLER", "BLER_CI_Low", "BLER_CI_High", true, true);
plotPaths = [plotPaths; paths]; %#ok<AGROW>
lineageRows = [lineageRows; rows]; %#ok<AGROW>

[paths, rows] = localRenderProbabilityPlot(layout, ulBlerT, files.ULBLER, ...
    "ul_bler_vs_snr", "Uplink BLER vs Configured AWGN SNR", "BLER", ...
    "BLER", "BLER_CI_Low", "BLER_CI_High", true, true);
plotPaths = [plotPaths; paths]; %#ok<AGROW>
lineageRows = [lineageRows; rows]; %#ok<AGROW>

[paths, rows] = localRenderProbabilityPlot(layout, dlBerT, files.DLBER, ...
    "dl_ber_vs_snr", "Downlink BER vs Configured AWGN SNR", "BER", ...
    "BER", "BER_CI_Low", "BER_CI_High", true, false);
plotPaths = [plotPaths; paths]; %#ok<AGROW>
lineageRows = [lineageRows; rows]; %#ok<AGROW>

[paths, rows] = localRenderProbabilityPlot(layout, ulBerT, files.ULBER, ...
    "ul_ber_vs_snr", "Uplink BER vs Configured AWGN SNR", "BER", ...
    "BER", "BER_CI_Low", "BER_CI_High", true, false);
plotPaths = [plotPaths; paths]; %#ok<AGROW>
lineageRows = [lineageRows; rows]; %#ok<AGROW>

[paths, rows] = localRenderThroughputPlot(layout, localFilterDirection(summaryT, "DL"), files.Summary, ...
    "dl_throughput_vs_snr", "Downlink Throughput and Goodput vs Configured AWGN SNR");
plotPaths = [plotPaths; paths]; %#ok<AGROW>
lineageRows = [lineageRows; rows]; %#ok<AGROW>

[paths, rows] = localRenderThroughputPlot(layout, localFilterDirection(summaryT, "UL"), files.Summary, ...
    "ul_throughput_vs_snr", "Uplink Throughput and Goodput vs Configured AWGN SNR");
plotPaths = [plotPaths; paths]; %#ok<AGROW>
lineageRows = [lineageRows; rows]; %#ok<AGROW>

[paths, rows] = localRenderMeasuredSINRPlot(layout, summaryT, files.Summary, ...
    "measured_sinr_vs_configured_snr", "Measured SINR vs Configured AWGN SNR");
plotPaths = [plotPaths; paths]; %#ok<AGROW>
lineageRows = [lineageRows; rows]; %#ok<AGROW>

[paths, rows] = localRenderTrialsPerPointPlot(layout, summaryT, files.Summary, ...
    "fixed_snr_trials_per_point", "Fixed-SNR Trials Per Point");
plotPaths = [plotPaths; paths]; %#ok<AGROW>
lineageRows = [lineageRows; rows]; %#ok<AGROW>

[paths, rows] = localRenderCIWidthPlot(layout, summaryT, files.Summary, ...
    "fixed_snr_ci_width_vs_snr", "Fixed-SNR BLER CI Width vs Configured AWGN SNR");
plotPaths = [plotPaths; paths]; %#ok<AGROW>
lineageRows = [lineageRows; rows]; %#ok<AGROW>

[paths, rows] = localRenderDashboardPlot(layout, summaryT, files.Summary, ...
    "fixed_snr_curve_dashboard", "Fixed-SNR Sweep Dashboard");
plotPaths = [plotPaths; paths]; %#ok<AGROW>
lineageRows = [lineageRows; rows]; %#ok<AGROW>

lineageTable = struct2table(lineageRows, "AsArray", true);
lineagePath = fullfile(layout.ReportCSVDir, "fixed_snr_plot_lineage.csv");
sixgr.analytics.writeAnalysisTable(lineagePath, lineageTable);

plotInfo = struct( ...
    "RootRunFolder", string(rootRunFolder), ...
    "Plots", plotPaths, ...
    "LineageCSV", string(lineagePath), ...
    "LineageTable", lineageTable);
end

function [plotPaths, lineageRows] = localRenderProbabilityPlot(layout, T, sourcePath, stem, plotTitle, yLabelText, yField, lowField, highField, semilogY, addTargetLine)
expectedPaths = localExpectedPlotPaths(layout, stem);
[sub, rowsUsed] = localFilterFiniteRows(T, "ConfiguredSNR_dB", yField);
if rowsUsed == 0
    plotPaths = strings(0, 1);
    lineageRows = localUnavailableLineage(expectedPaths, layout.Root, sourcePath, rowsUsed, ...
        "ConfiguredSNR_dB", yField, localTransformLabel(semilogY), yLabelText, "no_data");
    return;
end

fig = localNewFigure();
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
localPlotProbabilitySeries(ax, sub, yField, lowField, highField, semilogY);
if addTargetLine
    target = localFirstFinite(localNumericColumn(sub, "TargetBLER", NaN(height(sub), 1)), NaN);
    if isfinite(target)
        yline(ax, target, "--", sprintf("Target BLER %.3g", target), ...
            "Color", [0.45 0.45 0.45], "LabelHorizontalAlignment", "left");
    end
end
title(ax, plotTitle);
xlabel(ax, "Configured AWGN SNR / SINR label (dB)");
ylabel(ax, yLabelText);
grid(ax, "on");
legend(ax, "Location", "best");

plotPaths = localExportFigurePair(fig, expectedPaths);
lineageRows = localRenderedLineage(expectedPaths, plotPaths, layout.Root, sourcePath, rowsUsed, ...
    "ConfiguredSNR_dB", yField, localTransformLabel(semilogY), yLabelText);
end

function [plotPaths, lineageRows] = localRenderThroughputPlot(layout, T, sourcePath, stem, plotTitle)
expectedPaths = localExpectedPlotPaths(layout, stem);
[sub, rowsUsed] = localFilterFiniteRows(T, "ConfiguredSNR_dB", ["Throughput_Mbps", "Goodput_Mbps"]);
if rowsUsed == 0
    plotPaths = strings(0, 1);
    lineageRows = localUnavailableLineage(expectedPaths, layout.Root, sourcePath, rowsUsed, ...
        "ConfiguredSNR_dB", "Throughput_Mbps|Goodput_Mbps", "linear", "Mbps", "no_data");
    return;
end

fig = localNewFigure();
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
localPlotLinearSeries(ax, sub, "Throughput_Mbps", "Throughput");
localPlotLinearSeries(ax, sub, "Goodput_Mbps", "Goodput");
title(ax, plotTitle);
xlabel(ax, "Configured AWGN SNR / SINR label (dB)");
ylabel(ax, "Throughput / Goodput (Mbps)");
grid(ax, "on");
legend(ax, "Location", "best");

plotPaths = localExportFigurePair(fig, expectedPaths);
lineageRows = localRenderedLineage(expectedPaths, plotPaths, layout.Root, sourcePath, rowsUsed, ...
    "ConfiguredSNR_dB", "Throughput_Mbps|Goodput_Mbps", "linear", "Mbps");
end

function [plotPaths, lineageRows] = localRenderMeasuredSINRPlot(layout, T, sourcePath, stem, plotTitle)
expectedPaths = localExpectedPlotPaths(layout, stem);
if ~(istable(T) && ~isempty(T))
    plotPaths = strings(0, 1);
    lineageRows = localUnavailableLineage(expectedPaths, layout.Root, sourcePath, 0, ...
        "ConfiguredSNR_dB", "MeanMeasuredSINR_dB", "linear", "dB", "no_data");
    return;
end

rowsUsed = 0;
fig = localNewFigure();
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
dirs = ["DL", "UL"];
for i = 1:numel(dirs)
    sub = localFilterDirection(T, dirs(i));
    [sub, count] = localFilterFiniteRows(sub, "ConfiguredSNR_dB", "MeanMeasuredSINR_dB");
    rowsUsed = rowsUsed + count;
    if count == 0
        continue;
    end
    [x, order] = sort(double(sub.ConfiguredSNR_dB));
    y = double(sub.MeanMeasuredSINR_dB(order));
    plot(ax, x, y, localDirectionStyle(dirs(i)), "DisplayName", dirs(i), "LineWidth", 1.4, "MarkerSize", 7);
end
if rowsUsed == 0
    plotPaths = strings(0, 1);
    lineageRows = localUnavailableLineage(expectedPaths, layout.Root, sourcePath, rowsUsed, ...
        "ConfiguredSNR_dB", "MeanMeasuredSINR_dB", "linear", "dB", "no_data");
    return;
end

allConfigured = localNumericColumn(T, "ConfiguredSNR_dB", NaN(height(T), 1));
finiteConfigured = allConfigured(isfinite(allConfigured));
if ~isempty(finiteConfigured)
    minX = min(finiteConfigured);
    maxX = max(finiteConfigured);
    plot(ax, [minX maxX], [minX maxX], "k:", "DisplayName", "Identity");
end
title(ax, plotTitle);
xlabel(ax, "Configured AWGN SNR / SINR label (dB)");
ylabel(ax, "Measured Post-EQ SINR (dB)");
grid(ax, "on");
legend(ax, "Location", "best");

plotPaths = localExportFigurePair(fig, expectedPaths);
lineageRows = localRenderedLineage(expectedPaths, plotPaths, layout.Root, sourcePath, rowsUsed, ...
    "ConfiguredSNR_dB", "MeanMeasuredSINR_dB", "linear", "dB");
end

function [plotPaths, lineageRows] = localRenderTrialsPerPointPlot(layout, T, sourcePath, stem, plotTitle)
expectedPaths = localExpectedPlotPaths(layout, stem);
if ~(istable(T) && ~isempty(T))
    plotPaths = strings(0, 1);
    lineageRows = localUnavailableLineage(expectedPaths, layout.Root, sourcePath, 0, ...
        "ConfiguredSNR_dB", "TrialCount", "bar", "trials", "no_data");
    return;
end

rowsUsed = 0;
fig = localNewFigure();
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
dirs = ["DL", "UL"];
barWidth = 0.38;
for i = 1:numel(dirs)
    sub = localFilterDirection(T, dirs(i));
    if dirs(i) == "DL"
        trialField = "TrialCount";
    else
        trialField = "TrialCount";
    end
    [sub, count] = localFilterFiniteRows(sub, "ConfiguredSNR_dB", trialField);
    rowsUsed = rowsUsed + count;
    if count == 0
        continue;
    end
    [x, order] = sort(double(sub.ConfiguredSNR_dB));
    y = double(sub.TrialCount(order));
    offset = (i - (numel(dirs) + 1) / 2) * barWidth;
    bar(ax, x + offset, y, barWidth, "DisplayName", dirs(i));
end
if rowsUsed == 0
    plotPaths = strings(0, 1);
    lineageRows = localUnavailableLineage(expectedPaths, layout.Root, sourcePath, rowsUsed, ...
        "ConfiguredSNR_dB", "TrialCount", "bar", "trials", "no_data");
    return;
end

title(ax, plotTitle);
xlabel(ax, "Configured AWGN SNR / SINR label (dB)");
ylabel(ax, "Trials per point");
grid(ax, "on");
legend(ax, "Location", "best");

plotPaths = localExportFigurePair(fig, expectedPaths);
lineageRows = localRenderedLineage(expectedPaths, plotPaths, layout.Root, sourcePath, rowsUsed, ...
    "ConfiguredSNR_dB", "TrialCount", "bar", "trials");
end

function [plotPaths, lineageRows] = localRenderCIWidthPlot(layout, T, sourcePath, stem, plotTitle)
expectedPaths = localExpectedPlotPaths(layout, stem);
if ~(istable(T) && ~isempty(T))
    plotPaths = strings(0, 1);
    lineageRows = localUnavailableLineage(expectedPaths, layout.Root, sourcePath, 0, ...
        "ConfiguredSNR_dB", "BLER_CI_Width", "linear", "CI width", "no_data");
    return;
end

rowsUsed = 0;
fig = localNewFigure();
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
dirs = ["DL", "UL"];
for i = 1:numel(dirs)
    sub = localFilterDirection(T, dirs(i));
    [sub, count] = localFilterFiniteRows(sub, "ConfiguredSNR_dB", "BLER_CI_Width");
    rowsUsed = rowsUsed + count;
    if count == 0
        continue;
    end
    [x, order] = sort(double(sub.ConfiguredSNR_dB));
    y = double(sub.BLER_CI_Width(order));
    plot(ax, x, y, localDirectionStyle(dirs(i)), "DisplayName", dirs(i), "LineWidth", 1.4, "MarkerSize", 7);
end
if rowsUsed == 0
    plotPaths = strings(0, 1);
    lineageRows = localUnavailableLineage(expectedPaths, layout.Root, sourcePath, rowsUsed, ...
        "ConfiguredSNR_dB", "BLER_CI_Width", "linear", "CI width", "no_data");
    return;
end

title(ax, plotTitle);
xlabel(ax, "Configured AWGN SNR / SINR label (dB)");
ylabel(ax, "BLER CI width");
grid(ax, "on");
legend(ax, "Location", "best");

plotPaths = localExportFigurePair(fig, expectedPaths);
lineageRows = localRenderedLineage(expectedPaths, plotPaths, layout.Root, sourcePath, rowsUsed, ...
    "ConfiguredSNR_dB", "BLER_CI_Width", "linear", "CI width");
end

function [plotPaths, lineageRows] = localRenderDashboardPlot(layout, T, sourcePath, stem, plotTitle)
expectedPaths = localExpectedPlotPaths(layout, stem);
if ~(istable(T) && ~isempty(T))
    plotPaths = strings(0, 1);
    lineageRows = localUnavailableLineage(expectedPaths, layout.Root, sourcePath, 0, ...
        "ConfiguredSNR_dB", "BLER|BER|Throughput_Mbps|MeanMeasuredSINR_dB", "dashboard", "mixed", "no_data");
    return;
end

rowsUsed = sum(isfinite(localNumericColumn(T, "ConfiguredSNR_dB", NaN(height(T), 1))));
if rowsUsed == 0
    plotPaths = strings(0, 1);
    lineageRows = localUnavailableLineage(expectedPaths, layout.Root, sourcePath, rowsUsed, ...
        "ConfiguredSNR_dB", "BLER|BER|Throughput_Mbps|MeanMeasuredSINR_dB", "dashboard", "mixed", "no_data");
    return;
end

fig = localNewFigure([50 50 1200 780]);
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>

subplot(2, 2, 1);
hold on;
localPlotDirectionSummary(localFilterDirection(T, "DL"), "BLER", true, "DL");
localPlotDirectionSummary(localFilterDirection(T, "UL"), "BLER", true, "UL");
title("BLER");
xlabel("Configured AWGN SNR / SINR label (dB)");
ylabel("BLER");
grid on;
legend("Location", "best");

subplot(2, 2, 2);
hold on;
localPlotDirectionSummary(localFilterDirection(T, "DL"), "BER", true, "DL");
localPlotDirectionSummary(localFilterDirection(T, "UL"), "BER", true, "UL");
title("BER");
xlabel("Configured AWGN SNR / SINR label (dB)");
ylabel("BER");
grid on;
legend("Location", "best");

subplot(2, 2, 3);
hold on;
localPlotDirectionSummary(localFilterDirection(T, "DL"), "Throughput_Mbps", false, "DL");
localPlotDirectionSummary(localFilterDirection(T, "UL"), "Throughput_Mbps", false, "UL");
title("Throughput");
xlabel("Configured AWGN SNR / SINR label (dB)");
ylabel("Throughput (Mbps)");
grid on;
legend("Location", "best");

subplot(2, 2, 4);
hold on;
localPlotDirectionSummary(localFilterDirection(T, "DL"), "MeanMeasuredSINR_dB", false, "DL");
localPlotDirectionSummary(localFilterDirection(T, "UL"), "MeanMeasuredSINR_dB", false, "UL");
title("Measured SINR");
xlabel("Configured AWGN SNR / SINR label (dB)");
ylabel("Measured Post-EQ SINR (dB)");
grid on;
legend("Location", "best");

sgtitle(plotTitle);

plotPaths = localExportFigurePair(fig, expectedPaths);
lineageRows = localRenderedLineage(expectedPaths, plotPaths, layout.Root, sourcePath, rowsUsed, ...
    "ConfiguredSNR_dB", "BLER|BER|Throughput_Mbps|MeanMeasuredSINR_dB", "dashboard", "mixed");
end

function localPlotProbabilitySeries(ax, T, yField, lowField, highField, semilogY)
markers = ["o", "s", "d", "^", "v", ">", "<", "p"];
seriesMCS = unique(localNumericColumn(T, "MCS", NaN(height(T), 1)), "stable");
seriesMCS = seriesMCS(isfinite(seriesMCS));
if isempty(seriesMCS)
    seriesMCS = NaN;
end
for i = 1:numel(seriesMCS)
    if isfinite(seriesMCS(i))
        mask = abs(localNumericColumn(T, "MCS", NaN(height(T), 1)) - seriesMCS(i)) < 1e-9;
        label = "MCS " + string(round(seriesMCS(i)));
    else
        mask = true(height(T), 1);
        label = string(localFirstDirection(T));
    end
    sub = T(mask, :);
    if isempty(sub)
        continue;
    end
    [x, order] = sort(double(sub.ConfiguredSNR_dB));
    y = double(sub.(char(yField))(order));
    low = double(sub.(char(lowField))(order));
    high = double(sub.(char(highField))(order));
    if semilogY
        yFloor = 1e-6;
        y = max(y, yFloor);
        low = max(low, yFloor);
        high = max(high, yFloor);
    end
    loErr = max(0, y - low);
    hiErr = max(0, high - y);
    errorbar(ax, x, y, loErr, hiErr, "-" + markers(mod(i - 1, numel(markers)) + 1), ...
        "DisplayName", label, "LineWidth", 1.4, "MarkerSize", 7);
end
if semilogY
    set(ax, "YScale", "log");
end
end

function localPlotLinearSeries(ax, T, yField, labelPrefix)
markers = ["o", "s", "d", "^", "v", ">", "<", "p"];
seriesMCS = unique(localNumericColumn(T, "MCS", NaN(height(T), 1)), "stable");
seriesMCS = seriesMCS(isfinite(seriesMCS));
if isempty(seriesMCS)
    seriesMCS = NaN;
end
for i = 1:numel(seriesMCS)
    if isfinite(seriesMCS(i))
        mask = abs(localNumericColumn(T, "MCS", NaN(height(T), 1)) - seriesMCS(i)) < 1e-9;
        label = labelPrefix + " MCS " + string(round(seriesMCS(i)));
    else
        mask = true(height(T), 1);
        label = labelPrefix;
    end
    sub = T(mask, :);
    [sub, rowsUsed] = localFilterFiniteRows(sub, "ConfiguredSNR_dB", yField);
    if rowsUsed == 0
        continue;
    end
    [x, order] = sort(double(sub.ConfiguredSNR_dB));
    y = double(sub.(char(yField))(order));
    plot(ax, x, y, "-" + markers(mod(i - 1, numel(markers)) + 1), ...
        "DisplayName", label, "LineWidth", 1.4, "MarkerSize", 7);
end
end

function localPlotDirectionSummary(T, yField, semilogY, label)
[sub, rowsUsed] = localFilterFiniteRows(T, "ConfiguredSNR_dB", yField);
if rowsUsed == 0
    return;
end
[x, order] = sort(double(sub.ConfiguredSNR_dB));
y = double(sub.(char(yField))(order));
if semilogY
    y = max(y, 1e-6);
    semilogy(x, y, localDirectionStyle(label), "DisplayName", label, "LineWidth", 1.4, "MarkerSize", 7);
else
    plot(x, y, localDirectionStyle(label), "DisplayName", label, "LineWidth", 1.4, "MarkerSize", 7);
end
end

function [T, rowsUsed] = localFilterFiniteRows(T, xField, yFields)
rowsUsed = 0;
if ~(istable(T) && ~isempty(T))
    return;
end
x = localNumericColumn(T, xField, NaN(height(T), 1));
mask = isfinite(x);
for yField = reshape(string(yFields), 1, [])
    y = localNumericColumn(T, yField, NaN(height(T), 1));
    mask = mask & (isfinite(y) | maskWithAnyY(T, yFields));
end
if numel(string(yFields)) > 1
    mask = isfinite(x) & maskWithAnyY(T, yFields);
end
T = T(mask, :);
rowsUsed = height(T);
end

function mask = maskWithAnyY(T, yFields)
mask = false(height(T), 1);
for yField = reshape(string(yFields), 1, [])
    mask = mask | isfinite(localNumericColumn(T, yField, NaN(height(T), 1)));
end
end

function expectedPaths = localExpectedPlotPaths(layout, stem)
expectedPaths = [ ...
    string(fullfile(layout.ReportImageDir, stem + ".png"))
    string(fullfile(layout.ReportImageDir, stem + ".svg"))
    ];
end

function plotPaths = localExportFigurePair(fig, expectedPaths)
plotPaths = strings(0, 1);
for p = reshape(string(expectedPaths), 1, [])
    localSaveFigure(fig, p);
    if exist(p, "file") == 2
        plotPaths(end + 1, 1) = p; %#ok<AGROW>
    end
end
end

function localSaveFigure(fig, filePath)
sixgr.util.ensureDir(filePath);
[~, ~, ext] = fileparts(char(filePath));
try
    if strcmpi(ext, ".svg")
        exportgraphics(fig, filePath, "ContentType", "vector");
    else
        exportgraphics(fig, filePath, "Resolution", 160);
    end
catch
    if strcmpi(ext, ".svg")
        print(fig, char(filePath), "-dsvg");
    else
        print(fig, char(filePath), "-dpng", "-r160");
    end
end
end

function lineageRows = localRenderedLineage(expectedPaths, actualPaths, rootRunFolder, sourcePath, rowsUsed, xColumn, yColumn, transform, units)
lineageRows = repmat(localEmptyLineageRow(), numel(expectedPaths), 1);
for i = 1:numel(expectedPaths)
    pathValue = string(expectedPaths(i));
    info = sixgr.visual.inspectVisualArtifactFile(pathValue);
    existsNow = any(actualPaths == pathValue) && logical(info.exists);
    row = localEmptyLineageRow();
    row.PlotFile = localRelativePath(pathValue, rootRunFolder);
    row.SourceCSV = localRelativePath(sourcePath, rootRunFolder);
    row.SourceCSV_SHA256 = localFileSHA256(sourcePath);
    row.RowsUsed = double(rowsUsed);
    row.XColumn = string(xColumn);
    row.YColumn = string(yColumn);
    row.Transform = string(transform);
    row.Units = string(units);
    row.Status = localStatusToken(existsNow, "rendered", "render_failed");
    row.FailureCode = localStatusToken(existsNow, "", string(info.reason));
    lineageRows(i, 1) = row;
end
end

function lineageRows = localUnavailableLineage(expectedPaths, rootRunFolder, sourcePath, rowsUsed, xColumn, yColumn, transform, units, failureCode)
lineageRows = repmat(localEmptyLineageRow(), numel(expectedPaths), 1);
for i = 1:numel(expectedPaths)
    row = localEmptyLineageRow();
    row.PlotFile = localRelativePath(expectedPaths(i), rootRunFolder);
    row.SourceCSV = localRelativePath(sourcePath, rootRunFolder);
    row.SourceCSV_SHA256 = localFileSHA256(sourcePath);
    row.RowsUsed = double(rowsUsed);
    row.XColumn = string(xColumn);
    row.YColumn = string(yColumn);
    row.Transform = string(transform);
    row.Units = string(units);
    row.Status = "unavailable";
    row.FailureCode = string(failureCode);
    lineageRows(i, 1) = row;
end
end

function row = localEmptyLineageRow()
row = struct( ...
    "PlotFile", "", ...
    "SourceCSV", "", ...
    "SourceCSV_SHA256", "", ...
    "RowsUsed", NaN, ...
    "XColumn", "", ...
    "YColumn", "", ...
    "Transform", "", ...
    "Units", "", ...
    "Status", "", ...
    "FailureCode", "");
end

function style = localDirectionStyle(direction)
if upper(string(direction)) == "UL"
    style = "--s";
else
    style = "-o";
end
end

function direction = localFirstDirection(T)
if istable(T) && ~isempty(T) && ismember("Direction", string(T.Properties.VariableNames))
    direction = string(T.Direction(1));
else
    direction = "curve";
end
end

function rootRunFolder = localResolveRootRunFolder(runFolder)
rootRunFolder = char(string(runFolder));
if strlength(string(rootRunFolder)) == 0
    rootRunFolder = pwd;
    return;
end
[parent, leaf] = fileparts(rootRunFolder);
leaf = lower(string(leaf));
if any(leaf == ["air_interface", "reports", "control", "packet_flow", "system", "harq"])
    rootRunFolder = parent;
end
end

function T = localReadOptionalTable(pathValue)
if exist(pathValue, "file") ~= 2
    T = table();
    return;
end
try
    T = readtable(pathValue, "VariableNamingRule", "preserve", "TextType", "string");
catch
    T = table();
end
end

function fig = localNewFigure(position)
if nargin < 1
    position = [100 100 860 540];
end
fig = figure("Visible", "off", "Color", "w", "Position", position);
end

function T = localFilterDirection(T, direction)
if ~(istable(T) && ismember("Direction", string(T.Properties.VariableNames)))
    return;
end
T = T(string(T.Direction) == upper(string(direction)), :);
end

function values = localNumericColumn(T, varName, fallback)
n = 0;
if istable(T)
    n = height(T);
end
if n == 0
    values = zeros(0, 1);
    return;
end
values = repmat(double(fallback(1)), n, 1);
names = reshape(string(varName), 1, []);
for name = names
    if ismember(char(name), T.Properties.VariableNames)
        raw = T.(char(name));
        if isnumeric(raw) || islogical(raw)
            values = double(raw);
        else
            values = str2double(string(raw));
        end
        values = reshape(values, n, 1);
        return;
    end
end
end

function value = localFirstFinite(values, fallback)
values = double(values(:));
idx = find(isfinite(values), 1, "first");
if isempty(idx)
    value = fallback;
else
    value = values(idx);
end
end

function value = localFileSHA256(pathValue)
value = "";
pathValue = string(pathValue);
if strlength(pathValue) == 0 || exist(pathValue, "file") ~= 2
    return;
end
fid = fopen(pathValue, "r");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
data = fread(fid, Inf, "*uint8");
if isempty(data)
    return;
end
value = string(sixgr.util.sha256Hex(uint8(data(:))));
end

function rel = localRelativePath(pathValue, rootRunFolder)
pathValue = string(pathValue);
rootRunFolder = string(rootRunFolder);
normPath = replace(pathValue, "\", "/");
normRoot = replace(rootRunFolder, "\", "/");
if startsWith(normPath, normRoot + "/")
    rel = extractAfter(normPath, strlength(normRoot) + 1);
else
    rel = normPath;
end
end

function label = localTransformLabel(semilogY)
if semilogY
    label = "semilogy";
else
    label = "linear";
end
end

function out = localStatusToken(cond, trueValue, falseValue)
if cond
    out = string(trueValue);
else
    out = string(falseValue);
end
end
