function evidence = validateResumeSourceIdentity(rawManifest, currentSource)
%VALIDATERESUMESOURCEIDENTITY Compare sealed and current source identity.

% This pure validator is separated from Git discovery so the identity
% rules can be regression tested without mutating a run directory.

if ~(isstruct(rawManifest) && isscalar(rawManifest)) || ...
        ~(isstruct(currentSource) && isscalar(currentSource))
    error("sixgr:runtime:ResumeSourceIdentityInvalid", ...
        "Raw and current source identities must be scalar structs.");
end

rawCommit = localRequiredCommit(rawManifest, "GitCommit", "sealed raw execution");
currentCommit = localRequiredCommit(currentSource, "GitCommit", "current source");
rawDirty = localRequiredLogical(rawManifest, "GitDirty", "sealed raw execution");
currentDirty = localRequiredLogical(currentSource, "GitDirty", "current source");

if rawCommit ~= currentCommit
    error("sixgr:runtime:RawExecutionIdentityMismatch", ...
        "Sealed raw execution GitCommit '%s' does not match current source GitCommit '%s'.", ...
        rawCommit, currentCommit);
end
if rawDirty
    error("sixgr:runtime:ResumeSourceNotPublicationClean", ...
        "The sealed raw execution was produced from a dirty worktree. " + ...
        "Publication finalization requires a fresh execution from committed source.");
end
if currentDirty
    error("sixgr:runtime:ResumeSourceNotPublicationClean", ...
        "The current worktree is dirty. Resume finalization is blocked so " + ...
        "derived evidence cannot be rebound to uncommitted source changes.");
end

evidence = struct( ...
    "Ok", true, ...
    "GitCommit", rawCommit, ...
    "RawGitDirty", rawDirty, ...
    "CurrentGitDirty", currentDirty, ...
    "EvidenceClass", "sealed_raw_vs_current_clean_git_identity");
end

function value = localRequiredCommit(source, field, label)
value = lower(strtrim(string(sixgr.util.structGet(source, field, ""))));
if ~isscalar(value) || isempty(regexp(char(value), "^[0-9a-f]{40,64}$", "once"))
    error("sixgr:runtime:ResumeSourceIdentityInvalid", ...
        "%s requires a hexadecimal %s.", label, field);
end
end

function value = localRequiredLogical(source, field, label)
if ~isfield(source, field) || ~isscalar(source.(field)) || ...
        ~(islogical(source.(field)) || isnumeric(source.(field)))
    error("sixgr:runtime:ResumeSourceIdentityInvalid", ...
        "%s requires scalar logical %s.", label, field);
end
value = logical(source.(field));
end
