function ok = testRuntimeEvidenceSchemaIsolation()
%TESTRUNTIMEEVIDENCESCHEMAISOLATION Reject mixed finalization journal schemas.

setup6GRSimToolkit("Verbose", false);

runFolder = tempname();
mkdir(runFolder);
cleanup = onCleanup(@() localRemove(runFolder)); %#ok<NASGU>
sixgr.runtime.RuntimeEvidenceBus.prepareRunFolder(runFolder);
stagePath = fullfile(runFolder, "runtime", "csv", "stage_timing_events.csv");
legacyHeader = "run_id,event_id,global_event_sequence,timestamp_utc,event_type";
localWrite(stagePath, legacyHeader + newline + ...
    "legacy,event-1,1,2026-01-01T00:00:00Z,STAGE_START" + newline);
bus = sixgr.runtime.RuntimeEvidenceBus(runFolder, ...
    "RunId", "schema_isolation", "ExecutionId", "execution_001", ...
    "AttemptId", "attempt_002");
journalPath = fullfile(runFolder, "runtime", "journal", "runtime_events.jsonl");
journalBefore = fileread(journalPath);
csvBefore = fileread(stagePath);
try
    bus.stageStart("must_not_append");
    error("testRuntimeEvidenceSchemaIsolation:ExpectedCSVMismatch", ...
        "A mismatched runtime CSV schema must fail before append.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:runtime:CSVSchemaMismatch"), ...
        "Unexpected CSV mismatch error: %s | %s", ME.identifier, ME.message);
end
assert(strcmp(fileread(stagePath), csvBefore), ...
    "Schema mismatch must leave the existing CSV byte-for-byte unchanged.");
assert(strcmp(fileread(journalPath), journalBefore), ...
    "CSV preflight failure must not append a JSON journal event.");

journalRoot = tempname();
mkdir(journalRoot);
journalCleanup = onCleanup(@() localRemove(journalRoot)); %#ok<NASGU>
sixgr.runtime.RuntimeEvidenceBus.prepareRunFolder(journalRoot);
badJournal = fullfile(journalRoot, "runtime", "journal", "runtime_events.jsonl");
localWrite(badJournal, string('{"run_id":"legacy_without_schema"}') + newline);
before = fileread(badJournal);
try
    sixgr.runtime.RuntimeEvidenceBus(journalRoot, ...
        "RunId", "journal_isolation", "AttemptId", "attempt_002");
    error("testRuntimeEvidenceSchemaIsolation:ExpectedJournalMismatch", ...
        "A mismatched JSONL schema must fail before append.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:runtime:JournalSchemaMismatch"), ...
        "Unexpected journal mismatch error: %s | %s", ME.identifier, ME.message);
end
assert(strcmp(fileread(badJournal), before), ...
    "Journal schema mismatch must preserve the existing bytes.");

try
    sixgr.runtime.RuntimeEvidenceBus(tempname(), "AttemptId", "");
    error("testRuntimeEvidenceSchemaIsolation:ExpectedAttemptIdentity", ...
        "Blank attempt identity must fail.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:runtime:AttemptIdentityRequired"));
end

ok = true;
fprintf("PASS testRuntimeEvidenceSchemaIsolation: mixed CSV/JSONL schemas fail before append.\n");
end

function localWrite(pathValue, textValue)
folder = fileparts(pathValue);
if ~isfolder(folder)
    mkdir(folder);
end
fid = fopen(pathValue, "w");
assert(fid >= 0, "Unable to create schema-isolation fixture.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s", char(textValue));
end

function localRemove(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
