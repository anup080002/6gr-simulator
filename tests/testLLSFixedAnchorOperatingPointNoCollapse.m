function ok = testLLSFixedAnchorOperatingPointNoCollapse()
%TESTLLSFIXEDANCHOROPERATINGPOINTNOCOLLAPSE Fixed rank/MCS/modulation collapse is fatal.

setup6GRSimToolkit("Verbose", false);

ctx = llsRootGateFixture("fixed_collapse");
verdict = sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);
assert(~logical(verdict.Ok), "Fixed-anchor collapse must fail the final result.");

statusT = readtable(fullfile(ctx.Layout.ReportCSVDir, "result_status_summary.csv"), "VariableNamingRule", "preserve");
opT = readtable(fullfile(ctx.Layout.ReportCSVDir, "configured_effective_operating_point.csv"), "VariableNamingRule", "preserve");
issueT = readtable(fullfile(ctx.Layout.ReportCSVDir, "result_issue_registry.csv"), "VariableNamingRule", "preserve");

assert(~logical(statusT.ConfiguredEffectiveOk(1)), "ConfiguredEffectiveOk must be false for fixed-anchor collapse.");
assert(~logical(statusT.ScenarioObjectiveOk(1)), "ScenarioObjectiveOk must be false for fixed-anchor collapse.");
assert(all(~logical(opT.ExactOperatingPointMatch)), "Every collapsed fixed-anchor row must record ExactOperatingPointMatch=false.");
assert(any(contains(string(opT.MismatchFields), "rank") & contains(string(opT.MismatchFields), "mcs")), ...
    "MismatchFields must include rank and MCS for the collapse.");
assert(any(string(issueT.issue_id) == "AUD-002"), "AUD-002 must be emitted for configured/effective collapse.");

ok = true;
end
