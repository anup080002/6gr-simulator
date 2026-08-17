function stats = classifySupplementalEvidenceScope(stats, result, componentName, statusField)
%CLASSIFYSUPPLEMENTALEVIDENCESCOPE Report component evidence without scope promotion.
%   A passing component anchor is useful qualification evidence, but it is
%   not evidence that the same scenario exercised the component in-path.
%   This adapter deliberately leaves the caller's in-path StrictOk field
%   unchanged and only adds an explicit parallel classification.

arguments
    stats (1,1) struct
    result
    componentName (1,1) string
    statusField (1,1) string
end

stats.InPathEvidenceScope = "in_path";
stats.ComponentAnchorEvaluated = false;
stats.ComponentAnchorStrictOk = false;
stats.ComponentAnchorStatisticallyQualified = false;
stats.ComponentAnchorStatisticalQualification = "NOT_EVALUATED";
stats.ComponentAnchorEvidenceScope = "not_evaluated";
stats.ComponentAnchorSameScenarioInPathEligible = false;
stats.ComponentAnchorArtifactRoot = "";
stats.ComponentAnchorFailureReason = "";
stats.ComponentAnchorStatus = "NOT_EVALUATED";

if ~(isstruct(result) && isscalar(result))
    return;
end
supplemental = sixgr.util.structGet(result, ...
    "StrictSupplemental." + componentName, struct());
if ~(isstruct(supplemental) && isscalar(supplemental) && ...
        ~isempty(fieldnames(supplemental)))
    return;
end

stats.ComponentAnchorEvaluated = true;
stats.ComponentAnchorStrictOk = logical(sixgr.util.structGet( ...
    supplemental, "StrictOk", sixgr.util.structGet(supplemental, "Ok", false)));
stats.ComponentAnchorStatisticallyQualified = logical(sixgr.util.structGet( ...
    supplemental, "StatisticallyQualified", false));
stats.ComponentAnchorStatisticalQualification = upper(strtrim(string( ...
    sixgr.util.structGet(supplemental, "StatisticalQualification", "NOT_EVALUATED"))));
stats.ComponentAnchorEvidenceScope = lower(strtrim(string( ...
    sixgr.util.structGet(supplemental, "EvidenceScope", "untyped"))));
stats.ComponentAnchorSameScenarioInPathEligible = logical(sixgr.util.structGet( ...
    supplemental, "SameScenarioInPathEligible", false));
stats.ComponentAnchorArtifactRoot = string(sixgr.util.structGet( ...
    supplemental, "ArtifactRoot", ""));
stats.ComponentAnchorFailureReason = string(sixgr.util.structGet( ...
    supplemental, "FailureReason", ""));

if stats.ComponentAnchorEvidenceScope == "component_anchor" && ...
        ~stats.ComponentAnchorSameScenarioInPathEligible
    if stats.ComponentAnchorStrictOk
        stats.ComponentAnchorStatus = "PASS_NOT_SAME_SCENARIO_IN_PATH";
        stats = localAppendStatus(stats, statusField, ...
            "component_anchor_pass_not_same_scenario_in_path");
    else
        stats.ComponentAnchorStatus = "FAIL";
        stats = localAppendStatus(stats, statusField, "component_anchor_fail");
    end
elseif stats.ComponentAnchorEvidenceScope == "in_path" && ...
        stats.ComponentAnchorSameScenarioInPathEligible
    % Promotion is permitted only for the sealed result of the dedicated
    % in-path evaluator.  A caller-created struct or a passing component
    % anchor cannot satisfy these markers.  The evaluator has already
    % checked every active raw row for truth/proxy separation, component
    % receiver success, entity coverage and scenario/config identity.
    validationComplete = logical(sixgr.util.structGet(supplemental, ...
        "InPathRuntimeValidationComplete", false));
    validationAuthority = string(sixgr.util.structGet(supplemental, ...
        "ValidationAuthority", ""));
    runtimeSource = string(sixgr.util.structGet(supplemental, ...
        "RuntimeEvidenceSource", ""));
    launchedSupplemental = logical(sixgr.util.structGet(supplemental, ...
        "LaunchedSupplementalWaveform", true));
    sourceHash = string(sixgr.util.structGet(supplemental, ...
        "SourceTableSHA256", ""));
    expectedAuthority = "sixgr.truth.evaluateInPathComponentEvidence/v1";
    expectedComponent = lower(strtrim(componentName));
    validationComponent = lower(strtrim(string(sixgr.util.structGet( ...
        supplemental, "ValidationComponent", expectedComponent))));
    if expectedComponent == "channelrf"
        expectedAuthority = "sixgr.channel.buildInPathChannelRFResult/v1";
        expectedComponent = "channel_rf";
    end
    locallyValidated = validationComplete && ...
        validationAuthority == expectedAuthority && ...
        validationComponent == expectedComponent && ...
        runtimeSource == "CoupledTruthRuntime.RawTrials" && ...
        ~launchedSupplemental && strlength(sourceHash) == 64;
    stats.InPathRuntimeEvidenceValidated = locallyValidated;
    stats.InPathRuntimeSourceSHA256 = sourceHash;
    stats.InPathRuntimeValidationAuthority = validationAuthority;
    stats.InPathRuntimeExpectedValidationAuthority = expectedAuthority;
    stats.InPathRuntimeValidationComponent = validationComponent;
    stats.InPathRuntimeExpectedValidationComponent = expectedComponent;
    strictField = replace(statusField, "Status", "StrictOk");
    if locallyValidated && isfield(stats, char(strictField))
        stats.(char(strictField)) = stats.ComponentAnchorStrictOk;
        stats.(char(statusField)) = string(localTernary( ...
            stats.ComponentAnchorStrictOk, ...
            "strict_in_path_runtime_evidence_present", ...
            "strict_in_path_runtime_evidence_failed"));
        stats.ComponentAnchorStatus = string(localTernary( ...
            stats.ComponentAnchorStrictOk, "PASS_IN_PATH_RUNTIME_VALIDATED", "FAIL"));
    else
        stats.ComponentAnchorStatus = "INVALID_IN_PATH_VALIDATION_AUTHORITY";
        stats = localAppendStatus(stats, statusField, ...
            "in_path_evidence_not_validated_by_runtime_evaluator");
    end
else
    stats.ComponentAnchorStatus = "INVALID_OR_UNTYPED_SCOPE";
    stats = localAppendStatus(stats, statusField, ...
        "supplemental_evidence_scope_invalid_or_untyped");
end
end

function stats = localAppendStatus(stats, statusField, suffix)
fieldName = char(statusField);
if isfield(stats, fieldName)
    current = strtrim(string(stats.(fieldName)));
else
    current = "";
end
if strlength(current) == 0
    stats.(fieldName) = string(suffix);
elseif ~contains(current, string(suffix))
    stats.(fieldName) = current + ";" + string(suffix);
end
end

function value = localTernary(condition, trueValue, falseValue)
if condition
    value = trueValue;
else
    value = falseValue;
end
end
