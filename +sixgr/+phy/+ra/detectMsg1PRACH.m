function det = detectMsg1PRACH(rxWaveform, cfg, raCfg, occasion)
%DETECTMSG1PRACH Detect MSG1 from received PRACH waveform.
prachCfg = sixgr.phy.ra.buildPRACHConfigFromRACHCommon(cfg, raCfg);
enableFrequencyEstimate = logical(sixgr.util.structGet( ...
    cfg, "random_access.enable_frequency_estimation_metric", ...
    sixgr.util.structGet(prachCfg, "EnableFrequencyEstimationMetric", false)));
% The capture may begin before the gNB's known PRACH-slot origin. That
% acquisition pre-guard is not propagation delay: leaving it inside the
% nrPRACHDetect input can cross a ZC cyclic shift and change the decoded
% preamble. Extract from the gNB origin, not from a measured/true arrival.
filterDelay=0;
observationGuard=0;
if string(sixgr.util.structGet(cfg,'lls6g.receiverSync.ReceivedWaveformTimingPlane',''))== ...
        "untrimmed_shared_physical_receive_stream"
    filterDelay=sixgr.util.structGet(cfg,'lls6g.receiverSync.ChannelFilterDelay_samples',[]);
    validateattributes(filterDelay,{'numeric'},{'real','scalar','finite','nonnegative'});
    observationGuard=sixgr.util.structGet(cfg,'lls6g.receiverSync.ULObservationSearchGuard_samples',0);
    validateattributes(observationGuard,{'numeric'},{'real','scalar','finite','integer','nonnegative'});
end
assert(size(rxWaveform,1)>observationGuard,'sixgr:phy:ra:IncompletePRACHReceiveWindow', ...
    'Complete the actual PRACH observation beyond its declared pre-guard.');
det = sixgr.rach.PRACHDetector(rxWaveform(observationGuard+1:end,:), prachCfg, ...
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
det.DetectorInputStartOffsetSamples=double(observationGuard);
det.DetectorTimingReference="offset_from_gnb_prach_slot_origin_within_actual_capture";
det.RawTimingOffsetSamples = double(sixgr.util.structGet(det, "TimingOffsetSamples", NaN))+double(observationGuard);
det.ImplementationFilterDelay_samples=double(filterDelay);
det.ObservationSearchGuard_samples=double(observationGuard);
if logical(det.Detected) && isfinite(det.RawTimingOffsetSamples)
    calibrated=double(det.RawTimingOffsetSamples)-double(filterDelay)-double(observationGuard);
    if observationGuard>0 && calibrated<0
        error('sixgr:phy:ra:NegativeMeasuredPRACHRoundTrip', ...
            'Measured PRACH arrival precedes the gNB reference: capture offset=%g, pre-guard=%g, filter=%g samples.', ...
            det.RawTimingOffsetSamples,observationGuard,filterDelay);
    end
    det.PropagationTimingOffsetSamples = max(0,calibrated);
    det.PropagationTimingEstimateValid = true;
    det.PropagationTimingEstimateSource = "nrPRACHDetect_relative_to_resolved_occasion";
    if filterDelay>0
        det.PropagationTimingEstimateSource="nrPRACHDetect_untrimmed_arrival_minus_known_implementation_filter_delay";
    end
    if observationGuard>0
        det.PropagationTimingEstimateSource="nrPRACHDetect_measured_round_trip_relative_gnb_common_offset_window";
    end
else
    det.PropagationTimingOffsetSamples = NaN;
    det.PropagationTimingEstimateValid = false;
    det.PropagationTimingEstimateSource = "unavailable_without_msg1_detection";
end
det.FrequencyEstimationEnabled = enableFrequencyEstimate;
end
