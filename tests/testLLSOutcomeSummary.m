function ok = testLLSOutcomeSummary()
%TESTLLSOUTCOMESUMMARY Verify summary artifacts reflect the actual-LLS harness outputs.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
addpath(fullfile(pwd, "tests"));

ctx = llsImplementationHarnessFixture("partial_actual");
out = sixgr.validation.LLSValidationHarness(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig, ...
    "WriteArtifacts", true);

mustExist = { ...
    out.ReportArtifacts.PHYOutcomeCSV
    out.ReportArtifacts.LinkPerformanceCSV
    out.ReportArtifacts.BlockCorrectnessCSV
    out.ReportArtifacts.ReferenceComparisonSummaryCSV
    out.ReportArtifacts.ImplementationCoverageSummaryCSV
    out.ReportArtifacts.ValidationMatrixCSV};
for i = 1:numel(mustExist)
    assert(exist(mustExist{i}, "file") == 2, "Missing expected outcome artifact: %s", mustExist{i});
end

phyOutcome = readtable(out.ReportArtifacts.PHYOutcomeCSV, "VariableNamingRule", "preserve");
pdsch = phyOutcome(string(phyOutcome.Feature) == "PDSCH", :);
pusch = phyOutcome(string(phyOutcome.Feature) == "PUSCH", :);
kpi = phyOutcome(string(phyOutcome.Feature) == "KPI", :);
assert(logical(pdsch.OverallBlockPass) && logical(pusch.OverallBlockPass), ...
    "PDSCH and PUSCH should pass the outcome summary.");
assert(~logical(kpi.OverallBlockPass), "KPI should fail closed in the outcome summary.");

linkPerf = readtable(out.ReportArtifacts.LinkPerformanceCSV, "VariableNamingRule", "preserve");
assert(height(linkPerf) == 2, "Partial-actual fixture should emit one DL and one UL link-performance row.");
assert(all(ismember(["Direction","MeanSINRdB","RawBLER","ThroughputMbps","GoodputMbps"], string(linkPerf.Properties.VariableNames))), ...
    "Link-performance summary must expose the required runtime outcome columns.");

ok = true;
end
