classdef MessageFlowTracer
%SIXGR.TRACE.MESSAGEFLOWTRACER Build a normalized runtime message-flow trace.

    methods (Static)
        function T = generate(runFolder, runId)
            layout = sixgr.report.resultLayout(runFolder);
            rows = repmat(localEmptyRow(), 0, 1);
            eventId = 0;

            specs = { ...
                fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv"), "PBCH", "DL", "broadcast", "broadcast", "pbch", "pbch_trials.csv"; ...
                fullfile(layout.ControlCSVDir, "pbch_recovery_trials.csv"), "MIB", "DL", "broadcast", "broadcast", "mib_decode", "pbch_recovery_trials.csv"; ...
                fullfile(layout.ControlCSVDir, "sib1_recovery_trials.csv"), "SIB1", "DL", "broadcast", "broadcast", "sib1_decode", "sib1_recovery_trials.csv"; ...
                fullfile(layout.ControlCSVDir, "prach_trials.csv"), "PRACH_Msg1", "UL", "random_access", "random_access", "prach", "prach_trials.csv"; ...
                fullfile(layout.ControlCSVDir, "pdcch_trials.csv"), "PDCCH_DCI", "DL", "control", "scheduler", "pdcch", "pdcch_trials.csv"; ...
                fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), "PDSCH_TB", "DL", "air_interface", "traffic", "pdsch_dl", "dl_pdsch_trials.csv"; ...
                fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), "PUSCH_TB", "UL", "air_interface", "traffic", "pusch_ul", "ul_pusch_trials.csv"; ...
                fullfile(layout.AirInterfaceCSVDir, "pucch_trials.csv"), "PUCCH_UCI", "UL", "air_interface", "harq", "pucch_uci", "pucch_trials.csv"; ...
                fullfile(layout.Root, "reference_signals", "csv", "srs_trials.csv"), "SRS", "UL", "reference_signal", "sounding", "srs", "srs_trials.csv"; ...
                fullfile(layout.Root, "reference_signals", "csv", "trs_trials.csv"), "TRS", "DL", "reference_signal", "tracking", "trs", "trs_trials.csv"; ...
                fullfile(layout.ReportCSVDir, "live_user_performance_snapshot.csv"), "TrafficPacket", "BIDIR", "traffic", "traffic", "traffic_snapshot", "live_user_performance_snapshot.csv" ...
                };

            for i = 1:size(specs, 1)
                sourcePath = char(specs{i, 1});
                if exist(sourcePath, "file") ~= 2
                    continue;
                end
                src = readtable(sourcePath, "VariableNamingRule", "preserve");
                for r = 1:height(src)
                    eventId = eventId + 1;
                    rows(end+1, 1) = localRowFromSource( ... %#ok<AGROW>
                        src, r, runId, eventId, ...
                        string(specs{i, 2}), string(specs{i, 3}), string(specs{i, 4}), ...
                        string(specs{i, 5}), string(specs{i, 6}), string(specs{i, 7}));
                end
            end

            if isempty(rows)
                T = localTable(repmat(localEmptyRow(), 0, 1));
            else
                T = localTable(rows);
            end
            outPath = fullfile(layout.ReportCSVDir, "runtime_message_flow_trace.csv");
            sixgr.util.csvWriteTable(outPath, T);
        end
    end
end

function row = localRowFromSource(T, idx, runId, eventId, messageType, direction, layer, subsystem, stage, sourceFile)
row = localEmptyRow();
row.RunId = string(runId);
row.EventId = double(eventId);
row.ParentEventId = localNumber(T, idx, ["ParentEventId","GrantId"], NaN);
row.Timestamp = localText(T, idx, ["Timestamp","TimeUTC","Time","Time_s"], "");
if strlength(row.Timestamp) == 0
    row.Timestamp = string(idx);
end
row.Slot = localNumber(T, idx, ["Slot","SlotNumber"], NaN);
row.Frame = localNumber(T, idx, ["Frame","FrameNumber"], NaN);
row.Symbol = localNumber(T, idx, ["Symbol","StartSymbol"], NaN);
row.UEId = localNumber(T, idx, ["UEID","UEId"], NaN);
row.CellId = localNumber(T, idx, ["CellID","CellId","ServingCellId"], NaN);
row.Direction = direction;
row.Layer = layer;
row.Subsystem = subsystem;
row.MessageType = messageType;
row.Procedure = localText(T, idx, ["Procedure","Stage","Case"], stage);
row.Stage = stage;
row.InputArtifact = string(sourceFile);
row.OutputArtifact = string(sourceFile);
row.RNTI = localNumber(T, idx, ["RNTI","TempCRNTI"], NaN);
row.HARQProcessId = localNumber(T, idx, ["HARQProcessId","HARQId"], NaN);
row.GrantId = localNumber(T, idx, ["GrantId"], NaN);
row.TransportBlockId = localText(T, idx, ["TransportBlockId","TBId","PayloadId"], "");
row.PayloadHash = localText(T, idx, ["PayloadHash","TxPayloadHash","PayloadSHA256"], "");
row.Status = localStatus(T, idx);
row.FailureReason = localText(T, idx, ["FailureReason","Reason","Notes"], "");
end

function status = localStatus(T, idx)
if localHasVar(T, "CRCPass")
    status = localBoolWord(T.CRCPass(idx));
    return;
end
if localHasVar(T, "StrictOk")
    status = localBoolWord(T.StrictOk(idx));
    return;
end
if localHasVar(T, "Valid")
    status = localBoolWord(T.Valid(idx));
    return;
end
if localHasVar(T, "MissedDetection")
    status = localBoolWord(~logical(T.MissedDetection(idx)));
    return;
end
status = "observed";
end

function out = localBoolWord(value)
try
    tf = logical(value);
catch
    tf = any(strcmpi(string(value), ["true","1","yes","pass","ok","valid"]));
end
if tf
    out = "pass";
else
    out = "fail";
end
end

function tf = localHasVar(T, name)
tf = ismember(string(name), string(T.Properties.VariableNames));
end

function value = localText(T, idx, names, defaultValue)
names = string(names(:));
for i = 1:numel(names)
    if localHasVar(T, names(i))
        raw = T.(names(i))(idx);
        try
            value = string(raw);
        catch
            value = string(defaultValue);
        end
        if ismissing(value)
            value = string(defaultValue);
        end
        return;
    end
end
value = string(defaultValue);
end

function value = localNumber(T, idx, names, defaultValue)
names = string(names(:));
for i = 1:numel(names)
    if localHasVar(T, names(i))
        raw = T.(names(i))(idx);
        try
            value = double(raw);
        catch
            value = defaultValue;
        end
        if ~isscalar(value) || ~isfinite(value)
            value = defaultValue;
        end
        return;
    end
end
value = defaultValue;
end

function T = localTable(rows)
T = struct2table(rows, "AsArray", true);
end

function row = localEmptyRow()
row = struct( ...
    "RunId", "", ...
    "EventId", NaN, ...
    "ParentEventId", NaN, ...
    "Timestamp", "", ...
    "Slot", NaN, ...
    "Frame", NaN, ...
    "Symbol", NaN, ...
    "UEId", NaN, ...
    "CellId", NaN, ...
    "Direction", "", ...
    "Layer", "", ...
    "Subsystem", "", ...
    "MessageType", "", ...
    "Procedure", "", ...
    "Stage", "", ...
    "InputArtifact", "", ...
    "OutputArtifact", "", ...
    "RNTI", NaN, ...
    "HARQProcessId", NaN, ...
    "GrantId", NaN, ...
    "TransportBlockId", "", ...
    "PayloadHash", "", ...
    "Status", "", ...
    "FailureReason", "");
end
