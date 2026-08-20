function [runTag, evidence] = resolvePersistedLLSRunTag(runFolder)
%RESOLVEPERSISTEDLLSRUNTAG Resolve logical RunTag from immutable evidence.
%
% A recovery/publication directory is a storage location, not a run
% identity. Prefer the lifecycle identity persisted on primary PHY trial
% rows, then an explicit metadata RunTag, and use a stored folder leaf only
% as a legacy last resort. Conflicting primary identities fail closed.

arguments
    runFolder (1,1) string
end

runFolder = strtrim(runFolder);
if strlength(runFolder) == 0 || exist(runFolder, "dir") ~= 7
    error("sixgr:truth:recover:RunFolderUnavailable", ...
        "Persisted RunTag resolution requires an existing run folder.");
end

relativePaths = [ ...
    "air_interface/csv/dl_fixed_link_campaign_trials.csv"; ...
    "air_interface/csv/ul_fixed_link_campaign_trials.csv"; ...
    "air_interface/csv/dl_pdsch_trials.csv"; ...
    "air_interface/csv/ul_pusch_trials.csv"; ...
    "air_interface/csv/prach_trials.csv"];
observed = strings(0,1);
sources = strings(0,1);
for relativePath = relativePaths.'
    source = fullfile(runFolder, replace(relativePath, "/", filesep));
    if exist(source, "file") ~= 2
        continue;
    end
    [values, columns] = localReadIdentityColumns(source);
    if isempty(values)
        continue;
    end
    observed = [observed; values(:)]; %#ok<AGROW>
    sources = [sources; relativePath + ":" + columns(:)]; %#ok<AGROW>
end

primary = unique(observed, "stable");
if numel(primary) > 1
    error("sixgr:truth:recover:PersistedRunTagIdentityMismatch", ...
        "Primary runtime evidence contains conflicting logical RunIDs: %s.", ...
        strjoin(primary, ", "));
end

[metadataTag, metadataSource, folderFallback] = localReadMetadata(runFolder);
if numel(primary) == 1
    runTag = primary(1);
    if strlength(metadataTag) > 0 && metadataTag ~= runTag
        error("sixgr:truth:recover:PersistedRunTagIdentityMismatch", ...
            ["Explicit metadata RunTag '%s' conflicts with primary " ...
            "runtime RunID '%s'."], metadataTag, runTag);
    end
    authority = "primary_trial_tables";
    sourceList = unique(sources, "stable");
elseif strlength(metadataTag) > 0
    runTag = metadataTag;
    authority = "explicit_metadata_run_tag";
    sourceList = metadataSource;
elseif strlength(folderFallback) > 0
    runTag = folderFallback;
    authority = "legacy_stored_run_folder_leaf";
    sourceList = "meta_stored_run_folder";
else
    runTag = localFolderLeaf(runFolder);
    authority = "legacy_current_run_folder_leaf";
    sourceList = "current_run_folder";
end

runTag = strtrim(string(runTag));
evidence = struct( ...
    "RunTag", runTag, ...
    "Authority", authority, ...
    "Sources", sourceList(:), ...
    "PrimaryIdentityCount", double(numel(primary)), ...
    "PrimaryIdentities", primary(:), ...
    "CurrentFolderLeaf", localFolderLeaf(runFolder));
end

function [values, columns] = localReadIdentityColumns(pathValue)
values = strings(0,1);
columns = strings(0,1);
try
    opts = detectImportOptions(pathValue, ...
        "FileType", "text", "Delimiter", ",", ...
        "VariableNamingRule", "preserve");
    names = string(opts.VariableNames);
    candidates = ["RunID","RunId","RunTag","run_tag"];
    selected = names(ismember(lower(names), lower(candidates)));
    if isempty(selected)
        return;
    end
    opts.SelectedVariableNames = cellstr(selected);
    T = readtable(pathValue, opts);
    for name = selected
        raw = strtrim(string(T.(char(name))));
        raw = raw(~ismissing(raw) & strlength(raw) > 0 & lower(raw) ~= "nan");
        uniqueValues = unique(raw, "stable");
        if numel(uniqueValues) > 1
            error("sixgr:truth:recover:PersistedRunTagIdentityMismatch", ...
                "Persisted table %s contains multiple %s values: %s.", ...
                pathValue, name, strjoin(uniqueValues, ", "));
        end
        if numel(uniqueValues) == 1
            values(end+1,1) = uniqueValues(1); %#ok<AGROW>
            columns(end+1,1) = name; %#ok<AGROW>
        end
    end
catch ME
    if startsWith(string(ME.identifier), ...
            "sixgr:truth:recover:PersistedRunTagIdentityMismatch")
        rethrow(ME);
    end
    error("sixgr:truth:recover:PersistedRunTagUnreadable", ...
        "Could not read persisted RunTag identity from %s: %s", ...
        pathValue, ME.message);
end
end

function [runTag, source, folderFallback] = localReadMetadata(runFolder)
runTag = "";
source = "";
folderFallback = "";
paths = [ ...
    fullfile(runFolder, "meta", "scenario_manifest.json"); ...
    fullfile(runFolder, "meta", "runtime_summary.json")];
for pathValue = paths.'
    if exist(pathValue, "file") ~= 2
        continue;
    end
    try
        value = jsondecode(fileread(pathValue));
        explicit = localFirstNonEmpty( ...
            sixgr.util.structGet(value, "RunTag", ""), ...
            sixgr.util.structGet(value, "run_tag", ""), ...
            sixgr.util.structGet(value, "RunID", ""), ...
            sixgr.util.structGet(value, "RunId", ""));
        if strlength(explicit) > 0
            if strlength(runTag) > 0 && runTag ~= explicit
                error("sixgr:truth:recover:PersistedRunTagIdentityMismatch", ...
                    "Metadata contains conflicting explicit RunTags '%s' and '%s'.", ...
                    runTag, explicit);
            end
            runTag = explicit;
            source = string(pathValue);
        end
        folderFallback = localFirstNonEmpty(folderFallback, ...
            localFolderLeaf(string(sixgr.util.structGet(value, "RunFolder", ""))));
    catch ME
        if startsWith(string(ME.identifier), ...
                "sixgr:truth:recover:PersistedRunTagIdentityMismatch")
            rethrow(ME);
        end
    end
end
end

function value = localFirstNonEmpty(varargin)
value = "";
for index = 1:nargin
    candidate = strtrim(string(varargin{index}));
    candidate = candidate(~ismissing(candidate) & strlength(candidate) > 0);
    if ~isempty(candidate)
        value = candidate(1);
        return;
    end
end
end

function leaf = localFolderLeaf(pathValue)
leaf = "";
pathValue = strtrim(string(pathValue));
if strlength(pathValue) == 0
    return;
end
[~, name, ext] = fileparts(char(pathValue));
leaf = string(name) + string(ext);
end
