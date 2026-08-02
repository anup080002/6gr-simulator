function metrics = measureULLinkState(Hest, nVar, cfg, varargin)
%MEASUREULLINKSTATE Derive UL link-state measurements from actual UL RX evidence.
%
% This helper intentionally does not reuse DL CSI feedback semantics for UL.
% It reports only measurements that can be supported by the active UL
% receive chain:
%   - DMRS-reference Hest/noise-variance SINR estimate
%   - received reference-signal power
%   - CQI derived from the UL SINR estimate
%   - rank estimate from the wideband channel estimate
%   - TPMI/beam metadata only when the active UL path is codebook-based

ip = inputParser;
ip.addParameter("ReceivedGrid", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("ReferenceIndices", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("ReferenceSymbols", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("PrecoderInfo", struct(), @(x) isempty(x) || isstruct(x));
ip.parse(varargin{:});
opt = ip.Results;
reportCQI = logical(sixgr.util.structGet(cfg, "phy.csi.reportCQI", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "cqi_reporting", reportCQI, ...
    "measureULLinkState.CQI");

metrics = struct( ...
    "NMSE_dB", NaN, ...
    "DetectionMetric", NaN, ...
    "SINR_dB", NaN, ...
    "SINRSource", "", ...
    "SINRValueRole", "", ...
    "SINRValueStatus", "", ...
    "SINRNAReason", "", ...
    "PilotSINR_dB", NaN, ...
    "PilotSINRSource", "", ...
    "PilotSINRValueRole", "diagnostic_reference_signal_quality_not_for_scheduling", ...
    "PilotSINRValueStatus", "", ...
    "PilotSINRNAReason", "", ...
    "CQI", NaN, ...
    "CQISource", "", ...
    "CQIValueStatus", "", ...
    "RI", NaN, ...
    "PMI", NaN, ...
    "CRI", NaN, ...
    "PMIType", "", ...
    "PMICodebookMode", "", ...
    "CSIReportMode", "", ...
    "CSIPayloadBitLength", NaN, ...
    "CSIPayloadHex", "", ...
    "ChannelGain_dB", NaN, ...
    "RankEstimate", NaN, ...
    "ConditionNumber_dB", NaN, ...
    "NumRxAnt", NaN, ...
    "NumTxPorts", NaN, ...
    "SelectedBeamIndices", [], ...
    "SelectedBeamIndex", NaN, ...
    "BestBeamIndex", NaN, ...
    "BeamHit", NaN, ...
    "TopKBeamHit", NaN, ...
    "BeamCandidateCount", NaN, ...
    "SelectedBeamGain_dB", NaN, ...
    "BestBeamGain_dB", NaN, ...
    "BeamGainGap_dB", NaN, ...
    "BeamScoreVector_dB", "", ...
    "TopBeamIndexSet", "", ...
    "TopBeamGainSet_dB", "", ...
    "BeamScoreSource", "", ...
    "ConfiguredPMI", NaN, ...
    "ConfiguredCRI", NaN, ...
    "CSI_RSRP_dB", NaN, ...
    "CSI_RSRPSource", "", ...
    "CSI_RSSI_dB", NaN, ...
    "CSI_RSSISource", "", ...
    "CSI_RSRQ_dB", NaN, ...
    "CSI_RSRQSource", "", ...
    "RISource", "", ...
    "PMISource", "", ...
    "RuntimeAppliedPMI", NaN, ...
    "TPMICandidateCount", NaN, ...
    "TPMIMutualInformation", NaN, ...
    "SRSConditionNumber_dB", NaN, ...
    "SRSRITPMIValid", false);

if isempty(Hest)
    metrics.SINRSource = "ul_receiver_hest_missing";
    metrics.SINRValueStatus = "unavailable";
    metrics.SINRNAReason = "ul_channel_estimate_empty";
    return;
end

Hwb = localWidebandChannelMatrix(Hest, cfg);
if isempty(Hwb)
    metrics.SINRSource = "ul_receiver_hest_wideband_matrix_unavailable";
    metrics.SINRValueStatus = "unavailable";
    metrics.SINRNAReason = "ul_wideband_channel_matrix_unavailable";
    return;
end

[metrics.NumRxAnt, metrics.NumTxPorts] = size(Hwb);
[metrics.ChannelGain_dB, metrics.RankEstimate, metrics.ConditionNumber_dB] = localWidebandChannelDescriptors(Hwb);
metrics.RI = localResolveULRankIndicator(metrics.RankEstimate, cfg);
metrics.RISource = "ul_wideband_rank_indicator_lab_default";

srsEstimate = sixgr.phy.ul.estimateSRSRITPMI(Hest, nVar, cfg);
metrics.SRSRITPMIValid = logical(sixgr.util.structGet(srsEstimate, "Valid", false));
metrics.SRSConditionNumber_dB = double(sixgr.util.structGet(srsEstimate, "ConditionNumber_dB", NaN));
metrics.TPMICandidateCount = double(sixgr.util.structGet(srsEstimate, "TPMICandidateCount", NaN));
metrics.TPMIMutualInformation = double(sixgr.util.structGet(srsEstimate, "TPMIMutualInformation", NaN));
if isfinite(double(sixgr.util.structGet(srsEstimate, "RI", NaN)))
    metrics.RI = double(sixgr.util.structGet(srsEstimate, "RI", metrics.RI));
    metrics.RISource = char(string(sixgr.util.structGet(srsEstimate, "RISource", "ul_srs_covariance_rank_estimator_lab_default")));
end

[sinr_dB, sinrSource, sinrStatus, pilotNMSE_dB, perRBSINR_dB] = localMeasureReferenceSINR(Hest, nVar, ...
    opt.ReceivedGrid, opt.ReferenceIndices, opt.ReferenceSymbols, cfg);
measuredSINRAvailable = isfinite(sinr_dB);
metrics.PilotSINR_dB = double(sinr_dB);
metrics.PilotSINRSource = char(string(sinrSource));
metrics.PilotSINRValueRole = "diagnostic_reference_signal_quality_not_for_scheduling";
metrics.PilotSINRValueStatus = char(string(sinrStatus));
if isfinite(sinr_dB)
    metrics.SINR_dB = double(sinr_dB);
    metrics.SINRSource = "measured_ul_rs_sinr";
    metrics.SINRValueRole = "measured_ul_rs_cqi_input";
    metrics.SINRValueStatus = char(string(sinrStatus));
    metrics.SINRNAReason = "";
else
    metrics.SINRSource = char(string(sinrSource));
    if strlength(strtrim(string(metrics.SINRSource))) == 0
        metrics.SINRSource = "ul_reference_signal_sinr_unavailable";
    end
    metrics.SINRValueRole = "unavailable";
    metrics.SINRValueStatus = "unavailable";
    metrics.SINRNAReason = "ul_reference_signal_sinr_not_available_from_receiver_evidence";
    metrics.PilotSINRNAReason = metrics.SINRNAReason;
end

if isfinite(pilotNMSE_dB)
    metrics.NMSE_dB = double(pilotNMSE_dB);
    metrics.DetectionMetric = 1 / (1 + 10.^(pilotNMSE_dB / 10));
end

[referencePower, rsrpSource] = localMeasureReferencePower(opt.ReceivedGrid, opt.ReferenceIndices, opt.ReferenceSymbols);
if isfinite(referencePower) && referencePower > 0
    metrics.CSI_RSRP_dB = 10 * log10(max(referencePower, eps));
    metrics.CSI_RSRPSource = char(string(rsrpSource));
else
    metrics.CSI_RSRPSource = "measurement_unavailable";
end
[rssiPower, rssiNRB, rssiSource, ~] = localMeasureRSSI(opt.ReceivedGrid, opt.ReferenceIndices);
if isfinite(rssiPower) && rssiPower > 0
    metrics.CSI_RSSI_dB = 10 * log10(max(rssiPower, eps));
    metrics.CSI_RSSISource = char(string(rssiSource));
end
if isfinite(referencePower) && referencePower > 0 && isfinite(rssiPower) && rssiPower > 0 && ...
        isfinite(rssiNRB) && rssiNRB > 0
    metrics.CSI_RSRQ_dB = 10 * log10(max(double(rssiNRB) * referencePower / max(rssiPower, eps), eps));
    metrics.CSI_RSRQSource = "ts38215_n_times_rsrp_over_rssi";
end

if measuredSINRAvailable && reportCQI
    feedback = sixgr.link.resolveWidebandCQI(struct( ...
        "WidebandSINR_dB", metrics.SINR_dB, ...
        "PerRBSINR_dB", double(perRBSINR_dB), ...
        "SINRSource", metrics.SINRSource, ...
        "SINRValueRole", metrics.SINRValueRole, ...
        "SINRValueStatus", metrics.SINRValueStatus), cfg, "UL");
    rawCQI = double(sixgr.util.structGet(feedback, "WidebandCQI", NaN));
    if isfinite(rawCQI)
        metrics.CQI = double(max(0, min(15, round(rawCQI))));
        metrics.CQISource = "ul_measured_rs_sinr_to_cqi:" + string(sixgr.util.structGet(feedback, "Mode", "sinr_threshold_table"));
        if metrics.CQI == 0
            metrics.CQIValueStatus = "out_of_range_cqi0_from_measured_ul_sinr";
        else
            metrics.CQIValueStatus = "OK";
        end
    else
        metrics.CQI = NaN;
        metrics.CQISource = "ul_measured_rs_sinr_rejected_for_cqi:" + string(sixgr.util.structGet(feedback, "SINRInputRejectionReason", ""));
        metrics.CQIValueStatus = "unavailable_non_scheduling_sinr_input";
    end
end

metrics = localResolveULPrecoderMeasurementFields(metrics, cfg, opt.PrecoderInfo, srsEstimate);
end

function [gain_dB, rankEstimate, cond_dB] = localWidebandChannelDescriptors(Hwb)
gain_dB = NaN;
rankEstimate = NaN;
cond_dB = NaN;
gainLin = mean(abs(Hwb(:)).^2, "omitnan");
if isfinite(gainLin) && gainLin > 0
    gain_dB = 10 * log10(max(gainLin, eps));
end
try
    [cond, ~, rankEst] = sixgr.mimo.channelConditionNumber(Hwb);
catch
    cond = NaN;
    rankEst = NaN;
end
if isfinite(rankEst)
    rankEstimate = double(rankEst);
end
cond_dB = double(cond);
end

function ri = localResolveULRankIndicator(rankEstimate, cfg)
configuredLayers = double(sixgr.util.structGet(cfg, "phy.pusch.nLayers", ...
    sixgr.util.structGet(cfg, "phy.pusch.NumLayers", ...
    sixgr.util.structGet(cfg, "phy.pusch.maxRankDefault", 1))));
if ~(isscalar(configuredLayers) && isfinite(configuredLayers) && configuredLayers >= 1)
    configuredLayers = 1;
end
configuredLayers = max(1, round(configuredLayers));
ri = NaN;
if isfinite(rankEstimate) && rankEstimate >= 1
    ri = double(max(1, min(round(rankEstimate), configuredLayers)));
else
    ri = double(configuredLayers);
end
end

function metrics = localResolveULPrecoderMeasurementFields(metrics, cfg, precInfo, srsEstimate)
configuredPMI = double(sixgr.util.structGet(cfg, "phy.pusch.TPMI", ...
    sixgr.util.structGet(cfg, "phy.pusch.PMI", NaN)));
metrics.ConfiguredPMI = configuredPMI;
metrics.ConfiguredCRI = NaN;

scheme = lower(string(sixgr.util.structGet(cfg, "phy.pusch.transmissionScheme", "nonCodebook")));
transformPrecoding = logical(sixgr.util.structGet(cfg, "phy.pusch.transformPrecoding", false));
isCodebook = scheme == "codebook" && ~transformPrecoding;

appliedPMI = double(sixgr.util.structGet(precInfo, "AppliedPrecoderPMI", NaN));
if ~(isfinite(appliedPMI) && isCodebook)
    appliedPMI = configuredPMI;
end
metrics.RuntimeAppliedPMI = appliedPMI;

if isCodebook && isfinite(appliedPMI)
    estimatedTPMI = double(sixgr.util.structGet(srsEstimate, "TPMI", NaN));
    estimatedBeamIndices = double(sixgr.util.structGet(srsEstimate, "SelectedBeamIndices", []));
    if isfinite(estimatedTPMI)
        metrics.PMI = double(round(estimatedTPMI));
        metrics.PMISource = char(string(sixgr.util.structGet(srsEstimate, "TPMISource", "ul_srs_mutual_information_tpmi_estimator_lab_default")));
    else
        metrics.PMI = double(round(appliedPMI));
        metrics.PMISource = "ul_runtime_applied_codebook_tpmi";
    end
    metrics.PMIType = char(string(sixgr.util.structGet(precInfo, "AppliedPrecoderPMIType", "pusch_codebook")));
    metrics.PMICodebookMode = char(string(sixgr.util.structGet(precInfo, "AppliedPrecoderCodebookMode", ...
        sixgr.util.structGet(cfg, "phy.pusch.codebookType", "nr_pusch_codebook"))));
    metrics.CSIReportMode = "ul_srs_based_ri_tpmi_estimator_lab_default";
    metrics.SelectedBeamIndices = localParseIndexSet(sixgr.util.structGet(precInfo, "AppliedBeamIndexSet", []));
    if isempty(metrics.SelectedBeamIndices) && ~isempty(estimatedBeamIndices)
        metrics.SelectedBeamIndices = estimatedBeamIndices;
    end
    if isempty(metrics.SelectedBeamIndices)
        metrics.SelectedBeamIndices = localResolveNativeULCodebookBeamIndices(metrics.NumTxPorts, metrics.RI, metrics.PMI, transformPrecoding);
    end
    if ~isempty(metrics.SelectedBeamIndices)
        metrics.SelectedBeamIndex = double(metrics.SelectedBeamIndices(1));
        metrics.BeamCandidateCount = double(max(max(metrics.SelectedBeamIndices), numel(metrics.SelectedBeamIndices)));
    end
else
    if transformPrecoding
        metrics.CSIReportMode = "ul_gnb_reference_measurement_transform_precoding_active";
    else
        metrics.CSIReportMode = "ul_gnb_reference_measurement_noncodebook";
    end
    metrics.PMI = NaN;
    metrics.CRI = NaN;
    metrics.PMIType = "";
    metrics.PMICodebookMode = "";
    metrics.SelectedBeamIndices = [];
    metrics.PMISource = "ul_tpmi_not_applicable";
end
metrics.CSIPayloadBitLength = NaN;
metrics.CSIPayloadHex = "";
end

function values = localParseIndexSet(rawValue)
values = [];
if isempty(rawValue)
    return;
end
if isstring(rawValue) || ischar(rawValue)
    toks = regexp(char(string(rawValue)), "\d+", "match");
    if isempty(toks)
        return;
    end
    values = str2double(string(toks));
else
    values = double(rawValue(:).');
end
values = values(isfinite(values));
values = unique(round(values), "stable");
end

function beamIndices = localResolveNativeULCodebookBeamIndices(numTxPorts, rankIndicator, tpmi, transformPrecoding)
beamIndices = [];
if ~(isscalar(numTxPorts) && isfinite(numTxPorts) && numTxPorts >= 1 && ...
        isfinite(rankIndicator) && rankIndicator >= 1 && isfinite(tpmi))
    return;
end
if exist("nrPUSCHCodebook", "file") ~= 2
    return;
end
try
    W = nrPUSCHCodebook(max(1, round(rankIndicator)), max(1, round(numTxPorts)), round(tpmi), logical(transformPrecoding));
catch
    try
        W = nrPUSCHCodebook(max(1, round(rankIndicator)), max(1, round(numTxPorts)), round(tpmi));
    catch
        W = [];
    end
end
if isempty(W)
    return;
end
portPower = sum(abs(double(W)).^2, 1, "omitnan");
beamIndices = find(isfinite(portPower) & portPower > (eps(max(portPower, [], "omitnan")) * 16));
end

function Hwb = localWidebandChannelMatrix(Hest, cfg)
Hwb = [];
if isempty(Hest)
    return;
end
nd = ndims(Hest);
if nd >= 4
    try
        Havg = mean(mean(Hest, 1, "omitnan"), 2, "omitnan");
    catch
        Havg = mean(mean(Hest, 1), 2);
    end
    Hwb = squeeze(Havg);
elseif nd == 3
    try
        Havg = mean(mean(Hest, 1, "omitnan"), 2, "omitnan");
    catch
        Havg = mean(mean(Hest, 1), 2);
    end
    Hwb = reshape(squeeze(Havg), [], 1);
elseif ismatrix(Hest)
    [expectedRx, expectedTx] = localExpectedWidebandMatrixSize(cfg);
    if size(Hest, 1) == expectedRx && size(Hest, 2) == expectedTx
        Hwb = double(Hest);
    else
        try
            Havg = mean(Hest(:), "omitnan");
        catch
            Havg = mean(Hest(:));
        end
        Hwb = Havg;
    end
end
if isvector(Hwb)
    Hwb = reshape(Hwb, numel(Hwb), 1);
end
if ~ismatrix(Hwb)
    Hwb = [];
end
end

function [expectedRx, expectedTx] = localExpectedWidebandMatrixSize(cfg)
expectedRx = double(sixgr.util.structGet(cfg, "phy.nRxAnt", 1));
expectedTx = double(sixgr.util.structGet(cfg, "phy.nTxAnt", ...
    sixgr.util.structGet(cfg, "phy.pusch.nLayers", 1)));
if ~(isscalar(expectedRx) && isfinite(expectedRx) && expectedRx >= 1)
    expectedRx = 1;
end
if ~(isscalar(expectedTx) && isfinite(expectedTx) && expectedTx >= 1)
    expectedTx = 1;
end
expectedRx = max(1, round(expectedRx));
expectedTx = max(1, round(expectedTx));
end

function [powerLin, source] = localMeasureReferencePower(rxGrid, refInd, refSym)
powerLin = NaN;
source = "measurement_unavailable";
if isempty(rxGrid) || isempty(refInd)
    return;
end
try
    rxRef = nrExtractResources(refInd, rxGrid);
catch
    rxRef = [];
end
if isempty(rxRef)
    return;
end
if ~isempty(refSym)
    try
        refMask = abs(refSym(:)) > 0;
        if ismatrix(rxRef) && size(rxRef, 1) == numel(refMask)
            rxRef = rxRef(refMask, :);
        elseif isvector(rxRef) && numel(rxRef) == numel(refMask)
            rxRef = rxRef(refMask);
        end
    catch
    end
end
vals = abs(double(rxRef(:))).^2;
vals = vals(isfinite(vals));
if isempty(vals)
    return;
end
powerLin = mean(vals, "omitnan");
source = "received_reference_signal_power";
end

function [rssiLin, nRB, source, status] = localMeasureRSSI(rxGrid, refInd)
rssiLin = NaN;
nRB = NaN;
source = "measurement_unavailable";
status = "unavailable";
if isempty(rxGrid) || isempty(refInd)
    return;
end
[subcarrier, symbol] = localReferenceSubcarrierAndSymbol(rxGrid, refInd);
if isempty(subcarrier) || isempty(symbol)
    return;
end
rbIndex = unique(floor((double(subcarrier(:)) - 1) ./ 12) + 1);
rbIndex = rbIndex(isfinite(rbIndex) & rbIndex >= 1);
symbol = unique(double(symbol(:)));
symbol = symbol(isfinite(symbol) & symbol >= 1 & symbol <= size(rxGrid, 2));
if isempty(rbIndex) || isempty(symbol)
    return;
end
nRB = double(numel(rbIndex));
scMask = false(size(rxGrid, 1), 1);
for i = 1:numel(rbIndex)
    sc0 = (rbIndex(i) - 1) * 12 + 1;
    sc1 = min(size(rxGrid, 1), sc0 + 11);
    if sc0 <= size(rxGrid, 1)
        scMask(sc0:sc1) = true;
    end
end
perSymbolPower = nan(numel(symbol), 1);
for i = 1:numel(symbol)
    vals = abs(double(rxGrid(scMask, round(symbol(i)), :))).^2;
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        perSymbolPower(i) = sum(vals, "omitnan");
    end
end
perSymbolPower = perSymbolPower(isfinite(perSymbolPower));
if isempty(perSymbolPower)
    return;
end
rssiLin = mean(perSymbolPower, "omitnan");
source = "received_signal_strength_indicator_measurement_bandwidth";
status = "OK";
end

function [subcarrier, symbol] = localReferenceSubcarrierAndSymbol(rxGrid, refInd)
subcarrier = [];
symbol = [];
if isempty(refInd)
    return;
end
if isnumeric(refInd) && ismatrix(refInd) && size(refInd, 2) >= 2 && size(refInd, 2) <= 4 && size(refInd, 1) > 1
    subcarrier = double(refInd(:, 1));
    symbol = double(refInd(:, 2));
    return;
end
nSc = size(rxGrid, 1);
nSym = size(rxGrid, 2);
idx = double(refInd(:));
idx = idx(isfinite(idx) & idx >= 1);
if isempty(idx)
    return;
end
subcarrier = mod(idx - 1, max(nSc, 1)) + 1;
symbol = mod(floor((idx - 1) ./ max(nSc, 1)), max(nSym, 1)) + 1;
end

function [sinr_dB, source, status, pilotNMSE_dB, perRBSINR_dB] = localMeasureReferenceSINR(Hest, nVar, rxGrid, refInd, refSym, cfg)
sinr_dB = NaN;
source = "measurement_unavailable";
status = "unavailable";
pilotNMSE_dB = NaN;
perRBSINR_dB = [];
if isempty(Hest) || isempty(rxGrid) || isempty(refInd) || isempty(refSym)
    return;
end
try
    [rxRef, hRef] = nrExtractResources(refInd, rxGrid, Hest);
catch
    status = "reference_extraction_failed";
    return;
end
[rxPilot, pilotRecon, pilotObsH, pilotEstH] = localPilotChannelObservation(rxRef, hRef, refSym);
if isempty(rxPilot) || isempty(pilotRecon) || isempty(pilotObsH) || isempty(pilotEstH)
    status = "reference_observation_unavailable";
    return;
end
perRBSINR_dB = localPerRBReferenceSINR(rxGrid, refInd, rxRef, hRef, refSym, nVar);
maxTrustedSINR = localMaxTrustedReferenceSINR(cfg);
if isfinite(maxTrustedSINR) && ~isempty(perRBSINR_dB)
    perRBSINR_dB = min(double(perRBSINR_dB), double(maxTrustedSINR));
end

[signalPowLin, noisePowLin] = localHestNoiseSignalPowers(hRef, refSym, nVar);
[pilotSignalPowLin, pilotResidualPowLin] = localPilotSignalResidualPowers(rxPilot, pilotRecon, nVar);
if isfinite(pilotSignalPowLin) && pilotSignalPowLin > 0
    signalPowLin = pilotSignalPowLin;
end
if isfinite(pilotResidualPowLin) && pilotResidualPowLin > 0
    noisePowLin = max(localFiniteOrZero(noisePowLin), pilotResidualPowLin);
end
if isfinite(signalPowLin) && signalPowLin > 0 && isfinite(noisePowLin) && noisePowLin > 0
    sinr_dB = 10 * log10(signalPowLin / noisePowLin);
    source = "receiver_hest_reference_signal_measurement";
    status = "OK";
    if isfinite(maxTrustedSINR) && sinr_dB > maxTrustedSINR
        sinr_dB = double(maxTrustedSINR);
        status = "OK_dynamic_range_limited";
    end
end

nmseLin = localNormalizedPilotMSE(pilotEstH, pilotObsH);
if isfinite(nmseLin) && nmseLin > 0
    pilotNMSE_dB = 10 * log10(max(nmseLin, eps));
end
if ~isfinite(sinr_dB)
    status = "reference_signal_measurement_unavailable";
end
end

function maxSINR = localMaxTrustedReferenceSINR(cfg)
maxSINR = double(sixgr.util.structGet(cfg, "phy.csi.maxTrustedReferenceSINR_dB", 80));
if ~(isscalar(maxSINR) && isfinite(maxSINR) && maxSINR > 0)
    maxSINR = inf;
end
end

function perRBSINR_dB = localPerRBReferenceSINR(rxGrid, refInd, rxRef, hRef, refSym, nVar)
perRBSINR_dB = [];
if isempty(rxGrid) || isempty(refInd) || isempty(rxRef) || isempty(hRef) || isempty(refSym)
    return;
end
subcarrier = localReferenceSubcarrierIndices(rxGrid, refInd);
if isempty(subcarrier)
    return;
end
numRE = min([numel(subcarrier), size(rxRef, 1), size(hRef, 1), numel(refSym)]);
if numRE < 1
    return;
end
subcarrier = double(subcarrier(1:numRE));
refSym = double(refSym(1:numRE));
rxRef = double(rxRef(1:numRE, :, :, :));
hRef = double(hRef(1:numRE, :, :, :));
[pilotRecon, ~, ~, validRef] = localReferenceReconstruction(hRef, refSym, numRE);
valid = isfinite(subcarrier) & validRef(:);
if ~any(valid)
    return;
end
subcarrier = subcarrier(valid);
pilotRecon = pilotRecon(valid, :);
signalPow = mean(abs(pilotRecon).^2, 2, "omitnan");
nVar = double(nVar);
if ~(isscalar(nVar) && isfinite(nVar) && nVar > 0)
    return;
end
noisePow = repmat(nVar, size(signalPow));
rbIndex = floor((subcarrier - 1) ./ 12) + 1;
maxRb = max(rbIndex(isfinite(rbIndex)));
if ~(isfinite(maxRb) && maxRb >= 1)
    return;
end
perRBSINR_dB = nan(maxRb, 1);
for rb = 1:maxRb
    mask = rbIndex == rb & isfinite(signalPow) & signalPow > 0 & isfinite(noisePow) & noisePow > 0;
    if ~any(mask)
        continue;
    end
    sig = mean(signalPow(mask), "omitnan");
    res = mean(noisePow(mask), "omitnan");
    if isfinite(sig) && sig > 0 && isfinite(res) && res > 0
        perRBSINR_dB(rb) = 10 * log10(sig / res);
    end
end
end

function subcarrier = localReferenceSubcarrierIndices(rxGrid, refInd)
subcarrier = [];
if isempty(refInd)
    return;
end
if isnumeric(refInd) && ismatrix(refInd) && size(refInd, 2) >= 1 && size(refInd, 2) <= 4 && size(refInd, 1) > 1
    if size(refInd, 2) > 1
        subcarrier = double(refInd(:, 1));
        return;
    end
end
try
    nSc = size(rxGrid, 1);
    subcarrier = mod(double(refInd(:)) - 1, max(double(nSc), 1)) + 1;
catch
    subcarrier = [];
end
end

function values = localMeanAcrossNonRE(x)
values = double(x);
for dim = ndims(values):-1:2
    try
        values = mean(values, dim, "omitnan");
    catch
        values = mean(values, dim);
    end
end
values = squeeze(values);
end

function [rxPilot, pilotRecon, pilotObsH, pilotEstH] = localPilotChannelObservation(rxRef, hRef, refSym)
rxPilot = [];
pilotRecon = [];
pilotObsH = [];
pilotEstH = [];
L = min([size(rxRef, 1), size(hRef, 1)]);
if ~(isfinite(L) && L >= 1)
    return;
end
rxMat = reshape(double(rxRef(1:L, :, :, :)), L, []);
[pilotReconAll, pilotEstHAll, refScale, valid] = localReferenceReconstruction(hRef, refSym, L);
if isempty(pilotReconAll) || ~any(valid)
    return;
end
rxPilot = rxMat(valid, :);
pilotRecon = pilotReconAll(valid, :);
pilotEstH = pilotEstHAll(valid, :);
pilotObsH = rxPilot ./ max(refScale(valid), sqrt(eps));
end

function [signalPowLin, noisePowLin] = localHestNoiseSignalPowers(hRef, refSym, nVar)
signalPowLin = NaN;
noisePowLin = NaN;
L = size(hRef, 1);
if ~(isfinite(L) && L >= 1)
    return;
end
[pilotRecon, ~, ~, valid] = localReferenceReconstruction(hRef, refSym, L);
if ~any(valid)
    return;
end
signalPow = abs(pilotRecon(valid, :)).^2;
signalPow = signalPow(isfinite(signalPow));
if isempty(signalPow)
    return;
end
nVar = double(nVar);
if ~(isscalar(nVar) && isfinite(nVar) && nVar > 0)
    return;
end
signalPowLin = mean(signalPow, "omitnan");
noisePowLin = nVar;
end

function [pilotRecon, pilotEstH, refScale, valid] = localReferenceReconstruction(hRef, refSym, L)
pilotRecon = [];
pilotEstH = [];
refScale = [];
valid = false(0, 1);
if isempty(hRef) || isempty(refSym) || ~(isfinite(L) && L >= 1)
    return;
end
h = reshape(double(hRef(1:L, :, :, :)), L, size(hRef, 2), []);
nPorts = size(h, 3);
refMat = localReferenceSymbolMatrix(refSym, L, nPorts);
if isempty(refMat)
    return;
end
refEnergy = sum(abs(refMat).^2, 2);
valid = refEnergy > sqrt(eps);
if ~any(valid)
    return;
end
pilotRecon = complex(zeros(L, size(h, 2)));
for p = 1:nPorts
    pilotRecon = pilotRecon + h(:, :, p) .* refMat(:, p);
end
refScale = sqrt(max(refEnergy, eps));
pilotEstH = pilotRecon ./ max(refScale, sqrt(eps));
end

function refMat = localReferenceSymbolMatrix(refSym, L, nPorts)
refMat = [];
if isempty(refSym) || ~(isfinite(L) && L >= 1) || ~(isfinite(nPorts) && nPorts >= 1)
    return;
end
raw = double(refSym);
if isvector(raw)
    raw = raw(:);
    if numel(raw) >= L * nPorts
        refMat = reshape(raw(1:L * nPorts), L, nPorts);
    elseif numel(raw) >= L
        refMat = repmat(raw(1:L), 1, nPorts);
    end
else
    raw = reshape(raw, size(raw, 1), []);
    if size(raw, 1) < L
        flat = raw(:);
        if numel(flat) >= L * nPorts
            refMat = reshape(flat(1:L * nPorts), L, nPorts);
        end
    else
        refMat = raw(1:L, :);
        if size(refMat, 2) < nPorts
            refMat = [refMat, zeros(L, nPorts - size(refMat, 2))]; %#ok<AGROW>
        elseif size(refMat, 2) > nPorts
            refMat = refMat(:, 1:nPorts);
        end
    end
end
end

function [signalPowLin, residualPowLin] = localPilotSignalResidualPowers(rxPilot, pilotRecon, nVar)
signalPowLin = NaN;
residualPowLin = NaN;
rxPilot = double(rxPilot(:));
pilotRecon = double(pilotRecon(:));
N = min(numel(rxPilot), numel(pilotRecon));
if N == 0
    return;
end
rxPilot = rxPilot(1:N);
pilotRecon = pilotRecon(1:N);
mask = isfinite(real(rxPilot)) & isfinite(imag(rxPilot)) & ...
    isfinite(real(pilotRecon)) & isfinite(imag(pilotRecon));
if ~any(mask)
    return;
end
rxPilot = rxPilot(mask);
pilotRecon = pilotRecon(mask);
signalPowLin = mean(abs(pilotRecon).^2, "omitnan");
residualPowLin = mean(abs(rxPilot - pilotRecon).^2, "omitnan");
nVar = double(nVar);
if ~(isfinite(residualPowLin) && residualPowLin > 0) && isfinite(nVar) && nVar > 0
    residualPowLin = nVar;
end
end

function nmseLin = localNormalizedPilotMSE(hEst, hObs)
nmseLin = NaN;
hEst = double(hEst(:));
hObs = double(hObs(:));
N = min(numel(hEst), numel(hObs));
if N == 0
    return;
end
hEst = hEst(1:N);
hObs = hObs(1:N);
mask = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(real(hObs)) & isfinite(imag(hObs));
if ~any(mask)
    return;
end
hEst = hEst(mask);
hObs = hObs(mask);
alpha = (hObs' * hEst) / max(hObs' * hObs, eps);
ref = alpha * hObs;
den = mean(abs(ref).^2, "omitnan");
if ~(isfinite(den) && den > 0)
    return;
end
err = hEst - ref;
nmseLin = mean(abs(err).^2, "omitnan") / max(den, eps);
end

function value = localFiniteOrZero(value)
value = double(value);
if ~(isscalar(value) && isfinite(value) && value > 0)
    value = 0;
end
end
