function audit = validateConfiguredSeedPairing(dropStats, expectedGroupKeys, expectedSeedValues)
%VALIDATECONFIGUREDSEEDPAIRING Verify one YAML seed map at every point.
%
% FixedLinkDropSeed is a task/replay seed.  Independent campaign pairing is
% instead defined by the YAML-owned FixedLinkSeedIndex/Value map.  A valid
% campaign must preserve one bijective index-to-value map and expose every
% configured index at every executed direction/operating-point group.

if nargin < 2
    expectedGroupKeys = strings(0,1);
end
if nargin < 3
    expectedSeedValues = zeros(0,1);
end
expectedGroupKeys = strtrim(string(expectedGroupKeys(:)));
expectedGroupKeys = expectedGroupKeys(strlength(expectedGroupKeys) > 0);
expectedSeedValues = localNumeric(expectedSeedValues);

audit = struct( ...
    "Pass", false, ...
    "FailureCode", "configured_seed_pairing_evidence_missing", ...
    "ObservedGroupCount", 0, ...
    "ExpectedGroupCount", double(numel(expectedGroupKeys)), ...
    "ExpectedSeedCount", double(numel(expectedSeedValues)), ...
    "ConfiguredSeedCount", 0, ...
    "ExpectedSeedSetPass", false, ...
    "IndexValueBijectionOk", false, ...
    "ContiguousIndexSetOk", false, ...
    "EveryGroupContainsFullSeedSet", false);
if ~(istable(dropStats) && height(dropStats) > 0)
    return;
end
if ~isempty(expectedSeedValues) && ...
        (any(~isfinite(expectedSeedValues)) || any(expectedSeedValues < 0) || ...
        any(expectedSeedValues ~= round(expectedSeedValues)) || ...
        numel(unique(expectedSeedValues)) ~= numel(expectedSeedValues))
    audit.FailureCode = "configured_expected_seed_set_invalid";
    return;
end

required = ["Direction","FixedLinkPointIndex", ...
    "FixedLinkSeedIndex","FixedLinkSeedValue", ...
    "SeedLineageComplete","EvidenceStatus"];
if any(~ismember(required, string(dropStats.Properties.VariableNames)))
    audit.FailureCode = "configured_seed_pairing_schema_invalid";
    return;
end

executed = lower(strtrim(string(dropStats.EvidenceStatus))) == ...
    "executed_trial_rows";
rows = dropStats(executed, :);
if isempty(rows)
    audit.FailureCode = "configured_seed_pairing_has_no_executed_rows";
    return;
end

direction = upper(strtrim(string(rows.Direction)));
point = localNumeric(rows.FixedLinkPointIndex);
seedIndex = localNumeric(rows.FixedLinkSeedIndex);
seedValue = localNumeric(rows.FixedLinkSeedValue);
lineage = localLogical(rows.SeedLineageComplete);
valid = lineage & strlength(direction) > 0 & isfinite(point) & ...
    point >= 1 & point == round(point) & isfinite(seedIndex) & ...
    seedIndex >= 1 & seedIndex == round(seedIndex) & ...
    isfinite(seedValue) & seedValue >= 0 & seedValue == round(seedValue);
if ~all(valid)
    audit.FailureCode = "configured_seed_pairing_lineage_invalid";
    return;
end

groupKey = direction + "|" + string(point);
observedGroups = unique(groupKey, "stable");
audit.ObservedGroupCount = double(numel(observedGroups));
if ~isempty(expectedGroupKeys) && ...
        ~isequal(sort(observedGroups), sort(expectedGroupKeys))
    audit.FailureCode = "configured_seed_pairing_operating_group_mismatch";
    return;
end

indices = unique(seedIndex, "sorted");
audit.ConfiguredSeedCount = double(numel(indices));
contiguous = isequal(indices(:), (1:numel(indices)).');
audit.ContiguousIndexSetOk = logical(contiguous);

indexValueBijection = true;
mappedValues = NaN(numel(indices), 1);
for index = 1:numel(indices)
    values = unique(seedValue(seedIndex == indices(index)));
    if numel(values) ~= 1
        indexValueBijection = false;
        break;
    end
    mappedValues(index) = values;
end
if indexValueBijection && numel(unique(mappedValues)) ~= numel(mappedValues)
    indexValueBijection = false;
end
audit.IndexValueBijectionOk = logical(indexValueBijection);
if ~contiguous || ~indexValueBijection
    audit.FailureCode = "configured_seed_index_value_map_not_bijective";
    return;
end

if isempty(expectedSeedValues)
    expectedSeedSetPass = true;
else
    expectedSeedSetPass = isequal(mappedValues(:), expectedSeedValues(:));
end
audit.ExpectedSeedSetPass = logical(expectedSeedSetPass);
if ~expectedSeedSetPass
    audit.FailureCode = "configured_seed_set_does_not_match_yaml";
    return;
end

everyGroup = true;
for groupIndex = 1:numel(observedGroups)
    mask = groupKey == observedGroups(groupIndex);
    groupIndices = unique(seedIndex(mask), "sorted");
    if ~isequal(groupIndices(:), indices(:))
        everyGroup = false;
        break;
    end
    for index = 1:numel(indices)
        groupValues = unique(seedValue(mask & seedIndex == indices(index)));
        if numel(groupValues) ~= 1 || groupValues ~= mappedValues(index)
            everyGroup = false;
            break;
        end
    end
    if ~everyGroup
        break;
    end
end
audit.EveryGroupContainsFullSeedSet = logical(everyGroup);
if ~everyGroup
    audit.FailureCode = "configured_seed_set_not_paired_across_operating_groups";
    return;
end

audit.Pass = true;
audit.FailureCode = "";
end

function values = localNumeric(raw)
if isnumeric(raw) || islogical(raw)
    values = double(raw(:));
else
    values = str2double(string(raw(:)));
end
end

function values = localLogical(raw)
if islogical(raw)
    values = raw(:);
elseif isnumeric(raw)
    values = isfinite(double(raw(:))) & double(raw(:)) ~= 0;
else
    token = lower(strtrim(string(raw(:))));
    values = ismember(token, ["1","true","yes","on","pass","passed"]);
end
end
