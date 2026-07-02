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
gainDb = double(sixgr.util.structGet(replay, "AGCGain_dB", 0));
if logical(sixgr.util.structGet(replay, "AGCApplied", false)) && isfinite(gainDb)
    gainLinear = 10.^(gainDb ./ 20);
end
if ~(isfinite(gainLinear) && gainLinear > 0)
    gainLinear = 1;
end

qVar = localCompositeADCQuantizationNoiseVariance(replay);
preNVar = double(sixgr.util.structGet(replay, "InjectedNoiseVariance", NaN));
if isfinite(preNVar) && preNVar >= 0
    replay.InjectedNoiseVariancePreCompositeFrontEnd = double(preNVar);
    replay.InjectedNoiseVariance = double(preNVar .* gainLinear.^2 + max(0, qVar));
    source = string(sixgr.util.structGet(replay, "NoiseVarianceSource", ""));
    if strlength(strtrim(source)) == 0
        source = "receiver_noise_variance";
    end
    replay.NoiseVarianceSource = char(source + "_post_composite_front_end_agc_adc");
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
end

function qVar = localCompositeADCQuantizationNoiseVariance(replay)
qVar = 0;
if ~logical(sixgr.util.structGet(replay, "ADCQuantizationApplied", false))
    return;
end
bits = double(sixgr.util.structGet(replay, "ADCBits", NaN));
fullScale = double(sixgr.util.structGet(replay, "ADCFullScale", NaN));
if ~(isfinite(bits) && bits > 0 && bits < 32 && isfinite(fullScale) && fullScale > 0)
    return;
end
levels = 2^max(1, round(bits));
maxCode = levels / 2 - 1;
if ~(isfinite(maxCode) && maxCode > 0)
    return;
end
step = double(fullScale) ./ double(maxCode);
qVar = double(step.^2 ./ 6);
end
