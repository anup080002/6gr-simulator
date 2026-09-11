function tracking = trackTRSOverTime(det, timing, freq, ch, cfg, observation)
%TRACKTRSOVERTIME Combine TRS detection/timing/CFO/channel evidence.

detT = det.Table;
timingT = timing.Table;
freqT = freq.Table;
chT = ch.Table;
count=numel(cfg.SlotNumbers);
detectionOk = localCompleteFlags(detT,count,["DetectionAttempted","DetectionSuccess"]);
timingOk = localCompleteFlags(timingT,count,["TimingTrackingAttempted","TRSTimingEstimateAvailable"]) && ...
    all(abs(double(timingT.TimingError_samples)) <= double(cfg.TimingToleranceSamples));
freqOk = localCompleteFlags(freqT,count,["FrequencyTrackingAttempted","TRSCFOEstimateAvailable"]) && ...
    all(abs(double(freqT.FrequencyError_Hz)) <= double(cfg.FrequencyToleranceHz));
channelOk = localCompleteFlags(chT,count,["ChannelEstimationAttempted","TRSChannelEstimateAvailable"]) && ...
    ch.NMSEScoringAvailable && ...
    ~isnan(ch.MeanNMSE_dB) && ch.MeanNMSE_dB <= double(cfg.ChannelNMSEThresholddB);
strictOk = detectionOk && timingOk && freqOk && channelOk;
% Practical tracking cannot use injected timing/frequency errors or scored
% NMSE. Require every configured received window, rather than an aggregate
% availability flag hiding a failed/missing window.
runtimeTimingOk=localCompleteFlags(timingT,count, ...
    ["TimingTrackingAttempted","TRSTimingEstimateAvailable"]) && ...
    all(isfinite(timingT.EstimatedTimingOffset_samples));
runtimeFrequencyOk=localCompleteFlags(freqT,count, ...
    ["FrequencyTrackingAttempted","TRSCFOEstimateAvailable"]) && ...
    all(isfinite(freqT.EstimatedCommonFrequency_Hz)) && ...
    all(isfinite(freqT.UnambiguousHalfRange_Hz) & freqT.UnambiguousHalfRange_Hz>0) && ...
    all(abs(freqT.EstimatedCommonFrequency_Hz)<=freqT.UnambiguousHalfRange_Hz) && ...
    all(freqT.FrequencyEstimateDomain=="received_TRS_common_phase_frequency");
runtimeChannelOk=localCompleteFlags(chT,count, ...
    ["ChannelEstimationAttempted","TRSChannelEstimateAvailable"]);
runtimeDetectionOk=localCompleteFlags(detT,count,["DetectionAttempted","DetectionSuccess"]);
runtimeEvidenceOk=runtimeDetectionOk && runtimeTimingOk && runtimeFrequencyOk && runtimeChannelOk && ...
    nargin>=6 && ~isempty(observation);
producerSlot = localLastFiniteSlot(detT);

row = struct();
row.RunId = string(cfg.RunId);
row.ConfigHash = string(cfg.ConfigHash);
row.ProducerSlot = double(producerSlot);
row.AvailableSlot = NaN;
row.AvailabilitySource = "unavailable_without_received_completion_clock";
row.SlotIndexing = "zero_based_absolute_slot_available_at_slot_start";
row.ObservationEndSampleExclusive = NaN;
row.ObservationSampleRateHz = NaN;
if nargin>=6 && ~isempty(observation)
    assert(isa(observation,'sixgr.phy.waveform.WaveformObservationBuffer') && observation.isComplete(), ...
        'sixgr:phy:trs:IncompleteTrackingObservation','Tracking availability requires actual received completion.');
    samplesPerSlot=observation.SampleRateHz*1e-3/(double(cfg.ToolboxCarrier.SubcarrierSpacing)/15);
    validateattributes(samplesPerSlot,{'numeric'},{'scalar','finite','integer','positive'});
    row.AvailableSlot=ceil(observation.EndSampleExclusive/samplesPerSlot);
    row.AvailabilitySource="actual_received_completion_next_slot_start";
    row.ObservationEndSampleExclusive=observation.EndSampleExclusive;
    row.ObservationSampleRateHz=observation.SampleRateHz;
end
row.MeasurementTargetType = "CELL";
row.CausalConsumerContract = "TRS timing/CFO/phase tracking may feed data receivers only when AvailableSlot<=grant slot and age is within TRS freshness";
row.TrackingAttempted = true;
row.DetectionOk = logical(detectionOk);
row.TimingTrackingOk = logical(timingOk);
row.FrequencyTrackingOk = logical(freqOk);
row.ChannelTrackingOk = logical(channelOk);
row.StrictOk = logical(strictOk);
row.RuntimeEvidenceUsable = logical(runtimeEvidenceOk);
row.RuntimeEvidenceScope = "all_configured_received_TRS_windows_no_scoring_truth";
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
tracking.RuntimeEvidenceUsable = logical(runtimeEvidenceOk);
end

function tf=localCompleteFlags(T,count,fields)
tf=istable(T) && height(T)==count && count>0 && ...
    all(ismember(fields,string(T.Properties.VariableNames)));
if ~tf, return; end
for field=fields
    value=T.(field);
    tf=tf && (isnumeric(value)||islogical(value)) && ...
        all(isfinite(value) & value==1,'all');
end
end

function slot = localLastFiniteSlot(T)
slot = NaN;
if ~(istable(T) && height(T) > 0 && ismember("Slot", string(T.Properties.VariableNames)))
    return;
end
raw = double(T.Slot);
raw = raw(isfinite(raw));
if ~isempty(raw)
    slot = max(raw);
end
end
