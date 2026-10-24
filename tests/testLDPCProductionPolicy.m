function ok=testLDPCProductionPolicy()
% Actual encoded-LLR codec integration, not waveform/MAC/BLER qualification.
% Native references share MATLAB's decoder kernel but independently perform
% recovery, the exact native policy call, desegmentation and TB-CRC. Retained
% RV0/RV2 combining here is a declared same-TB codec fixture, not a scheduled
% retransmission or received-feedback claim. No old MEX ABI is qualified.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
beforeRNG=rng; restore=onCleanup(@()rng(beforeRNG)); %#ok<NASGU>
fixture=localFixture();
algorithms=["Belief propagation","Layered belief propagation", ...
    "Normalized min-sum","Offset min-sum"];
rows=repmat(struct('Case',"",'Passed',false,'ErrorID',"",'Detail',""),0,1);
for algorithm=algorithms
    for termination=["early","max"]
        for batch=[false true]
            policy=struct('algorithm',char(algorithm),'scalingFactor',.61, ...
                'minSumOffset',.31,'termination',char(termination), ...
                'maxIterations',4,'useMexBatchDecode',batch);
            record(algorithm+"/"+termination+"/batch="+string(batch), ...
                @()localSCHPaths(fixture,policy));
        end
    end
end
record("actual_multi_CB_complete_parity",@()localMultiCB(algorithms));
record("encoded_bad_TB_CRC_not_parity_failure",@()localBadCRC(fixture));
record("conflicting_UL_policy_rejected",@()localPolicyConflict(fixture));
checks=struct2table(rows);
for k=find(~checks.Passed).'
    fprintf(2,'LDPC_PRODUCTION_POLICY %s FAIL %s %s\n', ...
        checks.Case(k),checks.ErrorID(k),checks.Detail(k));
end
assert(all(checks.Passed),'test:LDPCProductionPolicy', ...
    '%d/%d codec groups failed.',nnz(~checks.Passed),height(checks));
assert(isequaln(beforeRNG,rng),'Codec policy checks unexpectedly consumed RNG.');
fprintf('LDPC_PRODUCTION_POLICY_PASS groups=%d actual_encoded_LLR=1 complete_parity=1 waveform=0 MAC_retry=0 MEX_qualification=0\n',height(checks));
ok=true;

    function record(name,fn)
        row=struct('Case',name,'Passed',false,'ErrorID',"",'Detail',"");
        try, fn(); row.Passed=true;
        catch cause
            row.ErrorID=string(cause.identifier);
            row.Detail=string(getReport(cause,'extended','hyperlinks','off'));
        end
        rows(end+1,1)=row; %#ok<AGROW>
    end
end

function f=localFixture()
f.A=256; f.Rate=.3; f.G=1200; f.RVs=[0 2];
f.Bits=int8(mod((1:f.A).'+floor((1:f.A).'/7),2));
f.PUSCH=nrPUSCHConfig('NumLayers',1,'Modulation','QPSK');
f.Plans=cell(1,2); f.ULLayouts=cell(1,2);
f.DLLLR=cell(1,2); f.ULLLR=cell(1,2);
f.DLRecovered=cell(1,2); f.ULRecovered=cell(1,2);
sch=nrULSCHInfo(f.A,f.Rate);
withCRC=nrCRCEncode(f.Bits,sch.CRC);
segmented=nrCodeBlockSegmentLDPC(withCRC,sch.BGN);
coded=nrLDPCEncode(segmented,sch.BGN);
for k=1:2
    rv=f.RVs(k);
    f.Plans{k}=sixgr.pdsch.DLSCHCodingPlan.resolve('TransportBlockSize',f.A, ...
        'TargetCodeRate',f.Rate,'RV',rv,'Modulation','QPSK','NumLayers',1, ...
        'RateMatchedBitCount',f.G,'CodewordIndex',0);
    encoded=sixgr.pdsch.DLSCHEncoder(f.Bits,f.Plans{k});
    ulBits=nrRateMatchLDPC(coded,f.G,rv,'QPSK',1);
    % Actual native UL encoding agrees with the existing DL codec for this
    % common small-TB layout; subsequent declared noise operands differ.
    assert(isequal(encoded.RateMatchedBits,ulBits));
    n=(1:f.G).';
    f.DLLLR{k}=1.1*(1-2*double(encoded.RateMatchedBits))+1.8*sin(.731*n+k)+cos(.193*n);
    f.ULLLR{k}=1.1*(1-2*double(ulBits))+1.8*cos(.617*n+k)+sin(.217*n);
    f.ULLayouts{k}=sixgr.phy.phycode.resolveCodingLayout('Direction','UL', ...
        'TransportBlockSize',f.A,'TargetCodeRate',f.Rate,'RV',rv, ...
        'Modulation','QPSK','NumLayers',1,'RateMatchedBitCount',f.G);
    f.DLRecovered{k}=nrRateRecoverLDPC(f.DLLLR{k},f.A,f.Rate,rv,'QPSK',1);
    f.ULRecovered{k}=nrRateRecoverLDPC(f.ULLLR{k},f.A,f.Rate,rv,'QPSK',1);
end
end

function localSCHPaths(f,policy)
args=localDLSCHArgs(policy);
cfg=struct('phy',struct('ldpc',policy));
resolved=sixgr.phy.phycode.resolveLDPCPolicy(cfg);
assert(isequaln(resolved,policy),'Configured decoder policy changed before execution.');
dl=sixgr.pdsch.DLSCHDecoder(f.DLLLR{1},'CodingPlan',f.Plans{1},args{:});
dlLayout=f.Plans{1}.toCodingLayout();
reference=localNative(f.DLRecovered{1},dlLayout,policy);
assert(isequaln(dl.RateRecoveredLLR,f.DLRecovered{1}));
localDLCompare(dl,reference,policy,"initial_decode");
ul=sixgr.phy.ul.pusch.decodeResolvedULSCH(f.ULLLR(1),true,f.PUSCH,f.A, ...
    f.Rate,0,f.ULLayouts(1),4,policy.algorithm,[],[],policy);
referenceUL=localNative(f.ULRecovered{1},f.ULLayouts{1},policy);
localULCompare(ul,referenceUL,policy,"initial_decode");

% Only actual first-decode buffers are passed to the receiver-owned retry.
dlCombined=sixgr.pdsch.DLSCHDecoder(f.DLLLR{2},'CodingPlan',f.Plans{2}, ...
    args{:},'PriorRecoveredLLR',dl.SoftBuffer,'PriorCodingPlan',f.Plans{1});
ulPrior={ul.CodewordEvidence{1}.HARQCombining.SoftBuffer};
ulCombined=sixgr.phy.ul.pusch.decodeResolvedULSCH(f.ULLLR(2),true,f.PUSCH,f.A, ...
    f.Rate,2,f.ULLayouts(2),4,policy.algorithm,ulPrior,f.ULLayouts(1),policy);
dlMother=f.DLRecovered{1}+f.DLRecovered{2};
ulMother=f.ULRecovered{1}+f.ULRecovered{2};
assert(dlCombined.HARQCombineInfo.Applied&&ulCombined.CodewordEvidence{1}.HARQCombining.Applied);
assert(isequaln(dlCombined.HARQCombinedLLR,dlMother));
dlReference=localNative(dlMother,f.Plans{2}.toCodingLayout(),policy);
ulReference=localNative(ulMother,f.ULLayouts{2},policy);
localDLCompare(dlCombined,dlReference,policy,"harq_combined_decode");
localULCompare(ulCombined,ulReference,policy,"harq_combined_decode");

% These public final-combined owners consume mother-code LLRs, not TX bits.
[pass,meanIterations,bits,diagnostic]=sixgr.phy.harq.decodeCombinedDLSCH( ...
    dlCombined.CodingLayout,dlMother,cfg);
localCombinedCompare(pass,meanIterations,bits,diagnostic,dlReference,policy,"DL");
[pass,meanIterations,bits,diagnostic]=sixgr.phy.harq.decodeCombinedULSCH( ...
    ulCombined.CodewordEvidence{1}.CodingLayout,ulMother,cfg);
localCombinedCompare(pass,meanIterations,bits,diagnostic,ulReference,policy,"UL");
end

function args=localDLSCHArgs(p)
args={'MaxIterations',4,'Algorithm',p.algorithm,'ScalingFactor',p.scalingFactor, ...
    'Offset',p.minSumOffset,'Termination',p.termination,'UseMexLDPC',p.useMexBatchDecode};
end

function r=localNative(llr,layout,p)
args=localNativeArgs(p);
[decoded,iterations,parity]=nrLDPCDecode(llr,double(layout.BaseGraph),4,args{:});
[withCRC,cbError]=nrCodeBlockDesegmentLDPC(decoded,double(layout.BaseGraph),double(layout.B));
[bits,errorFlag]=nrCRCDecode(withCRC,char(layout.TBCRCType));
r=struct('Decoded',decoded,'Iterations',iterations,'Parity',parity, ...
    'Bits',int8(bits(:)),'CRCError',logical(errorFlag),'CBError',cbError);
end

function args=localNativeArgs(p)
args={'Algorithm',p.algorithm,'Termination',p.termination};
if strcmp(p.algorithm,'Normalized min-sum'), args=[args,{'ScalingFactor',p.scalingFactor}]; end
if strcmp(p.algorithm,'Offset min-sum'), args=[args,{'Offset',p.minSumOffset}]; end
end

function localDLCompare(d,r,p,stage)
assert(isequal(d.DecodedCodeBlocks,r.Decoded)&&isequal(d.TransportBlock,r.Bits)&& ...
    isequal(logical(d.CRCError),r.CRCError)&&isequal(d.ActiveIterations(:),double(r.Iterations(:)))&& ...
    isequal(d.FinalParityChecks,r.Parity));
assert(~d.UseMexLDPC&&d.BatchLDPCRequested==p.useMexBatchDecode);
localReceipt(d.LDPCPolicyReceipt,r,p);
localParity(d.LDPCParityEvidence,r.Parity,stage);
end

function localULCompare(d,r,p,stage)
e=d.CodewordEvidence{1};
assert(d.DecodeAttempted&&d.CRCAvailable&&isequal(d.TransportBlocks{1},r.Bits)&& ...
    logical(d.CRCError)==r.CRCError&&isequal(e.ActualIterations(:),r.Iterations(:))&& ...
    isequal(e.FinalParityChecks,r.Parity)&&e.CodewordIndex==0);
localReceipt(e.LDPCPolicyReceipt,r,p);
localParity(d.LDPCParityEvidence,r.Parity,stage);
end

function localCombinedCompare(pass,meanIterations,bits,d,r,p,direction)
assert(isequal(pass,~r.CRCError)&&isequal(bits,r.Bits)&& ...
    meanIterations==mean(r.Iterations,'all')&&d.Direction==direction&& ...
    isequal(d.FinalParityChecks,r.Parity)&&d.TransportBlockLengthMatch&& ...
    d.TransportBlockCRCPass==~r.CRCError&& ...
    isequal(logical(d.CodeBlockCRCError),logical(r.CBError)));
localReceipt(d.LDPCPolicyReceipt,r,p);
localParity(d.LDPCParityEvidence,r.Parity,"harq_combined_decode");
end

function localReceipt(receipt,r,p)
assert(receipt.AppliedAlgorithm==string(p.algorithm)&&receipt.AppliedTermination==string(p.termination)&& ...
    receipt.ConfiguredScalingFactor==p.scalingFactor&&receipt.ConfiguredOffset==p.minSumOffset&& ...
    receipt.MaximumIterations==4&&~receipt.MEXApplied&&~receipt.AlgorithmSubstitutionApplied&& ...
    ~receipt.RetryApplied&&receipt.AccelerationRequested==p.useMexBatchDecode&& ...
    isequal(receipt.ActualIterationsPerCodeBlock(:),double(r.Iterations(:)))&& ...
    isequal(receipt.FinalParityCheckShape,double(size(r.Parity)))&& ...
    isequal(receipt.UnsatisfiedParityChecksPerCodeBlock,sum(r.Parity~=0,1))&& ...
    isequal(receipt.AllParityChecksSatisfiedPerCodeBlock,all(r.Parity==0,1)));
assert(receipt.CodeBlockCount==size(r.Parity,2)&&size(r.Parity,1)>1);
if p.useMexBatchDecode
    assert(receipt.DecoderEngine=="sixgr_ldpc_decode_batch_kernel_v2_MATLAB"&& ...
        receipt.AccelerationStatus=="exact_MATLAB_batch_v2_no_qualified_v2_MEX");
else
    assert(receipt.DecoderEngine=="nrLDPCDecode"&&receipt.AccelerationStatus=="native_execution");
end
if strcmp(p.algorithm,'Normalized min-sum')
    assert(receipt.AppliedScalingFactor==p.scalingFactor&&isnan(receipt.AppliedOffset));
elseif strcmp(p.algorithm,'Offset min-sum')
    assert(receipt.AppliedOffset==p.minSumOffset&&isnan(receipt.AppliedScalingFactor));
else
    assert(isnan(receipt.AppliedScalingFactor)&&isnan(receipt.AppliedOffset));
end
if strcmp(p.termination,'max'), assert(all(r.Iterations==4,'all')); end
end

function localParity(e,matrix,stage)
assert(e.Available&&e.HasObservedCodewords&&e.Stage==stage&& ...
    isequal(e.FinalParityChecksPerCodeword,{matrix})&&e.CheckCount==numel(matrix)&& ...
    e.UnsatisfiedCheckCount==nnz(matrix)&&e.CodeBlockCount==size(matrix,2)&& ...
    e.FailedCodeBlockCount==nnz(any(matrix~=0,1)));
end

function localMultiCB(algorithms)
observedFailedChecks=false;
for bgn=[1 2]
    K=10*16; if bgn==1, K=22*16; end
    input=int8(mod(reshape(1:(K*3),K,3)+floor(reshape(1:(K*3),K,3)/7),2));
    coded=nrLDPCEncode(input,bgn);
    n=reshape(1:numel(coded),size(coded));
    llr=.7*(1-2*double(coded))+2.3*sin(.711*n)+cos(.137*n);
    for algorithm=algorithms
        for termination=["early","max"]
            p=struct('algorithm',char(algorithm),'scalingFactor',.61, ...
                'minSumOffset',.31,'termination',char(termination),'useMexBatchDecode',true);
            args=localNativeArgs(p);
            [expected,it,pc]=nrLDPCDecode(llr,bgn,4,args{:});
            [actual,iterations,parity,receipt]=sixgr.phy.phycode.decodeLDPCConfigured(llr,bgn,4,p,true);
            assert(isequal(actual,expected)&&isequal(iterations(:),it(:))&&isequal(parity,pc));
            r=struct('Iterations',it,'Parity',pc); localReceipt(receipt,r,p);
            assert(numel(receipt.CodeBlockReceipts)==3&&size(parity,2)==3);
            for c=1:3
                assert(isequal(receipt.CodeBlockReceipts{c}.UnsatisfiedParityChecksPerCodeBlock,sum(pc(:,c)~=0)));
            end
            nativePolicy=p; nativePolicy.useMexBatchDecode=false;
            [native,ni,np,nr]=sixgr.phy.phycode.decodeLDPCConfigured(llr,bgn,4,nativePolicy,false);
            assert(isequal(native,expected)&&isequal(ni(:),it(:))&&isequal(np,pc));
            localReceipt(nr,r,nativePolicy);
            observedFailedChecks=observedFailedChecks||any(pc~=0,'all');
        end
    end
end
assert(observedFailedChecks,'The noisy parity fixture did not exercise an actual failed native check.');
end

function localBadCRC(f)
plan=f.Plans{1}; layout=plan.toCodingLayout();
withCRC=nrCRCEncode(f.Bits,char(layout.TBCRCType));
withCRC(end)=1-withCRC(end); % Declared invalid TB CRC BEFORE actual LDPC coding.
encoded=nrLDPCEncode(nrCodeBlockSegmentLDPC(withCRC,double(layout.BaseGraph)),double(layout.BaseGraph));
matched=nrRateMatchLDPC(encoded,f.G,0,'QPSK',1); llr=30*(1-2*double(matched));
p=struct('algorithm','Normalized min-sum','scalingFactor',.61, ...
    'minSumOffset',.31,'termination','max','useMexBatchDecode',true);
args=localDLSCHArgs(p); d=sixgr.pdsch.DLSCHDecoder(llr,'CodingPlan',plan,args{:});
recovered=nrRateRecoverLDPC(llr,f.A,f.Rate,0,'QPSK',1); r=localNative(recovered,layout,p);
localDLCompare(d,r,p,"initial_decode");
assert(r.CRCError&&d.CRCError&&isequal(d.TransportBlock,f.Bits)&&all(r.Parity==0,'all'), ...
    'TB CRC failure must remain distinct from an all-satisfied LDPC syndrome.');
end

function localPolicyConflict(f)
p=struct('algorithm','Offset min-sum','scalingFactor',.61,'minSumOffset',.31,'termination','early');
try
    sixgr.phy.ul.pusch.decodeResolvedULSCH(f.ULLLR(1),true,f.PUSCH,f.A, ...
        f.Rate,0,f.ULLayouts(1),4,'Normalized min-sum',[],[],p);
catch cause
    assert(strcmp(cause.identifier,'sixgr:pusch:LDPCPolicyConflict')); return;
end
error('test:MissingLDPCPolicyConflict','Explicit algorithm/policy contradiction was accepted.');
end
