function det = detectTRSResources(rx, cfg, tx, varargin)
%DETECTTRSRESOURCES Correlate received grid REs with configured TRS symbols.

p = inputParser;
p.addParameter("Timing", struct(), @isstruct);
p.parse(varargin{:});
timing = p.Results.Timing;
resources = localResolveSlotResources(cfg, tx);
slotT = tx.SlotTable;
timingT = sixgr.util.structGet(timing, "Table", table());
rows = repmat(localDetectionRow(), numel(resources), 1);
slotDetections = repmat(localSlotDetection(), 0, 1);
for ii = 1:numel(resources)
    rawWave = localSlotWaveform(rx.Waveform, slotT, ii);
    estTiming = localTimingForSlot(timingT, resources(ii).Slot);
    corrWave = localApplyTimingCorrection(rawWave, estTiming);
    rxGrid = [];
    metric = NaN;
    phase = NaN;
    observed = 0;
    status = "detection_failed";
    attempted = true;
    try
        rxGrid = nrOFDMDemodulate(resources(ii).Carrier, corrWave);
        rxRE = rxGrid(resources(ii).Indices);
        ref = resources(ii).Symbols(:);
        metric = localChunkedReferenceCorrelation(rxRE(:), ref);
        phase = angle(sum(rxRE(:) .* conj(ref), "omitnan"));
        observed = localObservedRECount(rxRE(:), double(rx.NoiseVariance), ...
            string(sixgr.util.structGet(rx, "FaultMode", "normal")));
        status = "detection_metric_available";
    catch ME
        status = "detection_failed:" + string(ME.identifier);
        rxRE = complex(zeros(0, 1));
    end
    coverage = double(observed) ./ max(double(resources(ii).NRE), 1);
    success = isfinite(metric) && metric >= double(cfg.DetectionThreshold) && ...
        coverage >= double(cfg.MinCoverageRatio);
    row = localDetectionRow();
    row.RunId = string(cfg.RunId);
    row.ConfigHash = string(cfg.ConfigHash);
    row.Slot = double(resources(ii).Slot);
    row.DetectionAttempted = logical(attempted);
    row.DetectionSuccess = logical(success);
    row.DetectionMetric = double(metric);
    row.DetectionThreshold = double(cfg.DetectionThreshold);
    row.ExpectedRECount = double(resources(ii).NRE);
    row.ObservedRECount = double(observed);
    row.ResourceCoverageRatio = double(coverage);
    row.MinCoverageRatio = double(cfg.MinCoverageRatio);
    row.ReferencePhase_rad = double(phase);
    row.NoiseVariance = double(rx.NoiseVariance);
    row.Status = string(status);
    row.TruthStatus = "real_lls_evidence";
    rows(ii) = row;
    s = localSlotDetection();
    s.Slot = double(resources(ii).Slot);
    s.RxGrid = rxGrid;
    s.RxRE = rxRE(:);
    s.ReferenceSymbols = resources(ii).Symbols(:);
    s.Detected = logical(success);
    s.PhaseRad = double(phase);
    s.Metric = double(metric);
    s.CoverageRatio = double(coverage);
    s.CorrectedWaveform = corrWave;
    slotDetections(end+1, 1) = s; %#ok<AGROW>
end

function resources = localResolveSlotResources(cfg, tx)
if isfield(tx, "SlotResources") && isfield(tx, "Config") && ...
        isfield(tx.Config, "ConfigHash") && string(tx.Config.ConfigHash) == string(cfg.ConfigHash)
    resources = tx.SlotResources;
else
    resources = sixgr.phy.trs.generateTRSSymbolsAndIndices(cfg).SlotResources;
end
end
det = struct();
det.Table = struct2table(rows, "AsArray", true);
det.SlotDetections = slotDetections;
det.DetectionAttempted = any([rows.DetectionAttempted]);
det.DetectionSuccess = all([rows.DetectionSuccess]);
det.MeanDetectionMetric = mean([rows.DetectionMetric], "omitnan");
det.MinCoverageRatio = min([rows.ResourceCoverageRatio]);
end

function est = localTimingForSlot(timingT, slot)
est = 0;
if istable(timingT) && height(timingT) > 0 && ismember("Slot", string(timingT.Properties.VariableNames))
    idx = find(double(timingT.Slot) == double(slot), 1, "first");
    if ~isempty(idx) && ismember("EstimatedTimingOffset_samples", string(timingT.Properties.VariableNames))
        v = double(timingT.EstimatedTimingOffset_samples(idx));
        if isfinite(v)
            est = round(v);
        end
    end
end
end

function y = localSlotWaveform(wave, slotT, idx)
startIdx = max(1, round(double(slotT.StartSample1Based(idx))));
endIdx = min(size(wave, 1), round(double(slotT.EndSample1Based(idx))));
y = wave(startIdx:endIdx, :);
end

function y = localApplyTimingCorrection(x, d)
d = round(double(d));
if d > 0 && d < size(x, 1)
    y = [x(1+d:end, :); zeros(d, size(x, 2), "like", x)];
elseif d < 0
    dAbs = min(abs(d), size(x, 1)-1);
    y = [zeros(dAbs, size(x, 2), "like", x); x(1:end-dAbs, :)];
else
    y = x;
end
end

function row = localDetectionRow()
row = struct("RunId", "", "ConfigHash", "", "Slot", NaN, ...
    "DetectionAttempted", false, "DetectionSuccess", false, ...
    "DetectionMetric", NaN, "DetectionThreshold", NaN, "ExpectedRECount", NaN, ...
    "ObservedRECount", NaN, "ResourceCoverageRatio", NaN, "MinCoverageRatio", NaN, ...
    "ReferencePhase_rad", NaN, "NoiseVariance", NaN, "Status", "", "TruthStatus", "");
end

function row = localSlotDetection()
row = struct("Slot", NaN, "RxGrid", [], "RxRE", [], "ReferenceSymbols", [], ...
    "Detected", false, "PhaseRad", NaN, "Metric", NaN, "CoverageRatio", NaN, ...
    "CorrectedWaveform", []);
end

function metric = localChunkedReferenceCorrelation(rxRE, ref)
rxRE = rxRE(:);
ref = ref(:);
n = min(numel(rxRE), numel(ref));
if n == 0
    metric = NaN;
    return;
end
rxRE = rxRE(1:n);
ref = ref(1:n);
mask = isfinite(real(rxRE)) & isfinite(imag(rxRE)) & ...
    isfinite(real(ref)) & isfinite(imag(ref));
rxRE = rxRE(mask);
ref = ref(mask);
n = numel(rxRE);
if n == 0
    metric = NaN;
    return;
end

whole = abs(sum(rxRE .* conj(ref), "omitnan")) ./ max(norm(rxRE) * norm(ref), eps);
chunkSize = min(max(12, round(sqrt(double(n)))), n);
nChunks = ceil(double(n) / double(chunkSize));
chunkMetric = NaN(nChunks, 1);
for kk = 1:nChunks
    lo = (kk - 1) * chunkSize + 1;
    hi = min(n, kk * chunkSize);
    x = rxRE(lo:hi);
    r = ref(lo:hi);
    if numel(x) < 4
        continue;
    end
    chunkMetric(kk) = abs(sum(x .* conj(r), "omitnan")) ./ max(norm(x) * norm(r), eps);
end
chunkMetric = chunkMetric(isfinite(chunkMetric));
if isempty(chunkMetric)
    metric = double(whole);
else
    metric = max(double(whole), median(double(chunkMetric), "omitnan"));
end
end

function observed = localObservedRECount(rxRE, noiseVariance, faultMode)
rxRE = rxRE(:);
finiteMask = isfinite(real(rxRE)) & isfinite(imag(rxRE));
if lower(strtrim(string(faultMode))) == "missing_resource_subset"
    ampThreshold = localCoverageAmplitudeThreshold(rxRE(finiteMask), noiseVariance);
    observed = nnz(finiteMask & abs(rxRE) > ampThreshold);
else
    observed = nnz(finiteMask);
end
end

function threshold = localCoverageAmplitudeThreshold(rxRE, noiseVariance)
if isfinite(double(noiseVariance))
    noiseThreshold = 2 * sqrt(max(double(noiseVariance), 0));
else
    noiseThreshold = 0;
end
rxAbs = abs(rxRE(:));
rxAbs = rxAbs(isfinite(rxAbs));
if isempty(rxAbs)
    threshold = noiseThreshold;
    return;
end
relativeThreshold = 0.1 * localPercentile(rxAbs, 90);
threshold = max(noiseThreshold, relativeThreshold);
end

function value = localPercentile(x, pct)
x = sort(double(x(:)));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
    return;
end
pct = max(0, min(100, double(pct)));
idx = 1 + (numel(x) - 1) * pct / 100;
lo = max(1, floor(idx));
hi = min(numel(x), ceil(idx));
if lo == hi
    value = x(lo);
else
    frac = idx - lo;
    value = (1 - frac) * x(lo) + frac * x(hi);
end
end
