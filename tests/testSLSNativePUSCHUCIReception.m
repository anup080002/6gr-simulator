function ok=testSLSNativePUSCHUCIReception()
% Dedicated waveform receiver checks, not a statistical detector campaign.
% Receiver schema and transport size are established before TX generation.
cfg=sixgr.config.defaultConfig(); cfg.run.useMex=false;
cfg.phy.pusch.mcsTable='qam64_table1'; cfg.phy.pusch.transformPrecoding=false;
stream=RandStream('mt19937ar','Seed',71203); cases=0;
for rank=[1 2]
 for csiKind=["none","PUSCH","PUCCH"]
    hasCSI=csiKind~="none";
    cfg.phy.nTxAnt=rank; cfg.phy.nRxAnt=rank;
    cfg.channel.nTxAnt=rank; cfg.channel.nRxAnt=rank;
    cfg.phy.pusch.numLayers=rank; cfg.phy.pusch.nLayers=rank;
    c=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',30);
    p=nrPUSCHConfig('PRBSet',0:11,'NumLayers',rank,'Modulation','QPSK');
    p.DMRS.DMRSPortSet=0:rank-1;
    [~,grid]=nrPUSCHIndices(c,p);
    tbs=nrTBS('QPSK',rank,12,grid.NREPerPRB,.3,0);
    bits=int8(randi(stream,[0 1],tbs,1)); ack=int8([1;0;1]);
    schema=[]; first=int8([]); second=int8([]); reportID=""; epoch=NaN;
    if hasCSI
        request=struct('ReportConfigID',"independent_sls_receiver_check",'Epoch',0, ...
            'CodebookType',"typeI-SinglePanel",'Ports',4,'Rank',rank,'MaxRank',2, ...
            'N1',2,'N2',1,'O1',4,'O2',1,'CodebookMode',1, ...
            'ReportQuantity',"cri-RI-PMI-CQI",'NumCSIResources',3, ...
            'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
        request.ConfiguredUCIChannel=csiKind;
        schema=sixgr.phy.mimo.CSIReportConfiguration(request,0);
        [~,values]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,0);
        values.RI=rank; values.CRI=2; values.CQI_CW0=9;
        report=schema.build(values); first=report.Part1Bits; second=report.Part2Bits;
        reportID=request.ReportConfigID; epoch=0;
    end
    receive=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(struct( ...
        'ObservationID',"independent_schedule_not_tx_payload",'ConfigurationEpoch',0, ...
        'AssignmentDigest',"installed_receiver_fixture",'HARQMappingDigest',"three_issued_DL_assignments", ...
        'HARQACKBitCount',3,'ConfiguredGrantUCIBitCount',0, ...
        'CSIReportConfigID',reportID,'CSIConfigurationEpoch',epoch));
    payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',ack,'CSIPart1',first,'CSIPart2',second);
    tx=sixgr.phy.ul.PUSCH_Tx(cfg,'Carrier',c,'PUSCH',p, ...
        'TargetCodeRate',.3,'NumTxAnt',rank,'UCIPayload',payload, ...
        'TransportBlockBits',bits,'TransportBlockSizeOverride',tbs,'RV',0,'ExecutionProfile','phy_calibration');
    % Add a declared grid-domain variance through MATLAB's OFDM transform.
    % Identity channel is intentional; no fading or RF-array qualification.
    variance=1e-4; nfft=tx.OFDM.Nfft;
    noise=sqrt(variance/(2*nfft))*complex(randn(stream,size(tx.Waveform)),randn(stream,size(tx.Waveform)));
    rx=sixgr.phy.ul.PUSCH_Rx(tx.Waveform+noise,cfg,'Carrier',c,'PUSCH',p, ...
        'TransportBlockSize',tbs,'TargetCodeRate',.3,'RV',0,'InitialIMCSPerCodeword',0, ...
        'UCIReceiveContext',receive,'UCIReportConfiguration',schema, ...
        'NoiseVar',variance,'NoiseVarDomain','grid','SkipTimingEstimate',true,'ExecutionProfile','phy_calibration');
    assert(rx.Ok && ~rx.CRCError && isequal(rx.TransportBlock,bits));
    assert(isequal(rx.DecodedHARQACKBits,ack) && ~rx.UCIReferenceScoringAvailable);
    if hasCSI
        assert(isequal(rx.DecodedCSIPart1Bits,first) && isequal(rx.DecodedCSIPart2Bits,second));
    end
    cases=cases+1;
 end
end
fprintf('SLS_NATIVE_PUSCH_UCI_RX_PASS waveform_cases=%d statistical_qualification=0\n',cases); ok=true;
end
