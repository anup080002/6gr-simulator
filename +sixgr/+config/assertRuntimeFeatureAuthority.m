function authority = assertRuntimeFeatureAuthority(cfg)
%ASSERTRUNTIMEFEATUREAUTHORITY Ensure YAML feature flags were not bypassed.

arguments
    cfg (1,1) struct
end

authority = sixgr.util.structGet(cfg, "runtime.features", struct());
isYAMLScenario = isstruct(sixgr.util.structGet(cfg, ...
    "lls6g.resolvedConfig", []));
if isempty(fieldnames(authority))
    if isYAMLScenario
        error("sixgr:config:MissingRuntimeFeatureAuthority", ...
            "A resolved YAML scenario reached execution without runtime.features authority.");
    end
    return;
end

featureNames = fieldnames(authority);
for index = 1:numel(featureNames)
    feature = authority.(featureNames{index});
    enabled = sixgr.util.structGet(feature, "Enabled", []);
    if ~localIsBooleanScalar(enabled)
        error("sixgr:config:InvalidRuntimeFeatureAuthority", ...
            "runtime.features.%s.Enabled must be a boolean scalar.", ...
            featureNames{index});
    end
    paths = string(sixgr.util.structGet(feature, ...
        "RuntimeConsumerPaths", strings(0, 1)));
    if isempty(paths)
        error("sixgr:config:MissingRuntimeFeatureConsumer", ...
            "runtime.features.%s declares no runtime consumer.", ...
            featureNames{index});
    end
    for path = paths(:).'
        value = sixgr.util.structGet(cfg, path, []);
        if ~localIsBooleanScalar(value)
            error("sixgr:config:MissingRuntimeFeatureConsumer", ...
                "runtime.features.%s has no boolean consumer at %s.", ...
                featureNames{index}, char(path));
        end
        if logical(value) ~= logical(enabled)
            error("sixgr:config:YAMLFeatureAuthorityBypassed", ...
                "YAML feature %s=%d was bypassed by runtime consumer %s=%d.", ...
                char(string(sixgr.util.structGet(feature, ...
                "SourceYAMLPath", featureNames{index}))), ...
                logical(enabled), char(path), logical(value));
        end
    end
end
end

function tf = localIsBooleanScalar(value)
tf = (islogical(value) || isnumeric(value)) && isscalar(value) && ...
    isfinite(double(value)) && any(double(value) == [0 1]);
end
