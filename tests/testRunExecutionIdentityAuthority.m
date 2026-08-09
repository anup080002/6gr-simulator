function ok = testRunExecutionIdentityAuthority()
%TESTRUNEXECUTIONIDENTITYAUTHORITY Resume cannot rebind old PHY evidence.

root = tempname;
mkdir(root);
cleanup = onCleanup(@() localCleanup(root)); %#ok<NASGU>
hash = repmat('a', 1, 64);

fresh = sixgr.runtime.resolveExecutionIdentity(root, "run_001", hash, struct());
assert(startsWith(fresh.ExecutionID, "execution_"));
assert(fresh.Source == "new_waveform_execution_uuid");

mkdir(fullfile(root, "meta"));
sixgr.util.jsonWrite(fullfile(root, "meta", "runtime_summary.json"), struct( ...
    "RunID", "run_001", "ExecutionID", fresh.ExecutionID, ...
    "ConfigHash", hash));
resume = sixgr.runtime.resolveExecutionIdentity(root, "run_001", hash, ...
    struct("ResumeCompletedRuntimeFinalization", true));
assert(resume.ExecutionID == fresh.ExecutionID);
assert(startsWith(resume.Source, "persisted:"));

localMustFail(@() sixgr.runtime.resolveExecutionIdentity(root, "run_001", ...
    hash, struct("ResumeCompletedRuntimeFinalization", true, ...
    "ExecutionID", "execution_wrong")), ...
    "sixgr:runtime:ExecutionIdentityMismatch");
localMustFail(@() sixgr.runtime.resolveExecutionIdentity(root, "run_002", ...
    hash, struct("ResumeCompletedRuntimeFinalization", true)), ...
    "sixgr:runtime:ExecutionRunIdentityMismatch");
localMustFail(@() sixgr.runtime.resolveExecutionIdentity(root, "run_001", ...
    repmat('b', 1, 64), struct("ResumeCompletedRuntimeFinalization", true)), ...
    "sixgr:runtime:ExecutionConfigIdentityMismatch");

emptyRoot = tempname;
mkdir(emptyRoot);
emptyCleanup = onCleanup(@() localCleanup(emptyRoot)); %#ok<NASGU>
localMustFail(@() sixgr.runtime.resolveExecutionIdentity(emptyRoot, "run_003", ...
    hash, struct("ResumeCompletedRuntimeFinalization", true)), ...
    "sixgr:runtime:ResumeExecutionIdentityMissing");

rowRoot = tempname;
mkdir(fullfile(rowRoot, "air_interface", "csv"));
rowCleanup = onCleanup(@() localCleanup(rowRoot)); %#ok<NASGU>
rowExecutionID = "execution_11111111-2222-3333-4444-555555555555";
rows = table(repmat(rowExecutionID, 2, 1), ...
    repmat("run_rows", 2, 1), repmat(string(hash), 2, 1), ...
    'VariableNames', {'ExecutionID','RunTag','ConfigHash'});
sixgr.util.csvWriteTable(fullfile(rowRoot, "air_interface", "csv", ...
    "pdcch_trials.csv"), rows);
rowResume = sixgr.runtime.resolveExecutionIdentity(rowRoot, ...
    "run_rows", hash, struct("ResumeCompletedRuntimeFinalization", true));
assert(rowResume.ExecutionID == rowExecutionID);
assert(startsWith(rowResume.Source, "persisted_canonical_rows:"), ...
    "Resume must recover the immutable ID from canonical waveform rows.");

ok = true;
fprintf("PASS testRunExecutionIdentityAuthority: resume preserves execution identity.\n");
end

function localMustFail(fcn, identifier)
try
    fcn();
    error("testRunExecutionIdentityAuthority:ExpectedFailure", ...
        "Expected %s.", identifier);
catch cause
    assert(string(cause.identifier) == string(identifier), ...
        "Expected %s, received %s.", identifier, cause.identifier);
end
end

function localCleanup(root)
if isfolder(root)
    rmdir(root, "s");
end
end
