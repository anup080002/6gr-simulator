function ok = testLLSScenarioObjectiveGateRequiresConfiguredEffectiveEvidence()
%TESTLLSSCENARIOOBJECTIVEGATEREQUIRESCONFIGUREDEFFECTIVEEVIDENCE Missing fixed evidence fails.

setup6GRSimToolkit("Verbose", false);

ctx = llsRootGateFixture("missing_effective");
sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);

statusT = readtable(fullfile(ctx.Layout.ReportCSVDir, "result_status_summary.csv"), "VariableNamingRule", "preserve");
opT = readtable(fullfile(ctx.Layout.ReportCSVDir, "configured_effective_operating_point.csv"), "VariableNamingRule", "preserve");

assert(~logical(statusT.ConfiguredEffectiveOk(1)), "Fixed-anchor rows missing effective MCS/rank/layers/modulation must fail.");
assert(any(contains(string(opT.MismatchFields), "mcs_missing")), ...
    "Missing effective MCS evidence must be visible in MismatchFields.");
assert(~logical(statusT.ResultOk(1)), "ResultOk must fail when configured/effective evidence is missing.");

ok = true;
end
