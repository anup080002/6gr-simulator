function ok = testMsg3HARQLDPCPolicy()
% Actual encoded UL-SCH LLRs through the Msg3 HARQ diagnostic owner.
% This is a same-TB RV0/RV2 codec fixture, not received RAR, waveform, MAC
% feedback or scheduler qualification. The existing CurrentDecodeOK TX-bit
% comparison remains a diagnostic and is not promoted to receiver policy.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
originalRNG=rng;
restore=onCleanup(@()rng(originalRNG)); %#ok<NASGU>
f=localFixture(false);
rows=repmat(struct('Case',"",'Passed',false,'ErrorID',"",'Detail',""),0,1);
for algorithm=["Belief propagation","Layered belief propagation", ...
        "Normalized min-sum","Offset min-sum"]
    for termination=["early","max"]
        for batch=[false true]
            policy=struct('algorithm',char(algorithm),'scalingFactor',.61, ...
                'minSumOffset',.31,'termination',char(termination), ...
                'maxIterations',4,'useMexBatchDecode',batch);
            record(algorithm+"/"+termination+"/batch="+string(batch), ...
                @()localPolicyCase(f,policy));
        end
    end
end
record("TB_CRC_distinct_from_complete_syndrome",@localBadCRC);
record("existing_current_TX_bit_diagnostic_preserved",@()localCurrentDiagnostic(f));
record("absent_LLR_has_no_decoder_receipt",@()localAbsentLLR(f));
checks=struct2table(rows);
for k=find(~checks.Passed).'
    fprintf(2,'MSG3_HARQ_LDPC_POLICY %s FAIL %s %s\n', ...
        checks.Case(k),checks.ErrorID(k),checks.Detail(k));
end
assert(all(checks.Passed),'test:Msg3HARQLDPCPolicy', ...
    '%d/%d Msg3 codec policy groups failed.',nnz(~checks.Passed),height(checks));
assert(isequaln(originalRNG,rng),'The codec policy checks unexpectedly consumed RNG.');
fprintf(['MSG3_HARQ_LDPC_POLICY_PASS groups=%d actual_encoded_ULSCH=1 ' ...
    'same_TB_RV0_RV2=1 complete_parity=1 waveform=0 MAC_retry=0\n'],height(checks));
ok=true;

    function record(name,fn)
        row=struct('Case',name,'Passed',false,'ErrorID',"",'Detail',"");
        try
            fn(); row.Passed=true;
        catch cause
            row.ErrorID=string(cause.identifier);
            row.Detail=string(getReport(cause,'extended','hyperlinks','off'));
        end
        rows(end+1,1)=row; %#ok<AGROW>
    end
end

function f=localFixture(badCRC)
f.A=256; f.Rate=.3; f.G=1200; f.RV=[0 2];
f.Bits=int8(mod((1:f.A).'+floor((1:f.A).'/7),2));
f.PUSCH=nrPUSCHConfig('NumLayers',1,'Modulation','QPSK');
sch=nrULSCHInfo(f.A,f.Rate);
withCRC=nrCRCEncode(f.Bits,sch.CRC);
if badCRC, withCRC(end)=1-withCRC(end); end
coded=nrLDPCEncode(nrCodeBlockSegmentLDPC(withCRC,sch.BGN),sch.BGN);
f.Layout=cell(1,2); f.LLR=cell(1,2); f.Recovered=cell(1,2);
for k=1:2
    bits=nrRateMatchLDPC(coded,f.G,f.RV(k),'QPSK',1);
    n=(1:f.G).';
    f.LLR{k}=1.1*(1-2*double(bits))+1.8*cos(.617*n+k)+sin(.217*n);
    if badCRC, f.LLR{k}=30*(1-2*double(bits)); end
    f.Layout{k}=sixgr.phy.phycode.resolveCodingLayout('Direction','UL', ...
        'TransportBlockSize',f.A,'TargetCodeRate',f.Rate,'RV',f.RV(k), ...
        'Modulation','QPSK','NumLayers',1,'RateMatchedBitCount',f.G);
    f.Recovered{k}=nrRateRecoverLDPC(f.LLR{k},f.A,f.Rate,f.RV(k),'QPSK',1);
end
assert(string(f.Layout{1}.CombineSignature)==string(f.Layout{2}.CombineSignature) && ...
    string(f.Layout{1}.RateMatchSignature)~=string(f.Layout{2}.RateMatchSignature));
end

function localPolicyCase(f,policy)
cfg=struct('phy',struct('ldpc',policy));
prior=[];
for k=1:2
    [tx,rx]=localOriginalCodecOperands(f,k,policy);
    originalTx=tx; originalRx=rx;
    d=sixgr.link.evaluateHARQDecode(tx,rx,cfg,prior);
    expected=f.Recovered{k};
    stage="initial_decode";
    if k==2
        expected=f.Recovered{1}+f.Recovered{2};
        stage="harq_combined_decode";
    end
    reference=localNative(expected,rx.CodingLayout,policy);
    assert(isequaln(d.RateRecoveredLLR,f.Recovered{k})&& ...
        isequaln(d.CombinedLLR,expected)&&d.HARQSoftCombiningApplied==(k==2));
    assert(isequaln(tx,originalTx)&&isequaln(rx,originalRx), ...
        'The HARQ diagnostic must not modify original codec operands.');
    localCompare(d,reference,policy,stage);
    expectedCurrent=rx.Ok && isequal(rx.TransportBlock,f.Bits);
    assert(d.CurrentDecodeOK==expectedCurrent&& ...
        d.BitErrors==nnz(rx.TransportBlock~=f.Bits)&&d.BitsCompared==f.A);
    assert(isequaln(d.CodingLayout,rx.CodingLayout));
    prior=d.HARQSoftBuffer;
end
end

function [tx,rx]=localOriginalCodecOperands(f,k,policy)
decoded=sixgr.phy.ul.pusch.decodeResolvedULSCH(f.LLR(k),true,f.PUSCH, ...
    f.A,f.Rate,f.RV(k),f.Layout(k),4,policy.algorithm,[],[],policy);
e=decoded.CodewordEvidence{1};
% Retain the actual receiver layout and actual decoder result. Native rate
% recovery independently supplies the same original mother-code LLR operand.
rx=struct('RecLLR',f.Recovered{k},'CodingLayout',e.CodingLayout, ...
    'TransportBlock',decoded.TransportBlocks{1},'Ok',decoded.AllTransportBlocksPassed, ...
    'ActiveIterations',e.ActualIterations,'CodeBlockCRCError',e.CodeBlockCRCError, ...
    'CRCError',decoded.CRCError,'NumCodeBlocks',e.CodingLayout.NumCodeBlocks);
tx=struct('TransportBlock',f.Bits,'CodingLayout',f.Layout{k}, ...
    'NumCodeBlocks',f.Layout{k}.NumCodeBlocks);
assert(isequaln(e.HARQCombining.SoftBuffer.LLR,f.Recovered{k}));
end

function r=localNative(llr,layout,p)
args={'Algorithm',p.algorithm,'Termination',p.termination};
if strcmp(p.algorithm,'Normalized min-sum'), args=[args,{'ScalingFactor',p.scalingFactor}]; end
if strcmp(p.algorithm,'Offset min-sum'), args=[args,{'Offset',p.minSumOffset}]; end
[decoded,iterations,parity]=nrLDPCDecode(llr,double(layout.BaseGraph),4,args{:});
[withCRC,cbError]=nrCodeBlockDesegmentLDPC(decoded,double(layout.BaseGraph),double(layout.B));
[bits,crcError]=nrCRCDecode(withCRC,char(layout.TBCRCType));
r=struct('Bits',int8(bits(:)),'Iterations',iterations,'Parity',parity, ...
    'CRCError',logical(crcError),'CodeBlockCRCError',cbError);
end

function localCompare(d,r,p,stage)
assert(d.CombinedDecodeOK==~r.CRCError&& ...
    d.CombinedDecoderIterations==mean(double(r.Iterations),'all')&& ...
    isequal(d.CombinedFinalParityChecks,r.Parity));
receipt=d.CombinedLDPCPolicyReceipt;
assert(receipt.AppliedAlgorithm==string(p.algorithm)&& ...
    receipt.AppliedTermination==string(p.termination)&& ...
    receipt.ConfiguredScalingFactor==p.scalingFactor&&receipt.ConfiguredOffset==p.minSumOffset&& ...
    receipt.MaximumIterations==4&&~receipt.MEXApplied&&~receipt.AlgorithmSubstitutionApplied&& ...
    ~receipt.RetryApplied&&receipt.AccelerationRequested==p.useMexBatchDecode&& ...
    isequal(receipt.ActualIterationsPerCodeBlock(:),double(r.Iterations(:)))&& ...
    isequal(receipt.FinalParityCheckShape,double(size(r.Parity)))&& ...
    isequal(receipt.UnsatisfiedParityChecksPerCodeBlock,sum(r.Parity~=0,1))&& ...
    isequal(receipt.AllParityChecksSatisfiedPerCodeBlock,all(r.Parity==0,1)));
if p.useMexBatchDecode
    assert(receipt.DecoderEngine=="sixgr_ldpc_decode_batch_kernel_v2_MATLAB");
else
    assert(receipt.DecoderEngine=="nrLDPCDecode");
end
if strcmp(p.algorithm,'Normalized min-sum')
    assert(receipt.AppliedScalingFactor==p.scalingFactor&&isnan(receipt.AppliedOffset));
elseif strcmp(p.algorithm,'Offset min-sum')
    assert(receipt.AppliedOffset==p.minSumOffset&&isnan(receipt.AppliedScalingFactor));
else
    assert(isnan(receipt.AppliedScalingFactor)&&isnan(receipt.AppliedOffset));
end
if strcmp(p.termination,'max'), assert(all(r.Iterations==4,'all')); end
e=d.CombinedLDPCParityEvidence;
assert(e.Available&&e.Stage==stage&&e.CodeBlockCount==size(r.Parity,2)&& ...
    e.CheckCount==numel(r.Parity)&&e.UnsatisfiedCheckCount==nnz(r.Parity)&& ...
    isequal(e.FinalParityChecksPerCodeword,{r.Parity}));
end

function localBadCRC()
f=localFixture(true); p=localPolicy();
[tx,rx]=localOriginalCodecOperands(f,1,p);
d=sixgr.link.evaluateHARQDecode(tx,rx,struct('phy',struct('ldpc',p)),[]);
r=localNative(f.Recovered{1},rx.CodingLayout,p);
localCompare(d,r,p,"initial_decode");
assert(r.CRCError&&~d.CurrentDecodeOK&&~d.CombinedDecodeOK&& ...
    all(r.Parity==0,'all')&&isequal(r.Bits,f.Bits), ...
    'TB-CRC failure must not be replaced by an all-satisfied LDPC syndrome.');
end

function localCurrentDiagnostic(f)
p=localPolicy(); cfg=struct('phy',struct('ldpc',p));
[tx,rx]=localOriginalCodecOperands(f,1,p);
original=sixgr.link.evaluateHARQDecode(tx,rx,cfg,[]);
% Deliberately inconsistent TX comparison metadata ONLY: the old diagnostic
% must reject current-bit equality, while combined receiver CRC is unchanged.
tx.TransportBlock=1-rx.TransportBlock;
changed=sixgr.link.evaluateHARQDecode(tx,rx,cfg,[]);
assert(~changed.CurrentDecodeOK&&changed.BitErrors==f.A&& ...
    changed.CombinedDecodeOK==original.CombinedDecodeOK&& ...
    isequal(changed.CombinedFinalParityChecks,original.CombinedFinalParityChecks)&& ...
    isequaln(changed.CombinedLDPCPolicyReceipt,original.CombinedLDPCPolicyReceipt));
end

function localAbsentLLR(f)
p=localPolicy();
[tx,rx]=localOriginalCodecOperands(f,1,p);
rx.RecLLR=[];
d=sixgr.link.evaluateHARQDecode(tx,rx,struct('phy',struct('ldpc',p)),[]);
assert(~d.CombinedDecodeOK&&isnan(d.CombinedDecoderIterations)&& ...
    isempty(fieldnames(d.CombinedLDPCPolicyReceipt))&&isempty(d.CombinedFinalParityChecks)&& ...
    ~d.CombinedLDPCParityEvidence.Available&&~d.CombinedLDPCParityEvidence.HasObservedCodewords&& ...
    isnan(d.CombinedLDPCParityEvidence.CheckCount), ...
    'An absent decoder input must not create a policy or all-passed parity receipt.');
end

function p=localPolicy()
p=struct('algorithm','Normalized min-sum','scalingFactor',.61, ...
    'minSumOffset',.31,'termination','max','maxIterations',4,'useMexBatchDecode',true);
end
