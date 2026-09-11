function ok=testPDCCHReceivedCandidateContext()
% Independent RE mapping check, including frame wrap and AL ambiguity.
setup6GRSimToolkit('Verbose',false);
checked=0;
for scs=[15 30]
    carrier=nrCarrierConfig('SubcarrierSpacing',scs,'NSizeGrid',25);
    for coreID=0:2
        core=nrCORESETConfig('CORESETID',coreID,'FrequencyResources',ones(1,4), ...
            'Duration',2,'CCEREGMapping','noninterleaved');
        for kind=["common","ue"]
            ss=nrSearchSpaceConfig('CORESETID',coreID,'SearchSpaceType',char(kind), ...
                'NumCandidates',[4 2 1 1 0]);
            p=nrPDCCHConfig('CORESET',core,'SearchSpace',ss,'NSizeBWP',25,'RNTI',1);
            if kind=="common", p.RNTI=0; end
            for slot=[0 1 9 10 30]
                carrier.NSlot=slot; carrier.NFrame=3;
                for level=[1 2 4 8]
                    p.AggregationLevel=level;
                    count=ss.NumCandidates(log2(level)+1);
                    for index=0:count-1
                        p.AllocatedCandidate=index+1;
                        c=sixgr.phy.pdcch.resolveCandidateContext(carrier,p,level,index);
                        re=double(nrPDCCHResources(carrier,p,'IndexStyle','subscript'));
                        % Noninterleaved, contiguous CORESET: each RB has
                        % Duration REGs; six consecutive REGs form one CCE.
                        expected=floor((min(re(:,1))-1)/12)*core.Duration/6;
                        assert(c.FirstCCE==expected && c.NumCCE==8);
                        assert(c.SlotWithinFrame==mod(slot,carrier.SlotsPerFrame));
                        checked=checked+1;
                    end
                end
            end
        end
    end
end
% Two CRC-valid equivalent payload hypotheses may have different ALs.
% Preserve the selected AL instead of combining its CCE with the TX AL.
p.AggregationLevel=8; p.AllocatedCandidate=1;
c=sixgr.phy.pdcch.resolveCandidateContext(carrier,p,1,3);
assert(c.AggregationLevel==1 && c.CandidateIndex==3);
row=table(7,8,1,3,'VariableNames',{'PDCCHSelectedCCEIndex','AvailableCCECount', ...
    'PDCCHSelectedAggregationLevel','PDCCHSelectedCandidateIndex'});
grant=struct('PDCCHAggregationLevel',8,'PDCCHGrantAggregationLevel',8, ...
    'PDCCHGrantCandidateIndex',0);
bound=sixgr.truth.bindReceivedPDCCHGrantContext(grant,row);
assert(bound.PDCCHAggregationLevel==8 && bound.PDCCHGrantAggregationLevel==1);
assert(bound.PDCCHGrantFirstCCE==7 && bound.PDCCHGrantCandidateIndex==3);
localReject(@()sixgr.truth.bindReceivedPDCCHGrantContext(grant, ...
    removevars(row,'PDCCHSelectedAggregationLevel')), ...
    'sixgr:truth:MissingDecodedPDCCHCCEContext');
bad=row; bad.PDCCHSelectedAggregationLevel=4;
localReject(@()sixgr.truth.bindReceivedPDCCHGrantContext(grant,bad), ...
    'sixgr:truth:MissingDecodedPDCCHCCEContext');
localReject(@()sixgr.phy.pdcch.resolveCandidateContext(carrier,p,1,4), ...
    'sixgr:phy:pdcch:ReceivedCandidateOutOfRange');
fprintf('PDCCH_RECEIVED_CANDIDATE_CONTEXT_PASS: %d independent resource mappings.\n',checked);
ok=true;
end

function localReject(call,id)
try, call(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s.',id,cause.identifier);
    return;
end
error('test:MissingError','Expected %s.',id);
end
