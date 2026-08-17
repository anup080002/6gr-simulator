function snapshot = snapshotRawExecutionEvidence(runFolder, link, identity)
%SNAPSHOTRAWEXECUTIONEVIDENCE Freeze same-scenario waveform tables pre-finalization.
%
% The report/finalization layer is intentionally allowed to be rerun.  The
% waveform evidence it consumes is not.  This function copies the current
% execution's in-memory, in-path raw tables into raw/evidence exactly once,
% validates their identity, rejects proxy/fallback rows, and records hashes
% before RunEvidenceLifecycle seals the execution manifest.

if ~(isstruct(link) && isscalar(link))
    error("sixgr:runtime:RawExecutionLinkRequired", ...
        "Raw execution snapshot requires one link-result struct.");
end
identity = localIdentity(identity);
runFolder = char(string(runFolder));
rawRoot = fullfile(runFolder, "raw");
evidenceRoot = fullfile(rawRoot, "evidence");
indexPath = fullfile(evidenceRoot, "raw_evidence_index.csv");
if isfile(indexPath)
    snapshot = localReadExisting(indexPath, identity);
    return;
end
if isfolder(evidenceRoot) && ~isempty(localEntries(evidenceRoot))
    error("sixgr:runtime:UnsealedRawEvidenceExists", ...
        "Raw evidence exists without its immutable index: %s", evidenceRoot);
end

stageRoot = fullfile(rawRoot, ".evidence_stage_" + localUUID());
stageTables = fullfile(stageRoot, "tables");
mkdir(stageTables);
cleanupStage = onCleanup(@() localRemoveOwnedStage(stageRoot, rawRoot)); %#ok<NASGU>

sources = localRawTableSources(link);
rows = repmat(localEmptyIndexRow(), 0, 1);
for sourceIndex = 1:numel(sources)
    source = sources(sourceIndex);
    T = source.Value;
    if ~(istable(T) && ~isempty(T))
        continue;
    end
    [T, excludedRows] = localSelectInPathRows(T, source.Name);
    if isempty(T)
        continue;
    end
    T = sixgr.runtime.bindInPathArtifactIdentity(T, identity);
    sixgr.artifact.validateEvidenceIdentity(T, struct( ...
        "ScenarioID", identity.ScenarioID, ...
        "ConfigHash", identity.ConfigHash, ...
        "EvidenceScope", "in_path", ...
        "RunID", identity.RunID, ...
        "ExecutionID", identity.ExecutionID), ...
        source.Name, "RequireIdentityColumns", true, ...
        "RequireRadioIdentityColumns", false);
    localRejectApproximationRows(T, source.Name);

    fileName = localSafeName(source.Name) + ".csv";
    stagePath = fullfile(stageTables, fileName);
    writetable(T, stagePath);
    persistedT = readtable(stagePath, "TextType", "string", ...
        "VariableNamingRule", "preserve");
    % A matrix-valued table variable is expanded by writetable into several
    % physical CSV columns.  Therefore the parsed CSV width may exceed the
    % logical MATLAB table width, but it must never lose rows or contract
    % below the number of logical source variables.
    if height(persistedT) ~= height(T) || width(persistedT) < width(T)
        error("sixgr:runtime:RawEvidenceSerializedShapeMismatch", ...
            "Serialized raw execution table %s lost shape: memory=%dx%d, csv=%dx%d.", ...
            char(source.Name), height(T), width(T), ...
            height(persistedT), width(persistedT));
    end
    [primaryKey, duplicateKeyCount] = localPrimaryKeyAudit(T);
    if duplicateKeyCount > 0
        error("sixgr:runtime:RawEvidenceDuplicateKey", ...
            "Raw execution table %s contains %d duplicate primary-key row(s) for %s.", ...
            source.Name, duplicateKeyCount, strjoin(primaryKey, "|"));
    end
    rows(end + 1, 1) = struct( ... %#ok<AGROW>
        "SchemaName", "sixgr.raw_evidence_index", ...
        "SchemaVersion", "1.0.0", ...
        "RunID", identity.RunID, ...
        "ExecutionID", identity.ExecutionID, ...
        "ScenarioID", identity.ScenarioID, ...
        "ConfigHash", identity.ConfigHash, ...
        "EvidenceScope", "in_path", ...
        "TableName", source.Name, ...
        "Producer", source.Producer, ...
        "RelativePath", replace(string(fullfile("tables", fileName)), "\", "/"), ...
        "RowCount", height(persistedT), ...
        "ColumnCount", width(persistedT), ...
        "ExcludedNonInPathRows", excludedRows, ...
        "PrimaryKeyColumns", strjoin(primaryKey, "|"), ...
        "DuplicateKeyCount", duplicateKeyCount, ...
        "SHA256", localFileSHA256(stagePath));
end
if isempty(rows)
    error("sixgr:runtime:RawExecutionEvidenceMissing", ...
        "The completed execution did not expose any nonempty in-path raw waveform table.");
end
indexT = struct2table(rows, "AsArray", true);
indexT = sortrows(indexT, "TableName");
writetable(indexT, fullfile(stageRoot, "raw_evidence_index.csv"));

if ~isfolder(rawRoot)
    mkdir(rawRoot);
end
if isfolder(evidenceRoot)
    error("sixgr:runtime:RawEvidencePublishCollision", ...
        "Refusing to replace an existing raw evidence root: %s", evidenceRoot);
end
[ok, message] = movefile(stageRoot, evidenceRoot);
if ~ok
    error("sixgr:runtime:RawEvidencePublishFailed", ...
        "Unable to atomically publish raw execution evidence: %s", message);
end
clear cleanupStage;
snapshot = localSnapshot(indexPath, indexT, identity);
end

function sources = localRawTableSources(link)
sources = repmat(struct("Name", "", "Producer", "", "Value", table()), 0, 1);
containers = {"RawTrials", "sixgr.truth.runWaveformLinkBundle"; ...
    "SupplementalStrictRawTrials", "strict_in_path_component_runtime"};
for containerIndex = 1:size(containers, 1)
    field = containers{containerIndex, 1};
    producer = containers{containerIndex, 2};
    value = sixgr.util.structGet(link, field, struct());
    if ~(isstruct(value) && isscalar(value))
        continue;
    end
    names = sort(string(fieldnames(value)));
    for name = names(:).'
        T = value.(char(name));
        if ~istable(T)
            continue;
        end
        canonicalName = lower(string(field)) + "_" + lower(name);
        sources(end + 1, 1) = struct( ... %#ok<AGROW>
            "Name", canonicalName, "Producer", string(producer), "Value", T);
    end
end
end

function [T, excluded] = localSelectInPathRows(T, name)
excluded = 0;
vars = string(T.Properties.VariableNames);
if ~ismember("EvidenceScope", vars)
    return;
end
scope = lower(strtrim(string(T.EvidenceScope)));
blank = ismissing(scope) | strlength(scope) == 0;
if any(blank)
    error("sixgr:runtime:RawEvidenceScopeMissing", ...
        "Raw table %s contains blank EvidenceScope rows.", name);
end
keep = scope == "in_path";
excluded = nnz(~keep);
T = T(keep, :);
end

function localRejectApproximationRows(T, name)
vars = string(T.Properties.VariableNames);
textColumns = ["SourceClassification", "ExecutionBackend", ...
    "ApproximationMode", "E2EAirModel", "TruthStatus"];
badTokens = ["fast_proxy", "proxy", "synthetic", "fallback", ...
    "logistic", "lookup_table", "lut"];
for column = intersect(textColumns, vars, "stable")
    values = lower(strtrim(string(T.(char(column)))));
    populated = ~ismissing(values) & strlength(values) > 0;
    bad = false(height(T), 1);
    for token = badTokens
        bad = bad | (populated & contains(values, token));
    end
    if any(bad)
        error("sixgr:runtime:ProxyRawEvidenceForbidden", ...
            "Raw table %s contains proxy/fallback classification in %s.", ...
            name, column);
    end
end
for column = intersect(["FallbackFlag", "PlaceholderFlag"], vars, "stable")
    if any(localLogical(T.(char(column))))
        error("sixgr:runtime:ProxyRawEvidenceForbidden", ...
            "Raw table %s contains asserted %s rows.", name, column);
    end
end
end

function [key, duplicateCount] = localPrimaryKeyAudit(T)
vars = string(T.Properties.VariableNames);
candidates = { ...
    ["TrialID"], ...
    ["Direction","FixedLinkPointIndex","FixedLinkTrialIndex", ...
        "FixedLinkSeedIndex"], ...
    ["Direction","Frame","Slot","UEID","TBId","HARQRound"], ...
    ["Direction","Frame","Slot","UEIndex","TBId","HARQRound"], ...
    ["Signal","Frame","Slot","UEID"], ...
    ["Frame","Slot","UEID","HARQProcess","HARQRound"]};
key = strings(0, 1);
for candidateIndex = 1:numel(candidates)
    candidate = candidates{candidateIndex};
    if all(ismember(candidate, vars))
        key = candidate(:);
        break;
    end
end
if isempty(key)
    duplicateCount = 0;
    key = "row_order_only_no_declared_primary_key";
    return;
end
keyTable = T(:, cellstr(key));
try
    [~, uniqueIndex] = unique(keyTable, "rows", "stable");
    duplicateCount = height(T) - numel(uniqueIndex);
catch
    duplicateCount = NaN;
end
if ~isfinite(duplicateCount)
    error("sixgr:runtime:RawEvidencePrimaryKeyUnsupported", ...
        "Unable to evaluate the raw evidence primary key %s.", strjoin(key, "|"));
end
end

function snapshot = localReadExisting(indexPath, identity)
T = readtable(indexPath, "VariableNamingRule", "preserve", "TextType", "string");
required = ["RunID","ExecutionID","ScenarioID","ConfigHash", ...
    "EvidenceScope","RelativePath","SHA256"];
if isempty(T) || any(~ismember(required, string(T.Properties.VariableNames)))
    error("sixgr:runtime:RawEvidenceIndexInvalid", ...
        "Existing raw evidence index is empty or malformed: %s", indexPath);
end
for field = ["RunID","ExecutionID","ScenarioID","ConfigHash"]
    if any(string(T.(char(field))) ~= identity.(char(field)))
        error("sixgr:runtime:RawExecutionIdentityMismatch", ...
            "Existing raw evidence %s does not match the requested execution.", field);
    end
end
root = fileparts(indexPath);
for row = 1:height(T)
    pathValue = fullfile(root, char(T.RelativePath(row)));
    if ~isfile(pathValue) || lower(localFileSHA256(pathValue)) ~= lower(T.SHA256(row))
        error("sixgr:runtime:RawEvidenceHashMismatch", ...
            "Immutable raw evidence is missing or changed: %s", pathValue);
    end
end
snapshot = localSnapshot(indexPath, T, identity);
end

function snapshot = localSnapshot(indexPath, indexT, identity)
snapshot = struct( ...
    "SchemaName", "sixgr.raw_evidence_snapshot", ...
    "SchemaVersion", "1.0.0", ...
    "RunID", identity.RunID, ...
    "ExecutionID", identity.ExecutionID, ...
    "ScenarioID", identity.ScenarioID, ...
    "ConfigHash", identity.ConfigHash, ...
    "IndexPath", string(indexPath), ...
    "IndexRelativePath", "evidence/raw_evidence_index.csv", ...
    "IndexSHA256", localFileSHA256(indexPath), ...
    "TableCount", height(indexT), ...
    "RowCount", sum(double(indexT.RowCount)));
end

function identity = localIdentity(identity)
if ~(isstruct(identity) && isscalar(identity))
    error("sixgr:runtime:RawExecutionIdentityRequired", ...
        "Raw execution identity must be one scalar struct.");
end
for field = ["RunID","ExecutionID","ScenarioID","ConfigHash"]
    value = strtrim(string(sixgr.util.structGet(identity, field, "")));
    if ~isscalar(value) || strlength(value) == 0
        error("sixgr:runtime:RawExecutionIdentityRequired", ...
            "Raw execution identity requires nonempty %s.", field);
    end
    identity.(char(field)) = value;
end
identity.ConfigHash = lower(identity.ConfigHash);
if strlength(identity.ConfigHash) ~= 64 || ...
        isempty(regexp(char(identity.ConfigHash), "^[0-9a-f]{64}$", "once"))
    error("sixgr:runtime:RawExecutionIdentityRequired", ...
        "Raw execution ConfigHash must be a SHA-256 digest.");
end
end

function value = localLogical(value)
if islogical(value)
    return;
end
if isnumeric(value)
    value = value ~= 0;
else
    value = ismember(lower(strtrim(string(value))), ["true","1","yes","pass"]);
end
end

function name = localSafeName(value)
name = regexprep(lower(char(string(value))), "[^a-z0-9_]+", "_");
name = string(regexprep(name, "^_+|_+$", ""));
if strlength(name) == 0
    error("sixgr:runtime:RawEvidenceNameInvalid", ...
        "Raw evidence table name is empty after normalization.");
end
end

function row = localEmptyIndexRow()
row = struct("SchemaName", "", "SchemaVersion", "", ...
    "RunID", "", "ExecutionID", "", "ScenarioID", "", ...
    "ConfigHash", "", "EvidenceScope", "", "TableName", "", ...
    "Producer", "", "RelativePath", "", "RowCount", 0, ...
    "ColumnCount", 0, "ExcludedNonInPathRows", 0, ...
    "PrimaryKeyColumns", "", "DuplicateKeyCount", 0, "SHA256", "");
end

function entries = localEntries(pathValue)
entries = dir(pathValue);
entries = entries(~ismember(string({entries.name}), [".", ".."])) ;
end

function localRemoveOwnedStage(stageRoot, rawRoot)
stageRoot = string(stageRoot);
rawRoot = string(rawRoot);
if isfolder(stageRoot) && startsWith(stageRoot, rawRoot + string(filesep)) && ...
        contains(string(fileparts(char(stageRoot))), rawRoot)
    rmdir(stageRoot, "s");
end
end

function hash = localFileSHA256(pathValue)
fid = fopen(pathValue, "rb");
if fid < 0
    error("sixgr:runtime:RawEvidenceHashReadFailed", ...
        "Unable to read raw evidence for hashing: %s", pathValue);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
hash = sixgr.util.sha256Hex(fread(fid, Inf, "*uint8"));
end

function value = localUUID()
value = lower(string(char(java.util.UUID.randomUUID())));
end
