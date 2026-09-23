function estimate = estimateSRSRITPMI(Hest, nVar, cfg, varargin)
%ESTIMATESRSRITPMI Estimate UL RI and TPMI from SRS channel observations.
%
% This helper keeps the estimator explicitly in the SRS / UL sounding path:
%   1. Form PRB-averaged channel observations from the measured Hest grid.
%   2. Derive RI from post-equalization mutual information across PRBs
%      and SRS symbols.
%
% The channel-estimate/noise pair is sufficient to rank spatial candidates,
% but it is not, by itself, an absolute PUSCH data-channel power reference.
% Callers that need a scheduler-facing SINR must therefore supply the
% receiver-measured SRS reference power/SINR and a declared SRS-to-data
% energy conversion. Calibrate disturbance BEFORE precoding and MMSE;
% never force the layer mean to equal a reference-signal SINR, because
% doing so erases the native codebook's rank-dependent power split.

ip = inputParser;
ip.addParameter("AbsoluteSINRAnchor_dB", NaN, ...
    @(x) isnumeric(x) && isscalar(x));
ip.addParameter("AbsoluteSINRAnchorSource", "", ...
    @(x) ischar(x) || isstring(x));
ip.addParameter("AbsoluteSINRAnchorPowerReferencePlane", "", ...
    @(x) ischar(x) || isstring(x));
ip.addParameter("ReferenceSignalPower", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("ReferencePowerSource", "", @(x) ischar(x) || isstring(x));
ip.addParameter("PUSCHToSRSReferenceEnergyRatio", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("PUSCHToSRSReferenceEnergySource", "", @(x) ischar(x) || isstring(x));
ip.parse(varargin{:});
opt = ip.Results;
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
    "SelectedPostEqSINRPerLayer_dB", [], ...
    "SelectedMinimumLayerMeanPostEqSINR_dB", NaN, ...
    "SelectedWidebandMeanPostEqSINR_dB", NaN, ...
    "SelectedPostEqSINRSource", "", ...
    "SelectedPostEqSINRValueRole", "", ...
    "SelectedPostEqSINRValueStatus", "NOT_AVAILABLE", ...
    "SelectedPostEqSINRCalibrationOffset_dB", NaN, ...
    "SelectedPostEqSINRAnchor_dB", NaN, ...
    "SelectedPostEqSINRAnchorSource", "", ...
    "SelectedPostEqSINRPowerReferencePlane", "", ...
    "SelectedReferenceSignalPower", NaN, ...
    "SelectedDisturbancePower", NaN, ...
    "SelectedPUSCHToSRSReferenceEnergyRatio", NaN, ...
    "SelectedPUSCHToSRSReferenceEnergySource", "", ...
    "SelectedBeamIndices", [], ...
    "SelectedCodebookPortIndices1Based", [], ...
    "CodebookPortIndexDefinition", "nonzero_nrPUSCHCodebook_antenna_port_support_not_spatial_beam_ID", ...
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
strict = logical(sixgr.util.structGet(cfg,"mimo.strict", ...
    sixgr.util.structGet(cfg,"phy.mimo.strict",false)));

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

anchor_dB = double(opt.AbsoluteSINRAnchor_dB);
anchorSource = strtrim(string(opt.AbsoluteSINRAnchorSource));
anchorPlane = strtrim(string(opt.AbsoluteSINRAnchorPowerReferencePlane));
referencePower = double(opt.ReferenceSignalPower);
energyRatio = double(opt.PUSCHToSRSReferenceEnergyRatio);
energySource = strtrim(string(opt.PUSCHToSRSReferenceEnergySource));
% The currently executable absolute conversion is the explicit normalized
% fixed-Es/N0 path: SRS and PUSCH preserve unit-grid symbols before their
% own native mappings. Thermal link-budget totals alone cannot establish
% a PUSCH/SRS per-RE ratio; leave that unsupported conversion diagnostic.
anchorUsable = isfinite(anchor_dB) && isfinite(referencePower) && referencePower>0 && ...
    isfinite(double(nVar)) && isscalar(nVar) && nVar>0 && ...
    anchorSource == "measured_ul_srs_pilot_reconstruction_sinr" && ...
    anchorPlane == "receiver_srs_resource_elements_after_ofdm_demodulation" && ...
    string(opt.ReferencePowerSource) == "received_reference_grid_plus_receiver_hest" && ...
    energyRatio == 1 && energySource == "normalized_fixed_snr_unit_grid_reference_no_device_power_scaling";
predictionNoise = max(double(nVar),eps);
if anchorUsable
    candidateNoise = max(double(nVar),referencePower/10^(anchor_dB/10));
    anchorUsable = isfinite(candidateNoise) && candidateNoise>0;
    if anchorUsable, predictionNoise = candidateNoise; end
end
if anchorUsable
    Hprb = Hprb .* sqrt(energyRatio);
    estimate.SelectedReferenceSignalPower = referencePower;
    estimate.SelectedDisturbancePower = predictionNoise;
    estimate.SelectedPUSCHToSRSReferenceEnergyRatio = energyRatio;
    estimate.SelectedPUSCHToSRSReferenceEnergySource = energySource;
end

[cond_dB] = localRankConditionNumber(Hprb);
[ri, rankMetric, rankCandidateCount] = localEstimateRankByMI(Hprb, predictionNoise, cfg);
estimate.RI = double(ri);
estimate.ConditionNumber_dB = double(cond_dB);
estimate.RankMutualInformation = double(rankMetric);
estimate.RankCandidateCount = double(rankCandidateCount);
estimate.RISource = "ul_srs_post_equalization_mi_rank_estimator";

if scheme ~= "codebook" || transformPrecoding
    estimate.Valid = isfinite(estimate.RI);
    estimate.TPMISource = "ul_srs_tpmi_not_required_for_noncodebook_or_transform_precoding";
    return;
end

[Htpmi, tpmiNumPorts, portSource] = localRestrictToPUSCHCodebookPorts( ...
    Hprb, cfg, numTxPorts, strict);
estimate.NumTxPorts = double(tpmiNumPorts);
estimate.PUSCHCodebookNumPorts = double(tpmiNumPorts);
estimate.PortSelectionSource = char(portSource);
[riJoint, tpmi, metric, candidateCount, beamIndices, layerSINR_dB, ...
    minimumLayerSINR_dB, widebandMeanSINR_dB] = localEstimateRankTPMI( ...
    Htpmi, predictionNoise, cfg, tpmiNumPorts, transformPrecoding);
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
estimate.SelectedCodebookPortIndices1Based = double(beamIndices);
if anchorUsable && ~isempty(layerSINR_dB) && isfinite(widebandMeanSINR_dB)
    estimate.SelectedPostEqSINRCalibrationOffset_dB = 0;
    estimate.SelectedPostEqSINRAnchor_dB = double(anchor_dB);
    estimate.SelectedPostEqSINRAnchorSource = char(anchorSource);
    estimate.SelectedPostEqSINRPowerReferencePlane = char(anchorPlane);
end
estimate.SelectedPostEqSINRPerLayer_dB = double(layerSINR_dB);
estimate.SelectedMinimumLayerMeanPostEqSINR_dB = double(minimumLayerSINR_dB);
estimate.SelectedWidebandMeanPostEqSINR_dB = double(widebandMeanSINR_dB);
if ~isempty(layerSINR_dB) && all(isfinite(layerSINR_dB))
    if anchorUsable
        estimate.SelectedPostEqSINRSource = ...
            "receiver_measured_srs_reference_power_selected_ri_tpmi_mmse_layer_prediction";
        estimate.SelectedPostEqSINRValueRole = ...
            "power_plane_calibrated_predicted_pusch_data_channel_scheduling_input";
        estimate.SelectedPostEqSINRValueStatus = "PASS";
    else
        estimate.SelectedPostEqSINRSource = ...
            "measured_srs_hest_selected_ri_tpmi_mmse_unanchored_relative_layer_metric";
        estimate.SelectedPostEqSINRValueRole = ...
            "diagnostic_relative_spatial_metric_not_data_scheduler_input";
        estimate.SelectedPostEqSINRValueStatus = ...
            "DIAGNOSTIC_ONLY_UNCALIBRATED_POWER_PLANE";
    end
end
if isfinite(tpmi)
    estimate.TPMISource = "ul_srs_mmse_post_equalization_mi_tpmi_estimator";
else
    estimate.TPMISource = "ul_srs_tpmi_estimator_unavailable";
end
estimate.Valid = isfinite(estimate.RI) || isfinite(estimate.TPMI);
end

function [Hout, numPortsOut, source] = localRestrictToPUSCHCodebookPorts(Hprb, cfg, measuredNumPorts, strict)
Hout = Hprb;
numPortsOut = max(1, round(double(measuredNumPorts)));
source = "srs_port_count_matches_pusch_codebook";

configuredPorts = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pusch.NumAntennaPorts", NaN), ...
    sixgr.util.structGet(cfg, "phy.pusch.numAntennaPorts", NaN), ...
    sixgr.util.structGet(cfg, "phy.pusch.dmrs.nPorts", NaN), ...
    sixgr.util.structGet(cfg, "phy.pusch.nPorts", NaN));
if ~(isfinite(configuredPorts) && configuredPorts >= 1)
    if strict
        error("sixgr:mimo:MissingSRSState", ...
            "Strict SRS-driven PUSCH selection requires the active PUSCH antenna-port count.");
    end
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
    if strict
        error("sixgr:mimo:UnsupportedAntennaTuple", ...
            "Strict PUSCH codebook supports exactly 1, 2, or 4 active antenna ports; received %d.", ...
            configuredPorts);
    end
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
    if strict
        error("sixgr:mimo:MissingSRSState", ...
            "Measured SRS exposes %d port(s), fewer than the active %d-port PUSCH codebook.", ...
            numPortsOut,configuredPorts);
    end
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

function [ri, tpmi, metricBest, candidateCount, beamIndices, ...
        layerSINR_dB, minimumLayerSINR_dB, widebandMeanSINR_dB] = ...
        localEstimateRankTPMI(Hprb, nVar, cfg, numTxPorts, transformPrecoding)
ri = NaN;
tpmi = NaN;
metricBest = NaN;
candidateCount = 0;
beamIndices = [];
layerSINR_dB = [];
minimumLayerSINR_dB = NaN;
widebandMeanSINR_dB = NaN;
if ~(numTxPorts >= 1)
    return;
end
if exist("nrPUSCHCodebook", "file") ~= 2
    return;
end

bestMetric = -inf;
bestBeamIndices = [];
bestRI = NaN;
bestLayerSINR_dB = [];
bestMinimumLayerSINR_dB = NaN;
bestWidebandMeanSINR_dB = NaN;
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
        [metric, candidateLayerSINR_dB, candidateMinimumLayerSINR_dB, ...
            candidateWidebandMeanSINR_dB] = ...
            localAverageMutualInformation(Hprb, W, nVar);
        if isfinite(metric) && metric > bestMetric
            bestMetric = metric;
            bestRI = rankIdx;
            tpmi = double(tpmiIdx);
            bestBeamIndices = candidateBeamIndices;
            bestLayerSINR_dB = candidateLayerSINR_dB;
            bestMinimumLayerSINR_dB = candidateMinimumLayerSINR_dB;
            bestWidebandMeanSINR_dB = candidateWidebandMeanSINR_dB;
        end
    end
end

if isfinite(bestMetric)
    ri = double(bestRI);
    metricBest = bestMetric;
    beamIndices = bestBeamIndices;
    layerSINR_dB = bestLayerSINR_dB;
    minimumLayerSINR_dB = bestMinimumLayerSINR_dB;
    widebandMeanSINR_dB = bestWidebandMeanSINR_dB;
end
end

function [metric, layerMeanSINR_dB, minimumLayerMeanSINR_dB, ...
        widebandMeanSINR_dB] = localAverageMutualInformation(Hprb, W, nVar)
metric = NaN;
layerMeanSINR_dB = [];
minimumLayerMeanSINR_dB = NaN;
widebandMeanSINR_dB = NaN;
if isempty(Hprb) || isempty(W)
    return;
end
acc = 0;
count = 0;
layerSINRAccumulator = [];
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
        if isempty(layerSINRAccumulator)
            layerSINRAccumulator = zeros(size(sinr));
        end
        if numel(sinr) ~= numel(layerSINRAccumulator)
            continue;
        end
        acc = acc + sum(log2(1 + sinr));
        layerSINRAccumulator = layerSINRAccumulator + sinr;
        count = count + 1;
    end
end
if count > 0
    metric = acc / count;
    layerMeanSINRLinear = max(layerSINRAccumulator ./ count, 0);
    layerMeanSINR_dB = 10 .* log10(max(layerMeanSINRLinear(:).', eps));
    minimumLayerMeanSINR_dB = min(layerMeanSINR_dB);
    widebandMeanSINR_dB = 10 .* log10(max(mean(layerMeanSINRLinear), eps));
end
end

function WportsByLayer = localOrientPUSCHCodebookForChannel(W, numTxPorts)
WportsByLayer = [];
if isempty(W) || ~(isscalar(numTxPorts) && isfinite(numTxPorts) && numTxPorts >= 1)
    return;
end
W = double(W);
numTxPorts = max(1, round(double(numTxPorts)));

% Candidate construction returns the canonical port-by-layer matrix.
% Never infer orientation from dimensions: square full-rank matrices are
% ambiguous and must use the same explicit transpose as PUSCH mapping.
if size(W, 1) ~= numTxPorts
    error('sixgr:phy:ul:SRSPrecoderDomainMismatch', ...
        'SRS scoring requires a canonical port-by-layer precoder.');
end
WportsByLayer = W;
end

function [W, beamIndices] = localPUSCHCodebookCandidate(ri, numTxPorts, tpmiIdx, transformPrecoding)
W = [];
beamIndices = [];
[W, ~] = sixgr.phy.ul.puschCodebookProjectionMatrix( ...
    max(1, round(double(ri))), max(1, round(double(numTxPorts))), ...
    round(double(tpmiIdx)), logical(transformPrecoding));
if isempty(W)
    return;
end
portPower = sum(abs(double(W)).^2, 2);
beamIndices = find(portPower > (eps(max(portPower)) * 16)).';
end
