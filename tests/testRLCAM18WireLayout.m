function ok=testRLCAM18WireLayout()
% Literal octets independently read from TS38.322 V18.2.0 Fig6.2.2.4-2/-4.
vectors={0,0,0,[],uint8([128 0 0]); ...
    0,0,1,[],uint8([128 0 1]); ...
    1,0,262143,[],uint8([195 255 255]); ...
    1,2,74565,32,uint8([225 35 69 0 32])};
for k=1:size(vectors,1)
    v=vectors(k,:); b=sixgr.l2.rlc18.RLCHeaderCodec.encodeAM(18,1,v{1},v{2},v{3},v{4});
    assert(isequal(b,v{5}));
    d=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM([v{5} uint8(42)],18);
    assert(d.SN==v{3} && d.Poll==v{1} && d.SI==v{2} && isequal(d.SO,v{4}) && d.Payload==42);
end
for reserved=[4 8 12]
    d=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(uint8([128+reserved 0 1 42]),18);
    assert(d.SN==1 && d.Payload==42,'TS38.322 6.2.3.8 requires RX to ignore R.');
end
% Last-octet low bits are sequence bits; each must be preserved.
for sn=0:7
    d=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(uint8([128 0 sn 42]),18);
    assert(d.SN==sn);
end
ok=true;
end
