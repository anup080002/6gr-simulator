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
% Receiver channel resources are immutable measured complex samples. Their
% exact CSV bytes are hashed in the primary trial at capture time; adding
% identity columns here invalidates that hash and can round numeric values.
immutableRoots = ["runtime", "raw", "channel_estimation", componentMirrorRoots];
immutableFiles = ["control/csv/pdcch_channel_estimates.csv", ...
    "control/csv/pdcch_channel_estimate_plot_lineage.csv"];
annotationChanges = containers.Map('KeyType','char','ValueType','any');

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
    [~, fileStem, ~] = fileparts(char(pathValue));
    browserOwned = startsWith(lower(string(fileStem)),"contract__") || ...
        strcmpi(fileStem,"contract_plot_lineage");
    % Only the browser producer may write its rendered chart datasets and
    % exact lineage. Late generic annotations would invalidate those bytes.
    if any(lower(topLevel) == lower(immutableRoots)) || ...
            any(lower(relativePath) == immutableFiles) || browserOwned || ...
            startsWith(lower(relativePath),"reports/live_measurements/")
        summary.SkippedImmutableCount = summary.SkippedImmutableCount + 1;
        continue;
    end

    try
        tableValue = sixgr.util.csvReadTable(pathValue,'TextType','string');
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
        beforeHash = localFileSHA256(pathValue);
        sixgr.util.csvWriteTable(pathValue, tableValue, ...
            'PreserveSchema',true,'RoundTripNumericText',true);
        annotationChanges(localPathKey(pathValue)) = struct( ...
            'Before',beforeHash,'After',localFileSHA256(pathValue));
        summary.AnnotatedCount = summary.AnnotatedCount + 1;
    end
end
summary.RefreshedLineageCount = localRefreshLineageHashes(runFolder,annotationChanges);
end

function values = localConstantColumn(rowCount, value)
values = repmat(string(value), rowCount, 1);
end

function refreshed = localRefreshLineageHashes(runFolder,annotationChanges)
% CSV identity annotation is an intentional final byte mutation.  Refresh
% cryptographic lineage only after every mutable report CSV has reached its
% final schema; image bytes and scientific values are not changed here.
% Never repair an unrelated stale/corrupt source by blessing its new hash.
% The previously recorded hash must match the bytes observed immediately
% before this function's own annotation, and no intervening write may occur.
refreshed = 0;
files = dir(fullfile(runFolder, "**", "*plot_lineage.csv"));
for fileIndex = 1:numel(files)
    lineagePath = string(fullfile(files(fileIndex).folder, files(fileIndex).name));
    if sixgr.runtime.isNestedExecutionPath(runFolder, lineagePath) || ...
            strcmpi(files(fileIndex).name,"contract_plot_lineage.csv") || ...
            contains(lower(replace(lineagePath,"\","/")),"/reports/live_measurements/")
        continue;
    end
    try
        T = sixgr.util.csvReadTable(lineagePath, "TextType", "string");
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
        [existsOk, hashes, previousHashes] = localSourceHashes(runFolder, lineagePath, ...
            T.(char(sourceName))(rowIndex),annotationChanges);
        if existsOk && string(T.(char(hashName))(rowIndex)) == previousHashes && ...
                string(T.(char(hashName))(rowIndex)) ~= hashes
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

function [ok, hashes, previousHashes] = localSourceHashes(runFolder, lineagePath, sourceSpec,annotationChanges)
parts = split(strtrim(string(sourceSpec)), "|");
parts = strtrim(parts(:));
parts = parts(~ismissing(parts) & strlength(parts) > 0);
ok = ~isempty(parts);
values = strings(numel(parts), 1);
previousValues = strings(numel(parts), 1);
for index = 1:numel(parts)
    sourcePath = localResolveOwnedPath(runFolder, lineagePath, parts(index));
    existsOne = strlength(sourcePath) > 0 && exist(sourcePath, "file") == 2;
    ok = ok && existsOne;
    if existsOne
        values(index) = localFileSHA256(sourcePath);
        previousValues(index) = values(index);
        key = localPathKey(sourcePath);
        if isKey(annotationChanges,key)
            change = annotationChanges(key);
            ok = ok && values(index) == change.After;
            previousValues(index) = change.Before;
        end
    end
end
hashes = strjoin(values, "|");
previousHashes = strjoin(previousValues, "|");
end

function key = localPathKey(pathValue)
key = char(java.io.File(char(pathValue)).getCanonicalPath());
if ispc, key = lower(key); end
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
