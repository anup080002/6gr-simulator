function status = applyFinalizationGate(status, finalization)
%APPLYFINALIZATIONGATE Reduce runtime-only artifact publication fail closed.
%
% PHY execution, scenario-objective and standards-conformance states remain
% independent. This gate controls overall result/publication qualification
% only; missing contract evidence must never become a green run.

if ~(isstruct(status) && isscalar(status))
    error("sixgr:artifact:ScenarioStatusRequired", ...
        "Artifact finalization reduction requires a scalar scenario status.");
end
if ~(isstruct(finalization) && isscalar(finalization))
    error("sixgr:artifact:FinalizationStatusRequired", ...
        "Artifact finalization reduction requires a scalar finalization result.");
end

executed = logical(sixgr.util.structGet(finalization, "Executed", false));
enabled = logical(sixgr.util.structGet(finalization, "Enabled", executed));
required = executed || enabled;
reportedStatus = upper(strtrim(string(sixgr.util.structGet( ...
    finalization, "Status", "NOT_EVALUATED"))));
requiredFailures = double(sixgr.util.structGet(finalization, ...
    "RequiredFailureCount", 0));
failureCount = double(sixgr.util.structGet(finalization, "FailureCount", 0));
contractCount = double(sixgr.util.structGet(finalization, "ContractCount", 0));
ok = required && executed && ...
    logical(sixgr.util.structGet(finalization, "Ok", false)) && ...
    reportedStatus == "PASS" && requiredFailures == 0;

status.ArtifactContractRequired = logical(required);
status.ArtifactContractExecuted = logical(executed);
status.ArtifactContractGateOk = logical(ok || ~required);
status.ArtifactContractStatus = localGateStatus(required, executed, ok);
status.ArtifactContractCount = contractCount;
status.ArtifactContractFailureCount = failureCount;
status.ArtifactContractRequiredFailureCount = requiredFailures;
status.ArtifactContractAuditPath = string(sixgr.util.structGet( ...
    finalization, "AuditPath", ""));
status.ArtifactContractFailurePath = string(sixgr.util.structGet( ...
    finalization, "FailurePath", ""));
status.ArtifactContractErrorIdentifier = string(sixgr.util.structGet( ...
    finalization, "ErrorIdentifier", ""));
status.ArtifactContractErrorMessage = string(sixgr.util.structGet( ...
    finalization, "ErrorMessage", ""));

if ~required || ok
    return;
end

failureToken = localFailureToken(finalization, executed, requiredFailures);
status.ResultOk = false;
status.CaseOk = false;
status.PartialOk = logical(sixgr.util.structGet(status, ...
    "ArtifactsGenerated", false));
if logical(sixgr.util.structGet(status, "RunCompleted", false))
    status.RunCompletion = "completed_with_failures";
end
status.ArtifactCompletenessOk = false;
status.PublicationQualified = false;
status.PublicationQualificationStatus = "FAIL";
status.StrictAnchorPass = false;
status.RequiredFailureCount = double(sixgr.util.structGet(status, ...
    "RequiredFailureCount", 0)) + max(1, requiredFailures);
failed = string(sixgr.util.structGet(status, ...
    "RequiredFailedCases", strings(0, 1)));
failed = failed(strlength(strtrim(failed)) > 0);
status.RequiredFailedCases = unique([failed(:); failureToken], "stable");
status.FailingCaseCount = numel(status.RequiredFailedCases);
status.AuthoritativeStatusSource = "runtime_artifact_contract_gate";
status.StatusAuthority = "scenario_status_aggregation_v3_artifact_contract";
status.StatusNotes = localJoinNotes(string(sixgr.util.structGet( ...
    status, "StatusNotes", "")), ...
    "Runtime-only artifact publication is required and did not satisfy every required CSV/PNG contract.");
status.ResultStatusReason = localJoinNotes(string(sixgr.util.structGet( ...
    status, "ResultStatusReason", "")), failureToken);
if strlength(string(sixgr.util.structGet(status, "ErrorIdentifier", ""))) == 0
    status.ErrorSource = "runtime_artifact_contract_gate";
    status.ErrorIdentifier = string(sixgr.util.structGet(finalization, ...
        "ErrorIdentifier", "sixgr:artifact:RequiredArtifactGenerationFailed"));
    if strlength(status.ErrorIdentifier) == 0
        status.ErrorIdentifier = "sixgr:artifact:RequiredArtifactGenerationFailed";
    end
    status.ErrorMessage = string(sixgr.util.structGet(finalization, ...
        "ErrorMessage", failureToken));
end
end

function value = localGateStatus(required, executed, ok)
if ~required
    value = "NOT_APPLICABLE";
elseif ~executed
    value = "NOT_EVALUATED";
elseif ok
    value = "PASS";
else
    value = "FAIL";
end
end

function token = localFailureToken(finalization, executed, requiredFailures)
identifier = strtrim(string(sixgr.util.structGet(finalization, ...
    "ErrorIdentifier", "")));
if ~executed
    reason = "required_finalization_not_executed";
elseif strlength(identifier) > 0
    reason = identifier;
elseif requiredFailures > 0
    reason = "required_artifacts_missing_or_invalid";
else
    reason = "artifact_finalization_failed";
end
token = "artifact_contract_finalization:" + reason;
end

function value = localJoinNotes(left, right)
left = strtrim(string(left));
right = strtrim(string(right));
if strlength(left) == 0
    value = right;
elseif strlength(right) == 0 || contains(left, right)
    value = left;
else
    value = left + " " + right;
end
end
