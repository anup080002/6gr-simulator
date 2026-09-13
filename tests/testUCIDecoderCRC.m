function ok=testUCIDecoderCRC()
% Actual native decoding is the CRC authority, not expected payload equality.
setup6GRSimToolkit('Verbose',false);
failedBlocksExercised=0;
for A=[1 2 3 11 12 19 20 359 360 1013 1706]
    E=max(96,4*A); payload=int8(mod((1:A).',2));
    coded=nrUCIEncode(payload,E); coded(coded==-1)=1;
    for k=find(coded==-2).', coded(k)=coded(k-1); end
    llr=12*(1-2*double(coded));
    [nativeBits,nativeErrors]=nrUCIDecode(llr,A);
    actual=sixgr.phy.pucch.UCIDecoder.decode(llr,A);
    assert(isequal(actual.Bits,nativeBits) && isequal(actual.Bits,payload) && actual.CRCPassed);
    assert(actual.CRCApplicable==(A>=12));
    if A<12
        assert(isempty(actual.CodeBlockCRCError) && actual.CRCStatus=="not_applicable");
        continue;
    end
    assert(isequal(actual.CodeBlockCRCError,logical(nativeErrors(:))));
    stream=RandStream('mt19937ar','Seed',12000+A);
    corrupted=randn(stream,E,1);
    [nativeBits,nativeErrors]=nrUCIDecode(corrupted,A);
    actual=sixgr.phy.pucch.UCIDecoder.decode(corrupted,A);
    assert(isequal(actual.Bits,nativeBits) && ...
        isequal(actual.CodeBlockCRCError,logical(nativeErrors(:))) && ...
        numel(actual.CodeBlockCRCError)==actual.Plan.CodeBlocks && ...
        actual.CRCPassed==~any(nativeErrors(:)));
    if any(nativeErrors(:)), assert(actual.FailureReason=="uci_crc_failed"); end
    failedBlocksExercised=failedBlocksExercised+nnz(nativeErrors);
end
assert(failedBlocksExercised>0,'test:CRCFailureNotExercised','Exercise actual failed code blocks.');
empty=sixgr.phy.pucch.UCIDecoder.decode(zeros(0,1),0);
assert(~empty.CRCApplicable && isempty(empty.Bits) && isempty(empty.CodeBlockCRCError));
fprintf('UCI_CRC_NATIVE_AUTHORITY_PASS coding_cases=11 failed_codeblocks_exercised=%d\n',failedBlocksExercised);
ok=true;
end
