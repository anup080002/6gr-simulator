function ok = testLLSTRSRuntimeArtifacts()
%TESTLLSTRSRUNTIMEARTIFACTS Verify truthful TRS runtime export and blocker labeling.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scfg = sixgr.lls6g.config.loadScenarioConfig( ...
    fullfile(pwd, "simulator", "configs", "scenarios", "lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml"));
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.snr_dB = 30;
cfg.run.noiseOperatingMode = "receiver_noise_figure_thermal_noise";
cfg.phy.trs.enable = true;
cfg.run.controlGating.pbchRequired = false;
cfg.run.controlGating.prachRequired = false;
cfg.run.controlGating.pdcchRequired = false;
cfg.run.controlGating.srsRequired = false;
cfg.run.controlGating.trsRequired = true;
cfg.run.controlGating.trsMaxAgeSlots = 2;
cfg.phy.pdsch.enable = true;
cfg.phy.pusch.enable = true;

multiUser = struct("Enabled", true, "NumUsers", 1, "RNTIStart", 320, "ExecutionModel", "slot_coupled_truth");
state = sixgr.truth.CoupledTruthRuntime.initialize(cfg, fullfile(tmp, "runtime"), multiUser, struct(), 1);
state.CurrentServingIdx(1) = 1;
state.CurrentFrame = 1;
state.CurrentSlot = 5;
state.CurrentSNR_dB = 30;
state.CurrentServingMetric_dBm(1) = -70;
state.LargeScaleState.BeamIndex = 1;
state.LargeScaleState.BeamGain_dB = 0;
state.LargeScaleState.RxPower_dBm = -70;
state.LargeScaleState.BasePathloss_dB = 100;
state.LargeScaleState.Pathloss_dB = 100;
state.LargeScaleState.Shadow_dB = 0;
state.LargeScaleState.O2I_dB = 0;
state.DLQueueBits(1) = 24000;
state.ULQueueBits(1) = 24000;
state = sixgr.truth.CoupledTruthRuntime.startSlot(state, cfg, "DL", 1, 1, 1, 1, 10);
state = sixgr.truth.CoupledTruthRuntime.refreshControlState(state);
assert(~logical(state.SchedulingEligibility(1)), ...
    "TRS-required runtime state must keep scheduling ineligible before a valid TRS trial.");

trsRow = table(1, 5, 30, 28, -18, 3, 0.98, 18, true, true, true, true, true, 0, 0, 0, true, true, true, true, 0, 0, 0, true, true, true, true, "trs_reference_waveform_estimator", "PASS", 'VariableNames', ...
    {'Frame','Slot','InjectedDoppler_Hz','EstimatedDopplerHz','NMSE_dB','PhaseTrackingError_deg', ...
    'QCLAccuracy','DetectionMetric','DetectionAttempted','DetectionSuccess','DetectionUsable', ...
    'TimingTrackingAttempted','TRSTimingEstimateAvailable','EstimatedTimingOffset_samples', ...
    'TimingEstimate_samples','TimingError_samples','TRSTimingEstimateUsable','FrequencyTrackingAttempted', ...
    'TRSCFOEstimateAvailable','TRSCFOEstimateUsable','EstimatedCFO_Hz','EstimatedCFO_PreCorrection_Hz', ...
    'FrequencyError_Hz','ChannelEstimationAttempted','TRSChannelEstimateAvailable','TRSRuntimeEvidenceUsable', ...
    'StrictOk','TrackingEstimateSource','Status'});
state = sixgr.truth.CoupledTruthRuntime.applyTRSTrial(state, 1, trsRow);
state = sixgr.truth.CoupledTruthRuntime.refreshControlState(state);
assert(logical(state.SchedulingEligibility(1)), ...
    "TRS runtime state must enable scheduling after a valid TRS observation.");
assert(isfield(state, "ReceiverTrackingStateByCell") && logical(state.ReceiverTrackingStateByCell(1).TRSProcessed) && ...
    strcmpi(char(string(state.ReceiverTrackingStateByCell(1).ReceiverConsumerType)), "shared_receiver_tracking_state"), ...
    "Valid TRS observations must update the shared receiver tracking state object.");
assert(logical(state.ReceiverTrackingStateByCell(1).TimingEstimateAvailable) && isfinite(double(state.ReceiverTrackingStateByCell(1).TimingEstimate_samples)), ...
    "Strict TRS observations must publish measured timing estimates to the shared receiver tracking state.");
assert(logical(state.ReceiverTrackingStateByCell(1).CFOEstimateAvailable) && isfinite(double(state.ReceiverTrackingStateByCell(1).EstimatedCFO_Hz)), ...
    "Strict TRS observations must publish measured CFO estimates to the shared receiver tracking state.");
state = sixgr.truth.CoupledTruthRuntime.writeTables(state, fullfile(tmp, "runtime"));
trackingStatePath = fullfile(tmp, "runtime", "reports", "csv", "live_receiver_tracking_state.csv");
trackingTracePath = fullfile(tmp, "runtime", "reports", "csv", "live_receiver_tracking_trace.csv");
assert(exist(trackingStatePath, "file") == 2 && exist(trackingTracePath, "file") == 2, ...
    "Receiver tracking state and trace artifacts must be persisted.");
trackingStateT = readtable(trackingStatePath, "VariableNamingRule", "preserve");
trackingTraceT = readtable(trackingTracePath, "VariableNamingRule", "preserve");
assert(height(trackingStateT) >= 1 && logical(trackingStateT.TRSProcessed(1)) && ...
    strcmpi(char(string(trackingStateT.IntegrationStatus(1))), "integrated_shared_tracking_object"), ...
    "Persisted receiver tracking state must carry runtime-backed TRS integration evidence.");
assert(height(trackingTraceT) == 1 && strcmpi(char(string(trackingTraceT.TRSReceiverConsumerType(1))), "shared_receiver_tracking_state") && ...
    strcmpi(char(string(trackingTraceT.TRSUpdateOutcome(1))), "updated_from_trs_runtime_observation"), ...
    "Persisted receiver tracking trace must show the actual TRS update outcome.");

cfgRun = cfg;
cfgRun = sixgr.util.structSet(cfgRun, "lls6g.userContext.RuntimeServingCell", 1);
cfgRun = sixgr.truth.CoupledTruthRuntime.applyUserContext(cfgRun, state, 1, "DL");
[state, grants] = sixgr.truth.CoupledTruthRuntime.scheduleDirection(state, cfgRun, "DL");
assert(~isempty(grants), ...
    "A DL grant must be produced once TRS gating has made the UE eligible.");
grant = grants(1);
assert(isstruct(grant) && logical(sixgr.util.structGet(grant, "ControlEligible", false)), ...
    "A DL grant must be marked control-eligible after valid TRS gating.");

out = sixgr.link.runDLPDSCHThroughput(cfgRun, "SNR_dB", 30, "NumFrames", 1, ...
    "GrantSnapshot", grant);
T = out.TrialTable;
assert(istable(T) && height(T) == 1, ...
    "DL replay must produce a single raw trial row for the TRS runtime truth check.");
assert(all(ismember(["TRSGatingActive","TRSValidityState","TrackingEligibility","TRSRuntimeConsumer", ...
    "TRSInfluencedDecision","TRSInfluenceDefinition","TRSReceiverIntegrationStatus","TRSReceiverIntegrationBlocker"], ...
    string(T.Properties.VariableNames))), ...
    "Raw DL trial exports must carry the canonical TRS runtime context fields.");
assert(logical(T.TRSGatingActive(1)) && strcmpi(char(string(T.TRSValidityState(1))), "valid") && logical(T.TrackingEligibility(1)), ...
    "Raw DL trial rows must reflect the active valid TRS state.");
assert(strcmpi(char(string(T.TRSRuntimeConsumer(1))), "shared_receiver_tracking_state"), ...
    "Raw DL trial rows must name the shared receiver tracking object as the real TRS runtime consumer.");
assert(logical(T.TRSInfluencedDecision(1)), ...
    "Raw DL trial rows must show that TRS influenced the downstream scheduling decision.");
assert(strcmpi(char(string(T.TRSReceiverIntegrationStatus(1))), "integrated_shared_tracking_object"), ...
    "Raw DL trial rows must state the runtime-backed receiver integration status.");
assert(strlength(strtrim(string(T.TRSReceiverIntegrationBlocker(1)))) == 0, ...
    "Raw DL trial rows must not retain the old receiver-integration blocker after real integration.");

ok = true;
end
