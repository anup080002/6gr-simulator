function ok=testQueuedProtocolSegmentation()
setup6GRSimToolkit('Verbose',false);
c=struct('UEID',"UE-001",'BearerID',"DRB-1",'QFI',9,'DRBID',1, ...
    'PduSessionID',1,'LCID',4,'PDCPSNBits',18,'RLCSNBits',18, ...
    'ConfigurationEpoch',1,'Direction',"UL",'ReorderingTime_s',.05);
r=sixgr.protocol.ProtocolRuntime(c); payload=uint8(1:35);
record=r.enqueuePacket("whole-packet",payload,0);
assert(record.PacketBytes==35 && r.pendingTransmitBytes().TotalBSRBytes==39);
r.enqueuePacket("whole-packet",payload,.001);
assert(r.pendingTransmitBytes().TotalBSRBytes==39 && r.PacketsTransmitted==1);
parts={}; totalApp=0; previous=39;
while r.pendingTransmitBytes().TotalBSRBytes>0
    p=r.prepareSegment(19,.002);
    assert(numel(p.Bytes)<=19 && p.SegmentPayloadBytes+p.RLCHeaderBytes==numel(p.Bytes));
    assert(p.ApplicationOffsetBytes==totalApp);
    totalApp=totalApp+p.ApplicationPayloadBytes;
    next=r.pendingTransmitBytes().TotalBSRBytes;
    assert(previous-next==p.SegmentPayloadBytes);
    previous=next;
    mac=sixgr.l2.mac.MACPDUAssembler.assemble('UL', ...
        struct('LCID',4,'Payload',p.Bytes,'OwnerID',"segment"),32);
    p.MACBytes=mac.Bytes; p.MACSHA256=mac.SHA256; parts{end+1}=p; %#ok<AGROW>
end
assert(numel(parts)==3 && totalApp==35 && parts{end}.CompletedTxPacket);
assert(all(cellfun(@(p)p.PDCPCount==0 && p.RLCSN==0,parts)), ...
    'All grant segments must preserve one original PDCP and RLC SDU identity.');
for k=numel(parts):-1:2
    [delivered,completed]=r.receive(parts{k},.003+(numel(parts)-k)*.001);
    assert(~delivered && isempty(completed));
end
[delivered,completed]=r.receive(parts{1},.006);
assert(delivered && numel(completed)==1 && isequal(completed.Payload,payload));
assert(completed.PacketID=="whole-packet" && r.PacketsDelivered==1);
assert(~r.receive(parts{end},.007) && r.PacketsDelivered==1);

% Actual overlap resegmentation: only previously missing bytes are added.
base=struct('UEID',"UE-1",'BearerID',"DRB-1",'Direction',"UL",'ConfigurationEpoch',1,'SNBits',18);
rx=sixgr.l2.rlc18.RLCAMEntity(base); original=uint8(1:32);
last=[sixgr.l2.rlc18.RLCHeaderCodec.encodeAM(18,1,0,2,0,20) original(21:32)];
first=[sixgr.l2.rlc18.RLCHeaderCodec.encodeAM(18,1,0,1,0,[]) original(1:12)];
middle=[sixgr.l2.rlc18.RLCHeaderCodec.encodeAM(18,1,0,3,0,10) original(11:25)];
rx.receivePDU(last);rx.receivePDU(first); assert(isempty(rx.pullSDUs()));
rx.receivePDU(middle); got=rx.pullSDUs(); assert(isequal(got,{original}));
rx.receivePDU(last); assert(isempty(rx.pullSDUs()));
ok=true;
end
