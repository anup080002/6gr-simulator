function state=enqueueProtocolApplicationPackets(state,cfg)
% Original offered bytes enter L2 once its own endpoint is admitted.
% Application arrival time is retained; PDCP discard starts at actual L2 admission.
if ~logical(sixgr.util.structGet(state,'ProtocolWaveformEnabled',false)), return; end
bridge=state.ProtocolBridge; T=state.PacketDeliveryLedgerTable;
known=sixgr.util.structGet(state,'ProtocolEnqueuedApplicationIDs',strings(0,1));
if ~ismember('ProtocolAdmissionTime_s',T.Properties.VariableNames)
    T.ProtocolAdmissionTime_s=nan(height(T),1);
    T.ProtocolAdmissionSource=strings(height(T),1);
end
if bridge.OriginalRRCRequired
    assert(isfield(state,'SharedWaveformStream'),'sixgr:protocol:OriginalAdmissionClock', ...
        'Original DRB application admission requires the shared execution clock.');
    owner=state.SharedWaveformStream;
    assert((isstruct(owner.Physical)&&isfield(owner.Physical,'ConfigurationEpoch'))|| ...
        (isobject(owner.Physical)&&isprop(owner.Physical,'ConfigurationEpoch')),'sixgr:protocol:OriginalAdmissionClock', ...
        'Original shared execution clock epoch is required.');
    admissionTime=owner.Events.NextSampleIndex/owner.SampleRateHz;
end
for k=1:height(T)
    id=string(T.ApplicationPacketId(k)); if any(known==id), continue; end
    if bridge.OriginalRRCRequired&&~bridge.endpointAdmitted(double(T.UEIndex(k)),string(T.Direction(k)),"TX")
        T.ProtocolAdmissionSource(k)="waiting_original_received_DRB_endpoint";
        continue;
    end
    if bridge.OriginalRRCRequired
        assert(all(ismember({'QFI','PduSessionID'},T.Properties.VariableNames)), ...
            'sixgr:protocol:ApplicationBearerMapping','Original offered QFI and PDU session must be retained.');
        bridge.validateApplicationMapping(double(T.UEIndex(k)),string(T.Direction(k)), ...
            double(T.QFI(k)),double(T.PduSessionID(k)));
        bridge.validateOriginalApplicationClock(double(T.UEIndex(k)),string(T.Direction(k)), ...
            owner.Events.NextSampleIndex,owner.SampleRateHz,owner.Physical.ConfigurationEpoch);
        if admissionTime<double(T.EnqueueTime_s(k)),continue;end
        time=admissionTime;source="original_DRB_endpoint_admitted_at_shared_sample";
    else
        time=double(T.EnqueueTime_s(k));source="explicit_preconfigured_bounded_DRB_original_arrival";
    end
    bits=double(T.OfferedBits(k)); assert(isfinite(bits)&&bits>0&&mod(bits,8)==0, ...
        'sixgr:protocol:NonByteAlignedApplicationPayload','Original queued packet requires whole bytes.');
    bytes=sixgr.protocol.applicationPayloadBytes(state.ProtocolPayloadSeed,string(T.PacketId(k)), ...
        string(T.Direction(k)),double(T.UEIndex(k)),0,bits/8);
    assert(sixgr.protocol.ProtocolHash.bytes(bytes)==string(T.OriginalApplicationPayloadSHA256(k)), ...
        'sixgr:protocol:OriginalPacketIdentity','Original arrival hash differs before L2 enqueue.');
    packet=bridge.enqueuePacket(double(T.UEIndex(k)),string(T.Direction(k)),id,bytes,time);
    T.ProtocolAdmissionTime_s(k)=time;T.ProtocolAdmissionSource(k)=source;
    T.ProtocolUEID(k)=string(packet.UEID);
    T.ProtocolBearerID(k)=string(packet.BearerID);
    T.ProtocolConfigurationEpoch(k)=double(packet.ConfigurationEpoch);
    known(end+1,1)=id;
end
state.ProtocolEnqueuedApplicationIDs=known;
state.PacketDeliveryLedgerTable=T;
p=sixgr.util.structGet(state,'ULMACPolicy',struct('Enabled',false));
if p.Enabled && isfield(state,'SharedUEBSRStates')
    for u=1:numel(state.SharedUEBSRStates)
        if ~isempty(state.SharedUEBSRStates{u})
            sixgr.truth.refreshUEMACQueue(state,u,p,state.CurrentSlot);
        end
    end
end
end
