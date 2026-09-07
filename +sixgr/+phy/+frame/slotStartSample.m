function sample=slotStartSample(carrier,absoluteSlot,sampleRateHz)
% Actual CP-OFDM boundary, not absoluteSlot times the mean slot duration.
spec=sixgr.phy.frame.NumerologyCatalog.resolve(double(carrier.SubcarrierSpacing), ...
    string(carrier.CyclicPrefix),'generic_waveform_test','');
start=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(absoluteSlot,0,spec);
tc=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/double(sampleRateHz);
if ~isfinite(tc) || tc<=0 || tc~=fix(tc) || rem(start.Ticks,int64(tc))~=0
    error('sixgr:phy:frame:SlotBoundaryOffSampleClock','The physical slot boundary must lie on the configured sample clock.');
end
sample=double(idivide(start.Ticks,int64(tc)));
end
