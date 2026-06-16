function ok = testLLSPublicOutputClaimScan()
%TESTLLSPUBLICOUTPUTCLAIMSCAN Public broad claims must be scanned and rejected.

setup6GRSimToolkit("Verbose", false);

ctx = llsRootGateFixture("broad_claim");
sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);

scanT = readtable(fullfile(ctx.Layout.ReportCSVDir, "public_output_claim_scan.csv"), "VariableNamingRule", "preserve");
assert(height(scanT) > 0, "public_output_claim_scan.csv must contain scanned claim rows.");
assert(any(~logical(scanT.Pass) & string(scanT.IssueIdIfFailed) == "AUD-001"), ...
    "Broad rejected public claim rows must fail with AUD-001.");
assert(any(contains(string(scanT.AllowedReplacement), "study")), ...
    "Rejected public claim scan rows must suggest honest study/profile replacement wording.");

ok = true;
end
