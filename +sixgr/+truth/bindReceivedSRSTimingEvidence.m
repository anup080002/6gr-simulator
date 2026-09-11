function row=bindReceivedSRSTimingEvidence(row,timing)
%BINDRECEIVEDSRSTIMINGEVIDENCE Project the actual receiver's applied timing.
required=["TimingOffsetSamples","AppliedTimingCorrectionSamples", ...
    "TimingSource","OracleTimingUsed","ReceiverZeroPaddingUsed"];
assert(isstruct(timing) && all(isfield(timing,required)), ...
    'sixgr:truth:MissingReceivedSRSTiming','Actual SRS receive timing evidence is required.');
raw=double(timing.TimingOffsetSamples);
applied=double(timing.AppliedTimingCorrectionSamples);
assert(isscalar(raw) && isfinite(raw) && isscalar(applied) && isfinite(applied) && ...
    ~timing.OracleTimingUsed && ~timing.ReceiverZeroPaddingUsed && ...
    strlength(string(timing.TimingSource))>0, ...
    'sixgr:truth:InvalidReceivedSRSTiming','Shared SRS timing must be measured and applied to actual received samples.');
row.SRSReceiveTimingOffset_samples=raw;
row.SRSAppliedTimingCorrection_samples=applied;
row.SRSReceiveTimingSource=string(timing.TimingSource);
row.TimingEstimate_samples=raw;
row.EstimatedTimingOffset_samples=raw;
row.EstimatedTimingOffset_PreCorrection_samples=raw;
row.TimingOffset_samples=raw;
row.AppliedTimingCorrection_samples=applied;
row.TimingEstimateUsed=true;
row.UseIdealTimingSync=false;
row.TimingEstimateApplicationPolicy="received_reference_bounded_capture_extraction";
row.TimingEstimateStatus="available_applied_at_receiver";
row.TimingEstimateWasClipped=(raw~=applied);
% No true delay, residual error or zero residual is inferred here.
end
