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
state = sixgr.truth.CoupledTruthRuntime.applySRSTrial(state, 1, srsPass);
assert(string(state.SRSValidityState(1)) == "valid", ...
    "SRS pass must move the UE into valid SRS state.");

[stateReady, dlGrantsReady, ~] = sixgr.truth.CoupledTruthRuntime.scheduleDirection(state, cfg, "DL");
assert(~isempty(dlGrantsReady), ...
    "DL grants must appear once PBCH/PRACH gating is satisfied.");
grant = dlGrantsReady(1);
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

stateReady.CurrentSlot = double(stateReady.CurrentSlot) + double(stateReady.ControlGating.SRSMaxAgeSlots) + 1;
stateReady = sixgr.truth.CoupledTruthRuntime.refreshControlState(stateReady);
assert(string(stateReady.SRSValidityState(1)) == "stale", ...
    "SRS freshness gating must age successful SRS into stale state after the configured slot budget.");
assert(string(stateReady.CSIValidityState(1)) == "stale_srs_fallback", ...
    "Stale SRS must switch CSI validity into the conservative fallback state.");

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
