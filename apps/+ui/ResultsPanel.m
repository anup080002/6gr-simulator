classdef ResultsPanel < handle
% ui.ResultsPanel
% Results viewer: summary + KPI tables + artifacts.
%
% This panel is tolerant to varying results schemas.
%
% File: apps/+ui/ResultsPanel.m
% ASCII-only.

    properties
        Parent
        Grid matlab.ui.container.GridLayout

        % Summary labels
        LblOk matlab.ui.control.Label
        LblRunFolder matlab.ui.control.Label
        LblStart matlab.ui.control.Label
        LblEnd matlab.ui.control.Label

        % KPI widgets
        ListKPI matlab.ui.control.ListBox
        TableKPI matlab.ui.control.Table

        % Artifacts
        ListArtifacts matlab.ui.control.ListBox

        % Buttons
        BtnExport matlab.ui.control.Button
        BtnOpenFolder matlab.ui.control.Button
        BtnRefresh matlab.ui.control.Button

        OnExportRequested = []
        OnOpenRunFolder = []

        Results = []
        Cfg struct = struct()
        ExportManifest = []
    end

    properties(Access=private)
        KPIStruct = struct()
        KPINameList cell = {}
        ArtifactList cell = {}
    end

    methods
        function obj = ResultsPanel(parent, varargin)
            if nargin < 1 || isempty(parent)
                error('ui:ResultsPanel:NeedParent','Parent container is required.');
            end
            obj.Parent = parent;

            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('ui:ResultsPanel:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = string(varargin{i});
                    v = varargin{i+1};
                    switch lower(k)
                        case "onexportrequested"
                            obj.OnExportRequested = v;
                        case "onopenrunfolder"
                            obj.OnOpenRunFolder = v;
                        otherwise
                            error('ui:ResultsPanel:BadOpt','Unknown option: %s', k);
                    end
                end
            end

            obj.buildUI_();
        end

        function setResults(obj, results, cfg)
            if nargin < 2
                results = [];
            end
            if nargin >= 3 && ~isempty(cfg)
                obj.Cfg = cfg;
            end
            obj.Results = results;

            obj.refresh();
        end

        function setExportManifest(obj, manifest)
            obj.ExportManifest = manifest;
            % Merge artifacts if present
            try
                if isstruct(manifest)
                    all = {};
                    if isfield(manifest,'mat'), all = [all; manifest.mat(:)]; end
                    if isfield(manifest,'csv'), all = [all; manifest.csv(:)]; end
                    if isfield(manifest,'fig'), all = [all; manifest.fig(:)]; end
                    if isfield(manifest,'other'), all = [all; manifest.other(:)]; end
                    obj.ArtifactList = unique(string(all));
                    obj.ListArtifacts.Items = cellstr(obj.ArtifactList);
                end
            catch
            end
        end

        function refresh(obj)
            % Refresh UI from current results
            res = obj.Results;

            runFolder = obj.getRunFolder_(res);
            ok = obj.getOk_(res);
            t0 = obj.getTime_(res, 'StartTime');
            t1 = obj.getTime_(res, 'EndTime');

            obj.LblOk.Text = sprintf('Ok: %s', string(ok));
            obj.LblRunFolder.Text = sprintf('RunFolder: %s', runFolder);
            obj.LblStart.Text = sprintf('Start: %s', t0);
            obj.LblEnd.Text = sprintf('End: %s', t1);

            % KPIs
            kpis = obj.getKPIs_(res);
            obj.KPIStruct = kpis;

            names = fieldnames(kpis);
            % Keep only tables for list
            keep = false(size(names));
            for i = 1:numel(names)
                v = kpis.(names{i});
                keep(i) = istable(v);
            end
            names = names(keep);
            obj.KPINameList = names;
            if isempty(names)
                obj.ListKPI.Items = {'(no KPI tables)'};
            else
                obj.ListKPI.Items = names;
            end

            % Artifacts
            obj.ArtifactList = obj.getArtifacts_(res);
            if isempty(obj.ArtifactList)
                obj.ListArtifacts.Items = {'(no artifacts)'};
            else
                obj.ListArtifacts.Items = cellstr(obj.ArtifactList);
            end

            % Reset KPI table view
            obj.TableKPI.Data = {};
        end
    end

    methods(Access=private)
        function buildUI_(obj)
            obj.Grid = uigridlayout(obj.Parent, [4 1]);
            obj.Grid.RowHeight = {90, 180, 120, 34};
            obj.Grid.ColumnWidth = {'1x'};
            obj.Grid.Padding = [6 6 6 6];
            obj.Grid.RowSpacing = 6;

            % Summary
            sumGrid = uigridlayout(obj.Grid,[4 1]);
            sumGrid.Layout.Row = 1;
            sumGrid.Padding = [0 0 0 0];
            sumGrid.RowHeight = {20,20,20,20};

            obj.LblOk = uilabel(sumGrid,'Text','Ok: -');
            obj.LblRunFolder = uilabel(sumGrid,'Text','RunFolder: -');
            obj.LblStart = uilabel(sumGrid,'Text','Start: -');
            obj.LblEnd = uilabel(sumGrid,'Text','End: -');

            % KPI section: list + table
            kpiGrid = uigridlayout(obj.Grid,[1 2]);
            kpiGrid.Layout.Row = 2;
            kpiGrid.ColumnWidth = {140,'1x'};
            kpiGrid.Padding = [0 0 0 0];
            kpiGrid.ColumnSpacing = 6;

            obj.ListKPI = uilistbox(kpiGrid,'Items',{'(no KPI tables)'},'ValueChangedFcn',@(~,~) obj.onSelectKPI_());
            obj.TableKPI = uitable(kpiGrid);
            obj.TableKPI.ColumnEditable = false;

            % Artifacts list
            artGrid = uigridlayout(obj.Grid,[2 1]);
            artGrid.Layout.Row = 3;
            artGrid.RowHeight = {18,'1x'};
            artGrid.Padding = [0 0 0 0];

            uilabel(artGrid,'Text','Artifacts:');
            obj.ListArtifacts = uilistbox(artGrid,'Items',{'(no artifacts)'},'ValueChangedFcn',@(~,~) obj.onSelectArtifact_());

            % Buttons
            btnRow = uigridlayout(obj.Grid,[1 3]);
            btnRow.Layout.Row = 4;
            btnRow.ColumnWidth = {'1x','1x','1x'};
            btnRow.Padding = [0 0 0 0];
            btnRow.ColumnSpacing = 6;

            obj.BtnExport = uibutton(btnRow,'Text','Export Results','ButtonPushedFcn',@(~,~) obj.onExport_());
            obj.BtnOpenFolder = uibutton(btnRow,'Text','Open Run Folder','ButtonPushedFcn',@(~,~) obj.onOpenFolder_());
            obj.BtnRefresh = uibutton(btnRow,'Text','Refresh','ButtonPushedFcn',@(~,~) obj.refresh());
        end

        function onSelectKPI_(obj)
            name = obj.ListKPI.Value;
            if isempty(name) || strcmp(name,'(no KPI tables)')
                obj.TableKPI.Data = {};
                return;
            end

            try
                T = obj.KPIStruct.(name);
                if istable(T)
                    obj.TableKPI.Data = T;
                else
                    obj.TableKPI.Data = {};
                end
            catch
                obj.TableKPI.Data = {};
            end
        end

        function onSelectArtifact_(obj)
            % Double-click open is not supported in uilistbox directly;
            % users can copy path from selection.
        end

        function onExport_(obj)
            if ~isempty(obj.OnExportRequested)
                obj.OnExportRequested();
            end
        end

        function onOpenFolder_(obj)
            if ~isempty(obj.OnOpenRunFolder)
                obj.OnOpenRunFolder();
            end
        end

        function runFolder = getRunFolder_(obj, res) %#ok<INUSL>
            runFolder = '';
            try
                if isempty(res)
                    return;
                end
                if isa(res,'sixgr.core.SimResults')
                    if isprop(res,'RunFolder')
                        runFolder = char(res.RunFolder);
                        return;
                    end
                end
                if isstruct(res)
                    if isfield(res,'RunFolder')
                        runFolder = char(string(res.RunFolder));
                        return;
                    end
                    if isfield(res,'runFolder')
                        runFolder = char(string(res.runFolder));
                        return;
                    end
                    if isfield(res,'Summary') && isstruct(res.Summary) && isfield(res.Summary,'RunFolder')
                        runFolder = char(string(res.Summary.RunFolder));
                        return;
                    end
                end
            catch
            end
        end

        function ok = getOk_(obj, res) %#ok<INUSL>
            ok = '-';
            try
                if isempty(res)
                    return;
                end
                if isa(res,'sixgr.core.SimResults')
                    if isprop(res,'Ok')
                        ok = res.Ok;
                        return;
                    end
                end
                if isstruct(res)
                    if isfield(res,'Ok')
                        ok = res.Ok;
                        return;
                    end
                    if isfield(res,'Summary') && isstruct(res.Summary) && isfield(res.Summary,'Ok')
                        ok = res.Summary.Ok;
                        return;
                    end
                end
            catch
            end
        end

        function t = getTime_(obj, res, fieldName) %#ok<INUSL>
            t = '-';
            try
                if isempty(res)
                    return;
                end
                if isa(res,'sixgr.core.SimResults')
                    if isprop(res, fieldName)
                        v = res.(fieldName);
                        t = obj.formatTime_(v);
                        return;
                    end
                end
                if isstruct(res)
                    if isfield(res, fieldName)
                        t = obj.formatTime_(res.(fieldName));
                        return;
                    end
                end
            catch
            end
        end

        function s = formatTime_(obj, v) %#ok<INUSL>
            if isempty(v)
                s = '-';
                return;
            end
            try
                if isa(v,'datetime')
                    s = char(string(v));
                else
                    s = char(string(v));
                end
            catch
                s = '-';
            end
        end

        function kpis = getKPIs_(obj, res) %#ok<INUSL>
            kpis = struct();
            try
                if isempty(res)
                    return;
                end
                if isa(res,'sixgr.core.SimResults')
                    if isprop(res,'KPIs')
                        kpis = res.KPIs;
                        return;
                    end
                end
                if isstruct(res)
                    if isfield(res,'KPIs')
                        kpis = res.KPIs;
                        return;
                    end
                    if isfield(res,'kpis')
                        kpis = res.kpis;
                        return;
                    end
                end
            catch
            end
        end

        function list = getArtifacts_(obj, res) %#ok<INUSL>
            list = strings(0,1);
            try
                if isempty(res)
                    return;
                end
                if isa(res,'sixgr.core.SimResults')
                    if isprop(res,'Artifacts')
                        A = res.Artifacts;
                        list = obj.flattenArtifacts_(A);
                        return;
                    end
                end
                if isstruct(res)
                    if isfield(res,'Artifacts')
                        list = obj.flattenArtifacts_(res.Artifacts);
                        return;
                    end
                    if isfield(res,'artifacts')
                        list = obj.flattenArtifacts_(res.artifacts);
                        return;
                    end
                end
            catch
            end
        end

        function list = flattenArtifacts_(obj, A) %#ok<INUSL>
            list = strings(0,1);
            if isempty(A)
                return;
            end

            if iscell(A)
                list = string(A(:));
                return;
            end

            if isstring(A)
                list = A(:);
                return;
            end

            if isstruct(A)
                all = {};
                fn = fieldnames(A);
                for i = 1:numel(fn)
                    v = A.(fn{i});
                    if iscell(v)
                        all = [all; v(:)]; %#ok<AGROW>
                    elseif isstring(v)
                        all = [all; cellstr(v(:))]; %#ok<AGROW>
                    elseif ischar(v)
                        all = [all; {v}]; %#ok<AGROW>
                    end
                end
                list = string(all);
                list = unique(list);
                return;
            end

            % unknown type
        end
    end
end
