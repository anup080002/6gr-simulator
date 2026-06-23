classdef CallFlowInstrumentor < handle
    %CALLFLOWINSTRUMENTOR Optional runtime call-flow recorder.
    %
    % The recorder is inert unless enable(runDir) is called. It is intended
    % for future live runs; post-run dashboards can fall back to the MATLAB
    % profiler edge table when this trace is absent.

    properties (Access = private)
        RunDir string = ""
        Enabled logical = false
        CallStack double = zeros(0, 1)
        Records struct = struct.empty(0, 1)
        T0 uint64 = 0
    end

    methods (Static)
        function obj = getInstance()
            persistent inst
            if isempty(inst) || ~isvalid(inst)
                inst = sixgr.analytics.CallFlowInstrumentor();
            end
            obj = inst;
        end

        function n = estimateBytes(x)
            try
                info = whos("x");
                n = double(info.bytes);
            catch
                n = NaN;
            end
        end
    end

    methods
        function enable(obj, runDir)
            obj.RunDir = string(runDir);
            obj.Enabled = true;
            obj.CallStack = zeros(0, 1);
            obj.Records = struct( ...
                "FunctionName", {}, "FullPath", {}, "Stage", {}, ...
                "Depth", {}, "CallIndex", {}, "ParentIndex", {}, ...
                "EntryTime_s", {}, "ExitTime_s", {}, "ElapsedTime_s", {}, ...
                "EstimatedFLOPs", {}, "InputBytes", {}, "OutputBytes", {}, ...
                "UEIndex", {}, "Direction", {}, "Frame", {}, "Slot", {}, ...
                "ReturnStatus", {}, "ErrorMsg", {});
            obj.T0 = tic;
        end

        function disable(obj)
            obj.Enabled = false;
        end

        function idx = enter(obj, funcName, fullPath, stage, meta)
            if ~obj.Enabled
                idx = -1;
                return;
            end
            if nargin < 5 || ~isstruct(meta)
                meta = struct();
            end
            idx = numel(obj.Records) + 1;
            parentIdx = 0;
            if ~isempty(obj.CallStack)
                parentIdx = obj.CallStack(end);
            end
            obj.CallStack(end+1, 1) = idx;

            r = struct();
            r.FunctionName = string(funcName);
            r.FullPath = string(fullPath);
            r.Stage = string(stage);
            r.Depth = numel(obj.CallStack);
            r.CallIndex = idx;
            r.ParentIndex = parentIdx;
            r.EntryTime_s = toc(obj.T0);
            r.ExitTime_s = NaN;
            r.ElapsedTime_s = NaN;
            r.EstimatedFLOPs = localMeta(meta, "FLOPs", NaN);
            r.InputBytes = localMeta(meta, "InputBytes", NaN);
            r.OutputBytes = NaN;
            r.UEIndex = localMeta(meta, "UEIndex", NaN);
            r.Direction = string(localMeta(meta, "Direction", ""));
            r.Frame = localMeta(meta, "Frame", NaN);
            r.Slot = localMeta(meta, "Slot", NaN);
            r.ReturnStatus = "running";
            r.ErrorMsg = "";
            obj.Records(idx, 1) = r;
        end

        function exit(obj, idx, outputBytes, status, errMsg)
            if ~obj.Enabled || idx < 1 || idx > numel(obj.Records)
                return;
            end
            if nargin < 4 || strlength(string(status)) == 0
                status = "OK";
            end
            if nargin < 5
                errMsg = "";
            end
            t = toc(obj.T0);
            obj.Records(idx).ExitTime_s = t;
            obj.Records(idx).ElapsedTime_s = t - obj.Records(idx).EntryTime_s;
            obj.Records(idx).OutputBytes = outputBytes;
            obj.Records(idx).ReturnStatus = string(status);
            obj.Records(idx).ErrorMsg = string(errMsg);
            if ~isempty(obj.CallStack)
                obj.CallStack(end) = [];
            end
        end

        function T = table(obj)
            if isempty(obj.Records)
                T = localEmptyCallFlowTable();
            else
                T = struct2table(obj.Records);
            end
        end

        function exportCSV(obj)
            if strlength(obj.RunDir) == 0
                return;
            end
            layout = sixgr.report.resultLayout(obj.RunDir);
            sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "call_flow_trace.csv"), obj.table());
        end
    end
end

function value = localMeta(meta, fieldName, defaultValue)
if isfield(meta, fieldName)
    value = meta.(fieldName);
else
    value = defaultValue;
end
end

function T = localEmptyCallFlowTable()
T = table( ...
    strings(0,1), strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), strings(0,1), zeros(0,1), zeros(0,1), strings(0,1), strings(0,1), ...
    'VariableNames', {'FunctionName','FullPath','Stage','Depth','CallIndex','ParentIndex', ...
    'EntryTime_s','ExitTime_s','ElapsedTime_s','EstimatedFLOPs','InputBytes','OutputBytes', ...
    'UEIndex','Direction','Frame','Slot','ReturnStatus','ErrorMsg'});
end
