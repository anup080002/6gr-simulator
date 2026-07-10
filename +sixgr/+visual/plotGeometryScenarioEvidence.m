function plotInfo = plotGeometryScenarioEvidence(runFolder, varargin)
%PLOTGEOMETRYSCENARIOEVIDENCE Render runtime geometry evidence plots.

ip = inputParser;
ip.addRequired("runFolder", @(x)ischar(x) || (isstring(x) && isscalar(x)));
ip.parse(runFolder, varargin{:});

rootRunFolder = localResolveRootRunFolder(runFolder);
layout = sixgr.report.resultLayout(rootRunFolder);
geometryImageDir = fullfile(rootRunFolder, "geometry", "image");
mobilityImageDir = fullfile(rootRunFolder, "mobility", "image");
reportImageDir = layout.ReportImageDir;
sixgr.util.ensureFolder(geometryImageDir);
sixgr.util.ensureFolder(mobilityImageDir);
sixgr.util.ensureFolder(reportImageDir);

topologyT = localReadOptionalTable(fullfile(rootRunFolder, "geometry", "csv", "topology_nodes.csv"));
trajT = localReadOptionalTable(fullfile(rootRunFolder, "geometry", "csv", "trajectory_geometry.csv"));
doppT = localReadOptionalTable(fullfile(rootRunFolder, "mobility", "csv", "doppler_reconciliation.csv"));
pathlossT = localReadOptionalTable(fullfile(rootRunFolder, "mobility", "csv", "pathloss_reconciliation.csv"));
sinrT = localReadOptionalTable(fullfile(layout.ReportCSVDir, "measured_sinr_timeseries.csv"));

generated = strings(0, 1);
skipped = repmat(struct("PlotStem", "", "Reason", ""), 0, 1);

[paths, reason] = localPlotTopologyMap(geometryImageDir, topologyT, trajT);
[generated, skipped] = localAccumulate(generated, skipped, paths, "topology_map", reason);
[paths, reason] = localPlotTrajectoryXY(geometryImageDir, trajT);
[generated, skipped] = localAccumulate(generated, skipped, paths, "ue_trajectory_xy", reason);
[paths, reason] = localPlotDistanceVsSlot(geometryImageDir, trajT);
[generated, skipped] = localAccumulate(generated, skipped, paths, "distance_vs_slot", reason);
[paths, reason] = localPlotDopplerVsSlot(mobilityImageDir, trajT, doppT);
[generated, skipped] = localAccumulate(generated, skipped, paths, "doppler_vs_slot", reason);
[paths, reason] = localPlotPathlossVsSlot(mobilityImageDir, trajT, pathlossT);
[generated, skipped] = localAccumulate(generated, skipped, paths, "pathloss_vs_slot", reason);
[paths, reason] = localPlotMeasuredSINRVsSlot(reportImageDir, sinrT);
[generated, skipped] = localAccumulate(generated, skipped, paths, "measured_sinr_vs_slot", reason);
[paths, reason] = localPlotMCSRankVsSlot(reportImageDir, sinrT);
[generated, skipped] = localAccumulate(generated, skipped, paths, "mcs_rank_vs_slot", reason);
[paths, reason] = localPlotGeometryDashboard(reportImageDir, topologyT, trajT, sinrT);
[generated, skipped] = localAccumulate(generated, skipped, paths, "geometry_scenario_dashboard", reason);

plotInfo = struct();
plotInfo.RootRunFolder = string(rootRunFolder);
plotInfo.GeneratedPlots = generated;
plotInfo.GeneratedCount = double(numel(generated));
plotInfo.Skipped = skipped;
end

function [generated, skipped] = localAccumulate(generated, skipped, paths, stem, reason)
if isempty(paths)
    skipped(end+1, 1) = struct("PlotStem", string(stem), "Reason", string(reason)); %#ok<AGROW>
else
    generated = [generated; paths(:)]; %#ok<AGROW>
end
end

function [paths, reason] = localPlotTopologyMap(outDir, topologyT, trajT)
paths = strings(0, 1);
reason = "";
if ~(istable(topologyT) && height(topologyT) > 0)
    reason = "topology_nodes_missing_or_empty";
    return;
end

fig = localNewFigure([100 100 840 620]);
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");

nodeClass = upper(localColumnText(topologyT, "NodeClass", strings(height(topologyT), 1)));
cellMask = nodeClass == "CELL";
ueMask = nodeClass == "UE";
if any(cellMask)
    scatter(ax, double(topologyT.X_m(cellMask)), double(topologyT.Y_m(cellMask)), 90, "s", ...
        "filled", "DisplayName", "Cells");
end
if any(ueMask)
    scatter(ax, double(topologyT.X_m(ueMask)), double(topologyT.Y_m(ueMask)), 70, "o", ...
        "filled", "DisplayName", "UE initial");
end
if istable(trajT) && height(trajT) > 0
    ueVals = unique(localFirstAvailableNumeric(trajT, ["UeId","UEID"]));
    ueVals = ueVals(isfinite(ueVals));
    for i = 1:numel(ueVals)
        mask = localFirstAvailableNumeric(trajT, ["UeId","UEID"]) == ueVals(i);
        slice = sortrows(trajT(mask, :), "CanonicalSlot");
        plot(ax, double(slice.X_m), double(slice.Y_m), "-", "LineWidth", 1.2, ...
            "DisplayName", sprintf("UE %d path", round(ueVals(i))));
    end
end
title(ax, "Topology Map");
xlabel(ax, "X (m)");
ylabel(ax, "Y (m)");
axis(ax, "equal");
grid(ax, "on");
legend(ax, "Location", "best");

paths = localExportFigurePair(fig, outDir, "topology_map");
end

function [paths, reason] = localPlotTrajectoryXY(outDir, trajT)
paths = strings(0, 1);
reason = "";
if ~(istable(trajT) && height(trajT) > 0)
    reason = "trajectory_geometry_missing_or_empty";
    return;
end

fig = localNewFigure();
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
ueVals = unique(localFirstAvailableNumeric(trajT, ["UeId","UEID"]));
ueVals = ueVals(isfinite(ueVals));
if isempty(ueVals)
    reason = "trajectory_missing_ue_ids";
    return;
end
for i = 1:numel(ueVals)
    mask = localFirstAvailableNumeric(trajT, ["UeId","UEID"]) == ueVals(i);
    slice = sortrows(trajT(mask, :), "CanonicalSlot");
    plot(ax, double(slice.X_m), double(slice.Y_m), "-o", "LineWidth", 1.1, ...
        "MarkerSize", 4, "DisplayName", sprintf("UE %d", round(ueVals(i))));
end
title(ax, "UE Trajectory XY");
xlabel(ax, "X (m)");
ylabel(ax, "Y (m)");
axis(ax, "equal");
grid(ax, "on");
legend(ax, "Location", "best");

paths = localExportFigurePair(fig, outDir, "ue_trajectory_xy");
end

function [paths, reason] = localPlotDistanceVsSlot(outDir, trajT)
paths = strings(0, 1);
reason = "";
if ~(istable(trajT) && height(trajT) > 0)
    reason = "trajectory_geometry_missing_or_empty";
    return;
end

fig = localNewFigure();
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
ueVals = unique(localFirstAvailableNumeric(trajT, ["UeId","UEID"]));
ueVals = ueVals(isfinite(ueVals));
for i = 1:numel(ueVals)
    mask = localFirstAvailableNumeric(trajT, ["UeId","UEID"]) == ueVals(i);
    slice = sortrows(trajT(mask, :), "CanonicalSlot");
    plot(ax, double(slice.CanonicalSlot), double(slice.Distance3D_m), "-o", ...
        "LineWidth", 1.1, "MarkerSize", 4, "DisplayName", sprintf("UE %d", round(ueVals(i))));
end
title(ax, "Distance vs Slot");
xlabel(ax, "Canonical Slot");
ylabel(ax, "Distance3D (m)");
grid(ax, "on");
legend(ax, "Location", "best");

paths = localExportFigurePair(fig, outDir, "distance_vs_slot");
end

function [paths, reason] = localPlotDopplerVsSlot(outDir, trajT, doppT)
paths = strings(0, 1);
reason = "";
sourceT = trajT;
slotField = "CanonicalSlot";
if ~(istable(sourceT) && height(sourceT) > 0 && localHasColumn(sourceT, "ExpectedDopplerHz"))
    sourceT = doppT;
end
if ~(istable(sourceT) && height(sourceT) > 0)
    reason = "doppler_evidence_missing_or_empty";
    return;
end

fig = localNewFigure();
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
tiledlayout(fig, 2, 1, "TileSpacing", "compact", "Padding", "compact");

nexttile;
hold on;
localPlotByUE(sourceT, slotField, "ExpectedDopplerHz", "--", "Expected");
title("Expected Doppler vs Slot");
xlabel("Canonical Slot");
ylabel("Expected Doppler (Hz)");
grid on;
legend("Location", "best");

nexttile;
hold on;
localPlotByUE(sourceT, slotField, "AppliedDopplerHz", "-", "Applied");
title("Applied Doppler vs Slot");
xlabel("Canonical Slot");
ylabel("Applied Doppler (Hz)");
grid on;
legend("Location", "best");

paths = localExportFigurePair(fig, outDir, "doppler_vs_slot");
end

function [paths, reason] = localPlotPathlossVsSlot(outDir, trajT, pathlossT)
paths = strings(0, 1);
reason = "";
sourceT = trajT;
valueField = "Pathloss_dB";
if ~(istable(sourceT) && height(sourceT) > 0 && localHasColumn(sourceT, valueField))
    sourceT = pathlossT;
    valueField = "ObservedPathloss_dB";
end
if ~(istable(sourceT) && height(sourceT) > 0)
    reason = "pathloss_evidence_missing_or_empty";
    return;
end

fig = localNewFigure();
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
localPlotByUE(sourceT, "CanonicalSlot", valueField, "-", "Pathloss");
title(ax, "Pathloss vs Slot");
xlabel(ax, "Canonical Slot");
ylabel(ax, "Pathloss (dB)");
grid(ax, "on");
legend(ax, "Location", "best");

paths = localExportFigurePair(fig, outDir, "pathloss_vs_slot");
end

function [paths, reason] = localPlotMeasuredSINRVsSlot(outDir, sinrT)
paths = strings(0, 1);
reason = "";
if ~(istable(sinrT) && height(sinrT) > 0)
    reason = "measured_sinr_timeseries_missing_or_empty";
    return;
end

fig = localNewFigure();
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
dirs = unique(upper(localColumnText(sinrT, "Direction", strings(height(sinrT), 1))), "stable");
dirs = dirs(strlength(dirs) > 0);
if isempty(dirs)
    reason = "measured_sinr_direction_missing";
    return;
end
for i = 1:numel(dirs)
    mask = upper(localColumnText(sinrT, "Direction", strings(height(sinrT), 1))) == dirs(i);
    slice = sortrows(sinrT(mask, :), "CanonicalSlot");
    plot(ax, double(slice.CanonicalSlot), double(slice.MeasuredSINR_dB), localDirectionStyle(dirs(i)), ...
        "LineWidth", 1.2, "MarkerSize", 5, "DisplayName", dirs(i));
end
title(ax, "Measured SINR vs Slot");
xlabel(ax, "Canonical Slot");
ylabel(ax, "Measured SINR (dB)");
grid(ax, "on");
legend(ax, "Location", "best");

paths = localExportFigurePair(fig, outDir, "measured_sinr_vs_slot");
end

function [paths, reason] = localPlotMCSRankVsSlot(outDir, sinrT)
paths = strings(0, 1);
reason = "";
if ~(istable(sinrT) && height(sinrT) > 0)
    reason = "measured_sinr_timeseries_missing_or_empty";
    return;
end

fig = localNewFigure([120 120 900 620]);
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
tiledlayout(fig, 2, 1, "TileSpacing", "compact", "Padding", "compact");

nexttile;
hold on;
localPlotByDirection(sinrT, "CanonicalSlot", "MCS");
title("MCS vs Slot");
xlabel("Canonical Slot");
ylabel("MCS");
grid on;
legend("Location", "best");

nexttile;
hold on;
rankField = "Rank";
if ~localHasColumn(sinrT, rankField)
    rankField = "Layers";
end
localPlotByDirection(sinrT, "CanonicalSlot", rankField);
title("Rank / Layers vs Slot");
xlabel("Canonical Slot");
ylabel("Rank / Layers");
grid on;
legend("Location", "best");

paths = localExportFigurePair(fig, outDir, "mcs_rank_vs_slot");
end

function [paths, reason] = localPlotGeometryDashboard(outDir, topologyT, trajT, sinrT)
paths = strings(0, 1);
reason = "";
if ~(istable(trajT) && height(trajT) > 0)
    reason = "trajectory_geometry_missing_or_empty";
    return;
end

fig = localNewFigure([60 60 1200 780]);
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
tiledlayout(fig, 2, 2, "TileSpacing", "compact", "Padding", "compact");

nexttile;
hold on;
if istable(topologyT) && height(topologyT) > 0
    nodeClass = upper(localColumnText(topologyT, "NodeClass", strings(height(topologyT), 1)));
    cellMask = nodeClass == "CELL";
    ueMask = nodeClass == "UE";
    if any(cellMask)
        scatter(double(topologyT.X_m(cellMask)), double(topologyT.Y_m(cellMask)), 80, "s", "filled");
    end
    if any(ueMask)
        scatter(double(topologyT.X_m(ueMask)), double(topologyT.Y_m(ueMask)), 60, "o", "filled");
    end
end
localPlotTrajectoryLines(trajT);
title("Topology / Trajectory");
xlabel("X (m)");
ylabel("Y (m)");
axis equal;
grid on;

nexttile;
hold on;
localPlotByUE(trajT, "CanonicalSlot", "Distance3D_m", "-", "Distance");
title("Distance vs Slot");
xlabel("Canonical Slot");
ylabel("Distance3D (m)");
grid on;

nexttile;
hold on;
localPlotByUE(trajT, "CanonicalSlot", "AppliedDopplerHz", "-", "Applied Doppler");
title("Applied Doppler vs Slot");
xlabel("Canonical Slot");
ylabel("Applied Doppler (Hz)");
grid on;

nexttile;
hold on;
if istable(sinrT) && height(sinrT) > 0
    localPlotByDirection(sinrT, "CanonicalSlot", "MeasuredSINR_dB");
end
title("Measured SINR vs Slot");
xlabel("Canonical Slot");
ylabel("Measured SINR (dB)");
grid on;
legend("Location", "best");

paths = localExportFigurePair(fig, outDir, "geometry_scenario_dashboard");
end

function localPlotByUE(T, xField, yField, lineStyle, labelPrefix)
ueVals = unique(localFirstAvailableNumeric(T, ["UeId","UEID"]));
ueVals = ueVals(isfinite(ueVals));
for i = 1:numel(ueVals)
    mask = localFirstAvailableNumeric(T, ["UeId","UEID"]) == ueVals(i);
    slice = sortrows(T(mask, :), xField);
    x = localFirstAvailableNumeric(slice, xField);
    y = localFirstAvailableNumeric(slice, yField);
    maskFinite = isfinite(x) & isfinite(y);
    if ~any(maskFinite)
        continue;
    end
    plot(x(maskFinite), y(maskFinite), lineStyle, "LineWidth", 1.1, "Marker", "o", ...
        "MarkerSize", 4, "DisplayName", sprintf("%s UE %d", labelPrefix, round(ueVals(i))));
end
end

function localPlotByDirection(T, xField, yField)
dirs = unique(upper(localColumnText(T, "Direction", strings(height(T), 1))), "stable");
dirs = dirs(strlength(dirs) > 0);
for i = 1:numel(dirs)
    mask = upper(localColumnText(T, "Direction", strings(height(T), 1))) == dirs(i);
    slice = sortrows(T(mask, :), xField);
    x = localFirstAvailableNumeric(slice, xField);
    y = localFirstAvailableNumeric(slice, yField);
    maskFinite = isfinite(x) & isfinite(y);
    if ~any(maskFinite)
        continue;
    end
    plot(x(maskFinite), y(maskFinite), localDirectionStyle(dirs(i)), ...
        "LineWidth", 1.1, "MarkerSize", 4, "DisplayName", dirs(i));
end
end

function localPlotTrajectoryLines(trajT)
ueVals = unique(localFirstAvailableNumeric(trajT, ["UeId","UEID"]));
ueVals = ueVals(isfinite(ueVals));
for i = 1:numel(ueVals)
    mask = localFirstAvailableNumeric(trajT, ["UeId","UEID"]) == ueVals(i);
    slice = sortrows(trajT(mask, :), "CanonicalSlot");
    plot(double(slice.X_m), double(slice.Y_m), "-", "LineWidth", 1.1, ...
        "DisplayName", sprintf("UE %d path", round(ueVals(i))));
end
end

function style = localDirectionStyle(direction)
if upper(string(direction)) == "UL"
    style = "--s";
else
    style = "-o";
end
end

function values = localFirstAvailableNumeric(T, names)
for name = reshape(string(names), 1, [])
    if localHasColumn(T, name)
        values = localNumericColumn(T, name, NaN(height(T), 1));
        return;
    end
end
values = NaN(height(T), 1);
end

function values = localNumericColumn(T, name, fallback)
if ~(istable(T) && height(T) > 0)
    values = zeros(0, 1);
    return;
end
if localHasColumn(T, name)
    raw = T.(char(name));
    if isnumeric(raw) || islogical(raw)
        values = double(raw);
    else
        values = str2double(string(raw));
    end
    values = reshape(values, [], 1);
else
    values = repmat(double(fallback(1)), height(T), 1);
end
end

function values = localColumnText(T, name, fallback)
if ~(istable(T) && height(T) > 0)
    values = strings(0, 1);
    return;
end
if localHasColumn(T, name)
    values = string(T.(char(name)));
    values = reshape(values, [], 1);
else
    values = repmat(string(fallback(1)), height(T), 1);
end
end

function tf = localHasColumn(T, name)
tf = istable(T) && ismember(string(name), string(T.Properties.VariableNames));
end

function paths = localExportFigurePair(fig, outDir, stem)
paths = strings(0, 1);
for ext = [".png", ".svg"]
    filePath = string(fullfile(outDir, stem + ext));
    localSaveFigure(fig, filePath);
    if exist(filePath, "file") == 2
        paths(end+1, 1) = filePath; %#ok<AGROW>
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

function fig = localNewFigure(position)
if nargin < 1
    position = [100 100 860 540];
end
fig = figure("Visible", "off", "Color", "w", "Position", position);
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

function rootRunFolder = localResolveRootRunFolder(runFolder)
rootRunFolder = char(string(runFolder));
if strlength(string(rootRunFolder)) == 0
    rootRunFolder = pwd;
    return;
end
while true
    [parentPath, leaf] = fileparts(rootRunFolder);
    leaf = lower(string(leaf));
    if any(leaf == ["geometry", "mobility", "reports", "air_interface", "meta"])
        rootRunFolder = parentPath;
    else
        break;
    end
end
end
