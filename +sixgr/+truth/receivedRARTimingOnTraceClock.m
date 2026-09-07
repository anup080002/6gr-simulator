function samples = receivedRARTimingOnTraceClock(result, traceSampleRateHz)
% RAR TA duration in the PRACH trace clock, not the RAR command index.
% Does not include N_TA,offset, a correlation-peak origin, or an assertion
% that shared-stream UE transmit timing has been applied.
validateattributes(traceSampleRateHz, {'numeric'}, {'real','scalar','finite','positive'});
ticks = sixgr.util.structGet(result, 'TimingAdvanceNTA_Tc', NaN);
source = string(sixgr.util.structGet(result, 'TimingAdvanceSource', ""));
if isnumeric(ticks) && isreal(ticks) && isscalar(ticks) && isnan(ticks) && ...
        isscalar(source) && source == ""
    samples = NaN; % No received/applied RAR timing context yet.
    return;
end
if ~isnumeric(ticks) || ~isreal(ticks) || ~isscalar(ticks) || ...
        ~isfinite(ticks) || ticks < 0 || ticks ~= fix(ticks) || ...
        ~isscalar(source) || source ~= "received_MAC_RAR_absolute_command_ts_38_213_4_2"
    error('sixgr:truth:InvalidRARTimingTraceAuthority', ...
        'The TA marker requires received RAR timing in Tc with explicit provenance.');
end
fs = sixgr.util.structGet(result, 'TimingAdvanceSampleRate_Hz', NaN);
originalSamples = sixgr.util.structGet(result, 'TimingAdvanceSamples', NaN);
validateattributes(fs, {'numeric'}, {'real','scalar','finite','positive'});
validateattributes(originalSamples, {'numeric'}, {'real','scalar','finite','nonnegative'});
seconds = double(ticks)/double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond);
if abs(originalSamples - seconds*fs) > 16*eps(max(1,abs(seconds*fs)))
    error('sixgr:truth:RARTimingTraceUnitMismatch', ...
        'Received RAR Tc, sample rate and sample-duration evidence disagree.');
end
samples = seconds * double(traceSampleRateHz);
end
