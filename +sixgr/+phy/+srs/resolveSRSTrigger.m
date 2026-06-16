function trigger = resolveSRSTrigger(srsCfg)
%RESOLVESRSTRIGGER Resolve strict SRS trigger provenance.

resourceType = lower(string(srsCfg.ResourceType));
expectedSlot = NaN;
if isfield(srsCfg, "ExpectedSlotSet") && ~isempty(srsCfg.ExpectedSlotSet)
    expectedSlot = double(srsCfg.ExpectedSlotSet(1));
end
trigger = struct("TriggerAttempted", true, "TriggerValid", false, ...
    "TriggerSource", "", "TriggerReferenceId", "", "ExpectedSlot", expectedSlot, ...
    "ObservedSlot", expectedSlot, "Status", "trigger_invalid", "FailureReason", "");
if resourceType == "periodic"
    trigger.TriggerValid = true;
    trigger.TriggerSource = "periodic_srs_resource_set";
    trigger.TriggerReferenceId = "periodic:" + string(srsCfg.Periodicity) + ":" + string(srsCfg.Offset);
    trigger.Status = "periodic_srs_trigger_valid";
elseif resourceType == "aperiodic"
    trigger.TriggerSource = "decoded_dci_srs_request";
    trigger.TriggerReferenceId = string(srsCfg.DCITriggerReferenceId);
    trigger.TriggerValid = strlength(strtrim(trigger.TriggerReferenceId)) > 0;
    if ~trigger.TriggerValid
        trigger.FailureReason = "aperiodic_srs_missing_decoded_dci_trigger_reference";
        trigger.Status = trigger.FailureReason;
    else
        trigger.Status = "aperiodic_srs_trigger_valid";
    end
else
    trigger.TriggerSource = "unsupported_srs_resource_type";
    trigger.FailureReason = "unsupported_srs_resource_type:" + string(srsCfg.ResourceType);
    trigger.Status = trigger.FailureReason;
end
end
