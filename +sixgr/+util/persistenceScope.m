function cleanup = persistenceScope(enabled)
%PERSISTENCESCOPE Temporarily enable or disable simulator artifact writes.

if nargin < 1
    enabled = true;
end

prevDisable = getenv("SIXGR_DISABLE_PERSISTENCE");
prevCoreOnly = getenv("SIXGR_CORE_ONLY");
if logical(enabled)
    cleanup = onCleanup(@() localRestore(prevDisable, prevCoreOnly));
    return;
end

setenv("SIXGR_DISABLE_PERSISTENCE", "1");
setenv("SIXGR_CORE_ONLY", "1");
cleanup = onCleanup(@() localRestore(prevDisable, prevCoreOnly));
end

function localRestore(prevDisable, prevCoreOnly)
setenv("SIXGR_DISABLE_PERSISTENCE", char(prevDisable));
setenv("SIXGR_CORE_ONLY", char(prevCoreOnly));
end
