function ok=testPUSCHResolvedCodewordDecode()
% Actual public LDPC/CRC codecs on declared LLR fixtures, not RF evidence.
setup6GRSimToolkit('Verbose',false);
cases=0;
for rank=5:8
    p=nrPUSCHConfig('NumLayers',rank,'Modulation',{'QPSK','16QAM'});
    [layers,~]=sixgr.phy.ul.pusch.PUSCHLayerMapper.layerCounts(rank);
    tbs=[512 10240]; rate=[.3 .6]; rv=[0 2];
    [llr,bits,layouts]=localEncode(p,layers,tbs,rate,rv,false);
    full=sixgr.phy.ul.pusch.decodeResolvedULSCH(llr,true(1,2),p,tbs,rate,rv, ...
        layouts,25,'Normalized min-sum',[],[]);
    assert(full.AllTransportBlocksPassed && isequal(full.TransportBlocks,bits));
    % Independent public system decoder reference uses both codewords.
    reference=nrULSCHDecoder('MultipleHARQProcesses',false,'TargetCodeRate',rate, ...
        'TransportBlockLength',tbs,'LDPCDecodingAlgorithm','Normalized min-sum', ...
        'MaximumLDPCIterationCount',25);
    [expected,errors]=reference(llr,p.Modulation,p.NumLayers,rv);
    assert(isequal(full.TransportBlocks,reshape(expected,1,[])) && ...
        isequal(full.CRCError,double(reshape(errors,1,[]))));
    for mask={[true false],[false true],[false false]}
        resolved=mask{1}; received=llr;
        received(~resolved)={[]};
        partial=sixgr.phy.ul.pusch.decodeResolvedULSCH(received,resolved,p,tbs,rate,rv, ...
            layouts,25,'Normalized min-sum',[],[]);
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
        cases=cases+1;
    end
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
% A deliberately wrong TB CRC is a coded negative stimulus. It must remain
% an actual attempted/failed CRC, distinct from an unattempted codeword.
[badLLR,~,layouts]=localEncode(p,layers,tbs,rate,rv,true);
failed=sixgr.phy.ul.pusch.decodeResolvedULSCH({[],badLLR{2}},[false true], ...
    p,tbs,rate,rv,layouts,25,'Normalized min-sum',[],[]);
assert(~failed.DecodeAttempted(1) && isnan(failed.CRCError(1)));
assert(failed.DecodeAttempted(2) && failed.CRCError(2)==1 && failed.CRCPass(2)==0);
ok=true; fprintf('PUSCH_RESOLVED_CODEWORD_DECODE_PASS partial_cases=%d plus public reference and CRC negative.\n',cases);
end

function [llr,bits,layouts]=localEncode(p,layers,tbs,rate,rv,badCRC)
llr=cell(1,2); bits=cell(1,2); layouts=cell(1,2);
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
