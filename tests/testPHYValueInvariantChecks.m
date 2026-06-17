function ok = testPHYValueInvariantChecks()
%TESTPHYVALUEINVARIANTCHECKS Verify value-level invariant failures are surfaced.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
addpath(fullfile(pwd, "tests"));

ctx = llsImplementationHarnessFixture("llr_low");
out = sixgr.validation.LLSValidationHarness(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig, ...
    "WriteArtifacts", false);

invT = out.PHYValueInvariantChecks(string(out.PHYValueInvariantChecks.CheckId) == "LLR-01", :);
assert(height(invT) == 2, "Low-LLR fixture should emit one DL and one UL LLR invariant row.");
assert(all(~logical(invT.Pass)), "Low-LLR fixture should fail high-SNR LLR invariants.");
assert(all(string(invT.FailureReason) == "high_snr_llr_near_zero"), ...
    "LLR invariant failures should preserve the expected failure reason.");

ok = true;
end
