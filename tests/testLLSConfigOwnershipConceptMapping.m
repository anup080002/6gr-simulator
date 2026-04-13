function ok = testLLSConfigOwnershipConceptMapping()
%TESTLLSCONFIGOWNERSHIPCONCEPTMAPPING Guard against concept-mapping drift in ownership exports.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));

artifacts = sixgr.truth.exportLLSConfigOwnershipArtifacts(fullfile(tmp, "run"), scfg, cfg);
dictT = localReadVerificationCSV(char(artifacts.RuntimeValueSourceDictionary));
matrixT = localReadVerificationCSV(char(artifacts.ConfigOwnershipMatrix));

mobilityCfg = localSingleRow(matrixT, "ParameterName", "mobility.ue_speed_kmh");
assert(strcmp(string(mobilityCfg.ResolvedRuntimeValue), "30"), ...
    "mobility.ue_speed_kmh must stay mapped to the configured speed value.");

mobilityDict = localSingleRow(dictT, "FieldName", "MobilitySpeed_kmh");
assert(strcmp(string(mobilityDict.ValueSource), "resolved_scenario_mobility_speed"), ...
    "MobilitySpeed_kmh must keep a speed-specific value source.");
assert(strcmp(string(mobilityDict.ValueRole), "configured"), ...
    "MobilitySpeed_kmh must remain classified as configured.");
assert(contains(lower(string(mobilityDict.ValueDefinition)), "speed"), ...
    "MobilitySpeed_kmh definition must explicitly describe speed semantics.");

dopplerDict = localSingleRow(dictT, "FieldName", "ResolvedDopplerHz");
assert(strcmp(string(dopplerDict.ValueSource), "carrier_frequency_and_mobility_speed_derivation"), ...
    "ResolvedDopplerHz must keep a derivation-specific value source.");
assert(strcmp(string(dopplerDict.ValueRole), "derived"), ...
    "ResolvedDopplerHz must remain classified as derived.");
assert(contains(lower(string(dopplerDict.ValueDefinition)), "doppler"), ...
    "ResolvedDopplerHz definition must explicitly describe Doppler semantics.");
assert(~strcmpi(string(mobilityDict.ValueSource), string(dopplerDict.ValueSource)), ...
    "Speed and Doppler must never share the same value-source mapping.");

cqiCfg = localSingleRow(matrixT, "ParameterName", "link_adaptation.cqi_table");
assert(strcmp(string(cqiCfg.ResolvedRuntimeValue), "table1"), ...
    "link_adaptation.cqi_table must stay mapped to the configured CQI-table token.");

cqiPolicyCfg = localSingleRow(matrixT, "ParameterName", "csi_acquisition_and_reporting.cqi_policy");
assert(strcmp(string(cqiPolicyCfg.ResolvedRuntimeValue), "baseline"), ...
    "csi_acquisition_and_reporting.cqi_policy must stay mapped to the configured policy token, not the derived reportCQI boolean.");

pmiPolicyCfg = localSingleRow(matrixT, "ParameterName", "csi_acquisition_and_reporting.pmi_policy");
assert(strcmp(string(pmiPolicyCfg.ResolvedRuntimeValue), "baseline"), ...
    "csi_acquisition_and_reporting.pmi_policy must stay mapped to the configured policy token, not the derived reportPMI boolean.");

layoutCfg = localSingleRow(matrixT, "ParameterName", "deployment_topology.layout_type");
assert(strcmp(string(layoutCfg.ResolvedRuntimeValue), "hex_grid"), ...
    "deployment_topology.layout_type must stay mapped to the resolved layout token, not a topology count.");
assert(contains(string(layoutCfg.CanonicalArtifact), "deployment_layout_reference.csv"), ...
    "deployment_topology.layout_type must use deployment layout reference evidence.");

idealTimingDict = localSingleRow(dictT, "FieldName", "UseIdealTimingSync");
assert(strcmp(string(idealTimingDict.ValueSource), "resolved_receiver_timing_policy"), ...
    "UseIdealTimingSync must keep a receiver-policy-specific value source.");
assert(strcmp(string(idealTimingDict.ValueRole), "resolved"), ...
    "UseIdealTimingSync must remain classified as resolved runtime policy.");
assert(contains(lower(string(idealTimingDict.ValueDefinition)), "timing"), ...
    "UseIdealTimingSync definition must explicitly describe receiver timing semantics.");

ok = true;
end

function row = localSingleRow(T, fieldName, expectedValue)
mask = strcmp(string(T.(fieldName)), string(expectedValue));
assert(nnz(mask) == 1, "Expected exactly one row where %s == %s.", fieldName, expectedValue);
row = T(find(mask, 1, "first"), :);
end

function T = localReadVerificationCSV(filePath)
opts = detectImportOptions(filePath, "Delimiter", ",");
opts.VariableNamingRule = "preserve";
opts = setvartype(opts, opts.VariableNames, "string");
T = readtable(filePath, opts);
end
