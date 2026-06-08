function timing = estimateTimingOffset(offsetSamples, sampleRateHz, trueOffsetSamples)
%ESTIMATETIMINGOFFSET Convert PRACH timing observations to KPI fields.

if nargin < 3
    trueOffsetSamples = NaN;
end

timing = struct();
timing.OffsetSamples = double(offsetSamples);
timing.TrueOffsetSamples = double(trueOffsetSamples);
timing.TruthAvailable = isfinite(double(trueOffsetSamples));

sr = double(sampleRateHz);
if ~(isfinite(sr) && sr > 0)
    timing.Offset_us = NaN;
    timing.TrueOffset_us = NaN;
    timing.ErrorSamples = NaN;
    timing.Error_us = NaN;
    return;
end

timing.Offset_us = 1e6 * timing.OffsetSamples / sr;
timing.TrueOffset_us = 1e6 * timing.TrueOffsetSamples / sr;
timing.ErrorSamples = timing.OffsetSamples - timing.TrueOffsetSamples;
timing.Error_us = 1e6 * timing.ErrorSamples / sr;

if ~timing.TruthAvailable
    timing.ErrorSamples = NaN;
    timing.Error_us = NaN;
end
end
