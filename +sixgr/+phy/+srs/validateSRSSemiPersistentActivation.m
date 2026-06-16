function T = validateSRSSemiPersistentActivation(srsCfg)
%VALIDATESRSSEMIPERSISTENTACTIVATION Fail closed unless activation evidence exists.

isSemi = ismember(lower(string(srsCfg.ResourceType)), ["semipersistent","semi-persistent"]);
activationId = string(srsCfg.ActivationMACCEReferenceId);
valid = isSemi && strlength(strtrim(activationId)) > 0;
if ~isSemi
    status = "not_applicable";
elseif valid
    status = "activation_reference_present";
else
    status = "semi_persistent_activation_missing_fail_closed";
end
T = struct2table(struct("RunId", string(srsCfg.RunId), ...
    "ResourceType", string(srsCfg.ResourceType), ...
    "ActivationValidationAttempted", logical(isSemi), ...
    "ActivationValid", logical(valid), ...
    "ActivationMACCEReferenceId", activationId, ...
    "Status", string(status), "ConfigHash", string(srsCfg.ConfigHash), ...
    "TruthStatus", "real_lls_evidence"), "AsArray", true);
end
