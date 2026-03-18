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
p.parse(varargin{:});
opt = p.Results;

if nargin < 3 || isempty(details)
    details = struct();
end

artifacts = struct('csv',{{}},'mat',{{}},'fig',{{}});

sixgr.util.ensureDir(fullfile(runFolder, "csv"));
sixgr.util.ensureDir(fullfile(runFolder, "mat"));
sixgr.util.ensureDir(fullfile(runFolder, "fig"));

if opt.SaveCSV
    csvFile = fullfile(runFolder, "csv", "link_kpis.csv");
    sixgr.util.csvWriteTable(csvFile, kpiTable);
    artifacts.csv{end+1} = csvFile;

    % Backward-compatible campaign alias.
    csvSummary = fullfile(runFolder, "csv", "lls_kpi_summary.csv");
    sixgr.util.csvWriteTable(csvSummary, kpiTable);
    artifacts.csv{end+1} = csvSummary;
end

if opt.SaveMAT
    matFile = fullfile(runFolder, "mat", "link_results.mat");
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
        sweep = sixgr.util.structGet(details, "SNRSweep", table());
        if istable(sweep) && ~isempty(sweep)
            resStruct.KPIs.LinkSNRSweep = sweep;
        end

        figs = sixgr.visual.PlotLinkKPIs(resStruct, ...
            "FigurePrefix", char(string(opt.FigurePrefix)), ...
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
                fp = fullfile(runFolder, "fig", lower(string(opt.FigurePrefix)) + "_" + lower(string(n)) + ".png");
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
