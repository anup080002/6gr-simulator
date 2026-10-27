function ok=testRLCReceivedSTATUSAtomicity()
% Declared original MAC-byte/sample-clock boundary; no physical CRC claim.
c=struct('UEID',"UE-001",'BearerID',"DRB-1",'QFI',9,'DRBID',1, ...
    'PduSessionID',1,'LCID',4,'PDCPSNBits',18,'RLCSNBits',18, ...
    'ConfigurationEpoch',1,'Direction',"UL",'RLCARQEnabled',true, ...
    'SampleRateHz',1000,'ClockEpoch',1,'RLCPollRetransmit_s',.045, ...
    'RLCReassembly_s',.035,'RLCStatusProhibit_s',0);
r=sixgr.protocol.ProtocolRuntime(c);r.enqueuePacket("original",uint8(1:10),0);
[~,t]=r.previewSegment(64,.001);r.commitPreparedSegment(t,.001);
before=r.pendingTransmitBytes();deadline=r.nextTimerExpiry();
% Even after the live poll deadline, malformed bytes cannot advance timers.
bad=uint8([128 0 0]);reject(@()r.previewReceivedStatus(bad,'bad',.050),"");
assert(isequaln(before,r.pendingTransmitBytes())&&deadline==r.nextTimerExpiry());
n=struct('NACKSN',0,'SOstart',[],'SOend',[],'NACKRange',[]);
s=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(18,1,n);
p=r.previewReceivedStatus(s.Bytes,'received-1',.050);
assert(isequaln(before,r.pendingTransmitBytes())&&deadline==r.nextTimerExpiry());
% A later original enqueue changes the ARQ owner; never overwrite it with
% an earlier preview, even when the received STATUS bytes remain identical.
r.enqueuePacket("tail",uint8(21:23),.002);
reject(@()r.validateReceivedStatus(p),'sixgr:rlc:StaleSTATUSAdmission');
r.cancelReceivedStatus(p);
p=r.previewReceivedStatus(s.Bytes,'received-1',.050);
q=r.previewReceivedStatus(s.Bytes,'received-2',.050);
r.validateReceivedStatus(p);r.commitReceivedStatus(p);
assert(r.pendingTransmitBytes().AMRetransmissionBytes>0&&r.pendingTransmitBytes().RLCPayloadBytes>0);
reject(@()r.commitReceivedStatus(q),'sixgr:rlc:StaleSTATUSAdmission');r.cancelReceivedStatus(q);
reject(@()r.commitReceivedStatus(p),'sixgr:rlc:StaleSTATUSAdmission');
ok=true;
end
function reject(f,id)
try,f();catch e,if strlength(id)>0,assert(string(e.identifier)==id,e.message);end;return;end
error('test:ExpectedRejectedSTATUS','Invalid or stale STATUS was admitted.');
end
