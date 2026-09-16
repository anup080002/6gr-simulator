function ok=testUCICodingOverhead()
% TS 38.212 5.2.1 / 6.3.1.2 declared boundaries plus native-codec checks.
setup6GRSimToolkit('Verbose',false);
% A, E, CRC bits/block, block count, segmentation filler bits.
vectors=[0 0 0 1 0;1 8 0 1 0;2 8 0 1 0;3 32 0 1 0;11 32 0 1 0; ...
    12 64 6 1 0;19 96 6 1 0;20 96 11 1 0;359 1088 11 1 0; ...
    360 1087 11 1 0;360 1088 11 2 0;361 1088 11 2 1; ...
    1012 1087 11 1 0;1013 2048 11 2 1;1706 4096 11 2 0];
for row=vectors.'
    A=row(1); E=row(2);
    p=sixgr.phy.pucch.UCIEncodingPlan(A,E);
    assert(p.CRCBits==row(3) && p.CodeBlocks==row(4) && p.CodeBlockPaddingBits==row(5));
    assert(p.TotalCRCBits==row(3)*row(4));
    assert(p.InformationAndCRCBits==A+row(3)*row(4));
    assert(p.CodeBlockInputBits==A+row(3)*row(4)+row(5));
    if A==0, continue; end
    payload=int8(mod((1:A).',2)); encoded=nrUCIEncode(payload,E);
    encoded(encoded==-1)=1;
    for index=find(encoded==-2).', encoded(index)=encoded(index-1); end
    [decoded,crcErrors]=nrUCIDecode(20*(1-2*double(encoded)),A);
    assert(isequal(decoded,payload) && ~any(crcErrors(:)) && numel(encoded)==E);
    if A>=12
        blocks=reshape([zeros(row(5),1,'int8');payload],[],row(4));
        crcBlocks=nrCRCEncode(blocks,char(string(row(3))));
        assert(numel(crcBlocks)==p.CodeBlockInputBits && numel(crcErrors)==p.CodeBlocks);
    end
end
ok=true;
fprintf('UCI_CODING_OVERHEAD_PASS vectors=%d CRC_filler_separate=1 native_roundtrip=1\n',size(vectors,1));
end
