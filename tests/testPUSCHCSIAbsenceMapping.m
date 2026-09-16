function ok=testPUSCHCSIAbsenceMapping()
% Public demultiplexer index/codec fixtures, not an RF qualification.
setup6GRSimToolkit('Verbose',false);
p=nrPUSCHConfig('PRBSet',0:11,'SymbolAllocation',[0 14], ...
    'NumLayers',1,'Modulation','QPSK','BetaOffsetACK',20, ...
    'BetaOffsetCSI1',6.25,'BetaOffsetCSI2',6.25);
carrier=nrCarrierConfig('NSizeGrid',12);
[~,gridInfo]=nrPUSCHIndices(carrier,p);
request=struct('ReportConfigID',"absent_csi_mapping",'Epoch',0, ...
    'CodebookType',"typeI-SinglePanel",'Ports',4,'Rank',1,'MaxRank',2, ...
    'N1',2,'N2',1,'O1',4,'O2',1,'CodebookMode',1, ...
    'ReportQuantity',"cri-RI-LI-PMI-CQI",'NumCSIResources',3, ...
    'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
schema=sixgr.phy.mimo.CSIReportConfiguration(request,0);
cases=0; erasureCases=0;
for tbs=[0 512]
 for ackCount=[0 1 2 4 11 12]
  for cgCount=[0 2]
    mapping=""; if ackCount>0, mapping="declared_harq_mapping"; end
    d=struct('ObservationID',"declared_absent_csi_capture",'ConfigurationEpoch',0, ...
        'AssignmentDigest',"declared_grant",'HARQMappingDigest',mapping, ...
        'HARQACKBitCount',ackCount,'ConfiguredGrantUCIBitCount',cgCount, ...
        'CSIReportConfigID',schema.ReportConfigID,'CSIConfigurationEpoch',schema.Epoch);
    context=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(d);
    labels=(1:gridInfo.G).';
    plan=sixgr.phy.ul.pusch.inspectUCIResourceInvariance(p,.3,tbs,labels,context,4,schema);
    assert(isequal(plan.CandidateCSIInformationBitCounts, ...
        [0 0; schema.part1BitCount() 5; schema.part1BitCount() 6]));
    assert(~plan.PhysicalExecutionEvidence && ~plan.CSI1MappingInvariant);
    for k=1:numel(plan.CandidateMaps)
        candidate=plan.CandidateMaps{k};
        first=candidate.Part1BitCount; second=candidate.Part2BitCount;
        if ackCount+first+second+cgCount==0
            data=labels; if tbs==0, data=zeros(0,1); end
            ack=zeros(0,1); csi1=ack; combined=ack;
        else
            [data,ack,csi1,combined]=nrULSCHDemultiplex( ...
                p,.3,tbs,ackCount,first,second+cgCount,labels);
        end
        assert(isequal(candidate.HARQ,ack) && isequal(candidate.CSI1,csi1) && ...
            isequal(candidate.CSI2AndCGUCI,combined) && isequal(candidate.ULSCH{1},data));
        assert(candidate.CSI2AndCGUCIBitCount==second+cgCount, ...
            'CSI absence must not delete an independently configured CG-UCI obligation.');
    end
    first=plan.CandidateMaps{1};
    sameACK=all(cellfun(@(x)isequal(x.HARQ,first.HARQ),plan.CandidateMaps));
    sameData=all(cellfun(@(x)isequal(x.ULSCH,first.ULSCH),plan.CandidateMaps));
    sameCombined=all(cellfun(@(x)x.CSI2AndCGUCIBitCount==first.CSI2AndCGUCIBitCount && ...
        isequal(x.CSI2AndCGUCI,first.CSI2AndCGUCI),plan.CandidateMaps));
    erasureCases=erasureCases+any(cellfun(@(x)any(x.CSI2AndCGUCI==0),plan.CandidateMaps));
    assert(plan.HARQMappingInvariant==sameACK && plan.ULSCHMappingInvariant==sameData && ...
        plan.CSI2AndCGUCIMappingInvariant==sameCombined);
    if ~sameData, assert(isempty(plan.ULSCHSourceIndices1Based{1})); end
    if ~sameCombined, assert(isempty(plan.CSI2AndCGUCISourceIndices1Based)); end
    poisoned=sixgr.phy.ul.pusch.inspectUCIResourceInvariance(p,.3,tbs,-labels,context,4,schema);
    assert(isequaln(plan,poisoned),'Received values must not choose the resource-map domain.');
    cases=cases+1;
  end
 end
end
assert(erasureCases>0,'Exercise actual public-demultiplexer CSI2 puncturing erasures.');
% Actual public UCI coding with absent CSI. This direct partial-path check
% declares unresolved presence; it does not qualify the normal success-path
% presence selector (still a separate integration requirement).
d.HARQACKBitCount=4; d.HARQMappingDigest="declared_four_assignments";
d.ConfiguredGrantUCIBitCount=0;
context=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(d);
payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',int8([1;0;1;0]));
info=nrULSCHInfo(p,.3,512,4,0,0);
encoded=sixgr.phy.ul.pusch.PUSCHUCIMultiplexer.multiplex( ...
    p,.3,512,int8(mod((1:info.GULSCH).',2)),payload,4);
llr=100*(1-2*double(encoded.Codewords{1}));
reason=MException('sixgr:pusch:UnresolvedReceivedCSIPart1','Declared unresolved CSI-presence fixture.');
partial=sixgr.phy.ul.pusch.receiveInvariantUCI(p,.3,512,llr,context,4,schema,reason);
assert(partial.UCIReceiverEvidence.HARQACK.DecodeUsable && ...
    isequal(partial.DecodedHARQACK,payload.HARQACK));
assert(~partial.ULSCHMappingResolved && isempty(partial.ULSCHLLR{1}) && ...
    ~partial.CSIPart1Usable && ~partial.CSIPresenceResolved && ...
    isempty(partial.DecodedCSIPart1) && isempty(partial.DecodedCSIPart2));
fprintf('PUSCH_CSI_ABSENCE_MAPPING_PASS index_cases=%d erasure_cases=%d actual_UCI_codec=1 RF_qualification=0\n', ...
    cases,erasureCases);
ok=true;
end
