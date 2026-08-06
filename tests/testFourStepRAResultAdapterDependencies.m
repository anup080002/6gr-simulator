function ok = testFourStepRAResultAdapterDependencies()
%TESTFOURSTEPRARRESULTADAPTERDEPENDENCIES Guard the in-path RA row adapter.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
sourcePath = fullfile(pwd, "+sixgr", "+truth", ...
    "runWaveformLinkBundle.m");
source = string(fileread(sourcePath));
startToken = "function r = localApplyFourStepRAEvidenceToPRACHRow";
endToken = "function tables = localEmptyRAEvidenceTables";
startIndex = strfind(source, startToken);
endIndex = strfind(source, endToken);
assert(numel(startIndex) == 1 && ~isempty(endIndex) && ...
    endIndex(1) > startIndex(1), ...
    "Unable to isolate the production four-step RA result adapter.");
adapter = extractBetween(source, startIndex(1), endIndex(1) - 1);
assert(~contains(adapter, "ternary("), ...
    "The RA result adapter must not depend on an undefined ternary helper.");
assert(all(contains(adapter, ["TimingEstimateStatus", ...
    "CFOEstimateAvailability", "CFOValueStatus"])), ...
    "The RA result adapter must materialize timing and CFO availability states.");

collectorStart = strfind(source, "function [T, correlationTraceT, raEvidenceTables] = localCollectPRACHTrials");
collectorEnd = strfind(source, "function tf = localShouldRunFourStepRAForPRACH");
collector = extractBetween(source, collectorStart(1), collectorEnd(1) - 1);
assert(contains(collector, "r.FailureReason = failure") && ...
    contains(collector, "r.RAFailureReason = failure"), ...
    "The canonical PRACH row must preserve identifier and message on adapter failure.");
ok = true;
fprintf("PASS testFourStepRAResultAdapterDependencies: RA adapter dependencies and failure provenance are explicit.\n");
end
