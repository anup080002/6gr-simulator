function results = runLLSTests(varargin)
%RUNLLSTESTS Run the focused LLS and coupled-truth regression pack only.
% Keep this file ASCII-only.

p = inputParser;
p.addParameter("Verbose", true, @(x) islogical(x) && isscalar(x));
p.addParameter("Names", strings(0,1), @(x) isstring(x) || ischar(x) || iscellstr(x));
p.parse(varargin{:});
opt = p.Results;

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false, "CheckYAMLRuntime", false);
setupPythonYamlFor6GRSim("Verbose", logical(opt.Verbose), "RequireYAML", true, "ForceRefresh", true);

testNames = string(opt.Names);
if ischar(opt.Names)
    testNames = string({opt.Names});
end
if isempty(testNames) || all(strlength(testNames) == 0)
    testNames = localDefaultTestNames();
end

rootDir = fileparts(mfilename("fullpath"));
testPaths = strings(numel(testNames), 1);
for i = 1:numel(testNames)
    name = string(testNames(i));
    if endsWith(lower(name), ".m")
        testPaths(i) = string(fullfile(rootDir, "tests", name));
    else
        testPaths(i) = string(fullfile(rootDir, "tests", name + ".m"));
    end
end

if logical(opt.Verbose)
    fprintf("[lls-tests] Running %d focused LLS tests under R2023b-compatible MATLAB path setup.\n", numel(testPaths));
end

suite = matlab.unittest.TestSuite.empty;
addpath(fullfile(rootDir, "tests"), "-begin");
results = repmat(struct("Name", "", "Passed", false, "Failed", false, "Incomplete", false, "Duration_s", NaN, "Message", ""), numel(testPaths), 1);
for i = 1:numel(testPaths)
    [~, funcName] = fileparts(char(testPaths(i)));
    results(i).Name = char(string(funcName));
    tStart = tic;
    try
        outcome = feval(funcName);
        results(i).Passed = logical(isempty(outcome) || outcome);
        results(i).Failed = ~results(i).Passed;
        results(i).Incomplete = false;
    catch ME
        results(i).Passed = false;
        results(i).Failed = true;
        results(i).Incomplete = false;
        results(i).Message = char(string(ME.message));
        if logical(opt.Verbose)
            fprintf("[lls-tests] FAIL %s :: %s\n", funcName, ME.message);
        end
    end
    results(i).Duration_s = toc(tStart);
end
failed = [results.Failed];
incomplete = [results.Incomplete];

if logical(opt.Verbose)
    fprintf("[lls-tests] Passed: %d  Failed: %d  Incomplete: %d\n", ...
        nnz([results.Passed]), nnz(failed), nnz(incomplete));
end

if any(failed) || any(incomplete)
    failedNames = string({results(failed | incomplete).Name});
    error("sixgr:tests:LLSFocusedFailure", ...
        "Focused LLS test pack failed: %s", strjoin(failedNames, ", "));
end
end

function names = localDefaultTestNames()
names = [ ...
    "testLLS_DL.m"
    "testLLS_UL.m"
    "testLLS_ReferencePoints.m"
    "testChannelEstimationValidation.m"
    "testFadingLinkDelayAlignment.m"
    "testNRCQITableAndGrantSizing.m"
    "testLLS700MHzTruthSNRResponse.m"
    "testLLS700MHzFullTruthProfile.m"
    "testLLSClosedLoopLinkAdaptation.m"
    "testLLSHARQGrantReplayTBConsistency.m"
    "testLLSCoupledTruthFallbackFeedbackSanity.m"
    "testLLSCoupledTruthHARQRoundTrip.m"
    "test6GLLSCoupledTruthBidirectional.m"
    "test6GLLSMultiUserBeamforming.m"
    "testLLSHARQExercise.m"
    "testLLSResultRichness.m"
    "testLLSReportBundle.m"
    "testLLSAvailabilityAggregation.m"
    "testLLSProductionArtifactSuppression.m"
    "testLLSScenarioStatusPropagation.m"
    "testLLSEffectiveOperatingPointSummary.m"
    "testLLSSweepTrialBudget.m"
    "testLLSDeploymentTopologyConfigWiring.m"
    ];
end
