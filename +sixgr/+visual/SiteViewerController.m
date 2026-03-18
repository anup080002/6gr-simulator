classdef SiteViewerController < handle
% sixgr.visual.SiteViewerController
% Attach txsite/rxsite/siteviewer and animate UE movement.
%
% This controller is optional (NOT coder-friendly). It is designed to be
% used by interactive runs and by report generation.
%
% Key features
%   - Works in cartesian coordinate system (meters) to match
%     sixgr.scenario.generateLayout/dropUEs outputs.
%   - Gracefully degrades when Site Viewer is unavailable:
%       -> falls back to a normal MATLAB figure (2D plot).
%
% Typical usage
%   cfg = sixgr.config.defaultConfig();
%   layout = sixgr.scenario.generateLayout(cfg);
%   ue = sixgr.scenario.dropUEs(cfg, layout);
%
%   vis = sixgr.visual.SiteViewerController(cfg, layout, ue);
%   vis.updateUE(ue);
%   vis.capture(fullfile(pwd,'snapshot.png'));
%
%   % Animate trace (K x 3 x T):
%   vis.animate(layout, ueTrace, 'Dt_s', 0.1);
%
% File: +sixgr/+visual/SiteViewerController.m
% ASCII-only.

    properties
        Cfg struct = struct()
        Logger = []

        % Rendering controls
        EnableSiteViewer (1,1) logical = true
        CoordinateSystem (1,1) string = "cartesian" % "cartesian" only for now
        Basemap (1,1) string = "streets"            % used if siteviewer supports basemap

        MaxUEsToRender (1,1) double = 50
        UEIdsToRender double = []

        ShowSectorArrows (1,1) logical = true
        ShowLinks (1,1) logical = false

        % If set, save snapshots into this folder during animate()
        SnapshotFolder (1,:) char = ''
        SnapshotEvery (1,1) double = 0 % 0 disables
    end

    properties(SetAccess=private)
        HasSiteViewer (1,1) logical = false
        Viewer = []
        Fig = []
        Ax = []

        TxSites = [] % txsite array
        RxSites = [] % rxsite array

        Layout = struct()
        UE = struct()

        % 2D fallback graphics handles
        hBS = []
        hUE = []
        hUEIndoor = []
        hSector = []
        hLinks = []

        % internal snapshot counter
        SnapshotCount (1,1) double = 0
    end

    methods
        function obj = SiteViewerController(cfg, layout, ue, varargin)
            % SiteViewerController(cfg, layout, ue, Name,Value,...)
            if nargin >= 1 && ~isempty(cfg)
                obj.Cfg = cfg;
            end
            if nargin >= 2 && ~isempty(layout)
                obj.Layout = layout;
            end
            if nargin >= 3 && ~isempty(ue)
                obj.UE = ue;
            end

            % Read defaults from cfg if present
            try
                obj.EnableSiteViewer = logical(sixgr.util.structGet(cfg,'visual.siteviewer.enable', obj.EnableSiteViewer));
                obj.MaxUEsToRender   = double(sixgr.util.structGet(cfg,'visual.siteviewer.maxUEs', obj.MaxUEsToRender));
                obj.ShowLinks        = logical(sixgr.util.structGet(cfg,'visual.siteviewer.showLinks', obj.ShowLinks));
            catch
            end

            % Apply name-value overrides
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:visual:SiteViewerController:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = string(varargin{i});
                    v = varargin{i+1};
                    switch lower(k)
                        case "logger"
                            obj.Logger = v;
                        case "enablesiteviewer"
                            obj.EnableSiteViewer = logical(v);
                        case "maxuestorender"
                            obj.MaxUEsToRender = double(v);
                        case {"ueidstorender","ueids"}
                            obj.UEIdsToRender = double(v);
                        case "showlinks"
                            obj.ShowLinks = logical(v);
                        case "showsectorarrows"
                            obj.ShowSectorArrows = logical(v);
                        case "snapshotfolder"
                            obj.SnapshotFolder = char(v);
                        case "snapshotevery"
                            obj.SnapshotEvery = double(v);
                        otherwise
                            error('sixgr:visual:SiteViewerController:BadOpt','Unknown option: %s', k);
                    end
                end
            end

            obj.setup();
        end

        function setup(obj)
            % Create viewer and initial sites/plots.

            % Decide UE subset for rendering
            ue = obj.UE;
            if isfield(ue,'id')
                ueIdsAll = double(ue.id(:));
            else
                ueIdsAll = (1:size(ue.pos_m,1)).';
            end

            if ~isempty(obj.UEIdsToRender)
                ueMask = ismember(ueIdsAll, obj.UEIdsToRender(:));
            else
                ueMask = true(size(ueIdsAll));
            end

            % Cap number of UEs to render (for siteviewer performance)
            maxN = max(1, round(obj.MaxUEsToRender));
            idx = find(ueMask);
            if numel(idx) > maxN
                idx = idx(1:maxN);
            end

            % Store subset UE
            ue2 = ue;
            if isfield(ue2,'pos_m')
                ue2.pos_m = ue2.pos_m(idx,:);
            end
            if isfield(ue2,'id')
                ue2.id = ue2.id(idx);
            end
            if isfield(ue2,'indoor')
                ue2.indoor = ue2.indoor(idx);
            end
            obj.UE = ue2;

            % Try siteviewer path
            obj.HasSiteViewer = false;
            if obj.EnableSiteViewer && exist('siteviewer','file') == 2
                try
                    obj.Viewer = obj.localCreateSiteViewer_();
                    obj.HasSiteViewer = ~isempty(obj.Viewer);
                catch
                    obj.Viewer = [];
                    obj.HasSiteViewer = false;
                end
            end

            if obj.HasSiteViewer
                obj.createSitesInViewer_();
            else
                obj.createFallbackFigure_();
            end
        end

        function updateUE(obj, ue)
            % Update UE positions (works for siteviewer or fallback plot)
            if nargin < 2 || isempty(ue)
                ue = obj.UE;
            end

            if obj.HasSiteViewer
                obj.updateRxSites_(ue);
            else
                obj.updateFallbackUE_(ue);
            end

            obj.UE = ue;
        end

        function updateLayout(obj, layout)
            % Update layout (BS sites are usually static; can refresh)
            if nargin < 2 || isempty(layout)
                layout = obj.Layout;
            end
            obj.Layout = layout;

            if obj.HasSiteViewer
                % easiest: re-create
                obj.createSitesInViewer_();
            else
                obj.createFallbackFigure_();
            end
        end

        function animate(obj, layout, ueTrace, varargin)
            % animate(layout, ueTrace, Name,Value,...)
            % ueTrace: K x 3 x T numeric array (meters) OR struct with pos_m
            %
            % Name-value:
            %   'Dt_s'     : seconds between frames (default 0.05)
            %   'Time_s'   : vector length T (optional)
            %   'UEIds'    : render subset

            if nargin < 2 || isempty(layout)
                layout = obj.Layout;
            end

            dt_s = 0.05;
            t_s = [];
            ueIds = [];
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:visual:SiteViewerController:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = string(varargin{i});
                    v = varargin{i+1};
                    switch lower(k)
                        case "dt_s"
                            dt_s = double(v);
                        case {"time_s","t_s"}
                            t_s = double(v(:));
                        case "ueids"
                            ueIds = double(v(:));
                        otherwise
                            error('sixgr:visual:SiteViewerController:BadOpt','Unknown option: %s', k);
                    end
                end
            end

            pos = obj.localParseUETrace_(ueTrace);
            % pos is K x 3 x T
            K = size(pos,1);
            T = size(pos,3);

            % Apply UE subset mapping if ids are provided
            if ~isempty(ueIds) && isfield(obj.UE,'id')
                idsCur = double(obj.UE.id(:));
                keep = ismember(idsCur, ueIds);
                idsCur = idsCur(keep);
                pos = pos(keep,:,:);
                K = size(pos,1);
            end

            if isempty(t_s)
                t_s = (0:T-1) * dt_s;
            end

            % Ensure snapshot folder
            if ~isempty(obj.SnapshotFolder)
                try
                    sixgr.util.ensureDir(obj.SnapshotFolder);
                catch
                    if ~isfolder(obj.SnapshotFolder)
                        mkdir(obj.SnapshotFolder);
                    end
                end
            end

            for tt = 1:T
                ue = obj.UE;
                if isfield(ue,'pos_m')
                    ue.pos_m = pos(:,:,tt);
                else
                    ue.pos_m = pos(:,:,tt);
                end

                obj.updateUE(ue);

                if ~isempty(obj.Logger) && isa(obj.Logger,'sixgr.core.Logger')
                    if mod(tt, max(1,round(T/10))) == 0
                        obj.Logger.info(sprintf('SiteViewer animate: frame %d/%d (t=%.3fs)', tt, T, t_s(tt)));
                    end
                end

                % Optional snapshot
                if obj.SnapshotEvery > 0 && ~isempty(obj.SnapshotFolder)
                    if mod(tt-1, round(obj.SnapshotEvery)) == 0
                        obj.SnapshotCount = obj.SnapshotCount + 1;
                        fn = fullfile(obj.SnapshotFolder, sprintf('frame_%05d.png', obj.SnapshotCount));
                        obj.capture(fn);
                    end
                end

                drawnow;
                pause(max(0, dt_s));
            end
        end

        function capture(obj, filePath)
            % capture Save a snapshot to an image file.
            if nargin < 2 || isempty(filePath)
                error('sixgr:visual:SiteViewerController:NeedFile','Provide filePath for capture().');
            end
            filePath = char(filePath);
            try
                sixgr.util.ensureDir(filePath);
            catch
                % ignore
            end

            if obj.HasSiteViewer
                % siteviewer snapshot API differs by release; try common ones
                try
                    snapshot(obj.Viewer, filePath);
                    return;
                catch
                end
                try
                    % Some releases expose Viewer.Figure
                    if isprop(obj.Viewer,'Figure') && ~isempty(obj.Viewer.Figure)
                        exportgraphics(obj.Viewer.Figure, filePath);
                        return;
                    end
                catch
                end
            end

            % fallback to figure
            if ~isempty(obj.Fig) && isvalid(obj.Fig)
                try
                    exportgraphics(obj.Fig, filePath);
                catch
                    try
                        saveas(obj.Fig, filePath);
                    catch
                        % last resort
                        print(obj.Fig, filePath, '-dpng', '-r150');
                    end
                end
            else
                error('sixgr:visual:SiteViewerController:NoFigure','No viewer/figure available to capture.');
            end
        end

        function close(obj)
            % close viewer/figure
            try
                if ~isempty(obj.Fig) && isvalid(obj.Fig)
                    close(obj.Fig);
                end
            catch
            end
            obj.Fig = [];
            obj.Ax = [];
            obj.Viewer = [];
            obj.TxSites = [];
            obj.RxSites = [];
            obj.HasSiteViewer = false;
        end

        function delete(obj)
            obj.close();
        end
    end

    methods(Access=private)
        function viewer = localCreateSiteViewer_(obj)
            % Create siteviewer with best-effort arguments.
            viewer = [];

            try
                viewer = siteviewer('CoordinateSystem','cartesian');
                return;
            catch
            end

            try
                viewer = siteviewer("CoordinateSystem","cartesian");
                return;
            catch
            end

            try
                viewer = siteviewer;
                % Try set property
                try
                    if isprop(viewer,'CoordinateSystem')
                        viewer.CoordinateSystem = 'cartesian';
                    end
                catch
                end
                return;
            catch
            end
        end

        function createSitesInViewer_(obj)
            % Create txsite/rxsite objects in siteviewer.
            layout = obj.Layout;
            ue = obj.UE;

            if isempty(layout) || ~isfield(layout,'bs') || ~isfield(layout.bs,'pos_m')
                error('sixgr:visual:SiteViewerController:BadLayout','layout.bs.pos_m is required.');
            end
            if isempty(ue) || ~isfield(ue,'pos_m')
                error('sixgr:visual:SiteViewerController:BadUE','ue.pos_m is required.');
            end

            % Remove previous if present
            obj.TxSites = [];
            obj.RxSites = [];

            bsPos = double(layout.bs.pos_m);
            nBS = size(bsPos,1);

            % Frequency for rendering (optional)
            fc = double(sixgr.util.structGet(obj.Cfg,'channel.fc_Hz', 3.5e9));

            % Create BS txsite array (build dynamically to avoid requiring a default constructor)
            tx = [];
            for i = 1:nBS
                tx(i,1) = txsite('CoordinateSystem','cartesian', ...
                    'Name', sprintf('BS%02d', i), ...
                    'AntennaPosition', bsPos(i,:), ...
                    'TransmitterFrequency', fc, ...
                    'TransmitterPower', 0);
                try
                    show(tx(i), 'Parent', obj.Viewer);
                catch
                    try
                        show(tx(i));
                    catch
                    end
                end
            end

            % Create UE rxsite array
            uePos = double(ue.pos_m);
            K = size(uePos,1);

            if exist('rxsite','file') == 2
                rx = [];
                for k = 1:K
                    rx(k,1) = rxsite('CoordinateSystem','cartesian', ...
                        'Name', sprintf('UE%03d', k), ...
                        'AntennaPosition', uePos(k,:));
                    try
                        show(rx(k), 'Parent', obj.Viewer);
                    catch
                        try
                            show(rx(k));
                        catch
                        end
                    end
                end
            else
                % Fallback: visualize UEs as txsites with 0 power
                rx = [];
                for k = 1:K
                    t = txsite('CoordinateSystem','cartesian', ...
                        'Name', sprintf('UE%03d', k), ...
                        'AntennaPosition', uePos(k,:), ...
                        'TransmitterFrequency', fc, ...
                        'TransmitterPower', 0);
                    rx(k,1) = t; %#ok<AGROW>
                    try
                        show(rx(k), 'Parent', obj.Viewer);
                    catch
                        try
                            show(rx(k));
                        catch
                        end
                    end
                end
            end

            obj.TxSites = tx;
            obj.RxSites = rx;

            % Optional sector arrows: not natively supported in siteviewer;
            % keep for fallback only.
        end

        function updateRxSites_(obj, ue)
            if isempty(obj.RxSites)
                % Create from scratch
                obj.UE = ue;
                obj.createSitesInViewer_();
                return;
            end

            uePos = double(ue.pos_m);
            K = min(size(uePos,1), numel(obj.RxSites));
            for k = 1:K
                try
                    obj.RxSites(k).AntennaPosition = uePos(k,:);
                catch
                    % If immutable, recreate that UE site
                    try
                        name = sprintf('UE%03d', k);
                        if exist('rxsite','file') == 2
                            obj.RxSites(k) = rxsite('CoordinateSystem','cartesian', ...
                                'Name', name, ...
                                'AntennaPosition', uePos(k,:));
                        else
                            fc = double(sixgr.util.structGet(obj.Cfg,'channel.fc_Hz', 3.5e9));
                            obj.RxSites(k) = txsite('CoordinateSystem','cartesian', ...
                                'Name', name, ...
                                'AntennaPosition', uePos(k,:), ...
                                'TransmitterFrequency', fc, ...
                                'TransmitterPower', 0);
                        end
                        try
                            show(obj.RxSites(k), 'Parent', obj.Viewer);
                        catch
                        end
                    catch
                    end
                end
            end
        end

        function createFallbackFigure_(obj)
            % Standard 2D figure fallback
            layout = obj.Layout;
            ue = obj.UE;

            if isempty(obj.Fig) || ~isvalid(obj.Fig)
                obj.Fig = figure('Name','sixgr Scenario Viewer','NumberTitle','off');
            else
                figure(obj.Fig);
                clf(obj.Fig);
            end

            obj.Ax = axes(obj.Fig);
            hold(obj.Ax,'on');
            grid(obj.Ax,'on');
            xlabel(obj.Ax,'x (m)');
            ylabel(obj.Ax,'y (m)');

            % Plot area rectangle if available
            if isfield(layout,'area_m') && numel(layout.area_m)==2
                W = double(layout.area_m(1));
                H = double(layout.area_m(2));
                rectangle(obj.Ax, 'Position', [-W/2 -H/2 W H], 'LineStyle','--');
            end

            % BS positions
            if isfield(layout,'bs') && isfield(layout.bs,'pos_m')
                bs = double(layout.bs.pos_m);
                obj.hBS = plot(obj.Ax, bs(:,1), bs(:,2), '^', 'DisplayName','BS');

                % Sector arrows
                if obj.ShowSectorArrows && isfield(layout.bs,'azim_deg')
                    az = double(layout.bs.azim_deg(:));
                    L = 20;
                    dx = L*cosd(az);
                    dy = L*sind(az);
                    obj.hSector = quiver(obj.Ax, bs(:,1), bs(:,2), dx, dy, 0, 'DisplayName','Sector');
                end
            end

            % UE positions
            if isfield(ue,'pos_m')
                pos = double(ue.pos_m);
                if isfield(ue,'indoor')
                    in = logical(ue.indoor(:));
                else
                    in = false(size(pos,1),1);
                end
                obj.hUEIndoor = plot(obj.Ax, pos(in,1), pos(in,2), '.', 'DisplayName','UE indoor');
                obj.hUE = plot(obj.Ax, pos(~in,1), pos(~in,2), '.', 'DisplayName','UE');
            end

            axis(obj.Ax,'equal');
            legend(obj.Ax,'Location','best');

            hold(obj.Ax,'off');
        end

        function updateFallbackUE_(obj, ue)
            if isempty(obj.Ax) || ~isvalid(obj.Ax)
                obj.UE = ue;
                obj.createFallbackFigure_();
                return;
            end

            if ~isfield(ue,'pos_m')
                return;
            end
            pos = double(ue.pos_m);
            if isfield(ue,'indoor')
                in = logical(ue.indoor(:));
            else
                in = false(size(pos,1),1);
            end

            if ~isempty(obj.hUEIndoor) && isvalid(obj.hUEIndoor)
                set(obj.hUEIndoor,'XData',pos(in,1),'YData',pos(in,2));
            end
            if ~isempty(obj.hUE) && isvalid(obj.hUE)
                set(obj.hUE,'XData',pos(~in,1),'YData',pos(~in,2));
            end
        end

        function pos = localParseUETrace_(obj, ueTrace) %#ok<INUSL>
            % Parse ueTrace to K x 3 x T numeric
            if isstruct(ueTrace)
                if isfield(ueTrace,'pos_m')
                    pos = ueTrace.pos_m;
                elseif isfield(ueTrace,'pos')
                    pos = ueTrace.pos;
                elseif isfield(ueTrace,'posTrace_m')
                    pos = ueTrace.posTrace_m;
                else
                    error('sixgr:visual:SiteViewerController:BadTrace','ueTrace struct must contain pos_m or posTrace_m.');
                end
            else
                pos = ueTrace;
            end

            if ~isnumeric(pos) || ndims(pos) < 3
                error('sixgr:visual:SiteViewerController:BadTrace','ueTrace must be numeric Kx3xT.');
            end

            % Common layouts: K x 3 x T (preferred). If 3 x K x T, permute.
            if size(pos,2) == 3
                % ok
            elseif size(pos,1) == 3
                pos = permute(pos,[2 1 3]);
            elseif size(pos,3) == 3
                pos = permute(pos,[1 3 2]);
            else
                error('sixgr:visual:SiteViewerController:BadTrace','Cannot infer Kx3xT shape for ueTrace.');
            end

            pos = double(pos);
        end
    end
end
