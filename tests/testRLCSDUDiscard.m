function ok=testRLCSDUDiscard()
% Exact RLC/MAC component boundary; no RF or remotely decoded STATUS claim.
% ACK bytes enter the original received-STATUS API explicitly, never via RX delivery.
setup6GRSimToolkit('Verbose',false);
for sn=[12 18]
    c=config(sn); e=sixgr.l2.rlc18.RLCAMEntity(c);
    a=e.addSDU(uint8(1:4)); b=e.addSDU(uint8(5:8)); d=e.addSDU(uint8(9:12));
    assert(a~=b && b~=d && a~=d);
    r=e.discardUnsubmittedSDU(b);
    assert(r.Discarded && r.OriginalFullCount==1 && r.RemappedQueueIDs==d && ...
        r.OldFullCounts==2 && r.NewFullCounts==1 && e.pendingPayloadBytes()==8);
    again=e.discardUnsubmittedSDU(b);assert(~again.Discarded && again.Disposition=="already_discarded");
    [p,s,t]=e.previewPDU(64);assert(s.QueueID==a && s.FullCount==0 && s.SN==0);
    e.commitPreparedPDU(t,.001);
    [p2,s2,t2]=e.previewPDU(64);assert(s2.QueueID==d && s2.FullCount==1 && s2.SN==1);
    e.commitPreparedPDU(t2,.002);
    assert(e.pendingPayloadBytes()==0 && isempty(e.takeSDUAcknowledgements()));
    % Local peer RX completion is not TX acknowledgment.
    peer=sixgr.l2.rlc18.RLCAMEntity(c);peer.receivePDU(p{1},.002);peer.receivePDU(p2{1},.003);
    assert(numel(peer.pullSDUs())==2 && isempty(e.takeSDUAcknowledgements()));
    ack=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(sn,2,struct([]));
    ack=ack.Bytes;
    token=e.previewReceivedStatus(ack,'original-component-status',.004);
    assert(isempty(e.takeSDUAcknowledgements()));e.cancelReceivedStatus(token);
    assert(isempty(e.takeSDUAcknowledgements()));
    e.receiveStatus(ack,'original-component-status',.004);
    rows=e.takeSDUAcknowledgements();assert(numel(rows)==2);
    assert(isequal([rows.QueueID],[a d]) && isequal([rows.RLCFullCount],[0 1]) && ...
        all([rows.STATUSReceiptID]=="original-component-status") && ...
        all([rows.STATUSPayloadSHA256]==sixgr.protocol.ProtocolHash.bytes(ack)) && ...
        all([rows.AcknowledgedAtSample]==4));
    assert(rows(1).PayloadSHA256==sixgr.protocol.ProtocolHash.bytes(uint8(1:4)));
    assert(isempty(e.takeSDUAcknowledgements()));
    e.receiveStatus(ack,'original-component-status',.005);
    assert(isempty(e.takeSDUAcknowledgements()));
    e.receiveStatus(ack,'second-original-status-same-ACK',.006);
    assert(isempty(e.takeSDUAcknowledgements()));
    % A returned original AMD PDU is handed to lower MAC even before RF.
    e=sixgr.l2.rlc18.RLCAMEntity(c);a=e.addSDU(uint8(1:8));b=e.addSDU(uint8(11:14));
    [p,s,t]=e.previewPDU(5);assert(s.QueueID==a && ~s.Complete);
    r=e.discardUnsubmittedSDU(a);assert(~r.Discarded && e.pendingPayloadBytes()==12);
    e.cancelPreparedPDU(t);r=e.discardUnsubmittedSDU(a);assert(~r.Discarded);
    % Removing a never-handed tail must not invalidate the original head PDU.
    [p,s,t]=e.previewPDU(5);r=e.discardUnsubmittedSDU(b);assert(r.Discarded);
    [actual,committed]=e.commitPreparedPDU(t,.001);
    assert(isequal(actual,p{1}) && committed.QueueID==a && e.State.TX_NEXT==0);
    r=e.discardUnsubmittedSDU(a);assert(~r.Discarded && e.pendingPayloadBytes()==8-s.PayloadBytes);
    partialAck=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(sn,1,struct([]));
    partialAck=partialAck.Bytes;
    e.receiveStatus(partialAck,'partial-submitted-byte-ACK',.002);
    assert(isempty(e.takeSDUAcknowledgements()),'ACK of submitted prefix cannot confirm the unsent SDU tail.');
    [~,~,tail]=e.previewPDU(64);e.commitPreparedPDU(tail,.003);
    e.receiveStatus(partialAck,'whole-original-byte-ACK',.004);
    confirmed=e.takeSDUAcknowledgements();
    assert(isscalar(confirmed) && confirmed.QueueID==a && confirmed.RLCFullCount==0 && ...
        confirmed.STATUSReceiptID=="whole-original-byte-ACK");
    reject(@()e.discardUnsubmittedSDU("foreign-owner-id"));
    % Head removal closes count gaps without losing a later opaque identity.
    e=sixgr.l2.rlc18.RLCAMEntity(c);a=e.addSDU(uint8(1:4));b=e.addSDU(uint8(5:8));
    r=e.discardUnsubmittedSDU(a);assert(r.Discarded && r.RemappedQueueIDs==b);
    [~,s]=e.previewPDU(64);assert(s.QueueID==b && s.FullCount==0 && s.SN==0);
end
c=config(12);arq=sixgr.l2.rlc18.RLCAMARQState(c.ARQConfig);
for k=0:2,arq=arq.retainSDU(k,uint8(k+(1:4)));end
before=arq;[same,r]=arq.discardUnsubmitted(1,2);assert(~r.Discarded && isequaln(same,before));
[next,r]=arq.discardUnsubmitted(1,[]);
assert(r.Discarded && next.HighestSubmitted==before.HighestSubmitted && ...
    next.NextAck==before.NextAck && isequaln(next.PollSN,before.PollSN) && ...
    next.PollDeadline==before.PollDeadline && isequal(next.SeenTX,before.SeenTX) && ...
    isequal(next.SeenSTATUS,before.SeenSTATUS));
ok=true;fprintf('RLC_SDU_DISCARD_PASS stable_identity=1 immutable_MAC_handoff=1 actual_STATUS_API_only=1 RF_qualified=0\n');
end
function c=config(sn)
c=struct('UEID',"UE-001",'BearerID',"DRB-1",'Direction',"DL", ...
    'ConfigurationEpoch',1,'SNBits',sn,'ARQEnabled',true,'PollPDU',16, ...
    'PollByte',65536,'MaxRetxThreshold',8);
c.ARQConfig=struct('BearerID',"component",'SNBits',sn,'InitialCount',0, ...
    'PollRetransmitSamples',45,'ReassemblySamples',5,'StatusProhibitSamples',0, ...
    'ClockEpoch',1,'SampleRateHz',1000,'MaxRetxThreshold',8);
end
function reject(fn)
try,fn();catch e,assert(strcmp(e.identifier,'sixgr:rlc:SDUIdentity'));return;end
error('test:MissingSDUIdentityGuard','Foreign opaque identity was accepted.');
end
