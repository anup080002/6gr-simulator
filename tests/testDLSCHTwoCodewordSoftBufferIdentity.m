function ok=testDLSCHTwoCodewordSoftBufferIdentity()
% Canonical active DL codec on actual encoded declared LLRs, not RF/MAC.
% Explicit same-TB RV0/RV2 boundary invocation, not retransmission after ACK.
setup6GRSimToolkit('Verbose',false);
A=512; rate=.3; layers=3; modulation='QPSK'; G=3600;
bits={int8(mod((1:A).',2)),int8(mod(floor((1:A).'/3),2))};
[plans0,llr0]=localEncode(bits,A,rate,layers,modulation,G,0);
[plans2,llr2]=localEncode(bits,A,rate,layers,modulation,G,2);
initial=sixgr.pdsch.DLSCHDecoder(llr0,'CodingPlan',plans0,'MaxIterations',25);
current=sixgr.pdsch.DLSCHDecoder(llr2,'CodingPlan',plans2,'MaxIterations',25);
combined=sixgr.pdsch.DLSCHDecoder(llr2,'CodingPlan',plans2, ...
    'PriorRecoveredLLR',initial,'PriorCodingPlan',plans0,'MaxIterations',25);
assert(initial.CRCPass && combined.CRCPass && isequal(combined.TransportBlocks,bits));
prior=cellfun(@(e)e.SoftBuffer,initial.Codewords,'UniformOutput',false);
assert(isequal(size(prior{1}.LLRSum),size(prior{2}.LLRSum)) && ...
    string(prior{1}.CodingLayoutHash)==string(prior{2}.CodingLayoutHash));
sch=nrDLSCHInfo(A,rate);
for cw=1:2
    e=combined.Codewords{cw};
    expected=nrRateRecoverLDPC(llr0{cw},A,rate,0,modulation,layers)+ ...
        nrRateRecoverLDPC(llr2{cw},A,rate,2,modulation,layers);
    assert(e.CodewordIndex==cw-1 && e.SoftBuffer.CodewordIndex==cw && ...
        e.HARQCombineInfo.Applied && e.HARQCombineInfo.PositionAware);
    assert(isequaln(e.HARQCombinedLLR,expected) && ...
        isequaln(e.RateRecoveredLLR,current.Codewords{cw}.RateRecoveredLLR));
    decoded=nrLDPCDecode(expected,sch.BGN,25,'Algorithm','Normalized min-sum');
    withCRC=nrCodeBlockDesegmentLDPC(decoded,sch.BGN,A+sch.L);
    [reference,err]=nrCRCDecode(withCRC,sch.CRC);
    assert(err==0 && isequal(int8(reference(:)),e.TransportBlock));
end
localReject(@()sixgr.pdsch.DLSCHDecoder(llr2,'CodingPlan',plans2, ...
    'PriorRecoveredLLR',prior([2 1]),'PriorCodingPlan',plans0), ...
    'sixgr:phy:harq:SoftBufferCodewordMismatch');
% The no-current-observation retention branch must not transplant a buffer.
localReject(@()sixgr.phy.harq.combineSoftLLR([],prior{2},'CodewordIndex',1), ...
    'sixgr:phy:harq:SoftBufferCodewordMismatch');
missing=prior; missing{2}=rmfield(missing{2},'CodewordIndex');
localReject(@()sixgr.pdsch.DLSCHDecoder(llr2,'CodingPlan',plans2, ...
    'PriorRecoveredLLR',missing,'PriorCodingPlan',plans0), ...
    'sixgr:phy:harq:SoftBufferCodewordMismatch');
% Nested aggregate selection must not bypass the same canonical identity.
swapped=initial; swapped.Codewords=swapped.Codewords([2 1]);
localReject(@()sixgr.pdsch.DLSCHDecoder(llr2,'CodingPlan',plans2, ...
    'PriorRecoveredLLR',swapped,'PriorCodingPlan',plans0), ...
    'sixgr:phy:harq:SoftBufferCodewordMismatch');
single=sixgr.pdsch.DLSCHDecoder(llr2{1},'CodingPlan',plans2{1}, ...
    'PriorRecoveredLLR',prior{1},'PriorCodingPlan',plans0{1},'MaxIterations',25);
assert(single.CRCPass && single.SoftBuffer.CodewordIndex==1 && ...
    isequal(single.TransportBlock,bits{1}));
% Preserve the existing layout-incompatibility contract: reset only that CW.
foreign=prior; foreign{2}.CodingLayoutHash='different-layout';
reset=sixgr.pdsch.DLSCHDecoder(llr2,'CodingPlan',plans2, ...
    'PriorRecoveredLLR',foreign,'PriorCodingPlan',plans0,'MaxIterations',25);
assert(reset.Codewords{1}.HARQCombineInfo.Applied && ...
    ~reset.Codewords{2}.HARQCombineInfo.Applied && reset.Codewords{2}.HARQCombineInfo.ResetPrior && ...
    isequaln(reset.Codewords{2}.HARQCombinedLLR,current.Codewords{2}.HARQCombinedLLR));
ok=true; fprintf('DLSCH_TWO_CW_SOFT_BUFFER_IDENTITY_PASS scope=declared_LLR_same_TB_boundary\n');
end

function [plans,llr]=localEncode(bits,A,rate,layers,modulation,G,rv)
plans=cell(1,2); llr=cell(1,2); sch=nrDLSCHInfo(A,rate);
for cw=1:2
    plans{cw}=sixgr.pdsch.DLSCHCodingPlan.resolve('TransportBlockSize',A, ...
        'TargetCodeRate',rate,'RV',rv,'Modulation',modulation, ...
        'NumLayers',layers,'RateMatchedBitCount',G,'CodewordIndex',cw-1);
    withCRC=nrCRCEncode(bits{cw},sch.CRC);
    segmented=nrCodeBlockSegmentLDPC(withCRC,sch.BGN);
    coded=nrLDPCEncode(segmented,sch.BGN);
    matched=nrRateMatchLDPC(coded,G,rv,modulation,layers);
    llr{cw}=20*(1-2*double(matched));
end
end

function localReject(fn,id)
try, fn(); catch err
    assert(strcmp(err.identifier,id),'Expected %s, got %s: %s',id,err.identifier,err.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
