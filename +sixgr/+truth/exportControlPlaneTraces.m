function controlTrace = exportControlPlaneTraces(runFolder, e2e, runtime)
%EXPORTCONTROLPLANETRACES Build control-plane traces from link and E2E truth outputs.

layout = sixgr.report.resultLayout(runFolder);
controlDir = layout.ControlCSVDir;
sixgr.util.ensureFolder(controlDir);

if nargin < 2 || ~(builtin("isstruct", e2e) && isscalar(e2e))
    e2e = struct();
end
if nargin < 3 || ~(builtin("isstruct", runtime) && isscalar(runtime))
    runtime = struct();
end

linkCsvDir = layout.AirInterfaceCSVDir;
runtimeTables = localResolveRuntimeTables(runtime);
pbchTrials = localResolveControlTrialTable(runtimeTables, "PBCH", fullfile(controlDir, "pbch_trials.csv"), fullfile(linkCsvDir, "pbch_trials.csv"));
prachTrials = localResolveControlTrialTable(runtimeTables, "PRACH", fullfile(controlDir, "prach_trials.csv"), fullfile(linkCsvDir, "prach_trials.csv"));
pdcchTrials = localResolveControlTrialTable(runtimeTables, "PDCCH", fullfile(controlDir, "pdcch_trials.csv"), fullfile(linkCsvDir, "pdcch_trials.csv"));
pucchTrials = localResolveControlTrialTable(runtimeTables, "PUCCH", fullfile(controlDir, "pucch_trials.csv"), fullfile(linkCsvDir, "pucch_trials.csv"));
srsTrials = localResolveControlTrialTable(runtimeTables, "SRS", fullfile(controlDir, "srs_trials.csv"), fullfile(linkCsvDir, "srs_trials.csv"));
trsTrials = localResolveControlTrialTable(runtimeTables, "TRS", fullfile(controlDir, "trs_trials.csv"), fullfile(linkCsvDir, "trs_trials.csv"));
initialAccessLifecycle = localResolveOptionalTable(runtimeTables, "InitialAccessLifecycleTraceTable", ...
    fullfile(controlDir, "initial_access_lifecycle_trace.csv"), ...
    fullfile(layout.ReportCSVDir, "initial_access_lifecycle_trace.csv"));
controlSummary = localResolveOptionalTable(runtimeTables, "ControlGatingSummaryTable", fullfile(layout.ReportCSVDir, "live_control_gating_summary.csv"));
controlState = localResolveOptionalTable(runtimeTables, "ControlGatingStateTable", fullfile(layout.ReportCSVDir, "live_control_gating_state.csv"));

cellSearchTrials = localBuildStageDerivedTrialTable(pbchTrials, "CELL_SEARCH");
pbchRecoveryTrials = localBuildStageDerivedTrialTable(pbchTrials, "PBCH_RECOVERY");
prachTrials = localApplyControlStage(prachTrials, "PRACH_ACCESS");
pdcchTrials = localApplyControlStage(pdcchTrials, "PDCCH_CONTROL");
pucchTrials = localApplyControlStage(pucchTrials, "PUCCH_CONTROL");
srsTrials = localApplyControlStage(srsTrials, "SRS_SOUNDING");
trsTrials = localApplyControlStage(trsTrials, "TRS_TRACKING");

fCell = fullfile(controlDir, "cell_search_trials.csv");
fPBCH = fullfile(controlDir, "pbch_recovery_trials.csv");
fPBCHRaw = fullfile(controlDir, "pbch_trials.csv");
fPRACH = fullfile(controlDir, "prach_trials.csv");
fPDCCH = fullfile(controlDir, "pdcch_trials.csv");
fPUCCH = fullfile(controlDir, "pucch_trials.csv");
fSRS = fullfile(controlDir, "srs_trials.csv");
fTRS = fullfile(controlDir, "trs_trials.csv");
fInitialAccessLifecycle = fullfile(controlDir, "initial_access_lifecycle_trace.csv");
fControlSummary = fullfile(controlDir, "control_gating_summary.csv");
fControlState = fullfile(controlDir, "control_gating_state.csv");
fCell = localWriteOptionalTable(fCell, cellSearchTrials);
fPBCH = localWriteOptionalTable(fPBCH, pbchRecoveryTrials);
fPBCHRaw = localWriteOptionalTable(fPBCHRaw, pbchTrials);
fPRACH = localWriteOptionalTable(fPRACH, prachTrials);
fPDCCH = localWriteOptionalTable(fPDCCH, pdcchTrials);
fPUCCH = localWriteOptionalTable(fPUCCH, pucchTrials);
fSRS = localWriteOptionalTable(fSRS, srsTrials);
fTRS = localWriteOptionalTable(fTRS, trsTrials);
fInitialAccessLifecycle = localWriteOptionalTable(fInitialAccessLifecycle, initialAccessLifecycle);
fControlSummary = localWriteOptionalTable(fControlSummary, controlSummary);
fControlState = localWriteOptionalTable(fControlState, controlState);

attachTrace = table();
attachTrace = sixgr.util.structGet(e2e, "AttachTraceTable", table());
if ~(istable(attachTrace) && ~isempty(attachTrace)) && ~(istable(controlState) && ~isempty(controlState))
    try
        attachTrace = readtable(fullfile(layout.PacketFlowCSVDir, "e2e_attach_trace.csv"), "VariableNamingRule", "preserve");
    catch
        attachTrace = table();
    end
end

fAttachState = fullfile(controlDir, "attach_state_trace.csv");
fRRCMsg = fullfile(controlDir, "rrc_message_trace.csv");
if istable(attachTrace) && ~isempty(attachTrace)
    attachStateTrace = localBuildAttachStateTraceTable(attachTrace);
    rrcMessageTrace = localBuildRRCMessageTraceTable(attachTrace);
elseif istable(controlState) && ~isempty(controlState)
    attachStateTrace = localBuildAttachStateTraceFromControlState(controlState);
    rrcMessageTrace = table();
else
    attachStateTrace = table();
    rrcMessageTrace = table();
end
fAttachState = localWriteOptionalTable(fAttachState, attachStateTrace);
fRRCMsg = localWriteOptionalTable(fRRCMsg, rrcMessageTrace);

controlTrace = struct();
controlTrace.Folder = controlDir;
controlTrace.CellSearchTrialsCSV = fCell;
controlTrace.PBCHRecoveryTrialsCSV = fPBCH;
controlTrace.PBCHTrialsCSV = fPBCHRaw;
controlTrace.PRACHTrialsCSV = fPRACH;
controlTrace.PDCCHTrialsCSV = fPDCCH;
controlTrace.PUCCHTrialsCSV = fPUCCH;
controlTrace.SRSTrialsCSV = fSRS;
controlTrace.TRSTrialsCSV = fTRS;
controlTrace.InitialAccessLifecycleTraceCSV = fInitialAccessLifecycle;
controlTrace.ControlGatingSummaryCSV = fControlSummary;
controlTrace.ControlGatingStateCSV = fControlState;
controlTrace.AttachStateTraceCSV = fAttachState;
controlTrace.RRCMessageTraceCSV = fRRCMsg;
end

function runtimeTables = localResolveRuntimeTables(runtime)
runtimeTables = struct();
if ~(builtin("isstruct", runtime) && isscalar(runtime))
    return;
end
names = ["PBCH","PRACH","PDCCH","PUCCH","SRS","TRS","ControlGatingSummaryTable","ControlGatingStateTable","InitialAccessLifecycleTraceTable"];
for i = 1:numel(names)
    name = char(names(i));
    runtimeTables.(name) = sixgr.util.structGet(runtime, name, table());
end
coupled = sixgr.util.structGet(runtime, "CoupledRuntime", []);
if ~isempty(coupled)
    coupledControlTrials = sixgr.util.structGet(coupled, "ControlTrials", struct());
    for i = 1:6
        trialName = char(names(i));
        if ~(istable(runtimeTables.(trialName)) && ~isempty(runtimeTables.(trialName)))
            runtimeTables.(trialName) = sixgr.util.structGet(coupledControlTrials, trialName, table());
        end
    end
    try
        coupledArtifacts = sixgr.truth.CoupledTruthRuntime.mobilityArtifacts(coupled);
    catch
        coupledArtifacts = struct();
    end
    if ~(istable(runtimeTables.ControlGatingSummaryTable) && ~isempty(runtimeTables.ControlGatingSummaryTable))
        runtimeTables.ControlGatingSummaryTable = sixgr.util.structGet(coupledArtifacts, "ControlGatingSummaryTable", ...
            sixgr.util.structGet(coupled, "ControlGatingSummaryTable", table()));
    end
    if ~(istable(runtimeTables.ControlGatingStateTable) && ~isempty(runtimeTables.ControlGatingStateTable))
        runtimeTables.ControlGatingStateTable = sixgr.util.structGet(coupledArtifacts, "ControlGatingStateTable", ...
            sixgr.util.structGet(coupled, "ControlGatingStateTable", table()));
    end
    if ~(istable(runtimeTables.InitialAccessLifecycleTraceTable) && ~isempty(runtimeTables.InitialAccessLifecycleTraceTable))
        runtimeTables.InitialAccessLifecycleTraceTable = sixgr.util.structGet(coupled, "InitialAccessLifecycleTraceTable", table());
    end
end
end

function T = localResolveControlTrialTable(runtimeTables, fieldName, varargin)
T = sixgr.util.structGet(runtimeTables, fieldName, table());
if istable(T) && ~isempty(T)
    return;
end
for i = 1:numel(varargin)
    T = localReadControlTrialTable(varargin{i});
    if istable(T) && ~isempty(T)
        return;
    end
end
T = table();
end

function T = localResolveOptionalTable(runtimeTables, fieldName, varargin)
T = sixgr.util.structGet(runtimeTables, fieldName, table());
if istable(T) && ~isempty(T)
    return;
end
for i = 1:numel(varargin)
    T = localReadControlTrialTable(varargin{i});
    if istable(T) && ~isempty(T)
        return;
    end
end
T = table();
end

function T = localBuildStageDerivedTrialTable(Tin, stageName)
T = localApplyControlStage(Tin, stageName);
end

function T = localApplyControlStage(T, stageName)
if ~(istable(T) && ~isempty(T))
    T = table();
    return;
end
T.ControlStage = repmat(string(stageName), height(T), 1);
end

function outPath = localWriteOptionalTable(filePath, T)
outPath = "";
if ~(istable(T) && ~isempty(T))
    return;
end
sixgr.util.csvWriteTable(filePath, T);
outPath = string(filePath);
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

function T = localBuildAttachStateTraceFromControlState(controlState)
if ~(istable(controlState) && ~isempty(controlState))
    T = localBuildAttachStateTraceTable(table());
    return;
end
n = height(controlState);
step = (1:n).';
slotCol = localNumericColumn(controlState, "LastSuccessfulPRACHSlot", NaN(n,1));
fallbackPBCH = localNumericColumn(controlState, "LastSuccessfulPBCHSlot", NaN(n,1));
fallbackPDCCH = localNumericColumn(controlState, "LastSuccessfulPDCCHSlot", NaN(n,1));
missingSlot = ~isfinite(slotCol);
slotCol(missingSlot) = fallbackPBCH(missingSlot);
missingSlot = ~isfinite(slotCol);
slotCol(missingSlot) = fallbackPDCCH(missingSlot);
timeCol = nan(n,1);
ueCol = localNumericColumn(controlState, "UEIndex", NaN(n,1));
cellCol = localNumericColumn(controlState, "ServingCell", NaN(n,1));
dirCol = repmat("UL", n, 1);
evtCol = repmat("CONTROL_GATING_SNAPSHOT", n, 1);
stateCol = localStringColumn(controlState, "AccessState", strings(n,1));
okCol = localLogicalColumn(controlState, "SchedulingEligibility", false(n,1));
pbchCol = localStringColumn(controlState, "CellAcquisitionState", strings(n,1));
pdcchCol = localStringColumn(controlState, "LastPDCCHStatus", strings(n,1));
srsCol = localStringColumn(controlState, "SRSValidityState", strings(n,1));
causeCol = "PBCH=" + pbchCol + ";PDCCH=" + pdcchCol + ";SRS=" + srsCol;
T = table(step, slotCol, timeCol, ueCol, cellCol, dirCol, evtCol, stateCol, okCol, causeCol, ...
    'VariableNames', {'Step','Slot','Time_s','UE','CellID','Direction','Event','State','Success','Cause'});
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
