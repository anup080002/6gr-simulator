function estimate = estimateSRSRITPMI(Hest, nVar, cfg)
%ESTIMATESRSRITPMI Estimate UL RI and TPMI from SRS channel observations.
%
% This helper keeps the estimator explicitly in the SRS / UL sounding path:
%   1. Form PRB-averaged channel observations from the measured Hest grid.
%   2. Derive RI from post-equalization mutual information across PRBs
%      and SRS symbols.
%   3. Score TPMI codebook candidates with the same MI objective across PRBs
%      and SRS symbols.

estimate = struct( ...
    "Valid", false, ...
    "RI", NaN, ...
    "TPMI", NaN, ...
    "RISource", "", ...
    "TPMISource", "", ...
    "ConditionNumber_dB", NaN, ...
    "RankMutualInformation", NaN, ...
    "RankCandidateCount", NaN, ...
    "TPMICandidateCount", NaN, ...
    "TPMIMutualInformation", NaN, ...
    "SelectedBeamIndices", [], ...
    "PRBCount", NaN, ...
    "SRSSymbolCount", NaN, ...
    "NumTxPorts", NaN, ...
    "SRSNumTxPorts", NaN, ...
    "PUSCHCodebookNumPorts", NaN, ...
    "PortSelectionSource", "", ...
    "NumRxAnt", NaN, ...
    "TransformPrecoding", false, ...
    "TransmissionScheme", "", ...
    "MetricFamily", "post_equalization_mutual_information", ...
    "RankSelectionObjective", "sum_log2_one_plus_layer_sinr", ...
    "ValueRole", "estimated_runtime_srs");

if isempty(Hest)
    estimate.RISource = "srs_hest_missing";
    estimate.TPMISource = "srs_hest_missing";
    return;
end

[Hprb, numRxAnt, numTxPorts] = localPRBAveragedChannel(Hest);
estimate.PRBCount = double(size(Hprb, 3));
estimate.SRSSymbolCount = double(size(Hprb, 4));
estimate.NumRxAnt = double(numRxAnt);
estimate.NumTxPorts = double(numTxPorts);
estimate.SRSNumTxPorts = double(numTxPorts);
if isempty(Hprb) || numTxPorts < 1 || numRxAnt < 1
    estimate.RISource = "srs_prb_channel_unavailable";
    estimate.TPMISource = "srs_prb_channel_unavailable";
    return;
end

scheme = lower(string(sixgr.util.structGet(cfg, "phy.pusch.transmissionScheme", "nonCodebook")));
transformPrecoding = logical(sixgr.util.structGet(cfg, "phy.pusch.transformPrecoding", false));
estimate.TransformPrecoding = logical(transformPrecoding);
estimate.TransmissionScheme = char(scheme);

[cond_dB] = localRankConditionNumber(Hprb);
[ri, rankMetric, rankCandidateCount] = localEstimateRankByMI(Hprb, max(double(nVar), eps), cfg);
estimate.RI = double(ri);
estimate.ConditionNumber_dB = double(cond_dB);
estimate.RankMutualInformation = double(rankMetric);
estimate.RankCandidateCount = double(rankCandidateCount);
estimate.RISource = "ul_srs_post_equalization_mi_rank_estimator";

if scheme ~= "codebook" || transformPrecoding || numTxPorts < 2
    estimate.Valid = isfinite(estimate.RI);
    estimate.TPMISource = "ul_srs_tpmi_not_required_for_noncodebook_or_transform_precoding";
    return;
end

[Htpmi, tpmiNumPorts, portSource] = localRestrictToPUSCHCodebookPorts(Hprb, cfg, numTxPorts);
estimate.NumTxPorts = double(tpmiNumPorts);
estimate.PUSCHCodebookNumPorts = double(tpmiNumPorts);
estimate.PortSelectionSource = char(portSource);
[riJoint, tpmi, metric, candidateCount, beamIndices] = localEstimateRankTPMI(Htpmi, max(double(nVar), eps), cfg, tpmiNumPorts, transformPrecoding);
if isfinite(riJoint)
    estimate.RI = double(riJoint);
    estimate.RankMutualInformation = double(metric);
    estimate.RISource = "ul_srs_joint_rank_tpmi_post_equalization_mi_estimator";
elseif isfinite(estimate.RI)
    estimate.RI = double(max(1, min(round(double(estimate.RI)), max(1, round(double(tpmiNumPorts))))));
end
estimate.TPMI = double(tpmi);
estimate.TPMICandidateCount = double(candidateCount);
estimate.TPMIMutualInformation = double(metric);
estimate.SelectedBeamIndices = double(beamIndices);
if isfinite(tpmi)
    estimate.TPMISource = "ul_srs_mmse_post_equalization_mi_tpmi_estimator";
else
    estimate.TPMISource = "ul_srs_tpmi_estimator_unavailable";
end
estimate.Valid = isfinite(estimate.RI) || isfinite(estimate.TPMI);
end

function [Hout, numPortsOut, source] = localRestrictToPUSCHCodebookPorts(Hprb, cfg, measuredNumPorts)
Hout = Hprb;
numPortsOut = max(1, round(double(measuredNumPorts)));
source = "srs_port_count_matches_pusch_codebook";

configuredPorts = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pusch.NumAntennaPorts", NaN), ...
    sixgr.util.structGet(cfg, "phy.pusch.numAntennaPorts", NaN), ...
    sixgr.util.structGet(cfg, "phy.pusch.dmrs.nPorts", NaN), ...
    sixgr.util.structGet(cfg, "phy.pusch.nPorts", NaN));
if ~(isfinite(configuredPorts) && configuredPorts >= 1)
    configuredPorts = numPortsOut;
    source = "pusch_codebook_ports_inferred_from_srs_ports";
end
configuredPorts = max(1, round(double(configuredPorts)));

% nrPUSCH codebook precoding is defined only for 1, 2, or 4 antenna ports.
% If SRS sounds more ports than the active PUSCH port set, score only the
% ports the grant can actually transmit on instead of passing a wider-port
% TPMI into nrPUSCHConfig later.
allowedPorts = [1 2 4];
if ~ismember(configuredPorts, allowedPorts)
    idx = find(allowedPorts >= configuredPorts, 1, "first");
    if isempty(idx)
        idx = numel(allowedPorts);
    end
    configuredPorts = allowedPorts(idx);
    source = "pusch_codebook_ports_normalized_to_nr_allowed_set";
end

if configuredPorts < numPortsOut
    Hout = Hprb(:, 1:configuredPorts, :, :);
    numPortsOut = configuredPorts;
    source = "srs_ports_restricted_to_active_pusch_codebook_ports";
elseif configuredPorts > numPortsOut
    source = "pusch_codebook_ports_limited_by_available_srs_ports";
end
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for ii = 1:nargin
    candidate = varargin{ii};
    if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
        value = double(candidate);
        return;
    end
end
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
    Hprb = reshape(Hwide, numRxAnt, numTxPorts, 1, 1);
    return;
end

if ndims(Hest) == 3
    % Single-port estimate often lands here as K x L x NRx. Keep each SRS
    % OFDM symbol as its own observation; only subcarriers inside a PRB are
    % averaged.
    Hgrid = double(Hest);
    K = size(Hgrid, 1);
    L = size(Hgrid, 2);
    numRxAnt = size(Hgrid, 3);
    numTxPorts = 1;
    nPRB = max(1, floor(K / 12));
    Hprb = complex(zeros(numRxAnt, numTxPorts, nPRB, L));
    for prb = 1:nPRB
        sc = (prb - 1) * 12 + (1:12);
        sc = sc(sc <= K);
        for sym = 1:L
            slice = Hgrid(sc, sym, :);
            Hprb(:, 1, prb, sym) = reshape(mean(slice, 1, "omitnan"), [], 1);
        end
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
Hprb = complex(zeros(numRxAnt, numTxPorts, nPRB, L));
for prb = 1:nPRB
    sc = (prb - 1) * 12 + (1:12);
    sc = sc(sc <= K);
    for sym = 1:L
        slice = Hgrid(sc, sym, :, :);
        avg = squeeze(mean(slice, 1, "omitnan"));
        if isempty(avg)
            continue;
        end
        if isvector(avg)
            avg = reshape(avg, numRxAnt, numTxPorts);
        end
        Hprb(:, :, prb, sym) = avg;
    end
end
end

function cond_dB = localRankConditionNumber(Hprb)
cond_dB = NaN;
numTxPorts = size(Hprb, 2);
if isempty(Hprb) || numTxPorts < 1
    return;
end

condVals = NaN(numel(1:size(Hprb, 3)) * numel(1:size(Hprb, 4)), 1);
k = 0;
for prb = 1:size(Hprb, 3)
    for sym = 1:size(Hprb, 4)
        H = double(Hprb(:, :, prb, sym));
        if ~all(isfinite(H), "all")
            continue;
        end
        [condHere, status] = sixgr.mimo.channelConditionNumber(H);
        if isfinite(condHere) && string(status) == "valid"
            k = k + 1;
            condVals(k) = double(condHere);
        end
    end
end
condVals = condVals(isfinite(condVals));
if isempty(condVals)
    return;
end
cond_dB = mean(condVals, "omitnan");
end

function [ri, metricBest, candidateCount] = localEstimateRankByMI(Hprb, nVar, cfg)
ri = NaN;
metricBest = NaN;
candidateCount = 0;
numTxPorts = size(Hprb, 2);
if isempty(Hprb) || numTxPorts < 1
    return;
end
maxRank = localResolveMaxRank(cfg, numTxPorts);
bestMetric = -inf;
minIncrement = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.rankMinIncrementMI_bpcu", ...
    sixgr.util.structGet(cfg, "phy.srs.rankMinIncrementMI_bpcu", 1e-6)));
if ~(isfinite(minIncrement) && minIncrement >= 0)
    minIncrement = 1e-6;
end
for rankIdx = 1:maxRank
    candidateCount = candidateCount + 1;
    metric = localAverageEigenmodeMI(Hprb, nVar, rankIdx);
    if isfinite(metric) && (metric > bestMetric + minIncrement || ~isfinite(bestMetric))
        bestMetric = metric;
        ri = rankIdx;
    end
end
if isfinite(bestMetric)
    metricBest = bestMetric;
end
end

function maxRank = localResolveMaxRank(cfg, numTxPorts)
maxRank = double(sixgr.util.structGet(cfg, "phy.pusch.maxRankDefault", ...
    sixgr.util.structGet(cfg, "phy.pusch.numLayers", sixgr.util.structGet(cfg, "phy.pusch.nLayers", numTxPorts))));
if ~(isfinite(maxRank) && maxRank >= 1)
    maxRank = numTxPorts;
end
maxRank = max(1, min(round(maxRank), max(1, round(double(numTxPorts)))));
end

function metric = localAverageEigenmodeMI(Hprb, nVar, rankIdx)
metric = NaN;
acc = 0;
count = 0;
for prb = 1:size(Hprb, 3)
    for sym = 1:size(Hprb, 4)
        H = double(Hprb(:, :, prb, sym));
        if ~all(isfinite(H), "all")
            continue;
        end
        Rtx = H' * H;
        eigvals = sort(real(eig((Rtx + Rtx') / 2)), "descend");
        eigvals = eigvals(isfinite(eigvals) & eigvals > 0);
        if isempty(eigvals)
            continue;
        end
        n = min(max(1, round(double(rankIdx))), numel(eigvals));
        acc = acc + sum(log2(1 + eigvals(1:n) ./ max(double(nVar), eps)));
        count = count + 1;
    end
end
if count > 0
    metric = acc / count;
end
end

function [ri, tpmi, metricBest, candidateCount, beamIndices] = localEstimateRankTPMI(Hprb, nVar, cfg, numTxPorts, transformPrecoding)
ri = NaN;
tpmi = NaN;
metricBest = NaN;
candidateCount = 0;
beamIndices = [];
if ~(numTxPorts >= 2)
    return;
end
if exist("nrPUSCHCodebook", "file") ~= 2
    return;
end

bestMetric = -inf;
bestBeamIndices = [];
bestRI = NaN;
maxRank = localResolveMaxRank(cfg, numTxPorts);
for rankIdx = 1:maxRank
    catalog = sixgr.phy.ul.puschCodebookCatalog(rankIdx, numTxPorts, transformPrecoding);
    if ~logical(catalog.Valid)
        continue;
    end
    validTPMIs = double(catalog.ValidTPMISet);
    for idx = 1:numel(validTPMIs)
        tpmiIdx = validTPMIs(idx);
        [W, candidateBeamIndices] = localPUSCHCodebookCandidate(rankIdx, numTxPorts, tpmiIdx, transformPrecoding);
        if isempty(W)
            continue;
        end
        candidateCount = candidateCount + 1;
        metric = localAverageMutualInformation(Hprb, W, nVar);
        if isfinite(metric) && metric > bestMetric
            bestMetric = metric;
            bestRI = rankIdx;
            tpmi = double(tpmiIdx);
            bestBeamIndices = candidateBeamIndices;
        end
    end
end

if isfinite(bestMetric)
    ri = double(bestRI);
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
    for sym = 1:size(Hprb, 4)
        H = double(Hprb(:, :, prb, sym));
        if ~all(isfinite(H), "all")
            continue;
        end
        WportsByLayer = localOrientPUSCHCodebookForChannel(W, size(H, 2));
        if isempty(WportsByLayer)
            continue;
        end
        Heff = H * WportsByLayer;
        nLayers = size(Heff, 2);
        regularized = eye(nLayers) + (Heff' * Heff) ./ max(double(nVar), eps);
        if rcond(regularized) < 1e-12
            regularized = regularized + eye(nLayers) .* (1e-12 * max(trace(regularized) / max(nLayers, 1), 1));
        end
        postEqCov = regularized \ eye(nLayers);
        sinr = 1 ./ max(real(diag(postEqCov)), eps) - 1;
        sinr = max(real(sinr), 0);
        acc = acc + sum(log2(1 + sinr));
        count = count + 1;
    end
end
if count > 0
    metric = acc / count;
end
end

function WportsByLayer = localOrientPUSCHCodebookForChannel(W, numTxPorts)
WportsByLayer = [];
if isempty(W) || ~(isscalar(numTxPorts) && isfinite(numTxPorts) && numTxPorts >= 1)
    return;
end
W = double(W);
numTxPorts = max(1, round(double(numTxPorts)));

% nrPUSCHCodebook returns layer-by-port weights in current 5G Toolbox
% releases. The channel matrix is receive-antenna-by-transmit-port, so the
% score needs a port-by-layer precoder. Preserve already-oriented custom
% candidates and reject genuinely incompatible dimensions.
if size(W, 1) == numTxPorts
    WportsByLayer = W;
elseif size(W, 2) == numTxPorts
    WportsByLayer = W.';
else
    return;
end

if isempty(WportsByLayer) || size(WportsByLayer, 1) ~= numTxPorts
    WportsByLayer = [];
end
end

function [W, beamIndices] = localPUSCHCodebookCandidate(ri, numTxPorts, tpmiIdx, transformPrecoding)
W = [];
beamIndices = [];
[~, ~, W] = sixgr.phy.ul.puschCodebookProjectionMatrix( ...
    max(1, round(double(ri))), max(1, round(double(numTxPorts))), ...
    round(double(tpmiIdx)), logical(transformPrecoding));
if isempty(W)
    return;
end
portPower = sum(abs(double(W)).^2, 1, "omitnan");
beamIndices = find(isfinite(portPower) & portPower > (eps(max(portPower, [], "omitnan")) * 16));
end
