function tf = shouldPreserveCompletedRunOnPostRunFailure(scenarioStatus)
%SHOULDPRESERVECOMPLETEDRUNONPOSTRUNFAILURE Keep completed truth-backed runs authoritative.
%
% Late publishing failures after the final truth-gated summary/manifest have
% already been written should not spawn a failed recovery row that replaces a
% truthful completed run in the browser.

tf = false;
if ~isstruct(scenarioStatus) || isempty(fieldnames(scenarioStatus))
    return;
end

runCompletion = lower(strtrim(char(string(sixgr.util.structGet(scenarioStatus, "RunCompletion", "")))));
resultOk = logical(sixgr.util.structGet(scenarioStatus, "ResultOk", false));
truthOk = logical(sixgr.util.structGet(scenarioStatus, "RuntimeTruthContractOk", false));
requiredFailures = double(sixgr.util.structGet(scenarioStatus, "RequiredFailureCount", NaN));
strictTruthFailures = double(sixgr.util.structGet(scenarioStatus, "StrictTruthFailureCount", NaN));
strictProxyFailures = double(sixgr.util.structGet(scenarioStatus, "StrictProxyGuardFailureCount", NaN));

tf = strcmp(runCompletion, "completed") && resultOk && truthOk && ...
    isequaln(requiredFailures, 0) && isequaln(strictTruthFailures, 0) && ...
    isequaln(strictProxyFailures, 0);
end
