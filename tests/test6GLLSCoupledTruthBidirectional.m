function ok = test6GLLSCoupledTruthBidirectional()
%TEST6GLLSCOUPLEDTRUTHBIDIRECTIONAL Ensure coupled truth execution publishes DL and UL from one run.

setup6GRSimToolkit("Verbose", false);

previousScratch = string(getenv("SIXGR_REGRESSION_SCRATCH_ROOT"));
scratchRoot = previousScratch;
ownsScratchRoot = strlength(strtrim(scratchRoot)) == 0;
if ownsScratchRoot
    scratchRoot = string(tempname);
    mkdir(scratchRoot);
    setenv("SIXGR_REGRESSION_SCRATCH_ROOT", scratchRoot);
elseif ~isfolder(scratchRoot)
    mkdir(scratchRoot);
end
scratchCleanup = onCleanup(@() localRestoreScratch(previousScratch, scratchRoot, ownsScratchRoot)); %#ok<NASGU>
tmp = localScratchChild(scratchRoot, "c", ownsScratchRoot);
mkdir(tmp);
c = onCleanup(@() localRemoveFolder(tmp)); %#ok<NASGU>

baseScenario = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "lls_causal_access_to_data_wiring.yaml");
scenarioPath = fullfile(tmp, "lls_coupled_truth_smoke.yaml");
fid = fopen(scenarioPath, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(baseScenario, '\', '\\') '"],' ...
    '"meta":{"scenario_id":"lls_coupled_truth_smoke","description":"coupled truth smoke","version":"1","owner":"test","maturity_tag":"smoke"},' ...
    '"simulation":{"link_direction":"both","n_frames":1,"n_slots":2,"monte_carlo_iterations":1,"random_seed":23,"snr_db":50,"noise_operating_mode":"standalone_awgn_snr_argument"},' ...
    '"scenario":{"study_mode":"smoke"},' ...
    '"run_control":{"total_slots":2,"warmup_slots":0,"measurement_slots":2,"total_time_ms":2.0,"warmup_time_ms":0,"measurement_time_ms":2.0,"batch_size_links":1,"num_workers":1},' ...
    '"channels":{"model_type":"AWGN","profile":"AWGN","delay_spread_ns":0,"doppler_hz":0,"mobility_kmph":0,"los_enabled":true,"spatial_consistency_enabled":false,"pathloss_enabled":false,"shadow_fading_enabled":false},' ...
    '"mimo":{"mu_mimo_enable":false,"ul_mu_mimo_enable":false},' ...
    '"pdsch":{"execution_profile":"scheduler_truth"},' ...
    '"pusch":{"execution_profile":"scheduler_truth"},' ...
    '"random_access":{"enabled":false,"msg3_enabled":false},' ...
    '"random_access_evidence":{"four_step_ra_required":false,"msg1_prach_required":false,"msg2_rar_pdcch_pdsch_required":false,"msg3_pusch_required":false,"msg4_contention_resolution_required":false,"ra_rnti_decode_required":false,"rar_mac_ce_decode_required":false,"timing_advance_required":false,"contention_resolution_identity_required":false,"require_runtime_stage_waveforms":false,"allow_runtime_stage_waveform_composition":false},' ...
    '"reference_signals":{"srs_periodicity_slots":1,"srs_slot_within_period":1,"srs":{"period_offset":0},"trs_enabled":false,"tracking_rs_enabled":false},' ...
    '"users":{"enabled":true,"n_users":2,"rnti_start":201,"seed_stride":17,' ...
    '"execution_model":"slot_coupled_truth","beam_selection_strategy":"fixed_first_beam","save_user_tables":true},' ...
    '"link_adaptation":{"fixed_or_amc":"fixed","operating_point_mode":"fixed","outer_loop_flag":false,"inner_loop_flag":false,' ...
    '"pdcch_link_adaptation_policy":"fixed","pdsch_link_adaptation_policy":"fixed","pusch_link_adaptation_policy":"fixed",' ...
    '"rank_adaptation_policy":"fixed","al_adaptation_policy":"fixed","beam_adaptation_policy":"fixed"},' ...
    '"control_gating":{"pbch_required":false,"prach_required":false,"pdcch_required":false,"srs_required":false,"srs_max_age_slots":4,"trs_required":false,"trs_max_age_slots":4},' ...
    '"output":{"save_figures":false,"save_png":false,"save_mat":false,"phy_signal_diagnostic_enabled":false,"publication_mode":"smoke","profile":"lls_coupled_truth_smoke",' ...
    '"live_publish_frame_interval":1,"live_heavy_refresh_interval_frames":3}}']);
fclose(fid);

out = run_6g_phy_lls_single(scenarioPath, tmp, "smoke");
assert(out.Ok, "Coupled truth bidirectional scenario should complete cleanly.");

runFolder = char(string(out.RunFolder));
dlFile = fullfile(runFolder, "air_interface", "csv", "dl_pdsch_trials.csv");
ulFile = fullfile(runFolder, "air_interface", "csv", "ul_pusch_trials.csv");
summaryFile = fullfile(runFolder, "air_interface", "csv", "multiuser_user_summary.csv");
coverageFile = fullfile(runFolder, "reports", "csv", "live_coverage_layer.csv");
userPerfFile = fullfile(runFolder, "reports", "csv", "live_user_performance_snapshot.csv");
harqFile = fullfile(runFolder, "harq", "csv", "live_harq_observation_timeline.csv");
chanEstFile = fullfile(runFolder, "reports", "csv", "live_channel_estimation_tti.csv");
stageFile = fullfile(runFolder, "air_interface", "reports", "csv", "live_stage_status.csv");
dlGrantFile = fullfile(runFolder, "packet_flow", "csv", "live_dl_scheduler_grants.csv");
ulGrantFile = fullfile(runFolder, "packet_flow", "csv", "live_ul_scheduler_grants.csv");
slotTraceFile = fullfile(runFolder, "reports", "csv", "slot_trace.csv");
runStateFile = fullfile(runFolder, "reports", "csv", "run_state.csv");
prachFile = fullfile(runFolder, "air_interface", "csv", "prach_trials.csv");
pdcchFile = fullfile(runFolder, "air_interface", "csv", "pdcch_trials.csv");
srsFile = fullfile(runFolder, "air_interface", "csv", "srs_trials.csv");
trsFile = fullfile(runFolder, "air_interface", "csv", "trs_trials.csv");
mimoSummaryFile = fullfile(runFolder, "beamforming", "csv", "mimo_configured_vs_effective.csv");
mimoGateFile = fullfile(runFolder, "beamforming", "csv", "mimo_strict_gate_summary.csv");

assert(exist(dlFile, "file") == 2, "Missing coupled-truth DL trials CSV.");
assert(exist(ulFile, "file") == 2, "Missing coupled-truth UL trials CSV.");
assert(exist(summaryFile, "file") == 2, "Missing coupled-truth multi-user summary CSV.");
assert(exist(coverageFile, "file") == 2, "Missing coupled-truth live coverage layer CSV.");
assert(exist(userPerfFile, "file") == 2, "Missing coupled-truth live user performance CSV.");
assert(exist(harqFile, "file") == 2, "Missing coupled-truth live HARQ timeline CSV.");
assert(exist(chanEstFile, "file") == 2, "Missing coupled-truth live channel-estimation CSV.");
assert(exist(stageFile, "file") == 2, "Missing coupled-truth live stage CSV.");
assert(exist(dlGrantFile, "file") == 2, "Missing coupled-truth DL scheduler grant CSV.");
assert(exist(ulGrantFile, "file") == 2, "Missing coupled-truth UL scheduler grant CSV.");
assert(exist(slotTraceFile, "file") == 2, "Missing canonical coupled-truth SlotTrace CSV.");
assert(exist(runStateFile, "file") == 2, "Missing canonical coupled-truth RunState CSV.");
assert(exist(prachFile, "file") ~= 2, ...
    "Disabled PRACH with zero observations must not publish a header-only primary CSV.");
assert(exist(pdcchFile, "file") == 2, "Missing coupled-truth mirrored PDCCH CSV.");
assert(exist(srsFile, "file") == 2, "Missing coupled-truth mirrored SRS CSV.");
assert(exist(trsFile, "file") ~= 2, ...
    "Disabled TRS with zero observations must not publish a header-only primary CSV.");
assert(exist(mimoSummaryFile, "file") == 2, "Missing coupled-truth MIMO configured/effective CSV.");
assert(exist(mimoGateFile, "file") == 2, "Missing coupled-truth MIMO strict-gate CSV.");

dl = readtable(dlFile, "VariableNamingRule", "preserve");
ul = readtable(ulFile, "VariableNamingRule", "preserve");
summary = readtable(summaryFile, "VariableNamingRule", "preserve");
coverage = readtable(coverageFile, "VariableNamingRule", "preserve");
userPerf = readtable(userPerfFile, "VariableNamingRule", "preserve");
harq = readtable(harqFile, "VariableNamingRule", "preserve");
chanEst = readtable(chanEstFile, "VariableNamingRule", "preserve");
stage = readtable(stageFile, "VariableNamingRule", "preserve");
dlGrant = readtable(dlGrantFile, "VariableNamingRule", "preserve");
ulGrant = readtable(ulGrantFile, "VariableNamingRule", "preserve");
slotTrace = readtable(slotTraceFile, "VariableNamingRule", "preserve");
runState = readtable(runStateFile, "VariableNamingRule", "preserve");
prach = table();
pdcch = readtable(pdcchFile, "VariableNamingRule", "preserve");
srs = readtable(srsFile, "VariableNamingRule", "preserve");
trs = table();
mimoSummary = readtable(mimoSummaryFile, "VariableNamingRule", "preserve");
mimoGate = readtable(mimoGateFile, "VariableNamingRule", "preserve");

assert(~isempty(dl), "Coupled truth DL trials must not be empty.");
assert(~isempty(ul), "Coupled truth UL trials must not be empty.");
assert(~isempty(coverage), "Coupled truth coverage layer must not be empty.");
assert(~isempty(userPerf), "Coupled truth user performance snapshot must not be empty.");
assert(~isempty(harq), "Coupled truth HARQ timeline must not be empty.");
assert(~isempty(chanEst), "Coupled truth channel-estimation trace must not be empty.");
assert(~isempty(stage), "Coupled truth live stage trace must not be empty.");
assert(~isempty(dlGrant), "Coupled truth DL scheduler grant trace must not be empty.");
assert(~isempty(ulGrant), "Coupled truth UL scheduler grant trace must not be empty.");
assert(~isempty(slotTrace), "Coupled truth SlotTrace must not be empty.");
assert(~isempty(runState), "Coupled truth RunState must not be empty.");
assert(isempty(prach), "Disabled PRACH must remain absent from primary runtime evidence.");
assert(~isempty(pdcch), "Coupled truth mirrored PDCCH CSV must not be empty.");
assert(istable(srs), "Coupled truth mirrored SRS CSV must remain readable.");
assert(isempty(trs), "Disabled TRS must remain absent from primary runtime evidence.");
assert(all(string(mimoSummary.RunId) == "smoke") && ...
    all(string(mimoSummary.ScenarioName) == "lls_coupled_truth_smoke"), ...
    "MIMO evidence must keep logical RunId distinct from ScenarioName.");
assert(height(mimoGate) == 8 && all(logical(mimoGate.Pass)), ...
    "Every strict MIMO evidence sub-gate must pass for the coupled truth scenario.");
localAssertExactTBSInputs(dl, "TBSize_bits", "DL trial");
localAssertExactTBSInputs(ul, "TBSize_bits", "UL trial");
localAssertExactTBSInputs(dlGrant, "TBSBits", "DL grant");
localAssertExactTBSInputs(ulGrant, "TBSBits", "UL grant");
assert(numel(unique(double(dl.UEIndex))) >= 2, "Coupled truth DL trials must cover multiple UEs.");
assert(numel(unique(double(ul.UEIndex))) >= 2, "Coupled truth UL trials must cover multiple UEs.");
assert(ismember("ExecutionProfile", dl.Properties.VariableNames) && ...
    all(string(dl.ExecutionProfile) == "scheduler_truth"), ...
    "Coupled scheduler-owned DL trials must retain the scheduler_truth profile.");
assert(ismember("ExecutionProfile", ul.Properties.VariableNames) && ...
    all(string(ul.ExecutionProfile) == "scheduler_truth"), ...
    "Coupled scheduler-owned UL trials must retain the scheduler_truth profile.");
assert(all(string(summary.ExecutionModel) == "slot_coupled_truth"), ...
    "Coupled truth summary must declare slot_coupled_truth honestly.");
assert(all(ismember(["DetectionMetric","NMSEDefinition","NMSEInterpretation"], string(chanEst.Properties.VariableNames))), ...
    "Channel-estimation trace must expose NMSE semantics explicitly.");
assert(all(ismember(["MeasuredWidebandSINR_dB","LargeScaleWidebandSINR_dB","RSRPSource","WidebandSINRSource"], string(coverage.Properties.VariableNames))), ...
    "Coverage layer must expose RF/SINR source semantics explicitly.");
assert(all(ismember(["DLTrialsReady","ULTrialsReady","HARQReady","BeamReady","DLCompletedFrames","ULCompletedFrames"], string(stage.Properties.VariableNames))), ...
    "Live stage trace must expose coupled readiness flags.");
assert(all(ismember(["PBCHAttemptCount","PRACHAttemptCount","SRSAttemptCount","TRSAttemptCount"], string(stage.Properties.VariableNames))), ...
    "Live stage trace must expose cumulative control/reference attempt counters for WebGUI status.");
assert(all(ismember(["GrantReason","TBSBits","PRBCount","MCSIndex","CQIUsed"], string(dlGrant.Properties.VariableNames))), ...
    "DL scheduler grant trace must expose key MAC scheduling fields.");
assert(all(ismember(["GrantReason","TBSBits","PRBCount","MCSIndex","CQIUsed"], string(ulGrant.Properties.VariableNames))), ...
    "UL scheduler grant trace must expose key MAC scheduling fields.");
assert(all(ismember(["SlotTraceID","CanonicalSlot","DLStarted","ULStarted","DLScheduled","ULScheduled","DLTrialRows","ULTrialRows","TraceStatus","ValueSource"], string(slotTrace.Properties.VariableNames))), ...
    "SlotTrace must expose canonical DL/UL slot-state lineage fields.");
assert(all(ismember(["RunStateID","ExecutionModel","SlotTraceRows","DLGrantRows","ULGrantRows","StateStatus","ValueSource"], string(runState.Properties.VariableNames))), ...
    "RunState must expose coupled runtime lineage fields.");
assert(any(logical(slotTrace.DLStarted) & logical(slotTrace.ULStarted)), ...
    "At least one canonical SlotTrace row must contain both DL and UL starts.");
assert(any(logical(slotTrace.DLScheduled) & logical(slotTrace.ULScheduled)), ...
    "At least one canonical SlotTrace row must contain both DL and UL scheduler state.");
assert(max(double(runState.SlotTraceRows)) == height(slotTrace), ...
    "RunState SlotTraceRows must match the exported SlotTrace table height.");
assert(all(string(runState.ExecutionModel) == "slot_coupled_truth"), ...
    "RunState must declare the coupled truth execution model.");
assert(max(double(stage.DLCompletedFrames)) >= 1 && max(double(stage.ULCompletedFrames)) >= 1, ...
    "Coupled truth live stage must track DL and UL completed frames independently.");
if ~isempty(prach)
    assert(max(double(stage.PRACHAttemptCount)) >= height(prach), ...
        "Live stage PRACH attempt count must be cumulative and match mirrored PRACH trial evidence.");
end
if ~isempty(srs)
    assert(max(double(stage.SRSAttemptCount)) >= height(srs), ...
        "Live stage SRS attempt count must be cumulative and match mirrored SRS trial evidence.");
end
if ~isempty(trs)
    assert(max(double(stage.TRSAttemptCount)) >= height(trs), ...
        "Live stage TRS attempt count must be cumulative and match mirrored TRS trial evidence.");
end

dlGrantCheck = dlGrant(:, {'UEIndex','RNTI','Frame','Slot','MCSIndex','Modulation','TBSBits'});
dlGrantCheck.Properties.VariableNames = {'UEIndex','RNTI','Frame','Slot','GrantMCS','GrantModulation','GrantTBSBits'};
ulGrantCheck = ulGrant(:, {'UEIndex','RNTI','Frame','Slot','MCSIndex','Modulation','TBSBits'});
ulGrantCheck.Properties.VariableNames = {'UEIndex','RNTI','Frame','Slot','GrantMCS','GrantModulation','GrantTBSBits'};

dlJoin = innerjoin(dl(:, {'UEIndex','RNTI','Frame','Slot','MCS','Modulation','TBSize_bits'}), dlGrantCheck);
ulJoin = innerjoin(ul(:, {'UEIndex','RNTI','Frame','Slot','MCS','Modulation','TBSize_bits'}), ulGrantCheck);
assert(~isempty(dlJoin), "DL trials and DL grants must share identical Frame/Slot/UE coordinates.");
assert(~isempty(ulJoin), "UL trials and UL grants must share identical Frame/Slot/UE coordinates.");
assert(all(abs(double(dlJoin.MCS) - double(dlJoin.GrantMCS)) < 1e-9), ...
    "DL executed MCS must match the scheduler grant MCS.");
assert(all(abs(double(ulJoin.MCS) - double(ulJoin.GrantMCS)) < 1e-9), ...
    "UL executed MCS must match the scheduler grant MCS.");
assert(all(string(dlJoin.Modulation) == string(dlJoin.GrantModulation)), ...
    "DL executed modulation must match the scheduler grant modulation.");
assert(all(string(ulJoin.Modulation) == string(ulJoin.GrantModulation)), ...
    "UL executed modulation must match the scheduler grant modulation.");
assert(all(abs(double(dlJoin.TBSize_bits) - double(dlJoin.GrantTBSBits)) < 1e-9), ...
    "DL executed TBS must match the scheduler grant TBS.");
assert(all(abs(double(ulJoin.TBSize_bits) - double(ulJoin.GrantTBSBits)) < 1e-9), ...
    "UL executed TBS must match the scheduler grant TBS.");

dlGrantSlots = unique(dlGrant(:, {'Frame','Slot'}));
ulGrantSlots = unique(ulGrant(:, {'Frame','Slot'}));
dirField = "GrantDirection";
if ~ismember(dirField, string(pdcch.Properties.VariableNames))
    dirField = "Direction";
end
assert(ismember(dirField, string(pdcch.Properties.VariableNames)), ...
    "PDCCH trace must expose a direction field for DL/UL grant lineage.");
pdcchDL = pdcch(strcmpi(string(pdcch.(char(dirField))), "DL"), :);
pdcchUL = pdcch(strcmpi(string(pdcch.(char(dirField))), "UL"), :);
pdcchDLSlots = unique(pdcchDL(:, {'Frame','Slot'}));
pdcchULGrantSlots = pdcchUL(:, {'Frame','Slot'});
if all(ismember(["GrantFrame","GrantSlot"], string(pdcchUL.Properties.VariableNames)))
    pdcchULGrantSlots = pdcchUL(:, {'GrantFrame','GrantSlot'});
    pdcchULGrantSlots.Properties.VariableNames = {'Frame','Slot'};
end
pdcchULGrantSlots = unique(pdcchULGrantSlots);
assert(~isempty(pdcchDL), "PDCCH trace must include DL-grant control rows.");
assert(~isempty(pdcchUL), "PDCCH trace must include UL-grant control rows.");
assert(all(ismember(table2array(pdcchDLSlots), table2array(dlGrantSlots), 'rows')), ...
    "DL-grant PDCCH rows must be stamped on the same Frame/Slot coordinates as DL grants.");
assert(all(ismember(table2array(pdcchULGrantSlots), table2array(ulGrantSlots), 'rows')), ...
    "UL-grant PDCCH rows must expose GrantFrame/GrantSlot coordinates matching UL grants.");
if all(ismember(["ControlSlot","GrantSlot","K2Slots"], string(pdcchUL.Properties.VariableNames)))
    lineageRows = pdcchUL(isfinite(double(pdcchUL.ControlSlot)) & isfinite(double(pdcchUL.GrantSlot)) & isfinite(double(pdcchUL.K2Slots)), :);
    assert(~isempty(lineageRows), "UL-grant PDCCH rows must expose K2 control-slot lineage.");
    assert(all(abs((double(lineageRows.GrantSlot) - double(lineageRows.ControlSlot)) - double(lineageRows.K2Slots)) < 1e-9), ...
        "UL-grant PDCCH K2 lineage must equal GrantSlot minus ControlSlot.");
end
if ~isempty(srs)
    assert(all(ismember(["LastSuccessfulSRSSlot","SRSAgeSlots","SRSValid"], string(ulGrant.Properties.VariableNames))), ...
        "UL grants must expose SRS freshness lineage.");
    for i = 1:height(ulGrant)
        lastSRS = double(ulGrant.LastSuccessfulSRSSlot(i));
        grantSlot = double(ulGrant.Slot(i));
        hasLineage = isfinite(lastSRS);
        hasValidSRS = logical(ulGrant.SRSValid(i));
        if hasValidSRS || hasLineage
            assert(hasLineage && lastSRS <= grantSlot, ...
                "UL grants with valid or stale SRS lineage must point to an earlier or same-slot SRS observation.");
            assert(abs(double(ulGrant.SRSAgeSlots(i)) - (grantSlot - lastSRS)) < 1e-9, ...
                "UL grant SRS age must equal grant slot minus the last successful SRS slot.");
            hasSRSObservation = any(double(srs.UEIndex) == double(ulGrant.UEIndex(i)) & double(srs.Slot) == lastSRS);
            assert(hasSRSObservation, ...
                "UL grant SRS freshness lineage must point back to an exported SRS observation.");
        else
            assert(~isfinite(double(ulGrant.SRSAgeSlots(i))), ...
                "UL grants without SRS lineage must leave SRS age unavailable rather than fabricating freshness.");
        end
    end
end

ok = true;
end

function localAssertExactTBSInputs(T, tbsField, label)
required = ["TBSInputModulation","TBSInputNumLayers","TBSInputNPRB", ...
    "TBSInputNREPerPRB","TBSInputTargetCodeRate","TBSInputXOverhead", ...
    "TBSInputSource",string(tbsField)];
missing = required(~ismember(required, string(T.Properties.VariableNames)));
assert(isempty(missing), "%s evidence is missing exact TBS columns: %s", ...
    label, strjoin(missing, ", "));
source = lower(strtrim(string(T.TBSInputSource)));
assert(all(strlength(source) > 0) && ...
    ~any(contains(source, ["proxy","fallback","synthetic"])), ...
    "%s TBS input source must identify exact transmitter/grant accounting.", label);
for rowIdx = 1:height(T)
    modulation = char(string(T.TBSInputModulation(rowIdx)));
    layers = double(T.TBSInputNumLayers(rowIdx));
    nPRB = double(T.TBSInputNPRB(rowIdx));
    nRE = double(T.TBSInputNREPerPRB(rowIdx));
    rate = double(T.TBSInputTargetCodeRate(rowIdx));
    xOverhead = double(T.TBSInputXOverhead(rowIdx));
    assert(strlength(string(modulation)) > 0 && isfinite(layers) && layers >= 1 && ...
        isfinite(nPRB) && nPRB >= 1 && isfinite(nRE) && nRE > 0 && ...
        isfinite(rate) && rate > 0 && rate < 1 && isfinite(xOverhead) && xOverhead >= 0, ...
        "%s row %d has incomplete exact TBS inputs.", label, rowIdx);
    expected = double(nrTBS(modulation, layers, nPRB, nRE, rate, xOverhead));
    observed = double(T.(char(tbsField))(rowIdx));
    assert(isfinite(observed) && round(observed) == round(expected), ...
        "%s row %d TBS mismatch: expected %d from exact inputs, observed %d.", ...
        label, rowIdx, round(expected), round(observed));
end
end

function localRestoreScratch(previousScratch, scratchRoot, ownsScratchRoot)
setenv("SIXGR_REGRESSION_SCRATCH_ROOT", previousScratch);
if ownsScratchRoot
    localRemoveFolder(scratchRoot);
end
end

function pathValue = localScratchChild(scratchRoot, prefix, ownsScratchRoot)
if ownsScratchRoot
    pathValue = fullfile(scratchRoot, prefix);
else
    token = char(java.util.UUID.randomUUID());
    pathValue = fullfile(scratchRoot, prefix + string(token(1:8)));
end
end

function localRemoveFolder(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
