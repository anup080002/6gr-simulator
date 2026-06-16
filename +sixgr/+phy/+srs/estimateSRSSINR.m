function out = estimateSRSSINR(det, srsCfg)
%ESTIMATESRSSINR Estimate SRS SINR from sequence projection residuals.

obs = det.Extracted.ObservedSymbols(:);
ref = det.Extracted.ReferenceSymbols(:);
N = min(numel(obs), numel(ref));
sinrDb = NaN;
noisePower = NaN;
signalPower = NaN;
if N > 0
    obs = obs(1:N);
    ref = ref(1:N);
    mask = isfinite(real(obs)) & isfinite(imag(obs)) & ...
        isfinite(real(ref)) & isfinite(imag(ref)) & abs(ref) > eps;
    if any(mask)
        obs = obs(mask);
        ref = ref(mask);
        h = (ref' * obs) / max(ref' * ref, eps);
        signal = h .* ref;
        residual = obs - signal;
        signalPower = mean(abs(signal).^2, "omitnan");
        noisePower = mean(abs(residual).^2, "omitnan");
        sinrDb = 10 * log10(max(signalPower / max(noisePower, eps), eps));
    end
end
out = struct();
out.SINR_dB = double(sinrDb);
out.SignalPower = double(signalPower);
out.NoisePower = double(noisePower);
out.ConfigHash = string(srsCfg.ConfigHash);
out.TruthStatus = "real_lls_evidence";
end
