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
assert(logical(T.ArtifactsWritten(1)) && logical(T.ArtifactCompletenessOk(1)), ...
    "Artifact creation and artifact completeness must be separate passing gates.");
assert(logical(T.ResultOk(1)), "Clean strict fixture must pass the canonical ResultOk formula.");
assert(logical(verdict.Ok), "Legacy truth-contract verdict must remain aligned with canonical ResultOk for clean fixtures.");

scenarioSummary = readtable(fullfile(ctx.Layout.ReportCSVDir, "scenario_summary.csv"), ...
    "VariableNamingRule", "preserve");
assert(logical(scenarioSummary.Ok(1)) == logical(T.ResultOk(1)) && ...
    logical(scenarioSummary.ResultOk(1)) == logical(T.ResultOk(1)), ...
    "Scenario-summary root aliases must match the canonical result status.");
assert(logical(scenarioSummary.VisualArtifactIntegrityOk(1)) == ...
        logical(T.VisualArtifactGateOk(1)) && ...
    double(scenarioSummary.VisualArtifactIntegrityFailureCount(1)) == ...
        double(T.VisualArtifactFailureCount(1)), ...
    "Legacy visual-integrity summary aliases must be refreshed by terminal status reduction.");

ok = true;
end
