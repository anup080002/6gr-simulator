function ok=testGrantFiniteCalibrationPredictor()
% Real coded captures, independently probed native channel and LMMSE/ZF math.
cfg=sixgr.config.defaultConfig();
cfg=sixgr.util.mergeStruct(cfg,sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/system/calibrated_link_abstraction.yaml'));
cfg.run.strictMode=true; cfg.run.useMex=false;
cfg.run.pdschExecutionProfile='phy_calibration'; cfg.run.puschExecutionProfile='phy_calibration';
cfg.phy.carrier.NSizeGrid=6; cfg.phy.carrier.NStartGrid=0; cfg.phy.carrier.SubcarrierSpacing=30;
cfg.phy.numerology.scs_kHz=30; cfg.phy.duplex.mode='TDD'; cfg.phy.fc_Hz=4e9;
cfg.phy.nTxAnt=2; cfg.phy.nRxAnt=2;
for endpoint=["bs","ue"]
    cfg.scenario.(endpoint).nTxAnt=2; cfg.scenario.(endpoint).nRxAnt=2;
    cfg.antenna.(endpoint).numElements=2; cfg.antenna.(endpoint).numRFChains=2;
end
cfg.rf=struct(); cfg.phy.impairments=struct();
cfg.phy.beamManagement.hybridBeamformingEnabled=false;
for signal=["ssb","csirs","trs","csiim","ptrs"], cfg.phy.(signal).enable=false; end
cfg.system.linkAbstraction.spatialProviderClass='sixgr.system.abstraction.NetworkSpatialGrantProvider';
cfg.system.linkAbstraction.networkSpatial.bsPorts=2;
cfg.system.linkAbstraction.networkSpatial.uePorts=2;
cfg.system.linkAbstraction.networkSpatial.channelResponseSampling='signal_rate';
cfg.system.linkAbstraction.networkSpatial.sinrPredictorModel='finite_committed_shared_data';
mcs=sixgr.link.resolveMCSProfile('qam64_table1',1);
rows=cell(0,7);
for profile=["TDL-A","CDL-C"]
    cfg.channel=struct('model',char(profile),'delaySpread_s',300e-9,'doppler_Hz',70, ...
        'normalizeChannelOutputs',false,'awgnOnly',false,'nTxAnt',2,'nRxAnt',2);
    if profile=="TDL-A", cfg.channel.tdlProfile=char(profile);
    else, cfg.channel.cdlProfile=char(profile); end
    for direction=["DL","UL"]
        for layers=[1 2]
            for name=["pdsch","pusch"]
                cfg.phy.(name).modulation='QPSK'; cfg.phy.(name).codeRate=mcs.TargetCodeRate;
                cfg.phy.(name).mcsTable='qam64_table1'; cfg.phy.(name).mcsIndex=1;
                cfg.phy.(name).numPorts=2; cfg.phy.(name).nPorts=2;
                cfg.phy.(name).numLayers=layers; cfg.phy.(name).nLayers=layers;
                cfg.phy.(name).dmrs.portSet=0:layers-1;
                cfg.phy.(name).enablePTRS=false; cfg.phy.(name).xOverhead=0;
            end
            cfg.phy.pusch.transformPrecoding=false;
            W=eye(2,layers)/sqrt(layers);
            g=struct('Direction',char(direction),'Frame',1,'Slot',3,'ScheduledAbsoluteSlot',23, ...
                'RNTI',73,'UEIndex',1,'ServingCell',1,'PRBSet',0,'SymbolAllocation',[2 4], ...
                'Modulation','QPSK','NumLayers',layers,'Layers',layers,'NumLogicalPorts',2,'NumRFChains',2, ...
                'TargetCodeRate',mcs.TargetCodeRate,'MCSIndex',1,'MCSTable','qam64_table1','RV',0, ...
                'PrecodingMatrixLogicalPorts',W,'PrecodingMatrix',W, ...
                'PrecoderNormalizationConvention','unit_frobenius','PrecoderSource','finite_capture_test');
            g.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,direction,g,'Frame',1,'Slot',3);
            [~,carrier,native]=sixgr.system.abstraction.scheduledDataREMap(cfg,g,23);
            if direction=="DL", [~,info]=nrPDSCHIndices(carrier,native);
            else, [~,info]=nrPUSCHIndices(carrier,native); end
            g.TBSBits=double(nrTBS('QPSK',layers,numel(g.PRBSet),info.NREPerPRB,g.TargetCodeRate,0));
            g.NREPerPRB=info.NREPerPRB; g.XOverhead=0;
            g=rmfield(g,'PHYGrant');
            g.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,direction,g,'Frame',1,'Slot',3);
            [replay,e]=sixgr.system.waveform.replayGrant(cfg,direction,g,[],30, ...
                'StrictMode',true,'CompactPHYIO',false,'FastAWGNPath',false,'AdaptiveLDPC',false, ...
                'NoiseSeed',7391,'ChannelSeed',7392,'ChannelInitialTime_s',23*.0005);
            assert(replay.WaveformReplayExecuted && e.WaveformBacked);
            original=e;
            [key,f]=sixgr.system.waveform.extractGrantCalibrationBinding(e);
            assert(isequaln(e,original) && key.ReceiverProfileID==e.CalibrationReceiverIdentity.ProfileID);
            assert(f.ResidualISIICIIncluded && ~f.ReceiverOracleUsed && ...
                ~f.CalibrationQualified && ~f.PrimaryStudyAccepted && ~f.FullNetworkInterferenceQualified);
            [reference,zfReference]=nativeFeatures(e,f.PerLayerSymbolEnergy,direction);
            relative=norm(reference-f.SINRLinear,'fro')/norm(reference,'fro');
            assert(relative<1e-9,'Finite predictor disagrees with native-channel probes: %.15g',relative);
            zf=sixgr.system.waveform.extractGrantCalibrationPredictor(e,"zf", ...
                'Plane','scheduled_nominal_fft_before_receiver_sync','Model','finite_committed_shared_data');
            relativeZF=norm(zfReference-zf.SINRLinear,'fro')/norm(zfReference,'fro');
            assert(relativeZF<1e-9,'Finite ZF predictor disagrees with native-channel probes: %.15g',relativeZF);
            diagonal=sixgr.system.waveform.extractGrantCalibrationPredictor(e,"lmmse", ...
                'Plane','scheduled_nominal_fft_before_receiver_sync');
            difference=norm(diagonal.SINRLinear-f.SINRLinear,'fro')/norm(f.SINRLinear,'fro');
            assert(difference>1e-8,'Finite model must not merely relabel diagonal features.');
            rows(end+1,:)={profile,direction,layers,relative,relativeZF,difference,logical(replay.Ok)}; %#ok<AGROW>
            fprintf('GRANT_FINITE_FEATURE profile=%s direction=%s rank=%d native_error=%g native_zf_error=%g diagonal_difference=%g\n', ...
                profile,direction,layers,relative,relativeZF,difference);
        end
    end
end
bad=e; bad.Propagation.PathGains=bad.Propagation.PathGains(1:2:end,:,:,:);
bad.Propagation.SampleTimes=bad.Propagation.SampleTimes(1:2:end);
reject(@()sixgr.system.waveform.extractGrantCalibrationBinding(bad),'sixgr:abstraction:FiniteOFDMSampleClock');
bad=e; bad.AppliedImpairments.RFAppliedStageCount=1;
reject(@()sixgr.system.waveform.extractGrantCalibrationBinding(bad),'sixgr:calibration:GrantPredictorRFDomain');
bad=e;
if isfield(bad.Transmitter,'OFDMInfo'), bad.Transmitter.OFDMInfo.Windowing=2;
else, bad.Transmitter.OFDM.Windowing=2; end
reject(@()sixgr.system.waveform.extractGrantCalibrationBinding(bad),'sixgr:calibration:FinitePredictorWindowing');
folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
writetable(cell2table(rows,'VariableNames',{'Profile','Direction','Rank','NativeRelativeError', ...
    'NativeZFRelativeError','DiagonalRelativeDifference','DecodedCRCOK'}),fullfile(folder,'finite_calibration_features.csv'));
% Exercise production collection and sealed-evidence reconstruction, not
% just a stand-alone numerical extractor. Two episodes are NOT qualification.
entries=cell(1,2);
for k=1:2
    issued=rmfield(g,'PHYGrant');
    issued.TransportBlockIdentity="finite_collection_"+k; issued.IsRetransmission=false;
    issued.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,direction,issued,'Frame',1,'Slot',3);
    role="fit"; if k==2, role="validation"; end
    seeds=struct('Bits',8100+10*k,'Noise',8101+10*k,'Channel',8102+10*k, ...
        'ControlNoise',8103+10*k,'RF',8104+10*k,'ChannelEvolution','persistent_link_absolute_slot');
    entries{k}=struct('EpisodeID',"finite_"+k,'Role',role,'Grants',{{issued}},'SNRdB',30,'Seeds',seeds);
end
collection=fullfile(folder,'collection');
receipt=sixgr.system.waveform.collectGrantCalibrationEpisodes(cfg,[entries{:}],collection,'MaximumNewEpisodes',2);
assert(receipt.CompletedEpisodes==2 && ~receipt.CalibrationQualified);
[population,proof]=sixgr.calibration.readGrantCalibrationFeatureRows(collection,key,1);
assert(height(population)==2 && all(ismember(["fit","validation"],population.Role)) && ...
    proof.AllPlannedEpisodesPresent && ~proof.CalibrationQualified);
fprintf('GRANT_FINITE_CALIBRATION_PASS native_cases=8 statistical_qualification=0 folder=%s\n',folder);
ok=true;
end

function [sinr,zfSINR]=nativeFeatures(e,energy,direction)
% No use of sampledOFDMInterferenceCovariance/applySampledFadingChannel or
% nrPerfectChannelEstimate: probe the native executed channel directly.
tx=e.Transmitter; p=e.Propagation; c=tx.Carrier; ofdm=e.ReceiverOFDMInfo;
ch=sixgr.system.abstraction.createNetworkSpatialChannel(e.ResolvedConfig,p.SampleRateHz,direction,p.ChannelSeed);
ch.Object.InitialTime=p.ChannelInitialTime_s;
base=e.DataREMap.PhysicalIndices1Based; n=numel(base); rankValue=numel(energy);
G=complex(zeros(2,rankValue,n)); leak=complex(zeros(2,2,n));
w=double(tx.PrecodeInfo.MatrixPorts)*diag(sqrt(energy));
for source=1:n
    for layer=1:rankValue
        x=complex(zeros(12*c.NSizeGrid,c.SymbolsPerSlot,2));
        for port=1:2, x(base(source)+(port-1)*numel(x(:,:,1)))=w(port,layer); end
        wave=nrOFDMModulate(c,x,'Nfft',ofdm.Nfft,'SampleRate',ofdm.SampleRate,'Windowing',0);
        reset(ch.Object);
        [rx,pg,t]=ch.Object([wave;zeros(p.InputPadSamples,2)]);
        assert(isequal(pg,p.PathGains) && isequal(t,p.SampleTimes),'Native probe must reproduce captured channel realization.');
        rx=rx(p.ImplementationFilterTrimSamples+(1:size(wave,1)),:)*e.AppliedImpairments.AppliedLargeScaleAmplitudeGain;
        grid=nrOFDMDemodulate(c,rx,'Nfft',ofdm.Nfft,'SampleRate',ofdm.SampleRate, ...
            'CyclicPrefixFraction',ofdm.CyclicPrefixFraction);
        flat=reshape(grid,[],2);
        for k=1:n
            v=flat(base(k),:).';
            if source==k, G(:,layer,k)=v; else, leak(:,:,k)=leak(:,:,k)+v*v'; end
        end
    end
end
sinr=zeros(n,rankValue);
zfSINR=zeros(n,rankValue);
for k=1:n
    R=e.Noise.GridNoiseVariance*eye(2)+leak(:,:,k);
    E=(eye(rankValue)+G(:,:,k)'*(R\G(:,:,k)))\eye(rankValue);
    sinr(k,:)=1./real(diag(E)).'-1;
    % Independent pseudo-inverse reference, not production QR code.
    W=pinv(G(:,:,k)); response=W*G(:,:,k);
    useful=abs(diag(response)).^2;
    response(1:rankValue+1:end)=0;
    zfSINR(k,:)=(useful./(sum(abs(response).^2,2)+real(diag(W*R*W')))).';
end
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s',id);
end
