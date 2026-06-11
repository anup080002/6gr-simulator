function det = PRACHDetector(rxWaveform, cfg, varargin)
%PRACHDETECTOR Correlation-based PRACH detector using toolbox kernels.

p = inputParser;
p.FunctionName = "sixgr.rach.PRACHDetector";
addRequired(p, "rxWaveform", @(x) isnumeric(x) && ~isempty(x));
addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "Occasion", struct(), @(x) isstruct(x));
addParameter(p, "CandidatePreambles", 0:63, @(x) isnumeric(x));
addParameter(p, "DetectionThresholdMode", "", @(x) isempty(x) || any(strcmpi(string(x), ["fixed","auto"])));
addParameter(p, "DetectionThreshold", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0));
addParameter(p, "EnableFrequencyEstimationMetric", [], @(x) isempty(x) || islogical(x) || isnumeric(x));
parse(p, rxWaveform, cfg, varargin{:});
opts = p.Results;
profScope = sixgr.perf.TimeProfiler.scope("sixgr.rach.PRACHDetector", ...
    "Stage", "prach_detection", ...
    "Metadata", struct("NSamples", double(numel(rxWaveform)), ...
    "CandidatePreambles", double(numel(opts.CandidatePreambles)))); %#ok<NASGU>

occasion = opts.Occasion;
if isempty(fieldnames(occasion))
    occasion = sixgr.rach.mapPRACHToOccasion(cfg, "OccasionIndex", 1);
end

candidateSet = unique(round(double(opts.CandidatePreambles(:).')));
candidateSet = candidateSet(candidateSet >= 0 & candidateSet <= 63);
if isempty(candidateSet)
    error("sixgr:rach:PRACHDetector:NoCandidates", ...
        "CandidatePreambles must contain at least one valid 0..63 index.");
end

thresholdMode = lower(string(localFirstNonEmpty(opts.DetectionThresholdMode, ...
    sixgr.util.structGet(cfg, "DetectionThresholdMode", "fixed"))));
explicitThreshold = double(localFirstNonEmpty(opts.DetectionThreshold, ...
    sixgr.util.structGet(cfg, "DetectionThreshold", 0.02)));
enableFreq = logical(localFirstNonEmpty(opts.EnableFrequencyEstimationMetric, ...
    sixgr.util.structGet(cfg, "EnableFrequencyEstimationMetric", false)));

[idx0, offset0, detInfo] = localDetectByWaveformCorrelation(rxWaveform, cfg, occasion, candidateSet);

peaks = double(detInfo.CorrelationPeaks(:));
if isempty(peaks)
    peaks = nan(numel(candidateSet), 1);
end

[peakMetric, maxIdx] = max(peaks, [], "omitnan");
if isempty(maxIdx) || ~isfinite(peakMetric)
    maxIdx = 1;
    peakMetric = NaN;
end
candidateDetected = candidateSet(maxIdx);
threshold = localResolveThreshold(peaks, thresholdMode, explicitThreshold, cfg);
detected = isfinite(peakMetric) && peakMetric >= threshold && ~isempty(idx0);

if detected
    idx = double(candidateDetected);
    if numel(offset0) >= maxIdx
        offset = double(offset0(maxIdx));
    else
        offset = double(offset0(1));
    end
else
    idx = NaN;
    offset = NaN;
end

freqEst = struct("Valid", false, "EstimateHz", NaN, "Estimator", "disabled");
if detected && enableFreq
    ref = sixgr.rach.generatePRACHWaveform(cfg, "Occasion", occasion, "PreambleIndex", idx);
    cpLen = localFirstCPLength(ref);
    aligned = localAlignWaveforms(rxWaveform, ref.Waveform, round(offset), cpLen);
    freqEst = sixgr.rach.estimateFrequencyOffset(aligned.RxAligned, aligned.RefAligned, ref.SampleRate_Hz);
end

det = struct();
det.Detected = logical(detected);
det.DetectedPreambleIndex = idx;
det.DetectedPreambleIndexRaw = localScalarOrNaN(idx0);
det.PreambleIndexFromPeak = double(candidateDetected);
det.TimingOffsetSamples = double(offset);
det.PeakMetric = double(peakMetric);
det.Threshold = double(threshold);
det.ThresholdMode = char(thresholdMode);
det.CorrelationPeaks = peaks;
det.CandidatePreambles = candidateSet(:);
det.MultiCandidateAboveThreshold = sum(peaks >= threshold) > 1;
det.DetInfo = detInfo;
det.CorrelationTrace = localSelectedCorrelationTrace(detInfo, candidateDetected, threshold, offset);
det.FrequencyEstimate = freqEst;
det.Occasion = occasion;
end

function [idx0, offset0, detInfo] = localDetectByWaveformCorrelation(rxWaveform, cfg, occasion, candidateSet)
rx = localVector(rxWaveform);
peaks = nan(numel(candidateSet), 1);
offsets = nan(numel(candidateSet), 1);
traceCells = cell(numel(candidateSet), 1);
for iCand = 1:numel(candidateSet)
    ref = sixgr.rach.generatePRACHWaveform(cfg, "Occasion", occasion, ...
        "PreambleIndex", double(candidateSet(iCand)));
    [peaks(iCand), offsets(iCand), lags, metrics] = localCorrelationPeak(rx, localVector(ref.Waveform));
    traceCells{iCand} = struct( ...
        "PreambleIndex", double(candidateSet(iCand)), ...
        "LagSamples", double(lags(:)), ...
        "CorrelationAbs", double(metrics(:)));
end
[bestPeak, bestIdx] = max(peaks, [], "omitnan");
if isempty(bestIdx) || ~isfinite(bestPeak)
    idx0 = [];
    bestIdx = 1;
else
    idx0 = double(candidateSet(bestIdx));
end
offset0 = offsets(:);
detInfo = struct();
detInfo.CorrelationPeaks = peaks;
detInfo.CorrelationOffsets = offsets;
detInfo.BestCandidateIndex = double(bestIdx);
detInfo.BestCorrelationTrace = traceCells{bestIdx};
detInfo.DetectorBackend = "inrepo_waveform_correlation_from_nrPRACH_symbols";
end

function [peakMetric, offsetSamples, lags, metrics] = localCorrelationPeak(rx, ref)
peakMetric = NaN;
offsetSamples = NaN;
lags = [];
metrics = [];
rx = complex(rx(:));
ref = complex(ref(:));
if isempty(rx) || isempty(ref)
    return;
end
[metrics, lags] = localNormalizedCorrelationPower(rx, ref);
if isempty(metrics)
    return;
end
[peakMetric, peakIdx] = max(metrics, [], "omitnan");
if isempty(peakIdx) || ~isfinite(peakMetric)
    return;
end
fracOffset = localParabolicPeakOffset(metrics, peakIdx);
offsetSamples = double(peakIdx) - numel(ref) + fracOffset;
end

function [metrics, lags] = localNormalizedCorrelationPower(rx, ref)
rx = complex(rx(:));
ref = complex(ref(:));
nRx = numel(rx);
nRef = numel(ref);
corrVals = conv(rx, flipud(conj(ref)), "full");
metrics = nan(size(corrVals));
lags = (1:numel(corrVals)).' - nRef;
rxPower = abs(rx).^2;
refPower = abs(ref).^2;
minOverlap = max(16, ceil(0.75 * double(nRef)));
for k = 1:numel(corrVals)
    lag = k - nRef;
    if lag < 0
        continue;
    end
    refStart = max(1, 1 - lag);
    refEnd = min(nRef, nRx - lag);
    if refEnd < refStart
        continue;
    end
    if (refEnd - refStart + 1) < minOverlap
        continue;
    end
    rxStart = lag + refStart;
    rxEnd = lag + refEnd;
    rxEnergy = sum(rxPower(rxStart:rxEnd), "omitnan");
    refEnergy = sum(refPower(refStart:refEnd), "omitnan");
    denom = double(rxEnergy) * double(refEnergy);
    if isfinite(denom) && denom > 0
        metrics(k) = double(abs(corrVals(k)).^2) / max(denom, eps);
    end
end
end

function trace = localSelectedCorrelationTrace(detInfo, preambleIndex, threshold, peakLagSamples)
emptyVec = zeros(0, 1);
trace = struct( ...
    "PreambleIndex", double(preambleIndex), ...
    "LagSamples", emptyVec, ...
    "CorrelationAbs", emptyVec, ...
    "Threshold", double(threshold), ...
    "NoiseFloor", NaN, ...
    "PeakLagSamples", double(peakLagSamples), ...
    "TraceStatus", "unavailable");
if ~(isstruct(detInfo) && isfield(detInfo, "BestCorrelationTrace") && isstruct(detInfo.BestCorrelationTrace))
    return;
end
src = detInfo.BestCorrelationTrace;
if isfield(src, "PreambleIndex")
    trace.PreambleIndex = double(src.PreambleIndex);
end
if isfield(src, "LagSamples")
    trace.LagSamples = double(src.LagSamples(:));
end
if isfield(src, "CorrelationAbs")
    trace.CorrelationAbs = double(src.CorrelationAbs(:));
end
finiteVals = trace.CorrelationAbs(isfinite(trace.CorrelationAbs));
if ~isempty(finiteVals)
    trace.NoiseFloor = localCorrelationNoiseFloor(finiteVals);
    trace.TraceStatus = "real_lls_evidence";
end
end

function noiseFloor = localCorrelationNoiseFloor(vals)
vals = double(vals(:));
vals = vals(isfinite(vals));
if isempty(vals)
    noiseFloor = NaN;
    return;
end
% Use a robust lower-tail statistic so the dominant PRACH peak does not
% inflate the displayed noise floor.
noiseFloor = median(vals(vals <= localPercentile(vals, 70)), "omitnan");
if ~isfinite(noiseFloor)
    noiseFloor = median(vals, "omitnan");
end
end

function p = localPercentile(vals, pct)
vals = sort(double(vals(:)));
vals = vals(isfinite(vals));
if isempty(vals)
    p = NaN;
    return;
end
idx = 1 + (numel(vals) - 1) * double(pct) / 100;
lo = floor(idx);
hi = ceil(idx);
if lo == hi
    p = vals(lo);
else
    frac = idx - lo;
    p = vals(lo) * (1 - frac) + vals(hi) * frac;
end
end

function fracOffset = localParabolicPeakOffset(metrics, peakIdx)
fracOffset = 0;
if peakIdx <= 1 || peakIdx >= numel(metrics)
    return;
end
yPrev = sqrt(max(0, double(metrics(peakIdx - 1))));
y0 = sqrt(max(0, double(metrics(peakIdx))));
yNext = sqrt(max(0, double(metrics(peakIdx + 1))));
if ~(isfinite(yPrev) && isfinite(y0) && isfinite(yNext))
    return;
end
denom = yPrev - 2 * y0 + yNext;
if abs(denom) <= eps
    return;
end
fracOffset = 0.5 * (yPrev - yNext) / denom;
fracOffset = max(-0.5, min(0.5, double(fracOffset)));
end

function threshold = localResolveThreshold(peaks, modeToken, explicitThreshold, cfg)
if modeToken == "fixed"
    threshold = explicitThreshold;
    return;
end

finitePeaks = peaks(isfinite(peaks));
if isempty(finitePeaks)
    threshold = explicitThreshold;
    return;
end
targetPfa = double(sixgr.util.structGet(cfg, "TargetFalseAlarmProbability", 1e-3));
robustCenter = median(finitePeaks);
robustSigma = 1.4826 * median(abs(finitePeaks - robustCenter));
gaussQuantile = max(1, sqrt(-2 * log(max(targetPfa, eps))));
threshold = max(explicitThreshold, robustCenter + gaussQuantile * robustSigma);
end

function aligned = localAlignWaveforms(rxWave, refWave, offsetSamples, cpLength)
if nargin < 4 || isempty(cpLength) || ~isfinite(double(cpLength)) || double(cpLength) < 0
    cpLength = 0;
end
rx = localVector(rxWave);
ref = localVector(refWave);
offsetSamples = max(0, round(double(offsetSamples)));
cpLength = max(0, round(double(cpLength)));
startIdx = offsetSamples + cpLength + 1;
if startIdx > numel(rx)
    aligned.RxAligned = complex([]);
    aligned.RefAligned = complex([]);
    return;
end
rx = rx(startIdx:end);
if cpLength + 1 <= numel(ref)
    ref = ref(cpLength + 1:end);
else
    ref = complex([]);
end
L = min(numel(rx), numel(ref));
aligned.RxAligned = rx(1:L);
aligned.RefAligned = ref(1:L);
end

function cpLen = localFirstCPLength(ref)
cpLen = 0;
try
    cp = double(ref.OFDMInfo.CyclicPrefixLengths(:));
    cp = cp(isfinite(cp) & cp >= 0);
    if ~isempty(cp)
        cpLen = cp(1);
    end
catch
end
end

function value = localScalarOrNaN(x)
if isempty(x)
    value = NaN;
else
    value = double(x(1));
end
end

function vec = localVector(x)
if size(x, 2) > 1
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
