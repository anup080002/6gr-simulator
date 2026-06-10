classdef TimeProfiler
    %TIMEPROFILER Scoped tic/toc and complexity coverage profiler for LLS.

    methods (Static)
        function configure(cfg)
            enabled = logical(sixgr.util.structGet(cfg, "perf.timeProfilingEnabled", ...
                sixgr.util.structGet(cfg, "run.timeProfilingEnabled", false)));
            granularity = string(sixgr.util.structGet(cfg, "perf.timeProfilingGranularity", "function"));
            required = sixgr.util.structGet(cfg, "perf.requiredFunctionStages", strings(0, 1));
            if isempty(required)
                required = sixgr.perf.TimeProfiler.defaultRequiredStages();
            end
            state = sixgr.perf.TimeProfiler.defaultState();
            state.Enabled = enabled;
            state.Granularity = char(granularity);
            state.RequiredStages = string(required(:));
            state.ConfiguredUTC = sixgr.util.utcNowISO8601();
            sixgr.perf.TimeProfiler.state("set", state);
        end

        function reset()
            state = sixgr.perf.TimeProfiler.state("get");
            state.Records = sixgr.perf.TimeProfiler.emptyRecords();
            state.ConfiguredUTC = sixgr.util.utcNowISO8601();
            sixgr.perf.TimeProfiler.state("set", state);
        end

        function cleanup = scope(functionName, varargin)
            p = inputParser;
            p.addRequired("functionName", @(x)ischar(x) || isstring(x));
            p.addParameter("Stage", "", @(x)ischar(x) || isstring(x));
            p.addParameter("Metadata", struct(), @(x)isstruct(x));
            p.addParameter("Status", "executed", @(x)ischar(x) || isstring(x));
            p.addParameter("Reason", "", @(x)ischar(x) || isstring(x));
            p.parse(functionName, varargin{:});

            state = sixgr.perf.TimeProfiler.state("get");
            if ~logical(state.Enabled)
                cleanup = onCleanup(@()[]);
                return;
            end
            meta = p.Results.Metadata;
            [flops, bytes, note] = sixgr.perf.ComplexityAnalyzer.estimate(functionName, meta);
            token = struct( ...
                "FunctionName", string(functionName), ...
                "Stage", string(p.Results.Stage), ...
                "Status", string(p.Results.Status), ...
                "Reason", string(p.Results.Reason), ...
                "EstimateFLOPs", double(flops), ...
                "EstimateBytes", double(bytes), ...
                "EstimateNote", string(note), ...
                "Metadata", meta, ...
                "StartTic", tic);
            cleanup = onCleanup(@()sixgr.perf.TimeProfiler.finish(token));
        end

        function finish(token)
            if ~isstruct(token)
                return;
            end
            elapsed = toc(token.StartTic);
            sixgr.perf.TimeProfiler.record(token.FunctionName, token.Stage, ...
                token.Status, token.Reason, elapsed, token.EstimateFLOPs, ...
                token.EstimateBytes, token.EstimateNote, token.Metadata);
        end

        function markSkipped(functionName, stage, reason, varargin)
            sixgr.perf.TimeProfiler.mark(functionName, stage, "skipped", reason, varargin{:});
        end

        function markBypassed(functionName, stage, reason, varargin)
            sixgr.perf.TimeProfiler.mark(functionName, stage, "bypassed", reason, varargin{:});
        end

        function markMissing(functionName, stage, reason, varargin)
            sixgr.perf.TimeProfiler.mark(functionName, stage, "missing_required", reason, varargin{:});
        end

        function mark(functionName, stage, status, reason, varargin)
            p = inputParser;
            p.addParameter("Metadata", struct(), @(x)isstruct(x));
            p.parse(varargin{:});
            state = sixgr.perf.TimeProfiler.state("get");
            if ~logical(state.Enabled)
                return;
            end
            meta = p.Results.Metadata;
            [flops, bytes, note] = sixgr.perf.ComplexityAnalyzer.estimate(functionName, meta);
            sixgr.perf.TimeProfiler.record(functionName, stage, status, reason, 0, flops, bytes, note, meta);
        end

        function record(functionName, stage, status, reason, elapsed_s, flops, bytes, note, meta)
            if nargin < 9 || ~isstruct(meta)
                meta = struct();
            end
            state = sixgr.perf.TimeProfiler.state("get");
            if ~logical(state.Enabled)
                return;
            end
            row = struct( ...
                "FunctionName", string(functionName), ...
                "Stage", string(stage), ...
                "Status", string(status), ...
                "Reason", string(reason), ...
                "Elapsed_s", double(elapsed_s), ...
                "EstimatedFLOPs", double(flops), ...
                "EstimatedBytes", double(bytes), ...
                "EstimateNote", string(note), ...
                "CallUTC", string(sixgr.util.utcNowISO8601()), ...
                "MetadataJSON", string(sixgr.perf.TimeProfiler.encodeMeta(meta)));
            state.Records(end+1, 1) = row;
            sixgr.perf.TimeProfiler.state("set", state);
        end

        function [callT, summaryT, coverageT] = snapshot()
            state = sixgr.perf.TimeProfiler.state("get");
            callT = struct2table(state.Records);
            if isempty(callT)
                callT = sixgr.perf.TimeProfiler.emptyCallTable();
            end
            summaryT = sixgr.perf.TimeProfiler.summaryTable(callT, state);
            coverageT = sixgr.perf.TimeProfiler.coverageTable(callT, state);
        end

        function out = export(runFolder, cfg)
            if nargin < 2
                cfg = struct();
            end
            out = sixgr.perf.exportTimeProfile(runFolder, cfg);
        end

        function required = defaultRequiredStages()
            required = [
                "sixgr.link.runDLPDSCHThroughput"
                "sixgr.link.runULPUSCHThroughput"
                "sixgr.phy.dl.PDSCH_Rx"
                "sixgr.phy.ul.PUSCH_Rx"
                "sixgr.phy.rx.mimoDetect"
                "sixgr.phy.rx.computePostEqSINR"
                "sixgr.link.applyWaveformImpairments"
                "sixgr.rach.PRACHDetector"
                "sixgr.l2.mac.SchedulerPF.schedule"
                ];
        end

        function stateOut = defaultState()
            stateOut = struct( ...
                "Enabled", false, ...
                "Granularity", "function", ...
                "ConfiguredUTC", "", ...
                "RequiredStages", sixgr.perf.TimeProfiler.defaultRequiredStages(), ...
                "Records", sixgr.perf.TimeProfiler.emptyRecords());
        end
    end

    methods (Static, Access = private)
        function out = state(action, value)
            persistent stateValue
            if isempty(stateValue)
                stateValue = sixgr.perf.TimeProfiler.defaultState();
            end
            switch lower(string(action))
                case "get"
                    out = stateValue;
                case "set"
                    stateValue = value;
                    out = stateValue;
                otherwise
                    out = stateValue;
            end
        end

        function rows = emptyRecords()
            rows = repmat(struct( ...
                "FunctionName", "", ...
                "Stage", "", ...
                "Status", "", ...
                "Reason", "", ...
                "Elapsed_s", NaN, ...
                "EstimatedFLOPs", NaN, ...
                "EstimatedBytes", NaN, ...
                "EstimateNote", "", ...
                "CallUTC", "", ...
                "MetadataJSON", ""), 0, 1);
        end

        function T = emptyCallTable()
            T = table('Size', [0 10], ...
                'VariableTypes', {'string','string','string','string','double','double','double','string','string','string'}, ...
                'VariableNames', {'FunctionName','Stage','Status','Reason','Elapsed_s','EstimatedFLOPs','EstimatedBytes','EstimateNote','CallUTC','MetadataJSON'});
        end

        function T = summaryTable(callT, state)
            executed = callT;
            if ~isempty(executed)
                executed = executed(strcmpi(string(executed.Status), "executed"), :);
            end
            totalCalls = height(callT);
            executedCalls = height(executed);
            totalElapsed = 0;
            totalFlops = NaN;
            totalBytes = NaN;
            if executedCalls > 0
                totalElapsed = sum(double(executed.Elapsed_s), "omitnan");
                totalFlops = sum(double(executed.EstimatedFLOPs), "omitnan");
                totalBytes = sum(double(executed.EstimatedBytes), "omitnan");
            end
            coverageT = sixgr.perf.TimeProfiler.coverageTable(callT, state);
            missingCount = sum(strcmpi(string(coverageT.CoverageStatus), "missing_required"));
            T = table( ...
                logical(state.Enabled), ...
                string(state.Granularity), ...
                totalCalls, ...
                executedCalls, ...
                totalElapsed, ...
                totalFlops, ...
                totalBytes, ...
                height(coverageT), ...
                missingCount, ...
                string(state.ConfiguredUTC), ...
                string(sixgr.util.utcNowISO8601()), ...
                'VariableNames', {'Enabled','Granularity','TotalCallRows','ExecutedCallRows','TotalElapsed_s','EstimatedTotalFLOPs','EstimatedTotalBytes','RequiredFunctionCount','MissingRequiredFunctionCount','ConfiguredUTC','ExportedUTC'});
        end

        function T = coverageTable(callT, state)
            required = string(state.RequiredStages(:));
            rows = repmat(struct( ...
                "FunctionName", "", ...
                "CoverageStatus", "", ...
                "ExecutedCallCount", NaN, ...
                "SkippedCallCount", NaN, ...
                "BypassedCallCount", NaN, ...
                "MissingReason", ""), 0, 1);
            for i = 1:numel(required)
                name = required(i);
                mask = strcmpi(string(callT.FunctionName), name);
                status = string(callT.Status(mask));
                executedCount = sum(strcmpi(status, "executed"));
                skippedCount = sum(strcmpi(status, "skipped"));
                bypassedCount = sum(strcmpi(status, "bypassed"));
                if executedCount > 0
                    coverageStatus = "executed";
                    reason = "";
                elseif skippedCount > 0
                    coverageStatus = "skipped";
                    reason = localFirstString(callT.Reason(mask));
                elseif bypassedCount > 0
                    coverageStatus = "bypassed";
                    reason = localFirstString(callT.Reason(mask));
                else
                    coverageStatus = "missing_required";
                    reason = "no_scope_or_explicit_skip_recorded_for_required_stage";
                end
                rows(end+1, 1) = struct( ... %#ok<AGROW>
                    "FunctionName", name, ...
                    "CoverageStatus", coverageStatus, ...
                    "ExecutedCallCount", double(executedCount), ...
                    "SkippedCallCount", double(skippedCount), ...
                    "BypassedCallCount", double(bypassedCount), ...
                    "MissingReason", string(reason));
            end
            T = struct2table(rows);
        end

        function txt = encodeMeta(meta)
            try
                txt = jsonencode(meta);
            catch
                txt = "{}";
            end
        end
    end
end

function out = localFirstString(values)
values = string(values);
values = values(strlength(strtrim(values)) > 0);
if isempty(values)
    out = "";
else
    out = values(1);
end
end
