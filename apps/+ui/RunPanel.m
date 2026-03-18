classdef RunPanel < handle
% ui.RunPanel
% Run control panel: choose mode/module, start/stop, show logs.
%
% This panel supports both synchronous and background (parfeval) execution.
%
% File: apps/+ui/RunPanel.m
% ASCII-only.

    properties
        Parent
        Grid matlab.ui.container.GridLayout

        % Controls
        DropMode matlab.ui.control.DropDown
        DropModule matlab.ui.control.DropDown
        CbExport matlab.ui.control.CheckBox

        BtnRun matlab.ui.control.Button
        BtnStop matlab.ui.control.Button
        BtnClearLog matlab.ui.control.Button
        BtnOpenRunFolder matlab.ui.control.Button

        Log matlab.ui.control.TextArea

        OnRunRequested = []
        OnOpenRunFolder = []

        Cfg struct = struct()
    end

    properties(Access=private)
        Future = []
        PollTimer = []
        ProgressDlg = []

        RunCompletionCb = []

        WorkerFcn = []
        WorkerCfg = []
        WorkerMode = ''
        WorkerModule = ''
    end

    methods
        function obj = RunPanel(parent, varargin)
            if nargin < 1 || isempty(parent)
                error('ui:RunPanel:NeedParent','Parent container is required.');
            end
            obj.Parent = parent;

            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('ui:RunPanel:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = string(varargin{i});
                    v = varargin{i+1};
                    switch lower(k)
                        case "onrunrequested"
                            obj.OnRunRequested = v;
                        case "onopenrunfolder"
                            obj.OnOpenRunFolder = v;
                        otherwise
                            error('ui:RunPanel:BadOpt','Unknown option: %s', k);
                    end
                end
            end

            obj.buildUI_();
        end

        function setConfig(obj, cfg)
            if nargin < 2 || isempty(cfg)
                cfg = struct();
            end
            obj.Cfg = cfg;
        end

        function appendLog(obj, msg)
            if nargin < 2
                return;
            end

            try
                t = datestr(now,'HH:MM:SS');
                line = sprintf('[%s] %s', t, char(string(msg)));

                cur = obj.Log.Value;
                if ischar(cur)
                    cur = {cur};
                end

                if isempty(cur)
                    obj.Log.Value = {line};
                else
                    obj.Log.Value = [cur; {line}];
                end
                drawnow limitrate;
            catch
                % ignore
            end
        end

        function cancelRun(obj)
            % cancelRun cancels any background run.
            try
                if ~isempty(obj.PollTimer) && isvalid(obj.PollTimer)
                    stop(obj.PollTimer);
                    delete(obj.PollTimer);
                end
            catch
            end
            obj.PollTimer = [];

            try
                if ~isempty(obj.Future)
                    cancel(obj.Future);
                end
            catch
            end
            obj.Future = [];

            try
                if ~isempty(obj.ProgressDlg) && isvalid(obj.ProgressDlg)
                    close(obj.ProgressDlg);
                end
            catch
            end
            obj.ProgressDlg = [];

            obj.BtnRun.Enable = 'on';
            obj.BtnStop.Enable = 'off';

            obj.appendLog('[Run] Cancelled.');
        end

        function runSimulation(obj, workerFcn, cfg, mode, module, onDone)
            % runSimulation(workerFcn, cfg, mode, module, onDone)
            %   workerFcn signature: results = workerFcn(cfg, mode, module)
            %   onDone signature: onDone(results, errMsg)

            obj.cancelRun();

            obj.WorkerFcn = workerFcn;
            obj.WorkerCfg = cfg;
            obj.WorkerMode = char(string(mode));
            obj.WorkerModule = char(string(module));
            obj.RunCompletionCb = onDone;

            obj.BtnRun.Enable = 'off';
            obj.BtnStop.Enable = 'on';

            fig = ancestor(obj.Parent,'figure');
            try
                obj.ProgressDlg = uiprogressdlg(fig, 'Title','Running', 'Message','Simulation running...', 'Indeterminate','on');
            catch
                obj.ProgressDlg = [];
            end

            % Prefer backgroundPool execution when available
            canBG = false;
            try
                canBG = exist('parfeval','file') == 2 && license('test','Distrib_Computing_Toolbox');
            catch
                canBG = false;
            end

            if canBG
                try
                    pool = backgroundPool;
                    obj.Future = parfeval(pool, workerFcn, 1, cfg, obj.WorkerMode, obj.WorkerModule);

                    obj.PollTimer = timer('ExecutionMode','fixedSpacing','Period',0.2, ...
                        'TimerFcn',@(~,~) obj.onPoll_());
                    start(obj.PollTimer);

                    obj.appendLog('[Run] Started in background.');
                    return;
                catch ME
                    obj.appendLog(sprintf('[Run] Background start failed, falling back to foreground: %s', ME.message));
                    % fallthrough
                end
            end

            % Foreground fallback
            obj.appendLog('[Run] Started in foreground.');
            try
                res = workerFcn(cfg, obj.WorkerMode, obj.WorkerModule);
                obj.finishRun_(res, '');
            catch ME
                obj.finishRun_([], ME.message);
            end
        end
    end

    methods(Access=private)
        function buildUI_(obj)
            obj.Grid = uigridlayout(obj.Parent, [3 1]);
            obj.Grid.RowHeight = {110,'1x',34};
            obj.Grid.ColumnWidth = {'1x'};
            obj.Grid.Padding = [6 6 6 6];
            obj.Grid.RowSpacing = 6;

            % Top controls grid
            top = uigridlayout(obj.Grid, [4 2]);
            top.Layout.Row = 1;
            top.Layout.Column = 1;
            top.RowHeight = {22,22,22,22};
            top.ColumnWidth = {120,'1x'};
            top.Padding = [0 0 0 0];
            top.RowSpacing = 6;
            top.ColumnSpacing = 8;

            uilabel(top,'Text','Run Profile:','HorizontalAlignment','right');
            obj.DropMode = uidropdown(top,'Items',{'full','quick','long'},'Value','full');

            uilabel(top,'Text','Runner:','HorizontalAlignment','right');
            obj.DropModule = uidropdown(top,'Items',{'sixgr_run_3gpp_full_campaign'},'Value','sixgr_run_3gpp_full_campaign');

            uilabel(top,'Text','Export after run:','HorizontalAlignment','right');
            obj.CbExport = uicheckbox(top,'Value', true);

            % Buttons row in top grid (span)
            btnRow = uigridlayout(top,[1 4]);
            btnRow.Layout.Row = 4;
            btnRow.Layout.Column = 1;
            btnRow.ColumnWidth = {'1x','1x','1x','1x'};
            btnRow.RowHeight = {28};
            btnRow.Padding = [0 0 0 0];
            btnRow.ColumnSpacing = 6;

            obj.BtnRun = uibutton(btnRow,'Text','Run','ButtonPushedFcn',@(~,~) obj.onRunButton_());
            obj.BtnStop = uibutton(btnRow,'Text','Stop','Enable','off','ButtonPushedFcn',@(~,~) obj.cancelRun());
            obj.BtnClearLog = uibutton(btnRow,'Text','Clear Log','ButtonPushedFcn',@(~,~) obj.onClearLog_());
            obj.BtnOpenRunFolder = uibutton(btnRow,'Text','Open Run Folder','ButtonPushedFcn',@(~,~) obj.onOpenFolder_());

            % Log
            obj.Log = uitextarea(obj.Grid);
            obj.Log.Layout.Row = 2;
            obj.Log.Layout.Column = 1;
            obj.Log.Editable = 'off';
            obj.Log.FontName = 'Consolas';
            obj.Log.FontSize = 12;

            % Footer hint
            foot = uilabel(obj.Grid);
            foot.Layout.Row = 3;
            foot.Layout.Column = 1;
            foot.Text = 'Tip: Use Config tab to edit cfg, then Run.';
            foot.FontColor = [0.3 0.3 0.3];
        end

        function onRunButton_(obj)
            if isempty(obj.OnRunRequested)
                obj.appendLog('[Run] No OnRunRequested callback configured.');
                return;
            end

            mode = obj.DropMode.Value;
            module = obj.DropModule.Value;
            exportAfter = logical(obj.CbExport.Value);

            obj.OnRunRequested(mode, module, exportAfter);
        end

        function onClearLog_(obj)
            obj.Log.Value = {};
        end

        function onOpenFolder_(obj)
            if ~isempty(obj.OnOpenRunFolder)
                obj.OnOpenRunFolder();
            end
        end

        function onPoll_(obj)
            % Poll background future
            if isempty(obj.Future)
                return;
            end

            st = '';
            try
                st = obj.Future.State;
            catch
                st = '';
            end

            if strcmpi(st,'finished')
                % Stop polling
                try
                    stop(obj.PollTimer);
                    delete(obj.PollTimer);
                catch
                end
                obj.PollTimer = [];

                % Fetch outputs
                try
                    res = fetchOutputs(obj.Future);
                    if iscell(res) && numel(res) == 1
                        res = res{1};
                    end
                    obj.finishRun_(res, '');
                catch ME
                    obj.finishRun_([], ME.message);
                end

            elseif strcmpi(st,'failed')
                try
                    stop(obj.PollTimer);
                    delete(obj.PollTimer);
                catch
                end
                obj.PollTimer = [];

                % Fetch error
                errMsg = 'Background run failed.';
                try
                    errMsg = obj.Future.Error.message;
                catch
                end
                obj.finishRun_([], errMsg);
            end
        end

        function finishRun_(obj, res, errMsg)
            % Common completion
            try
                if ~isempty(obj.ProgressDlg) && isvalid(obj.ProgressDlg)
                    close(obj.ProgressDlg);
                end
            catch
            end
            obj.ProgressDlg = [];

            obj.BtnRun.Enable = 'on';
            obj.BtnStop.Enable = 'off';

            obj.Future = [];

            % Invoke completion callback
            if ~isempty(obj.RunCompletionCb)
                try
                    obj.RunCompletionCb(res, errMsg);
                catch
                    % ignore
                end
            end
        end
    end
end
