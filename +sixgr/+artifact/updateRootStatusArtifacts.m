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
    fieldName = string(updates{index, 1});
    try
        T.(char(fieldName)) = localTableScalar(updates{index, 2});
    catch cause
        wrapped = MException("sixgr:artifact:RootStatusAssignmentFailed", ...
            "Could not assign scalar root status field %s: %s", ...
            fieldName, string(cause.message));
        wrapped = addCause(wrapped, cause);
        throw(wrapped);
    end
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
    "ScenarioObjectiveOk"; "ScenarioObjectivePassed"; ...
    "ScenarioObjectiveEvidenceAvailable"; "ScenarioObjectiveStatus"; ...
    "ResultOk"; "PublicationQualified"; ...
    "PublicationQualificationStatus"; "StrictAnchorPass"; ...
    "ResultStatusReason"; "FunctionalRunOk"; "WiringCoverageOk"; ...
    "WiringCoverageStatus"; "NumericalValidationOk"; ...
    "NumericalValidationStatus"; "ReferenceQualificationOk"; ...
    "ReferenceQualificationStatus"; "ScientificQualificationOk"; ...
    "ScientificQualificationStatus"; "TerminalPublicationGatesOk"; ...
    "TerminalPublicationGateStatus"; "ProductionGradeOk"; ...
    "PublicationReady"; "OverallQualificationStatus"; ...
    "ProductionQualificationFailureReasons"; ...
    "ProductionQualificationProducer"; ...
    "ProductionQualificationSchemaVersion"];
updates = cell(numel(names), 2);
for index = 1:numel(names)
    updates{index, 1} = names(index);
    updates{index, 2} = sixgr.util.structGet(status, names(index), "");
end
end

function value = localTableScalar(value)
% Older persisted status JSON can contain [] for an absent optional text
% field. jsondecode returns that token as a 0-by-0 double. In a one-row
% status table the faithful scalar representation is an empty text cell,
% not a zero-row numeric column.
if isempty(value)
    value = "";
elseif islogical(value)
    value = logical(value);
elseif isnumeric(value)
    value = double(value);
else
    % jsondecode represents an empty JSON string as a 0-by-0 char array.
    % string(char.empty) is a 0-by-0 string array, which cannot be assigned
    % to the canonical one-row status table.  Preserve the semantic empty
    % value as one scalar empty string; never truncate a genuinely
    % multi-valued status field.
    if ischar(value) && isempty(value)
        value = "";
    else
        value = string(value);
    end
    if ~isscalar(value)
        error("sixgr:artifact:RootStatusValueNotScalar", ...
            "Root status fields must be scalar; received a %s value.", ...
            mat2str(size(value)));
    end
end
end
