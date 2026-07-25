function [csi, info] = CSI_Feedback(hEst, nVar, cfg, varargin)
%CSI_Feedback Compute wideband CQI/PMI/RI/CRI from an actual channel estimate.

ip = inputParser;
ip.addParameter("Method", "wideband_codebook", @(s) ischar(s) || isstring(s));
ip.addParameter("MaxRank", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
ip.addParameter("WidebandOnly", true, @(x) islogical(x) && isscalar(x));
ip.addParameter("Direction", "DL", @(s) ischar(s) || isstring(s));
ip.addParameter("ReceivedGrid", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("ReferenceIndices", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("ReferenceSymbols", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("PostEqSINR_dB", NaN, @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("PostEqSINRSource", "", @(s) ischar(s) || isstring(s));
ip.addParameter("PostEqSINRValueRole", "", @(s) ischar(s) || isstring(s));
ip.addParameter("PostEqSINRValueStatus", "", @(s) ischar(s) || isstring(s));
ip.addParameter("PostEqSINRNAReason", "", @(s) ischar(s) || isstring(s));
ip.parse(varargin{:});
opt = ip.Results;

method = lower(string(opt.Method));
direction = localNormalizeDirection(opt.Direction);
Hwb = localWidebandChannelMatrix(hEst, cfg);
nVar = double(nVar);
if ~isfinite(nVar) || nVar < 0
    nVar = 0;
end

[numRxAnt, numTxPorts] = size(Hwb);
if isempty(Hwb)
    numRxAnt = 1;
    numTxPorts = 1;
end

maxRank = opt.MaxRank;
if isempty(maxRank)
    cfgMaxRank = double(sixgr.util.structGet(cfg, "phy.csi.maxRank", min(numRxAnt, numTxPorts)));
    maxRank = max(1, min([cfgMaxRank, numRxAnt, numTxPorts]));
else
    maxRank = max(1, min([double(maxRank), numRxAnt, numTxPorts]));
end
svdRank = localEstimateRIFromSVD(hEst, cfg, maxRank);

reportCQI = logical(sixgr.util.structGet(cfg, "phy.csi.reportCQI", true));
reportPMI = logical(sixgr.util.structGet(cfg, "phy.csi.reportPMI", true));
reportRI = logical(sixgr.util.structGet(cfg, "phy.csi.reportRI", true));
reportCRI = logical(sixgr.util.structGet(cfg, "phy.csi.reportCRI", false));
csiMode = string(sixgr.util.structGet(cfg, "phy.csi.channelStateInformationMode", ...
    sixgr.util.structGet(cfg, "phy.csi.feedbackMode", "PMI+CQI+RI")));
codebookMode = string(sixgr.util.structGet(cfg, "phy.csi.pmiCodebookMode", "type1_su_mimo"));
codebookType = string(sixgr.util.structGet(cfg, "phy.csi.codebookType", localPMIType(codebookMode)));

best = localSelectBestWidebandPrecoder(Hwb, nVar, cfg, maxRank, codebookMode);
criInfo = localSelectCRI(Hwb, nVar, cfg);

modelSinrLin = double(best.EffectiveSINR);
if ~isfinite(modelSinrLin) || modelSinrLin < 0
    modelSinrLin = 0;
end
if modelSinrLin <= 0
    modelSinr_dB = -inf;
else
    modelSinr_dB = 10 * log10(modelSinrLin);
end

[measuredSINR_dB, measuredSINRSource, measuredSINRStatus, pilotNMSE_dB, perRBSINR_dB] = ...
    localMeasureReferenceSINR(hEst, nVar, opt.ReceivedGrid, opt.ReferenceIndices, opt.ReferenceSymbols, cfg);
[postEqSINR_dB, postEqSINRSource, postEqSINRRole, postEqSINRStatus, postEqSINRReason] = ...
    localResolveSchedulerEligiblePostEqSINR(opt);
if isfinite(postEqSINR_dB)
    sinr_dB = double(postEqSINR_dB);
    sinrSource = string(postEqSINRSource);
    sinrRole = string(postEqSINRRole);
    sinrStatus = string(postEqSINRStatus);
    sinrReason = string(postEqSINRReason);
elseif isfinite(measuredSINR_dB)
    sinr_dB = double(measuredSINR_dB);
    sinrSource = "measured_csi_rs_sinr";
    sinrRole = "measured_csi_rs_cqi_input";
    if contains(lower(string(measuredSINRStatus)), "dynamic_range_limited")
        sinrStatus = "OK_dynamic_range_limited";
    else
        sinrStatus = "OK";
    end
    sinrReason = "";
else
    sinr_dB = NaN;
    sinrSource = "reference_signal_sinr_unavailable";
    sinrRole = "unavailable";
    sinrStatus = "unavailable";
    sinrReason = "reference_signal_sinr_not_available_from_receiver_evidence";
end
if ~isfinite(measuredSINR_dB)
    measuredSINRStatus = "unavailable_missing_reference_signal_measurement";
end

hPow = mean(abs(Hwb(:)).^2, "omitnan");
if isempty(hPow) || ~isfinite(hPow) || hPow <= 0
    hPow = 0;
end
channelGain_dB = 10 * log10(max(hPow, eps));
[referencePower, rsrpSource] = localMeasureReferencePower(opt.ReceivedGrid, opt.ReferenceIndices, opt.ReferenceSymbols);
if isfinite(referencePower) && referencePower > 0
    rsrp_dB = 10 * log10(max(referencePower, eps));
else
    rsrp_dB = NaN;
    rsrpSource = "measurement_unavailable";
end
[rssiPower, rssiNRB, rssiSource, rssiStatus] = localMeasureRSSI(opt.ReceivedGrid, opt.ReferenceIndices);
if isfinite(rssiPower) && rssiPower > 0
    rssi_dB = 10 * log10(max(rssiPower, eps));
else
    rssi_dB = NaN;
end
if isfinite(referencePower) && referencePower > 0 && isfinite(rssiPower) && rssiPower > 0 && ...
        isfinite(rssiNRB) && rssiNRB > 0
    rsrq_dB = 10 * log10(max(double(rssiNRB) * referencePower / max(rssiPower, eps), eps));
    rsrqSource = "ts38215_n_times_rsrp_over_rssi";
    rsrqStatus = "OK";
else
    rsrq_dB = NaN;
    rsrqSource = "measurement_unavailable";
    rsrqStatus = "unavailable_missing_rsrp_or_rssi";
end
if isfinite(sinr_dB)
    cqiInput = struct( ...
        "WidebandSINR_dB", sinr_dB, ...
        "SINRSource", char(sinrSource), ...
        "SINRValueRole", char(sinrRole), ...
        "SINRValueStatus", char(sinrStatus));
    cqiFeedback = sixgr.link.resolveWidebandCQI(cqiInput, cfg, direction);
    cqi = double(sixgr.util.normalizeReportedCQI(sixgr.util.structGet(cqiFeedback, "WidebandCQI", NaN)));
    cqiFeedback.WidebandCQI = double(cqi);
else
    cqiFeedback = struct( ...
        "WidebandCQI", NaN, ...
        "EffectiveSINR_dB", NaN, ...
        "EffectiveSINRMethod", "measurement_required_unavailable");
    cqi = NaN;
end
subband = localComputeSubbandCSI(hEst, nVar, cfg, direction, []);

csi = struct();
csi.CQI = localReportedScalar(cqi, reportCQI);
csi.RI = localReportedScalar(best.Rank, reportRI);
csi.PMI = localReportedScalar(best.PMI, reportPMI);
csi.CRI = localReportedScalar(criInfo.CRI, reportCRI);
csi.RankSelectionMethod = "wideband_codebook_post_equalization_mi";
csi.RankSelectionObjective = "sum_log2_one_plus_layer_sinr";
csi.SVDRankEstimate = double(svdRank);
csi.SINR_dB = double(sinr_dB);
csi.Direction = char(direction);
csi.RSRP_dB = double(rsrp_dB);
csi.RSSI_dB = double(rssi_dB);
csi.RSRQ_dB = double(rsrq_dB);
csi.RSSI_N_RB = double(rssiNRB);
csi.ChannelGain_dB = double(channelGain_dB);
csi.ChannelStateInformationMode = char(csiMode);
csi.PMICodebookMode = char(codebookMode);
csi.CodebookType = char(codebookType);
csi.PMIType = char(best.PMIType);
csi.PMICandidateCount = double(best.NumCandidates);
csi.CRICandidateCount = double(criInfo.NumCandidates);
csi.NumRxAnt = double(numRxAnt);
csi.NumTxPorts = double(numTxPorts);
csi.SelectedBeamIndices = double(best.BeamIndices);
csi.SelectedPrecoder = best.W;
csi.SelectedLayerSINR_dB = double(best.LayerSINR_dB);
csi.SelectedMutualInformation_bpcu = double(best.Capacity_bpcu);
csi.SelectedCRIMetric_dB = double(criInfo.Metric_dB);
csi.ReportCQI = reportCQI;
csi.ReportPMI = reportPMI;
csi.ReportRI = reportRI;
csi.ReportCRI = reportCRI;
csi.SubbandCQI = double(subband.CQI);
csi.SubbandCQIVector = char(subband.CQIVector);
csi.SubbandPMI = double(subband.PMI);
csi.SubbandPMIVector = char(subband.PMIVector);
csi.SubbandSINR_dB = char(subband.SINRVector);
csi.SubbandSizePRB = double(subband.SubbandSizePRB);
csi.SubbandCount = double(subband.SubbandCount);
csi.WidebandOrSubband = char(subband.ReportMode);
csi.SubbandCQISource = char(subband.Source);
csi.SubbandCQIValueStatus = char(subband.ValueStatus);

payload = sixgr.phy.dl.packCSIFeedbackPayload(csi, cfg, ...
    "Candidate", sixgr.util.structGet(best, "Candidate", struct()), ...
    "CodebookInfo", sixgr.util.structGet(best, "CodebookInfo", struct()), ...
    "MaxRank", maxRank);
csi.CSIPayloadBits = payload.Bits;
csi.CSIPayloadBitLength = double(payload.BitLength);
csi.CSIPayloadHex = char(string(payload.Hex));
csi.CSIPayloadMode = char(string(payload.Mode));
csi.CSIPayloadStandardProfile = char(string(payload.StandardProfile));
csi.CSIPayloadCRCEnabled = logical(payload.CRCEnabled);
csi.CSIPayloadFieldCount = double(payload.FieldCount);
csi.CSIPayloadFieldLayout = payload.FieldLayout;
csi.RSRPSource = char(rsrpSource);
csi.RSSISource = char(rssiSource);
csi.RSSIValueStatus = char(rssiStatus);
csi.RSRQSource = char(rsrqSource);
csi.RSRQValueStatus = char(rsrqStatus);
csi.SINRSource = char(sinrSource);
csi.SINRValueRole = char(sinrRole);
csi.SINRValueStatus = char(sinrStatus);
csi.SINRNAReason = char(sinrReason);
csi.PostEqSINR_dB = double(postEqSINR_dB);
csi.PostEqSINRSource = char(postEqSINRSource);
csi.PostEqSINRValueRole = char(postEqSINRRole);
csi.PostEqSINRValueStatus = char(postEqSINRStatus);
csi.PostEqSINRNAReason = char(postEqSINRReason);
csi.PilotSINR_dB = double(measuredSINR_dB);
csi.PilotSINRSource = char(string(measuredSINRSource));
csi.PilotSINRValueStatus = char(string(measuredSINRStatus));
csi.PilotSINRValueRole = "diagnostic_reference_signal_quality_not_for_scheduling";
csi.ModelEffectiveSINR_dB = double(modelSinr_dB);
csi.ReferenceMeasuredSINR_dB = double(measuredSINR_dB);
csi.ReferencePilotNMSE_dB = double(pilotNMSE_dB);
csi.ReferenceSINRValueStatus = char(string(measuredSINRStatus));
csi.CQIEffectiveSINR_dB = double(sixgr.util.structGet(cqiFeedback, "EffectiveSINR_dB", NaN));
csi.CQIEffectiveSINRMethod = char(string(sixgr.util.structGet(cqiFeedback, "EffectiveSINRMethod", "")));

info = struct();
info.Method = char(method);
info.EngineUsed = "wideband_codebook";
info.NoiseVar = double(nVar);
info.ChannelPower = double(hPow);
info.WidebandOnly = logical(opt.WidebandOnly);
info.WidebandChannel = Hwb;
info.SelectedMetric = double(best.Metric);
info.SelectedEffectiveSINR = double(best.EffectiveSINR);
info.SelectedRank = double(best.Rank);
info.SVDRankEstimate = double(svdRank);
info.RankSelectionMethod = "wideband_codebook_post_equalization_mi";
info.RankSelectionObjective = "sum_log2_one_plus_layer_sinr";
info.SelectedPMI = double(best.PMI);
info.SelectedLayerSINR_dB = double(best.LayerSINR_dB);
info.SelectedCRI = double(criInfo.CRI);
info.Config = struct( ...
    "TargetBLER", double(localResolveTargetBLER(cfg, direction)), ...
    "PMICodebookMode", char(codebookMode), ...
    "CodebookType", char(codebookType), ...
    "ChannelStateInformationMode", char(csiMode));
info.SelectedCandidate = sixgr.util.structGet(best, "Candidate", struct());
info.CodebookInfo = sixgr.util.structGet(best, "CodebookInfo", struct());
info.Payload = payload;
info.ReferencePower = double(referencePower);
info.RSRPSource = char(rsrpSource);
info.RSSIPower = double(rssiPower);
info.RSSI_N_RB = double(rssiNRB);
info.RSSISource = char(rssiSource);
info.RSSIStatus = char(rssiStatus);
info.RSRQ_dB = double(rsrq_dB);
info.RSRQSource = char(rsrqSource);
info.RSRQStatus = char(rsrqStatus);
info.ModelEffectiveSINR_dB = double(modelSinr_dB);
info.MeasuredReferenceSINR_dB = double(measuredSINR_dB);
info.MeasuredReferenceSINRSource = char(string(measuredSINRSource));
info.MeasuredReferenceSINRStatus = char(string(measuredSINRStatus));
info.PostEqSINR_dB = double(postEqSINR_dB);
info.PostEqSINRSource = char(postEqSINRSource);
info.PostEqSINRValueRole = char(postEqSINRRole);
info.PostEqSINRValueStatus = char(postEqSINRStatus);
info.PostEqSINRNAReason = char(postEqSINRReason);
info.ReferencePilotNMSE_dB = double(pilotNMSE_dB);
info.PerRBSINR_dB = double(perRBSINR_dB);
info.CQIFeedback = cqiFeedback;
info.SubbandCSI = subband;
info.Hints = struct( ...
    "AddCSIRSBasedCQI", true, ...
    "AddPMISelection", true, ...
    "AddRISelection", true, ...
    "AddCRISelection", true);
end

function ri = localEstimateRIFromSVD(hEst, cfg, maxRank)
ri = NaN;
if nargin < 3 || isempty(maxRank) || ~(isfinite(double(maxRank)) && double(maxRank) >= 1)
    maxRank = double(sixgr.util.structGet(cfg, "phy.csi.maxRank", 1));
end
maxRank = max(1, round(double(maxRank)));
if isempty(hEst)
    return;
end
Hwb = localWidebandChannelMatrix(hEst, cfg);
if isempty(Hwb)
    return;
end
sv = svd(double(Hwb));
sv = sv(isfinite(sv) & sv > 0);
if isempty(sv)
    return;
end
threshold_dB = double(sixgr.util.structGet(cfg, "phy.mimo.rankSelectionSVGap_dB", ...
    sixgr.util.structGet(cfg, "phy.csi.rankSelectionSVGap_dB", 3)));
if ~(isfinite(threshold_dB) && threshold_dB >= 0)
    threshold_dB = 3;
end
sv_dB = 20 .* log10(sv ./ max(sv));
ri = sum(sv_dB >= -threshold_dB);
ri = max(1, min(maxRank, ri));
end

function [value, source, role, status, reason] = localResolveSchedulerEligiblePostEqSINR(opt)
value = double(opt.PostEqSINR_dB);
source = string(opt.PostEqSINRSource);
role = string(opt.PostEqSINRValueRole);
status = string(opt.PostEqSINRValueStatus);
reason = string(opt.PostEqSINRNAReason);
if strlength(strtrim(source)) == 0
    source = "post_equalization_sinr_from_equalizer_channel_estimate";
end
if strlength(strtrim(role)) == 0
    role = "measured_post_equalization_scheduling_input";
end
if strlength(strtrim(status)) == 0
    status = "unavailable";
end
if ~(isscalar(value) && isfinite(value)) || ~localSINRProvenanceIsSchedulerEligible(source, role)
    value = NaN;
    if status == "OK"
        status = "rejected";
    elseif status ~= "failed"
        status = "unavailable";
    end
    if strlength(strtrim(reason)) == 0
        reason = "post_equalization_sinr_missing_or_not_scheduler_eligible";
    end
    return;
end
status = "OK";
reason = "";
end

function tf = localSINRProvenanceIsSchedulerEligible(source, role)
token = lower(strjoin([string(source), string(role)], " "));
words = string(regexp(char(token), '[a-z0-9]+', 'match'));
blocked = ["receiverhest", "receiver_hest", "pilot", ...
    "reference_signal", "evm_proxy", "proxy", "fallback", "configured", "sweep"];
tf = contains(token, "post_equalization") && ~any(words == "hest") && ~any(contains(token, blocked));
end

function direction = localNormalizeDirection(rawDirection)
direction = upper(strtrim(string(rawDirection)));
if strlength(direction) == 0
    direction = "DL";
end
if ~ismember(direction, ["DL", "UL"])
    error("sixgr:phy:dl:CSI_Feedback:InvalidDirection", ...
        "CSI feedback direction must be DL or UL, got '%s'.", char(direction));
end
end

function targetBLER = localResolveTargetBLER(cfg, direction)
if direction == "UL"
    targetBLER = double(sixgr.util.structGet(cfg, "phy.pusch.targetBLER", ...
        sixgr.util.structGet(cfg, "phy.csi.targetBLER", 0.1)));
else
    targetBLER = double(sixgr.util.structGet(cfg, "phy.pdsch.targetBLER", ...
        sixgr.util.structGet(cfg, "phy.csi.targetBLER", 0.1)));
end
if ~(isscalar(targetBLER) && isfinite(targetBLER) && targetBLER > 0)
    targetBLER = 0.1;
end
end

function best = localSelectBestWidebandPrecoder(Hwb, nVar, cfg, maxRank, codebookMode)
numTxPorts = size(Hwb, 2);
if isempty(Hwb)
    best = struct( ...
        "Rank", 1, ...
        "PMI", 0, ...
        "PMIType", char(localPMIType(codebookMode)), ...
        "W", eye(1), ...
        "BeamIndices", 1, ...
        "Metric", 0, ...
        "Capacity_bpcu", 0, ...
        "EffectiveSINR", 0, ...
        "LayerSINR_dB", NaN, ...
        "NumCandidates", 1);
    return;
end

best = struct( ...
    "Rank", 1, ...
    "PMI", 0, ...
    "PMIType", char(localPMIType(codebookMode)), ...
    "W", eye(numTxPorts, 1), ...
    "BeamIndices", 1, ...
    "Metric", -inf, ...
    "Capacity_bpcu", 0, ...
    "EffectiveSINR", 0, ...
    "LayerSINR_dB", NaN, ...
    "NumCandidates", 0);

for rankIdx = 1:maxRank
    if codebookMode == "noncodebook"
        W = localDominantRightSingularVectors(Hwb, rankIdx);
        layerSINR = localLayerMMSESINR(Hwb, W, nVar);
        metric = localCapacityMetricFromSINR(layerSINR);
        effSinr = localEffectiveSINRFromSINR(layerSINR);
        candidate = struct( ...
            "Rank", double(rankIdx), ...
            "PMI", -1, ...
            "PMIType", "noncodebook", ...
            "W", W, ...
            "BeamIndices", 1:rankIdx, ...
            "Metric", metric, ...
            "Capacity_bpcu", metric, ...
            "EffectiveSINR", effSinr, ...
            "LayerSINR_dB", localSINRToDb(layerSINR), ...
            "NumCandidates", 1, ...
            "Candidate", struct( ...
                "PMI", -1, ...
                "BeamIndices", 1:rankIdx, ...
                "PMIType", "noncodebook", ...
                "CodebookMode", "noncodebook", ...
                "NumPorts", double(numTxPorts), ...
                "NumLayers", double(rankIdx), ...
                "NumBeams", double(numTxPorts), ...
                "StartBeamIndex", 0, ...
                "Stride", 1, ...
                "StrideIndex", 0, ...
                "PhaseVariantIndex", 0, ...
                "PhasePattern", ones(1, rankIdx)), ...
            "CodebookInfo", struct( ...
                "Mode", "noncodebook", ...
                "PMIType", "noncodebook", ...
                "NumBeams", double(numTxPorts), ...
                "NumCandidates", 1, ...
                "NumPorts", double(numTxPorts), ...
                "NumLayers", double(rankIdx), ...
                "StrideSet", 1, ...
                "NumPhaseVariants", 1));
    else
        [candidates, cbInfo] = sixgr.phy.dl.pmiCodebookCandidates(cfg, rankIdx, numTxPorts, "Mode", codebookMode);
        [winner, metric, effSinr, layerSINR_dB] = localBestCandidate(Hwb, candidates, nVar);
        candidate = struct( ...
            "Rank", double(rankIdx), ...
            "PMI", double(winner.PMI), ...
            "PMIType", char(winner.PMIType), ...
            "W", winner.W, ...
            "BeamIndices", double(winner.BeamIndices), ...
            "Metric", double(metric), ...
            "Capacity_bpcu", double(metric), ...
            "EffectiveSINR", double(effSinr), ...
            "LayerSINR_dB", double(layerSINR_dB), ...
            "NumCandidates", double(numel(candidates)), ...
            "Candidate", winner, ...
            "CodebookInfo", cbInfo);
    end
    if ~localRankCandidateAllowed(candidate, Hwb, cfg)
        continue;
    end
    if candidate.Metric > best.Metric + 1e-9
        best = candidate;
    end
end
end

function tf = localRankCandidateAllowed(candidate, Hwb, cfg)
rankIdx = max(1, round(double(sixgr.util.structGet(candidate, "Rank", 1))));
tf = true;
if rankIdx <= 1
    return;
end

rankThreshold = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.rankThreshold", ...
    sixgr.util.structGet(cfg, "phy.mimo.svRankThreshold", NaN)));
if isfinite(rankThreshold) && rankThreshold > 0
    sv = svd(double(Hwb));
    sv = sv(isfinite(sv) & sv > 0);
    if numel(sv) < rankIdx || double(sv(rankIdx)) < double(rankThreshold) * max(double(sv(1)), eps)
        tf = false;
        return;
    end
end

minSINR_dB = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.minSINRForRank2_dB", NaN));
if isfinite(minSINR_dB)
    layerSINR_dB = double(sixgr.util.structGet(candidate, "LayerSINR_dB", []));
    layerSINR_dB = layerSINR_dB(:).';
    if numel(layerSINR_dB) < rankIdx || any(~isfinite(layerSINR_dB(1:rankIdx))) || ...
            any(layerSINR_dB(1:rankIdx) < double(minSINR_dB))
        tf = false;
    end
end
end

function [winner, bestMetric, effSinr, layerSINR_dB] = localBestCandidate(Hwb, candidates, nVar)
winner = candidates(1);
bestMetric = -inf;
effSinr = 0;
layerSINR_dB = NaN;
for i = 1:numel(candidates)
    W = candidates(i).W;
    layerSINR = localLayerMMSESINR(Hwb, W, nVar);
    metric = localCapacityMetricFromSINR(layerSINR);
    if metric > bestMetric
        bestMetric = metric;
        effSinr = localEffectiveSINRFromSINR(layerSINR);
        layerSINR_dB = localSINRToDb(layerSINR);
        winner = candidates(i);
    end
end
end

function criInfo = localSelectCRI(Hwb, nVar, cfg)
numTxPorts = size(Hwb, 2);
if isempty(Hwb)
    criInfo = struct("CRI", 0, "NumCandidates", 1, "Metric_dB", -inf);
    return;
end

numCandidates = double(sixgr.util.structGet(cfg, "phy.csi.numResourceCandidates", []));
if isempty(numCandidates) || ~isfinite(numCandidates) || numCandidates < 1
    numCandidates = double(sixgr.util.structGet(cfg, "phy.csirs.numResources", []));
end
if isempty(numCandidates) || ~isfinite(numCandidates) || numCandidates < 1
    numCandidates = double(sixgr.util.structGet(cfg, "phy.beamManagement.trpCount", 1));
end
numCandidates = max(1, round(numCandidates));

codebook = localOversampledDFTCodebook(numTxPorts, max(numCandidates, numTxPorts));
metrics = zeros(numCandidates, 1);
for i = 1:numCandidates
    w = codebook(:, i);
    metrics(i) = localEffectiveSINR(Hwb, w, nVar);
end
[bestMetric, idx] = max(metrics);
criInfo = struct( ...
    "CRI", double(idx - 1), ...
    "NumCandidates", double(numCandidates), ...
    "Metric_dB", double(10 * log10(max(bestMetric, eps))));
end

function metric = localCapacityMetric(Hwb, W, nVar)
if isempty(Hwb) || isempty(W)
    metric = -inf;
    return;
end
sinrs = localLayerMMSESINR(Hwb, W, nVar);
metric = localCapacityMetricFromSINR(sinrs);
end

function metric = localCapacityMetricFromSINR(sinrs)
if isempty(sinrs)
    metric = -inf;
    return;
end
metric = sum(log2(1 + max(sinrs, 0)), "omitnan");
end

function effSinr = localEffectiveSINR(Hwb, W, nVar)
if isempty(Hwb) || isempty(W)
    effSinr = 0;
    return;
end
sinrs = localLayerMMSESINR(Hwb, W, nVar);
effSinr = localEffectiveSINRFromSINR(sinrs);
end

function effSinr = localEffectiveSINRFromSINR(sinrs)
if isempty(sinrs)
    effSinr = 0;
    return;
end
sinrs = max(double(sinrs(:)), eps);
effSinr = exp(mean(log(sinrs), "omitnan"));
end

function sinr_dB = localSINRToDb(sinrLin)
sinrLin = double(sinrLin(:).');
sinr_dB = nan(size(sinrLin));
mask = isfinite(sinrLin) & sinrLin > 0;
sinr_dB(mask) = 10 .* log10(max(sinrLin(mask), eps));
end

function sinrs = localLayerMMSESINR(Hwb, W, nVar)
H = double(Hwb);
W = double(W);
HW = H * W;
[nRx, rankW] = size(HW);
nVarSafe = max(double(nVar), 1e-12 * (norm(H, 'fro')^2 / max(numel(H), 1) + eps));
sinrs = zeros(1, rankW);
for l = 1:rankW
    h = HW(:, l);
    interferers = HW;
    interferers(:, l) = [];
    R = eye(nRx) + (interferers * interferers') / nVarSafe;
    sinrs(l) = real(h' * (R \ h)) / nVarSafe;
end
end

function W = localDominantRightSingularVectors(Hwb, rankIdx)
[~, ~, V] = svd(double(Hwb), "econ");
rankIdx = max(1, min(rankIdx, size(V, 2)));
W = V(:, 1:rankIdx);
W = localNormalizeColumns(W);
end

function Hwb = localWidebandChannelMatrix(Hest, cfg)
Hwb = [];
if isempty(Hest)
    return;
end
if nargin < 2
    cfg = struct();
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
    sixgr.util.structGet(cfg, "phy.pdsch.nLayers", ...
    sixgr.util.structGet(cfg, "phy.pusch.nLayers", 1))));
if ~(isscalar(expectedRx) && isfinite(expectedRx) && expectedRx >= 1)
    expectedRx = 1;
end
if ~(isscalar(expectedTx) && isfinite(expectedTx) && expectedTx >= 1)
    expectedTx = 1;
end
expectedRx = max(1, round(expectedRx));
expectedTx = max(1, round(expectedTx));
end

function subband = localComputeSubbandCSI(Hest, nVar, cfg, direction, perRBSINR_dB)
subband = struct( ...
    "CQI", [], ...
    "PMI", [], ...
    "SINR_dB", [], ...
    "CQIVector", "", ...
    "PMIVector", "", ...
    "SINRVector", "", ...
    "SubbandSizePRB", NaN, ...
    "SubbandCount", 0, ...
    "ReportMode", "wideband_only", ...
    "Source", "subband_cqi_not_requested", ...
    "ValueStatus", "NOT_AVAILABLE");

reportSubband = logical(sixgr.util.structGet(cfg, "phy.csi.reportSubbandCQI", ...
    sixgr.util.structGet(cfg, "phy.csi.subbandCQIEnabled", ...
    sixgr.util.structGet(cfg, "csi_acquisition_and_reporting.subband_cqi_enable", false))));
reportMode = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.csi.reportingMode", ...
    sixgr.util.structGet(cfg, "csi_acquisition_and_reporting.reporting_mode", "wideband")))));
reportSubband = reportSubband || reportMode == "subband";
if ~reportSubband
    return;
end

perRB = double(perRBSINR_dB(:));
perRB = perRB(isfinite(perRB));
if isempty(perRB)
    perRB = localPerRBSINRFromChannelEstimate(Hest, nVar);
end
if isempty(perRB)
    subband.ReportMode = "subband";
    subband.Source = "subband_cqi_requested_no_resource_sinr";
    subband.ValueStatus = "NOT_AVAILABLE";
    return;
end

numRB = numel(perRB);
subbandSize = localResolveSubbandSizePRB(cfg, numRB);
numSubbands = ceil(double(numRB) / double(subbandSize));
sinrVals = nan(numSubbands, 1);
cqiVals = nan(numSubbands, 1);
pmiVals = nan(numSubbands, 1);
for sb = 1:numSubbands
    rb0 = (sb - 1) * subbandSize + 1;
    rb1 = min(numRB, sb * subbandSize);
    vals = perRB(rb0:rb1);
    vals = vals(isfinite(vals));
    if isempty(vals)
        continue;
    end
    lin = 10 .^ (vals(:) / 10);
    effSinr = 10 * log10(max(mean(lin, "omitnan"), eps));
    sinrVals(sb) = effSinr;
    cqiFb = sixgr.link.resolveWidebandCQI(struct("WidebandSINR_dB", effSinr), cfg, direction);
    cqiVals(sb) = double(sixgr.util.normalizeReportedCQI(sixgr.util.structGet(cqiFb, "WidebandCQI", NaN)));
    Hsb = localSubbandWidebandChannelMatrix(Hest, rb0, rb1);
    if ~isempty(Hsb)
        maxRank = max(1, round(double(sixgr.util.structGet(cfg, "phy.csi.maxRank", min(size(Hsb))))));
        codebookMode = string(sixgr.util.structGet(cfg, "phy.csi.pmiCodebookMode", "type1_su_mimo"));
        bestSB = localSelectBestWidebandPrecoder(Hsb, nVar, cfg, maxRank, codebookMode);
        pmiVals(sb) = double(sixgr.util.structGet(bestSB, "PMI", NaN));
    end
end

valid = isfinite(sinrVals) & isfinite(cqiVals);
if ~any(valid)
    subband.ReportMode = "subband";
    subband.Source = "subband_cqi_requested_no_valid_bins";
    subband.ValueStatus = "NOT_AVAILABLE";
    subband.SubbandSizePRB = double(subbandSize);
    subband.SubbandCount = double(numSubbands);
    return;
end

subband.CQI = cqiVals;
subband.PMI = pmiVals;
subband.SINR_dB = sinrVals;
subband.CQIVector = localVectorToToken(cqiVals, "%.0f");
subband.PMIVector = localVectorToToken(pmiVals, "%.0f");
subband.SINRVector = localVectorToToken(sinrVals, "%.3f");
subband.SubbandSizePRB = double(subbandSize);
subband.SubbandCount = double(numSubbands);
subband.ReportMode = "wideband_and_subband";
subband.Source = "ts38214_subband_cqi_from_runtime_channel_sinr";
subband.ValueStatus = "OK";
end

function Hsb = localSubbandWidebandChannelMatrix(Hest, rb0, rb1)
Hsb = [];
if isempty(Hest)
    return;
end
K0 = max(1, (rb0 - 1) * 12 + 1);
K1 = min(size(Hest, 1), rb1 * 12);
if K1 < K0
    return;
end
try
    H = Hest(K0:K1, :, :, :);
    if ndims(H) >= 4
        Hsb = squeeze(mean(mean(H, 1, "omitnan"), 2, "omitnan"));
    elseif ndims(H) == 3
        Hsb = squeeze(mean(H, 1, "omitnan"));
    elseif ismatrix(H)
        Hsb = double(H);
    end
    if isempty(Hsb) || ~ismatrix(Hsb)
        Hsb = [];
    end
catch
    Hsb = [];
end
end

function perRB = localPerRBSINRFromChannelEstimate(Hest, nVar)
perRB = [];
if isempty(Hest)
    return;
end
nVar = double(nVar);
if ~(isscalar(nVar) && isfinite(nVar) && nVar > 0)
    return;
end
nd = ndims(Hest);
if nd >= 4
    K = size(Hest, 1);
    nRB = floor(double(K) / 12);
    if nRB < 1
        return;
    end
    perRB = nan(nRB, 1);
    for rb = 1:nRB
        sc = (rb - 1) * 12 + (1:12);
        vals = abs(double(Hest(sc, :, :, :))).^2;
        vals = vals(isfinite(vals));
        if ~isempty(vals)
            perRB(rb) = 10 * log10(max(mean(vals, "omitnan") / nVar, eps));
        end
    end
elseif nd == 3
    K = size(Hest, 1);
    nRB = floor(double(K) / 12);
    if nRB < 1
        return;
    end
    perRB = nan(nRB, 1);
    for rb = 1:nRB
        re = (rb - 1) * 12 + (1:12);
        vals = abs(double(Hest(re, :, :))).^2;
        vals = vals(isfinite(vals));
        if ~isempty(vals)
            perRB(rb) = 10 * log10(max(mean(vals, "omitnan") / nVar, eps));
        end
    end
end
perRB = perRB(isfinite(perRB));
end

function subbandSize = localResolveSubbandSizePRB(cfg, numRB)
subbandSize = double(sixgr.util.structGet(cfg, "phy.csi.subbandSizePRB", ...
    sixgr.util.structGet(cfg, "phy.csi.subbandSize", NaN)));
if isscalar(subbandSize) && isfinite(subbandSize) && subbandSize >= 1
    subbandSize = max(1, round(subbandSize));
    return;
end
% TS 38.214 defines subband CQI granularity as a function of BWP size.
% Keep the policy config-overridable, but choose the NR-like wide-BWP
% granularity when the scenario did not explicitly select one.
if numRB <= 24
    subbandSize = 4;
elseif numRB <= 72
    subbandSize = 8;
else
    subbandSize = 16;
end
end

function token = localVectorToToken(values, fmt)
values = double(values(:).');
parts = strings(1, numel(values));
for i = 1:numel(values)
    if isfinite(values(i))
        parts(i) = string(sprintf(fmt, values(i)));
    else
        parts(i) = "NaN";
    end
end
token = strjoin(parts, "|");
end

function B = localOversampledDFTCodebook(numTxPorts, numBeams)
n = (0:(numTxPorts-1)).';
m = 0:(numBeams-1);
B = exp(-1j * 2 * pi * (n * m) / max(numBeams, 1));
B = B ./ sqrt(max(numTxPorts, 1));
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
try
    [subcarrier, symbol] = localReferenceSubcarrierAndSymbol(rxGrid, refInd);
catch
    subcarrier = [];
    symbol = [];
end
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
if ~any(scMask)
    return;
end
perSymbolPower = nan(numel(symbol), 1);
for i = 1:numel(symbol)
    symIdx = round(symbol(i));
    vals = abs(double(rxGrid(scMask, symIdx, :))).^2;
    vals = vals(isfinite(vals));
    if isempty(vals)
        continue;
    end
    perSymbolPower(i) = sum(vals, "omitnan");
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
    referenceMetrics = sixgr.phy.rx.referenceSignalMetrics( ...
        rxGrid, Hest, refInd, refSym, ...
        "NoiseVariance", nVar, ...
        "ContextLabel", "CSI_Feedback");
catch ME
    status = "reference_reconstruction_failed:" + string(ME.identifier);
    return;
end
perRBSINR_dB = localPerRBReferenceSINR(referenceMetrics);
maxTrustedSINR = localMaxTrustedReferenceSINR(cfg);
if isfinite(maxTrustedSINR) && ~isempty(perRBSINR_dB)
    perRBSINR_dB = min(double(perRBSINR_dB), double(maxTrustedSINR));
end

signalPowLin = double(referenceMetrics.SignalPower);
noisePowLin = double(referenceMetrics.EffectiveDisturbancePower);
if isfinite(signalPowLin) && signalPowLin > 0 && isfinite(noisePowLin) && noisePowLin > 0
    sinr_dB = 10 * log10(signalPowLin / noisePowLin);
    source = "receiver_hest_reference_signal_measurement";
    status = "OK";
    if isfinite(maxTrustedSINR) && sinr_dB > maxTrustedSINR
        sinr_dB = double(maxTrustedSINR);
        status = "OK_dynamic_range_limited";
    end
end
pilotNMSE_dB = double(referenceMetrics.NMSEdB);

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

function perRBSINR_dB = localPerRBReferenceSINR(referenceMetrics)
perRBSINR_dB = [];
if ~(isstruct(referenceMetrics) && ...
        isfield(referenceMetrics, "SubcarrierIndices"))
    return;
end
subcarrier = double(referenceMetrics.SubcarrierIndices(:));
signalPow = double(referenceMetrics.PerRESignalPower(:));
noisePow = double(referenceMetrics.PerREEffectiveDisturbancePower(:));
valid = isfinite(subcarrier) & isfinite(signalPow) & signalPow > 0 ...
    & isfinite(noisePow) & noisePow > 0;
if ~any(valid)
    return;
end
subcarrier = subcarrier(valid);
signalPow = signalPow(valid);
noisePow = noisePow(valid);
rbIndex = floor((subcarrier - 1) ./ 12) + 1;
maxRb = max(rbIndex(isfinite(rbIndex)));
if ~(isfinite(maxRb) && maxRb >= 1)
    return;
end
perRBSINR_dB = nan(maxRb, 1);
for rb = 1:maxRb
    mask = rbIndex == rb;
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

function value = localReportedScalar(value, enabled)
if ~enabled
    value = NaN;
else
    value = double(value);
end
end

function tag = localPMIType(codebookMode)
switch lower(string(codebookMode))
    case "type1_su_mimo"
        tag = "type1";
    case "type2_mu_mimo"
        tag = "type2";
    case "etype2_candidate"
        tag = "etype2";
    otherwise
        tag = "noncodebook";
end
end

function W = localNormalizeColumns(W)
for i = 1:size(W, 2)
    nrm = norm(W(:, i));
    if nrm > 0
        W(:, i) = W(:, i) ./ nrm;
    end
end
end
