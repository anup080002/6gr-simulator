function results = generateMeasuredSINRPlots(cfg, runTag, varargin)
%GENERATEMEASUREDSINRPLOTS Plot runtime measured-SINR artifacts.

if nargin < 2
    runTag = "";
end

ip = inputParser;
ip.addParameter("MinimumTrialsPerBin", 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
ip.parse(varargin{:});
opt = ip.Results;

runDir = localResolveRunDir(cfg);
layout = sixgr.report.resultLayout(runDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.ReportImageDir);
sixgr.util.ensureFolder(layout.AirInterfaceImageDir);
% These plots have one canonical publication location under reports/image.
% Remove legacy mirrors so re-finalization cannot preserve duplicate evidence.
for legacyName = ["bler_vs_measured_sinr.png", "ber_vs_measured_sinr.png", ...
        "throughput_vs_measured_sinr.png"]
    localDeleteIfExists(fullfile(layout.AirInterfaceImageDir, legacyName));
end

tables = struct();
tables.DLBler = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "dl_measured_sinr_bler_curve.csv"));
tables.ULBler = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "ul_measured_sinr_bler_curve.csv"));
tables.DLThroughput = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "dl_measured_sinr_throughput_curve.csv"));
tables.ULThroughput = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "ul_measured_sinr_throughput_curve.csv"));
tables.Distribution = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "measured_sinr_distribution.csv"));
tables.DistanceScatter = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "distance_vs_sinr.csv"));

paths = strings(0, 1);
paths(end+1, 1) = localPlotBLER(layout, tables.DLBler, tables.ULBler, double(opt.MinimumTrialsPerBin));
paths(end+1, 1) = localPlotBER(layout, tables.DLBler, tables.ULBler, double(opt.MinimumTrialsPerBin));
paths(end+1, 1) = localPlotThroughput(layout, tables.DLThroughput, tables.ULThroughput, double(opt.MinimumTrialsPerBin));
paths(end+1, 1) = localPlotDistribution(layout, tables.Distribution);
paths(end+1, 1) = localPlotDistanceScatter(layout, tables.DistanceScatter);

lineage = localWritePlotLineage(layout, paths);

results = struct("Ok", true, "RunDir", string(runDir), "RunTag", string(runTag), ...
    "Plots", paths, "LineageCSV", string(lineage.Path), "LineageTable", lineage.Table);
end

function path = localPlotBLER(layout, dl, ul, minTrials)
path = fullfile(layout.ReportImageDir, "bler_vs_measured_sinr.png");
localDeleteIfExists(path);
if ~localHasEligibleRows(dl, "BLER", minTrials) && ~localHasEligibleRows(ul, "BLER", minTrials)
    path = "";
    return;
end
fig = localNewFigure();
hold on;
localPlotBlerTable(dl, "DL", "-", minTrials);
localPlotBlerTable(ul, "UL", "--", minTrials);
title("BLER vs Measured Post-Equalisation SINR");
xlabel("Measured post-EQ SINR (dB)");
ylabel("BLER");
ylim([0 1]);
grid on;
legend("Location", "best");
localSaveFigure(fig, path);
close(fig);
end

function localPlotBlerTable(T, direction, style, minTrials)
if ~(istable(T) && height(T) > 0)
    return;
end
T = T(localToDouble(T.TrialCount) >= minTrials, :);
if isempty(T)
    return;
end
ues = localUniqueUELabels(T.UEIndex);
for i = 1:numel(ues)
    ue = ues(i);
    mask = localUEMask(T.UEIndex, ue);
    sub = T(mask, :);
    if isempty(sub)
        continue;
    end
    [x, order] = sort(localToDouble(sub.PostEqSINR_dB_BinCenter));
    y = localToDouble(sub.BLER);
    lo = y - localToDouble(sub.BLER_CI_Low);
    hi = localToDouble(sub.BLER_CI_High) - y;
    y = y(order);
    lo = max(0, lo(order));
    hi = max(0, hi(order));
    marker = localMarkerForUE(ue);
    label = direction + " " + localUELabel(ue);
    errorbar(x, y, lo, hi, style + marker, "DisplayName", label, "LineWidth", localLineWidth(ue));
end
end

function path = localPlotBER(layout, dl, ul, minTrials)
path = fullfile(layout.ReportImageDir, "ber_vs_measured_sinr.png");
localDeleteIfExists(path);
if ~localHasEligibleRows(dl, "BER", minTrials) && ~localHasEligibleRows(ul, "BER", minTrials)
    path = "";
    return;
end
fig = localNewFigure();
hold on;
localPlotScalarCurve(dl, "DL", "BER", "-", minTrials);
localPlotScalarCurve(ul, "UL", "BER", "--", minTrials);
set(gca, "YScale", "log");
title("BER vs Measured Post-Equalisation SINR");
xlabel("Measured post-EQ SINR (dB)");
ylabel("BER");
ylim([1e-5 1]);
grid on;
legend("Location", "best");
localSaveFigure(fig, path);
close(fig);
end

function path = localPlotThroughput(layout, dl, ul, minTrials)
path = fullfile(layout.ReportImageDir, "throughput_vs_measured_sinr.png");
localDeleteIfExists(path);
if ~localHasEligibleRows(dl, "Goodput_Mbps_mean", minTrials) && ...
        ~localHasEligibleRows(ul, "Goodput_Mbps_mean", minTrials)
    path = "";
    return;
end
fig = localNewFigure();
hold on;
localPlotThroughputTable(dl, "DL", "-", minTrials);
localPlotThroughputTable(ul, "UL", "--", minTrials);
title("Goodput vs Measured Post-Equalisation SINR");
xlabel("Measured post-EQ SINR (dB)");
ylabel("Goodput (Mbps)");
grid on;
legend("Location", "best");
localSaveFigure(fig, path);
close(fig);
end

function localPlotThroughputTable(T, direction, style, minTrials)
if ~(istable(T) && height(T) > 0)
    return;
end
T = T(localToDouble(T.TrialCount) >= minTrials, :);
if isempty(T)
    return;
end
ues = localUniqueUELabels(T.UEIndex);
for i = 1:numel(ues)
    ue = ues(i);
    mask = localUEMask(T.UEIndex, ue);
    sub = T(mask, :);
    [x, order] = sort(localToDouble(sub.PostEqSINR_dB_BinCenter));
    y = localToDouble(sub.Goodput_Mbps_mean);
    marker = localMarkerForUE(ue);
    plot(x, y(order), style + marker, "DisplayName", direction + " " + localUELabel(ue), "LineWidth", localLineWidth(ue));
end
end

function localPlotScalarCurve(T, direction, yColumn, style, minTrials)
if ~(istable(T) && height(T) > 0) || ~localHasColumn(T, yColumn)
    return;
end
T = T(localToDouble(T.TrialCount) >= minTrials, :);
if isempty(T)
    return;
end
ues = localUniqueUELabels(T.UEIndex);
for i = 1:numel(ues)
    ue = ues(i);
    mask = localUEMask(T.UEIndex, ue);
    sub = T(mask, :);
    [x, order] = sort(localToDouble(sub.PostEqSINR_dB_BinCenter));
    y = max(localToDouble(sub.(char(yColumn))), 1e-5);
    plot(x, y(order), style + localMarkerForUE(ue), "DisplayName", direction + " " + localUELabel(ue), "LineWidth", localLineWidth(ue));
end
end

function path = localPlotDistribution(layout, T)
path = fullfile(layout.ReportImageDir, "measured_sinr_distribution.png");
localDeleteIfExists(path);
if ~(istable(T) && height(T) > 0 && ...
        all(ismember(["Direction","UEIndex","PostEqSINR_dB_BinCenter","Fraction"], ...
        string(T.Properties.VariableNames))) && ...
        any(isfinite(localToDouble(T.PostEqSINR_dB_BinCenter)) & isfinite(localToDouble(T.Fraction))))
    path = "";
    return;
end
fig = localNewFigure();
dirs = unique(string(T.Direction), "stable");
ues = localUniqueUELabels(T.UEIndex);
nSeries = max(1, numel(dirs) * numel(ues));
seriesIdx = 0;
hold on;
for d = 1:numel(dirs)
    for i = 1:numel(ues)
        ue = ues(i);
        sub = T(strcmpi(string(T.Direction), dirs(d)) & localUEMask(T.UEIndex, ue), :);
        if isempty(sub)
            continue;
        end
        seriesIdx = seriesIdx + 1;
        [x, order] = sort(localToDouble(sub.PostEqSINR_dB_BinCenter));
        y = localToDouble(sub.Fraction);
        offset = (seriesIdx - (nSeries + 1) / 2) * 0.12;
        bar(x + offset, y(order), 0.12, "DisplayName", dirs(d) + " " + localUELabel(ue));
    end
end
legend("Location", "best");
title("Measured SINR distribution by UE - geometry-derived");
xlabel("Measured post-EQ SINR (dB)");
ylabel("Trial fraction");
grid on;
localSaveFigure(fig, path);
close(fig);
end

function path = localPlotDistanceScatter(layout, T)
path = fullfile(layout.ReportImageDir, "distance_vs_sinr.png");
localDeleteIfExists(path);
if ~(istable(T) && height(T) > 0 && ...
        all(ismember(["UEIndex","PropagationDistance_m","PostEqSINR_dB"], ...
        string(T.Properties.VariableNames))) && ...
        any(isfinite(localToDouble(T.PropagationDistance_m)) & isfinite(localToDouble(T.PostEqSINR_dB))))
    path = "";
    return;
end
fig = localNewFigure();
hold on;
ues = localUniqueUELabels(T.UEIndex);
for i = 1:numel(ues)
    ue = ues(i);
    sub = T(localUEMask(T.UEIndex, ue), :);
    scatter(localToDouble(sub.PropagationDistance_m), localToDouble(sub.PostEqSINR_dB), 28, "filled", "DisplayName", localUELabel(ue));
    if localHasColumn(sub, "LargeScaleSINR_dB")
        scatter(localToDouble(sub.PropagationDistance_m), localToDouble(sub.LargeScaleSINR_dB), 28, "o", "DisplayName", localUELabel(ue) + " large-scale");
    end
end
yline(-10, "--", "PBCH min");
yline(15, "--", "PDSCH target");
legend("Location", "best");
title("UE propagation distance vs measured SINR");
xlabel("Propagation distance (m)");
ylabel("Measured post-EQ SINR (dB)");
grid on;
localSaveFigure(fig, path);
close(fig);
end

function tf = localHasEligibleRows(T, valueColumn, minTrials)
tf = istable(T) && height(T) > 0 && ...
    all(ismember(["TrialCount","PostEqSINR_dB_BinCenter", string(valueColumn)], ...
    string(T.Properties.VariableNames)));
if ~tf
    return;
end
tf = any(localToDouble(T.TrialCount) >= minTrials & ...
    isfinite(localToDouble(T.PostEqSINR_dB_BinCenter)) & ...
    isfinite(localToDouble(T.(char(valueColumn)))));
end

function localDeleteIfExists(pathValue)
if exist(char(string(pathValue)), "file") == 2
    delete(char(string(pathValue)));
end
end

function fig = localNewFigure()
fig = figure("Visible", "off", "Color", "w");
end

function localSaveFigure(fig, path)
sixgr.util.ensureDir(path);
try
    exportgraphics(fig, path, "Resolution", 140);
catch
    print(fig, path, "-dpng", "-r140");
end
end

function lineage = localWritePlotLineage(layout, paths)
plotIds = [
    "bler_vs_measured_sinr"
    "ber_vs_measured_sinr"
    "throughput_vs_measured_sinr"
    "measured_sinr_distribution"
    "distance_vs_sinr"
    ];
sourceCsv = [
    "air_interface/csv/dl_measured_sinr_bler_curve.csv|air_interface/csv/ul_measured_sinr_bler_curve.csv"
    "air_interface/csv/dl_measured_sinr_bler_curve.csv|air_interface/csv/ul_measured_sinr_bler_curve.csv"
    "air_interface/csv/dl_measured_sinr_throughput_curve.csv|air_interface/csv/ul_measured_sinr_throughput_curve.csv"
    "air_interface/csv/measured_sinr_distribution.csv"
    "air_interface/csv/distance_vs_sinr.csv"
    ];
generator = [
    "sixgr.analytics.generateMeasuredSINRPlots.localPlotBLER"
    "sixgr.analytics.generateMeasuredSINRPlots.localPlotBER"
    "sixgr.analytics.generateMeasuredSINRPlots.localPlotThroughput"
    "sixgr.analytics.generateMeasuredSINRPlots.localPlotDistribution"
    "sixgr.analytics.generateMeasuredSINRPlots.localPlotDistanceScatter"
    ];
xVariable = [
    "PostEqSINR_dB_BinCenter"
    "PostEqSINR_dB_BinCenter"
    "PostEqSINR_dB_BinCenter"
    "PostEqSINR_dB_BinCenter"
    "PropagationDistance_m"
    ];
yVariables = [
    "BLER|BLER_CI_Low|BLER_CI_High"
    "BER"
    "Goodput_Mbps_mean"
    "Fraction"
    "PostEqSINR_dB|LargeScaleSINR_dB"
    ];

rows = repmat(struct("PlotId", "", "ImagePath", "", "SourceCSV", "", ...
    "GeneratorFunction", "", "XVariable", "", "YVariables", "", ...
    "ImageExists", false, "SourceExists", false, "SourceRowCount", NaN, ...
    "TruthStatus", "", "LineageStatus", ""), numel(plotIds), 1);
for i = 1:numel(plotIds)
    imagePath = string(paths(min(i, numel(paths))));
    relImage = "reports/image/" + plotIds(i) + ".png";
    [sourceExists, sourceRows] = localSourceStats(layout.Root, sourceCsv(i));
    imageExists = strlength(imagePath) > 0 && exist(char(imagePath), "file") == 2;
    rows(i) = struct("PlotId", plotIds(i), ...
        "ImagePath", relImage, ...
        "SourceCSV", sourceCsv(i), ...
        "GeneratorFunction", generator(i), ...
        "XVariable", xVariable(i), ...
        "YVariables", yVariables(i), ...
        "ImageExists", logical(imageExists), ...
        "SourceExists", logical(sourceExists), ...
        "SourceRowCount", double(sourceRows), ...
        "TruthStatus", "real_lls_measured_sinr_analytics", ...
        "LineageStatus", string(localTernary(imageExists && sourceExists, "complete", "incomplete")));
end
T = struct2table(rows, "AsArray", true);
path = fullfile(layout.ReportCSVDir, "measurement_sinr_plot_lineage.csv");
sixgr.analytics.writeAnalysisTable(path, T);
lineage = struct("Path", string(path), "Table", T);
end

function [existsAll, rowCount] = localSourceStats(runDir, sourceSpec)
parts = split(string(sourceSpec), "|");
existsAll = true;
rowCount = 0;
for i = 1:numel(parts)
    p = fullfile(char(runDir), char(strrep(parts(i), "/", filesep)));
    if exist(p, "file") ~= 2
        existsAll = false;
        continue;
    end
    try
        T = readtable(p, "VariableNamingRule", "preserve");
        rowCount = rowCount + height(T);
    catch
        existsAll = false;
    end
end
end

function localEmptyAnnotationIfNeeded(counts, msg)
if all(double(counts(:)) == 0)
    localEmptyAnnotation(msg);
end
end

function localEmptyAnnotation(msg)
axis off;
text(0.5, 0.5, msg, "HorizontalAlignment", "center", "FontWeight", "bold");
end

function marker = localMarkerForUE(ue)
if isnan(ue)
    marker = "d";
elseif mod(round(ue), 2) == 0
    marker = "s";
else
    marker = "o";
end
end

function w = localLineWidth(ue)
if isnan(ue)
    w = 2.4;
else
    w = 1.2;
end
end

function label = localUELabel(ue)
if isnan(ue)
    label = "All";
else
    label = "UE" + string(round(ue));
end
end

function T = localReadOptionalTable(path)
if exist(path, "file") ~= 2
    T = table();
    return;
end
try
    T = readtable(path, "VariableNamingRule", "preserve", "TextType", "string");
catch
    T = table();
end
end

function runDir = localResolveRunDir(cfg)
if ischar(cfg) || (isstring(cfg) && isscalar(cfg))
    runDir = char(string(cfg));
    return;
end
runDir = char(string(sixgr.util.structGet(cfg, "output_dir", ...
    sixgr.util.structGet(cfg, "outputs.output_dir", ...
    sixgr.util.structGet(cfg, "run.rootRunFolder", ...
    sixgr.util.structGet(cfg, "runFolder", pwd))))));
end

function x = localToDouble(v)
if isnumeric(v) || islogical(v)
    x = double(v);
elseif iscell(v)
    x = str2double(string(v));
else
    x = str2double(string(v));
end
x = x(:);
end

function labels = localUniqueUELabels(v)
values = localToDouble(v);
labels = unique(values(isfinite(values)), "stable");
% MATLAB intentionally treats NaN values as distinct in some unique()
% modes.  Aggregate curve rows therefore used to create one identical
% "All" legend series per row.  Preserve exactly one aggregate series.
if any(isnan(values))
    labels(end + 1, 1) = NaN;
end
end

function mask = localUEMask(v, label)
values = localToDouble(v);
if isnan(label)
    mask = isnan(values);
else
    mask = values == label;
end
end

function tf = localHasColumn(T, name)
tf = istable(T) && any(string(T.Properties.VariableNames) == string(name));
end

function y = localTernary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end
