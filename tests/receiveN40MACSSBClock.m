function state=receiveN40MACSSBClock(state,items)
% Actual shared SS/PBCH clock for declared-common MAC integration fixture.
% No RAR/RRC/SIB1 reception is inferred from this bounded decoder.
owner=state.SharedWaveformStream;
for item=items
    assert(any(string(item.Kind)==["PBCH","SSBOccasion"]), ...
        'test:MACSSBUnexpectedEvent','Only original broadcast observations are accepted.');
    if string(item.Kind)=="PBCH"
        state.TestMACBroadcastCaptureComplete=true; continue;
    end
    if isfield(state,'TestMACReceivedDLClock'), continue; end
    p=item.Context.Prepared;
    [~,pre,~,~,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes);
    recovered=sixgr.phy.broadcast.recoverSIB1FromWaveform(receiver,p.ReceiverConfig, ...
        'RecoveryScope','SSB_MIB','CandidateSSBIndex',item.Context.SSBOccasionHorizon.SSBIndex, ...
        'PhysicalMeasurementObservation',pre);
    if ~(recovered.BCHCrcPass && recovered.MIBDecoded), continue; end
    ch=owner.channelState(item.UE,'DL');
    reference=sixgr.phy.frame.receivedDLTimingReference( ...
        p.ReceiverConfig,recovered,receiver,ch.ChannelTrimSamples);
    assert(reference.AvailableAtSample<=owner.Events.NextSampleIndex);
    state.TestMACReceivedDLClock=reference;
    save(fullfile(state.TestMACClockRoot,'original_shared_ssb_clock.mat'), ...
        'item','recovered','reference','-v7.3');
    fprintf('MAC_ORIGINAL_SSB_CLOCK sample=%d SSB=%d phase=%d BCH_CRC=1\n', ...
        reference.AvailableAtSample,reference.SSBIndex,reference.DLPhaseOffsetSamples);
end
end
