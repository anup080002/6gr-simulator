function ok = testBlockScope()
%TESTBLOCKSCOPE Verify block enter events have terminal exit/fail events.

setup6GRSimToolkit("Verbose", false);

runFolder = tempname;
mkdir(runFolder);
cleanupObj = onCleanup(@() rmdir(runFolder, "s")); %#ok<NASGU>

bus = sixgr.runtime.RuntimeEvidenceBus(runFolder, "RunId", "unit_block_scope");
scope = bus.enterBlock("unit_success_block", ...
    "FunctionName", "tests.testBlockScope", ...
    "SourceFile", mfilename("fullpath"));
scope.success();

unfinished = bus.enterBlock("unit_unfinished_block", ...
    "FunctionName", "tests.testBlockScope", ...
    "SourceFile", mfilename("fullpath"));
unfinished.closeIfUnfinished();
bus.close();

traceCsv = fullfile(runFolder, "runtime", "csv", "block_call_trace.csv");
assert(exist(traceCsv, "file") == 2, "Block call trace CSV must exist.");
T = readtable(traceCsv, "VariableNamingRule", "preserve");
eventTypes = string(T.event_type);
assert(sum(eventTypes == "BLOCK_ENTER") == 2, "Both block entries must be recorded.");
assert(sum(eventTypes == "BLOCK_EXIT") == 1, "Successful block exit must be recorded.");
assert(sum(eventTypes == "BLOCK_FAIL") == 1, "Unfinished block must fail reconciliation.");

enterCallIds = string(T.call_id(eventTypes == "BLOCK_ENTER"));
terminalCallIds = string(T.call_id(eventTypes == "BLOCK_EXIT" | eventTypes == "BLOCK_FAIL"));
assert(all(ismember(enterCallIds, terminalCallIds)), "Every entered block must have a terminal event.");

ok = true;
end
