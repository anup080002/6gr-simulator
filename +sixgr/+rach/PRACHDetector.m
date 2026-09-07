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
    [idx0, offset0, detInfo] = localDetectByWaveformCorrelation( ...
        rxWaveform, cfg, occasion, candidateSet, thresholdMode, explicitThreshold);
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
if ~isempty(idx0)
    % Root-sequence peaks can tie across cyclic shifts. Preserve the
    % measured peaks exactly and use the detector's decoded identity;
    % never perturb a correlation value to force max() to pick it.
    maxIdx=find(candidateSet==double(idx0(1)),1);
    if isempty(maxIdx)
        error('sixgr:rach:PRACHDetector:UnexpectedDetectedCandidate','Toolbox detected an unrequested preamble.');
    end
    candidateDetected=candidateSet(maxIdx);
    peakMetric=peaks(maxIdx);
end
if contains(string(detInfo.DetectorBackend),"nrPRACHDetect")
    % Do not calculate a legacy CFAR/peak-guard threshold, overwrite it
    % with nrPRACHDetect's value, then export the unused heuristic as if
    % it controlled this decision. Default thresholds are receiver policy,
    % not a single-observation proof of a requested false-alarm rate.
    threshold=double(detInfo.DetectionThreshold);
    validateattributes(threshold,{'numeric'},{'scalar','real','finite','>=',0,'<=',1});
    thresholdInfo=localEmptyThresholdInfo();
    if thresholdMode=="fixed"
        thresholdInfo.Source="configured_fixed_nrPRACHDetect";
    else
        thresholdInfo.Source="nrPRACHDetect_default_format_LRA_repetitions_rx_antennas";
    end
else
    error('sixgr:rach:PRACHDetector:UnknownDecisionBackend', ...
        'PRACH decisions must retain the actual nrPRACHDetect threshold.');
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
det.ThresholdSource = thresholdInfo.Source;
det.ThresholdCalibrationStatus = "single_detection_not_statistical_qualification";
det.ConfiguredTargetFalseAlarmProbability = double(sixgr.util.structGet(cfg,"TargetFalseAlarmProbability",NaN));
det.CorrelationPeaks = peaks;
det.CandidatePreambles = candidateSet(:);
toolboxDetections = double(sixgr.util.structGet( ...
    detInfo, "DetectedPreambleIndicesRaw", []));
toolboxDetections = unique(toolboxDetections(isfinite(toolboxDetections)));
if contains(string(sixgr.util.structGet( ...
        detInfo, "DetectorBackend", "")), "nrPRACHDetect")
    % nrPRACHDetect correlation peaks are root-sequence metrics.  Multiple
    % cyclic shifts of the same root can therefore have identical peaks;
    % that is not a multi-preamble detection.  The detector's returned
    % preamble-index set is the authoritative ambiguity evidence.
    candidatesAboveThreshold = numel(toolboxDetections);
    multiCandidate = candidatesAboveThreshold > 1;
else
    candidatesAboveThreshold = sum(peaks >= threshold);
    multiCandidate = candidatesAboveThreshold > 1;
end
det.MultiCandidateAboveThreshold = logical(multiCandidate);
det.DetInfo = detInfo;
det.CorrelationTrace = localSelectedCorrelationTrace(detInfo, candidateDetected, threshold, offset);
det.DetectorBackend = string(sixgr.util.structGet(detInfo, "DetectorBackend", ""));
det.RxAntennaCount = double(sixgr.util.structGet(detInfo, "RxAntennaCount", NaN));
det.CandidateCount = double(numel(candidateSet));
det.CandidatesAboveThreshold = double(candidatesAboveThreshold);
det.PDPNoiseFloor = double(sixgr.util.structGet(det.CorrelationTrace, "NoiseFloor", NaN));
det.PeakLagSamples = double(sixgr.util.structGet(det.CorrelationTrace, "PeakLagSamples", offset));
det.TimingSearchWindow = sixgr.util.structGet(detInfo, "TimingSearchWindow", struct());
det.ThresholdBackgroundComponent = double(sixgr.util.structGet(thresholdInfo, "BackgroundComponent", NaN));
det.ThresholdGlobalPeakComponent = double(sixgr.util.structGet(thresholdInfo, "GlobalPeakComponent", NaN));
det.TargetFalseAlarmProbability = double(sixgr.util.structGet(thresholdInfo, "TargetFalseAlarmProbability", NaN));
det.PeakGuardFactor = double(sixgr.util.structGet(thresholdInfo, "PeakGuardFactor", NaN));
det.PeakToThresholdRatio = localSafeRatio(peakMetric, threshold);
tracePeak=double(sixgr.util.structGet(detInfo,'DiagnosticMatchedFilterPeak',peakMetric));
det.PeakToNoiseRatio = localSafeRatio(tracePeak, det.PDPNoiseFloor);
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
detInfo.DetectedPreambleIndicesRaw = double(idx0(:));
detInfo.DetectedTimingOffsetsRaw = double(offset(:));
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
duplexMode = sixgr.util.structGet(prachIn, "DuplexMode", []);
if isempty(duplexMode)
    error("sixgr:rach:PRACHDetector:MissingDuplexMode", ...
        "A serialized PRACH runtime object must preserve DuplexMode.");
end
prach.DuplexMode = char(sixgr.phy.frame.resolveDuplexMode( ...
    struct("DuplexMode", duplexMode)));
prach.ConfigurationIndex = double(sixgr.util.structGet(prachIn, "ConfigurationIndex", 16));
prach.SubcarrierSpacing = double(sixgr.util.structGet(prachIn, "SubcarrierSpacing", 1.25));
prach.SequenceIndex = double(sixgr.util.structGet(prachIn, "SequenceIndex", 0));
prach.PreambleIndex = double(sixgr.util.structGet(prachIn, "PreambleIndex", 0));
prach.RestrictedSet = char(string(sixgr.util.structGet(prachIn, "RestrictedSet", "UnrestrictedSet")));
prach.ZeroCorrelationZone = double(sixgr.util.structGet(prachIn, "ZeroCorrelationZone", 0));
prach.FrequencyStart = double(sixgr.util.structGet(prachIn, "FrequencyStart", 0));
% Preserve the exact canonical occasion when rebuilding a Toolbox object
% from the serializable PRACH snapshot.  For short-preamble rows such as
% FR1 unpaired index 157/B4, ActivePRACHSlot=0 is invalid and must not be
% allowed to replace the resolver-owned value.
prach.ActivePRACHSlot = double(sixgr.util.structGet( ...
    prachIn, "ActivePRACHSlot", 0));
prach.NPRACHSlot = double(sixgr.util.structGet(prachIn, "NPRACHSlot", 0));
prach.TimeIndex = double(sixgr.util.structGet(prachIn, "TimeIndex", 0));
prach.FrequencyIndex = double(sixgr.util.structGet( ...
    prachIn, "FrequencyIndex", 0));
end

function [idx0, offset0, detInfo] = localDetectByWaveformCorrelation(rxWaveform, cfg, occasion, candidateSet, thresholdMode, explicitThreshold)
% The NR receiver decides identity/threshold. The full waveform correlation
% supplies a diagnostic trace and refines timing only for a detected index.
% Never mix maxima from two statistics or silently switch detector backends.
rx=localMatrix(rxWaveform);
[idx0,offset0,detInfo]=localDetectByToolboxPRACHDetect( ...
    rxWaveform,cfg,occasion,candidateSet,thresholdMode,explicitThreshold);
bestIdx=double(detInfo.BestCandidateIndex);
ref=sixgr.rach.generatePRACHWaveform(cfg,'Occasion',occasion, ...
    'PreambleIndex',double(candidateSet(bestIdx)));
[tracePeak,traceOffset,lags,metrics,antPeaks,antOffsets,timingWindow]= ...
    localCorrelationPeak(rx,ref,cfg);
if ~isempty(idx0) && isfinite(traceOffset)
    offset0(bestIdx)=double(traceOffset);
end
detInfo.CorrelationOffsets=offset0(:);
detInfo.DiagnosticMatchedFilterPeak=double(tracePeak);
detInfo.BestCorrelationTrace=struct( ...
    'PreambleIndex',double(candidateSet(bestIdx)), ...
    'LagSamples',double(lags(:)),'CorrelationAbs',double(metrics(:)), ...
    'AntennaPeakMetrics',double(antPeaks(:)), ...
    'AntennaPeakLags',double(antOffsets(:)), ...
    'TraceStatus',"real_lls_evidence");
detInfo.NumRepeatedSymbols=localRepeatedSymbolCount(ref);
detInfo.TimingSearchWindow=timingWindow;
detInfo.DetectorBackend="matlab_5g_toolbox_nrPRACHDetect_plus_best_candidate_full_trace";
detInfo.ProcessingFlow="nrPRACHDetect_identity_and_threshold_then_waveform_trace_and_timing_refinement";
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
corrVals = sixgr.rach.fullWaveformCorrelation(rx,ref);
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
trace.DecisionThreshold=double(threshold);
trace.ThresholdSource="nrPRACHDetect_decision_statistic";
if contains(string(detInfo.DetectorBackend),"full_trace")
    % The auxiliary matched-filter trace is not nrPRACHDetect's statistic.
    % Its y-axis must not carry the other statistic's decision threshold.
    trace.Threshold=NaN;
    trace.ThresholdSource="not_applicable_diagnostic_matched_filter_trace";
end
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

function info=localEmptyThresholdInfo()
info = struct( ...
    "BackgroundComponent", NaN, ...
    "GlobalPeakComponent", NaN, ...
    "BackgroundPDPLevel", NaN, ...
    "ThresholdScale", NaN, ...
    "TargetFalseAlarmProbability", NaN, ...
    "PeakGuardFactor", NaN, "Source", "");
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
