classdef TraceContext < handle
%SIXGR.TRACE.TRACECONTEXT Manage study-status and stage-progress artifacts.

    properties
        RunId (1,1) string
        ScenarioName (1,1) string
        RunFolder (1,1) string
        OutputRoot (1,1) string
        TotalSlots (1,1) double
        RequestedWorkers (1,1) double
        StatusPath (1,1) string
        StagePath (1,1) string
        StageProgressPath (1,1) string
        ArtifactTracePath (1,1) string
        IssueTracePath (1,1) string
        LatestLogPath (1,1) string = ""
        LatestIssueCount (1,1) double = 0
        LatestCriticalIssueCount (1,1) double = 0
        StageRows struct = struct([])
        CurrentStageIndex (1,1) double = 0
    end

    methods
        function obj = TraceContext(runId, scenarioName, runFolder, totalSlots, requestedWorkers, outputRoot)
            obj.RunId = string(runId);
            obj.ScenarioName = string(scenarioName);
            obj.RunFolder = string(runFolder);
            obj.OutputRoot = string(outputRoot);
            obj.TotalSlots = double(totalSlots);
            obj.RequestedWorkers = double(requestedWorkers);
            obj.StatusPath = fullfile(obj.RunFolder, "RUNNING.status.json");
            obj.StagePath = fullfile(obj.RunFolder, "RUNNING.stage.txt");
            obj.StageProgressPath = fullfile(obj.RunFolder, "reports", "csv", "live_stage_progress.csv");
            obj.ArtifactTracePath = fullfile(obj.RunFolder, "reports", "csv", "runtime_artifact_generation_trace.csv");
            obj.IssueTracePath = fullfile(obj.RunFolder, "reports", "csv", "runtime_issue_trace.csv");
            obj.StageRows = repmat(localStageRow("", NaN, "", "", "", NaN, false, false, false, NaN, NaN, 0, 0, 0, 0, "", ""), 0, 1);

            sixgr.util.ensureFolder(obj.RunFolder);
            sixgr.util.ensureFolder(fullfile(obj.RunFolder, "reports", "csv"));
            sixgr.util.ensureFolder(fullfile(obj.RunFolder, "reports", "json"));
            sixgr.util.ensureFolder(fullfile(obj.RunFolder, "reports", "md"));
            sixgr.util.ensureFolder(fullfile(obj.RunFolder, "reports", "html"));
            sixgr.util.ensureFolder(fullfile(obj.RunFolder, "reports", "profiling"));
            sixgr.util.ensureFolder(fullfile(obj.RunFolder, "reports", "text", "csv_summaries"));
            sixgr.util.ensureFolder(fullfile(obj.RunFolder, "config"));
            sixgr.util.ensureFolder(fullfile(obj.RunFolder, "logs"));
            sixgr.util.ensureFolder(fullfile(obj.RunFolder, "study_report"));

            obj.writeStatus("CurrentStage", "initialized");
            obj.writeStageText("initialized");
            sixgr.util.csvWriteTable(obj.StageProgressPath, localStageTable(struct([])));
            sixgr.util.csvWriteTable(obj.ArtifactTracePath, localArtifactTraceTable(struct([])));
            sixgr.util.csvWriteTable(obj.IssueTracePath, localIssueTraceTable(struct([])));
        end

        function startStage(obj, stageName, slotStart)
            if nargin < 3
                slotStart = NaN;
            end
            if obj.CurrentStageIndex >= 1 && obj.CurrentStageIndex <= numel(obj.StageRows)
                current = obj.StageRows(obj.CurrentStageIndex);
                if ~logical(current.Completed) && ~logical(current.Failed)
                    obj.completeStage("completed", slotStart, slotStart, 0, 0, 0, 0, "");
                end
            end
            obj.CurrentStageIndex = numel(obj.StageRows) + 1;
            obj.StageRows(obj.CurrentStageIndex, 1) = localStageRow( ... %#ok<AGROW>
                obj.RunId, obj.CurrentStageIndex, string(stageName), localNowText(), "", NaN, ...
                true, false, false, double(slotStart), NaN, 0, 0, 0, 0, "running", "");
            obj.flushStageProgress();
            obj.writeStageText(stageName);
            obj.writeStatus("CurrentStage", stageName, "CurrentSlot", slotStart);
        end

        function completeStage(obj, status, slotStart, slotEnd, artifactsCreated, csvRowsCreated, issuesCreated, criticalIssuesCreated, failureReason)
            if obj.CurrentStageIndex < 1 || obj.CurrentStageIndex > numel(obj.StageRows)
                return;
            end
            if nargin < 3
                slotStart = NaN;
            end
            if nargin < 4
                slotEnd = slotStart;
            end
            if nargin < 5
                artifactsCreated = 0;
            end
            if nargin < 6
                csvRowsCreated = 0;
            end
            if nargin < 7
                issuesCreated = 0;
            end
            if nargin < 8
                criticalIssuesCreated = 0;
            end
            if nargin < 9
                failureReason = "";
            end

            row = obj.StageRows(obj.CurrentStageIndex);
            row.EndedAt = localNowText();
            row.ElapsedSeconds = localElapsedSeconds(row.StartedAt, row.EndedAt);
            row.Completed = strcmpi(string(status), "completed");
            row.Failed = strcmpi(string(status), "failed");
            row.CurrentSlotStart = double(slotStart);
            row.CurrentSlotEnd = double(slotEnd);
            row.ArtifactsCreated = double(artifactsCreated);
            row.CsvRowsCreated = double(csvRowsCreated);
            row.IssuesCreated = double(issuesCreated);
            row.CriticalIssuesCreated = double(criticalIssuesCreated);
            row.Status = string(status);
            row.FailureReason = string(failureReason);
            obj.StageRows(obj.CurrentStageIndex) = row;
            obj.LatestIssueCount = obj.LatestIssueCount + double(issuesCreated);
            obj.LatestCriticalIssueCount = obj.LatestCriticalIssueCount + double(criticalIssuesCreated);
            obj.flushStageProgress();
            obj.writeStatus("CurrentStage", row.StageName, "CurrentSlot", slotEnd, ...
                "LatestIssueCount", obj.LatestIssueCount, ...
                "LatestCriticalIssueCount", obj.LatestCriticalIssueCount);
        end

        function recordArtifact(obj, artifactPath, category, status, note)
            if nargin < 5
                note = "";
            end
            T = localReadOptionalTable(obj.ArtifactTracePath);
            row = table( ...
                obj.RunId, ...
                string(localNowText()), ...
                string(artifactPath), ...
                string(category), ...
                string(status), ...
                string(note), ...
                'VariableNames', {'RunId','Timestamp','ArtifactPath','Category','Status','Note'});
            T = [T; row]; %#ok<AGROW>
            sixgr.util.csvWriteTable(obj.ArtifactTracePath, T);
        end

        function recordIssue(obj, issueId, severity, sourcePath, message, isCritical)
            if nargin < 6
                isCritical = false;
            end
            T = localReadOptionalTable(obj.IssueTracePath);
            row = table( ...
                obj.RunId, ...
                string(localNowText()), ...
                string(issueId), ...
                string(severity), ...
                string(sourcePath), ...
                string(message), ...
                logical(isCritical), ...
                'VariableNames', {'RunId','Timestamp','IssueId','Severity','Source','Message','Critical'});
            T = [T; row]; %#ok<AGROW>
            sixgr.util.csvWriteTable(obj.IssueTracePath, T);
            obj.LatestIssueCount = obj.LatestIssueCount + 1;
            obj.LatestCriticalIssueCount = obj.LatestCriticalIssueCount + double(logical(isCritical));
            obj.writeStatus("LatestIssueCount", obj.LatestIssueCount, ...
                "LatestCriticalIssueCount", obj.LatestCriticalIssueCount);
        end

        function finalize(obj, runCompleted, resultOk, fatalMessage, workersUsed, latestLogPath)
            if nargin < 6
                latestLogPath = obj.LatestLogPath;
            end
            if strlength(string(latestLogPath)) > 0
                obj.LatestLogPath = string(latestLogPath);
            end
            obj.writeStageText(localTernary(logical(runCompleted), "completed", "finished_with_errors"));
            obj.writeStatus( ...
                "RunCompleted", logical(runCompleted), ...
                "ResultOk", logical(resultOk), ...
                "FatalError", strlength(strtrim(string(fatalMessage))) > 0, ...
                "FatalErrorMessage", string(fatalMessage), ...
                "ParallelWorkersUsed", double(workersUsed), ...
                "LatestLogPath", obj.LatestLogPath);
        end

        function writeStatus(obj, varargin)
            payload = struct( ...
                "RunId", obj.RunId, ...
                "ScenarioName", obj.ScenarioName, ...
                "StartedAt", localStartedAt(obj.StageRows), ...
                "LastUpdateAt", localNowText(), ...
                "CurrentStage", localCurrentStage(obj.StageRows, obj.CurrentStageIndex), ...
                "CurrentSlot", NaN, ...
                "TotalSlots", obj.TotalSlots, ...
                "CurrentUE", NaN, ...
                "CurrentSnapshot", NaN, ...
                "RunCompleted", false, ...
                "ResultOk", false, ...
                "FatalError", false, ...
                "FatalErrorMessage", "", ...
                "MatlabPID", localMatlabPID(), ...
                "ParallelWorkersRequested", obj.RequestedWorkers, ...
                "ParallelWorkersUsed", NaN, ...
                "OutputRoot", obj.OutputRoot, ...
                "LatestLogPath", obj.LatestLogPath, ...
                "LatestIssueCount", obj.LatestIssueCount, ...
                "LatestCriticalIssueCount", obj.LatestCriticalIssueCount);
            for i = 1:2:numel(varargin)
                payload.(char(string(varargin{i}))) = varargin{i+1};
            end
            sixgr.util.jsonWrite(obj.StatusPath, payload);
        end

        function flushStageProgress(obj)
            sixgr.util.csvWriteTable(obj.StageProgressPath, localStageTable(obj.StageRows));
        end

        function writeStageText(obj, stageName)
            fid = fopen(obj.StagePath, "w");
            if fid < 0
                return;
            end
            cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, "%s\n", char(string(stageName)));
        end
    end
end

function T = localStageTable(rows)
if isempty(rows)
    T = struct2table(repmat(localStageRow("", NaN, "", "", "", NaN, false, false, false, NaN, NaN, 0, 0, 0, 0, "", ""), 0, 1), "AsArray", true);
    return;
end
T = struct2table(rows, "AsArray", true);
end

function row = localStageRow(runId, idx, stageName, startedAt, endedAt, elapsedSeconds, started, completed, failed, slotStart, slotEnd, artifactsCreated, csvRowsCreated, issuesCreated, criticalIssuesCreated, status, failureReason)
row = struct( ...
    "RunId", string(runId), ...
    "StageIndex", double(idx), ...
    "StageName", string(stageName), ...
    "StartedAt", string(startedAt), ...
    "EndedAt", string(endedAt), ...
    "ElapsedSeconds", double(elapsedSeconds), ...
    "Started", logical(started), ...
    "Completed", logical(completed), ...
    "Failed", logical(failed), ...
    "CurrentSlotStart", double(slotStart), ...
    "CurrentSlotEnd", double(slotEnd), ...
    "ArtifactsCreated", double(artifactsCreated), ...
    "CsvRowsCreated", double(csvRowsCreated), ...
    "IssuesCreated", double(issuesCreated), ...
    "CriticalIssuesCreated", double(criticalIssuesCreated), ...
    "Status", string(status), ...
    "FailureReason", string(failureReason));
end

function T = localArtifactTraceTable(rows)
if isempty(rows)
    T = table(strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
        'VariableNames', {'RunId','Timestamp','ArtifactPath','Category','Status','Note'});
    return;
end
T = struct2table(rows, "AsArray", true);
end

function T = localIssueTraceTable(rows)
if isempty(rows)
    T = table(strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), false(0,1), ...
        'VariableNames', {'RunId','Timestamp','IssueId','Severity','Source','Message','Critical'});
    return;
end
T = struct2table(rows, "AsArray", true);
end

function text = localNowText()
text = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
end

function secondsValue = localElapsedSeconds(startedAt, endedAt)
try
    t0 = datetime(startedAt, "InputFormat", "yyyy-MM-dd'T'HH:mm:ss'Z'", "TimeZone", "UTC");
    t1 = datetime(endedAt, "InputFormat", "yyyy-MM-dd'T'HH:mm:ss'Z'", "TimeZone", "UTC");
    secondsValue = seconds(t1 - t0);
catch
    secondsValue = NaN;
end
end

function out = localCurrentStage(rows, idx)
out = "initialized";
if isempty(rows) || idx < 1 || idx > numel(rows)
    return;
end
out = string(rows(idx).StageName);
end

function out = localStartedAt(rows)
out = localNowText();
if ~isempty(rows)
    out = string(rows(1).StartedAt);
end
end

function value = localMatlabPID()
value = NaN;
try
    value = double(feature("getpid"));
catch
end
end

function T = localReadOptionalTable(pathStr)
if exist(pathStr, "file") ~= 2
    [~, ~, ext] = fileparts(pathStr);
    if strcmpi(ext, ".csv")
        if contains(pathStr, "runtime_artifact_generation_trace.csv")
            T = localArtifactTraceTable(struct([]));
        else
            T = localIssueTraceTable(struct([]));
        end
        return;
    end
end
T = readtable(pathStr, "VariableNamingRule", "preserve");
end

function out = localTernary(tf, a, b)
if tf
    out = a;
else
    out = b;
end
end
