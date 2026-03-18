function manifest = ExportResults(ctxOrRunFolder, results, varargin)
% sixgr.visual.ExportResults
% Export results artifacts (MAT/CSV/Figures) + write a run manifest.
%
% This helper is designed to work with:
%   - sixgr.core.SimContext + sixgr.core.SimResults
%   - or (runFolder, resultsStruct)
%
% It is intentionally tolerant: it exports whatever is available.
%
% Usage
%   ctx = sixgr.core.SimContext(cfg);
%   runner = sixgr.core.SimRunner(ctx);
%   res = runner.run();
%   sixgr.visual.ExportResults(ctx, res);
%
% Name-value options
%   'Cfg'                : config struct (only needed if ctxOrRunFolder is not a SimContext)
%   'Layout'             : scenario layout struct (optional)
%   'UE'                 : UE struct (optional)
%   'UeTrace'            : mobility trace Kx3xT for PlotMobility (optional)
%   'MakePlots'          : true/false (default true)
%   'MakeScenarioPlots'  : true/false (default true)
%   'SavePNG'            : true/false (default true)
%   'SavePDF'            : true/false (default true)
%   'FigurePrefix'       : prefix string for saved figure files
%   'MakeInvisible'      : true -> figures created invisible (default true for batch)
%   'Overwrite'          : overwrite existing files (default true)
%
% Output
%   manifest : struct describing exported files
%
% File: +sixgr/+visual/ExportResults.m
% ASCII-only.

% ---------------- Resolve run context ----------------
runFolder = '';
cfg = struct();
logger = [];

if isa(ctxOrRunFolder,'sixgr.core.SimContext')
    runFolder = char(ctxOrRunFolder.RunFolder);
    cfg = ctxOrRunFolder.Cfg;
    logger = ctxOrRunFolder.Logger;
elseif ischar(ctxOrRunFolder) || (isstring(ctxOrRunFolder) && isscalar(ctxOrRunFolder))
    runFolder = char(ctxOrRunFolder);
else
    % Try to pull from results
    if isa(results,'sixgr.core.SimResults') && ~isempty(results.RunFolder)
        runFolder = char(results.RunFolder);
    else
        error('sixgr:visual:ExportResults:NeedRunFolder', ...
            'First arg must be SimContext or runFolder (char/string).');
    end
end

% ---------------- Options ----------------
opt.Cfg = cfg;
opt.Layout = [];
opt.UE = [];
opt.UeTrace = [];
opt.MakePlots = true;
opt.MakeScenarioPlots = true;
opt.SavePNG = true;
opt.SavePDF = true;
opt.FigurePrefix = '';
opt.MakeInvisible = true;
opt.Overwrite = true;

if ~isempty(varargin)
    if mod(numel(varargin),2) ~= 0
        error('sixgr:visual:ExportResults:BadNV','Name-value inputs must come in pairs.');
    end
    for i = 1:2:numel(varargin)
        k = string(varargin{i});
        v = varargin{i+1};
        switch lower(k)
            case "cfg"
                opt.Cfg = v;
            case "layout"
                opt.Layout = v;
            case "ue"
                opt.UE = v;
            case {"uetrace","uetrace_m"}
                opt.UeTrace = v;
            case "makeplots"
                opt.MakePlots = logical(v);
            case "makescenarioplots"
                opt.MakeScenarioPlots = logical(v);
            case "savepng"
                opt.SavePNG = logical(v);
            case "savepdf"
                opt.SavePDF = logical(v);
            case "figureprefix"
                opt.FigurePrefix = char(v);
            case "makeinvisible"
                opt.MakeInvisible = logical(v);
            case "overwrite"
                opt.Overwrite = logical(v);
            otherwise
                error('sixgr:visual:ExportResults:BadOpt','Unknown option: %s', k);
        end
    end
end

cfg = opt.Cfg;

% ---------------- Ensure output folders ----------------
try
    sixgr.util.ensureDir(runFolder);
catch
    if ~isfolder(runFolder)
        mkdir(runFolder);
    end
    for d = {fullfile(runFolder,'mat'), fullfile(runFolder,'csv'), fullfile(runFolder,'fig'), fullfile(runFolder,'logs')}
        if ~isfolder(d{1}), mkdir(d{1}); end
    end
end

matDir = fullfile(runFolder,'mat');
csvDir = fullfile(runFolder,'csv');
figDir = fullfile(runFolder,'fig');

% ---------------- Build manifest ----------------
manifest = struct();
manifest.runFolder = runFolder;
manifest.generatedUTC = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
manifest.mat = {};
manifest.csv = {};
manifest.fig = {};
manifest.other = {};

% Helper logger
    function logInfo(msg)
        try
            if ~isempty(logger) && isa(logger,'sixgr.core.Logger')
                logger.info(msg);
            end
        catch
        end
    end

logInfo('ExportResults: start');

% ---------------- Save config snapshot ----------------
try
    if ~isempty(cfg)
        cfgFile = fullfile(runFolder,'cfg_snapshot.json');
        if opt.Overwrite || ~exist(cfgFile,'file')
            sixgr.util.jsonWrite(cfgFile, cfg);
        end
        manifest.other{end+1} = cfgFile;
    end
catch ME
    logInfo(['ExportResults: cfg snapshot failed: ' ME.message]);
end

% ---------------- Save MAT (results snapshot) ----------------
try
    resStruct = localResultsToStruct(results);
    matFile = fullfile(matDir,'results.mat');
    if opt.Overwrite || ~exist(matFile,'file')
        sixgr.util.matSave(matFile, struct('results',resStruct,'cfg',cfg));
    end
    manifest.mat{end+1} = matFile;

    % If SimResults handle, record artifact
    if isa(results,'sixgr.core.SimResults')
        try
            results.addArtifact('mat', matFile);
        catch
        end
    end
catch ME
    logInfo(['ExportResults: MAT save failed: ' ME.message]);
end

% ---------------- Export KPI tables to CSV ----------------
try
    kpis = [];
    if isa(results,'sixgr.core.SimResults')
        kpis = results.KPIs;
    elseif isstruct(results)
        if isfield(results,'KPIs'), kpis = results.KPIs; end
        if isempty(kpis) && isfield(results,'kpis'), kpis = results.kpis; end
    end

    if ~isempty(kpis) && isstruct(kpis)
        fn = fieldnames(kpis);
        for i = 1:numel(fn)
            name = fn{i};
            val = kpis.(name);
            if istable(val)
                fcsv = fullfile(csvDir, [name '.csv']);
                if opt.Overwrite || ~exist(fcsv,'file')
                    sixgr.util.csvWriteTable(fcsv, val);
                end
                manifest.csv{end+1} = fcsv;
                if isa(results,'sixgr.core.SimResults')
                    try
                        results.addArtifact('csv', fcsv);
                    catch
                    end
                end
            end
        end
    end
catch ME
    logInfo(['ExportResults: CSV export failed: ' ME.message]);
end

% ---------------- Generate plots ----------------
if opt.MakePlots
    try
        figs = struct();

        % Scenario plot(s)
        if opt.MakeScenarioPlots && ~isempty(opt.Layout)
            try
                [f1,~,~] = sixgr.visual.PlotScenario(opt.Layout, opt.UE, ...
                    'Title','Scenario', 'MaxUEs', 500);
                figs.Scenario = f1;
            catch ME
                logInfo(['ExportResults: PlotScenario failed: ' ME.message]);
            end

            if ~isempty(opt.UeTrace)
                try
                    [f2,~,~] = sixgr.visual.PlotMobility(opt.Layout, opt.UeTrace, 'Title','Mobility');
                    figs.Mobility = f2;
                catch ME
                    logInfo(['ExportResults: PlotMobility failed: ' ME.message]);
                end
            end
        end

        % Link KPI plots
        try
            fk = sixgr.visual.PlotLinkKPIs(results, ...
                'FigurePrefix', localPrefix(opt,'Link'), 'MakeInvisible', opt.MakeInvisible);
            figs = localMergeStruct(figs, fk);
        catch ME
            logInfo(['ExportResults: PlotLinkKPIs failed: ' ME.message]);
        end

        % System KPI plots
        try
            fs = sixgr.visual.PlotSystemKPIs(results, ...
                'FigurePrefix', localPrefix(opt,'System'), 'MakeInvisible', opt.MakeInvisible);
            figs = localMergeStruct(figs, fs);
        catch ME
            logInfo(['ExportResults: PlotSystemKPIs failed: ' ME.message]);
        end

        % Save figures
        figNames = fieldnames(figs);
        for i = 1:numel(figNames)
            n = figNames{i};
            if startsWith(n,'_')
                continue;
            end
            f = figs.(n);
            if ~isempty(f) && ishghandle(f)
                base = fullfile(figDir, [n]);
                if ~isempty(opt.FigurePrefix)
                    base = fullfile(figDir, [opt.FigurePrefix '_' n]);
                end

                if opt.SavePNG
                    fpng = [base '.png'];
                    localSaveFigure(f, fpng, opt.Overwrite);
                    manifest.fig{end+1} = fpng;
                    if isa(results,'sixgr.core.SimResults')
                        try
                            results.addArtifact('fig', fpng);
                        catch
                        end
                    end
                end

                if opt.SavePDF
                    fpdf = [base '.pdf'];
                    localSaveFigurePDF(f, fpdf, opt.Overwrite);
                    manifest.fig{end+1} = fpdf;
                    if isa(results,'sixgr.core.SimResults')
                        try
                            results.addArtifact('fig', fpdf);
                        catch
                        end
                    end
                end
            end
        end

        % Close invisible figures to avoid clutter
        if opt.MakeInvisible
            for i = 1:numel(figNames)
                n = figNames{i};
                if startsWith(n,'_'), continue; end
                f = figs.(n);
                try
                    if ~isempty(f) && ishghandle(f)
                        close(f);
                    end
                catch
                end
            end
        end

    catch ME
        logInfo(['ExportResults: plotting failed: ' ME.message]);
    end
end

% ---------------- Write export manifest ----------------
try
    mfile = fullfile(runFolder,'export_manifest.json');
    sixgr.util.jsonWrite(mfile, manifest);
    manifest.other{end+1} = mfile;
catch ME
    logInfo(['ExportResults: manifest write failed: ' ME.message]);
end

logInfo('ExportResults: done');

end

% ---------------- local helpers ----------------

function s = localResultsToStruct(results)
% Convert results into a struct suitable for saving.
if isa(results,'sixgr.core.SimResults')
    s = struct();
    s.Ok = results.Ok;
    s.RunFolder = results.RunFolder;
    s.StartTime = results.StartTime;
    s.EndTime = results.EndTime;
    s.Outputs = results.Outputs;
    s.KPIs = results.KPIs;
    s.Artifacts = results.Artifacts;
elseif isstruct(results)
    s = results;
else
    s = struct('data', results);
end
end

function localSaveFigure(fig, filePath, overwrite)
if ~overwrite && exist(filePath,'file')
    return;
end
try
    exportgraphics(fig, filePath, 'Resolution', 200);
catch
    try
        saveas(fig, filePath);
    catch
        print(fig, filePath, '-dpng', '-r150');
    end
end
end

function localSaveFigurePDF(fig, filePath, overwrite)
if ~overwrite && exist(filePath,'file')
    return;
end
try
    exportgraphics(fig, filePath, 'ContentType','vector');
catch
    try
        print(fig, filePath, '-dpdf');
    catch
        % ignore
    end
end
end

function out = localMergeStruct(a,b)
out = a;
if ~isstruct(b)
    return;
end
fn = fieldnames(b);
for i = 1:numel(fn)
    out.(fn{i}) = b.(fn{i});
end
end

function p = localPrefix(opt, def)
if ~isempty(opt.FigurePrefix)
    p = opt.FigurePrefix;
else
    p = def;
end
end
