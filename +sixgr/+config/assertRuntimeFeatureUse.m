function enabled = assertRuntimeFeatureUse(cfg, featureName, actualValue, consumerName)
%ASSERTRUNTIMEFEATUREUSE Bind a production consumer to resolved YAML state.
% Manual/unit configurations without a resolved runtime authority retain
% their explicit object/config behavior.  Once a YAML scenario installs
% runtime.features, every guarded consumer must exactly match it.

arguments
    cfg (1,1) struct
    featureName (1,1) string
    actualValue
    consumerName (1,1) string = "runtime_consumer"
end

features = sixgr.util.structGet(cfg, "runtime.features", struct());
resolved = sixgr.util.structGet(cfg, "lls6g.resolvedConfig", []);
hasResolvedScenario = isstruct(resolved) && ~isempty(fieldnames(resolved));
hasAuthority = isstruct(features) && ~isempty(fieldnames(features));
if ~hasResolvedScenario && ~hasAuthority
    enabled = localBoolean(actualValue, "actual runtime feature value");
    return;
end
if ~hasAuthority
    error("sixgr:config:MissingRuntimeFeatureAuthority", ...
        "Resolved YAML consumer %s reached execution without runtime.features authority.", ...
        char(consumerName));
end

fieldName = char(featureName);
if ~isfield(features, fieldName)
    error("sixgr:config:MissingRuntimeFeature", ...
        "Resolved YAML consumer %s has no authority entry runtime.features.%s.", ...
        char(consumerName), fieldName);
end
feature = features.(fieldName);
enabled = localBoolean(sixgr.util.structGet(feature, "Enabled", []), ...
    "runtime feature authority");
actual = localBoolean(actualValue, "actual runtime feature value");
if actual ~= enabled
    error("sixgr:config:YAMLFeatureExecutionMismatch", ...
        ['YAML feature %s=%d, but production consumer %s resolved %d. ' ...
         'The YAML operating authority cannot be overridden by MATLAB defaults or explicit objects.'], ...
        char(string(sixgr.util.structGet(feature, "SourceYAMLPath", featureName))), ...
        enabled, char(consumerName), actual);
end
end

function value = localBoolean(raw, label)
if ~((islogical(raw) || isnumeric(raw)) && isscalar(raw) && ...
        isfinite(double(raw)) && any(double(raw) == [0 1]))
    error("sixgr:config:InvalidRuntimeFeatureValue", ...
        "%s must be a boolean scalar.", char(label));
end
value = logical(raw);
end
