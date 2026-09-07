function det = ZCDPEDetector(rxWaveform, cfg, varargin)
%ZCDPEDETECTOR Detect ZC-DPE PRACH preambles and DPI index.

p = inputParser;
p.FunctionName = "sixgr.rach.ZCDPEDetector";
addRequired(p, "rxWaveform", @(x) isnumeric(x) && ~isempty(x));
addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "Occasion", struct(), @(x) isstruct(x));
addParameter(p, "CandidatePreambles", 0:63, @(x) isnumeric(x));
addParameter(p, "DetectionThresholdMode", "", @(x) isempty(x) || any(strcmpi(string(x), ["fixed","auto"])));
addParameter(p, "DetectionThreshold", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0));
addParameter(p, "EnableFrequencyEstimationMetric", [], @(x) isempty(x) || islogical(x) || isnumeric(x));
addParameter(p, "ResidualFreqBound_Hz", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
parse(p, rxWaveform, cfg, varargin{:});
opts = p.Results;

baselineDet = sixgr.rach.PRACHDetector(rxWaveform, cfg, ...
    "Occasion", opts.Occasion, ...
    "CandidatePreambles", opts.CandidatePreambles, ...
    "DetectionThresholdMode", opts.DetectionThresholdMode, ...
    "DetectionThreshold", opts.DetectionThreshold, ...
    "EnableFrequencyEstimationMetric", opts.EnableFrequencyEstimationMetric);

zcfg = sixgr.rach.ZCDPEConfig(cfg);
occasion = opts.Occasion;
if isempty(fieldnames(occasion))
    occasion = sixgr.rach.mapPRACHToOccasion(cfg, "OccasionIndex", 1);
end
candidateSet = unique(round(double(opts.CandidatePreambles(:).')));
candidateSet = candidateSet(candidateSet >= 0 & candidateSet <= 63);
if isempty(candidateSet)
    error("sixgr:rach:ZCDPEDetector:NoCandidates", ...
        "CandidatePreambles must contain at least one valid 0..63 index.");
end
D = double(zcfg.DPI_D);
M = double(zcfg.NumSymbols);
search = localSearchZCDPE(rxWaveform, cfg, occasion, candidateSet, zcfg);
thresholdMode = lower(string(localFirstNonEmpty(opts.DetectionThresholdMode, ...
    sixgr.util.structGet(cfg, "DetectionThresholdMode", "fixed"))));
explicitThreshold = double(localFirstNonEmpty(opts.DetectionThreshold, ...
    sixgr.util.structGet(cfg, "DetectionThreshold", 0.02)));
threshold = localResolveThreshold(search.CandidatePeaks, thresholdMode, explicitThreshold, cfg);
detected = isfinite(search.PeakMetric) && search.PeakMetric >= threshold;

det = baselineDet;
det.Detected = logical(detected);
det.DetectedPreambleIndex = search.PreambleIndex;
det.PreambleIndexFromPeak = search.PreambleIndex;
det.TimingOffsetSamples = search.TimingOffsetSamples;
det.PeakMetric = search.PeakMetric;
det.Threshold = double(threshold);
det.ThresholdMode = char(thresholdMode);
det.DetectorBackend="zcdpe_waveform_candidate_dpi_correlation";
det.ThresholdSource="zcdpe_configured_fixed_matched_filter";
if thresholdMode=="auto"
    det.ThresholdSource="zcdpe_unqualified_peak_background_heuristic";
end
det.ThresholdCalibrationStatus="unqualified_research_detector";
% The baseline NR trace is not this research detector's decision trace.
% Keep it explicitly diagnostic; do not export its samples with DPI outcomes.
det.CorrelationTrace=struct('LagSamples',zeros(0,1),'CorrelationAbs',zeros(0,1), ...
    'Threshold',NaN,'NoiseFloor',NaN,'PeakLagSamples',NaN, ...
    'TraceStatus',"unavailable_zcdpe_decision_trace_not_published");
det.CorrelationPeaks = search.CandidatePeaks(:);
det.CandidatePreambles = candidateSet(:);
det.MultiCandidateAboveThreshold = sum(double(search.CandidatePeaks) >= double(threshold)) > 1;
det.ZCDPE = localEmptyZCDPE(zcfg);
det.ZCDPE.LegacyNRDetected = logical(baselineDet.Detected);
det.ZCDPE.LegacyNRPeakMetric = double(baselineDet.PeakMetric);
det.ZCDPE.LegacyNRCorrelationTrace=baselineDet.CorrelationTrace;
det.ZCDPE.SearchBackend = "waveform_candidate_dpi_correlation";

enableFreq = logical(localFirstNonEmpty(opts.EnableFrequencyEstimationMetric, ...
    sixgr.util.structGet(cfg, "EnableFrequencyEstimationMetric", false)));
if detected && enableFreq && isstruct(search.BestReference) && isfield(search.BestReference, "Waveform")
    alignedBest = localAlignWaveforms(rxWaveform, search.BestReference.Waveform, search.TimingOffsetSamples);
    det.FrequencyEstimate = sixgr.rach.estimateFrequencyOffset(alignedBest.RxAligned, ...
        alignedBest.RefAligned, search.BestReference.SampleRate_Hz);
end

if ~detected
    det.DetectedPreambleIndex = NaN;
    det.PreambleIndexFromPeak = search.PreambleIndex;
    det.TimingOffsetSamples = NaN;
    return;
end

detectedPreamble = double(search.PreambleIndex);

ref0 = sixgr.rach.generateZCDPEWaveform(localWithZCDPEDPI(cfg, 0), ...
    "Occasion", occasion, "PreambleIndex", detectedPreamble);
aligned0 = localAlignWaveforms(rxWaveform, ref0.Waveform, double(det.TimingOffsetSamples));
z = localComplexPeaks(aligned0.RxAligned, aligned0.RefAligned, M);
if isempty(z)
    return;
end
M = numel(z);
Trep = localRepetitionPeriodSeconds(ref0, M);

residualBound = double(localFirstNonEmpty(opts.ResidualFreqBound_Hz, zcfg.ResidualFreqBound_Hz));
if isfinite(residualBound)
    [dStar, scores, fJoint] = localJointSearch(z, D, Trep, residualBound, zcfg.FreqSearchPoints);
    isJoint = true;
else
    dStar = search.DPIIndex;
    scores = search.DPIScores(:);
    fJoint = NaN;
    isJoint = false;
end

phaseStep = 2*pi*dStar/D;
fLs = localLSDoppler(z, phaseStep, Trep);
if isfinite(fJoint)
    fOut = fJoint;
else
    fOut = fLs;
end
sortedScores = sort(double(scores(:)), "descend");
if numel(sortedScores) > 1 && sortedScores(1) > 0
    confusion = sortedScores(2) / sortedScores(1);
else
    confusion = 0;
end

det.ZCDPE.ComplexPeaks_z = z(:);
det.ZCDPE.DPI_Scores = scores(:);
det.ZCDPE.DPI_Detected = dStar;
det.ZCDPE.DPI_PhaseStep_rad = phaseStep;
det.ZCDPE.IsJointSearch = isJoint;
det.ZCDPE.DopplerEstimate_Hz = fOut;
det.ZCDPE.DopplerEstimate_Variance = NaN;
det.ZCDPE.DPI_ConfusionScore = confusion;
end

function z = localComplexPeaks(rxAligned, refAligned, M)
rx = localVector(rxAligned);
ref = localVector(refAligned);
L = min(numel(rx), numel(ref));
if L < 1
    z = complex([]);
    return;
end
rx = rx(1:L);
ref = ref(1:L);
M = max(1, min(round(double(M)), L));
edges = round(linspace(1, L + 1, M + 1));
z = complex(zeros(M, 1));
for m = 1:M
    idx = edges(m):max(edges(m), edges(m+1)-1);
    idx = idx(idx >= 1 & idx <= L);
    if isempty(idx)
        z(m) = 0;
    else
        z(m) = sum(rx(idx) .* conj(ref(idx)));
    end
end
end

function search = localSearchZCDPE(rxWaveform, cfg, occasion, candidateSet, zcfg)
rx = localVector(rxWaveform);
D = double(zcfg.DPI_D);
numCandidates = numel(candidateSet);
scoreMatrix = nan(numCandidates, D);
offsetMatrix = nan(numCandidates, D);
refs = cell(numCandidates, D);

for iCand = 1:numCandidates
    preamble = double(candidateSet(iCand));
    for d = 0:D-1
        try
            ref = sixgr.rach.generateZCDPEWaveform(cfg, ...
                "Occasion", occasion, "PreambleIndex", preamble, "DPI_d", d);
            [scoreMatrix(iCand, d+1), offsetMatrix(iCand, d+1)] = ...
                localNormalizedWaveformCorrelation(rx, ref.Waveform);
            refs{iCand, d+1} = ref;
        catch
            scoreMatrix(iCand, d+1) = NaN;
            offsetMatrix(iCand, d+1) = NaN;
        end
    end
end

[candidatePeaks, bestDPerCandidate] = max(scoreMatrix, [], 2, "omitnan");
candidatePeaks(~isfinite(candidatePeaks)) = NaN;
[peakMetric, bestCandidateIdx] = max(candidatePeaks, [], "omitnan");
if isempty(bestCandidateIdx) || ~isfinite(peakMetric)
    bestCandidateIdx = 1;
    peakMetric = NaN;
end
bestDIdx = bestDPerCandidate(bestCandidateIdx);
if isempty(bestDIdx) || ~isfinite(bestDIdx) || bestDIdx < 1
    bestDIdx = 1;
end

search = struct();
search.CandidatePeaks = candidatePeaks(:);
search.ScoreMatrix = scoreMatrix;
search.PeakMetric = double(peakMetric);
search.PreambleIndex = double(candidateSet(bestCandidateIdx));
search.DPIIndex = double(bestDIdx - 1);
search.DPIScores = scoreMatrix(bestCandidateIdx, :).';
search.TimingOffsetSamples = double(offsetMatrix(bestCandidateIdx, bestDIdx));
search.BestReference = refs{bestCandidateIdx, bestDIdx};
if isempty(search.BestReference)
    search.BestReference = struct();
end
end

function [metric, offsetSamples] = localNormalizedWaveformCorrelation(rxWave, refWave)
rx = localVector(rxWave);
ref = localVector(refWave);
metric = NaN;
offsetSamples = NaN;
if isempty(rx) || isempty(ref)
    return;
end
rx = rx(isfinite(real(rx)) & isfinite(imag(rx)));
ref = ref(isfinite(real(ref)) & isfinite(imag(ref)));
if isempty(rx) || isempty(ref)
    return;
end
xc = sixgr.rach.fullWaveformCorrelation(rx,ref);
lags = (1:numel(xc)).' - numel(ref);
valid = lags >= 0 & lags <= max(0, numel(rx) - 1);
if ~any(valid)
    return;
end
xcv = xc(valid);
lagv = lags(valid);
den = sum(abs(rx).^2) * sum(abs(ref).^2);
if ~(isfinite(den) && den > 0)
    return;
end
[peak, idx] = max(abs(xcv).^2, [], "omitnan");
if isempty(idx) || ~isfinite(peak)
    return;
end
metric = double(peak / den);
offsetSamples = double(lagv(idx));
end

function threshold = localResolveThreshold(peaks, thresholdMode, explicitThreshold, cfg)
finitePeaks = double(peaks(isfinite(peaks)));
if isempty(finitePeaks) || strcmpi(thresholdMode, "fixed")
    threshold = explicitThreshold;
    return;
end
targetPfa = double(sixgr.util.structGet(cfg, "TargetFalseAlarmProbability", 1e-3));
robustCenter = median(finitePeaks);
robustSigma = 1.4826 * median(abs(finitePeaks - robustCenter));
gaussQuantile = max(1, sqrt(-2 * log(max(targetPfa, eps))));
threshold = max(explicitThreshold, robustCenter + gaussQuantile * robustSigma);
end

function [dStar, scores, fJoint] = localJointSearch(z, D, Trep, residualBoundHz, nFreq)
nFreq = max(3, round(double(nFreq)));
residualBoundHz = abs(double(residualBoundHz));
if ~(isfinite(residualBoundHz) && residualBoundHz > 0)
    residualBoundHz = Inf;
end
if isfinite(Trep) && Trep > 0
    unambiguousHz = 0.5 / Trep;
else
    unambiguousHz = Inf;
end
fMax = min(residualBoundHz, unambiguousHz);
if ~(isfinite(fMax) && fMax > 0)
    fMax = 0;
end
freqGrid = linspace(-fMax, fMax, nFreq);
m = (0:numel(z)-1).';
scores2 = zeros(D, nFreq);
for d = 0:D-1
    phi = 2*pi*d/D;
    for iF = 1:nFreq
        phase = exp(-1i * m * (phi + 2*pi*freqGrid(iF)*Trep));
        scores2(d+1, iF) = abs(sum(z(:) .* phase)).^2;
    end
end
[~, linIdx] = max(scores2(:));
[dIdx, fIdx] = ind2sub(size(scores2), linIdx);
dStar = dIdx - 1;
fJoint = freqGrid(fIdx);
scores = max(scores2, [], 2);
end

function cfgOut = localWithZCDPEDPI(cfgIn, dpiIndex)
if isstruct(cfgIn)
    cfgOut = cfgIn;
else
    cfgOut = struct(cfgIn);
end
cfgOut = sixgr.util.structSet(cfgOut, "ZCDPE.DPI_d", double(dpiIndex));
end

function fHz = localLSDoppler(z, phaseStep, Trep)
fHz = NaN;
M = numel(z);
if M < 2 || ~(isfinite(Trep) && Trep > 0)
    return;
end
m = (0:M-1).';
zPrime = z(:) .* exp(-1i * m * phaseStep);
theta = unwrap(angle(zPrime));
mBar = mean(m);
thetaBar = mean(theta);
den = sum((m - mBar).^2);
if den <= 0
    return;
end
slope = sum((m - mBar) .* (theta - thetaBar)) / den;
fHz = slope / (2*pi*Trep);
end

function T = localRepetitionPeriodSeconds(tx, M)
T = NaN;
fs = double(sixgr.util.structGet(tx, "SampleRate_Hz", NaN));
if isfinite(fs) && fs > 0 && M > 0
    T = size(tx.Waveform, 1) / fs / max(M, 1);
end
end

function aligned = localAlignWaveforms(rxWave, refWave, offsetSamples)
rx = localVector(rxWave);
ref = localVector(refWave);
offsetSamples = max(0, round(double(offsetSamples)));
if offsetSamples + 1 > numel(rx)
    aligned.RxAligned = complex([]);
    aligned.RefAligned = complex([]);
    return;
end
rx = rx(offsetSamples + 1:end);
L = min(numel(rx), numel(ref));
aligned.RxAligned = rx(1:L);
aligned.RefAligned = ref(1:L);
end

function z = localEmptyZCDPE(zcfg)
z = struct( ...
    "ComplexPeaks_z", complex(nan(max(1, double(zcfg.NumSymbols)), 1)), ...
    "DPI_Scores", nan(double(zcfg.DPI_D), 1), ...
    "DPI_Detected", NaN, ...
    "DPI_PhaseStep_rad", NaN, ...
    "IsJointSearch", false, ...
    "DopplerEstimate_Hz", NaN, ...
    "DopplerEstimate_Variance", NaN, ...
    "DPI_ConfusionScore", NaN);
end

function vec = localVector(x)
if isempty(x)
    vec = complex([]);
elseif size(x, 2) > 1
    vec = mean(x, 2);
else
    vec = x(:);
end
end

function value = localFirstNonEmpty(varargin)
value = [];
for iArg = 1:nargin
    candidate = varargin{iArg};
    if isempty(candidate)
        continue;
    end
    value = candidate;
    return;
end
end
