function ok=testHARQProbeAWGNSpatialAuthority(gnbPorts,rank)
% Compare actual shared-channel and isolated HARQ sample paths. Holding the
% noise reference fixed must not erase the explicitly configured channel.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
if nargin==0
    assert(testHARQProbeAWGNSpatialAuthority(2,1));
    assert(testHARQProbeAWGNSpatialAuthority(4,1));
    assert(testHARQProbeAWGNSpatialAuthority(4,2));
    ok=true; return;
end
assert(ismember(gnbPorts,[2 4]) && ismember(rank,[1 2]));
baseMatrix=eye(2);
if gnbPorts==4
    scenario=sixgr.lls6g.config.loadScenarioConfig( ...
        'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
    target=sixgr.lls6g.buildInternalConfig(scenario,tempname);
    baseMatrix=target.channel.awgnSpatialMatrixDL;
    assert(isequal(size(baseMatrix),[2 4]));
end
cfg=sixgr.config.defaultConfig();
cfg.run.shortRun=true; cfg.outputs.saveFigures=false;
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
cfg.channel.pathlossEnabled=false; cfg.channel.shadowFadingEnabled=false;
cfg.channel.sharedIdentityAWGNEnabled=false;
cfg.channel.bandwidth_Hz=5e6; cfg.channel.awgnReferenceREEnergy=.25;
cfg.channel.snr_dB=30;
cfg.phy.carrier.NSizeGrid=25;
cfg.phy.carrier.SubcarrierSpacing=15; cfg.phy.carrier.SubcarrierSpacing_kHz=15;
cfg.phy.duplex.tddCommon=struct('ReferenceSubcarrierSpacingKHz',15, ...
    'Pattern1',struct('PeriodicityMilliseconds',5,'NumDownlinkSlots',3, ...
    'NumDownlinkSymbols',0,'NumUplinkSlots',1,'NumUplinkSymbols',0));
cfg.phy.duplex.tddDedicated=struct([]);
cfg.phy.ssb.enable=false; cfg.phy.csirs.enable=false; cfg.phy.csirs.enabled=false;
cfg.phy.harq.enable=true; cfg.phy.harq.validationMode='observation';
cfg.phy.nTxAnt=2; cfg.phy.nRxAnt=2;
cfg.channel.nTxAnt=2; cfg.channel.nRxAnt=2;
cfg.scenario.bs.nTxAnt=gnbPorts; cfg.scenario.bs.nRxAnt=gnbPorts;
cfg.scenario.ue.nTxAnt=2; cfg.scenario.ue.nRxAnt=2;
cfg.run.interferenceExecutionMode='none';
cfg.run.noiseOperatingMode='standalone_awgn_snr_argument';
cfg.phy.linkAdaptation.mode='fixed';
root=fullfile(pwd,'logs',['harq_spatial_authority_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(root); rows=table();
old=rng; restore=onCleanup(@()rng(old)); %#ok<NASGU>
for direction=["DL","UL"]
    if direction=="DL"
        key='pdsch'; numTx=gnbPorts; numRx=2;
    else
        key='pusch'; numTx=2; numRx=gnbPorts;
    end
    cfg.phy.nTxAnt=numTx; cfg.phy.nRxAnt=numRx;
    cfg.channel.nTxAnt=numTx; cfg.channel.nRxAnt=numRx;
    cfg.phy.(key).executionProfile='phy_calibration';
    cfg.phy.(key).enable=true; cfg.phy.(key).modulation='QPSK';
    cfg.phy.(key).codeRate=308/1024; cfg.phy.(key).mcsIndex=4;
    cfg.phy.(key).mcsTable='qam64_table1';
    cfg.phy.(key).prbSet=0:5; cfg.phy.(key).symbolAllocation=[0 10];
    cfg.phy.(key).mappingType='A';
    cfg.phy.(key).numPorts=numTx; cfg.phy.(key).nPorts=numTx; cfg.phy.(key).NumAntennaPorts=numTx;
    cfg.phy.(key).numLayers=rank; cfg.phy.(key).nLayers=rank;
    cfg.phy.(key).dmrs.portSet=0:rank-1; cfg.phy.(key).dmrs.DMRSPortSet=0:rank-1;
    cfg.phy.(key).dmrs.numCDMGroupsWithoutData=2;
    cfg.phy.(key).transmissionScheme='codebook';
    cfg.phy.(key).TPMI=0; cfg.phy.(key).PMI=0;
    cfg.phy.(key).transformPrecoding=false;
    cfg.phy.(key).codebookType='codebook1_ng1n4n1';
    for amplitude=[1 .5]
        cfg.channel.awgnSpatialMatrixDL=amplitude*baseMatrix;
        matrix=cfg.channel.awgnSpatialMatrixDL;
        if direction=="UL", matrix=matrix.'; end
        % Execute the main spatial operator independently of probe metadata.
        carrier=sixgr.phy.grid.makeCarrier(cfg); ofdm=nrOFDMInfo(carrier);
        state=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,direction,'UEIndex',1,'ServingCell',1);
        state=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(state,cfg,zeros(1,numTx), ...
            struct('OFDM',ofdm),'NumTxAnt',numTx,'NumRxAnt',numRx);
        x=reshape(complex(sin(1:100*numTx),cos(1:100*numTx)),100,numTx);
        y=sixgr.channel.ChannelFactory.applyRuntimeChannelState(state,x, ...
            'InputSampleDomain','materialized_channel_ports','OutputSampleAlignment','continuous_raw_samples');
        assert(norm(y-x*matrix.','fro')<1e-12);
        opt=struct('LinkSNR_dB',30,'LinkSNRGrid_dB',30,'HARQLivePreview',true, ...
            'HARQProbePackets',1,'HARQProbeDirections',direction);
        rng(220930,'twister'); % Identical bits/noise seed, only the channel differs.
        artifact=sixgr.truth.exportLLSHARQDiagnostics(cfg, ...
            fullfile(root,sprintf('%s_amplitude_%g',direction,amplitude),'air_interface'),opt);
        T=artifact.PacketTable;
        assert(height(T)==1 && T.CurrentDecodeOK && T.CombinedDecodeOK);
        assert(T.ChannelTxPortCount==numTx && T.ChannelRxBranchCount==numRx && ...
            T.ChannelSampleOperatorSource=="explicit_matrix_AWGN_shared_sample_operator" && ...
            T.ChannelSpatialMatrixSHA256==sixgr.phy.mimo.MatrixContract.digest(matrix));
        assert(abs(10*log10(T.MeasuredInjectedGridNoiseVariance/T.GridNoiseVariance))<.5);
        row=table(direction,gnbPorts,rank,amplitude,mean(abs(y).^2,'all'), ...
            T.MeasuredSignalEnergyPerOccupiedRE,T.GridNoiseVariance, ...
            'VariableNames',{'Direction','GNBPorts','Rank','ChannelAmplitude','SharedChannelMeasuredPower', ...
            'ProbeMeasuredSignalEnergy','ProbeGridNoiseVariance'});
        rows=[rows;row]; %#ok<AGROW>
        writetable(rows,fullfile(root,'spatial_authority.csv'));
    end
end
disp(rows); fprintf('HARQ_SPATIAL_AUTHORITY_EVIDENCE=%s\n',root);
for direction=["DL","UL"]
    T=rows(rows.Direction==direction,:);
    sharedRatio=T.SharedChannelMeasuredPower(2)/T.SharedChannelMeasuredPower(1);
    probeRatio=T.ProbeMeasuredSignalEnergy(2)/T.ProbeMeasuredSignalEnergy(1);
    assert(all(abs(T.ProbeGridNoiseVariance-.25e-3)<1e-12));
    assert(abs(probeRatio-sharedRatio)<1e-12, ...
        'test:HARQProbeAWGNSpatialOperatorBypassed', ...
        '%s: main channel power ratio=%g, probe ratio=%g; fixed noise must not erase the channel.', ...
        direction,sharedRatio,probeRatio);
end
ok=true;
end
