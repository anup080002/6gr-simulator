function score = scorePRACHDetection(det, txMeta, prachCfg, varargin)
%SCOREPRACHDETECTION Score receiver output after detection has completed.

p = inputParser;
p.FunctionName = "sixgr.phy.prach.scorePRACHDetection";
addRequired(p, "det", @isstruct);
addRequired(p, "txMeta", @isstruct);
addRequired(p, "prachCfg", @isstruct);
addParameter(p, "TrialType", "positive_high_snr", @(x) ischar(x) || isstring(x));
parse(p, det, txMeta, prachCfg, varargin{:});
trialType = string(p.Results.TrialType);

detected = logical(sixgr.util.structGet(det, "Detected", false));
idxDetected = double(sixgr.util.structGet(det, "DetectedPreambleIndex", NaN));
idxTx = double(sixgr.util.structGet(txMeta, "PreambleIndexTx", NaN));
timingTrue = double(sixgr.util.structGet(txMeta, "InjectedTimingOffsetSamples", 0));
timingEst = double(sixgr.util.structGet(det, "TimingOffsetSamples", NaN));
timingError = timingEst - timingTrue;
toleranceSamples = max(1.5, double(sixgr.util.structGet(prachCfg, "TimingTolerance_us", 0.25)) * ...
    double(sixgr.util.structGet(prachCfg, "SampleRate_Hz", 1)) / 1e6);
match = detected && isfinite(idxDetected) && isfinite(idxTx) && round(idxDetected) == round(idxTx);
timingOk = isfinite(timingError) && abs(timingError) <= toleranceSamples;

score = struct();
score.Detected = detected;
score.PreambleIndexDetected = idxDetected;
score.PreambleIndexMatch = logical(match);
score.EstimatedTimingOffsetSamples = timingEst;
score.TimingErrorSamples = timingError;
score.TimingWithinTolerance = logical(timingOk);
score.FalseAlarm = detected && ~logical(sixgr.util.structGet(txMeta, "PreamblePresent", true));
score.MissedDetection = ~detected && logical(sixgr.util.structGet(txMeta, "PreamblePresent", true));
score.StrictOk = trialType == "positive_high_snr" && match && timingOk && ~score.FalseAlarm && ~score.MissedDetection;
score.Status = string(ternary(score.StrictOk, "PASS", "FAIL"));
score.FailureReason = string("");
if ~score.StrictOk
    if score.FalseAlarm
        score.FailureReason = "false_alarm";
    elseif score.MissedDetection
        score.FailureReason = "missed_detection";
    elseif ~match
        score.FailureReason = "preamble_mismatch";
    elseif ~timingOk
        score.FailureReason = "timing_error_out_of_tolerance";
    else
        score.FailureReason = "not_strict_positive_trial";
    end
end
end

function y = ternary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end
