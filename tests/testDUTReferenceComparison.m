function ok = testDUTReferenceComparison()
%TESTDUTREFERENCECOMPARISON Verify positive and negative DUT-vs-reference outcomes.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
addpath(fullfile(pwd, "tests"));

ctxPass = llsImplementationHarnessFixture("partial_actual");
outPass = sixgr.validation.LLSValidationHarness(ctxPass.RunFolder, ctxPass.ScenarioConfig, ctxPass.InternalConfig, ...
    "WriteArtifacts", false);
passRows = outPass.DUTReferenceComparison(ismember(string(outPass.DUTReferenceComparison.BlockId), ["PDSCH","PUSCH"]), :);
assert(~isempty(passRows), "Expected DUT-vs-reference rows for PDSCH/PUSCH.");
assert(all(logical(passRows.Pass)), "Reference-aligned fixture should pass all PDSCH/PUSCH comparisons.");

ctxFail = llsImplementationHarnessFixture("reference_mismatch");
outFail = sixgr.validation.LLSValidationHarness(ctxFail.RunFolder, ctxFail.ScenarioConfig, ctxFail.InternalConfig, ...
    "WriteArtifacts", false);
failRows = outFail.DUTReferenceComparison(string(outFail.DUTReferenceComparison.BlockId) == "PDSCH", :);
assert(~isempty(failRows), "Expected PDSCH mismatch rows.");
assert(any(~logical(failRows.Pass)), "Reference-mismatch fixture should fail PDSCH comparison.");
assert(any(string(failRows.FailureReason) == "dut_reference_mismatch"), ...
    "Mismatch rows must preserve the DUT-vs-reference failure reason.");

ok = true;
end
