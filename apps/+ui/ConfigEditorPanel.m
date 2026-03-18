classdef ConfigEditorPanel < handle
% ui.ConfigEditorPanel
% JSON-centric config editor panel.
%
% This panel is designed to be robust across evolving config schemas.
% It edits the full config as JSON text (with PrettyPrint), and provides
% buttons to load/save/validate/apply.
%
% Integration
%   panel = ui.ConfigEditorPanel(parent, ...
%       'OnConfigChanged', @(cfg) ..., ...
%       'OnRequestScenarioRefresh', @() ...);
%
% File: apps/+ui/ConfigEditorPanel.m
% ASCII-only.

    properties
        Parent
        Grid matlab.ui.container.GridLayout

        BtnLoad matlab.ui.control.Button
        BtnSave matlab.ui.control.Button
        BtnReset matlab.ui.control.Button
        BtnValidate matlab.ui.control.Button
        BtnApply matlab.ui.control.Button
        BtnRefreshScenario matlab.ui.control.Button

        Txt matlab.ui.control.TextArea
        Status matlab.ui.control.Label

        OnConfigChanged = []
        OnRequestScenarioRefresh = []

        Cfg struct = struct()

        LastFile (1,:) char = ''
    end

    methods
        function obj = ConfigEditorPanel(parent, varargin)
            if nargin < 1 || isempty(parent)
                error('ui:ConfigEditorPanel:NeedParent','Parent container is required.');
            end
            obj.Parent = parent;

            % Parse name-values
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('ui:ConfigEditorPanel:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = string(varargin{i});
                    v = varargin{i+1};
                    switch lower(k)
                        case "onconfigchanged"
                            obj.OnConfigChanged = v;
                        case "onrequestscenariorefresh"
                            obj.OnRequestScenarioRefresh = v;
                        otherwise
                            error('ui:ConfigEditorPanel:BadOpt','Unknown option: %s', k);
                    end
                end
            end

            obj.buildUI_();
        end

        function setConfig(obj, cfg)
            if nargin < 2 || isempty(cfg)
                cfg = struct();
            end
            if ~isstruct(cfg)
                error('ui:ConfigEditorPanel:BadCfg','cfg must be a struct.');
            end
            obj.Cfg = cfg;
            obj.Txt.Value = obj.encodeJson_(cfg);
            obj.setStatus_('Config loaded into editor.');
        end

        function cfg = getConfig(obj)
            % Parse JSON from text area.
            txt = obj.Txt.Value;
            cfg = obj.decodeJsonFromText_(txt);
        end

        function applyToApp(obj)
            % Apply the current JSON to the app via callback.
            try
                cfg = obj.getConfig();
                obj.Cfg = cfg;
                if ~isempty(obj.OnConfigChanged)
                    obj.OnConfigChanged(cfg);
                end
                obj.setStatus_('Applied config to app.');
            catch ME
                obj.alert_(['Apply failed: ' ME.message], 'Config');
            end
        end
    end

    methods(Access=private)
        function buildUI_(obj)
            obj.Grid = uigridlayout(obj.Parent, [3 1]);
            obj.Grid.RowHeight = {34,'1x',22};
            obj.Grid.ColumnWidth = {'1x'};
            obj.Grid.Padding = [6 6 6 6];
            obj.Grid.RowSpacing = 6;

            btnRow = uigridlayout(obj.Grid,[1 6]);
            btnRow.Layout.Row = 1;
            btnRow.Layout.Column = 1;
            btnRow.ColumnWidth = {'1x','1x','1x','1x','1x','1x'};
            btnRow.RowHeight = {28};
            btnRow.Padding = [0 0 0 0];
            btnRow.ColumnSpacing = 6;

            obj.BtnLoad = uibutton(btnRow,'Text','Load','ButtonPushedFcn',@(~,~) obj.onLoad_());
            obj.BtnSave = uibutton(btnRow,'Text','Save','ButtonPushedFcn',@(~,~) obj.onSave_());
            obj.BtnReset = uibutton(btnRow,'Text','Defaults','ButtonPushedFcn',@(~,~) obj.onReset_());
            obj.BtnValidate = uibutton(btnRow,'Text','Validate','ButtonPushedFcn',@(~,~) obj.onValidate_());
            obj.BtnApply = uibutton(btnRow,'Text','Apply','ButtonPushedFcn',@(~,~) obj.applyToApp());
            obj.BtnRefreshScenario = uibutton(btnRow,'Text','Refresh Scenario','ButtonPushedFcn',@(~,~) obj.onRefreshScenario_());

            obj.Txt = uitextarea(obj.Grid);
            obj.Txt.Layout.Row = 2;
            obj.Txt.Layout.Column = 1;
            obj.Txt.FontName = 'Consolas';
            obj.Txt.FontSize = 12;

            obj.Status = uilabel(obj.Grid);
            obj.Status.Layout.Row = 3;
            obj.Status.Layout.Column = 1;
            obj.Status.Text = '';
            obj.Status.FontColor = [0.2 0.2 0.2];
        end

        function onLoad_(obj)
            [f,p] = uigetfile({'*.json','JSON config (*.json)';'*.*','All files'}, 'Load config');
            if isequal(f,0)
                return;
            end
            filePath = fullfile(p,f);

            try
                cfg = obj.readJsonFile_(filePath);

                % If your project provides a normalizer/validator loader, prefer it
                if exist('sixgr.config.loadConfig','file') == 2
                    try
                        cfg = sixgr.config.loadConfig(filePath);
                    catch
                        % keep raw
                    end
                end

                obj.LastFile = filePath;
                obj.setConfig(cfg);
                obj.setStatus_(sprintf('Loaded: %s', filePath));
            catch ME
                obj.alert_(['Load failed: ' ME.message], 'Load');
            end
        end

        function onSave_(obj)
            [f,p] = uiputfile({'*.json','JSON config (*.json)'}, 'Save config');
            if isequal(f,0)
                return;
            end
            filePath = fullfile(p,f);

            try
                cfg = obj.getConfig();
                obj.writeJsonFile_(filePath, cfg);
                obj.LastFile = filePath;
                obj.setStatus_(sprintf('Saved: %s', filePath));
            catch ME
                obj.alert_(['Save failed: ' ME.message], 'Save');
            end
        end

        function onReset_(obj)
            try
                if exist('sixgr.config.defaultConfig','file') == 2
                    cfg = sixgr.config.defaultConfig();
                else
                    cfg = struct();
                end
                obj.setConfig(cfg);
                obj.setStatus_('Reset to defaults. Click Apply to push into app.');
            catch ME
                obj.alert_(['Defaults failed: ' ME.message], 'Defaults');
            end
        end

        function onValidate_(obj)
            try
                cfg = obj.getConfig();

                if exist('sixgr.config.validateConfig','file') == 2
                    sixgr.config.validateConfig(cfg);
                    obj.setStatus_('Validation: OK');
                else
                    % Best-effort: basic JSON parse already succeeded
                    obj.setStatus_('Validation: OK (no validator found)');
                end
            catch ME
                obj.alert_(['Validation failed: ' ME.message], 'Validate');
            end
        end

        function onRefreshScenario_(obj)
            % Refresh scenario using current JSON text (do not require Apply)
            try
                cfg = obj.getConfig();
                if ~isempty(obj.OnConfigChanged)
                    obj.OnConfigChanged(cfg);
                end
                if ~isempty(obj.OnRequestScenarioRefresh)
                    obj.OnRequestScenarioRefresh();
                end
                obj.setStatus_('Scenario refresh requested.');
            catch ME
                obj.alert_(['Refresh failed: ' ME.message], 'Scenario');
            end
        end

        function setStatus_(obj, msg)
            obj.Status.Text = char(string(msg));
            drawnow limitrate;
        end

        function alert_(obj, msg, titleStr)
            try
                f = ancestor(obj.Parent,'figure');
                if ~isempty(f) && isa(f,'matlab.ui.Figure')
                    uialert(f, msg, titleStr);
                else
                    errordlg(msg, titleStr);
                end
            catch
                errordlg(msg, titleStr);
            end
        end

        function txt = encodeJson_(obj, cfg) %#ok<INUSL>
            % Pretty JSON text
            try
                txt = jsonencode(cfg, 'PrettyPrint', true);
            catch
                txt = jsonencode(cfg);
            end

            % TextArea expects cellstr/strings (one line per cell)
            if isstring(txt)
                txt = char(txt);
            end
            lines = splitlines(string(txt));
            % Remove possible trailing empty
            if ~isempty(lines) && strlength(lines(end))==0
                lines(end) = [];
            end
            txt = cellstr(lines);
        end

        function cfg = decodeJsonFromText_(obj, txt)
            % txt from uitextarea is cell array of lines or string
            if iscell(txt)
                s = strjoin(txt, '\n');
            else
                s = char(string(txt));
            end

            % Strip BOM if present
            if ~isempty(s) && s(1) == char(65279)
                s = s(2:end);
            end

            cfg = jsondecode(s);

            if ~isstruct(cfg)
                error('Config JSON must decode to a struct/object.');
            end

            % Optional: normalize if available
            if exist('sixgr.config.normalizeConfig','file') == 2
                try
                    cfg = sixgr.config.normalizeConfig(cfg);
                catch
                    % ignore
                end
            end
        end

        function cfg = readJsonFile_(obj, filePath) %#ok<INUSL>
            if exist('sixgr.util.jsonRead','file') == 2
                cfg = sixgr.util.jsonRead(filePath);
                return;
            end
            txt = fileread(filePath);
            cfg = jsondecode(txt);
        end

        function writeJsonFile_(obj, filePath, cfg) %#ok<INUSL>
            if exist('sixgr.util.jsonWrite','file') == 2
                sixgr.util.jsonWrite(filePath, cfg);
                return;
            end
            txt = jsonencode(cfg, 'PrettyPrint', true);
            fid = fopen(filePath,'w');
            if fid < 0
                error('Unable to open %s for writing.', filePath);
            end
            cleaner = onCleanup(@() fclose(fid));
            fwrite(fid, txt, 'char');
        end
    end
end
