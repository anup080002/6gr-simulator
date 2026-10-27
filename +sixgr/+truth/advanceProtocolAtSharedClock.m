function state=advanceProtocolAtSharedClock(state,stream)
% A timer releases retained decoded bytes; it is not a new PHY reception.
if ~logical(sixgr.util.structGet(state,'ProtocolWaveformEnabled',false)), return; end
bridge=state.ProtocolBridge;
sample=double(stream.Events.NextSampleIndex); fs=double(stream.SampleRateHz);
time=sample/fs;
completed=bridge.advance(time);
state=sixgr.truth.applyProtocolPacketDiscards(state,bridge.takeDiscardEvents());
indications=bridge.takeUpperLayerIndications();
if ~isempty(indications)
    rows=struct2table(indications,'AsArray',true);
    prior=sixgr.util.structGet(state,'ProtocolUpperLayerIndicationsTable',table());
    if ~isempty(prior)
        assert(~any(ismember(rows.IndicationID,prior.IndicationID)), ...
            'sixgr:protocol:DuplicateUpperLayerIndication','One original RLC threshold event must be delivered once.');
    end
    state.ProtocolUpperLayerIndicationsTable=[prior;rows];
end
security=bridge.takeSecurityIndications();
if ~isempty(security)
    rows=struct2table(security,'AsArray',true);
    assert(all(rows.SampleClockQualified & rows.SampleRateHz==fs & ...
        rows.ClockEpoch==stream.Physical.ConfigurationEpoch & rows.Sample<=sample), ...
        'sixgr:pdcp:SecurityObservationClock','Only original same-clock received failures enter shared publication.');
    rows.PublicationAvailableAtSample=repmat(sample,height(rows),1);
    prior=sixgr.util.structGet(state,'ProtocolSecurityIndicationsTable',table());
    assert(isempty(prior)||~any(ismember(rows.IndicationID,prior.IndicationID)), ...
        'sixgr:pdcp:DuplicateSecurityIndication','One original security failure is delivered once.');
    state.ProtocolSecurityIndicationsTable=[prior;rows];
end
if isempty(completed), return; end
slot=floor(time/double(state.SlotDuration_s))+1;
clock=struct('DeliveryTime_s',time,'DeliveryCanonicalSlot',slot, ...
    'DeliveryAvailableAtSample',sample,'DeliverySampleRateHz',fs, ...
    'DeliveryAvailableCanonicalSlot',slot,'TimingAuthority',"original_shared_sample_clock_timer_expiry");
[T,initialCount]=sixgr.truth.combinePacketTransportLedgers(state);
T=sixgr.truth.applyProtocolPacketCompletions(T,completed,clock);
state=sixgr.truth.publishPacketTransportLedgers(state,T,initialCount);
state=sixgr.truth.refreshApplicationPacketDeliveries(state);
end
