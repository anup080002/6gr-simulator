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
addParameter(p, "DetectorBackend", "", @(x) isempty(x) || any(strcmpi(string(x), ["full_trace","toolbox_peak"])));
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
backendMode = lower(string(localFirstNonEmpty(opts.DetectorBackend, ...
    sixgr.util.structGet(cfg, "DetectorBackend", "full_trace"))));

if backendMode == "toolbox_peak"
    [idx0, offset0, detInfo] = localDetectByToolboxPRACHDetect( ...
        rxWaveform, cfg, occasion, candidateSet, thresholdMode, explicitThreshold);
else
    [idx0, offset0, detInfo] = localDetectByWaveformCorrelation(rxWaveform, cfg, occasion, candidateSet);
end

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
[threshold, thresholdInfo] = localResolveThreshold(peaks, thresholdMode, explicitThreshold, cfg, detInfo);
if backendMode == "toolbox_peak" && isfield(detInfo, "DetectionThreshold")
    tbThreshold = double(detInfo.DetectionThreshold);
    if isfinite(tbThreshold) && tbThreshold >= 0
        threshold = tbThreshold;
        thresholdInfo.BackgroundComponent = tbThreshold;
        thresholdInfo.ThresholdScale = 1;
    end
end
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
det.DetectorBackend = string(sixgr.util.structGet(detInfo, "DetectorBackend", ""));
det.RxAntennaCount = double(sixgr.util.structGet(detInfo, "RxAntennaCount", NaN));
det.CandidateCount = double(numel(candidateSet));
det.CandidatesAboveThreshold = double(sum(peaks >= threshold));
det.PDPNoiseFloor = double(sixgr.util.structGet(det.CorrelationTrace, "NoiseFloor", NaN));
det.PeakLagSamples = double(sixgr.util.structGet(det.CorrelationTrace, "PeakLagSamples", offset));
det.TimingSearchWindow = sixgr.util.structGet(detInfo, "TimingSearchWindow", struct());
det.ThresholdBackgroundComponent = double(sixgr.util.structGet(thresholdInfo, "BackgroundComponent", NaN));
det.ThresholdGlobalPeakComponent = double(sixgr.util.structGet(thresholdInfo, "GlobalPeakComponent", NaN));
det.TargetFalseAlarmProbability = double(sixgr.util.structGet(thresholdInfo, "TargetFalseAlarmProbability", NaN));
det.PeakGuardFactor = double(sixgr.util.structGet(thresholdInfo, "PeakGuardFactor", NaN));
det.PeakToThresholdRatio = localSafeRatio(peakMetric, threshold);
det.PeakToNoiseRatio = localSafeRatio(peakMetric, det.PDPNoiseFloor);
det.PeakToNoiseRatio_dB = localRatioToDb(det.PeakToNoiseRatio);
det.FrequencyEstimate = freqEst;
det.Occasion = occasion;
end

function [idx0, offset0, detInfo] = localDetectByToolboxPRACHDetect(rxWaveform, cfg, occasion, candidateSet, thresholdMode, explicitThreshold)
carrier = sixgr.util.structGet(occasion, "Carrier", []);
prach = sixgr.util.structGet(occasion, "PRACH", []);
if isempty(carrier)
    carrier = sixgr.util.structGet(cfg, "ToolboxCarrier", []);
end
if isempty(prach)
    prach = sixgr.util.structGet(cfg, "ToolboxPRACH", []);
end
carrier = localCarrierObject(carrier);
prach = localPRACHObject(prach);
if isempty(carrier) || isempty(prach)
    error("sixgr:rach:PRACHDetector:MissingToolboxConfig", ...
        "toolbox_peak PRACH detection requires ToolboxCarrier and ToolboxPRACH in the resolved PRACH config.");
end
args = {"PreambleIndex", double(candidateSet)};
if thresholdMode == "fixed" && isfinite(double(explicitThreshold))
    args = [args, {"DetectionThreshold", double(explicitThreshold)}]; %#ok<AGROW>
end
[idx0, offset, tbInfo] = nrPRACHDetect(carrier, prach, rxWaveform, args{:});
peaks = double(sixgr.util.structGet(tbInfo, "CorrelationPeaks", nan(numel(candidateSet), 1)));
peaks = peaks(:);
if numel(peaks) ~= numel(candidateSet)
    tmp = nan(numel(candidateSet), 1);
    tmp(1:min(numel(tmp), numel(peaks))) = peaks(1:min(numel(tmp), numel(peaks)));
    peaks = tmp;
end
offset0 = nan(numel(candidateSet), 1);
idxDetected = [];
if ~isempty(idx0)
    idxDetected = double(idx0(1));
    idxMatch = find(double(candidateSet(:)) == idxDetected, 1, "first");
    if ~isempty(idxMatch) && ~isempty(offset)
        offset0(idxMatch) = double(offset(1));
    end
end
[bestPeak, bestIdx] = max(peaks, [], "omitnan");
if isempty(bestIdx) || ~isfinite(bestPeak)
    bestIdx = 1;
    bestPeak = NaN;
end
bestOffset = NaN;
if ~isempty(offset) && ~isempty(idxDetected)
    idxMatch = find(double(candidateSet(:)) == idxDetected, 1, "first");
    if ~isempty(idxMatch)
        bestIdx = idxMatch;
    end
    bestOffset = double(offset(1));
    if isfinite(bestPeak) && bestIdx <= numel(peaks)
        peakMax = max(double(peaks), [], "omitnan");
        if ~(isfinite(peakMax) && peakMax >= 0)
            peakMax = double(bestPeak);
        end
        peaks(bestIdx) = max(double(peaks(bestIdx)), peakMax + max(eps(peakMax), 1e-12));
        bestPeak = double(peaks(bestIdx));
    end
elseif bestIdx <= numel(offset0)
    bestOffset = double(offset0(bestIdx));
end
threshold = double(sixgr.util.structGet(tbInfo, "DetectionThreshold", explicitThreshold));
detInfo = struct();
detInfo.CorrelationPeaks = peaks;
detInfo.CorrelationOffsets = offset0;
detInfo.BestCandidateIndex = double(bestIdx);
detInfo.BestCorrelationTrace = struct( ...
    "PreambleIndex", double(candidateSet(bestIdx)), ...
    "LagSamples", double(bestOffset), ...
    "CorrelationAbs", double(bestPeak), ...
    "NoiseFloor", localCorrelationNoiseFloor(peaks), ...
    "TraceStatus", "toolbox_peak_only_evidence");
detInfo.CandidateResults = table(double(candidateSet(:)), peaks(:), offset0(:), ...
    repmat(double(size(rxWaveform, 2)), numel(candidateSet), 1), ...
    'VariableNames', {'PreambleIndex','PeakMetric','PeakLagSamples','AntennaCount'});
detInfo.RxAntennaCount = double(size(rxWaveform, 2));
detInfo.NumRepeatedSymbols = NaN;
detInfo.TimingSearchWindow = localEmptyTimingSearchWindow();
detInfo.TimingSearchWindow.SearchApplied = true;
detInfo.TimingSearchWindow.Source = "nrPRACHDetect_internal_search";
detInfo.TimingSearchWindow.SearchLagCount = double(numel(peaks));
detInfo.TimingSearchWindow.FiniteLagCount = double(sum(isfinite(peaks)));
detInfo.DetectorBackend = "matlab_5g_toolbox_nrPRACHDetect_peak";
detInfo.ProcessingFlow = "nrPRACHDetect_carrier_prach_waveform_candidate_peak_search";
detInfo.DetectionThreshold = threshold;
end

function carrier = localCarrierObject(carrierIn)
carrier = carrierIn;
if isa(carrier, "nrCarrierConfig")
    return;
end
if ~(isstruct(carrierIn) && ~isempty(fieldnames(carrierIn)))
    carrier = [];
    return;
end
carrier = nrCarrierConfig;
carrier.SubcarrierSpacing = double(sixgr.util.structGet(carrierIn, "SubcarrierSpacing", 15));
carrier.NSizeGrid = double(sixgr.util.structGet(carrierIn, "NSizeGrid", 52));
carrier.NStartGrid = double(sixgr.util.structGet(carrierIn, "NStartGrid", 0));
carrier.NCellID = double(sixgr.util.structGet(carrierIn, "NCellID", 1));
carrier.NSlot = double(sixgr.util.structGet(carrierIn, "NSlot", 0));
carrier.CyclicPrefix = char(string(sixgr.util.structGet(carrierIn, "CyclicPrefix", "normal")));
end

function prach = localPRACHObject(prachIn)
prach = prachIn;
if isa(prach, "nrPRACHConfig")
    return;
end
if ~(isstruct(prachIn) && ~isempty(fieldnames(prachIn)))
    prach = [];
    return;
end
prach = nrPRACHConfig;
prach.FrequencyRange = char(string(sixgr.util.structGet(prachIn, "FrequencyRange", "FR1")));
prach.DuplexMode = char(string(sixgr.util.structGet(prachIn, "DuplexMode", "FDD")));
prach.ConfigurationIndex = double(sixgr.util.structGet(prachIn, "ConfigurationIndex", 16));
prach.SubcarrierSpacing = double(sixgr.util.structGet(prachIn, "SubcarrierSpacing", 1.25));
prach.SequenceIndex = double(sixgr.util.structGet(prachIn, "SequenceIndex", 0));
prach.PreambleIndex = double(sixgr.util.structGet(prachIn, "PreambleIndex", 0));
prach.RestrictedSet = char(string(sixgr.util.structGet(prachIn, "RestrictedSet", "UnrestrictedSet")));
prach.ZeroCorrelationZone = double(sixgr.util.structGet(prachIn, "ZeroCorrelationZone", 0));
prach.FrequencyStart = double(sixgr.util.structGet(prachIn, "FrequencyStart", 0));
prach.NPRACHSlot = double(sixgr.util.structGet(prachIn, "NPRACHSlot", 0));
try
    prach.TimeIndex = double(sixgr.util.structGet(prachIn, "TimeIndex", 0));
catch
end
end

function [idx0, offset0, detInfo] = localDetectByWaveformCorrelation(rxWaveform, cfg, occasion, candidateSet)
rx = localMatrix(rxWaveform);
try
    [idx0, offset0, detInfo] = localDetectByToolboxPRACHDetect( ...
        rxWaveform, cfg, occasion, candidateSet, "auto", []);
    bestIdx = round(double(sixgr.util.structGet(detInfo, "BestCandidateIndex", 1)));
    bestIdx = max(1, min(numel(candidateSet), bestIdx));
    ref = sixgr.rach.generatePRACHWaveform(cfg, "Occasion", occasion, ...
        "PreambleIndex", double(candidateSet(bestIdx)));
    [tracePeak, traceOffset, lags, metrics, antPeaks, antOffsets, timingWindow] = localCorrelationPeak(rx, ref, cfg);
    peaks = double(sixgr.util.structGet(detInfo, "CorrelationPeaks", nan(numel(candidateSet), 1)));
    offsets = double(sixgr.util.structGet(detInfo, "CorrelationOffsets", nan(numel(candidateSet), 1)));
    if numel(peaks) ~= numel(candidateSet)
        peaks = nan(numel(candidateSet), 1);
    end
    if numel(offsets) ~= numel(candidateSet)
        offsets = nan(numel(candidateSet), 1);
    end
    if isfinite(tracePeak)
        peaks(bestIdx) = max(peaks(bestIdx), double(tracePeak));
    end
    if isfinite(traceOffset)
        offsets(bestIdx) = double(traceOffset);
    end
    if isempty(idx0) && any(isfinite(peaks))
        idx0 = double(candidateSet(bestIdx));
    end
    offset0 = offsets(:);
    detInfo.CorrelationPeaks = peaks(:);
    detInfo.CorrelationOffsets = offsets(:);
    detInfo.BestCandidateIndex = double(bestIdx);
    detInfo.BestCorrelationTrace = struct( ...
        "PreambleIndex", double(candidateSet(bestIdx)), ...
        "LagSamples", double(lags(:)), ...
        "CorrelationAbs", double(metrics(:)), ...
        "AntennaPeakMetrics", double(antPeaks(:)), ...
        "AntennaPeakLags", double(antOffsets(:)), ...
        "TraceStatus", "real_lls_evidence");
    detInfo.NumRepeatedSymbols = localFirstFinite(NaN, localRepeatedSymbolCount(ref));
    detInfo.TimingSearchWindow = timingWindow;
    detInfo.DetectorBackend = "matlab_5g_toolbox_nrPRACHDetect_plus_best_candidate_full_trace";
    detInfo.ProcessingFlow = "nrPRACHDetect_all_candidates_then_inrepo_best_candidate_lag_trace";
    return;
catch
    % Fall through to the legacy all-candidate trace path when Toolbox
    % detection is unavailable for a focused PRACH evidence run.
end
peaks = nan(numel(candidateSet), 1);
offsets = nan(numel(candidateSet), 1);
traceCells = cell(numel(candidateSet), 1);
timingWindow = struct();
candidateRows = repmat(struct( ...
    "PreambleIndex", NaN, ...
    "PeakMetric", NaN, ...
    "PeakLagSamples", NaN, ...
    "AntennaCount", size(rx, 2), ...
    "AntennaPeakMetrics", "", ...
    "AntennaPeakLags", ""), numel(candidateSet), 1);
numRepeatedSymbols = NaN;
for iCand = 1:numel(candidateSet)
    ref = sixgr.rach.generatePRACHWaveform(cfg, "Occasion", occasion, ...
        "PreambleIndex", double(candidateSet(iCand)));
    numRepeatedSymbols = localFirstFinite(numRepeatedSymbols, localRepeatedSymbolCount(ref));
    [peaks(iCand), offsets(iCand), lags, metrics, antPeaks, antOffsets, timingWindow] = localCorrelationPeak(rx, ref, cfg);
    traceCells{iCand} = struct( ...
        "PreambleIndex", double(candidateSet(iCand)), ...
        "LagSamples", double(lags(:)), ...
        "CorrelationAbs", double(metrics(:)), ...
        "AntennaPeakMetrics", double(antPeaks(:)), ...
        "AntennaPeakLags", double(antOffsets(:)));
    candidateRows(iCand).PreambleIndex = double(candidateSet(iCand));
    candidateRows(iCand).PeakMetric = double(peaks(iCand));
    candidateRows(iCand).PeakLagSamples = double(offsets(iCand));
    candidateRows(iCand).AntennaCount = double(size(rx, 2));
    candidateRows(iCand).AntennaPeakMetrics = strjoin(string(double(antPeaks(:)).'), "|");
    candidateRows(iCand).AntennaPeakLags = strjoin(string(double(antOffsets(:)).'), "|");
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
detInfo.CandidateResults = struct2table(candidateRows, "AsArray", true);
detInfo.RxAntennaCount = double(size(rx, 2));
detInfo.NumRepeatedSymbols = double(numRepeatedSymbols);
detInfo.TimingSearchWindow = timingWindow;
detInfo.DetectorBackend = "inrepo_section5_prach_waveform_matched_filter_noncoherent_pdp";
detInfo.ProcessingFlow = "rx_waveform_per_antenna_correlation_pdp_noncoherent_combining_peak_window_threshold_ta";
end

function [peakMetric, offsetSamples, lags, metrics, antPeaks, antOffsets, timingWindow] = localCorrelationPeak(rx, ref, cfg)
peakMetric = NaN;
offsetSamples = NaN;
lags = [];
metrics = [];
antPeaks = zeros(0, 1);
antOffsets = zeros(0, 1);
timingWindow = localEmptyTimingSearchWindow();
rx = complex(rx);
refInfo = localReferenceInfo(ref);
refWaveform = complex(localVector(sixgr.util.structGet(refInfo, "Waveform", [])));
if isempty(rx) || isempty(refWaveform)
    return;
end
if isvector(rx)
    rx = rx(:);
end
numAnt = max(1, size(rx, 2));
metricCells = cell(numAnt, 1);
lagCells = cell(numAnt, 1);
antPeaks = nan(numAnt, 1);
antOffsets = nan(numAnt, 1);
for iAnt = 1:numAnt
    [metricCells{iAnt}, lagCells{iAnt}] = localNormalizedCorrelationPower(rx(:, iAnt), refWaveform);
    if isempty(metricCells{iAnt})
        continue;
    end
    [antPeaks(iAnt), antIdx] = max(metricCells{iAnt}, [], "omitnan");
    if ~isempty(antIdx) && isfinite(double(antPeaks(iAnt)))
        antOffsets(iAnt) = double(antIdx) - numel(refWaveform) + localParabolicPeakOffset(metricCells{iAnt}, antIdx);
    end
end
[metrics, lags] = localNoncoherentAverage(metricCells, lagCells);
if isempty(metrics)
    return;
end
[searchMask, timingWindow] = localTimingSearchMask(lags, metrics, cfg, refInfo);
peakMetrics = metrics;
if any(searchMask & isfinite(peakMetrics))
    peakMetrics(~searchMask) = NaN;
    timingWindow.SearchApplied = true;
else
    timingWindow.SearchApplied = false;
end
[peakMetric, peakIdx] = max(peakMetrics, [], "omitnan");
if isempty(peakIdx) || ~isfinite(peakMetric)
    return;
end
fracOffset = localParabolicPeakOffset(metrics, peakIdx);
offsetSamples = double(peakIdx) - numel(refWaveform) + fracOffset;
end

function [combined, lags] = localNoncoherentAverage(metricCells, lagCells)
combined = [];
lags = [];
validIdx = find(cellfun(@(x) ~isempty(x), metricCells), 1, "first");
if isempty(validIdx)
    return;
end
lags = lagCells{validIdx}(:);
n = numel(lags);
M = nan(n, numel(metricCells));
for iAnt = 1:numel(metricCells)
    m = metricCells{iAnt};
    if isempty(m)
        continue;
    end
    li = lagCells{iAnt}(:);
    if numel(m) ~= n || numel(li) ~= n || any(li ~= lags)
        [common, ia, ib] = intersect(lags, li, "stable");
        if isempty(common)
            continue;
        end
        if numel(common) ~= n
            M = M(ia, :);
            lags = common;
            n = numel(lags);
        end
        tmp = nan(n, 1);
        tmp(1:numel(ia)) = double(m(ib));
        M(:, iAnt) = tmp;
    else
        M(:, iAnt) = double(m(:));
    end
end
combined = mean(M, 2, "omitnan");
combined(all(~isfinite(M), 2)) = NaN;
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
rxPower(~isfinite(rxPower)) = 0;
refPower(~isfinite(refPower)) = 0;
rxCum = [0; cumsum(double(rxPower(:)))];
refCum = [0; cumsum(double(refPower(:)))];

lagVals = 0:(nRx - 1);
if isempty(lagVals)
    return;
end
overlap = min(double(nRef), double(nRx) - double(lagVals));
valid = overlap >= minOverlap;
if ~any(valid)
    return;
end

lagVals = lagVals(valid);
overlap = overlap(valid);
kIdx = double(lagVals) + double(nRef);
rxStart = double(lagVals) + 1;
rxEnd = double(lagVals) + overlap;
refEnd = overlap;

rxEnergy = rxCum(rxEnd + 1) - rxCum(rxStart);
refEnergy = refCum(refEnd + 1) - refCum(1);
denom = double(rxEnergy(:)) .* double(refEnergy(:));
metricVals = double(abs(corrVals(kIdx)).^2) ./ max(denom, eps);
metricVals(~(isfinite(denom) & denom > 0)) = NaN;
metrics(kIdx) = metricVals;
end

function [mask, win] = localTimingSearchMask(lags, metrics, cfg, refInfo)
win = localResolveTimingSearchWindow(cfg, refInfo);
lags = double(lags(:));
metrics = double(metrics(:));
mask = isfinite(lags) & isfinite(metrics) & ...
    lags >= double(win.MinLagSamples) & lags <= double(win.MaxLagSamples);
win.FiniteLagCount = double(sum(isfinite(metrics)));
win.SearchLagCount = double(sum(mask));
end

function win = localResolveTimingSearchWindow(cfg, refInfo)
sr = localFirstFinite( ...
    sixgr.util.structGet(cfg, "SampleRate_Hz", NaN), ...
    sixgr.util.structGet(refInfo, "SampleRate_Hz", NaN));
tol = localTimingToleranceSamples(cfg, sr);
cpLen = double(localFirstCPLength(refInfo));
explicit = localFiniteVector(localFirstNonEmpty( ...
    sixgr.util.structGet(cfg, "PrachTimingSearchWindowSamples", []), ...
    sixgr.util.structGet(cfg, "TimingSearchWindowSamples", [])));
if numel(explicit) >= 2
    minLag = min(explicit(1:2));
    maxLag = max(explicit(1:2));
    source = "explicit_config_window";
elseif numel(explicit) == 1
    minLag = 0;
    maxLag = explicit(1);
    source = "explicit_config_window";
else
    offsets = abs(localFiniteVector(sixgr.util.structGet(cfg, "TimingOffsetSweepSamples", [])));
    if isempty(offsets)
        offsets = 0;
    end
    timingUncertainty = localTimingUncertaintySamples(cfg, sr);
    propagation = localCellRadiusPropagationSamples(cfg, sr);
    delaySpread = localDelaySpreadSamples(cfg, sr);
    candidates = [max(offsets) + tol, cpLen, timingUncertainty + tol, propagation + delaySpread + tol, 32];
    candidates = candidates(isfinite(candidates) & candidates >= 0);
    minLag = 0;
    maxLag = max(candidates);
    source = "derived_from_prach_timing_budget";
end
guard = max(4, ceil(0.25 * max(1, tol)));
maxLag = max(maxLag, minLag) + guard;
win = localEmptyTimingSearchWindow();
win.MinLagSamples = double(max(0, floor(minLag)));
win.MaxLagSamples = double(ceil(maxLag));
win.Source = source;
win.SampleRateHz = double(sr);
win.CPLengthSamples = double(cpLen);
win.TimingToleranceSamples = double(tol);
win.SearchApplied = false;
end

function tol = localTimingToleranceSamples(cfg, sampleRateHz)
tolUs = double(sixgr.util.structGet(cfg, "TimingTolerance_us", NaN));
sr = double(sampleRateHz);
if isfinite(tolUs) && isfinite(sr) && sr > 0
    tol = tolUs * sr / 1e6;
else
    tol = NaN;
end
if ~(isfinite(tol) && tol >= 0)
    tol = 1.5;
end
tol = max(1.5, double(tol));
end

function samples = localTimingUncertaintySamples(cfg, sampleRateHz)
sr = double(sampleRateHz);
if ~(isfinite(sr) && sr > 0)
    samples = NaN;
    return;
end
maxUs = double(sixgr.util.structGet(cfg, "TimingUncertaintyMax_us", NaN));
if ~(isfinite(maxUs) && maxUs >= 0)
    samples = NaN;
else
    samples = maxUs * sr / 1e6;
end
end

function samples = localCellRadiusPropagationSamples(cfg, sampleRateHz)
sr = double(sampleRateHz);
radiusM = double(sixgr.util.structGet(cfg, "CellRadius_m", NaN));
if ~(isfinite(sr) && sr > 0 && isfinite(radiusM) && radiusM >= 0)
    samples = NaN;
else
    samples = radiusM / 299792458 * sr;
end
end

function samples = localDelaySpreadSamples(cfg, sampleRateHz)
sr = double(sampleRateHz);
delayNs = double(sixgr.util.structGet(cfg, "DelaySpread_ns", NaN));
if ~(isfinite(sr) && sr > 0 && isfinite(delayNs) && delayNs >= 0)
    samples = NaN;
else
    samples = 5 * delayNs * 1e-9 * sr;
end
end

function values = localFiniteVector(raw)
try
    values = double(raw(:));
catch
    values = [];
end
values = values(isfinite(values));
end

function info = localReferenceInfo(ref)
if isstruct(ref)
    info = ref;
else
    info = struct("Waveform", ref);
end
end

function win = localEmptyTimingSearchWindow()
win = struct( ...
    "MinLagSamples", NaN, ...
    "MaxLagSamples", NaN, ...
    "Source", "", ...
    "SampleRateHz", NaN, ...
    "CPLengthSamples", NaN, ...
    "TimingToleranceSamples", NaN, ...
    "FiniteLagCount", 0, ...
    "SearchLagCount", 0, ...
    "SearchApplied", false);
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
    if isfield(src, "NoiseFloor") && isfinite(double(src.NoiseFloor))
        trace.NoiseFloor = double(src.NoiseFloor);
    else
        trace.NoiseFloor = localCorrelationNoiseFloor(finiteVals);
    end
    if isfield(src, "TraceStatus") && strlength(strtrim(string(src.TraceStatus))) > 0
        trace.TraceStatus = string(src.TraceStatus);
    else
        trace.TraceStatus = "real_lls_evidence";
    end
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

function [threshold, info] = localResolveThreshold(peaks, modeToken, explicitThreshold, cfg, detInfo)
info = struct( ...
    "BackgroundComponent", NaN, ...
    "GlobalPeakComponent", NaN, ...
    "BackgroundPDPLevel", NaN, ...
    "ThresholdScale", NaN, ...
    "TargetFalseAlarmProbability", NaN, ...
    "PeakGuardFactor", NaN);
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
peakGuardFactor = double(sixgr.util.structGet(cfg, "PrachPeakGuardFactor", ...
    sixgr.util.structGet(cfg, "PeakThresholdFactor", 0.1)));
if ~(isfinite(peakGuardFactor) && peakGuardFactor >= 0 && peakGuardFactor <= 1)
    peakGuardFactor = 0.1;
end
numRxAnt = double(sixgr.util.structGet(detInfo, "RxAntennaCount", ...
    sixgr.util.structGet(cfg, "NumRxAntennas", 1)));
scale = localFlexRANPRACHThresholdScale(cfg, numRxAnt);
background = NaN;
try
    tr = detInfo.BestCorrelationTrace;
    background = localBackgroundPDPLevel(double(tr.CorrelationAbs(:)), double(sixgr.util.structGet(tr, "PeakLagSamples", NaN)), cfg);
catch
end
if ~(isfinite(background) && background >= 0)
    robustCenter = median(finitePeaks);
    robustSigma = 1.4826 * median(abs(finitePeaks - robustCenter));
    gaussQuantile = max(1, sqrt(-2 * log(max(targetPfa, eps))));
    backgroundComponent = robustCenter + gaussQuantile * robustSigma;
else
    backgroundComponent = background * scale;
end
globalPeakComponent = max(finitePeaks) * peakGuardFactor;
threshold = max([double(explicitThreshold), double(backgroundComponent), double(globalPeakComponent)], [], "omitnan");
if ~(isfinite(threshold) && threshold >= 0)
    threshold = explicitThreshold;
end
info.BackgroundComponent = double(backgroundComponent);
info.GlobalPeakComponent = double(globalPeakComponent);
info.BackgroundPDPLevel = double(background);
info.ThresholdScale = double(scale);
info.TargetFalseAlarmProbability = double(targetPfa);
info.PeakGuardFactor = double(peakGuardFactor);
end

function scale = localFlexRANPRACHThresholdScale(cfg, numRxAnt)
fmt = upper(strtrim(string(sixgr.util.structGet(cfg, "ResolvedPRACHFormat", ...
    sixgr.util.structGet(cfg, "RequestedPRACHFormat", "")))));
fmt = erase(fmt, "FORMAT");
if strlength(fmt) == 0
    fmt = "0";
end
ant = [1 2 4];
switch fmt
    case {"0"}
        vals = [17.5320 11.7240 8.5440];
    case {"A1", "B1"}
        vals = [11.3570 8.3450 6.6500];
    case {"A2", "B2"}
        vals = [8.3450 5.1500 4.1660];
    case {"C2"}
        vals = [14.3450 11.1500 10.1660];
    case {"A3", "B3"}
        vals = [7.2410 5.0130 4.2870];
    case {"B4"}
        vals = [6.0130 5.2870 4.8430];
    otherwise
        vals = [16.8390 11.3570 8.3450];
end
numRxAnt = max(1, double(numRxAnt));
scale = interp1(ant, vals, min(max(numRxAnt, ant(1)), ant(end)), "linear");
if numRxAnt > ant(end)
    scale = vals(end);
end
end

function background = localBackgroundPDPLevel(vals, peakLagSamples, cfg)
vals = double(vals(:));
vals = vals(isfinite(vals));
if isempty(vals)
    background = NaN;
    return;
end
peakNeighborhood = round(double(sixgr.util.structGet(cfg, "PrachPeakNeighborhoodSamples", NaN)));
if ~(isfinite(peakNeighborhood) && peakNeighborhood >= 0)
    lra = double(sixgr.util.structGet(cfg, "ToolboxPRACH.LRA", NaN));
    if isfinite(lra) && lra > 200
        peakNeighborhood = 4;
    else
        peakNeighborhood = 8;
    end
end
[~, peakIdx] = max(vals, [], "omitnan");
if isfinite(peakLagSamples) && peakLagSamples >= 0 && peakLagSamples < numel(vals)
    peakIdx = max(1, min(numel(vals), round(peakLagSamples) + 1));
end
keep = true(size(vals));
lo = max(1, peakIdx - peakNeighborhood);
hi = min(numel(vals), peakIdx + peakNeighborhood);
keep(lo:hi) = false;
bg = vals(keep);
if isempty(bg)
    bg = vals;
end
background = mean(bg, "omitnan");
if ~(isfinite(background) && background >= 0)
    background = median(vals, "omitnan");
end
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

function mat = localMatrix(x)
mat = complex(x);
if isvector(mat)
    mat = mat(:);
end
if ndims(mat) > 2
    mat = reshape(mat, size(mat, 1), []);
end
end

function n = localRepeatedSymbolCount(ref)
n = NaN;
try
    lra = double(ref.PRACH.LRA);
    if isfinite(lra) && lra > 0
        n = max(1, round(numel(ref.Symbols) / lra));
    end
catch
end
end

function value = localFirstFinite(varargin)
value = NaN;
for iArg = 1:nargin
    raw = double(varargin{iArg});
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = raw(1);
        return;
    end
end
end

function ratio = localSafeRatio(num, den)
num = double(num);
den = double(den);
if isfinite(num) && isfinite(den) && den > 0
    ratio = num / den;
else
    ratio = NaN;
end
end

function db = localRatioToDb(ratio)
ratio = double(ratio);
if isfinite(ratio) && ratio > 0
    db = 10 * log10(ratio);
else
    db = NaN;
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
