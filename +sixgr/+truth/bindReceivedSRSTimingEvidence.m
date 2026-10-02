function row=bindReceivedSRSTimingEvidence(row,timing,physicalTiming)
%BINDRECEIVEDSRSTIMINGEVIDENCE Separate capture extraction from timing error.
required=["TimingOffsetSamples","AppliedTimingCorrectionSamples", ...
    "TimingSource","OracleTimingUsed","ReceiverZeroPaddingUsed"];
assert(isstruct(timing) && all(isfield(timing,required)), ...
    'sixgr:truth:MissingReceivedSRSTiming','Actual SRS receive timing evidence is required.');
requiredPhysical=["ReceiveSearchGuardSamples","ReceiveStartSample"];
assert(isstruct(physicalTiming) && all(isfield(physicalTiming,requiredPhysical)), ...
    'sixgr:truth:MissingSRSPhysicalTiming', ...
    'SRS timing semantics require the independently scheduled receive-window center.');
raw=double(timing.TimingOffsetSamples);
applied=double(timing.AppliedTimingCorrectionSamples);
expectedCaptureOffset=double(physicalTiming.ReceiveSearchGuardSamples);
residual=raw-expectedCaptureOffset;
assert(isscalar(raw) && isfinite(raw) && isscalar(applied) && isfinite(applied) && ...
    isscalar(expectedCaptureOffset) && isfinite(expectedCaptureOffset) && ...
    expectedCaptureOffset>=0 && ...
    ~timing.OracleTimingUsed && ~timing.ReceiverZeroPaddingUsed && ...
    strlength(string(timing.TimingSource))>0, ...
    'sixgr:truth:InvalidReceivedSRSTiming','Shared SRS timing must be measured and applied to actual received samples.');
row.SRSCaptureExtractionOffset_samples=raw;
row.SRSExpectedCaptureOffset_samples=expectedCaptureOffset;
row.SRSExpectedReceiveCenterSample=double(physicalTiming.ReceiveStartSample)+expectedCaptureOffset;
row.SRSReceiveTimingOffset_samples=residual;
row.SRSAppliedTimingCorrection_samples=applied;
row.SRSReceiveTimingSource=string(timing.TimingSource);
row.TimingEstimate_samples=residual;
row.EstimatedTimingOffset_samples=residual;
row.EstimatedTimingOffset_PreCorrection_samples=residual;
row.TimingOffset_samples=residual;
row.AppliedTimingCorrection_samples=applied;
row.TimingEstimateUsed=true;
row.UseIdealTimingSync=false;
row.TimingEstimateApplicationPolicy= ...
    "received_reference_residual_relative_to_independently_scheduled_receive_center";
row.TimingEstimateStatus="available_residual_and_capture_extraction_separated";
row.TimingEstimateWasClipped=(raw~=applied);
% No channel-delay truth or zero residual is inferred here.
end
