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
        metric = abs(sum(rxRE(:) .* conj(ref), "omitnan")) ./ max(norm(rxRE(:)) * norm(ref), eps);
        phase = angle(sum(rxRE(:) .* conj(ref), "omitnan"));
        ampThreshold = max(6 * sqrt(max(double(rx.NoiseVariance), 0)), 0.05);
        observed = nnz(abs(rxRE(:)) > ampThreshold);
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
