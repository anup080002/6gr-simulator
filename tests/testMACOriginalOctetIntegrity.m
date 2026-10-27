function ok=testMACOriginalOctetIntegrity()
% Bounded API input integrity; no NR over-air R-bit discard requirement.
for value={NaN,Inf,-1,256,1.5,complex(1,1),true,'a'}
    bad=value{1}; rejects(@()sixgr.l2.mac.MACSubheaderCodec.decode('UL',bad));
    rejects(@()sixgr.l2.mac.MACPDUDemultiplexer.decode('UL',bad));
    item=struct('LCID',52,'Payload',bad,'OwnerID',"CCCH");
    rejects(@()sixgr.l2.mac.MACPDUAssembler.assemble('UL',item,16));
end
% Six original CCCH48 bytes are preserved exactly through fixed header.
item=struct('LCID',52,'Payload',double([0 1 127 128 254 255]),'OwnerID',"CCCH48");
p=sixgr.l2.mac.MACPDUAssembler.assemble('UL',item,12);
r=sixgr.l2.mac.MACPDUDemultiplexer.decode('UL',double(p.Bytes));
assert(r.SubPDUs.LCID==52 && isequal(r.SubPDUs.Payload,uint8(item.Payload)) && r.PaddingBytes==5);
% Padding is validated as original octets even though no payload is parsed.
assert(sixgr.l2.mac.MACPDUDemultiplexer.decode('UL',uint8([63 0 255])).PaddingBytes==3);
rejects(@()sixgr.l2.mac.MACPDUDemultiplexer.decode('UL',[63 NaN]));
rejects(@()sixgr.l2.mac.MACPDUDemultiplexer.decode('UL',[63 256]));
% The supported decoder keeps its existing reserved-bit interpretation.
a=sixgr.l2.mac.MACPDUDemultiplexer.decode('UL',uint8([52 1:6]));
b=sixgr.l2.mac.MACPDUDemultiplexer.decode('UL',uint8([180 1:6]));
assert(isequal(a.SubPDUs.Payload,b.SubPDUs.Payload));
for n={NaN,-1,0,1.5,complex(12,1)}
    rejects(@()sixgr.l2.mac.MACPDUAssembler.assemble('UL',item,n{1}));
end
ok=true;
end
function rejects(f)
thrown=false; try, f(); catch, thrown=true; end
assert(thrown,'Malformed original octets/count must be rejected before conversion.');
end
