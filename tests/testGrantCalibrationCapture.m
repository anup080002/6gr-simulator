function ok=testGrantCalibrationCapture()
% Capture must preserve the physical outcome and retain its applied channel.
cfg=sixgr.config.defaultConfig();
cfg.run.strictMode=true; cfg.run.useMex=false;
cfg.run.pdschExecutionProfile='phy_calibration';
cfg.run.puschExecutionProfile='phy_calibration';
cfg.phy.carrier.NSizeGrid=24; cfg.phy.carrier.NStartGrid=0;
cfg.phy.carrier.SubcarrierSpacing=30;
cfg.phy.fc_Hz=4e9;
cfg.phy.nTxAnt=2; cfg.phy.nRxAnt=2;
cfg.scenario.bs.nTxAnt=2; cfg.scenario.bs.nRxAnt=2;
cfg.scenario.ue.nTxAnt=2; cfg.scenario.ue.nRxAnt=2;
cfg.antenna.bs.numElements=2; cfg.antenna.bs.numRFChains=2;
cfg.antenna.ue.numElements=2; cfg.antenna.ue.numRFChains=2;
cfg.rf=struct(); cfg.phy.impairments=struct();
cfg.phy.beamManagement.hybridBeamformingEnabled=false;
cfg.phy.ssb.enable=false; cfg.phy.csirs.enable=false;
cfg.phy.trs.enable=false; cfg.phy.csiim.enable=false; cfg.phy.ptrs.enable=false;
mcs=sixgr.link.resolveMCSProfile('qam64_table1',1);
for name=["pdsch","pusch"]
    cfg.phy.(name).modulation='QPSK'; cfg.phy.(name).codeRate=mcs.TargetCodeRate;
    cfg.phy.(name).mcsTable='qam64_table1'; cfg.phy.(name).mcsIndex=1;
    cfg.phy.(name).numPorts=2; cfg.phy.(name).nPorts=2;
    cfg.phy.(name).enablePTRS=false; cfg.phy.(name).xOverhead=0;
end
cfg.phy.pusch.transformPrecoding=false;
for profile=["AWGN","TDL-A"]
    cfg.channel=struct('model',char(profile),'tdlProfile','TDL-A', ...
        'delaySpread_s',30e-9,'doppler_Hz',0,'normalizeChannelOutputs',false, ...
        'awgnOnly',profile=="AWGN",'nTxAnt',2,'nRxAnt',2);
    for direction=["DL","UL"]
        for layers=[1 2]
            for name=["pdsch","pusch"]
                cfg.phy.(name).numLayers=layers; cfg.phy.(name).nLayers=layers;
                cfg.phy.(name).dmrs.portSet=0:layers-1;
            end
            W=eye(2,layers)/sqrt(layers);
            absoluteSlot=23*(layers-1);
            g=struct('Direction',char(direction),'Frame',floor(absoluteSlot/20), ...
                'Slot',mod(absoluteSlot,20),'ScheduledAbsoluteSlot',absoluteSlot, ...
                'RNTI',73,'UEIndex',1,'ServingCell',1,'PRBSet',0:5, ...
                'SymbolAllocation',[2 10],'Modulation','QPSK','NumLayers',layers,'Layers',layers, ...
                'NumLogicalPorts',2,'NumRFChains',2,'TargetCodeRate',mcs.TargetCodeRate, ...
                'MCSIndex',1,'MCSTable','qam64_table1','RV',0, ...
                'PrecodingMatrixLogicalPorts',W,'PrecodingMatrix',W, ...
                'PrecoderNormalizationConvention','unit_frobenius','PrecoderSource','capture_regression');
            g.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,direction,g,'Frame',g.Frame,'Slot',g.Slot);
            args={'StrictMode',true,'CompactPHYIO',false,'FastAWGNPath',false, ...
                'AdaptiveLDPC',false,'NoiseSeed',7391,'ChannelSeed',7392};
            before=sixgr.system.waveform.replayGrant(cfg,direction,g,[],30,args{:});
            [after,e]=sixgr.system.waveform.replayGrant(cfg,direction,g,[],30,args{:});
            assert(before.WaveformReplayExecuted && after.WaveformReplayExecuted && ...
                before.CRCError==after.CRCError && before.BitErrors==after.BitErrors && ...
                before.TransmittedTransportBlockSHA256==after.TransmittedTransportBlockSHA256 && ...
                abs(before.EVM_rms-after.EVM_rms)<1e-12, ...
                'Diagnostic capture must not change the waveform, channel realization or decoder outcome.');
            assert(e.WaveformBacked && ~e.CalibrationQualified && ~e.PrimaryStudyAccepted && ...
                ~e.Propagation.ReceiverOracleUsed && e.DataREMap.NumLayers==layers);
            assert(e.Transmitter.Carrier.NSlot==g.Slot && e.Transmitter.Carrier.NFrame==g.Frame, ...
                'The replay must use the scheduled carrier clock, including frame crossings.');
            assert(isequaln(e.Grant.PHYGrant,g.PHYGrant), 'Frozen grant changed during capture.');
            assert( ...
                e.Noise.GridNoiseVariance==after.AWGNGridNoiseVariance && ...
                e.Propagation.ChannelSeed==7392, 'Noise or channel seed evidence changed during capture.');
            [feature,H]=sixgr.system.waveform.extractGrantCalibrationPredictor(e,"lmmse");
            assert(feature.DataRECount==e.DataREMap.LayerRECount && ...
                ~feature.CalibrationQualified && ~feature.PrimaryStudyAccepted && ...
                ~feature.ReceiverOracleUsed && ...
                contains(feature.SINRSource,"not_receiver_measurement"));
            if profile=="TDL-A"
                ch=sixgr.channel.ChannelFactory.create(e.ResolvedConfig, ...
                    'Model','TDL-A','SampleRate',e.Propagation.SampleRateHz, ...
                    'NumTxAnt',2,'NumRxAnt',2,'Seed',7392);
                wave=e.Transmitter.Waveform;
                padded=[wave;zeros(e.Propagation.InputPadSamples,2,'like',wave)];
                [noiseless,gains,times]=ch.Object(padded);
                assert(isequal(gains,e.Propagation.PathGains) && ...
                    isequal(times,e.Propagation.SampleTimes) && ...
                    isequal(getPathFilters(ch.Object),e.Propagation.PathFilters), ...
                    'Retained fading evidence must reproduce the actually executed channel invocation.');
            else
                assert(isempty(e.Propagation.PathGains) && ~e.Propagation.UseFading);
                noiseless=e.Transmitter.Waveform;
            end
            % Independent sample-domain convolution/FFT comparison, not a
            % second invocation of the perfect-channel reconstruction.
            start=e.Propagation.ImplementationFilterTrimSamples+ ...
                e.Receiver.AppliedTimingCorrection_samples;
            noiseless=noiseless(1+start:end,:)*e.AppliedImpairments.AppliedLargeScaleAmplitudeGain;
            ofdm=e.ReceiverOFDMInfo;
            received=nrOFDMDemodulate(e.Transmitter.Carrier,noiseless, ...
                'Nfft',ofdm.Nfft,'SampleRate',ofdm.SampleRate, ...
                'CyclicPrefixFraction',ofdm.CyclicPrefixFraction);
            xgrid=double(e.Transmitter.Grid);
            predicted=complex(zeros(size(H,1),size(H,2),size(H,3)));
            for r=1:size(H,3)
                for t=1:size(H,4)
                    predicted(:,:,r)=predicted(:,:,r)+H(:,:,r,t).*xgrid(:,:,t);
                end
            end
            idx=e.DataREMap.PhysicalIndices1Based;
            pred=reshape(predicted,[],size(H,3)); obs=reshape(received,[],size(H,3));
            relative=norm(pred(idx,:)-obs(idx,:),'fro')/norm(obs(idx,:),'fro');
            assert(relative<1e-8,'Applied per-RE channel disagrees with noiseless sample-domain execution: %g',relative);
            % Independent LMMSE error-covariance identity, not the shared
            % evaluator's filter/desired/interference-power implementation.
            channelPages=reshape(H,[],size(H,3),size(H,4));
            appliedW=double(e.Transmitter.PrecodeInfo.MatrixPorts)* ...
                diag(sqrt(feature.PerLayerSymbolEnergy));
            independent=zeros(size(feature.SINRLinear));
            for re=1:numel(idx)
                effective=reshape(channelPages(idx(re),:,:),size(H,3),size(H,4))*appliedW;
                errorCovariance=(eye(layers)+(effective'*effective)/e.Noise.GridNoiseVariance)\eye(layers);
                independent(re,:)=1./real(diag(errorCovariance)).'-1;
            end
            assert(norm(independent-feature.SINRLinear,'fro')/norm(independent,'fro')<1e-8, ...
                'Spatial SINR must agree with independent LMMSE error covariance.');
            fprintf('GRANT_PREDICTOR_SAMPLE_CLOSURE profile=%s direction=%s rank=%d relative_error=%g\n', ...
                profile,direction,layers,relative);
            fprintf('GRANT_CALIBRATION_CAPTURE_CASE profile=%s direction=%s rank=%d crc_pass=%d\n', ...
                profile,direction,layers,after.Ok);
        end
    end
end
bad=e; bad.AppliedImpairments.RFAppliedStageCount=1;
localExpect(@()sixgr.system.waveform.extractGrantCalibrationPredictor(bad,"lmmse"), ...
    'sixgr:calibration:GrantPredictorRFDomain');
bad=e;
bad.Receiver.ReceiverChannelOperator.CaptureOriginCFOCorrection_Hz=100;
localExpect(@()sixgr.system.waveform.extractGrantCalibrationPredictor(bad,"lmmse"), ...
    'sixgr:calibration:GrantPredictorReceiverOperator');
bad=e; bad.Noise.AppliedLargeScalePowerGain=2*bad.Noise.AppliedLargeScalePowerGain;
localExpect(@()sixgr.system.waveform.extractGrantCalibrationPredictor(bad,"lmmse"), ...
    'sixgr:calibration:GrantPredictorPower');
ok=true;
fprintf('GRANT_CALIBRATION_CAPTURE_PASS outcomes_unchanged=1 no_receiver_oracle=1 not_qualified=1\n');
end

function localExpect(callback,id)
caught=false;
try, callback(); catch err, caught=strcmp(err.identifier,id); if ~caught, rethrow(err); end; end
assert(caught,'Expected explicit rejection: %s',id);
end
