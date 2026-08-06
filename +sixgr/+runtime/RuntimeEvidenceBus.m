classdef RuntimeEvidenceBus < handle
%RUNTIMEEVIDENCEBUS Append-only runtime evidence journal for LLS runs.

    properties
        RunFolder (1,1) string
        RunId (1,1) string
        ExecutionId (1,1) string
        FinalizationId (1,1) string
        AttemptId (1,1) string
        DefaultContext struct = struct()
    end

    methods
        function obj = RuntimeEvidenceBus(runFolder, varargin)
            p = inputParser;
            p.addRequired("runFolder", @(x)ischar(x) || isstring(x));
            p.addParameter("RunId", "", @(x)ischar(x) || isstring(x));
            p.addParameter("ExecutionId", "", @(x)ischar(x) || isstring(x));
            p.addParameter("FinalizationId", "", @(x)ischar(x) || isstring(x));
            p.addParameter("AttemptId", "attempt_001", @(x)ischar(x) || isstring(x));
            p.addParameter("Context", struct(), @(x)isstruct(x));
            p.parse(runFolder, varargin{:});

            obj.RunFolder = string(runFolder);
            obj.RunId = string(p.Results.RunId);
            if strlength(obj.RunId) == 0
                obj.RunId = sixgr.runtime.RuntimeEvidenceBus.deriveRunId(obj.RunFolder);
            end
            obj.ExecutionId = string(p.Results.ExecutionId);
            if strlength(obj.ExecutionId) == 0
                obj.ExecutionId = obj.RunId;
            end
            obj.FinalizationId = string(p.Results.FinalizationId);
            obj.AttemptId = string(p.Results.AttemptId);
            if strlength(obj.AttemptId) == 0
                error("sixgr:runtime:AttemptIdentityRequired", ...
                    "Runtime evidence requires a non-empty AttemptId.");
            end
            obj.DefaultContext = p.Results.Context;
            sixgr.runtime.RuntimeEvidenceBus.prepareRunFolder(obj.RunFolder);
            obj.emit("RUN_START", "Status", "started", ...
                "Message", "runtime evidence bus initialized", ...
                "EvidenceClass", "LIVE_RUNTIME_BOUNDARY");
        end

        function event = emit(obj, eventType, varargin)
            event = sixgr.runtime.RuntimeEvidenceBus.appendStandaloneEvent( ...
                obj.RunFolder, eventType, "RunId", obj.RunId, ...
                "ExecutionId", obj.ExecutionId, ...
                "FinalizationId", obj.FinalizationId, ...
                "AttemptId", obj.AttemptId, ...
                "Context", obj.DefaultContext, varargin{:});
        end

        function event = heartbeat(obj, stageName, varargin)
            event = obj.emit("HEARTBEAT", "StageName", stageName, ...
                "Status", "progress", varargin{:});
        end

        function event = stageStart(obj, stageName, varargin)
            event = obj.emit("STAGE_START", "StageName", stageName, ...
                "Status", "started", varargin{:});
        end

        function event = stageEnd(obj, stageName, varargin)
            event = obj.emit("STAGE_END", "StageName", stageName, ...
                "Status", "completed", varargin{:});
        end

        function event = stageFail(obj, stageName, ME, varargin)
            if nargin < 3
                ME = [];
            end
            event = obj.emit("STAGE_FAIL", "StageName", stageName, ...
                "Status", "failed", "ReasonCode", localExceptionId(ME), ...
                "Message", localExceptionMessage(ME), varargin{:});
        end

        function scope = enterBlock(obj, blockId, varargin)
            scope = sixgr.runtime.RuntimeBlockScope(obj, blockId, varargin{:});
        end

        function event = captureValue(obj, valueName, value, varargin)
            meta = sixgr.runtime.RuntimeEvidenceBus.valueMetadata(valueName, value, varargin{:});
            event = obj.emit("VALUE_CAPTURE", "Status", "captured", ...
                "EvidenceClass", "LIVE_RUNTIME", "Context", meta.Context, ...
                "Message", meta.Message, "ReasonCode", meta.ValueHash);
        end

        function close(obj, status)
            if nargin < 2
                status = "completed";
            end
            obj.emit("RUN_END", "Status", status, ...
                "EvidenceClass", "LIVE_RUNTIME_BOUNDARY");
        end
    end

    methods (Static)
        function prepareRunFolder(runFolder)
            runFolder = string(runFolder);
            localEnsureFolder(fullfile(runFolder, "runtime", "journal"));
            localEnsureFolder(fullfile(runFolder, "runtime", "csv"));
            localEnsureFolder(fullfile(runFolder, "runtime", "payloads"));
            localEnsureFolder(fullfile(runFolder, "reports", "csv"));
            localEnsureFolder(fullfile(runFolder, "reports", "json"));
        end

        function runId = deriveRunId(runFolder)
            runFolder = string(runFolder);
            [~, name] = fileparts(char(runFolder));
            if isempty(name)
                name = "run";
            end
            runId = string(name);
        end

        function event = appendStandaloneEvent(runFolder, eventType, varargin)
            p = inputParser;
            p.addRequired("runFolder", @(x)ischar(x) || isstring(x));
            p.addRequired("eventType", @(x)ischar(x) || isstring(x));
            p.addParameter("RunId", "", @(x)ischar(x) || isstring(x));
            p.addParameter("ExecutionId", "", @(x)ischar(x) || isstring(x));
            p.addParameter("FinalizationId", "", @(x)ischar(x) || isstring(x));
            p.addParameter("AttemptId", "attempt_001", @(x)ischar(x) || isstring(x));
            p.addParameter("Context", struct(), @(x)isstruct(x));
            p.addParameter("StageId", "", @(x)ischar(x) || isstring(x) || isnumeric(x));
            p.addParameter("StageName", "", @(x)ischar(x) || isstring(x));
            p.addParameter("BlockId", "", @(x)ischar(x) || isstring(x));
            p.addParameter("CallId", "", @(x)ischar(x) || isstring(x));
            p.addParameter("ParentCallId", "", @(x)ischar(x) || isstring(x));
            p.addParameter("FunctionName", "", @(x)ischar(x) || isstring(x));
            p.addParameter("SourceFile", "", @(x)ischar(x) || isstring(x));
            p.addParameter("SourceLine", NaN, @(x)isnumeric(x) || ischar(x) || isstring(x));
            p.addParameter("Status", "", @(x)ischar(x) || isstring(x));
            p.addParameter("ReasonCode", "", @(x)ischar(x) || isstring(x) || isnumeric(x));
            p.addParameter("Message", "", @(x)ischar(x) || isstring(x) || isnumeric(x));
            p.addParameter("EvidenceClass", "LIVE_RUNTIME", @(x)ischar(x) || isstring(x));
            p.addParameter("ArtifactId", "", @(x)ischar(x) || isstring(x));
            p.addParameter("RelativePath", "", @(x)ischar(x) || isstring(x));
            p.addParameter("TemporaryPath", "", @(x)ischar(x) || isstring(x));
            p.addParameter("ByteCount", NaN, @(x)isnumeric(x));
            p.addParameter("SHA256", "", @(x)ischar(x) || isstring(x));
            p.addParameter("ValidationStatus", "", @(x)ischar(x) || isstring(x));
            p.addParameter("CommitStatus", "", @(x)ischar(x) || isstring(x));
            p.addParameter("FailureReason", "", @(x)ischar(x) || isstring(x));
            p.addParameter("DroppedEventCount", 0, @(x)isnumeric(x));
            p.parse(runFolder, eventType, varargin{:});

            runFolder = string(runFolder);
            sixgr.runtime.RuntimeEvidenceBus.prepareRunFolder(runFolder);
            runId = string(p.Results.RunId);
            if strlength(runId) == 0
                runId = sixgr.runtime.RuntimeEvidenceBus.deriveRunId(runFolder);
            end
            executionId = string(p.Results.ExecutionId);
            if strlength(executionId) == 0
                executionId = runId;
            end
            finalizationId = string(p.Results.FinalizationId);
            attemptId = string(p.Results.AttemptId);
            if strlength(attemptId) == 0
                error("sixgr:runtime:AttemptIdentityRequired", ...
                    "Runtime evidence requires a non-empty AttemptId.");
            end

            context = localMergeContext(localDefaultContext(), p.Results.Context);
            [globalSeq, workerSeq, monotonicSeconds] = localNextSequence(runFolder, context.worker_id);
            event = struct( ...
                "schema_name", "sixgr.runtime.event", ...
                "schema_version", "2.0.0", ...
                "attempt_id", attemptId, ...
                "execution_id", executionId, ...
                "finalization_id", finalizationId, ...
                "run_id", runId, ...
                "event_id", localUUID(), ...
                "global_event_sequence", double(globalSeq), ...
                "worker_event_sequence", double(workerSeq), ...
                "event_type", upper(string(eventType)), ...
                "timestamp_utc", sixgr.util.utcNowISO8601(), ...
                "monotonic_time_s", double(monotonicSeconds), ...
                "simulation_time_s", double(context.simulation_time_s), ...
                "frame", double(context.frame), ...
                "slot", double(context.slot), ...
                "symbol", double(context.symbol), ...
                "cell_id", localString(context.cell_id), ...
                "ue_id", localString(context.ue_id), ...
                "direction", localString(context.direction), ...
                "worker_id", localString(context.worker_id), ...
                "block_id", localFirstString(p.Results.BlockId, context.block_id), ...
                "call_id", localFirstString(p.Results.CallId, context.call_id), ...
                "parent_call_id", localFirstString(p.Results.ParentCallId, context.parent_call_id), ...
                "function_name", string(p.Results.FunctionName), ...
                "source_file", string(p.Results.SourceFile), ...
                "source_line", localNumericOrString(p.Results.SourceLine), ...
                "status", string(p.Results.Status), ...
                "reason_code", string(p.Results.ReasonCode), ...
                "message", string(p.Results.Message), ...
                "evidence_class", string(p.Results.EvidenceClass), ...
                "stage_id", string(p.Results.StageId), ...
                "stage_name", string(p.Results.StageName), ...
                "elapsed_stage_s", NaN, ...
                "process_memory_bytes", localProcessMemoryBytes(), ...
                "worker_memory_bytes", NaN, ...
                "output_directory_bytes", NaN, ...
                "open_figure_count", localOpenFigureCount(), ...
                "pending_future_count", NaN, ...
                "queued_event_count", NaN, ...
                "last_completed_artifact", "", ...
                "artifact_id", string(p.Results.ArtifactId), ...
                "relative_path", string(p.Results.RelativePath), ...
                "temporary_path", string(p.Results.TemporaryPath), ...
                "byte_count", double(p.Results.ByteCount), ...
                "sha256", string(p.Results.SHA256), ...
                "validation_status", string(p.Results.ValidationStatus), ...
                "commit_status", string(p.Results.CommitStatus), ...
                "failure_reason", string(p.Results.FailureReason), ...
                "dropped_event_count", double(p.Results.DroppedEventCount));

            localPreflightDerivedCSV(runFolder, event);
            localAppendJSONL(localJournalPath(runFolder, event.event_type), event);
            localAppendDerivedCSV(runFolder, event);
        end

        function summary = rebuildDerivedCSVViews(runFolder)
            %REBUILDDERIVEDCSVVIEWS Recreate versioned CSV views from JSONL truth.
            % Runtime CSVs are derived projections. Rebuild them from the
            % authoritative journal and quarantine any previous bytes.
            runFolder = string(runFolder);
            journalRoot = fullfile(runFolder, "runtime", "journal");
            if ~isfolder(journalRoot)
                error("sixgr:runtime:JournalRootMissing", ...
                    "Runtime journal folder is missing: %s", char(journalRoot));
            end

            journalFiles = dir(fullfile(journalRoot, "*.jsonl"));
            events = cell(0, 1);
            for fileIndex = 1:numel(journalFiles)
                pathValue = fullfile(journalFiles(fileIndex).folder, journalFiles(fileIndex).name);
                lines = splitlines(string(fileread(pathValue)));
                lines = lines(strlength(strtrim(lines)) > 0);
                for lineIndex = 1:numel(lines)
                    try
                        event = jsondecode(char(lines(lineIndex)));
                    catch ME
                        error("sixgr:runtime:JournalSchemaInvalid", ...
                            "Runtime journal %s contains invalid JSON at line %d: %s", ...
                            pathValue, lineIndex, ME.message);
                    end
                    if ~isfield(event, "schema_name") || ...
                            ~isfield(event, "schema_version") || ...
                            string(event.schema_name) ~= "sixgr.runtime.event" || ...
                            string(event.schema_version) ~= "2.0.0"
                        error("sixgr:runtime:JournalSchemaMismatch", ...
                            "Cannot rebuild runtime CSVs from noncanonical event at %s line %d.", ...
                            pathValue, lineIndex);
                    end
                    events{end + 1, 1} = event; %#ok<AGROW>
                end
            end
            if isempty(events)
                error("sixgr:runtime:JournalEvidenceMissing", ...
                    "No runtime JSONL events are available under %s.", char(journalRoot));
            end

            sequence = cellfun(@(event) double(localEventValue(event, ...
                "global_event_sequence")), events);
            if any(~isfinite(sequence)) || numel(unique(sequence)) ~= numel(sequence)
                error("sixgr:runtime:JournalSequenceInvalid", ...
                    "Runtime journal event sequences must be finite and unique before rebuild.");
            end
            [~, order] = sort(sequence);
            events = events(order);

            workspaceRoot = fullfile(runFolder, "runtime", ...
                ".csv_rebuild_" + localUUID());
            localEnsureFolder(workspaceRoot);
            cleanupWorkspace = onCleanup(@() localRemoveFolder(workspaceRoot)); %#ok<NASGU>
            for eventIndex = 1:numel(events)
                localAppendDerivedCSV(workspaceRoot, events{eventIndex});
            end

            viewNames = ["artifact_transactions.csv", "block_call_trace.csv", ...
                "progress_heartbeat.csv", "stage_timing_events.csv", ...
                "warning_exception_trace.csv", "message_flow.csv"];
            targetRoot = fullfile(runFolder, "runtime", "csv");
            quarantineRoot = fullfile(runFolder, "runtime", "quarantine", ...
                "csv_schema_rebuild_" + replace(replace(replace( ...
                sixgr.util.utcNowISO8601(), ":", ""), "-", ""), ".", ""));
            rebuilt = strings(0, 1);
            quarantined = strings(0, 1);
            for name = viewNames
                sourcePath = fullfile(workspaceRoot, "runtime", "csv", name);
                if exist(sourcePath, "file") ~= 2
                    continue;
                end
                targetPath = fullfile(targetRoot, name);
                backupPath = "";
                if exist(targetPath, "file") == 2
                    localEnsureFolder(quarantineRoot);
                    backupPath = fullfile(quarantineRoot, name);
                    [moved, message] = movefile(char(targetPath), char(backupPath), "f");
                    if ~moved
                        error("sixgr:runtime:CSVQuarantineFailed", ...
                            "Unable to quarantine %s: %s", char(targetPath), message);
                    end
                    quarantined(end + 1, 1) = string(backupPath); %#ok<AGROW>
                end
                [moved, message] = movefile(char(sourcePath), char(targetPath), "f");
                if ~moved
                    if strlength(backupPath) > 0 && exist(backupPath, "file") == 2
                        movefile(char(backupPath), char(targetPath), "f");
                    end
                    error("sixgr:runtime:CSVRebuildPublishFailed", ...
                        "Unable to publish rebuilt runtime CSV %s: %s", ...
                        char(targetPath), message);
                end
                rebuilt(end + 1, 1) = string(targetPath); %#ok<AGROW>
            end

            summary = struct( ...
                "EventCount", numel(events), ...
                "RebuiltCount", numel(rebuilt), ...
                "RebuiltPaths", rebuilt, ...
                "QuarantinedCount", numel(quarantined), ...
                "QuarantinedPaths", quarantined, ...
                "QuarantineRoot", string(quarantineRoot));
        end

        function meta = valueMetadata(valueName, value, varargin)
            p = inputParser;
            p.addRequired("valueName", @(x)ischar(x) || isstring(x));
            p.addRequired("value");
            p.addParameter("Units", "", @(x)ischar(x) || isstring(x));
            p.addParameter("Context", struct(), @(x)isstruct(x));
            p.parse(valueName, value, varargin{:});

            dims = size(value);
            isComplex = ~isreal(value);
            numeric = [];
            if isnumeric(value) || islogical(value)
                numeric = double(value(:));
            end
            finiteVals = numeric(isfinite(numeric));
            if isempty(finiteVals)
                minVal = NaN; maxVal = NaN; meanVal = NaN; rmsVal = NaN; normVal = NaN;
            else
                minVal = min(finiteVals);
                maxVal = max(finiteVals);
                meanVal = mean(finiteVals);
                rmsVal = sqrt(mean(finiteVals.^2));
                normVal = norm(finiteVals);
            end
            valueHash = "";
            try
                valueHash = sixgr.util.sha256Hex(value);
            catch
                valueHash = "";
            end
            ctx = p.Results.Context;
            ctx.value_name = string(p.Results.valueName);
            ctx.value_class = string(class(value));
            ctx.value_dimensions = string(mat2str(dims));
            ctx.value_complex = logical(isComplex);
            ctx.value_units = string(p.Results.Units);
            ctx.value_min = minVal;
            ctx.value_max = maxVal;
            ctx.value_mean = meanVal;
            ctx.value_rms = rmsVal;
            ctx.value_norm = normVal;
            ctx.value_nan_count = double(sum(isnan(numeric)));
            ctx.value_inf_count = double(sum(isinf(numeric)));
            ctx.value_zero_count = double(sum(numeric == 0));
            ctx.value_sha256 = string(valueHash);
            meta = struct( ...
                "Context", ctx, ...
                "ValueHash", string(valueHash), ...
                "Message", "value=" + string(p.Results.valueName) + ...
                    ",class=" + string(class(value)) + ...
                    ",dims=" + string(mat2str(dims)));
        end
    end
end

function context = localDefaultContext()
context = struct( ...
    "simulation_time_s", NaN, ...
    "frame", NaN, ...
    "slot", NaN, ...
    "symbol", NaN, ...
    "cell_id", "", ...
    "ue_id", "", ...
    "direction", "", ...
    "worker_id", localWorkerId(), ...
    "block_id", "", ...
    "call_id", "", ...
    "parent_call_id", "");
end

function out = localMergeContext(base, extra)
out = base;
if ~isstruct(extra)
    return;
end
names = fieldnames(extra);
for i = 1:numel(names)
    out.(names{i}) = extra.(names{i});
end
names = fieldnames(base);
for i = 1:numel(names)
    if ~isfield(out, names{i})
        out.(names{i}) = base.(names{i});
    end
end
end

function workerId = localWorkerId()
workerId = "client";
try
    task = getCurrentTask();
    if ~isempty(task)
        workerId = "worker_" + string(task.ID);
    end
catch
end
end

function [globalSeq, workerSeq, monotonicSeconds] = localNextSequence(runFolder, workerId)
persistent globalSeqByRun workerSeqByRun startTicByRun
if isempty(globalSeqByRun)
    globalSeqByRun = containers.Map("KeyType", "char", "ValueType", "double");
    workerSeqByRun = containers.Map("KeyType", "char", "ValueType", "double");
    startTicByRun = containers.Map("KeyType", "char", "ValueType", "any");
end
runKey = char(string(runFolder));
if ~isKey(globalSeqByRun, runKey)
    globalSeqByRun(runKey) = 0;
    startTicByRun(runKey) = tic;
end
globalSeqByRun(runKey) = globalSeqByRun(runKey) + 1;
globalSeq = globalSeqByRun(runKey);
workerKey = [runKey '|' char(string(workerId))];
if ~isKey(workerSeqByRun, workerKey)
    workerSeqByRun(workerKey) = 0;
end
workerSeqByRun(workerKey) = workerSeqByRun(workerKey) + 1;
workerSeq = workerSeqByRun(workerKey);
monotonicSeconds = toc(startTicByRun(runKey));
end

function pathStr = localJournalPath(runFolder, eventType)
eventType = upper(string(eventType));
if startsWith(eventType, "ARTIFACT")
    name = "artifact_events.jsonl";
elseif startsWith(eventType, "MESSAGE") || startsWith(eventType, "STATE_")
    name = "message_events.jsonl";
elseif startsWith(eventType, "VALUE")
    name = "value_events.jsonl";
elseif eventType == "WARNING" || eventType == "EXCEPTION"
    name = "warning_exception_events.jsonl";
else
    name = "runtime_events.jsonl";
end
pathStr = fullfile(runFolder, "runtime", "journal", name);
end

function localAppendDerivedCSV(runFolder, event)
[pathStr, headers] = localDerivedCSVSpec(runFolder, event);
if strlength(pathStr) > 0
    localAppendCSV(pathStr, headers, event);
end
end

function localPreflightDerivedCSV(runFolder, event)
[pathStr, headers] = localDerivedCSVSpec(runFolder, event);
if strlength(pathStr) > 0
    localValidateExistingCSVSchema(pathStr, headers);
end
end

function [pathStr, headers] = localDerivedCSVSpec(runFolder, event)
eventType = upper(string(event.event_type));
pathStr = "";
headers = strings(1, 0);
if startsWith(eventType, "ARTIFACT")
    pathStr = string(fullfile(runFolder, "runtime", "csv", "artifact_transactions.csv"));
    headers = [localIdentityHeaders(), "run_id","event_id","global_event_sequence","timestamp_utc","event_type", ...
        "artifact_id","relative_path","temporary_path","byte_count","sha256", ...
        "validation_status","commit_status","failure_reason","stage_name","block_id"];
elseif startsWith(eventType, "BLOCK")
    pathStr = string(fullfile(runFolder, "runtime", "csv", "block_call_trace.csv"));
    headers = [localIdentityHeaders(), "run_id","event_id","global_event_sequence","timestamp_utc","event_type", ...
        "block_id","call_id","parent_call_id","function_name","source_file","source_line", ...
        "status","reason_code","message","evidence_class"];
elseif eventType == "HEARTBEAT"
    pathStr = string(fullfile(runFolder, "runtime", "csv", "progress_heartbeat.csv"));
    headers = [localIdentityHeaders(), "run_id","event_id","global_event_sequence","timestamp_utc","monotonic_time_s", ...
        "event_type","stage_name","status","message","process_memory_bytes","open_figure_count", ...
        "pending_future_count","queued_event_count","last_completed_artifact"];
elseif startsWith(eventType, "STAGE")
    pathStr = string(fullfile(runFolder, "runtime", "csv", "stage_timing_events.csv"));
    headers = [localIdentityHeaders(), "run_id","event_id","global_event_sequence","timestamp_utc","monotonic_time_s", ...
        "event_type","stage_id","stage_name","status","reason_code","message", ...
        "process_memory_bytes","open_figure_count","pending_future_count"];
elseif eventType == "WARNING" || eventType == "EXCEPTION"
    pathStr = string(fullfile(runFolder, "runtime", "csv", "warning_exception_trace.csv"));
    headers = [localIdentityHeaders(), "run_id","event_id","global_event_sequence","timestamp_utc","event_type", ...
        "block_id","function_name","source_file","source_line","reason_code","message"];
elseif startsWith(eventType, "MESSAGE") || startsWith(eventType, "STATE_")
    pathStr = string(fullfile(runFolder, "runtime", "csv", "message_flow.csv"));
    headers = [localIdentityHeaders(), "run_id","event_id","global_event_sequence","timestamp_utc","event_type", ...
        "block_id","call_id","parent_call_id","status","reason_code","message"];
end
end

function headers = localIdentityHeaders()
headers = ["schema_name", "schema_version", "attempt_id", ...
    "execution_id", "finalization_id"];
end

function localAppendJSONL(pathStr, event)
localEnsureFolder(fileparts(char(pathStr)));
localValidateExistingJSONLSchema(pathStr, event.schema_name, event.schema_version);
fid = fopen(char(pathStr), "a");
if fid < 0
    error("sixgr:runtime:JournalOpenFailed", "Unable to open runtime journal: %s", char(pathStr));
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", char(jsonencode(event)));
end

function localAppendCSV(pathStr, headers, event)
headers = string(headers(:)).';
localEnsureFolder(fileparts(char(pathStr)));
newFile = localValidateExistingCSVSchema(pathStr, headers);
fid = fopen(char(pathStr), "a");
if fid < 0
    error("sixgr:runtime:CSVOpenFailed", "Unable to open runtime CSV: %s", char(pathStr));
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
if newFile
    fprintf(fid, "%s\n", char(strjoin(headers, ",")));
end
cells = strings(1, numel(headers));
for i = 1:numel(headers)
    cells(i) = localCSVCell(localEventValue(event, headers(i)));
end
fprintf(fid, "%s\n", char(strjoin(cells, ",")));
end

function newFile = localValidateExistingCSVSchema(pathStr, expectedHeaders)
newFile = exist(pathStr, "file") ~= 2;
if newFile
    return;
end
info = dir(pathStr);
if isempty(info) || info.bytes == 0
    newFile = true;
    return;
end
fid = fopen(char(pathStr), "r");
if fid < 0
    error("sixgr:runtime:CSVSchemaReadFailed", ...
        "Unable to inspect existing runtime CSV schema: %s", char(pathStr));
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
headerLine = fgetl(fid);
if ~ischar(headerLine)
    error("sixgr:runtime:CSVSchemaMissing", ...
        "Existing runtime CSV has no readable header: %s", char(pathStr));
end
actualHeaders = string(strsplit(headerLine, ","));
actualHeaders = arrayfun(@localNormalizeHeaderCell, actualHeaders);
if ~isequal(actualHeaders(:).', expectedHeaders(:).')
    error("sixgr:runtime:CSVSchemaMismatch", ...
        ['Refusing to append runtime CSV %s. Existing schema has %d fields ' ...
         '(%s); required schema has %d fields (%s).'], ...
        char(pathStr), numel(actualHeaders), strjoin(actualHeaders, "|"), ...
        numel(expectedHeaders), strjoin(expectedHeaders, "|"));
end
newFile = false;
end

function value = localNormalizeHeaderCell(value)
value = strtrim(string(value));
if startsWith(value, '"') && endsWith(value, '"') && strlength(value) >= 2
    value = extractBetween(value, 2, strlength(value) - 1);
    value = replace(value, '""', '"');
end
end

function localValidateExistingJSONLSchema(pathStr, expectedName, expectedVersion)
if exist(pathStr, "file") ~= 2
    return;
end
info = dir(pathStr);
if isempty(info) || info.bytes == 0
    return;
end
fid = fopen(char(pathStr), "r");
if fid < 0
    error("sixgr:runtime:JournalSchemaReadFailed", ...
        "Unable to inspect existing runtime journal schema: %s", char(pathStr));
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
firstLine = fgetl(fid);
try
    firstEvent = jsondecode(firstLine);
catch ME
    error("sixgr:runtime:JournalSchemaInvalid", ...
        "Existing runtime journal %s does not start with valid JSON: %s", ...
        char(pathStr), ME.message);
end
if ~isfield(firstEvent, "schema_name") || ~isfield(firstEvent, "schema_version") || ...
        string(firstEvent.schema_name) ~= string(expectedName) || ...
        string(firstEvent.schema_version) ~= string(expectedVersion)
    actualName = string(localEventValue(firstEvent, "schema_name"));
    actualVersion = string(localEventValue(firstEvent, "schema_version"));
    error("sixgr:runtime:JournalSchemaMismatch", ...
        "Refusing to mix journal schema %s/%s with required %s/%s in %s.", ...
        actualName, actualVersion, expectedName, expectedVersion, char(pathStr));
end
end

function value = localEventValue(event, fieldName)
fieldName = char(string(fieldName));
if isfield(event, fieldName)
    value = event.(fieldName);
else
    value = "";
end
end

function text = localCSVCell(value)
text = localString(value);
needsQuotes = any(contains(text, [",", """", string(newline), string(char(13))]));
if needsQuotes
    text = replace(text, """", """""");
    text = """" + text + """";
end
end

function text = localString(value)
if isstring(value)
    if isempty(value)
        text = "";
    else
        text = strjoin(value(:), "|");
    end
elseif ischar(value)
    text = string(value);
elseif isnumeric(value) || islogical(value)
    if isempty(value)
        text = "";
    elseif isscalar(value)
        if isnan(double(value))
            text = "";
        else
            text = string(value);
        end
    else
        text = string(mat2str(value));
    end
else
    try
        text = string(jsonencode(value));
    catch
        text = string(value);
    end
end
text(ismissing(text)) = "";
text = replace(text, newline, "\n");
end

function out = localFirstString(value, fallback)
out = string(value);
if strlength(strtrim(out)) == 0
    out = string(fallback);
end
end

function value = localNumericOrString(value)
if isnumeric(value)
    if isscalar(value)
        value = double(value);
    else
        value = string(mat2str(value));
    end
else
    value = string(value);
end
end

function bytes = localProcessMemoryBytes()
bytes = NaN;
try
    m = memory;
    if isfield(m, "MemUsedMATLAB")
        bytes = double(m.MemUsedMATLAB);
    end
catch
end
end

function n = localOpenFigureCount()
n = NaN;
try
    n = double(numel(findall(0, "Type", "figure")));
catch
end
end

function id = localUUID()
try
    id = string(char(java.util.UUID.randomUUID()));
catch
    id = "evt_" + string(round(posixtime(datetime("now")) * 1e6)) + "_" + string(randi(1e9));
end
end

function localEnsureFolder(folder)
folder = char(string(folder));
if ~isempty(folder) && ~isfolder(folder)
    mkdir(folder);
end
end

function localRemoveFolder(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end

function id = localExceptionId(ME)
id = "";
if isa(ME, "MException")
    id = string(ME.identifier);
end
end

function msg = localExceptionMessage(ME)
msg = "";
if isa(ME, "MException")
    msg = string(ME.message);
end
end
