function ok=testResearchPUSCHIndependentUCI()
% Existing independent receive/CSI-part-1 logic with explicit Qm=10 transport.
% Symbol-level execution, not integrated scheduling or RF detector qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
policy=sixgr.lls6g.config.readConfigFile('simulator/configs/coding/research_pusch_uci.yaml');
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(20260920,'twister'); cases=0;
for prbs=[25 264]
 for rank=[2 4]
    p=nrPUSCHConfig('NSizeBWP',prbs,'NStartBWP',0,'PRBSet',0:prbs-1, ...
        'NumLayers',rank,'SymbolAllocation',[0 14]);
    p.DMRS.DMRSPortSet=0:rank-1; p.DMRS.NumCDMGroupsWithoutData=2;
    carrier=nrCarrierConfig('NSizeGrid',prbs);
    [~,ri]=nrPUSCHIndices(carrier,p);
    tbs=nrTBS('1024QAM',rank,prbs,ri.NREPerPRB,.5);
    request=struct('ReportConfigID',"research_independent_csi",'Epoch',1, ...
        'CodebookType',"typeI-SinglePanel",'Ports',4,'Rank',rank,'MaxRank',4, ...
        'N1',2,'N2',1,'O1',4,'O2',1,'CodebookMode',1, ...
        'ReportQuantity',"cri-RI-PMI-CQI",'NumCSIResources',3, ...
        'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
    schema=sixgr.phy.mimo.CSIReportConfiguration(request,1);
    [~,values]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,0);
    values.RI=rank; values.CRI=2; values.CQI_CW0=12;
    report=schema.build(values);
    payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',int8([1;0;1;0;1]), ...
        'CSIPart1',report.Part1Bits,'CSIPart2',report.Part2Bits);
    txConfig=sixgr.phy.research.PUSCHUCIResourceAdapter(policy,p,"1024QAM");
    budget=txConfig.resourcePlan(.5,tbs,[5 numel(report.Part1Bits) numel(report.Part2Bits)]);
    data=int8(randi([0 1],budget.GULSCH,1));
    encoded=sixgr.phy.ul.pusch.PUSCHUCIMultiplexer.multiplex(txConfig,.5,tbs,data,payload,0);
    assert(~encoded.StandardNR && contains(encoded.Source,"experimental"));
    cw=encoded.Codewords{1};
    scrambled=nrPUSCHScramble(cw,11,73);
    symbols=nrSymbolModulate(scrambled,'1024QAM');
    variance=1e-4;
    samples=symbols+sqrt(variance/2)*(randn(size(symbols))+1j*randn(size(symbols)));
    llr=nrPUSCHDescramble(nrSymbolDemodulate(samples,'1024QAM',variance),11,73);
    rxConfig=sixgr.phy.research.PUSCHUCIResourceAdapter(policy,p,"1024QAM");
    rxRequest=request; rxRequest.Rank=1;
    rxSchema=sixgr.phy.mimo.CSIReportConfiguration(rxRequest,1);
    context=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(struct( ...
        'ObservationID',"research_symbol_capture",'ConfigurationEpoch',1, ...
        'AssignmentDigest',"installed_UL_assignment",'HARQMappingDigest',"installed_five_DL_assignments", ...
        'HARQACKBitCount',5,'ConfiguredGrantUCIBitCount',0, ...
        'CSIReportConfigID',"research_independent_csi",'CSIConfigurationEpoch',1));
    decoded=sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.receive( ...
        rxConfig,.5,tbs,llr,context,0,rxSchema);
    assert(~decoded.StandardNR && ~decoded.PartialReception && decoded.CSIPart1Usable && ...
        decoded.CSIPart1DecodedBeforePart2 && decoded.ReceiverContextDigest==context.Digest && ...
        isequal(decoded.DecodedHARQACK,payload.HARQACK) && ...
        isequal(decoded.DecodedCSIPart1,report.Part1Bits) && ...
        isequal(decoded.DecodedCSIPart2,report.Part2Bits));
    assert(numel(decoded.ULSCHLLR{1})==numel(data));
    received=struct('DecodedHARQACKBits',decoded.DecodedHARQACK, ...
        'UCIReceiverEvidence',decoded.UCIReceiverEvidence);
    observed=sixgr.truth.normalizeReceivedPUSCHHARQ(received,context);
    assert(observed.DecodeOk && observed.Source=="actual_experimental_Qm10_UCI_field_evidence");
    assert(sixgr.truth.puschCSIReceiverUsable(received,decoded.DecodedCSIPart1, ...
        decoded.DecodedCSIPart2,[numel(report.Part1Bits),numel(report.Part2Bits)]));
    erased=sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.receive( ...
        rxConfig,.5,tbs,zeros(size(llr)),context,0,rxSchema);
    assert(erased.PartialReception && ~erased.CSIPart1Usable && ...
        ~erased.UCIReceiverEvidence.HARQACK.DecodeUsable && ~erased.ULSCHMappingResolved);
    cases=cases+1;
 end
end
ok=true; fprintf('RESEARCH_PUSCH_INDEPENDENT_UCI_PASS cases=%d variable_CSI2=1 unresolved_CSI_fail_closed=1 shared_runtime=0\n',cases);
end
