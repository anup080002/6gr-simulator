function ok=testQueuedWaveformProtocolBridge()
% Authored original decoded-byte boundary; no waveform/RF claim.
c=struct('enabled',true,'strict',true,'configuration_epoch',1);
c.rlc=struct('sn_bits',18,'poll_pdu',16,'poll_byte',65536,'max_retx_threshold',8);
c.pdcp=struct('sn_bits',18,'cipher_algorithm','NEA0','integrity_algorithm','NIA0','t_reordering_ms',50);
c.sdap=struct('pdu_session_id',1,'qfi_to_drb',struct('qfi',9,'drb_id',1));
c.mac=struct('lcid',4); c.traffic.sessions=struct('flow_id','data-1','pdu_session_id',1,'qfi',9,'direction','BIDIR');
b=sixgr.protocol.WaveformProtocolBridge(c,1); original=uint8(1:35);
b.enqueuePacket(1,'UL','UL_original_packet_1',original,0);
assert(b.pendingTransmitBytes(1,'UL').TotalBSRBytes==39);
bits={}; ids=strings(0,1); counts=[];
while b.pendingTransmitBytes(1,'UL').TotalBSRBytes>0
    k=numel(bits)+1; id="queued-tb-"+k;
    [wire,e]=b.prepareQueuedSegment(1,'UL',id,160,k*.001,5);
    private=b.originalTransportApplicationBinding(id);
    assert(islogical(private.ControlOnly)&&~private.ControlOnly&&private.TransportKind=="RLC_DATA"&& ...
        private.ApplicationPayloadBytes==e.PayloadBits/8&&private.MACSHA256==e.MACSHA256);
    b.commitPreparedTransportBlock(id,k*.001);
    bits{k}=wire; ids(k,1)=id; counts(k,1)=e.PayloadBits/8; %#ok<AGROW>
end
assert(numel(bits)>1 && sum(counts)==numel(original));
for k=numel(bits):-1:1
    [delivered,e]=b.deliverDecoded(ids(k),bits{k},.1+(numel(bits)-k)*.001);
    if k>1, assert(~delivered && isempty(e.CompletedTransportBlocks));
    else, assert(delivered && numel(e.CompletedTransportBlocks)==numel(bits)); end
end
[received,hash]=b.reassembleDecodedApplication(ids,counts);
assert(isequal(received,original) && hash==sixgr.protocol.ProtocolHash.bytes(original));
assert(b.pendingTransmitBytes(1,'UL').TotalBSRBytes==0);
% Packet names are bearer-scoped, and preview/cancellation cannot debit BSR.
scoped=sixgr.protocol.WaveformProtocolBridge(c,2);
scoped.enqueuePacket(1,'UL','same-name',uint8(1:8),0);
scoped.enqueuePacket(2,'UL','same-name',uint8(21:28),0);
scoped.enqueuePacket(1,'DL','same-name',uint8(41:48),0);
before=scoped.pendingTransmitBytes(1,'UL');
[~,first]=scoped.prepareQueuedSegment(1,'UL','cancelled',160,.001,0);
assert(isequal(scoped.pendingTransmitBytes(1,'UL'),before));
assert(scoped.hasUncommittedTransport(1,'UL'));
try
    scoped.prepareQueuedSegment(1,'UL','competing',160,.001,0);
    error('test:ExpectedPending','Competing head preview must be deferred.');
catch ex
    assert(strcmp(ex.identifier,'sixgr:protocol:PendingOriginalMACTransmission'));
end
scoped.cancelPreparedTransportBlock('cancelled');
assert(~scoped.hasUncommittedTransport(1,'UL'));
[~,again]=scoped.prepareQueuedSegment(1,'UL','reprepared',160,.002,0);
assert(first.PayloadSHA256==again.PayloadSHA256 && isequal(scoped.pendingTransmitBytes(1,'UL'),before));
[~,otherUE]=scoped.prepareQueuedSegment(2,'UL','other-ue',160,.002,0);
[~,otherDirection]=scoped.prepareQueuedSegment(1,'DL','other-direction',160,.002,0);
assert(otherUE.PayloadSHA256==sixgr.protocol.ProtocolHash.bytes(uint8(21:28)));
assert(otherDirection.PayloadSHA256==sixgr.protocol.ProtocolHash.bytes(uint8(41:48)));
scoped.validatePreparedTransportBlock('reprepared',.002);
scoped.commitPreparedTransportBlock('reprepared',.002);
assert(scoped.pendingTransmitBytes(1,'UL').TotalBSRBytes==0);
ok=true;
end
