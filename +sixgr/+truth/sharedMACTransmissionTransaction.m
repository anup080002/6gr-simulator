function transaction=sharedMACTransmissionTransaction(action,state,grant,bits,ue,direction,identity,startSample,slot)
% Coordinator-only validation/commit after the physical owner starts TX.
transaction=struct('Enabled',false);
if ~logical(sixgr.util.structGet(grant,'ProtocolPayloadSameWaveformTruth',false)) || ...
        sixgr.truth.GrantPreparation.grantIsRetransmission(grant), return; end
time=startSample/identity.SampleRateHz; id=string(grant.TransportBlockId);
bridge=state.ProtocolBridge;
bridge.validatePreparedTransportBlock(id,time,bits);
transaction=struct('Enabled',true,'TransportBlockId',id,'Time_s',time,'HasControl',false);
if direction=="UL" && isfield(grant,'MACControlTransaction')
    t=grant.MACControlTransaction; scope=grant.MACOwnerScope;
    assert(isequaln(scope,state.SharedUEMACScopes{ue})&&scope.RNTI==identity.RNTI&& ...
        t.SHA256==sixgr.l2.mac.MACHash.of(rmfield(t,'SHA256')), ...
        'sixgr:mac:MACTXTransactionIdentity','Original UE scope and immutable MAC transaction required.');
    receipt=grant.MACFinalizationReceipt;
    bytes=uint8(double(reshape(bits,8,[]).')*(2.^(7:-1:0)).');
    mac=sixgr.l2.mac.MACPDUDemultiplexer.decode('UL',bytes);
    assert(receipt.SHA256==sixgr.l2.mac.MACHash.of(rmfield(receipt,'SHA256'))&& ...
        isequaln(receipt.Authority,t.Authority)&&receipt.MACSHA256==mac.SHA256&& ...
        string(grant.ProtocolMACSHA256)==mac.SHA256, ...
        'sixgr:mac:MACTXEncodedControl','Finalized original MAC receipt and actual bytes differ.');
    controls=mac.SubPDUs(string({mac.SubPDUs.Kind})~="SDU");
    assert(numel(controls)==numel(t.ControlSubPDUs),'sixgr:mac:MACTXEncodedControl','Actual CE count differs.');
    for k=1:numel(controls)
        assert(controls(k).LCID==t.ControlSubPDUs(k).LCID&& ...
            isequal(controls(k).Payload(:),t.ControlSubPDUs(k).Payload(:)), ...
            'sixgr:mac:MACTXEncodedControl','Actual CE bytes differ from trigger transaction.');
    end
    volume=bridge.pendingTransmitBytes(ue,'UL');
    selected=grant.ProtocolRLCSegmentPayloadBytes;
    validateattributes(selected,{'numeric'},{'scalar','integer','finite','nonnegative','<=',volume.TotalBSRBytes});
    policy=state.ULMACPolicy; post=zeros(1,policy.LCGID+1);
    post(policy.LCGID+1)=volume.TotalBSRBytes-selected;
    phr=state.SharedUEPHRStates{ue}; bsr=state.SharedUEBSRStates{ue};
    assert(bsr.Buffers(policy.LCGID+1)==volume.TotalBSRBytes, ...
        'sixgr:mac:UEMACQueueSynchronization','UE BSR queue must retain all original arrivals before TX commit.');
    tx=struct('Executed',true,'IsNewData',true,'UEID',ue,'Slot',slot, ...
        'TransmissionID',identity.TransmissionID);
    if t.PHRReport.Transmit
        q=controls([controls.LCID]==57);
        assert(isscalar(q),'sixgr:mac:MACTXEncodedControl','Exactly one transmitted PHR required.');
        [~,~,~,decoded]=sixgr.l2.mac.BSR_PHR.decodeSingleEntryPHR(q.Payload);
        assert(isequal(decoded.PHIndex,t.PHRReport.PHIndex)&&isequal(decoded.PCMAXIndex,t.PHRReport.PCMAXIndex), ...
            'sixgr:mac:MACTXEncodedControl','PHR trigger transaction differs from encoded indices.');
        tx.PHRReportSHA256=t.PHRReport.ReportSHA256;
        phr.validateTransmission(t.PHRReport,tx);
    end
    if t.BSRReport.Transmit, bsr.validatePreviewCommit(t.BSRReport,slot,post); end
    transaction.HasControl=true;
end
assert(any(string(action)==["validate","commit"]),'sixgr:mac:MACTransactionAction','Unknown MAC transaction action.');
if string(action)=="validate", return; end
% Every fallible original identity/byte/trigger check precedes handle mutation.
bridge.commitPreparedTransportBlock(id,time);
if transaction.HasControl
    if t.PHRReport.Transmit, phr.recordTransmission(t.PHRReport,tx); end
    if t.BSRReport.Transmit
        bsr.commitPreview(t.BSRReport,slot,post);
    else
        bsr.dequeue(policy.LCGID,selected);
    end
end
end
