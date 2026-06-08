function artifacts = exportLinkKPIs(runFolder, kpiTable, details, varargin)
%EXPORTLINKKPIS Unified link-level CSV/MAT/FIG export.

p = inputParser;
p.addParameter("SaveCSV", true, @(x) islogical(x) && isscalar(x));
p.addParameter("SaveMAT", true, @(x) islogical(x) && isscalar(x));
p.addParameter("SaveFigures", false, @(x) islogical(x) && isscalar(x));
p.addParameter("SavePNG", true, @(x) islogical(x) && isscalar(x));
p.addParameter("FigurePrefix", "Link", @(x) ischar(x) || isstring(x));
p.addParameter("PlotVisible", false, @(x) islogical(x) && isscalar(x));
p.addParameter("FigureResolution", 140, @(x) isnumeric(x) && isscalar(x) && x >= 72);
p.addParameter("FileSuffix", "", @(x) ischar(x) || (isstring(x) && isscalar(x)));
p.parse(varargin{:});
opt = p.Results;

if nargin < 3 || isempty(details)
    details = struct();
end

artifacts = struct('csv',{{}},'mat',{{}},'fig',{{}});

sixgr.util.ensureFolder(fullfile(runFolder, "csv"));
sixgr.util.ensureFolder(fullfile(runFolder, "mat"));
sixgr.util.ensureFolder(fullfile(runFolder, "image"));

if opt.SaveCSV
    fileSuffix = localNormalizeFileSuffix(opt.FileSuffix);
    csvFile = fullfile(runFolder, "csv", localAppendFileSuffix("link_kpis.csv", fileSuffix));
    sixgr.util.csvWriteTable(csvFile, kpiTable);
    artifacts.csv{end+1} = csvFile;

    sweep = sixgr.util.structGet(details, "SNRSweep", table());
    if istable(sweep) && ~isempty(sweep)
        sweepFile = fullfile(runFolder, "csv", localAppendFileSuffix("lls_snr_sweep.csv", fileSuffix));
        sweep = localPreserveExistingTableColumns(sweepFile, sweep);
        sixgr.util.csvWriteTable(sweepFile, sweep);
        artifacts.csv{end+1} = sweepFile;
    end

    paprT = sixgr.util.structGet(details, "PAPRCCDF", table());
    if istable(paprT) && ~isempty(paprT)
        paprFile = fullfile(runFolder, "csv", localAppendFileSuffix("papr_ccdf.csv", fileSuffix));
        sixgr.util.csvWriteTable(paprFile, paprT);
        artifacts.csv{end+1} = paprFile;
    end

    % Backward-compatible campaign alias with compact scalar content.
    csvSummary = fullfile(runFolder, "csv", localAppendFileSuffix("lls_kpi_summary.csv", fileSuffix));
    sixgr.util.csvWriteTable(csvSummary, localBuildSingleRowSummary(kpiTable, sweep));
    artifacts.csv{end+1} = csvSummary;
end

if opt.SaveMAT
    fileSuffix = localNormalizeFileSuffix(opt.FileSuffix);
    matFile = fullfile(runFolder, "mat", localAppendFileSuffix("link_results.mat", fileSuffix));
    payload = struct();
    payload.kpiTable = kpiTable;
    payload.details = details;
    sixgr.util.matSave(matFile, payload);
    artifacts.mat{end+1} = matFile;
end

if opt.SaveFigures
    try
        resStruct = struct();
        resStruct.KPIs = struct();
        resStruct.KPIs.LinkKPI = kpiTable;
        figPrefix = string(opt.FigurePrefix) + localNormalizeFileSuffix(opt.FileSuffix);
        sweep = sixgr.util.structGet(details, "SNRSweep", table());
        if istable(sweep) && ~isempty(sweep)
            resStruct.KPIs.LinkSNRSweep = sweep;
        end
        paprCCDF = sixgr.util.structGet(details, "PAPRCCDF", table());
        if istable(paprCCDF) && ~isempty(paprCCDF)
            resStruct.KPIs.PAPRCCDF = paprCCDF;
        end

        figs = sixgr.visual.PlotLinkKPIs(resStruct, ...
            "FigurePrefix", char(figPrefix), ...
            "MakeInvisible", ~logical(opt.PlotVisible));
        fNames = fieldnames(figs);
        for i = 1:numel(fNames)
            n = fNames{i};
            if startsWith(n, "_")
                continue;
            end
            f = figs.(n);
            if isempty(f) || ~ishghandle(f)
                continue;
            end
            if opt.SavePNG
                fp = fullfile(runFolder, "image", lower(figPrefix) + "_" + lower(string(n)) + ".png");
                sixgr.util.exportFigureArtifact(f, fp, "Resolution", round(double(opt.FigureResolution)));
                artifacts.fig{end+1} = char(fp); %#ok<AGROW>
            end
            try
                if ~logical(opt.PlotVisible)
                    close(f);
                end
            catch
            end
        end
    catch
        % Keep data export successful even if plotting fails.
    end
end
end

function T = localPreserveExistingTableColumns(csvFile, T)
% Keep richer runner-owned measured columns when this generic exporter
% refreshes the same artifact later in the bundle pipeline.
if ~(istable(T) && isfile(csvFile))
    return;
end
try
    existing = readtable(csvFile, "VariableNamingRule", "preserve");
catch
    return;
end
if ~(istable(existing) && height(existing) == height(T))
    return;
end

existingVars = string(existing.Properties.VariableNames);
newVars = string(T.Properties.VariableNames);
merged = existing;
for i = 1:numel(newVars)
    varName = char(newVars(i));
    merged.(varName) = T.(varName);
end

missingExisting = setdiff(existingVars, newVars, "stable");
if ~isempty(missingExisting) || width(existing) > width(T)
    T = merged;
end
end

function suffix = localNormalizeFileSuffix(in)
suffix = strtrim(string(in));
if strlength(suffix) == 0
    suffix = "";
    return;
end
if ~startsWith(suffix, "_")
    suffix = "_" + suffix;
end
end

function out = localAppendFileSuffix(fileName, suffix)
fileName = string(fileName);
suffix = string(suffix);
if strlength(suffix) == 0
    out = char(fileName);
    return;
end
[folder, stem, ext] = fileparts(char(fileName));
outName = string(stem) + suffix + string(ext);
if strlength(string(folder)) > 0
    out = char(fullfile(folder, char(outName)));
else
    out = char(outName);
end
end

function T = localBuildSingleRowSummary(kpiTable, sweepT)
row = struct();
row.BLER_DL_min = localTableMin(kpiTable, ["DL_BLER", "BLER_DL", "BLER"]);
row.BLER_UL_min = localTableMin(kpiTable, ["UL_BLER", "BLER_UL"]);
row.Goodput_DL_max_Mbps = localTableMax(kpiTable, ["DL_Goodput_Mbps", "DL_Throughput_Mbps", "Goodput_Mbps", "Throughput_Mbps"]);
row.Goodput_UL_max_Mbps = localTableMax(kpiTable, ["UL_Goodput_Mbps", "UL_Throughput_Mbps", "Goodput_Mbps", "Throughput_Mbps"]);
row.RequiredSNR_DL_10pctBLER = localRequiredSNRFromSweep(sweepT, "DL_BLER", 0.1);
row.RequiredSNR_UL_10pctBLER = localRequiredSNRFromSweep(sweepT, "UL_BLER", 0.1);
T = struct2table(row);
end

function v = localTableMin(T, candidates)
v = NaN;
x = localTableValues(T, candidates);
if ~isempty(x)
    v = min(x);
end
end

function v = localTableMax(T, candidates)
v = NaN;
x = localTableValues(T, candidates);
if ~isempty(x)
    v = max(x);
end
end

function x = localTableValues(T, candidates)
x = [];
if ~(istable(T) && ~isempty(T))
    return;
end
vars = string(T.Properties.VariableNames);
candidates = string(candidates);
for i = 1:numel(candidates)
    if ismember(candidates(i), vars)
        try
            x = double(T.(candidates(i)));
        catch
            x = str2double(string(T.(candidates(i))));
        end
        x = x(isfinite(x));
        return;
    end
end
end

function snrReq = localRequiredSNRFromSweep(sweepT, blerCol, target)
snrReq = NaN;
if ~(istable(sweepT) && ~isempty(sweepT) && all(ismember(["SNR_dB", string(blerCol)], string(sweepT.Properties.VariableNames))))
    return;
end
snr = double(sweepT.SNR_dB);
bler = double(sweepT.(string(blerCol)));
mask = isfinite(snr) & isfinite(bler);
snr = snr(mask);
bler = bler(mask);
if numel(snr) < 2 || ~(any(bler <= target) && any(bler >= target))
    return;
end
[snr, order] = sort(snr);
bler = bler(order);
for i = 1:(numel(snr) - 1)
    if (bler(i) - target) * (bler(i + 1) - target) > 0
        continue;
    end
    if abs(bler(i + 1) - bler(i)) < eps
        snrReq = snr(i);
    else
        t = (target - bler(i)) / (bler(i + 1) - bler(i));
        snrReq = snr(i) + t * (snr(i + 1) - snr(i));
    end
    return;
end
end
