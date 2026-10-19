function ok = testLDPCAccountingEvidence()
% Coding-only regression: actual bit selection, not waveform performance.
rng(16016,'twister');
fixtures = [4104 26712 304 4616; 8976 57872 528 10400; 5000 32212 48 6660];
for f=1:size(fixtures,1)
    A=fixtures(f,1); G=fixtures(f,2);
    [tx,info,enc,cbs]=localFixture(A,0.15,G,0,[]);
    idx=double(info.RateMatch.PositionMap.MotherCodeLinearIndex);
    assert(isequal(enc(idx),tx.Codeword),'Recorded positions do not reproduce transmitted bits.');
    assert(all(enc(idx)>=0),'Filler positions must never be transmitted.');
    metrics=sixgr.link.deriveCodingTrialMetrics(tx,info,struct(),struct());
    assert(metrics.SegmentationPaddingBits==fixtures(f,3),'CB CRC is not filler.');
    assert(metrics.RateMatchRepetitionBits==fixtures(f,4),'Repetition must count repeated selections.');
    assert(metrics.EncodedBits==numel(enc),'EncodedBits is post-puncture encoder output, not G.');
    assert(metrics.CBCRCBits==24*size(cbs,2));
    assert(metrics.CodeBlockInputBits==tx.TransportBlockLenWithCRC+metrics.CBCRCBits+metrics.SegmentationPaddingBits);
end
% Both BGs, all RVs, short/repeated output, full/limited circular buffer.
cases=[384 .3; 8448 .48];
for c=1:size(cases,1)
    for rv=0:3
        for nref=[0 1000]
            for G=[400 50000]
                limit=[]; if nref>0, limit=nref; end
                [tx,info,enc]=localFixture(cases(c,1),cases(c,2),G,rv,limit);
                map=info.RateMatch.PositionMap;
                idx=double(map.MotherCodeLinearIndex);
                assert(isequal(enc(idx),tx.Codeword));
                assert(all(enc(idx)>=0));
                if nref>0, assert(all(double(map.MotherCodeBitIndex)<=nref)); end
                a=info.RateMatch.Accounting;
                assert(sum(a.SelectedPositions)==G);
                assert(all(a.UniqueSelectedPositions+a.RepeatedSelections==a.SelectedPositions));
                assert(all(a.UniqueSelectedPositions+a.UnselectedEligiblePositions==a.EligibleBufferPositions));
                assert(all(a.BufferPositions==a.EligibleBufferPositions+a.BufferFillerPositions));
            end
        end
    end
end
% Multiple codewords must aggregate real layouts, including unequal K/C.
[t1,i1]=localFixture(384,.3,3000,0,[]);
[t2,i2]=localFixture(4104,.15,26712,0,[]);
t=t1; t.CodingLayouts={t1.CodingLayout,t2.CodingLayout};
t.TransportBlockSizePerCodeword=[384 4104];
t.TransportBlockCRCLengthPerCodeword=[t1.TransportBlockCRCLength t2.TransportBlockCRCLength];
t.TransportBlockLenWithCRCPerCodeword=[t1.TransportBlockLenWithCRC t2.TransportBlockLenWithCRC];
t.GPerCodeword=[3000 26712];
i=i1; i.RateMatchPerCodeword={i1.RateMatch,i2.RateMatch};
m=sixgr.link.deriveCodingTrialMetrics(t,i,struct(),struct());
assert(m.CBCRCBits==48 && m.NumCodeBlocks==3);
assert(m.CodeBlockInputBits==sum(t.TransportBlockLenWithCRCPerCodeword)+m.CBCRCBits+m.SegmentationPaddingBits);
fprintf('LDPC accounting: 3 retained fixtures, 32 RV/buffer cases, mixed codewords PASS\n');
ok=true;
end

function [tx,info,enc,cbs]=localFixture(A,R,G,rv,nref)
sch=nrDLSCHInfo(A,R);
tb=int8(randi([0 1],A,1));
b=nrCRCEncode(tb,sch.CRC);
[cbs,seg]=sixgr.phy.tb.segmentLDPC(b,sch.BGN);
enc=nrLDPCEncode(cbs,sch.BGN);
[bits,rm]=sixgr.phy.phycode.rateMatchLDPC(enc,G,rv,'QPSK',1,nref);
layout=sixgr.phy.phycode.resolveCodingLayout('TransportBlockSize',A, ...
    'TargetCodeRate',R,'RateMatchedBitCount',G,'RV',rv,'Nref',nref);
tx=struct('TransportBlockSize',A,'TransportBlockCRCLength',sch.L, ...
    'TransportBlockLenWithCRC',numel(b),'BaseGraph',sch.BGN, ...
    'G',G,'Codeword',bits,'CodingLayout',layout,'CodingLayouts',{{layout}});
info=struct('Segmentation',seg,'RateMatch',rm);
end
