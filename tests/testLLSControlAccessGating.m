function ok = testLLSControlAccessGating()
%TESTLLSCONTROLACCESSGATING Focused LLS control/access gating checks.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scfg = sixgr.lls6g.config.loadScenarioConfig( ...
    fullfile(pwd, "simulator", "configs", "scenarios", "lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml"));
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
cfg = sixgr.util.structSet(cfg, "run.controlGating.trsRequired", false);
cfg = sixgr.util.structSet(cfg, "control_gating.trs_required", false);
cfg = sixgr.util.structSet(cfg, "phy.duplex.mode", "TDD");
cfg = sixgr.util.structSet(cfg, "referenceSignals.operationOrientation", "");
cfg = sixgr.util.structSet(cfg, "referenceSignals.csiAcquisitionMode", "");
cfg = sixgr.util.structSet(cfg, "lls6g.reference_signals.operation_orientation", "tdd_reciprocity");
cfg = sixgr.util.structSet(cfg, "lls6g.reference_signals.csi_acquisition_mode", "joint_dl_ul");

multiUser = struct( ...
    "Enabled", true, ...
    "NumUsers", 1, ...
    "RNTIStart", 320, ...
    "ExecutionModel", "slot_coupled_truth");

state = sixgr.truth.CoupledTruthRuntime.initialize(cfg, fullfile(tmp, "run"), multiUser, struct(), 1);
state.CurrentServingIdx(:) = 1;
state.CurrentServingMetric_dBm(:) = -80;
state.DLQueueBits(:) = 24000;
state.ULQueueBits(:) = 24000;
state = sixgr.truth.CoupledTruthRuntime.startSlot(state, cfg, "DL", 1, 1, 1, 1, 10);
state = sixgr.truth.CoupledTruthRuntime.refreshControlState(state);

[stateBlocked, dlGrantsBlocked, ~] = sixgr.truth.CoupledTruthRuntime.scheduleDirection(state, cfg, "DL");
assert(isempty(dlGrantsBlocked), ...
    "PBCH/PRACH gating must block initial DL scheduling before acquisition/access succeed.");
assert(logical(stateBlocked.SchedulingEligibility(1)) == false, ...
    "SchedulingEligibility must stay false before PBCH/PRACH succeed.");

pbchPass = localControlTrial("PASS", double(state.CurrentSlot), double(state.CurrentFrame));
state = sixgr.truth.CoupledTruthRuntime.applyPBCHTrial(state, 1, pbchPass);
assert(string(state.CellAcquisitionState(1)) == "acquired", ...
    "PBCH pass must move the UE into acquired state.");

prachPass = localControlTrial("PASS", double(state.CurrentSlot), double(state.CurrentFrame));
state = sixgr.truth.CoupledTruthRuntime.applyPRACHTrial(state, 1, prachPass);
assert(string(state.AccessState(1)) == "succeeded", ...
    "PRACH pass must move the UE into succeeded access state.");

srsPass = localControlTrial("PASS", double(state.CurrentSlot), double(state.CurrentFrame));
srsPass.RIEstimate = 1;
srsPass.TPMIEstimate = 0;
srsPass.MeasuredTrialSINR_dB = 18;
srsPass.WidebandCQI = 10;
srsPass.CQIDerivedMCS = 11;
srsPass.CQIDerivedModulation = "64QAM";
srsPass.CQIDerivedTargetCodeRate = 0.455078125;
state = sixgr.truth.CoupledTruthRuntime.applySRSTrial(state, 1, srsPass);
assert(string(state.SRSValidityState(1)) == "valid", ...
    "SRS pass must move the UE into valid SRS state.");
assert(logical(state.LatestULFeedback(1).Valid) && double(state.LatestULFeedback(1).RI) == 1, ...
    "SRS RI/TPMI evidence must feed the latest UL feedback state.");
assert(logical(state.LatestDLFeedback(1).Valid) && double(state.LatestDLFeedback(1).CQI) > 0 && ...
        isfinite(double(state.LatestDLFeedback(1).MCSIndex)), ...
    "TDD reciprocal SRS evidence from lls6g.reference_signals must feed measured DL AMC feedback.");

[stateReady, dlGrantsReady, ~] = sixgr.truth.CoupledTruthRuntime.scheduleDirection(state, cfg, "DL");
assert(~isempty(dlGrantsReady), ...
    "DL grants must appear once PBCH/PRACH gating is satisfied.");
grant = dlGrantsReady(1);
assert(double(sixgr.util.structGet(grant, "MCSIndex", NaN)) > 1 && ...
        strcmpi(char(string(sixgr.util.structGet(grant, "GrantOperatingPointSource", ""))), "feedback_cqi_derived_reference"), ...
    "DL grants after reciprocal SRS feedback must consume measured CQI-derived AMC before PHY execution.");
assert(strcmpi(char(string(sixgr.util.structGet(grant, "GrantControlState", ""))), "control_pending"), ...
    "Scheduled grants must start in the control_pending state when PDCCH gating is active.");

pdcchFail = localControlTrial("FAIL", double(grant.Slot), double(grant.Frame));
[stateReady, gatedGrant, allowExecution] = sixgr.truth.CoupledTruthRuntime.applyPDCCHGrantTrial(stateReady, grant, "DL", pdcchFail);
assert(~allowExecution, ...
    "Failed PDCCH gating must block PHY data execution for the scheduled grant.");
assert(strcmpi(char(string(sixgr.util.structGet(gatedGrant, "GrantControlState", ""))), "control_failed"), ...
    "Failed PDCCH gating must mark the grant as control_failed.");
assert(logical(stateReady.GrantsBlockedByGatingCount(1)) >= 1, ...
    "Failed PDCCH gating must increment the blocked-grant counter.");
assert(istable(stateReady.DLGrantTraceTable) && ~isempty(stateReady.DLGrantTraceTable) && ...
    strcmpi(char(string(stateReady.DLGrantTraceTable.GrantControlState(end))), "control_failed"), ...
    "Grant trace must record control_failed for blocked data grants.");

[stateReady, tddBlockedGrant] = sixgr.truth.CoupledTruthRuntime.blockPDCCHGrantTrial( ...
    stateReady, grant, "DL", "control_blocked_no_dl_control_symbols_in_tdd_slot");
assert(strcmpi(char(string(sixgr.util.structGet(tddBlockedGrant, "GrantControlState", ""))), ...
    "control_blocked_no_dl_control_symbols_in_tdd_slot"), ...
    "TDD slots with no DL control symbols must block PDCCH-gated grants explicitly.");
assert(~logical(sixgr.util.structGet(tddBlockedGrant, "ControlDecodeOk", true)), ...
    "TDD PDCCH slot-direction blocking must not mark control decode as successful.");

stateReady.CurrentSlot = double(stateReady.CurrentSlot) + double(stateReady.ControlGating.SRSMaxAgeSlots) + 1;
stateReady = sixgr.truth.CoupledTruthRuntime.refreshControlState(stateReady);
assert(string(stateReady.SRSValidityState(1)) == "stale", ...
    "SRS freshness gating must age successful SRS into stale state after the configured slot budget.");
assert(string(stateReady.CSIValidityState(1)) == "stale_srs_not_usable", ...
    "Stale SRS must switch CSI validity into an unavailable-for-fresh-CSI state.");

ok = true;
end

function T = localControlTrial(status, slotIdx, frameIdx)
row = table( ...
    string(status), double(slotIdx), double(frameIdx), ...
    'VariableNames', {'Status','Slot','Frame'});
if strcmpi(status, "PASS")
    row.CRCPass = 1;
else
    row.CRCPass = 0;
end
T = row;
end
