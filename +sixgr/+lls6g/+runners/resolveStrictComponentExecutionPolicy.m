function policy = resolveStrictComponentExecutionPolicy(scfg, cfg, component, runFolder)
%RESOLVESTRICTCOMPONENTEXECUTIONPOLICY Resolve YAML-owned evidence scope.
%
% Strict component validators are component anchors unless the resolved
% scenario explicitly enables same-execution campaigns and lists the
% component as required.  This keeps anchor evidence isolated while making
% it possible to run real waveform validation under the active scenario
% identity without copying or relabeling files after execution.

component = lower(strtrim(string(component)));
runFolder = string(runFolder);
if ~isscalar(component) || strlength(component) == 0
    error("sixgr:lls6g:StrictComponentNameRequired", ...
        "Strict component execution requires one component name.");
end
allowedComponents = ["prach","pdcch","srs","trs","sib1","channel_rf"];
if ~ismember(component, allowedComponents)
    error("sixgr:lls6g:UnsupportedStrictComponent", ...
        "Unsupported strict in-path component %s.", component);
end

section = sixgr.util.structGet(cfg, ...
    "validation.strict_component_evidence", struct());
if ~(isstruct(section) && isscalar(section))
    section = struct();
end
enabled = logical(sixgr.util.structGet(section, "enabled", ...
    localScenarioGet(scfg, "validation.strict_component_evidence.enabled", false)));
scope = lower(strtrim(string(sixgr.util.structGet(section, ...
    "execution_scope", localScenarioGet(scfg, ...
    "validation.strict_component_evidence.execution_scope", ...
    "component_anchor")))));
if ~isscalar(scope) || ~ismember(scope, ["component_anchor","in_path"])
    error("sixgr:lls6g:InvalidStrictComponentExecutionScope", ...
        "validation.strict_component_evidence.execution_scope must be " + ...
        "component_anchor or in_path; received %s.", scope);
end
required = localStringVector(sixgr.util.structGet(section, ...
    "required_components", localScenarioGet(scfg, ...
    "validation.strict_component_evidence.required_components", ...
    strings(0, 1))));
required = lower(strtrim(required));
required = unique(required(strlength(required) > 0), "stable");
unsupported = setdiff(required, allowedComponents, "stable");
if ~isempty(unsupported)
    error("sixgr:lls6g:UnsupportedStrictComponent", ...
        "Unsupported strict component(s): %s.", strjoin(unsupported, ", "));
end

isRequired = enabled && ismember(component, required);
inPath = isRequired && scope == "in_path";
if inPath
    artifactRoot = runFolder;
    evidenceScope = "in_path";
else
    artifactRoot = string(sixgr.runtime.prepareComponentAnchorRoot( ...
        runFolder, component, scfg, cfg));
    evidenceScope = "component_anchor";
end

runId = strtrim(string(sixgr.util.structGet(cfg, "run.runTag", "")));
executionId = strtrim(string(sixgr.util.structGet(cfg, ...
    "run.executionID", sixgr.util.structGet(cfg, "meta.executionID", ""))));
configHash = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "meta.configHash", localScenarioGet(scfg, "ConfigHash", "")))));
scenarioId = strtrim(string(sixgr.util.structGet(cfg, ...
    "run.scenarioID", localScenarioGet(scfg, "ScenarioID", ""))));
if inPath && (~isscalar(runId) || strlength(runId) == 0 || ...
        ~isscalar(executionId) || strlength(executionId) == 0 || ...
        ~isscalar(configHash) || strlength(configHash) ~= 64)
    error("sixgr:lls6g:InPathEvidenceIdentityMissing", ...
        "In-path strict component %s requires immutable RunID, " + ...
        "ExecutionID and ConfigHash before waveform execution.", component);
end
validatorRunId = scenarioId;
bindingExecutionId = "";
bindingConfigHash = "";
if inPath
    validatorRunId = runId;
    bindingExecutionId = executionId;
    bindingConfigHash = configHash;
end

policy = struct( ...
    "Component", component, ...
    "Enabled", enabled, ...
    "Required", isRequired, ...
    "ExecutionScope", evidenceScope, ...
    "SameScenarioInPathEligible", inPath, ...
    "ArtifactRoot", artifactRoot, ...
    "RunID", runId, ...
    "ValidatorRunID", validatorRunId, ...
    "ExecutionID", executionId, ...
    "ConfigHash", configHash, ...
    "ScenarioID", scenarioId, ...
    "BindingExecutionID", bindingExecutionId, ...
    "BindingConfigHash", bindingConfigHash);
end

function value = localScenarioGet(scfg, path, defaultValue)
value = defaultValue;
try
    if isobject(scfg) && ismethod(scfg, "get")
        value = scfg.get(path, defaultValue);
    elseif isstruct(scfg)
        value = sixgr.util.structGet(scfg, path, defaultValue);
    end
catch
    value = defaultValue;
end
end

function values = localStringVector(raw)
if isempty(raw)
    values = strings(0, 1);
elseif iscell(raw)
    values = string(raw(:));
else
    values = string(raw(:));
end
end
