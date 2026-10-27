function ok=testProtocolTransmitCommit()
% Missing TX must leave original queues, sequence identities and bytes intact.
c=struct('UEID',"UE-001",'BearerID',"DRB-1",'QFI',9,'DRBID',1, ...
    'PduSessionID',1,'LCID',4,'PDCPSNBits',18,'RLCSNBits',18, ...
    'ConfigurationEpoch',1,'Direction',"UL");
r=sixgr.protocol.ProtocolRuntime(c); r.enqueuePacket("first",uint8(1:35),0);
[p,t]=r.previewSegment(19,.001); [again,stale]=r.previewSegment(19,.001);
assert(isequal(p.Bytes,again.Bytes) && r.pendingTransmitBytes().TotalBSRBytes==39);
assert(p.RLCSN==0 && p.SegmentOffset==0);
r.enqueuePacket("second",uint8(50:59),.002); % Tail arrival does not steal original head.
assert(r.pendingTransmitBytes().TotalBSRBytes==53);
tampered=t; tampered.Revision=t.Revision+1;
rejects(@()r.commitPreparedSegment(tampered,.003));
assert(r.pendingTransmitBytes().TotalBSRBytes==53);
committed=r.commitPreparedSegment(t,.003);
assert(isequal(committed.Bytes,p.Bytes) && r.pendingTransmitBytes().TotalBSRBytes==37);
rejects(@()r.commitPreparedSegment(t,.004));
rejects(@()r.commitPreparedSegment(stale,.004));
other=sixgr.protocol.ProtocolRuntime(c); other.enqueuePacket("first",uint8(1:35),0);
rejects(@()other.commitPreparedSegment(t,.004));
[next,token]=r.previewSegment(19,.004);
assert(next.SegmentOffset==16 && next.RLCSN==0 && next.PDCPCount==0);
rejects(@()r.commitPreparedSegment(token,.003));
assert(r.pendingTransmitBytes().TotalBSRBytes==37);
r.commitPreparedSegment(token,.005);
while true
    [next,token]=r.previewSegment(100,.006);
    if isempty(fieldnames(next)),break;end
    r.commitPreparedSegment(token,.006);
    if next.PacketID=="second", assert(next.RLCSN==1 && next.PDCPCount==1); end
end
assert(r.pendingTransmitBytes().TotalBSRBytes==0);
ok=true;
end
function rejects(f)
thrown=false; try,f();catch e,thrown=contains(e.identifier,'StaleTransmitPreparation');end
assert(thrown,'Expected rejection of changed/stale/duplicate preparation.');
end
