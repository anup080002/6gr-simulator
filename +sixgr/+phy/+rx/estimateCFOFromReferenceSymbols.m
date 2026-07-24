function [freqHz, info] = estimateCFOFromReferenceSymbols(rxGrid, refInd, refSym, carrier, sampleRateHz)
%estimateCFOFromReferenceSymbols Estimate common frequency offset from RS phase drift.
%
% The estimate is derived from received reference-symbol phase versus OFDM
% symbol time. It is only available when the reference mapping spans at
% least two distinct OFDM symbols.

info = struct( ...
    "EstimateAvailable", false, ...
    "EstimatedCFO_Hz", NaN, ...
    "Status", "not_computed", ...
    "Source", "reference_symbol_phase_slope", ...
    "NumReferenceRE", 0, ...
    "NumSymbolsUsed", 0, ...
    "SymbolIndices", zeros(0, 1), ...
    "SampleRate_Hz", NaN);
freqHz = NaN;

if isempty(rxGrid) || isempty(refInd) || isempty(refSym)
    info.Status = "empty_reference_or_grid";
    return;
end
if ~isnumeric(rxGrid) || ~isnumeric(refInd) || ~isnumeric(refSym)
    info.Status = "non_numeric_reference_or_grid";
    return;
end

sampleRateHz = double(sampleRateHz);
if ~(isscalar(sampleRateHz) && isfinite(sampleRateHz) && sampleRateHz > 0)
    sampleRateHz = localCarrierSampleRate(carrier);
end
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    info.Status = "sample_rate_unavailable";
    return;
end

dims = size(rxGrid);
if numel(dims) < 2 || dims(1) < 1 || dims(2) < 1
    info.Status = "rx_grid_not_resource_grid";
    return;
end
K = double(dims(1));
L = double(dims(2));
refInd = double(refInd(:));
refSym = refSym(:);
n = min(numel(refInd), numel(refSym));
refInd = refInd(1:n);
refSym = refSym(1:n);
valid = isfinite(refInd) & refInd >= 1 & abs(refSym) > 0 & ...
    isfinite(real(refSym)) & isfinite(imag(refSym));
refInd = round(refInd(valid));
refSym = refSym(valid);
if isempty(refInd)
    info.Status = "no_valid_reference_symbols";
    return;
end

numRefPorts = max(1, ceil(max(refInd) / max(K * L, 1)));
[kSub, lSub, pSub] = ind2sub([K, L, numRefPorts], refInd);
valid = kSub >= 1 & kSub <= K & lSub >= 1 & lSub <= L;
kSub = kSub(valid);
lSub = lSub(valid);
pSub = pSub(valid);
refSym = refSym(valid);
if isempty(kSub)
    info.Status = "reference_indices_outside_grid";
    return;
end

symbolTimes = localSymbolCenterTimes(carrier, sampleRateHz, L);
if numel(symbolTimes) < L
    info.Status = "symbol_times_unavailable";
    return;
end

uniqueSymbols = unique(lSub(:), "stable");
[pairFreqHz, pairInfo] = localPairwiseCommonREEstimate(rxGrid, refSym, kSub, lSub, pSub, uniqueSymbols, symbolTimes);
if logical(pairInfo.EstimateAvailable)
    info.EstimateAvailable = true;
    info.EstimatedCFO_Hz = double(pairFreqHz);
    info.Status = "OK";
    info.Source = "reference_symbol_common_re_phase_slope";
    info.NumReferenceRE = double(numel(refInd));
    info.NumSymbolsUsed = double(pairInfo.NumSymbolsUsed);
    info.SymbolIndices = double(pairInfo.SymbolIndices(:));
    info.SampleRate_Hz = double(sampleRateHz);
    info.NumSymbolPairsUsed = double(pairInfo.NumSymbolPairsUsed);
    info.NumCommonRESamplesUsed = double(pairInfo.NumCommonRESamplesUsed);
    freqHz = double(pairFreqHz);
    return;
end

phaseObs = NaN(numel(uniqueSymbols), 1);
timeObs = NaN(numel(uniqueSymbols), 1);
for ii = 1:numel(uniqueSymbols)
    lSym = uniqueSymbols(ii);
    mask = (lSub == lSym);
    if ~any(mask)
        continue;
    end
    hObs = zeros(nnz(mask), 1);
    kk = kSub(mask);
    refs = refSym(mask);
    for jj = 1:numel(kk)
        rxVals = squeeze(rxGrid(kk(jj), lSym, :));
        rxVals = rxVals(:);
        rxVals = rxVals(isfinite(real(rxVals)) & isfinite(imag(rxVals)));
        if isempty(rxVals)
            hObs(jj) = NaN;
        else
            hObs(jj) = mean(rxVals, "omitnan") ./ refs(jj);
        end
    end
    hObs = hObs(isfinite(real(hObs)) & isfinite(imag(hObs)));
    if isempty(hObs)
        continue;
    end
    hMean = mean(hObs(:), "omitnan");
    if ~(isfinite(real(hMean)) && isfinite(imag(hMean)) && abs(hMean) > eps)
        continue;
    end
    phaseObs(ii) = angle(hMean);
    timeObs(ii) = symbolTimes(lSym);
end

validObs = isfinite(phaseObs) & isfinite(timeObs);
phaseObs = phaseObs(validObs);
timeObs = timeObs(validObs);
symbolObs = uniqueSymbols(validObs);
info.NumReferenceRE = double(numel(refInd));
info.NumSymbolsUsed = double(numel(phaseObs));
info.SymbolIndices = double(symbolObs(:) - 1);
info.SampleRate_Hz = double(sampleRateHz);
if numel(phaseObs) < 2
    info.Status = "fewer_than_two_reference_symbol_times";
    return;
end

phaseObs = unwrap(phaseObs(:));
fit = polyfit(timeObs(:), phaseObs(:), 1);
freqHz = fit(1) ./ (2 * pi);
if ~isfinite(freqHz)
    info.Status = "frequency_estimate_nonfinite";
    freqHz = NaN;
    return;
end

info.EstimateAvailable = true;
info.EstimatedCFO_Hz = double(freqHz);
info.Status = "OK";
end

function [freqHz, info] = localPairwiseCommonREEstimate(rxGrid, refSym, kSub, lSub, pSub, uniqueSymbols, symbolTimes)
freqHz = NaN;
info = struct( ...
    "EstimateAvailable", false, ...
    "NumSymbolPairsUsed", 0, ...
    "NumCommonRESamplesUsed", 0, ...
    "NumSymbolsUsed", 0, ...
    "SymbolIndices", zeros(0, 1));
if numel(uniqueSymbols) < 2
    return;
end
K = size(rxGrid, 1);
pairFreq = zeros(0, 1);
pairWeight = zeros(0, 1);
symbolsUsed = false(numel(uniqueSymbols), 1);
for ia = 1:numel(uniqueSymbols)-1
    l1 = uniqueSymbols(ia);
    mask1 = lSub == l1;
    if ~any(mask1)
        continue;
    end
    key1 = double(kSub(mask1)) + double(K) .* double(pSub(mask1) - 1);
    k1 = kSub(mask1);
    ref1 = refSym(mask1);
    for ib = ia+1:numel(uniqueSymbols)
        l2 = uniqueSymbols(ib);
        dt = double(symbolTimes(l2) - symbolTimes(l1));
        if ~(isfinite(dt) && dt > 0)
            continue;
        end
        mask2 = lSub == l2;
        if ~any(mask2)
            continue;
        end
        key2 = double(kSub(mask2)) + double(K) .* double(pSub(mask2) - 1);
        k2 = kSub(mask2);
        ref2 = refSym(mask2);
        [~, idx1, idx2] = intersect(key1(:), key2(:), "stable");
        if isempty(idx1)
            continue;
        end
        corrSum = complex(0, 0);
        sampleCount = 0;
        for jj = 1:numel(idx1)
            r1 = ref1(idx1(jj));
            r2 = ref2(idx2(jj));
            if ~(isfinite(real(r1)) && isfinite(imag(r1)) && abs(r1) > eps && ...
                    isfinite(real(r2)) && isfinite(imag(r2)) && abs(r2) > eps)
                continue;
            end
            rx1 = squeeze(rxGrid(k1(idx1(jj)), l1, :));
            rx2 = squeeze(rxGrid(k2(idx2(jj)), l2, :));
            rx1 = rx1(:);
            rx2 = rx2(:);
            n = min(numel(rx1), numel(rx2));
            if n < 1
                continue;
            end
            rx1 = rx1(1:n);
            rx2 = rx2(1:n);
            valid = isfinite(real(rx1)) & isfinite(imag(rx1)) & ...
                isfinite(real(rx2)) & isfinite(imag(rx2));
            if ~any(valid)
                continue;
            end
            h1 = rx1(valid) ./ r1;
            h2 = rx2(valid) ./ r2;
            cross = h2(:) .* conj(h1(:));
            cross = cross(isfinite(real(cross)) & isfinite(imag(cross)) & abs(cross) > eps);
            if isempty(cross)
                continue;
            end
            corrSum = corrSum + sum(cross, "all");
            sampleCount = sampleCount + numel(cross);
        end
        if sampleCount < 1 || ~(isfinite(real(corrSum)) && isfinite(imag(corrSum))) || abs(corrSum) <= eps
            continue;
        end
        pairFreq(end+1, 1) = angle(corrSum) ./ (2 * pi * dt); %#ok<AGROW>
        pairWeight(end+1, 1) = max(abs(corrSum), eps) * double(sampleCount); %#ok<AGROW>
        symbolsUsed(ia) = true;
        symbolsUsed(ib) = true;
        info.NumSymbolPairsUsed = double(info.NumSymbolPairsUsed) + 1;
        info.NumCommonRESamplesUsed = double(info.NumCommonRESamplesUsed) + double(sampleCount);
    end
end
validFreq = isfinite(pairFreq) & isfinite(pairWeight) & pairWeight > 0;
if ~any(validFreq)
    return;
end
pairFreq = pairFreq(validFreq);
pairWeight = pairWeight(validFreq);
freqHz = sum(pairFreq .* pairWeight, "omitnan") ./ sum(pairWeight, "omitnan");
if ~isfinite(freqHz)
    freqHz = NaN;
    return;
end
info.EstimateAvailable = true;
info.NumSymbolsUsed = double(sum(symbolsUsed));
info.SymbolIndices = double(uniqueSymbols(symbolsUsed) - 1);
end

function sampleRate = localCarrierSampleRate(carrier)
sampling = sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
sampleRate = double(sampling.SampleRateHz);
end

function symbolTimes = localSymbolCenterTimes(carrier, sampleRateHz, symbolsPerSlot)
validateattributes(symbolsPerSlot, {'numeric'}, ...
    {'scalar','integer','positive','finite'});
sampling = sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
if double(symbolsPerSlot) ~= double(sampling.SymbolsPerSlot)
    error("sixgr:phy:frame:InconsistentOFDMNumerology", ...
        "Reference grid has %d symbols, while the canonical carrier has %d.", ...
        symbolsPerSlot, sampling.SymbolsPerSlot);
end
symbolLengths = double(sampling.Nfft) + ...
    double(sampling.CyclicPrefixLengthsPerSlot(:));
if abs(double(sampleRateHz) - double(sampling.SampleRateHz)) > ...
        max(1e-9 * double(sampling.SampleRateHz), 1e-6)
    error("sixgr:phy:frame:InconsistentOFDMSampleRate", ...
        "Reference-symbol timing sample rate %.15g Hz differs from the " + ...
        "canonical carrier rate %.15g Hz.", ...
        sampleRateHz, sampling.SampleRateHz);
end
symbolTimes = (cumsum(symbolLengths) - 0.5 .* symbolLengths) ./ ...
    double(sampling.SampleRateHz);
end
