function ta = estimateTimingAdvanceFromPRACH(det)
%ESTIMATETIMINGADVANCEFROMPRACH Convert calibrated PRACH timing evidence to TA.
rawOffset = double(sixgr.util.structGet(det, "TimingOffsetSamples", NaN));
if ~(isscalar(rawOffset) && isfinite(rawOffset))
    rawOffset = 0;
end
propOffset = double(sixgr.util.structGet(det, "PropagationTimingOffsetSamples", NaN));
if ~(isscalar(propOffset) && isfinite(propOffset))
    % The raw correlation peak includes format/occasion alignment. Do not
    % treat it as propagation TA unless a calibrated propagation-relative
    % detector field is available.
    propOffset = 0;
end
propOffset = max(0, round(propOffset));
ta = struct();
ta.RawTimingOffsetSamples = double(rawOffset);
ta.TimingOffsetSamples = double(propOffset);
ta.TimingAdvanceSamples = double(propOffset);
ta.TimingAdvanceCommand = double(max(0, min(3846, round(propOffset / 16))));
ta.Source = "msg1_prach_calibrated_propagation_timing";
end
