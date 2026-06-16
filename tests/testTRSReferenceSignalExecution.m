function ok = testTRSReferenceSignalExecution()
%TESTTRSREFERENCESIGNALEXECUTION Verify TRS generation and observation runtime.

setup6GRSimToolkit("Verbose", false);
if exist("nrOFDMModulate", "file") ~= 2 || exist("nrOFDMDemodulate", "file") ~= 2
    ok = true;
    return;
end

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.trs.enable = true;
cfg.phy.carrier.NSizeGrid = 24;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.snr_dB = 20;
cfg.run.noiseOperatingMode = "receiver_noise_figure_thermal_noise";
cfg.channel.doppler_Hz = 30;
cfg.channel.dopplerHz = 30;
cfg.channel.fading.maxDoppler_Hz = 30;
cfg = sixgr.util.structSet(cfg, "phy.trs.nPorts", 1);
cfg = sixgr.util.structSet(cfg, "phy.trs.scramblingID", 7);
cfg = sixgr.util.structSet(cfg, "phy.trs.symbolLocations", [2 11]);
cfg = sixgr.util.structSet(cfg, "phy.trs.subcarrierComb", 4);

[carrier, ~] = sixgr.phy.grid.makeCarrier(cfg);
[trsInd, trsSym, info] = sixgr.phy.refsig.trs(carrier, cfg);
assert(logical(info.Enabled), "TRS helper must enable when cfg.phy.trs.enable=true.");
assert(~isempty(trsInd) && ~isempty(trsSym), "TRS helper must generate actual indices and symbols.");

out = sixgr.link.runTRSTracking(cfg, "SNR_dB", 20);
assert(out.Ok, "TRS tracking smoke must complete.");
assert(isfinite(out.NMSE_dB), "TRS runtime must report NMSE.");
assert(isfinite(out.PhaseError_deg), "TRS runtime must report phase error.");
assert(isfinite(out.InjectedDoppler_Hz) && abs(out.InjectedDoppler_Hz - 30) < 1e-9, ...
    "TRS runtime must expose the injected Doppler semantics.");
assert(isfinite(out.EstimatedDoppler_Hz), "TRS runtime must report a finite Doppler estimate.");
assert(abs(out.EstimatedDoppler_Hz - out.InjectedDoppler_Hz) < 20, ...
    "TRS Doppler estimate must stay reasonably close to the injected Doppler in the smoke case.");
assert(strcmpi(char(string(out.CFOEstimateAvailability)), "available") && ...
    isfinite(double(out.EstimatedCFO_Hz)) && isfinite(double(out.EstimatedCFO_PreCorrection_Hz)), ...
    "TRS runtime must expose a real CFO estimate when the reference-symbol phase slope is observable.");
assert(out.NMSE_dB < 0, "TRS NMSE should be meaningfully below 0 dB at 20 dB SNR.");

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
scfg = sixgr.lls6g.config.loadScenarioConfig( ...
    fullfile(pwd, "simulator", "configs", "scenarios", "lls_100mhz_tdlc_bidirectional_truth.yaml"));
cfgLLS = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
cfgLLS.scenario.nUE = 1;
cfgLLS.scenario.ue.nUE = 1;
cfgLLS.run.controlGating.pbchRequired = false;
cfgLLS.run.controlGating.prachRequired = false;
cfgLLS.run.controlGating.pdcchRequired = false;
cfgLLS.run.controlGating.srsRequired = false;
cfgLLS.run.controlGating.trsRequired = true;
cfgLLS.run.controlGating.trsMaxAgeSlots = 2;
cfgLLS.phy.trs.enable = true;
multiUser = struct("Enabled", true, "NumUsers", 1, "RNTIStart", 320, "ExecutionModel", "slot_coupled_truth");
state = sixgr.truth.CoupledTruthRuntime.initialize(cfgLLS, fullfile(tmp, "runtime"), multiUser, struct(), 1);
state.CurrentServingIdx(1) = 1;
state.CurrentServingMetric_dBm(1) = -70;
state.LargeScaleState.BeamIndex = 1;
state.LargeScaleState.BeamGain_dB = 0;
state.LargeScaleState.RxPower_dBm = -70;
state.LargeScaleState.BasePathloss_dB = 100;
state.LargeScaleState.Pathloss_dB = 100;
state.LargeScaleState.Shadow_dB = 0;
state.LargeScaleState.O2I_dB = 0;
state.CurrentSlot = 4;
state = sixgr.truth.CoupledTruthRuntime.refreshControlState(state);
assert(~logical(state.SchedulingEligibility(1)), ...
    "TRS-required runtime state must keep scheduling ineligible before a valid TRS observation.");
stateBeforeTRS = state;

trsRow = table( ...
    1, ...
    5, ...
    double(out.InjectedDoppler_Hz), ...
    double(out.EstimatedDoppler_Hz), ...
    double(out.NMSE_dB), ...
    double(out.PhaseError_deg), ...
    double(out.QCLAccuracy), ...
    double(out.DetectionMetric), ...
    string(out.TrackingEstimateSource), ...
    string(ternaryTRSStatus(logical(out.Ok))), ...
    'VariableNames', {'Frame','Slot','InjectedDoppler_Hz','EstimatedDopplerHz','NMSE_dB','PhaseTrackingError_deg', ...
    'QCLAccuracy','DetectionMetric','TrackingEstimateSource','Status'});
state = sixgr.truth.CoupledTruthRuntime.applyTRSTrial(state, 1, trsRow);
assert(strcmpi(char(string(state.TRSValidityStateByCell(1))), "failed") && ~logical(state.TrackingEligibilityByCell(1)), ...
    "TRS-required gating must reject rows that lack explicit detection/timing/frequency/channel evidence.");
assert(isfield(state, "ReceiverTrackingStateByCell") && logical(state.ReceiverTrackingStateByCell(1).TRSProcessed), ...
    "TRS trial application must update the shared receiver tracking state object.");
assert(strcmpi(char(string(state.ReceiverTrackingStateByCell(1).ReceiverConsumerType)), "shared_receiver_tracking_state") && ...
    strcmpi(char(string(state.ReceiverTrackingStateByCell(1).IntegrationStatus)), "integrated_shared_tracking_object"), ...
    "TRS must be consumed by the shared receiver tracking state object, not scheduler-only metadata.");
assert(strcmpi(char(string(state.ReceiverTrackingStateByCell(1).TimingTrackingState)), "not_updated_timing_estimate_unavailable") && ...
    ~logical(state.ReceiverTrackingStateByCell(1).TimingEstimateAvailable) && ~isfinite(double(state.ReceiverTrackingStateByCell(1).TimingEstimate_samples)), ...
    "TRS receiver tracking must not fabricate timing estimates when the runtime row has none.");
assert(~logical(state.ReceiverTrackingStateByCell(1).CFOEstimateAvailable) && ~isfinite(double(state.ReceiverTrackingStateByCell(1).EstimatedCFO_Hz)), ...
    "TRS receiver tracking must not fabricate CFO estimates when the runtime row has none.");
assert(~logical(state.SchedulingEligibility(1)), ...
    "Incomplete TRS rows must not feed scheduler eligibility when TRS gating is active.");

trsRuntimeCFORow = localStrictTRSRow(trsRow, out);
stateRuntimeCFO = sixgr.truth.CoupledTruthRuntime.applyTRSTrial(stateBeforeTRS, 1, trsRuntimeCFORow);
assert(strcmpi(char(string(stateRuntimeCFO.TRSValidityStateByCell(1))), "valid") && logical(stateRuntimeCFO.TrackingEligibilityByCell(1)), ...
    "TRS trial application must update runtime tracking state only after strict evidence is complete.");
assert(logical(stateRuntimeCFO.ReceiverTrackingStateByCell(1).CFOEstimateAvailable) && ...
    abs(double(stateRuntimeCFO.ReceiverTrackingStateByCell(1).EstimatedCFO_Hz) - double(out.EstimatedCFO_Hz)) < 1e-9, ...
    "TRS receiver tracking must consume real CFO estimates carried by runtime TRS trial rows.");
state = stateRuntimeCFO;

cfgLLS = sixgr.truth.CoupledTruthRuntime.applyUserContext(cfgLLS, state, 1, "DL");
userMeta = sixgr.util.structGet(cfgLLS, "lls6g.userContext", struct());
assert(logical(sixgr.util.structGet(userMeta, "RuntimeTRSGatingActive", false)) && ...
    strcmpi(char(string(sixgr.util.structGet(userMeta, "RuntimeTRSRuntimeConsumer", ""))), "shared_receiver_tracking_state") && ...
    logical(sixgr.util.structGet(userMeta, "RuntimeTRSInfluencedDecision", false)), ...
    "Applied user context must expose the shared receiver tracking object as the real TRS runtime consumer.");
assert(strcmpi(char(string(sixgr.util.structGet(userMeta, "RuntimeTRSReceiverIntegrationStatus", ""))), ...
    "integrated_shared_tracking_object") && ...
    strlength(strtrim(string(sixgr.util.structGet(userMeta, "RuntimeTRSReceiverIntegrationBlocker", "")))) == 0 && ...
    logical(sixgr.util.structGet(userMeta, "RuntimeTRSProcessed", false)), ...
    "Applied user context must export runtime-backed TRS receiver integration evidence.");

stateSync = state;
trsSyncRow = localStrictTRSRow(trsRow, out);
trsSyncRow.EstimatedTimingOffset_samples = 0;
trsSyncRow.EstimatedCFO_Hz = 0;
stateSync = sixgr.truth.CoupledTruthRuntime.applyTRSTrial(stateSync, 1, trsSyncRow);
assert(logical(stateSync.ReceiverTrackingStateByCell(1).TimingEstimateAvailable) && ...
    isfinite(double(stateSync.ReceiverTrackingStateByCell(1).TimingEstimate_samples)) && ...
    logical(stateSync.ReceiverTrackingStateByCell(1).CFOEstimateAvailable) && ...
    isfinite(double(stateSync.ReceiverTrackingStateByCell(1).EstimatedCFO_Hz)), ...
    "TRS receiver tracking must persist real timing/CFO estimates when the runtime row provides them.");

cfgSyncDL = sixgr.truth.CoupledTruthRuntime.applyUserContext(cfgLLS, stateSync, 1, "DL");
cfgSyncDL.channel.model = "AWGN";
cfgSyncDL.channel.awgnOnly = true;
cfgSyncDL.channel.snr_dB = 30;
cfgSyncDL.phy.rx.useIdealTimingSync = false;
cfgSyncDL = sixgr.util.structSet(cfgSyncDL, "phy.impairments.cfoHz", 0);
cfgSyncDL = sixgr.util.structSet(cfgSyncDL, "phy.impairments.timingOffsetSamples", 0);
dlSync = sixgr.link.runDLPDSCHThroughput(cfgSyncDL, "SNR_dB", 30, "NumFrames", 1);
dlSyncT = dlSync.TrialTable;
assert(istable(dlSyncT) && height(dlSyncT) == 1 && ...
    strcmpi(char(string(dlSyncT.CFOEstimateAvailability(1))), "available") && ...
    logical(dlSyncT.TimingEstimateUsed(1)) && ...
    isfinite(double(dlSyncT.EstimatedCFO_PreCorrection_Hz(1))) && ...
    isfinite(double(dlSyncT.EstimatedTimingOffset_PreCorrection_samples(1))) && ...
    isfinite(double(dlSyncT.AppliedTimingCorrection_samples(1))) && ...
    strcmpi(char(string(dlSyncT.TimingEstimateStatus(1))), "available_applied_signed_correction"), ...
    "DL PDSCH receiver must consume real TRS timing/CFO estimates and persist them in raw trial outputs.");

cfgSyncUL = sixgr.truth.CoupledTruthRuntime.applyUserContext(cfgLLS, stateSync, 1, "UL");
cfgSyncUL.channel.model = "AWGN";
cfgSyncUL.channel.awgnOnly = true;
cfgSyncUL.channel.snr_dB = 30;
cfgSyncUL.phy.rx.useIdealTimingSync = false;
cfgSyncUL = sixgr.util.structSet(cfgSyncUL, "phy.impairments.cfoHz", 0);
cfgSyncUL = sixgr.util.structSet(cfgSyncUL, "phy.impairments.timingOffsetSamples", 0);
ulSync = sixgr.link.runULPUSCHThroughput(cfgSyncUL, "SNR_dB", 30, "NumFrames", 1);
ulSyncT = ulSync.TrialTable;
assert(istable(ulSyncT) && height(ulSyncT) == 1 && ...
    strcmpi(char(string(ulSyncT.CFOEstimateAvailability(1))), "available") && ...
    logical(ulSyncT.TimingEstimateUsed(1)) && ...
    isfinite(double(ulSyncT.EstimatedCFO_PreCorrection_Hz(1))) && ...
    isfinite(double(ulSyncT.EstimatedTimingOffset_PreCorrection_samples(1))) && ...
    isfinite(double(ulSyncT.AppliedTimingCorrection_samples(1))) && ...
    strcmpi(char(string(ulSyncT.TimingEstimateStatus(1))), "available_applied_signed_correction"), ...
    "UL PUSCH receiver must consume real TRS timing/CFO estimates and persist them in raw trial outputs.");

artifacts = sixgr.truth.CoupledTruthRuntime.mobilityArtifacts(state);
controlStateT = artifacts.ControlGatingStateTable;
assert(istable(controlStateT) && height(controlStateT) == 1 && logical(controlStateT.TrackingEligibility(1)), ...
    "Control-state artifacts must export the runtime TRS tracking eligibility.");
assert(isfinite(double(controlStateT.LastEstimatedTRSDopplerHz(1))), ...
    "Control-state artifacts must export the estimated TRS Doppler state.");
assert(istable(artifacts.ReceiverTrackingStateTable) && height(artifacts.ReceiverTrackingStateTable) >= 1 && ...
    logical(artifacts.ReceiverTrackingStateTable.TRSProcessed(1)), ...
    "Mobility artifacts must expose the shared receiver tracking state updated by TRS.");
assert(istable(artifacts.ReceiverTrackingTraceTable) && height(artifacts.ReceiverTrackingTraceTable) == 1 && ...
    strcmpi(char(string(artifacts.ReceiverTrackingTraceTable.TRSRuntimeEvidenceSource(1))), "trs_reference_waveform_estimator"), ...
    "Receiver tracking trace must persist the real TRS runtime estimator source.");

state.CurrentSlot = 8;
state = sixgr.truth.CoupledTruthRuntime.refreshControlState(state);
assert(strcmpi(char(string(state.TRSValidityStateByCell(1))), "stale") && ~logical(state.TrackingEligibilityByCell(1)), ...
    "TRS runtime state must age out when the observation becomes stale.");
assert(strcmpi(char(string(state.ReceiverTrackingStateByCell(1).TrackingState)), "stale"), ...
    "Shared receiver tracking state must age to stale with the TRS freshness state.");
assert(~logical(state.SchedulingEligibility(1)), ...
    "Stale TRS state must revoke scheduler eligibility in the active runtime path.");

ok = true;
end

function row = localStrictTRSRow(row, out)
row.DetectionAttempted = true;
row.DetectionSuccess = true;
row.TimingTrackingAttempted = true;
row.TRSTimingEstimateAvailable = true;
row.EstimatedTimingOffset_samples = 0;
row.FrequencyTrackingAttempted = true;
row.TRSCFOEstimateAvailable = true;
row.EstimatedCFO_Hz = double(out.EstimatedCFO_Hz);
row.EstimatedCFO_PreCorrection_Hz = double(out.EstimatedCFO_PreCorrection_Hz);
row.ChannelEstimationAttempted = true;
row.TRSChannelEstimateAvailable = true;
row.StrictOk = true;
end

function status = ternaryTRSStatus(okFlag)
if okFlag
    status = "PASS";
else
    status = "FAIL";
end
end
