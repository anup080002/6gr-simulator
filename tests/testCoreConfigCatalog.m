function ok = testCoreConfigCatalog()
%TESTCORECONFIGCATALOG Core non-6G config defaults and policy must come from YAML catalog.

setup6GRSimToolkit("Verbose", false);

catalog = sixgr.config.loadCoreCatalog();
assert(isstruct(catalog) && isfield(catalog, "parameters"), ...
    "Core config catalog must load and expose a parameters section.");

cfg = sixgr.config.defaultConfig();
assert(strcmpi(char(string(cfg.run.mode)), ...
    char(string(catalog.parameters.run.mode.default))), ...
    "defaultConfig.run.mode must come from the YAML catalog.");
assert(strcmpi(char(string(cfg.scenario.mobility.model)), ...
    char(string(catalog.parameters.scenario.mobility.model.default))), ...
    "defaultConfig.scenario.mobility.model must come from the YAML catalog.");
assert(strcmpi(char(string(cfg.system.phyBackend)), ...
    char(string(catalog.parameters.system.phyBackend.default))), ...
    "defaultConfig.system.phyBackend must come from the YAML catalog.");
assert(isequal(cfg.outputs.kpi.list, cellstr(string(catalog.parameters.outputs.kpi.list.default(:).'))), ...
    "defaultConfig.outputs.kpi.list must come from the YAML catalog.");

cfgBadMobility = sixgr.config.defaultConfig();
cfgBadMobility.scenario.mobility.model = "teleport";
cfgBadMobility = sixgr.config.normalizeConfig(cfgBadMobility);
threwBadMobility = false;
try
    sixgr.config.validateConfig(cfgBadMobility);
catch ME
    threwBadMobility = strcmp(ME.identifier, 'sixgr:config:BadEnum');
    assert(contains(string(ME.message), "scenario.mobility.model"), ...
        "Catalog-driven enum failures should identify the bad field.");
end
assert(threwBadMobility, ...
    "Core catalog validation must reject unsupported scenario.mobility.model values.");

cfgAlias = sixgr.config.loadConfig(struct("scenario", struct("name", "uma")));
assert(strcmpi(char(string(cfgAlias.run.preset)), "UMa_FR1"), ...
    "Scenario-to-preset alias mapping should come from the YAML catalog.");

ok = true;
end
