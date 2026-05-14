function T = filterParametersForFeature(bindingMatrix, featureFamily, options)
%FILTERPARAMETERSFORFEATURE Filter the binding matrix to one feature family.

if nargin < 3 || ~isstruct(options)
    options = struct();
end
includeExcluded = logical(sixgr.util.structGet(options, "IncludeExcluded", false));

if ~(istable(bindingMatrix) && ~isempty(bindingMatrix))
    T = bindingMatrix;
    return;
end

featureFamily = string(featureFamily);
T = bindingMatrix;
T.SelectionBucket = repmat("excluded", height(T), 1);
T.ExclusionReason = repmat("", height(T), 1);

featureMask = string(T.FeatureFamily) == featureFamily;
sharedMask = logical(localLogicalColumn(T, "SharedDependency"));

disabledReason = "";
if featureFamily == "Random_Access_PRACH"
    enabledMask = strcmp(string(T.ParameterId), "random_access.enabled");
    if any(enabledMask) && ~any(string(T.ResolvedScenarioValue(enabledMask)) == "1" | lower(string(T.ResolvedScenarioValue(enabledMask))) == "true")
        disabledReason = "feature_disabled_by_config";
    end
end

for i = 1:height(T)
    if featureMask(i)
        if strlength(disabledReason) > 0
            T.SelectionBucket(i) = "excluded";
            T.ExclusionReason(i) = disabledReason;
        else
            T.SelectionBucket(i) = "feature_parameter";
        end
    elseif sharedMask(i)
        T.SelectionBucket(i) = "shared_dependency";
    else
        T.ExclusionReason(i) = "not_applicable_for_selected_feature";
    end
end

if ~includeExcluded
    keep = string(T.SelectionBucket) ~= "excluded";
    T = T(keep, :);
end
end

function values = localLogicalColumn(T, name)
if any(strcmp(string(T.Properties.VariableNames), string(name)))
    values = T.(char(string(name)));
else
    values = false(height(T), 1);
end
values = logical(values);
end
