function absoluteSlot0=slotIndexFromStartSample(carrier,startSample,sampleRateHz)
% Invert an exact CP-OFDM slot boundary, without mean-slot rounding.
% In particular, normal-CP slots at mu>=2 do not all have equal lengths.
validateattributes(startSample,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
validateattributes(sampleRateHz,{'numeric'},{'scalar','real','finite','positive'});
ticksPerSample=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/double(sampleRateHz);
assert(ticksPerSample==fix(ticksPerSample) && ticksPerSample>=1 && ...
    double(startSample)<=flintmax/ticksPerSample, ...
    'sixgr:phy:frame:SlotBoundaryOffSampleClock', ...
    'Require an exactly representable sample boundary on the NR basic-time clock.');
spec=sixgr.phy.frame.NumerologyCatalog.resolve(double(carrier.SubcarrierSpacing), ...
    string(carrier.CyclicPrefix),'generic_waveform_test','');
time=sixgr.phy.frame.AbsoluteTime(int64(double(startSample)*ticksPerSample));
[frame,slot,symbol,aligned]=time.toNumerology(spec);
assert(aligned && symbol==0,'sixgr:phy:frame:NotSlotStartSample', ...
    'The retained nominal origin must be an exact slot start, not an arrival offset or average-duration estimate.');
absoluteSlot0=double(frame)*double(spec.SlotsPerFrame)+double(slot);
end
