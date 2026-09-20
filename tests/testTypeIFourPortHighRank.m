function ok=testTypeIFourPortHighRank()
% Four-port rank-3/4 formulas against independent R2026a codebook matrices.
% This qualifies the codebook/CSI codec, not RF or scheduler integration.
setup6GRSimToolkit('Verbose',false);
assert(string(version('-release'))=="2026a", ...
    'test:ReferenceRelease','Independent matrix reference is pinned to R2026a.');
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30);
csirs=nrCSIRSConfig('CSIRSType','nzp','RowNumber',4,'Density','one', ...
    'SymbolLocations',3,'SubcarrierLocations',0,'NumRB',24);
H=repmat(reshape(eye(4),1,1,4,4),288,14,1,1);
matrixCount=0; codecCount=0;
for mode=[1 2]
 for rank=[3 4]
    request=struct('ProfileID',"fr1_typeI_single_panel_strict", ...
        'Direction',"DL",'CodebookType',"typeI-SinglePanel", ...
        'Ports',4,'Panels',1,'N1',2,'N2',1,'O1',4,'O2',1, ...
        'Rank',rank,'CodebookMode',mode,'MaxRank',4, ...
        'ReportConfigID',"four_port_high_rank",'Epoch',1, ...
        'ReportQuantity',"cri-RI-LI-PMI-CQI",'NumCSIResources',3, ...
        'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
    reference=nrCSIReportConfig('NSizeBWP',24,'CodebookType','type1SinglePanel', ...
        'PanelDimensions',[1 2 1],'CodebookMode',mode,'PMIFormatIndicator','wideband');
    [~,info]=nr5g.internal.nrPMIReport(carrier,csirs,reference,rank,H,.1);
    expected=reshape(info.Codebook,4,rank,[]);
    actual=sixgr.phy.mimo.CodebookEngine.enumerate(request);
    assert(isequal(size(actual.Matrices),[4 rank 16]) && ...
        isequal(size(actual.Matrices),size(expected)));
    assert(max(abs(actual.Matrices(:)-expected(:)))<1e-12);
    assert(all(abs(actual.FrobeniusPower-1)<1e-12));
    assert(all(actual.OrthogonalityError<1e-12));
    first=[1 1 1 1;1 -1 1 -1;1 1 -1 -1;1 -1 -1 1]/sqrt(4*rank);
    assert(norm(actual.Matrices(:,:,1)-first(:,1:rank),'fro')<1e-12);
    capability=sixgr.phy.mimo.MIMOCapabilityProfile().resolve(request);
    assert(capability.EnumerationReady && ~capability.IndependentMatrixPackReady);
    cfg=sixgr.util.structSet(struct(),'phy.mimo',struct('strict',true, ...
        'profileID',request.ProfileID,'panels',1,'N1',2,'N2',1,'O1',4,'O2',1));
    cfg=sixgr.util.structSet(cfg,'phy.csi.reportConfiguration',request);
    candidates=sixgr.phy.dl.pmiCodebookCandidates(cfg,rank,4,'Mode','type1_su_mimo');
    assert(isequal(cat(3,candidates.W),actual.Matrices));
    for transport=["PUCCH","PUSCH"]
     request.UCIChannel=transport;
     for index=0:15
        [W,values]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,index);
        values.RI=rank; values.LI=rank-1; values.CRI=2; values.CQI_CW0=11;
        tx=sixgr.phy.mimo.CSIReportConfiguration(request,1);
        payload=tx.build(values); received=tx.encodeDecodeNoNoise(payload);
        assert(received.CRCPassed && received.Part1BitErrors+received.Part2BitErrors==0);
        rxRequest=request; rxRequest.Rank=1; % Received RI must override stale prior rank.
        rx=sixgr.phy.mimo.CSIReportConfiguration(rxRequest,1);
        decoded=rx.decode(received.Part1.Bits,received.Part2.Bits);
        assert(decoded.RI==rank && decoded.PMI==index && decoded.CRI==2);
        rxRequest.Rank=decoded.RI;
        restored=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(rxRequest,decoded.PMI);
        assert(norm(restored-W,'fro')==0);
        codecCount=codecCount+1;
     end
    end
    restricted=request; restricted.CodebookSubsetRestriction=[0 ones(1,7)];
    subset=sixgr.phy.mimo.CodebookEngine.enumerate(restricted);
    assert(isequal(subset.CandidateIndices,(2:15).'));
    localReject(@()sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(restricted,0), ...
        'sixgr:mimo:RestrictedPMI');
    unsupported=request; unsupported.Ports=8; unsupported.N1=4;
    localReject(@()sixgr.phy.mimo.TypeISinglePanelCodebook.layout(unsupported), ...
        'sixgr:mimo:UnsupportedRank');
    localReject(@()sixgr.phy.mimo.CSIReportConfiguration(unsupported,1), ...
        'sixgr:mimo:UnsupportedAntennaTuple');
    if rank==4
        % Exercise the production measurement -> selected RI -> typed report
        % boundary with the requested rank-2/rank-4 candidate restriction.
        measured=sixgr.phy.mimo.CSIMeasurementState( ...
            MeasurementID="analytic_four_port_fixture",UEID="UE-1", ...
            ResourceType="NZP-CSI-RS",ResourceID="CSI-RS-0",ResourceOrdinal=0, ...
            Slot=0,MaxAgeSlots=4,ChannelEstimate=eye(4),NoiseVariance=.001, ...
            Provenance="measured_input_fixture_analytic_identity_not_air_capture");
        request.Rank=2; request.AllowedRanks=[2 4];
        selection=struct('Strict',true,'RankDomain',[2 4],'MaxRank',4, ...
            'CQITable',"table1",'ReportConfiguration',request, ...
            'ReportConfigurationEpoch',1,'CurrentSlot',0);
        csi=sixgr.phy.mimo.NRCSIReportEngine.run( ...
            carrier,csirs,nrPDSCHDMRSConfig,H,.001,selection,measured);
        assert(csi.RI==4 && ~isempty(csi.CSIPart1Bits) && ~isempty(csi.CSIPart2Bits));
        prior=sixgr.phy.mimo.CSIReportConfiguration(request,1);
        received=prior.decode(csi.CSIPart1Bits,csi.CSIPart2Bits);
        assert(received.RI==4 && received.PMI==csi.PMI);
        request.Rank=received.RI;
        W=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,received.PMI);
        assert(isequal(W,csi.Precoder_W));
    end
    matrixCount=matrixCount+16;
 end
end
ok=true;
fprintf('TYPEI_FOUR_PORT_HIGH_RANK_PASS independent_matrices=%d received_PMI_roundtrips=%d measured_rank2_rank4_selection=2\n',matrixCount,codecCount);
end

function localReject(f,id)
try, f(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingError','Expected %s.',id);
end
