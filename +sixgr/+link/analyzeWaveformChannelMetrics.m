function metrics = analyzeWaveformChannelMetrics(rx, cfg)
%ANALYZEWAVEFORMCHANNELMETRICS Derive authoritative CSI/beam metrics from the Rx chain.

metrics = struct( ...
    "NMSE_dB", NaN, ...
    "DetectionMetric", NaN, ...
    "SINR_dB", NaN, ...
    "CQI", NaN, ...
    "RI", NaN, ...
    "PMI", NaN, ...
    "CRI", NaN, ...
    "PMIType", "", ...
    "PMICodebookMode", "", ...
    "CSIReportMode", "", ...
    "CSIPayloadBitLength", NaN, ...
    "CSIPayloadHex", "", ...
    "ChannelGain_dB", NaN, ...
    "RSRP_dB", NaN, ...
    "RankEstimate", NaN, ...
    "ConditionNumber_dB", NaN, ...
    "ConditionNumberStatus", "", ...
    "NumRxAnt", NaN, ...
    "NumTxPorts", NaN, ...
    "SelectedBeamIndices", [], ...
    "SelectedBeamIndex", NaN, ...
    "BestBeamIndex", NaN, ...
    "BeamHit", NaN, ...
    "TopKBeamHit", NaN, ...
    "BeamCandidateCount", NaN, ...
    "BeamP1Index", NaN, ...
    "BeamP2Index", NaN, ...
    "BeamP3Index", NaN, ...
    "BeamP1Gain_dB", NaN, ...
    "BeamP2Gain_dB", NaN, ...
    "BeamP3Gain_dB", NaN, ...
    "SelectedBeamGain_dB", NaN, ...
    "BestBeamGain_dB", NaN, ...
    "BeamGainGap_dB", NaN, ...
    "ConfiguredPMI", NaN, ...
    "ConfiguredCRI", NaN);

Hest = sixgr.util.structGet(rx, "ChannelEstimate", []);
nVar = double(sixgr.util.structGet(rx, "NoiseVar", NaN));
if isempty(Hest)
    return;
end

measuredRSRP = double(sixgr.util.structGet(rx, "RSRP_dB", NaN));
if isfinite(measuredRSRP)
    metrics.RSRP_dB = measuredRSRP;
end

try
    csi = sixgr.phy.dl.CSI_Feedback(Hest, nVar, cfg, "RSRP_dB", measuredRSRP);
    metrics.SINR_dB = double(sixgr.util.structGet(csi, "SINR_dB", NaN));
    metrics.CQI = double(sixgr.util.structGet(csi, "CQI", NaN));
    metrics.RI = double(sixgr.util.structGet(csi, "RI", NaN));
    metrics.PMI = double(sixgr.util.structGet(csi, "PMI", NaN));
    metrics.CRI = double(sixgr.util.structGet(csi, "CRI", NaN));
    metrics.PMIType = string(sixgr.util.structGet(csi, "PMIType", ""));
    metrics.PMICodebookMode = string(sixgr.util.structGet(csi, "PMICodebookMode", ""));
    metrics.CSIReportMode = string(sixgr.util.structGet(csi, "ChannelStateInformationMode", ""));
    metrics.CSIPayloadBitLength = double(sixgr.util.structGet(csi, "CSIPayloadBitLength", NaN));
    metrics.CSIPayloadHex = char(string(sixgr.util.structGet(csi, "CSIPayloadHex", "")));
    metrics.ChannelGain_dB = double(sixgr.util.structGet(csi, "ChannelGain_dB", NaN));
    metrics.RSRP_dB = double(sixgr.util.structGet(csi, "RSRP_dB", metrics.RSRP_dB));
    metrics.SelectedBeamIndices = double(sixgr.util.structGet(csi, "SelectedBeamIndices", []));
catch
end

gain = mean(abs(Hest(:)).^2, "omitnan");
if isfinite(gain) && gain > 0
    if ~isfinite(metrics.ChannelGain_dB)
        metrics.ChannelGain_dB = 10 * log10(gain);
    end
    nmseLin = max(double(nVar), eps) / max(gain, eps);
    metrics.NMSE_dB = 10 * log10(max(nmseLin, eps));
    metrics.DetectionMetric = 1 / (1 + nmseLin);
end

Hwb = localWidebandChannelMatrix(Hest);
if isempty(Hwb)
    return;
end
metrics.NumRxAnt = size(Hwb, 1);
metrics.NumTxPorts = size(Hwb, 2);
try
    [metrics.ConditionNumber_dB, condStatus, metrics.RankEstimate] = ...
        sixgr.mimo.channelConditionNumber(Hwb);
    metrics.ConditionNumberStatus = char(condStatus);
catch
end

beamMetrics = localComputeBeamMetrics(Hwb, cfg, metrics);
beamFields = fieldnames(beamMetrics);
for f = 1:numel(beamFields)
    metrics.(beamFields{f}) = beamMetrics.(beamFields{f});
end
end

function Hwb = localWidebandChannelMatrix(Hest)
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
    Hwb = double(Hest);
end
if isvector(Hwb)
    Hwb = reshape(Hwb, numel(Hwb), 1);
end
if ~ismatrix(Hwb)
    Hwb = [];
end
end

function metrics = localComputeBeamMetrics(Hwb, cfg, baseMetrics)
metrics = struct( ...
    "SelectedBeamIndex", NaN, ...
    "BestBeamIndex", NaN, ...
    "BeamHit", NaN, ...
    "TopKBeamHit", NaN, ...
    "BeamCandidateCount", NaN, ...
    "BeamP1Index", NaN, ...
    "BeamP2Index", NaN, ...
    "BeamP3Index", NaN, ...
    "BeamP1Gain_dB", NaN, ...
    "BeamP2Gain_dB", NaN, ...
    "BeamP3Gain_dB", NaN, ...
    "SelectedBeamGain_dB", NaN, ...
    "BestBeamGain_dB", NaN, ...
    "BeamGainGap_dB", NaN, ...
    "ConfiguredPMI", NaN, ...
    "ConfiguredCRI", NaN);

if isempty(Hwb)
    return;
end

numTx = max(1, size(Hwb, 2));
numCandidates = max(numTx, round(double(sixgr.util.structGet(cfg, "phy.beamManagement.numBeams", ...
    sixgr.util.structGet(cfg, "phy.csi.numResourceCandidates", numTx)))));
codebook = sixgr.rf.getCachedOversampledDFTCodebook(numTx, numCandidates);
gains = zeros(numCandidates, 1);
for i = 1:numCandidates
    w = codebook(:, i);
    gains(i) = real(trace((Hwb * w) * (Hwb * w)'));
end
gains_dB = 10 * log10(max(gains, eps));
[sortedGains, sortedIdx] = sort(gains_dB, "descend");
metrics.BeamCandidateCount = double(numCandidates);
metrics.BestBeamIndex = double(sortedIdx(1) - 1);
metrics.BestBeamGain_dB = double(sortedGains(1));
metrics.BeamP1Index = double(sortedIdx(1) - 1);
metrics.BeamP1Gain_dB = double(sortedGains(1));
if numel(sortedIdx) >= 2
    metrics.BeamP2Index = double(sortedIdx(2) - 1);
    metrics.BeamP2Gain_dB = double(sortedGains(2));
end
if numel(sortedIdx) >= 3
    metrics.BeamP3Index = double(sortedIdx(3) - 1);
    metrics.BeamP3Gain_dB = double(sortedGains(3));
end

configuredPMI = double(sixgr.util.structGet(cfg, "phy.pdsch.PMI", NaN));
configuredCRI = double(sixgr.util.structGet(cfg, "phy.beamManagement.selectedCRI", NaN));
metrics.ConfiguredPMI = configuredPMI;
metrics.ConfiguredCRI = configuredCRI;
selectedIdx = NaN;
if isfinite(configuredPMI)
    selectedIdx = configuredPMI;
elseif ~isempty(baseMetrics.SelectedBeamIndices)
    selectedIdx = double(baseMetrics.SelectedBeamIndices(1)) - 1;
elseif isfinite(configuredCRI)
    selectedIdx = configuredCRI;
end
if isfinite(selectedIdx)
    selectedIdx = max(0, min(numCandidates - 1, round(selectedIdx)));
    metrics.SelectedBeamIndex = double(selectedIdx);
    metrics.SelectedBeamGain_dB = double(gains_dB(selectedIdx + 1));
    metrics.BeamGainGap_dB = double(metrics.BestBeamGain_dB - metrics.SelectedBeamGain_dB);
    metrics.BeamHit = double(selectedIdx == metrics.BestBeamIndex);
    metrics.TopKBeamHit = double(any(selectedIdx == double(sortedIdx(1:min(3, numel(sortedIdx)))) - 1));
end
end
