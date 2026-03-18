function [fig, ax, h] = PlotMobility(layout, ueTrace, varargin)
% sixgr.visual.PlotMobility
% Plot UE mobility tracks (2D) with optional BS/TRxP overlay.
%
% Inputs
%   layout  : layout struct (optional; can pass [])
%   ueTrace : numeric Kx3xT array OR struct containing a trace field
%
% Name-value options
%   'Figure'        : existing figure handle
%   'Title'         : title string
%   'UEIds'         : plot subset of UE ids (requires ueTrace.ueId or layout)
%   'MaxUEs'        : cap number of UEs rendered (default 50)
%   'ShowBS'        : show BS/TRxP positions (default true)
%   'ShowArea'      : show scenario area rectangle if available (default true)
%   'AxisEqual'     : axis equal (default true)
%
% Outputs
%   fig, ax, handles struct h
%
% File: +sixgr/+visual/PlotMobility.m
% ASCII-only.

if nargin < 1
    layout = [];
end
if nargin < 2
    error('sixgr:visual:PlotMobility:NeedTrace','ueTrace is required.');
end

opt.Figure = [];
opt.Title = '';
opt.UEIds = [];
opt.MaxUEs = 50;
opt.ShowBS = true;
opt.ShowArea = true;
opt.AxisEqual = true;

if ~isempty(varargin)
    if mod(numel(varargin),2) ~= 0
        error('sixgr:visual:PlotMobility:BadNV','Name-value inputs must come in pairs.');
    end
    for i = 1:2:numel(varargin)
        k = string(varargin{i});
        v = varargin{i+1};
        switch lower(k)
            case "figure"
                opt.Figure = v;
            case "title"
                opt.Title = char(v);
            case {"ueids","ueid"}
                opt.UEIds = double(v(:));
            case "maxues"
                opt.MaxUEs = double(v);
            case "showbs"
                opt.ShowBS = logical(v);
            case "showarea"
                opt.ShowArea = logical(v);
            case "axisequal"
                opt.AxisEqual = logical(v);
            otherwise
                error('sixgr:visual:PlotMobility:BadOpt','Unknown option: %s', k);
        end
    end
end

[pos, ids] = localParseTrace(ueTrace);
% pos is K x 3 x T
K = size(pos,1);
T = size(pos,3);

% Subset by UEIds if possible
if ~isempty(opt.UEIds) && ~isempty(ids)
    keep = ismember(ids(:), opt.UEIds(:));
    pos = pos(keep,:,:);
    ids = ids(keep);
    K = size(pos,1);
end

% Cap UEs
maxN = max(1, round(opt.MaxUEs));
if K > maxN
    pos = pos(1:maxN,:,:);
    if ~isempty(ids)
        ids = ids(1:maxN);
    end
    K = maxN;
end

% Figure
if isempty(opt.Figure)
    fig = figure('Name','sixgr PlotMobility','NumberTitle','off');
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

% Area
if opt.ShowArea && ~isempty(layout) && isfield(layout,'area_m') && numel(layout.area_m)==2
    W = double(layout.area_m(1));
    H = double(layout.area_m(2));
    h.Area = rectangle(ax,'Position',[-W/2 -H/2 W H],'LineStyle','--','DisplayName','Area');
end

% BS overlay
if opt.ShowBS && ~isempty(layout) && isfield(layout,'bs') && isfield(layout.bs,'pos_m')
    bp = double(layout.bs.pos_m);
    h.BS = plot(ax, bp(:,1), bp(:,2), '^', 'DisplayName','BS/TRxP');
end

% Tracks
for k = 1:K
    xy = squeeze(pos(k,1:2,:)); % 2 x T
    h.Track(k,1) = plot(ax, xy(1,:), xy(2,:), '-', 'DisplayName', localTrackName(ids,k)); %#ok<AGROW>
    % Start/end markers
    h.Start(k,1) = plot(ax, xy(1,1), xy(2,1), 'o', 'HandleVisibility','off'); %#ok<AGROW>
    h.End(k,1)   = plot(ax, xy(1,end), xy(2,end), 'x', 'HandleVisibility','off'); %#ok<AGROW>
end

% Title
if isempty(opt.Title)
    ttl = sprintf('Mobility tracks (T=%d)', T);
else
    ttl = opt.Title;
end

title(ax, ttl);

if opt.AxisEqual
    axis(ax,'equal');
end

legend(ax,'Location','best');

hold(ax,'off');

end

% ---------------- helpers ----------------

function [pos, ids] = localParseTrace(ueTrace)
ids = [];

if isstruct(ueTrace)
    if isfield(ueTrace,'pos_m')
        pos = ueTrace.pos_m;
    elseif isfield(ueTrace,'posTrace_m')
        pos = ueTrace.posTrace_m;
    elseif isfield(ueTrace,'pos')
        pos = ueTrace.pos;
    else
        error('sixgr:visual:PlotMobility:BadTrace','ueTrace struct must contain pos_m/posTrace_m/pos.');
    end

    if isfield(ueTrace,'ueId')
        ids = double(ueTrace.ueId(:));
    elseif isfield(ueTrace,'id')
        ids = double(ueTrace.id(:));
    end
else
    pos = ueTrace;
end

if ~isnumeric(pos) || ndims(pos) < 3
    error('sixgr:visual:PlotMobility:BadTrace','ueTrace must be numeric Kx3xT.');
end

% Normalize to K x 3 x T
if size(pos,2) == 3
    % ok
elseif size(pos,1) == 3
    pos = permute(pos,[2 1 3]);
elseif size(pos,3) == 3
    pos = permute(pos,[1 3 2]);
else
    error('sixgr:visual:PlotMobility:BadTrace','Cannot infer Kx3xT shape for ueTrace.');
end

pos = double(pos);
end

function name = localTrackName(ids,k)
if ~isempty(ids)
    name = sprintf('UE %d', ids(k));
else
    name = sprintf('UE %d', k);
end
end
