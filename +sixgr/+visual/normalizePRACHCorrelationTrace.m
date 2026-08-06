function T = normalizePRACHCorrelationTrace(sourceT)
%NORMALIZEPRACHCORRELATIONTRACE Canonicalize measured PRACH lag traces.
%
% This is a schema adapter only.  It never invents correlation samples or
% promotes a trace to truth.  A truth status is accepted only when it is
% explicitly present in the source artifact.

names = ["trial_id","preamble_index","root_sequence_index","restricted_set_type","n_cs", ...
    "zero_correlation_zone_config","lag_samples","lag_us","correlation_abs","threshold", ...
    "noise_floor","peak_lag_samples","timing_advance_samples","detection_result", ...
    "false_alarm","missed_detection","snr_db","cfo_hz","seed","truth_status"];
if ~(istable(sourceT) && ~isempty(sourceT))
    T = localEmptyTable(names);
    return;
end
n = height(sourceT);
T = table( ...
    localNumeric(sourceT, ["trial_id","TrialID","TrialId","AttemptID"]), ...
    localNumeric(sourceT, ["preamble_index","PreambleIndex","PreambleID"]), ...
    localNumeric(sourceT, ["root_sequence_index","RootSequenceIndex","RootSequence"]), ...
    localText(sourceT, ["restricted_set_type","RestrictedSetType"], "not_available"), ...
    localNumeric(sourceT, ["n_cs","NCS","N_CS"]), ...
    localNumeric(sourceT, ["zero_correlation_zone_config","ZeroCorrelationZoneConfig","ZeroCorrelationZone"]), ...
    localNumeric(sourceT, ["lag_samples","LagSamples","Lag","TimingLagSamples"]), ...
    localNumeric(sourceT, ["lag_us","Lag_us","LagMicroseconds"]), ...
    localNumeric(sourceT, ["correlation_abs","CorrelationAbs","CorrelationMagnitude","Metric"]), ...
    localNumeric(sourceT, ["threshold","Threshold","DetectionThreshold"]), ...
    localNumeric(sourceT, ["noise_floor","NoiseFloor","NoiseFloorEstimate"]), ...
    localNumeric(sourceT, ["peak_lag_samples","PeakLagSamples","DetectedPeakLag"]), ...
    localNumeric(sourceT, ["timing_advance_samples","TimingAdvanceSamples","EstimatedTimingAdvanceSamples"]), ...
    localText(sourceT, ["detection_result","DetectionResult","Status"], "not_available"), ...
    localTriState(sourceT, ["false_alarm","FalseAlarm","IsFalseAlarm"]), ...
    localTriState(sourceT, ["missed_detection","MissedDetection","IsMissedDetection"]), ...
    localNumeric(sourceT, ["snr_db","SNR_dB","SNRdB"]), ...
    localNumeric(sourceT, ["cfo_hz","CFO_Hz","CFOHz"]), ...
    localNumeric(sourceT, ["seed","Seed","RandomSeed"]), ...
    localTruthStatus(sourceT, n), ...
    'VariableNames', cellstr(names));
end

function T = localEmptyTable(names)
types = repmat("double", size(names));
types(ismember(names, ["restricted_set_type","detection_result","truth_status"])) = "string";
T = table('Size', [0 numel(names)], 'VariableTypes', cellstr(types), ...
    'VariableNames', cellstr(names));
end

function values = localNumeric(T, aliases)
values = nan(height(T), 1);
for alias = string(aliases)
    match = strcmpi(string(T.Properties.VariableNames), alias);
    if ~any(match)
        continue;
    end
    raw = T{:, find(match, 1, "first")};
    try
        candidate = double(raw);
    catch
        candidate = str2double(string(raw));
    end
    candidate = reshape(candidate, [], 1);
    if numel(candidate) == height(T)
        values = candidate;
        return;
    end
end
end

function values = localText(T, aliases, defaultValue)
values = repmat(string(defaultValue), height(T), 1);
for alias = string(aliases)
    match = strcmpi(string(T.Properties.VariableNames), alias);
    if ~any(match)
        continue;
    end
    candidate = string(T{:, find(match, 1, "first")});
    candidate = reshape(candidate, [], 1);
    if numel(candidate) == height(T)
        valid = ~ismissing(candidate) & strlength(strtrim(candidate)) > 0;
        values(valid) = candidate(valid);
        return;
    end
end
end

function values = localTriState(T, aliases)
values = nan(height(T), 1);
for alias = string(aliases)
    match = strcmpi(string(T.Properties.VariableNames), alias);
    if ~any(match)
        continue;
    end
    raw = T{:, find(match, 1, "first")};
    if islogical(raw)
        values = double(raw(:));
    elseif isnumeric(raw)
        candidate = double(raw(:));
        valid = isfinite(candidate);
        values(valid) = double(candidate(valid) ~= 0);
    else
        token = lower(strtrim(string(raw(:))));
        trueMask = ismember(token, ["true","1","yes","pass"]);
        falseMask = ismember(token, ["false","0","no","fail"]);
        values(trueMask) = 1;
        values(falseMask) = 0;
    end
    return;
end
end

function values = localTruthStatus(T, n)
values = repmat("not_available_missing_truth_status", n, 1);
for alias = ["truth_status","TruthStatus","EvidenceTruthStatus","LLSValidity"]
    match = strcmpi(string(T.Properties.VariableNames), alias);
    if ~any(match)
        continue;
    end
    candidate = lower(strtrim(string(T{:, find(match, 1, "first")})));
    candidate = reshape(candidate, [], 1);
    if numel(candidate) ~= n
        continue;
    end
    valid = ~ismissing(candidate) & strlength(candidate) > 0;
    values(valid) = candidate(valid);
    return;
end
end
