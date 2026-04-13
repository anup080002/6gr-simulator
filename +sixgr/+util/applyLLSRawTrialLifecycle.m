function T = applyLLSRawTrialLifecycle(T)
%APPLYLLSRAWTRIALLIFECYCLE Classify raw LLS trial rows using primary-truth semantics.
%
% Row finalization is driven by primary runtime truth required to interpret
% a DL/UL trial row as decode/grant evidence. Optional secondary fields such
% as preview SINR or auxiliary estimator diagnostics remain available through
% per-field status columns and the SecondaryFieldGap* summary columns.

if ~istable(T)
    error("sixgr:util:applyLLSRawTrialLifecycle:InvalidInput", ...
        "Input must be a table.");
end

n = height(T);

mcsIndex = double(localOptionalColumn(T, "MCSIndex", NaN));
legacyMcs = double(localOptionalColumn(T, "MCS", NaN));
mcsFallbackMask = ~isfinite(mcsIndex) & isfinite(legacyMcs);
if any(mcsFallbackMask) || ~ismember("MCSIndex", string(T.Properties.VariableNames))
    mcsIndex(mcsFallbackMask) = legacyMcs(mcsFallbackMask);
    T.MCSIndex = mcsIndex;
end

estimatedCFOPre = double(localOptionalColumn(T, "EstimatedCFO_PreCorrection_Hz", NaN));
estimatedCFO = double(localOptionalColumn(T, "EstimatedCFO_Hz", NaN));
cfoEstimateMask = isfinite(estimatedCFOPre) | isfinite(estimatedCFO);
T.CFOEstimateAvailability = repmat("missing", n, 1);
T.CFOEstimateAvailability(cfoEstimateMask) = "available";
T.CFOErrorDefinition = repmat("not_available_without_cfo_estimate", n, 1);
T.CFOErrorDefinition(cfoEstimateMask) = "residual_post_correction_hz_relative_to_estimated_pre_correction";
invalidCfoErrorMask = ~cfoEstimateMask & isfinite(double(localOptionalColumn(T, "CFOError_Hz", NaN)));
if any(invalidCfoErrorMask)
    T.CFOError_Hz(invalidCfoErrorMask) = NaN;
end
if ismember("ResidualCFO_PostCorrection_Hz", string(T.Properties.VariableNames))
    residualCFO = double(localOptionalColumn(T, "ResidualCFO_PostCorrection_Hz", NaN));
    staleResidualMask = ~cfoEstimateMask & isfinite(residualCFO);
    if any(staleResidualMask)
        T.ResidualCFO_PostCorrection_Hz(staleResidualMask) = NaN;
    end
end
T.CFOValueStatus = repmat("NOT_AVAILABLE", n, 1);
validCfoMask = cfoEstimateMask & isfinite(double(localOptionalColumn(T, "CFOError_Hz", NaN)));
partialCfoMask = cfoEstimateMask & ~validCfoMask;
T.CFOValueStatus(validCfoMask) = "OK";
T.CFOValueStatus(partialCfoMask) = "PARTIAL";

timingEstimateMask = logical(localOptionalColumn(T, "TimingEstimateUsed", false)) & ...
    isfinite(double(localOptionalColumn(T, "EstimatedTimingOffset_PreCorrection_samples", NaN)));
idealTimingMask = logical(localOptionalColumn(T, "UseIdealTimingSync", false));
T.TimingEstimateAvailability = repmat("missing", n, 1);
T.TimingEstimateAvailability(timingEstimateMask) = "available";
T.TimingEstimateAvailability(idealTimingMask & ~timingEstimateMask) = "ideal_sync_bypass";
T.TimingErrorDefinition = repmat("not_available_without_timing_estimate", n, 1);
T.TimingErrorDefinition(timingEstimateMask) = "residual_post_correction_samples_relative_to_estimated_pre_correction";
T.TimingValueStatus = repmat("NOT_AVAILABLE", n, 1);
validTimingMask = timingEstimateMask & isfinite(double(localOptionalColumn(T, "TimingError_samples", NaN)));
partialTimingMask = timingEstimateMask & ~validTimingMask;
T.TimingValueStatus(validTimingMask) = "OK";
T.TimingValueStatus(partialTimingMask) = "PARTIAL";
T.TimingValueStatus(idealTimingMask & ~timingEstimateMask) = "NOT_APPLICABLE";

largeScale = double(localOptionalColumn(T, "LargeScaleSINR_dB", NaN));
largeScaleSource = strtrim(string(localOptionalColumn(T, "LargeScaleSINRSource", "")));
largeScaleValueMask = isfinite(largeScale);
largeScaleSourceMask = strlength(largeScaleSource) > 0;
largeScaleGapMask = ~largeScaleValueMask & largeScaleSourceMask;
T.LargeScaleSINRValueStatus = repmat("MISSING", n, 1);
T.LargeScaleSINRValueStatus(largeScaleValueMask) = "OK";
T.LargeScaleSINRValueStatus(largeScaleGapMask) = "NOT_AVAILABLE";
T.LargeScaleSINRFinalizedFlag = largeScaleValueMask;
T.LargeScaleSINRNAReason = repmat("", n, 1);
T.LargeScaleSINRNAReason(largeScaleGapMask) = "preview_source_present_value_not_finalized";
T.LargeScaleSINRNAReason(~largeScaleValueMask & ~largeScaleSourceMask) = "no_large_scale_sinr_source";

allocatedPrbs = double(localOptionalColumn(T, "AllocatedPRBCount", NaN));
prbStart = double(localOptionalColumn(T, "PRBStart", NaN));
prbStartMissingMask = isfinite(allocatedPrbs) & allocatedPrbs > 0 & ~isfinite(prbStart);

[primaryGapMask, primaryReason] = localResolvePrimaryTruthGaps(T);

T.PrimaryTruthValueStatus = repmat("OK", n, 1);
T.PrimaryTruthValueStatus(primaryGapMask) = "NOT_AVAILABLE";

secondaryGapFlag = false(n, 1);
secondaryGapCount = zeros(n, 1);
secondaryGapReason = repmat("", n, 1);
[secondaryGapFlag, secondaryGapCount, secondaryGapReason] = localAppendReason( ...
    secondaryGapFlag, secondaryGapCount, secondaryGapReason, partialCfoMask, "cfo_error_missing_with_estimate");
[secondaryGapFlag, secondaryGapCount, secondaryGapReason] = localAppendReason( ...
    secondaryGapFlag, secondaryGapCount, secondaryGapReason, partialTimingMask, "timing_error_missing_with_estimate");
[secondaryGapFlag, secondaryGapCount, secondaryGapReason] = localAppendReason( ...
    secondaryGapFlag, secondaryGapCount, secondaryGapReason, prbStartMissingMask, "prb_start_missing_for_nonzero_allocation");
[secondaryGapFlag, secondaryGapCount, secondaryGapReason] = localAppendReason( ...
    secondaryGapFlag, secondaryGapCount, secondaryGapReason, largeScaleGapMask, "large_scale_sinr_not_finalized");
T.SecondaryFieldGapFlag = secondaryGapFlag;
T.SecondaryFieldGapCount = secondaryGapCount;
T.SecondaryFieldGapReason = secondaryGapReason;

crashMask = logical(localOptionalColumn(T, "Crash", false));
T.PartialRowFlag = ~crashMask & primaryGapMask;
T.FallbackFlag = false(n, 1);
T.PlaceholderFlag = false(n, 1);
T.NAReason = repmat("", n, 1);
T.NAReason(T.PartialRowFlag) = primaryReason(T.PartialRowFlag);
T.NAReason(crashMask) = "trial_crash";
T.FinalizedFlag = ~crashMask & ~primaryGapMask;
T.RowLifecycleState = repmat("finalized", n, 1);
T.RowLifecycleState(crashMask) = "crashed";
T.RowLifecycleState(T.PartialRowFlag) = "partial";
T.PrimaryTruthValueStatus(crashMask) = "CRASHED";
end

function [mask, reason] = localResolvePrimaryTruthGaps(T)
n = height(T);
mask = false(n, 1);
reason = repmat("", n, 1);

[mask, ~, reason] = localAppendReason(mask, zeros(n, 1), reason, ...
    strlength(strtrim(string(localOptionalColumn(T, "Direction", "")))) == 0, ...
    "direction_missing");
[mask, ~, reason] = localAppendReason(mask, zeros(n, 1), reason, ...
    ~isfinite(double(localOptionalColumn(T, "Frame", NaN))), ...
    "frame_missing");
[mask, ~, reason] = localAppendReason(mask, zeros(n, 1), reason, ...
    ~isfinite(double(localOptionalColumn(T, "Slot", NaN))), ...
    "slot_missing");
[mask, ~, reason] = localAppendReason(mask, zeros(n, 1), reason, ...
    ~isfinite(double(localOptionalColumn(T, "CRCPass", NaN))), ...
    "crc_pass_missing");
[mask, ~, reason] = localAppendReason(mask, zeros(n, 1), reason, ...
    ~isfinite(double(localOptionalColumn(T, "BitsCompared", NaN))), ...
    "bits_compared_missing");
[mask, ~, reason] = localAppendReason(mask, zeros(n, 1), reason, ...
    ~isfinite(double(localOptionalColumn(T, "Goodput_Mbps", NaN))), ...
    "goodput_missing");
[mask, ~, reason] = localAppendReason(mask, zeros(n, 1), reason, ...
    ~isfinite(double(localOptionalColumn(T, "AllocatedPRBCount", NaN))), ...
    "allocated_prb_count_missing");
[mask, ~, reason] = localAppendReason(mask, zeros(n, 1), reason, ...
    ~isfinite(double(localOptionalColumn(T, "MCSIndex", NaN))), ...
    "mcs_index_missing");
[mask, ~, reason] = localAppendReason(mask, zeros(n, 1), reason, ...
    strlength(strtrim(string(localOptionalColumn(T, "Modulation", "")))) == 0, ...
    "modulation_missing");
[mask, ~, reason] = localAppendReason(mask, zeros(n, 1), reason, ...
    ~isfinite(double(localOptionalColumn(T, "TargetCodeRate", NaN))), ...
    "target_code_rate_missing");
end

function [flag, count, reason] = localAppendReason(flag, count, reason, mask, token)
mask = logical(mask(:));
if isempty(flag)
    flag = false(size(mask));
end
if isempty(count)
    count = zeros(size(mask));
end
if isempty(reason)
    reason = repmat("", numel(mask), 1);
end
if ~any(mask)
    return;
end
flag = flag | mask;
count(mask) = count(mask) + 1;
token = string(token);
appendMask = mask & strlength(reason) > 0;
emptyMask = mask & strlength(reason) == 0;
reason(emptyMask) = token;
reason(appendMask) = reason(appendMask) + ";" + token;
end

function values = localOptionalColumn(T, name, defaultValue)
n = height(T);
if ismember(name, string(T.Properties.VariableNames))
    values = T.(char(name));
    return;
end
if isstring(defaultValue) || ischar(defaultValue)
    values = repmat(string(defaultValue), n, 1);
elseif islogical(defaultValue)
    values = repmat(logical(defaultValue), n, 1);
else
    values = repmat(defaultValue, n, 1);
end
end
