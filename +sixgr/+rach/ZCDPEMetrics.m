function metrics = ZCDPEMetrics(trialTable, roTable, cfg, varargin)
%ZCDPEMETRICS Aggregate baseline PRACH plus ZC-DPE-specific KPIs.

p = inputParser;
p.FunctionName = "sixgr.rach.ZCDPEMetrics";
addRequired(p, "trialTable", @(x) istable(x));
addRequired(p, "roTable", @(x) istable(x));
addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "WriteOutputs", true, @(x) islogical(x) || isnumeric(x));
parse(p, trialTable, roTable, cfg, varargin{:});

metrics = sixgr.rach.PRACHMetrics(trialTable, roTable, cfg, "WriteOutputs", false);
metrics.DPIConfusionMatrix = localDPIConfusion(trialTable);
metrics.DPIErrorBySnr = localDPIErrorBySnr(trialTable);
metrics.DopplerRMSEBySnr = localDopplerRMSEBySnr(trialTable);
metrics.PoolAnalysis = localPoolAnalysis(trialTable, cfg);
metrics.BackwardCompatVerified = localBackwardCompatVerified(trialTable);

if ~logical(p.Results.WriteOutputs)
    return;
end

outDir = char(sixgr.util.structGet(cfg, "OutputDir", fullfile(pwd, "results")));
plotDir = fullfile(outDir, "plots");
sixgr.util.ensureDir(fullfile(plotDir, "stub.txt"));
localSaveLine(metrics.DPIErrorBySnr, "snr_db", "dpi_error_probability", ...
    fullfile(plotDir, "zcdpe_dpi_error_probability_vs_snr.png"), "ZC-DPE DPI Error Probability vs SNR");
localSaveLine(metrics.DopplerRMSEBySnr, "snr_db", "doppler_rmse_hz", ...
    fullfile(plotDir, "zcdpe_doppler_rmse_vs_snr.png"), "ZC-DPE Doppler RMSE vs SNR");
localSaveConfusion(metrics.DPIConfusionMatrix, fullfile(plotDir, "zcdpe_confusion_matrix_heatmap.png"));
localSavePool(metrics.PoolAnalysis, fullfile(plotDir, "zcdpe_pool_analysis_bar.png"));
end

function T = localDPIConfusion(trialTable)
vars = string(trialTable.Properties.VariableNames);
if isempty(trialTable) || ~all(ismember(["dpi_d_true","dpi_d_detected"], vars))
    T = table();
    return;
end
mask = isfinite(double(trialTable.dpi_d_true)) & isfinite(double(trialTable.dpi_d_detected));
if ~any(mask)
    T = table();
    return;
end
dTrue = round(double(trialTable.dpi_d_true(mask)));
dDet = round(double(trialTable.dpi_d_detected(mask)));
[pairs, ~, ic] = unique([dTrue dDet], "rows");
counts = accumarray(ic, 1);
T = table(pairs(:,1), pairs(:,2), counts, 'VariableNames', {'dpi_d_true','dpi_d_detected','count'});
end

function T = localDPIErrorBySnr(trialTable)
vars = string(trialTable.Properties.VariableNames);
if isempty(trialTable) || ~all(ismember(["snr_db","dpi_d_true","dpi_d_detected"], vars))
    T = table();
    return;
end
snr = double(trialTable.snr_db);
err = double(round(double(trialTable.dpi_d_true)) ~= round(double(trialTable.dpi_d_detected)));
mask = isfinite(snr) & isfinite(double(trialTable.dpi_d_true)) & isfinite(double(trialTable.dpi_d_detected));
if ~any(mask)
    T = table();
    return;
end
snrs = unique(snr(mask));
prob = nan(numel(snrs), 1);
for i = 1:numel(snrs)
    rows = mask & snr == snrs(i);
    prob(i) = mean(err(rows), "omitnan");
end
T = table(snrs(:), prob, 'VariableNames', {'snr_db','dpi_error_probability'});
end

function T = localDopplerRMSEBySnr(trialTable)
vars = string(trialTable.Properties.VariableNames);
if isempty(trialTable) || ~all(ismember(["snr_db","doppler_error_hz"], vars))
    T = table();
    return;
end
snr = double(trialTable.snr_db);
err = double(trialTable.doppler_error_hz);
mask = isfinite(snr) & isfinite(err);
if ~any(mask)
    T = table();
    return;
end
snrs = unique(snr(mask));
rmse = nan(numel(snrs), 1);
for i = 1:numel(snrs)
    rows = mask & snr == snrs(i);
    rmse(i) = sqrt(mean(err(rows).^2, "omitnan"));
end
T = table(snrs(:), rmse, 'VariableNames', {'snr_db','doppler_rmse_hz'});
end

function T = localPoolAnalysis(trialTable, cfg)
if isempty(trialTable) || ~ismember("scenario_id", string(trialTable.Properties.VariableNames))
    D = double(sixgr.util.structGet(cfg, "ZCDPE.DPI_D", NaN));
    T = table(string("configured"), D, D, 'VariableNames', {'scenario_id','dpi_D','pool_gain_factor'});
    return;
end
scenario = string(trialTable.scenario_id);
if ismember("dpi_D", string(trialTable.Properties.VariableNames))
    Dcol = double(trialTable.dpi_D);
else
    Dcol = nan(height(trialTable), 1);
end
if ismember("pool_gain_factor", string(trialTable.Properties.VariableNames))
    gainCol = double(trialTable.pool_gain_factor);
else
    gainCol = Dcol;
end
scenarios = unique(scenario);
D = nan(numel(scenarios), 1);
gain = nan(numel(scenarios), 1);
for i = 1:numel(scenarios)
    rows = scenario == scenarios(i);
    D(i) = localFirstFinite(Dcol(rows));
    gain(i) = localFirstFinite(gainCol(rows));
end
T = table(scenarios(:), D, gain, 'VariableNames', {'scenario_id','dpi_D','pool_gain_factor'});
end

function tf = localBackwardCompatVerified(trialTable)
tf = false;
vars = string(trialTable.Properties.VariableNames);
if isempty(trialTable) || ~all(ismember(["is_backward_compat","zcdpe_enabled","correct_detection"], vars))
    return;
end
rows = logical(trialTable.is_backward_compat) & logical(trialTable.zcdpe_enabled);
if ~any(rows)
    tf = true;
else
    tf = all(logical(trialTable.correct_detection(rows)));
end
end

function val = localFirstFinite(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    val = NaN;
else
    val = x(1);
end
end

function localSaveLine(T, xName, yName, filePath, plotTitle)
if isempty(T) || ~all(ismember([xName yName], string(T.Properties.VariableNames)))
    return;
end
fig = figure("Visible", "off", "Color", "w");
cleanup = onCleanup(@() close(fig));
plot(double(T.(xName)), double(T.(yName)), "-o", "LineWidth", 1.5);
grid on;
xlabel(strrep(xName, "_", " "));
ylabel(strrep(yName, "_", " "));
title(plotTitle, "Interpreter", "none");
exportgraphics(fig, filePath, "Resolution", 150);
end

function localSaveConfusion(T, filePath)
if isempty(T) || ~all(ismember(["dpi_d_true","dpi_d_detected","count"], string(T.Properties.VariableNames)))
    return;
end
vals = unique([double(T.dpi_d_true); double(T.dpi_d_detected)]);
vals = vals(isfinite(vals));
if isempty(vals)
    return;
end
M = zeros(numel(vals));
for i = 1:height(T)
    r = find(vals == double(T.dpi_d_true(i)), 1);
    c = find(vals == double(T.dpi_d_detected(i)), 1);
    M(r, c) = double(T.count(i));
end
fig = figure("Visible", "off", "Color", "w");
cleanup = onCleanup(@() close(fig));
imagesc(vals, vals, M);
axis xy;
colorbar;
xlabel("detected d");
ylabel("true d");
title("ZC-DPE DPI Confusion Matrix");
exportgraphics(fig, filePath, "Resolution", 150);
end

function localSavePool(T, filePath)
if isempty(T) || ~ismember("pool_gain_factor", string(T.Properties.VariableNames))
    return;
end
fig = figure("Visible", "off", "Color", "w");
cleanup = onCleanup(@() close(fig));
bar(double(T.pool_gain_factor));
xticks(1:height(T));
xticklabels(cellstr(string(T.scenario_id)));
xtickangle(35);
ylabel("pool gain factor");
title("ZC-DPE Pool Gain");
exportgraphics(fig, filePath, "Resolution", 150);
end
