function est = PDCCHChannelEstimator(rxGrid4D, dmrs, ~, copyIndex, noiseVar)
%PDCCHChannelEstimator Estimate the control-channel response from DMRS.

if nargin < 5 || isempty(noiseVar)
    noiseVar = 0;
end

if isempty(dmrs.Locations)
    est = struct("Hhat", complex([]), "NMSE", NaN, "NoiseVar", noiseVar, "QualityMetric", NaN);
    return;
end

slotMask = dmrs.Locations.CopyIndex == copyIndex;
loc = dmrs.Locations(slotMask, :);
txSym = dmrs.Symbols(slotMask);
if isempty(loc)
    est = struct("Hhat", complex([]), "NMSE", NaN, "NoiseVar", noiseVar, "QualityMetric", NaN);
    return;
end

nRx = size(rxGrid4D, 3);
hDmrs = complex(zeros(height(loc), nRx));
for i = 1:height(loc)
    y = squeeze(rxGrid4D(loc.Subcarrier(i)+1, loc.Symbol(i)+1, :, loc.SlotIndex(i)));
    hDmrs(i,:) = (y(:).' ./ txSym(i));
end

hMean = repmat(mean(hDmrs, 1), height(loc), 1);
residual = hDmrs - hMean;
nmse = mean(abs(hDmrs(:) - hMean(:)).^2) / max(mean(abs(hDmrs(:)).^2), eps);
est = struct();
est.Hhat = hDmrs;
est.HMean = mean(hDmrs, 1);
est.NMSE = double(nmse);
est.NoiseVar = double(noiseVar);
est.QualityMetric = mean(abs(hDmrs(:)).^2) / max(noiseVar, eps);
est.Residual = residual;
end
