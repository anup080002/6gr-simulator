function evidence=pucchReceiverDisposition(observed)
% Preserve physical receiver DTX separately from unusable logical HARQ bits.
% A missing decoded bit can produce FeedbackOutcome=DTX without receiver DTX.
arguments
    observed (1,1) struct
end
assert(isfield(observed,'DTXFlag'), ...
    'sixgr:truth:MissingPUCCHReceiverDisposition','Received PUCCH must retain its explicit DTX decision.');
value=observed.DTXFlag;
assert((islogical(value)||isnumeric(value)) && isscalar(value) && ...
    isreal(value) && isfinite(value) && any(value==[0 1]), ...
    'sixgr:truth:InvalidPUCCHReceiverDisposition','Receiver DTX must be a scalar binary decision.');
evidence=struct('DTXFlag',logical(value),'DTXReason',"");
if evidence.DTXFlag
    evidence.DTXReason="receiver_reported_dtx";
end
end
