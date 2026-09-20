function ok=testResearchPUSCHSharedWaveform(widths,ranks,ackCounts,snrDB)
% Production TX/RX over the shared physical AWGN owner, not symbol-only replay.
% The fixture installs UL/feedback obligations directly: no PDCCH/coordinator
% qualification or 30-dB throughput claim follows from this bounded test.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
if nargin<1, widths=[25 264]; end
if nargin<2, ranks=[2 4]; end
if nargin<3, ackCounts=[0 1 2 5]; end
if nargin<4, snrDB=40; end
validateattributes(snrDB,{'numeric'},{'scalar','real','finite'});
policy=sixgr.lls6g.config.readConfigFile('simulator/configs/coding/research_pusch_uci.yaml');
old=rng; cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
rng(3821209,'twister'); cases=0;
for width=widths
 for rank=ranks
  for ackCount=ackCounts
    cfg=sixgr.config.defaultConfig();
    cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
    cfg.channel.pathlossEnabled=false; cfg.channel.shadowFadingEnabled=false;
    cfg.channel.sharedIdentityAWGNEnabled=true;
    cfg.channel.awgnReferenceREEnergy=.25;
    cfg.run.noiseOperatingMode='standalone_awgn_snr_argument'; cfg.channel.snr_dB=snrDB;
    cfg.phy.nTxAnt=4; cfg.phy.nRxAnt=4; cfg.channel.nTxAnt=4; cfg.channel.nRxAnt=4;
    cfg.scenario.ue.nTxAnt=4; cfg.antenna.ue.numElements=4;
    cfg.phy.carrier.NSizeGrid=width;
    scs=15; if width==264, scs=120; end
    cfg.phy.carrier.SubcarrierSpacing=scs; cfg.phy.carrier.SubcarrierSpacing_kHz=scs;
    cfg.phy.duplexMode='TDD'; cfg.frame.duplexMode='TDD'; cfg.channel.duplexMode='TDD';
    cfg.phy.pusch.transformPrecoding=false; cfg.phy.pusch.enablePTRS=false;
    cfg.phy.pusch.numLayers=rank; cfg.phy.pusch.nLayers=rank;
    cfg.phy.pusch.numAntennaPorts=4; cfg.phy.pusch.numPorts=4;
    cfg.phy.pusch.transmissionScheme='codebook'; cfg.phy.pusch.TPMI=0;
    cfg.phy.pusch.equalizer='MMSE'; cfg.phy.channelEstimation.method='LS';
    carrier=sixgr.phy.grid.makeCarrier(cfg);
    geometry=nrPUSCHConfig('NSizeBWP',width,'PRBSet',0:width-1, ...
        'NumLayers',rank,'NumAntennaPorts',4,'TransmissionScheme','codebook', ...
        'TPMI',0,'Modulation','QPSK','SymbolAllocation',[0 14],'NID',11,'RNTI',73);
    geometry.DMRS.DMRSPortSet=0:rank-1; geometry.DMRS.NumCDMGroupsWithoutData=2;
    geometry.DMRS.DMRSAdditionalPosition=1;
    txAdapter=sixgr.phy.research.PUSCHUCIResourceAdapter(policy,geometry,"1024QAM");
    request=struct('ReportConfigID',"shared_waveform_csi",'Epoch',1, ...
        'CodebookType',"typeI-SinglePanel",'Ports',4,'Rank',rank,'MaxRank',4, ...
        'N1',2,'N2',1,'O1',4,'O2',1,'CodebookMode',1, ...
        'ReportQuantity',"cri-RI-PMI-CQI",'NumCSIResources',3, ...
        'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
    schema=sixgr.phy.mimo.CSIReportConfiguration(request,1);
    [~,values]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,0);
    values.RI=rank; values.CRI=2; values.CQI_CW0=12; report=schema.build(values);
    ackBits=int8(mod((1:ackCount).',2));
    mappingID=""; if ackCount>0, mappingID="installed_DL_fixture_"+string(ackCount); end
    payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',ackBits, ...
        'CSIPart1',report.Part1Bits,'CSIPart2',report.Part2Bits);
    [tx,txInfo]=sixgr.phy.ul.PUSCH_Tx(cfg,'Carrier',carrier, ...
        'ResearchTransport',txAdapter,'TargetCodeRate',.5,'UCIPayload',payload, ...
        'InitialIMCSPerCodeword',0,'RV',0,'NumTxAnt',4);
    assert(tx.Modulation=="1024QAM" && tx.ResourceAccounting.Qm==10 && ...
        ~tx.StandardNR && tx.TxContext.PUSCH.Modulation=="1024QAM");
    assert(tx.G==size(tx.PUSCHLayerSymbols,1)*rank*10 && size(tx.Waveform,2)==4);
    state=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,'UL','UEIndex',1,'ServingCell',1);
    state.TargetUEIndex=1; state.TargetServingCell=1;
    state=sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
        state,cfg,tx.Waveform,txInfo,'NumTxAnt',4,'NumRxAnt',4);
    owner=sixgr.truth.SharedWaveformPhysicalRuntime(tx.OFDM.SampleRate,0,1);
    owner.addTransmitter('ue',cfg,'UL',4,false);
    owner.addReceiver('gnb',cfg,'UL',4,false);
    owner.addLink('identity','ue','gnb',state,cfg);
    input=struct('ID',"ue",'Chunk',sixgr.phy.waveform.WaveformChunk(tx.Waveform,0));
    [outputs,execution]=owner.process(input,0,size(tx.Waveform,1),[]);
    selected=outputs(string({outputs.ID})=="gnb:post_rf");
    assert(isscalar(selected));
    request.Rank=1; installed=sixgr.phy.mimo.CSIReportConfiguration(request,1);
    context=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(struct( ...
        'ObservationID',"shared_physical_fixture",'ConfigurationEpoch',1, ...
        'AssignmentDigest',"installed_UL_fixture",'HARQMappingDigest',mappingID, ...
        'HARQACKBitCount',ackCount,'ConfiguredGrantUCIBitCount',0, ...
        'CSIReportConfigID',"shared_waveform_csi",'CSIConfigurationEpoch',1));
    rxAdapter=sixgr.phy.research.PUSCHUCIResourceAdapter(policy,geometry,"1024QAM");
    % No TX UCI, coding layout or TX-derived CSI length enters the receiver.
    [~,idx]=nrPUSCHIndices(carrier,geometry);
    expectedTB=nrTBS('1024QAM',rank,width,idx.NREPerPRB,.5);
    [rx,rxInfo]=sixgr.phy.ul.PUSCH_Rx(selected.Chunk.Samples,cfg,'Carrier',carrier, ...
        'ResearchTransport',rxAdapter,'TransportBlockSize',expectedTB,'TargetCodeRate',.5, ...
        'RV',0,'InitialIMCSPerCodeword',0,'UCIReceiveContext',context, ...
        'UCIReportConfiguration',installed);
    assert(rx.Ok && ~rx.CRCError && isequal(rx.TransportBlock,tx.TransportBlock));
    assert(~rx.StandardNR && rx.Modulation=="1024QAM");
    assert(rx.CSIPresenceResolved && rx.CSIReportDetected && ...
        isequal(rx.DecodedHARQACKBits,payload.HARQACK) && ...
        isequal(rx.DecodedCSIPart1Bits,report.Part1Bits) && ...
        isequal(rx.DecodedCSIPart2Bits,report.Part2Bits));
    assert(~rx.UCIReferenceScoringAvailable && rx.UCIReceiveContextDigest==context.Digest);
    assert(execution.RX.Replay.GridNoiseVariance==.25*10^(-snrDB/10) && ...
        rx.ChannelEstimateAvailable && rx.EqualizationAvailable);
    errorGrid=sixgr.phy.waveform.ofdmDemodulate(carrier,selected.Chunk.Samples-tx.Waveform);
    empiricalNoise=mean(abs(errorGrid(:)).^2);
    reference=geometry; reference.TransmissionScheme='nonCodebook';
    receivedGrid=sixgr.phy.waveform.ofdmDemodulate(carrier,selected.Chunk.Samples);
    [~,directNoise]=nrChannelEstimate(carrier,receivedGrid, ...
        nrPUSCHDMRSIndices(carrier,reference),nrPUSCHDMRS(carrier,reference), ...
        'CDMLengths',reference.DMRS.CDMLengths);
    fprintf('SHARED_PUSCH_NOISE_DIAGNOSTIC empirical=%g receiver=%g direct_toolbox=%g source=%s cdm=%s timing=%g\n', ...
        empiricalNoise,rx.NoiseVar,directNoise,string(rx.NoiseVarSource), ...
        mat2str(rxInfo.ChannelEstimation.CDMLengths),rx.TimingOffset);
    assert(isequal(rxInfo.ChannelEstimation.CDMLengths,reference.DMRS.CDMLengths));
    assert(abs(empiricalNoise/execution.RX.Replay.GridNoiseVariance-1)<.08);
    assert(abs(rx.NoiseVar/directNoise-1)<.05 && ...
        abs(rx.NoiseVar/empiricalNoise-1)<.25, ...
        'Received noise must agree with actual samples and independently configured CDM estimation.');
    cases=cases+1;
    fprintf('RESEARCH_PRODUCTION_SHARED_PUSCH_PASS PRB=%d SCS=%g rank=%d ports=4 Qm=10 TBS=%d G=%d CRC=1 CSI=1 HARQACK_count=%d measured_nvar=%g reference_nvar=%g configured_reference_SNR_dB=%g code_rate=0.5\n', ...
        width,scs,rank,expectedTB,tx.G,ackCount,rx.NoiseVar,execution.RX.Replay.GridNoiseVariance,snrDB);
  end
 end
end
ok=true; fprintf('RESEARCH_PUSCH_SHARED_WAVEFORM_PASS cases=%d full_coordinator=0 missing_DCI_qualified=0\n',cases);
end
