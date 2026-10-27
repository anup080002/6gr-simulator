function ok=testSRBProtocolRuntime()
% SRB1: actual RRC octets through PDCP12/MAC-I/RLCAM12/MAC LCID1.
for r=0:15
    d=sixgr.l2.pdcp18.PDCPHeaderCodec.decode('SRB',12,uint8([16*r 1 42]));
    assert(d.SN==1 && d.Payload==42); % RX must ignore R, not include it in SN.
end
for n=[12 18]
    mask=112; if n==18,mask=124;end
    h=sixgr.l2.pdcp18.PDCPHeaderCodec.encode('DRB',n,7);
    h(1)=bitor(h(1),uint8(mask));
    d=sixgr.l2.pdcp18.PDCPHeaderCodec.decode('DRB',n,[h uint8(42)]);
    assert(d.SN==7 && d.Payload==42);
end
c=struct('UEID',"UE-001",'BearerID',"SRB-1",'BearerType',"SRB", ...
    'SRBID',1,'QFI',0,'LCID',1,'PDCPSNBits',12,'RLCSNBits',12, ...
    'ConfigurationEpoch',1,'Direction',"UL");
r=sixgr.protocol.ProtocolRuntime(c); original=uint8([16 0 1 2 3 4 5 6 7 8]);
packet=r.enqueuePacket("SetupComplete",original,0);
assert(isempty(packet.SDAPHeader) && packet.RLCSDUBytes==16 && packet.ApplicationStartByte==2);
parts={};
while r.pendingTransmitBytes().TotalBSRBytes>0
    [p,t]=r.previewSegment(10,.001);r.commitPreparedSegment(t,.002);
    m=sixgr.l2.mac.MACPDUAssembler.assemble('UL', ...
        struct('LCID',1,'Payload',p.Bytes,'OwnerID',"srb"),24);
    p.MACBytes=m.Bytes;p.MACSHA256=m.SHA256;parts{end+1}=p; %#ok<AGROW>
end
assert(sum(cellfun(@(p)p.ApplicationPayloadBytes,parts))==numel(original));
encoded=uint8([]);
for k=1:numel(parts)
    d=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(parts{k}.Bytes,12);
    encoded=[encoded d.Payload]; %#ok<AGROW>
end
assert(isequal(encoded,[uint8([0 0]) original zeros(1,4,'uint8')]), ...
    'SRB has no SDAP header; pre-security MAC-I is four zero octets.');
for k=numel(parts):-1:1
    [delivered,completed]=r.receive(parts{k},.01+(numel(parts)-k)*.001);
    if k>1,assert(~delivered && isempty(completed));end
end
assert(delivered && isequal(completed.Payload,original) && r.PacketsDelivered==1);
% Security BEARER is the received/configured RB identity minus1, not LCID.
c.SecurityActive=true;c.CipherAlgorithm="NEA0";c.IntegrityAlgorithm="128-NIA2";
c.IntegrityKey=uint8(0:15);
secure=sixgr.protocol.ProtocolRuntime(c);
p=secure.transmit("secured-RRC",original,0);
d=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(p.Bytes,12);
tag=sixgr.l2.pdcp18.PDCPSecurity128.nia2(c.IntegrityKey,0,0,0, ...
    [uint8([0 0]) original],8*(2+numel(original)));
assert(isequal(d.Payload,[uint8([0 0]) original tag]));
[delivered,completed]=secure.receive(p,.01);
assert(delivered && isequal(completed.Payload,original));
ok=true;
end
