function ok = testRuntimeEvidenceCSVRebuild()
%TESTRUNTIMEEVIDENCECSVREBUILD Recover derived CSVs from JSONL truth.

setup6GRSimToolkit("Verbose", false);
runFolder = string(tempname());
mkdir(runFolder);
cleanup = onCleanup(@() localRemove(runFolder)); %#ok<NASGU>

bus = sixgr.runtime.RuntimeEvidenceBus(runFolder, ...
    "RunId", "runtime_rebuild", ...
    "ExecutionId", "execution_001", ...
    "FinalizationId", "finalization_001", ...
    "AttemptId", "attempt_001");
bus.stageStart("rebuild_guard");
bus.heartbeat("rebuild_guard", "Message", "working");
bus.stageEnd("rebuild_guard");

stagePath = fullfile(runFolder, "runtime", "csv", "stage_timing_events.csv");
stageTruth = readtable(stagePath, 'VariableNamingRule', 'preserve');
corrupt = stageTruth(:, setdiff(1:width(stageTruth), [5, 12, 15, 19], 'stable'));
corrupt = addvars(corrupt, repmat("scenario", height(corrupt), 1), ...
    'Before', 1, 'NewVariableNames', 'ScenarioID');
sixgr.util.csvWriteTable(stagePath, corrupt);

summary = sixgr.runtime.RuntimeEvidenceBus.rebuildDerivedCSVViews(runFolder);
assert(summary.EventCount >= 4 && summary.RebuiltCount >= 2);
assert(summary.QuarantinedCount >= 2);
rebuilt = readtable(stagePath, 'VariableNamingRule', 'preserve');
assert(width(rebuilt) == 19, "Rebuilt stage timing CSV must use schema v2.");
assert(height(rebuilt) == height(stageTruth));
assert(isequal(string(rebuilt.event_type), string(stageTruth.event_type)));
assert(all(string(rebuilt.finalization_id) == "finalization_001"));

bus.stageStart("after_rebuild");
appended = readtable(stagePath, 'VariableNamingRule', 'preserve');
assert(height(appended) == height(rebuilt) + 1, ...
    "Rebuilt CSV must accept subsequent versioned events.");
assert(isfolder(summary.QuarantineRoot), ...
    "Corrupted derived bytes must be retained in quarantine.");

ok = true;
fprintf("PASS testRuntimeEvidenceCSVRebuild: JSONL truth rebuilt derived CSV views.\n");
end

function localRemove(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
