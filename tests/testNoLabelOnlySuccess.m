function ok = testNoLabelOnlySuccess()
%TESTNOLABELONLYSUCCESS Verify label-only passes are rejected as REALPHY-001.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
addpath(fullfile(pwd, "tests"));

ctx = llsImplementationHarnessFixture("label_only");
out = sixgr.validation.LLSValidationHarness(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig, ...
    "WriteArtifacts", false);

assert(string(out.Summary.ActualLLSVerdict) == "label/proxy simulator", ...
    "Label-only fixture must be classified as a label/proxy simulator.");

matrixT = out.ValidationMatrix;
pdsch = matrixT(string(matrixT.BlockId) == "PDSCH", :);
assert(logical(pdsch.LabelOnlyEvidence), "PDSCH should be flagged as label-only evidence.");
assert(string(pdsch.IssueIdIfFailed) == "REALPHY-001", ...
    "Label-only passes must fail under REALPHY-001.");
assert(string(pdsch.FailureReason) == "pass_row_has_no_real_lls_implementation_evidence", ...
    "Label-only failure reason should stay explicit.");

ok = true;
end
