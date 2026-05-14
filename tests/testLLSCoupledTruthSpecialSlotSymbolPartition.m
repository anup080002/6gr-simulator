function ok = testLLSCoupledTruthSpecialSlotSymbolPartition()
%TESTLLSCOUPLEDTRUTHSPECIALSLOTSYMBOLPARTITION Verify symbol-level special-slot truth in coupled LLS.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

baseScenario = fullfile(pwd, "simulator", "configs", "scenarios", "lls_mimo4x4_multiuser_beamformed_awgn_validation.yaml");
scenarioPath = fullfile(tmp, "lls_coupled_truth_special_slot_symbol_partition.yaml");
fid = fopen(scenarioPath, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(baseScenario, '\', '\\') '"],' ...
    '"meta":{"scenario_id":"lls_coupled_truth_special_slot_symbol_partition","description":"coupled truth special slot symbol partition regression","version":"1","owner":"test","maturity_tag":"regression"},' ...
    '"simulation":{"link_direction":"both","n_frames":1,"n_slots":5,"monte_carlo_iterations":1,"random_seed":31,"snr_db":36,"snr_sweep_offsets_db":[0]},' ...
    '"run_control":{"total_slots":5,"warmup_slots":0,"measurement_slots":5,"total_time_ms":2.5,"warmup_time_ms":0,"measurement_time_ms":2.5,"batch_size_links":1,"num_workers":1},' ...
    '"frame":{"tdd_pattern":"DDDSU","special_slot_downlink_symbols":12,"ul_dl_guard_symbols":1,"special_slot_uplink_symbols":1},' ...
    '"frame_timing":{"tdd_pattern":"DDDSU","special_slot_downlink_symbols":12,"ul_dl_guard_symbols":1,"special_slot_uplink_symbols":1},' ...
    '"users":{"enabled":true,"n_users":2,"rnti_start":601,"seed_stride":17,' ...
    '"execution_model":"slot_coupled_truth","beam_selection_strategy":"fixed_first_beam","save_user_tables":true},' ...
    '"control_gating":{"pbch_required":false,"prach_required":false,"pdcch_required":false,"srs_required":false,"srs_max_age_slots":1,"trs_required":false,"trs_max_age_slots":1},' ...
    '"sweeps_and_matrix":{"snr_sweep":{"enabled":false,"values_db":[]}},' ...
    '"output":{"save_figures":false,"save_mat":false,"save_png":false,"profile":"lls_coupled_truth_special_slot_symbol_partition",' ...
    '"live_publish_frame_interval":1,"live_heavy_refresh_interval_frames":3}}']);
fclose(fid);

scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "preflight"));
partition = sixgr.util.resolveTDDSlotPartition(cfg, 4);
assert(string(partition.SlotLabel) == "S", "Canonical slot 4 must resolve to the configured special slot.");
assert(logical(partition.IsSpecialSlot), "Canonical slot 4 must be marked as a special slot.");
assert(isequal(double(partition.DLSymbolAllocation), [0 12]), ...
    "Special-slot DL allocation must follow the configured 12-symbol downlink partition.");
assert(isequal(double(partition.GuardSymbolAllocation), [12 1]), ...
    "Special-slot guard allocation must follow the configured single-symbol guard.");
assert(isequal(double(partition.ULSymbolAllocation), [13 1]), ...
    "Special-slot UL allocation must follow the configured single-symbol uplink partition.");

slotDuration_s = max(eps, double(sixgr.util.structGet(cfg, "phy.numerology.slotDuration_ms", 0.5)) / 1e3);
opt = struct( ...
    "LinkDuration_s", max(double(cfg.run.totalSlots) * slotDuration_s, slotDuration_s), ...
    "LinkMaxSimFrames", double(cfg.run.totalSlots), ...
    "LinkSNR_dB", double(cfg.channel.snr_dB), ...
    "LinkSNRGrid_dB", double(cfg.channel.snr_dB), ...
    "LinkSweepFrames", 1, ...
    "LinkSweepTrialsPerSNR", double(cfg.run.totalSlots), ...
    "LinkReferenceSweepFrames", double(cfg.run.totalSlots), ...
    "LinkSweepMaxPoints", 1, ...
    "LinkAdaptiveSweepEnabled", false, ...
    "LinkAdaptiveSweepStep_dB", 2, ...
    "LinkAdaptiveSweepMaxPoints", 1, ...
    "SaveFigures", false);
airInterfaceFolder = fullfile(tmp, "special_slot_symbol_partition_run", "air_interface");
caught = [];
out = struct("Ok", false);
evalc('try, out = sixgr.truth.runWaveformLinkBundle(cfg, airInterfaceFolder, opt); catch ME, caught = ME; end');
if ~isempty(caught)
    assert(contains(string(caught.identifier), "PrimarySummarySkipped") || ...
        contains(string(caught.message), "Primary link KPI summary contains skipped rows"), ...
        "Special-slot regression should only tolerate the known primary-summary coverage guard.");
else
    assert(logical(sixgr.util.structGet(out, "Ok", false)), ...
        "Special-slot coupled truth bundle should complete cleanly when the summary guard does not fire.");
end

runFolder = fileparts(airInterfaceFolder);
dlGrantFile = fullfile(runFolder, "packet_flow", "csv", "live_dl_scheduler_grants.csv");
ulGrantFile = fullfile(runFolder, "packet_flow", "csv", "live_ul_scheduler_grants.csv");
slotTraceFile = fullfile(runFolder, "reports", "csv", "slot_trace.csv");
runStateFile = fullfile(runFolder, "reports", "csv", "run_state.csv");

assert(exist(dlGrantFile, "file") == 2, "Missing DL grant trace for the special-slot regression.");
assert(exist(ulGrantFile, "file") == 2, "Missing UL grant trace for the special-slot regression.");
assert(exist(slotTraceFile, "file") == 2, "Missing canonical slot trace for the special-slot regression.");
assert(exist(runStateFile, "file") == 2, "Missing run-state export for the special-slot regression.");

dlGrant = readtable(dlGrantFile, "VariableNamingRule", "preserve");
ulGrant = readtable(ulGrantFile, "VariableNamingRule", "preserve");
slotTrace = readtable(slotTraceFile, "VariableNamingRule", "preserve");
runState = readtable(runStateFile, "VariableNamingRule", "preserve");

assert(all(ismember(["SpecialSlotActive","DLSymbolStart","DLNumSymbols","GuardSymbolStart","GuardNumSymbols","ULSymbolStart","ULNumSymbols"], ...
    string(slotTrace.Properties.VariableNames))), ...
    "SlotTrace must expose symbol-level DL/guard/UL partition evidence for special slots.");
assert(all(ismember(["CurrentSlotIsSpecial","CurrentSlotDLSymbolStart","CurrentSlotDLNumSymbols", ...
    "CurrentSlotGuardSymbolStart","CurrentSlotGuardNumSymbols","CurrentSlotULSymbolStart","CurrentSlotULNumSymbols"], ...
    string(runState.Properties.VariableNames))), ...
    "RunState must expose symbol-level special-slot fields.");
assert(all(ismember(["SymbolStart","NumSymbols"], string(dlGrant.Properties.VariableNames))) && ...
    all(ismember(["SymbolStart","NumSymbols"], string(ulGrant.Properties.VariableNames))), ...
    "Grant traces must expose the scheduled symbol allocation truthfully.");

specialTrace = slotTrace(double(slotTrace.CanonicalSlot) == 4, :);
assert(~isempty(specialTrace), "SlotTrace must include canonical slot 4 for the configured DDDSU special slot.");
assert(all(logical(specialTrace.SpecialSlotActive)), ...
    "Canonical slot 4 must be marked as a special slot in the exported SlotTrace.");
assert(all(double(specialTrace.DLSymbolStart) == 0) && all(double(specialTrace.DLNumSymbols) == 12), ...
    "SlotTrace must export the configured 12-symbol downlink portion for the special slot.");
assert(all(double(specialTrace.GuardSymbolStart) == 12) && all(double(specialTrace.GuardNumSymbols) == 1), ...
    "SlotTrace must export the configured single-symbol guard portion for the special slot.");
assert(all(double(specialTrace.ULSymbolStart) == 13) && all(double(specialTrace.ULNumSymbols) == 1), ...
    "SlotTrace must export the configured single-symbol uplink portion for the special slot.");
assert(any(logical(specialTrace.DLStarted) & logical(specialTrace.ULStarted)), ...
    "The special-slot SlotTrace row must record both DL and UL direction starts.");
assert(any(logical(specialTrace.DLScheduled) & logical(specialTrace.ULScheduled)), ...
    "The special-slot SlotTrace row must record both DL and UL scheduler activity.");

dlSpecial = dlGrant(double(dlGrant.Slot) == 4, :);
ulSpecial = ulGrant(double(ulGrant.Slot) == 4, :);
assert(~isempty(dlSpecial), "DL grant trace must include at least one grant in the configured special slot.");
assert(all(double(dlSpecial.SymbolStart) == 0) && all(double(dlSpecial.NumSymbols) == 12), ...
    "DL grants in the special slot must use only the configured downlink symbol region.");
assert(all(double(dlSpecial.SymbolStart) + double(dlSpecial.NumSymbols) <= 12), ...
    "DL grants in the special slot must end before the guard symbol begins.");
if ~isempty(ulSpecial)
    assert(all(double(ulSpecial.SymbolStart) == 13) && all(double(ulSpecial.NumSymbols) == 1), ...
        "UL grants in the special slot must use only the configured uplink symbol region.");
    assert(all(double(ulSpecial.SymbolStart) >= 13), ...
        "UL grants in the special slot must begin after the guard symbol ends.");
end

multiUser = struct("Enabled", true, "NumUsers", 2, "RNTIStart", 601, "ExecutionModel", "slot_coupled_truth");
stateOneSym = sixgr.truth.CoupledTruthRuntime.initialize(cfg, fullfile(tmp, "direct_runtime_one_symbol"), multiUser, struct(), 5);
stateOneSym = sixgr.truth.CoupledTruthRuntime.advanceFrame(stateOneSym, cfg, multiUser, 4, double(cfg.channel.snr_dB));
stateOneSym.DLQueueBits(:) = max(double(stateOneSym.DLQueueBits(:)), 120000);
stateOneSym.ULQueueBits(:) = max(double(stateOneSym.ULQueueBits(:)), 120000);
stateOneSym.ControlEligibility(:) = true;
stateOneSym.SchedulingEligibility(:) = true;
stateOneSym.CellAcquisitionState(:) = "acquired";
stateOneSym.AccessState(:) = "succeeded";
stateOneSym.SRSValidityState(:) = "valid";
stateOneSym.CSIValidityState(:) = "fresh_srs";
stateOneSym.LastSuccessfulSRSSlotByUE(:) = 4;
stateOneSym.LastSRSObservedSlotByUE(:) = 4;
stateOneSym = sixgr.truth.CoupledTruthRuntime.startSlot(stateOneSym, cfg, "UL", 1, 1, 4, 5, double(cfg.channel.snr_dB));
[~, ulOneSymbolGrants, ~] = sixgr.truth.CoupledTruthRuntime.scheduleDirection(stateOneSym, cfg, "UL");
assert(isempty(ulOneSymbolGrants), ...
    "A one-symbol UL special-slot tail with no data RE must not produce executable UL data grants.");

cfgSched = cfg;
cfgSched = sixgr.util.structSet(cfgSched, "phy.duplex.specialSlot.numDLSymbols", 11);
cfgSched = sixgr.util.structSet(cfgSched, "phy.duplex.specialSlot.numGuardSymbols", 1);
cfgSched = sixgr.util.structSet(cfgSched, "phy.duplex.specialSlot.numULSymbols", 2);
partitionSched = sixgr.util.resolveTDDSlotPartition(cfgSched, 4);
assert(isequal(double(partitionSched.DLSymbolAllocation), [0 11]) && ...
    isequal(double(partitionSched.GuardSymbolAllocation), [11 1]) && ...
    isequal(double(partitionSched.ULSymbolAllocation), [12 2]), ...
    "The scheduler proof configuration must expose an 11+1+2 special-slot partition.");
state = sixgr.truth.CoupledTruthRuntime.initialize(cfgSched, fullfile(tmp, "direct_runtime"), multiUser, struct(), 5);
state = sixgr.truth.CoupledTruthRuntime.advanceFrame(state, cfgSched, multiUser, 4, double(cfgSched.channel.snr_dB));
state.DLQueueBits(:) = max(double(state.DLQueueBits(:)), 120000);
state.ULQueueBits(:) = max(double(state.ULQueueBits(:)), 120000);
state.ControlEligibility(:) = true;
state.SchedulingEligibility(:) = true;
state.CellAcquisitionState(:) = "acquired";
state.AccessState(:) = "succeeded";
state.SRSValidityState(:) = "valid";
state.CSIValidityState(:) = "fresh_srs";
state.LastSuccessfulSRSSlotByUE(:) = 4;
state.LastSRSObservedSlotByUE(:) = 4;

state = sixgr.truth.CoupledTruthRuntime.startSlot(state, cfgSched, "DL", 1, 1, 4, 5, double(cfgSched.channel.snr_dB));
[state, dlDirectGrants, ~] = sixgr.truth.CoupledTruthRuntime.scheduleDirection(state, cfgSched, "DL");
state = sixgr.truth.CoupledTruthRuntime.startSlot(state, cfgSched, "UL", 1, 1, 4, 5, double(cfgSched.channel.snr_dB));
[state, ulDirectGrants, ~] = sixgr.truth.CoupledTruthRuntime.scheduleDirection(state, cfgSched, "UL");

assert(~isempty(dlDirectGrants), ...
    "Direct coupled-runtime scheduling must produce DL grants in the configured special slot when backlog exists.");
assert(~isempty(ulDirectGrants), ...
    "Direct coupled-runtime scheduling must produce UL grants in a schedulable two-symbol UL special-slot tail when backlog exists.");
dlDirectSymbols = localGrantSymbolAllocations(dlDirectGrants);
ulDirectSymbols = localGrantSymbolAllocations(ulDirectGrants);
assert(all(dlDirectSymbols(:,1) == 0) && all(dlDirectSymbols(:,2) == 11), ...
    "Direct DL grants in the schedulable proof slot must inherit the configured 11-symbol downlink partition.");
assert(all(ulDirectSymbols(:,1) == 12) && all(ulDirectSymbols(:,2) == 2), ...
    "Direct UL grants in the schedulable proof slot must inherit the configured two-symbol uplink partition.");

ok = true;
end

function sym = localGrantSymbolAllocations(grants)
sym = zeros(numel(grants), 2);
for i = 1:numel(grants)
    alloc = double(sixgr.util.structGet(grants(i), "SymbolAllocation", [NaN NaN]));
    if numel(alloc) < 2
        alloc = [NaN NaN];
    end
    sym(i, :) = reshape(alloc(1:2), 1, 2);
end
end
