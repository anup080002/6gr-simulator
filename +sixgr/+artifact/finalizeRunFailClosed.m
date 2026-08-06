function result = finalizeRunFailClosed(runFolder, evidence, scenarioConfig, runtimeIdentity)
%FINALIZERUNFAILCLOSED Finalize configured artifacts without hiding failure.
%
% A contract failure is a publication failure, not an execution exception.
% The underlying generator writes its complete audit before throwing.  This
% coordinator preserves that audit and returns a typed status so the root
% reducer can distinguish completed PHY execution from failed publication.

if nargin < 4 || isempty(runtimeIdentity)
    runtimeIdentity = struct();
end
result = localEmptyResult();
try
    generated = sixgr.artifact.finalizeConfiguredRun( ...
        runFolder, evidence, scenarioConfig, runtimeIdentity);
    result = localMerge(result, generated);
    result.Executed = logical(sixgr.util.structGet(generated, "Enabled", false));
    result.Ok = logical(sixgr.util.structGet(generated, "Ok", false));
    result.ContractCount = double(sixgr.util.structGet(generated, ...
        "CatalogCount", result.ContractCount));
    if result.Executed
        result.AuditPath = string(fullfile(runFolder, "artifact_generation", ...
            "artifact_generation_results.csv"));
        result.FailurePath = string(fullfile(runFolder, "artifact_generation", ...
            "artifact_generation_failures.csv"));
    end
    if ~result.Executed
        result.Status = "DISABLED_BY_YAML";
    elseif result.Ok
        result.Status = "PASS";
    else
        result.Status = "FAIL";
    end
catch cause
    result.Executed = true;
    result.Ok = false;
    result.Status = "FAIL";
    result.ErrorIdentifier = string(cause.identifier);
    result.ErrorMessage = string(cause.message);
    [result.ContractCount, result.FailureCount, ...
        result.RequiredFailureCount, result.AuditPath, result.FailurePath] = ...
        localReadPersistedAudit(runFolder);
end

statusPath = fullfile(runFolder, "artifact_generation", ...
    "artifact_contract_finalization_status.json");
if result.Executed || isfolder(fileparts(statusPath))
    sixgr.util.jsonWrite(statusPath, struct( ...
        "SchemaName", "sixgr.artifact.finalization_status", ...
        "SchemaVersion", "1.0.0", ...
        "Status", char(result.Status), ...
        "Executed", logical(result.Executed), ...
        "Ok", logical(result.Ok), ...
        "ContractCount", double(result.ContractCount), ...
        "FailureCount", double(result.FailureCount), ...
        "RequiredFailureCount", double(result.RequiredFailureCount), ...
        "ErrorIdentifier", char(result.ErrorIdentifier), ...
        "ErrorMessage", char(result.ErrorMessage), ...
        "AuditPath", char(result.AuditPath), ...
        "FailurePath", char(result.FailurePath)));
end
end

function result = localEmptyResult()
result = struct( ...
    "Ok", false, ...
    "Executed", false, ...
    "Enabled", false, ...
    "Status", "NOT_EVALUATED", ...
    "ContractCount", 0, ...
    "CSVCount", 0, ...
    "PNGCount", 0, ...
    "FailureCount", 0, ...
    "RequiredFailureCount", 0, ...
    "AuditPath", "", ...
    "FailurePath", "", ...
    "ErrorIdentifier", "", ...
    "ErrorMessage", "");
end

function [contractCount, failureCount, requiredFailureCount, auditPath, failurePath] = ...
        localReadPersistedAudit(runFolder)
auditPath = string(fullfile(runFolder, "artifact_generation", ...
    "artifact_generation_results.csv"));
failurePath = string(fullfile(runFolder, "artifact_generation", ...
    "artifact_generation_failures.csv"));
contractCount = 0;
failureCount = 0;
requiredFailureCount = 0;
if isfile(auditPath)
    try
        audit = readtable(auditPath, "VariableNamingRule", "preserve", ...
            "TextType", "string");
        contractCount = height(audit);
        if ismember("Status", string(audit.Properties.VariableNames))
            failed = upper(strtrim(string(audit.Status))) ~= "PASS";
            failureCount = nnz(failed);
            if ismember("Required", string(audit.Properties.VariableNames))
                requiredFailureCount = nnz(failed & localLogical(audit.Required));
            else
                requiredFailureCount = failureCount;
            end
        end
    catch
        contractCount = 0;
        failureCount = 1;
        requiredFailureCount = 1;
    end
end
end

function value = localLogical(value)
if islogical(value)
    return;
end
if isnumeric(value)
    value = value ~= 0;
    return;
end
value = ismember(lower(strtrim(string(value))), ["true","1","yes","pass","required"]);
end

function out = localMerge(out, extra)
names = fieldnames(extra);
for index = 1:numel(names)
    out.(names{index}) = extra.(names{index});
end
end
