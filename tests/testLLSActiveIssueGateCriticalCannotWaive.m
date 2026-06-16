function ok = testLLSActiveIssueGateCriticalCannotWaive()
%TESTLLSACTIVEISSUEGATECRITICALCANNOTWAIVE Critical root issues cannot be waived.

setup6GRSimToolkit("Verbose", false);

ctx = llsRootGateFixture("critical_waiver");
sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);

statusT = readtable(fullfile(ctx.Layout.ReportCSVDir, "result_status_summary.csv"), "VariableNamingRule", "preserve");
gateT = readtable(fullfile(ctx.Layout.ReportCSVDir, "active_issue_gate_summary.csv"), "VariableNamingRule", "preserve");

assert(~logical(statusT.ActiveIssueGateOk(1)), "Critical waived_non_blocking issue must still fail ActiveIssueGateOk.");
assert(~logical(statusT.ResultOk(1)), "Critical waived_non_blocking issue must fail ResultOk.");
assert(any(string(gateT.Status) == "critical_waiver_rejected"), ...
    "active_issue_gate_summary.csv must show critical_waiver_rejected.");

ok = true;
end
