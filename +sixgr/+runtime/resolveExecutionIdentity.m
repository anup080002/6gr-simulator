function identity = resolveExecutionIdentity(runFolder, runId, configHash, executionOptions)
%RESOLVEEXECUTIONIDENTITY Create or recover one immutable execution identity.
%
% A new execution receives a UUID-backed identifier. A finalization resume
% must recover the identifier already persisted by that execution; it may
% never mint a replacement identity for old waveform evidence.

if nargin < 4 || isempty(executionOptions)
    executionOptions = struct();
end
if ~(isstruct(executionOptions) && isscalar(executionOptions))
    error("sixgr:runtime:ExecutionOptionsInvalid", ...
        "Execution identity options must be a scalar struct.");
end
runFolder = string(runFolder);
runId = strtrim(string(runId));
configHash = lower(strtrim(string(configHash)));
if ~isscalar(runFolder) || strlength(strtrim(runFolder)) == 0
    error("sixgr:runtime:RunFolderRequired", ...
        "Execution identity requires a non-empty run folder.");
end
if ~isscalar(runId) || strlength(runId) == 0
    error("sixgr:runtime:RunIdentityRequired", ...
        "Execution identity requires a non-empty RunID.");
end
if ~isscalar(configHash) || strlength(configHash) ~= 64 || ...
        isempty(regexp(char(configHash), '^[0-9a-f]{64}$', 'once'))
    error("sixgr:runtime:ConfigHashInvalid", ...
        "Execution identity requires the resolved YAML SHA-256 ConfigHash.");
end

resumeRequested = logical(sixgr.util.structGet(executionOptions, ...
    "ResumeCompletedRuntimeFinalization", false));
explicit = strtrim(string(sixgr.util.structGet(executionOptions, ...
    "ExecutionID", "")));
if ~isscalar(explicit)
    error("sixgr:runtime:ExecutionIdentityInvalid", ...
        "ExecutionID must be a text scalar.");
end

[persisted, source, persistedRunId, persistedHash] = ...
    localPersistedIdentity(runFolder);
if strlength(persisted) > 0
    if strlength(persistedRunId) > 0 && persistedRunId ~= runId
        error("sixgr:runtime:ExecutionRunIdentityMismatch", ...
            "Persisted RunID %s does not match requested RunID %s.", ...
            persistedRunId, runId);
    end
    if strlength(persistedHash) > 0 && lower(persistedHash) ~= configHash
        error("sixgr:runtime:ExecutionConfigIdentityMismatch", ...
            "Persisted ConfigHash %s does not match requested ConfigHash %s.", ...
            persistedHash, configHash);
    end
end
if strlength(explicit) > 0 && strlength(persisted) > 0 && explicit ~= persisted
    error("sixgr:runtime:ExecutionIdentityMismatch", ...
        "Requested ExecutionID %s does not match persisted ExecutionID %s.", ...
        explicit, persisted);
end

if strlength(persisted) > 0
    executionId = persisted;
elseif strlength(explicit) > 0
    executionId = explicit;
    source = "explicit_execution_option";
elseif resumeRequested
    error("sixgr:runtime:ResumeExecutionIdentityMissing", ...
        ["Finalization resume requires an ExecutionID persisted by the " + ...
         "original waveform execution; a replacement identity is forbidden."]);
else
    executionId = "execution_" + lower(string(char(java.util.UUID.randomUUID())));
    source = "new_waveform_execution_uuid";
end

identity = struct( ...
    "RunID", runId, ...
    "ExecutionID", executionId, ...
    "ConfigHash", configHash, ...
    "Source", source, ...
    "ResumeRequested", resumeRequested);
end

function [executionId, source, runId, configHash] = localPersistedIdentity(runFolder)
executionId = "";
source = "";
runId = "";
configHash = "";
candidates = [ ...
    string(fullfile(runFolder, "raw", "execution_manifest.json")), ...
    string(fullfile(runFolder, "meta", "runtime_summary.json")), ...
    string(fullfile(runFolder, "meta", "scenario_manifest.json"))];
for pathValue = candidates
    if ~isfile(pathValue)
        continue;
    end
    try
        value = jsondecode(fileread(pathValue));
    catch cause
        error("sixgr:runtime:PersistedExecutionIdentityUnreadable", ...
            "Cannot read persisted execution identity %s: %s", ...
            pathValue, cause.message);
    end
    candidate = localFirstText(value, ["ExecutionID","execution_id"]);
    if strlength(candidate) == 0
        continue;
    end
    executionId = candidate;
    runId = localFirstText(value, ["RunID","RunId","run_id"]);
    configHash = localFirstText(value, ["ConfigHash","config_hash"]);
    source = "persisted:" + replace(pathValue, "\", "/");
    return;
end

% Failed-run report recovery can legitimately replace the summary JSON
% before a completed PHY is re-finalized.  The immutable execution ID is
% also stamped on canonical waveform rows.  Recover it from those rows
% rather than minting a new ID or trusting a derived report artifact.
[executionId, source, runId, configHash] = ...
    localPersistedCanonicalRowIdentity(runFolder);
end

function [executionId, source, runId, configHash] = ...
        localPersistedCanonicalRowIdentity(runFolder)
executionId = "";
source = "";
runId = "";
configHash = "";
candidates = [ ...
    string(fullfile(runFolder, "air_interface", "csv", "pdcch_trials.csv")), ...
    string(fullfile(runFolder, "air_interface", "csv", "dl_pdsch_trials.csv")), ...
    string(fullfile(runFolder, "air_interface", "csv", "ul_pusch_trials.csv")), ...
    string(fullfile(runFolder, "control", "csv", "pdcch_trials.csv"))];
for pathValue = candidates
    if ~isfile(pathValue)
        continue;
    end
    try
        opts = detectImportOptions(char(pathValue), "FileType", "text", ...
            "Delimiter", ",", "VariableNamingRule", "preserve");
        wanted = intersect(opts.VariableNames, ...
            {'ExecutionID','RunTag','RunID','ConfigHash'}, "stable");
        if ~ismember('ExecutionID', wanted)
            continue;
        end
        opts.SelectedVariableNames = wanted;
        rows = readtable(char(pathValue), opts);
    catch cause
        error("sixgr:runtime:PersistedExecutionIdentityUnreadable", ...
            "Cannot read canonical execution identity %s: %s", ...
            pathValue, cause.message);
    end
    ids = localUniqueIdentityText(rows, "ExecutionID");
    if isempty(ids)
        continue;
    end
    if numel(ids) ~= 1
        error("sixgr:runtime:PersistedExecutionIdentityAmbiguous", ...
            "Canonical evidence %s contains multiple ExecutionID values: %s.", ...
            pathValue, strjoin(ids, ", "));
    end
    executionId = ids(1);
    runIds = localUniqueIdentityText(rows, "RunTag");
    if isempty(runIds)
        runIds = localUniqueIdentityText(rows, "RunID");
    end
    if numel(runIds) > 1
        error("sixgr:runtime:PersistedExecutionRunIdentityAmbiguous", ...
            "Canonical evidence %s contains multiple run identities: %s.", ...
            pathValue, strjoin(runIds, ", "));
    elseif numel(runIds) == 1
        runId = runIds(1);
    end
    hashes = lower(localUniqueIdentityText(rows, "ConfigHash"));
    if numel(hashes) > 1
        error("sixgr:runtime:PersistedExecutionConfigIdentityAmbiguous", ...
            "Canonical evidence %s contains multiple ConfigHash values: %s.", ...
            pathValue, strjoin(hashes, ", "));
    elseif numel(hashes) == 1
        configHash = hashes(1);
    end
    source = "persisted_canonical_rows:" + replace(pathValue, "\", "/");
    return;
end
end

function values = localUniqueIdentityText(rows, fieldName)
values = strings(0, 1);
if ~istable(rows) || ~ismember(fieldName, rows.Properties.VariableNames)
    return;
end
raw = strtrim(string(rows.(fieldName)));
raw = raw(strlength(raw) > 0 & ~ismissing(raw) & lower(raw) ~= "nan");
values = unique(raw, "stable");
end

function value = localFirstText(S, fields)
value = "";
for field = fields
    if isfield(S, field)
        candidate = strtrim(string(S.(field)));
        if isscalar(candidate) && strlength(candidate) > 0
            value = candidate;
            return;
        end
    end
end
end
