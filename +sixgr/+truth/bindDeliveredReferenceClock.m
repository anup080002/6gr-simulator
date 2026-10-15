function row=bindDeliveredReferenceClock(state,row)
% Bind deferred SRS/TRS at its delivery event, not an assumed source delay.
owner=sixgr.util.structGet(state,'SharedWaveformStream',[]);
assert(isa(owner,'sixgr.truth.CoupledWaveformStream') && height(row)==1, ...
    'sixgr:truth:ReferenceDeliveryOwnerRequired','A shared receiver owner is required.');
fs=owner.SampleRateHz;
carrier=sixgr.phy.grid.makeCarrier(state.CfgMobility);
first=sixgr.phy.frame.slotStartSample(carrier,state.CurrentSlot-1,fs);
last=sixgr.phy.frame.slotStartSample(carrier,state.CurrentSlot,fs);
now=owner.Events.NextSampleIndex;
assert(row.ObservationSampleRateHz==fs && ...
    row.ObservationEndSampleExclusive<=now && now>=first && now<last && ...
    row.MeasurementClockEpoch==owner.Physical.ConfigurationEpoch, ...
    'sixgr:truth:ReferenceDeliveryClockMismatch', ...
    'A delivered result must follow its capture on the actual receiver clock.');
row.ResultCompletedAtSample=row.ObservationEndSampleExclusive;
row.ResultAvailableAtSample=double(now);
row.DeliverySlotStartSample=double(first);
row.DeliverySlotEndSampleExclusive=double(last);
row.MeasurementClockDomain="shared_receiver_sample_clock/v1";
end
