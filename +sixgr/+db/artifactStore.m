function varargout = artifactStore(action, varargin)
%ARTIFACTSTORE Run-scoped MySQL-backed artifact sink.

persistent state
if isempty(state)
    state = localEmptyState();
end

action = lower(string(action));
switch action
    case "activate"
        [state, out] = localActivate(state, varargin{:});
        varargout{1} = out;
    case "deactivate"
        state = localDeactivate(state);
    case "is_active"
        varargout{1} = localIsActive(state);
    case "store_table"
        varargout{1} = localStoreTable(state, varargin{:});
    case "store_text"
        varargout{1} = localStoreText(state, varargin{:});
    case "store_binary"
        varargout{1} = localStoreBinary(state, varargin{:});
    case "capture_file"
        varargout{1} = localCaptureFile(state, varargin{:});
    case "hydrate_display_folder"
        varargout{1} = localHydrateDisplayFolder(state, varargin{:});
    case "append_log"
        localAppendLog(state, varargin{:});
    case "mark_status"
        localMarkStatus(state, varargin{:});
    case "get_state"
        varargout{1} = state;
    otherwise
        error("sixgr:db:artifactStore:UnknownAction", ...
            "Unsupported artifact-store action '%s'.", action);
end

end

function out = localHydrateDisplayFolder(state, targetRoot)
out = struct( ...
    "Ok", false, ...
    "RunID", NaN, ...
    "TargetRoot", "", ...
    "FileCount", 0, ...
    "ByteCount", 0, ...
    "SkippedCount", 0, ...
    "Notes", "");
if ~localIsActive(state)
    out.Notes = "artifact_store_inactive";
    return;
end
if nargin < 2 || strlength(strtrim(string(targetRoot))) == 0
    targetRoot = state.DisplayRunFolder;
end
targetRoot = char(string(targetRoot));
out.RunID = double(state.RunID);
out.TargetRoot = string(targetRoot);
if strlength(strtrim(string(targetRoot))) == 0
    out.Notes = "display_run_folder_unavailable";
    return;
end

sixgr.util.ensureFolder(targetRoot);
conn = state.Connection;
ps = conn.prepareStatement([ ...
    "SELECT artifact_id, logical_path, byte_size FROM sim_artifacts " + ...
    "WHERE run_id=? ORDER BY artifact_id ASC"]);
cleanupPS = onCleanup(@() ps.close()); %#ok<NASGU>
ps.setLong(1, int64(state.RunID));
rs = ps.executeQuery();
cleanupRS = onCleanup(@() rs.close()); %#ok<NASGU>
psChunk = conn.prepareStatement([ ...
    "SELECT chunk_data FROM sim_artifact_chunks " + ...
    "WHERE artifact_id=? ORDER BY chunk_index ASC"]);
cleanupChunkPS = onCleanup(@() psChunk.close()); %#ok<NASGU>

while rs.next()
    artifactID = double(rs.getLong(1));
    logicalPath = char(string(rs.getString(2)));
    [targetPath, okTarget] = localHydrationTargetPath(targetRoot, logicalPath);
    if ~okTarget
        out.SkippedCount = out.SkippedCount + 1;
        continue;
    end
    sixgr.util.ensureDir(targetPath);
    fid = fopen(targetPath, "wb");
    if fid < 0
        out.SkippedCount = out.SkippedCount + 1;
        continue;
    end
    cleanupFID = onCleanup(@() fclose(fid)); %#ok<NASGU>
    psChunk.setLong(1, int64(artifactID));
    rsChunk = psChunk.executeQuery();
    cleanupChunkRS = onCleanup(@() rsChunk.close()); %#ok<NASGU>
    writtenBytes = 0;
    while rsChunk.next()
        chunkBytes = localBytesFromJava(rsChunk.getBytes(1));
        if ~isempty(chunkBytes)
            writtenBytes = writtenBytes + double(fwrite(fid, chunkBytes, "uint8"));
        end
    end
    clear cleanupChunkRS cleanupFID
    out.FileCount = out.FileCount + 1;
    if isfinite(writtenBytes)
        out.ByteCount = out.ByteCount + double(writtenBytes);
    end
end
out.Ok = true;
out.Notes = "hydrated_mysql_artifacts_to_display_run_folder";
end

function state = localEmptyState()
state = struct( ...
    "Active", false, ...
    "Backend", "", ...
    "RunFolder", "", ...
    "DisplayRunFolder", "", ...
    "RunID", NaN, ...
    "RunUUID", "", ...
    "DatabaseHost", "", ...
    "DatabasePort", NaN, ...
    "DatabaseSchema", "", ...
    "MaxAllowedPacketBytes", NaN, ...
    "Connection", [], ...
    "LogSequence", 0);
end

function tf = localIsActive(state)
tf = isstruct(state) && logical(sixgr.util.structGet(state, "Active", false)) && ...
    ~isempty(sixgr.util.structGet(state, "Connection", []));
end

function [state, out] = localActivate(state, runFolder, cfg, meta)
if nargin < 4 || ~isstruct(meta)
    meta = struct();
end

state = localDeactivate(state);
backend = lower(string(sixgr.util.structGet(cfg, "outputs.storageBackend", "filesystem")));
if backend ~= "mysql_web"
    out = struct("Active", false, "Backend", backend);
    return;
end

host = char(string(sixgr.util.structGet(cfg, "outputs.databaseHost", "localhost")));
port = double(sixgr.util.structGet(cfg, "outputs.databasePort", 3306));
schemaName = char(string(sixgr.util.structGet(cfg, "outputs.databaseSchema", "sixgr_results")));
username = localEnvOrDefault("MYSQL_USER", "root");
password = localEnvOrDefault("MYSQL_PASSWORD", "root");

adminConn = [];
conn = [];
try
    adminConn = sixgr.util.connectMySQLJDBC( ...
        Host=host, Port=port, Database="", Username=username, Password=password);
    localExec(adminConn, "CREATE DATABASE IF NOT EXISTS `" + localEscapeIdentifier(schemaName) + ...
        "` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
    adminConn.close();
    adminConn = [];

    conn = sixgr.util.connectMySQLJDBC( ...
        Host=host, Port=port, Database=schemaName, Username=username, Password=password);
    localEnsureSchema(conn);

    state = localEmptyState();
    state.Active = true;
    state.Backend = char(backend);
    state.RunFolder = char(string(runFolder));
    state.DisplayRunFolder = char(string(sixgr.util.structGet(meta, "LogicalRunFolder", runFolder)));
    state.DatabaseHost = host;
    state.DatabasePort = port;
    state.DatabaseSchema = schemaName;
    state.Connection = conn;
    state.MaxAllowedPacketBytes = localQueryMaxAllowedPacket(conn);
    state.RunUUID = char(javaMethod("randomUUID", "java.util.UUID").toString());
    existingRunID = double(sixgr.util.structGet(meta, "ExistingRunID", NaN));
    [hasExistingRun, existingRunUUID] = localLookupExistingRun(conn, existingRunID);
    if hasExistingRun
        state.RunID = existingRunID;
        if strlength(strtrim(existingRunUUID)) > 0
            state.RunUUID = char(existingRunUUID);
        end
        localRefreshExistingRunRow(conn, state, cfg, meta);
    else
        state.RunID = localInsertRunRow(conn, state, cfg, meta);
    end

    out = struct( ...
        "Active", true, ...
        "Backend", state.Backend, ...
        "RunID", state.RunID, ...
        "RunUUID", string(state.RunUUID), ...
        "DatabaseSchema", string(state.DatabaseSchema));
catch ME
    try
        if ~isempty(adminConn)
            adminConn.close();
        end
    catch
    end
    try
        if ~isempty(conn)
            conn.close();
        end
    catch
    end
    state = localEmptyState();
    error("sixgr:db:artifactStore:ActivateFailed", ...
        "Failed to activate the MySQL artifact store: %s", ME.message);
end
end

function state = localDeactivate(state)
if ~localIsActive(state)
    state = localEmptyState();
    return;
end
try
    state.Connection.close();
catch
end
state = localEmptyState();
end

function handled = localStoreTable(state, filePath, T)
handled = false;
if ~localIsActive(state)
    return;
end

tmpPath = char(string(tempname) + ".csv");
cleanupObj = onCleanup(@() localDeleteIfExists(tmpPath)); %#ok<NASGU>
try
    sixgr.util.ensureDir(tmpPath);
    try
        writetable(T, tmpPath, "Delimiter", ",", "QuoteStrings", true);
    catch
        writetable(T, tmpPath);
    end
    bytes = localReadFileBytes(tmpPath);
    metadata = struct( ...
        "row_count", height(T), ...
        "column_names", {cellstr(string(T.Properties.VariableNames(:)).')}, ...
        "variable_count", width(T), ...
        "source_path", char(string(filePath)));
    handled = localStoreBinary(state, char(string(filePath)), bytes, ...
        "table_csv", "text/csv; charset=UTF-8", metadata);
catch ME
    error("sixgr:db:artifactStore:StoreTableFailed", ...
        "Failed to store table artifact '%s' in MySQL: %s", string(filePath), ME.message);
end
end

function handled = localStoreText(state, filePath, txt, mimeType, artifactKind, metadata)
handled = false;
if ~localIsActive(state)
    return;
end
if nargin < 4 || strlength(string(mimeType)) == 0
    mimeType = "text/plain; charset=UTF-8";
end
if nargin < 5 || strlength(string(artifactKind)) == 0
    artifactKind = "text";
end
if nargin < 6 || ~isstruct(metadata)
    metadata = struct();
end
bytes = uint8(unicode2native(char(string(txt)), "UTF-8"));
handled = localStoreBinary(state, filePath, bytes, artifactKind, mimeType, metadata);
end

function handled = localStoreBinary(state, filePath, bytes, artifactKind, mimeType, metadata)
handled = false;
if ~localIsActive(state)
    return;
end
if nargin < 6 || ~isstruct(metadata)
    metadata = struct();
end

conn = state.Connection;
logicalPath = localLogicalPath(filePath, state.RunFolder);
bytes = uint8(bytes(:).');
metadata.source_path = string(filePath);
metadata.logical_path = string(logicalPath);
metadata_json = localJSON(metadata);

oldId = localFindArtifactID(conn, state.RunID, logicalPath);
prevAutoCommit = [];
try
    prevAutoCommit = conn.getAutoCommit();
catch
end
cleanupAuto = onCleanup(@() localRestoreAutoCommit(conn, prevAutoCommit)); %#ok<NASGU>
try
    if isempty(prevAutoCommit) || logical(prevAutoCommit)
        conn.setAutoCommit(false);
    end

    if isfinite(oldId)
        localDeleteArtifact(conn, oldId);
    end

    ps = conn.prepareStatement([ ...
        "INSERT INTO sim_artifacts " + ...
        "(run_id, logical_path, artifact_kind, mime_type, byte_size, metadata_json, created_utc) " + ...
        "VALUES (?, ?, ?, ?, ?, ?, UTC_TIMESTAMP())"]);
    cleanupInsert = onCleanup(@() ps.close()); %#ok<NASGU>
    ps.setLong(1, int64(state.RunID));
    ps.setString(2, char(logicalPath));
    ps.setString(3, char(string(artifactKind)));
    ps.setString(4, char(string(mimeType)));
    ps.setLong(5, int64(numel(bytes)));
    ps.setString(6, char(metadata_json));
    ps.executeUpdate();
    artifactID = localLastInsertID(conn);
    clear cleanupInsert

    [chunkSize, chunkBatchSize] = localResolveChunkPlan(state, bytes, artifactKind, mimeType);
    if ~isempty(bytes)
        psChunk = conn.prepareStatement([ ...
            "INSERT INTO sim_artifact_chunks (artifact_id, chunk_index, chunk_data) " + ...
            "VALUES (?, ?, ?)"]);
        cleanupChunk = onCleanup(@() psChunk.close()); %#ok<NASGU>
        chunkIndex = 1;
        queued = 0;
        for idx = 1:chunkSize:numel(bytes)
            chunk = bytes(idx:min(idx + chunkSize - 1, numel(bytes)));
            psChunk.setLong(1, int64(artifactID));
            psChunk.setInt(2, int32(chunkIndex));
            psChunk.setBytes(3, localJavaBytes(chunk));
            if chunkBatchSize <= 1
                psChunk.executeUpdate();
            else
                psChunk.addBatch();
                queued = queued + 1;
                if queued >= chunkBatchSize
                    psChunk.executeBatch();
                    queued = 0;
                end
            end
            chunkIndex = chunkIndex + 1;
        end
        if chunkBatchSize > 1 && queued > 0
            psChunk.executeBatch();
        end
    end

    localTouchRun(conn, state.RunID);
    conn.commit();
    handled = true;
catch ME
    try
        conn.rollback();
    catch
    end
    rethrow(ME);
end
end

function handled = localCaptureFile(state, filePath, artifactKind, mimeType, deleteAfter, logicalPath)
handled = false;
if nargin < 5
    deleteAfter = true;
end
if nargin < 6 || strlength(string(logicalPath)) == 0
    logicalPath = filePath;
end
if ~localIsActive(state) || exist(filePath, "file") ~= 2
    return;
end
bytes = localReadFileBytes(filePath);
metadata = struct("captured_from_file", true);
sourceRefs = localInferImageSourceArtifacts(logicalPath);
if strlength(sourceRefs) > 0
    metadata.source_artifact_ref = sourceRefs;
    metadata.source_logical_path = sourceRefs;
    metadata.provenance_rule = "captured_image_companion_source_artifact";
end
handled = localStoreBinary(state, logicalPath, bytes, artifactKind, mimeType, metadata);
if handled && logical(deleteAfter)
    localDeleteIfExists(filePath);
end
end

function sourceRefs = localInferImageSourceArtifacts(logicalPath)
sourceRefs = "";
lp = replace(string(logicalPath), "\", "/");
if strlength(strtrim(lp)) == 0
    return;
end
[folderPath, stem, ext] = fileparts(lp);
ext = lower(string(ext));
if ~ismember(ext, [".png", ".svg", ".html", ".htm"])
    return;
end

folderPath = replace(string(folderPath), "\", "/");
stem = string(stem);
explicitRef = localExplicitImageSourceRef(folderPath, stem);
if strlength(explicitRef) > 0
    sourceRefs = explicitRef;
    return;
end
if contains(folderPath, "/image")
    csvFolder = replace(folderPath, "/image", "/csv");
    sourceRefs = localNormalizeSourceRef(csvFolder + "/" + stem + ".csv");
    return;
end
if endsWith(folderPath, "image")
    csvFolder = extractBefore(folderPath, strlength(folderPath) - strlength("image") + 1) + "csv";
    sourceRefs = localNormalizeSourceRef(csvFolder + "/" + stem + ".csv");
    return;
end
if contains(folderPath, "reports/image")
    sourceRefs = localNormalizeSourceRef("reports/csv/" + stem + ".csv");
    return;
end
if contains(folderPath, "analytics/image")
    sourceRefs = localNormalizeSourceRef("analytics/csv/" + stem + ".csv");
end
end

function ref = localExplicitImageSourceRef(folderPath, stem)
ref = "";
folderPath = string(folderPath);
stem = string(stem);
if endsWith(folderPath, "beamforming/image") && ismember(stem, ["beam_channel_sinr", "beam_condition_number", "beam_gain_gap"])
    ref = "beamforming/csv/probe_beam_mimo.csv";
    return;
end
if endsWith(folderPath, "air_interface/image")
    switch stem
        case {"dl_trial_sinr", "dl_trial_channel_gain", "dl_posteq_sinr_by_trial_scatter", "dl_channel_gain_distribution"}
            ref = "air_interface/csv/dl_pdsch_trials.csv";
        case "dl_constellation_scatter"
            ref = "air_interface/csv/dl_constellation_preview.csv";
        case {"ul_trial_sinr", "ul_trial_channel_gain", "ul_posteq_sinr_by_trial_scatter", "ul_channel_gain_distribution"}
            ref = "air_interface/csv/ul_pusch_trials.csv";
        case "ul_constellation_scatter"
            ref = "air_interface/csv/ul_constellation_preview.csv";
        case {"link_truth_validation_bler", "link_truth_validation_ber", "link_truth_validation_throughput"}
            ref = "air_interface/csv/live_link_snr_sweep.csv|air_interface/csv/link_kpis.csv";
        case "link_truth_validation_papr"
            ref = "air_interface/csv/link_kpis.csv";
    end
    return;
end
if endsWith(folderPath, "reports/image")
    switch stem
        case "gains_losses_waterfall"
            ref = "reports/csv/per_scenario_summary_tables.csv";
        case "papr_ccdf"
            ref = "reports/csv/papr_ccdf.csv";
        case "latency_cdf"
            ref = "reports/csv/table_latency.csv";
        case "energy_vs_throughput"
            ref = "reports/csv/energy_vs_throughput.csv";
        case "complexity_vs_gain"
            ref = "reports/csv/complexity_vs_gain.csv";
        case "control_pass_rates"
            ref = "reports/csv/control_pass_rates.csv";
        case "metric_coverage_by_category"
            ref = "reports/csv/metric_coverage_by_category.csv";
        case "bler_vs_snr"
            ref = "air_interface/csv/lls_snr_sweep.csv";
        case "throughput_vs_snr"
            ref = "air_interface/csv/lls_snr_sweep.csv";
        case "bler_vs_measured_posteq_sinr_bins_diagnostic"
            ref = "reports/csv/bler_vs_measured_posteq_sinr_bins_diagnostic.csv";
        case {"heatmap_band_feature_kpi", "heatmap_beam_rank_trp_kpi", "heatmap_impairment_kpi"}
            ref = "reports/csv/heatmap_band_feature_kpi.csv|reports/csv/heatmap_beam_rank_trp_kpi.csv|reports/csv/heatmap_impairment_kpi.csv";
    end
end
end

function ref = localNormalizeSourceRef(ref)
ref = replace(string(ref), "\", "/");
ref = regexprep(ref, "/+", "/");
ref = regexprep(ref, "^./", "");
end

function localAppendLog(state, levelStr, timeStr, msgStr)
if ~localIsActive(state)
    return;
end
conn = state.Connection;
ps = conn.prepareStatement([ ...
    "INSERT INTO sim_run_logs (run_id, level_str, time_str, message_text, created_utc) " + ...
    "VALUES (?, ?, ?, ?, UTC_TIMESTAMP())"]);
cleanupObj = onCleanup(@() ps.close()); %#ok<NASGU>
ps.setLong(1, int64(state.RunID));
ps.setString(2, char(string(levelStr)));
ps.setString(3, char(string(timeStr)));
ps.setString(4, char(string(msgStr)));
ps.executeUpdate();
localTouchRun(conn, state.RunID);
end

function localMarkStatus(state, statusText, statusPayload)
if ~localIsActive(state)
    return;
end
if nargin < 3 || ~isstruct(statusPayload)
    statusPayload = struct();
end
ps = state.Connection.prepareStatement([ ...
    "UPDATE sim_runs SET status_text=?, status_json=?, updated_utc=UTC_TIMESTAMP() " + ...
    "WHERE run_id=?"]);
cleanupObj = onCleanup(@() ps.close()); %#ok<NASGU>
ps.setString(1, char(string(statusText)));
ps.setString(2, char(localJSON(statusPayload)));
ps.setLong(3, int64(state.RunID));
ps.executeUpdate();
end

function localTouchRun(conn, runID)
ps = conn.prepareStatement( ...
    "UPDATE sim_runs SET updated_utc=UTC_TIMESTAMP() WHERE run_id=?");
cleanupObj = onCleanup(@() ps.close()); %#ok<NASGU>
ps.setLong(1, int64(runID));
ps.executeUpdate();
end

function localEnsureSchema(conn)
localExec(conn, [ ...
    "CREATE TABLE IF NOT EXISTS sim_runs (" + ...
    "run_id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY, " + ...
    "run_uuid VARCHAR(64) NOT NULL UNIQUE, " + ...
    "scenario_id VARCHAR(255) NULL, " + ...
    "run_tag VARCHAR(255) NULL, " + ...
    "run_folder VARCHAR(2048) NULL, " + ...
    "bucket VARCHAR(64) NULL, " + ...
    "profile_name VARCHAR(255) NULL, " + ...
    "backend VARCHAR(64) NULL, " + ...
    "status_text VARCHAR(64) NULL, " + ...
    "status_json LONGTEXT NULL, " + ...
    "config_json LONGTEXT NULL, " + ...
    "created_utc TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP, " + ...
    "updated_utc TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP" + ...
    ")"]);

localExec(conn, [ ...
    "CREATE TABLE IF NOT EXISTS sim_artifacts (" + ...
    "artifact_id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY, " + ...
    "run_id BIGINT NOT NULL, " + ...
    "logical_path VARCHAR(2048) NOT NULL, " + ...
    "artifact_kind VARCHAR(64) NOT NULL, " + ...
    "mime_type VARCHAR(255) NULL, " + ...
    "byte_size BIGINT NOT NULL DEFAULT 0, " + ...
    "metadata_json LONGTEXT NULL, " + ...
    "created_utc TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP, " + ...
    "INDEX idx_sim_artifacts_run_id (run_id), " + ...
    "INDEX idx_sim_artifacts_logical_path (logical_path(255))" + ...
    ")"]);

localExec(conn, [ ...
    "CREATE TABLE IF NOT EXISTS sim_artifact_chunks (" + ...
    "artifact_id BIGINT NOT NULL, " + ...
    "chunk_index INT NOT NULL, " + ...
    "chunk_data LONGBLOB NOT NULL, " + ...
    "PRIMARY KEY (artifact_id, chunk_index)" + ...
    ")"]);

localExec(conn, [ ...
    "CREATE TABLE IF NOT EXISTS sim_run_logs (" + ...
    "log_id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY, " + ...
    "run_id BIGINT NOT NULL, " + ...
    "level_str VARCHAR(16) NULL, " + ...
    "time_str VARCHAR(64) NULL, " + ...
    "message_text LONGTEXT NULL, " + ...
    "created_utc TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP, " + ...
    "INDEX idx_sim_run_logs_run_id (run_id)" + ...
    ")"]);

localCreateIndexIfMissing(conn, "sim_runs", "idx_sim_runs_run_tag", "(run_tag)");
localCreateIndexIfMissing(conn, "sim_runs", "idx_sim_runs_updated_utc", "(updated_utc)");
localCreateIndexIfMissing(conn, "sim_artifacts", "idx_sim_artifacts_run_artifact", "(run_id, artifact_id)");
localCreateIndexIfMissing(conn, "sim_artifacts", "idx_sim_artifacts_run_created", "(run_id, created_utc, artifact_id)");
localCreateIndexIfMissing(conn, "sim_artifacts", "idx_sim_artifacts_run_path", "(run_id, logical_path(512), artifact_id)");
localCreateIndexIfMissing(conn, "sim_run_logs", "idx_sim_run_logs_run_log", "(run_id, log_id)");
end

function runID = localInsertRunRow(conn, state, cfg, meta)
scenarioID = char(string(sixgr.util.structGet(meta, "ScenarioID", sixgr.util.structGet(cfg, "meta.lls6gScenarioID", ""))));
runTag = char(string(sixgr.util.structGet(meta, "RunTag", sixgr.util.structGet(cfg, "run.runTag", ""))));
bucket = char(string(sixgr.util.structGet(meta, "Bucket", sixgr.util.structGet(cfg, "run.mode", ""))));
profileName = char(string(sixgr.util.structGet(meta, "Profile", sixgr.util.structGet(cfg, "scenario.id", ""))));
configPayload = localBuildRunConfigPayload(cfg, meta);
ps = conn.prepareStatement([ ...
    "INSERT INTO sim_runs " + ...
    "(run_uuid, scenario_id, run_tag, run_folder, bucket, profile_name, backend, status_text, status_json, config_json, created_utc, updated_utc) " + ...
    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, UTC_TIMESTAMP(), UTC_TIMESTAMP())"]);
cleanupObj = onCleanup(@() ps.close()); %#ok<NASGU>
ps.setString(1, char(state.RunUUID));
ps.setString(2, scenarioID);
ps.setString(3, runTag);
ps.setString(4, char(string(state.DisplayRunFolder)));
ps.setString(5, bucket);
ps.setString(6, profileName);
ps.setString(7, char(string(state.Backend)));
ps.setString(8, "running");
ps.setString(9, "{}");
ps.setString(10, char(localJSON(configPayload)));
ps.executeUpdate();
runID = localLastInsertID(conn);
end

function [tf, runUUID] = localLookupExistingRun(conn, runID)
tf = false;
runUUID = "";
if ~(isfinite(runID) && runID > 0)
    return;
end
ps = conn.prepareStatement("SELECT run_uuid FROM sim_runs WHERE run_id=? LIMIT 1");
cleanupObj = onCleanup(@() ps.close()); %#ok<NASGU>
ps.setLong(1, int64(runID));
rs = ps.executeQuery();
cleanupRs = onCleanup(@() rs.close()); %#ok<NASGU>
if rs.next()
    tf = true;
    runUUID = string(rs.getString(1));
end
end

function localRefreshExistingRunRow(conn, state, cfg, meta)
scenarioID = char(string(sixgr.util.structGet(meta, "ScenarioID", sixgr.util.structGet(cfg, "meta.lls6gScenarioID", ""))));
runTag = char(string(sixgr.util.structGet(meta, "RunTag", sixgr.util.structGet(cfg, "run.runTag", ""))));
bucket = char(string(sixgr.util.structGet(meta, "Bucket", sixgr.util.structGet(cfg, "run.mode", ""))));
profileName = char(string(sixgr.util.structGet(meta, "Profile", sixgr.util.structGet(cfg, "scenario.id", ""))));
configPayload = localBuildRunConfigPayload(cfg, meta);
ps = conn.prepareStatement([ ...
    "UPDATE sim_runs SET scenario_id=?, run_tag=?, run_folder=?, bucket=?, profile_name=?, backend=?, config_json=?, updated_utc=UTC_TIMESTAMP() " + ...
    "WHERE run_id=?"]);
cleanupObj = onCleanup(@() ps.close()); %#ok<NASGU>
ps.setString(1, scenarioID);
ps.setString(2, runTag);
ps.setString(3, char(string(state.DisplayRunFolder)));
ps.setString(4, bucket);
ps.setString(5, profileName);
ps.setString(6, char(string(state.Backend)));
ps.setString(7, char(localJSON(configPayload)));
ps.setLong(8, int64(state.RunID));
ps.executeUpdate();
end

function payload = localBuildRunConfigPayload(cfg, meta)
payload = cfg;
scenarioStruct = sixgr.util.structGet(meta, "ScenarioConfigStruct", struct());
if isstruct(scenarioStruct) && ~isempty(fieldnames(scenarioStruct))
    payload = sixgr.util.structSet(payload, "lls6g.submittedScenarioConfig", scenarioStruct);
    payload = sixgr.util.structSet(payload, "lls6g.browserResolvedScenarioConfig", scenarioStruct);
end
sourceFiles = string(sixgr.util.structGet(meta, "ScenarioSourceFiles", strings(0, 1)));
if ~isempty(sourceFiles)
    payload = sixgr.util.structSet(payload, "lls6g.scenarioSourceFiles", cellstr(sourceFiles(:)));
end
sourceKind = string(sixgr.util.structGet(meta, "ScenarioConfigSourceKind", ""));
if strlength(strtrim(sourceKind)) == 0
    sourceKind = localInferSourceKindFromFiles(sourceFiles, sixgr.util.structGet(meta, "ScenarioConfigStruct", struct()));
end
payload = sixgr.util.structSet(payload, "lls6g.configSourceKind", char(sourceKind));
if sourceKind == "browser_runtime_overlay"
    payload = sixgr.util.structSet(payload, "lls6g.browserExecutionPath", "browser_runtime_yaml_overlay");
else
    payload = sixgr.util.structSet(payload, "lls6g.browserExecutionPath", "");
end
end

function kind = localInferSourceKindFromFiles(sourceFiles, scenarioStruct)
kind = string(sixgr.util.structGet(scenarioStruct, "SourceKind", ""));
if strlength(strtrim(kind)) == 0
    kind = string(sixgr.util.structGet(scenarioStruct, "meta.SourceKind", ""));
end
if strlength(strtrim(kind)) == 0
    kind = string(sixgr.util.structGet(scenarioStruct, "config_inheritance.provenance.source_kind", ""));
end
if strlength(strtrim(kind)) > 0
    return;
end
kind = "scenario_config_file";
for i = 1:numel(sourceFiles)
    candidate = string(sourceFiles(i));
    [~, name, ext] = fileparts(char(candidate));
    if startsWith(string(name), "__web_runtime_", "IgnoreCase", true) && any(strcmpi(string(ext), [".yaml",".yml",".json"]))
        kind = "browser_runtime_overlay";
        return;
    end
end
end

function artifactID = localFindArtifactID(conn, runID, logicalPath)
artifactID = NaN;
ps = conn.prepareStatement([ ...
    "SELECT artifact_id FROM sim_artifacts WHERE run_id=? AND logical_path=? ORDER BY artifact_id DESC LIMIT 1"]);
cleanupObj = onCleanup(@() ps.close()); %#ok<NASGU>
ps.setLong(1, int64(runID));
ps.setString(2, char(logicalPath));
rs = ps.executeQuery();
cleanupRs = onCleanup(@() rs.close()); %#ok<NASGU>
if rs.next()
    artifactID = double(rs.getLong(1));
end
end

function localDeleteArtifact(conn, artifactID)
localExec(conn, "DELETE FROM sim_artifact_chunks WHERE artifact_id=" + string(round(double(artifactID))));
localExec(conn, "DELETE FROM sim_artifacts WHERE artifact_id=" + string(round(double(artifactID))));
end

function id = localLastInsertID(conn)
stmt = conn.createStatement();
cleanupObj = onCleanup(@() stmt.close()); %#ok<NASGU>
rs = stmt.executeQuery("SELECT LAST_INSERT_ID()");
cleanupRs = onCleanup(@() rs.close()); %#ok<NASGU>
if ~rs.next()
    error("sixgr:db:artifactStore:MissingInsertID", "Failed to read LAST_INSERT_ID().");
end
id = double(rs.getLong(1));
end

function localExec(conn, sqlText)
stmt = conn.createStatement();
cleanupObj = onCleanup(@() stmt.close()); %#ok<NASGU>
stmt.execute(char(string(sqlText)));
end

function localCreateIndexIfMissing(conn, tableName, indexName, columnSpec)
sqlText = "CREATE INDEX " + string(indexName) + " ON " + string(tableName) + " " + string(columnSpec);
try
    localExec(conn, sqlText);
catch ME
    msg = lower(string(ME.message));
    if contains(msg, "duplicate") || contains(msg, "exists") || contains(msg, "1061")
        return;
    end
    rethrow(ME);
end
end

function localRestoreAutoCommit(conn, prevAutoCommit)
try
    if ~isempty(prevAutoCommit)
        conn.setAutoCommit(prevAutoCommit);
    else
        conn.setAutoCommit(true);
    end
catch
end
end

function value = localEnvOrDefault(name, defaultValue)
value = char(string(getenv(char(string(name)))));
if strlength(strtrim(string(value))) == 0
    value = char(string(defaultValue));
end
end

function maxPacketBytes = localQueryMaxAllowedPacket(conn)
maxPacketBytes = NaN;
stmt = [];
rs = [];
try
    stmt = conn.createStatement();
    rs = stmt.executeQuery("SELECT @@max_allowed_packet");
    if rs.next()
        maxPacketBytes = double(rs.getLong(1));
    end
catch
    maxPacketBytes = NaN;
end
try
    if ~isempty(rs)
        rs.close();
    end
catch
end
try
    if ~isempty(stmt)
        stmt.close();
    end
catch
end
if ~isfinite(maxPacketBytes) || maxPacketBytes <= 0
    maxPacketBytes = 64 * 1024 * 1024;
end
end

function [chunkSize, chunkBatchSize] = localResolveChunkPlan(state, bytes, artifactKind, mimeType)
maxPacketBytes = double(sixgr.util.structGet(state, "MaxAllowedPacketBytes", NaN));
if ~isfinite(maxPacketBytes) || maxPacketBytes <= 0
    maxPacketBytes = 64 * 1024 * 1024;
end

defaultChunkSize = 8 * 1024 * 1024;
safePacketBudget = max(1 * 1024 * 1024, floor(0.5 * maxPacketBytes));
chunkSize = min(defaultChunkSize, safePacketBudget);
chunkSize = max(1 * 1024 * 1024, chunkSize);

artifactKind = lower(string(artifactKind));
mimeType = lower(string(mimeType));
isLargeBinary = contains(mimeType, "application/octet-stream") || ...
    contains(artifactKind, "binary") || numel(bytes) > floor(0.25 * maxPacketBytes);

if isLargeBinary
    chunkSize = min(chunkSize, 4 * 1024 * 1024);
    chunkBatchSize = 1;
    return;
end

chunkBatchSize = max(1, floor(safePacketBudget / max(double(chunkSize), 1)));
chunkBatchSize = min(chunkBatchSize, 8);
end

function logicalPath = localLogicalPath(filePath, runFolder)
filePath = char(string(filePath));
runFolder = char(string(runFolder));
fileNorm = localNormalizePath(filePath);
runNorm = localNormalizePath(runFolder);
if strlength(string(runNorm)) > 0 && localPathStartsWith(fileNorm, runNorm)
    rel = extractAfter(string(fileNorm), strlength(string(runNorm)));
    rel = replace(rel, "\", "/");
    rel = regexprep(rel, '^/+', '');
    logicalPath = char(rel);
else
    logicalPath = char(replace(string(fileNorm), "\", "/"));
end
end

function tf = localPathStartsWith(pathValue, rootValue)
pathValue = localNormalizePath(pathValue);
rootValue = localNormalizePath(rootValue);
if ispc
    pathCmp = lower(pathValue);
    rootCmp = lower(rootValue);
else
    pathCmp = pathValue;
    rootCmp = rootValue;
end
tf = strcmp(pathCmp, rootCmp) || startsWith(pathCmp, [rootCmp filesep]);
end

function p = localNormalizePath(inPath)
p = char(string(inPath));
if strlength(string(p)) == 0
    return;
end
p = strrep(p, "/", filesep);
p = strrep(p, "\", filesep);
while contains(p, [filesep filesep])
    p = strrep(p, [filesep filesep], filesep);
end
end

function txt = localEscapeIdentifier(txtIn)
txt = replace(string(txtIn), "`", "``");
end

function txt = localJSON(value)
try
    txt = string(jsonencode(value, "PrettyPrint", true));
catch
    txt = string(jsonencode(value));
end
txt = char(txt);
end

function bytes = localReadFileBytes(filePath)
fid = fopen(filePath, "rb");
if fid < 0
    error("sixgr:db:artifactStore:ReadFailed", "Unable to read artifact '%s'.", string(filePath));
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, Inf, "*uint8").';
end

function bytesOut = localJavaBytes(bytesIn)
% Preserve raw uint8 payload bits when passing bytes above 127 to Java.
bytesOut = typecast(uint8(bytesIn(:).'), "int8");
end

function bytesOut = localBytesFromJava(bytesIn)
if isempty(bytesIn)
    bytesOut = uint8([]);
    return;
end
bytesOut = typecast(int8(bytesIn(:).'), "uint8");
end

function [targetPath, ok] = localHydrationTargetPath(targetRoot, logicalPath)
ok = false;
targetPath = "";
targetRoot = char(string(targetRoot));
rel = replace(string(logicalPath), "\", "/");
rel = regexprep(rel, '^/+', '');
if strlength(strtrim(rel)) == 0 || contains(rel, ":")
    return;
end
parts = split(rel, "/");
parts = parts(strlength(parts) > 0 & parts ~= ".");
if isempty(parts) || any(parts == "..")
    return;
end
partCell = cellstr(parts(:).');
targetPath = fullfile(targetRoot, partCell{:});
if ~localPathStartsWith(targetPath, targetRoot)
    targetPath = "";
    return;
end
ok = true;
end

function localDeleteIfExists(filePath)
try
    if exist(filePath, "file") == 2
        warnState = warning("off", "all");
        cleanupWarn = onCleanup(@() warning(warnState)); %#ok<NASGU>
        delete(filePath);
    end
catch
end
end
