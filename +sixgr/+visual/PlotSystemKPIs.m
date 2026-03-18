function figs = PlotSystemKPIs(results, varargin)
% sixgr.visual.PlotSystemKPIs
% Generate system-level KPI plots from a results container.
%
% This is an abstract/system-level plotting helper. It searches for
% commonly-named KPI tables (throughput, latency, fairness) and plots what
% is available.
%
% Inputs
%   results : sixgr.core.SimResults | struct
%
% Name-value options
%   'FigurePrefix' : prefix for figure names
%   'MakeInvisible': true -> figures created invisible
%
% Output
%   figs : struct of figure handles
%
% File: +sixgr/+visual/PlotSystemKPIs.m
% ASCII-only.

opt.FigurePrefix = 'System';
opt.MakeInvisible = false;

if ~isempty(varargin)
    if mod(numel(varargin),2) ~= 0
        error('sixgr:visual:PlotSystemKPIs:BadNV','Name-value inputs must come in pairs.');
    end
    for i = 1:2:numel(varargin)
        k = string(varargin{i});
        v = varargin{i+1};
        switch lower(k)
            case "figureprefix"
                opt.FigurePrefix = char(v);
            case "makeinvisible"
                opt.MakeInvisible = logical(v);
            otherwise
                error('sixgr:visual:PlotSystemKPIs:BadOpt','Unknown option: %s', k);
        end
    end
end

kpis = localGetKPIs(results);
[tbls, names] = localCollectTables(kpis);

figs = struct();

if isempty(tbls)
    return;
end

% 1) Throughput over time (TTI/slot)
idx = localFindTableWithVar(tbls, {'tti','slot','time','t_s'});
if idx ~= 0
    T = tbls{idx};
    [x, xname] = localFindNumericVar(T, {'Time_s','t_s','TTI','Slot','Frame'});
    [y, yname] = localFindNumericVar(T, {'CellThroughput_Mbps','CellTput_Mbps','Throughput_Mbps','Tput_Mbps'});
    if ~isempty(x) && ~isempty(y)
        figs.CellThroughput = localMakeFig(opt, sprintf('%s_CellThroughput', opt.FigurePrefix));
        ax = axes(figs.CellThroughput);
        plot(ax, x, y);
        grid(ax,'on');
        xlabel(ax, xname);
        ylabel(ax, yname);
        title(ax, sprintf('%s: %s vs %s', opt.FigurePrefix, yname, xname));
    end
end

% 2) Per-UE throughput distribution
idx = localFindTableWithVar(tbls, {'ue','ueid','user'});
if idx ~= 0
    T = tbls{idx};
    [y, yname] = localFindNumericVar(T, {'UEThroughput_Mbps','Throughput_Mbps','AvgThroughput_Mbps'});
    if ~isempty(y)
        figs.UEThroughput = localMakeFig(opt, sprintf('%s_UEThroughput', opt.FigurePrefix));
        ax = axes(figs.UEThroughput);
        plot(ax, sort(y));
        grid(ax,'on');
        xlabel(ax, 'UE index (sorted)');
        ylabel(ax, yname);
        title(ax, sprintf('%s: UE throughput distribution', opt.FigurePrefix));
    end
end

% 3) Latency CDF
idx = localFindTableWithVar(tbls, {'latency','delay'});
if idx ~= 0
    T = tbls{idx};
    [lat, lname] = localFindNumericVar(T, {'Latency_ms','Latency','Delay_ms','Delay'});
    if ~isempty(lat)
        lat = sort(lat(:));
        cdfy = (1:numel(lat))'/max(1,numel(lat));
        figs.LatencyCDF = localMakeFig(opt, sprintf('%s_LatencyCDF', opt.FigurePrefix));
        ax = axes(figs.LatencyCDF);
        plot(ax, lat, cdfy);
        grid(ax,'on');
        xlabel(ax, lname);
        ylabel(ax, 'CDF');
        title(ax, sprintf('%s: Latency CDF', opt.FigurePrefix));
    end
end

% Attach table names for debugging
figs._Tables = names; %#ok<STRNU>

end

% ---------------- helpers ----------------

function kpis = localGetKPIs(results)
if isa(results,'sixgr.core.SimResults')
    kpis = results.KPIs;
elseif isstruct(results)
    if isfield(results,'KPIs')
        kpis = results.KPIs;
    elseif isfield(results,'kpis')
        kpis = results.kpis;
    else
        kpis = struct();
    end
else
    kpis = struct();
end
end

function [tbls, names] = localCollectTables(kpis)
fields = fieldnames(kpis);
tbls = {};
names = {};
for i = 1:numel(fields)
    f = fields{i};
    v = kpis.(f);
    if istable(v)
        tbls{end+1,1} = v; %#ok<AGROW>
        names{end+1,1} = f; %#ok<AGROW>
    end
end
end

function idx = localFindTableWithVar(tbls, varCandidates)
idx = 0;
for i = 1:numel(tbls)
    T = tbls{i};
    vnames = lower(string(T.Properties.VariableNames));
    hit = false;
    for k = 1:numel(varCandidates)
        if any(contains(vnames, lower(string(varCandidates{k}))))
            hit = true;
            break;
        end
    end
    if hit
        idx = i;
        return;
    end
end
end

function [x, name] = localFindNumericVar(T, candidates)
x = [];
name = '';
if ~istable(T)
    return;
end
vnames = string(T.Properties.VariableNames);
for i = 1:numel(candidates)
    c = string(candidates{i});
    j = find(strcmpi(vnames, c), 1);
    if isempty(j)
        j = find(contains(lower(vnames), lower(c)), 1);
    end
    if ~isempty(j)
        vec = T.(vnames(j));
        if isnumeric(vec)
            x = double(vec(:));
            name = char(vnames(j));
            return;
        end
    end
end
end

function fig = localMakeFig(opt, name)
vis = 'on';
if opt.MakeInvisible
    vis = 'off';
end
fig = figure('Name',name,'NumberTitle','off','Visible',vis);
end
