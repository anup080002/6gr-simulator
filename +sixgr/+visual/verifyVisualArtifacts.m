function T = verifyVisualArtifacts(runFolder, plotManifest)
%VERIFYVISUALARTIFACTS Verify visual artifact extension, bytes, and stale state.

if nargin < 2 || isempty(plotManifest)
    plotManifest = table();
end
runFolder = sixgr.util.canonicalPath(runFolder);
rows = repmat(localEmptyRow(), 0, 1);
seen = strings(0, 1);

if istable(plotManifest) && ~isempty(plotManifest)
    for i = 1:height(plotManifest)
        relPath = string(plotManifest.ImagePath(i));
        absPath = fullfile(runFolder, relPath);
        if sixgr.runtime.isNestedExecutionPath(runFolder, absPath)
            row = localBuildRow(absPath, relPath, true);
            row.PlotId = string(plotManifest.PlotId(i));
            row = localFail(row, "nested_execution_artifact_not_owned", ...
                "A parent execution cannot claim a child sweep artifact in its plot manifest.");
            rows(end + 1, 1) = row; %#ok<AGROW>
            seen(end + 1, 1) = string(absPath); %#ok<AGROW>
            continue;
        end
        row = localBuildRow(absPath, relPath, true);
        row.PlotId = string(plotManifest.PlotId(i));
        row.PlotRenderStatus = string(plotManifest.PlotRenderStatus(i));
        row.VisualValidity = string(plotManifest.VisualValidity(i));
        row.IsUnavailableCard = logical(plotManifest.IsUnavailableCard(i));
        row.DeclaredMimeType = localDeclaredFromManifest(plotManifest, i, row.DeclaredMimeType);
        row = localApplyManifestRules(row);
        rows(end + 1, 1) = row; %#ok<AGROW>
        seen(end + 1, 1) = string(absPath); %#ok<AGROW>
        staleSiblings = localStaleNormalSiblings(absPath, row.IsUnavailableCard);
        for j = 1:numel(staleSiblings)
            staleRelPath = localRelativePath(runFolder, staleSiblings(j));
            staleRow = localBuildRow(staleSiblings(j), staleRelPath, false);
            staleRow.PlotId = row.PlotId;
            staleRow.PlotRenderStatus = row.PlotRenderStatus;
            staleRow.VisualValidity = "invalid_stale";
            staleRow = localFail(staleRow, "stale_suppressed_normal_artifact", ...
                "Manifest points to an unavailable/suppressed card but a normal visual artifact still exists.");
            rows(end + 1, 1) = staleRow; %#ok<AGROW>
            seen(end + 1, 1) = string(staleSiblings(j)); %#ok<AGROW>
        end
    end
end

[componentRows, componentSeen] = localComponentLineageRows(runFolder, seen);
if ~isempty(componentRows)
    rows = [rows; componentRows(:)]; %#ok<AGROW>
    seen = [seen; componentSeen(:)]; %#ok<AGROW>
end
[mirrorRows, mirrorSeen] = localComponentMirrorRows(runFolder, seen);
if ~isempty(mirrorRows)
    rows = [rows; mirrorRows(:)]; %#ok<AGROW>
    seen = [seen; mirrorSeen(:)]; %#ok<AGROW>
end

files = localVisualFiles(runFolder);
for i = 1:numel(files)
    absPath = string(files(i));
    if any(strcmp(seen, absPath))
        continue;
    end
    relPath = localRelativePath(runFolder, absPath);
    row = localBuildRow(absPath, relPath, false);
    row = localApplyFileRules(row);
    if row.IntegrityOk
        row = localFail(row, "unmanifested_visual_artifact", ...
            "Every persisted PNG or JPEG must have canonical or component plot lineage with exact source CSV evidence.");
    end
    rows(end + 1, 1) = row; %#ok<AGROW>
end

if isempty(rows)
    T = struct2table(localEmptyRow());
    T(1, :) = [];
else
    T = struct2table(rows);
end
end


function [rows, seen] = localComponentLineageRows(runFolder, alreadySeen)
rows = repmat(localEmptyRow(), 0, 1);
seen = strings(0, 1);
files = dir(fullfile(runFolder, "**", "*plot_lineage.csv"));
for f = 1:numel(files)
    lineagePath = fullfile(files(f).folder, files(f).name);
    if sixgr.runtime.isNestedExecutionPath(runFolder, lineagePath)
        continue;
    end
    try
        T = readtable(lineagePath, "VariableNamingRule", "preserve", "TextType", "string");
    catch
        continue;
    end
    imageColumn = localFirstColumn(T, ["ImagePath","PlotFile","ArtifactPath"]);
    sourceColumn = localFirstColumn(T, ["SourceCSV","source_csv"]);
    if strlength(imageColumn) == 0
        continue;
    end
    for i = 1:height(T)
        relPath = localNormalizeLineageArtifactPath( ...
            T.(imageColumn)(i), runFolder, lineagePath);
        if strlength(relPath) == 0
            continue;
        end
        absPath = fullfile(runFolder, strrep(char(relPath), "/", filesep));
        if any(strcmp(alreadySeen, string(absPath))) || any(strcmp(seen, string(absPath)))
            continue;
        end
        row = localBuildRow(absPath, relPath, true);
        row.PlotId = localTableString(T, "PlotId", i, erase(files(f).name, ".csv"));
        lineageStatus = lower(strtrim(localTableString(T, "Status", i, ...
            localTableString(T, "LineageStatus", i, "not_evaluated"))));
        explicitlyNotRendered = any(lineageStatus == ...
            ["incomplete","not_evaluated","not_rendered","suppressed"]);
        if explicitlyNotRendered
            row.PlotRenderStatus = "not_rendered";
        else
            row.PlotRenderStatus = localTableString(T, "Status", i, ...
                localTableString(T, "LineageStatus", i, "rendered_component_plot"));
        end
        row.VisualValidity = "component_runtime_evidence";
        if explicitlyNotRendered
            if row.ByteCount > 0
                row = localFail(row, "stale_suppressed_normal_artifact", ...
                    "Component lineage says the plot was not rendered, but image bytes still exist.");
            else
                row.IntegrityOk = true;
                row.FailureCode = "";
                row.FailureReason = "";
            end
            rows(end + 1, 1) = row; %#ok<AGROW>
            seen(end + 1, 1) = string(absPath); %#ok<AGROW>
            continue;
        end
        row = localApplyFileRules(row);
        if strlength(sourceColumn) == 0
            row = localFail(row, "manifest_source_csv_missing", ...
                "Component plot lineage does not identify a source CSV.");
        else
            sourceSpec = string(T.(sourceColumn)(i));
            [sourceExists, actualSourceHashes] = localSourceSpecEvidence( ...
                runFolder, sourceSpec, lineagePath);
            if ~sourceExists
                row = localFail(row, "source_csv_missing", ...
                    "One or more component plot source CSV files are missing.");
            else
                expectedSourceHashes = lower(strtrim(localTableString(T, ...
                    "SourceCSV_SHA256", i, "")));
                if strlength(expectedSourceHashes) > 0 && ...
                        lower(actualSourceHashes) ~= expectedSourceHashes
                    row = localFail(row, "component_plot_source_hash_mismatch", ...
                        "Component plot source CSV bytes do not match the lineage hash.");
                end
            end
        end
        if ~any(lineageStatus == ["pass","complete","rendered","rendered_component_plot"])
            row = localFail(row, "component_plot_lineage_failed", ...
                "Component plot lineage status is not successful: " + lineageStatus);
        end
        expectedHash = lower(strtrim(localTableString(T, "ImageSHA256", i, ...
            localTableString(T, "PNG_SHA256", i, ""))));
        if strlength(expectedHash) > 0 && lower(string(row.SHA256)) ~= expectedHash
            row = localFail(row, "component_plot_hash_mismatch", ...
                "Component plot bytes do not match the lineage hash.");
        end
        rows(end + 1, 1) = row; %#ok<AGROW>
        seen(end + 1, 1) = string(absPath); %#ok<AGROW>
    end
end
end

function [rows, seen] = localComponentMirrorRows(runFolder, lineagedPaths)
% Component views are byte-identical mirrors, not independently rendered
% plots. Accept one only when its canonical image was already admitted by
% canonical/component plot lineage and both sides match the publisher's
% recorded hashes.
rows = repmat(localEmptyRow(), 0, 1);
seen = strings(0, 1);
manifestPath = fullfile(runFolder, "reports", "csv", ...
    "component_artifact_publication_manifest.csv");
if exist(manifestPath, "file") ~= 2
    return;
end
try
    T = readtable(manifestPath, "VariableNamingRule", "preserve", ...
        "TextType", "string");
catch
    return;
end
required = ["ArtifactType", "CanonicalRelativePath", ...
    "PublishedRelativePath", "CanonicalSHA256", "PublishedSHA256", ...
    "PublishStatus"];
if ~all(ismember(required, string(T.Properties.VariableNames)))
    return;
end
lineagedCanonical = strings(numel(lineagedPaths), 1);
for i = 1:numel(lineagedPaths)
    lineagedCanonical(i) = localCanonicalPath(lineagedPaths(i));
end
for i = 1:height(T)
    if lower(strtrim(string(T.ArtifactType(i)))) ~= "image"
        continue;
    end
    canonicalRel = replace(strtrim(string(T.CanonicalRelativePath(i))), "\", "/");
    publishedRel = replace(strtrim(string(T.PublishedRelativePath(i))), "\", "/");
    canonicalAbs = localCanonicalPath(fullfile(runFolder, ...
        strrep(char(canonicalRel), "/", filesep)));
    publishedAbs = localCanonicalPath(fullfile(runFolder, ...
        strrep(char(publishedRel), "/", filesep)));
    if any(strcmpi(seen, publishedAbs))
        continue;
    end
    row = localBuildRow(publishedAbs, publishedRel, true);
    row.PlotId = "component_mirror__" + string(i);
    row.PlotRenderStatus = "published_hash_verified_mirror";
    row.VisualValidity = "byte_identical_lineaged_component_mirror";
    row = localApplyFileRules(row);
    if ~any(strcmpi(lineagedCanonical, canonicalAbs))
        row = localFail(row, "component_mirror_source_not_lineaged", ...
            "The canonical image behind this component mirror has no accepted plot lineage.");
    elseif ~localFileExists(canonicalAbs)
        row = localFail(row, "component_mirror_source_missing", ...
            "The canonical image behind this component mirror is missing.");
    else
        canonicalHash = lower(localFileSHA256(canonicalAbs));
        publishedHash = lower(localFileSHA256(publishedAbs));
        expectedCanonical = lower(strtrim(string(T.CanonicalSHA256(i))));
        expectedPublished = lower(strtrim(string(T.PublishedSHA256(i))));
        if string(T.PublishStatus(i)) ~= "PUBLISHED_HASH_VERIFIED" || ...
                strlength(expectedCanonical) ~= 64 || ...
                strlength(expectedPublished) ~= 64 || ...
                canonicalHash ~= expectedCanonical || ...
                publishedHash ~= expectedPublished || ...
                canonicalHash ~= publishedHash
            row = localFail(row, "component_mirror_hash_mismatch", ...
                "Component mirror bytes do not exactly match the lineaged canonical image and publisher hashes.");
        end
    end
    rows(end + 1, 1) = row; %#ok<AGROW>
    seen(end + 1, 1) = publishedAbs; %#ok<AGROW>
end
end

function name = localFirstColumn(T, candidates)
name = "";
names = string(T.Properties.VariableNames);
for candidate = string(candidates(:)).'
    idx = find(strcmpi(names, candidate), 1, "first");
    if ~isempty(idx)
        name = names(idx);
        return;
    end
end
end

function value = localTableString(T, name, row, fallback)
value = string(fallback);
idx = find(strcmpi(string(T.Properties.VariableNames), string(name)), 1, "first");
if isempty(idx)
    return;
end
candidate = string(T.(T.Properties.VariableNames{idx})(row));
if strlength(strtrim(candidate)) > 0
    value = candidate;
end
end

function rel = localNormalizeLineageArtifactPath(pathValue, runFolder, lineagePath)
pathValue = strtrim(string(pathValue));
if localLooksAbsolute(pathValue)
    canonicalPath = localCanonicalPath(pathValue);
    canonicalRoot = localCanonicalPath(runFolder);
    if canonicalPath == canonicalRoot || ...
            startsWith(canonicalPath, canonicalRoot + string(filesep), "IgnoreCase", ispc)
        rel = localRelativePath(canonicalRoot, canonicalPath);
    else
        rel = "";
    end
else
    resolved = localResolveOwnedRelativePath(runFolder, lineagePath, pathValue);
    if strlength(resolved) == 0
        rel = replace(pathValue, "\", "/");
        while startsWith(rel, "./")
            rel = extractAfter(rel, 2);
        end
    else
        rel = localRelativePath(runFolder, resolved);
    end
end
end

function [tf, hashes] = localSourceSpecEvidence(runFolder, sourceSpec, lineagePath)
parts = split(strtrim(string(sourceSpec)), "|");
parts = strtrim(parts(:));
parts = parts(strlength(parts) > 0);
tf = ~isempty(parts);
hashValues = strings(numel(parts), 1);
for i = 1:numel(parts)
    part = parts(i);
    if localLooksAbsolute(part)
        canonicalPart = localCanonicalPath(part);
        canonicalRoot = localCanonicalPath(runFolder);
        if canonicalPart ~= canonicalRoot && ...
                ~startsWith(canonicalPart, canonicalRoot + string(filesep), ...
                    "IgnoreCase", ispc)
            tf = false;
            continue;
        end
        pathValue = char(canonicalPart);
    else
        pathValue = localResolveOwnedRelativePath(runFolder, lineagePath, part);
    end
    existsOne = localFileExists(pathValue);
    tf = tf && existsOne;
    if existsOne
        hashValues(i) = localFileSHA256(pathValue);
    end
end
hashes = strjoin(hashValues, "|");
end

function resolved = localResolveOwnedRelativePath(runFolder, lineagePath, relativePath)
% Resolve a component lineage path against the component that owns the
% lineage file.  Component exporters intentionally use paths relative to
% their own output root (for example reports/figures/foo.png).  Treating
% every such value as run-root-relative aliases unrelated component files
% or reports valid evidence as missing.
resolved = "";
portable = replace(strtrim(string(relativePath)), "\", "/");
while startsWith(portable, "./")
    portable = extractAfter(portable, 2);
end
segments = split(portable, "/");
if strlength(portable) == 0 || any(segments == "..")
    return;
end
canonicalRoot = localCanonicalPath(runFolder);
cursor = localCanonicalPath(fileparts(char(string(lineagePath))));
while cursor == canonicalRoot || startsWith(cursor, ...
        canonicalRoot + string(filesep), "IgnoreCase", ispc)
    candidate = localCanonicalPath(fullfile(cursor, ...
        strrep(char(portable), "/", filesep)));
    if (candidate == canonicalRoot || startsWith(candidate, ...
            canonicalRoot + string(filesep), "IgnoreCase", ispc)) && ...
            localFileExists(candidate)
        resolved = candidate;
        return;
    end
    if cursor == canonicalRoot
        break;
    end
    parent = localCanonicalPath(fileparts(char(cursor)));
    if parent == cursor
        break;
    end
    cursor = parent;
end
end

function tf = localLooksAbsolute(pathValue)
pathValue = char(string(pathValue));
tf = ~isempty(regexp(pathValue, '^[A-Za-z]:[\\/]', 'once')) || ...
    startsWith(string(pathValue), "\\\\") || startsWith(string(pathValue), "/");
end

function value = localCanonicalPath(pathValue)
value = sixgr.util.canonicalPath(pathValue);
end

function hash = localFileSHA256(pathValue)
hash = "";
if ~localFileExists(pathValue)
    return;
end
fid = fopen(sixgr.util.ioPath(pathValue), "r");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, inf, "*uint8");
hash = string(sixgr.util.sha256Hex(uint8(bytes(:))));
end

function tf = localFileExists(pathValue)
tf = exist(sixgr.util.ioPath(pathValue), "file") == 2;
end

function row = localEmptyRow()
row = struct( ...
    "PlotId", "", ...
    "ArtifactPath", "", ...
    "IsManifestRow", false, ...
    "PlotRenderStatus", "", ...
    "VisualValidity", "", ...
    "IsUnavailableCard", false, ...
    "DeclaredMimeType", "", ...
    "ActualMimeType", "", ...
    "Extension", "", ...
    "SHA256", "", ...
    "ByteCount", 0, ...
    "IntegrityOk", true, ...
    "FailureCode", "", ...
    "FailureReason", "");
end

function row = localBuildRow(absPath, relPath, isManifestRow)
info = sixgr.visual.inspectVisualArtifactFile(absPath);
row = localEmptyRow();
row.ArtifactPath = string(relPath);
row.IsManifestRow = logical(isManifestRow);
row.DeclaredMimeType = string(info.declared_mime_type);
row.ActualMimeType = string(info.actual_mime_type);
row.Extension = string(info.extension);
row.SHA256 = string(info.sha256);
row.ByteCount = double(info.byte_count);
row.IntegrityOk = logical(info.extension_mime_match);
row.FailureCode = string(info.signature_status);
row.FailureReason = string(info.reason);
if ~logical(info.exists)
    row.IntegrityOk = false;
end
end

function row = localApplyManifestRules(row)
status = lower(strtrim(string(row.PlotRenderStatus)));
isSuppressed = any(status == ["suppressed","source_csv_missing","not_rendered","invalid_stale_artifact"]) || contains(status, "suppressed");
if lower(string(row.Extension)) == ".svg" || lower(string(row.ActualMimeType)) == "image/svg+xml"
    row = localFail(row, "vector_visual_format_forbidden", ...
        "Persisted visual artifacts must use PNG or JPEG; SVG is read-only legacy input.");
elseif row.IsUnavailableCard
    row = localFail(row, "unavailable_raster_forbidden", ...
        "Unavailable measurements must be recorded as suppressed CSV status rows, not raster cards.");
elseif isSuppressed && row.ByteCount > 0
    row = localFail(row, "stale_suppressed_normal_artifact", "Manifest says this plot is suppressed/not rendered but a normal visual file exists.");
elseif isSuppressed
    row.IntegrityOk = true;
    row.FailureCode = "";
    row.FailureReason = "";
elseif ~row.IntegrityOk
    row = localFail(row, string(row.FailureCode), string(row.FailureReason));
end
end

function row = localApplyFileRules(row)
if lower(string(row.Extension)) == ".svg" || lower(string(row.ActualMimeType)) == "image/svg+xml"
    row = localFail(row, "vector_visual_format_forbidden", ...
        "Persisted visual artifacts must use PNG or JPEG; SVG is read-only legacy input.");
elseif ~row.IntegrityOk
    row = localFail(row, string(row.FailureCode), string(row.FailureReason));
elseif endsWith(lower(string(row.ArtifactPath)), "_unavailable.png")
    row = localFail(row, "unavailable_raster_forbidden", ...
        "Unavailable measurements must not be persisted as raster cards.");
end
end

function row = localFail(row, code, reason)
row.IntegrityOk = false;
row.FailureCode = string(code);
row.FailureReason = string(reason);
end

function mime = localDeclaredFromManifest(T, idx, fallback)
mime = string(fallback);
if ismember("declared_mime_type", string(T.Properties.VariableNames))
    candidate = string(T.declared_mime_type(idx));
elseif ismember("DeclaredMimeType", string(T.Properties.VariableNames))
    candidate = string(T.DeclaredMimeType(idx));
else
    candidate = "";
end
if strlength(strtrim(candidate)) > 0
    mime = candidate;
end
end

function files = localVisualFiles(runFolder)
files = strings(0, 1);
listing = dir(fullfile(string(runFolder), "**", "*.*"));
for j = 1:numel(listing)
    if listing(j).isdir
        continue;
    end
    candidatePath = string(fullfile(listing(j).folder, listing(j).name));
    if sixgr.runtime.isNestedExecutionPath(runFolder, candidatePath)
        continue;
    end
    [~, ~, ext] = fileparts(listing(j).name);
    if any(lower(string(ext)) == [".png",".svg",".jpg",".jpeg"])
        files(end + 1, 1) = candidatePath; %#ok<AGROW>
    end
end
files = unique(files, "stable");
end

function rel = localRelativePath(root, absPath)
root = string(root);
absPath = string(absPath);
prefix = root + string(filesep);
if startsWith(absPath, prefix)
    rel = extractAfter(absPath, strlength(prefix));
else
    rel = absPath;
end
rel = replace(rel, filesep, "/");
end

function files = localStaleNormalSiblings(absPath, isUnavailableCard)
files = strings(0, 1);
if ~logical(isUnavailableCard)
    return;
end
[folder, name] = fileparts(char(string(absPath)));
name = regexprep(string(name), "_unavailable$", "");
for ext = [".png",".svg",".jpg",".jpeg"]
    candidate = string(fullfile(folder, name + ext));
    if candidate ~= string(absPath) && localFileExists(candidate)
        files(end + 1, 1) = candidate; %#ok<AGROW>
    end
end
end
