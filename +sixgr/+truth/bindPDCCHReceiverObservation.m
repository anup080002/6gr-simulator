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
% ErrFlag is the RNTI-masked CRC result of the retained receiver hypothesis.
% rx.Ok also includes context parsing/hypothesis selection; TX agreement is
% a separate audit. Neither may rewrite the physical CRC observation.
flag = sixgr.util.structGet(rx,'ErrFlag',NaN);
row.CRCApplicable = true;
row.CRCPass = NaN;
row.DCICrcPass = false;
row.CRCOutcome = "unavailable";
if row.DetectionUsable && isnumeric(flag) && isreal(flag) && isscalar(flag) && ...
        isfinite(flag) && flag>=0 && flag==fix(flag)
    row.DCICrcPass = (flag==0);
    row.CRCPass = double(row.DCICrcPass);
    if row.DCICrcPass
        row.CRCOutcome = "pass";
    else
        row.CRCOutcome = "fail";
    end
end
row.DetectionSuccess = row.DetectionUsable && ...
    isequal(sixgr.util.structGet(rx,'Ok',false),true) && ...
    isequal(sixgr.util.structGet(rx,'ErrFlag',NaN),0);
row.Modulation = "QPSK"; % PDCCH modulation, not the scheduled data modulation.
for name=["LLRMeanAbs","LLRMin","LLRMax","LLRCount"]
    row.("PDCCH"+name)=double(sixgr.util.structGet(rx,name,NaN));
end
% These flags describe the retained decoder samples, not a SINR/EVM proxy
% or a stale aggregate. Absent samples cannot establish finite LLRs.
row.LLRAvailable = NaN;
row.LLRFinite = NaN;
if isfield(rx,'DecoderLLRs')
    llrs = rx.DecoderLLRs;
    assert(isnumeric(llrs) && isreal(llrs) && (isvector(llrs) || isempty(llrs)), ...
        'sixgr:truth:InvalidPDCCHLLREvidence','Decoder LLR evidence must be a real numeric vector.');
    row.LLRAvailable = ~isempty(llrs);
    row.LLRFinite = ~isempty(llrs) && all(isfinite(llrs(:)));
end

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
