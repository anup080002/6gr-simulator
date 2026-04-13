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

    % Backward-compatible campaign alias.
    csvSummary = fullfile(runFolder, "csv", localAppendFileSuffix("lls_kpi_summary.csv", fileSuffix));
    sixgr.util.csvWriteTable(csvSummary, kpiTable);
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
                exportgraphics(f, fp, "Resolution", round(double(opt.FigureResolution)));
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
