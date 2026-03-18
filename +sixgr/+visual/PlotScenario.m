function [fig, ax, h] = PlotScenario(layout, ue, varargin)
% sixgr.visual.PlotScenario
% Plot scenario layout (BS/TRxP + UE drop) in 2D.
%
% Inputs
%   layout : struct from sixgr.scenario.generateLayout
%   ue     : struct from sixgr.scenario.dropUEs (optional)
%
% Name-value options
%   'Figure'            : existing figure handle (optional)
%   'Title'             : plot title (char/string)
%   'ShowSites'         : true/false (default true)
%   'ShowSectors'       : true/false (default true)
%   'ShowUE'            : true/false (default true)
%   'UEColorByIndoor'   : true/false (default true)
%   'MaxUEs'            : cap number of UEs rendered (default 200)
%   'AxisEqual'         : true/false (default true)
%   'Legend'            : true/false (default true)
%
% Outputs
%   fig : figure handle
%   ax  : axes handle
%   h   : struct of plot handles
%
% File: +sixgr/+visual/PlotScenario.m
% ASCII-only.

if nargin < 1
    error('sixgr:visual:PlotScenario:NeedLayout','layout is required.');
end
if nargin < 2
    ue = struct();
end

% Defaults
opt.Figure = [];
opt.Title = '';
opt.ShowSites = true;
opt.ShowSectors = true;
opt.ShowUE = true;
opt.UEColorByIndoor = true;
opt.MaxUEs = 200;
opt.AxisEqual = true;
opt.Legend = true;

% Parse name-value
if ~isempty(varargin)
    if mod(numel(varargin),2) ~= 0
        error('sixgr:visual:PlotScenario:BadNV','Name-value inputs must come in pairs.');
    end
    for i = 1:2:numel(varargin)
        k = string(varargin{i});
        v = varargin{i+1};
        switch lower(k)
            case "figure"
                opt.Figure = v;
            case "title"
                opt.Title = char(v);
            case "showsites"
                opt.ShowSites = logical(v);
            case "showsectors"
                opt.ShowSectors = logical(v);
            case "showue"
                opt.ShowUE = logical(v);
            case "uecolorbyindoor"
                opt.UEColorByIndoor = logical(v);
            case "maxues"
                opt.MaxUEs = double(v);
            case "axisequal"
                opt.AxisEqual = logical(v);
            case "legend"
                opt.Legend = logical(v);
            otherwise
                error('sixgr:visual:PlotScenario:BadOpt','Unknown option: %s', k);
        end
    end
end

% Figure/axes
if isempty(opt.Figure)
    fig = figure('Name','sixgr PlotScenario','NumberTitle','off');
else
    fig = opt.Figure;
    figure(fig);
    clf(fig);
end
ax = axes(fig);
hold(ax,'on');
grid(ax,'on');
xlabel(ax,'x (m)');
ylabel(ax,'y (m)');

h = struct();

% Scenario area
if isfield(layout,'area_m') && numel(layout.area_m)==2
    W = double(layout.area_m(1));
    H = double(layout.area_m(2));
    h.Area = rectangle(ax, 'Position', [-W/2 -H/2 W H], 'LineStyle','--', 'DisplayName','Area');
end

% Sites
if opt.ShowSites && isfield(layout,'sites') && isfield(layout.sites,'pos_m')
    sp = double(layout.sites.pos_m);
    if ~isempty(sp)
        h.Sites = plot(ax, sp(:,1), sp(:,2), 's', 'DisplayName','Sites');
    end
end

% BS/TRxP
if isfield(layout,'bs') && isfield(layout.bs,'pos_m')
    bp = double(layout.bs.pos_m);
    if ~isempty(bp)
        h.BS = plot(ax, bp(:,1), bp(:,2), '^', 'DisplayName','BS/TRxP');

        % Sector arrows
        if opt.ShowSectors && isfield(layout.bs,'azim_deg')
            az = double(layout.bs.azim_deg(:));
            L = 20;
            dx = L*cosd(az);
            dy = L*sind(az);
            h.Sectors = quiver(ax, bp(:,1), bp(:,2), dx, dy, 0, 'DisplayName','Sectors');
        end
    end
end

% UEs
if opt.ShowUE && isfield(ue,'pos_m')
    up = double(ue.pos_m);
    if ~isempty(up)
        % cap
        maxN = max(1, round(opt.MaxUEs));
        if size(up,1) > maxN
            up = up(1:maxN,:);
            if isfield(ue,'indoor')
                ue.indoor = ue.indoor(1:maxN);
            end
        end

        if opt.UEColorByIndoor && isfield(ue,'indoor')
            in = logical(ue.indoor(:));
            h.UEIndoor = plot(ax, up(in,1), up(in,2), '.', 'DisplayName','UE indoor');
            h.UEOutdoor = plot(ax, up(~in,1), up(~in,2), '.', 'DisplayName','UE');
        else
            h.UE = plot(ax, up(:,1), up(:,2), '.', 'DisplayName','UE');
        end
    end
end

% Title
if isempty(opt.Title)
    if isfield(layout,'profileName')
        ttl = sprintf('Scenario: %s', char(string(layout.profileName)));
    else
        ttl = 'Scenario';
    end
else
    ttl = opt.Title;
end

title(ax, ttl);

if opt.AxisEqual
    axis(ax,'equal');
end

if opt.Legend
    legend(ax,'Location','best');
end

hold(ax,'off');

end
