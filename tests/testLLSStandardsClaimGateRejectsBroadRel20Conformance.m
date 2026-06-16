function ok = testLLSStandardsClaimGateRejectsBroadRel20Conformance()
%TESTLLSSTANDARDSCLAIMGATEREJECTSBROADREL20CONFORMANCE Broad claims need proof.

setup6GRSimToolkit("Verbose", false);

ctx = llsRootGateFixture("broad_claim");
verdict = sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);
assert(~logical(verdict.Ok), "Broad 3GPP/6G/Rel-20 conformance claim must fail strict success without full proof.");

statusT = readtable(fullfile(ctx.Layout.ReportCSVDir, "result_status_summary.csv"), "VariableNamingRule", "preserve");
claimT = readtable(fullfile(ctx.Layout.ReportCSVDir, "standards_claim_audit.csv"), "VariableNamingRule", "preserve");
issueT = readtable(fullfile(ctx.Layout.ReportCSVDir, "result_issue_registry.csv"), "VariableNamingRule", "preserve");

assert(~logical(statusT.ClaimAllowed(1)), "ClaimAllowed must be false for rejected broad conformance wording.");
assert(string(statusT.ClaimStatus(1)) == "claim_rejected", "ClaimStatus must be claim_rejected.");
assert(~logical(statusT.StandardsConformanceOk(1)) && ~logical(statusT.ResultOk(1)), ...
    "Rejected standards claims must set StandardsConformanceOk=false and ResultOk=false.");
assert(any(string(claimT.IssueIdIfFailed) == "AUD-001"), "standards_claim_audit.csv must identify AUD-001.");
assert(any(string(issueT.issue_id) == "AUD-001" & lower(string(issueT.severity)) == "critical"), ...
    "result_issue_registry.csv must emit AUD-001 as a critical active issue.");

studyCtx = llsRootGateFixture("honest_study");
sixgr.truth.evaluateLLSRuntimeTruthContract(studyCtx.RunFolder, studyCtx.ScenarioConfig, studyCtx.InternalConfig);
studyStatus = readtable(fullfile(studyCtx.Layout.ReportCSVDir, "result_status_summary.csv"), "VariableNamingRule", "preserve");
assert(logical(studyStatus.ClaimAllowed(1)), "Honest rel20_study_context label must not be rejected as broad conformance.");
assert(string(studyStatus.ClaimProfile(1)) == "rel20_study_context", "Honest study fixture must keep the explicit claim profile.");

ok = true;
end
