function [metrics, constellationT] = deriveModulationTrackingMetrics(tx, rx, cfg, direction)
%DERIVEMODULATIONTRACKINGMETRICS Measured modulation/shaping and tracking metrics.

direction = upper(string(direction));
metrics = struct( ...
    "EVM_rms", NaN, ...
    "EVMStatus", "unavailable", ...
    "EVMComputationDomain", "", ...
    "SymbolErrors", NaN, ...
    "SymbolsCompared", NaN, ...
    "SymbolErrorRate", NaN, ...
    "SymbolDecisionBitErrors", NaN, ...
    "SymbolDecisionBitsCompared", NaN, ...
    "SymbolDecisionBitErrorRate", NaN, ...
    "SymbolComparisonDomain", "", ...
    "ReferenceSymbolDomain", "", ...
    "EqualizedSymbolDomain", "", ...
    "SymbolOrdering", "", ...
    "SymbolOrderingStatus", "", ...
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
    "DataRECountPerLayer", NaN, ...
    "TotalDataRECount", NaN, ...
    "LayerDataRE", NaN, ...
    "PortIndexCellCount", NaN, ...
    "QAMSymbolCount", NaN, ...
    "RateMatchedBitCount", NaN, ...
    "DemapperLLRCount", NaN, ...
    "ModulationOrderQm", NaN, ...
    "ComputedE_TS38212", NaN, ...
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
[eqSymRaw, eqDomain, eqOrder] = localEqualizedLayerSymbols(rx);
[txSym, refDomain, refOrder] = localReferenceSymbols(tx, direction);
detectorSym = localDetectorSymbols(rx, direction);

[refSym, eqSymAligned, eqSymRawUse, orderInfo] = localPrepareMatchedLayerSymbols( ...
    txSym, eqSymRaw, refDomain, eqDomain, refOrder, eqOrder);
metrics.ReferenceSymbolDomain = refDomain;
metrics.EqualizedSymbolDomain = eqDomain;
metrics.SymbolComparisonDomain = orderInfo.ComparisonDomain;
metrics.SymbolOrdering = orderInfo.Ordering;
metrics.SymbolOrderingStatus = orderInfo.Status;
hardSym = localHardDecisionSymbols(eqSymAligned, modulation, refSym);
if isempty(refSym)
    refSym = txSym;
end

if ~isempty(eqSymAligned) && ~isempty(refSym)
    [eqNorm, refNorm, evmStatus] = localNormalizeEVMInputs(eqSymAligned, refSym);
    if ~isempty(eqNorm) && ~isempty(refNorm)
        err = eqNorm - refNorm;
        metrics.EVM_rms = sqrt(mean(abs(err).^2, "omitnan"));
        metrics.EVMStatus = evmStatus;
        if isfinite(metrics.EVM_rms) && metrics.EVM_rms > 1
            metrics.EVMStatus = "warning_gt_100pct_check_timing_or_channel_estimate";
        end
        metrics.EVMComputationDomain = "post_equalized_and_reference_unit_power_constellation";
    else
        metrics.EVMStatus = evmStatus;
    end
end

if ~isempty(refSym) && ~isempty(hardSym)
    if numel(refSym) ~= numel(hardSym)
        error("sixgr:link:SymbolDomainMismatch", ...
            "Hard-decision symbol count %d does not match reference symbol count %d.", ...
            numel(hardSym), numel(refSym));
    end
    L = numel(refSym);
    symErr = sum(abs(refSym - hardSym) > 1e-8);
    metrics.SymbolErrors = double(symErr);
    metrics.SymbolsCompared = double(L);
    metrics.SymbolErrorRate = double(symErr) / max(double(L), 1);
    [bitErr, bitsCompared] = localSymbolDecisionBitErrors(refSym, hardSym, modulation);
    metrics.SymbolDecisionBitErrors = double(bitErr);
    metrics.SymbolDecisionBitsCompared = double(bitsCompared);
    if bitsCompared > 0
        metrics.SymbolDecisionBitErrorRate = double(bitErr) / double(bitsCompared);
    end
    resid = eqSymAligned - hardSym;
    metrics.ResidualInterferencePower_dB = 10 * log10(max(mean(abs(resid).^2, "omitnan"), eps));
end

wf = sixgr.util.structGet(tx, "Waveform", []);
if ~isempty(wf)
    metrics.PAPR_dB = localPAPRdB(wf);
    metrics.PeakClippingEvents = localPeakClippingEvents(wf, cfg);
end

llrForMetrics = sixgr.util.structGet(rx, "RecLLR", []);
if isempty(llrForMetrics)
    llrForMetrics = sixgr.util.structGet(rx, "RateRecoveredLLR", []);
end
if isempty(llrForMetrics)
    llrForMetrics = sixgr.util.structGet(rx, "CodewordLLR", []);
end
[metrics.LLRMeanAbs, metrics.LLRStdAbs, metrics.LLRImbalance, metrics.ModulationMappingSensitivity] = ...
    localLLRMetrics(llrForMetrics, modulation);

[metrics.ShapingRateLoss, metrics.DistributionMatchingLatency_ms] = localShapingMetrics(cfg, tx, modulation);
metrics.DetectorComplexityUnits = localDetectorComplexity(rx, eqSymAligned);
metrics.ModulationOrderQm = localQm(modulation);
[metrics.DataRECount, metrics.DMRSRECount, metrics.PTRSRECount, metrics.RSOverheadFraction, ...
    metrics.DataRECountPerLayer, metrics.TotalDataRECount, metrics.ComputedE_TS38212] = ...
    localResourceOverheadMetrics(tx, direction, metrics.ModulationOrderQm);
[metrics.LayerDataRE, metrics.PortIndexCellCount, metrics.QAMSymbolCount, ...
    metrics.RateMatchedBitCount, metrics.DemapperLLRCount] = localDomainCountMetrics(tx, rx);

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
    sixgr.util.structGet(cfg, "channel.snr_dB", NaN), tx, refSym, eqSymRawUse, eqSymAligned, hardSym, detectorSym, orderInfo);
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

function [eqNorm, refNorm, status] = localNormalizeEVMInputs(eqSym, refSym)
eqNorm = [];
refNorm = [];
status = "unavailable";
eqSym = eqSym(:);
refSym = refSym(:);
valid = isfinite(real(eqSym)) & isfinite(imag(eqSym)) & ...
    isfinite(real(refSym)) & isfinite(imag(refSym));
eqSym = eqSym(valid);
refSym = refSym(valid);
if isempty(eqSym) || isempty(refSym)
    status = "unavailable_no_finite_symbol_pairs";
    return;
end
eqPower = mean(abs(eqSym).^2, "omitnan");
refPower = mean(abs(refSym).^2, "omitnan");
if ~(isfinite(eqPower) && eqPower > eps && isfinite(refPower) && refPower > eps)
    status = "unavailable_invalid_symbol_power";
    return;
end
eqNorm = eqSym ./ sqrt(eqPower);
refNorm = refSym ./ sqrt(refPower);
status = "OK";
end

function [txSym, domain, order] = localReferenceSymbols(tx, direction)
txSym = [];
domain = "layer";
order = struct();
if direction == "UL"
    [txSym, fieldName] = localFirstPresent(tx, ["PUSCHLayerSymbolsForEvidence", ...
        "PUSCHLayerSymbols", "PUSCHSymbolsForEvidence", "PUSCHSymbols"]);
else
    [txSym, fieldName] = localFirstPresent(tx, ["PDSCHLayerSymbolsForEvidence", ...
        "PDSCHLayerSymbols", "PDSCHSymbolsForEvidence", "PDSCHSymbols"]);
end
if contains(lower(string(fieldName)), "port") || contains(lower(string(fieldName)), "antenna")
    domain = "port";
else
    domain = string(sixgr.util.structGet(tx, "LayerSymbolDomain", "layer"));
end
order = sixgr.util.structGet(tx, "LayerSymbolOrder", struct());
txSym = localEnsureSymbolMatrix(txSym);
end

function [eqSym, domain, order] = localEqualizedLayerSymbols(rx)
[eqSym, fieldName] = localFirstPresent(rx, ["LayerEqualizedSymbolsForEvidence", ...
    "LayerEqualizedSymbols", "EqualizedSymbolsForEvidence", "EqualizedSymbols"]);
domain = string(sixgr.util.structGet(rx, "EqualizedSymbolDomain", "layer"));
if contains(lower(string(fieldName)), "port") || contains(lower(string(fieldName)), "antenna")
    domain = "port";
end
order = sixgr.util.structGet(rx, "LayerSymbolOrder", struct());
eqSym = localEnsureSymbolMatrix(eqSym);
end

function [value, fieldName] = localFirstPresent(s, names)
value = [];
fieldName = "";
for i = 1:numel(names)
    raw = sixgr.util.structGet(s, char(names(i)), []);
    if ~isempty(raw)
        value = raw;
        fieldName = names(i);
        return;
    end
end
end

function x = localEnsureSymbolMatrix(x)
if isempty(x)
    return;
end
if iscell(x)
    x = localUnwrapCellSignal(x);
end
if isempty(x)
    return;
end
if isvector(x)
    x = x(:);
end
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
x = localWaveformPortMatrix(waveform);
p = abs(x).^2;
if isempty(p) || ~any(isfinite(p(:)))
    return;
end
portMean = mean(p, 1, "omitnan");
portPeak = max(p, [], 1, "omitnan");
valid = isfinite(portMean) & portMean > 0 & isfinite(portPeak);
if ~any(valid)
    return;
end
portPAPR_dB = 10 * log10(portPeak(valid) ./ max(portMean(valid), eps));
papr_dB = max(portPAPR_dB, [], "omitnan");
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
x = localWaveformPortMatrix(waveform);
p = abs(x).^2;
portMean = mean(p, 1, "omitnan");
th = portMean .* 10^(targetPAPR / 10);
count = sum(p > th, "all");
end

function x = localWaveformPortMatrix(waveform)
x = waveform;
if isempty(x)
    return;
end
if isvector(x)
    x = x(:);
    return;
end
sz = size(x);
x = reshape(x, sz(1), []);
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

function [dataRE, dmrsRE, ptrsRE, rsFrac, dataREPerLayer, totalDataRE, computedE] = localResourceOverheadMetrics(tx, direction, qm)
dataRE = NaN;
dmrsRE = NaN;
ptrsRE = NaN;
rsFrac = NaN;
dataREPerLayer = NaN;
totalDataRE = NaN;
computedE = NaN;
acct = sixgr.util.structGet(tx, "ResourceAccounting", struct());
if isstruct(acct) && ~isempty(fieldnames(acct))
    dataRE = double(sixgr.util.structGet(acct, "LayerDataRE", NaN));
    dataREPerLayer = dataRE;
    totalDataRE = double(sixgr.util.structGet(acct, "ModulationSymbolCount", NaN));
    dmrsRE = double(sixgr.util.structGet(acct, "DMRSRE", NaN));
    ptrsRE = double(sixgr.util.structGet(acct, "PTRSRE", NaN));
    computedE = double(sixgr.util.structGet(acct, "CodedBitCountG", NaN));
    totalRE = totalDataRE + dmrsRE + ptrsRE;
    if totalRE > 0
        rsFrac = (dmrsRE + ptrsRE) / totalRE;
    end
    return;
end
if direction == "UL"
    dataIdx = sixgr.util.structGet(tx, "PUSCHIndices", []);
    numLayers = double(sixgr.util.structGet(tx, "PUSCH.NumLayers", NaN));
else
    dataIdx = sixgr.util.structGet(tx, "PDSCHIndices", []);
    numLayers = double(sixgr.util.structGet(tx, "PDSCH.NumLayers", NaN));
end
dmrsIdx = sixgr.util.structGet(tx, "DMRSIndices", []);
ptrsIdx = sixgr.util.structGet(tx, "PTRSIndices", []);
if ~(isscalar(numLayers) && isfinite(numLayers) && numLayers >= 1)
    numLayers = 1;
end
numLayers = max(1, round(numLayers));
totalDataRE = double(numel(dataIdx));
dataREPerLayer = totalDataRE / double(numLayers);
dataRE = dataREPerLayer;
dmrsRE = double(numel(dmrsIdx));
ptrsRE = double(numel(ptrsIdx));
totalRE = totalDataRE + dmrsRE + ptrsRE;
if totalRE > 0
    rsFrac = (dmrsRE + ptrsRE) / totalRE;
end
if isscalar(qm) && isfinite(qm) && qm > 0 && isfinite(dataREPerLayer)
    computedE = dataREPerLayer * double(qm) * double(numLayers);
end
end

function [layerDataRE, portIndexCellCount, qamSymbolCount, rateMatchedBitCount, demapperLLRCount] = localDomainCountMetrics(tx, rx)
acct = sixgr.util.structGet(tx, "ResourceAccounting", struct());
layerDataRE = double(sixgr.util.structGet(tx, "LayerDataRE", NaN));
portIndexCellCount = double(sixgr.util.structGet(tx, "PortIndexCellCount", NaN));
qamSymbolCount = double(sixgr.util.structGet(tx, "QAMSymbolCount", NaN));
rateMatchedBitCount = double(sixgr.util.structGet(tx, "RateMatchedBitCount", NaN));
if isstruct(acct) && ~isempty(fieldnames(acct))
    if ~isfinite(layerDataRE)
        layerDataRE = double(sixgr.util.structGet(acct, "LayerDataRE", NaN));
    end
    if ~isfinite(portIndexCellCount)
        portIndexCellCount = double(sixgr.util.structGet(acct, "PortMappedRE", NaN));
    end
    if ~isfinite(qamSymbolCount)
        qamSymbolCount = double(sixgr.util.structGet(acct, "ModulationSymbolCount", NaN));
    end
    if ~isfinite(rateMatchedBitCount)
        rateMatchedBitCount = double(sixgr.util.structGet(acct, "CodedBitCountG", NaN));
    end
end
if ~isfinite(qamSymbolCount)
    layerSym = sixgr.util.structGet(tx, "PUSCHLayerSymbolsForEvidence", ...
        sixgr.util.structGet(tx, "PDSCHLayerSymbolsForEvidence", []));
    qamSymbolCount = double(numel(layerSym));
end
if ~isfinite(portIndexCellCount)
    portInd = sixgr.util.structGet(tx, "PUSCHPortIndices", ...
        sixgr.util.structGet(tx, "PDSCHPortIndices", []));
    portIndexCellCount = double(numel(portInd));
end
if ~isfinite(rateMatchedBitCount)
    rateMatchedBitCount = double(sixgr.util.structGet(tx, "G", NaN));
end
demapperLLRCount = double(sixgr.util.structGet(rx, "DemapperLLRCount", NaN));
if ~isfinite(demapperLLRCount)
    llr = sixgr.util.structGet(rx, "CodewordLLR", []);
    if isempty(llr)
        llr = sixgr.util.structGet(rx, "ULSCHCodewordLLR", ...
            sixgr.util.structGet(rx, "DLSCHCodewordLLR", []));
    end
    demapperLLRCount = double(numel(llr));
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

if size(H2, 2) >= 2
    symCorr = sum(conj(H2(:, 1:end-1)) .* H2(:, 2:end), 1, "omitnan");
    valid = isfinite(real(symCorr)) & isfinite(imag(symCorr)) & (abs(symCorr) > 0);
    if nnz(valid) >= 1
        slotDur_s = localSlotDuration(cfg);
        symDur_s = slotDur_s / max(size(H2, 2) - 1, 1);
        phaseStep = angle(symCorr(valid));
        meanStep = mean(phaseStep, "omitnan");
        metrics.EstimatedDopplerHz = meanStep / (2 * pi * max(symDur_s, eps));
        resid = phaseStep - meanStep;
        metrics.PhaseTrackingError_deg = sqrt(mean(resid.^2, "omitnan")) * (180 / pi);
    end
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

function [refUse, eqAligned, eqRawUse, info] = localPrepareMatchedLayerSymbols(refSym, eqSymRaw, refDomain, eqDomain, refOrder, eqOrder)
refUse = [];
eqAligned = [];
eqRawUse = [];
info = struct( ...
    "ComparisonDomain", "layer", ...
    "Ordering", "matrix_column_major_matches_nr_resource_indices", ...
    "Status", "unavailable");
refDomain = lower(strtrim(string(refDomain)));
eqDomain = lower(strtrim(string(eqDomain)));
refSym = localEnsureSymbolMatrix(refSym);
eqSymRaw = localEnsureSymbolMatrix(eqSymRaw);
if isempty(refSym) || isempty(eqSymRaw)
    return;
end
if refDomain ~= "layer" || eqDomain ~= "layer"
    error("sixgr:link:SymbolDomainMismatch", ...
        "Layer-domain SER/EVM requires layer reference and layer estimate, got reference=%s estimate=%s.", ...
        char(refDomain), char(eqDomain));
end
if ~isequal(size(refSym), size(eqSymRaw))
    if isvector(refSym) && isvector(eqSymRaw) && numel(refSym) == numel(eqSymRaw)
        refSym = refSym(:);
        eqSymRaw = eqSymRaw(:);
    else
        error("sixgr:link:SymbolDomainMismatch", ...
            "Layer-domain symbol comparison requires identical shapes; reference=%s estimate=%s.", ...
            mat2str(size(refSym)), mat2str(size(eqSymRaw)));
    end
end
localAssertCompatibleOrdering(refOrder, eqOrder);
refUse = refSym(:);
eqRawUse = eqSymRaw(:);
info.Status = "matched_layer_domain_same_shape";

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

function localAssertCompatibleOrdering(refOrder, eqOrder)
refIdx = localOrderLinearIndex(refOrder);
eqIdx = localOrderLinearIndex(eqOrder);
if isempty(refIdx) || isempty(eqIdx)
    return;
end
if ~isequal(size(refIdx), size(eqIdx))
    error("sixgr:link:SymbolOrderingMismatch", ...
        "Layer-domain ordering map shapes differ: reference=%s estimate=%s.", ...
        mat2str(size(refIdx)), mat2str(size(eqIdx)));
end
finite = isfinite(refIdx) & isfinite(eqIdx);
if any(finite(:)) && any(refIdx(finite) ~= eqIdx(finite))
    error("sixgr:link:SymbolOrderingMismatch", ...
        "Layer-domain symbol ordering maps refer to different resource indices.");
end
end

function idx = localOrderLinearIndex(order)
idx = [];
if ~isstruct(order) || isempty(fieldnames(order))
    return;
end
try
    idx = double(order.LinearIndex);
catch
    idx = [];
end
end

function constellationT = localConstellationTable(direction, modulation, snr_dB, tx, refSym, eqSymRaw, eqSymAligned, hardSym, detectorSym, orderInfo)
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
[subcarrierIdx, ofdmSymbolIdx, layerIdx, codewordIdx] = localConstellationRECoordinates(tx, direction, L);
errorMag = abs(eqUse - refUse);
refPower = max(abs(refUse).^2, eps);
evmRms = abs(eqUse - refUse) ./ sqrt(refPower);

constellationT = table( ...
    repmat(direction, L, 1), repmat(string(modulation), L, 1), repmat(double(snr_dB), L, 1), (1:L).', ...
    repmat(string(orderInfo.ComparisonDomain), L, 1), repmat(string(orderInfo.Ordering), L, 1), ...
    repmat(string(orderInfo.Status), L, 1), ...
    subcarrierIdx, ofdmSymbolIdx, layerIdx, codewordIdx, ...
    real(refUse), imag(refUse), ...
    real(refUse), imag(refUse), ...
    real(eqRawUse), imag(eqRawUse), ...
    real(eqUse), imag(eqUse), ...
    real(hardUse), imag(hardUse), ...
    real(hardUse), imag(hardUse), ...
    real(detUse), imag(detUse), ...
    errorMag, evmRms, ...
    'VariableNames', {'Direction','Modulation','SNR_dB','SampleIndex', ...
    'SymbolComparisonDomain','SymbolOrdering','SymbolOrderingStatus', ...
    'SubcarrierIndex','OFDMSymbolIndex','LayerIndex','CodewordIndex', ...
    'ReferenceSymbolReal','ReferenceSymbolImag','TxReal','TxImag', ...
    'RawEqualizedReal','RawEqualizedImag','EqualizedReal','EqualizedImag', ...
    'HardDecisionReal','HardDecisionImag','DecisionReal','DecisionImag', ...
    'DetectorOutputReal','DetectorOutputImag','SymbolErrorMagnitude','SymbolEVM_rms'});
end

function [subcarrierIdx, ofdmSymbolIdx, layerIdx, codewordIdx] = localConstellationRECoordinates(tx, direction, L)
subcarrierIdx = nan(L, 1);
ofdmSymbolIdx = nan(L, 1);
layerIdx = nan(L, 1);
codewordIdx = zeros(L, 1);
if nargin < 3 || L <= 0
    return;
end
order = sixgr.util.structGet(tx, "LayerSymbolOrder", struct());
if isstruct(order) && ~isempty(fieldnames(order))
    sc = sixgr.util.structGet(order, "SubcarrierIndex", []);
    sym = sixgr.util.structGet(order, "OFDMSymbolIndex", []);
    lyr = sixgr.util.structGet(order, "LayerIndex", []);
    if ~isempty(sc) && ~isempty(sym)
        take = min([numel(sc), numel(sym), L]);
        subcarrierIdx(1:take) = double(sc(1:take));
        ofdmSymbolIdx(1:take) = double(sym(1:take));
        if ~isempty(lyr)
            layerIdx(1:min(numel(lyr), L)) = double(lyr(1:min(numel(lyr), L)));
        end
        return;
    end
end
if direction == "UL"
    ind = sixgr.util.structGet(tx, "PUSCHIndices", []);
else
    ind = sixgr.util.structGet(tx, "PDSCHIndices", []);
end
if isempty(ind)
    return;
end
ind = double(ind);
ind = ind(:);
take = min(numel(ind), L);
if take <= 0
    return;
end
grid = sixgr.util.structGet(tx, "Grid", []);
if ~isempty(grid)
    K = size(grid, 1);
    Nsym = size(grid, 2);
    Nlayer = max(size(grid, 3), 1);
else
    K = NaN;
    Nsym = NaN;
    Nlayer = NaN;
end
if ~(isfinite(K) && K > 0 && isfinite(Nsym) && Nsym > 0)
    return;
end
maxLinear = max(ind(1:take), [], "omitnan");
if ~(isfinite(maxLinear) && maxLinear <= K * Nsym * max(Nlayer, 1))
    return;
end
[sc, sym, lyr] = ind2sub([K, Nsym, max(Nlayer, 1)], ind(1:take));
subcarrierIdx(1:take) = double(sc(:));
ofdmSymbolIdx(1:take) = double(sym(:));
layerIdx(1:take) = double(lyr(:));
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

function [bitErr, bitsCompared] = localSymbolDecisionBitErrors(refSym, hardSym, modulation)
bitErr = NaN;
bitsCompared = NaN;
refSym = localEnsureColumn(refSym);
hardSym = localEnsureColumn(hardSym);
if isempty(refSym) || isempty(hardSym) || numel(refSym) ~= numel(hardSym)
    return;
end
alphabet = localConstellationAlphabet(modulation, refSym);
labels = localConstellationBitLabels(modulation, numel(alphabet));
if isempty(alphabet) || isempty(labels)
    return;
end
refIdx = localNearestAlphabetIndex(refSym, alphabet);
hardIdx = localNearestAlphabetIndex(hardSym, alphabet);
valid = refIdx >= 1 & hardIdx >= 1 & refIdx <= size(labels, 1) & hardIdx <= size(labels, 1);
if ~any(valid)
    return;
end
refBits = labels(refIdx(valid), :);
hardBits = labels(hardIdx(valid), :);
bitErr = sum(refBits ~= hardBits, "all");
bitsCompared = numel(refBits);
end

function idx = localNearestAlphabetIndex(sym, alphabet)
sym = localEnsureColumn(sym);
alphabet = localEnsureColumn(alphabet);
if isempty(sym) || isempty(alphabet)
    idx = zeros(numel(sym), 1);
    return;
end
dist = abs(sym - reshape(alphabet, 1, []));
[~, idx] = min(dist, [], 2);
end

function labels = localConstellationBitLabels(modulation, M)
labels = [];
qm = localQm(modulation);
if ~(isfinite(qm) && qm >= 1 && M >= 2)
    return;
end
if strcmp(upper(char(string(modulation))), 'QPSK') && M == 4
    labels = logical([0 0; 0 1; 1 1; 1 0]);
    return;
end
if M ~= 2^qm
    return;
end
labels = false(M, qm);
for k = 0:(M - 1)
    gray = bitxor(uint32(k), bitshift(uint32(k), -1));
    for b = 1:qm
        labels(k + 1, b) = bitget(gray, qm - b + 1) ~= 0;
    end
end
end

function alphabet = localConstellationAlphabet(modulation, refSym)
alphabet = [];
qm = localQm(modulation);
Mref = 2^qm;
refAlphabet = localUniqueComplex(refSym);
if numel(refAlphabet) >= 2 && numel(refAlphabet) <= Mref
    alphabet = refAlphabet;
    return;
end
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
