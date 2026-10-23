function row=bindSRSArrivalTimingReference(row,planes,physicalTiming)
%BINDSRSARRIVALTIMINGREFERENCE Post-reception earliest-path scoring only.
% The receiver's selected correlation peak and capture extraction are already
% fixed. Derive the arrival reference from the SAME executed clocks/RF/link;
% never supply it to acquisition or call the peak-minus-earliest difference
% an independently measured post-correction residual on a fading channel.
arguments
    row table
    planes struct
    physicalTiming (1,1) struct
end
identifier='sixgr:truth:SRSArrivalTimingBindingMismatch';
required=["SRSCaptureExtractionOffset_samples","SRSExpectedCaptureOffset_samples", ...
    "SRSExpectedReceiveCenterSample","SRSReceiveTimingOffset_samples", ...
    "SRSAppliedTimingCorrection_samples","TransmitStartSample"];
assert(height(row)==1 && all(ismember(required,string(row.Properties.VariableNames))) && ...
    all(isfield(physicalTiming,{'TransmitStartSample','ReceiveStartSample', ...
    'ReceiveSearchGuardSamples'})),identifier, ...
    'Bind one completed SRS receiver result and its actual scheduled TX/RX clocks.');
transmitStart=double(physicalTiming.TransmitStartSample);
captureStart=double(physicalTiming.ReceiveStartSample);
guard=double(physicalTiming.ReceiveSearchGuardSamples);
assert(isscalar(transmitStart) && isscalar(captureStart) && isscalar(guard) && ...
    all(isfinite([transmitStart captureStart guard])) && ...
    all([transmitStart captureStart guard]>=0) && ...
    all([transmitStart captureStart guard]==fix([transmitStart captureStart guard])), ...
    identifier,'Physical TX, receive-window start and pre-roll must use one integer sample clock.');
for name=required
    value=row.(name);
    assert(isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value), ...
        identifier,'Actual SRS timing field %s must be finite before independent scoring.',name);
end
assert(row.TransmitStartSample==transmitStart && ...
    row.SRSExpectedCaptureOffset_samples==guard && ...
    row.SRSExpectedReceiveCenterSample==captureStart+guard && ...
    row.SRSReceiveTimingOffset_samples==row.SRSCaptureExtractionOffset_samples-guard, ...
    identifier,'Do not join receiver timing to another transmit time or receive-window origin.');
reference=sixgr.truth.sharedArrivalTimingReference(planes,transmitStart);
assert(reference.ReceiveStartSample==captureStart && ...
    ~reference.ReceiverEstimatorInput && reference.AdditionalChannelExecutions==0, ...
    identifier,'The arrival reference must use the same completed observation and executed link.');
offset=double(reference.ExpectedArrivalOffset_samples);
reference.ExpectedArrivalAbsoluteSample=captureStart+offset;
reference.ScheduledReceiveCenterSample=captureStart+guard;
reference.ExpectedArrivalRelativeToScheduledCenter_samples=offset-guard;
reference.SelectedCorrelationPeakCaptureOffset_samples=row.SRSCaptureExtractionOffset_samples;
reference.SelectedPeakMinusEarliestArrival_samples=row.SRSCaptureExtractionOffset_samples-offset;
reference.ClockDomain="shared_physical_runtime_absolute_sample_zero_based";
reference.ScoringRole="earliest_path_reference_not_strongest_peak_error_or_post_correction_residual";
% Keep every practical receiver estimate/applied correction unchanged. In
% particular, this reference is not injected RF delay or the receiver's CFO.
row.SRSArrivalTimingReferenceAvailable=true;
row.SRSExpectedEarliestArrivalSample=reference.ExpectedArrivalAbsoluteSample;
row.SRSExpectedEarliestArrivalCaptureOffset_samples=offset;
row.SRSExpectedEarliestArrivalRelativeToReceiveCenter_samples=offset-guard;
row.SRSSelectedPeakMinusEarliestArrival_samples=reference.SelectedPeakMinusEarliestArrival_samples;
row.SRSArrivalTimingReferencePlane=string(reference.ReferencePlane);
row.SRSArrivalTimingScoringStatus="available_earliest_path_not_post_correction_residual";
row.TimingScoringReferenceSource=string(reference.Source);
row.TimingScoringReferenceJSON=string(jsonencode(reference));
row.TrueTimingOffset_samples=offset-guard;
end
