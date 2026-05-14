function ok = testFeatureParameterFiltering()
%TESTFEATUREPARAMETERFILTERING Ensure feature filtering keeps PRACH isolated.

setup6GRSimToolkit("Verbose", false);

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempdir, "sixgr_feature_filter_smoke"));

bindingT = sixgr.config.buildParameterBindingMatrix(scfg, cfg, struct());
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
