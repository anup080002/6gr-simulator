function ok = testSystemWaveformTDDULGrantTiming()
%TESTSYSTEMWAVEFORMTDDULGRANTTIMING Prove DL-control/K2/UL-data timing.

% The production system runner must create a PUSCH grant on a real DL
% control occasion, preserve the canonical K2 decision, and execute the
% waveform only in the selected future UL slot.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.strictMode = true;
cfg.run.useMex = false;
cfg.system.phyBackend = "waveform";
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.outputs.saveFIG = false;

cfg.scenario.layout.nSites = 1;
cfg.scenario.layout.nSectorsPerSite = 1;
cfg.scenario.layout.wrapAround = false;
cfg.scenario.ue.nUE = 1;
cfg.scenario.nUE = 1;
cfg.scenario.bs.nTxAnt = 1;
cfg.scenario.bs.nRxAnt = 1;
cfg.scenario.ue.nTxAnt = 1;
cfg.scenario.ue.nRxAnt = 1;

cfg.channel.awgnOnly = true;
cfg.channel.model = "AWGN";
cfg.channel.fading.enable = false;

cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.duplex.mode = "TDD";
cfg.phy.duplex.tddCommon.ReferenceSubcarrierSpacingKHz = 30;
cfg.phy.duplex.tddCommon.Pattern1.PeriodicityMilliseconds = 5;
cfg.phy.duplex.tddCommon.Pattern1.NumDownlinkSlots = 1;
cfg.phy.duplex.tddCommon.Pattern1.NumDownlinkSymbols = 10;
cfg.phy.duplex.tddCommon.Pattern1.NumUplinkSlots = 8;
cfg.phy.duplex.tddCommon.Pattern1.NumUplinkSymbols = 2;
cfg.phy.pdcch.symbolAllocation = [0 2];
cfg.phy.pdsch.symbolAllocation = [2 12];
cfg.phy.pusch.symbolAllocation = [2 12];
cfg.phy.pucch.symbolAllocation = [12 2];
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.codeRate = 0.3;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.nLayers = 1;
cfg.phy.pusch.dmrs.portSet = 0;
cfg.phy.tddTiming.allowedK2 = 2;
cfg.phy.tddTiming.pdcchToPUSCHK2 = 2;
cfg.phy.tddTiming.ulGrantK2 = 2;
cfg.phy.tddTiming.capabilityProfileID = ...
    "38.214-v18.8.0-cap1-dmrs-pos0-mu1";
cfg.phy.tddTiming.n1PDSCHProcessingTimeSymbols = 10;
cfg.phy.tddTiming.n2PUSCHPreparationTimeSymbols = 12;
cfg.phy.tddTiming.timingAdvanceTicks = 0;
cfg.mac.scheduler.type = "rr";

cfg = sixgr.config.normalizeConfig(cfg);
if isfield(cfg.phy, "frameStructure")
    cfg.phy = rmfield(cfg.phy, "frameStructure");
end
if isfield(cfg, "resolved_runtime_view") && ...
        isfield(cfg.resolved_runtime_view, "frame_structure")
    cfg.resolved_runtime_view = rmfield( ...
        cfg.resolved_runtime_view, "frame_structure");
end
if isfield(cfg.phy, "frame")
    cfg.phy = rmfield(cfg.phy, "frame");
end
cfg = sixgr.phy.frame.FrameRuntimeStateBuilder.attachTimingContext(cfg);
sixgr.config.validateConfig(cfg);

ctx = sixgr.core.SimContext(cfg);
numTTI = 3;
res = sixgr.system.SystemLevelRunner.run(ctx, struct( ...
    "NumTTI", numTTI, ...
    "OfferedBitsDL", zeros(numTTI, 1), ...
    "OfferedBitsUL", repmat(4000, numTTI, 1), ...
    "PHYBackend", "waveform"));

assert(res.Ok, "TDD UL waveform run reported failure.");
assert(sum(double(res.Details.GrantCountUL(:))) >= 1, ...
    "The future UL slot must execute at least one PUSCH grant.");
grants = res.Details.SchedulerGrants;
assert(istable(grants) && ~isempty(grants), ...
    "The TDD UL run did not export its executed grant trace.");
ul = grants(upper(string(grants.Direction)) == "UL", :);
assert(height(ul) >= 1, "No executed UL grant exists in the grant trace.");
assert(all(double(ul.TTI) == 3), ...
    "PUSCH was executed outside the configured first full UL slot.");
assert(all(double(ul.ControlAbsoluteSlot) == 0), ...
    "The UL grant must retain the slot-0 DL control occasion.");
assert(all(double(ul.ScheduledAbsoluteSlot) == 2), ...
    "The UL grant must retain the canonical slot-2 PUSCH target.");
assert(all(double(ul.K2) == 2), ...
    "The executed UL grant must retain the configured K2=2 decision.");
assert(all(double(ul.ScheduledAbsoluteSlot) - ...
    double(ul.ControlAbsoluteSlot) == double(ul.K2)), ...
    "The exported control/data slots do not satisfy the grant's K2.");
assert(all(logical(ul.WaveformReplayExecuted)), ...
    "The queued UL grant did not execute through waveform replay.");
assert(all(double(res.Details.GrantCountDL(:)) == 0), ...
    "The UL-only fixture must not create a data-DL grant.");

ok = true;
end
