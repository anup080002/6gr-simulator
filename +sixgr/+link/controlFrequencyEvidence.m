function out=controlFrequencyEvidence(rx)
%CONTROLFREQUENCYEVIDENCE Project original receiver operators, not RF truth.
% Legacy receivers without an operator receipt acquire no inferred evidence.
out=struct();
if ~isfield(rx,'ReceiveFrequency'), return; end
e=rx.ReceiveFrequency;
id='sixgr:link:InvalidControlFrequencyEvidence';
assert(isstruct(e) && isscalar(e),id,'Retain one original receiver frequency receipt.');
if isempty(fieldnames(e)), return; end
numeric=["EstimatedCFO_Hz","EstimatedCommonFrequency_Hz","CFOCorrectionApplied_Hz", ...
    "CFOCorrectionSampleOrigin","CFOCorrectionAbsoluteSampleOrigin", ...
    "ResidualCFOEstimatorConsistency_Hz"];
flags=["CFOEstimateAvailable","CFOCorrectionEnabled","CFOCorrectionApplied", ...
    "ResidualCFOReusesAcquisitionObservation","ResidualCFOEstimateAvailable"];
texts=["CFOEstimateSource","CFOCorrectionSource","ResidualCFOEstimateRole", ...
    "FrequencyEstimateDomain","CFOCorrectionClockSource"];
for name=[numeric flags texts]
    if ~isfield(e,name), continue; end
    value=e.(name);
    if any(name==numeric)
        assert(isnumeric(value) && isreal(value) && isscalar(value) && ~isinf(value), ...
            id,'Original %s must be a numeric scalar or unavailable NaN.',name);
    elseif any(name==flags)
        assert(islogical(value) && isscalar(value),id,'Original %s must be a logical scalar.',name);
    else
        assert((isstring(value) && isscalar(value) && ~ismissing(value)) || ...
            (ischar(value) && (isrow(value) || isempty(value))), ...
            id,'Original %s must be scalar text.',name);
    end
    if isfield(rx,name)
        assert(isequaln(rx.(name),value),id, ...
            'Receiver scalar %s disagrees with its original frequency receipt.',name);
    end
    out.(name)=value;
end
if isfield(e,'Status')
    value=e.Status;
    assert((isstring(value) && isscalar(value) && ~ismissing(value)) || ...
        (ischar(value) && isrow(value)),id,'Frequency status must be original scalar text.');
    if isfield(rx,'FrequencyCorrectionStatus')
        assert(isequaln(rx.FrequencyCorrectionStatus,value),id, ...
            'Frequency status disagrees with its original receipt.');
    end
    out.FrequencyCorrectionStatus=value; % Never replace channel/decode Status.
end
% Preserve original status, estimator operands, clocks and hashes together.
% JSON/hash is serialization integrity, not independent execution authority.
out.ReceiverFrequencyEvidenceJSON=string(jsonencode(sixgr.util.jsonSafeValue(e)));
out.ReceiverFrequencyEvidenceSHA256=string(sixgr.util.sha256Hex(char(out.ReceiverFrequencyEvidenceJSON)));
end
