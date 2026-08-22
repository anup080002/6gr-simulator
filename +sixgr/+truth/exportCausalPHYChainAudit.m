function out = exportCausalPHYChainAudit(runFolder, scfg, cfg, options)
%EXPORTCAUSALPHYCHAINAUDIT Prove configured PHY stages were actually consumed.
%
% For every YAML-declared stage, bind resolved scenario authority to the
% internal runtime authority, exact runtime-call/profiler evidence, and a
% nonempty measured artifact. Disabled stages must not execute. Enabled
% stages must execute and emit non-proxy measurements. Dependency failures
% are reported as blocked, never as successful downstream execution.

arguments
    runFolder {mustBeTextScalar}
    scfg
    cfg (1,1) struct
    options.RunId (1,1) string = ""
    options.WriteArtifacts (1,1) logical = true
end

runFolder = char(string(runFolder));
layout = sixgr.report.resultLayout(runFolder);
auditCfg = localGetScenarioValue(scfg, ...
    "validation.causal_phy_chain_audit", ...
    sixgr.util.structGet(cfg, "validation.causal_phy_chain_audit", struct()));
enabled = localBoolean(sixgr.util.structGet(auditCfg, "enabled", false), false);
required = localBoolean(sixgr.util.structGet(auditCfg, "required", false), false);
failOnEnabledBypass = localBoolean(sixgr.util.structGet( ...
    auditCfg, "fail_on_enabled_bypass", true), true);
stages = localStructArray(sixgr.util.structGet(auditCfg, "stages", struct([])));
bindings = localStructArray(sixgr.util.structGet( ...
    auditCfg, "parameter_bindings", struct([])));
ledgerT = localReadTable(fullfile(layout.ReportCSVDir, "runtime_call_ledger.csv"));
profileT = localReadTable(fullfile(layout.ReportCSVDir, "runtime_function_profile.csv"));
runId = options.RunId;
if strlength(runId) == 0 && ~isempty(ledgerT) && ...
        ismember("RunId", string(ledgerT.Properties.VariableNames))
    ids = unique(strtrim(string(ledgerT.RunId)), "stable");
    ids(ids == "") = [];
    if numel(ids) == 1
        runId = ids(1);
    end
end
if strlength(runId) == 0
    [~, runId] = fileparts(runFolder);
    runId = string(runId);
end
configHash = string(localGetScenarioProperty(scfg, "ConfigHash", ...
    sixgr.util.structGet(cfg, "meta.configHash", "")));

if ~enabled
    detailT = localEmptyStageTable();
    bindingT = localEmptyBindingTable();
    gateT = localGateTable(runId, configHash, required, false, true, ...
        0, 0, 0, 0, "DISABLED_BY_YAML", "");
    out = localOutput(detailT, bindingT, gateT, runFolder, false, true);
    out.Required = required;
    out.FailOnEnabledBypass = failOnEnabledBypass;
    out.FailureCount = 0;
    if options.WriteArtifacts
        localWriteArtifacts(layout, detailT, bindingT, gateT);
    end
    return;
end

if isempty(stages)
    detailT = localEmptyStageTable();
    bindingT = localBuildParameterBindings(bindings, runId, configHash, ...
        scfg, cfg, ledgerT, profileT);
    gateT = localGateTable(runId, configHash, required, true, false, ...
        0, 0, 0, height(bindingT), "FAILED", ...
        "causal_stage_registry_missing_or_empty");
    out = localOutput(detailT, bindingT, gateT, runFolder, true, false);
    out.Required = required;
    out.FailOnEnabledBypass = failOnEnabledBypass;
    out.FailureCount = height(bindingT) + 1;
    if options.WriteArtifacts
        localWriteArtifacts(layout, detailT, bindingT, gateT);
    end
    return;
end

orders = arrayfun(@(x) double(sixgr.util.structGet(x, "order", NaN)), stages);
if any(~isfinite(orders)) || numel(unique(orders)) ~= numel(orders)
    error("sixgr:truth:CausalPHYChainAuditInvalidOrder", ...
        "Every causal PHY audit stage requires one unique finite order value.");
end
[~, orderIndex] = sort(orders);
stages = stages(orderIndex);

rows = repmat(localEmptyStageRow(), numel(stages), 1);
for stageIndex = 1:numel(stages)
    spec = stages(stageIndex);
    row = localEmptyStageRow();
    row.RunID = runId;
    row.ConfigHash = configHash;
    row.StageOrder = double(sixgr.util.structGet(spec, "order", NaN));
    row.StageID = string(sixgr.util.structGet(spec, "stage_id", ""));
    row.Subsystem = string(sixgr.util.structGet(spec, "subsystem", ""));
    dependencies = localStringList(sixgr.util.structGet( ...
        spec, "dependency_stages", strings(0,1)));
    row.DependencyStage = strjoin(dependencies, "|");
    row.Required = localBoolean(sixgr.util.structGet(spec, "required", true), true);

    [stageEnabled, sourcePath, configuredText, runtimePaths, resolvedText, ...
        mappingMatch, mappingDetails] = localStageAuthority(spec, scfg, cfg);
    row.ScenarioEnablePath = sourcePath;
    row.ConfiguredValue = configuredText;
    row.InternalEnablePaths = strjoin(runtimePaths, "|");
    row.ResolvedValue = resolvedText;
    row.ConfigMappingMatch = mappingMatch;
    row.RequiredForScenario = logical(row.Required && stageEnabled);
    row.ConfigMappingDetails = mappingDetails;

    functions = localStringList(sixgr.util.structGet( ...
        spec, "consumer_functions", strings(0,1)));
    sourceFiles = localStringList(sixgr.util.structGet( ...
        spec, "consumer_source_files", strings(0,1)));
    [ledgerCount, ledgerMatches] = localLedgerEvidence(ledgerT, functions);
    [profileCount, profileSeconds, profileMatches] = ...
        localProfilerEvidence(profileT, sourceFiles);
    row.ConsumerFunctions = strjoin(functions, "|");
    row.ConsumerSourceFiles = strjoin(sourceFiles, "|");
    row.LedgerCallCount = ledgerCount;
    row.ProfilerCallCount = profileCount;
    row.RuntimeCallCount = max(ledgerCount, profileCount);
    row.RuntimeSeconds = profileSeconds;
    row.ConsumerObserved = row.RuntimeCallCount > 0;
    row.RuntimeEvidenceSource = localRuntimeEvidenceSource(ledgerCount, profileCount);
    row.MatchedConsumers = strjoin(unique([ledgerMatches(:); ...
        profileMatches(:)], "stable"), "|");

    artifact = string(sixgr.util.structGet(spec, "measurement_artifact", ""));
    measuredFields = localStringList(sixgr.util.structGet( ...
        spec, "measured_fields", strings(0,1)));
    minimumRows = double(sixgr.util.structGet(spec, "measurement_min_rows", 1));
    [artifactExists, evidenceRows, finiteRows, measurementOk, ...
        successOk, truthOk, measurementDetails] = localMeasurementEvidence( ...
        runFolder, artifact, measuredFields, minimumRows, spec);
    row.MeasurementArtifact = artifact;
    row.ArtifactExists = artifactExists;
    row.EvidenceRows = evidenceRows;
    row.MeasuredFields = strjoin(measuredFields, "|");
    row.MeasuredFiniteRows = finiteRows;
    row.MeasurementEvidence = measurementOk;
    row.MeasurementSuccess = successOk;
    row.TruthEvidence = truthOk;
    row.MeasurementDetails = measurementDetails;

    dependencyFailed = localDependencyFailed(rows, stageIndex, dependencies);
    [row.StageOutcome, row.StrictPass, row.Bypassed, row.Skipped, ...
        row.FailureReason] = localStageOutcome(stageEnabled, mappingMatch, ...
        dependencyFailed, row.ConsumerObserved, measurementOk, successOk, truthOk);
    rows(stageIndex) = row;
end

detailT = struct2table(rows, "AsArray", true);
bindingT = localBuildParameterBindings(bindings, runId, configHash, ...
    scfg, cfg, ledgerT, profileT);
requiredStageFailures = sum(detailT.RequiredForScenario & ~detailT.StrictPass);
disabledExecutionFailures = sum(detailT.StageOutcome == "DISABLED_BUT_CALLED");
bindingFailures = sum(bindingT.RequiredForScenario & ~bindingT.StrictPass);
failureCount = requiredStageFailures + disabledExecutionFailures + bindingFailures;
allPassed = failureCount == 0;
failureReasons = unique([string(detailT.FailureReason(~detailT.StrictPass)); ...
    string(bindingT.FailureReason(~bindingT.StrictPass))], "stable");
failureReasons(failureReasons == "") = [];
status = "PASS";
if ~allPassed
    status = "FAILED";
end
gateT = localGateTable(runId, configHash, required, true, allPassed, ...
    height(detailT), requiredStageFailures, disabledExecutionFailures, ...
    bindingFailures, status, strjoin(failureReasons, ";"));
out = localOutput(detailT, bindingT, gateT, runFolder, true, allPassed);
out.Required = required;
out.FailOnEnabledBypass = failOnEnabledBypass;
out.FailureCount = failureCount;
out.RequiredStageFailureCount = requiredStageFailures;
out.DisabledExecutionFailureCount = disabledExecutionFailures;
out.ParameterBindingFailureCount = bindingFailures;
if options.WriteArtifacts
    localWriteArtifacts(layout, detailT, bindingT, gateT);
end
end

function T = localBuildParameterBindings(specs, runId, configHash, scfg, cfg, ledgerT, profileT)
if isempty(specs)
    T = localEmptyBindingTable();
    return;
end
rows = repmat(localEmptyBindingRow(), numel(specs), 1);
for index = 1:numel(specs)
    spec = specs(index);
    row = localEmptyBindingRow();
    row.RunID = runId;
    row.ConfigHash = configHash;
    row.ParameterID = string(sixgr.util.structGet(spec, "parameter_id", ""));
    row.Subsystem = string(sixgr.util.structGet(spec, "subsystem", ""));
    row.ScenarioPath = string(sixgr.util.structGet(spec, "scenario_path", ""));
    row.RuntimePath = string(sixgr.util.structGet(spec, "runtime_path", ""));
    featureName = string(sixgr.util.structGet(spec, "feature_authority", ""));
    [applicable, featureDetails] = localFeatureApplicable(cfg, featureName);
    row.FeatureAuthority = featureName;
    row.FeatureAuthorityDetails = featureDetails;
    row.Required = localBoolean(sixgr.util.structGet(spec, "required", true), true);
    row.RequiredForScenario = row.Required && applicable;

    [configured, configuredFound] = localTryScenarioValue(scfg, row.ScenarioPath);
    [resolved, resolvedFound] = localTryStructValue(cfg, row.RuntimePath);
    row.ConfiguredValue = localValueText(configured);
    row.ResolvedValue = localValueText(resolved);
    row.ConfiguredPresent = configuredFound;
    row.ResolvedPresent = resolvedFound;
    row.ValueMatch = configuredFound && resolvedFound && localValuesEqual(configured, resolved);

    functions = localStringList(sixgr.util.structGet( ...
        spec, "consumer_functions", strings(0,1)));
    files = localStringList(sixgr.util.structGet( ...
        spec, "consumer_source_files", strings(0,1)));
    [ledgerCount, ledgerMatches] = localLedgerEvidence(ledgerT, functions);
    [profileCount, ~, profileMatches] = localProfilerEvidence(profileT, files);
    row.ConsumerFunctions = strjoin(functions, "|");
    row.ConsumerSourceFiles = strjoin(files, "|");
    row.ConsumerObserved = max(ledgerCount, profileCount) > 0;
    row.MatchedConsumers = strjoin(unique([ledgerMatches(:); ...
        profileMatches(:)], "stable"), "|");

    if ~applicable
        row.Status = "DISABLED_BY_YAML";
        row.StrictPass = true;
    elseif ~configuredFound
        row.Status = "CONFIG_VALUE_MISSING";
        row.FailureReason = "configured_parameter_missing:" + row.ScenarioPath;
    elseif ~resolvedFound
        row.Status = "RUNTIME_VALUE_MISSING";
        row.FailureReason = "resolved_runtime_parameter_missing:" + row.RuntimePath;
    elseif ~row.ValueMatch
        row.Status = "VALUE_MISMATCH";
        row.FailureReason = "configured_resolved_value_mismatch:" + row.ParameterID;
    elseif ~row.ConsumerObserved
        row.Status = "CONSUMER_NOT_CALLED";
        row.FailureReason = "parameter_consumer_not_called:" + row.ParameterID;
    else
        row.Status = "PASS";
        row.StrictPass = true;
    end
    rows(index) = row;
end
T = struct2table(rows, "AsArray", true);
end

function [enabled, sourcePath, configuredText, runtimePaths, resolvedText, match, details] = localStageAuthority(spec, scfg, cfg)
featureName = string(sixgr.util.structGet(spec, "feature_authority", ""));
alwaysRequired = localBoolean(sixgr.util.structGet(spec, "always_required", false), false);
if strlength(featureName) > 0
    feature = sixgr.util.structGet(cfg, "runtime.features." + featureName, struct());
    enabledRaw = sixgr.util.structGet(feature, "Enabled", []);
    sourcePath = string(sixgr.util.structGet(feature, "SourceYAMLPath", ""));
    runtimePaths = localStringList(sixgr.util.structGet(feature, ...
        "RuntimeConsumerPaths", strings(0,1)));
    [configured, configuredFound] = localTryScenarioValue(scfg, sourcePath);
    enabled = localBoolean(enabledRaw, false);
    configuredText = localValueText(configured);
    resolvedValues = strings(0,1);
    featureStatus = lower(string(sixgr.util.structGet(feature, "Status", "")));
    if featureStatus == "yaml_target_case_derived_runtime_consumer_exact"
        declaredSourceValue = string(sixgr.util.structGet( ...
            feature, "SourceYAMLValue", ""));
        match = configuredFound && ~isempty(configured) && ...
            localIsBooleanScalar(enabledRaw) && ...
            declaredSourceValue == localValueText(configured) && ...
            ~isempty(runtimePaths);
    else
        match = configuredFound && localIsBooleanScalar(configured) && ...
            localIsBooleanScalar(enabledRaw) && ...
            logical(configured) == logical(enabledRaw) && ...
            ~isempty(runtimePaths);
    end
    for runtimePath = runtimePaths(:).'
        [runtimeValue, found] = localTryStructValue(cfg, runtimePath);
        resolvedValues(end+1,1) = runtimePath + "=" + localValueText(runtimeValue); %#ok<AGROW>
        match = match && found && localIsBooleanScalar(runtimeValue) && ...
            logical(runtimeValue) == enabled;
    end
    resolvedText = strjoin(resolvedValues, ";");
    details = "feature_authority=" + featureName;
    return;
end

sourcePath = string(sixgr.util.structGet(spec, "scenario_enable_path", ""));
runtimePaths = localStringList(sixgr.util.structGet(spec, ...
    "internal_enable_paths", strings(0,1)));
if alwaysRequired
    enabled = true;
    configuredText = "true(always_required)";
    resolvedText = "true(always_required)";
    match = true;
    details = "always_required_stage";
    return;
end
[configured, configuredFound] = localTryScenarioValue(scfg, sourcePath);
enabled = localBoolean(configured, false);
configuredText = localValueText(configured);
match = configuredFound && localIsBooleanScalar(configured) && ~isempty(runtimePaths);
resolvedValues = strings(0,1);
for runtimePath = runtimePaths(:).'
    [runtimeValue, found] = localTryStructValue(cfg, runtimePath);
    resolvedValues(end+1,1) = runtimePath + "=" + localValueText(runtimeValue); %#ok<AGROW>
    match = match && found && localIsBooleanScalar(runtimeValue) && ...
        logical(runtimeValue) == enabled;
end
resolvedText = strjoin(resolvedValues, ";");
details = "explicit_stage_enable_mapping";
end

function dependencyFailed = localDependencyFailed(rows, currentIndex, dependencyIds)
dependencyFailed = false;
for dependencyId = dependencyIds(:).'
    if strlength(dependencyId) == 0
        continue;
    end
    if currentIndex <= 1
        dependencyFailed = true;
        return;
    end
    priorIds = string({rows(1:currentIndex-1).StageID});
    prior = find(priorIds == dependencyId, 1, "last");
    if isempty(prior) || ~logical(rows(prior).StrictPass)
        dependencyFailed = true;
        return;
    end
end
end

function [outcome, pass, bypassed, skipped, reason] = localStageOutcome(enabled, mappingMatch, dependencyFailed, called, measured, success, truthOk)
pass = false;
bypassed = false;
skipped = false;
reason = "";
if ~mappingMatch
    outcome = "CONFIG_MAPPING_MISMATCH";
    bypassed = true;
    reason = "configured_and_internal_enable_authority_mismatch";
elseif ~enabled && called
    outcome = "DISABLED_BUT_CALLED";
    bypassed = true;
    reason = "yaml_disabled_stage_executed";
elseif ~enabled
    outcome = "DISABLED_BY_YAML";
    pass = true;
    skipped = true;
elseif dependencyFailed
    outcome = "BLOCKED_BY_DEPENDENCY";
    skipped = true;
    reason = "upstream_causal_stage_failed_or_missing";
elseif ~called
    outcome = "ENABLED_NOT_CALLED";
    bypassed = true;
    reason = "enabled_stage_has_no_exact_runtime_entry";
elseif ~measured
    outcome = "CALLED_NO_MEASUREMENT";
    reason = "runtime_consumer_called_without_required_measurement_rows";
elseif ~truthOk
    outcome = "NON_TRUTH_MEASUREMENT_EVIDENCE";
    reason = "measurement_rows_contain_proxy_fallback_or_placeholder_evidence";
elseif ~success
    outcome = "FAILED_MEASUREMENT";
    reason = "measurement_success_rule_failed";
else
    outcome = "PASS";
    pass = true;
end
end

function [existsFlag, rowCount, finiteRows, measurementOk, successOk, truthOk, details] = localMeasurementEvidence(runFolder, relativePath, fields, minimumRows, spec)
existsFlag = false;
rowCount = 0;
finiteRows = 0;
measurementOk = false;
successOk = true;
truthOk = true;
details = "";
if strlength(relativePath) == 0
    details = "measurement_artifact_not_declared";
    return;
end
path = fullfile(runFolder, char(relativePath));
existsFlag = isfile(path);
if ~existsFlag
    details = "measurement_artifact_missing";
    return;
end
T = localReadTable(path);
rowCount = height(T);
minimumRows = max(1, round(minimumRows));
if rowCount < minimumRows
    details = "measurement_row_count_below_required:" + rowCount + "<" + minimumRows;
    return;
end
valid = true(rowCount,1);
for field = fields(:).'
    if ~ismember(field, string(T.Properties.VariableNames))
        details = "measured_field_missing:" + field;
        return;
    end
    valid = valid & localValidValueMask(T.(char(field)));
end
finiteRows = sum(valid);
measurementOk = finiteRows >= minimumRows;
if ~measurementOk
    details = "measured_finite_row_count_below_required:" + finiteRows + "<" + minimumRows;
    return;
end
for flagName = ["ProxyUsed","ProxyFlag","FallbackFlag","PlaceholderFlag"]
    if ismember(flagName, string(T.Properties.VariableNames)) && ...
            any(localTruthFlag(T.(char(flagName))))
        truthOk = false;
    end
end
successField = string(sixgr.util.structGet(spec, "success_field", ""));
successMode = lower(string(sixgr.util.structGet(spec, "success_mode", "")));
successValue = sixgr.util.structGet(spec, "success_value", []);
if strlength(successField) > 0
    if ~ismember(successField, string(T.Properties.VariableNames))
        successOk = false;
        details = "success_field_missing:" + successField;
        return;
    end
    values = T.(char(successField));
    switch successMode
        case "any_true"
            successOk = any(localTruthFlag(values));
        case "all_true"
            successOk = all(localTruthFlag(values));
        case "any_equals"
            successOk = any(localEqualsMask(values, successValue));
        case "all_equals"
            successOk = all(localEqualsMask(values, successValue));
        otherwise
            error("sixgr:truth:CausalPHYChainAuditInvalidSuccessMode", ...
                "Stage success_mode '%s' is unsupported.", successMode);
    end
end
if truthOk && successOk
    details = "runtime_measurement_rows_valid";
elseif ~truthOk
    details = "non_truth_measurement_markers_detected";
else
    details = "success_rule_failed";
end
end

function mask = localValidValueMask(values)
if isnumeric(values) || islogical(values)
    mask = isfinite(double(values));
else
    text = lower(strtrim(string(values)));
    mask = strlength(text) > 0 & ~ismember(text, ...
        ["nan","na","n/a","unavailable","not_available","missing"]);
end
mask = mask(:);
end

function mask = localTruthFlag(values)
if islogical(values) || isnumeric(values)
    mask = isfinite(double(values)) & double(values) ~= 0;
else
    text = lower(strtrim(string(values)));
    mask = ismember(text, ["1","true","yes","y"]);
end
mask = mask(:);
end

function mask = localEqualsMask(values, expected)
if (isnumeric(values) || islogical(values)) && ...
        (isnumeric(expected) || islogical(expected))
    mask = double(values) == double(expected);
else
    mask = strcmpi(strtrim(string(values)), strtrim(string(expected)));
end
mask = mask(:);
end

function [count, matches] = localLedgerEvidence(T, functions)
count = 0;
matches = strings(0,1);
if isempty(T) || ~ismember("FunctionName", string(T.Properties.VariableNames))
    return;
end
names = strtrim(string(T.FunctionName));
for functionName = functions(:).'
    mask = strcmpi(names, strtrim(functionName));
    count = count + sum(mask);
    if any(mask)
        matches(end+1,1) = "ledger:" + functionName; %#ok<AGROW>
    end
end
end

function [count, seconds, matches] = localProfilerEvidence(T, sourceFiles)
count = 0;
seconds = 0;
matches = strings(0,1);
if isempty(T) || ~ismember("FileName", string(T.Properties.VariableNames))
    return;
end
profilePaths = localNormalizePaths(string(T.FileName));
repoRoot = localNormalizePaths(string(fileparts(fileparts(fileparts( ...
    mfilename("fullpath"))))));
for sourceFile = sourceFiles(:).'
    expected = localNormalizePaths(repoRoot + "/" + sourceFile);
    mask = strcmpi(profilePaths, expected);
    if any(mask)
        if ismember("NumCalls", string(T.Properties.VariableNames))
            count = count + sum(localNumeric(T.NumCalls(mask)), "omitnan");
        else
            count = count + sum(mask);
        end
        if ismember("TotalTime_s", string(T.Properties.VariableNames))
            seconds = seconds + sum(localNumeric(T.TotalTime_s(mask)), "omitnan");
        end
        matches(end+1,1) = "profiler:" + sourceFile; %#ok<AGROW>
    end
end
end

function out = localNormalizePaths(in)
out = lower(replace(string(in), "\", "/"));
while any(contains(out, "//"))
    out = replace(out, "//", "/");
end
end

function values = localNumeric(values)
if isnumeric(values) || islogical(values)
    values = double(values);
else
    values = str2double(string(values));
end
end

function source = localRuntimeEvidenceSource(ledgerCount, profileCount)
if ledgerCount > 0 && profileCount > 0
    source = "runtime_call_ledger+exact_profiler_file_match";
elseif ledgerCount > 0
    source = "runtime_call_ledger_exact_function_match";
elseif profileCount > 0
    source = "runtime_profiler_exact_source_file_match";
else
    source = "no_exact_runtime_entry_evidence";
end
end

function [applicable, details] = localFeatureApplicable(cfg, featureName)
if strlength(featureName) == 0
    applicable = true;
    details = "always_applicable";
    return;
end
feature = sixgr.util.structGet(cfg, "runtime.features." + featureName, struct());
enabled = sixgr.util.structGet(feature, "Enabled", []);
applicable = localBoolean(enabled, false);
details = "runtime.features." + featureName + ".Enabled=" + localValueText(enabled);
end

function [value, found] = localTryScenarioValue(scfg, path)
found = strlength(path) > 0;
if ~found
    value = [];
    return;
end
if isa(scfg, "sixgr.lls6g.config.ScenarioConfig")
    found = scfg.has(path);
    value = scfg.get(path, []);
else
    [value, found] = localTryStructValue(scfg, path);
end
end

function [value, found] = localTryStructValue(s, path)
found = false;
value = [];
if ~(isstruct(s) && isscalar(s)) || strlength(path) == 0
    return;
end
parts = split(string(path), ".");
current = s;
for part = parts(:).'
    if ~(isstruct(current) && isscalar(current) && isfield(current, char(part)))
        return;
    end
    current = current.(char(part));
end
value = current;
found = true;
end

function value = localGetScenarioValue(scfg, path, defaultValue)
[value, found] = localTryScenarioValue(scfg, path);
if ~found
    value = defaultValue;
end
end

function value = localGetScenarioProperty(scfg, propertyName, defaultValue)
value = defaultValue;
if isobject(scfg) && isprop(scfg, propertyName)
    value = scfg.(propertyName);
elseif isstruct(scfg) && isfield(scfg, propertyName)
    value = scfg.(propertyName);
end
end

function text = localValueText(value)
if isempty(value)
    text = "<missing>";
    return;
end
try
    text = string(jsonencode(value));
catch
    text = string(value);
    text = strjoin(text(:), "|");
end
end

function tf = localValuesEqual(left, right)
if (isnumeric(left) || islogical(left)) && ...
        (isnumeric(right) || islogical(right))
    scale = max(1, max(abs([double(left(:)); double(right(:))])));
    % YAML sequences commonly deserialize as column vectors while MATLAB
    % PHY APIs conventionally expose ordered port/index sets as row vectors.
    % Their orientation is not semantic.  Preserve strict dimensional
    % equality for genuine matrices (for example, precoders/beam weights),
    % but compare one-dimensional ordered lists by value and order.
    sameShape = isequal(size(left), size(right)) || ...
        (isvector(left) && isvector(right) && numel(left) == numel(right));
    tf = sameShape && numel(left) == numel(right) && ...
        all(abs(double(left(:)) - double(right(:))) <= 1e-12 * scale);
else
    tf = strcmp(localValueText(left), localValueText(right));
end
end

function value = localBoolean(raw, defaultValue)
if localIsBooleanScalar(raw)
    value = logical(raw);
else
    value = logical(defaultValue);
end
end

function tf = localIsBooleanScalar(value)
tf = (islogical(value) || isnumeric(value)) && isscalar(value) && ...
    isfinite(double(value)) && any(double(value) == [0 1]);
end

function values = localStringList(raw)
if isempty(raw)
    values = strings(0,1);
elseif iscell(raw)
    values = string(raw(:));
else
    values = string(raw(:));
end
values = strtrim(values);
values(values == "") = [];
end

function values = localStructArray(raw)
if isempty(raw)
    values = struct([]);
elseif iscell(raw)
    % Heterogeneous optional YAML mapping fields are represented as a cell
    % array of scalar structs. Normalize the union of fields before
    % concatenation so the registry remains data-driven rather than forcing
    % every stage to carry irrelevant empty keys.
    if ~all(cellfun(@(x) builtin("isstruct", x) && isscalar(x), raw(:)))
        error("sixgr:truth:CausalPHYChainAuditInvalidRegistry", ...
            "Every causal audit registry item must be a scalar struct.");
    end
    fieldUnion = strings(0,1);
    for itemIndex = 1:numel(raw)
        fieldUnion = union(fieldUnion, string(fieldnames(raw{itemIndex})), "stable");
    end
    normalized = raw(:);
    for itemIndex = 1:numel(normalized)
        for fieldName = fieldUnion(:).'
            if ~isfield(normalized{itemIndex}, char(fieldName))
                normalized{itemIndex}.(char(fieldName)) = [];
            end
        end
        normalized{itemIndex} = orderfields(normalized{itemIndex}, cellstr(fieldUnion));
    end
    values = vertcat(normalized{:});
elseif isstruct(raw)
    values = raw(:);
else
    error("sixgr:truth:CausalPHYChainAuditInvalidRegistry", ...
        "Causal audit stage and parameter registries must be struct arrays.");
end
end

function T = localReadTable(path)
if ~isfile(path)
    T = table();
    return;
end
try
    T = readtable(path, "TextType", "string", ...
        "VariableNamingRule", "preserve");
catch
    T = table();
end
end

function row = localEmptyStageRow()
row = struct( ...
    "RunID", "", "ConfigHash", "", "StageOrder", NaN, ...
    "StageID", "", "Subsystem", "", "DependencyStage", "", ...
    "ScenarioEnablePath", "", "ConfiguredValue", "", ...
    "InternalEnablePaths", "", "ResolvedValue", "", ...
    "ConfigMappingMatch", false, "ConfigMappingDetails", "", ...
    "Required", true, "RequiredForScenario", false, ...
    "ConsumerFunctions", "", "ConsumerSourceFiles", "", ...
    "ConsumerObserved", false, "LedgerCallCount", 0, ...
    "ProfilerCallCount", 0, "RuntimeCallCount", 0, ...
    "RuntimeSeconds", 0, "RuntimeEvidenceSource", "", ...
    "MatchedConsumers", "", "MeasurementArtifact", "", ...
    "ArtifactExists", false, "EvidenceRows", 0, ...
    "MeasuredFields", "", "MeasuredFiniteRows", 0, ...
    "MeasurementEvidence", false, "MeasurementSuccess", false, ...
    "TruthEvidence", false, "MeasurementDetails", "", ...
    "StageOutcome", "", "Bypassed", false, "Skipped", false, ...
    "StrictPass", false, "FailureReason", "");
end

function row = localEmptyBindingRow()
row = struct( ...
    "RunID", "", "ConfigHash", "", "ParameterID", "", ...
    "Subsystem", "", "ScenarioPath", "", "ConfiguredValue", "", ...
    "RuntimePath", "", "ResolvedValue", "", ...
    "FeatureAuthority", "", "FeatureAuthorityDetails", "", ...
    "Required", true, "RequiredForScenario", false, ...
    "ConfiguredPresent", false, "ResolvedPresent", false, ...
    "ValueMatch", false, "ConsumerFunctions", "", ...
    "ConsumerSourceFiles", "", "ConsumerObserved", false, ...
    "MatchedConsumers", "", "Status", "", "StrictPass", false, ...
    "FailureReason", "");
end

function T = localEmptyStageTable()
T = struct2table(repmat(localEmptyStageRow(), 0, 1), "AsArray", true);
end

function T = localEmptyBindingTable()
T = struct2table(repmat(localEmptyBindingRow(), 0, 1), "AsArray", true);
end

function T = localGateTable(runId, configHash, required, enabled, passed, ...
        stageCount, stageFailures, disabledExecutionFailures, bindingFailures, ...
        status, failureReason)
T = table(runId, configHash, logical(required), logical(enabled), ...
    logical(passed), double(stageCount), double(stageFailures), ...
    double(disabledExecutionFailures), double(bindingFailures), ...
    string(status), string(failureReason), ...
    'VariableNames', {'RunID','ConfigHash','Required','Enabled','Pass', ...
    'StageCount','RequiredStageFailureCount','DisabledExecutionFailureCount', ...
    'ParameterBindingFailureCount','Status','FailureReason'});
end

function out = localOutput(detailT, bindingT, gateT, runFolder, executed, passed)
out = struct( ...
    "Executed", logical(executed), "Ok", logical(passed), ...
    "DetailTable", detailT, "ParameterBindingTable", bindingT, ...
    "GateTable", gateT, ...
    "DetailPath", string(fullfile(runFolder, "reports", "csv", ...
        "causal_phy_chain_audit.csv")), ...
    "ParameterBindingPath", string(fullfile(runFolder, "reports", "csv", ...
        "causal_phy_parameter_authority.csv")), ...
    "GatePath", string(fullfile(runFolder, "reports", "csv", ...
        "causal_phy_chain_gate.csv")));
end

function localWriteArtifacts(layout, detailT, bindingT, gateT)
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, ...
    "causal_phy_chain_audit.csv"), detailT, "PreserveSchema", true);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, ...
    "causal_phy_parameter_authority.csv"), bindingT, "PreserveSchema", true);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, ...
    "causal_phy_chain_gate.csv"), gateT, "PreserveSchema", true);
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:truth:CausalPHYChainAuditInvalidPath", ...
        "runFolder must be a character vector or string scalar.");
end
end
