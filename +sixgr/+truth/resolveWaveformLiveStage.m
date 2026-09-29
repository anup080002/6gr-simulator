function stage = resolveWaveformLiveStage(dlTrialRows, ulTrialRows, controlAttemptCounts)
%RESOLVEWAVEFORMLIVESTAGE Name a live stage from completed evidence only.
%
% A raw-data streaming label is permitted only after at least one measured
% PDSCH or PUSCH trial row exists.  Control-attempt evidence may describe
% control gating, but it must not be promoted to a shared-channel trial.

dlTrialRows = localNonnegativeCount(dlTrialRows, "dlTrialRows");
ulTrialRows = localNonnegativeCount(ulTrialRows, "ulTrialRows");
controlAttemptCounts = double(controlAttemptCounts(:));
if any(~isfinite(controlAttemptCounts) | controlAttemptCounts < 0 | ...
        controlAttemptCounts ~= round(controlAttemptCounts))
    error("sixgr:truth:InvalidLiveControlAttemptCounts", ...
        "controlAttemptCounts must contain finite nonnegative integer counts.");
end

if dlTrialRows > 0 && ulTrialRows > 0
    stage = "dl_ul_raw_trials_streaming";
elseif dlTrialRows > 0
    stage = "dl_raw_trials_streaming";
elseif ulTrialRows > 0
    stage = "ul_raw_trials_streaming";
elseif any(controlAttemptCounts > 0)
    stage = "control_gating_streaming";
else
    stage = "control_access_pending";
end
end

function count = localNonnegativeCount(value, fieldName)
count = double(value);
if ~(isscalar(count) && isfinite(count) && count >= 0 && count == round(count))
    error("sixgr:truth:InvalidLiveTrialRowCount", ...
        "%s must be a finite nonnegative integer count.", fieldName);
end
end
