function ok = testRunEvidenceLifecycle()
%TESTRUNEVIDENCELIFECYCLE Raw evidence is immutable and attempts are isolated.

setup6GRSimToolkit("Verbose", false);
runFolder = tempname();
mkdir(runFolder);
cleanup = onCleanup(@() localRemove(runFolder)); %#ok<NASGU>
metadata = struct( ...
    "RunID", "run_lifecycle_unit", ...
    "ExecutionID", "execution_lifecycle_001", ...
    "ConfigHash", repmat('a', 1, 64), ...
    "ExecutionStartUTC", "2026-08-05T00:00:00Z", ...
    "ExecutionEndUTC", "2026-08-05T00:10:00Z", ...
    "GitCommit", "0123456789abcdef", ...
    "GitDirty", true);
try
    sixgr.runtime.RunEvidenceLifecycle.sealExecution(runFolder, metadata);
    error("testRunEvidenceLifecycle:ExpectedPatchFailure", ...
        "Dirty execution must require a captured patch bundle.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:runtime:DirtyExecutionPatchRequired"));
end
metadata.PatchBundleContent = "diff --git a/source.m b/source.m" + newline + ...
    "+runtime evidence repair" + newline;
raw = sixgr.runtime.RunEvidenceLifecycle.sealExecution(runFolder, metadata);
rawManifest = fullfile(runFolder, "raw", "execution_manifest.json");
patchPath = fullfile(runFolder, "raw", "source_patch.diff");
assert(isfile(rawManifest) && isfile(patchPath));
assert(strlength(string(raw.PatchBundleSHA256)) == 64);
rawHashBefore = localSHA(rawManifest);
patchHashBefore = localSHA(patchPath);

repeat = sixgr.runtime.RunEvidenceLifecycle.sealExecution(runFolder, metadata);
assert(string(repeat.ExecutionID) == "execution_lifecycle_001");
assert(localSHA(rawManifest) == rawHashBefore && localSHA(patchPath) == patchHashBefore, ...
    "Repeated sealing must not mutate immutable raw evidence.");

attempt1 = sixgr.runtime.RunEvidenceLifecycle.beginFinalization(runFolder, ...
    struct("ExecutionID", "execution_lifecycle_001"));
assert(attempt1.AttemptID == "attempt_001");
failure = MException("sixgr:test:FinalizationFailure", "unit failure");
terminal1 = sixgr.runtime.RunEvidenceLifecycle.failFinalization(attempt1, failure);
assert(string(terminal1.Status) == "FAIL" && ~logical(terminal1.PublicationQualified));
attemptManifest1 = jsondecode(fileread(fullfile( ...
    attempt1.AttemptRoot, "attempt_manifest.json")));
assert(string(attemptManifest1.Status) == "FAIL" && ...
    string(attemptManifest1.TerminalStatusRelativePath) == "terminal_status.json" && ...
    ~logical(attemptManifest1.PublicationQualified) && ...
    string(attemptManifest1.FailureIdentifier) == "sixgr:test:FinalizationFailure", ...
    "A failed terminal record must close its attempt manifest as FAIL.");
assert(~isfile(fullfile(runFolder, "published", "current.json")), ...
    "A failed finalization must never create a green publication pointer.");

attempt2 = sixgr.runtime.RunEvidenceLifecycle.beginFinalization(runFolder, ...
    struct("ExecutionID", "execution_lifecycle_001"));
assert(attempt2.AttemptID == "attempt_002");
artifactManifest = fullfile(attempt2.OutputsRoot, "artifact_manifest.json");
sixgr.util.jsonWrite(artifactManifest, struct( ...
    "SchemaName", "unit.artifacts", "Status", "PASS", "ArtifactCount", 2));
terminal2 = sixgr.runtime.RunEvidenceLifecycle.publish(attempt2, artifactManifest);
assert(string(terminal2.Status) == "PASS" && logical(terminal2.PublicationQualified));
attemptManifest2 = jsondecode(fileread(fullfile( ...
    attempt2.AttemptRoot, "attempt_manifest.json")));
assert(string(attemptManifest2.Status) == "PASS" && ...
    logical(attemptManifest2.PublicationQualified) && ...
    string(attemptManifest2.TerminalStatusRelativePath) == "terminal_status.json" && ...
    strlength(string(attemptManifest2.ArtifactManifestSHA256)) == 64, ...
    "A published terminal record must close its attempt manifest as PASS.");
pointerPath = fullfile(runFolder, "published", "current.json");
pointer = jsondecode(fileread(pointerPath));
assert(string(pointer.AttemptID) == "attempt_002");
assert(string(pointer.ExecutionID) == "execution_lifecycle_001");
assert(strlength(string(pointer.ArtifactManifestSHA256)) == 64);

try
    sixgr.runtime.RunEvidenceLifecycle.failFinalization(attempt1, failure);
    error("testRunEvidenceLifecycle:ExpectedTerminalFailure", ...
        "A terminal attempt cannot be rewritten.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:runtime:FinalizationAttemptAlreadyTerminal"));
end
attempt3 = sixgr.runtime.RunEvidenceLifecycle.beginFinalization(runFolder, ...
    struct("ExecutionID", "execution_lifecycle_001"));
try
    sixgr.runtime.RunEvidenceLifecycle.publish(attempt3, rawManifest);
    error("testRunEvidenceLifecycle:ExpectedPathEscape", ...
        "Publication must reject manifests outside the attempt root.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:runtime:LifecyclePathEscape"));
end

assert(localSHA(rawManifest) == rawHashBefore && localSHA(patchPath) == patchHashBefore, ...
    "Finalization attempts must not mutate raw execution evidence.");
ok = true;
fprintf("PASS testRunEvidenceLifecycle: failed attempts stay isolated; PASS pointer is atomic.\n");
end

function hash = localSHA(pathValue)
fid = fopen(pathValue, "rb");
assert(fid >= 0);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
hash = sixgr.util.sha256Hex(fread(fid, Inf, "*uint8"));
end

function localRemove(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
