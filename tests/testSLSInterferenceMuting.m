function ok = testSLSInterferenceMuting()
%TESTSLSINTERFERENCEMUTING Muting non-serving cells must raise DL SINR.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.strictMode = false;
cfg.run.useMex = false;
cfg.run.seed = 11;
cfg.run.scenario = "UMi";
cfg.system.phyBackend = "waveform";
cfg.system.handover.enable = false;
cfg.system.beam.enable = false;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.outputs.saveFIG = false;

cfg.scenario.layout.nSites = 2;
cfg.scenario.layout.nSectorsPerSite = 1;
cfg.scenario.layout.interSiteDistance_m = 200;
cfg.scenario.layout.wrapAround = false;
cfg.scenario.ue.nUE = 12;
cfg.scenario.nUE = 12;
cfg.scenario.ue.indoorFraction = 0;
cfg.scenario.mobility.enable = false;
cfg.scenario.bs.nTxAnt = 1;
cfg.scenario.bs.nRxAnt = 1;
cfg.scenario.ue.nTxAnt = 1;
cfg.scenario.ue.nRxAnt = 1;

cfg.phy.duplex.mode = "FDD";
cfg.phy.duplex.fdd = struct( ...
    "dlCenterFrequencyHz", 2.14e9, ...
    "ulCenterFrequencyHz", 1.95e9);
cfg.channel.awgnOnly = true;
cfg.channel.model = "AWGN";
cfg.channel.fading.enable = false;
cfg.channel.pathlossEnabled = true;
cfg.channel.shadowFadingEnabled = false;
cfg.channel.losEnabled = false;
cfg.channel.interferenceMargin_dB = 40;
cfg.channel.interferenceStd_dB = 15;

cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 0.35;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.symbolAllocation = [0 14];
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.codeRate = 0.35;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.nLayers = 1;
cfg.phy.pusch.symbolAllocation = [0 14];
cfg.phy.pdcch.symbolAllocation = [0 2];
cfg.phy.pucch.symbolAllocation = [0 2];
cfg.phy.tddTiming = struct( ...
    "allowedK0", 1, ...
    "pdcchToPDSCHK0", 1, ...
    "dlHARQFeedbackK1Candidates", 2, ...
    "pdcchToPUSCHK2", 1, ...
    "ulGrantK2", 1, ...
    "capabilityProfileID", ...
        "38.214-v18.8.0-cap1-dmrs-pos0-mu1", ...
    "n1PDSCHProcessingTimeSymbols", 10, ...
    "n2PUSCHPreparationTimeSymbols", 12, ...
    "timingAdvanceTicks", 0);
cfg.mac.scheduler.type = "rr";

cfg = sixgr.config.normalizeConfig(cfg);
cfg = sixgr.config.validateConfig(cfg);

numTTI = 4;
nUE = double(cfg.scenario.ue.nUE);
offeredBusy = repmat(4000, numTTI, nUE);
offeredZeroUL = zeros(numTTI, nUE);

sixgr.util.rngInit(double(cfg.run.seed), false);
resBusy = sixgr.system.SystemLevelRunner.run(sixgr.core.SimContext(cfg), struct( ...
    "NumTTI", numTTI, ...
    "OfferedBitsDL", offeredBusy, ...
    "OfferedBitsUL", offeredZeroUL, ...
    "PHYBackend", "waveform"));

assert(resBusy.Ok, "Busy interference-accounting run failed.");
assert(string(resBusy.Details.SINRModel) == "explicit_activity_power_sum", ...
    "Default system SINR path must use explicit desired/interference/noise accounting.");

servingSlot1 = reshape(double(resBusy.Details.ServingCell(1,:)), 1, []);
assert(numel(unique(servingSlot1)) >= 2, ...
    "Two-site regression must attach UEs to at least two serving cells.");

slot1Busy = resBusy.Details.InterferenceDetail(double(resBusy.Details.InterferenceDetail.TTI) == 1, :);
candidateBusy = slot1Busy(double(slot1Busy.ActiveInterfererCountDL) > 0 & ...
    isfinite(double(slot1Busy.SINR_DL_dB)), :);
assert(height(candidateBusy) >= 1, ...
    "Busy run must expose at least one UE with active non-serving DL interference.");

targetUE = double(candidateBusy.UE(1));
targetCell = servingSlot1(targetUE);
targetMask = servingSlot1 == targetCell;
assert(any(~targetMask), "Regression requires at least one non-serving-cell UE to mute.");

offeredMuted = offeredBusy;
offeredMuted(:, ~targetMask) = 0;

sixgr.util.rngInit(double(cfg.run.seed), false);
resMuted = sixgr.system.SystemLevelRunner.run(sixgr.core.SimContext(cfg), struct( ...
    "NumTTI", numTTI, ...
    "OfferedBitsDL", offeredMuted, ...
    "OfferedBitsUL", offeredZeroUL, ...
    "PHYBackend", "waveform"));

assert(resMuted.Ok, "Muted interferer run failed.");
servingSlot1Muted = reshape(double(resMuted.Details.ServingCell(1,:)), 1, []);
assert(servingSlot1Muted(targetUE) == targetCell, ...
    "Muted run must preserve the target UE serving cell for a clean SINR comparison.");

slot1Muted = resMuted.Details.InterferenceDetail(double(resMuted.Details.InterferenceDetail.TTI) == 1, :);
busyRow = localRowForUE(slot1Busy, targetUE);
mutedRow = localRowForUE(slot1Muted, targetUE);

assert(double(busyRow.ActiveInterfererCountDL) > 0, ...
    "Busy run must report at least one active non-serving DL interferer for the target UE.");
assert(double(mutedRow.ActiveInterfererCountDL) == 0, ...
    "Muting non-serving cells must remove DL interferers for the target UE.");
assert(double(mutedRow.SINR_DL_dB) > double(busyRow.SINR_DL_dB) + 0.1, ...
    "Muting neighboring cells must increase the target UE DL SINR.");
if isfinite(double(busyRow.InterferencePowerDL_dBm))
    assert(~isfinite(double(mutedRow.InterferencePowerDL_dBm)) || ...
        double(mutedRow.InterferencePowerDL_dBm) < double(busyRow.InterferencePowerDL_dBm) - 0.1, ...
        "Muting neighboring cells must reduce explicit DL interference power.");
end

busyRecon = double(busyRow.RxPower_dBm) - double(busyRow.Noise_dBm) - ...
    double(busyRow.InterferenceMargin_dB) + double(busyRow.SmallScaleFading_dB) - ...
    double(busyRow.InterferenceVariation_dB);
mutedRecon = double(mutedRow.RxPower_dBm) - double(mutedRow.Noise_dBm) - ...
    double(mutedRow.InterferenceMargin_dB) + double(mutedRow.SmallScaleFading_dB) - ...
    double(mutedRow.InterferenceVariation_dB);
assert(abs(busyRecon - double(busyRow.SINR_DL_dB)) < 1e-9, ...
    "Legacy DL alias columns must reconstruct the explicit DL SINR exactly.");
assert(abs(mutedRecon - double(mutedRow.SINR_DL_dB)) < 1e-9, ...
    "Legacy DL alias columns must reconstruct the muted-run DL SINR exactly.");

ok = true;
end

function row = localRowForUE(T, ue)
mask = double(T.UE) == double(ue);
assert(nnz(mask) == 1, "Expected exactly one slot-1 interference row for UE %d.", round(double(ue)));
row = T(mask, :);
end
