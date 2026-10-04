function metrics = PDCCHMetrics(perCandidateResults, perSlotResults, confidenceLevel)
%PDCCHMetrics Build per-scenario control-channel KPI tables.

metrics = struct();
metrics.PerCandidateResults = perCandidateResults;
metrics.PerSlotResults = perSlotResults;

if ~(istable(perSlotResults) && ~isempty(perSlotResults))
    metrics.Summary = table();
    metrics.ComplexitySummary = table();
    return;
end

present = localNumeric(perSlotResults,'SignalPresent');
h1 = isfinite(present) & present == 1;
h0 = isfinite(present) & present == 0;
% Unlabelled legacy rows cannot establish either statistical denominator.
metrics.Summary = table( ...
    mean(localNumeric(perSlotResults(h1,:), "true_detection")), ...
    mean(localNumeric(perSlotResults(h1,:), "miss_detection")), ...
    mean(localNumeric(perSlotResults(h0,:), "false_alarm")), ...
    mean(localNumeric(perSlotResults(h1,:), "false_positive_wrong_candidate")), ...
    mean(localNumeric(perSlotResults, "ambiguous_multiple_pass")), ...
    mean(localNumeric(perSlotResults, "monitored_candidates_count")), ...
    mean(localNumeric(perSlotResults, "total_blind_decodes")), ...
    mean(localNumeric(perSlotResults, "decode_latency_proxy_ops")), ...
    'VariableNames', { ...
    'DetectionProbability','MissProbability','FalseAlarmProbability', ...
    'WrongCandidateProbability','AmbiguousProbability', ...
    'AverageCandidatesMonitored','AverageBlindDecodes','AverageOps'});
metrics.Summary.SignalPresentTrialCount = sum(h1);
metrics.Summary.NoiseOnlyTrialCount = sum(h0);
metrics.Summary.FalseAlarmCount = sum(localNumeric(perSlotResults(h0,:),'false_alarm'));
metrics.Summary.MissedDetectionCount = sum(localNumeric(perSlotResults(h1,:),'miss_detection'));
metrics.Summary.StatisticalQualification = "not_evaluated_population_only";
metrics.Summary.ConfidenceLevel = confidenceLevel;
[metrics.Summary.FalseAlarmCILower,metrics.Summary.FalseAlarmCIUpper] = ...
    localInterval(metrics.Summary.FalseAlarmCount,sum(h0),confidenceLevel);
[metrics.Summary.MissCILower,metrics.Summary.MissCIUpper] = ...
    localInterval(metrics.Summary.MissedDetectionCount,sum(h1),confidenceLevel);

if istable(perCandidateResults) && ~isempty(perCandidateResults)
    metrics.ComplexitySummary = table( ...
        mean(localNumeric(perCandidateResults, "AL")), ...
        mean(localNumeric(perCandidateResults, "decoding_metric")), ...
        mean(localNumeric(perCandidateResults, "nmse_channel_est")), ...
        mean(localNumeric(perCandidateResults, "post_eq_evm")), ...
        'VariableNames', {'AverageAL','AverageDecodingMetric','AverageNMSE','AveragePostEqEVM'});
    metrics.DCIBLER = 1 - mean(localNumeric(perSlotResults(h1,:), "true_detection"));
else
    metrics.ComplexitySummary = table();
    metrics.DCIBLER = NaN;
end
end

function [low,high] = localInterval(k,n,confidenceLevel)
low = NaN; high = NaN;
if n>0
    [~,~,low,high] = sixgr.stats.wilsonBinomialCI(k,n,confidenceLevel);
end
end

function v = localNumeric(T, fieldName)
if istable(T) && ismember(fieldName, T.Properties.VariableNames)
    v = double(T.(fieldName));
else
    v = NaN(height(T),1);
end
end
