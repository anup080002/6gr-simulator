function testPrachAccessStateMachine
%TESTPRACHACCESSSTATEMACHINE PRACH transitions update runtime state and ledger.

state = localMinimalAccessState(3);

pbch = struct2table(struct( ...
    "Status", "PASS", "CRCPass", 1, "Slot", 1, "RNTI", 4601, ...
    "SSBIndex", 0), "AsArray", true);
state = sixgr.truth.CoupledTruthRuntime.applyPBCHTrial(state, 1, pbch);
assert(state.CellAcquisitionState(1) == "acquired", "PBCH pass must acquire the serving cell.");
assert(any(string(state.AccessTransitionLedgerTable.new_state) == "PBCH_DECODED"), ...
    "PBCH transition must be recorded in access_transition_ledger.");

prachPass = localPrachRow("PASS", 1, true, 0.84, "");
state = sixgr.truth.CoupledTruthRuntime.applyPRACHTrial(state, 1, prachPass);
assert(state.AccessState(1) == "succeeded", "PRACH pass must move UE access to succeeded.");
assert(state.LastSuccessfulPRACHSlotByUE(1) == 5, "PRACH success slot must be retained.");
assert(any(string(state.AccessTransitionLedgerTable.new_state) == "ACCESS_SUCCEEDED"), ...
    "PRACH success must be recorded in access_transition_ledger.");

prachFail = localPrachRow("FAIL", 0, false, 0.05, "prach_correlation_below_threshold");
state = sixgr.truth.CoupledTruthRuntime.applyPRACHTrial(state, 2, prachFail);
assert(state.AccessState(2) == "failed", "PRACH failure must not be promoted to success.");
assert(any(string(state.AccessTransitionLedgerTable.new_state) == "ACCESS_FAILED"), ...
    "PRACH failure must be recorded in access_transition_ledger.");

state.CfgMobility.initial_access.rrc.require_setup_complete = true;
pbch.Slot(1) = 1;
pbch.RNTI(1) = 4603;
state = sixgr.truth.CoupledTruthRuntime.applyPBCHTrial(state, 3, pbch);
rrcPrach = localPrachRow("PASS", 1, true, 0.91, "");
rrcPrach.RACompleted = true;
rrcPrach.FullRAEvidenceSource = "sixgr.phy.ra.runFourStepRA";
rrcPrach.RequireRRCSetupComplete = true;
rrcPrach.Msg2ScheduledSlot = 6;
rrcPrach.Msg3ScheduledSlot = 7;
rrcPrach.Msg4ScheduledSlot = 8;
rrcPrach.SetupCompleteScheduledSlot = 9;
rrcPrach.RRCSetupRequestDecoded = true;
rrcPrach.RRCSetupDecoded = true;
rrcPrach.SRB1Installed = true;
rrcPrach.RRCSetupCompleteCRC = true;
rrcPrach.RRCSetupCompleteDecoded = true;
rrcPrach.RRCConnected = true;
rrcPrach.RRCSetupCompletePayloadSHA256 = ...
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
state = sixgr.truth.CoupledTruthRuntime.applyPRACHTrial(state, 3, rrcPrach);
trace = state.InitialAccessLifecycleTraceTable;
ue3 = double(trace.UEIndex) == 3;
terminal = ue3 & string(trace.EventName) == "RRC_SETUP_COMPLETE_ACCEPTED";
assert(nnz(terminal) == 1 && logical(trace.CompleteFlag(terminal)) && ...
    double(trace.Slot(terminal)) == 9, ...
    "Required RRCSetupComplete must be the terminal coupled-runtime event at its actual scheduled slot.");
assert(string(trace.SourceArtifact(terminal)) == "control/csv/rrc_setup_complete.csv", ...
    "The terminal lifecycle event must bind to canonical RRCSetupComplete waveform evidence.");
end

function T = localPrachRow(status, crcPass, detected, metric, failureReason)
row = struct( ...
    "Status", string(status), ...
    "CRCPass", double(crcPass), ...
    "Slot", 5, ...
    "RNTI", 4601, ...
    "DetectionSuccess", logical(detected), ...
    "DetectionMetric", double(metric), ...
    "CorrelationPeak", double(metric), ...
    "RequestedPreambleIndex", 7, ...
    "DetectedPreambleIndex", 7, ...
    "PRACHRootSequenceIndex", 1, ...
    "PRACHOccasionIndex", 0, ...
    "PRACHCarrierSlot", 5, ...
    "PRACHFormat", "B4", ...
    "TimingAdvance_samples", 3, ...
    "TimingOffset_samples", 3, ...
    "RACompleted", false, ...
    "FailureReason", string(failureReason), ...
    "Notes", string(failureReason), ...
    "Skipped", false);
T = struct2table(row, "AsArray", true);
end

function state = localMinimalAccessState(nUsers)
nCells = 2;
state = struct();
state.NumUsers = nUsers;
state.MultiUser = struct("RNTIStart", 4601, "NumUsers", nUsers, "Enabled", true, "ExecutionModel", "coupled_truth");
state.CurrentFrame = 1;
state.CurrentSlot = 5;
state.SlotsPerFrame = 20;
state.SlotDuration_s = 0.0005;
state.CurrentServingIdx = (1:nUsers).';
state.CfgMobility = struct();
state.LargeScaleState = struct();
state.Bandwidth_Hz = 100e6;
state.NoiseFigure_dB = 7;
state.ControlGating = struct("PBCHRequired", true, "PRACHRequired", true, ...
    "PDCCHRequired", true, "SRSRequired", false, "TRSRequired", false, ...
    "SRSMaxAgeSlots", 20, "TRSMaxAgeSlots", 20);
state.CellAcquisitionState = repmat("acquired", nUsers, 1);
state.CellAcquisitionState(1) = "searching";
state.AccessState = repmat("pending", nUsers, 1);
state.SRSValidityState = repmat("not_required", nUsers, 1);
state.CSIValidityState = repmat("not_required", nUsers, 1);
state.TRSValidityStateByCell = repmat("not_required", nCells, 1);
state.TrackingEligibilityByCell = true(nCells, 1);
state.LastSuccessfulPBCHSlotByUE = nan(nUsers, 1);
state.LastSuccessfulPRACHSlotByUE = nan(nUsers, 1);
state.LastSuccessfulSRSSlotByUE = nan(nUsers, 1);
state.LastSuccessfulTRSSlotByCell = nan(nCells, 1);
state.LastTRSObservedSlotByCell = nan(nCells, 1);
state.LastTimingAdvanceSamplesByUE = nan(nUsers, 1);
state.LastTimingAdvanceUsByUE = nan(nUsers, 1);
state.LastTimingAdvanceSourceByUE = repmat("", nUsers, 1);
state.LastTimingAdvanceUpdateSlotByUE = nan(nUsers, 1);
state.LastTimingAdvanceServingCellByUE = nan(nUsers, 1);
state.LastTimingAdvanceServingDistanceMByUE = nan(nUsers, 1);
state.TimingAdvanceDriftSamplesByUE = nan(nUsers, 1);
state.TimingAdvanceDriftUsByUE = nan(nUsers, 1);
state.TimingAdvanceUpdateRequiredByUE = false(nUsers, 1);
state.TimeAlignmentState = repmat("not_time_aligned", nUsers, 1);
state.TimingAdvanceUpdateStatusByUE = repmat("not_evaluated", nUsers, 1);
state.PRACHFailureCount = zeros(nUsers, 1);
state.PBCHFailureCount = zeros(nUsers, 1);
state.SRSInvalidEventCount = zeros(nUsers, 1);
state.AccessTransitionLedgerTable = sixgr.monitor.AccessFlowRecorder.emptyLedger();
end
