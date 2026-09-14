function ok=testPUSCHResolvedCodewordDecode(outputRoot)
% Actual public LDPC/CRC codecs on declared LLR fixtures, not RF evidence.
setup6GRSimToolkit('Verbose',false);
if nargin<1, outputRoot=tempname(fullfile(pwd,'logs')); end
assert(~isfolder(outputRoot),'test:EvidenceAlreadyExists','Preserve prior codec diagnostics.');
mkdir(outputRoot);
runtimeVersion=version; toolboxVersions=ver;
cases=0;
for rank=5:8
    p=nrPUSCHConfig('NumLayers',rank,'Modulation',{'QPSK','16QAM'});
    [layers,~]=sixgr.phy.ul.pusch.PUSCHLayerMapper.layerCounts(rank);
    tbs=[512 10240]; rate=[.3 .6]; rv=[0 2];
    [llr,bits,layouts,encodedStages]=localEncode(p,layers,tbs,rate,rv,false);
    full=sixgr.phy.ul.pusch.decodeResolvedULSCH(llr,true(1,2),p,tbs,rate,rv, ...
        layouts,25,'Normalized min-sum',[],[]);
    % Independent public system decoder reference uses both codewords.
    reference=nrULSCHDecoder('MultipleHARQProcesses',false,'TargetCodeRate',rate, ...
        'TransportBlockLength',tbs,'LDPCDecodingAlgorithm','Normalized min-sum', ...
        'MaximumLDPCIterationCount',25);
    [expected,errors]=reference(llr,p.Modulation,p.NumLayers,rv);
    % Retain both independent results BEFORE a failing assertion. Do not
    % change rate/RV/iterations merely to obtain a green noiseless fixture.
    save(fullfile(outputRoot,sprintf('resolved_codewords_rank_%d.mat',rank)), ...
        'p','layers','tbs','rate','rv','llr','bits','layouts','encodedStages', ...
        'full','expected','errors','runtimeVersion','toolboxVersions');
    fprintf('PUSCH_RESOLVED_REFERENCE rank=%d candidate_crc=%s public_crc=%s evidence=%s\n', ...
        rank,mat2str(full.CRCError),mat2str(errors),outputRoot);
    % Preserve the original RV2-only stimulus as an attempted failed decode.
    % Its puncturing pattern leaves unresolved iterative-decoder variables:
    % the independently encoded/reference-decoded case fails identically.
    assert(all(full.DecodeAttempted) && all(full.CRCAvailable) && ...
        isequal(full.CRCError,[0 1]) && ~full.AllTransportBlocksPassed);
    assert(isequal(full.TransportBlocks{1},bits{1}) && ~isequal(full.TransportBlocks{2},bits{2}));
    assert(isequal(full.TransportBlocks,reshape(expected,1,[])) && ...
        isequal(full.CRCError,double(reshape(errors,1,[]))));
    % Add a real initial encoding, not invented prior LLRs. Rates, TB sizes,
    % modulation, rank, LLR magnitude and iteration limit stay unchanged.
    initialRV=[0 0];
    [initialLLR,initialBits,initialLayouts,initialStages]=localEncode(p,layers,tbs,rate,initialRV,false);
    assert(isequal(initialBits,bits));
    encoder=nrULSCH('MultipleHARQProcesses',false,'TargetCodeRate',rate);
    setTransportBlock(encoder,bits);
    encodedReference=encoder(p.Modulation,p.NumLayers,cellfun(@numel,llr),rv);
    initialEncodedReference=encoder(p.Modulation,p.NumLayers,cellfun(@numel,initialLLR),initialRV);
    for cw=1:2
        assert(isequal(encodedReference{cw},encodedStages{cw}.RateMatchedBits) && ...
            isequal(initialEncodedReference{cw},initialStages{cw}.RateMatchedBits));
    end
    initial=sixgr.phy.ul.pusch.decodeResolvedULSCH(initialLLR,true(1,2),p,tbs,rate,initialRV, ...
        initialLayouts,25,'Normalized min-sum',[],[]);
    prior=cellfun(@(e)e.HARQCombining.SoftBuffer,initial.CodewordEvidence,'UniformOutput',false);
    priorLayouts=cellfun(@(e)e.CodingLayout,initial.CodewordEvidence,'UniformOutput',false);
    combined=sixgr.phy.ul.pusch.decodeResolvedULSCH(llr,true(1,2),p,tbs,rate,rv, ...
        layouts,25,'Normalized min-sum',prior,priorLayouts);
    % Direct public recovery/sum/decode avoids version-dependent automatic
    % flushing after CRC success in the public system decoder. This is a
    % retained-same-TB codec comparison, not a claim of MAC retransmission.
    initialReference=localPrimitiveReference(initialLLR,p,layers,tbs,rate,initialRV,[],[]);
    combinedReference=localPrimitiveReference(llr,p,layers,tbs,rate,rv,initialLLR,initialRV);
    save(fullfile(outputRoot,sprintf('positive_codewords_rank_%d.mat',rank)), ...
        'initialRV','initialLLR','initialLayouts','initialStages','initial', ...
        'combined','initialReference','combinedReference');
    assert(initial.AllTransportBlocksPassed && isequal(initial.TransportBlocks,bits) && ...
        isequal(initial.TransportBlocks,initialReference.Bits) && all(initialReference.CRCError==0));
    assert(combined.AllTransportBlocksPassed && isequal(combined.TransportBlocks,bits) && ...
        isequal(combined.TransportBlocks,combinedReference.Bits) && all(combinedReference.CRCError==0));
    assert(all(cellfun(@(e)e.HARQCombining.Applied,combined.CodewordEvidence)));
    cases=cases+localCheckPartial(initialLLR,p,tbs,rate,initialRV,initialLayouts,[],[],bits);
    cases=cases+localCheckPartial(llr,p,tbs,rate,rv,layouts,prior,priorLayouts,bits);
    unresolvedAndFailed=sixgr.phy.ul.pusch.decodeResolvedULSCH({[],llr{2}},[false true], ...
        p,tbs,rate,rv,layouts,25,'Normalized min-sum',[],[]);
    assert(isequal(unresolvedAndFailed.DecodeAttempted,[false true]) && ...
        isequal(unresolvedAndFailed.CRCAvailable,[false true]) && ...
        isnan(unresolvedAndFailed.CRCError(1)) && unresolvedAndFailed.CRCError(2)==1 && ...
        isequal(unresolvedAndFailed.TransportBlocks{2},full.TransportBlocks{2}));
    bad=layouts; bad{2}.RateMatchedBitCount=bad{2}.RateMatchedBitCount+uint32(1);
    localReject(@()sixgr.phy.ul.pusch.decodeResolvedULSCH({[],llr{2}},[false true], ...
        p,tbs,rate,rv,bad,25,'Normalized min-sum',[],[]), ...
        'sixgr:pusch:ResolvedCodingLayoutMismatch');
    localReject(@()sixgr.phy.ul.pusch.decodeResolvedULSCH(llr,[false true], ...
        p,tbs,rate,rv,layouts,25,'Normalized min-sum',[],[]), ...
        'sixgr:pusch:UnresolvedCodewordHasLLR');
    localReject(@()sixgr.phy.ul.pusch.decodeResolvedULSCH({[],llr{2}},[false true], ...
        p,tbs,rate,rv,layouts,25,'Normalized min-sum',llr{2},[]), ...
        'sixgr:pusch:MissingPerCodewordCodingAuthority');
end
% Pair CRC corruption with the already-passed decodable initial-RV control.
% The old RV2-only stimulus fails even without corruption and cannot prove
% that the deliberate CRC error caused its failure.
[badLLR,~,layouts]=localEncode(p,layers,tbs,rate,initialRV,true);
failed=sixgr.phy.ul.pusch.decodeResolvedULSCH({[],badLLR{2}},[false true], ...
    p,tbs,rate,initialRV,layouts,25,'Normalized min-sum',[],[]);
assert(~failed.DecodeAttempted(1) && isnan(failed.CRCError(1)));
assert(failed.DecodeAttempted(2) && failed.CRCError(2)==1 && failed.CRCPass(2)==0);
assert(isequal(failed.TransportBlocks{2},bits{2}) && ...
    all(failed.CodewordEvidence{2}.CodeBlockCRCError==0));
ok=true; fprintf('PUSCH_RESOLVED_CODEWORD_DECODE_PASS partial_cases=%d plus public reference and CRC negative.\n',cases);
end

function count=localCheckPartial(llr,p,tbs,rate,rv,layouts,prior,priorLayouts,bits)
count=0;
for mask={[true false],[false true],[false false]}
    resolved=mask{1}; received=llr; received(~resolved)={[]};
    partial=sixgr.phy.ul.pusch.decodeResolvedULSCH(received,resolved,p,tbs,rate,rv, ...
        layouts,25,'Normalized min-sum',prior,priorLayouts);
    assert(isequal(partial.DecodeAttempted,resolved) && isequal(partial.CRCAvailable,resolved));
    assert(~partial.AllTransportBlocksPassed);
    for cw=1:2
        e=partial.CodewordEvidence{cw};
        assert(e.TransportBlockSize==tbs(cw) && e.CodewordIndex==cw-1);
        if resolved(cw)
            assert(isequal(partial.TransportBlocks{cw},bits{cw}) && partial.CRCPass(cw)==1);
            assert(e.DecodeAttempted && e.CRCAvailable && e.CRCError==0);
        else
            assert(isempty(partial.TransportBlocks{cw}) && isnan(partial.CRCPass(cw)));
            assert(~e.DecodeAttempted && ~e.CRCAvailable && isnan(e.CRCError));
            assert(isempty(fieldnames(e.CodingLayout)), ...
                'An unresolved map must not claim that a supplied layout was executed.');
        end
    end
    count=count+1;
end
end

function result=localPrimitiveReference(llr,p,layers,tbs,rate,rv,priorLLR,priorRV)
bits=cell(1,2); errors=zeros(1,2); modulation=string(p.Modulation);
for cw=1:2
    sch=nrULSCHInfo(tbs(cw),rate(cw));
    recovered=nrRateRecoverLDPC(llr{cw},tbs(cw),rate(cw),rv(cw),char(modulation(cw)),layers(cw));
    if ~isempty(priorLLR)
        recovered=recovered+nrRateRecoverLDPC(priorLLR{cw},tbs(cw),rate(cw),priorRV(cw), ...
            char(modulation(cw)),layers(cw));
    end
    decoded=nrLDPCDecode(recovered,sch.BGN,25,'Algorithm','Normalized min-sum');
    withCRC=nrCodeBlockDesegmentLDPC(decoded,sch.BGN,tbs(cw)+sch.L);
    [bits{cw},errors(cw)]=nrCRCDecode(withCRC,sch.CRC);
end
result=struct('Bits',{bits},'CRCError',errors);
end

function [llr,bits,layouts,encodedStages]=localEncode(p,layers,tbs,rate,rv,badCRC)
llr=cell(1,2); bits=cell(1,2); layouts=cell(1,2);
encodedStages=cell(1,2);
modulation=string(p.Modulation); qm=[2 4];
for cw=1:2
    bits{cw}=int8(mod((1:tbs(cw)).'+floor((1:tbs(cw)).'/7),2));
    sch=nrULSCHInfo(tbs(cw),rate(cw));
    withCRC=nrCRCEncode(bits{cw},sch.CRC);
    if badCRC && cw==2, withCRC(end)=1-withCRC(end); end
    segmented=nrCodeBlockSegmentLDPC(withCRC,sch.BGN);
    coded=nrLDPCEncode(segmented,sch.BGN);
    quantum=qm(cw)*layers(cw);
    length=quantum*ceil((tbs(cw)/rate(cw))/quantum);
    matched=nrRateMatchLDPC(coded,length,rv(cw),char(modulation(cw)),layers(cw));
    encodedStages{cw}=struct('WithTBCRC',withCRC,'SegmentedBlocks',segmented, ...
        'MotherCodeBits',coded,'RateMatchedBits',matched,'ULSCHInfo',sch);
    llr{cw}=100*(1-2*double(matched));
    layouts{cw}=sixgr.phy.phycode.resolveCodingLayout('Direction','UL', ...
        'TransportBlockSize',tbs(cw),'TargetCodeRate',rate(cw),'RV',rv(cw), ...
        'Modulation',modulation(cw),'NumLayers',layers(cw),'RateMatchedBitCount',length);
end
end

function localReject(action,identifier)
try
    action();
catch err
    assert(strcmp(err.identifier,identifier),'Expected %s, observed %s: %s',identifier,err.identifier,err.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected rejection: %s',identifier);
end
