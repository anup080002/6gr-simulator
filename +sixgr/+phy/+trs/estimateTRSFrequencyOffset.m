function freq = estimateTRSFrequencyOffset(det, cfg, tx, rx)
%ESTIMATETRSFREQUENCYOFFSET Estimate CFO from TRS channel phase drift.
%
% The estimator is intentionally based on per-RE LS TRS channel estimates:
% H(k,n) = Y_TRS(k,n) / X_TRS(k,n).  The inter-slot phase increment is then
% angle(sum_k H_late(k) * conj(H_early(k))).  This later-times-conj-earlier
% ordering gives a positive estimate for a positive injected frequency offset,
% and the elapsed time is the measured full sample-time gap between TRS slots.

slotDet = det.SlotDetections;
slotT = tx.SlotTable;
physicalDopplerHz = localPhysicalDopplerHz(rx);
candidateRows = repmat(localFrequencyRow(), 0, 1);
pairEstimates = [];
pairWeights = [];

attempted = true;
for ii = 1:max(0, numel(slotDet) - 1)
    row = localFrequencyRow();
    row.RunId = string(cfg.RunId);
    row.ConfigHash = string(cfg.ConfigHash);
    row.FromSlot = double(slotDet(ii).Slot);
    row.ToSlot = double(slotDet(ii + 1).Slot);
    row.FrequencyTrackingAttempted = logical(attempted);
    row.InjectedCFO_Hz = double(rx.InjectedCFO_Hz);
    row.PhysicalDoppler_Hz = double(physicalDopplerHz);
    row.FrequencyTolerance_Hz = double(cfg.FrequencyToleranceHz);
    row.PhaseSampleCount = 0;
    row.DeltaT_s = localSlotDeltaSeconds(slotT, ii, ii + 1, tx.SampleRateHz);
    row.CrossCorrelationOrder = "late_times_conj_early";

    if ~(logical(slotDet(ii).Detected) && logical(slotDet(ii + 1).Detected))
        row.Status = "frequency_estimate_unavailable_no_detected_trs_pair";
        row.FrequencyError_Hz = NaN;
        candidateRows(end + 1, 1) = row; %#ok<AGROW>
        continue;
    end

    [hEarly, hLate, n] = localAlignedChannelEstimates(slotDet(ii), slotDet(ii + 1));
    row.PhaseSampleCount = double(n);
    if n == 0 || ~(isfinite(row.DeltaT_s) && row.DeltaT_s > 0)
        row.Status = "frequency_estimate_unavailable_no_valid_channel_samples";
        row.FrequencyError_Hz = NaN;
        candidateRows(end + 1, 1) = row; %#ok<AGROW>
        continue;
    end

    accumC = sum(hLate .* conj(hEarly), "omitnan");
    row.DeltaPhi_rad = double(angle(accumC));
    row.EstimatedCommonFrequency_Hz = double(row.DeltaPhi_rad ./ (2 * pi * row.DeltaT_s));
    row.EstimatedCFO_Hz = double(row.EstimatedCommonFrequency_Hz - physicalDopplerHz);
    row.FrequencyError_Hz = double(row.EstimatedCFO_Hz - double(rx.InjectedCFO_Hz));
    row.TRSCFOEstimateAvailable = isfinite(row.EstimatedCFO_Hz);
    row.Status = string(sixgr.phy.trs.localTernary(row.TRSCFOEstimateAvailable, ...
        "frequency_estimate_available", "frequency_estimate_unavailable"));
    row.TruthStatus = "real_lls_evidence";
    candidateRows(end + 1, 1) = row; %#ok<AGROW>

    if row.TRSCFOEstimateAvailable
        pairEstimates(end + 1, 1) = row.EstimatedCommonFrequency_Hz; %#ok<AGROW>
        pairWeights(end + 1, 1) = max(1, double(n)); %#ok<AGROW>
    end
end

if isempty(candidateRows)
    candidateRows = localFrequencyRow();
    candidateRows.RunId = string(cfg.RunId);
    candidateRows.ConfigHash = string(cfg.ConfigHash);
    candidateRows.FrequencyTrackingAttempted = logical(attempted);
    candidateRows.InjectedCFO_Hz = double(rx.InjectedCFO_Hz);
    candidateRows.PhysicalDoppler_Hz = double(physicalDopplerHz);
    candidateRows.FrequencyTolerance_Hz = double(cfg.FrequencyToleranceHz);
    candidateRows.Status = "frequency_estimate_unavailable_insufficient_trs_slots";
    candidateRows.TruthStatus = "real_lls_evidence";
end

available = ~isempty(pairEstimates);
if available
    estimatedCommon = sum(pairEstimates .* pairWeights, "omitnan") ./ max(sum(pairWeights, "omitnan"), eps);
    estimated = estimatedCommon - physicalDopplerHz;
else
    estimatedCommon = NaN;
    estimated = NaN;
end
err = estimated - double(rx.InjectedCFO_Hz);
for ii = 1:numel(candidateRows)
    if available
        candidateRows(ii).EstimatedCommonFrequency_Hz = double(estimatedCommon);
        candidateRows(ii).EstimatedCFO_Hz = double(estimated);
        candidateRows(ii).FrequencyError_Hz = double(err);
        candidateRows(ii).TRSCFOEstimateAvailable = true;
    end
end

freq = struct();
freq.Table = struct2table(candidateRows, "AsArray", true);
freq.Attempted = logical(attempted);
freq.EstimateAvailable = logical(available);
freq.EstimatedCFO_Hz = double(estimated);
freq.EstimatedCommonFrequency_Hz = double(estimatedCommon);
freq.PhysicalDoppler_Hz = double(physicalDopplerHz);
freq.FrequencyError_Hz = double(err);
end

function dopplerHz = localPhysicalDopplerHz(rx)
dopplerHz = localFirstFinite(rx, ["PhysicalDoppler_Hz","InjectedDoppler_Hz","InjectedScalarDoppler_Hz"], 0);
if ~isfinite(dopplerHz)
    dopplerHz = 0;
end
end

function value = localFirstFinite(s, names, defaultValue)
value = double(defaultValue);
if ~isstruct(s)
    return;
end
for name = string(names(:)).'
    field = char(name);
    if ~isfield(s, field)
        continue;
    end
    raw = double(s.(field));
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = raw(1);
        return;
    end
end
end

function [hEarly, hLate, n] = localAlignedChannelEstimates(early, late)
obsEarly = early.RxRE(:);
obsLate = late.RxRE(:);
refEarly = early.ReferenceSymbols(:);
refLate = late.ReferenceSymbols(:);
n = min([numel(obsEarly), numel(obsLate), numel(refEarly), numel(refLate)]);
if n == 0
    hEarly = complex([]);
    hLate = complex([]);
    return;
end
obsEarly = obsEarly(1:n);
obsLate = obsLate(1:n);
refEarly = refEarly(1:n);
refLate = refLate(1:n);
mask = isfinite(real(obsEarly)) & isfinite(imag(obsEarly)) & ...
    isfinite(real(obsLate)) & isfinite(imag(obsLate)) & ...
    isfinite(real(refEarly)) & isfinite(imag(refEarly)) & abs(refEarly) > eps & ...
    isfinite(real(refLate)) & isfinite(imag(refLate)) & abs(refLate) > eps;
hEarly = obsEarly(mask) ./ refEarly(mask);
hLate = obsLate(mask) ./ refLate(mask);
n = numel(hEarly);
end

function deltaT = localSlotDeltaSeconds(slotT, earlyIdx, lateIdx, sampleRateHz)
deltaT = NaN;
if ~istable(slotT) || height(slotT) < lateIdx
    return;
end
if ~(ismember("StartSample1Based", string(slotT.Properties.VariableNames)) && ...
        isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0)
    return;
end
earlyStart = double(slotT.StartSample1Based(earlyIdx));
lateStart = double(slotT.StartSample1Based(lateIdx));
deltaT = (lateStart - earlyStart) ./ double(sampleRateHz);
end

function row = localFrequencyRow()
row = struct("RunId", "", "ConfigHash", "", "FromSlot", NaN, "ToSlot", NaN, ...
    "FrequencyTrackingAttempted", false, "TRSCFOEstimateAvailable", false, ...
    "EstimatedCommonFrequency_Hz", NaN, "PhysicalDoppler_Hz", NaN, ...
    "EstimatedCFO_Hz", NaN, "InjectedCFO_Hz", NaN, "FrequencyError_Hz", NaN, ...
    "FrequencyTolerance_Hz", NaN, "PhaseSampleCount", NaN, "DeltaPhi_rad", NaN, ...
    "DeltaT_s", NaN, "CrossCorrelationOrder", "", "Status", "", ...
    "TruthStatus", "");
end
