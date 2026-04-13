function controlTrace = exportControlPlaneTraces(runFolder, e2e)
%EXPORTCONTROLPLANETRACES Build control-plane traces from link and E2E truth outputs.

layout = sixgr.report.resultLayout(runFolder);
controlDir = layout.ControlCSVDir;
sixgr.util.ensureFolder(controlDir);

linkCsvDir = layout.AirInterfaceCSVDir;
pbchTrials = localReadControlTrialTable(fullfile(linkCsvDir, "pbch_trials.csv"));
prachTrials = localReadControlTrialTable(fullfile(linkCsvDir, "prach_trials.csv"));
pdcchTrials = localReadControlTrialTable(fullfile(linkCsvDir, "pdcch_trials.csv"));
pucchTrials = localReadControlTrialTable(fullfile(linkCsvDir, "pucch_trials.csv"));

if isempty(pbchTrials), pbchTrials = localEmptyLinkTrialTable(0); end
if isempty(prachTrials), prachTrials = localEmptyLinkTrialTable(0); end
if isempty(pdcchTrials), pdcchTrials = localEmptyLinkTrialTable(0); end
if isempty(pucchTrials), pucchTrials = localEmptyLinkTrialTable(0); end

cellSearchTrials = pbchTrials;
pbchRecoveryTrials = pbchTrials;
if ~isempty(cellSearchTrials), cellSearchTrials.ControlStage = repmat("CELL_SEARCH", height(cellSearchTrials), 1); end
if ~isempty(pbchRecoveryTrials), pbchRecoveryTrials.ControlStage = repmat("PBCH_RECOVERY", height(pbchRecoveryTrials), 1); end
if ~isempty(prachTrials), prachTrials.ControlStage = repmat("PRACH_ACCESS", height(prachTrials), 1); end
if ~isempty(pdcchTrials), pdcchTrials.ControlStage = repmat("PDCCH_CONTROL", height(pdcchTrials), 1); end
if ~isempty(pucchTrials), pucchTrials.ControlStage = repmat("PUCCH_CONTROL", height(pucchTrials), 1); end

fCell = fullfile(controlDir, "cell_search_trials.csv");
fPBCH = fullfile(controlDir, "pbch_recovery_trials.csv");
fPRACH = fullfile(controlDir, "prach_trials.csv");
fPDCCH = fullfile(controlDir, "pdcch_trials.csv");
fPUCCH = fullfile(controlDir, "pucch_trials.csv");
sixgr.util.csvWriteTable(fCell, cellSearchTrials);
sixgr.util.csvWriteTable(fPBCH, pbchRecoveryTrials);
sixgr.util.csvWriteTable(fPRACH, prachTrials);
sixgr.util.csvWriteTable(fPDCCH, pdcchTrials);
sixgr.util.csvWriteTable(fPUCCH, pucchTrials);

attachTrace = table();
if builtin("isstruct", e2e) && isscalar(e2e)
    attachTrace = sixgr.util.structGet(e2e, "AttachTraceTable", table());
end
if ~(istable(attachTrace) && ~isempty(attachTrace))
    try
        attachTrace = readtable(fullfile(layout.PacketFlowCSVDir, "e2e_attach_trace.csv"), "VariableNamingRule", "preserve");
    catch
        attachTrace = localEmptyAttachTraceTable();
    end
end
if isempty(attachTrace)
    attachTrace = localEmptyAttachTraceTable();
end

attachStateTrace = localBuildAttachStateTraceTable(attachTrace);
rrcMessageTrace = localBuildRRCMessageTraceTable(attachTrace);
fAttachState = fullfile(controlDir, "attach_state_trace.csv");
fRRCMsg = fullfile(controlDir, "rrc_message_trace.csv");
sixgr.util.csvWriteTable(fAttachState, attachStateTrace);
sixgr.util.csvWriteTable(fRRCMsg, rrcMessageTrace);

controlTrace = struct();
controlTrace.Folder = controlDir;
controlTrace.CellSearchTrialsCSV = fCell;
controlTrace.PBCHRecoveryTrialsCSV = fPBCH;
controlTrace.PRACHTrialsCSV = fPRACH;
controlTrace.PDCCHTrialsCSV = fPDCCH;
controlTrace.PUCCHTrialsCSV = fPUCCH;
controlTrace.AttachStateTraceCSV = fAttachState;
controlTrace.RRCMessageTraceCSV = fRRCMsg;
end

function T = localReadControlTrialTable(filePath)
T = table();
if nargin < 1 || strlength(string(filePath)) == 0
    return;
end
if exist(char(string(filePath)), "file") ~= 2
    return;
end
try
    T = readtable(char(string(filePath)), "VariableNamingRule", "preserve");
catch
    T = table();
end
end

function T = localEmptyLinkTrialTable(nRows)
nRows = max(0, round(double(nRows)));
T = table(strings(nRows,1), NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), ...
    NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), strings(nRows,1), NaN(nRows,1), ...
    NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), ...
    strings(nRows,1), false(nRows,1), strings(nRows,1), ...
    'VariableNames', {'Direction','SNR_dB','Seed','Frame','Slot','MCS','PRBs','Layers','TBSize_bits', ...
    'ChannelModel','DopplerHz','CRCPass','DecoderIterations','EVM_rms','NMSE_dB','DetectionMetric', ...
    'BitErrors','BitsCompared','Status','Crash','Notes'});
end

function T = localEmptyAttachTraceTable()
T = table([], [], string.empty(0,1), string.empty(0,1), string.empty(0,1), [], [], [], false(0,1), string.empty(0,1), ...
    'VariableNames', {'Slot','Time_s','Direction','Event','Message','UE','CellID','TempCRNTI','Success','Cause'});
end

function T = localBuildAttachStateTraceTable(attachTrace)
if ~(istable(attachTrace) && ~isempty(attachTrace))
    T = table([], [], [], [], [], string.empty(0,1), string.empty(0,1), string.empty(0,1), false(0,1), string.empty(0,1), ...
        'VariableNames', {'Step','Slot','Time_s','UE','CellID','Direction','Event','State','Success','Cause'});
    return;
end
A = attachTrace;
n = height(A);
step = (1:n).';
state = strings(n,1);
for i = 1:n
    evt = "";
    msg = "";
    if ismember("Event", A.Properties.VariableNames), evt = string(A.Event(i)); end
    if ismember("Message", A.Properties.VariableNames), msg = string(A.Message(i)); end
    state(i) = localAttachEventToState(evt, msg);
end
slotCol = localNumericColumn(A, "Slot", NaN(n,1));
timeCol = localNumericColumn(A, "Time_s", NaN(n,1));
ueCol = localNumericColumn(A, "UE", NaN(n,1));
cellCol = localNumericColumn(A, "CellID", NaN(n,1));
dirCol = localStringColumn(A, "Direction", strings(n,1));
evtCol = localStringColumn(A, "Event", strings(n,1));
okCol = localLogicalColumn(A, "Success", false(n,1));
causeCol = localStringColumn(A, "Cause", strings(n,1));
T = table(step, slotCol, timeCol, ueCol, cellCol, dirCol, evtCol, state, okCol, causeCol, ...
    'VariableNames', {'Step','Slot','Time_s','UE','CellID','Direction','Event','State','Success','Cause'});
end

function T = localBuildRRCMessageTraceTable(attachTrace)
if ~(istable(attachTrace) && ~isempty(attachTrace))
    T = table([], [], [], [], [], [], string.empty(0,1), string.empty(0,1), string.empty(0,1), false(0,1), string.empty(0,1), ...
        'VariableNames', {'Step','Slot','Time_s','UE','CellID','TempCRNTI','Direction','Event','Message','Success','Cause'});
    return;
end
A = attachTrace;
n = height(A);
msgCol = localStringColumn(A, "Message", strings(n,1));
evtCol = localStringColumn(A, "Event", strings(n,1));
uMsg = upper(msgCol);
uEvt = upper(evtCol);
isMsg = strlength(msgCol) > 0 & (startsWith(uEvt, "MSG") | startsWith(uMsg, "RRC") | ismember(uMsg, ["PRACH","RAR","PUCCH_ACKNACK"]));
if ~any(isMsg)
    T = table([], [], [], [], [], [], string.empty(0,1), string.empty(0,1), string.empty(0,1), false(0,1), string.empty(0,1), ...
        'VariableNames', {'Step','Slot','Time_s','UE','CellID','TempCRNTI','Direction','Event','Message','Success','Cause'});
    return;
end
idx = find(isMsg);
slotCol = localNumericColumn(A, "Slot", NaN(n,1));
timeCol = localNumericColumn(A, "Time_s", NaN(n,1));
ueCol = localNumericColumn(A, "UE", NaN(n,1));
cellCol = localNumericColumn(A, "CellID", NaN(n,1));
tmpRntiCol = localNumericColumn(A, "TempCRNTI", NaN(n,1));
dirCol = localStringColumn(A, "Direction", strings(n,1));
okCol = localLogicalColumn(A, "Success", false(n,1));
causeCol = localStringColumn(A, "Cause", strings(n,1));
T = table(idx(:), slotCol(idx), timeCol(idx), ueCol(idx), cellCol(idx), tmpRntiCol(idx), ...
    dirCol(idx), evtCol(idx), msgCol(idx), okCol(idx), causeCol(idx), ...
    'VariableNames', {'Step','Slot','Time_s','UE','CellID','TempCRNTI','Direction','Event','Message','Success','Cause'});
end

function state = localAttachEventToState(eventName, messageName)
uEvt = upper(strtrim(char(string(eventName))));
uMsg = upper(strtrim(char(string(messageName))));
switch uEvt
    case "ATTACH_START", state = "START";
    case "MSG1_TX", state = "PRACH_SENT";
    case "MSG2_RX", state = "RAR_RECEIVED";
    case "MSG2_MISS", state = "RAR_MISSED";
    case "MSG3_TX", state = "RRC_SETUP_REQUEST_SENT";
    case "MSG3_ACK_ERR", state = "MSG3_ACK_ERROR";
    case "MSG4_RX", state = "RRC_SETUP_RECEIVED";
    case "MSG4_MISS", state = "RRC_SETUP_MISSED";
    case "MSG5_TX", state = "RRC_SETUP_COMPLETE_SENT";
    case "MSG5_ACK_ERR", state = "MSG5_ACK_ERROR";
    case "ATTACH_RETRY", state = "RETRY";
    case "ATTACH_CONNECTED", state = "CONNECTED";
    case "ATTACH_FAILED", state = "FAILED";
    case "ATTACH_EXCEPTION", state = "EXCEPTION";
    otherwise
        if startsWith(uMsg, "RRC")
            state = "RRC_SIGNALING";
        elseif strcmp(uMsg, "PRACH")
            state = "PRACH";
        elseif strcmp(uMsg, "RAR")
            state = "RAR";
        else
            state = "UNSPECIFIED";
        end
end
state = string(state);
end

function v = localNumericColumn(T, name, fallback)
if ismember(name, T.Properties.VariableNames)
    try
        v = double(T.(name));
        return;
    catch
    end
end
v = double(fallback);
end

function v = localLogicalColumn(T, name, fallback)
if ismember(name, T.Properties.VariableNames)
    try
        v = logical(T.(name));
        return;
    catch
    end
end
v = logical(fallback);
end

function v = localStringColumn(T, name, fallback)
if ismember(name, T.Properties.VariableNames)
    try
        v = string(T.(name));
        return;
    catch
    end
end
v = string(fallback);
end
