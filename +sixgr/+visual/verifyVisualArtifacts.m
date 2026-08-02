function T = verifyVisualArtifacts(runFolder, plotManifest)
%VERIFYVISUALARTIFACTS Verify visual artifact extension, bytes, and stale state.

if nargin < 2 || isempty(plotManifest)
    plotManifest = table();
end
runFolder = string(runFolder);
rows = repmat(localEmptyRow(), 0, 1);
seen = strings(0, 1);

if istable(plotManifest) && ~isempty(plotManifest)
    for i = 1:height(plotManifest)
        relPath = string(plotManifest.ImagePath(i));
        absPath = fullfile(runFolder, relPath);
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

files = localVisualFiles(runFolder);
for i = 1:numel(files)
    absPath = string(files(i));
    if any(strcmp(seen, absPath))
        continue;
    end
    relPath = localRelativePath(runFolder, absPath);
    row = localBuildRow(absPath, relPath, false);
    row = localApplyFileRules(row);
    rows(end + 1, 1) = row; %#ok<AGROW>
end

if isempty(rows)
    T = struct2table(localEmptyRow());
    T(1, :) = [];
else
    T = struct2table(rows);
end
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
    if ~endsWith(lower(string(row.ArtifactPath)), "_unavailable.png")
        row = localFail(row, "bad_unavailable_card_name", "Unavailable visual cards must end with _unavailable.png.");
    elseif row.ActualMimeType ~= "image/png"
        row = localFail(row, "unavailable_card_mime_mismatch", "Unavailable visual card is not a valid PNG image.");
    elseif row.IntegrityOk
        row.FailureCode = "";
        row.FailureReason = "";
    end
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
elseif endsWith(lower(string(row.ArtifactPath)), "_unavailable.png") && row.ActualMimeType ~= "image/png"
    row = localFail(row, "unavailable_card_mime_mismatch", "Unavailable visual card is not a valid PNG image.");
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
layout = sixgr.report.resultLayout(runFolder);
dirs = strings(0, 1);
names = fieldnames(layout);
for i = 1:numel(names)
    if endsWith(string(names{i}), "ImageDir")
        dirs(end + 1, 1) = string(layout.(names{i})); %#ok<AGROW>
    end
end
dirs(end + 1, 1) = string(layout.PlotsDir);
files = strings(0, 1);
for i = 1:numel(dirs)
    if exist(dirs(i), "dir") ~= 7
        continue;
    end
    listing = dir(fullfile(dirs(i), "**", "*.*"));
    for j = 1:numel(listing)
        if listing(j).isdir
            continue;
        end
        [~, ~, ext] = fileparts(listing(j).name);
        if any(lower(string(ext)) == [".png",".svg",".jpg",".jpeg"])
            files(end + 1, 1) = string(fullfile(listing(j).folder, listing(j).name)); %#ok<AGROW>
        end
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
    if candidate ~= string(absPath) && exist(candidate, "file") == 2
        files(end + 1, 1) = candidate; %#ok<AGROW>
    end
end
end
