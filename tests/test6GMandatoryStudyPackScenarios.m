function ok = test6GMandatoryStudyPackScenarios()
%TEST6GMANDATORYSTUDYPACKSCENARIOS Validate shipped mandatory 6G study-pack scenarios.

setup6GRSimToolkit("Verbose", false);

scenarioFiles = [ ...
    "mandatory_general_scope_packs.yaml"
    "mandatory_tracking_packs.yaml"
    "mandatory_ul_waveform_packs.yaml"
    "mandatory_csi_acquisition_packs.yaml"
    "mandatory_pdcch_packs.yaml"
    "mandatory_initial_access_packs.yaml"
    "mandatory_harq_packs.yaml"
    "mandatory_coding_modulation_packs.yaml"
    "mandatory_ai_ml_packs.yaml"
    "mandatory_energy_efficiency_packs.yaml"];

for i = 1:numel(scenarioFiles)
    scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", scenarioFiles(i));
    assert(exist(scenarioPath, "file") == 2, "Missing mandatory scenario pack %s.", scenarioFiles(i));
    scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
    assert(strcmpi(string(scfg.get("scenario.runner_profile")), "generic_sweep"), ...
        "Mandatory scenario pack %s must use generic_sweep.", scenarioFiles(i));
    assert(strlength(string(scfg.get("meta.research_class", ""))) > 0, ...
        "Mandatory scenario pack %s must carry a research_class.", scenarioFiles(i));

    raw = sixgr.lls6g.config.readConfigFile(scenarioPath);
    overrides = sixgr.util.structGet(raw, "scenario.sweep.overrides", struct([]));
    assert(~isempty(overrides), "Mandatory scenario pack %s must include sweep overrides.", scenarioFiles(i));
    for k = 1:numel(overrides)
        merged = sixgr.util.mergeStruct(scfg.toStruct(), sixgr.util.structGet(overrides(k), "config", struct()));
        sixgr.lls6g.config.validateScenarioConfig(merged, ...
            "Kind", "scenario", "AllowPartial", false, ...
            "Context", string(scenarioFiles(i)) + "::" + string(sixgr.util.structGet(overrides(k), "label", "case")));
    end
end

generalPath = fullfile(pwd, "simulator", "configs", "scenarios", "mandatory_general_scope_packs.yaml");
generalRaw = sixgr.lls6g.config.readConfigFile(generalPath);
labels = strings(0,1);
for i = 1:numel(generalRaw.scenario.sweep.overrides)
    labels(end+1,1) = string(generalRaw.scenario.sweep.overrides(i).label); %#ok<AGROW>
end
assert(any(labels == "custom_10_5ghz"), "Mandatory general-scope pack must include an arbitrary custom carrier override.");

base = sixgr.lls6g.config.loadScenarioConfig(generalPath).toStruct();
customOverride = generalRaw.scenario.sweep.overrides(find(labels == "custom_10_5ghz", 1)).config;
customCfg = sixgr.util.mergeStruct(base, customOverride);
assert(strcmpi(string(customCfg.frequency.band_name), "custom_10_5ghz"), "Custom carrier band_name should remain config-driven.");
assert(abs(double(customCfg.frequency.center_frequency_hz) - 10.5e9) < 1, ...
    "Custom carrier center frequency should remain config-driven.");

ok = true;
end
