function results = generateMeasuredSINRPlots(cfg, runTag, varargin)
%GENERATEMEASUREDSINRPLOTS Plot geometry-driven measured-SINR artifacts.

if nargin < 2
    runTag = "";
end

ip = inputParser;
ip.addParameter("MinimumTrialsPerBin", 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
ip.parse(varargin{:});
opt = ip.Results;

runDir = localResolveRunDir(cfg);
layout = sixgr.report.resultLayout(runDir);
sixgr.util.ensureFolder(layout.ReportImageDir);
sixgr.util.ensureFolder(layout.AirInterfaceImageDir);

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

results = struct("Ok", true, "RunDir", string(runDir), "RunTag", string(runTag), "Plots", paths);
end

function path = localPlotBLER(layout, dl, ul, minTrials)
fig = localNewFigure();
hold on;
localPlotBlerTable(dl, "DL", "-", minTrials);
localPlotBlerTable(ul, "UL", "--", minTrials);
title("BLER vs Measured Post-Equalisation SINR - Geometry-Driven");
xlabel("Measured post-EQ SINR (dB)");
ylabel("BLER");
ylim([0 1]);
grid on;
legend("Location", "best");
localEmptyAnnotationIfNeeded([height(dl), height(ul)], "No measured SINR BLER bins available");
path = fullfile(layout.ReportImageDir, "bler_vs_measured_sinr.png");
localSaveFigure(fig, path);
localSaveFigure(fig, fullfile(layout.AirInterfaceImageDir, "bler_vs_measured_sinr.png"));
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
ues = unique(localToDouble(T.UEIndex));
for i = 1:numel(ues)
    ue = ues(i);
    mask = localToDouble(T.UEIndex) == ue | (isnan(ue) & isnan(localToDouble(T.UEIndex)));
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
fig = localNewFigure();
hold on;
localPlotScalarCurve(dl, "DL", "BER", "-", minTrials);
localPlotScalarCurve(ul, "UL", "BER", "--", minTrials);
set(gca, "YScale", "log");
title("BER vs Measured Post-Equalisation SINR - Geometry-Driven");
xlabel("Measured post-EQ SINR (dB)");
ylabel("BER");
ylim([1e-5 1]);
grid on;
legend("Location", "best");
localEmptyAnnotationIfNeeded([height(dl), height(ul)], "No measured SINR BER bins available");
path = fullfile(layout.ReportImageDir, "ber_vs_measured_sinr.png");
localSaveFigure(fig, path);
localSaveFigure(fig, fullfile(layout.AirInterfaceImageDir, "ber_vs_measured_sinr.png"));
close(fig);
end

function path = localPlotThroughput(layout, dl, ul, minTrials)
fig = localNewFigure();
hold on;
localPlotThroughputTable(dl, "DL", "-", minTrials);
localPlotThroughputTable(ul, "UL", "--", minTrials);
title("Goodput vs Measured Post-Equalisation SINR - Geometry-Driven");
xlabel("Measured post-EQ SINR (dB)");
ylabel("Goodput (Mbps)");
grid on;
legend("Location", "best");
localEmptyAnnotationIfNeeded([height(dl), height(ul)], "No measured SINR throughput bins available");
path = fullfile(layout.ReportImageDir, "throughput_vs_measured_sinr.png");
localSaveFigure(fig, path);
localSaveFigure(fig, fullfile(layout.AirInterfaceImageDir, "throughput_vs_measured_sinr.png"));
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
ues = unique(localToDouble(T.UEIndex));
for i = 1:numel(ues)
    ue = ues(i);
    mask = localToDouble(T.UEIndex) == ue | (isnan(ue) & isnan(localToDouble(T.UEIndex)));
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
ues = unique(localToDouble(T.UEIndex));
for i = 1:numel(ues)
    ue = ues(i);
    mask = localToDouble(T.UEIndex) == ue | (isnan(ue) & isnan(localToDouble(T.UEIndex)));
    sub = T(mask, :);
    [x, order] = sort(localToDouble(sub.PostEqSINR_dB_BinCenter));
    y = max(localToDouble(sub.(char(yColumn))), 1e-5);
    plot(x, y(order), style + localMarkerForUE(ue), "DisplayName", direction + " " + localUELabel(ue), "LineWidth", localLineWidth(ue));
end
end

function path = localPlotDistribution(layout, T)
fig = localNewFigure();
if istable(T) && height(T) > 0
    dirs = unique(string(T.Direction), "stable");
    ues = unique(localToDouble(T.UEIndex));
    nSeries = max(1, numel(dirs) * numel(ues));
    seriesIdx = 0;
    hold on;
    for d = 1:numel(dirs)
        for i = 1:numel(ues)
            ue = ues(i);
            sub = T(strcmpi(string(T.Direction), dirs(d)) & localToDouble(T.UEIndex) == ue, :);
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
else
    localEmptyAnnotation("No measured SINR distribution available");
end
title("Measured SINR distribution by UE - geometry-derived");
xlabel("Measured post-EQ SINR (dB)");
ylabel("Trial fraction");
grid on;
path = fullfile(layout.ReportImageDir, "measured_sinr_distribution.png");
localSaveFigure(fig, path);
close(fig);
end

function path = localPlotDistanceScatter(layout, T)
fig = localNewFigure();
if istable(T) && height(T) > 0
    hold on;
    ues = unique(localToDouble(T.UEIndex));
    for i = 1:numel(ues)
        ue = ues(i);
        sub = T(localToDouble(T.UEIndex) == ue, :);
        scatter(localToDouble(sub.PropagationDistance_m), localToDouble(sub.PostEqSINR_dB), 28, "filled", "DisplayName", localUELabel(ue));
        if localHasColumn(sub, "LargeScaleSINR_dB")
            scatter(localToDouble(sub.PropagationDistance_m), localToDouble(sub.LargeScaleSINR_dB), 28, "o", "DisplayName", localUELabel(ue) + " large-scale");
        end
    end
    yline(-10, "--", "PBCH min");
    yline(15, "--", "PDSCH target");
    legend("Location", "best");
else
    localEmptyAnnotation("No distance-vs-SINR rows available");
end
title("UE propagation distance vs measured SINR");
xlabel("Propagation distance (m)");
ylabel("Measured post-EQ SINR (dB)");
grid on;
path = fullfile(layout.ReportImageDir, "distance_vs_sinr.png");
localSaveFigure(fig, path);
close(fig);
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

function tf = localHasColumn(T, name)
tf = istable(T) && any(string(T.Properties.VariableNames) == string(name));
end
