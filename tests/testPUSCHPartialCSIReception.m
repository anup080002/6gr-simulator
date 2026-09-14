function ok=testPUSCHPartialCSIReception()
% Deliberately invalid CSI codec fixtures, not RF/detector qualification.
setup6GRSimToolkit('Verbose',false);
p=nrPUSCHConfig('PRBSet',0:11,'SymbolAllocation',[0 14], ...
    'NumLayers',1,'Modulation','QPSK','BetaOffsetACK',20, ...
    'BetaOffsetCSI1',6.25,'BetaOffsetCSI2',6.25);
cases=0;
for quantity=["cri-RI-PMI-CQI","cri-RI-CQI","cri-RI-LI-PMI-CQI"]
 for rank=[1 2]
  for tbs=[0 512]
    request=struct('ReportConfigID',"partial_csi_fixture",'Epoch',0, ...
        'CodebookType',"typeI-SinglePanel",'Ports',4,'Rank',rank,'MaxRank',2, ...
        'N1',2,'N2',1,'O1',4,'O2',1,'CodebookMode',1, ...
        'ReportQuantity',quantity,'NumCSIResources',3, ...
        'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
    schema=sixgr.phy.mimo.CSIReportConfiguration(request,0);
    % Four-port mode-1 PMI is five bits for BOTH ranks. LI contributes
    % zero/one bits for ranks one/two and creates a genuinely variable map.
    if quantity=="cri-RI-CQI"
        expectedPart2Counts=0;
    elseif quantity=="cri-RI-PMI-CQI"
        expectedPart2Counts=5;
    else
        expectedPart2Counts=[5 6];
    end
    assert(isequal(schema.part2BitCountCandidates(),expectedPart2Counts), ...
        'The authored negative fixture must exercise the intended Part-2 geometry.');
    [~,values]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,0);
    values.RI=rank; values.CRI=2; values.CQI_CW0=9;
    if contains(quantity,'-LI-'), values.LI=rank-1; end
    report=schema.build(values);
    % Literal spare CRI=3 for three resources. Production build rejects it;
    % only this negative codec fixture authors its invalid wire bits.
    invalid=report.Part1Bits; assert(schema.Part1Fields(1)=="CRI" && schema.Part1Widths(1)==2);
    invalid(1:2)=int8([1;1]);
    ack=int8([1;0;1;0;1]);
    payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',ack, ...
        'CSIPart1',invalid,'CSIPart2',report.Part2Bits);
    info=nrULSCHInfo(p,.3,tbs,5,numel(invalid),numel(report.Part2Bits));
    data=int8(mod((1:info.GULSCH).',2));
    encoded=sixgr.phy.ul.pusch.PUSCHUCIMultiplexer.multiplex(p,.3,tbs,data,payload,4);
    llr=100*(1-2*double(encoded.Codewords{1}));
    d=struct('ObservationID',"declared_partial_capture",'ConfigurationEpoch',0, ...
        'AssignmentDigest',"declared_grant",'HARQMappingDigest',"declared_five_assignments", ...
        'HARQACKBitCount',5,'ConfiguredGrantUCIBitCount',0, ...
        'CSIReportConfigID',"partial_csi_fixture",'CSIConfigurationEpoch',0);
    context=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(d);
    rx=sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.receive(p,.3,tbs,llr,context,4,schema);
    assert(rx.PartialReception && ~rx.CSIPart1Usable);
    assert(rx.CSIRejectionIdentifier=="sixgr:mimo:InvalidCRI");
    assert(isequal(rx.DecodedHARQACK,ack) && rx.UCIReceiverEvidence.HARQACK.DecodeUsable);
    assert(isequal(rx.DecodedCSIPart1,invalid));
    assert(rx.UCIReceiverEvidence.CSI1.DecodeUsable && ~rx.UCIReceiverEvidence.CSI1.SchemaUsable);
    assert(~rx.UCIReceiverEvidence.CSI1.CRCApplicable && isnan(rx.CSI1CRCOK));
    plan=rx.ResourceResolution;
    assert(isequal(rx.ULSCHMappingResolved,plan.ULSCHMappingInvariant));
    for candidate=schema.part2BitCountCandidates()
        [expected,expectedACK]=nrULSCHDemultiplex(p,.3,tbs,5,numel(invalid),candidate,llr);
        assert(isequal(rx.HARQACKLLR,expectedACK));
        if rx.ULSCHMappingResolved
            assert(isequal(rx.ULSCHLLR{1},expected));
        else
            assert(isempty(rx.ULSCHLLR{1}));
        end
    end
    if isscalar(expectedPart2Counts)
        assert(rx.ULSCHMappingResolved && rx.ResolvedCSI2BitCount==expectedPart2Counts);
        assert(rx.CSI2LengthAuthority=="single_length_in_active_report_configuration");
        assert(isequal(rx.DecodedCSIPart2,report.Part2Bits), ...
            'Fixed-length coded Part 2 remains observable despite invalid CSI semantics.');
        assert(~rx.CSIPart1Usable && ~rx.UCIReceiverEvidence.CSI1.SchemaUsable);
    else
        assert(numel(schema.part2BitCountCandidates())>1 && isnan(rx.ResolvedCSI2BitCount));
        assert(isempty(rx.DecodedCSIPart2) && isnan(rx.CSI2CRCOK));
        assert(~rx.UCIReceiverEvidence.CSI2AndConfiguredGrantUCI.DecodeAttempted);
    end
    [actual,adapter]=sixgr.phy.ul.pusch.receiveConfiguredUCI(llr,p,.3,tbs,context,4,schema);
    assert(isequaln(actual,rx.ULSCHLLR) && adapter.Status=="decoded_usable");
    assert(adapter.PartialReception && ~adapter.CSIPart1Usable);
    assert(~adapter.ReferenceScoringAvailable && ~isfield(rx,'HARQACKContentMatch'));
    % The old TX-reference adapter keeps its existing fail-loud contract.
    localReject(@()sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.demultiplex( ...
        p,.3,tbs,llr,payload,4,schema),'sixgr:mimo:InvalidCRI');
    request.Epoch=1;
    stale=sixgr.phy.mimo.CSIReportConfiguration(request,1);
    localReject(@()sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.receive( ...
        p,.3,tbs,llr,context,4,stale),'sixgr:pusch:CSIReceiveConfigurationMismatch');
    cases=cases+1;
  end
 end
end
ok=true; fprintf('PUSCH_PARTIAL_CSI_RECEPTION_PASS declared_codec_cases=%d; no RF qualification.\n',cases);
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
