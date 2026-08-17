function evidence = assertResumeSourceIdentity(runFolder)
%ASSERTRESUMESOURCEIDENTITY Fail before resume writes on source mismatch.

runFolder = char(string(runFolder));
manifestPath = fullfile(runFolder, "raw", "execution_manifest.json");
if ~isfile(manifestPath)
    error("sixgr:runtime:RawExecutionNotSealed", ...
        "Resume finalization requires a sealed raw execution: %s", manifestPath);
end
try
    rawManifest = jsondecode(fileread(manifestPath));
catch ME
    error("sixgr:runtime:RawExecutionManifestUnreadable", ...
        "Unable to read sealed raw execution manifest %s: %s", ...
        manifestPath, ME.message);
end

repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
[commitStatus, commitText] = system(sprintf('git -C "%s" rev-parse HEAD', repoRoot));
if commitStatus ~= 0
    error("sixgr:runtime:CurrentGitIdentityUnavailable", ...
        "Unable to resolve the current Git commit for %s: %s", ...
        repoRoot, strtrim(commitText));
end
[dirtyStatus, dirtyText] = system(sprintf('git -C "%s" status --porcelain --untracked-files=all', repoRoot));
if dirtyStatus ~= 0
    error("sixgr:runtime:CurrentGitIdentityUnavailable", ...
        "Unable to resolve current Git worktree status for %s: %s", ...
        repoRoot, strtrim(dirtyText));
end
currentSource = struct( ...
    "GitCommit", strtrim(string(commitText)), ...
    "GitDirty", strlength(strtrim(string(dirtyText))) > 0);
evidence = sixgr.runtime.validateResumeSourceIdentity(rawManifest, currentSource);
evidence.ManifestPath = string(manifestPath);
end
