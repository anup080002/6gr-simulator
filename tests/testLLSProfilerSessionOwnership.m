function ok = testLLSProfilerSessionOwnership()
%TESTLLSPROFILERSESSIONOWNERSHIP Fail before a run can lose profile evidence.

setup6GRSimToolkit("Verbose", false);
localStopProfiler();
cleanup = onCleanup(@localStopProfiler); %#ok<NASGU>

disabled = sixgr.lls6g.runners.acquireMATLABProfilerSession(false);
assert(~disabled.Enabled && ~disabled.OwnsSession, ...
    "A disabled profiler must not start or claim a session.");

profile on;
threw = false;
try
    sixgr.lls6g.runners.acquireMATLABProfilerSession(true);
catch err
    threw = true;
    assert(string(err.identifier) == "sixgr:lls6g:ProfilerSessionAlreadyActive", ...
        "An active caller-owned profiler must fail with the typed ownership error.");
end
assert(threw, "A requested run profiler must not reuse a caller-owned session.");
assert(localProfilerRunning(), ...
    "Rejecting profiler acquisition must not stop the caller-owned session.");

localStopProfiler();
owned = sixgr.lls6g.runners.acquireMATLABProfilerSession(true);
assert(owned.Enabled && owned.OwnsSession && localProfilerRunning(), ...
    "An idle profiler must be started and owned by the requesting run.");

fprintf("LLSProfilerSessionOwnership: isolated ownership and fail-fast guard verified.\n");
ok = true;
end

function tf = localProfilerRunning()
status = profile("status");
if isfield(status, "ProfilerStatus")
    token = string(status.ProfilerStatus);
elseif isfield(status, "Profiler")
    token = string(status.Profiler);
else
    token = "off";
end
tf = contains(lower(strtrim(token)), "on");
end

function localStopProfiler()
try
    profile off;
catch
end
try
    profile clear;
catch
end
end
