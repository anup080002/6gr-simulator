function ok = testLLSConfiguredEffectiveMismatchFailsScenarioObjective()
%TESTLLSCONFIGUREDEFFECTIVEMISMATCHFAILSSCENARIOOBJECTIVE Exact match rate 0% is fatal.

setup6GRSimToolkit("Verbose", false);

ctx = llsRootGateFixture("configured_effective_mismatch");
sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);

statusT = readtable(fullfile(ctx.Layout.ReportCSVDir, "result_status_summary.csv"), "VariableNamingRule", "preserve");
summary = jsondecode(fileread(fullfile(ctx.Layout.ReportDir, "json", "configured_effective_operating_point_summary.json")));

assert(double(summary.DLExactMatchRate) == 0, "DL exact configured/effective match rate must be 0 for the mismatch fixture.");
assert(double(summary.ULExactMatchRate) == 0, "UL exact configured/effective match rate must be 0 for the mismatch fixture.");
assert(~logical(statusT.ScenarioObjectiveOk(1)), "ScenarioObjectiveOk must fail when fixed exact-match rate is 0%.");
assert(~logical(statusT.ResultOk(1)), "ResultOk must fail when fixed exact-match rate is 0%.");

ok = true;
end
