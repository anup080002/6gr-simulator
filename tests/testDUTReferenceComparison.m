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

ctxGBits = llsImplementationHarnessFixture("partial_actual");
ulPath = fullfile(ctxGBits.RunFolder, "air_interface", "csv", "ul_pusch_trials.csv");
ulT = readtable(ulPath, "VariableNamingRule", "preserve");
qm = 2; % fixture modulation is QPSK
ulT.RateMatchedBits = ulT.DataRECount .* qm .* ulT.Layers;
ulT.MeasuredRateMatchedCodewordLLRBits = ulT.RateMatchedBits;
ulT.DataRECount = ulT.RateMatchedBits;
writetable(ulT, ulPath);
outGBits = sixgr.validation.LLSValidationHarness(ctxGBits.RunFolder, ctxGBits.ScenarioConfig, ctxGBits.InternalConfig, ...
    "WriteArtifacts", false);
puschGBitRows = outGBits.DUTReferenceComparison(string(outGBits.DUTReferenceComparison.BlockId) == "PUSCH", :);
assert(~isempty(puschGBitRows) && any(~logical(puschGBitRows.Pass)), ...
    "PUSCH reference comparison must reject coded-bit budget G when it is mislabeled as physical DataRECount.");

ctxComputedE = llsImplementationHarnessFixture("partial_actual");
ulPath = fullfile(ctxComputedE.RunFolder, "air_interface", "csv", "ul_pusch_trials.csv");
ulT = readtable(ulPath, "VariableNamingRule", "preserve");
ulT.DataRECountPerLayer = ulT.DataRECount;
ulT.TotalDataRECount = ulT.DataRECount .* ulT.Layers;
ulT.ModulationOrderQm = repmat(2, height(ulT), 1);
ulT.ComputedE_TS38212 = ulT.DataRECountPerLayer .* ulT.ModulationOrderQm .* ulT.Layers;
ulT.RateMatchedBits = ulT.ComputedE_TS38212;
ulT.RateMatchedBitsDelta_TS38212 = ulT.RateMatchedBits - ulT.ComputedE_TS38212;
writetable(ulT, ulPath);
trialData = sixgr.analytics.loadAllTrialData(ctxComputedE.RunFolder);
analysis = sixgr.analytics.buildScenarioAnalyticsTables(ctxComputedE.RunFolder, trialData, ctxComputedE.ScenarioConfig);
tbsT = readtable(analysis.Paths.TBSReferenceComparison, "VariableNamingRule", "preserve");
puschRows = tbsT(string(tbsT.Direction) == "UL", :);
assert(~isempty(puschRows) && all(abs(double(puschRows.RateMatchedBits_Delta)) < 1e-9), ...
    "Rate-matching audit must use ComputedE_TS38212 when present.");

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
