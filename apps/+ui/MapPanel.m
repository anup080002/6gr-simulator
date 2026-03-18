classdef MapPanel < handle
% ui.MapPanel
% In-app scenario map + mobility animation (uiaxes).
%
% This panel plots:
%   - Scenario area
%   - BS/TRxP locations (+ optional sector arrows)
%   - UE locations
%   - Optional mobility animation from UETrace
%
% It can also launch a separate Site Viewer window using
% sixgr.visual.SiteViewerController when available.
%
% File: apps/+ui/MapPanel.m
% ASCII-only.

    properties
        Parent
        Grid matlab.ui.container.GridLayout

        Toolbar matlab.ui.container.GridLayout
        BtnRefresh matlab.ui.control.Button
        BtnPlot matlab.ui.control.Button
        BtnAnimate matlab.ui.control.Button
        BtnOpenSiteViewer matlab.ui.control.Button
        BtnClear matlab.ui.control.Button

        LblInfo matlab.ui.control.Label

        Ax matlab.ui.control.UIAxes

        OnRequestScenarioRefresh = []

        % Data
        Cfg struct = struct()
        Layout struct = struct()
        UE struct = struct()
        UETrace = []
    end

    properties(Access=private)
        hArea = []
        hBS = []
        hSectors = []
        hUE = []
        hUEIndoor = []

        IsAnimating (1,1) logical = false
        SiteViewerCtrl = []
    end

    methods
        function obj = MapPanel(parent, varargin)
            if nargin < 1 || isempty(parent)
                error('ui:MapPanel:NeedParent','Parent container is required.');
            end
            obj.Parent = parent;

            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('ui:MapPanel:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = string(varargin{i});
                    v = varargin{i+1};
                    switch lower(k)
                        case "onrequestscenariorefresh"
                            obj.OnRequestScenarioRefresh = v;
                        otherwise
                            error('ui:MapPanel:BadOpt','Unknown option: %s', k);
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

        function setScenario(obj, layout, ue, ueTrace)
            if nargin < 2, layout = struct(); end
            if nargin < 3, ue = struct(); end
            if nargin < 4, ueTrace = []; end

            obj.Layout = layout;
            obj.UE = ue;
            obj.UETrace = ueTrace;

            obj.renderScenario();

            % Update siteviewer if open
            try
                if ~isempty(obj.SiteViewerCtrl)
                    obj.SiteViewerCtrl.updateLayout(layout);
                    obj.SiteViewerCtrl.updateUE(ue);
                end
            catch
            end
        end

        function renderScenario(obj)
            % Render layout + UE drop in the uiaxes
            ax = obj.Ax;
            cla(ax);
            hold(ax,'on');
            grid(ax,'on');
            xlabel(ax,'x (m)');
            ylabel(ax,'y (m)');

            layout = obj.Layout;
            ue = obj.UE;

            % Area
            obj.hArea = [];
            if isfield(layout,'area_m') && numel(layout.area_m)==2
                W = double(layout.area_m(1));
                H = double(layout.area_m(2));
                obj.hArea = rectangle(ax,'Position',[-W/2 -H/2 W H],'LineStyle','--');
            end

            % BS
            obj.hBS = [];
            obj.hSectors = [];
            if isfield(layout,'bs') && isfield(layout.bs,'pos_m')
                bp = double(layout.bs.pos_m);
                if ~isempty(bp)
                    obj.hBS = scatter(ax, bp(:,1), bp(:,2), 50, '^', 'filled');

                    if isfield(layout.bs,'azim_deg')
                        az = double(layout.bs.azim_deg(:));
                        L = 20;
                        dx = L*cosd(az);
                        dy = L*sind(az);
                        obj.hSectors = quiver(ax, bp(:,1), bp(:,2), dx, dy, 0);
                    end
                end
            end

            % UE
            obj.hUE = [];
            obj.hUEIndoor = [];
            if isfield(ue,'pos_m')
                up = double(ue.pos_m);
                if ~isempty(up)
                    if isfield(ue,'indoor')
                        in = logical(ue.indoor(:));
                    else
                        in = false(size(up,1),1);
                    end

                    if any(in)
                        obj.hUEIndoor = scatter(ax, up(in,1), up(in,2), 18, '.');
                    end
                    if any(~in)
                        obj.hUE = scatter(ax, up(~in,1), up(~in,2), 18, '.');
                    end
                end
            end

            axis(ax,'equal');
            title(ax, obj.makeTitle_());
            hold(ax,'off');

            obj.LblInfo.Text = obj.makeInfoText_();
        end

        function animate(obj, varargin)
            % animate UETrace (Kx3xT) if present.
            % Name-value:
            %   'Dt_s' : pause between frames (default 0.05)

            if obj.IsAnimating
                return;
            end

            dt_s = 0.05;
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('ui:MapPanel:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = string(varargin{i});
                    v = varargin{i+1};
                    switch lower(k)
                        case "dt_s"
                            dt_s = double(v);
                        otherwise
                            error('ui:MapPanel:BadOpt','Unknown option: %s', k);
                    end
                end
            end

            pos = obj.parseUETrace_(obj.UETrace);
            if isempty(pos)
                uialert(ancestor(obj.Parent,'figure'),'No UETrace available to animate.','Animate');
                return;
            end

            obj.IsAnimating = true;
            c = onCleanup(@() obj.stopAnimate_()); %#ok<NASGU>

            T = size(pos,3);

            % If scatter handles exist, update them; else rerender each frame
            for t = 1:T
                if ~obj.IsAnimating
                    break;
                end

                ue = obj.UE;
                ue.pos_m = pos(:,:,t);

                obj.updateUEPositions_(ue);

                % Update siteviewer if open
                try
                    if ~isempty(obj.SiteViewerCtrl)
                        obj.SiteViewerCtrl.updateUE(ue);
                    end
                catch
                end

                drawnow;
                pause(max(0, dt_s));
            end
        end

        function cancelAnimation(obj)
            obj.IsAnimating = false;
        end

        function openSiteViewer(obj)
            % Launch separate Site Viewer controller if available
            if exist('sixgr.visual.SiteViewerController','class') ~= 8
                uialert(ancestor(obj.Parent,'figure'), 'sixgr.visual.SiteViewerController not found on path.', 'Site Viewer');
                return;
            end

            try
                if isempty(obj.SiteViewerCtrl)
                    obj.SiteViewerCtrl = sixgr.visual.SiteViewerController(obj.Cfg, obj.Layout, obj.UE, ...
                        'MaxUEsToRender', 50);
                else
                    obj.SiteViewerCtrl.updateLayout(obj.Layout);
                    obj.SiteViewerCtrl.updateUE(obj.UE);
                end
            catch ME
                uialert(ancestor(obj.Parent,'figure'), ME.message, 'Site Viewer');
            end
        end

        function clear(obj)
            cla(obj.Ax);
            obj.LblInfo.Text = '';
        end
    end

    methods(Access=private)
        function buildUI_(obj)
            obj.Grid = uigridlayout(obj.Parent, [2 1]);
            obj.Grid.RowHeight = {38,'1x'};
            obj.Grid.ColumnWidth = {'1x'};
            obj.Grid.Padding = [6 6 6 6];
            obj.Grid.RowSpacing = 6;

            obj.Toolbar = uigridlayout(obj.Grid, [1 6]);
            obj.Toolbar.Layout.Row = 1;
            obj.Toolbar.Layout.Column = 1;
            obj.Toolbar.RowHeight = {28};
            obj.Toolbar.ColumnWidth = {90,90,90,120,70,'1x'};
            obj.Toolbar.Padding = [0 0 0 0];
            obj.Toolbar.ColumnSpacing = 6;

            obj.BtnRefresh = uibutton(obj.Toolbar,'Text','Refresh','ButtonPushedFcn',@(~,~) obj.onRefresh_());
            obj.BtnPlot = uibutton(obj.Toolbar,'Text','Plot','ButtonPushedFcn',@(~,~) obj.renderScenario());
            obj.BtnAnimate = uibutton(obj.Toolbar,'Text','Animate','ButtonPushedFcn',@(~,~) obj.onAnimate_());
            obj.BtnOpenSiteViewer = uibutton(obj.Toolbar,'Text','Site Viewer','ButtonPushedFcn',@(~,~) obj.openSiteViewer());
            obj.BtnClear = uibutton(obj.Toolbar,'Text','Clear','ButtonPushedFcn',@(~,~) obj.clear());

            obj.LblInfo = uilabel(obj.Toolbar);
            obj.LblInfo.Text = '';
            obj.LblInfo.HorizontalAlignment = 'right';

            obj.Ax = uiaxes(obj.Grid);
            obj.Ax.Layout.Row = 2;
            obj.Ax.Layout.Column = 1;
            obj.Ax.Box = 'on';
        end

        function onRefresh_(obj)
            if ~isempty(obj.OnRequestScenarioRefresh)
                obj.OnRequestScenarioRefresh();
            else
                obj.renderScenario();
            end
        end

        function onAnimate_(obj)
            if obj.IsAnimating
                obj.cancelAnimation();
                return;
            end
            obj.animate('Dt_s', 0.05);
        end

        function stopAnimate_(obj)
            obj.IsAnimating = false;
        end

        function updateUEPositions_(obj, ue)
            % Update scatter points for UE positions.
            if ~isfield(ue,'pos_m')
                return;
            end
            up = double(ue.pos_m);

            if isfield(ue,'indoor')
                in = logical(ue.indoor(:));
            else
                in = false(size(up,1),1);
            end

            if ~isempty(obj.hUEIndoor) && isvalid(obj.hUEIndoor)
                set(obj.hUEIndoor,'XData', up(in,1), 'YData', up(in,2));
            elseif any(in)
                hold(obj.Ax,'on');
                obj.hUEIndoor = scatter(obj.Ax, up(in,1), up(in,2), 18, '.');
                hold(obj.Ax,'off');
            end

            if ~isempty(obj.hUE) && isvalid(obj.hUE)
                set(obj.hUE,'XData', up(~in,1), 'YData', up(~in,2));
            elseif any(~in)
                hold(obj.Ax,'on');
                obj.hUE = scatter(obj.Ax, up(~in,1), up(~in,2), 18, '.');
                hold(obj.Ax,'off');
            end

            % Update title with time index if desired (omitted)
        end

        function txt = makeTitle_(obj)
            if isfield(obj.Layout,'profileName')
                txt = sprintf('Scenario: %s', char(string(obj.Layout.profileName)));
            else
                txt = 'Scenario';
            end
        end

        function txt = makeInfoText_(obj)
            nBS = 0;
            nUE = 0;

            try
                if isfield(obj.Layout,'bs') && isfield(obj.Layout.bs,'pos_m')
                    nBS = size(obj.Layout.bs.pos_m,1);
                end
                if isfield(obj.UE,'pos_m')
                    nUE = size(obj.UE.pos_m,1);
                end
            catch
            end

            txt = sprintf('BS=%d  UE=%d', nBS, nUE);
        end

        function pos = parseUETrace_(obj, ueTrace) %#ok<INUSL>
            pos = [];
            if isempty(ueTrace)
                return;
            end

            if isstruct(ueTrace)
                if isfield(ueTrace,'pos_m')
                    pos = ueTrace.pos_m;
                elseif isfield(ueTrace,'posTrace_m')
                    pos = ueTrace.posTrace_m;
                elseif isfield(ueTrace,'pos')
                    pos = ueTrace.pos;
                else
                    pos = [];
                end
            else
                pos = ueTrace;
            end

            if isempty(pos)
                return;
            end

            if ~isnumeric(pos) || ndims(pos) < 3
                pos = [];
                return;
            end

            % Normalize to K x 3 x T
            if size(pos,2) == 3
                % ok
            elseif size(pos,1) == 3
                pos = permute(pos,[2 1 3]);
            elseif size(pos,3) == 3
                pos = permute(pos,[1 3 2]);
            else
                pos = [];
                return;
            end

            pos = double(pos);
        end
    end
end
