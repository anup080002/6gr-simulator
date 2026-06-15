function T = RAEventLog(events)
%RAEVENTLOG Convert RA state transition structs to a canonical table.
if nargin < 1 || isempty(events)
    T = table('Size', [0 16], ...
        'VariableTypes', {'string','double','double','double','double','double','double','string','string','string','string','double','double','double','string','logical'}, ...
        'VariableNames', {'RunId','CellId','UEId','AttemptId','Frame','Slot','Symbol','StateBefore','StateAfter','Event','TimerName','TimerValueSlots','RNTI','PreambleIndex','FailureReason','StrictOkContribution'});
    return;
end
T = struct2table(events(:), "AsArray", true);
end
