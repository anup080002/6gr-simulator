function ok=testUplinkControlStreamStages()
% Isolated actual SRS and PUCCH codec observations on the TDD profile.
% Analytic connector/pathloss and known UCI are UNIT FIXTURES, not access
% measurements, production feedback or shared-scheduler qualification.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(source,tempname);
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
cfg.channel.fading.enabled=false; cfg.channel.fading.type='AWGN';
cfg.run.noiseOperatingMode='standalone_awgn_snr_argument';
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,5,1);
cfg.lls6g.userContext.RuntimeSlotStartTime_s=4e-3;
cfg.lls6g.userContext.RuntimeServingPathloss_dB=77;
cfg.lls6g.userContext.RuntimeServingPathlossSource='unit_fixture_analytic_reference_not_field_measurement';
cfg.lls6g.userContext.RuntimeServingPathlossReferenceRS='SSB-0';
cfg.lls6g.userContext.RuntimeServingPathlossMeasurementId='unit_fixture_not_measured_access';
cfg.lls6g.userContext.RuntimeServingPathlossMeasurementSlot=1;
cfg.lls6g.userContext.RuntimeServingPathlossReferenceSignalType='SSB';
cfg.lls6g.userContext.RuntimeServingPathlossReferenceSignalId=0;

% The old Format-0 connector case had no received UL timing/TAG history.
% Its actual shared-SRS -> Format-0 replacement is executed below; never
% manufacture a prior clock to keep that obsolete receive fixture passing.
for caseIndex=[1 3]
    channels=["SRS","PUCCH","PUCCH"];
    channel=channels(caseIndex);
    if channel=="SRS"
        runner=@sixgr.link.runSRSChannelEstimation;
        args={'SlotIndex',5,'SNR_dB',12,'TimingAdvanceSamples',0};
    else
        connected=localPUCCH(cfg,caseIndex==3);
        runner=@sixgr.link.runPUCCHWaveformTrial;
        args={'Assignment',connected.Assignment,'Report',connected.Report, ...
            'Carrier',sixgr.phy.grid.makeCarrier(cfg),'ChannelProfile','AWGN', ...
            'SNR_dB',12,'TimingAdvanceSamples',0};
        localReject(@()runner(cfg,args{:},'SignalPresent',false,'PrepareOnly',true), ...
            'sixgr:link:AbsentPUCCHNeedsReceiveOnlyWindow');
    end
    pending=runner(cfg,args{:},'PrepareOnly',true);
    assert(~pending.Ok && pending.ExecutionStage=="transmit_prepared_not_received");
    p=pending.PreparedTransmission;
    assert(p.StartSample==round(4e-3*p.SampleRateHz));
    assert(~p.Tx.PowerContext.PAApplied && ...
        (~p.Tx.PowerContext.PAEnabled || p.Tx.PowerContext.PAExecutionDeferred));
    array=sixgr.rf.AntennaArrayFactory.build(cfg,'ue','signal',lower(channel), ...
        'numPorts',size(p.Tx.Waveform,2));
    x=p.Tx.Waveform*cast(array.PortToElementMatrix.','like',p.Tx.Waveform);
    connector=eye(size(x,2),p.NumReceiveAntennas)*10^(-77/20);
    desired=x*cast(connector,'like',x);
    if channel=="SRS", indices=p.Tx.SRSIndices; else, indices=p.Tx.PUCCHIndices; end
    [energy,~]=sixgr.phy.waveform.measureReceivedOccupiedREEnergy( ...
        p.Tx.Carrier,desired,indices,'SignalFamily',channel);
    % Explicit standalone occupied-RE reference AWGN, not a production
    % thermal-noise calibration and not a replacement for measured SINR.
    [y,noise]=sixgr.phy.waveform.addOccupiedREAWGN(desired,p.Tx.Carrier,12, ...
        'SignalEnergyPerOccupiedRE',energy);
    replay=struct('SampleNoiseVariance',noise.SampleNoiseVariance, ...
        'SampleNoiseVarianceDomain','receiver_sample_waveform_post_composite_front_end', ...
        'NoiseVarianceSource','explicit_isolated_occupied_re_awgn', ...
        'NoiseOperatingMode','standalone_awgn_snr_argument', ...
        'AppliedAWGNSNR_dB',12,'ApproximationMode','none');
    context=struct('Prepared',p,'Observation',localBuffer(p,y), ...
        'PhysicalMeasurementObservation',localBuffer(p,y), ...
        'TransmitterObservation',localBuffer(p,x),'DesiredReferenceObservation',localBuffer(p,desired), ...
        'Replay',replay,'ChannelState',struct('UnitConnectorConsumedSamples',size(x,1)), ...
        'Channel',struct('Profile','AWGN','Source','unit_analytic_attenuating_connector'));
    bad=context;
    bad.Observation=sixgr.phy.waveform.WaveformObservationBuffer( ...
        p.StartSample,p.EndSampleExclusive,p.SampleRateHz,p.NumReceiveAntennas);
    localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'WAVEFORM:IncompleteObservation');
    bad=context; bad.Replay.SampleNoiseVarianceDomain='resource_grid_pre_equalization';
    localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'sixgr:link:ULControlNoisePlaneMismatch');
    bad=context; bad.Replay.ProxyUsed=true;
    localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'sixgr:link:ProxyULControlStreamForbidden');
    wrong=cfg; wrong.phy.carrier.NCellID=cfg.phy.carrier.NCellID+1;
    localReject(@()runner(wrong,args{:},'ReceivedContext',context),'sixgr:link:PreparedULControlRequestMismatch');
    advanced=args; advanced{end}=3;
    localReject(@()runner(cfg,advanced{:},'PrepareOnly',true),'sixgr:link:SharedULControlTimingAdvanceNotIntegrated');
    savedRNG=rng;
    completed=runner(cfg,args{:},'ReceivedContext',context);
    assert(isequal(savedRNG,rng),'Completion must not regenerate TX/channel/noise or reset the RNG.');
    assert(completed.Ok, '%s completion failed: %s',channel,completed.FailureReason);
    assert(completed.ExecutionStage=="received_shared_stream_completed");
    if channel=="SRS"
        assert(isequaln(completed.ChannelState,context.ChannelState));
        assert(completed.TrueChannelOracleAvailable && completed.NMSE_dB<=completed.ChannelNMSEThreshold_dB);
        assert(isnan(completed.QCLAccuracy));
        [~,info]=sixgr.phy.waveform.ofdmDemodulate(p.Tx.Carrier,y);
        expected=sixgr.phy.waveform.convertNoiseVarianceToGridDomain( ...
            noise.SampleNoiseVariance,info,'InputDomain','time');
        assert(abs(completed.NoiseVariance-expected)<=1e-12*expected);
        % A shared RF owner may not know a scalar post-RF variance. Use the
        % actual SRS resource estimator, never the configured SNR as rescue.
        estimatedContext=context;
        estimatedContext.Replay.SampleNoiseVariance=NaN;
        estimatedContext.Replay.SampleNoiseVarianceDomain= ...
            'unavailable_requires_received_reference_estimation';
        estimated=runner(cfg,args{:},'ReceivedContext',estimatedContext);
        assert(isfinite(estimated.NoiseVariance) && estimated.NoiseVariance>0 && ...
            string(estimated.NoiseVarianceSource)=="runtime_channel_estimate");
        assert(string(estimated.NoiseVarianceDomain)=="resource_grid_pre_equalization");
        assert(string(estimated.InjectedSampleNoiseVarianceSource)==string(replay.NoiseVarianceSource), ...
            'Keep physical injection provenance separate from the received estimator source.');
        % Missing channel reference must not generate a Doppler stand-in.
        noReference=rmfield(context,'DesiredReferenceObservation');
        failed=runner(cfg,args{:},'ReceivedContext',noReference);
        assert(~failed.Ok && ~failed.TrueChannelOracleAvailable && isnan(failed.NMSE_dB) && ...
            string(failed.FailureReason)=="srs_channel_nmse_reference_unavailable");
        localUnchangedReceiver(completed,failed);
        % A wrong absolute gain is an NMSE failure, not fitted away.
        wrongReference=context;
        wrongReference.DesiredReferenceObservation=localBuffer(p,2*desired);
        failed=runner(cfg,args{:},'ReceivedContext',wrongReference);
        assert(~failed.Ok && failed.NMSE_dB>-8 && ...
            string(failed.FailureReason)=="srs_channel_nmse_above_threshold");
        localUnchangedReceiver(completed,failed);
    else
        assert(isequaln(completed.UpdatedRuntimeChannelState,context.ChannelState));
        assert(completed.UCIContentMatch && isequal(completed.ExpectedBits,completed.DecodedBits));
        assert(isnan(completed.InputEVMPercent) && isnan(completed.MeasuredInputNoisePower), ...
            'Do not manufacture isolated-noise measurements from a variance parameter.');
        assert(isequal(completed.Tx.Waveform,p.Tx.Waveform));
        assert(completed.NoiseVariance==completed.Rx.GridNoiseVariance && ...
            string(completed.NoiseVarianceDomain)=="resource_grid_pre_equalization" && ...
            string(completed.NoiseVarSource)==string(completed.Rx.GridNoiseVarianceSource));
        unknownNoise=context;
        unknownNoise.Replay.SampleNoiseVariance=NaN;
        unknownNoise.Replay.SampleNoiseVarianceDomain= ...
            'unavailable_requires_received_reference_estimation';
        if isempty(p.Tx.DMRSIndices)
            localReject(@()runner(cfg,args{:},'ReceivedContext',unknownNoise), ...
                'sixgr:link:PUCCHNoiseObservationRequired');
        else
            estimated=runner(cfg,args{:},'ReceivedContext',unknownNoise);
            assert(estimated.Ok && estimated.UCIContentMatch && estimated.NoiseVariance>0 && ...
                isnan(estimated.ReceiverInputSampleNoiseVariance) && ...
                estimated.NoiseVarSource=="received_pucch_dmrs_noise_plus_residual_estimate");
            assert(isequal(estimated.DecodedBits,estimated.ExpectedBits));
        end
    end
    fprintf('[PASS] %s staged actual reception at standalone 12 dB; no main scheduler claim.\n',channel);
end
assert(testSharedPUCCHFeedbackClock(), ...
    'Pilot-free PUCCH requires the actual preceding shared SRS timing fixture.');
ok=true;
end

function localUnchangedReceiver(good,scoringFailure)
assert(~scoringFailure.StrictOk && scoringFailure.SRSRuntimeEvidenceUsable, ...
    'Scoring failure must fail qualification without replacing received evidence.');
for field=["SRSRuntimeEvidenceUsable","SRSChannelEstimateAvailable","ChannelEstimateAvailable", ...
        "SINR_dB","CQI","MCSIndex","RIEstimate","TPMIEstimate","NoiseVariance"]
    assert(isequaln(good.(field),scoringFailure.(field)), ...
        'Independent scoring changed receiver output %s.',field);
end
end

function out=localPUCCH(cfg,withDMRS)
identity=cfg.phy.frame.DefaultIdentity;
ue=struct('UEID',1,'RNTI',cfg.phy.pusch.RNTI,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',identity.ScheduledCCID,'ActiveULBWP',identity.ULBWPID);
frame=struct('K1',4,'K1Source','decoded_dci','PDSCHEndSlot',1,'TargetSlot',5, ...
    'DecodedPRI',0,'PRIFieldWidth',3,'PRIProvenance','unit_fixture', ...
    'FirstCCE',0,'NumCCE',4,'SlotSymbolOwnership','UUUUUUUUUUUUUU', ...
    'FlexibleResolutionProvided',false,'TriggeringEventID','unit_fixture');
bits=true;
if withDMRS, bits=logical([1;0;1]); end
out=sixgr.phy.pucch.PUCCHConfigBuilder.connectedHARQ(cfg,ue,bits,frame);
end

function buffer=localBuffer(p,x)
buffer=sixgr.phy.waveform.WaveformObservationBuffer(p.StartSample, ...
    p.StartSample+size(x,1),p.SampleRateHz,size(x,2));
cut=floor(size(x,1)/2);
buffer.append(sixgr.phy.waveform.WaveformChunk(x(1:cut,:),p.StartSample),p.SampleRateHz);
buffer.append(sixgr.phy.waveform.WaveformChunk(x(cut+1:end,:),p.StartSample+cut),p.SampleRateHz);
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('TEST:MissingRejection','Expected %s.',id);
end
