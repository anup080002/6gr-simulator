function replay = applyCompositeFrontEndVarianceReplay(replay)
%APPLYCOMPOSITEFRONTENDVARIANCEREPLAY Move variance/tensors into post-FE domain.
%   The composite receiver front end is applied after shared-slot summation.
%   Noise variance and stored interference tensors must therefore be in the
%   same sample domain as the waveform passed to the receiver.

if nargin < 1 || ~isstruct(replay)
    replay = struct();
    return;
end

gainLinear = 1;
gainDb = double(sixgr.util.structGet(replay, "AGCGain_dB", NaN));
if logical(sixgr.util.structGet(replay,"AGCGainIsTimeVarying",false))
    error('RF:NonstationaryNoiseRequiresReceivedEstimation', ...
        'Time-varying AGC requires received-resource noise/covariance estimation, not a unity or averaged scalar gain.');
end
if logical(sixgr.util.structGet(replay, "AGCApplied", false))
    if ~(isreal(gainDb) && isscalar(gainDb) && isfinite(gainDb))
        error('RF:MissingAppliedAGCGain','A post-RF noise calculation requires the actual recorded AGC gain.');
    end
    gainLinear = 10.^(gainDb ./ 20);
end
if ~(isfinite(gainLinear) && gainLinear > 0)
    error('RF:InvalidAppliedAGCGain','An invalid applied gain cannot be replaced with unity.');
end

qVar = localCompositeADCQuantizationNoiseVariance(replay);
preNVar = double(sixgr.util.structGet(replay, "InjectedNoiseVariance", NaN));
if isfinite(preNVar) && preNVar >= 0
    replay.InjectedNoiseVariancePreCompositeFrontEnd = double(preNVar);
    replay.InjectedNoiseVariancePreCompositeFrontEndDomain = ...
        "receiver_sample_waveform_pre_composite_front_end";
    preSource = string(sixgr.util.structGet(replay, "NoiseVarianceSource", ""));
    if strlength(strtrim(preSource)) == 0
        preSource = "receiver_noise_variance";
    end
    replay.InjectedNoiseVariancePreCompositeFrontEndSource = char(preSource);
    postNVar = double(preNVar .* gainLinear.^2 + max(0, qVar));
    replay.InjectedNoiseVariancePostCompositeFrontEnd = postNVar;
    replay.InjectedNoiseVariancePostCompositeFrontEndDomain = ...
        "receiver_sample_waveform_post_composite_front_end";
    % Preserve InjectedNoiseVariance as a compatibility alias, but make the
    % alias and its plane explicit.  Scientific reports must use one of the
    % versioned pre/post fields above rather than inferring a domain.
    replay.InjectedNoiseVariance = postNVar;
    replay.InjectedNoiseVarianceAliasOf = ...
        "InjectedNoiseVariancePostCompositeFrontEnd";
    replay.InjectedNoiseVarianceDomain = ...
        "receiver_sample_waveform_post_composite_front_end";
    replay.NoiseVarianceSource = char(preSource + "_post_composite_front_end_agc_adc");
    replay.InjectedNoiseVariancePostCompositeFrontEndSource = ...
        replay.NoiseVarianceSource;
end

if isfinite(double(sixgr.util.structGet(replay, ...
        "DesiredSignalPowerBeforeNoise", NaN)))
    replay.DesiredSignalPowerBeforeNoiseDomain = ...
        "receiver_sample_waveform_pre_noise_pre_composite_front_end";
end
if isfinite(double(sixgr.util.structGet(replay, ...
        "CompositeSignalPowerBeforeNoise", NaN)))
    replay.CompositeSignalPowerBeforeNoiseDomain = ...
        "receiver_sample_waveform_pre_noise_pre_composite_front_end";
end

if isfield(replay, "InterferenceContributionTensor") && ~isempty(replay.InterferenceContributionTensor)
    replay.InterferenceContributionTensor = replay.InterferenceContributionTensor .* ...
        cast(gainLinear, "like", replay.InterferenceContributionTensor);
    replay.InterferenceContributionDomain = "receiver_sample_waveform_post_composite_front_end_linear_gain";
end
if isfield(replay, "InterferenceCovariance") && ~isempty(replay.InterferenceCovariance) && isnumeric(replay.InterferenceCovariance)
    replay.InterferenceCovariance = replay.InterferenceCovariance .* double(gainLinear.^2);
end
if isfinite(double(sixgr.util.structGet(replay, "InterferenceWaveformVariance", NaN)))
    replay.InterferenceWaveformVariancePreCompositeFrontEnd = double(replay.InterferenceWaveformVariance);
    replay.InterferenceWaveformVariance = double(replay.InterferenceWaveformVariance) .* double(gainLinear.^2);
end

replay.CompositeReceiverFrontEndGainLinear = double(gainLinear);
replay.CompositeReceiverFrontEndNoiseVarianceDomain = "receiver_sample_waveform_post_composite_front_end";
replay.CompositeReceiverFrontEndADCQuantizationNoiseVariance = double(qVar);
replay.CompositeReceiverNoiseVarianceMethod = "constant_recorded_agc_gain_white_noise_propagation";
if logical(sixgr.util.structGet(replay,"ADCQuantizationApplied",false))
    replay.CompositeReceiverNoiseVarianceMethod = ...
        "constant_gain_thermal_plus_measured_ADC_error_power_uncorrelated_estimate";
end
% ADC error power is measured, but adding its variance to thermal noise
% assumes zero cross-correlation. Do not label that estimator as an exact
% measured decomposition of the post-quantizer disturbance.
replay.CompositeReceiverNoiseVarianceAssumesUncorrelatedADCError = ...
    logical(sixgr.util.structGet(replay,"ADCQuantizationApplied",false));
end

function qVar = localCompositeADCQuantizationNoiseVariance(replay)
qVar = 0;
if ~logical(sixgr.util.structGet(replay, "ADCQuantizationApplied", false))
    return;
end
qVar = double(sixgr.util.structGet(replay, ...
    "ADCQuantizationErrorVariance", NaN));
if ~(isscalar(qVar) && isfinite(qVar) && qVar >= 0)
    error("RF:CovarianceInvalid", ...
        "Post-ADC variance replay requires covariance measured from the actual quantization-error samples.");
end
end
