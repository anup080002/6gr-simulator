function row = bindPDCCHReceiverObservation(row,rx,info)
%BINDPDCCHRECEIVEROBSERVATION Export actual blind decode and timing evidence.
% Transmitted-bit agreement is an audit, not a receiver detection statistic.
candidates = sixgr.util.structGet(info,'CandidateResults',table());
assert(istable(candidates),'sixgr:truth:InvalidPDCCHCandidateEvidence', ...
    'Receiver candidate evidence must be a table.');
row.DetectionMetric = NaN;
row.DetectionThreshold = NaN;
row.DetectionMetricStatus = "not_applicable_rnti_masked_crc_and_semantic_decode";
row.DetectionPopulationScope = "actual_monitored_candidate_and_DCI_hypothesis_set";
row.DetectionAttempted = height(candidates)>0;
row.DetectionUsable = false;
if row.DetectionAttempted && ismember('ErrFlag',candidates.Properties.VariableNames)
    flags = sixgr.truth.numericMeasurementColumn(candidates.ErrFlag,'ErrFlag');
    row.DetectionUsable = numel(flags)==height(candidates) && ...
        all(isfinite(flags) & flags>=0 & flags==fix(flags));
end
row.DetectionSuccess = row.DetectionUsable && ...
    isequal(sixgr.util.structGet(rx,'Ok',false),true) && ...
    isequal(sixgr.util.structGet(rx,'ErrFlag',NaN),0);
row.Modulation = "QPSK"; % PDCCH modulation, not the scheduled data modulation.

% The injected RF delay is not the arrival time after channel/filter delay.
% Keep it in InjectedTimingOffset_samples; do not relabel it as truth timing.
row.TrueTimingOffset_samples = NaN;
timing = sixgr.util.structGet(info,'TimingEstimate',struct());
row.TimingEstimateUsed = logical(sixgr.util.structGet(timing,'EstimateUsed',false));
row.TimingEstimate_samples = double(sixgr.util.structGet(timing,'RawEstimate_samples',NaN));
row.EstimatedTimingOffset_PreCorrection_samples = row.TimingEstimate_samples;
row.EstimatedTimingOffset_samples = row.TimingEstimate_samples;
row.AppliedTimingCorrection_samples = double(sixgr.util.structGet(timing,'AppliedCorrection_samples',NaN));
row.TimingEstimateStatus = string(sixgr.util.structGet(timing,'Status','unavailable_no_receiver_timing_evidence'));
row.TimingEstimateApplicationPolicy = string(sixgr.util.structGet(timing,'ApplicationPolicy',''));
row.TimingEstimateWasClipped = logical(sixgr.util.structGet(timing,'WasClipped',false));
end
