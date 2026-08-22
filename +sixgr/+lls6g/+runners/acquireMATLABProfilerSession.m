function state = acquireMATLABProfilerSession(enabled)
%ACQUIREMATLABPROFILERSESSION Acquire an isolated MATLAB profiler session.
%
% A production run that requests profiler evidence must own the profiler
% session from its start. Reusing a caller-owned session would mix unrelated
% calls into the exported profile, while silently declining to start a
% session would let a long run finish without its mandatory evidence.

state = struct("Enabled", logical(enabled), "OwnsSession", false);
if ~state.Enabled
    return;
end

if localProfilerIsRunning()
    error("sixgr:lls6g:ProfilerSessionAlreadyActive", ...
        "MATLAB profiling is enabled for this run, but a profiler " + ...
        "session is already active. Stop or export the caller-owned " + ...
        "session before launching the run so its performance evidence " + ...
        "is isolated and complete.");
end

profile clear;
profile on;
state.OwnsSession = true;
end

function tf = localProfilerIsRunning()
try
    status = profile("status");
    if isstruct(status) && isfield(status, "ProfilerStatus")
        token = string(status.ProfilerStatus);
    elseif isstruct(status) && isfield(status, "Profiler")
        token = string(status.Profiler);
    else
        token = "off";
    end
    tf = contains(lower(strtrim(token)), "on");
catch
    tf = false;
end
end
