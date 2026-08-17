function testResumeSourceIdentityGuard()
%TESTRESUMESOURCEIDENTITYGUARD Resume must bind to clean exact source.

commitA = repmat('a', 1, 40);
commitB = repmat('b', 1, 40);
raw = struct("GitCommit", commitA, "GitDirty", false);
current = struct("GitCommit", commitA, "GitDirty", false);
evidence = sixgr.runtime.validateResumeSourceIdentity(raw, current);
assert(evidence.Ok && string(evidence.GitCommit) == string(commitA));

localAssertIdentifier(@()sixgr.runtime.validateResumeSourceIdentity( ...
    raw, struct("GitCommit", commitB, "GitDirty", false)), ...
    "sixgr:runtime:RawExecutionIdentityMismatch");
localAssertIdentifier(@()sixgr.runtime.validateResumeSourceIdentity( ...
    struct("GitCommit", commitA, "GitDirty", true), current), ...
    "sixgr:runtime:ResumeSourceNotPublicationClean");
localAssertIdentifier(@()sixgr.runtime.validateResumeSourceIdentity( ...
    raw, struct("GitCommit", commitA, "GitDirty", true)), ...
    "sixgr:runtime:ResumeSourceNotPublicationClean");
end

function localAssertIdentifier(fn, expected)
threw = false;
try
    fn();
catch ME
    threw = true;
    assert(string(ME.identifier) == string(expected), ...
        "Expected %s, got %s.", expected, ME.identifier);
end
assert(threw, "Expected %s.", expected);
end
