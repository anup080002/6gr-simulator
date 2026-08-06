function det = detectMsg1PRACH(rxWaveform, cfg, raCfg, occasion)
%DETECTMSG1PRACH Detect MSG1 from received PRACH waveform.
prachCfg = sixgr.phy.ra.buildPRACHConfigFromRACHCommon(cfg, raCfg);
enableFrequencyEstimate = logical(sixgr.util.structGet( ...
    cfg, "random_access.enable_frequency_estimation_metric", ...
    sixgr.util.structGet(prachCfg, "EnableFrequencyEstimationMetric", false)));
det = sixgr.rach.PRACHDetector(rxWaveform, prachCfg, ...
    "Occasion", occasion, ...
    "CandidatePreambles", 0:63, ...
    "DetectorBackend", "toolbox_peak", ...
    "EnableFrequencyEstimationMetric", enableFrequencyEstimate, ...
    "DetectionThresholdMode", sixgr.util.structGet(cfg, "random_access.detection_threshold_mode", "fixed"), ...
    "DetectionThreshold", double(sixgr.util.structGet(cfg, "random_access.detection_threshold", 0.02)));
det.RAPIDMatchesTx = logical(det.Detected) && double(det.DetectedPreambleIndex) == double(raCfg.PreambleIndex);
% nrPRACHDetect returns timing relative to the start of the supplied PRACH
% occasion waveform.  The runtime channel removes its known implementation
% filter delay before this receiver runs, so the detector offset is the
% receiver-owned propagation timing measurement.  No transmitted timing or
% geometry oracle is consulted here.
det.RawTimingOffsetSamples = double(sixgr.util.structGet(det, "TimingOffsetSamples", NaN));
if logical(det.Detected) && isfinite(det.RawTimingOffsetSamples)
    det.PropagationTimingOffsetSamples = max(0, double(det.RawTimingOffsetSamples));
    det.PropagationTimingEstimateValid = true;
    det.PropagationTimingEstimateSource = "nrPRACHDetect_relative_to_resolved_occasion";
else
    det.PropagationTimingOffsetSamples = NaN;
    det.PropagationTimingEstimateValid = false;
    det.PropagationTimingEstimateSource = "unavailable_without_msg1_detection";
end
det.FrequencyEstimationEnabled = enableFrequencyEstimate;
end
