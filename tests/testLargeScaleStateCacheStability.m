function ok = testLargeScaleStateCacheStability()
%TESTLARGESCALESTATECACHESTABILITY Keep large-scale propagation state stable across slots.

setup6GRSimToolkit("Verbose", false);

cfg = localBaseCfg(23);
layout = sixgr.scenario.generateLayout(cfg);
ue = sixgr.scenario.dropUEs(cfg, layout);
K = size(ue.pos_m, 1);
nCells = size(layout.bs.pos_m, 1);
beamIdx = ones(K, nCells);
beamGain_dB = zeros(K, nCells);
nRB = 24;

plModel = sixgr.channel.TR38901Plus(cfg, "Seed", double(cfg.run.seed) + 17);
state1 = sixgr.system.buildLargeScaleStateCache(cfg, layout, ue, beamIdx, beamGain_dB, plModel, ...
    "NumRB", nRB);
state2 = sixgr.system.buildLargeScaleStateCache(cfg, layout, ue, beamIdx, beamGain_dB, plModel, ...
    "NumRB", nRB, ...
    "PreviousState", state1, ...
    "ReusePropagation", true);

assert(isequal(state1.LOS, state2.LOS), ...
    "Reused large-scale cache must preserve the LOS mask exactly.");
assert(localMaxAbsDiff(state1.Shadow_dB, state2.Shadow_dB) < 1e-12, ...
    "Reused large-scale cache must preserve shadow fading exactly.");
assert(localMaxAbsDiff(state1.Pathloss_dB, state2.Pathloss_dB) < 1e-12, ...
    "Reused large-scale cache must preserve pathloss exactly.");
assert(localMaxAbsDiff(state1.RSRP_dBm, state2.RSRP_dBm) < 1e-12, ...
    "Reused large-scale cache must preserve RSRP exactly.");

% Mobility must refresh deterministic geometry without independently
% redrawing the same-drop LOS, shadowing, or O2I realization. This shared
% cache invariant applies identically to FDD and TDD runtimes.
ueMoved = ue;
ueMoved.pos_m(:, 1) = ueMoved.pos_m(:, 1) + 1e-3;
stateMoved = sixgr.system.buildLargeScaleStateCache(cfg, layout, ueMoved, beamIdx, beamGain_dB, plModel, ...
    "NumRB", nRB, "PreviousState", state1, "ReusePropagation", false);
assert(isequal(state1.LOS, stateMoved.LOS), ...
    "A millimetre-scale mobility update must not redraw LOS/NLOS state.");
assert(localMaxAbsDiff(state1.Shadow_dB, stateMoved.Shadow_dB) < 1e-12, ...
    "A same-drop mobility update must preserve its shadow-fading realization.");
assert(localMaxAbsDiff(state1.O2I_dB, stateMoved.O2I_dB) < 1e-12, ...
    "A same-drop mobility update must preserve its O2I realization.");
assert(logical(stateMoved.RandomComponentsPreserved), ...
    "The cache must disclose that random large-scale components were preserved.");
assert(localMaxAbsDiff(state1.d2d_m, stateMoved.d2d_m) > 0, ...
    "Mobility must still update deterministic geometry while preserving random LSP state.");

cfgOff = localBaseCfg(23);
cfgOff.channel.pathlossEnabled = false;
cfgOff.channel.shadowFadingEnabled = false;
cfgOff.channel.losEnabled = false;
cfgOff = sixgr.config.normalizeConfig(cfgOff);
sixgr.config.validateConfig(cfgOff);
plOff = sixgr.channel.TR38901Plus(cfgOff, "Seed", double(cfgOff.run.seed) + 17);
stateOff = sixgr.system.buildLargeScaleStateCache(cfgOff, layout, ue, beamIdx, beamGain_dB, plOff, ...
    "NumRB", nRB);

assert(~any(stateOff.LOS(:)), ...
    "Disabling LOS logic must stop LOS sampling in the shared large-scale cache.");
assert(all(abs(stateOff.Shadow_dB(:)) < 1e-12), ...
    "Disabling shadow fading must zero shadow contribution in the shared cache.");
assert(all(abs(stateOff.Pathloss_dB(:)) < 1e-12), ...
    "Disabling pathloss must stop pathloss contribution in the shared cache.");
expectedRxPower = stateOff.TxPower_dBm + stateOff.BeamGain_dB;
assert(localMaxAbsDiff(stateOff.RxPower_dBm, expectedRxPower) < 1e-12, ...
    "With pathloss disabled, Rx power must reduce to transmit power plus beam gain only.");

cfgRun = localBaseCfg(31);
cfgRun = withCanonicalSchedulerTiming(cfgRun);
ctx = sixgr.core.SimContext(cfgRun);
numTTI = 12;
offeredDL = repmat(4000, numTTI, cfgRun.scenario.ue.nUE);
offeredUL = repmat(2000, numTTI, cfgRun.scenario.ue.nUE);
res = sixgr.system.SystemLevelRunner.run(ctx, struct( ...
    "NumTTI", numTTI, ...
    "TTI_s", 0.5, ...
    "OfferedBitsDL", offeredDL, ...
    "OfferedBitsUL", offeredUL));

assert(res.Ok, "SystemLevelRunner failed in large-scale state stability regression.");
D = res.Details;
assert(sum(double(D.GrantCountDL)) > 0 && sum(double(D.GrantCountUL)) > 0, ...
    "The stability regression must exercise real DL and UL scheduled grants; " + ...
    "a timing-rejected zero-grant run is not valid evidence.");
assert(nnz(logical(D.LargeScalePropagationUpdateMask)) == 1, ...
    "With mobility disabled and no explicit large-scale refresh, propagation state should update once only.");
assert(all(isfinite(D.Pathloss_dB(:))), "Pathloss history must remain finite.");
assert(all(isfinite(D.RSRP_dBm(:))), "RSRP history must remain finite.");
assert(localMaxAbsDiff(D.Pathloss_dB, repmat(D.Pathloss_dB(1,:), numTTI, 1)) < 1e-12, ...
    "Pathloss must remain exactly stable across slots when geometry does not change.");
assert(localMaxAbsDiff(D.RSRP_dBm, repmat(D.RSRP_dBm(1,:), numTTI, 1)) < 1e-12, ...
    "Serving-link RSRP must remain exactly stable across slots when geometry does not change.");
traceRef = repmat(D.MeasurementRSRPTrace_dBm(1,:,:), [numTTI 1 1]);
assert(localMaxAbsDiff(D.MeasurementRSRPTrace_dBm, traceRef) < 1e-12, ...
    "Measurement RSRP trace must remain exactly stable across slots when geometry does not change.");

ok = true;
end

function cfg = localBaseCfg(seed)
cfg = sixgr.config.defaultConfig();
cfg.run.seed = double(seed);
cfg.run.shortRun = false;
cfg.run.strictMode = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.outputs.savePNG = false;
cfg.scenario.layout.nSites = 1;
cfg.scenario.layout.nSectorsPerSite = 1;
cfg.scenario.layout.wrapAround = false;
cfg.scenario.nUE = 1;
cfg.scenario.ue.nUE = 1;
cfg.scenario.bs.nTxAnt = 1;
cfg.scenario.bs.nRxAnt = 1;
cfg.scenario.ue.nTxAnt = 1;
cfg.scenario.ue.nRxAnt = 1;
cfg.scenario.mobility.enable = false;
cfg.system.beam.enable = false;
cfg.system.handover.enable = false;
cfg.system.phyBackend = "waveform";
cfg.system.measurement.periodSlots = 1;
cfg.phy.pdcch.symbolAllocation = [0 2];
cfg.phy.pdcch.SymbolAllocation = [0 2];
cfg.channel.pathloss.model = "nrPathLoss";
cfg.channel.pathlossModel = "nrPathLoss";
cfg.channel.pathlossEnabled = true;
cfg.channel.shadowFadingEnabled = true;
cfg.channel.losEnabled = true;
cfg.channel.shadowSigma_dB = 7;
cfg.channel.shadowFadingStd_dB = 7;
cfg.channel.awgnOnly = true;
cfg.channel.model = "AWGN";
cfg.channel.fading.enable = false;
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 0.35;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.symbolAllocation = [2 12];
cfg.phy.pdsch.mappingType = "A";
cfg.phy.pdsch.dmrs.portSet = 0;
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.codeRate = 0.35;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.nLayers = 1;
cfg.phy.pusch.symbolAllocation = [2 12];
cfg.phy.pusch.mappingType = "A";
cfg.phy.pusch.dmrs.portSet = 0;
cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);
end

function d = localMaxAbsDiff(a, b)
d = max(abs(double(a(:)) - double(b(:))));
if isempty(d)
    d = 0;
end
end
