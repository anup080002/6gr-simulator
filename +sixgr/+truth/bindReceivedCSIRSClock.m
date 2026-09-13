function rows=bindReceivedCSIRSClock(rows,prepared,observation,timing,availableAtSample,epoch)
% Bind CSI rows to the completed shared DL receiver, without changing RF data.
if isempty(rows), return; end
assert(istable(rows),'sixgr:truth:CSIRSClockTableRequired','Retain actual receiver rows.');
e=sixgr.truth.receivedDataSymbolTiming(prepared,observation,timing,availableAtSample);
assert(e.Direction=="DL",'sixgr:truth:CSIRSClockDirection','CSI-RS requires a DL capture.');
validateattributes(epoch,{'numeric'},{'scalar','real','finite','integer','nonnegative','<=',flintmax});
assert(all(ismember({'Slot','RNTI'},rows.Properties.VariableNames)) && ...
    all(rows.Slot==e.DataAbsoluteSlot+1) && all(rows.RNTI==e.RNTI), ...
    'sixgr:truth:CSIRSClockIdentityMismatch','CSI rows must belong to this executed DL allocation.');
% Locate the completion event in the exact CP-OFDM calendar. No average-slot
% division: high numerologies may have nonuniform sample lengths.
carrier=prepared.Tx.Carrier;
slot0=e.DataAbsoluteSlot;
start=sixgr.phy.frame.slotStartSample(carrier,slot0,e.SampleRateHz);
assert(availableAtSample>=start,'sixgr:truth:CSIRSClockBeforeSource','Completion precedes the source slot.');
stop=sixgr.phy.frame.slotStartSample(carrier,slot0+1,e.SampleRateHz);
while availableAtSample>=stop
    slot0=slot0+1; start=stop;
    stop=sixgr.phy.frame.slotStartSample(carrier,slot0+1,e.SampleRateHz);
end
values=struct('ObservationStartSample',e.ObservationStartSample, ...
    'ObservationEndSampleExclusive',e.ObservationEndSampleExclusive, ...
    'ObservationSampleRateHz',e.SampleRateHz, ...
    'ResultAvailableAtSample',e.ResultAvailableAtSample, ...
    'MeasurementClockEpoch',double(epoch), ...
    'ObservationDeliverySlot',slot0+1, ...
    'DeliverySlotStartSample',start,'DeliverySlotEndSampleExclusive',stop, ...
    'MeasurementClockDomain',"shared_receiver_sample_clock/v1", ...
    'RuntimeTransportMode',"shared_physical_stream_CSIRS_received_completion");
for name=string(fieldnames(values)).'
    bound=repmat(values.(name),height(rows),1);
    if ismember(name,rows.Properties.VariableNames)
        assert(isequaln(rows.(name),bound), ...
            'sixgr:truth:ConflictingCSIRSReceiverClock', ...
            'Existing CSI receiver-clock evidence cannot be overwritten or rebound to a later event.');
    else
        rows.(name)=bound;
    end
end
end
