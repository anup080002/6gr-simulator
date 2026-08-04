function ok = testWebGUIAdaptiveRunClassification()
%TESTWEBGUIADAPTIVERUNCLASSIFICATION Explicit WebGUI AMC intent survives reduction.

setup6GRSimToolkit("Verbose", false);
ctx = llsRootGateFixture("adaptive_link");
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "webgui_sinr_sweep_64x4_mu_mimo_full.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, ctx.RunFolder);
sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, scfg, cfg);
classification = readtable(fullfile(ctx.Layout.ReportCSVDir, ...
    "run_classification.csv"), "VariableNamingRule", "preserve");
assert(height(classification) == 1);
assert(string(classification.RunClass(1)) == "adaptive_system_diagnostic");
assert(logical(classification.AdaptiveMode(1)), ...
    "The explicit adaptive_system_diagnostic YAML class must report AdaptiveMode=true.");
assert(~logical(classification.PublicationLLSEligible(1)), ...
    "Adaptive diagnostics must remain ineligible for fixed-link publication claims.");
ok = true;
end
