function figs = PlotLinkKPIs(results, varargin)
% sixgr.visual.PlotLinkKPIs
% Generate link-level KPI plots from a results container.
%
% This function is intentionally tolerant to different KPI table schemas.
% It searches for tables containing common NR link metrics and plots what
% is available.
%
% Inputs
%   results : sixgr.core.SimResults | struct
%
% Name-value options
%   'FigurePrefix' : prefix for figure names
%   'MakeInvisible': true -> figures are created invisible (default false)
%
% Output
%   figs : struct of figure handles (fields present depend on data)
%
% File: +sixgr/+visual/PlotLinkKPIs.m
% ASCII-only.

opt.FigurePrefix = 'Link';
opt.MakeInvisible = false;

if ~isempty(varargin)
    if mod(numel(varargin),2) ~= 0
        error('sixgr:visual:PlotLinkKPIs:BadNV','Name-value inputs must come in pairs.');
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
                error('sixgr:visual:PlotLinkKPIs:BadOpt','Unknown option: %s', k);
        end
    end
end

kpis = localGetKPIs(results);
[tbls, names] = localCollectTables(kpis);

figs = struct();
madeAny = false;

% Find a primary table with SNR
idx = localFindTableWithVar(tbls, {'snr','snr_db','esno','esno_db'});
if idx == 0 && ~isempty(tbls)
    idx = 1;
end

if idx == 0
    % nothing to plot
    return;
end

T = tbls{idx};

% Extract x-axis: SNR or Eb/No
[x, xname] = localFindNumericVar(T, {'SNR_dB','SNR','EsNo_dB','EbNo_dB','EsNo','EbNo'});

% Plot BLER
[y, yname] = localFindNumericVar(T, {'BLER','bler','TB_BLER','PDSCH_BLER','PUSCH_BLER'});
if ~isempty(x) && ~isempty(y)
    figs.BLER = localMakeFig(opt, sprintf('%s_BLER', opt.FigurePrefix));
    ax = axes(figs.BLER);
    semilogy(ax, x, max(y, eps));
    grid(ax,'on');
    xlabel(ax, xname);
    ylabel(ax, yname);
    title(ax, sprintf('%s: %s vs %s', opt.FigurePrefix, yname, xname));
    madeAny = true;
end

% Plot BER
[y, yname] = localFindNumericVar(T, {'BER','ber','BitErrorRate'});
if ~isempty(x) && ~isempty(y)
    figs.BER = localMakeFig(opt, sprintf('%s_BER', opt.FigurePrefix));
    ax = axes(figs.BER);
    semilogy(ax, x, max(y, eps));
    grid(ax,'on');
    xlabel(ax, xname);
    ylabel(ax, yname);
    title(ax, sprintf('%s: %s vs %s', opt.FigurePrefix, yname, xname));
    madeAny = true;
end

% Plot throughput
[y, yname] = localFindNumericVar(T, {'Throughput_Mbps','ThroughputGbps','Tput_Mbps','Tput'});
if ~isempty(x) && ~isempty(y)
    figs.Throughput = localMakeFig(opt, sprintf('%s_Throughput', opt.FigurePrefix));
    ax = axes(figs.Throughput);
    plot(ax, x, y);
    grid(ax,'on');
    xlabel(ax, xname);
    ylabel(ax, yname);
    title(ax, sprintf('%s: %s vs %s', opt.FigurePrefix, yname, xname));
    madeAny = true;
end

% Plot EVM
[y, yname] = localFindNumericVar(T, {'EVM_rms','EVM','EVM_percent','EVM_rms_percent'});
if ~isempty(x) && ~isempty(y)
    figs.EVM = localMakeFig(opt, sprintf('%s_EVM', opt.FigurePrefix));
    ax = axes(figs.EVM);
    plot(ax, x, y);
    grid(ax,'on');
    xlabel(ax, xname);
    ylabel(ax, yname);
    title(ax, sprintf('%s: %s vs %s', opt.FigurePrefix, yname, xname));
    madeAny = true;
end

% If a PAPR CCDF table exists, plot it
idxP = localFindTableWithVar(tbls, {'papr','ccdf'});
if idxP ~= 0
    TP = tbls{idxP};
    [px, pxname] = localFindNumericVar(TP, {'PAPR_dB','PAPR','PAPRdb'});
    [py, pyname] = localFindNumericVar(TP, {'CCDF','ccdf','Pr'});
    if ~isempty(px) && ~isempty(py)
        figs.PAPR = localMakeFig(opt, sprintf('%s_PAPR_CCDF', opt.FigurePrefix));
        ax = axes(figs.PAPR);
        semilogy(ax, px, max(py, eps));
        grid(ax,'on');
        xlabel(ax, pxname);
        ylabel(ax, pyname);
        title(ax, sprintf('%s: PAPR CCDF', opt.FigurePrefix));
        madeAny = true;
    end
end

% Fallback for case-wise KPI tables (no SNR axis).
if ~madeAny
    [caseLbl, hasCase] = localCaseLabels(T);
    if hasCase
        [yBler, ~] = localFindNumericVar(T, {'BLER','bler','TB_BLER','PDSCH_BLER','PUSCH_BLER'});
        if ~isempty(yBler)
            figs.BLER_ByCase = localMakeFig(opt, sprintf('%s_BLER_ByCase', opt.FigurePrefix));
            ax = axes(figs.BLER_ByCase);
            semilogy(ax, 1:numel(yBler), max(yBler, eps), 'o-');
            grid(ax, 'on');
            set(ax, 'XTick', 1:numel(yBler), 'XTickLabel', caseLbl);
            xtickangle(ax, 25);
            xlabel(ax, 'Case');
            ylabel(ax, 'BLER');
            title(ax, sprintf('%s: BLER by Case', opt.FigurePrefix));
            madeAny = true;
        end

        [yBer, ~] = localFindNumericVar(T, {'BER','ber','BitErrorRate'});
        if ~isempty(yBer)
            figs.BER_ByCase = localMakeFig(opt, sprintf('%s_BER_ByCase', opt.FigurePrefix));
            ax = axes(figs.BER_ByCase);
            semilogy(ax, 1:numel(yBer), max(yBer, eps), 'o-');
            grid(ax, 'on');
            set(ax, 'XTick', 1:numel(yBer), 'XTickLabel', caseLbl);
            xtickangle(ax, 25);
            xlabel(ax, 'Case');
            ylabel(ax, 'BER');
            title(ax, sprintf('%s: BER by Case', opt.FigurePrefix));
            madeAny = true;
        end

        [yThr, yThrName] = localFindNumericVar(T, {'Throughput_Mbps','ThroughputGbps','Tput_Mbps','Tput'});
        if ~isempty(yThr)
            figs.Throughput_ByCase = localMakeFig(opt, sprintf('%s_Throughput_ByCase', opt.FigurePrefix));
            ax = axes(figs.Throughput_ByCase);
            bar(ax, 1:numel(yThr), yThr);
            grid(ax, 'on');
            set(ax, 'XTick', 1:numel(yThr), 'XTickLabel', caseLbl);
            xtickangle(ax, 25);
            xlabel(ax, 'Case');
            ylabel(ax, yThrName);
            title(ax, sprintf('%s: %s by Case', opt.FigurePrefix, yThrName));
            madeAny = true;
        end
    end
end

% Attach names for debugging
figs.DebugTables = names; %#ok<STRNU>

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
    % exact match preferred
    j = find(strcmpi(vnames, c), 1);
    if isempty(j)
        % fuzzy match
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

function [lbl, ok] = localCaseLabels(T)
lbl = strings(0,1);
ok = false;
if ~istable(T)
    return;
end
vnames = string(T.Properties.VariableNames);
j = find(strcmpi(vnames, "Case"), 1, "first");
if isempty(j)
    return;
end
c = T.(vnames(j));
lbl = string(c(:));
lbl = strrep(lbl, "_", "\_");
ok = ~isempty(lbl);
end
