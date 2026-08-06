function ok = testRuntimeEvidenceBus()
%TESTRUNTIMEEVIDENCEBUS Verify append-only runtime journals and CSV views.

setup6GRSimToolkit("Verbose", false);

runFolder = tempname;
mkdir(runFolder);
cleanupObj = onCleanup(@() rmdir(runFolder, "s")); %#ok<NASGU>

bus = sixgr.runtime.RuntimeEvidenceBus(runFolder, ...
    "RunId", "unit_runtime_bus", ...
    "ExecutionId", "execution_unit_001", ...
    "FinalizationId", "finalization_unit_001", ...
    "AttemptId", "attempt_007");
bus.stageStart("unit_stage");
bus.heartbeat("unit_stage", "Message", "still progressing");
bus.stageEnd("unit_stage");
bus.close();

runtimeJournal = fullfile(runFolder, "runtime", "journal", "runtime_events.jsonl");
assert(exist(runtimeJournal, "file") == 2, "Runtime journal must exist.");
events = localReadJSONLines(runtimeJournal);
assert(numel(events) >= 5, "Runtime journal must contain run, stage, heartbeat events.");
seq = zeros(numel(events), 1);
for i = 1:numel(events)
    seq(i) = double(events{i}.global_event_sequence);
    assert(string(events{i}.schema_name) == "sixgr.runtime.event");
    assert(string(events{i}.schema_version) == "2.0.0");
    assert(string(events{i}.execution_id) == "execution_unit_001");
    assert(string(events{i}.finalization_id) == "finalization_unit_001");
    assert(string(events{i}.attempt_id) == "attempt_007");
end
assert(isequal(seq(:), unique(seq(:), "stable")), "Global event sequence IDs must be unique.");
assert(all(diff(seq(:)) > 0), "Global event sequence IDs must be strictly increasing.");

stageCsv = fullfile(runFolder, "runtime", "csv", "stage_timing_events.csv");
heartbeatCsv = fullfile(runFolder, "runtime", "csv", "progress_heartbeat.csv");
assert(exist(stageCsv, "file") == 2, "Stage timing CSV must exist.");
assert(exist(heartbeatCsv, "file") == 2, "Progress heartbeat CSV must exist.");
stageT = readtable(stageCsv, "Delimiter", ",", "VariableNamingRule", "preserve");
hbT = readtable(heartbeatCsv, "Delimiter", ",", "VariableNamingRule", "preserve");
assert(any(strcmpi(string(stageT.event_type), "STAGE_START")), "Stage start must be exported.");
assert(any(strcmpi(string(stageT.event_type), "STAGE_END")), "Stage end must be exported.");
assert(any(strcmpi(string(hbT.event_type), "HEARTBEAT")), "Heartbeat must be exported.");
identityColumns = ["schema_name", "schema_version", "attempt_id", ...
    "execution_id", "finalization_id"];
assert(all(ismember(identityColumns, string(stageT.Properties.VariableNames))));
assert(all(string(stageT.attempt_id) == "attempt_007"));
assert(all(string(stageT.execution_id) == "execution_unit_001"));
assert(all(string(stageT.finalization_id) == "finalization_unit_001"));

ok = true;
end

function events = localReadJSONLines(pathStr)
raw = string(fileread(pathStr));
lines = splitlines(raw);
lines = lines(strlength(strtrim(lines)) > 0);
events = cell(numel(lines), 1);
for i = 1:numel(lines)
    events{i} = jsondecode(lines(i));
end
end
