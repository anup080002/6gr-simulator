function value = bindInPathArtifactIdentity(value, identity, evidenceScope)
%BINDINPATHARTIFACTIDENTITY Bind fresh execution evidence before export.
%
% Component-specific ConfigHash columns remain intact and are mirrored to
% ComponentConfigHash.  ScenarioConfigHash and ExecutionID identify the
% active scenario execution.  Existing contradictory identity values fail
% closed rather than being overwritten.

if nargin < 3 || strlength(strtrim(string(evidenceScope))) == 0
    evidenceScope = "in_path";
end
evidenceScope = lower(strtrim(string(evidenceScope)));
if ~isscalar(evidenceScope) || ...
        ~ismember(evidenceScope, ["in_path","same_execution_campaign"])
    error("sixgr:runtime:InvalidRuntimeEvidenceScope", ...
        "Runtime evidence scope must be in_path or same_execution_campaign.");
end
identity = localValidateIdentity(identity);
value = localBindValue(value, identity, evidenceScope);
end

function value = localBindValue(value, identity, evidenceScope)
if istable(value)
    value = localBindTable(value, identity, evidenceScope);
    return;
end
if ~(isstruct(value) && isscalar(value))
    return;
end
names = fieldnames(value);
for index = 1:numel(names)
    name = names{index};
    child = value.(name);
    if istable(child) || (isstruct(child) && isscalar(child))
        value.(name) = localBindValue(child, identity, evidenceScope);
    end
end
end

function T = localBindTable(T, identity, evidenceScope)
n = height(T);
if ismember("ConfigHash", string(T.Properties.VariableNames)) && ...
        ~ismember("ComponentConfigHash", string(T.Properties.VariableNames))
    T.ComponentConfigHash = string(T.ConfigHash);
end
T = localBindText(T, "RunID", identity.RunID, n);
T = localBindText(T, "ExecutionID", identity.ExecutionID, n);
T = localBindText(T, "ScenarioID", identity.ScenarioID, n);
T = localBindText(T, "ScenarioConfigHash", identity.ConfigHash, n);
T = localBindText(T, "EvidenceScope", evidenceScope, n);
inPathEligible = evidenceScope == "in_path";
if inPathEligible && ismember("SameScenarioInPathEligible", string(T.Properties.VariableNames))
    existing = logical(T.SameScenarioInPathEligible);
    if any(~existing)
        error("sixgr:runtime:InPathEvidenceEligibilityMismatch", ...
            "Fresh in-path evidence contains rows marked ineligible.");
    end
end
T.SameScenarioInPathEligible = repmat(inPathEligible, n, 1);
end

function T = localBindText(T, name, expected, n)
expected = string(expected);
names = string(T.Properties.VariableNames);
matchingIndices = find(strcmpi(names, string(name)));
if numel(matchingIndices) > 1
    error("sixgr:runtime:DuplicateInPathIdentityColumn", ...
        "Artifact contains case-insensitive duplicate identity columns for %s: %s.", ...
        name, strjoin(names(matchingIndices), "|"));
end
if ~isempty(matchingIndices)
    % Preserve the producer's versioned schema spelling (for example
    % RunId) instead of appending a second, case-only alias (RunID).  CSV
    % consumers commonly use case-insensitive dictionaries and cannot
    % represent both columns without overwriting one of them.
    columnName = names(matchingIndices(1));
    actual = strtrim(string(T.(char(columnName))));
    populated = strlength(actual) > 0;
    if any(populated & actual ~= expected)
        error("sixgr:runtime:InPathEvidenceIdentityMismatch", ...
            "Artifact column %s contradicts the active execution identity.", ...
            columnName);
    end
    T.(char(columnName)) = repmat(expected, n, 1);
    return;
end
T.(char(name)) = repmat(expected, n, 1);
end

function identity = localValidateIdentity(identity)
if ~(isstruct(identity) && isscalar(identity))
    error("sixgr:runtime:InPathEvidenceIdentityRequired", ...
        "In-path artifact identity must be a scalar struct.");
end
for name = ["RunID","ExecutionID","ScenarioID","ConfigHash"]
    value = strtrim(string(sixgr.util.structGet(identity, name, "")));
    if ~isscalar(value) || strlength(value) == 0
        error("sixgr:runtime:InPathEvidenceIdentityRequired", ...
            "In-path artifact identity requires non-empty %s.", name);
    end
    identity.(char(name)) = value;
end
identity.ConfigHash = lower(identity.ConfigHash);
if strlength(identity.ConfigHash) ~= 64 || ...
        isempty(regexp(char(identity.ConfigHash), '^[0-9a-f]{64}$', 'once'))
    error("sixgr:runtime:InPathEvidenceIdentityRequired", ...
        "In-path ConfigHash must be a 64-character SHA-256 digest.");
end
end
