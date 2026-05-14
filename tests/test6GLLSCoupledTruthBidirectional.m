function ok = test6GLLSCoupledTruthBidirectional()
%TEST6GLLSCOUPLEDTRUTHBIDIRECTIONAL Ensure coupled truth execution publishes DL and UL from one run.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

baseScenario = fullfile(pwd, "simulator", "configs", "scenarios", "lls_mimo4x4_multiuser_beamformed_awgn_validation.yaml");
scenarioPath = fullfile(tmp, "lls_coupled_truth_smoke.yaml");
fid = fopen(scenarioPath, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(baseScenario, '\', '\\') '"],' ...
    '"meta":{"scenario_id":"lls_coupled_truth_smoke","description":"coupled truth smoke","version":"1","owner":"test","maturity_tag":"smoke"},' ...
    '"simulation":{"link_direction":"both","n_frames":1,"n_slots":1,"monte_carlo_iterations":1,"random_seed":23,"snr_db":28},' ...
    '"random_access":{"enabled":true,"prach_format":"A1","preamble_length_mode":"short","preamble_count":64,"zero_correlation_zone":8,"detection_threshold":0.5,"msg3_enabled":true,"configuration_index":84,"subcarrier_spacing_khz":30,"root_sequence_index":1,"preamble_index":0},' ...
    '"users":{"enabled":true,"n_users":2,"rnti_start":201,"seed_stride":17,' ...
    '"execution_model":"slot_coupled_truth","beam_selection_strategy":"fixed_first_beam","save_user_tables":true},' ...
    '"control_gating":{"pbch_required":false,"prach_required":false,"pdcch_required":false,"srs_required":false,"srs_max_age_slots":4,"trs_required":false,"trs_max_age_slots":4},' ...
    '"output":{"save_figures":false,"save_mat":false,"profile":"lls_coupled_truth_smoke",' ...
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
assert(exist(prachFile, "file") == 2, "Missing coupled-truth mirrored PRACH CSV.");
assert(exist(pdcchFile, "file") == 2, "Missing coupled-truth mirrored PDCCH CSV.");
assert(exist(srsFile, "file") == 2, "Missing coupled-truth mirrored SRS CSV.");
assert(exist(trsFile, "file") == 2, "Missing coupled-truth mirrored TRS CSV.");

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
prach = readtable(prachFile, "VariableNamingRule", "preserve");
pdcch = readtable(pdcchFile, "VariableNamingRule", "preserve");
srs = readtable(srsFile, "VariableNamingRule", "preserve");
trs = readtable(trsFile, "VariableNamingRule", "preserve");

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
assert(~isempty(prach), "Coupled truth mirrored PRACH CSV must not be empty.");
assert(~isempty(pdcch), "Coupled truth mirrored PDCCH CSV must not be empty.");
assert(istable(srs), "Coupled truth mirrored SRS CSV must remain readable.");
assert(istable(trs), "Coupled truth mirrored TRS CSV must remain readable.");
assert(numel(unique(double(dl.UEIndex))) >= 2, "Coupled truth DL trials must cover multiple UEs.");
assert(numel(unique(double(ul.UEIndex))) >= 2, "Coupled truth UL trials must cover multiple UEs.");
assert(all(string(summary.ExecutionModel) == "slot_coupled_truth"), ...
    "Coupled truth summary must declare slot_coupled_truth honestly.");
assert(all(ismember(["DetectionMetric","NMSEDefinition","NMSEInterpretation"], string(chanEst.Properties.VariableNames))), ...
    "Channel-estimation trace must expose NMSE semantics explicitly.");
assert(all(ismember(["MeasuredWidebandSINR_dB","LargeScaleWidebandSINR_dB","RSRPSource","WidebandSINRSource"], string(coverage.Properties.VariableNames))), ...
    "Coverage layer must expose RF/SINR source semantics explicitly.");
assert(all(ismember(["DLTrialsReady","ULTrialsReady","HARQReady","BeamReady","DLCompletedFrames","ULCompletedFrames"], string(stage.Properties.VariableNames))), ...
    "Live stage trace must expose coupled readiness flags.");
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
pdcchULSlots = unique(pdcchUL(:, {'Frame','Slot'}));
srsSlots = unique(srs(:, {'Frame','Slot'}));
assert(~isempty(pdcchDL), "PDCCH trace must include DL-grant control rows.");
assert(~isempty(pdcchUL), "PDCCH trace must include UL-grant control rows.");
assert(all(ismember(table2array(pdcchDLSlots), table2array(dlGrantSlots), 'rows')), ...
    "DL-grant PDCCH rows must be stamped on the same Frame/Slot coordinates as DL grants.");
assert(all(ismember(table2array(pdcchULSlots), table2array(ulGrantSlots), 'rows')), ...
    "UL-grant PDCCH rows must be stamped on the same Frame/Slot coordinates as UL grants.");
if ~isempty(srs)
    assert(all(ismember(["LastSuccessfulSRSSlot","SRSAgeSlots"], string(ulGrant.Properties.VariableNames))), ...
        "UL grants must expose SRS freshness lineage.");
    for i = 1:height(ulGrant)
        lastSRS = double(ulGrant.LastSuccessfulSRSSlot(i));
        grantSlot = double(ulGrant.Slot(i));
        assert(isfinite(lastSRS) && lastSRS <= grantSlot, ...
            "UL grants with valid SRS must point to an earlier or same-slot SRS observation.");
        assert(abs(double(ulGrant.SRSAgeSlots(i)) - (grantSlot - lastSRS)) < 1e-9, ...
            "UL grant SRS age must equal grant slot minus the last successful SRS slot.");
        hasSRSObservation = any(double(srs.UEIndex) == double(ulGrant.UEIndex(i)) & double(srs.Slot) == lastSRS);
        assert(hasSRSObservation, ...
            "UL grant SRS freshness lineage must point back to an exported SRS observation.");
    end
end

ok = true;
end
