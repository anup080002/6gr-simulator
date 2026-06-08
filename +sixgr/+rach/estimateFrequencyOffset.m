function freq = estimateFrequencyOffset(rxWaveform, refWaveform, sampleRateHz)
%ESTIMATEFREQUENCYOFFSET Robust residual CFO estimate from aligned PRACH samples.

rx = localVectorize(rxWaveform);
ref = localVectorize(refWaveform);
L = min(numel(rx), numel(ref));

freq = struct( ...
    "Valid", false, ...
    "EstimateHz", NaN, ...
    "Estimator", "mlr_multilag_ls", ...
    "AmbiguityRange_Hz", NaN);

sampleRateHz = double(sampleRateHz);
if L < 8 || ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    return;
end

rx = rx(1:L);
ref = ref(1:L);
post = rx .* conj(ref);
valid = isfinite(real(post)) & isfinite(imag(post));
post = post(valid);
N = numel(post);
if N < 8
    return;
end

maxLag = max(1, min(floor(N/4), 16));
lags = (1:maxLag).';
phases = nan(maxLag, 1);
weights = nan(maxLag, 1);
for iLag = 1:maxLag
    m = lags(iLag);
    Rm = mean(post(m+1:end) .* conj(post(1:end-m)));
    phases(iLag) = angle(Rm);
    weights(iLag) = max(abs(Rm), eps);
end

finite = isfinite(phases) & isfinite(weights) & weights > 0;
if ~any(finite)
    return;
end
lags = lags(finite);
phases = unwrap(phases(finite));
weights = weights(finite);
den = sum(weights .* (double(lags).^2));
if ~(isfinite(den) && den > 0)
    return;
end

phaseStep = sum(weights .* double(lags) .* phases) ./ den;
freq.Valid = isfinite(phaseStep);
freq.EstimateHz = double(phaseStep) * sampleRateHz / (2*pi);
freq.AmbiguityRange_Hz = sampleRateHz / (2 * maxLag);
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
