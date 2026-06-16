function freq = estimateTRSFrequencyOffset(det, cfg, tx, rx)
%ESTIMATETRSFREQUENCYOFFSET Estimate CFO from TRS common phase drift.

slotDet = det.SlotDetections;
rows = repmat(localFrequencyRow(), max(1, numel(slotDet)-1), 1);
phases = [];
times = [];
slots = [];
slotT = tx.SlotTable;
for ii = 1:numel(slotDet)
    if logical(slotDet(ii).Detected) && isfinite(slotDet(ii).PhaseRad)
        phases(end+1, 1) = double(slotDet(ii).PhaseRad); %#ok<AGROW>
        times(end+1, 1) = double(slotT.StartSample1Based(ii) - 1) ./ max(double(tx.SampleRateHz), eps); %#ok<AGROW>
        slots(end+1, 1) = double(slotDet(ii).Slot); %#ok<AGROW>
    end
end
attempted = true;
available = numel(phases) >= 2;
estimated = NaN;
status = "frequency_estimate_unavailable";
if available
    ph = unwrap(phases);
    fit = polyfit(times, ph, 1);
    estimated = fit(1) ./ (2 * pi);
    status = "frequency_estimate_available";
end
err = estimated - double(rx.InjectedCFO_Hz);
if isempty(rows)
    rows = localFrequencyRow();
end
for ii = 1:numel(rows)
    row = localFrequencyRow();
    row.RunId = string(cfg.RunId);
    row.ConfigHash = string(cfg.ConfigHash);
    if numel(slots) >= 2
        row.FromSlot = double(slots(1));
        row.ToSlot = double(slots(end));
    end
    row.FrequencyTrackingAttempted = logical(attempted);
    row.TRSCFOEstimateAvailable = logical(available);
    row.EstimatedCFO_Hz = double(estimated);
    row.InjectedCFO_Hz = double(rx.InjectedCFO_Hz);
    row.FrequencyError_Hz = double(err);
    row.FrequencyTolerance_Hz = double(cfg.FrequencyToleranceHz);
    row.PhaseSampleCount = double(numel(phases));
    row.Status = string(status);
    row.TruthStatus = "real_lls_evidence";
    rows(ii) = row;
end
freq = struct();
freq.Table = struct2table(rows, "AsArray", true);
freq.Attempted = logical(attempted);
freq.EstimateAvailable = logical(available);
freq.EstimatedCFO_Hz = double(estimated);
freq.FrequencyError_Hz = double(err);
end

function row = localFrequencyRow()
row = struct("RunId", "", "ConfigHash", "", "FromSlot", NaN, "ToSlot", NaN, ...
    "FrequencyTrackingAttempted", false, "TRSCFOEstimateAvailable", false, ...
    "EstimatedCFO_Hz", NaN, "InjectedCFO_Hz", NaN, "FrequencyError_Hz", NaN, ...
    "FrequencyTolerance_Hz", NaN, "PhaseSampleCount", NaN, "Status", "", ...
    "TruthStatus", "");
end
