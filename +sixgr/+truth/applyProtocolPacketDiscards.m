function state=applyProtocolPacketDiscards(state,events)
% Original PDCP timer + lower-layer refusal/removal, never HARQ-inferred loss.
if isempty(events),return;end
assert(numel(unique(string({events.ReceiptID})))==numel(events), ...
    'sixgr:protocol:DuplicateDiscardReceipt','A batch cannot repeat an original discard receipt.');
bridge=state.ProtocolBridge;P=state.PacketDeliveryLedgerTable;
prior=sixgr.util.structGet(state,'ProtocolDiscardEventsTable',table());
if ~ismember('DiscardedUnscheduledBits',P.Properties.VariableNames)
    P.DiscardedUnscheduledBits=zeros(height(P),1);P.DiscardReceiptID=strings(height(P),1);
end
S=sixgr.util.structGet(state,'PacketSDULedgerTable',table());
affectedUL=[];
for r=reshape(events,1,[])
    assert(isequaln(r,bridge.originalDiscardReceipt(r.ReceiptID)), ...
        'sixgr:protocol:DiscardIdentity','Discard must be the original private protocol receipt.');
    assert(isempty(prior)||~any(prior.ReceiptID==r.ReceiptID), ...
        'sixgr:protocol:DuplicateDiscardReceipt','The same original discard event cannot be applied twice.');
    if r.PacketizationMode=="legacy_fragment"
        % Legacy fragments have their own protocol identity; they are
        % already handed to MAC. Do not invent a whole-application mapping.
        assert(r.ApplicationBytesDropped==0&&r.LowerLayerDisposition=="retained_already_handed_to_lower_layer", ...
            'sixgr:protocol:DiscardIdentity','Submitted legacy fragments cannot claim an unsent application discard.');
        continue;
    end
    assert(all(ismember({'ProtocolUEID','ProtocolBearerID','ProtocolConfigurationEpoch'},P.Properties.VariableNames)), ...
        'sixgr:protocol:DiscardIdentity','Original application enqueue scope is required before discard.');
    mask=P.UEIndex==r.UEIndex & string(P.Direction)==r.Direction & string(P.ApplicationPacketId)==r.PacketID & ...
        string(P.ProtocolUEID)==r.UEID & string(P.ProtocolBearerID)==r.BearerID & ...
        P.ProtocolConfigurationEpoch==r.ConfigurationEpoch;
    assert(nnz(mask)==1&&P.OriginalApplicationPayloadSHA256(mask)==r.PayloadSHA256&& ...
        P.OfferedBits(mask)==8*r.PacketBytes,'sixgr:protocol:DiscardIdentity', ...
        'Discard must match the original offered application bytes and owner.');
    if r.ApplicationBytesDropped==0,continue;end
    bits=8*r.ApplicationBytesDropped;
    assert(r.LowerLayerDisposition=="discarded_wholly_unsubmitted"&&r.ApplicationBytesDropped==r.PacketBytes&& ...
        P.RemainingBits(mask)==bits&&P.ScheduledBits(mask)==0&&~P.DeliverySuccess(mask)&&P.DiscardedUnscheduledBits(mask)==0, ...
        'sixgr:protocol:DiscardIdentity','Application drop requires actual wholly unsubmitted byte removal.');
    if ~isempty(S)
        assert(~any(S.UEIndex==r.UEIndex&string(S.Direction)==r.Direction&string(S.ApplicationPacketId)==r.PacketID), ...
            'sixgr:protocol:DiscardIdentity','A MAC-committed application range cannot become an unsent discard.');
    end
    field=char(r.Direction+"QueueBits");
    assert(state.(field)(r.UEIndex)>=bits,'sixgr:protocol:DiscardIdentity','Actual queue debit exceeds original queued bytes.');
    state.(field)(r.UEIndex)=state.(field)(r.UEIndex)-bits;
    P.RemainingBits(mask)=0;P.DiscardedUnscheduledBits(mask)=bits;P.DiscardReceiptID(mask)=r.ReceiptID;
    P.Status(mask)="PDCP_timer_discarded_before_MAC_submission";
    if r.Direction=="UL",affectedUL(end+1)=r.UEIndex;end %#ok<AGROW>
end
state.PacketDeliveryLedgerTable=P;
state.ProtocolDiscardEventsTable=[prior;struct2table(events,'AsArray',true)];
state=sixgr.truth.reconcilePacketBitConservation(state);
policy=sixgr.util.structGet(state,'ULMACPolicy',struct('Enabled',false));
if policy.Enabled
    for ue=unique(affectedUL)
        sixgr.truth.refreshUEMACQueue(state,ue,policy,state.CurrentSlot);
    end
end
end
