function ok=testProtocolRLCARQIntegration()
% Authored MAC-delivery clock boundary; no RF/BLER claim. Exact original
% AMD and reverse STATUS bytes drive timers and recovery, never local ACKs.
c=struct('UEID',"UE-001",'BearerID',"DRB-1",'QFI',9,'DRBID',1, ...
    'PduSessionID',1,'LCID',4,'PDCPSNBits',18,'RLCSNBits',18, ...
    'ConfigurationEpoch',1,'Direction',"UL",'RLCARQEnabled',true, ...
    'SampleRateHz',1000,'ClockEpoch',1,'RLCPollRetransmit_s',.045, ...
    'RLCReassembly_s',.035,'RLCStatusProhibit_s',0);
r=sixgr.protocol.ProtocolRuntime(c); original=uint8(1:35);
r.enqueuePacket("original-app",original,0); parts={};
for k=1:3
    [p,t]=r.previewSegment(19,k*.001);r.commitPreparedSegment(t,k*.001);
    parts{k}=bindMAC(p); %#ok<AGROW>
end
assert(r.pendingTransmitBytes().TotalBSRBytes==0);
% Only the last original segment reached MAC; missing bytes must be requested.
[delivered,completed]=r.receive(parts{3},.004);assert(~delivered&&isempty(completed));
r.advance(.039);assert(r.pendingReverseStatusBytes()>0);
status=r.prepareReverseStatus(128,.039);
report=sixgr.l2.rlc18.RLCStatusCodec.decodeReport(status.Bytes,18);
assert(report.ACKSN==1 && report.NACKs.NACKSN==0 && ...
    report.NACKs.SOstart==0 && report.NACKs.SOend==29);
assert(r.pendingTransmitBytes().AMRetransmissionBytes==0,'A local STATUS preparation cannot act as received feedback.');
r.commitReverseStatus(status,'actual-reverse-mac-1',.040);
r.receiveReverseStatus(status.Bytes,'decoded-reverse-mac-1',.041);
assert(r.pendingTransmitBytes().AMRetransmissionBytes==30 && r.pendingTransmitBytes().RLCPayloadBytes==0);
% A withheld retransmission leaves the exact original missing interval pending.
[p,t]=r.previewSegment(19,.042);r.cancelPreparedSegment(t);
assert(p.IsRLCRetransmission && r.pendingTransmitBytes().AMRetransmissionBytes==30);
for k=1:2
    txTime=.042+(k-1)*.002;
    [p,t]=r.previewSegment(19,txTime);
    assert(p.IsRLCRetransmission && p.PDCPCount==0 && p.RLCFullCount==0);
    r.commitPreparedSegment(t,txTime);
    [delivered,completed]=r.receive(bindMAC(p),txTime+.001);
end
assert(delivered && isequal(completed.Payload,original) && r.PacketsDelivered==1);
assert(r.pendingTransmitBytes().TotalBSRBytes==0);
ack=r.prepareReverseStatus(128,.046);
decoded=sixgr.l2.rlc18.RLCStatusCodec.decodeReport(ack.Bytes,18);
assert(decoded.ACKSN==1 && isempty(decoded.NACKs));
r.commitReverseStatus(ack,'actual-reverse-mac-2',.047);
r.receiveReverseStatus(ack.Bytes,'decoded-reverse-mac-2',.048);
r.advance(.100);assert(r.pendingTransmitBytes().AMRetransmissionBytes==0);
% Release stops old-bearer timers and cannot admit another packet under that owner.
released=sixgr.protocol.ProtocolRuntime(c);released.enqueuePacket("release-packet",uint8(1:8),0);
[p,t]=released.previewSegment(32,.001);released.commitPreparedSegment(t,.001);
assert(isfinite(released.nextTimerExpiry()));released.release(.002);
assert(isinf(released.nextTimerExpiry()) && released.pendingTransmitBytes().TotalBSRBytes==0);
assert(isempty(released.advance(.100)));
threw=false;try,released.enqueuePacket("after-release",uint8(1),.101);catch e,threw=contains(e.identifier,'ReleasedBearer');end
assert(threw);
ok=true;
end
function p=bindMAC(p)
m=sixgr.l2.mac.MACPDUAssembler.assemble('UL', ...
    struct('LCID',4,'Payload',p.Bytes,'OwnerID',"original-AMD"),32);
p.MACBytes=m.Bytes;p.MACSHA256=m.SHA256;
end
