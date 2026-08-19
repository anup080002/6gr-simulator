function [scfg, authority] = resolveRecoveryScenarioConfig(runFolder, inputCfg, varargin)
%RESOLVERECOVERYSCENARIOCONFIG Bind recovery to the executed immutable config.
%
% Recovery must never reload a mutable YAML file and silently associate its
% values with waveform rows from an older execution.  This resolver compares
% the content hash of every available resolved configuration with the hash
% persisted by the runtime trial rows.  A mismatch fails before any recovery
% artifact or configuration snapshot can be written.

p = inputParser;
p.addRequired("runFolder", @(x)ischar(x) || isstring(x));
p.addRequired("inputCfg", @(x)isa(x, "sixgr.lls6g.config.ScenarioConfig") || ...
    isstruct(x) || ischar(x) || isstring(x));
p.addParameter("SourceFiles", strings(0,1), @(x)isstring(x) || iscellstr(x) || ischar(x));
p.addParameter("ConfigPath", "", @(x)ischar(x) || isstring(x));
p.addParameter("ConfigHash", "", @(x)ischar(x) || isstring(x));
p.parse(runFolder, inputCfg, varargin{:});

runFolder = char(string(p.Results.runFolder));
sourceFiles = string(p.Results.SourceFiles(:));
configPath = string(p.Results.ConfigPath);
requestedHash = localValidHash(p.Results.ConfigHash);
[runtimeHash, runtimeSources] = localRuntimeEvidenceHash(runFolder);
stored = localStoredMetadata(runFolder);
storedHash = localValidHash(stored.ConfigHash);

[persistedCfg, persistedHash, persistedCompatibility] = ...
    localPersistedResolvedConfig( ...
    runFolder, sourceFiles, configPath);
expectedHash = localFirstNonEmpty(runtimeHash, storedHash, requestedHash);
suppliedCfg = [];
suppliedHash = "";
% Do not force an immutable legacy snapshot through the current launch
% schema merely because the caller supplied its path. When the persisted
% snapshot already matches the runtime/stored authority, it is sufficient
% and the caller input is not an independent competing authority.
persistedAlreadyAuthoritative = ~isempty(persistedCfg) && ...
    (strlength(expectedHash) == 0 || persistedHash == expectedHash);
if ~persistedAlreadyAuthoritative
    [suppliedCfg, suppliedHash] = localSuppliedConfig( ...
        inputCfg, sourceFiles, configPath);
end
matCfg = [];
matHash = "";
if strlength(expectedHash) > 0 && ...
        (isempty(persistedCfg) || persistedHash ~= expectedHash)
    [matCfg, matHash] = localExecutedMATConfig(runFolder, sourceFiles, configPath);
end
selected = [];
selectedHash = "";
selectedSource = "";
if strlength(expectedHash) > 0
    if ~isempty(persistedCfg) && persistedHash == expectedHash
        selected = persistedCfg;
        selectedHash = persistedHash;
        selectedSource = "persisted_resolved_config_snapshot";
    elseif ~isempty(matCfg) && matHash == expectedHash
        selected = matCfg;
        selectedHash = matHash;
        selectedSource = "persisted_link_results_executed_config";
    elseif ~isempty(suppliedCfg) && suppliedHash == expectedHash
        selected = suppliedCfg;
        selectedHash = suppliedHash;
        selectedSource = "supplied_exact_resolved_config";
    else
        error("sixgr:truth:recover:ImmutableConfigUnavailable", ...
            ["Recovery evidence is bound to ConfigHash %s, but neither the " + ...
            "persisted resolved snapshot (hash=%s), persisted executed MAT config " + ...
            "(hash=%s), nor the supplied configuration (hash=%s) matches it. " + ...
            "The source run remains immutable; provide the " + ...
            "exact executed resolved configuration."], ...
            char(expectedHash), char(persistedHash), char(matHash), char(suppliedHash));
    end
else
    if ~isempty(persistedCfg)
        selected = persistedCfg;
        selectedHash = persistedHash;
        selectedSource = "persisted_resolved_config_snapshot_no_runtime_hash";
    elseif ~isempty(suppliedCfg)
        selected = suppliedCfg;
        selectedHash = suppliedHash;
        selectedSource = "supplied_resolved_config_no_runtime_hash";
    else
        error("sixgr:truth:recover:ScenarioConfigNotFound", ...
            "No resolved scenario configuration is available for artifact recovery.");
    end
end

% Reconstruct the immutable value with the verified content hash.  Never
% retain a caller-provided ConfigHash that disagrees with its actual data.
scfg = sixgr.lls6g.config.ScenarioConfig(selected.toStruct(), ...
    "SourceFiles", selected.SourceFiles, ...
    "ConfigPath", selected.ConfigPath, ...
    "ConfigHash", selectedHash, ...
    "Kind", selected.Kind);
authority = struct( ...
    "Authority", selectedSource, ...
    "ExpectedConfigHash", expectedHash, ...
    "ResolvedConfigHash", selectedHash, ...
    "RuntimeEvidenceConfigHash", runtimeHash, ...
    "RuntimeEvidenceSources", runtimeSources(:), ...
    "PersistedSnapshotHash", persistedHash, ...
    "PersistedSnapshotCurrentCompatibilityOk", ...
        logical(persistedCompatibility.Ok), ...
    "PersistedSnapshotCompatibilityStatus", ...
        string(persistedCompatibility.Status), ...
    "PersistedSnapshotCompatibilityIdentifier", ...
        string(persistedCompatibility.Identifier), ...
    "PersistedSnapshotCompatibilityMessage", ...
        string(persistedCompatibility.Message), ...
    "PersistedExecutedMATConfigHash", matHash, ...
    "SuppliedConfigHash", suppliedHash, ...
    "ExactMatch", strlength(expectedHash) == 0 || selectedHash == expectedHash);
end

function [scfg, hash] = localExecutedMATConfig(runFolder, sourceFiles, configPath)
scfg = [];
hash = "";
path = fullfile(runFolder, "air_interface", "mat", "link_results.mat");
if exist(path, "file") ~= 2
    return;
end
try
    payload = load(path, "details");
catch
    return;
end
details = sixgr.util.structGet(payload, "details", struct());
cfg = sixgr.util.structGet(details, "Config", struct());
data = sixgr.util.structGet(cfg, "lls6g.resolvedConfig", struct());
if ~(isstruct(data) && isscalar(data) && ~isempty(fieldnames(data)))
    return;
end
declaredHash = localValidHash(sixgr.util.structGet(cfg, "meta.configHash", ""));
contentHash = localContentHash(data);
if strlength(declaredHash) == 0 || declaredHash ~= contentHash
    error("sixgr:truth:recover:PersistedMATConfigHashMismatch", ...
        ["The resolved scenario embedded in link_results.mat does not match its " + ...
        "executed ConfigHash (declared=%s content=%s)."], ...
        char(declaredHash), char(contentHash));
end
sixgr.lls6g.config.validateScenarioConfig(data, ...
    "Kind", "scenario", "AllowPartial", false, ...
    "Context", "recoverLLSRunArtifacts persisted link_results.mat");
matSources = string(sixgr.util.structGet(data, ...
    "config_inheritance.provenance.source_files", sourceFiles));
matPath = string(sixgr.util.structGet(data, ...
    "config_inheritance.provenance.config_path", configPath));
scfg = sixgr.lls6g.config.ScenarioConfig(data, ...
    "SourceFiles", matSources(:), ...
    "ConfigPath", matPath, ...
    "ConfigHash", declaredHash, ...
    "Kind", "scenario");
hash = declaredHash;
end

function [scfg, hash, compatibility] = localPersistedResolvedConfig(runFolder, sourceFiles, configPath)
scfg = [];
hash = "";
compatibility = struct( ...
    "Ok", false, ...
    "Status", "persisted_snapshot_not_available", ...
    "Identifier", "", ...
    "Message", "");
snapshotPath = fullfile(runFolder, "meta", "scenario_config_resolved.json");
if exist(snapshotPath, "file") ~= 2
    return;
end
try
    data = jsondecode(fileread(snapshotPath));
catch ME
    error("sixgr:truth:recover:InvalidPersistedResolvedConfig", ...
        "Cannot decode immutable resolved configuration %s: %s", snapshotPath, ME.message);
end
if ~(isstruct(data) && isscalar(data))
    error("sixgr:truth:recover:InvalidPersistedResolvedConfig", ...
        "Persisted resolved configuration %s is not a scalar structure.", snapshotPath);
end
snapshotDigest = localFileSHA256(snapshotPath);
stored = localStoredMetadata(runFolder);
identityPath = fullfile(runFolder, "meta", "scenario_config_identity.json");
declaredHash = "";
if exist(identityPath, "file") == 2
    try
        identity = jsondecode(fileread(identityPath));
    catch ME
        error("sixgr:truth:recover:InvalidConfigIdentity", ...
            "Cannot decode immutable config identity %s: %s", identityPath, ME.message);
    end
    declaredDigest = lower(strtrim(string(sixgr.util.structGet(identity, ...
        "ResolvedJSONSHA256", ""))));
    if strlength(declaredDigest) ~= 64 || declaredDigest ~= snapshotDigest
        error("sixgr:truth:recover:ResolvedConfigSnapshotDigestMismatch", ...
            "Resolved configuration snapshot digest does not match %s.", identityPath);
    end
    declaredHash = localValidHash(sixgr.util.structGet(identity, "ConfigHash", ""));
end
% Older runners wrote a derived reporting/runtime view into the file named
% scenario_config_resolved.json.  Its file digest is still verified above,
% but it is not executable configuration authority and must not be passed
% to the strict input schema.  Recovery can select the exact supplied or
% MAT-embedded configuration by ConfigHash instead.
if isfield(data, "reporting_semantics") || ...
        isfield(data, "resolved_runtime_view")
    scfg = [];
    hash = "";
    return;
end
try
    sixgr.lls6g.config.validateScenarioConfig(data, ...
        "Kind", "scenario", "AllowPartial", false, ...
        "Context", "recoverLLSRunArtifacts persisted snapshot");
    compatibility.Ok = true;
    compatibility.Status = "current_schema_compatible";
catch ME
    legacyIntervalGap = string(ME.identifier) == ...
        "sixgr:lls6g:config:FixedLinkMasterFieldMissing" && ...
        contains(string(ME.message), "'interval_method'");
    if ~legacyIntervalGap
        rethrow(ME);
    end
    % The snapshot is immutable execution evidence, not a candidate for a
    % new launch. Accept its structurally valid legacy fields for recovery
    % while recording that it cannot satisfy the current sequential-
    % interval launch contract. Downstream sweep gates remain fail-closed.
    sixgr.lls6g.config.validateScenarioConfig(data, ...
        "Kind", "scenario", "AllowPartial", true, ...
        "Context", "recoverLLSRunArtifacts legacy persisted snapshot");
    compatibility.Ok = false;
    compatibility.Status = "legacy_fixed_link_interval_method_missing";
    compatibility.Identifier = string(ME.identifier);
    compatibility.Message = string(ME.message);
end
if strlength(declaredHash) == 0
    % Legacy runs predate the immutable identity sidecar. The run manifest
    % remains usable only as a declaration; runtime row identity is still
    % required to match it before this snapshot can be selected.
    declaredHash = localValidHash(stored.ConfigHash);
end
if strlength(declaredHash) > 0
    hash = declaredHash;
else
    hash = localContentHash(data);
end
persistedSources = localStoredSourceFiles(runFolder);
if isempty(persistedSources)
    persistedSources = sourceFiles;
end
persistedPath = localFirstNonEmpty(stored.ConfigPath, configPath, string(snapshotPath));
scfg = sixgr.lls6g.config.ScenarioConfig(data, ...
    "SourceFiles", persistedSources(:), ...
    "ConfigPath", persistedPath, ...
    "ConfigHash", hash, ...
    "Kind", "scenario");
end

function [scfg, hash] = localSuppliedConfig(inputCfg, sourceFiles, configPath)
scfg = [];
hash = "";
if isa(inputCfg, "sixgr.lls6g.config.ScenarioConfig")
    data = inputCfg.toStruct();
    suppliedSources = inputCfg.SourceFiles;
    suppliedPath = inputCfg.ConfigPath;
    kind = inputCfg.Kind;
elseif ischar(inputCfg) || isstring(inputCfg)
    candidate = char(string(inputCfg));
    if exist(candidate, "file") ~= 2
        error("sixgr:truth:recover:ScenarioConfigNotFound", ...
            "Scenario configuration '%s' could not be resolved for artifact recovery.", candidate);
    end
    loaded = sixgr.lls6g.config.loadScenarioConfig(candidate);
    data = loaded.toStruct();
    suppliedSources = loaded.SourceFiles;
    suppliedPath = loaded.ConfigPath;
    kind = loaded.Kind;
else
    data = inputCfg;
    if isfield(data, "lls6g") && isstruct(data.lls6g) && ...
            isfield(data.lls6g, "resolvedConfig")
        suppliedSources = string(sixgr.util.structGet(data, ...
            "lls6g.resolvedConfig.config_inheritance.provenance.source_files", sourceFiles));
        suppliedPath = string(sixgr.util.structGet(data, ...
            "lls6g.resolvedConfig.config_inheritance.provenance.config_path", configPath));
        data = data.lls6g.resolvedConfig;
    else
        suppliedSources = sourceFiles;
        suppliedPath = configPath;
    end
    kind = "scenario";
end
sixgr.lls6g.config.validateScenarioConfig(data, ...
    "Kind", "scenario", "AllowPartial", false, ...
    "Context", "recoverLLSRunArtifacts supplied config");
hash = localContentHash(data);
scfg = sixgr.lls6g.config.ScenarioConfig(data, ...
    "SourceFiles", string(suppliedSources(:)), ...
    "ConfigPath", string(suppliedPath), ...
    "ConfigHash", hash, ...
    "Kind", string(kind));
end

function [hash, sources] = localRuntimeEvidenceHash(runFolder)
hashes = strings(0,1);
sources = strings(0,1);
candidates = [ ...
    "air_interface/csv/pbch_trials.csv"
    "air_interface/csv/prach_trials.csv"
    "air_interface/csv/pdcch_trials.csv"
    "air_interface/csv/pucch_trials.csv"
    "air_interface/csv/srs_trials.csv"
    "air_interface/csv/trs_trials.csv"
    "air_interface/csv/dl_pdsch_trials.csv"
    "air_interface/csv/ul_pusch_trials.csv"
    "air_interface/csv/dl_fixed_link_campaign_trials.csv"
    "air_interface/csv/ul_fixed_link_campaign_trials.csv"];
for rel = candidates.'
    path = fullfile(runFolder, strrep(char(rel), '/', filesep));
    if exist(path, "file") ~= 2
        continue;
    end
    try
        T = readtable(path, "FileType", "text", "Delimiter", ",", ...
            "ReadVariableNames", true, "VariableNamingRule", "preserve");
        if ~ismember("ConfigHash", string(T.Properties.VariableNames))
            continue;
        end
        values = lower(strtrim(string(T.ConfigHash)));
        values = unique(values(strlength(values) == 64));
        if isempty(values)
            continue;
        end
        hashes = [hashes; values(:)]; %#ok<AGROW>
        sources(end+1,1) = rel; %#ok<AGROW>
    catch
        % A malformed evidence table is handled by the downstream truth
        % contract. It cannot be used as configuration authority here.
    end
end
hashes = unique(hashes);
if numel(hashes) > 1
    error("sixgr:truth:recover:ConflictingRuntimeConfigHashes", ...
        "Persisted runtime evidence contains multiple ConfigHash values: %s", ...
        char(strjoin(hashes, ", ")));
end
if isempty(hashes)
    hash = "";
else
    hash = hashes(1);
end
end

function files = localStoredSourceFiles(runFolder)
files = strings(0,1);
path = fullfile(runFolder, "meta", "scenario_source_chain.csv");
if exist(path, "file") ~= 2
    return;
end
try
    T = readtable(path, "VariableNamingRule", "preserve");
    if ismember("SourceConfigFile", string(T.Properties.VariableNames))
        files = string(T.SourceConfigFile(:));
        files = files(strlength(strtrim(files)) > 0);
    end
catch
end
end

function meta = localStoredMetadata(runFolder)
meta = struct("ConfigHash", "", "ConfigPath", "");
path = fullfile(runFolder, "meta", "scenario_manifest.json");
if exist(path, "file") ~= 2
    return;
end
try
    raw = jsondecode(fileread(path));
    meta.ConfigHash = string(sixgr.util.structGet(raw, "ConfigHash", ""));
    meta.ConfigPath = string(sixgr.util.structGet(raw, "ConfigPath", ""));
catch
end
end

function hash = localContentHash(data)
bytes = uint8(unicode2native(char(jsonencode(data)), "UTF-8"));
hash = lower(string(sixgr.util.sha256Hex(bytes)));
end

function hash = localFileSHA256(path)
fid = fopen(path, "r");
if fid < 0
    error("sixgr:truth:recover:ResolvedConfigSnapshotUnreadable", ...
        "Cannot open resolved configuration snapshot %s.", path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
hash = lower(string(sixgr.util.sha256Hex(fread(fid, Inf, "*uint8"))));
end

function value = localValidHash(value)
value = lower(strtrim(string(value)));
if ~isscalar(value) || strlength(value) ~= 64
    value = "";
end
end

function value = localFirstNonEmpty(varargin)
value = "";
for i = 1:nargin
    candidate = string(varargin{i});
    candidate = candidate(~ismissing(candidate));
    candidate = strtrim(candidate);
    candidate = candidate(strlength(candidate) > 0);
    if ~isempty(candidate)
        value = candidate(1);
        return;
    end
end
end
