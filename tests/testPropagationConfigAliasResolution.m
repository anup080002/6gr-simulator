function ok = testPropagationConfigAliasResolution()
%TESTPROPAGATIONCONFIGALIASRESOLUTION Keep layout/profile and propagation semantics aligned.

setup6GRSimToolkit("Verbose", false);

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "dl_4ghz_baseline.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempdir, "propagation_alias_probe"));

assert(strcmpi(string(sixgr.util.structGet(cfg, "scenario.id", "")), "dl_4ghz_baseline"), ...
    "Scenario identifier must remain available separately from scenario.profileName.");
assert(strcmpi(string(sixgr.util.structGet(cfg, "scenario.profileName", "")), "InH"), ...
    "Scenario profile name must resolve from deployment_topology.cell_type.");
assert(strcmpi(string(sixgr.util.structGet(cfg, "scenario.name", "")), "InH"), ...
    "scenario.name must mirror the resolved layout/profile selector.");
assert(strcmpi(string(sixgr.util.structGet(cfg, "channel.propagationScenario", "")), "InH"), ...
    "channel.propagationScenario must resolve from deployment_topology.cell_type.");
assert(strcmpi(string(sixgr.util.structGet(cfg, "run.scenario", "")), "InH"), ...
    "Legacy run.scenario must mirror the canonical propagation scenario.");
assert(logical(sixgr.util.structGet(cfg, "channel.pathlossEnabled", false)) == logical(scfg.get("channels.pathloss_enabled")), ...
    "channel.pathlossEnabled must survive normalization.");
assert(logical(sixgr.util.structGet(cfg, "channel.shadowFadingEnabled", false)) == logical(scfg.get("channels.shadow_fading_enabled")), ...
    "channel.shadowFadingEnabled must survive normalization.");
assert(logical(sixgr.util.structGet(cfg, "channel.losEnabled", false)) == logical(scfg.get("channels.los_enabled")), ...
    "channel.losEnabled must survive normalization.");

prof = sixgr.scenario.ScenarioFactory.getProfile(cfg);
assert(strcmpi(string(prof.name), "InH"), ...
    "ScenarioFactory must use scenario.profileName rather than an arbitrary scenario ID.");

pl = sixgr.channel.TR38901Plus(cfg);
rt = sixgr.channel.RayTracingAdapter(cfg);
assert(strcmpi(string(pl.Scenario), "InH"), ...
    "TR38901Plus must resolve the canonical propagation scenario.");
assert(strcmpi(string(rt.Scenario), "InH"), ...
    "RayTracingAdapter must resolve the canonical propagation scenario.");

aliasCfg = sixgr.config.defaultConfig();
aliasCfg = sixgr.util.structSet(aliasCfg, "scenario.name", "RMa");
aliasCfg = sixgr.util.structSet(aliasCfg, "channel.fc_Hz", 9e8);
aliasCfg = sixgr.util.structSet(aliasCfg, "channel.pathloss.model", "nrPathLoss");
aliasCfg = sixgr.util.structSet(aliasCfg, "channel.shadowFadingStd_dB", 8);
aliasCfg = sixgr.config.normalizeConfig(aliasCfg);
assert(strcmpi(string(sixgr.util.structGet(aliasCfg, "scenario.profileName", "")), "RMa"), ...
    "normalizeConfig must bridge legacy scenario.name into scenario.profileName.");
assert(strcmpi(string(sixgr.util.structGet(aliasCfg, "channel.propagationScenario", "")), "RMa"), ...
    "normalizeConfig must bridge legacy scenario.name into channel.propagationScenario.");
assert(abs(double(sixgr.util.structGet(aliasCfg, "phy.fc_Hz", NaN)) - 9e8) < 1e-9, ...
    "normalizeConfig must bridge channel.fc_Hz into phy.fc_Hz.");
assert(strcmpi(string(sixgr.util.structGet(aliasCfg, "channel.pathlossModel", "")), "nrPathLoss"), ...
    "normalizeConfig must bridge channel.pathloss.model into channel.pathlossModel.");
assert(double(sixgr.util.structGet(aliasCfg, "channel.shadowSigma_dB", NaN)) == 8, ...
    "normalizeConfig must bridge channel.shadowFadingStd_dB into channel.shadowSigma_dB.");

ok = true;
end
