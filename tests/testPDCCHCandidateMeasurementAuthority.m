function ok=testPDCCHCandidateMeasurementAuthority()
setup6GRSimToolkit('Verbose',false);
% Resource identity is checked against native CCE-offset mapping, including
% interleaving, USS hashing, nonzero slots and non-first candidates.
c=nrCarrierConfig('NSizeGrid',48,'SubcarrierSpacing',30,'NSlot',7);
p=nrPDCCHConfig;
p.NSizeBWP=48; p.NStartBWP=0;
p.CORESET.FrequencyResources=ones(1,8); p.CORESET.Duration=2;
p.CORESET.CORESETID=1;
p.SearchSpace.NumCandidates=[4 4 2 1 0];
p.RNTI=17001;
for kind=["common","ue"]
    p.SearchSpace.SearchSpaceType=kind;
    if kind=="common", p.RNTI=0; else, p.RNTI=17001; end
    for mapping=["noninterleaved","interleaved"]
        p.CORESET.CCEREGMapping=mapping;
        [allInd,~,~]=nrPDCCHSpace(c,p);
        for a=1:4
            level=2^(a-1);
            for k=1:size(allInd{a},2)
                first=sixgr.phy.pdcch.candidateFirstCCE(c,p,level,k-1,true);
                explicit=p; explicit.AggregationLevel=level; explicit.CCEOffset=first;
                actual=nrPDCCHResources(c,explicit);
                assert(isequal(sort(actual(:)),sort(allInd{a}(:,k))));
            end
        end
    end
end
% The mini anchor is physical coded waveform execution, not a population
% qualification. Inspect each candidate's own LLR/payload/CCE evidence.
b=pdcchStrictAnchorResult();
candidate=b.Result.ArtifactTables.pdcch_candidates;
assert(all(candidate.LLRCount>0));
assert(all(candidate.DecodeAttempted));
assert(all(candidate.LLRMin<=candidate.LLRMax));
assert(all(candidate.LLRMeanAbs>=0));
assert(all(mod(candidate.CCEIndex,candidate.AggregationLevel)==0));
assert(all(~candidate.GrantValid | candidate.SelectedCandidate));
assert(all(strlength(string(candidate.PayloadHash))>0));
% A selected H0 CRC pass MUST count. Labelled scoring fixture, not a
% manufactured physical false alarm used in any statistical table.
strict=b.Result.Config;
if isfield(strict,'ToolboxCarrier')
    cfg=strict;
else
    error('test:MissingStrictConfig','Mini anchor must expose installed strict config.');
end
det=struct('Rx',struct('Ok',false),'DecodedDCI',struct(), ...
    'Candidates',table(true,true,1,true,'VariableNames', ...
        {'CrcPass','SelectedCandidate','Metric','DecodeAttempted'}), ...
    'UsedOracleFields',"",'ProxyUsed',false,'Skipped',false,'ToolboxMissing',false);
scored=sixgr.phy.pdcch.scorePDCCHDetection(det,struct(),cfg, ...
    'TrialType','false_alarm_sweep','NegativeExpected',true);
assert(scored.FalseCandidateCount==1 && ~scored.NegativeExpectedOk);
ok=true; fprintf('PDCCH_CANDIDATE_MEASUREMENT_AUTHORITY_PASS\n');
end
