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

child1 = sixgr.runtime.deriveChildRunID("repeat_1", ...
    "sweep_point", 1, "Baseline Point");
child2 = sixgr.runtime.deriveChildRunID("repeat_1", ...
    "sweep_point", 2, "Baseline-Point");
assert(child1 == "repeat_1__sweep_point_001_baseline_point");
assert(child2 == "repeat_1__sweep_point_002_baseline-point");
assert(child1 ~= child2, ...
    "Nested point identities must remain unique after token normalization.");
localMustFail(@() sixgr.runtime.deriveChildRunID("", ...
    "sweep_point", 1, "point"), ...
    "sixgr:runtime:ParentRunIdentityRequired");

baseConfig = struct("meta", struct("scenario_id", "hash_test"), ...
    "simulation", struct("snr_db", 0));
changedConfig = baseConfig;
changedConfig.simulation.snr_db = 10;
hash1 = sixgr.lls6g.config.hashResolvedScenario(baseConfig);
hash2 = sixgr.lls6g.config.hashResolvedScenario(changedConfig);
assert(strlength(hash1) == 64 && strlength(hash2) == 64 && hash1 ~= hash2, ...
    "Resolved sweep overrides must change the immutable configuration hash.");

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
