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
[kSub, lSub] = ind2sub([K, L, numRefPorts], refInd);
valid = kSub >= 1 & kSub <= K & lSub >= 1 & lSub <= L;
kSub = kSub(valid);
lSub = lSub(valid);
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

function sampleRate = localCarrierSampleRate(carrier)
sampleRate = NaN;
try
    ofdmInfo = nrOFDMInfo(carrier);
    sampleRate = double(sixgr.util.structGet(ofdmInfo, "SampleRate", NaN));
catch
end
end

function symbolTimes = localSymbolCenterTimes(carrier, sampleRateHz, symbolsPerSlot)
symbolTimes = NaN(max(1, round(double(symbolsPerSlot))), 1);
try
    ofdmInfo = nrOFDMInfo(carrier);
    symbolLengths = double(sixgr.util.structGet(ofdmInfo, "SymbolLengths", []));
    if isempty(symbolLengths)
        symbolLengths = double(sixgr.util.structGet(ofdmInfo, "CyclicPrefixLengths", [])) + ...
            double(sixgr.util.structGet(ofdmInfo, "Nfft", NaN));
    end
    symbolLengths = symbolLengths(:);
    if isempty(symbolLengths) || any(~isfinite(symbolLengths))
        return;
    end
    if numel(symbolLengths) < symbolsPerSlot
        symbolLengths(end + 1:symbolsPerSlot, 1) = symbolLengths(end);
    end
    symbolLengths = symbolLengths(1:symbolsPerSlot);
    symbolTimes = (cumsum(symbolLengths) - 0.5 .* symbolLengths) ./ max(double(sampleRateHz), eps);
catch
end
end
