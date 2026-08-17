function ok = testLLSFinalQualificationOrdering()
%TESTLLSFINALQUALIFICATIONORDERING Terminal evidence precedes production reduction.

repoRoot = fileparts(fileparts(mfilename("fullpath")));
runnerPath = fullfile(repoRoot, "+sixgr", "+lls6g", "+runners", ...
    "runSingle.m");
source = string(fileread(runnerPath));

refreshToken = "finalQualificationEvidence = localRefreshFinalQualificationEvidence(";
auditToken = "artifactAudit = localRunArtifactAuditIfNeeded(runFolder, scfg, cfg);";
reducerToken = "scenarioStatus = sixgr.truth.applyProductionQualificationGate(";
refreshPositions = strfind(source, refreshToken);
assert(numel(refreshPositions) >= 2, ...
    "Both required and terminal finalization passes must refresh Phase-7 evidence.");

for index = 1:numel(refreshPositions)
    tail = extractAfter(source, refreshPositions(index) - 1);
    auditPosition = strfind(tail, auditToken);
    reducerPosition = strfind(tail, reducerToken);
    assert(~isempty(auditPosition) && ~isempty(reducerPosition) && ...
        auditPosition(1) < reducerPosition(1), ...
        ["Final Phase-7 refresh must precede recursive artifact audit, " ...
         "which must precede production qualification reduction."]);
end

helperStart = strfind(source, ...
    "function evidence = localRefreshFinalQualificationEvidence");
helperTail = extractAfter(source, helperStart(1) - 1);
nextFunction = strfind(extractAfter(helperTail, 1), newline + "function ");
assert(~isempty(nextFunction), "Could not isolate the terminal refresh helper.");
helper = extractBefore(helperTail, nextFunction(1) + 1);
assert(contains(helper, "sixgr.analytics.buildPhase7ReadinessArtifacts") && ...
    contains(helper, "sixgr.analytics.evaluatePublicationReadinessGates"), ...
    "Terminal refresh must recompute both Phase-7 and publication evidence.");
assert(contains(helper, "no_proxy_no_missing_gate_override"), ...
    "The refresh policy must explicitly prohibit proxy or missing-gate overrides.");

ok = true;
fprintf("PASS testLLSFinalQualificationOrdering: terminal reducer ordering is fail closed.\n");
end
