classdef AlgorithmAuditLogger < handle
    %ALGORITHMAUDITLOGGER Optional live algorithm decision recorder.

    properties (Access = private)
        RunDir string = ""
        Enabled logical = false
        Records struct = struct.empty(0, 1)
        RecordIndex double = 0
    end

    methods (Static)
        function obj = getInstance()
            persistent inst
            if isempty(inst) || ~isvalid(inst)
                inst = sixgr.analytics.AlgorithmAuditLogger();
            end
            obj = inst;
        end
    end

    methods
        function enable(obj, runDir)
            obj.RunDir = string(runDir);
            obj.Enabled = true;
            obj.RecordIndex = 0;
            obj.Records = struct( ...
                "RecordIndex", {}, "Frame", {}, "Slot", {}, "UEIndex", {}, "RNTI", {}, ...
                "Direction", {}, "AlgorithmFamily", {}, "AlgorithmName", {}, "EquationId", {}, ...
                "InputArtifact", {}, "InputValues", {}, "OutputValues", {}, "Decision", {}, ...
                "ReferenceValue", {}, "Delta", {}, "Tolerance", {}, "PassFail", {}, ...
                "ProducerFunction", {}, "EvidenceClass", {}, "Notes", {});
        end

        function disable(obj)
            obj.Enabled = false;
        end

        function log(obj, algorithmFamily, algorithmName, meta)
            if ~obj.Enabled
                return;
            end
            if nargin < 4 || ~isstruct(meta)
                meta = struct();
            end
            obj.RecordIndex = obj.RecordIndex + 1;
            r = struct();
            r.RecordIndex = obj.RecordIndex;
            r.Frame = localMeta(meta, "Frame", NaN);
            r.Slot = localMeta(meta, "Slot", NaN);
            r.UEIndex = localMeta(meta, "UEIndex", NaN);
            r.RNTI = localMeta(meta, "RNTI", NaN);
            r.Direction = string(localMeta(meta, "Direction", ""));
            r.AlgorithmFamily = string(algorithmFamily);
            r.AlgorithmName = string(algorithmName);
            r.EquationId = string(localMeta(meta, "EquationId", ""));
            r.InputArtifact = string(localMeta(meta, "InputArtifact", ""));
            r.InputValues = string(localMeta(meta, "InputValues", ""));
            r.OutputValues = string(localMeta(meta, "OutputValues", ""));
            r.Decision = string(localMeta(meta, "Decision", ""));
            r.ReferenceValue = localMeta(meta, "ReferenceValue", NaN);
            r.Delta = localMeta(meta, "Delta", NaN);
            r.Tolerance = string(localMeta(meta, "Tolerance", ""));
            r.PassFail = string(localMeta(meta, "PassFail", ""));
            r.ProducerFunction = string(localMeta(meta, "ProducerFunction", ""));
            r.EvidenceClass = "DIRECT_RUNTIME_EVIDENCE";
            r.Notes = string(localMeta(meta, "Notes", ""));
            obj.Records(end+1, 1) = r;
        end

        function T = table(obj)
            if isempty(obj.Records)
                T = localEmptyAlgorithmTable();
            else
                T = struct2table(obj.Records);
            end
        end

        function exportCSV(obj)
            if strlength(obj.RunDir) == 0
                return;
            end
            layout = sixgr.report.resultLayout(obj.RunDir);
            sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "algorithm_audit_trace.csv"), obj.table());
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

function T = localEmptyAlgorithmTable()
T = table( ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), strings(0,1), ...
    strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
    strings(0,1), zeros(0,1), zeros(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
    'VariableNames', {'RecordIndex','Frame','Slot','UEIndex','RNTI','Direction','AlgorithmFamily','AlgorithmName', ...
    'EquationId','InputArtifact','InputValues','OutputValues','Decision','ReferenceValue','Delta','Tolerance','PassFail', ...
    'ProducerFunction','EvidenceClass','Notes'});
end
