function testProfiledRunnerFlushesPartialEvidence
%TESTPROFILEDRUNNERFLUSHESPARTIALEVIDENCE Access ledger flushes mid-run.

runFolder = tempname(fullfile(tempdir, "sixgr_profiled_flush_probe"));
sixgr.util.ensureFolder(runFolder);

state = struct();
state.CurrentFrame = 1;
state.CurrentSlot = 5;
state.CurrentServingIdx = [1; 2];
state.AccessState = ["succeeded"; "pending"];
state.SchedulingEligibility = [true; false];
state.AccessTransitionLedgerTable = sixgr.monitor.AccessFlowRecorder.emptyLedger();
state = sixgr.monitor.AccessFlowRecorder.recordEvent(state, ...
    "UEIndex", 1, ...
    "CellID", 1, ...
    "OldState", "pending", ...
    "NewState", "ACCESS_SUCCEEDED", ...
    "TransitionReason", "prach_msg1_detected", ...
    "SourceFunction", "testProfiledRunnerFlushesPartialEvidence", ...
    "SourceFile", "tests/testProfiledRunnerFlushesPartialEvidence.m", ...
    "Procedure", "RACH_MSG1", ...
    "PhysicalChannel", "PRACH", ...
    "AccessSuccess", true);

sixgr.monitor.AccessFlowRecorder.writeTables(runFolder, state);

layout = sixgr.report.resultLayout(runFolder);
controlLedger = fullfile(layout.ControlCSVDir, "access_transition_ledger.csv");
reportTimeline = fullfile(layout.ReportCSVDir, "access_state_timeline.csv");
assert(exist(controlLedger, "file") == 2, "Control access transition ledger CSV must be flushed.");
assert(exist(reportTimeline, "file") == 2, "Report access timeline CSV must be flushed.");

T = readtable(controlLedger);
assert(height(T) == 1, "Flushed access transition ledger must preserve recorded rows.");
assert(string(T.new_state(1)) == "ACCESS_SUCCEEDED", "Flushed ledger must preserve transition state.");
end
