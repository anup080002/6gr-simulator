function ok = testMobilityControlLoop()
%TESTMOBILITYCONTROLLOOP Validate closed measurement/beam/handover loop in SLS.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = false;
cfg.run.strictMode = true;
cfg.run.seed = 7;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.mac.scheduler.type = "pf";

% Force mobility and aggressive HO so events happen in regression runtime.
nUE = 24;
numTTI = 96;
cfg.scenario.nUE = nUE;
cfg.scenario.ue.nUE = nUE;
cfg.scenario.mobility.enable = true;
cfg.scenario.mobility.model = "randomWaypoint";
cfg.scenario.mobility.speed_kmh = [90 140];

cfg.system.measurement.periodSlots = 1;
cfg.system.measurement.filterAlpha = 0.5;
cfg.system.beam.enable = true;
cfg.system.beam.updatePeriod_slots = 1;
cfg.system.handover.enable = true;
cfg.system.handover.a3Offset_dB = 0;
cfg.system.handover.hysteresis_dB = 0;
cfg.system.handover.timeToTrigger_slots = 1;
cfg.system.handover.minServingSlots = 0;
cfg.system.handover.preparationSlots = 0;
cfg.system.handover.interruptionSlots = 1;
cfg.system.phyBackend = "waveform";
cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);

ctx = sixgr.core.SimContext(cfg);

offeredDL = repmat(5500, numTTI, nUE);
offeredUL = repmat(3000, numTTI, nUE);
res = sixgr.system.SystemLevelRunner.run(ctx, struct( ...
    "NumTTI", numTTI, ...
    "TTI_s", 0.25, ...
    "OfferedBitsDL", offeredDL, ...
    "OfferedBitsUL", offeredUL));

assert(res.Ok, "SystemLevelRunner failed in mobility-control regression.");
assert(isfield(res, "Details"), "Missing Details output.");
D = res.Details;
assert(isfield(D, "HandoverEvents"), "Missing handover event table.");
assert(isfield(D, "MobilityControlSeries"), "Missing mobility-control time series.");
assert(isfield(D, "ServingCell"), "Missing serving-cell history.");
assert(isfield(D, "ServingBeamIndex"), "Missing serving-beam history.");
assert(istable(D.HandoverEvents), "HandoverEvents must be a table.");
assert(istable(D.MobilityControlSeries), "MobilityControlSeries must be a table.");
assert(height(D.MobilityControlSeries) == numTTI, "MobilityControlSeries row count mismatch.");

% Under this aggressive setup, we expect at least one full HO with interruption.
assert(sum(double(D.HandoverTriggerCount)) > 0, "Expected at least one handover trigger.");
assert(sum(double(D.HandoverCompleteCount)) > 0, "Expected at least one handover completion.");
assert(any(double(D.HandoverInterruptedUECount) > 0), "Expected at least one UE interruption window.");
assert(any(isfinite(double(D.ServingCell(:)))), "Serving-cell history is empty.");

k = res.KPITable(1,:);
assert(double(k.NumCells) >= 2, "Expected multi-cell layout.");
assert(double(k.HO_Completed) > 0, "KPI should report completed handovers.");
assert(strcmpi(char(string(k.ExecutionBackend)), "WAVEFORM_SYSTEM_PHY"), ...
    "Mobility control loop must run on the waveform system backend.");
ok = true;
end
