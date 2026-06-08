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

T = localResolvePrimarySweepTable(kpis, tbls);
if isempty(T)
    return;
end

% Extract x-axis: SNR or Eb/No
[x, xname] = localFindNumericVar(T, {'SNR_dB','SNR','EsNo_dB','EbNo_dB','EsNo','EbNo'});

% Plot BLER
[figs, made] = localMaybePlotSweepMetric(figs, "BLER", opt, T, x, xname, ...
    {'DL_BLER','UL_BLER','BLER','PDSCH_BLER','PUSCH_BLER'}, {'DL','UL','Aggregate','PDSCH','PUSCH'}, ...
    "BLER", true);
madeAny = made || madeAny;

% Plot BER
[figs, made] = localMaybePlotSweepMetric(figs, "BER", opt, T, x, xname, ...
    {'DL_BER','UL_BER','BER','BitErrorRate'}, {'DL','UL','Aggregate','Aggregate'}, ...
    "BER", true);
madeAny = made || madeAny;

% Plot throughput
[figs, made] = localMaybePlotSweepMetric(figs, "Throughput", opt, T, x, xname, ...
    {'DL_Throughput_Mbps','UL_Throughput_Mbps','Throughput_Mbps','Tput_Mbps','Tput'}, {'DL','UL','Aggregate','Aggregate','Aggregate'}, ...
    "Throughput (Mbps)", false);
madeAny = made || madeAny;

% Plot goodput when present; this is the primary successful-user-bit KPI.
[figs, made] = localMaybePlotSweepMetric(figs, "Goodput", opt, T, x, xname, ...
    {'DL_Goodput_Mbps','UL_Goodput_Mbps','Goodput_Mbps'}, {'DL','UL','Aggregate'}, ...
    "Goodput (Mbps)", false);
madeAny = made || madeAny;

% Plot EVM
[figs, made] = localMaybePlotSweepMetric(figs, "EVM", opt, T, x, xname, ...
    {'DL_EVM_rms','UL_EVM_rms','EVM_rms','EVM','EVM_percent','EVM_rms_percent'}, {'DL','UL','Aggregate','Aggregate','Aggregate','Aggregate'}, ...
    "EVM", false);
madeAny = made || madeAny;

% If a PAPR CCDF table exists, plot it
[figs, made] = localMaybePlotPAPR(figs, opt, kpis);
madeAny = made || madeAny;

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

        [yThr, yThrName] = localFindNumericVar(T, {'Goodput_Mbps','Throughput_Mbps','ThroughputGbps','Tput_Mbps','Tput'});
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

function T = localResolvePrimarySweepTable(kpis, tbls)
T = table();
if isstruct(kpis) && isfield(kpis, 'LinkSNRSweep') && istable(kpis.LinkSNRSweep) && ...
        ~isempty(kpis.LinkSNRSweep) && ismember("SNR_dB", string(kpis.LinkSNRSweep.Properties.VariableNames))
    T = kpis.LinkSNRSweep;
    return;
end

idx = localFindTableWithVar(tbls, {'snr','snr_db','esno','esno_db'});
if idx == 0 && ~isempty(tbls)
    idx = 1;
end
if idx ~= 0
    T = tbls{idx};
end
end

function [figs, made] = localMaybePlotSweepMetric(figs, fieldName, opt, T, x, xname, candidates, labels, yLabel, useLog)
made = false;
if isempty(x)
    return;
end
[series, names, sourceVars] = localFindNamedSeries(T, candidates, labels);
if isempty(series)
    return;
end
figs.(fieldName) = localMakeFig(opt, sprintf('%s_%s', opt.FigurePrefix, fieldName)); %#ok<NASGU>
ax = axes(figs.(fieldName));
hold(ax, 'on');
if useLog
    set(ax, 'YScale', 'log');
end
for i = 1:numel(series)
    y = series{i};
    yPlot = y;
    if useLog
        yPlot = localResolveLogSweepSeries(T, sourceVars{i}, yPlot);
    end
    mask = isfinite(x) & isfinite(yPlot);
    if ~any(mask)
        continue;
    end
    localPlotDiscreteSweepSeries(ax, x(mask), yPlot(mask), useLog, names{i});
    made = true;
end
if ~made
    close(figs.(fieldName));
    figs.(fieldName) = [];
    return;
end
grid(ax,'on');
xlabel(ax, xname, 'Interpreter', 'none');
ylabel(ax, yLabel, 'Interpreter', 'none');
title(ax, sprintf('%s: %s vs %s', opt.FigurePrefix, yLabel, xname), 'Interpreter', 'none');
localApplyFiniteXLimits(ax, x);
localApplyFiniteSweepTicks(ax, x);
if numel(series) > 1
    legend(ax, 'Location', 'best');
end
end

function [figs, made] = localMaybePlotPAPR(figs, opt, kpis)
made = false;
if ~(isstruct(kpis) && isfield(kpis, 'PAPRCCDF') && istable(kpis.PAPRCCDF))
    return;
end
TP = kpis.PAPRCCDF;
if isempty(TP) || ~all(ismember(["PAPR_dB","CCDF"], string(TP.Properties.VariableNames)))
    return;
end
figs.PAPR = localMakeFig(opt, sprintf('%s_PAPR_CCDF', opt.FigurePrefix)); %#ok<NASGU>
ax = axes(figs.PAPR);
hold(ax, 'on');
if ismember("Direction", string(TP.Properties.VariableNames))
    dirs = unique(string(TP.Direction));
else
    dirs = "Aggregate";
    TP.Direction = repmat("Aggregate", height(TP), 1);
end
for i = 1:numel(dirs)
    maskDir = string(TP.Direction) == dirs(i);
    x = double(TP.PAPR_dB(maskDir));
    y = double(TP.CCDF(maskDir));
    mask = isfinite(x) & isfinite(y);
    if ~any(mask)
        continue;
    end
    [xSorted, order] = sort(x(mask));
    ySorted = y(mask);
    ySorted = ySorted(order);
    semilogy(ax, xSorted, max(ySorted, eps), 'o-', 'LineWidth', 1.25, 'MarkerSize', 4, 'DisplayName', char(dirs(i)));
    made = true;
end
if ~made
    close(figs.PAPR);
    figs.PAPR = [];
    return;
end
grid(ax,'on');
xlabel(ax, 'PAPR_dB', 'Interpreter', 'none');
ylabel(ax, 'CCDF', 'Interpreter', 'none');
title(ax, sprintf('%s: PAPR CCDF', opt.FigurePrefix), 'Interpreter', 'none');
localApplyFiniteXLimits(ax, double(TP.PAPR_dB));
if numel(dirs) > 1
    legend(ax, 'Location', 'best');
end
end

function [series, names, sourceVars] = localFindNamedSeries(T, candidates, labels)
series = {};
names = {};
sourceVars = {};
if ~istable(T)
    return;
end
vnames = string(T.Properties.VariableNames);
for i = 1:numel(candidates)
    c = string(candidates{i});
    j = find(strcmpi(vnames, c), 1);
    if isempty(j)
        continue;
    end
    vec = T.(vnames(j));
    if ~isnumeric(vec)
        continue;
    end
    series{end+1} = double(vec(:)); %#ok<AGROW>
    names{end+1} = char(labels{i}); %#ok<AGROW>
    sourceVars{end+1} = char(vnames(j)); %#ok<AGROW>
end
end

function y = localResolveLogSweepSeries(T, metricVar, y)
y = double(y(:));
mask = isfinite(y) & y <= 0;
if ~any(mask)
    return;
end
[~, ciHighVar] = localResolveSweepCIColumns(T, metricVar);
if strlength(ciHighVar) > 0 && ismember(ciHighVar, string(T.Properties.VariableNames))
    hi = double(T.(ciHighVar));
    hi = hi(:);
    useCI = mask & isfinite(hi) & hi > 0;
    y(useCI) = hi(useCI);
    mask = isfinite(y) & y <= 0;
end
if any(mask)
    positive = y(isfinite(y) & y > 0);
    if isempty(positive)
        floorVal = eps;
    else
        floorVal = max(min(positive) / 10, eps);
    end
    y(mask) = floorVal;
end
end

function [ciLowVar, ciHighVar] = localResolveSweepCIColumns(T, metricVar)
ciLowVar = "";
ciHighVar = "";
if ~istable(T)
    return;
end
vars = string(T.Properties.VariableNames);
base = string(metricVar);
baseNoUnit = base;
if endsWith(base, "_dB")
    baseNoUnit = extractBefore(base, strlength(base) - 2);
end
patterns = [
    base + "_CI95_Low", base + "_CI95_High";
    base + "_CI_Low", base + "_CI_High";
    baseNoUnit + "_CI95_Low", baseNoUnit + "_CI95_High";
    baseNoUnit + "_CI_Low", baseNoUnit + "_CI_High";
    base + "_lo", base + "_hi";
    base + "_lower", base + "_upper"];
for i = 1:size(patterns, 1)
    if ismember(patterns(i, 1), vars) && ismember(patterns(i, 2), vars)
        ciLowVar = patterns(i, 1);
        ciHighVar = patterns(i, 2);
        return;
    end
end
end

function localApplyFiniteXLimits(ax, x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    return;
end
if min(x) < max(x)
    xlim(ax, [min(x), max(x)]);
else
    xlim(ax, [min(x) - 0.5, max(x) + 0.5]);
end
end

function localApplyFiniteSweepTicks(ax, x)
x = double(x(:));
x = unique(x(isfinite(x)), 'sorted');
if isempty(x) || numel(x) > 16
    return;
end
xticks(ax, x.');
end

function localPlotDiscreteSweepSeries(ax, x, y, useLog, displayName)
[x, order] = sort(double(x(:)));
y = double(y(:));
y = y(order);
if useLog
    y = max(y, eps);
end
if numel(x) > 1
    stairs(ax, x, y, '-', 'LineWidth', 1.1, 'HandleVisibility', 'off');
end
plot(ax, x, y, 'o', 'LineWidth', 1.1, 'MarkerSize', 5, 'DisplayName', displayName);
end

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
