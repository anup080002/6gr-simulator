function ok = testScenarioGeometryModes()
%TESTSCENARIOGEOMETRYMODES Guard explicit wrap-around and UE drop modes.

setup6GRSimToolkit("Verbose", false);

isd = 500;
uePos = [0 0 1.5];
bsPos = [1.5 * isd, (sqrt(3) / 2) * isd, 25];
area_m = [3 * isd, sqrt(3) * isd];

dRect = sixgr.scenario.wraparoundDistance(uePos, bsPos, area_m, "Mode", "rectangular_torus");
dHex = sixgr.scenario.wraparoundDistance(uePos, bsPos, area_m, "Mode", "hex_lattice_min_image", "ISD_m", isd);
assert(dRect > 1, ...
    "Legacy rectangular torus should not collapse arbitrary hex-lattice translations to zero.");
assert(dHex < 1e-9, ...
    "Hex wrap-around must use the nearest hex-lattice image.");

cfgLegacy = localBaseCfg(41);
cfgLegacy.scenario.layout.nSites = 2;
cfgLegacy.scenario.layout.nSectorsPerSite = 1;
cfgLegacy.scenario.geometry.wraparound = false;
cfgLegacy.scenario.ue.nUE = 21;
cfgLegacy.scenario.ue.dropMode = "legacy_equal_sector_drop";
cfgLegacy = sixgr.config.normalizeConfig(cfgLegacy);
sixgr.config.validateConfig(cfgLegacy);

layoutLegacy = sixgr.scenario.generateLayout(cfgLegacy);
ueLegacy = sixgr.scenario.dropUEs(cfgLegacy, layoutLegacy);
legacyCounts = accumarray(double(ueLegacy.drop_cell_id), 1, [size(layoutLegacy.bs.pos_m,1) 1]);
assert(max(legacyCounts) - min(legacyCounts) <= 1, ...
    "Legacy UE drop mode must retain the old nearly equal sector balancing behavior.");

cfgPathloss = cfgLegacy;
cfgPathloss.scenario.ue.dropMode = "pathloss_based_association_drop";
cfgPathloss = sixgr.config.normalizeConfig(cfgPathloss);
sixgr.config.validateConfig(cfgPathloss);

layoutPathloss = sixgr.scenario.generateLayout(cfgPathloss);
uePathloss = sixgr.scenario.dropUEs(cfgPathloss, layoutPathloss);
dx = uePathloss.pos_m(:,1) - layoutPathloss.bs.pos_m(:,1).';
dy = uePathloss.pos_m(:,2) - layoutPathloss.bs.pos_m(:,2).';
[~, nearestCell] = min(sqrt(dx.^2 + dy.^2), [], 2);
assert(isequal(double(uePathloss.drop_cell_id), double(nearestCell)), ...
    "Pathloss-based UE drop mode must assign the post-placement nearest serving reference cell.");
assert(all(string(uePathloss.serving_selection_method) == "nearest_cell_distance_after_uniform_area_drop"), ...
    "Pathloss-based UE drop mode must label the serving-cell selection method explicitly.");

ok = true;
end

function cfg = localBaseCfg(seed)
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = false;
cfg.run.strictMode = true;
cfg.run.seed = double(seed);
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.scenario.profileName = "UMa";
cfg.scenario.name = "UMa";
cfg.channel.propagationScenario = "UMa";
cfg.run.scenario = "UMa";
cfg.scenario.mobility.enable = false;
cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);
end
