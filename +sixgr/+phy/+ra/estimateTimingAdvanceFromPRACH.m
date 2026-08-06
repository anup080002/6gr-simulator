function ta = estimateTimingAdvanceFromPRACH(det)
%ESTIMATETIMINGADVANCEFROMPRACH Convert calibrated PRACH timing evidence to TA.
rawOffset = double(sixgr.util.structGet(det, "TimingOffsetSamples", NaN));
if ~(isscalar(rawOffset) && isfinite(rawOffset))
    rawOffset = 0;
end
propOffset = double(sixgr.util.structGet(det, "PropagationTimingOffsetSamples", NaN));
if ~(isscalar(propOffset) && isfinite(propOffset))
    ta = struct();
    ta.RawTimingOffsetSamples = double(rawOffset);
    ta.TimingOffsetSamples = NaN;
    ta.TimingAdvanceSamples = NaN;
    ta.TimingAdvanceCommand = NaN;
    ta.Valid = false;
    ta.Source = "msg1_prach_propagation_timing_unavailable";
    return;
end
propOffset = max(0, round(propOffset));
ta = struct();
ta.RawTimingOffsetSamples = double(rawOffset);
ta.TimingOffsetSamples = double(propOffset);
ta.TimingAdvanceSamples = double(propOffset);
ta.TimingAdvanceCommand = double(max(0, min(3846, round(propOffset / 16))));
ta.Valid = true;
ta.Source = "msg1_prach_calibrated_propagation_timing";
end
