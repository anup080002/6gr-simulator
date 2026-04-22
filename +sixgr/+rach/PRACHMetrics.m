function metrics = PRACHMetrics(trialTable, roTable, cfg, varargin)
%PRACHMETRICS Aggregate PRACH LLS KPI tables and render study plots.

p = inputParser;
p.FunctionName = "sixgr.rach.PRACHMetrics";
addRequired(p, "trialTable", @(x) istable(x));
addRequired(p, "roTable", @(x) istable(x));
addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "WriteOutputs", true, @(x) islogical(x) || isnumeric(x));
parse(p, trialTable, roTable, cfg, varargin{:});

metrics = struct();
metrics.TrialTable = trialTable;
metrics.ROTable = roTable;

if isempty(roTable)
    metrics.SummaryBySNR = table();
    metrics.SummaryByScenario = table();
    metrics.Confusion = table();
    metrics.TimingErrorSamples = table();
    metrics.FrequencyErrorSamples = table();
    return;
end

metrics.SummaryBySNR = localSummarize(roTable, ["scenario_id","snr_db","threshold"]);
metrics.SummaryByScenario = localSummarize(roTable, "scenario_id");
metrics.Confusion = groupcounts(roTable(:, ["scenario_id","snr_db","detection_type"]), ...
    ["scenario_id","snr_db","detection_type"]);
metrics.Confusion = renamevars(metrics.Confusion, "GroupCount", "count");
metrics.TimingErrorSamples = roTable(:, intersect(["scenario_id","trial_id","ro_id","snr_db", ...
    "timing_offset_true_us","timing_offset_est_us","timing_error_us"], string(roTable.Properties.VariableNames)));
metrics.FrequencyErrorSamples = roTable(:, intersect(["scenario_id","trial_id","ro_id","snr_db", ...
    "cfo_true_hz","cfo_est_hz","frequency_error_hz"], string(roTable.Properties.VariableNames)));

if ~logical(p.Results.WriteOutputs)
    return;
end

outDir = char(sixgr.util.structGet(cfg, "OutputDir", fullfile(pwd, "results")));
plotDir = fullfile(outDir, "plots");
sixgr.util.ensureDir(fullfile(plotDir, "stub.txt"));

localSaveMetricPlot(metrics.SummaryBySNR, "snr_db", "DetectionProbability", ...
    fullfile(plotDir, "detection_probability_vs_snr.png"), "Detection Probability vs SNR");
localSaveMetricPlot(metrics.SummaryBySNR, "snr_db", "MissDetectionProbability", ...
    fullfile(plotDir, "miss_detection_vs_snr.png"), "Miss Detection vs SNR");
localSaveMetricPlot(metrics.SummaryBySNR, "snr_db", "FalseAlarmProbability", ...
    fullfile(plotDir, "false_alarm_vs_snr.png"), "False Alarm vs SNR");
localSaveMetricPlot(metrics.SummaryBySNR, "snr_db", "WrongPreambleProbability", ...
    fullfile(plotDir, "wrong_preamble_vs_snr.png"), "Wrong Preamble vs SNR");
localSaveMetricPlot(metrics.SummaryBySNR, "snr_db", "TimingRMSEUs", ...
    fullfile(plotDir, "timing_rmse_vs_snr.png"), "Timing RMSE vs SNR");
if any(isfinite(double(metrics.SummaryBySNR.OptionalFrequencyRMSEHz)))
    localSaveMetricPlot(metrics.SummaryBySNR, "snr_db", "OptionalFrequencyRMSEHz", ...
        fullfile(plotDir, "optional_frequency_error_vs_snr.png"), "Frequency Error vs SNR");
end
localSaveHeatmap(metrics.SummaryBySNR, fullfile(plotDir, "detection_heatmap_threshold_vs_snr.png"));
end

function summary = localSummarize(roTable, groupVars)
summary = groupsummary(roTable, groupVars, "mean", ...
    ["detected_flag","correct_detection_flag","wrong_preamble_flag","false_alarm_flag", ...
    "missed_detection_flag","type1_false_detection_flag","type2_false_detection_flag", ...
    "mixed_false_detection_flag","timing_error_sq_us2","frequency_error_abs_hz"]);
summary = renamevars(summary, ...
    ["mean_detected_flag","mean_correct_detection_flag","mean_wrong_preamble_flag","mean_false_alarm_flag", ...
    "mean_missed_detection_flag","mean_type1_false_detection_flag","mean_type2_false_detection_flag", ...
    "mean_mixed_false_detection_flag","mean_timing_error_sq_us2","mean_frequency_error_abs_hz"], ...
    ["DetectionProbability","CorrectDetectionProbability","WrongPreambleProbability","FalseAlarmProbability", ...
    "MissDetectionProbability","OptionalType1FalseDetectionProbability","OptionalType2FalseDetectionProbability", ...
    "OptionalMixedFalseDetectionProbability","timing_rmse_sq","OptionalFrequencyMeanAbsErrorHz"]);
summary.TimingRMSEUs = sqrt(max(double(summary.timing_rmse_sq), 0));
summary.OptionalFrequencyRMSEHz = double(summary.OptionalFrequencyMeanAbsErrorHz);
summary = removevars(summary, "timing_rmse_sq");
end

function localSaveMetricPlot(T, xName, yName, filePath, plotTitle)
if ~all(ismember([xName yName], string(T.Properties.VariableNames)))
    return;
end
fig = figure("Visible", "off", "Color", "w");
cleanup = onCleanup(@() close(fig));
plot(double(T.(xName)), double(T.(yName)), "-o", "LineWidth", 1.5, "MarkerSize", 6);
grid on;
xlabel(strrep(xName, "_", " "));
ylabel(strrep(yName, "_", " "));
title(plotTitle, "Interpreter", "none");
exportgraphics(fig, filePath, "Resolution", 150);
end

function localSaveHeatmap(T, filePath)
if ~all(ismember(["snr_db","threshold","DetectionProbability"], string(T.Properties.VariableNames)))
    return;
end
snrs = unique(double(T.snr_db));
thresholds = unique(double(T.threshold));
Z = nan(numel(thresholds), numel(snrs));
for i = 1:height(T)
    x = find(snrs == double(T.snr_db(i)), 1, "first");
    y = find(thresholds == double(T.threshold(i)), 1, "first");
    if ~isempty(x) && ~isempty(y)
        Z(y, x) = double(T.DetectionProbability(i));
    end
end
fig = figure("Visible", "off", "Color", "w");
cleanup = onCleanup(@() close(fig));
imagesc(snrs, thresholds, Z);
axis xy;
colorbar;
xlabel("SNR (dB)");
ylabel("Threshold");
title("Detection Probability Heatmap");
exportgraphics(fig, filePath, "Resolution", 150);
end
