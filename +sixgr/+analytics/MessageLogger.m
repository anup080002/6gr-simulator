classdef MessageLogger < handle
    %MESSAGELOGGER Optional slot-coupled message trace recorder.
    %
    % This logger records live message exchanges only when enabled. Post-run
    % analysis may derive message timelines from existing artifacts, but those
    % derived rows are not equivalent to this live trace.

    properties (Access = private)
        RunDir string = ""
        Enabled logical = false
        Messages struct = struct.empty(0, 1)
        MsgIndex double = 0
    end

    properties (Constant)
        MSG_DCI_1_0 = "DCI_1_0_PDSCH_Grant"
        MSG_DCI_0_0 = "DCI_0_0_PUSCH_Grant"
        MSG_DCI_1_1 = "DCI_1_1_PDSCH_Grant_MU"
        MSG_RAR_MSG2 = "RAR_MSG2"
        MSG_PRACH_PREAMBLE = "PRACH_MSG1"
        MSG_MSG3_PUSCH = "MSG3_PUSCH"
        MSG_MSG4_CONTENTION = "MSG4_ConRes"
        MSG_PUCCH_ACK = "PUCCH_ACK_NACK"
        MSG_PUCCH_SR = "PUCCH_SR"
        MSG_PUCCH_CSI = "PUCCH_CSI_Part1"
        MSG_SRS = "SRS_Channel_Est"
        MSG_TRS_TRACK = "TRS_Tracking"
        MSG_SSB_BEAM_SWEEP = "SSB_P1_Beam_Sweep"
        MSG_PDSCH_TB = "PDSCH_TB"
        MSG_PUSCH_TB = "PUSCH_TB"
        MSG_HARQ_NACK_RETX = "HARQ_NACK_Retransmit"
        MSG_HARQ_ACK_DONE = "HARQ_ACK_Final"
        MSG_SCHED_GRANT = "Scheduler_Grant_Decision"
        MSG_CQI_REPORT = "CQI_PMI_RI_Report"
        MSG_MCS_SELECTION = "MCS_Selection"
        MSG_OLLA_UPDATE = "OLLA_Update"
        MSG_BEAM_SWITCH = "Beam_Switch"
    end

    methods (Static)
        function obj = getInstance()
            persistent inst
            if isempty(inst) || ~isvalid(inst)
                inst = sixgr.analytics.MessageLogger();
            end
            obj = inst;
        end
    end

    methods
        function enable(obj, runDir)
            obj.RunDir = string(runDir);
            obj.Enabled = true;
            obj.MsgIndex = 0;
            obj.Messages = struct( ...
                "EventIndex", {}, "Frame", {}, "Slot", {}, "Timestamp_ms", {}, ...
                "SourceEntity", {}, "DestinationEntity", {}, "MessageType", {}, ...
                "UEIndex", {}, "RNTI", {}, "Direction", {}, "PayloadBits", {}, ...
                "PayloadRef", {}, "Status", {}, "ProducerFunction", {}, "ConsumerFunction", {}, ...
                "EvidenceClass", {}, "Notes", {});
        end

        function disable(obj)
            obj.Enabled = false;
        end

        function log(obj, sourceEntity, destinationEntity, messageType, meta)
            if ~obj.Enabled
                return;
            end
            if nargin < 5 || ~isstruct(meta)
                meta = struct();
            end
            obj.MsgIndex = obj.MsgIndex + 1;
            r = struct();
            r.EventIndex = obj.MsgIndex;
            r.Frame = localMeta(meta, "Frame", NaN);
            r.Slot = localMeta(meta, "Slot", NaN);
            r.Timestamp_ms = localMeta(meta, "Timestamp_ms", NaN);
            r.SourceEntity = string(sourceEntity);
            r.DestinationEntity = string(destinationEntity);
            r.MessageType = string(messageType);
            r.UEIndex = localMeta(meta, "UEIndex", NaN);
            r.RNTI = localMeta(meta, "RNTI", NaN);
            r.Direction = string(localMeta(meta, "Direction", ""));
            r.PayloadBits = localMeta(meta, "PayloadBits", NaN);
            r.PayloadRef = string(localMeta(meta, "PayloadRef", ""));
            r.Status = string(localMeta(meta, "Status", "observed"));
            r.ProducerFunction = string(localMeta(meta, "ProducerFunction", ""));
            r.ConsumerFunction = string(localMeta(meta, "ConsumerFunction", ""));
            r.EvidenceClass = "DIRECT_RUNTIME_EVIDENCE";
            r.Notes = string(localMeta(meta, "Notes", ""));
            obj.Messages(end+1, 1) = r;
        end

        function T = table(obj)
            if isempty(obj.Messages)
                T = localEmptyMessageTable();
            else
                T = struct2table(obj.Messages);
            end
        end

        function exportCSV(obj)
            if strlength(obj.RunDir) == 0
                return;
            end
            layout = sixgr.report.resultLayout(obj.RunDir);
            sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "message_sequence_trace.csv"), obj.table());
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

function T = localEmptyMessageTable()
T = table( ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), strings(0,1), strings(0,1), strings(0,1), ...
    zeros(0,1), zeros(0,1), strings(0,1), zeros(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
    'VariableNames', {'EventIndex','Frame','Slot','Timestamp_ms','SourceEntity','DestinationEntity','MessageType', ...
    'UEIndex','RNTI','Direction','PayloadBits','PayloadRef','Status','ProducerFunction','ConsumerFunction','EvidenceClass','Notes'});
end
