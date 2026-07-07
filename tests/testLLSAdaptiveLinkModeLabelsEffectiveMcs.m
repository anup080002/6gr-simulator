function ok = testLLSAdaptiveLinkModeLabelsEffectiveMcs()
%TESTLLSADAPTIVELINKMODELABELSEFFECTIVEMCS Adaptive lower MCS is not fixed-anchor success.

setup6GRSimToolkit("Verbose", false);

ctx = llsRootGateFixture("adaptive_link");
sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);

statusT = readtable(fullfile(ctx.Layout.ReportCSVDir, "result_status_summary.csv"), "VariableNamingRule", "preserve");
opT = readtable(fullfile(ctx.Layout.ReportCSVDir, "configured_effective_operating_point.csv"), "VariableNamingRule", "preserve");
classT = readtable(fullfile(ctx.Layout.ReportCSVDir, "run_classification.csv"), "VariableNamingRule", "preserve");

assert(string(statusT.ScenarioMode(1)) == "adaptive_link", "Adaptive fixture must be labeled adaptive_link.");
assert(string(classT.RunClass(1)) == "adaptive_system_diagnostic", "Adaptive fixture must classify as adaptive_system_diagnostic.");
assert(all(logical(opT.AdaptiveMode)), "Operating-point rows must mark AdaptiveMode=true.");
assert(logical(statusT.ConfiguredEffectiveOk(1)), "Adaptive mode must not be failed by lower effective MCS alone.");
assert(~logical(classT.PublicationLLSEligible(1)), "Adaptive diagnostic runs must not claim fixed-link publication eligibility.");
assert(~all(logical(opT.ExactOperatingPointMatch)), "Adaptive rows must still expose the configured/effective mismatch honestly.");

ok = true;
end
