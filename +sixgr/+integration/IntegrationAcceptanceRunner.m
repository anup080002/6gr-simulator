classdef IntegrationAcceptanceRunner
    %INTEGRATIONACCEPTANCERUNNER Evaluate Phase-16 rules from observations.
    %
    % Observations are deliberately separate from the rule catalog.  A
    % caller must supply one runtime-derived value per metric; missing,
    % duplicate, nonfinite, or unsupported observations fail closed.

    methods (Static)
        function results = evaluate(rulePath, observations, runID)
            rules = localReadRules(rulePath);
            localValidateObservations(observations);
            if nargin < 3 || strlength(strtrim(string(runID))) == 0
                error("sixgr:integration:MissingActualRunEvidence", ...
                    "Acceptance evaluation requires an exact RunID.");
            end
            runID = string(runID);
            rows = repmat(struct( ...
                "RunID", "", "RuleID", "", "Category", "", ...
                "RuleType", "", "Metric", "", "Observed", "", ...
                "Operator", "", "Threshold", "", "Scope", "", ...
                "Status", "", "FailureReason", ""), height(rules), 1);
            for index = 1:height(rules)
                metric = string(rules.Metric(index));
                match = find(observations.Metric == metric);
                if numel(match) ~= 1
                    error("sixgr:integration:MissingActualRunEvidence", ...
                        "Metric %s has %d runtime observations; exactly one is required.", ...
                        metric, numel(match));
                end
                observed = observations.Observed(match);
                [passed, observedText, failure] = localCompare( ...
                    observed, rules.Operator(index), rules.Threshold(index));
                rows(index) = struct( ...
                    "RunID", runID, ...
                    "RuleID", string(rules.RuleID(index)), ...
                    "Category", string(rules.Category(index)), ...
                    "RuleType", string(rules.RuleType(index)), ...
                    "Metric", metric, ...
                    "Observed", observedText, ...
                    "Operator", string(rules.Operator(index)), ...
                    "Threshold", string(rules.Threshold(index)), ...
                    "Scope", string(rules.Scope(index)), ...
                    "Status", localStatus(passed), ...
                    "FailureReason", failure);
            end
            results = struct2table(rows, "AsArray", true);
            if height(results) ~= 120 || ...
                    numel(unique(results.RuleID)) ~= 120
                error("sixgr:integration:IncompleteAcceptanceRules", ...
                    "Expected exactly 120 unique Phase-16 rule evaluations.");
            end
        end
    end
end

function rules = localReadRules(path)
path = string(path);
if ~isfile(path)
    error("sixgr:integration:IncompleteConfiguration", ...
        "Acceptance-rule catalog does not exist: %s.", path);
end
options = detectImportOptions(path, ...
    "Delimiter", ",", "VariableNamingRule", "preserve");
options = setvartype(options, options.VariableNames, "string");
rules = readtable(path, options);
required = ["RuleID","Category","RuleType","Metric", ...
    "Operator","Threshold","Scope","Mandatory"];
if ~all(ismember(required, string(rules.Properties.VariableNames))) || ...
        height(rules) ~= 120 || numel(unique(rules.RuleID)) ~= 120
    error("sixgr:integration:IncompleteAcceptanceRules", ...
        "Acceptance catalog must contain 120 unique, schema-valid rows.");
end
mandatory = lower(strtrim(string(rules.Mandatory)));
if any(~ismember(mandatory, ["true","1","yes"]))
    error("sixgr:integration:IncompleteAcceptanceRules", ...
        "Every Phase-16 acceptance rule must be mandatory.");
end
end

function localValidateObservations(input)
if ~istable(input) || ~all(ismember(["Metric","Observed"], ...
        string(input.Properties.VariableNames)))
    error("sixgr:integration:MissingActualRunEvidence", ...
        "Runtime observations require Metric and Observed columns.");
end
metrics = string(input.Metric);
if any(strlength(strtrim(metrics)) == 0) || ...
        numel(unique(metrics)) ~= numel(metrics)
    error("sixgr:integration:MissingActualRunEvidence", ...
        "Runtime observation metrics must be nonempty and unique.");
end
end

function [passed, observedText, failure] = ...
        localCompare(observed, operator, threshold)
operator = strtrim(string(operator));
threshold = strtrim(string(threshold));
observedText = localScalarText(observed);
failure = "";
if operator == "=="
    [observedLogical, observedIsLogical] = localLogical(observedText);
    [thresholdLogical, thresholdIsLogical] = localLogical(threshold);
    if observedIsLogical || thresholdIsLogical
        if ~(observedIsLogical && thresholdIsLogical)
            error("sixgr:integration:AcceptanceMetricTypeMismatch", ...
                "Cannot compare logical and non-logical values '%s' and '%s'.", ...
                observedText, threshold);
        end
        passed = observedLogical == thresholdLogical;
    else
        [observedNumeric, observedIsNumeric] = localNumeric(observedText);
        [thresholdNumeric, thresholdIsNumeric] = localNumeric(threshold);
        if observedIsNumeric || thresholdIsNumeric
            if ~(observedIsNumeric && thresholdIsNumeric)
                error("sixgr:integration:AcceptanceMetricTypeMismatch", ...
                    "Cannot compare numeric and text values '%s' and '%s'.", ...
                    observedText, threshold);
            end
            passed = observedNumeric == thresholdNumeric;
        else
            passed = observedText == threshold;
        end
    end
elseif any(operator == ["<=",">=","<",">"])
    [observedNumeric, observedIsNumeric] = localNumeric(observedText);
    [thresholdNumeric, thresholdIsNumeric] = localNumeric(threshold);
    if ~(observedIsNumeric && thresholdIsNumeric)
        error("sixgr:integration:AcceptanceMetricTypeMismatch", ...
            "Operator %s requires finite numeric values, got '%s' and '%s'.", ...
            operator, observedText, threshold);
    end
    switch operator
        case "<="
            passed = observedNumeric <= thresholdNumeric;
        case ">="
            passed = observedNumeric >= thresholdNumeric;
        case "<"
            passed = observedNumeric < thresholdNumeric;
        otherwise
            passed = observedNumeric > thresholdNumeric;
    end
else
    error("sixgr:integration:AcceptanceOperatorUnsupported", ...
        "Unsupported acceptance operator '%s'.", operator);
end
if ~passed
    failure = "observed=" + observedText + " " + operator + ...
        " threshold=" + threshold;
end
end

function output = localScalarText(value)
if iscell(value) && isscalar(value)
    value = value{1};
end
if islogical(value) && isscalar(value)
    output = string(lower(mat2str(value)));
elseif isnumeric(value) && isscalar(value)
    if ~isfinite(value)
        error("sixgr:integration:AcceptanceMetricNonFinite", ...
            "Acceptance observations must be finite.");
    end
    output = string(sprintf("%.17g", double(value)));
else
    output = strtrim(string(value));
    if ~isscalar(output) || strlength(output) == 0
        error("sixgr:integration:AcceptanceMetricTypeMismatch", ...
            "Acceptance observations must be nonempty scalars.");
    end
end
end

function [value, valid] = localLogical(text)
text = lower(strtrim(string(text)));
valid = ismember(text, ["true","false"]);
value = text == "true";
end

function [value, valid] = localNumeric(text)
value = str2double(string(text));
valid = isscalar(value) && isfinite(value);
end

function output = localStatus(passed)
if passed
    output = "PASS";
else
    output = "FAIL";
end
end
