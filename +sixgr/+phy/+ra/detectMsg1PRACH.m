function det = detectMsg1PRACH(rxWaveform, cfg, raCfg, occasion)
%DETECTMSG1PRACH Detect MSG1 from received PRACH waveform.
sixgr.runtime.RuntimeCallLedger.record("sixgr.phy.ra.detectMsg1PRACH","PRACH","UL",struct("Stage","RX"));
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
policy=string(sixgr.util.structGet(cfg,'random_access.preamble_detection_policy','strongest'));
assert(any(policy==["strongest","awgn_sic_unrestricted"]), ...
    'sixgr:phy:ra:InvalidPRACHDetectionPolicy','Unknown configured PRACH detection policy.');
if policy=="awgn_sic_unrestricted"
    [candidates,background]=sixgr.rach.detectUnrestrictedPreambles( ...
        rxWaveform(observationGuard+1:end,:),prachCfg,occasion,det, ...
        sixgr.util.structGet(cfg,'random_access.multi_preamble_max_delay_us',[]));
    timed=cell(numel(candidates),1);
    for k=1:numel(candidates)
        timed{k}=localTiming(candidates(k),filterDelay,observationGuard,enableFrequencyEstimate);
    end
    if ~isempty(timed), candidates=vertcat(timed{:}); end
    if ~isempty(candidates)
        [~,best]=max([candidates.PeakMetric]); det=candidates(best);
    else
        det.Detected=false; det.DetectedPreambleIndex=NaN; det.TimingOffsetSamples=NaN;
        det.NoiseFloorEvidence=background; det.PDPNoiseFloor=background.NoiseFloor;
        % The native-template peak uses a different metric; do not divide it
        % by the SIC background or publish its trace as a SIC measurement.
        det.PeakToNoiseRatio=NaN; det.PeakToNoiseRatio_dB=NaN;
        det.CorrelationTrace=struct();
    end
    det=localTiming(det,filterDelay,observationGuard,enableFrequencyEstimate);
    det.Detections=candidates;
    det.MultiCandidateAboveThreshold=numel(candidates)>1;
    det.CandidatesAboveThreshold=numel(candidates);
else
    det=localTiming(det,filterDelay,observationGuard,enableFrequencyEstimate);
end
det.RAPIDMatchesTx = logical(det.Detected) && double(det.DetectedPreambleIndex) == double(raCfg.PreambleIndex);
end

function det=localTiming(det,filterDelay,observationGuard,enableFrequencyEstimate)
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
    backend=string(det.DetectorBackend);
    source="nrPRACHDetect";
    if ~contains(backend,"nrPRACHDetect"), source=backend; end
    det.PropagationTimingEstimateSource = source+"_relative_to_resolved_occasion";
    if filterDelay>0
        det.PropagationTimingEstimateSource=source+"_untrimmed_arrival_minus_known_implementation_filter_delay";
    end
    if observationGuard>0
        det.PropagationTimingEstimateSource=source+"_measured_round_trip_relative_gnb_common_offset_window";
    end
else
    det.PropagationTimingOffsetSamples = NaN;
    det.PropagationTimingEstimateValid = false;
    det.PropagationTimingEstimateSource = "unavailable_without_msg1_detection";
end
det.FrequencyEstimationEnabled = enableFrequencyEstimate;
end
