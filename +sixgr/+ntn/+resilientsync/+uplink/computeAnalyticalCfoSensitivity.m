function tableOut = computeAnalyticalCfoSensitivity(frequencyErrorHz, scsHz, snrDb)
%COMPUTEANALYTICALCFOSENSITIVITY Analytical OFDM CFO reference only.

[f,s] = ndgrid(double(frequencyErrorHz(:)), double(snrDb(:)));
epsilon = f ./ double(scsHz);
g = ones(size(epsilon));
mask = abs(epsilon) > eps;
g(mask) = (sin(pi*epsilon(mask)) ./ (pi*epsilon(mask))).^2;
sir = g ./ max(1-g, eps);
gamma = 10.^(s/10);
gammaEff = gamma .* g ./ (1 + gamma .* (1-g));
tableOut = table(f(:), s(:), epsilon(:), g(:), ...
    10*log10(sir(:)), 10*log10(gammaEff(:)), ...
    repmat("ANALYTICAL",numel(f),1), ...
    'VariableNames', {'FrequencyError_Hz','SNR_dB','NormalizedCFO', ...
    'CoherentPowerGain','SIR_ICI_dB','EffectiveSNR_dB','Provenance'});
end
