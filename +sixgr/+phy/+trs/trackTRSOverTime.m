function tracking = trackTRSOverTime(det, timing, freq, ch, cfg)
%TRACKTRSOVERTIME Combine TRS detection/timing/CFO/channel evidence.

detT = det.Table;
timingT = timing.Table;
freqT = freq.Table;
chT = ch.Table;
detectionOk = istable(detT) && height(detT) > 0 && all(logical(detT.DetectionAttempted)) && all(logical(detT.DetectionSuccess));
timingOk = istable(timingT) && height(timingT) > 0 && all(logical(timingT.TimingTrackingAttempted)) && ...
    all(logical(timingT.TRSTimingEstimateAvailable)) && ...
    all(abs(double(timingT.TimingError_samples)) <= double(cfg.TimingToleranceSamples));
freqOk = istable(freqT) && height(freqT) > 0 && all(logical(freqT.FrequencyTrackingAttempted)) && ...
    any(logical(freqT.TRSCFOEstimateAvailable)) && ...
    any(abs(double(freqT.FrequencyError_Hz)) <= double(cfg.FrequencyToleranceHz));
channelOk = istable(chT) && height(chT) > 0 && all(logical(chT.ChannelEstimationAttempted)) && ...
    all(logical(chT.TRSChannelEstimateAvailable)) && mean(double(chT.NMSE_dB), "omitnan") <= double(cfg.ChannelNMSEThresholddB);
strictOk = detectionOk && timingOk && freqOk && channelOk;

row = struct();
row.RunId = string(cfg.RunId);
row.ConfigHash = string(cfg.ConfigHash);
row.TrackingAttempted = true;
row.DetectionOk = logical(detectionOk);
row.TimingTrackingOk = logical(timingOk);
row.FrequencyTrackingOk = logical(freqOk);
row.ChannelTrackingOk = logical(channelOk);
row.StrictOk = logical(strictOk);
row.EstimatedTimingOffset_samples = double(timing.EstimatedTimingOffset_samples);
row.EstimatedCFO_Hz = double(freq.EstimatedCFO_Hz);
row.MeanNMSE_dB = double(ch.MeanNMSE_dB);
row.MeanDetectionMetric = double(det.MeanDetectionMetric);
row.TrackingState = string(sixgr.phy.trs.localTernary(strictOk, "valid", "failed"));
row.TrackingEstimateSource = "trs_nzp_csirs_waveform_estimator";
row.TruthStatus = "real_lls_evidence";
tracking = struct();
tracking.Table = struct2table(row, "AsArray", true);
tracking.StrictOk = logical(strictOk);
end
