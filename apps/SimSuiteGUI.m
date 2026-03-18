classdef SimSuiteGUI < handle
% SimSuiteGUI
% Main GUI window for the unified SixGR simulator.
%
% Files
%   apps/SimSuiteGUI.m
%   apps/+ui/ConfigEditorPanel.m
%   apps/+ui/MapPanel.m
%   apps/+ui/RunPanel.m
%   apps/+ui/ResultsPanel.m
%
% Usage
%   cd <projectRoot>
%   setup6GRSimToolkit
%   app = SimSuiteGUI();
%
% Notes
%   - This is a pure-code GUI (uifigure-based), not an .mlapp.
%   - It is intentionally tolerant to evolving simulator internals.
%   - It integrates with your existing +sixgr library when available.
%
% MATLAB: R2025b+

    properties
        UIFigure matlab.ui.Figure

        RootGrid matlab.ui.container.GridLayout
        LeftTabs matlab.ui.container.TabGroup
        RightGrid matlab.ui.container.GridLayout

        TabConfig matlab.ui.container.Tab
        TabRun matlab.ui.container.Tab
        TabResults matlab.ui.container.Tab

        % Panel objects
        ConfigPanel ui.ConfigEditorPanel
        RunPanel ui.RunPanel
        ResultsPanel ui.ResultsPanel
        MapPanel ui.MapPanel

        % Data model
        Cfg struct = struct()
        Layout struct = struct()
        UE struct = struct()
        UETrace = []
        Results = []
    end

    properties(Access=private)
        Busy (1,1) logical = false
    end

    methods
        function obj = SimSuiteGUI(varargin)
            % SimSuiteGUI(Name,Value,...)
            %   'Cfg' : config struct (optional)

            cfgIn = [];
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('SimSuiteGUI:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = string(varargin{i});
                    v = varargin{i+1};
                    switch lower(k)
                        case "cfg"
                            cfgIn = v;
                        otherwise
                            error('SimSuiteGUI:BadOpt','Unknown option: %s', k);
                    end
                end
            end

            obj.buildUI_();

            % Load default cfg if not provided
            if isempty(cfgIn)
                obj.Cfg = obj.defaultConfig_();
            elseif ischar(cfgIn) || (isstring(cfgIn) && isscalar(cfgIn))
                cfgPath = char(string(cfgIn));
                try
                    if exist('sixgr.config.loadConfig','file') == 2
                        obj.Cfg = sixgr.config.loadConfig(cfgPath);
                    else
                        obj.Cfg = SimSuiteGUI.readJson_(cfgPath);
                    end
                catch
                    obj.Cfg = obj.defaultConfig_();
                end
            elseif isstruct(cfgIn)
                obj.Cfg = cfgIn;
            else
                obj.Cfg = obj.defaultConfig_();
            end

            % Push cfg to panels
            obj.ConfigPanel.setConfig(obj.Cfg);
            obj.RunPanel.setConfig(obj.Cfg);
            obj.MapPanel.setConfig(obj.Cfg);

            % Try build an initial scenario (best-effort)
            obj.refreshScenario();

            % Bring to front
            figure(obj.UIFigure);
        end

        function refreshScenario(obj)
            % refreshScenario Build layout + UE drop from current cfg.
            if obj.Busy
                return;
            end
            obj.Busy = true;
            cleaner = onCleanup(@() obj.setBusyFlag_(false)); %#ok<NASGU>

            cfg = obj.Cfg;

            layout = struct();
            ue = struct();
            ueTrace = [];

            try
                if exist('sixgr.scenario.generateLayout','file') == 2
                    layout = sixgr.scenario.generateLayout(cfg);
                elseif exist('sixgr.scenario.ScenarioFactory','class')
                    % Best-effort factory usage
                    layout = sixgr.scenario.ScenarioFactory.make(cfg);
                end
            catch ME
                obj.RunPanel.appendLog(sprintf('[Scenario] generateLayout failed: %s', ME.message));
            end

            try
                if exist('sixgr.scenario.dropUEs','file') == 2
                    ue = sixgr.scenario.dropUEs(cfg, layout);
                end
            catch ME
                obj.RunPanel.appendLog(sprintf('[Scenario] dropUEs failed: %s', ME.message));
            end

            % Optional: mobility trace generation hook if you have it
            try
                if exist('sixgr.scenario.mobility.updatePositions','file') == 2
                    % Not generating traces here by default.
                    ueTrace = [];
                end
            catch
            end

            obj.Layout = layout;
            obj.UE = ue;
            obj.UETrace = ueTrace;

            obj.MapPanel.setScenario(layout, ue, ueTrace);
        end

        function setConfig(obj, cfg)
            if nargin < 2 || isempty(cfg)
                cfg = struct();
            end
            obj.Cfg = cfg;

            obj.ConfigPanel.setConfig(cfg);
            obj.RunPanel.setConfig(cfg);
            obj.MapPanel.setConfig(cfg);
        end

        function cfg = getConfig(obj)
            cfg = obj.Cfg;
        end

        function setResults(obj, results)
            obj.Results = results;
            obj.ResultsPanel.setResults(results, obj.Cfg);

            % Auto-update map if results contain layout/ue/trace
            try
                if isstruct(results)
                    if isfield(results,'Layout')
                        obj.Layout = results.Layout;
                    end
                    if isfield(results,'UE')
                        obj.UE = results.UE;
                    end
                    if isfield(results,'UETrace')
                        obj.UETrace = results.UETrace;
                    end
                elseif isa(results,'sixgr.core.SimResults')
                    if isfield(results.Outputs,'Layout')
                        obj.Layout = results.Outputs.Layout;
                    end
                    if isfield(results.Outputs,'UE')
                        obj.UE = results.Outputs.UE;
                    end
                    if isfield(results.Outputs,'UETrace')
                        obj.UETrace = results.Outputs.UETrace;
                    end
                end
            catch
            end

            obj.MapPanel.setScenario(obj.Layout, obj.UE, obj.UETrace);
        end

        function close(obj)
            try
                if ~isempty(obj.RunPanel)
                    obj.RunPanel.cancelRun();
                end
            catch
            end

            try
                if ~isempty(obj.UIFigure) && isvalid(obj.UIFigure)
                    delete(obj.UIFigure);
                end
            catch
            end
        end

        function delete(obj)
            obj.close();
        end
    end

    methods(Access=private)
        function buildUI_(obj)
            obj.UIFigure = uifigure('Name','SixGR SimSuite','Position',[100 100 1200 720]);
            obj.UIFigure.CloseRequestFcn = @(~,~) obj.onCloseRequest_();

            % Menus
            mFile = uimenu(obj.UIFigure,'Text','File');
            uimenu(mFile,'Text','Load Config...','MenuSelectedFcn',@(~,~) obj.onLoadConfig_());
            uimenu(mFile,'Text','Save Config As...','MenuSelectedFcn',@(~,~) obj.onSaveConfigAs_());
            uimenu(mFile,'Text','Export Results...','MenuSelectedFcn',@(~,~) obj.onExportResults_());
            uimenu(mFile,'Text','Open Run Folder','Separator','on','MenuSelectedFcn',@(~,~) obj.onOpenRunFolder_());
            uimenu(mFile,'Text','Exit','Separator','on','MenuSelectedFcn',@(~,~) obj.onCloseRequest_());

            mView = uimenu(obj.UIFigure,'Text','View');
            uimenu(mView,'Text','Refresh Scenario','MenuSelectedFcn',@(~,~) obj.refreshScenario());
            uimenu(mView,'Text','Open Site Viewer','MenuSelectedFcn',@(~,~) obj.MapPanel.openSiteViewer());

            mHelp = uimenu(obj.UIFigure,'Text','Help');
            uimenu(mHelp,'Text','About','MenuSelectedFcn',@(~,~) obj.onAbout_());

            % Main grid: left tabs + right map
            obj.RootGrid = uigridlayout(obj.UIFigure, [1 2]);
            obj.RootGrid.ColumnWidth = {420,'1x'};
            obj.RootGrid.RowHeight = {'1x'};
            obj.RootGrid.Padding = [8 8 8 8];
            obj.RootGrid.ColumnSpacing = 8;

            % Left tabs
            obj.LeftTabs = uitabgroup(obj.RootGrid);
            obj.LeftTabs.Layout.Row = 1;
            obj.LeftTabs.Layout.Column = 1;

            obj.TabConfig = uitab(obj.LeftTabs,'Title','Config');
            obj.TabRun    = uitab(obj.LeftTabs,'Title','Run');
            obj.TabResults= uitab(obj.LeftTabs,'Title','Results');

            obj.ConfigPanel = ui.ConfigEditorPanel(obj.TabConfig, ...
                'OnConfigChanged', @(cfg) obj.onConfigChanged_(cfg), ...
                'OnRequestScenarioRefresh', @() obj.refreshScenario());

            obj.RunPanel = ui.RunPanel(obj.TabRun, ...
                'OnRunRequested', @(mode,module,exportAfter) obj.onRunRequested_(mode,module,exportAfter), ...
                'OnOpenRunFolder', @() obj.onOpenRunFolder_());

            obj.ResultsPanel = ui.ResultsPanel(obj.TabResults, ...
                'OnExportRequested', @() obj.onExportResults_(), ...
                'OnOpenRunFolder', @() obj.onOpenRunFolder_());

            % Right side: map panel
            obj.RightGrid = uigridlayout(obj.RootGrid, [1 1]);
            obj.RightGrid.Layout.Row = 1;
            obj.RightGrid.Layout.Column = 2;
            obj.RightGrid.Padding = [0 0 0 0];

            obj.MapPanel = ui.MapPanel(obj.RightGrid, ...
                'OnRequestScenarioRefresh', @() obj.refreshScenario());
        end

        function setBusyFlag_(obj, tf)
            obj.Busy = logical(tf);
        end

        function cfg = defaultConfig_(obj) %#ok<MANU>
            % Best-effort default config from +sixgr
            if exist('sixgr.config.loadConfig','file') == 2
                try
                    cfg = sixgr.config.loadConfig(fullfile('config','suite_config.json'));
                    return;
                catch
                end
            end
            if exist('sixgr.config.defaultConfig','file') == 2
                try
                    cfg = sixgr.config.defaultConfig();
                    return;
                catch
                end
            end
            cfg = struct();
        end

        function onConfigChanged_(obj, cfg)
            % Callback from ConfigEditorPanel
            obj.setConfig(cfg);
        end

        function onRunRequested_(obj, mode, module, exportAfter)
            % Callback from RunPanel
            if obj.Busy
                obj.RunPanel.appendLog('[Run] Busy. Please wait for current action to finish.');
                return;
            end
            obj.Busy = true;

            cfg = obj.Cfg;
            obj.RunPanel.appendLog(sprintf('[Run] Requested: profile=%s runner=%s', string(mode), string(module)));

            % Launch run via RunPanel (handles background/foreground)
            obj.RunPanel.runSimulation(@SimSuiteGUI.runSimWorker, cfg, mode, module, @(res,err) obj.onRunFinished_(res,err,exportAfter));
        end

        function onRunFinished_(obj, res, err, exportAfter)
            % Completion callback from RunPanel
            obj.Busy = false;

            if ~isempty(err)
                obj.RunPanel.appendLog(sprintf('[Run] FAILED: %s', err));
                return;
            end

            obj.RunPanel.appendLog('[Run] Completed successfully.');
            obj.setResults(res);

            % Optionally export artifacts
            if exportAfter
                try
                    obj.onExportResults_();
                catch ME
                    obj.RunPanel.appendLog(sprintf('[Export] FAILED: %s', ME.message));
                end
            end

            % Switch to results tab
            try
                obj.LeftTabs.SelectedTab = obj.TabResults;
            catch
            end
        end

        function onLoadConfig_(obj)
            [f,p] = uigetfile({'*.json','JSON config (*.json)';'*.*','All files'}, 'Load config');
            if isequal(f,0)
                return;
            end
            filePath = fullfile(p,f);
            try
                cfg = SimSuiteGUI.readJson_(filePath);
                % If you have a normalizer/validator, apply it
                if exist('sixgr.config.loadConfig','file') == 2
                    try
                        cfg = sixgr.config.loadConfig(filePath);
                    catch
                        % keep decoded cfg
                    end
                end
                obj.setConfig(cfg);
                obj.RunPanel.appendLog(sprintf('[Config] Loaded: %s', filePath));
            catch ME
                uialert(obj.UIFigure, ME.message, 'Load config failed');
            end
        end

        function onSaveConfigAs_(obj)
            [f,p] = uiputfile({'*.json','JSON config (*.json)'}, 'Save config as');
            if isequal(f,0)
                return;
            end
            filePath = fullfile(p,f);
            try
                SimSuiteGUI.writeJson_(filePath, obj.Cfg);
                obj.RunPanel.appendLog(sprintf('[Config] Saved: %s', filePath));
            catch ME
                uialert(obj.UIFigure, ME.message, 'Save config failed');
            end
        end

        function onExportResults_(obj)
            if isempty(obj.Results)
                uialert(obj.UIFigure,'No results to export yet. Run a simulation first.','Export');
                return;
            end

            % Determine run folder
            runFolder = SimSuiteGUI.getRunFolder_(obj.Results);
            if isempty(runFolder)
                % Ask user
                runFolder = uigetdir(pwd,'Select results run folder');
                if isequal(runFolder,0)
                    return;
                end
            end

            try
                if exist('sixgr.visual.ExportResults','file') == 2
                    manifest = sixgr.visual.ExportResults(runFolder, obj.Results, ...
                        'Cfg', obj.Cfg, ...
                        'Layout', obj.Layout, ...
                        'UE', obj.UE, ...
                        'UeTrace', obj.UETrace);
                else
                    % Fallback: save a MAT snapshot
                    manifest = struct();
                    manifest.runFolder = runFolder;
                    outMat = fullfile(runFolder,'mat','results.mat');
                    if exist('sixgr.util.matSave','file') == 2
                        sixgr.util.matSave(outMat, struct('results',obj.Results,'cfg',obj.Cfg));
                    else
                        if ~isfolder(fileparts(outMat))
                            mkdir(fileparts(outMat));
                        end
                        snap = struct('results',obj.Results,'cfg',obj.Cfg); %#ok<NASGU>
                        save(outMat,'-struct','snap');
                    end
                end

                obj.ResultsPanel.setExportManifest(manifest);
                obj.RunPanel.appendLog(sprintf('[Export] Done: %s', runFolder));
            catch ME
                uialert(obj.UIFigure, ME.message, 'Export failed');
            end
        end

        function onOpenRunFolder_(obj)
            runFolder = SimSuiteGUI.getRunFolder_(obj.Results);
            if isempty(runFolder)
                runFolder = SimSuiteGUI.getRunFolderFromCfg_(obj.Cfg);
            end
            if isempty(runFolder)
                uialert(obj.UIFigure,'Run folder is unknown. Run a simulation first.','Open folder');
                return;
            end

            try
                if ispc
                    winopen(runFolder);
                elseif ismac
                    system(sprintf('open "%s" &', runFolder));
                else
                    system(sprintf('xdg-open "%s" &', runFolder));
                end
            catch ME
                uialert(obj.UIFigure, ME.message, 'Open folder failed');
            end
        end

        function onCloseRequest_(obj)
            selection = questdlg('Close SimSuiteGUI?','Close','Yes','No','Yes');
            if strcmp(selection,'Yes')
                obj.close();
            end
        end

        function onAbout_(obj)
            msg = sprintf([ ...
                'SixGR SimSuite GUI\n\n', ...
                'Mode: Unified full-campaign runner (full/quick/long profiles)\n', ...
                'MATLAB: %s\n\n', ...
                'This GUI is code-based and designed to be tolerant to evolving simulator internals.'], version);
            uialert(obj.UIFigure, msg, 'About');
        end
    end

    methods(Static)
        function results = runSimWorker(cfg, mode, module)
            % runSimWorker
            % Background/foreground worker that runs one unified campaign file.

            if isstring(mode), mode = char(mode); end
            if isstring(module), module = char(module); end
            profile = lower(strtrim(char(string(mode))));
            if isempty(profile)
                profile = "full";
            end

            if exist('sixgr_run_3gpp_full_campaign','file') == 2
                resultsRoot = char(string(sixgr.util.structGet(cfg,'run.resultsRoot','results')));
                runE2E = logical(sixgr.util.structGet(cfg,'run.enableE2EProbe', true));
                e2eDur = double(sixgr.util.structGet(cfg,'run.e2eDuration_s', 60));
                e2eUE = double(sixgr.util.structGet(cfg,'run.e2eUECount', 8));
                e2eTraffic = char(string(sixgr.util.structGet(cfg,'run.e2eTrafficModel','xr')));
                enableAI = logical(sixgr.util.structGet(cfg,'ai.enable', true));
                linkSNR = double(sixgr.util.structGet(cfg,'channel.snr_dB', 20));
                nUE = max(4, round(double(sixgr.util.structGet(cfg,'scenario.ue.nUE', 120))));

                switch profile
                    case "quick"
                        linkDur = 60;
                        sysDur = 60;
                        linkMaxFrames = 220;
                        linkSweepFrames = 8;
                    case "long"
                        linkDur = 1800;
                        sysDur = 1800;
                        linkMaxFrames = 2400;
                        linkSweepFrames = 16;
                    otherwise % full
                        linkDur = 180;
                        sysDur = 180;
                        linkMaxFrames = 500;
                        linkSweepFrames = 12;
                end

                results = sixgr_run_3gpp_full_campaign(cfg, ...
                    "ResultsRoot", resultsRoot, ...
                    "LinkDuration_s", linkDur, ...
                    "SystemDuration_s", sysDur, ...
                    "LinkMaxSimFrames", linkMaxFrames, ...
                    "LinkSweepFrames", linkSweepFrames, ...
                    "SystemNumUE", nUE, ...
                    "LinkSNR_dB", linkSNR, ...
                    "RunE2EStackProbe", runE2E, ...
                    "E2EDuration_s", e2eDur, ...
                    "E2EUECount", e2eUE, ...
                    "E2ETrafficModel", e2eTraffic, ...
                    "E2EEnableAI", enableAI, ...
                    "Verbose", false);
                return;
            end

            error('SimSuiteGUI:RunFailed', ...
                'Unable to run simulation. Required entrypoint sixgr_run_3gpp_full_campaign is unavailable.');
        end

        function cfg = readJson_(filePath)
            % Prefer sixgr.util.jsonRead (comment-safe), else jsondecode
            if exist('sixgr.util.jsonRead','file') == 2
                cfg = sixgr.util.jsonRead(filePath);
                return;
            end
            txt = fileread(filePath);
            cfg = jsondecode(txt);
        end

        function writeJson_(filePath, cfg)
            if exist('sixgr.util.jsonWrite','file') == 2
                sixgr.util.jsonWrite(filePath, cfg);
                return;
            end
            txt = jsonencode(cfg, 'PrettyPrint', true);
            fid = fopen(filePath,'w');
            if fid < 0
                error('SimSuiteGUI:IO','Unable to open %s for writing.', filePath);
            end
            cleaner = onCleanup(@() fclose(fid));
            fwrite(fid, txt, 'char');
        end

        function runFolder = getRunFolder_(results)
            runFolder = '';
            try
                if isempty(results)
                    return;
                end

                if isa(results,'sixgr.core.SimResults')
                    if isprop(results,'RunFolder')
                        runFolder = char(results.RunFolder);
                        return;
                    end
                end

                if isstruct(results)
                    if isfield(results,'RunFolder')
                        runFolder = char(string(results.RunFolder));
                        return;
                    end
                    if isfield(results,'runFolder')
                        runFolder = char(string(results.runFolder));
                        return;
                    end
                    if isfield(results,'Summary') && isstruct(results.Summary) && isfield(results.Summary,'RunFolder')
                        runFolder = char(string(results.Summary.RunFolder));
                        return;
                    end
                end
            catch
            end
        end

        function runFolder = getRunFolderFromCfg_(cfg)
            runFolder = '';
            try
                if isstruct(cfg)
                    runFolder = char(string(sixgr.util.structGet(cfg,'run.resultsRoot','')));
                end
            catch
            end
        end
    end
end
