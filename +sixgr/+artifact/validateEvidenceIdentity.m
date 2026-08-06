function result = validateEvidenceIdentity(T, expected, artifactName, options)
%VALIDATEEVIDENCEIDENTITY Reject cross-run/config/scope artifact evidence.

arguments
    T table
    expected (1,1) struct
    artifactName {mustBeTextScalar}
    options.RequireIdentityColumns (1,1) logical = true
    options.RequireRadioIdentityColumns (1,1) logical = true
end

artifactName = string(artifactName);
expected = localNormalizeExpected(expected);
localVerifyExpectedConfigHash(expected);

checks = repmat(struct("Field","", "Column","", "Expected","", ...
    "Observed","", "Pass",false), 0, 1);
identitySpecs = {
    "ScenarioID", ["ScenarioID","ScenarioId","scenario_id"]
    "ConfigHash", ["ConfigHash","config_hash"]
    "EvidenceScope", ["EvidenceScope","evidence_scope"]
    "RunID", ["RunID","RunId","run_id"]
    "ExecutionID", ["ExecutionID","ExecutionId","execution_id"]
    };
for index = 1:size(identitySpecs, 1)
    field = identitySpecs{index, 1};
    aliases = identitySpecs{index, 2};
    expectedValue = string(expected.(field));
    required = options.RequireIdentityColumns && ...
        any(field == ["ScenarioID","ConfigHash","EvidenceScope"]);
    if any(field == ["RunID","ExecutionID"])
        required = options.RequireIdentityColumns && strlength(expectedValue) > 0;
    end
    [present, column] = localFindColumn(T, aliases);
    if ~present
        if required
            error("sixgr:artifact:IdentityColumnMissing", ...
                "Artifact %s is missing required identity column %s.", ...
                artifactName, field);
        end
        continue;
    end
    observed = strtrim(string(T.(column)));
    if any(ismissing(observed) | strlength(observed) == 0)
        error("sixgr:artifact:BlankIdentityValue", ...
            "Artifact %s contains blank %s values.", artifactName, field);
    end
    if field == "EvidenceScope"
        allowed = ["in_path","component_anchor","diagnostic","proxy"];
        if any(~ismember(lower(observed), allowed))
            error("sixgr:artifact:InvalidEvidenceScope", ...
                "Artifact %s contains unsupported EvidenceScope values.", artifactName);
        end
    end
    pass = strlength(expectedValue) == 0 || all(observed == expectedValue);
    if ~pass
        error("sixgr:artifact:EvidenceIdentityMismatch", ...
            "Artifact %s %s differs from the expected value '%s' (observed: %s).", ...
            artifactName, field, expectedValue, strjoin(unique(observed), "|"));
    end
    checks(end+1,1) = localCheck(field, column, expectedValue, ... %#ok<AGROW>
        strjoin(unique(observed), "|"), pass);
end

if expected.EvidenceScope == "in_path"
    [present, column] = localFindColumn(T, ["EvidenceScope","evidence_scope"]);
    if present && any(lower(strtrim(string(T.(column)))) ~= "in_path")
        error("sixgr:artifact:ComponentAnchorCannotSatisfyInPathContract", ...
            "Artifact %s includes non-in-path evidence in an in-path publication.", artifactName);
    end
end

radioSpecs = {
    "CenterFrequencyHz", ["CenterFrequencyHz","CarrierFrequencyHz","FrequencyHz"], 1
    "BandwidthHz", ["BandwidthHz","ChannelBandwidthHz"], 1
    "SubcarrierSpacingHz", ["SubcarrierSpacingHz","SCSHz"], 1
    };
for index = 1:size(radioSpecs, 1)
    field = radioSpecs{index, 1};
    aliases = radioSpecs{index, 2};
    expectedValue = double(expected.(field));
    required = options.RequireRadioIdentityColumns && isfinite(expectedValue);
    [present, column] = localFindColumn(T, aliases);
    if ~present
        if required
            error("sixgr:artifact:RadioIdentityColumnMissing", ...
                "Artifact %s is missing required radio identity column %s.", ...
                artifactName, field);
        end
        continue;
    end
    observed = localNumeric(T.(column));
    tolerance = max(1e-9, abs(expectedValue) * 1e-12);
    pass = all(isfinite(observed)) && all(abs(observed - expectedValue) <= tolerance);
    if ~pass
        error("sixgr:artifact:RadioIdentityMismatch", ...
            "Artifact %s %s differs from %.15g (observed: %s).", ...
            artifactName, field, expectedValue, strjoin(string(unique(observed)), "|"));
    end
    checks(end+1,1) = localCheck(field, column, string(expectedValue), ... %#ok<AGROW>
        strjoin(string(unique(observed)), "|"), pass);
end

if isempty(checks)
    result = table('Size',[0 5], ...
        'VariableTypes',{'string','string','string','string','logical'}, ...
        'VariableNames',{'Field','Column','Expected','Observed','Pass'});
else
    result = struct2table(checks, 'AsArray', true);
end
end

function expected = localNormalizeExpected(expected)
textFields = ["ScenarioID","ConfigHash","EvidenceScope","RunID","ExecutionID"];
for field = textFields
    if ~isfield(expected, field)
        expected.(field) = "";
    else
        expected.(field) = strtrim(string(expected.(field)));
        if ~isscalar(expected.(field))
            error("sixgr:artifact:NonScalarExpectedIdentity", ...
                "Expected identity field %s must be scalar.", field);
        end
    end
end
if strlength(expected.EvidenceScope) == 0
    expected.EvidenceScope = "in_path";
end
for field = ["CenterFrequencyHz","BandwidthHz","SubcarrierSpacingHz"]
    if ~isfield(expected, field) || isempty(expected.(field))
        expected.(field) = NaN;
    else
        values = double(expected.(field));
        expected.(field) = values(1);
    end
end
end

function localVerifyExpectedConfigHash(expected)
if ~isfield(expected, "NormalizedConfig") || isempty(expected.NormalizedConfig)
    return;
end
computed = sixgr.integration.IntegrationHash.data(expected.NormalizedConfig);
if strlength(expected.ConfigHash) == 0 || lower(computed) ~= lower(expected.ConfigHash)
    error("sixgr:artifact:NormalizedConfigHashMismatch", ...
        "Normalized scenario configuration hashes to %s, not exported ConfigHash %s.", ...
        computed, expected.ConfigHash);
end
end

function [present, column] = localFindColumn(T, aliases)
names = string(T.Properties.VariableNames);
index = find(ismember(lower(names), lower(string(aliases))), 1, "first");
present = ~isempty(index);
if present
    column = char(names(index));
else
    column = '';
end
end

function values = localNumeric(raw)
if isnumeric(raw)
    values = double(raw(:));
else
    values = str2double(string(raw(:)));
end
end

function row = localCheck(field, column, expected, observed, pass)
row = struct("Field",string(field), "Column",string(column), ...
    "Expected",string(expected), "Observed",string(observed), "Pass",logical(pass));
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:artifact:TextScalarRequired", ...
        "Artifact identity name must be a text scalar.");
end
end
