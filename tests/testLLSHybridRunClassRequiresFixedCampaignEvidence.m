function ok = testLLSHybridRunClassRequiresFixedCampaignEvidence()
%TESTLLSHYBRIDRUNCLASSREQUIRESFIXEDCAMPAIGNEVIDENCE Hybrid validation needs fixed-link and adaptive evidence.

setup6GRSimToolkit("Verbose", false);

ctx = llsRootGateFixture("hybrid_missing_campaign");
verdict = sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);
assert(~logical(verdict.Ok), "Hybrid validation without fixed-link campaign evidence must fail the final result.");

statusT = readtable(fullfile(ctx.Layout.ReportCSVDir, "result_status_summary.csv"), "VariableNamingRule", "preserve");
classT = readtable(fullfile(ctx.Layout.ReportCSVDir, "run_classification.csv"), "VariableNamingRule", "preserve");

assert(string(classT.RunClass(1)) == "hybrid_validation", "Hybrid fixture must classify as hybrid_validation.");
assert(~logical(classT.PublicationLLSEligible(1)), "Hybrid validation without fixed-link curves must not be publication-eligible.");
assert(contains(lower(string(classT.Reason(1))), "fixed-link campaign"), ...
    "Hybrid failure reason must point to missing fixed-link campaign evidence.");
assert(~logical(statusT.RunClassGateOk(1)), "Hybrid validation must fail the run-class gate when fixed-link evidence is missing.");
assert(~logical(statusT.ScenarioObjectiveOk(1)), "Hybrid validation must fail ScenarioObjectiveOk when fixed-link evidence is missing.");

ok = true;
end
