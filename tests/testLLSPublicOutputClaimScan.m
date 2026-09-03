function ok = testLLSPublicOutputClaimScan()
%TESTLLSPUBLICOUTPUTCLAIMSCAN Public broad claims must be scanned and rejected.

setup6GRSimToolkit("Verbose", false);

ctx = llsRootGateFixture("broad_claim");
sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);

% Canonical simulator CSVs are comma-delimited.  MATLAB R2026a delimiter
% inference can mistake the underscores in quoted claim text for a
% delimiter, so exercise the production reader rather than auto-detection.
scanT = sixgr.util.csvReadTable(fullfile( ...
    ctx.Layout.ReportCSVDir, "public_output_claim_scan.csv"));
assert(height(scanT) > 0, "public_output_claim_scan.csv must contain scanned claim rows.");
assert(any(~logical(scanT.Pass) & string(scanT.IssueIdIfFailed) == "AUD-001"), ...
    "Broad rejected public claim rows must fail with AUD-001.");
assert(any(contains(string(scanT.AllowedReplacement), "study")), ...
    "Rejected public claim scan rows must suggest honest study/profile replacement wording.");

ok = true;
end
