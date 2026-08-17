function summary = annotateScenarioCSVArtifacts(runFolder, scenarioID, configHash, runnerProfile)
%ANNOTATESCENARIOCSVARTIFACTS Add scenario identity to mutable report CSVs.
%   Runtime evidence CSVs are append-only, versioned journal projections.
%   Their schemas are owned by RuntimeEvidenceBus and must never be changed
%   by report annotation. Component mirrors are also excluded because they
%   must remain byte-identical to their canonical published artifacts.

runFolder = string(runFolder);
scenarioID = string(scenarioID);
configHash = string(configHash);
runnerProfile = string(runnerProfile);

componentMirrorRoots = ["air_interface","beamforming", ...
    "prach","initial_access","ssb","pdcch", ...
    "pdsch","pusch","pucch","reference_signals","mimo", ...
    "frame_grid","waveform","l3","channel","rf", ...
    "mac_harq_scheduler","l2","traffic","validation", ...
    "component_anchors"];
% raw/ is the cryptographically indexed, immutable execution snapshot.
% Finalization and recovery may annotate derived reports repeatedly, but
% must never rewrite a raw table after raw_evidence_index.csv is sealed.
immutableRoots = ["runtime", "raw", componentMirrorRoots];

summary = struct( ...
    "ScannedCount", 0, ...
    "AnnotatedCount", 0, ...
    "SkippedImmutableCount", 0, ...
    "SkippedNestedExecutionCount", 0, ...
    "UnreadableCount", 0, ...
    "RefreshedLineageCount", 0);

files = dir(fullfile(runFolder, "**", "*.csv"));
normalizedRoot = strip(replace(runFolder, "\", "/"), "right", "/");
for i = 1:numel(files)
    summary.ScannedCount = summary.ScannedCount + 1;
    pathValue = string(fullfile(files(i).folder, files(i).name));
    if sixgr.runtime.isNestedExecutionPath(runFolder, pathValue)
        summary.SkippedNestedExecutionCount = ...
            summary.SkippedNestedExecutionCount + 1;
        continue;
    end
    normalizedFile = replace(pathValue, "\", "/");
    relativePath = normalizedFile;
    if startsWith(lower(normalizedFile), lower(normalizedRoot + "/"))
        relativePath = extractAfter(normalizedFile, strlength(normalizedRoot) + 1);
    end
    topLevel = extractBefore(relativePath + "/", "/");
    if any(lower(topLevel) == lower(immutableRoots))
        summary.SkippedImmutableCount = summary.SkippedImmutableCount + 1;
        continue;
    end

    try
        tableValue = readtable(pathValue, 'Delimiter', ',', ...
            'ReadVariableNames', true, 'VariableNamingRule', 'preserve');
    catch
        summary.UnreadableCount = summary.UnreadableCount + 1;
        continue;
    end

    changed = false;
    variableNames = string(tableValue.Properties.VariableNames);
    if ~any(strcmpi(variableNames, "ScenarioID"))
        tableValue = addvars(tableValue, localConstantColumn(height(tableValue), scenarioID), ...
            'Before', 1, 'NewVariableNames', 'ScenarioID');
        changed = true;
    end
    variableNames = string(tableValue.Properties.VariableNames);
    if ~any(strcmpi(variableNames, "ConfigHash"))
        tableValue = addvars(tableValue, localConstantColumn(height(tableValue), configHash), ...
            'Before', min(2, width(tableValue) + 1), 'NewVariableNames', 'ConfigHash');
        changed = true;
    end
    variableNames = string(tableValue.Properties.VariableNames);
    if ~any(strcmpi(variableNames, "RunnerProfile"))
        tableValue = addvars(tableValue, localConstantColumn(height(tableValue), runnerProfile), ...
            'Before', min(3, width(tableValue) + 1), 'NewVariableNames', 'RunnerProfile');
        changed = true;
    end
    if changed
        sixgr.util.csvWriteTable(pathValue, tableValue);
        summary.AnnotatedCount = summary.AnnotatedCount + 1;
    end
end
summary.RefreshedLineageCount = localRefreshLineageHashes(runFolder);
end

function values = localConstantColumn(rowCount, value)
values = repmat(string(value), rowCount, 1);
end

function refreshed = localRefreshLineageHashes(runFolder)
% CSV identity annotation is an intentional final byte mutation.  Refresh
% cryptographic lineage only after every mutable report CSV has reached its
% final schema; image bytes and scientific values are not changed here.
refreshed = 0;
files = dir(fullfile(runFolder, "**", "*plot_lineage.csv"));
for fileIndex = 1:numel(files)
    lineagePath = string(fullfile(files(fileIndex).folder, files(fileIndex).name));
    if sixgr.runtime.isNestedExecutionPath(runFolder, lineagePath)
        continue;
    end
    try
        T = readtable(lineagePath, "VariableNamingRule", "preserve", ...
            "TextType", "string");
    catch
        continue;
    end
    names = string(T.Properties.VariableNames);
    sourceName = localFirstColumn(names, ["SourceCSV","source_csv"]);
    hashName = localFirstColumn(names, ["SourceCSV_SHA256","source_csv_sha256"]);
    if strlength(sourceName) == 0 || strlength(hashName) == 0
        continue;
    end
    changed = false;
    for rowIndex = 1:height(T)
        [existsOk, hashes] = localSourceHashes(runFolder, lineagePath, ...
            T.(char(sourceName))(rowIndex));
        if existsOk && string(T.(char(hashName))(rowIndex)) ~= hashes
            T.(char(hashName))(rowIndex) = hashes;
            changed = true;
        end
    end
    if changed
        sixgr.util.csvWriteTable(lineagePath, T);
        refreshed = refreshed + 1;
    end
end
end

function name = localFirstColumn(names, candidates)
name = "";
for candidate = string(candidates(:)).'
    index = find(strcmpi(names, candidate), 1, "first");
    if ~isempty(index)
        name = names(index);
        return;
    end
end
end

function [ok, hashes] = localSourceHashes(runFolder, lineagePath, sourceSpec)
parts = split(strtrim(string(sourceSpec)), "|");
parts = strtrim(parts(:));
parts = parts(~ismissing(parts) & strlength(parts) > 0);
ok = ~isempty(parts);
values = strings(numel(parts), 1);
for index = 1:numel(parts)
    sourcePath = localResolveOwnedPath(runFolder, lineagePath, parts(index));
    existsOne = strlength(sourcePath) > 0 && exist(sourcePath, "file") == 2;
    ok = ok && existsOne;
    if existsOne
        values(index) = localFileSHA256(sourcePath);
    end
end
hashes = strjoin(values, "|");
end

function resolved = localResolveOwnedPath(runFolder, lineagePath, relativePath)
resolved = "";
portable = replace(strtrim(string(relativePath)), "\", "/");
while startsWith(portable, "./")
    portable = extractAfter(portable, 2);
end
if strlength(portable) == 0 || any(split(portable, "/") == "..")
    return;
end
root = string(char(java.io.File(char(runFolder)).getCanonicalPath()));
if ~isempty(regexp(char(portable), '^[A-Za-z]:[\\/]', 'once'))
    candidate = string(char(java.io.File(char(portable)).getCanonicalPath()));
    if localInsideRoot(candidate, root) && exist(candidate, "file") == 2
        resolved = candidate;
    end
    return;
end
cursor = string(char(java.io.File(fileparts(char(lineagePath))).getCanonicalPath()));
while localInsideRoot(cursor, root)
    candidate = string(char(java.io.File(fullfile(char(cursor), ...
        strrep(char(portable), "/", filesep))).getCanonicalPath()));
    if localInsideRoot(candidate, root) && exist(candidate, "file") == 2
        resolved = candidate;
        return;
    end
    if strcmpi(cursor, root)
        break;
    end
    parent = string(char(java.io.File(fileparts(char(cursor))).getCanonicalPath()));
    if parent == cursor
        break;
    end
    cursor = parent;
end
end

function tf = localInsideRoot(pathValue, root)
tf = strcmpi(pathValue, root) || startsWith(pathValue, root + string(filesep), ...
    "IgnoreCase", ispc);
end

function hash = localFileSHA256(pathValue)
fid = fopen(pathValue, "r");
if fid < 0
    hash = "";
    return;
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
hash = string(sixgr.util.sha256Hex(fread(fid, inf, "*uint8")));
end
