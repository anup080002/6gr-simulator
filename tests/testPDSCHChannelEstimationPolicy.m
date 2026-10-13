function ok=testPDSCHChannelEstimationPolicy()
% Configured estimator policy must execute, not silently become fixed LS.
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(824331,'twister');
fixture=StrictPDSCHChainFixture.create(2,'NPRB',6);
tx=sixgr.pdsch.PDSCHTransmitter(fixture.TransportBlocks,fixture.Assignment, ...
    fixture.ResourcePlan,fixture.Carrier,fixture.ReferenceConfig, ...
    'PrecoderBundle',fixture.PrecoderBundle);
wave=filter([1;.12i],1,tx.Waveform*[1 .1i;.05 .9]);
wave=wave+1e-4*complex(randn(size(wave)),randn(size(wave)));
receiver=rmfield(fixture.ReceiverConfig,'ReferenceChannelGain');
receiver.ChannelModel='TDL-C'; receiver.NPhysicalRxAntennas=2;
% This deterministic FIR checks the receiver policy, not TDL statistics.
baseline=localReceive(wave,fixture,tx,receiver);
windows=[0 0;1 1;9 1]; estimates=cell(3,1);
for k=1:size(windows,1)
    receiver.ChannelEstimationMethod='LS';
    receiver.ChannelEstimationAveragingWindow=windows(k,:);
    rx=localReceive(wave,fixture,tx,receiver);
    ref=sixgr.pdsch.PDSCHReferenceSignalGenerator.generate( ...
        fixture.Assignment,fixture.ResourcePlan,fixture.Carrier,fixture.ReferenceConfig);
    pdsch=ref.MaterializedPDSCH;
    [native,nvar]=nrChannelEstimate(fixture.Carrier,rx.OFDMGrid, ...
        nrPDSCHDMRSIndices(fixture.Carrier,pdsch),nrPDSCHDMRS(fixture.Carrier,pdsch), ...
        'CDMLengths',pdsch.DMRS.CDMLengths,'AveragingWindow',windows(k,:));
    assert(max(abs(native-rx.EffectiveLayerChannelEstimate),[],'all')<1e-12);
    assert(abs(nvar-rx.EstimatedNoiseVariance)<1e-12);
    assert(string(rx.ChannelEstimationInfo.Method)=="LS" && ...
        isequal(rx.ChannelEstimationInfo.RequestedAveragingWindow,windows(k,:)));
    assert(~rx.EstimatorUsesTrueChannel && ~rx.ChannelEstimationInfo.ScalarFastPathUsed);
    estimates{k}=rx.EffectiveLayerChannelEstimate;
    if k==1
        assert(isequal(rx.TransportBlock,baseline.TransportBlock) && ...
            isequal(rx.LayerSymbols,baseline.LayerSymbols));
    end
end
assert(norm(estimates{2}(:)-estimates{3}(:))>1e-6, ...
    'Configured averaging must alter the actual channel estimate, not just metadata.');
receiver.ChannelEstimationMethod='wiener';
receiver.ChannelEstimationAveragingWindow=[0 0];
rx=localReceive(wave,fixture,tx,receiver);
assert(string(rx.ChannelEstimationInfo.Method)=="wiener" && ...
    string(rx.ChannelEstimationInfo.EngineUsed)=="nrChannelEstimate");
receiver.ChannelEstimationMethod='lmmse';
localError(@()localReceive(wave,fixture,tx,receiver), ...
    'sixgr:phy:channelEstimate:LMMSECovarianceMissing');
for badMethod=["bogus","ideal",""]
    receiver.ChannelEstimationMethod=badMethod;
    localError(@()localReceive(wave,fixture,tx,receiver), ...
        'sixgr:pdsch:PDSCHReceiver:InvalidChannelEstimationMethod');
end
receiver.ChannelEstimationMethod='LS';
for invalidWindow={[2 0],[-1 0],[1 1 1],[NaN 1]}
    receiver.ChannelEstimationAveragingWindow=invalidWindow{1};
    localError(@()localReceive(wave,fixture,tx,receiver), ...
        'sixgr:pdsch:PDSCHReceiver:InvalidChannelEstimationAveragingWindow');
end
% Exercise YAML -> internal config -> fresh and cached production facades.
s=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/fixtures/lls_result_richness.yaml');
s=s.toStruct();
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
[tx,txInfo]=sixgr.phy.dl.PDSCH_Tx(cfg,'ExecutionProfile','phy_calibration','NumTxAnt',2);
s.receiver_algorithms.channel_estimation_method='wiener';
s.meta.config_hash=char(sixgr.lls6g.config.hashResolvedScenario(s));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
args={'ExecutionProfile','phy_calibration','Carrier',tx.Carrier,'PDSCH',tx.PDSCH, ...
    'PDSCHIndices',tx.PDSCHIndices,'CodingPlan',tx.CodingPlans,'SkipTimingEstimate',true, ...
    'NoiseVar',1e-8,'NoiseVarDomain','grid'};
fresh=sixgr.phy.dl.PDSCH_Rx(tx.Waveform,cfg,args{:});
cached=sixgr.phy.dl.PDSCH_Rx(tx.Waveform,cfg,args{:}, ...
    'CalibrationReceiverBundle',txInfo.CalibrationReceiverBundle);
assert(string(fresh.ChannelEstimation.Method)=="wiener" && ...
    string(cached.ChannelEstimation.Method)=="wiener");
assert(isequal(fresh.LayerSymbols,cached.LayerSymbols) && ...
    isequal(fresh.TransportBlock,cached.TransportBlock));
assert(cached.CalibrationReceiverBundleReused);
s.receiver_algorithms.channel_estimation_method='LS';
s.receiver_algorithms.pdsch_channel_estimation_averaging_window=[9 1];
s.meta.config_hash=char(sixgr.lls6g.config.hashResolvedScenario(s));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
fresh=sixgr.phy.dl.PDSCH_Rx(tx.Waveform,cfg,args{:});
cached=sixgr.phy.dl.PDSCH_Rx(tx.Waveform,cfg,args{:}, ...
    'CalibrationReceiverBundle',txInfo.CalibrationReceiverBundle);
assert(isequal(fresh.ChannelEstimation.RequestedAveragingWindow,[9 1]) && ...
    isequal(cached.ChannelEstimation.RequestedAveragingWindow,[9 1]) && ...
    isequal(fresh.LayerSymbols,cached.LayerSymbols));
s.receiver_algorithms.pdsch_channel_estimation_averaging_window=[2 0];
localError(@()sixgr.lls6g.buildInternalConfig(s,tempname), ...
    'sixgr:pdsch:PDSCHReceiver:InvalidChannelEstimationAveragingWindow');
ok=true;
end

function rx=localReceive(wave,f,tx,receiver)
rx=sixgr.pdsch.PDSCHReceiver(wave,f.Assignment,f.ResourcePlan,f.Carrier, ...
    f.ReferenceConfig,receiver,'CodingPlans',tx.CodingPlans,'PrecoderBundle',f.PrecoderBundle);
end

function localError(f,id)
try, f(); catch err, assert(strcmp(err.identifier,id),'Unexpected error %s: %s',err.identifier,err.message); return; end
error('testPDSCHChannelEstimationPolicy:MissingError','Expected rejection: %s',id);
end
