function ok = testSchedulerHARQStateUnblockAndLineage()
%TESTSCHEDULERHARQSTATEUNBLOCKANDLINEAGE Guard HARQ unblock and PF lineage.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

localAssertHARQEventDrivenRelease();
localAssertPFCandidateLineage();
localAssertRuntimeDecisionExport();

ok = true;
end

function localAssertHARQEventDrivenRelease()
cfg = sixgr.config.defaultConfig();
cfg.mac.harq.enable = true;
cfg.mac.harq.numProcesses = 2;
cfg.mac.harq.maxRetx = 3;

harq = sixgr.l2.mac.HARQEntity(cfg, "Direction", "DL");
rnti = 101;

txp1 = harq.allocate(rnti, 1, 100, "NewData", true);
harq.onTx(rnti, txp1.HARQ.HarqID, uint8(ones(800, 1)), struct("TBSBits", 800), 1);
txp2 = harq.allocate(rnti, 2, 100, "NewData", true);
harq.onTx(rnti, txp2.HARQ.HarqID, uint8(ones(800, 1)), struct("TBSBits", 800), 2);

assert(~harq.hasFreeProcess(rnti, 3), ...
    "HARQ must report no free process while both processes await feedback.");
assert(~harq.hasFreeProcess(rnti, 7), ...
    "HARQ process lifetime must remain event-driven; slot age cannot synthesize release.");
assert(double(harq.Stats.TimeoutDrop) == 0, ...
    "Event-driven HARQ must not synthesize timeout drops.");

harq.onFeedback(rnti, txp1.HARQ.HarqID, true, "SourceSlot", 1);
harq.onFeedback(rnti, txp2.HARQ.HarqID, true, "SourceSlot", 2);
assert(harq.hasFreeProcess(rnti, 7), ...
    "Decoded ACK events must release active HARQ processes.");
assert(double(harq.Stats.Ack) >= 2, ...
    "Decoded ACK releases must be counted as ACKs.");

txp3 = harq.allocate(rnti, 7, 100, "NewData", true);
assert(~logical(sixgr.util.structGet(txp3, "NoFreeProcess", false)), ...
    "A new TB must be schedulable after decoded feedback releases HARQ state.");
staleBefore = double(harq.Stats.StaleFeedbackIgnored);
harq.onFeedback(rnti, txp1.HARQ.HarqID, false, "SourceSlot", 1);
assert(double(harq.Stats.StaleFeedbackIgnored) == staleBefore + 1, ...
    "Late feedback for a released and reused HARQ process must be ignored.");
end

function localAssertPFCandidateLineage()
cfg = sixgr.config.defaultConfig();
assert(string(cfg.run.interferenceExecutionMode) == "none", ...
    ["The YAML-backed core config must give direct production-runtime " ...
    "fixtures an explicit no-interference execution policy."]);
cfg.mac.scheduler.maxUEPerSlot = 1;
cfg.mac.scheduler.minPRBPerUE = 4;
cfg.mac.scheduler.maxPRBAllocationPerUE = 12;
cfg.mac.scheduler.muMimoEnabled = false;
cfg.mac.harq.enable = false;
cfg = withCanonicalSchedulerTiming(cfg);

sched = sixgr.l2.mac.SchedulerPF(cfg, "Direction", "DL", "HARQ", []);
ues = repmat(struct("RNTI", 0, "CQI", 8, "RI", 1, ...
    "DLBufferBytes", 6000, "ULBufferBytes", 0, ...
    "ControlEligible", true, "GrantControlState", "ok"), 1, 2);
ues(1).RNTI = 201;
ues(2).RNTI = 202;
ues(2).CQI = 10;

[grants, info] = sched.schedule(11, ues, struct( ...
    "PRBSet", 0:23, ...
    "ControlSymbolAllocation", [0 2], ...
    "SymbolAllocation", [2 12]));
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
cfg = localDisableControlGating(cfg);
cfg = withCanonicalSchedulerTiming(cfg);
cfg.phy.tddTiming.allowedK0 = 0;
cfg.phy.tddTiming.pdcchToPDSCHK0 = 0;
cfg.phy.pdcch.symbolAllocation = [0 2];
cfg.phy.pdsch.symbolAllocation = [2 12];
cfg.phy.pdsch.mappingType = "A";
if isfield(cfg.phy, "frameStructure")
    cfg.phy = rmfield(cfg.phy, "frameStructure");
end
if isfield(cfg, "resolved_runtime_view") && ...
        isfield(cfg.resolved_runtime_view, "frame_structure")
    cfg.resolved_runtime_view = rmfield( ...
        cfg.resolved_runtime_view, "frame_structure");
end
if isfield(cfg.phy, "frame")
    cfg.phy = rmfield(cfg.phy, "frame");
end
cfg = sixgr.phy.frame.FrameRuntimeStateBuilder.attachTimingContext(cfg);
nSizeGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 273));
cfg.phy.bwp.dl = struct("NStartBWP", 0, "NSizeBWP", nSizeGrid);
cfg.phy.bwp.ul = struct("NStartBWP", 0, "NSizeBWP", nSizeGrid);

multiUser = struct("Enabled", true, "NumUsers", 2, "RNTIStart", 501, ...
    "ExecutionModel", "slot_coupled_truth");
state = sixgr.truth.CoupledTruthRuntime.initialize(cfg, tmp, multiUser, struct(), 1);
state = sixgr.truth.CoupledTruthRuntime.advanceFrame(state, cfg, multiUser, 2, 30);
state.CurrentServingIdx(:) = 1;
state.DLQueueBits(:) = 120000;
state.ULQueueBits(:) = 0;
state.ControlEligibility(:) = true;
state.SchedulingEligibility(:) = true;
state.CellAcquisitionState(:) = "acquired";
state.AccessState(:) = "succeeded";
state.SRSValidityState(:) = "valid";
state.CSIValidityState(:) = "fresh_srs";
state = sixgr.truth.CoupledTruthRuntime.startSlot(state, cfg, "DL", 1, 1, 2, 2, 30);
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
