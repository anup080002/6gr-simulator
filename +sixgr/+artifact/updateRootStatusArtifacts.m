function updateRootStatusArtifacts(runFolder, status)
%UPDATEROOTSTATUSARTIFACTS Persist the post-finalization publication gate.

if ~(isstruct(status) && isscalar(status))
    error("sixgr:artifact:ScenarioStatusRequired", ...
        "Root status publication requires a scalar scenario status.");
end
runFolder = char(string(runFolder));
csvPath = fullfile(runFolder, "reports", "csv", "result_status_summary.csv");
jsonPath = fullfile(runFolder, "reports", "json", "result_status_summary.json");
if ~isfile(csvPath) || ~isfile(jsonPath)
    error("sixgr:artifact:RootStatusArtifactMissing", ...
        "Post-finalization reduction requires existing canonical CSV and JSON root status artifacts.");
end

T = readtable(csvPath, "VariableNamingRule", "preserve", "TextType", "string");
if height(T) ~= 1
    error("sixgr:artifact:RootStatusArtifactRowCount", ...
        "Canonical result_status_summary.csv must contain exactly one row.");
end
updates = localUpdates(status);
for index = 1:size(updates, 1)
    T.(char(updates{index, 1})) = localTableScalar(updates{index, 2});
end
jsonStatus = jsondecode(fileread(jsonPath));
for index = 1:size(updates, 1)
    jsonStatus.(char(updates{index, 1})) = updates{index, 2};
end
% Validate both representations before replacing either canonical file.
% A malformed JSON status must not leave CSV and JSON with different root
% verdicts.
sixgr.truth.validateResultStatusPayload(T);
sixgr.truth.validateResultStatusPayload(jsonStatus);
sixgr.util.csvWriteTable(csvPath, T, "PreserveSchema", true);
sixgr.util.jsonWrite(jsonPath, jsonStatus);
end

function updates = localUpdates(status)
names = ["ArtifactContractRequired"; "ArtifactContractExecuted"; ...
    "ArtifactContractGateOk"; "ArtifactContractStatus"; ...
    "ArtifactContractCount"; "ArtifactContractFailureCount"; ...
    "ArtifactContractRequiredFailureCount"; "ArtifactContractAuditPath"; ...
    "ArtifactContractFailurePath"; "ArtifactContractErrorIdentifier"; ...
    "ArtifactContractErrorMessage"; "ArtifactCompletenessOk"; ...
    "ResultOk"; "PublicationQualified"; ...
    "PublicationQualificationStatus"; "StrictAnchorPass"; ...
    "ResultStatusReason"];
updates = cell(numel(names), 2);
for index = 1:numel(names)
    updates{index, 1} = names(index);
    updates{index, 2} = sixgr.util.structGet(status, names(index), "");
end
end

function value = localTableScalar(value)
if islogical(value)
    value = logical(value);
elseif isnumeric(value)
    value = double(value);
else
    value = string(value);
end
end
