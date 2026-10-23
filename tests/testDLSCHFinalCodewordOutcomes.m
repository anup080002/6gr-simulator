function [ok,checks]=testDLSCHFinalCodewordOutcomes()
% Actual native CRC/segmentation/LDPC/rate-matching decoder fixtures only.
% No waveform, received DCI, scheduler retry, MAC delivery or public BLER
% qualification. Invalid-CRC stimuli are formed before actual LDPC encoding;
% only explicitly rejected copies alter original decoder metadata.
setup6GRSimToolkit('Verbose',false);
originalRNG=rng; cleanup=onCleanup(@()rng(originalRNG)); %#ok<NASGU>
cfg=struct('phy',struct('ldpc',struct('maxIterations',25,'algorithm','Normalized min-sum')));
rows=repmat(struct('Case',"",'Passed',false,'FailureID',"",'Detail',""),0,1);
record("individual_mixed_CRC_final_projection",@mixed);
record("scalar_compatibility_no_external_prior",@single);
record("already_combined_receiver_no_second_decode",@alreadyCombined);
record("indexed_RV0_RV2_outer_final_decisions",@outer);
record("actual_failed_combined_TB_no_reference_rescue",@failed);
record("identity_shape_and_double_combining_negatives",@negative);
checks=struct2table(rows);
for k=find(~checks.Passed).'
    fprintf(2,'DLSCH_FINAL_CW %s FAIL %s %s\n',checks.Case(k),checks.FailureID(k),checks.Detail(k));
end
assert(all(checks.Passed),'test:DLSCHFinalCodewordOutcomes:Failed', ...
    '%d/%d bounded final-decoder cases failed.',nnz(~checks.Passed),height(checks));
fprintf('DLSCH_FINAL_CW_PASS cases=%d native_codec=1 waveform=0 completed_trial_binding=0\n',height(checks));
ok=true;

    function record(name,fn)
        row=struct('Case',name,'Passed',false,'FailureID',"",'Detail',"");
        try, fn(); row.Passed=true;
        catch cause
            row.FailureID=string(cause.identifier);
            row.Detail=string(getReport(cause,'extended','hyperlinks','off'));
        end
        rows(end+1,1)=row; %#ok<AGROW>
    end
    function mixed()
        [p,llr,bits]=codec(0,true,20);
        d=decode(llr,p); before=d; randomBefore=rng;
        assert(isequal(d.CRCPassPerCodeword,[true false]) && isequal(d.TransportBlocks,bits));
        [f,s]=sixgr.link.finalizeDLSCHCodewordOutcomes(d,cfg);
        assert(isequaln(before,d) && isequaln(randomBefore,rng));
        assert(isequal(f.CRCPassPerCodeword,[true false]) && ~f.CRCPass && f.CRCError && ...
            f.AdditionalDecoderInvocationCount==0 && isequal(s.TransportBlocks,bits));
        assert(isequal(f.OfferedBitsPerCodeword,[512 512]) && ...
            isequal(f.SuccessfulDecodedBitsPerCodeword,[512 0]) && f.SuccessfulDecodedBits==512 && ...
            sum(f.OfferedBitsPerCodeword)*double(f.CRCPass)==0 && ...
            f.DecodedBitsScope=="this_decoder_attempt_not_unique_MAC_delivery");
        check(f,s,d);
        assert(f.Codewords{1}.CodingLayoutHash==f.Codewords{2}.CodingLayoutHash && ...
            f.Codewords{1}.CodingPlanID~=f.Codewords{2}.CodingPlanID);
        encoded=jsonencode(f); saved=jsondecode(encoded);
        assert(~saved.FinalThroughputOutcomeBound && ~saved.UniqueTransportBlockIdentityAvailable && ...
            isequal(logical(saved.CRCPassPerCodeword(:).'),[true false]));
        assert(~contains(encoded,'LLRSum') && ~contains(encoded,'TransportBlocks'), ...
            'Compact final decisions must not duplicate soft arrays or payloads.');
    end
    function single()
        [p,llr,bits]=codec(0,false,20);
        d=decode(llr{1},p{1});
        [f,s]=sixgr.link.finalizeDLSCHCodewordOutcomes(d,cfg,'Mode','legacy_outer_harq');
        assert(f.NumCodewords==1 && f.CRCPass && f.AdditionalDecoderInvocationCount==0 && ...
            isequal(s.TransportBlocks{1},bits{1}) && ...
            f.Codewords{1}.CodewordIndex==0 && f.Codewords{1}.CurrentAttemptStandaloneCRCMeasured && ...
            ~f.Codewords{1}.CodeBlockCRCApplicable && isempty(f.Codewords{1}.CodeBlockCRCError));
        check(f,s,d);
    end
    function alreadyCombined()
        [p0,l0,bits]=codec(0,false,20); [p2,l2,bits2]=codec(2,false,20);
        assert(isequal(bits,bits2)); initial=decode(l0,p0);
        actual=sixgr.pdsch.DLSCHDecoder(l2,'CodingPlan',p2, ...
            'PriorRecoveredLLR',initial,'PriorCodingPlan',p0,'MaxIterations',25);
        before=actual; randomBefore=rng;
        [f,s]=sixgr.link.finalizeDLSCHCodewordOutcomes(actual,cfg);
        assert(isequaln(actual,before) && isequaln(randomBefore,rng) && f.CRCPass && ...
            f.AdditionalDecoderInvocationCount==0 && isequal(s.TransportBlocks,bits));
        check(f,s,actual);
        for cw=1:2
            assert(f.Codewords{cw}.SelectedDecoderUsedCombining && ...
                ~f.Codewords{cw}.CurrentAttemptStandaloneCRCMeasured && ...
                isequaln(s.CombinedLLRPerCodeword{cw},actual.Codewords{cw}.HARQCombinedLLR));
        end
    end
    function outer()
        [p0,l0,bits]=codec(0,false,100); [p2,l2,bits2]=codec(2,true,1);
        assert(isequal(bits,bits2)); prior=decode(l0,p0); current=decode(l2,p2);
        assert(prior.CRCPass && isequal(current.CRCPassPerCodeword,[true false]));
        [f,s]=sixgr.link.finalizeDLSCHCodewordOutcomes(current,cfg, ...
            'Mode','legacy_outer_harq','PriorRecoveredLLR',prior.Codewords);
        assert(f.AdditionalDecoderInvocationCount==1 && ...
            f.Codewords{1}.AdditionalDecoderInvocationCount==0 && ...
            f.Codewords{2}.AdditionalDecoderInvocationCount==1 && f.CRCPass && ...
            isequal(s.TransportBlocks,bits));
        assert(f.Codewords{1}.SelectedDecoderSource=="original_canonical_decoder_result" && ...
            ~f.Codewords{1}.SelectedDecoderUsedCombining && ...
            f.Codewords{1}.RetainedSoftBufferCombiningApplied && ...
            f.Codewords{2}.SelectedDecoderSource=="outer_decodeCombinedDLSCH_result" && ...
            f.Codewords{2}.SelectedDecoderUsedCombining && ...
            ~f.Codewords{2}.OriginalDecoderCRCPass);
        % Independent primitive comparison of the exact selected mother-code
        % input. This additional test decode is not a production invocation.
        [pass,~,tb,diag]=sixgr.phy.harq.decodeCombinedDLSCH( ...
            current.Codewords{2}.CodingLayout,s.CombinedLLRPerCodeword{2},cfg);
        assert(isequal(pass,f.Codewords{2}.CRCPass) && isequal(tb,s.TransportBlocks{2}) && ...
            isequal(diag.CodeBlockCRCError,f.Codewords{2}.CodeBlockCRCError));
        for cw=1:2
            assert(f.Codewords{cw}.CodewordIndex==cw-1 && f.Codewords{cw}.RV==2 && ...
                s.SoftBufferPerCodeword{cw}.CodewordIndex==cw && ...
                f.Codewords{cw}.RetainedHARQCombineInfo.PriorNumel>0);
        end
    end
    function failed()
        [p,llr,bits]=codec(0,true,20); d=decode(llr,p);
        [f,s]=sixgr.link.finalizeDLSCHCodewordOutcomes(d,cfg, ...
            'Mode','legacy_outer_harq','PriorRecoveredLLR',d.Codewords);
        assert(isequal(f.CRCPassPerCodeword,[true false]) && ~f.CRCPass && ...
            f.AdditionalDecoderInvocationCount==1 && isequal(s.TransportBlocks,bits) && ...
            ~f.Codewords{2}.TransportBlockCRCPass && f.Codewords{2}.TransportBlockLengthMatch);
    end
    function negative()
        [p,llr]=codec(0,false,20); d=decode(llr,p);
        id='sixgr:link:DLSCHFinalCodewordMismatch';
        bad=d; bad.Codewords=bad.Codewords([2 1]); reject(@()finish(bad),id);
        bad=d; bad.Codewords{2}.CodingPlanID="wrong"; reject(@()finish(bad),id);
        bad=d; bad.Codewords{2}.TransportBlock=bad.Codewords{2}.TransportBlock(2:end); reject(@()finish(bad),id);
        bad=d; bad.Codewords{2}.CRCPass=false; reject(@()finish(bad),id);
        bad=d; bad.Codewords{2}.HARQCombineInfo.CodewordIndex=1; reject(@()finish(bad),id);
        bad=d; bad.Codewords{2}.HARQCombineInfo.Applied=[false false]; reject(@()finish(bad),id);
        reject(@()outerFinish(d,d.Codewords([2 1])),'sixgr:phy:harq:SoftBufferCodewordMismatch');
        prior=d.Codewords; prior{2}.SoftBuffer=rmfield(prior{2}.SoftBuffer,'CodewordIndex');
        reject(@()outerFinish(d,prior),'sixgr:phy:harq:SoftBufferCodewordMismatch');
        reject(@()outerFinish(d,d.Codewords(1)),'sixgr:link:DLSCHFinalPriorCodewordCount');
        reject(@()outerFinish(d,d),'sixgr:link:DLSCHFinalPriorCodewordCount');
        reject(@()sixgr.link.finalizeDLSCHCodewordOutcomes(d,cfg, ...
            'PriorRecoveredLLR',d.Codewords),'sixgr:link:DLSCHFinalDuplicateCombining');
        actual=sixgr.pdsch.DLSCHDecoder(llr,'CodingPlan',p, ...
            'PriorRecoveredLLR',d,'PriorCodingPlan',p,'MaxIterations',25);
        reject(@()outerFinish(actual,d.Codewords),'sixgr:link:DLSCHFinalDuplicateCombining');
    end
    function finish(d)
        sixgr.link.finalizeDLSCHCodewordOutcomes(d,cfg);
    end
    function outerFinish(d,prior)
        sixgr.link.finalizeDLSCHCodewordOutcomes(d,cfg,'Mode','legacy_outer_harq','PriorRecoveredLLR',prior);
    end
end

function d=decode(llr,plans)
d=sixgr.pdsch.DLSCHDecoder(llr,'CodingPlan',plans,'MaxIterations',25,'Algorithm','Normalized min-sum');
end

function [plans,llr,bits]=codec(rv,poisonSecond,amplitude)
A=512; rate=.3; layers=3; modulation='QPSK'; G=3600;
bits={int8(mod((1:A).',2)),int8(mod(floor((1:A).'/3),2))};
plans=cell(1,2); llr=cell(1,2); sch=nrDLSCHInfo(A,rate);
for cw=1:2
    plans{cw}=sixgr.pdsch.DLSCHCodingPlan.resolve('TransportBlockSize',A, ...
        'TargetCodeRate',rate,'RV',rv,'Modulation',modulation,'NumLayers',layers, ...
        'RateMatchedBitCount',G,'CodewordIndex',cw-1);
    withCRC=nrCRCEncode(bits{cw},sch.CRC);
    if poisonSecond && cw==2, withCRC(end)=1-withCRC(end); end
    cb=nrCodeBlockSegmentLDPC(withCRC,sch.BGN); coded=nrLDPCEncode(cb,sch.BGN);
    matched=nrRateMatchLDPC(coded,G,rv,modulation,layers);
    llr{cw}=amplitude*(1-2*double(matched));
end
end

function check(f,state,decodeResult)
if f.NumCodewords==1, original={decodeResult}; else, original=decodeResult.Codewords; end
assert(f.ContractVersion=="DLSCHFinalDecoderOutcome/v1" && ...
    f.PopulationScope=="one_decoder_attempt_per_explicit_codeword" && ...
    ~f.FinalThroughputOutcomeBound && ~f.UniqueTransportBlockIdentityAvailable && ...
    ~f.StatisticalIndependenceClaimed && numel(f.Codewords)==numel(original));
for cw=1:numel(original)
    r=f.Codewords{cw}; d=original{cw};
    assert(r.CodewordIndex==cw-1 && r.NumCodewords==numel(original) && ...
        r.CodingPlanID==string(d.CodingPlanID) && ...
        r.CodingLayoutHash==string(d.CodingLayout.CodingLayoutHash) && ...
        r.TransportBlockSize==double(d.CodingPlan.TransportBlockSize) && ...
        isequal(r.CRCPass,d.CRCPass) && isequal(r.CRCError,d.CRCError) && ...
        isequaln(r.CodeBlockCRCError,d.CodeBlockCRCError) && ...
        isequaln(r.OriginalHARQCombineInfo,rmfield(d.HARQCombineInfo,'SoftBuffer')) && ...
        isequal(state.TransportBlocks{cw},d.TransportBlock));
    assert(r.DecodedTransportBlockSHA256==string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(d.TransportBlock)) && ...
        r.SuccessfulDecodedBits==double(d.CodingPlan.TransportBlockSize)*double(d.CRCPass));
    assert(~any(isfield(r,{'TransportBlock','RateRecoveredLLR','SoftBuffer','LogicalTBID','TBId'})));
end
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'test:DLSCHFinalCodewordOutcomes:WrongRejection', ...
        'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:DLSCHFinalCodewordOutcomes:MissingRejection','Expected %s.',id);
end
