classdef AccessFlowRecorder
%ACCESSFLOWRECORDER Runtime access-state transition ledger utilities.
% This class records observations only; it never changes eligibility or
% access state.

methods(Static)
    function T = emptyLedger()
        T = struct2table(repmat(sixgr.monitor.AccessFlowRecorder.emptyRow(), 0, 1));
    end

    function state = recordEvent(state, varargin)
        if ~isstruct(state)
            return;
        end
        p = inputParser;
        p.addParameter("UEIndex", NaN, @(x)isnumeric(x) && isscalar(x));
        p.addParameter("CellID", NaN, @(x)isnumeric(x) && isscalar(x));
        p.addParameter("OldState", "", @(x)ischar(x) || isstring(x));
        p.addParameter("NewState", "", @(x)ischar(x) || isstring(x));
        p.addParameter("TransitionReason", "", @(x)ischar(x) || isstring(x));
        p.addParameter("SourceFunction", "", @(x)ischar(x) || isstring(x));
        p.addParameter("SourceFile", "", @(x)ischar(x) || isstring(x));
        p.addParameter("Procedure", "", @(x)ischar(x) || isstring(x));
        p.addParameter("PhysicalChannel", "", @(x)ischar(x) || isstring(x));
        p.addParameter("RequiredPrecondition", "", @(x)ischar(x) || isstring(x));
        p.addParameter("PreconditionValue", "", @(x)ischar(x) || isstring(x) || isnumeric(x) || islogical(x));
        p.addParameter("TimerName", "", @(x)ischar(x) || isstring(x));
        p.addParameter("TimerValue", NaN, @(x)isnumeric(x) && isscalar(x));
        p.addParameter("RNTI", NaN, @(x)isnumeric(x) && isscalar(x));
        p.addParameter("TemporaryCRNTI", NaN, @(x)isnumeric(x) && isscalar(x));
        p.addParameter("SSBIndex", NaN, @(x)isnumeric(x) && isscalar(x));
        p.addParameter("PRACHOccasionID", NaN, @(x)isnumeric(x) && isscalar(x));
        p.addParameter("PRACHPreambleIndex", NaN, @(x)isnumeric(x) && isscalar(x));
        p.addParameter("PRACHRootSequence", NaN, @(x)isnumeric(x) && isscalar(x));
        p.addParameter("PRACHFormat", "", @(x)ischar(x) || isstring(x));
        p.addParameter("PRACHDetected", false, @(x)islogical(x) || isnumeric(x));
        p.addParameter("PRACHDetectionMetric", NaN, @(x)isnumeric(x) && isscalar(x));
        p.addParameter("TimingAdvanceSamples", NaN, @(x)isnumeric(x) && isscalar(x));
        p.addParameter("RARCreated", false, @(x)islogical(x) || isnumeric(x));
        p.addParameter("RARDecoded", false, @(x)islogical(x) || isnumeric(x));
        p.addParameter("Msg3GrantCreated", false, @(x)islogical(x) || isnumeric(x));
        p.addParameter("Msg3TxExecuted", false, @(x)islogical(x) || isnumeric(x));
        p.addParameter("Msg3CRCPass", false, @(x)islogical(x) || isnumeric(x));
        p.addParameter("Msg4Created", false, @(x)islogical(x) || isnumeric(x));
        p.addParameter("Msg4Decoded", false, @(x)islogical(x) || isnumeric(x));
        p.addParameter("ContentionResolutionPass", false, @(x)islogical(x) || isnumeric(x));
        p.addParameter("AccessSuccess", false, @(x)islogical(x) || isnumeric(x));
        p.addParameter("FailureReason", "", @(x)ischar(x) || isstring(x));
        p.addParameter("OldStateOriginal", "", @(x)ischar(x) || isstring(x));
        p.addParameter("NewStateOriginal", "", @(x)ischar(x) || isstring(x));
        p.parse(varargin{:});
        opt = p.Results;

        if ~(isfield(state, "AccessTransitionLedgerTable") && istable(state.AccessTransitionLedgerTable))
            state.AccessTransitionLedgerTable = sixgr.monitor.AccessFlowRecorder.emptyLedger();
        end
        row = sixgr.monitor.AccessFlowRecorder.emptyRow();
        row.event_index = double(height(state.AccessTransitionLedgerTable) + 1);
        row.wall_time = string(sixgr.util.utcNowISO8601());
        row.frame = double(sixgr.util.structGet(state, "CurrentFrame", NaN));
        row.slot = double(sixgr.util.structGet(state, "CurrentSlot", NaN));
        row.symbol = NaN;
        row.cell_id = double(opt.CellID);
        row.ue_id = double(opt.UEIndex);
        row.old_state = string(opt.OldState);
        row.new_state = string(opt.NewState);
        row.transition_reason = string(opt.TransitionReason);
        row.source_function = string(opt.SourceFunction);
        row.source_file = string(opt.SourceFile);
        row.procedure = string(opt.Procedure);
        row.physical_channel = string(opt.PhysicalChannel);
        row.required_precondition = string(opt.RequiredPrecondition);
        row.precondition_value = sixgr.monitor.AccessFlowRecorder.toString(opt.PreconditionValue);
        row.timer_name = string(opt.TimerName);
        row.timer_value = double(opt.TimerValue);
        row.rnti = double(opt.RNTI);
        row.temporary_crnti = double(opt.TemporaryCRNTI);
        row.ssb_index = double(opt.SSBIndex);
        row.prach_occasion_id = double(opt.PRACHOccasionID);
        row.prach_preamble_index = double(opt.PRACHPreambleIndex);
        row.prach_root_sequence = double(opt.PRACHRootSequence);
        row.prach_format = string(opt.PRACHFormat);
        row.prach_detected = logical(opt.PRACHDetected);
        row.prach_detection_metric = double(opt.PRACHDetectionMetric);
        row.timing_advance_samples = double(opt.TimingAdvanceSamples);
        row.rar_created = logical(opt.RARCreated);
        row.rar_decoded = logical(opt.RARDecoded);
        row.msg3_grant_created = logical(opt.Msg3GrantCreated);
        row.msg3_tx_executed = logical(opt.Msg3TxExecuted);
        row.msg3_crc_pass = logical(opt.Msg3CRCPass);
        row.msg4_created = logical(opt.Msg4Created);
        row.msg4_decoded = logical(opt.Msg4Decoded);
        row.contention_resolution_pass = logical(opt.ContentionResolutionPass);
        row.access_success = logical(opt.AccessSuccess);
        row.failure_reason = string(opt.FailureReason);
        row.old_state_original = string(opt.OldStateOriginal);
        row.new_state_original = string(opt.NewStateOriginal);
        state.AccessTransitionLedgerTable = sixgr.monitor.AccessFlowRecorder.appendCompatTable( ...
            state.AccessTransitionLedgerTable, struct2table(row, "AsArray", true));
    end

    function writeTables(runFolder, state)
        if nargin < 2 || ~isstruct(state)
            return;
        end
        ledger = sixgr.util.structGet(state, "AccessTransitionLedgerTable", sixgr.monitor.AccessFlowRecorder.emptyLedger());
        if ~istable(ledger)
            ledger = sixgr.monitor.AccessFlowRecorder.emptyLedger();
        end
        timeline = sixgr.monitor.AccessFlowRecorder.buildTimeline(ledger);
        layout = sixgr.report.resultLayout(runFolder);
        sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, "access_transition_ledger.csv"), ledger);
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "access_transition_ledger.csv"), ledger);
        sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, "access_state_timeline.csv"), timeline);
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "access_state_timeline.csv"), timeline);
    end

    function T = buildTimeline(ledger)
        if ~(istable(ledger) && ~isempty(ledger))
            T = table();
            return;
        end
        keep = ["event_index","wall_time","frame","slot","cell_id","ue_id", ...
            "old_state","new_state","procedure","physical_channel", ...
            "transition_reason","access_success","failure_reason"];
        keep = keep(ismember(keep, string(ledger.Properties.VariableNames)));
        T = ledger(:, keep);
    end

    function row = emptyRow()
        row = struct( ...
            "event_index", NaN, ...
            "wall_time", "", ...
            "frame", NaN, ...
            "slot", NaN, ...
            "symbol", NaN, ...
            "cell_id", NaN, ...
            "ue_id", NaN, ...
            "old_state", "", ...
            "new_state", "", ...
            "transition_reason", "", ...
            "source_function", "", ...
            "source_file", "", ...
            "procedure", "", ...
            "physical_channel", "", ...
            "required_precondition", "", ...
            "precondition_value", "", ...
            "timer_name", "", ...
            "timer_value", NaN, ...
            "rnti", NaN, ...
            "temporary_crnti", NaN, ...
            "ssb_index", NaN, ...
            "prach_occasion_id", NaN, ...
            "prach_preamble_index", NaN, ...
            "prach_root_sequence", NaN, ...
            "prach_format", "", ...
            "prach_detected", false, ...
            "prach_detection_metric", NaN, ...
            "timing_advance_samples", NaN, ...
            "rar_created", false, ...
            "rar_decoded", false, ...
            "msg3_grant_created", false, ...
            "msg3_tx_executed", false, ...
            "msg3_crc_pass", false, ...
            "msg4_created", false, ...
            "msg4_decoded", false, ...
            "contention_resolution_pass", false, ...
            "access_success", false, ...
            "failure_reason", "", ...
            "old_state_original", "", ...
            "new_state_original", "");
    end

    function s = toString(value)
        if isstring(value) || ischar(value)
            s = string(value);
        elseif islogical(value)
            s = string(logical(value));
        elseif isnumeric(value)
            s = string(double(value));
        else
            s = "";
        end
    end

    function Tout = appendCompatTable(Ta, Tb)
        if ~(istable(Ta) && ~isempty(Ta))
            Tout = Tb;
            return;
        end
        if ~(istable(Tb) && ~isempty(Tb))
            Tout = Ta;
            return;
        end
        names = unique([string(Ta.Properties.VariableNames), string(Tb.Properties.VariableNames)], "stable");
        Ta = sixgr.monitor.AccessFlowRecorder.ensureVars(Ta, names, Tb);
        Tb = sixgr.monitor.AccessFlowRecorder.ensureVars(Tb, names, Ta);
        Tout = [Ta(:, cellstr(names)); Tb(:, cellstr(names))];
    end

    function T = ensureVars(T, names, referenceT)
        for i = 1:numel(names)
            name = char(names(i));
            if ismember(name, T.Properties.VariableNames)
                continue;
            end
            if istable(referenceT) && ismember(name, referenceT.Properties.VariableNames)
                sample = referenceT.(name);
                if isstring(sample)
                    T.(name) = strings(height(T), 1);
                elseif islogical(sample)
                    T.(name) = false(height(T), 1);
                elseif isnumeric(sample)
                    T.(name) = nan(height(T), 1);
                else
                    T.(name) = repmat({''}, height(T), 1);
                end
            else
                T.(name) = strings(height(T), 1);
            end
        end
    end
end
end
