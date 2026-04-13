function sem = deriveUserSummarySemantics(sourceT)
%DERIVEUSERSUMMARYSEMANTICS Truthful per-user summary validity and success semantics.

if nargin < 1 || ~istable(sourceT)
    sourceT = table();
end
sourceT = localEnsureSourceVars(sourceT);

observedRowCount = double(height(sourceT));
runtimeDataPresent = observedRowCount > 0;

status = upper(strtrim(string(sourceT.Status)));
status = fillmissing(status, "constant", "");
successByStatus = status == "PASS";
failureByStatus = status == "FAIL";
crashByStatus = status == "CRASH";

crcKnown = false(height(sourceT), 1);
successByCRC = false(height(sourceT), 1);
failureByCRC = false(height(sourceT), 1);
if ismember("CRCPass", string(sourceT.Properties.VariableNames))
    crcVals = double(sourceT.CRCPass);
    crcKnown = isfinite(crcVals);
    successByCRC = crcKnown & logical(crcVals);
    failureByCRC = crcKnown & ~logical(crcVals);
end

goodputVals = double(sourceT.Goodput_Mbps);
goodputPositive = isfinite(goodputVals) & (goodputVals > 0);

crashMask = crashByStatus;
if ismember("Crash", string(sourceT.Properties.VariableNames))
    crashVals = sourceT.Crash;
    if islogical(crashVals)
        crashMask = crashMask | logical(crashVals);
    else
        crashMask = crashMask | (isfinite(double(crashVals)) & logical(double(crashVals)));
    end
end

successMask = successByStatus | successByCRC | goodputPositive;
failureMask = failureByStatus | failureByCRC | crashMask;
observedOutcomeMask = successMask | failureMask;

observedSuccessCount = double(nnz(successMask));
observedFailureCount = double(nnz(failureMask));
observedCrashCount = double(nnz(crashMask));
observedOutcomeCount = double(nnz(observedOutcomeMask));

allObservedRowsSuccessful = runtimeDataPresent && observedOutcomeCount > 0 && ...
    observedFailureCount == 0 && all(successMask(observedOutcomeMask));
userHadAnySuccessfulTx = observedSuccessCount > 0;
userHadAnySuccessfulRx = observedSuccessCount > 0;
partialSuccess = runtimeDataPresent && userHadAnySuccessfulTx && observedFailureCount > 0;
summaryRowValid = runtimeDataPresent;

if observedOutcomeCount > 0
    passRate = observedSuccessCount / observedOutcomeCount;
else
    passRate = NaN;
end

if ~runtimeDataPresent
    summaryStatus = "no_runtime_data";
elseif partialSuccess
    summaryStatus = "partial_success";
elseif allObservedRowsSuccessful
    summaryStatus = "all_success";
elseif observedFailureCount > 0
    summaryStatus = "all_failed";
elseif userHadAnySuccessfulTx
    summaryStatus = "success_with_unclassified_rows";
else
    summaryStatus = "runtime_data_present_no_observed_outcome";
end

sem = struct( ...
    "ObservedRowCount", observedRowCount, ...
    "RuntimeDataPresent", logical(runtimeDataPresent), ...
    "SummaryRowValid", logical(summaryRowValid), ...
    "UserHadAnySuccessfulTx", logical(userHadAnySuccessfulTx), ...
    "UserHadAnySuccessfulRx", logical(userHadAnySuccessfulRx), ...
    "PartialSuccess", logical(partialSuccess), ...
    "AllObservedRowsSuccessful", logical(allObservedRowsSuccessful), ...
    "ObservedSuccessCount", observedSuccessCount, ...
    "ObservedFailureCount", observedFailureCount, ...
    "ObservedCrashCount", observedCrashCount, ...
    "ObservedOutcomeCount", observedOutcomeCount, ...
    "PassRate", double(passRate), ...
    "SummaryStatus", string(summaryStatus), ...
    "Ok", logical(summaryRowValid), ...
    "OkDefinition", "compatibility_alias_of_summary_row_valid");
end

function T = localEnsureSourceVars(T)
defaults = struct( ...
    "Status", "", ...
    "CRCPass", NaN, ...
    "Crash", false, ...
    "Goodput_Mbps", NaN);
names = fieldnames(defaults);
for i = 1:numel(names)
    name = names{i};
    if ismember(string(name), string(T.Properties.VariableNames))
        continue;
    end
    value = defaults.(name);
    if islogical(value)
        T.(name) = false(height(T), 1);
    elseif isstring(value) || ischar(value)
        T.(name) = strings(height(T), 1);
    else
        T.(name) = nan(height(T), 1);
    end
end
end
