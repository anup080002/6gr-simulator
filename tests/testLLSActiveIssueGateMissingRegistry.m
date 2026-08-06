function ok = testLLSActiveIssueGateMissingRegistry()
%TESTLLSACTIVEISSUEGATEMISSINGREGISTRY Missing issue evidence fails closed.

setup6GRSimToolkit("Verbose", false);
ctx = llsRootGateFixture("pass");
registryPath = fullfile(ctx.Layout.ReportCSVDir, "result_issue_registry.csv");
assert(isfile(registryPath));
delete(registryPath);
sixgr.truth.evaluateLLSRuntimeTruthContract( ...
    ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);
statusT = readtable(fullfile(ctx.Layout.ReportCSVDir, ...
    "result_status_summary.csv"), "VariableNamingRule", "preserve");
gateT = readtable(fullfile(ctx.Layout.ReportCSVDir, ...
    "active_issue_gate_summary.csv"), "VariableNamingRule", "preserve");
assert(~logical(statusT.ActiveIssueGateOk(1)) && ~logical(statusT.ResultOk(1)));
assert(string(statusT.IssueRegistryStatus(1)) == "NOT_EVALUATED");
assert(double(statusT.IssueRegistryRowCount(1)) == 0);
assert(height(gateT) == 1 && ...
    string(gateT.IssueId(1)) == "ISSUE_REGISTRY_NOT_EVALUATED");
assert(string(gateT.Status(1)) == "not_evaluated");

ok = true;
fprintf("PASS testLLSActiveIssueGateMissingRegistry: missing/header-only registry cannot pass.\n");
end
