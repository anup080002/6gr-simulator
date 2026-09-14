function ok=testPBCHOnlyConfiguredChannel()
% The no-SIB1 path must execute configured noise/channel and received-only sync.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.run.strictMode=true; cfg.run.seed=88120;
cfg.phy.carrier.NCellID=17; cfg.phy.carrier.NSizeGrid=51;
cfg.phy.carrier.SubcarrierSpacing=30; cfg.phy.carrier.SubcarrierSpacing_kHz=30;
cfg.phy.channelBandwidth_MHz=20; cfg.frequency.bandwidth_hz=20e6;
cfg.phy.ssb.enable=true; cfg.phy.pbch.enable=true; cfg.phy.sib1.enable=false;
cfg.channel.model="AWGN"; cfg.channel.awgnOnly=true;
cfg.integration.run_mode="FIXED_SNR_SWEEP";
cfg.integration.configured_snr_is_link_authority=true;
cfg.run.noiseOperatingMode="standalone_awgn_snr_argument";
cfg.run.direction="DL";
requested=[10 20]; measured=nan(size(requested)); variances=measured;
for k=1:numel(requested)
    cfg.channel.snr_dB=requested(k);
    out=sixgr.link.runCellSearch_MIB_SIB1(cfg,'NumSubframes',5, ...
        'SSBIndex',0,'UseRuntimeChannel',true,'WriteArtifacts',false);
    assert(~out.Crash && ~out.Skipped && out.PBCH.Ok, ...
        'Configured PBCH-only AWGN reception failed: %s',out.FailureReason);
    replay=out.RuntimeChannelReplay;
    assert(replay.InjectedNoiseVariance>0 && replay.AppliedAWGNSNR_dB==requested(k));
    assert(replay.NoiseVarianceSource=="fixed_unit_occupied_re_esn0_canonical_ofdm_transform");
    assert(out.CFOEstimateSource=="SSB_Rx_received_PSS_CP_synchronization");
    assert(out.EstimatedCFO_PreCorrection_Hz==out.Sync.FreqOffset_Hz);
    assert(out.PBCH.PostEqSINRValueStatus=="OK" && ~out.PBCH.PreEqualizationNoiseVarianceFloorApplied);
    measured(k)=out.PBCH.PostEqSINR_dB; variances(k)=replay.InjectedNoiseVariance;
    % Same existing occupied-RE PBCH calibration tolerance, not a new gate.
    assert(abs(measured(k)-requested(k))<=3);
    assert(out.ObservationEndSampleExclusive-out.ObservationStartSample== ...
        size(replay.ReceiverInputWaveform,1));
    assert(out.ObservationCompletionTime_s==out.ObservationEndSampleExclusive/out.ObservationSampleRateHz);
    row=sixgr.truth.bindPBCHReceiverSINREvidence(struct( ...
        'ChannelEstimateAvailable',out.ChannelEstimateAvailable, ...
        'EqualizationAvailable',out.EqualizationAvailable),out,out.PBCH);
    assert(row.RuntimeNoiseApplied && row.RuntimeNoiseVarianceMean==variances(k));
    assert(row.RuntimeNoiseVarianceDomain=="time_sample_per_receive_branch");
    assert(row.AppliedAWGNSNR_dB==requested(k) && row.ReceiverHestSINRApplicable);
end
assert(measured(2)>measured(1)+6 && abs(variances(1)/variances(2)-10)<1e-10);
% The requested fading profile must not become a direct TX-to-RX loop when
% SIB1 is disabled. Decoder success is not imposed on this fading fixture.
cfg.channel.model="TDL-C"; cfg.channel.awgnOnly=false;
cfg.channel.tdlProfile="TDL-C"; cfg.channel.fading.model="TDL-C";
[wave,info,contract]=sixgr.phy.dl.SSB_Tx(cfg,'NumSubframes',5,'SSBIndex',0);
capture=sixgr.link.applySSBPBCHChannel(wave,info,contract,cfg,struct(),NaN);
assert(capture.ChannelReplay.RuntimeChannelStateUsed && capture.ChannelReplay.InjectedNoiseVariance>0);
assert(capture.RuntimeDLChannelState.Initialized && capture.RuntimeDLChannelState.Materialized);
assert(~isequal(capture.Waveform,capture.TransmitWaveform));
ok=true; fprintf('PBCH_ONLY_CONFIGURED_CHANNEL_PASS AWGN=2 fading=1; no integrated 12 dB qualification.\n');
end
