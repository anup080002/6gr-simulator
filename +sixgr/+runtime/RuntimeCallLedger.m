classdef RuntimeCallLedger
%RUNTIMECALLLEDGER In-process evidence of canonical production entry points.
% The ledger proves invocation only. It does not infer numerical correctness
% and does not replace MATLAB profiler performance evidence.

methods(Static)
    function configure(runFolder, identity)
        if nargin < 2 || ~isstruct(identity), identity = struct(); end
        payload = struct("RunFolder", string(runFolder), ...
            "RunId", string(sixgr.util.structGet(identity,"RunId","")), ...
            "ExecutionID", string(sixgr.util.structGet(identity,"ExecutionID","")), ...
            "ConfigHash", string(sixgr.util.structGet(identity,"ConfigHash","")), ...
            "PreserveExisting", logical(sixgr.util.structGet( ...
            identity,"PreserveExisting",false)));
        sixgr.runtime.RuntimeCallLedger.dispatch("configure", payload);
    end

    function record(functionName, component, direction, context)
        if nargin < 2, component = ""; end
        if nargin < 3, direction = ""; end
        if nargin < 4 || ~isstruct(context), context = struct(); end
        payload = struct("FunctionName", string(functionName), ...
            "Component", upper(string(component)), ...
            "Direction", upper(string(direction)), ...
            "Context", context);
        sixgr.runtime.RuntimeCallLedger.dispatch("record", payload);
    end

    function out = flush()
        out = sixgr.runtime.RuntimeCallLedger.dispatch("flush", struct());
    end

    function T = snapshot()
        T = sixgr.runtime.RuntimeCallLedger.dispatch("snapshot", struct());
    end

    function reset()
        sixgr.runtime.RuntimeCallLedger.dispatch("reset", struct());
    end
end

methods(Static, Access=private)
    function out = dispatch(action, payload)
        persistent state
        if isempty(state)
            state = struct("Configured",false,"RunFolder","","RunId","", ...
                "ExecutionID","","ConfigHash","","Rows",repmat( ...
                sixgr.runtime.RuntimeCallLedger.emptyRow(),0,1),"Sequence",0);
        end
        out = [];
        switch lower(string(action))
            case "configure"
                state.Configured = true;
                state.RunFolder = string(payload.RunFolder);
                state.RunId = string(payload.RunId);
                state.ExecutionID = string(payload.ExecutionID);
                state.ConfigHash = string(payload.ConfigHash);
                if logical(payload.PreserveExisting)
                    [state.Rows, state.Sequence] = ...
                        sixgr.runtime.RuntimeCallLedger.loadExistingRows(state);
                else
                    state.Rows = repmat( ...
                        sixgr.runtime.RuntimeCallLedger.emptyRow(),0,1);
                    state.Sequence = 0;
                end
            case "record"
                if ~state.Configured, return; end
                state.Sequence = state.Sequence + 1;
                row = sixgr.runtime.RuntimeCallLedger.emptyRow();
                row.Sequence = state.Sequence;
                row.TimestampUTC = sixgr.util.utcNowISO8601();
                row.FunctionName = string(payload.FunctionName);
                row.Component = string(payload.Component);
                row.Direction = string(payload.Direction);
                row.Event = "ENTER";
                row.RunId = state.RunId;
                row.ExecutionID = state.ExecutionID;
                row.ConfigHash = state.ConfigHash;
                % Hash only when the ledger is configured. Calibration and
                % component-level Monte Carlo loops deliberately run with
                % no ledger sink; hashing their large contexts before the
                % configured-state check was pure discarded work.
                row.ContextSHA256 = ...
                    sixgr.runtime.RuntimeCallLedger.contextHash(payload.Context);
                row.EvidenceClass = "ACTUAL_RUNTIME_ENTRY";
                row.ApproximationMode = "none";
                state.Rows(end+1,1) = row;
            case "snapshot"
                out = struct2table(state.Rows);
            case "flush"
                out = struct2table(state.Rows);
                if state.Configured && strlength(strtrim(state.RunFolder)) > 0
                    layout = sixgr.report.resultLayout(char(state.RunFolder));
                    sixgr.util.ensureFolder(layout.ReportCSVDir);
                    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, ...
                        "runtime_call_ledger.csv"), out, "PreserveSchema", true);
                end
            case "reset"
                state = [];
            otherwise
                error("sixgr:runtime:RuntimeCallLedgerBadAction", ...
                    "Unknown runtime call-ledger action '%s'.", action);
        end
    end

    function digest = contextHash(context)
        try
            digest = string(sixgr.util.sha256Hex(uint8(unicode2native( ...
                jsonencode(context), "UTF-8"))));
        catch
            digest = "";
        end
    end

    function row = emptyRow()
        row = struct("Sequence",NaN,"TimestampUTC","","FunctionName","", ...
            "Component","","Direction","","Event","","RunId","", ...
            "ExecutionID","","ConfigHash","","ContextSHA256","", ...
            "EvidenceClass","","ApproximationMode","");
    end

    function [rows, sequence] = loadExistingRows(state)
        layout = sixgr.report.resultLayout(char(state.RunFolder));
        pathValue = fullfile(layout.ReportCSVDir, ...
            "runtime_call_ledger.csv");
        if ~isfile(pathValue)
            error("sixgr:runtime:RuntimeCallLedgerResumeMissing", ...
                "Finalization resume requires the existing runtime call ledger: %s", ...
                pathValue);
        end
        try
            T = readtable(pathValue, "TextType", "string", ...
                "VariableNamingRule", "preserve");
        catch ME
            error("sixgr:runtime:RuntimeCallLedgerResumeUnreadable", ...
                "Unable to read the existing runtime call ledger: %s", ...
                ME.message);
        end
        expected = string(fieldnames( ...
            sixgr.runtime.RuntimeCallLedger.emptyRow())).';
        if isempty(T) || ~all(ismember(expected, ...
                string(T.Properties.VariableNames)))
            error("sixgr:runtime:RuntimeCallLedgerResumeEmpty", ...
                ["Finalization resume cannot replace missing or empty " + ...
                "in-path runtime-call evidence."]);
        end
        identityFields = ["RunId","ExecutionID","ConfigHash"];
        expectedValues = [state.RunId,state.ExecutionID,state.ConfigHash];
        for idx = 1:numel(identityFields)
            observed = unique(strtrim(string( ...
                T.(char(identityFields(idx))))), "stable");
            observed(observed == "") = [];
            if numel(observed) ~= 1 || observed ~= expectedValues(idx)
                error("sixgr:runtime:RuntimeCallLedgerResumeIdentityMismatch", ...
                    "Existing ledger %s does not match resumed identity %s.", ...
                    identityFields(idx), expectedValues(idx));
            end
        end
        seq = double(T.Sequence);
        if any(~isfinite(seq) | seq < 1 | seq ~= floor(seq)) || ...
                numel(unique(seq)) ~= height(T)
            error("sixgr:runtime:RuntimeCallLedgerResumeSequenceInvalid", ...
                "Existing runtime-call sequence is not finite, positive, and unique.");
        end
        T = sortrows(T, "Sequence");
        rows = table2struct(T);
        sequence = max(double(T.Sequence));
    end
end
end
