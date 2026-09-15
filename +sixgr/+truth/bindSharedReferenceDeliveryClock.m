function rows=bindSharedReferenceDeliveryClock(rows,state)
% Publish a completed shared observation at the actual scheduler boundary.
% Completion and publication are separate events; neither is inferred from
% the source slot or from a consumer's desired availability.
owner=state.SharedWaveformStream;
assert(isa(owner,'sixgr.truth.CoupledWaveformStream'), ...
    'sixgr:truth:ReferenceDeliveryOwnerRequired','Retain the shared physical owner.');
required={'ObservationStartSample','ObservationEndSampleExclusive', ...
    'ObservationSampleRateHz','MeasurementClockEpoch','ResultCompletedAtSample'};
assert(istable(rows) && all(ismember(required,rows.Properties.VariableNames)), ...
    'sixgr:truth:ReferenceDeliveryClockRequired','Retain complete receiver clock evidence.');
fs=owner.SampleRateHz; now=owner.Events.NextSampleIndex;
carrier=sixgr.phy.grid.makeCarrier(state.CfgMobility);
first=sixgr.phy.frame.slotStartSample(carrier,state.CurrentSlot-1,fs);
stop=sixgr.phy.frame.slotStartSample(carrier,state.CurrentSlot,fs);
assert(now==first && all(rows.ObservationSampleRateHz==fs) && ...
    all(rows.MeasurementClockEpoch==owner.Physical.ConfigurationEpoch), ...
    'sixgr:truth:ReferenceDeliveryClockMismatch','Publish on the retained receiver epoch and actual slot-start clock.');
samples=[rows.ObservationStartSample rows.ObservationEndSampleExclusive rows.ResultCompletedAtSample];
assert(isnumeric(samples) && isreal(samples) && all(isfinite(samples),'all') && ...
    all(samples>=0 & samples==fix(samples) & samples<=flintmax,'all') && ...
    all(samples(:,2)>samples(:,1) & samples(:,3)>=samples(:,2) & samples(:,3)<=now), ...
    'sixgr:truth:ReferenceDeliveryBeforeCompletion','Publication requires an already completed receiver observation.');
values=struct('ResultAvailableAtSample',now,'DeliverySlotStartSample',first, ...
    'DeliverySlotEndSampleExclusive',stop,'MeasurementClockDomain',"shared_receiver_sample_clock/v1");
for name=string(fieldnames(values)).'
    value=repmat(values.(name),height(rows),1);
    if ismember(name,rows.Properties.VariableNames)
        assert(isequaln(rows.(name),value),'sixgr:truth:ReferenceDeliveryClockRebound', ...
            'Existing publication clock evidence cannot be overwritten.');
    else
        rows.(name)=value;
    end
end
end
