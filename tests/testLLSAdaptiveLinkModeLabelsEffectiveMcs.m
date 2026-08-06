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
assert(logical(classT.AdaptiveMode(1)), "Adaptive run classification must preserve AdaptiveMode=true.");
assert(all(logical(opT.AdaptiveMode)), "Operating-point rows must mark AdaptiveMode=true.");
assert(~logical(statusT.ConfiguredEffectiveOk(1)), ...
    "Adaptive lower MCS must not be mislabeled as an exact configured/effective match.");
assert(logical(statusT.ConfiguredEffectivePolicyOk(1)), ...
    "Adaptive lower MCS may conform to policy even though exact match is false.");
assert(~logical(classT.PublicationLLSEligible(1)), "Adaptive diagnostic runs must not claim fixed-link publication eligibility.");
assert(~all(logical(opT.ExactOperatingPointMatch)), "Adaptive rows must still expose the configured/effective mismatch honestly.");

fixedRankCtx = llsRootGateFixture("adaptive_fixed_rank");
sixgr.truth.evaluateLLSRuntimeTruthContract( ...
    fixedRankCtx.RunFolder, fixedRankCtx.ScenarioConfig, fixedRankCtx.InternalConfig);
fixedRankStatus = readtable(fullfile(fixedRankCtx.Layout.ReportCSVDir, ...
    "result_status_summary.csv"), "VariableNamingRule", "preserve");
assert(~logical(fixedRankStatus.ConfiguredEffectiveOk(1)), ...
    "AMC must not hide collapse of an independently fixed rank/layer contract.");
assert(~logical(fixedRankStatus.ConfiguredEffectivePolicyOk(1)), ...
    "Fixed rank/layer collapse must fail adaptive policy conformance.");

% A decoder outage must not be confused with a transmission-rank collapse:
% the transmitted rank/layers remain authoritative for configured execution.
for fileName = ["dl_pdsch_trials.csv", "ul_pusch_trials.csv"]
    pathValue = fullfile(fixedRankCtx.Layout.AirInterfaceCSVDir, fileName);
    trialT = readtable(pathValue, "VariableNamingRule", "preserve");
    trialT.TransmittedRank(:) = 2;
    trialT.TransmittedLayers(:) = 2;
    trialT.EffectiveRank(:) = 0;
    trialT.EffectiveLayers(:) = 0;
    trialT.CRCPass(:) = false;
    sixgr.util.csvWriteTable(pathValue, trialT);
end
sixgr.truth.evaluateLLSRuntimeTruthContract( ...
    fixedRankCtx.RunFolder, fixedRankCtx.ScenarioConfig, fixedRankCtx.InternalConfig);
outageStatus = readtable(fullfile(fixedRankCtx.Layout.ReportCSVDir, ...
    "result_status_summary.csv"), "VariableNamingRule", "preserve");
assert(~logical(outageStatus.ConfiguredEffectiveOk(1)), ...
    "Adaptive MCS divergence remains an exact mismatch after an outage.");
assert(logical(outageStatus.ConfiguredEffectivePolicyOk(1)), ...
    "CRC failure must preserve policy conformance when transmitted rank/layers match.");

ok = true;
end
