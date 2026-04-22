function freq = estimateFrequencyOffset(rxWaveform, refWaveform, sampleRateHz)
%ESTIMATEFREQUENCYOFFSET Estimate residual CFO from aligned PRACH samples.
%
% This auxiliary estimator uses the phase increment of the reference-removed
% received sequence. It is a lab-default metric, not a 3GPP-mandated
% algorithm.

rx = localVectorize(rxWaveform);
ref = localVectorize(refWaveform);
L = min(numel(rx), numel(ref));

freq = struct("Valid", false, "EstimateHz", NaN, "Estimator", "phase_increment_lab_default");
if L < 4
    return;
end

rx = rx(1:L);
ref = ref(1:L);
post = rx .* conj(ref);
valid = isfinite(real(post)) & isfinite(imag(post));
post = post(valid);
if numel(post) < 4
    return;
end

delta = post(2:end) .* conj(post(1:end-1));
phaseStep = angle(sum(delta));
freq.Valid = true;
freq.EstimateHz = double(phaseStep) * double(sampleRateHz) / (2*pi);
end

function vec = localVectorize(x)
if isempty(x)
    vec = complex([]);
elseif size(x, 2) > 1
    vec = mean(x, 2);
else
    vec = x(:);
end
end
