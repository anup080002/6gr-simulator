function ok=testPUSCHUCIResourceInvariance()
% Real public NR codec/resource APIs on declared LLR fixtures, not RF trials.
setup6GRSimToolkit('Verbose',false);
p=nrPUSCHConfig('PRBSet',0:11,'SymbolAllocation',[0 14], ...
    'NumLayers',1,'Modulation','QPSK','BetaOffsetACK',20, ...
    'BetaOffsetCSI1',6.25,'BetaOffsetCSI2',6.25);
cases=0;
for rank=[1 2]
 for tbs=[0 512]
    request=struct('ReportConfigID',"invariant_mapping_fixture",'Epoch',0, ...
        'CodebookType',"typeI-SinglePanel",'Ports',4,'Rank',rank,'MaxRank',2, ...
        'N1',2,'N2',1,'O1',4,'O2',1,'CodebookMode',1, ...
        'ReportQuantity',"cri-RI-PMI-CQI",'NumCSIResources',3, ...
        'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
    schema=sixgr.phy.mimo.CSIReportConfiguration(request,0);
    [~,values]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,0);
    values.RI=rank; values.CRI=2; values.CQI_CW0=9;
    report=schema.build(values);
    payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',int8([1;0;1;0;1]), ...
        'CSIPart1',report.Part1Bits,'CSIPart2',report.Part2Bits);
    sizeInfo=nrULSCHInfo(p,.3,tbs,5,numel(report.Part1Bits),numel(report.Part2Bits));
    data=int8(mod((1:sizeInfo.GULSCH).',2));
    encoded=sixgr.phy.ul.pusch.PUSCHUCIMultiplexer.multiplex(p,.3,tbs,data,payload,4);
    llr=100*(1-2*double(encoded.Codewords{1}));
    d=struct('ObservationID',"declared_mapping_probe",'ConfigurationEpoch',0, ...
        'AssignmentDigest',"declared_ul_grant",'HARQMappingDigest',"declared_five_dl_assignments", ...
        'HARQACKBitCount',5,'ConfiguredGrantUCIBitCount',0, ...
        'CSIReportConfigID',"invariant_mapping_fixture",'CSIConfigurationEpoch',0);
    context=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(d);
    plan=sixgr.phy.ul.pusch.inspectUCIResourceInvariance(p,.3,tbs,llr,context,4,schema);
    assert(plan.HARQMappingInvariant && plan.CSI1MappingInvariant);
    assert(~plan.PhysicalExecutionEvidence && plan.ReceiverContextDigest==context.Digest);
    assert(numel(plan.CandidateMaps)==numel(schema.part2BitCountCandidates()));
    % Changing received VALUES must not change any resource identity.
    other=sixgr.phy.ul.pusch.inspectUCIResourceInvariance(p,.3,tbs,-llr,context,4,schema);
    assert(isequaln(plan,other));
    for candidate=schema.part2BitCountCandidates()
        [mappedData,ack,first]=nrULSCHDemultiplex(p,.3,tbs,5, ...
            schema.part1BitCount(),candidate,llr);
        assert(isequal(ack,llr(plan.HARQSourceIndices1Based)) && ...
            isequal(first,llr(plan.CSI1SourceIndices1Based)));
        if plan.ULSCHMappingInvariant
            recovered=zeros(size(plan.ULSCHSourceIndices1Based{1}));
            index=plan.ULSCHSourceIndices1Based{1}; present=index>0;
            recovered(present)=llr(index(present));
            assert(isequal(recovered,mappedData));
        else
            assert(isempty(plan.ULSCHSourceIndices1Based{1}), ...
                'An unresolved UL-SCH map must not select one candidate as a fallback.');
        end
    end
    [ack,e]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(llr(plan.HARQSourceIndices1Based),5,'QPSK');
    assert(e.DecodeUsable && isequal(ack,payload.HARQACK));
    assert(~e.CRCApplicable && isnan(e.CRCPass));
    cases=cases+1;
 end
end
ok=true; fprintf('PUSCH_UCI_RESOURCE_INVARIANCE_PASS declared_cases=%d; no RF qualification.\n',cases);
end
