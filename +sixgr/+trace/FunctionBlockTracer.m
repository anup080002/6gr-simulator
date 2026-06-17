classdef FunctionBlockTracer
%SIXGR.TRACE.FUNCTIONBLOCKTRACER Audit expected process coverage and bypasses.

    methods (Static)
        function T = generate(runFolder, runId, registryPath)
            layout = sixgr.report.resultLayout(runFolder);
            registry = sixgr.lls6g.config.readConfigFile(registryPath);
            processList = sixgr.util.structGet(registry, "required_processes", struct([]));
            if isempty(processList)
                T = struct2table(repmat(localEmptyRow(), 0, 1), "AsArray", true);
                return;
            end

            prof = localReadOptionalTable(fullfile(layout.ReportCSVDir, "runtime_function_profile.csv"));
            issues = localReadOptionalTable(fullfile(layout.ReportCSVDir, "result_issue_registry.csv"));
            rows = repmat(localEmptyRow(), 0, 1);
            unusedRows = repmat(localUnusedRow(), 0, 1);

            for i = 1:numel(processList)
                spec = processList(i);
                [pathsExist, measurementEvidence, pathList] = localArtifactEvidence(runFolder, spec);
                [callCount, runtimeSeconds, matchedFunctions] = localFunctionEvidence(prof, spec);
                issueId = localIssueIdForProcess(issues, spec);
                proxyUsed = localIssueFlag(issues, spec, "proxy");
                fallbackUsed = localIssueFlag(issues, spec, "fallback");
                skipped = localIssueFlag(issues, spec, "skip");
                called = pathsExist || callCount > 0;
                configOnlyEvidence = pathsExist && ~measurementEvidence;
                bypassed = logical(sixgr.util.structGet(spec, "required", true)) && ~called;
                hardcodedInputUsed = false;
                implementationPass = logical(sixgr.util.structGet(spec, "required", true)) && called && measurementEvidence && ~proxyUsed && ~fallbackUsed && ~configOnlyEvidence;
                if ~called && ~isempty(matchedFunctions)
                    implementationPass = false;
                end
                failureReason = "";
                if bypassed
                    failureReason = "required_process_not_observed";
                    issueId = localDefaultIssue(issueId, "BYPASS-01");
                elseif configOnlyEvidence
                    failureReason = "config_only_evidence";
                    issueId = localDefaultIssue(issueId, "BYPASS-02");
                elseif ~measurementEvidence
                    failureReason = "measurement_evidence_missing";
                    issueId = localDefaultIssue(issueId, "REALPHY-001");
                elseif proxyUsed
                    failureReason = "proxy_evidence_detected";
                elseif fallbackUsed
                    failureReason = "fallback_evidence_detected";
                elseif skipped
                    failureReason = "process_marked_skipped";
                end

                rows(end+1, 1) = struct( ... %#ok<AGROW>
                    "RunId", string(runId), ...
                    "BlockId", string(sixgr.util.structGet(spec, "process_id", "")), ...
                    "Subsystem", string(localSubsystem(spec)), ...
                    "FunctionName", string(strjoin(string(matchedFunctions), "|")), ...
                    "FilePath", string(strjoin(string(pathList), "|")), ...
                    "ExpectedForScenario", logical(sixgr.util.structGet(spec, "required", true)), ...
                    "Called", logical(called), ...
                    "CallCount", double(callCount), ...
                    "FirstCallTimestamp", "", ...
                    "LastCallTimestamp", "", ...
                    "TotalRuntimeSeconds", double(runtimeSeconds), ...
                    "InputsCaptured", logical(pathsExist), ...
                    "OutputsCaptured", logical(pathsExist), ...
                    "Bypassed", logical(bypassed), ...
                    "Skipped", logical(skipped), ...
                    "ProxyUsed", logical(proxyUsed), ...
                    "FallbackUsed", logical(fallbackUsed), ...
                    "HardcodedInputUsed", logical(hardcodedInputUsed), ...
                    "ConfigOnlyEvidence", logical(configOnlyEvidence), ...
                    "MeasurementEvidence", logical(measurementEvidence), ...
                    "ImplementationPass", logical(implementationPass), ...
                    "IssueIdIfFailed", string(issueId), ...
                    "FailureReason", string(failureReason));

                if callCount < 1
                    unusedRows(end+1, 1) = struct( ... %#ok<AGROW>
                        "RunId", string(runId), ...
                        "ProcessId", string(sixgr.util.structGet(spec, "process_id", "")), ...
                        "ProcessName", string(sixgr.util.structGet(spec, "process_name", "")), ...
                        "ExpectedFunctionPatterns", string(strjoin(localPatternList(spec, "function_patterns"), "|")), ...
                        "Observed", logical(called), ...
                        "MeasurementEvidence", logical(measurementEvidence), ...
                        "FailureReason", string(failureReason));
                end
            end

            T = struct2table(rows, "AsArray", true);
            sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "runtime_function_block_trace.csv"), T);
            sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "runtime_function_coverage.csv"), T(:, {'RunId','BlockId','Subsystem','ExpectedForScenario','Called','Bypassed','Skipped','ProxyUsed','FallbackUsed','MeasurementEvidence','ImplementationPass'}));
            sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "unused_expected_functions.csv"), struct2table(unusedRows, "AsArray", true));
            bypassed = T(logical(T.ExpectedForScenario) & (logical(T.Bypassed) | logical(T.ConfigOnlyEvidence) | logical(T.ProxyUsed) | logical(T.FallbackUsed)), :);
            sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "e2e_unused_bypassed_processes.csv"), bypassed);
            sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "bypassed_required_processes.csv"), bypassed(:, {'RunId','BlockId','Subsystem','Bypassed','ConfigOnlyEvidence','ProxyUsed','FallbackUsed','IssueIdIfFailed','FailureReason'}));
        end
    end
end

function [pathsExist, measurementEvidence, pathList] = localArtifactEvidence(runFolder, spec)
patterns = localPatternList(spec, "artifact_patterns");
pathList = strings(0, 1);
measurementEvidence = false;
for i = 1:numel(patterns)
    parts = strtrim(split(patterns(i), "|"));
    for j = 1:numel(parts)
        rel = string(parts(j));
        if strlength(rel) == 0
            continue;
        end
        absPath = fullfile(runFolder, char(rel));
        if exist(absPath, "file") == 2
            pathList(end+1, 1) = rel; %#ok<AGROW>
            if ~any(startsWith(rel, ["config/", "meta/", "reports/md/", "reports/html/", "reports/json/"]))
                measurementEvidence = true;
            end
        end
    end
end
pathsExist = ~isempty(pathList);
end

function [callCount, runtimeSeconds, matchedFunctions] = localFunctionEvidence(prof, spec)
callCount = 0;
runtimeSeconds = 0;
matchedFunctions = strings(0, 1);
if isempty(prof)
    return;
end
patterns = lower(localPatternList(spec, "function_patterns"));
if isempty(patterns)
    return;
end
nameVar = localFindVar(prof, ["FunctionName","Function","Name"]);
timeVar = localFindVar(prof, ["TotalTimeSeconds","TotalTime_s","TotalTime","Seconds"]);
if strlength(nameVar) == 0
    return;
end
names = lower(string(prof.(nameVar)));
mask = false(height(prof), 1);
for i = 1:numel(patterns)
    if strlength(patterns(i)) == 0
        continue;
    end
    mask = mask | contains(names, patterns(i));
end
matchedFunctions = unique(string(prof.(nameVar)(mask)));
callCount = height(prof(mask, :));
if strlength(timeVar) > 0
    runtimeSeconds = sum(double(prof.(timeVar)(mask)), "omitnan");
end
end

function out = localPatternList(spec, fieldName)
raw = sixgr.util.structGet(spec, fieldName, strings(0, 1));
if ischar(raw) || isstring(raw)
    out = string(raw(:));
elseif iscell(raw)
    out = string(raw(:));
else
    out = string(raw);
    out = out(:);
end
end

function name = localFindVar(T, candidates)
name = "";
vars = string(T.Properties.VariableNames);
candidates = string(candidates(:));
for i = 1:numel(candidates)
    hit = vars(strcmpi(vars, candidates(i)));
    if ~isempty(hit)
        name = string(hit(1));
        return;
    end
end
end

function issueId = localIssueIdForProcess(issues, spec)
issueId = "";
if isempty(issues)
    return;
end
procName = lower(string(sixgr.util.structGet(spec, "process_name", "")));
procId = lower(string(sixgr.util.structGet(spec, "process_id", "")));
searchText = lower(localIssueSearchText(issues));
mask = contains(searchText, procName) | contains(searchText, procId);
idVar = localFindVar(issues, ["IssueId","IssueID","ID"]);
if ~any(mask) || strlength(idVar) == 0
    return;
end
issueId = string(issues.(idVar)(find(mask, 1, "first")));
end

function tf = localIssueFlag(issues, spec, needle)
tf = false;
if isempty(issues)
    return;
end
procName = lower(string(sixgr.util.structGet(spec, "process_name", "")));
procId = lower(string(sixgr.util.structGet(spec, "process_id", "")));
text = lower(localIssueSearchText(issues));
mask = (contains(text, procName) | contains(text, procId)) & contains(text, lower(string(needle)));
tf = any(mask);
end

function text = localIssueSearchText(T)
vars = intersect(string(T.Properties.VariableNames), ["IssueId","IssueID","IssueName","Reason","FailureReason","IssueSource","Message","Notes"]);
text = strings(height(T), 1);
for i = 1:numel(vars)
    text = text + " " + lower(string(T.(vars(i))));
end
end

function out = localDefaultIssue(issueId, defaultIssue)
if strlength(strtrim(string(issueId))) == 0
    out = string(defaultIssue);
else
    out = string(issueId);
end
end

function subsystem = localSubsystem(spec)
procId = lower(string(sixgr.util.structGet(spec, "process_id", "")));
if any(contains(procId, ["prach","ra"]))
    subsystem = "random_access";
elseif any(contains(procId, ["pdcch","dci","pucch","sib1","pbch","ssb","mib"]))
    subsystem = "control";
elseif any(contains(procId, ["pdsch","dlsch"]))
    subsystem = "downlink_data";
elseif any(contains(procId, ["pusch","ulsch"]))
    subsystem = "uplink_data";
elseif any(contains(procId, ["srs","trs","csirs","ptrs"]))
    subsystem = "reference_signal";
elseif any(contains(procId, ["mimo","beam","precoder"]))
    subsystem = "mimo_beamforming";
elseif any(contains(procId, ["harq","k0k1k2"]))
    subsystem = "mac_harq";
elseif any(contains(procId, ["channel","doppler","pathloss","cfo","noise","timing","iq","quantization"]))
    subsystem = "rf_channel";
elseif any(contains(procId, ["traffic","mac_pdu","mac_sdu","kpi"]))
    subsystem = "traffic_kpi";
else
    subsystem = "reporting";
end
end

function T = localReadOptionalTable(pathStr)
if exist(pathStr, "file") ~= 2
    T = table();
    return;
end
T = readtable(pathStr, "VariableNamingRule", "preserve");
end

function row = localEmptyRow()
row = struct( ...
    "RunId", "", ...
    "BlockId", "", ...
    "Subsystem", "", ...
    "FunctionName", "", ...
    "FilePath", "", ...
    "ExpectedForScenario", false, ...
    "Called", false, ...
    "CallCount", NaN, ...
    "FirstCallTimestamp", "", ...
    "LastCallTimestamp", "", ...
    "TotalRuntimeSeconds", NaN, ...
    "InputsCaptured", false, ...
    "OutputsCaptured", false, ...
    "Bypassed", false, ...
    "Skipped", false, ...
    "ProxyUsed", false, ...
    "FallbackUsed", false, ...
    "HardcodedInputUsed", false, ...
    "ConfigOnlyEvidence", false, ...
    "MeasurementEvidence", false, ...
    "ImplementationPass", false, ...
    "IssueIdIfFailed", "", ...
    "FailureReason", "");
end

function row = localUnusedRow()
row = struct( ...
    "RunId", "", ...
    "ProcessId", "", ...
    "ProcessName", "", ...
    "ExpectedFunctionPatterns", "", ...
    "Observed", false, ...
    "MeasurementEvidence", false, ...
    "FailureReason", "");
end
