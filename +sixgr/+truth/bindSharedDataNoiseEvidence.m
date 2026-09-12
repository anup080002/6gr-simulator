function replay=bindSharedDataNoiseEvidence(planes,prepared,planeID,replay)
% Independent scalar bookkeeping from the SAME physical execution.
% The serving-link sample SNR includes every serving-transmitter component
% in this capture. It is not PDSCH/PUSCH SINR, RSRP, or the nominal SNR.
% No reference samples or channel coefficients enter a practical receiver.
assert(isa(prepared,'sixgr.link.PreparedDataTransmission'), ...
    'sixgr:truth:SharedDataNoisePreparationRequired','Retain the exact data preparation.');
[reference,evidence]=sixgr.truth.sharedLinkScoringObservation(planes,prepared,planeID);
assert(~evidence.ReceiverEstimatorInput && evidence.AdditionalChannelExecutions==0 && ...
    evidence.AdditionalRFExecutions==0,'sixgr:truth:SharedNoiseReferenceReexecuted', ...
    'Noise bookkeeping cannot regenerate a noiseless waveform.');
assert(string(replay.InjectedNoiseVarianceDomain)=="receiver_sample_waveform_pre_composite_front_end", ...
    'sixgr:truth:SharedInjectedNoisePlaneMismatch','Injected variance belongs before receiver RF.');
variance=double(replay.InjectedNoiseVariance);
mode=lower(strtrim(string(replay.NoiseOperatingMode)));
assert(isfinite(variance) && variance>0, ...
    'sixgr:truth:SharedNoiseVarianceInvalid','The executed sample variance must be finite and positive.');
if mode=="receiver_noise_figure_thermal_noise"
    thermal=double(replay.ThermalNoisePSD_mWPerHz)*double(replay.ThermalSampleNoiseBandwidth_Hz);
    assert(isfinite(thermal) && abs(variance-thermal)<=1e-10*variance, ...
        'sixgr:truth:SharedThermalNoiseClosure', ...
        'The executed sample variance must agree with the actual thermal PSD and bandwidth.');
    nominalSource='actual_whole_capture_serving_transmitter_link_sample_power_over_executed_thermal_variance_not_data_SINR';
elseif mode=="standalone_awgn_snr_argument"
    requested=double(sixgr.util.structGet(replay,'RequestedAWGNReferenceSNR_dB',NaN));
    signalEnergy=double(sixgr.util.structGet(replay,'SignalEnergyPerOccupiedRE',NaN));
    gridVariance=double(sixgr.util.structGet(replay,'GridNoiseVariance',NaN));
    transformGain=double(sixgr.util.structGet(replay,'SampleToGridNoiseVarianceGain',NaN));
    expectedGridVariance=signalEnergy*10^(-requested/10);
    expectedSampleVariance=expectedGridVariance/transformGain;
    assert(isfinite(requested) && isfinite(signalEnergy) && signalEnergy>0 && ...
        isfinite(gridVariance) && gridVariance>0 && isfinite(transformGain) && transformGain>0 && ...
        abs(gridVariance-expectedGridVariance)<=1e-12*gridVariance && ...
        abs(variance-expectedSampleVariance)<=1e-12*variance, ...
        'sixgr:truth:SharedFixedSNRNoiseClosure', ...
        'Fixed-SNR execution must close from occupied-RE Es/N0 through the canonical OFDM variance transform.');
    assert(string(sixgr.util.structGet(replay,'SharedNoiseCalibrationSource',''))== ...
        "fixed_once_from_unit_occupied_re_energy_and_canonical_ofdm_noise_transform", ...
        'sixgr:truth:SharedFixedSNRCalibrationSourceMismatch', ...
        'Fixed-SNR noise must be calibrated once and must not follow instantaneous faded waveform power.');
    % This is the applied AWGN reference operating point, not a measured
    % post-channel SINR.  It is valid because the executed sample variance
    % above closes exactly through the OFDM transform from the requested
    % occupied-RE Es/N0.
    replay.AppliedAWGNSNR_dB=requested;
    replay.AppliedAWGNSNRSource= ...
        'executed_fixed_occupied_RE_EsN0_with_exact_OFDM_variance_closure_not_data_SINR';
    nominalSource='actual_whole_capture_serving_link_sample_power_over_fixed_occupied_RE_EsN0_noise_variance_diagnostic_not_configured_SNR_not_data_SINR';
else
    error('sixgr:truth:SharedNoiseOperatingModeUnsupported', ...
        'Unsupported shared noise operating mode %s.',mode);
end
samples=reference.readComplete();
assert(all(isfinite(samples(:))),'sixgr:truth:NonfiniteSharedSignalPower','Scoring samples must be finite.');
power=mean(abs(double(samples(:))).^2);
assert(isfinite(power) && power>0,'sixgr:truth:MissingExecutedSharedLinkEnergy','No measured serving-link energy in the receive capture.');
replay.InjectedNoiseVariancePreCompositeFrontEnd=variance;
replay.InjectedNoiseVariancePreCompositeFrontEndDomain='receiver_sample_waveform_pre_composite_front_end';
replay.InjectedNoiseVariancePreCompositeFrontEndSource=replay.NoiseVarianceSource;
% RF/ADC plus actual gain compensation is not a scalar noise transform.
% Leave its injected variance unavailable; the receiver estimates its own
% pre/post-equalization and LLR disturbance from received reference REs.
replay.InjectedNoiseVariancePostCompositeFrontEnd=NaN;
replay.InjectedNoiseVariancePostCompositeFrontEndDomain='receiver_sample_waveform_post_composite_front_end';
replay.InjectedNoiseVariancePostCompositeFrontEndSource= ...
    'unavailable_after_actual_RF_ADC_gain_compensation_receiver_reference_RE_estimation_required';
replay.GridNoiseVarianceDomain='equivalent_OFDM_grid_of_pre_front_end_injected_sample_noise';
replay.DesiredSignalPowerBeforeNoise=power;
replay.DesiredSignalPowerBeforeNoiseDomain='receiver_sample_waveform_pre_noise_pre_composite_front_end';
replay.ConfiguredSNRReferencePlane=string(sixgr.util.structGet(replay, ...
    'SNRReferencePlane','occupied_resource_grid_re_pre_equalization'));
replay.SNRReferencePlane='receiver_sample_waveform_pre_composite_front_end';
replay.AppliedNoiseSNR_dB=10*log10(power/variance);
replay.AppliedNoiseSNRSource=nominalSource;
replay.ServingLinkPowerMeasurementEvidence=evidence;
channelArrivalDelay=double(sixgr.util.structGet(evidence, ...
    'RuntimeChannelExpectedEarliestArrivalDelay_samples',NaN));
receiveWindowDisplacement=double(prepared.StartSample-prepared.ReceiveStartSample);
if isfinite(channelArrivalDelay) && isfinite(receiveWindowDisplacement) && ...
        isfinite(double(replay.InjectedTimingOffset_samples))
    replay.TrueReceiverTimingOffset_samples=receiveWindowDisplacement + ...
        channelArrivalDelay + double(replay.InjectedTimingOffset_samples);
    replay.TrueReceiverTimingOffsetSource= ...
        'prepared_tx_minus_rx_observation_origin_plus_executed_channel_filter_and_minimum_path_delay_plus_applied_RF_timing_offset';
    replay.ReceiveWindowDisplacement_samples=receiveWindowDisplacement;
    replay.RuntimeChannelFilterDelay_samples=double(evidence.RuntimeChannelFilterDelay_samples);
    replay.RuntimeChannelMinimumPathDelay_samples=double(evidence.RuntimeChannelMinimumPathDelay_samples);
    replay.TimingTruthReceiverEstimatorInput=false;
else
    replay.TrueReceiverTimingOffset_samples=NaN;
    replay.TrueReceiverTimingOffsetSource='unavailable_incomplete_executed_shared_channel_timing_truth';
    replay.TimingTruthReceiverEstimatorInput=false;
end
end
