function ok=testSLSWaveformChannelIdentity(options)
% Exact native fading recipe across model/actual waveform, including 4x2 UL.
arguments
    options.DopplerHz (1,1) double=0
    options.AbsoluteSlot (1,1) double=0
    options.RetryCollection (1,1) logical=false
    options.SubcarrierSpacing (1,1) double=30
end
cfg=localConfig();
cfg.channel.doppler_Hz=options.DopplerHz;
cfg.phy.carrier.SubcarrierSpacing=options.SubcarrierSpacing;
cfg.phy.numerology.scs_kHz=options.SubcarrierSpacing;
nativeCarrier=sixgr.phy.grid.makeCarrier(cfg);
slotsPerFrame=nativeCarrier.SlotsPerFrame;
absoluteSlot=options.AbsoluteSlot;
frame=floor(absoluteSlot/slotsPerFrame); slot=mod(absoluteSlot,slotsPerFrame);
nativeInfo=nrOFDMInfo(nativeCarrier);
slotSamples=sum(reshape(nativeInfo.SymbolLengths,nativeCarrier.SymbolsPerSlot,[]),1);
% Independent expected boundary from the native subframe symbol vector.
expectedTime=(floor(absoluteSlot/nativeCarrier.SlotsPerSubframe)*sum(slotSamples)+ ...
    sum(slotSamples(1:mod(absoluteSlot,nativeCarrier.SlotsPerSubframe))))/nativeInfo.SampleRate;
for profile=["TDL-A","CDL-C"]
    cfg.channel.model=char(profile);
    cfg.channel=rmfield(cfg.channel,intersect(fieldnames(cfg.channel),{'tdlProfile','cdlProfile'}));
    if profile=="TDL-A", cfg.channel.tdlProfile=char(profile);
    else, cfg.channel.cdlProfile=char(profile); end
    provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
    hash=char(sixgr.util.sha256Hex(uint8(char(string(cfg.run.seed)+"_network_link_1_1"))));
    seed=mod(hex2dec(hash(1:8)),2^32-1);
    for direction=["DL","UL"]
        ntx=4; if direction=="UL", ntx=2; end
        W=eye(ntx,2)/sqrt(2);
        grant=struct('Direction',char(direction),'Frame',frame,'Slot',slot,'ScheduledAbsoluteSlot',absoluteSlot, ...
            'RNTI',1,'UEIndex',1,'ServingCell',1,'PRBSet',0:5,'SymbolAllocation',[2 10], ...
            'Modulation','QPSK','NumLayers',2,'Layers',2,'NumLogicalPorts',ntx,'NumRFChains',ntx, ...
            'TargetCodeRate',cfg.phy.pdsch.codeRate,'MCSIndex',1,'MCSTable','qam64_table1','RV',0, ...
            'PrecodingMatrixLogicalPorts',W,'PrecodingMatrix',W, ...
            'PrecoderNormalizationConvention','unit_frobenius','PrecoderSource','channel_identity_regression');
        grant.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,direction,grant,'Frame',frame,'Slot',slot);
        % Resolve the native allocation before issuing the final coded grant.
        % freezePHYGrant preserves TBS; it cannot invent one for this fixture.
        [~,plannedCarrier,plannedChannel]=sixgr.system.abstraction.scheduledDataREMap(cfg,grant,absoluteSlot);
        if direction=="DL"
            [~,allocationInfo]=nrPDSCHIndices(plannedCarrier,plannedChannel);
        else
            [~,allocationInfo]=nrPUSCHIndices(plannedCarrier,plannedChannel);
        end
        grant.TBSBits=double(nrTBS('QPSK',2,numel(grant.PRBSet), ...
            allocationInfo.NREPerPRB,grant.TargetCodeRate,0));
        grant.NREPerPRB=allocationInfo.NREPerPRB; grant.XOverhead=0;
        grant=rmfield(grant,'PHYGrant');
        grant.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,direction,grant,'Frame',frame,'Slot',slot);
        state=struct('TTI',absoluteSlot+1,'GrantsDL',struct([]),'GrantsUL',struct([]), ...
            'GrantCellsDL',[],'GrantCellsUL',[], ...
            'LargeScaleState',struct('Pathloss_dB',0,'TxPower_dBm',30));
        state.("Grants"+direction)=grant; state.("GrantCells"+direction)=1;
        context=struct('TTI',absoluteSlot+1,'Direction',direction,'Grant',grant,'ServingCellID',1);
        observation=provider.evaluate(context,state);
        [replay,e]=sixgr.system.waveform.replayGrant(cfg,direction,grant,[],30, ...
            'StrictMode',true,'CompactPHYIO',false,'FastAWGNPath',false,'AdaptiveLDPC',false, ...
            'NoiseSeed',7121,'ChannelSeed',seed);
        assert(replay.WaveformReplayExecuted && e.Propagation.UseFading);
        identity=e.Propagation.Metadata.CalibrationChannelIdentity;
        assert(identity.ProfileID==observation.ChannelProfileID, ...
            'Waveform and modeled network channel must have the same native physical profile identity.');
        [feature,H]=sixgr.system.waveform.extractGrantCalibrationPredictor(e,"lmmse", ...
            'Plane','scheduled_nominal_fft_before_receiver_sync');
        assert(e.Propagation.ChannelInitialTime_s==expectedTime && ...
            replay.ReplayChannelInitialTime_s==expectedTime);
        assert(identity.ChannelClock=="actual_cp_ofdm_symbol_boundary");
        assert(e.CalibrationReceiverIdentity.ProfileID==observation.ReceiverProfileID);
        assert(isequaln(feature.ChannelCyclicPrefixSupport,observation.ChannelCyclicPrefixSupport) && ...
            ~feature.ResidualISIICIIncluded && ~observation.ResidualISIICIIncluded, ...
            'Waveform calibration and SLS must expose the same finite-filter CP domain.');
        [key,boundFeature]=sixgr.system.waveform.extractGrantCalibrationBinding(e);
        context.TBSBits=grant.TBSBits; context.NumLayers=grant.NumLayers;
        context.TargetCodeRate=grant.TargetCodeRate;
        context.SCS_kHz=cfg.phy.carrier.SubcarrierSpacing; context.ChannelModel=string(profile);
        expectedKey=sixgr.system.CalibratedLinkPHY.calibrationKey(context,observation, ...
            "lmmse",cfg.system.linkAbstraction.effectiveSINRMethod);
        assert(isequaln(key,expectedKey) && ~boundFeature.CalibrationQualified, ...
            'Actual waveform key must match the SLS lookup key without implying qualification. Actual=%s Expected=%s', ...
            jsonencode(key),jsonencode(expectedKey));
        poisoned=e; poisoned.Receiver.MaxDecoderIterations=1+poisoned.Receiver.MaxDecoderIterations;
        localReject(@()sixgr.system.waveform.bindCalibrationReceiverIdentity(poisoned,cfg), ...
            'sixgr:calibration:ReceiverRecipeDecoder');
        poisoned=e; poisoned.Receiver.EqualizerType='other';
        localReject(@()sixgr.system.waveform.bindCalibrationReceiverIdentity(poisoned,cfg), ...
            'sixgr:calibration:ReceiverRecipeEqualizer');
        index=e.DataREMap.PhysicalIndices1Based;
        flat=reshape(H,[],size(H,3),size(H,4));
        selected=permute(flat(index,:,:),[2 3 1]);
        % A common FFT-timing phase does not change the spatial Gram matrix.
        % Compare every data RE, preserving all antenna dimensions.
        errorSum=0; referenceSum=0;
        for k=1:numel(index)
            actual=selected(:,:,k)'*selected(:,:,k);
            expected=observation.Channel(:,:,k)'*observation.Channel(:,:,k);
            errorSum=errorSum+norm(actual-expected,'fro')^2;
            referenceSum=referenceSum+norm(expected,'fro')^2;
        end
        relative=sqrt(errorSum/referenceSum);
        if relative>=1e-10
            diagnostic=string(tempname(fullfile(pwd,'logs')))+"_channel_time.mat";
            save(diagnostic,'e','observation','cfg','grant','seed','relative','-v7.3');
            fprintf('SLS_CHANNEL_TIME_DIAGNOSTIC=%s\n',diagnostic);
        end
        assert(relative<1e-10,'Waveform/network spatial channel mismatch: %g',relative);
        noise=e.Noise.GridNoiseVariance;
        predicted=sixgr.system.abstraction.evaluateSpatialSINR( ...
            observation.Channel,observation.Precoder,1,noise*eye(size(H,3)),"lmmse");
        sinrError=norm(predicted.SINRLinear-feature.SINRLinear,'fro')/norm(feature.SINRLinear,'fro');
        assert(sinrError<1e-10,'Normalized per-RE SINR differs across physical/model channel paths.');
        fprintf('SLS_WAVEFORM_CHANNEL_IDENTITY profile=%s direction=%s ports=%dx%d slot=%d doppler=%g gram_error=%g sinr_error=%g\n', ...
            profile,direction,size(H,4),size(H,3),absoluteSlot,options.DopplerHz,relative,sinrError);
    end
end
% Realization seeds and output selection do not change physical profile;
% native sampling, array and channel parameters do.
ofdm=nrOFDMInfo(sixgr.phy.grid.makeCarrier(cfg)); fs=ofdm.SampleRate;
a=sixgr.system.abstraction.createNetworkSpatialChannel(cfg,fs,"DL",1);
b=sixgr.system.abstraction.createNetworkSpatialChannel(cfg,fs,"DL",2);
ia=sixgr.system.abstraction.networkChannelCalibrationIdentity(cfg,a.Object);
ib=sixgr.system.abstraction.networkChannelCalibrationIdentity(cfg,b.Object);
assert(ia.ProfileID==ib.ProfileID);
b.Object.DelaySpread=2*b.Object.DelaySpread;
ib=sixgr.system.abstraction.networkChannelCalibrationIdentity(cfg,b.Object);
assert(ia.ProfileID~=ib.ProfileID);
ra=sixgr.system.abstraction.networkReceiverCalibrationIdentity(cfg,"DL","lmmse");
changed=cfg; changed.phy.ldpc.maxIterations=ra.MaxIterations+1;
rb=sixgr.system.abstraction.networkReceiverCalibrationIdentity(changed,"DL","lmmse");
assert(ra.ProfileID~=rb.ProfileID,'Decoder configuration must change the receiver recipe identity.');
% Exercise the raw collection path too: two actual, independent UL episodes
% retain the matching runtime key and predictor arrays in sealed MAT files.
base=rmfield(grant,'PHYGrant');
base.IsRetransmission=false;
planEntries=cell(1,2);
for k=1:2
    base.TransportBlockIdentity="receiver_binding_tb_"+k;
    base.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,"UL",base,'Frame',frame,'Slot',slot);
    seeds=struct('Bits',8000+10*k,'Noise',8001+10*k,'Channel',8002+10*k, ...
        'ControlNoise',8003+10*k,'RF',8004+10*k, ...
        'ChannelEvolution','persistent_link_absolute_slot');
    role="fit"; if k==2, role="validation"; end
    planEntries{k}=struct('EpisodeID',"receiver_binding_"+k,'Role',role, ...
        'Grants',{{base}},'SNRdB',30,'Seeds',seeds);
    if options.RetryCollection
        retry=rmfield(base,'PHYGrant');
        retry.ScheduledAbsoluteSlot=absoluteSlot+4;
        retry.Frame=floor(retry.ScheduledAbsoluteSlot/slotsPerFrame);
        retry.Slot=mod(retry.ScheduledAbsoluteSlot,slotsPerFrame);
        retry.IsRetransmission=true; retry.RV=2;
        retry.HARQTBContext=struct('OriginalNumLayers',base.NumLayers);
        retry.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,"UL",retry,'Frame',retry.Frame,'Slot',retry.Slot);
        planEntries{k}.Grants={base,retry}; planEntries{k}.SNRdB=[-40 40];
        planEntries{k}.Seeds.Noise=[seeds.Noise seeds.Noise+100];
        planEntries{k}.Seeds.Channel=[seeds.Channel seeds.Channel];
        planEntries{k}.Seeds.ControlNoise=[seeds.ControlNoise seeds.ControlNoise+100];
        planEntries{k}.Seeds.RF=[seeds.RF seeds.RF+100];
    end
    base=rmfield(base,'PHYGrant');
end
plan=[planEntries{:}];
folder=tempname(fullfile(pwd,'logs'));
receipt=sixgr.system.waveform.collectGrantCalibrationEpisodes(cfg,plan,folder,'MaximumNewEpisodes',2);
rows=readtable(fullfile(folder,'waveform_trials.csv'),'TextType','string');
assert(receipt.CompletedEpisodes==2 && ~receipt.CalibrationQualified && ...
    height(rows)==2*(1+double(options.RetryCollection)) && all(rows.CalibrationBindingAvailable) && ...
    all(strlength(rows.CalibrationKeySHA256)==64));
for k=1:height(rows)
    saved=load(fullfile(folder,rows.EpisodeRelativePath(k)),'episode');
    retained=saved.episode.SpatialPredictorFeatures{rows.Attempt(k)};
    assert(retained.CalibrationKeySHA256==rows.CalibrationKeySHA256(k) && ...
        isequaln(saved.episode.CalibrationBindings{rows.Attempt(k)},retained.CalibrationKey) && ...
        ~retained.CalibrationQualified && all(isfinite(retained.SINRLinear),'all'));
    if options.RetryCollection
        attempts=saved.episode.Attempts;
        assert(numel(attempts)==2 && attempts(1).CRCError && ~attempts(2).CRCError && ...
            attempts(2).HARQSoftCombiningApplied && attempts(1).ChannelSeed==attempts(2).ChannelSeed && ...
            attempts(2).ChannelInitialTime_s-attempts(1).ChannelInitialTime_s>0 && ...
            saved.episode.Delivered && saved.episode.StopReason=="crc_success");
    end
end
[fittingRows,proof]=sixgr.calibration.readGrantCalibrationFeatureRows(folder,retained.CalibrationKey,1);
assert(proof.AllPlannedEpisodesPresent && proof.VerifiedEpisodes==2 && ...
    ~proof.CalibrationQualified && height(fittingRows)==2 && ...
    all(ismember(["fit","validation"],fittingRows.Role)) && ...
    all(fittingRows.ConfigurationSHA256==retained.CalibrationKeySHA256));
if options.RetryCollection
    [retryRows,retryProof]=sixgr.calibration.readGrantCalibrationFeatureRows(folder,retained.CalibrationKey,2);
    assert(height(retryRows)==2 && retryProof.ChannelEvolution=="persistent_link_absolute_slot" && ...
        all(cellfun(@(v)isequal(v,[0 2]),retryRows.RVSequence)) && ~any(retryRows.CRCError));
    fprintf('SLS_PERSISTENT_HARQ_REAL_RETRY_PASS episodes=2 unchanged_TB=1 combining=1\n');
end
unmatched=retained.CalibrationKey; unmatched.Rank=unmatched.Rank+1;
[absent,missingProof]=sixgr.calibration.readGrantCalibrationFeatureRows(folder,unmatched,1);
assert(isempty(absent) && missingProof.MatchingConditionalTrials==0, ...
    'A different runtime key must not borrow retained trials.');
% Change only the derived CSV: the verified feature reader must continue to
% derive populations from sealed physical episodes, never the edited view.
rows.CRCError=~logical(rows.CRCError);
writetable(rows,fullfile(folder,'waveform_trials.csv'));
[unchanged,~]=sixgr.calibration.readGrantCalibrationFeatureRows(folder,retained.CalibrationKey,1);
assert(isequaln(unchanged,fittingRows),'The editable CSV cannot replace physical CRC evidence.');
% Restore the view through the production resume path without new episodes.
resumed=sixgr.system.waveform.collectGrantCalibrationEpisodes(cfg,plan,folder,'MaximumNewEpisodes',1);
assert(resumed.NewEpisodes==0);
fprintf('SLS_RECEIVER_BINDING_RAW_COLLECTION episodes=2 qualification=0 folder=%s\n',folder);
ok=true;
fprintf('SLS_WAVEFORM_CHANNEL_IDENTITY_PASS statistical_calibration_qualified=0\n');
end

function localReject(fn,identifier)
try
    fn();
catch err
    assert(strcmp(err.identifier,identifier),'Unexpected rejection: %s',err.identifier);
    return;
end
error('testSLSWaveformChannelIdentity:MissingRejection','Expected %s.',identifier);
end

function cfg=localConfig()
cfg=sixgr.config.defaultConfig();
policy=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
cfg=sixgr.util.mergeStruct(cfg,policy);
cfg.run.strictMode=true; cfg.run.useMex=false; cfg.run.seed=113; cfg.run.executionID='channel_identity';
cfg.run.pdschExecutionProfile='phy_calibration'; cfg.run.puschExecutionProfile='phy_calibration';
cfg.phy.carrier.NSizeGrid=24; cfg.phy.carrier.NStartGrid=0; cfg.phy.carrier.SubcarrierSpacing=30;
cfg.phy.numerology.scs_kHz=30; cfg.phy.duplex.mode='TDD'; cfg.phy.fc_Hz=4e9;
cfg.phy.nTxAnt=4; cfg.phy.nRxAnt=2;
cfg.scenario.bs.nTxAnt=4; cfg.scenario.bs.nRxAnt=4;
cfg.scenario.ue.nTxAnt=2; cfg.scenario.ue.nRxAnt=2;
cfg.scenario.bs.noiseFigure_dB=7; cfg.scenario.ue.noiseFigure_dB=9; cfg.scenario.ue.txPower_dBm=23;
cfg.antenna.bs.numElements=4; cfg.antenna.bs.numRFChains=4;
cfg.antenna.ue.numElements=2; cfg.antenna.ue.numRFChains=2;
cfg.rf=struct(); cfg.phy.impairments=struct();
cfg.phy.beamManagement.hybridBeamformingEnabled=false;
cfg.phy.ssb.enable=false; cfg.phy.csirs.enable=false; cfg.phy.trs.enable=false;
cfg.phy.csiim.enable=false; cfg.phy.ptrs.enable=false;
cfg.channel=struct('model','TDL-A','tdlProfile','TDL-A', ...
    'delaySpread_s',30e-9,'doppler_Hz',0,'normalizeChannelOutputs',false, ...
    'awgnOnly',false,'nTxAnt',4,'nRxAnt',2);
mcs=sixgr.link.resolveMCSProfile('qam64_table1',1);
for name=["pdsch","pusch"]
    ports=4; if name=="pusch", ports=2; end
    cfg.phy.(name).modulation='QPSK'; cfg.phy.(name).codeRate=mcs.TargetCodeRate;
    cfg.phy.(name).mcsTable='qam64_table1'; cfg.phy.(name).mcsIndex=1;
    cfg.phy.(name).numPorts=ports; cfg.phy.(name).nPorts=ports;
    cfg.phy.(name).numLayers=2; cfg.phy.(name).nLayers=2; cfg.phy.(name).dmrs.portSet=0:1;
    cfg.phy.(name).enablePTRS=false; cfg.phy.(name).xOverhead=0;
end
cfg.phy.pusch.transformPrecoding=false;
cfg.system.linkAbstraction.spatialProviderClass='sixgr.system.abstraction.NetworkSpatialGrantProvider';
p=cfg.system.linkAbstraction.networkSpatial;
p.bsPorts=4; p.uePorts=2; p.dlAntennaBasis='direct_ports';
p.sinrResourcePopulation='native_shared_channel_data_re';
cfg.system.linkAbstraction.networkSpatial=p;
end
