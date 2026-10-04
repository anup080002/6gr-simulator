function time_s=resolveReplayChannelTime(cfg,grant,slotField,explicitTime_s)
% Bind the fading process to the same absolute clock as transmitted samples.
% An explicit calibration time may not contradict an issued grant clock.
if nargin<4, explicitTime_s=[]; end
slot=double(sixgr.util.structGet(grant,slotField,NaN));
hasSlot=isfield(grant,slotField);
carrier=sixgr.phy.grid.makeCarrier(cfg);
if hasSlot
    assert(isscalar(slot)&&isreal(slot)&&isfinite(slot)&&slot>=0&& ...
        slot==fix(slot)&&slot<flintmax,'sixgr:system:WaveformReplay:InvalidAbsoluteSlot', ...
        '%s must be an exact nonnegative absolute slot.',slotField);
else
    % Legacy isolated component calls still own an explicit configured
    % carrier clock. Do not reset it to zero when NSlot/NFrame are nonzero.
    slot=double(carrier.NFrame)*double(carrier.SlotsPerFrame)+double(carrier.NSlot);
end
% Normal-CP slots at mu >= 2 do not all have the mean slot duration.
% Use the existing physical sample clock, shared with waveform assembly.
ofdm=nrOFDMInfo(carrier);
expected=sixgr.phy.frame.slotStartSample(carrier,slot,ofdm.SampleRate)/ofdm.SampleRate;
if isempty(explicitTime_s)
    time_s=expected;
else
    validateattributes(explicitTime_s,{'numeric'},{'scalar','real','finite','nonnegative'});
    time_s=double(explicitTime_s);
    assert(~hasSlot||abs(time_s-expected)<=16*eps(max(1,expected)), ...
        'sixgr:system:WaveformReplay:ChannelClockMismatch', ...
        'Fading time %.17g s disagrees with %s (%.17g s).',time_s,slotField,expected);
end
end
