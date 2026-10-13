function ok=testGrantCalibrationReference(storageMode)
% Real AWGN references and fading targets keep separate physical identities.
arguments
    storageMode (1,1) string="lossless_path_gains_xor_v1"
end
cfg=localConfig();
source=sixgr.calibration.grantSourceIdentity();
sixgr.calibration.assertGrantSourceIdentity(source);
badSource=source; badSource.SHA256(1)=repmat('0',1,64);
localReject(@()sixgr.calibration.assertGrantSourceIdentity(badSource), ...
    'sixgr:calibration:GrantSourceChanged');
badSource=source; badSource.MATLAB='different_execution_environment';
localReject(@()sixgr.calibration.assertGrantSourceIdentity(badSource), ...
    'sixgr:calibration:GrantSourceChanged');
for direction=["DL","UL"]
    grant=localGrant(cfg,direction);
    referenceCfg=cfg;
    referenceCfg.channel=struct('model','AWGN','awgnOnly',true,'nTxAnt',2,'nRxAnt',2);
    plan=localPlan(grant,10000+1000*double(direction=="UL"));
    referenceFolder=tempname(fullfile(pwd,'logs'));
    r=sixgr.system.waveform.collectGrantCalibrationEpisodes(referenceCfg,plan,referenceFolder, ...
        'MaximumNewEpisodes',4);
    assert(r.CompletedEpisodes==4 && ~r.CalibrationQualified);
    referenceKey=localReadKey(referenceFolder);
    localVerifySampleTiming(referenceFolder,direction);
    targetPlan=plan;
    for k=1:numel(targetPlan)
        for name=string(fieldnames(targetPlan(k).Seeds)).'
            targetPlan(k).Seeds.(name)=targetPlan(k).Seeds.(name)+10000;
        end
    end
    targetFolder=tempname(fullfile(pwd,'logs'));
    t=sixgr.system.waveform.collectGrantCalibrationEpisodes(cfg,targetPlan,targetFolder, ...
        'MaximumNewEpisodes',4,'EvidenceStorage',storageMode);
    assert(t.CompletedEpisodes==4 && ~t.CalibrationQualified);
    targetKey=localReadKey(targetFolder);
    [reference,heldout,proof]=sixgr.calibration.readGrantCalibrationReference( ...
        referenceFolder,referenceKey,targetKey,0);
    assert(isequal(reference.TrialCount,[1;1]) && isequal(heldout.TrialCount,[1;1]) && ...
        ~proof.ReferenceChannelRelabeledAsTarget && ...
        reference.ReferencePhysicalKey.ChannelProfile=="AWGN" && ...
        reference.TargetRuntimeKey.ChannelProfile=="TDL-A" && ...
        reference.ReferencePhysicalKeySHA256~=reference.ConfigurationSHA256);
    fprintf('GRANT_REFERENCE_MEASURED_AXIS direction=%s configured=[-3,3] measured=%s\n', ...
        direction,jsonencode(reference.SINRAxes_dB{1}));
    % Unit-Frobenius rank-two precoding splits power equally. The reference
    % axis must be per-layer SINR, not the configured aggregate Es/N0 label.
    assert(max(abs(reference.SINRAxes_dB{1}-([-3;3]-10*log10(2))))<1e-8);
    for field=["Rank","TBSBits"]
        bad=targetKey; bad.(field)=bad.(field)+1;
        localReject(@()sixgr.calibration.readGrantCalibrationReference( ...
            referenceFolder,referenceKey,bad,0),'sixgr:calibration:ReferenceKeyMismatch');
    end
    bad=targetKey; bad.ReceiverProfileID="different_decoder";
    localReject(@()sixgr.calibration.readGrantCalibrationReference( ...
        referenceFolder,referenceKey,bad,0),'sixgr:calibration:ReferenceKeyMismatch');
    bad=targetKey; bad.AllocationSHA256="different_allocation";
    localReject(@()sixgr.calibration.readGrantCalibrationReference( ...
        referenceFolder,referenceKey,bad,0),'sixgr:calibration:ReferenceKeyMismatch');
    bad=targetKey; bad.EffectiveSINRMethod="calibrated_miesm";
    localReject(@()sixgr.calibration.fitGrantCalibrationCollections( ...
        referenceFolder,targetFolder,referenceKey,bad,0,struct()), ...
        'sixgr:calibration:GrantFittingMethod');
    % Four real episodes are a component test, never a qualified BLER curve.
    q=struct('minimum_conditional_trials',2000,'confidence_level',0.95, ...
        'maximum_wilson_half_width',0.025,'maximum_validation_absolute_bler_error',0.02, ...
        'beta_linear_bounds',[0.01 100],'beta_log_grid_count',21, ...
        'minimum_beta_objective_contrast',1e-6);
    localReject(@()sixgr.calibration.fitGrantCalibrationCollections( ...
        referenceFolder,targetFolder,referenceKey,targetKey,0,q), ...
        'sixgr:calibration:ReferenceValidationGrid');
    assert(isequal(proof.HARQSlotOffsets0,0));
    % The install path must rerun evidence/statistical checks, not accept
    % sealed-but-underpopulated physical episodes as a production curve.
    [~,refName]=fileparts(referenceFolder); [~,targetName]=fileparts(targetFolder);
    collection=struct('CurveID',"reference_pair_"+direction, ...
        'ReferenceFolder',string(refName),'TargetFolder',string(targetName), ...
        'ReferenceManifestSHA256',sixgr.csi.studyFileSHA256(fullfile(referenceFolder,'campaign.mat')), ...
        'TargetManifestSHA256',sixgr.csi.studyFileSHA256(fullfile(targetFolder,'campaign.mat')), ...
        'ReferenceKey',referenceKey,'TargetKey',targetKey,'RVSequence',0,'FittingPolicy',q);
    package=struct('CalibrationID',"underpopulated_physical_component_test",'Collections',collection);
    output=string(tempname(fullfile(pwd,'logs')))+".mat";
    installPolicy=cfg.system.linkAbstraction;
    localReject(@()sixgr.system.abstraction.buildGrantCalibrationPackage(package,installPolicy,output), ...
        'sixgr:calibration:ReferenceValidationGrid');
    assert(~isfile(output),'An unqualified collection must never produce an installed package.');
    bad=collection; bad.ReferenceManifestSHA256=repmat('0',1,64);
    localReject(@()sixgr.system.abstraction.reconstructGrantCalibrationCurve(bad,installPolicy,fullfile(pwd,'logs')), ...
        'sixgr:abstraction:CalibrationDigest');
    bad=collection; bad.ReferenceFolder="..";
    localReject(@()sixgr.system.abstraction.reconstructGrantCalibrationCurve(bad,installPolicy,fullfile(pwd,'logs')), ...
        'sixgr:abstraction:GrantCalibrationSource');
    bad=collection; bad.FittingPolicy.minimum_conditional_trials=1;
    localReject(@()sixgr.system.abstraction.reconstructGrantCalibrationCurve(bad,installPolicy,fullfile(pwd,'logs')), ...
        'sixgr:abstraction:GrantCalibrationPolicy');
    fprintf('GRANT_REFERENCE_PAIR_PASS direction=%s independent_awgn_episodes=4 target_episodes=4 qualification=0\n',direction);
end
ok=true;
end

function localVerifySampleTiming(folder,direction)
rows=readtable(fullfile(folder,'waveform_trials.csv'),'TextType','string');
shifted=false; outOfWindow=0;
for k=1:height(rows)
    saved=load(fullfile(folder,rows.EpisodeRelativePath(k)),'episode');
    e=saved.episode.Captures{1}; timing=e.Receiver.AppliedTimingCorrection_samples;
    assert(e.Noise.ReferenceSymbolPlane=="mean_preprecoding_layer_symbol_energy" && ...
        abs(e.Noise.TransmittedSignalEnergyPerOccupiedRE-1)<1e-12, ...
        'Matched QPSK DL/UL must use the same pre-precoding symbol energy plane.');
    shifted=shifted || timing~=0;
    [feature,H]=sixgr.system.waveform.extractGrantCalibrationPredictor(e,"lmmse", ...
        'Plane',"scheduled_nominal_fft_before_receiver_sync");
    assert(feature.ActualReceiverTimingCorrection_samples==timing && ...
        feature.PredictorFFTOffsetFromChannelOrigin_samples==0 && ...
        feature.PredictorPlane==e.CalibrationReceiverIdentity.PredictorPlane && ...
        saved.episode.Attempts(1).CRCError==any(logical(e.Receiver.CRCError)), ...
        'Nominal predictor must preserve actual receiver timing and CRC outcomes.');
    wave=e.Transmitter.Waveform;
    wave=wave*e.AppliedImpairments.AppliedLargeScaleAmplitudeGain;
    ofdm=e.ReceiverOFDMInfo;
    measured=nrOFDMDemodulate(e.Transmitter.Carrier,wave,'Nfft',ofdm.Nfft, ...
        'SampleRate',ofdm.SampleRate,'CyclicPrefixFraction',ofdm.CyclicPrefixFraction);
    predicted=complex(zeros(size(H,1),size(H,2),size(H,3)));
    for rx=1:size(H,3)
        for tx=1:size(H,4)
            predicted(:,:,rx)=predicted(:,:,rx)+H(:,:,rx,tx).*e.Transmitter.Grid(:,:,tx);
        end
    end
    ix=e.DataREMap.PhysicalIndices1Based;
    a=reshape(predicted,[],size(H,3)); b=reshape(measured,[],size(H,3));
    error=norm(a(ix,:)-b(ix,:),'fro')/norm(b(ix,:),'fro');
    assert(error<1e-10,'Nominal AWGN predictor differs from independent sample-domain FFT: %g',error);
    fprintf('GRANT_REFERENCE_NOMINAL_FFT direction=%s actual_rx_timing=%g relative_error=%g crc_error=%d\n', ...
        direction,timing,error,saved.episode.Attempts(1).CRCError);
    % The separate receiver-plane diagnostic may reject ISI/ICI windows;
    % that is not permission to omit the waveform from pre-sync calibration.
    try
        sixgr.system.waveform.extractGrantCalibrationPredictor(e,"lmmse");
    catch err
        assert(strcmp(err.identifier,'sixgr:calibration:GrantPredictorTimingWindow'));
        outOfWindow=outOfWindow+1;
    end
    bad=e; invalid=ofdm.Nfft;
    bad.Receiver.AppliedTimingCorrection_samples=invalid;
    bad.Receiver.ReceiverChannelOperator.AppliedTimingCorrection_samples=invalid;
    localReject(@()sixgr.system.waveform.extractGrantCalibrationPredictor(bad,"lmmse"), ...
        'sixgr:calibration:GrantPredictorTimingWindow');
end
if direction=="UL"
    assert(shifted && outOfWindow>0, ...
        'Keep the original low-SNR seeds exercising out-of-window timing; do not hide these outcomes.');
end
end

function key=localReadKey(folder)
rows=readtable(fullfile(folder,'waveform_trials.csv'),'TextType','string');
saved=load(fullfile(folder,rows.EpisodeRelativePath(1)),'episode');
manifest=load(fullfile(folder,'campaign.mat'),'storageMode');
episode=sixgr.calibration.decodeGrantEpisodeStorage(saved.episode,manifest.storageMode);
key=episode.CalibrationBindings{1};
end

function plan=localPlan(grant,seed)
entries=cell(1,4);
for k=1:4
    role="fit"; if k>2, role="validation"; end
    snr=-3; if mod(k,2)==0, snr=3; end
    g=grant; g.TransportBlockIdentity="reference_pair_"+seed+"_"+k;
    s=seed+10*k;
    entries{k}=struct('EpisodeID',"reference_pair_"+k,'Role',role,'Grants',{{g}}, ...
        'SNRdB',snr,'Seeds',struct('Bits',s,'Noise',s+1,'Channel',s+2,'ControlNoise',s+3,'RF',s+4));
end
plan=[entries{:}];
end

function g=localGrant(cfg,direction)
carrier=sixgr.phy.grid.makeCarrier(cfg);
if direction=="DL"
    [~,info,channel]=sixgr.phy.grid.allocREsPDSCH(carrier,cfg,'RNTI',73);
else
    [~,info,channel]=sixgr.phy.grid.allocPUSCHTransport(carrier,cfg,'RNTI',73);
end
if isfield(info,'IndicesInfo'), info=info.IndicesInfo; end
rate=cfg.phy.pdsch.codeRate;
tbs=double(nrTBS('QPSK',2,numel(channel.PRBSet),info.NREPerPRB,rate,0));
g=struct('Direction',char(direction),'Frame',0,'Slot',0,'ScheduledAbsoluteSlot',0, ...
    'RNTI',73,'UEIndex',1,'ServingCell',1,'PRBSet',0:5,'SymbolAllocation',[2 10], ...
    'Modulation','QPSK','NumLayers',2,'Layers',2,'NumLogicalPorts',2,'NumRFChains',2, ...
    'TargetCodeRate',rate,'MCSIndex',1,'MCSTable','qam64_table1','TBSBits',tbs, ...
    'RV',0,'IsRetransmission',false,'XOverhead',0,'NREPerPRB',info.NREPerPRB, ...
    'PrecodingMatrixLogicalPorts',eye(2)/sqrt(2),'PrecodingMatrix',eye(2)/sqrt(2), ...
    'PrecoderNormalizationConvention','unit_frobenius','PrecoderSource','reference_pair_regression');
g.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,direction,g,'Frame',0,'Slot',0);
end

function cfg=localConfig()
cfg=sixgr.config.defaultConfig();
p=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
cfg=sixgr.util.mergeStruct(cfg,p);
cfg.run.strictMode=true; cfg.run.useMex=false;
cfg.run.pdschExecutionProfile='phy_calibration'; cfg.run.puschExecutionProfile='phy_calibration';
cfg.phy.carrier.NSizeGrid=24; cfg.phy.carrier.NStartGrid=0; cfg.phy.carrier.SubcarrierSpacing=30;
cfg.phy.numerology.scs_kHz=30; cfg.phy.duplex.mode='TDD'; cfg.phy.fc_Hz=4e9;
cfg.phy.nTxAnt=2; cfg.phy.nRxAnt=2; cfg.phy.ldpc.maxIterations=100;
cfg.scenario.bs.nTxAnt=2; cfg.scenario.bs.nRxAnt=2;
cfg.scenario.ue.nTxAnt=2; cfg.scenario.ue.nRxAnt=2;
cfg.antenna.bs.numElements=2; cfg.antenna.bs.numRFChains=2;
cfg.antenna.ue.numElements=2; cfg.antenna.ue.numRFChains=2;
cfg.rf=struct(); cfg.phy.impairments=struct();
cfg.phy.beamManagement.hybridBeamformingEnabled=false;
cfg.phy.ssb.enable=false; cfg.phy.csirs.enable=false; cfg.phy.trs.enable=false;
cfg.phy.csiim.enable=false; cfg.phy.ptrs.enable=false;
cfg.channel=struct('model','TDL-A','tdlProfile','TDL-A','delaySpread_s',30e-9, ...
    'doppler_Hz',0,'normalizeChannelOutputs',false,'awgnOnly',false,'nTxAnt',2,'nRxAnt',2);
mcs=sixgr.link.resolveMCSProfile('qam64_table1',1);
for name=["pdsch","pusch"]
    cfg.phy.(name).modulation='QPSK'; cfg.phy.(name).codeRate=mcs.TargetCodeRate;
    cfg.phy.(name).mcsTable='qam64_table1'; cfg.phy.(name).mcsIndex=1;
    cfg.phy.(name).numPorts=2; cfg.phy.(name).nPorts=2;
    cfg.phy.(name).numLayers=2; cfg.phy.(name).nLayers=2; cfg.phy.(name).dmrs.portSet=0:1;
    cfg.phy.(name).enablePTRS=false; cfg.phy.(name).xOverhead=0;
    cfg.phy.(name).prbSet=0:5; cfg.phy.(name).symbolAllocation=[2 10];
end
cfg.phy.pusch.transformPrecoding=false;
cfg.system.linkAbstraction.spatialProviderClass='sixgr.system.abstraction.NetworkSpatialGrantProvider';
cfg.system.linkAbstraction.networkSpatial.bsPorts=2;
cfg.system.linkAbstraction.networkSpatial.uePorts=2;
cfg.system.linkAbstraction.networkSpatial.dlAntennaBasis='direct_ports';
cfg.system.linkAbstraction.networkSpatial.sinrResourcePopulation='native_shared_channel_data_re';
end

function localReject(fn,id)
try, fn(); catch err, assert(strcmp(err.identifier,id),'Unexpected rejection: %s',err.identifier); return; end
error('testGrantCalibrationReference:MissingRejection','Expected %s.',id);
end
