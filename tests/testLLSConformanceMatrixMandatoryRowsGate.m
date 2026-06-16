function ok = testLLSConformanceMatrixMandatoryRowsGate()
%TESTLLSCONFORMANCEMATRIXMANDATORYROWSGATE Mandatory runtime rows gate conformance.

setup6GRSimToolkit("Verbose", false);

ctx = llsRootGateFixture("pass");
verdict = sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);
statusT = readtable(fullfile(ctx.Layout.ReportCSVDir, "result_status_summary.csv"), "VariableNamingRule", "preserve");
assert(logical(statusT.ResultOk(1)), "Baseline fixture must pass before injecting mandatory partial evidence.");

bad = verdict;
bad.CheckDetails.SRS = struct("SRSRequired", true, "SRSStrictOk", false, "SRSStatus", "unavailable");
dlT = readtable(fullfile(ctx.Layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), "VariableNamingRule", "preserve");
ulT = readtable(fullfile(ctx.Layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), "VariableNamingRule", "preserve");
opSummary = sixgr.truth.summarizeEffectiveOperatingPoint(ctx.ScenarioConfig, dlT, ulT);
rootBad = sixgr.truth.evaluateStrictAnchorStatus(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig, bad, dlT, ulT, opSummary);
auditT = readtable(fullfile(ctx.Layout.ReportCSVDir, "conformance_matrix_runtime_audit.csv"), "VariableNamingRule", "preserve");

assert(~logical(rootBad.Status.MandatorySubsystemsOk), "Required unavailable SRS evidence must fail MandatorySubsystemsOk.");
assert(~logical(rootBad.Status.StandardsConformanceOk), "Mandatory unavailable runtime evidence must fail StandardsConformanceOk.");
assert(any(string(auditT.Subsystem) == "srs" & ~logical(auditT.Pass)), ...
    "conformance_matrix_runtime_audit.csv must include the failing SRS row.");

ok = true;
end
