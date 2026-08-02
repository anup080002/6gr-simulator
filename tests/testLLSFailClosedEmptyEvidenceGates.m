function ok = testLLSFailClosedEmptyEvidenceGates()
%TESTLLSFAILCLOSEDEMPTYEVIDENCEGATES Required evidence cannot pass vacuously.

setup6GRSimToolkit("Verbose", false);

localMissingPDCCHBindingEvidenceFails();
localMissingKPIBindingEvidenceFails();
localPersistedMIMOGateFailureReachesRootStatus();

ok = true;
end

function localPersistedMIMOGateFailureReachesRootStatus()
ctx = llsRootGateFixture("honest_study");
sixgr.util.ensureDir(fullfile(ctx.Layout.BeamformingCSVDir, ".keep"));
mimoT = table(["DL";"UL"], [true;false], [true;true], [true;true], ...
    [true;true], [true;false], ...
    'VariableNames', {'Direction','ScenarioObjectivePass','SpatialContractMatch', ...
    'FixedOperatingPointMatch','AdaptivePolicyConformance','MUExecutionMatch'});
sixgr.util.csvWriteTable(fullfile(ctx.Layout.BeamformingCSVDir, ...
    "mimo_configured_vs_effective.csv"), mimoT);

verdict = sixgr.truth.evaluateLLSRuntimeTruthContract( ...
    ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);
statusT = readtable(fullfile(ctx.Layout.ReportCSVDir, "result_status_summary.csv"), ...
    "VariableNamingRule", "preserve");
assert(~logical(statusT.ConfiguredEffectiveOk(1)) && ...
    any(contains(string(verdict.Failures), "mimo_four_gate_configured_effective_evidence_failed")), ...
    "A persisted failing MIMO four-gate summary must force the canonical root configured/effective status to fail.");
end

function localMissingPDCCHBindingEvidenceFails()
ctx = llsRootGateFixture("honest_study");
scfg = sixgr.util.structSet(ctx.ScenarioConfig, "control_gating.pdcch_required", true);
cfg = sixgr.util.structSet(ctx.InternalConfig, "control_gating.pdcch_required", true);
delete(fullfile(ctx.Layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"));
delete(fullfile(ctx.Layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"));

verdict = sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, scfg, cfg);

statusT = readtable(fullfile(ctx.Layout.ReportCSVDir, "result_status_summary.csv"), ...
    "VariableNamingRule", "preserve");
bindingT = readtable(fullfile(ctx.Layout.ReportCSVDir, "pdcch_grant_binding_evidence.csv"), ...
    "VariableNamingRule", "preserve");
assert(height(bindingT) == 0, "Fixture must contain no PDCCH binding evidence for this guard.");
assert(~logical(statusT.PDCCHGrantBindingOk(1)), ...
    "Required PDCCH binding must fail when zero grants carry binding evidence.");
assert(any(contains(string(verdict.Failures), "missing_required_grant_binding_evidence")), ...
    "The empty-evidence failure must identify missing required PDCCH binding evidence.");
end

function localMissingKPIBindingEvidenceFails()
ctx = llsRootGateFixture("honest_study");
bindingPath = fullfile(ctx.Layout.ReportCSVDir, "kpi_objective_binding.csv");
delete(bindingPath);

sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);

statusT = readtable(fullfile(ctx.Layout.ReportCSVDir, "result_status_summary.csv"), ...
    "VariableNamingRule", "preserve");
gateT = readtable(fullfile(ctx.Layout.ReportCSVDir, "kpi_consistency_gate.csv"), ...
    "VariableNamingRule", "preserve");
assert(~logical(statusT.KpiConsistencyOk(1)), ...
    "Strict KPI consistency must fail when objective-binding evidence is absent.");
assert(any(string(gateT.GateName) == "kpi_objective_binding_present" & ~logical(gateT.Pass)), ...
    "KPI gate must report the missing objective-binding artifact.");
assert(any(string(gateT.GateName) == "kpi_objective_binding_mandatory_rows" & ~logical(gateT.Pass)), ...
    "KPI gate must report the four missing mandatory objective rows.");
end
