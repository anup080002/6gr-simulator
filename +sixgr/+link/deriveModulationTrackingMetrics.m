function [metrics, constellationT] = deriveModulationTrackingMetrics(tx, rx, cfg, direction)
%DERIVEMODULATIONTRACKINGMETRICS Measured modulation/shaping and tracking metrics.

direction = upper(string(direction));
metrics = struct( ...
    "EVM_rms", NaN, ...
    "SymbolErrors", NaN, ...
    "SymbolsCompared", NaN, ...
    "SymbolErrorRate", NaN, ...
    "ResidualInterferencePower_dB", NaN, ...
    "PAPR_dB", NaN, ...
    "PeakClippingEvents", NaN, ...
    "LLRMeanAbs", NaN, ...
    "LLRStdAbs", NaN, ...
    "LLRImbalance", NaN, ...
    "ModulationMappingSensitivity", NaN, ...
    "ShapingRateLoss", NaN, ...
    "DistributionMatchingLatency_ms", NaN, ...
    "HighOrderRobustness", NaN, ...
    "DetectorComplexityUnits", NaN, ...
    "DataRECount", NaN, ...
    "DMRSRECount", NaN, ...
    "PTRSRECount", NaN, ...
    "RSOverheadFraction", NaN, ...
    "EstimatedDopplerHz", NaN, ...
    "PhaseTrackingError_deg", NaN, ...
    "QCLAccuracy", NaN, ...
    "ChannelAgingLoss_dB", NaN, ...
    "InterpolationLoss_dB", NaN, ...
    "MismatchSensitivity_dB", NaN);
constellationT = table();

modulation = localResolveModulation(tx, cfg, direction);
eqSymRaw = localEnsureColumn(sixgr.util.structGet(rx, "EqualizedSymbols", []));
txSym = localReferenceSymbols(tx, direction);
detectorSym = localDetectorSymbols(rx, direction);

[refSym, eqSymAligned, eqSymRawUse] = localPrepareAlignedSymbols(txSym, eqSymRaw);
hardSym = localHardDecisionSymbols(eqSymAligned, modulation, refSym);
if isempty(refSym)
    refSym = txSym;
end

if ~isempty(eqSymAligned) && ~isempty(refSym)
    L = min(numel(eqSymAligned), numel(refSym));
    err = eqSymAligned(1:L) - refSym(1:L);
    pRef = max(mean(abs(refSym(1:L)).^2, "omitnan"), eps);
    metrics.EVM_rms = sqrt(mean(abs(err).^2, "omitnan") / pRef);
end

if ~isempty(refSym) && ~isempty(hardSym)
    L = min(numel(refSym), numel(hardSym));
    symErr = sum(abs(refSym(1:L) - hardSym(1:L)) > 1e-8);
    metrics.SymbolErrors = double(symErr);
    metrics.SymbolsCompared = double(L);
    metrics.SymbolErrorRate = double(symErr) / max(double(L), 1);
    resid = eqSymAligned(1:L) - hardSym(1:L);
    metrics.ResidualInterferencePower_dB = 10 * log10(max(mean(abs(resid).^2, "omitnan"), eps));
end

wf = sixgr.util.structGet(tx, "Waveform", []);
if ~isempty(wf)
    metrics.PAPR_dB = localPAPRdB(wf);
    metrics.PeakClippingEvents = localPeakClippingEvents(wf, cfg);
end

[metrics.LLRMeanAbs, metrics.LLRStdAbs, metrics.LLRImbalance, metrics.ModulationMappingSensitivity] = ...
    localLLRMetrics(sixgr.util.structGet(rx, "CodewordLLR", []), modulation);

[metrics.ShapingRateLoss, metrics.DistributionMatchingLatency_ms] = localShapingMetrics(cfg, tx, modulation);
metrics.DetectorComplexityUnits = localDetectorComplexity(rx, eqSymAligned);
[metrics.DataRECount, metrics.DMRSRECount, metrics.PTRSRECount, metrics.RSOverheadFraction] = ...
    localResourceOverheadMetrics(tx, direction);

if isfinite(metrics.SymbolErrorRate)
    robustness = max(0, 1 - metrics.SymbolErrorRate);
    if isfinite(metrics.EVM_rms)
        robustness = robustness / max(1 + metrics.EVM_rms, eps);
    end
    if localQm(modulation) < 10
        robustness = 0;
    end
    metrics.HighOrderRobustness = robustness;
end

tracking = localTrackingMetrics(sixgr.util.structGet(rx, "ChannelEstimate", []), cfg);
fields = fieldnames(tracking);
for i = 1:numel(fields)
    metrics.(fields{i}) = tracking.(fields{i});
end

constellationT = localConstellationTable(direction, modulation, ...
    sixgr.util.structGet(cfg, "channel.snr_dB", NaN), refSym, eqSymRawUse, eqSymAligned, hardSym, detectorSym);
end

function modulation = localResolveModulation(tx, cfg, direction)
modulation = "";
if direction == "UL"
    modulation = string(sixgr.util.structGet(tx, "PUSCH.Modulation", ...
        sixgr.util.structGet(cfg, "phy.pusch.modulation", "")));
else
    modulation = string(sixgr.util.structGet(tx, "PDSCH.Modulation", ...
        sixgr.util.structGet(cfg, "phy.pdsch.modulation", "")));
end
end

function x = localEnsureColumn(x)
if isempty(x)
    return;
end
if iscell(x)
    x = localUnwrapCellSignal(x);
    if isempty(x)
        return;
    end
end
x = x(:);
end

function txSym = localReferenceSymbols(tx, direction)
txSym = [];
if direction == "UL"
    txSym = sixgr.util.structGet(tx, "PUSCHSymbols", []);
else
    txSym = sixgr.util.structGet(tx, "PDSCHSymbols", sixgr.util.structGet(tx, "PDSCHAntennaSymbols", []));
end
txSym = localEnsureColumn(txSym);
end

function decSym = localDetectorSymbols(rx, direction)
if direction == "UL"
    decSym = sixgr.util.structGet(rx, "PUSCHRxSymbols", []);
else
    decSym = sixgr.util.structGet(rx, "PDSCHRxSymbols", []);
end
decSym = localEnsureColumn(decSym);
end

function papr_dB = localPAPRdB(waveform)
papr_dB = NaN;
if isempty(waveform)
    return;
end
p = abs(waveform(:)).^2;
if isempty(p) || ~any(isfinite(p))
    return;
end
papr_dB = 10 * log10(max(p) / max(mean(p, "omitnan"), eps));
end

function count = localPeakClippingEvents(waveform, cfg)
count = NaN;
if isempty(waveform)
    return;
end
cfrEnabled = logical(sixgr.util.structGet(cfg, "power_and_rf_frontend.cfr_enabled", ...
    sixgr.util.structGet(cfg, "waveform.cfr_enabled", false)));
if ~cfrEnabled
    count = 0;
    return;
end
targetPAPR = double(sixgr.util.structGet(cfg, "waveform.cfr_target_papr_db", ...
    sixgr.util.structGet(cfg, "power_and_rf_frontend.cfr_target_papr_db", 8)));
p = abs(waveform(:)).^2;
th = mean(p, "omitnan") * 10^(targetPAPR / 10);
count = sum(p > th);
end

function [meanAbs, stdAbs, imbalance, sensitivity] = localLLRMetrics(llr, modulation)
meanAbs = NaN;
stdAbs = NaN;
imbalance = NaN;
sensitivity = NaN;
llr = localEnsureColumn(llr);
if isempty(llr)
    return;
end
a = abs(double(llr));
a = a(isfinite(a));
if isempty(a)
    return;
end
meanAbs = mean(a, "omitnan");
stdAbs = std(a, "omitnan");
qm = localQm(modulation);
if ~(isscalar(qm) && isfinite(qm) && qm >= 1)
    return;
end
L = floor(numel(a) / qm) * qm;
if L < qm
    return;
end
A = reshape(a(1:L), qm, []);
perPos = mean(A, 2, "omitnan");
den = max(mean(perPos, "omitnan"), eps);
imbalance = std(perPos, "omitnan") / den;
sensitivity = (max(perPos) - min(perPos)) / den;
end

function [rateLoss, dmLatency_ms] = localShapingMetrics(cfg, tx, modulation)
rateLoss = NaN;
dmLatency_ms = NaN;
shapingEnabled = logical(sixgr.util.structGet(cfg, "phy.modulation.constellationShapingEnabled", ...
    sixgr.util.structGet(cfg, "modulation_and_mapping.probabilistic_shaping_flag", false)));
if ~shapingEnabled
    rateLoss = 0;
    dmLatency_ms = 0;
    return;
end

G = double(sixgr.util.structGet(tx, "G", NaN));
tb = double(sixgr.util.structGet(tx, "TransportBlockSize", NaN));
qm = localQm(modulation);
if isfinite(G) && isfinite(tb) && G > 0 && tb >= 0
    rateLoss = max(0, 1 - (tb / G));
else
    rateLoss = NaN;
end
if isfinite(tb) && tb >= 0
    dmLatency_ms = tb / 1e5;
end
end

function complexity = localDetectorComplexity(rx, eqSym)
complexity = NaN;
H2 = localCollapseHest(sixgr.util.structGet(rx, "ChannelEstimate", []));
if isempty(eqSym) || isempty(H2)
    return;
end
numSym = numel(eqSym);
nRx = size(H2, 1);
nTx = size(H2, 2);
complexity = double(numSym) * max(double(nRx), 1) * max(double(nTx), 1);
end

function [dataRE, dmrsRE, ptrsRE, rsFrac] = localResourceOverheadMetrics(tx, direction)
dataRE = NaN;
dmrsRE = NaN;
ptrsRE = NaN;
rsFrac = NaN;
if direction == "UL"
    dataIdx = sixgr.util.structGet(tx, "PUSCHIndices", []);
else
    dataIdx = sixgr.util.structGet(tx, "PDSCHIndices", []);
end
dmrsIdx = sixgr.util.structGet(tx, "DMRSIndices", []);
ptrsIdx = sixgr.util.structGet(tx, "PTRSIndices", []);
dataRE = double(numel(dataIdx));
dmrsRE = double(numel(dmrsIdx));
ptrsRE = double(numel(ptrsIdx));
totalRE = dataRE + dmrsRE + ptrsRE;
if totalRE > 0
    rsFrac = (dmrsRE + ptrsRE) / totalRE;
end
end

function metrics = localTrackingMetrics(Hest, cfg)
metrics = struct( ...
    "EstimatedDopplerHz", NaN, ...
    "PhaseTrackingError_deg", NaN, ...
    "QCLAccuracy", NaN, ...
    "ChannelAgingLoss_dB", NaN, ...
    "InterpolationLoss_dB", NaN, ...
    "MismatchSensitivity_dB", NaN);

H2 = localCollapseHest(Hest);
if isempty(H2)
    return;
end

gainPerSym = mean(abs(H2).^2, 1, "omitnan");
gainPerSym = gainPerSym(isfinite(gainPerSym));
if numel(gainPerSym) >= 2
    metrics.ChannelAgingLoss_dB = max(0, 10 * log10(max(gainPerSym(1), eps) / max(gainPerSym(end), eps)));
end

hSym = mean(H2, 1, "omitnan");
hSym = hSym(:);
valid = isfinite(real(hSym)) & isfinite(imag(hSym));
if nnz(valid) >= 2
    slotDur_s = localSlotDuration(cfg);
    t = linspace(0, slotDur_s, nnz(valid)).';
    phase = unwrap(angle(hSym(valid)));
    p = polyfit(t, phase, 1);
    metrics.EstimatedDopplerHz = p(1) / (2 * pi);
    phaseFit = polyval(p, t);
    resid = phase - phaseFit;
    metrics.PhaseTrackingError_deg = sqrt(mean(resid.^2, "omitnan")) * (180 / pi);
end

ref = H2(:, 1);
refNorm = norm(ref);
if refNorm > 0
    corrVals = NaN(size(H2, 2), 1);
    for idx = 1:size(H2, 2)
        v = H2(:, idx);
        denom = refNorm * norm(v);
        if denom > 0
            corrVals(idx) = abs(ref' * v) / denom;
        end
    end
    metrics.QCLAccuracy = mean(corrVals, "omitnan");
end

[K, L] = size(H2);
if K >= 4 && L >= 2
    kIdx = unique([1:6:K K]);
    lIdx = unique([1:2:L L]);
    [KK, LL] = ndgrid(1:K, 1:L);
    [Kc, Lc] = ndgrid(kIdx, lIdx);
    coarse = H2(kIdx, lIdx);
    realHat = interp2(Lc, Kc, real(coarse), LL, KK, "linear");
    imagHat = interp2(Lc, Kc, imag(coarse), LL, KK, "linear");
    Hhat = complex(realHat, imagHat);
    nmse = mean(abs(H2(:) - Hhat(:)).^2, "omitnan") / max(mean(abs(H2(:)).^2, "omitnan"), eps);
    metrics.InterpolationLoss_dB = 10 * log10(max(nmse, eps));
end

magdB = 20 * log10(max(abs(H2(:)), eps));
magdB = magdB(isfinite(magdB));
if ~isempty(magdB)
    metrics.MismatchSensitivity_dB = std(magdB, "omitnan");
end
end

function H2 = localCollapseHest(H)
H2 = [];
if isempty(H)
    return;
end
if ndims(H) >= 4
    H2 = squeeze(mean(H, [3 4], "omitnan"));
elseif ndims(H) == 3
    H2 = squeeze(mean(H, 3, "omitnan"));
else
    H2 = H;
end
if isvector(H2)
    H2 = reshape(H2, [], 1);
end
if ~ismatrix(H2)
    H2 = [];
end
end

function [refUse, eqAligned, eqRawUse] = localPrepareAlignedSymbols(refSym, eqSymRaw)
refUse = [];
eqAligned = [];
eqRawUse = [];
refSym = localEnsureColumn(refSym);
eqSymRaw = localEnsureColumn(eqSymRaw);
if isempty(refSym) || isempty(eqSymRaw)
    return;
end

L = min(numel(refSym), numel(eqSymRaw));
if L <= 0
    return;
end
refUse = refSym(1:L);
eqRawUse = eqSymRaw(1:L);

den = sum(abs(refUse).^2, "omitnan");
gain = 1;
if isfinite(den) && den > eps
    gain = sum(eqRawUse .* conj(refUse), "omitnan") / den;
end
if ~(isfinite(real(gain)) && isfinite(imag(gain)) && abs(gain) > sqrt(eps))
    gain = 1;
end
eqAligned = eqRawUse ./ gain;
end

function constellationT = localConstellationTable(direction, modulation, snr_dB, refSym, eqSymRaw, eqSymAligned, hardSym, detectorSym)
constellationT = table();
if isempty(eqSymAligned)
    return;
end
L = min(numel(eqSymAligned), 512);
if isempty(L) || L <= 0
    return;
end
eqUse = eqSymAligned(1:L);
if isempty(eqSymRaw)
    eqRawUse = complex(nan(L, 1));
else
    eqRawUse = eqSymRaw(1:min(numel(eqSymRaw), L));
    if numel(eqRawUse) < L
        eqRawUse(end+1:L,1) = complex(nan);
    end
end
if isempty(refSym)
    refUse = complex(nan(L, 1));
else
    refUse = refSym(1:min(numel(refSym), L));
    if numel(refUse) < L
        refUse(end+1:L,1) = complex(nan);
    end
end
if isempty(hardSym)
    hardUse = complex(nan(L, 1));
else
    hardUse = hardSym(1:min(numel(hardSym), L));
    if numel(hardUse) < L
        hardUse(end+1:L,1) = complex(nan);
    end
end
if isempty(detectorSym)
    detUse = complex(nan(L, 1));
else
    detUse = detectorSym(1:min(numel(detectorSym), L));
    if numel(detUse) < L
        detUse(end+1:L,1) = complex(nan);
    end
end

constellationT = table( ...
    repmat(direction, L, 1), repmat(string(modulation), L, 1), repmat(double(snr_dB), L, 1), (1:L).', ...
    real(refUse), imag(refUse), ...
    real(refUse), imag(refUse), ...
    real(eqRawUse), imag(eqRawUse), ...
    real(eqUse), imag(eqUse), ...
    real(hardUse), imag(hardUse), ...
    real(hardUse), imag(hardUse), ...
    real(detUse), imag(detUse), ...
    'VariableNames', {'Direction','Modulation','SNR_dB','SampleIndex', ...
    'ReferenceSymbolReal','ReferenceSymbolImag','TxReal','TxImag', ...
    'RawEqualizedReal','RawEqualizedImag','EqualizedReal','EqualizedImag', ...
    'HardDecisionReal','HardDecisionImag','DecisionReal','DecisionImag', ...
    'DetectorOutputReal','DetectorOutputImag'});
end

function y = localHardDecisionSymbols(sym, modulation, refSym)
y = [];
sym = localEnsureColumn(sym);
if isempty(sym)
    return;
end
alphabet = localConstellationAlphabet(modulation, refSym);
if isempty(alphabet)
    return;
end
dist = abs(sym - reshape(alphabet, 1, []));
[~, idx] = min(dist, [], 2);
y = alphabet(idx);
end

function alphabet = localConstellationAlphabet(modulation, refSym)
alphabet = [];
qm = localQm(modulation);
modToken = upper(char(string(modulation)));
switch modToken
    case 'PI/2-BPSK'
        alphabet = localUniqueComplex(refSym);
        if isempty(alphabet)
            alphabet = exp(1j * (0:3).' * (pi / 2));
        end
    case 'BPSK'
        alphabet = [-1; 1];
    case 'QPSK'
        alphabet = (1/sqrt(2)) * [1+1j; -1+1j; -1-1j; 1-1j];
    otherwise
        M = 2^qm;
        if ~(isscalar(M) && isfinite(M) && M >= 2)
            alphabet = localUniqueComplex(refSym);
            return;
        end
        try
            alphabet = qammod((0:M-1).', M, "gray", "UnitAveragePower", true);
        catch
            alphabet = localUniqueComplex(refSym);
        end
end
alphabet = localUniqueComplex(alphabet);
end

function y = localUniqueComplex(x)
y = [];
x = localEnsureColumn(x);
if isempty(x)
    return;
end
mask = isfinite(real(x)) & isfinite(imag(x));
x = x(mask);
if isempty(x)
    return;
end
key = round(real(x), 12) + 1j * round(imag(x), 12);
[~, ia] = unique(key, "stable");
y = x(sort(ia));
end

function qm = localQm(modScheme)
switch upper(char(string(modScheme)))
    case {'PI/2-BPSK','BPSK'}
        qm = 1;
    case 'QPSK'
        qm = 2;
    case '16QAM'
        qm = 4;
    case '64QAM'
        qm = 6;
    case '256QAM'
        qm = 8;
    case '1024QAM'
        qm = 10;
    case '4096QAM'
        qm = 12;
    otherwise
        qm = 2;
end
end

function slotDur_s = localSlotDuration(cfg)
slotDur_s = 1e-3;
scs_kHz = double(sixgr.util.structGet(cfg, "phy.scs", ...
    sixgr.util.structGet(cfg, "frame.scs_khz", sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 15))));
if isfinite(scs_kHz) && scs_kHz > 0
    mu = round(log2(scs_kHz / 15));
    mu = max(mu, 0);
    slotDur_s = 1e-3 / (2^mu);
end
end

function x = localUnwrapCellSignal(x)
if isempty(x)
    x = [];
    return;
end
parts = cell(numel(x), 1);
keep = false(numel(x), 1);
for i = 1:numel(x)
    xi = x{i};
    if iscell(xi)
        xi = localUnwrapCellSignal(xi);
    end
    if isnumeric(xi) || islogical(xi)
        xi = xi(:);
        if ~isempty(xi)
            parts{i} = xi;
            keep(i) = true;
        end
    end
end
if any(keep)
    x = vertcat(parts{keep});
else
    x = [];
end
end
