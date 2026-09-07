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
% occasion waveform. Legacy aligned observations already removed the
% implementation filter delay; untrimmed shared observations have not.
% Calibrate only that known receiver implementation delay, never substitute
% a geometric propagation delay for the measured arrival.
det.RawTimingOffsetSamples = double(sixgr.util.structGet(det, "TimingOffsetSamples", NaN));
filterDelay=0;
if string(sixgr.util.structGet(cfg,'lls6g.receiverSync.ReceivedWaveformTimingPlane',''))== ...
        "untrimmed_shared_physical_receive_stream"
    filterDelay=sixgr.util.structGet(cfg,'lls6g.receiverSync.ChannelFilterDelay_samples',[]);
    validateattributes(filterDelay,{'numeric'},{'real','scalar','finite','nonnegative'});
end
det.ImplementationFilterDelay_samples=double(filterDelay);
if logical(det.Detected) && isfinite(det.RawTimingOffsetSamples)
    det.PropagationTimingOffsetSamples = max(0, double(det.RawTimingOffsetSamples)-double(filterDelay));
    det.PropagationTimingEstimateValid = true;
    det.PropagationTimingEstimateSource = "nrPRACHDetect_relative_to_resolved_occasion";
    if filterDelay>0
        det.PropagationTimingEstimateSource="nrPRACHDetect_untrimmed_arrival_minus_known_implementation_filter_delay";
    end
else
    det.PropagationTimingOffsetSamples = NaN;
    det.PropagationTimingEstimateValid = false;
    det.PropagationTimingEstimateSource = "unavailable_without_msg1_detection";
end
det.FrequencyEstimationEnabled = enableFrequencyEstimate;
end
