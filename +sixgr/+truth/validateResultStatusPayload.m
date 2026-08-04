function validateResultStatusPayload(payload)
%VALIDATERESULTSTATUSPAYLOAD Enforce canonical strict-anchor status schema.

required = ["RunId","ScenarioName","ScenarioClass","ScenarioMode","ClaimProfile","ClaimStatus","ClaimAllowed", ...
    "RunCompleted","ArtifactsWritten","ArtifactCompletenessOk","TruthContractOk","RuntimeTruthContractOk","StandardsConformanceOk", ...
    "ScenarioObjectiveOk","ConfiguredEffectiveOk","MandatorySubsystemsOk","ActiveIssueGateOk","KpiConsistencyOk", ...
    "VisualArtifactGateOk","DuplicateArtifactGateOk","ResultOk","ActiveCriticalIssueCount","ActiveHighIssueCount", ...
    "ActiveMediumIssueCount","ActiveMandatoryIssueCount","ProxyEvidenceCount","SkippedEvidenceCount","FallbackEvidenceCount", ...
    "UnavailableMandatoryCount","PartialMandatoryCount","ReviewRequiredMandatoryCount","ConfiguredEffectiveMismatchCount", ...
    "StrictAnchorEligible","StrictAnchorPass","ResultStatusReason","StrictAnchorFailureReasons","ProducerModule","GeneratedAt","SchemaVersion"];

if istable(payload)
    names = string(payload.Properties.VariableNames);
    rowCount = height(payload);
elseif isstruct(payload)
    names = string(fieldnames(payload));
    rowCount = numel(payload);
else
    error("sixgr:truth:ResultStatusPayloadBadType", ...
        "Result status payload must be a table or struct.");
end

missing = setdiff(required, names, "stable");
if ~isempty(missing)
    error("sixgr:truth:ResultStatusPayloadMissingFields", ...
        "Result status payload is missing required fields: %s", strjoin(missing, ", "));
end
if rowCount ~= 1
    error("sixgr:truth:ResultStatusPayloadRowCount", ...
        "Result status payload must contain exactly one row.");
end
end
