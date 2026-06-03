function out = exportLLSRelationalTraceDatabase(cfg, runFolder, link, controlTrace)
%EXPORTLLSRELATIONALTRACEDATABASE Build a supplementary SQLite trace DB.

if nargin < 3 || ~isstruct(link)
    link = struct();
end
if nargin < 4 || ~isstruct(controlTrace)
    controlTrace = struct();
end

layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.DatabaseDir);

out = struct();
out.Ok = false;
out.Status = "not_started";
out.DBPath = char(string(layout.TraceDatabaseSQLite));
out.RelativeDBPath = localRelativeRunPath(runFolder, layout.TraceDatabaseSQLite);
out.ManifestPath = char(string(layout.TraceDatabaseManifestJSON));
out.TablesWritten = cell(0, 1);
out.Warnings = strings(0, 1);

baseStationID = localConfiguredBaseStationID(cfg);
tableBundle = struct();
tableBundle.Metadata = localBuildMetadataTable(cfg, runFolder, link, controlTrace, baseStationID);
tableBundle.ArtifactCatalog = localBuildArtifactCatalog(layout);
tableBundle.RadioLinkTimeline = localBuildRadioLinkTimeline(layout, baseStationID);
tableBundle.ParallelTaskExecution = localBuildParallelTaskExecution(layout, baseStationID);
tableBundle.ControlPlaneTrace = localBuildControlPlaneTrace(layout, baseStationID);
tableBundle.BeamTrace = localBuildBeamTrace(layout, baseStationID);
tableBundle.HARQPacketTrace = localBuildHARQPacketTrace(layout, baseStationID);
tableBundle.EnergyTrace = localBuildEnergyTrace(layout, baseStationID);

if exist(out.DBPath, "file") == 2
    delete(out.DBPath);
end

if ~(exist("sqlite", "file") == 2 && exist("sqlwrite", "file") == 2)
    out.Status = "sqlite_interface_unavailable";
    localWriteDatabaseManifest(out, tableBundle);
    return;
end

conn = [];
cleanup = onCleanup(@() localCloseSQLite(conn));
try
    conn = sqlite(out.DBPath, "create");
    localExecuteSQL(conn, "PRAGMA journal_mode = WAL");
    localExecuteSQL(conn, "PRAGMA synchronous = NORMAL");

    tableNames = string(fieldnames(tableBundle));
    written = strings(0, 1);
    for i = 1:numel(tableNames)
        matlabName = tableNames(i);
        tableName = localTableNameToken(matlabName);
        T = tableBundle.(char(matlabName));
        if ~(istable(T) && ~isempty(T))
            continue;
        end
        sqlwrite(conn, char(tableName), T);
        localCreateIndexes(conn, tableName);
        written(end+1, 1) = tableName; %#ok<AGROW>
    end
    out.Ok = true;
    out.Status = "ok";
    out.TablesWritten = cellstr(written);
catch ME
    out.Status = "sqlite_export_failed";
    out.Warnings = string(ME.message);
end

localWriteDatabaseManifest(out, tableBundle);
end

function T = localBuildMetadataTable(cfg, runFolder, link, controlTrace, baseStationID)
rows = repmat(struct("Key", "", "Value", ""), 0, 1);
rows(end+1, 1) = struct("Key", "run_folder", "Value", string(runFolder)); %#ok<AGROW>
rows(end+1, 1) = struct("Key", "generated_utc", "Value", string(localUTCStamp())); %#ok<AGROW>
rows(end+1, 1) = struct("Key", "base_station_id", "Value", string(baseStationID)); %#ok<AGROW>
rows(end+1, 1) = struct("Key", "parallel_pool_type", ...
    "Value", string(sixgr.util.structGet(cfg, "run.parallelPoolType", ""))); %#ok<AGROW>
rows(end+1, 1) = struct("Key", "parallel_execution_model", ...
    "Value", string(sixgr.util.structGet(cfg, "run.parallelWorkerExecutionModel", ""))); %#ok<AGROW>
rows(end+1, 1) = struct("Key", "effective_workers", ...
    "Value", string(double(sixgr.util.structGet(cfg, "run.numWorkers", 0)))); %#ok<AGROW>
rows(end+1, 1) = struct("Key", "multi_user_mode", ...
    "Value", string(sixgr.util.structGet(link, "MultiUserMode", ""))); %#ok<AGROW>
rows(end+1, 1) = struct("Key", "control_trace_folder", ...
    "Value", string(sixgr.util.structGet(controlTrace, "Folder", ""))); %#ok<AGROW>
T = struct2table(rows);
end

function T = localBuildArtifactCatalog(layout)
spec = [ ...
    struct("TableName", "radio_link_timeline", "Path", fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv")); ...
    struct("TableName", "radio_link_timeline", "Path", fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv")); ...
    struct("TableName", "radio_link_timeline", "Path", fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv")); ...
    struct("TableName", "radio_link_timeline", "Path", fullfile(layout.AirInterfaceCSVDir, "prach_trials.csv")); ...
    struct("TableName", "radio_link_timeline", "Path", fullfile(layout.AirInterfaceCSVDir, "pdcch_trials.csv")); ...
    struct("TableName", "radio_link_timeline", "Path", fullfile(layout.AirInterfaceCSVDir, "pucch_trials.csv")); ...
    struct("TableName", "radio_link_timeline", "Path", fullfile(layout.AirInterfaceCSVDir, "srs_trials.csv")); ...
    struct("TableName", "radio_link_timeline", "Path", fullfile(layout.AirInterfaceCSVDir, "trs_trials.csv")); ...
    struct("TableName", "parallel_task_execution", "Path", fullfile(layout.AirInterfaceCSVDir, "parallel_task_trace.csv")); ...
    struct("TableName", "control_plane_trace", "Path", fullfile(layout.ControlCSVDir, "attach_state_trace.csv")); ...
    struct("TableName", "control_plane_trace", "Path", fullfile(layout.ControlCSVDir, "rrc_message_trace.csv")); ...
    struct("TableName", "beam_trace", "Path", fullfile(layout.BeamformingCSVDir, "probe_beam_mimo.csv")); ...
    struct("TableName", "beam_trace", "Path", fullfile(layout.BeamformingCSVDir, "beam_score_trace.csv")); ...
    struct("TableName", "harq_packet_trace", "Path", fullfile(layout.HARQCSVDir, "probe_harq_packets.csv")); ...
    struct("TableName", "energy_trace", "Path", fullfile(layout.RFCSVDir, "energy_timeline_trace.csv"))];
rows = repmat(struct("TargetTable", "", "SourceArtifact", "", "Exists", NaN, "RowCount", NaN), 0, 1);
for i = 1:numel(spec)
    path = string(spec(i).Path);
    existsFlag = exist(char(path), "file") == 2;
    rowCount = NaN;
    if existsFlag
        Tsrc = localReadOptionalTable(path);
        if istable(Tsrc)
            rowCount = double(height(Tsrc));
        end
    end
    rows(end+1, 1) = struct( ... %#ok<AGROW>
        "TargetTable", string(spec(i).TableName), ...
        "SourceArtifact", string(localRelativeRunPath(layout.Root, path)), ...
        "Exists", double(existsFlag), ...
        "RowCount", double(rowCount));
end
T = struct2table(rows);
end

function T = localBuildRadioLinkTimeline(layout, baseStationID)
spec = [ ...
    struct("TraceSource", "dl_pdsch_trials", "Direction", "DL", "Path", fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv")); ...
    struct("TraceSource", "ul_pusch_trials", "Direction", "UL", "Path", fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv")); ...
    struct("TraceSource", "pbch_trials", "Direction", "DL", "Path", fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv")); ...
    struct("TraceSource", "prach_trials", "Direction", "UL", "Path", fullfile(layout.AirInterfaceCSVDir, "prach_trials.csv")); ...
    struct("TraceSource", "pdcch_trials", "Direction", "DL", "Path", fullfile(layout.AirInterfaceCSVDir, "pdcch_trials.csv")); ...
    struct("TraceSource", "pucch_trials", "Direction", "UL", "Path", fullfile(layout.AirInterfaceCSVDir, "pucch_trials.csv")); ...
    struct("TraceSource", "srs_trials", "Direction", "UL", "Path", fullfile(layout.AirInterfaceCSVDir, "srs_trials.csv")); ...
    struct("TraceSource", "trs_trials", "Direction", "DL", "Path", fullfile(layout.AirInterfaceCSVDir, "trs_trials.csv"))];
parts = {};
for i = 1:numel(spec)
    Tsrc = localReadOptionalTable(spec(i).Path);
    if istable(Tsrc) && ~isempty(Tsrc)
        parts{end+1, 1} = localNormalizeRadioTrace(Tsrc, spec(i).TraceSource, spec(i).Direction, spec(i).Path, layout.Root, baseStationID); %#ok<AGROW>
    end
end
if isempty(parts)
    T = localEmptyRadioLinkTimelineTable();
else
    T = vertcat(parts{:});
end
end

function T = localBuildParallelTaskExecution(layout, baseStationID)
path = fullfile(layout.AirInterfaceCSVDir, "parallel_task_trace.csv");
Tin = localReadOptionalTable(path);
if ~(istable(Tin) && ~isempty(Tin))
    T = localEmptyParallelTaskExecutionTable();
    return;
end
n = height(Tin);
T = table( ...
    localNumericColumn(Tin, "TaskIndex", NaN(n,1)), ...
    localStringColumn(Tin, "Direction", strings(n,1)), ...
    localNumericColumn(Tin, "SNR_dB", NaN(n,1)), ...
    localNumericColumn(Tin, "UEIndex", NaN(n,1)), ...
    localNumericColumn(Tin, "RNTI", NaN(n,1)), ...
    localNumericColumn(Tin, "BaseStationID", repmat(baseStationID, n, 1)), ...
    localStringColumn(Tin, "ParallelPoolType", strings(n,1)), ...
    localStringColumn(Tin, "ExecutionModel", strings(n,1)), ...
    localNumericColumn(Tin, "WorkerID", NaN(n,1)), ...
    localNumericColumn(Tin, "TrialCount", NaN(n,1)), ...
    localNumericColumn(Tin, "FrameStart", NaN(n,1)), ...
    localNumericColumn(Tin, "FrameEnd", NaN(n,1)), ...
    localNumericColumn(Tin, "SlotStart", NaN(n,1)), ...
    localNumericColumn(Tin, "SlotEnd", NaN(n,1)), ...
    localNumericColumn(Tin, "PRBCountMean", NaN(n,1)), ...
    localStringColumn(Tin, "StartedUTC", strings(n,1)), ...
    localStringColumn(Tin, "CompletedUTC", strings(n,1)), ...
    localNumericColumn(Tin, "Elapsed_s", NaN(n,1)), ...
    double(localLogicalColumn(Tin, "Ok", false(n,1))), ...
    repmat(string(localRelativeRunPath(layout.Root, path)), n, 1), ...
    "VariableNames", {"TaskIndex","Direction","SNR_dB","UEID","RNTI","BaseStationID","ParallelPoolType", ...
    "ExecutionModel","WorkerID","TrialCount","FrameStart","FrameEnd","SlotStart","SlotEnd", ...
    "PRBCountMean","StartedUTC","CompletedUTC","Elapsed_s","Ok","SourceArtifact"});
end

function T = localBuildControlPlaneTrace(layout, baseStationID)
spec = [ ...
    struct("TraceSource", "attach_state_trace", "Path", fullfile(layout.ControlCSVDir, "attach_state_trace.csv")); ...
    struct("TraceSource", "rrc_message_trace", "Path", fullfile(layout.ControlCSVDir, "rrc_message_trace.csv"))];
parts = {};
for i = 1:numel(spec)
    Tin = localReadOptionalTable(spec(i).Path);
    if ~(istable(Tin) && ~isempty(Tin))
        continue;
    end
    n = height(Tin);
    frame = NaN(n,1);
    slot = localNumericColumn(Tin, "Slot", NaN(n,1));
    parts{end+1, 1} = table( ... %#ok<AGROW>
        repmat(string(spec(i).TraceSource), n, 1), ...
        localDeriveSFN(frame, slot), ...
        frame, ...
        slot, ...
        localNumericColumn(Tin, "UE", NaN(n,1)), ...
        localNumericColumn(Tin, "CellID", repmat(baseStationID, n, 1)), ...
        localStringColumn(Tin, "Direction", strings(n,1)), ...
        localStringColumn(Tin, "Event", strings(n,1)), ...
        localStringColumn(Tin, "Message", strings(n,1)), ...
        localStringColumn(Tin, "State", strings(n,1)), ...
        double(localLogicalColumn(Tin, "Success", false(n,1))), ...
        localStringColumn(Tin, "Cause", strings(n,1)), ...
        repmat(string(localRelativeRunPath(layout.Root, spec(i).Path)), n, 1), ...
        "VariableNames", {"TraceSource","SFN","Frame","Slot","UEID","BaseStationID","Direction","Event", ...
        "Message","State","Success","Cause","SourceArtifact"});
    end
if isempty(parts)
    T = localEmptyControlPlaneTraceTable();
else
    T = vertcat(parts{:});
end
end

function T = localBuildBeamTrace(layout, baseStationID)
spec = [ ...
    struct("TraceSource", "probe_beam_mimo", "Path", fullfile(layout.BeamformingCSVDir, "probe_beam_mimo.csv")); ...
    struct("TraceSource", "beam_score_trace", "Path", fullfile(layout.BeamformingCSVDir, "beam_score_trace.csv"))];
parts = {};
for i = 1:numel(spec)
    Tin = localReadOptionalTable(spec(i).Path);
    if ~(istable(Tin) && ~isempty(Tin))
        continue;
    end
    n = height(Tin);
    frame = localNumericColumn(Tin, "Frame", NaN(n,1));
    slot = localNumericColumn(Tin, "Slot", frame);
    parts{end+1, 1} = table( ... %#ok<AGROW>
        repmat(string(spec(i).TraceSource), n, 1), ...
        localDeriveSFN(frame, slot), ...
        frame, ...
        slot, ...
        localFirstNumericColumn(Tin, ["UEIndex","UE"], NaN(n,1)), ...
        localNumericColumn(Tin, "RNTI", NaN(n,1)), ...
        localNumericColumn(Tin, "CellID", repmat(baseStationID, n, 1)), ...
        localNumericColumn(Tin, "SelectedBeamIndex", NaN(n,1)), ...
        localNumericColumn(Tin, "BestBeamIndex", NaN(n,1)), ...
        localNumericColumn(Tin, "BeamGainGap_dB", NaN(n,1)), ...
        localStringColumn(Tin, "PrecoderSource", strings(n,1)), ...
        double(localLogicalColumn(Tin, "BeamformingApplied", false(n,1))), ...
        localStringColumn(Tin, "ExecutionModel", strings(n,1)), ...
        repmat(string(localRelativeRunPath(layout.Root, spec(i).Path)), n, 1), ...
        "VariableNames", {"TraceSource","SFN","Frame","Slot","UEID","RNTI","BaseStationID","SelectedBeamIndex", ...
        "BestBeamIndex","BeamGainGap_dB","PrecoderSource","BeamformingApplied","ExecutionModel","SourceArtifact"});
end
if isempty(parts)
    T = localEmptyBeamTraceTable();
else
    T = vertcat(parts{:});
end
end

function T = localBuildHARQPacketTrace(layout, baseStationID)
path = fullfile(layout.HARQCSVDir, "probe_harq_packets.csv");
Tin = localReadOptionalTable(path);
if ~(istable(Tin) && ~isempty(Tin))
    T = localEmptyHARQPacketTraceTable();
    return;
end
n = height(Tin);
frame = localNumericColumn(Tin, "Frame", NaN(n,1));
slot = localNumericColumn(Tin, "Slot", NaN(n,1));
T = table( ...
    repmat("probe_harq_packets", n, 1), ...
    localStringColumn(Tin, "Direction", strings(n,1)), ...
    localDeriveSFN(frame, slot), ...
    frame, ...
    slot, ...
    localFirstNumericColumn(Tin, ["UEIndex","UE"], NaN(n,1)), ...
    localNumericColumn(Tin, "RNTI", NaN(n,1)), ...
    repmat(baseStationID, n, 1), ...
    localNumericColumn(Tin, "HARQProcess", NaN(n,1)), ...
    localNumericColumn(Tin, "RV", NaN(n,1)), ...
    localNumericColumn(Tin, "RTT_slots", NaN(n,1)), ...
    localNumericColumn(Tin, "TBSize_bits", NaN(n,1)), ...
    localStringColumn(Tin, "StopCondition", strings(n,1)), ...
    localStringColumn(Tin, "Mode", strings(n,1)), ...
    repmat(string(localRelativeRunPath(layout.Root, path)), n, 1), ...
    "VariableNames", {"TraceSource","Direction","SFN","Frame","Slot","UEID","RNTI","BaseStationID","HARQProcess", ...
    "RV","RTT_slots","TBSize_bits","StopCondition","Mode","SourceArtifact"});
end

function T = localBuildEnergyTrace(layout, baseStationID)
path = fullfile(layout.RFCSVDir, "energy_timeline_trace.csv");
Tin = localReadOptionalTable(path);
if ~(istable(Tin) && ~isempty(Tin))
    T = localEmptyEnergyTraceTable();
    return;
end
n = height(Tin);
frame = localNumericColumn(Tin, "Frame", NaN(n,1));
slot = localNumericColumn(Tin, "Slot", frame);
T = table( ...
    repmat("energy_timeline_trace", n, 1), ...
    localStringColumn(Tin, "Direction", strings(n,1)), ...
    localDeriveSFN(frame, slot), ...
    frame, ...
    slot, ...
    localFirstNumericColumn(Tin, ["UEIndex","UE"], NaN(n,1)), ...
    repmat(baseStationID, n, 1), ...
    localNumericColumn(Tin, "Power_W", NaN(n,1)), ...
    localNumericColumn(Tin, "Energy_J", NaN(n,1)), ...
    localNumericColumn(Tin, "PRBs", NaN(n,1)), ...
    localStringColumn(Tin, "Entity", strings(n,1)), ...
    localStringColumn(Tin, "Domain", strings(n,1)), ...
    repmat(string(localRelativeRunPath(layout.Root, path)), n, 1), ...
    "VariableNames", {"TraceSource","Direction","SFN","Frame","Slot","UEID","BaseStationID","Power_W", ...
    "Energy_J","PRBCount","Entity","Domain","SourceArtifact"});
end

function T = localNormalizeRadioTrace(Tin, traceSource, defaultDirection, sourceArtifact, runRoot, baseStationID)
n = height(Tin);
frame = localNumericColumn(Tin, "Frame", NaN(n,1));
slot = localNumericColumn(Tin, "Slot", frame);
T = table( ...
    repmat(string(traceSource), n, 1), ...
    localStringColumn(Tin, "Direction", repmat(string(defaultDirection), n, 1)), ...
    localDeriveSFN(frame, slot), ...
    frame, ...
    slot, ...
    localFirstNumericColumn(Tin, ["UEIndex","UE"], NaN(n,1)), ...
    localNumericColumn(Tin, "RNTI", NaN(n,1)), ...
    localNumericColumn(Tin, "CellID", repmat(baseStationID, n, 1)), ...
    localFirstNumericColumn(Tin, ["PRBs","PRBCount"], NaN(n,1)), ...
    localNumericColumn(Tin, "PRBStart", NaN(n,1)), ...
    localNumericColumn(Tin, "MCS", NaN(n,1)), ...
    localNumericColumn(Tin, "Layers", NaN(n,1)), ...
    localNumericColumn(Tin, "SNR_dB", NaN(n,1)), ...
    localNumericColumn(Tin, "MeasuredSINR_dB", NaN(n,1)), ...
    localNumericColumn(Tin, "TBSize_bits", NaN(n,1)), ...
    localStringColumn(Tin, "ExecutionModel", strings(n,1)), ...
    localStringColumn(Tin, "Status", strings(n,1)), ...
    localStringColumn(Tin, "Notes", strings(n,1)), ...
    repmat(string(localRelativeRunPath(runRoot, sourceArtifact)), n, 1), ...
    "VariableNames", {"TraceSource","Direction","SFN","Frame","Slot","UEID","RNTI","BaseStationID","PRBCount", ...
    "PRBStart","MCS","Layers","SNR_dB","MeasuredSINR_dB","TBSize_bits","ExecutionModel", ...
    "Status","Notes","SourceArtifact"});
end

function out = localRelativeRunPath(runFolder, pathIn)
runFolder = char(string(runFolder));
pathIn = char(string(pathIn));
try
    out = erase(string(pathIn), string(runFolder) + filesep);
catch
    out = string(pathIn);
end
out = char(string(out));
end

function id = localConfiguredBaseStationID(cfg)
id = double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", sixgr.util.structGet(cfg, "phy.NCellID", 1)));
if ~isfinite(id)
    id = 1;
end
end

function sfn = localDeriveSFN(frame, slot)
if nargin < 2
    slot = [];
end
frame = double(frame);
sfn = NaN(size(frame));
mask = isfinite(frame);
if any(mask)
    sfn(mask) = mod(round(frame(mask)) - 1, 1024);
end
slot = double(slot);
mask = ~isfinite(sfn) & isfinite(slot);
if any(mask)
    sfn(mask) = mod(floor(max(slot(mask) - 1, 0) / 10), 1024);
end
end

function T = localReadOptionalTable(pathIn)
T = table();
pathIn = char(string(pathIn));
if exist(pathIn, "file") ~= 2
    return;
end
try
    T = readtable(pathIn, "VariableNamingRule", "preserve");
catch
    T = table();
end
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

function v = localFirstNumericColumn(T, names, fallback)
for i = 1:numel(names)
    name = char(string(names(i)));
    if ismember(name, T.Properties.VariableNames)
        try
            v = double(T.(name));
            return;
        catch
        end
    end
end
v = double(fallback);
end

function localCreateIndexes(conn, tableName)
tableName = char(string(tableName));
switch tableName
    case "radio_link_timeline"
        localExecuteSQL(conn, "CREATE INDEX IF NOT EXISTS idx_radio_link_key ON radio_link_timeline (BaseStationID, UEID, SFN, Slot)");
        localExecuteSQL(conn, "CREATE INDEX IF NOT EXISTS idx_radio_link_direction ON radio_link_timeline (Direction, SFN, Slot)");
    case "parallel_task_execution"
        localExecuteSQL(conn, "CREATE INDEX IF NOT EXISTS idx_parallel_task_key ON parallel_task_execution (UEID, Direction, SNR_dB)");
    case "control_plane_trace"
        localExecuteSQL(conn, "CREATE INDEX IF NOT EXISTS idx_control_trace_key ON control_plane_trace (UEID, BaseStationID, SFN, Slot)");
    case "beam_trace"
        localExecuteSQL(conn, "CREATE INDEX IF NOT EXISTS idx_beam_trace_key ON beam_trace (UEID, BaseStationID, SFN, Slot)");
    case "harq_packet_trace"
        localExecuteSQL(conn, "CREATE INDEX IF NOT EXISTS idx_harq_trace_key ON harq_packet_trace (UEID, BaseStationID, SFN, Slot)");
    case "energy_trace"
        localExecuteSQL(conn, "CREATE INDEX IF NOT EXISTS idx_energy_trace_key ON energy_trace (BaseStationID, SFN, Slot)");
end
end

function localExecuteSQL(conn, sqlText)
if isempty(conn)
    return;
end
try
    execute(conn, sqlText);
catch
    try
        exec(conn, sqlText);
    catch
    end
end
end

function localCloseSQLite(conn)
if isempty(conn)
    return;
end
try
    close(conn);
catch
end
end

function name = localTableNameToken(nameIn)
name = lower(regexprep(char(string(nameIn)), "([a-z])([A-Z])", "$1_$2"));
end

function localWriteDatabaseManifest(out, tableBundle)
manifest = struct();
manifest.GeneratedUTC = char(string(localUTCStamp()));
manifest.Status = char(string(out.Status));
manifest.Ok = logical(out.Ok);
manifest.DBPath = char(string(out.RelativeDBPath));
manifest.TablesWritten = out.TablesWritten;
manifest.Warnings = cellstr(string(out.Warnings(:)));
tableNames = fieldnames(tableBundle);
manifest.TableRowCounts = struct();
for i = 1:numel(tableNames)
    T = tableBundle.(tableNames{i});
    manifest.TableRowCounts.(tableNames{i}) = double(height(T));
end
sixgr.util.jsonWrite(out.ManifestPath, manifest);
end

function stamp = localUTCStamp()
stamp = datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
end

function T = localEmptyRadioLinkTimelineTable()
T = table(strings(0,1), strings(0,1), NaN(0,1), NaN(0,1), NaN(0,1), NaN(0,1), NaN(0,1), NaN(0,1), ...
    NaN(0,1), NaN(0,1), NaN(0,1), NaN(0,1), NaN(0,1), NaN(0,1), NaN(0,1), strings(0,1), ...
    strings(0,1), strings(0,1), strings(0,1), ...
    "VariableNames", {"TraceSource","Direction","SFN","Frame","Slot","UEID","RNTI","BaseStationID", ...
    "PRBCount","PRBStart","MCS","Layers","SNR_dB","MeasuredSINR_dB","TBSize_bits","ExecutionModel", ...
    "Status","Notes","SourceArtifact"});
end

function T = localEmptyParallelTaskExecutionTable()
T = table(NaN(0,1), strings(0,1), NaN(0,1), NaN(0,1), NaN(0,1), NaN(0,1), strings(0,1), strings(0,1), ...
    NaN(0,1), NaN(0,1), NaN(0,1), NaN(0,1), NaN(0,1), NaN(0,1), NaN(0,1), strings(0,1), strings(0,1), ...
    NaN(0,1), NaN(0,1), strings(0,1), ...
    "VariableNames", {"TaskIndex","Direction","SNR_dB","UEID","RNTI","BaseStationID","ParallelPoolType", ...
    "ExecutionModel","WorkerID","TrialCount","FrameStart","FrameEnd","SlotStart","SlotEnd", ...
    "PRBCountMean","StartedUTC","CompletedUTC","Elapsed_s","Ok","SourceArtifact"});
end

function T = localEmptyControlPlaneTraceTable()
T = table(strings(0,1), NaN(0,1), NaN(0,1), NaN(0,1), NaN(0,1), NaN(0,1), strings(0,1), ...
    strings(0,1), strings(0,1), strings(0,1), NaN(0,1), strings(0,1), strings(0,1), ...
    "VariableNames", {"TraceSource","SFN","Frame","Slot","UEID","BaseStationID","Direction","Event", ...
    "Message","State","Success","Cause","SourceArtifact"});
end

function T = localEmptyBeamTraceTable()
T = table("Size", [0, 14], ...
    "VariableTypes", {"string","double","double","double","double","double","double","double", ...
    "double","double","string","double","string","string"}, ...
    "VariableNames", {"TraceSource","SFN","Frame","Slot","UEID","RNTI","BaseStationID","SelectedBeamIndex", ...
    "BestBeamIndex","BeamGainGap_dB","PrecoderSource","BeamformingApplied","ExecutionModel","SourceArtifact"});
end

function T = localEmptyHARQPacketTraceTable()
T = table("Size", [0, 15], ...
    "VariableTypes", {"string","string","double","double","double","double","double","double", ...
    "double","double","double","double","string","string","string"}, ...
    "VariableNames", {"TraceSource","Direction","SFN","Frame","Slot","UEID","RNTI","BaseStationID","HARQProcess", ...
    "RV","RTT_slots","TBSize_bits","StopCondition","Mode","SourceArtifact"});
end

function T = localEmptyEnergyTraceTable()
T = table("Size", [0, 13], ...
    "VariableTypes", {"string","string","double","double","double","double","double","double", ...
    "double","double","string","string","string"}, ...
    "VariableNames", {"TraceSource","Direction","SFN","Frame","Slot","UEID","BaseStationID","Power_W", ...
    "Energy_J","PRBCount","Entity","Domain","SourceArtifact"});
end
