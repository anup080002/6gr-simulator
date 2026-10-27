function ok=testRLCAMARQState()
% State-machine test; declared receipt boundary, no PHY transport claim.
c=struct('BearerID',"b1",'SNBits',12,'InitialCount',4095,'PollRetransmitSamples',20, ...
    'ClockEpoch',3,'SampleRateHz',1e6,'MaxRetxThreshold',2);
a=sixgr.l2.rlc18.RLCAMARQState(c); data=uint8(10:19);
a=a.retainSDU(4095,data); a=initial(a,data,0,1,"tx1");
n=struct('NACKSN',4095,'SOstart',2,'SOend',5,'NACKRange',[]);
s=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(12,0,n);
[a,result]=a.admitSTATUS(s.Bytes,receipt("rx1",2,"original_CRC_accepted_reverse_MAC_STATUS",s.Bytes));
assert(result=="original_STATUS_applied" && isinf(a.PollDeadline) && a.Records{1}.RetxCount==0);
assert(a.pendingRetxBytes()==4 && a.nextRetainedCount()==4096 && numel(a.unackedRecords())==1);
[b,result]=a.admitSTATUS(s.Bytes,receipt("rx1",2,"original_CRC_accepted_reverse_MAC_STATUS",s.Bytes));
assert(result=="duplicate_original_receipt" && isequaln(a,b));
p=a.previewRetx(7,false); assert(p.Offset==2 && p.StopExclusive==5);
assert(isequaln(a.previewRetx(7,false),p)); % Withheld preview consumes nothing.
[a,p]=a.prepareRetx(7,false);
released=a.releasePreparedRetx(p);assert(released.pendingRetxBytes()==4);
b=a.commitRetx(p,receipt("tx2",3,"actual_MAC_lower_layer_submission",p.PDU));
assert(~any(b.Records{1}.Pending(3:5)) && b.Records{1}.Pending(6));
reject(@()b.commitRetx(p,receipt("tx3",4,"actual_MAC_lower_layer_submission",p.PDU)));
ack=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(12,0,n([]));
[ackedBeforeTX,~]=a.admitSTATUS(ack.Bytes,receipt("ack_before_tx",3,"original_CRC_accepted_reverse_MAC_STATUS",ack.Bytes));
ackedBeforeTX=ackedBeforeTX.commitRetx(p,receipt("late_original_tx",4,"actual_MAC_lower_layer_submission",p.PDU));
assert(ackedBeforeTX.NextAck==4096 && ackedBeforeTX.pendingRetxBytes()==0);
[b,~]=b.admitSTATUS(ack.Bytes,receipt("rx2",5,"original_CRC_accepted_reverse_MAC_STATUS",ack.Bytes));
assert(b.NextAck==4096 && ~any(b.Records{1}.Pending));
assert(b.pendingRetxBytes()==0 && isempty(b.unackedRecords()));
% Poll expiry offers original unacked bytes without assuming peer delivery.
a=sixgr.l2.rlc18.RLCAMARQState(c);a=a.retainSDU(4095,data);
a=initial(a,data,0,10,"tx4");
b=a.advancePollTimer(29,true,false);assert(~any(b.Records{1}.Pending));
b=b.advancePollTimer(30,true,false);assert(all(b.Records{1}.Pending)&&b.PollRequired);
assert(isequal(a.Records{1}.Bytes,b.Records{1}.Bytes));
% Highest partially submitted SDU: NACK tail does not convert unsent bytes.
a=sixgr.l2.rlc18.RLCAMARQState(c);a=a.retainSDU(4095,data);
a=initial(a,data(1:4),1,1,"tx5");
n=struct('NACKSN',4095,'SOstart',2,'SOend',65535,'NACKRange',[]);
s=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(12,0,n);
[a,~]=a.admitSTATUS(s.Bytes,receipt("rx3",2,"original_CRC_accepted_reverse_MAC_STATUS",s.Bytes));
assert(isequal(find(a.Records{1}.Pending),3:4) && ~any(a.Records{1}.Sent(5:end)) && a.NextAck==4095);
% ACK exactly half a 12-bit window is valid when every SN was submitted.
cw=c;cw.InitialCount=0;w=sixgr.l2.rlc18.RLCAMARQState(cw);
for count=0:2047
    payload=uint8(mod(count,256));w=w.retainSDU(count,payload);
    token=struct('Owner',"full_window_test",'Revision',count,'ID',"p"+count);
    bytes=uint8([sixgr.l2.rlc18.RLCHeaderCodec.encodeAM(12,1,0,0,count,[]) payload]);
    proposal=w.previewData(count,bytes,token);
    tx=receipt("w"+count,count,"actual_MAC_lower_layer_submission",bytes);tx.OriginalToken=token;
    w=w.commitData(proposal,tx);
end
% Queued tail beyond the send window is retained, never transmitted early.
w=w.retainSDU(2048,uint8(42));assert(w.windowStalled() && ~w.canTransmitInitial(2048));
blocked=uint8([sixgr.l2.rlc18.RLCHeaderCodec.encodeAM(12,1,0,0,2048,[]) uint8(42)]);
blockedToken=struct('Owner',"full_window_test",'Revision',2048,'ID',"blocked_tail");
reject(@()w.previewData(2048,blocked,blockedToken));
status=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(12,2048,n([]));
[w,disposition]=w.admitSTATUS(status.Bytes,receipt("full_window_ack",2048,"original_CRC_accepted_reverse_MAC_STATUS",status.Bytes));
assert(disposition=="original_STATUS_applied" && w.NextAck==2048 && w.canTransmitInitial(2048) && ~w.windowStalled());
ok=true;
end
function r=receipt(id,sample,source,bytes)
r=struct('ID',id,'BearerID',"b1",'Sample',sample,'ClockEpoch',3,'SampleRateHz',1e6, ...
    'Source',source,'PayloadSHA256',hash(bytes));
end
function h=hash(x)
h=sixgr.protocol.ProtocolHash.bytes(x);
end
function reject(fn)
try,fn();catch ex,assert(startsWith(string(ex.identifier),"sixgr:rlc:ARQ"));return;end
error('test:ARQGuard','Expected strict original-state rejection.');
end

function a=initial(a,data,si,sample,id)
% Declared preview token boundary here. Integration must use actual entity token.
t=struct('Owner',"declared_test_rlc_owner",'Revision',0,'ID',"preview_"+id);
pdu=uint8([sixgr.l2.rlc18.RLCHeaderCodec.encodeAM(12,1,1,si,4095,[]) data]);
p=a.previewData(4095,pdu,t);r=receipt(id,sample,"actual_MAC_lower_layer_submission",pdu);r.OriginalToken=t;
bad=r;bad.OriginalToken.ID="foreign";reject(@()a.commitData(p,bad));
bad=r;bad.PayloadSHA256=hash(uint8([pdu 0]));reject(@()a.commitData(p,bad));
assert(isequaln(p,a.previewData(4095,pdu,t))); % Withheld initial preview preserves ownership.
a=a.commitData(p,r);
end
