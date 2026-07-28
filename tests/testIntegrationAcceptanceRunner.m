function tests = testIntegrationAcceptanceRunner
%TESTINTEGRATIONACCEPTANCERUNNER Phase-16 rule binding and fail-closed tests.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename("fullpath")));
testCase.TestData.RulePath = fullfile(root, "tests", "vectors", ...
    "integration", "integration_acceptance_rules.csv");
options = detectImportOptions(testCase.TestData.RulePath, ...
    "Delimiter", ",", "VariableNamingRule", "preserve");
options = setvartype(options, options.VariableNames, "string");
testCase.TestData.Rules = readtable(testCase.TestData.RulePath, options);
end

function testEvaluatesAll120RulesFromSeparateObservations(testCase)
rules = testCase.TestData.Rules;
observations = localPassingObservations(rules);
results = sixgr.integration.IntegrationAcceptanceRunner.evaluate( ...
    testCase.TestData.RulePath, observations, "ACTUAL-RUN-BUNDLE-001");
verifyEqual(testCase, height(results), 120);
verifyEqual(testCase, numel(unique(results.RuleID)), 120);
verifyTrue(testCase, all(results.Status == "PASS"));
verifyTrue(testCase, all(results.RunID == "ACTUAL-RUN-BUNDLE-001"));
end

function testMissingRuntimeMetricFailsClosed(testCase)
rules = testCase.TestData.Rules;
observations = localPassingObservations(rules);
observations(1,:) = [];
verifyError(testCase, @() ...
    sixgr.integration.IntegrationAcceptanceRunner.evaluate( ...
    testCase.TestData.RulePath, observations, "ACTUAL-RUN-BUNDLE-002"), ...
    "sixgr:integration:MissingActualRunEvidence");
end

function testDuplicateRuntimeMetricFailsClosed(testCase)
rules = testCase.TestData.Rules;
observations = localPassingObservations(rules);
metrics = [string(observations.Metric); string(observations.Metric(1))];
values = [string(observations.Observed); string(observations.Observed(1))];
observations = table(metrics, values, ...
    'VariableNames', {'Metric','Observed'});
verifyError(testCase, @() ...
    sixgr.integration.IntegrationAcceptanceRunner.evaluate( ...
    testCase.TestData.RulePath, observations, "ACTUAL-RUN-BUNDLE-003"), ...
    "sixgr:integration:MissingActualRunEvidence");
end

function testNonfiniteObservationCannotPass(testCase)
rules = testCase.TestData.Rules;
observations = localPassingObservations(rules);
values = string(observations.Observed);
values(1) = "NaN";
observations = table(string(observations.Metric), values, ...
    'VariableNames', {'Metric','Observed'});
verifyError(testCase, @() ...
    sixgr.integration.IntegrationAcceptanceRunner.evaluate( ...
    testCase.TestData.RulePath, observations, "ACTUAL-RUN-BUNDLE-004"), ...
    "sixgr:integration:AcceptanceMetricTypeMismatch");
end

function observations = localPassingObservations(rules)
[metrics, first] = unique(string(rules.Metric), "stable");
values = string(rules.Threshold(first));
observations = table(metrics, values, ...
    'VariableNames', {'Metric','Observed'});
end
