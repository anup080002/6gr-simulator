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

[idx0, offset0, detInfo] = nrPRACHDetect(occasion.Carrier, occasion.PRACH, rxWaveform, ...
    "DetectionThreshold", 0, "PreambleIndex", candidateSet);

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
    idx = double(idx0(1));
    offset = double(offset0(1));
else
    idx = NaN;
    offset = NaN;
end

freqEst = struct("Valid", false, "EstimateHz", NaN, "Estimator", "disabled");
if detected && enableFreq
    ref = sixgr.rach.generatePRACHWaveform(cfg, "Occasion", occasion, "PreambleIndex", idx);
    aligned = localAlignWaveforms(rxWaveform, ref.Waveform, round(offset));
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
det.FrequencyEstimate = freqEst;
det.Occasion = occasion;
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
