function ok = testRealFunctionUseCoverage()
%TESTREALFUNCTIONUSECOVERAGE Verify profiler-backed function coverage for real PHY calls.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
addpath(fullfile(pwd, "tests"));

ctx = llsImplementationHarnessFixture("partial_actual");
out = sixgr.validation.LLSValidationHarness(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig, ...
    "WriteArtifacts", false);

covT = out.RuntimeFunctionCoverage(ismember(string(out.RuntimeFunctionCoverage.FunctionName), ...
    ["sixgr.phy.dl.PDSCH_Tx","sixgr.phy.dl.PDSCH_Rx","sixgr.phy.ul.PUSCH_Tx","sixgr.phy.ul.PUSCH_Rx"]), :);
assert(height(covT) == 4, "Expected four data-path runtime coverage rows.");
assert(all(logical(covT.ActuallyCalled)), "Profiler-backed data-path functions must be marked called.");
assert(all(logical(covT.ImplementationCoveragePass)), ...
    "Called data-path functions with evidence should pass coverage gating.");
assert(all(double(covT.CallCount) > 0), "Profiler-backed data-path functions must expose positive call counts.");

ok = true;
end
