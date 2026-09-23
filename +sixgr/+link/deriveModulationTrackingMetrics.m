function [metrics, constellationT] = deriveModulationTrackingMetrics(tx, rx, cfg, direction)
%DERIVEMODULATIONTRACKINGMETRICS Measured modulation/shaping and tracking metrics.

direction = upper(string(direction));
metrics = struct( ...
    "EVM_rms", NaN, ...
    "EVMPerLayer_rms", zeros(1,0), ...
    "EVMPerLayerSource", "", ...
    "EVMStatus", "unavailable", ...
    "EVMComputationDomain", "", ...
    "SymbolErrors", NaN, ...
    "SymbolsCompared", NaN, ...
    "SymbolErrorRate", NaN, ...
    "SymbolDecisionBitErrors", NaN, ...
    "SymbolDecisionBitsCompared", NaN, ...
    "SymbolDecisionBitErrorRate", NaN, ...
    "SymbolDecisionStatus", "unavailable", ...
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
[eqSymRaw, eqDomain, eqOrder] = localEqualizedLayerSymbols(rx, direction);
[txSym, refDomain, refOrder] = localReferenceSymbols(tx, direction);
detectorSym = localDetectorSymbols(rx, direction);

[refSym, eqSymAligned, eqSymRawUse, orderInfo] = localPrepareMatchedLayerSymbols( ...
    txSym, eqSymRaw, refDomain, eqDomain, refOrder, eqOrder);
metrics.ReferenceSymbolDomain = refDomain;
metrics.EqualizedSymbolDomain = eqDomain;
metrics.SymbolComparisonDomain = orderInfo.ComparisonDomain;
metrics.SymbolOrdering = orderInfo.Ordering;
metrics.SymbolOrderingStatus = orderInfo.Status;
symbolModulation = localSymbolModulations(modulation, tx, refOrder, numel(refSym));
hardSym = complex(nan(size(eqSymAligned)));
symbolErrors = 0;
bitErrors = 0;
decisionBits = 0;
decisionStatuses = strings(0, 1);
for token = unique(symbolModulation).'
    mask = symbolModulation == token;
    [decisions, groupSymbols, groupErrors, groupBits, groupStatus] = ...
        localNRDecisionEvidence(eqSymAligned(mask), refSym(mask), token);
    hardSym(mask) = decisions;
    symbolErrors = symbolErrors + groupSymbols;
    bitErrors = bitErrors + groupErrors;
    decisionBits = decisionBits + groupBits;
    decisionStatuses(end+1, 1) = groupStatus; %#ok<AGROW>
end
if ~isempty(decisionStatuses)
    metrics.SymbolDecisionStatus = strjoin(unique(decisionStatuses, "stable"), ";");
end
% A mixed-codeword allocation has no single modulation order. Preserve the
% per-sample labels and leave scalar modulation-specific diagnostics N/A.
summaryModulation = strjoin(unique(modulation(:), "stable"), "/");
if isempty(refSym)
    refSym = txSym;
end

if ~isempty(eqSymAligned) && ~isempty(refSym)
    [eqNorm, refNorm, evmStatus] = localNormalizeEVMInputs(eqSymAligned, refSym);
    if ~isempty(eqNorm) && ~isempty(refNorm)
        err = eqNorm - refNorm;
        metrics.EVM_rms = sqrt(mean(abs(err).^2));
        metrics.EVMStatus = evmStatus;
        if isfinite(metrics.EVM_rms) && metrics.EVM_rms > 1
            metrics.EVMStatus = "warning_gt_100pct_check_timing_or_channel_estimate";
        end
        metrics.EVMComputationDomain = "receiver_equalized_symbols_average_reference_power_no_payload_fit";
        % The validated input matrices retain layer identity before the
        % aggregate comparison is flattened. Normalize each layer by its
        % own reference power; never copy the wideband RMS or fit RX gain.
        refLayers=reshape(refSym,size(txSym));
        eqLayers=reshape(eqSymAligned,size(txSym));
        referencePower=mean(abs(refLayers).^2,1);
        layerEVM=nan(1,size(refLayers,2));
        validPower=isfinite(referencePower) & referencePower>0;
        errorPower=mean(abs(eqLayers-refLayers).^2,1);
        layerEVM(validPower)=sqrt(errorPower(validPower)./referencePower(validPower));
        metrics.EVMPerLayer_rms=layerEVM;
        metrics.EVMPerLayerSource="paired_layer_symbols_average_reference_power_no_payload_fit";
    else
        metrics.EVMStatus = evmStatus;
    end
end

if ~isempty(refSym) && ~isempty(hardSym) && all(decisionStatuses == "measured_nr_hard_decision")
    if numel(refSym) ~= numel(hardSym)
        error("sixgr:link:SymbolDomainMismatch", ...
            "Hard-decision symbol count %d does not match reference symbol count %d.", ...
            numel(hardSym), numel(refSym));
    end
    L = numel(refSym);
    symErr = symbolErrors;
    metrics.SymbolErrors = double(symErr);
    metrics.SymbolsCompared = double(L);
    metrics.SymbolErrorRate = double(symErr) / max(double(L), 1);
    bitErr = bitErrors;
    bitsCompared = decisionBits;
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
    ofdmInfo = sixgr.util.structGet(tx, "OFDMInfo", ...
        sixgr.util.structGet(tx, "OFDM", struct()));
    metrics.PAPR_dB = localPAPRdB(wf, ofdmInfo);
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
    localLLRMetrics(llrForMetrics, summaryModulation);

[metrics.ShapingRateLoss, metrics.DistributionMatchingLatency_ms] = localShapingMetrics(cfg, tx, summaryModulation);
metrics.DetectorComplexityUnits = localDetectorComplexity(rx, eqSymAligned);
metrics.ModulationOrderQm = localQm(summaryModulation);
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
    if ~isfinite(metrics.ModulationOrderQm)
        robustness = NaN;
    elseif metrics.ModulationOrderQm < 10
        robustness = 0;
    end
    metrics.HighOrderRobustness = robustness;
end

tracking = localTrackingMetrics(sixgr.util.structGet(rx, "ChannelEstimate", []), cfg);
fields = fieldnames(tracking);
for i = 1:numel(fields)
    metrics.(fields{i}) = tracking.(fields{i});
end

captureScope = string(sixgr.util.structGet(cfg, "outputs.constellationCaptureScope", "preview"));
if ~isscalar(captureScope) || ~any(captureScope == ["preview", "full_allocation"])
    error("sixgr:link:InvalidConstellationCaptureScope", ...
        "outputs.constellationCaptureScope must be preview or full_allocation.");
end
constellationT = localConstellationTable(direction, symbolModulation, ...
    sixgr.util.structGet(cfg, "channel.snr_dB", NaN), tx, refSym, eqSymRawUse, eqSymAligned, hardSym, detectorSym, orderInfo, refOrder, captureScope);
if ~isempty(constellationT)
    constellationT.SymbolDecisionStatus = repmat(metrics.SymbolDecisionStatus, height(constellationT), 1);
end
end

function tokens = localSymbolModulations(modulation, tx, order, count)
tokens = strings(count, 1);
if count == 0
    return;
end
modulation = string(modulation(:));
qmTokens = arrayfun(@localQm, modulation);
if any(~isfinite(qmTokens))
    error("sixgr:link:UnknownSymbolModulation", ...
        "Paired symbol evidence requires an explicit supported modulation per codeword.");
end
if numel(modulation) == 1 || numel(unique(modulation)) == 1
    tokens(:) = modulation(1);
    return;
end
layers = double(sixgr.util.structGet(order, "LayerIndex", []));
cw = double(sixgr.util.structGet(tx, "CodewordLayerMapping.CodewordIndexByLayer", []));
if numel(layers) ~= count || isempty(cw) || ...
        any(~isfinite(layers(:)) | layers(:) < 1 | layers(:) ~= round(layers(:)) | layers(:) > numel(cw)) || ...
        any(~isfinite(cw(:)) | cw(:) < 0 | cw(:) ~= round(cw(:)) | cw(:) >= numel(modulation))
    error("sixgr:link:InvalidConstellationCodewordMapping", ...
        "Mixed-modulation evidence requires an exact codeword-to-layer symbol map.");
end
tokens = reshape(modulation(cw(layers(:))+1), [], 1);
end

function modulation = localResolveModulation(tx, cfg, direction)
modulation = "";
if direction == "UL"
    modulation = sixgr.link.resolvePUSCHTransportModulation(tx);
    if strlength(modulation)==0
        modulation=string(sixgr.util.structGet(cfg,"phy.pusch.modulation",""));
    end
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
if isempty(eqSym) || isempty(refSym)
    status = "unavailable_no_symbol_pairs";
    return;
end
refPower = mean(abs(refSym).^2);
if ~(isfinite(refPower) && refPower > 0)
    status = "unavailable_invalid_symbol_power";
    return;
end
% Both vectors use the SAME reference-power scale. Normalizing the received
% vector independently would erase amplitude errors, including attenuation
% caused by an incorrect equalizer. A zero receiver vector has 100% EVM.
eqNorm = eqSym ./ sqrt(refPower);
refNorm = refSym ./ sqrt(refPower);
status = "OK";
end

function [txSym, domain, order] = localReferenceSymbols(tx, direction)
txSym = [];
domain = "layer";
order = struct();
if direction == "UL"
    [txSym, fieldName] = localFirstPresent(tx, ["PUSCHDFTInputSymbolsForEvidence", ...
        "PUSCHDFTInputSymbols", "DFTInputSymbols", "PUSCHQAMSymbolsForEvidence", ...
        "PUSCHLayerSymbolsForEvidence", ...
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
if direction == "UL" && (contains(lower(string(fieldName)), "dftinput") || contains(lower(string(fieldName)), "qam"))
    order = sixgr.util.structGet(tx, "QAMSymbolOrder", ...
        sixgr.util.structGet(tx, "LayerSymbolOrder", struct()));
else
    order = sixgr.util.structGet(tx, "LayerSymbolOrder", struct());
end
txSym = localEnsureSymbolMatrix(txSym);
end

function [eqSym, domain, order] = localEqualizedLayerSymbols(rx, direction)
if direction == "UL"
    [eqSym, fieldName] = localFirstPresent(rx, ["PUSCHQAMSymbolsForEvidence", ...
        "PUSCHDFTInputSymbolsForEvidence", "QAMEqualizedSymbolsForEvidence", ...
        "PUSCHQAMSymbols", "QAMEqualizedSymbols", ...
        "LayerEqualizedSymbolsForEvidence", "LayerEqualizedSymbols", ...
        "EqualizedSymbolsForEvidence", "EqualizedSymbols"]);
else
    [eqSym, fieldName] = localFirstPresent(rx, ["LayerEqualizedSymbolsForEvidence", ...
        "LayerEqualizedSymbols", "EqualizedSymbolsForEvidence", "EqualizedSymbols"]);
end
if direction == "UL" && (contains(lower(string(fieldName)), "qam") || contains(lower(string(fieldName)), "dftinput"))
    domain = string(sixgr.util.structGet(rx, "QAMEqualizedSymbolDomain", "layer"));
    order = sixgr.util.structGet(rx, "QAMSymbolOrder", ...
        sixgr.util.structGet(rx, "LayerSymbolOrder", struct()));
else
    domain = string(sixgr.util.structGet(rx, "EqualizedSymbolDomain", "layer"));
    order = sixgr.util.structGet(rx, "LayerSymbolOrder", struct());
end
if contains(lower(string(fieldName)), "port") || contains(lower(string(fieldName)), "antenna")
    domain = "port";
end
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

function papr_dB = localPAPRdB(waveform, ofdmInfo)
papr_dB = NaN;
if isempty(waveform)
    return;
end
x = localWaveformPortMatrix(waveform);
if nargin >= 2
    usefulIdx = localUsefulSampleIndices(size(x, 1), ofdmInfo);
    if ~isempty(usefulIdx)
        x = x(usefulIdx, :);
    end
end
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

function idx = localUsefulSampleIndices(nSamples, ofdmInfo)
idx = [];
if nargin < 2 || ~isstruct(ofdmInfo)
    return;
end
nfft = round(double(sixgr.util.structGet(ofdmInfo, "Nfft", NaN)));
cpLens = round(double(sixgr.util.structGet(ofdmInfo, "CyclicPrefixLengths", [])));
if ~(isfinite(nfft) && nfft > 0 && ~isempty(cpLens))
    return;
end
offset = 0;
while offset < nSamples
    for s = 1:numel(cpLens)
        cp = max(0, cpLens(s));
        useful = offset + cp + (1:nfft);
        useful = useful(useful <= nSamples);
        idx = [idx, useful]; %#ok<AGROW>
        offset = offset + cp + nfft;
        if offset >= nSamples
            break;
        end
    end
end
idx = idx(:);
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
    % RS overhead is a physical time-frequency occupancy ratio.  The
    % ResourceAccounting.ModulationSymbolCount value is layer-domain
    % (LayerDataRE * NumLayers), whereas DMRSRE and PTRSRE are unique base
    % grid RE counts.  Mixing those domains understates overhead whenever
    % rank > 1.  LayerDataRE is the unique scheduled data-RE count for one
    % physical resource grid and is therefore the compatible denominator.
    totalRE = dataRE + dmrsRE + ptrsRE;
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
    % dataREPerLayer and the unique reference-signal indices share the
    % physical base-grid domain; totalDataRE is layer-domain and must not be
    % used in this ratio.
    totalRE = dataREPerLayer + dmrsRE + ptrsRE;
if totalRE > 0
    rsFrac = (dmrsRE + ptrsRE) / totalRE;
end
if isscalar(qm) && isfinite(qm) && qm > 0 && isfinite(dataREPerLayer)
    computedE = dataREPerLayer * double(qm) * double(numLayers);
end
end

function [layerDataRE, portIndexCellCount, qamSymbolCount, rateMatchedBitCount, demapperLLRCount] = localDomainCountMetrics(tx, rx)
acct = sixgr.util.structGet(tx, "ResourceAccounting", struct());
uciOnPUSCHApplied = logical(sixgr.util.structGet(tx, "UCIOnPUSCHApplied", false));
layerDataRE = double(sixgr.util.structGet(tx, "LayerDataRE", NaN));
portIndexCellCount = double(sixgr.util.structGet(tx, "PortIndexCellCount", NaN));
qamSymbolCount = double(sixgr.util.structGet(tx, "QAMSymbolCount", NaN));
rateMatchedBitCount = double(sixgr.util.structGet(tx, "RateMatchedBitCount", NaN));
dataRateMatchedBitCount = double(sixgr.util.structGet(tx, "DataRateMatchedBitCount", NaN));
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
if logical(uciOnPUSCHApplied) && isfinite(dataRateMatchedBitCount) && dataRateMatchedBitCount > 0
    rateMatchedBitCount = double(dataRateMatchedBitCount);
end
if logical(uciOnPUSCHApplied)
    demapperLLRCount = double(sixgr.util.structGet(rx, "ULSCHDemapperLLRCount", NaN));
else
    demapperLLRCount = double(sixgr.util.structGet(rx, "DemapperLLRCount", NaN));
end
if ~isfinite(demapperLLRCount)
    if logical(uciOnPUSCHApplied)
        llr = sixgr.util.structGet(rx, "ULSCHCodewordLLR", ...
            sixgr.util.structGet(rx, "DLSCHCodewordLLR", []));
        if isempty(llr)
            llr = sixgr.util.structGet(rx, "CodewordLLR", []);
        end
    else
        llr = sixgr.util.structGet(rx, "CodewordLLR", []);
        if isempty(llr)
            llr = sixgr.util.structGet(rx, "ULSCHCodewordLLR", ...
                sixgr.util.structGet(rx, "DLSCHCodewordLLR", []));
        end
    end
    demapperLLRCount = double(numel(llr));
end
end

function metrics = localTrackingMetrics(Hest, cfg)
metrics = struct( ...
    "EstimatedDopplerHz", NaN, ...
    "PhaseTrackingError_deg", NaN, ...
    "QCLAccuracy", NaN, ...
    "QCLMeasurementStatus", "not_measured_requires_QCL_TCI_binding_evidence", ...
    "EstimatedChannelReferenceCorrelationMagnitude", NaN, ...
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
    % This compares estimated channel symbols to the first symbol. It has
    % no QCL source-RS pair, QCL type, activated TCI state or validation of
    % shared channel properties, so it cannot be called QCL accuracy.
    metrics.EstimatedChannelReferenceCorrelationMagnitude = mean(corrVals, "omitnan");
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
if any(~isfinite(real(refSym(:))) | ~isfinite(imag(refSym(:)))) || ...
        any(~isfinite(real(eqSymRaw(:))) | ~isfinite(imag(eqSymRaw(:))))
    error("sixgr:link:NonfiniteSymbolEvidence", ...
        "SER/EVM requires every paired symbol to be finite; invalid samples cannot be discarded.");
end
refUse = refSym(:);
eqRawUse = eqSymRaw(:);
info.Status = "matched_layer_domain_same_shape";
% The receiver owns timing, channel equalization and phase tracking. The
% reporter may align resource identities, but must not fit a complex gain
% from the known transmitted payload and silently repair receiver errors.
eqAligned = eqRawUse;
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

function constellationT = localConstellationTable(direction, modulation, snr_dB, tx, refSym, eqSymRaw, eqSymAligned, hardSym, detectorSym, orderInfo, referenceOrder, captureScope)
constellationT = table();
if isempty(eqSymAligned)
    return;
end
L = min(numel(eqSymAligned), 512);
if captureScope == "full_allocation"
    L = numel(eqSymAligned);
    expectedCount = double(sixgr.util.structGet(tx, "QAMSymbolCount", NaN));
    if ~isscalar(expectedCount) || ~isfinite(expectedCount) || expectedCount ~= L
        error("sixgr:link:IncompleteConstellationAllocation", ...
            "Full capture requires the paired count to equal the transmitter's actual QAMSymbolCount.");
    end
    % Full-allocation evidence needs the actual layer/QAM ordering map; port
    % indices or inferred grid dimensions cannot establish coverage.
    requiredCoordinates = ["LinearIndex", "SubcarrierIndex", "OFDMSymbolIndex", "LayerIndex"];
    for coordinate = requiredCoordinates
        values = sixgr.util.structGet(referenceOrder, coordinate, []);
        if numel(values) ~= L || any(~isfinite(values(:))) || ...
                any(values(:) < 1 | values(:) ~= round(values(:)))
            error("sixgr:link:IncompleteConstellationOrdering", ...
                "Full-allocation capture requires one valid %s per paired symbol.", coordinate);
        end
    end
    if numel(unique(double(referenceOrder.LinearIndex(:)))) ~= L
        error("sixgr:link:DuplicateConstellationResource", ...
            "Full-allocation capture cannot contain duplicate layer resource identities.");
    end
end
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
[subcarrierIdx, ofdmSymbolIdx, layerIdx, codewordIdx] = localConstellationRECoordinates(tx, direction, L, referenceOrder);
cwByLayer = double(sixgr.util.structGet(tx, "CodewordLayerMapping.CodewordIndexByLayer", []));
if ~isempty(cwByLayer)
    if any(~isfinite(cwByLayer(:)) | cwByLayer(:) < 0 | cwByLayer(:) ~= round(cwByLayer(:))) || ...
            any(~isfinite(layerIdx) | layerIdx < 1 | layerIdx > numel(cwByLayer))
        error("sixgr:link:InvalidConstellationCodewordMapping", ...
            "Paired samples must resolve to the transmitter's codeword-to-layer map.");
    end
    codewordIdx = reshape(cwByLayer(layerIdx), [], 1);
elseif captureScope == "full_allocation"
    error("sixgr:link:MissingConstellationCodewordMapping", ...
        "Full capture requires the transmitter's codeword-to-layer map.");
end
errorMag = abs(eqUse - refUse);
% Per-sample errors use the complete observation's average reference power,
% not each QAM point's amplitude or the truncated preview's power.
refPower = mean(abs(refSym(:)).^2);
evmRms = nan(L, 1);
if isfinite(refPower) && refPower > 0
    evmRms = abs(eqUse - refUse) ./ sqrt(refPower);
end

constellationT = table( ...
    repmat(direction, L, 1), modulation(1:L), repmat(double(snr_dB), L, 1), (1:L).', ...
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
constellationT.EVMReferencePower = repmat(refPower, L, 1);
constellationT.EqualizationSource = repmat("receiver_output_without_payload_gain_or_phase_fit", L, 1);
constellationT.Normalization = repmat("receiver_equalized_symbols_average_reference_power_no_payload_fit", L, 1);
constellationT.CaptureScope = repmat("paired_sample_preview", L, 1);
if captureScope == "full_allocation"
    constellationT.CaptureScope(:) = "full_allocation_paired_symbols";
end
constellationT.ObservationSymbolCount = repmat(double(numel(refSym)), L, 1);
constellationT.CapturedSymbolCount = repmat(double(L), L, 1);
constellationT.SymbolCoordinateDomain = repmat("layer_resource_elements", L, 1);
if direction == "UL" && logical(sixgr.util.structGet(tx, "PUSCH.TransformPrecoding", false))
    % After inverse DFT, QAM positions share an OFDM-symbol identity but are
    % not individual physical subcarrier REs. Do not label them as such.
    constellationT.SymbolCoordinateDomain(:) = "pre_transform_qam_positions";
end
end

function [subcarrierIdx, ofdmSymbolIdx, layerIdx, codewordIdx] = localConstellationRECoordinates(tx, direction, L, order)
subcarrierIdx = nan(L, 1);
ofdmSymbolIdx = nan(L, 1);
layerIdx = nan(L, 1);
codewordIdx = zeros(L, 1);
if nargin < 3 || L <= 0
    return;
end
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

function [hard, symbolErrors, bitErrors, bitsCompared, status] = localNRDecisionEvidence(sym, ref, modulation)
% Use TS 38.211 mapping, not the subset/order of points in a known payload.
% These are pre-decoder symbol decisions, not transport-block BER or CRC.
sym = localEnsureColumn(sym);
ref = localEnsureColumn(ref);
hard = complex(nan(size(sym)));
symbolErrors = NaN;
bitErrors = NaN;
bitsCompared = NaN;
status = "unavailable_unsupported_nr_constellation";
token = upper(string(modulation));
if ~any(token == ["BPSK", "PI/2-BPSK", "QPSK", "16QAM", "64QAM", "256QAM", "1024QAM"])
    return;
end
if token == "PI/2-BPSK"
    token = "pi/2-BPSK";
end
referenceBits = nrSymbolDemodulate(ref, token, 'DecisionType', 'hard');
nominalReference = nrSymbolModulate(referenceBits, token);
% A scaled/custom TX alphabet needs explicit normalization/mapping authority.
% Do not infer its scale or learn a constellation from the payload. EVM can
% still be measured against the actual paired reference independently.
if any(abs(ref - nominalReference) > 1e-6 * max(1, abs(nominalReference)))
    status = "unavailable_reference_not_nr_normalized";
    return;
end
receivedBits = nrSymbolDemodulate(sym, token, 'DecisionType', 'hard');
hard = nrSymbolModulate(receivedBits, token);
bitMismatch = receivedBits ~= referenceBits;
bitErrors = sum(bitMismatch);
bitsCompared = numel(referenceBits);
symbolErrors = sum(any(reshape(bitMismatch, localQm(token), []), 1));
status = "measured_nr_hard_decision";
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
        qm = NaN;
end
end

function slotDur_s = localSlotDuration(cfg)
slotDur_s = sixgr.time.slotDurationSec(cfg);
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
