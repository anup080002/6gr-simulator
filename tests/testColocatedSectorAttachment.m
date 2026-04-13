function ok = testColocatedSectorAttachment()
%TESTCOLOCATEDSECTORATTACHMENT Validate sectorized attach on a co-located 3-sector site.

setup6GRSimToolkit("Verbose", false);

seed = 19;
cfg = localBaseCfg(seed);
cfg.scenario.layout.nSites = 1;
cfg.scenario.layout.nSectorsPerSite = 3;
cfg.scenario.sectorization.azimOffsets_deg = [0 120 240];
cfg.scenario.geometry.wraparound = false;
cfg.scenario.ue.nUE = 3;
cfg.system.beam.enable = true;
cfg.system.beam.numBeams = 1;
cfg.system.beam.sectorSpan_deg = 120;
cfg.system.beam.maxGain_dB = 12;
cfg.channel.pathlossEnabled = false;
cfg.channel.shadowFadingEnabled = false;
cfg.channel.losEnabled = false;
cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);

layout = sixgr.scenario.generateLayout(cfg);
assert(size(layout.bs.pos_m, 1) == 3, "Expected one co-located 3-sector site.");
assert(max(abs(layout.bs.pos_m(:,1) - layout.bs.pos_m(1,1))) < 1e-12, ...
    "All sectors must share the same site X position.");
assert(max(abs(layout.bs.pos_m(:,2) - layout.bs.pos_m(1,2))) < 1e-12, ...
    "All sectors must share the same site Y position.");

radius_m = 120;
ueAngles_deg = [0; 120; 240];
ue = struct();
ue.K = 3;
ue.id = (1:3).';
ue.pos_m = [radius_m .* cosd(ueAngles_deg), radius_m .* sind(ueAngles_deg), 1.5 * ones(3,1)];
ue.indoor = false(3,1);
ue.speed_kmh = zeros(3,1);
ue.heading_deg = zeros(3,1);

[beamIdx, beamGain_dB] = sixgr.system.selectBestBeamPerLink( ...
    ue.pos_m, layout.bs.pos_m, layout.bs.azim_deg, ...
    sixgr.util.structGet(cfg, "system.beam.numBeams", 1), ...
    sixgr.util.structGet(cfg, "system.beam.sectorSpan_deg", 120), ...
    sixgr.util.structGet(cfg, "system.beam.maxGain_dB", 12));
plModel = sixgr.channel.TR38901Plus(cfg, "Seed", seed + 17);
state = sixgr.system.buildLargeScaleStateCache(cfg, layout, ue, beamIdx, beamGain_dB, plModel, "NumRB", 1);

d2dRef = repmat(state.d2d_m(:,1), 1, size(state.d2d_m, 2));
assert(max(abs(state.d2d_m(:) - d2dRef(:))) < 1e-12, ...
    "Co-located sectors must present identical site distance to each UE.");

[attachFromRSRP, ~] = sixgr.system.selectServingCellsFromPower(state.RSRP_dBm);
[attachFromRxPower, ~] = sixgr.system.selectServingCellsFromPower(state.RxPower_dBm);
expectedSector = (1:3).';

assert(isequal(attachFromRSRP, expectedSector), ...
    "Cache-based RSRP attach must distinguish co-located sectors by azimuth/beam gain.");
assert(isequal(attachFromRxPower, expectedSector), ...
    "Cache-based Rx power attach must distinguish co-located sectors by azimuth/beam gain.");

[~, strongestBeamSector] = max(state.BeamGain_dB, [], 2);
assert(isequal(strongestBeamSector, expectedSector), ...
    "Beam-gain table must favor the sector aligned with each UE azimuth.");
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
cfg.system.phyBackend = "waveform";
cfg.scenario.profileName = "UMa";
cfg.scenario.name = "UMa";
cfg.channel.propagationScenario = "UMa";
cfg.run.scenario = "UMa";
cfg.scenario.mobility.enable = false;
cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);
end
