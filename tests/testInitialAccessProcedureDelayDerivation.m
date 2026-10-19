function ok = testInitialAccessProcedureDelayDerivation()
%TESTINITIALACCESSPROCEDUREDELAYDERIVATION Runtime-event delay, no proxy.

setup6GRSimToolkit("Verbose", false);
events = ["SSB_DETECTED"; "PBCH_DECODED"; "PRACH_MSG1_DETECTED"; ...
    "MSG2_RAR_DECODED"; "MSG3_PUSCH_COMPLETED"; ...
    "MSG4_CONTENTION_RESOLUTION_COMPLETED"];
slots = [1; 1; 30; 31; 32; 33];
slotDuration_s = repmat(0.5e-3, numel(events), 1);
times_s = (slots - 1) .* slotDuration_s;
T = table(ones(numel(events), 1), events, slots, times_s, slotDuration_s, ...
    false(numel(events), 1), ...
    'VariableNames', {'UEIndex','EventName','Slot','Time_s','SlotDuration_s','CompleteFlag'});

actual = sixgr.truth.deriveInitialAccessProcedureDelay(T);
terminal = actual.EventName == "MSG4_CONTENTION_RESOLUTION_COMPLETED";
assert(abs(actual.EventElapsed_ms(terminal)-16)<1e-12);
assert(abs(actual.ProcedureDelay_ms(terminal)-1e3*( ...
    actual.ProcedureIntervalEndExclusive_s(terminal)-actual.ProcedureIntervalStart_s(terminal)))<1e-12);
assert(abs(actual.EventElapsed_ms(terminal)-1e3*( ...
    actual.ProcedureEndTime_s(terminal)-actual.ProcedureStartTime_s(terminal)))<1e-12);
assert(nnz(terminal) == 1 && logical(actual.CompleteFlag(terminal)), ...
    "Measured Msg4 contention resolution must terminate four-step access.");
assert(abs(actual.ProcedureDelay_ms(terminal) - 16.5) < 1e-12 && ...
    actual.AccessDelay_ms(terminal) == actual.ProcedureDelay_ms(terminal), ...
    "Access delay must come from the runtime event interval plus terminal slot duration.");

incomplete = T(1:5, :);
incomplete = sixgr.truth.deriveInitialAccessProcedureDelay(incomplete);
assert(~any(incomplete.CompleteFlag) && ...
    all(~isfinite(incomplete.ProcedureDelay_ms)), ...
    "Missing Msg4 evidence must remain incomplete without a substitute delay.");

rrcEvents = [events; "RRC_SETUP_COMPLETE_ACCEPTED"];
rrcSlots = [slots; 34];
rrcSlotDuration_s = repmat(0.5e-3, numel(rrcEvents), 1);
rrcTimes_s = (rrcSlots - 1) .* rrcSlotDuration_s;
rrcTable = table(ones(numel(rrcEvents), 1), rrcEvents, rrcSlots, ...
    rrcTimes_s, rrcSlotDuration_s, false(numel(rrcEvents), 1), ...
    'VariableNames', {'UEIndex','EventName','Slot','Time_s', ...
    'SlotDuration_s','CompleteFlag'});
beforeSetupComplete = sixgr.truth.deriveInitialAccessProcedureDelay( ...
    rrcTable(1:end-1, :), "RequireRRCSetupComplete", true);
assert(~any(beforeSetupComplete.CompleteFlag), ...
    "Msg4 must not terminate access when waveform RRCSetupComplete is required.");
% A prior report may have used the wrong four-step-only policy. Reapplying
% the installed RRC policy must not trust its stale Msg4 completion flag.
wrongPolicy = sixgr.truth.deriveInitialAccessProcedureDelay(rrcTable(1:end-1,:));
revalidated = sixgr.truth.deriveInitialAccessProcedureDelay( ...
    wrongPolicy,"RequireRRCSetupComplete",true);
assert(~any(revalidated.CompleteFlag) && all(~isfinite(revalidated.ProcedureDelay_ms)), ...
    'A stale pre-RRC completion flag must not bypass the installed completion policy.');
withSetupComplete = sixgr.truth.deriveInitialAccessProcedureDelay( ...
    rrcTable, "RequireRRCSetupComplete", true);
rrcTerminal = withSetupComplete.EventName == "RRC_SETUP_COMPLETE_ACCEPTED";
assert(nnz(rrcTerminal) == 1 && logical(withSetupComplete.CompleteFlag(rrcTerminal)), ...
    "Required waveform RRCSetupComplete must be the terminal access event.");
assert(abs(withSetupComplete.ProcedureDelay_ms(rrcTerminal) - 17) < 1e-12, ...
    "RRC-complete access delay must use the actual terminal runtime slot.");
assert(isequaln(withSetupComplete,sixgr.truth.deriveInitialAccessProcedureDelay( ...
    withSetupComplete,"RequireRRCSetupComplete",true)), ...
    'Recomputing the same complete event clock must be idempotent.');
% Missing/invalid group identity must not preserve an old completed sample.
for invalidIdentity=[NaN Inf 0 -1 1.5]
    invalid=withSetupComplete;
    invalid.UEIndex(:)=invalidIdentity;
    invalid=sixgr.truth.deriveInitialAccessProcedureDelay(invalid,"RequireRRCSetupComplete",true);
    assert(~any(invalid.CompleteFlag) && all(isnan(invalid.ProcedureDelay_ms)), ...
        'A completion requires a valid UE identity, not a retained flag or latency.');
    invalid=withSetupComplete;
    invalid.SweepPointIndex=repmat(invalidIdentity,height(invalid),1);
    invalid=sixgr.truth.deriveInitialAccessProcedureDelay(invalid,"RequireRRCSetupComplete",true);
    assert(~any(invalid.CompleteFlag) && all(isnan(invalid.ProcedureDelay_ms)), ...
        'A completion requires a valid sweep identity, not a retained flag or latency.');
end

% Exercise the production control-trace exporter with the live runtime's
% installed policy, and separately with the persisted immutable snapshot.
root=tempname; mkdir(root);
cleanup=onCleanup(@() rmdir(root,'s')); %#ok<NASGU>
cfg=struct('initial_access',struct('rrc',struct('require_setup_complete',true)));
runtime=struct('InitialAccessLifecycleTraceTable',wrongPolicy, ...
    'CoupledRuntime',struct('CfgMobility',cfg));
trace=sixgr.truth.exportControlPlaneTraces(root,struct(),runtime);
exported=readtable(trace.InitialAccessLifecycleTraceCSV,'TextType','string');
assert(~any(exported.CompleteFlag),'Control export must not complete access before required RRC.');
sixgr.util.ensureFolder(fullfile(root,'meta'));
sixgr.util.jsonWrite(fullfile(root,'meta','scenario_config_resolved.json'),cfg);
runtime=struct('InitialAccessLifecycleTraceTable',rrcTable);
trace=sixgr.truth.exportControlPlaneTraces(root,struct(),runtime);
exported=readtable(trace.InitialAccessLifecycleTraceCSV,'TextType','string');
assert(nnz(exported.CompleteFlag)==1 && ...
    exported.EventName(logical(exported.CompleteFlag))=="RRC_SETUP_COMPLETE_ACCEPTED" && ...
    abs(exported.ProcedureDelay_ms(logical(exported.CompleteFlag))-17)<1e-12, ...
    'Snapshot-backed control export must retain the decoded RRC terminal event.');

% Independent sweep points must never borrow an access event from another
% operating point. Point 1 is complete; point 2 deliberately lacks Msg3.
sweepOne = T;
sweepOne.SweepPointIndex = ones(height(sweepOne), 1);
sweepTwo = T([1 2 3 4 6], :);
sweepTwo.SweepPointIndex = 2 .* ones(height(sweepTwo), 1);
sweepTwo.Slot = sweepTwo.Slot + 40;
sweepTwo.Time_s = (sweepTwo.Slot - 1) .* sweepTwo.SlotDuration_s;
isolated = sixgr.truth.deriveInitialAccessProcedureDelay([sweepOne; sweepTwo]);
pointOneTerminal = isolated.SweepPointIndex == 1 & ...
    isolated.EventName == "MSG4_CONTENTION_RESOLUTION_COMPLETED";
pointTwoTerminal = isolated.SweepPointIndex == 2 & ...
    isolated.EventName == "MSG4_CONTENTION_RESOLUTION_COMPLETED";
assert(logical(isolated.CompleteFlag(pointOneTerminal)) && ...
    ~logical(isolated.CompleteFlag(pointTwoTerminal)), ...
    "Initial-access lifecycle completion must be isolated by SNR sweep point.");
assert(~isfinite(isolated.ProcedureDelay_ms(pointTwoTerminal)), ...
    "An incomplete operating point must not inherit a delay from another point.");

nonCausal = T;
nonCausal.Slot(nonCausal.EventName == "MSG2_RAR_DECODED") = 2;
nonCausal.Time_s = (nonCausal.Slot - 1) .* nonCausal.SlotDuration_s;
try
    sixgr.truth.deriveInitialAccessProcedureDelay(nonCausal);
    error("testInitialAccessProcedureDelayDerivation:ExpectedNonCausalFailure", ...
        "Non-causal lifecycle unexpectedly passed.");
catch cause
    assert(string(cause.identifier) == ...
        "sixgr:truth:InitialAccessLifecycleNonCausal");
end
ok = true;
end
