function T = deriveInitialAccessProcedureDelay(T, varargin)
%DERIVEINITIALACCESSPROCEDUREDELAY Bind access delay to runtime event times.
%
% The function marks the terminal Msg4 lifecycle row for each UE and SNR
% sweep point, and adds a procedure-delay sample only when all four-step RA
% events from that same operating point are present.
% It never substitutes configured latency or MATLAB compute time.

p = inputParser;
p.addParameter("SlotDuration_s", NaN, ...
    @(x)isnumeric(x) && isscalar(x));
p.addParameter("RequireRRCSetupComplete", false, ...
    @(x)islogical(x) && isscalar(x));
p.parse(varargin{:});
fallbackSlotDuration_s = double(p.Results.SlotDuration_s);
requireRRCSetupComplete = logical(p.Results.RequireRRCSetupComplete);

if ~(istable(T) && ~isempty(T))
    return;
end
requiredColumns = ["UEIndex","EventName","Slot","Time_s"];
if ~all(ismember(requiredColumns, string(T.Properties.VariableNames)))
    error("sixgr:truth:InitialAccessLifecycleSchemaMissing", ...
        "Initial-access lifecycle evidence requires columns: %s.", ...
        strjoin(requiredColumns, ", "));
end

n = height(T);
T = localEnsureNumericColumn(T, "ProcedureStartSlot", n);
T = localEnsureNumericColumn(T, "ProcedureEndSlot", n);
T = localEnsureNumericColumn(T, "ProcedureDelay_ms", n);
T = localEnsureNumericColumn(T, "AccessDelay_ms", n);
T = localEnsureLogicalColumn(T, "CompleteFlag", n);

ueValues = double(T.UEIndex);
if ismember("SweepPointIndex", string(T.Properties.VariableNames))
    sweepValues = double(T.SweepPointIndex);
else
    sweepValues = ones(n, 1);
end
eventNames = upper(strtrim(string(T.EventName)));
slots = double(T.Slot);
times_s = double(T.Time_s);
groupRows = find(isfinite(ueValues) & isfinite(sweepValues));
if isempty(groupRows)
    return;
end
groups = unique([ueValues(groupRows), sweepValues(groupRows)], "rows", "stable");
for groupIdx = 1:size(groups, 1)
    ue = groups(groupIdx, 1);
    sweepPoint = groups(groupIdx, 2);
    ueMask = ueValues == ue & sweepValues == sweepPoint;
    if any(ueMask & logical(T.CompleteFlag) & ...
            isfinite(double(T.ProcedureDelay_ms)))
        continue;
    end
    requiredEvents = ["SSB_DETECTED","PBCH_DECODED", ...
        "PRACH_MSG1_DETECTED","MSG2_RAR_DECODED", ...
        "MSG3_PUSCH_COMPLETED"];
    if any(arrayfun(@(name)~any(ueMask & eventNames == name), requiredEvents))
        continue;
    end
    if requireRRCSetupComplete
        terminalNames = ["RRC_SETUP_COMPLETE_ACCEPTED", ...
            "RRC_SETUP_COMPLETE_DECODED","RRC_SETUP_COMPLETE_OK"];
    else
        terminalNames = ["MSG4_CONTENTION_RESOLUTION_COMPLETED", ...
            "MSG4_PDSCH_COMPLETED"];
    end
    terminalMask = ueMask & ismember(eventNames, terminalNames);
    if ~any(terminalMask)
        continue;
    end
    startMask = ueMask & ismember(eventNames, ["SSB_DETECTED","PBCH_DECODED"]);
    startRows = find(startMask & isfinite(slots) & isfinite(times_s));
    terminalRows = find(terminalMask & isfinite(slots) & isfinite(times_s));
    if isempty(startRows) || isempty(terminalRows)
        continue;
    end
    msg4Rows = find(ueMask & ismember(eventNames, ...
        ["MSG4_CONTENTION_RESOLUTION_COMPLETED","MSG4_PDSCH_COMPLETED"]));
    if isempty(msg4Rows)
        continue;
    end
    localAssertCausalOrder(eventNames, times_s, slots, ueMask, ...
        msg4Rows, terminalRows, requireRRCSetupComplete);
    [~, startLocal] = min(times_s(startRows));
    [~, endLocal] = max(times_s(terminalRows));
    startRow = startRows(startLocal);
    endRow = terminalRows(endLocal);
    slotDuration_s = fallbackSlotDuration_s;
    if ismember("SlotDuration_s", string(T.Properties.VariableNames))
        measuredSlotDuration = double(T.SlotDuration_s(endRow));
        if isfinite(measuredSlotDuration) && measuredSlotDuration > 0
            slotDuration_s = measuredSlotDuration;
        end
    end
    if ~(isfinite(slotDuration_s) && slotDuration_s > 0)
        continue;
    end
    delayMs = max(0, ...
        (times_s(endRow) - times_s(startRow) + slotDuration_s) * 1e3);
    T.ProcedureStartSlot(endRow) = slots(startRow);
    T.ProcedureEndSlot(endRow) = slots(endRow);
    T.ProcedureDelay_ms(endRow) = delayMs;
    T.AccessDelay_ms(endRow) = delayMs;
    T.CompleteFlag(endRow) = true;
    T = localAssignText(T, "LifecycleState", endRow, "CONNECTED");
    T = localAssignText(T, "ValueSource", endRow, ...
        "slot_coupled_runtime_initial_access_lifecycle");
    T = localAssignText(T, "ValueRole", endRow, ...
        "measured_runtime_procedure_delay");
    T = localAssignText(T, "ValueStatus", endRow, ...
        "available_runtime_procedure_sample");
    if requireRRCSetupComplete
        definition = "SSB/PBCH through PRACH/Msg2/Msg3/Msg4 and waveform-decoded SRB1 RRCSetupComplete delay from runtime event timestamps";
    else
        definition = "SSB/PBCH through PRACH/Msg2/Msg3/Msg4 delay from runtime event timestamps";
    end
    T = localAssignText(T, "ValueDefinition", endRow, definition);
    T = localAssignText(T, "Notes", endRow, ...
        "Delay uses slot-coupled runtime timestamps only; configured values and compute runtime are not substituted.");
end
end

function localAssertCausalOrder(eventNames, times_s, slots, groupMask, msg4Rows, terminalRows, requireRRC)
pbchRow = localFirstEventRow(eventNames, times_s, groupMask, "PBCH_DECODED");
prachRow = localFirstEventRow(eventNames, times_s, groupMask, "PRACH_MSG1_DETECTED");
msg2Row = localFirstEventRow(eventNames, times_s, groupMask, "MSG2_RAR_DECODED");
msg3Row = localFirstEventRow(eventNames, times_s, groupMask, "MSG3_PUSCH_COMPLETED");
[~, msg4Local] = min(times_s(msg4Rows));
msg4Row = msg4Rows(msg4Local);
rows = [pbchRow,prachRow,msg2Row,msg3Row,msg4Row];
labels = ["PBCH","PRACH_MSG1","MSG2","MSG3","MSG4"];
if requireRRC
    [~, terminalLocal] = min(times_s(terminalRows));
    rows(end+1) = terminalRows(terminalLocal);
    labels(end+1) = "RRC_SETUP_COMPLETE";
end
eventTimes = times_s(rows);
eventSlots = slots(rows);
if any(~isfinite(eventTimes)) || any(~isfinite(eventSlots)) || ...
        any(diff(eventTimes) <= 0) || any(diff(eventSlots) <= 0)
    detail = strjoin(labels + "@slot" + string(eventSlots), " -> ");
    error("sixgr:truth:InitialAccessLifecycleNonCausal", ...
        "Initial-access lifecycle must be strictly causal after PBCH: %s.", detail);
end
end

function row = localFirstEventRow(eventNames, times_s, groupMask, eventName)
rows = find(groupMask & eventNames == eventName & isfinite(times_s));
if isempty(rows)
    error("sixgr:truth:InitialAccessLifecycleEventMissing", ...
        "Required initial-access event %s is missing.", eventName);
end
[~, local] = min(times_s(rows));
row = rows(local);
end

function T = localEnsureNumericColumn(T, name, n)
if ~ismember(name, string(T.Properties.VariableNames))
    T.(name) = nan(n, 1);
end
end

function T = localEnsureLogicalColumn(T, name, n)
if ~ismember(name, string(T.Properties.VariableNames))
    T.(name) = false(n, 1);
else
    T.(name) = logical(T.(name));
end
end

function T = localAssignText(T, name, row, value)
if ~ismember(name, string(T.Properties.VariableNames))
    return;
end
if iscell(T.(name))
    T.(name){row} = char(value);
elseif isstring(T.(name))
    T.(name)(row) = string(value);
elseif iscategorical(T.(name))
    T.(name)(row) = categorical(string(value));
else
    T.(name)(row) = value;
end
end
