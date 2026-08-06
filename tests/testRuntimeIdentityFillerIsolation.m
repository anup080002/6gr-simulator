function ok = testRuntimeIdentityFillerIsolation()
%TESTRUNTIMEIDENTITYFILLERISOLATION Identity blanks are never decorated.

T = table([""; "run-2"], [""; "scenario-2"], [""; "abc123"], ...
    [""; "runtime"], [""; "available"], ...
    'VariableNames', {'RunID', 'ScenarioID', 'ConfigHash', 'MetricSource', 'ValueStatus'});
filled = sixgr.truth.fillBlankCategoricalColumns(T, "pdcch_measurement");
assert(filled.RunID(1) == "" && filled.ScenarioID(1) == "" && ...
    filled.ConfigHash(1) == "", ...
    "Immutable identity blanks must remain visible to fail-closed validation.");
assert(contains(filled.MetricSource(1), "not_emitted_by_active_pdcch_measurement_runtime"));
assert(contains(filled.ValueStatus(1), "not_emitted_by_active_pdcch_measurement_runtime"));
assert(filled.RunID(2) == "run-2" && filled.ScenarioID(2) == "scenario-2");
assert(sixgr.truth.isImmutableIdentityField("SourceArtifactSHA256"));
assert(~sixgr.truth.isImmutableIdentityField("MetricSource"));

canonical = sixgr.truth.canonicalizeLLSLiveSignalChainTable( ...
    "ul_pusch_trials", T);
assert(canonical.RunID(1) == "" && canonical.ScenarioID(1) == "" && ...
    canonical.ConfigHash(1) == "", ...
    "Signal-chain canonicalization must not fabricate immutable identity.");

ok = true;
fprintf("PASS testRuntimeIdentityFillerIsolation: identity provenance is no longer fabricated.\n");
end
