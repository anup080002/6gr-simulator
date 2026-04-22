function timing = estimateTimingOffset(offsetSamples, sampleRateHz, trueOffsetSamples)
%ESTIMATETIMINGOFFSET Convert sample-domain timing offsets into KPI fields.

if nargin < 3
    trueOffsetSamples = NaN;
end

timing = struct();
timing.OffsetSamples = double(offsetSamples);
timing.Offset_us = 1e6 * double(offsetSamples) / max(double(sampleRateHz), eps);
timing.TrueOffsetSamples = double(trueOffsetSamples);
timing.TrueOffset_us = 1e6 * double(trueOffsetSamples) / max(double(sampleRateHz), eps);
timing.ErrorSamples = double(offsetSamples) - double(trueOffsetSamples);
timing.Error_us = 1e6 * timing.ErrorSamples / max(double(sampleRateHz), eps);
end
