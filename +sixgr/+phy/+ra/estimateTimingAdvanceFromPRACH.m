function ta = estimateTimingAdvanceFromPRACH(det, sampleRateHz, firstULSCSkHz)
%ESTIMATETIMINGADVANCEFROMPRACH Convert calibrated PRACH timing evidence to TA.
if nargin ~= 3
    error('sixgr:phy:ra:MissingRARTimingClock', ...
        'PRACH delay conversion requires its actual sample rate and the first scheduled UL SCS.');
end
step = sixgr.phy.ra.resolveRARTimingAdvance(0,firstULSCSkHz,sampleRateHz);
rawOffset = double(sixgr.util.structGet(det, "TimingOffsetSamples", NaN));
if ~(isscalar(rawOffset) && isfinite(rawOffset))
    rawOffset = NaN;
end
propOffset = double(sixgr.util.structGet(det, "PropagationTimingOffsetSamples", NaN));
if ~(isscalar(propOffset) && isreal(propOffset) && isfinite(propOffset) && propOffset>=0)
    ta = struct();
    ta.RawTimingOffsetSamples = double(rawOffset);
    ta.TimingOffsetSamples = NaN;
    ta.TimingAdvanceSamples = NaN;
    ta.TimingAdvanceCommand = NaN;
    ta.Valid = false;
    ta.Source = "msg1_prach_propagation_timing_unavailable";
    return;
end
% Nearest legal RAR step is the explicit gNB quantization policy. Do not
% first round the observation to samples or silently clamp an overflow.
command = round(propOffset / step.StepSamples);
if command > 3846
    error('sixgr:phy:ra:PRACHTimingOutsideRARRange', ...
        'Measured PRACH delay cannot be represented by the RAR TA field at the configured UL SCS.');
end
timing = sixgr.phy.ra.resolveRARTimingAdvance(command,firstULSCSkHz,sampleRateHz);
ta = struct();
ta.RawTimingOffsetSamples = double(rawOffset);
ta.TimingOffsetSamples = double(propOffset);
ta.TimingAdvanceSamples = timing.Samples;
ta.TimingAdvanceCommand = timing.Command;
ta.NTA_Tc = timing.NTA_Tc;
ta.SampleRateHz = double(sampleRateHz);
ta.FirstULSCSkHz = double(firstULSCSkHz);
ta.StepSamples = timing.StepSamples;
ta.QuantizationResidualSamples = propOffset-timing.Samples;
ta.Valid = true;
ta.Source = "msg1_prach_measured_delay_nearest_rar_ta_step_ts_38_213_4_2";
end
