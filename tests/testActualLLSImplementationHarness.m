function ok = testActualLLSImplementationHarness()
%TESTACTUALLLSIMPLEMENTATIONHARNESS Verify partial-actual verdict from runtime evidence.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
addpath(fullfile(pwd, "tests"));

ctx = llsImplementationHarnessFixture("partial_actual");
out = sixgr.validation.LLSValidationHarness(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig, ...
    "WriteArtifacts", false);

assert(string(out.Summary.ActualLLSVerdict) == "partial actual LLS", ...
    "Expected partial actual LLS verdict for data-channel-only runtime evidence.");
assert(double(out.Summary.EnabledBlockCount) == 3, ...
    "Fixture should enable PDSCH, PUSCH, and KPI only.");

matrixT = out.ValidationMatrix;
pdsch = matrixT(string(matrixT.BlockId) == "PDSCH", :);
pusch = matrixT(string(matrixT.BlockId) == "PUSCH", :);
kpi = matrixT(string(matrixT.BlockId) == "KPI", :);

assert(isscalar(pdsch.ImplementationPass) && logical(pdsch.ImplementationPass), ...
    "PDSCH should pass actual runtime implementation checks.");
assert(isscalar(pusch.ImplementationPass) && logical(pusch.ImplementationPass), ...
    "PUSCH should pass actual runtime implementation checks.");
assert(isscalar(kpi.ImplementationPass) && ~logical(kpi.ImplementationPass), ...
    "KPI should fail closed when no strict reference path is available.");
assert(string(kpi.FailureReason) == "reference_path_unavailable", ...
    "KPI failure should stay explicitly tied to missing strict reference evidence.");

ok = true;
end
