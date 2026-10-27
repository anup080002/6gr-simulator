function ok=testWaveformProtocolMACControlCoexistence()
% Authored byte-codec boundary; this is not a physical PUSCH receive test.
c=struct('enabled',true,'strict',true,'configuration_epoch',1);
c.rlc=struct('sn_bits',18,'poll_pdu',16,'poll_byte',65536,'max_retx_threshold',8);
c.pdcp=struct('sn_bits',18,'cipher_algorithm','NEA0','integrity_algorithm','NIA0');
c.sdap=struct('pdu_session_id',1,'qfi_to_drb',struct('qfi',9,'drb_id',1));
c.mac=struct('lcid',4); c.traffic.sessions=struct('flow_id','data-1', ...
    'pdu_session_id',1,'qfi',9,'direction','BIDIR');
b=sixgr.protocol.WaveformProtocolBridge(c,1);
ce(1)=struct('LCID',57,'Payload',sixgr.l2.mac.BSR_PHR.encodeSingleEntryPHR(-4,23,false),'OwnerID',"phr");
ce(2)=struct('LCID',61,'Payload',sixgr.l2.mac.BSR_PHR.encodeShortBSR(0,900),'OwnerID',"bsr");
reserved=5; n=b.maximumPayloadBytes(1024,reserved); payload=uint8(mod(1:n,251));
[bits,e]=b.encodeFragment(1,"UL","ce-tb","flow-UL-UE-001-fragment-1",payload,1024,.001,ce);
assert(numel(bits)==1024 && e.PayloadBits==8*n && e.MACControlSubPDUBytes==reserved);
assert(sum([e.MACSubPDUs.HeaderLength])+sum([e.MACSubPDUs.PayloadLength])+e.MACPaddingBytes==128);
bytes=uint8(double(reshape(bits,8,[]).')*(2.^(7:-1:0)).');
m=sixgr.l2.mac.MACPDUDemultiplexer.decode('UL',bytes);
assert(isequal([m.SubPDUs.LCID],[57 61 4]));
assert(isequal(m.SubPDUs(1).Payload(:),ce(1).Payload(:)) && isequal(m.SubPDUs(2).Payload(:),ce(2).Payload(:)));
[delivered,d]=b.deliverDecoded("ce-tb",bits,.002);
assert(delivered && d.DecodedMACSHA256==e.MACSHA256);
[again,~]=b.deliverDecoded("ce-tb",bits,.003); assert(~again);
% Oversized payload rejection must precede protocol SN/lineage mutation.
threw=false;
try
    b.encodeFragment(1,"UL","bad-capacity","flow-UL-UE-001-fragment-2",uint8(ones(1,n+1)),1024,.004,ce);
catch err
    threw=strcmp(err.identifier,'sixgr:protocol:MACPDUCapacityExceeded');
end
assert(threw);
ok=true;
end
