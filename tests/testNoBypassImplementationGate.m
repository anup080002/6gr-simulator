function ok = testNoBypassImplementationGate()
%TESTNOBYPASSIMPLEMENTATIONGATE Verify bypassed real-function paths fail closed.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
addpath(fullfile(pwd, "tests"));

ctx = llsImplementationHarnessFixture("bypass_dl");
out = sixgr.validation.LLSValidationHarness(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig, ...
    "WriteArtifacts", false);

gateT = out.NoBypassGate(string(out.NoBypassGate.BlockId) == "PDSCH", :);
assert(height(gateT) == 1, "Expected a single no-bypass gate row for PDSCH.");
assert(logical(gateT.BypassDetected), "PDSCH should be flagged as bypassed when runtime call evidence is absent.");
assert(~logical(gateT.GatePass), "Bypassed PDSCH path must fail the no-bypass gate.");

covT = out.RuntimeFunctionCoverage(string(out.RuntimeFunctionCoverage.Subsystem) == "downlink_data", :);
assert(all(~logical(covT.ActuallyCalled)), "Bypass fixture should leave downlink data functions uncalled.");
assert(all(string(covT.FailureReason) == "expected_function_not_called"), ...
    "Coverage failures should point to the missing real function call.");

ok = true;
end
