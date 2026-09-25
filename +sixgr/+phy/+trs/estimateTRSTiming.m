function timing = estimateTRSTiming(rx, cfg, tx)
%ESTIMATETRSTIMING Estimate timing from received TRS reference resources.

resources = localResolveSlotResources(cfg, tx);
slotT = tx.SlotTable;
rows = repmat(localTimingRow(), numel(resources), 1);
for ii = 1:numel(resources)
    carrier = resources(ii).Carrier;
    attempted = true;
    est = NaN;
    hypotheses = NaN;
    status = "timing_estimate_unavailable";
    try
        slotWave = localSlotWaveform(rx.Waveform, slotT, ii);
        [est,mag] = nrTimingEstimate(carrier, slotWave, resources(ii).Indices, resources(ii).Symbols, ...
            'SampleRate',tx.SampleRateHz,'Nfft',tx.OFDM.Nfft);
        est=double(est);
        hypotheses=size(mag,1); % Every searched lag, not just the selected peak.
        status = "timing_estimate_available";
    catch ME
        status = "timing_estimate_failed:" + string(ME.identifier);
    end
    err = est - double(rx.InjectedTimingOffset_samples);
    available = attempted && isfinite(est);
    rows(ii) = localTimingRow();
    rows(ii).RunId = string(cfg.RunId);
    rows(ii).ConfigHash = string(cfg.ConfigHash);
    rows(ii).Slot = double(resources(ii).Slot);
    rows(ii).TimingTrackingAttempted = logical(attempted);
    rows(ii).TRSTimingEstimateAvailable = logical(available);
    rows(ii).EstimatedTimingOffset_samples = double(est);
    rows(ii).TimingHypothesisCount = double(hypotheses);
    rows(ii).InjectedTimingOffset_samples = double(rx.InjectedTimingOffset_samples);
    rows(ii).TimingError_samples = double(err);
    rows(ii).TimingTolerance_samples = double(cfg.TimingToleranceSamples);
    rows(ii).Status = string(status);
    rows(ii).TruthStatus = "real_lls_evidence";
end

function resources = localResolveSlotResources(cfg, tx)
if isfield(tx, "SlotResources") && isfield(tx, "Config") && ...
        isfield(tx.Config, "ConfigHash") && string(tx.Config.ConfigHash) == string(cfg.ConfigHash)
    resources = tx.SlotResources;
else
    resources = sixgr.phy.trs.generateTRSSymbolsAndIndices(cfg).SlotResources;
end
end
timing = struct();
timing.Table = struct2table(rows, "AsArray", true);
timing.Attempted = any([rows.TimingTrackingAttempted]);
timing.EstimateAvailable = any([rows.TRSTimingEstimateAvailable]);
timing.EstimatedTimingOffset_samples = median([rows.EstimatedTimingOffset_samples], "omitnan");
timing.TimingError_samples = median([rows.TimingError_samples], "omitnan");
end

function y = localSlotWaveform(wave, slotT, idx)
startIdx = double(slotT.StartSample1Based(idx));
endIdx = double(slotT.EndSample1Based(idx));
if ~isfinite(startIdx) || ~isfinite(endIdx) || ...
        startIdx~=fix(startIdx) || endIdx~=fix(endIdx) || ...
        startIdx<1 || endIdx<startIdx || endIdx>size(wave,1)
    error('sixgr:phy:trs:IncompleteTimingCapture', ...
        'TRS timing correlation requires the complete declared received slot.');
end
y = wave(startIdx:endIdx, :);
end

function row = localTimingRow()
row = struct("RunId", "", "ConfigHash", "", "Slot", NaN, ...
    "TimingTrackingAttempted", false, "TRSTimingEstimateAvailable", false, ...
    "EstimatedTimingOffset_samples", NaN, "InjectedTimingOffset_samples", NaN, ...
    "TimingHypothesisCount", NaN, ...
    "TimingError_samples", NaN, "TimingTolerance_samples", NaN, ...
    "Status", "", "TruthStatus", "");
end
