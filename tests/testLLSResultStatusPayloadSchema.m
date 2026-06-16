function ok = testLLSResultStatusPayloadSchema()
%TESTLLSRESULTSTATUSPAYLOADSCHEMA Canonical result status schema is emitted.

setup6GRSimToolkit("Verbose", false);

ctx = llsRootGateFixture("pass");
verdict = sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);

statusPath = fullfile(ctx.Layout.ReportCSVDir, "result_status_summary.csv");
assert(exist(statusPath, "file") == 2, "result_status_summary.csv must be emitted.");
T = readtable(statusPath, "VariableNamingRule", "preserve");
sixgr.truth.validateResultStatusPayload(T);
assert(logical(T.RunCompleted(1)), "RunCompleted must be true for the completed fixture.");
assert(logical(T.ResultOk(1)), "Clean strict fixture must pass the canonical ResultOk formula.");
assert(logical(verdict.Ok), "Legacy truth-contract verdict must remain aligned with canonical ResultOk for clean fixtures.");

ok = true;
end
