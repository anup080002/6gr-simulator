classdef RunMonitor < handle
    %RUNMONITOR Lightweight optional runtime activity recorder.
    %   The monitor is audit-only. It records timing, call scopes and errors
    %   without feeding values back into PHY algorithms or result KPIs.

    properties
        RunDir string
        ScenarioPath string
        RunID string
        StartWall string
        StartTic
        EventIndex double = 0
        Stack double = []
        Events struct
        Exceptions struct
        Closed logical = false
    end

    methods
        function obj = RunMonitor(runDir, scenarioPath)
            if nargin < 2
                scenarioPath = "";
            end
            obj.RunDir = string(runDir);
            obj.ScenarioPath = string(scenarioPath);
            obj.RunID = "profiled_" + string(char(java.util.UUID.randomUUID()));
            obj.StartWall = string(sixgr.util.utcNowISO8601());
            obj.StartTic = tic;
            obj.Events = sixgr.monitor.RunMonitor.emptyEventRows();
            obj.Exceptions = sixgr.monitor.RunMonitor.emptyExceptionRows();
            sixgr.util.ensureFolder(char(obj.RunDir));
            obj.record("START_PHASE", "function_name", "sixgr.monitor.RunMonitor", ...
                "phase", "monitor_start", "status", "started");
        end

        function scope = scope(obj, varargin)
            scope = sixgr.monitor.TraceScope(obj, varargin{:});
        end

        function meta = parseMetaPublic(obj, varargin)
            meta = obj.parseMeta(varargin{:});
        end

        function eventId = enter(obj, meta)
            if nargin < 2 || ~isstruct(meta)
                meta = struct();
            end
            eventId = obj.record("ENTER_FUNCTION", meta);
            obj.Stack(end+1) = eventId;
        end

        function eventId = exit(obj, enterId, elapsedWall_s, elapsedCpu_s, meta)
            if nargin < 5 || ~isstruct(meta)
                meta = struct();
            end
            meta.related_event_index = enterId;
            meta.elapsed_wall_s = elapsedWall_s;
            meta.elapsed_cpu_s = elapsedCpu_s;
            if ~isfield(meta, "status") || strlength(strtrim(string(meta.status))) == 0
                meta.status = "completed";
            end
            eventId = obj.record("EXIT_FUNCTION", meta);
            if ~isempty(obj.Stack)
                idx = find(obj.Stack == enterId, 1, "last");
                if ~isempty(idx)
                    obj.Stack(idx:end) = [];
                else
                    obj.Stack(end) = [];
                end
            end
        end

        function eventId = record(obj, eventType, varargin)
            meta = obj.parseMeta(varargin{:});
            row = sixgr.monitor.RunMonitor.defaultEventRow();
            obj.EventIndex = obj.EventIndex + 1;
            row.run_id = obj.RunID;
            row.timestamp_wall = string(sixgr.util.utcNowISO8601());
            row.timestamp_monotonic = toc(obj.StartTic);
            row.event_index = obj.EventIndex;
            row.parent_event_index = obj.currentParent();
            row.call_depth = numel(obj.Stack);
            row.event_type = string(eventType);
            row = obj.applyCaller(row);
            row = obj.applyMeta(row, meta);
            obj.Events(end+1, 1) = row;
            eventId = row.event_index;
        end

        function recordException(obj, ME, varargin)
            if nargin < 2 || ~isa(ME, "MException")
                return;
            end
            meta = obj.parseMeta(varargin{:});
            if ~isfield(meta, "function_name") || strlength(strtrim(string(meta.function_name))) == 0
                if ~isempty(ME.stack)
                    meta.function_name = string(ME.stack(1).name);
                    meta.file_path = string(ME.stack(1).file);
                    meta.line_number_if_available = double(ME.stack(1).line);
                end
            end
            meta.status = "error";
            meta.error_message = string(ME.message);
            eventId = obj.record("ERROR", meta);
            ex = sixgr.monitor.RunMonitor.defaultExceptionRow();
            ex.run_id = obj.RunID;
            ex.timestamp_wall = string(sixgr.util.utcNowISO8601());
            ex.event_index = eventId;
            ex.identifier = string(ME.identifier);
            ex.message = string(ME.message);
            ex.stack = string(getReport(ME, "extended", "hyperlinks", "off"));
            ex.scenario_path = obj.ScenarioPath;
            ex.last_trace_events_json = string(obj.lastEventsJSON(200));
            obj.Exceptions(end+1, 1) = ex;
        end

        function [eventT, traceT, exceptionT] = snapshot(obj)
            eventT = struct2table(obj.Events);
            if isempty(eventT)
                eventT = sixgr.monitor.RunMonitor.emptyEventTable();
            end
            traceT = obj.buildCallTrace(eventT);
            exceptionT = struct2table(obj.Exceptions);
            if isempty(exceptionT)
                exceptionT = sixgr.monitor.RunMonitor.emptyExceptionTable();
            end
        end

        function close(obj)
            if obj.Closed
                return;
            end
            obj.record("END_PHASE", "function_name", "sixgr.monitor.RunMonitor", ...
                "phase", "monitor_close", "status", "completed");
            [eventT, traceT, exceptionT] = obj.snapshot();
            sixgr.util.csvWriteTable(fullfile(obj.RunDir, "activity_timeline.csv"), eventT);
            sixgr.util.csvWriteTable(fullfile(obj.RunDir, "function_call_trace.csv"), traceT);
            sixgr.util.csvWriteTable(fullfile(obj.RunDir, "runtime_exception_log.csv"), exceptionT);
            obj.Closed = true;
        end

        function delete(obj)
            try
                obj.close();
            catch
            end
        end
    end

    methods (Access = private)
        function parent = currentParent(obj)
            parent = NaN;
            if ~isempty(obj.Stack)
                parent = obj.Stack(end);
            end
        end

        function meta = parseMeta(~, varargin)
            if nargin == 2 && isstruct(varargin{1})
                meta = varargin{1};
                return;
            end
            meta = struct();
            if mod(numel(varargin), 2) ~= 0
                return;
            end
            for k = 1:2:numel(varargin)
                key = sixgr.monitor.RunMonitor.canonicalField(varargin{k});
                if strlength(key) > 0
                    meta.(char(key)) = varargin{k+1};
                end
            end
        end

        function row = applyMeta(~, row, meta)
            names = string(fieldnames(meta));
            for i = 1:numel(names)
                key = sixgr.monitor.RunMonitor.canonicalField(names(i));
                if isfield(row, char(key))
                    value = meta.(char(names(i)));
                    row.(char(key)) = sixgr.monitor.RunMonitor.coerceLike(row.(char(key)), value);
                end
            end
        end

        function row = applyCaller(~, row)
            st = dbstack("-completenames");
            if numel(st) >= 3
                row.caller_function = string(st(3).name);
            end
            if numel(st) >= 4 && strlength(row.function_name) == 0
                row.function_name = string(st(4).name);
                row.file_path = string(st(4).file);
                row.line_number_if_available = double(st(4).line);
            end
        end

        function json = lastEventsJSON(obj, n)
            if nargin < 2
                n = 50;
            end
            rows = obj.Events;
            if numel(rows) > n
                rows = rows(end-n+1:end);
            end
            try
                json = jsonencode(rows);
            catch
                json = "[]";
            end
        end

        function T = buildCallTrace(~, eventT)
            T = table('Size', [0 15], ...
                'VariableTypes', {'double','double','double','string','string','string','string','double','double','string','string','double','double','double','double'}, ...
                'VariableNames', {'event_id','parent_event_id','depth','function','caller','start_time','end_time','elapsed_wall_s','elapsed_cpu_s','channel','phase','frame','slot','cell','ue'});
            if ~(istable(eventT) && height(eventT) > 0)
                return;
            end
            enterMask = string(eventT.event_type) == "ENTER_FUNCTION";
            exitMask = string(eventT.event_type) == "EXIT_FUNCTION";
            enters = eventT(enterMask, :);
            exits = eventT(exitMask, :);
            for i = 1:height(enters)
                enterId = double(enters.event_index(i));
                match = exits(double(exits.related_event_index) == enterId, :);
                endTime = "";
                elapsed = NaN;
                cpu = NaN;
                if height(match) > 0
                    endTime = string(match.timestamp_wall(1));
                    elapsed = double(match.elapsed_wall_s(1));
                    cpu = double(match.elapsed_cpu_s(1));
                end
                T(end+1, :) = {enterId, double(enters.parent_event_index(i)), double(enters.call_depth(i)), ...
                    string(enters.function_name(i)), string(enters.caller_function(i)), ...
                    string(enters.timestamp_wall(i)), endTime, elapsed, cpu, string(enters.channel(i)), ...
                    string(enters.phase(i)), double(enters.frame(i)), double(enters.slot(i)), ...
                    double(enters.cell_id(i)), double(enters.ue_id(i))}; %#ok<AGROW>
            end
        end
    end

    methods (Static)
        function row = defaultEventRow()
            row = struct( ...
                "run_id", "", "timestamp_wall", "", "timestamp_monotonic", NaN, ...
                "event_index", NaN, "parent_event_index", NaN, "related_event_index", NaN, ...
                "call_depth", NaN, "event_type", "", "function_name", "", "file_path", "", ...
                "line_number_if_available", NaN, "caller_function", "", "phase", "", ...
                "channel", "", "direction", "", "frame", NaN, "slot", NaN, "symbol", NaN, ...
                "cell_id", NaN, "ue_id", NaN, "link_id", "", "harq_process_id", NaN, ...
                "tb_id", "", "rv", NaN, "mcs", NaN, "modulation", "", "q_m", NaN, ...
                "code_rate", NaN, "tbs_bits", NaN, "n_info_bits", NaN, "crc_bits", NaN, ...
                "cb_count", NaN, "cb_size", NaN, "ldpc_base_graph", "", "lifting_size", NaN, ...
                "n_re", NaN, "n_data_re", NaN, "n_dmrs_re", NaN, "n_prb", NaN, ...
                "n_symbols", NaN, "n_layers", NaN, "n_ports", NaN, "n_tx_elements", NaN, ...
                "n_rx_elements", NaN, "n_tx_rf_chains", NaN, "n_rx_rf_chains", NaN, ...
                "precoder_shape", "", "channel_matrix_shape", "", "tx_grid_shape", "", ...
                "rx_grid_shape", "", "waveform_shape", "", "noise_variance", NaN, ...
                "target_snr_db", NaN, "measured_snr_db", NaN, "signal_power", NaN, ...
                "noise_power", NaN, "interference_power", NaN, "post_eq_sinr_db", NaN, ...
                "cfo_injected_hz", NaN, "cfo_estimated_hz", NaN, "cfo_residual_hz", NaN, ...
                "timing_injected_samples", NaN, "timing_estimated_samples", NaN, ...
                "timing_residual_samples", NaN, "doppler_injected_hz", NaN, ...
                "doppler_estimated_hz", NaN, "doppler_residual_hz", NaN, ...
                "crc_applicable", NaN, "crc_pass", NaN, "bit_errors", NaN, ...
                "bits_compared", NaN, "symbol_errors", NaN, "symbols_compared", NaN, ...
                "status", "", "skip_reason", "", "bypass_reason", "", "error_message", "", ...
                "elapsed_wall_s", NaN, "elapsed_cpu_s", NaN, "peak_memory_if_available", NaN);
        end

        function rows = emptyEventRows()
            rows = repmat(sixgr.monitor.RunMonitor.defaultEventRow(), 0, 1);
        end

        function T = emptyEventTable()
            T = struct2table(sixgr.monitor.RunMonitor.emptyEventRows());
        end

        function row = defaultExceptionRow()
            row = struct("run_id", "", "timestamp_wall", "", "event_index", NaN, ...
                "identifier", "", "message", "", "stack", "", "scenario_path", "", ...
                "last_trace_events_json", "");
        end

        function rows = emptyExceptionRows()
            rows = repmat(sixgr.monitor.RunMonitor.defaultExceptionRow(), 0, 1);
        end

        function T = emptyExceptionTable()
            T = struct2table(sixgr.monitor.RunMonitor.emptyExceptionRows());
        end

        function key = canonicalField(key)
            key = lower(strtrim(string(key)));
            key = replace(key, "-", "_");
            switch key
                case "function"
                    key = "function_name";
                case "cell"
                    key = "cell_id";
                case "ue"
                    key = "ue_id";
                case "line"
                    key = "line_number_if_available";
                case "event_id"
                    key = "event_index";
                case "parent_event_id"
                    key = "parent_event_index";
                otherwise
                    key = regexprep(key, "[^a-z0-9_]", "_");
            end
        end

        function out = coerceLike(template, value)
            if isstring(template) || ischar(template)
                if isstring(value) || ischar(value) || iscategorical(value)
                    out = string(value);
                else
                    try
                        out = string(value);
                    catch
                        out = "";
                    end
                end
                if numel(out) ~= 1
                    out = strjoin(out(:), "|");
                end
            else
                if islogical(value)
                    out = double(value);
                elseif isnumeric(value)
                    value = double(value);
                    if isempty(value)
                        out = NaN;
                    else
                        out = value(1);
                    end
                else
                    out = str2double(string(value));
                    if ~isfinite(out)
                        out = NaN;
                    end
                end
            end
        end
    end
end
