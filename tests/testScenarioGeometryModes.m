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
dHexTwoRing = sixgr.scenario.wraparoundDistance([0 0 1.5], [2 * isd 0 25], area_m, ...
    "Mode", "hex_lattice_min_image", "ISD_m", isd);
assert(dHexTwoRing < 1e-9, ...
    "Hex wrap-around must search beyond the immediate one-ring image set.");

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

cfgArea = cfgLegacy;
cfgArea.scenario.layout.nSites = 1;
cfgArea.scenario.layout.nSectorsPerSite = 1;
cfgArea.scenario.ue.nUE = 2000;
cfgArea = sixgr.config.normalizeConfig(cfgArea);
sixgr.config.validateConfig(cfgArea);
layoutArea = sixgr.scenario.generateLayout(cfgArea);
assert(all(abs(double(layoutArea.bs.pos_m(1, 1:2))) < 1e-9), ...
    "A single-site rectangular grid must center the TRP at the local origin.");
ueArea = sixgr.scenario.dropUEs(cfgArea, layoutArea);
center = double(layoutArea.bs.pos_m(1, 1:2));
r = sqrt(sum((double(ueArea.pos_m(:,1:2)) - center).^2, 2));
rMax = double(layoutArea.isd_m) / sqrt(3);
rMin = min(40, max(5, 0.08 * rMax));
expectedMean = (2/3) * ((rMax^3 - rMin^3) / max(rMax^2 - rMin^2, eps));
assert(max(r) > 0.95 * rMax, ...
    "Equal-sector UE drop must exercise the outer hex-cell radius.");
assert(abs(mean(r, "omitnan") - expectedMean) < 0.03 * rMax, ...
    "Equal-sector UE radial drop must follow the uniform-area annulus distribution.");
assert(all(string(ueArea.serving_selection_method) == "equal_sector_uniform_area_annulus_reference"), ...
    "Equal-sector UE drop must label its corrected area-uniform placement method.");

cfgBounded = cfgArea;
cfgBounded.scenario.ue.nUE = 200;
cfgBounded.scenario.ue.distribution.min_bs_dist_m = 20;
cfgBounded.scenario.ue.distribution.max_bs_dist_m = 120;
cfgBounded = sixgr.config.normalizeConfig(cfgBounded);
sixgr.config.validateConfig(cfgBounded);
layoutBounded = sixgr.scenario.generateLayout(cfgBounded);
ueBounded = sixgr.scenario.dropUEs(cfgBounded, layoutBounded);
dBounded = hypot(double(ueBounded.pos_m(:,1)) - double(layoutBounded.bs.pos_m(1,1)), ...
    double(ueBounded.pos_m(:,2)) - double(layoutBounded.bs.pos_m(1,2)));
assert(all(dBounded >= 20 - 1e-9 & dBounded <= 120 + 1e-9), ...
    "Configured min/max UE-to-BS distance bounds must constrain equal-sector UE drops.");

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
