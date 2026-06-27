function ok = testCanonicalGeometryEngine()
%TESTCANONICALGEOMETRYENGINE Verify distance, delay, Doppler, and pathloss share one state.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.seed = 121;
cfg.run.strictMode = false;
cfg.phy.fc_Hz = 4e9;
cfg.channel.model = "TR38901";
cfg.channel.propagationScenario = "UMa";
cfg.channel.pathlossModel = "nrPathLoss";
cfg.channel.pathloss.model = "nrPathLoss";
cfg.channel.pathlossEnabled = true;
cfg.channel.shadowFadingEnabled = false;
cfg.channel.shadowSigma_dB = 0;
cfg.channel.losEnabled = true;
cfg.channel.o2i.model = "none";
cfg.channel.o2i.indoorDistance_m = 0;
cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);

layout = struct();
layout.bs = struct();
layout.bs.pos_m = [0 0 25];
layout.bs.txPower_dBm = 43;
layout.bs.siteId = 1;
layout.bs.sectorId = 1;
layout.bs.azim_deg = 0;
layout.wraparoundEnabled = false;
layout.wraparoundMode = "disabled";
layout.area_m = [1000 1000];
layout.isd_m = NaN;

ue = struct();
ue.K = 1;
ue.id = 1;
ue.pos_m = [300 400 1.5];
ue.indoor = false;
ue.speed_kmh = 100;
ue.heading_deg = 0;

plModel = sixgr.channel.TR38901Plus(cfg, "Scenario", "UMa", "Seed", 5001);
state = sixgr.system.buildLargeScaleStateCache(cfg, layout, ue, 1, 0, plModel, "NumRB", 24);

c = sixgr.system.GeometryEngine.lightSpeed();
expectedD2D = 500;
expectedD3D = sqrt(300^2 + 400^2 + (1.5 - 25)^2);
expectedDelay = expectedD3D / c;
ueVel = [100/3.6 0 0];
unitTxToRx = [300 400 (1.5 - 25)] ./ expectedD3D;
expectedRadial = sum(ueVel .* unitTxToRx);
expectedDoppler = expectedRadial / c * 4e9;

assert(abs(double(state.d2d_m) - expectedD2D) < 1e-12, "2D distance must come from canonical positions.");
assert(abs(double(state.d3d_m) - expectedD3D) < 1e-12, "3D distance must come from canonical positions.");
assert(abs(double(state.PropagationDelay_s) - expectedDelay) < 1e-15, "Propagation delay must equal d/c.");
assert(abs(double(state.RadialVelocity_mps) - expectedRadial) < 1e-12, "Radial velocity must be the relative velocity projection.");
assert(abs(double(state.SignedDoppler_Hz) - expectedDoppler) < 0.1, "Doppler must equal radial_velocity/c*fc within 0.1 Hz.");
assert(abs(double(state.Pathloss_dB) - double(state.BasePathloss_dB)) < 1e-9, "With shadow and O2I disabled, pathloss must equal base pathloss exactly.");
assert(isfinite(double(state.RxPower_dBm)) && abs(double(state.RxPower_dBm) - (43 - double(state.Pathloss_dB))) < 1e-9, "Large-scale gain must be applied once in the Rx power ledger.");

stateReuse = sixgr.system.buildLargeScaleStateCache(cfg, layout, ue, 1, 0, plModel, ...
    "NumRB", 24, "PreviousState", state, "ReusePropagation", true);
assert(abs(double(stateReuse.PropagationDelay_s) - expectedDelay) < 1e-15, "Reused propagation keeps canonical delay finite.");
assert(abs(double(stateReuse.Pathloss_dB) - double(state.Pathloss_dB)) < 1e-12, "Reused propagation preserves pathloss exactly.");

ok = true;
end
