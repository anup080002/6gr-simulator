function evidence = pdcchTrialExecutionState(T)
% Separate untransmitted/unexecuted control obligations from failed decoding.
% Never trust a previously derived ControlObservationAvailable flag: older
% exports marked NA blocked grants observed merely because a row existed.
assert(istable(T),'sixgr:link:PDCCHExecutionTableRequired','Expected a PDCCH trial table.');
n = height(T);
status = repmat("",n,1);
if ismember('Status',T.Properties.VariableNames), status = upper(string(T.Status)); end
observed = status ~= "" & status ~= "NA" & status ~= "CRASH" & ~contains(status,"PENDING");
source = repmat("legacy_executed_status",n,1);
if ismember('PDCCHReceiverTrialExecuted',T.Properties.VariableNames)
    value = double(T.PDCCHReceiverTrialExecuted);
    assert(all(isnan(value) | value == 0 | value == 1), ...
        'sixgr:link:InvalidPDCCHExecutionEvidence','Receiver execution evidence must be 0/1 or unavailable.');
    known = isfinite(value);
    observed(known) = value(known) == 1;
    source(known) = "physical_pdcch_receive_completion";
end
attempted = observed;
if ismember('DecodeAttempted',T.Properties.VariableNames)
    value = double(T.DecodeAttempted);
    assert(all(isnan(value) | value == 0 | value == 1), ...
        'sixgr:link:InvalidPDCCHExecutionEvidence','Decode attempted must be 0/1 or unavailable.');
    known = isfinite(value);
    attempted(known) = value(known) == 1;
end
bindingEligible = observed & attempted;
precheck = repmat("",n,1);
precheck(~observed) = "pdcch_receiver_not_executed";
precheck(observed & ~attempted) = "dci_decode_not_attempted";
if ismember('FailureReason',T.Properties.VariableNames)
    reason = string(T.FailureReason);
    blocked = ~bindingEligible & startsWith(reason,"control_blocked_");
    precheck(blocked) = reason(blocked);
end
evidence = table(observed,attempted,bindingEligible,precheck,source, ...
    'VariableNames',{'ObservationAvailable','DecodeAttempted','BindingEligible', ...
    'BindingFailureCode','ExecutionEvidenceSource'});
end
