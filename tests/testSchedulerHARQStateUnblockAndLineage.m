function ok = testSchedulerHARQStateUnblockAndLineage()
%TESTSCHEDULERHARQSTATEUNBLOCKANDLINEAGE Guard HARQ unblock and PF lineage.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

localAssertHARQStaleRelease();
localAssertPFCandidateLineage();
localAssertRuntimeDecisionExport();

ok = true;
end

function localAssertHARQStaleRelease()
cfg = sixgr.config.defaultConfig();
cfg.mac.harq.enable = true;
cfg.mac.harq.numProcesses = 2;
cfg.mac.harq.maxRetx = 3;
cfg.mac.harq.staleProcessTimeoutSlots = 4;

harq = sixgr.l2.mac.HARQEntity(cfg, "Direction", "DL");
rnti = 101;

txp1 = harq.allocate(rnti, 1, 100, "NewData", true);
harq.onTx(rnti, txp1.HARQ.HarqID, uint8(ones(800, 1)), struct("TBSBits", 800), 1);
txp2 = harq.allocate(rnti, 2, 100, "NewData", true);
harq.onTx(rnti, txp2.HARQ.HarqID, uint8(ones(800, 1)), struct("TBSBits", 800), 2);

assert(~harq.hasFreeProcess(rnti, 3), ...
    "HARQ must report no free process before the stale-process timeout.");
assert(harq.hasFreeProcess(rnti, 7), ...
    "HARQ must release stale active processes once the timeout has elapsed.");
assert(double(harq.Stats.TimeoutDrop) >= 2, ...
    "HARQ timeout releases must be counted as timeout drops, not ACKs.");

txp3 = harq.allocate(rnti, 7, 100, "NewData", true);
assert(~logical(sixgr.util.structGet(txp3, "NoFreeProcess", false)), ...
    "A new TB must be schedulable after stale HARQ release.");
staleBefore = double(harq.Stats.StaleFeedbackIgnored);
harq.onFeedback(rnti, txp1.HARQ.HarqID, false, "SourceSlot", 1);
assert(double(harq.Stats.StaleFeedbackIgnored) == staleBefore + 1, ...
    "Late feedback for a released/reused HARQ process must be ignored.");
end

function localAssertPFCandidateLineage()
cfg = sixgr.config.defaultConfig();
cfg.mac.scheduler.maxUEPerSlot = 1;
cfg.mac.scheduler.minPRBPerUE = 4;
cfg.mac.scheduler.maxPRBAllocationPerUE = 12;
cfg.mac.scheduler.muMimoEnabled = false;
cfg.mac.harq.enable = false;

sched = sixgr.l2.mac.SchedulerPF(cfg, "Direction", "DL", "HARQ", []);
ues = repmat(struct("RNTI", 0, "CQI", 8, "RI", 1, ...
    "DLBufferBytes", 6000, "ULBufferBytes", 0, ...
    "ControlEligible", true, "GrantControlState", "ok"), 1, 2);
ues(1).RNTI = 201;
ues(2).RNTI = 202;
ues(2).CQI = 10;

[grants, info] = sched.schedule(11, ues, struct("PRBSet", 0:23, "SymbolAllocation", [0 14]));
assert(~isempty(grants), "PF scheduler must produce at least one grant for non-empty buffers.");
assert(isfield(info, "CandidateTable") && istable(info.CandidateTable), ...
    "PF scheduler must return a CandidateTable.");
cand = info.CandidateTable;
required = ["PFMetric","InstantRate_bps","AvgThroughput_bps","Scheduled","Rejected","RejectionReason","PFRank"];
assert(all(ismember(required, string(cand.Properties.VariableNames))), ...
    "PF CandidateTable must expose PF metric, rate history, selected flag, and rejection reason.");
assert(height(cand) >= 2, "PF CandidateTable must include all active UE candidates.");
assert(sum(logical(cand.Scheduled)) == numel(grants), ...
    "PF CandidateTable scheduled rows must match selected grants.");
assert(any(~logical(cand.Scheduled) & string(cand.RejectionReason) == "NOT_SELECTED_LOWER_PF_OR_RESOURCE_LIMIT"), ...
    "PF CandidateTable must explain unselected candidates instead of omitting them.");
end

function localAssertRuntimeDecisionExport()
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

cfg = sixgr.config.defaultConfig();
cfg.mac.scheduler.maxUEPerSlot = 1;
cfg.mac.scheduler.minPRBPerUE = 4;
cfg.mac.scheduler.maxPRBAllocationPerUE = 12;
cfg.mac.scheduler.muMimoEnabled = false;
cfg.mac.harq.staleProcessTimeoutSlots = 4;
cfg = localDisableControlGating(cfg);

multiUser = struct("Enabled", true, "NumUsers", 2, "RNTIStart", 501, ...
    "ExecutionModel", "slot_coupled_truth");
state = sixgr.truth.CoupledTruthRuntime.initialize(cfg, tmp, multiUser, struct(), 1);
state = sixgr.truth.CoupledTruthRuntime.advanceFrame(state, cfg, multiUser, 1, 30);
state.CurrentServingIdx(:) = 1;
state.DLQueueBits(:) = 120000;
state.ULQueueBits(:) = 0;
state.ControlEligibility(:) = true;
state.SchedulingEligibility(:) = true;
state.CellAcquisitionState(:) = "acquired";
state.AccessState(:) = "succeeded";
state.SRSValidityState(:) = "valid";
state.CSIValidityState(:) = "fresh_srs";
state = sixgr.truth.CoupledTruthRuntime.startSlot(state, cfg, "DL", 1, 1, 1, 1, 30);
state = sixgr.truth.CoupledTruthRuntime.scheduleDirection(state, cfg, "DL");
assert(istable(state.SchedulerDecisionTable) && ~isempty(state.SchedulerDecisionTable), ...
    "Coupled runtime must collect scheduler candidate decision rows.");

state = sixgr.truth.CoupledTruthRuntime.writeTables(state, tmp);
layout = sixgr.report.resultLayout(tmp);
decisionPath = fullfile(layout.PacketFlowCSVDir, "scheduler_decision_log.csv");
summaryPath = fullfile(layout.PacketFlowCSVDir, "scheduler_ue_summary.csv");
assert(exist(decisionPath, "file") == 2, "scheduler_decision_log.csv must be exported.");
assert(exist(summaryPath, "file") == 2, "scheduler_ue_summary.csv must be exported.");

decisionT = readtable(decisionPath, "VariableNamingRule", "preserve");
summaryT = readtable(summaryPath, "VariableNamingRule", "preserve");
assert(all(ismember(["PFMetric","RejectionReason","CandidateDecisionRowsAvailable"], ...
    string(decisionT.Properties.VariableNames))), ...
    "scheduler_decision_log.csv must carry PF lineage and candidate availability.");
assert(any(logical(decisionT.CandidateDecisionRowsAvailable)), ...
    "scheduler_decision_log.csv rows must be marked as real candidate decisions.");
assert(all(ismember(["UEIndex","RNTI","ScheduledGrantCount","ScheduledFrac"], ...
    string(summaryT.Properties.VariableNames))), ...
    "scheduler_ue_summary.csv must carry UE-level balance fields.");
end

function cfg = localDisableControlGating(cfg)
cfg = sixgr.util.structSet(cfg, "run.controlGating.pbchRequired", false);
cfg = sixgr.util.structSet(cfg, "run.controlGating.prachRequired", false);
cfg = sixgr.util.structSet(cfg, "run.controlGating.pdcchRequired", false);
cfg = sixgr.util.structSet(cfg, "run.controlGating.srsRequired", false);
cfg = sixgr.util.structSet(cfg, "run.controlGating.trsRequired", false);
cfg = sixgr.util.structSet(cfg, "run.controlGating.srsMaxAgeSlots", 1);
cfg = sixgr.util.structSet(cfg, "run.controlGating.trsMaxAgeSlots", 1);
end
