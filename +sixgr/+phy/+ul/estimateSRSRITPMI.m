function estimate = estimateSRSRITPMI(Hest, nVar, cfg)
%ESTIMATESRSRITPMI Estimate UL RI and TPMI from SRS channel observations.
%
% This helper keeps the estimator explicitly in the SRS / UL sounding path:
%   1. Form PRB-averaged channel observations from the measured Hest grid.
%   2. Derive RI from the transmit-side covariance eigen-structure.
%   3. Score TPMI codebook candidates with an MI-style metric across PRBs.
%
% The exact thresholds and metric family are lab-default implementation
% choices, not 3GPP-mandated constants.

estimate = struct( ...
    "Valid", false, ...
    "RI", NaN, ...
    "TPMI", NaN, ...
    "RISource", "", ...
    "TPMISource", "", ...
    "ConditionNumber_dB", NaN, ...
    "TPMICandidateCount", NaN, ...
    "TPMIMutualInformation", NaN, ...
    "SelectedBeamIndices", [], ...
    "PRBCount", NaN, ...
    "NumTxPorts", NaN, ...
    "NumRxAnt", NaN, ...
    "TransformPrecoding", false, ...
    "TransmissionScheme", "", ...
    "MetricFamily", "mutual_information_lab_default", ...
    "ValueRole", "estimated_lab_default");

if isempty(Hest)
    estimate.RISource = "srs_hest_missing";
    estimate.TPMISource = "srs_hest_missing";
    return;
end

[Hprb, numRxAnt, numTxPorts] = localPRBAveragedChannel(Hest);
estimate.PRBCount = double(size(Hprb, 3));
estimate.NumRxAnt = double(numRxAnt);
estimate.NumTxPorts = double(numTxPorts);
if isempty(Hprb) || numTxPorts < 1 || numRxAnt < 1
    estimate.RISource = "srs_prb_channel_unavailable";
    estimate.TPMISource = "srs_prb_channel_unavailable";
    return;
end

scheme = lower(string(sixgr.util.structGet(cfg, "phy.pusch.transmissionScheme", "nonCodebook")));
transformPrecoding = logical(sixgr.util.structGet(cfg, "phy.pusch.transformPrecoding", false));
estimate.TransformPrecoding = logical(transformPrecoding);
estimate.TransmissionScheme = char(scheme);

[ri, cond_dB] = localEstimateRI(Hprb, cfg);
estimate.RI = double(ri);
estimate.ConditionNumber_dB = double(cond_dB);
estimate.RISource = "ul_srs_covariance_rank_estimator_lab_default";

if scheme ~= "codebook" || transformPrecoding || numTxPorts < 2
    estimate.Valid = isfinite(estimate.RI);
    estimate.TPMISource = "ul_srs_tpmi_not_required_for_noncodebook_or_transform_precoding";
    return;
end

[tpmi, metric, candidateCount, beamIndices] = localEstimateTPMI(Hprb, max(double(nVar), eps), estimate.RI, numTxPorts, transformPrecoding);
estimate.TPMI = double(tpmi);
estimate.TPMICandidateCount = double(candidateCount);
estimate.TPMIMutualInformation = double(metric);
estimate.SelectedBeamIndices = double(beamIndices);
if isfinite(tpmi)
    estimate.TPMISource = "ul_srs_mutual_information_tpmi_estimator_lab_default";
else
    estimate.TPMISource = "ul_srs_tpmi_estimator_unavailable";
end
estimate.Valid = isfinite(estimate.RI) || isfinite(estimate.TPMI);
end

function [Hprb, numRxAnt, numTxPorts] = localPRBAveragedChannel(Hest)
Hprb = [];
numRxAnt = NaN;
numTxPorts = NaN;
if isempty(Hest)
    return;
end

sz = size(Hest);
if ismatrix(Hest)
    Hwide = double(Hest);
    if isvector(Hwide)
        Hwide = reshape(Hwide, numel(Hwide), 1);
    end
    numRxAnt = size(Hwide, 1);
    numTxPorts = size(Hwide, 2);
    Hprb = reshape(Hwide, numRxAnt, numTxPorts, 1);
    return;
end

if ndims(Hest) == 3
    % Single-port estimate often lands here as K x L x NRx.
    Hgrid = double(Hest);
    K = size(Hgrid, 1);
    L = size(Hgrid, 2);
    numRxAnt = size(Hgrid, 3);
    numTxPorts = 1;
    nPRB = max(1, floor(K / 12));
    Hprb = complex(zeros(numRxAnt, numTxPorts, nPRB));
    for prb = 1:nPRB
        sc = (prb - 1) * 12 + (1:12);
        sc = sc(sc <= K);
        slice = Hgrid(sc, 1:L, :);
        Hprb(:, 1, prb) = reshape(mean(slice, [1 2], "omitnan"), [], 1);
    end
    return;
end

% Expected waveform truth shape: K x L x NRx x NPorts
Hgrid = double(Hest);
K = size(Hgrid, 1);
L = size(Hgrid, 2);
numRxAnt = size(Hgrid, 3);
numTxPorts = size(Hgrid, 4);
nPRB = max(1, floor(K / 12));
Hprb = complex(zeros(numRxAnt, numTxPorts, nPRB));
for prb = 1:nPRB
    sc = (prb - 1) * 12 + (1:12);
    sc = sc(sc <= K);
    slice = Hgrid(sc, 1:L, :, :);
    avg = squeeze(mean(slice, [1 2], "omitnan"));
    if isempty(avg)
        continue;
    end
    if isvector(avg)
        avg = reshape(avg, numRxAnt, numTxPorts);
    end
    Hprb(:, :, prb) = avg;
end
end

function [ri, cond_dB] = localEstimateRI(Hprb, cfg)
ri = NaN;
cond_dB = NaN;
numTxPorts = size(Hprb, 2);
if isempty(Hprb) || numTxPorts < 1
    return;
end

Rtx = zeros(numTxPorts, numTxPorts);
validCount = 0;
for prb = 1:size(Hprb, 3)
    H = double(Hprb(:, :, prb));
    if ~all(isfinite(H), "all")
        continue;
    end
    Rtx = Rtx + (H' * H);
    validCount = validCount + 1;
end
if validCount < 1
    return;
end
Rtx = Rtx ./ validCount;
eigvals = sort(real(eig((Rtx + Rtx') / 2)), "descend");
eigvals = eigvals(isfinite(eigvals) & eigvals >= 0);
if isempty(eigvals)
    return;
end
maxEig = max(eigvals);
if maxEig <= 0
    ri = 1;
    cond_dB = 0;
    return;
end
threshold_dB = double(sixgr.util.structGet(cfg, "phy.srs.rankEigenThreshold_dB", 10));
thresholdLin = 10^(-threshold_dB / 10);
ri = max(1, sum(eigvals >= maxEig * thresholdLin));
if numel(eigvals) >= 2 && eigvals(end) > 0
    cond_dB = 10 * log10(maxEig / eigvals(end));
else
    cond_dB = 0;
end
maxRank = double(sixgr.util.structGet(cfg, "phy.pusch.maxRankDefault", ...
    sixgr.util.structGet(cfg, "phy.pusch.numLayers", sixgr.util.structGet(cfg, "phy.pusch.nLayers", numTxPorts))));
if ~(isfinite(maxRank) && maxRank >= 1)
    maxRank = numTxPorts;
end
ri = max(1, min(round(ri), round(maxRank)));
end

function [tpmi, metricBest, candidateCount, beamIndices] = localEstimateTPMI(Hprb, nVar, ri, numTxPorts, transformPrecoding)
tpmi = NaN;
metricBest = NaN;
candidateCount = 0;
beamIndices = [];
if ~(isfinite(ri) && ri >= 1 && numTxPorts >= 2)
    return;
end
if exist("nrPUSCHCodebook", "file") ~= 2
    return;
end

bestMetric = -inf;
bestBeamIndices = [];
missStreak = 0;
for tpmiIdx = 0:255
    [W, candidateBeamIndices] = localPUSCHCodebookCandidate(ri, numTxPorts, tpmiIdx, transformPrecoding);
    if isempty(W)
        missStreak = missStreak + 1;
        if candidateCount > 0 && missStreak >= 32
            break;
        end
        continue;
    end
    missStreak = 0;
    candidateCount = candidateCount + 1;
    metric = localAverageMutualInformation(Hprb, W, nVar);
    if isfinite(metric) && metric > bestMetric
        bestMetric = metric;
        tpmi = double(tpmiIdx);
        bestBeamIndices = candidateBeamIndices;
    end
end

if isfinite(bestMetric)
    metricBest = bestMetric;
    beamIndices = bestBeamIndices;
end
end

function metric = localAverageMutualInformation(Hprb, W, nVar)
metric = NaN;
if isempty(Hprb) || isempty(W)
    return;
end
acc = 0;
count = 0;
for prb = 1:size(Hprb, 3)
    H = double(Hprb(:, :, prb));
    if ~all(isfinite(H), "all")
        continue;
    end
    Heff = H * double(W);
    sval = svd(Heff, "econ") .^ 2;
    acc = acc + sum(log2(1 + sval ./ max(double(nVar), eps)));
    count = count + 1;
end
if count > 0
    metric = acc / count;
end
end

function [W, beamIndices] = localPUSCHCodebookCandidate(ri, numTxPorts, tpmiIdx, transformPrecoding)
W = [];
beamIndices = [];
try
    W = nrPUSCHCodebook(max(1, round(double(ri))), max(1, round(double(numTxPorts))), ...
        round(double(tpmiIdx)), logical(transformPrecoding));
catch
    try
        W = nrPUSCHCodebook(max(1, round(double(ri))), max(1, round(double(numTxPorts))), round(double(tpmiIdx)));
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
