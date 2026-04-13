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

sinrLin = best.EffectiveSINR;
if ~isfinite(sinrLin)
    sinrLin = 0;
end
if sinrLin <= 0
    sinr_dB = -inf;
else
    sinr_dB = 10 * log10(sinrLin);
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
    rsrp_dB = channelGain_dB;
    rsrpSource = "channel_estimate_gain_proxy";
end
cqiFeedback = sixgr.link.resolveWidebandCQI(struct("WidebandSINR_dB", sinr_dB), cfg, direction);
cqi = double(cqiFeedback.WidebandCQI);

csi = struct();
csi.CQI = localReportedScalar(cqi, reportCQI);
csi.RI = localReportedScalar(best.Rank, reportRI);
csi.PMI = localReportedScalar(best.PMI, reportPMI);
csi.CRI = localReportedScalar(criInfo.CRI, reportCRI);
csi.SINR_dB = double(sinr_dB);
csi.Direction = char(direction);
csi.RSRP_dB = double(rsrp_dB);
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
csi.SelectedCRIMetric_dB = double(criInfo.Metric_dB);
csi.ReportCQI = reportCQI;
csi.ReportPMI = reportPMI;
csi.ReportRI = reportRI;
csi.ReportCRI = reportCRI;

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
info.SelectedPMI = double(best.PMI);
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
info.Hints = struct( ...
    "AddCSIRSBasedCQI", true, ...
    "AddPMISelection", true, ...
    "AddRISelection", true, ...
    "AddCRISelection", true);
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
        "EffectiveSINR", 0, ...
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
    "EffectiveSINR", 0, ...
    "NumCandidates", 0);

for rankIdx = 1:maxRank
    if codebookMode == "noncodebook"
        W = localDominantRightSingularVectors(Hwb, rankIdx);
        metric = localCapacityMetric(Hwb, W, nVar);
        effSinr = localEffectiveSINR(Hwb, W, nVar);
        candidate = struct( ...
            "Rank", double(rankIdx), ...
            "PMI", -1, ...
            "PMIType", "noncodebook", ...
            "W", W, ...
            "BeamIndices", 1:rankIdx, ...
            "Metric", metric, ...
            "EffectiveSINR", effSinr, ...
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
        [winner, metric, effSinr] = localBestCandidate(Hwb, candidates, nVar);
        candidate = struct( ...
            "Rank", double(rankIdx), ...
            "PMI", double(winner.PMI), ...
            "PMIType", char(winner.PMIType), ...
            "W", winner.W, ...
            "BeamIndices", double(winner.BeamIndices), ...
            "Metric", double(metric), ...
            "EffectiveSINR", double(effSinr), ...
            "NumCandidates", double(numel(candidates)), ...
            "Candidate", winner, ...
            "CodebookInfo", cbInfo);
    end
    if candidate.Metric > best.Metric + 1e-9
        best = candidate;
    end
end
end

function [winner, bestMetric, effSinr] = localBestCandidate(Hwb, candidates, nVar)
winner = candidates(1);
bestMetric = -inf;
effSinr = 0;
for i = 1:numel(candidates)
    W = candidates(i).W;
    metric = localCapacityMetric(Hwb, W, nVar);
    if metric > bestMetric
        bestMetric = metric;
        effSinr = localEffectiveSINR(Hwb, W, nVar);
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
rankW = max(1, size(W, 2));
snrScale = 1 / max(double(nVar), eps);
Heff = Hwb * W;
s = svd(double(Heff), "econ");
metric = sum(log2(1 + (abs(s).^2) * snrScale / rankW), "omitnan");
end

function effSinr = localEffectiveSINR(Hwb, W, nVar)
if isempty(Hwb) || isempty(W)
    effSinr = 0;
    return;
end
rankW = max(1, size(W, 2));
powerGain = real(trace((Hwb * W) * (Hwb * W)')) / rankW;
if ~isfinite(powerGain) || powerGain < 0
    powerGain = 0;
end
effSinr = powerGain / max(double(nVar), eps);
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
