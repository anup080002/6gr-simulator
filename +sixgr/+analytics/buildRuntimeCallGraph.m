function callGraph = buildRuntimeCallGraph(runDir)
%BUILDRUNTIMECALLGRAPH Export a profiler/time-profile backed call graph CSV.

arguments
    runDir {mustBeTextScalar}
end

layout = sixgr.report.resultLayout(runDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);

[T, sourceArtifact] = localBuildRows(layout);
outPath = fullfile(layout.ReportCSVDir, "runtime_call_graph.csv");
sixgr.analytics.writeAnalysisTable(outPath, T);
callGraph = struct("Path", string(outPath), "Rows", height(T), "SourceArtifact", sourceArtifact);
end

function [T, sourceArtifact] = localBuildRows(layout)
ledgerPath = fullfile(layout.ReportCSVDir, "runtime_call_ledger.csv");
profilePath = fullfile(layout.ReportCSVDir, "runtime_function_profile.csv");
edgePath = fullfile(layout.ReportCSVDir, "runtime_function_call_edges.csv");
timeProfilePath = fullfile(layout.ReportCSVDir, "time_profile_calls.csv");

L = localReadOptionalTable(ledgerPath);
if height(L) > 0
    T = localRowsFromLedger(L);
    sourceArtifact = "reports/csv/runtime_call_ledger.csv";
    return;
end

F = localReadOptionalTable(profilePath);
if height(F) > 0
    T = localRowsFromFunctionProfile(F);
    sourceArtifact = "reports/csv/runtime_function_profile.csv";
    return;
end

E = localReadOptionalTable(edgePath);
if height(E) > 0
    T = localRowsFromEdges(E);
    sourceArtifact = "reports/csv/runtime_function_call_edges.csv";
    return;
end

C = localReadOptionalTable(timeProfilePath);
if height(C) > 0
    T = localRowsFromTimeProfile(C);
    sourceArtifact = "reports/csv/time_profile_calls.csv";
    return;
end

T = localEmptyTable();
sourceArtifact = "no_runtime_profiler_rows";
end

function T = localRowsFromLedger(L)
if ~ismember("FunctionName", string(L.Properties.VariableNames))
    T = localEmptyTable();
    return;
end
names = strtrim(string(L.FunctionName));
names = names(strlength(names) > 0);
[uniqueNames,~,group] = unique(names,"stable");
rows = repmat(localEmptyRow(),numel(uniqueNames),1);
for i = 1:numel(uniqueNames)
    mask = group == i;
    rows(i).FunctionName = uniqueNames(i);
    rows(i).ParentFunctionName = "sixgr.lls6g.runners.runSingle";
    rows(i).NumCalls = sum(mask);
    rows(i).TotalTime_s = NaN;
    rows(i).SelfTime_s = NaN;
    rows(i).MeanTime_s = NaN;
    rows(i).SourceArtifact = "reports/csv/runtime_call_ledger.csv";
    rows(i).EvidenceClass = "ACTUAL_RUNTIME_ENTRY";
    rows(i).Status = "runtime_call_ledger_entry";
end
T = struct2table(rows);
end

function T = localRowsFromFunctionProfile(F)
rows = repmat(localEmptyRow(), height(F), 1);
for i = 1:height(F)
    rows(i).FunctionName = localStringValue(F(i,:), ["FunctionName","CompleteName","Name"], "");
    rows(i).ParentFunctionName = "";
    rows(i).NumCalls = localNumericValue(F(i,:), "NumCalls", NaN);
    rows(i).TotalTime_s = localNumericValue(F(i,:), "TotalTime_s", localNumericValue(F(i,:), "TotalTime", NaN));
    rows(i).SelfTime_s = localNumericValue(F(i,:), "SelfTimeApprox_s", localNumericValue(F(i,:), "SelfTime_s", NaN));
    rows(i).MeanTime_s = localSafeDivide(rows(i).TotalTime_s, rows(i).NumCalls);
    rows(i).SourceArtifact = "reports/csv/runtime_function_profile.csv";
    rows(i).EvidenceClass = "RUNTIME_DERIVED";
    rows(i).Status = "profiler_function_profile";
end
T = struct2table(rows);
T = localSortByTime(T);
end

function T = localRowsFromEdges(E)
rows = repmat(localEmptyRow(), height(E), 1);
for i = 1:height(E)
    rows(i).FunctionName = localStringValue(E(i,:), ["CalleeFunctionName","FunctionName","Name"], "");
    rows(i).ParentFunctionName = localStringValue(E(i,:), ["CallerFunctionName","ParentFunctionName"], "");
    rows(i).NumCalls = localNumericValue(E(i,:), "NumCalls", NaN);
    rows(i).TotalTime_s = localNumericValue(E(i,:), "TotalTime_s", localNumericValue(E(i,:), "TotalTime", NaN));
    rows(i).SelfTime_s = NaN;
    rows(i).MeanTime_s = localSafeDivide(rows(i).TotalTime_s, rows(i).NumCalls);
    rows(i).SourceArtifact = "reports/csv/runtime_function_call_edges.csv";
    rows(i).EvidenceClass = "RUNTIME_DERIVED";
    rows(i).Status = "profiler_call_edges";
end
T = struct2table(rows);
T = localSortByTime(T);
end

function T = localRowsFromTimeProfile(C)
rows = repmat(localEmptyRow(), height(C), 1);
for i = 1:height(C)
    rows(i).FunctionName = localStringValue(C(i,:), ["FunctionName","StageName","Label","Name"], "");
    rows(i).ParentFunctionName = "";
    rows(i).NumCalls = localNumericValue(C(i,:), ["NumCalls","CallCount","Count"], 1);
    rows(i).TotalTime_s = localNumericValue(C(i,:), ["Elapsed_s","TotalTime_s","TotalSeconds"], NaN);
    rows(i).SelfTime_s = rows(i).TotalTime_s;
    rows(i).MeanTime_s = localSafeDivide(rows(i).TotalTime_s, rows(i).NumCalls);
    rows(i).SourceArtifact = "reports/csv/time_profile_calls.csv";
    rows(i).EvidenceClass = "RUNTIME_DERIVED";
    rows(i).Status = "time_profiler_calls";
end
T = struct2table(rows);
T = localSortByTime(T);
end

function row = localEmptyRow()
row = struct("FunctionName", "", "ParentFunctionName", "", "NumCalls", NaN, ...
    "TotalTime_s", NaN, "SelfTime_s", NaN, "MeanTime_s", NaN, ...
    "SourceArtifact", "", "EvidenceClass", "", "Status", "");
end

function T = localEmptyTable()
T = table('Size', [0 9], ...
    'VariableTypes', {'string','string','double','double','double','double','string','string','string'}, ...
    'VariableNames', {'FunctionName','ParentFunctionName','NumCalls','TotalTime_s','SelfTime_s','MeanTime_s','SourceArtifact','EvidenceClass','Status'});
end

function T = localSortByTime(T)
if height(T) > 0 && any(string(T.Properties.VariableNames) == "TotalTime_s")
    T = sortrows(T, "TotalTime_s", "descend");
end
end

function value = localNumericValue(T, names, defaultValue)
value = defaultValue;
for name = string(names)
    if any(string(T.Properties.VariableNames) == name)
        v = T.(name);
        if iscell(v)
            v = v{1};
        else
            v = v(1);
        end
        if isnumeric(v) || islogical(v)
            value = double(v);
        else
            value = str2double(string(v));
        end
        if isfinite(value)
            return;
        end
    end
end
end

function value = localStringValue(T, names, defaultValue)
value = string(defaultValue);
for name = string(names)
    if any(string(T.Properties.VariableNames) == name)
        v = T.(name);
        if iscell(v)
            v = v{1};
        else
            v = v(1);
        end
        value = string(v);
        return;
    end
end
end

function y = localSafeDivide(a, b)
if ~isfinite(a) || ~isfinite(b) || b == 0
    y = NaN;
else
    y = a ./ b;
end
end

function T = localReadOptionalTable(pathStr)
pathStr = char(string(pathStr));
if exist(pathStr, "file") ~= 2
    T = table();
    return;
end
try
    T = readtable(pathStr, "VariableNamingRule", "preserve", "TextType", "string");
catch
    try
        T = readtable(pathStr, "VariableNamingRule", "preserve");
    catch
        T = table();
    end
end
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:analytics:buildRuntimeCallGraph:BadRunDir", "runDir must be a char vector or string scalar.");
end
end
