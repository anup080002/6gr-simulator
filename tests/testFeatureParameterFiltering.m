function ok = testFeatureParameterFiltering()
%TESTFEATUREPARAMETERFILTERING Ensure feature filtering keeps PRACH isolated.

setup6GRSimToolkit("Verbose", false);

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempdir, "sixgr_feature_filter_smoke"));

bindingT = sixgr.config.buildParameterBindingMatrix(scfg, cfg, struct());
assert(any(strcmp(string(bindingT.Properties.VariableNames), "RuntimeObservedValue")), ...
    "Parameter binding matrix must expose RuntimeObservedValue for config-to-runtime traceability.");
assert(all(strlength(strtrim(string(bindingT.RuntimeObservedValue))) == 0 | ismissing(string(bindingT.RuntimeObservedValue))), ...
    "Config-only binding matrix must not fabricate runtime-observed values.");

applicationEvidence = table("frequency.center_frequency_hz", "4000000000", ...
    'VariableNames', {'ParameterId','AppliedValue'});
appliedBindingT = sixgr.config.buildParameterBindingMatrix(scfg, cfg, struct("ApplicationEvidence", applicationEvidence));
appliedMask = strcmp(string(appliedBindingT.ParameterId), "frequency.center_frequency_hz");
assert(nnz(appliedMask) == 1, "Applied-evidence binding must include frequency.center_frequency_hz exactly once.");
assert(strcmp(string(appliedBindingT.RuntimeObservedValue(appliedMask)), "4000000000"), ...
    "RuntimeObservedValue must use direct runtime-applied evidence when it exists.");

tmpRun = tempname;
mkdir(fullfile(tmpRun, "reports", "csv"));
c = onCleanup(@() rmdir(tmpRun, "s")); %#ok<NASGU>
measuredT = table(42, 'VariableNames', {'RuntimeValue'});
sixgr.util.csvWriteTable(fullfile(tmpRun, "reports", "csv", "runtime_probe.csv"), measuredT);
registryHint = struct( ...
    "ParameterId", "unit_test.runtime_probe", ...
    "MeasuredArtifact", "reports/csv/runtime_probe.csv", ...
    "MeasuredField", "RuntimeValue", ...
    "FeatureFamily", "Unit_Test", ...
    "UILayer", "Test", ...
    "UISection", "Runtime_Probe", ...
    "BrowserVisible", true, ...
    "BrowserEditable", true);
measuredBindingT = sixgr.config.buildParameterBindingMatrix( ...
    struct("unit_test", struct("runtime_probe", true)), struct(), ...
    struct("RunFolder", tmpRun, "RegistryHints", registryHint));
measuredMask = strcmp(string(measuredBindingT.ParameterId), "unit_test.runtime_probe");
assert(nnz(measuredMask) == 1, "Measured-evidence binding must include the runtime probe exactly once.");
assert(strcmp(string(measuredBindingT.RuntimeObservedValue(measuredMask)), "42"), ...
    "RuntimeObservedValue must fall back to measured runtime evidence when no applied evidence exists.");

auditT = sixgr.config.filterParametersForFeature(bindingT, "Random_Access_PRACH", struct("IncludeExcluded", true));

maskCfgIdx = strcmp(string(auditT.ParameterId), "random_access.configuration_index");
assert(any(maskCfgIdx), "PRACH filter audit must include random_access.configuration_index.");
assert(any(maskCfgIdx & strcmp(string(auditT.SelectionBucket), "feature_parameter")), ...
    "random_access.configuration_index must be selected as a PRACH-owned parameter.");

maskShared = strcmp(string(auditT.ParameterId), "frequency.center_frequency_hz");
assert(any(maskShared & strcmp(string(auditT.SelectionBucket), "shared_dependency")), ...
    "frequency.center_frequency_hz must be retained as a shared PRACH dependency.");

maskPusch = strcmp(string(auditT.ParameterId), "waveform.transform_precoding_enabled");
if any(maskPusch)
    assert(all(strcmp(string(auditT.SelectionBucket(maskPusch)), "excluded")), ...
        "PRACH filter must exclude unrelated UL-data waveform knobs.");
end

maskPdcch = strcmp(string(auditT.ParameterId), "control.pdcch_enabled");
if any(maskPdcch)
    assert(all(strcmp(string(auditT.SelectionBucket(maskPdcch)), "excluded")), ...
        "PRACH filter must exclude unrelated PDCCH knobs.");
end

ok = true;
end
