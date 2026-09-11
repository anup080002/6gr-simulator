function ok=testMACFixedCEByteLayout()
% Independent TS 38.321 V18.5.0 Tables 6.2.1-1/2, clauses 6.1.2/6.1.3.
% Byte framing only: this does not certify CE field semantics or activation.
cases={"DL",47,2; "DL",48,2; "DL",52,2; "DL",57,4; ...
    "DL",58,1; "DL",59,0; "DL",60,0; "DL",61,1; "DL",62,6; ...
    "UL",0,8; "UL",52,6; "UL",44,2; "UL",55,0; ...
    "UL",57,2; "UL",58,2; "UL",59,1; "UL",61,1};
for k=1:size(cases,1)
    direction=cases{k,1}; lcid=cases{k,2}; count=cases{k,3};
    [schema,n,h]=sixgr.l2.mac.MACSubheaderCodec.decode(direction,uint8(lcid));
    assert(schema.SizeType=="fixed" && n==count && h==1, ...
        '%s LCID %d must own %d payload octets.',direction,lcid,count);
    assert(isequal(sixgr.l2.mac.MACSubheaderCodec.encode(direction,lcid,count),uint8(lcid)));
    localMustFail(@() sixgr.l2.mac.MACSubheaderCodec.encode(direction,lcid,count+1), ...
        "sixgr:mac:FixedMACPayloadLengthMismatch");
    if count>0
        localMustFail(@() sixgr.l2.mac.MACPDUDemultiplexer.decode(direction, ...
            uint8([lcid zeros(1,count-1)])),"sixgr:mac:MACPDULengthOverrun");
    end
end
% Independent byte strings include CE payloads that resemble MAC headers.
dl=uint8([61 31 52 0 63 62 1 2 3 4 5 6 1 3 170 187 204 63 0]);
ul=uint8([0 1 2 3 4 5 6 7 8 1 2 170 187 57 31 32 61 63 58 18 52 63 0]);
localRoundTrip("DL",dl,[61 52 62 1],[1 2 6 3],[0 2 5 12]);
localRoundTrip("UL",ul,[0 1 57 61 58],[8 2 2 1 2],[0 9 13 16 18]);
for invalid={NaN,Inf,-1,1.5,[1 2]}
    localMustFail(@() sixgr.l2.mac.MACSubheaderCodec.encode("UL",57,invalid{1}), ...
        "sixgr:mac:MACPDULengthOverrun");
end
ok=true;
fprintf('PASS testMACFixedCEByteLayout\n');
end

function localRoundTrip(direction,bytes,lcids,lengths,offsets)
decoded=sixgr.l2.mac.MACPDUDemultiplexer.decode(direction,bytes);
assert(isequal([decoded.SubPDUs.LCID],lcids));
assert(isequal([decoded.SubPDUs.PayloadLength],lengths));
assert(isequal([decoded.SubPDUs.HeaderOffset],offsets));
assert(decoded.PaddingBytes==2 && decoded.ConsumedBytes==numel(bytes));
items=struct('LCID',{},'Payload',{},'OwnerID',{});
for k=1:numel(lcids)
    items(k)=struct('LCID',lcids(k),'Payload',decoded.SubPDUs(k).Payload, ...
        'OwnerID',"byte_layout_fixture");
end
encoded=sixgr.l2.mac.MACPDUAssembler.assemble(direction,items,numel(bytes));
assert(isequal(encoded.Bytes,bytes),'Mixed CE/SDU byte ownership must round-trip exactly.');
end

function localMustFail(fn,id)
try
    fn();
catch ME
    assert(string(ME.identifier)==id,'%s: %s',ME.identifier,ME.message);
    return;
end
error('testMACFixedCEByteLayout:ExpectedFailure','Expected %s.',id);
end
